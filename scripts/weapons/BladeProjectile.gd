class_name BladeProjectile
extends Area2D

## 法器弹丸：伤害由 FloatingWeapon 计算好后直接传入

var direction: Vector2 = Vector2.RIGHT
var speed: float = 470.0
var damage: float = 20.0
var lifetime: float = 1.6
var pierce_left: int = 1
var spin: bool = true

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
    rotation = direction.angle()
    if spin:
        var tw = create_tween().set_loops()
        tw.tween_property(sprite, "rotation", TAU, 0.45).as_relative()

func _physics_process(delta: float) -> void:
    position += direction * speed * delta
    lifetime -= delta
    if lifetime <= 0.0:
        queue_free()

func _on_area_entered(area: Area2D) -> void:
    var enemy = area.get_parent()
    if enemy and enemy.has_method("take_damage"):
        var is_crit = randf() < 0.2
        var actual_dmg = damage * (1.5 if is_crit else 1.0)
        enemy.take_damage(actual_dmg, direction * 120.0, is_crit)

        pierce_left -= 1
        if pierce_left <= 0:
            queue_free()
