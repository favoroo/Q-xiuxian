class_name GameStyle
extends RefCounted

## 「蓝白黄」大色块扁平化 UI 统一样式工厂（移植 dudu-cocos 的斜切语言）。
## 规则：无圆角、无渐变、无柔光；斜切平行四边形四档斜率；硬错位投影 + 同色压暗厚底边。
## 字体：正文 MiSans-Semibold，大标题 MiSans-Heavy。

const INK := Color("0a0e1a")        # 最深底
const NAVY := Color("121a2e")       # 面板底
const NAVY2 := Color("1a2440")      # 按钮底/未选中
const LINE := Color("2a3550")       # 描线/分隔
const PAPER := Color("f2efe4")      # 纸白
const PAPER_DIM := Color("c9c4b4")  # 次要纸白
const INK_TEXT := Color("0a0e1c")   # 亮面上的墨黑字

const BLUE := Color("2f7dff")       # 主蓝 = 主行动
const BLUE_EDGE := Color("8fb8ff")
const BLUE_DK := Color("123c99")
const YELLOW := Color("ffd24d")     # 点缀黄 = 货币/选中/星
const YELLOW_EDGE := Color("ffe89a")
const YELLOW_DK := Color("8f7414")
const GOOD := Color("7dff9e")       # 治疗/增益
const GOOD_DK := Color("2f8f4c")
const BAD := Color("ff5a5a")        # 危险/扣血
const BAD_DK := Color("8f2020")
const GREY := Color("8f9cbe")       # 暗部正文

const SLANT_PLATE := 3.0
const SLANT_BLOCK := 5.0
const SLANT_BUTTON := 6.0
const SLANT_BAND := 10.0

const FONT_BODY := "res://fonts/MiSans-Semibold.woff2"
const FONT_DISPLAY := "res://fonts/MiSans-Heavy.woff2"

static var _body: FontVariation
static var _display: FontVariation

static func body_font() -> FontVariation:
    if _body == null:
        _body = FontVariation.new()
        _body.base_font = load(FONT_BODY)
        _body.variation_embolden = 0.12
    return _body

static func display_font() -> FontVariation:
    if _display == null:
        _display = FontVariation.new()
        _display.base_font = load(FONT_DISPLAY)
        _display.variation_embolden = 0.08
    return _display

## 基础斜切面板，带硬投影（shadow_size=0 保持边缘锐利）
static func panel(bg: Color, skew_deg: float = SLANT_PLATE, shadow_offset: Vector2 = Vector2(4, 4),
        shadow_col: Color = Color(0, 0, 0, 0.5)) -> StyleBoxFlat:
    var sb := StyleBoxFlat.new()
    sb.bg_color = bg
    sb.skew = Vector2(deg_to_rad(skew_deg), 0.0)
    sb.corner_radius_top_left = 0
    sb.corner_radius_top_right = 0
    sb.corner_radius_bottom_right = 0
    sb.corner_radius_bottom_left = 0
    if shadow_offset != Vector2.ZERO:
        sb.shadow_color = shadow_col
        sb.shadow_size = 0
        sb.shadow_offset = shadow_offset
    return sb

## dudu 实底大色块：主色面 + 同色压暗厚底边 + 描边 + 硬投影
static func block(bg: Color, skew_deg: float = SLANT_BLOCK, shadow_offset: Vector2 = Vector2(4, 5)) -> StyleBoxFlat:
    var sb := panel(bg, skew_deg, shadow_offset)
    sb.border_width_left = 2
    sb.border_width_top = 2
    sb.border_width_right = 2
    sb.border_width_bottom = 5
    sb.border_color = bg.darkened(0.4)
    return sb

## 带外描边的斜切面板（武器槽/卡片描边态）
static func outlined_panel(bg: Color, border: Color, border_w: int = 2, skew_deg: float = SLANT_BLOCK) -> StyleBoxFlat:
    var sb := panel(bg, skew_deg, Vector2.ZERO)
    sb.border_width_left = border_w
    sb.border_width_top = border_w
    sb.border_width_right = border_w
    sb.border_width_bottom = border_w
    sb.border_color = border
    return sb

## 凹陷槽：经验槽轨道/滑杆/未选中
static func slot() -> StyleBoxFlat:
    var sb := panel(NAVY2, 0.0, Vector2.ZERO)
    sb.border_width_left = 1
    sb.border_width_top = 1
    sb.border_width_right = 1
    sb.border_width_bottom = 3
    sb.border_color = LINE
    return sb

## 进度条成对样式（track 底 + fill 面）
static func bar_styles(track: Color, fill: Color) -> Array:
    var bg := slot()
    bg.bg_color = track
    var fl := panel(fill, 0.0, Vector2.ZERO)
    return [bg, fl]

## 色签 chip：小面积斜切更陡才读得出形状
static func chip(face: Color) -> StyleBoxFlat:
    return block(face, SLANT_BAND, Vector2(2, 3))

static func label(l: Label, size: int, color: Color = PAPER, outline: int = 0,
        outline_col: Color = INK, display: bool = false) -> Label:
    l.add_theme_font_override("font", display_font() if display else body_font())
    l.add_theme_font_size_override("font_size", size)
    l.add_theme_color_override("font_color", color)
    if outline > 0:
        l.add_theme_constant_override("outline_size", outline)
        l.add_theme_color_override("font_outline_color", outline_col)
    return l

## 按钮三态（normal / hover / pressed）
static func button(btn: Button, bg: Color, hover_bg: Color, font_size: int,
        font_color: Color = PAPER, skew_deg: float = SLANT_BUTTON,
        hover_color: Color = Color(0, 0, 0, 0)) -> void:
    var normal := block(bg, skew_deg, Vector2(3, 4))
    var hover := block(hover_bg, skew_deg, Vector2(3, 4))
    btn.add_theme_stylebox_override("normal", normal)
    btn.add_theme_stylebox_override("hover", hover)
    btn.add_theme_stylebox_override("pressed", block(hover_bg.darkened(0.15), skew_deg, Vector2(1, 1)))
    btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
    btn.add_theme_font_override("font", body_font())
    btn.add_theme_font_size_override("font_size", font_size)
    btn.add_theme_color_override("font_color", font_color)
    btn.add_theme_color_override("font_hover_color", hover_color if hover_color.a > 0 else font_color)
    btn.add_theme_color_override("font_pressed_color", hover_color if hover_color.a > 0 else font_color)
