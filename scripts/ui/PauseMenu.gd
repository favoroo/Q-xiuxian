class_name PauseMenu
extends Control

## 暂停菜单：ESC（内置 ui_cancel）或 HUD 暂停按钮触发。
## 暂停模式与 LevelUpDialog 一致：process_mode=ALWAYS + get_tree().paused。
## 升级/商店/结算/开局选器弹窗打开时必然已 paused，故按"未暂停才可打开"
## 即可与它们天然互斥，无需逐个检查。

signal stats_requested

var _closing: bool = false
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

	var resume_btn := Button.new()
	resume_btn.text = "继 续 游 戏"
	resume_btn.custom_minimum_size = Vector2(0, 46)
	resume_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(resume_btn, GameStyle.BLUE, GameStyle.YELLOW, 17, GameStyle.PAPER, 6.0, GameStyle.INK_TEXT)
	resume_btn.pressed.connect(func(): close(true))
	vbox.add_child(resume_btn)

	var stats_btn := Button.new()
	stats_btn.text = "人 物 属 性"
	stats_btn.custom_minimum_size = Vector2(0, 40)
	stats_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(stats_btn, GameStyle.NAVY2, GameStyle.YELLOW, 15, GameStyle.PAPER, 6.0, GameStyle.INK_TEXT)
	stats_btn.pressed.connect(_on_stats_pressed)
	vbox.add_child(stats_btn)

	var retry_btn := Button.new()
	retry_btn.text = "重 新 开 始"
	retry_btn.custom_minimum_size = Vector2(0, 40)
	retry_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(retry_btn, GameStyle.NAVY2, GameStyle.BLUE, 15, GameStyle.PAPER)
	retry_btn.pressed.connect(_on_retry_pressed)
	vbox.add_child(retry_btn)

	_update_btn = Button.new()
	_update_btn.text = "检 查 更 新"
	_update_btn.custom_minimum_size = Vector2(0, 40)
	_update_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(_update_btn, GameStyle.NAVY2, GameStyle.BLUE, 15, GameStyle.PAPER)
	_update_btn.pressed.connect(_on_check_update_pressed)
	vbox.add_child(_update_btn)

	var quit_btn := Button.new()
	quit_btn.text = "退 出 游 戏"
	quit_btn.custom_minimum_size = Vector2(0, 40)
	quit_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(quit_btn, GameStyle.NAVY2, GameStyle.BAD, 15, GameStyle.PAPER)
	quit_btn.pressed.connect(func(): get_tree().quit())
	vbox.add_child(quit_btn)

	_ver_label = Label.new()
	_ver_label.text = "修仙幸存者 " + Version.APP_VERSION_NAME
	_ver_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameStyle.label(_ver_label, 11, GameStyle.GREY)
	vbox.add_child(_ver_label)

func _on_check_update_pressed() -> void:
	if UpdateManager.is_checking:
		return
	if not UpdateManager.pending_update.is_empty():
		UpdateManager.show_update_dialog(UpdateManager.pending_update)
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
	visible = true
	get_tree().paused = true
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.16)

func close(unpause: bool = true) -> void:
	if _closing:
		return
	_closing = true
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
	stats_requested.emit()

func _on_retry_pressed() -> void:
	get_tree().paused = false
	GameManager.reset_run()
	get_tree().reload_current_scene()
