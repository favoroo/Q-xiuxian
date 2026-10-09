class_name CultivatorSelect
extends Control

## 开局道统择选（上下分层 Master-Detail 架构）：
## - 上半部分：当前选中修士的详解大卡片（形象、名号、称号、开局装备与特权、独门天赋、背负代价、契合神通、拜入/解锁条件）
## - 下半部分：全部 9 名修士的形象小卡片横排一览（头像、名号、状态/通关勋章），点击或方向键即时切换预览
## 流程：StartMenu → CultivatorSelect → SkillSelect → StartWeaponSelect（全程保持 paused）

const EDGE := 24.0          # 左右屏边留白（兼顾斜切面板伸出量，确保 drawn_rect 不出屏）
const DETAIL_PAD_X := 14.0  # 顶部详解大卡片左右内边距
const LEFT_COL_W := 148.0   # 顶部详解卡：左侧形象与名号列宽
const RIGHT_COL_W := 128.0  # 顶部详解卡：右侧确认/解锁列宽
const DETAIL_GAP := 12.0    # 顶部详解卡：左中右三列间距
const ROW_PAD_X := 8.0      # 中间特性条目卡左右内边距
const TAG_CHIP_W := 68.0    # 中间特性条目卡左侧分类色签宽
const ROW_GAP := 8.0        # 分类色签与正文间距
const BORDER_RESERVE := 16.0 # 外层面板描边 + 条目卡描边 + 色签内边距安全余量
const TXT := 12             # 特性正文字号
const ROSTER_GAP := 5.0     # 底部形象小卡片间距
const SMALL_CARD_H := 104.0 # 底部形象小卡片高度

var _title_label: Label
var _sub_label: Label
var _detail_panel: PanelContainer
var _detail_margin: MarginContainer
var _roster_row: HBoxContainer
var _selected_id: String = "jianchi"
var _transitioning: bool = false

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.04, 0.09, 0.90)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", int(EDGE))
	margin.add_theme_constant_override("margin_right", int(EDGE))
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vbox)

	# 1. 顶部导航栏：左返回按钮 + 居中标题 + 右侧等宽占位保证绝对居中
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

	_title_label = Label.new()
	_title_label.text = "选 择 道 统"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	header_row.add_child(_title_label)
	GameStyle.label(_title_label, 25, GameStyle.PAPER, 0, GameStyle.INK, true)

	var r_spacer := Control.new()
	r_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(r_spacer)

	var dummy_r := Control.new()
	dummy_r.custom_minimum_size = Vector2(84, 32)
	dummy_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(dummy_r)

	_sub_label = Label.new()
	_sub_label.text = "点选下方修士卡片查看道统详情 · 确认开局装备、独门天赋与代价后拜入道门"
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(_sub_label)
	GameStyle.label(_sub_label, 12, GameStyle.PAPER_DIM)

	# 2. 上半部分：当前选中人物的介绍大卡片
	_detail_panel = PanelContainer.new()
	_detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(_detail_panel)

	_detail_margin = MarginContainer.new()
	_detail_margin.add_theme_constant_override("margin_left", int(DETAIL_PAD_X))
	_detail_margin.add_theme_constant_override("margin_right", int(DETAIL_PAD_X))
	_detail_margin.add_theme_constant_override("margin_top", 10)
	_detail_margin.add_theme_constant_override("margin_bottom", 10)
	_detail_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_panel.add_child(_detail_margin)

	# 3. 下半部分：各个人物的形象小卡片与名称横排
	_roster_row = HBoxContainer.new()
	_roster_row.add_theme_constant_override("separation", int(ROSTER_GAP))
	_roster_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_roster_row.custom_minimum_size = Vector2(0, SMALL_CARD_H)
	_roster_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_roster_row)

func show_select() -> void:
	_transitioning = false
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

