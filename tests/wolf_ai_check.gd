extends Node

## 妖狼（LeiBeastEnemy，图 = warrior_red_8dir ⇒ 青灰妖狼）扑击行为判据。
## 起因（用户现场 2026-10-08）：「近距离它为什么一直追着我、不放冲击技能，远距离才有冲击」。
## 旧版只有一条长扑，触发带下沿写死 120px ⇒ 贴着脸它整个技能不出手，只剩毫无预告的接触伤害
## 一路蹭；而且预警期不复查距离，玩家从 300px 走进贴身它照样把 307px 冲刺碾过去。
## 现在近距离补了一记短扑咬，两带以 charge_min_range 为界互补。这一屏钉死七件事：
##   ① 出生缓冲（旧 _charge_timer 初值 0.0 ⇒ 出屏第一帧就预警）
##   ② 远带走长扑    ③ 超出上沿谁都不出手（不许无限追扑）
##   ④ 近带走短咬，且**没跳到位就不结算**（不白罚）
##   ⑤ 两带互补不留缝（119px 有得看 / 121px 有得看）
##   ⑥ 长扑预警中被贴掉跑道 ⇒ 就地转短咬，不再把冲刺打出去
##   ⑦ 预警线长度 = 真撞得到的位移（不许虚报到玩家身上）
## 运行: godot --headless --path . res://tests/WolfAiCheck.tscn
## 只摆一个裸 world + 真 Player + 一只狼，不跑波次（别的怪会污染阶段读数）。

var _c := TestCheck.new()
var _world: Node2D
var _player: Node2D

## 一次观察的读数：四种阶段出现过没有、这一跑里起跳/结算各几次、预警线最长多少
func _blank() -> Dictionary:
	return {
		"windup": false, "active": false,
		"bite_windup": false, "bite_active": false,
		"launches": 0, "hits": 0, "line_max": 0.0,
		"windup_before_half_second": false,
	}

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	# 判据只关心「游戏时间内阶段有没有推进」：玩家受击走 feedback(LARGE) 会开 hit_stop
	# （Engine.time_scale = 0.04），把 9 秒的实测拖成几十分钟。这里关掉顿帧只改内存
	# （auto_save = false，不落盘、不动用户设置），最后再验一次时间标度没留残值。
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
	_c.check(wolf_probe.bite_range > 0.0, "前置：这一种怪确实配了近距离短咬")
	_c.check(
		wolf_probe.bite_range <= wolf_probe.charge_min_range,
		"前置：短咬上沿 ≤ 长拍下沿（两带互补的前提，%f ≤ %f）" % [wolf_probe.bite_range, wolf_probe.charge_min_range]
	)
	wolf_probe.queue_free()
	await get_tree().process_frame

	await _case_long_charge()
	await _case_out_of_range()
	await _case_close_bite()
	await _case_bands_meet()
	await _case_convert_on_closing()
	await _case_warning_line_honest()
	await _case_real_chase_bites()

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
	var was_active := false
	var was_hit := false
	var was_bite_active := false
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
		if wolf._bite_windup > 0.0:
			s["bite_windup"] = true
		# 起跳/结算各数一次"假→真"的边沿：一口跳只结算一口
		var is_active: bool = wolf._bite_active > 0.0
		if is_active and not was_bite_active:
			s["launches"] = int(s["launches"]) + 1
		was_bite_active = is_active
		var is_hit: bool = wolf._bite_hit
		if is_hit and not was_hit:
			s["hits"] = int(s["hits"]) + 1
		was_hit = is_hit
		if is_active:
			s["bite_active"] = true
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
	_c.check(not bool(s["bite_windup"]), "远带 220px：跑道够的时候不该改用短咬")
	wolf.queue_free()

## ③：520px 超出上沿 → 谁都不出手（只走位追人，不会隔半个屏幕扑）
func _case_out_of_range() -> void:
	var wolf := _spawn_wolf(520.0)
	var s: Dictionary = await _watch(wolf, 6.6, wolf.global_position)
	_c.check(not bool(s["windup"]) and not bool(s["bite_windup"]),
		"超出 charge_max_range 520px：长扑短咬都不起手")
	wolf.queue_free()

