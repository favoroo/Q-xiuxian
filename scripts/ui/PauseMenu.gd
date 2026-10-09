class_name PauseMenu
extends Control

## 暂停菜单：ESC（内置 ui_cancel）或 HUD 暂停按钮触发。
## 暂停模式与 LevelUpDialog 一致：process_mode=ALWAYS + get_tree().paused。
## 升级/商店/结算/开局选器弹窗打开时必然已 paused，故按"未暂停才可打开"
## 即可与它们天然互斥，无需逐个检查。

signal stats_requested
signal settings_requested
signal manual_requested

var _closing: bool = false
var _retry_armed: bool = false
var _retry_btn: Button
var _retry_reset_tween: Tween
var _update_btn: Button
var _ver_label: Label

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	UpdateManager.update_available.connect(_on_update_available)
	UpdateManager.no_update_found.connect(_on_no_update_found)
	UpdateManager.check_failed.connect(_on_check_failed)

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.09, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(330, 0)
	var style := GameStyle.panel(GameStyle.NAVY, GameStyle.SLANT_PLATE, Vector2(9, 11))
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 5
	style.border_color = GameStyle.LINE
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 26)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)

	var title := GameStyle.label(Label.new(), 30, GameStyle.PAPER, 0, GameStyle.INK, true)
	title.text = "暂  停"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var subtitle := GameStyle.label(Label.new(), 13, GameStyle.GREY)
	subtitle.text = "妖潮暂歇 · 灵息归元"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(spacer)

	var resume_btn := _mk_btn("继 续 游 戏", 42, GameStyle.BLUE, GameStyle.YELLOW, 17, GameStyle.PAPER, GameStyle.INK_TEXT)
	resume_btn.pressed.connect(func(): close(true))
	vbox.add_child(resume_btn)

	# 六颗键分三排：整列排下去面板要 593 高 > 540 屏高，
	# 音量条与版本号整块落在屏外点不到（判据 LayoutCheck 量 rect 才看得见）。
	var stats_btn := _mk_btn("人 物 属 性", 36, GameStyle.NAVY2, GameStyle.YELLOW, 15, GameStyle.PAPER, GameStyle.INK_TEXT)
	stats_btn.pressed.connect(_on_stats_pressed)
	var manual_btn := _mk_btn("教 程 手 册", 36, GameStyle.NAVY2, GameStyle.YELLOW, 15, GameStyle.PAPER, GameStyle.INK_TEXT)
	manual_btn.pressed.connect(_on_manual_pressed)
	_add_row(vbox, [stats_btn, manual_btn])

	var settings_btn := _mk_btn("游 戏 设 置", 36, GameStyle.NAVY2, GameStyle.BLUE, 15, GameStyle.PAPER)
	settings_btn.pressed.connect(_on_settings_pressed)
	_update_btn = _mk_btn("检 查 更 新", 36, GameStyle.NAVY2, GameStyle.BLUE, 15, GameStyle.PAPER)
	_update_btn.pressed.connect(_on_check_update_pressed)
	_add_row(vbox, [settings_btn, _update_btn])

	_retry_btn = _mk_btn("重 新 开 始", 36, GameStyle.NAVY2, GameStyle.YELLOW, 15, GameStyle.PAPER)
	_retry_btn.pressed.connect(_on_retry_pressed)
	var quit_btn := _mk_btn("退 出 游 戏", 36, GameStyle.NAVY2, GameStyle.BAD, 15, GameStyle.PAPER)
	quit_btn.pressed.connect(func(): get_tree().quit())
	_add_row(vbox, [_retry_btn, quit_btn])

	# 快捷音量微调（与 SettingsManager 双向同步）
	var vol_title := GameStyle.label(Label.new(), 12, GameStyle.GREY)
	vol_title.text = "快 捷 音 量"
	vol_title.custom_minimum_size = Vector2(0, 16)
	vbox.add_child(vol_title)
	_add_volume_row(vbox, "灵乐", &"BGM")
	_add_volume_row(vbox, "音效", &"SFX")

	_ver_label = Label.new()
	_ver_label.text = "修仙幸存者 " + Version.APP_VERSION_NAME
	_ver_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameStyle.label(_ver_label, 11, GameStyle.GREY)
	vbox.add_child(_ver_label)

func _mk_btn(text: String, h: float, bg: Color, hover_bg: Color, font_size: int,
		font_col: Color, hover_font_col: Color = Color(0, 0, 0, 0)) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, h)
	btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(btn, bg, hover_bg, font_size, font_col, 6.0, hover_font_col)
	return btn

