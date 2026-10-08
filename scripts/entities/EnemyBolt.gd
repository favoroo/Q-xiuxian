class_name EnemyBolt
extends Area2D

## 敌方剑气弹：御剑邪修发射，直线飞行，命中玩家造成伤害
## 纯代码构建，无需场景文件

var direction: Vector2 = Vector2.RIGHT
var speed: float = 300.0
var damage: float = 6.0
var lifetime: float = 3.0

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # player
	rotation = direction.angle()

	var sprite := Sprite2D.new()
	sprite.texture = load("res://assets/art/weapon_dagger.png")
	sprite.modulate = Color(1.3, 0.55, 0.75)
	sprite.scale = Vector2(0.5, 0.5)
	add_child(sprite)

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 8.0
	shape.shape = circle
	add_child(shape)

	# 发光尾迹
	var glow := Sprite2D.new()
	var glow_tex := load("res://assets/art/light_radial.png") as Texture2D
	if glow_tex != null:
		glow.texture = glow_tex
		glow.modulate = Color(1.2, 0.4, 0.6, 0.55)
		glow.scale = Vector2(0.5, 0.5)
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		glow.material = mat
		add_child(glow)

	body_entered.connect(_on_body_entered)

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
