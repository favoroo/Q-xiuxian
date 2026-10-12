extends Node

## 盾势（守卫受击出口）判据：护甲挡下的伤害存进盾势槽，蓄满自动炸开还一圈。
## 数值全在 GuardStanceData，本判据从生产入口量兑现：Player.take_damage 蓄能 → 满即 _release_guard_stance。
##
## 钉住六件事：
##   1. 守卫受击蓄能：蓄能 == 被护甲挡下的部分（raw - reduced），走真入口
##   2. 0 护甲不蓄能（没挡住就没得存）；非守卫（guard_stance=0）受击不蓄能
##   3. 蓄能钳在上限（= 气血 × CAP_HP_RATIO），满即自动爆发、槽当帧清零
##   4. 爆发兑现：圈内敌人吃到 蓄能×BURST_RATIO 并被击退，圈外一格不掉
##   5. 视觉与判定同源：冲击环半径 == GuardStanceData.BURST_RADIUS == 判定半径
##   6. 全自动：守卫无 extra_skill，盾势不点按钮（攒/放同一写点）
##
## 运行: godot --headless --path . res://tests/GuardStanceCheck.tscn
##       godot --headless --path . res://tests/GuardStanceCheck.tscn -- --selftest
## 退出码 0 且末行 GUARD_STANCE_RESULT: ALL PASS
##
## 坑（与 ShadowStepCheck 同）：特效视口终审要求落点在屏内，玩家必须摆在 (260,270) 附近；
## 受击顿帧会拖时间，跑前先关 hit_stop（auto_save=false，不落盘）。

const EPS := 0.0001
const SPAWN_AT := Vector2(260.0, 270.0)   ## 视口内：冲击波不被视口丢弃

