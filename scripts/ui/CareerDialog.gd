class_name CareerDialog
extends Control

## 修仙志（生涯功绩簿）：查看天道功绩达成情况、解锁奖励、生涯累计统计与最近战报
## 采用全屏暂停式弹窗，双页签切换（天道功绩 / 历战名录），严格遵循 GameStyle 设计规范

signal closed

var _closing: bool = false
var _current_tab: int = 0
var _tab_buttons: Array[Button] = []
var _pages: Array[Control] = []

# 顶部概览数据标签
var _runs_val_lbl: Label
var _wins_val_lbl: Label
var _kills_val_lbl: Label
var _wave_val_lbl: Label

# 列表容器
var _ach_list_box: VBoxContainer
var _history_list_box: VBoxContainer

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()

func _build_ui() -> void:
	# 1. 半透明暗色背景遮罩（支持点击空白处关闭）
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.09, 0.85)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			close()
	)
	add_child(dim)

	# 2. 居中大容器
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	# 3. 斜切大面板（880 x 470）
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(880, 470)
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
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	margin.add_child(root_vbox)

	# 4. 顶部标题栏 + Tab 切换 + 关闭按钮
	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 12)
	root_vbox.add_child(top_bar)

	var title_box := PanelContainer.new()
	title_box.add_theme_stylebox_override("panel", GameStyle.block(GameStyle.BLUE, GameStyle.SLANT_BAND, Vector2(3, 4)))
	var title_margin := MarginContainer.new()
	title_margin.add_theme_constant_override("margin_left", 14)
	title_margin.add_theme_constant_override("margin_right", 14)
	title_margin.add_theme_constant_override("margin_top", 4)
	title_margin.add_theme_constant_override("margin_bottom", 4)
	var title_lbl := Label.new()
	title_lbl.text = "修 仙 志  ·  天 道 功 绩 簿"
	GameStyle.label(title_lbl, 18, GameStyle.PAPER, 0, GameStyle.INK, true)
	title_margin.add_child(title_lbl)
	title_box.add_child(title_margin)
	top_bar.add_child(title_box)

	var tab_bar := HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 8)
	tab_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(tab_bar)

	_add_tab_button(tab_bar, 0, "✦ 天道功绩")
	_add_tab_button(tab_bar, 1, "✦ 历战名录")

	var close_btn := Button.new()
	close_btn.text = "返 回"
	close_btn.custom_minimum_size = Vector2(84, 34)
	close_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(close_btn, GameStyle.NAVY2, GameStyle.BLUE, 14, GameStyle.PAPER, 5.0)
	close_btn.pressed.connect(close)
	top_bar.add_child(close_btn)

	# 5. 生涯核心数据横条（4 个指标卡）
	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 10)
	root_vbox.add_child(stats_row)

	_runs_val_lbl = _add_summary_card(stats_row, "修行局数", "0 局")
	_wins_val_lbl = _add_summary_card(stats_row, "渡劫成功", "0 胜")
	_kills_val_lbl = _add_summary_card(stats_row, "累计斩妖", "0 只")
	_wave_val_lbl = _add_summary_card(stats_row, "最高抵御", "第 0 波")

	# 6. 内容分页面板
	var content_panel := PanelContainer.new()
	content_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var cont_sb := GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 2, 0.0)
	cont_sb.content_margin_left = 14.0
	cont_sb.content_margin_top = 10.0
	cont_sb.content_margin_right = 14.0
	cont_sb.content_margin_bottom = 10.0
	content_panel.add_theme_stylebox_override("panel", cont_sb)
	root_vbox.add_child(content_panel)

	_pages.append(_build_achievements_page(content_panel))
	_pages.append(_build_history_page(content_panel))

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

func _add_summary_card(parent: HBoxContainer, title: String, init_val: String) -> Label:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := GameStyle.block(GameStyle.NAVY2, GameStyle.SLANT_PLATE, Vector2(2, 3))
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	card.add_theme_stylebox_override("panel", sb)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	card.add_child(hbox)

	var t_lbl := Label.new()
	t_lbl.text = title
	GameStyle.label(t_lbl, 12, GameStyle.GREY)
	hbox.add_child(t_lbl)

	var v_lbl := Label.new()
	v_lbl.text = init_val
	v_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	GameStyle.label(v_lbl, 14, GameStyle.YELLOW)
	hbox.add_child(v_lbl)

	parent.add_child(card)
	return v_lbl

# ----------------- 分页 1：天道功绩列表 -----------------

func _build_achievements_page(parent: Control) -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)

	_ach_list_box = VBoxContainer.new()
	_ach_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ach_list_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_ach_list_box)
	return scroll

# ----------------- 分页 2：历战名录列表 -----------------

func _build_history_page(parent: Control) -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)

	_history_list_box = VBoxContainer.new()
	_history_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_history_list_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_history_list_box)
	return scroll

## 打开修仙志弹窗并刷新最新数据
func open() -> void:
	visible = true
	_closing = false
	_refresh_data()
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.2)

func close() -> void:
	if _closing:
		return
	_closing = true
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.16)
	tw.tween_callback(func():
		visible = false
		_closing = false
		closed.emit()
	)

