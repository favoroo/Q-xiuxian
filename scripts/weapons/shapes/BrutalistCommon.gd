extends RefCounted

## 新野兽派法器画法 · 共用调色板与构件（刃/重/巧三族模块共用，配色只改这一处）
##
## 画法纪律（用户认可的样稿口径，不得偏离）：
##   · 平涂色块 + 粗墨描边 + 右下硬偏移投影；零辉光 / 零渐变 / 零装饰纹。
##   · 每把 = 五行主色一大块（pal["body"]）+ 撞色块一处（pal["accent"]）+ 墨黑。
##   · 升星分档：★2 墨描加粗+投影微扩（锻造加固）；★3 再叠 accent 金芯描线（鎏金）；
##     ★4 换太虚霓虹双色边（电光青 HDR + 太虚紫，紫电琉璃）。
##     ★2~★4 同时保留 star_studs 撞色方钉作最直白星级读数；小构件自动豁免（见下方常量）。
##   · 投影画在本地坐标系（随武器旋转），是有意为之的硬斜切感，不要改成世界对齐。
##
## 坐标契约（与 ProceduralWeaponRenderer 一致）：画布像素空间沿 +X 画，器尖/器口
## 落在 (r.tip_len, 0)；upright 由宿主统一旋转，族模块内永远只沿 +X 画。

const INK := Color(0.07, 0.08, 0.11)
const PAPER := Color(0.93, 0.91, 0.85)
const CINNABAR := Color(0.72, 0.14, 0.10)
const SHADOW := Color(0.0, 0.0, 0.0, 0.40)

## 五行平涂配色：主色块 body + 撞色 accent（高饱和、平涂，不许渐变）
const PAL := {
	"metal": {"body": Color(0.90, 0.91, 0.94), "accent": Color(1.00, 0.78, 0.18)},
	"wood": {"body": Color(0.42, 0.74, 0.36), "accent": Color(0.80, 0.93, 0.30)},
	"water": {"body": Color(0.26, 0.58, 0.94), "accent": Color(0.50, 0.93, 1.00)},
	"fire": {"body": Color(0.90, 0.28, 0.14), "accent": Color(1.00, 0.72, 0.12)},
	"earth": {"body": Color(0.70, 0.55, 0.34), "accent": Color(0.98, 0.60, 0.16)},
}

static func pal(elem: String) -> Dictionary:
	return PAL.get(elem, PAL["metal"])

## 平涂块：硬投影 + 粗墨描边（贴形外线）+ 纯色填充。ow = 露出外侧的描边厚度。
## ★3 在墨描之下先走一道加宽 accent 描线：内侧被墨描与填充盖住，外缘露出金边
## ——深底背景上剪影最外圈变金，是升星最直读的信号。
## ★4 换「太虚霓虹（紫电琉璃）」双色边：墨描之下先铺一层加宽 NEON_CYAN_HDR 电光青
## （分量 >1 ⇒ 走 HDR glow 泛光），再叠一层 NEON_VIOLET 紫电内衬，最外圈仍是电光青，
## 往里第二圈紫 —— 与 ★3 的单层暖金一眼分档，且不与五色主色块抢读数。
static func flat(r: Node2D, pts: PackedVector2Array, fill: Color, ow: float = 2.2) -> void:
	var st: int = star_of(r)
	var d: float = star_shadow_off(st)
	var sh := PackedVector2Array()
	for p in pts:
		sh.append(p + Vector2(d, d))
	r.draw_colored_polygon(sh, SHADOW)
	var closed := pts.duplicate()
	closed.append(pts[0])
	var ink_w: float = star_ink_w(ow, st)
	if st >= 4 and ow + 2.4 >= STAR_INK_MIN:
		r.draw_polyline(closed, NEON_CYAN_HDR, ink_w + STAR4_NEON_PEEP * 2.0, true)
		r.draw_polyline(closed, NEON_VIOLET, ink_w + STAR4_NEON_PEEP, true)
	elif st >= 3 and ow + 2.4 >= STAR_INK_MIN:
		r.draw_polyline(closed, pal(String(r.get("element")))["accent"], ink_w + STAR_EDGE_PEEP * 2.0, true)
	r.draw_polyline(closed, INK, ink_w, true)
	r.draw_colored_polygon(pts, fill)

