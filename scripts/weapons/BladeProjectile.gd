class_name BladeProjectile
extends Area2D

## 法器弹丸：伤害由 FloatingWeapon 计算好后直接传入，支持锁定追踪、穿透、弹射连锁与五行异常

## 追踪转向速率（rad/s）。弹速 470 ÷ 3.6 ⇒ 最小转弯半径约 130px：看得见符在拐，但不是制导导弹。
## 为什么要追踪（2026-10-08 用户口径：「火符比其他武器要弱很多」）：
## 旧写法直线飞行、不预判不锁敌，弹丸飞 0.5 秒的时间里敌人已经横移七八十个像素，
## 而判定只有 7px + 敌人受击圈 15px —— 离线仿真（弹速/判定/寿命全取运行时真值）给出
## 200px 命中 33%、350px 以上只剩 11%、雷兽横切冲刺 0%。
## 近战挥扫是当帧结算、环绕法宝是接触即伤，都没有这笔隐形税 —— 远程纸面 DPS 打不出来就是假的。
## 留白的部分：400px 外打冲刺中的雷兽仍只有三成命中，高速怪的走位克制要保住。
const HOMING_TURN_RATE := 3.6
## 锁定目标中途暴毙后「另找最近的生气」的选择半径；只认弹头前方锥内的敌人，不许掉头 180° 追人
const HOMING_ACQUIRE_RADIUS := 240.0
const HOMING_ACQUIRE_AHEAD := 0.30        ## dot(弹向, 目标方位) 低于这个值就不算"在前方"
const BOUNCE_SEARCH_RADIUS := 260.0       ## 弹射连锁的找下家半径（沿用历史值）
## 仅判据用：整体缩放转向速率（tests/ProjectileProbe.tscn 的 `-- --no-homing` 置 0 退回旧直线弹），
## 用来证明"命中率"这条断言真的有牙齿。运行时永远是 1.0。
static var homing_scale: float = 1.0
## 复用物理查询形状与参数，杜绝每帧弹丸重寻目标时 new CircleShape2D / PhysicsShapeQueryParameters2D
static var _search_shape: CircleShape2D = null
static var _search_query: PhysicsShapeQueryParameters2D = null
static var query_alloc_count: int = 0
static var query_reuse_count: int = 0

var direction: Vector2 = Vector2.RIGHT
var speed: float = 470.0
var damage: float = 20.0
var knockback_base: float = 140.0
var lifetime: float = 1.6
var pierce_left: int = 1
var bounce_left: int = 0
var spin: bool = true
## 这一发咬定的敌人：开火时由 FloatingWeapon 逐发分配（一次三发的法器各锁一个，不扎堆）
var homing_target: Node2D = null
## 弹丸外观按法器归位（2026-10-08 用户口径：「发出来一个不知道什么样的东西，火焰符就发出火」）：
## 旧写法五把远程法器共用 BladeProjectile.tscn 里那张 blade.png（一张燃烧的符箓）——
## 飞剑、飞刀、冰针打出去的全是火符。现在由 WeaponData 的 bullet / bullet_scale / bullet_spin 逐件指定。
## 画布尺寸 == 屏上像素（Nearest、不缩放），贴图一律朝右，飞行时随 direction 转向。
var bullet_texture: Texture2D = null
var bullet_scale: float = 1.0
## 还能"另找目标"几次：命中过一次就归零 —— 穿透的语义是"一条线穿过去"，不是"拐回来再穿一遍"
var acquire_left: int = 1

# 五行异常触发
var proc_burn: bool = false
var burn_dps: float = 0.0
var burn_dur: float = 3.0
var proc_chill: float = 0.0
var chill_dur: float = 2.0
var proc_poison: bool = false
var poison_dps: float = 0.0
var poison_dur: float = 2.5

@onready var sprite: Sprite2D = $Sprite2D
@onready var glow: PointLight2D = $PointLight2D

func _ready() -> void:
	rotation = direction.angle()
	if bullet_texture != null:
		sprite.texture = bullet_texture
		sprite.scale = Vector2.ONE * bullet_scale
	if spin:
		var tw = create_tween().set_loops()
		tw.tween_property(sprite, "rotation", TAU, 0.45).as_relative()
	_apply_elemental_tint()

## 异常色温：弹丸本体与它自带的那盏 PointLight2D 一起染色（场景里默认是暖橙，
## 冰针顶着一盏暖灯看着就像打歪了）。只改色相，不改判定、不改尺寸。
func _apply_elemental_tint() -> void:
	var tint := Color.WHITE
	if proc_burn:
		tint = Color(1.3, 0.75, 0.45)
	elif proc_chill > 0.0:
		tint = Color(0.65, 0.9, 1.3)
	elif proc_poison:
		tint = Color(0.65, 1.3, 0.65)
	if tint != Color.WHITE:
		modulate = tint
	if glow != null:
		if proc_burn:
			glow.color = Color(1.0, 0.6, 0.25)
		elif proc_chill > 0.0:
			glow.color = Color(0.55, 0.85, 1.0)
		elif proc_poison:
			glow.color = Color(0.55, 1.0, 0.6)

