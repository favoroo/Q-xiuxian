extends Node

## 判据：设置·操作页的「按钮调整模式」必须拖得动 —— 手指按住哪颗浮动键，那颗键就要
## 跟着手指走，松手后位置落盘；空白处按下不许把键带走。
## 运行: $G --headless --path . res://tests/HudBtnDragCheck.tscn
##       $G --headless --path . res://tests/HudBtnDragCheck.tscn -- --probe     # 派发诊断
##       $G --headless --path . res://tests/HudBtnDragCheck.tscn -- --selftest  # 跑反例
##       $G --headless --path . res://tests/HudBtnDragCheck.tscn -- --width=720 # 换档
##
## 为什么立这条（用户 2026-10-11 真机：三颗键一颗都拖不动）：
##   HudEditOverlay._process 旧写法 `_apply_drag(_xy_setter.bind(_drag_id))`，而 _apply_drag 里
##   `setter.call(norm, false)`。Callable.bind() 是把绑定参数**追加到实参表末尾**，于是每帧调成
##   `_xy_setter(norm, false, drag_id)`：形参 1 要 int 却收到 Vector2 ⇒ GDScript 报
##   "Cannot convert argument 1 from Vector2 to int" 并放弃这次调用 ⇒ 设置项一次都没写进去，
##   真实按钮原地不动，代理钮每帧又被贴回原处，看着就是"按住了拖不走"。
##   这种错不崩、不退出，只在控制台每帧刷一条 SCRIPT ERROR ⇒ UnitRunner / SmokeRunner 全绿。
##
## 尺子口径：走生产入口（GameHUD.open_btn_edit_overlay，设置页那颗按钮调的就是它），
## 事件用 push_input 真发按下/微动/抬起（emit_signal 会绕过拾取，热区是死的也照样全绿），
## 量的是「真实按钮的视觉中心有没有跟到手指落点」+「代理钮跟不跟得上」+「松手才落盘」。
## --selftest 把修复前的调用形状原样跑一遍，必须量到位置纹丝不动，才算有牙齿。

const VIEWPORT_SIZE := Vector2i(960, 540)
## 每颗键各自的落点偏移（设计像素）：三颗键若拖到同一个点就会叠在一起，
## 之后"按哪颗"全看谁在上面 —— 判据量的是「按到谁」，必须各留各的位置
const DRAG_OFFSETS: Array[Vector2] = [Vector2(-260, -60), Vector2(-420, -100), Vector2(-260, -40)]
## 视觉中心与手指落点的容差（设计像素）：拖动是绝对定位，只允许浮点与半尺寸夹取余量
const SNAP_EPS := 3.0
## HudEditOverlay.DRAG_NONE（脚本常量不走 get()，这里同值钉死）
const DRAG_NONE := -1

var _c := TestCheck.new()
var _main: Node = null
var _hud: GameHUD = null
var _ov: Control = null
var _probe: bool = false
var _last_motion := Vector2.ZERO

## 三颗键一张表：名字 / 代理钮字段 / 设置项 / HUD 门面与 SettingsManager 的取数口径
const KEYS: Array[Dictionary] = [
	{
		"name": "技能键", "proxy": "_skill_proxy", "cfg": "skill_btn_xy",
		"get_px": "skill_btn_center_px", "get_xy": "skill_btn_xy", "set_xy": "set_skill_btn_xy",
		"get_scale": "skill_btn_scale", "set_scale": "set_skill_btn_scale",
	},
	{
		"name": "祭坛键", "proxy": "_obelisk_proxy", "cfg": "obelisk_btn_xy",
		"get_px": "obelisk_btn_center_px", "get_xy": "obelisk_btn_xy", "set_xy": "set_obelisk_btn_xy",
		"get_scale": "obelisk_btn_scale", "set_scale": "set_obelisk_btn_scale",
	},
	{
		"name": "额外技能键", "proxy": "_extra_proxy", "cfg": "extra_btn_xy",
		"get_px": "extra_skill_btn_center_px", "get_xy": "extra_btn_xy", "set_xy": "set_extra_btn_xy",
		"get_scale": "extra_btn_scale", "set_scale": "set_extra_btn_scale",
	},
]

func _ready() -> void:
	call_deferred("_boot", OS.get_cmdline_user_args())

