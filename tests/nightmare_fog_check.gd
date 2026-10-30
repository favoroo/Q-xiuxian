extends Node

## 噩梦迷雾可见性判据（2026-10-30 新增）：
##   ① 玩法闸：只有 danger_level >= 1 且在局内战斗时显示；普通难度（含读老档把难度洗回 D0）不显示
##   ② 全屏 UI：金币阁/悟道打开挂起、关闭恢复；暂停态下不许被自愈逻辑误点亮
##   ③ 阵亡：结算屏一弹立即收屏（结算屏会暂停整树，不能只等 _process 下一拍）
##   ④ 原地复活：清 is_game_over 后迷雾必须当天恢复 —— 不许缺到下一波（2026-10-30 用户反馈的根因）
##   ⑤ 接线口径：阵亡只走 _on_game_over 收屏，**不得**接进 _on_fullscreen_ui_opened 挂起表
## 运行: $G --headless --path . res://tests/NightmareFogCheck.tscn
## 退出码 0 且末行 NIGHTMARE_FOG_RESULT: ALL PASS

const MAIN_PATH := "res://scenes/main/Main.tscn"
const DEATH_TIMEOUT_FRAMES := 600

var _c := TestCheck.new()
var _fog: NightmareFogOverlay = null
var _spawner: WaveSpawner = null


func _ready() -> void:
	call_deferred("_run")


