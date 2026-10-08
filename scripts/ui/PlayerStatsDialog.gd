class_name PlayerStatsDialog
extends Control

## 人物属性详情面板：可在战斗中查看基础属性、战斗加成、持用法器、历史悟道加点
## 采用全屏暂停式弹窗，支持右上角返回、点击半透明遮罩背景或按 ESC 关闭

var _closing: bool = false

# UI 节点引用
var _dim_rect: ColorRect
var _panel: PanelContainer
var _title_label: Label
var _meta_label: Label
var _close_btn: Button

# 左侧属性节点
var _hp_bar: ProgressBar
var _hp_val_lbl: Label
var _regen_val_lbl: Label
var _armor_val_lbl: Label
var _atk_val_lbl: Label
var _haste_val_lbl: Label
var _speed_val_lbl: Label
var _pickup_val_lbl: Label
var _range_val_lbl: Label
var _crit_val_lbl: Label
var _dodge_val_lbl: Label
var _lifesteal_val_lbl: Label
var _luck_val_lbl: Label
var _harvest_val_lbl: Label
var _kills_val_lbl: Label
var _stones_val_lbl: Label

# 右侧法器与历史节点
var _weapons_box: HBoxContainer
var _stash_box: HBoxContainer
var _stash_section: VBoxContainer
var _history_count_lbl: Label
var _history_list: VBoxContainer

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()

func _build_ui() -> void:
	# 1. 半透明暗色背景（阻挡并支持点击关闭）
	_dim_rect = ColorRect.new()
	_dim_rect.color = Color(0.02, 0.04, 0.09, 0.82)
	_dim_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim_rect.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			close()
	)
	add_child(_dim_rect)

	# 2. 居中大容器
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	# 3. 仿 dudu-cocos 仙侠大面板
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(880, 560)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(GameStyle.NAVY.r, GameStyle.NAVY.g, GameStyle.NAVY.b, 0.985)
	panel_style.skew = Vector2(deg_to_rad(2.5), 0.0)
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 6
	panel_style.border_color = GameStyle.BLUE
	panel_style.shadow_color = Color(0, 0, 0, 0.65)
	panel_style.shadow_size = 0
	panel_style.shadow_offset = Vector2(8, 8)
	_panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	_panel.add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 12)
	margin.add_child(root_vbox)

	# 4. 顶部标题栏
	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 12)

	var title_box := PanelContainer.new()
	title_box.add_theme_stylebox_override("panel", GameStyle.block(GameStyle.BLUE, GameStyle.SLANT_BAND, Vector2(3, 4)))
	var title_margin := MarginContainer.new()
	title_margin.add_theme_constant_override("margin_left", 14)
	title_margin.add_theme_constant_override("margin_right", 14)
	title_margin.add_theme_constant_override("margin_top", 4)
	title_margin.add_theme_constant_override("margin_bottom", 4)
	_title_label = Label.new()
	_title_label.text = "修 为 境 界  ·  人 物 属 性"
	GameStyle.label(_title_label, 19, GameStyle.PAPER, 0, GameStyle.INK, true)
	title_margin.add_child(_title_label)
	title_box.add_child(title_margin)
	top_bar.add_child(title_box)

	_meta_label = Label.new()
	GameStyle.label(_meta_label, 14, GameStyle.YELLOW)
	_meta_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_meta_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_bar.add_child(_meta_label)

	_close_btn = Button.new()
	_close_btn.text = "返 回 战 斗"
	_close_btn.custom_minimum_size = Vector2(100, 34)
	_close_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(_close_btn, GameStyle.NAVY2, GameStyle.BLUE, 14, GameStyle.PAPER, 5.0)
	_close_btn.pressed.connect(close)
	top_bar.add_child(_close_btn)

	root_vbox.add_child(top_bar)

	# 5. 主体内容：左右分栏
	var body_hbox := HBoxContainer.new()
	body_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_hbox.add_theme_constant_override("separation", 16)
	root_vbox.add_child(body_hbox)

	# 左侧栏：人物气血与战斗属性
	var left_panel := _build_left_stats_panel()
	body_hbox.add_child(left_panel)

	# 右侧栏：法器槽与历史悟道
	var right_panel := _build_right_equipment_and_history_panel()
	body_hbox.add_child(right_panel)

