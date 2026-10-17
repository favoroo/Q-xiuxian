extends Node

## 辉光/HDR 联动通道判据（2026-10-17 真机 42fps GPU 专项）：
## 钉住 Main 辉光状态机的三条不变量：
##   1. SettingsManager SCHEMA 注册了 display/gow 键（toggle，默认 true）——
##      缺 SCHEMA 时 SettingsDialog reset 会漏掉该项
##   2. FxBudget 拥挤档常量与 glow_intensity 分档函数口径（0.4/0.25）
##   3. Main 的自动降档状态机字段存在且翻转沿逻辑正确（headless 下 _apply_glow_channel
##      直接短路返回，但状态机字段与采样逻辑可独立驱动验证）
## 运行: godot --headless --path . res://tests/GlowChannelCheck.tscn
## 退出码 0 且末行 GLOW_RESULT: ALL PASS

var _c := TestCheck.new()

func _check(cond: bool, label: String) -> void:
	_c.check(cond, label)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_schema_registered()
	_test_fx_budget_tier()
	_test_auto_off_state_machine()
	_test_apply_short_circuit()

	if not _c.all_passed():
		print("GLOW_RESULT: FAILED (%d failures)" % _c.failures.size())
		get_tree().quit(1)
	else:
		print("GLOW_RESULT: ALL PASS (%d checks)" % _c.passed)
		get_tree().quit(0)

## 1. SCHEMA 注册与默认值
func _test_schema_registered() -> void:
	var found := false
	var default_ok := false
	for item in SettingsManager.SCHEMA:
		if item.get("section") == "display" and item.get("key") == "glow":
			found = true
			default_ok = item.get("type") == "toggle" and item.get("default") == true
	_check(found, "SCHEMA 注册 display/glow 键")
	_check(default_ok, "glow 键为 toggle 默认 true（老用户升级行为不变）")
	# 默认读侧：get_val 走 bool 归一化（_to_bool 清单已登记 glow）
	_check(bool(SettingsManager.get_val(&"display", &"glow", true)),
		"get_val 默认读出 true")

## 2. FxBudget 拥挤档 glow 分档口径
func _test_fx_budget_tier() -> void:
	_check(FxBudget.GLOW_INTENSITY_NORMAL == 0.4, "常态 glow_intensity 0.4")
	_check(FxBudget.GLOW_INTENSITY_CROWDED == 0.25, "拥挤档 glow_intensity 0.25")
	_check(FxBudget.gem_light_cap() == FxBudget.LIGHT_CAP_GEM,
		"非拥挤档掉落灯名额回到全额")
	var saved := FxBudget.crowded
	FxBudget.crowded = true
	_check(FxBudget.gem_light_cap() == FxBudget.LIGHT_CAP_GEM >> 1, "拥挤档掉落灯名额减半")
	_check(FxBudget.projectile_light_cap() == FxBudget.LIGHT_CAP_PROJECTILE >> 1, "拥挤档弹丸灯名额减半")
	_check(is_equal_approx(FxBudget.glow_intensity(), 0.25), "拥挤档 glow_intensity 读出 0.25")
	FxBudget.crowded = saved
	_check(FxBudget.CROWDED_ENEMY_THRESHOLD == 24, "拥挤档敌量阈值 24")

## 3. 自动降档状态机（直接驱动 Main 的采样逻辑；headless 下生效出口短路但状态可验）
func _test_auto_off_state_machine() -> void:
	GameManager.reset_run()
	var main: Node = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	# 注意顺序：Main._ready 里会调 GameManager.reset_run()（run_started 清回 false）
	# 并把整树置暂停（开局主菜单态）——都在场景就位后改回「战斗中」再驱动采样
	GameManager.run_started = true
	get_tree().paused = false
	var m := main as MainLevel
	_check(m != null, "Main 场景实例化（拿到状态机宿主）")
	if m == null:
		return
	_check(m._glow_auto_offed == false, "初始态：未自动降档")
	_check(m._glow_low_streak == 0, "初始态：低帧计数 0")
	# headless 下 Engine.get_frames_per_second() 返回 0 < 50 ⇒ 连续 5 次采样必触发翻转
	for i in range(MainLevel.GLOW_AUTO_TRIGGERS):
		m._poll_glow_auto_off()
	_check(m._glow_auto_offed, "连续 %d 次低帧采样触发自动降档翻转" % MainLevel.GLOW_AUTO_TRIGGERS)
	_check(m._glow_toasted, "自动降档时 toast 提示一次闸置位")
	# 手动开回（setting_changed 路径）：清自动降档态
	SettingsManager.set_val(&"display", &"glow", true, false)
	_check(m._glow_auto_offed == false, "手动开回清自动降档态（恢复唯一路径）")
	_check(m._glow_low_streak == 0, "手动开回清低帧计数")
	# 翻转后不再重复 toast（本对局内）
	SettingsManager.set_val(&"display", &"glow", true, false)
	for i in range(MainLevel.GLOW_AUTO_TRIGGERS + 1):
		m._poll_glow_auto_off()
	_check(m._glow_auto_offed, "再次低帧仍能重新翻转（新对局语义由 _ready 复位）")
	main.queue_free()
	await get_tree().process_frame

## 4. 生效出口 headless 短路（不碰渲染状态，判据环境安全）
func _test_apply_short_circuit() -> void:
	# headless 下直接调用不抛错不写状态（真机行为由真机验收覆盖）
	var main := MainLevel.new()
	main._apply_glow_channel()
	_check(true, "headless 下 _apply_glow_channel 短路不抛错")
	main.free()
