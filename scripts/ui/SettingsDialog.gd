class_name SettingsDialog
extends Control

## 游戏设置弹窗：包含灵音调律（音频）、剑意视界（战斗画面）与演化推衍（系统）三大分类
## 严格遵循 GameStyle 大色块斜切设计语言与硬错位投影，支持键盘 ESC 与遮罩点击退出。

signal closed

var _closing: bool = false
var _current_tab: int = 0
var _tab_buttons: Array[Button] = []
var _pages: Array[Control] = []

# 音频控件映射: bus_name -> { "slider": HSlider, "val_lbl": Label, "mute_btn": Button }
var _audio_controls: Dictionary = {}
# 开关控件映射: key -> Button
var _toggle_controls: Dictionary = {}
# 循环档位控件映射: key -> Button（文本由档位名驱动，不走开/关那套）
var _cycle_controls: Dictionary = {}

var _content_box: MarginContainer
var _reset_tip_lbl: Label

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	SettingsManager.audio_volume_changed.connect(_on_audio_volume_changed)
	SettingsManager.setting_changed.connect(_on_setting_changed)

func _build_ui() -> void:
	# 1. 半透明暗色背景遮罩（拦截点击，支持点击关闭）
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.09, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			close()
	)
	add_child(dim)

	# 2. 居中容器
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	# 3. 斜切大面板（960x540 视口下 740x450）
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(740, 440)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# 卡体登记成「长按键」：面板不是按钮，摇杆认不出 ⇒ 点面板空白处不许在它底下长出摇杆
	panel.add_to_group(DawnJoystick.UI_PRESS_HOLD_GROUP)
	var panel_style := GameStyle.panel(GameStyle.NAVY, GameStyle.SLANT_PLATE, Vector2(8, 9))
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 6
	panel_style.border_color = GameStyle.BLUE
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 14)
	margin.add_child(root_vbox)

	# 4. 顶部标题栏 + Tab 切换栏 + 关闭按钮
	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 14)
	root_vbox.add_child(top_bar)

	var title_box := PanelContainer.new()
	title_box.add_theme_stylebox_override("panel", GameStyle.block(GameStyle.BLUE, GameStyle.SLANT_BAND, Vector2(3, 4)))
	var title_margin := MarginContainer.new()
	title_margin.add_theme_constant_override("margin_left", 14)
	title_margin.add_theme_constant_override("margin_right", 14)
	title_margin.add_theme_constant_override("margin_top", 4)
	title_margin.add_theme_constant_override("margin_bottom", 4)
	var title_lbl := Label.new()
	title_lbl.text = "天 地 律 动  ·  游 戏 设 置"
	GameStyle.label(title_lbl, 18, GameStyle.PAPER, 0, GameStyle.INK, true)
	title_margin.add_child(title_lbl)
	title_box.add_child(title_margin)
	top_bar.add_child(title_box)

	# Tab 按钮组
	var tab_bar := HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 8)
	tab_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(tab_bar)

	_add_tab_button(tab_bar, 0, "✦ 灵音调律")
	_add_tab_button(tab_bar, 1, "✦ 剑意视界")
	_add_tab_button(tab_bar, 2, "✦ 演化推衍")

	var close_btn := Button.new()
	close_btn.text = "返 回"
	close_btn.custom_minimum_size = Vector2(84, 34)
	close_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(close_btn, GameStyle.NAVY2, GameStyle.BLUE, 14, GameStyle.PAPER, 5.0)
	close_btn.pressed.connect(close)
	top_bar.add_child(close_btn)

	# 5. 内容面板区域（带卡槽内衬）
	var content_panel := PanelContainer.new()
	content_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var cont_sb := GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 2, 0.0)
	cont_sb.content_margin_left = 16.0
	cont_sb.content_margin_top = 14.0
	cont_sb.content_margin_right = 16.0
	cont_sb.content_margin_bottom = 14.0
	content_panel.add_theme_stylebox_override("panel", cont_sb)
	root_vbox.add_child(content_panel)

	_content_box = MarginContainer.new()
	_content_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_panel.add_child(_content_box)

	# 6. 分页构建
	_pages.append(_build_audio_page())
	_pages.append(_build_display_page())
	_pages.append(_build_system_page())

	for p in _pages:
		_content_box.add_child(p)

	_switch_tab(0)