func _build_left_stats_panel() -> Control:
	var left_panel := PanelContainer.new()
	left_panel.custom_minimum_size = Vector2(340, 0)
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb := GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 2, 0.0)
	sb.content_margin_left = 14.0
	sb.content_margin_top = 12.0
	sb.content_margin_right = 14.0
	sb.content_margin_bottom = 12.0
	left_panel.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	left_panel.add_child(vbox)

	var sec_title := Label.new()
	sec_title.text = "✦ 气血与道法根基"
	GameStyle.label(sec_title, 15, GameStyle.YELLOW)
	vbox.add_child(sec_title)

	# 气血条
	var hp_box := HBoxContainer.new()
	hp_box.add_theme_constant_override("separation", 8)
	var hp_title := Label.new()
	hp_title.text = "气血值"
	GameStyle.label(hp_title, 13, GameStyle.PAPER_DIM)
	hp_box.add_child(hp_title)

	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size = Vector2(130, 14)
	_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hp_bar.show_percentage = false
	var bar_st = GameStyle.bar_styles(Color(0.04, 0.06, 0.1, 0.85), Color(0.95, 0.94, 0.89))
	_hp_bar.add_theme_stylebox_override("background", bar_st[0])
	_hp_bar.add_theme_stylebox_override("fill", bar_st[1])
	hp_box.add_child(_hp_bar)

	_hp_val_lbl = Label.new()
	GameStyle.label(_hp_val_lbl, 13, GameStyle.PAPER)
	hp_box.add_child(_hp_val_lbl)
	vbox.add_child(hp_box)

	var sep1 := HSeparator.new()
	sep1.add_theme_stylebox_override("separator", _create_line_style(GameStyle.LINE))
	vbox.add_child(sep1)

	# 各项属性行
	_regen_val_lbl = _add_stat_row(vbox, "气血回复", "+0.0 / 秒")
	_armor_val_lbl = _add_stat_row(vbox, "护甲罡气", "0 点 (减伤 0.0%)")
	_dodge_val_lbl = _add_stat_row(vbox, "流云身法", "0% 闪避")
	_lifesteal_val_lbl = _add_stat_row(vbox, "噬元诀", "0% 概率")
	_atk_val_lbl = _add_stat_row(vbox, "剑意法伤", "100% (+0%)")
	_haste_val_lbl = _add_stat_row(vbox, "掐诀神速", "0% 冷却缩减")
	_speed_val_lbl = _add_stat_row(vbox, "神行移速", "210 (+0%)")
	_pickup_val_lbl = _add_stat_row(vbox, "摄灵范围", "96 (+0%)")
	_range_val_lbl = _add_stat_row(vbox, "神识范围", "+0%")
	_crit_val_lbl = _add_stat_row(vbox, "天命暴击", "5.0% 概率 (1.5× 伤害)")
	_luck_val_lbl = _add_stat_row(vbox, "福缘", "0")
	_harvest_val_lbl = _add_stat_row(vbox, "灵韵", "0 (波末 +0)")

	var sep2 := HSeparator.new()
	sep2.add_theme_stylebox_override("separator", _create_line_style(GameStyle.LINE))
	vbox.add_child(sep2)

	_kills_val_lbl = _add_stat_row(vbox, "累计诛妖", "0 妖")
	_stones_val_lbl = _add_stat_row(vbox, "随身灵石", "0 颗")

	return left_panel

