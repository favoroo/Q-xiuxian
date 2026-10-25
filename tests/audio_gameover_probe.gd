extends Node

## 阵亡音频探针（非判据，诊断用）：复刻「阵亡瞬间」的音频调用序列，监测混音是否变满幅失控。
## 运行（不加 --headless 也能复现，headless 更快）:
##   $G --headless --path . res://tests/AudioGameOverProbe.tscn -- --variant=N
## 背景：真机阵亡一刻起应用音轨 maxAmplitude 恒定 32768 持续 7 分钟（保护限幅后听感为死寂）；
## headless 复刻序列可稳定复现「混音峰值 2~6 倍满幅的失控振荡」。变体二分定位触发环节：
##   variant 0 = 完整序列（battle→boss 闷音→battle→阵亡：树暂停+defeat BGM 瞬切+defeat 音效）
##   variant 1 = 0 但不暂停树（排查 SceneTree.paused）
##   variant 2 = 0 但摘掉 BGM 总线低通（排查 AudioEffectLowPassFilter）
##   variant 3 = 0 但阵亡切 shop 曲（排查 defeat 素材频谱）
##   variant 4 = 0 但低通 cutoff 恒 22000（排查 Nyquist 边界系数退化）
## 判据：连续 3 个 1s 窗满幅样本占比 ≥50%。

var PHASES: Array = [
	{"name": "battle1", "dur": 6.0},
	{"name": "boss", "dur": 8.0},
	{"name": "battle2", "dur": 8.0},
	{"name": "gameover", "dur": 30.0},
]

var variant: int = 0
var cutoff_override: float = 0.0   ## >0 时把 CLEAR_CUTOFF 钉到该值
var muffle_enabled: bool = true    ## false 时 Boss 阶段不切闷音（静态 cutoff 行为）
var loop_mode: int = 0             ## >0 时跳过 boss/battle2，循环「战斗→阵亡瞬切」N 次
var _loop_left: int = 0
var _first_peg_dumped: bool = false
var _bus_captures: Dictionary = {}
var _phase_idx: int = 0
var _phase_t: float = 0.0
var _capture: AudioEffectCapture
var _capture_bus_fx_idx: int = -1
var _win_peak: float = 0.0
var _win_peg: int = 0
var _win_frames: int = 0
var _win_t: float = 0.0
var _pegged_streak: int = 0
var _events: Array[String] = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameManager.headless_guard_sec = 90.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--variant="):
			variant = int(a.split("=")[1])
		elif a.begins_with("--cutoff="):
			cutoff_override = float(a.split("=")[1])
		elif a == "--no-muffle":
			muffle_enabled = false
		elif a.begins_with("--loop="):
			loop_mode = int(a.split("=")[1])
	_rng.seed = 20261024
	_capture = AudioEffectCapture.new()
	AudioServer.add_bus_effect(0, _capture)
	_capture_bus_fx_idx = AudioServer.get_bus_effect_count(0) - 1
	# BGM / SFX 总线各挂一只 capture：Master 撞满幅时定位失控源自哪条总线
	_bus_captures = {}
	for bus_name in ["BGM", "SFX"]:
		var idx := AudioServer.get_bus_index(StringName(bus_name))
		if idx >= 0:
			var c := AudioEffectCapture.new()
			AudioServer.add_bus_effect(idx, c)
			_bus_captures[bus_name] = c
	if cutoff_override > 0.0 and AudioManager._bgm_lowpass != null:
		AudioManager._bgm_lowpass.cutoff_hz = cutoff_override
		print("[GO_PROBE] cutoff 钉在 %.0f" % cutoff_override)
	if loop_mode > 0:
		_loop_left = loop_mode
		# 循环模式：战斗 6s → 阵亡瞬切 10s → 解暂停回战斗 4s，往复；只走 battle1/gameover 两相
		PHASES.clear()
		PHASES.append({"name": "battle1", "dur": 6.0})
		PHASES.append({"name": "gameover", "dur": 10.0})
		PHASES.append({"name": "battle1", "dur": 4.0})
		print("[GO_PROBE] 循环模式 ×%d（battle→gameover 往复）" % loop_mode)
	match variant:
		2:
			if AudioManager._bgm_lowpass != null:
				var bgm_idx := AudioServer.get_bus_index(AudioManager.BUS_BGM)
				for i in range(AudioServer.get_bus_effect_count(bgm_idx)):
					if AudioServer.get_bus_effect(bgm_idx, i) == AudioManager._bgm_lowpass:
						AudioServer.remove_bus_effect(bgm_idx, i)
						print("[GO_PROBE] variant2: BGM 低通已摘除")
						break
		4:
			if AudioManager._bgm_lowpass != null:
				AudioManager._bgm_lowpass.cutoff_hz = 22000.0
				print("[GO_PROBE] variant4: 低通 cutoff 钉在 22000（避开 Nyquist 退化点）")
	AudioManager.play_bgm_key("battle")
	print("[GO_PROBE] start variant=%d" % variant)

