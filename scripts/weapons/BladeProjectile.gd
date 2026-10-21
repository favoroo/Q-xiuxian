class_name BladeProjectile
extends Area2D

## 武器弹丸：伤害由 FloatingWeapon 计算好后直接传入，支持锁定追踪、穿透、弹射连锁与五行异常

## 追踪转向速率（rad/s）。弹速 420 ÷ 3.6 ⇒ 最小转弯半径约 117px：看得见符在拐，但不是制导导弹。
## 为什么要追踪（2026-10-08 用户口径：「火符比其他武器要弱很多」）：
## 旧写法直线飞行、不预判不锁敌，弹丸飞 0.5 秒的时间里敌人已经横移七八十个像素，
## 而判定只有 7px + 敌人受击圈 15px —— 离线仿真（弹速/判定/寿命全取运行时真值）给出
## 200px 命中 33%、350px 以上只剩 11%、雷兽横切冲刺 0%。
## 近战挥扫是当帧结算、环绕道具是接触即伤，都没有这笔隐形税 —— 远程纸面 DPS 打不出来就是假的。
## 留白的部分：400px 外打冲刺中的雷兽仍只有三成命中，高速怪的走位克制要保住。
const HOMING_TURN_RATE := 3.6
## 锁定目标中途暴毙后「另找最近的生气」的选择半径；只认弹头前方锥内的敌人，不许掉头 180° 追人
const HOMING_ACQUIRE_RADIUS := 240.0
const HOMING_ACQUIRE_AHEAD := 0.30        ## dot(弹向, 目标方位) 低于这个值就不算"在前方"
const BOUNCE_SEARCH_RADIUS := 260.0       ## 弹射连锁的找下家半径（沿用历史值）
## 穿透/弹射伤害衰减（2026-10-17，用户口径：「穿透之后的二次伤害要降低」）：
## 同一发弹丸第 N 次命中（N=1 首跳全额）伤害 × N 次的 PIERCE_HIT_DECAY 次方。
## 0.5：首跳 100% → 二跳 50% → 三跳 25% —— 贯穿是"刮过"，不是"全额重复收账"。
## 弹射与穿透同一把尺：都是"同一发弹丸的第 N 个敌人"。
const PIERCE_HIT_DECAY := 0.5
var _hit_index: int = 0                   ## 本发已命中敌人数（衰减用，activate 清零）
## 仅判据用：整体缩放转向速率（tests/ProjectileProbe.tscn 的 `-- --no-homing` 置 0 退回旧直线弹），
## 用来证明"命中率"这条断言真的有牙齿。运行时永远是 1.0。
static var homing_scale: float = 1.0
## 复用物理查询形状与参数，杜绝每帧弹丸重寻目标时 new CircleShape2D / PhysicsShapeQueryParameters2D
static var _search_shape: CircleShape2D = null
static var _search_query: PhysicsShapeQueryParameters2D = null
static var query_alloc_count: int = 0
static var query_reuse_count: int = 0

# —— 对象池（2026-10-10 性能优化）——
## 三发齐射 × 多件远程武器每秒 instantiate/free 十几次节点（Area2D + 碰撞体 + 矢量渲染器
## 全套生命周期）是「剑一多就卡」的分配压力来源。照 JuiceEffect/DamageNumber 池模式：
## 死亡不再 queue_free 而是回池休眠，复用由 activate() 全量重置（字段清单见 activate 注释）。
const POOL_CAP := 64
## 活跃弹丸预算（2026-10-17 性能专项）：POOL_CAP 只限「停泊数」，活跃数原先无约束，
## 极端武器组合可无限堆同屏弹丸（每发都带物理回调 + 灯 + 拖尾）。超预算时新弹照发、
## 最旧一发强制让位（它本来就快过期）。120 ≈ 现役构建峰值的 2 倍，常规构建永不触闸。
const ACTIVE_BUDGET := 120
## 场景默认寿命：activate 复用时重置的基准（FloatingWeapon 出膛再乘 range_mult）
## 2026-10-17 收紧 1.6→1.2（用户口径「满屏飞行物」）。
## 2026-10-20 再收紧 1.2→1.0 且弹速 470→420（用户口径「攻击范围很容易提到很大很远」）：
## 裸航程 564px→420px，吃满范围乘区也不再拉满整屏对角线
const BASE_LIFETIME := 1.0
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
static var active_count: int = 0     ## 当前在场（已激活未回收）弹丸数：HUD 性能面板消费
## 活跃弹丸出生序登记表（acquire 预算闸用）：Dictionary 保插入序，头部即最旧
static var _active_registry: Dictionary = {}
## 回收终值登记（launch_id -> {pierce,bounce}）：projectile_probe 结账用，读取后由探针清除
static var _final_stats: Dictionary = {}
static var record_final_stats: bool = false

