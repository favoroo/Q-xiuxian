class_name UnitEconomyTests
extends UnitTestsBase

## 单测模块：经验等级 / 商店定价 / 灵韵 / 稀有度 / 权重抽奖 / 羁绊档位 / 商店确定性与主流派保底（从 tests/unit_runner.gd 拆出，2026-10-11）。
## 调用顺序与判据契约（UNIT_RESULT: ALL PASS / 退出码）由 UnitRunner 统一保证；
## _c 与 EPS 继承自 UnitTestsBase，函数体与拆分前逐字一致。
func _test_exp_curve() -> void:
	GameManager.reset_run()
	_c.equals(GameManager.experience_to_next, GameBalance.EXP_FIRST_LEVEL, "1 级起始修为取自 GameBalance")
	_c.equals(GameBalance.exp_to_next(10), 20, "exp_to_next(10)=int(14.2)+6")
	_c.equals(GameBalance.exp_to_next(20), 34, "exp_to_next(20)=int(28.4)+6")
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

func _test_pricing() -> void:
	_c.equals(GameBalance.weapon_price(25, 1, 1.0), 25, "首波原价")
	_c.equals(GameBalance.weapon_price(25, 5, 1.0), 33, "第 5 波 +8")
	_c.equals(GameBalance.weapon_price(25, 5, 0.8), 26, "散修 8 折取整")
	_c.equals(GameBalance.potion_price(WeaponData.POTION_BASE_PRICE, 5, 1.0), 15, "回气丹随波加价")
	_c.equals(GameBalance.reroll_cost(5, 0, 1.0), 7, "首次重掷 = 2+波次")
	_c.equals(GameBalance.reroll_cost(5, 2, 1.0), 11, "本波第 3 次重掷再 +4（递增随波缩放：5×0.4=2/次）")
	_c.equals(GameBalance.reroll_cost(5, 1, 1.0), 9, "第 2 次重掷 = 2+5+2")
	_c.equals(GameBalance.reroll_cost(5, 1, 0.8), 7, "重掷价也吃折扣（9×0.8 取整）")
	_c.equals(GameBalance.reroll_cost(1, 3, 1.0), 6, "第 1 波递增至少为 1（2+1+3×1）")
	_c.equals(GameBalance.reroll_cost(15, 1, 1.0), 23, "高波递增变陡（2+15+1×6）")

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

	# 回气丹回多少：货架卡、气血徽记拆解与 ShopSystem 的 heal() 三处共用这一条，
	# 卡上不许印一个兑现不了的量（缺血不够就按缺血截断，满血就是 0）
	_c.near(GameBalance.potion_heal_amount(120.0), 60.0, EPS, "名义量 = 上限 × POTION_HEAL_RATIO")
	_c.near(GameBalance.potion_heal_amount(0.0), 0.0, EPS, "空载（没有 Player）回 0，不出 NaN")
	_c.near(GameBalance.potion_effective_heal(120.0, 100.0), 20.0, EPS, "缺血 20 → 只回得上 20")
	_c.near(GameBalance.potion_effective_heal(120.0, 50.0), 60.0, EPS, "缺血够 → 回满名义量")
	_c.near(GameBalance.potion_effective_heal(120.0, 120.0), 0.0, EPS, "满血 → 0（买就是白花钱）")
	_c.near(GameBalance.potion_effective_heal(0.0, 0.0), 0.0, EPS, "空载 → 0")
	# 危险档只有一把尺：HUD 血字与灵石阁徽记都走 hp_is_low，阈值挪了两边一起动
	_c.check(GameBalance.hp_is_low(30.0, 120.0), "剩 25% 算危险（低于 HP_LOW_RATIO）")
	_c.check(not GameBalance.hp_is_low(40.0, 120.0), "剩 33% 不算危险")
	_c.check(not GameBalance.hp_is_low(30.0, 0.0), "空载（上限 0）不许报危险，也不许除零")
	_c.check(GameBalance.hp_is_full(119.6, 120.0), "差半点在四舍五入内算满血")
	_c.check(not GameBalance.hp_is_full(119.0, 120.0), "差 1 点不算满血")

