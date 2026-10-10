class_name HollowKnightCultivatorRenderer
extends CultivatorRendererBase

## 通用模块化修仙角色渲染器（土豆兄弟式参数化驱动·高精仙侠版）
## 基于统一修仙素体与 4 大外观插槽（体型、面部、斗篷、武器），实现全道统角色的极速拓展与高辨识度差异化

# ----------------- 颜色缓存 -----------------
var col_void: Color = Color(0.06, 0.07, 0.10)
var col_bone: Color = Color(0.96, 0.97, 0.99)
var col_bone_shadow: Color = Color(0.76, 0.82, 0.88)
var col_eye_glow: Color = Color(0.75, 0.92, 1.0, 0.45)
var col_eye_core: Color = Color(0.98, 1.0, 1.0)
var col_cloak_outer: Color = Color(0.11, 0.24, 0.17)
var col_cloak_inner: Color = Color(0.18, 0.38, 0.28)
var col_cloak_edge: Color = Color(0.28, 0.62, 0.46)
var col_weapon_main: Color = Color(0.95, 0.97, 1.0)
var col_weapon_shadow: Color = Color(0.70, 0.78, 0.86)
var col_weapon_accent: Color = Color(1.0, 1.0, 1.0, 0.9)
var col_slash_arc: Color = Color(0.92, 0.98, 1.0, 0.95)
var col_slash_glow: Color = Color(0.40, 0.85, 0.70, 0.4)

# 修仙细节专属辅助色
var col_gold: Color = Color(0.96, 0.84, 0.32)
var col_gold_shadow: Color = Color(0.65, 0.48, 0.18)
var col_jade: Color = Color(0.58, 0.94, 0.80)
var col_tassel_red: Color = Color(0.88, 0.22, 0.18)

# ----------------- 插槽参数缓存 -----------------
var body_scale: float = 1.0
var width_scale: float = 1.0
var height_scale: float = 1.0
var head_scale: float = 1.0

var mask_style: String = "oval_chin"
var horns_style: String = "butterfly"
var eye_style: String = "hollow_oval"
var cloak_style: String = "split_flowing"
var chest_ornament: String = "pearl"
var weapon_type: String = "bone_nail"
var strap_style: String = "diagonal"

func _init(p_cfg: CultivatorVisualConfig = null) -> void:
	if p_cfg != null:
		config = p_cfg
	elif config == null:
		config = CultivatorVisualConfig.make_jianchi()
	_sync_config()

func _on_config_changed() -> void:
	_sync_config()

func _sync_config() -> void:
	if config == null:
		return

	# 1. 体型插槽
	var b_dict: Dictionary = config.body
	body_scale = float(b_dict.get("scale", 1.0))
	width_scale = float(b_dict.get("width_scale", 1.0))
	height_scale = float(b_dict.get("height_scale", 1.0))
	head_scale = float(b_dict.get("head_scale", 1.0))

	# 2. 面孔插槽
	var f_dict: Dictionary = config.face
	mask_style = String(f_dict.get("mask_style", "oval_chin"))
	horns_style = String(f_dict.get("horns_style", "butterfly"))
	eye_style = String(f_dict.get("eye_style", "hollow_oval"))
	col_eye_glow = f_dict.get("eye_color", Color(0.75, 0.92, 1.0, 0.45))
	col_eye_core = f_dict.get("eye_core_color", Color(0.98, 1.0, 1.0))

	# 3. 斗篷插槽
	var c_dict: Dictionary = config.cloak
	cloak_style = String(c_dict.get("cloak_style", "split_flowing"))
	chest_ornament = String(c_dict.get("chest_ornament", "pearl"))
	col_cloak_outer = c_dict.get("col_outer", Color(0.11, 0.24, 0.17))
	col_cloak_inner = c_dict.get("col_inner", Color(0.18, 0.38, 0.28))
	col_cloak_edge = c_dict.get("col_edge", Color(0.28, 0.62, 0.46))

	# 4. 武器插槽
	var w_dict: Dictionary = config.weapon
	weapon_type = String(w_dict.get("weapon_type", "bone_nail"))
	strap_style = String(w_dict.get("strap_style", "diagonal"))
	col_weapon_main = w_dict.get("col_main", Color(0.95, 0.97, 1.0))
	col_weapon_shadow = w_dict.get("col_shadow", Color(0.70, 0.78, 0.86))
	col_weapon_accent = w_dict.get("col_accent", Color(1.0, 1.0, 1.0, 0.9))

	# 骨玉基底
	col_bone = config.bone_white
	col_bone_shadow = config.bone_shadow
	col_void = config.void_black
	col_slash_glow = col_cloak_edge

	# 协调衍生细节色
	if cloak_style == "royal_shawl":
		col_gold = col_cloak_edge
	elif cloak_style == "tattered_rags":
		col_gold = Color(0.80, 0.70, 0.48)
	else:
		col_gold = Color(0.96, 0.84, 0.32)

## 动态设置视觉配置
func set_visual_config(cfg: CultivatorVisualConfig) -> void:
	config = cfg
	_sync_config()
	queue_redraw()

# ==================== 1. 待机 (IDLE) ====================

func _draw_idle(angle: Angle) -> void:
	var total_scale := Vector2(body_scale * width_scale, body_scale * height_scale)
	draw_set_transform(Vector2.ZERO, 0.0, total_scale)

	var float_y := sin(_time * 2.6) * 1.8
	var cloak_wave := sin(_time * 3.0) * 1.5
	var eye_pulse := sin(_time * 3.0) * 0.08

	_draw_ground_shadow(Vector2(0, 32), 17.0 * width_scale, 4.8, 0.48)
	_draw_immortal_motes(float_y)

	match angle:
		Angle.FRONT:
			_draw_modular_weapon(Vector2(6, -6 + float_y), deg_to_rad(22.0), Angle.FRONT)
			_draw_modular_cloak(float_y, cloak_wave, 0.0, Angle.FRONT)
			_draw_head_front(float_y, eye_pulse)
		Angle.SIDE:
			_draw_modular_weapon(Vector2(-5, 1 + float_y), deg_to_rad(-16.0), Angle.SIDE)
			_draw_modular_cloak(float_y, cloak_wave, 0.0, Angle.SIDE)
			_draw_head_side(float_y, eye_pulse)
		Angle.BACK:
			_draw_modular_cloak(float_y, cloak_wave, 0.0, Angle.BACK)
			_draw_modular_strap(float_y)
			_draw_modular_weapon(Vector2(1, -2 + float_y), deg_to_rad(152.0), Angle.BACK)
			_draw_head_back(float_y)

# ==================== 2. 奔跑 / 御风飞行 (RUN / GLIDE) ====================

func _draw_run(angle: Angle, _phase: float, _air_val: float) -> void:
	var total_scale := Vector2(body_scale * width_scale, body_scale * height_scale)
	draw_set_transform(Vector2.ZERO, 0.0, total_scale)

	var wave_t := _time * 5.2
	var float_y := sin(wave_t) * 2.4
	# 风阻波动与双频斗篷衣摆，营造灵动御风感
	var cloak_drag := clampf(speed_ratio, 0.4, 1.4) * 2.8
	var cloak_wave := cos(wave_t) * 2.8 + sin(_time * 9.5) * 0.9

	var shadow_alpha := 0.44 - sin(wave_t) * 0.07
	var shadow_rx := (16.5 - sin(wave_t) * 1.1) * width_scale
	_draw_ground_shadow(Vector2(0, 32), shadow_rx, 4.4, shadow_alpha)
	_draw_immortal_motes(float_y)

	match angle:
		Angle.FRONT:
			_draw_modular_weapon(Vector2(6, -6 + float_y * 0.85), deg_to_rad(22.0 + sin(wave_t) * 2.5), Angle.FRONT)
			_draw_modular_cloak(float_y, cloak_wave, cloak_drag, Angle.FRONT)
			_draw_head_front(float_y, 0.06)
		Angle.SIDE:
			_draw_modular_weapon(Vector2(-5, 1 + float_y), deg_to_rad(-15.0), Angle.SIDE)
			_draw_modular_cloak(float_y, cloak_wave, cloak_drag, Angle.SIDE)
			_draw_head_side(float_y, 0.05)
			_draw_eye_trail(float_y)
		Angle.BACK:
			_draw_modular_cloak(float_y, cloak_wave, 0.0, Angle.BACK)
			_draw_modular_strap(float_y)
			_draw_modular_weapon(Vector2(1, -2 + float_y), deg_to_rad(152.0), Angle.BACK)
			_draw_head_back(float_y)

# ==================== 3. 冲刺 (DASH) ====================

func _draw_dash(angle: Angle, progress: float) -> void:
	var total_scale := Vector2(body_scale * width_scale, body_scale * height_scale)
	draw_set_transform(Vector2.ZERO, 0.0, total_scale)

	var dash_y := 4.0
	for i in [1, 2]:
		var lag := float(i) * 12.0
		draw_filled_ellipse(Vector2(-lag, dash_y + 24), 16.0 * width_scale, 3.8, Color(col_cloak_outer.r, col_cloak_outer.g, col_cloak_outer.b, 0.16 / float(i)))

	draw_filled_ellipse(Vector2(0, 32), 20.0 * width_scale, 3.8, Color(0.04, 0.06, 0.09, 0.55))
	draw_line(Vector2(-18, 31), Vector2(14, 31), col_eye_core, 1.0)

	match angle:
		Angle.FRONT:
			_draw_modular_weapon(Vector2(7, -5 + dash_y), deg_to_rad(30.0), Angle.FRONT)
			_draw_modular_cloak(dash_y, 0.0, 6.0, Angle.FRONT)
			_draw_head_front(dash_y + 1, 0.3)
		Angle.SIDE:
			_draw_modular_weapon(Vector2(8, 7 + dash_y), deg_to_rad(65.0), Angle.SIDE)
			_draw_cloak_dash_side(dash_y)
			_draw_head_side(dash_y + 2, 0.45)
			draw_line(Vector2(8, -5 + dash_y), Vector2(-22, -5 + dash_y), col_eye_glow, 1.8)
		Angle.BACK:
			_draw_modular_cloak(dash_y, 0.0, 6.0, Angle.BACK)
			_draw_modular_strap(dash_y)
			_draw_modular_weapon(Vector2(3, 4 + dash_y), deg_to_rad(144.0), Angle.BACK)
			_draw_head_back(dash_y + 1)

