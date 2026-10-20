class_name CultivatorSelect
extends Control

## 开局道统择选（左右分栏 Master-Detail 架构）：
## - 左侧部分：当前选中角色的详解大卡片（固定高度、内容平滑滚动）
##   * 顶部：形象大头像、名号、称号、通关勋章
##   * 中部：滚动特性区（初始装备、独门天赋、额外技能、背负代价、契合技能）
##     精炼排版，默认纸白，仅在数值与专属机制处精准高亮（增益绿、代偿红、机制金）
##   * 底部：固定吸底的主行动按钮（选择此角色 / 解锁条件）
## - 右侧部分：全部角色的形象小卡片纵向双列网格（40x40头像、名号、称号、通关勋章），上下平滑滚动
## 流程：StartMenu → CultivatorSelect → SkillSelect → StartWeaponSelect（全程保持 paused）

const EDGE := 20.0          # 左右屏边留白
const TOP_MARGIN := 10.0
const BOTTOM_MARGIN := 10.0
const DETAIL_PAD_X := 12.0  # 详情大卡片左右内边距
const DETAIL_PAD_Y := 10.0  # 详情大卡片上下内边距
const ROW_PAD_X := 8.0      # 特性条目卡左右内边距
const TAG_CHIP_W := 52.0    # 特性条目卡左侧分类色签宽
const ROW_GAP := 8.0        # 分类色签与正文间距
const BORDER_RESERVE := 8.0 # 外层边框安全余量
const TXT := 12             # 特性正文字号
const ROSTER_GAP := 6.0     # 右侧小卡片网格间距
const SMALL_CARD_H := 56.0  # 右侧形象小卡片高度
const CONTENT_GAP := 12.0   # 左右栏间距

var _title_label: Label
var _sub_label: Label
var _progress_label: Label
var _content_hbox: HBoxContainer
var _detail_panel: PanelContainer
var _detail_content: VBoxContainer
var _roster_panel: PanelContainer
var _roster_scroll: ScrollContainer
var _roster_grid: GridContainer
var _selected_id: String = "jianchi"
var _transitioning: bool = false
var _roster_cards: Dictionary = {}
var _cached_roster_w: float = -1.0
var _detail_pview: ProceduralCultivatorView = null  ## 详情卡大头像（皮肤切换实时预览用）
var _skin_row: Control = null                     ## 详情卡皮肤切换栏（点选皮肤后局部重建用）

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = GameStyle.dim_overlay(0.90)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", int(EDGE))
	margin.add_theme_constant_override("margin_right", int(EDGE))
	margin.add_theme_constant_override("margin_top", int(TOP_MARGIN))
	margin.add_theme_constant_override("margin_bottom", int(BOTTOM_MARGIN))
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vbox)

	# 1. 顶部导航栏：左返回按钮 + 居中标题与副标 + 右侧收集进度徽章
	var header_row := HBoxContainer.new()
	header_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(header_row)

	var back_btn := Button.new()
	back_btn.text = "〈 返 回"
	back_btn.custom_minimum_size = Vector2(84, 32)
	back_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	back_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(back_btn, GameStyle.NAVY2, GameStyle.JADE, 13, GameStyle.PAPER, 5.0, GameStyle.INK_TEXT)
	back_btn.pressed.connect(_on_back_pressed)
	header_row.add_child(back_btn)

	var l_spacer := Control.new()
	l_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(l_spacer)

	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 1)
	title_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(title_box)

	_title_label = Label.new()
	_title_label.text = "选 择 角 色"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_box.add_child(_title_label)
	GameStyle.label(_title_label, 20, GameStyle.CHALK, 0, GameStyle.INK, true)

	_sub_label = Label.new()
	_sub_label.text = "点选右侧角色预览 · 确认天赋与代价后出战"
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_box.add_child(_sub_label)
	GameStyle.label(_sub_label, 11, GameStyle.with_alpha(GameStyle.CHALK, 0.75))

	var r_spacer := Control.new()
	r_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(r_spacer)

	_progress_label = Label.new()
	_progress_label.custom_minimum_size = Vector2(104, 30)
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_progress_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_progress_label.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.GOLD))
	GameStyle.label(_progress_label, 11, GameStyle.INK_TEXT)
	header_row.add_child(_progress_label)

	# 2. 主体左右分栏
	_content_hbox = HBoxContainer.new()
	_content_hbox.add_theme_constant_override("separation", int(CONTENT_GAP))
	_content_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_content_hbox)

	# 2.1 左侧：固定高度详情大卡片（Master-Detail 左侧）
	_detail_panel = PanelContainer.new()
	_detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_panel.size_flags_stretch_ratio = 1.35
	_detail_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_content_hbox.add_child(_detail_panel)

	var detail_margin := MarginContainer.new()
	detail_margin.add_theme_constant_override("margin_left", int(DETAIL_PAD_X))
	detail_margin.add_theme_constant_override("margin_right", int(DETAIL_PAD_X))
	detail_margin.add_theme_constant_override("margin_top", int(DETAIL_PAD_Y))
	detail_margin.add_theme_constant_override("margin_bottom", int(DETAIL_PAD_Y))
	detail_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_panel.add_child(detail_margin)

	_detail_content = VBoxContainer.new()
	_detail_content.add_theme_constant_override("separation", 8)
	_detail_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_margin.add_child(_detail_content)

	# 2.2 右侧：全部角色纵向网格列表
	_roster_panel = PanelContainer.new()
	_roster_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_roster_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_roster_panel.size_flags_stretch_ratio = 1.0
	_roster_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var r_style := GameStyle.card(GameStyle.LINE, GameStyle.SLANT_PLATE, Vector2(3, 4))
	r_style.bg_color = GameStyle.NAVY2.darkened(0.2)
	_roster_panel.add_theme_stylebox_override("panel", r_style)
	_content_hbox.add_child(_roster_panel)

	var roster_margin := MarginContainer.new()
	roster_margin.add_theme_constant_override("margin_left", 8)
	roster_margin.add_theme_constant_override("margin_right", 8)
	roster_margin.add_theme_constant_override("margin_top", 8)
	roster_margin.add_theme_constant_override("margin_bottom", 8)
	roster_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_roster_panel.add_child(roster_margin)

	_roster_scroll = ScrollContainer.new()
	_roster_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_roster_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_roster_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	GameStyle.scrollable(_roster_scroll)
	roster_margin.add_child(_roster_scroll)

	_roster_grid = GridContainer.new()
	_roster_grid.columns = 2
	_roster_grid.add_theme_constant_override("h_separation", int(ROSTER_GAP))
	_roster_grid.add_theme_constant_override("v_separation", int(ROSTER_GAP))
	_roster_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_roster_grid.mouse_filter = Control.MOUSE_FILTER_PASS
	_roster_scroll.add_child(_roster_grid)

