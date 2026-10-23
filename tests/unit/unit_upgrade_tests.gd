class_name UnitUpgradeTests
extends UnitTestsBase

## 单测模块：加点表 / 悟道候选过滤与确定性 / 波后悟道结算（从 tests/unit_runner.gd 拆出，2026-10-11）。
## 调用顺序与判据契约（UNIT_RESULT: ALL PASS / 退出码）由 UnitRunner 统一保证；
## _c 与 EPS 继承自 UnitTestsBase，函数体与拆分前逐字一致。
func _test_upgrade_table() -> void:
	var fields: Array = GameBalance.upgrade_fields()
	var unknown: Array = []
	var missing: Array = []
	for u in UpgradeData.UPGRADES:
		var apply: Dictionary = u.get("apply", {})
		if apply.is_empty():
			missing.append(u.get("id", "?"))
		for key in apply.keys():
			if not (key in fields):
				unknown.append("%s.%s" % [u.get("id", "?"), key])
	_c.check(missing.is_empty(), "每个升级项都带 apply 幅度表（缺: %s）" % str(missing))
	_c.check(unknown.is_empty(), "apply 字段名都在白名单内（非法: %s）" % str(unknown))

	# 逐项落地：加点确实改到了对应属性，且幅度就是表里的数
	var deltas := {
		"atk_up": 0.08, "armor_up": 2.0, "speed_up": 0.08, "temper": 3.0,
		"regen_up": 1.2, "critdmg_up": 0.25, "lifesteal_up": 0.04, "luck_up": 6.0,
		"harvest_up": 8.0, "range_up": 0.05,
	}
	var targets := {
		"atk_up": "weapon_damage_mult", "armor_up": "armor", "speed_up": "move_speed_mult",
		"temper": "armor", "regen_up": "hp_regen", "critdmg_up": "crit_mult",
		"lifesteal_up": "lifesteal", "luck_up": "luck", "harvest_up": "harvest",
		"range_up": "attack_range_mult",
	}
	for uid in deltas.keys():
		GameManager.reset_run()
		var before: float = float(GameManager.get(targets[uid]))
		GameManager.apply_upgrade(uid)
		_c.near(float(GameManager.get(targets[uid])) - before, deltas[uid], EPS, "%s 幅度与表一致" % uid)

	# 特殊项：会心/流云有上限，法诀有地板，灵石补给直接发钱
	GameManager.reset_run()
	for i in range(30):
		GameManager.apply_upgrade("crit_up")
	_c.near(GameManager.get_crit_rate(), GameManager.CRIT_RATE_CAP, EPS, "暴击率叠满后卡在软上限")
	GameManager.reset_run()
	for i in range(30):
		GameManager.apply_upgrade("dodge_up")
	_c.near(GameManager.get_effective_dodge(), GameManager.DODGE_CAP, EPS, "身法叠满后卡在硬上限")
	GameManager.reset_run()
	for i in range(40):
		GameManager.apply_upgrade("haste_up")
	_c.near(GameManager.attack_speed_mult, GameManager.ATTACK_SPEED_FLOOR, EPS, "施法间隔不会低于地板")
	GameManager.reset_run()
	# 贪婪：收益 +10 落地（原 coins_up 直接发钱档已重做为长期经济档）
	var harvest_before: float = GameManager.harvest
	GameManager.apply_upgrade("greed")
	_c.near(GameManager.harvest - harvest_before, 10.0, EPS, "贪婪按表加收益")
	GameManager.reset_run()

	# 历史记录：同一项叠加两次要记下 count=2，供 max_stacks 过滤使用
	GameManager.apply_upgrade("atk_up")
	GameManager.apply_upgrade("atk_up")
	_c.equals(int(GameManager.upgrade_counts.get("atk_up", 0)), 2, "领悟次数被统计")
	_c.equals(GameManager.upgrade_history.size(), 2, "本局悟道记录有条目")
	_c.check(GameManager.upgrade_history[0].has("rarity_label"), "记录里带稀有度文案")

