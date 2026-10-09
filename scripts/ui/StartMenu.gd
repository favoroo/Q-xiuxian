class_name StartMenu
extends Control

## P5 大色块风格开始界面：实底墨蓝 + 斜切色块装饰 + 黄色标题块。
## 点「开始游戏」后淡出，交给 StartWeaponSelect 选本命法器（paused 链不中断）。

signal settings_requested
signal career_requested
signal manual_requested

var _title_block: PanelContainer
var _sub_chip: Label
var _buttons: Array[Button] = []
var _decor_blocks: Array[Control] = []
var _brackets: Array[Line2D] = []
var _update_btn: Button
var _update_reset_tween: Tween
var _danger_buttons: Array[Button] = []
const DANGER_NAMES := ["凡尘", "微澜", "惊涛", "炼狱", "无间", "天劫"]

## 四角括号是「贴着屏角」的装饰：坐标必须跟着这一屏的实得尺寸走。
## 旧写法把 960×540 拍死在点上 ⇒ 20:9 屏（可视宽 1202）那两只括号浮在屏幕中段，
## 4:3 屏（可视高 720）下面两只落在半空。判据 LayoutCheck 逐档屏宽度量。
const BRACKET_LEN := 56.0
const BRACKET_INSET := 26.0
## 按钮列行距的下限：视口再矮也不许挤成一条缝
const CENTER_SEP_MIN := 5
var _center_vbox: VBoxContainer = null

func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED and not _brackets.is_empty():
        _layout_brackets()

func _ready() -> void:
    visible = false
    process_mode = Node.PROCESS_MODE_ALWAYS
    mouse_filter = Control.MOUSE_FILTER_STOP
    _build_background()
    _build_decor()
    _build_center()
    _build_version_label()
    _fit_center_column()
    UpdateManager.update_available.connect(_on_update_available)
    UpdateManager.no_update_found.connect(_on_no_update_found)
    UpdateManager.check_failed.connect(_on_check_failed)

func _build_background() -> void:
    var bg := ColorRect.new()
    bg.color = GameStyle.INK
    bg.set_anchors_preset(Control.PRESET_FULL_RECT)
    bg.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(bg)

func _build_decor() -> void:
    var decor := Control.new()
    decor.set_anchors_preset(Control.PRESET_FULL_RECT)
    decor.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(decor)

    # 横向斜切深蓝带（横穿标题后方）：有意比屏宽，两头出血 ⇒ 判据放行这一格
    var band := PanelContainer.new()
    band.add_theme_stylebox_override("panel", GameStyle.panel(GameStyle.NAVY2, GameStyle.SLANT_BAND, Vector2.ZERO))
    band.set_anchors_preset(Control.PRESET_CENTER_TOP)
    band.custom_minimum_size = Vector2(1100, 150)
    band.position = Vector2(-550, 108)
    band.mouse_filter = Control.MOUSE_FILTER_IGNORE
    band.set_meta("layout_bleed", true)
    decor.add_child(band)
    _decor_blocks.append(band)

    # 点缀：左侧黄色斜切块 + 右下主蓝斜切块
    var yblk := PanelContainer.new()
    yblk.add_theme_stylebox_override("panel", GameStyle.block(GameStyle.YELLOW, GameStyle.SLANT_BAND, Vector2(5, 6)))
    yblk.custom_minimum_size = Vector2(64, 22)
    yblk.position = Vector2(150, 246)
    yblk.rotation = deg_to_rad(-4.0)
    yblk.mouse_filter = Control.MOUSE_FILTER_IGNORE
    decor.add_child(yblk)
    _decor_blocks.append(yblk)

    var bblk := PanelContainer.new()
    bblk.add_theme_stylebox_override("panel", GameStyle.block(GameStyle.BLUE, GameStyle.SLANT_BAND, Vector2(5, 6)))
    bblk.custom_minimum_size = Vector2(90, 18)
    bblk.position = Vector2(730, 420)
    bblk.rotation = deg_to_rad(3.0)
    bblk.mouse_filter = Control.MOUSE_FILTER_IGNORE
    decor.add_child(bblk)
    _decor_blocks.append(bblk)

    # 四角黄色括号（呼应灵田界碑语言）：坐标现读这一屏的实得尺寸。
    # 旧写法把 960×540 拍死在点上 ⇒ 20:9 屏（可视宽 1202）右边两只浮在屏幕中段，
    # 4:3 屏（可视高 720）下面两只落在半空。
    for i in range(4):
        var bracket := Line2D.new()
        bracket.width = 6.0
        bracket.default_color = GameStyle.YELLOW
        bracket.joint_mode = Line2D.LINE_JOINT_ROUND
        bracket.begin_cap_mode = Line2D.LINE_CAP_ROUND
        bracket.end_cap_mode = Line2D.LINE_CAP_ROUND
        decor.add_child(bracket)
        _brackets.append(bracket)
    _layout_brackets()

