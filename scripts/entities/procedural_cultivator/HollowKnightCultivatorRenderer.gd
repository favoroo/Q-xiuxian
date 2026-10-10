class_name HollowKnightCultivatorRenderer
extends CultivatorRendererBase

## 通用模块化修仙角色渲染器（土豆兄弟式参数化驱动）
## 基于统一修仙素体与 4 大外观插槽（体型、面部、斗篷、武器），实现全道统角色的极速拓展与差异化

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

## 动态设置视觉配置
func set_visual_config(cfg: CultivatorVisualConfig) -> void:
	config = cfg
	_sync_config()
	queue_redraw()

# ==================== 1. 待机 (IDLE) ====================

func _draw_idle(angle: Angle) -> void:
	var total_scale := Vector2(body_scale * width_scale, body_scale * height_scale)
	draw_set_transform(Vector2.ZERO, 0.0, total_scale)

	var float_y := sin(_time * 2.6) * 2.0
	var cloak_wave := sin(_time * 3.2) * 2.5
	var eye_pulse := sin(_time * 3.0) * 0.08

	# 脚底地影
	_draw_ground_shadow(Vector2(0, 32), 18.0 * width_scale, 5.0, 0.5)

	match angle:
		Angle.FRONT:
			_draw_modular_cloak(float_y, cloak_wave, 0.0, Angle.FRONT)
			_draw_head_front(float_y, eye_pulse)
		Angle.SIDE:
			_draw_modular_weapon(Vector2(-7, 2 + float_y), deg_to_rad(-24.0), Angle.SIDE)
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

	var wave_t := _time * 4.2
	var float_y := sin(wave_t) * 1.6
	var cloak_drag := clampf(speed_ratio, 0.4, 1.4) * 9.0
	var cloak_wave := cos(wave_t) * 4.0 + sin(_time * 8.5) * 1.4
	var forward_lean := deg_to_rad(4.5)

	var shadow_alpha := 0.45 - sin(wave_t) * 0.06
	var shadow_rx := (16.0 - sin(wave_t) * 0.8) * width_scale
	_draw_ground_shadow(Vector2(0, 32), shadow_rx, 4.5, shadow_alpha)

	match angle:
		Angle.FRONT:
			_draw_modular_cloak(float_y, cloak_wave, 0.0, Angle.FRONT)
			_draw_head_front(float_y, 0.0)
		Angle.SIDE:
			_draw_modular_weapon(Vector2(-7, 2 + float_y), deg_to_rad(-24.0 + forward_lean), Angle.SIDE)
			_draw_modular_cloak(float_y, cloak_wave, cloak_drag, Angle.SIDE)
			_draw_head_side(float_y, 0.05)
		Angle.BACK:
			_draw_modular_cloak(float_y, cloak_wave, 0.0, Angle.BACK)
			_draw_modular_strap(float_y)
			_draw_modular_weapon(Vector2(1, -2 + float_y), deg_to_rad(152.0), Angle.BACK)
			_draw_head_back(float_y)

# ==================== 3. 冲刺 (DASH) ====================

func _draw_dash(angle: Angle, progress: float) -> void:
	var total_scale := Vector2(body_scale * width_scale, body_scale * height_scale)
	draw_set_transform(Vector2.ZERO, 0.0, total_scale)

	var dash_y := 6.0
	for i in [1, 2]:
		var lag := float(i) * 14.0
		draw_filled_ellipse(Vector2(-lag, dash_y + 24), 16.0 * width_scale, 4.0, Color(col_cloak_outer.r, col_cloak_outer.g, col_cloak_outer.b, 0.18 / float(i)))

	draw_filled_ellipse(Vector2(0, 32), 22.0 * width_scale, 4.0, Color(0.04, 0.06, 0.09, 0.6))
	draw_line(Vector2(-20, 31), Vector2(16, 31), col_eye_core, 1.2)

	match angle:
		Angle.FRONT:
			_draw_modular_cloak(dash_y, 0.0, 16.0, Angle.FRONT)
			_draw_head_front(dash_y + 2, 0.3)
		Angle.SIDE:
			_draw_modular_weapon(Vector2(12, 10 + dash_y), deg_to_rad(75.0), Angle.SIDE)
			_draw_cloak_dash_side(dash_y)
			_draw_head_side(dash_y + 4, 0.5)
			draw_line(Vector2(10, -5 + dash_y), Vector2(-28, -5 + dash_y), col_eye_glow, 2.0)
		Angle.BACK:
			_draw_modular_cloak(dash_y, 0.0, 16.0, Angle.BACK)
			_draw_modular_strap(dash_y)
			_draw_modular_weapon(Vector2(3, 5 + dash_y), deg_to_rad(144.0), Angle.BACK)
			_draw_head_back(dash_y + 2)

# ==================== 4. 攻击挥剑 (ATTACK) ====================

func _draw_attack(angle: Angle, progress: float) -> void:
	var total_scale := Vector2(body_scale * width_scale, body_scale * height_scale)
	draw_set_transform(Vector2.ZERO, 0.0, total_scale)

	var float_y := sin(progress * PI) * -3.0
	_draw_ground_shadow(Vector2(0, 32), 20.0 * width_scale, 5.5, 0.6)

	match angle:
		Angle.FRONT:
			_draw_modular_cloak(float_y, 4.0, 0.0, Angle.FRONT)
			_draw_head_front(float_y, 0.25)
			_draw_slash_crescent(Vector2(0, 12 + float_y), deg_to_rad(90.0), 38.0, progress)
		Angle.SIDE:
			_draw_modular_cloak(float_y, 6.0, 8.0, Angle.SIDE)
			_draw_head_side(float_y, 0.3)
			var slash_rot := lerpf(deg_to_rad(-45.0), deg_to_rad(55.0), progress)
			_draw_modular_weapon(Vector2(16, 4 + float_y), slash_rot, Angle.SIDE)
			_draw_slash_crescent(Vector2(20, 2 + float_y), deg_to_rad(15.0), 44.0, progress)
		Angle.BACK:
			_draw_modular_cloak(float_y, 4.0, 0.0, Angle.BACK)
			_draw_modular_strap(float_y)
			_draw_modular_weapon(Vector2(-1, 3 + float_y), deg_to_rad(152.0), Angle.BACK)
			_draw_head_back(float_y)
			_draw_slash_crescent(Vector2(0, -8 + float_y), deg_to_rad(-90.0), 38.0, progress)

