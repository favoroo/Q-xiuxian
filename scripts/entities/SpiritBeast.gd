class_name SpiritBeast
extends CharacterBody2D

## 祭坛灵兽（2026-10-11 远程吐息重做）：祭坛激活时召唤的风筝型远程友军。
##
## 组与碰撞（两条铁律，动了会被全场武器追着打 / 波末被清场）：
##   - 只挂 "allies" 组 —— 绝不进 enemies/turrets/gems/chests，那四组 WaveSpawner.end_wave 全清；
##     正因为它不在那四组里，血量不耗尽就跨波次一直在场。
##   - 本体 collision_layer/mask 全 0：与敌人无任何物理碰撞体积（旧版挂 player 层会被敌人
##     move_and_slide 双向推挤，「撞着敌人跑」）；玩家武器索敌全走 mask=4（enemies 层），
##     也打不到它。移动直接积分 global_position，不走 move_and_slide。
##
## 行为：嘲讽（EnemyBase 走 live_allies 登记表，与碰撞无关，仍然生效）引怪后风筝——
## 目标进甜区（PREFER_RANGE_MIN~MAX）就切向环绕着吐丹弹，太近后退拉开，太远追近；
## 被嘲讽追它的敌人天然被它拖着绕圈。
## 丹弹复用 BladeProjectile 对象池（player_projectiles 层），命中/击杀反馈全走敌人那一条；
## 伤害吃召唤伤害乘区（engineering_damage + synergy_engineering_damage，与御灵/炮台同链路）。
## 血量是它的寿命：无碰撞后敌人 slide 接触咬不到它，改为灵兽自判近身啃咬
## （CONTACT_RANGE 内取敌人 contact_damage，同一把尺子、同一无敌帧）；血量耗尽即消散。
## 血量不挂血条：受击时把 hp_ratio 灌给渲染器，由玄鹤本体传达（灵光/丹顶/灵目转暗、濒死裂纹闪烁）。
## 索敌读 GameManager.live_enemies 登记表，不做物理查询（最多 3 只，10Hz 重索节流）。

const BULLET_TEXTURE: Texture2D = preload("res://assets/art/bullet_spirit_pellet.png")
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/weapons/BladeProjectile.tscn")

var max_hp: float = 100.0
var current_hp: float = 100.0
var current_target: Node2D = null

var _wave: int = 1
var _dying: bool = false
var _attack_timer: float = 0.0
var _search_timer: float = 0.0
var _invincible_timer: float = 0.0
var _hit_flash: float = 0.0
var _face_sign: float = 1.0
var _orbit_sign: float = 1.0   ## 甜区环绕方向（每只灵兽固定一边，避免临界抖动）
var _renderer: ProceduralDroneRenderer = null

func _ready() -> void:
	add_to_group("allies")
	collision_layer = 0   # 无碰撞体积（铁律见文件头，别改）
	collision_mask = 0
	_wave = maxi(GameManager.wave_number, 1)
	max_hp = GameBalance.spirit_beast_max_hp(_wave)
	current_hp = max_hp

	_renderer = ProceduralDroneRenderer.new()
	_renderer.kind = ProceduralDroneRenderer.DroneKind.XUAN_HE
	add_child(_renderer)

	GameManager.register_ally(self)

	# 出场弹起
	scale = Vector2(0.2, 0.2)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_attack_timer = GameManager.rng.randf_range(0.2, 0.5)
	_search_timer = GameManager.rng.randf_range(0.0, GameBalance.SPIRIT_BEAST_SEARCH_INTERVAL)
	_orbit_sign = 1.0 if GameManager.rng.randf() < 0.5 else -1.0

func _exit_tree() -> void:
	GameManager.unregister_ally(self)

func _physics_process(delta: float) -> void:
	if GameManager.is_game_over or _dying:
		return

	if _invincible_timer > 0.0:
		_invincible_timer -= delta
	if _hit_flash > 0.0:
		_hit_flash -= delta
		if _hit_flash <= 0.0:
			modulate = Color.WHITE
	_attack_timer -= delta

	# 索敌节流：目标死了不当帧重查，下一节拍再找
	_search_timer -= delta
	if _search_timer <= 0.0:
		_search_timer = GameBalance.SPIRIT_BEAST_SEARCH_INTERVAL
		if current_target == null or not is_instance_valid(current_target) or current_target.dying:
			current_target = _find_target()

	var move_dir := Vector2.ZERO
	if current_target != null and is_instance_valid(current_target):
		var to_target: Vector2 = current_target.global_position - global_position
		var dist := to_target.length()
		var dir_to := Vector2.ZERO
		if dist > 0.001:
			dir_to = to_target / dist
		# 风筝三段：远追近、近拉开、甜区切向环绕着输出
		if dist > GameBalance.SPIRIT_BEAST_PREFER_RANGE_MAX:
			move_dir = dir_to
			velocity = dir_to * GameBalance.SPIRIT_BEAST_MOVE_SPEED
		elif dist < GameBalance.SPIRIT_BEAST_PREFER_RANGE_MIN:
			move_dir = -dir_to
			velocity = -dir_to * GameBalance.SPIRIT_BEAST_MOVE_SPEED
		else:
			move_dir = dir_to   # 面朝目标吐息，身子绕切向漂
			var tangent := Vector2(-dir_to.y, dir_to.x) * _orbit_sign
			velocity = tangent * GameBalance.SPIRIT_BEAST_MOVE_SPEED * GameBalance.SPIRIT_BEAST_STRAFE_SPEED_RATIO
		_try_fire(dir_to, dist)
	else:
		# 无敌人时巡游回玩家身边站着
		var p := GameManager.player
		if p != null and global_position.distance_to(p.global_position) > GameBalance.SPIRIT_BEAST_IDLE_FOLLOW_DIST:
			move_dir = (p.global_position - global_position).normalized()
			velocity = move_dir * GameBalance.SPIRIT_BEAST_MOVE_SPEED * 0.8
		else:
			velocity = velocity.move_toward(Vector2.ZERO, 600.0 * delta)

	# 无碰撞体积：直接积分位置（move_and_slide 无可撞之物，白走一遍管线）
	global_position += velocity * delta
	var lim: float = GameManager.MAP_HALF_EXTENT - 20.0
	global_position = global_position.clamp(Vector2(-lim, -lim), Vector2(lim, lim))

	# 近身啃咬结算：敌人贴到 CONTACT_RANGE 内仍咬得到它（血量即寿命的承伤口）
	_resolve_contact_bites()

	if _renderer != null:
		# 朝向翻转带滞回：只有走向明确与当前朝向相反（反向分量 > 0.25）才翻面，
		# 竖直方向追击（move_dir.x≈0）与临界抖动都不翻
		if move_dir.x * _face_sign < -0.25:
			_face_sign = -_face_sign
		_renderer.scale.x = _face_sign
		_renderer.speed_ratio = clampf(velocity.length() / GameBalance.SPIRIT_BEAST_MOVE_SPEED, 0.0, 1.0)
		# 悬浮侧倾：按朝向系下的横向走位 bank（与悬浮怪同款 ~6.5°），镜像由 scale.x 承担
		_renderer.bank_angle = deg_to_rad(6.5) * clampf(velocity.x * _face_sign / GameBalance.SPIRIT_BEAST_MOVE_SPEED, -1.0, 1.0)