## ④：70px（近带）→ 走短咬；但 70px > 咬合半径 40px，钉住不动就跳不到人身上 ⇒ 一口都不结算
func _case_close_bite() -> void:
	var wolf := _spawn_wolf(70.0)
	var pin := wolf.global_position
	var s: Dictionary = await _watch(wolf, 4.2, pin)
	_c.check(bool(s["bite_windup"]) and bool(s["bite_active"]),
		"近带 70px：短咬出手了（下蹲预告 → 起跳），近距离不再是技能盲区")
	_c.check(not bool(s["windup"]) and not bool(s["active"]),
		"近带 70px：没跑道就不打长扑（旧版这里恒不出手、新版也不该硬冲）")
	_c.check(int(s["launches"]) >= 1 and int(s["hits"]) == 0,
		"没跳进咬合半径就一口不结算（起跳 %d 次、结算 %d 次 ⇒ 不白罚）" % [int(s["launches"]), int(s["hits"])])
	wolf.queue_free()

## ⑤：119px 与 121px 各归一带，中间不许出现"两带都不触发"的缝
func _case_bands_meet() -> void:
	var near := _spawn_wolf(119.0)
	var s_near: Dictionary = await _watch(near, 4.2, near.global_position)
	near.queue_free()
	var far := _spawn_wolf(121.0)
	var s_far: Dictionary = await _watch(far, 6.6, far.global_position)
	far.queue_free()
	_c.check(bool(s_near["bite_windup"]), "119px 落在短咬带里（≤ bite_range）")
	_c.check(bool(s_far["windup"]), "121px 落在长扑带里（> charge_min_range）")

## ⑥：长扑预警站桩期间被贴掉跑道 → 就地转短咬，不把 307px 冲刺碾过去
func _case_convert_on_closing() -> void:
	var wolf := _spawn_wolf(220.0)
	# 阶段一：钉在 220px 等到它真的进入预警
	var t := 0.0
	while wolf._charge_windup <= 0.0 and t < 6.0:
		wolf.global_position = _player.global_position + Vector2(220.0, 0.0)
		await get_tree().physics_frame
		t += maxf(wolf.get_physics_process_delta_time(), 0.0)
	_c.check(wolf._charge_windup > 0.0, "贴身转换前置：先在 220px 进入长扑预警")
	# 阶段二：玩家贴进来（等价于把狼挪到 40px），预警自然走完
	var charged := false
	var bit := false
	t = 0.0
	while t < 1.6:
		wolf.global_position = _player.global_position + Vector2(40.0, 0.0)
		await get_tree().physics_frame
		t += maxf(wolf.get_physics_process_delta_time(), 0.0)
		if wolf._charge_active > 0.0:
			charged = true
		if wolf._bite_active > 0.0:
			bit = true
	_c.check(bit and not charged,
		"预警中被贴掉跑道 → 转短咬（旧写法不复查距离，照样把冲刺打出去）")
	wolf.queue_free()

## ⑦：预警线只画「真撞得到的那一段」，不许画到玩家身上虚报射程
func _case_warning_line_honest() -> void:
	var wolf := _spawn_wolf(400.0)
	var reach := wolf.charge_duration * wolf.move_speed * wolf.charge_speed_mul
	var s: Dictionary = await _watch(wolf, 6.6, wolf.global_position)
	_c.check(bool(s["windup"]), "预警线前置：400px 已进入长扑预警")
	_c.check(float(s["line_max"]) <= reach + 1.0,
		"预警线长度 ≤ 真实冲刺位移（线最长 %.1f，位移 %.1f）" % [float(s["line_max"]), reach])
	_c.check(float(s["line_max"]) < 399.0,
		"400px 处不许把线画到玩家身上（旧写法恒等于当前距离 ⇒ 虚报 %.0fpx）" % (400.0 - reach))
	wolf.queue_free()

## 真走位：让它自己追（不钉），跑进贴身后短咬应当真的结算到玩家身上
func _case_real_chase_bites() -> void:
	var wolf := _spawn_wolf(200.0)
	var s: Dictionary = await _watch(wolf, 9.0, Vector2.ZERO)
	_c.check(int(s["hits"]) >= 1, "自由走位 9s：短咬真的咬到玩家（结算 %d 次）" % int(s["hits"]))
	_c.check(int(s["launches"]) == int(s["hits"]),
		"一次起跳只结算一口（起跳 %d 次 / 结算 %d 次）" % [int(s["launches"]), int(s["hits"])])
	wolf.queue_free()
