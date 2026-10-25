class_name CodexCardFactory
extends RefCounted

## 图鉴 / 作者面板共用的条目卡工厂：图标 + 名称（+ 可选色签行 / 副标签 + 可选关键数值行）。
##
## 2026-10-22 作者面板改版抽出：作者面板的武器/道具/灵兽卡要与图鉴同一副样子
## （同卡宽、同图标框、同色签行），否则同一件东西在两屏上长得不一样、没法扫着比。
## chips = [[文字, 面色, 字色], ...]，给了 chips 就不画 sub 那行灰字（同一件事不印两遍）。

const CARD_W := 148.0

## 造一张条目卡。on_press 收到的参数是卡本体（详情卡贴它摆位）。
## tint 仅在 icon 为空时使用：灵兽没有位图图标（战斗里是程序化光灵），画一颗主体色圆点占位。
static func make_entry_card(icon: String, name: String, sub: String, sub_color: Color,
		on_press: Callable, stat_line: String = "", chips: Array = [],
		tint: Color = Color(-1, -1, -1, -1)) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_W, 0)
	var sb := GameStyle.block(GameStyle.NAVY2, GameStyle.SLANT_PLATE, Vector2(2, 3))
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	card.add_theme_stylebox_override("panel", sb)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.set_meta("tip_title", name)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	var icon_center := CenterContainer.new()
	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(48, 48)
	icon_box.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 1, 0.0))
	if icon.is_empty() and tint.a > 0.0:
		# 灵兽占位：与图鉴灵兽页同一颗圆点（主体色 + 高光点）
		var dot := Control.new()
		dot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.draw.connect(func() -> void:
			var c := dot.size * 0.5
			dot.draw_circle(c, minf(dot.size.x, dot.size.y) * 0.30, tint)
			dot.draw_circle(c, minf(dot.size.x, dot.size.y) * 0.15, Color(1, 1, 1, 0.55))
		)
		icon_box.add_child(dot)
	else:
		var tex := GameStyle.icon_texture_rect(icon, Vector2(40, 40))
		tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tex.offset_left = 4
		tex.offset_top = 4
		tex.offset_right = -4
		tex.offset_bottom = -4
		icon_box.add_child(tex)
		card.set_meta("icon_tex", tex)
	icon_center.add_child(icon_box)
	vbox.add_child(icon_center)

	var name_lbl := Label.new()
	name_lbl.text = name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameStyle.label(name_lbl, 13, GameStyle.PAPER, 0, GameStyle.INK, true)
	vbox.add_child(name_lbl)
	# 暴露名字 Label：调用方要挂「新」角标时直接改它，不必再遍历子树找 Label
	card.set_meta("name_lbl", name_lbl)

	if not chips.is_empty():
		# 色签成排：摆得下就一行，摆不下自动折第二行（图鉴卡窄，双器类武器有 4 签）
		var flow := HFlowContainer.new()
		flow.name = "TagFlow"
		flow.alignment = FlowContainer.ALIGNMENT_CENTER
		flow.add_theme_constant_override("h_separation", 4)
		flow.add_theme_constant_override("v_separation", 3)
		vbox.add_child(flow)
		for cd in chips:
			flow.add_child(GameStyle.chip_label(String(cd[0]), cd[1] as Color, cd[2] as Color))
	elif sub != "":
		var sub_lbl := Label.new()
		sub_lbl.text = sub
		sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		GameStyle.label(sub_lbl, 11, sub_color)
		vbox.add_child(sub_lbl)

	if stat_line != "":
		var stat_lbl := Label.new()
		stat_lbl.text = stat_line
		stat_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		GameStyle.label(stat_lbl, 10, GameStyle.PAPER_DIM)
		vbox.add_child(stat_lbl)

	GameStyle.tap(card, func() -> void: on_press.call(card))
	# 整格都是热区：图框那层 PanelContainer 默认 STOP，会把「点图片」这一枪截在半路
	# （用户 2026-10-09 真机：点名字弹卡、点图片没反应）。放在最后一步统一压子树。
	GameStyle.hotzone(card)
	return card


## 纯文字段卡：段题（黄）+ 可选插图 + 正文（wrap_cjk 硬换行）。图鉴与作者面板共用。
static func make_text_card(title: String, body: String, text_w: float,
		image: String = "", image_h: float = 80.0) -> Control:
	var card := PanelContainer.new()
	var sb := GameStyle.block(GameStyle.NAVY2, GameStyle.SLANT_PLATE, Vector2(2, 3))
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	card.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	card.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = "◆ " + title
	GameStyle.label(title_lbl, 15, GameStyle.JADE_DK, 0, GameStyle.INK, true)
	vbox.add_child(title_lbl)

	if image != "" and ResourceLoader.exists(image):
		var img_center := CenterContainer.new()
		var tex := TextureRect.new()
		tex.texture = load(image)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(image_h * 2.0, image_h)
		img_center.add_child(tex)
		vbox.add_child(img_center)

	# 正文走 RichTextLabel：名词与数值由 colorize_terms 自动上语义色（文案表里仍是纯文本）。
	# 换行必须用 wrap_bbcode —— 纯文本的 wrap_cjk 会把 [color] 标签当可见字符切断。
	var body_lbl := RichTextLabel.new()
	body_lbl.bbcode_enabled = true
	body_lbl.fit_content = true
	body_lbl.scroll_active = false
	body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body_lbl.custom_minimum_size = Vector2(text_w, 0)
	body_lbl.add_theme_font_override("normal_font", GameStyle.body_font())
	body_lbl.add_theme_font_override("bold_font", GameStyle.emph_font())
	body_lbl.add_theme_font_size_override("normal_font_size", 13)
	body_lbl.add_theme_font_size_override("bold_font_size", 13)
	body_lbl.add_theme_color_override("default_color", GameStyle.PAPER_DIM)
	body_lbl.text = GameStyle.wrap_bbcode(
		GameStyle.colorize_terms(body), GameStyle.body_font(), 13, text_w)
	vbox.add_child(body_lbl)

	return card