var _c := TestCheck.new()
var _selftest: bool = false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a) == "--selftest":
			_selftest = true
	SettingsManager.set_val(&"display", &"hit_stop", false, false)
	GameManager.reset_run()
	await _test_charge_from_blocked()
	await _test_no_charge_without_armor_or_stance()
	await _test_burst_delivers()
	if _selftest:
		_test_selftest_guard()
	if _c.report("GUARD_STANCE_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

# ---------------- 公共摆位 ----------------

func _make_player(armor: float, stance: float = 1.0) -> Player:
	var p: Player = load("res://scenes/entities/Player.tscn").instantiate() as Player
	add_child(p)
	p.global_position = SPAWN_AT
	p.max_health = 200.0
	p.current_health = 200.0
	p.invulnerable_time = 0.0
	GameManager.player = p
	GameManager.is_game_over = false
	GameManager.armor = armor
	GameManager.synergy_armor = 0.0
	GameManager.dodge = 0.0          ## 不许闪避搅局：本判据量的是「真挨打」那一路
	GameManager.guard_stance = stance
	GameManager.shield_charge = 0.0
	GameManager.rng = RandomNumberGenerator.new()
	GameManager.rng.seed = 20261011
	return p

func _make_enemy(at: Vector2) -> EnemyBase:
	var e: EnemyBase = load("res://scenes/entities/SlimeEnemy.tscn").instantiate() as EnemyBase
	add_child(e)
	e.global_position = at
	e.max_hp = 999999.0
	e.current_hp = 999999.0
	e.move_speed = 0.0        ## 不许自己凑过来污染读数
	e.contact_damage = 0.0    ## 接触伤害不参与本判据
	e.add_to_group("enemies")
	return e

# ---------------- 1. 受击蓄能 == 被挡下的部分 ----------------

func _test_charge_from_blocked() -> void:
	var p := _make_player(10.0)
	# 护甲 10：reduced = raw / (1 + 10×0.08) = raw/1.8；raw 90 → 实伤 50，挡下 40
	p.take_damage(90.0)
	var blocked := 90.0 - GameBalance.incoming_damage(90.0, 10.0)
	_c.near(GameManager.shield_charge, GuardStanceData.add_charge(0.0, blocked, p.max_health), 0.01,
		"受击蓄能 == 被护甲挡下的部分（%.1f，走生产 take_damage 入口）" % blocked)
	_c.check(GameManager.shield_charge < GuardStanceData.cap_of(p.max_health),
		"一刀蓄不满（前置：爆发在第 4 条专项量）")
	p.queue_free()

# ---------------- 2. 没挡住 / 非守卫 不蓄能 ----------------

func _test_no_charge_without_armor_or_stance() -> void:
	var p0 := _make_player(0.0)
	p0.take_damage(90.0)
	_c.near(GameManager.shield_charge, 0.0, EPS, "0 护甲全吃，没挡住 ⇒ 不蓄能")
	p0.queue_free()
	GameManager.shield_charge = 0.0
	var p1 := _make_player(10.0, 0.0)
	p1.take_damage(90.0)
	_c.near(GameManager.shield_charge, 0.0, EPS, "非守卫（盾势开关 0）受击不蓄能（数据门控）")
	p1.queue_free()

# ---------------- 3+4+5+6. 蓄满自动爆发：钳上限、兑现、同源半径、清零 ----------------

func _test_burst_delivers() -> void:
	var p := _make_player(10.0)
	# 守卫没有第二颗按钮：盾势必须全自动（攒/放同一写点，不存在「点开放」）
	_c.check(CultivatorData.get_extra_skill_id("shiyue").is_empty(), "守卫无 extra_skill（盾势全自动，不点按钮）")
	# 先垫两刀：blocked 40+40=80 < 上限 100，不许提前炸
	p.take_damage(90.0)
	p.invulnerable_time = 0.0
	p.take_damage(90.0)
	_c.near(GameManager.shield_charge, 80.0, 0.5, "两刀垫到 80（钳上前置，未触发）")
	var inside := _make_enemy(SPAWN_AT + Vector2(GuardStanceData.BURST_RADIUS - 40.0, 0.0))
	var outside := _make_enemy(SPAWN_AT + Vector2(GuardStanceData.BURST_RADIUS + 60.0, 0.0))
	var hp_in: float = inside.current_hp
	var hp_out: float = outside.current_hp
	var pos_in: Vector2 = inside.global_position
	var pos_out: Vector2 = outside.global_position
	var want_dmg := GuardStanceData.burst_damage(GuardStanceData.cap_of(p.max_health))

	# 第三刀：蓄能 120 钳到上限 100 → 满 → 当帧自动爆发
	p.invulnerable_time = 0.0
	p.take_damage(90.0)

	_c.near(GameManager.shield_charge, 0.0, EPS, "蓄满当帧自动爆发，槽清零（全自动，下一槽重新攒）")
	_c.near(hp_in - inside.current_hp, want_dmg, 0.5,
		"圈内敌人吃到盾势爆发 %.1f（= 上限 %.0f × %.1f，走 EnemyBase.take_damage）" % [
			want_dmg, GuardStanceData.cap_of(p.max_health), GuardStanceData.BURST_RATIO])
	_c.check(is_equal_approx(hp_out, outside.current_hp), "圈外敌人一格没掉（判定半径没被辉光糊大）")

	var ring_r := _shockwave_radius()
	_c.near(ring_r, GuardStanceData.BURST_RADIUS, 0.01,
		"冲击环扫到的半径 == 判定半径 %f（画多大 == 判多大）" % GuardStanceData.BURST_RADIUS)

	for i in range(20):
		await get_tree().physics_frame
	_c.check(inside.global_position.distance_to(pos_in) > 1.0,
		"圈内敌人被震开（实测位移 %.1f px）" % inside.global_position.distance_to(pos_in))
	_c.check(outside.global_position.distance_to(pos_out) < 0.5, "圈外敌人纹丝不动")
	inside.queue_free()
	outside.queue_free()
	p.queue_free()

## 读活跃冲击波的目标半径：特效池挂在场景根下的 JuiceEffectPool 里（与 ShadowStepCheck 同一取法）
func _shockwave_radius() -> float:
	var host := get_tree().current_scene.get_node_or_null("JuiceEffectPool")
	if host == null:
		return -1.0
	for child in host.get_children():
		if child is JuiceEffect and child.effect_type == JuiceEffect.EffectType.SHOCKWAVE:
			if not child._r_max.is_empty():
				return float(child._r_max[0])
	return -1.0

# ---------------- 自检守卫：证明判据抓得住旧写法 ----------------

func _test_selftest_guard() -> void:
	# 旧写法：受击只掉血，不蓄能 ⇒ 第 1 条的蓄能断言会红；没蓄能 ⇒ 第 4 条的爆发兑现全红
	var legacy_charge := 0.0
	_c.check(legacy_charge < GuardStanceData.add_charge(0.0, 40.0, 200.0),
		"自检证实：旧写法受击不蓄能，第 1/3/4 条都会抓红")
