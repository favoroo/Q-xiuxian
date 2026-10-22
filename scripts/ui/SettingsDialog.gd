class_name SettingsDialog
extends BaseModalDialog

## 游戏设置弹窗：灵音调律（音频）/ 剑意视界（战斗画面）/ 运指开阖（操作按钮布局）/ 演化推衍（系统）四大分类
## 继承 BaseModalDialog，严格遵循 GameStyle 大色块斜切设计语言与硬错位投影。

# 音频控件映射: bus_name -> { "slider": HSlider, "val_lbl": Label, "mute_btn": Button }
var _audio_controls: Dictionary = {}
# 开关控件映射: key -> Button
var _toggle_controls: Dictionary = {}
# 循环档位控件映射: key -> Button（文本由档位名驱动，不走开/关那套）
var _cycle_controls: Dictionary = {}

var _content_box: MarginContainer
var _reset_tip_lbl: Label
var _changelog_dialog: ChangelogDialog = null
var _check_update_btn: Button
var _update_tip_lbl: Label
# 主题色块：id -> PanelContainer（选中框按当前主题刷新）
var _theme_slots: Dictionary = {}
var _theme_name_lbl: Label = null

func _get_title_text() -> String:
	return "游 戏 设 置"

func _get_panel_size() -> Vector2:
	return Vector2(740, 440)

func _get_panel_margins() -> Vector4:
	return Vector4(26, 18, 26, 18)

func _get_vbox_separation() -> int:
	return 14

func _get_top_bar_separation() -> int:
	return 14

func _build_body(root_vbox: VBoxContainer) -> void:
	add_tab_button(0, "◆ 音效")
	add_tab_button(1, "◆ 画面")
	add_tab_button(2, "◆ 操作")
	add_tab_button(3, "◆ 其他")

	var content_panel := PanelContainer.new()
	content_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var cont_sb := GameStyle.outlined_panel(GameStyle.NAVY2, GameStyle.INK, 2, 0.0)
	cont_sb.content_margin_left = 16.0
	cont_sb.content_margin_top = 14.0
	cont_sb.content_margin_right = 16.0
	cont_sb.content_margin_bottom = 14.0
	content_panel.add_theme_stylebox_override("panel", cont_sb)
	root_vbox.add_child(content_panel)

	_content_box = MarginContainer.new()
	_content_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_panel.add_child(_content_box)

	_pages.append(_build_audio_page())
	_pages.append(_build_display_page())
	_pages.append(_build_controls_page())
	_pages.append(_build_system_page())

	for p in _pages:
		_content_box.add_child(p)

	# 底部常驻动作条：新手指南任何页签都在手边（原「其他」页单页入口上提，免翻页找）
	var foot_bar := HBoxContainer.new()
	foot_bar.add_theme_constant_override("separation", 12)
	root_vbox.add_child(foot_bar)

	var guide_btn := Button.new()
	guide_btn.text = "◆ 新手指南"
	guide_btn.custom_minimum_size = Vector2(130, 32)
	guide_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(guide_btn, GameStyle.NAVY2, GameStyle.JADE, 13, GameStyle.PAPER, 5.0, GameStyle.INK_TEXT)
	guide_btn.pressed.connect(_open_tutorial)
	foot_bar.add_child(guide_btn)

	switch_tab(0)
	SettingsManager.audio_volume_changed.connect(_on_audio_volume_changed)
	SettingsManager.setting_changed.connect(_on_setting_changed)
	SettingsManager.theme_color_changed.connect(_on_theme_color_changed)

	UpdateManager.update_available.connect(func(_info: Dictionary):
		_on_update_check_done("发现新版本，已弹出更新视窗", GameStyle.GOOD)
	)
	UpdateManager.no_update_found.connect(func():
		_on_update_check_done("当前已是最新版本 (%s)" % Version.APP_VERSION_NAME, GameStyle.GOOD)
	)
	UpdateManager.check_failed.connect(func(err_msg: String):
		_on_update_check_done("检测失败（%s）" % err_msg, GameStyle.BAD)
	)

	# 三页整棵子树放开「按下」冒泡：设置行是 PanelContainer（mouse_filter 默认 STOP），
	# 会把外层 ScrollContainer 起手锁定手指拖动要的那一拍吃掉 → 真机上只有卡片缝隙能划。
	# 行控件（HSlider / Button）自己收事件，降成 PASS 不影响拖滑杆与点按钮。
	# 本弹窗的页签内容只在 _ready 建一次（刷新只改文本），所以这里建完刷一遍就够。
	for p in _pages:
		GameStyle.swipeable(p as Control)