# ==================== 4. 攻击挥剑 (ATTACK) ====================

func _draw_attack(angle: Angle, progress: float) -> void:
	var total_scale := Vector2(body_scale * width_scale, body_scale * height_scale)
	draw_set_transform(Vector2.ZERO, 0.0, total_scale)

	var float_y := sin(progress * PI) * -2.8
	_draw_ground_shadow(Vector2(0, 32), 19.0 * width_scale, 5.0, 0.55)

	match angle:
		Angle.FRONT:
			_draw_modular_weapon(Vector2(6, -6 + float_y), deg_to_rad(22.0), Angle.FRONT)
			_draw_modular_cloak(float_y, 2.5, 0.0, Angle.FRONT)
			_draw_head_front(float_y, 0.25)
			_draw_slash_crescent(Vector2(0, 12 + float_y), deg_to_rad(90.0), 38.0, progress)
		Angle.SIDE:
			_draw_modular_cloak(float_y, 3.0, 2.0, Angle.SIDE)
			_draw_head_side(float_y, 0.25)
			var slash_rot := lerpf(deg_to_rad(-40.0), deg_to_rad(50.0), progress)
			_draw_modular_weapon(Vector2(14, 3 + float_y), slash_rot, Angle.SIDE)
			_draw_slash_crescent(Vector2(18, 2 + float_y), deg_to_rad(15.0), 42.0, progress)
		Angle.BACK:
			_draw_modular_cloak(float_y, 2.5, 0.0, Angle.BACK)
			_draw_modular_strap(float_y)
			_draw_modular_weapon(Vector2(-1, 2 + float_y), deg_to_rad(152.0), Angle.BACK)
			_draw_head_back(float_y)
			_draw_slash_crescent(Vector2(0, -8 + float_y), deg_to_rad(-90.0), 38.0, progress)

# ==================== 5. 受击硬直 (HIT) ====================

func _draw_hit(angle: Angle, progress: float) -> void:
	var total_scale := Vector2(body_scale * width_scale, body_scale * height_scale)
	draw_set_transform(Vector2.ZERO, 0.0, total_scale)

	var hit_flash := 1.0 - progress
	_draw_ground_shadow(Vector2(0, 32), 16.0 * width_scale, 3.8, 0.4)

	match angle:
		Angle.FRONT:
			_draw_modular_weapon(Vector2(6, -6), deg_to_rad(22.0), Angle.FRONT)
			_draw_modular_cloak(0.0, -2.0, 0.0, Angle.FRONT)
			_draw_head_front(0.0, 0.35)
		Angle.SIDE:
			_draw_modular_weapon(Vector2(-5, 4), deg_to_rad(-16.0), Angle.SIDE)
			_draw_modular_cloak(0.0, -2.0, -1.0, Angle.SIDE)
			_draw_head_side(0.0, 0.35)
		Angle.BACK:
			_draw_modular_cloak(0.0, -2.0, 0.0, Angle.BACK)
			_draw_modular_strap(0.0)
			_draw_modular_weapon(Vector2(-1, 2), deg_to_rad(-140.0), Angle.BACK)
			_draw_head_back(0.0)

	if hit_flash > 0.05:
		draw_soft_glow(Vector2(0, 0), 22.0, Color(1.0, 1.0, 1.0, hit_flash * 0.4), 2)
		draw_circle(Vector2(0, -10), 11.0, Color(1.0, 1.0, 1.0, hit_flash * 0.35))

# ==================== 辅助效果：地影与道韵灵气 ====================

func _draw_ground_shadow(pos: Vector2, rx: float, ry: float, alpha: float) -> void:
	draw_filled_ellipse(pos, rx, ry, Color(0.03, 0.04, 0.07, alpha))
	draw_filled_ellipse(pos, rx * 0.65, ry * 0.65, Color(0.02, 0.02, 0.04, alpha * 0.4))
	var edge_col := col_cloak_edge
	if cloak_shimmer_intensity > 0.05 and cloak_shimmer_color.a > 0.01:
		edge_col = col_cloak_edge.lerp(cloak_shimmer_color, clampf(cloak_shimmer_intensity, 0.0, 1.0))
	draw_arc(pos, rx + 1.8, 0, TAU, 28, Color(edge_col.r, edge_col.g, edge_col.b, alpha * 0.28), 1.0, true)

func _draw_immortal_motes(float_y: float) -> void:
	var eff_col := col_cloak_edge
	var eff_eye := col_eye_glow
	if cloak_shimmer_color.a > 0.01:
		eff_col = col_cloak_edge.lerp(cloak_shimmer_color, clampf(cloak_shimmer_intensity, 0.0, 1.0))
	if eye_override_color.a > 0.01:
		eff_eye = col_eye_glow.lerp(eye_override_color, clampf(eye_override_color.a, 0.0, 1.0))

	var speed_mul := 1.0 + motes_boost * 1.6
	var t1 := _time * 1.8 * speed_mul
	var mx1 := sin(t1) * (14.0 * width_scale)
	var my1 := cos(t1 * 1.2) * 8.0 + float_y + 8.0
	var alpha1 := (sin(_time * 2.2 * speed_mul) * 0.5 + 0.5) * (0.35 + motes_boost * 0.45)
	draw_circle(Vector2(mx1, my1), 1.0 + motes_boost * 0.6, Color(eff_col.r, eff_col.g, eff_col.b, alpha1))

	var t2 := _time * 2.3 * speed_mul + 2.1
	var mx2 := cos(t2) * (12.0 * width_scale)
	var my2 := sin(t2 * 1.4) * 7.0 + float_y - 2.0
	var alpha2 := (cos(_time * 2.5 * speed_mul) * 0.5 + 0.5) * (0.28 + motes_boost * 0.45)
	draw_circle(Vector2(mx2, my2), 0.9 + motes_boost * 0.6, Color(eff_eye.r, eff_eye.g, eff_eye.b, alpha2))

	# 技能爆发/法力激荡时，额外环绕 3 颗周天流光微粒子
	if motes_boost > 0.1:
		for i in range(3):
			var extra_t := _time * 3.6 + float(i) * (TAU / 3.0)
			var ex := sin(extra_t) * (18.0 * width_scale)
			var ey := cos(extra_t * 1.2) * 11.0 + float_y + 4.0
			var extra_a := (sin(extra_t * 2.4) * 0.35 + 0.65) * clampf(motes_boost, 0.0, 1.0) * 0.8
			draw_circle(Vector2(ex, ey), 1.2, Color(1.0, 1.0, 1.0, extra_a))
			var tail_dir := -Vector2(cos(extra_t) * 18.0, -sin(extra_t * 1.2) * 13.2).normalized()
			draw_line(Vector2(ex, ey), Vector2(ex, ey) + tail_dir * 5.0, Color(eff_col.r, eff_col.g, eff_col.b, extra_a * 0.65), 1.2)

func _draw_eye_trail(float_y: float) -> void:
	var eff_eye := col_eye_glow
	if eye_override_color.a > 0.01:
		eff_eye = col_eye_glow.lerp(eye_override_color, clampf(eye_override_color.a, 0.0, 1.0))
	var trail_len := 8.0 + (eye_glow_boost * 14.0)
	var eye_p := Vector2(2.5, -14.0 + float_y)
	var trail_alpha := 0.32 + eye_glow_boost * 0.35
	draw_line(eye_p, eye_p + Vector2(-trail_len, 1.0), Color(eff_eye.r, eff_eye.g, eff_eye.b, trail_alpha), 1.1 + eye_glow_boost * 0.8)
	if eye_glow_boost > 0.2:
		draw_line(eye_p, eye_p + Vector2(-trail_len * 0.55, 0.6), Color(1.0, 1.0, 1.0, trail_alpha * 0.9), 1.0)

# ==================== 头部与面具插槽绘制 ====================

func _draw_head_front(float_y: float, eye_pulse: float) -> void:
	var head_center := Vector2(0, -15 + float_y)
	_draw_modular_headwear(head_center, Angle.FRONT)
	_draw_modular_mask(head_center, Angle.FRONT)
	_draw_modular_eyes(head_center, Angle.FRONT, eye_pulse)

func _draw_head_side(float_y: float, eye_pulse: float) -> void:
	var head_center := Vector2(1.2, -15 + float_y)
	_draw_modular_headwear(head_center, Angle.SIDE)
	_draw_modular_mask(head_center, Angle.SIDE)
	_draw_modular_eyes(head_center, Angle.SIDE, eye_pulse)

func _draw_head_back(float_y: float) -> void:
	var head_center := Vector2(0, -15 + float_y)
	draw_circle(head_center, 9.5 * head_scale, col_bone)
	draw_arc(head_center, 9.5 * head_scale, 0, TAU, 24, col_bone_shadow, 1.2, true)
	draw_arc(head_center, 7.5 * head_scale, PI * 0.2, PI * 0.8, 16, Color(col_bone_shadow.r, col_bone_shadow.g, col_bone_shadow.b, 0.35), 1.0)
	_draw_modular_headwear(head_center, Angle.BACK)

