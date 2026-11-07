class_name BatchDraw
extends RefCounted

## 填充多边形合批工具（2026-10-29 渲染专项，实测见 tests/DrawCallProbe.tscn）
##
## 背景：gl_compatibility 下 CanvasItem.draw_colored_polygon / draw_circle 每个原语都是
## 独立 draw call（实测 100 个填充多边形 = 100 draws），而一次
## RenderingServer.canvas_item_add_triangle_array 能把任意多三角形压成 1 个 draw call
## （实测 100 个三角形 = 1 draw）。矢量渲染器单次 _draw 常有 6~20 个填充面片，
## 不合成就是 6~20 个 draw call —— 这是敌人/掉落物/技能特效在低端机上的头号提交开销。
##
## 使用纪律（顺序正确性靠这三条保证，违反其一就会出现叠放错乱）：
##   ① 只收集「填充多边形」与「合批线」（line/polyline，斜接四边形并进同一三角形数组，
##      顺序由索引序保证，无需 flush）；贴图/文字等其余原语之前必须先 flush()，
##      让合批命令落在与原来完全相同的位置；
##   ② 每个 _draw 结束前必须 flush()（静态缓冲全进程共用，残留会串到下一帧/下一个对象）；
##   ③ 同批内按顶点顺序栅格化，多边形之间的覆盖关系与逐次绘制一致（半透明面片先铺底后压上），
##      但不要把「必须画在某个非填充原语之上」的面片留在批里。
##
## 多边形按扇形三角化，要求凸多边形（宝石切面/圆/蛋形均由凸块拼成）。
##
## 线条合批（2026-11-02 高负载渲染专项）：原生 draw_line/draw_polyline 每根线 1 个 draw call，
## 敌形描边/细节线单敌 10~25 根 = 满场数百次提交，是 48 敌同屏 draws 破两千的主因。
## line()/polyline() 把线转成斜接四边形三角形并进合批（1~2px 细线放弃引擎抗锯齿，
## Nearest 像素风下无感；半透明线接头用斜接拉伸避免端点叠斑）。

static var _pts := PackedVector2Array()
static var _cols := PackedColorArray()
static var _idx := PackedInt32Array()

## —— 调试计数（2026-11-07，正式路径成本 = flush 里两次整数自增/赋值）——
## 「弹丸不许加 draw call、批顶点别失控」这条红线原先只能靠人肉看代码：
## 单发弹体的 draw call 数 = 非空 flush 次数，顶点数 = _pts.size()。
## tests/inspect_check.gd 按器形逐个 _draw() 后读这两个数做预算断言。
static var last_flush_vertices: int = 0
static var flush_submits: int = 0

static func reset_draw_stats() -> void:
	last_flush_vertices = 0
	flush_submits = 0

## 收集一个凸填充多边形
static func poly(item: CanvasItem, points: PackedVector2Array, col: Color) -> void:
	var n := points.size()
	if n < 3:
		return
	var base := _pts.size()
	_pts.append_array(points)
	for i in n:
		_cols.append(col)
	for i in range(1, n - 1):
		_idx.append(base)
		_idx.append(base + i)
		_idx.append(base + i + 1)

## 收集一个填充圆（段数与 AdaptiveDraw.circle 同口径）
static func circle(item: CanvasItem, center: Vector2, radius: float, col: Color, chord_px: float = 3.2) -> void:
	var ratio: float = clampf(chord_px / maxf(radius * 2.0, 0.0001), 0.0, 1.0)
	var seg: int = clampi(int(ceil(PI / maxf(asin(ratio), 0.0001))), 8, 40)
	var base := _pts.size()
	var step := TAU / float(seg)
	for i in seg:
		var ang := step * float(i)
		_pts.append(center + Vector2(cos(ang), sin(ang)) * radius)
		_cols.append(col)
	for i in range(1, seg - 1):
		_idx.append(base)
		_idx.append(base + i)
		_idx.append(base + i + 1)

static var _miter: PackedVector2Array = PackedVector2Array()  ## polyline 斜接偏移复用缓冲
static var _arc_pts: PackedVector2Array = PackedVector2Array()  ## arc 采样点复用缓冲
static var _rect_pts: PackedVector2Array = PackedVector2Array()  ## rect 顶点复用缓冲