func _on_opened() -> void:
	_refresh_all_ui()
	get_tree().paused = true

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
	tip.text = "音效细调。支持静音与音量滑杆调节，实时生效并自动保存。"
	GameStyle.label(tip, 12, GameStyle.PAPER_DIM)
	vbox.add_child(tip)

	_add_audio_slider_row(vbox, &"Master", "主 音 量", "全局整体音量大小控制")
	_add_audio_slider_row(vbox, &"BGM", "音乐音量", "背景音乐 (BGM)")
	_add_audio_slider_row(vbox, &"SFX", "音效音量", "战斗与击杀音效 (SFX)")
	_add_audio_slider_row(vbox, &"Voice", "语音音量", "选角台词与角色语音 (Voice)")

	GameStyle.scrollable(scroll)
	return scroll

func _add_audio_slider_row(parent: VBoxContainer, bus: StringName, title: String, desc: String) -> void:
	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var r_st := GameStyle.side_card(GameStyle.GOLD, 0.0)
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
	var styles := GameStyle.bar_styles(GameStyle.NAVY2, GameStyle.GOLD)
	slider.add_theme_stylebox_override("slider", styles[0])
	slider.add_theme_stylebox_override("grabber_area", styles[1])
	hbox.add_child(slider)

	var val_lbl := Label.new()
	val_lbl.custom_minimum_size = Vector2(50, 24)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	GameStyle.label(val_lbl, 13, GameStyle.JADE_DK)
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
		# 拖动途中只改内存与总线（persist=false），松手才落盘，避免每 5% 步长同步写文件
		SettingsManager.set_bus_volume(bus, v / 100.0, false)
	)
	slider.drag_ended.connect(func(value_changed: bool):
		if value_changed:
			SettingsManager.set_bus_volume(bus, slider.value / 100.0, true)
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
		GameStyle.button(mute_btn, GameStyle.BAD_DK, GameStyle.BAD, 12, GameStyle.CHALK, 4.0)
	else:
		val_lbl.text = "%d%%" % int(round(vol * 100.0))
		val_lbl.add_theme_color_override("font_color", GameStyle.JADE_DK)
		mute_btn.text = "静音"
		GameStyle.button(mute_btn, GameStyle.NAVY2, GameStyle.GOLD, 12, GameStyle.PAPER_DIM, 4.0, GameStyle.INK_TEXT)

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
	tip.text = "调整战斗反馈与画面效果。可自由开关顿帧、震屏与伤害跳字。"
	GameStyle.label(tip, 12, GameStyle.PAPER_DIM)
	vbox.add_child(tip)

	# 界面主题：五套配色色块直选（即点即换）。排最上 —— 换色是全局观感，翻到这一页第一眼就该看到
	_add_theme_swatch_row(vbox)

	_add_toggle_row(vbox, "damage_numbers", "伤害跳字", "命中与暴击时显示伤害数字，闪避时显示回避标识")
	# 震屏不给「开/关」两态：他想要的是"偶尔来一下"，所以按幅度分四档，人话命名、不暴露系数
	_add_cycle_row(
		vbox,
		"shake_intensity",
		"屏幕震动",
		"只在击杀精英、受击等关键时刻震动；点按切换 关闭 / 轻 / 标准 / 强",
		func() -> String: return "震屏 · %s" % SettingsManager.shake_level_label(),
		func() -> bool: return SettingsManager.shake_mult() > 0.0,
		func(): SettingsManager.set_val(&"display", &"shake_intensity", SettingsManager.shake_level_next())
	)
	_add_toggle_row(vbox, "hit_stop", "顿帧打击感", "命中或击杀强敌时的微顿帧（增强打击感）")
	_add_toggle_row(vbox, "screen_flash", "受击红晕", "受伤及濒死时屏幕边缘的暗红呼吸效果")
	_add_toggle_row(vbox, "show_fps", "实时帧率", "左上角显示当前帧率 (FPS)")
	# 真机闪屏排查用（2026-10-20）：开启后记录 HUD 闪烁时刻的状态到 user://flicker_log.csv
	_add_toggle_row(vbox, "flicker_probe", "闪屏探针", "排查用：记录 HUD 闪烁时刻的状态到 user://flicker_log.csv（默认关）")
	# 画面清晰度：高清（原生高分屏极清渲染）/ 流畅（固定视口拉伸，低配防掉帧）
	_add_cycle_row(
		vbox,
		"render_quality",
		"画面清晰度",
		"高清（原生高分渲染，极致清晰）/ 流畅（固定视口拉伸，低配防掉帧）",
		func() -> String: return "清晰度 · %s" % SettingsManager.render_quality_label(),
		func() -> bool: return SettingsManager.render_quality() == &"high",
		func(): SettingsManager.set_val(&"display", &"render_quality", SettingsManager.render_quality_next())
	)
	# T-6.1 热浪扭曲：可选高档位默认关（back buffer copy 低端机有掉帧风险），排最后不抢眼
	_add_toggle_row(vbox, "heat_distortion", "热浪扭曲", "火锥与火雨区域画面热浪扭曲（高端画质，低配设备可能掉帧，默认关）")
	# T-6.2 受击屏幕冲击波：可选高档位默认关
	_add_toggle_row(vbox, "screen_shockwave", "受击冲击波", "遭受强敌重击时从受击点扩散屏幕径向扭曲环（高端画质，默认关）")
	# 辉光（2026-10-17 真机 GPU 专项）：最大的单项画质税，默认开，低帧自动关。
	# 移动端不碰 HDR 帧缓冲后（2026-10-20）glow pass 本身可安全开启，故文案回到常态描述。
	_add_toggle_row(vbox, "glow", "辉光", "画面亮部起辉光效（暴击绯金、灵光等）。关掉可大幅省电提帧，低帧时会自动关闭")

	GameStyle.scrollable(scroll)
	return scroll

## 通用行外壳：左「标题 + 说明」右控件的金签墨条，开关行与档位行共用同一份摆位
func _add_row_shell(parent: VBoxContainer, title: String, desc: String) -> HBoxContainer:
	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var r_st := GameStyle.side_card(GameStyle.GOLD, 0.0)
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

## 主题色块行：五套预设色块直选，选中态粗黑框 + 硬影（select_snap 位移回弹）。
## 换色本身是全屏 Brutal Snap 硬切；色块的选中框切换给流畅感。
func _add_theme_swatch_row(parent: VBoxContainer) -> void:
	var hbox := _add_row_shell(parent, "界面主题", "主行动、选中与标题带的高亮色；点色块即换，自动保存")
	_theme_slots.clear()

	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 8)
	strip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(strip)

	for preset in GameStyle.THEME_PRESETS:
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(38, 38)
		slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		strip.add_child(slot)
		var id: StringName = preset["id"]
		_theme_slots[id] = slot
		GameStyle.tap(slot, func() -> void: _on_theme_slot_tapped(id))

	_theme_name_lbl = Label.new()
	_theme_name_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	GameStyle.label(_theme_name_lbl, 12, GameStyle.PAPER_DIM)
	hbox.add_child(_theme_name_lbl)

	_update_theme_swatches()

