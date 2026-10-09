class_name CultivatorBase
extends Node2D

## 修仙角色代码程序化绘制基类
## 提供通用角度枚举、动画循环及抗锯齿矢量几何绘制工具

enum Angle {
	FRONT, ## 正面朝向（俯视正对镜头）
	SIDE,  ## 侧面/斜向（冲刺与战斗主姿态）
	BACK   ## 背面朝向（背影持剑/背负剑匣）
}

@export var current_angle: Angle = Angle.FRONT:
	set(val):
		current_angle = val
		queue_redraw()

@export var animate: bool = true
var _time: float = 0.0

func _process(delta: float) -> void:
	if animate:
		_time += delta
		queue_redraw()

func _draw() -> void:
	match current_angle:
		Angle.FRONT:
			_draw_front()
		Angle.SIDE:
			_draw_side()
		Angle.BACK:
			_draw_back()

func _draw_front() -> void:
	pass

func _draw_side() -> void:
	pass

func _draw_back() -> void:
	pass

# ----------------- 实用矢量绘制工具 -----------------

## 绘制带轮廓的多边形
func draw_stroked_polygon(pts: PackedVector2Array, fill_col: Color, stroke_col: Color, stroke_w: float = 2.0) -> void:
	if pts.size() < 3:
		return
	draw_colored_polygon(pts, fill_col)
	var closed_pts := pts.duplicate()
	closed_pts.append(pts[0])
	draw_polyline(closed_pts, stroke_col, stroke_w, true)

## 绘制带轮廓的圆形
func draw_stroked_circle(center: Vector2, radius: float, fill_col: Color, stroke_col: Color, stroke_w: float = 2.0) -> void:
	draw_circle(center, radius, fill_col)
	draw_arc(center, radius, 0, TAU, 32, stroke_col, stroke_w, true)

## 绘制带轮廓的椭圆
func draw_stroked_ellipse(center: Vector2, rx: float, ry: float, fill_col: Color, stroke_col: Color, stroke_w: float = 2.0, segments: int = 32) -> void:
	var pts := PackedVector2Array()
	for i in range(segments):
		var theta := (float(i) / float(segments)) * TAU
		pts.append(center + Vector2(cos(theta) * rx, sin(theta) * ry))
	draw_stroked_polygon(pts, fill_col, stroke_col, stroke_w)

## 绘制填充椭圆
func draw_filled_ellipse(center: Vector2, rx: float, ry: float, col: Color, segments: int = 24) -> void:
	var pts := PackedVector2Array()
	for i in range(segments):
		var theta := (float(i) / float(segments)) * TAU
		pts.append(center + Vector2(cos(theta) * rx, sin(theta) * ry))
	draw_colored_polygon(pts, col)

## 绘制柔和外晕光圈
func draw_soft_glow(center: Vector2, radius: float, col: Color, layers: int = 3) -> void:
	for i in range(layers):
		var r := radius * (1.0 + float(i) * 0.45)
		var a := col.a / float(i + 1.8)
		draw_circle(center, r, Color(col.r, col.g, col.b, a))