## 左上/右上/右下/左下各一只，开口朝屏心
func _layout_brackets() -> void:
    var w := size.x
    var h := size.y
    if w <= 0.0 or h <= 0.0:
        return
    var corners := [
        Vector2(BRACKET_INSET, BRACKET_INSET), Vector2(1, 1),
        Vector2(w - BRACKET_INSET, BRACKET_INSET), Vector2(-1, 1),
        Vector2(w - BRACKET_INSET, h - BRACKET_INSET), Vector2(-1, -1),
        Vector2(BRACKET_INSET, h - BRACKET_INSET), Vector2(1, -1),
    ]
    for i in range(_brackets.size()):
        var origin: Vector2 = corners[i * 2]
        var sgn: Vector2 = corners[i * 2 + 1]
        _brackets[i].points = PackedVector2Array([
            origin + Vector2(-sgn.x * BRACKET_LEN, 0),
            origin,
            origin + Vector2(0, -sgn.y * BRACKET_LEN),
        ])

func _build_center() -> void:
    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    center.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(center)

    var vbox := VBoxContainer.new()
    vbox.add_theme_constant_override("separation", 14)
    vbox.alignment = BoxContainer.ALIGNMENT_CENTER
    center.add_child(vbox)
    _center_vbox = vbox

    # 标题：黄色斜切大色块 + 墨黑超大字
    _title_block = PanelContainer.new()
    _title_block.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    var tstyle := GameStyle.block(GameStyle.YELLOW, GameStyle.SLANT_BLOCK, Vector2(8, 9))
    tstyle.content_margin_left = 34.0
    tstyle.content_margin_top = 10.0
    tstyle.content_margin_right = 34.0
    tstyle.content_margin_bottom = 14.0
    _title_block.add_theme_stylebox_override("panel", tstyle)
    var title := Label.new()
    title.text = "修 仙 幸 存 者"
    GameStyle.label(title, 56, GameStyle.INK_TEXT, 0, GameStyle.INK, true)
    _title_block.add_child(title)
    vbox.add_child(_title_block)

    # 副标题：主蓝 chip
    _sub_chip = Label.new()
    _sub_chip.text = " 斩 妖 修 行 · 一 念 飞 升 "
    _sub_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _sub_chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    _sub_chip.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.BLUE))
    GameStyle.label(_sub_chip, 14, GameStyle.PAPER)
    vbox.add_child(_sub_chip)

    var spacer := Control.new()
    spacer.custom_minimum_size = Vector2(0, 16)
    vbox.add_child(spacer)

    # 危险度选择：通关当前最高档解锁下一档（落盘持久化，见 GameManager）
    _build_danger_row(vbox)

    # 按钮列
    _buttons.append(_make_button(vbox, "开 始 游 戏", 24, Vector2(300, 56),
        GameStyle.BLUE, GameStyle.YELLOW, GameStyle.PAPER, _on_start_pressed))
    _buttons.append(_make_button(vbox, "修  仙  志", 15, Vector2(220, 38),
        GameStyle.NAVY2, GameStyle.YELLOW, GameStyle.PAPER, _on_career_pressed))
    _buttons.append(_make_button(vbox, "教 程 手 册", 15, Vector2(220, 38),
        GameStyle.NAVY2, GameStyle.YELLOW, GameStyle.PAPER, _on_manual_pressed))
    _buttons.append(_make_button(vbox, "游 戏 设 置", 15, Vector2(220, 38),
        GameStyle.NAVY2, GameStyle.YELLOW, GameStyle.PAPER_DIM, _on_settings_pressed))
    _update_btn = _make_button(vbox, "检 查 更 新", 15, Vector2(220, 38),
        GameStyle.NAVY2, GameStyle.BLUE, GameStyle.PAPER_DIM, _on_update_pressed)
    _buttons.append(_update_btn)
    _buttons.append(_make_button(vbox, "退 出 游 戏", 15, Vector2(220, 38),
        GameStyle.NAVY2, GameStyle.BAD, GameStyle.PAPER_DIM, _on_quit_pressed))

