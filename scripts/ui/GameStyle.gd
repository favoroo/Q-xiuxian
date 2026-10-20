class_name GameStyle
extends RefCounted

## 「新野兽派」UI 统一样式工厂（纯黑舞台 × 宣纸白面板 × 纯黑粗框 × 硬偏移影）。
## 规则：全直角、无圆角、无渐变、无柔光；边框纯黑等宽；硬影零模糊零扩散、不透明纯黑。
## 色即功能：品红 = 主行动/选中，点缀黄 = 金币/星级，朱砂 = 危险，增益绿 = 治疗。
## 动效口径：颜色/阴影瞬间硬切（Brutal Snap），位置/缩放/透明度走快速 ease-out 补间，
##    按钮按下「物理压扁」（pressed 阴影归零 + 内容位移量 = 原阴影偏移量）。
## 【注意】2026-10-19 新野兽派换肤：用户拍板「黑舞台 + 白纸面板 + 全直角 + 只改 UI 层」——
##    INK 舞台保持纯黑；NAVY/NAVY2 翻成宣纸白 #f7f3e8（名字沿用历史）；
##    PAPER 二次翻转为纸面墨字 #171410（暗底亮字一律显式走 CHALK）；
##    GOLD 三件套改品红 #ff006e 家族；SLANT_* 四档归零（常量保留，调用点不动）；
##    FX_HDR_*/ELEMENT_COLORS/RARITY_* 战斗特效色一律不动。
## 【主题色】2026-10-19 新增「用户自选主题色」：GOLD 三件套由 const 改 static var，
##    取值来自 THEME_PRESETS（5 套：品红/明黄/暖橙/天青/荧绿），由 SettingsManager 持久化。
##    切换走 apply_theme_color()：先改三个 static var，再遍历「样式注册表」把已产出的
##    StyleBoxFlat / Label 字色原地改色（Resource 是共享实例，一处改、整屏重绘），
##    最后清空按色缓存的字典（旧 key 已失真）。工厂函数产出样式时若颜色命中主题角色
##    会自动登记，调用点无需逐界面接线；逐帧 _draw 的用法天然每帧读新值。
## 【历史】2026-10-10 二次换肤（纯黑主题）：底一律纯黑；PAPER 翻回纸白亮字。
## 【历史】2026-10-14 主蓝换色：GOLD 三件套取 Material Light Blue 家族（现已被品红取代）。

# —— 底色（纯黑舞台 × 宣纸白面板：黑底托纸面，层次交给黑框与硬影）——
const INK := Color("000000")        # 舞台底/边框/硬影/墨字（纯黑）
const NAVY := Color("f7f3e8")       # 面板底（宣纸白）※名字沿用历史
const NAVY2 := Color("f7f3e8")      # 次级面/卡片底（宣纸白，靠黑框分层）
const LINE := Color("3a3a42")       # 描线/分隔（中性深灰线，用于舞台暗件与次级描边）

# —— 文字 ——
const PAPER := Color("171410")      # 面板正文（纸面墨字）※值已翻为深色
const PAPER_DIM := Color("5f5a4e")  # 次要正文（纸底深灰）
const INK_TEXT := Color("000000")   # 亮面/彩色面上的黑字
const CHALK := Color("f2efe4")      # 暗底亮字（舞台/HUD/深色块上的文字一律显式用它）

# —— 角色色（色即功能）——
# 主题三件套（main / edge / dk）：主行动、选中、标题带。2026-10-19 起由 const 改 static var，
# 值来自 THEME_PRESETS，玩家可在设置页切换（名字沿用历史 GOLD，82 个调用点零改动）。
# 注意：这三项不再能进 const 数组/常量表达式；引用它们的地方一律用 static var 或运行时取。
static var GOLD := Color("ff006e")       # 主题主色（默认品红；做底配黑字）
static var GOLD_EDGE := Color("ff69ac")  # 主题亮边（hover/高光）
static var GOLD_DK := Color("b0004e")    # 主题压暗（按压态/深底）

## 战斗/世界空间特效的「固定品红基准」（不随 UI 主题色漂移）。
## 用户口径：主题色只换 UI 层，战斗特效不动。玩家自选主题色后，暴击跳字、技能光效、
## 敌人爆炸环、聚灵阵读环等世界空间视觉仍用这一套固定色，避免「选天青后敌人爆炸变青」。
const GOLD_FX := Color("ff006e")
const GOLD_FX_EDGE := Color("ff69ac")
const GOLD_FX_DK := Color("b0004e")

## 可自选主题色预设表（唯一真话源）。每套手调 edge/dk，不跑 lightened() 公式，
## 保证与默认品红三件套同品质；id 写进 settings.cfg，改名会断存档。
const THEME_PRESETS: Array[Dictionary] = [
	{"id": &"pink", "name": "品红", "main": Color("ff006e"), "edge": Color("ff69ac"), "dk": Color("b0004e")},
	{"id": &"amber", "name": "明黄", "main": Color("ffd500"), "edge": Color("ffe45c"), "dk": Color("b39400")},
	{"id": &"orange", "name": "暖橙", "main": Color("ff6b35"), "edge": Color("ff9a72"), "dk": Color("b3471c")},
	{"id": &"cyan", "name": "天青", "main": Color("27ddf5"), "edge": Color("7aebfa"), "dk": Color("179cad")},
	{"id": &"lime", "name": "荧绿", "main": Color("c5e803"), "edge": Color("dbf45c"), "dk": Color("8ba300")},
]
## 当前主题 id（SettingsManager 启动时按存档位调用 apply_theme_color 覆盖）
static var _theme_id: StringName = &"pink"

## 主题 id 列表 / 预设查询 / 人话名
static func theme_ids() -> Array:
	var out: Array = []
	for p in THEME_PRESETS:
		out.append(p["id"])
	return out

static func theme_preset(id: StringName) -> Dictionary:
	for p in THEME_PRESETS:
		if p["id"] == id:
			return p
	return THEME_PRESETS[0]

static func theme_name(id: StringName) -> String:
	return String(theme_preset(id).get("name", "品红"))

static func current_theme() -> StringName:
	return _theme_id