func _test_upgrade_roll_filters() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242

	var ctx := {"luck": 0.0, "locked_upgrades": [], "counts": {}, "rng": rng}
	var picks := UpgradeData.get_random_upgrades(3, ctx)
	_c.equals(picks.size(), 3, "默认池足够时抽满 3 项")
	var ids: Array = []
	for p in picks:
		ids.append(p.get("id", ""))
	var seen := {}
	for id in ids:
		seen[id] = true
	_c.equals(seen.size(), 3, "同屏候选无重复")
	_c.check(picks[0].has("border_color"), "抽到的项带稀有度边框色")

	# 同种子必须同结果（这条断言依赖 rng 注入，是以前做不到的一件事）
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 4242
	var picks2 := UpgradeData.get_random_upgrades(3, {"rng": rng2})
	var ids2: Array = []
	for p in picks2:
		ids2.append(p.get("id", ""))
	_c.equals(ids2, ids, "同种子 → 同结果（可确定性回归）")

	# 锁死项与叠满项都不该出现
	var all_ids: Array = []
	for u in UpgradeData.UPGRADES:
		all_ids.append(u.get("id", ""))
	var locked := UpgradeData.get_random_upgrades(3, {"locked_upgrades": all_ids})
	_c.equals(locked.size(), 0, "全部锁死时抽不出任何项")
	var maxed_counts := {}
	for u in UpgradeData.UPGRADES:
		maxed_counts[u.get("id", "")] = int(u.get("max_stacks", 99))
	_c.equals(UpgradeData.get_random_upgrades(3, {"counts": maxed_counts}).size(), 0, "全部叠满时抽不出任何项")
	var one_left := {}
	for u in UpgradeData.UPGRADES:
		one_left[u.get("id", "")] = int(u.get("max_stacks", 99))
	one_left["atk_up"] = 0
	var rest := UpgradeData.get_random_upgrades(3, {"counts": one_left})
	_c.equals(rest.size(), 1, "只剩 1 项可选时不硬凑 3 项")
	_c.equals(rest[0].get("id", ""), "atk_up", "剩下的正是未叠满那项")

	# 轮回重生：限购 2 次（复活次数），落地与「买满不再刷新」双向回归
	GameManager.reset_run()
	GameManager.apply_upgrade("revive_up")
	_c.equals(GameManager.revive_charges, 1, "轮回重生落地为复活次数 +1")
	var revive_maxed := {}
	for u in UpgradeData.UPGRADES:
		revive_maxed[u.get("id", "")] = int(u.get("max_stacks", 99))
	revive_maxed["revive_up"] = 2
	var revive_picks := UpgradeData.get_random_upgrades(3, {"counts": revive_maxed})
	var leaked := false
	for rp in revive_picks:
		if rp.get("id", "") == "revive_up":
			leaked = true
	_c.check(not leaked, "轮回重生买满 2 次后不再出现在悟道候选")

	# 福缘把高稀有（史诗+传说）概率抬上去：固定样本量下数量应随福缘增加
	var epic_low := _count_high_rarity(0.0)
	var epic_high := _count_high_rarity(40.0)
	_c.check(epic_high >= epic_low, "福缘 40 的史诗+传说数量不少于福缘 0（%d → %d）" % [epic_low, epic_high])

