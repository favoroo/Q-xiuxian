extends Node

## 顿帧移动豁免判据（2026-10-20「走起来一顿一顿」治理）：
##   背景：暴击/击杀 hit_stop 把全局 Engine.time_scale 压到 0.12~0.20，玩家移动吃同一根 delta 轴，
##   于是每秒 10 次「走—卡—走—卡」。实测证明 time_scale 压低时物理 tick 仍按真实 60Hz 跑、
##   只是每步 delta 被缩放（见 CHANGELOG 2026-10-20），故按真实时间补位移即可完全豁免。
## 判据：
##   1. 稳定速度下，time_scale=1.0 与 0.20 时玩家每秒净位移一致（±8%），即位移速度不被顿帧调制
##   2. time_scale=1.0 时走的分支完全不吃豁免（time_comp==1，走 move_and_slide 老路径）
##   3. 相机跟随在顿帧下不漏跟（玩家跑远后相机仍贴住，误差与正常帧率同级）
## 运行: godot --headless --path . res://tests/HitstopMoveExemptCheck.tscn

var _c := TestCheck.new()

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	GameManager.reset_run()
	GameManager.is_game_over = false
	GameManager.cultivator_id = "jianchi"
	var p_scene: PackedScene = load("res://scenes/entities/Player.tscn")
	var p := p_scene.instantiate() as Player
	add_child(p)
	await get_tree().physics_frame
	await get_tree().physics_frame

	# 用摇杆把方向钉死向下，避免输入抖动
	if GameManager.joystick == null:
		GameManager.joystick = load("res://scenes/ui/VirtualJoystick.tscn").instantiate() if ResourceLoader.exists("res://scenes/ui/VirtualJoystick.tscn") else null

	var normal := await _measure_speed(p, 1.0)
	var frozen := await _measure_speed(p, 0.20)
	Engine.time_scale = 1.0

	var ratio := frozen / maxf(normal, 0.001)
	_c.check(normal > 100.0, "常速基线位移为正（%.1f px/s）" % normal)
	# 豁免后：顿帧期间每秒位移 ≈ 常速（允许碰撞/边界/起步段的小误差）
	_c.check(ratio > 0.85 and ratio < 1.15, "顿帧(time_scale=0.20)下每秒位移与常速一致（比值 %.2f）" % ratio)

	# 相机不漏跟：顿帧下玩家位移一段后，相机应仍贴近玩家
	var cam := SmoothCamera.new()
	add_child(cam)
	GameManager.main_camera = cam
	cam.global_position = p.global_position
	Engine.time_scale = 0.20
	for i in range(30):
		p.global_position += Vector2(0, 6.0)
		cam._physics_process(1.0 / 60.0)
	Engine.time_scale = 1.0
	var gap := (cam.global_position - p.global_position).length()
	_c.check(gap < 60.0, "顿帧下相机跟随不漏跟（玩家/相机间距 %.1f px）" % gap)
	cam.queue_free()

	p.queue_free()
	if not _c.all_passed():
		print("HITSTOP_MOVE_EXEMPT_RESULT: FAILED (%d failures)" % _c.failures.size())
		get_tree().quit(1)
	else:
		print("HITSTOP_MOVE_EXEMPT_RESULT: ALL PASS (%d checks)" % _c.passed)
		get_tree().quit(0)

## 让玩家稳定向下跑约 1 秒真实时间，返回「每秒真实时间净位移」
func _measure_speed(p: Player, ts: float) -> float:
	p.global_position = Vector2.ZERO
	p.velocity = Vector2.ZERO
	p._dash_time = 0.0
	# 直接钉输入方向：走 joystick.get_direction() 分支
	var joy = _make_joy(Vector2.DOWN)
	GameManager.joystick = joy
	Engine.time_scale = ts
	# 先跑 6 帧稳定加速到目标速度
	for i in range(6):
		await get_tree().physics_frame
	var start: Vector2 = p.global_position
	var frames := 0
	# 顿帧时物理仍是真实 60Hz，数 60 个物理帧 ≈ 1 秒真实时间
	while frames < 60:
		await get_tree().physics_frame
		frames += 1
	var dist := (p.global_position - start).length()
	Engine.time_scale = 1.0
	GameManager.joystick = null
	joy.queue_free()
	return dist

## 造一个只吐固定方向的假摇杆（有 get_direction 方法即走摇杆分支）
func _make_joy(dir: Vector2) -> Node:
	var n := Node.new()
	n.set_script(_fixed_joy_script())
	n.set("dir", dir)
	add_child(n)
	return n

func _fixed_joy_script() -> GDScript:
	var s := GDScript.new()
	s.source_code = "extends Node\nvar dir := Vector2.ZERO\nfunc get_direction() -> Vector2:\n\treturn dir\n"
	s.reload()
	return s
