class_name SpiritPet
extends Node2D

## 灵兽（随行伙伴）实体：纯 _draw 程序化光灵 + 精致特征部件，无碰撞体，跨回合存活
## 铁律：只挂 "spirit_pets" 组，绝不进 enemies/turrets/gems/chests 四个回合末清场组。
## 多个灵兽通过 orbit_index 均分绕飘相位，视觉各自舒展不重叠。

const FOLLOW_DIST: float = 42.0     ## 跟随绕飘半径（px）
const HEIGHT_OFFSET: float = 32.0   ## 悬在玩家头顶上方（px）
const DISSOLVE_SEC: float = 0.35    ## 出售/移除时的消散时长（秒）

const BULLET_FIRE_TEXTURE = preload("res://assets/art/bullet_fire_flame.png")
const BULLET_PELLET_TEXTURE = preload("res://assets/art/bullet_spirit_pellet.png")
const BULLET_COIN_TEXTURE = preload("res://assets/art/icon_coin.png")
const PROJECTILE_SCENE = preload("res://scenes/weapons/BladeProjectile.tscn")
const BOULDER_SCRIPT = preload("res://scripts/entities/SpiritPetBoulder.gd")

var pet_id: String = ""             ## 灵兽 id（见 PetData）
var pet_def: Dictionary = {}
var orbit_index: int = 0            ## 在已购灵兽队列里的序号（0, 1, 2）
var total_pets: int = 1             ## 当前总灵兽数（均分相位用）
var target: Player = null           ## 随行主人

var _age: float = 0.0
var _cooldown_timer: float = 0.8    ## 首跳延迟 0.8 秒，平稳入场
var _dying: bool = false
var _action_fx: float = -1.0        ## 脉冲/动作特效进度（0~1，<0 为无）
var _lightning_target_pos: Vector2 = Vector2.ZERO ## 雷击主目标终点（本地坐标）
var _chain_targets_pos: Array[Vector2] = []       ## 雷击连锁分支目标终点（本地坐标）
var _spit_dir: Vector2 = Vector2.ZERO             ## 聚宝蟾吐金宝朝向（本地坐标，供吐宝扇芒绘制）
var _fire_dir: Vector2 = Vector2.ZERO             ## 焰灵狐吐火朝向（本地坐标，供喷射扇焰绘制）

# --- 增强视觉表现字段 ---
var _flash_timer: float = 0.0       ## 触发/受激闪白计时（秒）
var _scale_punch: Vector2 = Vector2.ONE ## 施法挤压回弹（Squash & Stretch）
var _tether_target_pos: Vector2 = Vector2.ZERO ## 法力连线目标点（相对本地坐标，如玄甲龟拦截）
var _tether_progress: float = -1.0  ## 连线动画进度（0~1，<0 为无）
var _spin_angle: float = 0.0        ## 灵兽专属旋转姿态（如灵风貂旋转）
var _custom_fx_type: String = ""    ## 专属特效类型标记
var _yulu_buff_timer: float = 0.0   ## 玉露鹿生机加速计时器（秒）

## 重绘节流（2026-10-15 性能优化）：全场最多 3 只灵兽，原 _physics_process 每帧无条件 queue_redraw()，
## 55 处矢量 draw 指令。环绕跟随与呼吸均为平滑慢速量，降至 20Hz 节流 + 错相，动作爆发（pulse_trigger_fx）
## 打 dirty 插队，保证灵敏反馈同时削减 33%~66% 冗余重绘。
const REDRAW_INTERVAL := 0.05
var _draw_phase: float = 0.0
var _dirty: bool = true

static var _circle_buf := PackedVector2Array()

func _circle(center: Vector2, radius: float, col: Color) -> void:
	var seg := clampi(int(radius * 1.4), 6, 28)
	_circle_buf.resize(seg)
	for i in range(seg):
		var ang := float(i) * TAU / float(seg)
		_circle_buf[i] = center + Vector2(cos(ang), sin(ang)) * radius
	draw_colored_polygon(_circle_buf, col)

func _arc(center: Vector2, radius: float, start_angle: float, end_angle: float, _point_count: int, color: Color, width: float = 1.0, antialiased: bool = false) -> void:
	var seg := clampi(int(radius * absf(end_angle - start_angle) * 0.22), 6, 32)
	draw_arc(center, radius, start_angle, end_angle, seg, color, width, antialiased)

func _ready() -> void:
	add_to_group("spirit_pets")
	_draw_phase = fposmod(float(get_instance_id() % 97) * 0.001, REDRAW_INTERVAL)
	if pet_id != "":
		_apply_def()

func setup(p_id: String, idx: int, total: int, owner_player: Player) -> void:
	pet_id = p_id
	orbit_index = idx
	total_pets = maxi(1, total)
	target = owner_player
	_apply_def()

func _apply_def() -> void:
	pet_def = PetData.get_def(pet_id)
	_dirty = true
	queue_redraw()

