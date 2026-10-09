class_name SkillSelect
extends Control

## 随行神通五选一：选完道统后进入，选定后转本命法器六选一
## 道统契合判定与强化文案全部走 SkillData（is_enhanced_for_cultivator / enhance_desc），本地不抄数值

## 卡片宽按屏宽现算（与本命法器同一套算术）：5 卡写死 156 时 720 宽整排要 820，左右出屏。
const CARD_H := 310.0
const CARD_PAD_X := 10.0
const CARD_SEP := 10.0
## 面板侧向总吃掉的宽：内边距 40×2 + 斜切出血与硬影留量 24
const PANEL_CHROME_X := 104.0
const PANEL_MIN_H := 470.0

@onready var cards_container: HBoxContainer = $CenterContainer/Panel/MarginContainer/VBox/CardsContainer
@onready var title_label: Label = $CenterContainer/Panel/MarginContainer/VBox/TitleLabel
@onready var sub_label: Label = $CenterContainer/Panel/MarginContainer/VBox/SubLabel
@onready var hint_label: Label = $CenterContainer/Panel/MarginContainer/VBox/HintLabel

var _transitioning: bool = false
var _card_w := 156.0

## 一屏摆 n 张卡时每张的宽（纯函数，判据可拿同一份算术量文案）
static func card_w_for(screen_w: float, count: int) -> float:
	var avail := screen_w - PANEL_CHROME_X - CARD_SEP * float(count - 1)
	return clampf(avail / float(count), 88.0, 156.0)

## 图标框随卡宽缩：窄屏卡的内宽装不下 74 的满配图标框
static func icon_size_for(card_w: float) -> float:
	return clampf(card_w - CARD_PAD_X * 2.0 - 4.0, 56.0, 74.0)

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 面板样式收口到 GameStyle（旧版在 .tscn 里钉死 900 宽 + 旧蓝色板 + 不画的投影）
	var panel: PanelContainer = $CenterContainer/Panel
	var st := GameStyle.dialog_panel(GameStyle.LINE, GameStyle.SLANT_PLATE, Vector2(10, 10))
	st.content_margin_left = 24.0
	st.content_margin_top = 20.0
	st.content_margin_right = 24.0
	st.content_margin_bottom = 18.0
	panel.add_theme_stylebox_override("panel", st)
	panel.custom_minimum_size = Vector2(0, PANEL_MIN_H)
	_setup_header_bar()
	GameStyle.label(title_label, 30, GameStyle.PAPER, 0, GameStyle.INK, true)
	GameStyle.label(sub_label, 14, GameStyle.PAPER_DIM)
	GameStyle.label(hint_label, 12, GameStyle.GREY)
	hint_label.text = "◆ 金边为道统契合神通：所选道统对它加持专属强化 ◆"

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
	GameStyle.button(back_btn, GameStyle.NAVY2, GameStyle.JADE, 13, GameStyle.PAPER, 5.0, GameStyle.INK_TEXT)
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
		sub_label.text = "已入道统 · %s「%s」 · 随行神通择其一" % [cname, cepi]
	else:
		sub_label.text = "灵田妖潮将至，择一门随行神通，应劫保命"
	for child in cards_container.get_children():
		child.queue_free()
	_card_w = card_w_for(get_viewport_rect().size.x, SkillData.OFFER_IDS.size())
	cards_container.add_theme_constant_override("separation", int(CARD_SEP))
	var idx := 0
	for s_id in SkillData.OFFER_IDS:
		var card = _create_card(s_id)
		cards_container.add_child(card)
		card.pivot_offset = Vector2(_card_w * 0.5, CARD_H * 0.5)
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

## 描述可用的那一条内宽：本次摆卡的卡宽减去左右内边距
func _desc_w() -> float:
	return _card_w - CARD_PAD_X * 2.0