func _test_tag_affinity() -> void:
	# 梯度亲和（2026-10-11 拓充）：不足门槛恒 1，≥2 件进一档 ×L1，≥4 件进二档 ×L2
	_c.near(GameBalance.tag_affinity_mult(0), 1.0, EPS, "未持有 → 无亲和")
	_c.near(GameBalance.tag_affinity_mult(1), 1.0, EPS, "1 件未达 MIN_COPIES → 无亲和")
	_c.near(GameBalance.tag_affinity_mult(2), GameBalance.TAG_AFFINITY_MULT_L1, EPS, "2 件 → 一档 ×L1")
	_c.near(GameBalance.tag_affinity_mult(3), GameBalance.TAG_AFFINITY_MULT_L1, EPS, "3 件仍是一档")
	_c.near(GameBalance.tag_affinity_mult(4), GameBalance.TAG_AFFINITY_MULT_L2, EPS, "4 件 → 二档 ×L2")
	_c.near(GameBalance.tag_affinity_mult(9), GameBalance.TAG_AFFINITY_MULT_L2, EPS, "更多件不超二档")
	# 双流派共鸣：最高档全额，其余已激活流派按 COMBO_DAMP 半价叠加（剑系∩金系交叉吸力）
	_c.near(GameBalance.tag_affinity_combo({}, ["sword", "metal"]), 1.0, EPS, "无持有 → 共鸣恒 1")
	_c.near(GameBalance.tag_affinity_combo({"sword": 4}, ["sword", "metal"]), GameBalance.TAG_AFFINITY_MULT_L2, EPS, "单流派激活 → 只有该档，不凭空加成")
	_c.near(GameBalance.tag_affinity_combo({"sword": 4, "metal": 4}, ["sword", "metal"]),
		GameBalance.TAG_AFFINITY_MULT_L2 * (1.0 + (GameBalance.TAG_AFFINITY_MULT_L2 - 1.0) * GameBalance.TAG_AFFINITY_COMBO_DAMP),
		EPS, "双流派均二档 → 交叉法器 ×6 反超单流派 ×3")
	_c.near(GameBalance.tag_affinity_combo({"sword": 2, "metal": 4}, ["sword", "metal"]),
		GameBalance.TAG_AFFINITY_MULT_L2 * (1.0 + (GameBalance.TAG_AFFINITY_MULT_L1 - 1.0) * GameBalance.TAG_AFFINITY_COMBO_DAMP),
		EPS, "二档+一档 → 最高全额 + 次高档半价 = ×4.5")
	_c.near(GameBalance.tag_affinity_combo({"sword": 2, "metal": 2}, ["sword", "metal"]),
		GameBalance.TAG_AFFINITY_MULT_L1 * (1.0 + (GameBalance.TAG_AFFINITY_MULT_L1 - 1.0) * GameBalance.TAG_AFFINITY_COMBO_DAMP),
		EPS, "双一档 → ×3")
	# 雷火符三 tag（符箓+雷法+火）：两个流派已激活即触发，第三个未激活不掺和
	_c.near(GameBalance.tag_affinity_combo({"thunder": 4, "fire": 4}, ["talisman", "thunder", "fire"]),
		GameBalance.TAG_AFFINITY_MULT_L2 * (1.0 + (GameBalance.TAG_AFFINITY_MULT_L2 - 1.0) * GameBalance.TAG_AFFINITY_COMBO_DAMP),
		EPS, "三 tag 只结算已激活的两个")
	# 共鸣必须严格大于任何单一亲和，否则交叉武器吸不动
	_c.check(GameBalance.tag_affinity_combo({"sword": 4, "metal": 4}, ["sword", "metal"]) > GameBalance.TAG_AFFINITY_MULT_L2,
		"双二档共鸣 > 单二档亲和（交叉格子必须更吸）")

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
	# 刷怪预算补差（2026-10-11）：预算没花完的部分波末折经验找平，减潮不减收入
	_c.equals(GameBalance.budget_compensation_exp(0, 2.0), 0, "预算零未刷出 → 零补差")
	_c.equals(GameBalance.budget_compensation_exp(-3, 2.0), 0, "负差额按 0 收")
	_c.equals(GameBalance.budget_compensation_exp(10, 0.0), 20, "均值缺失落兜底 2")
	_c.equals(GameBalance.budget_compensation_exp(10, 1.5), 15, "均值生效：10 只 × 1.5")
	_c.equals(GameBalance.budget_compensation_exp(7, 2.4), 17, "四舍五入：16.8 → 17")