## 粗杆（柄/骨/轴）：投影 + 墨描 + 纯色芯。升星加粗墨描；★3 走金边外缘、★4 走霓虹双色边
##（描线都在墨描之下、只露外缘，不顶掉杆芯色），小杆被 STAR_INK_MIN 豁免。
static func bar(r: Node2D, a: Vector2, b: Vector2, w: float, col: Color) -> void:
	var st: int = star_of(r)
	var d: float = star_shadow_off(st)
	var ink_w: float = star_ink_w(w, st)
	r.draw_line(a + Vector2(d, d), b + Vector2(d, d), SHADOW, ink_w, true)
	if st >= 4 and w + 2.4 >= STAR_INK_MIN:
		r.draw_line(a, b, NEON_CYAN_HDR, ink_w + STAR4_NEON_PEEP * 2.0, true)
		r.draw_line(a, b, NEON_VIOLET, ink_w + STAR4_NEON_PEEP, true)
	elif st >= 3 and w + 2.4 >= STAR_INK_MIN:
		r.draw_line(a, b, pal(String(r.get("element")))["accent"], ink_w + STAR_EDGE_PEEP * 2.0, true)
	r.draw_line(a, b, INK, ink_w, true)
	r.draw_line(a, b, col, w, true)

## 方钉/方块构件（剑首、印钮、销钉）：走 flat，小件被 STAR_INK_MIN 自动豁免分档
static func square(r: Node2D, c: Vector2, half: float, col: Color, ow: float = 1.4) -> void:
	flat(r, PackedVector2Array([
		c + Vector2(-half, -half), c + Vector2(half, -half),
		c + Vector2(half, half), c + Vector2(-half, half),
	]), col, ow)

## 圆盘（鼓面/镜面/珠体）：投影 + 墨描 + 平涂。ow 是向内内缩量（墨环厚）。
## 升星：大盘墨环加厚一档；★3 在墨描外缘走一圈金环（与平涂块的金边同语言），
## ★4 走双层霓虹环（电光青外 + 太虚紫内），墨环内半区再叠一道紫电弧，小盘（radius < 5）豁免。
static func disc(r: Node2D, c: Vector2, radius: float, fill: Color, ow: float = 2.4) -> void:
	var st: int = star_of(r)
	var d: float = star_shadow_off(st)
	r.draw_circle(c + Vector2(d, d), radius, SHADOW)
	var inset: float = ow
	if radius >= 4.5:
		inset = ow + 0.5 * float(st - 1)
	if st >= 4 and radius >= 5.0:
		r.draw_circle(c, radius + STAR4_NEON_PEEP, NEON_CYAN_HDR)
		r.draw_circle(c, radius + STAR4_NEON_PEEP * 0.5, NEON_VIOLET)
	elif st >= 3 and radius >= 5.0:
		r.draw_circle(c, radius + STAR_EDGE_PEEP, pal(String(r.get("element")))["accent"])
	r.draw_circle(c, radius, INK)
	r.draw_circle(c, radius - inset, fill)
	if st >= 4 and radius >= 5.0:
		r.draw_arc(c, radius - inset * 0.5, 0.0, TAU, 28, NEON_CYAN_HDR, minf(inset * 0.55, 1.8), true)
	elif st >= 3 and radius >= 5.0:
		r.draw_arc(c, radius - inset * 0.5, 0.0, TAU, 28,
			pal(String(r.get("element")))["accent"], minf(inset * 0.55, 1.6), true)

## 圆环带（鼓环/镜框）：墨底 + 撞色环。升星只加厚墨底，撞色环带宽保持
static func ring(r: Node2D, c: Vector2, radius: float, w: float, col: Color) -> void:
	var st: int = star_of(r)
	var ink_w: float = w + 2.0
	if radius >= 4.5:
		ink_w += minf(0.6, w * 0.3) * float(st - 1)
	r.draw_arc(c, radius, 0.0, TAU, 28, INK, ink_w, true)
	r.draw_arc(c, radius, 0.0, TAU, 28, col, w, true)

