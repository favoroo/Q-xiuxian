extends Node

## 精英关锁关判据（2026-10-22 用户口径：「有精英怪的那种关卡，必须要打完精英怪才能结束，
## 而不是时间倒计时完就结束，比如说第5关、第15关这种」）。
## 运行: $G --headless --path . res://tests/EliteOvertimeCheck.tscn
##
## 为什么必须在真 Main + 真 WaveSpawner 上打：
##   ① 锁关判据读的是 `_elite_ref / elite_spawned / wave_timer / phase` 四个现场量，
##      任何一处接线断了都会回到「倒计时归零就把精英关收了」——只有生产入口量得到；
##   ② 精英必须从真实刷怪口（SpawnIndicator 1.1s 凝聚 → callback → 入组）落地，
##      手塞一个假节点会漏掉「_elite_ref 根本没被赋值」这一类断线；
##   ③ 击杀走真实 take_damage → _die → 塌缩动画 → 回池（dying 置位才算伏诛），
##      只改 phase 或把节点 remove_child 都测不出「死亡后锁关解除」。
##
## 判据清单：
##   ① 精英回合（第 5 波）表走到 0、精英还活着 ⇒ 仍在 FIGHT，且「精英未除」播报只发一次；
##   ② 击杀精英 ⇒ 锁关解除、波次收尾；
##   ③ 精英提前伏诛 ⇒ 不等表走完就进入结算（余时赏路径照旧）；
##   ④ 普通波（第 7 波）表走到 0 照旧收尾，且不发锁关播报（锁关不许外溢）；
##   ⑤ Boss 回合（第 10 波）保持原有锁关口径（本次重构不许把 Boss 一起改坏）；
##   ⑥ 开新波清空上一波 `_elite_ref`（池化复用不复读上一波尸体）。

var _c := TestCheck.new()
var _main: Node = null
var _spawner: WaveSpawner = null
var _lines: Array[String] = []

func _ready() -> void:
	call_deferred("_dispatch")

func _dispatch() -> void:
	await _setup_run()
	await _run()
	get_tree().quit(0 if _c.report("ELITE_OVERTIME_RESULT") else 1)

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
	GameManager.announcement_triggered.connect(
		func(text: String) -> void: _lines.append(text))
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

	# ---- ① 精英回合：表走到 0、精英未死 ⇒ 锁关不收 ----
	_begin_wave(5)
	var elite := await _spawn_gatekeeper()
	_c.check(elite != null and is_instance_valid(elite), "① 第 5 波精英已从真实刷怪口落地")
	_c.check(elite != null and elite.is_elite, "① 落地个体确实是精英（is_elite=true）")
	_c.check(_spawner.wave_left_count() >= 1,
		"① 余妖读数把在场精英算进去（实得 %d）" % _spawner.wave_left_count())
	_spawner.wave_timer = 0.0
	await _wait_secs(1.2)
	_c.check(int(_spawner.phase) == int(WaveSpawner.Phase.FIGHT),
		"① 表走到 0 但精英还活着 ⇒ 仍在 FIGHT（倒计时不能强行收关）")
	_c.check(_count_line("精英未除") == 1,
		"① 锁关播报「精英未除 · 敌潮不退」只发一次（实得 %d 次）" % _count_line("精英未除"))
	_c.check(_spawner.wave_left_count() == 1 and _spawner.wave_total_count() == 1,
		"① 锁关期余妖读数只数关底本身（实得 %d/%d，不许拿冻结预算当分母）" % [
			_spawner.wave_left_count(), _spawner.wave_total_count()])

	# ---- ② 击杀精英 ⇒ 锁关解除、波次收尾 ----
	elite.take_damage(9999999.0, Vector2.ZERO, false)
	var ended_after_kill := await _wait_leave_fight(5.0)
	_c.check(ended_after_kill,
		"② 精英伏诛后锁关解除、波次进入结算（phase=%d）" % int(_spawner.phase))

	# ---- ③ 精英提前伏诛 ⇒ 不必等表走完（余时赏路径照旧） ----
	_begin_wave(15)
	var elite_early := await _spawn_gatekeeper()
	var left_before_kill := float(_spawner.wave_timer)
	_c.check(elite_early != null and left_before_kill > 10.0,
		"③ 第 15 波开局精英在场、表还剩 %.1fs" % left_before_kill)
	elite_early.take_damage(9999999.0, Vector2.ZERO, false)
	var ended_early := await _wait_leave_fight(5.0)
	_c.check(ended_early and float(_spawner.wave_timer) > 10.0,
		"③ 提前击杀精英 ⇒ 不等表走完即收尾（收尾时还剩 %.1fs）" % float(_spawner.wave_timer))

	# ---- ④ 普通波：表走到 0 照旧收尾，且不许发锁关播报 ----
	_begin_wave(7)
	_spawner._budget_used = maxi(_spawner._budget_total - 1, 0)   # 预算差一只，堵掉提前清场腿
	_spawner.wave_timer = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	_c.check(int(_spawner.phase) != int(WaveSpawner.Phase.FIGHT),
		"④ 普通波表走到 0 照旧收尾（phase=%d）" % int(_spawner.phase))
	_c.check(_count_line("未除") == 0, "④ 普通波不发锁关播报（锁关不外溢）")

	# ---- ⑤ Boss 回合：原有锁关口径不能被本次重构改坏 ----
	_begin_wave(10)
	_spawner.elite_spawned = true
	_spawner._spawn_boss(GameManager.player)
	await _wait_until(func(): return _spawner._boss_ref != null, 5.0)
	_c.check(_spawner._boss_ref != null, "⑤ 第 10 波魔君已落地")
	_spawner.wave_timer = 0.0
	await _wait_secs(1.0)
	_c.check(int(_spawner.phase) == int(WaveSpawner.Phase.FIGHT),
		"⑤ Boss 未死仍锁关（phase=%d）" % int(_spawner.phase))
	_c.check(_count_line("Boss未除") == 1, "⑤ Boss 锁关播报照旧")
	if _spawner._boss_ref != null and is_instance_valid(_spawner._boss_ref):
		_spawner._boss_ref.take_damage(99999999.0, Vector2.ZERO, false)
	var ended_boss := await _wait_leave_fight(8.0)
	_c.check(ended_boss, "⑤ 击杀魔君后波次收尾（phase=%d）" % int(_spawner.phase))

	# ---- ⑥ 开新波清空上一波精英引用 ----
	_begin_wave(6)
	_c.check(_spawner._elite_ref == null, "⑥ 开新波清空上一波 _elite_ref（池化尸体不复读）")

	_main.queue_free()
	await get_tree().process_frame

