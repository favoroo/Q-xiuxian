class_name PlayerSkillVfx
extends Node2D

## 角色随行神通（技能）视觉特效控制器与渲染器
## 负责表现角色在施放技能瞬间与增益持续期间的国风空灵修仙视觉效果：
##   1. 金光护体 (aegis): 六合天罡护身法印 + 双向浑天星轨金线 + 脚底金莲大阵 + 粒子化崩解碎散
##   2. 疾风咒 (haste): 身周三重高速风刃气刃 + 脚底八卦太极疾风阵 + 向上生腾的风丝灵气粒子
##   3. 神行术 (gale): 御风破空矢量身法虚影 + 脚底透视双层风轮 + 飘逸风灵飘带
##   4. 缩地成寸 (dash): 瞬身纯白剑意锋芒 + 破空剑气割裂裂痕 + 矢量残影
##   5. 回春术 (renewal): 地面九品青莲甘露阵 + 穿透升华的生机光羽与甘露灵丝
##
## 取色严格源自 GameStyle，完全剔除粗暴的半透明多边形填充罩（死皮感根源），
## 全面联动角色矢量本体（眼睛变色爆芒、斗篷流光反光、道印激活），达到主机级高精仙侠观感。

# ---------------- 常量与配置 ----------------
const BODY_CENTER := Vector2(0.0, -14.0)    ## 角色身躯中心（高宽覆盖的核心基准）
const FEET_CENTER := Vector2(0.0, 14.0)     ## 角色脚底地面中心

## 金光护体星轨半径
const SHIELD_RX := 36.0
const SHIELD_RY := 46.0

## 疾风咒风刃回旋半径
const HASTE_GROUND_RADIUS := 36.0
const HASTE_BODY_RX := 32.0
const HASTE_BODY_RY := 42.0

const GHOST_POOL_CAP := 12                  ## 图集残影池上限

# ---------------- 运行时状态 ----------------
@onready var player: CharacterBody2D = get_parent() as CharacterBody2D

# 1. 金光护体状态
var aegis_active: bool = false
var aegis_timer: float = 0.0
var aegis_max_dur: float = 1.6
var aegis_rot: float = 0.0
var aegis_shatter_progress: float = -1.0  ## >=0 时播放消散碎裂动画
var aegis_shatter_sparks: Array[Dictionary] = [] ## {pos, vel, alpha, size}

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
var dash_total_dur: float = 0.16
var dash_dir: Vector2 = Vector2.DOWN

# 5. 回春术状态
var renewal_progress: float = -1.0  ## >=0 播放回春法阵与生机光柱 (0.0 -> 1.0)
var renewal_particles: Array[Dictionary] = []

# 6. 图集残影对象池 (Sprite2D，仅供图集模式兼容)
var _ghost_pool: Array[Sprite2D] = []

# 7. 程序化角色纯矢量流光残影队列
var _vector_ghosts: Array[Dictionary] = []

func _ready() -> void:
	z_index = 2  ## 略高于角色精灵
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

## 通知角色本体视图联动更新法相与流光状态
func _notify_procedural_view(skill_id: String, active: bool, intensity: float = 1.0) -> void:
	if player == null:
		return
	if player.get("is_procedural") and player.get("procedural_view") != null:
		var pv = player.procedural_view
		if pv.has_method("set_skill_visual"):
			pv.set_skill_visual(skill_id, active, intensity)

# ---------------- 技能触发入口 ----------------

## 缩地成寸瞬间释放
func on_dash_start(direction: Vector2, distance: float, duration: float) -> void:
	dash_dir = direction.normalized()
	dash_total_dur = maxf(duration, 0.05)
	dash_flash_timer = dash_total_dur + 0.10
	_notify_procedural_view("dash", true, 1.0)
	# 生成瞬身残影
	spawn_ghost(Color(GameStyle.GOLD_EDGE, 0.85), 0.28)
	queue_redraw()

## 神行术激活
func on_gale_start(duration: float) -> void:
	gale_active = true
	gale_timer = duration
	gale_trail_timer = 0.0
	_notify_procedural_view("gale", true, 1.0)
	spawn_ghost(Color(GameStyle.JADE_EDGE, 0.75), 0.25)
	queue_redraw()

