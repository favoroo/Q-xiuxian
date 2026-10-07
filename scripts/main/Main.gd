class_name MainLevel
extends Node2D

@onready var joystick: Control = $UILayer/VirtualJoystick
var dust_particles: CPUParticles2D

func _ready() -> void:
    GameManager.reset_run()
    GameManager.joystick = joystick
    GameManager.announcement_triggered.emit("✦ 轮回试炼开启·晨曦圣庭 ✦")
    _setup_dust()
    
    if ResourceLoader.exists("res://assets/audio/bgm_sanctuary_dawn.mp3"):
        var bgm = load("res://assets/audio/bgm_sanctuary_dawn.mp3")
        if bgm is AudioStreamMP3:
            bgm.loop = true
        AudioManager.play_bgm(bgm)
        
    if ResourceLoader.exists("res://assets/audio/vo_guide_start.wav"):
        var vo = load("res://assets/audio/vo_guide_start.wav")
        AudioManager.play_voice(vo)

func _setup_dust() -> void:
    dust_particles = CPUParticles2D.new()
    dust_particles.amount = 18
    dust_particles.lifetime = 2.5
    dust_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
    dust_particles.emission_rect_extents = Vector2(480, 280)
    dust_particles.gravity = Vector2(3.0, 5.0)
    dust_particles.initial_velocity_min = 6.0
    dust_particles.initial_velocity_max = 14.0
    dust_particles.scale_amount_min = 1.5
    dust_particles.scale_amount_max = 3.0
    dust_particles.color = Color(0.9, 0.85, 0.72, 0.3)
    $AtmosphereLayer.add_child(dust_particles)

func _process(_delta: float) -> void:
    if GameManager.player != null and is_instance_valid(GameManager.player):
        if dust_particles != null:
            dust_particles.global_position = GameManager.player.global_position
