class_name ObeliskFx
extends Node2D

## 祭坛（聚灵阵）演出节点 —— 一次性自释放演出，纯 _draw 时间轴。
## 仿 player_level_ritual.gd 范式：无贴图 / 无粒子节点 / 无光源，全走矢量绘制；
## 存活 ≤0.9s 后 queue_free，绝不常驻、不占 FxBudget 灯与发射器名额。
## 作用：把「金币注入 / 激活爆发 / 全屏冲击环 / 灵兽登场 / 熄灭余烬」这些只演一次的
## 东西从 BlessingObelisk 里拆出来，宿主只管一条 create_tween 的数值收尾，视觉全在这里。
## 2026-10-25 祭坛重设计：新增金币注入（玩家身上的灵石飞入祭坛）与全屏冲击环，
## 激活光柱加高加金幕 —— 单祭坛后预算全给这一座。

enum Mode { ACTIVATION, BEAST_ENTRANCE, SPENT_WISP, COIN_INFUSION, SHOCK_RING }

const ACTIVATION_DUR := 0.7    ## 激活爆发总时长（2026-10-25 光柱加高后由 0.55 拉长）
const BEAST_DUR := 0.32        ## 灵兽聚灵现身时长
const SPENT_DUR := 0.65        ## 熄灭余烬时长
const INFUSION_DUR := 0.45     ## 金币注入总时长（最后一枚到位即爆发，宿主据此排爆发时序）
const SHOCK_DUR := 0.5         ## 全屏冲击环时长
const HZ := 40.0               ## 演出期间重绘节流（短命节点，40Hz 足够顺滑）

## 地面环 2.5D 俯视压扁系数（与全场地面特效同款观感）
const GROUND_SQUASH := 0.62

## 金币注入几何：7 枚金铢错峰从玩家飞向晶柱（贝塞尔弧 + 拖尾 + 抵达闪）
const COIN_COUNT := 7
const COIN_STAGGER := 0.05     ## 相邻两枚的出发间隔（秒）
const COIN_FLIGHT := 0.3       ## 单枚飞行时长（秒）
const COIN_ARRIVE_R := 10.0    ## 落点（晶柱中腹，本地坐标）

## 通天光柱几何（抄 player_level_ritual 的成熟双层梯形配方，改成青玉+鎏金三幕）
const PILLAR_UP_DUR := 0.14
const PILLAR_TOTAL := 0.45
const PILLAR_BASE_W := 26.0
const PILLAR_TOP_W := 52.0
const PILLAR_CORE_BASE_W := 10.0
const PILLAR_CORE_TOP_W := 20.0
const PILLAR_GOLD_BASE_W := 34.0   ## 外层鎏金幕（比青玉幕宽一档、矮一档）
const PILLAR_GOLD_TOP_W := 66.0
const PILLAR_HEIGHT := 300.0   ## 2026-10-25 由 210 加高：单祭坛的大招要有顶天立地的架势
const PILLAR_SEGMENTS := 8

## 全屏冲击环几何：从祭坛扩散到屏幕边缘的细金白环（把「全场受击」画在脸上）
const SHOCK_MAX_R := 1400.0

## 青玉主色（与灵珑泽青同源，祭坛的冷冽仙气基调）
const JADE_FX := Color(0.45, 0.9, 1.0, 1.0)
## 鎏金供金主色（金币注入 / 金幕 / 冲击环外缘，金币语义走 GameStyle.JADE 同调）
const GOLD_FX := Color(1.0, 0.82, 0.30, 1.0)

var _mode: int = Mode.ACTIVATION
var _t: float = 0.0
var _dur: float = ACTIVATION_DUR
var _redraw_timer: float = 0.0
var _seed: float = 0.0
## 金币注入的起点偏移（玩家位置 − 祭坛位置，本地坐标画出飞行起点）
var _coin_from := Vector2.ZERO

static func play_activation(host: Node, pos: Vector2) -> void:
	_spawn(host, pos, Mode.ACTIVATION)

