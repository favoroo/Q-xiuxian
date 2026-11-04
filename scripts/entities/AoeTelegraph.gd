class_name AoeTelegraph
extends Node2D

## 圆形 AoE 预警圈（Boss 震地冲击 / 丹爆傀儡自爆共用）。
## 「填满式」读法：半透明填充从圆心随进度扩张，填到外圈 = 伤害结算时刻，
## 玩家一眼读出「炸多大、还剩多久」，不再是一个只会闪的静圈。
## 铁律对齐：
##   - 范围视觉与判定同源：radius 必须由持有者赋成判定半径本身（同一常量/字段），
##     本组件不自算范围、不自判伤害，只画。
##   - progress 由持有者每帧驱动（计时真话源在持有者），组件只负责呈现。
##   - 取色走 GameStyle（唯一取色入口），不再散落硬编码橙红。

enum Style { FILL, RUNE, FIRE, THUNDER, VOID }

const EDGE_W_MIN := 3.0         ## 外圈描边起始线宽（对齐旧 SlamRing 的 3.0）
const EDGE_W_MAX := 5.0         ## 结算前外圈描边线宽（随进度加粗，越接近越醒目）
const FILL_ALPHA := 0.20        ## 填充峰值不透明度（半透明，不糊地面细节）
const EDGE_ALPHA_BASE := 0.55   ## 外圈描边基础不透明度
const PULSE_AMP := 0.10         ## 呼吸闪烁幅度（低幅提示"活着"，不抢进度可读性）
const PULSE_SPEED := 16.0       ## 呼吸频率（rad/s），末段加倍
const END_HIGHLIGHT_AT := 0.85  ## 进度超过此值视为"最后关头"：描边提亮、闪烁加急
const LEAD_EDGE_W := 2.0        ## 填充前沿亮边线宽

var radius: float = 100.0
var progress: float = 0.0   ## 0→1，由持有者每帧赋值；到 1 即结算时刻
var color: Color = GameStyle.BAD ## 预警圈颜色（默认红，Boss 可传主题色区分招式）
var style: int = Style.FILL
var accent: Color = Color(0, 0, 0, 0)   ## alpha==0 表示由 color 派生
var _clock: float = 0.0     ## 仅驱动呼吸闪烁的视觉时钟（不参与计时结算）

## 重绘节流（2026-10-14）：原每渲染帧无条件 queue_redraw，每个圈 2 条 48 段弧，
## Boss/精英/丹爆同屏蓄力时是矢量指令大户。20Hz 采样呼吸脉动（2.5Hz）无混叠；锁 30 帧后 30Hz 节流 = 帧长即每帧重绘，故取 20Hz。
const REDRAW_INTERVAL := 0.05
static var redraw_count: int = 0  ## 重绘计数（perf_probe 节流判据消费）
var _draw_phase: float = 0.0

func _ready() -> void:
	_draw_phase = fposmod(float(get_instance_id() % 97) * 0.001, REDRAW_INTERVAL)

func _process(delta: float) -> void:
	_clock += delta
	_draw_phase -= delta
	if _draw_phase <= 0.0:
		_draw_phase = REDRAW_INTERVAL
		redraw_count += 1
		queue_redraw()

func set_style(s: int, accent_color: Color = Color(0, 0, 0, 0)) -> void:
	style = s
	accent = accent_color
	queue_redraw()

func _draw() -> void:
	BatchDraw.flush(self)
	var t := clampf(progress, 0.0, 1.0)
	var ending := t >= END_HIGHLIGHT_AT
	var pulse := sin(_clock * (PULSE_SPEED * (2.0 if ending else 1.0))) * PULSE_AMP
	var edge_alpha := clampf(EDGE_ALPHA_BASE + pulse + (0.25 if ending else 0.0), 0.0, 1.0)
	var edge_w := lerpf(EDGE_W_MIN, EDGE_W_MAX, t)
	var c := color
	var acc: Color = accent if accent.a > 0.0 else c.lightened(0.25)

	match style:
		Style.RUNE:
			_draw_rune(t, c, acc, edge_alpha, edge_w)
		Style.FIRE:
			_draw_fire(t, c, acc, edge_alpha, edge_w)
		Style.THUNDER:
			_draw_thunder(t, c, acc, edge_alpha, edge_w)
		Style.VOID:
			_draw_void(t, c, acc, edge_alpha, edge_w)
		_:
			_draw_fill(t, c, edge_alpha, edge_w)

	BatchDraw.flush(self)

