class_name ChangelogDialog
extends BaseModalDialog

## 历史更新记录弹窗
## 遵循 BaseModalDialog 规范与 GameStyle 斜切大色块风格。
## 供玩家在游戏内直接翻阅版本演进史与更新说明。

func _get_title_text() -> String:
	return "更 新 历 史 记 录"

func _get_panel_size() -> Vector2:
	return Vector2(740, 440)

func _get_panel_margins() -> Vector4:
	return Vector4(24, 16, 24, 16)

func _get_vbox_separation() -> int:
	return 12

func _build_body(root_vbox: VBoxContainer) -> void:
	var sub_bar := HBoxContainer.new()
	sub_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	root_vbox.add_child(sub_bar)

	var sub_lbl := Label.new()
	sub_lbl.text = "✦ 记录《剑士》各版本演进轨迹、核心玩法拓展与优化细节 ✦"
	GameStyle.label(sub_lbl, 12, GameStyle.PAPER_DIM)
	sub_bar.add_child(sub_lbl)

	var content_panel := PanelContainer.new()
	content_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var cont_sb := GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 2, 0.0)
	cont_sb.content_margin_left = 14.0
	cont_sb.content_margin_top = 12.0
	cont_sb.content_margin_right = 14.0
	cont_sb.content_margin_bottom = 12.0
	content_panel.add_theme_stylebox_override("panel", cont_sb)
	root_vbox.add_child(content_panel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_panel.add_child(scroll)

	var list_vbox := VBoxContainer.new()
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_vbox.add_theme_constant_override("separation", 12)
	scroll.add_child(list_vbox)

	var logs := ChangelogData.get_logs()
	for log_entry in logs:
		var card := _build_version_card(log_entry)
		list_vbox.add_child(card)

	GameStyle.scrollable(scroll)
	GameStyle.swipeable(scroll)

func _build_version_card(log_entry: Dictionary) -> Control:
	var ver_str: String = str(log_entry.get("version", ""))
	var is_current: bool = ver_str == Version.APP_VERSION_NAME or ver_str.ends_with(Version.APP_VERSION)

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var border_color: Color = GameStyle.JADE if is_current else GameStyle.LINE
	var border_w: int = 2 if is_current else 1
	var card_sb := GameStyle.outlined_panel(GameStyle.NAVY2, border_color, border_w, 0.0)
	card_sb.content_margin_left = 14.0
	card_sb.content_margin_top = 10.0
	card_sb.content_margin_right = 14.0
	card_sb.content_margin_bottom = 10.0
	card.add_theme_stylebox_override("panel", card_sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	card.add_child(vbox)

	# 顶部标题行
	var head_hbox := HBoxContainer.new()
	head_hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(head_hbox)

	var ver_lbl := Label.new()
	ver_lbl.text = "✦ " + ver_str
	GameStyle.label(ver_lbl, 15, GameStyle.JADE if is_current else GameStyle.GOLD)
	head_hbox.add_child(ver_lbl)

	var date_lbl := Label.new()
	date_lbl.text = str(log_entry.get("date", ""))
	GameStyle.label(date_lbl, 11, GameStyle.GREY)
	head_hbox.add_child(date_lbl)

	var title_lbl := Label.new()
	title_lbl.text = "· " + str(log_entry.get("title", ""))
	GameStyle.label(title_lbl, 13, GameStyle.PAPER)
	head_hbox.add_child(title_lbl)

	# 弹性占位
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_hbox.add_child(spacer)

	if is_current:
		var cur_tag := Label.new()
		cur_tag.text = "【当前版本】"
		GameStyle.label(cur_tag, 12, GameStyle.JADE)
		head_hbox.add_child(cur_tag)

	# 更新明细条目
	var items = log_entry.get("items", [])
	if items is Array:
		var items_vbox := VBoxContainer.new()
		items_vbox.add_theme_constant_override("separation", 3)
		vbox.add_child(items_vbox)

		for item in items:
			var item_lbl := Label.new()
			item_lbl.text = "  · " + str(item)
			item_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			GameStyle.label(item_lbl, 12, GameStyle.PAPER_DIM if not is_current else GameStyle.PAPER)
			items_vbox.add_child(item_lbl)

	return card