func _physics_process(delta: float) -> void:
	if _dying:
		return
	if target == null or not is_instance_valid(target):
		if GameManager.player != null and is_instance_valid(GameManager.player):
			target = GameManager.player as Player
		else:
			return

	_age += delta

	# 柔和环绕跟随：椭圆绕飘 + 均分相位角
	var base_phase: float = (TAU * float(orbit_index) / float(maxi(1, total_pets)))
	var t: float = _age * 0.85 + base_phase
	var offset := Vector2(
		cos(t) * FOLLOW_DIST,
		sin(t * 1.2) * (FOLLOW_DIST * 0.55) - HEIGHT_OFFSET + sin(_age * 2.2 + base_phase) * 4.0
	)
	global_position = global_position.lerp(target.global_position + offset, minf(1.0, 6.0 * delta))

	# 特效动画推进
	if _action_fx >= 0.0:
		_action_fx += delta * 2.8
		if _action_fx > 1.0:
				_action_fx = -1.0
				_lightning_target_pos = Vector2.ZERO
				_chain_targets_pos.clear()
				_spit_dir = Vector2.ZERO
				_fire_dir = Vector2.ZERO
				_custom_fx_type = ""

	# 闪白与挤压回弹推进
	if _flash_timer > 0.0:
		_flash_timer = maxf(0.0, _flash_timer - delta)
	if _scale_punch != Vector2.ONE:
		_scale_punch = _scale_punch.lerp(Vector2.ONE, minf(1.0, 14.0 * delta))
	scale = _scale_punch

	# 连线特效推进（如玄甲龟连线拦截点、聚宝蟾引宝光线）
	if _tether_progress >= 0.0:
		_tether_progress += delta * 4.5
		if _tether_progress > 1.0:
			_tether_progress = -1.0
			_tether_target_pos = Vector2.ZERO

	# 专属自转衰减（如灵风貂磁吸自转）
	if absf(_spin_angle) > 0.001:
		_spin_angle = lerpf(_spin_angle, 0.0, minf(1.0, 10.0 * delta))
		rotation = _spin_angle
	else:
		rotation = 0.0

	# 玉露鹿生机加速状态推进
	if _yulu_buff_timer > 0.0:
		_yulu_buff_timer -= delta
		if _yulu_buff_timer <= 0.0:
			GameManager.buff_move_speed_mult = 1.0
			GameManager.buff_pickup_range_mult = 1.0

	# 战斗行为（非终局、非暂停时按冷却心跳推进）
	if not GameManager.is_game_over and not get_tree().paused:
		_tick_behavior(delta)

	if _dirty or _draw_phase <= 0.0:
		_dirty = false
		_draw_phase = REDRAW_INTERVAL
		queue_redraw()
	else:
		_draw_phase -= delta

func _tick_behavior(delta: float) -> void:
	var base_cd: float = float(pet_def.get("base_cooldown", 0.0))
	if base_cd <= 0.0:
		return
	var cd: float = BalanceSpiritPet.cooldown(base_cd, GameManager.pet_cooldown_mult)
	_cooldown_timer -= delta
	if _cooldown_timer <= 0.0:
		_cooldown_timer = cd
		_trigger_action()

func _trigger_action() -> void:
	match pet_id:
		"yanhu":
			_act_yanhu()
		"leique":
			_act_leique()
		"xuangui":
			_act_xuangui()
		"yulu":
			_act_yulu()
		"juchan":
			_act_juchan()
		"fengdiao":
			_act_fengdiao()
		"shiyuan":
			_act_shiyuan()

## 获取灵兽当前享受的综合伤害倍率
func _get_effective_damage_mult() -> float:
	var global_dmg: float = (GameManager.get_weapon_damage_mult() * GameManager.synergy_damage_mult) - 1.0
	var elem_bonus: float = 0.0
	if not GameManager.element_damage.is_empty():
		for v in GameManager.element_damage.values():
			elem_bonus = maxf(elem_bonus, float(v))
	return BalanceSpiritPet.calc_pet_damage_mult(GameManager.pet_damage_mult, global_dmg, elem_bonus)

## 通用触发高光脉冲与形变回弹
func pulse_trigger_fx(squash_stretch: Vector2 = Vector2(1.35, 1.35), flash_duration: float = 0.14) -> void:
	_action_fx = 0.0
	_flash_timer = flash_duration
	_scale_punch = squash_stretch
	_dirty = true
	queue_redraw()

## 焰灵狐：三昧真火与烈焰易伤
func _act_yanhu() -> void:
	var nearest := _find_nearest_enemy(340.0)
	if nearest == null:
		return
	var dir := (nearest.global_position - global_position).normalized()
	var eff_mult := _get_effective_damage_mult()
	var dmg := BalanceSpiritPet.fire_damage(GameManager.wave_number, eff_mult)

	var p := BladeProjectile.acquire_or_new(PROJECTILE_SCENE, get_tree().current_scene)
	p.global_position = global_position + dir * 12.0
	p.direction = dir
	p.speed = 380.0
	p.damage = dmg
	p.knockback_base = 55.0
	p.pierce_left = 1
	p.bounce_left = 0
	p.homing_target = nearest
	# 换用火属性真实贴图，启用 ProceduralProjectileRenderer 的 4 层三昧真火
	p.bullet_texture = BULLET_FIRE_TEXTURE
	p.bullet_scale = 0.65
	p.spin = true
	# 强力灼烧 Proc
	p.proc_burn = true
	p.burn_dps = BalanceSpiritPet.fire_burn_dps(dmg)
	p.burn_dur = BalanceSpiritPet.FIRE_BURN_DURATION
	p.activate()
	p.lifetime = 1.1

	# 后坐形变 + 灵狐吐火星屑
	pulse_trigger_fx(Vector2(0.75, 1.35), 0.14)
	_custom_fx_type = "fire_burst"
	_fire_dir = dir
	var scene_parent: Node = get_parent()
	if is_inside_tree() and scene_parent != null:
		JuiceEffect.spawn_impact_pop(scene_parent, global_position, Color(1.0, 0.45, 0.15), -dir)
		JuiceEffect.spawn_shockwave(scene_parent, global_position + dir * 8.0, 26.0, Color(1.0, 0.45, 0.15, 0.8), 0.2)
	AudioManager.play_sfx("blade_shoot", 0.4, 1.1)