func _boot(args: Array) -> void:
	get_tree().root.size = VIEWPORT_SIZE
	for a in args:
		if String(a).begins_with("--width="):
			get_tree().root.size = Vector2i(int(String(a).trim_prefix("--width=")), VIEWPORT_SIZE.y)
	_probe = "--probe" in args
	_main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(_main)
	await _settle(4)
	GameManager.cultivator_id = "meiying"  # 影者：带额外技能影爆，三颗键都该在
	GameManager.pending_skill_id = "dash"
	GameManager.start_run("qingyun_sword")
	get_tree().paused = false
	_dismiss()
	await _settle(12)
	_hud = _main.get_node_or_null("UILayer/GameHUD") as GameHUD
	_dismiss()
	# 世界冻住：只测摆位，不让刷怪与结算面板在这一拍里插一脚（覆盖层是 PROCESS_MODE_ALWAYS）
	get_tree().paused = true
	if _hud != null:
		_hud.open_btn_edit_overlay()
	await _settle(4)
	_ov = null
	if _hud != null:
		_ov = _hud.get("_edit_overlay") as Control
	if "--selftest" in args:
		await _selftest()
	else:
		await _run()
	# 判据不改玩家存档：三颗键的位/大小与开局前同一份
	get_tree().quit(0 if _c.report("HUD_BTN_DRAG_RESULT") else 1)

func _dismiss() -> void:
	for node_name in ["LevelUpDialog", "WaveShop", "PlayerStatsDialog", "PauseMenu",
			"SettingsDialog", "StartMenu", "StartWeaponSelect", "CultivatorSelect",
			"SkillSelect", "GameOverDialog", "TutorialDialog", "ManualDialog", "CareerDialog"]:
		var n := _main.get_node_or_null("UILayer/" + node_name) as Control
		if n != null and n.visible:
			n.visible = false

