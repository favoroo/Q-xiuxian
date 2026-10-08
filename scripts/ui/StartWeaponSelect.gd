class_name StartWeaponSelect
extends Control

## 开局本命法器三选一：选择后才开始第一波

@onready var cards_container: HBoxContainer = $CenterContainer/Panel/MarginContainer/VBox/CardsContainer
@onready var title_label: Label = $CenterContainer/Panel/MarginContainer/VBox/TitleLabel
@onready var sub_label: Label = $CenterContainer/Panel/MarginContainer/VBox/SubLabel
@onready var hint_label: Label = $CenterContainer/Panel/MarginContainer/VBox/HintLabel

func _ready() -> void:
    visible = false
    process_mode = Node.PROCESS_MODE_ALWAYS
    GameStyle.label(title_label, 34, GameStyle.PAPER, 0, GameStyle.INK, true)
    GameStyle.label(sub_label, 15, GameStyle.PAPER_DIM)
    GameStyle.label(hint_label, 12, GameStyle.GREY)
    hint_label.text = "◆ 集齐三把同名同星法器，可在波间商店手动合成升星 ◆"

    var ver_btn := Button.new()
    ver_btn.text = "修仙幸存者 " + Version.APP_VERSION_NAME
    ver_btn.flat = true
    ver_btn.focus_mode = Control.FOCUS_NONE
    ver_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
    ver_btn.position = Vector2(-160, -32)
    ver_btn.add_theme_font_override("font", GameStyle.body_font())
    ver_btn.add_theme_font_size_override("font_size", 11)
    ver_btn.add_theme_color_override("font_color", GameStyle.GREY)
    ver_btn.add_theme_color_override("font_hover_color", GameStyle.YELLOW)
    ver_btn.pressed.connect(func():
        UpdateManager.check_for_update(true)
    )
    add_child(ver_btn)

func show_select() -> void:
    for child in cards_container.get_children():
        child.queue_free()
    var idx := 0
    for w_id in WeaponData.STARTER_IDS:
        var card = _create_card(w_id)
        cards_container.add_child(card)
        card.pivot_offset = Vector2(110.0, 160.0)
        card.scale = Vector2(0.72, 0.72)
        card.modulate.a = 0.0
        var ctw = card.create_tween()
        ctw.tween_interval(float(idx) * 0.06)
        ctw.set_parallel(true)
        ctw.tween_property(card, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
        ctw.tween_property(card, "modulate:a", 1.0, 0.18)
        idx += 1
    visible = true
    modulate.a = 0.0
    var tw = create_tween()
    tw.tween_property(self, "modulate:a", 1.0, 0.25)

func _create_card(w_id: String) -> Control:
    var def := WeaponData.get_def(w_id)
    var card = PanelContainer.new()
    card.custom_minimum_size = Vector2(220.0, 320.0)
    card.mouse_filter = Control.MOUSE_FILTER_PASS

    var style = StyleBoxFlat.new()
    style.bg_color = GameStyle.NAVY
    style.skew = Vector2(deg_to_rad(4.0), 0)
    style.border_width_left = 2
    style.border_width_top = 2
    style.border_width_right = 2
    style.border_width_bottom = 5
    style.border_color = GameStyle.BLUE.darkened(0.3)
    style.shadow_color = Color(0, 0, 0, 0.55)
    style.shadow_size = 0
    style.shadow_offset = Vector2(6, 6)
    style.content_margin_left = 14.0
    style.content_margin_top = 16.0
    style.content_margin_right = 14.0
    style.content_margin_bottom = 14.0
    card.add_theme_stylebox_override("panel", style)

    var vbox = VBoxContainer.new()
    vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
    vbox.add_theme_constant_override("separation", 12)
    vbox.alignment = BoxContainer.ALIGNMENT_CENTER

    # 图标
    var icon_box = PanelContainer.new()
    icon_box.custom_minimum_size = Vector2(92, 92)
    icon_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    icon_box.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, GameStyle.BLUE_EDGE, 2, 0.0))
    var icon_tex = TextureRect.new()
    if ResourceLoader.exists(def.get("icon", "")):
        icon_tex.texture = load(def["icon"])
    icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    icon_tex.custom_minimum_size = Vector2(76, 76)
    icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    icon_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
    icon_box.add_child(icon_tex)
    vbox.add_child(icon_box)

    # 名称 + 星
    var name_lbl = Label.new()
    name_lbl.text = WeaponData.star_text(1) + " " + def.get("name", "?")
    name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    vbox.add_child(name_lbl)
    GameStyle.label(name_lbl, 20, GameStyle.PAPER, 0, GameStyle.INK, true)

    # 行为签
    var tag_lbl = Label.new()
    tag_lbl.text = " " + def.get("tag", "") + " "
    tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    tag_lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    tag_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.YELLOW))
    vbox.add_child(tag_lbl)
    GameStyle.label(tag_lbl, 12, GameStyle.INK_TEXT)

    # 描述
    var desc_lbl = Label.new()
    desc_lbl.text = def.get("desc", "")
    desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
    desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
    vbox.add_child(desc_lbl)
    GameStyle.label(desc_lbl, 13, GameStyle.PAPER_DIM)

    # 选择按钮
    var btn = Button.new()
    btn.text = "执 此 器"
    btn.custom_minimum_size = Vector2(0, 40)
    btn.mouse_filter = Control.MOUSE_FILTER_PASS
    GameStyle.button(btn, GameStyle.BLUE, GameStyle.YELLOW, 15, GameStyle.PAPER, 6.0, GameStyle.INK_TEXT)
    btn.pressed.connect(func(): _choose(w_id))
    vbox.add_child(btn)

    card.add_child(vbox)

    card.mouse_entered.connect(func():
        var tw = card.create_tween()
        tw.tween_property(card, "scale", Vector2(1.04, 1.04), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
        style.border_color = GameStyle.BLUE_EDGE
    )
    card.mouse_exited.connect(func():
        var tw = card.create_tween()
        tw.tween_property(card, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
        style.border_color = GameStyle.BLUE.darkened(0.3)
    )
    return card

func _choose(w_id: String) -> void:
    AudioManager.play_sfx("level_up", 0.9)
    GameManager.start_run(w_id)
    var tw = create_tween()
    tw.tween_property(self, "modulate:a", 0.0, 0.2)
    tw.tween_callback(func():
        visible = false
        get_tree().paused = false
    )