## 雷灵雀：高伤连锁神雷与麻痹打断
func _act_leique() -> void:
	var nearest := _find_nearest_enemy(320.0)
	if nearest == null:
		return
	var eff_mult := _get_effective_damage_mult()
	var base_dmg := BalanceSpiritPet.thunder_damage(GameManager.wave_number, eff_mult)
	var crit_m := GameManager.get_crit_mult()
	var primary_dmg := base_dmg * crit_m * GameManager.elite_damage_mult_for(nearest)

	# 1. 主目标受创与麻痹打断
	if nearest.has_method("take_damage"):
		nearest.take_damage(primary_dmg, Vector2.ZERO, true)
	# 神通钩子（兽群链电 / 灵蕴五行）：直击落点统一走 OnHitEffects.on_pet_hit
	OnHitEffects.on_pet_hit(self, nearest, primary_dmg)
	if nearest.has_method("apply_vortex_pin"):
		nearest.apply_vortex_pin(Vector2.ZERO, BalanceSpiritPet.THUNDER_STUN_DURATION)

	_lightning_target_pos = to_local(nearest.global_position)
	_chain_targets_pos.clear()

	# 2. 连锁神雷：向最近的 1~2 个敌人弹射
	var chain_dmg := primary_dmg * BalanceSpiritPet.THUNDER_CHAIN_RATIO
	var chained: int = 0
	for e in GameManager.live_enemies:
		if e == nearest or not is_instance_valid(e) or not (e is Node2D):
			continue
		if e.get(&"dying") == true:
			continue
		var n2d := e as Node2D
		var d_sq := nearest.global_position.distance_squared_to(n2d.global_position)
		if d_sq <= 190.0 * 190.0:
			if e.has_method("take_damage"):
				e.take_damage(chain_dmg, Vector2.ZERO, true)
				OnHitEffects.on_pet_hit(self, n2d, chain_dmg)
			if e.has_method("apply_vortex_pin"):
				e.apply_vortex_pin(Vector2.ZERO, BalanceSpiritPet.THUNDER_STUN_DURATION * 0.75)
			_chain_targets_pos.append(to_local(n2d.global_position))
			chained += 1
			if chained >= BalanceSpiritPet.THUNDER_CHAIN_MAX:
				break

	pulse_trigger_fx(Vector2(1.4, 0.75), 0.16)
	_custom_fx_type = "thunder_chain"
	var scene_parent: Node = get_parent()
	if is_inside_tree() and scene_parent != null:
		JuiceEffect.spawn_impact_pop(scene_parent, nearest.global_position, Color(0.68, 0.58, 1.0))
		JuiceEffect.spawn_shockwave(scene_parent, nearest.global_position, 34.0, Color(0.75, 0.65, 1.0), 0.22)
	AudioManager.play_sfx("thunder_strike", 0.45, 1.2)

## 玄甲龟：金汤拒马与护体
func _act_xuangui() -> void:
	var radius := BalanceSpiritPet.intercept_radius(GameManager.pet_effect_mult)
	var radius_sq := radius * radius
	var center := target.global_position if target != null else global_position
	var scene_parent: Node = get_parent()

	# 1. 范围消除敌方弹丸
	var bolts := get_tree().get_nodes_in_group("enemy_bolts")
	var intercepted_count: int = 0
	var first_bolt_pos := Vector2.ZERO
	for b in bolts:
		if not is_instance_valid(b) or not (b is Node2D):
			continue
		var n2d := b as Node2D
		if not n2d.visible:
			continue
		var d := center.distance_squared_to(n2d.global_position)
		if d <= radius_sq:
			if first_bolt_pos == Vector2.ZERO:
				first_bolt_pos = n2d.global_position
			if b.has_method("intercept"):
				b.intercept()
			elif b.has_method("_recycle"):
				b._recycle()
			intercepted_count += 1
	# 拦截火花防抢占：不再对每颗弹丸逐发 spawn_impact_pop（避免吃光全局 6/帧 限流闸导致玩家飞剑无反馈），仅在首颗位置放至多 1 处
	if intercepted_count > 0 and first_bolt_pos != Vector2.ZERO and is_inside_tree() and scene_parent != null:
		JuiceEffect.spawn_impact_pop(scene_parent, first_bolt_pos, Color(0.35, 0.85, 0.95))

	# 2. 拒马震退近身敌人
	var repelled: int = 0
	for e in GameManager.live_enemies:
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		if e.get(&"dying") == true:
			continue
		var n2d := e as Node2D
		var diff := n2d.global_position - center
		if diff.length_squared() <= radius_sq:
			var kb_dir := diff.normalized() if diff.length_squared() > 1.0 else Vector2.RIGHT
			if e.has_method("take_damage"):
				e.take_damage(0.0, kb_dir * BalanceSpiritPet.XUANGUI_REPEL_FORCE, false)
				repelled += 1

	# 3. 濒危玄甲护符（生命 < 35% 时紧急保护）
	var shield_granted := false
	if target != null and target.current_health < target.max_health * 0.35:
		target.heal(BalanceSpiritPet.shield_amount(GameManager.wave_number), true)
		shield_granted = true

	if intercepted_count > 0 or repelled > 0 or shield_granted:
		pulse_trigger_fx(Vector2(1.15, 1.15), 0.12)
		_custom_fx_type = "xuangui_shield"
		if first_bolt_pos != Vector2.ZERO:
			_tether_target_pos = to_local(first_bolt_pos)
			_tether_progress = 0.0

		if is_inside_tree() and scene_parent != null:
			# 冲击环去噪：收拢横跨全屏的 240px 超大金环，只在拦到弹丸时放紧凑金环（半径 0.40，时长 0.18s）
			if intercepted_count > 0:
				JuiceEffect.spawn_shockwave(scene_parent, center, radius * 0.40, GameStyle.AURUM, 0.18)
			if shield_granted:
				DamageNumber.spawn(scene_parent, center + Vector2(0, -22), 0, false, "玄甲护体")
			elif intercepted_count > 0:
				DamageNumber.spawn(scene_parent, center + Vector2(0, -14), 0, false, "抵挡")

		AudioManager.play_sfx("impact_blunt", 0.5, 1.35)

## 玉露鹿：甘霖回春与生机加成
func _act_yulu() -> void:
	if target == null:
		return
	var heal_amt := BalanceSpiritPet.heal_value(target.max_health, GameManager.pet_effect_mult)
	var before := target.current_health
	target.heal(heal_amt, true)

	# 生机加速与灵泉感知（移速 + 拾取范围双加成）
	GameManager.buff_move_speed_mult = maxf(GameManager.buff_move_speed_mult, 1.0 + BalanceSpiritPet.YULU_SPEED_BONUS)
	GameManager.buff_pickup_range_mult = maxf(GameManager.buff_pickup_range_mult, 1.0 + BalanceSpiritPet.YULU_PICKUP_BONUS)
	_yulu_buff_timer = BalanceSpiritPet.YULU_BUFF_DURATION

	pulse_trigger_fx(Vector2(1.05, 1.15), 0.10)
	_custom_fx_type = "yulu_dew"
	var scene_parent: Node = get_parent()
	if is_inside_tree() and scene_parent != null:
		JuiceEffect.spawn_shockwave(scene_parent, target.global_position, 28.0, GameStyle.GOOD, 0.18)
		DamageNumber.spawn(scene_parent, target.global_position + Vector2(0, -22), int(heal_amt), false, "+" + str(int(heal_amt)))
	AudioManager.play_sfx("heal", 0.45, 1.25)

