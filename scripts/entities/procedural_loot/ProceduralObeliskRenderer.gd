class_name ProceduralObeliskRenderer
extends Node2D

## 九天锁灵悬晶大阵 · 程序化矢量渲染器（空洞冷冽国风）
## 涵盖半径 85px 八卦外环阵盘、中央悬浮三段玄晶柱、充能聚灵流光与耗尽灰相

## 重绘节流（2026-10-15 性能优化）：全场 3 座界碑常驻，原 _process 每帧无条件 queue_redraw()，
## 且 BlessingObelisk 每帧写 ring_rotation 在 setter 又 queue_redraw()（一帧两度标脏）。
## 阵盘慢速旋转、浮动与呼吸全是平滑慢速量，20Hz 节流 + 错相完全足够，消灭每帧无谓重绘。
## 【2026-10-21 充能升档】静止仍 20Hz；仅「正在充能 / 熄灭形变 / 激活闪白」这一座升到满帧率
## （VisualRate.interval(60,30)）。玩家同一时刻只能站进一座碑，故峰值只多一个节点的 _draw。
const REDRAW_INTERVAL := 0.05
## 激活闪白时长（秒）：晶柱瞬间超白过曝后回落
const FLASH_DUR := 0.16

var _draw_phase: float = 0.0
var _dirty: bool = true

@export var is_spent: bool = false:
	set(val):
		if is_spent != val:
			is_spent = val
			_dirty = true

## 熄灭形变进度（0=鲜活, 1=全灰）。由 BlessingObelisk 在收尾 tween 里推进，
## 让「瞬间切剪影」变成连续下沉/褪色，避免硬切跳变。
var spent_blend: float = 0.0:
	set(val):
		spent_blend = clampf(val, 0.0, 1.0)
		_dirty = true

## 激活闪白强度（1→0 衰减），由 BlessingObelisk.trigger 时置 1
var activation_flash: float = 0.0

@export var fill_ratio: float = 0.0:
	set(val):
		fill_ratio = clampf(val, 0.0, 1.0)
		# 灌灵进度平滑累加，由 20Hz/满帧节流自然呈现，不再每帧直接 queue_redraw

@export var ring_rotation: float = 0.0:
	set(val):
		ring_rotation = val
		# 阵盘自转由节流自然呈现，不再每帧直接 queue_redraw

@export var is_charging: bool = false:
	set(val):
		if is_charging != val:
			is_charging = val
			_dirty = true

@export var is_player_inside: bool = false

var _time: float = 0.0

func _ready() -> void:
	_time = randf() * 10.0
	_draw_phase = fposmod(float(get_instance_id() % 97) * 0.001, REDRAW_INTERVAL)

func _process(delta: float) -> void:
	_time += delta
	if activation_flash > 0.0:
		activation_flash = maxf(0.0, activation_flash - delta / FLASH_DUR)

	# 节流间隔：静止 20Hz；充能/熄灭形变/闪白这一座升到满帧率（跟随帧率档）
	var interval: float = REDRAW_INTERVAL
	if is_charging or activation_flash > 0.0 or (spent_blend > 0.0 and spent_blend < 0.999):
		interval = VisualRate.interval(60.0, 30.0)

	if _dirty or _draw_phase <= 0.0:
		_dirty = false
		_draw_phase = interval
		queue_redraw()
	else:
		_draw_phase -= delta

func _draw() -> void:
	if is_spent or spent_blend >= 0.999:
		_draw_spent_look()
		return

	_draw_altar_ground_runes()
	_draw_charge_column()
	_draw_floating_crystal_spire()