func show_select() -> void:
	_transitioning = false
	var parent_node = get_parent()
	if parent_node != null:
		var backdrop = parent_node.get_node_or_null("StageBackdrop")
		if backdrop != null:
			backdrop.visible = true
	var ids: Array = CultivatorData.all_ids()
	if not GameManager.cultivator_id.is_empty() and GameManager.cultivator_id in ids:
		_selected_id = GameManager.cultivator_id
	elif not (_selected_id in ids):
		_selected_id = String(ids[0]) if not ids.is_empty() else "jianchi"
	_rebuild_all()
	visible = true
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.22)

## 左右布局下：左侧详情卡内特性列的可用文字宽。
## 纯函数 ⇒ LayoutCheck 直接调用它做全表文案折行校验，不另抄算术。
static func text_col_w(vis_w: float) -> float:
	var avail_w := vis_w - EDGE * 2.0 - CONTENT_GAP
	var left_w := floorf(avail_w * (1.35 / (1.35 + 1.0)))
	var inner_w := left_w - DETAIL_PAD_X * 2.0
	var txt_w := inner_w - ROW_PAD_X * 2.0 - TAG_CHIP_W - ROW_GAP - BORDER_RESERVE
	return maxf(160.0, txt_w)

## 左右布局下：右侧网格中每张形象小卡片的内部可用文字宽（双列纵向排布）
static func small_card_inner_w(vis_w: float, _count: int = 15) -> float:
	var avail_w := vis_w - EDGE * 2.0 - CONTENT_GAP
	var left_w := floorf(avail_w * (1.35 / (1.35 + 1.0)))
	var right_w := avail_w - left_w
	var grid_w := right_w - 16.0 - 6.0 # 扣除右卡边距与滚动条余量
	var card_w := floorf((grid_w - ROSTER_GAP) / 2.0)
	return maxf(48.0, card_w - 56.0) # 扣除 40x40 头像与边距

func _select_cultivator(cid: String) -> void:
	if _transitioning or cid == _selected_id:
		return
	AudioManager.play_sfx("ui_click")
	var old_id := _selected_id
	_selected_id = cid
	var vis_w := get_viewport().get_visible_rect().size.x
	if vis_w <= 0.0:
		vis_w = 960.0
	_rebuild_detail_card(_selected_id, vis_w)
	_update_small_card_selection(old_id)
	_update_small_card_selection(_selected_id)

func _rebuild_all() -> void:
	var vis_w := get_viewport().get_visible_rect().size.x
	if vis_w <= 0.0:
		vis_w = 960.0

	var ids: Array = CultivatorData.all_ids()
	var unlocked_count := 0
	for cid in ids:
		if GameManager.is_cultivator_unlocked(String(cid)):
			unlocked_count += 1
	_progress_label.text = " 已解锁 %d/%d " % [unlocked_count, ids.size()]

	_rebuild_detail_card(_selected_id, vis_w)
	_rebuild_roster_cards(vis_w)

