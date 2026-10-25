extends Node

## 闪避落地震开判据（2026-10-24）：
## 用户现场「闪到敌人面前，无敌时效一结束就立马吃接触伤」。冲刺 110px 且玩家碰撞层不收敌人
## （Player.tscn mask=1），落点常常正好压在怪身上；落地补一记「只推不伤」的震开，
## 把「落地即挨打」换成「有一拍脱身」。
##
## 钉住七件事：
##   1. 数据同源：final_stats("dash") 的 land_push_* 与数据表 DEFS 一致且 > 0；
##   2. 落点圈内敌人沿「远离落点」方向被推开（≥20px 且不失控），圈外纹丝不动；
##   3. 只推不伤：血量不变、_focus_hit_count 仍为 0（走了 take_damage 会给目标记一次集火保护，
##      把闪避落地那记必暴刀削到 70%，还会跳「0」字、放命中音）；
##   4. 落地当帧敌人带硬直（位移只走受击硬直滑行段，没硬直就没有位移）；
##   5. 无敌余量（~0.19s）走完时敌人仍在接触圈外 —— 把 move_speed 恢复成真实小怪速度也追不上；
##   6. 精英抗震开（位移明显小于普通怪，档位换算生效）；
##   7. 冲击环半径 == 判定半径（画多大 == 判多大）。
##
## 运行: godot --headless --path . res://tests/DashLandShoveCheck.tscn
## 退出码 0 且末行 DASH_LAND_SHOVE_RESULT: ALL PASS
##
## 坑（写判据时踩到的）：
##   - 视口终审：玩家必须在屏内（本判据不建主场景、没有相机，世界坐标 == 屏幕坐标），
##     摆在 (300,240) 附近；摆在屏幕外冲击环会被 _pos_in_viewport 静默丢弃，第 7 条会假绿；
##   - 敌群分离半径 60px：两个测试敌人要摆开，否则会被同伴顶开、污染位移读数；
##   - 纯接触怪的扑咬前摇/收势是锁定段（会把 knockback_velocity 清掉），判据里把 lunge 置空，
##     否则量到的是「扑咬锁定」而不是落地震开；
##   - 敌人不摆进冲刺走廊（横向偏 40px，> 玩家 14 + 史莱姆 18），避免玩家身体在冲刺途中先把它顶走。

const SPAWN := Vector2(300.0, 240.0)
const CONTACT := 32.0   ## 接触线：玩家身位 14 + 史莱姆身位 18

var _c := TestCheck.new()
var _normal_push := 0.0   ## 普通怪实测位移（精英档要拿它做对照）

