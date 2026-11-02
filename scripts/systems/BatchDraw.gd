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
	_clear()

## 丢弃未提交的批次（异常路径兜底，正常只走 flush）
static func discard() -> void:
	_clear()

static func _clear() -> void:
	_pts.clear()
	_cols.clear()
	_idx.clear()
