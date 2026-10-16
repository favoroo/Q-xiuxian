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
		_draw_phase = 0.0  # 姿态切换插队重绘，不等下一拍

@export var animate: bool = true
var _time: float = 0.0

# —— 重绘节流 + 屏外剔除（2026-10-16，照 CultivatorRendererBase/HollowKnightEnemyRenderer 范式）——
## 本基类此前每帧无条件 queue_redraw() 且无可见性守卫：画廊 4 风格 × 多姿态十几个实例
## 哪怕藏在隐藏面板里也照跑 60Hz 全量重绘。节流 20Hz + instance_id 错相摊帧，
## 与 CultivatorRendererBase（玩家级 30Hz）口径一致；animate=false 时完全静止零重绘。
const REDRAW_INTERVAL := 0.05

var _draw_phase: float = 0.0

func _ready() -> void:
	_draw_phase = fposmod(float(get_instance_id() % 97) * 0.001, REDRAW_INTERVAL)

func _process(delta: float) -> void:
	if not animate:
		return
	_time += delta
	# 隐藏（如未打开的画廊面板）不重绘：visible=false 时 CanvasItem 不提交绘制，重绘纯浪费
	if not is_visible_in_tree():
		return
	if _draw_phase <= 0.0:
		_draw_phase = REDRAW_INTERVAL
		# 屏外剔除：局部原点投到屏幕坐标，落在视口外（留 96px 边距给大件装饰）就不必重绘
		var canvas_xf := get_viewport().get_canvas_transform()
		var screen_pos := canvas_xf * get_global_transform().origin
		var vp := get_viewport().get_visible_rect().size
		if screen_pos.x < -96.0 or screen_pos.y < -96.0 or screen_pos.x > vp.x + 96.0 or screen_pos.y > vp.y + 96.0:
			return
		queue_redraw()
	else:
		_draw_phase -= delta

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

## 自适应圆/弧段数（2026-10-14 性能优化）：内置 draw_circle 固定 64 段，
## 小至 1px 的眸光点也付 64 三角形的钱；渲染器的 draw_circle/draw_arc 统一走这两个包装，
## 按半径与弧角张量自适应 6~32 段。静态缓冲复用，_draw 在主线程串行执行，无重入风险。
static var _circle_buf := PackedVector2Array()
static var _stroke_buf := PackedVector2Array()

func _circle(center: Vector2, radius: float, col: Color) -> void:
	var seg := clampi(int(radius * 1.4), 6, 28)
	_circle_buf.resize(seg)
	for i in range(seg):
		var ang := float(i) * TAU / float(seg)
		_circle_buf[i] = center + Vector2(cos(ang), sin(ang)) * radius
	draw_colored_polygon(_circle_buf, col)

func _arc(center: Vector2, radius: float, start_angle: float, end_angle: float, _point_count: int, color: Color, width: float = 1.0, antialiased: bool = false) -> void:
	var seg := clampi(int(radius * absf(end_angle - start_angle) * 0.22), 6, 32)
	draw_arc(center, radius, start_angle, end_angle, seg, color, width, antialiased)

## 绘制带轮廓的多边形
func draw_stroked_polygon(pts: PackedVector2Array, fill_col: Color, stroke_col: Color, stroke_w: float = 2.0) -> void:
	if pts.size() < 3:
		return
	draw_colored_polygon(pts, fill_col)
	var n := pts.size()
	_stroke_buf.resize(n + 1)
	for i in range(n):
		_stroke_buf[i] = pts[i]
	_stroke_buf[n] = pts[0]
	draw_polyline(_stroke_buf, stroke_col, stroke_w, true)

## 绘制带轮廓的圆形
func draw_stroked_circle(center: Vector2, radius: float, fill_col: Color, stroke_col: Color, stroke_w: float = 2.0) -> void:
	_circle(center, radius, fill_col)
	_arc(center, radius, 0, TAU, 32, stroke_col, stroke_w, true)

## 绘制带轮廓的椭圆（segments <= 0 时按半径自适应段数）
func draw_stroked_ellipse(center: Vector2, rx: float, ry: float, fill_col: Color, stroke_col: Color, stroke_w: float = 2.0, segments: int = 0) -> void:
	if segments <= 0:
		segments = clampi(int(maxf(rx, ry) * 1.2), 10, 28)
	_circle_buf.resize(segments)
	for i in range(segments):
		var theta := (float(i) / float(segments)) * TAU
		_circle_buf[i] = center + Vector2(cos(theta) * rx, sin(theta) * ry)
	draw_stroked_polygon(_circle_buf, fill_col, stroke_col, stroke_w)

## 绘制填充椭圆（segments <= 0 时按半径自适应段数）
func draw_filled_ellipse(center: Vector2, rx: float, ry: float, col: Color, segments: int = 0) -> void:
	if segments <= 0:
		segments = clampi(int(maxf(rx, ry) * 1.2), 10, 24)
	_circle_buf.resize(segments)
	for i in range(segments):
		var theta := (float(i) / float(segments)) * TAU
		_circle_buf[i] = center + Vector2(cos(theta) * rx, sin(theta) * ry)
	draw_colored_polygon(_circle_buf, col)

## 绘制柔和外晕光圈
func draw_soft_glow(center: Vector2, radius: float, col: Color, layers: int = 3) -> void:
	for i in range(layers):
		var r := radius * (1.0 + float(i) * 0.45)
		var a := col.a / float(i + 1.8)
		_circle(center, r, Color(col.r, col.g, col.b, a))
