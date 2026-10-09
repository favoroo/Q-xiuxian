extends Node

## 缩地成寸「实际冲出去多远」诊断（真实 Main 场景，不打 mock，释放走 HUD 同一入口 try_activate_skill）
## 为什么需要它：SkillData 里的 distance 只是纸面值。冲刺结束那一帧速度仍是
## distance/duration 的峰值（260/0.16 = 1625 px/s），之后靠 2200~2800 px/s² 的加减速
## 插值慢慢掉回常速 ⇒ 真正的位移 = 冲刺段 + 一段没写进数据表的惯性滑行段。
## 「冲得太远」到底是哪一段贡献的，只有逐帧量真实落点才看得见。
## 输出：纸面距离 / 冲刺段位移 / 滑行段位移 / 总位移 / 峰值速度 / 掉回常速的帧数
## 运行: godot --headless --path . res://tests/DashTravelProbe.tscn
## 退出码 0 = 实际总位移 ≤ 纸面 1.35 倍（滑行段不许把冲刺悄悄放大）；末行 DASH_TRAVEL_RESULT

var _c := TestCheck.new()

func _dismiss() -> void:
	for node_name in ["LevelUpDialog", "WaveShop", "PlayerStatsDialog", "PauseMenu", "SettingsDialog"]:
		var n := get_node_or_null("/root/Main/UILayer/" + node_name)
		if n != null and n.visible:
			n.visible = false
	get_tree().paused = false

func _ready() -> void:
	call_deferred("_run")

## 跑一次冲刺并逐帧量落点。hold=true 模拟摇杆一直朝冲刺方向推着，false = 松手站着放
func _measure(main: Node, hold: bool, cid: String) -> Dictionary:
	var player: Player = GameManager.player
	if player == null:
		return {}
	GameManager.cultivator_id = cid
	GameManager.active_skill_id = "dash"
	player.velocity = Vector2.ZERO
	player._dash_time = 0.0
	player._skill_buffs.clear()
	GameManager.buff_move_speed_mult = 1.0
	# 摆到场地中心，四周留出足够空间，避免边界 clamp 吃掉滑行段
	player.global_position = Vector2.ZERO
	var dir := Vector2.DOWN
	if GameManager.joystick != null:
		GameManager.joystick.output = dir if hold else Vector2.ZERO
	# 摇杆推着时常速目标就在冲刺方向上；松手时目标是 0
	await get_tree().physics_frame
	await get_tree().physics_frame
	var st := SkillData.final_stats("dash", cid)
	var base := player.base_speed * (GameManager.move_speed_mult + GameManager.synergy_move_speed_mult)
	var before: Vector2 = player.global_position
	var peak := 0.0
	var dash_pos: Vector2 = before
	var landed: Vector2 = before
	var settle := -1
	var dash_seen := false
	var dash_ended := false
	player.skill_cd_left = 0.0
	_c.check(player.try_activate_skill(), "%s：冲刺释放成功（生产入口）" % (cid if not cid.is_empty() else "默认"))
	for i in range(300):
		await get_tree().physics_frame
		_dismiss()
		var spd: float = player.velocity.length()
		peak = maxf(peak, spd)
		if player._dash_time > 0.0:
			dash_seen = true
			dash_pos = player.global_position   # 冲刺段最后一帧的位置
		else:
			dash_ended = dash_seen
		landed = player.global_position
		if dash_ended and spd <= base * 1.05:
			settle = i
			break
	return {
		"nominal": float(st["distance"]),
		"in_dash": dash_pos.distance_to(before),
		"coast": landed.distance_to(dash_pos),
		"total": landed.distance_to(before),
		"peak": peak,
		"settle_frames": settle,
		"base": base,
	}

func _report(label: String, r: Dictionary) -> void:
	if r.is_empty():
		print("  [%s] 测量失败（无玩家）" % label)
		return
	var nominal: float = float(r["nominal"])
	var total: float = float(r["total"])
	print("  [%s] 纸面 %.0f ⇒ 冲刺段 %.0f + 滑行段 %.0f = 实际 %.0f px（纸面的 %.2f 倍，占屏高 %.0f%%）｜峰值 %.0f px/s（常速 %.0f 的 %.1f 倍）｜掉回常速 %d 帧 = %.2f s" % [
		label, nominal, float(r["in_dash"]), float(r["coast"]), total,
		total / maxf(1.0, nominal), total / 540.0 * 100.0,
		float(r["peak"]), float(r["base"]), float(r["peak"]) / maxf(1.0, float(r["base"])),
		int(r["settle_frames"]), int(r["settle_frames"]) / 60.0])

func _run() -> void:
	var main = load("res://scenes/main/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	_c.check(is_instance_valid(main), "主场景已进树")

	GameManager.cultivator_id = "jianchi"
	GameManager.pending_skill_id = "dash"
	GameManager.start_run("qingyun_sword")
	_dismiss()
	for i in range(12):
		await get_tree().process_frame
		_dismiss()
	var player: Player = GameManager.player
	_c.check(player != null, "玩家已生成")
	if player != null:
		# 别让沿途的伤害或加点打断测量
		player.max_health = 100000.0
		player.current_health = 100000.0
	var spawner: WaveSpawner = GameManager.wave_spawner
	_c.check(spawner != null and int(spawner.phase) == int(WaveSpawner.Phase.FIGHT), "已进入战斗阶段")
	print("  视口 960×540，场地半径 %.0f，常速 %.0f px/s，拾取圈 %.0f px" % [
		GameManager.MAP_HALF_EXTENT, player.base_speed, Player.BASE_PICKUP_RADIUS])

	var held := await _measure(main, true, "")
	var idle := await _measure(main, false, "")
	var meiying := await _measure(main, true, "meiying")
	_report("默认道统·摇杆推着不放", held)
	_report("默认道统·松手站着放", idle)
	_report("魅影 ×1.55·摇杆推着不放", meiying)

	for r in [held, idle]:
		if r.is_empty():
			continue
		_c.check(float(r["total"]) <= float(r["nominal"]) * 1.35,
			"实际位移 ≤ 纸面 1.35 倍（实测 %.2f 倍：纸面 %.0f / 实际 %.0f）" % [
				float(r["total"]) / maxf(1.0, float(r["nominal"])), float(r["nominal"]), float(r["total"])])

	if _c.report("DASH_TRAVEL_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)