const JADE := Color("ffd23f")       # 点缀黄 = 金币/星级/选中强调（历史名 JADE 沿用；做底时配黑字）
const JADE_EDGE := Color("ffe9a8")
const JADE_DK := Color("8f6a14")
const GOOD := Color("2fd271")       # 增益绿 = 治疗/增益（黑底可读）
const GOOD_DK := Color("2f8f4c")
const BAD := Color("e2503c")        # 朱砂 = 危险/扣血
const BAD_DK := Color("8f2a1c")
const GREY := Color("8a857a")       # 暗部正文/禁用（纸底可读暖灰）
const DISABLED_FACE := Color("ddd8ca")  # 禁用按钮面（浅灰纸：形状价格全在，只是按不动）
const ELEMENT := Color("ff8a3d")    # 元素橙红 = 「元素伤害」角标专用（与蓝/黄/增益绿/朱砂都不撞）
const SWEEP := Color("f5a83d")      # 琥珀金 = 「横扫」攻击方式专用（近战朱砂/横扫琥珀/其他主蓝三档，与元素橙红拉开明度）
const AURUM := Color("ffc94d")      # 暖金 = 金光护体椭球护罩主色（世界特效专用，与点缀黄 JADE 的货币语义区分）
const AURUM_EDGE := Color("ffe9b0") # 暖金亮边（护罩描边/流光高光）
const SHADOW := Color(0.78, 0.50, 1.0)      ## 幽夜紫 = 「踏影/影层」专用（闪避攒的层数读数、
## 落地影袭环）：与暖金护罩、元素橙红、主蓝行动色都不撞，黑底上够亮才读得出层数
const SHADOW_EDGE := Color(0.94, 0.84, 1.0) ## 影层亮边（攒满时的可释放高亮与环描边）
const SHADOW_DK := Color("3a1f52")          ## 幽夜紫暗底（影层角标的芯片底色，配 SHADOW 亮字）
const POISON := Color(0.35, 0.75, 0.45)     ## 剧毒绿 = 敌方投毒毒潭/持续伤害区域专用（与增益绿 GOOD 的语义
## 相反：GOOD 是给玩家的治疗，POISON 是敌人放的地面持续伤害，黑底上同档亮度但只用于世界空间危险区）

# 稀有度 / 品阶统一色值（普通暖灰 / 稀有灵蓝 / 史诗幽紫 / 传说浩然金 —— 哈迪斯式四档，按黑底可读调亮）
const RARITY_COMMON := Color(0.72, 0.70, 0.65)   ## 普通：纸白暖灰（不发辉）
const RARITY_RARE := Color(0.28, 0.68, 0.98)     ## 稀有：灵蓝（水系/天蓝同调）
const RARITY_EPIC := Color(0.78, 0.45, 0.98)     ## 史诗：幽夜紫
const RARITY_LEGEND := Color(1.0, 0.78, 0.25)    ## 传说：浩然金（冷月霜金调亮古金）

# 五行标签统一色值（2026-10-14 重定：金改金色，火/土随动拉开与状态色的距离，
# 水随主蓝换天蓝随动压深 —— 主蓝 #4fc3f7 与旧水色只差 31，玄水必得是深蓝才分得出）
# 这套色一色多用：图标外框描边、图鉴五行签面（签上是黑字）、羁绊行头签。
# 挑值的硬约束（改前实测）：火 #e6734c 与「元素橙红下边框」#ff8a3d 只差 38 ——
# 火系 13 把里 11 把带橙红下边框，两者在同一格上几乎糊成一条；金原为冷银白 #d9dbeb，
# 与「当前选中」白框 #f2efe4 只差 33，金系 16 把（占比最大）选中时看不出外框变过色。
# 故：金 → 古金（用户口径「金系就该是金色」），火 → 赤红（压暗收红，离橙红条 85），
# 土 → 棕土（金变金后与土黄只差 50，同为暖黄会撞，必须一起往棕压）。
const ELEMENT_COLORS := {
	"metal": Color("c9a227"),
	"wood": Color("59bf73"),
	"water": Color("1e88e5"),
	"fire": Color("ec4018"),
	"earth": Color("a97544"),
}

# —— FX_HDR 特效发光色表（超白起辉通道）——
# 项目已开启 viewport/hdr_2d=true，Main.tscn Environment glow_hdr_threshold=1.0。
# 任何分量 > 1.0 的颜色自动触发 WorldEnvironment glow 泛光起辉，零额外性能开销。
# 通用发光档位：
const FX_HDR_CORE := Color(2.6, 2.5, 2.3)        ## 白芯超白：刀光、弹丸硬核、高亮爆发中心
const FX_HDR_LIGHTNING := Color(2.4, 2.3, 1.9)   ## 雷光超白：雷击、电弧核心（消灭散落魔法数）
const FX_HDR_CRIT := Color(2.6, 1.8, 0.4)        ## 暴击绯金超白：暴击火花、暴击跳字描边
const FX_HDR_HEAL := Color(0.8, 2.2, 1.2)        ## 治愈碧翠超白：回春、生机灵光
const FX_HDR_SHADOW := Color(1.8, 1.2, 2.5)      ## 幽夜紫超白：暗影、影层释放、紫虹镜光束芯
const FX_HDR_GOLD := Color(2.4, 2.0, 0.8)        ## 浩然金超白：境界升级、护罩高光

# 五行 HDR 起辉色（分量 > 1.0，与 ELEMENT_COLORS 对应，供火花/弹丸/光束/法阵取用）：
const FX_HDR_METAL := Color(2.4, 1.9, 0.6)       ## 金系古金超白
const FX_HDR_WOOD := Color(1.0, 2.3, 1.4)        ## 木系青碧超白
const FX_HDR_WATER := Color(0.8, 1.8, 2.5)       ## 水系灵蓝超白
const FX_HDR_FIRE := Color(2.5, 1.1, 0.4)        ## 火系炽阳超白
const FX_HDR_EARTH := Color(2.2, 1.6, 0.9)       ## 土系玄黄超白

const FX_HDR_ELEMENTS := {
	"metal": FX_HDR_METAL,
	"wood": FX_HDR_WOOD,
	"water": FX_HDR_WATER,
	"fire": FX_HDR_FIRE,
	"earth": FX_HDR_EARTH,
}

## 按五行字符串获取 HDR 发光色，未匹配时回退到 FX_HDR_CORE
static func fx_hdr_element(elem: String, fallback: Color = FX_HDR_CORE) -> Color:
	return FX_HDR_ELEMENTS.get(elem, fallback)

# —— T-5.1 稀有度卡框与选中光 HDR 体系（哈迪斯式四档，普通白不发辉、金色档 HDR 起辉）——
const FX_HDR_RARITY_COMMON := Color(0.72, 0.70, 0.65)        ## 普通白：不超白不发辉
const FX_HDR_RARITY_RARE := Color(0.40, 1.10, 1.60)          ## 稀有蓝：轻微泛光
const FX_HDR_RARITY_EPIC := Color(1.35, 0.80, 1.95)          ## 史诗紫：中度起辉
const FX_HDR_RARITY_LEGEND := Color(2.40, 1.90, 0.60)        ## 传说金：强 HDR 超白起辉（= FX_HDR_METAL/GOLD）

# 稀有度选中瞬间高光脉冲色（落子确认反馈，0.22s 内平滑回落至卡框描边色）：
const FX_HDR_SEL_COMMON := Color(1.10, 1.10, 1.15)           ## 普通白高光
const FX_HDR_SEL_RARE := Color(0.60, 1.40, 2.20)             ## 稀有蓝高光
const FX_HDR_SEL_EPIC := Color(1.80, 1.10, 2.50)             ## 史诗紫高光
const FX_HDR_SEL_LEGEND := Color(2.80, 2.30, 1.10)           ## 传说金超白强脉冲

