extends Node

## 精英攻击方式判据（2026-10-22 用户口径：「第五关、第十五关的精英怪要再优化攻击方式，
## 现在这个精英怪感觉就除了血厚一点，其他什么难度都没有，要增加一些新的攻击方式，提高难度」）。
## 运行: $G --headless --path . res://tests/EliteAttackCheck.tscn
##
## 判据分两层：
##   ① 场景配置层（直 instance 三只精英 .tscn）：常驻招式字段真的配上了、数值与 BalanceWave 同源；
##   ② 行为层（真 Main + 真 WaveSpawner，同 EliteOvertimeCheck 范式）：W5 铁甲魔傀进场即带
##      震地+落石、落石预警圈数量与半径同源、震地真的扣血、变异后升格多段；
##      W15 赤雷兽雷环真的出弹、冲刺伤害倍率升档、变异后链冲与雷环增发；
##      剑煞雷剑域真的铺场、变异后扩域并解锁瞬身回斩。
##   ③ 池化层：杀死后重取同种，新招式字段回滚出厂值（坑13：变异原地改数必须可回滚）。
##
## 为什么行为层必须走真刷怪口：`_elite_ref / _scale_to_wave / activate` 的接线只有生产入口量得到；
## 手塞假节点会漏掉「字段配了但 activate 没初始化计时器」这类断线。
##
## 判据清单：
##   ① 三只精英场景常驻招式字段齐全且与 BalanceWave 常量一致；
##   ② W5 铁甲魔傀：进场 slam_interval/rock_interval 均 >0（不再是白板木桩）；
##   ③ W5 落石起手：预警圈数 == rock_count、每圈半径 == rock_radius（画多大判多大）；
##   ④ W5 震地：玩家站圈内 ⇒ 结算扣血；站圈外 ⇒ 不扣；
##   ⑤ W5 变异：slam_hits == MUT_GOLEM_SLAM_HITS、rock_count 增点、震地半径升档；
##   ⑥ W15 赤雷兽：charge_damage_mul 升档 1.3、雷环出弹数 == ring_bolt_count；
##   ⑦ W15 变异：chain_charges == MUT_CHILEI_CHAIN_CHARGES、ring_bolt_count 增发；
##   ⑧ 剑煞：雷剑域铺场（PoisonPool 落点 == 锁定点、半径同源）、变异扩域 + 解锁瞬身回斩；
##   ⑨ 池化复用：变异个体回池后重取，新招式字段回到出厂值（不回滚就会永久强化）。

var _c := TestCheck.new()
var _main: Node = null
var _spawner: WaveSpawner = null

func _ready() -> void:
	call_deferred("_dispatch")

func _dispatch() -> void:
	await _setup_run()
	await _run()
	get_tree().quit(0 if _c.report("ELITE_ATTACK_RESULT") else 1)

func _setup_run() -> void:
	Engine.time_scale = 1.0
	get_tree().root.size = Vector2i(960, 540)
	_main = load("res://scenes/main/Main.tscn").instantiate()
	get_tree().root.add_child(_main)
	await get_tree().process_frame
	GameManager.cultivator_id = "fuzhen"
	GameManager.start_run("qingyun_sword")
	get_tree().paused = false
	await get_tree().process_frame
	_spawner = GameManager.wave_spawner as WaveSpawner
	var waited := 0
	while _spawner != null and int(_spawner.phase) != int(WaveSpawner.Phase.FIGHT) and waited < 240:
		await get_tree().process_frame
		waited += 1
	_c.check(_spawner != null and int(_spawner.phase) == int(WaveSpawner.Phase.FIGHT),
		"真 spawner 已进入 FIGHT（等了 %d 帧）" % waited)

