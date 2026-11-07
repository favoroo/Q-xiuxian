class_name UnitSpiritBeastTests
extends UnitTestsBase

## 祭坛灵兽数值单测（2026-10-11 远程吐息重做；2026-10-25 祭坛金币启动 + 寿命重设计）：
## 钉 BalanceSpiritBeast / BalanceEconomy / BalanceCombat 纯函数与 GameBalance 转发。
## 行为判据（召唤/嘲讽/吐息/承伤/跨波存活/寿命）在 tests/SpiritBeastCheck.tscn。

func _test_spirit_beast_scaling() -> void:
	# 气血/伤害成长：单调递增、1 波取基准值、0 波钳到 1 波（不出 NaN/回落）
	_c.near(GameBalance.spirit_beast_max_hp(1), BalanceSpiritBeast.BASE_HP, EPS, "灵兽气血：1 波取基准")
	_c.near(GameBalance.spirit_beast_damage(1), BalanceSpiritBeast.BASE_DAMAGE, EPS, "灵兽伤害：1 波取基准")
	_c.check(GameBalance.spirit_beast_max_hp(10) > GameBalance.spirit_beast_max_hp(1), "灵兽气血：随波次成长")
	_c.check(GameBalance.spirit_beast_damage(10) > GameBalance.spirit_beast_damage(1), "灵兽伤害：随波次成长")
	_c.near(GameBalance.spirit_beast_max_hp(0), GameBalance.spirit_beast_max_hp(1), EPS, "灵兽气血：0 波钳到 1 波")
	_c.near(GameBalance.spirit_beast_damage(-3), GameBalance.spirit_beast_damage(1), EPS, "灵兽伤害：负波钳到 1 波")
	# 成长必须低于敌人（1.16），否则后期灵兽死不掉，「血量耗尽即散」就成空话
	_c.check(BalanceSpiritBeast.HP_GROWTH < BalanceWave.ENEMY_HP_GROWTH, "灵兽气血成长低于敌人成长（后期会被磨死）")