func _ready() -> void:
	SettingsManager.set_val(&"display", &"hit_stop", false, false)
	GameManager.reset_run()
	await _test_data()
	await _test_land_shove()
	await _test_elite_resist()
	if _c.report("DASH_LAND_SHOVE_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

# ---------------- 公共摆位 ----------------

func _make_player() -> Player:
	var p: Player = load("res://scenes/entities/Player.tscn").instantiate() as Player
	add_child(p)
	p.global_position = SPAWN
	p.max_health = 99999.0
	p.current_health = 99999.0
	p.invulnerable_time = 0.0
	p.velocity = Vector2.ZERO
	p.facing = "s"            ## 无摇杆 + 无惯性 ⇒ 冲刺沿面朝方向（向下）
	p.skill_cd_left = 0.0
	p.skill_active_left = 0.0
	GameManager.player = p
	GameManager.is_game_over = false
	GameManager.active_skill_id = "dash"
	GameManager.wave_spawner = null   ## 无主场景：让 try_activate_skill 的「战斗中」门控放行
	return p

func _make_enemy(at: Vector2, elite: bool = false) -> EnemyBase:
	var e: EnemyBase = load("res://scenes/entities/SlimeEnemy.tscn").instantiate() as EnemyBase
	e.is_elite = elite
	add_child(e)
	e.global_position = at
	e.max_hp = 999999.0
	e.current_hp = 999999.0
	e.move_speed = 0.0        ## 不许自己凑过来污染读数
	e.contact_damage = 0.0    ## 接触伤害不参与本判据（量的是位移）
	e.lunge = null            ## 扑咬前摇/收势是锁定段，会把击退初速清掉
	return e

## 跑一次真实冲刺（走 try_activate_skill 生产入口），返回落地那一帧的玩家位置。
## 返回时落地震开已经在同一物理帧里执行过了。
func _run_dash(p: Player) -> Vector2:
	if not p.try_activate_skill():
		_c.fail("冲刺未能释放（前置：技能门控 / 战斗阶段）")
		return p.global_position
	var frames := 0
	while p._dash_time > 0.0 and frames < 60:
		await get_tree().physics_frame
		frames += 1
	return p.global_position

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

# ---------------- 1. 数据同源 ----------------

func _test_data() -> void:
	var def := SkillData.get_def("dash")
	var st := SkillData.final_stats("dash", "")
	for key in ["land_push_radius", "land_push_impulse", "land_push_stun"]:
		_c.check(def.has(key), "数据表 dash 带 %s（数值只进数据表）" % key)
		_c.near(float(st.get(key, -1.0)), float(def.get(key, 0.0)), 0.0001,
			"final_stats 透传 %s（与数据表同源）" % key)
		_c.check(float(st.get(key, 0.0)) > 0.0,
			"%s > 0（落地震开是常开行为，不是 0 值开关）" % key)

# ---------------- 2+3+4+5+7. 落地震开本体的全部读数 ----------------

func _test_land_shove() -> void:
	var p := _make_player()
	# 落点 ≈ SPAWN + (0, ~103)（实测 0.94×距离误差范围内）；圈内敌人摆在落点右侧 40px
	# （横向 40 > 接触线 32 ⇒ 冲刺途中玩家身体碰不到它）
	var near_enemy := _make_enemy(SPAWN + Vector2(40.0, 110.0))
	# 圈外对照：与落点相距 ~97px（> 判定半径 76），也与圈内怪相隔 ~98px（> 分离半径 60）
	var far_enemy := _make_enemy(SPAWN + Vector2(0.0, 200.0))
	var near_start: Vector2 = near_enemy.global_position
	var far_start: Vector2 = far_enemy.global_position
	var hp_before: float = near_enemy.current_hp
	var radius := float(SkillData.final_stats("dash", "")["land_push_radius"])

	var landed_at: Vector2 = await _run_dash(p)
	var stun_at_land: float = near_enemy.hit_stun_timer
	var dist_at_land: float = near_enemy.global_position.distance_to(landed_at)
	for i in range(24):
		await get_tree().physics_frame

	var moved: float = near_enemy.global_position.distance_to(near_start)
	_normal_push = moved
	_c.check(moved >= 20.0, "圈内敌人被落地震开（实测位移 %.1f px）" % moved)
	_c.check(moved <= 80.0, "推开幅度没有失控（实测 %.1f px ≤ 80）" % moved)
	var away_from_land: Vector2 = (near_start - landed_at).normalized()
	var push_dir: Vector2 = (near_enemy.global_position - near_start).normalized()
	_c.check(push_dir.dot(away_from_land) > 0.5,
		"推开方向远离落点（与径向夹角余弦 %.2f）" % push_dir.dot(away_from_land))
	_c.check(is_equal_approx(near_enemy.current_hp, hp_before), "只推不伤：血量一格没掉")
	_c.check(near_enemy._focus_hit_count == 0,
		"只推不伤：不占同目标集火保护（走 take_damage 会被记一次，落地必暴刀变 70%）")
	_c.check(stun_at_land > 0.0, "落地当帧敌人被钉身（剩余 %.2f s，滑行段才有位移）" % stun_at_land)
	_c.check(far_enemy.global_position.distance_to(far_start) < 0.5,
		"圈外敌人纹丝不动（实测位移 %.2f px）" % far_enemy.global_position.distance_to(far_start))
	_c.near(_shockwave_radius(), radius, 0.01,
		"冲击环半径 == 判定半径 %.0f（画多大 == 判多大）" % radius)

	# 无敌余量走完那一刻：把敌人恢复成真实小怪速度，硬直应把它钉在接触圈外
	near_enemy.move_speed = 105.0
	var guard := 0
	while p.invulnerable_time > 0.0 and guard < 60:
		await get_tree().physics_frame
		guard += 1
	_c.check(dist_at_land > CONTACT,
		"落地即脱离接触圈（落点距离 %.1f px > %.0f）" % [dist_at_land, CONTACT])
	_c.check(p.global_position.distance_to(near_enemy.global_position) > CONTACT,
		"无敌结束那一刻敌人仍在接触圈外（距离 %.1f px > %.0f，硬直盖过了剩余无敌）" % [
			p.global_position.distance_to(near_enemy.global_position), CONTACT])

	near_enemy.queue_free()
	far_enemy.queue_free()
	p.queue_free()
	await get_tree().physics_frame

# ---------------- 6. 精英抗震开 ----------------

func _test_elite_resist() -> void:
	var p := _make_player()
	var elite := _make_enemy(SPAWN + Vector2(40.0, 110.0), true)
	var elite_start: Vector2 = elite.global_position
	await _run_dash(p)
	for i in range(24):
		await get_tree().physics_frame
	var moved: float = elite.global_position.distance_to(elite_start)
	_c.check(moved > 3.0, "精英也会被震开（实测 %.1f px > 3）" % moved)
	_c.check(_normal_push > 0.0 and moved < _normal_push * 0.7,
		"精英抗震开：位移明显小于普通怪（精英 %.1f px < 普通 %.1f × 0.7）" % [moved, _normal_push])
	elite.queue_free()
	p.queue_free()
	await get_tree().physics_frame
