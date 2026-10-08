class_name SunOrb
extends Area2D

## 灵蝶：环绕玩家的灵体，接触伤害走 WeaponData「灵蝶」定义，星级影响伤害/冷却/体型

var star: int = 1
var base_damage: float = 15.0
var hit_cooldown: float = 0.35
var hit_cooldowns: Dictionary = {}
var _pulse_tween: Tween = null

@onready var sprite: Sprite2D = $Sprite2D
@onready var _base_sprite_scale: Vector2 = sprite.scale

## 由 Player.sync_drones 下发星级（必须在节点可用后调用）
func setup(star_level: int) -> void:
	star = clampi(star_level, 1, WeaponData.MAX_STAR)
	base_damage = WeaponData.damage_for("lingdie", star)
	hit_cooldown = WeaponData.cooldown_for("lingdie", star)
	if is_inside_tree():
		_apply_star_visuals()

func _ready() -> void:
	_apply_star_visuals()

func _apply_star_visuals() -> void:
	# 高星灵蝶更大更金：★1 青 → ★2 偏金 → ★3 金亮
	sprite.scale = _base_sprite_scale * (1.0 + 0.14 * float(star - 1))
	var tint := Color(1, 1, 1)
	if star >= 2:
		tint = Color(1.0, 0.95, 0.72) if star == 2 else Color(1.0, 0.88, 0.45)
	sprite.modulate = tint

func _process(delta: float) -> void:
	var to_erase: Array = []
	for enemy_id in hit_cooldowns.keys():
		hit_cooldowns[enemy_id] -= delta
		if hit_cooldowns[enemy_id] <= 0.0:
			to_erase.append(enemy_id)
	for k in to_erase:
		hit_cooldowns.erase(k)

func _on_area_entered(area: Area2D) -> void:
	_try_damage(area)

func _try_damage(area: Area2D) -> void:
	var enemy = area.get_parent()
	if enemy and enemy.has_method("take_damage"):
		var id = enemy.get_instance_id()
		if not hit_cooldowns.has(id):
			hit_cooldowns[id] = hit_cooldown
			var is_crit = randf() < GameManager.get_crit_rate()
			var dmg = base_damage * GameManager.weapon_damage_mult * GameManager.synergy_damage_mult * GameManager.cultivator_damage_mult("lingdie") * (GameManager.crit_mult if is_crit else 1.0)
			var knockback = (enemy.global_position - global_position).normalized() * 165.0
			enemy.take_damage(dmg, knockback, is_crit)
			GameManager.try_lifesteal()
			_play_hit_pulse()
			AudioManager.play_sfx("orb_hit", 1.0)

## 触敌反馈：灵蝶扑闪一下（压扁弹回 + 亮闪）
func _play_hit_pulse() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	sprite.modulate = Color(1.7, 1.7, 1.35)
	sprite.scale = _base_sprite_scale * Vector2(1.25, 0.8) * (1.0 + 0.14 * float(star - 1))
	_pulse_tween = create_tween()
	_pulse_tween.set_parallel(true)
	_pulse_tween.tween_property(sprite, "modulate", _star_tint(), 0.16)
	_pulse_tween.tween_property(sprite, "scale", _base_sprite_scale * (1.0 + 0.14 * float(star - 1)), 0.16)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _star_tint() -> Color:
	if star >= 3:
		return Color(1.0, 0.88, 0.45)
	if star == 2:
		return Color(1.0, 0.95, 0.72)
	return Color.WHITE
