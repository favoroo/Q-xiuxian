class_name StartWeaponSelect
extends Control

## 开局本命法器六选一：选择后才开始第一波

## 卡片宽按屏宽现算：6 卡 + 间距 + 面板内边距必须在最窄屏（720）也摆得下。
## （旧版写死 130：720 宽整排要 830，左右出屏；判据量到的是入场动画中间帧缩了
## 0.72 的卡，没抓住 —— 现在窄屏真会收成 94 宽的卡。）
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
var _card_w := 130.0

## 一屏摆 n 张卡时每张的宽（纯函数，判据 tests/layout_check.gd 拿同一份算术量文案）
static func card_w_for(screen_w: float, count: int) -> float:
	var avail := screen_w - PANEL_CHROME_X - CARD_SEP * float(count - 1)
	return clampf(avail / float(count), 88.0, 132.0)

## 图标框随卡宽缩：窄屏卡的内宽装不下 74 的满配图标框
static func icon_size_for(card_w: float) -> float:
	return clampf(card_w - CARD_PAD_X * 2.0 - 4.0, 56.0, 74.0)

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 面板样式收口到 GameStyle（旧版在 .tscn 里钉死 820 宽 + 旧蓝色板 + 不画的投影）
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
	sub_label.text = "选择一件初始武器开始战斗"
	GameStyle.label(hint_label, 12, GameStyle.GREY)
	hint_label.text = "◆ 元素搭配、武器共鸣：集齐三把同名同星武器可在商店手动升星 ◆"

func _setup_header_bar() -> void:
	var vbox: VBoxContainer = $CenterContainer/Panel/MarginContainer/VBox
	var header_row := HBoxContainer.new()
	header_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(header_row)
	vbox.move_child(header_row, 0)

	var back_btn := Button.new()
	back_btn.text = "〈 重选角色"
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
	var sname: String = String(SkillData.get_def(GameManager.pending_skill_id).get("name", ""))
	if not cname.is_empty():
		sub_label.text = "已选角色 · %s「%s」 · 技能「%s」 · 选择一件初始武器" % [cname, cepi, sname]
	else:
		sub_label.text = "选择一件初始武器开始战斗"
	for child in cards_container.get_children():
		child.queue_free()
	_card_w = card_w_for(get_viewport_rect().size.x, WeaponData.STARTER_IDS.size())
	cards_container.add_theme_constant_override("separation", int(CARD_SEP))
	var idx := 0
	for w_id in WeaponData.STARTER_IDS:
		var card = _create_card(w_id)
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
	card.custom_minimum_size = Vector2(_card_w, CARD_H)
	card.mouse_filter = Control.MOUSE_FILTER_PASS

	var base_border: Color = GameStyle.JADE if rec else GameStyle.GOLD.darkened(0.3)
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

	# 图标
	var icon_box = PanelContainer.new()
	var icon_size := icon_size_for(_card_w)
	icon_box.custom_minimum_size = Vector2(icon_size, icon_size)
	icon_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, GameStyle.JADE if rec else GameStyle.GOLD_EDGE, 2, 0.0))
	var icon_tex = TextureRect.new()
	if ResourceLoader.exists(def.get("icon", "")):
		icon_tex.texture = load(def["icon"])
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.custom_minimum_size = Vector2(icon_size - 14.0, icon_size - 14.0)
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_child(icon_tex)
	# 吃「元素伤害」属性加成的法器挂橙红角标（与商店/属性面板同一口径）
	GameStyle.maybe_add_element_badge(icon_box, w_id, 8)
	vbox.add_child(icon_box)

	# 名称 + 星
	var name_lbl = Label.new()
	name_lbl.text = def.get("name", "?")
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lbl)
	GameStyle.label(name_lbl, 17, GameStyle.JADE if rec else GameStyle.PAPER, 0, GameStyle.INK, true)

	# 行为签（若契合当前道统则追加契合标识）
	var tag_lbl = Label.new()
	tag_lbl.text = (" ✦适配·%s " % def.get("tag", "")) if rec else (" " + def.get("tag", "") + " ")
	tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag_lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tag_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.JADE))
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
	btn.text = "装 备 此 武 器"
	btn.custom_minimum_size = Vector2(0, 36)
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	btn.focus_mode = Control.FOCUS_NONE
	if rec:
		GameStyle.button(btn, GameStyle.JADE, GameStyle.JADE_EDGE, 14, GameStyle.INK_TEXT, 5.0, GameStyle.INK_TEXT)
	else:
		GameStyle.button(btn, GameStyle.GOLD, GameStyle.JADE, 14, GameStyle.INK_TEXT, 5.0, GameStyle.INK_TEXT)
	btn.pressed.connect(func(): _choose(w_id))
	vbox.add_child(btn)

	card.add_child(vbox)

	card.mouse_entered.connect(func():
		var tw = card.create_tween()
		tw.tween_property(card, "scale", Vector2(1.04, 1.04), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		style.border_color = GameStyle.JADE_EDGE if rec else GameStyle.GOLD_EDGE
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
		# 返回链与前进链互为镜像：法器 ← 神通 ← 道统；旧档缺 SkillSelect 节点时回退到道统
		var skill_select = get_parent().get_node_or_null("SkillSelect")
		if skill_select != null and skill_select.has_method("show_select"):
			skill_select.show_select()
			return
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
