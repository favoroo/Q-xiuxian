class_name ConeTelegraph
extends Node2D

## 扇形攻击预警（Boss 烈焰喷吐 / 扇形范围技能共用）。
## 范围视觉与判定同源：length 与 half_angle 必须与持有者判定参数严格同源。
## 本组件不自算范围、不自判伤害，只负责呈现。
## 扇形朝向为局部 +X 轴，展开角度范围为 [-half_angle, +half_angle]。
## 20Hz 错相重绘节流（对齐 AoeTelegraph 规范）。

const REDRAW_INTERVAL := 0.05
const FILL_ALPHA_PEAK := 0.20
const EDGE_W_MIN := 3.0
const EDGE_W_MAX := 5.0
const SEGS := 28

static var redraw_count: int = 0

var length: float = 300.0
var half_angle: float = 0.5585   ## rad ≈ 32°
var progress: float = 0.0        ## 0→1，由持有者驱动；到 1 即结算出招
var color: Color = GameStyle.BAD ## 预警颜色（默认 BAD 警示红，支持传招式主题色）

var _clock: float = 0.0
var _draw_phase: float = 0.0

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_draw_phase = fposmod(float(get_instance_id() % 97) * 0.001, REDRAW_INTERVAL)

func set_shape(new_length: float, new_half_angle: float) -> void:
	length = maxf(new_length, 0.0)
	half_angle = maxf(new_half_angle, 0.0)
	queue_redraw()

func reset() -> void:
	progress = 0.0
	visible = false
	queue_redraw()

func _process(delta: float) -> void:
	if not visible:
		return
	_clock += delta
	_draw_phase -= delta
	if _draw_phase <= 0.0:
		_draw_phase = REDRAW_INTERVAL
		redraw_count += 1
		queue_redraw()

func _draw() -> void:
	if not visible or length <= 0.0 or half_angle <= 0.0:
		return

	var t := clampf(progress, 0.0, 1.0)
	var seg_count := SEGS

	# 1. 填充扇形从 0 展开到 progress（按当前角度范围扫开，让玩家看出"还在起手"）
	if t > 0.001:
		var cur_half := half_angle * t
		var pts := PackedVector2Array()
		pts.append(Vector2.ZERO)
		for i in range(seg_count + 1):
			var a := lerpf(-cur_half, cur_half, float(i) / float(seg_count))
			pts.append(Vector2(cos(a), sin(a)) * length)
		var fill_alpha := FILL_ALPHA_PEAK * lerpf(0.6, 1.0, t)
		var fill_col := Color(color.r, color.g, color.b, fill_alpha)
		draw_colored_polygon(pts, fill_col)

		# 展开中填充扇形前沿边界（未达 1.0 时让扫开动态更分明）
		if t < 0.98:
			var lead_col := Color(color.r, color.g, color.b, 0.35)
			var p_lead_top := Vector2(cos(-cur_half), sin(-cur_half)) * length
			var p_lead_bot := Vector2(cos(cur_half), sin(cur_half)) * length
			draw_line(Vector2.ZERO, p_lead_top, lead_col, 1.5, true)
			draw_line(Vector2.ZERO, p_lead_bot, lead_col, 1.5, true)

	# 2. 判定边界：外弧（宽 3~5px）+ 两条径向边
	var edge_w := lerpf(EDGE_W_MIN, EDGE_W_MAX, t)
	var edge_alpha := lerpf(0.55, 0.90, t)
	var edge_col := Color(color.r, color.g, color.b, edge_alpha)

	# 外弧（判定最远射程边界）
	draw_arc(Vector2.ZERO, length, -half_angle, half_angle, seg_count, edge_col, edge_w, true)

	# 两条径向边（判定扇角边界）
	var p_top := Vector2(cos(-half_angle), sin(-half_angle)) * length
	var p_bot := Vector2(cos(half_angle), sin(half_angle)) * length
	draw_line(Vector2.ZERO, p_top, edge_col, edge_w, true)
	draw_line(Vector2.ZERO, p_bot, edge_col, edge_w, true)
