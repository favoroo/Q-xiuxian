extends Control

## tests/blink_rift_preview.gd — 瞬移落点符环 + Boss 瞬移前摇现场预览（非判据）
##
## 用途：肉眼验收「起手 → 去向 → 离开 → 现身」四段读法。
##   上排：普通 / 精英 / 魔君三档符环循环重放（收缩速度 = 实际前摇）。
##   下排：幽冥剑魄尊循环演示 瞬步回斩 / 阵眼换桩；落点符环填满才落地，落地后才出招。
##
## 跑法（需要真实窗口出图，headless 下看不到演出）：
##   G=/Applications/Godot.app/Contents/MacOS/Godot
##   $G --path . res://tests/BlinkRiftPreview.tscn

const BOSS_SCENE := "res://scenes/entities/BossEnemy.tscn"
const PLAYER_SCENE := "res://scenes/entities/Player.tscn"

## 三档符环演示位（上排）
const RIFT_POS: Array[Vector2] = [Vector2(190.0, 120.0), Vector2(480.0, 120.0), Vector2(770.0, 120.0)]
const RIFT_DUR: Array[float] = [GameBalance.BLINK_WINDUP, GameBalance.MUT_JIANSHA_BLINK_WINDUP,
	GameBalance.BOSS_BLINK_SLASH_WINDUP]
const RIFT_RAD: Array[float] = [BlinkRift.RADIUS_NORMAL, BlinkRift.RADIUS_ELITE, BlinkRift.RADIUS_BOSS]

var _world: Node2D
var _boss: BossEnemy
var _player: Player
var _rifts: Array[BlinkRift] = [null, null, null]
var _caption: Label
var _demo_timer: float = 0.8
var _demo_step: int = 0

func _ready() -> void:
	custom_minimum_size = Vector2(960, 540)

	var bg := ColorRect.new()
	bg.color = Color(0.045, 0.05, 0.075)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "瞬移落点符环 · 起手 → 去向 → 离开 → 现身"
	title.position = Vector2(18.0, 8.0)
	GameStyle.label(title, 16, GameStyle.PAPER, 0, GameStyle.INK, true)
	add_child(title)

	_caption = Label.new()
	_caption.text = "上排：普通 / 精英 / 魔君三档收束速度；下排：Boss 落地后才出招"
	_caption.position = Vector2(18.0, 508.0)
	GameStyle.label(_caption, 13, GameStyle.PAPER, 0, GameStyle.INK, true)
	add_child(_caption)

	_world = Node2D.new()
	add_child(_world)

	GameManager.reset_run()
	GameManager.cultivator_id = "jianchi"
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	_world.add_child(_player)
	_player.global_position = Vector2(660.0, 330.0)
	_player.max_health = 999999.0
	_player.current_health = 999999.0

	_boss = (load(BOSS_SCENE) as PackedScene).instantiate() as BossEnemy
	_boss.boss_id = "jianpo"
	_world.add_child(_boss)
	_boss.global_position = Vector2(300.0, 330.0)
	_boss.max_hp = 999999.0
	_boss.current_hp = 999999.0
	# 关掉所有自动出招/移动：预览只演示「瞬移前摇」这一件事
	_boss.attack_interval = 9999.0
	_boss._attack_timer = 9999.0
	_boss.move_speed = 0.0
	_boss.charge_interval = 0.0
	_boss.bolt_interval = 0.0
	_boss.slam_interval = 0.0
	_boss.field_interval = 0.0
	_boss.ring_bolt_interval = 0.0
	_boss.rock_interval = 0.0
	GameManager.player = _player

func _exit_tree() -> void:
	BlinkRift.clear_pool()

func _process(delta: float) -> void:
	_loop_rifts()
	_demo_timer -= delta
	if _demo_timer <= 0.0:
		_demo_timer = 1.9
		if _demo_step % 2 == 0:
			_boss._cast_blink_slash(_player)
			_caption.text = "瞬步回斩：起手 0.40s → 落点符环填满 → 现身 → 扇形剑气"
		else:
			_boss._cast_turret_shift(_player)
			_caption.text = "阵眼换桩：起手 0.42s → 新阵点符环填满 → 换位 + 旧桩小环弹"
		_demo_step += 1

## 三档符环循环：上一次回池后立刻在原点位重新取一只（池化复用，零节点 churn）
func _loop_rifts() -> void:
	for i in range(3):
		var r: BlinkRift = _rifts[i]
		if r == null or not is_instance_valid(r) or not r.is_inside_tree():
			var col: Color = [GameStyle.BAD, GameStyle.POISON, _boss._fx_color][i]
			_rifts[i] = BlinkRift.acquire(_world, RIFT_POS[i], RIFT_DUR[i], col, RIFT_RAD[i])