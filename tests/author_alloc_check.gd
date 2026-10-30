extends Node

## 作者面板「◆ 悟道」测试台判据（2026-10-25）
##
## 钉住的核心不变量：
##  ① 重算幂等 —— AuthorStatRebuild.rebuild 对「角色 + 道具 + 加点 + 回合末成长」重放一遍，
##     所有属性字段必须原样（任何漏重放的来源都会在这条红）。
##  ② 删一层精确 —— 加 3 层再删 1 层 ≡ 账本直接只有 2 层的重放结果。
##  ③ 上限场景 —— elite_up ×4 恰好顶到 ELITE_DAMAGE_CAP(1.0)，删 1 层必须回落到 0.75。
##     这是「为什么不能走撤销」的根因回归：revert_stat_fields 对夹顶字段一分不扣，会永远卡在 cap。
##  ④ 超级悟道 —— 领悟/撤销连赠予的神通道具一起进出，hook 读数与武器槽位同步。
##  ⑤ 采气不参与重放 —— harvest 是跨回合复利值，重算保留现值；删采气卡按名义值扣。
##  ⑥ 账本对账 —— sum(upgrade_counts.values()) == upgrade_history.size()。
##  ⑦ 面板 UI —— ◆ 悟道 分页能打开、全表卡数与表一致、点卡加/删走 AuthorMode 全链路。
##
## 运行: $G --headless --path . res://tests/AuthorAllocCheck.tscn

const STAT_FIELDS: Array[String] = [
	"weapon_damage_mult", "melee_damage", "ranged_damage", "elemental_damage",
	"engineering_damage", "contraption_damage", "attack_speed_mult", "armor",
	"move_speed_mult", "attack_range_mult", "pickup_range_mult", "hp_regen",
	"fog_vision_bonus",
	"crit_rate", "crit_mult", "dodge", "lifesteal", "luck", "xp_gain_mult",
	"knockback_mult", "elite_damage", "skill_cooldown_mult", "free_rerolls",
	"revive_charges", "thorns_pct", "chest_count_bonus", "chest_quality",
	"chest_reward_mult", "pet_damage_mult", "pet_effect_mult", "pet_cooldown_mult",
	"pet_slots_bonus", "shop_price_mult", "stat_bonus_pierce", "bonus_pierce",
	"dodge_cap_bonus", "harvest", "element_damage",
]

var _c := TestCheck.new()
var _panel: AuthorPanel
## 角色基线采气（apply_cultivator 之后的值）：harvest 是跨回合复利值，
## _build_loadout 反复重建时必须先归回基线，否则它在多次重建间越滚越大
var _harvest_base: float = 0.0

func _ready() -> void:
	call_deferred("_run")
	_c.set_min_checks(30)  # ⑦ 段要等帧，中途断链就靠这条下限报红

func _run() -> void:
	_setup_run()
	_test_rebuild_idempotent()
	_test_remove_exact()
	_test_cap_precision()
	_test_super_card()
	_test_harvest_carry()
	_test_ledger_consistency()
	await _test_alloc_view_ui()  # 含 await（等帧收 dying 节点）：必须 await，否则协程在首帧断掉、后半判据静默丢失
	get_tree().quit(0 if _c.report("AUTHOR_ALLOC_RESULT") else 1)

## 一份干净开局（不载 Main 场景）：假玩家 + 剑士角色 mods + 属性初值
func _setup_run() -> void:
	GameManager.headless_guard_sec = 120.0
	GameManager.reset_run()
	# 抽函数防漏行回归钉（#30 实录）：reset_stat_fields 从 reset() 切出去时曾把
	# chest_break_bonus/chest_item_grants/cultivator_id 三行清零一起带丢
	_c.check(GameManager.cultivator_id == "" and GameManager.chest_item_grants == 0 \
			and GameManager.chest_break_bonus == 0,
			"⓪ reset_run 清零表完整：cultivator_id/chest_item_grants/chest_break_bonus 归零")
	var p := AuthorTestPlayer.new()
	GameManager.player = p
	add_child(p)
	# 假玩家默认 100 血，与真 Player 的 BASE_MAX_HEALTH(120) 对齐：重算的上限公式才对得上
	p.max_health = Player.BASE_MAX_HEALTH
	p.current_health = p.max_health
	GameManager.run_started = true
	GameManager.author_mode = true
	GameManager.cultivator_id = "jian"
	CultivatorSystem.apply_cultivator(GameManager)
	_harvest_base = GameManager.harvest

