extends Node2D

## ★4 极境「太虚霓虹」常驻气场（2026-10-25）：
## 极境武器器身之外的一圈缓慢旋转的双色虚弧 + 呼吸外环，待机时也一眼认出「这把是极境」。
##
## 为什么不做成第三套描边：器身描边（BrutalistCommon 的 NEON_CYAN_HDR / NEON_VIOLET 双层墨描）
## 只在器形轮廓上，小件（御灵/匕首/针）几乎看不出来；气场是绕本体的独立几何，与器形大小无关。
##
## 性能纪律（对齐 ChestBurstFx / obelisk_fx 的纯 _draw 范式）：
## - 零贴图、零粒子、零动态灯 ⇒ 不占 FxBudget 的灯与发射器名额；
## - 重绘走 VisualRate 双档（60fps 档 40Hz / 30fps 档 20Hz）并按 instance_id 错相，
##   同场多把极境武器不会同帧一起重绘（每把武器每 3 帧才画一次）；
## - 顶点写成员缓冲复用，_draw 里不 new PackedVector2Array。
##
## 按路径 preload 使用，不加 class_name（避免新增全局类名触发编辑器扫描串行点）。

const CYAN := Color(0.45, 1.95, 2.55)      ## 电光青（HDR）：外弧主色
const VIOLET := Color(0.78, 0.38, 1.00)    ## 太虚紫：内弧副色

## 弧几何（屏上像素，相对武器本体中心）
const ARC_RADIUS := 26.0        ## 虚弧半径
const ARC_SPAN_DEG := 54.0      ## 单段弧张角
const ARC_SEGS := 10            ## 单段弧折线点数（自适应段数由 AdaptiveDraw 兜底）
const SPIN_SPEED := 0.9         ## 双弧旋转角速度（弧度/秒，一正一反）
const BREATH_HZ := 0.55         ## 外环呼吸频率
const BREATH_AMPLITUDE := 0.18  ## 呼吸幅度（半径 ±18%）
const FADE_IN := 0.22           ## 升到★4 时的淡入时长

## 重绘节流：与 BeamRenderer / FlameConeRenderer 同一双档口径
const HZ_LOW := 20.0
const HZ_HIGH := 40.0

var _anim: float = 0.0
var _phase: float = 0.0
var _fade: float = 0.0           ## 0→1 淡入（升星当拍从 0 起）
var _arc_buf: PackedVector2Array = []   ## 单段弧顶点缓冲（复用）


func _ready() -> void:
	z_index = 0
	# 静置在器身之下（与 aura_sprite 同一层规则：z=-1 会掉进不透明地砖底下）
	if get_parent() is Node:
		get_parent().move_child(self, 0)
	_phase = fposmod(float(get_instance_id() % 97) * 0.001, _redraw_interval())
	set_process(true)


func _redraw_interval() -> float:
	return VisualRate.interval(HZ_HIGH, HZ_LOW)


func _process(delta: float) -> void:
	_anim += delta
	if _fade < 1.0:
		_fade = minf(1.0, _fade + delta / FADE_IN)
	_phase += delta
	if _phase >= _redraw_interval():
		_phase -= _redraw_interval()
		queue_redraw()


func _draw() -> void:
	var a: float = _fade
	if a <= 0.0:
		return
	var breath: float = 1.0 + sin(_anim * TAU * BREATH_HZ) * BREATH_AMPLITUDE
	var alpha_scale: float = 0.55 + 0.45 * sin(_anim * TAU * BREATH_HZ + PI * 0.5)

	# 外环：一层细青环 + 一层更淡的紫环（呼吸式明暗，不遮挡器身）
	var r_out: float = ARC_RADIUS * breath
	_draw_arc_ring(r_out, CYAN, 0.55 * a * alpha_scale, 1.4)
	_draw_arc_ring(r_out + 3.0, VIOLET, 0.34 * a * alpha_scale, 1.0)

	# 双虚弧反向旋转：一青一紫，各两段对位（读作「极境的环」而非普通光晕）
	_draw_spin_arcs(_anim * SPIN_SPEED, CYAN, 0.85 * a, 1.8, 2)
	_draw_spin_arcs(-_anim * SPIN_SPEED * 0.7, VIOLET, 0.65 * a, 1.4, 2)


## 整圈细环（呼吸明暗）：用 AdaptiveDraw 控段数，避免满圈 64 段图元虚高
func _draw_arc_ring(radius: float, col: Color, alpha: float, width: float) -> void:
	if alpha <= 0.004:
		return
	var c := Color(col.r, col.g, col.b, alpha)
	AdaptiveDraw.arc(self, Vector2.ZERO, radius, 0.0, TAU, c, width, true)


## 旋转虚弧：count 段均分整圈，每段 ARC_SPAN_DEG
func _draw_spin_arcs(base_angle: float, col: Color, alpha: float, width: float, count: int) -> void:
	if alpha <= 0.004:
		return
	var span: float = deg_to_rad(ARC_SPAN_DEG)
	var c := Color(col.r, col.g, col.b, alpha)
	for i in count:
		var start: float = base_angle + TAU * float(i) / float(count)
		_arc_points(start, start + span)
		draw_polyline(_arc_buf, c, width, true)


## 单段弧顶点写进成员缓冲（_draw 内零分配）
func _arc_points(from_ang: float, to_ang: float) -> void:
	if _arc_buf.size() != ARC_SEGS + 1:
		_arc_buf.resize(ARC_SEGS + 1)
	for i in ARC_SEGS + 1:
		var t: float = float(i) / float(ARC_SEGS)
		var ang: float = lerpf(from_ang, to_ang, t)
		_arc_buf[i] = Vector2(cos(ang), sin(ang)) * ARC_RADIUS