## 收集一根弧线（按 AdaptiveDraw.arc 同款段数公式转 polyline）。
## 用途：武器/弹丸/阵法里的 draw_arc 大多是 1~2px 装饰弧，逐条原生提交会打断合批；
## 转成斜接四边形后与填充面片共用一次 draw call。对 AA 有硬要求的极细弧仍可保留原生
## draw_arc（调用前先 flush）。
static func arc(item: CanvasItem, center: Vector2, radius: float, start_angle: float, end_angle: float, col: Color, width: float = 1.0, _antialiased: bool = false, segments: int = 0) -> void:
	if radius <= 0.0 or col.a <= 0.0:
		return
	var span := absf(end_angle - start_angle)
	if span < 0.0001:
		return
	# segments>0 = 调用方原生 draw_arc 的 point_count，照原样保留（AoE 预警大圈原本 48~64 段）；
	# 0 = AdaptiveDraw 同款自适应（6~32 段），供 UI/小装饰弧用。两条上限分开，别让
	# 自适应路径把大半径装饰圈也拉到 96 段（会白付三倍顶点）。
	var seg := clampi(segments, 4, 96) if segments > 0 else clampi(int(radius * span * 0.22), 6, 32)
	_arc_pts.resize(seg + 1)
	var step := (end_angle - start_angle) / float(seg)
	for i in range(seg + 1):
		var ang := start_angle + step * float(i)
		_arc_pts[i] = center + Vector2(cos(ang), sin(ang)) * radius
	polyline(item, _arc_pts, col, width)

## 收集一个轴对齐矩形（填充，2 三角形）
static func rect(item: CanvasItem, r: Rect2, col: Color) -> void:
	if col.a <= 0.0:
		return
	_rect_pts.resize(4)
	_rect_pts[0] = r.position
	_rect_pts[1] = Vector2(r.end.x, r.position.y)
	_rect_pts[2] = r.end
	_rect_pts[3] = Vector2(r.position.x, r.end.y)
	poly(item, _rect_pts, col)

## 收集任意简单多边形（自动三角化，凹多边形安全）。
## 现有的 poly() 只做扇形三角化，要求凸多边形；弯刀月牙/斧刃/葫芦腰/手里剑这类凹形
## 必须走这里，否则会画出穿帮的扇形。三角化只在每次 _draw 调用时做一次（器形/弹体
## 本身有重绘节流，不作为每帧热路径）。
static func poly_any(item: CanvasItem, points: PackedVector2Array, col: Color) -> void:
	var n := points.size()
	if n < 3 or col.a <= 0.0:
		return
	# 允许调用方传闭合多边形（首尾重复）：先剥掉重复尾点再三角化
	if points[0].is_equal_approx(points[n - 1]):
		n -= 1
		if n < 3:
			return
	var poly_pts: PackedVector2Array = points if n == points.size() else points.slice(0, n)
	var tri := Geometry2D.triangulate_polygon(poly_pts)
	if tri.is_empty():
		# 三角化失败（自交/退化）：退回凸扇形，至少保证不崩；内容本身已不合法
		poly(item, poly_pts, col)
		return
	var base := _pts.size()
	_pts.append_array(poly_pts)
	for i in n:
		_cols.append(col)
	for i in tri:
		_idx.append(base + int(i))

# ---------------- 原生 draw_* 同名参数适配（便于存量渲染器机械迁移）----------------
# 这些 helper 的参数顺序与 CanvasItem.draw_* 一致，只是多了首参 item；把
# `draw_line(` 换成 `BatchDraw.native_line(self, ` / `r.draw_line(` 换成
# `BatchDraw.native_line(r, ` 即可，不用逐处删 antialiased/point_count 参数。
# 原生抗锯齿参数被忽略（BatchDraw 用斜接四边形；Nearest 像素风下差异极小）。

static func native_line(item: CanvasItem, a: Vector2, b: Vector2, col: Color, width: float = -1.0, _antialiased: bool = false) -> void:
	line(item, a, b, col, 1.0 if width <= 0.0 else width)

static func native_polyline(item: CanvasItem, points: PackedVector2Array, col: Color, width: float = -1.0, _antialiased: bool = false) -> void:
	polyline(item, points, col, 1.0 if width <= 0.0 else width)

static func native_poly(item: CanvasItem, points: PackedVector2Array, col: Color, _uvs: Variant = null, _texture: Variant = null) -> void:
	poly_any(item, points, col)

