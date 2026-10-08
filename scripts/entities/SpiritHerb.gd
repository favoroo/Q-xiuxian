class_name SpiritHerb
extends Node2D

## 灵药丛：竞技场内随机刷新的可破坏灵植（Brotato 树木的修仙版）
## 被任意武器波及即摧毁：60% 掉回春果（回 15% 气血），40% 掉藏宝匣（3 颗金灵石）
## 挂在 4 号层（enemies）让武器判定能碰到；加入 herbs 组使自动索敌跳过它

var gem_scene: PackedScene = preload("res://scenes/entities/AstralGem.tscn")
var gold_gem_tex: Texture2D = preload("res://assets/art/gem_gold.png")

var _sprite: Sprite2D

func _ready() -> void:
	add_to_group("herbs")

	var herb := Area2D.new()
	herb.collision_layer = 4
	herb.collision_mask = 0
	add_child(herb)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 20.0
	shape.shape = circle
	herb.add_child(shape)

	_sprite = Sprite2D.new()
	_sprite.texture = load("res://assets/art/icon_regen.png")
	_sprite.modulate = Color(0.7, 1.3, 0.75)
	add_child(_sprite)

	# 破土而出 + 呼吸摇曳
	_sprite.scale = Vector2.ZERO
	var tw := create_tween()
	tw.tween_property(_sprite, "scale", Vector2(0.7, 0.7), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var sway := create_tween().set_loops()
	sway.tween_property(_sprite, "rotation", 0.09, 0.9).set_trans(Tween.TRANS_SINE)
	sway.tween_property(_sprite, "rotation", -0.09, 0.9).set_trans(Tween.TRANS_SINE)

## 武器判定命中（与 EnemyBase 同签名，被挥砍/落雷/弹丸/灵蝶波及）
func take_damage(_amount: float, _knockback: Vector2, _is_crit: bool = false) -> void:
	_destroy()

func _destroy() -> void:
	if is_queued_for_deletion():
		return
	JuiceEffect.spawn_death_burst(get_parent(), global_position, false)
	AudioManager.play_sfx("gem_pickup", 0.8)
	if randf() < 0.6:
		var fruit := HealOrb.new()
		fruit.global_position = global_position
		fruit.heal_pct = 0.15
		get_parent().call_deferred("add_child", fruit)
	else:
		for i in range(3):
			var gem := gem_scene.instantiate() as AstralGem
			gem.global_position = global_position + Vector2(randf_range(-20.0, 20.0), randf_range(-20.0, 20.0))
			gem.is_gold = true
			gem.exp_value = 5
			gem.get_node("Sprite2D").texture = gold_gem_tex
			gem.get_node("PointLight2D").color = Color(1.0, 0.82, 0.35)
			get_parent().call_deferred("add_child", gem)
	queue_free()
