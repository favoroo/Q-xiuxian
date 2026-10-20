extends Node

## 辉光/HDR 联动通道判据（2026-10-17 真机 42fps GPU 专项）：
## 钉住 Main 辉光状态机的三条不变量：
##   1. SettingsManager SCHEMA 注册了 display/gow 键（toggle，默认 true）——
##      缺 SCHEMA 时 SettingsDialog reset 会漏掉该项
##   2. FxBudget 拥挤档常量与 glow_intensity 分档函数口径（0.4/0.25，阈值滞回 24/20）
##   3. Main 的自动降档状态机字段存在且翻转沿逻辑正确（headless 下 _apply_glow_channel
##      直接短路返回，但状态机字段与采样逻辑可独立驱动验证）；
##      自动降档态持久化在 display/glow_auto_off，跨局读回（2026-10-17 UI 频闪治理）
##   4. UI 侧不许出现 HDR 起辉色（2026-10-20 真机整层 UI 频闪根治）：
##      UI 与世界同处根视口 HDR 缓冲，任何 modulate/color 分量 >1.0 的 UI 元素都会被
##      WorldEnvironment glow bloom，且 glow_intensity 战斗中随拥挤档升降 ⇒ 整层 HUD 闪。
##      扫 scripts/ui/ 下所有 Color(...) 字面量 + 硬编码 modulate 写入，分量必须 ≤1.0。
##      战斗特效（FX_HDR_* 常量表，定义在 GameStyle.gd）是设计内的曝光源，不在本判据口径。
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
	_test_ui_modulate_not_hdr()
	_test_hud_pulse_constants_in_range()
	_test_glow_level_fade_path()

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
	_check(FxBudget.CROWDED_EXIT_THRESHOLD == 20, "拥挤档退出阈值 20（滞回，防阈值附近每秒翻转）")
	_check(FxBudget.CROWDED_EXIT_THRESHOLD < FxBudget.CROWDED_ENEMY_THRESHOLD, "退出阈值严格低于进入阈值")

## 3. 自动降档状态机（直接驱动 Main 的采样逻辑；headless 下生效出口短路但状态可验）
func _test_auto_off_state_machine() -> void:
	GameManager.reset_run()
	# 清持久位：上次崩溃的测试或真机游玩可能在 user://settings.cfg 留了 glow_auto_off=true，
	# 不清的话 Main._ready 会把它读回，「初始态」断言被环境污染
	SettingsManager.set_val(&"display", &"glow_auto_off", false, false)
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
	_check(bool(SettingsManager.get_val(&"display", &"glow_auto_off", false)),
		"自动降档态持久化写入 display/glow_auto_off")
	# 跨局持久：新 Main 实例 _ready 从持久位读回（重开一局不再重新触发通道翻转）
	var main2: Node = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main2)
	await get_tree().process_frame
	var m2 := main2 as MainLevel
	_check(m2 != null and m2._glow_auto_offed, "重开一局自动降档态从持久位读回（跨局生效）")
	main2.queue_free()
	await get_tree().process_frame
	# 第二实例的 _ready 同样 reset_run + 暂停整树，恢复「战斗中」再驱动主实例
	GameManager.run_started = true
	get_tree().paused = false
	# 手动开回（setting_changed 路径）：清自动降档态（含持久位）
	SettingsManager.set_val(&"display", &"glow", true, false)
	_check(m._glow_auto_offed == false, "手动开回清自动降档态（恢复唯一路径）")
	_check(m._glow_low_streak == 0, "手动开回清低帧计数")
	_check(not bool(SettingsManager.get_val(&"display", &"glow_auto_off", false)),
		"手动开回同步清持久位")
	# 翻转后不再重复 toast（本对局内）
	SettingsManager.set_val(&"display", &"glow", true, false)
	for i in range(MainLevel.GLOW_AUTO_TRIGGERS + 1):
		m._poll_glow_auto_off()
	_check(m._glow_auto_offed, "再次低帧仍能重新翻转（新对局语义由 _ready 复位）")
	main.queue_free()
	await get_tree().process_frame
	# 收尾把持久位写回 false 并落盘，不污染真机/桌面设置文件
	SettingsManager.set_val(&"display", &"glow_auto_off", false, true)