func _update_theme_swatches() -> void:
	# 以「实际生效主题」为准（GameStyle.current_theme），存档值只负责持久化；
	# 两者在正常流程恒等，但以生效值为准可避免任何时刻显示与观感分家。
	var cur := GameStyle.current_theme()
	for preset in GameStyle.THEME_PRESETS:
		var id: StringName = preset["id"]
		var slot: PanelContainer = _theme_slots.get(id, null)
		if slot == null:
			continue
		var main: Color = preset["main"]
		var on := id == cur
		# 选中：3px 纯黑粗框 + 硬影；未选：1px 深灰细框。色块面恒为预设主色（所见即所得）
		var sb := StyleBoxFlat.new()
		sb.bg_color = main
		sb.corner_radius_top_left = 0
		sb.corner_radius_top_right = 0
		sb.corner_radius_bottom_left = 0
		sb.corner_radius_bottom_right = 0
		sb.border_color = GameStyle.INK
		var bw := 3 if on else 1
		sb.border_width_left = bw
		sb.border_width_top = bw
		sb.border_width_right = bw
		sb.border_width_bottom = bw
		if on:
			sb.shadow_color = Color(0, 0, 0, 1)
			sb.shadow_size = 1
			sb.shadow_offset = Vector2(3, 3)
		slot.add_theme_stylebox_override("panel", sb)
	if _theme_name_lbl != null:
		_theme_name_lbl.text = SettingsManager.theme_color_label()

