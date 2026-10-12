class_name SpiritPet
extends Node2D

## 灵兽（随行伙伴）实体：纯 _draw 程序化光灵 + 小部件区分，无碰撞体，跨波存活
## 铁律：只挂 "spirit_pets" 组，绝不进 enemies/turrets/gems/chests 四个波末清场组。
## 多个灵兽通过 orbit_index 均分绕飘相位，视觉各自舒展不重叠。

const FOLLOW_DIST: float = 38.0     ## 跟随绕飘半径（px）
const HEIGHT_OFFSET: float = 28.0   ## 悬在玩家头顶上方（px）
const DISSOLVE_SEC: float = 0.35    ## 出售/移除时的消散时长（秒）

const BULLET_TEXTURE = preload("res://assets/art/bullet_spirit_pellet.png")
const PROJECTILE_SCENE = preload("res://scenes/weapons/BladeProjectile.tscn")

var pet_id: String = ""             ## 灵兽 id（见 PetData）
var pet_def: Dictionary = {}
var orbit_index: int = 0            ## 在已购灵兽队列里的序号（0, 1, 2）
var total_pets: int = 1             ## 当前总灵兽数（均分相位用）
var target: Player = null           ## 随行主人

var _age: float = 0.0
var _cooldown_timer: float = 1.0    ## 首跳延迟 1 秒，平稳入场
var _dying: bool = false
var _action_fx: float = -1.0        ## 脉冲/动作特效进度（0~1，<0 为无）
var _lightning_target_pos: Vector2 = Vector2.ZERO ## 雷击特效终点（相对本地坐标）

func _ready() -> void:
	add_to_group("spirit_pets")
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
	queue_redraw()

func _physics_process(delta: float) -> void:
	if _dying:
		return
	if target == null or not is_instance_valid(target):
		# 主人可能未初始化或正在场景切换，从 GameManager 寻找
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

	# 战斗行为（非终局、非暂停时按冷却心跳推进）
	if not GameManager.is_game_over and not get_tree().paused:
		_tick_behavior(delta)

	queue_redraw()

func _tick_behavior(delta: float) -> void:
	var base_cd: float = float(pet_def.get("base_cooldown", 0.0))
	if base_cd <= 0.0:
		return  # 经济类等被动触发型灵兽走事件驱动
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
		"fengdiao":
			_act_fengdiao()
		"shiyuan":
			_act_shiyuan()

## 焰灵狐：追踪火丹
func _act_yanhu() -> void:
	var nearest := _find_nearest_enemy(320.0)
	if nearest == null:
		return
	var dir := (nearest.global_position - global_position).normalized()
	var dmg := BalanceSpiritPet.fire_damage(GameManager.wave_number, GameManager.pet_damage_mult)
	var p := BladeProjectile.acquire_or_new(PROJECTILE_SCENE, get_tree().current_scene)
	p.global_position = global_position + dir * 8.0
	p.direction = dir
	p.speed = 360.0
	p.damage = dmg
	p.knockback_base = 50.0
	p.pierce_left = 1
	p.bounce_left = 0
	p.homing_target = nearest
	p.bullet_texture = BULLET_TEXTURE
	p.bullet_scale = 0.55
	p.spin = false
	p.activate()
	p.lifetime = 1.0
	_action_fx = 0.0
	AudioManager.play_sfx("blade_shoot", 0.35, 1.15)

## 雷灵雀：高伤雷击
func _act_leique() -> void:
	var nearest := _find_nearest_enemy(280.0)
	if nearest == null:
		return
	var dmg := BalanceSpiritPet.thunder_damage(GameManager.wave_number, GameManager.pet_damage_mult)
	if nearest.has_method("take_damage"):
		nearest.take_damage(dmg, Vector2.ZERO, true)
	_lightning_target_pos = to_local(nearest.global_position)
	_action_fx = 0.0
	AudioManager.play_sfx("hit_thunder", 0.45, 1.2)

