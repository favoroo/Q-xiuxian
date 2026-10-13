extends Node

## 健壮性与容错机制判据（2026-10-13 健壮性优化）：
##   1. 坏类型与损坏配置容错：settings.cfg 注入非法类型（非 Vector2 的坐标、非 bool 的开关、非数值的缩放），
##      SettingsManager 加载与便捷接口调用绝不崩溃，且优雅回退默认值。
##   2. 局外进度与设置保存容错：目标路径不可写时 save_from 捕获 Error，触发重试与警告日志，不发生未捕获异常。
##   3. 单局重置契约完整性：RunReset 彻底清空 live_allies、ally_count、last_run_new_records，
##      消灭跨局灵兽残留与战报文案污染。
##
## 运行: godot --headless --path . res://tests/RobustnessCheck.tscn
## 退出码 0 且末行 ROBUSTNESS_CHECK_RESULT: ALL PASS

var _c := TestCheck.new()

func _check(cond: bool, label: String) -> void:
	_c.check(cond, label)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_norm_xy_and_btn_scale_guards()
	_test_to_bool_guards()
	_test_corrupt_settings_loading()
	_test_progress_save_failure_handling()
	_test_run_reset_allies_and_records_cleanup()

	if not _c.all_passed():
		print("ROBUSTNESS_CHECK_RESULT: FAILED (%d failures)" % _c.failures.size())
		get_tree().quit(1)
	else:
		print("ROBUSTNESS_CHECK_RESULT: ALL PASS (%d checks)" % _c.passed)
		get_tree().quit(0)

## 一、_norm_xy 与 _btn_scale 对各种异常类型的防御
func _test_norm_xy_and_btn_scale_guards() -> void:
	# 1. _norm_xy 在传入 String、int、null、float 时绝不能抛 SCRIPT ERROR
	var fallback := SettingsManager.SKILL_BTN_XY_DEFAULT
	var res_str = SettingsManager._norm_xy("corrupted_string", fallback)
	_check(res_str == fallback, "字符串类型传入 _norm_xy 安全回退默认值")

	var res_int = SettingsManager._norm_xy(12345, fallback)
	_check(res_int == fallback, "整数类型传入 _norm_xy 安全回退默认值")

	var res_null = SettingsManager._norm_xy(null, fallback)
	_check(res_null == fallback, "null 传入 _norm_xy 安全回退默认值")

	var res_f = SettingsManager._norm_xy(0.75, fallback)
	_check(res_f == fallback, "浮点标量传入 _norm_xy 安全回退默认值")

	# 正常 Vector2 / Vector2i
	var res_v2 = SettingsManager._norm_xy(Vector2(0.3, 0.4), fallback)
	_check(res_v2.is_equal_approx(Vector2(0.3, 0.4)), "合法 Vector2 正常解析")

	var res_v2i = SettingsManager._norm_xy(Vector2i(0, 1), fallback)
	_check(res_v2i.is_equal_approx(Vector2(0.0, 1.0)), "合法 Vector2i 正常转为 Vector2")

	# 2. _btn_scale 在非数值字符串时回退 1.0，而不是被 clamp 到 0.6
	var s_bad = SettingsManager._btn_scale("non_numeric")
	_check(is_equal_approx(s_bad, 1.0), "非法非数字文本传入 _btn_scale 回落 1.0 (实际 %.2f)" % s_bad)

	var s_valid_str = SettingsManager._btn_scale("1.35")
	_check(is_equal_approx(s_valid_str, 1.35), "合法数字文本传入 _btn_scale 正常解析 (1.35)")

	var s_num = SettingsManager._btn_scale(1.5)
	_check(is_equal_approx(s_num, 1.5), "合法浮点传入 _btn_scale 正常解析 (1.5)")

## 二、_to_bool 转换容错
func _test_to_bool_guards() -> void:
	_check(SettingsManager._to_bool(true) == true, "bool true 正常解析")
	_check(SettingsManager._to_bool(false) == false, "bool false 正常解析")
	_check(SettingsManager._to_bool("true") == true, "文本 'true' 解析为 true")
	_check(SettingsManager._to_bool("1") == true, "文本 '1' 解析为 true")
	_check(SettingsManager._to_bool("false") == false, "文本 'false' 解析为 false")
	_check(SettingsManager._to_bool("0") == false, "文本 '0' 解析为 false")
	_check(SettingsManager._to_bool(1) == true, "数值 1 解析为 true")
	_check(SettingsManager._to_bool(0) == false, "数值 0 解析为 false")
	_check(SettingsManager._to_bool("corrupt_value", true) == true, "非法文本回退给定默认值 true")
	_check(SettingsManager._to_bool("corrupt_value", false) == false, "非法文本回退给定默认值 false")
	_check(SettingsManager._to_bool(null, false) == false, "null 回退给定默认值 false")