## 索敌：读 live_enemies 登记表取最近活体（含濒死未清的要跳过）
func _find_target() -> Node2D:
	var nearest: Node2D = null
	var min_dist_sq := 99999999.0
	for e in GameManager.live_enemies:
		if e == null or not is_instance_valid(e) or e.dying:
			continue
		var d: float = global_position.distance_squared_to(e.global_position)
		if d < min_dist_sq:
			min_dist_sq = d
			nearest = e
	return nearest

## 吐息：冷却到且目标进了甜区上沿就吐丹弹；伤害吃召唤伤害乘区，
## 追踪小幅修正（homing_target）配风筝走位，命中/击杀掉落全走敌人 take_damage 那一条
func _try_fire(dir_to: Vector2, dist: float) -> void:
	if _attack_timer > 0.0:
		return
	if current_target == null or not is_instance_valid(current_target):
		return
	if dir_to == Vector2.ZERO or dist > GameBalance.SPIRIT_BEAST_PREFER_RANGE_MAX:
		return
	_attack_timer = GameBalance.SPIRIT_BEAST_ATTACK_INTERVAL
	var dmg: float = GameBalance.spirit_beast_damage(_wave) * (1.0 + GameManager.engineering_damage + GameManager.synergy_engineering_damage)
	var p := BladeProjectile.acquire_or_new(PROJECTILE_SCENE, get_tree().current_scene)
	p.global_position = global_position + dir_to * 12.0
	p.direction = dir_to
	p.speed = GameBalance.SPIRIT_BEAST_PROJECTILE_SPEED
	p.damage = dmg
	p.knockback_base = 60.0          # 轻推即可：别一发把敌人推出嘲讽圈
	p.pierce_left = 1
	p.bounce_left = 0
	p.homing_target = current_target
	p.bullet_texture = BULLET_TEXTURE
	p.bullet_scale = 0.6
	p.spin = false
	p.activate()
	p.lifetime = 0.9                 # activate 会把 lifetime 重置回 BASE_LIFETIME，必须在其后覆盖；覆盖甜区上沿 ×1.5 的飞行时长
	# 吐息小后坐（纯视觉，不改判定）
	if _renderer != null:
		_renderer.position = -dir_to * 4.0
		var recoil := create_tween()
		recoil.tween_property(_renderer, "position", Vector2.ZERO, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	AudioManager.play_sfx("blade_shoot", 0.4, GameManager.rng.randf_range(0.95, 1.1))

## 近身啃咬：无碰撞体积后敌人 slide 接触够不到灵兽，改由灵兽自判——
## 敌人贴进 CONTACT_RANGE 就按它自己的 contact_damage 咬一口（无敌帧挡逐帧结算）
func _resolve_contact_bites() -> void:
	if _invincible_timer > 0.0:
		return
	var range_sq: float = GameBalance.SPIRIT_BEAST_CONTACT_RANGE * GameBalance.SPIRIT_BEAST_CONTACT_RANGE
	for e in GameManager.live_enemies:
		if e == null or not is_instance_valid(e) or e.dying:
			continue
		if global_position.distance_squared_to(e.global_position) <= range_sq:
			take_damage(e.contact_damage)
			return

## 受击（近身啃咬的口子）：无敌帧挡逐帧结算，闪白 + 灵息转暗（hp_ratio 灌给渲染器）
func take_damage(amount: float) -> void:
	if _dying or _invincible_timer > 0.0:
		return
	_invincible_timer = GameBalance.SPIRIT_BEAST_HIT_INVINCIBLE
	current_hp -= amount
	_hit_flash = 0.12
	modulate = Color(1.8, 1.8, 1.8)
	if _renderer != null:
		_renderer.hp_ratio = clampf(current_hp / max_hp, 0.0, 1.0)
	if current_hp <= 0.0:
		_die()

func _die() -> void:
	_dying = true
	set_physics_process(false)
	AudioManager.play_sfx("enemy_death", 0.8)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2(0.1, 0.1), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	tw.chain().tween_callback(queue_free)