## 玄甲龟：拦截飞行物
func _act_xuangui() -> void:
	var bolts := get_tree().get_nodes_in_group("enemy_bolts")
	if bolts.is_empty():
		return
	var radius := BalanceSpiritPet.intercept_radius(GameManager.pet_effect_mult)
	var radius_sq := radius * radius
	# 以玩家或玄龟为中心，优先拦截威胁最大的飞行物
	var center := target.global_position if target != null else global_position
	var candidate: Node = null
	var min_d: float = radius_sq
	for b in bolts:
		if not is_instance_valid(b) or not (b is Node2D):
			continue
		var n2d := b as Node2D
		if not n2d.visible:
			continue
		var d := center.distance_squared_to(n2d.global_position)
		if d < min_d:
			min_d = d
			candidate = b
	if candidate != null:
		if candidate.has_method("intercept"):
			candidate.intercept()
		elif candidate.has_method("_recycle"):
			candidate._recycle()
		_action_fx = 0.0
		AudioManager.play_sfx("parry", 0.4, 1.1)

## 玉露鹿：气血回复
func _act_yulu() -> void:
	if target == null:
		return
	var ratio := BalanceSpiritPet.heal_ratio(GameManager.pet_effect_mult)
	var heal_amt := target.max_health * ratio
	var before := target.current_health
	target.heal(heal_amt, true)
	var gained := target.current_health - before
	if gained > 0.01:
		_action_fx = 0.0
		DamageNumber.spawn(get_parent(), target.global_position + Vector2(0, -22), int(gained), false, "+" + str(int(gained)))

## 灵风貂：磁吸掉落物
func _act_fengdiao() -> void:
	var radius := BalanceSpiritPet.magnet_radius(GameManager.pet_effect_mult)
	var gems := get_tree().get_nodes_in_group("gems")
	var pulled := 0
	for g in gems:
		if not is_instance_valid(g) or not (g is Node2D):
			continue
		var n2d := g as Node2D
		if global_position.distance_to(n2d.global_position) <= radius:
			if g.has_method("magnet_to") and target != null:
				g.magnet_to(target)
				pulled += 1
	if pulled > 0:
		_action_fx = 0.0
		AudioManager.play_sfx("pickup_gem", 0.3, 1.25)

## 磐石猿：击退与震击
func _act_shiyuan() -> void:
	var dmg := BalanceSpiritPet.smash_damage(GameManager.wave_number, GameManager.pet_damage_mult)
	var radius := 110.0 * maxf(0.5, GameManager.pet_effect_mult)
	var hit := false
	for e in GameManager.live_enemies:
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		if e.get("dying") == true:
			continue
		var n2d := e as Node2D
		var diff := n2d.global_position - global_position
		if diff.length() <= radius:
			var kb_dir := diff.normalized() if diff.length() > 0.1 else Vector2.RIGHT
			if e.has_method("take_damage"):
				e.take_damage(dmg, kb_dir * 180.0, false)
				hit = true
	if hit:
		_action_fx = 0.0
		AudioManager.play_sfx("hit_heavy", 0.4, 0.95)

## 聚宝蟾：波末产出灵石（由波末信号调用）
func harvest_wave_end() -> int:
	if pet_id != "juchan":
		return 0
	var stones := BalanceSpiritPet.harvest_stones(GameManager.wave_number, GameManager.pet_effect_mult)
	GameManager.add_spirit_stones(stones)
	_action_fx = 0.0
	AudioManager.play_sfx("chest_open", 0.4, 1.2)
	return stones

func _find_nearest_enemy(max_range: float) -> Node2D:
	var nearest: Node2D = null
	var min_d := max_range * max_range
	for e in GameManager.live_enemies:
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		if e.get("dying") == true:
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

# ---------------- 程序化绘制 ----------------