## 聚宝蟾：金蟾吐宝（向最近敌人发射飞旋金钱镖，带高质感破空金芒与金币爆散反馈）
func _act_juchan() -> void:
	var nearest := _find_nearest_enemy(340.0)
	if nearest == null:
		return
	var dir := (nearest.global_position - global_position).normalized()
	var eff_mult := _get_effective_damage_mult()
	var dmg := BalanceSpiritPet.coin_damage(GameManager.wave_number, eff_mult)

	var p := BladeProjectile.acquire_or_new(PROJECTILE_SCENE, get_tree().current_scene)
	p.global_position = global_position + dir * 12.0
	p.direction = dir
	p.speed = 400.0
	p.damage = dmg
	p.knockback_base = 65.0
	p.pierce_left = 1
	p.bounce_left = 0
	p.homing_target = nearest
	# 换用金钱镖贴图，启用 ProceduralProjectileRenderer 的 GOLD_COIN 纯矢量飞旋金钱
	p.bullet_texture = BULLET_COIN_TEXTURE
	p.bullet_scale = 0.85
	p.spin = true
	p.activate()
	p.lifetime = 1.1

	# 后坐形变 + 聚宝蟾吐宝碎金特效
	pulse_trigger_fx(Vector2(0.72, 1.38), 0.15)
	_custom_fx_type = "gold_spit"
	_spit_dir = dir
	var scene_parent: Node = get_parent()
	if is_inside_tree() and scene_parent != null:
		JuiceEffect.spawn_impact_pop(scene_parent, global_position + dir * 10.0, Color(1.0, 0.88, 0.35), dir)
		JuiceEffect.spawn_shockwave(scene_parent, global_position + dir * 8.0, 22.0, Color(1.0, 0.85, 0.25, 0.8), 0.18)
	AudioManager.play_sfx("metal_dart", 0.45, 1.25)

## 灵风貂：罡风卷定
func _act_fengdiao() -> void:
	if target == null or not is_instance_valid(target):
		return
	var radius := BalanceSpiritPet.vortex_radius(GameManager.pet_effect_mult)
	var radius_sq := radius * radius
	var eff_mult := _get_effective_damage_mult()
	var dmg := BalanceSpiritPet.vortex_damage(GameManager.wave_number, eff_mult)
	var scene_parent: Node = get_parent()
	var affected: int = 0
	for e in GameManager.live_enemies:
		if not is_instance_valid(e) or not (e is EnemyBase):
			continue
		var en := e as EnemyBase
		if en.dying:
			continue
		var diff := en.global_position - target.global_position
		var dist_sq := diff.length_squared()
		if dist_sq > radius_sq:
			continue
		var dist := sqrt(dist_sq)
		var out_dir := diff / dist if dist > 0.001 else Vector2.DOWN
		var ring_pt := Vector2(out_dir.x, out_dir.y * GameBalance.TARGETING_ELLIPSE_Y_RATIO) * BalanceSpiritPet.MELEE_RING
		var pull_vec := target.global_position + ring_pt - en.global_position
		var travel := pull_vec.length()
		var is_boss := en is BossEnemy
		var elite_scale := 0.55 if en.is_elite else 1.0
		if travel > 12.0:
			pull_vec = pull_vec.normalized() * BalanceSpiritPet.pull_impulse(travel) * elite_scale * (GameBalance.BOSS_KNOCKBACK_RESIST if is_boss else 1.0)
		else:
			pull_vec = Vector2.ZERO
		var dealt: float = dmg * GameManager.elite_damage_mult_for(en)
		en.take_damage(dealt, Vector2.ZERO)
		# 神通钩子（兽群链电 / 灵蕴五行）：罡风直击也在「灵兽直击」口径内
		OnHitEffects.on_pet_hit(self, en, dealt)
		en.apply_vortex_pin(pull_vec, BalanceSpiritPet.pin_duration(elite_scale * en.hit_stun_resist * (0.25 if is_boss else 1.0)))
		# 附加风阻减速
		if en.has_method("apply_chill"):
			en.apply_chill(BalanceSpiritPet.VORTEX_SLOW_PCT, BalanceSpiritPet.VORTEX_SLOW_DURATION)
		affected += 1
		if affected <= 6 and scene_parent != null:
			DamageNumber.spawn(scene_parent, en.global_position + Vector2(0, -14), 0, false, "定")
	if affected > 0:
		pulse_trigger_fx(Vector2(1.15, 1.15), 0.12)
		_spin_angle = 0.0  # 取消本体 720° 自转，避免像穿模失控
		_custom_fx_type = "wind_vortex"
		if is_inside_tree() and scene_parent != null:
			JuiceEffect.spawn_shockwave(scene_parent, target.global_position, BalanceSpiritPet.MELEE_RING * 0.65, Color(0.85, 0.92, 1.0, 0.6), 0.22)
		AudioManager.play_sfx("fan_gust", 0.5, 0.85)

## 磐石猿：掷出巨石远程轰击（石落点范围震伤击退减速，落点结算与碎裂演出在 SpiritPetBoulder）
func _act_shiyuan() -> void:
	var nearest := _find_nearest_enemy(BalanceSpiritPet.BOULDER_RANGE)
	if nearest == null:
		return
	var eff_mult := _get_effective_damage_mult()
	var dmg := BalanceSpiritPet.smash_damage(GameManager.wave_number, eff_mult)
	var radius := BalanceSpiritPet.smash_radius(GameManager.pet_effect_mult)
	var boulder := BOULDER_SCRIPT.new()
	boulder.setup(global_position, nearest.global_position, dmg, radius)
	get_tree().current_scene.add_child(boulder)

	# 掷石后坐 + 扬尘起手
	pulse_trigger_fx(Vector2(0.8, 1.3), 0.14)
	var scene_parent: Node = get_parent()
	if is_inside_tree() and scene_parent != null:
		JuiceEffect.spawn_impact_pop(scene_parent, global_position, Color(0.65, 0.58, 0.52), (nearest.global_position - global_position).normalized())
	AudioManager.play_sfx("whoosh_heavy", 0.5, 0.9)