func _add_tab_button(parent: HBoxContainer, index: int, text: String) -> void:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(100, 32)
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(func(): _switch_tab(index))
	parent.add_child(btn)
	_tab_buttons.append(btn)

func _switch_tab(index: int) -> void:
	_current_tab = index
	for i in range(_pages.size()):
		_pages[i].visible = (i == index)

	for i in range(_tab_buttons.size()):
		var b := _tab_buttons[i]
		if i == index:
			GameStyle.button(b, GameStyle.BLUE, GameStyle.BLUE_EDGE, 13, GameStyle.PAPER, 5.0)
		else:
			GameStyle.button(b, GameStyle.NAVY2, GameStyle.BLUE, 13, GameStyle.PAPER_DIM, 5.0)

# ----------------- 分页 1：灵音调律（音频总线） -----------------

func _build_audio_page() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 12)
	scroll.add_child(vbox)

	var tip := Label.new()
	tip.text = "天地乾坤四维灵音微调。支持细化静音与音量滑杆调节，数值实时生效并持久存盘。"
	GameStyle.label(tip, 12, GameStyle.GREY)
	vbox.add_child(tip)

	_add_audio_slider_row(vbox, &"Master", "主 音 量", "全局整体音量大小控制")
	_add_audio_slider_row(vbox, &"BGM", "灵乐音量", "背景修仙律动音乐 (BGM)")
	_add_audio_slider_row(vbox, &"SFX", "音效应量", "法术轰鸣、兵刃破空与诛妖音效 (SFX)")
	_add_audio_slider_row(vbox, &"Voice", "道音启示", "天道箴言、人物台词与提示语音 (Voice)")

	return scroll

func _add_audio_slider_row(parent: VBoxContainer, bus: StringName, title: String, desc: String) -> void:
	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var r_st := StyleBoxFlat.new()
	r_st.bg_color = Color(0.06, 0.09, 0.16, 0.7)
	r_st.border_width_left = 3
	r_st.border_color = GameStyle.BLUE
	r_st.content_margin_left = 12.0
	r_st.content_margin_top = 8.0
	r_st.content_margin_right = 12.0
	r_st.content_margin_bottom = 8.0
	row.add_theme_stylebox_override("panel", r_st)
	parent.add_child(row)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	row.add_child(hbox)

	var title_vbox := VBoxContainer.new()
	title_vbox.custom_minimum_size = Vector2(170, 0)
	title_vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(title_vbox)

	var t_lbl := Label.new()
	t_lbl.text = title
	GameStyle.label(t_lbl, 14, GameStyle.PAPER)
	title_vbox.add_child(t_lbl)

	var d_lbl := Label.new()
	d_lbl.text = desc
	GameStyle.label(d_lbl, 11, GameStyle.GREY)
	title_vbox.add_child(d_lbl)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 5.0
	slider.value = SettingsManager.get_bus_volume(bus) * 100.0
	slider.custom_minimum_size = Vector2(180, 24)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_ALL
	var styles := GameStyle.bar_styles(GameStyle.NAVY2, GameStyle.BLUE)
	slider.add_theme_stylebox_override("slider", styles[0])
	slider.add_theme_stylebox_override("grabber_area", styles[1])
	hbox.add_child(slider)

	var val_lbl := Label.new()
	val_lbl.custom_minimum_size = Vector2(50, 24)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	GameStyle.label(val_lbl, 13, GameStyle.YELLOW)
	hbox.add_child(val_lbl)

	var mute_btn := Button.new()
	mute_btn.custom_minimum_size = Vector2(68, 28)
	mute_btn.focus_mode = Control.FOCUS_NONE
	hbox.add_child(mute_btn)

	_audio_controls[bus] = {
		"slider": slider,
		"val_lbl": val_lbl,
		"mute_btn": mute_btn,
	}

	_update_audio_row_ui(bus)

	slider.value_changed.connect(func(v: float):
		SettingsManager.set_bus_volume(bus, v / 100.0)
	)

	mute_btn.pressed.connect(func():
		SettingsManager.toggle_bus_muted(bus)
	)

