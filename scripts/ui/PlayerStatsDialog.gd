class_name PlayerStatsDialog
extends Control

## 人物属性详情面板：可在战斗中查看基础属性、战斗加成、持用法器、历史悟道加点
## 采用全屏暂停式弹窗，支持右上角返回、点击半透明遮罩背景或按 ESC 关闭
##
## 点按口径（2026-10-08）：属性行 / 法器格 / 备用法器 / 悟道条目全部可点，弹出 DetailTip 详解卡。
## 原先只有 tooltip_text —— 触屏没有 hover，手机上永远不会出现，于是「这行数字什么意思」在真机上无处可查。
## 卡里的读数一律现读 GameManager.get_stat_breakdown() 与 GameBalance / WeaponData 的同一批公式，
## 规则文案在 StatInfoData（只写人话、不抄数字），本面板不做第二套结算。

signal closed

var _closing: bool = false
var _unpause_on_close: bool = true

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
	_panel.custom_minimum_size = Vector2(880, _fit_panel_height())
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
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_panel.add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 8)
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

	# 一句提示把三个入口一起说完（每个区块各重复一遍就是噪音）
	var hint_lbl := Label.new()
	hint_lbl.text = "提示：点属性行、法器图标或悟道条目，可看它的算法与来源拆解。"
	GameStyle.label(hint_lbl, 12, GameStyle.GREY)
	root_vbox.add_child(hint_lbl)

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
	sb.content_margin_left = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_right = 12.0
	sb.content_margin_bottom = 8.0
	left_panel.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	left_panel.add_child(vbox)

	var sec_title := Label.new()
	sec_title.text = "✦ 气血与道法根基"
	GameStyle.label(sec_title, 15, GameStyle.YELLOW)
	vbox.add_child(sec_title)

	# 气血条（整行可点：与下面各属性行同一入口）
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
	var bar_st := GameStyle.bar_styles(Color(0.04, 0.06, 0.1, 0.85), Color(0.95, 0.94, 0.89))
	_hp_bar.add_theme_stylebox_override("background", bar_st[0])
	_hp_bar.add_theme_stylebox_override("fill", bar_st[1])
	hp_box.add_child(_hp_bar)

	_hp_val_lbl = Label.new()
	GameStyle.label(_hp_val_lbl, 13, GameStyle.PAPER)
	hp_box.add_child(_hp_val_lbl)
	vbox.add_child(_make_tip_row("hp", hp_box))

	var sep1 := HSeparator.new()
	sep1.add_theme_stylebox_override("separator", _create_line_style(GameStyle.LINE))
	vbox.add_child(sep1)

	# 各项属性行
	_regen_val_lbl = _add_stat_row(vbox, "regen", "+0.0 / 秒")
	_armor_val_lbl = _add_stat_row(vbox, "armor", "0 点 (减伤 0.0%)")
	_dodge_val_lbl = _add_stat_row(vbox, "dodge", "0% 闪避")
	_lifesteal_val_lbl = _add_stat_row(vbox, "lifesteal", "0% 概率")
	_atk_val_lbl = _add_stat_row(vbox, "damage", "100% (+0%)")
	_haste_val_lbl = _add_stat_row(vbox, "haste", "0% 冷却缩减")
	_speed_val_lbl = _add_stat_row(vbox, "speed", "210 (+0%)")
	_pickup_val_lbl = _add_stat_row(vbox, "pickup", "96 (+0%)")
	_range_val_lbl = _add_stat_row(vbox, "range", "+0%")
	_crit_val_lbl = _add_stat_row(vbox, "crit", "5.0% 概率 (1.5× 伤害)")
	_luck_val_lbl = _add_stat_row(vbox, "luck", "0")
	_harvest_val_lbl = _add_stat_row(vbox, "harvest", "0 (波末 +0)")

	var sep2 := HSeparator.new()
	sep2.add_theme_stylebox_override("separator", _create_line_style(GameStyle.LINE))
	vbox.add_child(sep2)

	_kills_val_lbl = _add_stat_row(vbox, "kills", "0 妖")
	_stones_val_lbl = _add_stat_row(vbox, "stones", "0 颗")

	return left_panel

