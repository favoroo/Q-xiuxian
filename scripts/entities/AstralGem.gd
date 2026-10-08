class_name AstralGem
extends Area2D

@export var exp_value: int = 1
@export var is_gold: bool = false

var target_player: Node2D = null
var current_speed: float = -40.0   # 初始微反冲：有被吸附瞬间的弹性缓冲
var max_speed: float = 680.0
var acceleration: float = 850.0

@onready var sprite: Sprite2D = $Sprite2D
var _bob_tween: Tween = null

func _ready() -> void:
	add_to_group("gems")
	_bob_tween = create_tween().set_loops()
	_bob_tween.tween_property(sprite, "position:y", -3.0, 0.45).set_trans(Tween.TRANS_SINE)
	_bob_tween.tween_property(sprite, "position:y", 3.0, 0.45).set_trans(Tween.TRANS_SINE)

func magnet_to(player: Node2D) -> void:
	if target_player == null:
		target_player = player
		current_speed = -50.0
		if _bob_tween != null and _bob_tween.is_valid():
			_bob_tween.kill()

func _physics_process(delta: float) -> void:
	if target_player != null and is_instance_valid(target_player):
		var dir = (target_player.global_position - global_position).normalized()
		var dist = global_position.distance_to(target_player.global_position)
		current_speed = minf(max_speed, current_speed + acceleration * delta)
		global_position += dir * current_speed * delta

		if dist < 22.0:
			JuiceEffect.spawn_pickup_pop(get_parent(), global_position, is_gold)
			if target_player.has_method("play_squash"):
				target_player.play_squash(Vector2(0.96, 1.05), 0.12)
			GameManager.add_experience(exp_value)
			queue_free()
