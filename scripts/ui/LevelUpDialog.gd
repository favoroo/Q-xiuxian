class_name LevelUpDialog
extends Control

@onready var cards_container: HBoxContainer = $CenterContainer/Panel/MarginContainer/VBox/CardsContainer
@onready var title_label: Label = $CenterContainer/Panel/MarginContainer/VBox/TitleBand/TitleLabel

var current_upgrades: Array[Dictionary] = []

func _ready() -> void:
    visible = false
    process_mode = Node.PROCESS_MODE_ALWAYS
    P5Style.label(title_label, 24, P5Style.WHITE, 0, P5Style.INK, true)
    GameManager.player_leveled_up.connect(_on_level_up)

func _on_level_up(level: int) -> void:
    current_upgrades = UpgradeData.get_random_upgrades(3)
    title_label.text = "升 级 ！  Lv." + str(level)
    _populate_cards()

    visible = true
    get_tree().paused = true
    modulate.a = 0.0
    var tw = create_tween()
    tw.tween_property(self, "modulate:a", 1.0, 0.16)

func _populate_cards() -> void:
    for child in cards_container.get_children():
        child.queue_free()

    for i in range(current_upgrades.size()):
        var data = current_upgrades[i]
        var card_panel = _create_card_node(data)
        cards_container.add_child(card_panel)

