class_name SpiritPet
extends Node2D

## 灵兽（随行伙伴）实体：纯 _draw 程序化光灵 + 小部件区分，无碰撞体，跨波存活
## 铁律：只挂 "spirit_pets" 组，绝不进 enemies/turrets/gems/chests 四个波末清场组。
## 多个灵兽通过 orbit_index 均分绕飘相位，视觉各自舒展不重叠。

const FOLLOW_DIST: float = 38.0     ## 跟随绕飘半径（px）
const HEIGHT_OFFSET: float = 28.0   ## 悬在玩家头顶上方（px）
const DISSOLVE_SEC: float = 0.35    ## 出售/移除时的消散时长（秒）

const BULLET_TEXTURE = preload("res://assets/art/bullet_spirit_pellet.png")
const PROJECTILE_SCENE = preload("res://scenes/weapons/BladeProjectile.tscn")

var pet_id: String = ""             ## 灵兽 id（见 PetData）
var pet_def: Dictionary = {}
var orbit_index: int = 0            ## 在已购灵兽队列里的序号（0, 1, 2）
var total_pets: int = 1             ## 当前总灵兽数（均分相位用）
var target: Player = null           ## 随行主人

var _age: float = 0.0
var _cooldown_timer: float = 1.0    ## 首跳延迟 1 秒，平稳入场
var _dying: bool = false
var _action_fx: float = -1.0        ## 脉冲/动作特效进度（0~1，<0 为无）
var _lightning_target_pos: Vector2 = Vector2.ZERO ## 雷击特效终点（相对本地坐标）

# --- 增强视觉表现字段 ---
var _flash_timer: float = 0.0       ## 触发/受激闪白计时（秒）
var _scale_punch: Vector2 = Vector2.ONE ## 施法挤压回弹（Squash & Stretch）
var _tether_target_pos: Vector2 = Vector2.ZERO ## 法力连线目标点（相对本地坐标，如玄甲龟拦截）
var _tether_progress: float = -1.0  ## 连线动画进度（0~1，<0 为无）
var _spin_angle: float = 0.0        ## 灵兽专属旋转姿态（如灵风貂旋转）
var _custom_fx_type: String = ""    ## 专属特效类型标记

func _ready() -> void:
	add_to_group("spirit_pets")
	if pet_id != "":
		_apply_def()

func setup(p_id: String, idx: int, total: int, owner_player: Player) -> void:
	pet_id = p_id
	orbit_index = idx
	total_pets = maxi(1, total)
	target = owner_player
	_apply_def()

func _apply_def() -> void:
	pet_def = PetData.get_def(pet_id)
	queue_redraw()

func _physics_process(delta: float) -> void:
	if _dying:
		return
	if target == null or not is_instance_valid(target):
		# 主人可能未初始化或正在场景切换，从 GameManager 寻找
		if GameManager.player != null and is_instance_valid(GameManager.player):
			target = GameManager.player as Player
		else:
			return

	_age += delta

	# 柔和环绕跟随：椭圆绕飘 + 均分相位角
	var base_phase: float = (TAU * float(orbit_index) / float(maxi(1, total_pets)))
	var t: float = _age * 0.85 + base_phase
	var offset := Vector2(
		cos(t) * FOLLOW_DIST,
		sin(t * 1.2) * (FOLLOW_DIST * 0.55) - HEIGHT_OFFSET + sin(_age * 2.2 + base_phase) * 4.0
	)
	global_position = global_position.lerp(target.global_position + offset, minf(1.0, 6.0 * delta))

	# 特效动画推进
	if _action_fx >= 0.0:
		_action_fx += delta * 2.8
		if _action_fx > 1.0:
			_action_fx = -1.0
			_lightning_target_pos = Vector2.ZERO
			_custom_fx_type = ""

	# 闪白与挤压回弹推进
	if _flash_timer > 0.0:
		_flash_timer = maxf(0.0, _flash_timer - delta)
	if _scale_punch != Vector2.ONE:
		_scale_punch = _scale_punch.lerp(Vector2.ONE, minf(1.0, 14.0 * delta))
	scale = _scale_punch

	# 连线特效推进（如玄甲龟连线拦截点）
	if _tether_progress >= 0.0:
		_tether_progress += delta * 4.5
		if _tether_progress > 1.0:
			_tether_progress = -1.0
			_tether_target_pos = Vector2.ZERO

	# 专属自转衰减（如灵风貂磁吸自转）
	if absf(_spin_angle) > 0.001:
		_spin_angle = lerpf(_spin_angle, 0.0, minf(1.0, 10.0 * delta))
		rotation = _spin_angle
	else:
		rotation = 0.0

	# 战斗行为（非终局、非暂停时按冷却心跳推进）
	if not GameManager.is_game_over and not get_tree().paused:
		_tick_behavior(delta)

	queue_redraw()

