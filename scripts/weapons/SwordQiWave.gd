class_name SwordQiWave
extends Node2D

## 剑气凌霄（神通）的飞行剑气波（2026-10-26 v2）：一次完整的月牙剑弧离体飞出。
## 用户口径（两轮）：①「我要的不是发一个弹丸出去，而是一道完整的剑弧出去，这才叫剑气」；
## ②「直接改变这个近战武器的攻击方式，不管怎么攻击都是挥出一道剑气，而不是一下近战一下剑气」。
## 所以本实体是【近战/横扫开启剑气凌霄后的唯一伤害来源】：本体圆/扇面判定整段让位，
## 整道弧（±70° 锥形刃带 + 元素配色 + HDR 亮芯，无飞行长拖尾）就是那一刀。
##
## 判定与视觉同源（项目铁律 6）：每物理帧以波心查一圈敌人，再按方位过滤出
## 「前方 ±70°+宽容扇形」的目标 —— 剑弧是整片扫过去的气，贴身的也在扇区里；
## 只有身后的敌人才漏。同一波对每个敌人只结算一次（命中表去重，剑气穿阵而过）。
##
## 池化照 BladeProjectile 范式：_recycle 回池休眠，activate 全量重置字段。
## 纪律（项目坑 12/16）：本文件全程鸭类型访问敌人（has_method("take_damage")），
## 绝不硬引用 EnemyBase —— 武器侧硬类型引用会把弹丸/场景 preload 打成空 PackedScene。

## 弧带几何：与 WeaponArcRenderer 的月牙同源（改画布要同步改这里，断言在 WeaponAimCheck）
const ART_OUTER := 124.0        ## == WeaponArcRenderer.OUTER（画布外缘半径，缩放基准）
const ART_INNER := 114.0        ## == WeaponArcRenderer.MELEE_INNER（弧带内缘，只用于出生"贴剑尖"反解）
const ART_SCALE := 0.92         ## 整体缩放：外缘 ≈114px、整弧宽 ≈215px 的一道完整剑弧
const HALF_ANGLE_DEG := 70.0    ## == WeaponArcRenderer.MELEE_HALF
const ANGLE_SLACK_DEG := 6.0    ## 角度宽容（度）：刃带羽化边擦到的也算中
const BODY_REACH := 12.0        ## 敌人受击半径近似：体表压进刃带也算被砍中（纯几何补偿）
const SPAWN_SCALE_REL := 0.45   ## 出膛缩放（相对 ART_SCALE）：刃带贴剑尖出生，扫放到全尺寸后前飞
const GROW_TIME := 0.07         ## 扫放到全尺寸的时长（与近战月牙的出鞘节奏同档）
const SPEED := 420.0            ## 飞行速度（与 BladeProjectile 同档，看得清弧面）
const MIN_TRAVEL := 60.0        ## 最短航程（极短射程武器也保证弧面真的离体）
const REACH_PAD := 8.0          ## 刃缘超出索敌距离的余量（保证锁定圈内的怪一个不漏，又不越程太多）
const FADE_TIME := 0.10         ## 寿命末段淡出时长
const MAX_HITS := 16            ## 单波命中上限（控成本：剑气穿阵也不无限收账）
const SPARK_MAX := 3            ## 命中火花上限（一道弧扫过一片也只冒几朵）
const CRIT_SPARK_SCALE := 1.5   ## 与 StrikeFx.CRIT_SPARK_SCALE 同档（不跨引，防类循环）
const SPARK_SCALE := 0.75       ## 与 StrikeFx.MELEE_SPARK_SCALE 同档
const SPARK_EDGE := 14.0        ## 火花锚点由敌人中心向来向偏移，落在体表而非几何中心

# —— 对象池（照 BladeProjectile）：近战挥砍 1 次/秒级，池上限给足余量 ——
const POOL_CAP := 16
static var _pool: Array[SwordQiWave] = []
static var _host: Node2D = null
static var created_count: int = 0    ## 累计 instantiate 数
static var reused_count: int = 0     ## 累计池复用数
static var active_count: int = 0     ## 当前在场（已激活未回收）剑气数

