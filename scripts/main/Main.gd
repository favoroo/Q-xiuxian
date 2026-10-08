class_name MainLevel
extends Node2D

@onready var joystick: Control = $UILayer/VirtualJoystick
@onready var weapon_select: Control = $UILayer/StartWeaponSelect
@onready var pause_menu: PauseMenu = $UILayer/PauseMenu
var dust_particles: CPUParticles2D

func _ready() -> void:
    GameManager.reset_run()
    GameManager.joystick = joystick
    _setup_dust()
    _setup_map_bounds()
    $UILayer/GameHUD.pause_requested.connect(pause_menu.open)

    if ResourceLoader.exists("res://assets/audio/bgm_cultivation.mp3"):
        var bgm = load("res://assets/audio/bgm_cultivation.mp3")
        if bgm is AudioStreamMP3:
            bgm.loop = true
        AudioManager.play_bgm(bgm)

    if ResourceLoader.exists("res://assets/audio/vo_guide_start.wav"):
        var vo = load("res://assets/audio/vo_guide_start.wav")
        AudioManager.play_voice(vo)

    # 开局暂停：先选本命法器再开战
    weapon_select.show_select()
    get_tree().paused = true

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
    dust_particles.color = Color(0.75, 0.85, 0.9, 0.2)
    $AtmosphereLayer.add_child(dust_particles)

func _process(_delta: float) -> void:
    if GameManager.player != null and is_instance_valid(GameManager.player):
        if dust_particles != null:
            dust_particles.global_position = GameManager.player.global_position

## 灵田界碑：可活动范围（GameManager.MAP_HALF_EXTENT）之外压暗，
## 边界描墨线 + 内侧蓝线 + 黄色四角括号，明示「这里就是地图边缘」
func _setup_map_bounds() -> void:
    var map: Node2D = $MapLayer
    var half: float = GameManager.MAP_HALF_EXTENT
    var ground_half: float = 2400.0

    # 1. 场外压暗：边界到地砖边缘的四块遮罩
    var dim := Color(0.02, 0.04, 0.09, 0.66)
    var bands := [
        [Vector2(-ground_half, -ground_half), Vector2(ground_half * 2.0, ground_half - half)],
        [Vector2(-ground_half, half), Vector2(ground_half * 2.0, ground_half - half)],
        [Vector2(-ground_half, -half), Vector2(ground_half - half, half * 2.0)],
        [Vector2(half, -half), Vector2(ground_half - half, half * 2.0)],
    ]
    for b in bands:
        var rect := ColorRect.new()
        rect.color = dim
        rect.position = b[0]
        rect.size = b[1]
        rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
        map.add_child(rect)

    # 2. 界碑线：粗墨底线（±half）+ 内侧主蓝细线
    _add_bound_line(map, half, 18.0, Color(0.04, 0.06, 0.1, 0.95))
    _add_bound_line(map, half - 11.0, 5.0, Color(0.184, 0.49, 1.0, 0.85))

    # 3. 黄色四角括号（呼应 UI 的斜切黄块语言）
    var bracket_len: float = 110.0
    var inset: float = 22.0
    var corners := [
        Vector2(-half + inset, -half + inset), Vector2(1, 1),
        Vector2(half - inset, -half + inset), Vector2(-1, 1),
        Vector2(half - inset, half - inset), Vector2(-1, -1),
        Vector2(-half + inset, half - inset), Vector2(1, -1),
    ]
    for i in range(0, corners.size(), 2):
        var origin: Vector2 = corners[i]
        var sgn: Vector2 = corners[i + 1]
        var bracket := Line2D.new()
        bracket.points = PackedVector2Array([
            origin + Vector2(-sgn.x * bracket_len, 0),
            origin,
            origin + Vector2(0, -sgn.y * bracket_len),
        ])
        bracket.width = 9.0
        bracket.default_color = Color(1.0, 0.824, 0.302, 0.9)
        bracket.joint_mode = Line2D.LINE_JOINT_ROUND
        bracket.begin_cap_mode = Line2D.LINE_CAP_ROUND
        bracket.end_cap_mode = Line2D.LINE_CAP_ROUND
        bracket.z_index = 2
        map.add_child(bracket)

func _add_bound_line(parent: Node2D, half: float, width: float, color: Color) -> void:
    var line := Line2D.new()
    line.points = PackedVector2Array([
        Vector2(-half, -half), Vector2(half, -half),
        Vector2(half, half), Vector2(-half, half),
    ])
    line.width = width
    line.default_color = color
    line.closed = true
    line.joint_mode = Line2D.LINE_JOINT_ROUND
    line.z_index = 2
    parent.add_child(line)