func _test_obelisk_economy_and_lifetime() -> void:
	# 启动价（2026-10-25 重设计）：1 波取基准、随波线性 +3、0/负波钳到 1 波
	# 2026-10-30：本局第一次启动免费（已启动 0 次 ⇒ 0 金币，与波次无关）
	_c.equals(GameBalance.obelisk_activation_cost(1, 0), 0, "祭坛启动价：本局首次启动免费")
	_c.equals(GameBalance.obelisk_activation_cost(20, 0), 0, "祭坛启动价：首次免费与波次无关")
	_c.equals(GameBalance.obelisk_activation_cost(1, 1), BalanceEconomy.OBELISK_COST_BASE, "祭坛启动价：第二次起 1 波取基准")
	_c.equals(GameBalance.obelisk_activation_cost(20, 1),
		BalanceEconomy.OBELISK_COST_BASE + 19 * BalanceEconomy.OBELISK_COST_WAVE_STEP, "祭坛启动价：每波线性 +3")
	_c.equals(GameBalance.obelisk_activation_cost(0, 1), GameBalance.obelisk_activation_cost(1, 1), "祭坛启动价：0 波钳到 1 波")
	_c.equals(GameBalance.obelisk_activation_cost(-5, 1), GameBalance.obelisk_activation_cost(1, 1), "祭坛启动价：负波钳到 1 波")
	# 启动价量级护栏：开局一波收入（约 81）付得起一次启动，但不能付得起两次
	_c.check(GameBalance.obelisk_activation_cost(1, 1) >= 30 and GameBalance.obelisk_activation_cost(1, 1) <= 60,
		"祭坛启动价落在「值得斟酌但不卡死」档（30~60）")
	# 释放伤害/击退（随波成长）：1 波取基准、随波递增、缓于敌血复利（相对威力缓降）
	_c.near(GameBalance.obelisk_blessing_damage(1), BalanceCombat.OBELISK_DAMAGE_BASE, EPS, "祭坛释放伤害：1 波取基准")
	_c.check(GameBalance.obelisk_blessing_damage(10) > GameBalance.obelisk_blessing_damage(1), "祭坛释放伤害：随波次成长")
	_c.check(BalanceCombat.OBELISK_DAMAGE_GROWTH < BalanceWave.ENEMY_HP_GROWTH,
		"祭坛伤害成长缓于敌血复利（后期灵兽价值 > 伤害价值）")
	_c.check(GameBalance.obelisk_knock_force(10) > GameBalance.obelisk_knock_force(1), "祭坛击退：随波次成长")
	# 按最大生命附加分量 + 斩杀线（2026-10-26 新增：让后期祭坛对厚血单位仍有交代）
	_c.near(GameBalance.obelisk_blessing_hp_ratio(1), BalanceCombat.OBELISK_HP_RATIO_BASE, EPS,
		"祭坛按生命附加比例：1 波取基准")
	_c.near(GameBalance.obelisk_blessing_hp_ratio(20),
		BalanceCombat.OBELISK_HP_RATIO_BASE + 19.0 * BalanceCombat.OBELISK_HP_RATIO_WAVE_STEP, EPS,
		"祭坛按生命附加比例：每波线性 +0.5%")
	_c.check(GameBalance.obelisk_blessing_hp_ratio(20) > GameBalance.obelisk_blessing_hp_ratio(1),
		"祭坛按生命附加比例：随波次成长")
	_c.check(GameBalance.obelisk_blessing_hp_ratio(1) <= 0.05 and GameBalance.obelisk_blessing_hp_ratio(20) <= 0.15,
		"祭坛按生命附加比例：W1≤5%、W20≤15%（避免一刀直接削掉小怪整管血）")
	_c.near(GameBalance.obelisk_execute_threshold(1), BalanceCombat.OBELISK_EXECUTE_BASE, EPS,
		"祭坛斩杀线：1 波取基准")
	_c.near(GameBalance.obelisk_execute_threshold(20),
		BalanceCombat.OBELISK_EXECUTE_BASE + 19.0 * BalanceCombat.OBELISK_EXECUTE_WAVE_STEP, EPS,
		"祭坛斩杀线：每波线性 +0.4%")
	_c.check(GameBalance.obelisk_execute_threshold(1) < GameBalance.BOSS_PHASE2_AT,
		"祭坛斩杀线 < Boss 二阶段触发线（不会绕过二阶段）")
	_c.check(GameBalance.obelisk_execute_threshold(20) < GameBalance.BOSS_PHASE2_AT,
		"祭坛斩杀线 W20 仍 < Boss 二阶段线")
	_c.check(GameBalance.obelisk_execute_threshold(20) < BalanceWave.ELITE_MUTATION_HP_PCT,
		"祭坛斩杀线 < 精英变异触发线（不会绕过变异）")
	# 寿命与同场上限（2026-10-25 重设计）
	_c.equals(GameBalance.SPIRIT_BEAST_LIFETIME_WAVES, BalanceSpiritBeast.LIFETIME_WAVES, "灵兽寿命常量转发一致")
	_c.equals(GameBalance.SPIRIT_BEAST_MAX_ACTIVE, BalanceSpiritBeast.MAX_ACTIVE, "灵兽同场上限常量转发一致")
	_c.check(BalanceSpiritBeast.LIFETIME_WAVES >= 2, "灵兽寿命至少 2 回合（不然顶替机制没意义）")
	_c.check(BalanceSpiritBeast.MAX_ACTIVE == ProceduralDroneRenderer.PALETTES.size(),
		"同场上限与配色档数一致（每只在场灵兽都能分到独占配色）")