static func native_arc(item: CanvasItem, center: Vector2, radius: float, start_angle: float, end_angle: float, point_count: int, col: Color, width: float = -1.0, _antialiased: bool = false) -> void:
	arc(item, center, radius, start_angle, end_angle, col, 1.0 if width <= 0.0 else width, false, point_count)

static func native_rect(item: CanvasItem, r: Rect2, col: Color, filled: bool = true, width: float = -1.0, _antialiased: bool = false) -> void:
	if filled:
		rect(item, r, col)
		return
	_rect_pts.resize(5)
	_rect_pts[0] = r.position
	_rect_pts[1] = Vector2(r.end.x, r.position.y)
	_rect_pts[2] = r.end
	_rect_pts[3] = Vector2(r.position.x, r.end.y)
	_rect_pts[4] = r.position
	polyline(item, _rect_pts, col, 1.0 if width <= 0.0 else width)

static func native_circle(item: CanvasItem, center: Vector2, radius: float, col: Color, filled: bool = true, width: float = -1.0, _antialiased: bool = false) -> void:
	if filled:
		circle(item, center, radius, col)
	else:
		arc(item, center, radius, 0.0, TAU, col, 1.0 if width <= 0.0 else width)

## 收集一根线段（等宽四边形，2 三角形）
static func line(item: CanvasItem, a: Vector2, b: Vector2, col: Color, width: float = 1.0) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.001 or col.a <= 0.0:
		return
	var off: Vector2 = Vector2(-d.y, d.x) * (width * 0.5 / len)
	_quad(a + off, b + off, b - off, a - off, col)

## 收集一条折线（逐段四边形，内角斜接 —— 半透明描边接头处不会因重叠而加深出斑）
static func polyline(item: CanvasItem, points: PackedVector2Array, col: Color, width: float = 1.0) -> void:
	var n := points.size()
	if n < 2 or col.a <= 0.0:
		return
	var half := width * 0.5
	if _miter.size() < n:
		_miter.resize(n)
	# 逐点求偏移向量：端点取法线，内点取相邻两法线的斜接方向（限幅防尖角拉飞）
	for i in n:
		var dir: Vector2
		if i == 0:
			dir = (points[1] - points[0]).normalized()
			_miter[i] = Vector2(-dir.y, dir.x) * half
		elif i == n - 1:
			dir = (points[n - 1] - points[n - 2]).normalized()
			_miter[i] = Vector2(-dir.y, dir.x) * half
		else:
			var d0: Vector2 = (points[i] - points[i - 1]).normalized()
			var d1: Vector2 = (points[i + 1] - points[i]).normalized()
			var n0 := Vector2(-d0.y, d0.x)
			var n1 := Vector2(-d1.y, d1.x)
			var m := n0 + n1
			if m.length_squared() < 0.0001:
				_miter[i] = n1 * half  # 近 180° 回头线：退化用下一段法线
			else:
				m = m.normalized()
				# 斜接长度 = half / cos(转角/2)；dot(m, n1) 即 cos，钳 0.4 防爆
				var scale := half / maxf(m.dot(n1), 0.4)
				_miter[i] = m * scale
	for i in range(n - 1):
		var a := points[i]
		var b := points[i + 1]
		if a.distance_squared_to(b) < 0.000001:
			continue
		_quad(a + _miter[i], b + _miter[i + 1], b - _miter[i + 1], a - _miter[i], col)

static func _quad(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2, col: Color) -> void:
	var base := _pts.size()
	_pts.append(p1)
	_pts.append(p2)
	_pts.append(p3)
	_pts.append(p4)
	for i in 4:
		_cols.append(col)
	_idx.append(base)
	_idx.append(base + 1)
	_idx.append(base + 2)
	_idx.append(base)
	_idx.append(base + 2)
	_idx.append(base + 3)

## 提交当前批次（一次 draw call）
static func flush(item: CanvasItem) -> void:
	if _idx.is_empty():
		return
	RenderingServer.canvas_item_add_triangle_array(item.get_canvas_item(), _idx, _pts, _cols)
	last_flush_vertices = _pts.size()
	flush_submits += 1
	_clear()

## 丢弃未提交的批次（异常路径兜底，正常只走 flush）
static func discard() -> void:
	_clear()

## 待提交顶点/索引数（单测与调试用；生产路径不读）
static func pending_vertex_count() -> int:
	return _pts.size()

static func pending_index_count() -> int:
	return _idx.size()

static func _clear() -> void:
	_pts.clear()
	_cols.clear()
	_idx.clear()
