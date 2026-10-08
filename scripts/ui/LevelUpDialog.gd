class_name LevelUpDialog
extends Control

@onready var main_vbox: VBoxContainer = $CenterContainer/Panel/MarginContainer/VBox
@onready var cards_container: HBoxContainer = $CenterContainer/Panel/MarginContainer/VBox/CardsContainer
@onready var title_label: Label = $CenterContainer/Panel/MarginContainer/VBox/TitleBand/TitleLabel

var current_upgrades: Array[Dictionary] = []
var selected_index: int = -1
var _can_interact: bool = false
var _is_confirming: bool = false

## 保存每张卡片的组件引用以便切换选中/未选中视觉状态
var _card_entries: Array[Dictionary] = []
var _hint_label: Label

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameStyle.label(title_label, 24, GameStyle.PAPER, 0, GameStyle.INK, true)
	_build_hint_bar()
	GameManager.player_leveled_up.connect(_on_level_up)

func _build_hint_bar() -> void:
	var hint_panel := PanelContainer.new()
	hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.11, 0.85)
	sb.skew = Vector2(deg_to_rad(4.0), 0.0)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_color = GameStyle.LINE
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	hint_panel.add_theme_stylebox_override("panel", sb)

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameStyle.label(_hint_label, 13, GameStyle.PAPER_DIM)
	hint_panel.add_child(_hint_label)
	main_vbox.add_child(hint_panel)

func _on_level_up(level: int) -> void:
	# 1. 立即重置触屏摇杆状态，防止拖动摇杆升级时残留手指触发误触
	if GameManager.joystick != null and GameManager.joystick.has_method("_stop_joystick"):
		GameManager.joystick._stop_joystick()

	selected_index = -1
	_can_interact = false
	_is_confirming = false

	current_upgrades = UpgradeData.get_random_upgrades(3)
	title_label.text = "悟 道 加 点  ·  Lv." + str(level)
	_update_hint_text()
	_populate_cards()

	visible = true
	get_tree().paused = true
	modulate.a = 0.0
	var tw = create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.16)
	# 入场防误触保护窗口：动画播放完后才允许交互
	tw.tween_interval(0.14)
	tw.tween_callback(func(): _can_interact = true)

