class_name CultivatorSelect
extends Control

## 开局道统四选一：每名修士都是「超能力 + 严苛负面代偿」的不对称设计
## 流程：StartMenu → CultivatorSelect → StartWeaponSelect（全程保持 paused）

var _cards_container: HBoxContainer
var _title_label: Label
var _sub_label: Label

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

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)

	_title_label = Label.new()
	_title_label.text = "选 择 道 统"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title_label)
	GameStyle.label(_title_label, 34, GameStyle.PAPER, 0, GameStyle.INK, true)

	_sub_label = Label.new()
	_sub_label.text = "每位修士都有独门天赋，也有必须背负的代价"
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_sub_label)
	GameStyle.label(_sub_label, 15, GameStyle.PAPER_DIM)

	_cards_container = HBoxContainer.new()
	_cards_container.add_theme_constant_override("separation", 16)
	_cards_container.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(_cards_container)

func show_select() -> void:
	for child in _cards_container.get_children():
		child.queue_free()
	var idx := 0
	for cid in CultivatorData.all_ids():
		var card := _create_card(cid)
		_cards_container.add_child(card)
		card.pivot_offset = Vector2(105.0, 190.0)
		card.scale = Vector2(0.72, 0.72)
		card.modulate.a = 0.0
		var ctw := card.create_tween()
		ctw.tween_interval(float(idx) * 0.06)
		ctw.set_parallel(true)
		ctw.tween_property(card, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		ctw.tween_property(card, "modulate:a", 1.0, 0.18)
		idx += 1
	visible = true
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.25)

func _create_card(cid: String) -> Control:
	var def: Dictionary = CultivatorData.get_def(cid)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(210.0, 380.0)
	card.mouse_filter = Control.MOUSE_FILTER_PASS

	var style := StyleBoxFlat.new()
	style.bg_color = GameStyle.NAVY
	style.skew = Vector2(deg_to_rad(3.0), 0)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 5
	style.border_color = GameStyle.BLUE.darkened(0.3)
	style.shadow_color = Color(0, 0, 0, 0.55)
	style.shadow_size = 0
	style.shadow_offset = Vector2(6, 6)
	style.content_margin_left = 12.0
	style.content_margin_top = 14.0
	style.content_margin_right = 12.0
	style.content_margin_bottom = 12.0
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 8)

	# 图标
	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(72, 72)
	icon_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, GameStyle.BLUE_EDGE, 2, 0.0))
	var icon_tex := TextureRect.new()
	if ResourceLoader.exists(def.get("icon", "")):
		icon_tex.texture = load(def["icon"])
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.custom_minimum_size = Vector2(58, 58)
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_child(icon_tex)
	vbox.add_child(icon_box)

	# 名称与称号
	var name_lbl := Label.new()
	name_lbl.text = def.get("name", "?")
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lbl)
	GameStyle.label(name_lbl, 19, GameStyle.PAPER, 0, GameStyle.INK, true)

	var epithet_lbl := Label.new()
	epithet_lbl.text = " " + def.get("epithet", "") + " "
	epithet_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	epithet_lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	epithet_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.BLUE))
	vbox.add_child(epithet_lbl)
	GameStyle.label(epithet_lbl, 11, GameStyle.PAPER)

	# 天赋（绿）与代价（红）
	for line in def.get("pros", []):
		var l := Label.new()
		l.text = "✦ " + line
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		vbox.add_child(l)
		GameStyle.label(l, 12, GameStyle.GOOD)
	for line in def.get("cons", []):
		var l := Label.new()
		l.text = "✖ " + line
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		vbox.add_child(l)
		GameStyle.label(l, 12, GameStyle.BAD)

	# 撑开把按钮压到底部
	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(grow)

	var btn := Button.new()
	btn.text = "拜 入 此 门"
	btn.custom_minimum_size = Vector2(0, 38)
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(btn, GameStyle.BLUE, GameStyle.YELLOW, 15, GameStyle.PAPER, 6.0, GameStyle.INK_TEXT)
	btn.pressed.connect(func(): _choose(cid))
	vbox.add_child(btn)

	card.add_child(vbox)

	card.mouse_entered.connect(func():
		var tw := card.create_tween()
		tw.tween_property(card, "scale", Vector2(1.04, 1.04), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		style.border_color = GameStyle.BLUE_EDGE
	)
	card.mouse_exited.connect(func():
		var tw := card.create_tween()
		tw.tween_property(card, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		style.border_color = GameStyle.BLUE.darkened(0.3)
	)
	return card

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
