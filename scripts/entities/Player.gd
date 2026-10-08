class_name Player
extends CharacterBody2D

@export var max_health: float = 120.0
var current_health: float = 120.0
var base_speed: float = 210.0
var invulnerable_time: float = 0.0

@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var shadow_sprite: Sprite2D = $Shadow
@onready var sun_orb_container: Node2D = $SunOrbContainer
@onready var weapon_holder: Node2D = $WeaponHolder
@onready var pickup_area: Area2D = $PickupArea
@onready var hit_flash_mat: ShaderMaterial = anim_sprite.material as ShaderMaterial

var sun_orb_angle: float = 0.0
var idle_bob_phase: float = 0.0
var facing: String = "s"
var anim_base_scale: Vector2 = Vector2.ONE
var juice_scale: Vector2 = Vector2.ONE
var regen_tick: float = 0.0
var flash_tween: Tween = null
var squash_tween: Tween = null
var dust_timer: float = 0.0

var floating_weapon_scene: PackedScene = preload("res://scenes/weapons/FloatingWeapon.tscn")
var sun_orb_scene: PackedScene = preload("res://scenes/weapons/SunOrb.tscn")

func _ready() -> void:
	current_health = max_health
	GameManager.player = self
	GameManager.player_hp_changed.emit(current_health, max_health)
	GameManager.player_leveled_up.connect(_on_leveled_up)
	GameManager.upgrade_applied.connect(_on_upgrade_applied)
	_setup_sprite_frames()
	anim_base_scale = anim_sprite.scale
	# 浮游法器在 _process 里做轨道跟随（渲染帧率），父链开了物理插值会互相打架，关闭该分支插值
	weapon_holder.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	sync_drones()
	_sync_pickup_radius()

func _setup_sprite_frames() -> void:
	var base_tex = load("res://assets/art/pawn_blue_8dir.png") as Texture2D
	var sf = SpriteFrames.new()
	for dir in RunMotion.DIR_ROW:
		var row: int = RunMotion.DIR_ROW[dir]
		sf.add_animation("idle_" + dir)
		sf.set_animation_speed("idle_" + dir, 1.0)
		sf.set_animation_loop("idle_" + dir, true)
		sf.add_frame("idle_" + dir, _cell_tex(base_tex, 0, row))

		sf.add_animation("run_" + dir)
		sf.set_animation_speed("run_" + dir, 10.5)
		sf.set_animation_loop("run_" + dir, true)
		for c in range(1, 5):
			sf.add_frame("run_" + dir, _cell_tex(base_tex, c, row))

	anim_sprite.sprite_frames = sf
	anim_sprite.play("idle_s")

func _cell_tex(tex: Texture2D, col: int, row: int) -> AtlasTexture:
	var at = AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(col * 192, row * 192, 192, 192)
	return at

## 挤压与拉伸（Squash & Stretch）手感核心方法
func play_squash(target: Vector2, duration: float = 0.18) -> void:
	if squash_tween != null and squash_tween.is_valid():
		squash_tween.kill()
	juice_scale = target
	squash_tween = create_tween()
	squash_tween.tween_property(self, "juice_scale", Vector2.ONE, duration)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_upgrade_applied(up_id: String) -> void:
	if up_id == "pickup_up":
		_sync_pickup_radius()

func _sync_pickup_radius() -> void:
	var shape_node = $PickupArea/CollisionShape2D
	if shape_node != null and shape_node.shape is CircleShape2D:
		var c_shape = shape_node.shape.duplicate() as CircleShape2D
		c_shape.radius = 96.0 * GameManager.pickup_range_mult
		shape_node.shape = c_shape

func _on_leveled_up(_lvl: int) -> void:
	play_squash(Vector2(0.72, 1.38), 0.28)
	JuiceEffect.spawn_death_burst(get_parent(), global_position, true)

# ---------------- 武器管理 ----------------

func add_weapon_instance(def_id: String, star: int) -> void:
	var weapon = floating_weapon_scene.instantiate() as FloatingWeapon
	weapon.setup(def_id, star)
	weapon_holder.add_child(weapon)
	_recalculate_weapon_slots()