## 插槽 1：面壳轮廓绘制
func _draw_modular_mask(head_center: Vector2, angle: Angle) -> void:
	var hs := head_scale
	if angle == Angle.FRONT:
		var mask_pts: PackedVector2Array = []
		match mask_style:
			"square_rock":
				mask_pts = [
					head_center + Vector2(-11 * hs, -6 * hs),
					head_center + Vector2(-11 * hs, 5 * hs),
					head_center + Vector2(-5 * hs, 10 * hs),
					head_center + Vector2(5 * hs, 10 * hs),
					head_center + Vector2(11 * hs, 5 * hs),
					head_center + Vector2(11 * hs, -6 * hs),
					head_center + Vector2(0, -9 * hs)
				]
			"round_petite":
				mask_pts = [
					head_center + Vector2(-9 * hs, -4 * hs),
					head_center + Vector2(-9 * hs, 4 * hs),
					head_center + Vector2(-4 * hs, 9 * hs),
					head_center + Vector2(4 * hs, 9 * hs),
					head_center + Vector2(9 * hs, 4 * hs),
					head_center + Vector2(9 * hs, -4 * hs),
					head_center + Vector2(0, -8 * hs)
				]
			"sharp_fox":
				mask_pts = [
					head_center + Vector2(-9 * hs, -5 * hs),
					head_center + Vector2(-7 * hs, 3 * hs),
					head_center + Vector2(0, 11 * hs),
					head_center + Vector2(7 * hs, 3 * hs),
					head_center + Vector2(9 * hs, -5 * hs),
					head_center + Vector2(0, -10 * hs)
				]
			"stout_brute":
				mask_pts = [
					head_center + Vector2(-12 * hs, -5 * hs),
					head_center + Vector2(-12 * hs, 6 * hs),
					head_center + Vector2(-4 * hs, 11 * hs),
					head_center + Vector2(4 * hs, 11 * hs),
					head_center + Vector2(12 * hs, 6 * hs),
					head_center + Vector2(12 * hs, -5 * hs),
					head_center + Vector2(0, -8 * hs)
				]
			"oval_chin", _:
				mask_pts = [
					head_center + Vector2(-9.5 * hs, -6 * hs),
					head_center + Vector2(-9.0 * hs, 4 * hs),
					head_center + Vector2(0, 10 * hs),
					head_center + Vector2(9.0 * hs, 4 * hs),
					head_center + Vector2(9.5 * hs, -6 * hs),
					head_center + Vector2(0, -9 * hs)
				]

		draw_colored_polygon(mask_pts, col_bone)
		var shadow_cut: PackedVector2Array = [
			mask_pts[2], mask_pts[3], mask_pts[4],
			head_center + Vector2(4 * hs, 2 * hs),
			head_center + Vector2(0, 5 * hs)
		]
		draw_colored_polygon(shadow_cut, Color(col_bone_shadow.r, col_bone_shadow.g, col_bone_shadow.b, 0.35))
		draw_polyline(mask_pts, col_bone_shadow, 1.2, true)
		_draw_forehead_sigil(head_center, hs, Angle.FRONT)

	else:
		var side_mask: PackedVector2Array = []
		match mask_style:
			"square_rock":
				side_mask = [
					head_center + Vector2(-6 * hs, -8 * hs),
					head_center + Vector2(6 * hs, -5 * hs),
					head_center + Vector2(8 * hs, 4 * hs),
					head_center + Vector2(3 * hs, 10 * hs),
					head_center + Vector2(-4 * hs, 9 * hs),
					head_center + Vector2(-7 * hs, 0)
				]
			"round_petite":
				side_mask = [
					head_center + Vector2(-5 * hs, -7 * hs),
					head_center + Vector2(5 * hs, -4 * hs),
					head_center + Vector2(7 * hs, 3 * hs),
					head_center + Vector2(2 * hs, 8.5 * hs),
					head_center + Vector2(-4 * hs, 7 * hs),
					head_center + Vector2(-6 * hs, 0)
				]
			"sharp_fox":
				side_mask = [
					head_center + Vector2(-6 * hs, -8 * hs),
					head_center + Vector2(6 * hs, -4 * hs),
					head_center + Vector2(8.5 * hs, 2 * hs),
					head_center + Vector2(2 * hs, 10.5 * hs),
					head_center + Vector2(-4 * hs, 7 * hs),
					head_center + Vector2(-7 * hs, 0)
				]
			"stout_brute":
				side_mask = [
					head_center + Vector2(-7 * hs, -7 * hs),
					head_center + Vector2(7 * hs, -4 * hs),
					head_center + Vector2(9 * hs, 5 * hs),
					head_center + Vector2(3 * hs, 11 * hs),
					head_center + Vector2(-5 * hs, 9 * hs),
					head_center + Vector2(-8 * hs, 0)
				]
			"oval_chin", _:
				side_mask = [
					head_center + Vector2(-5.5 * hs, -8 * hs),
					head_center + Vector2(5.5 * hs, -5 * hs),
					head_center + Vector2(7.5 * hs, 3 * hs),
					head_center + Vector2(1.5 * hs, 9.5 * hs),
					head_center + Vector2(-4.5 * hs, 8 * hs),
					head_center + Vector2(-6.5 * hs, 0)
				]

		draw_colored_polygon(side_mask, col_bone)
		var cheek_pts: PackedVector2Array = [
			head_center + Vector2(-2 * hs, 1 * hs),
			side_mask[2], side_mask[3], side_mask[4]
		]
		draw_colored_polygon(cheek_pts, Color(col_bone_shadow.r, col_bone_shadow.g, col_bone_shadow.b, 0.4))
		draw_polyline(side_mask, col_bone_shadow, 1.2, true)
		_draw_forehead_sigil(head_center, hs, Angle.SIDE)

## 额间道统纹样微雕
func _draw_forehead_sigil(head_center: Vector2, hs: float, angle: Angle) -> void:
	if horns_style == "bamboo_hat":
		if angle == Angle.FRONT:
			draw_line(head_center + Vector2(-2.5 * hs, -5 * hs), head_center + Vector2(3.5 * hs, 4 * hs), Color(0.45, 0.48, 0.55), 1.2)
		else:
			draw_line(head_center + Vector2(1.0 * hs, -3 * hs), head_center + Vector2(4.5 * hs, 3 * hs), Color(0.45, 0.48, 0.55), 1.1)
		return

	if horns_style == "talisman":
		return

	match mask_style:
		"square_rock":
			if angle == Angle.FRONT:
				draw_line(head_center + Vector2(-2.5 * hs, -4.5 * hs), head_center + Vector2(2.5 * hs, -4.5 * hs), col_gold, 1.2)
				draw_line(head_center + Vector2(-1.5 * hs, -2.5 * hs), head_center + Vector2(1.5 * hs, -2.5 * hs), col_gold, 1.2)
			else:
				draw_line(head_center + Vector2(1.0 * hs, -4.5 * hs), head_center + Vector2(3.5 * hs, -4.5 * hs), col_gold, 1.1)

		"round_petite":
			var sigil_col := col_tassel_red if horns_style == "dao_bun" else col_gold
			if angle == Angle.FRONT:
				draw_circle(head_center + Vector2(0, -4.0 * hs), 1.1 * hs, sigil_col)
			else:
				draw_circle(head_center + Vector2(2.8 * hs, -3.5 * hs), 1.0 * hs, sigil_col)

		"sharp_fox":
			if angle == Angle.FRONT:
				draw_line(head_center + Vector2(0, -6 * hs), head_center + Vector2(0, -2 * hs), col_eye_glow, 1.1)
				draw_line(head_center + Vector2(-2 * hs, -5 * hs), head_center + Vector2(2 * hs, -5 * hs), col_eye_glow, 0.9)
			else:
				draw_line(head_center + Vector2(2.5 * hs, -5 * hs), head_center + Vector2(2.5 * hs, -2 * hs), col_eye_glow, 1.0)

		"stout_brute":
			if angle == Angle.FRONT:
				draw_line(head_center + Vector2(-2.5 * hs, -6 * hs), head_center + Vector2(2.5 * hs, -2 * hs), col_tassel_red, 1.2)
				draw_line(head_center + Vector2(2.5 * hs, -6 * hs), head_center + Vector2(-2.5 * hs, -2 * hs), col_tassel_red, 1.2)
			else:
				draw_line(head_center + Vector2(1.0 * hs, -5 * hs), head_center + Vector2(4.0 * hs, -2 * hs), col_tassel_red, 1.1)

		"oval_chin", _:
			if angle == Angle.FRONT:
				draw_line(head_center + Vector2(0, -6.5 * hs), head_center + Vector2(0, -2.5 * hs), col_eye_glow, 1.2)
				draw_line(head_center + Vector2(-1.5 * hs, -5.0 * hs), head_center + Vector2(1.5 * hs, -5.0 * hs), col_eye_glow, 0.9)
				draw_circle(head_center + Vector2(0, -2.5 * hs), 0.7 * hs, col_eye_core)
			else:
				draw_line(head_center + Vector2(2.6 * hs, -5.5 * hs), head_center + Vector2(2.6 * hs, -2.5 * hs), col_eye_glow, 1.1)

	# 额间道印通玄激活动态光晕
	if sigil_boost > 0.05:
		var sigil_pos := head_center + (Vector2(0, -4.2 * hs) if angle == Angle.FRONT else Vector2(2.4 * hs, -3.8 * hs))
		var sigil_glow_col := cloak_shimmer_color if cloak_shimmer_color.a > 0.01 else col_gold
		draw_soft_glow(sigil_pos, 4.2 * hs * (1.0 + sigil_boost * 0.5), Color(sigil_glow_col.r, sigil_glow_col.g, sigil_glow_col.b, 0.45 * sigil_boost), 2)
		draw_circle(sigil_pos, 1.0 * hs, Color(1, 1, 1, 0.8 * sigil_boost))