## 疾风咒激活
func on_haste_start(duration: float) -> void:
	haste_active = true
	haste_timer = duration
	haste_rot = 0.0
	haste_particle_timer = 0.0
	_notify_procedural_view("haste", true, 1.0)
	queue_redraw()

## 金光护体激活
func on_aegis_start(duration: float) -> void:
	aegis_active = true
	aegis_max_dur = duration
	aegis_timer = duration
	aegis_shatter_progress = -1.0
	aegis_shatter_sparks.clear()
	_notify_procedural_view("aegis", true, 1.0)
	queue_redraw()

## 回春术施放
func on_renewal_cast() -> void:
	renewal_progress = 0.0
	renewal_particles.clear()
	_notify_procedural_view("renewal", true, 1.0)
	for i in range(16):
		var ang := float(i) * (TAU / 16.0)
		renewal_particles.append({
			"ang": ang,
			"radius": randf_range(14.0, 36.0),
			"y": randf_range(10.0, 24.0),
			"speed_y": randf_range(110.0, 160.0),
			"rot_speed": randf_range(3.2, 5.8),
			"size": randf_range(1.5, 3.0)
		})
	queue_redraw()

# ---------------- 每帧逻辑更新 ----------------

func update_vfx(delta: float, is_moving: bool, velocity: Vector2) -> void:
	var needs_redraw := false

	# 1. 图集残影生命周期淡出
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

	# 2. 程序化角色纯矢量流光虚影更新
	if not _vector_ghosts.is_empty():
		needs_redraw = true
		var vi := _vector_ghosts.size() - 1
		while vi >= 0:
			var vg: Dictionary = _vector_ghosts[vi]
			vg["life"] = float(vg["life"]) - delta
			if float(vg["life"]) <= 0.0:
				_vector_ghosts.remove_at(vi)
			vi -= 1

	# 3. 金光护体
	if aegis_active:
		needs_redraw = true
		aegis_rot += delta * 2.5
		aegis_timer -= delta
		if aegis_timer <= 0.0:
			aegis_active = false
			aegis_shatter_progress = 0.0  ## 启动消散碎裂动效
			_notify_procedural_view("aegis", false)
			# 生成崩散碎星粒子
			aegis_shatter_sparks.clear()
			for i in range(12):
				var a := float(i) * (TAU / 12.0) + randf_range(-0.15, 0.15)
				var spd := randf_range(75.0, 140.0)
				aegis_shatter_sparks.append({
					"pos": BODY_CENTER + Vector2(cos(a) * SHIELD_RX, sin(a) * SHIELD_RY),
					"vel": Vector2(cos(a) * spd, sin(a) * spd),
					"size": randf_range(2.0, 3.8)
				})
	elif aegis_shatter_progress >= 0.0:
		needs_redraw = true
		aegis_shatter_progress += delta * 4.2  ## 约 0.24 秒碎散淡出
		for spk in aegis_shatter_sparks:
			spk["pos"] = Vector2(spk["pos"]) + Vector2(spk["vel"]) * delta
			spk["vel"] = Vector2(spk["vel"]) * 0.92
		if aegis_shatter_progress >= 1.0:
			aegis_shatter_progress = -1.0
			aegis_shatter_sparks.clear()

	# 4. 疾风咒
	if haste_active:
		needs_redraw = true
		haste_rot += delta * 7.8
		haste_timer -= delta
		if haste_timer <= 0.0:
			haste_active = false
			haste_sparks.clear()
			_notify_procedural_view("haste", false)
		else:
			# 周期性散逸微风刃灵气（覆盖全身范围）
			haste_particle_timer -= delta
			if haste_particle_timer <= 0.0:
				haste_particle_timer = 0.05
				if haste_sparks.size() < 16:
					var p_ang := randf() * TAU
					var spawn_y := randf_range(-38.0, 12.0)
					var spawn_x := cos(p_ang) * randf_range(14.0, 30.0)
					haste_sparks.append({
						"pos": Vector2(spawn_x, spawn_y),
						"vel": Vector2(randf_range(-15.0, 15.0), randf_range(-70.0, -125.0)),
						"life": 0.30,
						"max_life": 0.30,
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

	# 5. 神行术
	if gale_active:
		needs_redraw = true
		gale_wind_phase += delta * 12.0
		gale_timer -= delta
		if gale_timer <= 0.0:
			gale_active = false
			_notify_procedural_view("gale", false)
		else:
			# 移动中产生残影
			if is_moving and velocity.length_squared() > 1600.0:
				gale_trail_timer -= delta
				if gale_trail_timer <= 0.0:
					gale_trail_timer = 0.08
					spawn_ghost(Color(GameStyle.JADE_EDGE, 0.55), 0.22)

	# 6. 缩地成寸
	if dash_flash_timer > 0.0:
		needs_redraw = true
		dash_flash_timer -= delta
		if is_moving and fmod(dash_flash_timer, 0.04) < delta:
			spawn_ghost(Color(GameStyle.GOLD_EDGE, 0.65), 0.20)
		if dash_flash_timer <= 0.0:
			_notify_procedural_view("dash", false)

	# 7. 回春术
	if renewal_progress >= 0.0:
		needs_redraw = true
		renewal_progress += delta * 1.7  ## 约 0.58s 走完
		for p in renewal_particles:
			p["y"] = float(p["y"]) - float(p["speed_y"]) * delta
			p["ang"] = float(p["ang"]) + float(p["rot_speed"]) * delta
		if renewal_progress >= 1.0:
			renewal_progress = -1.0
			renewal_particles.clear()
			_notify_procedural_view("renewal", false)

	if needs_redraw:
		queue_redraw()

## 生成一具角色当前帧的身法残影
func spawn_ghost(color: Color, duration: float) -> void:
	if player == null:
		return

	# 若为程序化角色：生成纯矢量修仙流光虚影，绝不使用图集！
	if player.get("is_procedural"):
		if _vector_ghosts.size() < 16:
			var facing_str: String = "s"
			var is_flip: bool = false
			var pv = player.get("procedural_view")
			if pv != null:
				facing_str = pv.facing
				is_flip = pv.flip_h
			_vector_ghosts.append({
				"pos": player.global_position,
				"facing": facing_str,
				"flip_h": is_flip,
				"color": color,
				"life": duration,
				"max_life": duration
			})
		return

	# 若为图集角色：从 AnimatedSprite2D 获取帧
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

	# 0. 程序化角色纯矢量流光虚影（最底层）
	if not _vector_ghosts.is_empty():
		_draw_vector_ghosts()

	# 1. 疾风咒：环身风刃切线与八卦疾风大阵（无任何大半透蒙皮填充）
	if haste_active:
		_draw_haste_fx()

	# 2. 神行术：踝部风旋微弧与御风流带
	if gale_active:
		_draw_gale_wind()

	# 3. 缩地成寸：前方破空剑气割裂裂痕
	if dash_flash_timer > 0.0:
		_draw_dash_cone()

	# 4. 金光护体：浑天星轨金线 + 六合天罡法印（无任何多边形填色死皮）
	if aegis_active or aegis_shatter_progress >= 0.0:
		_draw_aegis_shield()

	# 5. 回春术：九品青莲生机甘露阵与生机光羽
	if renewal_progress >= 0.0:
		_draw_renewal_fx()

## 绘制程序化修仙角色的纯矢量流光身法虚影（彻底解决老版蓝衫小人残影 Bug）
func _draw_vector_ghosts() -> void:
	for g in _vector_ghosts:
		var life: float = float(g["life"])
		var max_l: float = float(g["max_life"])
		var ratio := clampf(life / max_l, 0.0, 1.0)
		var col: Color = g["color"]
		var alpha := col.a * ratio * 0.72
		if alpha <= 0.01:
			continue

		var rel_pos: Vector2 = Vector2(g["pos"]) - player.global_position
		var flip: float = -1.0 if bool(g["flip_h"]) else 1.0

		# 绘制流光身形剪影：头部面具轮廓 + 飘逸斗篷下摆
		var head_c := rel_pos + Vector2(0.0, -15.0)
		draw_circle(head_c, 8.5, Color(col.r, col.g, col.b, alpha * 0.45))
		draw_arc(head_c, 8.5, 0, TAU, 16, Color(1.0, 1.0, 1.0, alpha * 0.75), 1.0, true)

		# 飘逸斗篷轮廓
		var cloak_pts := PackedVector2Array([
			rel_pos + Vector2(0.0, -6.0),
			rel_pos + Vector2(10.0 * flip, -1.0),
			rel_pos + Vector2(13.0 * flip, 14.0),
			rel_pos + Vector2(11.0 * flip, 26.0),
			rel_pos + Vector2(0.0, 28.0),
			rel_pos + Vector2(-11.0 * flip, 26.0),
			rel_pos + Vector2(-13.0 * flip, 14.0),
			rel_pos + Vector2(-10.0 * flip, -1.0)
		])
		draw_colored_polygon(cloak_pts, Color(col.r, col.g, col.b, alpha * 0.40))
		draw_polyline(cloak_pts, Color(1.0, 1.0, 1.0, alpha * 0.85), 1.2, true)

## 绘制【疾风咒】：环身三道极速风刃切线 + 脚底太极疾风八卦大阵 + 升腾风丝
func _draw_haste_fx() -> void:
	var col_main := Color(GameStyle.GOLD, 0.88)
	var col_edge := Color(GameStyle.GOLD_EDGE, 0.98)

	var pulse := sin(haste_rot * 1.2) * 1.5
	var rx := HASTE_BODY_RX + pulse
	var ry := HASTE_BODY_RY + pulse

	# 1. 环绕全身的 3 道高速椭圆风刃大弧（纯粹金白切线，告别半透明色块覆盖）
	for i in range(3):
		var base_a := haste_rot + float(i) * (TAU / 3.0)
		var arc_pts := PackedVector2Array()
		var steps := 12
		var span := 1.40
		for s in range(steps + 1):
			var a := base_a + span * (float(s) / float(steps))
			arc_pts.append(BODY_CENTER + Vector2(cos(a) * rx, sin(a) * ry))
		draw_polyline(arc_pts, col_edge, 2.4, true)
		# 风刃弧头纯白凝光刃尖
		var tip := arc_pts[arc_pts.size() - 1]
		draw_circle(tip, 2.5, Color.WHITE)
		draw_line(tip, tip - Vector2(-sin(base_a + span) * 6.0, cos(base_a + span) * 6.0), Color.WHITE, 1.5)

	# 2. 内层反向交织的护身螺旋风流（立体包裹动势）
	var inner_rx := rx * 0.78
	var inner_ry := ry * 0.82
	for i in range(2):
		var base_a := -haste_rot * 1.25 + float(i) * PI
		var inner_pts := PackedVector2Array()
		var steps := 10
		var span := 1.55
		for s in range(steps + 1):
			var a := base_a + span * (float(s) / float(steps))
			inner_pts.append(BODY_CENTER + Vector2(cos(a) * inner_rx, sin(a) * inner_ry))
		draw_polyline(inner_pts, col_main, 1.6, true)

	# 3. 脚底八卦太极疾风大阵（透视风轮 + 太极阴阳流转弧）
	for i in range(4):
		var g_a := haste_rot * 1.4 + float(i) * (TAU / 4.0)
		draw_arc(FEET_CENTER, HASTE_GROUND_RADIUS, g_a, g_a + 0.95, 14, col_edge, 2.0, true)
		# 四象金芒位点
		var pt_pos := FEET_CENTER + Vector2(cos(g_a) * HASTE_GROUND_RADIUS, sin(g_a) * HASTE_GROUND_RADIUS * 0.45)
		draw_circle(pt_pos, 2.0, Color.WHITE)
	# 内层太极流光小环
	draw_arc(FEET_CENTER, HASTE_GROUND_RADIUS * 0.52, -haste_rot * 2.0, -haste_rot * 2.0 + PI, 16, col_main, 1.5, true)

	# 4. 向上飞升的金色风刃光丝（Sparks）
	for sp in haste_sparks:
		var ratio := clampf(float(sp["life"]) / float(sp["max_life"]), 0.0, 1.0)
		var p_col := Color(GameStyle.GOLD_EDGE.r, GameStyle.GOLD_EDGE.g, GameStyle.GOLD_EDGE.b, ratio * 0.95)
		var p_pos := Vector2(sp["pos"])
		var p_tail := p_pos - Vector2(sp["vel"]).normalized() * (10.0 * ratio)
		draw_line(p_tail, p_pos, p_col, 2.0, true)
		draw_circle(p_pos, 1.2, Color(1, 1, 1, ratio * 0.9))

## 绘制【神行术】：脚底御风双层青轮 + 身侧破风流光飘带
func _draw_gale_wind() -> void:
	var wave := sin(gale_wind_phase) * 2.2
	var col_edge := Color(GameStyle.JADE_EDGE, 0.92)
	var col_main := Color(GameStyle.JADE, 0.75)

	# 1. 脚底御风大青轮（透视双层风环与破风角标）
	var wheel_rx := 32.0
	var wheel_ry := 13.0
	for i in range(2):
		var base_a := gale_wind_phase * 0.8 + float(i) * PI
		var pts := PackedVector2Array()
		for s in range(11):
			var a := base_a + 1.8 * (float(s) / 10.0)
			pts.append(FEET_CENTER + Vector2(cos(a) * wheel_rx, sin(a) * wheel_ry))
		draw_polyline(pts, col_edge, 2.2, true)
		# 轮端纯白破空锋点
		draw_circle(pts[pts.size() - 1], 2.2, Color.WHITE)

	# 内层风轮
	draw_arc(FEET_CENTER, 18.0, -gale_wind_phase, -gale_wind_phase + PI * 1.2, 16, col_main, 1.4, true)

	# 2. 身躯两侧上升的灵动青风流带（轻柔飘逸曲线，告别生硬粗折线）
	for side_val in [-1.0, 1.0]:
		var side: float = float(side_val)
		var ribbon := PackedVector2Array()
		for s in range(10):
			var t := float(s) / 9.0
			var y := lerpf(16.0, -36.0, t)
			var x: float = side * (24.0 + sin(gale_wind_phase * 0.8 + t * PI * 2.2) * 4.5)
			ribbon.append(Vector2(x, y))
		draw_polyline(ribbon, Color(col_main.r, col_main.g, col_main.b, 0.65), 1.8, true)
		# 飘带尖端流萤微光
		draw_circle(ribbon[ribbon.size() - 1], 1.5, Color(1, 1, 1, 0.85))

## 绘制【缩地成寸】：破空剑气割裂裂痕（纯正仙侠剑步破空感，彻底剔除实心填色大三角锥）
func _draw_dash_cone() -> void:
	var cone_dir := dash_dir
	var ratio := clampf(dash_flash_timer / (dash_total_dur + 0.10), 0.0, 1.0)
	var col_outer := Color(GameStyle.GOLD_EDGE.r, GameStyle.GOLD_EDGE.g, GameStyle.GOLD_EDGE.b, ratio * 0.95)
	var col_core := Color(1.0, 1.0, 1.0, ratio * 0.98)

	# 1. 中心主破障剑芒裂痕
	var tip := BODY_CENTER + cone_dir * (52.0 * ratio)
	var base_origin := BODY_CENTER - cone_dir * 12.0
	draw_line(base_origin, tip, col_outer, 3.2, true)
	draw_line(base_origin + cone_dir * 8.0, tip, col_core, 1.6, true)
	draw_circle(tip, 3.2, Color.WHITE)

	# 2. 左右两翼破空折线剑气（锐利破障）
	var spread_ang := deg_to_rad(32.0)
	var l_dir := cone_dir.rotated(spread_ang)
	var r_dir := cone_dir.rotated(-spread_ang)
	var l_wing_tip := BODY_CENTER + l_dir * (42.0 * ratio)
	var r_wing_tip := BODY_CENTER + r_dir * (42.0 * ratio)

	var l_pts := PackedVector2Array([
		BODY_CENTER,
		BODY_CENTER + l_dir * (24.0 * ratio) + cone_dir * 6.0,
		l_wing_tip
	])
	var r_pts := PackedVector2Array([
		BODY_CENTER,
		BODY_CENTER + r_dir * (24.0 * ratio) + cone_dir * 6.0,
		r_wing_tip
	])
	draw_polyline(l_pts, col_outer, 2.2, true)
	draw_polyline(r_pts, col_outer, 2.2, true)
	draw_polyline(l_pts, col_core, 1.2, true)
	draw_polyline(r_pts, col_core, 1.2, true)

	# 3. 破障碎刃星点
	for i in range(4):
		var spark_p := BODY_CENTER + cone_dir * (15.0 + float(i) * 9.0) + Vector2(-cone_dir.y, cone_dir.x) * (float(i % 2 * 2 - 1) * 8.0)
		draw_circle(spark_p, 1.6 * ratio, Color.WHITE)

## 绘制【金光护体】：浑天星轨金线 + 六合天罡法印 + 粒子崩散（彻底剔除半透明多边形死皮填充）
func _draw_aegis_shield() -> void:
	var pulse := sin(aegis_rot * 2.5) * 1.5
	var rx := SHIELD_RX + pulse
	var ry := SHIELD_RY + pulse

	if aegis_active:
		var col_border := Color(GameStyle.GOLD_EDGE, 0.98)
		var col_inner := Color(GameStyle.GOLD, 0.75)
		var col_white := Color(1.0, 1.0, 1.0, 0.95)

		# 1. 双向立体浑天星轨金线（相向交织，空灵通透）
		var ring1_pts := PackedVector2Array()
		var ring2_pts := PackedVector2Array()
		for i in range(25):
			var a := float(i) * (TAU / 24.0)
			# 正向椭圆轨道
			ring1_pts.append(BODY_CENTER + Vector2(cos(a + aegis_rot * 0.4) * rx, sin(a + aegis_rot * 0.4) * ry))
			# 倾斜立体反向轨道
			var tilted_a := a - aegis_rot * 0.5
			var tx := cos(tilted_a) * (rx * 0.92)
			var ty := sin(tilted_a) * (ry * 0.92)
			ring2_pts.append(BODY_CENTER + Vector2(tx * 0.92 - ty * 0.12, tx * 0.12 + ty * 0.92))

		draw_polyline(ring1_pts, col_border, 2.0, true)
		draw_polyline(ring2_pts, col_inner, 1.4, true)

		# 2. 六合天罡护身法印（6 枚精致菱形金符，沿星轨公转）
		for i in range(6):
			var bead_a := -aegis_rot * 1.4 + float(i) * (TAU / 6.0)
			var bead_pos := BODY_CENTER + Vector2(cos(bead_a) * (rx + 4.0), sin(bead_a) * (ry + 4.0))
			var d_size := 4.2
			var diamond := PackedVector2Array([
				bead_pos + Vector2(0, -d_size),
				bead_pos + Vector2(d_size * 0.85, 0),
				bead_pos + Vector2(0, d_size),
				bead_pos + Vector2(-d_size * 0.85, 0)
			])
			# 金边法印 + 白心核心
			draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), col_border, 1.5, true)
			draw_circle(bead_pos, 1.8, col_white)
			# 法印流光微尾
			var tail_p := bead_pos - Vector2(-sin(bead_a), cos(bead_a)) * 5.0
			draw_line(tail_p, bead_pos, Color(col_border.r, col_border.g, col_border.b, 0.65), 1.2)

		# 3. 脚底天罡降魔金莲大阵（地面透视莲花阵盘）
		draw_arc(FEET_CENTER, 32.0, aegis_rot, aegis_rot + TAU, 28, col_inner, 1.8, true)
		for k in range(8):
			var petal_a := aegis_rot + float(k) * (TAU / 8.0)
			var petal_p := FEET_CENTER + Vector2(cos(petal_a) * 32.0, sin(petal_a) * 12.0)
			draw_circle(petal_p, 1.8, Color.WHITE)

	elif aegis_shatter_progress >= 0.0:
		# 结界到期破碎：纯粒子化向四周迸散（告别生硬大椭圆向外缩放）
		var p := aegis_shatter_progress
		var alpha := 1.0 - p
		for spk in aegis_shatter_sparks:
			var sp_pos: Vector2 = spk["pos"]
			var sp_sz: float = float(spk["size"]) * (1.0 - p * 0.4)
			draw_circle(sp_pos, sp_sz, Color(1, 1, 1, alpha * 0.95))
			var tail := sp_pos - Vector2(spk["vel"]).normalized() * (8.0 * (1.0 - p))
			draw_line(tail, sp_pos, Color(GameStyle.GOLD_EDGE.r, GameStyle.GOLD_EDGE.g, GameStyle.GOLD_EDGE.b, alpha * 0.85), 1.6)

		# 微细环形音爆裂纹（急速淡出）
		if p < 0.4:
			var ring_p := p / 0.4
			var s_rx := rx + ring_p * 24.0
			var s_ry := ry + ring_p * 24.0
			var shatter_pts := PackedVector2Array()
			for i in range(25):
				var a := float(i) * (TAU / 24.0)
				shatter_pts.append(BODY_CENTER + Vector2(cos(a) * s_rx, sin(a) * s_ry))
			draw_polyline(shatter_pts, Color(GameStyle.GOLD_EDGE.r, GameStyle.GOLD_EDGE.g, GameStyle.GOLD_EDGE.b, (1.0 - ring_p) * 0.75), 1.8, true)

