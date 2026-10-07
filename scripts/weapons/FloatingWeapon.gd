class_name FloatingWeapon
extends Node2D

enum WeaponType { RANGED, MELEE }

@export var weapon_id: String = "staff"
@export var weapon_name: String = "自制弹弓"
@export var weapon_type: WeaponType = WeaponType.RANGED
@export var base_damage: float = 24.0
@export var attack_cooldown: float = 0.95
@export var attack_range: float = 380.0
@export var level: int = 1

var cooldown_timer: float = 0.0
var slot_offset: Vector2 = Vector2.ZERO
var current_target: Node2D = null
var is_attacking: bool = false
var bob_phase: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var muzzle_point: Marker2D = $Sprite2D/MuzzlePoint
@onready var slash_sprite: Sprite2D = $SlashEffect

var projectile_scene: PackedScene = preload("res://scenes/weapons/BladeProjectile.tscn")

func _ready() -> void:
    slash_sprite.visible = false
    slash_sprite.modulate.a = 0.0
    bob_phase = randf() * TAU
    _update_weapon_visuals()

func _update_weapon_visuals() -> void:
    if weapon_type == WeaponType.RANGED:
        sprite.texture = load("res://assets/art/weapon_staff.png")
        attack_range = 420.0
        attack_cooldown = 0.92
    else:
        sprite.texture = load("res://assets/art/weapon_sword.png")
        attack_range = 145.0
        attack_cooldown = 1.15
        base_damage = 36.0

func _process(delta: float) -> void:
    if GameManager.is_game_over:
        return
        
    cooldown_timer -= delta
    bob_phase += delta * 3.5
    
    # 1. Floating slot positioning with gentle breathing bob
    if not is_attacking:
        var bob_y = sin(bob_phase) * 3.2
        position = position.lerp(slot_offset + Vector2(0, bob_y), delta * 14.0)
    
    # 2. Acquire nearest enemy target within weapon range
    current_target = _find_target()
    
    # 3. Aiming rotation
    if not is_attacking:
        if current_target != null:
            var target_angle = (current_target.global_position - global_position).angle()
            rotation = lerp_angle(rotation, target_angle, delta * 15.0)
        else:
            # Face default outward angle
            var default_angle = slot_offset.angle()
            rotation = lerp_angle(rotation, default_angle, delta * 6.0)
            
        # Flip sprite V if pointing left so weapon is never upside down
        var norm_rot = wrapf(rotation, -PI, PI)
        sprite.flip_v = abs(norm_rot) > PI * 0.5
        
    # 4. Trigger attack if ready
    if cooldown_timer <= 0.0 and current_target != null and not is_attacking:
        _perform_attack()

func _perform_attack() -> void:
    if weapon_type == WeaponType.RANGED:
        _perform_ranged_attack()
    else:
        _perform_melee_attack()

func _perform_ranged_attack() -> void:
    is_attacking = true
    cooldown_timer = attack_cooldown * GameManager.blade_cooldown_mult
    
    var aim_dir = Vector2.RIGHT.rotated(rotation)
    if current_target != null:
        aim_dir = (current_target.global_position - global_position).normalized()
        rotation = aim_dir.angle()
        
    # Staff Recoil Animation (pull back, then spring forward)
    var orig_pos = position
    var recoil_pos = orig_pos - aim_dir * 10.0
    var tw = create_tween()
    tw.tween_property(self, "position", recoil_pos, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    tw.tween_property(self, "position", orig_pos, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    tw.tween_callback(func(): is_attacking = false)
    
    # Spawn Projectiles
    var count = GameManager.blade_count
    var spread = deg_to_rad(14.0)
    var start_angle = -float(count - 1) * 0.5 * spread
    
    for i in range(count):
        var p = projectile_scene.instantiate() as BladeProjectile
        p.global_position = muzzle_point.global_position
        var a = aim_dir.angle() + start_angle + i * spread
        p.direction = Vector2(cos(a), sin(a))
        p.damage = base_damage * GameManager.blade_damage_mult
        get_tree().current_scene.add_child(p)
        
    AudioManager.play_sfx("blade_shoot")

func _perform_melee_attack() -> void:
    is_attacking = true
    cooldown_timer = attack_cooldown * GameManager.blade_cooldown_mult
    
    var aim_dir = Vector2.RIGHT.rotated(rotation)
    if current_target != null:
        aim_dir = (current_target.global_position - global_position).normalized()
        
    var base_angle = aim_dir.angle()
    var orig_pos = position
    var thrust_pos = orig_pos + aim_dir * 28.0
    
    # Sword Lunge & Arc Slash Animation
    var tw = create_tween()
    rotation = base_angle - deg_to_rad(45.0)
    slash_sprite.visible = true
    slash_sprite.modulate.a = 1.0
    slash_sprite.rotation = 0.0
    
    tw.set_parallel(true)
    tw.tween_property(self, "position", thrust_pos, 0.08).set_trans(Tween.TRANS_QUAD)
    tw.tween_property(self, "rotation", base_angle + deg_to_rad(45.0), 0.14).set_trans(Tween.TRANS_QUAD)
    tw.tween_property(slash_sprite, "rotation", deg_to_rad(90.0), 0.14)
    tw.tween_property(slash_sprite, "modulate:a", 0.0, 0.18)
    
    tw.chain().set_parallel(false)
    tw.tween_property(self, "position", orig_pos, 0.12).set_trans(Tween.TRANS_SINE)
    tw.tween_callback(func(): 
        is_attacking = false
        slash_sprite.visible = false
    )
    
    AudioManager.play_sfx("enemy_hit", 1.25)
    
    # Melee Area Damage Cone
    _deal_melee_damage(aim_dir)

func _deal_melee_damage(aim_dir: Vector2) -> void:
    var space_state = get_world_2d().direct_space_state
    var shape = CircleShape2D.new()
    shape.radius = 75.0
    var query = PhysicsShapeQueryParameters2D.new()
    query.shape = shape
    query.transform = Transform2D(0.0, global_position + aim_dir * 30.0)
    query.collision_mask = 4 # Enemies
    query.collide_with_areas = true
    var results = space_state.intersect_shape(query, 24)
    
    for res in results:
        var col = res["collider"]
        if col and col.get_parent() and col.get_parent().has_method("take_damage"):
            var enemy = col.get_parent()
            var dmg = base_damage * GameManager.blade_damage_mult * 1.35
            var is_crit = randf() < 0.25
            if is_crit:
                dmg *= 1.5
            var knock = (enemy.global_position - global_position).normalized() * 240.0
            enemy.take_damage(dmg, knock, is_crit)
            GameManager.shake_camera(3.5, 0.12)

func _find_target() -> Node2D:
    var space_state = get_world_2d().direct_space_state
    var shape = CircleShape2D.new()
    shape.radius = attack_range
    var query = PhysicsShapeQueryParameters2D.new()
    query.shape = shape
    query.transform = Transform2D(0.0, global_position)
    query.collision_mask = 4 # Enemies Area2D
    query.collide_with_areas = true
    var results = space_state.intersect_shape(query, 32)
    
    var nearest: Node2D = null
    var min_dist: float = 999999.0
    for res in results:
        var col = res["collider"]
        if col and col.get_parent() and col.get_parent().has_method("take_damage"):
            var enemy = col.get_parent()
            var d = global_position.distance_to(enemy.global_position)
            if d < min_dist:
                min_dist = d
                nearest = enemy
    return nearest
