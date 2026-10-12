extends Node

## 2026-10-12 新敌机制判据（仿土豆兄弟 Elite Mutation / Healer / Looter 落地）。钉死六件事：
##   ① 灵医治疗脉冲：范围内受伤同伴回血、不奶自己、不溢出上限
##   ② 金蟾恒背离玩家逃窜（速度矢量与指向玩家的方向相反）
##   ③ 金蟾击杀爆金币（stone_reward 入 GameManager.spirit_stones）
##   ④ 精英变异只触发一次：铁甲巨怪获得震地、烈雷兽获得冲刺侧射、剑客亡灵剑气加密
##   ⑤ 铁甲巨怪变异震地：圈内玩家掉血、圈外不掉血
##   ⑥ 未登记敌种（Boss）走自己的二阶段，不被变异钩子截胡
## 运行: godot --headless --path . res://tests/EnemyNewMechanicsCheck.tscn
## 只摆一个裸 world + 真 Player + 按需单只妖物，不跑波次（别的怪会污染读数）。

var _c := TestCheck.new()
var _world: Node2D
var _player: Node2D

func _ready() -> void:
	call_deferred("_run")

func _spawn_enemy(scene_path: String, pos: Vector2) -> EnemyBase:
	var scene: PackedScene = load(scene_path)
	var e := scene.instantiate() as EnemyBase
	e.global_position = pos
	e.add_to_group("enemies")
	_world.add_child(e)
	return e

