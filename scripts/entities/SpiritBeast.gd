class_name SpiritBeast
extends CharacterBody2D

## 祭坛灵兽「灵珑」（2026-10-15 去鹤形改焰形；2026-10-24 圆球光灵重做：无脸圆球 +
## 金焰苗 + 双耳芽，形体语言对齐随行灵兽）：祭坛激活时召唤的风筝型远程友军。
##
## 组与碰撞（两条铁律，动了会被全场武器追着打 / 回合末被清场）：
##   - 只挂 "allies" 组 —— 绝不进 enemies/turrets/gems/chests，那四组 WaveSpawner.end_wave 全清；
##     正因为它不在那四组里，生命不耗尽就跨回合一直在场。
##   - 回合寿命（2026-10-25 重设计）：自召唤波起算共在场 GameBalance.SPIRIT_BEAST_LIFETIME_WAVES（3）
##     个回合，第 4 个回合开始时消散（_on_wave_changed 寿命闸）；同场上限 MAX_ACTIVE（3）由
##     祭坛召唤侧顶替最老一只来强制执行。
##   - 本体 collision_layer/mask 全 0：与敌人无任何物理碰撞体积（旧版挂 player 层会被敌人
##     move_and_slide 双向推挤，「撞着敌人跑」）；玩家武器索敌全走 mask=4（enemies 层），
##     也打不到它。移动直接积分 global_position，不走 move_and_slide。
##
## 行为：嘲讽（EnemyBase 走 live_allies 登记表，与碰撞无关，仍然生效）引怪后风筝——
## 目标进甜区（PREFER_RANGE_MIN~MAX）就切向环绕着输出，太近边退边打（倒退也面朝目标），
## 太远追近；被嘲讽追它的敌人天然被它拖着绕圈。三段走位速度用 MOVE_ACCEL 平滑过渡、
## 侧倾 bank 一阶跟随带死区（2026-10-15 抽搐修复：旧版朝向随后退 180° 翻面 + bank 每帧直写）。
## 拥挤软分离（2026-10-24）：无碰撞体积 ⇒ 敌人纯路过会踩上来，CROWD_RADIUS 内按距离衰减
## 合成远离向漂移直接积分位置，被围时从人堆缓缓挤出；本体 z_index=1 永画在敌人上层不被盖。
## 攻击为「三连灵羽弹」：冷却到 → 蓄力 CHARGE_TIME（嘴边灵光球涨大，渲染器 charge_ratio 0→1）
## → BURST_GAP 间隔连吐 BURST_COUNT 发追踪灵羽（每发后坐、音调递进，余辉随剩余发数递减）。
## 灵羽复用 BladeProjectile 对象池（player_projectiles 层），命中/击杀反馈全走敌人那一条；
## 伤害吃召唤伤害乘区（engineering_damage + synergy_engineering_damage，与御灵/炮台同链路）。
## 生命是它的寿命：无碰撞后敌人 slide 接触咬不到它，改为灵兽自判近身啃咬
## （CONTACT_RANGE 内取敌人 contact_damage，同一把尺子、同一无敌帧）；生命耗尽即消散。
## 生命不挂血条：受击时把 hp_ratio / hit_flash 灌给渲染器，由灵珑本体传达
## （受击平涂闪白一拍 + 挤压回弹 + 顺咬合方向微弹退；血量低落圆身转暗、濒死裂纹闪烁）。
## 索敌读 GameManager.live_enemies 登记表，不做物理查询（最多 3 只，10Hz 重索节流）。

const BULLET_TEXTURE: Texture2D = preload("res://assets/art/bullet_spirit_pellet.png")
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/weapons/BladeProjectile.tscn")

## 召唤波次（也是本回合血量/伤害的成长基准；祭坛顶替逻辑按它找「最老」的一只）
var summon_wave: int = 1
## 配色档位（0 灵青 / 1 赤焰 / 2 紫电）：祭坛召唤时取场上未占用的最小档，同场不撞色
var palette_idx: int = 0

var max_hp: float = 100.0
var current_hp: float = 100.0
var current_target: Node2D = null