## 升星方钉（最直白的星级读数）：★2 在 a 落一颗撞色方钉，★3 再在 b 落一颗，
## ★4 在 a~b 中点补第三颗电光青神印（三钉 = 四星，霓虹色与描边同源）
static func star_studs(r: Node2D, star: int, a: Vector2, b: Vector2, col: Color) -> void:
	if star >= 2:
		square(r, a, 1.7, col, 1.2)
	if star >= 3:
		square(r, b, 1.7, col, 1.2)
	if star >= 4:
		square(r, a.lerp(b, 0.5), 1.9, NEON_CYAN_HDR, 1.2)

# ==================== 升星外观档（★2 锻造加固 / ★3 鎏金缘 / ★4 太虚霓虹） ====================
## 画法纪律内的分档，变化集中在用户最容易感知的「描边」上：
##   ★2 墨描加粗（每星 +1.2）+ 投影外扩（2.0→2.6→3.2，「离纸感」逐档增强）。
##   ★3 再沿构件轮廓先走一道加宽 accent 描线（被后续墨描盖住内侧），墨描外缘
##      露出 ~1.4 单位金边——深底背景上剪影最外圈直接变金，一眼可读；同时 disc
##      在墨环内半区叠金弧、保留双星钉。零辉光零渐变。
##   ★4 换「太虚霓虹（紫电琉璃）」：墨描之下铺两层描线——外层 NEON_CYAN_HDR 电光青
##      （分量 >1，走 HDR glow 自动泛光）+ 内层 NEON_VIOLET 太虚紫，投影再外扩一档；
##      disc 叠紫电内弧，星钉补第三颗电光青神印。色相与 ★3 的暖金完全分开，
##      不与五行主色块（金/木/水/火/土）抢读数 —— 玩家一眼分得出「这把是极境」。
##
## 小构件豁免：基准墨宽（ow+2.4）< STAR_INK_MIN 的构件（星钉/剑首/箍环等小方块小件）
## 不吃分档——星钉本身就是 3.4 单位的小方块，加粗描边会把它整个吞成墨团。

const STAR_INK_MIN := 4.0   ## 基准墨宽达到此值的「大面积构件」才参与升星分档
const STAR_EDGE_PEEP := 1.4 ## ★3 金边露出墨描外的宽度（描线加宽 = 2×此值）
## ★4 太虚霓虹双色边（2026-10-24）：电光青是 HDR 超白（分量 >1 ⇒ 引擎 glow 自动泛光），
## 太虚紫负责「往里第二圈」的色相分层。两个值都压在 1 单位量级，否则细构件会糊成一团。
const NEON_CYAN_HDR := Color(0.45, 1.95, 2.55)   ## 电光青（HDR）：极境描边外圈
const NEON_VIOLET := Color(0.78, 0.38, 1.00)     ## 太虚紫：极境描边内圈 / 内弧
const STAR4_NEON_PEEP := 2.0                     ## ★4 霓虹边露出墨描外的宽度（比 ★3 金边更厚）

## 读宿主渲染器的星数（法器/机关/御灵三系渲染器都有 star 字段，鸭子访问）
static func star_of(r: Node2D) -> int:
	var v: Variant = r.get("star")
	return clampi(int(v), 1, 4) if v != null else 1

## 升星后的墨描宽度：基准 ow+2.4；大面积构件每星加粗 1.2（可见外缘 +0.6/星）
static func star_ink_w(ow: float, st: int) -> float:
	var base: float = ow + 2.4
	if base < STAR_INK_MIN:
		return base
	return base + 1.2 * float(st - 1)

## 升星后的硬投影偏移：(2,2) → ★2 (2.6,2.6) → ★3 (3.2,3.2) → ★4 (3.8,3.8)
static func star_shadow_off(st: int) -> float:
	return 2.0 + 0.6 * float(clampi(st - 1, 0, 3))
