class_name WaveSpawner
extends Node2D

@export var max_enemies: int = 70
var spawn_timer: float = 0.0
var elite_timer: float = 55.0

var slime_scene: PackedScene = preload("res://scenes/entities/SlimeEnemy.tscn")
var flower_scene: PackedScene = preload("res://scenes/entities/FlowerEnemy.tscn")
var golem_scene: PackedScene = preload("res://scenes/entities/GolemEnemy.tscn")

func _process(delta: float) -> void:
    if GameManager.is_game_over:
        return
        
    var player = GameManager.player
    if player == null:
        return
        
    spawn_timer -= delta
    elite_timer -= delta
    
    # Check regular enemy spawn
    var spawn_interval = maxf(0.42, 1.35 - (GameManager.game_time / 180.0) * 0.9)
    if spawn_timer <= 0.0:
        spawn_timer = spawn_interval
        _spawn_regular_wave(player)
        
    # Elite spawn
    if elite_timer <= 0.0:
        elite_timer = randf_range(45.0, 60.0)
        _spawn_elite(player)

func _spawn_regular_wave(player: Node2D) -> void:
    var enemy_count = get_tree().get_nodes_in_group("enemies").size()
    if enemy_count >= max_enemies:
        return
        
    var count = 1
    if GameManager.game_time > 40.0:
        count = randi_range(1, 3)
        
    for i in range(count):
        var angle = randf() * TAU
        var spawn_dist = randf_range(380.0, 480.0)
        var pos = player.global_position + Vector2(cos(angle), sin(angle)) * spawn_dist
        
        var enemy_scene = slime_scene
        if GameManager.game_time > 25.0 and randf() < 0.45:
            enemy_scene = flower_scene
            
        var enemy = enemy_scene.instantiate() as EnemyBase
        enemy.global_position = pos
        enemy.add_to_group("enemies")
        get_parent().add_child(enemy)

func _spawn_elite(player: Node2D) -> void:
    var angle = randf() * TAU
    var pos = player.global_position + Vector2(cos(angle), sin(angle)) * 420.0
    var golem = golem_scene.instantiate() as EnemyBase
    golem.global_position = pos
    golem.add_to_group("enemies")
    get_parent().add_child(golem)
    
    GameManager.announcement_triggered.emit("【警报】防暴警察进场了！")
    GameManager.shake_camera(5.0, 0.25)
