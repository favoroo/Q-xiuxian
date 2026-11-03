class_name BlinkRift
extends Node2D

## 瞬移落点符环（2026-11-03 瞬移可读性专项；同日二次强化：Boss 档三阶段演出）。
##
## 旧链路是 `global_position = 目标点` 一帧硬切：旧位残影只能表达「它刚才在这」，
## 不能预告「它要去哪」。本组件在起手帧把落点亮在地面，符环从外向内收拢、填满即落地，
## 给玩家一段可读、可走出的反应窗。
##
## 三档模式（同一套节点池，靠 mode 切画法）：
##   DEST    落点预告：外环收拢 + 内环反转 + 刻度；Boss 档追加目标十字、8 向阵纹、
##           从天而降的落顶光柱 —— 满屏弹幕里也能一眼找到「它要落到这」。
##   ORIGIN  起手吸积（Boss 档）：本体脚下的塌缩环 + 内旋吸积纹 + 拔升光柱，
##           读「本尊正在被抽离」，与落点符环一头一尾成对。
##   ARRIVAL 落地爆闪（Boss 档）：双环外扩 + 光柱塌落 + 八向残光，读「它到了」。
##
## 纪律：
##   - 只画落点，不参与伤害判定、不参与索敌；半径是纯表现读数，不是命中半径。
##   - 池化消灭节点 churn：影魅/剑煞同屏可能同时闪现，逐次 new + queue_free 是 GC 尖峰源。
##   - 落点由持有者锁定（起手帧算一次），本组件不追玩家 —— 画哪落哪，躲得掉才算读招。
##   - 取色仍由调用方给（Boss 主题色 / GameStyle.BAD），不在本组件里散落硬编码。

enum Mode {
	DEST,     ## 落点预告（默认，小怪/精英/魔君共用）
	ORIGIN,   ## 起手吸积（Boss 档，画在本体脚下）
	ARRIVAL,  ## 落地爆闪（Boss 档，画在落点）
}

const POOL_CAP := 24                 ## 同屏符环池上限（Boss 同时至多 1 组，小怪闪现留余量）
const REDRAW_INTERVAL := 0.033       ## 30Hz 重绘：小怪前摇 0.3~0.4s，30Hz 足够读出收拢过程
const REDRAW_INTERVAL_HEAVY := 0.016 ## Boss 档 60Hz：光柱/高频脉冲需要连续帧才不跳
const LIFETIME_PAD := 0.06           ## 到期后多留一瞬，与落地冲击环重叠，避免「圈先没、人后到」

const RADIUS_NORMAL := 28.0          ## 普通小怪档（影魅）
const RADIUS_ELITE := 36.0           ## 精英档（剑煞变异）
const RADIUS_BOSS := 62.0            ## 魔君档（原 48：Boss 本体 scale 1.7、半身约 48px，
                                     ## 符环要能圈住整个身形才读得出「落点包住它」）
const HEAVY_TIER_MIN := RADIUS_BOSS - 0.1 ## 档位判定：达到魔君档即启用 Boss 强化画法

var radius: float = RADIUS_NORMAL
var progress: float = 0.0            ## 0→1，由本组件按 _time_left 自驱；1 = 落地时刻（PAD 内保持满环）
var color: Color = GameStyle.BAD
var mode: int = Mode.DEST
var heavy: bool = false              ## Boss 强化画法（半径档位自动判定）

var _time_left: float = 0.0
var _duration: float = 0.3
var _clock: float = 0.0
var _redraw_timer: float = 0.0
var _redraw_interval: float = REDRAW_INTERVAL
var _pooled: bool = false

static var _pool: Array[BlinkRift] = []
static var active_count: int = 0
static var created_count: int = 0
static var reused_count: int = 0

## 取一只符环（落点预告档，兼容旧调用点）：出池复位 → 落点/时长/档位就位 → 入树。
## 字段必须在 add_child 前写好（_ready 只跑一次，复用不会重跑）。
static func acquire(parent: Node, pos: Vector2, duration: float, col: Color,
		rad: float = RADIUS_NORMAL) -> BlinkRift:
	return acquire_ex(parent, pos, duration, col, rad, Mode.DEST)

## 带模式的取用入口：Boss 起手吸积 / 落地爆闪走这里，池子仍是同一份。
static func acquire_ex(parent: Node, pos: Vector2, duration: float, col: Color,
		rad: float, md: int) -> BlinkRift:
	if parent == null:
		return null
	var r: BlinkRift = null
	while not _pool.is_empty():
		var cand: BlinkRift = _pool.pop_back()
		if is_instance_valid(cand):
			r = cand
			reused_count += 1
			break
	if r == null:
		r = BlinkRift.new()
		created_count += 1
	r._reset(pos, duration, col, rad, md)
	parent.add_child(r)
	return r

