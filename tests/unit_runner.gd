extends Node

## 数值逻辑单元测试：纯函数 + 少量需要 GameManager 状态的商店断言
## 运行: godot --headless --path . res://tests/UnitRunner.tscn
## 这些公式以前埋在 autoload / 刷怪器里，必须起整棵场景树才能碰；
## 现在它们都在 GameBalance（static 纯函数）、随机源可由 GameManager.rng 注入，所以能直接断言。

const EPS := 0.0001

var _c := TestCheck.new()

func _ready() -> void:
	_test_exp_curve()
	_test_armor()
	_test_wave_scaling()
	_test_boss_waves()
	_test_spawn_shape()
	_test_pricing()
	_test_harvest()
	_test_rarity_weights()
	_test_weighted_pick()
	_test_synergy_levels()
	_test_upgrade_table()
	_test_upgrade_roll_filters()
	_test_shop_determinism()
	_test_main_tag_pity()
	_test_shop_tag_soft_bias()
	_test_weapon_targeting()
	_test_audio_wiring()
	_test_settings_manager()
	_test_five_elements_system()

	if _c.report("UNIT_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

# ---------------- 经验 / 等级 ----------------

func _test_exp_curve() -> void:
	GameManager.reset_run()
	_c.equals(GameManager.experience_to_next, GameBalance.EXP_FIRST_LEVEL, "1 级起始修为取自 GameBalance")
	_c.equals(GameBalance.exp_to_next(10), 18, "exp_to_next(10)=int(13.5)+5")
	_c.equals(GameBalance.exp_to_next(18), 29, "exp_to_next(18)=int(24.3)+5")
	var prev := 1
	var monotonic := true
	for i in range(20):
		var nxt := GameBalance.exp_to_next(prev)
		if nxt <= prev:
			monotonic = false
		prev = nxt
	_c.check(monotonic, "经验曲线严格递增（20 级）")

	# 与 GameManager 的升级循环同源：喂满一次升级，检查下一级门槛就是公式值
	GameManager.add_experience(GameBalance.EXP_FIRST_LEVEL)
	_c.equals(GameManager.level, 2, "喂满初始修为后升到 2 级")
	_c.equals(GameManager.experience_to_next, GameBalance.exp_to_next(GameBalance.EXP_FIRST_LEVEL), "第 2 级门槛与公式一致")

# ---------------- 护甲 / 受伤 ----------------

func _test_armor() -> void:
	_c.near(GameBalance.armor_reduction(0.0), 0.0, EPS, "0 护甲无减伤")
	_c.near(GameBalance.armor_reduction(10.0), 1.0 - 1.0 / 1.8, EPS, "10 护甲减伤 44.4%")
	_c.near(GameBalance.incoming_damage(100.0, 10.0), 100.0 * (1.0 - GameBalance.armor_reduction(10.0)), 0.01, "面板减伤与实伤同源")
	_c.near(GameBalance.incoming_damage(1.0, 5000.0), GameBalance.DAMAGE_FLOOR, EPS, "极高护甲仍保底 1 点实伤")
	_c.near(GameBalance.incoming_damage(50.0, -20.0), 50.0, EPS, "负护甲不会被当成增益")
	var last := 999.0
	var decreasing := true
	for a in range(0, 60):
		var v := GameBalance.incoming_damage(100.0, float(a))
		if v > last + EPS:
			decreasing = false
		last = v
	_c.check(decreasing, "护甲越高实伤单调不增")
	_c.check(GameBalance.armor_reduction(100000.0) < 1.0, "减伤永远达不到 100%")

# ---------------- 波次缩放 ----------------

func _test_wave_scaling() -> void:
	_c.near(GameBalance.enemy_hp_mult(1), 1.0, EPS, "第 1 波血量倍率 1.0")
	_c.near(GameBalance.enemy_hp_mult(10), 2.62, EPS, "第 10 波血量 ×2.62")
	_c.near(GameBalance.enemy_hp_mult(20), 4.42, EPS, "第 20 波血量 ×4.42")
	_c.near(GameBalance.enemy_dmg_mult(10), 1.90, EPS, "第 10 波接触伤害 ×1.90")
	_c.near(GameBalance.wave_duration(1), 22.0, EPS, "第 1 波时长 22s")
	_c.near(GameBalance.wave_duration(20), 60.0, EPS, "第 20 波封顶 60s")
	_c.near(GameBalance.wave_duration(99), 60.0, EPS, "无尽波次也封顶 60s")
	_c.near(GameBalance.spawn_interval(1), 1.295, EPS, "第 1 波刷怪间隔 1.295s")
	_c.near(GameBalance.spawn_interval(40), GameBalance.SPAWN_INTERVAL_MIN, EPS, "刷怪间隔有下限")
	_c.near(GameBalance.enemy_hp_mult(0), GameBalance.enemy_hp_mult(1), EPS, "非法波次 0 被夹到 1")

# ---------------- Boss 波（固定关卡） ----------------

func _test_boss_waves() -> void:
	_c.check(GameBalance.is_boss_wave(10), "第 10 波是固定 Boss 关")
	_c.check(GameBalance.is_boss_wave(20), "第 20 波是固定 Boss 关（心魔劫）")
	_c.check(not GameBalance.is_boss_wave(5), "第 5 波仍是精英不是 Boss")
	_c.check(not GameBalance.is_boss_wave(15), "第 15 波仍是精英不是 Boss")
	_c.check(not GameBalance.is_boss_wave(9), "非 Boss 波次不错判")
	_c.check(GameBalance.is_boss_wave(30), "无尽 30 波再逢魔君")
	_c.check(not GameBalance.is_boss_wave(25), "无尽 25 波不是 Boss")

	# 10/20 波让位给魔君，精英退守 5/15 与无尽每 3 波
	_c.check(GameBalance.is_elite_wave(5), "第 5 波精英保留")
	_c.check(GameBalance.is_elite_wave(15), "第 15 波精英保留")
	_c.check(not GameBalance.is_elite_wave(10), "第 10 波不再刷精英（Boss 关）")
	_c.check(not GameBalance.is_elite_wave(20), "第 20 波不再刷精英（Boss 关）")
	_c.check(not GameBalance.is_elite_wave(21), "非无尽模式 21 波不是精英")
	_c.check(GameBalance.is_elite_wave(21, true), "无尽 21 波恢复每 3 波精英")
	_c.check(not GameBalance.is_elite_wave(30, true), "无尽 30 波是 Boss 不是精英")

	# Boss 血条厚度：与普通敌人同曲线，靠基础值拉开 ~5 倍精英的差距
	_c.near(GameBalance.boss_hp(10) / GameBalance.boss_hp(1), GameBalance.enemy_hp_mult(10), EPS, "Boss 血量与敌人同一条成长曲线")
	var golem_w10 := 550.0 * GameBalance.enemy_hp_mult(10)
	_c.check(GameBalance.boss_hp(10) > golem_w10 * 5.0, "第 10 波 Boss 血量至少精英 5 倍 (%.0f vs %.0f)" % [GameBalance.boss_hp(10), golem_w10])
	_c.check(GameBalance.boss_hp(20) > GameBalance.boss_hp(10), "第 20 波魔尊血更厚")
	_c.check(GameBalance.boss_contact_damage(20) > GameBalance.boss_contact_damage(1), "Boss 接触伤害随波次成长")

# ---------------- 一轮刷几只 ----------------

func _test_spawn_shape() -> void:
	_c.equals(GameBalance.spawn_batch(1, 0.0), 2, "第 1 波 + 触发追加 → 2 只")
	_c.equals(GameBalance.spawn_batch(1, 0.9), 1, "第 1 波未触发追加 → 1 只")
	_c.equals(GameBalance.spawn_batch(8, 0.9), 3, "第 8 波 → 1+2=3 只")
	_c.equals(GameBalance.spawn_batch(8, 0.0), 4, "第 8 波追加 → 4 只")
	_c.equals(GameBalance.ELITE_STONE_BONUS, 25, "精英额外灵石 25")
	var count_at_cap := 0
	for i in range(200):
		count_at_cap += GameBalance.spawn_batch(20, 0.0)
	_c.check(count_at_cap > 200, "后期每轮必然多于 1 只")

# ---------------- 商店定价 ----------------

func _test_pricing() -> void:
	_c.equals(GameBalance.weapon_price(25, 1, 1.0), 25, "首波原价")
	_c.equals(GameBalance.weapon_price(25, 5, 1.0), 33, "第 5 波 +8")
	_c.equals(GameBalance.weapon_price(25, 5, 0.8), 26, "散修 8 折取整")
	_c.equals(GameBalance.potion_price(WeaponData.POTION_BASE_PRICE, 5, 1.0), 15, "回气丹随波加价")
	_c.equals(GameBalance.reroll_cost(5, 0, 1.0), 7, "首次重掷 = 2+波次")
	_c.equals(GameBalance.reroll_cost(5, 2, 1.0), 11, "本波第 3 次重掷再 +4")
	_c.equals(GameBalance.reroll_cost(5, 1, 1.0), 9, "第 2 次重掷 = 2+5+2")
	_c.equals(GameBalance.reroll_cost(5, 1, 0.8), 7, "重掷价也吃折扣（9×0.8 取整）")

	# GameManager 必须真的用这条公式，而不是自己再写一遍
	GameManager.reset_run()
	GameManager.wave_number = 3
	GameManager.reroll_count = 1
	GameManager.shop_price_mult = 1.0
	GameManager.roll_shop(false)
	_c.equals(GameManager.reroll_cost, GameBalance.reroll_cost(3, 1, 1.0), "roll_shop 的重掷价与公式一致")

	# 流派偏好软加权（替代旧版硬过滤）
	_c.near(GameBalance.tag_filter_mult(["sword"], []), 1.0, EPS, "无过滤时恒为 1（不改变权重）")
	_c.near(GameBalance.tag_filter_mult(["sword"], ["sword"]), GameBalance.TAG_FILTER_BONUS, EPS, "命中限定 tag → BONUS 倍率")
	_c.near(GameBalance.tag_filter_mult(["spirit"], ["sword"]), GameBalance.TAG_FILTER_LEAK, EPS, "未命中 → LEAK 漏出权重")
	_c.near(GameBalance.tag_filter_mult(["sword", "spirit"], ["sword"]), GameBalance.TAG_FILTER_BONUS, EPS, "多 tag 命中其一即 BONUS")

# ---------------- 灵韵复利 ----------------

func _test_harvest() -> void:
	_c.equals(GameBalance.harvest_gain(7.6), 8, "灵韵发放四舍五入")
	_c.equals(GameBalance.harvest_gain(0.4), 0, "不足 0.5 不发")
	_c.near(GameBalance.harvest_next(100.0, 5, 16), 105.0, EPS, "截止波前复利 ×1.05")
	_c.near(GameBalance.harvest_next(100.0, 16, 16), 100.0, EPS, "到截止波停止增长")
	_c.near(GameBalance.harvest_next(100.0, 40, 16), 100.0, EPS, "无尽也不暴涨")
	var h := 100.0
	for w in range(1, 16):
		h = GameBalance.harvest_next(h, w, 16)
	_c.near(h, 100.0 * pow(1.05, 15), 0.01, "15 次复利累计正确")

# ---------------- 稀有度权重 ----------------

func _test_rarity_weights() -> void:
	var base: Dictionary = GameBalance.rarity_weights(0.0)
	_c.near(base["epic"], 10.0, EPS, "无福缘时仙品权重 10")
	_c.near(base["common"], 60.0, EPS, "无福缘时凡品权重 60")
	_c.near(base["rare"], 30.0, EPS, "良品权重恒为 30")
	var lucky: Dictionary = GameBalance.rarity_weights(20.0)
	_c.near(lucky["epic"], 30.0, EPS, "20 点福缘把仙品抬到 30")
	_c.near(lucky["common"], 40.0, EPS, "差额从凡品扣")
	_c.near(float(lucky["common"]) + float(lucky["rare"]) + float(lucky["epic"]), 100.0, EPS, "三档之和仍是 100")
	var maxed: Dictionary = GameBalance.rarity_weights(999.0)
	_c.near(maxed["common"], GameBalance.RARITY_COMMON_FLOOR, EPS, "凡品有权重地板不会归零")
	_c.near(GameBalance.rarity_weights(-5.0)["epic"], 10.0, EPS, "负福缘不会倒扣仙品")

# ---------------- 权重抽奖 ----------------

func _test_weighted_pick() -> void:
	_c.equals(GameBalance.weighted_pick_index([1.0, 1.0], 0.25), 0, "前半段命中第 0 项")
	_c.equals(GameBalance.weighted_pick_index([1.0, 1.0], 0.75), 1, "后半段命中第 1 项")
	_c.equals(GameBalance.weighted_pick_index([0.0, 1.0], 0.0), 1, "零权重项不会被选中")
	_c.equals(GameBalance.weighted_pick_index([], 0.5), 0, "空表安全返回 0")
	_c.equals(GameBalance.weighted_pick_index([0.0, 0.0], 0.5), 0, "全零权重不除零")
	_c.equals(GameBalance.weighted_pick_index([1.0], 1.0), 0, "roll=1 边界仍落在最后一项")

	# 倍率与概率：亲和 ×2.5 应显著抬高被选中频率
	var hits := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261008
	for i in range(2000):
		if GameBalance.weighted_pick_index([2.5, 1.0], rng.randf()) == 0:
			hits += 1
	_c.check(hits > 1200 and hits < 1800, "2.5 倍权重的命中率约 71%%（实测 %.1f%%）" % [float(hits) / 20.0])

# ---------------- 羁绊档位 ----------------

func _test_synergy_levels() -> void:
	var th: Array = [2, 4, 6]
	_c.equals(GameBalance.synergy_level(1, th), 0, "1 件未激活")
	_c.equals(GameBalance.synergy_level(2, th), 1, "2 件一档")
	_c.equals(GameBalance.synergy_level(3, th), 1, "3 件仍是一档")
	_c.equals(GameBalance.synergy_level(4, th), 2, "4 件二档")
	_c.equals(GameBalance.synergy_level(6, th), 3, "6 件满档")
	_c.equals(GameBalance.synergy_level(99, th), 3, "超过满档不会溢出")
	_c.equals(GameBalance.synergy_level(1, th, 1), 1, "门槛下移 1 后 1 件即激活")
	_c.equals(GameBalance.synergy_level(5, th, 1), 3, "门槛下移 1 后 5 件满档")
	_c.equals(GameBalance.synergy_level(0, th, 99), 0, "门槛再低也要至少 1 件")
	_c.equals(GameBalance.synergy_level(3, []), 0, "空阈值表安全")

	# 与 GameManager 的结算保持同一把尺子：两只灵蝶 → 御灵一档
	GameManager.reset_run()
	GameManager.drones = [1, 1]
	GameManager.recalc_synergies()
	_c.check(GameManager.active_synergies.has("spirit"), "御灵羁绊已进入结算表")
	_c.equals(int(GameManager.active_synergies["spirit"]["level"]), 1, "2 只灵蝶 = 御灵一档")
	_c.near(GameManager.synergy_max_hp_bonus, 15.0, EPS, "御灵一档 +15 气血上限")
	GameManager.spirit_threshold_adj = 1
	GameManager.recalc_synergies()
	_c.equals(int(GameManager.active_synergies["spirit"]["level"]), 1, "门槛下移后 2 只仍是一档")
	GameManager.reset_run()

# ---------------- 加点表 ----------------

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
		"atk_up": 0.15, "armor_up": 2.0, "speed_up": 0.08, "pickup_up": 0.4,
		"regen_up": 1.2, "critdmg_up": 0.25, "lifesteal_up": 0.04, "luck_up": 6.0,
		"harvest_up": 8.0, "range_up": 0.12,
	}
	var targets := {
		"atk_up": "weapon_damage_mult", "armor_up": "armor", "speed_up": "move_speed_mult",
		"pickup_up": "pickup_range_mult", "regen_up": "hp_regen", "critdmg_up": "crit_mult",
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
	var stones := GameManager.spirit_stones
	GameManager.apply_upgrade("coins_up")
	_c.equals(GameManager.spirit_stones - stones, int(UpgradeData.get_upgrade_def("coins_up").get("apply", {})["spirit_stones"]), "灵石补给按表发钱")
	GameManager.reset_run()

	# 历史记录：同一项叠加两次要记下 count=2，供 max_stacks 过滤使用
	GameManager.apply_upgrade("atk_up")
	GameManager.apply_upgrade("atk_up")
	_c.equals(int(GameManager.upgrade_counts.get("atk_up", 0)), 2, "领悟次数被统计")
	_c.equals(GameManager.upgrade_history.size(), 2, "本局悟道记录有条目")
	_c.check(GameManager.upgrade_history[0].has("rarity_label"), "记录里带稀有度文案")

# ---------------- 三选一的过滤与确定性 ----------------

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
	_c.equals(seen.size(), 3, "三选一无重复")
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

	# 福缘把仙品概率抬上去：固定样本量下仙品数量应随福缘增加
	var epic_low := _count_epic(0.0)
	var epic_high := _count_epic(40.0)
	_c.check(epic_high >= epic_low, "福缘 40 的仙品数量不少于福缘 0（%d → %d）" % [epic_low, epic_high])

func _count_epic(luck: float) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var n := 0
	for i in range(400):
		for p in UpgradeData.get_random_upgrades(1, {"luck": luck, "rng": rng}):
			if p.get("rarity", "") == "epic":
				n += 1
	return n

# ---------------- 商店：确定性 + 主流派保底 ----------------

func _test_shop_determinism() -> void:
	GameManager.reset_run()
	GameManager.wave_number = 6
	GameManager.rng.seed = 1234567
	GameManager.roll_shop(true)
	var first: Array = GameManager.shop_offers.duplicate(true)
	_c.equals(GameManager.shop_offers.size(), 4, "货架固定 4 个位")
	for offer in first:
		_c.check(offer.get("kind", "") in ["weapon", "potion"], "货架项类型合法：%s" % str(offer.get("kind", "")))
		_c.check(int(offer.get("price", 0)) > 0, "货架项价格大于 0：%s" % str(offer.get("id", "")))

	# 价格必须等于公式值，不能有第二套算法
	for offer in first:
		if offer.get("kind", "") == "weapon":
			var base := int(WeaponData.get_def(offer["id"]).get("price", 20))
			_c.equals(int(offer["price"]), GameBalance.weapon_price(base, 6, GameManager.shop_price_mult), "法器价与 GameBalance 一致（%s）" % offer["id"])
		else:
			_c.equals(int(offer["price"]), GameBalance.potion_price(WeaponData.POTION_BASE_PRICE, 6, GameManager.shop_price_mult), "回气丹价与 GameBalance 一致")

	GameManager.rng.seed = 1234567
	GameManager.roll_shop(true)
	_c.equals(str(GameManager.shop_offers), str(first), "同种子 → 同一副货架")

func _test_main_tag_pity() -> void:
	GameManager.reset_run()
	GameManager.drones = [1, 1]        # 御灵 2 件 → 主流派 = spirit
	GameManager.wave_number = 5
	# 手动构造无 spirit 的货架，直接驱动保底计数器，不再依赖旧版硬过滤
	GameManager.shop_offers = _make_all_non_spirit_offers(5)
	GameManager._no_main_tag_waves = 0
	GameManager._apply_main_tag_pity(5)
	_c.check(not _shelf_has_spirit(), "第 1 波无 spirit → 保底未触发（计数 1/2）")
	GameManager._apply_main_tag_pity(5)   # 计数 2/2 → 触发
	_c.check(_shelf_has_spirit(), "连续 2 波后保底强制塞入一件御灵法器")
	GameManager.reset_run()

func _make_all_non_spirit_offers(wave: int) -> Array:
	# 4 个全为青云剑（tags=["sword"]，不含 spirit）的货架，用于保底测试的确定输入
	var w_id := "qingyun_sword"
	var base := int(WeaponData.get_def(w_id).get("price", 20))
	var offers: Array = []
	for i in range(4):
		offers.append({
			"kind": "weapon", "id": w_id,
			"price": GameBalance.weapon_price(base, wave, GameManager.shop_price_mult),
			"sold": false, "locked": false,
		})
	return offers

func _shelf_has_spirit() -> bool:
	for offer in GameManager.shop_offers:
		if offer.get("kind", "") == "weapon" and "spirit" in WeaponData.tags_of(offer.get("id", "")):
			return true
	return false

## 剑痴（shop_tag_filter=["sword"]）软加权：旧版硬过滤会让货架坍缩成全是青云剑，
## 改为软加权后必定能在多次刷新中见到非剑系法器。
func _test_shop_tag_soft_bias() -> void:
	GameManager.reset_run()
	GameManager.shop_tag_filter = ["sword"]   # 剑痴流派偏好
	GameManager.wave_number = 1
	GameManager.rng.seed = 99991
	var saw_non_sword := false
	for i in range(30):
		GameManager.roll_shop(true)
		for offer in GameManager.shop_offers:
			if offer.get("kind", "") == "weapon":
				if not ("sword" in WeaponData.tags_of(offer.get("id", ""))):
					saw_non_sword = true
					break
		if saw_non_sword:
			break
	_c.check(saw_non_sword, "剑痴软加权下 30 次刷新内必出现非剑系法器（不再全是青云剑）")
	GameManager.reset_run()

# ---------------- 多武器智能多向索敌分配 ----------------

func _test_weapon_targeting() -> void:
	# 1. 空输入与无敌人
	var empty_res := GameBalance.assign_weapon_targets([], [])
	_c.equals(empty_res.size(), 0, "空武器表返回空数组")

	var w4 := [
		{"base_angle": 0.0, "range": 150.0, "prev_id": 0},
		{"base_angle": PI * 0.5, "range": 150.0, "prev_id": 0},
		{"base_angle": PI, "range": 150.0, "prev_id": 0},
		{"base_angle": -PI * 0.5, "range": 150.0, "prev_id": 0},
	]
	_c.equals(GameBalance.assign_weapon_targets(w4, []), [-1, -1, -1, -1], "无敌人时全部无目标")

	# 2. 单一敌人：射程内全部集火，超射程不打
	var single_enemy := [{"id": 101, "dist": 120.0, "angle": 0.0}]
	_c.equals(GameBalance.assign_weapon_targets(w4, single_enemy), [0, 0, 0, 0], "单一敌人时 4 把剑全部集火")

	var mixed_range := [
		{"base_angle": 0.0, "range": 100.0, "prev_id": 0},
		{"base_angle": PI, "range": 200.0, "prev_id": 0},
	]
	_c.equals(GameBalance.assign_weapon_targets(mixed_range, single_enemy), [-1, 0], "超出单把武器射程的不强行锁定")

	# 3. 四面来敌：4 把剑按各自槽位扇区一对一迎战 4 个方向的敌人
	var four_dirs := [
		{"id": 1, "dist": 110.0, "angle": 0.0},       # 右 (东)
		{"id": 2, "dist": 115.0, "angle": PI * 0.5},  # 下 (南)
		{"id": 3, "dist": 120.0, "angle": PI},        # 左 (西)
		{"id": 4, "dist": 125.0, "angle": -PI * 0.5}, # 上 (北)
	]
	var assigned4 := GameBalance.assign_weapon_targets(w4, four_dirs)
	_c.equals(assigned4, [0, 1, 2, 3], "四面受敌时 4 把剑按各自方位一对一分流迎击")

	# 4. 武器多于敌人（3 把剑 vs 2 个反方向敌人）：绝不漏掉任一方向敌人（防 Overkill 扎堆）
	var w3 := [
		{"base_angle": 0.0, "range": 150.0, "prev_id": 0},
		{"base_angle": 2.0 * PI / 3.0, "range": 150.0, "prev_id": 0},
		{"base_angle": -2.0 * PI / 3.0, "range": 150.0, "prev_id": 0},
	]
	var two_dirs := [
		{"id": 10, "dist": 95.0, "angle": 0.0},
		{"id": 20, "dist": 130.0, "angle": PI},
	]
	var assigned3 := GameBalance.assign_weapon_targets(w3, two_dirs)
	_c.check(0 in assigned3 and 1 in assigned3, "3 剑对 2 敌时两侧敌人均被覆盖（实际: %s）" % str(assigned3))

	# 5. 贴身危急敌人优先解围：40px 贴脸敌人必定优先获得防守
	var danger_case := [
		{"id": 99, "dist": 40.0, "angle": PI},
		{"id": 88, "dist": 110.0, "angle": 0.0},
	]
	var w_single := [{"base_angle": 0.0, "range": 150.0, "prev_id": 0}]
	_c.equals(GameBalance.assign_weapon_targets(w_single, danger_case), [0], "即使在背后，贴身危急敌人也优先保命迎击")

	# 6. 目标粘滞性：距离与角度相近的两个敌人，保持原锁定目标不来回抽搐
	var close_pair := [
		{"id": 501, "dist": 110.0, "angle": 0.05},
		{"id": 502, "dist": 108.0, "angle": -0.05},
	]
	var sticky_w := [{"base_angle": 0.0, "range": 150.0, "prev_id": 501}]
	_c.equals(GameBalance.assign_weapon_targets(sticky_w, close_pair), [0], "粘滞保护：已锁定目标微弱劣势时不跳变")

# ---------------- 音频接线完整性 ----------------
## 这一组断言专门挡三类「听起来正常其实哑了」的事故：
##   注册了 key 但素材没进包 / 没被导入（本项目踩过：新烘的 wav 未跑 editor import）
##   调用点写了文件名当 key（曾经的 play_sfx("powerUp2") 一直静默无效）
##   总线布局没加载（音量设置就会对着不存在的总线空转）

func _test_audio_wiring() -> void:
	var missing: Array = AudioManager.missing_paths()
	_c.check(missing.is_empty(), "注册表里的音效文件全部就位（缺: %s）" % str(missing))

	var needed := [
		"blade_shoot", "enemy_hit", "orb_hit", "gem_pickup", "level_up", "obelisk_blessing",
		"enemy_death", "enemy_death_elite", "sword_swing", "talisman_throw", "thunder_strike",
		"fan_gust", "shop_buy", "shop_reroll", "shop_lock", "sell", "equip", "unequip",
		"merge_success", "ui_click", "ui_back", "ui_error", "wave_start", "wave_clear",
		"boss_raid", "dodge", "heal", "victory", "defeat",
	]
	var silent: Array = []
	for k in needed:
		if not AudioManager.has_sfx(k):
			silent.append(k)
	_c.check(silent.is_empty(), "游戏会用到的 %d 个音效 key 都能播（哑的: %s）" % [needed.size(), str(silent)])

	# 数据表里配的 sfx 必须是已注册 key，否则 WeaponData 改了名而 AudioManager 没跟上
	var bad_table: Array = []
	for w_id in WeaponData.SHOP_POOL:
		var k: String = WeaponData.sfx_for(w_id)
		if not AudioManager.has_sfx(k):
			bad_table.append("%s→%s" % [w_id, k])
	_c.check(bad_table.is_empty(), "每件法器的开火音都注册过（异常: %s）" % str(bad_table))
	_c.equals(WeaponData.sfx_for("qingyun_sword"), "sword_swing", "青云剑开火音按流派走")
	_c.equals(WeaponData.sfx_for("不存在的法器"), "blade_shoot", "未知 id 回落到通用开火音")

	for bus in ["Master", "BGM", "SFX", "Voice"]:
		_c.check(AudioServer.get_bus_index(StringName(bus)) >= 0, "总线 %s 存在" % bus)

	# 音量读写往返 + 落盘（测完还原成原值，不弄脏用户的设置）
	var before := AudioManager.get_bus_linear(&"SFX")
	AudioManager.set_bus_linear(&"SFX", 0.5)
	_c.near(AudioManager.get_bus_linear(&"SFX"), 0.5, 0.01, "SFX 音量设 50% 后读回一致")
	AudioManager.set_bus_linear(&"SFX", 0.0)
	_c.check(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"SFX")), "拉到 0 真静音（不留 -inf 残响）")
	AudioManager.set_bus_linear(&"SFX", before)
	_c.near(AudioManager.get_bus_linear(&"SFX"), before, 0.01, "音量已还原为 %.2f" % before)

	# BGM 状态机：素材齐备 + 真能切换 + 未知 key 不打断当前播放
	for key in AudioManager.BGM_TABLE.keys():
		var path: String = AudioManager.BGM_TABLE[key].get("path", "")
		_c.check(ResourceLoader.exists(path), "BGM 素材就位：%s (%s)" % [key, path.get_file()])
	AudioManager.play_bgm_key("battle")
	_c.equals(String(AudioManager.bgm_key), "battle", "battle 在播")
	AudioManager.play_bgm_key("shop")
	_c.equals(String(AudioManager.bgm_key), "shop", "商店阶段切到 shop")
	AudioManager.play_bgm_key("shop")
	_c.equals(String(AudioManager.bgm_players[AudioManager.bgm_next].stream.resource_path),
		AudioManager.BGM_TABLE["shop"]["path"], "重复调同一 key 不会重头播")
	AudioManager.play_bgm_key("这个 key 不存在")
	_c.equals(String(AudioManager.bgm_key), "shop", "未知 BGM key 不影响当前播放")
	AudioManager.play_bgm_key("battle")

