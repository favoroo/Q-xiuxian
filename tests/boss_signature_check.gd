extends Node

## Boss 签名招判据（2026-11-03）：新八招 + 镜影/魂潮前摇 + 俯冲换位/定身清理 + 冲锋锁向复位。
## 只验行为几何与状态机，不做视觉截图；每条都要求「至少产生一颗弹幕/预警」且不崩。
## 运行: godot --headless --path . res://tests/BossSignatureCheck.tscn
## 退出码 0 且末行 BOSS_SIGNATURE_CHECK_RESULT: ALL PASS

var _c := TestCheck.new()

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	GameManager.reset_run()
	_c.set_min_checks(12)
	var p := _make_player(Vector2.ZERO)

	await _test_all_signatures(p)
	await _test_deep_summon(p)
	await _test_mirror_windup(p)
	await _test_soul_windup(p)
	_test_dive_anchor(p)
	_test_charge_lock_reset(p)

	p.queue_free()
	GameManager.player = null
	_recycle_bolts()
	if not _c.all_passed():
		print("BOSS_SIGNATURE_CHECK_RESULT: FAILED (%d failures)" % _c.failures.size())
		get_tree().quit(1)
	else:
		print("BOSS_SIGNATURE_CHECK_RESULT: ALL PASS (%d checks)" % _c.passed)
		get_tree().quit(0)

func _make_player(pos: Vector2) -> Player:
	GameManager.cultivator_id = "jianchi"
	var p_scene: PackedScene = load("res://scenes/entities/Player.tscn")
	var p := p_scene.instantiate() as Player
	add_child(p)
	p.global_position = pos
	p.max_health = 999999.0
	p.current_health = 999999.0
	# 判据只看「弹幕有没有出膛」，不让弹幕命中后回收干扰 active_count
	p.invulnerable_time = 9999.0
	GameManager.player = p
	return p

func _make_boss(bid: String, pos: Vector2) -> BossEnemy:
	var boss_scene: PackedScene = load("res://scenes/entities/BossEnemy.tscn")
	var boss := boss_scene.instantiate() as BossEnemy
	boss.boss_id = bid
	add_child(boss)
	boss.global_position = pos
	boss.attack_interval = 999.0
	boss._attack_timer = 999.0
	return boss

func _recycle_bolts() -> void:
	if EnemyBolt._host == null:
		return
	for child in EnemyBolt._host.get_children():
		if child is EnemyBolt and not child._pooled:
			child._recycle()

## 弹幕「出膛总数」累计读数：命中玩家后弹体会回池，active_count 会掉；
## created+reused 是单调递增的发射计数，判据只看「有没有真的打出去」。
func _bolt_serial() -> int:
	return EnemyBolt.created_count + EnemyBolt.reused_count

func _test_all_signatures(p: Player) -> void:
	var ids: Array[String] = ["jianzhong", "leijie", "kunwang", "kuijia", "fenghuang", "tianmo", "hundun", "wanjie"]
	for bid in ids:
		var boss := _make_boss(bid, Vector2(260.0, 0.0))
		var before := _bolt_serial()
		boss._cast_signature(p)
		# 延迟类签名（雷劫/机弩/无相）靠 tween 分步出招；1.6s 足够走完一轮
		await get_tree().create_timer(1.6).timeout
		_c.check(_bolt_serial() > before, "%s 签名招至少产生一颗弹幕" % bid)
		_c.check(not boss.dying, "%s 签名招执行后未进入死亡态" % bid)
		boss._die()
		boss.queue_free()
		_recycle_bolts()

func _test_deep_summon(p: Player) -> void:
	# W45 起召唤物换深层妖种；路径懒加载不能为空，否则傀王/引魂使的召唤只剩掩护火球
	var old_wave := GameManager.wave_number
	GameManager.wave_number = 45
	var boss := _make_boss("kuijia", Vector2(200.0, 0.0))
	var before := GameManager.enemy_count
	boss._cast_summon(p)
	await get_tree().process_frame
	_c.check(boss._deep_minion_scenes.size() > 0, "W45 召唤使用深层妖种表")
	_c.check(GameManager.enemy_count > before, "W45 召唤至少落地一只深层妖")
	boss._die()
	boss.queue_free()
	for child in get_children():
		if child is EnemyBase and child != boss and not child.dying:
			child.queue_free()
	GameManager.wave_number = old_wave
	_recycle_bolts()

