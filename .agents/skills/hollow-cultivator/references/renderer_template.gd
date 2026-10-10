class_name TemplateCultivatorRenderer
extends CultivatorRendererBase

## 【空洞骑士风修士渲染器模板】
## 复制此模板创建新角色（例如 StyleShiyueRenderer / StyleFuzhenRenderer）
## 覆盖 5 大动作状态 × 3 大视角，保持纯代码抗锯齿矢量绘制

# 1. 角色专属色盘（可在 _init 中从 config.palette 同步，也可直接定制）
var col_void: Color = Color(0.06, 0.07, 0.10)
var col_bone: Color = Color(0.96, 0.97, 0.99)
var col_bone_shadow: Color = Color(0.76, 0.82, 0.88)
var col_eye_glow: Color = Color(0.75, 0.92, 1.0, 0.45)
var col_eye_core: Color = Color(0.98, 1.0, 1.0)
var col_cloak_outer: Color = Color(0.12, 0.22, 0.16) # 道统主色
var col_cloak_inner: Color = Color(0.18, 0.36, 0.26)
var col_cloak_edge: Color = Color(0.30, 0.60, 0.45)
var col_weapon_main: Color = Color(0.95, 0.97, 1.0)
var col_weapon_shadow: Color = Color(0.70, 0.78, 0.86)
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

# ==================== 1. 待机 (IDLE) ====================
func _draw_idle(angle: Angle) -> void:
	var float_y := sin(_time * 2.6) * 2.0
	var cloak_wave := sin(_time * 3.2) * 2.5
	var eye_pulse := sin(_time * 3.0) * 0.08
	_draw_ground_shadow(Vector2(0, 32), 18.0, 5.0, 0.5)

	match angle:
		Angle.FRONT:
			# 正面：骨钉大角度斜贯背负（右手拔剑工学，剑柄右肩上探，剑尖左腰下探）
			_draw_weapon(Vector2(1, -2 + float_y), deg_to_rad(152.0))
			_draw_cloak_front(float_y, cloak_wave)
			_draw_head_front(float_y, eye_pulse)
		Angle.SIDE:
			# 侧面：骨钉稳负后背！剑尖向后上方斜挑，绝不可拿在身前
			_draw_weapon(Vector2(-7, 2 + float_y), deg_to_rad(-24.0))
			_draw_cloak_side(float_y, cloak_wave, 0.0)
			_draw_head_side(float_y, eye_pulse)
		Angle.BACK:
			# 背面：骨钉绘制在斗篷最外层！黑白对比鲜明
			_draw_cloak_back(float_y, cloak_wave)
			_draw_weapon_strap(float_y)
			_draw_weapon(Vector2(1, -2 + float_y), deg_to_rad(152.0))
			_draw_head_back(float_y)

# ==================== 2. 移动 / 御风 (RUN / GLIDE) ====================
func _draw_run(angle: Angle, _phase: float, _air_val: float) -> void:
	# 仙人御风柔和波浪起伏 (1.6px 长波浮沉，严禁机械高频上下蹦跶)
	var wave_t := _time * 4.2
	var float_y := sin(wave_t) * 1.6
	var cloak_drag := clampf(speed_ratio, 0.4, 1.4) * 9.0
	var cloak_wave := cos(wave_t) * 4.0 + sin(_time * 8.5) * 1.4
	var forward_lean := deg_to_rad(4.5)
	_draw_ground_shadow(Vector2(0, 32), 16.0 - sin(wave_t) * 0.8, 4.5, 0.45 - sin(wave_t) * 0.06)

	match angle:
		Angle.FRONT:
			_draw_weapon(Vector2(1, -2 + float_y), deg_to_rad(152.0))
			_draw_cloak_front(float_y, cloak_wave)
			_draw_head_front(float_y, 0.0)
		Angle.SIDE:
			_draw_weapon(Vector2(-7, 2 + float_y), deg_to_rad(-24.0 + forward_lean))
			_draw_cloak_side(float_y, cloak_wave, cloak_drag)
			_draw_head_side(float_y, 0.05)
		Angle.BACK:
			_draw_cloak_back(float_y, cloak_wave)
			_draw_weapon_strap(float_y)
			_draw_weapon(Vector2(1, -2 + float_y), deg_to_rad(152.0))
			_draw_head_back(float_y)

