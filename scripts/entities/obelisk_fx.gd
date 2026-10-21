class_name ObeliskFx
extends Node2D

## 祭坛（聚灵阵）演出节点 —— 三种一次性自释放演出，纯 _draw 时间轴。
## 仿 player_level_ritual.gd 范式：无贴图 / 无粒子节点 / 无光源，全走矢量绘制；
## 存活 ≤0.65s 后 queue_free，绝不常驻、不占 FxBudget 灯与发射器名额。
## 作用：把「激活爆发 / 灵兽登场 / 熄灭余烬」这些只演一次的东西从 BlessingObelisk
## 里拆出来，宿主只管一条 create_tween 的数值收尾，视觉全在这里。

enum Mode { ACTIVATION, BEAST_ENTRANCE, SPENT_WISP }

const ACTIVATION_DUR := 0.55   ## 激活爆发总时长
const BEAST_DUR := 0.32        ## 灵兽聚灵现身时长
const SPENT_DUR := 0.65        ## 熄灭余烬时长
const HZ := 40.0               ## 演出期间重绘节流（短命节点，40Hz 足够顺滑）

## 地面环 2.5D 俯视压扁系数（与全场地面特效同款观感）
const GROUND_SQUASH := 0.62

## 通天光柱几何（抄 player_level_ritual 的成熟双层梯形配方，改成青玉色系）
const PILLAR_UP_DUR := 0.12
const PILLAR_TOTAL := 0.34
const PILLAR_BASE_W := 26.0
const PILLAR_TOP_W := 52.0
const PILLAR_CORE_BASE_W := 10.0
const PILLAR_CORE_TOP_W := 20.0
const PILLAR_HEIGHT := 210.0
const PILLAR_SEGMENTS := 8

## 青玉主色（与灵珑泽青同源，祭坛的冷冽仙气基调）
const JADE_FX := Color(0.45, 0.9, 1.0, 1.0)

var _mode: int = Mode.ACTIVATION
var _t: float = 0.0
var _dur: float = ACTIVATION_DUR
var _redraw_timer: float = 0.0
var _seed: float = 0.0

static func play_activation(host: Node, pos: Vector2) -> void:
	_spawn(host, pos, Mode.ACTIVATION)

static func play_beast_entrance(host: Node, pos: Vector2) -> void:
	_spawn(host, pos, Mode.BEAST_ENTRANCE)

static func play_spent_wisp(host: Node, pos: Vector2) -> void:
	_spawn(host, pos, Mode.SPENT_WISP)

static func _spawn(host: Node, pos: Vector2, mode: int) -> void:
	if host == null or not is_instance_valid(host):
		return
	var fx := ObeliskFx.new()
	fx._mode = mode
	fx.z_index = 0
	host.add_child(fx)
	fx.global_position = pos

func _ready() -> void:
	_seed = fposmod(float(get_instance_id() % 83) * 0.021, TAU)
	match _mode:
		Mode.ACTIVATION:
			_dur = ACTIVATION_DUR
		Mode.BEAST_ENTRANCE:
			_dur = BEAST_DUR
		_:
			_dur = SPENT_DUR
	queue_redraw()

func _process(delta: float) -> void:
	_t += delta
	_redraw_timer -= delta
	if _redraw_timer <= 0.0:
		_redraw_timer = 1.0 / HZ
		queue_redraw()
	if _t >= _dur:
		queue_free()

func _draw() -> void:
	match _mode:
		Mode.ACTIVATION:
			_draw_activation(_t / _dur)
		Mode.BEAST_ENTRANCE:
			_draw_beast(_t / _dur)
		Mode.SPENT_WISP:
			_draw_spent(_t / _dur)

# ==============================================================================
# 1. 激活爆发：地面双环扩散 + 核心闪白 + 通天青玉光柱
# ==============================================================================
func _draw_activation(p: float) -> void:
	## 1.1 地面扩散双环（青玉外环 + 超白内环，错峰）
	_draw_ground_ring(p, 0.0, 132.0, JADE_FX)
	_draw_ground_ring(p, 0.11, 92.0, Color(GameStyle.FX_HDR_CORE, 1.0))

	## 1.2 脚下核心闪白（前 0.18s 过曝后回落）
	if _t < 0.18:
		var fp: float = _t / 0.18
		var r: float = 32.0 * (1.0 - fp * 0.45)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, GROUND_SQUASH))
		AdaptiveDraw.circle(self, Vector2.ZERO, r, Color(GameStyle.FX_HDR_CORE, 0.85 * (1.0 - fp)))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	## 1.3 通天光柱
	_draw_pillar()