func _reset(pos: Vector2, duration: float, col: Color, rad: float, md: int) -> void:
	_pooled = false
	_duration = maxf(duration, 0.001)
	_time_left = _duration + LIFETIME_PAD
	radius = maxf(rad, 1.0)
	color = col
	mode = md
	heavy = radius >= HEAVY_TIER_MIN
	_redraw_interval = REDRAW_INTERVAL_HEAVY if heavy else REDRAW_INTERVAL
	progress = 0.0
	_clock = 0.0
	_redraw_timer = 0.0
	global_position = pos
	visible = true
	set_process(true)
	queue_redraw()

## 外部取消（宿主伏诛/回合末消散/定身打断）：立即回池，不留无主符环。
func cancel() -> void:
	_release()

func _release() -> void:
	if _pooled:
		return
	_pooled = true
	set_process(false)
	visible = false
	if get_parent() != null:
		get_parent().remove_child(self)
	if _pool.size() < POOL_CAP:
		_pool.append(self)
	else:
		queue_free()

static func clear_pool() -> void:
	for r in _pool:
		if is_instance_valid(r):
			r.free()
	_pool.clear()
	created_count = 0
	reused_count = 0

func _enter_tree() -> void:
	active_count += 1

func _exit_tree() -> void:
	active_count -= 1

func _process(delta: float) -> void:
	if GameManager.is_game_over:
		_release()
		return
	_clock += delta
	_time_left -= delta
	# 进度按「前摇时长」归一，LIFETIME_PAD 只用来兜住落地那一拍不提前回池：
	# 用 _time_left 直接除会让落地时只填到 duration/(duration+PAD)（0.3s 档约 83%），
	# 符环还没收满就被宿主的落地回调取消 —— 玩家看到的是圈缺一角人已经出来了。
	progress = clampf(1.0 - maxf(_time_left - LIFETIME_PAD, 0.0) / _duration, 0.0, 1.0)
	_redraw_timer -= delta
	if _redraw_timer <= 0.0:
		_redraw_timer = _redraw_interval
		queue_redraw()
	if _time_left <= 0.0:
		_release()

func _draw() -> void:
	BatchDraw.flush(self)
	match mode:
		Mode.ORIGIN:
			_draw_origin()
		Mode.ARRIVAL:
			_draw_arrival()
		_:
			_draw_dest()
	BatchDraw.flush(self)

# ---------------- 落点预告 ----------------

func _draw_dest() -> void:
	var t := clampf(progress, 0.0, 1.0)
	var c := color
	var pulse := 0.86 + 0.14 * sin(_clock * 17.0)
	# 地面暗底：把落点从地形上「压」出来
	BatchDraw.native_circle(self, Vector2.ZERO, radius * 0.78, Color(0.05, 0.03, 0.06, 0.42))
	# Boss 档：目标十字（横竖长线探出符环，读「锁定」；先画，压在环下）
	if heavy:
		var cross_len := radius * 1.9
		var cross_a := (0.10 + 0.20 * t) * pulse
		BatchDraw.native_line(self, Vector2(-cross_len, 0.0), Vector2(cross_len, 0.0),
			Color(c.r, c.g, c.b, cross_a), 1.2)
		BatchDraw.native_line(self, Vector2(0.0, -cross_len * 0.72), Vector2(0.0, cross_len * 0.72),
			Color(c.r, c.g, c.b, cross_a), 1.2)
	# 落顶天光：Boss 档从上方压下来的光柱，随进度变亮变宽（「有东西要从这出来」）
	if heavy and t > 0.22:
		var k: float = clampf((t - 0.22) / 0.78, 0.0, 1.0)
		_draw_column(Color(c.r, c.g, c.b, 0.06 + 0.18 * k), 0.85 + 0.35 * k, k, true)
	# 外环：从外向内收拢，填满 = 落地。外沿给一圈描边保证贴地可读
	var ring_r := lerpf(radius * 1.58, radius, ease(t, 0.38))
	var ring_a := (0.28 + 0.58 * t) * pulse
	BatchDraw.native_arc(self, Vector2.ZERO, ring_r, 0.0, TAU, 40,
		Color(c.r, c.g, c.b, ring_a), 1.8 + 2.6 * t, true)
	# Boss 档：外圈警示环反向自转（大圆 + 断口，和伤害圈区分开）
	if heavy:
		var warn_r := radius * (1.42 - 0.10 * t)
		for i in range(4):
			var a0 := -_clock * 1.4 + float(i) * TAU / 4.0
			BatchDraw.native_arc(self, Vector2.ZERO, warn_r, a0, a0 + TAU * 0.16, 12,
				Color(c.r, c.g, c.b, (0.22 + 0.30 * t) * pulse), 2.2, true)
	# 内环反向自转：读「空间在收束」，与外环单向收缩区分开
	var inner_r := lerpf(radius * 0.92, radius * 0.34, t)
	BatchDraw.native_arc(self, Vector2.ZERO, inner_r, 0.0, TAU, 28,
		Color(c.r, c.g, c.b, ring_a * 0.55), 1.2, true)
	# 刻度（俯视压扁）：让符环带「阵纹」身份，不与圆形伤害圈混读
	var ticks := 8 if heavy else 4
	for i in range(ticks):
		var ang := _clock * 1.6 + float(i) * TAU / float(ticks)
		var dir := Vector2(cos(ang), sin(ang) * 0.62)
		BatchDraw.native_line(self, dir * ring_r * 0.58, dir * ring_r * 1.06,
			Color(c.r, c.g, c.b, ring_a * 0.8), 1.6 + 1.2 * t)
	# 内核：随进度胀大，末段提亮
	BatchDraw.native_circle(self, Vector2.ZERO, lerpf(2.0, radius * 0.30, t),
		Color(c.r, c.g, c.b, 0.26 + 0.50 * t))
	# Boss 档末段：中心白热核随进度压实（比小怪多一层，落点像被烧红）
	if heavy and t > 0.5:
		var hk: float = (t - 0.5) / 0.5
		BatchDraw.native_circle(self, Vector2.ZERO, radius * 0.16 * hk,
			Color(1.0, 1.0, 1.0, 0.30 + 0.45 * hk))
	# 末段中心亮缝：最后一刻的「要落了」读数
	if t > 0.68:
		var k: float = (t - 0.68) / 0.32
		BatchDraw.native_line(self, Vector2(0.0, -radius * 0.72 * k),
			Vector2(0.0, radius * 0.72 * k), Color(1.0, 1.0, 1.0, 0.7 * k), 2.0)