## 按稀有度获取基础 LDR 颜色（标签、色签文本背景使用）
static func rarity_color(rarity: Variant) -> Color:
	if rarity is Color:
		return rarity
	var r_str := String(rarity).to_lower()
	match r_str:
		"legendary", "legend", "4":
			return RARITY_LEGEND
		"epic", "3":
			return RARITY_EPIC
		"rare", "2":
			return RARITY_RARE
		_:
			return RARITY_COMMON

## 按稀有度获取卡框描边 HDR 颜色（常态描边，普通白不发辉、金色档 HDR 起辉）
static func rarity_edge_color(rarity: Variant) -> Color:
	if rarity is Color:
		return _rarity_color_to_edge(rarity)
	var r_str := str(rarity).to_lower()
	match r_str:
		"legendary", "legend", "4":
			return FX_HDR_RARITY_LEGEND
		"epic", "3":
			return FX_HDR_RARITY_EPIC
		"rare", "2":
			return FX_HDR_RARITY_RARE
		_:
			return FX_HDR_RARITY_COMMON

static func _rarity_color_to_edge(col: Color) -> Color:
	if col.is_equal_approx(RARITY_LEGEND) or col.r > 1.5:
		return FX_HDR_RARITY_LEGEND
	if col.is_equal_approx(RARITY_EPIC):
		return FX_HDR_RARITY_EPIC
	if col.is_equal_approx(RARITY_RARE):
		return FX_HDR_RARITY_RARE
	return FX_HDR_RARITY_COMMON

## 按稀有度获取选中瞬间高光脉冲色
static func rarity_select_glow(rarity: Variant) -> Color:
	var r_str := String(rarity).to_lower()
	match r_str:
		"legendary", "legend", "4":
			return FX_HDR_SEL_LEGEND
		"epic", "3":
			return FX_HDR_SEL_EPIC
		"rare", "2":
			return FX_HDR_SEL_RARE
		_:
			return FX_HDR_SEL_COMMON



# —— 斜率四档（2026-10-19 新野兽派换肤：全直角，四档归零）——
# 常量保留、调用点不动：LayoutCheck 的 drawn_rect / ShopCardLayout 的留白算术都从这些常量推导，
# 归零后斜切伸出量自然为 0，算术自洽。
const SLANT_PLATE := 0.0
const SLANT_BLOCK := 0.0
const SLANT_BUTTON := 0.0
const SLANT_BAND := 0.0

# —— 动效时长收口（新代码一律从这几个常量取）——
const ANIM_PRESS := 0.1    # 按钮松开回弹（按下瞬间 0ms 硬切）
const ANIM_SNAP := 0.12    # 卡片选中/取消的位移与缩放
const ANIM_SLAM := 0.18    # 弹窗拍桌进入

# —— 弹窗进出时长收口（新代码一律从这两个常量取，不再各写一份 0.12~0.25 的魔法数）——
const UI_FADE_IN := 0.2    # 弹窗/面板淡入
const UI_FADE_OUT := 0.15  # 弹窗/面板淡出（退场比进场快半拍，等人才是重灾区）

# —— 透明度组合（2026-10-11 收口：UI 层不再手写 Color(r,g,b,a)，统一从这几个入口取）——
const DIM_BASE := Color(0.02, 0.02, 0.03)    # 弹窗/浮层遮罩基色（近黑微蓝）
const COOLDOWN_ARC := Color(0.35, 0.75, 1.0) # 技能冷却环弧光蓝

## 某色 rgb + 自定透明度：半透明层的唯一写法，替代散落的 Color(c.r, c.g, c.b, a)
static func with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)

## 弹窗/浮层的压暗遮罩：基色统一，只允许浓度差异（0.5 轻提示 ～ 0.9 全屏模态）
static func dim_overlay(alpha: float) -> Color:
	return Color(DIM_BASE.r, DIM_BASE.g, DIM_BASE.b, alpha)

## 图标/卡片禁用态灰化（可见但不可用的那一档）
static func disabled_modulate() -> Color:
	return Color(0.4, 0.4, 0.5, 0.7)

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
## （金币阁那枚「丹/药」竖排就是这个）。
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
const COMPACT_CHIP_PAD := 4.0

static func chip_pin_w(text: String, font: Font, font_size: int) -> float:
	return line_max_w(text, font, font_size) + CHIP_PAD

static func compact_chip_pin_w(text: String, font: Font, font_size: int = 10) -> float:
	return line_max_w(text, font, font_size) + COMPACT_CHIP_PAD

## 色签 Label 工厂：斜切面 + 贴着字走的宽。商店货架卡行②、图鉴卡面三签、羁绊签
## 都是「[文字, 面色, 字色]」这一形状，画法收在这一处 —— 否则两处各画一套，
## 同一张流派签在商店是蓝的、在图鉴是灰的，玩家对不上号。
## 面色由调用方给（色即功能，取色口径在业务侧）；text_color 可缺省（Color(-1,-1,-1,-1)），缺省按底色明度自动适配。
static func chip_label(text: String, face: Color, text_color: Color = Color(-1, -1, -1, -1),
		font_size: int = 11) -> Label:
	var lbl := Label.new()
	lbl.text = " %s " % text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.custom_minimum_size = Vector2(chip_pin_w(lbl.text, body_font(), font_size), 0)
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lbl.add_theme_stylebox_override("normal", chip(face))
	var auto_fg: bool = text_color.r < 0.0
	var final_fg: Color = on_face_text(face) if auto_fg else text_color
	label(lbl, font_size, final_fg)
	# 主题色面 + 自动适配字色：换主题后面色明暗翻转（品红暗面配白字、四套新色亮面配黑字），
	# 字色必须跟着重算 —— 登记 &"auto"，apply 时按新面色跑 on_face_text。
	if auto_fg and _theme_role(face) != &"":
		_track_append({
			"ref": weakref(lbl),
			"kind": &"auto",
			"field": &"font_color",
			"role": &"main",
		})
	return lbl

## 亮面配墨黑字、暗面配纸白字：全项目统一色度判据
## 亮度阈值 0.5（>0.5 为亮面走 INK_TEXT，<=0.5 为暗面走 CHALK/PAPER）
static func on_face_text(face: Color) -> Color:
	return INK_TEXT if face.get_luminance() > 0.5 else CHALK

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