## AuthorMode 只改账本（重放触发在视图层，避免循环类依赖）；测试同构：动作 + 立即重放
func _add(id: String, n: int = 1) -> bool:
	var ok := AuthorMode.add_upgrade(GameManager, id, n)
	if ok:
		AuthorStatRebuild.rebuild(GameManager)
	return ok

func _remove(id: String, n: int = 1) -> bool:
	var ok := AuthorMode.remove_upgrade(GameManager, id, n)
	if ok:
		AuthorStatRebuild.rebuild(GameManager)
	return ok

func _take(card_id: String) -> bool:
	var ok := AuthorMode.take_super(GameManager, card_id)
	if ok:
		AuthorStatRebuild.rebuild(GameManager)
	return ok

func _drop_super(card_id: String) -> bool:
	var ok := AuthorMode.remove_super(GameManager, card_id)
	if ok:
		AuthorStatRebuild.rebuild(GameManager)
	return ok

func _snapshot() -> Dictionary:
	var d := {}
	for f in STAT_FIELDS:
		d[f] = GameManager.get(f)
	d["player_max_hp"] = GameManager.player.max_health
	d["player_cur_hp"] = GameManager.player.current_health
	return d

## 逐字段比对（浮点容差 1e-4，element_damage 走字典 hash），失败字段拼进断言文案
func _same(a: Dictionary, b: Dictionary, label: String) -> void:
	var bad: Array[String] = []
	for f in a.keys():
		var va = a[f]
		var vb = b.get(f)
		if va is Dictionary:
			if (va as Dictionary).hash() != (vb as Dictionary).hash():
				bad.append(String(f))
		elif absf(float(va) - float(vb)) > 0.0001:
			bad.append("%s %s→%s" % [f, va, vb])
	_c.check(bad.is_empty(), "%s%s" % [label, "" if bad.is_empty() else "（漂移：" + "、".join(bad) + "）"])

## 一套固定「构筑」：3 件道具 + 3 张卡 + 一段回合末成长（幂等/精确两条测试共用）
func _build_loadout() -> void:
	GameManager.harvest = _harvest_base
	GameManager.upgrade_counts.clear()
	GameManager.upgrade_history.clear()
	GameManager.super_cards_taken.clear()
	GameManager.items = []
	AuthorStatRebuild.invalidate_caches(GameManager)
	GameManager.add_item("kuangxue_dan")
	GameManager.add_item("guijia_fu")
	GameManager.add_item("mibao_luopan")
	_add("atk_up", 3)
	_add("harvest_up", 1)
	_add("luck_up", 2)
	GameManager._wave_end_growth = {"max_hp": 9.0, "hp_regen": 1.5, "lifesteal": 0.04}
	AuthorStatRebuild.rebuild(GameManager)

func _test_rebuild_idempotent() -> void:
	_build_loadout()
	var before := _snapshot()
	AuthorStatRebuild.rebuild(GameManager)
	_same(before, _snapshot(), "① 重算幂等：角色+道具+加点+回合末成长重放一遍全字段不变")
	# 金币不许被重放动过（作者面板测试期间钱包只由显式按钮动）
	_c.check(GameManager.spirit_stones == 0, "① 重算不碰钱包（spirit_stones 保持 %d）" % GameManager.spirit_stones)