func _on_theme_slot_tapped(id: StringName) -> void:
	if id == SettingsManager.theme_color():
		return
	SettingsManager.set_theme_color(id)
	_update_theme_swatches()

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
		GameStyle.button(btn, GameStyle.JADE, GameStyle.JADE_EDGE, 13, GameStyle.INK_TEXT, 5.0)
	else:
		btn.text = "已关闭  [关]"
		GameStyle.button(btn, GameStyle.NAVY2, GameStyle.GOLD, 13, GameStyle.PAPER_DIM, 5.0, GameStyle.INK_TEXT)

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
		GameStyle.button(btn, GameStyle.JADE, GameStyle.JADE_EDGE, 13, GameStyle.INK_TEXT, 5.0)
	else:
		GameStyle.button(btn, GameStyle.NAVY2, GameStyle.GOLD, 13, GameStyle.PAPER_DIM, 5.0, GameStyle.INK_TEXT)

# ----------------- 分页 3：运指开阖（操作按钮布局） -----------------

## 位置与大小都收进调整模式里现场调（看着按钮调才直观），本页只留入口与兜底

func _build_controls_page() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)

	var tip := Label.new()
	tip.text = "技能键与祭坛键的位置与大小都在调整模式里改：点选按钮后拖动摆放，滑杆只调选中的那颗，全程实时保存。"
	GameStyle.label(tip, 12, GameStyle.PAPER_DIM)
	vbox.add_child(tip)

	_add_action_row(vbox, "按钮位置与大小", "进入调整模式，点选技能键或祭坛键，拖动摆放、滑杆调大小",
		"进入调整模式", _enter_btn_edit_mode, false)
	_add_action_row(vbox, "恢复默认布局", "两个按钮的位置与大小一起回到出厂摆位",
		"恢复默认", func(): SettingsManager.reset_button_layout(), true)

	GameStyle.scrollable(scroll)
	return scroll

## 动作行：右侧一颗按钮执行一件事（进入调整模式 / 恢复默认布局）
func _add_action_row(parent: VBoxContainer, title: String, desc: String,
		btn_text: String, on_press: Callable, danger: bool) -> void:
	var hbox := _add_row_shell(parent, title, desc)

	var btn := Button.new()
	btn.text = btn_text
	btn.custom_minimum_size = Vector2(150, 30)
	btn.focus_mode = Control.FOCUS_NONE
	if danger:
		GameStyle.button(btn, GameStyle.NAVY2, GameStyle.BAD, 13, GameStyle.PAPER, 5.0, GameStyle.CHALK)
	else:
		GameStyle.button(btn, GameStyle.JADE, GameStyle.JADE_EDGE, 13, GameStyle.INK_TEXT, 5.0)
	hbox.add_child(btn)
	btn.pressed.connect(on_press)

## 进入按钮调整模式：藏起设置面板（不发 closed，回来还停在当前页），交给 HUD 覆盖层拖。
## 主菜单入口要顺手把菜单卡片与纯黑幕布收掉——调整背景必须是游戏地图场景，
## 对着首页卡片摆战斗按钮会失去参照（2026-10-15 用户反馈）。
func _enter_btn_edit_mode() -> void:
	var hud := get_parent().get_node_or_null("GameHUD") as GameHUD
	if hud == null:
		return
	DetailTip.close_all(self)
	visible = false
	var menu := get_parent().get_node_or_null("StartMenu") as Control
	var backdrop := get_parent().get_node_or_null("StageBackdrop") as Control
	var from_menu := menu != null and menu.visible
	if from_menu:
		menu.visible = false
		if backdrop != null:
			backdrop.visible = false
	hud.open_btn_edit_overlay(func():
		if from_menu:
			# 回到菜单态：黑幕与菜单卡片按原样亮回来（设置弹窗保持停在本页）
			if backdrop != null:
				backdrop.visible = true
			if menu != null:
				menu.visible = true
		visible = true
	)

# ----------------- 分页 4：演化推衍（系统与拓展） -----------------

