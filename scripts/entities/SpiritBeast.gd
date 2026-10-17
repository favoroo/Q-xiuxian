class_name SpiritBeast
extends CharacterBody2D

## 祭坛灵兽「灵珑」（2026-10-15 圆形灵魄重做：去鹤形、按圆形设计）：祭坛激活时召唤的风筝型远程友军。
##
## 组与碰撞（两条铁律，动了会被全场武器追着打 / 回合末被清场）：
##   - 只挂 "allies" 组 —— 绝不进 enemies/turrets/gems/chests，那四组 WaveSpawner.end_wave 全清；
##     正因为它不在那四组里，生命不耗尽就跨回合一直在场。
##   - 本体 collision_layer/mask 全 0：与敌人无任何物理碰撞体积（旧版挂 player 层会被敌人
##     move_and_slide 双向推挤，「撞着敌人跑」）；玩家武器索敌全走 mask=4（enemies 层），
##     也打不到它。移动直接积分 global_position，不走 move_and_slide。
##
## 行为：嘲讽（EnemyBase 走 live_allies 登记表，与碰撞无关，仍然生效）引怪后风筝——
## 目标进甜区（PREFER_RANGE_MIN~MAX）就切向环绕着输出，太近边退边打（倒退也面朝目标），
## 太远追近；被嘲讽追它的敌人天然被它拖着绕圈。三段走位速度用 MOVE_ACCEL 平滑过渡、
## 侧倾 bank 一阶跟随带死区（2026-10-15 抽搐修复：旧版朝向随后退 180° 翻面 + bank 每帧直写）。
## 攻击为「三连灵羽弹」：冷却到 → 蓄力 CHARGE_TIME（嘴边灵光球涨大，渲染器 charge_ratio 0→1）
## → BURST_GAP 间隔连吐 BURST_COUNT 发追踪灵羽（每发后坐、音调递进，余辉随剩余发数递减）。
## 灵羽复用 BladeProjectile 对象池（player_projectiles 层），命中/击杀反馈全走敌人那一条；
## 伤害吃召唤伤害乘区（engineering_damage + synergy_engineering_damage，与御灵/炮台同链路）。
## 生命是它的寿命：无碰撞后敌人 slide 接触咬不到它，改为灵兽自判近身啃咬
## （CONTACT_RANGE 内取敌人 contact_damage，同一把尺子、同一无敌帧）；生命耗尽即消散。
## 生命不挂血条：受击时把 hp_ratio 灌给渲染器，由灵珑本体传达（灵光/祭纹灵印/灵目转暗、濒死裂纹闪烁）。
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
var _bank: float = 0.0           ## 平滑后的侧倾角（bank 一阶跟随的状态载体）
var _orbit_sign: float = 1.0     ## 甜区环绕方向（每只灵兽固定一边，避免临界抖动）
var _aim_dir: Vector2 = Vector2.RIGHT  ## 最近一拍瞄准方向（连发时每发重取）
var _charge_timer: float = 0.0   ## >0 = 吐息蓄力中（嘴边灵光球涨大）
var _burst_left: int = 0         ## >0 = 三连连发中剩余发数
var _burst_timer: float = 0.0    ## 连发间隔计时
var _renderer: ProceduralDroneRenderer = null

