class_name HollowKnightCultivatorRenderer
extends CultivatorRendererBase

## 空洞骑士风 · 绿衣修士高精渲染器 (Hollow Knight Deluxe)
## 实现全套动作状态机：待机、奔跑、冲刺、挥剑、受击，支持正/侧/背三视角

# 默认绿色修仙色盘
var col_void: Color = Color(0.06, 0.07, 0.10)
var col_bone: Color = Color(0.96, 0.97, 0.99)
var col_bone_shadow: Color = Color(0.76, 0.82, 0.88)
var col_eye_glow: Color = Color(0.75, 0.92, 1.0, 0.45)
var col_eye_core: Color = Color(0.98, 1.0, 1.0)
var col_cloak_outer: Color = Color(0.11, 0.24, 0.17) # 深邃墨绿
var col_cloak_inner: Color = Color(0.18, 0.38, 0.28) # 青碧月影薄纱
var col_cloak_edge: Color = Color(0.28, 0.62, 0.46)  # 边缘冷玉月辉
var col_nail_white: Color = Color(0.95, 0.97, 1.0)
var col_nail_shadow: Color = Color(0.70, 0.78, 0.86)
var col_slash_arc: Color = Color(0.92, 0.98, 1.0, 0.95)
var col_slash_glow: Color = Color(0.40, 0.85, 0.70, 0.4)

func _init() -> void:
	if config == null:
		config = CultivatorVisualConfig.make_green_hollow_knight()
	_sync_palette()

func _sync_palette() -> void:
	if config and config.palette.size() > 0:
		col_void = config.palette.get("void_black", col_void)
		col_bone = config.palette.get("bone_white", col_bone)
		col_bone_shadow = config.palette.get("bone_shadow", col_bone_shadow)
		col_eye_glow = config.palette.get("eye_glow", col_eye_glow)
		col_eye_core = config.palette.get("eye_core", col_eye_core)
		col_cloak_outer = config.palette.get("cloak_outer", col_cloak_outer)
		col_cloak_inner = config.palette.get("cloak_inner", col_cloak_inner)
		col_cloak_edge = config.palette.get("cloak_edge", col_cloak_edge)
		col_nail_white = config.palette.get("nail_white", col_nail_white)
		col_nail_shadow = config.palette.get("nail_shadow", col_nail_shadow)
		col_slash_arc = config.palette.get("slash_arc", col_slash_arc)
		col_slash_glow = config.palette.get("slash_glow", col_slash_glow)

# ==================== 1. 待机 (IDLE) ====================

func _draw_idle(angle: Angle) -> void:
	var float_y := sin(_time * 2.6) * 2.0
	var cloak_wave := sin(_time * 3.2) * 2.5
	var eye_pulse := sin(_time * 3.0) * 0.08

	# 脚底地影与虚空清气
	_draw_ground_shadow(Vector2(0, 32), 18.0, 5.0, 0.5)

	match angle:
		Angle.FRONT:
			_draw_nail(Vector2(-2, -10 + float_y), deg_to_rad(-24.0))
			_draw_cloak_front(float_y, cloak_wave)
			_draw_chest_pearl(float_y)
			_draw_head_front(float_y, eye_pulse)
		Angle.SIDE:
			_draw_cloak_side(float_y, cloak_wave, 0.0)
			_draw_head_side(float_y, eye_pulse)
			_draw_nail(Vector2(16, 8 + float_y), deg_to_rad(62.0)) # 单手握钉待发
		Angle.BACK:
			_draw_nail(Vector2(0, 0 + float_y), deg_to_rad(-8.0))
			_draw_cloak_back(float_y, cloak_wave)
			_draw_head_back(float_y)

# ==================== 2. 奔跑 (RUN) ====================

