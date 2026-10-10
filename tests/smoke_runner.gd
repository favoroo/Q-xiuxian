extends Node

## 无头全流程冒烟测试：道统选择→本命法器→战斗→升级→灵韵结算→商店(锁/买/reroll/合成)→新波次敌种
## 运行: godot --headless --path . res://tests/SmokeRunner.tscn

var _c := TestCheck.new()

## 断言实现统一走 tests/check.gd（与 UnitRunner / PoolCheck 同一套判据与输出格式）
func _check(cond: bool, label: String) -> void:
	_c.check(cond, label)

func _dismiss_dialogs() -> void:
	while GameManager.has_pending_upgrades() and not GameManager.alloc_offers.is_empty():
		GameManager.take_alloc_upgrade(0)
	_hide_dialogs()

## 只藏面板、不解点数：验证「升级只攒点不打断战斗」时不能顺手把点数花掉
func _hide_dialogs() -> void:
	for node_name in ["LevelUpDialog", "WaveShop", "PlayerStatsDialog", "PauseMenu", "SettingsDialog"]:
		var n := get_node_or_null("/root/Main/UILayer/" + node_name)
		if n != null and n.visible:
			n.visible = false
	get_tree().paused = false

func _dlg_visible(node_name: String) -> bool:
	var n := get_node_or_null("/root/Main/UILayer/" + node_name)
	return n != null and n.visible