func _ready() -> void:
	add_to_group("allies")
	collision_layer = 0   # 无碰撞体积（铁律见文件头，别改）
	collision_mask = 0
	_wave = maxi(GameManager.wave_number, 1)
	max_hp = GameBalance.spirit_beast_max_hp(_wave)
	current_hp = max_hp

	_renderer = ProceduralDroneRenderer.new()
	_renderer.kind = ProceduralDroneRenderer.DroneKind.YUAN_LING
	add_child(_renderer)

	GameManager.register_ally(self)

	# 出场弹起 + 现身辉光（晕圈强闪、灵尘收拢一拍，衔接祭坛冲击环）
	scale = Vector2(0.2, 0.2)
	_renderer.spawn_glow = 1.0
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

	# 索敌节流：目标死了不当帧重查，下一节拍再找
	_search_timer -= delta
	if _search_timer <= 0.0:
		_search_timer = GameBalance.SPIRIT_BEAST_SEARCH_INTERVAL
		if current_target == null or not is_instance_valid(current_target) or current_target.dying:
			current_target = _find_target()

	# face_dir：朝向依据（有目标跟目标方向，倒退也面朝目标；无目标跟走向）
	# desired_vel：本拍想要的速度，三段风筝之间用 MOVE_ACCEL 平滑过渡，不硬切
	var face_dir := Vector2.ZERO
	var desired_vel := Vector2.ZERO
	if current_target != null and is_instance_valid(current_target):
		var to_target: Vector2 = current_target.global_position - global_position
		var dist := to_target.length()
		var dir_to := Vector2.ZERO
		if dist > 0.001:
			dir_to = to_target / dist
			_aim_dir = dir_to
		face_dir = dir_to
		# 风筝三段：远追近、近边退边打（面朝不变）、甜区切向环绕着输出
		if dist > GameBalance.SPIRIT_BEAST_PREFER_RANGE_MAX:
			desired_vel = dir_to * GameBalance.SPIRIT_BEAST_MOVE_SPEED
		elif dist < GameBalance.SPIRIT_BEAST_PREFER_RANGE_MIN:
			desired_vel = -dir_to * GameBalance.SPIRIT_BEAST_MOVE_SPEED
		else:
			var tangent := Vector2(-dir_to.y, dir_to.x) * _orbit_sign
			desired_vel = tangent * GameBalance.SPIRIT_BEAST_MOVE_SPEED * GameBalance.SPIRIT_BEAST_STRAFE_SPEED_RATIO
	else:
		# 无敌人时巡游回玩家身边站着
		var p := GameManager.player
		if p != null and global_position.distance_to(p.global_position) > GameBalance.SPIRIT_BEAST_IDLE_FOLLOW_DIST:
			face_dir = (p.global_position - global_position).normalized()
			desired_vel = face_dir * GameBalance.SPIRIT_BEAST_MOVE_SPEED * 0.8

	# 速度平滑过渡 + 无碰撞体积直接积分位置（move_and_slide 无可撞之物，白走一遍管线）
	velocity = velocity.move_toward(desired_vel, GameBalance.SPIRIT_BEAST_MOVE_ACCEL * delta)
	global_position += velocity * delta
	var lim: float = GameManager.MAP_HALF_EXTENT - 20.0
	global_position = global_position.clamp(Vector2(-lim, -lim), Vector2(lim, lim))

	# 近身啃咬结算：敌人贴到 CONTACT_RANGE 内仍咬得到它（生命即寿命的承伤口）
	_resolve_contact_bites()

	# 蓄力 → 三连 → 冷却的攻击状态机
	_update_attack(delta)

	if _renderer != null:
		# 朝向翻转带滞回：只有朝向依据明确与当前朝向相反（反向分量 > 0.35）才翻面，
		# 竖直方向追击（face_dir.x≈0）与临界抖动都不翻
		if face_dir != Vector2.ZERO and face_dir.x * _face_sign < -0.35:
			_face_sign = -_face_sign
		_renderer.scale.x = _face_sign
		_renderer.speed_ratio = clampf(velocity.length() / GameBalance.SPIRIT_BEAST_MOVE_SPEED, 0.0, 1.0)
		# 悬浮侧倾：按朝向系下的横向走位 bank，一阶跟随 + 死区（环绕边界上不抖）
		var bank_target := 0.0
		var lateral: float = velocity.x * _face_sign / GameBalance.SPIRIT_BEAST_MOVE_SPEED
		if absf(lateral) > 0.18:
			bank_target = deg_to_rad(6.5) * clampf(lateral, -1.0, 1.0)
		_bank = lerpf(_bank, bank_target, minf(delta * 10.0, 1.0))
		_renderer.bank_angle = _bank

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