## 插槽 2：头部首服与角冠绘制
func _draw_modular_headwear(head_center: Vector2, angle: Angle) -> void:
	var hs := head_scale
	match horns_style:
		"bull_horns":
			var l_horn := [
				head_center + Vector2(-6 * hs, -5 * hs),
				head_center + Vector2(-15 * hs, -12 * hs),
				head_center + Vector2(-18 * hs, -24 * hs),
				head_center + Vector2(-11 * hs, -17 * hs),
				head_center + Vector2(-4 * hs, -7 * hs)
			]
			var r_horn := [
				head_center + Vector2(4 * hs, -7 * hs),
				head_center + Vector2(11 * hs, -17 * hs),
				head_center + Vector2(18 * hs, -24 * hs),
				head_center + Vector2(15 * hs, -12 * hs),
				head_center + Vector2(6 * hs, -5 * hs)
			]
			if angle == Angle.FRONT:
				draw_colored_polygon(l_horn, col_bone)
				draw_colored_polygon(r_horn, col_bone)
				draw_polyline(l_horn, col_bone_shadow, 1.2, true)
				draw_polyline(r_horn, col_bone_shadow, 1.2, true)
				draw_line(head_center + Vector2(-10 * hs, -10 * hs), head_center + Vector2(-13 * hs, -14 * hs), col_bone_shadow, 1.2)
				draw_line(head_center + Vector2(10 * hs, -10 * hs), head_center + Vector2(13 * hs, -14 * hs), col_bone_shadow, 1.2)
			elif angle == Angle.SIDE:
				var side_horn := [
					head_center + Vector2(-2 * hs, -6 * hs),
					head_center + Vector2(-12 * hs, -16 * hs),
					head_center + Vector2(-14 * hs, -26 * hs),
					head_center + Vector2(-7 * hs, -17 * hs),
					head_center + Vector2(2 * hs, -8 * hs)
				]
				draw_colored_polygon(side_horn, col_bone)
				draw_polyline(side_horn, col_bone_shadow, 1.2, true)
				draw_line(head_center + Vector2(-8 * hs, -12 * hs), head_center + Vector2(-10 * hs, -16 * hs), col_bone_shadow, 1.1)
			else:
				draw_colored_polygon(l_horn, col_bone_shadow)
				draw_colored_polygon(r_horn, col_bone_shadow)
				draw_polyline(l_horn, col_bone, 1.0, true)
				draw_polyline(r_horn, col_bone, 1.0, true)

		"dao_bun":
			var bun_c: Vector2 = head_center + Vector2(-1.5 * hs, -12 * hs) if angle == Angle.SIDE else head_center + Vector2(0, -12 * hs)
			draw_circle(bun_c, 5.2 * hs, col_bone)
			draw_circle(bun_c, 3.0 * hs, col_bone_shadow)
			draw_arc(bun_c, 4.0 * hs, -0.4, 2.8, 12, col_bone_shadow, 1.1)
			if angle == Angle.SIDE:
				draw_line(bun_c + Vector2(-6 * hs, -1 * hs), bun_c + Vector2(7 * hs, 1 * hs), col_weapon_main, 1.8)
				draw_circle(bun_c + Vector2(7 * hs, 1 * hs), 1.6, col_jade)
				draw_line(bun_c + Vector2(-5 * hs, -1 * hs), bun_c + Vector2(-7 * hs, 3 * hs), col_tassel_red, 1.2)
			else:
				draw_line(bun_c + Vector2(-8 * hs, 0), bun_c + Vector2(8 * hs, 0), col_weapon_main, 1.8)
				draw_circle(bun_c + Vector2(8 * hs, 0), 1.6, col_jade)
				draw_line(bun_c + Vector2(-7 * hs, 0), bun_c + Vector2(-9 * hs, 4 * hs), col_tassel_red, 1.2)

		"bamboo_hat":
			var hat_c := head_center + Vector2(0, -9 * hs)
			if angle == Angle.SIDE:
				hat_c = head_center + Vector2(1 * hs, -9 * hs)
				var hat_pts: PackedVector2Array = [
					hat_c + Vector2(-15 * hs, 2 * hs),
					hat_c + Vector2(-1 * hs, -11 * hs),
					hat_c + Vector2(16 * hs, 4 * hs),
					hat_c + Vector2(2 * hs, -1 * hs)
				]
				draw_colored_polygon(hat_pts, Color(0.38, 0.32, 0.22))
				draw_polyline(hat_pts, Color(0.68, 0.58, 0.40), 1.2, true)
				draw_line(hat_c + Vector2(-7 * hs, -4 * hs), hat_c + Vector2(8 * hs, 1 * hs), Color(0.28, 0.22, 0.15), 1.2)
				draw_line(hat_c + Vector2(0, 0), hat_c + Vector2(-1 * hs, 8 * hs), Color(0.12, 0.10, 0.08), 1.2)
			elif angle == Angle.BACK:
				var hat_pts: PackedVector2Array = [
					hat_c + Vector2(-17 * hs, 2 * hs),
					hat_c + Vector2(0, -11 * hs),
					hat_c + Vector2(17 * hs, 2 * hs),
					hat_c + Vector2(0, 1 * hs)
				]
				draw_colored_polygon(hat_pts, Color(0.32, 0.26, 0.17))
				draw_polyline(hat_pts, Color(0.62, 0.52, 0.35), 1.2, true)
				draw_arc(hat_c + Vector2(0, -3 * hs), 8.0 * hs, 0, PI, 16, Color(0.24, 0.19, 0.12), 1.2)
			else:
				var hat_pts: PackedVector2Array = [
					hat_c + Vector2(-17 * hs, 3 * hs),
					hat_c + Vector2(0, -11 * hs),
					hat_c + Vector2(17 * hs, 3 * hs),
					hat_c + Vector2(0, -2 * hs)
				]
				draw_colored_polygon(hat_pts, Color(0.38, 0.32, 0.22))
				draw_polyline(hat_pts, Color(0.68, 0.58, 0.40), 1.2, true)
				draw_arc(hat_c + Vector2(0, -3 * hs), 8.0 * hs, 0, PI, 16, Color(0.28, 0.22, 0.15), 1.2)
				draw_line(hat_c + Vector2(0, -11 * hs), hat_c + Vector2(0, -2 * hs), Color(0.24, 0.20, 0.14), 1.4)
				draw_circle(hat_c + Vector2(0, 0), 1.2, Color(0.12, 0.10, 0.08))

		"talisman":
			if angle == Angle.FRONT:
				var t_pos := head_center + Vector2(0, -10 * hs)
				var t_pts: PackedVector2Array = [
					t_pos + Vector2(-3.2 * hs, 0),
					t_pos + Vector2(3.2 * hs, 0),
					t_pos + Vector2(3.0 * hs, 13 * hs),
					t_pos + Vector2(0, 11.5 * hs),
					t_pos + Vector2(-3.0 * hs, 13 * hs)
				]
				draw_colored_polygon(t_pts, Color(0.92, 0.82, 0.28))
				draw_line(t_pos + Vector2(0, 2 * hs), t_pos + Vector2(0, 10 * hs), Color(0.85, 0.20, 0.15), 1.3)
				draw_line(t_pos + Vector2(-1.5 * hs, 4 * hs), t_pos + Vector2(1.5 * hs, 4 * hs), Color(0.85, 0.20, 0.15), 1.1)
				draw_line(t_pos + Vector2(-1.2 * hs, 7 * hs), t_pos + Vector2(1.2 * hs, 7 * hs), Color(0.85, 0.20, 0.15), 1.1)
			elif angle == Angle.SIDE:
				var t_pos := head_center + Vector2(5.5 * hs, -8 * hs)
				var t_pts: PackedVector2Array = [
					t_pos,
					t_pos + Vector2(1.5 * hs, 0),
					t_pos + Vector2(0.5 * hs, 12 * hs),
					t_pos + Vector2(-1.0 * hs, 12 * hs)
				]
				draw_colored_polygon(t_pts, Color(0.92, 0.82, 0.28))
				draw_line(t_pos + Vector2(0.8 * hs, 2 * hs), t_pos + Vector2(0, 10 * hs), Color(0.85, 0.20, 0.15), 1.2)
			else:
				draw_line(head_center + Vector2(-5 * hs, -8 * hs), head_center + Vector2(5 * hs, -8 * hs), Color(0.85, 0.20, 0.15), 1.3)
				draw_circle(head_center + Vector2(0, -8 * hs), 1.4, Color(0.85, 0.20, 0.15))

		"gold_crown":
			var crown_c := head_center + Vector2(0, -11 * hs)
			if angle == Angle.SIDE:
				crown_c = head_center + Vector2(1 * hs, -11 * hs)
				draw_circle(crown_c + Vector2(-3 * hs, 0), 3.0 * hs, Color(0.88, 0.72, 0.18))
				draw_circle(crown_c + Vector2(2 * hs, -2 * hs), 3.8 * hs, Color(1.0, 0.88, 0.32))
				draw_circle(crown_c + Vector2(2 * hs, -2 * hs), 1.5 * hs, col_void)
				draw_rect(Rect2(crown_c + Vector2(1.2 * hs, -2.8 * hs), Vector2(1.6 * hs, 1.6 * hs)), col_gold)
			else:
				draw_circle(crown_c + Vector2(-6 * hs, 0), 3.2 * hs, Color(0.92, 0.78, 0.20))
				draw_circle(crown_c + Vector2(6 * hs, 0), 3.2 * hs, Color(0.92, 0.78, 0.20))
				draw_circle(crown_c + Vector2(0, -3 * hs), 4.4 * hs, Color(1.0, 0.88, 0.32))
				draw_circle(crown_c + Vector2(0, -3 * hs), 1.7 * hs, col_void)
				draw_rect(Rect2(crown_c + Vector2(-0.8 * hs, -3.8 * hs), Vector2(1.6 * hs, 1.6 * hs)), col_gold)

		"fox_ears":
			if angle == Angle.SIDE:
				var rear_ear := [
					head_center + Vector2(-5 * hs, -7 * hs),
					head_center + Vector2(-10 * hs, -19 * hs),
					head_center + Vector2(-2 * hs, -13 * hs)
				]
				var front_ear := [
					head_center + Vector2(1 * hs, -6 * hs),
					head_center + Vector2(8 * hs, -21 * hs),
					head_center + Vector2(4 * hs, -14 * hs)
				]
				draw_colored_polygon(rear_ear, col_bone_shadow)
				draw_colored_polygon(front_ear, col_bone)
				draw_colored_polygon([
					head_center + Vector2(2 * hs, -7 * hs),
					head_center + Vector2(7 * hs, -18 * hs),
					head_center + Vector2(3 * hs, -13 * hs)
				], col_cloak_outer)
			else:
				var l_ear := [
					head_center + Vector2(-4 * hs, -6 * hs),
					head_center + Vector2(-11 * hs, -21 * hs),
					head_center + Vector2(-2 * hs, -14 * hs)
				]
				var r_ear := [
					head_center + Vector2(4 * hs, -6 * hs),
					head_center + Vector2(11 * hs, -21 * hs),
					head_center + Vector2(2 * hs, -14 * hs)
				]
				draw_colored_polygon(l_ear, col_bone)
				draw_colored_polygon(r_ear, col_bone)
				if angle == Angle.FRONT:
					draw_colored_polygon([
						head_center + Vector2(-4 * hs, -7 * hs),
						head_center + Vector2(-9 * hs, -18 * hs),
						head_center + Vector2(-3 * hs, -13 * hs)
					], col_cloak_outer)
					draw_colored_polygon([
						head_center + Vector2(4 * hs, -7 * hs),
						head_center + Vector2(9 * hs, -18 * hs),
						head_center + Vector2(3 * hs, -13 * hs)
					], col_cloak_outer)

		"none":
			pass

		"butterfly", _:
			_draw_butterfly_horns(head_center, hs, angle)

