class_name HudEditOverlay
extends Control

## 按钮调整模式覆盖层：把技能键 / 额外技能键 / 祭坛键亮在真实位置上，手指自由拖动摆放。
## 位置以归一化中心点写回 SettingsManager（拖动中不落盘，松手才存）；
## 大小在设置·操作页的滑杆调。代理钮每帧与真实按钮互相同步：
## 真实按钮是摆位真话（含屏内夹取），拖动写设置 → HUD 套用 → 代理跟着走。

signal finished

const DRAG_NONE: int = -1
const DRAG_SKILL: int = 0
const DRAG_OBELISK: int = 1
const DRAG_EXTRA: int = 2

var _hud: GameHUD = null
var _skill_proxy: Button = null
var _obelisk_proxy: Button = null
var _extra_proxy: Button = null
var _built: bool = false

## 选中态：滑杆永远只调选中的那颗（按下代理钮即选中）
var _selected: int = DRAG_SKILL
var _size_slider: HSlider = null
var _size_lbl: Label = null
var _sel_label: Label = null

var _drag_id: int = DRAG_NONE
var _drag_off: Vector2 = Vector2.ZERO
var _drag_touch_idx: int = -100  # -100 = 鼠标拖动；≥0 = 触控 index
var _pointer: Vector2 = Vector2.ZERO

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

func open(hud: GameHUD) -> void:
	_hud = hud
	if not _built:
		_build()
		_built = true
	visible = true
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.15)

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = GameStyle.dim_overlay(0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var top_strip := CenterContainer.new()
	top_strip.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_strip.offset_top = 18.0
	top_strip.offset_bottom = 58.0
	top_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_strip)
	var hint := Label.new()
	hint.text = "点选按钮拖到顺手的位置 · 滑杆只调选中的那颗"
	GameStyle.label(hint, 15, GameStyle.CHALK, 3, GameStyle.INK)
	top_strip.add_child(hint)

	_skill_proxy = Button.new()
	_skill_proxy.text = "技"
	_skill_proxy.custom_minimum_size = Vector2(SkillButtonView.SKILL_BTN_SIZE, SkillButtonView.SKILL_BTN_SIZE)
	_skill_proxy.mouse_filter = Control.MOUSE_FILTER_STOP
	_skill_proxy.focus_mode = Control.FOCUS_NONE
	SkillButtonView.style_circle_button(_skill_proxy)
	_skill_proxy.gui_input.connect(_on_proxy_input.bind(DRAG_SKILL))
	add_child(_skill_proxy)

	_obelisk_proxy = Button.new()
	_obelisk_proxy.text = GameHUD.OBELISK_BTN_TEXT
	_obelisk_proxy.custom_minimum_size = GameHUD.OBELISK_BTN_SIZE
	_obelisk_proxy.mouse_filter = Control.MOUSE_FILTER_STOP
	_obelisk_proxy.focus_mode = Control.FOCUS_NONE
	SkillButtonView.style_circle_action(_obelisk_proxy, GameStyle.GOLD, GameHUD.OBELISK_BTN_FONT)
	_obelisk_proxy.gui_input.connect(_on_proxy_input.bind(DRAG_OBELISK))
	add_child(_obelisk_proxy)

	# 额外技能键代理：与真实键同款式同文案（它就是 HudSkillButton 的额外槽位）
	_extra_proxy = Button.new()
	_extra_proxy.text = HudSkillButton.EXTRA_BTN_TEXT
	_extra_proxy.custom_minimum_size = Vector2(SkillButtonView.SKILL_BTN_SIZE, SkillButtonView.SKILL_BTN_SIZE)
	_extra_proxy.mouse_filter = Control.MOUSE_FILTER_STOP
	_extra_proxy.focus_mode = Control.FOCUS_NONE
	SkillButtonView.style_circle_button(_extra_proxy, HudSkillButton.EXTRA_BTN_FONT)
	_extra_proxy.gui_input.connect(_on_proxy_input.bind(DRAG_EXTRA))
	add_child(_extra_proxy)

	var bottom_strip := CenterContainer.new()
	bottom_strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_strip.offset_top = -66.0
	bottom_strip.offset_bottom = -22.0
	add_child(bottom_strip)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	bottom_strip.add_child(bar)

	# 选中指示 chip：滑杆调谁，看它就知道
	var sel_chip := PanelContainer.new()
	sel_chip.add_theme_stylebox_override("panel", GameStyle.chip(GameStyle.JADE))
	_sel_label = Label.new()
	_sel_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameStyle.label(_sel_label, 13, GameStyle.INK_TEXT)
	sel_chip.add_child(_sel_label)
	bar.add_child(sel_chip)

	# 单滑杆：点选哪颗钮就调哪颗的大小（60%~180%，步进 5%，与音频滑杆同款即时落盘）
	_size_slider = HSlider.new()
	_size_slider.min_value = SettingsManager.BTN_SCALE_MIN * 100.0
	_size_slider.max_value = SettingsManager.BTN_SCALE_MAX * 100.0
	_size_slider.step = 5.0
	_size_slider.custom_minimum_size = Vector2(230, 24)
	_size_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_size_slider.focus_mode = Control.FOCUS_ALL
	var s_styles := GameStyle.bar_styles(GameStyle.NAVY2, GameStyle.GOLD)
	_size_slider.add_theme_stylebox_override("slider", s_styles[0])
	_size_slider.add_theme_stylebox_override("grabber_area", s_styles[1])
	bar.add_child(_size_slider)
	_size_slider.value_changed.connect(_on_size_slider_changed)

	_size_lbl = Label.new()
	_size_lbl.custom_minimum_size = Vector2(48, 24)
	_size_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_size_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	GameStyle.label(_size_lbl, 13, GameStyle.JADE_EDGE)
	bar.add_child(_size_lbl)

	var reset_btn := Button.new()
	reset_btn.text = "恢复默认位置"
	reset_btn.custom_minimum_size = Vector2(150, 36)
	reset_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(reset_btn, GameStyle.NAVY2, GameStyle.BAD, 14, GameStyle.PAPER, 5.0)
	reset_btn.pressed.connect(func():
		SettingsManager.reset_button_layout()
		_sync_size_slider()
	)
	bar.add_child(reset_btn)

	var done_btn := Button.new()
	done_btn.text = "完 成"
	done_btn.custom_minimum_size = Vector2(130, 36)
	done_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(done_btn, GameStyle.GOLD, GameStyle.GOLD_EDGE, 14, GameStyle.INK_TEXT, 5.0)
	done_btn.pressed.connect(finish)
	bar.add_child(done_btn)

	_select(_selected)