func _update_audio_row_ui(bus: StringName) -> void:
	if not _audio_controls.has(bus):
		return
	var ctrl: Dictionary = _audio_controls[bus]
	var slider: HSlider = ctrl["slider"]
	var val_lbl: Label = ctrl["val_lbl"]
	var mute_btn: Button = ctrl["mute_btn"]

	var vol := SettingsManager.get_bus_volume(bus)
	var muted := SettingsManager.is_bus_muted(bus)

	if not slider.has_focus():
		slider.set_value_no_signal(vol * 100.0)

	if muted:
		val_lbl.text = "静音"
		val_lbl.add_theme_color_override("font_color", GameStyle.BAD)
		mute_btn.text = "解除静音"
		GameStyle.button(mute_btn, GameStyle.BAD_DK, GameStyle.BAD, 12, GameStyle.PAPER, 4.0)
	else:
		val_lbl.text = "%d%%" % int(round(vol * 100.0))
		val_lbl.add_theme_color_override("font_color", GameStyle.YELLOW)
		mute_btn.text = "静音"
		GameStyle.button(mute_btn, GameStyle.NAVY2, GameStyle.BLUE, 12, GameStyle.PAPER_DIM, 4.0)

# ----------------- 分页 2：剑意视界（战斗与画面特效） -----------------

func _build_display_page() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)

	var tip := Label.new()
	tip.text = "调整战斗反馈与画面视觉效果。针对设备性能或视疲劳体验，可自由启闭顿帧、震屏与跳字。"
	GameStyle.label(tip, 12, GameStyle.GREY)
	vbox.add_child(tip)

	_add_toggle_row(vbox, "damage_numbers", "伤害跳字", "在命中与暴击时展现跳动伤害数字与身法回避标识")
	# 震屏不给「开/关」两态：他想要的是"偶尔来一下"，所以按幅度分四档，人话命名、不暴露系数
	_add_cycle_row(
		vbox,
		"shake_intensity",
		"屏幕震动",
		"只在诛精英、受创、天雷落劫等要紧时刻震一下；点按切换 关闭 / 轻 / 标准 / 强",
		func() -> String: return "震屏 · %s" % SettingsManager.shake_level_label(),
		func() -> bool: return SettingsManager.shake_mult() > 0.0,
		func(): SettingsManager.set_val(&"display", &"shake_intensity", SettingsManager.shake_level_next())
	)
	_add_toggle_row(vbox, "hit_stop", "顿帧打击感", "法刃命中或强敌湮灭瞬间的时空凝滞微顿帧（提高击打顿挫感）")
	_add_toggle_row(vbox, "screen_flash", "受击红晕", "气血受损及濒死警戒时刻屏幕边缘的暗红收缩呼吸晕影")
	_add_toggle_row(vbox, "show_fps", "实时帧率", "在界面左上方常驻呈现当前灵息运转刷新率 (FPS)")
	# 技能按钮停靠档位：右下（拇指区）/ 右中 / 左下，点按循环，HUD 监听 setting_changed 实时挪位
	_add_cycle_row(
		vbox,
		"skill_btn_pos",
		"技能按钮位置",
		"随行神通释放键停靠位置：右下 / 右中 / 左下，按顺手程度点按切换",
		func() -> String: return "位置 · %s" % SettingsManager.skill_btn_pos_label(),
		func() -> bool: return true,
		func(): SettingsManager.set_val(&"display", &"skill_btn_pos", SettingsManager.skill_btn_pos_next())
	)

	return scroll

## 通用行外壳：左「标题 + 说明」右控件的深蓝斜条，开关行与档位行共用同一份摆位
func _add_row_shell(parent: VBoxContainer, title: String, desc: String) -> HBoxContainer:
	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var r_st := StyleBoxFlat.new()
	r_st.bg_color = Color(0.06, 0.09, 0.16, 0.7)
	r_st.border_width_left = 3
	r_st.border_color = GameStyle.BLUE
	r_st.content_margin_left = 12.0
	r_st.content_margin_top = 8.0
	r_st.content_margin_right = 12.0
	r_st.content_margin_bottom = 8.0
	row.add_theme_stylebox_override("panel", r_st)
	parent.add_child(row)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	row.add_child(hbox)

	var title_vbox := VBoxContainer.new()
	title_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(title_vbox)

	var t_lbl := Label.new()
	t_lbl.text = title
	GameStyle.label(t_lbl, 14, GameStyle.PAPER)
	title_vbox.add_child(t_lbl)

	var d_lbl := Label.new()
	d_lbl.text = desc
	GameStyle.label(d_lbl, 11, GameStyle.GREY)
	title_vbox.add_child(d_lbl)

	return hbox

