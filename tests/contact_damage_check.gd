extends Node

## 接触伤害判据（2026-10-13）：敌人贴身碰撞必须咬到玩家。
##
## 背景：3e8a827（v0.0.24 发布）把 EnemyBase._resolve_contact_damage 里
## 「# 4. 接触伤害判定」整块多缩进 1 个 tab，误嵌进上方 `if charge_locked and not _charge_hit:`
## 分支内 —— 全 16 种敌人里只有雷兽和 ChileiElite 两种会冲刺，其余 14 种 charge_locked 恒 false，
## 整段接触结算被跳过 ⇒ 玩家推着敌人走完全不掉血（回归存活了 3 个版本无人发现，
## 因为此前接触伤害零测试覆盖）。本判据钉住真实物理链路：
## 史莱姆（无冲刺、contact_damage=12）自己 move_and_slide 追撞玩家，玩家必须扣血。
##
## 运行: godot --headless --path . res://tests/ContactDamageCheck.tscn
## 退出码 0 且末行 CONTACT_DAMAGE_CHECK_RESULT: ALL PASS
## 反例（回归时必红）：把接触伤害块缩回 if charge_locked 分支内 ⇒ 玩家全程不掉血报红。

const MAX_WAIT_FRAMES := 300  ## 史莱姆 105px/s，60px 外追到贴脸约 0.6s，300 帧上限留足余量

var _c := TestCheck.new()
var _world: Node2D
var _player: Player

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	# 判据只关心扣血：关掉顿帧（不落盘）、时间缩放钉 1.0（避免帧采样窗被拉长）
	SettingsManager.set_val(&"display", &"hit_stop", false, false)
	Engine.time_scale = 1.0
	GameManager.reset_run()

	_world = Node2D.new()
	_world.name = "ContactDamageWorld"
	get_tree().root.add_child(_world)
	await get_tree().process_frame

	_player = load("res://scenes/entities/Player.tscn").instantiate() as Player
	_world.add_child(_player)
	_player.global_position = Vector2.ZERO
	await get_tree().process_frame

	_c.check(GameManager.player == _player, "前置：敌人读到的玩家就是这一只")
	_c.check(not GameManager.is_game_over, "前置：对局未结束（否则怪不动）")
	_c.check(GameManager.get_effective_dodge() <= 0.0, "前置：新局无闪避（判定无随机性）")

	await _case_slime_contact()

	print("CONTACT_DAMAGE_CHECK 判据跑完")
	Engine.time_scale = 1.0
	if _c.report("CONTACT_DAMAGE_CHECK_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

## 无冲刺小怪（史莱姆）从 60px 外自行追击，贴身后必须咬到玩家且扣血量与公式同源
func _case_slime_contact() -> void:
	var scene: PackedScene = load("res://scenes/entities/SlimeEnemy.tscn")
	var e := scene.instantiate() as EnemyBase
	e.global_position = Vector2(60.0, 0.0)
	e.add_to_group("enemies")
	_world.add_child(e)
	await get_tree().process_frame

	var contact_damage: float = e.contact_damage
	_c.check(contact_damage > 0.0, "前置：史莱姆 contact_damage 配置非零（%.0f）" % contact_damage)

	var hp_before: float = _player.current_health
	var hit_frame := -1
	for i in range(MAX_WAIT_FRAMES):
		await get_tree().physics_frame
		if _player.current_health < hp_before:
			hit_frame = i
			break
		if not is_instance_valid(e) or e.dying:
			break

	_c.check(hit_frame >= 0, "无冲刺小怪贴身碰撞对玩家结算接触伤害（第 %s 帧咬到）" % (str(hit_frame) if hit_frame >= 0 else "？"))
	if hit_frame >= 0:
		var expected: float = GameBalance.incoming_damage(contact_damage, GameManager.get_effective_armor())
		var actual: float = hp_before - _player.current_health
		_c.near(actual, expected, 0.01, "首次咬中扣血量与 GameBalance.incoming_damage 同源")
	_c.check(is_instance_valid(e), "判据结束时敌人仍存活（反震/意外击杀会污染读数）")