# ==============================================================================
# 1. 地面八方阵盘（Rune Circle - 精确对应 85px 判定范围）
# ==============================================================================
func _draw_altar_ground_runes() -> void:
	var r_outer: float = 85.0
	var r_inner: float = 52.0
	var r_center: float = 24.0

	var alpha_base: float = 0.35 if is_player_inside else 0.18
	if is_charging:
		alpha_base = 0.55 + sin(_time * 12.0) * 0.15
	# 熄灭形变：阵盘整体淡出
	alpha_base *= (1.0 - spent_blend)

	var col_rune_main := Color(0.25, 0.85, 1.0, alpha_base)
	var col_rune_gold := Color(1.0, 0.82, 0.30, alpha_base * 0.9)
	var col_line_dim := Color(0.12, 0.35, 0.55, alpha_base * 0.5)

	# 1.1 外阵环（受 ring_rotation 顺时针驱动）
	draw_set_transform(Vector2.ZERO, ring_rotation, Vector2.ONE)

	# 外同心双环（弧段自适应：85px 36 段、52px 24 段、24px 16 段，取代原 64/48/32 段）
	draw_arc(Vector2.ZERO, r_outer, 0, TAU, 36, col_rune_main, 1.8, true)
	draw_arc(Vector2.ZERO, r_outer - 4.0, 0, TAU, 36, col_line_dim, 1.0, true)
	draw_arc(Vector2.ZERO, r_center, 0, TAU, 16, col_line_dim, 1.0, true)

	# 24 节气刻度：随充能进度逐段点亮（青→金），形成「阵盘被一路点燃」的扫描感
	var lit: float = fill_ratio
	for k in range(24):
		var a_tick := (TAU / 24.0) * float(k)
		var tdir := Vector2(cos(a_tick), sin(a_tick))
		var is_major := (k % 3 == 0)
		var tick_len := 5.0 if is_major else 3.0
		# 该刻度是否已点亮：以进度扫过为界（起始角从 -PI/2 顺时针，与走针环同源起点）
		var tick_frac := fposmod(a_tick + PI / 2.0, TAU) / TAU
		var on: float = clampf((lit - tick_frac) / 0.12, 0.0, 1.0)
		var col_tick := col_line_dim.lerp(Color(1.0, 0.9, 0.45, alpha_base), on) if is_charging else col_line_dim
		draw_line(tdir * (r_outer + 1.5), tdir * (r_outer + 1.5 + tick_len), col_tick, 1.0)

	# 8 方位星宿卦爻刻印与引线
	var num_nodes := 8
	for i in range(num_nodes):
		var angle := (TAU / float(num_nodes)) * float(i)
		var dir := Vector2(cos(angle), sin(angle))

		# 辐射引线
		draw_line(dir * (r_inner + 4.0), dir * (r_outer - 6.0), col_line_dim, 1.0)

		# 外圈节点菱形符印
		var p_node := dir * (r_outer - 2.0)
		var p_poly := PackedVector2Array([
			p_node + dir * 3.5,
			p_node + dir.orthogonal() * 2.5,
			p_node - dir * 3.5,
			p_node - dir.orthogonal() * 2.5
		])
		draw_colored_polygon(p_poly, col_rune_gold)

		# 内圈小八卦短线
		var p_mid := dir * r_inner
		draw_line(p_mid - dir.orthogonal() * 3.0, p_mid + dir.orthogonal() * 3.0, col_rune_main, 1.5)

	# 恢复原点变换
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 1.2 内阵环（反向慢转）：与外环形成「天地阴阳对转」的齿轮感
	draw_set_transform(Vector2.ZERO, ring_rotation * -0.6, Vector2.ONE)
	var col_inner_ring := Color(0.35, 0.9, 1.0, alpha_base * 0.7)
	draw_arc(Vector2.ZERO, r_inner, 0, TAU, 24, col_inner_ring, 1.4, true)
	# 内环 6 枚小刻点
	for m in range(6):
		var ma := (TAU / 6.0) * float(m)
		var mp := Vector2(cos(ma), sin(ma)) * r_inner
		draw_circle(mp, 1.4, col_rune_gold)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 1.3 充能时向心螺旋灵气丝（3 条臂，每臂 8 粒拖尾，向心加速吸入）
	if is_charging:
		var arm_count := 3
		var dots_per_arm := 8
		var warm: float = fill_ratio  # 随进度由青转金
		var stream_col := Color(0.55, 0.95, 1.0, 1.0).lerp(Color(1.0, 0.9, 0.5, 1.0), warm)
		for arm in range(arm_count):
			var base_ang := (TAU / float(arm_count)) * float(arm) + _time * 3.2
			for d in range(dots_per_arm):
				# 沿臂的相位错开，形成向内收束的拖尾
				var t_prog := fmod(_time * 2.2 + float(d) * 0.09 + float(arm) * 0.21, 1.0)
				var cur_r := lerpf(r_outer - 3.0, r_center + 3.0, t_prog)
				var ang := base_ang + t_prog * 2.2
				var sdir := Vector2(cos(ang), sin(ang))
				var a_dot := (1.0 - t_prog) * 0.85
				var sz := 2.2 - 1.2 * t_prog
				draw_circle(sdir * cur_r, sz, Color(stream_col, a_dot))
				if t_prog > 0.55:
					draw_circle(sdir * cur_r, sz * 0.5, Color(1.0, 1.0, 0.92, a_dot))