## 提前清场余时赏（2026-10-12 用户口径「提前杀完还在干等，余下的时间该多给点金币」）：
## 按余秒折金币、向下取整、有封顶。只给金币这条不在这里量（是给账还是给账由
## tests/EarlyClearCheck 从生产入口差分）。
func _test_early_clear_bonus() -> void:
	_c.equals(GameBalance.early_clear_stones(0.0), 0, "表走完（余 0 秒）不给余时赏")
	_c.equals(GameBalance.early_clear_stones(-4.0), 0, "负余秒按 0 收")
	_c.equals(GameBalance.early_clear_stones(0.9), 0, "不足 1 秒不凑整")
	_c.equals(GameBalance.early_clear_stones(13.7), 13, "余 13.7 秒 = 13 枚（截图那一格 0:13）")
	_c.equals(GameBalance.early_clear_stones(float(GameBalance.EARLY_CLEAR_STONES_MAX)),
		GameBalance.EARLY_CLEAR_STONES_MAX, "余秒刚好触顶")
	_c.equals(GameBalance.early_clear_stones(999.0), GameBalance.EARLY_CLEAR_STONES_MAX,
		"封顶：无尽长波也不会滚成巨款")
	var prev := 0
	var mono := true
	for s in range(0, 40):
		var v := GameBalance.early_clear_stones(float(s))
		if v < prev:
			mono = false
		prev = maxi(prev, v)
	_c.check(mono, "余时赏随余秒单调不减（0~39 秒）")
	_c.check(GameBalance.early_clear_stones(19) > GameBalance.early_clear_stones(5),
		"多杀 14 秒确实多给钱（5 枚 → 19 枚）")
	# 量级：一波提前 20s 收尾的那笔，要「一点点」而不是「再打半波」
	_c.check(GameBalance.EARLY_CLEAR_STONES_MAX <= GameBalance.wave_spawn_budget(10),
		"封顶不超过第 10 波的刷怪只数（%d ≤ %d）：余时赏是添头，不是第二条击杀收入" % [
			GameBalance.EARLY_CLEAR_STONES_MAX, GameBalance.wave_spawn_budget(10)])

## 碎金档（2026-10-13 体验重塑）：普通怪按波次概率掉基础碎金/金砂片，
## 只砍金币腿不砍经验腿。第 1 波起步 50% 成为最常掉落物品，平滑递增至 70% 封顶。
func _test_gem_shard() -> void:
	# 碎金率曲线：第 0 波（选人/结算态）为 0；第 1 波起从基准 50% 起步（最常见掉落），随后单调上升，封顶 70%
	_c.near(GameBalance.gem_shard_chance(0), 0.0, EPS, "第 0 波（选人/结算态）不 roll 碎金")
	_c.near(GameBalance.gem_shard_chance(1), GameBalance.GEM_SHARD_BASE_CHANCE, EPS,
		"第 1 波起步 %.2f（碎金最容易掉落）" % GameBalance.GEM_SHARD_BASE_CHANCE)
	_c.check(GameBalance.gem_shard_chance(2) > GameBalance.gem_shard_chance(1), "第 2 波概率高于第 1 波")
	var prev := -1.0
	var mono := true
	for w in range(1, 60):
		var p := GameBalance.gem_shard_chance(w)
		if p < prev:
			mono = false
		prev = p
	_c.check(mono, "碎金率 1~59 波单调不减")
	_c.near(GameBalance.gem_shard_chance(999), GameBalance.GEM_SHARD_CHANCE_CAP, EPS,
		"无尽波次封顶 %.2f：保留约三成大灵石/高光" % GameBalance.GEM_SHARD_CHANCE_CAP)
	# 量级钉：第 20 波的碎金率在六成半以上
	_c.check(GameBalance.gem_shard_chance(20) > 0.65, "W20 碎金率已超六成五（实测 %.2f）" % GameBalance.gem_shard_chance(20))

	# 购买力硬护栏：第 1 波击杀期望金币必须能买得起首波基础武器（原价 25）
	# 2026-10-15 分批清剿制：W1 预算 10 只，单怪 exp_reward 基准 3 × MOB_KILL_EXP_MULT(1.75) = 5.25
	#（实际取整为 5），50% 碎金(1) + 50% 灵石(5) = 期望 3.0/只，10 × 3.0 = 30.0 ≥ 25
	var w1_kills: int = GameBalance.wave_spawn_budget(1)
	var w1_unit_exp := float(GameBalance.mob_kill_exp(3))
	var w1_expected_stones: float = float(w1_kills) * ((1.0 - GameBalance.gem_shard_chance(1)) * w1_unit_exp + GameBalance.gem_shard_chance(1) * 1.0)
	_c.check(w1_expected_stones >= 25.0,
		"W1 击杀期望金币 %.1f ≥ 25（确保首回合稳买基础武器）" % w1_expected_stones)

	# 入账分离：stone_amount 缺省 = 旧行为（灵石=经验原价）；显式传值只改金币腿。
	# 每段单独 reset + 4×1.5=6 低于升级门槛 10，不触发扣减（与 unit_content 悟性判据同一口径）。
	GameManager.reset_run()
	GameManager.xp_gain_mult = 1.5
	var xp0 := GameManager.experience
	var st0 := GameManager.spirit_stones
	GameManager.add_experience(4)
	_c.equals(GameManager.experience - xp0, 6, "缺省入参：经验 ×悟性 1.5 → 4×1.5=6")
	_c.equals(GameManager.spirit_stones - st0, 4, "缺省入参：灵石按原价入账（旧契约不破坏）")
	GameManager.reset_run()
	GameManager.xp_gain_mult = 1.5
	var xp1 := GameManager.experience
	var st1 := GameManager.spirit_stones
	GameManager.add_experience(4, GameBalance.GEM_SHARD_STONE_VALUE)
	_c.equals(GameManager.experience - xp1, 6, "碎金：经验腿仍足额 ×悟性（升级节奏不动）")
	_c.equals(GameManager.spirit_stones - st1, GameBalance.GEM_SHARD_STONE_VALUE, "碎金：金币腿只进 1 枚")
	GameManager.reset_run()
	var st2 := GameManager.spirit_stones
	GameManager.add_experience(4, -3)
	_c.equals(GameManager.spirit_stones - st2, 4, "负 stone_amount 回落原价口径（-1 约定不破坏）")
	GameManager.xp_gain_mult = 1.0
	GameManager.reset_run()