## 绘制【回春术】：地面九品青莲生机甘露阵 + 穿透升华的生机光羽（彻底剔除绿色大光罩覆盖）
func _draw_renewal_fx() -> void:
	var p := renewal_progress
	var alpha := 1.0 - p
	var r := 16.0 + p * 36.0

	# 1. 地面九品青莲甘露阵（层叠展开的生机青玉莲瓣与甘露环）
	var ring_col := Color(GameStyle.GOOD.r, GameStyle.GOOD.g, GameStyle.GOOD.b, alpha * 0.95)
	draw_arc(FEET_CENTER, r, 0.0, TAU, 32, ring_col, maxf(1.0, 3.2 * (1.0 - p)), true)
	draw_arc(FEET_CENTER, r * 0.65, -p * 2.5, -p * 2.5 + TAU * 0.85, 24, Color(1.0, 1.0, 1.0, alpha * 0.85), 1.5, true)

	# 莲瓣角标
	for i in range(8):
		var la := float(i) * (TAU / 8.0) + p * 0.8
		var lp := FEET_CENTER + Vector2(cos(la) * r, sin(la) * (r * 0.42))
		draw_circle(lp, maxf(1.0, 2.8 * (1.0 - p * 0.5)), Color.WHITE)

	# 2. 旋升穿透身躯的甘露光羽与灵气微粒（从脚底直冲云霄，化作点点甘霖）
	for pt in renewal_particles:
		var cur_y := float(pt["y"])
		var cur_r := float(pt["radius"]) * (1.0 - p * 0.2)
		var ang := float(pt["ang"])
		var pos := Vector2(cos(ang) * cur_r, cur_y)
		var p_alpha := clampf((1.0 - p) * 1.3, 0.0, 1.0)
		var p_sz: float = float(pt.get("size", 2.2)) * (1.0 - p * 0.3)

		# 翠绿甘露光羽 + 纯白灵核
		draw_circle(pos, p_sz, Color(GameStyle.GOOD.r, GameStyle.GOOD.g, GameStyle.GOOD.b, p_alpha * 0.9))
		draw_circle(pos, p_sz * 0.55, Color(1.0, 1.0, 1.0, p_alpha * 0.95))
		# 向上拖曳的甘霖光丝
		var tail_p := pos + Vector2(0.0, float(pt["speed_y"]) * 0.06 * (1.0 - p))
		draw_line(tail_p, pos, Color(GameStyle.GOOD.r, GameStyle.GOOD.g, GameStyle.GOOD.b, p_alpha * 0.65), 1.2)
