class_name PlayerStatsDialog
extends Control

## 人物属性详情面板：仿《土豆兄弟》构筑总览界面
## 左侧：主要/次要属性 Tab 切换（覆盖全部 25 项属性，点按看详解与来源拆解）
## 右侧：上阵法器槽 + 流派羁绊阶梯加成卡（直观显示 2/6 持有进度与各级加成激活状态）+ 随身法宝/悟道历程双标签

signal closed

var _closing: bool = false
var _unpause_on_close: bool = true

# UI 节点引用
var _dim_rect: ColorRect
var _panel: PanelContainer
var _title_label: Label
var _meta_label: Label
var _close_btn: Button

# 左侧属性 Tab 与容器
var _stat_tab_primary_btn: Button
var _stat_tab_secondary_btn: Button
var _primary_stats_box: VBoxContainer
var _secondary_stats_box: VBoxContainer
var _current_stat_tab: int = 0 # 0 = 主要, 1 = 次要

# 左侧属性节点（主要 16 项 + 次要 9 项 = 25 项）
var _hp_bar: ProgressBar
var _hp_val_lbl: Label
var _regen_val_lbl: Label
var _lifesteal_val_lbl: Label
var _atk_val_lbl: Label
var _melee_val_lbl: Label
var _ranged_val_lbl: Label
var _elem_val_lbl: Label
var _eng_val_lbl: Label
var _haste_val_lbl: Label
var _crit_val_lbl: Label
var _range_val_lbl: Label
var _armor_val_lbl: Label
var _dodge_val_lbl: Label
var _speed_val_lbl: Label
var _luck_val_lbl: Label
var _harvest_val_lbl: Label

var _pickup_val_lbl: Label
var _xp_gain_val_lbl: Label
var _elite_dmg_val_lbl: Label
var _knockback_val_lbl: Label
var _pierce_val_lbl: Label
var _shop_price_val_lbl: Label
var _free_rerolls_val_lbl: Label
var _stones_val_lbl: Label
var _kills_val_lbl: Label

# 右侧法器、羁绊、法宝与历史节点（保留测试依赖变量名 _weapons_box / _stash_box / _history_list）
var _wp_title_lbl: Label
var _weapons_box: HBoxContainer
# 顶部道统卡：当前角色的正面加成 / 负面代偿速览
var _cult_card: PanelContainer
var _cult_icon: TextureRect
var _cult_name_lbl: Label
var _cult_epi_lbl: Label
var _cult_pros_lbl: Label
var _cult_cons_lbl: Label
var _stash_box: HBoxContainer
var _stash_section: HBoxContainer
var _synergy_flow: HFlowContainer
var _synergy_hint_lbl: Label

var _bottom_tab_items_btn: Button
var _bottom_tab_hist_btn: Button
var _items_scroll: ScrollContainer
var _items_flow: HFlowContainer
var _history_scroll: ScrollContainer
var _history_list: VBoxContainer
var _history_count_lbl: Label
var _current_bottom_tab: int = 0 # 0 = 随身法宝, 1 = 悟道历程

## 各流派每一档的阶梯文案（与 WeaponData.SYNERGIES 数值严格同源）
const SYNERGY_TIER_LINES: Dictionary = {
	"sword": ["攻击范围 +15%", "攻击范围 +30%", "攻击范围 +50%"],
	"talisman": ["弹丸穿透 +1", "弹丸穿透 +2", "弹丸穿透 +3"],
	"thunder": ["攻击间隔 -8%", "攻击间隔 -15%", "攻击间隔 -25%"],
	"spirit": ["气血上限 +15", "气血上限 +30", "气血上限 +50"],
	"wide": ["法器伤害 +10%", "法器伤害 +20%", "法器伤害 +30%"],
	"metal": ["暴击率+6% · 暴伤+20%", "暴击率+12% · 暴伤+40%", "暴击率+20% · 暴伤+75%"],
	"wood": ["回复+1.0/秒 · 吸血+2%", "回复+2.0/秒 · 吸血+4%", "回复+3.5/秒 · 吸血+7%"],
	"water": ["攻击间隔-6% · 移速+8%", "攻击间隔-12% · 移速+16%", "攻击间隔-20% · 移速+25%"],
	"fire": ["法伤+8% · 灼烧+30%", "法伤+16% · 灼烧+60%", "法伤+26% · 灼烧+100%"],
	"earth": ["护甲+3 · 击退+25%", "护甲+6 · 击退+50%", "护甲+10 · 击退+80%"],
}

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

	# 3. 仙侠大面板
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(900, _fit_panel_height())
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_to_group(DawnJoystick.UI_PRESS_HOLD_GROUP)
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
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_panel.add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 6)
	margin.add_child(root_vbox)

	# 4. 顶部标题栏
	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 10)

	var title_box := PanelContainer.new()
	title_box.add_theme_stylebox_override("panel", GameStyle.block(GameStyle.BLUE, GameStyle.SLANT_BAND, Vector2(3, 4)))
	var title_margin := MarginContainer.new()
	title_margin.add_theme_constant_override("margin_left", 12)
	title_margin.add_theme_constant_override("margin_right", 12)
	title_margin.add_theme_constant_override("margin_top", 3)
	title_margin.add_theme_constant_override("margin_bottom", 3)
	_title_label = Label.new()
	_title_label.text = "修 为 境 界  ·  人 物 属 性"
	GameStyle.label(_title_label, 18, GameStyle.PAPER, 0, GameStyle.INK, true)
	title_margin.add_child(_title_label)
	title_box.add_child(title_margin)
	top_bar.add_child(title_box)

	_meta_label = Label.new()
	GameStyle.label(_meta_label, 13, GameStyle.YELLOW)
	_meta_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_meta_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_bar.add_child(_meta_label)

	var hint_lbl := Label.new()
	hint_lbl.text = "点任意条目查看加成拆解"
	GameStyle.label(hint_lbl, 11, GameStyle.GREY)
	hint_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_bar.add_child(hint_lbl)

	_close_btn = Button.new()
	_close_btn.text = "返 回 战 斗"
	_close_btn.custom_minimum_size = Vector2(96, 30)
	_close_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(_close_btn, GameStyle.NAVY2, GameStyle.BLUE, 13, GameStyle.PAPER, 5.0)
	_close_btn.pressed.connect(close)
	top_bar.add_child(_close_btn)

	root_vbox.add_child(top_bar)

	# 5. 主体内容：左右分栏
	var body_hbox := HBoxContainer.new()
	body_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_hbox.add_theme_constant_override("separation", 12)
	root_vbox.add_child(body_hbox)

	# 左侧栏：主要/次要属性面板（仿土豆兄弟）
	var left_panel := _build_left_stats_panel()
	body_hbox.add_child(left_panel)

	# 右侧栏：法器 + 流派羁绊阶梯 + 法宝/悟道
	var right_panel := _build_right_equipment_and_history_panel()
	body_hbox.add_child(right_panel)