func _tick_behavior(delta: float) -> void:
	var base_cd: float = float(pet_def.get("base_cooldown", 0.0))
	if base_cd <= 0.0:
		return  # 经济类等被动触发型灵兽走事件驱动
	var cd: float = BalanceSpiritPet.cooldown(base_cd, GameManager.pet_cooldown_mult)
	_cooldown_timer -= delta
	if _cooldown_timer <= 0.0:
		_cooldown_timer = cd
		_trigger_action()

func _trigger_action() -> void:
	match pet_id:
		"yanhu":
			_act_yanhu()
		"leique":
			_act_leique()
		"xuangui":
			_act_xuangui()
		"yulu":
			_act_yulu()
		"fengdiao":
			_act_fengdiao()
		"shiyuan":
			_act_shiyuan()

## 通用触发高光脉冲与形变回弹
func pulse_trigger_fx(squash_stretch: Vector2 = Vector2(1.35, 1.35), flash_duration: float = 0.14) -> void:
	_action_fx = 0.0
	_flash_timer = flash_duration
	_scale_punch = squash_stretch
	queue_redraw()

## 焰灵狐：追踪火丹
func _act_yanhu() -> void:
	var nearest := _find_nearest_enemy(320.0)
	if nearest == null:
		return
	var dir := (nearest.global_position - global_position).normalized()
	var dmg := BalanceSpiritPet.fire_damage(GameManager.wave_number, GameManager.pet_damage_mult)
	var p := BladeProjectile.acquire_or_new(PROJECTILE_SCENE, get_tree().current_scene)
	p.global_position = global_position + dir * 8.0
	p.direction = dir
	p.speed = 360.0
	p.damage = dmg
	p.knockback_base = 50.0
	p.pierce_left = 1
	p.bounce_left = 0
	p.homing_target = nearest
	p.bullet_texture = BULLET_TEXTURE
	p.bullet_scale = 0.55
	p.spin = false
	p.activate()
	p.lifetime = 1.0

	# 后坐形变 + 灵狐吐火星屑
	pulse_trigger_fx(Vector2(0.8, 1.3), 0.12)
	if is_inside_tree() and get_parent() != null:
		JuiceEffect.spawn_impact_pop(get_parent(), global_position, Color(1.0, 0.45, 0.15), -dir)
	AudioManager.play_sfx("blade_shoot", 0.35, 1.15)

## 雷灵雀：高伤雷击
func _act_leique() -> void:
	var nearest := _find_nearest_enemy(280.0)
	if nearest == null:
		return
	var dmg := BalanceSpiritPet.thunder_damage(GameManager.wave_number, GameManager.pet_damage_mult)
	if nearest.has_method("take_damage"):
		nearest.take_damage(dmg, Vector2.ZERO, true)
	_lightning_target_pos = to_local(nearest.global_position)
	pulse_trigger_fx(Vector2(1.4, 0.75), 0.16)
	# 落雷点击打火花
	if is_inside_tree() and get_parent() != null:
		JuiceEffect.spawn_impact_pop(get_parent(), nearest.global_position, Color(0.68, 0.58, 1.0))
	AudioManager.play_sfx("thunder_strike", 0.45, 1.2)