## 一排两颗键：等分面板内宽，键高不变（触屏最小热区）
func _add_row(parent: VBoxContainer, btns: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for b in btns:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	parent.add_child(row)

func _add_volume_row(parent: VBoxContainer, title: String, bus: StringName) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var name_lbl := GameStyle.label(Label.new(), 13, GameStyle.PAPER_DIM)
	name_lbl.text = title
	name_lbl.custom_minimum_size = Vector2(48, 24)
	row.add_child(name_lbl)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 5.0
	slider.value = AudioManager.get_bus_linear(bus) * 100.0
	slider.custom_minimum_size = Vector2(150, 24)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_ALL
	var styles := GameStyle.bar_styles(GameStyle.NAVY2, GameStyle.BLUE)
	slider.add_theme_stylebox_override("slider", styles[0])
	slider.add_theme_stylebox_override("grabber_area", styles[1])
	row.add_child(slider)

	var val_lbl := GameStyle.label(Label.new(), 13, GameStyle.YELLOW)
	val_lbl.text = "%d%%" % int(slider.value)
	val_lbl.custom_minimum_size = Vector2(46, 24)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val_lbl)

	slider.value_changed.connect(func(v: float) -> void:
		AudioManager.set_bus_linear(bus, v / 100.0)
		val_lbl.text = "%d%%" % int(v)
	)
	SettingsManager.audio_volume_changed.connect(func(b: StringName, linear_val: float, _muted: bool) -> void:
		if b == bus and is_instance_valid(slider) and not slider.has_focus():
			slider.set_value_no_signal(linear_val * 100.0)
			val_lbl.text = "%d%%" % int(round(linear_val * 100.0))
	)

func _on_check_update_pressed() -> void:
	if not UpdateManager.pending_update.is_empty():
		UpdateManager.show_update_dialog(UpdateManager.pending_update)
		return
	if UpdateManager.is_checking:
		_update_btn.text = "正在检查更新..."
		UpdateManager.show_toast("正在检查最新版本，请稍候...", GameStyle.BLUE)
		return
	_update_btn.text = "正在检查更新..."
	UpdateManager.check_for_update(true)

func _on_update_available(info: Dictionary) -> void:
	if is_instance_valid(_update_btn):
		_update_btn.text = "发现新版 %s!" % info.get("tag_name", "")

func _on_no_update_found() -> void:
	if is_instance_valid(_update_btn):
		_update_btn.text = "已是最新版本"
		var tw := create_tween()
		tw.tween_interval(2.5)
		tw.tween_callback(func():
			if is_instance_valid(_update_btn):
				_update_btn.text = "检 查 更 新"
		)

func _on_check_failed(err_msg: String) -> void:
	if is_instance_valid(_update_btn):
		_update_btn.text = "检查失败，请重试"
		var tw := create_tween()
		tw.tween_interval(2.5)
		tw.tween_callback(func():
			if is_instance_valid(_update_btn):
				_update_btn.text = "检 查 更 新"
		)

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if visible:
		close()
	elif not get_tree().paused and not GameManager.is_game_over:
		open()
	get_viewport().set_input_as_handled()

func open() -> void:
	if visible or GameManager.is_game_over:
		return
	_closing = false
	_reset_retry_confirm()
	visible = true
	get_tree().paused = true
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.16)

func close(unpause: bool = true) -> void:
	if _closing:
		return
	_closing = true
	_reset_retry_confirm()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.12)
	tw.tween_callback(func():
		visible = false
		if unpause:
			get_tree().paused = false
		_closing = false
	)

func _on_stats_pressed() -> void:
	visible = false
	_closing = false
	_reset_retry_confirm()
	stats_requested.emit()

func _on_manual_pressed() -> void:
	visible = false
	_closing = false
	_reset_retry_confirm()
	manual_requested.emit()

func _on_settings_pressed() -> void:
	visible = false
	_closing = false
	_reset_retry_confirm()
	settings_requested.emit()

func _reset_retry_confirm() -> void:
	_retry_armed = false
	if _retry_reset_tween != null and _retry_reset_tween.is_valid():
		_retry_reset_tween.kill()
		_retry_reset_tween = null
	if is_instance_valid(_retry_btn):
		_retry_btn.text = "重 新 开 始"
		GameStyle.button(_retry_btn, GameStyle.NAVY2, GameStyle.BLUE, 15, GameStyle.PAPER, 6.0)

func _on_retry_pressed() -> void:
	if not _retry_armed:
		_retry_armed = true
		if is_instance_valid(_retry_btn):
			_retry_btn.text = "再点确认重开"
			GameStyle.button(_retry_btn, GameStyle.BAD, GameStyle.YELLOW, 14, GameStyle.PAPER, 6.0, GameStyle.INK_TEXT)
		if _retry_reset_tween != null and _retry_reset_tween.is_valid():
			_retry_reset_tween.kill()
		_retry_reset_tween = create_tween()
		_retry_reset_tween.tween_interval(3.0)
		_retry_reset_tween.tween_callback(_reset_retry_confirm)
		return
	_reset_retry_confirm()
	get_tree().paused = false
	GameManager.reset_run()
	get_tree().reload_current_scene()