func _draw_run(angle: Angle, phase: float, _air_val: float) -> void:
	var step_lift := sin(phase * TAU) * 2.8
	var cloak_fly := sin(phase * TAU + 1.2) * 5.0
	var forward_lean := deg_to_rad(6.0)

	_draw_ground_shadow(Vector2(0, 32), 16.0 + step_lift * 0.4, 4.5, 0.45)

	match angle:
		Angle.FRONT:
			_draw_nail(Vector2(-2, -10 + step_lift), deg_to_rad(-24.0))
			_draw_cloak_front(step_lift, cloak_fly)
			_draw_chest_pearl(step_lift)
			_draw_head_front(step_lift, 0.0)
		Angle.SIDE:
			# 奔跑大前倾，披风如蝉翼向后剧烈展开
			_draw_cloak_side(step_lift, cloak_fly, 8.0)
			_draw_head_side(step_lift, 0.05)
			# 奔跑时骨钉在身侧上下轻颠
			var nail_bob := cos(phase * TAU) * 3.0
			_draw_nail(Vector2(14, 10 + step_lift + nail_bob), deg_to_rad(55.0 + forward_lean))
		Angle.BACK:
			_draw_nail(Vector2(0, 0 + step_lift), deg_to_rad(-8.0))
			_draw_cloak_back(step_lift, cloak_fly)
			_draw_head_back(step_lift)

# ==================== 3. 冲刺 (DASH) ====================

func _draw_dash(angle: Angle, progress: float) -> void:
	# 空洞骑士经典的「蛾翼冲刺」：极低重心大俯冲、纯白月光轨迹
	var dash_y := 6.0
	var stretch := 1.25

	# 冲刺虚空残影（2 段淡出虚影）
	for i in [1, 2]:
		var lag := float(i) * 14.0
		draw_filled_ellipse(Vector2(-lag, dash_y + 24), 16.0, 4.0, Color(col_cloak_outer.r, col_cloak_outer.g, col_cloak_outer.b, 0.18 / float(i)))

	# 脚底极速气旋
	draw_filled_ellipse(Vector2(0, 32), 22.0, 4.0, Color(0.04, 0.06, 0.09, 0.6))
	draw_line(Vector2(-20, 31), Vector2(16, 31), col_eye_core, 1.2)

	match angle:
		Angle.FRONT:
			_draw_nail(Vector2(-2, -8 + dash_y), deg_to_rad(-30.0))
			_draw_cloak_front(dash_y, 6.0)
			_draw_chest_pearl(dash_y)
			_draw_head_front(dash_y, 0.2)
		Angle.SIDE:
			# 侧向蛾翼冲刺：身形拉长，披风像一道锋利薄刃割裂空气
			_draw_cloak_dash_side(dash_y)
			_draw_head_side(dash_y, 0.3)
			# 纯白冷月眼眸拉出长长光芒轨迹 (Trail)
			draw_line(Vector2(6, -14 + dash_y), Vector2(-22, -14 + dash_y), Color(col_eye_core.r, col_eye_core.g, col_eye_core.b, 0.8), 2.4)
			draw_soft_glow(Vector2(-8, -14 + dash_y), 8.0, col_eye_glow, 2)
			# 骨钉笔直前突平刺！
			_draw_nail(Vector2(26, dash_y + 2), deg_to_rad(85.0))
		Angle.BACK:
			_draw_nail(Vector2(0, dash_y), deg_to_rad(-12.0))
			_draw_cloak_back(dash_y, 6.0)
			_draw_head_back(dash_y)

# ==================== 4. 攻击斩击 (ATTACK) ====================

func _draw_attack(angle: Angle, progress: float) -> void:
	# 挥出空洞骑士标志性的「冷月月牙斩痕 (Pale Crescent Slash)」
	var float_y := sin(_time * 2.8) * 1.5

	match angle:
		Angle.FRONT:
			_draw_nail(Vector2(-2, -10 + float_y), deg_to_rad(-24.0))
			_draw_cloak_front(float_y, 2.0)
			_draw_chest_pearl(float_y)
			_draw_head_front(float_y, 0.15)
			# 正面斜向斩弧
			_draw_slash_crescent(Vector2(10, 6), deg_to_rad(-20.0), 32.0, progress)
		Angle.SIDE:
			_draw_cloak_side(float_y, 2.0, 0.0)
			_draw_head_side(float_y, 0.2)
			# 侧身下劈/横扫挥出的巨型冷月斩弧
			var slash_pos := Vector2(22, 2)
			_draw_slash_crescent(slash_pos, deg_to_rad(10.0), 36.0, progress)
			# 顺势挥出的骨钉
			var nail_angle := lerp_angle(deg_to_rad(-30.0), deg_to_rad(85.0), clampf(progress * 1.5, 0.0, 1.0))
			_draw_nail(Vector2(14, 6), nail_angle)
		Angle.BACK:
			_draw_cloak_back(float_y, 2.0)
			_draw_head_back(float_y)
			_draw_slash_crescent(Vector2(-10, 6), deg_to_rad(160.0), 32.0, progress)