## 聚宝蟾：回合末产出金币触发视觉动效
func trigger_wave_harvest_fx() -> void:
	pulse_trigger_fx(Vector2(1.5, 0.8), 0.22)
	var scene_parent: Node = get_parent()
	if is_inside_tree() and scene_parent != null:
		JuiceEffect.spawn_pickup_pop(scene_parent, global_position, true)
		JuiceEffect.spawn_shockwave(scene_parent, global_position, 48.0, GameStyle.JADE, 0.35)

func _find_nearest_enemy(max_range: float) -> Node2D:
	var nearest: Node2D = null
	var min_d := max_range * max_range
	for e in GameManager.live_enemies:
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		if e.get(&"dying") == true:
			continue
		var n2d := e as Node2D
		var d := global_position.distance_squared_to(n2d.global_position)
		if d < min_d:
			min_d = d
			nearest = n2d
	return nearest

## 消散：淡出并销毁
func dissolve() -> void:
	if _dying:
		return
	_dying = true
	remove_from_group("spirit_pets")
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2(0.1, 0.1), DISSOLVE_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, DISSOLVE_SEC)
	tw.chain().tween_callback(queue_free)

# ---------------- 程序化精致矢量绘制 ----------------

func _draw() -> void:
	var pulse: float = 0.5 + 0.5 * sin(_age * 3.2 + float(orbit_index))
	var flash_ratio: float = clampf(_flash_timer / 0.15, 0.0, 1.0)
	# 核心尺寸由原来的 7.5px 适度升级至 13.5px，形态清晰生动
	var core_r: float = (13.5 + 1.8 * pulse) * (1.0 + 0.35 * flash_ratio)
	var base_color: Color = pet_def.get("color", Color(0.9, 0.9, 0.9))
	var base_halo: Color = pet_def.get("halo_color", Color(1.0, 1.0, 1.0, 0.35))

	# 闪白提亮：受激/触发时轻微提亮，保留本色，避免持续刺眼过曝
	var color: Color = base_color.lerp(Color.WHITE, flash_ratio * 0.35)
	var halo: Color = base_halo.lerp(Color(1.0, 1.0, 1.0, 0.45), flash_ratio * 0.35)

	# 1. 外层灵光晕（轻灵收敛：避免在玩家头顶形成大团白光遮挡视线）
	var halo_scale: float = 1.35 + 0.25 * flash_ratio
	_circle(Vector2.ZERO, core_r * halo_scale, Color(halo.r, halo.g, halo.b, halo.a * (0.35 + 0.15 * pulse + 0.20 * flash_ratio)))
	# 2. 核心真身
	_circle(Vector2.ZERO, core_r, color)
	# 3. 柔和高光灵瞳（单点轻微提神）
	_circle(Vector2(-core_r * 0.28, -core_r * 0.32), core_r * 0.32, Color(1.0, 1.0, 1.0, 0.45))

	# 4. 特征部件（精细化绘制）
	var decor: String = String(pet_def.get("decor", ""))
	_draw_decor(decor, core_r, color)

	# 5. 法力连线
	if _tether_progress >= 0.0 and _tether_target_pos != Vector2.ZERO:
		var tether_alpha: float = 1.0 - _tether_progress
		var tether_col: Color = GameStyle.AURUM
		tether_col.a = tether_alpha * 0.9
		draw_line(Vector2.ZERO, _tether_target_pos, tether_col, 2.8 * tether_alpha)
		draw_line(Vector2.ZERO, _tether_target_pos, Color(1.0, 1.0, 1.0, tether_alpha * 0.95), 1.2 * tether_alpha)
		_circle(_tether_target_pos * 0.5, 3.2 * tether_alpha, tether_col)
		_circle(_tether_target_pos, 4.0 * tether_alpha, Color(1.0, 1.0, 1.0, tether_alpha))

		# 6. 行动与专属特效（按灵兽各自特征绘制，2026-10-20 七只统一打磨）
		if _action_fx >= 0.0:
			if _lightning_target_pos != Vector2.ZERO:
				# 主雷电电弧
				_draw_lightning_arc(Vector2.ZERO, _lightning_target_pos, 1.0 - _action_fx)
				# 连锁分支电弧
				for cp in _chain_targets_pos:
					_draw_lightning_arc(_lightning_target_pos, cp, (1.0 - _action_fx) * 0.8)
				# 命中点十字闪光（雷灵雀专属）
				_draw_fx_thunder_hit(_lightning_target_pos, 1.0 - _action_fx)
			elif _custom_fx_type == "wind_vortex":
				# 灵风气旋双螺旋 + 外圈风刃刻线
				var wind_r: float = lerpf(core_r * 1.5, core_r * 4.2, _action_fx)
				var wind_alpha: float = (1.0 - _action_fx) * 0.85
				_arc(Vector2.ZERO, wind_r, _age * 12.0, _age * 12.0 + PI * 1.2, 24, Color(0.85, 0.92, 1.0, wind_alpha), 2.4)
				_arc(Vector2.ZERO, wind_r * 0.72, -_age * 10.0, -_age * 10.0 + PI * 1.2, 24, Color(0.7, 0.85, 1.0, wind_alpha * 0.75), 1.8)
				_draw_fx_wind_blades(wind_r, wind_alpha)
			elif _custom_fx_type == "fire_burst":
				# 焰灵狐：吐火朝向的锥形扇焰 + 余烬飞点
				_draw_fx_fire(local_fire_dir(), 1.0 - _action_fx, core_r)
			elif _custom_fx_type == "gold_spit":
				# 聚宝蟾：吐金宝朝向的金色扇弧 + 飞溅金星灵屑
				_draw_fx_gold_spit(local_spit_dir(), 1.0 - _action_fx, core_r)
			elif _custom_fx_type == "yulu_dew":
				# 玉露鹿：甘霖雨丝下落 + 地面上升绿色光点
				_draw_fx_yulu_dew(1.0 - _action_fx, core_r)
			elif _custom_fx_type == "xuangui_shield":
				# 玄甲龟：六边形龟甲盾纹闪光
				_draw_fx_turtle_shield(1.0 - _action_fx, core_r)
			else:
				# 保底：轻柔单层扩散波纹环
				var ring_r: float = lerpf(core_r, core_r * 2.2, _action_fx)
				var ring_alpha: float = (1.0 - _action_fx) * 0.65
				_arc(Vector2.ZERO, ring_r, 0.0, TAU, 28, Color(color.r, color.g, color.b, ring_alpha), 1.4)

