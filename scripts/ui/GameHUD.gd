class_name GameHUD
extends Control

## 顶栏暂停与属性按钮请求（由 Main 接线）
signal pause_requested
signal stats_requested

@onready var hp_bar: ProgressBar = $TopContainer/LeftBox/HPBlock/HBox/HPBar
@onready var hp_label: Label = $TopContainer/LeftBox/HPBlock/HBox/HPLabel
@onready var level_label: Label = $TopContainer/LeftBox/LevelBadge/LevelLabel
@onready var exp_bar: ProgressBar = $ExpBar
@onready var time_label: Label = $TopContainer/CenterBox/TimeBlock/TimeLabel
@onready var wave_label: Label = $TopContainer/CenterBox/WaveChip/WaveLabel
@onready var kills_label: Label = $TopContainer/RightBox/KillsChip/KillsLabel
@onready var shards_label: Label = $TopContainer/RightBox/ShardsChip/ShardsLabel
@onready var weapons_bar: HBoxContainer = $WeaponsBar
@onready var banner: PanelContainer = $Banner
@onready var banner_label: Label = $Banner/BannerLabel

func _ready() -> void:
    banner.modulate.a = 0.0
    # 蓝白黄斜切色块（场景里未定样的两块在这里补）
    banner.add_theme_stylebox_override("panel", GameStyle.block(GameStyle.BLUE, GameStyle.SLANT_BAND, Vector2(5, 6)))
    $TopContainer/CenterBox/TimeBlock.add_theme_stylebox_override("panel", GameStyle.block(GameStyle.INK, GameStyle.SLANT_BAND, Vector2(4, 5)))

    GameStyle.label($TopContainer/LeftBox/HPBlock/HBox/HPTitle, 17, GameStyle.PAPER, 0, GameStyle.INK, true)
    GameStyle.label(hp_label, 14, GameStyle.PAPER)
    GameStyle.label(level_label, 14, GameStyle.INK_TEXT)
    GameStyle.label(time_label, 24, GameStyle.PAPER, 0, GameStyle.INK, true)
    GameStyle.label(wave_label, 15, GameStyle.YELLOW)
    GameStyle.label(kills_label, 15, GameStyle.INK_TEXT)
    GameStyle.label(shards_label, 15, GameStyle.INK_TEXT)
    GameStyle.label(banner_label, 17, GameStyle.PAPER, 0, GameStyle.INK, true)

    GameManager.player_hp_changed.connect(_on_hp_changed)
    GameManager.player_exp_changed.connect(_on_exp_changed)
    GameManager.player_leveled_up.connect(_on_leveled_up)
    GameManager.stats_updated.connect(_on_stats_updated)
    GameManager.announcement_triggered.connect(show_announcement)
    GameManager.weapons_updated.connect(_on_weapons_updated)
    GameManager.wave_changed.connect(_on_wave_changed)
    _on_wave_changed(GameManager.wave_number)

    _on_weapons_updated(GameManager.get_weapons_summary())
    _build_top_buttons()
    # 羁绊徽记行：挂在左栏之下，只显示已激活的流派
    _synergy_box = HBoxContainer.new()
    _synergy_box.add_theme_constant_override("separation", 6)
    _synergy_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    $TopContainer/LeftBox.add_child(_synergy_box)

var _synergy_box: HBoxContainer = null

func _refresh_synergy_badges() -> void:
    if _synergy_box == null:
        return
    for child in _synergy_box.get_children():
        child.queue_free()
    for tag in GameManager.active_synergies.keys():
        var data: Dictionary = GameManager.active_synergies[tag]
        var lv := int(data.get("level", 0))
        if lv <= 0:
            continue
        var info: Dictionary = WeaponData.SYNERGIES.get(tag, {})
        var chip := Label.new()
        chip.text = " %s Lv.%d " % [info.get("name", tag), lv]
        chip.tooltip_text = info.get("desc", "")
        chip.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.YELLOW_DK))
        GameStyle.label(chip, 11, GameStyle.PAPER)
        chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _synergy_box.add_child(chip)

