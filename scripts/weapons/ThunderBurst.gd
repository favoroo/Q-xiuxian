class_name ThunderBurst
extends Node2D

## 五雷法牌的落雷爆发：命中范围内所有敌人一次，短暂闪光后自毁

var radius: float = 80.0
var damage: float = 35.0
var proc_burn: bool = false
var burn_dps: float = 0.0
var burn_dur: float = 3.0

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
	# 震屏挪到 _deal_damage 里按战果发放：劈空的落雷不该让镜头跟着抖一下
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
	var hits := 0
	var kills := 0
	var hit_elite := false
	for res in results:
		var col = res["collider"]
		if col and col.get_parent() and col.get_parent().has_method("take_damage"):
			var enemy = col.get_parent()
			var is_crit: bool = GameManager.rng.randf() < GameManager.get_crit_rate()
			var crit_m: float = GameManager.crit_mult + GameManager.synergy_crit_mult
			var dmg: float = damage * (crit_m if is_crit else 1.0) * GameManager.elite_damage_mult_for(enemy)
			# 震退方向走统一出口：落雷点常在玩家外侧，纯径向会把落点内侧那圈敌人往玩家身上拱
			var knock: Vector2 = GameManager.knockback_vec(global_position, enemy.global_position, 200.0)
			# 灵药丛（SpiritHerb）也有 take_damage 但没有 dying/is_elite 字段，
			# 所以一律走 get()：取不到就当 false，不许在这里炸一场落雷
			var was_dying := bool(enemy.get("dying"))
			enemy.take_damage(dmg, knock, is_crit)
			if proc_burn and enemy.has_method("apply_burn"):
				enemy.apply_burn(burn_dps, burn_dur)
			GameManager.try_lifesteal()
			hits += 1
			if bool(enemy.get("dying")) and not was_dying:
				kills += 1
			if bool(enemy.get("is_elite")):
				hit_elite = true
			if is_crit:
				had_crit = true
	if had_crit:
		GameManager.hit_stop(0.04, 0.06)
	if hits == 0:
		return
	# 落雷是本作少数「值得抖一下」的节点，量按战果给：劈到就轻震，收掉多命/劈到精英才加码
	var trauma := 0.16
	if kills >= 3:
		trauma += 0.10
	if hit_elite:
		trauma += 0.14
	GameManager.add_trauma(trauma)
	if kills >= 3 or hit_elite:
		GameManager.zoom_punch(0.025, 0.14)
