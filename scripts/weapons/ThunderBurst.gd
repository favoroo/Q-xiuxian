class_name ThunderBurst
extends Node2D

## 五雷法牌的落雷爆发：命中范围内所有敌人一次，短暂闪光后自毁

var radius: float = 80.0
var damage: float = 35.0

@onready var fx_sprite: Sprite2D = $FxSprite
@onready var light: PointLight2D = $PointLight2D

func _ready() -> void:
	fx_sprite.scale = Vector2.ONE * 0.2
	fx_sprite.modulate = Color(1.0, 0.95, 0.6, 0.0)
	_spawn_sky_beam()

	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(fx_sprite, "modulate:a", 0.95, 0.05)
	tw.tween_property(fx_sprite, "scale", Vector2.ONE * (radius * 2.0 / 128.0), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(light, "energy", 2.2, 0.06)
	tw.chain().tween_property(fx_sprite, "modulate:a", 0.0, 0.18)
	tw.parallel().tween_property(light, "energy", 0.0, 0.2)
	tw.chain().tween_callback(queue_free)

	_deal_damage.call_deferred()
	JuiceEffect.spawn_death_burst(get_parent(), global_position, true)
	GameManager.add_trauma(0.28)
	GameManager.zoom_punch(0.025, 0.14)
	AudioManager.play_sfx("obelisk_blessing", 0.55)

## 天雷柱：从天而降的竖直雷光，强化「雷从天上来」的落点感知
func _spawn_sky_beam() -> void:
	var beam := Line2D.new()
	beam.points = PackedVector2Array([Vector2(0.0, -200.0), Vector2(0.0, 0.0)])
	beam.width = maxf(radius * 0.24, 16.0)
	beam.default_color = Color(1.0, 0.97, 0.8, 0.8)
	beam.begin_cap_mode = Line2D.LINE_CAP_ROUND
	beam.end_cap_mode = Line2D.LINE_CAP_ROUND
	var curve := Curve.new()
	curve.add_point(Vector2(0.25, 0.0))
	curve.add_point(Vector2(1.0, 1.0))
	beam.width_curve = curve
	add_child(beam)
	var btw = create_tween()
	btw.tween_property(beam, "modulate:a", 0.0, 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _deal_damage() -> void:
	var space_state = get_world_2d().direct_space_state
	var shape = CircleShape2D.new()
	shape.radius = radius
	var query = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = 4
	query.collide_with_areas = true
	var results = space_state.intersect_shape(query, 24)

	var had_crit := false
	for res in results:
		var col = res["collider"]
		if col and col.get_parent() and col.get_parent().has_method("take_damage"):
			var enemy = col.get_parent()
			var is_crit = randf() < GameManager.get_crit_rate()
			var dmg = damage * (GameManager.crit_mult if is_crit else 1.0)
			var knock = (enemy.global_position - global_position).normalized() * 200.0
			enemy.take_damage(dmg, knock, is_crit)
			GameManager.try_lifesteal()
			if is_crit:
				had_crit = true
	if had_crit:
		GameManager.hit_stop(0.04, 0.06)
