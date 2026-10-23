extends Node

## 原地复活判据（2026-10-23 新增）：
##   1. 「轮回重生」落地为复活次数（字段链路由 UnitRunner 覆盖，这里验战斗链路）
##   2. 致死 → 死亡演出 → 结算屏：有次数时复活按钮可见、文案带剩余次数
##   3. 点复活：扣次数、血量回 50%、3 秒无敌、_dying/is_game_over/暂停全部复位
##   4. 次数用尽后再死：复活按钮不再出现
## 运行: godot --headless --path . res://tests/ReviveCheck.tscn
## 退出码 0 且末行 REVIVE_RESULT: ALL PASS
## 说明：本判据会让玩家真死一次，author_mode 置位以跳过生涯战报写入（不污染本地存档）。

const MAIN_PATH := "res://scenes/main/Main.tscn"
const DEATH_TIMEOUT_FRAMES := 600

var _c := TestCheck.new()

func _check(cond: bool, label: String) -> void:
	_c.check(cond, label)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	Engine.time_scale = 8.0
	GameManager.author_mode = true  # 不写生涯统计/成就
	var main = load(MAIN_PATH).instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	GameManager.cultivator_id = "fuzhen"
	GameManager.start_run("qingyun_sword")
	get_tree().paused = false
	await get_tree().physics_frame

	var player = GameManager.player
	var dlg = get_node_or_null("/root/Main/UILayer/GameOverDialog")
	_check(player != null, "玩家已就位")
	_check(dlg != null, "结算屏已挂载")
	if player == null or dlg == null:
		_finish()
		return

	# 1. 致死 → 结算屏（每局默认带 1 次复活）
	GameManager.dodge = 0.0
	_check(GameManager.revive_charges == 1, "开局默认带 1 次复活")
	_kill_player(player)
	await _wait_game_over()
	_check(GameManager.is_game_over, "致死一击后进入结算态")
	_check(dlg.visible, "结算屏已显示")
	_check(dlg._revive_btn.visible, "有复活次数时按钮可见")
	_check(String(dlg._revive_btn.text).find("剩 1 次") >= 0,
		"按钮文案带剩余次数（实际：%s）" % dlg._revive_btn.text)

	# 2. 点复活：解除结算 → 还魂仪式 → 半血 + 3 秒无敌
	Engine.time_scale = 1.0
	dlg._on_revive_pressed()
	_check(GameManager.revive_charges == 0, "复活次数已扣减")
	await get_tree().create_timer(1.7).timeout  # 退场淡出 0.2s + 还魂仪式 0.95s + 余量

	_check(not GameManager.is_game_over, "复活后退出结算态")
	_check(not get_tree().paused, "复活后解除整场暂停")
	_check(not dlg.visible, "结算屏已收起")
	_check(not player._dying, "阵亡演出状态已复位")
	_check(player.current_health > player.max_health * 0.45 and player.current_health <= player.max_health * 0.55,
		"血量恢复到 50%%（%.1f/%.1f）" % [player.current_health, player.max_health])
	_check(player.invulnerable_time > 2.0,
		"复活无敌约 3 秒（剩余 %.2fs）" % player.invulnerable_time)

	# 3. 次数用尽后再死：按钮不再出现
	player.invulnerable_time = 0.0
	_kill_player(player)
	await _wait_game_over()
	_check(GameManager.is_game_over, "二次致死进入结算态")
	_check(not dlg._revive_btn.visible, "次数用尽后复活按钮不再出现")

	GameManager.author_mode = false
	_finish()

func _kill_player(player) -> void:
	player.invulnerable_time = 0.0
	player.take_damage(999999.0, player.global_position + Vector2.RIGHT)

func _wait_game_over() -> void:
	var frames := 0
	while not GameManager.is_game_over and frames < DEATH_TIMEOUT_FRAMES:
		await get_tree().process_frame
		frames += 1

func _finish() -> void:
	if not _c.all_passed():
		print("REVIVE_RESULT: FAILED (%d failures) %s" % [_c.failures.size(), str(_c.failures)])
		get_tree().quit(1)
	else:
		print("REVIVE_RESULT: ALL PASS (%d checks)" % _c.passed)
		get_tree().quit(0)