func _add_toggle_row(parent: VBoxContainer, key: String, title: String, desc: String) -> void:
	var hbox := _add_row_shell(parent, title, desc)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(96, 30)
	btn.focus_mode = Control.FOCUS_NONE
	hbox.add_child(btn)

	_toggle_controls[key] = btn
	_update_toggle_btn_ui(key)

	btn.pressed.connect(func():
		var cur: bool = bool(SettingsManager.get_val(&"display", StringName(key), true))
		SettingsManager.set_val(&"display", StringName(key), not cur)
	)

func _update_toggle_btn_ui(key: String) -> void:
	if not _toggle_controls.has(key):
		return
	var btn: Button = _toggle_controls[key]
	var is_on: bool = bool(SettingsManager.get_val(&"display", StringName(key), true))

	if is_on:
		btn.text = "已开启  [开]"
		GameStyle.button(btn, GameStyle.YELLOW, GameStyle.YELLOW_EDGE, 13, GameStyle.INK_TEXT, 5.0)
	else:
		btn.text = "已关闭  [关]"
		GameStyle.button(btn, GameStyle.NAVY2, GameStyle.BLUE, 13, GameStyle.PAPER_DIM, 5.0)

## 多档循环行：点一下走下一档，文本直接写当前档位的人话名
## level_text / is_on / on_press 由调用方给，控件本身不认识任何具体设置项
func _add_cycle_row(parent: VBoxContainer, key: String, title: String, desc: String,
		level_text: Callable, is_on: Callable, on_press: Callable) -> void:
	var hbox := _add_row_shell(parent, title, desc)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(132, 30)
	btn.focus_mode = Control.FOCUS_NONE
	hbox.add_child(btn)

	_cycle_controls[key] = {
		"btn": btn,
		"level_text": level_text,
		"is_on": is_on,
	}
	_update_cycle_btn_ui(key)

	btn.pressed.connect(func():
		on_press.call()
	)

func _update_cycle_btn_ui(key: String) -> void:
	if not _cycle_controls.has(key):
		return
	var ctrl: Dictionary = _cycle_controls[key]
	var btn: Button = ctrl["btn"]
	btn.text = String((ctrl["level_text"] as Callable).call())
	if bool((ctrl["is_on"] as Callable).call()):
		GameStyle.button(btn, GameStyle.YELLOW, GameStyle.YELLOW_EDGE, 13, GameStyle.INK_TEXT, 5.0)
	else:
		GameStyle.button(btn, GameStyle.NAVY2, GameStyle.BLUE, 13, GameStyle.PAPER_DIM, 5.0)

# ----------------- 分页 3：演化推衍（系统与拓展） -----------------

