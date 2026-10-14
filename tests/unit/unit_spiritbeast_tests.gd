class_name UnitSpiritBeastTests
extends UnitTestsBase

## 祭坛灵兽数值单测（2026-10-11 远程吐息重做）：钉 BalanceSpiritBeast 纯函数与 GameBalance 转发。
## 行为判据（召唤/嘲讽/吐息/承伤/跨波存活）在 tests/SpiritBeastCheck.tscn。

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