## 顶部详解卡中间特性列的可用文字宽：
## 整屏宽扣掉屏边留白、详解卡内边距、左列形象区、右列按钮区、列间距，再扣条目卡内边距与分类色签。
## 纯函数 ⇒ LayoutCheck 直接调用它做全表文案折行校验，不另抄算术。
static func text_col_w(vis_w: float) -> float:
	var panel_inner_w := vis_w - EDGE * 2.0 - DETAIL_PAD_X * 2.0
	var mid_w := panel_inner_w - LEFT_COL_W - RIGHT_COL_W - DETAIL_GAP * 2.0
	var txt_w := mid_w - ROW_PAD_X * 2.0 - TAG_CHIP_W - ROW_GAP - BORDER_RESERVE
	return maxf(160.0, txt_w)

## 底部每张形象小卡片的内部可用文字宽
static func small_card_inner_w(vis_w: float, count: int = 9) -> float:
	var n := maxi(1, count)
	var total_w := vis_w - EDGE * 2.0 - ROSTER_GAP * float(n - 1)
	var card_w := total_w / float(n)
	return maxf(48.0, card_w - 10.0)

func _select_cultivator(cid: String) -> void:
	if _transitioning or cid == _selected_id:
		return
	AudioManager.play_sfx("ui_click")
	_selected_id = cid
	_rebuild_all()

func _rebuild_all() -> void:
	var vis_w := get_viewport().get_visible_rect().size.x
	if vis_w <= 0.0:
		vis_w = 960.0
	_rebuild_detail_card(_selected_id, vis_w)
	_rebuild_roster_cards(vis_w)

# ---------------- 上半部分：人物介绍大卡片 ----------------