func _build_left_stats_panel() -> Control:
	var left_panel := PanelContainer.new()
	left_panel.custom_minimum_size = Vector2(296, 0)
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb := GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 2, 0.0)
	sb.content_margin_left = 10.0
	sb.content_margin_top = 8.0
	sb.content_margin_right = 10.0
	sb.content_margin_bottom = 8.0
	left_panel.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	left_panel.add_child(vbox)

	# 顶部：属性标题 + 【主要 / 次要】Tab 切换
	var tab_bar := HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 6)
	vbox.add_child(tab_bar)

	var sec_title := Label.new()
	sec_title.text = "✦ 属 性"
	GameStyle.label(sec_title, 15, GameStyle.YELLOW)
	sec_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_bar.add_child(sec_title)

	_stat_tab_primary_btn = Button.new()
	_stat_tab_primary_btn.text = "主 要"
	_stat_tab_primary_btn.custom_minimum_size = Vector2(76, 26)
	_stat_tab_primary_btn.focus_mode = Control.FOCUS_NONE
	_stat_tab_primary_btn.pressed.connect(func(): _switch_stat_tab(0))
	tab_bar.add_child(_stat_tab_primary_btn)

	_stat_tab_secondary_btn = Button.new()
	_stat_tab_secondary_btn.text = "次 要"
	_stat_tab_secondary_btn.custom_minimum_size = Vector2(76, 26)
	_stat_tab_secondary_btn.focus_mode = Control.FOCUS_NONE
	_stat_tab_secondary_btn.pressed.connect(func(): _switch_stat_tab(1))
	tab_bar.add_child(_stat_tab_secondary_btn)

	# 常驻气血条（整行可点）
	var hp_box := HBoxContainer.new()
	hp_box.add_theme_constant_override("separation", 6)
	var hp_title := Label.new()
	hp_title.text = StatInfoData.title("hp")
	GameStyle.label(hp_title, 12, GameStyle.PAPER_DIM)
	hp_box.add_child(hp_title)

	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size = Vector2(105, 13)
	_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hp_bar.show_percentage = false
	# 纯显示件也要让开「按下」那一拍：ProgressBar 的 mouse_filter 默认是 STOP，它自己不处理
	# 输入却照样把事件吃掉 → 气血值那一整行里最显眼的血条成了死点（点名字弹卡、点血条没反应）。
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar_st := GameStyle.bar_styles(Color(0.04, 0.06, 0.1, 0.85), GameStyle.GOOD)
	_hp_bar.add_theme_stylebox_override("background", bar_st[0])
	_hp_bar.add_theme_stylebox_override("fill", bar_st[1])
	hp_box.add_child(_hp_bar)

	_hp_val_lbl = Label.new()
	GameStyle.label(_hp_val_lbl, 12, GameStyle.GOOD)
	hp_box.add_child(_hp_val_lbl)
	vbox.add_child(_make_tip_row("hp", hp_box))

	var sep1 := HSeparator.new()
	sep1.add_theme_stylebox_override("separator", _create_line_style(GameStyle.LINE))
	vbox.add_child(sep1)

	# 主要属性页（15 行，加上顶端常驻气血共 16 项）——按 攻击/生存/机动 分三块
	_primary_stats_box = VBoxContainer.new()
	_primary_stats_box.add_theme_constant_override("separation", 2)
	_primary_stats_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_primary_stats_box)

	var atk_block := _add_stat_block(_primary_stats_box, "攻 击")
	_atk_val_lbl = _add_stat_row(atk_block, "damage", "+0%")
	_melee_val_lbl = _add_stat_row(atk_block, "melee_dmg", "0")
	_ranged_val_lbl = _add_stat_row(atk_block, "ranged_dmg", "0")
	_elem_val_lbl = _add_stat_row(atk_block, "elemental_dmg", "0")
	_eng_val_lbl = _add_stat_row(atk_block, "engineering_dmg", "0")
	_crit_val_lbl = _add_stat_row(atk_block, "crit", "5% (1.5×)")
	_range_val_lbl = _add_stat_row(atk_block, "range", "+0%")

	var sur_block := _add_stat_block(_primary_stats_box, "生 存")
	_regen_val_lbl = _add_stat_row(sur_block, "regen", "+0.0 / 秒")
	_lifesteal_val_lbl = _add_stat_row(sur_block, "lifesteal", "0% 概率")
	_armor_val_lbl = _add_stat_row(sur_block, "armor", "0 (0%)")
	_dodge_val_lbl = _add_stat_row(sur_block, "dodge", "0%")

	var util_block := _add_stat_block(_primary_stats_box, "机 动")
	_haste_val_lbl = _add_stat_row(util_block, "haste", "0.0%")
	_speed_val_lbl = _add_stat_row(util_block, "speed", "210 (+0%)")
	_luck_val_lbl = _add_stat_row(util_block, "luck", "0")
	_harvest_val_lbl = _add_stat_row(util_block, "harvest", "0")

	# 次要属性页（9 行）——按 战斗/成长/经营 分三块
	_secondary_stats_box = VBoxContainer.new()
	_secondary_stats_box.add_theme_constant_override("separation", 2)
	_secondary_stats_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_secondary_stats_box)

	var sec_combat := _add_stat_block(_secondary_stats_box, "战 斗")
	_elite_dmg_val_lbl = _add_stat_row(sec_combat, "elite_dmg", "+0%")
	_knockback_val_lbl = _add_stat_row(sec_combat, "knockback", "+0%")
	_pierce_val_lbl = _add_stat_row(sec_combat, "bonus_pierce", "0")

	var sec_growth := _add_stat_block(_secondary_stats_box, "成 长")
	_pickup_val_lbl = _add_stat_row(sec_growth, "pickup", "96 (+0%)")
	_xp_gain_val_lbl = _add_stat_row(sec_growth, "xp_gain", "+0%")

	var sec_econ := _add_stat_block(_secondary_stats_box, "经 营")
	_shop_price_val_lbl = _add_stat_row(sec_econ, "shop_price", "+0%")
	_free_rerolls_val_lbl = _add_stat_row(sec_econ, "free_rerolls", "0 次")
	_stones_val_lbl = _add_stat_row(sec_econ, "stones", "0 枚")
	_kills_val_lbl = _add_stat_row(sec_econ, "kills", "0 妖")

	_switch_stat_tab(0)
	return left_panel

func _switch_stat_tab(tab_idx: int) -> void:
	_current_stat_tab = tab_idx
	if _primary_stats_box != null:
		_primary_stats_box.visible = (tab_idx == 0)
	if _secondary_stats_box != null:
		_secondary_stats_box.visible = (tab_idx == 1)
	if _stat_tab_primary_btn != null:
		if tab_idx == 0:
			GameStyle.button(_stat_tab_primary_btn, GameStyle.PAPER, GameStyle.YELLOW, 12, GameStyle.INK_TEXT, 4.0)
		else:
			GameStyle.button(_stat_tab_primary_btn, GameStyle.NAVY2, GameStyle.BLUE, 12, GameStyle.PAPER_DIM, 4.0)
	if _stat_tab_secondary_btn != null:
		if tab_idx == 1:
			GameStyle.button(_stat_tab_secondary_btn, GameStyle.PAPER, GameStyle.YELLOW, 12, GameStyle.INK_TEXT, 4.0)
		else:
			GameStyle.button(_stat_tab_secondary_btn, GameStyle.NAVY2, GameStyle.BLUE, 12, GameStyle.PAPER_DIM, 4.0)

## 属性行：名字来自 StatInfoData（面板与详解卡共用同一份标题，改一处就两处一起变）
func _add_stat_row(parent: Container, stat_id: String, default_val: String) -> Label:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)

	var l_name := Label.new()
	l_name.text = StatInfoData.title(stat_id)
	GameStyle.label(l_name, 12, GameStyle.PAPER_DIM)
	hbox.add_child(l_name)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(spacer)

	var l_val := Label.new()
	l_val.text = default_val
	GameStyle.label(l_val, 12, GameStyle.PAPER)
	hbox.add_child(l_val)

	parent.add_child(_make_tip_row(stat_id, hbox))
	return l_val

## 属性分块：一组同类属性包一个浅色凹槽块，头行小标签 + 行列表（攻击/生存/机动…）
func _add_stat_block(parent: Container, header_text: String) -> VBoxContainer:
	var block := PanelContainer.new()
	var bs := GameStyle.outlined_panel(GameStyle.NAVY2, GameStyle.LINE, 1, 0.0)
	# 上下内边距 2/3：分组块 ×3，这里每省 2px 就是面板总高 6px——
	# 内容最小高度必须压在 526 钳制值内（StatsTipCheck 的 9px 出屏边距判定），否则面板被撑高出屏。
	bs.content_margin_left = 8.0
	bs.content_margin_top = 2.0
	bs.content_margin_right = 8.0
	bs.content_margin_bottom = 3.0
	block.add_theme_stylebox_override("panel", bs)
	parent.add_child(block)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 1)
	block.add_child(inner)

	var head := Label.new()
	head.text = header_text
	GameStyle.label(head, 11, GameStyle.YELLOW)
	inner.add_child(head)
	return inner

## 把一行内容包进可点的整行热区。
func _make_tip_row(stat_id: String, content: Control) -> Control:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var flat := StyleBoxFlat.new()
	flat.draw_center = false
	flat.content_margin_top = 1.0
	flat.content_margin_bottom = 1.0
	var on := StyleBoxFlat.new()
	on.bg_color = Color(GameStyle.BLUE.r, GameStyle.BLUE.g, GameStyle.BLUE.b, 0.22)
	on.content_margin_top = 1.0
	on.content_margin_bottom = 1.0
	row.add_theme_stylebox_override("panel", flat)
	row.set_meta("sb_flat", flat)
	row.set_meta("sb_on", on)
	row.set_meta("tip_title", StatInfoData.title(stat_id))
	GameStyle.tap(row, func() -> void: _open_stat_tip(stat_id, row))
	row.add_child(content)
	return row

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