# ---------------- 左侧：角色详情大卡片 ----------------

func _rebuild_detail_card(cid: String, vis_w: float) -> void:
	for child in _detail_content.get_children():
		child.queue_free()
	_detail_pview = null
	_skin_row = null

	var def: Dictionary = CultivatorData.get_def(cid)
	var is_unlocked: bool = GameManager.is_cultivator_unlocked(cid)

	var p_style := GameStyle.card(GameStyle.JADE if is_unlocked else GameStyle.LINE,
			GameStyle.SLANT_PLATE, Vector2(4, 5))
	if not is_unlocked:
		p_style.bg_color = GameStyle.INK.lightened(0.03)
	_detail_panel.add_theme_stylebox_override("panel", p_style)

	# 1. 顶部概览行（大头像 + 名号 + 称号 + 解锁状态签）- 固定高约 68
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 10)
	top_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_content.add_child(top_row)

	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(56, 56)
	icon_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_border := GameStyle.JADE if is_unlocked else GameStyle.LINE
	icon_box.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, icon_border, 2, 0.0))

	if String(def.get("motion", "")) == "procedural":
		var pview := ProceduralCultivatorView.new()
		pview.position = Vector2(28, 34)
		pview.scale = Vector2(0.8, 0.8)
		pview.setup_character_id(cid)
		if not is_unlocked:
			pview.modulate = GameStyle.disabled_modulate()
		icon_box.add_child(pview)
		_detail_pview = pview
	else:
		var icon_tex := TextureRect.new()
		if ResourceLoader.exists(String(def.get("icon", ""))):
			icon_tex.texture = load(String(def["icon"]))
		icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_tex.custom_minimum_size = Vector2(48, 48)
		icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not is_unlocked:
			icon_tex.modulate = GameStyle.disabled_modulate()
		icon_box.add_child(icon_tex)
	top_row.add_child(icon_box)

	var name_box := VBoxContainer.new()
	name_box.add_theme_constant_override("separation", 2)
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.alignment = BoxContainer.ALIGNMENT_CENTER
	name_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(name_box)

	var name_lbl := Label.new()
	name_lbl.text = String(def.get("name", "?"))
	GameStyle.label(name_lbl, 18, GameStyle.PAPER if is_unlocked else GameStyle.PAPER_DIM, 0, GameStyle.INK, true)
	name_box.add_child(name_lbl)

	var epi_raw := " " + String(def.get("epithet", "")) + " "
	var epithet_lbl := Label.new()
	epithet_lbl.text = epi_raw
	epithet_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	epithet_lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	epithet_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.GOLD if is_unlocked else GameStyle.NAVY2))
	GameStyle.label(epithet_lbl, 10, GameStyle.INK_TEXT if is_unlocked else GameStyle.GREY)
	name_box.add_child(epithet_lbl)

	var status_box := VBoxContainer.new()
	status_box.alignment = BoxContainer.ALIGNMENT_CENTER
	status_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(status_box)

	var status_chip := Label.new()
	status_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_chip.size_flags_horizontal = Control.SIZE_SHRINK_END
	if is_unlocked:
		status_chip.text = " ◆ 已解锁 "
		status_chip.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.GOOD_DK))
		GameStyle.label(status_chip, 10, GameStyle.GOOD)
	else:
		status_chip.text = " × 未解锁 "
		status_chip.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.BAD_DK))
		GameStyle.label(status_chip, 10, GameStyle.BAD)
	status_box.add_child(status_chip)

	# 2. 中间：滚动特性区（ScrollContainer 填满剩余高度，内部逐条呈现）
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	GameStyle.scrollable(scroll)
	_detail_content.add_child(scroll)

	var mid_col := VBoxContainer.new()
	mid_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid_col.add_theme_constant_override("separation", 6)
	mid_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(mid_col)

	var col_w := text_col_w(vis_w)

	# (a) 初始装备
	var raw_equip := CultivatorData.get_start_equip(cid)
	if not raw_equip.is_empty():
		mid_col.add_child(_make_info_row("装备", GameStyle.JADE_DK, GameStyle.JADE,
				["◆ " + raw_equip], col_w))

	# (b) 独门天赋
	var pros_lines: Array[String] = []
	for p in def.get("pros", []):
		pros_lines.append("＋ " + String(p))
	if not pros_lines.is_empty():
		mid_col.add_child(_make_info_row("天赋", GameStyle.GOOD_DK, GameStyle.GOOD,
				pros_lines, col_w))

	# (c) 额外绝技（踏影、药池等机制单独一段）
	var extra_lines := CultivatorData.get_extra_desc(cid)
	if not extra_lines.is_empty():
		mid_col.add_child(_make_info_row("绝技", GameStyle.SHADOW_DK, GameStyle.SHADOW,
				extra_lines, col_w))

	# (d) 背负代价
	var cons_lines: Array[String] = []
	for c in def.get("cons", []):
		cons_lines.append("－ " + String(c))
	if not cons_lines.is_empty():
		mid_col.add_child(_make_info_row("代价", GameStyle.BAD_DK, GameStyle.BAD,
				cons_lines, col_w))

	GameStyle.swipeable(mid_col)

	# 2.5 皮肤切换栏（通关难度解锁换色皮肤；未解锁角色整排置灰）
	_skin_row = _make_skin_row(cid, is_unlocked)
	_detail_content.add_child(_skin_row)

	# 3. 底部操作栏（固定吸底，高度 46）
	var bottom_bar := MarginContainer.new()
	bottom_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_content.add_child(bottom_bar)

	if is_unlocked:
		var choose_btn := Button.new()
		choose_btn.text = "选 择 此 角 色"
		choose_btn.custom_minimum_size = Vector2(0, 44)
		choose_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choose_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		choose_btn.focus_mode = Control.FOCUS_NONE
		GameStyle.button(choose_btn, GameStyle.GOLD, GameStyle.JADE, 15, GameStyle.INK_TEXT, 6.0, GameStyle.INK_TEXT)
		choose_btn.pressed.connect(func(): _choose(cid))
		bottom_bar.add_child(choose_btn)
	else:
		var ach := AchievementData.cultivator_unlock_achievement(cid)
		var ach_name := String(ach.get("name", "特定成就"))
		var lock_row := HBoxContainer.new()
		lock_row.add_theme_constant_override("separation", 8)
		lock_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bottom_bar.add_child(lock_row)

		# 左：解锁条件 + 当前进度（可点卡，点按出成就详解浮卡 —— 「这是什么」点按可得）
		var cond_card := PanelContainer.new()
		cond_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cond_card.mouse_filter = Control.MOUSE_FILTER_STOP
		var c_sb := GameStyle.side_card(GameStyle.GOLD_DK)
		c_sb.content_margin_left = 10.0
		c_sb.content_margin_right = 10.0
		c_sb.content_margin_top = 4.0
		c_sb.content_margin_bottom = 4.0
		cond_card.add_theme_stylebox_override("panel", c_sb)

		var cond_box := VBoxContainer.new()
		cond_box.add_theme_constant_override("separation", 1)
		cond_box.alignment = BoxContainer.ALIGNMENT_CENTER
		cond_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cond_card.add_child(cond_box)

		var cond_lbl := Label.new()
		cond_lbl.text = "达成成就【%s】解锁" % ach_name
		GameStyle.label(cond_lbl, 12, GameStyle.PAPER_DIM)
		cond_box.add_child(cond_lbl)

		var prog_txt := AchievementData.progress_text(String(ach.get("id", "")), GameManager.career_stats)
		var prog_lbl := Label.new()
		prog_lbl.text = ("当前进度：%s · 点看详情" % prog_txt) if not prog_txt.is_empty() else "点看解锁详情"
		GameStyle.label(prog_lbl, 10, GameStyle.GOLD)
		cond_box.add_child(prog_lbl)

		lock_row.add_child(cond_card)
		GameStyle.tap(cond_card, func() -> void: _open_lock_tip(ach, cond_card))

		var lock_btn := Button.new()
		lock_btn.text = "未 解 锁"
		lock_btn.custom_minimum_size = Vector2(100, 42)
		lock_btn.disabled = true
		lock_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		lock_btn.focus_mode = Control.FOCUS_NONE
		GameStyle.button(lock_btn, GameStyle.INK, GameStyle.LINE, 13, GameStyle.GREY, 6.0)
		lock_row.add_child(lock_btn)