# ==================== 5. 受击硬直 (HIT) ====================

func _draw_hit(angle: Angle, progress: float) -> void:
	var total_scale := Vector2(body_scale * width_scale, body_scale * height_scale)
	draw_set_transform(Vector2.ZERO, 0.0, total_scale)

	var hit_flash := 1.0 - progress
	_draw_ground_shadow(Vector2(0, 32), 17.0 * width_scale, 4.0, 0.4)

	match angle:
		Angle.FRONT:
			_draw_modular_cloak(0.0, -3.0, 0.0, Angle.FRONT)
			_draw_head_front(0.0, 0.4)
		Angle.SIDE:
			_draw_modular_weapon(Vector2(-6, 6), deg_to_rad(-22.0), Angle.SIDE)
			_draw_modular_cloak(0.0, -4.0, -4.0, Angle.SIDE)
			_draw_head_side(0.0, 0.4)
		Angle.BACK:
			_draw_modular_cloak(0.0, -3.0, 0.0, Angle.BACK)
			_draw_modular_strap(0.0)
			_draw_modular_weapon(Vector2(-1, 3), deg_to_rad(-140.0), Angle.BACK)
			_draw_head_back(0.0)

	if hit_flash > 0.05:
		draw_soft_glow(Vector2(0, 0), 24.0, Color(1.0, 1.0, 1.0, hit_flash * 0.4), 2)
		draw_circle(Vector2(0, -10), 12.0, Color(1.0, 1.0, 1.0, hit_flash * 0.35))

# ==================== 头部与面具插槽绘制 ====================

func _draw_ground_shadow(pos: Vector2, rx: float, ry: float, alpha: float) -> void:
	draw_filled_ellipse(pos, rx, ry, Color(0.04, 0.05, 0.08, alpha))
	draw_arc(pos, rx + 2.0, 0, TAU, 28, Color(col_cloak_edge.r, col_cloak_edge.g, col_cloak_edge.b, alpha * 0.35), 1.2, true)

func _draw_head_front(float_y: float, eye_pulse: float) -> void:
	var head_center := Vector2(0, -15 + float_y)
	_draw_modular_headwear(head_center, Angle.FRONT)
	_draw_modular_mask(head_center, Angle.FRONT)
	_draw_modular_eyes(head_center, Angle.FRONT, eye_pulse)

func _draw_head_side(float_y: float, eye_pulse: float) -> void:
	var head_center := Vector2(2, -15 + float_y)
	_draw_modular_headwear(head_center, Angle.SIDE)
	_draw_modular_mask(head_center, Angle.SIDE)
	_draw_modular_eyes(head_center, Angle.SIDE, eye_pulse)

func _draw_head_back(float_y: float) -> void:
	var head_center := Vector2(0, -15 + float_y)
	draw_circle(head_center, 9.5 * head_scale, col_bone)
	draw_arc(head_center, 9.5 * head_scale, 0, TAU, 24, col_bone_shadow, 1.2, true)
	_draw_modular_headwear(head_center, Angle.BACK)

## 插槽 1：面壳轮廓绘制
func _draw_modular_mask(head_center: Vector2, angle: Angle) -> void:
	var hs := head_scale
	if angle == Angle.FRONT:
		var mask_pts: PackedVector2Array = []
		match mask_style:
			"square_rock": # 方阔坚毅岩石面（体修石岳）
				mask_pts = [
					head_center + Vector2(-11 * hs, -6 * hs),
					head_center + Vector2(-11 * hs, 5 * hs),
					head_center + Vector2(-5 * hs, 10 * hs),
					head_center + Vector2(5 * hs, 10 * hs),
					head_center + Vector2(11 * hs, 5 * hs),
					head_center + Vector2(11 * hs, -6 * hs),
					head_center + Vector2(0, -9 * hs)
				]
			"round_petite": # 娇小圆润面（符阵灵童、金算盘、多宝）
				mask_pts = [
					head_center + Vector2(-9 * hs, -4 * hs),
					head_center + Vector2(-9 * hs, 4 * hs),
					head_center + Vector2(-4 * hs, 9 * hs),
					head_center + Vector2(4 * hs, 9 * hs),
					head_center + Vector2(9 * hs, 4 * hs),
					head_center + Vector2(9 * hs, -4 * hs),
					head_center + Vector2(0, -8 * hs)
				]
			"sharp_fox": # 敏锐尖锐狐面（魅影、夺舍）
				mask_pts = [
					head_center + Vector2(-9 * hs, -5 * hs),
					head_center + Vector2(-7 * hs, 3 * hs),
					head_center + Vector2(0, 11 * hs), # 锐长尖下巴
					head_center + Vector2(7 * hs, 3 * hs),
					head_center + Vector2(9 * hs, -5 * hs),
					head_center + Vector2(0, -10 * hs)
				]
			"stout_brute": # 粗犷战鬼面（狂战蛮修）
				mask_pts = [
					head_center + Vector2(-12 * hs, -5 * hs),
					head_center + Vector2(-12 * hs, 6 * hs),
					head_center + Vector2(-4 * hs, 11 * hs),
					head_center + Vector2(4 * hs, 11 * hs),
					head_center + Vector2(12 * hs, 6 * hs),
					head_center + Vector2(12 * hs, -5 * hs),
					head_center + Vector2(0, -9 * hs)
				]
			"oval_chin", _: # 优雅鹅蛋尖下巴（剑修独孤、独臂刀圣）
				mask_pts = [
					head_center + Vector2(-9.5 * hs, -4 * hs),
					head_center + Vector2(-8 * hs, 6 * hs),
					head_center + Vector2(0, 10.0 * hs),
					head_center + Vector2(8 * hs, 6 * hs),
					head_center + Vector2(9.5 * hs, -4 * hs),
					head_center + Vector2(0, -9 * hs)
				]
		draw_colored_polygon(mask_pts, col_bone)
		draw_polyline(mask_pts, col_bone_shadow, 1.2, true)
	else:
		# 侧面轮廓（根据面相分别精修侧脸剪影）
		var side_pts: PackedVector2Array = []
		match mask_style:
			"square_rock", "stout_brute": # 方阔岩面/战鬼厚下颌
				side_pts = [
					head_center + Vector2(-8 * hs, -4 * hs),
					head_center + Vector2(-6 * hs, 6 * hs),
					head_center + Vector2(2 * hs, 10.5 * hs), # 平厚方下巴
					head_center + Vector2(7 * hs, 10.0 * hs),
					head_center + Vector2(10 * hs, 3 * hs),
					head_center + Vector2(8 * hs, -6 * hs),
					head_center + Vector2(0, -9 * hs)
				]
			"round_petite": # 幼圆灵动小侧脸
				side_pts = [
					head_center + Vector2(-6 * hs, -4 * hs),
					head_center + Vector2(-5 * hs, 5 * hs),
					head_center + Vector2(2 * hs, 8.5 * hs), # 较短圆润小下巴
					head_center + Vector2(8 * hs, 2 * hs),
					head_center + Vector2(6 * hs, -5 * hs),
					head_center + Vector2(0, -8 * hs)
				]
			"sharp_fox": # 敏锐尖长前倾狐面
				side_pts = [
					head_center + Vector2(-7 * hs, -5 * hs),
					head_center + Vector2(-5 * hs, 4 * hs),
					head_center + Vector2(5 * hs, 11.5 * hs), # 前挑尖削下颌
					head_center + Vector2(9 * hs, 4 * hs),
					head_center + Vector2(7 * hs, -6 * hs),
					head_center + Vector2(0, -9 * hs)
				]
			"oval_chin", _: # 优雅鹅蛋尖下巴
				side_pts = [
					head_center + Vector2(-7 * hs, -4 * hs),
					head_center + Vector2(-5 * hs, 6 * hs),
					head_center + Vector2(3 * hs, 10.0 * hs),
					head_center + Vector2(9 * hs, 3 * hs),
					head_center + Vector2(7 * hs, -6 * hs),
					head_center + Vector2(0, -9 * hs)
				]
		draw_colored_polygon(side_pts, col_bone)
		draw_polyline(side_pts, col_bone_shadow, 1.2, true)

