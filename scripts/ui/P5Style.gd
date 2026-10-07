class_name P5Style
extends RefCounted

## P5（女神异闻录5）式大色块扁平化 UI 的统一色板与样式工厂。
## 规则：无圆角、无渐变、无柔光；斜切平行四边形 + 硬投影；粗体大字。

const RED := Color("e60012")
const DARK_RED := Color("b3000e")
const BLACK := Color("17141c")
const INK := Color("08070b")
const WHITE := Color("f5f2ea")
const YELLOW := Color("ffd400")
const GREY := Color("57515e")

const FONT_PATH := "res://assets/fonts/game_font.ttc"

static var _bold: FontVariation
static var _italic: FontVariation


## W6 粗体字面（ttc 集合第 2 个 face）+ 加粗
static func bold_font() -> FontVariation:
    if _bold == null:
        _bold = FontVariation.new()
        _bold.base_font = load(FONT_PATH)
        _bold.variation_face_index = 2
        _bold.variation_embolden = 0.35
    return _bold


## P5 式右倾仿斜体（在粗体基础上做字形剪切）
static func italic_font() -> FontVariation:
    if _italic == null:
        _italic = bold_font().duplicate()
        _italic.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(0.22, 1.0), Vector2.ZERO)
    return _italic


## 斜切色块面板，带硬投影（shadow_size=0 保持边缘锐利）
static func panel(bg: Color, skew_deg: float = 8.0, shadow_offset: Vector2 = Vector2(4, 4),
        shadow_col: Color = Color(0, 0, 0, 0.85)) -> StyleBoxFlat:
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


## 带描边的斜切面板（如白框黑底武器槽）
static func outlined_panel(bg: Color, border: Color, border_w: int = 2, skew_deg: float = 8.0) -> StyleBoxFlat:
    var sb := panel(bg, skew_deg, Vector2.ZERO)
    sb.border_width_left = border_w
    sb.border_width_top = border_w
    sb.border_width_right = border_w
    sb.border_width_bottom = border_w
    sb.border_color = border
    return sb


## 进度条成对样式（track 底 + fill 面），fill 覆盖 track
static func bar_styles(track: Color, fill: Color, skew_deg: float = 0.0) -> Array:
    var bg := StyleBoxFlat.new()
    bg.bg_color = track
    bg.corner_radius_top_left = 0
    bg.corner_radius_top_right = 0
    bg.corner_radius_bottom_right = 0
    bg.corner_radius_bottom_left = 0
    if skew_deg != 0.0:
        bg.skew = Vector2(deg_to_rad(skew_deg), 0.0)
    var fl := bg.duplicate()
    fl.bg_color = fill
    return [bg, fl]


## 统一标签样式：默认粗体；italic=true 用 P5 右倾体
static func label(l: Label, size: int, color: Color = WHITE, outline: int = 0,
        outline_col: Color = INK, italic: bool = false) -> Label:
    l.add_theme_font_override("font", italic_font() if italic else bold_font())
    l.add_theme_font_size_override("font_size", size)
    l.add_theme_color_override("font_color", color)
    if outline > 0:
        l.add_theme_constant_override("outline_size", outline)
        l.add_theme_color_override("font_outline_color", outline_col)
    return l


## 按钮三态（normal / hover / pressed + 悬停字色反转）
static func button(btn: Button, bg: Color, hover_bg: Color, font_size: int,
        font_color: Color = WHITE, skew_deg: float = 8.0,
        hover_color: Color = Color(0, 0, 0, 0)) -> void:
    var normal := panel(bg, skew_deg, Vector2(3, 3))
    var hover := panel(hover_bg, skew_deg, Vector2(3, 3))
    btn.add_theme_stylebox_override("normal", normal)
    btn.add_theme_stylebox_override("hover", hover)
    btn.add_theme_stylebox_override("pressed", panel(hover_bg.darkened(0.15), skew_deg, Vector2(1, 1)))
    btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
    btn.add_theme_font_override("font", bold_font())
    btn.add_theme_font_size_override("font_size", font_size)
    btn.add_theme_color_override("font_color", font_color)
    btn.add_theme_color_override("font_hover_color", hover_color if hover_color.a > 0 else font_color)
    btn.add_theme_color_override("font_pressed_color", hover_color if hover_color.a > 0 else font_color)
