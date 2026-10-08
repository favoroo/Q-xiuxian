class_name FloatingWeapon
extends Node2D

## 环绕玩家的悬浮法器：数值/行为全部来自 WeaponData，星级影响伤害与冷却

@export var weapon_def_id: String = "qingyun_sword"
@export var star: int = 1

var def: Dictionary = {}
var behavior: int = WeaponData.Behavior.MELEE
var base_damage: float = 30.0
var attack_cooldown: float = 1.1
var attack_range: float = 150.0
var pierce: int = 1
var burst_radius: float = 80.0
var arc_scale: float = 1.0

var cooldown_timer: float = 0.0
var base_angle: float = 0.0        # 无目标时回归的基础槽位角（Player 下发）
var spread_angle: float = 0.0      # 多把法器间的错开角，避免重叠（Player 下发）
var orbit_extents: Vector2 = Vector2(80.0, 58.0)  # 环绕轨道半径（椭圆）
var dynamic_angle: float = 0.0     # 当前轨道角：有目标时滑向目标方位
var current_target: Node2D = null
var is_attacking: bool = false
var bob_phase: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var muzzle_point: Marker2D = $Sprite2D/MuzzlePoint
@onready var slash_sprite: Sprite2D = $SlashEffect

var muzzle_flash: Sprite2D

var projectile_scene: PackedScene = preload("res://scenes/weapons/BladeProjectile.tscn")
var burst_scene: PackedScene = preload("res://scenes/weapons/ThunderBurst.tscn")
const LightningBoltScript = preload("res://scripts/weapons/LightningBolt.gd")

const CHARGE_GLOW := Color(1.45, 1.28, 0.62)   # 五雷蓄力时的金光

## 必须在 add_child 之前调用
func setup(def_id: String, star_level: int) -> void:
	weapon_def_id = def_id
	star = clampi(star_level, 1, WeaponData.MAX_STAR)
	def = WeaponData.get_def(def_id)
	behavior = int(def.get("behavior", WeaponData.Behavior.MELEE))
	base_damage = WeaponData.damage_for(def_id, star)
	attack_cooldown = WeaponData.cooldown_for(def_id, star)
	attack_range = float(def.get("range", 150.0))
	pierce = int(def.get("pierce", 1))
	burst_radius = float(def.get("burst_radius", 80.0))
	arc_scale = float(def.get("arc_scale", 1.0))

func _ready() -> void:
	slash_sprite.visible = false
	slash_sprite.modulate.a = 0.0
	bob_phase = randf() * TAU
	dynamic_angle = base_angle
	if def.is_empty():
		setup(weapon_def_id, star)
	if def.has("icon"):
		sprite.texture = load(def["icon"])
	_setup_muzzle_flash()

## 枪口闪光（远程法器开火反馈）：叠加发光的径向光斑
func _setup_muzzle_flash() -> void:
	muzzle_flash = Sprite2D.new()
	var tex := load("res://assets/art/light_radial.png") as Texture2D
	if tex == null:
		return
	muzzle_flash.texture = tex
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	muzzle_flash.material = mat
	muzzle_flash.position = muzzle_point.position
	muzzle_flash.z_index = 6
	muzzle_flash.visible = false
	sprite.add_child(muzzle_flash)

## 武器本体短促亮闪（近战挥砍/远程开火共用）
func _flash_sprite(color: Color, dur: float) -> void:
	sprite.modulate = color
	var ftw := create_tween()
	ftw.tween_property(sprite, "modulate", Color.WHITE, dur)

func _process(delta: float) -> void:
	if GameManager.is_game_over:
		return

	cooldown_timer -= delta
	bob_phase += delta * 3.5

	# 1. 索敌：优先保留 Player 统筹分配的智能多向目标；若目标失效或脱离射程则安全回退
	if current_target == null or not is_instance_valid(current_target):
		current_target = _find_target()
	else:
		var player = GameManager.player
		if player != null:
			var max_reach = attack_range * GameManager.attack_range_mult * GameManager.synergy_range_mult * 1.2
			if player.global_position.distance_to(current_target.global_position) > max_reach:
				current_target = _find_target()

	# 2. 动态轨道：有目标时沿轨道滑向目标方位（自动换位），无目标时回归基础槽位
	if not is_attacking:
		var player = GameManager.player
		var desired_angle = base_angle
		var track_speed = 4.0
		if current_target != null and player != null:
			desired_angle = (current_target.global_position - player.global_position).angle() + spread_angle
			track_speed = 8.0
		dynamic_angle = lerp_angle(dynamic_angle, desired_angle, minf(delta * track_speed, 1.0))
		var orbit_pos = Vector2(cos(dynamic_angle) * orbit_extents.x, sin(dynamic_angle) * orbit_extents.y)
		var bob_y = sin(bob_phase) * 3.0
		position = position.lerp(orbit_pos + Vector2(0, bob_y), minf(delta * 14.0, 1.0))

	# 3. 朝向：有目标面向目标；无目标朝轨道外
	if not is_attacking:
		if current_target != null:
			var target_angle = (current_target.global_position - global_position).angle()
			rotation = lerp_angle(rotation, target_angle, minf(delta * 15.0, 1.0))
		else:
			rotation = lerp_angle(rotation, dynamic_angle, minf(delta * 6.0, 1.0))

		var norm_rot = wrapf(rotation, -PI, PI)
		sprite.flip_v = abs(norm_rot) > PI * 0.5

	# 4. 攻击
	if cooldown_timer <= 0.0 and current_target != null and not is_attacking:
		_perform_attack()

