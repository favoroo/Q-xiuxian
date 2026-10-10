class_name CultivatorRendererBase
extends Node2D

## 程序化修仙角色绘制抽象基类
## 规范全动作状态机（Idle/Run/Dash/Attack/Hit）与三向视角（Front/Side/Back）的统一绘制接口

enum Action {
	IDLE,   ## 待机浮沉
	RUN,    ## 步态奔跑
	DASH,   ## 极速冲刺
	ATTACK, ## 拔剑斩击
	HIT     ## 受击硬直
}

enum Angle {
	FRONT, ## 正面视角
	SIDE,  ## 3/4 侧面视角
	BACK   ## 背面视角
}

@export var config: CultivatorVisualConfig:
	set(val):
		config = val
		_on_config_changed()
		queue_redraw()

func _on_config_changed() -> void:
	pass


var current_action: Action = Action.IDLE:
	set(val):
		current_action = val
		queue_redraw()

var current_angle: Angle = Angle.FRONT:
	set(val):
		current_angle = val
		queue_redraw()

var flip_h: bool = false:
	set(val):
		flip_h = val
		queue_redraw()

## 动画驱动物理参数（由 ProceduralCultivatorView 注入）
var gait_phase: float = 0.0
var air: float = 0.0
var speed_ratio: float = 1.0
var dash_progress: float = 0.0   # 0.0 到 1.0
var attack_progress: float = 0.0 # 0.0 到 1.0
var hit_progress: float = 0.0    # 0.0 到 1.0
var lean_angle: float = 0.0

var _time: float = 0.0

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	# 根据动作状态机分发到具体绘制函数
	match current_action:
		Action.IDLE:
			_draw_idle(current_angle)
		Action.RUN:
			_draw_run(current_angle, gait_phase, air)
		Action.DASH:
			_draw_dash(current_angle, dash_progress)
		Action.ATTACK:
			_draw_attack(current_angle, attack_progress)
		Action.HIT:
			_draw_hit(current_angle, hit_progress)

# ----------------- 虚拟接口（由具体风格渲染器实现） -----------------

func _draw_idle(_angle: Angle) -> void:
	pass

func _draw_run(_angle: Angle, _phase: float, _air: float) -> void:
	pass

func _draw_dash(_angle: Angle, _progress: float) -> void:
	pass

func _draw_attack(_angle: Angle, _progress: float) -> void:
	pass

func _draw_hit(_angle: Angle, _progress: float) -> void:
	pass

# ----------------- 实用矢量与几何绘制工具 -----------------

func draw_stroked_polygon(pts: PackedVector2Array, fill_col: Color, stroke_col: Color, stroke_w: float = 2.0) -> void:
	if pts.size() < 3:
		return
	draw_colored_polygon(pts, fill_col)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, stroke_col, stroke_w, true)

func draw_stroked_circle(center: Vector2, radius: float, fill_col: Color, stroke_col: Color, stroke_w: float = 2.0) -> void:
	draw_circle(center, radius, fill_col)
	draw_arc(center, radius, 0, TAU, 32, stroke_col, stroke_w, true)

func draw_stroked_ellipse(center: Vector2, rx: float, ry: float, fill_col: Color, stroke_col: Color, stroke_w: float = 2.0, segments: int = 28) -> void:
	var pts := PackedVector2Array()
	for i in range(segments):
		var theta := (float(i) / float(segments)) * TAU
		pts.append(center + Vector2(cos(theta) * rx, sin(theta) * ry))
	draw_stroked_polygon(pts, fill_col, stroke_col, stroke_w)

func draw_filled_ellipse(center: Vector2, rx: float, ry: float, col: Color, segments: int = 24) -> void:
	var pts := PackedVector2Array()
	for i in range(segments):
		var theta := (float(i) / float(segments)) * TAU
		pts.append(center + Vector2(cos(theta) * rx, sin(theta) * ry))
	draw_colored_polygon(pts, col)

func draw_soft_glow(center: Vector2, radius: float, col: Color, layers: int = 3) -> void:
	for i in range(layers):
		var r := radius * (1.0 + float(i) * 0.45)
		var a := col.a / float(i + 1.8)
		draw_circle(center, r, Color(col.r, col.g, col.b, a))