func _draw_ground_ring(p: float, delay: float, max_r: float, col: Color) -> void:
	var span := 0.6
	var q := clampf((p * _dur - delay) / span, 0.0, 1.0)
	if q <= 0.0 or q >= 1.0:
		return
	var e: float = 1.0 - pow(1.0 - q, 2.4)  # ease-out：起手猛、尾段缓
	var r: float = lerpf(20.0, max_r, e)
	var a: float = (1.0 - q) * 0.9 * col.a
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, GROUND_SQUASH))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(col, a), 3.0 * (1.0 - q * 0.5), true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_pillar() -> void:
	var p: float = clampf(_t / PILLAR_TOTAL, 0.0, 1.0)
	if p >= 1.0:
		return
	var up_norm: float = PILLAR_UP_DUR / PILLAR_TOTAL
	var h_ratio: float
	if p < up_norm:
		var up: float = p / up_norm
		h_ratio = 1.0 - pow(1.0 - up, 2.2)
	else:
		h_ratio = 1.0
	var fade: float
	if p < up_norm:
		fade = 1.0
	else:
		var fp: float = (p - up_norm) / (1.0 - up_norm)
		fade = 1.0 - pow(fp, 1.5)
	var h: float = PILLAR_HEIGHT * h_ratio
	if h <= 2.0 or fade <= 0.001:
		return

	var seg_h: float = h / float(PILLAR_SEGMENTS)
	var w_base: float = PILLAR_BASE_W * (1.0 - 0.18 * p)
	var w_top: float = PILLAR_TOP_W
	var c_base: float = PILLAR_CORE_BASE_W * (1.0 - 0.18 * p)
	var c_top: float = PILLAR_CORE_TOP_W

	for s in PILLAR_SEGMENTS:
		var t0: float = float(s) / float(PILLAR_SEGMENTS)
		var t1: float = float(s + 1) / float(PILLAR_SEGMENTS)
		var y0: float = -seg_h * float(s)
		var y1: float = -seg_h * float(s + 1)
		var w0o: float = lerpf(w_base, w_top, t0)
		var w1o: float = lerpf(w_base, w_top, t1)
		var w0c: float = lerpf(c_base, c_top, t0)
		var w1c: float = lerpf(c_base, c_top, t1)
		var d0: float = pow(1.0 - t0, 1.35)
		var d1: float = pow(1.0 - t1, 1.35)
		var sd: float = (d0 + d1) * 0.5
		# 外层青玉光幕
		draw_colored_polygon(
			PackedVector2Array([Vector2(-w0o, y0), Vector2(w0o, y0), Vector2(w1o, y1), Vector2(-w1o, y1)]),
			Color(0.45, 0.9, 1.0, fade * 0.42 * sd))
		# 内层超白柱芯
		draw_colored_polygon(
			PackedVector2Array([Vector2(-w0c, y0), Vector2(w0c, y0), Vector2(w1c, y1), Vector2(-w1c, y1)]),
			Color(GameStyle.FX_HDR_CORE, fade * 0.9 * sd))

# ==============================================================================
# 2. 灵兽登场：青玉聚灵漩涡 + 扩散环
# ==============================================================================
func _draw_beast(p: float) -> void:
	var converge: float = clampf(p / 0.7, 0.0, 1.0)
	var fade: float = 1.0 - clampf((p - 0.55) / 0.45, 0.0, 1.0)

	## 2.1 三条螺旋臂向心收束（灵光点点，越近越小越亮）
	for arm in 3:
		var arm_ang: float = _seed + float(arm) * TAU / 3.0 + p * 6.0
		for d in 6:
			var dp: float = clampf(converge * 1.2 - float(d) * 0.06, 0.0, 1.0)
			if dp <= 0.0:
				continue
			var r: float = lerpf(46.0, 3.0, dp)
			var ang: float = arm_ang + float(d) * 0.22
			var pos := Vector2(cos(ang) * r, sin(ang) * r * 0.6)
			var a: float = fade * (0.85 - 0.12 * float(d)) * (1.0 - dp * 0.4)
			var sz: float = 2.4 - 1.0 * dp
			AdaptiveDraw.circle(self, pos, sz, Color(0.58, 0.95, 0.98, a))
			if dp > 0.4:
				AdaptiveDraw.circle(self, pos, sz * 0.5, Color(GameStyle.FX_HDR_CORE, a * 0.9))

	## 2.2 收束完成时的地面扩散环
	var q: float = clampf((p - 0.35) / 0.65, 0.0, 1.0)
	if q > 0.0 and q < 1.0:
		var r: float = lerpf(10.0, 54.0, 1.0 - pow(1.0 - q, 2.2))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, GROUND_SQUASH))
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(0.58, 0.95, 0.98, (1.0 - q) * 0.8), 2.5, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ==============================================================================
# 3. 熄灭余烬：几缕冷灰蓝灵屑上升淡出，给「余温散尽」一点回味
# ==============================================================================
func _draw_spent(p: float) -> void:
	for i in 7:
		var ph: float = fposmod(p + float(i) * 0.137, 1.0)
		var ang: float = _seed + float(i) * 1.7
		var base_r: float = 8.0 + float(i % 3) * 6.0
		var pos := Vector2(cos(ang) * base_r * (1.0 - ph * 0.3), -ph * 46.0)
		var a: float = (1.0 - ph) * 0.7
		var sz: float = 2.6 * (1.0 - ph * 0.5)
		AdaptiveDraw.circle(self, pos, sz, Color(0.55, 0.66, 0.78, a * 0.55))
		AdaptiveDraw.circle(self, pos, sz * 0.45, Color(0.85, 0.9, 1.0, a))