## 锁定条点按详情浮卡：解锁条件 + 当前进度 + 奖励（进度口径 = career_stats 单局生涯最佳）
func _open_lock_tip(ach: Dictionary, anchor: Control) -> void:
	var aid := String(ach.get("id", ""))
	var done := GameManager.is_achievement_unlocked(aid)
	var cat := String(ach.get("category", "style"))
	var cat_col: Color
	match cat:
		"trial":
			cat_col = GameStyle.BAD
		"style":
			cat_col = GameStyle.GOLD
		"grind":
			cat_col = GameStyle.GOOD
		_:
			cat_col = GameStyle.JADE
	var rows: Array = [
		["状态", "已达成" if done else "未达成", GameStyle.GOOD if done else GameStyle.GREY],
		["奖励", "解锁角色：%s" % String(ach.get("reward_name", "")), GameStyle.JADE],
	]
	var prog := AchievementData.progress_text(aid, GameManager.career_stats)
	if not prog.is_empty():
		rows.append(["当前进度", prog, GameStyle.GOOD if done else GameStyle.GOLD])
	DetailTip.show_over(self, anchor, {
		"title": String(ach.get("name", "成就")),
		"chip": String(AchievementData.CATEGORY_NAMES.get(cat, cat)),
		"chip_color": cat_col,
		"rows": rows,
		"body": String(ach.get("cond_desc", "")),
		"foot": "进度取生涯单局最佳记录，达成后自动解锁该角色。",
	})

