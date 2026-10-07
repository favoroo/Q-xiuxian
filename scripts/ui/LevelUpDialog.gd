class_name LevelUpDialog
extends Control

@onready var cards_container: HBoxContainer = $CenterContainer/Panel/MarginContainer/VBox/CardsContainer
@onready var title_label: Label = $CenterContainer/Panel/MarginContainer/VBox/TitleLabel

var current_upgrades: Array[Dictionary] = []

func _ready() -> void:
    visible = false
    process_mode = Node.PROCESS_MODE_ALWAYS
    GameManager.player_leveled_up.connect(_on_level_up)

func _on_level_up(level: int) -> void:
    current_upgrades = UpgradeData.get_random_upgrades(3)
    title_label.text = "✦ 阶 位 突 破 · 领 悟 奇 物 （突破至阶位 " + str(level) + "）✦"
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
    card.custom_minimum_size = Vector2(260.0, 350.0)
    card.mouse_filter = Control.MOUSE_FILTER_PASS
    
    # Border & Background style based on rarity
    var border_col: Color = data.get("border_color", Color(0.85, 0.72, 0.38))
    var style_normal = StyleBoxFlat.new()
    style_normal.bg_color = Color(0.1, 0.12, 0.16, 0.98)
    style_normal.border_width_left = 2
    style_normal.border_width_top = 2
    style_normal.border_width_right = 2
    style_normal.border_width_bottom = 2
    style_normal.border_color = border_col
    style_normal.corner_radius_top_left = 10
    style_normal.corner_radius_top_right = 10
    style_normal.corner_radius_bottom_right = 10
    style_normal.corner_radius_bottom_left = 10
    style_normal.content_margin_left = 16.0
    style_normal.content_margin_top = 16.0
    style_normal.content_margin_right = 16.0
    style_normal.content_margin_bottom = 16.0
    card.add_theme_stylebox_override("panel", style_normal)
    
    var vbox = VBoxContainer.new()
    vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
    vbox.add_theme_constant_override("separation", 10)
    
    # 1. Header: Rarity pill & Category tag
    var hbox_top = HBoxContainer.new()
    hbox_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
    
    var rarity_lbl = Label.new()
    rarity_lbl.text = " " + data.get("rarity_label", "强化") + " "
    rarity_lbl.add_theme_font_size_override("font_size", 12)
    rarity_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
    var pill_style = StyleBoxFlat.new()
    pill_style.bg_color = border_col * 0.45
    pill_style.border_width_left = 1
    pill_style.border_width_top = 1
    pill_style.border_width_right = 1
    pill_style.border_width_bottom = 1
    pill_style.border_color = border_col
    pill_style.corner_radius_top_left = 4
    pill_style.corner_radius_top_right = 4
    pill_style.corner_radius_bottom_right = 4
    pill_style.corner_radius_bottom_left = 4
    rarity_lbl.add_theme_stylebox_override("normal", pill_style)
    hbox_top.add_child(rarity_lbl)
    
    var spacer = Control.new()
    spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    hbox_top.add_child(spacer)
    
    var tag_lbl = Label.new()
    tag_lbl.text = "【" + data.get("tag", "特性") + "】"
    tag_lbl.add_theme_font_size_override("font_size", 12)
    tag_lbl.add_theme_color_override("font_color", Color(0.72, 0.78, 0.85))
    hbox_top.add_child(tag_lbl)
    vbox.add_child(hbox_top)
    
    # 2. Central Icon in frame
    var icon_box = PanelContainer.new()
    icon_box.custom_minimum_size = Vector2(64, 64)
    icon_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var icon_style = StyleBoxFlat.new()
    icon_style.bg_color = Color(0.06, 0.08, 0.11, 0.8)
    icon_style.border_width_left = 1
    icon_style.border_width_top = 1
    icon_style.border_width_right = 1
    icon_style.border_width_bottom = 1
    icon_style.border_color = border_col * 0.65
    icon_style.corner_radius_top_left = 6
    icon_style.corner_radius_top_right = 6
    icon_style.corner_radius_bottom_right = 6
    icon_style.corner_radius_bottom_left = 6
    icon_box.add_theme_stylebox_override("panel", icon_style)
    
    var icon_tex = TextureRect.new()
    if data.has("icon") and ResourceLoader.exists(data["icon"]):
        icon_tex.texture = load(data["icon"])
    icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    icon_tex.custom_minimum_size = Vector2(48, 48)
    icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    icon_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
    icon_box.add_child(icon_tex)
    vbox.add_child(icon_box)
    
    # 3. Card Title
    var title_lbl = Label.new()
    title_lbl.text = data["title"]
    title_lbl.add_theme_font_size_override("font_size", 18)
    title_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.68))
    title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
    vbox.add_child(title_lbl)
    
    # 4. Divider
    var sep = HSeparator.new()
    sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var sep_style = StyleBoxLine.new()
    sep_style.color = border_col * 0.4
    sep_style.thickness = 1
    sep.add_theme_stylebox_override("separator", sep_style)
    vbox.add_child(sep)
    
    # 5. RichTextLabel for BBCode highlights (fixed width, auto wrapped, centered)
    var r_desc = RichTextLabel.new()
    r_desc.bbcode_enabled = true
    r_desc.text = data["desc"]
    r_desc.fit_content = true
    r_desc.scroll_active = false
    r_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
    r_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
    r_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
    if ResourceLoader.exists("res://assets/fonts/game_font.ttc"):
        var base_f = load("res://assets/fonts/game_font.ttc") as Font
        var bold_f = FontVariation.new()
        bold_f.base_font = base_f
        bold_f.variation_embolden = 0.45
        r_desc.add_theme_font_override("normal_font", base_f)
        r_desc.add_theme_font_override("bold_font", bold_f)
    r_desc.add_theme_font_size_override("normal_font_size", 13)
    r_desc.add_theme_font_size_override("bold_font_size", 13)
    r_desc.add_theme_color_override("default_color", Color(0.86, 0.88, 0.92))
    vbox.add_child(r_desc)
    
    # 6. Action Button overlay
    var btn = Button.new()
    btn.text = "装 配 / 突 破"
    btn.custom_minimum_size = Vector2(0, 36)
    btn.mouse_filter = Control.MOUSE_FILTER_PASS
    var btn_style = StyleBoxFlat.new()
    btn_style.bg_color = border_col * 0.35
    btn_style.border_width_left = 1
    btn_style.border_width_top = 1
    btn_style.border_width_right = 1
    btn_style.border_width_bottom = 1
    btn_style.border_color = border_col
    btn_style.corner_radius_top_left = 6
    btn_style.corner_radius_top_right = 6
    btn_style.corner_radius_bottom_right = 6
    btn_style.corner_radius_bottom_left = 6
    btn.add_theme_stylebox_override("normal", btn_style)
    
    var btn_hover = btn_style.duplicate()
    btn_hover.bg_color = border_col * 0.65
    btn.add_theme_stylebox_override("hover", btn_hover)
    btn.add_theme_stylebox_override("pressed", btn_hover)
    btn.add_theme_font_size_override("font_size", 14)
    btn.add_theme_color_override("font_color", Color(1, 1, 1))
    
    var up_id = data["id"]
    btn.pressed.connect(func(): _choose_upgrade(up_id))
    card.gui_input.connect(func(event: InputEvent):
        if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
            _choose_upgrade(up_id)
    )
    vbox.add_child(btn)
    
    card.add_child(vbox)
    
    # Hover animation on the card
    card.mouse_entered.connect(func():
        var tw = card.create_tween()
        tw.tween_property(card, "position:y", -6.0, 0.1)
        style_normal.border_width_left = 3
        style_normal.border_width_top = 3
        style_normal.border_width_right = 3
        style_normal.border_width_bottom = 3
    )
    card.mouse_exited.connect(func():
        var tw = card.create_tween()
        tw.tween_property(card, "position:y", 0.0, 0.1)
        style_normal.border_width_left = 2
        style_normal.border_width_top = 2
        style_normal.border_width_right = 2
        style_normal.border_width_bottom = 2
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
