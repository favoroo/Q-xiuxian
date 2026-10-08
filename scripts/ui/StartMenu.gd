class_name StartMenu
extends Control

## P5 大色块风格开始界面：实底墨蓝 + 斜切色块装饰 + 黄色标题块。
## 点「开始游戏」后淡出，交给 StartWeaponSelect 选本命法器（paused 链不中断）。

var _title_block: PanelContainer
var _sub_chip: Label
var _buttons: Array[Button] = []
var _decor_blocks: Array[Control] = []

func _ready() -> void:
    visible = false
    process_mode = Node.PROCESS_MODE_ALWAYS
    mouse_filter = Control.MOUSE_FILTER_STOP
    _build_background()
    _build_decor()
    _build_center()
    _build_version_label()

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

    # 横向斜切深蓝带（横穿标题后方）
    var band := PanelContainer.new()
    band.add_theme_stylebox_override("panel", GameStyle.panel(GameStyle.NAVY2, GameStyle.SLANT_BAND, Vector2.ZERO))
    band.set_anchors_preset(Control.PRESET_CENTER_TOP)
    band.custom_minimum_size = Vector2(1100, 150)
    band.position = Vector2(-550, 108)
    band.mouse_filter = Control.MOUSE_FILTER_IGNORE
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

    # 四角黄色括号（呼应灵田界碑语言）
    var bracket_len := 56.0
    var inset := 26.0
    var corners := [
        Vector2(inset, inset), Vector2(1, 1),
        Vector2(960 - inset, inset), Vector2(-1, 1),
        Vector2(960 - inset, 540 - inset), Vector2(-1, -1),
        Vector2(inset, 540 - inset), Vector2(1, -1),
    ]
    for i in range(0, corners.size(), 2):
        var origin: Vector2 = corners[i]
        var sgn: Vector2 = corners[i + 1]
        var bracket := Line2D.new()
        bracket.points = PackedVector2Array([
            origin + Vector2(-sgn.x * bracket_len, 0),
            origin,
            origin + Vector2(0, -sgn.y * bracket_len),
        ])
        bracket.width = 6.0
        bracket.default_color = GameStyle.YELLOW
        bracket.joint_mode = Line2D.LINE_JOINT_ROUND
        bracket.begin_cap_mode = Line2D.LINE_CAP_ROUND
        bracket.end_cap_mode = Line2D.LINE_CAP_ROUND
        decor.add_child(bracket)

func _build_center() -> void:
    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    center.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(center)

    var vbox := VBoxContainer.new()
    vbox.add_theme_constant_override("separation", 18)
    vbox.alignment = BoxContainer.ALIGNMENT_CENTER
    center.add_child(vbox)

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
    spacer.custom_minimum_size = Vector2(0, 26)
    vbox.add_child(spacer)

    # 按钮列
    _buttons.append(_make_button(vbox, "开 始 游 戏", 24, Vector2(300, 58),
        GameStyle.BLUE, GameStyle.YELLOW, GameStyle.PAPER, _on_start_pressed))
    _buttons.append(_make_button(vbox, "检 查 更 新", 15, Vector2(220, 42),
        GameStyle.NAVY2, GameStyle.BLUE, GameStyle.PAPER_DIM, _on_update_pressed))
    _buttons.append(_make_button(vbox, "退 出 游 戏", 15, Vector2(220, 42),
        GameStyle.NAVY2, GameStyle.BAD, GameStyle.PAPER_DIM, _on_quit_pressed))

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

func _build_version_label() -> void:
    var ver := Label.new()
    ver.text = "修仙幸存者 " + Version.APP_VERSION_NAME
    ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
    ver.position = Vector2(-170, -30)
    GameStyle.label(ver, 11, GameStyle.GREY)
    add_child(ver)

## 打开开始界面（入场动画：标题弹入 + 按钮错峰弹入）
func open() -> void:
    visible = true
    modulate.a = 0.0
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
        var weapon_select := get_parent().get_node_or_null("StartWeaponSelect")
        if weapon_select != null:
            weapon_select.show_select()
    )

func _on_update_pressed() -> void:
    UpdateManager.check_for_update(true)

func _on_quit_pressed() -> void:
    get_tree().quit()