func _draw_butterfly_horns(head_center: Vector2, hs: float, angle: Angle) -> void:
	if angle == Angle.SIDE:
		var side_horn: PackedVector2Array = [
			head_center + Vector2(-3 * hs, -6 * hs),
			head_center + Vector2(-11 * hs, -17 * hs),
			head_center + Vector2(-14 * hs, -27 * hs),
			head_center + Vector2(-5 * hs, -20 * hs),
			head_center + Vector2(2 * hs, -8 * hs)
		]
		draw_colored_polygon(side_horn, col_bone)
		draw_colored_polygon(PackedVector2Array([
			head_center + Vector2(-3 * hs, -6 * hs),
			head_center + Vector2(-11 * hs, -17 * hs),
			head_center + Vector2(-14 * hs, -27 * hs),
			head_center + Vector2(-7 * hs, -17 * hs)
		]), col_bone_shadow)
		draw_line(head_center + Vector2(-2 * hs, -8 * hs), head_center + Vector2(-12 * hs, -24 * hs), Color(col_eye_core.r, col_eye_core.g, col_eye_core.b, 0.75), 1.0)
		return

	var l_horn: PackedVector2Array = [
		head_center + Vector2(-6 * hs, -4 * hs),
		head_center + Vector2(-14 * hs, -17 * hs),
		head_center + Vector2(-12 * hs, -27 * hs),
		head_center + Vector2(-6 * hs, -19 * hs),
		head_center + Vector2(-3 * hs, -8 * hs)
	]
	draw_colored_polygon(l_horn, col_bone)
	draw_colored_polygon(PackedVector2Array([
		head_center + Vector2(-6 * hs, -4 * hs),
		head_center + Vector2(-14 * hs, -17 * hs),
		head_center + Vector2(-12 * hs, -27 * hs),
		head_center + Vector2(-9 * hs, -17 * hs)
	]), col_bone_shadow)
	draw_line(head_center + Vector2(-4 * hs, -7 * hs), head_center + Vector2(-10 * hs, -23 * hs), Color(col_eye_core.r, col_eye_core.g, col_eye_core.b, 0.7), 1.0)

	var r_horn: PackedVector2Array = [
		head_center + Vector2(3 * hs, -8 * hs),
		head_center + Vector2(6 * hs, -19 * hs),
		head_center + Vector2(12 * hs, -27 * hs),
		head_center + Vector2(14 * hs, -17 * hs),
		head_center + Vector2(6 * hs, -4 * hs)
	]
	draw_colored_polygon(r_horn, col_bone)
	draw_colored_polygon(PackedVector2Array([
		head_center + Vector2(3 * hs, -8 * hs),
		head_center + Vector2(6 * hs, -19 * hs),
		head_center + Vector2(12 * hs, -27 * hs),
		head_center + Vector2(9 * hs, -17 * hs)
	]), col_bone_shadow)
	draw_line(head_center + Vector2(4 * hs, -7 * hs), head_center + Vector2(10 * hs, -23 * hs), Color(col_eye_core.r, col_eye_core.g, col_eye_core.b, 0.7), 1.0)

## 插槽 3：眼睛神态与光芒
func _draw_modular_eyes(head_center: Vector2, angle: Angle, eye_pulse: float) -> void:
	var hs := head_scale
	var eff_glow := col_eye_glow
	var eff_core := col_eye_core
	if eye_override_color.a > 0.01:
		eff_glow = col_eye_glow.lerp(eye_override_color, clampf(eye_override_color.a, 0.0, 1.0))
		eff_core = col_eye_core.lerp(Color(1, 1, 1, 1), 0.55).lerp(eye_override_color, 0.45)
	var glow_r := eye_glow_boost * 3.6
	var glow_a := eye_glow_boost * 0.4
	var eff_glow_col := Color(eff_glow.r, eff_glow.g, eff_glow.b, clampf(eff_glow.a + eye_pulse + glow_a, 0.0, 1.0))

	if angle == Angle.FRONT:
		var l_eye := head_center + Vector2(-4.2 * hs, 1.0 * hs)
		var r_eye := head_center + Vector2(4.2 * hs, 1.0 * hs)

		match eye_style:
			"sharp_slit":
				draw_line(l_eye + Vector2(-3.2 * hs, 0), l_eye + Vector2(3.2 * hs, 0), col_void, 2.8)
				draw_line(r_eye + Vector2(-3.2 * hs, 0), r_eye + Vector2(3.2 * hs, 0), col_void, 2.8)
				draw_soft_glow(l_eye, 5.2 + glow_r, eff_glow_col, 2)
				draw_soft_glow(r_eye, 5.2 + glow_r, eff_glow_col, 2)
				draw_line(l_eye + Vector2(-1.6 * hs, 0), l_eye + Vector2(1.6 * hs, 0), eff_core, 1.5)
				draw_line(r_eye + Vector2(-1.6 * hs, 0), r_eye + Vector2(1.6 * hs, 0), eff_core, 1.5)

			"round_pupil":
				draw_circle(l_eye, 3.8 * hs, col_void)
				draw_circle(r_eye, 3.8 * hs, col_void)
				draw_soft_glow(l_eye, 6.0 + glow_r, eff_glow_col, 3)
				draw_soft_glow(r_eye, 6.0 + glow_r, eff_glow_col, 3)
				draw_circle(l_eye + Vector2(0.4, -0.4), 1.7 * hs, eff_core)
				draw_circle(r_eye + Vector2(-0.4, -0.4), 1.7 * hs, eff_core)
				draw_circle(l_eye + Vector2(-0.6, 0.6), 0.7 * hs, Color(1, 1, 1, 0.65))

			"angry_slit":
				var l_poly: PackedVector2Array = [l_eye + Vector2(-3.5 * hs, 2 * hs), l_eye + Vector2(3.5 * hs, -1.5 * hs), l_eye + Vector2(3 * hs, 1.5 * hs)]
				var r_poly: PackedVector2Array = [r_eye + Vector2(-3.5 * hs, -1.5 * hs), r_eye + Vector2(3.5 * hs, 2 * hs), r_eye + Vector2(-3 * hs, 1.5 * hs)]
				draw_colored_polygon(l_poly, col_void)
				draw_colored_polygon(r_poly, col_void)
				draw_soft_glow(l_eye, 6.0 + glow_r, eff_glow_col, 2)
				draw_soft_glow(r_eye, 6.0 + glow_r, eff_glow_col, 2)
				draw_circle(l_eye, 1.6 * hs, eff_core)
				draw_circle(r_eye, 1.6 * hs, eff_core)

			"hollow_oval", _:
				draw_filled_ellipse(l_eye, 3.8 * hs, 5.2 * hs, col_void)
				draw_filled_ellipse(r_eye, 3.8 * hs, 5.2 * hs, col_void)
				draw_soft_glow(l_eye, 6.2 + glow_r, eff_glow_col, 3)
				draw_soft_glow(r_eye, 6.2 + glow_r, eff_glow_col, 3)
				draw_filled_ellipse(l_eye + Vector2(0.2, -0.3), 2.2 * hs, 3.6 * hs, eff_core)
				draw_filled_ellipse(r_eye + Vector2(-0.2, -0.3), 2.2 * hs, 3.6 * hs, eff_core)

		if eye_glow_boost > 0.15:
			draw_circle(l_eye, 1.1 * hs, Color(1, 1, 1, eye_glow_boost * 0.85))
			draw_circle(r_eye, 1.1 * hs, Color(1, 1, 1, eye_glow_boost * 0.85))

	else:
		var eye_pos := head_center + Vector2(4.2 * hs, 1.0 * hs)
		match eye_style:
			"sharp_slit":
				var slit_pts: PackedVector2Array = [
					eye_pos + Vector2(-3.0 * hs, 1.0 * hs),
					eye_pos + Vector2(3.2 * hs, -1.6 * hs),
					eye_pos + Vector2(2.2 * hs, 0.8 * hs)
				]
				draw_colored_polygon(slit_pts, col_void)
				draw_soft_glow(eye_pos, 5.2 + glow_r, eff_glow_col, 2)
				draw_line(eye_pos + Vector2(-1.8 * hs, 0.6 * hs), eye_pos + Vector2(2.4 * hs, -0.8 * hs), eff_core, 1.2)

			"angry_slit":
				var angry_pts: PackedVector2Array = [
					eye_pos + Vector2(-3.2 * hs, -1.4 * hs),
					eye_pos + Vector2(3.2 * hs, 1.6 * hs),
					eye_pos + Vector2(-2.2 * hs, 1.4 * hs)
				]
				draw_colored_polygon(angry_pts, col_void)
				draw_soft_glow(eye_pos, 5.8 + glow_r, eff_glow_col, 2)
				draw_circle(eye_pos + Vector2(0.4 * hs, 0.2 * hs), 1.5 * hs, eff_core)

			"round_pupil":
				draw_circle(eye_pos, 3.2 * hs, col_void)
				draw_soft_glow(eye_pos, 5.8 + glow_r, eff_glow_col, 2)
				draw_circle(eye_pos + Vector2(0.3, -0.3), 1.7 * hs, eff_core)

			"hollow_oval", _:
				draw_filled_ellipse(eye_pos, 3.6 * hs, 5.0 * hs, col_void)
				draw_soft_glow(eye_pos, 6.2 + glow_r, eff_glow_col, 3)
				draw_filled_ellipse(eye_pos + Vector2(0.3, -0.2), 2.2 * hs, 3.6 * hs, eff_core)

		if eye_glow_boost > 0.15:
			draw_circle(eye_pos, 1.2 * hs, Color(1, 1, 1, eye_glow_boost * 0.85))