func _build_system_page() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 12)
	scroll.add_child(vbox)

	# 1. 游戏版本与更新
	vbox.add_child(_build_version_card())

	# 2. 作者 HQ · 宗门阵地
	vbox.add_child(_build_author_hq_card())

	# 3. 运行环境与诊断
	vbox.add_child(_build_diagnostics_card())

	# 4. 预设与重置
	vbox.add_child(_build_reset_card())

	GameStyle.scrollable(scroll)
	return scroll

func _build_version_card() -> Control:
	var panel := PanelContainer.new()
	var sb := GameStyle.outlined_panel(GameStyle.NAVY2, GameStyle.LINE, 1, 0.0)
	sb.content_margin_left = 14.0
	sb.content_margin_top = 10.0
	sb.content_margin_right = 14.0
	sb.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "◆ 游戏版本与更新"
	GameStyle.label(title, 14, GameStyle.JADE_DK)
	vb.add_child(title)

	var ver_lbl := Label.new()
	ver_lbl.text = "游戏版本：" + Version.APP_NAME + " (" + Version.APP_NAME_EN + ") " + Version.APP_VERSION_NAME + " (Godot 4.7 Forward+)"
	GameStyle.label(ver_lbl, 13, GameStyle.PAPER)
	vb.add_child(ver_lbl)

	var res_lbl := Label.new()
	res_lbl.text = "渲染规格：960×540 基准视口 · 像素平滑过滤 Nearest · 60 FPS"
	GameStyle.label(res_lbl, 12, GameStyle.PAPER_DIM)
	vb.add_child(res_lbl)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	vb.add_child(btn_row)

	_check_update_btn = Button.new()
	_check_update_btn.text = "◆ 检查更新"
	_check_update_btn.custom_minimum_size = Vector2(110, 30)
	_check_update_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(_check_update_btn, GameStyle.JADE, GameStyle.JADE_EDGE, 13, GameStyle.INK_TEXT, 5.0)
	_check_update_btn.pressed.connect(_on_check_update_pressed)
	btn_row.add_child(_check_update_btn)

	var changelog_btn := Button.new()
	changelog_btn.text = "◆ 更新记录"
	changelog_btn.custom_minimum_size = Vector2(110, 30)
	changelog_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(changelog_btn, GameStyle.NAVY2, GameStyle.GOLD, 13, GameStyle.PAPER, 5.0, GameStyle.INK_TEXT)
	changelog_btn.pressed.connect(_open_changelog)
	btn_row.add_child(changelog_btn)

	_update_tip_lbl = Label.new()
	_update_tip_lbl.text = ""
	GameStyle.label(_update_tip_lbl, 12, GameStyle.GOOD_DK)
	btn_row.add_child(_update_tip_lbl)

	return panel

func _build_author_hq_card() -> Control:
	var panel := PanelContainer.new()
	var sb := GameStyle.outlined_panel(GameStyle.NAVY2, GameStyle.LINE, 1, 0.0)
	sb.content_margin_left = 14.0
	sb.content_margin_top = 10.0
	sb.content_margin_right = 14.0
	sb.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "◆ 作者 HQ · 宗门阵地"
	GameStyle.label(title, 14, GameStyle.JADE_DK)
	vb.add_child(title)

	var desc := Label.new()
	desc.text = "独立制作：favo。代码与版本双端开源，欢迎道友交流论道、提交建议与反馈共建！"
	GameStyle.label(desc, 12, GameStyle.PAPER)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(desc)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	vb.add_child(btn_row)

	var gitee_btn := Button.new()
	gitee_btn.text = "◆ Gitee 阵地"
	gitee_btn.custom_minimum_size = Vector2(110, 30)
	gitee_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(gitee_btn, GameStyle.NAVY2, GameStyle.GOLD, 13, GameStyle.PAPER, 5.0, GameStyle.INK_TEXT)
	gitee_btn.pressed.connect(func():
		OS.shell_open("https://gitee.com/%s/%s" % [Version.GITEE_OWNER, Version.GITEE_REPO])
		UpdateManager.show_toast("正在前往 Gitee 宗门阵地...", GameStyle.JADE)
	)
	btn_row.add_child(gitee_btn)

	var gh_btn := Button.new()
	gh_btn.text = "◆ GitHub 阵地"
	gh_btn.custom_minimum_size = Vector2(110, 30)
	gh_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(gh_btn, GameStyle.NAVY2, GameStyle.GOLD, 13, GameStyle.PAPER, 5.0, GameStyle.INK_TEXT)
	gh_btn.pressed.connect(func():
		OS.shell_open("https://github.com/%s/%s" % [Version.GITHUB_OWNER, Version.GITHUB_REPO])
		UpdateManager.show_toast("正在前往 GitHub 宗门阵地...", GameStyle.JADE)
	)
	btn_row.add_child(gh_btn)

	var feedback_btn := Button.new()
	feedback_btn.text = "◆ 建议与反馈"
	feedback_btn.custom_minimum_size = Vector2(110, 30)
	feedback_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(feedback_btn, GameStyle.NAVY2, GameStyle.GOLD, 13, GameStyle.PAPER, 5.0, GameStyle.INK_TEXT)
	feedback_btn.pressed.connect(func():
		OS.shell_open("https://gitee.com/%s/%s/issues" % [Version.GITEE_OWNER, Version.GITEE_REPO])
		UpdateManager.show_toast("正在前往反馈通道，期待道友的高见...", GameStyle.JADE)
	)
	btn_row.add_child(feedback_btn)

	return panel