func _enter_phase(name: String) -> void:
	match name:
		"boss":
			AudioManager.play_bgm_key("trial")
			if muffle_enabled:
				AudioManager.set_bgm_muffle(true)
			AudioManager.play_sfx("boss_raid", 0.9)
		"battle2":
			if muffle_enabled:
				AudioManager.set_bgm_muffle(false)
			AudioManager.play_bgm_key("battle")
		"gameover":
			if variant != 1:
				get_tree().paused = true
			var key := "defeat" if variant != 3 else "shop"
			AudioManager.play_bgm_key(key, true)
			var t := get_tree().create_timer(1.5, true, false, true)
			t.timeout.connect(func(): AudioManager.play_sfx("defeat"))
			print("[GO_PROBE] GAMEOVER at t=%.1f — paused=%s bgm=%s" % [_elapsed(), str(variant != 1), key])
		"battle1":
			if loop_mode > 0 and _phase_idx > 0:
				# 循环模式里 battle1 回归 = 上一轮阵亡结束，解暂停继续战斗
				get_tree().paused = false
				AudioManager.play_bgm_key("battle")
				_loop_left -= 1
				if _loop_left <= 0:
					# 最后一轮：battle1 打完就收尾
					PHASES.resize(3)
					print("[GO_PROBE] 循环结束，最后一轮战斗后收尾")

func _elapsed() -> float:
	var total: float = 0.0
	for i in range(_phase_idx):
		total += float(PHASES[i]["dur"])
	return total + _phase_t

func _process(delta: float) -> void:
	_phase_t += delta
	if _phase_idx < PHASES.size():
		if _phase_t >= float(PHASES[_phase_idx]["dur"]):
			_phase_idx += 1
			_phase_t = 0.0
			if _phase_idx < PHASES.size():
				_enter_phase(PHASES[_phase_idx]["name"])
		elif PHASES[_phase_idx]["name"].begins_with("battle") or PHASES[_phase_idx]["name"] == "boss":
			if _rng.randf() < 40.0 * delta:
				AudioManager.play_sfx("enemy_hit" if _rng.randf() < 0.7 else "enemy_death",
					_rng.randf_range(0.5, 1.15))

	var avail := _capture.get_frames_available()
	if avail > 0:
		var buf := _capture.get_buffer(avail)
		var peg_idx := -1
		for i in range(buf.size()):
			var f: Vector2 = buf[i]
			var m: float = maxf(absf(f.x), absf(f.y))
			if m > _win_peak:
				_win_peak = m
			if m >= 0.99:
				_win_peg += 1
				if peg_idx < 0:
					peg_idx = i
		if peg_idx >= 0 and not _first_peg_dumped:
			_first_peg_dumped = true
			_dump_peg_context(buf, peg_idx)
		_win_frames += avail
	_win_t += delta
	if _win_t >= 1.0:
		var phase: String = PHASES[mini(_phase_idx, PHASES.size() - 1)]["name"]
		var peg_ratio: float = float(_win_peg) / maxf(1.0, float(_win_frames))
		print("[GO_PROBE] t=%5.1f phase=%-8s peak=%.3f peg=%4.1f%% streak=%d" % [_elapsed(), phase, _win_peak, peg_ratio * 100.0, _pegged_streak])
		if peg_ratio >= 0.5:
			_pegged_streak += 1
			if _pegged_streak == 3:
				_events.append("FULL-SCALE t=%.1f phase=%s" % [_elapsed(), phase])
				print("[GO_PROBE] !!!! FULL-SCALE MIX DETECTED (variant=%d)" % variant)
				_dump_diag()
		else:
			_pegged_streak = 0
		_win_peak = 0.0
		_win_peg = 0
		_win_frames = 0
		_win_t = 0.0

	if _phase_idx >= PHASES.size() and _phase_t >= 5.0:
		_finish()

