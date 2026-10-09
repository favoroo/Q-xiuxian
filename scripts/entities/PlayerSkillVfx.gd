class_name PlayerSkillVfx
extends Node2D

## 角色随行神通（技能）视觉特效控制器与渲染器
## 负责表现角色在施放技能瞬间与增益持续期间的国风修仙视觉效果：
##   1. 金光护体 (aegis): 六方金光结界 + 护体灵符环绕 + 破灭金芒碎环
##   2. 疾风咒 (haste): 脚底疾风八卦光环 + 向上生腾的风刃灵气粒子 + 攻速超频共振
##   3. 神行术 (gale): 御风破空残影 (Ghost Trail) + 踝下青苍风旋
##   4. 缩地成寸 (dash): 瞬身拉伸剑光残影 + 冲刺方向破空灵芒锥
##   5. 回春术 (renewal): 地面甘露阵纹 + 旋升式回春生机光柱
##
## 取色统一源自 GameStyle（唯一取色入口），图形基于 CanvasItem 程序化动态绘制，
## 残影使用轻量池化 Sprite2D（top_level=true），零额外纹理负担，性能开销极低。

# ---------------- 常量与配置 ----------------
## 角色视觉参考点（基于 192x192@0.5 贴图实测：高度约 60px，脚在 +16，头在 -42）
const BODY_CENTER := Vector2(0.0, -14.0)    ## 角色身躯中心（高宽覆盖的核心基准）
const FEET_CENTER := Vector2(0.0, 14.0)     ## 角色脚底地面中心

## 金光护体大结界尺寸：完全包裹人物头顶发冠至脚底影子
const SHIELD_RX := 38.0                     ## 金光护体横向半径（包裹双臂与身侧）
const SHIELD_RY := 48.0                     ## 金光护体纵向半径（从 y=-62 到 y=+34，全包裹）

## 疾风咒全包裹风暴结界尺寸
const HASTE_GROUND_RADIUS := 36.0           ## 脚底八卦疾风大阵半径
const HASTE_BODY_RX := 34.0                 ## 身周风刃气茧横向半径
const HASTE_BODY_RY := 44.0                 ## 身周风刃气茧纵向半径

const GHOST_POOL_CAP := 12                  ## 残影池上限

# ---------------- 运行时状态 ----------------
@onready var player: CharacterBody2D = get_parent() as CharacterBody2D

# 1. 金光护体状态
var aegis_active: bool = false
var aegis_timer: float = 0.0
var aegis_max_dur: float = 1.6
var aegis_rot: float = 0.0
var aegis_shatter_progress: float = -1.0  ## >=0 时播放消散碎裂动画

# 2. 疾风咒状态
var haste_active: bool = false
var haste_timer: float = 0.0
var haste_rot: float = 0.0
var haste_particle_timer: float = 0.0
var haste_sparks: Array[Dictionary] = []  ## {pos, vel, life, max_life}

# 3. 神行术状态
var gale_active: bool = false
var gale_timer: float = 0.0
var gale_trail_timer: float = 0.0
var gale_wind_phase: float = 0.0

# 4. 缩地成寸状态
var dash_flash_timer: float = 0.0
var dash_dir: Vector2 = Vector2.DOWN

# 5. 回春术状态
var renewal_progress: float = -1.0  ## >=0 播放回春法阵与生机光柱 (0.0 -> 1.0)
var renewal_particles: Array[Dictionary] = []

# 6. 残影对象池 (Sprite2D)
var _ghost_pool: Array[Sprite2D] = []
var _active_ghosts: Array[Sprite2D] = []

func _ready() -> void:
	z_index = 2  ## 略高于角色精灵 (AnimatedSprite2D 默认 z_index 0)
	_init_ghost_pool()

func _init_ghost_pool() -> void:
	for i in range(GHOST_POOL_CAP):
		var s := Sprite2D.new()
		s.top_level = true
		s.visible = false
		s.z_index = 1
		add_child(s)
		_ghost_pool.append(s)