## 属性行：名字来自 StatInfoData（面板与详解卡共用同一份标题，改一处就两处一起变）
func _add_stat_row(parent: Container, stat_id: String, default_val: String) -> Label:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)

	var l_name := Label.new()
	l_name.text = StatInfoData.title(stat_id)
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

	parent.add_child(_make_tip_row(stat_id, hbox))
	return l_val

## 把一行内容包进可点的整行热区。
## 为什么非要包一层 PanelContainer：Label 默认 MOUSE_FILTER_IGNORE，裸 HBoxContainer 的空隙
## 又会把事件漏给背后的面板 —— 结果就是「只有那几个字能点，偏一个像素就没反应」，
## 在触屏上这跟坏了一样。包一层并设成 STOP，整行全可点。
func _make_tip_row(stat_id: String, content: Control) -> Control:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var flat := StyleBoxFlat.new()
	flat.draw_center = false
	var on := StyleBoxFlat.new()
	on.bg_color = Color(GameStyle.BLUE.r, GameStyle.BLUE.g, GameStyle.BLUE.b, 0.22)
	row.add_theme_stylebox_override("panel", flat)
	row.set_meta("sb_flat", flat)
	row.set_meta("sb_on", on)
	row.set_meta("tip_title", StatInfoData.title(stat_id))
	row.gui_input.connect(func(ev: InputEvent) -> void:
		if _is_tap(ev):
			_open_stat_tip(stat_id, row)
	)
	row.add_child(content)
	return row

## 卡开着的那段时间，给触发它的那一行压一层蓝底：详情卡贴在旁边，「哪一行在讲这件事」
## 必须跟卡片同生同灭。触屏没有 hover，靠悬停提示可点在这台设备上等于没有提示。
func _highlight_while_open(anchor: Control, tip: DetailTip) -> void:
	if anchor == null or tip == null or not anchor.has_meta("sb_on"):
		return
	var on: StyleBox = anchor.get_meta("sb_on")
	var flat: StyleBox = anchor.get_meta("sb_flat")
	anchor.add_theme_stylebox_override("panel", on)
	tip.closed.connect(func() -> void:
		if is_instance_valid(anchor):
			anchor.add_theme_stylebox_override("panel", flat)
	)

## 触屏与鼠标统一的「点按」判定：只认鼠标左键松开。
## 真机上 Godot 会把触摸再合成一份鼠标事件，两个分支都认就是一次点击走两遍
## （与 LevelUpDialog 的卡片点击、本面板遮罩同一口径）。
func _is_tap(ev: InputEvent) -> bool:
	return ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed

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
		# 返回键先把详情卡收回去，再关面板：一次退出只退一层，不然按一次 ESC 连卡带面板一起没了
		if DetailTip.close_all(self):
			get_viewport().set_input_as_handled()
			return
		close()
		get_viewport().set_input_as_handled()

func open(unpause_on_close: bool = true) -> void:
	if visible or GameManager.is_game_over:
		return
	_closing = false
	_unpause_on_close = unpause_on_close
	_panel.custom_minimum_size.y = _fit_panel_height()
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
		if _unpause_on_close:
			get_tree().paused = false
		_closing = false
		closed.emit()
	)