func _build_right_equipment_and_history_panel() -> Control:
	var right_vbox := VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_theme_constant_override("separation", 8)

	# 0. 顶部：当前道统特性速览（正面加成 / 负面代偿，点按看全部详解）
	_cult_card = PanelContainer.new()
	_cult_card.mouse_filter = Control.MOUSE_FILTER_STOP
	var cult_st := GameStyle.outlined_panel(GameStyle.NAVY, GameStyle.LINE, 2, 0.0)
	cult_st.content_margin_left = 12.0
	cult_st.content_margin_top = 5.0
	cult_st.content_margin_right = 12.0
	cult_st.content_margin_bottom = 5.0
	_cult_card.add_theme_stylebox_override("panel", cult_st)
	_cult_card.set_meta("sb_flat", cult_st)
	_cult_card.set_meta("sb_on", GameStyle.outlined_panel(GameStyle.NAVY.lightened(0.08), GameStyle.YELLOW, 2, 0.0))

	var cult_row := HBoxContainer.new()
	cult_row.add_theme_constant_override("separation", 10)
	_cult_card.add_child(cult_row)

	_cult_icon = TextureRect.new()
	_cult_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cult_icon.custom_minimum_size = Vector2(40, 40)
	_cult_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_cult_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cult_row.add_child(_cult_icon)

	var cult_text := VBoxContainer.new()
	cult_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cult_text.add_theme_constant_override("separation", 1)
	cult_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cult_row.add_child(cult_text)

	var cult_head := HBoxContainer.new()
	cult_head.add_theme_constant_override("separation", 8)
	cult_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cult_text.add_child(cult_head)

	_cult_name_lbl = Label.new()
	GameStyle.label(_cult_name_lbl, 13, GameStyle.YELLOW)
	cult_head.add_child(_cult_name_lbl)

	_cult_epi_lbl = Label.new()
	GameStyle.label(_cult_epi_lbl, 11, GameStyle.GREY)
	cult_head.add_child(_cult_epi_lbl)

	var cult_head_sp := Control.new()
	cult_head_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cult_head_sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cult_head.add_child(cult_head_sp)

	var cult_hint := Label.new()
	cult_hint.text = "点按看道统全部特性"
	GameStyle.label(cult_hint, 10, GameStyle.GREY)
	cult_head.add_child(cult_hint)

	_cult_pros_lbl = Label.new()
	GameStyle.label(_cult_pros_lbl, 11, GameStyle.GOOD)
	cult_text.add_child(_cult_pros_lbl)

	_cult_cons_lbl = Label.new()
	GameStyle.label(_cult_cons_lbl, 11, GameStyle.BAD)
	cult_text.add_child(_cult_cons_lbl)

	GameStyle.tap(_cult_card, func() -> void: _open_cultivator_tip(_cult_card))
	right_vbox.add_child(_cult_card)

	# 1. 上半区：上阵法器与纳戒仓库
	var wp_panel := PanelContainer.new()
	var wp_st := GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 2, 0.0)
	wp_st.content_margin_left = 12.0
	wp_st.content_margin_top = 6.0
	wp_st.content_margin_right = 12.0
	wp_st.content_margin_bottom = 6.0
	wp_panel.add_theme_stylebox_override("panel", wp_st)

	var wp_vbox := VBoxContainer.new()
	wp_vbox.add_theme_constant_override("separation", 6)
	wp_panel.add_child(wp_vbox)

	var wp_head := HBoxContainer.new()
	wp_head.add_theme_constant_override("separation", 10)
	_wp_title_lbl = Label.new()
	_wp_title_lbl.text = "✦ 上阵法器 (0/6)"
	GameStyle.label(_wp_title_lbl, 14, GameStyle.YELLOW)
	wp_head.add_child(_wp_title_lbl)

	var wp_sp := Control.new()
	wp_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wp_head.add_child(wp_sp)

	var wp_sub := Label.new()
	wp_sub.text = "点图标看伤害乘区与升星规则"
	GameStyle.label(wp_sub, 11, GameStyle.GREY)
	wp_head.add_child(wp_sub)
	wp_vbox.add_child(wp_head)

	var slots_row := HBoxContainer.new()
	slots_row.add_theme_constant_override("separation", 12)
	wp_vbox.add_child(slots_row)

	_weapons_box = HBoxContainer.new()
	_weapons_box.add_theme_constant_override("separation", 8)
	slots_row.add_child(_weapons_box)

	# 纳戒仓库同排右侧展示（不额外撑高纵向空间）
	_stash_section = HBoxContainer.new()
	_stash_section.add_theme_constant_override("separation", 6)
	var stash_title := Label.new()
	stash_title.text = "仓库:"
	stash_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	GameStyle.label(stash_title, 12, GameStyle.GREY)
	_stash_section.add_child(stash_title)
	_stash_box = HBoxContainer.new()
	_stash_box.add_theme_constant_override("separation", 6)
	_stash_section.add_child(_stash_box)
	slots_row.add_child(_stash_section)

	right_vbox.add_child(wp_panel)

	# 2. 中间核心区：流派羁绊与五行共鸣（仿土豆兄弟装备标签阶梯加成）
	var syn_panel := PanelContainer.new()
	var syn_st := GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 2, 0.0)
	syn_st.content_margin_left = 12.0
	syn_st.content_margin_top = 6.0
	syn_st.content_margin_right = 12.0
	syn_st.content_margin_bottom = 6.0
	syn_panel.add_theme_stylebox_override("panel", syn_st)

	var syn_vbox := VBoxContainer.new()
	syn_vbox.add_theme_constant_override("separation", 6)
	syn_panel.add_child(syn_vbox)

	var syn_head := HBoxContainer.new()
	var syn_title := Label.new()
	syn_title.text = "✦ 流派羁绊与五行共鸣"
	GameStyle.label(syn_title, 14, GameStyle.YELLOW)
	syn_head.add_child(syn_title)

	var syn_sp := Control.new()
	syn_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	syn_head.add_child(syn_sp)

	_synergy_hint_lbl = Label.new()
	_synergy_hint_lbl.text = "集齐 2 / 4 / 6 件同系法器解锁阶梯加成"
	GameStyle.label(_synergy_hint_lbl, 11, GameStyle.GREY)
	syn_head.add_child(_synergy_hint_lbl)
	syn_vbox.add_child(syn_head)

	var syn_scroll := ScrollContainer.new()
	# 100：给顶部道统卡让出纵向空间，同时保住 StatsTipCheck 的 9px 出屏边距判定
	# （内容最小高度必须 ≤ 面板高度钳制 526，否则面板被撑高出屏）。羁绊卡可滚动，不丢信息。
	syn_scroll.custom_minimum_size = Vector2(0, 100)
	syn_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	syn_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	syn_vbox.add_child(syn_scroll)

	_synergy_flow = HFlowContainer.new()
	_synergy_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_synergy_flow.add_theme_constant_override("h_separation", 8)
	_synergy_flow.add_theme_constant_override("v_separation", 8)
	syn_scroll.add_child(_synergy_flow)

	right_vbox.add_child(syn_panel)

	# 3. 下半区：随身法宝 / 悟道历程（双标签切换）
	var bot_panel := PanelContainer.new()
	bot_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bot_st := GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 2, 0.0)
	bot_st.content_margin_left = 12.0
	bot_st.content_margin_top = 6.0
	bot_st.content_margin_right = 12.0
	bot_st.content_margin_bottom = 6.0
	bot_panel.add_theme_stylebox_override("panel", bot_st)

	var bot_vbox := VBoxContainer.new()
	bot_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bot_vbox.add_theme_constant_override("separation", 6)
	bot_panel.add_child(bot_vbox)

	var bot_header := HBoxContainer.new()
	bot_header.add_theme_constant_override("separation", 8)

	_bottom_tab_items_btn = Button.new()
	_bottom_tab_items_btn.text = "✦ 随身法宝 (0)"
	_bottom_tab_items_btn.custom_minimum_size = Vector2(136, 26)
	_bottom_tab_items_btn.focus_mode = Control.FOCUS_NONE
	_bottom_tab_items_btn.pressed.connect(func(): _switch_bottom_tab(0))
	bot_header.add_child(_bottom_tab_items_btn)

	_bottom_tab_hist_btn = Button.new()
	_bottom_tab_hist_btn.text = "✦ 悟道历程 (0)"
	_bottom_tab_hist_btn.custom_minimum_size = Vector2(136, 26)
	_bottom_tab_hist_btn.focus_mode = Control.FOCUS_NONE
	_bottom_tab_hist_btn.pressed.connect(func(): _switch_bottom_tab(1))
	bot_header.add_child(_bottom_tab_hist_btn)

	var h_spacer := Control.new()
	h_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot_header.add_child(h_spacer)

	_history_count_lbl = Label.new()
	_history_count_lbl.text = "点按图标或条目查看详情"
	GameStyle.label(_history_count_lbl, 11, GameStyle.PAPER_DIM)
	bot_header.add_child(_history_count_lbl)
	bot_vbox.add_child(bot_header)

	# 随身法宝滚动区
	_items_scroll = ScrollContainer.new()
	_items_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_items_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_items_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	bot_vbox.add_child(_items_scroll)

	_items_flow = HFlowContainer.new()
	_items_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_items_flow.add_theme_constant_override("h_separation", 8)
	_items_flow.add_theme_constant_override("v_separation", 8)
	_items_scroll.add_child(_items_flow)

	# 悟道历程滚动区
	_history_scroll = ScrollContainer.new()
	_history_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_history_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_history_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	bot_vbox.add_child(_history_scroll)

	_history_list = VBoxContainer.new()
	_history_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_history_list.add_theme_constant_override("separation", 5)
	_history_scroll.add_child(_history_list)

	_switch_bottom_tab(0)
	right_vbox.add_child(bot_panel)

	return right_vbox

