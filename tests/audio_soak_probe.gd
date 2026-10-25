extends Node

## 音频浸泡探针（非判据，诊断用）：模拟 13 波的音频负载曲线，监测引擎混音输出是否死亡。
## 运行（不加 --headless，需要真实音频驱动）:
##   $G --path . res://tests/AudioSoakProbe.tscn
## 背景：玩家实测在 ~13 波出现「BGM + 全部音效一起消失，偶尔冒一声又立刻断」。
## 本探针复刻该负载：
##   ① BGM 波次状态机（battle ↔ shop 交叉淡化，第 10 波 trial + Boss 闷音）
##   ② play_sfx 频率随波次线性爬升（4/s → ~100/s，按键权重近似群战构成）
##   ③ 13 波后追加主线程烧帧段（0→20ms/帧），区分「纯音频负载致死」与「主线程饥饿致死」
## 监测手段：Master 总线挂 AudioEffectCapture 读真实混音 RMS；每秒打印心跳行；
## 「应有声（BGM/音效在播）但混音 RMS 连续 ≥2.5s 为零」即判 AUDIO DEAD，打印完整诊断。

const WAVE_COUNT := 13          ## 模拟到第 13 波
const WAVE_DUR := 15.0          ## 每波战斗时长（秒）
const SHOP_DUR := 5.0           ## 波间商店时长（秒）
const RATE_BASE := 4.0          ## 第 1 波 play_sfx 频率（次/秒）
const RATE_PER_WAVE := 7.5      ## 每波频率增量（第 13 波 ≈ 102/s）
const BURN_RAMP_DUR := 60.0     ## 烧帧段：从 0 爬到 BURN_MAX 的时长
const BURN_MAX_MS := 20         ## 烧帧段：单帧主线程阻塞上限（毫秒）
const BURN_HOLD_DUR := 60.0     ## 烧帧段：满负荷保持时长
const SILENT_JUDGE_SEC := 2.5   ## 连续静音多少秒判死
const RMS_FLOOR := 1e-5         ## 混音 RMS 低于此值视为静（BGM -5dB 常态 rms ≈ 1e-2 量级）
const HEARTBEAT_SEC := 1.0      ## 心跳打印间隔

## 群战音效构成（权重近似后期割草：命中最多、死亡次之、敌攻与拾取零头）
const KEY_WEIGHTS := {
	"enemy_hit": 45.0,
	"enemy_death": 18.0,
	"whoosh_light": 8.0,
	"impact_blade": 6.0,
	"enemy_claw": 8.0,
	"enemy_bolt": 5.0,
	"gem_pickup": 6.0,
	"blade_shoot": 4.0,
}

var _t: float = 0.0
var _wave: int = 0
var _phase := "warmup"          ## warmup / fight / shop / burn_ramp / burn_hold
var _phase_t: float = 0.0
var _sfx_budget: float = 0.0
var _burn_ms: float = 0.0
var _weighted: Array = []
var _weight_total: float = 0.0
var _rng := RandomNumberGenerator.new()

# 监测状态
var _capture: AudioEffectCapture = null
var _window_sumsq: float = 0.0
var _window_frames: int = 0
var _window_t: float = 0.0
var _silent_sec: float = 0.0
var _dead_reported: bool = false
var _dead_events: Array[String] = []
var _dead_recoveries: int = 0
var _heartbeat_t: float = 0.0
var _peak_rate: int = 0
var _calls: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 20261024
	for k in KEY_WEIGHTS.keys():
		_weighted.append([k, KEY_WEIGHTS[k]])
		_weight_total += KEY_WEIGHTS[k]
	_capture = AudioEffectCapture.new()
	AudioServer.add_bus_effect(0, _capture)
	# 起手先让 BGM 响起来，等 1s 混音稳定再进入第 1 波
	AudioManager.play_bgm_key("battle")
	_enter("fight", 1)
	print("[AUDIO_SOAK] start")

func _enter(phase: String, wave: int = 0) -> void:
	_phase = phase
	_phase_t = 0.0
	if wave > 0:
		_wave = wave
	match phase:
		"fight":
			if _wave == 10:
				AudioManager.play_bgm_key("trial")
				AudioManager.set_bgm_muffle(true)
				AudioManager.play_sfx("boss_raid", 0.9)
			else:
				AudioManager.play_bgm_key("battle")
		"shop":
			if _wave == 10:
				AudioManager.set_bgm_muffle(false)
			AudioManager.play_bgm_key("shop")

func _pick_key() -> String:
	var roll := _rng.randf() * _weight_total
	for kv in _weighted:
		roll -= kv[1]
		if roll <= 0.0:
			return kv[0]
	return "enemy_hit"

