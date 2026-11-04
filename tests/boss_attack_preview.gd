extends Node2D

## Boss 三新招出图台（非判据，不参与判据绿线）：
## 把「玄光贯日 / 烈焰吐息 / 陨火天降」按真机路径各放一次，抓三张 PNG 供肉眼验收。
## 为什么要有：这三招的「画多大判多大」由 BossVarietyCheck 钉住数值，
## 但「光束是不是从 Boss 手里出来、扇形是不是朝着玩家、陨石影子有没有落在地上」只能看图。
## 运行（不能加 --headless，headless 不渲染、get_image 拿空图）：
##   $G --path . res://tests/BossAttackPreview.tscn
## 产物：/tmp/boss_laser.png、/tmp/boss_flame.png、/tmp/boss_meteor.png

const SHEET := "res://assets/art/"
const BOSS_AT := Vector2(560, 360)
const PLAYER_AT := Vector2(900, 360)

var _boss: BossEnemy = null
var _player: Player = null

func _ready() -> void:
	var tile: Texture2D = load(SHEET + "courtyard_tile.png")
	var tw := int(tile.get_width())
	for y in range(0, int(720.0 / tw) + 2):
		for x in range(0, int(1280.0 / tw) + 2):
			var s := Sprite2D.new()
			s.texture = tile
			s.position = Vector2(x * tw + tw / 2.0, y * tw + tw / 2.0)
			add_child(s)

	# 玩家桩：用真 Player 场景（EnemyBase 朝向会读 player），摆好后停掉它的物理，
	# 保证出图期间玩家不挪窝 —— 否则每张图的弹道方向都在飘。
	GameManager.cultivator_id = "jianchi"
	var p_scene: PackedScene = load("res://scenes/entities/Player.tscn")
	_player = p_scene.instantiate() as Player
	add_child(_player)
	_player.global_position = PLAYER_AT
	_player.max_health = 999999.0
	_player.current_health = 999999.0
	_player.invulnerable_time = 99999.0
	_player.set_physics_process(false)
	_player.set_process(false)
	GameManager.player = _player

	await _shot_laser()
	await _shot_flame()
	await _shot_meteor()

	get_tree().quit(0)

func _make_boss(bid: String) -> BossEnemy:
	# 上一尊延后释放即可（本台只出图，不让两尊同屏互打；move_speed=0 保证不追人）
	if _boss != null and is_instance_valid(_boss):
		_boss.queue_free()
		_boss = null
	var scene: PackedScene = load("res://scenes/entities/BossEnemy.tscn")
	_boss = scene.instantiate() as BossEnemy
	_boss.boss_id = bid
	add_child(_boss)
	_boss.global_position = BOSS_AT
	_boss.move_speed = 0.0
	_boss.velocity = Vector2.ZERO
	_boss.attack_interval = 999.0
	_boss._attack_timer = 999.0
	return _boss

func _shot_laser() -> void:
	var boss := _make_boss("qianji")
	await get_tree().process_frame
	print("[PREVIEW] laser boss=", boss.global_position, " player=", _player.global_position)
	boss._cast_laser_sweep(_player)
	# 充能 0.95s + 出束 0.42s：抓「束已亮、还没收」的那一帧
	await _wait(GameBalance.BOSS_LASER_CHARGE + 0.16)
	await _capture("/tmp/boss_laser.png")
	await _wait(GameBalance.BOSS_LASER_FIRE + 0.3)

func _shot_flame() -> void:
	var boss := _make_boss("chiyan")
	await get_tree().process_frame
	print("[PREVIEW] flame boss=", boss.global_position, " player=", _player.global_position)
	boss._cast_flame_cone(_player)
	# 前摇 0.7s 后出火：抓扇形铺满 + 火柱起手
	await _wait(GameBalance.BOSS_FLAME_WINDUP + 0.3)
	await _capture("/tmp/boss_flame.png")
	await _wait(GameBalance.BOSS_FLAME_BREATH + 0.3)

func _shot_meteor() -> void:
	var boss := _make_boss("chiyan")
	await get_tree().process_frame
	print("[PREVIEW] meteor boss=", boss.global_position, " player=", _player.global_position)
	boss._cast_meteor_strike(_player)
	# 坠落中：陨石+火尾+落点阴影同屏（地上那圈就是判定）
	await _wait(GameBalance.BOSS_METEOR_FALL * 0.62)
	await _capture("/tmp/boss_meteor.png")
	await _wait(GameBalance.BOSS_METEOR_FALL + 0.4)

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _capture(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(path)
		print("SAVED ", path, " ", img.get_size())