func _acquire_ghost() -> Sprite2D:
	for s in _ghost_pool:
		if not s.visible:
			return s
	return null

# ---------------- 技能触发入口 ----------------

## 缩地成寸瞬间释放
func on_dash_start(direction: Vector2, distance: float, duration: float) -> void:
	dash_dir = direction.normalized()
	dash_flash_timer = duration + 0.08
	# 生成冲刺起步与拉伸残影
	spawn_ghost(Color(GameStyle.BLUE_EDGE, 0.75), 0.28)
	queue_redraw()

## 神行术激活
func on_gale_start(duration: float) -> void:
	gale_active = true
	gale_timer = duration
	gale_trail_timer = 0.0
	spawn_ghost(Color(GameStyle.BLUE, 0.6), 0.25)
	queue_redraw()

## 疾风咒激活
func on_haste_start(duration: float) -> void:
	haste_active = true
	haste_timer = duration
	haste_rot = 0.0
	haste_particle_timer = 0.0
	queue_redraw()

## 金光护体激活
func on_aegis_start(duration: float) -> void:
	aegis_active = true
	aegis_max_dur = duration
	aegis_timer = duration
	aegis_shatter_progress = -1.0
	queue_redraw()

## 回春术施放
func on_renewal_cast() -> void:
	renewal_progress = 0.0
	renewal_particles.clear()
	for i in range(12):
		var ang := float(i) * (TAU / 12.0)
		renewal_particles.append({
			"ang": ang,
			"radius": randf_range(16.0, 34.0),
			"y": randf_range(12.0, 22.0),
			"speed_y": randf_range(95.0, 145.0),
			"rot_speed": randf_range(3.5, 6.0)
		})
	queue_redraw()

# ---------------- 每帧逻辑更新 ----------------

func update_vfx(delta: float, is_moving: bool, velocity: Vector2) -> void:
	var needs_redraw := false

	# 1. 残影生命周期淡出
	for s in _ghost_pool:
		if s.visible:
			var life: float = float(s.get_meta(&"life", 0.0)) - delta
			var max_l: float = float(s.get_meta(&"max_life", 0.2))
			if life <= 0.0:
				s.visible = false
			else:
				s.set_meta(&"life", life)
				var base_col: Color = s.get_meta(&"base_color", Color.WHITE)
				var ratio := clampf(life / max_l, 0.0, 1.0)
				s.modulate.a = base_col.a * ratio

	# 2. 金光护体
	if aegis_active:
		needs_redraw = true
		aegis_rot += delta * 2.4
		aegis_timer -= delta
		if aegis_timer <= 0.0:
			aegis_active = false
			aegis_shatter_progress = 0.0  ## 启动消散碎裂动效
	elif aegis_shatter_progress >= 0.0:
		needs_redraw = true
		aegis_shatter_progress += delta * 4.5  ## 约 0.22 秒碎散淡出
		if aegis_shatter_progress >= 1.0:
			aegis_shatter_progress = -1.0

	# 3. 疾风咒
	if haste_active:
		needs_redraw = true
		haste_rot += delta * 7.5
		haste_timer -= delta
		if haste_timer <= 0.0:
			haste_active = false
			haste_sparks.clear()
		else:
			# 周期性散逸微风刃灵气（覆盖全身范围）
			haste_particle_timer -= delta
			if haste_particle_timer <= 0.0:
				haste_particle_timer = 0.06
				if haste_sparks.size() < 14:
					var p_ang := randf() * TAU
					var spawn_y := randf_range(-38.0, 14.0)
					var spawn_x := cos(p_ang) * randf_range(16.0, 32.0)
					haste_sparks.append({
						"pos": Vector2(spawn_x, spawn_y),
						"vel": Vector2(randf_range(-20.0, 20.0), randf_range(-60.0, -110.0)),
						"life": 0.28,
						"max_life": 0.28,
					})

	# 更新疾风咒飞散微粒子
	if not haste_sparks.is_empty():
		needs_redraw = true
		var i := haste_sparks.size() - 1
		while i >= 0:
			var sp: Dictionary = haste_sparks[i]
			sp["life"] = float(sp["life"]) - delta
			if float(sp["life"]) <= 0.0:
				haste_sparks.remove_at(i)
			else:
				sp["pos"] = Vector2(sp["pos"]) + Vector2(sp["vel"]) * delta
			i -= 1

	# 4. 神行术
	if gale_active:
		needs_redraw = true
		gale_wind_phase += delta * 12.0
		gale_timer -= delta
		if gale_timer <= 0.0:
			gale_active = false
		else:
			# 移动中产生残影
			if is_moving and velocity.length_squared() > 1600.0:
				gale_trail_timer -= delta
				if gale_trail_timer <= 0.0:
					gale_trail_timer = 0.08
					spawn_ghost(Color(GameStyle.BLUE, 0.45), 0.22)

	# 5. 缩地成寸
	if dash_flash_timer > 0.0:
		needs_redraw = true
		dash_flash_timer -= delta
		if is_moving and fmod(dash_flash_timer, 0.04) < delta:
			spawn_ghost(Color(GameStyle.BLUE_EDGE, 0.6), 0.20)

	# 6. 回春术
	if renewal_progress >= 0.0:
		needs_redraw = true
		renewal_progress += delta * 1.8  ## 约 0.55s 走完
		for p in renewal_particles:
			p["y"] = float(p["y"]) - float(p["speed_y"]) * delta
			p["ang"] = float(p["ang"]) + float(p["rot_speed"]) * delta
		if renewal_progress >= 1.0:
			renewal_progress = -1.0
			renewal_particles.clear()

	if needs_redraw:
		queue_redraw()