func _test_alloc_session() -> void:
	GameManager.reset_run()
	GameManager.wave_number = 4
	GameManager.rng.seed = 20261009
	var finished_calls := 0
	if not GameManager.alloc_finished.is_connected(_on_alloc_finished_probe):
		GameManager.alloc_finished.connect(_on_alloc_finished_probe)
	_alloc_probe_count = 0

	# 升级只记账，不当场结算
	GameManager.add_experience(GameBalance.EXP_FIRST_LEVEL)
	_c.equals(GameManager.level, 2, "喂满初始修为升到 2 级")
	_c.equals(GameManager.pending_upgrade_points, 1, "升 1 级攒 1 点待加点")
	GameManager.add_experience(GameBalance.exp_to_next(GameBalance.EXP_FIRST_LEVEL))
	_c.equals(GameManager.level, 3, "再喂满一级升到 3 级")
	_c.equals(GameManager.pending_upgrade_points, 2, "升几级攒几点（现在 2 点）")
	_c.check(GameManager.has_pending_upgrades(), "has_pending_upgrades 认这 2 点")

	# 候选数量：默认 5，且不重复
	var five := GameManager.roll_upgrades()
	_c.equals(five.size(), GameManager.UPGRADE_OFFER_COUNT, "默认一次给 %d 个候选" % GameManager.UPGRADE_OFFER_COUNT)
	var ids := {}
	for p in five:
		ids[p.get("id", "")] = true
	_c.equals(ids.size(), five.size(), "同一屏候选不重复")

	# 开局会话：额度、报价与点数总额
	GameManager.open_alloc_session()
	_c.equals(GameManager.alloc_points_total, 2, "面板记住本次结算共 2 点")
	_c.equals(GameManager.alloc_offers.size(), GameManager.UPGRADE_OFFER_COUNT, "面板一屏 %d 张卡" % GameManager.UPGRADE_OFFER_COUNT)
	_c.equals(GameManager.alloc_reroll_free_left, GameManager.ALLOC_FREE_REROLLS, "每回合 %d 次免费刷新" % GameManager.ALLOC_FREE_REROLLS)
	_c.equals(GameManager.alloc_reroll_cost, GameBalance.reroll_cost(4, 0, 1.0), "悟道报价与货架重掷同一公式（第 1 次价）")

	# 加 1 点：属性落地 + 点数 -1 + 换一屏新候选
	var lvl_recs := GameManager.upgrade_history.size()
	var picked_id: String = String(GameManager.alloc_offers[0].get("id", ""))
	_c.check(GameManager.take_alloc_upgrade(0), "确认领悟第 1 张卡")
	_c.equals(GameManager.upgrade_history.size(), lvl_recs + 1, "悟道记录 +1")
	_c.equals(int(GameManager.upgrade_counts.get(picked_id, 0)), 1, "该条层数 +1")
	_c.equals(GameManager.pending_upgrade_points, 1, "还剩 1 点")
	_c.equals(GameManager.alloc_offers.size(), GameManager.UPGRADE_OFFER_COUNT, "剩点还在 → 换一屏新候选")
	_c.equals(_alloc_probe_count, 0, "没加完不发 alloc_finished（商店不许提前开）")

	# 越界与空池护栏
	_c.check(not GameManager.take_alloc_upgrade(99), "越界下标不加点了")

	# 刷新：先吃免费，再扣灵石，报价跟着上涨
	var stones := GameManager.spirit_stones
	_c.check(GameManager.reroll_alloc(), "免费刷新一次")
	_c.equals(GameManager.spirit_stones, stones, "免费刷新不扣灵石")
	_c.equals(GameManager.alloc_reroll_free_left, 0, "免费额度用光")
	_c.check(GameManager.can_reroll_alloc(), "灵石够就能继续刷")
	var price1 := GameManager.alloc_reroll_cost
	_c.check(GameManager.reroll_alloc(), "第二次刷新付灵石")
	_c.equals(GameManager.spirit_stones, stones - price1, "按报价扣灵石（-%d）" % price1)
	_c.equals(GameManager.alloc_reroll_cost, GameBalance.reroll_cost(4, 1, 1.0), "再刷一档涨价（与货架同曲线）")

	# 加完最后 1 点：发 alloc_finished、清空候选
	_c.check(GameManager.take_alloc_upgrade(0), "确认领悟最后 1 点")
	_c.equals(GameManager.pending_upgrade_points, 0, "点数清零")
	_c.check(not GameManager.has_pending_upgrades(), "has_pending_upgrades 归零")
	_c.equals(_alloc_probe_count, 1, "加完点发一次 alloc_finished")
	_c.check(GameManager.alloc_offers.is_empty(), "结算结束后不留候选")
	_c.check(not GameManager.reroll_alloc(), "没点数时刷新被拒（不许白扣灵石）")

	# 没有点数时：会话直接不开
	GameManager.open_alloc_session()
	_c.equals(_alloc_probe_count, 1, "零点数时 open_alloc_session 不重开结算")

	# 池子抽空（全部叠满）不许把玩家扣在这一屏：点数作废、商店照常开
	GameManager.reset_run()
	GameManager.pending_upgrade_points = 2
	for u in UpgradeData.UPGRADES:
		GameManager.upgrade_counts[u.get("id", "")] = int(u.get("max_stacks", 99))
	_alloc_probe_count = 0
	GameManager.open_alloc_session()
	_c.equals(GameManager.pending_upgrade_points, 0, "悟道池抽空时点数作废（不锁屏）")
	_c.check(GameManager.alloc_offers.is_empty(), "池抽空时不留空一屏候选")
	_c.equals(_alloc_probe_count, 1, "池抽空也发 alloc_finished（灵石阁照常开）")

	# reset_run 把这条线也清干净
	GameManager.pending_upgrade_points = 3
	GameManager.reset_run()
	_c.equals(GameManager.pending_upgrade_points, 0, "reset_run 清待加点")
	_c.equals(GameManager.alloc_reroll_count, 0, "reset_run 清悟道刷新次数")
	_c.equals(GameManager.alloc_reroll_free_left, 0, "reset_run 清悟道免费额度")
	_c.check(GameManager.alloc_offers.is_empty(), "reset_run 清悟道候选")
	if GameManager.alloc_finished.is_connected(_on_alloc_finished_probe):
		GameManager.alloc_finished.disconnect(_on_alloc_finished_probe)

var _alloc_probe_count: int = 0

## 第 12 波采样：史诗/传说均已解锁且未触顶，福缘乘区的差异能在计数上显出来
func _count_high_rarity(luck: float) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var n := 0
	for i in range(400):
		for p in UpgradeData.get_random_upgrades(1, {"luck": luck, "wave": 12, "rng": rng}):
			if p.get("rarity", "") in ["epic", "legendary"]:
				n += 1
	return n

# ---------------- 波后悟道结算：攒点 / 5 候选 / 刷新 ----------------

## 战斗中的升级从此只攒点数，回合结束一次性加完（2026-10-09 用户指令）。
## 这条断言钉三件事：点数与等级一一对应、候选数是 5、刷新的免费额度与价格线同货架一个口径。

func _on_alloc_finished_probe() -> void:
	_alloc_probe_count += 1
