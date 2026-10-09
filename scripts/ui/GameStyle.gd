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

## BBCode 版的硬换行：悟道候选那种 `[center]…\n• 武器总伤害 [b]+15%[/b][/color]…` 的文案，
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

## 把 node 设成一块「整块点得动」的热区：本体收事件，子孙一律不许截。
## 为什么需要它：PanelContainer / Control / ColorRect 的 mouse_filter 默认是 STOP，
## 卡片里再套一层图框（48×48 的描边底）就会在热区中间挖出一个「点了没反应」的洞 ——
## 触屏没有 hover，洞是静默的：代码看着整块可点，真机上只有文字那一小块有反应
## （用户 2026-10-09 真机：法宝图鉴点名字弹卡、点图片没反应）。
## 卡内装饰节点不参与交互，所以整棵子树压成 IGNORE 是安全的；
## 若日后卡里真要放按钮，那层自己改回 STOP 并单独接事件。
static func hotzone(node: Control) -> Control:
    node.mouse_filter = Control.MOUSE_FILTER_STOP
    _ignore_input(node)
    return node

static func _ignore_input(node: Node) -> void:
    for ch in node.get_children():
        if ch is Control:
            (ch as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
        _ignore_input(ch)

## 让一块滚动区「整列都能用手指拖起来」：把里面只为好看的 STOP 容器降成 PASS。
## 为什么必须显式做：Godot 4.7 的 ScrollContainer 拖动滚动走的是「左键按下那一拍 latch 住
## （drag_touching）+ 之后的 MouseMotion 累加 relative」（scene/gui/scroll_container.cpp
## 237-300，整段还被 is_touchscreen_available() 门控，真机上手指按下会转成模拟左键，
## 所以这条链在 Android 成立）。而 PanelContainer / ColorRect / Control 的 mouse_filter
## 默认是 STOP，STOP 会把「按下」这一拍就地吃掉、不再向父级冒泡 —— 卡片盖住多大面积，
## 滑不动的面积就有多大（用户 2026-10-09 真机：传道玉简「灰色卡片滑不动、卡片缝隙能滑」，
## 实测按在卡片上 ScrollContainer 一个事件都收不到，按在缝隙里才冒泡到它）。
## PASS 仍自己收事件，所以卡片点按弹详解照旧，与 hotzone「整块都是热区」不冲突，
## 只是不再拦冒泡。按钮保持原样：BaseButton 自己 accept_event，改它也不会让出这一拍。
## 必须在整页子树建完之后调用（判据 tests/ScrollSwipeCheck.tscn 逐落点采样验证）。
## 这里手写递归而不是 find_children("*", "Control", true)：那个 API 的 owned 参数默认 true，
## 只认 owner 非空的节点，而本项目的卡片全是代码 new() 出来的（owner 为空）→ 会一个都找不到。
static func swipeable(node: Node) -> void:
    for ch in node.get_children():
        var c := ch as Control
        if c != null and not (c is BaseButton) and c.mouse_filter == Control.MOUSE_FILTER_STOP:
            c.mouse_filter = Control.MOUSE_FILTER_PASS
        swipeable(ch)

## 按下→抬起之间允许划过的距离（内容单位），超过就不算点按。
## 14 在 960 基准宽下约 1.5% 屏宽，真机约 10dp —— 与 Android 的 touch slop 同量级：
## 手指按在原地轻微抖动仍算点，有意划动一定超得过。
const TAP_SLACK := 14.0

const _TAP_DOWN_META := "_gs_tap_down"
const _TAP_SCROLL_META := "_gs_tap_scroll"
## 本次手势里「划出去过」的最大距离：手指离按下点的最大距离，与列表被拖走的最大距离，取大的
const _TAP_REACH_META := "_gs_tap_reach"

## 挂一次「真点按」：按下与抬起都留在原地才算点，中途划出去（拖列表）就不触发。
## 为什么必须显式做：滚动区里的卡片为了让手指拖得起列表，mouse_filter 已从 STOP 降成 PASS
## （见 swipeable），于是「按下」那一拍同时被外层 ScrollContainer 拿去 latch 拖动滚动。
## 而点按若只认「左键松开」这一枪（旧 PlayerStatsDialog._is_tap / ManualDialog 卡片），
## 划完列表一松手照样算一次点击 —— 真机上就是「我本来想滑动，不小心就点按了」
## （用户 2026-10-09：属性面板「悟道历程」列表）。
## 尺子取「本次手势划出去过的最大距离」，手指与列表两个来源取大：
## ① 只比按下点与抬起点会漏判 —— 列表跟着手指走，抬起点与按下点可以挨得很近；
## ② 只比按下与抬起那一刻的列表读数会**误杀** —— 手指按在原地的微动（真机必然有）同样
##    会把列表拖走几单位（2026-10-09 灵石阁陈列行实测：微动 4 单位 → 列表动了 4 → 旧尺子
##    阈值 0.5 判成「被拖走过」⇒ 满仓时每一格都点不动）。
## 所以中途的每一次 motion 都要记账，容差用同一个 TAP_SLACK：手指微动仍算点，有意划必超。
## 都没按下过的松开不算点按 —— 按下在别处，这一枪不该由这块热区兑现。
## 判据 tests/TapSwipeCheck.tscn 与 tests/ShopRowScrollCheck.tscn（真发按下-移动-抬起，
## 逐处验「划动不弹、点按照弹」）。
static func tap(node: Control, on_tap: Callable) -> void:
    node.gui_input.connect(func(ev: InputEvent) -> void:
        var mb := ev as InputEventMouseButton
        if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
            if mb.pressed:
                node.set_meta(_TAP_DOWN_META, mb.global_position)
                node.set_meta(_TAP_SCROLL_META, _scroll_offset_above(node))
                node.set_meta(_TAP_REACH_META, 0.0)
                return
            if not node.has_meta(_TAP_DOWN_META):
                return                      # 没在本节点上按下过 → 这一枪不算点
            var down: Vector2 = node.get_meta(_TAP_DOWN_META)
            var scroll0: Vector2 = node.get_meta(_TAP_SCROLL_META, NO_SCROLL_ABOVE)
            var reach: float = node.get_meta(_TAP_REACH_META, 0.0)
            node.remove_meta(_TAP_DOWN_META)
            node.remove_meta(_TAP_SCROLL_META)
            node.remove_meta(_TAP_REACH_META)
            reach = maxf(reach, down.distance_to(mb.global_position))
            if scroll0 != NO_SCROLL_ABOVE:
                reach = maxf(reach, scroll0.distance_to(_scroll_offset_above(node)))
            if reach > TAP_SLACK:
                return
            on_tap.call()
            return
        var mm := ev as InputEventMouseMotion
        if mm != null and node.has_meta(_TAP_DOWN_META):
            var d0: Variant = node.get_meta(_TAP_DOWN_META)
            var s0: Variant = node.get_meta(_TAP_SCROLL_META)
            var r0: float = node.get_meta(_TAP_REACH_META, 0.0)
            if d0 is Vector2:
                r0 = maxf(r0, (d0 as Vector2).distance_to(mm.global_position))
            if s0 is Vector2 and s0 != NO_SCROLL_ABOVE:
                r0 = maxf(r0, (s0 as Vector2).distance_to(_scroll_offset_above(node)))
            node.set_meta(_TAP_REACH_META, r0)
    )

## 「往上没有会滚的父级」的哨兵值：滚动位置永远 >= 0，负数不会与真读数撞
const NO_SCROLL_ABOVE := Vector2(-1.0, -1.0)

## 往上找第一个会滚的父容器，取它此刻的滚动位置（横滑列表读 scroll_horizontal、
## 竖滑读 scroll_vertical；两头都能滚就一起带上）。没有滚动父级返回 NO_SCROLL_ABOVE。
## 为什么两个轴都要：只盯竖滑的话，横滑那一排（灵石阁陈列行）划完一松手照样算点按 ——
## 手指跟着内容走了 200 单位，抬起点与按下点的距离却被内容的位移抵消了一部分。
static func _scroll_offset_above(node: Node) -> Vector2:
    var p := node.get_parent()
    while p != null:
        var sc := p as ScrollContainer
        if sc != null and (sc.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED \
                or sc.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED):
            return Vector2(float(sc.scroll_horizontal), float(sc.scroll_vertical))
        p = p.get_parent()
    return NO_SCROLL_ABOVE

## 滚动条：引擎默认那根浅灰与深蓝面板不搭（真机上像系统控件，不像游戏界面），而且吃掉
## 一整条竖向预算。统一成「轨道不画、滑块一根主蓝细条」：只有内容真摆不下时
## 才露脸（ScrollContainer 的 AUTO 模式已经管「该不该露」，这里只管「露出来长什么样」）。
## 谁在用：灵石阁的货架排与陈列行（WaveShop._ready）。其余滚动面板沿用默认，
## 等谁再动那一屏时一并收口。
static func scrollable(sc: ScrollContainer) -> void:
    if sc == null:
        return
    _scroll_bar(sc.get_h_scroll_bar())
    _scroll_bar(sc.get_v_scroll_bar())

## 滚动条只能靠 modulate 调颜色：theme 的 scroll_background / scroll_grabber 那几张 stylebox，
## 无论是 `bar.add_theme_stylebox_override()` 还是给 bar 挂一份 Theme，画出来都还是默认那根
## 浅灰圆头（实测：节点上 get_theme_stylebox 读回来是我们要的色，屏幕上不动；同一节点
## modulate=红 立刻变红 ⇒ 4.7 的 ScrollBar 绘制不吃这两条路）。灰 × 深蓝 = 一条压在面板底上
## 的暗蓝细带：不抢视线，也不在满屏深蓝里跳出「网页滚动条」。
static func _scroll_bar(bar: ScrollBar) -> void:
    if bar == null:
        return
    bar.modulate = Color(0.34, 0.52, 0.92, 0.85)