func _process(delta: float) -> void:
	_t += delta
	_phase_t += delta

	# ---- 波次状态机 ----
	match _phase:
		"fight":
			_sfx_budget += (RATE_BASE + RATE_PER_WAVE * float(_wave)) * delta
			if _phase_t >= WAVE_DUR:
				_enter("shop")
		"shop":
			if _phase_t >= SHOP_DUR:
				if _wave < WAVE_COUNT:
					_enter("fight", _wave + 1)
				else:
					_enter("burn_ramp")
					print("[AUDIO_SOAK] all waves done, entering main-thread burn phase")
		"burn_ramp":
			_burn_ms = BURN_MAX_MS * clampf(_phase_t / BURN_RAMP_DUR, 0.0, 1.0)
			_sfx_budget += (RATE_BASE + RATE_PER_WAVE * float(WAVE_COUNT)) * delta
			if _phase_t >= BURN_RAMP_DUR:
				_enter("burn_hold")
		"burn_hold":
			_burn_ms = BURN_MAX_MS
			_sfx_budget += (RATE_BASE + RATE_PER_WAVE * float(WAVE_COUNT)) * delta
			if _phase_t >= BURN_HOLD_DUR:
				_finish()

	# ---- play_sfx 洪峰（每帧最多 40 发，防单帧整数秒积压失真）----
	var fired := 0
	while _sfx_budget >= 1.0 and fired < 40:
		AudioManager.play_sfx(_pick_key(), _rng.randf_range(0.5, 1.15))
		_sfx_budget -= 1.0
		fired += 1
		_calls += 1
	_peak_rate = maxi(_peak_rate, fired)

	# ---- 主线程烧帧（模拟大群战下的主线程帧耗时）----
	if _burn_ms > 0.0:
		var t0 := Time.get_ticks_usec()
		var target := int(_burn_ms * 1000.0)
		while Time.get_ticks_usec() - t0 < target:
			pass

	# ---- 混音监测 ----
	var avail := _capture.get_frames_available()
	if avail > 0:
		var buf := _capture.get_buffer(avail)
		for f in buf:
			_window_sumsq += f.x * f.x + f.y * f.y
		_window_frames += avail
	_window_t += delta
	if _window_t >= 0.25:
		var rms := 0.0
		if _window_frames > 0:
			rms = sqrt(_window_sumsq / float(_window_frames * 2))
		var expected := _expected_sound()
		if expected and rms < RMS_FLOOR:
			_silent_sec += _window_t
			if _silent_sec >= SILENT_JUDGE_SEC and not _dead_reported:
				_dead_reported = true
				_report_dead(rms)
		else:
			if _dead_reported and rms >= RMS_FLOOR:
				# 死过又活：正对「偶尔来一下」的样本
				_dead_recoveries += 1
				print("[AUDIO_SOAK] RECOVERED t=%.1f (dead→alive 转变 #%d)" % [_t, _dead_recoveries])
			_dead_reported = false
			_silent_sec = 0.0
		_window_sumsq = 0.0
		_window_frames = 0
		_window_t = 0.0

	# ---- 心跳 ----
	_heartbeat_t += delta
	if _heartbeat_t >= HEARTBEAT_SEC:
		_heartbeat_t = 0.0
		print("[AUDIO_SOAK] t=%5.1f wave=%2d phase=%-9s burn=%4.0fms fps=%3d bgm_playing=%d sfx_playing=%d calls=%d mute(M/B/S)=%s/%s/%s" % [
			_t, _wave, _phase, _burn_ms, Engine.get_frames_per_second(),
			_playing_count(AudioManager.bgm_players), _playing_count(AudioManager.sfx_players), _calls,
			AudioServer.is_bus_mute(0), AudioServer.is_bus_mute(AudioServer.get_bus_index(&"BGM")),
			AudioServer.is_bus_mute(AudioServer.get_bus_index(&"SFX")),
		])

func _expected_sound() -> bool:
	if _playing_count(AudioManager.bgm_players) > 0:
		return true
	return _playing_count(AudioManager.sfx_players) > 0

func _playing_count(players: Array) -> int:
	var n := 0
	for p in players:
		if p is AudioStreamPlayer and p.playing:
			n += 1
	return n

func _report_dead(rms: float) -> void:
	var line := "AUDIO DEAD t=%.1f wave=%d phase=%s rms=%.2e" % [_t, _wave, _phase, rms]
	_dead_events.append(line)
	print("[AUDIO_SOAK] !!!! " + line)
	# 完整诊断：总线与播放器逐个倾倒，供定位是哪一层先死
	for bus_name in ["Master", "BGM", "SFX", "Voice"]:
		var idx := AudioServer.get_bus_index(StringName(bus_name))
		if idx >= 0:
			print("  bus %-6s idx=%d mute=%s vol_db=%.1f effects=%d" % [
				bus_name, idx, AudioServer.is_bus_mute(idx), AudioServer.get_bus_volume_db(idx),
				AudioServer.get_bus_effect_count(idx)])
	for p in AudioManager.sfx_players:
		if p.playing:
			print("  sfx player playing stream=%s vol_db=%.2f pitch=%.3f" % [
				p.stream.resource_path if p.stream != null else "<null>", p.volume_db, p.pitch_scale])
	print("  capture: frames_in_buffer=%d" % _capture.get_frames_available())

func _finish() -> void:
	var master_fx_count := AudioServer.get_bus_effect_count(0)
	for i in range(master_fx_count):
		if AudioServer.get_bus_effect(0, i) == _capture:
			AudioServer.remove_bus_effect(0, i)
			break
	if _dead_events.is_empty():
		print("AUDIOSOAK_RESULT: ALL PASS (no audio death in %.0fs, peak_rate/frame=%d, calls=%d)" % [_t, _peak_rate, _calls])
	else:
		print("AUDIOSOAK_RESULT: AUDIO DEAD x%d, recoveries=%d — %s" % [
			_dead_events.size(), _dead_recoveries, " | ".join(_dead_events)])
	get_tree().quit()