func _switch_bottom_tab(tab_idx: int) -> void:
	_current_bottom_tab = tab_idx
	if _items_scroll != null:
		_items_scroll.visible = (tab_idx == 0)
	if _history_scroll != null:
		_history_scroll.visible = (tab_idx == 1)
	if _bottom_tab_items_btn != null:
		if tab_idx == 0:
			GameStyle.button(_bottom_tab_items_btn, GameStyle.BLUE, GameStyle.YELLOW, 12, GameStyle.PAPER, 4.0, GameStyle.INK_TEXT)
		else:
			GameStyle.button(_bottom_tab_items_btn, GameStyle.NAVY2, GameStyle.BLUE, 12, GameStyle.PAPER_DIM, 4.0)
	if _bottom_tab_hist_btn != null:
		if tab_idx == 1:
			GameStyle.button(_bottom_tab_hist_btn, GameStyle.BLUE, GameStyle.YELLOW, 12, GameStyle.PAPER, 4.0, GameStyle.INK_TEXT)
		else:
			GameStyle.button(_bottom_tab_hist_btn, GameStyle.NAVY2, GameStyle.BLUE, 12, GameStyle.PAPER_DIM, 4.0)

func _create_line_style(color: Color) -> StyleBoxLine:
	var s := StyleBoxLine.new()
	s.color = color
	s.thickness = 1
	return s

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
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
	DetailTip.close_all(self)
	var stats := GameManager.get_stat_breakdown()
	var mins := int(GameManager.game_time / 60.0)
	var secs := int(GameManager.game_time) % 60
	_meta_label.text = "%s  ·  Lv.%d  ·  第 %d 波 (%02d:%02d)" % [
		_cultivator_name(),
		GameManager.level,
		maxi(GameManager.wave_number, 1),
		mins, secs
	]

	# 1. 左侧主要属性刷新
	_hp_bar.max_value = stats["max_hp"]
	_hp_bar.value = stats["current_hp"]
	_hp_val_lbl.text = "%d / %d" % [int(stats["current_hp"]), int(stats["max_hp"])]

	var reg: float = float(stats["hp_regen"])
	_regen_val_lbl.text = "+%.1f / 秒" % reg
	_regen_val_lbl.add_theme_color_override("font_color", _c(reg))

	var ls_pct: float = float(stats["lifesteal_pct"])
	_lifesteal_val_lbl.text = "%.0f%%" % ls_pct
	_lifesteal_val_lbl.add_theme_color_override("font_color", _c(ls_pct))

	var dmg_bonus: float = float(stats["damage_bonus_pct"])
	_atk_val_lbl.text = "%s%.0f%%" % ["+" if dmg_bonus >= 0 else "", dmg_bonus]
	_atk_val_lbl.add_theme_color_override("font_color", _c(dmg_bonus))

	var melee_v: float = float(stats["melee_damage"])
	_melee_val_lbl.text = "%s%.0f" % ["+" if melee_v > 0 else "", melee_v]
	_melee_val_lbl.add_theme_color_override("font_color", _c(melee_v))

	var ranged_v: float = float(stats["ranged_damage"])
	_ranged_val_lbl.text = "%s%.0f" % ["+" if ranged_v > 0 else "", ranged_v]
	_ranged_val_lbl.add_theme_color_override("font_color", _c(ranged_v))

	var elem_v: float = float(stats["elemental_damage"])
	_elem_val_lbl.text = "%s%.0f" % ["+" if elem_v > 0 else "", elem_v]
	_elem_val_lbl.add_theme_color_override("font_color", _c(elem_v))

	var eng_v: float = float(stats["engineering_damage"])
	_eng_val_lbl.text = "%s%.0f" % ["+" if eng_v > 0 else "", eng_v]
	_eng_val_lbl.add_theme_color_override("font_color", _c(eng_v))

	var cdr: float = float(stats["cdr_pct"])
	_haste_val_lbl.text = "%s%.1f%%" % ["+" if cdr > 0 else "", cdr]
	_haste_val_lbl.add_theme_color_override("font_color", _c(cdr))

	var cr: float = float(stats["crit_rate_pct"])
	var cdmg: float = float(stats["crit_dmg_pct"]) / 100.0
	_crit_val_lbl.text = "%.0f%% (%.1f×)" % [cr, cdmg]
	_crit_val_lbl.add_theme_color_override("font_color", GameStyle.GOOD if cr > 5.0 or cdmg > 1.5 else GameStyle.PAPER)

	var rng_bonus: float = float(stats["attack_range_pct"])
	_range_val_lbl.text = "%s%.0f%%" % ["+" if rng_bonus >= 0 else "", rng_bonus]
	_range_val_lbl.add_theme_color_override("font_color", _c(rng_bonus))

	var arm: float = float(stats["armor"])
	_armor_val_lbl.text = "%.0f (减伤 %.0f%%)" % [arm, float(stats["dmg_reduction_pct"])]
	_armor_val_lbl.add_theme_color_override("font_color", _c(arm))

	var dodge_pct: float = float(stats["dodge_pct"])
	_dodge_val_lbl.text = "%.0f%%" % dodge_pct
	_dodge_val_lbl.add_theme_color_override("font_color", _c(dodge_pct))

	var spd_bonus: float = float(stats["move_speed_bonus_pct"])
	_speed_val_lbl.text = "%.0f (%s%.0f%%)" % [float(stats["move_speed"]), "+" if spd_bonus >= 0 else "", spd_bonus]
	_speed_val_lbl.add_theme_color_override("font_color", _c(spd_bonus))

	var luck_v: float = float(stats["luck"])
	_luck_val_lbl.text = "%s%.0f" % ["+" if luck_v > 0 else "", luck_v]
	_luck_val_lbl.add_theme_color_override("font_color", _c(luck_v))

	var harvest_v: float = float(stats["harvest"])
	_harvest_val_lbl.text = "%.0f (波末 +%d)" % [harvest_v, GameBalance.harvest_gain(harvest_v)]
	_harvest_val_lbl.add_theme_color_override("font_color", _c(harvest_v))

	# 2. 左侧次要属性刷新
	var pk_bonus: float = float(stats["pickup_bonus_pct"])
	_pickup_val_lbl.text = "%.0f (%s%.0f%%)" % [float(stats["pickup_radius"]), "+" if pk_bonus >= 0 else "", pk_bonus]
	_pickup_val_lbl.add_theme_color_override("font_color", _c(pk_bonus))

	var xp_pct: float = float(stats["xp_gain_pct"])
	_xp_gain_val_lbl.text = "%s%.0f%%" % ["+" if xp_pct >= 0 else "", xp_pct]
	_xp_gain_val_lbl.add_theme_color_override("font_color", _c(xp_pct))

	var elite_pct: float = float(stats["elite_damage_pct"])
	_elite_dmg_val_lbl.text = "%s%.0f%%" % ["+" if elite_pct >= 0 else "", elite_pct]
	_elite_dmg_val_lbl.add_theme_color_override("font_color", _c(elite_pct))

	var kb_pct: float = float(stats["knockback_pct"])
	_knockback_val_lbl.text = "%s%.0f%%" % ["+" if kb_pct >= 0 else "", kb_pct]
	_knockback_val_lbl.add_theme_color_override("font_color", _c(kb_pct))

	var pierce_v: int = int(stats["bonus_pierce"])
	_pierce_val_lbl.text = "%s%d" % ["+" if pierce_v > 0 else "", pierce_v]
	_pierce_val_lbl.add_theme_color_override("font_color", _c(float(pierce_v)))

	var sp_pct: float = float(stats["shop_price_pct"])
	_shop_price_val_lbl.text = "%s%.0f%%" % ["+" if sp_pct >= 0 else "", sp_pct]
	# 物价降低是好事（绿色），物价上涨是坏事（红色）
	_shop_price_val_lbl.add_theme_color_override("font_color", _c(-sp_pct))

	var fr_v: int = int(stats["free_rerolls"])
	_free_rerolls_val_lbl.text = "%d 次" % fr_v
	_free_rerolls_val_lbl.add_theme_color_override("font_color", _c(float(fr_v)))

	_stones_val_lbl.text = "%d 枚" % GameManager.spirit_stones
	_stones_val_lbl.add_theme_color_override("font_color", GameStyle.YELLOW if GameManager.spirit_stones > 0 else GameStyle.PAPER)

	_kills_val_lbl.text = "%d 妖" % GameManager.kills

	# 3. 右侧道统卡、法器、流派羁绊、法宝与历史刷新
	_refresh_cultivator()
	_refresh_weapons()
	_refresh_synergies()
	_refresh_items_and_history()