## 绘制斗篷轮廓描边与法力流动反光（仙侠高精流光反光感）
func _draw_cloak_rim_shimmer(pts: PackedVector2Array, default_edge: Color) -> void:
	if pts.size() < 3:
		return
	var eff_edge := default_edge
	if cloak_shimmer_intensity > 0.02 and cloak_shimmer_color.a > 0.01:
		eff_edge = default_edge.lerp(cloak_shimmer_color, clampf(cloak_shimmer_intensity * 0.85, 0.0, 1.0))
	var base_w := 1.2 + cloak_shimmer_intensity * 0.8
	draw_polyline(pts, eff_edge, base_w, true)

	if cloak_shimmer_intensity > 0.05:
		var n := pts.size()
		var phase := fmod(_time * 2.8, 1.0)
		var center_idx := int(phase * float(n))
		var shimmer_c := cloak_shimmer_color if cloak_shimmer_color.a > 0.01 else Color(1.0, 0.95, 0.72)
		var s_pts := PackedVector2Array()
		for off in range(-2, 3):
			var idx := (center_idx + off + n) % n
			s_pts.append(pts[idx])
		if s_pts.size() >= 2:
			var s_alpha := clampf(cloak_shimmer_intensity, 0.0, 1.0)
			draw_polyline(s_pts, Color(shimmer_c.r, shimmer_c.g, shimmer_c.b, s_alpha * 0.85), base_w + 1.5, true)
			draw_polyline(s_pts, Color(1.0, 1.0, 1.0, s_alpha * 0.95), base_w * 0.8, true)

# ==================== 斗篷插槽绘制（端正挺拔躯干 + 水平齐整自然下摆） ====================

func _draw_modular_cloak(float_y: float, wave: float, drag: float, angle: Angle) -> void:
	match angle:
		Angle.FRONT:
			_draw_cloak_front_modular(float_y, wave, drag)
		Angle.SIDE:
			_draw_cloak_side_modular(float_y, wave, drag)
		Angle.BACK:
			_draw_cloak_back_modular(float_y, wave)

# ----------------- 正面斗篷 -----------------

func _draw_cloak_front_modular(float_y: float, wave: float, extra_drag: float = 0.0) -> void:
	var w := width_scale
	var flare := extra_drag * 0.45

	# 1. 内衬道袍底衬
	var inner_pts: PackedVector2Array = [
		Vector2(0, -4 + float_y),
		Vector2((-15 - flare * 0.4) * w, 12 + float_y),
		Vector2((-14 - flare) * w + wave * 0.4, 30 + float_y),
		Vector2(wave * 0.15, 27 + float_y),
		Vector2((14 + flare) * w - wave * 0.4, 30 + float_y),
		Vector2((15 + flare * 0.4) * w, 12 + float_y)
	]
	draw_colored_polygon(inner_pts, col_cloak_inner)

	# 胸前交领右衽领口（道门中衣与素雪白领）
	var collar_outer: PackedVector2Array = [
		Vector2(-5.0 * w, -5 + float_y),
		Vector2(5.0 * w, -5 + float_y),
		Vector2(0, 5 + float_y)
	]
	draw_colored_polygon(collar_outer, Color(col_cloak_inner.r * 1.35, col_cloak_inner.g * 1.35, col_cloak_inner.b * 1.35))
	draw_line(Vector2(-5.0 * w, -5 + float_y), Vector2(1.5 * w, 5 + float_y), Color(col_bone.r, col_bone.g, col_bone.b, 0.8), 1.2)
	draw_line(Vector2(5.0 * w, -5 + float_y), Vector2(-1.0 * w, 2 + float_y), Color(col_bone_shadow.r, col_bone_shadow.g, col_bone_shadow.b, 0.4), 1.0)
	draw_line(Vector2(0, 5 + float_y), Vector2(0, 11 + float_y), Color(col_cloak_inner.r, col_cloak_inner.g, col_cloak_inner.b, 0.6), 1.0)

	# 2. 外袍款式
	var outer_pts: PackedVector2Array = []
	match cloak_style:
		"heavy_overcoat":
			outer_pts = [
				Vector2(0, -6 + float_y),
				Vector2(-11 * w, -2 + float_y),
				Vector2((-16 - flare * 0.5) * w, 15 + float_y),
				Vector2((-14 - flare) * w + wave * 0.35, 31 + float_y),
				Vector2(wave * 0.2, 30 + float_y),
				Vector2((14 + flare) * w - wave * 0.35, 31 + float_y),
				Vector2((16 + flare * 0.5) * w, 15 + float_y),
				Vector2(11 * w, -2 + float_y)
			]
		"short_cape":
			outer_pts = [
				Vector2(0, -6 + float_y),
				Vector2(-9 * w, -2 + float_y),
				Vector2((-13 - flare * 0.5) * w, 12 + float_y),
				Vector2((-10 - flare) * w + wave * 0.4, 22 + float_y),
				Vector2(-4 * w + wave * 0.2, 25 + float_y),
				Vector2(4 * w - wave * 0.2, 25 + float_y),
				Vector2((10 + flare) * w - wave * 0.4, 22 + float_y),
				Vector2((13 + flare * 0.5) * w, 12 + float_y),
				Vector2(9 * w, -2 + float_y)
			]
		"tattered_rags":
			outer_pts = [
				Vector2(0, -6 + float_y),
				Vector2(-10 * w, -2 + float_y),
				Vector2((-15 - flare * 0.5) * w, 15 + float_y),
				Vector2((-13 - flare) * w + wave * 0.45, 27 + float_y),
				Vector2((-9 - flare * 0.6) * w + wave * 0.3, 32 + float_y),
				Vector2(-5 * w, 24 + float_y),
				Vector2(wave * 0.2, 31 + float_y),
				Vector2(6 * w, 23 + float_y),
				Vector2((11 + flare * 0.8) * w - wave * 0.4, 32 + float_y),
				Vector2((15 + flare * 0.5) * w, 15 + float_y),
				Vector2(10 * w, -2 + float_y)
			]
		"royal_shawl":
			outer_pts = [
				Vector2(0, -6 + float_y),
				Vector2(-10 * w, -2 + float_y),
				Vector2((-15 - flare * 0.5) * w, 14 + float_y),
				Vector2((-12 - flare) * w + wave * 0.4, 29 + float_y),
				Vector2(wave * 0.15, 27 + float_y),
				Vector2((12 + flare) * w - wave * 0.4, 29 + float_y),
				Vector2((15 + flare * 0.5) * w, 14 + float_y),
				Vector2(10 * w, -2 + float_y)
			]
		"split_flowing", _:
			outer_pts = [
				Vector2(0, -6 + float_y),
				Vector2(-9 * w, -2 + float_y),
				Vector2((-14 - flare * 0.5) * w, 15 + float_y),
				Vector2((-12 - flare) * w + wave * 0.5, 28 + float_y),
				Vector2(-7 * w + wave * 0.2, 24 + float_y),
				Vector2(-3 * w + wave * 0.3, 31 + float_y),
				Vector2(2 * w - wave * 0.2, 26 + float_y),
				Vector2((8 + flare) * w - wave * 0.4, 29 + float_y),
				Vector2((14 + flare * 0.5) * w, 15 + float_y),
				Vector2(9 * w, -2 + float_y)
			]

	draw_colored_polygon(outer_pts, col_cloak_outer)
	_draw_cloak_rim_shimmer(outer_pts, col_cloak_edge)

	draw_line(Vector2(-5 * w, 14 + float_y), Vector2(-4 * w, 26 + float_y), Color(col_cloak_inner.r, col_cloak_inner.g, col_cloak_inner.b, 0.45), 1.0)
	draw_line(Vector2(5 * w, 14 + float_y), Vector2(4 * w, 26 + float_y), Color(col_cloak_inner.r, col_cloak_inner.g, col_cloak_inner.b, 0.45), 1.0)

	if cloak_style == "royal_shawl":
		draw_arc(Vector2(-7 * w, 4 + float_y), 5.0, 0, PI, 16, col_gold, 1.3)
		draw_arc(Vector2(7 * w, 4 + float_y), 5.0, 0, PI, 16, col_gold, 1.3)

# ----------------- 侧面斗篷（彻底重构：端正挺拔躯干 + 水平齐整自然下摆） -----------------

