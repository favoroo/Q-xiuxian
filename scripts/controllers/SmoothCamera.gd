class_name SmoothCamera
extends Camera2D

@export var follow_speed: float = 7.5
var shake_intensity: float = 0.0
var shake_timer: float = 0.0

func _ready() -> void:
    GameManager.main_camera = self

func _physics_process(delta: float) -> void:
    var player = GameManager.player
    if player != null:
        global_position = global_position.lerp(player.global_position, delta * follow_speed)
        
    if shake_timer > 0.0:
        shake_timer -= delta
        var offset_x = randf_range(-shake_intensity, shake_intensity)
        var offset_y = randf_range(-shake_intensity, shake_intensity)
        offset = Vector2(offset_x, offset_y)
    else:
        offset = Vector2.ZERO

func shake(intensity: float = 4.0, duration: float = 0.15) -> void:
    shake_intensity = intensity
    shake_timer = duration
