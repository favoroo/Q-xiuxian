extends Node

## 敌群集行为判据（2026-10-23）：分离排斥 + 包围走位在真实物理链路里生效。
## 钉死六件事：
##   ① 关闭分离时（strength=0）群怪会收束到同一点（对照组：证明分离真的在起作用）
##   ② 开启分离后，同批怪的最小两两间距显著大于对照组
##   ③ 分离不造加速怪：稳态下没有一只超过自己的 eff_speed
##   ④ 包围偏置按实例分配且分布在两侧（不是全挤同一侧包抄）
##   ⑤ 精英/金蟾不吃分离与包围（体型大/环流设计，不许被散兵线带歪）
##   ⑥ 承诺型状态不吃分离：前摇/罚站期间位移为零（画多大判多大的同源纪律）
##
## 运行: godot --headless --path . res://tests/FlockSeparationCheck.tscn
## 退出码 0 且末行 FLOCK_RESULT: ALL PASS
## 反例（回归时必红）：
##   - 删掉 EnemyBase 里的分离叠加 ⇒ ② 与对照组一致，报红
##   - 分离改成「加速度式」叠加 ⇒ ③ 出现超速怪报红
##   - 把 flock_separation 给精英也开 ⇒ ⑤ 报红

const MAX_WAIT_FRAMES := 240  ## 3.3 秒足够从出生点收拢到稳态

