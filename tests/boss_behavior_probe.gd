extends Node

## Boss 行为探针（判据）：对 BOSS_POOL 全部魔君做 60~90s 虚拟对局，量化
## 「角落停留时长 / 换桩次数 / 决策出招频率 / 贴边率 / 招式多样性」，并锁三条回归：
##   1. 千机尊炮台：换桩落点必须在地图钳制范围内（旧屏幕坐标中心 (480,270) 会把每次
##      换桩钳到 ±460 物理边界 = 永远蹲角落），且有换桩保底间隔（不得长时间不动）。
##   2. 二阶段狂暴：小伤害高频削血也必须触发（变身判定不得被重击创伤闸吞掉）。
##   3. 瞬步回斩：玩家在负坐标象限时落点仍须贴脸（旧钳制 90~870 会把 Boss 钳到正象限）。
## 运行: godot --headless --path . res://tests/BossBehaviorProbe.tscn
## 退出码 0 且末行 BOSS_BEHAVIOR_PROBE_RESULT: ALL PASS

var _c := TestCheck.new()

const SIM_DT := 0.05
## 位移判定阈值：单步位移超过该值视为「瞬移类换桩」（冲锋满速单步 ~14px，不会误报）
const TELEPORT_STEP_PX := 60.0
## 停留判定半径：位移不超过该值视为「原地待着」
const DWELL_RADIUS_PX := 12.0
## 贴边判定：任一坐标分量距物理边界（±460）不足 60px 视为贴边
const EDGE_LINE := 400.0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	GameManager.reset_run()
	_c.set_min_checks(12)

	_test_phase2_chip_damage()
	_test_phase2_heavy_hit()
	_test_turret_shift_lands_in_bounds()
	_test_blink_slash_negative_quadrant()
	_test_qianji_corner_camp()
	_test_all_bosses_activity()
	_test_wangu_corner_kite()

	if not _c.all_passed():
		print("BOSS_BEHAVIOR_PROBE_RESULT: FAILED (%d failures)" % _c.failures.size())
		get_tree().quit(1)
	else:
		print("BOSS_BEHAVIOR_PROBE_RESULT: ALL PASS (%d checks)" % _c.passed)
		get_tree().quit(0)

func _make_player(pos: Vector2) -> Player:
	GameManager.cultivator_id = "jianchi"
	var p_scene: PackedScene = load("res://scenes/entities/Player.tscn")
	var p := p_scene.instantiate() as Player
	add_child(p)
	p.global_position = pos
	p.max_health = 999999.0
	p.current_health = 999999.0
	p.invulnerable_time = 0.0
	GameManager.player = p
	return p

func _make_boss(bid: String, pos: Vector2, interval: float) -> BossEnemy:
	var boss_scene: PackedScene = load("res://scenes/entities/BossEnemy.tscn")
	var boss := boss_scene.instantiate() as BossEnemy
	boss.boss_id = bid
	add_child(boss)
	boss.global_position = pos
	boss.attack_interval = interval
	boss.max_hp = 999999.0
	boss.current_hp = 999999.0
	return boss

## 清理在场弹丸：长时间模拟中环弹/扇形弹只进不出会耗尽对象池
func _recycle_bolts() -> void:
	if EnemyBolt._host == null:
		return
	for child in EnemyBolt._host.get_children():
		if child is EnemyBolt and not child._pooled:
			child._recycle()

## 虚拟对局：手动按帧推进 Boss 大脑与物理（不驱动场景树，弹丸定期回收）。
## 返回 {casts, teleports, max_dwell, edge_ratio, patterns: Dictionary}
func _sim_boss(boss: BossEnemy, duration: float) -> Dictionary:
	var steps := int(duration / SIM_DT)
	var casts := 0
	var teleports := 0
	var edge_steps := 0
	var patterns: Dictionary = {}
	var last_idx: int = boss._pattern_idx
	var prev_pos: Vector2 = boss.global_position
	var anchor: Vector2 = boss.global_position
	var anchor_t: float = 0.0
	var max_dwell: float = 0.0
	var t: float = 0.0
	for i in range(steps):
		boss._physics_process(SIM_DT)
		boss._process(SIM_DT)
		t += SIM_DT
		if boss._pattern_idx != last_idx:
			last_idx = boss._pattern_idx
			casts += 1
			patterns[boss._last_pattern] = int(patterns.get(boss._last_pattern, 0)) + 1
		var pos: Vector2 = boss.global_position
		if pos.distance_to(prev_pos) > TELEPORT_STEP_PX:
			teleports += 1
		prev_pos = pos
		if pos.distance_to(anchor) > DWELL_RADIUS_PX:
			max_dwell = maxf(max_dwell, t - anchor_t)
			anchor = pos
			anchor_t = t
		if maxf(absf(pos.x), absf(pos.y)) > EDGE_LINE:
			edge_steps += 1
		if i % 10 == 9:
			_recycle_bolts()
	max_dwell = maxf(max_dwell, t - anchor_t)
	return {
		"casts": casts,
		"teleports": teleports,
		"max_dwell": max_dwell,
		"edge_ratio": float(edge_steps) / float(steps),
		"patterns": patterns,
	}