## Master 首次撞满幅的现场倾倒：满幅样本前后原始值、两条总线的实时峰值、各播放器当刻状态
func _dump_peg_context(buf: PackedVector2Array, peg_idx: int) -> void:
	print("  !!!! MASTER PEG @buf[%d/%d]:" % [peg_idx, buf.size()])
	var dump: Array = []
	for k in range(maxi(0, peg_idx - 4), mini(buf.size(), peg_idx + 8)):
		dump.append("[%d] %+.4f %+.4f" % [k, buf[k].x, buf[k].y])
	print("    " + " | ".join(dump))
	for bus_name in _bus_captures:
		var c: AudioEffectCapture = _bus_captures[bus_name]
		var n := c.get_frames_available()
		if n <= 0:
			print("    bus %-3s: 无新帧" % bus_name)
			continue
		var b := c.get_buffer(n)
		var peak := 0.0
		var peg_n := 0
		for f in b:
			var m: float = maxf(absf(f.x), absf(f.y))
			peak = maxf(peak, m)
			if m >= 0.99:
				peg_n += 1
		print("    bus %-3s: peak=%.4f peg_frames=%d/%d" % [bus_name, peak, peg_n, b.size()])
	for i in range(AudioManager.sfx_players.size()):
		var p: AudioStreamPlayer = AudioManager.sfx_players[i]
		if p.playing:
			print("    sfx[%d] stream=%s vol=%.2f pitch=%.3f" % [i,
				p.stream.resource_path.get_file() if p.stream != null else "<null>", p.volume_db, p.pitch_scale])
	for i in range(2):
		var bp: AudioStreamPlayer = AudioManager.bgm_players[i]
		print("    bgm[%d] playing=%s stream=%s vol=%.2f" % [i, bp.playing,
			bp.stream.resource_path.get_file() if bp.stream != null else "<null>", bp.volume_db])
	if AudioManager.ambience_player.playing:
		print("    ambience playing")

func _dump_diag() -> void:
	if AudioManager._bgm_lowpass != null:
		print("  lowpass cutoff=%.1f" % AudioManager._bgm_lowpass.cutoff_hz)
	else:
		print("  lowpass null")
	for i in range(2):
		var p: AudioStreamPlayer = AudioManager.bgm_players[i]
		print("  bgm[%d] playing=%s vol_db=%.2f stream=%s" % [i, p.playing, p.volume_db,
			p.stream.resource_path if p.stream != null else "<null>"])
	for bus_name in ["Master", "BGM", "SFX"]:
		var idx := AudioServer.get_bus_index(StringName(bus_name))
		print("  bus %s mute=%s vol=%.1f" % [bus_name, AudioServer.is_bus_mute(idx), AudioServer.get_bus_volume_db(idx)])

func _finish() -> void:
	get_tree().paused = false
	if _capture_bus_fx_idx >= 0:
		AudioServer.remove_bus_effect(0, _capture_bus_fx_idx)
	for bus_name in _bus_captures:
		var idx := AudioServer.get_bus_index(StringName(bus_name))
		var c: AudioEffectCapture = _bus_captures[bus_name]
		for i in range(AudioServer.get_bus_effect_count(idx)):
			if AudioServer.get_bus_effect(idx, i) == c:
				AudioServer.remove_bus_effect(idx, i)
				break
	if _events.is_empty():
		print("GO_PROBE_RESULT variant=%d: CLEAN (no full-scale window)" % variant)
	else:
		print("GO_PROBE_RESULT variant=%d: FULL-SCALE REPRODUCED — %s" % [variant, " | ".join(_events)])
	get_tree().quit()
