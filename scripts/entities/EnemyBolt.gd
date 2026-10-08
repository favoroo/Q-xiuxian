class_name EnemyBolt
extends Area2D

## 敌方剑气弹：御剑邪修发射，直线飞行，命中玩家造成伤害
## 纯代码构建，无需场景文件

var direction: Vector2 = Vector2.RIGHT
var speed: float = 300.0
var damage: float = 6.0
var lifetime: float = 3.0
var scale_factor: float = 1.0  ## 视觉与碰撞整体缩放（Boss 环弹比普通剑气大）

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # player
	# 火球不旋转，保持圆形
	rotation = 0.0

	# 外焰（大圆，黄色，additive blend）
	var outer := Sprite2D.new()
	outer.texture = load("res://assets/art/light_radial.png")
	outer.modulate = Color(1.0, 0.85, 0.3, 0.7)
	outer.scale = Vector2.ONE * scale_factor
	var outer_mat := CanvasItemMaterial.new()
	outer_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	outer.material = outer_mat
	add_child(outer)

	# 核心（小圆，橙红色）
	var core := Sprite2D.new()
	core.texture = load("res://assets/art/light_radial.png")
	core.modulate = Color(1.0, 0.4, 0.15, 1.0)
	core.scale = Vector2(0.55, 0.55) * scale_factor
	add_child(core)

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 8.0 * scale_factor
	shape.shape = circle
	add_child(shape)

	# 发光尾迹（橙红色）
	var glow := Sprite2D.new()
	var glow_tex := load("res://assets/art/light_radial.png") as Texture2D
	if glow_tex != null:
		glow.texture = glow_tex
		glow.modulate = Color(1.0, 0.5, 0.2, 0.5)
		glow.scale = Vector2(0.5, 0.5) * scale_factor
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		glow.material = mat
		add_child(glow)

	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	lifetime -= delta
	
	# 外焰脉动动画（周期约 0.3 秒）
	var outer = get_child(0) as Sprite2D
	if outer != null:
		var pulse: float = 1.0 + sin(lifetime * 20.0) * 0.05
		outer.scale = Vector2(pulse, pulse)
	
	if lifetime <= 0.0:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if body is Player:
		body.take_damage(damage)
		JuiceEffect.spawn_hit_sparks(get_parent(), global_position, direction, false)
		queue_free()
