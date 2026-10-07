class_name GameHUD
extends Control

@onready var hp_bar: ProgressBar = $TopContainer/LeftBox/HPBar
@onready var hp_label: Label = $TopContainer/LeftBox/HPLabel
@onready var level_label: Label = $TopContainer/LeftBox/LevelLabel
@onready var exp_bar: ProgressBar = $ExpBar
@onready var time_label: Label = $TopContainer/CenterBox/TimeLabel
@onready var kills_label: Label = $TopContainer/RightBox/KillsLabel
@onready var shards_label: Label = $TopContainer/RightBox/ShardsLabel
@onready var weapons_bar: HBoxContainer = $WeaponsBar
@onready var banner: PanelContainer = $Banner
@onready var banner_label: Label = $Banner/BannerLabel

func _ready() -> void:
    banner.modulate.a = 0.0
    GameManager.player_hp_changed.connect(_on_hp_changed)
    GameManager.player_exp_changed.connect(_on_exp_changed)
    GameManager.stats_updated.connect(_on_stats_updated)
    GameManager.announcement_triggered.connect(show_announcement)
    GameManager.weapons_updated.connect(_on_weapons_updated)
    
    if GameManager.player != null and GameManager.player.has_method("get_equipped_weapons_data"):
        _on_weapons_updated(GameManager.player.get_equipped_weapons_data())

func _on_hp_changed(cur: float, max_v: float) -> void:
    hp_bar.max_value = max_v
    var tw = create_tween()
    tw.tween_property(hp_bar, "value", cur, 0.15)
    hp_label.text = str(int(cur)) + "/" + str(int(max_v))

func _on_exp_changed(cur: int, target: int, lvl: int) -> void:
    exp_bar.max_value = target
    var tw = create_tween()
    tw.tween_property(exp_bar, "value", float(cur), 0.12)
    level_label.text = "【阶位 " + str(lvl) + "】"

func _on_stats_updated(kills: int, g_time: float, shards: int) -> void:
    kills_label.text = "讨伐 " + str(kills)
    shards_label.text = "辉晶 " + str(shards)
    var mins = int(g_time) / 60
    var secs = int(g_time) % 60
    time_label.text = "%02d:%02d" % [mins, secs]

func _on_weapons_updated(weapons: Array) -> void:
    for child in weapons_bar.get_children():
        child.queue_free()
        
    var max_slots = maxi(6, weapons.size())
    for i in range(max_slots):
        var slot = PanelContainer.new()
        slot.custom_minimum_size = Vector2(32, 32)
        slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
        
        var style = StyleBoxFlat.new()
        style.bg_color = Color(0.1, 0.12, 0.16, 0.85)
        style.border_width_left = 1
        style.border_width_top = 1
        style.border_width_right = 1
        style.border_width_bottom = 1
        style.corner_radius_top_left = 4
        style.corner_radius_top_right = 4
        style.corner_radius_bottom_right = 4
        style.corner_radius_bottom_left = 4
        
        if i < weapons.size():
            var w = weapons[i]
            style.border_color = Color(0.85, 0.72, 0.35, 0.95)
            slot.add_theme_stylebox_override("panel", style)
            
            var tex_rect = TextureRect.new()
            if w.has("icon") and ResourceLoader.exists(w["icon"]):
                tex_rect.texture = load(w["icon"])
            tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
            tex_rect.custom_minimum_size = Vector2(24, 24)
            tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
            tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
            slot.add_child(tex_rect)
        else:
            style.border_color = Color(0.3, 0.34, 0.4, 0.45)
            slot.add_theme_stylebox_override("panel", style)
            
        weapons_bar.add_child(slot)

func show_announcement(msg: String) -> void:
    banner_label.text = msg
    var tw = create_tween()
    tw.tween_property(banner, "modulate:a", 1.0, 0.2)
    tw.tween_interval(2.0)
    tw.tween_property(banner, "modulate:a", 0.0, 0.35)