func _test_rarity_weights() -> void:
	# 四档模型：稀有第 1 波基础 30；史诗第 5 波、传说第 11 波才解锁；普通取余
	var base: Dictionary = GameBalance.rarity_weights(0.0, 1)
	_c.near(base["rare"], 30.0, EPS, "第 1 波稀有权重 30")
	_c.near(base["epic"], 0.0, EPS, "第 1 波史诗未解锁")
	_c.near(base["legendary"], 0.0, EPS, "第 1 波传说未解锁")
	_c.near(base["common"], 70.0, EPS, "普通取余托底")
	var w4: Dictionary = GameBalance.rarity_weights(0.0, 4)
	_c.near(w4["epic"], 0.0, EPS, "第 4 波史诗仍未解锁（第 5 波起）")
	_c.near(w4["rare"], 32.4, EPS, "稀有随波缓升（30+0.8×3）")
	var late: Dictionary = GameBalance.rarity_weights(0.0, 20)
	_c.near(late["rare"], 45.0, EPS, "第 20 波稀有触顶 45")
	_c.near(late["epic"], 28.0, EPS, "第 20 波史诗触顶 28")
	_c.near(late["legendary"], 10.8, EPS, "第 20 波传说 1.2×9=10.8")
	_c.near(late["common"], 16.2, EPS, "普通 = 100 − 其余三档")
	_c.near(float(late["common"]) + float(late["rare"]) + float(late["epic"]) + float(late["legendary"]), 100.0, EPS, "四档之和恒为 100")
	# 福缘乘区：×(1+福缘/100)，但被各档上限封住
	var lucky: Dictionary = GameBalance.rarity_weights(100.0, 20)
	_c.near(lucky["epic"], 28.0, EPS, "百点福缘史诗被 28 上限封住")
	_c.near(lucky["legendary"], 12.0, EPS, "百点福缘传说被 12 上限封住")
	_c.check(float(lucky["common"]) >= GameBalance.RARITY_COMMON_FLOOR, "普通档不会跌穿地板")
	_c.near(GameBalance.rarity_weights(-5.0, 20)["epic"], 28.0, EPS, "负福缘不会倒扣（乘区地板 1.0）")
	var mid_luck: Dictionary = GameBalance.rarity_weights(50.0, 12)
	_c.near(mid_luck["legendary"], 1.8, EPS, "第 12 波 50 福缘：传说 1.2×1.5=1.8")

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

	# 读数必须与结算同一把尺子：门槛下移后 UI 不许再拿原表 2/4/6 报进度
	# （2026-10-11 商店顶栏「召唤 (6/5)」：满档只要 5 件，第 6 件照拿，件数比满了的分母还大，
	#  看着像数值溢出；同一角色在货架卡上又被提示「5/6 再买一件」，两头都差一件）
	GameManager.reset_run()
	GameManager.spirit_threshold_adj = 1
	GameManager.drones = [1, 1, 1, 1, 1]   # 5 只灵蝶：下移后正好满档
	GameManager.recalc_synergies()
	_c.equals(int(GameManager.active_synergies["spirit"]["level"]), 3, "门槛 -1 后 5 件即满档")
	_c.equals(SynergyUI.progress("spirit")["max_th"], 5, "满档门槛取下移后的 5")
	_c.equals(SynergyUI.progress("wood")["max_th"], 6, "没有门槛加成的流派仍是 6")
	_c.equals(SynergyUI.progress_text("spirit"), "召唤 (5/MAX)", "满档徽记写 MAX，不写 5/5")
	_c.equals(SynergyUI.badge("spirit", 5)["text"], "召唤 5/MAX", "货架卡：5 件已满档（旧写法报 5/6）")
	_c.equals(SynergyUI.badge("spirit", 4)["text"], "召唤 4/5", "货架卡下一档取下移后的 5（旧写法报 4/6）")
	_c.check(bool(SynergyUI.badge("spirit", 4)["hot"]), "4 件时买第 5 件正好满档 ⇒ 临门一档亮绿（旧写法不亮）")
	_c.check(not bool(SynergyUI.badge("spirit", 5)["hot"]), "已满档不再亮临门一档")
	GameManager.drones = [1, 1, 1, 1, 1, 1]   # 第 6 件：件数超过满档门槛，档位不再涨
	GameManager.recalc_synergies()
	_c.equals(int(GameManager.active_synergies["spirit"]["level"]), 3, "6 件仍是满档，不溢出")
	_c.equals(SynergyUI.progress_text("spirit"), "召唤 (6/MAX)", "6 件不写成 6/5")
	_c.check(not SynergyUI.progress_text("spirit").contains("/5)"), "读数里不再出现已作废的满档分母")
	# 折算只留一处：整族流派的下移与「下一档」都由 GameBalance 这两个纯函数说
	_c.check(GameBalance.synergy_thresholds([2, 4, 6], 1) == [1, 3, 5], "门槛表逐档 -1")
	_c.check(GameBalance.synergy_thresholds([2, 4, 6], 3) == [1, 1, 3], "逐档各减 3，封在 1 件（前两档并档）")
	_c.equals(GameBalance.synergy_next_threshold(4, [2, 4, 6], 1), 5, "下移后下一档是 5")
	_c.equals(GameBalance.synergy_next_threshold(5, [2, 4, 6], 1), 0, "0 = 已满档")
	_c.equals(GameBalance.synergy_next_threshold(3, [2, 4, 6]), 4, "无下移时下一档是 4")
	GameManager.reset_run()

