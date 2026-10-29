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
##   ① 只收集「填充多边形」；线/描边/贴图/文字等非填充原语之前必须先 flush()，
##      让合批命令落在与原来完全相同的位置；
##   ② 每个 _draw 结束前必须 flush()（静态缓冲全进程共用，残留会串到下一帧/下一个对象）；
##   ③ 同批内按顶点顺序栅格化，多边形之间的覆盖关系与逐次绘制一致（半透明面片先铺底后压上），
##      但不要把「必须画在某个非填充原语之上」的面片留在批里。
##
## 多边形按扇形三角化，要求凸多边形（宝石切面/圆/蛋形均由凸块拼成）。

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