func _rebuild_detail_card(cid: String, vis_w: float) -> void:
	for child in _detail_margin.get_children():
		child.queue_free()

	var def: Dictionary = CultivatorData.get_def(cid)
	var is_unlocked: bool = GameManager.is_cultivator_unlocked(cid)
	var best_d: int = GameManager.get_cultivator_best_danger(cid)

	var p_style := GameStyle.card(GameStyle.JADE if is_unlocked else GameStyle.LINE,
			GameStyle.SLANT_PLATE, Vector2(4, 5))
	if not is_unlocked:
		p_style.bg_color = GameStyle.INK.lightened(0.03)
	_detail_panel.add_theme_stylebox_override("panel", p_style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", int(DETAIL_GAP))
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_margin.add_child(hbox)

	# 1. 左列：大头像 + 名号 + 称号 + 通关状态
	var left_col := VBoxContainer.new()
	left_col.custom_minimum_size = Vector2(LEFT_COL_W, 0)
	left_col.add_theme_constant_override("separation", 6)
	left_col.alignment = BoxContainer.ALIGNMENT_CENTER
	left_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(left_col)

	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(72, 72)
	icon_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_border := GameStyle.JADE if is_unlocked else GameStyle.LINE
	icon_box.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, icon_border, 2, 0.0))

	var icon_tex := TextureRect.new()
	if ResourceLoader.exists(String(def.get("icon", ""))):
		icon_tex.texture = load(String(def["icon"]))
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.custom_minimum_size = Vector2(60, 60)
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not is_unlocked:
		icon_tex.modulate = Color(0.4, 0.4, 0.5, 0.7)
	icon_box.add_child(icon_tex)
	left_col.add_child(icon_box)

	var name_lbl := Label.new()
	name_lbl.text = GameStyle.wrap_cjk(String(def.get("name", "?")), GameStyle.display_font(), 18, LEFT_COL_W)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.custom_minimum_size = Vector2(LEFT_COL_W, 0)
	left_col.add_child(name_lbl)
	GameStyle.label(name_lbl, 18, GameStyle.PAPER if is_unlocked else GameStyle.PAPER_DIM, 0, GameStyle.INK, true)

	var epi_raw := " " + String(def.get("epithet", "")) + " "
	var epi_txt := GameStyle.wrap_cjk(epi_raw, GameStyle.body_font(), 10, LEFT_COL_W - 8.0)
	var epithet_lbl := Label.new()
	epithet_lbl.text = epi_txt
	epithet_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	epithet_lbl.custom_minimum_size = Vector2(GameStyle.chip_pin_w(epi_txt, GameStyle.body_font(), 10), 0)
	epithet_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	epithet_lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	epithet_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.GOLD_DK if is_unlocked else GameStyle.NAVY2))
	left_col.add_child(epithet_lbl)
	GameStyle.label(epithet_lbl, 10, GameStyle.PAPER if is_unlocked else GameStyle.GREY)

	var status_chip := Label.new()
	status_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if is_unlocked and best_d >= 0:
		var d_name: String = AchievementData.danger_name(best_d)
		status_chip.text = " ★ 最高通关·%s " % d_name
		status_chip.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.JADE_DK))
		GameStyle.label(status_chip, 10, GameStyle.JADE)
	elif is_unlocked:
		status_chip.text = " ✦ 道门已开 "
		status_chip.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.GOOD_DK))
		GameStyle.label(status_chip, 10, GameStyle.GOOD)
	else:
		status_chip.text = " ✖ 天道锁闭 "
		status_chip.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.BAD_DK))
		GameStyle.label(status_chip, 10, GameStyle.BAD)
	left_col.add_child(status_chip)

	# 2. 中列：结构化彩色特性行（开局装备 / 独门天赋 / 背负代价 / 契合神通）
	var mid_col := VBoxContainer.new()
	mid_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid_col.add_theme_constant_override("separation", 6)
	mid_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(mid_col)

	var col_w := text_col_w(vis_w)

	# (a) 开局装备（仅当角色确实额外携带初始装备时才展示，黄色高亮）
	var raw_equip := CultivatorData.get_start_equip(cid)
	if not raw_equip.is_empty():
		var equip_text := "✦ " + raw_equip
		mid_col.add_child(_make_info_row("开局装备", GameStyle.JADE_DK, GameStyle.JADE, [equip_text], GameStyle.JADE, col_w))

	# (b) 独门天赋（绿色高亮）
	var pros_lines: Array[String] = []
	for p in def.get("pros", []):
		pros_lines.append("＋ " + String(p))
	var pros_joined := "    ".join(pros_lines) if pros_lines.size() <= 2 else "\n".join(pros_lines)
	mid_col.add_child(_make_info_row("独门天赋", GameStyle.GOOD_DK, GameStyle.GOOD, [pros_joined], GameStyle.GOOD, col_w))

	# (c) 背负代价（红色高亮）
	var cons_lines: Array[String] = []
	for c in def.get("cons", []):
		cons_lines.append("－ " + String(c))
	var cons_joined := "    ".join(cons_lines) if cons_lines.size() <= 2 else "\n".join(cons_lines)
	mid_col.add_child(_make_info_row("背负代价", GameStyle.BAD_DK, GameStyle.BAD, [cons_joined], GameStyle.BAD, col_w))

	# (d) 契合神通（蓝色高亮，动态从 SkillData 合入真实强化描述）
	var syn_sid := CultivatorData.get_synergy_skill_id(cid)
	var syn_text := "✦ 任意随行神通皆可搭配"
	if not syn_sid.is_empty():
		var sdef := SkillData.get_def(syn_sid)
		var sname := String(sdef.get("name", syn_sid))
		var enh := SkillData.enhance_desc(syn_sid, cid)
		if not enh.is_empty():
			syn_text = "✦ 专属契合「%s」：%s" % [sname, enh]
		else:
			syn_text = "✦ 专属契合「%s」" % sname
	mid_col.add_child(_make_info_row("契合神通", GameStyle.GOLD_DK, GameStyle.GOLD_EDGE, [syn_text], GameStyle.GOLD_EDGE, col_w))

	# 3. 右列：拜入此门按钮 或 解锁条件说明
	var right_col := VBoxContainer.new()
	right_col.custom_minimum_size = Vector2(RIGHT_COL_W, 0)
	right_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right_col.add_theme_constant_override("separation", 8)
	right_col.alignment = BoxContainer.ALIGNMENT_CENTER
	right_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(right_col)

	if is_unlocked:
		var ready_lbl := Label.new()
		ready_lbl.text = "✦ 道统就绪 ✦"
		ready_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		GameStyle.label(ready_lbl, 12, GameStyle.JADE)
		right_col.add_child(ready_lbl)

		var choose_btn := Button.new()
		choose_btn.text = "拜 入 此 门"
		choose_btn.custom_minimum_size = Vector2(RIGHT_COL_W, 46)
		choose_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		choose_btn.focus_mode = Control.FOCUS_NONE
		GameStyle.button(choose_btn, GameStyle.GOLD, GameStyle.JADE, 15, GameStyle.INK_TEXT, 6.0, GameStyle.INK_TEXT)
		choose_btn.pressed.connect(func(): _choose(cid))
		right_col.add_child(choose_btn)
	else:
		var ach := AchievementData.cultivator_unlock_achievement(cid)
		var ach_name := String(ach.get("name", "天道考验"))
		var cond_text := String(ach.get("cond_desc", "完成特定天道功绩后解锁"))

		var lock_hdr := Label.new()
		lock_hdr.text = "✦ 解锁条件 ✦"
		lock_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		GameStyle.label(lock_hdr, 12, GameStyle.BAD)
		right_col.add_child(lock_hdr)

		var ach_lbl := Label.new()
		var ach_wrapped := GameStyle.wrap_cjk("功绩「%s」" % ach_name, GameStyle.body_font(), 11, RIGHT_COL_W - 4.0)
		ach_lbl.text = ach_wrapped
		ach_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ach_lbl.custom_minimum_size = Vector2(RIGHT_COL_W - 4.0, 0)
		ach_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		GameStyle.label(ach_lbl, 11, GameStyle.JADE)
		right_col.add_child(ach_lbl)

		var cond_lbl := Label.new()
		var cond_wrapped := GameStyle.wrap_cjk(cond_text, GameStyle.body_font(), 11, RIGHT_COL_W - 4.0)
		cond_lbl.text = cond_wrapped
		cond_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cond_lbl.custom_minimum_size = Vector2(RIGHT_COL_W - 4.0, 0)
		cond_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		GameStyle.label(cond_lbl, 11, GameStyle.PAPER_DIM)
		right_col.add_child(cond_lbl)

		var lock_btn := Button.new()
		lock_btn.text = "未 解 锁"
		lock_btn.custom_minimum_size = Vector2(RIGHT_COL_W, 38)
		lock_btn.disabled = true
		lock_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		lock_btn.focus_mode = Control.FOCUS_NONE
		GameStyle.button(lock_btn, GameStyle.INK, GameStyle.LINE, 13, GameStyle.GREY, 6.0)
		right_col.add_child(lock_btn)