func _draw_cloak_side_modular(float_y: float, wave: float, extra_drag: float) -> void:
	var w := width_scale
	var d := extra_drag

	# 1. 侧面内衬底色
	var inner_side: PackedVector2Array = [
		Vector2(1.5, -5 + float_y),
		Vector2(5.5 * w, 1 + float_y),
		Vector2(5.0 * w, 14 + float_y),
		Vector2(4.0 * w, 28 + float_y),
		Vector2(-4.5 * w - d * 0.2, 28 + float_y),
		Vector2(-4.0 * w, 12 + float_y)
	]
	draw_colored_polygon(inner_side, col_cloak_inner)

	# 2. 侧面外袍主体（前摆与后摆水平高度完全对齐）
	var side_pts: PackedVector2Array = []
	match cloak_style:
		"heavy_overcoat": # 厚重大氅（石岳、独臂刀圣）
			side_pts = [
				Vector2(2.0, -6 + float_y),
				Vector2(4.5 * w, -4 + float_y),
				Vector2(7.5 * w, 2 + float_y),
				Vector2(6.8 * w, 14 + float_y),
				Vector2(5.2 * w, 29.5 + float_y),
				Vector2(0.0, 30.0 + float_y),
				Vector2(-6.8 * w - d * 0.35 + wave * 0.2, 29.5 + float_y),
				Vector2(-7.5 * w, 14 + float_y),
				Vector2(-6.5 * w, 2 + float_y),
				Vector2(-3.5 * w, -5 + float_y)
			]

		"short_cape": # 灵动短披（符童）
			var skirt_pts: PackedVector2Array = [
				Vector2(1.5, 14 + float_y),
				Vector2(5.2 * w, 15 + float_y),
				Vector2(4.0 * w, 27.5 + float_y),
				Vector2(-4.8 * w, 27.5 + float_y),
				Vector2(-4.0 * w, 14 + float_y)
			]
			draw_colored_polygon(skirt_pts, col_cloak_inner)
			draw_polyline(skirt_pts, col_gold, 1.0, true)

			side_pts = [
				Vector2(1.8, -6 + float_y),
				Vector2(4.0 * w, -4 + float_y),
				Vector2(6.2 * w, 2 + float_y),
				Vector2(5.5 * w, 10 + float_y),
				Vector2(3.5 * w, 18.0 + float_y),
				Vector2(-1.0 * w, 18.5 + float_y),
				Vector2(-6.5 * w - d * 0.3 + wave * 0.25, 18.0 + float_y),
				Vector2(-6.0 * w, 10 + float_y),
				Vector2(-5.0 * w, 1 + float_y),
				Vector2(-3.0 * w, -5 + float_y)
			]

		"tattered_rags": # 破残百衲袍（狂战、夺舍）
			side_pts = [
				Vector2(2.0, -6 + float_y),
				Vector2(4.2 * w, -4 + float_y),
				Vector2(7.0 * w, 2 + float_y),
				Vector2(6.2 * w, 14 + float_y),
				Vector2(4.8 * w, 29.0 + float_y),
				Vector2(1.5 * w, 26.5 + float_y),
				Vector2(-2.5 * w, 29.5 + float_y),
				Vector2(-5.0 * w, 26.0 + float_y),
				Vector2(-7.2 * w - d * 0.35 + wave * 0.3, 29.0 + float_y),
				Vector2(-7.0 * w, 14 + float_y),
				Vector2(-6.0 * w, 2 + float_y),
				Vector2(-3.5 * w, -5 + float_y)
			]

		"royal_shawl": # 锦绣云肩（金算盘、多宝）
			side_pts = [
				Vector2(2.0, -6 + float_y),
				Vector2(4.5 * w, -4 + float_y),
				Vector2(7.2 * w, 2 + float_y),
				Vector2(6.5 * w, 14 + float_y),
				Vector2(4.8 * w, 28.5 + float_y),
				Vector2(0.0, 29.0 + float_y),
				Vector2(-6.8 * w - d * 0.3 + wave * 0.2, 28.5 + float_y),
				Vector2(-7.0 * w, 14 + float_y),
				Vector2(-6.0 * w, 2 + float_y),
				Vector2(-3.5 * w, -5 + float_y)
			]

		"split_flowing", _: # 经典双尾裂帛长袍（青云独孤、幽娘）
			side_pts = [
				Vector2(1.8, -6 + float_y),
				Vector2(4.0 * w, -4 + float_y),
				Vector2(6.8 * w, 2 + float_y),
				Vector2(6.0 * w, 14 + float_y),
				Vector2(4.5 * w, 28.5 + float_y),
				Vector2(0.0, 27.5 + float_y),
				Vector2(-3.5 * w, 29.0 + float_y),
				Vector2(-6.8 * w - d * 0.35 + wave * 0.25, 28.5 + float_y),
				Vector2(-6.5 * w, 14 + float_y),
				Vector2(-5.5 * w, 2 + float_y),
				Vector2(-3.0 * w, -5 + float_y)
			]

	draw_colored_polygon(side_pts, col_cloak_outer)
	_draw_cloak_rim_shimmer(side_pts, col_cloak_edge)

	draw_line(Vector2(1.8, -5 + float_y), Vector2(4.5 * w, 5 + float_y), Color(col_bone.r, col_bone.g, col_bone.b, 0.7), 1.1)
	draw_line(Vector2(-1.5 * w, 3 + float_y), Vector2(-2.5 * w - d * 0.1, 24 + float_y), Color(col_cloak_inner.r, col_cloak_inner.g, col_cloak_inner.b, 0.45), 1.0)

	if cloak_style == "royal_shawl":
		draw_arc(Vector2(0, 2 + float_y), 6.0 * w, 0, PI * 0.8, 14, col_gold, 1.2)

func _draw_cloak_dash_side(dash_y: float) -> void:
	var w := width_scale
	var dash_pts: PackedVector2Array = [
		Vector2(2.0, -6 + dash_y),
		Vector2(6.0 * w, -2 + dash_y),
		Vector2(8.0 * w, 5 + dash_y),
		Vector2(2.0 * w, 14 + dash_y),
		Vector2(-18 * w, 8 + dash_y),
		Vector2(-26 * w, 4 + dash_y),
		Vector2(-14 * w, 0 + dash_y),
		Vector2(-5 * w, -3 + dash_y)
	]
	draw_colored_polygon(dash_pts, col_cloak_outer)
	_draw_cloak_rim_shimmer(dash_pts, col_cloak_edge)

# ----------------- 背面斗篷 -----------------

func _draw_cloak_back_modular(float_y: float, wave: float) -> void:
	var w := width_scale
	var back_pts: PackedVector2Array = []
	match cloak_style:
		"heavy_overcoat":
			back_pts = [
				Vector2(0, -6 + float_y),
				Vector2(-11 * w, -2 + float_y),
				Vector2(-16 * w, 15 + float_y),
				Vector2(-14 * w, 31 + float_y),
				Vector2(0, 30 + float_y),
				Vector2(14 * w, 31 + float_y),
				Vector2(16 * w, 15 + float_y),
				Vector2(11 * w, -2 + float_y)
			]
		"short_cape":
			back_pts = [
				Vector2(0, -6 + float_y),
				Vector2(-9 * w, -2 + float_y),
				Vector2(-13 * w, 12 + float_y),
				Vector2(-10 * w, 22 + float_y),
				Vector2(-4 * w, 25 + float_y),
				Vector2(4 * w, 25 + float_y),
				Vector2(10 * w, 22 + float_y),
				Vector2(13 * w, 12 + float_y),
				Vector2(9 * w, -2 + float_y)
			]
		"tattered_rags":
			back_pts = [
				Vector2(0, -6 + float_y),
				Vector2(-10 * w, -2 + float_y),
				Vector2(-15 * w, 15 + float_y),
				Vector2(-13 * w, 27 + float_y),
				Vector2(-9 * w, 32 + float_y),
				Vector2(-5 * w, 24 + float_y),
				Vector2(0, 31 + float_y),
				Vector2(6 * w, 23 + float_y),
				Vector2(11 * w, 32 + float_y),
				Vector2(15 * w, 15 + float_y),
				Vector2(10 * w, -2 + float_y)
			]
		"royal_shawl":
			back_pts = [
				Vector2(0, -6 + float_y),
				Vector2(-10 * w, -2 + float_y),
				Vector2(-15 * w, 14 + float_y),
				Vector2(-12 * w, 29 + float_y),
				Vector2(0, 27 + float_y),
				Vector2(12 * w, 29 + float_y),
				Vector2(15 * w, 14 + float_y),
				Vector2(10 * w, -2 + float_y)
			]
		"split_flowing", _:
			back_pts = [
				Vector2(0, -6 + float_y),
				Vector2(-9 * w, -2 + float_y),
				Vector2(-14 * w, 15 + float_y),
				Vector2(-12 * w + wave * 0.3, 28 + float_y),
				Vector2(-7 * w, 24 + float_y),
				Vector2(-3 * w, 31 + float_y),
				Vector2(2 * w, 26 + float_y),
				Vector2(8 * w + wave * 0.2, 29 + float_y),
				Vector2(14 * w, 15 + float_y),
				Vector2(9 * w, -2 + float_y)
			]

	draw_colored_polygon(back_pts, col_cloak_outer)
	_draw_cloak_rim_shimmer(back_pts, col_cloak_edge)
	draw_line(Vector2(0, -2 + float_y), Vector2(0, 24 + float_y), Color(col_cloak_inner.r, col_cloak_inner.g, col_cloak_inner.b, 0.5), 1.1)

# ==================== 背负本命法器插槽绘制 ====================

func _draw_modular_strap(float_y: float) -> void:
	match strap_style:
		"dual":
			var l_top := Vector2(-6, -6 + float_y)
			var l_bot := Vector2(-4, 14 + float_y)
			var r_top := Vector2(6, -6 + float_y)
			var r_bot := Vector2(4, 14 + float_y)
			draw_line(l_top, l_bot, Color(0.05, 0.08, 0.12, 0.95), 2.2)
			draw_line(r_top, r_bot, Color(0.05, 0.08, 0.12, 0.95), 2.2)
			draw_circle(Vector2(0, 4 + float_y), 2.8, col_bone)
			draw_circle(Vector2(0, 4 + float_y), 1.4, col_void)
			draw_circle(Vector2(0, 4 + float_y), 0.7, col_gold)
		"floating":
			draw_arc(Vector2(0, 4 + float_y), 9.0, 0, TAU, 20, Color(col_cloak_edge.r, col_cloak_edge.g, col_cloak_edge.b, 0.45), 1.2)
			draw_circle(Vector2(cos(_time * 3.0) * 9.0, 4 + float_y + sin(_time * 3.0) * 9.0), 1.2, col_eye_core)
		"diagonal", _:
			var p_top := Vector2(7, -6 + float_y)
			var p_bot := Vector2(-5, 12 + float_y)
			draw_line(p_top, p_bot, Color(0.05, 0.08, 0.12, 0.95), 2.4)
			draw_line(p_top, p_bot, col_cloak_edge, 0.8)
			var center := (p_top + p_bot) * 0.5
			draw_circle(center, 2.4, col_bone)
			draw_circle(center, 1.2, col_void)
			draw_circle(center, 0.6, col_gold)

