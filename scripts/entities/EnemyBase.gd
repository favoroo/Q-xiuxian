class_name EnemyBase
extends CharacterBody2D

@export var max_hp: float = 40.0
@export var move_speed: float = 110.0
@export var contact_damage: float = 8.0
@export var is_elite: bool = false
@export var exp_reward: int = 1
@export var spritesheet_path: String = ""

var current_hp: float = 40.0
var knockback_velocity: Vector2 = Vector2.ZERO

@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hit_flash_mat: ShaderMaterial = anim_sprite.material as ShaderMaterial

var gem_scene: PackedScene = preload("res://scenes/entities/AstralGem.tscn")
var gold_gem_tex: Texture2D = preload("res://assets/art/gem_gold.png")

func _ready() -> void:
    current_hp = max_hp
    if spritesheet_path != "" and ResourceLoader.exists(spritesheet_path):
        _setup_frames(spritesheet_path)
    else:
        if anim_sprite.sprite_frames != null and anim_sprite.sprite_frames.has_animation("idle"):
            anim_sprite.play("idle")

func _setup_frames(path: String) -> void:
    var tex = load(path) as Texture2D
    if tex == null:
        return
    var sf = SpriteFrames.new()
    # Idle (Row 0, 6 frames)
    sf.add_animation("idle")
    sf.set_animation_speed("idle", 8.0)
    sf.set_animation_loop("idle", true)
    for c in range(6):
        var at = AtlasTexture.new()
        at.atlas = tex
        at.region = Rect2(c * 192, 0, 192, 192)
        sf.add_frame("idle", at)
        
    # Run (Row 1, 6 frames)
    sf.add_animation("run")
    sf.set_animation_speed("run", 10.0 if not is_elite else 8.0)
    sf.set_animation_loop("run", true)
    for c in range(6):
        var at = AtlasTexture.new()
        at.atlas = tex
        at.region = Rect2(c * 192, 192, 192, 192)
        sf.add_frame("run", at)
        
    anim_sprite.sprite_frames = sf
    anim_sprite.play("run")

func _physics_process(delta: float) -> void:
    if GameManager.is_game_over:
        return
        
    var player = GameManager.player
    if player == null:
        return
        
    # 1. Knockback decay
    if knockback_velocity.length_squared() > 10.0:
        knockback_velocity = knockback_velocity.lerp(Vector2.ZERO, delta * 14.0)
    else:
        knockback_velocity = Vector2.ZERO
        
    # 2. Track player
    var dir = (player.global_position - global_position).normalized()
    velocity = dir * move_speed + knockback_velocity
    move_and_slide()
    
    # 3. Sprite animation & flip
    if dir.x > 0.05:
        anim_sprite.flip_h = false
    elif dir.x < -0.05:
        anim_sprite.flip_h = true
        
    if anim_sprite.sprite_frames != null and anim_sprite.sprite_frames.has_animation("run"):
        if anim_sprite.animation != "run":
            anim_sprite.play("run")
            
    # Check player contact damage
    for i in range(get_slide_collision_count()):
        var col = get_slide_collision(i)
        var collider = col.get_collider()
        if collider is Player:
            collider.take_damage(contact_damage)

func take_damage(amount: float, knockback: Vector2, is_crit: bool = false) -> void:
    current_hp -= amount
    knockback_velocity = knockback
    
    AudioManager.play_sfx("enemy_hit", 1.1 if not is_elite else 0.85)
    DamageNumber.spawn(get_parent(), global_position, int(amount), is_crit)
    
    if hit_flash_mat != null:
        var tw = create_tween()
        tw.tween_property(hit_flash_mat, "shader_parameter/flash_modifier", 1.0, 0.03)
        tw.tween_property(hit_flash_mat, "shader_parameter/flash_modifier", 0.0, 0.1)
    
    if current_hp <= 0.0:
        _die()

func _die() -> void:
    GameManager.register_kill(is_elite)
    
    var gem_count = 1 if not is_elite else 5
    for i in range(gem_count):
        var gem = gem_scene.instantiate() as AstralGem
        var offset = Vector2.ZERO if gem_count == 1 else Vector2(randf_range(-20.0, 20.0), randf_range(-20.0, 20.0))
        gem.global_position = global_position + offset
        gem.exp_value = exp_reward
        if is_elite:
            gem.is_gold = true
            gem.exp_value = 8
            gem.get_node("Sprite2D").texture = gold_gem_tex
            gem.get_node("PointLight2D").color = Color(1.0, 0.82, 0.35)
        get_parent().call_deferred("add_child", gem)
        
    set_physics_process(false)
    $CollisionShape2D.set_deferred("disabled", true)
    $Hurtbox/CollisionShape2D.set_deferred("disabled", true)
    
    var tw = create_tween()
    tw.set_parallel(true)
    tw.tween_property(anim_sprite, "scale", Vector2.ZERO, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
    tw.tween_property(anim_sprite, "modulate:a", 0.0, 0.16)
    tw.chain().tween_callback(queue_free)