# ---------------- 游戏设置模块 ----------------

func _test_settings_manager() -> void:
	# 1. 保存当前用户状态以便测试后恢复
	var orig_master := SettingsManager.get_bus_volume(&"Master")
	var orig_master_mute := SettingsManager.is_bus_muted(&"Master")
	var orig_dmg_num := bool(SettingsManager.get_val(&"display", &"damage_numbers", true))
	var orig_shake := bool(SettingsManager.get_val(&"display", &"screen_shake", true))

	# 2. 音量与静音切换
	SettingsManager.set_bus_volume(&"Master", 0.65)
	_c.near(SettingsManager.get_bus_volume(&"Master"), 0.65, 0.01, "主音量设定 65% 读取一致")
	SettingsManager.set_bus_muted(&"Master", true)
	_c.check(SettingsManager.is_bus_muted(&"Master"), "主音量静音状态生效")
	_c.check(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Master")), "AudioServer Master 总线已同步静音")
	# 拖动音量大于 0 应自动解除静音
	SettingsManager.set_bus_volume(&"Master", 0.8)
	_c.check(not SettingsManager.is_bus_muted(&"Master"), "调高音量自动解除静音状态")

	# 3. 画面与战斗反馈开关读写
	SettingsManager.set_val(&"display", &"damage_numbers", false)
	_c.equals(bool(SettingsManager.get_val(&"display", &"damage_numbers", true)), false, "关闭伤害跳字配置生效")
	SettingsManager.set_val(&"display", &"screen_shake", false)
	_c.equals(bool(SettingsManager.get_val(&"display", &"screen_shake", true)), false, "关闭屏幕震动配置生效")

	# 4. 恢复默认设置
	SettingsManager.reset_to_defaults()
	_c.near(SettingsManager.get_bus_volume(&"Master"), 1.0, 0.01, "重置默认后主音量恢复 100%")
	_c.equals(bool(SettingsManager.get_val(&"display", &"damage_numbers", false)), true, "重置默认后伤害跳字恢复开启")
	_c.equals(bool(SettingsManager.get_val(&"display", &"screen_shake", false)), true, "重置默认后屏幕震动恢复开启")

	# 5. 还原测试前状态
	SettingsManager.set_bus_volume(&"Master", orig_master)
	SettingsManager.set_bus_muted(&"Master", orig_master_mute)
	SettingsManager.set_val(&"display", &"damage_numbers", orig_dmg_num)
	SettingsManager.set_val(&"display", &"screen_shake", orig_shake)

# ---------------- 五行武器矩阵与属性转化 ----------------

func _test_five_elements_system() -> void:
	# 1. 武器表完整性校验：15 把法器（5 五行 × 3 把）且图标资源齐全
	_c.equals(WeaponData.DEFS.size(), 15, "全武器库扩充至 15 把法器")
	_c.equals(WeaponData.SHOP_POOL.size(), 15, "商店池覆盖全部 15 把法器")
	var missing_icons: Array = []
	var missing_dual_tags: Array = []
	var elem_counts: Dictionary = {"metal": 0, "wood": 0, "water": 0, "fire": 0, "earth": 0}
	for w_id in WeaponData.SHOP_POOL:
		var def := WeaponData.get_def(w_id)
		var icon_path: String = def.get("icon", "")
		if icon_path.is_empty() or not ResourceLoader.exists(icon_path):
			missing_icons.append(w_id)
		var c_tag := WeaponData.class_of(w_id)
		var e_tag := WeaponData.element_of(w_id)
		if c_tag.is_empty() or e_tag.is_empty():
			missing_dual_tags.append(w_id)
		else:
			elem_counts[e_tag] = int(elem_counts.get(e_tag, 0)) + 1
	_c.check(missing_icons.is_empty(), "15 把法器的图标文件全部就位（缺: %s）" % str(missing_icons))
	_c.check(missing_dual_tags.is_empty(), "每把法器均具备「器类+五行」双标签（缺: %s）" % str(missing_dual_tags))
	for e_key in elem_counts.keys():
		_c.equals(int(elem_counts[e_key]), 3, "五行【%s】恰好包含 3 把法器" % e_key)

	# 2. 土豆兄弟式属性受益折算（GameBalance.weapon_stat_bonus 纯函数）
	var earth_scalings := {"armor": 3.5}
	_c.near(GameBalance.weapon_stat_bonus(earth_scalings, {"armor": 0.0}, 1), 0.0, EPS, "0 护甲时无额外属性加成")
	_c.near(GameBalance.weapon_stat_bonus(earth_scalings, {"armor": 10.0}, 1), 35.0, EPS, "10 护甲在 ★1 番天印下转化 +35 基础伤")
	_c.near(GameBalance.weapon_stat_bonus(earth_scalings, {"armor": 10.0}, 2), 43.75, EPS, "★2 属性转化系数 ×1.25 (+43.75)")
	_c.near(GameBalance.weapon_stat_bonus(earth_scalings, {"armor": 10.0}, 3), 52.5, EPS, "★3 属性转化系数 ×1.50 (+52.5)")

	var wood_scalings := {"hp_regen": 4.5}
	_c.near(GameBalance.weapon_stat_bonus(wood_scalings, {"hp_regen": 2.0}, 1), 9.0, EPS, "2.0 气血回复在青木藤鞭下转化 +9 基础伤")

	# 3. 五行羁绊与多品类环绕灵宝在 GameManager 中的结算
	GameManager.reset_run()
	GameManager.drones = [
		{"id": "hunyuan_zhong", "star": 1},
		{"id": "hunyuan_zhong", "star": 1}
	]
	GameManager.recalc_synergies()
	_c.check(GameManager.active_synergies.has("spirit") and GameManager.active_synergies.has("earth"), "上阵 2 尊混元古钟同时触发【御灵】与【厚土】双羁绊")
	_c.near(GameManager.synergy_armor, 3.0, EPS, "厚土一档提供 +3 护甲")
	_c.near(GameManager.synergy_knockback_mult, 1.25, EPS, "厚土一档提供 +25% 震退力")
	_c.near(GameManager.get_effective_armor(), 3.0, EPS, "有效护甲已计入厚土羁绊")
	GameManager.reset_run()