## 按钮列的行距按 viewport 现算：主菜单又加了「修仙志」「教程手册」两颗按钮后，
## 六颗 + 危险度行 + 标题在 960×540（16:9 真机的设计高）下要 583 高 ⇒ 「退出游戏」整颗掉到屏外
## （判据 LayoutCheck 量到的就是这一格）。这里不砍文案、不压字号，只按剩余高度折算行距。
func _fit_center_column() -> void:
    if _center_vbox == null or not is_instance_valid(_center_vbox):
        return
    var n := _center_vbox.get_child_count()
    if n < 2:
        return
    var sep := int(_center_vbox.get_theme_constant("separation"))
    var body: float = _center_vbox.get_combined_minimum_size().y - float(sep) * float(n - 1)
    var room: float = get_viewport().get_visible_rect().size.y - 16.0
    if body + float(sep) * float(n - 1) <= room:
        return
    _center_vbox.add_theme_constant_override(
        "separation", maxi(int((room - body) / float(n - 1)), CENTER_SEP_MIN))

func _make_button(parent: Control, text: String, font_size: int, min_size: Vector2,
        bg: Color, hover_bg: Color, font_col: Color, callback: Callable) -> Button:
    var btn := Button.new()
    btn.text = text
    btn.custom_minimum_size = min_size
    btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    btn.focus_mode = Control.FOCUS_NONE
    GameStyle.button(btn, bg, hover_bg, font_size, font_col, GameStyle.SLANT_BUTTON)
    btn.pressed.connect(callback)
    parent.add_child(btn)
    return btn

## 危险度选择行：未解锁的档位灰显锁定，当前选中档黄底高亮
func _build_danger_row(vbox: VBoxContainer) -> void:
    var chip := Label.new()
    chip.text = " 危 险 度 · 通 关 解 锁 "
    chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    chip.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.NAVY2))
    GameStyle.label(chip, 12, GameStyle.PAPER_DIM)
    vbox.add_child(chip)

    var row := HBoxContainer.new()
    row.alignment = BoxContainer.ALIGNMENT_CENTER
    row.add_theme_constant_override("separation", 8)
    vbox.add_child(row)
    _danger_buttons.clear()
    for d in range(GameBalance.DANGER_MAX + 1):
        var btn := Button.new()
        btn.custom_minimum_size = Vector2(62, 32)
        btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        btn.focus_mode = Control.FOCUS_NONE
        var dd := d
        btn.pressed.connect(func(): _on_danger_pressed(dd))
        row.add_child(btn)
        _danger_buttons.append(btn)
    _refresh_danger_row()

func _refresh_danger_row() -> void:
    for d in range(_danger_buttons.size()):
        var btn := _danger_buttons[d]
        var unlocked := d <= GameManager.max_danger_unlocked
        btn.disabled = not unlocked
        btn.text = DANGER_NAMES[d] if unlocked else "锁"
        if d == GameManager.danger_level and unlocked:
            GameStyle.button(btn, GameStyle.YELLOW, GameStyle.YELLOW_EDGE, 13, GameStyle.INK_TEXT, GameStyle.SLANT_BUTTON)
        elif unlocked:
            GameStyle.button(btn, GameStyle.NAVY2, GameStyle.LINE, 13, GameStyle.PAPER_DIM, GameStyle.SLANT_BUTTON)
        else:
            GameStyle.button(btn, GameStyle.INK, GameStyle.LINE, 13, GameStyle.GREY, GameStyle.SLANT_BUTTON)

func _on_danger_pressed(d: int) -> void:
    GameManager.set_danger(d)
    _refresh_danger_row()

func _build_version_label() -> void:
    var ver := Label.new()
    ver.text = "修仙幸存者 " + Version.APP_VERSION_NAME
    ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
    ver.position = Vector2(-170, -30)
    GameStyle.label(ver, 11, GameStyle.GREY)
    add_child(ver)