## 焰灵狐吐火朝向（本地坐标；无朝向时默认朝下偏右）
func local_fire_dir() -> Vector2:
	if _fire_dir == Vector2.ZERO:
		return Vector2(0.7, 1.0).normalized()
	return _fire_dir

## 聚宝蟾吐金宝朝向（本地坐标；无朝向时默认朝下偏右）
func local_spit_dir() -> Vector2:
	if _spit_dir == Vector2.ZERO:
		return Vector2(0.7, 0.8).normalized()
	return _spit_dir

## 焰灵狐：锥形扇焰 + 余烬飞点
func _draw_fx_fire(dir: Vector2, prog: float, core_r: float) -> void:
	var base_ang := dir.angle()
	var reach: float = core_r + lerpf(6.0, core_r * 2.6, prog)
	var spread := deg_to_rad(26.0)
	for layer in [[reach, Color(1.0, 0.42, 0.12, 0.55 * (1.0 - prog)), 6], [reach * 0.66, Color(1.0, 0.86, 0.35, 0.75 * (1.0 - prog)), 5]]:
		var r_len: float = layer[0]
		var col: Color = layer[1]
		var seg: int = layer[2]
		var pts := PackedVector2Array([Vector2.ZERO])
		for i in range(seg + 1):
			var a: float = base_ang - spread + (2.0 * spread) * float(i) / float(seg)
			var jag: float = 1.0 + 0.18 * sin(_age * 22.0 + float(i) * 1.7)
			pts.append(Vector2(cos(a), sin(a)) * r_len * jag)
		draw_colored_polygon(pts, col)
	# 余烬飞点
	var ember_col := Color(1.0, 0.72, 0.25, 0.9 * (1.0 - prog))
	for k in range(3):
		var t_f: float = prog + float(k) * 0.18
		var off: float = lerpf(core_r * 0.6, reach * 1.15, t_f)
		var tang := Vector2(cos(base_ang + PI * 0.5), sin(base_ang + PI * 0.5))
		var p: Vector2 = dir * off + tang * sin(_age * 8.0 + float(k) * 2.1) * 4.0 * t_f
		_circle(p, maxf(0.6, 2.2 * (1.0 - t_f)), ember_col)

## 聚宝蟾：金蟾吐宝灵光特效（喷吐金芒扇弧 + 飞溅金星灵屑）
func _draw_fx_gold_spit(dir: Vector2, prog: float, core_r: float) -> void:
	var base_ang := dir.angle()
	var reach: float = core_r + lerpf(4.0, core_r * 2.4, prog)
	var alpha: float = (1.0 - prog) * 0.95

	# 1. 吐宝金色灵环弧面（喷吐金光波）
	var spread := deg_to_rad(30.0)
	var pts := PackedVector2Array([Vector2.ZERO])
	var seg := 8
	for i in range(seg + 1):
		var a: float = base_ang - spread + (2.0 * spread) * float(i) / float(seg)
		pts.append(Vector2(cos(a), sin(a)) * reach)
	draw_colored_polygon(pts, Color(1.0, 0.88, 0.35, alpha * 0.40))

	# 2. 喷射外沿流金锋芒弧线
	var arc_pts := PackedVector2Array()
	for i in range(seg + 1):
		var a2: float = base_ang - spread + (2.0 * spread) * float(i) / float(seg)
		arc_pts.append(Vector2(cos(a2), sin(a2)) * (reach * 1.06))
	draw_polyline(arc_pts, Color(1.0, 0.96, 0.65, alpha * 0.9), 1.6)

	# 3. 飞溅招财碎金星尘（向吐出方向外扬）
	var coin_spark_col := Color(1.0, 0.88, 0.30, alpha)
	for k in range(4):
		var t_f: float = prog + float(k) * 0.16
		var off: float = lerpf(core_r * 0.5, reach * 1.25, t_f)
		var perp_ang := base_ang + PI * 0.5
		var tang := Vector2(cos(perp_ang), sin(perp_ang))
		var offset_side := sin(_age * 12.0 + float(k) * 2.3) * (3.0 + 2.5 * float(k))
		var p: Vector2 = dir * off + tang * offset_side
		_circle(p, maxf(0.8, 2.2 * (1.0 - t_f)), coin_spark_col)

## 玉露鹿：甘霖雨丝 + 上升绿色光点
func _draw_fx_yulu_dew(prog: float, core_r: float) -> void:
	var alpha: float = (1.0 - prog)
	for k in range(7):
		var ang: float = TAU * float(k) / 7.0 + float(orbit_index)
		var rad: float = core_r * (1.1 + 0.5 * float(k % 3))
		var cx: float = cos(ang) * rad
		var fall: float = fposmod(_age * 90.0 + float(k) * 37.0, 46.0)
		var y0: float = -core_r * 1.6 + fall
		draw_line(Vector2(cx, y0), Vector2(cx, y0 + 7.0), Color(0.7, 1.0, 0.85, alpha * 0.6), 1.2)
	for k in range(5):
		var ang2: float = TAU * float(k) / 5.0 - float(orbit_index)
		var rad2: float = core_r * (0.8 + 0.6 * prog)
		var rise: float = (1.0 - prog) * 10.0
		_circle(Vector2(cos(ang2) * rad2, core_r * 0.8 - rise), maxf(0.6, 2.4 * (1.0 - prog)), Color(0.62, 1.0, 0.72, alpha * 0.85))

