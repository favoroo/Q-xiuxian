class_name PauseMenu
extends Control

## 暂停菜单：ESC（内置 ui_cancel）或 HUD 暂停按钮触发。
## 暂停模式与 LevelUpDialog 一致：process_mode=ALWAYS + get_tree().paused。
## 升级/商店/结算/开局选器弹窗打开时必然已 paused，故按"未暂停才可打开"
## 即可与它们天然互斥，无需逐个检查。

signal stats_requested
signal settings_requested
signal manual_requested

var _unpause_on_close: bool = true
var _closing: bool = false
var _retry_armed: bool = false
var _retry_btn: Button
var _menu_btn: Button
var _retry_reset_tween: Tween
var _close_tween: Tween
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
	dim.color = GameStyle.dim_overlay(0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(330, 0)
	# 卡体登记成「长按键」：面板不是按钮，摇杆认不出 ⇒ 点面板空白处不许在它底下长出摇杆
	panel.add_to_group(DawnJoystick.UI_PRESS_HOLD_GROUP)
	var style := GameStyle.dialog_panel(GameStyle.INK, GameStyle.SLANT_PLATE, Vector2(9, 11))
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
	title.text = "暂 停"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var subtitle := GameStyle.label(Label.new(), 13, GameStyle.GREY)
	subtitle.text = "战斗暂停 · 休整片刻"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(spacer)

	var resume_btn := _mk_btn("继 续 游 戏", 42, GameStyle.GOLD, GameStyle.JADE, 17, GameStyle.PAPER, GameStyle.INK_TEXT)
	resume_btn.pressed.connect(func(): close(true))
	vbox.add_child(resume_btn)

	# 六颗键分三排：整列排下去面板要 593 高 > 540 屏高，
	# 音量条与版本号整块落在屏外点不到（判据 LayoutCheck 量 rect 才看得见）。
	var stats_btn := _mk_btn("角 色 属 性", 36, GameStyle.NAVY2, GameStyle.JADE, 15, GameStyle.PAPER, GameStyle.INK_TEXT)
	stats_btn.pressed.connect(_on_stats_pressed)
	var manual_btn := _mk_btn("教 程 手 册", 36, GameStyle.NAVY2, GameStyle.JADE, 15, GameStyle.PAPER, GameStyle.INK_TEXT)
	manual_btn.pressed.connect(_on_manual_pressed)
	_add_row(vbox, [stats_btn, manual_btn])

	var settings_btn := _mk_btn("游 戏 设 置", 36, GameStyle.NAVY2, GameStyle.GOLD, 15, GameStyle.PAPER)
	settings_btn.pressed.connect(_on_settings_pressed)
	_update_btn = _mk_btn("检 查 更 新", 36, GameStyle.NAVY2, GameStyle.GOLD, 15, GameStyle.PAPER)
	_update_btn.pressed.connect(_on_check_update_pressed)
	_add_row(vbox, [settings_btn, _update_btn])

	_retry_btn = _mk_btn("重 新 开 始", 36, GameStyle.NAVY2, GameStyle.JADE, 15, GameStyle.PAPER)
	_retry_btn.pressed.connect(_on_retry_pressed)
	_menu_btn = _mk_btn("返 回 主 菜 单", 36, GameStyle.NAVY2, GameStyle.GOLD, 15, GameStyle.PAPER)
	_menu_btn.pressed.connect(_on_menu_pressed)
	_add_row(vbox, [_retry_btn, _menu_btn])

	# 快捷音量微调（与 SettingsManager 双向同步）
	var vol_title := GameStyle.label(Label.new(), 12, GameStyle.GREY)
	vol_title.text = "快 捷 音 量"
	vol_title.custom_minimum_size = Vector2(0, 16)
	vbox.add_child(vol_title)
	_add_volume_row(vbox, "音乐", &"BGM")
	_add_volume_row(vbox, "音效", &"SFX")

	_ver_label = Label.new()
	_ver_label.text = Version.APP_NAME + " " + Version.APP_VERSION_NAME
	_ver_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameStyle.label(_ver_label, 11, GameStyle.GREY)
	vbox.add_child(_ver_label)

func _mk_btn(text: String, h: float, bg: Color, hover_bg: Color, font_size: int,
		font_col: Color, hover_font_col: Color = Color.TRANSPARENT) -> Button:
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
	var styles := GameStyle.bar_styles(GameStyle.NAVY2, GameStyle.GOLD)
	slider.add_theme_stylebox_override("slider", styles[0])
	slider.add_theme_stylebox_override("grabber_area", styles[1])
	row.add_child(slider)

	var val_lbl := GameStyle.label(Label.new(), 13, GameStyle.JADE)
	val_lbl.text = "%d%%" % int(slider.value)
	val_lbl.custom_minimum_size = Vector2(46, 24)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val_lbl)

	slider.value_changed.connect(func(v: float) -> void:
		# 拖动途中只改内存与总线（persist=false），松手才落盘，避免每 5% 步长同步写文件
		AudioManager.set_bus_linear(bus, v / 100.0, false)
		val_lbl.text = "%d%%" % int(v)
	)
	slider.drag_ended.connect(func(value_changed: bool) -> void:
		if value_changed:
			AudioManager.set_bus_linear(bus, slider.value / 100.0, true)
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
		UpdateManager.show_toast("正在检查最新版本，请稍候...", GameStyle.GOLD)
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

## 检查背后是否有加点、商店或局前选人等需要保持暂停的弹窗（含全部二级弹窗）
func _has_paused_modal_behind() -> bool:
	var p := get_parent()
	if p == null:
		return false
	for name_str in [
		"LevelUpDialog", "WaveShop", "StartMenu", "CultivatorSelect", "SkillSelect",
		"StartWeaponSelect", "GameOverDialog", "PlayerStatsDialog", "SettingsDialog",
		"ManualDialog", "TutorialDialog", "CareerDialog", "ChangelogDialog", "UpdateDialog"
	]:
		var n := p.get_node_or_null(name_str) as Control
		if n != null and n.visible:
			return true
	return false

## 检查当前是否处于不应响应全局暂停的局前/结算状态
func _is_pregame_or_settlement() -> bool:
	if GameManager.is_game_over:
		return true
	var p := get_parent()
	if p == null:
		return false
	for name_str in ["StartMenu", "CultivatorSelect", "SkillSelect", "StartWeaponSelect", "GameOverDialog"]:
		var n := p.get_node_or_null(name_str) as Control
		if n != null and n.visible:
			return true
	return false

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if visible:
		close()
		get_viewport().set_input_as_handled()
		return
	if _is_pregame_or_settlement():
		# 局前选人选武器或结算界面，不拦截 ESC，留给各界面自己的返回逻辑
		return
	# 战斗中或加点/商店中：若有展开的气泡详情卡则先收起气泡
	var p := get_parent()
	if p != null:
		for name_str in ["LevelUpDialog", "WaveShop", "GameHUD"]:
			var n := p.get_node_or_null(name_str) as Control
			if n != null and n.visible and DetailTip.close_all(n):
				get_viewport().set_input_as_handled()
				return
	open()
	get_viewport().set_input_as_handled()

func _kill_close_tween() -> void:
	if _close_tween != null and _close_tween.is_valid():
		_close_tween.kill()
		_close_tween = null

func open(unpause_on_close: Variant = null) -> void:
	if visible or GameManager.is_game_over:
		return
	_kill_close_tween()
	var behind := _has_paused_modal_behind()
	if unpause_on_close != null:
		_unpause_on_close = bool(unpause_on_close) and not behind
	else:
		_unpause_on_close = not behind
	_closing = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reset_retry_confirm()
	visible = true
	get_tree().paused = true
	modulate.a = 0.0
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(self, "modulate:a", 1.0, 0.16)

func close(unpause: bool = true) -> void:
	if _closing:
		return
	_closing = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_reset_retry_confirm()
	_kill_close_tween()
	_close_tween = create_tween()
	_close_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_close_tween.tween_property(self, "modulate:a", 0.0, 0.12)
	_close_tween.tween_callback(func():
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var should_unpause := unpause and _unpause_on_close and not _has_paused_modal_behind()
		if should_unpause:
			get_tree().paused = false
		_closing = false
		_close_tween = null
	)

func _on_stats_pressed() -> void:
	_kill_close_tween()
	visible = false
	_closing = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reset_retry_confirm()
	stats_requested.emit()

func _on_manual_pressed() -> void:
	_kill_close_tween()
	visible = false
	_closing = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reset_retry_confirm()
	manual_requested.emit()

func _on_settings_pressed() -> void:
	_kill_close_tween()
	visible = false
	_closing = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reset_retry_confirm()
	settings_requested.emit()

func _reset_retry_confirm() -> void:
	_retry_armed = false
	if _retry_reset_tween != null and _retry_reset_tween.is_valid():
		_retry_reset_tween.kill()
		_retry_reset_tween = null
	if is_instance_valid(_retry_btn):
		_retry_btn.text = "重 新 开 始"
		GameStyle.button(_retry_btn, GameStyle.NAVY2, GameStyle.GOLD, 15, GameStyle.PAPER, 6.0, GameStyle.INK_TEXT)

func _on_retry_pressed() -> void:
	if not _retry_armed:
		_retry_armed = true
		if is_instance_valid(_retry_btn):
			_retry_btn.text = "再点确认重开"
			GameStyle.button(_retry_btn, GameStyle.BAD, GameStyle.JADE, 14, GameStyle.CHALK, 6.0, GameStyle.INK_TEXT)
		if _retry_reset_tween != null and _retry_reset_tween.is_valid():
			_retry_reset_tween.kill()
		_retry_reset_tween = create_tween()
		_retry_reset_tween.tween_interval(3.0)
		_retry_reset_tween.tween_callback(_reset_retry_confirm)
		return
	_reset_retry_confirm()
	if is_instance_valid(_retry_btn):
		_retry_btn.text = "正在重置..."
		_retry_btn.disabled = true
	get_tree().paused = false
	# 带标记重载：Main._ready 消费后跳过主菜单，直落选角界面重开一把
	GameManager.restart_to_select = true
	GameManager.reset_run()
	await get_tree().process_frame
	get_tree().reload_current_scene()

## 返回主菜单：整场景重载，Main._ready 默认开主菜单；战场残留随场景重建一并清空
## 与「重新开始」同规格：先禁用按钮 + 画出一帧「正在返回」再同步重载整树，
## 否则 press 当帧直接重建场景（实测同级操作 124~181ms），用户看到的是冻死无反馈
func _on_menu_pressed() -> void:
	_reset_retry_confirm()
	if is_instance_valid(_menu_btn):
		_menu_btn.text = "正在返回..."
		_menu_btn.disabled = true
	get_tree().paused = false
	GameManager.reset_run()
	await get_tree().process_frame
	get_tree().reload_current_scene()