func _build_diagnostics_card() -> Control:
	var panel := PanelContainer.new()
	var sb := GameStyle.outlined_panel(GameStyle.NAVY2, GameStyle.LINE, 1, 0.0)
	sb.content_margin_left = 14.0
	sb.content_margin_top = 10.0
	sb.content_margin_right = 14.0
	sb.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "◆ 运行环境与诊断"
	GameStyle.label(title, 14, GameStyle.JADE_DK)
	vb.add_child(title)

	var arch := Engine.get_architecture_name()
	var env_lbl := Label.new()
	env_lbl.text = "平台环境：%s (%s) · 架构：%s · 引擎：%s" % [
		OS.get_name(),
		OS.get_version(),
		arch,
		Engine.get_version_info().get("string", "Godot 4.7")
	]
	GameStyle.label(env_lbl, 12, GameStyle.PAPER_DIM)
	env_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(env_lbl)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	vb.add_child(btn_row)

	var copy_btn := Button.new()
	copy_btn.text = "◆ 复制运行诊断信息"
	copy_btn.custom_minimum_size = Vector2(160, 30)
	copy_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(copy_btn, GameStyle.NAVY2, GameStyle.GOLD, 13, GameStyle.PAPER, 5.0, GameStyle.INK_TEXT)
	copy_btn.pressed.connect(_copy_diagnostics_info)
	btn_row.add_child(copy_btn)

	# 闪屏日志一键复制（2026-10-20）：真机上找 user:// 路径很麻烦，直接读文件内容塞剪贴板。
	# 只在探针开过、文件存在时有效；内容过长时只复制尾部（最近的记录最有用）。
	var flicker_btn := Button.new()
	flicker_btn.text = "◆ 复制闪屏日志"
	flicker_btn.custom_minimum_size = Vector2(160, 30)
	flicker_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(flicker_btn, GameStyle.NAVY2, GameStyle.GOLD, 13, GameStyle.PAPER, 5.0, GameStyle.INK_TEXT)
	flicker_btn.pressed.connect(_copy_flicker_log)
	btn_row.add_child(flicker_btn)

	return panel

## 复制闪屏探针日志到剪贴板（见 FlickerProbe）。文件不存在时明确提示「没采集到」，
## 而不是静默失败 —— 用户分不清「没闪」和「探针没跑」是这类排查最大的坑。
func _copy_flicker_log() -> void:
	var path := FlickerProbe.log_path()
	if not FileAccess.file_exists(path):
		UpdateManager.show_toast("◆ 还没有闪屏日志：请先在「画面」页开启闪屏探针 ◆", GameStyle.BAD)
		return
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		UpdateManager.show_toast("◆ 闪屏日志为空 ◆", GameStyle.BAD)
		return
	# 太长时只保留尾部（最近记录最能说明问题），并加一行说明
	const MAX_CHARS := 30000
	if text.length() > MAX_CHARS:
		text = "…（前段省略，仅保留最近记录）…\n" + text.substr(text.length() - MAX_CHARS)
	if DisplayServer.has_method("clipboard_set"):
		DisplayServer.clipboard_set(text)
	UpdateManager.show_toast("◆ 闪屏日志已复制到剪贴板（%d 字符）◆" % text.length(), GameStyle.GOOD)

