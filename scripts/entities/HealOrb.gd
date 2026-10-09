class_name HealOrb
extends Area2D

## 残丹/回春葫芦：可被摄灵术吸附的回复珠，飞抵玩家时恢复气血
## 纯代码构建，无需场景文件；加入 gems 组，波末清场一并吸附

var heal_amount: float = 3.0
var heal_pct: float = 0.0   ## >0 时按玩家气血上限百分比恢复（回春葫芦用）

var target_player: Node2D = null
var current_speed: float = -40.0
var max_speed: float = 680.0
var acceleration: float = 850.0

var _sprite: Sprite2D
var _bob_tween: Tween = null

func _ready() -> void:
	add_to_group("gems")
	collision_layer = 16  # loot
	collision_mask = 0
	monitoring = false
	monitorable = true

	_sprite = Sprite2D.new()
	_sprite.texture = load("res://assets/art/icon_hp.png")
	_sprite.modulate = Color(0.65, 1.35, 0.7)
	_sprite.scale = Vector2(0.36, 0.36)
	add_child(_sprite)

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 18.0
	shape.shape = circle
	add_child(shape)

	_bob_tween = create_tween().set_loops()
	_bob_tween.tween_property(_sprite, "position:y", -3.0, 0.45).set_trans(Tween.TRANS_SINE)
	_bob_tween.tween_property(_sprite, "position:y", 3.0, 0.45).set_trans(Tween.TRANS_SINE)

func magnet_to(player: Node2D) -> void:
	if target_player == null:
		target_player = player
		current_speed = -50.0
		if _bob_tween != null and _bob_tween.is_valid():
			_bob_tween.kill()

func _physics_process(delta: float) -> void:
	if target_player != null and is_instance_valid(target_player):
		var dir: Vector2 = (target_player.global_position - global_position).normalized()
		var dist := global_position.distance_to(target_player.global_position)
		current_speed = minf(max_speed, current_speed + acceleration * delta)
		global_position += dir * current_speed * delta

		if dist < 22.0:
			JuiceEffect.spawn_pickup_pop(get_parent(), global_position, false)
			var amount := heal_amount
			if heal_pct > 0.0 and target_player is Player:
				amount = target_player.max_health * heal_pct
			if target_player.has_method("heal"):
				target_player.heal(amount)
			AudioManager.play_sfx("gem_pickup", 1.2)
			queue_free()
