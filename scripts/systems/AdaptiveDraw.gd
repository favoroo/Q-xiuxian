class_name AdaptiveDraw
extends RefCounted

## 自适应段数矢量圆/弧绘制工具（2026-10-16 性能优化）
## 背景：内置 CanvasItem.draw_circle 固定 64 段，1px 小点也付 ~63 个三角形的钱；
## 地面/阵法装饰层往往上百个微小圆点，单层就能吃掉上万图元（实测 21k 的大头）。
## 按半径自适应 6~28 段，微小装饰点肉眼无差。与 CultivatorBase._circle/_arc 同一思路，
## 抽成静态工具供非 Cultivator 系的装饰层（GroundDecorLayer/ArenaVisualLayer/player_aura 等）共用。
## 静态缓冲复用：_draw 在主线程串行执行，无重入风险。
##
## 2026-10-29 性能补充：
## ① 单位圆顶点按段数缓存（_unit_cache），每次调用只做「缩放 + 平移」，不再付 segment 次
##    sin/cos（满场 140 颗宝石 × 7 圆 × 20Hz 曾因此每秒多烧 ~2 万次三角函数）。
## ② 新增 chord_px 参数：按「弦长 ≤ chord_px 像素」反解段数（下限 8、上限 40），
##    供对轮廓精度有要求的调用点（宝石耀斑、技能光点）在几乎零视觉差的前提下减面。
##    默认 0 保持旧公式，既有装饰层观感与开销完全不变。

static var _buf := PackedVector2Array()
## 单位圆顶点缓存：段数 → 半径 1 的圆周点
static var _unit_cache: Dictionary = {}

## 自适应段数填充圆（替代内置 draw_circle 的 64 段固定开销）
## chord_px > 0 时按弦长选段数（更平滑且可控），否则沿用旧公式。
static func circle(item: CanvasItem, center: Vector2, radius: float, col: Color, chord_px: float = 0.0) -> void:
	var seg := 0
	if chord_px > 0.0:
		# n = π / asin(chord / 2r)：半径越大段数越多，保证任意尺寸下轮廓弦长不超阈
		var ratio: float = clampf(chord_px / maxf(radius * 2.0, 0.0001), 0.0, 1.0)
		seg = clampi(int(ceil(PI / maxf(asin(ratio), 0.0001))), 8, 40)
	else:
		seg = clampi(int(radius * 1.4), 6, 28)
	var unit: PackedVector2Array = _unit_points(seg)
	_buf.resize(seg)
	for i in seg:
		_buf[i] = center + unit[i] * radius
	item.draw_colored_polygon(_buf, col)

## 取（并缓存）单位圆顶点表，只在首次见到该段数时算三角函数
static func _unit_points(seg: int) -> PackedVector2Array:
	var cached: Variant = _unit_cache.get(seg)
	if cached != null:
		return cached as PackedVector2Array
	var pts := PackedVector2Array()
	pts.resize(seg)
	var step := TAU / float(seg)
	for i in seg:
		var ang := step * float(i)
		pts[i] = Vector2(cos(ang), sin(ang))
	_unit_cache[seg] = pts
	return pts

## 自适应段数弧线（段数按半径与弧角张量 6~32；全圆 TAU 时与 CultivatorBase._arc 同式）
static func arc(item: CanvasItem, center: Vector2, radius: float, start_angle: float, end_angle: float, color: Color, width: float = 1.0, antialiased: bool = false) -> void:
	var seg := clampi(int(radius * absf(end_angle - start_angle) * 0.22), 6, 32)
	item.draw_arc(center, radius, start_angle, end_angle, seg, color, width, antialiased)
