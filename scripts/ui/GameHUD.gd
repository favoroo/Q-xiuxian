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

## 顶栏原本留的左右边距与顶边距（安全区让位是在它们之上再加，不是替换）
const BASE_EDGE_X := 22.0
const BASE_TOP := 20.0
## 让位上限：读数再大也不许被一个离谱的 safe area 推到屏心
const SAFE_CAP := 140.0

func _ready() -> void:
    banner.modulate.a = 0.0
    _apply_safe_area()
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
    GameManager.boss_hp_changed.connect(_on_boss_hp_changed)
    GameManager.boss_defeated.connect(_on_boss_defeated)
    _on_wave_changed(GameManager.wave_number)

    _on_weapons_updated(GameManager.get_weapons_summary())
    _build_top_buttons()
    _build_boss_bar()
    # 羁绊徽记单独一排，摆在顶栏之下。
    # 挂在顶栏里 = 左组要 755 宽 > 它在 960 屏上只分到的 389 ⇒ 整条顶栏被撑到 1125 宽、
    # 两头各出屏 82（气血块少半截、「暂停」整个没了，用户 2026-10-08 说的「顶部的一些 UI
    # 都显示到外面去了」就是这个）。判据 LayoutCheck 灌最宽读数样本量的就是这一格。
    _synergy_box = HBoxContainer.new()
    _synergy_box.add_theme_constant_override("separation", 6)
    _synergy_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _synergy_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
    _synergy_box.offset_left = BASE_EDGE_X
    _synergy_box.offset_top = 66.0
    _synergy_box.offset_right = -BASE_EDGE_X
    _synergy_box.offset_bottom = 88.0
    add_child(_synergy_box)

var _synergy_box: HBoxContainer = null

# ---------------- 安全区让位（刘海 / 圆角 / 系统手势条） ----------------

## 顶栏整条往安全区里让：刘海会把最左那颗气血块与最右那颗暂停键吃掉一半 ——
## 桌面预览里永远是整屏，只有真机看得见，所以这条算术做成纯函数交给判据喂假刘海。
func _apply_safe_area() -> void:
    var win := Rect2(Vector2(DisplayServer.window_get_position()), Vector2(DisplayServer.window_get_size()))
    var safe := Rect2(DisplayServer.get_display_safe_area()).intersection(win)
    var vp: Rect2 = get_viewport().get_visible_rect()
    var scale: float = win.size.x / vp.size.x if vp.size.x > 0.0 else 1.0
    var ins := safe_insets(safe, win, scale)
    var top := $TopContainer
    top.offset_left = BASE_EDGE_X + ins[0]
    top.offset_top = BASE_TOP + ins[1]
    top.offset_right = -BASE_EDGE_X - ins[2]

## 纯算术：安全区与窗口都取**屏幕像素**、scale = 像素/设计单位。
## 返回 [左, 上, 右] 三个让位量（设计单位，已夹到 0..SAFE_CAP）。
## 窗口比安全区小时（桌面窗口化）交集就是窗口本身 ⇒ 三个 0，摆位不变。
static func safe_insets(safe: Rect2, win: Rect2, scale: float) -> Array[float]:
    var out: Array[float] = [0.0, 0.0, 0.0]
    if scale <= 0.0 or safe.size.x <= 0.0 or win.size.x <= 0.0:
        return out
    out[0] = clampf((safe.position.x - win.position.x) / scale, 0.0, SAFE_CAP)
    out[1] = clampf((safe.position.y - win.position.y) / scale, 0.0, SAFE_CAP)
    out[2] = clampf((win.end.x - safe.end.x) / scale, 0.0, SAFE_CAP)
    return out

# ---------------- Boss 血条（固定 Boss 关专用，信号驱动上屏/收起） ----------------

var _boss_box: PanelContainer = null
var _boss_title_label: Label = null
var _boss_bar: ProgressBar = null
var _boss_active: bool = false