func _add_stat_row(parent: Container, label_text: String, default_val: String) -> Label:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)

	var l_name := Label.new()
	l_name.text = label_text
	GameStyle.label(l_name, 13, GameStyle.PAPER_DIM)
	hbox.add_child(l_name)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(spacer)

	var l_val := Label.new()
	l_val.text = default_val
	GameStyle.label(l_val, 13, GameStyle.PAPER)
	hbox.add_child(l_val)

	parent.add_child(hbox)
	return l_val

func _build_right_equipment_and_history_panel() -> Control:
	var right_vbox := VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_theme_constant_override("separation", 10)

	# 1. 本命与上阵法器区块
	var wp_panel := PanelContainer.new()
	var wp_st := GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 2, 0.0)
	wp_st.content_margin_left = 14.0
	wp_st.content_margin_top = 10.0
	wp_st.content_margin_right = 14.0
	wp_st.content_margin_bottom = 10.0
	wp_panel.add_theme_stylebox_override("panel", wp_st)

	var wp_vbox := VBoxContainer.new()
	wp_vbox.add_theme_constant_override("separation", 8)
	wp_panel.add_child(wp_vbox)

	var wp_head := HBoxContainer.new()
	var wp_title := Label.new()
	wp_title.text = "✦ 上阵法器与灵宝"
	GameStyle.label(wp_title, 14, GameStyle.YELLOW)
	wp_head.add_child(wp_title)
	wp_vbox.add_child(wp_head)

	_weapons_box = HBoxContainer.new()
	_weapons_box.add_theme_constant_override("separation", 10)
	wp_vbox.add_child(_weapons_box)

	# 背包区域（如有法器）
	_stash_section = VBoxContainer.new()
	_stash_section.add_theme_constant_override("separation", 4)
	var stash_title := Label.new()
	stash_title.text = "备用法器（纳戒仓库）："
	GameStyle.label(stash_title, 12, GameStyle.GREY)
	_stash_section.add_child(stash_title)
	_stash_box = HBoxContainer.new()
	_stash_box.add_theme_constant_override("separation", 8)
	_stash_section.add_child(_stash_box)
	wp_vbox.add_child(_stash_section)

	right_vbox.add_child(wp_panel)

	# 2. 历史加点流水区块（带滚动容器）
	var hist_panel := PanelContainer.new()
	hist_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var hist_st := GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 2, 0.0)
	hist_st.content_margin_left = 14.0
	hist_st.content_margin_top = 10.0
	hist_st.content_margin_right = 14.0
	hist_st.content_margin_bottom = 10.0
	hist_panel.add_theme_stylebox_override("panel", hist_st)

	var hist_vbox := VBoxContainer.new()
	hist_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hist_vbox.add_theme_constant_override("separation", 8)
	hist_panel.add_child(hist_vbox)

	var hist_header := HBoxContainer.new()
	var hist_title := Label.new()
	hist_title.text = "✦ 悟道历程（历史加点明细）"
	GameStyle.label(hist_title, 14, GameStyle.YELLOW)
	hist_header.add_child(hist_title)

	var h_spacer := Control.new()
	h_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hist_header.add_child(h_spacer)

	_history_count_lbl = Label.new()
	_history_count_lbl.text = "已领悟 0 项"
	GameStyle.label(_history_count_lbl, 13, GameStyle.PAPER_DIM)
	hist_header.add_child(_history_count_lbl)
	hist_vbox.add_child(hist_header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	hist_vbox.add_child(scroll)

	_history_list = VBoxContainer.new()
	_history_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_history_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_history_list)

	right_vbox.add_child(hist_panel)

	return right_vbox

func _create_line_style(color: Color) -> StyleBoxLine:
	var s := StyleBoxLine.new()
	s.color = color
	s.thickness = 1
	return s

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func open() -> void:
	if visible or GameManager.is_game_over:
		return
	_closing = false
	refresh()
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
		get_tree().paused = false
		_closing = false
	)