func _draw() -> void:
	var pulse := 0.5 + 0.5 * sin(_age * 3.0 + float(orbit_index))
	var core_r: float = 7.5 + 1.2 * pulse
	var color: Color = pet_def.get("color", Color(0.9, 0.9, 0.9))
	var halo: Color = pet_def.get("halo_color", Color(1.0, 1.0, 1.0, 0.3))

	# 1. 外晕
	draw_circle(Vector2.ZERO, core_r * 2.4, Color(halo.r, halo.g, halo.b, halo.a * (0.6 + 0.4 * pulse)))
	# 2. 中晕
	draw_circle(Vector2.ZERO, core_r * 1.5, Color(color.r, color.g, color.b, 0.35))
	# 3. 核心
	draw_circle(Vector2.ZERO, core_r, color)
	# 4. 高光
	draw_circle(Vector2(-1.8, -2.5), core_r * 0.4, Color(1.0, 1.0, 1.0, 0.85))

	# 5. 特征部件
	var decor: String = String(pet_def.get("decor", ""))
	_draw_decor(decor, core_r, color)

	# 6. 行动特效（波纹或雷弧）
	if _action_fx >= 0.0:
		if _lightning_target_pos != Vector2.ZERO:
			# 雷弧短闪
			var points := PackedVector2Array([
				Vector2.ZERO,
				_lightning_target_pos * 0.35 + Vector2(randf_range(-6, 6), randf_range(-6, 6)),
				_lightning_target_pos * 0.7 + Vector2(randf_range(-6, 6), randf_range(-6, 6)),
				_lightning_target_pos
			])
			draw_polyline(points, Color(0.85, 0.82, 1.0, 1.0 - _action_fx), 2.5)
		else:
			# 扩散波纹环
			var ring_r := lerpf(core_r, core_r * 3.4, _action_fx)
			draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 32, Color(color.r, color.g, color.b, 1.0 - _action_fx), 1.8)

func _draw_decor(decor: String, r: float, color: Color) -> void:
	match decor:
		"fox_ears_tail":
			# 尖耳 + 尾巴
			var ear_l := PackedVector2Array([Vector2(-r * 0.6, -r * 0.5), Vector2(-r * 0.9, -r * 1.4), Vector2(-r * 0.1, -r * 0.8)])
			var ear_r := PackedVector2Array([Vector2(r * 0.1, -r * 0.8), Vector2(r * 0.9, -r * 1.4), Vector2(r * 0.6, -r * 0.5)])
			draw_colored_polygon(ear_l, color.darkened(0.1))
			draw_colored_polygon(ear_r, color.darkened(0.1))
			# 小绒尾
			draw_circle(Vector2(r * 0.9, r * 0.6), r * 0.45, color.lightened(0.15))
		"bird_crest_beak":
			# 羽冠 + 小喙
			draw_line(Vector2(0, -r), Vector2(0, -r * 1.7), Color(1.0, 0.9, 0.4), 2.0)
			draw_line(Vector2(-2, -r), Vector2(-4, -r * 1.5), Color(1.0, 0.9, 0.4), 1.5)
			draw_colored_polygon(PackedVector2Array([Vector2(r * 0.5, -1), Vector2(r * 1.2, 0), Vector2(r * 0.5, 1.5)]), Color(1.0, 0.8, 0.2))
		"turtle_shell":
			# 背壳环纹
			draw_arc(Vector2.ZERO, r * 0.7, 0.0, TAU, 6, color.darkened(0.35), 1.6)
		"deer_horns":
			# 茸角
			draw_line(Vector2(-r * 0.5, -r * 0.7), Vector2(-r * 0.9, -r * 1.5), color.darkened(0.2), 2.0)
			draw_line(Vector2(r * 0.5, -r * 0.7), Vector2(r * 0.9, -r * 1.5), color.darkened(0.2), 2.0)
			draw_circle(Vector2(-r * 0.9, -r * 1.5), 1.6, Color(1.0, 0.8, 0.8))
			draw_circle(Vector2(r * 0.9, -r * 1.5), 1.6, Color(1.0, 0.8, 0.8))
		"toad_coin":
			# 头顶铜钱/元宝
			draw_circle(Vector2(0, -r * 1.05), r * 0.4, Color(1.0, 0.9, 0.3))
			draw_rect(Rect2(-1.2, -r * 1.05 - 1.2, 2.4, 2.4), color.darkened(0.3))
		"mink_tail":
			# 蓬松长尾
			draw_circle(Vector2(-r * 0.8, r * 0.5), r * 0.5, color.lightened(0.1))
			draw_circle(Vector2(-r * 1.3, r * 0.3), r * 0.35, color.lightened(0.2))
		"ape_brows":
			# 浓眉
			draw_line(Vector2(-r * 0.7, -r * 0.3), Vector2(-0.5, -r * 0.45), color.darkened(0.4), 2.0)
			draw_line(Vector2(0.5, -r * 0.45), Vector2(r * 0.7, -r * 0.3), color.darkened(0.4), 2.0)