# ==================== 5. 受击 (HIT) ====================

func _draw_hit(angle: Angle, progress: float) -> void:
	# 受击硬直：后缩形变、披风紧裹、白霜护体闪白
	var knock_back := -progress * 4.0
	var hit_flash := (1.0 - progress) * 0.85

	_draw_ground_shadow(Vector2(knock_back, 32), 16.0, 4.0, 0.5)

	# 绘制人物本体（附带白霜闪光遮罩）
	match angle:
		Angle.FRONT:
			_draw_cloak_front(0.0, -3.0)
			_draw_head_front(0.0, 0.4)
			_draw_chest_pearl(0.0)
		Angle.SIDE:
			_draw_cloak_side(0.0, -4.0, -4.0)
			_draw_head_side(0.0, 0.4)
		Angle.BACK:
			_draw_cloak_back(0.0, -3.0)
			_draw_head_back(0.0)

	# 受击白光微粒震颤
	if hit_flash > 0.05:
		draw_soft_glow(Vector2(0, 0), 24.0, Color(1.0, 1.0, 1.0, hit_flash * 0.4), 2)
		draw_circle(Vector2(0, -10), 12.0, Color(1.0, 1.0, 1.0, hit_flash * 0.35))

# ==================== 细分绘制构件函数 ====================

func _draw_ground_shadow(pos: Vector2, rx: float, ry: float, alpha: float) -> void:
	draw_filled_ellipse(pos, rx, ry, Color(0.04, 0.05, 0.08, alpha))
	draw_arc(pos, rx + 2.0, 0, TAU, 28, Color(col_cloak_edge.r, col_cloak_edge.g, col_cloak_edge.b, alpha * 0.35), 1.2, true)

func _draw_head_front(float_y: float, eye_pulse: float) -> void:
	var head_center := Vector2(0, -15 + float_y)
	_draw_butterfly_horns(head_center)

	# 骨面主轮廓（优雅鹅蛋尖下巴）
	var mask_pts: PackedVector2Array = [
		head_center + Vector2(-9.5, -4),
		head_center + Vector2(-8, 6),
		head_center + Vector2(0, 10.0),
		head_center + Vector2(8, 6),
		head_center + Vector2(9.5, -4),
		head_center + Vector2(0, -9)
	]
	draw_colored_polygon(mask_pts, col_bone)
	draw_polyline(mask_pts, col_bone_shadow, 1.2, true)

	# 双眼深渊凹陷与三层月辉
	var l_eye := head_center + Vector2(-4.2, 1.0)
	var r_eye := head_center + Vector2(4.2, 1.0)
	draw_filled_ellipse(l_eye, 3.8, 5.2, col_void)
	draw_filled_ellipse(r_eye, 3.8, 5.2, col_void)

	draw_soft_glow(l_eye, 6.0, Color(col_eye_glow.r, col_eye_glow.g, col_eye_glow.b, col_eye_glow.a + eye_pulse), 3)
	draw_soft_glow(r_eye, 6.0, Color(col_eye_glow.r, col_eye_glow.g, col_eye_glow.b, col_eye_glow.a + eye_pulse), 3)

	draw_filled_ellipse(l_eye + Vector2(0.2, -0.2), 2.4, 3.8, col_eye_core)
	draw_filled_ellipse(r_eye + Vector2(-0.2, -0.2), 2.4, 3.8, col_eye_core)

func _draw_head_side(float_y: float, eye_pulse: float) -> void:
	var head_center := Vector2(2, -15 + float_y)
	var mask_pts: PackedVector2Array = [
		head_center + Vector2(-7, -4),
		head_center + Vector2(-5, 6),
		head_center + Vector2(3, 10.0),
		head_center + Vector2(9, 3),
		head_center + Vector2(7, -6),
		head_center + Vector2(0, -9)
	]
	draw_colored_polygon(mask_pts, col_bone)

	# 侧面后仰仙角
	var horn_pts: PackedVector2Array = [
		head_center + Vector2(-3, -6),
		head_center + Vector2(-12, -18),
		head_center + Vector2(-16, -29),
		head_center + Vector2(-6, -21),
		head_center + Vector2(2, -8)
	]
	draw_colored_polygon(horn_pts, col_bone)
	draw_colored_polygon(PackedVector2Array([
		head_center + Vector2(-3, -6),
		head_center + Vector2(-12, -18),
		head_center + Vector2(-16, -29),
		head_center + Vector2(-8, -17)
	]), col_bone_shadow)

	# 侧面深渊眼眸
	var eye_pos := head_center + Vector2(4.5, 1.0)
	draw_filled_ellipse(eye_pos, 3.8, 5.2, col_void)
	draw_soft_glow(eye_pos, 6.5, Color(col_eye_glow.r, col_eye_glow.g, col_eye_glow.b, col_eye_glow.a + eye_pulse), 3)
	draw_filled_ellipse(eye_pos + Vector2(0.3, -0.2), 2.4, 4.0, col_eye_core)