func _populate_cards() -> void:
	for child in cards_container.get_children():
		child.queue_free()
	_card_entries.clear()

	for i in range(current_upgrades.size()):
		var data = current_upgrades[i]
		var entry := _create_card_entry(data, i)
		_card_entries.append(entry)
		var card_col: Control = entry["root"]
		cards_container.add_child(card_col)
		card_col.pivot_offset = Vector2(131.0, 195.0)
		card_col.scale = Vector2(0.75, 0.75)
		card_col.modulate.a = 0.0
		var ctw = card_col.create_tween()
		ctw.tween_interval(float(i) * 0.055)
		ctw.set_parallel(true)
		ctw.tween_property(card_col, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		ctw.tween_property(card_col, "modulate:a", 1.0, 0.16)

func _create_card_entry(data: Dictionary, index: int) -> Dictionary:
	# 外层垂直容器：上方卡片展示面板 + 下方独立两段式确认按钮
	var col_box := VBoxContainer.new()
	col_box.custom_minimum_size = Vector2(262.0, 0.0)
	col_box.add_theme_constant_override("separation", 10)
	col_box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(262.0, 300.0)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.pivot_offset = Vector2(131.0, 150.0)

	var rarity_col: Color = data.get("border_color", GameStyle.PAPER)
	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = Color(GameStyle.NAVY.r, GameStyle.NAVY.g, GameStyle.NAVY.b, 0.985)
	style_normal.skew = Vector2(deg_to_rad(3.0), 0.0)
	style_normal.border_width_left = 2
	style_normal.border_width_top = 2
	style_normal.border_width_right = 2
	style_normal.border_width_bottom = 5
	style_normal.border_color = rarity_col
	style_normal.shadow_color = Color(0, 0, 0, 0.6)
	style_normal.shadow_size = 0
	style_normal.shadow_offset = Vector2(6, 6)
	style_normal.content_margin_left = 16.0
	style_normal.content_margin_top = 14.0
	style_normal.content_margin_right = 16.0
	style_normal.content_margin_bottom = 14.0
	card.add_theme_stylebox_override("panel", style_normal)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 9)

	# 1. 顶部稀有度斜切色签 + 选中状态指示
	var hbox_top := HBoxContainer.new()
	hbox_top.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var rarity_lbl := Label.new()
	rarity_lbl.text = " " + data.get("rarity_label", "凡品") + " "
	GameStyle.label(rarity_lbl, 12, GameStyle.PAPER)
	var band_text_col: Color = GameStyle.INK_TEXT if rarity_col.get_luminance() > 0.5 else GameStyle.PAPER
	rarity_lbl.add_theme_color_override("font_color", band_text_col)
	var pill_style := GameStyle.block(rarity_col, GameStyle.SLANT_BAND, Vector2(2, 2))
	pill_style.content_margin_top = 2.0
	pill_style.content_margin_bottom = 2.0
	rarity_lbl.add_theme_stylebox_override("normal", pill_style)
	hbox_top.add_child(rarity_lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox_top.add_child(spacer)

	var state_badge := Label.new()
	var count_already: int = int(GameManager.upgrade_counts.get(data.get("id", ""), 0))
	state_badge.text = "已修 %d 层" % count_already if count_already > 0 else "点击选择"
	GameStyle.label(state_badge, 12, GameStyle.GREY)
	hbox_top.add_child(state_badge)
	vbox.add_child(hbox_top)

	# 2. 中央图标（墨底白框）
	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(68, 68)
	icon_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_panel_style := GameStyle.outlined_panel(GameStyle.INK, GameStyle.PAPER_DIM, 2, 0.0)
	icon_box.add_theme_stylebox_override("panel", icon_panel_style)

	var icon_tex := TextureRect.new()
	if data.has("icon") and ResourceLoader.exists(data["icon"]):
		icon_tex.texture = load(data["icon"])
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.custom_minimum_size = Vector2(52, 52)
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_child(icon_tex)
	vbox.add_child(icon_box)

	# 3. 名称（纸白大字）
	var title_lbl := Label.new()
	title_lbl.text = data["title"]
	GameStyle.label(title_lbl, 19, GameStyle.PAPER)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title_lbl)

	# 4. 分隔线（稀有度色）
	var sep := HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sep_style := StyleBoxLine.new()
	sep_style.color = Color(rarity_col.r, rarity_col.g, rarity_col.b, 0.45)
	sep_style.thickness = 2
	sep.add_theme_stylebox_override("separator", sep_style)
	vbox.add_child(sep)

	# 5. 描述富文本
	var r_desc := RichTextLabel.new()
	r_desc.bbcode_enabled = true
	r_desc.text = data["desc"]
	r_desc.fit_content = true
	r_desc.scroll_active = false
	r_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	r_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r_desc.add_theme_font_override("normal_font", GameStyle.body_font())
	r_desc.add_theme_font_override("bold_font", GameStyle.body_font())
	r_desc.add_theme_font_size_override("normal_font_size", 13)
	r_desc.add_theme_font_size_override("bold_font_size", 13)
	r_desc.add_theme_color_override("default_color", Color(0.85, 0.87, 0.94))
	vbox.add_child(r_desc)

	card.add_child(vbox)
	col_box.add_child(card)

	# 6. 卡片下方的独立两段式按钮（第1次点击：选择；第2次点击：确认领悟）
	var btn := Button.new()
	btn.text = "选  择"
	btn.custom_minimum_size = Vector2(0, 44)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.focus_mode = Control.FOCUS_NONE
	btn.pivot_offset = Vector2(131.0, 22.0)
	GameStyle.button(btn, GameStyle.NAVY2, GameStyle.BLUE, 15, GameStyle.PAPER, 6.0)
	col_box.add_child(btn)

	# 点击卡片本体：仅触发第1步「选中该卡片」，不直接加点，防止误触
	card.gui_input.connect(func(event: InputEvent):
		if not _can_interact or _is_confirming:
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_on_card_body_clicked(index)
	)

	# 点击卡片下方按钮：未选中时先选中；已选中时再次点击才确认加点
	btn.pressed.connect(func():
		if not _can_interact or _is_confirming:
			return
		_on_card_button_pressed(index)
	)

	return {
		"root": col_box,
		"card": card,
		"style": style_normal,
		"icon_panel_style": icon_panel_style,
		"rarity_col": rarity_col,
		"state_badge": state_badge,
		"title_lbl": title_lbl,
		"btn": btn,
		"data": data,
	}

func _on_card_body_clicked(index: int) -> void:
	if selected_index != index:
		_select_card(index)