func refresh() -> void:
	# 每次刷新都会整批重建行与格子：浮层继续贴着旧坐标，就是贴在一片废墟上，先收掉
	DetailTip.close_all(self)
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
		# 空格也点得动：想知道「这一格为什么是空的」同样要有答案
		slot.mouse_filter = Control.MOUSE_FILTER_STOP

		var filled := i < summary.size()
		var border_col: Color = GameStyle.BLUE if filled else GameStyle.LINE
		var bg_col: Color = GameStyle.NAVY if filled else Color(GameStyle.INK.r, GameStyle.INK.g, GameStyle.INK.b, 0.45)
		var sb_off := GameStyle.outlined_panel(bg_col, border_col, 2, 0.0)
		slot.add_theme_stylebox_override("panel", sb_off)
		slot.set_meta("sb_flat", sb_off)
		slot.set_meta("sb_on", GameStyle.outlined_panel(bg_col, GameStyle.YELLOW, 2, 0.0))

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

			var w_id: String = w.get("id", "")
			var w_star: int = int(w.get("star", 1))
			var tag_name: String = w.get("name", "")
			var w_tag: String = w.get("tag", "")
			var stat_bonus: float = GameManager.get_weapon_stat_bonus(w_id, w_star)
			var tip := "%s (%d阶) [%s]" % [tag_name, w_star, w_tag]
			if stat_bonus > 0.05:
				tip += "\n属性转化增伤: +%.1f" % stat_bonus
			tip += "\n点按看它的伤害算法"
			slot.tooltip_text = tip
			slot.gui_input.connect(func(ev: InputEvent) -> void:
				if _is_tap(ev):
					_open_weapon_tip(w, false, slot)
			)
		else:
			var empty_dot := Label.new()
			empty_dot.text = "·"
			empty_dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty_dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			GameStyle.label(empty_dot, 16, GameStyle.GREY)
			slot.add_child(empty_dot)
			slot.gui_input.connect(func(ev: InputEvent) -> void:
				if _is_tap(ev):
					_open_empty_slot_tip(i, slot)
			)

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
			var s_sb := GameStyle.outlined_panel(GameStyle.NAVY2, GameStyle.LINE, 1, 0.0)
			s_slot.add_theme_stylebox_override("panel", s_sb)

			var s_icon_path: String = item.get("icon", def.get("icon", ""))
			var s_tex := TextureRect.new()
			if not s_icon_path.is_empty() and ResourceLoader.exists(s_icon_path):
				s_tex.texture = load(s_icon_path)
			s_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			s_tex.custom_minimum_size = Vector2(26, 26)
			s_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			s_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			s_slot.add_child(s_tex)
			s_slot.set_meta("sb_flat", s_sb)
			s_slot.set_meta("sb_on", GameStyle.outlined_panel(GameStyle.NAVY2, GameStyle.YELLOW, 1, 0.0))

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
			if def.is_empty():
				# 表里查不到的 id（老档或改过 id）：不弹一张空卡，只留原来的读数
				s_slot.tooltip_text = "%s (%d阶)" % [s_name, s_star]
			else:
				s_slot.tooltip_text = "%s (%d阶)\n点按看它的伤害算法" % [s_name, s_star]
				s_slot.mouse_filter = Control.MOUSE_FILTER_STOP
				s_slot.gui_input.connect(func(ev: InputEvent) -> void:
					if _is_tap(ev):
						_open_weapon_tip(item, true, s_slot)
				)
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
	var r_on := r_style.duplicate() as StyleBoxFlat
	r_on.bg_color = Color(0.16, 0.22, 0.36, 0.95)
	r_on.border_width_left = 4
	row.set_meta("sb_flat", r_style)
	row.set_meta("sb_on", r_on)
	# 整条可点：这里只显示了名字、稀有度和次数，「它到底加了多少、吃到第几层」在卡里
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.gui_input.connect(func(ev: InputEvent) -> void:
		if _is_tap(ev):
			_open_history_tip(item, idx, row)
	)
	row.tooltip_text = "点按看这一条的幅度与来源"

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
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	# 裸 Control 默认 STOP：不改成 IGNORE，名字与 Lv. 之间那一大段就是块隐形挡板，
	# 整条只有左右两头点得动 —— 触屏上读起来跟「这行没接上」一模一样
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(sp)

	# 获得等级
	var lvl_lbl := Label.new()
	lvl_lbl.text = "Lv.%d" % int(item.get("level", 1))
	GameStyle.label(lvl_lbl, 12, GameStyle.YELLOW)
	hbox.add_child(lvl_lbl)

	return row

