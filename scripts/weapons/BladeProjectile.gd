class_name BladeProjectile
extends Area2D

## 法器弹丸：伤害由 FloatingWeapon 计算好后直接传入，支持穿透、弹射连锁与五行异常

var direction: Vector2 = Vector2.RIGHT
var speed: float = 470.0
var damage: float = 20.0
var lifetime: float = 1.6
var pierce_left: int = 1
var bounce_left: int = 0
var spin: bool = true

# 五行异常触发
var proc_burn: bool = false
var burn_dps: float = 0.0
var burn_dur: float = 3.0
var proc_chill: float = 0.0
var chill_dur: float = 2.0
var proc_poison: bool = false
var poison_dps: float = 0.0
var poison_dur: float = 2.5

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	rotation = direction.angle()
	if spin:
		var tw = create_tween().set_loops()
		tw.tween_property(sprite, "rotation", TAU, 0.45).as_relative()
	_apply_elemental_tint()

func _apply_elemental_tint() -> void:
	if proc_burn:
		modulate = Color(1.3, 0.75, 0.45)
	elif proc_chill > 0.0:
		modulate = Color(0.65, 0.9, 1.3)
	elif proc_poison:
		modulate = Color(0.65, 1.3, 0.65)

func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()

func _on_area_entered(area: Area2D) -> void:
	var enemy = area.get_parent()
	if enemy and enemy.has_method("take_damage"):
		var is_crit = GameManager.rng.randf() < GameManager.get_crit_rate()
		var crit_m := GameManager.crit_mult + GameManager.synergy_crit_mult
		var actual_dmg = damage * (crit_m if is_crit else 1.0)
		enemy.take_damage(actual_dmg, direction * 140.0, is_crit)
		GameManager.try_lifesteal()

		# 施加五行异常
		if proc_burn and enemy.has_method("apply_burn"):
			enemy.apply_burn(burn_dps, burn_dur)
		if proc_chill > 0.0 and enemy.has_method("apply_chill"):
			enemy.apply_chill(proc_chill, chill_dur)
		if proc_poison and enemy.has_method("apply_poison"):
			enemy.apply_poison(poison_dps, poison_dur)

		JuiceEffect.spawn_hit_sparks(get_parent(), global_position, direction, is_crit)
		if is_crit:
			GameManager.feedback(GameManager.FeedbackTier.MEDIUM)
		else:
			GameManager.add_trauma(0.06)

		# 弹射连锁：若有弹射次数，向最近另一敌人折射
		if bounce_left > 0:
			var next_enemy := _find_bounce_target(enemy)
			if next_enemy != null:
				bounce_left -= 1
				direction = (next_enemy.global_position - global_position).normalized()
				rotation = direction.angle()
				lifetime = 1.0
				return

		pierce_left -= 1
		if pierce_left <= 0:
			queue_free()

func _find_bounce_target(current_target: Node) -> Node2D:
	var space_state = get_world_2d().direct_space_state
	var shape = CircleShape2D.new()
	shape.radius = 260.0
	var query = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = 4
	query.collide_with_areas = true
	var results = space_state.intersect_shape(query, 16)

	var nearest: Node2D = null
	var min_dist: float = 99999.0
	for res in results:
		var col = res.get("collider")
		if col and col.get_parent() and col.get_parent().has_method("take_damage"):
			var target = col.get_parent() as Node2D
			if target == current_target or target.is_in_group("herbs"):
				continue
			var d := global_position.distance_to(target.global_position)
			if d < min_dist:
				min_dist = d
				nearest = target
	return nearest