## 玄甲龟：六边形龟甲盾纹闪光
func _draw_fx_turtle_shield(prog: float, core_r: float) -> void:
	var alpha: float = (1.0 - prog)
	var hr: float = core_r * (1.4 + 1.1 * prog)
	var hex := PackedVector2Array()
	for k in range(7):
		var a: float = TAU * float(k) / 6.0 - PI * 0.5
		hex.append(Vector2(cos(a), sin(a)) * hr)
	draw_polyline(hex, Color(0.45, 0.85, 0.95, alpha * 0.9), 2.2)
	for k in range(6):
		var a2: float = TAU * float(k) / 6.0 - PI * 0.5
		draw_line(Vector2.ZERO, Vector2(cos(a2), sin(a2)) * hr, Color(0.5, 0.9, 1.0, alpha * 0.5), 1.2)
	_circle(Vector2.ZERO, maxf(0.8, core_r * 0.35 * (1.0 - prog)), Color(0.85, 0.97, 1.0, alpha * 0.8))

## 雷灵雀：命中点十字闪光
func _draw_fx_thunder_hit(pos: Vector2, prog: float) -> void:
	var alpha: float = prog
	var l: float = 7.0 * prog + 3.0
	draw_line(pos + Vector2(-l, 0), pos + Vector2(l, 0), Color(0.9, 0.85, 1.0, alpha), 2.0)
	draw_line(pos + Vector2(0, -l), pos + Vector2(0, l), Color(0.9, 0.85, 1.0, alpha), 2.0)
	_circle(pos, maxf(0.8, 5.0 * prog), Color(1.0, 1.0, 1.0, alpha * 0.8))

## 灵风貂：外圈风刃刻线
func _draw_fx_wind_blades(radius: float, alpha: float) -> void:
	for k in range(6):
		var a: float = TAU * float(k) / 6.0 + _age * 9.0
		var p0: Vector2 = Vector2(cos(a), sin(a)) * radius
		var p1: Vector2 = Vector2(cos(a + 0.35), sin(a + 0.35)) * (radius * 0.72)
		draw_line(p0, p1, Color(0.9, 0.96, 1.0, alpha * 0.8), 1.6)

func _draw_lightning_arc(start_pt: Vector2, end_pt: Vector2, alpha: float) -> void:
	var mid := (start_pt + end_pt) * 0.5
	var perp := (end_pt - start_pt).orthogonal().normalized() * 8.0 * sin(_age * 30.0)
	var p1 := start_pt.lerp(mid, 0.6) + perp
	var p2 := mid.lerp(end_pt, 0.4) - perp * 0.7
	var points := PackedVector2Array([start_pt, p1, p2, end_pt])
	draw_polyline(points, Color(0.68, 0.58, 1.0, alpha * 0.95), 3.2)
	draw_polyline(points, Color(1.0, 1.0, 1.0, alpha * 0.9), 1.4)