## 边等边清理弹窗（多级连升会连续弹出 LevelUpDialog 并反复暂停）
func _wait_clean(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		await get_tree().create_timer(0.2).timeout
		_dismiss_dialogs()
		left -= 0.2

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	Engine.time_scale = 8.0
	var main = load("res://scenes/main/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	# 1. 道统 + 本命法器（绕过 UI，直接走逻辑层）
	GameManager.cultivator_id = "fuzhen"
	GameManager.start_run("qingyun_sword")
	get_tree().paused = false
	_check(GameManager.run_started, "道统 fuzhen 开局")
	_check(GameManager.drones.size() == 2, "符阵灵童自带 2 灵蝶 (实际 %d)" % GameManager.drones.size())
	var p_frame: Texture2D = GameManager.player.anim_sprite.sprite_frames.get_frame_texture("idle_s", 0)
	var p_atlas_path: String = (p_frame as AtlasTexture).atlas.resource_path if p_frame is AtlasTexture else ""
	_check(p_atlas_path == "res://assets/art/cultivator_fuzhen_8dir.png", "选角后玩家外观切为符阵灵童图集 (实际 %s)" % p_atlas_path)

	# 等第一只敌人刷出（条件达成即走，不再写死 sleep）
	var wait_spawn := 0
	while get_tree().get_nodes_in_group("enemies").is_empty() and wait_spawn < 120:
		await get_tree().physics_frame
		wait_spawn += 1
	_check(GameManager.wave_number == 1, "第 1 波已开启")
	var enemy_count := get_tree().get_nodes_in_group("enemies").size()
	_check(enemy_count > 0, "敌人已刷出 (%d)" % enemy_count)

	# 2. 升级与加点（含新属性）
	GameManager.add_spirit_stones(500)
	for up_id in ["crit_up", "dodge_up", "lifesteal_up", "luck_up", "harvest_up", "range_up"]:
		GameManager.apply_upgrade(up_id)
	_check(GameManager.crit_rate > 0.1, "暴击率加点生效 %.2f" % GameManager.crit_rate)
	_check(GameManager.dodge > 0.05, "身法闪避加点生效")
	_check(GameManager.harvest >= 8.0, "灵韵加点生效")
	var ups := GameManager.roll_upgrades(3)
	_check(ups.size() == 3, "指定 3 项时仍只出 3 项 (得 %d 项)" % ups.size())
	_check(GameManager.roll_upgrades().size() == GameManager.UPGRADE_OFFER_COUNT,
		"默认一次给 %d 个候选" % GameManager.UPGRADE_OFFER_COUNT)

	# 3. 战斗途中升级：只攒点数，不暂停、不当场弹面板（2026-10-09 用户指令的正面判据）
	GameManager.add_experience(50)
	await get_tree().process_frame
	_check(GameManager.level > 1, "修为到账升到 Lv.%d" % GameManager.level)
	_check(GameManager.pending_upgrade_points > 0, "升级攒下待加点 %d 点" % GameManager.pending_upgrade_points)
	_check(GameManager.has_pending_upgrades(), "has_pending_upgrades 与点数同步")
	_check(not _dlg_visible("LevelUpDialog"), "战斗中悟道面板没有抢开")
	_check(not get_tree().paused, "战斗中升级不再暂停游戏")
	_hide_dialogs()

	# 4. 回合结束 → 先清悟道点数 → 才轮到灵石阁（新流程的顺序就是这条判据要钉的东西）
	var spawner: Node = GameManager.wave_spawner
	var stones_before := GameManager.spirit_stones
	var points_before: int = GameManager.pending_upgrade_points
	spawner.end_wave()
	var waited := 0
	while spawner.phase != WaveSpawner.Phase.ALLOC and waited < 40:
		await get_tree().create_timer(0.1).timeout
		waited += 1
	_check(spawner.phase == WaveSpawner.Phase.ALLOC, "清场后先进悟道结算而不是商店（phase=%d）" % spawner.phase)
	_check(_dlg_visible("LevelUpDialog"), "悟道面板已弹出")
	_check(get_tree().paused, "悟道结算期间暂停")
	_check(GameManager.alloc_offers.size() == GameManager.UPGRADE_OFFER_COUNT,
		"悟道候选 %d 个 (实际 %d)" % [GameManager.UPGRADE_OFFER_COUNT, GameManager.alloc_offers.size()])
	_check(GameManager.alloc_points_total == GameManager.pending_upgrade_points,
		"面板记住这一回合攒了几点（%d 点，含灵韵结算那一级）" % GameManager.alloc_points_total)
	_check(GameManager.alloc_points_total >= points_before, "清场前攒的点没被吞掉")
	# 刷新：第一次吃免费额度、不扣灵石；用完才按货架同一档价格扣
	var stones_pre_reroll := GameManager.spirit_stones
	_check(GameManager.alloc_reroll_free_left == GameManager.ALLOC_FREE_REROLLS,
		"开局带 %d 次免费刷新" % GameManager.ALLOC_FREE_REROLLS)
	_check(GameManager.reroll_alloc(), "免费刷新悟道成功")
	_check(GameManager.spirit_stones == stones_pre_reroll, "首次刷新不吃灵石")
	_check(GameManager.alloc_reroll_free_left == 0, "免费额度已用掉")
	_check(GameManager.alloc_reroll_cost == GameBalance.reroll_cost(
		GameManager.wave_number, 0, GameManager.shop_price_mult),
		"免费那一次不把报价抬上去（与货架同一口径：%d）" % GameManager.alloc_reroll_cost)
	var paid_price := GameManager.alloc_reroll_cost
	_check(GameManager.reroll_alloc(), "第二次刷新付灵石")
	_check(GameManager.spirit_stones == stones_pre_reroll - paid_price,
		"付费刷新扣 %d 灵石" % paid_price)
	_check(GameManager.alloc_reroll_cost > paid_price,
		"再刷一档涨价 %d→%d（同货架重掷曲线）" % [paid_price, GameManager.alloc_reroll_cost])
	var lvl_before := GameManager.level
	_dismiss_dialogs()
	_check(GameManager.level == lvl_before, "加完点不再升级（点数与等级两条线不互串）")
	_check(not GameManager.has_pending_upgrades(), "点数已加完")
	_check(spawner.phase == WaveSpawner.Phase.SHOP, "加完点自动进灵石阁")
	_check(GameManager.spirit_stones > stones_before, "灵韵波末结算发灵石 (+%d)" % (GameManager.spirit_stones - stones_before))
	_check(GameManager.shop_offers.size() == GameManager.SHOP_BASE_SLOTS, "商店 %d 货架 (实际 %d)" % [GameManager.SHOP_BASE_SLOTS, GameManager.shop_offers.size()])
	_dismiss_dialogs()

	# 5. 商店护栏：锁定保留 / 购买 / reroll 递增
	GameManager.toggle_lock(0)
	var locked_id: String = GameManager.shop_offers[0].get("id", "")
	GameManager.roll_shop(true)
	_check(GameManager.shop_offers[0].get("id", "") == locked_id and GameManager.shop_offers[0].get("locked", false), "锁定商品跨刷新保留")
	while GameManager.reroll_free_left > 0:
		GameManager.reroll_shop()
	var cost1: int = GameManager.reroll_cost
	GameManager.reroll_shop()
	_check(GameManager.reroll_cost > cost1, "reroll 费用递增 %d→%d" % [cost1, GameManager.reroll_cost])
	var bought := false
	for i in range(GameManager.shop_offers.size()):
		if GameManager.buy_offer(i):
			bought = true
			break
	_check(bought, "购买一件商品")

	# 法宝（被动道具）货架位：若本波刷出法宝，买一件验证被动生效链路
	GameManager.add_spirit_stones(500)
	var item_idx := -1
	for i in range(GameManager.shop_offers.size()):
		var offer: Dictionary = GameManager.shop_offers[i]
		if offer.get("kind", "") == "item" and not offer.get("sold", false):
			item_idx = i
			break
	if item_idx >= 0:
		var item_id: String = GameManager.shop_offers[item_idx].get("id", "")
		_check(GameManager.buy_offer(item_idx), "购买法宝 %s" % item_id)
		_check(GameManager.has_item(item_id), "法宝已入持有列表（%s）" % item_id)
	else:
		print("[INFO] 本波货架未刷出法宝，跳过法宝购买验证")

	# 6. 三合一合成 + 羁绊
	GameManager.add_weapon("huoyan_fu")
	GameManager.add_weapon("huoyan_fu")
	GameManager.add_weapon("huoyan_fu")
	_check(GameManager.count_copies("huoyan_fu", 1) >= 3, "三把火焰符就位")
	_check(GameManager.bonus_pierce >= 1, "符箓羁绊穿透加成生效 (+%d)" % GameManager.bonus_pierce)
	var merged := GameManager.merge_weapon("huoyan_fu", 1, {"pool": "equipped", "index": 0})
	_check(merged, "三合一合成成功")
	_check(GameManager.active_synergies.has("talisman"), "羁绊表含符箓")

	# 7. 跳到 13 波验证新敌种 + 藏宝匣
	GameManager.player.max_health = 99999.0
	GameManager.player.current_health = 99999.0
	spawner.start_wave(13)
	await get_tree().process_frame
	var chests := get_tree().get_nodes_in_group("chests").size()
	_check(chests > 0, "藏宝匣已刷新 (%d)" % chests)
	var wait_w13 := 0
	while get_tree().get_nodes_in_group("enemies").size() < 10 and wait_w13 < 100:
		await get_tree().physics_frame
		_dismiss_dialogs()
		wait_w13 += 1
	var kinds := {}
	for e in get_tree().get_nodes_in_group("enemies"):
		kinds[e.name.get_basename()] = true
	print("[INFO] 13 波在场敌种: " + str(kinds.keys()))

	# 8. 藏宝匣砸开掉落：选取满耐久未受损匣子（避免战斗中被流弹预先波及）
	var chest: Node2D = null
	for c in get_tree().get_nodes_in_group("chests"):
		if c is SpiritChest and c.remaining_hits == c.max_hits:
			chest = c
			break
	if chest == null:
		chest = SpiritChest.new()
		chest.global_position = Vector2(100.0, 100.0)
		main.add_child(chest)
		await get_tree().process_frame
	var gems_before := get_tree().get_nodes_in_group("gems").size()
	chest.take_damage(99999.0, Vector2.ZERO, false)
	await get_tree().process_frame
	_check(is_instance_valid(chest) and get_tree().get_nodes_in_group("gems").size() == gems_before,
		"藏宝匣一下砸不开（按几下计，见 GameBalance.CHEST_BREAK_HITS）")
	for i in range(GameBalance.CHEST_BREAK_HITS - 1):
		if is_instance_valid(chest):
			chest.take_damage(1.0, Vector2.ZERO, false)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(get_tree().get_nodes_in_group("gems").size() > gems_before, "藏宝匣砸开后掉落补给")

	# 8.5 固定 Boss 波：第 10 波魔君登场 → 血条上屏 → 击杀才开商店（超时锁关）
	GameManager.is_game_over = false
	GameManager.player.max_health = 99999.0
	GameManager.player.current_health = 99999.0
	spawner.start_wave(10)
	var hud: Node = main.get_node_or_null("UILayer/GameHUD")
	var wait_boss_spawn := 0
	while (get_tree().get_nodes_in_group("boss").is_empty() or (hud != null and not hud.is_boss_bar_visible())) and wait_boss_spawn < 120:
		await get_tree().physics_frame
		_dismiss_dialogs()
		wait_boss_spawn += 1
	var bosses := get_tree().get_nodes_in_group("boss")
	_check(bosses.size() == 1, "第 10 波固定刷新 1 只魔君 (实际 %d)" % bosses.size())
	_check(hud != null and hud.is_boss_bar_visible(), "魔君登场后 Boss 血条上屏")
	if bosses.size() > 0:
		var stones_before_boss: int = GameManager.spirit_stones
		bosses[0].take_damage(9999999.0, Vector2.ZERO, false)
		var wait_boss_die := 0
		while (get_tree().get_nodes_in_group("boss").size() > 0 or (hud != null and hud.is_boss_bar_visible()) or GameManager.shop_offers.size() < GameManager.SHOP_BASE_SLOTS) and wait_boss_die < 180:
			await get_tree().physics_frame
			_dismiss_dialogs()
			wait_boss_die += 1
		_check(get_tree().get_nodes_in_group("boss").size() == 0, "魔君伏诛后离场")
		_check(GameManager.spirit_stones >= stones_before_boss + GameBalance.BOSS_STONE_REWARD,
			"魔君掉落灵石奖励 (+%d)" % GameBalance.BOSS_STONE_REWARD)
		_check(hud != null and not hud.is_boss_bar_visible(), "魔君伏诛后血条收起")
	_check(GameManager.shop_offers.size() == GameManager.SHOP_BASE_SLOTS, "Boss 波结算后商店照常开启")
	_dismiss_dialogs()

	# 9. 暂停菜单的音量控件：控件必须真的在、真的接总线（不可见的设置项等于没有设置项）
	var pause: Node = main.get_node_or_null("UILayer/PauseMenu")
	_check(pause != null, "暂停菜单存在")
	var sliders: Array = []
	if pause != null:
		var stack: Array = [pause]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is HSlider:
				sliders.append(n)
			for c in n.get_children():
				stack.append(c)
	_check(sliders.size() >= 2, "有 BGM/音效 两条音量滑条 (%d)" % sliders.size())
	if sliders.size() >= 2:
		# 不按遍历下标猜「第 0 条是 BGM」——栈式 DFS 会把顺序反过来。
		# 改成逐条拖动、看它实际把哪条总线拉到 40%，两条都被拉到才算接对。
		var before := {
			"BGM": AudioManager.get_bus_linear(&"BGM"),
			"SFX": AudioManager.get_bus_linear(&"SFX"),
		}
		var driven := {}
		for s in sliders:
			AudioManager.set_bus_linear(&"BGM", 1.0)
			AudioManager.set_bus_linear(&"SFX", 1.0)
			s.value = 60.0 if s.value != 60.0 else 70.0  # 先动一下，保证下面这次拖动会发信号
			s.value = 40.0
			if absf(AudioManager.get_bus_linear(&"BGM") - 0.4) < 0.02:
				driven["BGM"] = true
			if absf(AudioManager.get_bus_linear(&"SFX") - 0.4) < 0.02:
				driven["SFX"] = true
		_check(driven.has("BGM"), "有一条滑条驱动 BGM 总线")
		_check(driven.has("SFX"), "有一条滑条驱动 SFX 总线")
		AudioManager.set_bus_linear(&"BGM", float(before["BGM"]))
		AudioManager.set_bus_linear(&"SFX", float(before["SFX"]))

	# 10. 全局设置板块（SettingsDialog）挂载与打开/关闭闭环验证
	var settings: Node = main.get_node_or_null("UILayer/SettingsDialog")
	_check(settings != null, "设置面板 SettingsDialog 挂载就绪")
	if settings != null and settings.has_method("open"):
		settings.open()
		_check(settings.visible, "设置面板正常打开")
		settings.close()
		var wait_sett := 0
		while settings.visible and wait_sett < 60:
			await get_tree().physics_frame
			wait_sett += 1
		_check(not settings.visible, "设置面板正常关闭")

	await get_tree().process_frame
	_dismiss_dialogs()
	Engine.time_scale = 1.0

	if _c.report("SMOKE_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)