# ---------------- 起手吸积（Boss 档） ----------------

func _draw_origin() -> void:
	var t := clampf(progress, 0.0, 1.0)
	var c := color
	var pulse := 0.84 + 0.16 * sin(_clock * 22.0)
	var acc_r := lerpf(radius * 1.30, radius * 0.10, ease(t, 1.7))
	# 地面暗底：越接近抽离越黑（把本体脚下的地面「挖空」）
	BatchDraw.native_circle(self, Vector2.ZERO, radius * 0.95,
		Color(0.02, 0.02, 0.04, 0.32 + 0.36 * t))
	# 拔升光柱：本体正在被抽离（比落点光柱更细、更竖直）
	if t > 0.20:
		var k: float = clampf((t - 0.20) / 0.80, 0.0, 1.0)
		_draw_column(Color(c.r, c.g, c.b, 0.05 + 0.20 * k), 0.72 + 0.18 * k, k, false)
	# 吸积外环：从外向内塌缩，越接近消失越亮越粗
	BatchDraw.native_arc(self, Vector2.ZERO, acc_r, 0.0, TAU, 40,
		Color(c.r, c.g, c.b, (0.32 + 0.52 * t) * pulse), 2.0 + 2.6 * t, true)
	# 内环反向自转：读「空间被拧紧」
	var inner_r := acc_r * 0.72
	for i in range(3):
		var a0 := _clock * 2.2 + float(i) * TAU / 3.0
		BatchDraw.native_arc(self, Vector2.ZERO, inner_r, a0, a0 + TAU * 0.26, 14,
			Color(c.r, c.g, c.b, (0.28 + 0.42 * t) * pulse), 1.6, true)
	# 八条吸积纹：随进度旋入圆心（俯视压扁，贴地读法）
	for i in range(8):
		var ang := -_clock * 2.8 + float(i) * TAU / 8.0
		var dir0 := Vector2(cos(ang), sin(ang) * 0.68)
		var dir1 := Vector2(cos(ang + 0.32), sin(ang + 0.32) * 0.68)
		BatchDraw.native_line(self, dir0 * acc_r * 1.22, dir1 * acc_r * 0.52,
			Color(c.r, c.g, c.b, 0.28 + 0.45 * t), 1.6 + 1.2 * t)
	# 核心：被抽走的灵核，最后 45% 转白爆亮
	var core_r := lerpf(2.0, radius * 0.24, t)
	BatchDraw.native_circle(self, Vector2.ZERO, core_r, Color(c.r, c.g, c.b, 0.30 + 0.50 * t))
	if t > 0.55:
		var k: float = (t - 0.55) / 0.45
		BatchDraw.native_circle(self, Vector2.ZERO, core_r * (0.5 + 0.5 * k),
			Color(1.0, 1.0, 1.0, 0.35 + 0.55 * k))
	# 上升灵屑：沿光柱上飘，读「本体已经升走一半」
	if t > 0.30:
		for i in range(5):
			var ph := fposmod(_clock * 1.1 + float(i) * 0.23, 1.0)
			var px := (float(i) - 2.0) * radius * 0.16
			var py := -ph * radius * 1.9
			BatchDraw.native_circle(self, Vector2(px, py), 1.5 * (1.0 - ph),
				Color(1.0, 1.0, 1.0, 0.55 * (1.0 - ph) * t))