# ============================ 点按详解 ============================

## 面板最小高：原先写死 560，比 960×540 的视口还高 ⇒ 上下各被切走 10 单位，
## 被切走的正好是最底下两行（累计诛妖 / 随身灵石）—— 而那两行如今是要点却点不到的地方。
## 只夹「最小高」不够（容器仍会被内容顶开），所以配套的边距与行距一并收紧，
## 由 tests/StatsTipCheck 逐档长宽比量 rect 钉死：面板与每一个可点件都必须整块在屏内。
func _fit_panel_height() -> float:
	var vp := get_viewport_rect().size
	if vp.y <= 0.0:
		return 520.0
	return clampf(vp.y - 12.0, 380.0, 520.0)

func _open_stat_tip(id: String, anchor: Control) -> void:
	if not StatInfoData.has(id):
		return
	var tip := DetailTip.show_over(self, anchor, {
		"title": StatInfoData.title(id),
		"rows": _stat_tip_rows(id),
		"body": StatInfoData.brief(id),
		"notes": StatInfoData.rules(id),
		"foot": _stat_tip_foot(id),
	})
	_highlight_while_open(anchor, tip)

## 来源拆解：每一行都是现读 GameManager 的字段与 GameBalance 的公式，
## 面板左侧那个数字与卡里的拆解必须同一次算出来，不许在卡里再写一遍结果。
func _stat_tip_rows(id: String) -> Array:
	var s := GameManager.get_stat_breakdown()
	var rows: Array = []
	match id:
		"hp":
			var mx: float = float(s.get("max_hp", 0.0))
			var cur: float = float(s.get("current_hp", 0.0))
			rows = [
				["当前气血", "%d / %d" % [int(cur), int(mx)]],
				["气血上限", "%.0f" % mx],
				["已损", "%d 点" % int(mx - cur), GameStyle.BAD if cur < mx else GameStyle.GREY],
				["每秒回复", "+%.1f" % float(s.get("hp_regen", 0.0)), _c(float(s.get("hp_regen", 0.0)))],
				["道统", _cultivator_name()],
			]
		"regen":
			var rate: float = float(s.get("hp_regen", 0.0))
			var need: float = float(s.get("max_hp", 0.0)) - float(s.get("current_hp", 0.0))
			rows = [
				["每秒回复", "%.1f / 秒" % rate],
				["悟道·法宝·道统", "%.1f" % GameManager.hp_regen, _c(GameManager.hp_regen)],
				["流派羁绊", "+%.1f" % GameManager.synergy_hp_regen, _c(GameManager.synergy_hp_regen)],
				["回满这一截需要", "%.1f 秒" % (need / rate) if rate > 0.0 and need > 0.0 else "—"],
			]
		"armor":
			var arm: float = float(s.get("armor", 0.0))
			var nxt: float = GameBalance.armor_reduction(arm + 1.0) * 100.0
			rows = [
				["护甲合计", "%.0f 点" % arm],
				["悟道·法宝·道统", "%+.0f" % GameManager.armor, _c(GameManager.armor)],
				["流派羁绊", "%+.0f" % GameManager.synergy_armor, _c(GameManager.synergy_armor)],
				["当前减伤", "%.1f%%" % float(s.get("dmg_reduction_pct", 0.0)), GameStyle.GOOD],
				["再加 1 点", "+%.1f%%" % (nxt - float(s.get("dmg_reduction_pct", 0.0))), GameStyle.GOOD],
			]
		"dodge":
			var dg: float = float(s.get("dodge_pct", 0.0))
			var cap: float = GameManager.DODGE_CAP * 100.0
			rows = [
				["闪避率", "%.0f%%" % dg, _c(dg)],
				["悟道·法宝·道统", "%.0f%%" % (GameManager.dodge * 100.0), _c(GameManager.dodge)],
				["硬上限", "%.0f%%" % cap, GameStyle.GREY],
				["距上限", "%.0f%%" % maxf(0.0, cap - dg)],
			]
		"lifesteal":
			rows = [
				["触发概率", "%.0f%%" % float(s.get("lifesteal_pct", 0.0)), _c(float(s.get("lifesteal_pct", 0.0)))],
				["悟道·法宝·道统", "%.0f%%" % (GameManager.lifesteal * 100.0), _c(GameManager.lifesteal)],
				["流派羁绊", "%.0f%%" % (GameManager.synergy_lifesteal * 100.0), _c(GameManager.synergy_lifesteal)],
				["每秒至多", "%d 次" % GameManager.LIFESTEAL_MAX_PER_SEC],
				["每次生效", "回复 1 点气血"],
			]
		"damage":
			rows = [
				["总乘区", "%d%%" % int(float(s.get("damage_mult", 1.0)) * 100.0)],
				["换算增伤", "%+.0f%%" % float(s.get("damage_bonus_pct", 0.0)), _c(float(s.get("damage_bonus_pct", 0.0)))],
				["悟道·法宝·道统", _mul(GameManager.weapon_damage_mult), _c(GameManager.weapon_damage_mult - 1.0)],
				["流派羁绊", _mul(GameManager.synergy_damage_mult), _c(GameManager.synergy_damage_mult - 1.0)],
				["暴击另算", "%.0f%% 概率 ×%.2f" % [float(s.get("crit_rate_pct", 0.0)), float(s.get("crit_dmg_pct", 150.0)) / 100.0]],
			]
		"haste":
			rows = [
				["冷却缩减", "%.1f%%" % float(s.get("cdr_pct", 0.0)), _c(float(s.get("cdr_pct", 0.0)))],
				["实际施法间隔", _mul(float(s.get("attack_speed_mult", 1.0)))],
				["悟道·法宝·道统", _mul(GameManager.attack_speed_mult), _c(1.0 - GameManager.attack_speed_mult)],
				["流派羁绊", _mul(GameManager.synergy_haste_mult), _c(1.0 - GameManager.synergy_haste_mult)],
				["间隔地板", _mul(GameManager.ATTACK_SPEED_FLOOR), GameStyle.GREY],
			]
		"speed":
			var eff: float = GameManager.move_speed_mult + GameManager.synergy_move_speed_mult
			var spd: float = float(s.get("move_speed", 0.0))
			rows = [
				["实际移速", "%.0f" % spd],
				["道统基础", "%.0f" % (spd / eff if eff > 0.01 else spd)],
				["悟道·法宝·道统", "%+.0f%%" % ((GameManager.move_speed_mult - 1.0) * 100.0), _c(GameManager.move_speed_mult - 1.0)],
				["流派羁绊", "%+.0f%%" % (GameManager.synergy_move_speed_mult * 100.0), _c(GameManager.synergy_move_speed_mult)],
			]
		"pickup":
			var pkm: float = GameManager.pickup_range_mult
			var rad: float = float(s.get("pickup_radius", 0.0))
			rows = [
				["拾取半径", "%.0f 像素" % rad],
				["倍率", _mul(pkm), _c(pkm - 1.0)],
				["基础半径", "%.0f 像素" % (rad / pkm if pkm > 0.01 else rad)],
			]
		"range":
			rows = [
				["攻击范围", "%+.0f%%" % float(s.get("attack_range_pct", 0.0)), _c(float(s.get("attack_range_pct", 0.0)))],
				["悟道·法宝·道统", _mul(GameManager.attack_range_mult), _c(GameManager.attack_range_mult - 1.0)],
				["流派羁绊", _mul(GameManager.synergy_range_mult), _c(GameManager.synergy_range_mult - 1.0)],
			]
		"crit":
			var cmul: float = GameManager.crit_mult + GameManager.synergy_crit_mult
			rows = [
				["面板暴击率", "%.0f%%" % float(s.get("crit_rate_pct", 0.0)), GameStyle.YELLOW],
				["悟道·法宝·道统", "%.0f%%（含基础）" % (GameManager.crit_rate * 100.0)],
				["锐金羁绊", "+%.0f%%" % (GameManager.synergy_crit_rate * 100.0), _c(GameManager.synergy_crit_rate)],
				["暴击倍率", "%.2f×" % cmul, _c(cmul - 1.5)],
				["软上限", "%.0f%%" % (GameManager.CRIT_RATE_CAP * 100.0), GameStyle.GREY],
			]
		"luck":
			var rw: Dictionary = GameBalance.rarity_weights(GameManager.luck)
			rows = [
				["福缘", "%.0f" % float(s.get("luck", 0.0)), _c(GameManager.luck)],
				["仙品权重", "%.0f / %.0f" % [float(rw.get("epic", 0.0)), GameBalance.RARITY_TOTAL]],
				["良品权重", "%.0f / %.0f" % [float(rw.get("rare", 0.0)), GameBalance.RARITY_TOTAL]],
				["凡品权重", "%.0f / %.0f" % [float(rw.get("common", 0.0)), GameBalance.RARITY_TOTAL]],
			]
		"harvest":
			var hv: float = float(s.get("harvest", 0.0))
			var gain: int = GameBalance.harvest_gain(hv)
			rows = [
				["灵韵", "%.0f" % hv, _c(hv)],
				["本波末发放", "+%d 灵石 / +%d 修为" % [gain, gain], GameStyle.YELLOW],
				["每波复利", _mul(GameBalance.HARVEST_GROWTH), GameStyle.GREY],
				["增长截止", "第 %d 波（当前第 %d 波）" % [GameManager.HARVEST_GROWTH_WAVE_CAP, maxi(GameManager.wave_number, 1)]],
			]
		"kills":
			var mins: float = maxf(GameManager.game_time, 1.0) / 60.0
			rows = [
				["本局诛妖", "%d 妖" % GameManager.kills],
				["平均", "%.1f 妖/分钟" % (float(GameManager.kills) / mins)],
			]
		"stones":
			rows = [
				["随身灵石", "%d 枚" % GameManager.spirit_stones, GameStyle.YELLOW],
				["下一波灵韵", "+%d 枚" % GameBalance.harvest_gain(float(s.get("harvest", 0.0)))],
			]
	return rows