## 生成一具角色当前帧的世界残影
func spawn_ghost(color: Color, duration: float) -> void:
	if player == null:
		return
	var sprite: AnimatedSprite2D = player.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite == null or sprite.sprite_frames == null:
		return

	var anim := sprite.animation
	if not sprite.sprite_frames.has_animation(anim):
		return
	var frame_idx := sprite.frame
	var frame_count := sprite.sprite_frames.get_frame_count(anim)
	if frame_count <= 0:
		return
	var tex := sprite.sprite_frames.get_frame_texture(anim, frame_idx % frame_count)
	if tex == null:
		return

	var ghost := _acquire_ghost()
	if ghost == null:
		return

	ghost.texture = tex
	ghost.offset = sprite.offset
	ghost.flip_h = sprite.flip_h
	ghost.scale = sprite.global_scale
	ghost.rotation = sprite.global_rotation
	ghost.global_position = sprite.global_position
	ghost.modulate = color
	ghost.set_meta(&"base_color", color)
	ghost.set_meta(&"life", duration)
	ghost.set_meta(&"max_life", duration)
	ghost.visible = true

# ---------------- 动态图形绘制 ----------------

func _draw() -> void:
	# 绘制层级：相对于 Player 中心 (0, 0)
	# 1. 疾风咒：脚底疾风光环与灵气碎芒
	if haste_active:
		_draw_haste_fx()

	# 2. 神行术：踝部风旋微弧
	if gale_active:
		_draw_gale_wind()

	# 3. 缩地成寸：前方破空尖锥弧光
	if dash_flash_timer > 0.0:
		_draw_dash_cone()

	# 4. 金光护体：结界护罩与环绕符珠
	if aegis_active or aegis_shatter_progress >= 0.0:
		_draw_aegis_shield()

	# 5. 回春术：涌流生机与莲花法阵
	if renewal_progress >= 0.0:
		_draw_renewal_fx()

