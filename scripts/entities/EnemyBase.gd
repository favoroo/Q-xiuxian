class_name EnemyBase
extends CharacterBody2D

@export var max_hp: float = 40.0
@export var move_speed: float = 110.0
@export var contact_damage: float = 8.0
@export var is_elite: bool = false
@export var exp_reward: int = 1
@export var spritesheet_path: String = ""
# 可选行为（0 = 关闭，场景按怪种配置）
@export var preferred_range: float = 0.0   ## >0：远程怪，保持该距离环绕游走
@export var bolt_interval: float = 0.0     ## >0：每隔 N 秒向玩家发射剑气
@export var bolt_damage: float = 6.0
@export var charge_interval: float = 0.0   ## >0：每隔 N 秒朝玩家突进
@export var explode_radius: float = 0.0    ## >0：贴近玩家 40px 后点燃 0.8s 引信自爆
@export var heal_orb_drop: int = 0         ## >0：死亡掉「残丹」回血珠而非灵石

var current_hp: float = 40.0
var knockback_velocity: Vector2 = Vector2.ZERO
var facing: String = "s"
var anim_base_scale: Vector2 = Vector2.ONE
var juice_scale: Vector2 = Vector2.ONE
var _bolt_timer: float = 1.2
var _charge_timer: float = 0.0
var _charge_active: float = 0.0
var _charge_dir: Vector2 = Vector2.ZERO
var _fuse: float = -1.0   ## >=0 表示引信已点燃
var _no_drop: bool = false

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

	# 2. 追击玩家（平滑加速度 + 贴身防旋转抽搐）
	var to_player: Vector2 = player.global_position - global_position
	var dist_sq: float = to_player.length_squared()
	var dir: Vector2 = to_player.normalized() if dist_sq > 0.0001 else Vector2.ZERO

	# 引入轻微加减速平滑，消除突然转向时的身躯瞬间硬切
	var target_vel := dir * move_speed

	# 远程怪：保持距离，近了退、远了进、合适距离环绕游走
	if preferred_range > 0.0:
		var dist := sqrt(dist_sq)
		if dist < preferred_range - 30.0:
			target_vel = -dir * move_speed * 0.8
		elif dist <= preferred_range + 30.0:
			target_vel = Vector2(-dir.y, dir.x) * move_speed * 0.5

	# 雷兽突进：冷却一到就朝玩家猛冲 0.45s
	if charge_interval > 0.0:
		_charge_timer -= delta
		if _charge_active > 0.0:
			_charge_active -= delta
			target_vel = _charge_dir * move_speed * 3.2
		elif _charge_timer <= 0.0 and dist_sq > 14400.0 and dist_sq < 202500.0:
			_charge_timer = charge_interval
			_charge_active = 0.45
			_charge_dir = dir
			play_squash(Vector2(0.78, 1.24), 0.2)

	# 丹爆傀儡：贴近点燃引信，原地颤抖后自爆
	if explode_radius > 0.0:
		if _fuse < 0.0:
			if dist_sq < 1600.0:
				_fuse = 0.8
				anim_sprite.modulate = Color(2.2, 0.9, 0.6)
				play_squash(Vector2(1.2, 0.82), 0.3)
				AudioManager.play_sfx("orb_hit", 1.3)
		else:
			_fuse -= delta
			target_vel = Vector2.ZERO
			anim_sprite.position.x = randf_range(-1.6, 1.6)
			if _fuse <= 0.0:
				anim_sprite.position.x = 0.0
				_explode(player)
				return

	# 御剑邪修：保持距离的同时周期性发射剑气
	if bolt_interval > 0.0 and _fuse < 0.0:
		_bolt_timer -= delta
		if _bolt_timer <= 0.0 and dist_sq < 396900.0:
			_bolt_timer = bolt_interval
			_fire_bolt(player)

	velocity = velocity.move_toward(target_vel, 900.0 * delta) + knockback_velocity
	move_and_slide()

	# 界碑拦阻
	var lim: float = GameManager.MAP_HALF_EXTENT - 20.0
	global_position = global_position.clamp(Vector2(-lim, -lim), Vector2(lim, lim))

	# 3. Sprite 方向 & 动画（带迟滞滤波 + 贴近锁定 + 移速步频自适应）
	# 当怪物与玩家极度贴近（小于 18px）时锁定原有朝向，避免围绕玩家中心旋转时的抽风风扇效应
	if dist_sq > 324.0 and dir.length_squared() > 0.01:
		var face: Array = RunMotion.facing_stable(dir, facing, anim_sprite.flip_h, 32.0)
		if face[0] != "":
			facing = face[0]
			anim_sprite.flip_h = face[1]

	var current_base := anim_base_scale * juice_scale
	var current_speed := velocity.length()
	var speed_ratio: float = (current_speed / move_speed) if move_speed > 0.0 else 1.0

	if anim_sprite.sprite_frames != null and anim_sprite.sprite_frames.has_animation("run_" + facing):
		var run_anim: String = "run_" + facing
		if anim_sprite.animation != run_anim:
			var keep_frame: bool = anim_sprite.animation.begins_with("run_")
			var prev_frame: int = anim_sprite.frame
			var prev_prog: float = anim_sprite.frame_progress
			anim_sprite.play(run_anim)
			if keep_frame:
				anim_sprite.set_frame_and_progress(prev_frame, prev_prog)
		RunMotion.apply(anim_sprite, current_base, true, anim_sprite.flip_h, absf(dir.x), delta, speed_ratio)
	else:
		RunMotion.apply(anim_sprite, current_base, false, anim_sprite.flip_h, 0.0, delta)

	# 4. 玩家接触伤害判定
	for i in range(get_slide_collision_count()):
		var col = get_slide_collision(i)
		var collider = col.get_collider()
		if collider is Player:
			var hp_before: float = collider.current_health
			collider.take_damage(contact_damage)
			# 石岳反震：实际被打中才反弹（闪避/无敌帧不触发）
			if GameManager.thorns_pct > 0.0 and collider.current_health < hp_before:
				take_damage(contact_damage * GameManager.thorns_pct, Vector2.ZERO, false)

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

## 自爆结算：范围内伤玩家，不掉落、不计击杀奖励
func _explode(player: Node2D) -> void:
	if dying:
		return
	JuiceEffect.spawn_death_burst(get_parent(), global_position, true)
	GameManager.feedback(GameManager.FeedbackTier.MEDIUM)
	AudioManager.play_sfx("obelisk_blessing", 0.5)
	if player.global_position.distance_to(global_position) <= explode_radius:
		player.take_damage(contact_damage * 2.0)
	_no_drop = true
	_die()

## 发射剑气弹（御剑邪修）
func _fire_bolt(player: Node2D) -> void:
	var bolt := EnemyBolt.new()
	bolt.global_position = global_position
	bolt.direction = (player.global_position - global_position).normalized()
	bolt.damage = bolt_damage * (contact_damage / 8.0)  # 随波次缩放比例与接触伤害一致
	get_parent().add_child(bolt)
	play_squash(Vector2(1.16, 0.84), 0.16)
	AudioManager.play_sfx("blade_shoot", 0.6)

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
	if _no_drop:
		gem_count = 0
	if heal_orb_drop > 0 and gem_count > 0:
		gem_count = 0
		var orb := HealOrb.new()
		orb.global_position = global_position
		orb.heal_amount = float(heal_orb_drop)
		get_parent().call_deferred("add_child", orb)
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