func _run() -> void:
	if _spawner == null:
		_c.check(false, "前置缺失：spawner 没到位，后续项无法比")
		return

	# ---- ① 场景配置层：三只精英的常驻招式字段与 BalanceWave 同源 ----
	_check_scene_config()

	# ---- ② W5 铁甲魔傀：进场即带双招式 ----
	_begin_wave(5)
	var golem := await _spawn_gatekeeper()
	_c.check(golem != null and is_instance_valid(golem), "② 第 5 波铁甲魔傀已从真实刷怪口落地")
	if golem == null:
		return
	_c.check(golem.slam_interval > 0.0, "② 铁甲魔傀常驻震地（slam_interval=%.2f > 0，不再是 60%% 血线才解锁）" % golem.slam_interval)
	_c.check(golem.rock_interval > 0.0, "② 铁甲魔傀常驻落石（rock_interval=%.2f > 0，第二招式）" % golem.rock_interval)
	_c.check(golem.slam_hits == 1, "② 未变异时震地为单段（slam_hits=%d）" % golem.slam_hits)

	# ---- ③ 落石起手：预警圈数量与半径同源 ----
	# 把玩家固定在精英附近，清掉其它干扰怪，直接触发落石。
	# 精英血量抬到极高：判据只测招式结算，别让玩家武器在测量途中把它打死（否则 dying 短路）。
	golem.max_hp = 999999.0
	golem.current_hp = 999999.0
	_park_player_near(golem.global_position, 160.0)
	golem._rock_timer = 999.0   # 锁住自动计时，只测本次手动起手（否则结算后下一帧又自动重放）
	golem._start_rock_barrage(GameManager.player)
	await get_tree().process_frame
	_c.check(golem._rock_rings.size() == golem.rock_count,
		"③ 落石预警圈数 == rock_count（期望 %d，实得 %d）" % [golem.rock_count, golem._rock_rings.size()])
	var radius_ok := true
	for ring in golem._rock_rings:
		if ring == null or not is_instance_valid(ring) or absf(ring.radius - golem.rock_radius) > 0.01:
			radius_ok = false
			break
	_c.check(radius_ok, "③ 每个落石预警圈半径 == rock_radius（画多大判多大，%.1f）" % golem.rock_radius)
	# 结算：把玩家钉在首点中心 ⇒ 必吃一发（直接调结算，不依赖物理帧时序）
	var hp_before_rock := _player_hp()
	var first_point: Vector2 = golem._rock_points[0]
	GameManager.player.global_position = first_point
	golem._resolve_rock_barrage(GameManager.player)
	_c.check(_player_hp() < hp_before_rock,
		"③ 落石结算命中圈内玩家（HP %.1f → %.1f）" % [hp_before_rock, _player_hp()])
	_c.check(golem._rock_rings.is_empty(), "③ 落石结算后预警圈全部回收（实得 %d 个残留）" % golem._rock_rings.size())

	# ---- ④ 震地：圈内扣血 / 圈外不扣 ----
	await _wait_secs(0.65)   # 等玩家受击无敌帧过去
	var hp_before_slam := _player_hp()
	GameManager.player.global_position = golem.global_position + Vector2(golem.slam_radius * 0.5, 0.0)
	golem._resolve_elite_slam(GameManager.player)
	_c.check(_player_hp() < hp_before_slam,
		"④ 震地命中圈内玩家（HP %.1f → %.1f）" % [hp_before_slam, _player_hp()])
	await _wait_secs(0.65)
	var hp_before_out := _player_hp()
	GameManager.player.global_position = golem.global_position + Vector2(golem.slam_radius * 1.5, 0.0)
	golem._resolve_elite_slam(GameManager.player)
	_c.check(is_equal_approx(_player_hp(), hp_before_out),
		"④ 震地圈外不扣血（HP %.1f → %.1f；玩家距精英 %.1f，震地半径 %.1f）" % [
			hp_before_out, _player_hp(),
			GameManager.player.global_position.distance_to(golem.global_position), golem.slam_radius])

	# ---- ⑤ 变异：多段震 + 落石增点 ----
	golem.current_hp = golem.max_hp * 0.5
	golem.take_damage(1.0, Vector2.ZERO, false)
	await get_tree().process_frame
	_c.check(golem._mutated, "⑤ 过 60%% 血线触发精英狂暴（_mutated=true）")
	_c.check(golem.slam_hits == GameBalance.MUT_GOLEM_SLAM_HITS,
		"⑤ 变异震地升格多段（slam_hits=%d，期望 %d）" % [golem.slam_hits, GameBalance.MUT_GOLEM_SLAM_HITS])
	_c.check(golem.rock_count == GameBalance.MUT_GOLEM_ROCK_COUNT,
		"⑤ 变异落石增点（rock_count=%d，期望 %d）" % [golem.rock_count, GameBalance.MUT_GOLEM_ROCK_COUNT])
	_c.check(is_equal_approx(golem.slam_radius, GameBalance.MUT_GOLEM_SLAM_RADIUS),
		"⑤ 变异震地半径升档（%.1f，期望 %.1f）" % [golem.slam_radius, GameBalance.MUT_GOLEM_SLAM_RADIUS])
	# 多段余波：首段结算后剩余段数 = slam_hits - 1
	golem._resolve_elite_slam(GameManager.player)
	_c.check(golem._slam_echo_left == GameBalance.MUT_GOLEM_SLAM_HITS - 1,
		"⑤ 首段结算后余波段数 == slam_hits-1（实得 %d）" % golem._slam_echo_left)
	# 收掉这只（回池路径走 _die → 塌缩；测试只关心字段回滚，见 ⑨）
	golem.take_damage(9999999.0, Vector2.ZERO, false)

	# ---- ⑥ W15 赤雷兽：冲刺伤害升档 + 雷环出弹 ----
	_begin_wave(15)
	var chilei := await _spawn_gatekeeper()
	_c.check(chilei != null and is_instance_valid(chilei), "⑥ 第 15 波赤雷兽已从真实刷怪口落地")
	if chilei == null:
		return
	_c.near(chilei.charge_damage_mul, 1.3, 0.001,
		"⑥ 冲刺伤害倍率升档（1.0 → 1.3，不再是普通妖狼同档）")
	_c.check(chilei.ring_bolt_interval > 0.0,
		"⑥ 赤雷兽常驻雷环（ring_bolt_interval=%.2f > 0）" % chilei.ring_bolt_interval)
	_park_player_near(chilei.global_position, 300.0)
	var bolts_before := EnemyBolt.active_count
	chilei._fire_ring_bolts()
	await get_tree().process_frame
	var spawned := EnemyBolt.active_count - bolts_before
	_c.check(spawned == chilei.ring_bolt_count,
		"⑥ 雷环出弹数 == ring_bolt_count（期望 %d，实得 %d）" % [chilei.ring_bolt_count, spawned])

	# ---- ⑦ 变异：链冲 + 雷环增发 ----
	chilei.current_hp = chilei.max_hp * 0.5
	chilei.take_damage(1.0, Vector2.ZERO, false)
	await get_tree().process_frame
	_c.check(chilei._mutated, "⑦ 赤雷兽过血线触发狂暴")
	_c.check(chilei.chain_charges == GameBalance.MUT_CHILEI_CHAIN_CHARGES,
		"⑦ 变异解锁三连冲（chain_charges=%d，期望 %d）" % [chilei.chain_charges, GameBalance.MUT_CHILEI_CHAIN_CHARGES])
	_c.check(chilei.ring_bolt_count == GameBalance.MUT_CHILEI_RING_COUNT,
		"⑦ 变异雷环增发（ring_bolt_count=%d，期望 %d）" % [chilei.ring_bolt_count, GameBalance.MUT_CHILEI_RING_COUNT])
	_c.check(chilei.charge_side_bolts > 0, "⑦ 变异保留冲刺侧翼洒弹（charge_side_bolts=%d）" % chilei.charge_side_bolts)
	chilei.take_damage(9999999.0, Vector2.ZERO, false)

	# ---- ⑧ 剑煞：雷剑域铺场 / 变异扩域 + 瞬身回斩 ----
	var jiansha := _spawn_standalone("res://scenes/entities/JianshaEliteEnemy.tscn", Vector2(0, 0))
	await get_tree().process_frame
	_c.check(jiansha != null and is_instance_valid(jiansha), "⑧ 剑煞邪修场景可实例化")
	if jiansha != null:
		_c.check(jiansha.field_interval > 0.0,
			"⑧ 剑煞常驻雷剑域（field_interval=%.2f > 0）" % jiansha.field_interval)
		_c.check(jiansha.blink_strike_interval == 0.0,
			"⑧ 未变异不启用瞬身回斩（blink_strike_interval=%.2f）" % jiansha.blink_strike_interval)
		# 铺域：锁定点 = 玩家脚下，PoisonPool 落点与半径同源
		var target := GameManager.player.global_position
		jiansha._field_target = target
		jiansha._start_field_cast()
		jiansha._field_windup_t = 0.001
		var pools_before := PoisonPool.active_count
		await _wait_secs(0.12)
		_c.check(PoisonPool.active_count == pools_before + 1,
			"⑧ 雷剑域落场（PoisonPool 在场数 %d → %d）" % [pools_before, PoisonPool.active_count])
		var field_pool: PoisonPool = null
		for p in get_tree().get_nodes_in_group("enemies"):
			pass
		# 直接扫 PoisonPool 池宿主下的活动个体，按落点匹配
		for node in get_tree().root.find_children("*", "PoisonPool", true, false):
			var pp := node as PoisonPool
			if pp != null and pp.visible and pp.global_position.distance_to(target) < 1.0:
				field_pool = pp
				break
		_c.check(field_pool != null, "⑧ 雷剑域落点 == 锁定点（玩家脚下）")
		if field_pool != null:
			_c.near(field_pool.radius, jiansha.field_radius, 1.0,
				"⑧ 领域判定半径 == field_radius（画多大判多大）")
			_c.near(field_pool.damage, maxf(1.0, jiansha.contact_damage * jiansha.field_dmg_mult), 0.01,
				"⑧ 领域每跳伤害 = 接触伤害 × field_dmg_mult（同尺）")
		# 变异：扩域 + 解锁瞬身
		var r_before := jiansha.field_radius
		jiansha.current_hp = jiansha.max_hp * 0.5
		jiansha.take_damage(1.0, Vector2.ZERO, false)
		await get_tree().process_frame
		_c.check(jiansha._mutated, "⑧ 剑煞过血线触发狂暴")
		_c.near(jiansha.field_radius, r_before * GameBalance.MUT_JIANSHA_FIELD_RADIUS_MULT, 0.01,
			"⑧ 变异雷剑域扩域（%.1f → %.1f）" % [r_before, jiansha.field_radius])
		_c.check(jiansha.blink_strike_interval > 0.0,
			"⑧ 变异解锁瞬身回斩（blink_strike_interval=%.2f）" % jiansha.blink_strike_interval)
		# 瞬身回斩：真的会位移 + 出剑气。先把双方钉到场心：
		# 瞬身落点会被界碑 clamp，贴着地图边缘测会量到「被夹短」的位移而误判。
		GameManager.player.global_position = Vector2.ZERO
		jiansha.global_position = Vector2.ZERO
		var pos_before := jiansha.global_position
		var bolts_before2 := EnemyBolt.active_count
		jiansha._blink_strike(GameManager.player)
		await get_tree().process_frame
		_c.check(jiansha.global_position.distance_to(pos_before) > 100.0,
			"⑧ 瞬身回斩产生位移（%.0fpx）" % jiansha.global_position.distance_to(pos_before))
		_c.check(EnemyBolt.active_count - bolts_before2 >= jiansha.blink_strike_bolts,
			"⑧ 瞬身回斩出剑气（+%d 发，期望 ≥%d）" % [EnemyBolt.active_count - bolts_before2, jiansha.blink_strike_bolts])
		jiansha.queue_free()

	# ---- ⑨ 池化复用：变异字段回滚出厂值 ----
	var fresh := EnemyBase.acquire_or_new(load("res://scenes/entities/GolemEnemy.tscn"))
	_c.check(fresh != null, "⑨ 可重取铁甲魔傀个体")
	if fresh != null:
		fresh.reset_for_reuse()
		_c.check(fresh.slam_hits == 1,
			"⑨ 池化复用回滚 slam_hits（实得 %d，必须是出厂 1）" % fresh.slam_hits)
		_c.check(is_equal_approx(fresh.slam_radius, GameBalance.GOLEM_SLAM_RADIUS),
			"⑨ 池化复用回滚 slam_radius（实得 %.1f，出厂 %.1f）" % [fresh.slam_radius, GameBalance.GOLEM_SLAM_RADIUS])
		_c.check(fresh.rock_count == GameBalance.GOLEM_ROCK_COUNT,
			"⑨ 池化复用回滚 rock_count（实得 %d，出厂 %d）" % [fresh.rock_count, GameBalance.GOLEM_ROCK_COUNT])
		fresh.queue_free()

	_main.queue_free()
	await get_tree().process_frame