## 4. 生效出口 headless 短路（不碰渲染状态，判据环境安全）
func _test_apply_short_circuit() -> void:
	# headless 下直接调用不抛错不写状态（真机行为由真机验收覆盖）
	var main := MainLevel.new()
	main._apply_glow_channel()
	_check(true, "headless 下 _apply_glow_channel 短路不抛错")
	# 期望开态尺子与写入侧同源：手动开 + 未自动降档
	main._glow_auto_offed = false
	SettingsManager.set_val(&"display", &"glow", true, false)
	_check(main._glow_should_be_on(), "期望开态：手动开且未自动降档 ⇒ true")
	main._glow_auto_offed = true
	_check(not main._glow_should_be_on(), "期望开态：自动降档后 ⇒ false")
	main._glow_auto_offed = false
	main.free()

## 5. UI 源码里不许有分量 >1.0 的颜色字面量（防回潮）
## 口径：扫 scripts/ui/ 下 .gd 的 `Color(` 字面量前三个分量。
## 例外只有 GameStyle.gd —— FX_HDR_* 是战斗特效（世界层）的曝光源色表，定义在那里，
## 由世界层消费；UI 侧消费点必须自己钳，本判据正是钉 UI 那些点。
const UI_HDR_SCAN_EXCLUDE := ["GameStyle.gd"]
func _test_ui_modulate_not_hdr() -> void:
	var offenders: Array[String] = []
	for path in _ui_script_paths():
		if UI_HDR_SCAN_EXCLUDE.has(path.get_file()):
			continue
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			continue
		for hit in _scan_hdr_color_literals(text):
			offenders.append("%s → Color(%s)" % [path.get_file(), hit])
	_check(offenders.is_empty(),
		"scripts/ui/ 下无超白颜色字面量（得 %d 处：%s）" % [offenders.size(), ", ".join(offenders)])

## 6. HUD 脉冲色常量本身必须 LDR 安全（即使将来有人改了常量名也不漏）
func _test_hud_pulse_constants_in_range() -> void:
	var colors := {
		"HP_LOW_PULSE_COLOR": GameHUD.HP_LOW_PULSE_COLOR,
		"HP_HEAL_PULSE_COLOR": GameHUD.HP_HEAL_PULSE_COLOR,
		"SHARDS_PULSE_COLOR": GameHUD.SHARDS_PULSE_COLOR,
	}
	for name in colors:
		var c: Color = colors[name]
		_check(c.r <= 1.0 and c.g <= 1.0 and c.b <= 1.0,
			"%s 分量 ≤1.0（实得 %.2f/%.2f/%.2f）" % [name, c.r, c.g, c.b])

## 7. 辉光档位渐变通道：首写直落、后续走补间（headless 下按字段状态验证）
func _test_glow_level_fade_path() -> void:
	var main := MainLevel.new()
	_check(main._glow_level_cur < 0.0, "初始态：glow 档位尚未落地（-1 哨兵）")
	# headless 下 _env_res 为空 ⇒ _set_glow_level 安全返回，状态不变
	main._set_glow_level(0.4)
	_check(main._glow_level_cur < 0.0, "无 Environment 时 _set_glow_level 不写状态")
	_check(MainLevel.GLOW_FADE_DURATION > 0.0, "辉光渐变时长 >0（不许硬切）")
	main.free()

## scripts/ui/ 下全部 .gd 绝对路径（res:// 口径：Directory 递归）
func _ui_script_paths() -> Array[String]:
	var out: Array[String] = []
	var stack: Array[String] = ["res://scripts/ui"]
	while not stack.is_empty():
		var dir_path: String = stack.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for sub in dir.get_directories():
			stack.append(dir_path.path_join(sub))
		for file_name in dir.get_files():
			if file_name.ends_with(".gd"):
				out.append(dir_path.path_join(file_name))
	return out

## 正则扫 Color(r, g, b, ...) 字面量，返回超白的那几处原文
## 只认数值字面量（常量名/表达式不算）—— 常量表在 GameStyle 里，由判据 6 直接取值把关。
func _scan_hdr_color_literals(text: String) -> Array[String]:
	var re := RegEx.new()
	re.compile("Color\\(\\s*([0-9]*\\.?[0-9]+)\\s*,\\s*([0-9]*\\.?[0-9]+)\\s*,\\s*([0-9]*\\.?[0-9]+)")
	var out: Array[String] = []
	for m in re.search_all(text):
		var r := m.get_string(1).to_float()
		var g := m.get_string(2).to_float()
		var b := m.get_string(3).to_float()
		if r > 1.0 or g > 1.0 or b > 1.0:
			out.append("%s, %s, %s" % [m.get_string(1), m.get_string(2), m.get_string(3)])
	return out
