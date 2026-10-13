class_name PoisonPool
extends Area2D

## 敌方投毒留下的「毒潭」：一片持续 N 秒的伤害区域，玩家待在里面就按周期掉血。
## 落地形态照 AoeTelegraph（Boss 震地/丹爆自爆共用的圆形预警）的读法：**画出来的圈 == 判定圈**。
## 铁律对齐（与 AoeTelegraph / EnemyBolt 同一套）：
##   - 范围视觉与判定同源：radius 是判定半径的唯一真话，本组件不自算范围。
##   - 伤害周期真话在持有者侧的口径：玩家走自己的受击无敌帧（BASE_INVULNERABLE_TIME）
##     ⇒ 结算间隔天然被钉住，这里只负责「人在圈内就每跳招呼一次」，不另造冷却。
##   - 持续时长真话在 EnemyBase（POOL_DURATION），池只认 duration 字段。

const RADIUS := 60.0                ## 基准判定半径（不含 scale_factor）：外观与碰撞的唯一来源
const POOL_BODY := Color(0.35, 0.75, 0.45)   ## 毒液本色（青木剧毒的绿）
const POOL_EDGE := Color(0.55, 0.95, 0.62)   ## 内沿亮边（读「正在腐噬」）
const POOL_DARK := Color(0.10, 0.28, 0.16)   ## 外圈暗晕

# —— 对象池（照 AstralGem / HealOrb / EnemyBolt 模式）——
## 投毒是周期技，一只怪 5 秒一发，同屏多只时 instantiate/free 的节点生命周期是实打实的分配热点。
const POOL_CAP := 24
static var _pool: Array[PoisonPool] = []
static var _host: Node2D = null
static var created_count: int = 0   ## 累计 instantiate 数（PoolCheck 断言用）
static var reused_count: int = 0
static var active_count: int = 0    ## 当前在场毒潭数：HUD 性能面板消费

## 取一滩毒（优先复用）：调用方随后写 global_position / damage / duration / scale_factor，最后 activate()
static func acquire(parent: Node) -> PoisonPool:
	if _host == null or not is_instance_valid(_host):
		_pool.clear()
		_host = Node2D.new()
		_host.name = "PoisonPoolHost"
		parent.add_child(_host)
	while not _pool.is_empty():
		var p: PoisonPool = _pool.pop_back()
		if is_instance_valid(p):
			reused_count += 1
			p._reset_defaults()
			return p
	var np := PoisonPool.new()
	created_count += 1
	_host.add_child(np)
	return np

var damage: float = 4.0             ## 每跳伤害（跳的节奏由玩家受击无敌帧钉住）
var duration: float = 5.0           ## 持续时长（秒）
var scale_factor: float = 1.0       ## 整体缩放（外观与碰撞一起缩，同 EnemyBolt 口径）
var radius: float = RADIUS          ## 实际判定半径 = RADIUS × scale_factor

var _pooled: bool = false
var _shape_node: CollisionShape2D = null
var _circle: CircleShape2D = null
var _clock: float = 0.0             ## 视觉时钟（冒泡/呼吸相位，不参与计时结算）

func _reset_defaults() -> void:
	damage = 4.0
	duration = 5.0
	scale_factor = 1.0

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # player
	rotation = 0.0    # 毒潭是圆，不随节点旋转
	# 判定结算只走 _physics_process 的 overlap 扫描，不接 body_entered —— 原因见那里的注释
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	add_child(shape)
	_shape_node = shape
	_circle = circle

## 出膛激活：池化后 _ready 只在首建时跑过，半径/寿命必须按当前字段重铺
func activate() -> void:
	_pooled = false
	active_count += 1
	visible = true
	rotation = 0.0
	radius = RADIUS * maxf(scale_factor, 0.05)
	if _circle != null:
		_circle.radius = radius
	_clock = 0.0
	# 碰撞恢复必须走 deferred：同帧「回收→复用」时回收的 disabled=true 会延迟到帧末 flush，
	# 直接赋 false 会被它覆盖（照 EnemyBolt.activate 同一条坑）
	set_deferred("monitoring", true)
	_shape_node.set_deferred("disabled", false)
	set_physics_process(true)

## 回收入池（替代 queue_free）：休眠物理与碰撞，池满或宿主失效才真释放
func recycle() -> void:
	if _pooled:
		return
	_pooled = true
	active_count = maxi(0, active_count - 1)
	set_physics_process(false)
	set_deferred("monitoring", false)
	_shape_node.set_deferred("disabled", true)
	visible = false
	_reset_defaults()
	if _host == null or not is_instance_valid(_host) or _pool.size() >= POOL_CAP:
		queue_free()
		return
	_pool.append(self)

## 释放池内全部休眠个体（Main._exit_tree 随场景清）
static func clear_pool() -> void:
	_pool.clear()
	_host = null
	created_count = 0

## 池内休眠体总数（探针/判据用）
static func pool_idle_count() -> int:
	return _pool.size()

func _draw() -> void:
	# 外圈暗晕 + 毒液本体 + 内沿亮边：三层同心圆，半径全部锚在判定圆上。
	# 不加 additive 辉光、不做脉动缩放 —— 视觉永远不超过实际范围（EnemyBolt 同口径）。
	draw_circle(Vector2.ZERO, radius, POOL_DARK)
	draw_circle(Vector2.ZERO, radius * 0.82, POOL_BODY)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, POOL_EDGE, 2.0, true)

func _physics_process(delta: float) -> void:
	# 玩家在圈内就招呼：take_damage 自己按受击无敌帧节流 ⇒ 站圈里是稳定一跳一跳的掉血，
	# 而不是每帧一刀（伤害读数仍由玩家的护甲/闪避/免伤统一收口）。
	# 只走 overlap 扫描、不接 body_entered 信号：Area2D 的进入信号对「起手前就已经在圈里」
	## 的玩家不触发（毒潭多是砸在玩家脚下落成的），两条路径必须同一口径 —— 都在第一帧
	## 物理扫描里结算，先摆人后放潭与先放潭后摆人吃到的第一跳完全一致。
	var player := GameManager.player
	if player != null and is_instance_valid(player) and player.current_health > 0.0:
		for body in get_overlapping_bodies():
			if body == player:
				body.take_damage(damage, global_position)
				break
	duration -= delta
	if duration <= 0.0:
		recycle()
