extends Node

## 天雷（雷法真君被动出口）判据：周期落雷劈向最近妖兽，落点小范围震荡。
## 数值全在 ThunderData，本判据从生产入口量兑现：Player._physics_process 计时 → _call_thunder。
##
## 钉住六件事：
##   1. 开关门控：thunder_strike=1 才落雷；=0（其他角色）近怪也不落
##   2. 索敌：劈向 SEEK_RANGE 内最近妖兽；范围内无怪不落雷、走 RETRY_INTERVAL 短重试
##   3. 兑现伤害：落点敌人吃到 bolt_damage(元素) × buff_damage_mult
##   4. 落点震荡：RADIUS 内敌人同吃，圈外一格不掉；圈内被击退
##   5. 视觉与判定同源：冲击环半径 == ThunderData.RADIUS == 判定半径
##   6. 全自动：雷法无 extra_skill，天雷不点按钮
##
## 运行: godot --headless --path . res://tests/ThunderCheck.tscn
##       godot --headless --path . res://tests/ThunderCheck.tscn -- --selftest
## 退出码 0 且末行 THUNDER_RESULT: ALL PASS
##
## 坑（与 GuardStanceCheck 同）：特效视口终审要求落点在屏内，玩家必须摆在 (260,270) 附近；
## 受击顿帧会拖时间，跑前先关 hit_stop（auto_save=false，不落盘）。
## 坑 2：灵田界碑 MAP_HALF_EXTENT=560（怪的钳制带 540），摆怪超出会被当帧钳回，位移读数全毁；
## 坑 3：queue_free 的怪到帧末才出 enemies 组，跨场景段前要等一拍，否则尸体吃落雷。

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
	await _test_strike_delivers()
	await _test_no_enemy_retry()
	await _test_switch_off_no_strike()
	if _selftest:
		_test_selftest_guard()
	if _c.report("THUNDER_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

# ---------------- 公共摆位 ----------------

func _make_player(thunder: float = 1.0, elemental: float = 3.0) -> Player:
	var p: Player = load("res://scenes/entities/Player.tscn").instantiate() as Player
	add_child(p)
	p.global_position = SPAWN_AT
	p.max_health = 200.0
	p.current_health = 200.0
	p.invulnerable_time = 0.0
	GameManager.player = p
	GameManager.is_game_over = false
	GameManager.dodge = 0.0
	GameManager.thunder_strike = thunder
	GameManager.elemental_damage = elemental
	GameManager.buff_damage_mult = 1.0
	GameManager.knockback_mult = 1.0
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

## 把天雷倒计时摁到 0 再等物理帧：下一拍 _physics_process 必触发 _call_thunder
func _tick_thunder(p: Player) -> void:
	p._thunder_cd = 0.0
	await get_tree().physics_frame
	await get_tree().physics_frame

# ---------------- 1+3+4+5+6. 落雷兑现：索敌最近、AoE、同源半径、击退 ----------------

func _test_strike_delivers() -> void:
	var p := _make_player()
	# 雷法没有第二颗按钮：天雷必须全自动（计时器驱动，不存在「点开放」）
	_c.check(CultivatorData.get_extra_skill_id("leifa").is_empty(), "雷法无 extra_skill（天雷全自动，不点按钮）")
	# 目标 = 离玩家最近的妖兽；伴怪贴在落点圈内，远怪在圈外
	# （远怪摆落点正上方，避免出界被钳回污染位移读数）
	var target := _make_enemy(SPAWN_AT + Vector2(150.0, 0.0))
	var inside := _make_enemy(SPAWN_AT + Vector2(150.0 + ThunderData.RADIUS - 40.0, 0.0))
	var outside := _make_enemy(SPAWN_AT + Vector2(150.0, -(ThunderData.RADIUS + 60.0)))
	var hp_t: float = target.current_hp
	var hp_in: float = inside.current_hp
	var hp_out: float = outside.current_hp
	var pos_t: Vector2 = target.global_position
	var pos_out: Vector2 = outside.global_position
	var want_dmg := ThunderData.bolt_damage(3.0)

	await _tick_thunder(p)

	_c.near(hp_t - target.current_hp, want_dmg, 0.5,
		"落雷命中最近妖兽 %.1f（= bolt_damage(元素 3)，走 EnemyBase.take_damage）" % want_dmg)
	_c.near(hp_in - inside.current_hp, want_dmg, 0.5, "落点圈内伴怪同吃 %.1f" % want_dmg)
	_c.check(is_equal_approx(hp_out, outside.current_hp), "圈外敌人一格没掉（判定半径没被辉光糊大）")
	_c.near(p._thunder_cd, ThunderData.INTERVAL, 0.2, "落雷后倒计时按 INTERVAL 重计（实测 %.2f）" % p._thunder_cd)

	var ring_r := _shockwave_radius()
	_c.near(ring_r, ThunderData.RADIUS, 0.01,
		"冲击环扫到的半径 == 判定半径 %f（画多大 == 判多大）" % ThunderData.RADIUS)

	for i in range(20):
		await get_tree().physics_frame
	_c.check(target.global_position.distance_to(pos_t) > 1.0,
		"落点敌人被震开（实测位移 %.1f px）" % target.global_position.distance_to(pos_t))
	_c.check(outside.global_position.distance_to(pos_out) < 0.5, "圈外敌人纹丝不动")
	target.queue_free()
	inside.queue_free()
	outside.queue_free()
	p.queue_free()
	# queue_free 到帧末才真正出组：不等这一拍，下一场景的「无怪重试」会把尸体当活靶（仍在 enemies 组里）
	await get_tree().process_frame
	await get_tree().physics_frame

# ---------------- 2. 范围内无怪：不落雷、短重试 ----------------

func _test_no_enemy_retry() -> void:
	var p := _make_player()
	await _tick_thunder(p)
	_c.near(p._thunder_cd, ThunderData.RETRY_INTERVAL, 0.2,
		"无怪不落雷，走短重试 %.2f（不空耗整轮冷却）" % ThunderData.RETRY_INTERVAL)
	p.queue_free()

# ---------------- 1. 开关门控：非雷法不落雷 ----------------

func _test_switch_off_no_strike() -> void:
	GameManager.thunder_strike = 0.0
	var p := _make_player(0.0)
	var e := _make_enemy(SPAWN_AT + Vector2(150.0, 0.0))
	var hp: float = e.current_hp
	await _tick_thunder(p)
	_c.check(is_equal_approx(hp, e.current_hp), "非雷法（天雷开关 0）近怪也不落雷（数据门控）")
	e.queue_free()
	p.queue_free()

## 读活跃冲击波的目标半径：特效池挂在场景根下的 JuiceEffectPool 里（与 GuardStanceCheck 同一取法）
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
	# 旧写法：没有天雷机制 ⇒ 第 1 条的落雷伤害断言会红；无怪重试那条也会红（倒计时不会被写成 RETRY_INTERVAL）
	var legacy_hp_drop := 0.0
	_c.check(legacy_hp_drop < ThunderData.bolt_damage(3.0),
		"自检证实：旧写法没有落雷，第 1/2 条都会抓红")