## 玄甲龟：拦截飞行物
func _act_xuangui() -> void:
	var bolts := get_tree().get_nodes_in_group("enemy_bolts")
	if bolts.is_empty():
		return
	var radius := BalanceSpiritPet.intercept_radius(GameManager.pet_effect_mult)
	var radius_sq := radius * radius
	# 以玩家或玄龟为中心，优先拦截威胁最大的飞行物
	var center := target.global_position if target != null else global_position
	var candidate: Node2D = null
	var min_d: float = radius_sq
	for b in bolts:
		if not is_instance_valid(b) or not (b is Node2D):
			continue
		var n2d := b as Node2D
		if not n2d.visible:
			continue
		var d := center.distance_squared_to(n2d.global_position)
		if d < min_d:
			min_d = d
			candidate = n2d
	if candidate != null:
		var bolt_pos: Vector2 = candidate.global_position
		var b_dir: Vector2 = Vector2.ZERO
		var raw_dir: Variant = candidate.get("direction")
		if raw_dir is Vector2:
			b_dir = raw_dir as Vector2

		# 拦截并触发飞行物湮灭火花
		if candidate.has_method("intercept"):
			candidate.intercept()
		elif candidate.has_method("_recycle"):
			candidate._recycle()

		# 1. 灵龟本体闪白与护甲回弹
		pulse_trigger_fx(Vector2(1.4, 1.4), 0.18)
		# 2. 从灵龟朝向被拦截弹丸射出一道御灵连线
		_tether_target_pos = to_local(bolt_pos)
		_tether_progress = 0.0

		var scene_parent: Node = get_parent()
		if is_inside_tree() and scene_parent != null:
			# 3. 拦截点绽放青金相间的护盾光环（与玄甲防御半径契合）
			var shield_color: Color = GameStyle.AURUM
			JuiceEffect.spawn_shockwave(scene_parent, bolt_pos, radius * 0.65, shield_color, 0.28)
			JuiceEffect.spawn_impact_pop(scene_parent, bolt_pos, Color(0.35, 0.85, 0.95), -b_dir)
			# 4. 浮现青金风格的“抵挡”飘字
			DamageNumber.spawn(scene_parent, bolt_pos + Vector2(0, -14), 0, false, "抵挡")

		# 5. 清脆有力的防御音效（使用已注册的 impact_blunt）
		AudioManager.play_sfx("impact_blunt", 0.5, 1.35)

## 玉露鹿：气血回复
func _act_yulu() -> void:
	if target == null:
		return
	var ratio := BalanceSpiritPet.heal_ratio(GameManager.pet_effect_mult)
	var heal_amt := target.max_health * ratio
	var before := target.current_health
	target.heal(heal_amt, true)
	var gained := target.current_health - before
	if gained > 0.01:
		pulse_trigger_fx(Vector2(0.9, 1.35), 0.15)
		var scene_parent: Node = get_parent()
		if is_inside_tree() and scene_parent != null:
			# 玩家脚下甘霖回春护环
			JuiceEffect.spawn_shockwave(scene_parent, target.global_position, 36.0, GameStyle.GOOD, 0.26)
			DamageNumber.spawn(scene_parent, target.global_position + Vector2(0, -22), int(gained), false, "+" + str(int(gained)))
		AudioManager.play_sfx("heal", 0.4, 1.25)

