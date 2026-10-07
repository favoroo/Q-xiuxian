extends Node

signal player_hp_changed(current_hp: float, max_hp: float)
signal player_exp_changed(current_exp: int, target_exp: int, level: int)
signal player_leveled_up(level: int)
signal stats_updated(kills: int, game_time: float, astral_shards: int)
signal game_over_triggered(victory: bool)
signal upgrade_applied(upgrade_id: String)
signal announcement_triggered(text: String)
signal weapons_updated(weapons: Array)

var player: Node2D = null
var joystick: Control = null
var main_camera: Camera2D = null

var kills: int = 0
var game_time: float = 0.0
var astral_shards: int = 0
var level: int = 1
var experience: int = 0
var experience_to_next: int = 10
var is_game_over: bool = false

# Player upgrade modifiers
var blade_damage_mult: float = 1.0
var blade_count: int = 1
var blade_cooldown_mult: float = 1.0
var sun_orb_count: int = 1
var sun_orb_damage_mult: float = 1.0
var move_speed_mult: float = 1.0
var pickup_range_mult: float = 1.0
var has_radiance_synergy: bool = false

func reset_run() -> void:
    kills = 0
    game_time = 0.0
    astral_shards = 0
    level = 1
    experience = 0
    experience_to_next = 10
    is_game_over = false
    
    blade_damage_mult = 1.0
    blade_count = 1
    blade_cooldown_mult = 1.0
    sun_orb_count = 1
    sun_orb_damage_mult = 1.0
    move_speed_mult = 1.0
    pickup_range_mult = 1.0
    has_radiance_synergy = false

func _process(delta: float) -> void:
    if not is_game_over and not get_tree().paused and player != null:
        game_time += delta
        stats_updated.emit(kills, game_time, astral_shards)

func add_experience(amount: int) -> void:
    if is_game_over:
        return
    experience += amount
    astral_shards += amount
    AudioManager.play_sfx("gem_pickup")
    
    while experience >= experience_to_next:
        experience -= experience_to_next
        level += 1
        experience_to_next = int(experience_to_next * 1.35) + 5
        AudioManager.play_sfx("level_up")
        player_leveled_up.emit(level)
    
    player_exp_changed.emit(experience, experience_to_next, level)
    stats_updated.emit(kills, game_time, astral_shards)

func register_kill(is_elite: bool = false) -> void:
    kills += 1
    if is_elite:
        astral_shards += 25
    stats_updated.emit(kills, game_time, astral_shards)

func notify_weapons_updated(weapons: Array) -> void:
    weapons_updated.emit(weapons)

func apply_upgrade(upgrade_id: String) -> void:
    match upgrade_id:
        "add_sword":
            if player and player.has_method("add_floating_weapon"):
                player.add_floating_weapon("sword", 1, "铝制球棒")
        "add_staff":
            if player and player.has_method("add_floating_weapon"):
                player.add_floating_weapon("staff", 0, "自制弹弓")
        "blade_damage":
            blade_damage_mult += 0.35
        "blade_amount":
            blade_count += 1
        "blade_cooldown":
            blade_cooldown_mult = maxf(0.28, blade_cooldown_mult * 0.78)
        "sun_orb_add":
            sun_orb_count += 1
        "sun_orb_damage":
            sun_orb_damage_mult += 0.45
        "move_speed":
            move_speed_mult += 0.18
        "max_hp":
            if player and player.has_method("increase_max_hp"):
                player.increase_max_hp(30.0, 40.0)
        "pickup_range":
            pickup_range_mult += 0.45
        "synergy_radiance":
            has_radiance_synergy = true
    
    upgrade_applied.emit(upgrade_id)

func shake_camera(intensity: float = 3.5, duration: float = 0.12) -> void:
    if main_camera and main_camera.has_method("shake"):
        main_camera.shake(intensity, duration)

func trigger_hitstop(duration: float = 0.025) -> void:
    Engine.time_scale = 0.15
    get_tree().create_timer(duration * 0.15, true, false, true).timeout.connect(
        func(): Engine.time_scale = 1.0
    )

func trigger_game_over(victory: bool = false) -> void:
    if is_game_over:
        return
    is_game_over = true
    game_over_triggered.emit(victory)