func _draw_decor(decor: String, r: float, color: Color) -> void:
	match decor:
		"fox_ears_tail":
			# 灵狐：对称尖耳（外耳金红、内耳粉白）+ 对称双焰尾 + 额头朱砂
			var ear_l := PackedVector2Array([Vector2(-r * 0.65, -r * 0.4), Vector2(-r * 0.95, -r * 1.35), Vector2(-r * 0.2, -r * 0.85)])
			var ear_r := PackedVector2Array([Vector2(r * 0.2, -r * 0.85), Vector2(r * 0.95, -r * 1.35), Vector2(r * 0.65, -r * 0.4)])
			draw_colored_polygon(ear_l, color.darkened(0.12))
			draw_colored_polygon(ear_r, color.darkened(0.12))
			# 内耳粉白微光
			var in_ear_l := PackedVector2Array([Vector2(-r * 0.6, -r * 0.5), Vector2(-r * 0.85, -r * 1.2), Vector2(-r * 0.3, -r * 0.8)])
			var in_ear_r := PackedVector2Array([Vector2(r * 0.3, -r * 0.8), Vector2(r * 0.85, -r * 1.2), Vector2(r * 0.6, -r * 0.5)])
			draw_colored_polygon(in_ear_l, Color(1.0, 0.82, 0.75))
			draw_colored_polygon(in_ear_r, Color(1.0, 0.82, 0.75))
			# 额前朱砂焰火印
			_circle(Vector2(0, -r * 0.55), r * 0.16, Color(1.0, 0.25, 0.15))
			# 对称双焰尾（左右各一条舒展扬起的焰尾，反相轻摇）
			for side in [-1.0, 1.0]:
				var tail_sway := sin(_age * 3.5 + (0.0 if side < 0.0 else PI * 0.5)) * (r * 0.25)
				var tc := Vector2(side * r * 1.10, r * 0.48 + tail_sway)
				_circle(tc, r * 0.46, color.lightened(0.15))
				_circle(tc + Vector2(side * r * 0.36, -r * 0.20), r * 0.30, Color(1.0, 0.85, 0.35))
				_circle(tc + Vector2(side * r * 0.58, -r * 0.35), r * 0.16, Color(1.0, 0.95, 0.60))

		"bird_crest_beak":
			# 雷灵雀：对称三羽羽冠 + 对称双翼弧 + 居中雷纹额印
			var crest_sway := sin(_age * 4.2) * (r * 0.06)
			draw_line(Vector2(0, -r), Vector2(crest_sway, -r * 1.7), Color(1.0, 0.92, 0.4), 2.4)
			draw_line(Vector2(-3, -r), Vector2(-6 + crest_sway, -r * 1.45), Color(1.0, 0.85, 0.35), 1.8)
			draw_line(Vector2(3, -r), Vector2(6 + crest_sway, -r * 1.45), Color(1.0, 0.85, 0.35), 1.8)
			# 羽梢莹光三点
			_circle(Vector2(crest_sway, -r * 1.7), 1.0, Color(1.0, 0.95, 0.6, 0.85))
			_circle(Vector2(-6 + crest_sway, -r * 1.45), 0.8, Color(1.0, 0.95, 0.6, 0.7))
			_circle(Vector2(6 + crest_sway, -r * 1.45), 0.8, Color(1.0, 0.95, 0.6, 0.7))
			# 灵雀对称双翼轮廓（随扑翼起伏）
			var wing_flap := sin(_age * 5.0) * (r * 0.15)
			_arc(Vector2(-r * 0.6, 0), r * 0.65 + wing_flap, PI * 0.7, PI * 1.4, 12, Color(0.8, 0.75, 1.0), 2.0)
			_arc(Vector2(r * 0.6, 0), r * 0.65 + wing_flap, -PI * 0.4, PI * 0.3, 12, Color(0.8, 0.75, 1.0), 2.0)
			# 居中雷纹额印（菱形象征雷符，替代侧向喙）
			draw_colored_polygon(PackedVector2Array([
				Vector2(0, -r * 0.55), Vector2(r * 0.14, -r * 0.32),
				Vector2(0, -r * 0.09), Vector2(-r * 0.14, -r * 0.32)
			]), Color(1.0, 0.88, 0.35))

		"turtle_shell":
			# 玄甲龟：青甲八卦背壳 + 金色六边形环纹 + 对称四小足
			_arc(Vector2.ZERO, r * 0.75, 0.0, TAU, 8, color.darkened(0.4), 2.2)
			_arc(Vector2.ZERO, r * 0.45, 0.0, TAU, 6, Color(1.0, 0.85, 0.35, 0.75), 1.8)
			draw_line(Vector2(-r * 0.75, 0), Vector2(r * 0.75, 0), color.darkened(0.35), 1.4)
			draw_line(Vector2(0, -r * 0.75), Vector2(0, r * 0.75), color.darkened(0.35), 1.4)
			# 对称四小足（替代原右侧头凸，整体对称化）
			for fp in [Vector2(-r * 0.85, -r * 0.35), Vector2(r * 0.85, -r * 0.35), Vector2(-r * 0.85, r * 0.45), Vector2(r * 0.85, r * 0.45)]:
				_circle(fp, r * 0.18, color.lightened(0.1))
			# 壳心甲珠（呼吸微光）
			_circle(Vector2.ZERO, r * 0.14, Color(1.0, 0.92, 0.5, 0.6 + 0.3 * sin(_age * 3.0)))

		"deer_horns":
			# 玉露鹿：对称珊瑚玉角 + 角尖发光玉珠 + 额心露印
			draw_line(Vector2(-r * 0.5, -r * 0.6), Vector2(-r * 0.85, -r * 1.55), color.darkened(0.2), 2.2)
			draw_line(Vector2(-r * 0.7, -r * 1.1), Vector2(-r * 1.1, -r * 1.25), color.darkened(0.2), 1.8)
			draw_line(Vector2(r * 0.5, -r * 0.6), Vector2(r * 0.85, -r * 1.55), color.darkened(0.2), 2.2)
			draw_line(Vector2(r * 0.7, -r * 1.1), Vector2(r * 1.1, -r * 1.25), color.darkened(0.2), 1.8)
			# 角尖发光玉珠
			_circle(Vector2(-r * 0.85, -r * 1.55), 2.2, Color(1.0, 0.88, 0.9))
			_circle(Vector2(r * 0.85, -r * 1.55), 2.2, Color(1.0, 0.88, 0.9))
			_circle(Vector2(-r * 1.1, -r * 1.25), 1.8, Color(1.0, 0.88, 0.9))
			_circle(Vector2(r * 1.1, -r * 1.25), 1.8, Color(1.0, 0.88, 0.9))
			# 额心露印（水滴莹光，呼吸明灭）
			_circle(Vector2(0, -r * 0.45), r * 0.13, Color(0.85, 1.0, 0.9, 0.6 + 0.3 * sin(_age * 2.8)))

		"toad_coin":
			# 聚宝蟾：头顶居中灿金小元宝 + 对称金肚弧 + 对称铜钱光点
			_circle(Vector2(0, -r * 1.05), r * 0.45, Color(1.0, 0.88, 0.25))
			_circle(Vector2(0, -r * 1.05), r * 0.20, Color(1.0, 0.96, 0.6, 0.9))
			# 招财金圆肚弧线
			_arc(Vector2(0, r * 0.2), r * 0.6, 0.1 * PI, 0.9 * PI, 12, Color(1.0, 0.92, 0.4), 2.0)
			# 对称铜钱光点（左右各一，明灭闪烁）
			var coin_a := 0.5 + 0.4 * sin(_age * 3.4)
			_circle(Vector2(-r * 0.55, r * 0.05), r * 0.13, Color(1.0, 0.90, 0.35, coin_a))
			_circle(Vector2(r * 0.55, r * 0.05), r * 0.13, Color(1.0, 0.90, 0.35, coin_a))

		"mink_tail":
			# 灵风貂：对称双流风尾（左右各一条流线摆尾，替代原单侧三圆尾）
			for side in [-1.0, 1.0]:
				var sway := sin(_age * 4.0 + (0.0 if side < 0.0 else PI * 0.6)) * (r * 0.18)
				_circle(Vector2(side * r * 0.85, r * 0.5 + sway), r * 0.44, color.lightened(0.12))
				_circle(Vector2(side * r * 1.35, r * 0.32 + sway * 1.3), r * 0.34, color.lightened(0.2))
				_circle(Vector2(side * r * 1.75, r * 0.10 + sway * 1.6), r * 0.22, Color(1.0, 1.0, 1.0, 0.9))
			# 额心风纹印
			_arc(Vector2(0, -r * 0.35), r * 0.22, PI * 1.15, PI * 1.85, 8, Color(0.85, 0.92, 1.0, 0.85), 1.4)

		"ape_brows":
			# 磐石猿：威猛红纹石眉 + 古代护额金刚箍 + 居中额印
			_arc(Vector2(0, -r * 0.5), r * 0.75, PI * 1.1, PI * 1.9, 12, Color(1.0, 0.85, 0.35), 2.4)
			# 刚劲重眉
			draw_line(Vector2(-r * 0.7, -r * 0.2), Vector2(-0.8, -r * 0.4), color.darkened(0.45), 2.6)
			draw_line(Vector2(0.8, -r * 0.4), Vector2(r * 0.7, -r * 0.2), color.darkened(0.45), 2.6)
			# 居中额印（山岳菱纹，沉稳呼吸）
			var brow_a := 0.6 + 0.3 * sin(_age * 2.4)
			draw_colored_polygon(PackedVector2Array([
				Vector2(0, -r * 0.62), Vector2(r * 0.12, -r * 0.44),
				Vector2(0, -r * 0.26), Vector2(-r * 0.12, -r * 0.44)
			]), Color(1.0, 0.88, 0.45, brow_a))

