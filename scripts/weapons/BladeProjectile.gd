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

# —— 对象池（2026-10-10 性能优化）——
## 三发齐射 × 多件远程法器每秒 instantiate/free 十几次节点（Area2D + 碰撞体 + 矢量渲染器
## 全套生命周期）是「剑一多就卡」的分配压力来源。照 JuiceEffect/DamageNumber 池模式：
## 死亡不再 queue_free 而是回池休眠，复用由 activate() 全量重置（字段清单见 activate 注释）。
const POOL_CAP := 64
## 场景默认寿命：activate 复用时重置的基准（FloatingWeapon 出膛再乘 range_mult）
const BASE_LIFETIME := 1.6
## —— 弹丸灯光上限 ——
## 每发弹丸一盏 PointLight2D，6 剑齐射常驻 10~20 盏 2D 动态灯，光照 pass 逐灯叠加是
## 渲染侧主卡因。全场最多同时点亮 LIGHT_CAP 盏，超限弹丸灯灭但矢量渲染器自带的
## 辉光多边形仍在（ProceduralProjectileRenderer 光晕），视觉不空。
const LIGHT_CAP := 6
static var _pool: Array[BladeProjectile] = []
static var _host: Node2D = null
static var created_count: int = 0    ## 累计 instantiate 数（tests/PerfProbe 断言用）
static var reused_count: int = 0     ## 累计池复用数
static var _lit_count: int = 0       ## 当前点亮的弹丸灯数
## 回收终值登记（launch_id -> {pierce,bounce}）：projectile_probe 结账用，读取后由探针清除
static var _final_stats: Dictionary = {}

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

## 池状态标记：true = 已回池休眠（防双重回收）；_has_light = 是否持有灯名额
var _pooled: bool = false
var _has_light: bool = false

## 发射序号：activate 一次 +1，全局限一（PoolCheck 后探针按它区分「同一实例的多次发射」）
static var launch_seq: int = 0
var launch_id: int = -1

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
var _vector_renderer: ProceduralProjectileRenderer = null

func _ready() -> void:
	rotation = direction.angle()
	if bullet_texture != null:
		sprite.texture = bullet_texture
		sprite.scale = Vector2.ONE * bullet_scale
	# 自转不再用无限循环 Tween（每发弹丸一个常驻 Tween 是纯浪费）：
	# 改 _physics_process 手写推进，池化复用时零重建
	_setup_vector_visual()
	_apply_elemental_tint()

func _setup_vector_visual() -> void:
	var path_str := bullet_texture.resource_path if bullet_texture != null else ""
	_vector_renderer = ProceduralProjectileRenderer.new()
	_vector_renderer.kind = ProceduralProjectileRenderer.detect_kind_from_path(path_str)
	sprite.add_child(_vector_renderer)
	# 隐蔽旧像素贴图，保留子节点矢量渲染
	sprite.self_modulate.a = 0.0

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
	if spin:
		sprite.rotation += delta * (TAU / 0.45)   ## 与旧 Tween 同速：0.45s 一整圈
	lifetime -= delta
	if lifetime <= 0.0:
		_recycle()

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

		# 受击火花 / 震屏 / 顿帧全部由被击一方 EnemyBase.take_damage 统一发放：
		# 弹体侧再发一份就是同一次命中火花双发、创伤计两遍（方向读数糊掉 + 镜头一直摇的元凶）

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
			_recycle()

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

# ----------------- 对象池与灯光管理 -----------------

## 池宿主挂在场景根下（同 JuiceEffect 模式），场景切换后旧池随宿主一起销毁，
## acquire 时用 is_instance_valid 过滤空壳并重建宿主。
static func _ensure_host(parent: Node) -> void:
	if _host != null and is_instance_valid(_host):
		return
	_pool.clear()
	_host = Node2D.new()
	_host.name = "BladeProjectilePool"
	parent.add_child(_host)

