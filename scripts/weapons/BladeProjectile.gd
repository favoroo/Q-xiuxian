class_name BladeProjectile
extends Area2D

var direction: Vector2 = Vector2.RIGHT
var speed: float = 460.0
var damage: float = 24.0
var lifetime: float = 1.6
var pierce_left: int = 1

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
    rotation = direction.angle()
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
        var actual_dmg = damage * GameManager.blade_damage_mult
        var is_crit = randf() < 0.2
        if is_crit:
            actual_dmg *= 1.5
        
        enemy.take_damage(actual_dmg, direction * 120.0, is_crit)
        
        # Radiance Synergy explosion
        if GameManager.has_radiance_synergy and randf() < 0.28:
            _trigger_radiance_burst(global_position)
        
        pierce_left -= 1
        if pierce_left <= 0:
            queue_free()

func _trigger_radiance_burst(burst_pos: Vector2) -> void:
    DamageNumber.spawn(get_parent(), burst_pos, 0, true, "过载冲击!")
    GameManager.shake_camera(4.5, 0.15)
    AudioManager.play_sfx("orb_hit", 1.2)
    # Area damage nearby
    var space_state = get_world_2d().direct_space_state
    var shape = CircleShape2D.new()
    shape.radius = 65.0
    var query = PhysicsShapeQueryParameters2D.new()
    query.shape = shape
    query.transform = Transform2D(0.0, burst_pos)
    query.collision_mask = 4 # Enemies
    query.collide_with_areas = true
    var results = space_state.intersect_shape(query, 16)
    for res in results:
        var col_area = res["collider"]
        if col_area and col_area.get_parent() and col_area.get_parent().has_method("take_damage"):
            col_area.get_parent().take_damage(damage * 0.85, (col_area.global_position - burst_pos).normalized() * 150.0, true)
