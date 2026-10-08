extends Node

## 临时诊断工具（非判据）：量「攻击期里镜头有多少时间在动」
## 运行: godot --headless --path . res://tests/ShakeProbe.tscn
## 只读不写存档，跑完打数就退；用完即删，不留进仓库。

const SAMPLE_SECONDS := 18.0
const MOVE_EPS := 0.5      ## 位移超过这个像素才算"看得出在动"

var _samples := 0
var _moving := 0
var _max_off := 0.0
var _peak_trauma := 0.0
var _grants := 0
var _last_trauma := 0.0
var _sum_off := 0.0

func _ready() -> void:
	set_physics_process(false)
	call_deferred("_run")

func _physics_process(_delta: float) -> void:
	var cam: Camera2D = GameManager.main_camera
	if cam == null or not (cam is SmoothCamera):
		return
	var sc := cam as SmoothCamera
	if sc.trauma > _last_trauma + 0.0005:
		_grants += 1
	_last_trauma = sc.trauma
	_peak_trauma = maxf(_peak_trauma, sc.trauma)
	var off: float = sc.offset.length()
	_samples += 1
	_sum_off += off
	_max_off = maxf(_max_off, off)
	if off > MOVE_EPS:
		_moving += 1

func _run() -> void:
	var main = load("res://scenes/main/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	GameManager.cultivator_id = "fuzhen"
	GameManager.start_run("qingyun_sword")
	get_tree().paused = false

	# 中后期火力：五件满级法器（含落雷 BURST、近战挥扫、弹道穿透、环绕法宝）
	for w_id in ["wulei_paizi", "chiyan_dao", "huoyan_fu", "lingdie", "bajiao_fan"]:
		GameManager.add_weapon(w_id, 3)
	GameManager.add_spirit_stones(999)
	_dismiss_dialogs()

	# 可指定波次跑一个"尸潮档"：--wave 12
	var args := OS.get_cmdline_user_args()
	var wave := 1
	for i in range(args.size() - 1):
		if String(args[i]) == "--wave":
			wave = int(String(args[i + 1]))
	if wave > 1:
		GameManager.wave_spawner.start_wave(wave)
		await get_tree().create_timer(1.0).timeout
		_dismiss_dialogs()

	set_physics_process(true)
	var start_ms := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - start_ms) / 1000.0 < SAMPLE_SECONDS:
		await get_tree().create_timer(0.2).timeout
		_dismiss_dialogs()   # 升级/商店弹窗会暂停整棵树，边等边清，否则采样会断
	set_physics_process(false)
	var real_seconds := float(Time.get_ticks_msec() - start_ms) / 1000.0

	var hits_per_sec := float(_grants) / maxf(0.001, real_seconds)
	print("SHAKE_PROBE seconds=%.1f samples=%d grants=%d grants_per_sec=%.1f" % [real_seconds, _samples, _grants, hits_per_sec])
	print("SHAKE_PROBE moving_frames=%d/%d (%.1f%%) avg_offset=%.2fpx max_offset=%.2fpx peak_trauma=%.2f" % [
		_moving, _samples, 100.0 * float(_moving) / maxf(1.0, float(_samples)),
		_sum_off / maxf(1.0, float(_samples)), _max_off, _peak_trauma])
	print("SHAKE_PROBE enemies=%d kills=%d wave=%d" % [
		get_tree().get_nodes_in_group("enemies").size(), GameManager.kills, GameManager.wave_number])
	get_tree().quit(0)

func _dismiss_dialogs() -> void:
	for node_name in ["LevelUpDialog", "WaveShop", "PlayerStatsDialog", "PauseMenu", "SettingsDialog"]:
		var n := get_node_or_null("/root/Main/UILayer/" + node_name)
		if n != null and n.visible:
			n.visible = false
	get_tree().paused = false