func _refresh_data() -> void:
	# 1. 刷新顶部生涯概览
	var cs := GameManager.career_stats
	var runs := int(cs.get("total_runs", 0))
	var wins := int(cs.get("total_wins", 0))
	var kills := int(cs.get("total_kills", 0))
	var b_wave := int(cs.get("best_wave", 0))
	var win_rate := (float(wins) / float(runs) * 100.0) if runs > 0 else 0.0

	_runs_val_lbl.text = "%d 局" % runs
	_wins_val_lbl.text = "%d 胜 (%.0f%%)" % [wins, win_rate]
	_kills_val_lbl.text = "%d 只" % kills
	_wave_val_lbl.text = "第 %d 波" % b_wave

	# 2. 刷新成就列表
	for c in _ach_list_box.get_children():
		c.queue_free()
	for a in AchievementData.ACHIEVEMENTS:
		_ach_list_box.add_child(_create_achievement_row(a))

	# 3. 刷新战报列表
	for c in _history_list_box.get_children():
		c.queue_free()
	if GameManager.run_history.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "暂无历战战报 · 前往斩妖修道即可沉淀战果"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		GameStyle.label(empty_lbl, 13, GameStyle.GREY)
		_history_list_box.add_child(empty_lbl)
	else:
		for entry in GameManager.run_history:
			_history_list_box.add_child(_create_history_row(entry))

func _create_achievement_row(adef: Dictionary) -> Control:
	var aid := String(adef.get("id", ""))
	var is_done: bool = GameManager.is_achievement_unlocked(aid)
	var row := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = GameStyle.NAVY if is_done else GameStyle.INK.lightened(0.02)
	style.skew = Vector2(deg_to_rad(2.0), 0)
	style.border_width_left = 2
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 3
	style.border_color = GameStyle.YELLOW if is_done else GameStyle.LINE
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	row.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	row.add_child(hbox)

	# 图标
	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(36, 36)
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_box.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 1, 0.0))
	var icon_tex := TextureRect.new()
	if ResourceLoader.exists(String(adef.get("icon", ""))):
		icon_tex.texture = load(String(adef["icon"]))
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.custom_minimum_size = Vector2(30, 30)
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if not is_done:
		icon_tex.modulate = Color(0.4, 0.4, 0.5, 0.7)
	icon_box.add_child(icon_tex)
	hbox.add_child(icon_box)

	# 成就名与条件
	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 2)
	hbox.add_child(text_col)

	var name_lbl := Label.new()
	name_lbl.text = String(adef.get("name", "未名功绩"))
	GameStyle.label(name_lbl, 14, GameStyle.PAPER if is_done else GameStyle.PAPER_DIM, 0, GameStyle.INK, true)
	text_col.add_child(name_lbl)

	var cond_lbl := Label.new()
	cond_lbl.text = String(adef.get("cond_desc", ""))
	GameStyle.label(cond_lbl, 11, GameStyle.YELLOW if is_done else GameStyle.GREY)
	text_col.add_child(cond_lbl)

	# 奖励说明
	var rtype := String(adef.get("reward_type", ""))
	var rprefix := "解锁道统：" if rtype == "cultivator" else "入阁法宝："
	var rname := String(adef.get("reward_name", ""))
	var reward_lbl := Label.new()
	reward_lbl.text = "%s%s" % [rprefix, rname]
	reward_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	reward_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.NAVY2))
	GameStyle.label(reward_lbl, 11, GameStyle.PAPER_DIM)
	hbox.add_child(reward_lbl)

	# 状态色签
	var status_lbl := Label.new()
	status_lbl.text = " 已达成 " if is_done else " 未达成 "
	status_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.GOOD_DK if is_done else GameStyle.LINE))
	GameStyle.label(status_lbl, 12, GameStyle.GOOD if is_done else GameStyle.GREY)
	hbox.add_child(status_lbl)

	return row

func _create_history_row(entry: Dictionary) -> Control:
	var row := PanelContainer.new()
	var is_vic := bool(entry.get("victory", false))
	var style := StyleBoxFlat.new()
	style.bg_color = GameStyle.NAVY
	style.border_width_left = 2
	style.border_width_bottom = 2
	style.border_color = GameStyle.BLUE if is_vic else GameStyle.BAD
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	row.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	row.add_child(hbox)

	var cid := String(entry.get("cultivator_id", "jianchi"))
	var cdef := CultivatorData.get_def(cid)
	var cname := String(cdef.get("name", "修士"))
	var dname := AchievementData.danger_name(int(entry.get("danger", 0)))

	var c_lbl := Label.new()
	c_lbl.text = "%s「%s」" % [cname, dname]
	GameStyle.label(c_lbl, 13, GameStyle.PAPER, 0, GameStyle.INK, true)
	hbox.add_child(c_lbl)

	var wave := int(entry.get("wave", 1))
	var kills := int(entry.get("kills", 0))
	var lvl := int(entry.get("level", 1))
	var dur := float(entry.get("time", 0.0))
	var mins := int(dur / 60.0)
	var secs := int(dur) % 60

	var detail_lbl := Label.new()
	detail_lbl.text = "抵达第 %d 波 · 斩妖 %d 只 · 境界 Lv.%d · 耗时 %02d:%02d" % [wave, kills, lvl, mins, secs]
	detail_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	GameStyle.label(detail_lbl, 12, GameStyle.PAPER_DIM)
	hbox.add_child(detail_lbl)

	var v_tag := Label.new()
	v_tag.text = " 渡劫成功 " if is_vic else " 道消身殒 "
	v_tag.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.BLUE if is_vic else GameStyle.BAD_DK))
	GameStyle.label(v_tag, 11, GameStyle.PAPER if is_vic else GameStyle.BAD)
	hbox.add_child(v_tag)

	return row

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
