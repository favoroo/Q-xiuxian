class_name EnemyBoltTrail
extends Node2D

## 敌方弹丸世界坐标拖尾（2026-10-19）：为剑气/大弹这类「需要读出飞行轨迹」的
## 敌方弹丸补一条渐隐弧线，让玩家能预判弧弹/螺旋弹的来路。
##
## 为什么只给部分弹丸挂：
##  - 普通小火球数量大（Boss 环弹/连射一次几十颗），每颗挂拖尾会把 Line2D 图元量顶上去。
##  - 剑气（sword_style）与 Boss 大弹（scale_factor > 1.2）数量少、威胁高、轨迹曲率大，
##    是最需要轨迹读数的两类；普通火球不挂，守同屏图元预算。
##  - 拥挤档（FxBudget.crowded）整体不启用，进一步让位给满屏敌人。
##
## 范式照 ProjectileTrail：top_level 脱离弹体变换、环形缓冲零分配、
## 双层 Line2D（宽低透辉光 + 窄亮核）、渐隐走常驻 Gradient。
## 与 ProjectileTrail 的差别：本节点用 show_behind_parent 压在弹体自身 _draw 之下，
## 不依赖 move_child 抢兄弟序（EnemyBolt 是纯 _draw 弹体，子节点默认画在父之上）。

const SAMPLE_INTERVAL := 0.033      ## 低档采样节流
const SAMPLE_INTERVAL_HIGH := 0.014 ## 流畅档采样节流
const MAX_POINTS_LOW := 7           ## 低档历史点数
const MAX_POINTS_HIGH := 12         ## 流畅档历史点数
const RING_CAP := MAX_POINTS_HIGH   ## 环形容量按高档取
const MIN_STEP_SQ := 20.0           ## 相邻点平方距下限（≈4.5px），防贴脸零长线段

const GLOW_WIDTH := 4.6
const CORE_WIDTH := 1.5
const GLOW_ALPHA_HEAD := 0.20
const CORE_ALPHA_HEAD := 0.80

var active: bool = false

var _ring := PackedVector2Array()
var _head: int = 0
var _count: int = 0
var _draw_buf := PackedVector2Array()
var _acc: float = 0.0
var _line_glow: Line2D = null
var _line_core: Line2D = null
var _color := Color(1.0, 1.0, 1.0)
var _grad_glow: Gradient = null
var _grad_core: Gradient = null

func _ready() -> void:
	top_level = true
	position = Vector2.ZERO
	# 压在弹体自身 _draw 之下：拖尾是「尾迹」，不该盖住弹体本体
	show_behind_parent = true
	visible = false
	_ring.resize(RING_CAP)
	_draw_buf.resize(RING_CAP)
	_build_lines()

## 配色下发（弹体 rim 色）：颜色未变短路，变了只就地覆写常驻 Gradient
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

func _fill_gradient(grad: Gradient, head_alpha: float, hdr_boost: float) -> void:
	var r := _color.r * hdr_boost
	var g := _color.g * hdr_boost
	var b := _color.b * hdr_boost
	grad.colors = PackedColorArray([
		Color(r, g, b, 0.0),
		Color(r, g, b, head_alpha),
	])

func set_active(on: bool) -> void:
	active = on
	if not on:
		reset()

## 出膛起笔：清空上一发历史后从枪口位置落第一个点
func seed(pos: Vector2) -> void:
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

## 宿主物理帧调用（弹丸休眠时宿主 _physics_process 停发，本节点无需自计时）
func sample(pos: Vector2, delta: float) -> void:
	if not active:
		return
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

## 回池清史：残留弧线从上一发死亡点连到下一发枪口就是「池体占拍」事故（AGENTS 坑 13）
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
	# 方关节：ROUND joint 会在每个拐点展开三角扇，弧弹多拐点下是图元虚高元凶
	line.joint_mode = Line2D.LINE_JOINT_BEVEL
	line.begin_cap_mode = Line2D.LINE_CAP_NONE
	line.end_cap_mode = Line2D.LINE_CAP_NONE
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.1))
	curve.add_point(Vector2(1.0, 1.0))
	line.width_curve = curve
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
	_draw_buf.resize(_count)
	var start := (_head - _count + RING_CAP) % RING_CAP
	for i in range(_count):
		_draw_buf[i] = _ring[(start + i) % RING_CAP]
	_line_glow.points = _draw_buf
	_line_core.points = _draw_buf
