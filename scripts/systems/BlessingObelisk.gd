class_name BlessingObelisk
extends Node2D

## 聚灵阵 — 玩家主动长按激活的阵法节点。
## 玩家进入范围后 HUD 显示激活按钮，长按充能，松手前完成则触发全屏灵气冲击；
## 松手过早或离开范围则中断充能、进度归零。

## 充能时长（秒）—— 比旧版 3s 短，手感更利落
const CHARGE_TIME: float = 1.5
## 触发伤害
const BLESSING_DAMAGE: float = 85.0
## 击退力度
const KNOCK_FORCE: float = 320.0
## 掉落金色灵石数量
const GEM_COUNT: int = 5

## 与 HUD 通信的信号
signal activation_available(obelisk: BlessingObelisk)
signal activation_unavailable(obelisk: BlessingObelisk)
signal charge_started(obelisk: BlessingObelisk)
signal charge_progress_updated(obelisk: BlessingObelisk, ratio: float)
signal charge_cancelled(obelisk: BlessingObelisk)
signal blessing_triggered(obelisk: BlessingObelisk)

var is_player_inside: bool = false
var is_charging: bool = false
var is_triggered: bool = false
var charge_time: float = 0.0

@onready var light: PointLight2D = $PointLight2D
@onready var circle_sprite: Node2D = $ChargeCircle
@onready var interaction_area: Area2D = $InteractionArea

var gem_scene: PackedScene = preload("res://scenes/entities/AstralGem.tscn")
var gold_gem_tex: Texture2D = preload("res://assets/art/gem_gold.png")

## 充能期间的粒子效果 —— 灵气汇聚
var _charge_particles: CPUParticles2D = null

func _ready() -> void:
	light.energy = 1.2
	circle_sprite.rotation = 0.0
	_setup_charge_particles()

func _setup_charge_particles() -> void:
	_charge_particles = CPUParticles2D.new()
	_charge_particles.emitting = false
	_charge_particles.amount = 12
	_charge_particles.lifetime = 0.8
	_charge_particles.explosiveness = 0.0
	_charge_particles.direction = Vector2(0, -1)
	_charge_particles.spread = 180.0
	_charge_particles.gravity = Vector2(0, -30)
	_charge_particles.initial_velocity_min = 20.0
	_charge_particles.initial_velocity_max = 40.0
	_charge_particles.angular_velocity_min = -60.0
	_charge_particles.angular_velocity_max = 60.0
	_charge_particles.scale_amount_min = 1.0
	_charge_particles.scale_amount_max = 2.5
	_charge_particles.color = Color(0.45, 0.85, 1.0, 0.6)
	_charge_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RING
	_charge_particles.emission_ring_radius = 50.0
	_charge_particles.emission_ring_inner_radius = 0.0
	add_child(_charge_particles)

func _process(delta: float) -> void:
	if is_triggered:
		return
	if is_charging:
		charge_time = minf(CHARGE_TIME, charge_time + delta)
		var ratio: float = charge_time / CHARGE_TIME
		charge_progress_updated.emit(self, ratio)
		# 充能视觉反馈：光能随进度提升
		light.energy = 1.2 + ratio * 2.3
		# 灵符环旋转加速 —— 充能越快转越急
		circle_sprite.rotation += delta * (1.8 + ratio * 5.0)
		if charge_time >= CHARGE_TIME:
			_trigger_blessing()

## HUD 调用：玩家按下激活按钮
func start_charge() -> void:
	if is_triggered or not is_player_inside:
		return
	is_charging = true
	charge_time = 0.0
	charge_started.emit(self)
	if _charge_particles != null:
		_charge_particles.emitting = true

## HUD 调用：玩家松开激活按钮
func stop_charge() -> void:
	if not is_charging:
		return
	is_charging = false
	if _charge_particles != null:
		_charge_particles.emitting = false
	if charge_time < CHARGE_TIME:
		# 未完成 → 取消，进度归零
		charge_time = 0.0
		light.energy = 1.2
		circle_sprite.rotation = 0.0
		charge_cancelled.emit(self)

func _trigger_blessing() -> void:
	is_triggered = true
	is_charging = false
	if _charge_particles != null:
		_charge_particles.emitting = false
	blessing_triggered.emit(self)
	AudioManager.play_sfx("obelisk_blessing")
	GameManager.feedback(GameManager.FeedbackTier.HEAVY)
	JuiceEffect.spawn_death_burst(get_parent(), global_position, true)
	GameManager.announcement_triggered.emit("⚡ 护山大阵启动 · 灵气荡涤四方 ⚡")
	_spawn_shockwave_ring()
	# 对范围内所有敌人造成伤害与击退
	# 方向走 GameBalance.knock_dir（永不把敌人往玩家身上推）
	var enemies = get_tree().get_nodes_in_group("enemies")
	var player_pos: Vector2 = global_position if GameManager.player == null else GameManager.player.global_position
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.has_method("take_damage"):
			var knock = GameBalance.knock_dir(global_position, enemy.global_position, player_pos) * KNOCK_FORCE
			enemy.take_damage(BLESSING_DAMAGE, knock, true)
	# 掉落金色灵石
	for i in range(GEM_COUNT):
		var gem = gem_scene.instantiate() as AstralGem
		var offset = Vector2(randf_range(-40.0, 40.0), randf_range(-40.0, 40.0))
		gem.global_position = global_position + offset
		gem.is_gold = true
		gem.exp_value = 10
		gem.get_node("Sprite2D").texture = gold_gem_tex
		gem.get_node("PointLight2D").color = Color(1.0, 0.85, 0.35)
		get_parent().call_deferred("add_child", gem)
	# 触发视觉：光能爆闪 + 灵符环淡出
	var tw = create_tween()
	tw.tween_property(light, "energy", 5.0, 0.12)
	tw.tween_property(light, "energy", 0.8, 0.5)
	tw.parallel().tween_property(circle_sprite, "modulate:a", 0.15, 0.4)

## 触发时的扩散灵气环 —— 视觉冲击
func _spawn_shockwave_ring() -> void:
	var ring := Sprite2D.new()
	ring.texture = circle_sprite.get_node("RingSprite").texture
	ring.modulate = Color(0.45, 0.85, 1.0, 0.7)
	ring.scale = Vector2(0.5, 0.5)
	ring.z_index = 10
	get_parent().add_child(ring)
	ring.global_position = global_position
	var tw = create_tween()
	tw.tween_property(ring, "scale", Vector2(6.0, 6.0), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(ring, "modulate:a", 0.0, 0.45)
	tw.tween_callback(ring.queue_free)

func _on_interaction_area_body_entered(body: Node2D) -> void:
	if body is Player and not is_triggered:
		is_player_inside = true
		activation_available.emit(self)

func _on_interaction_area_body_exited(body: Node2D) -> void:
	if body is Player:
		if is_charging:
			stop_charge()
		is_player_inside = false
		if not is_triggered:
			activation_unavailable.emit(self)
