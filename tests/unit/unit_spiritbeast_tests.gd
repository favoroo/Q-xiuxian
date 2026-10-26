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
	_c.equals(GameBalance.obelisk_activation_cost(1), BalanceEconomy.OBELISK_COST_BASE, "祭坛启动价：1 波取基准")
	_c.equals(GameBalance.obelisk_activation_cost(20),
		BalanceEconomy.OBELISK_COST_BASE + 19 * BalanceEconomy.OBELISK_COST_WAVE_STEP, "祭坛启动价：每波线性 +3")
	_c.equals(GameBalance.obelisk_activation_cost(0), GameBalance.obelisk_activation_cost(1), "祭坛启动价：0 波钳到 1 波")
	_c.equals(GameBalance.obelisk_activation_cost(-5), GameBalance.obelisk_activation_cost(1), "祭坛启动价：负波钳到 1 波")
	# 启动价量级护栏：开局一波收入（约 81）付得起一次启动，但不能付得起两次
	_c.check(GameBalance.obelisk_activation_cost(1) >= 30 and GameBalance.obelisk_activation_cost(1) <= 60,
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