func _settle(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

# ================================ 正判 ================================

func _run() -> void:
	_c.check(_hud != null, "GameHUD 挂在 UILayer 下")
	_c.check(_ov != null and _ov.visible, "调整模式覆盖层已开（走生产入口 open_btn_edit_overlay）")
	if _hud == null or _ov == null:
		return
	var orig := _snapshot()
	if _probe:
		await _probe_dispatch()
	# 反例先跑：三颗键还在各自出厂位、彼此不叠，此时"空白处拖不走"量的才是拾取本身
	var vp := _hud.get_viewport_rect().size
	await _check_blank_drag_does_nothing(KEYS[0], Vector2(vp.x * 0.5, vp.y * 0.5))
	for i in range(KEYS.size()):
		await _check_one_drag(KEYS[i], DRAG_OFFSETS[i])
	await _check_save_only_on_release(KEYS[0])
	await _check_slider_follows_selection()
	_check_labels()
	_c.check(_c.passed >= 25, "判据记满账（实得 %d 条，条数掉一半 = 中途炸了还在打 ALL PASS）" % _c.passed)
	_restore(orig)
	await _settle(2)
	await _maybe_shot()

## 出图台：`-- --shot=/tmp/x.png` 把覆盖层现场拍一张（必须不带 --headless，否则没有像素）
func _maybe_shot() -> void:
	for a in OS.get_cmdline_user_args():
		if not String(a).begins_with("--shot="):
			continue
		await _settle(6)
		var img := get_tree().root.get_texture().get_image()
		var path := String(a).trim_prefix("--shot=")
		var err := img.save_png(path)
		print("[SHOT] %s err=%d 尺寸 %dx%d" % [path, err, img.get_width(), img.get_height()])

## 一颗键的完整一拖：按住它 → 拖到落点 → 松手，量真身 / 代理钮 / 存档三处同源
func _check_one_drag(k: Dictionary, off: Vector2) -> void:
	var name_s := String(k["name"])
	var start: Vector2 = _hud.call(String(k["get_px"]))
	var proxy0 := _proxy_center(String(k["proxy"]))
	# 前提自证：代理钮就贴在真实键上，否则"跟着手指走"量的不是同一颗键
	_c.check(proxy0.distance_to(start) <= SNAP_EPS,
			"%s 代理钮与真实键同位（代理 %.0f,%.0f / 真身 %.0f,%.0f）" % [
					name_s, proxy0.x, proxy0.y, start.x, start.y])
	# 落点收进「中心可达区」：HudButtonLayout 会把中心夹到半尺寸+2 之内，
	# 期望值取夹过的点，判据才不会去考一条本来就不允许的题
	var vp := _hud.get_viewport_rect().size
	var half := SkillButtonView.SKILL_BTN_SIZE * 0.5 + 2.0
	var target := Vector2(
			clampf(start.x + off.x, half, vp.x - half),
			clampf(start.y + off.y, half, vp.y - half))
	await _drag(start, target)
	var got: Vector2 = _hud.call(String(k["get_px"]))
	var got_proxy := _proxy_center(String(k["proxy"]))
	var got_xy: Vector2 = SettingsManager.call(String(k["get_xy"]))
	_c.check(start.distance_to(got) > 20.0,
			"%s 拖完动了（%.0f,%.0f → %.0f,%.0f）" % [name_s, start.x, start.y, got.x, got.y])
	_c.check(got.distance_to(target) <= SNAP_EPS,
			"%s 视觉中心跟到手指落点 %.0f,%.0f（实得 %.0f,%.0f，容差 %.0f）" % [
					name_s, target.x, target.y, got.x, got.y, SNAP_EPS])
	_c.check(got_proxy.distance_to(got) <= SNAP_EPS,
			"%s 拖完代理钮仍贴着真身（代理 %.0f,%.0f / 真身 %.0f,%.0f）" % [
					name_s, got_proxy.x, got_proxy.y, got.x, got.y])
	_c.near(got_xy.x, target.x / vp.x, 0.011, "%s 存档 X 与落点同源" % name_s)
	_c.near(got_xy.y, target.y / vp.y, 0.011, "%s 存档 Y 与落点同源" % name_s)

## 拖动中不落盘、松手才写 settings.cfg（口径写在 _apply_drag 注释里：每帧写盘会卡手）
func _check_save_only_on_release(k: Dictionary) -> void:
	var name_s := String(k["name"])
	var cfg := String(k["cfg"])
	var start: Vector2 = _hud.call(String(k["get_px"]))
	var disk0 := _disk_xy(cfg)
	var off := Vector2(-120.0, -80.0)
	await _motion(start)
	await _press(start)
	await _motion(start + off * 0.5)
	await _motion(start + off)
	var disk_mid := _disk_xy(cfg)
	_c.check(disk_mid.distance_to(disk0) < 0.0001,
			"%s 拖动中途不写盘（盘上仍是 %.3f,%.3f）" % [name_s, disk0.x, disk0.y])
	await _release(start + off)
	await _settle(3)
	var disk_end := _disk_xy(cfg)
	_c.check(disk_end.distance_to(disk_mid) > 0.0001,
			"%s 松手后落盘（盘上 %.3f,%.3f → %.3f,%.3f）" % [
					name_s, disk_mid.x, disk_mid.y, disk_end.x, disk_end.y])
	var mem: Vector2 = SettingsManager.call(String(k["get_xy"]))
	_c.check(disk_end.distance_to(mem) < 0.0001, "%s 盘上与内存里是同一份值" % name_s)

## 反例：在离三颗键都远的空白处按下并拖，键必须纹丝不动
## （否则"键跟着手指走"可能只是它自己想动，尺子抓不住"按到的是谁"这件事）
func _check_blank_drag_does_nothing(k: Dictionary, target: Vector2) -> void:
	var vp := _hud.get_viewport_rect().size
	var blank := Vector2(vp.x * 0.5, vp.y * 0.5)
	var before: Vector2 = _hud.call(String(k["get_px"]))
	await _drag(blank, target)
	var got: Vector2 = _hud.call(String(k["get_px"]))
	_c.check(before.distance_to(got) <= SNAP_EPS,
			"空白处按下拖不走 %s（%.0f,%.0f → %.0f,%.0f，位移 %.1f）" % [
					String(k["name"]), before.x, before.y, got.x, got.y, before.distance_to(got)])
	_c.check(int(_ov.get("_drag_id")) == DRAG_NONE,
			"空白处那一枪没起拖，也没留下没收尾的拖动（_drag_id 实得 %d）" % int(_ov.get("_drag_id")))

## 点选与大小滑杆：点哪颗，滑杆就只改哪颗
func _check_slider_follows_selection() -> void:
	var extra: Dictionary = KEYS[2]
	var px: Vector2 = _hud.call(String(extra["get_px"]))
	await _tap(px)
	await _settle(2)
	var chip: Label = _ov.get("_sel_label")
	_c.equals(String(chip.text), "额外技能", "点额外技能键后 chip 写「额外技能」（实得「%s」）" % chip.text)
	var slider: HSlider = _ov.get("_size_slider")
	var skill_before := SettingsManager.skill_btn_scale()
	slider.value = 140.0
	await _settle(2)
	_c.near(SettingsManager.extra_btn_scale(), 1.4, 0.011, "滑杆把选中的额外技能键调到 140%")
	_c.near(SettingsManager.skill_btn_scale(), skill_before, 0.001,
			"没选中的技能键大小不动（滑杆不串台，实得 %.2f）" % SettingsManager.skill_btn_scale())
	slider.value = 100.0
	await _settle(2)

## 键面文案（用户 2026-10-11：英文 extra 看不出那是颗什么键）
func _check_labels() -> void:
	var proxy: Button = _ov.get("_extra_proxy")
	_c.check(not proxy.text.contains("extra"),
			"额外技能键的拖动代理不再写英文（实得「%s」）" % proxy.text)
	_c.check(not HudSkillButton.EXTRA_BTN_TEXT.contains("extra"),
			"额外技能键真身的占位文案也不再写英文（实得「%s」）" % HudSkillButton.EXTRA_BTN_TEXT)

# ================================ 诊断与反例 ================================

## 派发诊断：分别量「鼠标那一枪」与「触屏那一枪」两条路 —— 按下起得起拖、拖得动键、
## 抬起收得住口。真机走触屏那条（Godot 把 ScreenTouch 也交给控件的 gui_input），
## 哪条不通就得改口径，不许把"没收到事件"当成"没问题"。
## 诊断自己会挪键，跑完按快照复位，不许污染后面的判据。
func _probe_dispatch() -> void:
	var orig := _snapshot()
	await _probe_gesture("鼠标")
	await _probe_gesture("触屏")
	_restore(orig)
	await _settle(2)

## 一枪三拍：按下 → 挪一段 → 抬起
func _probe_gesture(mode: String) -> void:
	var k: Dictionary = KEYS[0]
	var off := Vector2(-90.0, -60.0)
	var px: Vector2 = _hud.call(String(k["get_px"]))
	if mode == "鼠标":
		await _motion(px)
		await _press(px)
	else:
		await _touch_down(px)
	_c.check(int(_ov.get("_drag_id")) == 0,
			"%s那一枪按下起了拖（_drag_id 实得 %s）" % [mode, str(_ov.get("_drag_id"))])
	if mode == "鼠标":
		await _motion(px + off)
	else:
		await _touch_drag(px + off)
	var mid: Vector2 = _hud.call(String(k["get_px"]))
	_c.check(mid.distance_to(px + off) <= SNAP_EPS,
			"%s那一枪拖得动：键该跟到 %.0f,%.0f（实得 %.0f,%.0f）" % [
					mode, (px + off).x, (px + off).y, mid.x, mid.y])
	if mode == "鼠标":
		await _release(px + off)
	else:
		await _touch_up(px + off)
	await _settle(2)
	_c.check(int(_ov.get("_drag_id")) == DRAG_NONE,
			"%s那一枪抬起收得住口（收不住 ⇒ 这颗键之后再也起不了拖）" % mode)
	print("[PROBE] %s一枪后 _drag_touch_idx=%s" % [mode, str(_ov.get("_drag_touch_idx"))])

## 触屏那一枪的三个节拍：只发原生 ScreenTouch / ScreenDrag，一个鼠标事件都不发
## （真机就是这条路）。InputEventScreenTouch.global_position 是只读派生值，只能喂 position。
func _touch_down(at: Vector2) -> void:
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.pressed = true
	t.position = _to_input(at)
	get_tree().root.push_input(t)
	await get_tree().process_frame

func _touch_drag(to: Vector2) -> void:
	var d := InputEventScreenDrag.new()
	d.index = 0
	d.position = _to_input(to)
	d.relative = Vector2(-90, -60)
	get_tree().root.push_input(d)
	await get_tree().process_frame

func _touch_up(to: Vector2) -> void:
	var r := InputEventScreenTouch.new()
	r.index = 0
	r.pressed = false
	r.position = _to_input(to)
	get_tree().root.push_input(r)
	await get_tree().process_frame

## 反例：把修复前的调用形状原样跑一遍 —— 位置必须纹丝不动，才算这条判据有牙齿
func _selftest() -> void:
	_c.check(_ov != null, "覆盖层已开")
	if _ov == null:
		return
	var k: Dictionary = KEYS[0]
	var orig := _snapshot()
	var vp := _hud.get_viewport_rect().size
	var before: Vector2 = _hud.call(String(k["get_px"]))
	var half := SkillButtonView.SKILL_BTN_SIZE * 0.5 + 2.0
	var target := Vector2(
			clampf(before.x + DRAG_OFFSETS[0].x, half, vp.x - half),
			clampf(before.y + DRAG_OFFSETS[0].y, half, vp.y - half))
	var norm := Vector2(target.x / vp.x, target.y / vp.y)
	await _settle(2)
	# 旧写法那一枪必须单独开一个函数：形参错位是 SCRIPT ERROR，会把「发起调用的那一层」整个打断，
	# 留在 _selftest 里 = 后面的断言一条都不跑，还会打一句 ALL PASS（1 项）空转给人看
	_fire_broken_shape(norm)
	await _settle(3)
	var after: Vector2 = _hud.call(String(k["get_px"]))
	_c.check(before.distance_to(after) <= SNAP_EPS,
			"反例：修复前的形状打同一枪，键不动（位移 %.1f）—— 判据抓得住这次回归" % before.distance_to(after))
	# 正例：同一颗键、同一个落点，换成正确调用必须动
	_ov.call("_xy_setter", 0, norm, false)
	await _settle(3)
	var fixed: Vector2 = _hud.call(String(k["get_px"]))
	_c.check(fixed.distance_to(target) <= SNAP_EPS,
			"正例：正确调用把键送到 %.0f,%.0f（实得 %.0f,%.0f）" % [
					target.x, target.y, fixed.x, fixed.y])
	_c.check(_c.passed >= 3, "selftest 记满 3 条账（实得 %d 条，0 条 = 判据空转）" % _c.passed)
	_restore(orig)
	await _settle(2)

## 复刻修复前的调用形状：Callable.bind() 把绑定参数追加到实参表末尾，
## 于是 _xy_setter(drag_id, norm, auto_save) 被调成 (norm, false, 0) —— 形参 1 类型不符
func _fire_broken_shape(norm: Vector2) -> void:
	var broken: Callable = Callable(_ov, "_xy_setter").bind(0)
	broken.call(norm, false)

# ================================ 存档快照 ================================

func _snapshot() -> Dictionary:
	var out := {}
	for k in KEYS:
		out[String(k["cfg"])] = SettingsManager.call(String(k["get_xy"]))
		out[String(k["cfg"]) + "_scale"] = SettingsManager.call(String(k["get_scale"]))
	return out

func _restore(orig: Dictionary) -> void:
	for k in KEYS:
		var cfg := String(k["cfg"])
		SettingsManager.call(String(k["set_xy"]), orig[cfg], true)
		SettingsManager.call(String(k["set_scale"]), orig[cfg + "_scale"], true)

# ================================ 输入枪法 ================================

## 落点换算：center_px()/get_global_rect() 是画布（设计）坐标，push_input 要窗口坐标。
func _to_input(pos: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * pos

func _press(pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.global_position = _to_input(pos)
	e.position = e.global_position
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_tree().root.push_input(e)
	await get_tree().process_frame

func _release(pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.global_position = _to_input(pos)
	e.position = e.global_position
	get_tree().root.push_input(e)
	await get_tree().process_frame

func _motion(pos: Vector2) -> void:
	var p := _to_input(pos)
	var m := InputEventMouseMotion.new()
	m.global_position = p
	m.position = p
	m.relative = p - _last_motion
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	_last_motion = p
	get_tree().root.push_input(m)
	await get_tree().process_frame

## 原地一按一抬（先建立 hover 再按下，与真机手指落点同一套三拍）
func _tap(pos: Vector2) -> void:
	await _motion(pos)
	await _press(pos)
	await _release(pos)
	await get_tree().process_frame

## 按住拎起 → 分四步拖到 to → 放下
func _drag(from: Vector2, to: Vector2) -> void:
	await _motion(from)
	await _press(from)
	for i in range(1, 5):
		await _motion(from.lerp(to, float(i) / 4.0))
	await _settle(2)
	await _release(to)
	await _settle(4)

## 代理钮的视觉中心（覆盖层是 UILayer 下的整屏 Control，其局部坐标 == 画布坐标）
func _proxy_center(field: String) -> Vector2:
	var p: Control = _ov.get(field)
	if p == null:
		return Vector2(INF, INF)
	return p.position + p.pivot_offset

## 读 user://settings.cfg 上真正落盘的那一份（内存里的值证明不了落盘）
func _disk_xy(cfg: String) -> Vector2:
	var cf := ConfigFile.new()
	if cf.load(SettingsManager.SETTINGS_PATH) != OK:
		return Vector2(-1, -1)
	return cf.get_value("display", cfg, Vector2(-1, -1))
