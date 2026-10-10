class_name AstralGem
extends Area2D

@export var exp_value: int = 1
@export var is_gold: bool = false:
	set(val):
		is_gold = val
		_update_visual()

var target_player: Node2D = null
var current_speed: float = -40.0   # 初始微反冲：有被吸附瞬间的弹性缓冲
var max_speed: float = 680.0
var acceleration: float = 850.0

@onready var sprite: Sprite2D = $Sprite2D
var loot_renderer: ProceduralLootRenderer = null
var _bob_tween: Tween = null

func _ready() -> void:
	add_to_group("gems")
	if sprite != null:
		sprite.visible = false
	if loot_renderer == null:
		loot_renderer = ProceduralLootRenderer.new()
		add_child(loot_renderer)
	_update_visual()
	_bob_tween = create_tween().set_loops()
	_bob_tween.tween_property(loot_renderer, "position:y", -3.0, 0.45).set_trans(Tween.TRANS_SINE)
	_bob_tween.tween_property(loot_renderer, "position:y", 3.0, 0.45).set_trans(Tween.TRANS_SINE)

func _update_visual() -> void:
	if loot_renderer != null:
		loot_renderer.loot_type = ProceduralLootRenderer.LootType.GEM_GOLD if is_gold else ProceduralLootRenderer.LootType.GEM_BLUE
	var light = get_node_or_null("PointLight2D") as PointLight2D
	if light != null:
		light.color = Color(1.0, 0.85, 0.35) if is_gold else Color(0.4, 0.8, 1.0)

func magnet_to(player: Node2D) -> void:
	if target_player == null:
		target_player = player
		current_speed = -50.0
		if _bob_tween != null and _bob_tween.is_valid():
			_bob_tween.kill()

func _physics_process(delta: float) -> void:
	if target_player != null and is_instance_valid(target_player):
		var dir = (target_player.global_position - global_position).normalized()
		var dist = global_position.distance_to(target_player.global_position)
		current_speed = minf(max_speed, current_speed + acceleration * delta)
		global_position += dir * current_speed * delta

		if dist < 22.0:
			JuiceEffect.spawn_pickup_pop(get_parent(), global_position, is_gold)
			if target_player.has_method("play_squash"):
				target_player.play_squash(Vector2(0.96, 1.05), 0.12)
			GameManager.add_experience(exp_value)
			queue_free()
