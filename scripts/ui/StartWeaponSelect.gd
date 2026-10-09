class_name StartWeaponSelect
extends Control

## 开局本命法器三选一：选择后才开始第一波

## 卡片宽度与左右内边距：折行宽度由这两个数算出来，别在别处再抄一遍 136
const CARD_W := 156.0
const CARD_H := 310.0
const CARD_PAD_X := 10.0

@onready var cards_container: HBoxContainer = $CenterContainer/Panel/MarginContainer/VBox/CardsContainer
@onready var title_label: Label = $CenterContainer/Panel/MarginContainer/VBox/TitleLabel
@onready var sub_label: Label = $CenterContainer/Panel/MarginContainer/VBox/SubLabel
@onready var hint_label: Label = $CenterContainer/Panel/MarginContainer/VBox/HintLabel

var _transitioning: bool = false

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_header_bar()
	GameStyle.label(title_label, 30, GameStyle.PAPER, 0, GameStyle.INK, true)
	GameStyle.label(sub_label, 14, GameStyle.PAPER_DIM)
	sub_label.text = "灵田妖潮将至，五行法器择其一，随你上阵斩妖"
	GameStyle.label(hint_label, 12, GameStyle.GREY)
	hint_label.text = "◆ 五行相协、法器共鸣：集齐三把同名同星法器可在商店手动升星 ◆"

func _setup_header_bar() -> void:
	var vbox: VBoxContainer = $CenterContainer/Panel/MarginContainer/VBox
	var header_row := HBoxContainer.new()
	header_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(header_row)
	vbox.move_child(header_row, 0)

	var back_btn := Button.new()
	back_btn.text = "〈 重选道统"
	back_btn.custom_minimum_size = Vector2(98, 34)
	back_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	back_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(back_btn, GameStyle.NAVY2, GameStyle.YELLOW, 13, GameStyle.PAPER, 5.0, GameStyle.INK_TEXT)
	back_btn.pressed.connect(_on_back_pressed)
	header_row.add_child(back_btn)

	var l_spacer := Control.new()
	l_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(l_spacer)

	vbox.remove_child(title_label)
	title_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	header_row.add_child(title_label)

	var r_spacer := Control.new()
	r_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(r_spacer)

	var dummy_r := Control.new()
	dummy_r.custom_minimum_size = Vector2(98, 34)
	dummy_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(dummy_r)

func show_select() -> void:
	_transitioning = false
	var cdef: Dictionary = CultivatorData.get_def(GameManager.cultivator_id)
	var cname: String = String(cdef.get("name", ""))
	var cepi: String = String(cdef.get("epithet", ""))
	if not cname.is_empty():
		sub_label.text = "已入道统 · %s「%s」 · 五行法器择其一" % [cname, cepi]
	else:
		sub_label.text = "灵田妖潮将至，五行法器择其一，随你上阵斩妖"
	for child in cards_container.get_children():
		child.queue_free()
	cards_container.add_theme_constant_override("separation", 10)
	var idx := 0
	for w_id in WeaponData.STARTER_IDS:
		var card = _create_card(w_id)
		cards_container.add_child(card)
		card.pivot_offset = Vector2(CARD_W * 0.5, CARD_H * 0.5)
		card.scale = Vector2(0.72, 0.72)
		card.modulate.a = 0.0
		var ctw = card.create_tween()
		ctw.tween_interval(float(idx) * 0.05)
		ctw.set_parallel(true)
		ctw.tween_property(card, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		ctw.tween_property(card, "modulate:a", 1.0, 0.16)
		idx += 1
	visible = true
	modulate.a = 0.0
	var tw = create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.25)

## 描述可用的那一条内宽：卡片宽减去左右内边距
static func _desc_w() -> float:
	return CARD_W - CARD_PAD_X * 2.0

## 判断某件法器是否契合当前所选道统（含 allowed_tags 或 tag_damage 加成）
static func is_recommended_for_cultivator(w_id: String, cid: String) -> bool:
	var wdef: Dictionary = WeaponData.get_def(w_id)
	var cdef: Dictionary = CultivatorData.get_def(cid)
	if wdef.is_empty() or cdef.is_empty():
		return false
	var w_tags: Array = wdef.get("tags", [])
	var allowed: Array = cdef.get("allowed_tags", [])
	for t in allowed:
		if t in w_tags:
			return true
	var mods: Dictionary = cdef.get("mods", {})
	var tag_dmg: Dictionary = mods.get("tag_damage", {})
	for t in tag_dmg.keys():
		if t in w_tags and float(tag_dmg[t]) > 0.0:
			return true
	return false

