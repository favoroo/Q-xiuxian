class_name AdaptiveDraw
extends RefCounted

## 自适应段数矢量圆/弧绘制工具（2026-10-16 性能优化）
## 背景：内置 CanvasItem.draw_circle 固定 64 段，1px 小点也付 ~63 个三角形的钱；
## 地面/阵法装饰层往往上百个微小圆点，单层就能吃掉上万图元（实测 21k 的大头）。
## 按半径自适应 6~28 段，微小装饰点肉眼无差。与 CultivatorBase._circle/_arc 同一思路，
## 抽成静态工具供非 Cultivator 系的装饰层（GroundDecorLayer/ArenaVisualLayer/player_aura 等）共用。
## 静态缓冲复用：_draw 在主线程串行执行，无重入风险。

static var _buf := PackedVector2Array()

## 自适应段数填充圆（替代内置 draw_circle 的 64 段固定开销）
static func circle(item: CanvasItem, center: Vector2, radius: float, col: Color) -> void:
	var seg := clampi(int(radius * 1.4), 6, 28)
	_buf.resize(seg)
	for i in seg:
		var ang := TAU * float(i) / float(seg)
		_buf[i] = center + Vector2(cos(ang), sin(ang)) * radius
	item.draw_colored_polygon(_buf, col)

## 自适应段数弧线（段数按半径与弧角张量 6~32；全圆 TAU 时与 CultivatorBase._arc 同式）
static func arc(item: CanvasItem, center: Vector2, radius: float, start_angle: float, end_angle: float, color: Color, width: float = 1.0, antialiased: bool = false) -> void:
	var seg := clampi(int(radius * absf(end_angle - start_angle) * 0.22), 6, 32)
	item.draw_arc(center, radius, start_angle, end_angle, seg, color, width, antialiased)