## 基础直角面板，带硬错位墨影。
## 坑：shadow_size = 0 时引擎压根不画投影（style_box_flat.cpp draw_shadow = shadow_size > 0），
## 所以硬影要给 shadow_size = 1 —— StyleBoxFlat 的投影是无模糊的等形外扩剪影，
## size 1 + offset 就是「错位一块墨」的硬影，边缘依旧锐利。
## 新野兽派口径：阴影默认不透明纯黑，拒绝半透明柔影。
static func panel(bg: Color, skew_deg: float = SLANT_PLATE, shadow_offset: Vector2 = Vector2(4, 4),
		shadow_col: Color = Color(0, 0, 0, 1.0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.skew = Vector2(deg_to_rad(skew_deg), 0.0)
	sb.corner_radius_top_left = 0
	sb.corner_radius_top_right = 0
	sb.corner_radius_bottom_right = 0
	sb.corner_radius_bottom_left = 0
	if shadow_offset != Vector2.ZERO:
		sb.shadow_color = shadow_col
		sb.shadow_size = 1
		sb.shadow_offset = shadow_offset
	_track_style(sb, bg, &"bg_color")
	return sb

## 实底大色块：主色面 + 纯黑等宽粗框 + 硬偏移墨影（新野兽派标准件）
static func block(bg: Color, skew_deg: float = SLANT_BLOCK, shadow_offset: Vector2 = Vector2(4, 5)) -> StyleBoxFlat:
	var sb := panel(bg, skew_deg, shadow_offset)
	sb.border_width_left = 3
	sb.border_width_top = 3
	sb.border_width_right = 3
	sb.border_width_bottom = 3
	sb.border_color = INK
	return sb

## 色带卡：纸白底 + 顶部 accent 色带 + 同色细框 + 硬墨影。
## 卡片用「纸面+色带」，不要整面实底——实底留给主行动按钮与标题带，
## 卡片整面亮色会糊成一片；纸底托墨字，顶带那一笔 accent 就够标明身份
## （稀有度/选中态/流派色都走这一个 accent 参数，是游戏性色码，不随换肤改黑）。
## StyleBoxFlat 边框是单色的：顶带 5 + 侧 2 + 底 3 共用 accent，正好顺出细框。
static func card(accent: Color, skew_deg: float = SLANT_BLOCK, shadow_offset: Vector2 = Vector2(4, 5)) -> StyleBoxFlat:
	var sb := panel(NAVY2, skew_deg, shadow_offset)
	sb.border_width_left = 2
	sb.border_width_top = 5
	sb.border_width_right = 2
	sb.border_width_bottom = 3
	sb.border_color = accent
	_track_style(sb, accent, &"border_color")
	return sb

## 弹窗大面板：纸白底 + 纯黑 3 框 + 大硬影。
## BaseModalDialog / 属性面板 / 暂停 / 更新弹窗同一条配方，别开小灶。
static func dialog_panel(border: Color = INK, skew_deg: float = SLANT_PLATE,
		shadow_offset: Vector2 = Vector2(8, 9)) -> StyleBoxFlat:
	var sb := panel(NAVY, skew_deg, shadow_offset)
	sb.border_width_left = 3
	sb.border_width_top = 3
	sb.border_width_right = 3
	sb.border_width_bottom = 3
	sb.border_color = border
	return sb

## 左侧色签行：列表行的身份标记是左边一条竖带。行内不投影 —— 列表里每行都拖一条墨影
## 会糊成一锅；行的层次交给 accent 竖带 + 细描边。
static func side_card(accent: Color, skew_deg: float = SLANT_PLATE) -> StyleBoxFlat:
	var sb := panel(NAVY2, skew_deg, Vector2.ZERO)
	sb.border_width_left = 3
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 2
	sb.border_color = accent
	_track_style(sb, accent, &"border_color")
	return sb

## 带外描边的斜切面板（武器槽/卡片描边态）
static func outlined_panel(bg: Color, border: Color, border_w: int = 2, skew_deg: float = SLANT_BLOCK) -> StyleBoxFlat:
	var sb := panel(bg, skew_deg, Vector2.ZERO)
	sb.border_width_left = border_w
	sb.border_width_top = border_w
	sb.border_width_right = border_w
	sb.border_width_bottom = border_w
	sb.border_color = border
	_track_style(sb, border, &"border_color")
	return sb

## 凹陷槽：经验槽轨道/滑杆/未选中（全局单例共享）。
## 纸面板上的「凹」靠压暗一档的纸灰底 + 黑细框表达。
## 【注意】单例共享 —— 调用方严禁就地改属性（bg_color/content_margin 等），要改用 slot_of()：
## 2026-10-20 排查更新弹窗说明框变色，根因就是商店空槽拿单例改色（bg=INK@0.55、
## 边=GOLD@0.45），污染顺着共享缓存波及全项目每一处 slot()。
static func slot() -> StyleBoxFlat:
	if _slot_cache != null:
		return _slot_cache
	_slot_cache = slot_of()
	return _slot_cache

## 独立实例版凹槽：要就地调参（底色/描边/内边距）的调用方一律走这里，
## 每次新建不进缓存，改坏了也只脏自己这一个控件。
static func slot_of(bg: Color = NAVY2.darkened(0.08), border: Color = INK,
		border_w: int = 2) -> StyleBoxFlat:
	var sb := panel(bg, 0.0, Vector2.ZERO)
	sb.border_width_left = border_w
	sb.border_width_top = border_w
	sb.border_width_right = border_w
	sb.border_width_bottom = border_w
	sb.border_color = border
	_track_style(sb, border, &"border_color")
	return sb

## 进度条成对样式（track 底 + fill 面）
static func bar_styles(track: Color, fill: Color) -> Array:
	var bg := panel(track, 0.0, Vector2.ZERO)
	bg.border_width_left = 2
	bg.border_width_top = 2
	bg.border_width_right = 2
	bg.border_width_bottom = 2
	bg.border_color = INK
	var fl := panel(fill, 0.0, Vector2.ZERO)
	return [bg, fl]

## 色签 chip：实底小色块 + 黑框 + 小硬影（按色缓存共享）
## 【注意】单例共享 —— 要就地调内边距等参数的调用方改用 chip_of()（同 slot/slot_of 口径）。
static func chip(face: Color) -> StyleBoxFlat:
	var k := face.to_rgba32()
	if _chip_cache.has(k):
		return _chip_cache[k]
	var sb := block(face, SLANT_BAND, Vector2(2, 3))
	_chip_cache[k] = sb
	return sb

## 独立实例版色签：要改 content_margin 等参数时用，每次新建不进缓存。
static func chip_of(face: Color) -> StyleBoxFlat:
	return block(face, SLANT_BAND, Vector2(2, 3))

## 紧凑型色签 compact_chip：专用于高信息密度卡片（如商店货架卡），收窄边框与投影，防膨胀高度（按色缓存共享）
static func compact_chip(face: Color) -> StyleBoxFlat:
	var k := face.to_rgba32()
	if _compact_chip_cache.has(k):
		return _compact_chip_cache[k]
	var sb := panel(face, SLANT_BAND, Vector2(1, 1))
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = INK
	sb.content_margin_left = 3.0
	sb.content_margin_right = 3.0
	sb.content_margin_top = 1.0
	sb.content_margin_bottom = 1.0
	_compact_chip_cache[k] = sb
	return sb

## 半调网点带：标题带上的印刷味装饰。一次性 _draw（retained），不进每帧路径，不参与交互。
## 只铺大标题带（主菜单/结算这种一屏一条的场合），小卡片上网点只会糊成脏点。
class HalftoneStrip:
	extends Control
	var dot_color := Color(0.0, 0.0, 0.0, 0.10)
	var step := 14.0
	var dot_r := 1.6

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var row := 0
		var y := step * 0.5
		while y < size.y:
			# 奇数行错半格，菱形点阵比方阵更有印刷味
			var x := step * (0.5 if row % 2 == 0 else 1.0)
			while x < size.x:
				draw_circle(Vector2(x, y), dot_r, dot_color)
				x += step
			y += step
			row += 1

## 在 parent 上铺一条半调网点（满幅覆盖， parent 为 PanelContainer 时会被自动铺满）
static func halftone(parent: Control, col := Color(0.0, 0.0, 0.0, 0.10)) -> Control:
	var h := HalftoneStrip.new()
	h.dot_color = col
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(h)
	return h

## 支点钉在控件中心并跟随尺寸变化：布局前调用也安全（布局出尺寸时 resized 会补正）。
## 入场动效与「不淡入、只缩放」的 punch 演出共用这一根。
static func pin_center_pivot(node: Control) -> void:
	if node.size != Vector2.ZERO:
		node.pivot_offset = node.size * 0.5
	if not node.resized.is_connected(_recenter_pivot.bind(node)):
		node.resized.connect(_recenter_pivot.bind(node))

## 入场动效：微缩 + 淡入回弹。容器管布局，position 动不得，所以走 pivot 缩放 + 透明度；
## pivot 在布局前是零，挂一次 resized 持续跟随（之后卡片自身的选中缩放也受益）。
## PROCESS 模式：悟道/金币阁这些屏开着时游戏树是暂停的，暂停下 tween 默认不走。
static func enter_anim(node: Control, delay: float = 0.0) -> void:
	node.modulate = Color(1, 1, 1, 0)
	node.scale = Vector2(0.96, 0.96)
	pin_center_pivot(node)
	var tw := node.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.set_parallel()
	tw.tween_property(node, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

static func _recenter_pivot(node: Control) -> void:
	if is_instance_valid(node):
		node.pivot_offset = node.size * 0.5

## 卡片入场弹跳（货架卡/选卡/结算徽章的统一配方）：微缩 + 淡入 + TRANS_BACK 回弹，可错峰。
## 与 enter_anim 的差别只在幅度（卡片要「拍上桌」的存在感，from_scale 更低、回弹更硬）；
## pivot 挂 resized 持续跟随，布局前调用也安全（此前同一配方在 WaveShop / LevelUpDialog /
## SkillSelect / StartWeaponSelect 各抄了一份，支点逻辑还各自打了补丁，新代码一律走这里）。
static func pop_in(node: Control, delay: float = 0.0, from_scale: float = 0.82) -> void:
	node.modulate = Color(1, 1, 1, 0)
	node.scale = Vector2(from_scale, from_scale)
	pin_center_pivot(node)
	var tw := node.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.set_parallel()
	tw.tween_property(node, "modulate:a", 1.0, 0.15)
	tw.tween_property(node, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## 直角扫屏：一条色带从屏左外扫到屏右外，结算/大胜场面的开场一笔。
## delay 用于多条错峰（胜利双带）。用完自己 queue_free。PROCESS 模式：结算屏开着时游戏树是暂停的。
static func slash_wipe(host: Control, col: Color = GOLD, delay: float = 0.0) -> void:
	var vp := host.get_viewport_rect().size
	if vp.x <= 0.0:
		return
	var band := PanelContainer.new()
	band.add_theme_stylebox_override("panel", panel(col, SLANT_BAND, Vector2.ZERO))
	band.size = Vector2(vp.x * 0.45, vp.y * 1.7)
	band.position = Vector2(-vp.x * 0.7, -vp.y * 0.35)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.set_meta("layout_bleed", true)   # 扫屏带大半时间在屏外，判据放行
	host.add_child(band)
	var tw := band.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(band, "position:x", vp.x * 1.25, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(band, "modulate:a", 0.0, 0.18).set_delay(0.34)
	tw.tween_callback(band.queue_free)

## 矩带扫屏（界面切换）：品红 + 墨黑双带错峰横扫，用于主菜单与选人之间、回合间过渡这类
## 整屏切换的揭幕/闭幕。SLANT_BAND=0 后 slash_wipe 画出的就是直角矩带。
static func band_wipe(host: Control, col: Color = GOLD) -> void:
	slash_wipe(host, col, 0.0)
	slash_wipe(host, INK, 0.07)

## 「元素」怎么说这件事：吃「元素伤害」属性加成的武器，把它的图标框描边换成暖橙红 ELEMENT
## （判定唯一真话：WeaponData.elemental_scaling_coef）。
## 2026-10-12 用户真机：陈列行格子本来就只有 44 见方，右上角那枚「元素」色块把图标遮掉一角，
## 越小的格子越该把地方让给图 ⇒ 角标整套撤掉，改用边框颜色。
## 为什么是边框：货架大卡的图标框早就是这一副语言（ShopOfferCardFactory._create_card_head），
## 同一屏里小格跟大卡说同一句话，玩家不用学第二遍。
## 边框被更高优先级的状态占用时（选中/可合成/推荐）谁赢，由各调用点自己排；
## 元素是「这件的固有属性」，状态是「这一刻能对它做什么」，后者盖前者。
static func is_elemental(weapon_id: String) -> bool:
	return not weapon_id.is_empty() and WeaponData.elemental_scaling_coef(weapon_id) > 0.0

## 图标框描边色：元素件给暖橙红，其余沿用调用方原本那一款（不改变非元素件的长相）
static func element_border(weapon_id: String, fallback: Color) -> Color:
	return ELEMENT if is_elemental(weapon_id) else fallback

## 武器对应的五行代表色（金古金/木绿/水蓝/火赤红/土棕土），无对应或空则回退 fallback
static func weapon_element_color(weapon_id: String, fallback: Color = Color("3a3a42")) -> Color:
	if weapon_id.is_empty():
		return fallback
	var elem := WeaponData.element_of(weapon_id)
	if elem.is_empty():
		return fallback
	return ELEMENT_COLORS.get(elem, fallback)

## 元素特性下边框装饰条：在图标框底部叠一层暖橙红 ELEMENT 水平亮条（吃「元素伤害」属性加成），
## 宽度自适应铺满底部，高度默认 3px，不拦截输入事件。
static func apply_elemental_bottom_bar(parent: Control, is_elem: bool, height: float = 3.0) -> ColorRect:
	if not is_elem or parent == null:
		return null
	var bar := ColorRect.new()
	bar.name = "ElementBottomBar"
	bar.color = ELEMENT
	bar.custom_minimum_size = Vector2(0.0, height)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_END
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bar)
	return bar

## 武器星级 Label（统一字号、描边、右下角对齐）
static func star_label(parent: Control, star: int, font_size: int = 11) -> Label:
	var lbl := Label.new()
	lbl.text = "★%d" % star
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_override("font", body_font())
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", JADE)
	lbl.add_theme_color_override("font_outline_color", INK)
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(lbl)
	return lbl

static func label(l: Label, size: int, color: Color = PAPER, outline: int = 0,
		outline_col: Color = INK, display: bool = false) -> Label:
	l.add_theme_font_override("font", display_font() if display else body_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	_track_label(l, color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", outline_col)
	return l

## UI 图标工厂：统一设置 EXPAND_IGNORE_SIZE + STRETCH_KEEP_ASPECT_CENTERED，
## 并显式启用 TEXTURE_FILTER_LINEAR（双线性插值滤波），消除全局 Nearest 缩放时的锯齿像素感。
## 武器图标走「UI 高清变体优先」：战斗画布 weapon_*.png 固定 48x48（tip 剑尖坐标系绑定，
## 不能放大），UI 槽位 56~64px 放大显示会糊；assets/art/ui/ 下有同名 128px 变体则优先用，
## 没有则原样回退（item_*/其他图标无变体，路径原样通过，行为不变）。
static func icon_texture_rect(texture_path: String = "", min_size: Vector2 = Vector2.ZERO) -> TextureRect:
	var tex_rect := TextureRect.new()
	var path := _hd_icon_path(texture_path)
	if not path.is_empty() and ResourceLoader.exists(path):
		tex_rect.texture = load(path)
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if min_size != Vector2.ZERO:
		tex_rect.custom_minimum_size = min_size
	return tex_rect

static var _empty_focus_style: StyleBoxEmpty = null
static var _slot_cache: StyleBoxFlat = null
static var _chip_cache: Dictionary = {}
static var _compact_chip_cache: Dictionary = {}
static var _btn_block_cache: Dictionary = {}

# —— 主题色样式注册表 ——
# 工厂产出的样式若引用了主题三件套（GOLD/GOLD_EDGE/GOLD_DK），登记一条
# {ref: WeakRef, kind: &"box"/&"label"/&"modulate", field: StringName, role: &"main"/&"edge"/&"dk"}。
# 切换主题时遍历登记表，把存活的实例原地改色：StyleBoxFlat 是 Resource、控件与工厂共享同一实例，
# 改属性即整屏重绘，无需逐界面重跑构建。WeakRef 保证出树控件被回收后自净（apply 时顺手剪枝），
# 否则 static 表强引用 RefCounted 会在退出时报 resources still in use。
static var _theme_registry: Array[Dictionary] = []
## 去重表：obj_instance_id:field → true。刷新路径会反复对同一缓存 StyleBox 调工厂，
## 不去重会无限往注册表里追加同一条（内存只增不减）。
static var _theme_seen: Dictionary = {}

## 追加一条登记；同一对象同一属性只记一次
static func _track_append(entry: Dictionary) -> void:
	var obj: Variant = (entry["ref"] as WeakRef).get_ref()
	if obj == null:
		return
	var key := "%d:%s" % [(obj as Object).get_instance_id(), String(entry["field"])]
	if _theme_seen.has(key):
		return
	_theme_seen[key] = true
	_theme_registry.append(entry)

## 颜色 → 主题角色；不是主题三件套之一返回空串
static func _theme_role(c: Color) -> StringName:
	if c == GOLD:
		return &"main"
	if c == GOLD_EDGE:
		return &"edge"
	if c == GOLD_DK:
		return &"dk"
	return &""

static func _role_color(role: StringName) -> Color:
	match role:
		&"edge":
			return GOLD_EDGE
		&"dk":
			return GOLD_DK
		_:
			return GOLD

static func _track_style(sb: StyleBoxFlat, touched: Color, field: StringName) -> void:
	var role := _theme_role(touched)
	if role == &"":
		return
	_track_append({
		"ref": weakref(sb),
		"kind": &"box",
		"field": field,
		"role": role,
	})

## 派生色登记：面/边由主题色经过 darkened/lightened/alpha 变换而来（如按钮 pressed 面
## = hover_bg.darkened(0.15)）。回放时按同样变换重算，换主题后按压态也跟着走。
static func _track_derived(sb: StyleBoxFlat, field: StringName, base: Color,
		op: StringName, amount: float) -> void:
	var role := _theme_role(base)
	if role == &"":
		return
	_track_append({
		"ref": weakref(sb),
		"kind": &"box_derived",
		"field": field,
		"role": role,
		"op": op,
		"amount": amount,
	})

static func _apply_derived(base: Color, op: StringName, amount: float) -> Color:
	match op:
		&"darken":
			return base.darkened(amount)
		&"lighten":
			return base.lightened(amount)
		&"alpha":
			var c := base
			c.a = amount
			return c
		_:
			return base

## 登记外部已有的 StyleBoxFlat（如从 .tscn 烘焙样式 duplicate 来的），主题切换时回放改色。
## 供「颜色在场景文件里写死、不经工厂」的节点补挂——工厂出口会自动登记，这里只是补漏。
static func register_theme_box(sb: StyleBoxFlat, field: StringName = &"bg_color",
		role: StringName = &"main") -> void:
	if sb == null:
		return
	_track_append({
		"ref": weakref(sb),
		"kind": &"box",
		"field": field,
		"role": role,
	})

## 文字色登记：label() 里字体色正好是主题色时登记，主题切换时重写 font_color
static func _track_label(l: Label, color: Color) -> void:
	var role := _theme_role(color)
	if role == &"":
		return
	_track_append({
		"ref": weakref(l),
		"kind": &"label",
		"field": &"font_color",
		"role": role,
	})

## 外部已有 Label 的字体色补登记（节点已自行 override 成主题色的场景用）
static func register_theme_label(l: Label, role: StringName = &"main") -> void:
	if l == null:
		return
	_track_append({
		"ref": weakref(l),
		"kind": &"label",
		"field": &"font_color",
		"role": role,
	})

## 外部派生样式的补登记（颜色是主题色经 darkened/lightened/alpha 变换来的，工厂认不出原色）。
## 例：未选中卡描边 = GOLD.darkened(0.35)、上阵格底色 = GOLD 淡化 14%。
## op 取 &"darken"/&"lighten"/&"alpha"；role 指派生所依据的主题档位。
static func register_theme_derived_box(sb: StyleBoxFlat, field: StringName,
		role: StringName, op: StringName, amount: float) -> void:
	if sb == null:
		return
	_track_append({
		"ref": weakref(sb),
		"kind": &"box_derived",
		"field": field,
		"role": role,
		"op": op,
		"amount": amount,
	})

## 属性（modulate 等）登记：滚动条按 GOLD 调 modulate，主题切换时重算
static func _track_modulate(node: CanvasItem) -> void:
	_track_append({
		"ref": weakref(node),
		"kind": &"modulate",
		"field": &"modulate",
		"role": &"main",
	})

## 切换主题色：改 static var → 回放注册表原地改色 → 清按色缓存（旧 key 已失真）。
## SettingsManager 在启动加载与玩家点选色块时调用；幂等。
static func apply_theme_color(id: StringName) -> void:
	var preset := theme_preset(id)
	_theme_id = StringName(preset.get("id", &"pink"))
	GOLD = preset.get("main", Color("ff006e"))
	GOLD_EDGE = preset.get("edge", Color("ff69ac"))
	GOLD_DK = preset.get("dk", Color("b0004e"))

	var alive: Array[Dictionary] = []
	for entry in _theme_registry:
		var obj: Variant = (entry["ref"] as WeakRef).get_ref()
		if obj == null:
			continue   # 控件已释放：剪枝
		alive.append(entry)
		var col := _role_color(entry["role"])
		match entry["kind"]:
			&"box":
				(obj as StyleBoxFlat).set(entry["field"], col)
			&"label":
				(obj as Label).add_theme_color_override(entry["field"], col)
			&"auto":
				# 主题色面上的自适应字色：按新面色重新判明暗
				(obj as Label).add_theme_color_override(entry["field"], on_face_text(col))
			&"box_derived":
				(obj as StyleBoxFlat).set(entry["field"], _apply_derived(col, entry["op"], entry["amount"]))
			&"modulate":
				var c := col
				c.a = 0.85
				(obj as CanvasItem).modulate = c
	_theme_registry = alive
	# 去重表按存活条目重建（死引用同步清掉，避免 instance_id 复用导致新对象被误判为已登记）
	_theme_seen.clear()
	for entry in _theme_registry:
		var o: Variant = (entry["ref"] as WeakRef).get_ref()
		if o != null:
			_theme_seen["%d:%s" % [(o as Object).get_instance_id(), String(entry["field"])]] = true

	# 按色缓存的 key 里烤的是旧色值，必须清空（否则新建按钮会命中旧色缓存）
	_chip_cache.clear()
	_compact_chip_cache.clear()
	_btn_block_cache.clear()
	_slot_cache = null

static func empty_focus() -> StyleBoxEmpty:
	if _empty_focus_style == null:
		_empty_focus_style = StyleBoxEmpty.new()
	return _empty_focus_style

static func _btn_block(bg: Color, skew_deg: float, shadow_offset: Vector2) -> StyleBoxFlat:
	# 缓存命中仍要补登记：首次按钮用的缓存可能是「非主题色」建出来的，
	# 而主题切换会清空缓存；不清时返回的旧实例也需要登记才能跟随换色。
	var k := [bg.to_rgba32(), skew_deg, shadow_offset]
	if _btn_block_cache.has(k):
		var cached: StyleBoxFlat = _btn_block_cache[k]
		_track_style(cached, bg, &"bg_color")
		return cached
	var sb := block(bg, skew_deg, shadow_offset)
	_btn_block_cache[k] = sb
	return sb

## UI 图标路径 → 高清变体路径：assets/art/ 下的武器图标在 assets/art/ui/ 找同名 128px 变体。
## 变体只增不清：原路径不存在或无变体时原样返回，调用方 ResourceLoader.exists 兜底。
## 缓存探测结果：商店一屏几十张图标逐张 is_file() 太浪费。
static var _hd_icon_cache: Dictionary = {}
static func _hd_icon_path(path: String) -> String:
	if path.is_empty() or not path.begins_with("res://assets/art/"):
		return path
	if _hd_icon_cache.has(path):
		return _hd_icon_cache[path]
	var hd := path.replace("res://assets/art/", "res://assets/art/ui/")
	if hd != path and FileAccess.file_exists(hd):
		_hd_icon_cache[path] = hd
	else:
		_hd_icon_cache[path] = path
	return _hd_icon_cache[path]

## 按钮四态（normal / hover / pressed / disabled）+ 物理压扁点击动效。
## 新野兽派点击口径（Physical Crushing）：按下瞬间 0ms 硬切 —— pressed 阴影归零、
## 内容右下位移（位移量 = 原阴影偏移量 (3,4)）、面色加深；松开时 pivot 缩放从 0.97
## 弹回 1.0（ANIM_PRESS 快速 ease-out）。hover 阴影 (3,4)→(5,6) 硬切放大（Brutal Snap）。
## 禁用态在这里统一给浅灰纸面，每个界面不再自己补 disabled stylebox
## （漏一处就是一颗看不见的死键）。
static func button(btn: Button, bg: Color, hover_bg: Color, font_size: int,
		font_color: Color = PAPER, skew_deg: float = SLANT_BUTTON,
		hover_color: Color = Color(0, 0, 0, 0)) -> void:
	var normal := _btn_block(bg, skew_deg, Vector2(3, 4))
	var hover := _btn_block(hover_bg, skew_deg, Vector2(5, 6))
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := _btn_block(hover_bg.darkened(0.15), skew_deg, Vector2.ZERO)
	# pressed 面是 hover_bg 压暗派生：hover_bg 若为主题色，pressed 也必须跟着换肤
	_track_derived(pressed, &"bg_color", hover_bg, &"darken", 0.15)
	# 物理压扁：pressed 阴影归零，内容右下挪 —— 位移量 = 原阴影偏移量
	pressed.content_margin_left = 3.0
	pressed.content_margin_top = 4.0
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", _btn_block(DISABLED_FACE, skew_deg, Vector2(3, 4)))
	btn.add_theme_color_override("font_disabled_color", GREY)
	btn.add_theme_stylebox_override("focus", empty_focus())
	btn.add_theme_font_override("font", body_font())
	btn.add_theme_font_size_override("font_size", font_size)
	var act_color: Color = hover_color if hover_color.a > 0 else font_color
	btn.add_theme_color_override("font_color", font_color)
	btn.add_theme_color_override("font_hover_color", act_color)
	btn.add_theme_color_override("font_pressed_color", act_color)
	btn.add_theme_color_override("font_hover_pressed_color", act_color)
	btn.add_theme_color_override("font_focus_color", font_color)
	# 样式入口即反馈入口：全项目按钮的点击音在这里统一挂，避免每个界面各写一遍。
	# meta 标记防止同一按钮被重复刷新样式时挂出多重连接（一次点击响两声）。
	if not btn.has_meta("sfx_wired"):
		btn.set_meta("sfx_wired", true)
		btn.pressed.connect(func() -> void: AudioManager.play_sfx("ui_click"))
# 物理压扁的位移补间：按下 0ms 硬缩，松开快速弹回。meta 防重复接线。
	if not btn.has_meta("crush_wired"):
		btn.set_meta("crush_wired", true)
		btn.button_down.connect(func() -> void: _crush(btn, true))
		btn.button_up.connect(func() -> void: _crush(btn, false))

# 回弹 tween 存在按钮自己的 meta 上（随按钮释放）：static 字典持有 Tween 会在退出时
# 报「resources still in use」——Tween 是 RefCounted，进程收尾时静态表不撒手就算泄漏。
const _CRUSH_TW_META := "_gs_crush_tw"

static func _crush(btn: Button, down: bool) -> void:
	if not is_instance_valid(btn):
		return
	pin_center_pivot(btn)
	if btn.has_meta(_CRUSH_TW_META):
		var old: Variant = btn.get_meta(_CRUSH_TW_META)
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
		btn.remove_meta(_CRUSH_TW_META)
	if down:
		btn.scale = Vector2(0.97, 0.97)   # 按下瞬间硬切，不做补间
		return
	var tw := btn.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	btn.set_meta(_CRUSH_TW_META, tw)
	tw.tween_property(btn, "scale", Vector2.ONE, ANIM_PRESS)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## 卡片选中动效（Select Snap）：描边/色带的瞬间硬切由调用方换 stylebox 完成（Brutal Snap），
## 这里只管位移与缩放 —— 选中放大到 1.03、取消收回 1.0，ANIM_SNAP 快速 ease-out。
static func select_snap(card: Control, on: bool) -> void:
	pin_center_pivot(card)
	var tw := card.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(card, "scale", Vector2.ONE * (1.03 if on else 1.0), ANIM_SNAP)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## 弹窗拍桌进入（Slam In）：微缩 0.92 + 淡入，ANIM_SLAM 快速 CUBIC ease-out，不用弹簧。
## 容器管布局 position 动不得，落位感由缩放 + 透明度的快切节奏表达。
static func slam_in(panel_node: Control) -> void:
	panel_node.modulate = Color(1, 1, 1, 0)
	panel_node.scale = Vector2(0.92, 0.92)
	pin_center_pivot(panel_node)
	var tw := panel_node.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_parallel()
	tw.tween_property(panel_node, "modulate:a", 1.0, ANIM_SLAM)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel_node, "scale", Vector2.ONE, ANIM_SLAM)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## 把 node 设成一块「整块点得动」的热区：本体收事件，子孙一律不许截。
## 为什么需要它：PanelContainer / Control / ColorRect 的 mouse_filter 默认是 STOP，
## 卡片里再套一层图框（48×48 的描边底）就会在热区中间挖出一个「点了没反应」的洞 ——
## 触屏没有 hover，洞是静默的：代码看着整块可点，真机上只有文字那一小块有反应
## （用户 2026-10-09 真机：道具图鉴点名字弹卡、点图片没反应）。
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
## 盖在**事件对象**上的认领标记：同一次松开沿冒泡链向上，最里层兑现过的热区先盖戳，
## 外层热区见到就不再重复兑现（点卡里的受益装备图标不许顺手把这张卡选了）。
## 为什么不用 accept_event()：它会把这一枪从链上摘掉，外层 ScrollContainer 就收不到松开、
## drag_touching 复位不了（手指抬走了列表还跟着走）。事件对象本身是冒泡链上唯一的公共载体，
## 给它盖 meta 既不影响别人收事件，又只在这一次手势内有效。
const _TAP_CLAIM_META := "_gs_tap_claimed"

static func _tap_reset(node: Control) -> void:
	node.remove_meta(_TAP_DOWN_META)
	node.remove_meta(_TAP_SCROLL_META)
	node.remove_meta(_TAP_REACH_META)

## 挂一次「真点按」：按下与抬起都留在原地才算点，中途划出去（拖列表）就不触发。
## 为什么必须显式做：滚动区里的卡片为了让手指拖得起列表，mouse_filter 已从 STOP 降成 PASS
## （见 swipeable），于是「按下」那一拍同时被外层 ScrollContainer 拿去 latch 拖动滚动。
## 而点按若只认「左键松开」这一枪（旧 PlayerStatsDialog._is_tap / ManualDialog 卡片），
## 划完列表一松手照样算一次点击 —— 真机上就是「我本来想滑动，不小心就点按了」
## （用户 2026-10-09：属性面板「悟道历程」列表）。
## 尺子取「本次手势划出去过的最大距离」，手指与列表两个来源取大：
## ① 只比按下点与抬起点会漏判 —— 列表跟着手指走，抬起点与按下点可以挨得很近；
## ② 只比按下与抬起那一刻的列表读数会**误杀** —— 手指按在原地的微动（真机必然有）同样
##    会把列表拖走几单位（2026-10-09 金币阁陈列行实测：微动 4 单位 → 列表动了 4 → 旧尺子
##    阈值 0.5 判成「被拖走过」⇒ 满仓时每一格都点不动）。
## 所以中途的每一次 motion 都要记账，容差用同一个 TAP_SLACK：手指微动仍算点，有意划必超。
## 都没按下过的松开不算点按 —— 按下在别处，这一枪不该由这块热区兑现。
## 热区套热区（卡体里嵌图标）时只兑现最里那一层：见 _TAP_CLAIM_META。
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
			# 这一枪已被更里一层的热区兑现（点卡里的图标/角标）→ 外层卡体不再重复兑现，
			# 但要清掉自己那半截记账，否则下一次「只收到松开」会拿旧按下点算距离。
			if mb.has_meta(_TAP_CLAIM_META):
				_tap_reset(node)
				return
			if not node.has_meta(_TAP_DOWN_META):
				return                      # 没在本节点上按下过 → 这一枪不算点
			var down: Vector2 = node.get_meta(_TAP_DOWN_META)
			var scroll0: Vector2 = node.get_meta(_TAP_SCROLL_META, NO_SCROLL_ABOVE)
			var reach: float = node.get_meta(_TAP_REACH_META, 0.0)
			_tap_reset(node)
			reach = maxf(reach, down.distance_to(mb.global_position))
			if scroll0 != NO_SCROLL_ABOVE:
				reach = maxf(reach, scroll0.distance_to(_scroll_offset_above(node)))
			if reach > TAP_SLACK:
				return
			mb.set_meta(_TAP_CLAIM_META, true)
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
## 为什么两个轴都要：只盯竖滑的话，横滑那一排（金币阁陈列行）划完一松手照样算点按 ——
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
## 谁在用：金币阁的货架排与陈列行（WaveShop._ready）。其余滚动面板沿用默认，
## 等谁再动那一屏时一并收口。
static func scrollable(sc: ScrollContainer) -> void:
	if sc == null:
		return
	_scroll_bar(sc.get_h_scroll_bar())
	_scroll_bar(sc.get_v_scroll_bar())

## 滚动条只能靠 modulate 调颜色：theme 的 scroll_background / scroll_grabber 那几张 stylebox，
## 无论是 `bar.add_theme_stylebox_override()` 还是给 bar 挂一份 Theme，画出来都还是默认那根
## 浅灰圆头（实测：节点上 get_theme_stylebox 读回来是我们要的色，屏幕上不动；同一节点
## modulate=红 立刻变红 ⇒ 4.7 的 ScrollBar 绘制不吃这两条路）。统一 modulate 成品红细带。
static func _scroll_bar(bar: ScrollBar) -> void:
	if bar == null:
		return
	bar.modulate = Color(GOLD.r, GOLD.g, GOLD.b, 0.85)
	# ScrollBar 不吃 stylebox（4.7 实测），只能靠 modulate 上色 —— 主题切换时按新 GOLD 重算
	_track_modulate(bar)