func _test_remove_exact() -> void:
	_build_loadout()
	_add("atk_up", 1)   # 3 → 4 层
	var four := _snapshot()
	_remove("atk_up", 1)  # 4 → 3 层
	var three := _snapshot()
	_check_ledger_three()
	# 3 层的重放结果必须等于「一开始就只加 3 层」：删层与加层顺序无关
	_build_loadout()
	_same(three, _snapshot(), "② 删一层精确：加4删1 ≡ 直接加3")
	_c.near(float(three["weapon_damage_mult"]) - float(four["weapon_damage_mult"]), -0.08, 0.0001,
			"② 删一层读数恰好回落一层幅度（atk_up 0.08）")

func _test_cap_precision() -> void:
	_build_loadout()
	# elite_up ×4 = 1.0，恰好等于 ELITE_DAMAGE_CAP：夹顶态
	for _i in range(4):
		_add("elite_up", 1)
	_c.near(GameManager.elite_damage, 1.0, 0.0001, "③ elite_up ×4 顶到斩将上限 1.0")
	_remove("elite_up", 1)
	# 撤销路径（revert_stat_fields）在这一步会一分不扣；重放必须真的降到 0.75
	_c.near(GameManager.elite_damage, 0.75, 0.0001, "③ 夹顶后删一层精确回落到 0.75（撤销做不到）")
	_remove("elite_up", 3)
	_c.near(GameManager.elite_damage, 0.0, 0.0001, "③ 删光后回到角色/道具基线 0")

func _test_super_card() -> void:
	_build_loadout()
	var slots_before: int = GameManager.max_weapon_slots()
	_c.check(_take("super_kaitian"), "④ 领悟开天辟地成功")
	_c.check(GameManager.has_item("shen_kaitian"), "④ 神通道具入 items")
	_c.check("super_kaitian" in GameManager.super_cards_taken, "④ super_cards_taken 记账")
	_c.check(GameManager.upgrade_counts.get("super_kaitian", 0) == 1, "④ upgrade_counts 记账")
	_c.near(GameManager.item_hook_sum("weapon_slot_bonus"), 1.0, 0.0001, "④ 武器槽 hook +1")
	_c.check(GameManager.max_weapon_slots() == slots_before + 1, "④ 武器槽上限 +1")
	_drop_super("super_kaitian")
	_c.check(not GameManager.has_item("shen_kaitian"), "④ 撤销后神通道具出 items")
	_c.check(GameManager.super_cards_taken.is_empty(), "④ 撤销后超级卡名册清空")
	_c.check(not GameManager.upgrade_counts.has("super_kaitian"), "④ 撤销后 counts 清干净")
	_c.near(GameManager.item_hook_sum("weapon_slot_bonus"), 0.0, 0.0001, "④ 撤销后 hook 归零")
	_c.check(GameManager.max_weapon_slots() == slots_before, "④ 撤销后槽位回到原值")
	# 重复领悟被拦 + 撤销后再领悟可行
	_c.check(_take("super_kaitian"), "④ 撤销后可重新领悟")
	_c.check(not _take("super_kaitian"), "④ 同一张卡不能领悟两次")

func _test_harvest_carry() -> void:
	_build_loadout()
	GameManager.harvest = 100.0
	AuthorStatRebuild.rebuild(GameManager)
	_c.near(GameManager.harvest, 100.0, 0.0001, "⑤ 重算保留采气累积值（跨回合复利不抹）")
	var h0 := GameManager.harvest
	_add("harvest_up", 1)
	_c.near(GameManager.harvest, h0 + 12.0, 0.0001, "⑤ 加采气卡 +12")
	_remove("harvest_up", 1)
	_c.near(GameManager.harvest, h0, 0.0001, "⑤ 删采气卡按名义值扣回")