# ---------------- 场景配置层判据 ----------------

func _check_scene_config() -> void:
	var golem_scene: PackedScene = load("res://scenes/entities/GolemEnemy.tscn")
	var chilei_scene: PackedScene = load("res://scenes/entities/ChileiEliteEnemy.tscn")
	var jiansha_scene: PackedScene = load("res://scenes/entities/JianshaEliteEnemy.tscn")
	var g := golem_scene.instantiate() as EnemyBase
	var c := chilei_scene.instantiate() as EnemyBase
	var j := jiansha_scene.instantiate() as EnemyBase
	_c.near(g.slam_interval, GameBalance.GOLEM_SLAM_INTERVAL, 0.001, "① 铁甲魔傀场景 slam_interval 与 BalanceWave 同源")
	_c.near(g.slam_radius, GameBalance.GOLEM_SLAM_RADIUS, 0.001, "① 铁甲魔傀场景 slam_radius 与 BalanceWave 同源")
	_c.near(g.rock_interval, GameBalance.GOLEM_ROCK_INTERVAL, 0.001, "① 铁甲魔傀场景 rock_interval 与 BalanceWave 同源")
	_c.equals(g.rock_count, GameBalance.GOLEM_ROCK_COUNT, "① 铁甲魔傀场景 rock_count 与 BalanceWave 同源")
	_c.near(c.charge_damage_mul, 1.3, 0.001, "① 赤雷兽冲刺伤害倍率 1.3（高于普通妖狼 1.0 档）")
	_c.near(c.ring_bolt_interval, GameBalance.CHILEI_RING_INTERVAL, 0.001, "① 赤雷兽场景 ring_bolt_interval 与 BalanceWave 同源")
	_c.equals(c.ring_bolt_count, GameBalance.CHILEI_RING_COUNT, "① 赤雷兽场景 ring_bolt_count 与 BalanceWave 同源")
	_c.near(j.field_interval, GameBalance.JIANSHA_FIELD_INTERVAL, 0.001, "① 剑煞场景 field_interval 与 BalanceWave 同源")
	_c.near(j.field_radius, GameBalance.JIANSHA_FIELD_RADIUS, 0.001, "① 剑煞场景 field_radius 与 BalanceWave 同源")
	g.free()
	c.free()
	j.free()

