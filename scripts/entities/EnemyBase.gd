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
var facing: String = "s"
var anim_base_scale: Vector2 = Vector2.ONE
var juice_scale: Vector2 = Vector2.ONE

@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hit_flash_mat: ShaderMaterial = anim_sprite.material as ShaderMaterial

var gem_scene: PackedScene = preload("res://scenes/entities/AstralGem.tscn")
var gold_gem_tex: Texture2D = preload("res://assets/art/gem_gold.png")
var flash_tween: Tween = null
var squash_tween: Tween = null
var dying: bool = false

func _ready() -> void:
	current_hp = max_hp
	anim_base_scale = anim_sprite.scale
	if spritesheet_path != "" and ResourceLoader.exists(spritesheet_path):
		_setup_frames(spritesheet_path)
	else:
		if anim_sprite.sprite_frames != null and anim_sprite.sprite_frames.has_animation("idle"):
			anim_sprite.play("idle")

	# 妖物出生时的弹性跃出感
	juice_scale = Vector2(0.3, 0.3)
	play_squash(Vector2(1.18, 0.85), 0.22)

func _setup_frames(path: String) -> void:
	var tex = load(path) as Texture2D
	if tex == null:
		return
	var sf = SpriteFrames.new()
	for dir in RunMotion.DIR_ROW:
		var row: int = RunMotion.DIR_ROW[dir]
		sf.add_animation("idle_" + dir)
		sf.set_animation_speed("idle_" + dir, 1.0)
		sf.set_animation_loop("idle_" + dir, true)
		sf.add_frame("idle_" + dir, _cell_tex(tex, 0, row))

		sf.add_animation("run_" + dir)
		sf.set_animation_speed("run_" + dir, 10.0 if not is_elite else 8.5)
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

## 挤压与拉伸形变回弹（Squash & Stretch）
func play_squash(target: Vector2, duration: float = 0.16) -> void:
	if squash_tween != null and squash_tween.is_valid():
		squash_tween.kill()
	juice_scale = target
	squash_tween = create_tween()
	squash_tween.tween_property(self, "juice_scale", Vector2.ONE, duration)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _physics_process(delta: float) -> void:
	if GameManager.is_game_over or dying:
		return

	var player = GameManager.player
	if player == null:
		return

	# 1. 击退速度指数衰减
	if knockback_velocity.length_squared() > 10.0:
		knockback_velocity = knockback_velocity.lerp(Vector2.ZERO, minf(delta * 14.0, 1.0))
	else:
		knockback_velocity = Vector2.ZERO

	# 2. 追击玩家
	var dir = (player.global_position - global_position).normalized()
	velocity = dir * move_speed + knockback_velocity
	move_and_slide()

	# 界碑拦阻
	var lim: float = GameManager.MAP_HALF_EXTENT - 20.0
	global_position = global_position.clamp(Vector2(-lim, -lim), Vector2(lim, lim))

	# 3. Sprite 方向 & 动画（融合 juice_scale）
	if dir.length_squared() > 0.0001:
		var face: Array = RunMotion.facing(dir)
		if face[0] != "":
			facing = face[0]
			anim_sprite.flip_h = face[1]

	var current_base := anim_base_scale * juice_scale
	if anim_sprite.sprite_frames != null and anim_sprite.sprite_frames.has_animation("run_" + facing):
		var run_anim: String = "run_" + facing
		if anim_sprite.animation != run_anim:
			var keep_frame: bool = anim_sprite.animation.begins_with("run_")
			var prev_frame: int = anim_sprite.frame
			var prev_prog: float = anim_sprite.frame_progress
			anim_sprite.play(run_anim)
			if keep_frame:
				anim_sprite.set_frame_and_progress(prev_frame, prev_prog)
		RunMotion.apply(anim_sprite, current_base, true, anim_sprite.flip_h, absf(dir.x), delta)
	else:
		RunMotion.apply(anim_sprite, current_base, false, anim_sprite.flip_h, 0.0, delta)

	# 4. 玩家接触伤害判定
	for i in range(get_slide_collision_count()):
		var col = get_slide_collision(i)
		var collider = col.get_collider()
		if collider is Player:
			collider.take_damage(contact_damage)

func take_damage(amount: float, knockback: Vector2, is_crit: bool = false) -> void:
	if dying:
		return
	current_hp -= amount
	knockback_velocity = knockback * (0.55 if is_elite else 1.0)

	# 1. 声音与跳字
	if is_crit:
		AudioManager.play_sfx("enemy_hit", 1.35, randf_range(1.16, 1.32))
		GameManager.feedback(GameManager.FeedbackTier.MEDIUM)
	else:
		AudioManager.play_sfx("enemy_hit", 1.05 if not is_elite else 0.85)
		GameManager.add_trauma(0.06)

	DamageNumber.spawn(get_parent(), global_position, int(amount), is_crit)

	# 2. 受击定向火花与挤压形变
	JuiceEffect.spawn_hit_sparks(get_parent(), global_position, knockback, is_crit)
	play_squash(Vector2(1.36, 0.70) if is_crit else Vector2(1.24, 0.80), 0.16)

	# 3. 闪白 Shader
	if hit_flash_mat != null:
		if flash_tween != null and flash_tween.is_valid():
			flash_tween.kill()
		flash_tween = create_tween()
		flash_tween.tween_property(hit_flash_mat, ^"shader_parameter/flash_modifier", 1.0, 0.025)
		flash_tween.tween_property(hit_flash_mat, ^"shader_parameter/flash_modifier", 0.0, 0.10)

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

	# 击杀视觉爆散与分级震屏
	JuiceEffect.spawn_death_burst(get_parent(), global_position, is_elite)
	if is_elite:
		GameManager.feedback(GameManager.FeedbackTier.LARGE)
		AudioManager.play_sfx("level_up", 1.05)
	else:
		GameManager.add_trauma(0.09)

	var gem_count = 1 if not is_elite else 5
	for i in range(gem_count):
		var gem = gem_scene.instantiate() as AstralGem
		var offset = Vector2.ZERO if gem_count == 1 else Vector2(randf_range(-24.0, 24.0), randf_range(-24.0, 24.0))
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
	if squash_tween != null and squash_tween.is_valid():
		squash_tween.kill()

	# 死灭动画：先微幅膨胀（Anticipation）再塌缩消散
	var tw = create_tween()
	tw.tween_property(anim_sprite, "scale", anim_base_scale * Vector2(1.28, 1.28), 0.045)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.set_parallel(true)
	tw.tween_property(anim_sprite, "scale", Vector2.ZERO, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(anim_sprite, "modulate:a", 0.0, 0.14)
	tw.chain().tween_callback(queue_free)