func _build_system_page() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 14)
	scroll.add_child(vbox)

	var info_panel := PanelContainer.new()
	var ip_st := GameStyle.outlined_panel(GameStyle.NAVY2, GameStyle.LINE, 1, 0.0)
	ip_st.content_margin_left = 14.0
	ip_st.content_margin_top = 12.0
	ip_st.content_margin_right = 14.0
	ip_st.content_margin_bottom = 12.0
	info_panel.add_theme_stylebox_override("panel", ip_st)
	vbox.add_child(info_panel)

	var ip_vbox := VBoxContainer.new()
	ip_vbox.add_theme_constant_override("separation", 6)
	info_panel.add_child(ip_vbox)

	var ver_title := Label.new()
	ver_title.text = "✦ 当前运行状态"
	GameStyle.label(ver_title, 14, GameStyle.YELLOW)
	ip_vbox.add_child(ver_title)

	var ver_lbl := Label.new()
	ver_lbl.text = "游戏版本：修仙幸存者 " + Version.APP_VERSION_NAME + " (Godot 4.7 Forward+)"
	GameStyle.label(ver_lbl, 13, GameStyle.PAPER)
	ip_vbox.add_child(ver_lbl)

	var res_lbl := Label.new()
	res_lbl.text = "渲染规格：960×540 基准视口 · 像素平滑过滤 Nearest"
	GameStyle.label(res_lbl, 13, GameStyle.PAPER_DIM)
	ip_vbox.add_child(res_lbl)

	var exp_panel := PanelContainer.new()
	var ep_st := GameStyle.outlined_panel(GameStyle.NAVY2, GameStyle.LINE, 1, 0.0)
	ep_st.content_margin_left = 14.0
	ep_st.content_margin_top = 12.0
	ep_st.content_margin_right = 14.0
	ep_st.content_margin_bottom = 12.0
	exp_panel.add_theme_stylebox_override("panel", ep_st)
	vbox.add_child(exp_panel)

	var ep_vbox := VBoxContainer.new()
	ep_vbox.add_theme_constant_override("separation", 6)
	exp_panel.add_child(ep_vbox)

	var exp_title := Label.new()
	exp_title.text = "✦ 后续功能规划预留"
	GameStyle.label(exp_title, 14, GameStyle.YELLOW)
	ep_vbox.add_child(exp_title)

	var exp_desc := Label.new()
	exp_desc.text = "包含自定义虚拟摇杆位置锁定、键位映射配置、画质渲染级别选择、多语言本地化等设定将在后续版本陆续拓展接入。"
	GameStyle.label(exp_desc, 12, GameStyle.GREY)
	exp_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ep_vbox.add_child(exp_desc)

	# 恢复默认设置按钮
	var bottom_hbox := HBoxContainer.new()
	bottom_hbox.add_theme_constant_override("separation", 12)
	vbox.add_child(bottom_hbox)

	var reset_btn := Button.new()
	reset_btn.text = "恢 复 默 认 设 置"
	reset_btn.custom_minimum_size = Vector2(160, 36)
	reset_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(reset_btn, GameStyle.NAVY2, GameStyle.BAD, 13, GameStyle.PAPER, 5.0)
	reset_btn.pressed.connect(_on_reset_pressed)
	bottom_hbox.add_child(reset_btn)

	_reset_tip_lbl = Label.new()
	_reset_tip_lbl.text = ""
	GameStyle.label(_reset_tip_lbl, 13, GameStyle.GOOD)
	bottom_hbox.add_child(_reset_tip_lbl)

	return scroll

func _on_reset_pressed() -> void:
	SettingsManager.reset_to_defaults()
	_reset_tip_lbl.text = "已恢复所有预设默认值！"
	var tw := create_tween()
	tw.tween_interval(2.5)
	tw.tween_callback(func():
		if is_instance_valid(_reset_tip_lbl):
			_reset_tip_lbl.text = ""
	)

# ----------------- 信号监听与刷新 -----------------

func _on_audio_volume_changed(bus: StringName, _linear_val: float, _muted: bool) -> void:
	_update_audio_row_ui(bus)

func _on_setting_changed(section: StringName, key: StringName, _val: Variant) -> void:
	if String(section) == "display":
		# 两个控件都要刷：档位与旧的 screen_shake 总开关是同源的一对，改一个会连带动另一个
		_update_toggle_btn_ui(String(key))
		_update_cycle_btn_ui(String(key))

func _refresh_all_ui() -> void:
	for bus in [&"Master", &"BGM", &"SFX", &"Voice"]:
		_update_audio_row_ui(bus)
	for k in _toggle_controls.keys():
		_update_toggle_btn_ui(k)
	for k in _cycle_controls.keys():
		_update_cycle_btn_ui(k)

# ----------------- 弹窗开关控制 -----------------

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func open() -> void:
	if visible:
		return
	_closing = false
	_refresh_all_ui()
	visible = true
	get_tree().paused = true
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.16)

func close() -> void:
	if _closing or not visible:
		return
	_closing = true
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.12)
	tw.tween_callback(func():
		visible = false
		_closing = false
		closed.emit()
	)