## 道统卡文案折行宽度预算：面板最小宽 900 − 外边距32 − 左栏296 − 分栏间距12 − 卡片内边距24 − 图标40 − 列距10 − 余量8
func _cult_text_width() -> float:
	var panel_w: float = maxf(900.0, get_viewport_rect().size.x)
	return panel_w - 32.0 - 296.0 - 12.0 - 24.0 - 40.0 - 10.0 - 8.0

func _refresh_cultivator() -> void:
	if _cult_card == null:
		return
	var def := CultivatorData.get_def(GameManager.cultivator_id)
	if def.is_empty():
		_cult_card.visible = false
		return
	_cult_card.visible = true
	if _cult_icon != null:
		var icon_path: String = String(def.get("icon", ""))
		_cult_icon.texture = load(icon_path) if not icon_path.is_empty() and ResourceLoader.exists(icon_path) else null
	if _cult_name_lbl != null:
		_cult_name_lbl.text = String(def.get("name", "未选道统"))
	if _cult_epi_lbl != null:
		_cult_epi_lbl.text = "「%s」" % String(def.get("epithet", ""))
	var w := _cult_text_width()
	var font := GameStyle.body_font()
	var pros: Array = def.get("pros", [])
	var cons: Array = def.get("cons", [])
	if _cult_pros_lbl != null:
		var pros_txt := "加成：" + "；".join(PackedStringArray(pros))
		_cult_pros_lbl.text = GameStyle.wrap_cjk(pros_txt, font, 11, w)
		_cult_pros_lbl.visible = not pros.is_empty()
	if _cult_cons_lbl != null:
		var cons_txt := "代偿：" + "；".join(PackedStringArray(cons))
		_cult_cons_lbl.text = GameStyle.wrap_cjk(cons_txt, font, 11, w)
		_cult_cons_lbl.visible = not cons.is_empty()

## 道统详解：正面加成、负面代偿、随行神通契合、开局自带与商店/加点限制
func _open_cultivator_tip(anchor: Control) -> void:
	var def := CultivatorData.get_def(GameManager.cultivator_id)
	if def.is_empty():
		return
	var rows: Array = []
	var pros: Array = def.get("pros", [])
	for i in range(pros.size()):
		rows.append(["加成 %d" % (i + 1), String(pros[i]), GameStyle.GOOD])
	var cons: Array = def.get("cons", [])
	for i in range(cons.size()):
		rows.append(["代偿 %d" % (i + 1), String(cons[i]), GameStyle.BAD])
	var skill_id := CultivatorData.get_synergy_skill_id(GameManager.cultivator_id)
	if not skill_id.is_empty():
		var sdef := SkillData.get_def(skill_id)
		var enh := SkillData.enhance_desc(skill_id, GameManager.cultivator_id)
		rows.append(["随行神通", "%s（%s）" % [String(sdef.get("name", skill_id)), enh if not enh.is_empty() else "无专属强化"], GameStyle.YELLOW])
	var start_equip := CultivatorData.get_start_equip(GameManager.cultivator_id)
	if not start_equip.is_empty():
		rows.append(["开局自带", start_equip, GameStyle.PAPER])

	var notes: Array[String] = []
	var allowed: Array = def.get("allowed_tags", [])
	if not allowed.is_empty():
		var tag_names: Array[String] = []
		for t in allowed:
			tag_names.append(String(WeaponData.SYNERGIES.get(String(t), {}).get("name", t)))
		notes.append("道统亲和：灵石阁大幅偏向「%s」系法器，仍有少量他派漏出。" % "、".join(tag_names))
	var locked: Array = def.get("locked_upgrades", [])
	if not locked.is_empty():
		var titles: Array[String] = []
		for uid in locked:
			titles.append(String(UpgradeData.get_upgrade_def(String(uid)).get("title", uid)))
		notes.append("加点锁死：「%s」与本道统无缘，悟道候选中不会出现。" % "、".join(titles))

	var tip := DetailTip.show_over(self, anchor, {
		"title": "%s · 道统特性" % String(def.get("name", "")),
		"chip": "道统",
		"chip_color": GameStyle.BLUE,
		"rows": rows,
		"body": "「%s」" % String(def.get("epithet", "")),
		"notes": notes,
		"foot": "加成与代偿开局即生效、全程不变；具体数值已计入左侧属性行与各条详解。",
	})
	_highlight_while_open(anchor, tip)

func _refresh_weapons() -> void:
	for child in _weapons_box.get_children():
		child.queue_free()
	for child in _stash_box.get_children():
		child.queue_free()

	var summary := GameManager.get_weapons_summary()
	var max_slots := GameManager.max_weapon_slots()
	if _wp_title_lbl != null:
		_wp_title_lbl.text = "✦ 上阵法器 (%d/%d)" % [summary.size(), max_slots]

	for i in range(WeaponData.MAX_SLOTS):
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(44, 44)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP

		var filled := i < summary.size()
		var locked := i >= max_slots
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

			# 吃「元素伤害」属性加成的法器挂橙红角标（判定与详情弹窗加成文案同源 stat_scalings）
			if WeaponData.elemental_scaling_coef(String(w.get("id", ""))) > 0.0:
				slot.add_child(GameStyle.element_badge(8))

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

			GameStyle.tap(slot, func() -> void: _open_weapon_tip(w, false, slot))
		else:
			var empty_dot := Label.new()
			empty_dot.text = "×" if locked else "·"
			empty_dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty_dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			GameStyle.label(empty_dot, 15, GameStyle.BAD if locked else GameStyle.GREY)
			slot.add_child(empty_dot)
			GameStyle.tap(slot, func() -> void: _open_empty_slot_tip(i, slot))

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

			# 吃「元素伤害」属性加成的法器挂橙红角标（仓库件与上阵件同一口径）
			if not def.is_empty() and WeaponData.elemental_scaling_coef(String(item.get("id", ""))) > 0.0:
				s_slot.add_child(GameStyle.element_badge(8))

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

			if not def.is_empty():
				s_slot.mouse_filter = Control.MOUSE_FILTER_STOP
				GameStyle.tap(s_slot, func() -> void: _open_weapon_tip(item, true, s_slot))
			_stash_box.add_child(s_slot)

## 流派羁绊阶梯卡片：仿《土豆兄弟》样式，直接展示 (2/6) 进度与各级加成激活情况
func _refresh_synergies() -> void:
	if _synergy_flow == null:
		return
	for child in _synergy_flow.get_children():
		child.queue_free()

	# 按已激活优先、持有数从高到低排列当前拥有的流派
	var tags: Array[String] = []
	for tag in GameManager.active_synergies.keys():
		var data: Dictionary = GameManager.active_synergies[tag]
		if int(data.get("count", 0)) > 0:
			tags.append(String(tag))

	tags.sort_custom(func(a: String, b: String) -> bool:
		var da: Dictionary = GameManager.active_synergies.get(a, {})
		var db: Dictionary = GameManager.active_synergies.get(b, {})
		var lva := int(da.get("level", 0))
		var lvb := int(db.get("level", 0))
		if lva != lvb:
			return lva > lvb
		return int(da.get("count", 0)) > int(db.get("count", 0))
	)

	if tags.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "当前尚未装备法器。装备同系（如剑系、离火）法器满 2 / 4 / 6 件即可触发阶梯共鸣加成。"
		GameStyle.label(empty_lbl, 12, GameStyle.GREY)
		_synergy_flow.add_child(empty_lbl)
		return

	for tag in tags:
		_synergy_flow.add_child(_create_synergy_card(tag))
	GameStyle.swipeable(_synergy_flow)