func upgrade_weapon_instance(node: Node, new_star: int) -> void:
	if node == null or not is_instance_valid(node) or not (node is FloatingWeapon):
		return
	var w := node as FloatingWeapon
	w.setup(w.weapon_def_id, new_star)
	var tw := create_tween()
	tw.tween_property(w, "scale", Vector2(1.45, 1.45), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(w, "scale", Vector2.ONE, 0.14)

func remove_weapon_instance(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.queue_free()
	equipped_cleanup()
	_recalculate_weapon_slots()

func equipped_cleanup() -> void:
	for i in range(weapon_holder.get_child_count() - 1, -1, -1):
		var child = weapon_holder.get_child(i)
		if not is_instance_valid(child) or child.is_queued_for_deletion():
			weapon_holder.remove_child(child)
			child.free()

func get_weapon_count() -> int:
	equipped_cleanup()
	return weapon_holder.get_child_count()

func _recalculate_weapon_slots() -> void:
	var count = get_weapon_count()
	if count == 0:
		return
	for i in range(count):
		var w = weapon_holder.get_child(i) as FloatingWeapon
		w.base_angle = float(i) * (TAU / float(count))
		w.spread_angle = (float(i) - float(count - 1) * 0.5) * deg_to_rad(28.0)
		w.orbit_extents = Vector2(80.0, 58.0)

func get_equipped_weapons_data() -> Array[Dictionary]:
	equipped_cleanup()
	var list: Array[Dictionary] = []
	for w in weapon_holder.get_children():
		if not is_instance_valid(w):
			continue
		var def := WeaponData.get_def(w.weapon_def_id)
		list.append({
			"id": w.weapon_def_id,
			"name": def.get("name", "?"),
			"star": w.star,
			"tag": def.get("tag", ""),
			"icon": def.get("icon", ""),
			"node": w,
		})
	return list

func sync_drones() -> void:
	var target: Array = GameManager.drones
	var current_count = sun_orb_container.get_child_count()
	if current_count < target.size():
		for i in range(target.size() - current_count):
			var orb = sun_orb_scene.instantiate()
			sun_orb_container.add_child(orb)
	elif current_count > target.size():
		for i in range(current_count - target.size()):
			sun_orb_container.get_child(0).queue_free()
	for i in range(sun_orb_container.get_child_count()):
		var orb = sun_orb_container.get_child(i) as SunOrb
		if orb != null and i < target.size():
			var d_entry = target[i]
			var d_id: String = GameManager._drone_id(d_entry)
			var d_star: int = GameManager._drone_star(d_entry)
			orb.setup(d_star, d_id)

func heal(amount: float, quiet: bool = false) -> void:
	if amount <= 0.0:
		return
	current_health = minf(max_health, current_health + amount)
	GameManager.player_hp_changed.emit(current_health, max_health)
	if quiet:
		return
	play_squash(Vector2(0.88, 1.16), 0.18)
	AudioManager.play_sfx("heal", 0.9)
	DamageNumber.spawn(get_parent(), global_position, int(amount), false, "+" + str(int(amount)))

# ---------------- 主循环 ----------------

func _physics_process(delta: float) -> void:
	if GameManager.is_game_over:
		return

	if invulnerable_time > 0.0:
		invulnerable_time -= delta
		anim_sprite.modulate.a = 0.55 if fmod(invulnerable_time, 0.12) > 0.06 else 1.0
	else:
		anim_sprite.modulate.a = 1.0

	# 灵愈心法 + 青木羁绊：持续回血
	var total_regen := GameManager.hp_regen + GameManager.synergy_hp_regen
	if total_regen > 0.0 and current_health < max_health:
		current_health = minf(max_health, current_health + total_regen * delta)
		regen_tick += delta
		if regen_tick >= 0.5:
			regen_tick = 0.0
			GameManager.player_hp_changed.emit(current_health, max_health)

	# 1. 移动输入与高响应加减速平滑
	var dir: Vector2 = Vector2.ZERO
	if GameManager.joystick != null and GameManager.joystick.has_method("get_direction"):
		dir = GameManager.joystick.get_direction()
	else:
		dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

	var target_speed := base_speed * (GameManager.move_speed_mult + GameManager.synergy_move_speed_mult)
	var target_velocity := dir * target_speed
	var input_moving := dir.length_squared() > 0.03
	var actual_speed_sq := velocity.length_squared()
	# 松手减速到目标速度的 35% 以下立即切待机：否则腿在原地踏步而身体还在滑行（悬浮感来源）
	var stop_threshold := maxf(30.0, target_speed * 0.35)
	var is_moving := input_moving or actual_speed_sq > stop_threshold * stop_threshold
	var accel := 2200.0 if input_moving else 2800.0
	velocity = velocity.move_toward(target_velocity, accel * delta)
	move_and_slide()

	# 灵田界碑边界
	var lim: float = GameManager.MAP_HALF_EXTENT - 26.0
	global_position = global_position.clamp(Vector2(-lim, -lim), Vector2(lim, lim))

	# 2. 奔跑步伐微尘
	if is_moving and actual_speed_sq > 1600.0:
		dust_timer -= delta
		if dust_timer <= 0.0:
			dust_timer = 0.22
			JuiceEffect.spawn_step_dust(get_parent(), global_position + Vector2(0, 14), velocity)
	else:
		dust_timer = 0.0

	# 3. Sprite 方向 & 动画（带迟滞滤波 + 移速步频自适应 + 统一形变插值流）
	var current_base := anim_base_scale * juice_scale
	var current_speed := velocity.length()
	var speed_ratio: float = (current_speed / target_speed) if target_speed > 0.0 else 1.0

	if is_moving:
		# 使用带迟滞区间的 8 方向平滑算法，彻底消除摇杆临界角度导致的快速抽搐
		var effective_dir := dir if input_moving else velocity.normalized()
		var face: Array = RunMotion.facing_stable(effective_dir, facing, anim_sprite.flip_h, 29.0)
		if face[0] != "":
			facing = face[0]
			anim_sprite.flip_h = face[1]

		var run_anim: String = "run_" + facing
		RunMotion.select_anim(anim_sprite, run_anim, true)

		var lean_axis: float = absf(effective_dir.x)
		RunMotion.apply(anim_sprite, current_base, true, anim_sprite.flip_h, lean_axis, delta, speed_ratio, 0.0, shadow_sprite)
	else:
		var idle_anim: String = "idle_" + facing
		RunMotion.select_anim(anim_sprite, idle_anim, false)
		idle_bob_phase += delta * 2.2
		RunMotion.apply(anim_sprite, current_base, false, anim_sprite.flip_h, 0.0, delta, 1.0, idle_bob_phase, shadow_sprite)

	# 4. 灵蝶环绕运算
	_process_sun_orbs(delta)

	# 5. 统一调度各法器索敌目标（多向分流 + 贴身危急集火 + 动态扇形展开）
	_update_weapon_targets()

func _update_weapon_targets() -> void:
	equipped_cleanup()
	var count = weapon_holder.get_child_count()
	if count == 0:
		return

	var weapons: Array[FloatingWeapon] = []
	var max_range: float = 0.0
	for i in range(count):
		var w = weapon_holder.get_child(i) as FloatingWeapon
		if w != null and is_instance_valid(w):
			weapons.append(w)
			var w_range = w.attack_range * GameManager.attack_range_mult * GameManager.synergy_range_mult
			if w_range > max_range:
				max_range = w_range

	if weapons.is_empty() or max_range <= 0.0:
		return

	var space_state = get_world_2d().direct_space_state
	var shape = CircleShape2D.new()
	shape.radius = max_range
	var query = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = 4
	query.collide_with_areas = true
	var results = space_state.intersect_shape(query, 32)

	var candidate_enemies: Array[Node2D] = []
	var seen_ids := {}
	for res in results:
		var col = res.get("collider")
		if col and col.get_parent() and col.get_parent().has_method("take_damage"):
			var enemy = col.get_parent() as Node2D
			if not is_instance_valid(enemy) or enemy.is_in_group("herbs"):
				continue
			var eid := enemy.get_instance_id()
			if seen_ids.has(eid):
				continue
			seen_ids[eid] = true
			candidate_enemies.append(enemy)

	# 按距玩家从近到远排序，保证贴身危急判定与同向优先级稳定
	candidate_enemies.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position)
	)

	var weapons_info: Array[Dictionary] = []
	for w in weapons:
		var prev_id := 0
		if w.current_target != null and is_instance_valid(w.current_target):
			prev_id = w.current_target.get_instance_id()
		var w_range := w.attack_range * GameManager.attack_range_mult * GameManager.synergy_range_mult
		weapons_info.append({
			"base_angle": w.base_angle,
			"range": w_range,
			"prev_id": prev_id,
		})

	var enemies_info: Array[Dictionary] = []
	for e in candidate_enemies:
		var offset := e.global_position - global_position
		enemies_info.append({
			"id": e.get_instance_id(),
			"dist": offset.length(),
			"angle": offset.angle(),
		})

	var assignments: Array = GameBalance.assign_weapon_targets(weapons_info, enemies_info)

	# 按实际共享同一目标的法器分组计算扇形错开角：独自迎敌时不偏移，共享目标时扇形展开
	var target_groups := {}
	for i in range(weapons.size()):
		var t_idx := int(assignments[i])
		if t_idx >= 0:
			if not target_groups.has(t_idx):
				target_groups[t_idx] = []
			target_groups[t_idx].append(i)

	for i in range(weapons.size()):
		var w := weapons[i]
		var t_idx := int(assignments[i])
		if t_idx >= 0 and t_idx < candidate_enemies.size():
			var group: Array = target_groups[t_idx]
			var group_size := group.size()
			var pos_in_group := group.find(i)
			w.spread_angle = (float(pos_in_group) - float(group_size - 1) * 0.5) * deg_to_rad(24.0)
			if not w.is_attacking:
				w.current_target = candidate_enemies[t_idx]
		else:
			w.spread_angle = 0.0
			if not w.is_attacking:
				w.current_target = null