func _draw_fill(t: float, c: Color, edge_alpha: float, edge_w: float) -> void:
	# 填充：从圆心长到判定半径，填满 = 炸
	if t > 0.01:
		BatchDraw.native_circle(self, Vector2.ZERO, radius * t, Color(c.r, c.g, c.b, FILL_ALPHA))
		# 填充前沿亮边：让「正在长大」这件事一眼可读
		if t < 1.0:
			BatchDraw.native_arc(self, Vector2.ZERO, radius * t, 0.0, TAU, 48, c.lightened(0.4), LEAD_EDGE_W, true)
	# 外描边：就是判定边界本身，随进度加粗、末段高亮
	BatchDraw.native_arc(self, Vector2.ZERO, radius, 0.0, TAU, 48, Color(c.r, c.g, c.b, edge_alpha), edge_w, true)

func _draw_rune(t: float, c: Color, acc: Color, edge_alpha: float, edge_w: float) -> void:
	# 填充仍从圆心长到 r
	if t > 0.01:
		BatchDraw.native_circle(self, Vector2.ZERO, radius * t, Color(c.r, c.g, c.b, FILL_ALPHA))
		if t < 1.0:
			BatchDraw.native_arc(self, Vector2.ZERO, radius * t, 0.0, TAU, 48, acc, LEAD_EDGE_W, true)

	# 中心 0.42r 旋转方框（45°）
	var sq_pts := PackedVector2Array()
	var r_sq := radius * 0.42
	var rot_sq := _clock * 0.5 + PI * 0.25
	for k in 5:
		var ang := rot_sq + float(k % 4) * (PI * 0.5)
		sq_pts.append(Vector2(cos(ang), sin(ang)) * r_sq)
	BatchDraw.polyline(self, sq_pts, Color(acc.r, acc.g, acc.b, edge_alpha * 0.75), 1.8)

	# 外环内侧旋转虚线环（半径 0.78r，用 _clock 驱动旋转，24 段短线）
	var rot_rune := _clock * 0.8
	var r_dash := radius * 0.78
	var dash_step := TAU / 24.0
	for i in 24:
		var a0 := rot_rune + float(i) * dash_step
		var a1 := a0 + dash_step * 0.55
		var p0 := Vector2(cos(a0), sin(a0)) * r_dash
		var p1 := Vector2(cos(a1), sin(a1)) * r_dash
		BatchDraw.line(self, p0, p1, Color(acc.r, acc.g, acc.b, edge_alpha * 0.75), 1.6)

	# 12 根径向刻度（0.86r→0.96r）
	var tick_step := TAU / 12.0
	for k in 12:
		var ang := rot_rune + float(k) * tick_step
		var dir := Vector2(cos(ang), sin(ang))
		BatchDraw.line(self, dir * (radius * 0.86), dir * (radius * 0.96), Color(acc.r, acc.g, acc.b, edge_alpha * 0.85), 1.8)

	# 外描边
	BatchDraw.native_arc(self, Vector2.ZERO, radius, 0.0, TAU, 48, Color(c.r, c.g, c.b, edge_alpha), edge_w, true)

func _draw_fire(t: float, c: Color, acc: Color, edge_alpha: float, edge_w: float) -> void:
	# 填充色偏暖
	var warm_c := c.lerp(Color(1.0, 0.38, 0.08), 0.35)
	if t > 0.01:
		BatchDraw.native_circle(self, Vector2.ZERO, radius * t, Color(warm_c.r, warm_c.g, warm_c.b, FILL_ALPHA))
		if t < 1.0:
			BatchDraw.native_arc(self, Vector2.ZERO, radius * t, 0.0, TAU, 48, acc, LEAD_EDGE_W, true)

	# 沿外环画 12 片小火舌（外沿向内 0.78r→0.98r 的三角/梯形，高矮按 _clock 做静态相位错开，用 _clock 只改透明度）
	var flame_step := TAU / 12.0
	var r_base := radius * 0.98
	var half_w := flame_step * 0.28
	for i in 12:
		var ang := float(i) * flame_step
		var phase := float(i) * 1.618
		var h_factor := 0.5 + 0.5 * sin(phase)
		var r_tip := radius * lerpf(0.78, 0.88, h_factor)
		var p_b1 := Vector2(cos(ang - half_w), sin(ang - half_w)) * r_base
		var p_b2 := Vector2(cos(ang + half_w), sin(ang + half_w)) * r_base
		var p_tip := Vector2(cos(ang), sin(ang)) * r_tip
		var fl_alpha := clampf((0.35 + 0.25 * sin(_clock * 6.0 + phase)) * edge_alpha, 0.0, 1.0)
		var tri := PackedVector2Array([p_b1, p_b2, p_tip])
		BatchDraw.poly(self, tri, Color(acc.r, acc.g, acc.b, fl_alpha))

	# 外描边
	BatchDraw.native_arc(self, Vector2.ZERO, radius, 0.0, TAU, 48, Color(c.r, c.g, c.b, edge_alpha), edge_w, true)