func _create_synergy_card(tag: String) -> Control:
	var info: Dictionary = WeaponData.SYNERGIES.get(tag, {})
	var data: Dictionary = GameManager.active_synergies.get(tag, {"count": 0, "level": 0})
	var n: int = int(data.get("count", 0))
	var lv: int = int(data.get("level", 0))
	var raw_th: Array = info.get("thresholds", [2, 4, 6])
	var shift: int = GameManager.spirit_threshold_adj if tag == "spirit" else 0
	var max_th: int = maxi(1, int(raw_th[raw_th.size() - 1]) - shift)
	var is_elem: bool = tag in WeaponData.ELEMENTS

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(168, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var border_col: Color = (GameStyle.YELLOW if is_elem else GameStyle.BLUE) if lv > 0 else GameStyle.LINE
	var bg_col: Color = GameStyle.NAVY if lv > 0 else Color(0.07, 0.10, 0.18, 0.78)
	var sb_flat := GameStyle.outlined_panel(bg_col, border_col, 2 if lv > 0 else 1, 0.0)
	sb_flat.content_margin_left = 8.0
	sb_flat.content_margin_top = 5.0
	sb_flat.content_margin_right = 8.0
	sb_flat.content_margin_bottom = 5.0
	var sb_on := GameStyle.outlined_panel(bg_col.lightened(0.08), GameStyle.YELLOW, 2, 0.0)
	sb_on.content_margin_left = 8.0
	sb_on.content_margin_top = 5.0
	sb_on.content_margin_right = 8.0
	sb_on.content_margin_bottom = 5.0
	card.add_theme_stylebox_override("panel", sb_flat)
	card.set_meta("sb_flat", sb_flat)
	card.set_meta("sb_on", sb_on)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vbox)

	# 顶部标题行：如「剑系 (2/6)」或「离火 (3/6)」
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(head)

	var kind_lbl := Label.new()
	kind_lbl.text = "五行" if is_elem else "器类"
	GameStyle.label(kind_lbl, 10, GameStyle.YELLOW if is_elem else GameStyle.BLUE_EDGE)
	head.add_child(kind_lbl)

	var title_lbl := Label.new()
	title_lbl.text = "%s (%d/%d)" % [info.get("name", tag), n, max_th]
	var title_col: Color = (GameStyle.YELLOW if is_elem else GameStyle.PAPER) if lv > 0 else GameStyle.PAPER_DIM
	GameStyle.label(title_lbl, 13, title_col)
	head.add_child(title_lbl)

	# 展开 3 档阶梯加成（参照土豆兄弟：(2) +15% 范围，达成的高亮，未达成的置灰）
	var tier_lines: Array = SYNERGY_TIER_LINES.get(tag, [])
	for idx in range(raw_th.size()):
		var th_need: int = maxi(1, int(raw_th[idx]) - shift)
		var tier_txt: String = String(tier_lines[idx]) if idx < tier_lines.size() else String(info.get("desc", ""))
		var reached: bool = n >= th_need
		var is_current_tier: bool = (lv == idx + 1)
		var line_lbl := Label.new()
		var prefix: String = "★" if is_current_tier else ("·" if not reached else "+")
		line_lbl.text = "%s(%d) %s" % [prefix, th_need, tier_txt]
		var line_col: Color = GameStyle.GOOD if is_current_tier else (GameStyle.PAPER_DIM if reached else GameStyle.GREY)
		GameStyle.label(line_lbl, 11, line_col)
		vbox.add_child(line_lbl)

	GameStyle.tap(card, func() -> void: _open_synergy_tip(tag, card))
	return card

func _open_synergy_tip(tag: String, anchor: Control) -> void:
	var info: Dictionary = WeaponData.SYNERGIES.get(tag, {})
	if info.is_empty():
		return
	var data: Dictionary = GameManager.active_synergies.get(tag, {"count": 0, "level": 0})
	var n: int = int(data.get("count", 0))
	var lv: int = int(data.get("level", 0))
	var raw_th: Array = info.get("thresholds", [2, 4, 6])
	var shift: int = GameManager.spirit_threshold_adj if tag == "spirit" else 0
	var max_th: int = maxi(1, int(raw_th[raw_th.size() - 1]) - shift)
	var first_th: int = maxi(1, int(raw_th[0]) - shift)

	var rows: Array = [
		["当前装备", "%d / %d 件" % [n, max_th], GameStyle.YELLOW if lv > 0 else GameStyle.PAPER],
		["共鸣状态", "已达成第 %d 档" % lv if lv > 0 else "未激活 (差 %d 件)" % maxi(1, first_th - n), GameStyle.GOOD if lv > 0 else GameStyle.GREY],
	]
	var tier_lines: Array = SYNERGY_TIER_LINES.get(tag, [])
	for idx in range(raw_th.size()):
		var th_need: int = maxi(1, int(raw_th[idx]) - shift)
		var tier_txt: String = String(tier_lines[idx]) if idx < tier_lines.size() else ""
		var reached: bool = n >= th_need
		rows.append([
			"(%d/%d) 阶梯" % [th_need, max_th],
			tier_txt,
			GameStyle.GOOD if lv == idx + 1 else (GameStyle.PAPER_DIM if reached else GameStyle.GREY)
		])

	var match_weapons: Array[String] = []
	for wid in WeaponData.DEFS.keys():
		if tag in WeaponData.tags_of(wid):
			match_weapons.append(String(WeaponData.get_def(wid).get("name", wid)))

	var notes: Array[String] = [
		"上阵同系法器（含同名多把）达到门槛件数即自动激活对应阶梯。",
		"本流派法器：" + "、".join(match_weapons) + "。",
	]
	var tip := DetailTip.show_over(self, anchor, {
		"title": "%s (%d/%d)" % [info.get("name", tag), n, max_th],
		"chip": "五行共鸣" if tag in WeaponData.ELEMENTS else "器类羁绊",
		"chip_color": GameStyle.YELLOW if tag in WeaponData.ELEMENTS else GameStyle.BLUE,
		"rows": rows,
		"body": "流派总加成：" + String(info.get("desc", "")),
		"notes": notes,
		"foot": "纳戒仓库中的备用法器不计入上阵数量。",
	})
	_highlight_while_open(anchor, tip)

func _refresh_items_and_history() -> void:
	for child in _items_flow.get_children():
		child.queue_free()
	for child in _history_list.get_children():
		child.queue_free()

	var item_list := GameManager.items
	var history := GameManager.upgrade_history
	if _bottom_tab_items_btn != null:
		_bottom_tab_items_btn.text = "✦ 随身法宝 (%d)" % item_list.size()
	if _bottom_tab_hist_btn != null:
		_bottom_tab_hist_btn.text = "✦ 悟道历程 (%d)" % history.size()

	# 若法宝为空但已有悟道记录，自动展示悟道历程避免空面板；反之有法宝时优先展示法宝
	if item_list.is_empty() and not history.is_empty() and _current_bottom_tab == 0:
		_switch_bottom_tab(1)

	# 1. 填充随身法宝
	if item_list.is_empty():
		var empty_item_lbl := Label.new()
		empty_item_lbl.text = "尚未购入随身法宝。在波间灵石阁可购置各类被动奇珍。"
		GameStyle.label(empty_item_lbl, 12, GameStyle.GREY)
		_items_flow.add_child(empty_item_lbl)
	else:
		# 合并同名法宝计数展示，如「聚宝盆 ×2」
		var counts: Dictionary = {}
		var order: Array[String] = []
		for raw_id in item_list:
			var iid := String(raw_id)
			if not counts.has(iid):
				counts[iid] = 0
				order.append(iid)
			counts[iid] = int(counts[iid]) + 1
		for iid in order:
			_items_flow.add_child(_create_item_badge(iid, int(counts[iid])))
		GameStyle.swipeable(_items_flow)

	# 2. 填充历史悟道记录
	if history.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "尚未有悟道加成，每波平息后可根据境界提升领悟天地法则。"
		GameStyle.label(empty_lbl, 12, GameStyle.GREY)
		_history_list.add_child(empty_lbl)
		return

	for i in range(history.size()):
		var item: Dictionary = history[i]
		var row := _create_history_row(item, i + 1)
		_history_list.add_child(row)
	GameStyle.swipeable(_history_list)

func _create_item_badge(item_id: String, count: int) -> Control:
	var def := ItemData.get_def(item_id)
	var tier_num: int = int(def.get("tier", 1))
	var tier_col: Color = ItemData.tier_color(tier_num)

	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(126, 40)
	badge.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb_off := GameStyle.outlined_panel(GameStyle.NAVY2, tier_col, 2, 0.0)
	sb_off.content_margin_left = 6.0
	sb_off.content_margin_top = 4.0
	sb_off.content_margin_right = 8.0
	sb_off.content_margin_bottom = 4.0
	var sb_on := GameStyle.outlined_panel(GameStyle.NAVY2.lightened(0.1), GameStyle.YELLOW, 2, 0.0)
	sb_on.content_margin_left = 6.0
	sb_on.content_margin_top = 4.0
	sb_on.content_margin_right = 8.0
	sb_on.content_margin_bottom = 4.0
	badge.add_theme_stylebox_override("panel", sb_off)
	badge.set_meta("sb_flat", sb_off)
	badge.set_meta("sb_on", sb_on)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(hbox)

	var icon_path: String = def.get("icon", "")
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		var tex := TextureRect.new()
		tex.texture = load(icon_path)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.custom_minimum_size = Vector2(28, 28)
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(tex)

	var name_lbl := Label.new()
	var name_str: String = String(def.get("name", item_id))
	name_lbl.text = "%s ×%d" % [name_str, count] if count > 1 else name_str
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	GameStyle.label(name_lbl, 12, GameStyle.PAPER)
	hbox.add_child(name_lbl)

	GameStyle.tap(badge, func() -> void: _open_item_tip(item_id, count, badge))
	return badge