## 绘制法器（正面探出右肩上方、下半部藏于斗篷后绝不露底，侧面贴背，背面外挂最表层）
func _draw_modular_weapon(pos: Vector2, rot: float, angle: Angle) -> void:
	var t := Transform2D(rot, pos)

	match weapon_type:
		"stone_pillar": # 玄重墨石尺（体修石岳）
			var r_pts: PackedVector2Array = [
				t * Vector2(-3.2, -15), t * Vector2(3.2, -15),
				t * Vector2(3.2, 5), t * Vector2(-3.2, 5)
			]
			draw_colored_polygon(r_pts, col_weapon_main)
			draw_colored_polygon(PackedVector2Array([
				t * Vector2(0, -15), t * Vector2(3.2, -15),
				t * Vector2(3.2, 5), t * Vector2(0, 5)
			]), col_weapon_shadow)
			draw_polyline(r_pts, Color(0.18, 0.20, 0.24), 1.2, true)
			draw_line(t * Vector2(-1.5, -11), t * Vector2(1.5, -11), col_weapon_accent, 1.2)
			draw_line(t * Vector2(0, -11), t * Vector2(0, 0), col_weapon_accent, 1.2)
			draw_line(t * Vector2(-1.5, -5), t * Vector2(1.5, -5), col_weapon_accent, 1.2)
			draw_line(t * Vector2(-1.5, 0), t * Vector2(1.5, 0), col_weapon_accent, 1.2)
			draw_line(t * Vector2(0, 5), t * Vector2(0, 11), col_weapon_shadow, 2.6)
			draw_circle(t * Vector2(0, 11.5), 1.8, col_weapon_main)
			draw_circle(t * Vector2(0, 11.5), 0.9, col_void)

		"peach_sword": # 辟邪千年桃木剑（符阵灵童）
			var s_pts: PackedVector2Array = [
				t * Vector2(0, -14), t * Vector2(2.0, -8),
				t * Vector2(1.8, 3), t * Vector2(-1.8, 3), t * Vector2(-2.0, -8)
			]
			draw_colored_polygon(s_pts, col_weapon_main)
			draw_colored_polygon(PackedVector2Array([
				t * Vector2(0, -14), t * Vector2(2.0, -8),
				t * Vector2(1.8, 3), t * Vector2(0, 3)
			]), col_weapon_shadow)
			draw_line(t * Vector2(-3.2, 3), t * Vector2(3.2, 3), col_weapon_accent, 2.0)
			draw_circle(t * Vector2(-1.2, 3), 0.6, col_void)
			draw_circle(t * Vector2(1.2, 3), 0.6, col_eye_core)
			draw_line(t * Vector2(0, 3), t * Vector2(0, 9.5), col_weapon_main, 1.8)
			draw_circle(t * Vector2(0, 10), 1.4, col_weapon_accent)
			if angle != Angle.FRONT:
				draw_line(t * Vector2(0, 10), t * Vector2(-2.5, 14), Color(0.95, 0.85, 0.3), 1.2)

		"golden_abacus": # 乾坤金算盘（散修金算盘）
			var ab_pts: PackedVector2Array = [
				t * Vector2(-5.5, -12), t * Vector2(5.5, -12),
				t * Vector2(5.5, 6), t * Vector2(-5.5, 6)
			]
			draw_colored_polygon(ab_pts, col_weapon_main)
			draw_polyline(ab_pts, col_weapon_shadow, 1.2, true)
			draw_line(t * Vector2(-5, -6), t * Vector2(5, -6), col_weapon_shadow, 1.4)
			for b in [-3.2, 0, 3.2]:
				draw_circle(t * Vector2(b, -9), 1.0, col_weapon_accent)
				draw_circle(t * Vector2(b, -1), 1.0, col_weapon_accent)
				draw_circle(t * Vector2(b, 2.5), 1.0, col_weapon_accent)
			draw_line(t * Vector2(0, 6), t * Vector2(0, 11), col_weapon_shadow, 2.0)

		"shadow_daggers": # 阴煞双刃短刺（魅影幽娘）
			for side in [-2.5, 2.5]:
				var dt := t.translated(Vector2(side, 0))
				var d_pts: PackedVector2Array = [
					dt * Vector2(0, -13), dt * Vector2(1.8, -7),
					dt * Vector2(1.4, 2), dt * Vector2(-1.4, 2), dt * Vector2(-1.8, -7)
				]
				draw_colored_polygon(d_pts, col_weapon_main)
				draw_colored_polygon(PackedVector2Array([
					dt * Vector2(0, -13), dt * Vector2(1.8, -7),
					dt * Vector2(1.4, 2), dt * Vector2(0, 2)
				]), col_weapon_shadow)
				draw_line(dt * Vector2(0, -12), dt * Vector2(0, 1), col_weapon_accent, 1.0)
				draw_line(dt * Vector2(0, 2), dt * Vector2(0, 7.5), col_weapon_shadow, 1.6)
				draw_circle(dt * Vector2(0, 8), 1.2, col_weapon_accent)

		"broken_blade": # 厚背断马狂刀（独臂刀圣）
			var b_pts: PackedVector2Array = [
				t * Vector2(-2.5, -14), t * Vector2(4.5, -10),
				t * Vector2(4.0, 4), t * Vector2(-2.5, 4)
			]
			draw_colored_polygon(b_pts, col_weapon_main)
			draw_line(t * Vector2(-2.5, -14), t * Vector2(-2.5, 4), col_weapon_shadow, 1.8)
			draw_line(t * Vector2(0, -11), t * Vector2(0, 2), Color(0.85, 0.25, 0.20), 1.1)
			draw_circle(t * Vector2(0, 4.5), 2.8, col_weapon_shadow)
			draw_line(t * Vector2(0, 5), t * Vector2(0, 11.5), Color(0.9, 0.88, 0.84), 2.2)
			draw_circle(t * Vector2(0, 12), 1.8, col_weapon_main)

		"bone_axe": # 巨兽头骨双刃战斧（狂战蛮修）
			var h_pts: PackedVector2Array = [
				t * Vector2(-8, -13), t * Vector2(-3, -7),
				t * Vector2(-3, -1), t * Vector2(-7, 5),
				t * Vector2(-1, 0), t * Vector2(1, 0),
				t * Vector2(7, 5), t * Vector2(3, -1),
				t * Vector2(3, -7), t * Vector2(8, -13)
			]
			draw_colored_polygon(h_pts, col_weapon_main)
			draw_colored_polygon(PackedVector2Array([
				t * Vector2(0, -13), t * Vector2(8, -13),
				t * Vector2(3, -7), t * Vector2(1, 0)
			]), col_weapon_shadow)
			draw_line(t * Vector2(0, -14), t * Vector2(0, 11), col_weapon_shadow, 2.4)
			draw_circle(t * Vector2(0, 11.5), 1.8, col_weapon_accent)

		"soul_banner": # 墨竹引魂冥幡（夺舍散人）
			draw_line(t * Vector2(0, -16), t * Vector2(0, 11), Color(0.18, 0.20, 0.22), 2.0)
			draw_line(t * Vector2(-1, -14), t * Vector2(6.5, -14), Color(0.18, 0.20, 0.22), 1.4)
			var banner_pts: PackedVector2Array = [
				t * Vector2(1, -13), t * Vector2(6.5, -13),
				t * Vector2(5.5, 4), t * Vector2(1, 2)
			]
			draw_colored_polygon(banner_pts, col_weapon_main)
			draw_circle(t * Vector2(3.5, -5), 1.5, col_weapon_accent)
			draw_line(t * Vector2(3.5, -8), t * Vector2(3.5, -2), col_eye_core, 1.0)

		"treasure_chest": # 紫金百宝乾坤匣（多宝道人）
			var box_pts: PackedVector2Array = [
				t * Vector2(-6.5, -9), t * Vector2(6.5, -9),
				t * Vector2(6.5, 7), t * Vector2(-6.5, 7)
			]
			draw_colored_polygon(box_pts, col_weapon_main)
			draw_polyline(box_pts, col_weapon_shadow, 1.2, true)
			draw_line(t * Vector2(-6.5, 0), t * Vector2(6.5, 0), col_weapon_accent, 1.6)
			draw_line(t * Vector2(0, -9), t * Vector2(0, 7), col_weapon_accent, 1.6)
			draw_circle(t * Vector2(0, 0), 2.4, Color(1.0, 0.88, 0.35))
			draw_circle(t * Vector2(0, 0), 1.2, col_jade)

		"bone_nail", _: # 纯白月光骨钉/长剑（青云剑修独孤）
			var nail_pts: PackedVector2Array = [
				t * Vector2(0, -15),
				t * Vector2(2.4, -9),
				t * Vector2(2.0, 3),
				t * Vector2(-2.0, 3),
				t * Vector2(-2.4, -9)
			]
			draw_colored_polygon(nail_pts, col_weapon_main)
			draw_colored_polygon(PackedVector2Array([
				t * Vector2(0, -15), t * Vector2(2.4, -9),
				t * Vector2(2.0, 3), t * Vector2(0, 3)
			]), col_weapon_shadow)
			draw_line(t * Vector2(0, -13), t * Vector2(0, 2), col_weapon_accent, 1.1)
			var guard_pts: PackedVector2Array = [
				t * Vector2(-3.2, 3), t * Vector2(3.2, 3),
				t * Vector2(2.2, 5.5), t * Vector2(-2.2, 5.5)
			]
			draw_colored_polygon(guard_pts, col_bone_shadow)
			draw_circle(t * Vector2(0, 4.2), 0.9, col_jade)
			draw_line(t * Vector2(0, 5.5), t * Vector2(0, 10.5), col_weapon_main, 2.0)
			draw_circle(t * Vector2(0, 11), 1.6, col_weapon_main)
			draw_circle(t * Vector2(0, 11), 0.8, col_bone_shadow)

## 绘制月牙斩痕
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
