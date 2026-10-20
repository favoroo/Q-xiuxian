extends Node

## 真机闪屏探针判据（2026-10-20）：
## 钉住 FlickerProbe 的三条不变量，防止探针本身坏掉却不自知（探针失效比没探针更糟——
## 会让人误判「没记录 = 没问题」）：
##   1. 设置项 display/flicker_probe 已注册、默认关闭（不能默认开，玩家包不该写日志）
##   2. 探针脚本可实例化，默认不在采集（未开设置时 set_process 应为 false）
##   3. 日志路径为 user://flicker_log.csv，且判读阈值是合理正数
## 运行: godot --headless --path . res://tests/FlickerProbeCheck.tscn

var _c := TestCheck.new()

func _check(cond: bool, label: String) -> void:
	_c.check(cond, label)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_schema()
	_test_probe_instantiable()
	_test_constants()
	await _test_creates_file_on_enable()

	if not _c.all_passed():
		print("FLICKER_PROBE_RESULT: FAILED (%d failures)" % _c.failures.size())
		get_tree().quit(1)
	else:
		print("FLICKER_PROBE_RESULT: ALL PASS (%d checks)" % _c.passed)
		get_tree().quit(0)

## 1. 设置项注册与默认值
func _test_schema() -> void:
	var found := false
	var default_off := false
	for item in SettingsManager.SCHEMA:
		if item.get("section") == "display" and item.get("key") == "flicker_probe":
			found = true
			default_off = item.get("type") == "toggle" and item.get("default") == false
	_check(found, "SCHEMA 注册 display/flicker_probe")
	_check(default_off, "flicker_probe 为 toggle 且默认关闭（玩家包不写日志）")
	_check(bool(SettingsManager.get_val(&"display", &"flicker_probe", false)) == false,
		"get_val 默认读出 false")

## 2. 探针可实例化、未开启时不采集
func _test_probe_instantiable() -> void:
	var probe := FlickerProbe.new()
	add_child(probe)
	_check(probe != null, "FlickerProbe 可实例化")
	# 默认关（测试环境 settings 里 flicker_probe 为 false）
	_check(probe.is_active() == false, "未开启设置时探针不采集")
	_check(probe.rows_written() == 0, "未采集时不写任何行")
	probe.queue_free()
	await get_tree().process_frame

## 3. 常量口径
func _test_constants() -> void:
	_check(FlickerProbe.log_path() == "user://flicker_log.csv",
		"日志路径为 user://flicker_log.csv（实得 %s）" % FlickerProbe.log_path())
	_check(FlickerProbe.VRAM_JUMP_MB > 0.0, "显存跳变阈值 >0")
	_check(FlickerProbe.DRAW_DROP_RATIO > 0.0 and FlickerProbe.DRAW_DROP_RATIO < 1.0,
		"draw 跌幅阈值在 (0,1)")
	# 心跳必须存在且为正：首版只在异常时建文件，导致用户「开了探针却找不到文件」，
	# 心跳是「探针确实在跑」的可证伪凭据（2026-10-20 修正）
	_check(FlickerProbe.HEARTBEAT_SEC > 0.0,
		"心跳间隔 >0（保证文件一定被创建且有内容）")

## 4. 开启后必须立刻建文件（回归「找不到文件」那个坑）
func _test_creates_file_on_enable() -> void:
	var path := FlickerProbe.log_path()
	# 先清掉可能存在的旧日志，确保本段测的是「刚开启」的行为
	if FileAccess.file_exists(path):
		DirAccess.open("user://").remove(path.get_file())
	var probe := FlickerProbe.new()
	add_child(probe)
	await get_tree().process_frame
	# 打开开关：应立刻创建文件并写表头
	SettingsManager.set_val(&"display", &"flicker_probe", true, false)
	await get_tree().process_frame
	var exists := FileAccess.file_exists(path)
	_check(exists, "开启探针后立刻创建日志文件（不必等异常）")
	if exists:
		var content := FileAccess.get_file_as_string(path)
		_check(content.contains("frame,t_ms"), "文件含 CSV 表头")
		_check(content.contains("PROBE_STARTED"), "文件含启动标记")
	# 关掉并清理，避免污染用户/后续测试
	SettingsManager.set_val(&"display", &"flicker_probe", false, false)
	await get_tree().process_frame
	if FileAccess.file_exists(path):
		DirAccess.open("user://").remove(path.get_file())
	probe.queue_free()
	await get_tree().process_frame