func _open_item_tip(item_id: String, count: int, anchor: Control) -> void:
	var def := ItemData.get_def(item_id)
	if def.is_empty():
		return
	var tier_num: int = int(def.get("tier", 1))
	var tier_col: Color = ItemData.tier_color(tier_num)
	var rows: Array = [
		["品阶", ItemData.tier_label(tier_num), tier_col],
		["当前持有", "%d 件" % count, GameStyle.YELLOW],
	]
	var apply: Dictionary = def.get("apply", {})
	for key in apply.keys():
		var k := String(key)
		var v := float(apply[key])
		rows.append([StatInfoData.field_name(k), StatInfoData.format_amount(k, v), _c(v)])

	var desc_lines: Array = String(def.get("desc", "")).split("\n")
	var notes: Array[String] = [
		"本命法宝：购入即永久生效，不占用上阵法器槽位。",
	]
	for line in desc_lines:
		var s := String(line).strip_edges()
		if not s.is_empty():
			notes.append(s)

	var tip := DetailTip.show_over(self, anchor, {
		"title": String(def.get("name", item_id)),
		"chip": "%s法宝" % ItemData.tier_label(tier_num),
		"chip_color": tier_col,
		"rows": rows,
		"body": "法宝奇珍：属性加成与悟道同源叠加。",
		"notes": notes,
		"foot": "在波间灵石阁可继续购置更多奇珍。",
	})
	_highlight_while_open(anchor, tip)

func _create_history_row(item: Dictionary, idx: int) -> Control:
	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var r_style := StyleBoxFlat.new()
	r_style.bg_color = Color(0.08, 0.11, 0.19, 0.8)
	r_style.border_width_left = 2
	r_style.border_color = item.get("border_color", GameStyle.PAPER_DIM)
	r_style.content_margin_left = 8.0
	r_style.content_margin_top = 3.0
	r_style.content_margin_right = 8.0
	r_style.content_margin_bottom = 3.0
	row.add_theme_stylebox_override("panel", r_style)
	var r_on := r_style.duplicate() as StyleBoxFlat
	r_on.bg_color = Color(0.16, 0.22, 0.36, 0.95)
	r_on.border_width_left = 4
	row.set_meta("sb_flat", r_style)
	row.set_meta("sb_on", r_on)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	GameStyle.tap(row, func() -> void: _open_history_tip(item, idx, row))

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	row.add_child(hbox)

	var num_lbl := Label.new()
	num_lbl.text = "%02d." % idx
	GameStyle.label(num_lbl, 11, GameStyle.GREY)
	hbox.add_child(num_lbl)

	if item.has("icon") and ResourceLoader.exists(item["icon"]):
		var tex := TextureRect.new()
		tex.texture = load(item["icon"])
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.custom_minimum_size = Vector2(20, 20)
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(tex)

	var pill := Label.new()
	pill.text = " " + item.get("rarity_label", "凡品") + " "
	GameStyle.label(pill, 10, GameStyle.PAPER)
	var col: Color = item.get("border_color", GameStyle.PAPER)
	var pill_sb := GameStyle.block(col, GameStyle.SLANT_BAND, Vector2(1, 1))
	pill_sb.content_margin_top = 1.0
	pill_sb.content_margin_bottom = 1.0
	pill.add_theme_stylebox_override("normal", pill_sb)
	var band_text_col: Color = GameStyle.INK_TEXT if col.get_luminance() > 0.5 else GameStyle.PAPER
	pill.add_theme_color_override("font_color", band_text_col)
	hbox.add_child(pill)

	var title_lbl := Label.new()
	var count_text: String = " (第%d次)" % item.get("count", 1) if item.get("count", 1) > 1 else ""
	title_lbl.text = str(item.get("title", "")) + count_text
	GameStyle.label(title_lbl, 12, GameStyle.PAPER)
	hbox.add_child(title_lbl)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(sp)

	var lvl_lbl := Label.new()
	lvl_lbl.text = "Lv.%d" % int(item.get("level", 1))
	GameStyle.label(lvl_lbl, 11, GameStyle.YELLOW)
	hbox.add_child(lvl_lbl)

	return row

# ============================ 点按详解 ============================

func _fit_panel_height() -> float:
	var vp := get_viewport_rect().size
	if vp.y <= 0.0:
		return 516.0
	return clampf(vp.y - 14.0, 380.0, 516.0)

func _open_stat_tip(id: String, anchor: Control) -> void:
	if not StatInfoData.has(id):
		return
	# 若点按的条目属于隐藏的 Tab（例如自动化测试全扫 25 项），自动切过去使其具有真实屏幕坐标
	if id in StatInfoData.SECONDARY_IDS and _current_stat_tab != 1:
		_switch_stat_tab(1)
	elif id in StatInfoData.PRIMARY_IDS and id != "hp" and _current_stat_tab != 0:
		_switch_stat_tab(0)

	var tip := DetailTip.show_over(self, anchor, {
		"title": StatInfoData.title(id),
		"rows": _stat_tip_rows(id),
		"body": StatInfoData.brief(id),
		"notes": StatInfoData.rules(id),
		"foot": _stat_tip_foot(id),
	})
	_highlight_while_open(anchor, tip)