## 打开开始界面（入场动画：标题弹入 + 按钮错峰弹入）
func open() -> void:
    _fit_center_column()
    visible = true
    modulate.a = 0.0
    _refresh_danger_row()   # 通关回来后可能刚解锁新档位
    var tw := create_tween()
    tw.tween_property(self, "modulate:a", 1.0, 0.22)

    # 等一帧让容器完成布局，pivot 才准确
    await get_tree().process_frame
    _title_block.pivot_offset = _title_block.size * 0.5
    _title_block.scale = Vector2(0.6, 0.6)
    _title_block.modulate.a = 0.0
    var ttw := _title_block.create_tween().set_parallel(true)
    ttw.tween_property(_title_block, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.08)
    ttw.tween_property(_title_block, "modulate:a", 1.0, 0.2).set_delay(0.08)

    var idx := 0
    for btn in _buttons:
        btn.pivot_offset = btn.size * 0.5
        btn.scale = Vector2(0.7, 0.7)
        btn.modulate.a = 0.0
        var btw := btn.create_tween().set_parallel(true)
        var delay := 0.2 + float(idx) * 0.07
        btw.tween_property(btn, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(delay)
        btw.tween_property(btn, "modulate:a", 1.0, 0.16).set_delay(delay)
        idx += 1

## 关闭开始界面（淡出隐藏，不触发后续流程）
func close() -> void:
    if not visible:
        return
    var tw := create_tween()
    tw.tween_property(self, "modulate:a", 0.0, 0.2)
    tw.tween_callback(func(): visible = false)

func _on_start_pressed() -> void:
    AudioManager.play_sfx("level_up", 0.9)
    if ResourceLoader.exists("res://assets/audio/vo_guide_start.wav"):
        AudioManager.play_voice(load("res://assets/audio/vo_guide_start.wav"))
    var tw := create_tween()
    tw.tween_property(self, "modulate:a", 0.0, 0.2)
    tw.tween_callback(func():
        visible = false
        var cult_select := get_parent().get_node_or_null("CultivatorSelect")
        if cult_select != null:
            cult_select.show_select()
        else:
            var weapon_select := get_parent().get_node_or_null("StartWeaponSelect")
            if weapon_select != null:
                weapon_select.show_select()
    )

func _on_update_pressed() -> void:
    if not is_instance_valid(_update_btn):
        return
    if not UpdateManager.pending_update.is_empty():
        UpdateManager.show_update_dialog(UpdateManager.pending_update)
        return
    if UpdateManager.is_checking:
        _cancel_reset_timer()
        _update_btn.text = "正在检查更新..."
        UpdateManager.check_for_update(true)
        UpdateManager.show_toast("正在检查最新版本，请稍候...", GameStyle.BLUE)
        return

    _cancel_reset_timer()
    _update_btn.text = "正在检查更新..."
    UpdateManager.check_for_update(true)

func _on_update_available(info: Dictionary) -> void:
    if not is_instance_valid(_update_btn):
        return
    _cancel_reset_timer()
    _update_btn.text = "发现新版 %s!" % info.get("tag_name", "")

func _on_no_update_found() -> void:
    if not is_instance_valid(_update_btn):
        return
    _cancel_reset_timer()
    _update_btn.text = "已是最新版本"
    _update_reset_tween = create_tween()
    _update_reset_tween.tween_interval(2.5)
    _update_reset_tween.tween_callback(func():
        if is_instance_valid(_update_btn):
            _update_btn.text = "检 查 更 新"
    )

func _on_check_failed(_err_msg: String) -> void:
    if not is_instance_valid(_update_btn):
        return
    _cancel_reset_timer()
    _update_btn.text = "检查失败，请重试"
    _update_reset_tween = create_tween()
    _update_reset_tween.tween_interval(2.5)
    _update_reset_tween.tween_callback(func():
        if is_instance_valid(_update_btn):
            _update_btn.text = "检 查 更 新"
    )

func _cancel_reset_timer() -> void:
    if _update_reset_tween != null and _update_reset_tween.is_valid():
        _update_reset_tween.kill()
        _update_reset_tween = null

func _on_settings_pressed() -> void:
    settings_requested.emit()

func _on_career_pressed() -> void:
    career_requested.emit()

func _on_manual_pressed() -> void:
    manual_requested.emit()

func _on_quit_pressed() -> void:
    get_tree().quit()