static var _search_shape: CircleShape2D = null
static var _search_query: PhysicsShapeQueryParameters2D = null

# —— 战斗字段（出膛方在 activate 前写好）——
var direction: Vector2 = Vector2.RIGHT
var speed: float = SPEED
var lifetime: float = 0.5
var damage: float = 20.0
var knockback_force: float = 280.0
var element: String = ""        ## 五行元素（走 WeaponArcRenderer 调色板；空串回落金属）
var source_weapon: Node = null  ## 出膛宿主（机制卡命中结算用；弱引用，回池即清）
var source_behavior: int = WeaponData.Behavior.MELEE  ## 吸血分档口径（横扫传 SWEEP）
var impact_sfx_key: String = "" ## 命中材质声（首次咬到肉才响，挥空不响）
var impact_pitch: float = 1.0
var heal_full: bool = true      ## 吸血与固定回血只算主斩（★3/★4 追加段按原口径不双计）
var proc_burn: bool = false
var burn_ratio: float = 0.45
var burn_dur: float = 3.0
var proc_chill: float = 0.0
var chill_dur: float = 2.5
var proc_poison: bool = false
var poison_ratio: float = 0.35
var poison_dur: float = 3.0

# —— 运行态 ——
var _arc: WeaponArcRenderer = null
var _age: float = 0.0
var _visual_scale: float = ART_SCALE
var _hit_ids: Dictionary = {}   ## 本波已结算的敌人 instance_id（去重）
var _hit_count: int = 0
var _pooled: bool = false
var _has_mech: bool = false
var _mech: Dictionary = {}

## 出膛点反推：波心要落后出膛点「初始弧带内缘」那么多，出生那一帧刃带才正好压在剑尖上。
## 剑气从剑上劈出去，不是凭空悬在远处（近战月牙同一条纪律）。
static func spawn_offset() -> float:
	return ART_INNER * ART_SCALE * SPAWN_SCALE_REL

## 射程 → 飞行距离：按【刃带前缘】对齐 effective_range 反推波心飞多远。
## 2026-10-26 缩短（用户：「剑气的飞行距离短一点」）：旧写法波心整段飞 effective_range，
## 刃缘再白送一个外缘半径 ⇒ 长剑实际扫到 293px（锁定距离 210 之外 83px，越程偷打没锁定的怪，
## 且半个屏幕都在剑气范围里）。现在改成「刃缘前缘刚好够到索敌/开火距离」：
##   波心飞行 = eff + spawn_offset - 弧外缘半径 + REACH_PAD
## 长剑 210px → 飞行 163px（−22%），刃缘最远仍压在 ~230px，锁定范围内的怪一个不漏。
static func travel_distance_for(eff_range: float) -> float:
	return maxf(MIN_TRAVEL, eff_range + spawn_offset() - ART_OUTER * ART_SCALE + REACH_PAD)

## 射程 → 寿命：飞行距离 ÷ 弹速。改 SPEED 只改飞得多快，不改打多远。
static func travel_time_for(eff_range: float) -> float:
	return travel_distance_for(eff_range) / SPEED

func _ready() -> void:
	_arc = WeaponArcRenderer.new()
	_arc.trail_enabled = false
	_arc.configure(WeaponArcRenderer.ArcMode.MELEE, element)
	_arc.visible = false
	_arc.modulate.a = 1.0
	add_child(_arc)
	set_physics_process(false)

func activate() -> void:
	_pooled = false
	active_count += 1
	# 池化节点休眠时停在死亡点，复用是瞬移到剑尖：不重置物理插值会看到「从旧位置滑过来」
	reset_physics_interpolation()
	_age = 0.0
	_hit_ids.clear()
	_hit_count = 0
	_visual_scale = ART_SCALE * SPAWN_SCALE_REL
	rotation = direction.angle()
	modulate = Color.WHITE
	visible = true
	_has_mech = OnHitEffects.any_enabled()
	_mech = OnHitEffects.snapshot() if _has_mech else {}
	if _arc != null:
		_arc.trail_enabled = false
		_arc.configure(WeaponArcRenderer.ArcMode.MELEE, element)
		_arc.modulate = Color.WHITE
		_arc.rotation = 0.0
		_arc.scale = Vector2.ONE * _visual_scale
		_arc.visible = true
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	if _pooled:
		return
	_age += delta
	position += direction * speed * delta
	_update_visual()
	_query_and_damage()
	if _age >= lifetime:
		_recycle()