## 插槽 2：首饰与角冠绘制
func _draw_modular_headwear(head_center: Vector2, angle: Angle) -> void:
	var hs := head_scale
	match horns_style:
		"bull_horns": # 粗壮威猛牛角（体修石岳、狂战蛮修）
			var l_horn := [
				head_center + Vector2(-6 * hs, -6 * hs),
				head_center + Vector2(-16 * hs, -14 * hs),
				head_center + Vector2(-18 * hs, -26 * hs),
				head_center + Vector2(-10 * hs, -18 * hs),
				head_center + Vector2(-4 * hs, -8 * hs)
			]
			var r_horn := [
				head_center + Vector2(4 * hs, -8 * hs),
				head_center + Vector2(10 * hs, -18 * hs),
				head_center + Vector2(18 * hs, -26 * hs),
				head_center + Vector2(16 * hs, -14 * hs),
				head_center + Vector2(6 * hs, -6 * hs)
			]
			if angle == Angle.FRONT:
				draw_colored_polygon(l_horn, col_bone)
				draw_colored_polygon(r_horn, col_bone)
				draw_polyline(l_horn, col_bone_shadow, 1.2, true)
				draw_polyline(r_horn, col_bone_shadow, 1.2, true)
			elif angle == Angle.SIDE:
				var side_horn := [
					head_center + Vector2(-2 * hs, -6 * hs),
					head_center + Vector2(-14 * hs, -18 * hs),
					head_center + Vector2(-16 * hs, -28 * hs),
					head_center + Vector2(-8 * hs, -18 * hs),
					head_center + Vector2(2 * hs, -8 * hs)
				]
				draw_colored_polygon(side_horn, col_bone)
				draw_polyline(side_horn, col_bone_shadow, 1.2, true)
			else: # BACK
				draw_colored_polygon(l_horn, col_bone_shadow)
				draw_colored_polygon(r_horn, col_bone_shadow)
				draw_polyline(l_horn, col_bone, 1.0, true)
				draw_polyline(r_horn, col_bone, 1.0, true)

		"dao_bun": # 道家发髻与木簪（符阵灵童）
			var bun_c: Vector2
			if angle == Angle.SIDE:
				bun_c = head_center + Vector2(-2 * hs, -12 * hs)
			else:
				bun_c = head_center + Vector2(0, -12 * hs)
			draw_circle(bun_c, 5.0 * hs, col_bone)
			draw_circle(bun_c, 2.5 * hs, col_bone_shadow)
			# 横插小木簪
			if angle == Angle.SIDE:
				draw_line(bun_c + Vector2(-7 * hs, -1 * hs), bun_c + Vector2(8 * hs, 1 * hs), col_weapon_main, 1.8)
				draw_circle(bun_c + Vector2(8 * hs, 1 * hs), 1.5, col_weapon_accent)
			else:
				draw_line(bun_c + Vector2(-9 * hs, 0), bun_c + Vector2(9 * hs, 0), col_weapon_main, 1.8)
				draw_circle(bun_c + Vector2(9 * hs, 0), 1.5, col_weapon_accent)

		"bamboo_hat": # 江湖宽檐竹斗笠（独臂刀圣）
			var hat_c := head_center + Vector2(0, -9 * hs)
			if angle == Angle.SIDE:
				hat_c = head_center + Vector2(1 * hs, -9 * hs)
				var hat_pts: PackedVector2Array = [
					hat_c + Vector2(-16 * hs, 2 * hs),
					hat_c + Vector2(-2 * hs, -11 * hs),
					hat_c + Vector2(17 * hs, 4 * hs),
					hat_c + Vector2(2 * hs, -1 * hs)
				]
				draw_colored_polygon(hat_pts, Color(0.38, 0.32, 0.22))
				draw_polyline(hat_pts, Color(0.65, 0.55, 0.38), 1.2, true)
				draw_line(hat_c + Vector2(-2 * hs, -11 * hs), hat_c + Vector2(2 * hs, -1 * hs), Color(0.24, 0.20, 0.14), 1.5)
			elif angle == Angle.BACK:
				var hat_pts: PackedVector2Array = [
					hat_c + Vector2(-18 * hs, 2 * hs),
					hat_c + Vector2(0, -11 * hs),
					hat_c + Vector2(18 * hs, 2 * hs),
					hat_c + Vector2(0, 1 * hs)
				]
				draw_colored_polygon(hat_pts, Color(0.34, 0.28, 0.18))
				draw_polyline(hat_pts, Color(0.60, 0.50, 0.34), 1.2, true)
			else: # FRONT
				var hat_pts: PackedVector2Array = [
					hat_c + Vector2(-18 * hs, 3 * hs),
					hat_c + Vector2(0, -11 * hs),
					hat_c + Vector2(18 * hs, 3 * hs),
					hat_c + Vector2(0, -2 * hs)
				]
				draw_colored_polygon(hat_pts, Color(0.38, 0.32, 0.22))
				draw_polyline(hat_pts, Color(0.65, 0.55, 0.38), 1.2, true)
				draw_line(hat_c + Vector2(0, -11 * hs), hat_c + Vector2(0, -2 * hs), Color(0.24, 0.20, 0.14), 1.5)

		"talisman": # 额前垂落镇魂黄符（夺舍散人）
			if angle == Angle.FRONT:
				var t_pos := head_center + Vector2(0, -10 * hs)
				var t_pts: PackedVector2Array = [
					t_pos + Vector2(-3 * hs, 0),
					t_pos + Vector2(3 * hs, 0),
					t_pos + Vector2(3 * hs, 13 * hs),
					t_pos + Vector2(-3 * hs, 13 * hs)
				]
				draw_colored_polygon(t_pts, Color(0.92, 0.82, 0.28))
				draw_line(t_pos + Vector2(0, 2 * hs), t_pos + Vector2(0, 11 * hs), Color(0.85, 0.20, 0.15), 1.4)
			elif angle == Angle.SIDE:
				# 侧面贴额薄片
				var t_pos := head_center + Vector2(6 * hs, -8 * hs)
				var t_pts: PackedVector2Array = [
					t_pos,
					t_pos + Vector2(1.5 * hs, 0),
					t_pos + Vector2(0.5 * hs, 12 * hs),
					t_pos + Vector2(-1.0 * hs, 12 * hs)
				]
				draw_colored_polygon(t_pts, Color(0.92, 0.82, 0.28))
				draw_line(t_pos + Vector2(0.8 * hs, 2 * hs), t_pos + Vector2(0, 10 * hs), Color(0.85, 0.20, 0.15), 1.2)
			else:
				# 背面：仅见系符红绳结
				draw_line(head_center + Vector2(-5 * hs, -8 * hs), head_center + Vector2(5 * hs, -8 * hs), Color(0.85, 0.20, 0.15), 1.2)

		"gold_crown": # 纯金铜钱三连宝冠（散修金算盘、多宝道人）
			var crown_c := head_center + Vector2(0, -11 * hs)
			if angle == Angle.SIDE:
				crown_c = head_center + Vector2(1 * hs, -11 * hs)
				draw_circle(crown_c + Vector2(-3 * hs, 0), 3.0 * hs, Color(0.88, 0.72, 0.18))
				draw_circle(crown_c + Vector2(2 * hs, -2 * hs), 3.8 * hs, Color(1.0, 0.88, 0.32))
				draw_circle(crown_c + Vector2(2 * hs, -2 * hs), 1.5 * hs, col_void)
			else:
				draw_circle(crown_c + Vector2(-6 * hs, 0), 3.2 * hs, Color(0.95, 0.80, 0.22))
				draw_circle(crown_c + Vector2(6 * hs, 0), 3.2 * hs, Color(0.95, 0.80, 0.22))
				draw_circle(crown_c + Vector2(0, -3 * hs), 4.2 * hs, Color(1.0, 0.88, 0.32))
				draw_circle(crown_c + Vector2(0, -3 * hs), 1.6 * hs, col_void) # 方孔钱眼

		"fox_ears": # 灵动幽狐双尖耳（魅影幽娘）
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

		"none": # 光洁无冠
			pass

		"butterfly", _: # 经典蝶羽仙角（青云剑修独孤）
			_draw_butterfly_horns(head_center, hs, angle)