# ==============================================================================
# 1.5 升灵光柱：阵盘与悬晶之间自下而上升起的柔和梯形光柱（高度 ∝ fill_ratio）
# ==============================================================================
func _draw_charge_column() -> void:
	if fill_ratio <= 0.02 or spent_blend > 0.0:
		return
	var h: float = 58.0 * fill_ratio
	var pulse: float = 0.82 + 0.18 * sin(_time * 6.0)
	var a_out: float = 0.30 * fill_ratio * pulse * (1.0 - spent_blend)
	var a_core: float = 0.55 * fill_ratio * pulse * (1.0 - spent_blend)
	# 底宽顶窄的柔和梯形（自碑基 y=8 向上）
	var base_y: float = 8.0
	var top_y: float = base_y - h
	var w_base: float = 15.0
	var w_top: float = 8.0
	draw_colored_polygon(PackedVector2Array([
		Vector2(-w_base, base_y), Vector2(w_base, base_y),
		Vector2(w_top, top_y), Vector2(-w_top, top_y)
	]), Color(0.5, 0.9, 1.0, a_out))
	draw_colored_polygon(PackedVector2Array([
		Vector2(-w_base * 0.4, base_y), Vector2(w_base * 0.4, base_y),
		Vector2(w_top * 0.4, top_y), Vector2(-w_top * 0.4, top_y)
	]), Color(GameStyle.FX_HDR_CORE, a_core))