# ---------------- 槽位 → 设置项的取数口径（三颗键一张表，不再 if/else 串行） ----------------

func _proxy_of(drag_id: int) -> Button:
	match drag_id:
		DRAG_SKILL:
			return _skill_proxy
		DRAG_OBELISK:
			return _obelisk_proxy
		DRAG_EXTRA:
			return _extra_proxy
	return null

func _scale_getter(drag_id: int) -> float:
	match drag_id:
		DRAG_OBELISK:
			return SettingsManager.obelisk_btn_scale()
		DRAG_EXTRA:
			return SettingsManager.extra_btn_scale()
	return SettingsManager.skill_btn_scale()

func _scale_setter(drag_id: int, v: float) -> void:
	match drag_id:
		DRAG_OBELISK:
			SettingsManager.set_obelisk_btn_scale(v)
		DRAG_EXTRA:
			SettingsManager.set_extra_btn_scale(v)
		_:
			SettingsManager.set_skill_btn_scale(v)

func _xy_setter(drag_id: int, norm: Vector2, auto_save: bool) -> void:
	match drag_id:
		DRAG_OBELISK:
			SettingsManager.set_obelisk_btn_xy(norm, auto_save)
		DRAG_EXTRA:
			SettingsManager.set_extra_btn_xy(norm, auto_save)
		_:
			SettingsManager.set_skill_btn_xy(norm, auto_save)

func _sel_name(drag_id: int) -> String:
	match drag_id:
		DRAG_OBELISK:
			return "祭坛按钮"
		DRAG_EXTRA:
			# 用户 2026-10-11：「额外技能按钮」太长，chip 里写「额外技能」就够指认这颗键
			return "额外技能"
	return "技能按钮"

# ---------------- 每帧同步：真实按钮是摆位真话，代理钮贴上去 ----------------

func _process(_delta: float) -> void:
	if not visible or _hud == null:
		return
	if _drag_id != DRAG_NONE:
		_apply_drag(_drag_id)
	_sync_proxy(_skill_proxy, _hud.skill_btn_center_px(), SettingsManager.skill_btn_scale())
	_sync_proxy(_obelisk_proxy, _hud.obelisk_btn_center_px(), SettingsManager.obelisk_btn_scale())
	_sync_proxy(_extra_proxy, _hud.extra_skill_btn_center_px(), SettingsManager.extra_btn_scale())

func _sync_proxy(p: Button, center: Vector2, scale_f: float) -> void:
	if p == null:
		return
	# pivot 钉在矩形中心：视觉中心 = position + pivot，缩放不挪中心
	p.pivot_offset = p.size * 0.5
	p.scale = Vector2(scale_f, scale_f)
	p.position = center - p.size * 0.5