## 剑弧扫放与淡出：出膛从 0.45 倍扩到全尺寸（弧带贴剑尖出生、扫出去），
## 寿命末段整道弧渐隐。缩放同时是判定半径 —— 画多大就判多大。
func _update_visual() -> void:
	var grow: float = clampf(_age / GROW_TIME, 0.0, 1.0)
	_visual_scale = ART_SCALE * lerpf(SPAWN_SCALE_REL, 1.0, grow)
	if _arc != null:
		_arc.scale = Vector2.ONE * _visual_scale
	var remain: float = lifetime - _age
	if remain < FADE_TIME:
		modulate.a = clampf(remain / FADE_TIME, 0.0, 1.0)

## 扇形判定：查询圆（半径 = 当前弧外缘）+ 方位过滤（aim ±（半角+宽容））。
## 判的是【弧面扫过的整片前方扇形】，不是细刃带那一薄圈 —— 剑弧是一整片「气」，
## 贴着玩家身前的敌人也在这片扇区里，必须一起吃到；只有身后的（超出 ±70°）才漏。
## 缩放同时驱动外缘 —— 画多大就判多大（与近战「画多大==判多大」同一条铁律）。
func _query_and_damage() -> void:
	if _hit_count >= MAX_HITS:
		return
	var outer: float = ART_OUTER * _visual_scale
	var half: float = deg_to_rad(HALF_ANGLE_DEG + ANGLE_SLACK_DEG)
	var center: Vector2 = global_position
	var results: Array = _query_enemies(outer, center, 24)
	for res in results:
		var col = res.get("collider")
		var enemy = col.get_parent() if col != null else null
		if enemy == null or not enemy.has_method("take_damage"):
			continue
		var id: int = enemy.get_instance_id()
		if _hit_ids.has(id):
			continue
		var to_enemy: Vector2 = enemy.global_position - center
		if to_enemy.length() > outer:
			continue
		# 贴脸目标（dist < BODY_REACH）角度无意义，恒算命中 —— 与 SweepHandler 的
		# SWEEP_CLOSE_GRACE 同一条宽容：不许因为方位噪声漏掉脚边的怪
		if to_enemy.length() > BODY_REACH and absf(direction.angle_to(to_enemy)) > half:
			continue
		_hit_ids[id] = true
		_hit_count += 1
		_apply_hit(enemy)
		if _hit_count == 1 and impact_sfx_key != "":
			# 材质声只在首次咬到肉时响（与近战的挥空门控同一口径：剑气飞出去打空就是一声都没有）
			AudioManager.play_sfx(impact_sfx_key, 1.0, impact_pitch)
		if _hit_count >= MAX_HITS:
			return

