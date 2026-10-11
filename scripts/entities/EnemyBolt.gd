class_name EnemyBolt
extends Area2D

## 敌方火球：御剑邪修周期直射、魔君环弹齐射共用这一颗。纯代码构建，无需场景文件。
##
## 视觉口径（2026-10-08 用户指令：「这个火球怎么这么大呀，而且还有这种透明的效果、
## 虚化的效果。不要这种效果，就实际的，它的攻击范围是多大就显示多大」）：
## 	**画出来的圆 == 判定圆**。直径严格等于 2 × radius，不叠 additive 辉光、
## 	不留半透明外焰、不做脉动缩放。
## 	旧写法把 128px 的 light_radial 当「外焰」（additive + alpha 0.7）套在
## 	0.55 倍的橙红核心外面，视觉上糊开约 70~100px，而判定半径只有 8px ——
## 	玩家看到的威胁范围是真实范围的 4~8 倍（比施法者本人还大一圈），只能凭感觉躲。
## 	同口径的既有先例：Boss 震地预警圈（AoeTelegraph 按判定半径画圈，填满即结算）、
## 	玩家法器弹丸（BladeProjectile 判定半径 7，刃的可见长度也就这个量级）。
## 	⇒ 要改火球大小只动 RADIUS 一个常数，外观与碰撞一起变，不许分开设。

const RADIUS := 8.0                  ## 基准判定半径（不含 scale_factor）：外观与碰撞的唯一来源
const BODY_COLOR := Color(1.0, 0.45, 0.12)   ## 球体
const CORE_COLOR := Color(1.0, 0.87, 0.45)   ## 高光芯
const RIM_COLOR := Color(0.42, 0.07, 0.04)   ## 硬描边，压在判定圆内侧

# —— 对象池（2026-10-11，照 AstralGem/BladeProjectile 模式）——
## 御剑邪修周期直射 + 魔君环弹齐射（一圈 18+ 发）每次 new()+queue_free，Area2D + 碰撞体
## 全套生命周期分配是波次卡顿源。死亡/到期回池休眠，activate() 全量重置。
## 兼容约定：裸 new() + add_child 的旧路径（预览/单测）保持原行为不受影响。
const POOL_CAP := 96
const BASE_LIFETIME := 3.0   ## 场景默认寿命：activate 复用时重置的基准
static var _pool: Array[EnemyBolt] = []
static var _host: Node2D = null
static var created_count: int = 0    ## 累计 instantiate 数（PoolCheck 断言用）
static var reused_count: int = 0     ## 累计池复用数
static var active_count: int = 0     ## 当前在场（已激活未回收）火球数：HUD 性能面板消费

static func _ensure_host(parent: Node) -> void:
	if _host != null and is_instance_valid(_host):
		return
	_pool.clear()   # 旧宿主已失效，残留池引用一并作废
	_host = Node2D.new()
	_host.name = "EnemyBoltPool"
	parent.add_child(_host)

## 取一颗火球（优先复用）：发射方在调用后写 global_position/direction/speed/damage/scale_factor，
## 最后调 activate() 出膛
static func acquire(parent: Node) -> EnemyBolt:
	_ensure_host(parent)
	while not _pool.is_empty():
		var b: EnemyBolt = _pool.pop_back()
		if is_instance_valid(b):
			reused_count += 1
			return b
	var nb := EnemyBolt.new()
	created_count += 1
	_host.add_child(nb)
	return nb

var direction: Vector2 = Vector2.RIGHT
var speed: float = 300.0
var damage: float = 6.0
var lifetime: float = 3.0
var scale_factor: float = 1.0  ## 整体缩放（Boss 环弹比普通火球大），外观与碰撞一起缩
var radius: float = RADIUS     ## 实际判定半径 = RADIUS × scale_factor，_ready 里定一次

## 池状态与 _ready 建好的节点引用（复用时 activate 重铺要用）
var _pooled: bool = false
var _shape_node: CollisionShape2D = null
var _circle: CircleShape2D = null

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # player
	# 火球不旋转，保持圆形
	rotation = 0.0
	# scale_factor 由发射方在 add_child 之前写入，所以这里算一次就是终值
	radius = RADIUS * maxf(scale_factor, 0.05)

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	add_child(shape)
	_shape_node = shape
	_circle = circle

	body_entered.connect(_on_body_entered)

## 出膛激活：池化后 _ready 只在首建时跑过，所有依赖字段的视觉与物理状态
## 必须在这里按当前字段值重铺。重置清单（改字段签名时对照这里）：
##   direction/speed/damage/lifetime/scale_factor ⇒ radius/碰撞圆/寿命
func activate() -> void:
	_pooled = false
	active_count += 1
	visible = true
	rotation = 0.0
	radius = RADIUS * maxf(scale_factor, 0.05)
	if _circle != null:
		_circle.radius = radius
		queue_redraw()
	lifetime = BASE_LIFETIME
	set_physics_process(true)
	# 碰撞恢复必须走 deferred：同一帧「回收→复用」时，回收的 disabled=true deferred
	# 会在帧末 flush，直接赋值的 false 会被它覆盖（照 BladeProjectile.activate 同一条坑）
	set_deferred("monitoring", true)
	_shape_node.set_deferred("disabled", false)

## 回收入池（替代 queue_free）：休眠物理与碰撞，池满或宿主失效才真释放
func _recycle() -> void:
	if _pooled:
		return
	_pooled = true
	active_count = maxi(0, active_count - 1)
	set_physics_process(false)
	set_deferred("monitoring", false)
	_shape_node.set_deferred("disabled", true)
	visible = false
	if _host == null or not is_instance_valid(_host) or _pool.size() >= POOL_CAP:
		queue_free()
		return
	_pool.append(self)

func _draw() -> void:
	# 描边中心放在 radius - 1、线宽 2 ⇒ 最外沿正好压在判定圆上，视觉永不超过实际范围
	draw_circle(Vector2.ZERO, radius, BODY_COLOR)
	draw_arc(Vector2.ZERO, maxf(radius - 1.0, 1.0), 0.0, TAU, 24, RIM_COLOR, 2.0, true)
	draw_circle(Vector2.ZERO, radius * 0.45, CORE_COLOR)

func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0.0:
		_recycle()

func _on_body_entered(body: Node) -> void:
	if body is Player:
		# 受击火花/跳字统一由 Player.take_damage 发放（与 BladeProjectile 同一约定）：
		# 弹体侧再发一份，闪避/无敌帧会在没掉血时凭空闪白光，真命中又和玩家侧双发
		body.take_damage(damage)
		_recycle()