## 顶部居中血条：红斜切大色块 + 魔君名号，P5 剪纸风与顶栏一致
func _build_boss_bar() -> void:
    _boss_box = PanelContainer.new()
    _boss_box.visible = false
    _boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _boss_box.add_theme_stylebox_override("panel", GameStyle.block(GameStyle.BAD_DK, GameStyle.SLANT_BAND, Vector2(4, 5)))
    _boss_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
    _boss_box.offset_left = -240.0
    _boss_box.offset_right = 240.0
    _boss_box.offset_top = 140.0
    _boss_box.offset_bottom = 178.0
    _boss_box.pivot_offset = Vector2(240.0, 19.0)
    add_child(_boss_box)

    var row := HBoxContainer.new()
    row.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.add_theme_constant_override("separation", 10)
    _boss_box.add_child(row)

    _boss_title_label = Label.new()
    _boss_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    GameStyle.label(_boss_title_label, 15, GameStyle.PAPER)
    row.add_child(_boss_title_label)

    _boss_bar = ProgressBar.new()
    _boss_bar.custom_minimum_size = Vector2(300, 16)
    _boss_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    _boss_bar.show_percentage = false
    _boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var styles: Array = GameStyle.bar_styles(Color(0.06, 0.04, 0.06, 0.9), GameStyle.BAD)
    _boss_bar.add_theme_stylebox_override("background", styles[0])
    _boss_bar.add_theme_stylebox_override("fill", styles[1])
    row.add_child(_boss_bar)

func _on_boss_hp_changed(cur: float, max_v: float, title: String) -> void:
    if not _boss_active:
        _boss_active = true
        _boss_title_label.text = title
        _boss_bar.max_value = max_v
        _boss_bar.value = cur
        _boss_box.modulate.a = 1.0
        _boss_box.visible = true
        # 登场弹跳：与 banner / 等级徽章同款 BACK 缓动
        var tw := create_tween()
        tw.tween_property(_boss_box, "scale", Vector2.ONE, 0.22)\
            .from(Vector2(0.6, 0.6)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    elif absf(_boss_bar.value - cur) > 0.5:
        var tw := create_tween()
        tw.tween_property(_boss_bar, "value", cur, 0.15)

func _on_boss_defeated(_title: String) -> void:
    _boss_active = false
    var tw := create_tween()
    tw.tween_property(_boss_box, "modulate:a", 0.0, 0.3)
    tw.tween_callback(func():
        _boss_box.visible = false
        _boss_box.modulate.a = 1.0)

## 供冒烟测试与调试断言：血条当前是否上屏
func is_boss_bar_visible() -> bool:
    return _boss_box != null and _boss_box.visible

var _fps_label: Label = null
var _fps_timer: float = 0.0

func _setup_fps_counter() -> void:
    _fps_label = Label.new()
    _fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _fps_label.position = Vector2(16, 514)
    GameStyle.label(_fps_label, 12, GameStyle.GREY)
    _fps_label.text = "FPS: 60"
    add_child(_fps_label)
    _update_fps_visibility()
    SettingsManager.setting_changed.connect(func(sec: StringName, key: StringName, _val: Variant):
        if sec == &"display" and key == &"show_fps":
            _update_fps_visibility()
    )

func _update_fps_visibility() -> void:
    if _fps_label != null:
        _fps_label.visible = bool(SettingsManager.get_val(&"display", &"show_fps", false))

func _process(delta: float) -> void:
    if _fps_label != null and _fps_label.visible:
        _fps_timer += delta
        if _fps_timer >= 0.25:
            _fps_timer = 0.0
            var fps := Engine.get_frames_per_second()
            _fps_label.text = "FPS: %d" % fps
            var fps_col := GameStyle.GOOD if fps >= 55 else (GameStyle.YELLOW if fps >= 35 else GameStyle.BAD)
            _fps_label.add_theme_color_override("font_color", fps_col)

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
        var chip_color: Color = GameStyle.BLUE_DK if tag in WeaponData.ELEMENTS else GameStyle.YELLOW_DK
        chip.add_theme_stylebox_override("normal", GameStyle.chip(chip_color))
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