func _test_mirror_windup(p: Player) -> void:
	var boss := _make_boss("zhaoying", Vector2(260.0, 0.0))
	var before := _bolt_serial()
	boss._cast_mirror_flank(p)
	_c.check(boss._mirror_pending, "镜影夹击起手进入前摇态")
	_c.check(boss._mirror_telegraph != null and boss._mirror_telegraph.visible, "镜影落点预警圈可见")
	boss._process(GameBalance.BOSS_MIRROR_WINDUP + 0.05)
	_c.check(not boss._mirror_pending, "镜影前摇结束回到常规态")
	_c.check(_bolt_serial() > before, "镜影前摇结束后环弹/扇形已出膛")
	_c.check(not boss._mirror_telegraph.visible, "镜影预警圈结算后隐藏")
	boss._die()
	boss.queue_free()
	_recycle_bolts()

func _test_soul_windup(p: Player) -> void:
	var boss := _make_boss("yinhun", Vector2(260.0, 0.0))
	var before := _bolt_serial()
	boss._cast_soul_tide(p)
	_c.check(boss._soul_pending, "魂潮收网起手进入前摇态")
	_c.check(boss._soul_telegraph != null and boss._soul_telegraph.visible, "魂潮收网点预警圈可见")
	boss._process(GameBalance.BOSS_SOUL_TIDE_WINDUP + 0.05)
	_c.check(not boss._soul_pending, "魂潮前摇结束回到常规态")
	_c.check(_bolt_serial() > before, "魂潮前摇结束后包围环已出膛")
	_c.check(not boss._soul_telegraph.visible, "魂潮预警圈结算后隐藏")
	boss._die()
	boss.queue_free()
	_recycle_bolts()

func _test_dive_anchor(p: Player) -> void:
	# 玩家贴右墙、Boss 在玩家更右侧：旧钳制会把锚点落回 Boss 原地，俯冲没有助跑
	var boss := _make_boss("canglong", Vector2(400.0, 0.0))
	p.global_position = Vector2(380.0, 0.0)
	var origin := boss.global_position
	boss._cast_dive(p)
	_c.check(boss._blink_rift != null and boss._blink_rift.visible, "俯冲拉升起手亮落点符环")
	_c.check(boss.global_position.distance_to(origin) < 1.0, "俯冲拉升前摇期不提前换位（画哪落哪）")
	# 2026-11-03：换位改为「前摇填符环 → 落地」，手动推进物理帧把拉升前摇走完
	boss._physics_process(GameBalance.BOSS_DIVE_LEAP_WINDUP + 0.05)
	_c.check(boss.global_position.distance_to(p.global_position) >= GameBalance.BOSS_DIVE_MIN_LEAP,
		"俯冲换位后与玩家至少保留 %.0fpx 助跑" % GameBalance.BOSS_DIVE_MIN_LEAP)
	_c.check(boss._dive_pending, "俯冲进入预警态")
	# 罡风定身打断前摇：必须清掉 pending 并恢复冲锋口径，下一次普通冲锋才不会被当成俯冲
	boss.apply_vortex_pin(Vector2.ZERO, 0.5)
	_c.check(not boss._dive_pending, "定身打断后俯冲 pending 已清理")
	_c.near(boss.charge_duration, GameBalance.BOSS_CHARGE_DURATION, 0.01, "定身打断后冲锋时长已恢复")
	boss._die()
	boss.queue_free()
	_recycle_bolts()

func _test_charge_lock_reset(p: Player) -> void:
	var boss := _make_boss("chiyan", Vector2(200.0, 0.0))
	boss._charge_aim_locked = true
	boss._cast_charge(p)
	_c.check(not boss._charge_aim_locked, "新一轮冲锋起手复位锁向（预警线重新跟人）")
	_c.check(boss._charge_windup > 0.0, "冲锋起手进入预警态")
	boss._die()
	boss.queue_free()
	_recycle_bolts()