static func play_beast_entrance(host: Node, pos: Vector2) -> void:
	_spawn(host, pos, Mode.BEAST_ENTRANCE)

static func play_spent_wisp(host: Node, pos: Vector2) -> void:
	_spawn(host, pos, Mode.SPENT_WISP)

## 金币注入：alt_pos 处起 FX，金币从 player_pos 飞向祭坛晶柱（演出随机走 instance_id 本地种子）
static func play_coin_infusion(host: Node, altar_pos: Vector2, player_pos: Vector2) -> void:
	if host == null or not is_instance_valid(host):
		return
	var fx := ObeliskFx.new()
	fx._mode = Mode.COIN_INFUSION
	fx._coin_from = player_pos - altar_pos
	fx.z_index = 0
	host.add_child(fx)
	fx.global_position = altar_pos

static func play_shock_ring(host: Node, pos: Vector2) -> void:
	_spawn(host, pos, Mode.SHOCK_RING)

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
		Mode.COIN_INFUSION:
			_dur = INFUSION_DUR
		Mode.SHOCK_RING:
			_dur = SHOCK_DUR
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
		Mode.COIN_INFUSION:
			_draw_infusion()
		Mode.SHOCK_RING:
			_draw_shock()
		Mode.SPENT_WISP:
			_draw_spent(_t / _dur)

# ==============================================================================
# 1. 激活爆发：三重地面环 + 核心闪白 + 通天青金光柱
# ==============================================================================
func _draw_activation(p: float) -> void:
	## 1.1 地面扩散三重环（青玉外环 + 超白内环 + 鎏金大环，错峰铺开）
	_draw_ground_ring(p, 0.0, 132.0, JADE_FX)
	_draw_ground_ring(p, 0.11, 92.0, Color(GameStyle.FX_HDR_CORE, 1.0))
	_draw_ground_ring(p, 0.05, 170.0, GOLD_FX)

	## 1.2 脚下核心闪白（前 0.22s 过曝后回落）
	if _t < 0.22:
		var fp: float = _t / 0.22
		var r: float = 38.0 * (1.0 - fp * 0.45)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, GROUND_SQUASH))
		AdaptiveDraw.circle(self, Vector2.ZERO, r, Color(GameStyle.FX_HDR_CORE, 0.9 * (1.0 - fp)))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, GROUND_SQUASH))
		AdaptiveDraw.circle(self, Vector2.ZERO, r * 1.6, Color(GOLD_FX, 0.35 * (1.0 - fp)))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	## 1.3 通天光柱（青玉幕 + 鎏金幕 + 超白柱芯）
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
		# 外层鎏金幕（供金余韵：金币注入的色记忆，最宽最淡）
		var w0g: float = lerpf(PILLAR_GOLD_BASE_W, PILLAR_GOLD_TOP_W, t0)
		var w1g: float = lerpf(PILLAR_GOLD_BASE_W, PILLAR_GOLD_TOP_W, t1)
		draw_colored_polygon(
			PackedVector2Array([Vector2(-w0g, y0), Vector2(w0g, y0), Vector2(w1g, y1), Vector2(-w1g, y1)]),
			Color(GOLD_FX, fade * 0.16 * sd))
		# 中层青玉光幕
		draw_colored_polygon(
			PackedVector2Array([Vector2(-w0o, y0), Vector2(w0o, y0), Vector2(w1o, y1), Vector2(-w1o, y1)]),
			Color(0.45, 0.9, 1.0, fade * 0.42 * sd))
		# 内层超白柱芯
		draw_colored_polygon(
			PackedVector2Array([Vector2(-w0c, y0), Vector2(w0c, y0), Vector2(w1c, y1), Vector2(-w1c, y1)]),
			Color(GameStyle.FX_HDR_CORE, fade * 0.9 * sd))