# ==============================================================================
# 2. 中央悬浮玄晶灵塔（Floating Void Crystal Spire）
# ==============================================================================
func _draw_floating_crystal_spire() -> void:
	# 悬浮微动（1.6Hz 正弦）；熄灭形变时下沉收敛
	var bob_amp: float = 3.5 * (1.0 - spent_blend)
	var bob_y: float = sin(_time * 2.2) * bob_amp - 12.0 + spent_blend * 6.0
	var core_pos := Vector2(0, bob_y)

	# 2.0 地面落影（2026-10-18 补）：双层软影垫在基座下，悬浮玄晶有落点
	_draw_ground_shadow(Vector2(0, 12), 26.0, 6.0, 0.5)

	# 2.1 阵台玄铁基座（紧贴地面）
	var base_poly := PackedVector2Array([
		Vector2(-22, 6),
		Vector2(22, 6),
		Vector2(16, 14),
		Vector2(-16, 14)
	])
	draw_colored_polygon(base_poly, Color(0.08, 0.10, 0.15, 0.95))
	draw_polyline(base_poly, Color(0.28, 0.38, 0.50, 0.9), 1.3, true)
	# 基座符文凹槽微光（熄灭时随之暗下）
	var slot_a: float = (0.5 + sin(_time * 3.0) * 0.2) * (1.0 - spent_blend)
	draw_line(Vector2(-14, 10), Vector2(14, 10), Color(0.25, 0.85, 1.0, slot_a), 1.5)

	# 2.2 悬浮中央主晶（高 48px，宽 18px）
	var spire_h: float = 48.0 * (1.0 - spent_blend * 0.35)
	var spire_w: float = 18.0
	var hw: float = spire_w * 0.5
	var top := core_pos + Vector2(0, -spire_h * 0.6)
	var bottom := core_pos + Vector2(0, spire_h * 0.4)
	var mid_y := core_pos.y
	var left := Vector2(-hw, mid_y)
	var right := Vector2(hw, mid_y)
	var ridge := core_pos + Vector2(0, 1.0)

	# 主晶色彩定义
	var col_dark := Color(0.08, 0.16, 0.28, 0.95)
	var col_mid := Color(0.18, 0.45, 0.68, 0.95)
	var col_light := Color(0.40, 0.85, 1.0, 0.98)
	var col_ridge := Color(0.85, 0.96, 1.0, 0.95)

	# 灌灵高度对应的炽金/青白能量色
	var glow_power: float = fill_ratio
	if is_charging:
		col_light = col_light.lerp(Color(1.0, 0.92, 0.55), glow_power * 0.85)
		col_ridge = col_ridge.lerp(Color(1.0, 1.0, 0.85), glow_power * 0.9)

	# 激活闪白：整柱向超白过曝
	if activation_flash > 0.0:
		var f: float = activation_flash
		col_dark = col_dark.lerp(Color(GameStyle.FX_HDR_CORE, 1.0), f)
		col_mid = col_mid.lerp(Color(GameStyle.FX_HDR_CORE, 1.0), f)
		col_light = col_light.lerp(Color(GameStyle.FX_HDR_CORE, 1.0), f)
		col_ridge = col_ridge.lerp(Color(GameStyle.FX_HDR_CORE, 1.0), f)

	# 熄灭形变：晶面褪向冷灰
	if spent_blend > 0.0:
		var grey := Color(0.24, 0.28, 0.33, 0.95)
		var b: float = spent_blend
		col_dark = col_dark.lerp(grey.darkened(0.3), b)
		col_mid = col_mid.lerp(grey, b)
		col_light = col_light.lerp(grey.lightened(0.1), b)
		col_ridge = col_ridge.lerp(grey, b)

	# 4 个主晶几何切面
	draw_colored_polygon(PackedVector2Array([top, ridge, left]), col_mid)      # 上左（次亮）
	draw_colored_polygon(PackedVector2Array([top, right, ridge]), col_light)   # 上右（极亮）
	draw_colored_polygon(PackedVector2Array([left, ridge, bottom]), col_dark)  # 下左（暗面）
	draw_colored_polygon(PackedVector2Array([ridge, right, bottom]), col_mid.darkened(0.2))  # 下右（透光）

	# 中脊高光与锋刃
	draw_line(top, bottom, col_ridge, 1.3, true)
	draw_polyline(PackedVector2Array([top, right, bottom, left, top]), Color(0.55, 0.85, 1.0, 0.9 * (1.0 - spent_blend)), 1.2, true)

	# 灌灵液面（自下而上注入）；熄灭形变时不画
	if fill_ratio > 0.02 and spent_blend < 0.05:
		var fill_y := lerpf(bottom.y, top.y, fill_ratio)
		var fill_col := Color(1.0, 0.92, 0.45, 0.85)
		draw_line(Vector2(-hw * (1.0 - fill_ratio * 0.3), fill_y), Vector2(hw * (1.0 - fill_ratio * 0.3), fill_y), fill_col, 2.0)
		draw_circle(Vector2(0, fill_y), 2.5, Color(1.0, 1.0, 0.9, 0.95))

	# 2.3 两枚随侍悬晶（左、右环绕小菱晶）；熄灭时收拢淡出
	if spent_blend < 0.5:
		var orb_alpha: float = 1.0 - spent_blend * 2.0
		var orb_angle := _time * 2.0
		var orb_dist := lerpf(20.0, 6.0, spent_blend)
		var p_left_orb := core_pos + Vector2(cos(orb_angle) * orb_dist, sin(orb_angle) * 5.0 - 4.0)
		var p_right_orb := core_pos + Vector2(cos(orb_angle + PI) * orb_dist, sin(orb_angle + PI) * 5.0 - 4.0)
		_draw_mini_floating_gem(p_left_orb, Color(col_light, orbit_a(col_light, orb_alpha)), Color(col_ridge, orbit_a(col_ridge, orb_alpha)))
		_draw_mini_floating_gem(p_right_orb, Color(col_light, orbit_a(col_light, orb_alpha)), Color(col_ridge, orbit_a(col_ridge, orb_alpha)))