func _pattern_names(patterns: Dictionary) -> String:
	var names: Array[String] = []
	for k in patterns.keys():
		names.append("%s×%d" % [BossEnemy.Pattern.keys()[int(k)], int(patterns[k])])
	names.sort()
	return ", ".join(names)

# ---------------- 判据 1：小伤害高频削血也必须打进二阶段 ----------------

func _test_phase2_chip_damage() -> void:
	var p := _make_player(Vector2(450.0, 450.0))
	var boss := _make_boss("chiyan", Vector2(-450.0, -450.0), 3.8)
	boss.max_hp = 1000.0
	boss.current_hp = 1000.0
	# 单次 0.5% 最大生命（低于 6% 重击闸），连削到 30%：快速小伤害流派的典型剖面
	while boss.current_hp > 300.0 and not boss.dying:
		boss.take_damage(5.0, Vector2.ZERO)
	_c.check(boss._phase2, "小伤害高频削血至半血以下 → 二阶段狂暴必须触发")
	boss._die()
	boss.queue_free()
	p.queue_free()
	GameManager.player = null

func _test_phase2_heavy_hit() -> void:
	var p := _make_player(Vector2(450.0, 450.0))
	var boss := _make_boss("chiyan", Vector2(-450.0, -450.0), 3.8)
	boss.max_hp = 1000.0
	boss.current_hp = 1000.0
	boss.take_damage(600.0, Vector2.ZERO)  # 单发 60% ≥ 重击闸，血量 40% ≤ 变身线
	_c.check(boss._phase2, "单发重击压过变身线 → 二阶段狂暴触发（回归保护）")
	boss._die()
	boss.queue_free()
	p.queue_free()
	GameManager.player = null

# ---------------- 判据 2：换桩/瞬步落点不得被旧屏幕坐标钳到图外/正象限 ----------------

func _test_turret_shift_lands_in_bounds() -> void:
	var p := _make_player(Vector2(0.0, 0.0))
	var qianji := _make_boss("qianji", Vector2(-380.0, -380.0), 2.9)
	var lim: float = GameManager.MAP_HALF_EXTENT - 20.0
	for i in range(3):
		qianji._cast_turret_shift(p)
		# 2026-11-03：换桩改为「前摇填符环 → 落地」，手动推进物理帧把前摇走完再量落点
		qianji._physics_process(GameBalance.BOSS_TURRET_SHIFT_WINDUP + 0.05)
		var pos: Vector2 = qianji.global_position
		_c.check(maxf(absf(pos.x), absf(pos.y)) <= lim,
			"换桩落点 %s 在物理边界 ±%.0f 内" % [str(pos), lim])
		_recycle_bolts()
	qianji._die()
	qianji.queue_free()
	p.queue_free()
	GameManager.player = null

func _test_blink_slash_negative_quadrant() -> void:
	var p := _make_player(Vector2(-300.0, -200.0))
	var jianpo := _make_boss("jianpo", Vector2(300.0, 200.0), 2.8)
	jianpo._cast_blink_slash(p)
	# 前摇期不得提前落地：先断言仍在原地、符环已亮，再推进前摇量落点
	var origin: Vector2 = jianpo.global_position
	_c.check(jianpo.global_position.distance_to(origin) < 1.0 and jianpo._blink_rift != null,
		"瞬步回斩起手：原地锁定落点并亮符环（不瞬移）")
	jianpo._physics_process(GameBalance.BOSS_BLINK_SLASH_WINDUP + 0.05)
	_c.check(jianpo.global_position.distance_to(p.global_position) <= GameBalance.BOSS_BLINK_SLASH_DIST + 40.0,
		"玩家在负坐标象限：瞬步回斩落点仍贴脸（不被旧钳制拽去正象限）")
	_recycle_bolts()
	jianpo._die()
	jianpo.queue_free()
	p.queue_free()
	GameManager.player = null