func _draw_thunder(t: float, c: Color, acc: Color, edge_alpha: float, edge_w: float) -> void:
	if t > 0.01:
		BatchDraw.native_circle(self, Vector2.ZERO, radius * t, Color(c.r, c.g, c.b, FILL_ALPHA))
		if t < 1.0:
			BatchDraw.native_arc(self, Vector2.ZERO, radius * t, 0.0, TAU, 48, acc, LEAD_EDGE_W, true)

	# 3 条锯齿辐条（中心→0.92r，每根 5 段折线，抖动相位由 _clock 与序号决定，幅度 ≤ 0.06r）
	var spoke_step := TAU / 3.0
	for spoke_i in 3:
		var base_ang := float(spoke_i) * spoke_step
		var dir := Vector2(cos(base_ang), sin(base_ang))
		var perp := Vector2(-dir.y, dir.x)
		var spoke_pts := PackedVector2Array()
		spoke_pts.resize(6)
		spoke_pts[0] = Vector2.ZERO
		for seg_i in range(1, 5):
			var s := float(seg_i) / 5.0
			var r_nom := s * (radius * 0.92)
			var jitter_phase := _clock * 18.0 + float(spoke_i) * 2.3 + float(seg_i) * 1.7
			var jitter := sin(jitter_phase) * (radius * 0.05)
			spoke_pts[seg_i] = dir * r_nom + perp * jitter
		spoke_pts[5] = dir * (radius * 0.92)
		BatchDraw.polyline(self, spoke_pts, Color(acc.r, acc.g, acc.b, edge_alpha * 0.85), 2.0)

	# 外环锯齿化（保持半径 r）
	var ring_pts := PackedVector2Array()
	var teeth_count := 36
	ring_pts.resize(teeth_count + 1)
	for i in range(teeth_count + 1):
		var ang := TAU * float(i % teeth_count) / float(teeth_count)
		var r_ring := radius if (i % 2 == 0) else radius * 0.94
		ring_pts[i] = Vector2(cos(ang), sin(ang)) * r_ring
	BatchDraw.polyline(self, ring_pts, Color(c.r, c.g, c.b, edge_alpha), edge_w)

func _draw_void(t: float, c: Color, acc: Color, edge_alpha: float, edge_w: float) -> void:
	# 填充色更暗
	var void_c := c.darkened(0.55)
	if t > 0.01:
		BatchDraw.native_circle(self, Vector2.ZERO, radius * t, Color(void_c.r, void_c.g, void_c.b, FILL_ALPHA * 1.2))
		if t < 1.0:
			BatchDraw.native_arc(self, Vector2.ZERO, radius * t, 0.0, TAU, 48, acc.darkened(0.2), LEAD_EDGE_W, true)

	# 外环内侧 0.72r 再画一圈反向旋转的暗环
	var rot_void := -_clock * 0.8
	var dark_col := Color(c.r * 0.35, c.g * 0.35, c.b * 0.35, edge_alpha * 0.85)
	BatchDraw.native_arc(self, Vector2.ZERO, radius * 0.72, 0.0, TAU, 36, dark_col, 2.2, true)

	# 8 个向内的小三角（"吸"的读数）
	var step_void := TAU / 8.0
	var half_w := step_void * 0.22
	var r_base := radius * 0.84
	var r_tip := radius * 0.72
	for k in 8:
		var ang := rot_void + float(k) * step_void
		var p_b1 := Vector2(cos(ang - half_w), sin(ang - half_w)) * r_base
		var p_b2 := Vector2(cos(ang + half_w), sin(ang + half_w)) * r_base
		var p_tip := Vector2(cos(ang), sin(ang)) * r_tip
		var tri := PackedVector2Array([p_b1, p_b2, p_tip])
		var tri_col := Color(c.r * 0.4, c.g * 0.4, c.b * 0.4, edge_alpha * 0.8)
		BatchDraw.poly(self, tri, tri_col)

	# 外描边
	BatchDraw.native_arc(self, Vector2.ZERO, radius, 0.0, TAU, 48, Color(c.r, c.g, c.b, edge_alpha), edge_w, true)