func _test_spirit_beast_palette() -> void:
	# 三套配色（2026-10-25）：档位取值有界、选档不撞色、最小未占用回落
	_c.check(ProceduralDroneRenderer.PALETTES.size() >= 2, "灵珑配色至少两套（同场要分得开）")
	_c.near(ProceduralDroneRenderer.body_color(0).r, ProceduralDroneRenderer.PALETTES[0]["body"].r, EPS,
		"body_color(0) 即原灵青主色")
	_c.equals(ProceduralDroneRenderer.pick_palette_idx([]), 0, "场上无灵兽：取 0 档")
	# 用真实例（不进树，不跑 _ready）验选档：占用 0 取 1，占用 1/2 回落 0
	var b0 := SpiritBeast.new()
	b0.palette_idx = 0
	var b1 := SpiritBeast.new()
	b1.palette_idx = 1
	var b2 := SpiritBeast.new()
	b2.palette_idx = 2
	_c.equals(ProceduralDroneRenderer.pick_palette_idx([b0]), 1, "0 档被占：取 1 档")
	_c.equals(ProceduralDroneRenderer.pick_palette_idx([b1, b2]), 0, "1/2 档被占：回落 0 档（最小未占用）")
	b0.free()
	b1.free()
	b2.free()

func _test_spirit_beast_constants() -> void:
	# 嘲讽半径/受击无敌帧是机制成立的前提：没了它们灵兽既不扛伤也瞬间蒸发
	_c.check(GameBalance.SPIRIT_BEAST_TAUNT_RADIUS > 0.0, "嘲讽半径为正")
	_c.check(GameBalance.SPIRIT_BEAST_HIT_INVINCIBLE > 0.0, "受击无敌帧为正（近身啃咬逐帧结算，没它一秒磨没）")
	_c.check(GameBalance.SPIRIT_BEAST_ATTACK_INTERVAL > 0.0, "吐息冷却为正")
	# 三连灵羽弹（2026-10-15 重做）：连发数 >1 才有「三连」、连发间隔必须小于一轮冷却、蓄力时间为正
	_c.check(GameBalance.SPIRIT_BEAST_BURST_COUNT >= 2, "三连灵羽弹：一轮至少两发")
	_c.check(GameBalance.SPIRIT_BEAST_BURST_GAP > 0.0 and GameBalance.SPIRIT_BEAST_BURST_GAP < GameBalance.SPIRIT_BEAST_ATTACK_INTERVAL, "连发间隔在 (0, 一轮冷却) 内")
	_c.check(GameBalance.SPIRIT_BEAST_CHARGE_TIME > 0.0 and GameBalance.SPIRIT_BEAST_CHARGE_TIME < GameBalance.SPIRIT_BEAST_ATTACK_INTERVAL, "蓄力时间在 (0, 一轮冷却) 内")
	_c.check(GameBalance.SPIRIT_BEAST_MOVE_ACCEL > 0.0, "走位加速度为正（三段风筝平滑过渡）")
	# 风筝甜区：下沿必须严格小于上沿，且上沿大于敌人身位（甜区才有得站）
	_c.check(GameBalance.SPIRIT_BEAST_PREFER_RANGE_MIN > 0.0, "风筝甜区下沿为正")
	_c.check(GameBalance.SPIRIT_BEAST_PREFER_RANGE_MIN < GameBalance.SPIRIT_BEAST_PREFER_RANGE_MAX, "风筝甜区下沿小于上沿")
	_c.check(GameBalance.SPIRIT_BEAST_PROJECTILE_SPEED > 0.0, "丹弹飞行速度为正")
	_c.check(GameBalance.SPIRIT_BEAST_STRAFE_SPEED_RATIO > 0.0 and GameBalance.SPIRIT_BEAST_STRAFE_SPEED_RATIO < 1.0, "环绕移速占比在 (0,1)")
	_c.check(GameBalance.SPIRIT_BEAST_CONTACT_RANGE > 0.0, "近身啃咬判定距离为正")
	_c.check(GameBalance.SPIRIT_BEAST_MOVE_SPEED > 110.0, "灵兽移速快过小怪基准（风筝甩得开近战怪）")

