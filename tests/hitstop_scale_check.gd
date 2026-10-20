extends Node

## 顿帧「玩家与世界同步变慢」判据（2026-10-20 替换 HitstopMoveExemptCheck）：
##   背景：v0.0.58 的「顿帧移动豁免」在 Player 里按 1/time_scale 补位移
##   （move_and_slide + move_and_collide 大步），配合 physics_interpolation=false 造成
##   「卡一下 → 抽掉几帧 → 闪到新位置」，并让玩家深穿敌人触发其去穿透被弹飞。
##   整改为经典顿帧：顿帧期间玩家与世界同吃缩放后的 delta，一起变慢，不做任何位移补偿。
## 判据：
##   1. 常速(time_scale=1.0)下每真实秒净位移 ≈ base_speed（基线正常）
##   2. time_scale=0.20 时每真实秒净位移 ≈ 常速的 0.20（±容差）——玩家跟随世界变慢，无豁免
##   3. 脚本里已不存在 HITSTOP_TIME_COMP_CAP 常量（防止豁免机制被重新引入）
##   4. 相机跟随不漏跟（间距 < 60px）
## 运行: godot --headless --path . res://tests/HitstopScaleCheck.tscn

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

	var normal := await _measure_speed(p, 1.0)
	var frozen := await _measure_speed(p, 0.20)
	Engine.time_scale = 1.0

	var ratio := frozen / maxf(normal, 0.001)
	_c.check(normal > 100.0, "常速基线位移为正（%.1f px/s）" % normal)
	# 无豁免：顿帧期间玩家应跟随世界变慢，每真实秒位移 ≈ 常速 × 0.20（容差放宽覆盖起步/取整误差）
	_c.check(ratio > 0.15 and ratio < 0.28, "顿帧(time_scale=0.20)下位移随世界变慢（比值 %.2f，应≈0.20）" % ratio)

	# 防止豁免机制被重新引入：脚本常量表里不应再有 HITSTOP_TIME_COMP_CAP
	var consts: Dictionary = p.get_script().get_script_constant_map()
	_c.check(not consts.has("HITSTOP_TIME_COMP_CAP"), "Player 已移除顿帧位移补偿常量 HITSTOP_TIME_COMP_CAP")

	# 相机不漏跟：玩家持续下移，相机应仍贴近
	var cam := SmoothCamera.new()
	add_child(cam)
	GameManager.main_camera = cam
	cam.global_position = p.global_position
	for i in range(30):
		p.global_position += Vector2(0, 6.0)
		cam._physics_process(1.0 / 60.0)
	var gap := (cam.global_position - p.global_position).length()
	_c.check(gap < 60.0, "相机跟随不漏跟（玩家/相机间距 %.1f px）" % gap)
	cam.queue_free()

	p.queue_free()
	if not _c.all_passed():
		print("HITSTOP_SCALE_RESULT: FAILED (%d failures)" % _c.failures.size())
		get_tree().quit(1)
	else:
		print("HITSTOP_SCALE_RESULT: ALL PASS (%d checks)" % _c.passed)
		get_tree().quit(0)

## 让玩家稳定向下跑约 1 秒真实时间，返回「每秒真实时间净位移」。
## 顿帧时物理仍是真实 60Hz、只是每步 delta 被缩放，故数 60 个物理帧 ≈ 1 秒真实时间。
func _measure_speed(p: Player, ts: float) -> float:
	Engine.time_scale = ts
	# 直接钉输入方向与速度，跳过受 time_scale 拖慢的起步加速段（否则测的是加速度而非稳态速度）
	var joy = _make_joy(Vector2.DOWN)
	GameManager.joystick = joy
	p.global_position = Vector2.ZERO
	p._dash_time = 0.0
	p.velocity = Vector2.DOWN * p.base_speed
	await get_tree().physics_frame
	await get_tree().physics_frame
	var start: Vector2 = p.global_position
	var frames := 0
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
