class_name SunOrb
extends Area2D

@export var base_damage: float = 18.0
var hit_cooldowns: Dictionary = {}

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
            hit_cooldowns[id] = 0.35
            var dmg = base_damage * GameManager.sun_orb_damage_mult
            var knockback = (enemy.global_position - global_position).normalized() * 165.0
            enemy.take_damage(dmg, knockback, false)
            AudioManager.play_sfx("orb_hit", 1.0)