# ==================== 3. 冲刺 (DASH) ====================
func _draw_dash(angle: Angle, progress: float) -> void:
	var dash_y := 6.0
	for i in [1, 2]:
		var lag := float(i) * 14.0
		draw_filled_ellipse(Vector2(-lag, dash_y + 24), 16.0, 4.0, Color(col_cloak_outer.r, col_cloak_outer.g, col_cloak_outer.b, 0.18 / float(i)))

	draw_filled_ellipse(Vector2(0, 32), 22.0, 4.0, Color(0.04, 0.06, 0.09, 0.6))
	draw_line(Vector2(-20, 31), Vector2(16, 31), col_eye_core, 1.2)

	match angle:
		Angle.FRONT:
			_draw_weapon(Vector2(3, 5 + dash_y), deg_to_rad(-140.0))
			_draw_cloak_front(dash_y, 6.0)
			_draw_head_front(dash_y, 0.2)
		Angle.SIDE:
			_draw_cloak_dash_side(dash_y)
			_draw_head_side(dash_y, 0.3)
			# 纯白冷月眼眸轨迹
			draw_line(Vector2(6, -14 + dash_y), Vector2(-22, -14 + dash_y), Color(col_eye_core.r, col_eye_core.g, col_eye_core.b, 0.8), 2.4)
			draw_soft_glow(Vector2(-8, -14 + dash_y), 8.0, col_eye_glow, 2)
			# 兵刃出鞘平刺！
			_draw_weapon(Vector2(26, dash_y + 2), deg_to_rad(85.0))
		Angle.BACK:
			_draw_cloak_back(dash_y, 6.0)
			_draw_weapon_strap(dash_y)
			_draw_weapon(Vector2(3, 5 + dash_y), deg_to_rad(-140.0))
			_draw_head_back(dash_y)

# ==================== 4. 斩击 (ATTACK) ====================
func _draw_attack(angle: Angle, progress: float) -> void:
	var float_y := sin(_time * 2.8) * 1.5
	match angle:
		Angle.FRONT:
			_draw_weapon(Vector2(1, -2 + float_y), deg_to_rad(152.0))
			_draw_cloak_front(float_y, 2.0)
			_draw_head_front(float_y, 0.15)
			_draw_slash_crescent(Vector2(14, 6), deg_to_rad(-20.0), 34.0, progress)
		Angle.SIDE:
			_draw_cloak_side(float_y, 2.0, 0.0)
			_draw_head_side(float_y, 0.2)
			var slash_pos := Vector2(22, 2)
			_draw_slash_crescent(slash_pos, deg_to_rad(10.0), 36.0, progress)
			var w_angle := lerp_angle(deg_to_rad(-30.0), deg_to_rad(85.0), clampf(progress * 1.5, 0.0, 1.0))
			_draw_weapon(Vector2(14, 6), w_angle)
		Angle.BACK:
			_draw_cloak_back(float_y, 2.0)
			_draw_weapon_strap(float_y)
			_draw_weapon(Vector2(1, -2 + float_y), deg_to_rad(152.0))
			_draw_head_back(float_y)
			_draw_slash_crescent(Vector2(-12, 4), deg_to_rad(160.0), 34.0, progress)

# ==================== 5. 受击 (HIT) ====================
func _draw_hit(angle: Angle, progress: float) -> void:
	var knock_back := -progress * 4.0
	var hit_flash := (1.0 - progress) * 0.85
	_draw_ground_shadow(Vector2(knock_back, 32), 16.0, 4.0, 0.5)

	match angle:
		Angle.FRONT:
			_draw_weapon(Vector2(-1, 3), deg_to_rad(-140.0))
			_draw_cloak_front(0.0, -3.0)
			_draw_head_front(0.0, 0.4)
		Angle.SIDE:
			_draw_weapon(Vector2(-6, 6), deg_to_rad(-22.0))
			_draw_cloak_side(0.0, -4.0, -4.0)
			_draw_head_side(0.0, 0.4)
		Angle.BACK:
			_draw_cloak_back(0.0, -3.0)
			_draw_weapon_strap(0.0)
			_draw_weapon(Vector2(-1, 3), deg_to_rad(-140.0))
			_draw_head_back(0.0)

	if hit_flash > 0.05:
		draw_soft_glow(Vector2(0, 0), 24.0, Color(1.0, 1.0, 1.0, hit_flash * 0.4), 2)
		draw_circle(Vector2(0, -10), 12.0, Color(1.0, 1.0, 1.0, hit_flash * 0.35))