func _draw_head_back(float_y: float) -> void:
	var head_center := Vector2(0, -15 + float_y)
	draw_circle(head_center, 9.5, col_bone)
	draw_arc(head_center, 9.5, 0, TAU, 24, col_bone_shadow, 1.2, true)
	_draw_butterfly_horns(head_center)

func _draw_butterfly_horns(head_center: Vector2) -> void:
	var l_horn: PackedVector2Array = [
		head_center + Vector2(-6, -4),
		head_center + Vector2(-14, -18),
		head_center + Vector2(-12, -28),
		head_center + Vector2(-6, -20),
		head_center + Vector2(-3, -8)
	]
	draw_colored_polygon(l_horn, col_bone)
	draw_colored_polygon(PackedVector2Array([
		head_center + Vector2(-6, -4),
		head_center + Vector2(-14, -18),
		head_center + Vector2(-12, -28),
		head_center + Vector2(-10, -18)
	]), col_bone_shadow)

	var r_horn: PackedVector2Array = [
		head_center + Vector2(3, -8),
		head_center + Vector2(6, -20),
		head_center + Vector2(12, -28),
		head_center + Vector2(14, -18),
		head_center + Vector2(6, -4)
	]
	draw_colored_polygon(r_horn, col_bone)
	draw_colored_polygon(PackedVector2Array([
		head_center + Vector2(3, -8),
		head_center + Vector2(6, -20),
		head_center + Vector2(12, -28),
		head_center + Vector2(10, -18)
	]), col_bone_shadow)

func _draw_cloak_front(float_y: float, wave: float) -> void:
	# 双层墨绿蝉翼长披风
	var inner_cloak: PackedVector2Array = [
		Vector2(0, -4 + float_y),
		Vector2(-16, 12 + float_y),
		Vector2(-15 + wave * 0.3, 30 + float_y),
		Vector2(0, 27 + float_y),
		Vector2(15 - wave * 0.3, 30 + float_y),
		Vector2(16, 12 + float_y)
	]
	draw_colored_polygon(inner_cloak, col_cloak_inner)

	var outer_cloak: PackedVector2Array = [
		Vector2(0, -6 + float_y),
		Vector2(-9, -2 + float_y),
		Vector2(-14, 15 + float_y),
		Vector2(-12 + wave * 0.4, 28 + float_y),
		Vector2(-7, 24 + float_y),
		Vector2(-3, 31 + float_y),
		Vector2(2, 26 + float_y),
		Vector2(8 + wave * 0.3, 29 + float_y),
		Vector2(14, 15 + float_y),
		Vector2(9, -2 + float_y)
	]
	draw_colored_polygon(outer_cloak, col_cloak_outer)
	draw_polyline(outer_cloak, col_cloak_edge, 1.2, true)

func _draw_cloak_side(float_y: float, wave: float, extra_drag: float) -> void:
	var drag := extra_drag
	var cloak_pts: PackedVector2Array = [
		Vector2(2, -6 + float_y),
		Vector2(-4, 0 + float_y),
		Vector2(-15 - drag * 0.4 + wave, 12 + float_y),
		Vector2(-20 - drag + wave * 1.3, 29 + float_y),
		Vector2(-9 - drag * 0.5 + wave * 0.7, 26 + float_y),
		Vector2(-2, 30 + float_y),
		Vector2(6, 18 + float_y),
		Vector2(6, 0 + float_y)
	]
	draw_colored_polygon(cloak_pts, col_cloak_outer)
	draw_polyline(cloak_pts, col_cloak_edge, 1.2, true)