func _perform_attack() -> void:
	cooldown_timer = attack_cooldown * GameManager.attack_speed_mult * GameManager.synergy_haste_mult
	match behavior:
		WeaponData.Behavior.MELEE:
			_perform_melee_attack()
		WeaponData.Behavior.PROJECTILE:
			_perform_projectile_attack()
		WeaponData.Behavior.BURST:
			_perform_burst_attack()

func _final_damage() -> float:
	var stat_bonus := GameManager.get_weapon_stat_bonus(weapon_def_id, star)
	return (base_damage + stat_bonus) * GameManager.weapon_damage_mult * GameManager.synergy_damage_mult * GameManager.cultivator_damage_mult(weapon_def_id) * GameManager.element_damage_mult(weapon_def_id)

func _perform_projectile_attack() -> void:
	is_attacking = true

	var aim_dir = Vector2.RIGHT.rotated(rotation)
	if current_target != null:
		aim_dir = (current_target.global_position - global_position).normalized()
		rotation = aim_dir.angle()

	# 后坐动画
	var orig_pos = position
	var recoil_pos = orig_pos - aim_dir * 8.0
	var tw = create_tween()
	tw.tween_property(self, "position", recoil_pos, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "position", orig_pos, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): is_attacking = false)

	# 开火反馈：枪口闪光 + 本体亮闪
	if muzzle_flash != null:
		muzzle_flash.rotation = randf() * TAU
		muzzle_flash.scale = Vector2.ONE * randf_range(0.42, 0.52)
		muzzle_flash.modulate = Color(1.0, 0.9, 0.55, 0.95)
		muzzle_flash.visible = true
		var ftw = create_tween()
		ftw.set_parallel(true)
		ftw.tween_property(muzzle_flash, "scale", Vector2.ONE * 0.85, 0.09)
		ftw.tween_property(muzzle_flash, "modulate:a", 0.0, 0.09)
		ftw.chain().tween_callback(func(): muzzle_flash.visible = false)
	_flash_sprite(Color(1.35, 1.35, 1.35), 0.12)

	var p_count: int = maxi(1, int(def.get("projectile_count", 1)))
	var p_spread: float = float(def.get("spread_angle", 0.2))
	var p_bounce: int = int(def.get("bounce_count", 0))
	var final_dmg: float = _final_damage()
	# 逐发锁定：一次三发的法器，每一发各咬一个最近的敌人。
	# 旧写法三发全按同一个 aim_dir 扇形散开 ⇒ 只剩一个敌人时两边那两发飞过头顶（仿真：350px
	# 处散布侧偏 70+px，而判定只有 7px + 受击圈 15px），群怪时又因为不追踪而大量空放。
	# 现在"扇形疾射…贯穿群敌"按文案兑现：出膛照旧扇形错开，各自追上自己咬定的那一个；
	# 场上只剩一个敌人时三发也统统归它 —— 单点爆发不再靠运气。
	var volley: Array[Node2D] = _volley_targets(p_count)

	for idx in range(p_count):
		var p = projectile_scene.instantiate() as BladeProjectile
		p.global_position = muzzle_point.global_position
		var offset_ang := 0.0
		if p_count > 1:
			offset_ang = (float(idx) - float(p_count - 1) * 0.5) * p_spread
		# 出膛方向：优先朝这一发自己咬定的敌人，再叠扇形错开角（没有第二目标时退回主目标方位）
		var shot_dir: Vector2 = aim_dir
		var locked: Node2D = volley[idx % volley.size()] if not volley.is_empty() else null
		if locked != null:
			var to_lock: Vector2 = locked.global_position - muzzle_point.global_position
			if to_lock.length_squared() > 1.0:
				shot_dir = to_lock.normalized()
		p.homing_target = locked
		p.direction = shot_dir.rotated(offset_ang)
		p.damage = final_dmg
		p.pierce_left = pierce + GameManager.bonus_pierce
		p.bounce_left = p_bounce
		p.lifetime *= GameManager.attack_range_mult * GameManager.synergy_range_mult
		p.spin = behavior != WeaponData.Behavior.PROJECTILE or pierce <= 1
		if def.get("proc_burn", false):
			p.proc_burn = true
			p.burn_dps = final_dmg * float(def.get("burn_ratio", 0.4))
			p.burn_dur = float(def.get("burn_dur", 3.0))
		if float(def.get("proc_chill", 0.0)) > 0.0:
			p.proc_chill = float(def.get("proc_chill", 0.35))
			p.chill_dur = float(def.get("chill_dur", 2.0))
		if def.get("proc_poison", false):
			p.proc_poison = true
			p.poison_dps = final_dmg * float(def.get("poison_ratio", 0.3))
			p.poison_dur = float(def.get("poison_dur", 2.5))
		get_tree().current_scene.add_child(p)

	AudioManager.play_sfx(WeaponData.sfx_for(weapon_def_id))