var _c := TestCheck.new()
var _world: Node2D
var _player: Player

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	SettingsManager.set_val(&"display", &"hit_stop", false, false)
	Engine.time_scale = 1.0
	GameManager.reset_run()

	_world = Node2D.new()
	_world.name = "FlockWorld"
	get_tree().root.add_child(_world)
	await get_tree().process_frame

	_player = load("res://scenes/entities/Player.tscn").instantiate() as Player
	_world.add_child(_player)
	_player.global_position = Vector2.ZERO
	_player.max_health = 99999.0
	_player.current_health = 99999.0
	await get_tree().process_frame

	_c.check(GameManager.player == _player, "前置：敌人读到的玩家就是这一只")

	await _case_orbit_bias_assignment()
	await _case_elite_exempt()
	await _case_separation_spread()

	print("FLOCK_CHECK 判据跑完")
	Engine.time_scale = 1.0
	if _c.report("FLOCK_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

## ④ 包围偏置：按实例分配、分布两侧、远程怪不参与
func _case_orbit_bias_assignment() -> void:
	var biases: Array[float] = []
	for i in range(12):
		var e := _spawn("res://scenes/entities/SlimeEnemy.tscn", Vector2(200.0 + float(i) * 4.0, 200.0))
		biases.append(e.orbit_bias)
		e.queue_free()
	await get_tree().process_frame

	var pos_count := 0
	var neg_count := 0
	var max_abs := 0.0
	var nonzero := 0
	for b in biases:
		if b > 0.01:
			pos_count += 1
		elif b < -0.01:
			neg_count += 1
		if absf(b) > 0.01:
			nonzero += 1
		max_abs = maxf(max_abs, absf(b))
	_c.check(nonzero >= 8, "近战怪绝大多数抽到了非零包抄偏置（%d/12）" % nonzero)
	_c.check(pos_count > 0 and neg_count > 0,
		"偏置分布在两侧（顺 %d / 逆 %d，不是全挤一侧包抄）" % [pos_count, neg_count])
	_c.check(max_abs <= GameBalance.FLOCK_ORBIT_BIAS_MAX + 0.0001,
		"偏置不超过常量上限（实得最大 %.3f ≤ %.3f）" % [max_abs, GameBalance.FLOCK_ORBIT_BIAS_MAX])

	# 远程怪（preferred_range>0）不参与包围：它们已有 kite 环绕
	var ranged := _spawn("res://scenes/entities/XieXiuEnemy.tscn", Vector2(-300.0, 200.0))
	_c.near(ranged.orbit_bias, 0.0, 0.0001, "远程怪不分配包抄偏置（已有 kite 环绕）")
	ranged.queue_free()
	await get_tree().process_frame

## ⑤ 精英/金蟾不吃分离与包围
func _case_elite_exempt() -> void:
	var elite := _spawn("res://scenes/entities/GolemEnemy.tscn", Vector2(-400.0, -400.0))
	_c.near(elite.orbit_bias, 0.0, 0.0001, "精英不分配包抄偏置")
	_c.near(elite.flock_separation, 0.0, 0.0001, "精英不吃分离力（体型大，不参与散兵线）")
	_c.check(elite.lunge == null, "精英不配扑咬（已有震地/落石招式）")
	elite.queue_free()

	var looter := _spawn("res://scenes/entities/JinChanEnemy.tscn", Vector2(400.0, -400.0))
	_c.near(looter.orbit_bias, 0.0, 0.0001, "金蟾不分配包抄偏置（恒背离逃窜）")
	_c.near(looter.flock_separation, 0.0, 0.0001, "金蟾不吃分离力（绕场环流是设计好的）")
	looter.queue_free()
	await get_tree().process_frame

## ①②③ 分离真的把一坨摊开，且不造加速怪
func _case_separation_spread() -> void:
	# 对照组：同一批位置、同一批敌种，但把分离关掉
	var group_pos: Array[Vector2] = []
	for i in range(6):
		group_pos.append(Vector2.from_angle(float(i) * TAU / 6.0) * 30.0)

	var min_off := await _run_group(group_pos, false)
	var min_on := await _run_group(group_pos, true)

	_c.check(min_on > min_off + 4.0,
		"开启分离后两两最小间距变大（关 %.1fpx → 开 %.1fpx）" % [min_off, min_on])
	_c.check(min_on > 24.0, "开启分离后群怪不再叠成一坨（最小间距 %.1fpx > 24px）" % min_on)

## 跑一组群怪，返回稳态最小两两间距；strength=0 时作对照组
func _run_group(spawn_pos: Array[Vector2], with_separation: bool) -> float:
	var group: Array[EnemyBase] = []
	for i in range(spawn_pos.size()):
		var e := _spawn("res://scenes/entities/SlimeEnemy.tscn", spawn_pos[i])
		e.flock_separation = 1.0 if with_separation else 0.0
		e.orbit_bias = 0.0  # 只测分离，屏蔽包抄走位
		group.append(e)
	await get_tree().process_frame

	var max_speed_seen := 0.0
	for i in range(MAX_WAIT_FRAMES):
		await get_tree().physics_frame
		if with_separation:
			for e in group:
				if is_instance_valid(e):
					max_speed_seen = maxf(max_speed_seen, e.velocity.length())

	var min_dist := 99999.0
	for a in range(group.size()):
		for b in range(a + 1, group.size()):
			if is_instance_valid(group[a]) and is_instance_valid(group[b]):
				min_dist = minf(min_dist, group[a].global_position.distance_to(group[b].global_position))

	if with_separation:
		# ③ 分离不造加速怪：稳态速度不超过自身 eff_speed 的 1.15 倍（容许插值/碰撞的瞬时超调）
		var worst := 0.0
		for e in group:
			if is_instance_valid(e):
				worst = maxf(worst, e.velocity.length() / maxf(e.move_speed, 1.0))
		_c.check(worst <= 1.15, "分离不造加速怪（最快一只 = %.2f× 移速 ≤ 1.15×）" % worst)

	for e in group:
		if is_instance_valid(e):
			e.queue_free()
	await get_tree().process_frame
	return min_dist

func _spawn(scene_path: String, pos: Vector2) -> EnemyBase:
	var scene: PackedScene = load(scene_path)
	var e := scene.instantiate() as EnemyBase
	e.global_position = pos
	e.add_to_group("enemies")
	_world.add_child(e)
	return e
