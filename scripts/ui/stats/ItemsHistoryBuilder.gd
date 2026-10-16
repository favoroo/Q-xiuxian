class_name ItemsHistoryBuilder
extends RefCounted

## 属性面板下半区的单件构建：随身道具徽记（同名合并计数）与悟道历程行。
## 从 PlayerStatsDialog 拆出：填充编排在 dialog._refresh_items_and_history，
## 点按回调经 dialog 门面（_open_item_tip / _open_history_tip）。

## 随身道具徽记：档位描边 + 图标 + 「名号 ×n」，点按弹道具详解
static func create_item_badge(dialog: PlayerStatsDialog, item_id: String, count: int) -> Control:
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
	var sb_on := GameStyle.outlined_panel(GameStyle.NAVY2.lightened(0.1), GameStyle.JADE, 2, 0.0)
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
		var tex := GameStyle.icon_texture_rect(icon_path, Vector2(28, 28))
		hbox.add_child(tex)

	var name_lbl := Label.new()
	var name_str: String = String(def.get("name", item_id))
	name_lbl.text = "%s ×%d" % [name_str, count] if count > 1 else name_str
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	GameStyle.label(name_lbl, 12, GameStyle.PAPER)
	hbox.add_child(name_lbl)

	GameStyle.tap(badge, func() -> void: dialog._open_item_tip(item_id, count, badge))
	return badge

## 悟道历程行：序号 + 图标 + 稀有度色签 + 标题 + 等级，点按弹该次升级详情
static func create_history_row(dialog: PlayerStatsDialog, item: Dictionary, idx: int) -> Control:
	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var r_style := GameStyle.side_card(item.get("border_color", GameStyle.PAPER_DIM), 0.0)
	r_style.content_margin_left = 8.0
	r_style.content_margin_top = 3.0
	r_style.content_margin_right = 8.0
	r_style.content_margin_bottom = 3.0
	row.add_theme_stylebox_override("panel", r_style)
	var r_on := r_style.duplicate() as StyleBoxFlat
	r_on.bg_color = GameStyle.NAVY2.lightened(0.12)
	r_on.border_width_left = 5
	row.set_meta("sb_flat", r_style)
	row.set_meta("sb_on", r_on)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	GameStyle.tap(row, func() -> void: dialog._open_history_tip(item, idx, row))

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	row.add_child(hbox)

	var num_lbl := Label.new()
	num_lbl.text = "%02d." % idx
	GameStyle.label(num_lbl, 11, GameStyle.GREY)
	hbox.add_child(num_lbl)

	if item.has("icon") and ResourceLoader.exists(item["icon"]):
		var tex := GameStyle.icon_texture_rect(String(item["icon"]), Vector2(20, 20))
		hbox.add_child(tex)

	var pill := Label.new()
	pill.text = " " + item.get("rarity_label", "普通") + " "
	GameStyle.label(pill, 10, GameStyle.PAPER)
	var col: Color = item.get("border_color", GameStyle.PAPER)
	var pill_sb := GameStyle.block(col, GameStyle.SLANT_BAND, Vector2(1, 1))
	pill_sb.content_margin_top = 1.0
	pill_sb.content_margin_bottom = 1.0
	pill.add_theme_stylebox_override("normal", pill_sb)
	# 浅色带配黑字，深色带配暗底亮字（PAPER 已翻转为墨黑，深色带上会糊）
	var band_text_col: Color = GameStyle.on_face_text(col)
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
	GameStyle.label(lvl_lbl, 11, GameStyle.JADE)
	hbox.add_child(lvl_lbl)

	return row
