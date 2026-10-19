extends Node

## 妖狼（LeiBeastEnemy，图 = warrior_red_8dir ⇒ 青灰妖狼）扑击行为判据。
## 钉死八件事：
##   ① 出生缓冲（旧 _charge_timer 初值 0.0 ⇒ 出屏第一帧就预警）
##   ② 远带走长扑    ③ 超出上沿谁都不出手（不许无限追扑）
##   ④ 近带（< charge_min_range 120px）不出手长扑（需要跑道），继续追击
##   ⑤ 长扑预警中被贴脸（40px）不中断，照常冲刺出手
##   ⑥ 预警带长度 = GameBalance.charge_reach（不许虚报到玩家身上）
##   ⑦ 真冲出去的位移 = 画的带（逐帧量到速度归位，纸面/视觉/位移三方同尺）
##   ⑧ 静止玩家在线上必被这一冲在冲刺段内撂倒，侧身躲出走廊零结算且罚站
## 运行: godot --headless --path . res://tests/WolfAiCheck.tscn
## 只摆一个裸 world + 真 Player + 一只狼，不跑波次（别的怪会污染阶段读数）。

var _c := TestCheck.new()
var _world: Node2D
var _player: Node2D

## 一次观察的读数：冲刺阶段出现过没有、预警线最长多少
func _blank() -> Dictionary:
	return {
		"windup": false, "active": false,
		"line_max": 0.0,
		"windup_before_half_second": false,
	}

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	SettingsManager.set_val(&"display", &"hit_stop", false, false)
	Engine.time_scale = 8.0

	_world = Node2D.new()
	_world.name = "WolfAiWorld"
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
	_c.check(GameManager.is_game_over == false, "前置：对局未结束（否则怪不动）")

	var wolf_probe := _spawn_wolf(220.0)
	_c.check(wolf_probe.charge_interval > 0.0, "前置：这一种怪确实配了长扑（判据测的是它）")
	_c.check(wolf_probe.charge_brake_time > 0.0, "前置：配了收势刹车时长（量的位移要把这一段算进去）")
	_c.check(wolf_probe.charge_hit_radius > 0.0, "前置：配了冲刺走廊半宽（判的就是这条走廊）")
	wolf_probe.queue_free()
	await get_tree().process_frame

	await _case_long_charge()
	await _case_out_of_range()
	await _case_close_range_no_charge()
	await _case_charge_commit_on_closing()
	await _case_warning_line_honest()
	await _case_travel_matches_line()
	await _case_lunge_delivers()
	await _case_sidestep_whiffs()

	_world.queue_free()
	Engine.time_scale = 1.0
	# 时间标度留残值 = 上面所有"游戏秒"的读数都不可信，宁可红也不交假绿
	_c.check(is_equal_approx(Engine.time_scale, 1.0), "收尾：Engine.time_scale 已回到 1.0")
	if _c.report("WOLF_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

## 摆一只狼到玩家右侧 dist 处（_ready 里自带出生缓冲）
func _spawn_wolf(dist: float) -> EnemyBase:
	var wolf: EnemyBase = load("res://scenes/entities/LeiBeastEnemy.tscn").instantiate() as EnemyBase
	wolf.global_position = _player.global_position + Vector2(dist, 0.0)
	_world.add_child(wolf)
	return wolf

## 逐物理帧推进 seconds 秒游戏时间；pin 不为 ZERO 时每帧把狼钉回该点
## （钉住 = 只测触发条件、不让它自己走位；钉在玩家右侧 dist 处即"玩家一直在 dist"）
func _watch(wolf: EnemyBase, seconds: float, pin: Vector2) -> Dictionary:
	var s := _blank()
	var t := 0.0
	while t < seconds:
		if pin != Vector2.ZERO:
			wolf.global_position = pin
		await get_tree().physics_frame
		t += maxf(wolf.get_physics_process_delta_time(), 0.0)
		if wolf._charge_windup > 0.0:
			s["windup"] = true
			if t < 0.5:
				s["windup_before_half_second"] = true
		if wolf._charge_active > 0.0:
			s["active"] = true
		if wolf._charge_warning_line != null and wolf._charge_warning_line.get_point_count() >= 2:
			var a: Vector2 = wolf._charge_warning_line.get_point_position(0)
			var b: Vector2 = wolf._charge_warning_line.get_point_position(1)
			s["line_max"] = maxf(float(s["line_max"]), a.distance_to(b))
	return s

## ① + ②：220px（跑道够）→ 出生先等一个冷却，之后走长扑
func _case_long_charge() -> void:
	var wolf := _spawn_wolf(220.0)
	var pin := wolf.global_position
	var s: Dictionary = await _watch(wolf, 6.6, pin)
	_c.check(bool(s["windup"]) and bool(s["active"]),
		"远带 220px：冷却到 → 预警 → 冲刺（三段都出现过）")
	_c.check(not bool(s["windup_before_half_second"]),
		"出生缓冲：出屏 0.5s 内不许起手（旧初值 0.0 会第一帧就预警）")
	wolf.queue_free()

## ③：520px 超出上沿 → 谁都不出手（只走位追人，不会隔半个屏幕扑）
func _case_out_of_range() -> void:
	var wolf := _spawn_wolf(520.0)
	var s: Dictionary = await _watch(wolf, 6.6, wolf.global_position)
	_c.check(not bool(s["windup"]),
		"超出 charge_max_range 520px：长扑不起手")
	wolf.queue_free()

## ④：70px（近带 < charge_min_range 120px）→ 需要跑道，不打长扑
func _case_close_range_no_charge() -> void:
	var wolf := _spawn_wolf(70.0)
	var pin := wolf.global_position
	var s: Dictionary = await _watch(wolf, 4.2, pin)
	_c.check(not bool(s["windup"]) and not bool(s["active"]),
		"近带 70px：跑道不够不起手长扑（只走追击+接触判定）")
	wolf.queue_free()

## ⑤：长扑预警站桩期间被贴脸 → 照常冲出去（无条件冲刺出手，不再中断或转招）
func _case_charge_commit_on_closing() -> void:
	var wolf := _spawn_wolf(220.0)
	# 阶段一：钉在 220px 等到它真的进入预警
	var t := 0.0
	while wolf._charge_windup <= 0.0 and t < 6.0:
		wolf.global_position = _player.global_position + Vector2(220.0, 0.0)
		await get_tree().physics_frame
		t += maxf(wolf.get_physics_process_delta_time(), 0.0)
	_c.check(wolf._charge_windup > 0.0, "贴身前置：先在 220px 进入长扑预警")
	# 阶段二：玩家贴进来（把狼挪到 40px），预警自然走完并照常冲出
	var charged := false
	t = 0.0
	while t < 1.6:
		wolf.global_position = _player.global_position + Vector2(40.0, 0.0)
		await get_tree().physics_frame
		t += maxf(wolf.get_physics_process_delta_time(), 0.0)
		if wolf._charge_active > 0.0:
			charged = true
			break
	_c.check(charged, "预警中被贴脸（40px）：预警走完依然照常冲刺出手")
	wolf.queue_free()

## ⑥：预警带只画「真撞得到的那一段」，不许画到玩家身上虚报射程
func _case_warning_line_honest() -> void:
	var wolf := _spawn_wolf(400.0)
	var reach: float = GameBalance.charge_reach(wolf.move_speed * wolf.charge_speed_mul, wolf.charge_duration, wolf.charge_brake_time)
	var s: Dictionary = await _watch(wolf, 6.6, wolf.global_position)
	_c.check(bool(s["windup"]), "预警线前置：400px 已进入长扑预警")
	_c.check(float(s["line_max"]) <= reach + 1.0,
		"预警带长度 ≤ 真实冲刺位移（带最长 %.1f，charge_reach %.1f）" % [float(s["line_max"]), reach])
	_c.check(float(s["line_max"]) < 399.0,
		"400px 处不许把带画到玩家身上（旧写法恒等于当前距离 ⇒ 虚报 %.0fpx）" % (400.0 - reach))
	wolf.queue_free()

## 读预警带中心线长（Line2D 的圆头端帽向两端各延伸半宽，那一段不算进"线长"读数）
func _line_len(wolf: EnemyBase) -> float:
	var line: Line2D = wolf._charge_warning_line
	if line == null or line.get_point_count() < 2:
		return 0.0
	return line.get_point_position(0).distance_to(line.get_point_position(1))

## 钉在 dist 处一路走到长扑起跑那一帧，返回预告期间画出的最长带（没起跑则 -1）
## 复用 ⑥ 的两段式写法：钉住 = 只测触发与预告，不让它自己走位污染读数
func _pin_until_launch(wolf: EnemyBase, dist: float) -> float:
	var line_max := 0.0
	var t := 0.0
	while wolf._charge_active <= 0.0 and t < 6.0:
		wolf.global_position = _player.global_position + Vector2(dist, 0.0)
		await get_tree().physics_frame
		t += maxf(wolf.get_physics_process_delta_time(), 0.0)
		line_max = maxf(line_max, _line_len(wolf))
	return line_max if wolf._charge_active > 0.0 else -1.0

## ⑧：真冲出去的位移 == 画出去的带（纸面 / 视觉 / 位移三方同一条尺子）
## 旧写法冲刺段只交一个 target_vel，由 900 px/s² 的吸附插值从站桩预警的 0 速去爬峰速，
## 冲完还留一段朝玩家拐弯的滑行 ⇒ 位移既不是纸面值、也不是画出来的长度
func _case_travel_matches_line() -> void:
	var wolf := _spawn_wolf(400.0)
	var peak: float = wolf.move_speed * wolf.charge_speed_mul
	var reach: float = GameBalance.charge_reach(peak, wolf.charge_duration, wolf.charge_brake_time)
	var line_len: float = await _pin_until_launch(wolf, 400.0)
	_c.check(line_len >= 0.0, "⑧ 前置：400px 起跑并画出了预警带")
	# 起跑后解钉。400px 冲 336px 停在离玩家约 60px 处（> 走廊半宽）⇒ 这一冲必然落空，
	# 落空接 0.9s 罚站、速度干净归零 ⇒ "量到速度归位"不会被下一次起步污染
	var launch_pos: Vector2 = wolf.global_position
	var travel := 0.0
	var peak_seen := 0.0
	var t := 0.0
	while t < 3.0:
		await get_tree().physics_frame
		t += maxf(wolf.get_physics_process_delta_time(), 0.0)
		peak_seen = maxf(peak_seen, wolf.velocity.length())
		travel = maxf(travel, launch_pos.distance_to(wolf.global_position))
		if wolf._charge_active <= 0.0 and wolf._charge_brake <= 0.0 and wolf._charge_stagger > 0.0:
			break
	# 容差 ±10%：本屏跑在 Engine.time_scale = 8.0（一物理帧 = 0.133s），刹车段按帧量化最多丢 ~8%
	var tol: float = maxf(reach * 0.10, 8.0)
	_c.check(absf(travel - reach) <= tol,
		"实冲位移 %.1f = charge_reach 纸面 %.1f（容差 ±%.1f）" % [travel, reach, tol])
	_c.check(absf(line_len - travel) <= tol,
		"画出去的带 %.1f = 实冲位移 %.1f（画多大 == 撞多远）" % [line_len, travel])
	_c.check(absf(peak_seen - peak) <= peak * 0.03,
		"起步即满速：峰值 %.0f = move_speed×mul %.0f（旧写法靠插值爬，白丢一段位移）" % [peak_seen, peak])
	_c.check(travel <= reach * 1.35, "位移不许被悄悄放大（同 DashTravelProbe 那条兜底）")
	wolf.queue_free()

## ⑨：玩家站着不动 → 这一冲必须真的撂倒人，且在承诺段（冲刺+收势）内结算、只结算一下
## 旧写法长扑只有 33.5px 身位滑碰这一个出口，走廊判定这条口根本不存在 ⇒ 本条红
func _case_lunge_delivers() -> void:
	var wolf := _spawn_wolf(320.0)
	_c.check(GameManager.get_effective_dodge() < 0.05,
		"⑨ 前置：默认修士闪避近乎为零（这条用血量下降作读数， dodge 高了读数会漂）")
	var line_len: float = await _pin_until_launch(wolf, 320.0)
	_c.check(line_len >= 0.0, "⑨ 前置：320px 起跑并画出了预警带")
	# 起跑帧解钉，玩家零输入站在原地不动
	var hp_before: float = _player.current_health
	var launches := 0
	var hits := 0
	var was_active := false
	var was_hit := false
	var hit_in_commit := false
	var damaged_in_commit := false
	var staggered := false
	var t := 0.0
	while t < 1.9:
		await get_tree().physics_frame
		t += maxf(wolf.get_physics_process_delta_time(), 0.0)
		var locked: bool = wolf._charge_active > 0.0 or wolf._charge_brake > 0.0
		var is_active: bool = wolf._charge_active > 0.0
		if is_active and not was_active:
			launches += 1
		was_active = is_active
		var is_hit: bool = wolf._charge_hit
		if is_hit and not was_hit:
			hits += 1
			hit_in_commit = locked
		was_hit = is_hit
		if _player.current_health < hp_before and not damaged_in_commit:
			damaged_in_commit = locked
		if wolf._charge_stagger > 0.0:
			staggered = true
	_c.check(hits == 1 and hit_in_commit,
		"静止玩家在线上：这一冲在承诺段内结算（起冲 %d 次 / 结算 %d 次，结算在承诺段 = %s）" % [launches, hits, hit_in_commit])
	_c.check(damaged_in_commit, "结算真的掉到玩家血量上（掉血发生在承诺段 = %s）" % damaged_in_commit)
	_c.check(not staggered, "碾到人的那一冲不罚站（落空才罚）")
	wolf.queue_free()

## ⑧：预警期侧身一步躲出走廊 → 零结算，且冲空要罚站挨打（躲开的奖励）
func _case_sidestep_whiffs() -> void:
	var wolf := _spawn_wolf(320.0)
	var line_len: float = await _pin_until_launch(wolf, 320.0)
	_c.check(line_len >= 0.0, "⑧ 前置：320px 起跑并画出了预警带")
	# 起跑帧把玩家挪到侧向 60px（走廊半宽 34 ⇒ 留 26px 余量；方向已在起跑帧锁死，不再拐弯）
	_player.global_position = Vector2(0.0, 60.0)
	var hits := 0
	var was_hit := false
	var stagger_pos := Vector2.INF
	var t := 0.0
	var stagger_drift := 0.0
	while t < 2.4:
		await get_tree().physics_frame
		t += maxf(wolf.get_physics_process_delta_time(), 0.0)
		var is_hit: bool = wolf._charge_hit
		if is_hit and not was_hit:
			hits += 1
		was_hit = is_hit
		# 罚站起算点：承诺段（冲刺 + 收势刹车）走完、_charge_stagger 独占的那一段
		if stagger_pos == Vector2.INF:
			if wolf._charge_stagger > 0.0 and wolf._charge_brake <= 0.0:
				stagger_pos = wolf.global_position
		elif wolf._charge_stagger > 0.0:
			stagger_drift = maxf(stagger_drift, stagger_pos.distance_to(wolf.global_position))
		else:
			# 罚站走完了 ⇒ 读数结束。再往后是重新追击，不属于"站桩挨打"这一段
			break
	_c.check(hits == 0, "躲出走廊（横移 60 > 半宽 %.0f）这一冲零结算（结算 %d 次）" % [wolf.charge_hit_radius, hits])
	_c.check(stagger_pos != Vector2.INF, "冲空了要罚站（落空收势硬直 = 玩家的反打窗口）")
	_c.check(stagger_drift <= 10.0, "罚站期间不追人（站桩 %.1fs 内位移 %.1fpx）" % [wolf.charge_whiff_stagger, stagger_drift])
	wolf.queue_free()