func _create_card_node(data: Dictionary) -> Control:
    var card = PanelContainer.new()
    card.custom_minimum_size = Vector2(262.0, 340.0)
    card.mouse_filter = Control.MOUSE_FILTER_PASS

    var rarity_col: Color = data.get("border_color", P5Style.WHITE)
    var style_normal = StyleBoxFlat.new()
    style_normal.bg_color = Color(P5Style.BLACK.r, P5Style.BLACK.g, P5Style.BLACK.b, 0.985)
    style_normal.border_width_left = 2
    style_normal.border_width_top = 2
    style_normal.border_width_right = 2
    style_normal.border_width_bottom = 2
    style_normal.border_color = rarity_col
    style_normal.shadow_color = Color(0, 0, 0, 0.85)
    style_normal.shadow_size = 0
    style_normal.shadow_offset = Vector2(6, 6)
    style_normal.content_margin_left = 16.0
    style_normal.content_margin_top = 14.0
    style_normal.content_margin_right = 16.0
    style_normal.content_margin_bottom = 14.0
    card.add_theme_stylebox_override("panel", style_normal)

    var vbox = VBoxContainer.new()
    vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
    vbox.add_theme_constant_override("separation", 10)

    # 1. 顶部稀有度斜切色带 + 类别标签
    var hbox_top = HBoxContainer.new()
    hbox_top.mouse_filter = Control.MOUSE_FILTER_IGNORE

    var rarity_lbl = Label.new()
    rarity_lbl.text = " " + data.get("rarity_label", "强化") + " "
    rarity_lbl.add_theme_font_size_override("font_size", 12)
    var band_text_col: Color = P5Style.WHITE if rarity_col.get_luminance() < 0.45 else P5Style.BLACK
    rarity_lbl.add_theme_color_override("font_color", band_text_col)
    var pill_style = P5Style.panel(rarity_col, 8.0, Vector2(2, 2), Color(0, 0, 0, 0.7))
    pill_style.content_margin_top = 2.0
    pill_style.content_margin_bottom = 2.0
    rarity_lbl.add_theme_stylebox_override("normal", pill_style)
    hbox_top.add_child(rarity_lbl)

    var spacer = Control.new()
    spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    hbox_top.add_child(spacer)

    var tag_lbl = Label.new()
    tag_lbl.text = data.get("tag", "特性")
    tag_lbl.add_theme_font_size_override("font_size", 12)
    tag_lbl.add_theme_color_override("font_color", Color(0.62, 0.58, 0.68))
    hbox_top.add_child(tag_lbl)
    vbox.add_child(hbox_top)

    # 2. 中央图标（黑底白框）
    var icon_box = PanelContainer.new()
    icon_box.custom_minimum_size = Vector2(72, 72)
    icon_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    icon_box.add_theme_stylebox_override("panel", P5Style.outlined_panel(P5Style.BLACK, Color(0.9, 0.88, 0.85), 2, 0.0))

    var icon_tex = TextureRect.new()
    if data.has("icon") and ResourceLoader.exists(data["icon"]):
        icon_tex.texture = load(data["icon"])
    icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    icon_tex.custom_minimum_size = Vector2(56, 56)
    icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    icon_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
    icon_box.add_child(icon_tex)
    vbox.add_child(icon_box)

    # 3. 名称（白色大字）
    var title_lbl = Label.new()
    title_lbl.text = data["title"]
    title_lbl.add_theme_font_size_override("font_size", 19)
    title_lbl.add_theme_color_override("font_color", P5Style.WHITE)
    title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
    vbox.add_child(title_lbl)

    # 4. 分隔线（稀有度色）
    var sep = HSeparator.new()
    sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var sep_style = StyleBoxLine.new()
    sep_style.color = Color(rarity_col.r, rarity_col.g, rarity_col.b, 0.45)
    sep_style.thickness = 2
    sep.add_theme_stylebox_override("separator", sep_style)
    vbox.add_child(sep)

    # 5. 描述富文本
    var r_desc = RichTextLabel.new()
    r_desc.bbcode_enabled = true
    r_desc.text = data["desc"]
    r_desc.fit_content = true
    r_desc.scroll_active = false
    r_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
    r_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
    r_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
    r_desc.add_theme_font_override("normal_font", P5Style.bold_font())
    r_desc.add_theme_font_override("bold_font", P5Style.bold_font())
    r_desc.add_theme_font_size_override("normal_font_size", 13)
    r_desc.add_theme_font_size_override("bold_font_size", 13)
    r_desc.add_theme_color_override("default_color", Color(0.88, 0.86, 0.9))
    vbox.add_child(r_desc)

    # 6. 行动按钮（红底白字，悬停黄底黑字）
    var btn = Button.new()
    btn.text = "带 上 ！"
    btn.custom_minimum_size = Vector2(0, 38)
    btn.mouse_filter = Control.MOUSE_FILTER_PASS
    P5Style.button(btn, P5Style.RED, P5Style.YELLOW, 15, P5Style.WHITE, 8.0, P5Style.BLACK)

    var up_id = data["id"]
    btn.pressed.connect(func(): _choose_upgrade(up_id))
    card.gui_input.connect(func(event: InputEvent):
        if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
            _choose_upgrade(up_id)
    )
    vbox.add_child(btn)

    card.add_child(vbox)

    # 悬停动画：上浮 + 边框加粗
    card.mouse_entered.connect(func():
        var tw = card.create_tween()
        tw.tween_property(card, "position:y", -6.0, 0.1)
        style_normal.border_width_left = 3
        style_normal.border_width_top = 3
        style_normal.border_width_right = 3
        style_normal.border_width_bottom = 3
        style_normal.border_color = P5Style.WHITE
    )
    card.mouse_exited.connect(func():
        var tw = card.create_tween()
        tw.tween_property(card, "position:y", 0.0, 0.1)
        style_normal.border_width_left = 2
        style_normal.border_width_top = 2
        style_normal.border_width_right = 2
        style_normal.border_width_bottom = 2
        style_normal.border_color = rarity_col
    )

    return card

func _choose_upgrade(upgrade_id: String) -> void:
    GameManager.apply_upgrade(upgrade_id)
    AudioManager.play_sfx("gem_pickup", 1.2)

    var tw = create_tween()
    tw.tween_property(self, "modulate:a", 0.0, 0.12)
    tw.tween_callback(func():
        visible = false
        get_tree().paused = false
    )
