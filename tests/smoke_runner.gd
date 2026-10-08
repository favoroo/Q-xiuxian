extends Node

## 无头全流程冒烟测试：道统选择→本命法器→战斗→升级→灵韵结算→商店(锁/买/reroll/合成)→新波次敌种
## 运行: godot --headless --path . res://tests/SmokeRunner.tscn

var _c := TestCheck.new()

## 断言实现统一走 tests/check.gd（与 UnitRunner / PoolCheck 同一套判据与输出格式）
func _check(cond: bool, label: String) -> void:
	_c.check(cond, label)

func _dismiss_dialogs() -> void:
	for node_name in ["LevelUpDialog", "WaveShop", "PlayerStatsDialog", "PauseMenu", "SettingsDialog"]:
		var n := get_node_or_null("/root/Main/UILayer/" + node_name)
		if n != null and n.visible:
			n.visible = false
	get_tree().paused = false

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

	await get_tree().create_timer(2.0).timeout
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
	_check(ups.size() == 3, "升级三选一抽取 (得 %d 项)" % ups.size())

	# 3. 强制触发一次升级弹窗路径（验证信号链不炸），随后关闭
	GameManager.add_experience(50)
	await get_tree().process_frame
	_dismiss_dialogs()

	# 4. 结束本波 → 灵韵结算 → 商店
	var spawner: Node = GameManager.wave_spawner
	var stones_before := GameManager.spirit_stones
	spawner.end_wave()
	await _wait_clean(2.0)
	_check(GameManager.spirit_stones > stones_before, "灵韵波末结算发灵石 (+%d)" % (GameManager.spirit_stones - stones_before))
	_check(GameManager.shop_offers.size() == 4, "商店 4 货架 (实际 %d)" % GameManager.shop_offers.size())
	_dismiss_dialogs()

	# 5. 商店护栏：锁定保留 / 购买 / reroll 递增
	GameManager.toggle_lock(0)
	var locked_id: String = GameManager.shop_offers[0].get("id", "")
	GameManager.roll_shop(true)
	_check(GameManager.shop_offers[0].get("id", "") == locked_id and GameManager.shop_offers[0].get("locked", false), "锁定商品跨刷新保留")
	var cost1: int = GameManager.reroll_cost
	GameManager.reroll_shop()
	_check(GameManager.reroll_cost > cost1, "reroll 费用递增 %d→%d" % [cost1, GameManager.reroll_cost])
	var bought := false
	for i in range(GameManager.shop_offers.size()):
		if GameManager.buy_offer(i):
			bought = true
			break
	_check(bought, "购买一件商品")

	# 6. 三合一合成 + 羁绊
	GameManager.add_weapon("huoyan_fu")
	GameManager.add_weapon("huoyan_fu")
	GameManager.add_weapon("huoyan_fu")
	_check(GameManager.count_copies("huoyan_fu", 1) >= 3, "三把火焰符就位")
	_check(GameManager.bonus_pierce >= 1, "符箓羁绊穿透加成生效 (+%d)" % GameManager.bonus_pierce)
	var merged := GameManager.merge_weapon("huoyan_fu", 1, {"pool": "equipped", "index": 0})
	_check(merged, "三合一合成成功")
	_check(GameManager.active_synergies.has("talisman"), "羁绊表含符箓")

	# 7. 跳到 13 波验证新敌种 + 灵药丛
	GameManager.player.max_health = 99999.0
	GameManager.player.current_health = 99999.0
	spawner.start_wave(13)
	await _wait_clean(6.0)
	var herbs := get_tree().get_nodes_in_group("herbs").size()
	_check(herbs > 0, "灵药丛已刷新 (%d)" % herbs)
	var kinds := {}
	for e in get_tree().get_nodes_in_group("enemies"):
		kinds[e.name.get_basename()] = true
	print("[INFO] 13 波在场敌种: " + str(kinds.keys()))

	# 8. 灵药丛摧毁掉落
	var herb = get_tree().get_nodes_in_group("herbs")[0] if herbs > 0 else null
	if herb != null:
		var gems_before := get_tree().get_nodes_in_group("gems").size()
		herb.take_damage(1.0, Vector2.ZERO, false)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(get_tree().get_nodes_in_group("gems").size() > gems_before, "灵药丛摧毁后掉落补给")

	# 8.5 固定 Boss 波：第 10 波魔君登场 → 血条上屏 → 击杀才开商店（超时锁关）
	GameManager.is_game_over = false
	GameManager.player.max_health = 99999.0
	GameManager.player.current_health = 99999.0
	spawner.start_wave(10)
	await _wait_clean(3.5)
	var bosses := get_tree().get_nodes_in_group("boss")
	_check(bosses.size() == 1, "第 10 波固定刷新 1 只魔君 (实际 %d)" % bosses.size())
	var hud: Node = main.get_node_or_null("UILayer/GameHUD")
	_check(hud != null and hud.is_boss_bar_visible(), "魔君登场后 Boss 血条上屏")
	if bosses.size() > 0:
		var stones_before_boss: int = GameManager.spirit_stones
		bosses[0].take_damage(9999999.0, Vector2.ZERO, false)
		await _wait_clean(3.5)
		_check(get_tree().get_nodes_in_group("boss").size() == 0, "魔君伏诛后离场")
		_check(GameManager.spirit_stones >= stones_before_boss + GameBalance.BOSS_STONE_REWARD,
			"魔君掉落灵石奖励 (+%d)" % GameBalance.BOSS_STONE_REWARD)
		_check(hud != null and not hud.is_boss_bar_visible(), "魔君伏诛后血条收起")
	_check(GameManager.shop_offers.size() == 4, "Boss 波结算后商店照常开启")
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
		await get_tree().create_timer(0.2).timeout
		_check(not settings.visible, "设置面板正常关闭")

	await _wait_clean(2.0)
	_dismiss_dialogs()

	if _c.report("SMOKE_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)