## 绘制【疾风咒】：全身风暴气茧包裹 + 脚底八卦疾风大阵 + 升腾风刃粒子
func _draw_haste_fx() -> void:
	var col_main := Color(GameStyle.BLUE, 0.78)
	var col_edge := Color(GameStyle.BLUE_EDGE, 0.95)
	var col_fill := Color(GameStyle.BLUE.r, GameStyle.BLUE.g, GameStyle.BLUE.b, 0.11)

	# 1. 全身疾风气茧底衬（椭圆半透明风幕，把人物从头顶到脚底完整包裹）
	var pulse := sin(haste_rot * 0.8) * 1.5
	var rx := HASTE_BODY_RX + pulse
	var ry := HASTE_BODY_RY + pulse
	var cocoon_pts := PackedVector2Array()
	for i in range(24):
		var a := float(i) * (TAU / 24.0)
		cocoon_pts.append(BODY_CENTER + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(cocoon_pts, col_fill)

	# 2. 环绕全身的 3 道高速椭圆风刃大弧（贴合人形高宽比，包裹头尾与双肩）
	for i in range(3):
		var base_a := haste_rot + float(i) * (TAU / 3.0)
		var arc_pts := PackedVector2Array()
		var steps := 12
		var span := 1.45
		for s in range(steps + 1):
			var a := base_a + span * (float(s) / float(steps))
			arc_pts.append(BODY_CENTER + Vector2(cos(a) * rx, sin(a) * ry))
		draw_polyline(arc_pts, col_edge, 2.6, true)
		# 风刃弧头凝光白芯
		var tip := arc_pts[arc_pts.size() - 1]
		draw_circle(tip, 2.8, Color.WHITE)

	# 3. 内层反向交织的护身螺旋风流（立体包裹感）
	var inner_rx := rx * 0.78
	var inner_ry := ry * 0.82
	for i in range(2):
		var base_a := -haste_rot * 1.15 + float(i) * PI
		var inner_pts := PackedVector2Array()
		var steps := 10
		var span := 1.65
		for s in range(steps + 1):
			var a := base_a + span * (float(s) / float(steps))
			inner_pts.append(BODY_CENTER + Vector2(cos(a) * inner_rx, sin(a) * inner_ry))
		draw_polyline(inner_pts, col_main, 1.8, true)

	# 4. 脚底八卦疾风大阵（地面扁平透视风轮）
	for i in range(3):
		var g_a := haste_rot * 1.3 + float(i) * (TAU / 3.0)
		draw_arc(FEET_CENTER, HASTE_GROUND_RADIUS, g_a, g_a + 1.3, 16, col_main, 2.0, true)

	# 5. 飞散的全身向上风刃粒子
	for sp in haste_sparks:
		var ratio := clampf(float(sp["life"]) / float(sp["max_life"]), 0.0, 1.0)
		var p_col := Color(GameStyle.BLUE_EDGE.r, GameStyle.BLUE_EDGE.g, GameStyle.BLUE_EDGE.b, ratio * 0.92)
		var p_pos := Vector2(sp["pos"])
		var p_tail := p_pos - Vector2(sp["vel"]).normalized() * (9.0 * ratio)
		draw_line(p_tail, p_pos, p_col, 2.2, true)

## 绘制【神行术】：脚底御风青轮 + 身侧破风流线（覆盖全身高度）
func _draw_gale_wind() -> void:
	var wave := sin(gale_wind_phase) * 2.5
	var col_edge := Color(GameStyle.BLUE_EDGE, 0.88)
	var col_main := Color(GameStyle.BLUE, 0.65)

	# 1. 脚底御风大青轮（透视椭圆风环，完整托住双足）
	var wheel_rx := 32.0
	var wheel_ry := 13.0
	for i in range(2):
		var base_a := gale_wind_phase * 0.8 + float(i) * PI
		var pts := PackedVector2Array()
		for s in range(11):
			var a := base_a + 1.8 * (float(s) / 10.0)
			pts.append(FEET_CENTER + Vector2(cos(a) * wheel_rx, sin(a) * wheel_ry))
		draw_polyline(pts, col_edge, 2.4, true)

	# 2. 身躯两侧环绕的上升青风流带（从脚底盘绕至肩头）
	for side_val in [-1.0, 1.0]:
		var side: float = float(side_val)
		var ribbon := PackedVector2Array()
		for s in range(9):
			var t := float(s) / 8.0
			var y := lerpf(16.0, -38.0, t)
			var x: float = side * (26.0 + sin(gale_wind_phase + t * PI * 2.0) * 5.0)
			ribbon.append(Vector2(x, y))
		draw_polyline(ribbon, col_main, 2.0, true)
	draw_arc(BODY_CENTER, 32.0 + wave, -PI * 0.8, -PI * 0.2, 14, col_edge, 1.8, true)

## 绘制【缩地成寸】：全包裹破空灵芒锥（从身躯中心向前锐利撑开，包覆全身宽幅）
func _draw_dash_cone() -> void:
	var cone_dir := dash_dir
	var tip := BODY_CENTER + cone_dir * 46.0
	var left_wing := tip - cone_dir.rotated(deg_to_rad(36.0)) * 54.0
	var right_wing := tip - cone_dir.rotated(-deg_to_rad(36.0)) * 54.0
	var col_outer := Color(GameStyle.BLUE_EDGE, 0.9)
	var col_fill := Color(GameStyle.BLUE.r, GameStyle.BLUE.g, GameStyle.BLUE.b, 0.18)

	draw_colored_polygon(PackedVector2Array([left_wing, tip, right_wing]), col_fill)
	draw_line(left_wing, tip, col_outer, 3.2, true)
	draw_line(right_wing, tip, col_outer, 3.2, true)

	var inner_tip := BODY_CENTER + cone_dir * 38.0
	var inner_left := inner_tip - cone_dir.rotated(deg_to_rad(28.0)) * 38.0
	var inner_right := inner_tip - cone_dir.rotated(-deg_to_rad(28.0)) * 38.0
	draw_line(inner_left, inner_tip, Color(1, 1, 1, 0.95), 2.2, true)
	draw_line(inner_right, inner_tip, Color(1, 1, 1, 0.95), 2.2, true)

## 绘制【金光护体】：全身包裹八方天罡金光大结界 + 浑天内环 + 6 颗护法金符珠
func _draw_aegis_shield() -> void:
	var pulse := sin(aegis_rot * 2.5) * 1.8
	var rx := SHIELD_RX + pulse
	var ry := SHIELD_RY + pulse

	if aegis_active:
		var col_border := Color(GameStyle.YELLOW_EDGE, 0.95)
		var col_inner := Color(GameStyle.YELLOW, 0.55)
		var col_fill := Color(GameStyle.YELLOW.r, GameStyle.YELLOW.g, GameStyle.YELLOW.b, 0.18)

		# 1. 全身包裹八角天罡金光罩（中心对准 BODY_CENTER，上下从 -62 到 +34 完整罩住发冠与双足）
		var poly_pts := PackedVector2Array()
		var line_pts := PackedVector2Array()
		for i in range(8):
			var a := aegis_rot * 0.7 + float(i) * (TAU / 8.0)
			var pt := BODY_CENTER + Vector2(cos(a) * rx, sin(a) * ry)
			poly_pts.append(pt)
			line_pts.append(pt)
		line_pts.append(poly_pts[0])  # 闭合描边

		draw_colored_polygon(poly_pts, col_fill)
		draw_polyline(line_pts, col_border, 2.8, true)

		# 2. 结界内层椭圆浑天金环（贴合罩体轮廓）
		var inner_pts := PackedVector2Array()
		for i in range(25):
			var a := float(i) * (TAU / 24.0)
			inner_pts.append(BODY_CENTER + Vector2(cos(a) * (rx * 0.84), sin(a) * (ry * 0.84)))
		draw_polyline(inner_pts, col_inner, 1.5, true)

		# 3. 脚底天罡金莲阵盘（地面支撑感）
		draw_arc(FEET_CENTER, 32.0, aegis_rot, aegis_rot + TAU * 0.85, 24, col_inner, 1.8, true)

		# 4. 外围 6 颗随身护法金符灵珠（沿全身椭圆大轨道逆向巡天）
		for i in range(6):
			var bead_a := -aegis_rot * 1.5 + float(i) * (TAU / 6.0)
			var bead_pos := BODY_CENTER + Vector2(cos(bead_a) * (rx + 5.5), sin(bead_a) * (ry + 5.5))
			var d_size := 3.8
			var diamond := PackedVector2Array([
				bead_pos + Vector2(0, -d_size),
				bead_pos + Vector2(d_size, 0),
				bead_pos + Vector2(0, d_size),
				bead_pos + Vector2(-d_size, 0)
			])
			draw_colored_polygon(diamond, Color.WHITE)
			draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), col_border, 1.4, true)

	elif aegis_shatter_progress >= 0.0:
		# 结界到期：全身大罩向外崩解碎散
		var p := aegis_shatter_progress
		var s_rx := rx + p * 22.0
		var s_ry := ry + p * 26.0
		var alpha := 1.0 - p
		var col := Color(GameStyle.YELLOW_EDGE.r, GameStyle.YELLOW_EDGE.g, GameStyle.YELLOW_EDGE.b, alpha * 0.9)
		var shatter_pts := PackedVector2Array()
		for i in range(25):
			var a := float(i) * (TAU / 24.0)
			shatter_pts.append(BODY_CENTER + Vector2(cos(a) * s_rx, sin(a) * s_ry))
		draw_polyline(shatter_pts, col, maxf(1.0, 3.2 * (1.0 - p)), true)
		for i in range(8):
			var a := float(i) * (TAU / 8.0) + p * 0.8
			var sp_pos := BODY_CENTER + Vector2(cos(a) * s_rx, sin(a) * s_ry)
			draw_circle(sp_pos, maxf(1.0, 3.5 * (1.0 - p)), Color(1, 1, 1, alpha))