## 顶栏右侧追加属性与暂停按钮（触屏入口）
func _build_top_buttons() -> void:
    var stats_btn := Button.new()
    stats_btn.text = "属 性"
    stats_btn.custom_minimum_size = Vector2(62, 0)
    stats_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    stats_btn.mouse_filter = Control.MOUSE_FILTER_STOP
    stats_btn.focus_mode = Control.FOCUS_NONE
    GameStyle.button(stats_btn, GameStyle.NAVY2, GameStyle.YELLOW, 13, GameStyle.PAPER, 5.0, GameStyle.INK_TEXT)
    stats_btn.pressed.connect(func(): stats_requested.emit())
    $TopContainer/RightBox.add_child(stats_btn)

    var pause_btn := Button.new()
    pause_btn.text = "暂 停"
    pause_btn.custom_minimum_size = Vector2(62, 0)
    pause_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    pause_btn.mouse_filter = Control.MOUSE_FILTER_STOP
    pause_btn.focus_mode = Control.FOCUS_NONE
    GameStyle.button(pause_btn, GameStyle.NAVY2, GameStyle.BLUE, 13, GameStyle.PAPER, 5.0)
    pause_btn.pressed.connect(func(): pause_requested.emit())
    $TopContainer/RightBox.add_child(pause_btn)

func _on_hp_changed(cur: float, max_v: float) -> void:
    hp_bar.max_value = max_v
    var tw = create_tween()
    tw.tween_property(hp_bar, "value", cur, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    hp_label.text = str(int(cur)) + "/" + str(int(max_v))
    var low := max_v > 0.0 and (cur / max_v) < 0.28
    hp_label.add_theme_color_override("font_color", GameStyle.BAD if low else GameStyle.PAPER)

func _on_leveled_up(_lvl: int) -> void:
    var badge := $TopContainer/LeftBox/LevelBadge
    if badge != null:
        badge.pivot_offset = badge.size * 0.5
        badge.scale = Vector2(1.4, 1.4)
        var tw := badge.create_tween()
        tw.tween_property(badge, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_exp_changed(cur: int, target: int, lvl: int) -> void:
    exp_bar.max_value = target
    var tw = create_tween()
    tw.tween_property(exp_bar, "value", float(cur), 0.12)
    level_label.text = "Lv." + str(lvl)

func _on_stats_updated(kills: int, g_time: float, stones: int) -> void:
    kills_label.text = "斩妖 " + str(kills)
    shards_label.text = "灵石 " + str(stones)
    var mins = int(g_time / 60.0)
    var secs = int(g_time) % 60
    time_label.text = "%02d:%02d" % [mins, secs]

func _on_wave_changed(n: int) -> void:
    wave_label.text = "第 %d 波" % maxi(n, 1)
    wave_label.get_parent().visible = n >= 1

func _on_weapons_updated(weapons: Array) -> void:
    _refresh_synergy_badges()
    for child in weapons_bar.get_children():
        child.queue_free()

    for i in range(WeaponData.MAX_SLOTS):
        var slot = PanelContainer.new()
        slot.custom_minimum_size = Vector2(36, 36)
        slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

        var filled := i < weapons.size()
        var style = GameStyle.outlined_panel(
            GameStyle.NAVY if filled else Color(GameStyle.INK.r, GameStyle.INK.g, GameStyle.INK.b, 0.55),
            GameStyle.BLUE if filled else GameStyle.LINE, 2, 5.0)
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

            var star_lbl = Label.new()
            star_lbl.text = "★%d" % int(w.get("star", 1))
            star_lbl.add_theme_font_override("font", GameStyle.body_font())
            star_lbl.add_theme_font_size_override("font_size", 10)
            star_lbl.add_theme_color_override("font_color", GameStyle.YELLOW)
            star_lbl.add_theme_color_override("font_outline_color", GameStyle.INK)
            star_lbl.add_theme_constant_override("outline_size", 3)
            star_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
            star_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
            star_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            star_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
            star_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
            slot.add_child(star_lbl)

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
