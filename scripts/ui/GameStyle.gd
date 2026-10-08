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

# ---------------- 折行：把「这一句要切几行」从引擎手里拿回来 ----------------
##
## 为什么要自己切：同一段代码、同一份字体度量，macOS 上 `AUTOWRAP_WORD` 会折成三行，
## Android 真机上却画成一整行压到邻卡上（用户 2026-10-08 真机图：「都显示在一行里面叠在一起，
## 都看不清了」）。折得开折不开，取决于引擎给这段文字找到了几个断点 —— 那是跨平台、
## 跨字体不保证一致的自由量。把换行符切进文本里，就没有这个变量了。
##
## 中文排版的两条禁则一起做了（触屏上折错了比不折更难看）：
##   行首不许出现收尾标点（，.。！？）），遇到就把前一个字一起带下去；
##   行尾不许留下开括号（（【“），遇到就把它挪到下一行开头。

## 不能出现在行首的标点（收尾/停顿类）
const NO_LINE_START := "，。、；：！？）】》」』”’…—％%,.;:!?)）]}’”·"
## 不能出现在行尾的标点（起头类）
const NO_LINE_END := "（【《「『“‘(["

## 一个 token 是不是「不可断的整体」：拉丁字母/数字与夹在它们中间的符号
## （Lv.3 / +15% / -12% / ×1.8 都不许从中间切开）
static func _is_word_char(ch: String) -> bool:
    var u := ch.unicode_at(0)
    if u >= 48 and u <= 57:
        return true
    if u >= 65 and u <= 90 or u >= 97 and u <= 122:
        return true
    return u in [37, 43, 45, 46, 47, 95]  # % + - . / _

## 按可用宽把一段文字切成硬换行，返回可直接塞进 Label.text 的字符串。
## `reserve` = 从可用宽里再扣掉的安全量（描边/斜切会占宽度）。默认留 2 单位不贴边：
## 贴边那一行引擎会判成「装不下」而自己再折一次，色签上就多出一行孤字
## （灵石阁那枚「丹/药」竖排就是这个）。
static func wrap_cjk(text: String, font: Font, font_size: int, max_w: float,
        reserve: float = 2.0) -> String:
    if text == "" or max_w <= 0.0:
        return text
    var budget: float = maxf(8.0, max_w - reserve)
    var lines: Array[String] = []
    for seg in text.split("\n"):
        lines.append(_wrap_one(seg, font, font_size, budget))
    # 行尾禁则：把留在行尾的开括号挪到下一行开头（只在下一行存在时挪）
    for i in range(lines.size() - 1):
        while lines[i].length() > 1 and NO_LINE_END.contains(lines[i][lines[i].length() - 1]):
            lines[i + 1] = lines[i][lines[i].length() - 1] + lines[i + 1]
            lines[i] = lines[i].substr(0, lines[i].length() - 1)
    return "\n".join(lines)

static func _wrap_one(seg: String, font: Font, font_size: int, budget: float) -> String:
    if seg == "":
        return ""
    var line := ""
    var line_w := 0.0
    var out := PackedStringArray()
    for tok in _tokens(seg):
        var tw := _text_w(tok, font, font_size)
        if line != "" and line_w + tw > budget:
            if tok.length() == 1 and NO_LINE_START.contains(tok) and line.length() > 1:
                var last: String = line[line.length() - 1]
                line = line.substr(0, line.length() - 1)
                out.append(line)
                line = last + tok
                line_w = _text_w(line, font, font_size)
            else:
                out.append(line)
                line = tok
                line_w = tw
        else:
            line += tok
            line_w += tw
        # 单个 token 就超宽（长英文词）：按字强切，不许撑破卡片
        while line_w > budget and line.length() > 1:
            var cut := line.length() - 1
            while cut > 1 and _text_w(line.substr(0, cut), font, font_size) > budget:
                cut -= 1
            out.append(line.substr(0, cut))
            line = line.substr(cut)
            line_w = _text_w(line, font, font_size)
    if line != "":
        out.append(line)
    return "\n".join(out)

