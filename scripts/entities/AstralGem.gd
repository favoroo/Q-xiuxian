class_name AstralGem
extends Area2D

@export var exp_value: int = 1
@export var is_gold: bool = false

var target_player: Node2D = null
var current_speed: float = 80.0
var max_speed: float = 620.0
var acceleration: float = 750.0

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
    add_to_group("gems")
    # Gentle idle floating bobbing
    var tw = create_tween().set_loops()
    tw.tween_property(sprite, "position:y", -3.0, 0.45).set_trans(Tween.TRANS_SINE)
    tw.tween_property(sprite, "position:y", 3.0, 0.45).set_trans(Tween.TRANS_SINE)

func magnet_to(player: Node2D) -> void:
    target_player = player

func _physics_process(delta: float) -> void:
    if target_player != null:
        var dir = (target_player.global_position - global_position).normalized()
        var dist = global_position.distance_to(target_player.global_position)
        current_speed = minf(max_speed, current_speed + acceleration * delta)
        global_position += dir * current_speed * delta
        
        if dist < 18.0:
            GameManager.add_experience(exp_value)
            queue_free()