## 构造一条「左侧色签 + 右侧着色文案」的特性行卡片
func _make_info_row(tag_title: String, chip_bg: Color, accent_col: Color,
		lines: Array, text_col: Color, col_w: float) -> PanelContainer:
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
	GameStyle.label(tag_lbl, 11, accent_col)
	hbox.add_child(tag_lbl)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_box.add_theme_constant_override("separation", 2)
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(text_box)

	for raw_line in lines:
		var lbl := Label.new()
		lbl.text = GameStyle.wrap_cjk(String(raw_line), GameStyle.body_font(), TXT, col_w)
		lbl.custom_minimum_size = Vector2(col_w, 0)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		GameStyle.label(lbl, TXT, text_col)
		text_box.add_child(lbl)

	return row_panel

# ---------------- 下半部分：人物形象小卡片横排 ----------------

func _rebuild_roster_cards(vis_w: float) -> void:
	for child in _roster_row.get_children():
		child.queue_free()

	var ids: Array = CultivatorData.all_ids()
	var inner_w := small_card_inner_w(vis_w, ids.size())
	for cid in ids:
		_roster_row.add_child(_create_small_card(String(cid), inner_w))

func _create_small_card(cid: String, inner_w: float) -> Control:
	var def: Dictionary = CultivatorData.get_def(cid)
	var is_selected: bool = (cid == _selected_id)
	var is_unlocked: bool = GameManager.is_cultivator_unlocked(cid)
	var best_d: int = GameManager.get_cultivator_best_danger(cid)

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(66, SMALL_CARD_H)

	var accent := GameStyle.JADE if is_selected else \
			(GameStyle.GOLD.darkened(0.35) if is_unlocked else GameStyle.LINE)
	var style := GameStyle.card(accent, GameStyle.SLANT_PLATE, Vector2(3, 3))
	if is_selected:
		style.bg_color = GameStyle.NAVY2.lightened(0.12)
	elif not is_unlocked:
		style.bg_color = GameStyle.INK.lightened(0.02)
	style.content_margin_left = 3.0
	style.content_margin_right = 3.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 5.0
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	# 形象小头像
	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(42, 42)
	icon_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var ib_border := GameStyle.JADE if is_selected else (GameStyle.GOLD_EDGE if is_unlocked else GameStyle.LINE)
	icon_box.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, ib_border, 1, 0.0))

	var icon_tex := TextureRect.new()
	if ResourceLoader.exists(String(def.get("icon", ""))):
		icon_tex.texture = load(String(def["icon"]))
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.custom_minimum_size = Vector2(36, 36)
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if not is_unlocked:
		icon_tex.modulate = Color(0.38, 0.38, 0.48, 0.68)
	icon_box.add_child(icon_tex)
	vbox.add_child(icon_box)

	# 人物名称（窄屏自动切 11 号字保证单行不撑破）
	var name_fsize := 12 if inner_w >= 78.0 else 11
	var raw_name := String(def.get("name", "?"))
	var name_lbl := Label.new()
	name_lbl.text = GameStyle.wrap_cjk(raw_name, GameStyle.display_font(), name_fsize, inner_w)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.custom_minimum_size = Vector2(inner_w, 0)
	var name_col := GameStyle.JADE if is_selected else (GameStyle.PAPER if is_unlocked else GameStyle.GREY)
	GameStyle.label(name_lbl, name_fsize, name_col, 0, GameStyle.INK, true)
	vbox.add_child(name_lbl)

	# 底部状态小签
	var tag_lbl := Label.new()
	tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if is_selected:
		tag_lbl.text = "◆ 当前 ◆"
		GameStyle.label(tag_lbl, 10, GameStyle.JADE)
	elif not is_unlocked:
		tag_lbl.text = "未解锁"
		GameStyle.label(tag_lbl, 10, GameStyle.GREY)
	elif best_d >= 0:
		tag_lbl.text = "★%s" % AchievementData.danger_name(best_d)
		GameStyle.label(tag_lbl, 10, GameStyle.JADE)
	else:
		tag_lbl.text = "已入门"
		GameStyle.label(tag_lbl, 10, GameStyle.PAPER_DIM)
	vbox.add_child(tag_lbl)

	card.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			_select_cultivator(cid)
	)
	GameStyle.hotzone(card)
	return card

func _unhandled_input(event: InputEvent) -> void:
	if not visible or _transitioning:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_step_selection(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
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
		var start_menu = get_parent().get_node_or_null("StartMenu")
		if start_menu != null and start_menu.has_method("open"):
			start_menu.open()
	)

func _choose(cid: String) -> void:
	if _transitioning:
		return
	_transitioning = true
	AudioManager.play_sfx("level_up", 0.9)
	GameManager.cultivator_id = cid
	if GameManager.player != null and is_instance_valid(GameManager.player) and GameManager.player.has_method("_setup_sprite_frames"):
		GameManager.player._setup_sprite_frames()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func():
		visible = false
		_transitioning = false
		# 选人三步曲：道统 → 随行神通 → 本命法器；旧档缺 SkillSelect 节点时回退直进法器
		var skill_select := get_parent().get_node_or_null("SkillSelect")
		if skill_select != null and skill_select.has_method("show_select"):
			skill_select.show_select()
		else:
			var weapon_select := get_parent().get_node_or_null("StartWeaponSelect")
			if weapon_select != null:
				weapon_select.show_select()
	)