## 祭坛灵脉阶（2026-11-02 成长线）：波次阶/启动阶/max 兜底/封顶/阶数增益口径
func _test_obelisk_tier_growth() -> void:
	# 波次阶：每 5 波 +1，W1-5=1 / W6-10=2 / W11-15=3 / W16+=4
	_c.equals(BalanceObelisk.wave_tier(1), 1, "祭坛波次阶：W1=1")
	_c.equals(BalanceObelisk.wave_tier(5), 1, "祭坛波次阶：W5=1")
	_c.equals(BalanceObelisk.wave_tier(6), 2, "祭坛波次阶：W6=2（与天象阶段同拍）")
	_c.equals(BalanceObelisk.wave_tier(11), 3, "祭坛波次阶：W11=3")
	_c.equals(BalanceObelisk.wave_tier(16), 4, "祭坛波次阶：W16=4")
	_c.equals(BalanceObelisk.wave_tier(99), BalanceObelisk.MAX_TIER, "祭坛波次阶：封顶 MAX_TIER")
	_c.equals(BalanceObelisk.wave_tier(0), 1, "祭坛波次阶：0 波钳到 1")
	# 启动阶：累计成功启动 3/6/10 次分别到 2/3/4 阶
	_c.equals(BalanceObelisk.activation_tier(0), 1, "祭坛启动阶：0 次=1 阶")
	_c.equals(BalanceObelisk.activation_tier(2), 1, "祭坛启动阶：2 次仍 1 阶")
	_c.equals(BalanceObelisk.activation_tier(3), 2, "祭坛启动阶：3 次=2 阶")
	_c.equals(BalanceObelisk.activation_tier(5), 2, "祭坛启动阶：5 次仍 2 阶")
	_c.equals(BalanceObelisk.activation_tier(6), 3, "祭坛启动阶：6 次=3 阶")
	_c.equals(BalanceObelisk.activation_tier(10), 4, "祭坛启动阶：10 次=4 阶")
	_c.equals(BalanceObelisk.activation_tier(99), BalanceObelisk.MAX_TIER, "祭坛启动阶：封顶 MAX_TIER")
	# 最终阶 = max(波次阶, 启动阶)：投资提前，波次兜底
	_c.equals(BalanceObelisk.altar_tier(1, 0), 1, "祭坛阶：W1 未启动=1")
	_c.equals(BalanceObelisk.altar_tier(1, 3), 2, "祭坛阶：W1 启动 3 次提前到 2 阶")
	_c.equals(BalanceObelisk.altar_tier(16, 0), 4, "祭坛阶：不投资 W16 也靠波次到 4 阶")
	_c.equals(BalanceObelisk.altar_tier(99, 99), BalanceObelisk.MAX_TIER, "祭坛阶：上限封顶")
	_c.equals(GameBalance.obelisk_altar_tier(6, 0), 2, "GameBalance 转发祭坛阶一致")
	_c.equals(GameBalance.obelisk_tier_name(1), "一阶", "阶位中文名：一阶")
	_c.equals(GameBalance.obelisk_tier_name(4), "四阶", "阶位中文名：四阶")
	# 阶数增益单调，且斩杀线叠加后仍低于 Boss 二阶段/精英变异
	_c.check(BalanceObelisk.tier_damage_mult(1) == 1.0, "1 阶伤害乘区=1.0（基准不漂移）")
	_c.check(BalanceObelisk.tier_damage_mult(4) > BalanceObelisk.tier_damage_mult(1), "阶数伤害乘区单调递增")
	_c.check(BalanceObelisk.tier_knock_mult(4) > BalanceObelisk.tier_knock_mult(1), "阶数击退乘区单调递增")
	_c.check(GameBalance.obelisk_execute_threshold(20) + GameBalance.obelisk_tier_execute_bonus(4) < GameBalance.BOSS_PHASE2_AT,
		"4 阶 W20 斩杀线仍 < Boss 二阶段触发线")
	_c.check(GameBalance.obelisk_execute_threshold(20) + GameBalance.obelisk_tier_execute_bonus(4) < BalanceWave.ELITE_MUTATION_HP_PCT,
		"4 阶 W20 斩杀线仍 < 精英变异触发线")

