extends Control

## tests/blink_rift_preview.gd — 瞬移落点符环 + Boss 瞬移前摇现场预览（非判据）
##
## 用途：肉眼验收「起手吸积 → 去向预告 → 消失 → 落地爆闪」四段读法。
##   上排：普通 / 精英 / 魔君三档符环循环重放（收缩速度 = 实际前摇；魔君档带落顶光柱/目标十字）。
##   下排：玄天千机尊（W25）循环演示 Boss 档瞬移全流程；起手时脚下亮吸积环 + 本体收缩淡出，
##         落点符环填满才换位，落地爆闪后从落点胀回。
##
## 舞台直接用画布坐标（`_world` 不偏移）：三档符环与 Boss 演示位都按屏内取点，
## 保证起手段与落点段同屏可比。演示落点写死（不经 GameManager.rng）——
## 本预览只验画面，不验随机落点分布。
##
## 跑法（需要真实窗口出图，headless 下看不到演出）：
##   G=/Applications/Godot.app/Contents/MacOS/Godot
##   $G --path . res://tests/BlinkRiftPreview.tscn

const BOSS_SCENE := "res://scenes/entities/BossEnemy.tscn"
const PLAYER_SCENE := "res://scenes/entities/Player.tscn"

## 三档符环演示位（上排）：魔君档要留出 2.6×半径（≈161px）的落顶光柱高度，y 取 235 留出余量
const RIFT_POS: Array[Vector2] = [Vector2(240.0, 235.0), Vector2(500.0, 235.0), Vector2(860.0, 235.0)]
const RIFT_DUR: Array[float] = [GameBalance.BLINK_WINDUP, GameBalance.MUT_JIANSHA_BLINK_WINDUP,
	GameBalance.BOSS_BLINK_SLASH_WINDUP]
const RIFT_RAD: Array[float] = [BlinkRift.RADIUS_NORMAL, BlinkRift.RADIUS_ELITE, BlinkRift.RADIUS_BOSS]

## Boss 演示：本体站位与两个循环落点（都在屏内，保证起手与落点同屏可比）
const BOSS_HOME := Vector2(190.0, 430.0)
const DEMO_DEST: Array[Vector2] = [Vector2(700.0, 330.0), Vector2(470.0, 425.0)]

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
	title.text = "瞬移符环 · 起手吸积 → 落点光柱 → 消失 → 落地爆闪"
	title.position = Vector2(18.0, 8.0)
	GameStyle.label(title, 16, GameStyle.PAPER, 0, GameStyle.INK, true)
	add_child(title)

	_caption = Label.new()
	_caption.text = "上排：普通 / 精英 / 魔君三档收束速度；下排：玄天千机尊（W25）瞬移全流程"
	_caption.position = Vector2(18.0, 508.0)
	GameStyle.label(_caption, 13, GameStyle.PAPER, 0, GameStyle.INK, true)
	add_child(_caption)

	_world = Node2D.new()
	add_child(_world)

	GameManager.reset_run()
	GameManager.cultivator_id = "jianchi"
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	_world.add_child(_player)
	_player.global_position = Vector2(880.0, 480.0)
	_player.max_health = 999999.0
	_player.current_health = 999999.0
	_player.visible = false   # 预览只验瞬移演出，玩家不上屏（避免与符环抢视线）

	_boss = (load(BOSS_SCENE) as PackedScene).instantiate() as BossEnemy
	_boss.boss_id = "qianji"   # W25 玄天千机尊：换桩是其唯一位移技，预览对应用户现场
	_world.add_child(_boss)
	_boss.global_position = BOSS_HOME
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
		_demo_timer = 2.2
		_demo_step += 1
		# 本体回到起点再演一次（纯表现调用，不走 GameManager.rng：预览只验画面）
		_boss.global_position = BOSS_HOME
		var dest: Vector2 = DEMO_DEST[_demo_step % DEMO_DEST.size()]
		_boss._begin_blink_telegraph(dest, GameBalance.BOSS_TURRET_SHIFT_WINDUP,
			_boss._fx_color, BlinkRift.RADIUS_BOSS)
		_caption.text = "Boss 档瞬移全流程（起手 %.2fs）：脚下吸积 + 本体收缩 → 落点光柱 → 消失 → 落地爆闪胀回" \
			% GameBalance.BOSS_TURRET_SHIFT_WINDUP

## 三档符环循环：上一次回池后立刻在原点位重新取一只（池化复用，零节点 churn）
func _loop_rifts() -> void:
	for i in range(3):
		var r: BlinkRift = _rifts[i]
		if r == null or not is_instance_valid(r) or not r.is_inside_tree():
			var col: Color = [GameStyle.BAD, GameStyle.POISON, _boss._fx_color][i]
			_rifts[i] = BlinkRift.acquire(_world, RIFT_POS[i], RIFT_DUR[i], col, RIFT_RAD[i])