func refresh() -> void:
	var stats := GameManager.get_stat_breakdown()
	var mins := int(GameManager.game_time / 60.0)
	var secs := int(GameManager.game_time) % 60
	_meta_label.text = "境界：Lv.%d   |   波次：第 %d 波   |   存活：%02d:%02d" % [
		GameManager.level,
		maxi(GameManager.wave_number, 1),
		mins, secs
	]

	# 1. 左侧属性刷新
	_hp_bar.max_value = stats["max_hp"]
	_hp_bar.value = stats["current_hp"]
	_hp_val_lbl.text = "%d / %d" % [int(stats["current_hp"]), int(stats["max_hp"])]

	_regen_val_lbl.text = "+%.1f / 秒" % float(stats["hp_regen"])
	_regen_val_lbl.add_theme_color_override("font_color", GameStyle.GOOD if stats["hp_regen"] > 0.0 else GameStyle.PAPER)

	var arm: float = stats["armor"]
	_armor_val_lbl.text = "%.0f 点 (减伤 %.1f%%)" % [arm, stats["dmg_reduction_pct"]]
	_armor_val_lbl.add_theme_color_override("font_color", GameStyle.GOOD if arm > 0.0 else GameStyle.PAPER)

	var dmg_bonus: float = stats["damage_bonus_pct"]
	_atk_val_lbl.text = "%d%% (%s%.0f%%)" % [int(stats["damage_mult"] * 100.0), "+" if dmg_bonus >= 0 else "", dmg_bonus]
	_atk_val_lbl.add_theme_color_override("font_color", GameStyle.YELLOW if dmg_bonus > 0.0 else GameStyle.PAPER)

	var cdr: float = stats["cdr_pct"]
	_haste_val_lbl.text = "%.1f%% 冷却缩减" % cdr
	_haste_val_lbl.add_theme_color_override("font_color", GameStyle.BLUE if cdr > 0.0 else GameStyle.PAPER)

	var spd_bonus: float = stats["move_speed_bonus_pct"]
	_speed_val_lbl.text = "%.0f (%s%.0f%%)" % [stats["move_speed"], "+" if spd_bonus >= 0 else "", spd_bonus]
	_speed_val_lbl.add_theme_color_override("font_color", GameStyle.GOOD if spd_bonus > 0.0 else GameStyle.PAPER)

	var pk_bonus: float = stats["pickup_bonus_pct"]
	_pickup_val_lbl.text = "%.0f 像素 (%s%.0f%%)" % [stats["pickup_radius"], "+" if pk_bonus >= 0 else "", pk_bonus]
	_pickup_val_lbl.add_theme_color_override("font_color", GameStyle.BLUE if pk_bonus > 0.0 else GameStyle.PAPER)

	_crit_val_lbl.text = "%.0f%% 概率 (%.1f× 伤害)" % [stats["crit_rate_pct"], stats["crit_dmg_pct"] / 100.0]
	_crit_val_lbl.add_theme_color_override("font_color", GameStyle.YELLOW if stats["crit_rate_pct"] > 5.0 else GameStyle.PAPER)

	var dodge_pct: float = stats["dodge_pct"]
	_dodge_val_lbl.text = "%.0f%% 闪避" % dodge_pct
	_dodge_val_lbl.add_theme_color_override("font_color", GameStyle.BLUE if dodge_pct > 0.0 else GameStyle.PAPER)

	var ls_pct: float = stats["lifesteal_pct"]
	_lifesteal_val_lbl.text = "%.0f%% 概率 (每秒至多 %d 次)" % [ls_pct, GameManager.LIFESTEAL_MAX_PER_SEC]
	_lifesteal_val_lbl.add_theme_color_override("font_color", GameStyle.GOOD if ls_pct > 0.0 else GameStyle.PAPER)

	var rng_bonus: float = stats["attack_range_pct"]
	_range_val_lbl.text = "%s%.0f%%" % ["+" if rng_bonus >= 0 else "", rng_bonus]
	_range_val_lbl.add_theme_color_override("font_color", GameStyle.BLUE if rng_bonus > 0.0 else GameStyle.PAPER)

	var luck_v: float = stats["luck"]
	_luck_val_lbl.text = "%.0f" % luck_v
	_luck_val_lbl.add_theme_color_override("font_color", GameStyle.YELLOW if luck_v > 0.0 else GameStyle.PAPER)

	var harvest_v: float = stats["harvest"]
	_harvest_val_lbl.text = "%.0f (波末 +%d)" % [harvest_v, int(round(harvest_v))]
	_harvest_val_lbl.add_theme_color_override("font_color", GameStyle.YELLOW if harvest_v > 0.0 else GameStyle.PAPER)

	_kills_val_lbl.text = "%d 妖" % GameManager.kills
	_stones_val_lbl.text = "%d 颗" % GameManager.spirit_stones

	# 2. 右侧法器刷新
	_refresh_weapons()

	# 3. 历史加点流水刷新
	_refresh_history()