func _on_card_button_pressed(index: int) -> void:
	if selected_index != index:
		# 第一次点击按钮：选中该卡片，按钮变为「确认领悟」
		_select_card(index)
	else:
		# 第二次点击同一按钮：正式确认加点
		var up_id: String = current_upgrades[index].get("id", "")
		_confirm_upgrade(up_id)

func _select_card(index: int) -> void:
	selected_index = index
	AudioManager.play_sfx("gem_pickup", 0.95)
	_update_hint_text()

	for i in range(_card_entries.size()):
		var entry: Dictionary = _card_entries[i]
		var card: PanelContainer = entry["card"]
		var style: StyleBoxFlat = entry["style"]
		var icon_st: StyleBoxFlat = entry["icon_panel_style"]
		var rarity_col: Color = entry["rarity_col"]
		var badge: Label = entry["state_badge"]
		var title_lbl: Label = entry["title_lbl"]
		var btn: Button = entry["btn"]
		var data: Dictionary = entry["data"]
		var is_sel: bool = (i == selected_index)

		var tw := card.create_tween()
		tw.set_parallel(true)

		if is_sel:
			# 选中态：卡片微放大高亮、金框、按钮变为金色「确认领悟」
			tw.tween_property(card, "scale", Vector2(1.035, 1.035), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(card, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.12)
			style.bg_color = Color(0.10, 0.15, 0.28, 0.99)
			style.border_width_left = 3
			style.border_width_top = 3
			style.border_width_right = 3
			style.border_width_bottom = 6
			style.border_color = GameStyle.YELLOW
			icon_st.border_color = GameStyle.YELLOW
			title_lbl.add_theme_color_override("font_color", GameStyle.YELLOW)
			badge.text = "✦ 已选中"
			badge.add_theme_color_override("font_color", GameStyle.YELLOW)

			btn.text = "确 认 领 悟 ✓"
			GameStyle.button(btn, GameStyle.YELLOW, GameStyle.YELLOW_EDGE, 16, GameStyle.INK_TEXT, 6.0, GameStyle.INK_TEXT)
			btn.scale = Vector2(0.92, 0.92)
			var btw := btn.create_tween()
			btw.tween_property(btn, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			# 未选中态：轻微压暗退后，按钮重置为「选择」
			tw.tween_property(card, "scale", Vector2(0.97, 0.97), 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(card, "modulate", Color(0.78, 0.80, 0.86, 0.78), 0.12)
			style.bg_color = Color(GameStyle.NAVY.r, GameStyle.NAVY.g, GameStyle.NAVY.b, 0.96)
			style.border_width_left = 2
			style.border_width_top = 2
			style.border_width_right = 2
			style.border_width_bottom = 5
			style.border_color = rarity_col
			icon_st.border_color = GameStyle.PAPER_DIM
			title_lbl.add_theme_color_override("font_color", GameStyle.PAPER)
			var count_already: int = int(GameManager.upgrade_counts.get(data.get("id", ""), 0))
			badge.text = "已修 %d 层" % count_already if count_already > 0 else "点击选择"
			badge.add_theme_color_override("font_color", GameStyle.GREY)

			btn.text = "选  择"
			GameStyle.button(btn, GameStyle.NAVY2, GameStyle.BLUE, 15, GameStyle.PAPER, 6.0)
			btn.scale = Vector2.ONE

func _update_hint_text() -> void:
	if _hint_label == null:
		return
	if selected_index < 0 or selected_index >= current_upgrades.size():
		_hint_label.text = "提示：请先点击下方按钮「选择」心仪法门，再次点击「确认领悟」即可生效（防误触）"
		_hint_label.add_theme_color_override("font_color", GameStyle.PAPER_DIM)
	else:
		var sel_title: String = current_upgrades[selected_index].get("title", "")
		_hint_label.text = "✦ 已选定【%s】 —— 请再次点击下方金色「确认领悟 ✓」按钮完成加点 ✦" % sel_title
		_hint_label.add_theme_color_override("font_color", GameStyle.YELLOW)

func _confirm_upgrade(upgrade_id: String) -> void:
	if _is_confirming:
		return
	_is_confirming = true
	_can_interact = false

	GameManager.apply_upgrade(upgrade_id)
	AudioManager.play_sfx("gem_pickup", 1.25)

	var tw = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.12)
	tw.tween_callback(func():
		visible = false
		get_tree().paused = false
		_is_confirming = false
	)