# ---------------- 皮肤切换栏（通关难度解锁换色皮肤） ----------------

## 皮肤栏：「皮肤」色签 + 原色槽 + 6 套主题色槽
func _make_skin_row(cid: String, is_unlocked: bool) -> Control:
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 6)
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tag_lbl := Label.new()
	tag_lbl.text = " 皮肤 "
	tag_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.GOLD))
	GameStyle.label(tag_lbl, 11, GameStyle.INK_TEXT)
	strip.add_child(tag_lbl)

	var cur_idx := GameManager.get_selected_skin(cid)
	var base_cfg := CultivatorVisualConfig.get_config(cid)

	# 原色槽：底色取角色本相斗篷内衬，迷你小人直观展示「本来的样子」
	strip.add_child(_make_skin_slot(cid, -1,
			Color(base_cfg.cloak.get("col_inner", GameStyle.NAVY2)),
			Color(base_cfg.cloak.get("col_edge", GameStyle.LINE)),
			is_unlocked, cur_idx == -1))

	for i in range(SkinData.count()):
		var t := SkinData.get_theme(i)
		var slot_open := is_unlocked and GameManager.is_skin_unlocked(cid, i)
		strip.add_child(_make_skin_slot(cid, i,
				Color(t.get("cloak_inner", GameStyle.NAVY2)),
				Color(t.get("cloak_edge", GameStyle.LINE)),
				slot_open, is_unlocked and cur_idx == i))

	return strip

## 单个皮肤槽：迷你小人实况预览 + 内衬色底 + 缘色描边；选中金框高亮；未解锁灰化加「锁」
func _make_skin_slot(cid: String, skin_idx: int,
		main_col: Color, edge_col: Color, open: bool, selected: bool) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(40, 40)
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.clip_contents = true
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	# 底色用斗篷内衬（比外袍亮一档），未解锁降饱和压暗但仍可辨认主题色调
	# （引擎 Color 无 desaturated()，用向中性灰 lerp 实现降饱和）
	var bg := main_col if open else main_col.darkened(0.30).lerp(Color(0.5, 0.5, 0.5), 0.45)
	var border := GameStyle.JADE if selected else (edge_col if open else GameStyle.LINE)
	slot.add_theme_stylebox_override("panel",
			GameStyle.outlined_panel(bg, border, 2 if selected else 1, 0.0))

	# 迷你小人所见即所得：原色槽钉 -1 本相，主题槽钉各自 skin_idx
	var pv := ProceduralCultivatorView.new()
	pv.position = Vector2(20, 31)
	pv.scale = Vector2(0.55, 0.55)
	pv.setup_character_id(cid, skin_idx)
	if not open:
		pv.modulate = GameStyle.disabled_modulate()
	slot.add_child(pv)

	if not open:
		var lock_lbl := Label.new()
		lock_lbl.text = "锁"
		lock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lock_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		GameStyle.label(lock_lbl, 10, GameStyle.GREY)
		slot.add_child(lock_lbl)
	GameStyle.tap(slot, func() -> void: _on_skin_slot_tapped(cid, skin_idx, slot))
	return slot

func _on_skin_slot_tapped(cid: String, skin_idx: int, anchor: Control) -> void:
	if not GameManager.is_cultivator_unlocked(cid):
		return
	if not GameManager.is_skin_unlocked(cid, skin_idx):
		AudioManager.play_sfx("ui_click")
		_open_skin_lock_tip(cid, skin_idx, anchor)
		return
	if GameManager.get_selected_skin(cid) == skin_idx:
		return
	AudioManager.play_sfx("ui_confirm", 1.0)
	GameManager.set_selected_skin(cid, skin_idx)
	# 详情大头像与右侧网格缩略图实时换色；皮肤栏原位重建刷新选中框
	if _detail_pview != null and is_instance_valid(_detail_pview):
		_detail_pview.setup_character_id(cid)
	_refresh_roster_skin(cid)
	if _skin_row != null and is_instance_valid(_skin_row):
		var at := _skin_row.get_index()
		_skin_row.queue_free()
		_skin_row = _make_skin_row(cid, true)
		_detail_content.add_child(_skin_row)
		_detail_content.move_child(_skin_row, at)

## 右侧网格该角色缩略图同步换色
func _refresh_roster_skin(cid: String) -> void:
	if not _roster_cards.has(cid):
		return
	var pv: ProceduralCultivatorView = _roster_cards[cid].get("pview")
	if pv != null and is_instance_valid(pv):
		pv.setup_character_id(cid)

