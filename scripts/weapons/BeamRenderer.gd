class_name BeamRenderer
extends Node2D

## 持续光束渲染器（紫虹镜，2026-10-13）：三层电光束 + 蛇形摆芯 + 命中端菱晶溅射。
## 几何契约：set_beam 下发的 length 就是判定长度（画多远==判多远）——
## 由 FloatingWeapon._beam_cast_length 的射线结果唯一决定，渲染器不自算、不糊大。
## T-2.2 命中端接入 FxBudget 预留动态灯与池化碎屑；20Hz 错相重绘（本项目 _draw 标准节流），非激活期不占渲染帧。

var length: float = 0.0
var beam_width: float = 10.0
var tint: Color = Color(0.70, 0.55, 1.0)

const SEGS := 12
## 重绘节流按帧率档位取双档（2026-10-15 VisualRate 档位联动）：束流端点跟随移动实体，
## 60fps 档 20Hz 是每 3 帧一画、「位置顺画面卡」，翻倍到 40Hz；低档 20Hz 维持 perf_probe 预算。
const HZ_LOW := 20.0
const HZ_HIGH := 40.0
static func _redraw_interval() -> float:
	return VisualRate.interval(HZ_HIGH, HZ_LOW)

var _anim: float = 0.0
var _phase: float = 0.0
var _spark_timer: float = 0.0
var _tip_light: PointLight2D = null
## 顶点缓冲复用（照 ProjectileTrail 环形缓冲先例，避免每次重绘 new PackedVector2Array）
var _pts_buf: PackedVector2Array = []

func _ready() -> void:
	visible = false
	set_process(false)
	# 错相初始化：避免多把束流武器同帧扎堆重绘
	_phase = fposmod(float(get_instance_id() % 97) * 0.001, _redraw_interval())
	_setup_light()

func _setup_light() -> void:
	if _tip_light != null and is_instance_valid(_tip_light):
		return
	_tip_light = PointLight2D.new()
	_tip_light.name = "TipLight"
	_tip_light.texture = load("res://assets/art/light_radial.png") as Texture2D
	_tip_light.texture_scale = 0.35
	_tip_light.energy = 0.6
	_tip_light.color = Color(0.78, 0.55, 1.0)
	_tip_light.enabled = false
	add_child(_tip_light)

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
	if _tip_light != null:
		_tip_light.enabled = false

func _process(delta: float) -> void:
	_anim += delta
	_phase += delta
	_spark_timer -= delta
	if _spark_timer <= 0.0 and length > 10.0:
		_spark_timer = 0.18
		var tip_pos := to_global(Vector2(length, 0.0))
		FxParticlePool.burst(FxParticlePool.HIT_SPARK, tip_pos, "shadow", 0.85, true)

	var interval := _redraw_interval()
	if _phase >= interval:
		_phase -= interval
		queue_redraw()

func _draw() -> void:
	if length <= 1.0:
		if _tip_light != null:
			_tip_light.enabled = false
		return
	# 中心线蛇形驻波：根部稳、尾端飘（激光不是死直线，是憋着能量的电弧）
	if _pts_buf.size() != SEGS + 1:
		_pts_buf.resize(SEGS + 1)
	for i in SEGS + 1:
		var x := length * float(i) / float(SEGS)
		var wob := sin(x * 0.09 - _anim * 26.0) * 2.6 * (0.25 + 0.75 * float(i) / float(SEGS))
		_pts_buf[i] = Vector2(x, wob)

	# 三层同形叠画：外晕 / 主束 / HDR 超白核心芯（T-2.2 接 FX_HDR_SHADOW 泛光起辉）
	# 2026-10-15 视觉克制化：三层比例收细（1.0/0.5/0.18 → 0.8/0.38/0.14），
	# 多武器同屏时光束不再是最粗的常驻线；判定盒宽度与渲染器无关（FloatingWeapon 恒定 10px）
	var glow := tint
	glow.a = 0.22
	var mid := tint
	mid.a = 0.55
	var core := GameStyle.FX_HDR_SHADOW

	draw_polyline(_pts_buf, glow, beam_width * 0.8)
	draw_polyline(_pts_buf, mid, beam_width * 0.38)
	draw_polyline(_pts_buf, core, beam_width * 0.14)

	var tip := _pts_buf[SEGS]
	var pulse := 1.0 + sin(_anim * 30.0) * 0.25

	# 两端径向光晕圆（随光束缩放，消灭死硬线段感）
	# 端头圆是「粗」感主来源：0.65/0.95 → 0.5/0.62，端头糊团直径 ~32px 收到 ~20px
	var root_r := beam_width * 0.5 * pulse
	var tip_r := beam_width * 0.62 * pulse
	draw_circle(_pts_buf[0], root_r, Color(tint.r, tint.g, tint.b, 0.35))
	draw_circle(_pts_buf[0], root_r * 0.45, core)
	draw_circle(tip, tip_r, Color(tint.r, tint.g, tint.b, 0.45))
	draw_circle(tip, tip_r * 0.5, core)

	# 命中端溅射：菱晶 + 四散电丝，脉冲呼吸
	var d := 4.0 * pulse
	draw_colored_polygon(PackedVector2Array([
		tip + Vector2(d, 0.0), tip + Vector2(0.0, -d),
		tip + Vector2(-d, 0.0), tip + Vector2(0.0, d)]), core)
	for k in 4:
		var a := float(k) * TAU / 4.0 + _anim * 7.0
		var dir := Vector2(cos(a), sin(a))
		draw_line(tip + dir * d, tip + dir * (d + 5.0), mid, 1.1)

	# 命中端动态 PointLight2D 跟踪（名额在 FxBudget 登记）
	if _tip_light != null:
		_tip_light.enabled = true
		_tip_light.position = tip
		_tip_light.color = Color(tint.r, tint.g, tint.b, 0.9)

func _exit_tree() -> void:
	if _tip_light != null and is_instance_valid(_tip_light):
		_tip_light.queue_free()
		_tip_light = null