## 来源拆解：覆盖全部 25 项主要与次要属性
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
				["御灵羁绊", "+%.0f" % GameManager.synergy_max_hp_bonus, _c(GameManager.synergy_max_hp_bonus)],
				["道统", _cultivator_name()],
			]
		"regen":
			var rate: float = float(s.get("hp_regen", 0.0))
			var need: float = float(s.get("max_hp", 0.0)) - float(s.get("current_hp", 0.0))
			rows = [
				["每秒回复", "%.1f / 秒" % rate],
				["悟道·法宝·道统", "%.1f" % GameManager.hp_regen, _c(GameManager.hp_regen)],
				["青木羁绊", "+%.1f" % GameManager.synergy_hp_regen, _c(GameManager.synergy_hp_regen)],
				["回满已损需要", "%.1f 秒" % (need / rate) if rate > 0.0 and need > 0.0 else "—"],
			]
		"armor":
			var arm: float = float(s.get("armor", 0.0))
			var nxt: float = GameBalance.armor_reduction(arm + 1.0) * 100.0
			rows = [
				["护甲合计", "%.0f 点" % arm],
				["悟道·法宝·道统", "%+.0f" % GameManager.armor, _c(GameManager.armor)],
				["厚土羁绊", "%+.0f" % GameManager.synergy_armor, _c(GameManager.synergy_armor)],
				["当前减伤", "%.1f%%" % float(s.get("dmg_reduction_pct", 0.0)), _c(arm)],
				["再加 1 点", "+%.1f%%" % (nxt - float(s.get("dmg_reduction_pct", 0.0))), GameStyle.GOOD],
			]
		"dodge":
			var dg: float = float(s.get("dodge_pct", 0.0))
			var cap: float = (GameManager.DODGE_CAP + GameManager.dodge_cap_bonus) * 100.0
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
				["青木羁绊", "+%.0f%%" % (GameManager.synergy_lifesteal * 100.0), _c(GameManager.synergy_lifesteal)],
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
		"melee_dmg":
			var mv: float = float(s.get("melee_damage", 0.0))
			rows = [
				["近战伤害加成", "%+.0f" % mv, _c(mv)],
				["受益法器", "青云剑 / 赤焰斩马刀 / 青木藤鞭 / 芭蕉扇"],
				["星级放大", "每升 1 星转化效率 +25%"],
			]
		"ranged_dmg":
			var rv: float = float(s.get("ranged_damage", 0.0))
			rows = [
				["远程伤害加成", "%+.0f" % rv, _c(rv)],
				["受益法器", "庚金飞剑 / 柳叶飞刀 / 万木灵符 / 玄冰飞针 / 火焰符"],
				["星级放大", "每升 1 星转化效率 +25%"],
			]
		"elemental_dmg":
			var ev: float = float(s.get("elemental_damage", 0.0))
			rows = [
				["元素伤害加成", "%+.0f" % ev, _c(ev)],
				["离火灼烧倍率", _mul(GameManager.synergy_burn_mult), _c(GameManager.synergy_burn_mult - 1.0)],
				["受益法器", "火焰符 / 赤焰斩马刀 / 焚天宝灯 / 五雷法牌 / 番天印等"],
			]
		"engineering_dmg":
			var gv: float = float(s.get("engineering_damage", 0.0))
			rows = [
				["御灵伤害加成", "%+.0f" % gv, _c(gv)],
				["当前护体灵宝", "%d 尊" % GameManager.drones.size()],
				["受益灵宝", "灵蝶 / 寒泉玉莲 / 混元古钟"],
			]
		"haste":
			rows = [
				["间隔缩减", "%.1f%%" % float(s.get("cdr_pct", 0.0)), _c(float(s.get("cdr_pct", 0.0)))],
				["实际攻击间隔", _mul(float(s.get("attack_speed_mult", 1.0)))],
				["悟道·法宝·道统", _mul(GameManager.attack_speed_mult), _c(1.0 - GameManager.attack_speed_mult)],
				["雷法·玄水羁绊", _mul(GameManager.synergy_haste_mult), _c(1.0 - GameManager.synergy_haste_mult)],
				["间隔下限", _mul(GameManager.ATTACK_SPEED_FLOOR), GameStyle.GREY],
			]
		"speed":
			var eff: float = GameManager.move_speed_mult + GameManager.synergy_move_speed_mult
			var spd: float = float(s.get("move_speed", 0.0))
			rows = [
				["实际移速", "%.0f" % spd],
				["道统基础", "%.0f" % (spd / eff if eff > 0.01 else spd)],
				["悟道·法宝·道统", "%+.0f%%" % ((GameManager.move_speed_mult - 1.0) * 100.0), _c(GameManager.move_speed_mult - 1.0)],
				["玄水羁绊", "%+.0f%%" % (GameManager.synergy_move_speed_mult * 100.0), _c(GameManager.synergy_move_speed_mult)],
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
				["剑系羁绊", _mul(GameManager.synergy_range_mult), _c(GameManager.synergy_range_mult - 1.0)],
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
		"xp_gain":
			var xp_p: float = float(s.get("xp_gain_pct", 0.0))
			rows = [
				["修为获取倍率", _mul(GameManager.xp_gain_mult), _c(xp_p)],
				["折算加成", "%+.0f%%" % xp_p, _c(xp_p)],
				["当前升级门槛", "%d / %d" % [GameManager.experience, GameManager.experience_to_next]],
			]
		"shop_price":
			var sp_p: float = float(s.get("shop_price_pct", 0.0))
			rows = [
				["灵石阁物价系数", _mul(GameManager.shop_price_mult), _c(-sp_p)],
				["折算幅度", "%+.0f%%" % sp_p, _c(-sp_p)],
			]
		"bonus_pierce":
			var bp: int = int(s.get("bonus_pierce", 0))
			rows = [
				["额外穿透人数", "+%d" % bp, _c(float(bp))],
				["来源", "符箓羁绊 (2/4/6 件分别 +1/+2/+3)"],
			]
		"elite_dmg":
			var ep: float = float(s.get("elite_damage_pct", 0.0))
			rows = [
				["对精英/Boss增伤", "%+.0f%%" % ep, _c(ep)],
				["独立乘区", _mul(1.0 + GameManager.elite_damage), _c(ep)],
			]
		"knockback":
			var kp: float = float(s.get("knockback_pct", 0.0))
			rows = [
				["击退总倍率", _mul(GameManager.knockback_mult * GameManager.synergy_knockback_mult), _c(kp)],
				["悟道·法宝", _mul(GameManager.knockback_mult), _c(GameManager.knockback_mult - 1.0)],
				["厚土羁绊", _mul(GameManager.synergy_knockback_mult), _c(GameManager.synergy_knockback_mult - 1.0)],
			]
		"free_rerolls":
			var fr: int = int(s.get("free_rerolls", 0))
			rows = [
				["每波免费重掷", "%d 次" % fr, _c(float(fr))],
				["本波剩余免费", "%d 次" % GameManager.reroll_free_left],
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

func _open_empty_slot_tip(index: int, anchor: Control) -> void:
	var max_slots := GameManager.max_weapon_slots()
	var locked := index >= max_slots
	var tip := DetailTip.show_over(self, anchor, {
		"title": "封印法器位" if locked else "空法器位",
		"rows": [
			["上阵位", "第 %d 槽 / 上限 %d 槽" % [index + 1, max_slots]],
			["当前上阵", "%d 件" % GameManager.get_weapons_summary().size()],
			["纳戒仓库", "%d 件" % GameManager.stash.size()],
		],
		"body": "本道统限制了上阵法器槽上限，此槽位不可装备。" if locked else "这一格还空着。法器按获得顺序自动补上阵法器位，不需要手动摆。",
		"notes": [
			"上阵 %d 格全满之后，新买的法器进纳戒仓库，只用于合成与出售。" % max_slots,
			"上阵法器的数量（如 2/6、4/6、6/6）决定流派羁绊的激活档位。",
		],
		"foot": "波间在灵石阁买法器即可补上空槽。",
	})
	_highlight_while_open(anchor, tip)

## 法器详情：同时展示所属流派当前的 (n/6) 进度
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
	# 攻击范围：与其他行同口径显示最终生效值（词条 + 剑系羁绊乘区），有加成时附基础值
	var base_range: float = float(def.get("range", 0.0))
	var eff_range: float = base_range * GameManager.attack_range_mult * GameManager.synergy_range_mult
	var range_buffed: bool = not is_equal_approx(eff_range, base_range)
	var range_txt: String = "%.0f" % eff_range
	if range_buffed:
		range_txt = "%.0f（基础 %.0f）" % [eff_range, base_range]

	var syn_parts: Array[String] = []
	for t in def.get("tags", []):
		var sinfo: Dictionary = WeaponData.SYNERGIES.get(t, {})
		if not sinfo.is_empty():
			var cnt: int = GameManager.get_tag_count(String(t))
			syn_parts.append("%s(%d/6)" % [sinfo.get("name", t), cnt])

	var rows: Array = [
		["单发伤害", "%.1f" % per_hit, GameStyle.YELLOW],
		["流派进度", " · ".join(syn_parts) if not syn_parts.is_empty() else "—", GameStyle.GOOD],
		["基础 × 星级", "%.0f × %.1f" % [base_dmg, star_mul]],
		["属性转化", "+%.1f" % bonus, _c(bonus)],
		["全局×羁绊", "%s × %s" % [_mul(gm_dmg), _mul(syn_dmg)], _c(gm_dmg * syn_dmg - 1.0)],
		["道统×五行", "%s × %s" % [_mul(cult_dmg), _mul(elem_dmg)], _c(cult_dmg * elem_dmg - 1.0)],
		["攻击范围", range_txt, GameStyle.YELLOW if range_buffed else GameStyle.PAPER],
		["攻击间隔", "%.2f 秒" % cd],
	]
	var feats := _weapon_feats(def)
	if not feats.is_empty():
		rows.append(["特性", feats])

	var notes: Array[String] = [
		"单发伤害 =（基础 × 星级 + 属性转化）× 全局法伤 × 流派羁绊 × 道统 × 五行；暴击另按 %.0f%% 概率 ×%.2f 结算。" % [
			GameManager.get_crit_rate() * 100.0, GameManager.crit_mult + GameManager.synergy_crit_mult],
		"%s（每星效率 +25%%）。" % WeaponData.scaling_desc(id),
		"升星：同名同星集满 3 件在灵石阁合成，伤害 ×%s、攻击间隔 ×%s，最高 %s。" % [
			_num(WeaponData.STAR_DAMAGE_MULT), _num(WeaponData.STAR_COOLDOWN_MULT), WeaponData.star_text(WeaponData.MAX_STAR)],
	]

	var foot := "同名同星 %d 件 · 出售可得 %d 枚" % [
		GameManager.count_copies(id, star), WeaponData.sell_price(id, star)]
	if from_stash:
		foot += "\n在纳戒仓库里：未上阵、不出手、不吃羁绊，只用于合成与出售。"

	var tip := DetailTip.show_over(self, anchor, {
		"title": "%s %s" % [String(def.get("name", "法器")), WeaponData.star_text(star)],
		"chip": " · ".join(syn_parts) if not syn_parts.is_empty() else String(def.get("tag", "")),
		"chip_color": GameStyle.YELLOW_DK if from_stash else GameStyle.BLUE_DK,
		"rows": rows,
		"body": String(def.get("desc", "")),
		"notes": notes,
		"foot": foot,
	})
	_highlight_while_open(anchor, tip)

func _weapon_feats(def: Dictionary) -> String:
	var out: Array[String] = []
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

func _open_history_tip(item: Dictionary, idx: int, anchor: Control) -> void:
	if _current_bottom_tab != 1:
		_switch_bottom_tab(1)
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

## 语义色：正收益绿、负收益红、没动过白/灰
func _c(v: float) -> Color:
	if v > 0.0001:
		return GameStyle.GOOD
	if v < -0.0001:
		return GameStyle.BAD
	return GameStyle.PAPER

func _mul(v: float) -> String:
	return "×%.2f" % v

func _num(v: float) -> String:
	if absf(v - roundf(v)) < 0.0001:
		return "%d" % int(roundf(v))
	return "%.2f" % v