func _test_ledger_consistency() -> void:
	_build_loadout()
	_add("atk_up", 2)
	_remove("atk_up", 1)
	_take("super_shalu")
	_drop_super("super_shalu")
	var total := 0
	for uid in GameManager.upgrade_counts:
		total += int(GameManager.upgrade_counts[uid])
	_c.check(total == GameManager.upgrade_history.size(),
			"⑥ 账本对账：counts 总层数 %d == history 条数 %d" % [total, GameManager.upgrade_history.size()])

func _test_alloc_view_ui() -> void:
	_panel = AuthorPanel.new()
	add_child(_panel)
	_panel.open()
	await get_tree().process_frame
	_panel.switch_tab(5)
	# 等两帧：refresh 用 queue_free 清旧卡， dying 节点要等帧末才真正出树，数早了会虚高
	await get_tree().process_frame
	await get_tree().process_frame
	_c.check(_panel._alloc_view != null, "⑦ ◆ 悟道 分页已挂载")
	_c.check(_panel._alloc_view._upgrade_grid.get_child_count() == UpgradeData.UPGRADES.size(),
			"⑦ 全表卡数 == UPGRADES 表大小（%d）" % UpgradeData.UPGRADES.size())
	_c.check(_panel._alloc_view._super_grid.get_child_count() == SuperUpgradeData.all_ids().size(),
			"⑦ 超级卡数 == CARDS 表大小")
	# 稀有度筛选走同一套 chips 语言
	_panel._alloc_view._on_filter_tapped("rarity", "legendary")
	await get_tree().process_frame
	await get_tree().process_frame
	var legendary := 0
	for u in UpgradeData.UPGRADES:
		if String(u.get("rarity", "")) == "legendary":
			legendary += 1
	_c.check(_panel._alloc_view._upgrade_grid.get_child_count() == legendary,
			"⑦ 传说筛选后只剩 %d 张" % legendary)
	_panel._alloc_view._on_filter_tapped("rarity", "")
	await get_tree().process_frame
	await get_tree().process_frame
	# 面板内点卡全链路：详情窗动作走的就是 AuthorMode.add/remove
	var base_dmg: float = GameManager.weapon_damage_mult
	var owned_before := int(GameManager.upgrade_counts.get("atk_up", 0))
	_panel._alloc_view._add("atk_up")
	_c.check(int(GameManager.upgrade_counts.get("atk_up", 0)) == owned_before + 1,
			"⑦ 面板加卡 → counts %d → %d" % [owned_before, owned_before + 1])
	AuthorMode.remove_upgrade(GameManager, "atk_up", 1)
	AuthorStatRebuild.rebuild(GameManager)
	_c.near(GameManager.weapon_damage_mult, base_dmg, 0.0001, "⑦ 删卡后武器伤害回落")
	_panel.close()
	await get_tree().process_frame

	# 720 窄屏档：6 个 tab 不得把关闭键顶出/压住（tab 宽度自适应的下限验证）
	get_tree().root.size = Vector2i(720, 540)
	var narrow := AuthorPanel.new()
	add_child(narrow)
	narrow.open()
	await get_tree().process_frame
	var tab_tail := 0.0
	for b in narrow._tab_buttons:
		tab_tail = maxf(tab_tail, b.get_global_rect().end.x)
	var close_head: float = narrow._close_btn.get_global_rect().position.x
	_c.check(tab_tail <= close_head + 0.5,
			"⑦ 720 窄屏 6 tab 不压关闭键（tab 尾 %.0f ≤ 关闭键头 %.0f）" % [tab_tail, close_head])
	narrow.close()
	get_tree().root.size = Vector2i(960, 540)

## counts/history/超级卡名册三本账一致（删层只删最后一条同 id 流水）
func _check_ledger_three() -> void:
	var total := 0
	for uid in GameManager.upgrade_counts:
		total += int(GameManager.upgrade_counts[uid])
	_c.check(total == GameManager.upgrade_history.size(),
			"② 账本对账：counts 总层 %d == history %d 条" % [total, GameManager.upgrade_history.size()])