## 未解锁皮肤点按详情浮卡：解锁条件 + 当前进度（「这是什么」点按可得）
func _open_skin_lock_tip(cid: String, skin_idx: int, anchor: Control) -> void:
	var t := SkinData.get_theme(skin_idx)
	var tier := int(t.get("tier", 0))
	var dmax := AchievementData.DANGER_NAMES.size() - 1
	var dname := AchievementData.DANGER_NAMES[clampi(tier, 0, dmax)]
	var best := GameManager.get_cultivator_best_danger(cid)
	var best_txt := "尚未通关" if best < 0 else "已通关「%s」" % AchievementData.DANGER_NAMES[clampi(best, 0, dmax)]
	DetailTip.show_over(self, anchor, {
		"title": "皮肤 · %s" % String(t.get("name", "")),
		"chip": "未解锁",
		"chip_color": GameStyle.GREY,
		"rows": [
			["解锁条件", "通关「%s」难度" % dname, GameStyle.GOLD],
			["当前进度", best_txt, GameStyle.GOOD if best >= tier else GameStyle.GREY],
		],
		"body": "通关对应难度即可解锁该皮肤；通关更高难度时，低档皮肤将一并解锁。",
	})

## 将文本中的核心数值与机制名精准高亮（其余正文走 PAPER 纸白色）
static func highlight_bbcode(raw: String) -> String:
	var s := raw
	var good_hex := "#" + GameStyle.GOOD.to_html(false)
	var bad_hex := "#" + GameStyle.BAD.to_html(false)
	var jade_hex := "#" + GameStyle.JADE.to_html(false)
	var gold_hex := "#" + GameStyle.GOLD.to_html(false)

	# 1. 机制名 【...】 -> JADE 金黄
	var re_mech := RegEx.new()
	re_mech.compile("【([^】]+)】")
	s = re_mech.sub(s, "[color=" + jade_hex + "]【$1】[/color]", true)

	# 2. 负向限制与惩罚词
	var re_bad_kw := RegEx.new()
	re_bad_kw.compile("(无法通过加点提升|加点锁定|无法提升|限制为 3 格|损失 3 点|物价 \\+50%)")
	s = re_bad_kw.sub(s, "[color=" + bad_hex + "]$1[/color]", true)

	# 3. 负向数值 (-数字% 或 -数字)
	var re_bad_num := RegEx.new()
	re_bad_num.compile("(-\\d+(?:\\.\\d+)?%?)")
	s = re_bad_num.sub(s, "[color=" + bad_hex + "]$1[/color]", true)

	# 4. 正向增益数值 (+数字% / +数字 / ×数字 / 百分比)
	var re_good_num := RegEx.new()
	re_good_num.compile("(\\+\\d+(?:\\.\\d+)?%?|×\\d+(?:\\.\\d+)?|8 折|100%|90%|100 金币)")
	s = re_good_num.sub(s, "[color=" + good_hex + "]$1[/color]", true)

	# 5. 专属契合名字
	var re_syn := RegEx.new()
	re_syn.compile("「([^」]+)」")
	s = re_syn.sub(s, "[color=" + gold_hex + "]「$1」[/color]", true)

	return s

## 构造一条左侧色签 + 右侧精准强调色正文的特性行卡片
func _make_info_row(tag_title: String, chip_bg: Color, accent_col: Color,
		lines: Array, col_w: float) -> PanelContainer:
	var row_panel := PanelContainer.new()
	row_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb := GameStyle.side_card(accent_col)
	sb.content_margin_left = ROW_PAD_X
	sb.content_margin_right = ROW_PAD_X
	sb.content_margin_top = 5.0
	sb.content_margin_bottom = 5.0
	row_panel.add_theme_stylebox_override("panel", sb)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", int(ROW_GAP))
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row_panel.add_child(hbox)

	var tag_lbl := Label.new()
	tag_lbl.text = " %s " % tag_title
	tag_lbl.custom_minimum_size = Vector2(TAG_CHIP_W, 0)
	tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag_lbl.add_theme_stylebox_override("normal", GameStyle.chip(chip_bg))
	var tag_fg := GameStyle.on_face_text(chip_bg)
	GameStyle.label(tag_lbl, 11, tag_fg)
	hbox.add_child(tag_lbl)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_box.add_theme_constant_override("separation", 2)
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(text_box)

	for raw_line in lines:
		var rich_raw := highlight_bbcode(String(raw_line))
		var wrapped := GameStyle.wrap_bbcode(rich_raw, GameStyle.body_font(), TXT, col_w)

		var rtl := RichTextLabel.new()
		rtl.bbcode_enabled = true
		rtl.text = wrapped
		rtl.fit_content = true
		rtl.scroll_active = false
		rtl.custom_minimum_size = Vector2(col_w, 0)
		rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rtl.add_theme_font_override("normal_font", GameStyle.body_font())
		rtl.add_theme_font_size_override("normal_font_size", TXT)
		rtl.add_theme_color_override("default_color", GameStyle.PAPER)
		text_box.add_child(rtl)

	return row_panel

# ---------------- 右侧：全部角色纵向双列小卡片 ----------------