func _test_shop_determinism() -> void:
	GameManager.reset_run()
	GameManager.wave_number = 6
	GameManager.rng.seed = 1234567
	GameManager.roll_shop(true)
	var first: Array = GameManager.shop_offers.duplicate(true)
	_c.equals(GameManager.shop_offers.size(), GameManager.SHOP_BASE_SLOTS, "货架固定 %d 个位" % GameManager.SHOP_BASE_SLOTS)
	for offer in first:
		_c.check(offer.get("kind", "") in ["weapon", "potion", "item", "pet"], "货架项类型合法：%s" % str(offer.get("kind", "")))
		_c.check(int(offer.get("price", 0)) > 0, "货架项价格大于 0：%s" % str(offer.get("id", "")))

	# 价格必须等于公式值，不能有第二套算法
	for offer in first:
		match String(offer.get("kind", "")):
			"weapon":
				var base := int(WeaponData.get_def(offer["id"]).get("price", 20))
				_c.equals(int(offer["price"]), GameBalance.weapon_price(base, 6, GameManager.shop_price_mult), "法器价与 GameBalance 一致（%s）" % offer["id"])
			"item":
				var ibase := int(ItemData.get_def(offer["id"]).get("price", 20))
				_c.equals(int(offer["price"]), GameBalance.item_price(ibase, 6, GameManager.shop_price_mult), "法宝价与 GameBalance 一致（%s）" % offer["id"])
			"pet":
				var pbase := int(PetData.get_def(offer["id"]).get("base_price", 35))
				_c.equals(int(offer["price"]), GameBalance.pet_price(pbase, 6, GameManager.shop_price_mult), "灵兽价与 GameBalance 一致（%s）" % offer["id"])
			_:
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