## 三、模拟真实损坏 settings.cfg 加载场景
func _test_corrupt_settings_loading() -> void:
	# 先备份现有设置内存状态
	var backup_skill_xy = SettingsManager.skill_btn_xy()
	var backup_master_mute = SettingsManager.is_bus_muted(&"Master")

	# 构造注入坏配置的内存字典模拟 _validate_loaded_value
	var val_bad_xy = SettingsManager._validate_loaded_value("display", "skill_btn_xy", "bad_xy_data")
	_check(val_bad_xy == SettingsManager.SKILL_BTN_XY_DEFAULT, "坏位置配置加载校验时自动重置为默认坐标")

	var val_bad_mute = SettingsManager._validate_loaded_value("audio", "master_muted", "not_a_bool")
	_check(val_bad_mute == false, "坏静音配置加载校验时安全回退 false")

	var val_bad_vol = SettingsManager._validate_loaded_value("audio", "master_volume", "bad_volume")
	_check(is_equal_approx(val_bad_vol, 1.0), "坏音量配置加载校验时安全回退 1.0")

	var val_bad_shake = SettingsManager._validate_loaded_value("display", "shake_intensity", "super_ultra_shake")
	_check(val_bad_shake == SettingsManager.SHAKE_DEFAULT_LEVEL, "未知震屏档位加载校验时安全回退标准档")

	# 验证在内存存在坏值时调用便捷接口仍不崩溃
	SettingsManager._settings["display"]["skill_btn_xy"] = "totally_corrupt"
	var xy = SettingsManager.skill_btn_xy()
	_check(xy == SettingsManager.SKILL_BTN_XY_DEFAULT, "即使内存存在脏值，skill_btn_xy() 调用依然安全回退")

	SettingsManager._settings["audio"]["master_muted"] = "corrupt_mute"
	var mute = SettingsManager.is_bus_muted(&"Master")
	_check(mute == false, "即使内存存在脏值，is_bus_muted() 调用依然安全回退")

	# 还原
	SettingsManager.set_skill_btn_xy(backup_skill_xy, false)
	SettingsManager.set_bus_muted(&"Master", backup_master_mute)

## 四、保存失败分支与错误码捕获
func _test_progress_save_failure_handling() -> void:
	# 传入不可写非法路径，触发 cfg.save 失败分支
	var invalid_path := "user://invalid_nonexistent_directory/cannot_write/sub/progress.cfg"
	var err := ProgressStore.save_from(GameManager, invalid_path)
	_check(err != OK, "向非法只读路径保存局外进度返回非 OK 错误码 (实得 %d)" % err)
	_check(err is int, "save_from 正确返回 Error 类型整数")

## 五、RunReset 对 live_allies / ally_count / last_run_new_records 的彻底清空契约
func _test_run_reset_allies_and_records_cleanup() -> void:
	# 制造污染态
	var dummy_ally := Node2D.new()
	dummy_ally.name = "DummyAlly"
	add_child(dummy_ally)
	GameManager.register_ally(dummy_ally)
	GameManager.last_run_new_records.append("虚假历史纪录 · 破境金丹")

	_check(GameManager.live_allies.size() == 1, "前置：已注入 1 只测试友方灵兽")
	_check(GameManager.ally_count == 1, "前置：ally_count 计数为 1")
	_check(not GameManager.last_run_new_records.is_empty(), "前置：已注入测试纪录文案")

	# 执行单局重置
	GameManager.reset_run()

	_check(GameManager.live_allies.is_empty(), "reset_run 后 live_allies 彻底清空（消除嘲讽索敌残留）")
	_check(GameManager.ally_count == 0, "reset_run 后 ally_count 镜像计数归零")
	_check(GameManager.last_run_new_records.is_empty(), "reset_run 后 last_run_new_records 彻底清空（消除跨局结算污染）")

	dummy_ally.queue_free()
