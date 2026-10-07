class_name GameHUD
extends Control

@onready var hp_bar: ProgressBar = $TopContainer/LeftBox/HPBlock/HBox/HPBar
@onready var hp_label: Label = $TopContainer/LeftBox/HPBlock/HBox/HPLabel
@onready var level_label: Label = $TopContainer/LeftBox/LevelBadge/LevelLabel
@onready var exp_bar: ProgressBar = $ExpBar
@onready var time_label: Label = $TopContainer/CenterBox/TimeBlock/TimeLabel
@onready var kills_label: Label = $TopContainer/RightBox/KillsChip/KillsLabel
@onready var shards_label: Label = $TopContainer/RightBox/ShardsChip/ShardsLabel
@onready var weapons_bar: HBoxContainer = $WeaponsBar
@onready var banner: PanelContainer = $Banner
@onready var banner_label: Label = $Banner/BannerLabel

func _ready() -> void:
    banner.modulate.a = 0.0
    # P5 粗体字面统一
    P5Style.label($TopContainer/LeftBox/HPBlock/HBox/HPTitle, 17, P5Style.WHITE, 0, P5Style.INK, true)
    P5Style.label(hp_label, 14, P5Style.WHITE)
    P5Style.label(level_label, 14, P5Style.BLACK)
    P5Style.label(time_label, 24, P5Style.WHITE, 0, P5Style.INK, true)
    P5Style.label(kills_label, 15, P5Style.BLACK)
    P5Style.label(shards_label, 15, P5Style.BLACK)
    P5Style.label(banner_label, 17, P5Style.WHITE)

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
    level_label.text = "Lv." + str(lvl)

func _on_stats_updated(kills: int, g_time: float, shards: int) -> void:
    kills_label.text = "击倒 " + str(kills)
    shards_label.text = "硬币 " + str(shards)
    var mins = int(g_time) / 60
    var secs = int(g_time) % 60
    time_label.text = "%02d:%02d" % [mins, secs]

func _on_weapons_updated(weapons: Array) -> void:
    for child in weapons_bar.get_children():
        child.queue_free()

    var max_slots = maxi(6, weapons.size())
    for i in range(max_slots):
        var slot = PanelContainer.new()
        slot.custom_minimum_size = Vector2(36, 36)
        slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

        var filled := i < weapons.size()
        var style = P5Style.outlined_panel(
            P5Style.BLACK if filled else Color(P5Style.BLACK.r, P5Style.BLACK.g, P5Style.BLACK.b, 0.55),
            P5Style.YELLOW if filled else P5Style.GREY, 2, 8.0)
        slot.add_theme_stylebox_override("panel", style)

        if filled:
            var w = weapons[i]
            var tex_rect = TextureRect.new()
            if w.has("icon") and ResourceLoader.exists(w["icon"]):
                tex_rect.texture = load(w["icon"])
            tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
            tex_rect.custom_minimum_size = Vector2(26, 26)
            tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
            tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
            slot.add_child(tex_rect)

        weapons_bar.add_child(slot)

func show_announcement(msg: String) -> void:
    banner_label.text = msg
    banner.pivot_offset = banner.size / 2.0
    var tw = create_tween()
    tw.tween_property(banner, "modulate:a", 1.0, 0.18)
    tw.parallel().tween_property(banner, "scale", Vector2(1.08, 1.08), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    tw.tween_property(banner, "scale", Vector2.ONE, 0.1)
    tw.tween_interval(1.9)
    tw.tween_property(banner, "modulate:a", 0.0, 0.35)