## 灵风貂：罡风卷定 —— 把风涡半径内的敌人卷到玩家身前的定身环并钉住
## 落环沿索敌椭圆（x:MELEE_RING, y:×0.65）：卷定的目标就是「被近战自动锁到」，
## 圆环会在正上/正下方骗过椭圆索敌（长剑竖向有效距离 120÷0.65≈185>125 打不了）。
## 与磐石猿（外推解围）配成「推/拉」一对控制。
func _act_fengdiao() -> void:
	if target == null or not is_instance_valid(target):
		return
	var radius := BalanceSpiritPet.vortex_radius(GameManager.pet_effect_mult)
	var radius_sq := radius * radius
	var dmg := BalanceSpiritPet.vortex_damage(GameManager.wave_number, GameManager.pet_damage_mult)
	var scene_parent: Node = get_parent()
	var affected: int = 0
	for e in GameManager.live_enemies:
		if not is_instance_valid(e) or not (e is EnemyBase):
			continue
		var en := e as EnemyBase
		if en.dying:
			continue
		var diff := en.global_position - target.global_position
		var dist_sq := diff.length_squared()
		if dist_sq > radius_sq:
			continue
		# 收拢沿径向：环外往内卷、贴脸的往外送到环（风涡眼），12px 死区内只定不挪
		var dist := sqrt(dist_sq)
		var out_dir := diff / dist if dist > 0.001 else Vector2.DOWN
		var ring_pt := Vector2(out_dir.x, out_dir.y * GameBalance.TARGETING_ELLIPSE_Y_RATIO) * BalanceSpiritPet.MELEE_RING
		var pull_vec := target.global_position + ring_pt - en.global_position
		var travel := pull_vec.length()
		# 牵引/定身的抗性折扣与 take_damage 击退同一把尺：精英 0.55，Boss 位移 0.18 / 钉身 ×0.25
		var is_boss := en is BossEnemy
		var elite_scale := 0.55 if en.is_elite else 1.0
		if travel > 12.0:
			pull_vec = pull_vec.normalized() * BalanceSpiritPet.pull_impulse(travel) * elite_scale * (GameBalance.BOSS_KNOCKBACK_RESIST if is_boss else 1.0)
		else:
			pull_vec = Vector2.ZERO
		# 先伤害后卷定：take_damage 传零击退会把 knockback_velocity 清零，顺序反了就卷不动
		en.take_damage(dmg, Vector2.ZERO)
		en.apply_vortex_pin(pull_vec, BalanceSpiritPet.pin_duration(elite_scale * en.hit_stun_resist * (0.25 if is_boss else 1.0)))
		affected += 1
		# 「定」飘字限量：满屏小怪被卷时防字海，口径同玄甲龟「抵挡」
		if affected <= 6 and scene_parent != null:
			DamageNumber.spawn(scene_parent, en.global_position + Vector2(0, -14), 0, false, "定")
	if affected > 0:
		pulse_trigger_fx(Vector2(1.25, 1.25), 0.15)
		_spin_angle = TAU * 2.0  # 旋转 720 度呼啸而过
		_custom_fx_type = "wind_vortex"
		if is_inside_tree() and scene_parent != null:
			# 光环画在玩家位置、半径=定身环横轴：怪被卷到哪一圈，光就亮哪一圈
			JuiceEffect.spawn_shockwave(scene_parent, target.global_position, BalanceSpiritPet.MELEE_RING, Color(0.85, 0.92, 1.0, 0.75), 0.3)
		AudioManager.play_sfx("fan_gust", 0.5, 0.85)

## 磐石猿：击退与震击
func _act_shiyuan() -> void:
	var dmg := BalanceSpiritPet.smash_damage(GameManager.wave_number, GameManager.pet_damage_mult)
	var radius := 110.0 * maxf(0.5, GameManager.pet_effect_mult)
	var hit: bool = false
	for e in GameManager.live_enemies:
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		var n2d := e as Node2D
		var diff := n2d.global_position - global_position
		if diff.length() <= radius:
			var kb_dir := diff.normalized() if diff.length() > 0.1 else Vector2.RIGHT
			if e.has_method("take_damage"):
				e.take_damage(dmg, kb_dir * 180.0, false)
				hit = true
	if hit:
		pulse_trigger_fx(Vector2(1.4, 0.7), 0.16)
		var scene_parent: Node = get_parent()
		if is_inside_tree() and scene_parent != null:
			# 岩土撼地波
			JuiceEffect.spawn_shockwave(scene_parent, global_position, radius, Color(0.72, 0.62, 0.45, 0.85), 0.32)
			JuiceEffect.spawn_step_dust(scene_parent, global_position, Vector2.DOWN)
		AudioManager.play_sfx("enemy_hit_heavy", 0.4, 0.95)

## 聚宝蟾：波末产出灵石触发视觉动效
func trigger_wave_harvest_fx() -> void:
	pulse_trigger_fx(Vector2(1.5, 0.8), 0.22)
	var scene_parent: Node = get_parent()
	if is_inside_tree() and scene_parent != null:
		# 金蟾喷吐金色灵髓流光
		JuiceEffect.spawn_pickup_pop(scene_parent, global_position, true)
		JuiceEffect.spawn_shockwave(scene_parent, global_position, 48.0, GameStyle.JADE, 0.35)

func _find_nearest_enemy(max_range: float) -> Node2D:
	var nearest: Node2D = null
	var min_d := max_range * max_range
	for e in GameManager.live_enemies:
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		if e.get("dying") == true:
			continue
		var n2d := e as Node2D
		var d := global_position.distance_squared_to(n2d.global_position)
		if d < min_d:
			min_d = d
			nearest = n2d
	return nearest