static func clear_final_stats() -> void:
	_final_stats.clear()

static func clear_pool() -> void:
	_pool.clear()
	_lit_count = 0
	active_count = 0
	_active_registry.clear()
	_host = null
	clear_final_stats()

var direction: Vector2 = Vector2.RIGHT
## 弹速 2026-10-20 由 470 降到 420：与 BASE_LIFETIME 1.0 合并，裸航程 564→420px
var speed: float = 420.0
var damage: float = 20.0
var knockback_base: float = 140.0
var lifetime: float = 1.0
var pierce_left: int = 1
var bounce_left: int = 0
var spin: bool = true
## 这一发咬定的敌人：开火时由 FloatingWeapon 逐发分配（一次三发的武器各锁一个，不扎堆）
var homing_target: Node2D = null
## 弹丸外观按武器归位（2026-10-08 用户口径：「发出来一个不知道什么样的东西，火焰符就发出火」）：
## 旧写法五把远程武器共用 BladeProjectile.tscn 里那张 blade.png（一张燃烧的符箓）——
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

## 出膛它的武器攻击方式（吸血分档用）：FloatingWeapon 出膛填 PROJECTILE，
## TurretUnit 出膛填 TURRET。默认按远程算，未赋值时退化为远程系数。
var source_behavior: int = WeaponData.Behavior.PROJECTILE

@onready var sprite: Sprite2D = $Sprite2D
@onready var glow: PointLight2D = $PointLight2D
var _vector_renderer: ProceduralProjectileRenderer = null
## 世界坐标历史拖尾：追踪弹拐弯时留弧线（局部彗尾只会跟着本体转），池化复用零重建
var _trail: ProjectileTrail = null
## 上一次 kind 推断用的纹理路径：同一武器连发时路径恒定，跳过逐发的
## detect_kind_from_path 字符串子串匹配（activate 热路径）
var _last_kind_path: String = ""

func _ready() -> void:
	rotation = direction.angle()
	if bullet_texture != null:
		sprite.texture = bullet_texture
		sprite.scale = Vector2.ONE * bullet_scale
	# 自转不再用无限循环 Tween（每发弹丸一个常驻 Tween 是纯浪费）：
	# 改 _physics_process 手写推进，池化复用时零重建
	_setup_vector_visual()
	_apply_elemental_tint()
	_trail = ProjectileTrail.new()
	_trail.name = "Trail"
	add_child(_trail)
	# 压到兄弟首位画在弹体之下（top_level 只脱变换不脱树序）；z_index -1 会沉到地面之下，不可用
	move_child(_trail, 0)

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
	if _trail != null:
		_trail.sample(global_position, delta)
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
		var is_crit: bool = GameManager.roll_crit()
		var crit_m := GameManager.get_crit_mult()
		# 穿透/弹射逐跳衰减：第 1 跳全额，之后每跳 ×PIERCE_HIT_DECAY（异常量按实伤等比缩水）
		_hit_index += 1
		var decay := pow(PIERCE_HIT_DECAY, float(_hit_index - 1))
		var actual_dmg = damage * decay * (crit_m if is_crit else 1.0) * GameManager.elite_damage_mult_for(enemy)
		var knock := GameManager.knockback_vec(global_position, enemy.global_position, knockback_base)
		if knock.length_squared() < 0.001:
			knock = direction * GameManager.knockback_force(knockback_base)
		enemy.take_damage(actual_dmg, knock, is_crit)
		GameManager.try_lifesteal(source_behavior)

		# 命中火花与暴击加档反馈（T-1.1 / T-1.4）：严格贴实弹丸命中点，受帧限流与视口门控约束
		# 2026-10-16 攻击粒子减量：非暴击 scale 收 0.85，暴击维持 1.5（重击感知靠对比）；
		# 顺向喷溅：碎片随弹道飞（dir 非零 → ~100° 扇形），多武器齐射不再糊成全向白噪
		var spark_scale: float = 1.5 if is_crit else 0.85
		var spark_elem: Variant = "crit" if is_crit else _get_impact_element()
		FxParticlePool.burst(FxParticlePool.HIT_SPARK, global_position, spark_elem, spark_scale, false, direction)

		# 施加五行异常走 ProcStatus 收口（保持 has_method 鸭类型）。武器/弹丸脚本绝不能硬引用
		# EnemyBase——实测 `as EnemyBase` 会让 preload(BladeProjectile.tscn) 在运行中退化成
		# 空 PackedScene（循环类依赖解析坑），弹丸 instantiate 全返回 null。
		# 异常量跟随逐跳衰减的实伤口径：二跳引燃就不该有首跳那么旺
		ProcStatus.apply(enemy, proc_burn, burn_dps * decay, burn_dur,
			proc_chill, chill_dur, proc_poison, poison_dps * decay, poison_dur)

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
				# 弹射续命 1.0→0.7（2026-10-17 随基础寿命同批收紧）：3 次弹射总在场时长
				# 1.2+0.7×3 ≈ 3.3s，不再绕场半周；找下家半径不变，够不着就自然消散
				lifetime = 0.7
				JuiceEffect.spawn_impact_pop(self, global_position, _get_impact_color(), direction)
				return

			pierce_left -= 1
			if pierce_left <= 0:
				JuiceEffect.spawn_impact_pop(self, global_position, _get_impact_color(), direction)
				if _vector_renderer != null and _vector_renderer.kind == ProceduralProjectileRenderer.ProjectileKind.GOLD_COIN:
					var scene_parent := get_parent()
					if is_inside_tree() and scene_parent != null:
						JuiceEffect.spawn_shockwave(scene_parent, global_position, 20.0, Color(1.0, 0.85, 0.25, 0.75), 0.16)
				_recycle()