func _run() -> void:
	# 判据只关心游戏时间内阶段推进：关掉顿帧（不落盘），加速仿真
	SettingsManager.set_val(&"display", &"hit_stop", false, false)
	Engine.time_scale = 8.0

	_world = Node2D.new()
	_world.name = "EnemyNewMechanicsWorld"
	get_tree().root.add_child(_world)
	await get_tree().process_frame

	var player_scene: PackedScene = load("res://scenes/entities/Player.tscn")
	_player = player_scene.instantiate() as Node2D
	_world.add_child(_player)
	_player.global_position = Vector2.ZERO
	_player.max_health = 99999.0
	_player.current_health = 99999.0
	await get_tree().process_frame

	_c.check(GameManager.player == _player, "前置：EnemyBase 读到的玩家就是这一只")
	_c.check(not GameManager.is_game_over, "前置：对局未结束（否则怪不动）")

	await _case_healer()
	await _case_looter_flee()
	await _case_looter_stones()
	await _case_mutation_once()
	await _case_golem_slam()
	_case_boss_not_mutated()

	print("ENEMY_NEW_MECHANICS 判据跑完")
	Engine.time_scale = 1.0
	if _c.report("ENEMY_NEW_MECHANICS_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

## ① 灵医：治疗脉冲奶范围内同伴，不奶自己、不溢出上限
## 注意：坐标必须落在场内（±MAP_HALF_EXTENT），超出会被敌人移动收口夹回边界
func _case_healer() -> void:
	var lingyi := _spawn_enemy("res://scenes/entities/LingYiEnemy.tscn", Vector2(200, 0))
	var slime := _spawn_enemy("res://scenes/entities/SlimeEnemy.tscn", Vector2(300, 0))  # 100px，在 240 治疗半径内
	var far_slime := _spawn_enemy("res://scenes/entities/SlimeEnemy.tscn", Vector2(200, -400))  # 400px，圈外
	await get_tree().process_frame
	lingyi.heal_amount = 10.0
	slime.current_hp = slime.max_hp - 30.0
	far_slime.current_hp = far_slime.max_hp - 30.0
	var lingyi_hp := lingyi.current_hp
	var slime_hp := slime.current_hp
	var far_hp := far_slime.current_hp

	lingyi._pulse_heal()
	_c.near(slime.current_hp, slime_hp + 10.0, 0.01, "灵医一跳奶圈内同伴 10 点")
	_c.near(lingyi.current_hp, lingyi_hp, 0.01, "灵医不奶自己")
	_c.near(far_slime.current_hp, far_hp, 0.01, "圈外同伴吃不到治疗")

	slime.current_hp = slime.max_hp - 4.0
	lingyi._pulse_heal()
	_c.near(slime.current_hp, slime.max_hp, 0.01, "治疗不溢出气血上限")

	# 满血同伴不触发演出（healed_any=false 不放绿圈）：只验不报错不崩
	var healthy := _spawn_enemy("res://scenes/entities/SlimeEnemy.tscn", Vector2(250, 0))
	await get_tree().process_frame
	lingyi._pulse_heal()
	_c.check(healthy.current_hp == healthy.max_hp, "满血同伴不受影响")

	for e in [lingyi, slime, far_slime, healthy]:
		e.queue_free()
	await get_tree().process_frame

## ② 金蟾：速度矢量恒背离玩家
func _case_looter_flee() -> void:
	var jinchan := _spawn_enemy("res://scenes/entities/JinChanEnemy.tscn", Vector2(150, 0))
	await get_tree().process_frame
	_c.check(jinchan.always_flee, "前置：金蟾配了 always_flee")
	# 给吸附插值 0.5s 爬到满速
	var t := 0.0
	while t < 0.5:
		await get_tree().physics_frame
		t += 1.0 / 60.0 * 8.0
	var to_player: Vector2 = (_player.global_position - jinchan.global_position).normalized()
	_c.check(jinchan.velocity.dot(to_player) < 0.0, "金蟾速度背离玩家（点积 %.2f < 0）" % jinchan.velocity.dot(to_player))
	_c.check(jinchan.velocity.length() > 50.0, "金蟾真的在跑（不是站着不动）")
	jinchan.queue_free()
	await get_tree().process_frame

## ③ 金蟾：击杀爆金币进 GameManager.spirit_stones
func _case_looter_stones() -> void:
	var jinchan := _spawn_enemy("res://scenes/entities/JinChanEnemy.tscn", Vector2(-800, -800))
	await get_tree().process_frame
	jinchan.stone_reward = 25
	var before := GameManager.spirit_stones
	jinchan.take_damage(99999.0, Vector2.ZERO)
	await get_tree().process_frame
	_c.equals(GameManager.spirit_stones - before, 25, "击杀金蟾 +25 金币")

## ④ 精英变异：只触发一次，三种精英各拿到自己的新行为
func _case_mutation_once() -> void:
	var golem := _spawn_enemy("res://scenes/entities/GolemEnemy.tscn", Vector2(5000, 5000))
	var chilei := _spawn_enemy("res://scenes/entities/ChileiEliteEnemy.tscn", Vector2(5200, 5000))
	var jiansha := _spawn_enemy("res://scenes/entities/JianshaEliteEnemy.tscn", Vector2(5400, 5000))
	await get_tree().process_frame
	_c.check(golem.slam_interval == 0.0, "前置：铁甲巨怪变异前没有震地")
	_c.check(chilei.charge_side_bolts == 0, "前置：烈雷兽变异前没有侧射")
	_c.check(jiansha.bolt_count == 3, "前置：剑客亡灵变异前三连剑气")

	# 血线 60% 以上挨刀不触发
	golem.take_damage(golem.max_hp * 0.2, Vector2.ZERO)
	_c.check(not golem._mutated, "血线 60% 以上不触发变异（80% → 79.9%）")

	# 压到 60% 以下触发
	golem.current_hp = golem.max_hp * 0.59
	chilei.current_hp = chilei.max_hp * 0.59
	jiansha.current_hp = jiansha.max_hp * 0.59
	golem.take_damage(1.0, Vector2.ZERO)
	chilei.take_damage(1.0, Vector2.ZERO)
	jiansha.take_damage(1.0, Vector2.ZERO)
	_c.check(golem._mutated, "铁甲巨怪过血线触发变异")
	_c.check(golem.slam_interval > 0.0, "铁甲巨怪变异获得震地")
	_c.check(chilei._mutated and chilei.charge_side_bolts > 0, "烈雷兽变异获得冲刺侧射")
	_c.check(jiansha._mutated and jiansha.bolt_count == GameBalance.MUT_JIANSHA_BOLT_COUNT, "剑客亡灵变异剑气加密")
	_c.check(jiansha.preferred_range < 200.0, "剑客亡灵变异压近身（%.0f）" % jiansha.preferred_range)

	# 再挨刀不重复触发（移速只乘一次）
	var spd := golem.move_speed
	golem.take_damage(1.0, Vector2.ZERO)
	_c.check(golem._mutated and golem.move_speed == spd, "变异只触发一次（移速不重复翻倍）")

	for e in [golem, chilei, jiansha]:
		e.queue_free()
	await get_tree().process_frame

## ⑤ 铁甲巨怪变异震地：圈内玩家掉血、圈外不掉血
## 等待期间每帧把玩家钉回目标位：巨怪会追人，不钉的话它自己走进判定圈
func _case_golem_slam() -> void:
	var golem := _spawn_enemy("res://scenes/entities/GolemEnemy.tscn", Vector2(100, 100))
	await get_tree().process_frame
	golem.current_hp = golem.max_hp * 0.5
	golem.take_damage(1.0, Vector2.ZERO)
	_c.check(golem.slam_interval > 0.0, "前置：变异已给铁甲巨怪震地")

	# 玩家贴身（圈内），跳过冷却直接起手
	_player.global_position = golem.global_position + Vector2(60, 0)
	golem._elite_slam_timer = 0.0
	var hp_before: float = _player.current_health
	var t := 0.0
	while t < 1.5:  # 起手窗口 + 预警 0.8s
		_player.global_position = golem.global_position + Vector2(60, 0)
		await get_tree().physics_frame
		t += 1.0 / 60.0 * 8.0
	_c.check(_player.current_health < hp_before, "震地圈内玩家掉血（%.0f → %.0f）" % [hp_before, _player.current_health])

	# 玩家撤出圈外再吃一锤：不掉血
	_player.current_health = 99999.0
	hp_before = _player.current_health
	golem._elite_slam_timer = 0.0
	t = 0.0
	while t < 1.5:
		_player.global_position = golem.global_position + Vector2(golem.slam_radius + 120.0, 0)
		await get_tree().physics_frame
		t += 1.0 / 60.0 * 8.0
	_c.near(_player.current_health, hp_before, 0.01, "震地圈外玩家不掉血")

	_player.global_position = Vector2.ZERO
	golem.queue_free()
	await get_tree().process_frame

## ⑥ Boss 不被精英变异钩子截胡（它有自己的二阶段）
func _case_boss_not_mutated() -> void:
	var boss_scene: PackedScene = load("res://scenes/entities/BossEnemy.tscn")
	var boss := boss_scene.instantiate() as BossEnemy
	boss.global_position = Vector2(9000, 9000)
	boss.add_to_group("enemies")
	_world.add_child(boss)
	await get_tree().process_frame
	boss.current_hp = boss.max_hp * 0.5
	boss.take_damage(1.0, Vector2.ZERO)
	_c.check(not boss._mutated, "Boss 过 60% 血线不走精英变异（自己的二阶段照旧）")
	boss.queue_free()