# ==================== 具体构件实现（根据新角色修改） ====================
func _draw_ground_shadow(pos: Vector2, rx: float, ry: float, alpha: float) -> void:
	draw_filled_ellipse(pos, rx, ry, Color(0.04, 0.05, 0.08, alpha))
	draw_arc(pos, rx + 2.0, 0, TAU, 28, Color(col_cloak_edge.r, col_cloak_edge.g, col_cloak_edge.b, alpha * 0.35), 1.2, true)

func _draw_head_front(float_y: float, eye_pulse: float) -> void:
	var head_center := Vector2(0, -15 + float_y)
	_draw_horns(head_center)
	var mask_pts: PackedVector2Array = [
		head_center + Vector2(-9.5, -4), head_center + Vector2(-8, 6),
		head_center + Vector2(0, 10.0), head_center + Vector2(8, 6),
		head_center + Vector2(9.5, -4), head_center + Vector2(0, -9)
	]
	draw_colored_polygon(mask_pts, col_bone)
	draw_polyline(mask_pts, col_bone_shadow, 1.2, true)
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
		head_center + Vector2(-7, -4), head_center + Vector2(-5, 6),
		head_center + Vector2(3, 10.0), head_center + Vector2(9, 3),
		head_center + Vector2(7, -6), head_center + Vector2(0, -9)
	]
	draw_colored_polygon(mask_pts, col_bone)
	_draw_side_horns(head_center)
	var eye_pos := head_center + Vector2(4.5, 1.0)
	draw_filled_ellipse(eye_pos, 3.8, 5.2, col_void)
	draw_soft_glow(eye_pos, 6.5, Color(col_eye_glow.r, col_eye_glow.g, col_eye_glow.b, col_eye_glow.a + eye_pulse), 3)
	draw_filled_ellipse(eye_pos + Vector2(0.3, -0.2), 2.4, 4.0, col_eye_core)

func _draw_head_back(float_y: float) -> void:
	var head_center := Vector2(0, -15 + float_y)
	draw_circle(head_center, 9.5, col_bone)
	draw_arc(head_center, 9.5, 0, TAU, 24, col_bone_shadow, 1.2, true)
	_draw_horns(head_center)

func _draw_horns(head_center: Vector2) -> void:
	# 默认蝶羽角，子类根据道统个性化替换
	var l_horn: PackedVector2Array = [
		head_center + Vector2(-6, -4), head_center + Vector2(-14, -18),
		head_center + Vector2(-12, -28), head_center + Vector2(-6, -20), head_center + Vector2(-3, -8)
	]
	draw_colored_polygon(l_horn, col_bone)
	var r_horn: PackedVector2Array = [
		head_center + Vector2(3, -8), head_center + Vector2(6, -20),
		head_center + Vector2(12, -28), head_center + Vector2(14, -18), head_center + Vector2(6, -4)
	]
	draw_colored_polygon(r_horn, col_bone)

func _draw_side_horns(head_center: Vector2) -> void:
	var horn_pts: PackedVector2Array = [
		head_center + Vector2(-3, -6), head_center + Vector2(-12, -18),
		head_center + Vector2(-16, -29), head_center + Vector2(-6, -21), head_center + Vector2(2, -8)
	]
	draw_colored_polygon(horn_pts, col_bone)

func _draw_cloak_front(float_y: float, wave: float) -> void:
	var inner: PackedVector2Array = [
		Vector2(0, -4 + float_y), Vector2(-16, 12 + float_y),
		Vector2(-15 + wave * 0.3, 30 + float_y), Vector2(0, 27 + float_y),
		Vector2(15 - wave * 0.3, 30 + float_y), Vector2(16, 12 + float_y)
	]
	draw_colored_polygon(inner, col_cloak_inner)
	var outer: PackedVector2Array = [
		Vector2(0, -6 + float_y), Vector2(-9, -2 + float_y), Vector2(-14, 15 + float_y),
		Vector2(-12 + wave * 0.4, 28 + float_y), Vector2(-7, 24 + float_y),
		Vector2(-3, 31 + float_y), Vector2(2, 26 + float_y),
		Vector2(8 + wave * 0.3, 29 + float_y), Vector2(14, 15 + float_y), Vector2(9, -2 + float_y)
	]
	draw_colored_polygon(outer, col_cloak_outer)
	draw_polyline(outer, col_cloak_edge, 1.2, true)