func _build_reset_card() -> Control:
	var panel := PanelContainer.new()
	var sb := GameStyle.outlined_panel(GameStyle.NAVY2, GameStyle.LINE, 1, 0.0)
	sb.content_margin_left = 14.0
	sb.content_margin_top = 10.0
	sb.content_margin_right = 14.0
	sb.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "◆ 预设与重置"
	GameStyle.label(title, 14, GameStyle.JADE_DK)
	vb.add_child(title)

	var desc := Label.new()
	desc.text = "将音效音量、战斗视觉特效、震屏档位等全部设置恢复至出厂预设推荐值。"
	GameStyle.label(desc, 12, GameStyle.PAPER_DIM)
	vb.add_child(desc)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	vb.add_child(btn_row)

	var reset_btn := Button.new()
	reset_btn.text = "恢 复 默 认 设 置"
	reset_btn.custom_minimum_size = Vector2(150, 32)
	reset_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(reset_btn, GameStyle.NAVY2, GameStyle.BAD, 13, GameStyle.PAPER, 5.0, GameStyle.CHALK)
	reset_btn.pressed.connect(_on_reset_pressed)
	btn_row.add_child(reset_btn)

	_reset_tip_lbl = Label.new()
	_reset_tip_lbl.text = ""
	GameStyle.label(_reset_tip_lbl, 13, GameStyle.GOOD_DK)
	btn_row.add_child(_reset_tip_lbl)

	return panel

func _on_check_update_pressed() -> void:
	if UpdateManager.is_checking:
		return
	if is_instance_valid(_check_update_btn):
		_check_update_btn.disabled = true
		_check_update_btn.text = "检测中..."
	if is_instance_valid(_update_tip_lbl):
		_update_tip_lbl.text = "正在连接远端版本节点..."
		_update_tip_lbl.add_theme_color_override("font_color", GameStyle.GOLD)
	UpdateManager.check_for_update(true)

func _on_update_check_done(tip: String, color: Color) -> void:
	if is_instance_valid(_check_update_btn):
		_check_update_btn.disabled = false
		_check_update_btn.text = "◆ 检查更新"
	if is_instance_valid(_update_tip_lbl):
		_update_tip_lbl.text = tip
		_update_tip_lbl.add_theme_color_override("font_color", color)
		var tw := create_tween()
		tw.tween_interval(3.5)
		tw.tween_callback(func():
			if is_instance_valid(_update_tip_lbl):
				_update_tip_lbl.text = ""
		)

func _open_changelog() -> void:
	if _changelog_dialog == null or not is_instance_valid(_changelog_dialog):
		_changelog_dialog = ChangelogDialog.new()
		var p := get_parent()
		if p != null:
			p.add_child(_changelog_dialog)
		else:
			add_child(_changelog_dialog)
	_changelog_dialog.open()

func _copy_diagnostics_info() -> void:
	var info := "【剑士 (Swordsman) 运行诊断信息】\n"
	info += "游戏版本: %s (%s)\n" % [Version.APP_VERSION_NAME, Version.APP_NAME_EN]
	info += "运行平台: %s (%s)\n" % [OS.get_name(), OS.get_version()]
	info += "架构规格: %s\n" % Engine.get_architecture_name()
	info += "引擎版本: %s\n" % Engine.get_version_info().get("string", "Godot 4.7")
	info += "渲染基准: 960x540 (Nearest, 60 FPS)"

	if DisplayServer.has_method("clipboard_set"):
		DisplayServer.clipboard_set(info)
	UpdateManager.show_toast("◆ 运行诊断信息已复制到剪贴板 ◆", GameStyle.GOOD)

func _open_tutorial() -> void:
	var tut := get_parent().get_node_or_null("TutorialDialog")
	if tut != null:
		tut.open()

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

## 主题色变更：刷新本页色块选中框与主题名（本弹窗自身的金签行卡由 GameStyle 注册表自动换色）
func _on_theme_color_changed(_preset: StringName) -> void:
	_update_theme_swatches()

func _refresh_all_ui() -> void:
	# Voice 总线仍在引擎里，但这一页没有它的滑杆（开局台词已撤），故不刷该行
	for bus in [&"Master", &"BGM", &"SFX"]:
		_update_audio_row_ui(bus)
	for k in _toggle_controls.keys():
		_update_toggle_btn_ui(k)
	for k in _cycle_controls.keys():
		_update_cycle_btn_ui(k)
	_update_theme_swatches()