func _refresh_weapons() -> void:
	for child in _weapons_box.get_children():
		child.queue_free()
	for child in _stash_box.get_children():
		child.queue_free()

	var summary := GameManager.get_weapons_summary()
	for i in range(WeaponData.MAX_SLOTS):
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(44, 44)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var filled := i < summary.size()
		var border_col: Color = GameStyle.BLUE if filled else GameStyle.LINE
		var bg_col: Color = GameStyle.NAVY if filled else Color(GameStyle.INK.r, GameStyle.INK.g, GameStyle.INK.b, 0.45)
		slot.add_theme_stylebox_override("panel", GameStyle.outlined_panel(bg_col, border_col, 2, 0.0))

		if filled:
			var w: Dictionary = summary[i]
			var tex_rect := TextureRect.new()
			if w.has("icon") and ResourceLoader.exists(w["icon"]):
				tex_rect.texture = load(w["icon"])
			tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex_rect.custom_minimum_size = Vector2(34, 34)
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(tex_rect)

			var star_lbl := Label.new()
			star_lbl.text = "★%d" % int(w.get("star", 1))
			star_lbl.add_theme_font_override("font", GameStyle.body_font())
			star_lbl.add_theme_font_size_override("font_size", 11)
			star_lbl.add_theme_color_override("font_color", GameStyle.YELLOW)
			star_lbl.add_theme_color_override("font_outline_color", GameStyle.INK)
			star_lbl.add_theme_constant_override("outline_size", 3)
			star_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			star_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			star_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			star_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
			star_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(star_lbl)

			var tag_name: String = w.get("name", "")
			slot.tooltip_text = "%s (%d阶)" % [tag_name, int(w.get("star", 1))]
		else:
			var empty_dot := Label.new()
			empty_dot.text = "·"
			empty_dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty_dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			GameStyle.label(empty_dot, 16, GameStyle.GREY)
			slot.add_child(empty_dot)

		_weapons_box.add_child(slot)

	# 仓库法器
	var has_stash: bool = not GameManager.stash.is_empty()
	_stash_section.visible = has_stash
	if has_stash:
		for i in range(GameManager.stash.size()):
			var item: Dictionary = GameManager.stash[i]
			var def: Dictionary = WeaponData.get_def(item.get("id", ""))
			var s_slot := PanelContainer.new()
			s_slot.custom_minimum_size = Vector2(36, 36)
			s_slot.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.NAVY2, GameStyle.LINE, 1, 0.0))

			var s_icon_path: String = item.get("icon", def.get("icon", ""))
			var s_tex := TextureRect.new()
			if not s_icon_path.is_empty() and ResourceLoader.exists(s_icon_path):
				s_tex.texture = load(s_icon_path)
			s_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			s_tex.custom_minimum_size = Vector2(26, 26)
			s_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			s_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			s_slot.add_child(s_tex)

			var s_star := int(item.get("star", 1))
			var s_star_lbl := Label.new()
			s_star_lbl.text = "★%d" % s_star
			s_star_lbl.add_theme_font_override("font", GameStyle.body_font())
			s_star_lbl.add_theme_font_size_override("font_size", 10)
			s_star_lbl.add_theme_color_override("font_color", GameStyle.YELLOW)
			s_star_lbl.add_theme_color_override("font_outline_color", GameStyle.INK)
			s_star_lbl.add_theme_constant_override("outline_size", 3)
			s_star_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			s_star_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			s_star_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			s_star_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
			s_star_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			s_slot.add_child(s_star_lbl)

			var s_name: String = item.get("name", def.get("name", ""))
			s_slot.tooltip_text = "%s (%d阶)" % [s_name, s_star]
			_stash_box.add_child(s_slot)