## 取色并套上整体透明度的辅助（保留原色 RGB，只压 alpha）
func orbit_a(c: Color, mul: float) -> float:
	return c.a * clampf(mul, 0.0, 1.0)

## 双层软地影（2026-10-18 阴影统一升级）：外层弥散 + 内层接触暗核，与全场实体同一画法。
## 无 draw_filled_ellipse 辅助，本地以 16 边多边形近似压扁椭圆。
func _draw_ground_shadow(pos: Vector2, rx: float, ry: float, alpha: float) -> void:
	for layer in range(2):
		var k := 1.0 if layer == 0 else 0.66
		var a := alpha * 0.6 if layer == 0 else minf(alpha * 1.35, 0.88)
		var pts := PackedVector2Array()
		for i in range(16):
			var ang := TAU * float(i) / 16.0
			pts.append(pos + Vector2(cos(ang) * rx * k, sin(ang) * ry * k))
		var depth := 1.0 if layer == 0 else 0.4
		draw_colored_polygon(pts, Color(0.04 * depth, 0.05 * depth, 0.08 * depth, a))

func _draw_mini_floating_gem(pos: Vector2, c_main: Color, c_ridge: Color) -> void:
	var gw: float = 4.5
	var gh: float = 8.0
	var pts := PackedVector2Array([
		pos + Vector2(0, -gh * 0.5),
		pos + Vector2(gw * 0.5, 0),
		pos + Vector2(0, gh * 0.5),
		pos + Vector2(-gw * 0.5, 0)
	])
	draw_colored_polygon(pts, c_main)
	draw_line(pos + Vector2(0, -gh * 0.5), pos + Vector2(0, gh * 0.5), c_ridge, 1.0)

# ==============================================================================
# 3. 耗尽沉寂态（Spent / Inactive Look）
# ==============================================================================
func _draw_spent_look() -> void:
	# 阵盘残痕（冷灰，比原稿提亮一档：暗底上要还能看出「这儿有座用掉的碑」）
	draw_arc(Vector2.ZERO, 85.0, 0, TAU, 36, Color(0.34, 0.40, 0.46, 0.28), 1.2, true)
	draw_arc(Vector2.ZERO, 52.0, 0, TAU, 24, Color(0.30, 0.36, 0.42, 0.22), 1.0, true)

	# 地面落影（耗尽态同样垫底）
	_draw_ground_shadow(Vector2(0, 12), 26.0, 6.0, 0.45)

	# 基座与落座残石（灰岩质感：面提亮、棱描边）
	var base_poly := PackedVector2Array([
		Vector2(-22, 6),
		Vector2(22, 6),
		Vector2(16, 14),
		Vector2(-16, 14)
	])
	draw_colored_polygon(base_poly, Color(0.20, 0.23, 0.27, 0.95))
	draw_polyline(base_poly, Color(0.40, 0.45, 0.50, 0.85), 1.2, true)

	# 灵晶下落沉入基台且失去光泽（石灰色 + 冷高光棱线，读得出是块石化晶石）
	var resting_pos := Vector2(0, -6.0)
	var pts := PackedVector2Array([
		resting_pos + Vector2(0, -20),
		resting_pos + Vector2(8, 6),
		resting_pos + Vector2(0, 14),
		resting_pos + Vector2(-8, 6)
	])
	draw_colored_polygon(pts, Color(0.33, 0.36, 0.41, 0.96))
	# 左半面压暗，留一点体积感
	draw_colored_polygon(PackedVector2Array([
		resting_pos + Vector2(0, -20), resting_pos + Vector2(-8, 6),
		resting_pos + Vector2(0, 14)
	]), Color(0.26, 0.29, 0.34, 0.96))
	draw_polyline(pts, Color(0.52, 0.57, 0.62, 0.85), 1.3, true)
	draw_line(resting_pos + Vector2(0, -20), resting_pos + Vector2(0, 14), Color(0.46, 0.51, 0.56, 0.9), 1.1)