func _perform_burst_attack() -> void:
	is_attacking = true

	var target_pos = global_position + Vector2.RIGHT.rotated(rotation) * 30.0
	if current_target != null and is_instance_valid(current_target):
		target_pos = current_target.global_position

	var strike_dir := (target_pos - global_position).normalized()
	var orig_pos := position
	var cast_pos := orig_pos + Vector2(0.0, -16.0)

	# 施法演出：法牌升起蓄力、金光微颤 → 引雷落于目标 → 前突回落
	AudioManager.play_sfx("orb_hit", 0.7)
	var tw = create_tween()
	tw.tween_property(self, "position", cast_pos, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "scale", Vector2(1.22, 1.22), 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(sprite, "modulate", CHARGE_GLOW, 0.10)
	for i in range(3):
		tw.tween_property(self, "position", cast_pos + Vector2(randf_range(-2.5, 2.5), randf_range(-2.5, 2.5)), 0.035)
	tw.tween_callback(func(): _spawn_lightning(target_pos))
	tw.tween_property(self, "position", orig_pos + strike_dir * 12.0, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(sprite, "modulate", Color(1.9, 1.85, 1.45), 0.05)
	tw.tween_property(self, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "position", orig_pos, 0.15).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(sprite, "modulate", Color.WHITE, 0.18)
	tw.tween_callback(func(): is_attacking = false)

## 引雷：锯齿闪电从法器射向落雷点，落雷爆发在 ThunderBurst 自身的 _ready 里结算
func _spawn_lightning(target_pos: Vector2) -> void:
	var bolt = LightningBoltScript.new()
	bolt.from = muzzle_point.global_position
	bolt.to = target_pos
	bolt.width_mult = 1.0 + 0.18 * float(star - 1)
	get_tree().current_scene.add_child(bolt)

	var burst = burst_scene.instantiate()
	burst.global_position = target_pos
	burst.radius = burst_radius * GameManager.attack_range_mult * GameManager.synergy_range_mult
	var final_dmg := _final_damage()
	burst.damage = final_dmg
	if def.get("proc_burn", false):
		burst.proc_burn = true
		burst.burn_dps = final_dmg * float(def.get("burn_ratio", 0.5))
		burst.burn_dur = float(def.get("burn_dur", 3.0))
	get_tree().current_scene.add_child(burst)

func _perform_melee_attack() -> void:
	is_attacking = true

	var aim_dir = Vector2.RIGHT.rotated(rotation)
	if current_target != null:
		aim_dir = (current_target.global_position - global_position).normalized()

	var aim_angle = aim_dir.angle()
	var orig_pos = position
	var thrust_pos = orig_pos + aim_dir * 26.0

	# 挥砍弧光
	var swing = deg_to_rad(45.0) * arc_scale
	var tw = create_tween()
	rotation = aim_angle - swing
	slash_sprite.visible = true
	slash_sprite.modulate.a = 1.0
	slash_sprite.rotation = 0.0
	slash_sprite.scale = Vector2.ONE * arc_scale
	# 挥砍反馈：本体亮闪 + 轻微弹张
	_flash_sprite(Color(1.45, 1.45, 1.45), 0.15)
	scale = Vector2(1.08, 1.08)

	tw.set_parallel(true)
	tw.tween_property(self, "position", thrust_pos, 0.08).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(self, "rotation", aim_angle + swing, 0.14).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(slash_sprite, "rotation", deg_to_rad(90.0) * arc_scale, 0.14)
	tw.tween_property(slash_sprite, "modulate:a", 0.0, 0.18)

	tw.chain().set_parallel(false)
	tw.tween_property(self, "position", orig_pos, 0.12).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(self, "scale", Vector2.ONE, 0.14)
	tw.tween_callback(func():
		is_attacking = false
		slash_sprite.visible = false
	)

	AudioManager.play_sfx(WeaponData.sfx_for(weapon_def_id), 1.15)

	_deal_melee_damage(aim_dir)

func _deal_melee_damage(aim_dir: Vector2) -> void:
	var space_state = get_world_2d().direct_space_state
	var shape = CircleShape2D.new()
	shape.radius = 75.0 * arc_scale * GameManager.attack_range_mult * GameManager.synergy_range_mult
	var query = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, global_position + aim_dir * 30.0)
	query.collision_mask = 4
	query.collide_with_areas = true
	var results = space_state.intersect_shape(query, 24)

	for res in results:
		var col = res["collider"]
		if col and col.get_parent() and col.get_parent().has_method("take_damage"):
			var enemy = col.get_parent()
			var dmg = _final_damage() * 1.35
			var is_crit = GameManager.rng.randf() < GameManager.get_crit_rate()
			if is_crit:
				dmg *= GameManager.crit_mult + GameManager.synergy_crit_mult
			dmg *= GameManager.elite_damage_mult_for(enemy)
			var knock = GameManager.knockback_vec(global_position, enemy.global_position, 240.0)
			enemy.take_damage(dmg, knock, is_crit)
			if def.get("proc_burn", false) and enemy.has_method("apply_burn"):
				enemy.apply_burn(dmg * float(def.get("burn_ratio", 0.45)), float(def.get("burn_dur", 3.0)))
			if float(def.get("proc_chill", 0.0)) > 0.0 and enemy.has_method("apply_chill"):
				enemy.apply_chill(float(def.get("proc_chill", 0.35)), float(def.get("chill_dur", 2.5)))
			if def.get("proc_poison", false) and enemy.has_method("apply_poison"):
				enemy.apply_poison(dmg * float(def.get("poison_ratio", 0.35)), float(def.get("poison_dur", 3.0)))
			GameManager.try_lifesteal()
	# 一挥扫中一片也只算「打了几下」，不是「打了几件事」：
	# 震屏与顿帧由 EnemyBase.take_damage 按目标重要性发放，武器侧不再重复叠加

func _find_target() -> Node2D:
	var player = GameManager.player
	if player == null:
		return null
	var space_state = get_world_2d().direct_space_state
	var shape = CircleShape2D.new()
	shape.radius = attack_range * GameManager.attack_range_mult * GameManager.synergy_range_mult
	var query = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	# 以玩家为圆心索敌：武器会自行换位到目标一侧，四周的敌人都在打击范围内
	query.transform = Transform2D(0.0, player.global_position)
	query.collision_mask = 4
	query.collide_with_areas = true
	var results = space_state.intersect_shape(query, 32)

	var nearest: Node2D = null
	var min_dist: float = 999999.0
	for res in results:
		var col = res["collider"]
		if col and col.get_parent() and col.get_parent().has_method("take_damage"):
			var enemy = col.get_parent()
			if enemy.is_in_group("herbs"):
				continue  # 灵药丛可被波及摧毁，但不作为索敌目标
			var d = player.global_position.distance_to(enemy.global_position)
			if d < min_dist:
				min_dist = d
				nearest = enemy
	return nearest

## 逐发分配锁定目标：主目标（Player 按扇区统筹分配的那一个）排第一，其余按离炮口的远近补齐。
## 返回长度 = min(场上可用人手, n)，调用方按 idx % size 取用 ⇒ 怪少时多发自然归约到同一个敌人。
## 纯索敌，不改任何数值：弹丸拿到目标后按 BladeProjectile.HOMING_TURN_RATE 自己拐过去。
func _volley_targets(n: int) -> Array[Node2D]:
	var out: Array[Node2D] = []
	if n <= 0:
		return out
	if current_target != null and is_instance_valid(current_target):
		out.append(current_target)
	if n <= 1:
		return out
	var player = GameManager.player
	if player == null:
		return out
	var space_state = get_world_2d().direct_space_state
	var shape = CircleShape2D.new()
	shape.radius = attack_range * GameManager.attack_range_mult * GameManager.synergy_range_mult
	var query = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, player.global_position)
	query.collision_mask = 4
	query.collide_with_areas = true
	var results = space_state.intersect_shape(query, 32)
	var muzzle_pos: Vector2 = muzzle_point.global_position
	var cands: Array[Node2D] = []
	for res in results:
		var col = res.get("collider")
		if col == null or col.get_parent() == null:
			continue
		var e := col.get_parent() as Node2D
		if e == null or not e.has_method("take_damage") or e.is_in_group("herbs"):
			continue
		if out.has(e):
			continue
		cands.append(e)
	# 离炮口近的先被咬住：一次三发就是"点掉最近的三个"，而不是随便抽三个签
	cands.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return muzzle_pos.distance_squared_to(a.global_position) < muzzle_pos.distance_squared_to(b.global_position))
	for e in cands:
		if out.size() >= n:
			break
		out.append(e)
	return out
