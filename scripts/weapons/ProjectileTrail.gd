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
## 2026-10-15 视觉克制化：光晕 8.0→6.5、亮核 2.4→2.1、头部透明度 0.30→0.24，
## 弹丸拖尾是仅次于光束的常驻粗线，多弹齐射时不再糊成一片。
## 2026-10-16 攻击粒子减量：光晕 6.5→5.2、亮核 2.1→1.8——点数与记忆长度不动，
## 弧线形状不变只收宽度，多武器齐射时拖尾不再连成一片辉光海
const GLOW_WIDTH := 5.2
const CORE_WIDTH := 1.8
const GLOW_ALPHA_HEAD := 0.24
const CORE_ALPHA_HEAD := 0.85

## 历史点存环形缓冲：sample() 满员后原地覆写最老点（弹丸池 64 发 × 60Hz 齐射时
## 原先每拍 slice() 新建 PackedVector2Array ≈ 1200 次分配/秒，是弹丸路径最大持续分配源）。
## _redraw 时才按时间序展开进复用的 _draw_buf（Line2D.points 需要连续数组，仅这一次赋值拷贝）。
const RING_CAP := MAX_POINTS_HIGH  ## 环形容量按高档取（低档只用前 MAX_POINTS_LOW 个）

var _ring := PackedVector2Array()
var _head: int = 0        ## 下一个写入槽（即最老点）
var _count: int = 0
var _draw_buf := PackedVector2Array()
var _acc: float = 0.0
var _line_glow: Line2D = null
var _line_core: Line2D = null
var _color := Color(0.95, 0.90, 0.72)
## 两条 Line2D 共用的常驻 Gradient（_build_lines 建一次，configure 只就地改 colors）：
## 池化弹丸逐发 activate 都会 configure，原先每次 new 2 个 Gradient 是弹丸侧最大持续分配源
var _grad_glow: Gradient = null
var _grad_core: Gradient = null

func _ready() -> void:
	# top_level + position 恒为原点 ⇒ 本地坐标 == 世界坐标，历史点直接存全局位置。
	# 画序靠宿主 move_child 压到兄弟首位（z_index -1 会沉到地面瓦片之下，不可用）。
	top_level = true
	position = Vector2.ZERO
	visible = false
	_ring.resize(RING_CAP)
	_draw_buf.resize(RING_CAP)
	_build_lines()

## 配色下发（与弹体异常色温同源）：BladeProjectile.activate 逐发调用。
## 颜色未变直接短路；变了也只就地覆写常驻 Gradient 的 colors（照 WeaponArcRenderer
## 「不重建只下发」范式），不再每次 new 2 个 Gradient + PackedColorArray。
func configure(color: Color) -> void:
	if color == _color:
		return
	_color = color
	_apply_gradients()

func _apply_gradients() -> void:
	if _grad_glow == null:
		return
	_fill_gradient(_grad_glow, GLOW_ALPHA_HEAD, 1.0)
	_fill_gradient(_grad_core, CORE_ALPHA_HEAD, 1.6)

## 就地填充常驻 Gradient 的 colors（两色端点：尾端全透 → 头部带 HDR 提亮的主题色）
func _fill_gradient(grad: Gradient, head_alpha: float, hdr_boost: float = 1.0) -> void:
	var r := _color.r * hdr_boost
	var g := _color.g * hdr_boost
	var b := _color.b * hdr_boost
	grad.colors = PackedColorArray([
		Color(r, g, b, 0.0),
		Color(r, g, b, head_alpha),
	])

## 出膛起笔：清空上一发历史后从枪口位置落第一个点
func seed_point(pos: Vector2) -> void:
	reset()
	_ring[0] = pos
	_head = 1 % RING_CAP
	_count = 1
	visible = true
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
	if _count > 0:
		var last := _ring[(_head - 1 + RING_CAP) % RING_CAP]
		if last.distance_squared_to(pos) < MIN_STEP_SQ:
			return
	_ring[_head] = pos
	_head = (_head + 1) % RING_CAP
	if _count < _max_points():
		_count += 1
	_redraw()

## 回池清史：残留弧线从上一发死亡点连到下一发枪口就是「池体占拍」的同型事故（AGENTS 坑 13）
func reset() -> void:
	_head = 0
	_count = 0
	_acc = 0.0
	visible = false
	_redraw()

func _build_lines() -> void:
	_grad_glow = Gradient.new()
	_grad_core = Gradient.new()
	_line_glow = _make_line(GLOW_WIDTH, _grad_glow)
	_line_core = _make_line(CORE_WIDTH, _grad_core)
	_apply_gradients()

func _make_line(width: float, grad: Gradient) -> Line2D:
	var line := Line2D.new()
	line.width = width
	# 关节/bevel 不用 ROUND：ROUND joint 在每个拐点展开成扇形三角扇（顶点数 × 段数），
	# 弹幕 29 发 × 16 点 × 双线时是图元虚高的隐形大头（手机端实测 23.4k）。
	# 拖尾本来就有 gradient 渐隐 + width_curve 收尖，方关节的接缝在渐隐下不可见。
	line.joint_mode = Line2D.LINE_JOINT_BEVEL
	line.begin_cap_mode = Line2D.LINE_CAP_NONE
	line.end_cap_mode = Line2D.LINE_CAP_NONE
	# 尾端收到 10% 宽、头端全宽：与渐隐同向，弧线末端自然消失不留圆头
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.1))
	curve.add_point(Vector2(1.0, 1.0))
	line.width_curve = curve
	# Gradient 由调用方传入并常驻成员持有（_grad_glow/_grad_core），
	# configure 变色时就地覆写 colors，不再每次 new
	line.gradient = grad
	add_child(line)
	return line

func _redraw() -> void:
	if _line_glow == null or _line_core == null:
		return
	if _count == 0:
		visible = false
		return
	visible = true
	# 环形缓冲按时间序展开：最老点在 (_head - _count)（_head 是下一写入槽），
	# 低档 _count 封顶 9 < RING_CAP 16 时 _head 仍在全环上游走，不能拿 _head 当起点。
	# resize 缩容不释放底层内存，_count 单调涨到上限后稳定，不产生每次重绘的分配。
	_draw_buf.resize(_count)
	var start := (_head - _count + RING_CAP) % RING_CAP
	for i in range(_count):
		_draw_buf[i] = _ring[(start + i) % RING_CAP]
	_line_glow.points = _draw_buf
	_line_core.points = _draw_buf