func _create_card(w_id: String) -> Control:
	var def := WeaponData.get_def(w_id)
	var rec := is_recommended_for_cultivator(w_id, GameManager.cultivator_id)
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_W, CARD_H)
	card.mouse_filter = Control.MOUSE_FILTER_PASS

	var base_border: Color = GameStyle.YELLOW if rec else GameStyle.BLUE.darkened(0.3)
	var style = StyleBoxFlat.new()
	style.bg_color = GameStyle.NAVY
	style.skew = Vector2(deg_to_rad(3.0), 0)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 5
	style.border_color = base_border
	style.shadow_color = Color(0, 0, 0, 0.55)
	style.shadow_size = 0
	style.shadow_offset = Vector2(5, 5)
	style.content_margin_left = CARD_PAD_X
	style.content_margin_top = 12.0
	style.content_margin_right = CARD_PAD_X
	style.content_margin_bottom = 12.0
	card.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 8)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	# 图标
	var icon_box = PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(74, 74)
	icon_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, GameStyle.YELLOW if rec else GameStyle.BLUE_EDGE, 2, 0.0))
	var icon_tex = TextureRect.new()
	if ResourceLoader.exists(def.get("icon", "")):
		icon_tex.texture = load(def["icon"])
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.custom_minimum_size = Vector2(60, 60)
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_child(icon_tex)
	vbox.add_child(icon_box)

	# 名称 + 星
	var name_lbl = Label.new()
	name_lbl.text = def.get("name", "?")
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lbl)
	GameStyle.label(name_lbl, 17, GameStyle.YELLOW if rec else GameStyle.PAPER, 0, GameStyle.INK, true)

	# 行为签（若契合当前道统则追加契合标识）
	var tag_lbl = Label.new()
	tag_lbl.text = (" ✦契合·%s " % def.get("tag", "")) if rec else (" " + def.get("tag", "") + " ")
	tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag_lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tag_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.YELLOW))
	vbox.add_child(tag_lbl)
	GameStyle.label(tag_lbl, 11, GameStyle.INK_TEXT)

	# 描述（换行切进文本，不交给引擎折行：见 GameStyle.wrap_cjk 头注）
	var desc_lbl = Label.new()
	desc_lbl.text = GameStyle.wrap_cjk(def.get("desc", ""), GameStyle.body_font(), 12, _desc_w())
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.custom_minimum_size = Vector2(_desc_w(), 0)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(desc_lbl)
	GameStyle.label(desc_lbl, 12, GameStyle.PAPER_DIM)

	# 选择按钮
	var btn = Button.new()
	btn.text = "执 此 器"
	btn.custom_minimum_size = Vector2(0, 36)
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	btn.focus_mode = Control.FOCUS_NONE
	if rec:
		GameStyle.button(btn, GameStyle.YELLOW, GameStyle.YELLOW_EDGE, 14, GameStyle.INK_TEXT, 5.0, GameStyle.INK_TEXT)
	else:
		GameStyle.button(btn, GameStyle.BLUE, GameStyle.YELLOW, 14, GameStyle.PAPER, 5.0, GameStyle.INK_TEXT)
	btn.pressed.connect(func(): _choose(w_id))
	vbox.add_child(btn)

	card.add_child(vbox)

	card.mouse_entered.connect(func():
		var tw = card.create_tween()
		tw.tween_property(card, "scale", Vector2(1.04, 1.04), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		style.border_color = GameStyle.YELLOW_EDGE if rec else GameStyle.BLUE_EDGE
	)
	card.mouse_exited.connect(func():
		var tw = card.create_tween()
		tw.tween_property(card, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		style.border_color = base_border
	)
	return card

func _unhandled_input(event: InputEvent) -> void:
	if not visible or _transitioning:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()

func _on_back_pressed() -> void:
	if not visible or _transitioning:
		return
	_transitioning = true
	AudioManager.play_sfx("ui_click")
	var tw = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.16)
	tw.tween_callback(func():
		visible = false
		_transitioning = false
		var cult_select = get_parent().get_node_or_null("CultivatorSelect")
		if cult_select != null and cult_select.has_method("show_select"):
			cult_select.show_select()
		else:
			var start_menu = get_parent().get_node_or_null("StartMenu")
			if start_menu != null and start_menu.has_method("open"):
				start_menu.open()
	)

func _choose(w_id: String) -> void:
	if _transitioning:
		return
	_transitioning = true
	AudioManager.play_sfx("level_up", 0.9)
	GameManager.start_run(w_id)
	var tw = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func():
		visible = false
		_transitioning = false
		get_tree().paused = false
	)
