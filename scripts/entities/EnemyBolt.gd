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
## 	同口径的既有先例：Boss 震地预警圈（BossEnemy.SlamRing 按半径画描边）、
## 	玩家法器弹丸（BladeProjectile 判定半径 7，刃的可见长度也就这个量级）。
## 	⇒ 要改火球大小只动 RADIUS 一个常数，外观与碰撞一起变，不许分开设。

const RADIUS := 8.0                  ## 基准判定半径（不含 scale_factor）：外观与碰撞的唯一来源
const BODY_COLOR := Color(1.0, 0.45, 0.12)   ## 球体
const CORE_COLOR := Color(1.0, 0.87, 0.45)   ## 高光芯
const RIM_COLOR := Color(0.42, 0.07, 0.04)   ## 硬描边，压在判定圆内侧

var direction: Vector2 = Vector2.RIGHT
var speed: float = 300.0
var damage: float = 6.0
var lifetime: float = 3.0
var scale_factor: float = 1.0  ## 整体缩放（Boss 环弹比普通火球大），外观与碰撞一起缩
var radius: float = RADIUS     ## 实际判定半径 = RADIUS × scale_factor，_ready 里定一次

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

	body_entered.connect(_on_body_entered)

func _draw() -> void:
	# 描边中心放在 radius - 1、线宽 2 ⇒ 最外沿正好压在判定圆上，视觉永不超过实际范围
	draw_circle(Vector2.ZERO, radius, BODY_COLOR)
	draw_arc(Vector2.ZERO, maxf(radius - 1.0, 1.0), 0.0, TAU, 24, RIM_COLOR, 2.0, true)
	draw_circle(Vector2.ZERO, radius * 0.45, CORE_COLOR)

func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if body is Player:
		body.take_damage(damage)
		JuiceEffect.spawn_hit_sparks(get_parent(), global_position, direction, false)
		queue_free()