## 攻击状态机：待机冷却 → 蓄力（灵光球涨大）→ 三连连发 → 回冷却。
## 目标在蓄力/连发途中没了：蓄力散掉进短冷却，连发直接终止本轮
func _update_attack(delta: float) -> void:
	var target_ok: bool = current_target != null and is_instance_valid(current_target) and not current_target.dying
	if _burst_left > 0:
		_burst_timer -= delta
		if _burst_timer <= 0.0:
			if not target_ok:
				_burst_left = 0
				_attack_timer = GameBalance.SPIRIT_BEAST_ATTACK_INTERVAL * 0.5
				if _renderer != null:
					_renderer.charge_ratio = 0.0
				return
			_burst_timer = GameBalance.SPIRIT_BEAST_BURST_GAP
			_burst_left -= 1
			_fire_one()
			if _burst_left <= 0:
				_attack_timer = GameBalance.SPIRIT_BEAST_ATTACK_INTERVAL
		return
	if _charge_timer > 0.0:
		if not target_ok:
			_charge_timer = 0.0
			_attack_timer = 0.3
			if _renderer != null:
				_renderer.charge_ratio = 0.0
			return
		_charge_timer -= delta
		if _renderer != null:
			_renderer.charge_ratio = clampf(1.0 - _charge_timer / GameBalance.SPIRIT_BEAST_CHARGE_TIME, 0.0, 1.0)
		if _charge_timer <= 0.0:
			_burst_left = GameBalance.SPIRIT_BEAST_BURST_COUNT
			_burst_timer = 0.0
		return
	_attack_timer -= delta
	if _attack_timer <= 0.0:
		if target_ok and global_position.distance_to(current_target.global_position) <= GameBalance.SPIRIT_BEAST_PREFER_RANGE_MAX:
			_charge_timer = GameBalance.SPIRIT_BEAST_CHARGE_TIME
		else:
			_attack_timer = 0.1   # 不在射程/无目标，下一拍再看

## 吐一发灵羽：追踪小幅修正（homing_target）配风筝走位，命中/击杀掉落全走敌人 take_damage 那一条；
## 每发后坐 + 音调递进，蓄力余辉随剩余发数递减（charge_ratio 1→0）
func _fire_one() -> void:
	var dmg: float = GameBalance.spirit_beast_damage(_wave) * (1.0 + GameManager.engineering_damage + GameManager.synergy_engineering_damage)
	var dir := _aim_dir
	if current_target != null and is_instance_valid(current_target):
		var to_target: Vector2 = current_target.global_position - global_position
		if to_target.length() > 0.001:
			dir = to_target.normalized()
	var p := BladeProjectile.acquire_or_new(PROJECTILE_SCENE, GameManager.battle_host())
	p.global_position = global_position + dir * 12.0
	p.direction = dir
	p.speed = GameBalance.SPIRIT_BEAST_PROJECTILE_SPEED
	p.damage = dmg
	p.knockback_base = 60.0          # 轻推即可：别一发把敌人推出嘲讽圈
	p.pierce_left = 1
	p.bounce_left = 0
	p.homing_target = current_target
	p.bullet_texture = BULLET_TEXTURE
	p.bullet_scale = 0.8
	p.spin = false
	p.activate()
	p.lifetime = 0.9                 # activate 会把 lifetime 重置回 BASE_LIFETIME，必须在其后覆盖；覆盖甜区上沿 ×1.5 的飞行时长
	# 吐息小后坐（纯视觉，不改判定）+ 余辉随剩余发数递减
	if _renderer != null:
		_renderer.charge_ratio = float(_burst_left) / float(maxi(GameBalance.SPIRIT_BEAST_BURST_COUNT, 1))
		_renderer.position = -dir * 5.0
		var recoil := create_tween()
		recoil.tween_property(_renderer, "position", Vector2.ZERO, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var shot_idx: int = GameBalance.SPIRIT_BEAST_BURST_COUNT - _burst_left
	AudioManager.play_sfx("blade_shoot", 0.45, 0.92 + 0.09 * float(shot_idx))

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
	# 友方灵兽被咬死不是玩家战果：pitch_override 直传，不进击杀连击阶梯
	AudioManager.play_sfx("enemy_death", 0.8, 1.0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2(0.1, 0.1), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	tw.chain().tween_callback(queue_free)