func _draw_butterfly_horns(head_center: Vector2, hs: float, angle: Angle) -> void:
	if angle == Angle.SIDE:
		var side_horn: PackedVector2Array = [
			head_center + Vector2(-3 * hs, -6 * hs),
			head_center + Vector2(-12 * hs, -18 * hs),
			head_center + Vector2(-16 * hs, -29 * hs),
			head_center + Vector2(-6 * hs, -21 * hs),
			head_center + Vector2(2 * hs, -8 * hs)
		]
		draw_colored_polygon(side_horn, col_bone)
		draw_colored_polygon(PackedVector2Array([
			head_center + Vector2(-3 * hs, -6 * hs),
			head_center + Vector2(-12 * hs, -18 * hs),
			head_center + Vector2(-16 * hs, -29 * hs),
			head_center + Vector2(-8 * hs, -17 * hs)
		]), col_bone_shadow)
		return

	var l_horn: PackedVector2Array = [
		head_center + Vector2(-6 * hs, -4 * hs),
		head_center + Vector2(-14 * hs, -18 * hs),
		head_center + Vector2(-12 * hs, -28 * hs),
		head_center + Vector2(-6 * hs, -20 * hs),
		head_center + Vector2(-3 * hs, -8 * hs)
	]
	draw_colored_polygon(l_horn, col_bone)
	draw_colored_polygon(PackedVector2Array([
		head_center + Vector2(-6 * hs, -4 * hs),
		head_center + Vector2(-14 * hs, -18 * hs),
		head_center + Vector2(-12 * hs, -28 * hs),
		head_center + Vector2(-10 * hs, -18 * hs)
	]), col_bone_shadow)

	var r_horn: PackedVector2Array = [
		head_center + Vector2(3 * hs, -8 * hs),
		head_center + Vector2(6 * hs, -20 * hs),
		head_center + Vector2(12 * hs, -28 * hs),
		head_center + Vector2(14 * hs, -18 * hs),
		head_center + Vector2(6 * hs, -4 * hs)
	]
	draw_colored_polygon(r_horn, col_bone)
	draw_colored_polygon(PackedVector2Array([
		head_center + Vector2(3 * hs, -8 * hs),
		head_center + Vector2(6 * hs, -20 * hs),
		head_center + Vector2(12 * hs, -28 * hs),
		head_center + Vector2(10 * hs, -18 * hs)
	]), col_bone_shadow)