## 灵兽分阶（2026-11-03 出生定格）：阶段 = 召唤时祭坛阶，不再随存活回合成长；
## 封顶/生命/伤害/体型/连发/穿透/接触半径仍按阶段表。
func _test_spirit_beast_stage_scaling() -> void:
	_c.equals(BalanceSpiritBeast.MAX_STAGE, 4, "灵兽最高 4 阶")
	_c.equals(BalanceSpiritBeast.birth_stage(1), 1, "出生阶段：1 阶祭坛→1 阶")
	_c.equals(BalanceSpiritBeast.birth_stage(2), 2, "出生阶段：2 阶祭坛→2 阶")
	_c.equals(BalanceSpiritBeast.birth_stage(3), 3, "出生阶段：3 阶祭坛→3 阶")
	_c.equals(BalanceSpiritBeast.birth_stage(4), 4, "出生阶段：4 阶祭坛→4 阶")
	_c.equals(BalanceSpiritBeast.birth_stage(9), BalanceSpiritBeast.MAX_STAGE, "出生阶段：封顶 4 阶")
	_c.equals(BalanceSpiritBeast.birth_stage(0), 1, "出生阶段：0 阶钳到 1")
	_c.equals(GameBalance.spirit_beast_birth_stage(3), 3, "GameBalance 转发出生阶段一致")
	# 阶段乘区单调 + 叠在波次成长上
	_c.check(BalanceSpiritBeast.stage_hp_mult(4) > BalanceSpiritBeast.stage_hp_mult(1), "阶段生命乘区单调递增")
	_c.check(BalanceSpiritBeast.stage_damage_mult(4) > BalanceSpiritBeast.stage_damage_mult(1), "阶段伤害乘区单调递增")
	_c.check(BalanceSpiritBeast.stage_body_scale(4) > BalanceSpiritBeast.stage_body_scale(1), "阶段体型缩放单调递增")
	_c.near(GameBalance.spirit_beast_max_hp(1, 1), BalanceSpiritBeast.BASE_HP, EPS, "1 阶 1 波生命取基准")
	_c.check(GameBalance.spirit_beast_max_hp(1, 4) > GameBalance.spirit_beast_max_hp(1, 1), "4 阶生命高于 1 阶（同波）")
	_c.check(GameBalance.spirit_beast_damage(1, 4) > GameBalance.spirit_beast_damage(1, 1), "4 阶伤害高于 1 阶（同波）")
	# 攻击质变：3 阶 4 连发、4 阶 5 连发 + 可命中 2 目标
	_c.equals(GameBalance.spirit_beast_burst_count(1), 3, "1 阶连发数=3")
	_c.equals(GameBalance.spirit_beast_burst_count(2), 3, "2 阶连发数=3")
	_c.equals(GameBalance.spirit_beast_burst_count(3), 4, "3 阶连发数=4")
	_c.equals(GameBalance.spirit_beast_burst_count(4), 5, "4 阶连发数=5")
	_c.equals(GameBalance.spirit_beast_pierce(3), 1, "3 阶穿透=1（单目标）")
	_c.equals(GameBalance.spirit_beast_pierce(4), 2, "4 阶穿透=2（可命中 2 个目标）")
	# 体型变大后近身/拥挤半径同步放大
	_c.check(GameBalance.spirit_beast_contact_range(4) > GameBalance.SPIRIT_BEAST_CONTACT_RANGE, "4 阶近身啃咬半径大于基础")
	_c.check(GameBalance.spirit_beast_crowd_radius(4) > GameBalance.SPIRIT_BEAST_CROWD_RADIUS, "4 阶拥挤半径大于基础")

## 血祭代价（2026-11-02）：最大生命 18%、至少 1 点
func _test_obelisk_blood_cost() -> void:
	_c.check(BalanceObelisk.BLOOD_HP_RATIO > 0.0 and BalanceObelisk.BLOOD_HP_RATIO < 0.5,
		"血祭比例在 (0,0.5)（不能一次烧掉半管血）")
	_c.equals(BalanceObelisk.blood_cost(100.0), 18, "血祭代价：100 血=18")
	_c.equals(BalanceObelisk.blood_cost(200.0), 36, "血祭代价：200 血=36")
	_c.equals(BalanceObelisk.blood_cost(55.0), 10, "血祭代价：55 血向上取整=10")
	_c.equals(BalanceObelisk.blood_cost(0.0), 1, "血祭代价：0 血上限也至少 1 点")
	_c.equals(GameBalance.obelisk_blood_cost(100.0), 18, "GameBalance 转发血祭代价一致")