func _check(cond: bool, label: String) -> void:
	_c.check(cond, label)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _run() -> void:
	_c.set_min_checks(26)
	Engine.time_scale = 8.0
	GameManager.author_mode = true  # 不写生涯统计/成就，也不落中断档
	AuthorMode.god_mode = true      # 前半段只验迷雾闸，别被打死

	var main: Node = (load(MAIN_PATH) as PackedScene).instantiate()
	get_tree().root.add_child(main)
	await _frames(2)
	main.get_node("UILayer/StartMenu").visible = false
	var backdrop := main.get_node_or_null("UILayer/StageBackdrop") as Control
	if backdrop != null:
		backdrop.visible = false

	_fog = main.get_node_or_null("PostProcessLayer/NightmareFogOverlay") as NightmareFogOverlay
	_spawner = GameManager.wave_spawner as WaveSpawner
	_check(_fog != null, "主场景挂上了迷雾层")
	if _fog == null:
		_finish()
		return

	# 0. 接线口径
	_check(GameManager.shop_opened.is_connected(Callable(_fog, "_on_fullscreen_ui_opened")),
		"金币阁开启 → 迷雾挂起接线")
	_check(GameManager.alloc_opened.is_connected(Callable(_fog, "_on_fullscreen_ui_opened")),
		"悟道开启 → 迷雾挂起接线")
	_check(GameManager.shop_closed.is_connected(Callable(_fog, "_on_fullscreen_ui_closed")),
		"金币阁关闭 → 迷雾恢复接线")
	_check(GameManager.alloc_finished.is_connected(Callable(_fog, "_on_fullscreen_ui_closed")),
		"悟道关闭 → 迷雾恢复接线")
	_check(GameManager.game_over_triggered.is_connected(Callable(_fog, "_on_game_over")),
		"阵亡 → 迷雾收屏接线")
	_check(not GameManager.game_over_triggered.is_connected(Callable(_fog, "_on_fullscreen_ui_opened")),
		"阵亡不得进全屏挂起表（复活不发关闭信号，会把迷雾挂在下一波之前）")

	# 1. 开局：第 1 波才显示
	GameManager.career_stats["best_danger_cleared"] = 0
	GameManager.set_danger(1)
	GameManager.cultivator_id = "fuzhen"
	GameManager.start_run("qingyun_sword")
	get_tree().paused = false
	_check(not _fog.visible, "开局前（波次 0）不显示迷雾")
	_spawner.start_wave(1)
	await _frames(3)
	_check(GameManager.danger_level == 1, "本局难度为噩梦 D1")
	_check(_fog.visible, "噩梦第 1 波：迷雾生效")

	# 2. 难度闸：D0（含读老档把难度洗回 0）不显示；切回 D1 立刻恢复
	GameManager.danger_level = 0
	await _frames(2)
	_check(not _fog.visible, "普通难度 D0：迷雾不显示")
	GameManager.danger_level = 1
	await _frames(2)
	_check(_fog.visible, "切回噩梦 D1：迷雾立刻恢复")

	# 2b. 视野件加成：清晰圈/羽化圈同比例放大、指引半径随动、超顶夹回 +80%、清零复原
	var mat := _fog.material as ShaderMaterial
	GameManager.fog_vision_bonus = 0.4
	await _frames(2)
	_c.near(float(mat.get_shader_parameter("clear_ratio")), 280.0 / 540.0, 0.0015,
		"视野 +40%：清晰比例 280/540")
	_c.near(float(mat.get_shader_parameter("feather_ratio")), 399.0 / 540.0, 0.0015,
		"视野 +40%：羽化比例 399/540")
	_c.near(float(_fog._indicator_radius), 259.0, 0.5, "指引半径随清晰圈放大（280×0.925）")
	_c.near(float(_fog._far_threshold), 294.0, 0.5, "迷雾外判定随清晰圈放大（280×1.05）")
	GameManager.fog_vision_bonus = 2.0
	await _frames(2)
	_c.near(float(mat.get_shader_parameter("clear_ratio")), 360.0 / 540.0, 0.0015,
		"视野加成超顶夹回 +80%（360/540）")
	GameManager.fog_vision_bonus = 0.0
	await _frames(2)
	_c.near(float(mat.get_shader_parameter("clear_ratio")), 200.0 / 540.0, 0.0015,
		"视野加成清零：清晰圈回到基准 200/540")

	# 3. 全屏 UI 挂起/恢复 + 暂停态自愈守卫
	_fog._on_fullscreen_ui_opened()
	_check(not _fog.visible, "金币阁/悟道打开：迷雾收屏")
	get_tree().paused = true
	_fog._check_visibility()
	_check(not _fog.visible, "暂停态下不会被自愈误点亮")
	get_tree().paused = false
	_fog._on_fullscreen_ui_closed()
	_check(_fog.visible, "面板关闭：迷雾恢复")

	# 4. 阵亡 → 结算屏立即收屏（不靠 _process 下一拍，结算屏是暂停态）
	AuthorMode.god_mode = false
	GameManager.dodge = 0.0
	var player = GameManager.player
	if player != null and is_instance_valid(player):
		player.invulnerable_time = 0.0
		player.take_damage(999999.0, player.global_position + Vector2.RIGHT)
	await _wait_game_over()
	_check(GameManager.is_game_over, "致死一击后进入结算态")
	_check(not _fog.visible, "结算屏：迷雾立即收屏")

	# 5. 原地复活：迷雾当天恢复（回归点）
	var dlg: Control = main.get_node_or_null("UILayer/GameOverDialog") as Control
	_check(dlg != null, "结算屏已挂载")
	Engine.time_scale = 1.0
	if dlg != null:
		dlg._on_revive_pressed()
	await _wait_fog(true, 240)
	_check(not GameManager.is_game_over, "复活后退出结算态")
	_check(_fog.visible, "原地复活后迷雾当天恢复（未缺到下一波）")

	Engine.time_scale = 1.0
	GameManager.author_mode = false
	_finish()


func _wait_game_over() -> void:
	var frames := 0
	while not GameManager.is_game_over and frames < DEATH_TIMEOUT_FRAMES:
		await get_tree().process_frame
		frames += 1


func _wait_fog(want: bool, max_frames: int) -> void:
	var frames := 0
	while _fog != null and _fog.visible != want and frames < max_frames:
		await get_tree().process_frame
		frames += 1


func _finish() -> void:
	if not _c.report("NIGHTMARE_FOG_RESULT"):
		get_tree().quit(1)
	else:
		get_tree().quit(0)
