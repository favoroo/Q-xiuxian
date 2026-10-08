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
var facing: String = "s"  # 当前朝向（5 基准方向后缀，左系由 flip_h 表达）
var anim_base_scale: Vector2 = Vector2.ONE

@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hit_flash_mat: ShaderMaterial = anim_sprite.material as ShaderMaterial

var gem_scene: PackedScene = preload("res://scenes/entities/AstralGem.tscn")
var gold_gem_tex: Texture2D = preload("res://assets/art/gem_gold.png")
var flash_tween: Tween = null
var dying: bool = false

func _ready() -> void:
    current_hp = max_hp
    anim_base_scale = anim_sprite.scale
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
    # 5 个基准方向（左/左下/左上由 flip_h 补齐）：idle_<dir> 单帧 + run_<dir> 4 帧
    for dir in RunMotion.DIR_ROW:
        var row: int = RunMotion.DIR_ROW[dir]
        sf.add_animation("idle_" + dir)
        sf.set_animation_speed("idle_" + dir, 1.0)
        sf.set_animation_loop("idle_" + dir, true)
        sf.add_frame("idle_" + dir, _cell_tex(tex, 0, row))

        sf.add_animation("run_" + dir)
        sf.set_animation_speed("run_" + dir, 7.0 if not is_elite else 6.0)
        sf.set_animation_loop("run_" + dir, true)
        for c in range(1, 5):
            sf.add_frame("run_" + dir, _cell_tex(tex, c, row))

    anim_sprite.sprite_frames = sf
    anim_sprite.play("run_s")

func _cell_tex(tex: Texture2D, col: int, row: int) -> AtlasTexture:
    var at = AtlasTexture.new()
    at.atlas = tex
    at.region = Rect2(col * 192, row * 192, 192, 192)
    return at

func _physics_process(delta: float) -> void:
    if GameManager.is_game_over or dying:
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

    # 界碑拦阻：妖物同样不得越过灵田边界（被击退时尤其需要兜底）
    var lim: float = GameManager.MAP_HALF_EXTENT - 20.0
    global_position = global_position.clamp(Vector2(-lim, -lim), Vector2(lim, lim))

    # 3. Sprite 方向 & 动画（8 方向奔跑：5 基准方向 + flip_h，节奏动画见 RunMotion）
    if dir.length_squared() > 0.0001:
        var face: Array = RunMotion.facing(dir)
        if face[0] != "":
            facing = face[0]
            anim_sprite.flip_h = face[1]

    if anim_sprite.sprite_frames != null and anim_sprite.sprite_frames.has_animation("run_" + facing):
        var run_anim: String = "run_" + facing
        if anim_sprite.animation != run_anim:
            anim_sprite.play(run_anim)
        RunMotion.apply(anim_sprite, anim_base_scale, true, anim_sprite.flip_h, absf(dir.x), delta)
    else:
        anim_sprite.offset.y = sin(Time.get_ticks_msec() / 1000.0 * 2.0 + float(get_instance_id() % 97)) * 1.6
        RunMotion.apply(anim_sprite, anim_base_scale, false, anim_sprite.flip_h, 0.0, delta)

    # Check player contact damage
    for i in range(get_slide_collision_count()):
        var col = get_slide_collision(i)
        var collider = col.get_collider()
        if collider is Player:
            collider.take_damage(contact_damage)

func take_damage(amount: float, knockback: Vector2, is_crit: bool = false) -> void:
    if dying:
        return
    current_hp -= amount
    knockback_velocity = knockback

    AudioManager.play_sfx("enemy_hit", 1.1 if not is_elite else 0.85)
    DamageNumber.spawn(get_parent(), global_position, int(amount), is_crit)

    # 闪白节流：旧 tween 先杀，避免高频命中时 flash 参数抖动（精英怪"一直闪"的根因）
    if hit_flash_mat != null:
        if flash_tween != null and flash_tween.is_valid():
            flash_tween.kill()
        flash_tween = create_tween()
        flash_tween.tween_property(hit_flash_mat, "shader_parameter/flash_modifier", 1.0, 0.03)
        flash_tween.tween_property(hit_flash_mat, "shader_parameter/flash_modifier", 0.0, 0.1)

    if current_hp <= 0.0:
        _die()

## 波次结束时的消散：不掉落、不计数
func dissolve() -> void:
    if dying:
        return
    dying = true
    set_physics_process(false)
    $CollisionShape2D.set_deferred("disabled", true)
    $Hurtbox/CollisionShape2D.set_deferred("disabled", true)
    var tw = create_tween()
    tw.set_parallel(true)
    tw.tween_property(anim_sprite, "modulate:a", 0.0, 0.4)
    tw.tween_property(anim_sprite, "scale", anim_sprite.scale * 0.6, 0.4)
    tw.chain().tween_callback(queue_free)

func _die() -> void:
    if dying:
        return
    dying = true
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