func _rebuild_roster_cards(vis_w: float) -> void:
	var ids: Array = CultivatorData.all_ids()
	if _roster_cards.size() == ids.size() and absf(_cached_roster_w - vis_w) < 1.0:
		for cid in ids:
			_update_small_card_selection(String(cid))
		return

	for child in _roster_grid.get_children():
		child.queue_free()
	_roster_cards.clear()
	_cached_roster_w = vis_w

	_roster_grid.columns = 2
	var inner_w := small_card_inner_w(vis_w, ids.size())
	for cid in ids:
		_roster_grid.add_child(_create_small_card(String(cid), inner_w))
	GameStyle.swipeable(_roster_grid)

func _update_small_card_selection(cid: String) -> void:
	if not _roster_cards.has(cid):
		return
	var data: Dictionary = _roster_cards[cid]
	var is_selected: bool = (cid == _selected_id)
	var is_unlocked: bool = bool(data.get("is_unlocked", false))
	var style: StyleBoxFlat = data.get("style")
	var icon_box: PanelContainer = data.get("icon_box")
	var name_lbl: Label = data.get("name_lbl")
	var tag_lbl: Label = data.get("tag_lbl")

	var accent := GameStyle.JADE if is_selected else \
			(GameStyle.GOLD.darkened(0.35) if is_unlocked else GameStyle.LINE)
	if style != null:
		style.border_color = accent
		if is_unlocked and not is_selected:
			GameStyle.register_theme_derived_box(style, &"border_color", &"main", &"darken", 0.35)
		if is_selected:
			style.bg_color = GameStyle.NAVY2.lightened(0.12)
		elif not is_unlocked:
			style.bg_color = GameStyle.INK.lightened(0.02)
		else:
			style.bg_color = GameStyle.NAVY2

	if icon_box != null:
		var ib_border := GameStyle.JADE if is_selected else (GameStyle.GOLD_EDGE if is_unlocked else GameStyle.LINE)
		icon_box.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, ib_border, 1, 0.0))

	if name_lbl != null:
		var name_col := GameStyle.JADE_DK if is_selected else (GameStyle.PAPER if is_unlocked else GameStyle.GREY)
		name_lbl.add_theme_color_override("font_color", name_col)

	if tag_lbl != null:
		if is_selected:
			tag_lbl.text = "◆"
			tag_lbl.add_theme_color_override("font_color", GameStyle.JADE_DK)
		elif not is_unlocked:
			tag_lbl.text = "×"
			tag_lbl.add_theme_color_override("font_color", GameStyle.GREY)
		else:
			tag_lbl.text = " "
			tag_lbl.add_theme_color_override("font_color", GameStyle.PAPER_DIM)

