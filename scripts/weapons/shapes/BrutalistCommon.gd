extends RefCounted

## 新野兽派法器画法 · 共用调色板与构件（刃/重/巧三族模块共用，配色只改这一处）
##
## 画法纪律（用户认可的样稿口径，不得偏离）：
##   · 平涂色块 + 粗墨描边 + 右下硬偏移投影；零辉光 / 零渐变 / 零装饰纹。
##   · 每把 = 五行主色一大块（pal["body"]）+ 撞色块一处（pal["accent"]）+ 墨黑。
##   · 升星表达：★2/★3 用 star_studs 撞色方钉，不加任何光效。
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
static func flat(r: Node2D, pts: PackedVector2Array, fill: Color, ow: float = 2.2) -> void:
	var sh := PackedVector2Array()
	for p in pts:
		sh.append(p + Vector2(2.0, 2.0))
	r.draw_colored_polygon(sh, SHADOW)
	var closed := pts.duplicate()
	closed.append(pts[0])
	r.draw_polyline(closed, INK, ow + 2.4, true)
	r.draw_colored_polygon(pts, fill)

## 粗杆（柄/骨/轴）：投影 + 墨描 + 纯色芯
static func bar(r: Node2D, a: Vector2, b: Vector2, w: float, col: Color) -> void:
	r.draw_line(a + Vector2(2.0, 2.0), b + Vector2(2.0, 2.0), SHADOW, w + 2.4, true)
	r.draw_line(a, b, INK, w + 2.4, true)
	r.draw_line(a, b, col, w, true)

## 方钉/方块构件（剑首、印钮、销钉）
static func square(r: Node2D, c: Vector2, half: float, col: Color, ow: float = 1.4) -> void:
	flat(r, PackedVector2Array([
		c + Vector2(-half, -half), c + Vector2(half, -half),
		c + Vector2(half, half), c + Vector2(-half, half),
	]), col, ow)

## 圆盘（鼓面/镜面/珠体）：投影 + 墨描 + 平涂
static func disc(r: Node2D, c: Vector2, radius: float, fill: Color, ow: float = 2.4) -> void:
	r.draw_circle(c + Vector2(2.0, 2.0), radius, SHADOW)
	r.draw_circle(c, radius, INK)
	r.draw_circle(c, radius - ow, fill)

## 圆环带（鼓环/镜框）：墨底 + 撞色环
static func ring(r: Node2D, c: Vector2, radius: float, w: float, col: Color) -> void:
	r.draw_arc(c, radius, 0.0, TAU, 28, INK, w + 2.0, true)
	r.draw_arc(c, radius, 0.0, TAU, 28, col, w, true)

## 升星方钉（唯一的星级表达）：★2 在 a 落一颗撞色方钉，★3 再在 b 落一颗
static func star_studs(r: Node2D, star: int, a: Vector2, b: Vector2, col: Color) -> void:
	if star >= 2:
		square(r, a, 1.7, col, 1.2)
	if star >= 3:
		square(r, b, 1.7, col, 1.2)
