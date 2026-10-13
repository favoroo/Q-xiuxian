extends Node

## 击杀即原地塌缩判据（2026-10-13，用户口径：「如果这一下已经击杀他了，就不要有那个击退动画，直接击杀掉」）。
##
## 钉住三件事：
##   ① 小怪致命一刀：尸体在击杀点原地塌缩，整段消散期最大漂移 < 0.5px，且击杀计数 +1（证明判据非空）
##   ② 非致命一刀照常被推开（防过度修复：不许把击退整个砍掉）
##   ③ 精英致命暴击：同样原地塌缩
## 另钉：尸体不带受击微反冲偏移（_die 就地归位 anim_sprite.position），塌缩动画走完按时释放（无泄漏）。
##
## 为什么量「位置漂移」而不是「速度」：致命一刀的位移从来不来自物理 —— _die() 与致命一刀同帧
## set_physics_process(false)，活体一帧都没被推动过。玩家看到的「边被推飞边消失」全部来自
## _die() 里那条斩杀击飞 Tween（旧 KILL_LAUNCH_*，塌缩期最多推出 42px）。所以判据逐帧量尸体的
## global_position，只有这条路能抓到旧写法。
##
## 运行: godot --headless --path . res://tests/KillKnockbackCheck.tscn
## 退出码 0 且末行 KILL_KNOCKBACK_RESULT: ALL PASS
## 反例（判据的牙齿，改动后跑本场景必须报红）：
##   ① 恢复 _die() 的斩杀击飞 Tween ⇒ ①③ 报红（尸体在 5 帧采样窗内已漂出 ~38px）
##   ② 把致命与非致命击退一起砍掉 ⇒ ② 报红
##   ③ 删掉 _die() 里对 anim_sprite.position 的归位 ⇒ 尸体微反冲断言报红
##
## 摆位口径照 EnemyNewMechanicsCheck：裸 world + 真 Player，不跑波次（别的怪会污染读数）。
## move_speed 归零剔除 AI 位移，contact_damage 归零避免反震/接触结算串进来。

const EPS := 0.5                        ## 漂移容差（px）：旧写法同窗内漂 ~38px，区分度足够
const SPAWN_AT := Vector2(60.0, -40.0)  ## 场内（±MAP_HALF_EXTENT）且远离玩家，避免边界收口夹回
const PLAYER_AT := Vector2(200.0, 200.0)

var _c := TestCheck.new()
var _world: Node2D

func _ready() -> void:
	call_deferred("_run")

func _spawn_enemy(scene_path: String, at: Vector2) -> EnemyBase:
	var scene: PackedScene = load(scene_path)
	var e := scene.instantiate() as EnemyBase
	e.global_position = at
	e.add_to_group("enemies")
	_world.add_child(e)
	e.move_speed = 0.0        ## 不许自己走位污染读数（击退位移仍走 _resolve_velocity 硬直滑行段）
	e.contact_damage = 0.0    ## 接触伤害/反震不参与本判据
	return e

## 逐帧采样尸体的最大漂移；尸体被释放即提前结束（不越界访问已 free 的实例）
func _max_drift(e: EnemyBase, from: Vector2, frames: int) -> float:
	var max_drift := 0.0
	for i in range(frames):
		await get_tree().physics_frame
		if not is_instance_valid(e):
			break
		max_drift = maxf(max_drift, e.global_position.distance_to(from))
	return max_drift

func _run() -> void:
	# 判据只关心位移：关掉顿帧（不落盘）、时间缩放钉 1.0（顿帧会拖慢采样窗内的补间推进）
	SettingsManager.set_val(&"display", &"hit_stop", false, false)
	Engine.time_scale = 1.0
	GameManager.reset_run()

	_world = Node2D.new()
	_world.name = "KillKnockbackWorld"
	get_tree().root.add_child(_world)
	await get_tree().process_frame

	var player: Node2D = load("res://scenes/entities/Player.tscn").instantiate() as Node2D
	_world.add_child(player)
	player.global_position = PLAYER_AT
	player.max_health = 99999.0
	player.current_health = 99999.0
	await get_tree().process_frame

	_c.check(GameManager.player == player, "前置：EnemyBase 读到的玩家就是这一只")
	_c.check(not GameManager.is_game_over, "前置：对局未结束（否则怪不动）")
	_c.near(GameManager.knockback_mult, 1.0, 0.0001, "前置：震退倍率归基准（读数不被羁绊/法宝放大）")

	await _case_mob_lethal()
	await _case_nonlethal_still_knocked()
	await _case_elite_crit_lethal()

	print("KILL_KNOCKBACK 判据跑完")
	Engine.time_scale = 1.0
	if _c.report("KILL_KNOCKBACK_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

## ① 小怪致命一刀：尸体原地塌缩，整段消散期零位移，且击杀流真跑完
func _case_mob_lethal() -> void:
	var e := _spawn_enemy("res://scenes/entities/SlimeEnemy.tscn", SPAWN_AT)
	await get_tree().process_frame
	var kills_before: int = GameManager.kills
	e.current_hp = e.max_hp * 0.5
	var pos_before: Vector2 = e.global_position
	# 400px/s 击退 = 重武器量级（折算后撞上限，旧写法尸体会推出满额 42px）
	e.take_damage(e.max_hp, Vector2(400.0, 0.0))

	_c.check(e.dying, "致命一刀当场进死亡态（判据非空：真打死了）")
	_c.equals(GameManager.kills - kills_before, 1, "击杀计数 +1（死亡流真跑完）")
	_c.check(e.anim_sprite.position == Vector2.ZERO, "尸体不带受击微反冲偏移（_die 就地归位）")

	var drift := await _max_drift(e, pos_before, 20)
	_c.check(drift < EPS, "小怪致命一刀：尸体原地塌缩（最大漂移 %.3f px，上限 %.1f）" % [drift, EPS])

	for i in range(10):
		await get_tree().physics_frame
	_c.check(not is_instance_valid(e), "塌缩动画走完按时释放（无尸体泄漏）")

## ② 非致命一刀：照常被推开（防过度修复）
func _case_nonlethal_still_knocked() -> void:
	var e := _spawn_enemy("res://scenes/entities/SlimeEnemy.tscn", SPAWN_AT)
	await get_tree().process_frame
	e.max_hp = 999999.0
	e.current_hp = 999999.0
	var pos_before: Vector2 = e.global_position
	e.take_damage(1.0, Vector2(400.0, 0.0))
	_c.check(not e.dying, "前置：这一刀没打死（999999 血）")

	for i in range(20):
		await get_tree().physics_frame
	var moved := e.global_position.distance_to(pos_before)
	_c.check(moved > 5.0, "非致命一刀照常被推开（实测位移 %.1f px）" % moved)
	e.queue_free()

## ③ 精英致命暴击：同样原地塌缩（精英另有 kick_camera/分级反馈，不许顺带把尸体推出去）
func _case_elite_crit_lethal() -> void:
	var e := _spawn_enemy("res://scenes/entities/ChileiEliteEnemy.tscn", SPAWN_AT)
	await get_tree().process_frame
	var kills_before: int = GameManager.kills
	e.current_hp = e.max_hp * 0.5
	var pos_before: Vector2 = e.global_position
	e.take_damage(e.max_hp, Vector2(0.0, -400.0), true)

	_c.check(e.dying, "精英致命暴击当场进死亡态")
	_c.equals(GameManager.kills - kills_before, 1, "精英击杀计数 +1")

	var drift := await _max_drift(e, pos_before, 20)
	_c.check(drift < EPS, "精英致命暴击：尸体同样原地塌缩（最大漂移 %.3f px）" % drift)