func _create_small_card(cid: String, inner_w: float) -> Control:
	var def: Dictionary = CultivatorData.get_def(cid)
	var is_selected: bool = (cid == _selected_id)
	var is_unlocked: bool = GameManager.is_cultivator_unlocked(cid)

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, SMALL_CARD_H)

	var accent := GameStyle.JADE if is_selected else \
			(GameStyle.GOLD.darkened(0.35) if is_unlocked else GameStyle.LINE)
	var style := GameStyle.card(accent, GameStyle.SLANT_PLATE, Vector2(3, 3))
	if is_unlocked and not is_selected:
		GameStyle.register_theme_derived_box(style, &"border_color", &"main", &"darken", 0.35)
	if is_selected:
		style.bg_color = GameStyle.NAVY2.lightened(0.12)
	elif not is_unlocked:
		style.bg_color = GameStyle.INK.lightened(0.02)
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	card.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(hbox)

	# 形象小头像 (40x40)
	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(40, 40)
	icon_box.clip_contents = true
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ib_border := GameStyle.JADE if is_selected else (GameStyle.GOLD_EDGE if is_unlocked else GameStyle.LINE)
	icon_box.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, ib_border, 1, 0.0))

	var pview: ProceduralCultivatorView = null
	if String(def.get("motion", "")) == "procedural":
		pview = ProceduralCultivatorView.new()
		pview.position = Vector2(20, 24)
		pview.scale = Vector2(0.55, 0.55)
		pview.setup_character_id(cid)
		if not is_unlocked:
			pview.modulate = GameStyle.disabled_modulate()
		icon_box.add_child(pview)
	else:
		var icon_tex := TextureRect.new()
		if ResourceLoader.exists(String(def.get("icon", ""))):
			icon_tex.texture = load(String(def["icon"]))
		icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_tex.custom_minimum_size = Vector2(34, 34)
		icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not is_unlocked:
			icon_tex.modulate = GameStyle.disabled_modulate()
		icon_box.add_child(icon_tex)
	hbox.add_child(icon_box)

	# 中间文字列（名号 + 称号）
	var info_box := VBoxContainer.new()
	info_box.add_theme_constant_override("separation", 1)
	info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_box.alignment = BoxContainer.ALIGNMENT_CENTER
	info_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(info_box)

	var name_lbl := Label.new()
	name_lbl.text = String(def.get("name", "?"))
	var name_col := GameStyle.JADE_DK if is_selected else (GameStyle.PAPER if is_unlocked else GameStyle.GREY)
	GameStyle.label(name_lbl, 13, name_col, 0, GameStyle.INK, true)
	info_box.add_child(name_lbl)

	var epi_lbl := Label.new()
	epi_lbl.text = String(def.get("epithet", "")).split("，")[0] # 取前四字或简签
	GameStyle.label(epi_lbl, 10, GameStyle.PAPER_DIM if is_unlocked else GameStyle.GREY)
	info_box.add_child(epi_lbl)

	# 右侧状态徽章
	var badge_box := VBoxContainer.new()
	badge_box.alignment = BoxContainer.ALIGNMENT_CENTER
	badge_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(badge_box)

	var tag_lbl := Label.new()
	if is_selected:
		tag_lbl.text = "◆"
		GameStyle.label(tag_lbl, 12, GameStyle.JADE_DK)
	elif not is_unlocked:
		tag_lbl.text = "×"
		GameStyle.label(tag_lbl, 10, GameStyle.GREY)
	else:
		tag_lbl.text = " "
		GameStyle.label(tag_lbl, 10, GameStyle.PAPER_DIM)
	badge_box.add_child(tag_lbl)

	# 整块热区 + 「按下与抬起都留在原地」才算点（尺子在 GameStyle.tap 头注）。
	# 旧写法在这里认「按下」那一枪，两个后果都落在「拖列表」这个动作上：
	# ① 手指一落到卡片上就换人 —— 想滑动却点中了某个角色；
	# ② 换人要重建左侧整栏详情（实测单次平均 4.0ms、最坏 6.0ms，全是文本重排与节点重建，
	#    真机 CPU 更慢），而这一下正好卡在 ScrollContainer 起手锁定拖动的那一帧 ⇒ 滑动发涩。
	# 改成认完整手势后，点按仍在抬起那一刻兑现（与全项目其余卡片同一把尺子），
	# 拖动过程中谁都不重建，那一帧的预算全给滚动。
	GameStyle.hotzone(card)
	# 按下立刻亮一下：反馈不等抬手，样式在抬起时按「当前选中态」交还给唯一真话（_update_small_card_selection）
	card.gui_input.connect(func(ev: InputEvent) -> void:
		var mb := ev as InputEventMouseButton
		if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			style.bg_color = GameStyle.NAVY2.lightened(0.22)
		else:
			_update_small_card_selection(cid)
	)
	GameStyle.tap(card, func() -> void: _select_cultivator(cid))

	_roster_cards[cid] = {
		"card": card,
		"style": style,
		"icon_box": icon_box,
		"name_lbl": name_lbl,
		"tag_lbl": tag_lbl,
		"is_unlocked": is_unlocked,
		"pview": pview,
	}

	return card

func _unhandled_input(event: InputEvent) -> void:
	if not visible or _transitioning:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		_step_selection(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
		_step_selection(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		if GameManager.is_cultivator_unlocked(_selected_id):
			_choose(_selected_id)
			get_viewport().set_input_as_handled()

func _step_selection(delta: int) -> void:
	var ids: Array = CultivatorData.all_ids()
	if ids.is_empty():
		return
	var idx := ids.find(_selected_id)
	if idx < 0:
		idx = 0
	var next_idx := (idx + delta + ids.size()) % ids.size()
	_select_cultivator(String(ids[next_idx]))

func _on_back_pressed() -> void:
	if not visible or _transitioning:
		return
	_transitioning = true
	AudioManager.play_sfx("ui_click")
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.16)
	tw.tween_callback(func():
		visible = false
		_transitioning = false
		var parent_node = get_parent()
		if parent_node != null:
			var backdrop = parent_node.get_node_or_null("StageBackdrop")
			if backdrop != null:
				backdrop.visible = false
			var start_menu = parent_node.get_node_or_null("StartMenu")
			if start_menu != null and start_menu.has_method("open"):
				start_menu.open()
	)

func _choose(cid: String) -> void:
	if _transitioning:
		return
	_transitioning = true
	AudioManager.play_sfx("ui_confirm", 0.95)
	GameManager.cultivator_id = cid
	if GameManager.player != null and is_instance_valid(GameManager.player) and GameManager.player.has_method("_setup_sprite_frames"):
		GameManager.player._setup_sprite_frames()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func():
		visible = false
		_transitioning = false
		var skill_select := get_parent().get_node_or_null("SkillSelect")
		if skill_select != null and skill_select.has_method("show_select"):
			skill_select.show_select()
		else:
			var weapon_select := get_parent().get_node_or_null("StartWeaponSelect")
			if weapon_select != null:
				weapon_select.show_select()
	)