func _refresh_history() -> void:
	for child in _history_list.get_children():
		child.queue_free()

	var history := GameManager.upgrade_history
	_history_count_lbl.text = "已领悟 %d 项加成" % history.size()

	if history.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "尚未有悟道加成，提升修为境界后可感悟天地法则。"
		GameStyle.label(empty_lbl, 13, GameStyle.GREY)
		_history_list.add_child(empty_lbl)
		return

	for i in range(history.size()):
		var item: Dictionary = history[i]
		var row := _create_history_row(item, i + 1)
		_history_list.add_child(row)

func _create_history_row(item: Dictionary, idx: int) -> Control:
	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var r_style := StyleBoxFlat.new()
	r_style.bg_color = Color(0.08, 0.11, 0.19, 0.8)
	r_style.border_width_left = 2
	r_style.border_color = item.get("border_color", GameStyle.PAPER_DIM)
	r_style.content_margin_left = 8.0
	r_style.content_margin_top = 4.0
	r_style.content_margin_right = 8.0
	r_style.content_margin_bottom = 4.0
	row.add_theme_stylebox_override("panel", r_style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	row.add_child(hbox)

	# 序号
	var num_lbl := Label.new()
	num_lbl.text = "%02d." % idx
	GameStyle.label(num_lbl, 12, GameStyle.GREY)
	hbox.add_child(num_lbl)

	# 图标
	if item.has("icon") and ResourceLoader.exists(item["icon"]):
		var tex := TextureRect.new()
		tex.texture = load(item["icon"])
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.custom_minimum_size = Vector2(24, 24)
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hbox.add_child(tex)

	# 稀有度标签
	var pill := Label.new()
	pill.text = " " + item.get("rarity_label", "凡品") + " "
	GameStyle.label(pill, 11, GameStyle.PAPER)
	var col: Color = item.get("border_color", GameStyle.PAPER)
	var pill_sb := GameStyle.block(col, GameStyle.SLANT_BAND, Vector2(1, 1))
	pill_sb.content_margin_top = 1.0
	pill_sb.content_margin_bottom = 1.0
	pill.add_theme_stylebox_override("normal", pill_sb)
	var band_text_col: Color = GameStyle.INK_TEXT if col.get_luminance() > 0.5 else GameStyle.PAPER
	pill.add_theme_color_override("font_color", band_text_col)
	hbox.add_child(pill)

	# 标题与次数
	var title_lbl := Label.new()
	var count_text: String = " (第%d次)" % item.get("count", 1) if item.get("count", 1) > 1 else ""
	title_lbl.text = str(item.get("title", "")) + count_text
	GameStyle.label(title_lbl, 13, GameStyle.PAPER)
	hbox.add_child(title_lbl)

	# 占位
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(sp)

	# 获得等级
	var lvl_lbl := Label.new()
	lvl_lbl.text = "Lv.%d" % int(item.get("level", 1))
	GameStyle.label(lvl_lbl, 12, GameStyle.YELLOW)
	hbox.add_child(lvl_lbl)

	return row