# ---------------- 判据 3：千机尊 90s 角落蹲守复现（第 25 波战报） ----------------

func _test_qianji_corner_camp() -> void:
	var p := _make_player(Vector2(80.0, 40.0))
	var qianji := _make_boss("qianji", Vector2(-380.0, -380.0), 2.9)
	var m: Dictionary = _sim_boss(qianji, 90.0)
	print("METRIC qianji casts=%d teleports=%d max_dwell=%.1fs edge_ratio=%.2f patterns=[%s]" % [
		int(m.casts), int(m.teleports), float(m.max_dwell), float(m.edge_ratio), _pattern_names(m.patterns)])
	_c.check(int(m.teleports) >= 6, "千机尊 90s 换桩次数 >= 6（有保底机动，不一蹲到底）")
	_c.check(float(m.max_dwell) <= 13.0, "千机尊最长原地停留 <= 13s（决策超时强制换桩）")
	_c.check(float(m.edge_ratio) <= 0.5, "千机尊贴边时间占比 <= 50%（换桩落点在场内，不被钳到边缘）")
	qianji._die()
	qianji.queue_free()
	p.queue_free()
	GameManager.player = null

# ---------------- 判据 4：全 Boss 出招活跃度与招式多样性 ----------------

func _test_all_bosses_activity() -> void:
	var roster: Array = [
		["", 3.8], ["chiyan", 3.8], ["xiuluo", 3.0], ["qianji", 2.9],
		["wangu", 3.3], ["jianpo", 2.8], ["xinmo", 2.7],
		# 深层专属魔君（W45~W100，2026-11-03）：同一活跃度/多样性口径
		["zhaoying", 3.2], ["yinhun", 3.1], ["luding", 3.0],
		["canglong", 2.9], ["jianzhong", 2.8], ["leijie", 2.7], ["kunwang", 3.0],
		["kuijia", 2.8], ["fenghuang", 2.6], ["tianmo", 2.5], ["hundun", 2.5], ["wanjie", 2.4],
	]
	var p := _make_player(Vector2(0.0, 0.0))
	for entry in roster:
		var bid: String = entry[0]
		var boss := _make_boss(bid, Vector2(300.0, -300.0), float(entry[1]))
		var m: Dictionary = _sim_boss(boss, 60.0)
		var casts_per30: float = float(int(m.casts)) * 30.0 / 60.0
		var label: String = bid if bid != "" else "legacy"
		print("METRIC %s casts_per30=%.1f teleports=%d max_dwell=%.1fs edge_ratio=%.2f patterns=[%s]" % [
			label, casts_per30, int(m.teleports), float(m.max_dwell), float(m.edge_ratio), _pattern_names(m.patterns)])
		_c.check(casts_per30 >= 3.0, "%s 每 30s 出招 >= 3 次（决策不停摆）" % label)
		_c.check((m.patterns as Dictionary).size() >= 3, "%s 60s 内使用 >= 3 种不同招式" % label)
		boss._die()
		boss.queue_free()
	_recycle_bolts()
	p.queue_free()
	GameManager.player = null

# ---------------- 判据 5：万蛊风筝被压墙角不得钉死（回归保护） ----------------

func _test_wangu_corner_kite() -> void:
	var p := _make_player(Vector2(300.0, 300.0))
	var wangu := _make_boss("wangu", Vector2(440.0, 440.0), 3.3)
	wangu._attack_timer = 999.0  # 只验走位，不出招
	var dt := 1.0 / 60.0
	for i in range(60):  # 先 1s 让风筝逻辑把 Boss 压到墙角
		wangu._physics_process(dt)
	var watch_from: Vector2 = wangu.global_position
	for i in range(120):  # 再观察 2s
		wangu._physics_process(dt)
	var moved: float = wangu.global_position.distance_to(watch_from)
	print("METRIC wangu corner_moved=%.1fpx pos=%s" % [moved, str(wangu.global_position)])
	_c.check(moved >= 40.0, "万蛊被压墙角后 2s 内仍在走位（位移 %.0fpx，不钉死）" % moved)
	wangu._die()
	wangu.queue_free()
	p.queue_free()
	GameManager.player = null