func _stat_tip_foot(id: String) -> String:
	var src: Array[String] = StatInfoData.sources(id)
	if src.is_empty():
		return ""
	return "可提升途径：" + "、".join(src)

## 空法器位也要说得出话：不然点上去没反应，和坏了没区别
func _open_empty_slot_tip(index: int, anchor: Control) -> void:
	var tip := DetailTip.show_over(self, anchor, {
		"title": "空法器位",
		"rows": [
			["上阵位", "第 %d 槽 / 共 %d 槽" % [index + 1, WeaponData.MAX_SLOTS]],
			["当前上阵", "%d 件" % GameManager.get_weapons_summary().size()],
			["纳戒仓库", "%d 件" % GameManager.stash.size()],
		],
		"body": "这一格还空着。法器按获得顺序自动补上阵法器位，不需要手动摆。",
		"notes": [
			"上阵 %d 格全满之后，新买的法器进纳戒仓库，只用于合成与出售。" % WeaponData.MAX_SLOTS,
			"上阵法器的数量决定流派羁绊的档位，多一件就多一路加成。",
		],
		"foot": "波间在灵石阁买法器即可补上这一格。",
	})
	_highlight_while_open(anchor, tip)

## 法器详情：单发伤害那一串乘区与 FloatingWeapon._final_damage() 逐字同一条公式，
## 不在卡里另算一套「看起来差不多」的期望值。
func _open_weapon_tip(w: Dictionary, from_stash: bool, anchor: Control) -> void:
	var id: String = String(w.get("id", ""))
	var def := WeaponData.get_def(id)
	if def.is_empty():
		return
	var star := clampi(int(w.get("star", 1)), 1, WeaponData.MAX_STAR)
	var base_dmg: float = float(def.get("damage", 0.0))
	var star_mul: float = pow(WeaponData.STAR_DAMAGE_MULT, float(star - 1))
	var bonus: float = GameManager.get_weapon_stat_bonus(id, star)
	var gm_dmg: float = GameManager.weapon_damage_mult
	var syn_dmg: float = GameManager.synergy_damage_mult
	var cult_dmg: float = GameManager.cultivator_damage_mult(id)
	var elem_dmg: float = GameManager.element_damage_mult(id)
	var per_hit: float = (base_dmg * star_mul + bonus) * gm_dmg * syn_dmg * cult_dmg * elem_dmg
	var cd: float = WeaponData.cooldown_for(id, star) * GameManager.attack_speed_mult * GameManager.synergy_haste_mult

	var rows: Array = [
		["单发伤害", "%.1f" % per_hit, GameStyle.YELLOW],
		["基础 × 星级", "%.0f × %.1f" % [base_dmg, star_mul]],
		["属性转化", "+%.1f" % bonus, _c(bonus)],
		["全局法伤", _mul(gm_dmg), _c(gm_dmg - 1.0)],
		["流派羁绊", _mul(syn_dmg), _c(syn_dmg - 1.0)],
		["道统", _mul(cult_dmg), _c(cult_dmg - 1.0)],
		["五行", _mul(elem_dmg), _c(elem_dmg - 1.0)],
		["施法间隔", "%.2f 秒" % cd],
		["射程", "%.0f" % float(def.get("range", 0.0))],
	]
	var feats := _weapon_feats(def)
	if not feats.is_empty():
		rows.append(["特性", feats])

	var notes: Array[String] = [
		"单发伤害 =（基础 × 星级 + 属性转化）× 全局法伤 × 流派羁绊 × 道统 × 五行；暴击另按 %.0f%% 概率 ×%.2f 结算。" % [
			GameManager.get_crit_rate() * 100.0, GameManager.crit_mult + GameManager.synergy_crit_mult],
		"%s（每星效率 +25%%）。" % WeaponData.scaling_desc(id),
		"升星：同名同星集满 3 件在灵石阁合成，伤害 ×%s、间隔 ×%s，最高 %s。" % [
			_num(WeaponData.STAR_DAMAGE_MULT), _num(WeaponData.STAR_COOLDOWN_MULT), WeaponData.star_text(WeaponData.MAX_STAR)],
	]

	# 持有数与售价压进脚注：这两条不是「它怎么打人」，占一行读数不如省下来给乘区链
	var foot := "同名同星 %d 件 · 出售可得 %d 枚" % [
		GameManager.count_copies(id, star), WeaponData.sell_price(id, star)]
	if from_stash:
		foot += "\n在纳戒仓库里：未上阵、不出手、不吃羁绊，只用于合成与出售。"

	var tip := DetailTip.show_over(self, anchor, {
		"title": "%s %s" % [String(def.get("name", "法器")), WeaponData.star_text(star)],
		"chip": String(def.get("tag", "")),
		"chip_color": GameStyle.YELLOW_DK if from_stash else GameStyle.BLUE_DK,
		"rows": rows,
		"body": String(def.get("desc", "")),
		"notes": notes,
		"foot": foot,
	})
	_highlight_while_open(anchor, tip)
