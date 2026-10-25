extends Node
## JoystickRaceProbe — 诊断「摇杆闪一下就消失」的竞态（用户 2026-10-24：滑动时方向钮不常驻，时好时坏）。
## 假设根因：_stop_joystick() 创建的 0.15s 淡出 tween 尾部挂着 base.visible=false 回调；
## 若下一次按下落在该 tween 结束之前（快速连续滑动 / 换向），旧回调会在新触摸进行中把底座藏掉，
## 表现为「显示一下马上消失」且走位仍然有效（output 未被清零），与用户描述一致。
## 判据：
##   快速路径（松手后 0.06s 再按下并拖动）→ 触摸进行中 base.visible 必须为 true；
##   慢速路径（松手后 0.40s 再按下并拖动，对照组）→ 同上。
## 运行：python3 tools/run_test.py JoystickRaceProbe
## （当前实现若复现，将打印 BUG REPRODUCED 并以 JOYSTICK_RACE_RESULT: FAIL 退出 1。）

const JOY_SCENE := preload("res://scenes/ui/VirtualJoystick.tscn")

var _joy: DawnJoystick

func _ready() -> void:
	await get_tree().process_frame
	var layer := CanvasLayer.new()
	add_child(layer)
	_joy = JOY_SCENE.instantiate()
	layer.add_child(_joy)
	await get_tree().process_frame

	var fast_ok := await _scenario(0.06, "快速换向")
	var slow_ok := await _scenario(0.40, "慢速单滑")
	print("JOYSTICK_RACE_RESULT: %s" % ("ALL PASS" if fast_ok and slow_ok else "FAIL"))
	get_tree().quit(0 if fast_ok and slow_ok else 1)

## 单趟场景：按下→立刻松手→隔 gap 秒再按下并拖动→越过旧淡出回调时刻后检查底座可见性与走位输出
func _scenario(gap: float, tag: String) -> bool:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.position = Vector2(200, 300)
	# 第一趟触摸：按下即松手（留下一支 0.15s 淡出 tween）
	ev.pressed = true
	_joy._input(ev)
	ev.pressed = false
	_joy._input(ev)
	await get_tree().create_timer(gap).timeout
	# 第二趟触摸：按下并拖动（手指仍在屏上滑动中）
	ev.pressed = true
	_joy._input(ev)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(320, 300)
	_joy._input(drag)
	# 等到第一趟淡出 tween 的回调时刻（0.15s）之后再加余量
	await get_tree().create_timer(0.30).timeout
	var visible_now: bool = _joy.base.visible
	var moving: bool = _joy.output.length() > 0.01
	if visible_now and moving:
		print("[%s] 正常：base.visible=true 且走位输出有效" % tag)
	else:
		print("[%s] BUG REPRODUCED：触摸进行中 base.visible=%s（应为 true），output=%s（走位仍在生效）" % [tag, visible_now, _joy.output])
	# 收尾：松手复位，避免影响下一趟
	ev.pressed = false
	_joy._input(ev)
	await get_tree().create_timer(0.25).timeout
	return visible_now and moving