## 消散：淡出并销毁
func dissolve() -> void:
	if _dying:
		return
	_dying = true
	remove_from_group("spirit_pets")
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2(0.1, 0.1), DISSOLVE_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, DISSOLVE_SEC)
	tw.chain().tween_callback(queue_free)

# ---------------- 程序化绘制 ----------------

func _draw() -> void:
	var pulse: float = 0.5 + 0.5 * sin(_age * 3.0 + float(orbit_index))
	var flash_ratio: float = clampf(_flash_timer / 0.15, 0.0, 1.0)
	var core_r: float = (7.5 + 1.2 * pulse) * (1.0 + 0.35 * flash_ratio)
	var base_color: Color = pet_def.get("color", Color(0.9, 0.9, 0.9))
	var base_halo: Color = pet_def.get("halo_color", Color(1.0, 1.0, 1.0, 0.3))

	# 闪白提亮：受激/触发时瞬间过曝至乳白流光
	var color: Color = base_color.lerp(Color.WHITE, flash_ratio * 0.85)
	var halo: Color = base_halo.lerp(Color(1.0, 1.0, 1.0, 0.75), flash_ratio * 0.7)

	# 1. 外晕（触发时爆发扩张）
	var halo_scale: float = 2.4 + 1.2 * flash_ratio
	draw_circle(Vector2.ZERO, core_r * halo_scale, Color(halo.r, halo.g, halo.b, halo.a * (0.6 + 0.4 * pulse + 0.4 * flash_ratio)))
	# 2. 中晕
	draw_circle(Vector2.ZERO, core_r * 1.5, Color(color.r, color.g, color.b, 0.35 + 0.3 * flash_ratio))
	# 3. 核心
	draw_circle(Vector2.ZERO, core_r, color)
	# 4. 高光
	draw_circle(Vector2(-1.8, -2.5) * (1.0 + 0.2 * flash_ratio), core_r * 0.4, Color(1.0, 1.0, 1.0, 0.85))

	# 5. 特征部件
	var decor: String = String(pet_def.get("decor", ""))
	_draw_decor(decor, core_r, color)

	# 6. 法力连线（如玄甲龟拦截弹丸时的御灵连线）
	if _tether_progress >= 0.0 and _tether_target_pos != Vector2.ZERO:
		var tether_alpha: float = 1.0 - _tether_progress
		var tether_col: Color = GameStyle.AURUM
		tether_col.a = tether_alpha * 0.9
		# 主护身光束
		draw_line(Vector2.ZERO, _tether_target_pos, tether_col, 2.8 * tether_alpha)
		# 内芯白光
		draw_line(Vector2.ZERO, _tether_target_pos, Color(1.0, 1.0, 1.0, tether_alpha * 0.95), 1.2 * tether_alpha)
		# 连线中继符文节点
		draw_circle(_tether_target_pos * 0.5, 3.2 * tether_alpha, tether_col)
		draw_circle(_tether_target_pos, 4.0 * tether_alpha, Color(1.0, 1.0, 1.0, tether_alpha))

	# 7. 行动特效（波纹、雷弧或风灵气旋）
	if _action_fx >= 0.0:
		if _lightning_target_pos != Vector2.ZERO:
			# 雷弧短闪（折线电弧 + 主白内芯）
			var p1: Vector2 = _lightning_target_pos * 0.35 + Vector2(randf_range(-6, 6), randf_range(-6, 6))
			var p2: Vector2 = _lightning_target_pos * 0.7 + Vector2(randf_range(-6, 6), randf_range(-6, 6))
			var points: PackedVector2Array = PackedVector2Array([Vector2.ZERO, p1, p2, _lightning_target_pos])
			var arc_alpha: float = 1.0 - _action_fx
			draw_polyline(points, Color(0.68, 0.58, 1.0, arc_alpha), 3.0)
			draw_polyline(points, Color(1.0, 1.0, 1.0, arc_alpha * 0.9), 1.2)
		elif _custom_fx_type == "wind_vortex":
			# 灵风气旋双螺旋
			var wind_r: float = lerpf(core_r * 1.5, core_r * 4.5, _action_fx)
			var wind_alpha: float = (1.0 - _action_fx) * 0.8
			draw_arc(Vector2.ZERO, wind_r, _age * 12.0, _age * 12.0 + PI * 1.2, 24, Color(0.85, 0.92, 1.0, wind_alpha), 2.2)
			draw_arc(Vector2.ZERO, wind_r * 0.7, -_age * 10.0, -_age * 10.0 + PI * 1.2, 24, Color(0.7, 0.85, 1.0, wind_alpha * 0.7), 1.6)
		else:
			# 扩散波纹环（双重能量环：主环 + 亮白内圈）
			var ring_r: float = lerpf(core_r, core_r * 3.8, _action_fx)
			var ring_alpha: float = 1.0 - _action_fx
			draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 32, Color(color.r, color.g, color.b, ring_alpha * 0.85), 2.4)
			draw_arc(Vector2.ZERO, ring_r * 0.82, 0.0, TAU, 28, Color(1.0, 1.0, 1.0, ring_alpha * 0.6), 1.4)