## 特性行：表里有哪个键就说哪句，缺的键不编
func _weapon_feats(def: Dictionary) -> String:
	var out: Array[String] = []
	# 弹丸类法器从 2026-10-08 起带有限转向追踪（BladeProjectile.HOMING_TURN_RATE）：
	# 触屏没有 hover，这条只能在详情里说清，否则玩家会以为"打不中是我操作的问题"
	if int(def.get("behavior", -1)) == WeaponData.Behavior.PROJECTILE:
		out.append("锁敌追击")
	var pierce: int = int(def.get("pierce", 0))
	if pierce > 0:
		out.append("穿透 %d" % (pierce + GameManager.bonus_pierce))
	var count: int = int(def.get("projectile_count", 1))
	if count > 1:
		out.append("一次 %d 段" % count)
	var bounce: int = int(def.get("bounce_count", 0))
	if bounce > 0:
		out.append("弹射 %d 次" % bounce)
	var arc: float = float(def.get("arc_scale", 1.0))
	if arc > 1.001:
		out.append("横扫 ×%s" % _num(arc))
	if bool(def.get("proc_poison", false)):
		out.append("附毒")
	if bool(def.get("proc_burn", false)):
		out.append("灼烧")
	if float(def.get("proc_chill", 0.0)) > 0.0:
		out.append("冰缓")
	return "、".join(out)