## 插槽 3：眼睛神态与光芒
func _draw_modular_eyes(head_center: Vector2, angle: Angle, eye_pulse: float) -> void:
	var hs := head_scale
	if angle == Angle.FRONT:
		var l_eye := head_center + Vector2(-4.2 * hs, 1.0 * hs)
		var r_eye := head_center + Vector2(4.2 * hs, 1.0 * hs)

		match eye_style:
			"sharp_slit": # 细长冷眸（独臂、金算盘、魅影）
				draw_line(l_eye + Vector2(-3 * hs, 0), l_eye + Vector2(3 * hs, 0), col_void, 2.8)
				draw_line(r_eye + Vector2(-3 * hs, 0), r_eye + Vector2(3 * hs, 0), col_void, 2.8)
				draw_soft_glow(l_eye, 5.0, Color(col_eye_glow.r, col_eye_glow.g, col_eye_glow.b, col_eye_glow.a + eye_pulse), 2)
				draw_soft_glow(r_eye, 5.0, Color(col_eye_glow.r, col_eye_glow.g, col_eye_glow.b, col_eye_glow.a + eye_pulse), 2)
				draw_line(l_eye + Vector2(-1.5 * hs, 0), l_eye + Vector2(1.5 * hs, 0), col_eye_core, 1.6)
				draw_line(r_eye + Vector2(-1.5 * hs, 0), r_eye + Vector2(1.5 * hs, 0), col_eye_core, 1.6)

			"round_pupil": # 灵动道童圆目（符阵灵童、多宝道人）
				draw_circle(l_eye, 3.8 * hs, col_void)
				draw_circle(r_eye, 3.8 * hs, col_void)
				draw_soft_glow(l_eye, 6.0, Color(col_eye_glow.r, col_eye_glow.g, col_eye_glow.b, col_eye_glow.a + eye_pulse), 3)
				draw_soft_glow(r_eye, 6.0, Color(col_eye_glow.r, col_eye_glow.g, col_eye_glow.b, col_eye_glow.a + eye_pulse), 3)
				draw_circle(l_eye + Vector2(0.3, -0.3), 1.8 * hs, col_eye_core)
				draw_circle(r_eye + Vector2(-0.3, -0.3), 1.8 * hs, col_eye_core)

			"angry_slit": # 威严怒目斜挑（体修石岳、狂战蛮修）
				var l_poly: PackedVector2Array = [l_eye + Vector2(-3.5 * hs, 2 * hs), l_eye + Vector2(3.5 * hs, -1.5 * hs), l_eye + Vector2(3 * hs, 1.5 * hs)]
				var r_poly: PackedVector2Array = [r_eye + Vector2(-3.5 * hs, -1.5 * hs), r_eye + Vector2(3.5 * hs, 2 * hs), r_eye + Vector2(-3 * hs, 1.5 * hs)]
				draw_colored_polygon(l_poly, col_void)
				draw_colored_polygon(r_poly, col_void)
				draw_soft_glow(l_eye, 6.0, Color(col_eye_glow.r, col_eye_glow.g, col_eye_glow.b, col_eye_glow.a + eye_pulse), 2)
				draw_soft_glow(r_eye, 6.0, Color(col_eye_glow.r, col_eye_glow.g, col_eye_glow.b, col_eye_glow.a + eye_pulse), 2)
				draw_circle(l_eye, 1.6 * hs, col_eye_core)
				draw_circle(r_eye, 1.6 * hs, col_eye_core)

			"hollow_oval", _: # 经典椭圆深渊月光眼（青云剑修独孤、夺舍散人）
				draw_filled_ellipse(l_eye, 3.8 * hs, 5.2 * hs, col_void)
				draw_filled_ellipse(r_eye, 3.8 * hs, 5.2 * hs, col_void)
				draw_soft_glow(l_eye, 6.0, Color(col_eye_glow.r, col_eye_glow.g, col_eye_glow.b, col_eye_glow.a + eye_pulse), 3)
				draw_soft_glow(r_eye, 6.0, Color(col_eye_glow.r, col_eye_glow.g, col_eye_glow.b, col_eye_glow.a + eye_pulse), 3)
				draw_filled_ellipse(l_eye + Vector2(0.2, -0.2), 2.4 * hs, 3.8 * hs, col_eye_core)
				draw_filled_ellipse(r_eye + Vector2(-0.2, -0.2), 2.4 * hs, 3.8 * hs, col_eye_core)
	else:
		# 侧面单眸（根据眼神风格差异化绘制）
		var eye_pos := head_center + Vector2(4.5 * hs, 1.0 * hs)
		match eye_style:
			"sharp_slit": # 细长冷眸（独臂、金算盘、魅影）
				var slit_pts: PackedVector2Array = [
					eye_pos + Vector2(-3.2 * hs, 1.2 * hs),
					eye_pos + Vector2(3.5 * hs, -1.8 * hs),
					eye_pos + Vector2(2.4 * hs, 0.8 * hs)
				]
				draw_colored_polygon(slit_pts, col_void)
				draw_soft_glow(eye_pos, 5.5, Color(col_eye_glow.r, col_eye_glow.g, col_eye_glow.b, col_eye_glow.a + eye_pulse), 2)
				draw_line(eye_pos + Vector2(-2.0 * hs, 0.8 * hs), eye_pos + Vector2(2.6 * hs, -1.0 * hs), col_eye_core, 1.2)
			"angry_slit": # 暴怒威严目（石岳、狂战）
				var angry_pts: PackedVector2Array = [
					eye_pos + Vector2(-3.5 * hs, -1.5 * hs),
					eye_pos + Vector2(3.5 * hs, 1.8 * hs),
					eye_pos + Vector2(-2.5 * hs, 1.5 * hs)
				]
				draw_colored_polygon(angry_pts, col_void)
				draw_soft_glow(eye_pos, 6.0, Color(col_eye_glow.r, col_eye_glow.g, col_eye_glow.b, col_eye_glow.a + eye_pulse), 2)
				draw_circle(eye_pos + Vector2(0.5 * hs, 0.2 * hs), 1.5 * hs, col_eye_core)
			"round_pupil": # 纯真圆目（符童、多宝）
				draw_circle(eye_pos, 3.2 * hs, col_void)
				draw_soft_glow(eye_pos, 6.0, Color(col_eye_glow.r, col_eye_glow.g, col_eye_glow.b, col_eye_glow.a + eye_pulse), 2)
				draw_circle(eye_pos + Vector2(0.2, -0.2), 1.8 * hs, col_eye_core)
			"hollow_oval", _: # 经典深渊月光眼
				draw_filled_ellipse(eye_pos, 3.8 * hs, 5.2 * hs, col_void)
				draw_soft_glow(eye_pos, 6.5, Color(col_eye_glow.r, col_eye_glow.g, col_eye_glow.b, col_eye_glow.a + eye_pulse), 3)
				draw_filled_ellipse(eye_pos + Vector2(0.3, -0.2), 2.4 * hs, 4.0 * hs, col_eye_core)