# ---------------- 测试辅助 ----------------

## 开一波：把常规刷怪预算视为已刷尽（隔离关底），清空现场。
func _begin_wave(n: int) -> void:
	GameManager.is_game_over = false
	get_tree().paused = false
	GameManager.harvest = 0.0
	GameManager.experience = 0
	GameManager.experience_to_next = 1000000
	_spawner.phase = WaveSpawner.Phase.FIGHT
	_spawner.start_wave(n)
	_spawner._budget_used = _spawner._budget_total
	_clear_field()

func _spawn_gatekeeper() -> EnemyBase:
	_spawner.elite_spawned = true
	_spawner._spawn_elite(GameManager.player)
	await _wait_until(func(): return _spawner._elite_ref != null, 5.0)
	return _spawner._elite_ref

func _spawn_standalone(path: String, pos: Vector2) -> EnemyBase:
	var scene: PackedScene = load(path)
	if scene == null:
		return null
	var e := scene.instantiate() as EnemyBase
	e.global_position = pos
	e.add_to_group("enemies")
	get_tree().root.add_child(e)
	e.activate()
	return e

## 把玩家挪到精英旁固定距离（不触发追击位移干扰判据）
func _park_player_near(center: Vector2, dist: float) -> void:
	var p := GameManager.player
	if p == null or not is_instance_valid(p):
		return
	p.global_position = center + Vector2(dist, 0.0)
	p.velocity = Vector2.ZERO

func _player_hp() -> float:
	var p := GameManager.player
	if p == null or not is_instance_valid(p):
		return 0.0
	return p.current_health

func _clear_field() -> void:
	for group_name in ["enemies", "gems", "chests", "turrets"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if node is Node and node.get_parent() != null:
				node.get_parent().remove_child(node)
				node.queue_free()
	GameManager.enemy_count = 0

func _wait_secs(wall_secs: float) -> void:
	await get_tree().create_timer(wall_secs).timeout

func _wait_until(cond: Callable, timeout_secs: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_secs * 1000.0)
	while not bool(cond.call()):
		if Time.get_ticks_msec() >= deadline:
			return false
		await get_tree().create_timer(0.03).timeout
	return true
