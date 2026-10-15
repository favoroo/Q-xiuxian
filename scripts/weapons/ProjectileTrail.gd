class_name ProjectileTrail
extends Node2D

## 弹丸世界坐标历史拖尾：每发弹丸挂一条，top_level 脱离弹体变换，记录最近
## MAX_POINTS（低档 9 / 流畅档 16）个真实飞行位置点，画成渐隐收宽的弧线。
## 为什么需要它：ProceduralProjectileRenderer 的彗尾画在弹体局部 -X 方向，
## 追踪弹 3.6 rad/s 拧弯时拖尾跟着本体瞬间转、不留弧线，「在拐」看不出来。
## 双层 Line2D（宽低透辉光 + 窄亮核）沿用 LightningBolt 的成对画线范式，
## 渐隐/收宽走 gradient / width_curve 的顶点映射（偏移 0 = 最老尾端，1 = 弹头最新点）。

## 历史点数与采样间隔按帧率档位联动（2026-10-15 VisualRate 档位）：
## 低档 30Hz × 9 点 ≈ 0.27s 记忆（perf_probe 旧口径）；流畅档宿主物理 60Hz，
## 采样间隔取略小于一个物理帧 ⇒ 每拍采一个点（≈60Hz），16 点 ≈ 0.27s，
## 记忆长度不变而弧线分辨率翻倍（拐弯处不再 33ms 一个折角）。
const SAMPLE_INTERVAL := 0.033 ## 低档采样节流，与物理帧解耦；静止/低速不堆重合点
const SAMPLE_INTERVAL_HIGH := 0.0125 ## 流畅档采样节流（< 1/60s 物理帧 ⇒ 每拍一点）
const MAX_POINTS_LOW := 9      ## 低档历史点数（30Hz × 9 ≈ 0.27s）
const MAX_POINTS_HIGH := 16    ## 流畅档历史点数（60Hz × 16 ≈ 0.27s）
const MIN_STEP_SQ := 25.0      ## 相邻两点平方距下限（5px），回收前贴脸命中时防零长线段
const GLOW_WIDTH := 8.0
const CORE_WIDTH := 2.4
const GLOW_ALPHA_HEAD := 0.30
const CORE_ALPHA_HEAD := 0.85

var _pts := PackedVector2Array()
var _acc: float = 0.0
var _line_glow: Line2D = null
var _line_core: Line2D = null
var _color := Color(0.95, 0.90, 0.72)

func _ready() -> void:
	# top_level + position 恒为原点 ⇒ 本地坐标 == 世界坐标，历史点直接存全局位置。
	# 画序靠宿主 move_child 压到兄弟首位（z_index -1 会沉到地面瓦片之下，不可用）。
	top_level = true
	position = Vector2.ZERO
	_build_lines()

## 配色下发（与弹体异常色温同源）：BladeProjectile.activate 逐发调用
func configure(color: Color) -> void:
	_color = color
	if _line_glow != null:
		_line_glow.gradient = _make_gradient(GLOW_ALPHA_HEAD)
		_line_core.gradient = _make_gradient(CORE_ALPHA_HEAD)

## 出膛起笔：清空上一发历史后从枪口位置落第一个点
func seed_point(pos: Vector2) -> void:
	reset()
	_pts.append(pos)
	_redraw()

func _sample_interval() -> float:
	return SAMPLE_INTERVAL_HIGH if VisualRate.high_fps else SAMPLE_INTERVAL

func _max_points() -> int:
	return MAX_POINTS_HIGH if VisualRate.high_fps else MAX_POINTS_LOW

## 宿主物理帧调用（宿主自带 _physics_process，池化休眠时一并停发，无需本节点计时）
func sample(pos: Vector2, delta: float) -> void:
	_acc += delta
	if _acc < _sample_interval():
		return
	_acc = 0.0
	if _pts.size() > 0 and _pts[_pts.size() - 1].distance_squared_to(pos) < MIN_STEP_SQ:
		return
	_pts.append(pos)
	var cap := _max_points()
	if _pts.size() > cap:
		_pts = _pts.slice(_pts.size() - cap)
	_redraw()

## 回池清史：残留弧线从上一发死亡点连到下一发枪口就是「池体占拍」的同型事故（AGENTS 坑 13）
func reset() -> void:
	_pts = PackedVector2Array()
	_acc = 0.0
	_redraw()

func _build_lines() -> void:
	_line_glow = _make_line(GLOW_WIDTH, GLOW_ALPHA_HEAD)
	_line_core = _make_line(CORE_WIDTH, CORE_ALPHA_HEAD)

func _make_line(width: float, head_alpha: float) -> Line2D:
	var line := Line2D.new()
	line.width = width
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	# 尾端收到 10% 宽、头端全宽：与渐隐同向，弧线末端自然消失不留圆头
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.1))
	curve.add_point(Vector2(1.0, 1.0))
	line.width_curve = curve
	line.gradient = _make_gradient(head_alpha)
	add_child(line)
	return line

func _make_gradient(head_alpha: float) -> Gradient:
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(_color.r, _color.g, _color.b, 0.0),
		Color(_color.r, _color.g, _color.b, head_alpha),
	])
	return grad

func _redraw() -> void:
	if _line_glow == null or _line_core == null:
		return
	_line_glow.points = _pts
	_line_core.points = _pts