func _get_impact_color() -> Color:
	if modulate != Color.WHITE:
		return modulate
	if _vector_renderer != null:
		if _vector_renderer.kind == ProceduralProjectileRenderer.ProjectileKind.GOLD_COIN:
			return Color(1.0, 0.88, 0.28)
		if _vector_renderer.elemental_tint != Color.WHITE:
			return _vector_renderer.elemental_tint
	return Color(0.95, 0.90, 0.72)

func _get_impact_element() -> Variant:
	if proc_burn:
		return "fire"
	elif proc_chill > 0.0:
		return "water"
	elif proc_poison:
		return "wood"
	if _vector_renderer != null:
		if _vector_renderer.kind == ProceduralProjectileRenderer.ProjectileKind.GOLD_COIN:
			return "metal"
		if _vector_renderer.elemental_tint != Color.WHITE:
			return _vector_renderer.elemental_tint
	return "none"

## 拖尾取色：同一把尺子先用异常色温（modulate），退而矢量渲染器的元素色，最后回默认纸金。
## 与 _get_impact_color 的差别只在饱和度压暗——拖尾是辉光叠加线，全饱和色叠加会糊成白块
func _trail_color() -> Color:
	var base := _get_impact_color()
	return Color(base.r * 0.9, base.g * 0.9, base.b * 0.9)

## 就近找一个敌人。ahead_only = 只认弹头前方锥内的（丢目标重录用），false = 全向（弹射连锁用，历史行为）
func _nearest_other(exclude: Node, ahead_only: bool) -> Node2D:
	var space_state = get_world_2d().direct_space_state
	if _search_shape == null or _search_query == null:
		_search_shape = CircleShape2D.new()
		_search_query = PhysicsShapeQueryParameters2D.new()
		_search_query.shape = _search_shape
		_search_query.collision_mask = 4
		_search_query.collide_with_areas = true
		_search_query.collide_with_bodies = false  # 只查敌人 Hurtbox(Area)，不扫 body 层
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
		var parent = col.get_parent() if col != null else null
		if parent != null and parent.has_method("take_damage"):
			var target = parent as Node2D
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
	_lit_count = 0   ## 宿主销毁 = 灯随弹丸一起没了，名额同步归零
	_host = Node2D.new()
	_host.name = "BladeProjectilePool"
	parent.add_child(_host)