func _draw_cloak_side(float_y: float, wave: float, extra_drag: float) -> void:
	var drag := extra_drag
	var cloak_pts: PackedVector2Array = [
		Vector2(2, -6 + float_y), Vector2(-4, 0 + float_y),
		Vector2(-15 - drag * 0.4 + wave, 12 + float_y),
		Vector2(-20 - drag + wave * 1.3, 29 + float_y),
		Vector2(-9 - drag * 0.5 + wave * 0.7, 26 + float_y),
		Vector2(-2, 30 + float_y), Vector2(6, 18 + float_y), Vector2(6, 0 + float_y)
	]
	draw_colored_polygon(cloak_pts, col_cloak_outer)
	draw_polyline(cloak_pts, col_cloak_edge, 1.2, true)

func _draw_cloak_dash_side(dash_y: float) -> void:
	var dash_pts: PackedVector2Array = [
		Vector2(4, -8 + dash_y), Vector2(-6, -4 + dash_y),
		Vector2(-32, 0 + dash_y), Vector2(-48, 6 + dash_y),
		Vector2(-28, 12 + dash_y), Vector2(0, 14 + dash_y)
	]
	draw_colored_polygon(dash_pts, col_cloak_outer)
	draw_polyline(dash_pts, col_cloak_edge, 1.4, true)

func _draw_cloak_back(float_y: float, wave: float) -> void:
	var cloak_pts: PackedVector2Array = [
		Vector2(-9, -6 + float_y), Vector2(9, -6 + float_y), Vector2(16, 14 + float_y),
		Vector2(13 + wave * 0.4, 30 + float_y), Vector2(6, 26 + float_y),
		Vector2(0, 32 + float_y), Vector2(-6, 26 + float_y),
		Vector2(-14 - wave * 0.4, 30 + float_y), Vector2(-16, 14 + float_y)
	]
	draw_colored_polygon(cloak_pts, col_cloak_outer)
	draw_polyline(cloak_pts, col_cloak_edge, 1.2, true)

func _draw_weapon_strap(float_y: float) -> void:
	var p_top := Vector2(7, -6 + float_y)
	var p_bot := Vector2(-5, 12 + float_y)
	draw_line(p_top, p_bot, Color(0.05, 0.08, 0.12, 0.95), 2.4)
	draw_line(p_top, p_bot, col_cloak_edge, 0.8)
	var center := (p_top + p_bot) * 0.5
	draw_circle(center, 2.4, col_bone)
	draw_circle(center, 1.2, col_void)

func _draw_weapon(pos: Vector2, rot: float) -> void:
	var t := Transform2D(rot, pos)
	# 小巧精致的纯白骨质神兵（总长约 26px，紧凑利落，绝不拖出斗篷底部）
	var nail_pts: PackedVector2Array = [
		t * Vector2(0, -15), t * Vector2(2.4, -9),
		t * Vector2(2.0, 3), t * Vector2(-2.0, 3), t * Vector2(-2.4, -9)
	]
	draw_colored_polygon(nail_pts, col_weapon_main)
	draw_colored_polygon(PackedVector2Array([
		t * Vector2(0, -15), t * Vector2(2.4, -9),
		t * Vector2(2.0, 3), t * Vector2(0, 3)
	]), col_weapon_shadow)
	draw_line(t * Vector2(0, -13), t * Vector2(0, 2), Color(1.0, 1.0, 1.0, 0.9), 1.0)
	var guard_pts: PackedVector2Array = [
		t * Vector2(-3.0, 3), t * Vector2(3.0, 3),
		t * Vector2(2.2, 5.5), t * Vector2(-2.2, 5.5)
	]
	draw_colored_polygon(guard_pts, col_bone_shadow)
	draw_line(t * Vector2(0, 5.5), t * Vector2(0, 10.5), col_weapon_main, 2.0)
	draw_circle(t * Vector2(0, 11), 1.6, col_weapon_main)
	draw_circle(t * Vector2(0, 11), 0.8, col_bone_shadow)

func _draw_slash_crescent(pos: Vector2, rot: float, radius: float, progress: float) -> void:
	if progress <= 0.0 or progress >= 1.0:
		return
	var t := Transform2D(rot, pos)
	var alpha := (1.0 - progress) * 0.95
	var cur_radius := radius * (0.8 + progress * 0.3)
	draw_soft_glow(pos + t * Vector2(cur_radius * 0.6, 0), 16.0, Color(col_slash_glow.r, col_slash_glow.g, col_slash_glow.b, alpha * 0.6), 3)
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