func _draw_decor(decor: String, r: float, color: Color) -> void:
	match decor:
		"fox_ears_tail":
			# 尖耳 + 尾巴
			var ear_l := PackedVector2Array([Vector2(-r * 0.6, -r * 0.5), Vector2(-r * 0.9, -r * 1.4), Vector2(-r * 0.1, -r * 0.8)])
			var ear_r := PackedVector2Array([Vector2(r * 0.1, -r * 0.8), Vector2(r * 0.9, -r * 1.4), Vector2(r * 0.6, -r * 0.5)])
			draw_colored_polygon(ear_l, color.darkened(0.1))
			draw_colored_polygon(ear_r, color.darkened(0.1))
			# 小绒尾
			draw_circle(Vector2(r * 0.9, r * 0.6), r * 0.45, color.lightened(0.15))
		"bird_crest_beak":
			# 羽冠 + 小喙
			draw_line(Vector2(0, -r), Vector2(0, -r * 1.7), Color(1.0, 0.9, 0.4), 2.0)
			draw_line(Vector2(-2, -r), Vector2(-4, -r * 1.5), Color(1.0, 0.9, 0.4), 1.5)
			draw_colored_polygon(PackedVector2Array([Vector2(r * 0.5, -1), Vector2(r * 1.2, 0), Vector2(r * 0.5, 1.5)]), Color(1.0, 0.8, 0.2))
		"turtle_shell":
			# 背壳环纹
			draw_arc(Vector2.ZERO, r * 0.7, 0.0, TAU, 6, color.darkened(0.35), 1.6)
		"deer_horns":
			# 茸角
			draw_line(Vector2(-r * 0.5, -r * 0.7), Vector2(-r * 0.9, -r * 1.5), color.darkened(0.2), 2.0)
			draw_line(Vector2(r * 0.5, -r * 0.7), Vector2(r * 0.9, -r * 1.5), color.darkened(0.2), 2.0)
			draw_circle(Vector2(-r * 0.9, -r * 1.5), 1.6, Color(1.0, 0.8, 0.8))
			draw_circle(Vector2(r * 0.9, -r * 1.5), 1.6, Color(1.0, 0.8, 0.8))
		"toad_coin":
			# 头顶铜钱/元宝
			draw_circle(Vector2(0, -r * 1.05), r * 0.4, Color(1.0, 0.9, 0.3))
			draw_rect(Rect2(-1.2, -r * 1.05 - 1.2, 2.4, 2.4), color.darkened(0.3))
		"mink_tail":
			# 蓬松长尾
			draw_circle(Vector2(-r * 0.8, r * 0.5), r * 0.5, color.lightened(0.1))
			draw_circle(Vector2(-r * 1.3, r * 0.3), r * 0.35, color.lightened(0.2))
		"ape_brows":
			# 浓眉
			draw_line(Vector2(-r * 0.7, -r * 0.3), Vector2(-0.5, -r * 0.45), color.darkened(0.4), 2.0)
			draw_line(Vector2(0.5, -r * 0.45), Vector2(r * 0.7, -r * 0.3), color.darkened(0.4), 2.0)