## 取一发弹丸：池里有就复用，没有 instantiate 新的挂到池宿主下。
## 调用方随后设置全部战斗字段并调用 activate()。
## 2026-10-17 性能专项：加活跃预算闸 —— 旧版 POOL_CAP=64 只是「停泊上限」（回收时才判），
## 活跃数无任何约束，极端武器组合（多弹幕齐射）可无限堆活跃弹丸。
## 超预算时不丢新弹（新弹代表新伤害意图），而是强制回收最旧一发让位：
## 寿命最短的本来就是快过期的，视觉损失为零。
static func acquire_or_new(scene: PackedScene, parent: Node) -> BladeProjectile:
	_ensure_host(parent)
	# 活跃预算：超限时踢掉最旧活跃弹丸（active 记录的出生序，头部即最旧）
	while active_count >= ACTIVE_BUDGET:
		var victim: BladeProjectile = null
		for p in _active_registry:
			if is_instance_valid(p) and not p._pooled:
				victim = p
				break
		if victim == null:
			break   # 登记表空转保护（异常态下不阻塞出弹）
		victim._recycle()
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
##   homing_target/acquire_left/_hit_index/proc_burn/burn_dps/burn_dur/proc_chill/chill_dur/
##   proc_poison/poison_dur/bullet_texture/bullet_scale/spin
## 注：source_behavior 由出膛方在 activate() 之前写好，回收时在 _recycle 归零，activate 不覆盖它。
func activate() -> void:
	_pooled = false
	active_count += 1
	_active_registry[get_instance_id()] = self
	launch_seq += 1
	launch_id = launch_seq
	# 池化节点回收时留在树里停在死亡点，复用出膛是从旧位置瞬移到枪口：
	# 全局物理插值开着时，不重置的话前一两帧会渲染成「从死亡点滑到枪口」——
	# 桌面 60fps 恰好对齐 60Hz 物理帧使插值退化为空操作看不出，真机帧率抖动时就闪
	reset_physics_interpolation()
	visible = true
	# 异常色温残值清零：上一发是火符（modulate 橙），这一发换冰针时不清的话
	# _apply_elemental_tint 的 WHITE 分支跳过赋值，冰针顶着一身橙色飞全程
	modulate = Color.WHITE
	# 残值清零：lifetime（FloatingWeapon 出膛时是乘 range_mult 的，复用弹丸若带着上一发
	# 的残值会「出膛即逝」——ProjectileProbe B 段贴脸 100% 落空的元凶）与 acquire_left
	# （命中即置 0，复用后必须恢复丢目标重找的额度）与 _hit_index（穿透衰减从首跳全额起算）
	lifetime = BASE_LIFETIME
	acquire_left = 1
	_hit_index = 0
	rotation = direction.angle()
	sprite.texture = bullet_texture
	sprite.scale = Vector2.ONE * bullet_scale
	sprite.rotation = 0.0
	if _vector_renderer != null:
		var path_str := bullet_texture.resource_path if bullet_texture != null else ""
		# 同路径复用上一发的推断结果：detect 是纯路径子串匹配，换武器才需要重跑
		if path_str != _last_kind_path:
			_vector_renderer.kind = ProceduralProjectileRenderer.detect_kind_from_path(path_str)
			_last_kind_path = path_str
		_vector_renderer.queue_redraw()
	_apply_elemental_tint()
	if _trail != null:
		_trail.configure(_trail_color())
		_trail.seed_point(global_position)
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
	# 探针（projectile_probe）结账时优先读这里，防把真实命中误记成落空；仅在探针开启时记录，正式局不泄漏
	if record_final_stats and launch_id >= 0:
		_final_stats[launch_id] = {"pierce": pierce_left, "bounce": bounce_left}
	_pooled = true
	active_count = maxi(0, active_count - 1)
	_active_registry.erase(get_instance_id())
	homing_target = null
	# 拖尾同拍清史：休眠弹丸的弧线必须跟碰撞/登记表一起撤（池体不许占拍，AGENTS 坑 13）
	if _trail != null:
		_trail.reset()
	_release_light()
	set_physics_process(false)
	set_deferred("monitoring", false)
	$CollisionShape2D.set_deferred("disabled", true)
	visible = false
	# 清理可能残留的异常与战斗字段，防止池化复用时污染
	proc_burn = false
	burn_dps = 0.0
	burn_dur = 0.0
	proc_chill = 0.0
	chill_dur = 0.0
	proc_poison = false
	poison_dps = 0.0
	poison_dur = 0.0
	# 吸血分档残值清零：上一发若是机关炮台（TURRET），复用给灵兽/远程时不清会沿用高频系数
	source_behavior = WeaponData.Behavior.PROJECTILE
	bounce_left = 0
	pierce_left = 0
	if _host == null or not is_instance_valid(_host) or _pool.size() >= POOL_CAP:
		queue_free()
		return
	_pool.append(self)

## 灯按名额先到先得：超限弹丸熄灯飞行（矢量辉光仍在），回收时让位；
## 名额走 FxBudget 拥挤档（2026-10-17）：高压战斗弹丸灯减半让位带宽，敌潮退去回满
func _try_acquire_light() -> void:
	if glow == null:
		return
	if _has_light:
		glow.enabled = true
		glow.visible = true
		return
	if _lit_count < FxBudget.projectile_light_cap():
		_lit_count += 1
		_has_light = true
		glow.enabled = true
		glow.visible = true
	else:
		glow.enabled = false
		glow.visible = false

func _release_light() -> void:
	if _has_light:
		_lit_count = maxi(0, _lit_count - 1)
		_has_light = false
	if glow != null:
		glow.enabled = false
		glow.visible = false
