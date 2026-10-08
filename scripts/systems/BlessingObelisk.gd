class_name BlessingObelisk
extends Node2D

@export var charge_time_needed: float = 3.0
var current_charge: float = 0.0
var is_player_inside: bool = false
var is_triggered: bool = false

@onready var light: PointLight2D = $PointLight2D
@onready var circle_sprite: Node2D = $ChargeCircle
@onready var charge_bar: ProgressBar = $ProgressBar

var gem_scene: PackedScene = preload("res://scenes/entities/AstralGem.tscn")
var gold_gem_tex: Texture2D = preload("res://assets/art/gem_gold.png")

func _ready() -> void:
    charge_bar.visible = false
    charge_bar.max_value = charge_time_needed

func _process(delta: float) -> void:
    if is_triggered:
        return
        
    if is_player_inside:
        charge_bar.visible = true
        current_charge = minf(charge_time_needed, current_charge + delta)
        charge_bar.value = current_charge
        light.energy = 1.2 + (current_charge / charge_time_needed) * 1.5
        circle_sprite.rotation += delta * 1.8
        
        if current_charge >= charge_time_needed:
            _trigger_blessing()
    else:
        if current_charge > 0.0:
            current_charge = maxf(0.0, current_charge - delta * 1.5)
            charge_bar.value = current_charge
            light.energy = 1.2 + (current_charge / charge_time_needed) * 1.5
        else:
            charge_bar.visible = false

func _trigger_blessing() -> void:
    is_triggered = true
    charge_bar.visible = false
    AudioManager.play_sfx("obelisk_blessing")
    GameManager.feedback(GameManager.FeedbackTier.HEAVY)
    JuiceEffect.spawn_death_burst(get_parent(), global_position, true)
    GameManager.announcement_triggered.emit("⚠ 聚灵阵成 · 灵气冲击震荡全场 ⚠")
    
    # Damage and knockback all enemies on screen
    var enemies = get_tree().get_nodes_in_group("enemies")
    for enemy in enemies:
        if is_instance_valid(enemy) and enemy.has_method("take_damage"):
            var knock = (enemy.global_position - global_position).normalized() * 320.0
            enemy.take_damage(85.0, knock, true)
            
    # Spawn gold gems
    for i in range(5):
        var gem = gem_scene.instantiate() as AstralGem
        var offset = Vector2(randf_range(-40.0, 40.0), randf_range(-40.0, 40.0))
        gem.global_position = global_position + offset
        gem.is_gold = true
        gem.exp_value = 10
        gem.get_node("Sprite2D").texture = gold_gem_tex
        gem.get_node("PointLight2D").color = Color(1.0, 0.85, 0.35)
        get_parent().call_deferred("add_child", gem)
        
    # Visual pulse effect
    var tw = create_tween()
    tw.tween_property(light, "energy", 4.0, 0.15)
    tw.tween_property(light, "energy", 0.6, 0.45)
    tw.tween_property(circle_sprite, "modulate:a", 0.2, 0.3)

func _on_interaction_area_body_entered(body: Node2D) -> void:
    if body is Player:
        is_player_inside = true

func _on_interaction_area_body_exited(body: Node2D) -> void:
    if body is Player:
        is_player_inside = false