## 取一发弹丸：池里有就复用，没有 instantiate 新的挂到池宿主下。
## 调用方随后设置全部战斗字段并调用 activate()。
static func acquire_or_new(scene: PackedScene, parent: Node) -> BladeProjectile:
	_ensure_host(parent)
	while not _pool.is_empty():
		var p: BladeProjectile = _pool.pop_back()
		if is_instance_valid(p):
			reused_count += 1
			return p
	var np := scene.instantiate() as BladeProjectile
	created_count += 1
	_host.add_child(np)
	return np

## 出膛激活：池化后 _ready 先于战斗字段赋值跑过，所有依赖字段的视觉与物理状态
## 必须在这里按当前字段值重铺。重置清单（改字段签名时对照这里）：
##   direction/speed/damage/knockback_base/lifetime/pierce_left/bounce_left/
##   homing_target/acquire_left/proc_burn/burn_dps/burn_dur/proc_chill/chill_dur/
##   proc_poison/poison_dur/bullet_texture/bullet_scale/spin
func activate() -> void:
	_pooled = false
	launch_seq += 1
	launch_id = launch_seq
	visible = true
	# 残值清零：lifetime（FloatingWeapon 出膛时是乘 range_mult 的，复用弹丸若带着上一发
	# 的残值会「出膛即逝」——ProjectileProbe B 段贴脸 100% 落空的元凶）与 acquire_left
	# （命中即置 0，复用后必须恢复丢目标重找的额度）
	lifetime = BASE_LIFETIME
	acquire_left = 1
	rotation = direction.angle()
	sprite.texture = bullet_texture
	sprite.scale = Vector2.ONE * bullet_scale
	sprite.rotation = 0.0
	if _vector_renderer != null:
		var path_str := bullet_texture.resource_path if bullet_texture != null else ""
		_vector_renderer.kind = ProceduralProjectileRenderer.detect_kind_from_path(path_str)
		_vector_renderer.queue_redraw()
	_apply_elemental_tint()
	# 碰撞恢复必须也走 deferred：同一帧「回收→复用」时，回收的 disabled=true deferred
	# 会在帧末 flush，直接赋值的 false 会被它覆盖 —— 弹丸从此永世撞不到人（探针 B 段 0% 命中的元凶）。
	# 两个 deferred 按入队顺序执行：回收(true) → 出膛(false)，最终值必落在出膛侧。
	$CollisionShape2D.set_deferred("disabled", false)
	set_deferred("monitoring", true)
	set_physics_process(true)
	_try_acquire_light()

## 回收入池（替代 queue_free）：休眠物理与碰撞，灯让位，池满或宿主失效才真释放
func _recycle() -> void:
	if _pooled:
		return
	# 终值上报：贴脸弹丸常在两次扫描之间完成「命中→回收」，逐帧扫描读不到终值，
	# 探针（projectile_probe）结账时优先读这里，防把真实命中误记成落空
	if launch_id >= 0:
		_final_stats[launch_id] = {"pierce": pierce_left, "bounce": bounce_left}
	_pooled = true
	homing_target = null
	_release_light()
	set_physics_process(false)
	set_deferred("monitoring", false)
	$CollisionShape2D.set_deferred("disabled", true)
	visible = false
	if _host == null or not is_instance_valid(_host) or _pool.size() >= POOL_CAP:
		queue_free()
		return
	_pool.append(self)

## 灯按 LIGHT_CAP 先到先得：超限弹丸熄灯飞行（矢量辉光仍在），回收时让位
func _try_acquire_light() -> void:
	if glow == null:
		return
	if _has_light:
		glow.visible = true
		return
	if _lit_count < LIGHT_CAP:
		_lit_count += 1
		_has_light = true
		glow.visible = true
	else:
		glow.visible = false

func _release_light() -> void:
	if _has_light:
		_lit_count = maxi(0, _lit_count - 1)
		_has_light = false
	if glow != null:
		glow.visible = false