# ---------------- 落地爆闪（Boss 档） ----------------

func _draw_arrival() -> void:
	var t := clampf(progress, 0.0, 1.0)
	var c := color
	var fade := 1.0 - t
	# 中心白热地面闪：瞬间亮起再收掉（压低填充不透明度/半径：落地那一拍本体要从中心胀回，
	# 底光太满会把刚现身的本体糊掉 —— 环与残光负责「炸开」读数，填充只负责垫一层亮）
	BatchDraw.native_circle(self, Vector2.ZERO, radius * (0.72 - 0.42 * t),
		Color(c.r, c.g, c.b, 0.24 * fade))
	# 双环外扩：内白外彩，读「冲击波把空间推开」
	BatchDraw.native_arc(self, Vector2.ZERO, radius * (0.25 + 1.35 * t), 0.0, TAU, 40,
		Color(c.r, c.g, c.b, 0.90 * fade), 0.8 + 3.2 * fade, true)
	BatchDraw.native_arc(self, Vector2.ZERO, radius * (0.15 + 0.95 * t), 0.0, TAU, 32,
		Color(1.0, 1.0, 1.0, 0.72 * fade), 2.0 * fade, true)
	# 八向残光：沿地面摊开，压扁成椭圆保持俯视贴地感
	for i in range(8):
		var ang := float(i) * TAU / 8.0 + 0.20
		var dir := Vector2(cos(ang), sin(ang) * 0.72)
		var r0 := radius * (0.30 + 1.05 * t)
		BatchDraw.native_line(self, dir * r0, dir * (r0 + radius * 0.26 * fade),
			Color(c.r, c.g, c.b, 0.76 * fade), 2.0 * fade + 0.4)
	# 光柱塌落：从上方收回，读「东西已经落地了」
	if fade > 0.02:
		_draw_column(Color(c.r, c.g, c.b, 0.26 * fade), 0.55 + 0.45 * fade, fade, true, fade)

# ---------------- 共用光柱 ----------------

## 贴地光柱：堆叠半透明梯形模拟纵向渐变（BatchDraw 只收凸多边形，5 片足够）。
## from_above=true：天光下压（落点用），根部亮、越往上越淡；
## from_above=false：本体拔升（起手用），顶部亮、越往下越淡。
## height_scale 供落地爆闪做「光柱塌落」。
func _draw_column(col: Color, width_scale: float, grow: float, from_above: bool,
		height_scale: float = 1.0) -> void:
	if col.a <= 0.002:
		return
	var base_w := radius * 0.55 * width_scale + radius * 0.10 * grow
	var top_w := radius * (1.10 if from_above else 0.20) * width_scale
	var top_y := -radius * (2.25 + 0.35 * grow) * height_scale
	if top_y >= -1.0:
		return
	var slices := 5
	for i in range(slices):
		var f0 := float(i) / float(slices)
		var f1 := float(i + 1) / float(slices)
		var y0 := lerpf(0.0, top_y, f0)
		var y1 := lerpf(0.0, top_y, f1)
		var w0 := lerpf(base_w, top_w, f0)
		var w1 := lerpf(base_w, top_w, f1)
		var a_mul := lerpf(1.0, 0.30, f0) if from_above else lerpf(0.22, 1.0, f0)
		BatchDraw.poly(self, PackedVector2Array([
			Vector2(-w0 * 0.5, y0), Vector2(w0 * 0.5, y0),
			Vector2(w1 * 0.5, y1), Vector2(-w1 * 0.5, y1),
		]), Color(col.r, col.g, col.b, col.a * a_mul))
	# 中轴白芯：一根细线把光柱从地面串到顶，读「通道」
	var core_a := col.a * (0.9 if from_above else 0.65)
	BatchDraw.native_line(self, Vector2(0.0, 0.0), Vector2(0.0, top_y),
		Color(1.0, 1.0, 1.0, core_a), 1.6)
