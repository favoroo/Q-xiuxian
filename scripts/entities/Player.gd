class_name Player
extends CharacterBody2D

@export var max_health: float = 120.0
var current_health: float = 120.0
var base_speed: float = 210.0
var invulnerable_time: float = 0.0

@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var sun_orb_container: Node2D = $SunOrbContainer
@onready var weapon_holder: Node2D = $WeaponHolder
@onready var pickup_area: Area2D = $PickupArea
@onready var hit_flash_mat: ShaderMaterial = anim_sprite.material as ShaderMaterial

var sun_orb_angle: float = 0.0
var floating_weapon_scene: PackedScene = preload("res://scenes/weapons/FloatingWeapon.tscn")
var sun_orb_scene: PackedScene = preload("res://scenes/weapons/SunOrb.tscn")

var equipped_weapons: Array[FloatingWeapon] = []

func _ready() -> void:
    current_health = max_health
    GameManager.player = self
    GameManager.player_hp_changed.emit(current_health, max_health)
    _setup_sprite_frames()
    _init_default_weapons()
    _sync_sun_orbs()

func _setup_sprite_frames() -> void:
    var base_tex = load("res://assets/art/pawn_blue.png") as Texture2D
        
    var sf = SpriteFrames.new()
    # 1. Idle (Row 0, 6 frames)
    sf.add_animation("idle")
    sf.set_animation_speed("idle", 8.0)
    sf.set_animation_loop("idle", true)
    for c in range(6):
        var at = AtlasTexture.new()
        at.atlas = base_tex
        at.region = Rect2(c * 192, 0, 192, 192)
        sf.add_frame("idle", at)
        
    # 2. Run (Row 1, 6 frames)
    sf.add_animation("run")
    sf.set_animation_speed("run", 11.0)
    sf.set_animation_loop("run", true)
    for c in range(6):
        var at = AtlasTexture.new()
        at.atlas = base_tex
        at.region = Rect2(c * 192, 192, 192, 192)
        sf.add_frame("run", at)
        
    anim_sprite.sprite_frames = sf
    anim_sprite.play("idle")

func _init_default_weapons() -> void:
    # Start with 1 Floating Arcane Staff
    add_floating_weapon("staff", FloatingWeapon.WeaponType.RANGED, "自制弹弓")

func add_floating_weapon(w_id: String, w_type: int, w_name: String) -> void:
    var weapon = floating_weapon_scene.instantiate() as FloatingWeapon
    weapon.weapon_id = w_id
    weapon.weapon_type = w_type as FloatingWeapon.WeaponType
    weapon.weapon_name = w_name
    weapon_holder.add_child(weapon)
    equipped_weapons.append(weapon)
    _recalculate_weapon_slots()
    GameManager.notify_weapons_updated(get_equipped_weapons_data())

func _recalculate_weapon_slots() -> void:
    var count = equipped_weapons.size()
    if count == 0:
        return
        
    var radius_x = 56.0
    var radius_y = 40.0
    for i in range(count):
        var w = equipped_weapons[i]
        var angle = float(i) * (TAU / float(count))
        w.slot_offset = Vector2(cos(angle) * radius_x, sin(angle) * radius_y)

func get_equipped_weapons_data() -> Array[Dictionary]:
    var list: Array[Dictionary] = []
    for w in equipped_weapons:
        list.append({
            "id": w.weapon_id,
            "name": w.weapon_name,
            "type": w.weapon_type,
            "level": w.level,
            "icon": "res://assets/art/weapon_staff.png" if w.weapon_type == FloatingWeapon.WeaponType.RANGED else "res://assets/art/weapon_sword.png"
        })
    return list

func _physics_process(delta: float) -> void:
    if GameManager.is_game_over:
        return
        
    if invulnerable_time > 0.0:
        invulnerable_time -= delta
        anim_sprite.modulate.a = 0.55 if fmod(invulnerable_time, 0.12) > 0.06 else 1.0
    else:
        anim_sprite.modulate.a = 1.0

    # 1. Movement input
    var dir = Vector2.ZERO
    if GameManager.joystick != null and GameManager.joystick.has_method("get_direction"):
        dir = GameManager.joystick.get_direction()
    else:
        dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
    
    var speed = base_speed * GameManager.move_speed_mult
    velocity = dir * speed
    move_and_slide()
    
    # 2. Sprite Flip & Animation
    if dir.x > 0.05:
        anim_sprite.flip_h = false
    elif dir.x < -0.05:
        anim_sprite.flip_h = true
        
    if dir.length_squared() > 0.04:
        if anim_sprite.animation != "run":
            anim_sprite.play("run")
    else:
        if anim_sprite.animation != "idle":
            anim_sprite.play("idle")

    # 3. Pickup Area & Orbit Items
    pickup_area.scale = Vector2.ONE * GameManager.pickup_range_mult
    _process_sun_orbs(delta)

func _process_sun_orbs(delta: float) -> void:
    _sync_sun_orbs()
    sun_orb_angle += delta * 2.8
    var count = sun_orb_container.get_child_count()
    if count == 0:
        return
    var radius = 72.0
    for i in range(count):
        var orb = sun_orb_container.get_child(i) as Node2D
        var a = sun_orb_angle + float(i) * (TAU / float(count))
        orb.position = Vector2(cos(a), sin(a)) * radius

func _sync_sun_orbs() -> void:
    var target_count = GameManager.sun_orb_count
    var current_count = sun_orb_container.get_child_count()
    if current_count < target_count:
        for i in range(target_count - current_count):
            var orb = sun_orb_scene.instantiate()
            sun_orb_container.add_child(orb)
    elif current_count > target_count:
        for i in range(current_count - target_count):
            sun_orb_container.get_child(0).queue_free()

func take_damage(amount: float) -> void:
    if invulnerable_time > 0.0 or GameManager.is_game_over:
        return
        
    current_health = maxf(0.0, current_health - amount)
    invulnerable_time = 0.55
    GameManager.player_hp_changed.emit(current_health, max_health)
    GameManager.shake_camera(5.0, 0.2)
    AudioManager.play_sfx("enemy_hit", 0.8)
    
    if hit_flash_mat != null:
        var tw = create_tween()
        tw.tween_property(hit_flash_mat, "shader_parameter/flash_modifier", 1.0, 0.03)
        tw.tween_property(hit_flash_mat, "shader_parameter/flash_modifier", 0.0, 0.1)
        
    DamageNumber.spawn(get_parent(), global_position, int(amount), false)
    
    if current_health <= 0.0:
        GameManager.trigger_game_over(false)

func increase_max_hp(amount: float, heal_amount: float) -> void:
    max_health += amount
    current_health = minf(max_health, current_health + heal_amount)
    GameManager.player_hp_changed.emit(current_health, max_health)
    DamageNumber.spawn(get_parent(), global_position, int(heal_amount), false, "+" + str(int(heal_amount)) + " HP")

func _on_pickup_area_area_entered(area: Area2D) -> void:
    if area.has_method("magnet_to"):
        area.magnet_to(self)
    elif area.get_parent() and area.get_parent().has_method("magnet_to"):
        area.get_parent().magnet_to(self)