func _process_sun_orbs(delta: float) -> void:
	sun_orb_angle += delta * 2.8
	var count = sun_orb_container.get_child_count()
	if count == 0:
		return
	var radius = 78.0 * GameManager.attack_range_mult
	for i in range(count):
		var orb = sun_orb_container.get_child(i) as Node2D
		var a = sun_orb_angle + float(i) * (TAU / float(count))
		orb.position = Vector2(cos(a), sin(a)) * radius

func take_damage(amount: float) -> void:
	if invulnerable_time > 0.0 or GameManager.is_game_over:
		return

	# 流云身法：闪避成功不掉血、不消耗无敌帧
	if GameManager.rng.randf() < GameManager.get_effective_dodge():
		DamageNumber.spawn(get_parent(), global_position, 0, false, "身法回避")
		AudioManager.play_sfx("dodge", 1.0)
		return

	var reduced := GameBalance.incoming_damage(amount, GameManager.get_effective_armor())
	current_health = maxf(0.0, current_health - reduced)
	invulnerable_time = 0.55
	GameManager.player_hp_changed.emit(current_health, max_health)

	# game-feel 复合打击反馈：相机大创伤 + 顿帧 + 屏幕边缘红晕脉冲 + 玩家受力挤压
	GameManager.feedback(GameManager.FeedbackTier.LARGE)
	GameManager.pulse_damage_vignette(Color(0.85, 0.12, 0.12, 0.65), 0.24)
	play_squash(Vector2(1.35, 0.72), 0.22)
	JuiceEffect.spawn_hit_sparks(get_parent(), global_position, Vector2.UP, false)
	AudioManager.play_sfx("enemy_hit", 0.8)

	if hit_flash_mat != null:
		if flash_tween != null and flash_tween.is_valid():
			flash_tween.kill()
		flash_tween = create_tween()
		flash_tween.tween_property(hit_flash_mat, ^"shader_parameter/flash_modifier", 1.0, 0.03)
		flash_tween.tween_property(hit_flash_mat, ^"shader_parameter/flash_modifier", 0.0, 0.1)

	DamageNumber.spawn(get_parent(), global_position, int(reduced), false)

	if current_health <= 0.0:
		GameManager.trigger_game_over(false)

func increase_max_hp(amount: float, heal_amount: float) -> void:
	max_health += amount
	current_health = minf(max_health, current_health + heal_amount)
	GameManager.player_hp_changed.emit(current_health, max_health)
	play_squash(Vector2(0.82, 1.25), 0.24)
	DamageNumber.spawn(get_parent(), global_position, int(heal_amount), false, "+" + str(int(heal_amount)) + " HP")

func _on_pickup_area_area_entered(area: Area2D) -> void:
	if area.has_method("magnet_to"):
		area.magnet_to(self)
	elif area.get_parent() and area.get_parent().has_method("magnet_to"):
		area.get_parent().magnet_to(self)