## 单个目标结算：满额实伤 + 逐敌暴击/精英乘区 + 顺飞行方向击退 + 五行异常 + 吸血 + 机制卡。
## 与 MeleeHandler.deal_damage 同一份代码形状，只是伤害已经在出膛帧快照好。
func _apply_hit(enemy) -> void:
	var is_crit: bool = GameManager.roll_crit()
	var dmg: float = damage
	if is_crit:
		dmg *= GameManager.get_crit_mult()
	dmg *= GameManager.elite_damage_mult_for(enemy)
	var knock: Vector2 = GameManager.knockback_vec(global_position, enemy.global_position, knockback_force)
	if knock.length_squared() < 0.001:
		knock = direction * GameManager.knockback_force(knockback_force)
	enemy.take_damage(dmg, knock, is_crit)
	if heal_full:
		GameManager.try_lifesteal(source_behavior)
		# 开山重刃谱：近身挥砍（含剑气）命中额外吸收生命，与 MeleeHandler/SweepHandler 同一条钩子
		var flat_ls: float = GameManager.item_hook_sum("melee_lifesteal_flat")
		if flat_ls > 0.0:
			var player: Node2D = GameManager.player
			if player != null and is_instance_valid(player) and player.has_method("heal"):
				player.heal(flat_ls, true)
	if _hit_count <= SPARK_MAX:
		var spark_dir: Vector2 = knock.normalized() if knock.length_squared() > 1.0 else direction
		var spark_pos: Vector2 = enemy.global_position - spark_dir * SPARK_EDGE
		var spark_elem: Variant = "crit" if is_crit else element
		FxParticlePool.weapon_hit_spark(enemy, spark_pos, spark_elem,
			CRIT_SPARK_SCALE if is_crit else SPARK_SCALE, is_crit, spark_dir)
	if proc_burn or proc_chill > 0.0 or proc_poison:
		ProcStatus.apply(enemy, proc_burn, dmg * burn_ratio, burn_dur,
			proc_chill, chill_dur, proc_poison, dmg * poison_ratio, poison_dur)
	# 机制卡（五行轮转 / 天罚）：宿主武器可能已随回合清场释放，先验证。
	# 万剑归宗不在此列（2026-10-26 改判）：它按【出手】攒剑意、全体剑器齐射，见 SwordPhantom。
	if _has_mech and source_weapon != null and is_instance_valid(source_weapon):
		OnHitEffects.on_weapon_hit(source_weapon, enemy, dmg, is_crit, _mech)

## 以 center 为圆心查敌人受击区（碰撞层 4），与 FloatingWeapon._query_enemies 同参数。
func _query_enemies(radius: float, center: Vector2, max_results: int) -> Array:
	if _search_shape == null or _search_query == null:
		_search_shape = CircleShape2D.new()
		_search_query = PhysicsShapeQueryParameters2D.new()
		_search_query.shape = _search_shape
		_search_query.collision_mask = 4
		_search_query.collide_with_areas = true
		_search_query.collide_with_bodies = false  # 只查敌人 Hurtbox(Area)，不扫 body 层
	_search_shape.radius = radius
	_search_query.transform = Transform2D(0.0, center)
	return get_world_2d().direct_space_state.intersect_shape(_search_query, max_results)

# ----------------- 对象池 -----------------

static func clear_pool() -> void:
	_pool.clear()
	active_count = 0
	_host = null

static func _ensure_host(parent: Node) -> void:
	if _host != null and is_instance_valid(_host):
		return
	_pool.clear()
	_host = Node2D.new()
	_host.name = "SwordQiWavePool"
	parent.add_child(_host)

static func acquire_or_new(scene: PackedScene, parent: Node) -> SwordQiWave:
	_ensure_host(parent)
	while not _pool.is_empty():
		var p: SwordQiWave = _pool.pop_back()
		if is_instance_valid(p):
			reused_count += 1
			return p
	var np := scene.instantiate() as SwordQiWave
	if np == null:
		return null
	created_count += 1
	_host.add_child(np)
	return np

## 回池休眠：物理与弧光一起停（三件套同拍，项目坑 13），战果字段清残值防复用污染。
func _recycle() -> void:
	if _pooled:
		return
	_pooled = true
	active_count = maxi(0, active_count - 1)
	set_physics_process(false)
	visible = false
	if _arc != null:
		_arc.visible = false   ## 子渲染器的显隐通知会 set_process(false) + 清拖尾史
	source_weapon = null
	source_behavior = WeaponData.Behavior.MELEE
	impact_sfx_key = ""
	impact_pitch = 1.0
	heal_full = true
	_hit_ids.clear()
	_hit_count = 0
	_has_mech = false
	_mech.clear()
	proc_burn = false
	proc_chill = 0.0
	proc_poison = false
	if _host == null or not is_instance_valid(_host) or _pool.size() >= POOL_CAP:
		queue_free()
		return
	_pool.append(self)