var _dying: bool = false
var _attack_timer: float = 0.0
var _search_timer: float = 0.0
var _invincible_timer: float = 0.0
var _scale_tween: Tween = null    ## 本体 scale 补间句柄（出场弹起/受击挤压共用通道，先杀旧再起新）
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
	# 永远画在敌人上层（z 压过 EntitiesLayer 的 y_sort）：灵兽无碰撞体积，敌人纯路过会踩上来，
	# 被踩时剪影不能被怪体盖掉糊成一团（2026-10-24 拥挤状态优化）
	z_index = 1
	summon_wave = maxi(GameManager.wave_number, 1)
	max_hp = GameBalance.spirit_beast_max_hp(summon_wave)
	current_hp = max_hp

	_renderer = ProceduralDroneRenderer.new()
	_renderer.kind = ProceduralDroneRenderer.DroneKind.YUAN_LING
	_renderer.palette_idx = clampi(palette_idx, 0, ProceduralDroneRenderer.PALETTES.size() - 1)
	add_child(_renderer)

	GameManager.register_ally(self)
	# 寿命闸（2026-10-25 重设计）：回合开始时自召唤波起算满 LIFETIME_WAVES 即消散
	if not GameManager.wave_changed.is_connected(_on_wave_changed):
		GameManager.wave_changed.connect(_on_wave_changed)

	# 出场弹起 + 现身辉光（晕圈强闪、灵尘收拢一拍，衔接祭坛冲击环）
	scale = Vector2(0.2, 0.2)
	_renderer.spawn_glow = 1.0
	_scale_tween = create_tween()
	_scale_tween.tween_property(self, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_attack_timer = GameManager.rng.randf_range(0.2, 0.5)
	_search_timer = GameManager.rng.randf_range(0.0, GameBalance.SPIRIT_BEAST_SEARCH_INTERVAL)
	_orbit_sign = 1.0 if GameManager.rng.randf() < 0.5 else -1.0

## 寿命到期 / 满员顶替的消散口子：不是战死，不播受击音，只余一缕灰蓝灵屑
func expire_for_replacement() -> void:
	if _dying:
		return
	_dying = true
	set_physics_process(false)
	var fx_host: Node = get_tree().current_scene
	if fx_host != null:
		ObeliskFx.play_spent_wisp(fx_host, global_position)
	AudioManager.play_sfx("impact_blunt", 0.3, 1.5)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2(0.1, 0.1), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	tw.chain().tween_callback(queue_free)

## 回合开始：自召唤波起算满寿命即消散（召唤当波算第 1 回合，共在场 3 个回合）
func _on_wave_changed(wave_number: int) -> void:
	if _dying:
		return
	if wave_number - summon_wave >= GameBalance.SPIRIT_BEAST_LIFETIME_WAVES:
		expire_for_replacement()

func _exit_tree() -> void:
	GameManager.unregister_ally(self)

func _physics_process(delta: float) -> void:
	if GameManager.is_game_over or _dying:
		return

	if _invincible_timer > 0.0:
		_invincible_timer -= delta

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

	# 敌人接触结算：拥挤软分离 + 近身啃咬
	_resolve_contact_bites(delta)

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
	var dmg: float = GameBalance.spirit_beast_damage(summon_wave) * (1.0 + GameManager.engineering_damage + GameManager.synergy_engineering_damage)
	var dir := _aim_dir
	if current_target != null and is_instance_valid(current_target):
		var to_target: Vector2 = current_target.global_position - global_position
		if to_target.length() > 0.001:
			dir = to_target.normalized()
	var p := BladeProjectile.acquire_or_new(PROJECTILE_SCENE, get_tree().current_scene)
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

## 敌人接触结算：灵兽无碰撞体积（铁律见文件头），敌人是纯路过踩上来的——
## 一次循环做两件事（2026-10-24 拥挤状态优化）：
##   ① 拥挤软分离：CROWD_RADIUS 内每个敌人按距离衰减贡献一个远离向推量，
##      合成后直接积分位置——被围时从人堆里缓缓挤出去，不再站在怪堆剪影里糊成一团；
##   ② 近身啃咬：敌人贴进 CONTACT_RANGE 就按它自己的 contact_damage 咬一口（无敌帧挡逐帧结算）
func _resolve_contact_bites(delta: float) -> void:
	var crowd := Vector2.ZERO
	var crowd_n := 0
	var range_sq: float = GameBalance.SPIRIT_BEAST_CONTACT_RANGE * GameBalance.SPIRIT_BEAST_CONTACT_RANGE
	var crowd_sq: float = GameBalance.SPIRIT_BEAST_CROWD_RADIUS * GameBalance.SPIRIT_BEAST_CROWD_RADIUS
	for e in GameManager.live_enemies:
		if e == null or not is_instance_valid(e) or e.dying:
			continue
		var e_pos: Vector2 = e.global_position
		var diff := global_position - e_pos
		var d_sq := diff.length_squared()
		if d_sq > crowd_sq:
			continue
		var d := sqrt(d_sq)
		var push: Vector2 = diff / d if d > 0.001 else Vector2.UP
		crowd += push * (1.0 - d / GameBalance.SPIRIT_BEAST_CROWD_RADIUS)
		crowd_n += 1
		if d_sq <= range_sq:
			take_damage(e.contact_damage, push)
	if crowd_n > 0:
		global_position += crowd.normalized() * GameBalance.SPIRIT_BEAST_CROWD_PUSH_SPEED * delta
		var lim: float = GameManager.MAP_HALF_EXTENT - 20.0
		global_position = global_position.clamp(Vector2(-lim, -lim), Vector2(lim, lim))

## 受击（近身啃咬的口子）：无敌帧挡逐帧结算。受击一拍三件套（2026-10-24 受击动画重做）：
## 渲染器平涂闪白（hit_flash 1→0 约 0.16s，只提亮色块、墨环不发灰）+ 本体挤压回弹
## （压扁 1.18/0.84 后 BACK_OUT 弹回）+ 顺咬合方向微弹退（renderer 位移通道，与吐息后坐同款）；
## 血量长期传达照旧走 hp_ratio（低落圆身转暗、濒死墨裂纹）
func take_damage(amount: float, from_dir: Vector2 = Vector2.ZERO) -> void:
	if _dying or _invincible_timer > 0.0:
		return
	_invincible_timer = GameBalance.SPIRIT_BEAST_HIT_INVINCIBLE
	current_hp -= amount
	AudioManager.play_sfx("impact_blunt", 0.4, 1.3)
	if _renderer != null:
		_renderer.hit_flash = 1.0
		_renderer.hp_ratio = clampf(current_hp / max_hp, 0.0, 1.0)
		if from_dir != Vector2.ZERO:
			_renderer.position = from_dir * 6.0
			var nudge := create_tween()
			nudge.tween_property(_renderer, "position", Vector2.ZERO, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if current_hp <= 0.0:
		_die()
		return
	# 挤压回弹（flinch 一拍）：与出场弹起共用 scale 通道，先杀旧补间再起新
	if _scale_tween != null and _scale_tween.is_valid():
		_scale_tween.kill()
	scale = Vector2(1.18, 0.84)
	_scale_tween = create_tween()
	_scale_tween.tween_property(self, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

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