func _create_card(s_id: String) -> Control:
	var def := SkillData.get_def(s_id)
	var cid := GameManager.cultivator_id
	var enhanced := SkillData.is_enhanced_for_cultivator(s_id, cid)
	var st := SkillData.final_stats(s_id, cid)
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(_card_w, CARD_H)
	card.mouse_filter = Control.MOUSE_FILTER_PASS

	var base_border: Color = GameStyle.JADE if enhanced else GameStyle.GOLD.darkened(0.3)
	var style = GameStyle.card(base_border, 3.0, Vector2(5, 5))
	style.content_margin_left = CARD_PAD_X
	style.content_margin_top = 12.0
	style.content_margin_right = CARD_PAD_X
	style.content_margin_bottom = 12.0
	card.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 8)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	# 符文占位图标（正式图标走 media-gen 后替换为 TextureRect）
	var icon_box = PanelContainer.new()
	var icon_size := icon_size_for(_card_w)
	icon_box.custom_minimum_size = Vector2(icon_size, icon_size)
	icon_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, GameStyle.JADE if enhanced else GameStyle.GOLD_EDGE, 2, 0.0))
	var glyph_lbl = Label.new()
	glyph_lbl.text = String(def.get("glyph", "?"))
	glyph_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glyph_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_child(glyph_lbl)
	GameStyle.label(glyph_lbl, 34, GameStyle.JADE if enhanced else GameStyle.PAPER, 0, GameStyle.INK, true)
	vbox.add_child(icon_box)

	# 名称
	var name_lbl = Label.new()
	name_lbl.text = def.get("name", "?")
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lbl)
	GameStyle.label(name_lbl, 17, GameStyle.JADE if enhanced else GameStyle.PAPER, 0, GameStyle.INK, true)

	# 冷却 chip（契合时带标识，数值为角色合并后的真实冷却）
	var cd_lbl = Label.new()
	cd_lbl.text = (" ✦契合·冷却 %d 秒 " % int(round(float(st["cooldown"])))) if enhanced else (" 冷却 %d 秒 " % int(round(float(st["cooldown"]))))
	cd_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cd_lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cd_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.JADE))
	vbox.add_child(cd_lbl)
	GameStyle.label(cd_lbl, 11, GameStyle.INK_TEXT)

	# 描述（换行切进文本，不交给引擎折行：见 GameStyle.wrap_cjk 头注）
	var desc_text: String = String(def.get("desc", ""))
	var enhance := SkillData.enhance_desc(s_id, cid)
	if not enhance.is_empty():
		desc_text += "\n✦ 道统契合：" + enhance
	var desc_lbl = Label.new()
	desc_lbl.text = GameStyle.wrap_cjk(desc_text, GameStyle.body_font(), 12, _desc_w())
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.custom_minimum_size = Vector2(_desc_w(), 0)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(desc_lbl)
	GameStyle.label(desc_lbl, 12, GameStyle.PAPER_DIM)

	# 选择按钮
	var btn = Button.new()
	btn.text = "携 此 术"
	btn.custom_minimum_size = Vector2(0, 36)
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	btn.focus_mode = Control.FOCUS_NONE
	if enhanced:
		GameStyle.button(btn, GameStyle.JADE, GameStyle.JADE_EDGE, 14, GameStyle.INK_TEXT, 5.0, GameStyle.INK_TEXT)
	else:
		GameStyle.button(btn, GameStyle.GOLD, GameStyle.JADE, 14, GameStyle.INK_TEXT, 5.0, GameStyle.INK_TEXT)
	btn.pressed.connect(func(): _choose(s_id))
	vbox.add_child(btn)

	card.add_child(vbox)

	card.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
			_choose(s_id)
	)
	card.mouse_entered.connect(func():
		var tw = card.create_tween()
		tw.tween_property(card, "scale", Vector2(1.04, 1.04), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		style.border_color = GameStyle.JADE_EDGE if enhanced else GameStyle.GOLD_EDGE
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
	)

func _choose(s_id: String) -> void:
	if _transitioning:
		return
	_transitioning = true
	AudioManager.play_sfx("level_up", 0.9)
	GameManager.pending_skill_id = s_id
	var tw = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func():
		visible = false
		_transitioning = false
		var weapon_select = get_parent().get_node_or_null("StartWeaponSelect")
		if weapon_select != null and weapon_select.has_method("show_select"):
			weapon_select.show_select()
	)
