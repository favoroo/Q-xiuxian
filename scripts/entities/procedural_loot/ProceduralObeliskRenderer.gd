class_name ProceduralObeliskRenderer
extends Node2D

## 九天锁灵悬晶大阵 · 程序化矢量渲染器（空洞冷冽国风）
## 涵盖半径 85px 八卦外环阵盘、中央悬浮三段玄晶柱、充能聚灵流光与耗尽灰相

@export var is_spent: bool = false:
	set(val):
		is_spent = val
		queue_redraw()

@export var fill_ratio: float = 0.0:
	set(val):
		fill_ratio = clampf(val, 0.0, 1.0)
		queue_redraw()

@export var ring_rotation: float = 0.0:
	set(val):
		ring_rotation = val
		queue_redraw()

@export var is_charging: bool = false
@export var is_player_inside: bool = false

var _time: float = 0.0

func _ready() -> void:
	_time = randf() * 10.0

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	if is_spent:
		_draw_spent_look()
		return

	_draw_altar_ground_runes()
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

	var col_rune_main := Color(0.25, 0.85, 1.0, alpha_base)
	var col_rune_gold := Color(1.0, 0.82, 0.30, alpha_base * 0.9)
	var col_line_dim := Color(0.12, 0.35, 0.55, alpha_base * 0.5)

	# 1.1 旋转阵环（受 ring_rotation 驱动）
	draw_set_transform(Vector2.ZERO, ring_rotation, Vector2.ONE)

	# 外同心双环
	draw_arc(Vector2.ZERO, r_outer, 0, TAU, 64, col_rune_main, 1.8, true)
	draw_arc(Vector2.ZERO, r_outer - 4.0, 0, TAU, 64, col_line_dim, 1.0, true)
	draw_arc(Vector2.ZERO, r_inner, 0, TAU, 48, col_rune_gold, 1.4, true)
	draw_arc(Vector2.ZERO, r_center, 0, TAU, 32, col_line_dim, 1.0, true)

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

	# 充能时向心能量丝
	if is_charging:
		var stream_count := 6
		for j in range(stream_count):
			var s_angle := (TAU / float(stream_count)) * float(j) + _time * 4.0
			var s_dir := Vector2(cos(s_angle), sin(s_angle))
			var t_prog := fmod(_time * 2.5 + float(j) * 0.3, 1.0)
			var cur_r := lerpf(r_outer - 5.0, r_center + 4.0, t_prog)
			draw_circle(s_dir * cur_r, 1.6, Color(1.0, 0.95, 0.7, 0.8 * (1.0 - t_prog)))

	# 恢复原点变换
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ==============================================================================
# 2. 中央悬浮玄晶灵塔（Floating Void Crystal Spire）
# ==============================================================================
func _draw_floating_crystal_spire() -> void:
	# 悬浮微动（1.6Hz 正弦）
	var bob_y: float = sin(_time * 2.2) * 3.5 - 12.0
	var core_pos := Vector2(0, bob_y)

	# 2.1 阵台玄铁基座（紧贴地面）
	var base_poly := PackedVector2Array([
		Vector2(-22, 6),
		Vector2(22, 6),
		Vector2(16, 14),
		Vector2(-16, 14)
	])
	draw_colored_polygon(base_poly, Color(0.08, 0.10, 0.15, 0.95))
	draw_polyline(base_poly, Color(0.28, 0.38, 0.50, 0.9), 1.3, true)
	# 基座符文凹槽微光
	draw_line(Vector2(-14, 10), Vector2(14, 10), Color(0.25, 0.85, 1.0, 0.5 + sin(_time * 3.0) * 0.2), 1.5)

	# 2.2 悬浮中央主晶（高 48px，宽 18px）
	var spire_h: float = 48.0
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

	# 4 个主晶几何切面
	# 上左面（次亮）
	draw_colored_polygon(PackedVector2Array([top, ridge, left]), col_mid)
	# 上右面（极亮）
	draw_colored_polygon(PackedVector2Array([top, right, ridge]), col_light)
	# 下左面（暗面）
	draw_colored_polygon(PackedVector2Array([left, ridge, bottom]), col_dark)
	# 下右面（透光）
	draw_colored_polygon(PackedVector2Array([ridge, right, bottom]), col_mid.darkened(0.2))

	# 中脊高光与锋刃
	draw_line(top, bottom, col_ridge, 1.3, true)
	draw_polyline(PackedVector2Array([top, right, bottom, left, top]), Color(0.55, 0.85, 1.0, 0.9), 1.2, true)

	# 灌灵液面（自下而上注入）
	if fill_ratio > 0.02:
		var fill_y := lerpf(bottom.y, top.y, fill_ratio)
		var fill_col := Color(1.0, 0.92, 0.45, 0.85)
		draw_line(Vector2(-hw * (1.0 - fill_ratio * 0.3), fill_y), Vector2(hw * (1.0 - fill_ratio * 0.3), fill_y), fill_col, 2.0)
		draw_circle(Vector2(0, fill_y), 2.5, Color(1.0, 1.0, 0.9, 0.95))

	# 2.3 两枚随侍悬晶（左、右环绕小菱晶）
	var orb_angle := _time * 2.0
	var orb_dist := 20.0
	var p_left_orb := core_pos + Vector2(cos(orb_angle) * orb_dist, sin(orb_angle) * 5.0 - 4.0)
	var p_right_orb := core_pos + Vector2(cos(orb_angle + PI) * orb_dist, sin(orb_angle + PI) * 5.0 - 4.0)

	_draw_mini_floating_gem(p_left_orb, col_light, col_ridge)
	_draw_mini_floating_gem(p_right_orb, col_light, col_ridge)

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
	# 阵盘残痕（极暗冷灰）
	draw_arc(Vector2.ZERO, 85.0, 0, TAU, 48, Color(0.18, 0.22, 0.26, 0.2), 1.2, true)
	draw_arc(Vector2.ZERO, 52.0, 0, TAU, 36, Color(0.18, 0.22, 0.26, 0.15), 1.0, true)

	# 基座与落座残石
	var base_poly := PackedVector2Array([
		Vector2(-22, 6),
		Vector2(22, 6),
		Vector2(16, 14),
		Vector2(-16, 14)
	])
	draw_colored_polygon(base_poly, Color(0.08, 0.09, 0.11, 0.9))
	draw_polyline(base_poly, Color(0.20, 0.24, 0.28, 0.8), 1.1, true)

	# 灵晶下落沉入基台且失去光泽
	var resting_pos := Vector2(0, -6.0)
	var pts := PackedVector2Array([
		resting_pos + Vector2(0, -20),
		resting_pos + Vector2(8, 6),
		resting_pos + Vector2(0, 14),
		resting_pos + Vector2(-8, 6)
	])
	draw_colored_polygon(pts, Color(0.14, 0.16, 0.20, 0.95))
	draw_polyline(pts, Color(0.25, 0.30, 0.35, 0.75), 1.1, true)
	draw_line(resting_pos + Vector2(0, -20), resting_pos + Vector2(0, 14), Color(0.22, 0.26, 0.30, 0.8), 1.0)