## 开一波：把常规刷怪预算视为已刷尽（隔离关底这一件事），并清空现场与播报收集器。
## 经验门槛抬高：波末灵韵结算不许把等级顶出悟道面板打断后续枪。
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
	_lines.clear()

## 精英从真实刷怪口落地：先占住 elite_spawned（防 _process_fight 自动再刷一只），
## 再调 _spawn_elite → 等 SpawnIndicator 凝聚结束、callback 写回 _elite_ref。
func _spawn_gatekeeper() -> EnemyBase:
	_spawner.elite_spawned = true
	_spawner._spawn_elite(GameManager.player)
	await _wait_until(func(): return _spawner._elite_ref != null, 5.0)
	return _spawner._elite_ref

## 清空场上实体（走 remove_child 同帧注销登记表，不用 dissolve 动画拖时间）
func _clear_field() -> void:
	for group_name in ["enemies", "gems", "chests", "turrets"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if node is Node and node.get_parent() != null:
				node.get_parent().remove_child(node)
				node.queue_free()
	GameManager.enemy_count = 0

## 撑过 wall_secs 真实秒。锁关期间 wave_timer 已停在 0 不再走，不能拿它当表；
## headless 下 time_scale 恒 1，用场景计时器即可。
func _wait_secs(wall_secs: float) -> void:
	await get_tree().create_timer(wall_secs).timeout

## 按真实时间轮询（headless 帧率不可当秒表，不用帧数计时）：条件成立或超时返回条件值
func _wait_until(cond: Callable, timeout_secs: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_secs * 1000.0)
	while not bool(cond.call()):
		if Time.get_ticks_msec() >= deadline:
			return false
		await get_tree().create_timer(0.03).timeout
	return true

## 一帧一帧等 phase 离开 FIGHT；返回是否在时限内收尾
func _wait_leave_fight(max_secs: float) -> bool:
	return await _wait_until(
		func(): return int(_spawner.phase) != int(WaveSpawner.Phase.FIGHT), max_secs)

func _count_line(key: String) -> int:
	var n := 0
	for line in _lines:
		if line.find(key) >= 0:
			n += 1
	return n
