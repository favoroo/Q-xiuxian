class_name BeamRenderer
extends Node2D

## 持续光束渲染器（紫虹镜，2026-10-13）：三层电光束 + 蛇形摆芯 + 命中端菱晶溅射。
## 几何契约：set_beam 下发的 length 就是判定长度（画多远==判多远）——
## 由 FloatingWeapon._beam_cast_length 的射线结果唯一决定，渲染器不自算、不糊大。
## 零贴图零粒子零灯光；20Hz 错相重绘（本项目 _draw 标准节流），非激活期不占渲染帧。

var length: float = 0.0
var beam_width: float = 10.0
var tint: Color = Color(0.70, 0.55, 1.0)

const REDRAW_INTERVAL := 0.05
const SEGS := 12

var _anim: float = 0.0
var _phase: float = 0.0

func _ready() -> void:
	visible = false
	set_process(false)
	# 错相初始化：避免多把束流武器同帧扎堆重绘
	_phase = fposmod(float(get_instance_id() % 97) * 0.001, REDRAW_INTERVAL)

## 亮起/续命：每帧下发当前几何（长度随射线命中变化）
func beam_on(p_length: float, p_width: float, p_tint: Color) -> void:
	length = p_length
	beam_width = p_width
	tint = p_tint
	if not visible:
		visible = true
		set_process(true)

func beam_off() -> void:
	visible = false
	set_process(false)

func _process(delta: float) -> void:
	_anim += delta
	_phase += delta
	if _phase >= REDRAW_INTERVAL:
		_phase -= REDRAW_INTERVAL
		queue_redraw()

func _draw() -> void:
	if length <= 1.0:
		return
	# 中心线蛇形驻波：根部稳、尾端飘（激光不是死直线，是憋着能量的电弧）
	var pts := PackedVector2Array()
	pts.resize(SEGS + 1)
	for i in SEGS + 1:
		var x := length * float(i) / float(SEGS)
		var wob := sin(x * 0.09 - _anim * 26.0) * 2.6 * (0.25 + 0.75 * float(i) / float(SEGS))
		pts[i] = Vector2(x, wob)
	# 三层同形叠画：外晕 / 主束 / 白炽芯
	var glow := tint
	glow.a = 0.22
	var mid := tint
	mid.a = 0.55
	var core := tint.lerp(Color.WHITE, 0.75)
	core.a = 0.95
	draw_polyline(pts, glow, beam_width)
	draw_polyline(pts, mid, beam_width * 0.5)
	draw_polyline(pts, core, beam_width * 0.18)
	# 命中端溅射：菱晶 + 四散电丝，脉冲呼吸
	var tip := pts[SEGS]
	var pulse := 1.0 + sin(_anim * 30.0) * 0.25
	var d := 5.0 * pulse
	draw_colored_polygon(PackedVector2Array([
		tip + Vector2(d, 0.0), tip + Vector2(0.0, -d),
		tip + Vector2(-d, 0.0), tip + Vector2(0.0, d)]), core)
	for k in 4:
		var a := float(k) * TAU / 4.0 + _anim * 7.0
		var dir := Vector2(cos(a), sin(a))
		draw_line(tip + dir * d, tip + dir * (d + 5.0), mid, 1.4)