func _physics_process(delta: float) -> void:
	_steer(delta)
	position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()

## 每帧把弹向朝锁定目标拧过去，最多拧 HOMING_TURN_RATE × delta × homing_scale。
## homing_scale 为 0（判据反例）时等价于旧行为：直线飞行、永不修正。
func _steer(delta: float) -> void:
	if homing_target != null and not is_instance_valid(homing_target):
		homing_target = null
	if homing_target == null:
		if acquire_left <= 0:
			return
		acquire_left -= 1
		homing_target = _nearest_other(null, true)
		if homing_target == null:
			return
	var to_target: Vector2 = homing_target.global_position - global_position
	if to_target.length_squared() < 1.0:
		return
	var max_turn: float = HOMING_TURN_RATE * homing_scale * delta
	if max_turn <= 0.0:
		return
	var delta_ang: float = wrapf(to_target.angle() - direction.angle(), -PI, PI)
	if absf(delta_ang) <= max_turn:
		direction = to_target.normalized()
	else:
		direction = direction.rotated(signf(delta_ang) * max_turn)
	rotation = direction.angle()

func _on_area_entered(area: Area2D) -> void:
	var enemy = area.get_parent()
	if enemy and enemy.has_method("take_damage"):
		var is_crit = GameManager.rng.randf() < GameManager.get_crit_rate()
		var crit_m := GameManager.crit_mult + GameManager.synergy_crit_mult
		var actual_dmg = damage * (crit_m if is_crit else 1.0) * GameManager.elite_damage_mult_for(enemy)
		var knock := GameManager.knockback_vec(global_position, enemy.global_position, knockback_base)
		if knock.length_squared() < 0.001:
			knock = direction * GameManager.knockback_force(knockback_base)
		enemy.take_damage(actual_dmg, knock, is_crit)
		GameManager.try_lifesteal()

		# 施加五行异常
		if proc_burn and enemy.has_method("apply_burn"):
			enemy.apply_burn(burn_dps, burn_dur)
		if proc_chill > 0.0 and enemy.has_method("apply_chill"):
			enemy.apply_chill(proc_chill, chill_dur)
		if proc_poison and enemy.has_method("apply_poison"):
			enemy.apply_poison(poison_dps, poison_dur)

		JuiceEffect.spawn_hit_sparks(get_parent(), global_position, direction, is_crit)
		# 震屏/顿帧由被击一方 EnemyBase.take_damage 统一发放：
		# 这里再加一份就是同一次命中计费两遍，也是镜头一直摇的直接原因之一

		# 这一发已经吃到身上：不再回头咬同一个目标（穿透剩下的次数按直线贯穿排队站位的敌人）
		homing_target = null
		acquire_left = 0

		# 弹射连锁：若有弹射次数，向最近另一敌人折射
		if bounce_left > 0:
			var next_enemy := _nearest_other(enemy, false)
			if next_enemy != null:
				bounce_left -= 1
				homing_target = next_enemy
				# 弹射允许再丢一次目标时重找（连锁本来就是"就近找人"，不占穿透那一次额度）
				acquire_left = 1
				direction = (next_enemy.global_position - global_position).normalized()
				rotation = direction.angle()
				lifetime = 1.0
				return

		pierce_left -= 1
		if pierce_left <= 0:
			queue_free()

## 就近找一个敌人。ahead_only = 只认弹头前方锥内的（丢目标重录用），false = 全向（弹射连锁用，历史行为）
func _nearest_other(exclude: Node, ahead_only: bool) -> Node2D:
	var space_state = get_world_2d().direct_space_state
	if _search_shape == null or _search_query == null:
		_search_shape = CircleShape2D.new()
		_search_query = PhysicsShapeQueryParameters2D.new()
		_search_query.shape = _search_shape
		_search_query.collision_mask = 4
		_search_query.collide_with_areas = true
		query_alloc_count += 1
	else:
		query_reuse_count += 1
	_search_shape.radius = HOMING_ACQUIRE_RADIUS if ahead_only else BOUNCE_SEARCH_RADIUS
	_search_query.transform = Transform2D(0.0, global_position)
	var results = space_state.intersect_shape(_search_query, 16)

	var nearest: Node2D = null
	var min_dist: float = 99999.0
	var chest: Node2D = null
	var chest_dist: float = 99999.0
	for res in results:
		var col = res.get("collider")
		if col and col.get_parent() and col.get_parent().has_method("take_damage"):
			var target = col.get_parent() as Node2D
			if exclude != null and target == exclude:
				continue
			if ahead_only:
				var to_t: Vector2 = target.global_position - global_position
				if to_t.length_squared() < 1.0 or direction.dot(to_t.normalized()) < HOMING_ACQUIRE_AHEAD:
					continue
			var d := global_position.distance_to(target.global_position)
			if target.is_in_group("chests"):
				# 同一把尺子：匣子只在这一发本来要打空时才接（见 FloatingWeapon._find_target）
				if d < chest_dist:
					chest_dist = d
					chest = target
				continue
			if d < min_dist:
				min_dist = d
				nearest = target
	return nearest if nearest != null else chest
