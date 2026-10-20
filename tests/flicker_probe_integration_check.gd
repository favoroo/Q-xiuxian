extends Node

## 闪屏探针「集成」判据（2026-10-20）：不测孤立实例，而是**真的把 Main.tscn 拉起来**，
## 验证探针在真实场景树里确实被挂上、能找到 HUD、开启设置后确实落盘。
## 为什么必须集成测：上一版探针单测全绿，但真机上「开了开关没记录」—— 单测用的是
## 自己 new 的探针 + 自己设的 current_scene，绕过了「探针是否真的挂在 GameHUD 下」
## 和「get_tree().current_scene 路径能否解析」这两处真实环境才暴露的问题。
##
## 运行: godot --headless --path . res://tests/FlickerProbeIntegrationCheck.tscn

const LOG_PATH := "user://flicker_log.csv"

var _c := TestCheck.new()

func _check(cond: bool, label: String) -> void:
	_c.check(cond, label)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	# 清旧日志
	if FileAccess.file_exists(LOG_PATH):
		DirAccess.open("user://").remove("flicker_log.csv")

	var main: Node = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	# 1. 探针是否真的挂在 UILayer/GameHUD 下
	var hud := main.get_node_or_null("UILayer/GameHUD")
	_check(hud != null, "Main 场景里 GameHUD 存在")
	var probe: Node = null
	if hud != null:
		for ch in hud.get_children():
			if ch is FlickerProbe:
				probe = ch
				break
	_check(probe != null, "FlickerProbe 已挂到 GameHUD 下（集成点①）")
	if probe == null:
		_finish()
		return

	# 2. 开启设置后应立刻建文件（不必等异常）
	SettingsManager.set_val(&"display", &"flicker_probe", true, false)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(FileAccess.file_exists(LOG_PATH), "开启后立刻创建日志文件（集成点②）")
	var content := ""
	if FileAccess.file_exists(LOG_PATH):
		content = FileAccess.get_file_as_string(LOG_PATH)
		_check(content.contains("frame,t_ms"), "文件含 CSV 表头")
		_check(content.contains("PROBE_STARTED"), "文件含 PROBE_STARTED 标记")

	# 3. 跑足够久，确认心跳/数据行会累积（证明 _process 真的在采样，且 _hud 解析成功）
	# 注意：心跳按**真实秒**计时（HEARTBEAT_SEC=2s），headless 的 process_frame 极快，
	# 光刷帧数不够 —— 必须等真实时间跨过心跳周期。这里等到 2.6s 保险。
	await get_tree().create_timer(FlickerProbe.HEARTBEAT_SEC + 0.6).timeout
	await get_tree().process_frame
	if FileAccess.file_exists(LOG_PATH):
		content = FileAccess.get_file_as_string(LOG_PATH)
	var lines := content.split("\n", false)
	# 表头 + PROBE_STARTED + 至少一条 HEARTBEAT（2s 心跳，140 帧 headless 下时间很短，
	# 但 warmup 30 帧后若 heartbeat_cd 累计够就写；这里主要验「有数据行」）
	var data_rows := 0
	for ln in lines:
		if not ln.begins_with("#") and not ln.begins_with("frame,"):
			data_rows += 1
	_check(data_rows >= 1, "运行若干帧后有数据行（证明 _process 在采样，实得 %d 行）" % data_rows)

	# 4. 跨场景重载不截断（2026-10-20 真机「只留下最后 3 行」的根因）：
	# 死亡重开/暂停重启都走 reload_current_scene，探针会在新场景里重新 _ready。
	# 用 FileAccess.WRITE 会把整份日志截断；必须改成 READ_WRITE 追加。
	var before_lines := content.count("\n")
	SettingsManager.set_val(&"display", &"flicker_probe", false, false)
	await get_tree().process_frame
	main.queue_free()
	await get_tree().process_frame
	# 重新起一个 Main（模拟场景重载），再开探针
	var main2: Node = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	add_child(main2)
	await get_tree().process_frame
	await get_tree().process_frame
	SettingsManager.set_val(&"display", &"flicker_probe", true, false)
	await get_tree().process_frame
	var after := FileAccess.get_file_as_string(LOG_PATH) if FileAccess.file_exists(LOG_PATH) else ""
	_check(after.count("\n") > before_lines,
		"重载后日志是追加而非截断（前 %d 行 → 后 %d 行）" % [before_lines, after.count("\n")])
	_check(after.count("frame,t_ms") == 1, "表头只写一次（不因重载重复插入）")

	# 收尾
	SettingsManager.set_val(&"display", &"flicker_probe", false, false)
	await get_tree().process_frame
	main2.queue_free()
	await get_tree().process_frame
	if FileAccess.file_exists(LOG_PATH):
		DirAccess.open("user://").remove("flicker_log.csv")
	_finish()

func _finish() -> void:
	if not _c.all_passed():
		print("FLICKER_INTEGRATION_RESULT: FAILED (%d failures)" % _c.failures.size())
		get_tree().quit(1)
	else:
		print("FLICKER_INTEGRATION_RESULT: ALL PASS (%d checks)" % _c.passed)
		get_tree().quit(0)