static func _tokens(text: String) -> Array[String]:
    var out: Array[String] = []
    var i := 0
    while i < text.length():
        if _is_word_char(text[i]):
            var j := i
            while j < text.length() and _is_word_char(text[j]):
                j += 1
            out.append(text.substr(i, j - i))
            i = j
        else:
            out.append(text[i])
            i += 1
    return out

## 量一段文字的宽。字体没加载（base_font 为 null 时 get_string_size 回 0）就按
## 1 em 估 —— 真机上兜底字体里的汉字正好约 1 em，估出来的行宽与画出来的对得上。
static func _text_w(text: String, font: Font, font_size: int) -> float:
    if font == null:
        return float(text.length()) * float(font_size)
    var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
    if w <= 0.0:
        return float(text.length()) * float(font_size)
    return w

## 已经切好硬换行的文案，最宽那一行有多宽：色签/徽记这类「要贴着字走」的控件，
## 把 custom_minimum_size.x 钉成这个数 —— 既不会缩成一个字一行，也不会撑成通宽一条。
static func line_max_w(text: String, font: Font, font_size: int) -> float:
    var m := 0.0
    for line in text.split("\n"):
        m = maxf(m, _text_w(line, font, font_size))
    return m

## 色签要钉的宽：贴着字走，再留一点余量（stylebox 的左右内边距与取整会吃掉几单位，
## 贴边就会被引擎再折一次，多出一行孤字）
const CHIP_PAD := 6.0

static func chip_pin_w(text: String, font: Font, font_size: int) -> float:
    return line_max_w(text, font, font_size) + CHIP_PAD

## BBCode 版的硬换行：悟道三选一那种 `[center]…\n• 武器总伤害 [b]+15%[/b][/color]…` 的文案，
## 标签零宽、可见字符才占宽，所以逐字走一遍、只在可见字符之间下刀。
## 标签状态是跨行延续的（RichTextLabel 不在换行处重置 [color]/[b]），所以从中间断开
## 不会漏闭合 —— 这也是为什么这里能切、而纯文本那套 `wrap_cjk` 不能直接拿来用。
static func wrap_bbcode(text: String, font: Font, font_size: int, max_w: float,
        reserve: float = 2.0) -> String:
    if text == "" or max_w <= 0.0:
        return text
    var budget: float = maxf(8.0, max_w - reserve)
    var out := PackedStringArray()
    for seg in text.split("\n"):
        out.append(_wrap_bbcode_one(seg, font, font_size, budget))
    return "\n".join(out)

static func _wrap_bbcode_one(seg: String, font: Font, font_size: int, budget: float) -> String:
    var line := ""
    var last_vis_at := -1     # line 里最后一个「可见字符」的下标（行首禁则要把它带下去）
    var done := ""
    var i := 0
    while i < seg.length():
        var ch := seg[i]
        if ch == "[":
            var close := seg.find("]", i)
            if close >= 0:
                line += seg.substr(i, close - i + 1)   # 标签零宽，跟着当前行走
                i = close + 1
                continue
        if _visible_w(line, font, font_size) + _text_w(ch, font, font_size) > budget and last_vis_at >= 0:
            if ch.length() == 1 and NO_LINE_START.contains(ch):
                done += line.substr(0, last_vis_at) + "\n"
                line = line.substr(last_vis_at) + ch
            else:
                done += line + "\n"
                line = ch
            last_vis_at = -1
        else:
            last_vis_at = line.length()
            line += ch
        i += 1
    return done + line

## 一段 BBCode 里可见字符的宽（标签不算）
static func _visible_w(s: String, font: Font, font_size: int) -> float:
    return _text_w(_strip_bbcode(s), font, font_size)

static func _strip_bbcode(s: String) -> String:
    var out := ""
    var i := 0
    while i < s.length():
        if s[i] == "[":
            var close := s.find("]", i)
            if close >= 0:
                i = close + 1
                continue
        out += s[i]
        i += 1
    return out

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
    # 样式入口即反馈入口：全项目按钮的点击音在这里统一挂，避免每个界面各写一遍。
    # meta 标记防止同一按钮被重复刷新样式时挂出多重连接（一次点击响两声）。
    if not btn.has_meta("sfx_wired"):
        btn.set_meta("sfx_wired", true)
        btn.pressed.connect(func() -> void: AudioManager.play_sfx("ui_click"))
