extends Node

## 真机画面抓拍工具（非判据）：实例化 Main.tscn 真跑一局，指定时刻截全视口 PNG。
## 用于环境氛围/地面/特效等「整屏观感」改动的视觉验收（headless 不出图，必须带窗口跑）。
## 运行: godot --path . res://tests/ToneCapture.tscn -- --wave 8 --wait 6 --out tests/inspect/tone_capture.png
## 注意：默认切 LDR 直出（见 tools/capture_ldr.gd）——桌面 HDR2D+ACES 会把画面压暗、把品红偏成
## 纯红，与手机真机不符；加 --hdr 可保留桌面 HDR 通道（仅排障用）。

const CaptureLdr = preload("res://tools/capture_ldr.gd")

var _wave := 8
var _wait := 6.0
var _out := "tests/inspect/tone_capture.png"
var _status := false   ## true 时抓拍前给全场敌人挂灼烧+剧毒+冰缓（验收五行异常体表视觉）
var _danger := 0       ## >0 时强置危险度（压测用，绕开解锁钳制）
var _keep_hdr := false ## true 时不切 LDR（保留桌面 HDR2D/ACES，仅供排障对照）

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		match String(args[i]):
			"--wave": _wave = int(String(args[i + 1]))
			"--wait": _wait = float(String(args[i + 1]))
			"--out": _out = String(args[i + 1])
			"--danger": _danger = int(String(args[i + 1]))
		if String(args[i]) == "--status":
			_status = true
		if String(args[i]) == "--hdr":
			_keep_hdr = true

	var main = load("res://scenes/main/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	# 抓拍关掉受击红闪通道（含低血量红晕脉冲），保证抓到常态基调
	SettingsManager.set_val(&"display", &"screen_flash", false)

	GameManager.cultivator_id = "jianchi"
	GameManager.start_run("qingyun_sword")
	get_tree().paused = false
	# 出图色彩校准：切 LDR 直出，避开桌面 HDR2D/ACES 的「压暗 + 品红偏纯红」（与手机真机一致）。
	if not _keep_hdr:
		CaptureLdr.apply(get_viewport(), main)
		await get_tree().process_frame
		await get_tree().process_frame
	if _danger > 0:
		GameManager.danger_level = _danger
	for w_id in ["wulei_paizi", "chiyan_dao", "huoyan_fu"]:
		GameManager.add_weapon(w_id, 3)
	_dismiss_dialogs()
	if _wave > 1:
		GameManager.wave_spawner.start_wave(_wave)
		await get_tree().create_timer(1.0).timeout
		_dismiss_dialogs()

	# 战斗推进到指定时刻，边等边清弹窗防暂停
	var start_ms := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - start_ms) / 1000.0 < _wait:
		await get_tree().create_timer(0.2).timeout
		_dismiss_dialogs()
		if _status:
			_apply_status_cycle()
		if _danger > 0 and GameManager.player != null and is_instance_valid(GameManager.player):
			# 压测模式锁血：深波高危险下 lvl1 角色秒躺，FIGHT 一结束探针就停采
			GameManager.player.max_health = 999999
			GameManager.player.current_health = 999999
	# 多等两帧让渲染管线（tonemap/glow/暗角）出全量画面
	# 抓拍前回满血并静候红闪/低血脉冲退场，保证抓到常态基调
	if GameManager.player != null and is_instance_valid(GameManager.player):
		GameManager.player.current_health = GameManager.player.max_health
	await get_tree().create_timer(0.8).timeout
	_dismiss_dialogs()
	await get_tree().process_frame
	await get_tree().process_frame

	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_out)
	print("TONE_CAPTURE out=%s err=%d enemies=%d wave=%d" % [_out, err,
		get_tree().get_nodes_in_group("enemies").size(), GameManager.wave_number])
	get_tree().quit(0 if err == OK else 1)

## 按序分三组各挂一系，同屏对照灼烧/剧毒/冰缓的体表粒子与染色（等待期循环调用覆盖新刷怪）
func _apply_status_cycle() -> void:
	var idx := 0
	for e in GameManager.live_enemies:
		if e != null and is_instance_valid(e) and not e.dying:
			match idx % 3:
				0: e.apply_burn(5.0, 3.0)
				1: e.apply_poison(5.0, 3.0)
				2: e.apply_chill(0.4, 3.0)
			idx += 1

func _dismiss_dialogs() -> void:
	for node_name in ["LevelUpDialog", "WaveShop", "PlayerStatsDialog", "PauseMenu", "SettingsDialog",
		"StartMenu", "SkillSelect", "StartWeaponSelect", "CultivatorSelect", "TutorialDialog", "StageBackdrop"]:
		var n := get_node_or_null("/root/Main/UILayer/" + node_name)
		if n != null and n.visible:
			n.visible = false
	get_tree().paused = false