# ==================== 斗篷插槽绘制 ====================

func _draw_modular_cloak(float_y: float, wave: float, drag: float, angle: Angle) -> void:
	match angle:
		Angle.FRONT:
			_draw_cloak_front_modular(float_y, wave)
		Angle.SIDE:
			_draw_cloak_side_modular(float_y, wave, drag)
		Angle.BACK:
			_draw_cloak_back_modular(float_y, wave)

func _draw_cloak_front_modular(float_y: float, wave: float) -> void:
	var w := width_scale
	var inner_pts: PackedVector2Array = [
		Vector2(0, -4 + float_y),
		Vector2(-16 * w, 12 + float_y),
		Vector2(-15 * w + wave * 0.3, 30 + float_y),
		Vector2(0, 27 + float_y),
		Vector2(15 * w - wave * 0.3, 30 + float_y),
		Vector2(16 * w, 12 + float_y)
	]
	draw_colored_polygon(inner_pts, col_cloak_inner)

	var outer_pts: PackedVector2Array = []
	match cloak_style:
		"heavy_overcoat": # 厚重平齐长袍大氅（体修石岳、独臂刀圣）
			outer_pts = [
				Vector2(0, -6 + float_y),
				Vector2(-11 * w, -2 + float_y),
				Vector2(-16 * w, 15 + float_y),
				Vector2(-14 * w, 31 + float_y),
				Vector2(0, 30 + float_y),
				Vector2(14 * w, 31 + float_y),
				Vector2(16 * w, 15 + float_y),
				Vector2(11 * w, -2 + float_y)
			]
		"short_cape": # 灵动短披风（符阵灵童）
			outer_pts = [
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
		"tattered_rags": # 破败残条百衲袍（狂战蛮修、夺舍散人）
			outer_pts = [
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
		"royal_shawl": # 锦绣云肩霞帔（散修金算盘、多宝道人）
			outer_pts = [
				Vector2(0, -6 + float_y),
				Vector2(-10 * w, -2 + float_y),
				Vector2(-15 * w, 14 + float_y),
				Vector2(-12 * w, 29 + float_y),
				Vector2(0, 27 + float_y),
				Vector2(12 * w, 29 + float_y),
				Vector2(15 * w, 14 + float_y),
				Vector2(10 * w, -2 + float_y)
			]
			# 双肩云肩装饰弧线
			draw_arc(Vector2(-7 * w, 4 + float_y), 5.0, 0, PI, 16, col_cloak_edge, 1.4)
			draw_arc(Vector2(7 * w, 4 + float_y), 5.0, 0, PI, 16, col_cloak_edge, 1.4)
		"split_flowing", _: # 经典裂帛飞扬（青云剑修独孤、魅影幽娘）
			outer_pts = [
				Vector2(0, -6 + float_y),
				Vector2(-9 * w, -2 + float_y),
				Vector2(-14 * w, 15 + float_y),
				Vector2(-12 * w + wave * 0.4, 28 + float_y),
				Vector2(-7 * w, 24 + float_y),
				Vector2(-3 * w, 31 + float_y),
				Vector2(2 * w, 26 + float_y),
				Vector2(8 * w + wave * 0.3, 29 + float_y),
				Vector2(14 * w, 15 + float_y),
				Vector2(9 * w, -2 + float_y)
			]
	draw_colored_polygon(outer_pts, col_cloak_outer)
	draw_polyline(outer_pts, col_cloak_edge, 1.2, true)

func _draw_cloak_side_modular(float_y: float, wave: float, extra_drag: float) -> void:
	var w := width_scale
	var drag := extra_drag
	var side_pts: PackedVector2Array = []
	match cloak_style:
		"heavy_overcoat": # 厚重大氅长袍（体修石岳、独臂刀圣）
			side_pts = [
				Vector2(2, -6 + float_y),
				Vector2(-5 * w, 0 + float_y),
				Vector2(-16 * w - drag * 0.4 + wave * 0.5, 12 + float_y),
				Vector2(-21 * w - drag * 0.8 + wave * 0.7, 32 + float_y),
				Vector2(-10 * w - drag * 0.4 + wave * 0.5, 31 + float_y),
				Vector2(-2 * w, 32 + float_y),
				Vector2(7 * w, 18 + float_y),
				Vector2(7 * w, 0 + float_y)
			]
		"short_cape": # 灵动短披风（符阵灵童）
			side_pts = [
				Vector2(2, -6 + float_y),
				Vector2(-4 * w, 0 + float_y),
				Vector2(-13 * w - drag * 0.5 + wave * 1.1, 10 + float_y),
				Vector2(-16 * w - drag * 0.9 + wave * 1.4, 22 + float_y),
				Vector2(-8 * w - drag * 0.4 + wave * 0.7, 21 + float_y),
				Vector2(-1 * w, 23 + float_y),
				Vector2(5 * w, 14 + float_y),
				Vector2(5 * w, 0 + float_y)
			]
		"tattered_rags": # 破损百衲残袍（狂战蛮修、夺舍散人）
			side_pts = [
				Vector2(2, -6 + float_y),
				Vector2(-4 * w, 0 + float_y),
				Vector2(-15 * w - drag * 0.5 + wave, 12 + float_y),
				Vector2(-22 * w - drag + wave * 1.5, 30 + float_y),
				Vector2(-16 * w - drag * 0.8 + wave * 1.0, 24 + float_y),
				Vector2(-11 * w - drag * 0.5 + wave * 0.8, 29 + float_y),
				Vector2(-6 * w - drag * 0.3, 23 + float_y),
				Vector2(-2 * w, 28 + float_y),
				Vector2(6 * w, 18 + float_y),
				Vector2(6 * w, 0 + float_y)
			]
		"royal_shawl": # 云肩华贵长袍（散修金算盘、多宝道人）
			side_pts = [
				Vector2(2, -6 + float_y),
				Vector2(-5 * w, 0 + float_y),
				Vector2(-15 * w - drag * 0.4 + wave * 0.6, 12 + float_y),
				Vector2(-19 * w - drag * 0.7 + wave * 0.9, 29 + float_y),
				Vector2(-10 * w - drag * 0.4 + wave * 0.5, 27 + float_y),
				Vector2(-3 * w, 30 + float_y),
				Vector2(7 * w, 18 + float_y),
				Vector2(7 * w, 0 + float_y)
			]
		"split_flowing", _: # 经典飘逸双尾斗篷（青云剑修独孤、魅影幽娘）
			side_pts = [
				Vector2(2, -6 + float_y),
				Vector2(-4 * w, 0 + float_y),
				Vector2(-15 * w - drag * 0.4 + wave, 12 + float_y),
				Vector2(-20 * w - drag + wave * 1.3, 29 + float_y),
				Vector2(-9 * w - drag * 0.5 + wave * 0.7, 26 + float_y),
				Vector2(-2 * w, 30 + float_y),
				Vector2(6 * w, 18 + float_y),
				Vector2(6 * w, 0 + float_y)
			]
	draw_colored_polygon(side_pts, col_cloak_outer)
	draw_polyline(side_pts, col_cloak_edge, 1.2, true)

func _draw_cloak_dash_side(dash_y: float) -> void:
	var w := width_scale
	var dash_pts: PackedVector2Array = [
		Vector2(4, -8 + dash_y),
		Vector2(-6 * w, -4 + dash_y),
		Vector2(-32 * w, 0 + dash_y),
		Vector2(-48 * w, 6 + dash_y),
		Vector2(-28 * w, 12 + dash_y),
		Vector2(0, 14 + dash_y)
	]
	draw_colored_polygon(dash_pts, col_cloak_outer)
	draw_polyline(dash_pts, col_cloak_edge, 1.4, true)

func _draw_cloak_back_modular(float_y: float, wave: float) -> void:
	var w := width_scale
	var back_pts: PackedVector2Array = []
	match cloak_style:
		"heavy_overcoat": # 宽厚大氅齐整下摆
			back_pts = [
				Vector2(-10 * w, -6 + float_y), Vector2(10 * w, -6 + float_y),
				Vector2(17 * w, 14 + float_y),
				Vector2(15 * w + wave * 0.2, 32 + float_y),
				Vector2(0, 31 + float_y),
				Vector2(-15 * w - wave * 0.2, 32 + float_y),
				Vector2(-17 * w, 14 + float_y)
			]
		"short_cape": # 短披风高下摆
			back_pts = [
				Vector2(-8 * w, -6 + float_y), Vector2(8 * w, -6 + float_y),
				Vector2(13 * w, 12 + float_y),
				Vector2(11 * w + wave * 0.3, 23 + float_y),
				Vector2(0, 24 + float_y),
				Vector2(-11 * w - wave * 0.3, 23 + float_y),
				Vector2(-13 * w, 12 + float_y)
			]
		"tattered_rags": # 破损撕裂锯齿状披风
			back_pts = [
				Vector2(-9 * w, -6 + float_y), Vector2(9 * w, -6 + float_y),
				Vector2(16 * w, 14 + float_y),
				Vector2(14 * w + wave * 0.4, 31 + float_y),
				Vector2(8 * w, 24 + float_y),
				Vector2(4 * w, 31 + float_y),
				Vector2(0, 25 + float_y),
				Vector2(-4 * w, 30 + float_y),
				Vector2(-8 * w, 24 + float_y),
				Vector2(-14 * w - wave * 0.4, 31 + float_y),
				Vector2(-16 * w, 14 + float_y)
			]
		"royal_shawl": # 霞帔圆润下摆
			back_pts = [
				Vector2(-9 * w, -6 + float_y), Vector2(9 * w, -6 + float_y),
				Vector2(16 * w, 14 + float_y),
				Vector2(14 * w + wave * 0.3, 29 + float_y),
				Vector2(6 * w, 27 + float_y),
				Vector2(0, 30 + float_y),
				Vector2(-6 * w, 27 + float_y),
				Vector2(-14 * w - wave * 0.3, 29 + float_y),
				Vector2(-16 * w, 14 + float_y)
			]
		"split_flowing", _: # 经典飘逸飞燕双尾
			back_pts = [
				Vector2(-9 * w, -6 + float_y), Vector2(9 * w, -6 + float_y),
				Vector2(16 * w, 14 + float_y),
				Vector2(13 * w + wave * 0.4, 30 + float_y),
				Vector2(6 * w, 26 + float_y),
				Vector2(0, 32 + float_y),
				Vector2(-6 * w, 26 + float_y),
				Vector2(-14 * w - wave * 0.4, 30 + float_y),
				Vector2(-16 * w, 14 + float_y)
			]
	draw_colored_polygon(back_pts, col_cloak_outer)
	draw_polyline(back_pts, col_cloak_edge, 1.2, true)

func _draw_modular_chest(_float_y: float) -> void:
	# 正面下颌处纯净无口，严禁在此绘制任何小圆/圆扣/骨饰，杜绝视觉误判为“嘴巴”或“漏出后面的武器”
	pass

# ==================== 背负本命法器插槽绘制 ====================

func _draw_modular_strap(float_y: float) -> void:
	match strap_style:
		"dual": # 双肩背带（体修、刺客、多宝）
			var l_top := Vector2(-6, -6 + float_y)
			var l_bot := Vector2(-4, 14 + float_y)
			var r_top := Vector2(6, -6 + float_y)
			var r_bot := Vector2(4, 14 + float_y)
			draw_line(l_top, l_bot, Color(0.05, 0.08, 0.12, 0.95), 2.2)
			draw_line(r_top, r_bot, Color(0.05, 0.08, 0.12, 0.95), 2.2)
			draw_circle(Vector2(0, 4 + float_y), 2.8, col_bone)
			draw_circle(Vector2(0, 4 + float_y), 1.4, col_void)
		"floating": # 悬浮法宝（不画皮带，画一圈灵气悬浮环）
			draw_arc(Vector2(0, 4 + float_y), 9.0, 0, TAU, 16, Color(col_cloak_edge.r, col_cloak_edge.g, col_cloak_edge.b, 0.4), 1.2)
		"diagonal", _: # 经典斜跨剑带
			var p_top := Vector2(7, -6 + float_y)
			var p_bot := Vector2(-5, 12 + float_y)
			draw_line(p_top, p_bot, Color(0.05, 0.08, 0.12, 0.95), 2.4)
			draw_line(p_top, p_bot, col_cloak_edge, 0.8)
			var center := (p_top + p_bot) * 0.5
			draw_circle(center, 2.4, col_bone)
			draw_circle(center, 1.2, col_void)

## 绘制法器（严格遵循摄影三向铁律：正面完全收于背部不露下沿、侧面贴背不露底、背面外挂最表层）
func _draw_modular_weapon(pos: Vector2, rot: float, angle: Angle) -> void:
	# 正面视角：法器严格背负在身后，正面被身躯与斗篷严密遮挡，绝不在正面露头或下摆露馅
	if angle == Angle.FRONT:
		return
	var t := Transform2D(rot, pos)

	match weapon_type:
		"stone_pillar": # 玄重墨石尺（体修石岳）
			# 总长 28px，宽 6px，端庄浑厚
			var r_pts: PackedVector2Array = [
				t * Vector2(-3.2, -15), t * Vector2(3.2, -15),
				t * Vector2(3.2, 5), t * Vector2(-3.2, 5)
			]
			draw_colored_polygon(r_pts, col_weapon_main)
			draw_colored_polygon(PackedVector2Array([
				t * Vector2(0, -15), t * Vector2(3.2, -15),
				t * Vector2(3.2, 5), t * Vector2(0, 5)
			]), col_weapon_shadow)
			# 古金符文槽
			draw_line(t * Vector2(0, -12), t * Vector2(0, 2), col_weapon_accent, 1.2)
			# 厚重玄铁手柄与石环
			draw_line(t * Vector2(0, 5), t * Vector2(0, 11), col_weapon_shadow, 2.6)
			draw_circle(t * Vector2(0, 11.5), 1.8, col_weapon_main)

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
			# 八卦小木格
			draw_line(t * Vector2(-3, 3), t * Vector2(3, 3), col_weapon_accent, 2.0)
			draw_line(t * Vector2(0, 3), t * Vector2(0, 9.5), col_weapon_main, 1.8)
			draw_circle(t * Vector2(0, 10), 1.4, col_weapon_accent)
			# 挂带符尾小黄穗
			if angle != Angle.FRONT:
				draw_line(t * Vector2(0, 10), t * Vector2(-2, 14), Color(0.95, 0.85, 0.3), 1.2)

		"golden_abacus": # 乾坤金算盘（散修金算盘）
			var ab_pts: PackedVector2Array = [
				t * Vector2(-5.5, -12), t * Vector2(5.5, -12),
				t * Vector2(5.5, 6), t * Vector2(-5.5, 6)
			]
			draw_colored_polygon(ab_pts, col_weapon_main)
			draw_polyline(ab_pts, col_weapon_shadow, 1.2, true)
			# 横梁
			draw_line(t * Vector2(-5, -6), t * Vector2(5, -6), col_weapon_shadow, 1.4)
			# 算珠点缀
			for b in [-3, 0, 3]:
				draw_circle(t * Vector2(b, -9), 0.9, col_weapon_accent)
				draw_circle(t * Vector2(b, 0), 0.9, col_weapon_accent)
				draw_circle(t * Vector2(b, 3), 0.9, col_weapon_accent)
			# 算盘手柄
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
				draw_line(dt * Vector2(0, 2), dt * Vector2(0, 7.5), col_weapon_shadow, 1.6)
				draw_circle(dt * Vector2(0, 8), 1.2, col_weapon_accent)

		"broken_blade": # 厚背断马狂刀（独臂刀圣）
			var b_pts: PackedVector2Array = [
				t * Vector2(-2.5, -14), t * Vector2(4.5, -10), # 斜口断刃
				t * Vector2(4.0, 4), t * Vector2(-2.5, 4)
			]
			draw_colored_polygon(b_pts, col_weapon_main)
			# 厚背阴影刻线
			draw_line(t * Vector2(-2.5, -14), t * Vector2(-2.5, 4), col_weapon_shadow, 1.8)
			# 刀盘与缠布长手柄
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
			# 兽骨长战柄
			draw_line(t * Vector2(0, -14), t * Vector2(0, 11), col_weapon_shadow, 2.4)
			draw_circle(t * Vector2(0, 11.5), 1.8, col_weapon_accent)

		"soul_banner": # 墨竹引魂冥幡（夺舍散人）
			# 细长竹杆
			draw_line(t * Vector2(0, -16), t * Vector2(0, 11), Color(0.18, 0.20, 0.22), 2.0)
			# 横挑小枝
			draw_line(t * Vector2(-1, -14), t * Vector2(6, -14), Color(0.18, 0.20, 0.22), 1.4)
			# 下垂飘扬冥幡布
			var banner_pts: PackedVector2Array = [
				t * Vector2(1, -13), t * Vector2(6, -13),
				t * Vector2(5, 4), t * Vector2(1, 2)
			]
			draw_colored_polygon(banner_pts, col_weapon_main)
			draw_circle(t * Vector2(3, -5), 1.4, col_weapon_accent) # 幽绿魂火印

		"treasure_chest": # 紫金百宝乾坤匣（多宝道人）
			var box_pts: PackedVector2Array = [
				t * Vector2(-6.5, -9), t * Vector2(6.5, -9),
				t * Vector2(6.5, 7), t * Vector2(-6.5, 7)
			]
			draw_colored_polygon(box_pts, col_weapon_main)
			draw_polyline(box_pts, col_weapon_shadow, 1.2, true)
			# 紫金箍线
			draw_line(t * Vector2(-6.5, 0), t * Vector2(6.5, 0), col_weapon_accent, 1.6)
			draw_line(t * Vector2(0, -9), t * Vector2(0, 7), col_weapon_accent, 1.6)
			# 宝匣小金锁
			draw_circle(t * Vector2(0, 0), 2.2, Color(1.0, 0.88, 0.35))
			draw_circle(t * Vector2(0, 0), 1.0, col_void)

		"bone_nail", _: # 纯白月光骨钉/长剑（青云剑修独孤）
			var nail_pts: PackedVector2Array = [
				t * Vector2(0, -15),   # 锐利剑尖
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
			draw_line(t * Vector2(0, -13), t * Vector2(0, 2), col_weapon_accent, 1.0)
			# 剑格与剑柄
			var guard_pts: PackedVector2Array = [
				t * Vector2(-3.0, 3), t * Vector2(3.0, 3),
				t * Vector2(2.2, 5.5), t * Vector2(-2.2, 5.5)
			]
			draw_colored_polygon(guard_pts, col_bone_shadow)
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