func _draw_cloak_dash_side(dash_y: float) -> void:
	# 冲刺时披风笔直向后展平成刀锋形状
	var dash_pts: PackedVector2Array = [
		Vector2(4, -8 + dash_y),
		Vector2(-6, -4 + dash_y),
		Vector2(-32, 0 + dash_y),
		Vector2(-48, 6 + dash_y), # 极长破空后梢
		Vector2(-28, 12 + dash_y),
		Vector2(0, 14 + dash_y)
	]
	draw_colored_polygon(dash_pts, col_cloak_outer)
	draw_polyline(dash_pts, col_cloak_edge, 1.4, true)

func _draw_cloak_back(float_y: float, wave: float) -> void:
	var cloak_pts: PackedVector2Array = [
		Vector2(-9, -6 + float_y), Vector2(9, -6 + float_y),
		Vector2(16, 14 + float_y),
		Vector2(13 + wave * 0.4, 30 + float_y),
		Vector2(6, 26 + float_y),
		Vector2(0, 32 + float_y),
		Vector2(-6, 26 + float_y),
		Vector2(-14 - wave * 0.4, 30 + float_y),
		Vector2(-16, 14 + float_y)
	]
	draw_colored_polygon(cloak_pts, col_cloak_outer)
	draw_polyline(cloak_pts, col_cloak_edge, 1.2, true)

func _draw_chest_pearl(float_y: float) -> void:
	var chest_pos := Vector2(0, -3 + float_y)
	draw_soft_glow(chest_pos, 7.0, col_slash_glow, 2)
	draw_circle(chest_pos, 3.2, col_bone)
	draw_circle(chest_pos, 1.6, col_cloak_edge)

func _draw_nail(pos: Vector2, rot: float) -> void:
	var t := Transform2D(rot, pos)
	var nail_pts: PackedVector2Array = [
		t * Vector2(0, -36), # 极长剑尖
		t * Vector2(3.0, -26),
		t * Vector2(3.0, 13),
		t * Vector2(-3.0, 13),
		t * Vector2(-3.0, -26)
	]
	draw_colored_polygon(nail_pts, col_nail_white)
	# 剑脊阴影
	draw_colored_polygon(PackedVector2Array([
		t * Vector2(0, -36), t * Vector2(3.0, -26),
		t * Vector2(3.0, 13), t * Vector2(0, 13)
	]), col_nail_shadow)
	# 剑尖凝聚纯白星尘光点
	draw_circle(t * Vector2(0, -36), 2.2, Color.WHITE)
	draw_soft_glow(t * Vector2(0, -36), 6.0, col_eye_glow, 2)
	# 骨质剑柄
	draw_line(t * Vector2(0, 13), t * Vector2(0, 22), col_nail_white, 2.5)
	draw_circle(t * Vector2(0, 23), 2.6, col_nail_shadow)

## 绘制标志性的空洞骑士纯白冷月月牙斩弧 (Pale Crescent Slash)
func _draw_slash_crescent(pos: Vector2, rot: float, radius: float, progress: float) -> void:
	if progress <= 0.0 or progress >= 1.0:
		return
	var t := Transform2D(rot, pos)
	var alpha := (1.0 - progress) * 0.95
	var cur_radius := radius * (0.8 + progress * 0.3)

	# 外晕青玉光弧
	draw_soft_glow(pos + t * Vector2(cur_radius * 0.6, 0), 16.0, Color(col_slash_glow.r, col_slash_glow.g, col_slash_glow.b, alpha * 0.6), 3)

	# 核心纯白厚月牙斩痕
	var arc_start := deg_to_rad(-65.0)
	var arc_end := deg_to_rad(65.0)
	var arc_points := 24

	var outer_pts := PackedVector2Array()
	var inner_pts := PackedVector2Array()
	for i in range(arc_points + 1):
		var theta := lerpf(arc_start, arc_end, float(i) / float(arc_points))
		outer_pts.append(pos + t * Vector2(cos(theta) * cur_radius, sin(theta) * cur_radius))
		inner_pts.append(pos + t * Vector2(cos(theta) * (cur_radius - 8.0), sin(theta) * (cur_radius - 8.0)))

	inner_pts.reverse()
	var crescent_poly := outer_pts
	crescent_poly.append_array(inner_pts)
	draw_colored_polygon(crescent_poly, Color(col_slash_arc.r, col_slash_arc.g, col_slash_arc.b, alpha))
	draw_polyline(outer_pts, Color(1.0, 1.0, 1.0, alpha), 1.6, true)