## 悟道条目详情：正文直接沿用 UpgradeData 的 desc（与波后悟道卡片同一份文案，不再抄第二遍）
func _open_history_tip(item: Dictionary, idx: int, anchor: Control) -> void:
	var id: String = String(item.get("id", ""))
	var def := UpgradeData.get_upgrade_def(id)
	var apply: Dictionary = def.get("apply", {})
	var taken: int = int(item.get("count", 1))
	var cap: int = int(def.get("max_stacks", 0))
	var t: float = float(item.get("time", 0.0))

	var rows: Array = []
	for key in apply.keys():
		var k := String(key)
		var v := float(apply[key])
		rows.append([StatInfoData.field_name(k), StatInfoData.format_amount(k, v), _c(v)])
	rows.append(["已领悟", "第 %d 次 / 上限 %d 次" % [taken, cap],
		GameStyle.YELLOW if cap > 0 and taken >= cap else GameStyle.PAPER])
	rows.append(["领悟于", "Lv.%d · %02d:%02d" % [int(item.get("level", 1)), int(t / 60.0), int(t) % 60]])
	if cap > 0 and taken >= cap:
		rows.append(["状态", "已叠满，不再出现在候选里", GameStyle.GREY])

	var notes: Array[String] = [
		"升级只攒点数，每波妖潮平息后统一加点；选定即生效、不可撤销，同一条最多领悟 %d 次，叠满后从池子里剔除。" % cap,
		"领悟时卡片上写的那点幅度，就是真正落地的幅度：不会另有一本账。",
	]
	var stat_id := _stat_of_apply(apply)
	var foot := "" if stat_id.is_empty() else "这一条落在左侧「%s」那一行，点它可以看来源拆解。" % StatInfoData.title(stat_id)

	var tip := DetailTip.show_over(self, anchor, {
		"title": String(item.get("title", "悟道")),
		"chip": String(item.get("rarity_label", "凡品")),
		"chip_color": item.get("border_color", GameStyle.BLUE_DK),
		"rows": rows,
		"body": String(item.get("desc", "")),
		"notes": notes,
		"foot": foot,
	})
	_highlight_while_open(anchor, tip)

## 这条悟道影响面板上哪一行：走 StatInfoData 的反查表，不在面板里再写一份字段对照
func _stat_of_apply(apply: Dictionary) -> String:
	for key in apply.keys():
		var sid: String = StatInfoData.stat_of_field(String(key))
		if not sid.is_empty():
			return sid
	return ""

func _cultivator_name() -> String:
	var def := CultivatorData.get_def(GameManager.cultivator_id)
	if def.is_empty():
		return "未选道统"
	return String(def.get("name", "未选道统"))

## 语义色：正收益绿、负收益红、没动过灰
func _c(v: float) -> Color:
	if v > 0.0001:
		return GameStyle.GOOD
	if v < -0.0001:
		return GameStyle.BAD
	return GameStyle.GREY

func _mul(v: float) -> String:
	return "×%.2f" % v

func _num(v: float) -> String:
	if absf(v - roundf(v)) < 0.0001:
		return "%d" % int(roundf(v))
	return "%.2f" % v