## 绘制【回春术】：全身生机甘露光茧 + 地面青玉大阵 + 旋升生机光柱
func _draw_renewal_fx() -> void:
	var p := renewal_progress
	var alpha := 1.0 - p
	var r := 14.0 + p * 32.0

	# 1. 全身柔和翠绿生机光罩（从脚底包裹至头顶）
	var aura_col := Color(GameStyle.GOOD.r, GameStyle.GOOD.g, GameStyle.GOOD.b, alpha * 0.16)
	var aura_pts := PackedVector2Array()
	for i in range(20):
		var a := float(i) * (TAU / 20.0)
		aura_pts.append(BODY_CENTER + Vector2(cos(a) * 34.0, sin(a) * 44.0))
	draw_colored_polygon(aura_pts, aura_col)

	# 2. 地面回春青玉大光环
	var ring_col := Color(GameStyle.GOOD.r, GameStyle.GOOD.g, GameStyle.GOOD.b, alpha * 0.88)
	draw_arc(FEET_CENTER, r, 0.0, TAU, 32, ring_col, maxf(1.0, 3.5 * (1.0 - p)), true)

	# 3. 旋升笼罩全身的青芒灵气粒子（从脚底 +20 直冲头顶 -60）
	for pt in renewal_particles:
		var cur_y := float(pt["y"])
		var cur_r := float(pt["radius"]) * (1.0 - p * 0.25)
		var ang := float(pt["ang"])
		var pos := Vector2(cos(ang) * cur_r, cur_y)
		var p_alpha := clampf((1.0 - p) * 1.25, 0.0, 1.0)
		draw_circle(pos, 3.2 * (1.0 - p * 0.4), Color(GameStyle.GOOD.r, GameStyle.GOOD.g, GameStyle.GOOD.b, p_alpha))
		draw_circle(pos, 1.5, Color(1, 1, 1, p_alpha))