## 拖动中把指针位置写进槽位对应的设置项（不落盘，松手由 _end_drag 统一存）。
## 参数顺序：槽位 id 在前、坐标在后 —— 这里必须是普通调用。
## （用户 2026-10-11 真机：三颗键一颗都拖不动。旧写法 `_apply_drag(_xy_setter.bind(id))`
##  配 `setter.call(norm, false)`，而 Callable.bind() 是把绑定参数**追加到实参表末尾**，
##  于是每帧调成 `_xy_setter(norm, false, id)`：第一个形参要 int 却收到 Vector2，
##  GDScript 直接报 "Cannot convert argument 1 from Vector2 to int" 并放弃这次调用
##  ⇒ 设置项一次都没写进去，真实按钮原地不动，代理钮每帧又被贴回原处，看着就是"按住了拖不走"。）
func _apply_drag(drag_id: int) -> void:
	var vp := get_viewport_rect().size
	var c := _pointer + _drag_off
	var norm := Vector2(
		clampf(c.x / maxf(1.0, vp.x), 0.0, 1.0),
		clampf(c.y / maxf(1.0, vp.y), 0.0, 1.0))
	_xy_setter(drag_id, norm, false)

# ---------------- 指针追踪与拖动生命周期 ----------------

## _input 先于 gui_input 吃到同一拍事件：这里只记指针坐标与收尾，
## 起拖交给代理钮自己的 gui_input（它知道点没点在自己身上）。
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion or event is InputEventScreenDrag:
		_pointer = event.position
	elif event is InputEventScreenTouch:
		if event.pressed:
			_pointer = event.position
		elif _drag_id != DRAG_NONE and event.index == _drag_touch_idx:
			_end_drag()
	elif event is InputEventMouseButton and not event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and _drag_id != DRAG_NONE and _drag_touch_idx == -100:
		_end_drag()

## 代理钮按下：先选中（滑杆跟着切到它），再起拖
## （松手事件走 _input 全局收口，手指滑出钮面也能收得住）
func _on_proxy_input(event: InputEvent, drag_id: int) -> void:
	var pressed := false
	if event is InputEventScreenTouch and event.pressed:
		pressed = true
		_drag_touch_idx = event.index
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed = true
		_drag_touch_idx = -100
	if not pressed or _drag_id != DRAG_NONE:
		return
	_select(drag_id)
	var p := _proxy_of(drag_id)
	_drag_id = drag_id
	_drag_off = (p.position + p.pivot_offset) - _pointer

# ---------------- 选中与大小滑杆 ----------------

## 选中切换：滑杆换读数、chip 换名字、未选中的压暗一眼分清
func _select(drag_id: int) -> void:
	_selected = drag_id
	_sync_size_slider()
	_update_selection_visuals()

func _sync_size_slider() -> void:
	var v: float = _scale_getter(_selected)
	if _size_slider != null:
		_size_slider.set_value_no_signal(v * 100.0)
	_update_size_ui()

func _update_size_ui() -> void:
	if _size_lbl == null:
		return
	_size_lbl.text = "%d%%" % int(round(_size_slider.value))
	_sel_label.text = _sel_name(_selected)

func _update_selection_visuals() -> void:
	for entry in [[DRAG_SKILL, _skill_proxy], [DRAG_OBELISK, _obelisk_proxy], [DRAG_EXTRA, _extra_proxy]]:
		var p: Button = entry[1]
		if p != null:
			p.modulate = GameStyle.with_alpha(Color.WHITE, 1.0 if _selected == int(entry[0]) else 0.5)

## 滑杆只调当前选中的那颗
func _on_size_slider_changed(v: float) -> void:
	_scale_setter(_selected, v / 100.0)
	_update_size_ui()

func _end_drag() -> void:
	# 与拖动中同一份值再 set 一次触发落盘 + setting_changed（HUD 套用夹取后的最终位）
	if _drag_id != DRAG_NONE:
		_xy_setter(_drag_id, _xy_getter(_drag_id), true)
	_drag_id = DRAG_NONE
	_drag_touch_idx = -100

func _xy_getter(drag_id: int) -> Vector2:
	match drag_id:
		DRAG_OBELISK:
			return SettingsManager.obelisk_btn_xy()
		DRAG_EXTRA:
			return SettingsManager.extra_btn_xy()
	return SettingsManager.skill_btn_xy()

func finish() -> void:
	if not visible:
		return
	_end_drag()
	visible = false
	finished.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		finish()
		get_viewport().set_input_as_handled()