# ==============================================================================
# 2. 金币注入：7 枚金铢从玩家沿贝塞尔弧错峰飞入晶柱，带拖尾与抵达闪
# ==============================================================================
func _draw_infusion() -> void:
	## 每枚金币的出发时刻：i * COIN_STAGGER；飞行 COIN_FLIGHT 秒
	for i in COIN_COUNT:
		var t0: float = float(i) * COIN_STAGGER
		var ct: float = clampf((_t - t0) / COIN_FLIGHT, 0.0, 1.0)
		if ct <= 0.0:
			continue
		## 横向错开 + 左右交替的弧顶（演出随机走 _seed，不碰玩法 RNG）
		var side: float = 1.0 if i % 2 == 0 else -1.0
		var spread: float = 0.55 + 0.45 * fposmod(_seed * (float(i) + 1.0) * 0.37, 1.0)
		var from := _coin_from + Vector2(side * (10.0 + spread * 14.0), -4.0)
		var to := COIN_ARRIVE_R * Vector2(0, -1) + Vector2(side * 2.0, 0)
		var ctrl := from.lerp(to, 0.5) + Vector2(side * 26.0 * spread, -34.0 - spread * 18.0)
		## 缓入：起手被「吸」的迟滞，临近祭坛加速
		var et: float = ct * ct
		var pos: Vector2 = from.lerp(ctrl, et).lerp(ctrl.lerp(to, et), et)
		## 拖尾：沿轨迹回采两帧，越靠后越淡越小
		for k in 2:
			var tt: float = maxf(et - 0.06 * float(k + 1), 0.0)
			var tpos: Vector2 = from.lerp(ctrl, tt).lerp(ctrl.lerp(to, tt), tt)
			AdaptiveDraw.circle(self, tpos, 2.6 - float(k) * 0.8, Color(GOLD_FX, 0.35 - 0.12 * float(k)))
		## 金铢本体：鎏金核 + 超白高光
		AdaptiveDraw.circle(self, pos, 3.2, Color(GOLD_FX, 0.95))
		AdaptiveDraw.circle(self, pos + Vector2(-0.8, -0.8), 1.3, Color(GameStyle.FX_HDR_CORE, 0.95))
		## 抵达闪：落进晶柱的一瞬一圈小金环
		if ct >= 1.0:
			var since: float = _t - t0 - COIN_FLIGHT
			if since < 0.12:
				var q: float = since / 0.12
				draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, GROUND_SQUASH))
				draw_arc(to, 3.0 + q * 14.0, 0.0, TAU, 20, Color(GOLD_FX, 0.8 * (1.0 - q)), 2.0, true)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ==============================================================================
# 3. 全屏冲击环：细金白环从祭坛扩散到屏幕边缘，宣告「全场受击」
# ==============================================================================
func _draw_shock() -> void:
	var p: float = _t / _dur
	var e: float = 1.0 - pow(1.0 - p, 2.6)   # ease-out：起手猛冲、远端缓收
	var r: float = lerpf(70.0, SHOCK_MAX_R, e)
	var a: float = (1.0 - p) * 0.85
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, GROUND_SQUASH))
	# 外缘鎏金 + 内芯超白双描
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 96, Color(GOLD_FX, a * 0.7), 3.0, true)
	draw_arc(Vector2.ZERO, r - 4.0, 0.0, TAU, 96, Color(GameStyle.FX_HDR_CORE, a), 2.0, true)
	# 尾随青玉第二环（错峰 0.08s），呼应阵法底色
	var q: float = clampf((_t - 0.08) / _dur, 0.0, 1.0)
	if q > 0.0 and q < 1.0:
		var r2: float = lerpf(70.0, SHOCK_MAX_R, 1.0 - pow(1.0 - q, 2.6))
		draw_arc(Vector2.ZERO, r2, 0.0, TAU, 96, Color(JADE_FX, (1.0 - q) * 0.45), 2.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ==============================================================================
# 4. 灵兽登场：青玉聚灵漩涡 + 扩散环
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
# 5. 熄灭余烬：几缕冷灰蓝灵屑上升淡出，给「余温散尽」一点回味
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
