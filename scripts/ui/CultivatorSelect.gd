class_name CultivatorSelect
extends Control

## 开局道统择选：每名修士都是「超能力 + 严苛负面代偿」的不对称设计
## 流程：StartMenu → CultivatorSelect → StartWeaponSelect（全程保持 paused）
##
## 为什么是「可上下滑的名单」而不是一排卡片（2026-10-08 用户拍板）：
## 修士加到 9 名后，一排卡片横着 9×210 = 1890 单位远超 20:9 屏的 1202 可视宽，
## 两头各几张卡直接出屏；卡内文案按内宽折行后又要 591 高 > 540 屏高，
## 「拜入此门」整排落在屏外点不到 —— 不崩不报错，只有真机看得见。
## 名单一行一人：图标｜名号+称号｜天赋（绿）｜代价（红）｜那颗键，
## 一屏看得见四五个、上下滑看完九个，按钮永远在它那一行的行尾。

const EDGE := 24.0        # 名单左右留的屏边
const ROW_PAD_X := 10.0   # 行内左右边距
const ICON := 48.0
const NAME_COL := 150.0
const BTN_W := 96.0
const GAP := 12.0         # 各列之间
const SCROLL_W := 14.0    # 竖向滚动条占的宽：算列宽时要先扣掉，不然整行比可视区宽
const TXT := 12           # 天赋/代价字号

var _title_label: Label
var _sub_label: Label
var _scroll: ScrollContainer
var _list: VBoxContainer

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.04, 0.09, 0.88)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", int(EDGE))
	margin.add_theme_constant_override("margin_right", int(EDGE))
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vbox)

	_title_label = Label.new()
	_title_label.text = "选 择 道 统"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(_title_label)
	GameStyle.label(_title_label, 28, GameStyle.PAPER, 0, GameStyle.INK, true)

	_sub_label = Label.new()
	_sub_label.text = "每位修士都有独门天赋，也有必须背负的代价 · 上下滑动看全九人"
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(_sub_label)
	GameStyle.label(_sub_label, 13, GameStyle.PAPER_DIM)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	vbox.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(_list)

func show_select() -> void:
	for child in _list.get_children():
		child.queue_free()
	var ids: Array = CultivatorData.all_ids()
	var col_w := text_col_w(get_viewport().get_visible_rect().size.x)
	for cid in ids:
		_list.add_child(_create_row(cid, col_w))
	visible = true
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.25)

## 天赋列/代价列各有多宽：整屏宽减掉左右屏边、行内边距、图标、名号列、按钮与列间距，
## 剩下的平分给两列。名单要横向不出屏（只有竖向能滑），所以这一列宽必须现算。
## 纯函数 ⇒ 判据 LayoutCheck 直接吃它，不另抄一份算术。
static func text_col_w(vis_w: float) -> float:
	var row_w := vis_w - EDGE * 2.0 - SCROLL_W
	var used := ROW_PAD_X * 2.0 + ICON + NAME_COL + BTN_W + GAP * 4.0
	return maxf(120.0, (row_w - used) * 0.5)

func _create_row(cid: String, col_w: float) -> Control:
	var def: Dictionary = CultivatorData.get_def(cid)
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS

	var style := StyleBoxFlat.new()
	style.bg_color = GameStyle.NAVY
	style.skew = Vector2(deg_to_rad(3.0), 0)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 5
	style.border_color = GameStyle.BLUE.darkened(0.35)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 0
	style.shadow_offset = Vector2(4, 4)
	style.content_margin_left = ROW_PAD_X
	style.content_margin_top = 8.0
	style.content_margin_right = ROW_PAD_X
	style.content_margin_bottom = 8.0
	row.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", int(GAP))
	row.add_child(hbox)

	# 图标
	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(ICON, ICON)
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, GameStyle.BLUE_EDGE, 2, 0.0))
	var icon_tex := TextureRect.new()
	if ResourceLoader.exists(def.get("icon", "")):
		icon_tex.texture = load(def["icon"])
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.custom_minimum_size = Vector2(ICON - 8, ICON - 8)
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_child(icon_tex)
	hbox.add_child(icon_box)

	# 名号 + 称号
	var name_col := VBoxContainer.new()
	name_col.custom_minimum_size = Vector2(NAME_COL, 0)
	name_col.add_theme_constant_override("separation", 4)
	name_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(name_col)

	var name_lbl := Label.new()
	name_lbl.text = GameStyle.wrap_cjk(def.get("name", "?"), GameStyle.display_font(), 17, NAME_COL)
	name_lbl.custom_minimum_size = Vector2(NAME_COL, 0)
	name_col.add_child(name_lbl)
	GameStyle.label(name_lbl, 17, GameStyle.PAPER, 0, GameStyle.INK, true)

	var epi_txt := GameStyle.wrap_cjk(" " + def.get("epithet", "") + " ", GameStyle.body_font(), 10, NAME_COL - 8.0)
	var epithet_lbl := Label.new()
	epithet_lbl.text = epi_txt
	epithet_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 折行的控件必须钉住折行宽：不钉，容器按「一个汉字那么宽」去量它，
	# 称号会被竖着一字一行排到 191 高（判据 LayoutCheck 量 rect 抓到的就是这一格）
	epithet_lbl.custom_minimum_size = Vector2(GameStyle.chip_pin_w(epi_txt, GameStyle.body_font(), 10), 0)
	epithet_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	epithet_lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	epithet_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.BLUE))
	name_col.add_child(epithet_lbl)
	GameStyle.label(epithet_lbl, 10, GameStyle.PAPER)

	# 天赋（绿）与代价（红）：两列并排，各占算出来的列宽
	hbox.add_child(_make_text_col(def.get("pros", []), "✦ ", GameStyle.GOOD, col_w))
	hbox.add_child(_make_text_col(def.get("cons", []), "✖ ", GameStyle.BAD, col_w))

	# 行尾那颗键：跟着这一行走，不落在屏外
	var btn := Button.new()
	btn.text = "拜 入 此 门"
	btn.custom_minimum_size = Vector2(BTN_W, 38)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(btn, GameStyle.BLUE, GameStyle.YELLOW, 14, GameStyle.PAPER, 6.0, GameStyle.INK_TEXT)
	btn.pressed.connect(func(): _choose(cid))
	hbox.add_child(btn)

	return row

## 一列条目（每个条目一条文案，已按列宽切好硬换行）
func _make_text_col(items: Array, mark: String, col: Color, col_w: float) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for line in items:
		var l := Label.new()
		l.text = GameStyle.wrap_cjk(mark + line, GameStyle.body_font(), TXT, col_w)
		l.custom_minimum_size = Vector2(col_w, 0)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(l)
		GameStyle.label(l, TXT, col)
	return box

func _choose(cid: String) -> void:
	AudioManager.play_sfx("level_up", 0.9)
	GameManager.cultivator_id = cid
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func():
		visible = false
		var weapon_select := get_parent().get_node_or_null("StartWeaponSelect")
		if weapon_select != null:
			weapon_select.show_select()
	)
