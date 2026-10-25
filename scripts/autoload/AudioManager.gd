extends Node

## 全局音频管理：总线分层（Master/BGM/SFX/Voice）+ 16 通道并发池
## + 金币连续拾取音阶攀升（Combo Pitch Climbing）+ BGM 状态机交叉淡化 + 音量设置持久化
##
## 约定：音效 key 与短音效文件的对应关系只在这里声明；文件由 tools/bake_sfx.py 烘焙
## （assets_raw/sfx 是源，assets/audio/sfx 是产物）。注册了但文件不在的路径会记进
## _missing_paths，tests/UnitRunner 会断言它为空，避免「注册表和资源漂移」悄悄哑掉。

const SFX_PLAYER_COUNT := 16
const BUS_BGM := &"BGM"
const BUS_SFX := &"SFX"
const BUS_VOICE := &"Voice"

## BGM 状态机：按局内阶段切歌，同 key 重复调用不打断
const BGM_TABLE := {
	"menu": {"path": "res://assets/audio/bgm_menu.mp3", "db": -5.0},
	"battle": {"path": "res://assets/audio/bgm_cultivation.mp3", "db": -5.0},
	"shop": {"path": "res://assets/audio/bgm_shop.mp3", "db": -7.0},
	"trial": {"path": "res://assets/audio/bgm_trial.mp3", "db": -4.0},
	"victory": {"path": "res://assets/audio/bgm_victory.mp3", "db": -4.0},
	"defeat": {"path": "res://assets/audio/bgm_defeat.mp3", "db": -4.0},
}
const BGM_DEFAULT_KEY := "menu"

## 战场环境音（深渊罡风）：挂在 BGM 总线垫在配乐下面，随 BGM 音量条一起缩放；
## 不进 Voice 总线——那是角色语音专用，有独立音量设置。
## ogg 优先、wav 兜底（烘焙机有无 libvorbis 决定产物），素材缺席时静默不播，不进 _missing_paths。
const AMBIENCE_PATHS := ["res://assets/audio/ambience_wind.ogg", "res://assets/audio/ambience_wind.wav"]
const AMBIENCE_DB := -14.0
## 局内阶段才垫环境音：战斗/试炼/金币阁；菜单与胜负结算停掉
const AMBIENCE_KEYS := {"battle": true, "trial": true, "shop": true}

## Boss 战的 BGM 闷音（LowPass）：开场压闷制造紧张感，伏诛/转阶段即解除。
## 2026-10-24 满幅事故整改（根因链见 CHANGELOG）：引擎播放器流热换与音频线程有竞态，
## 偶发 NaN 样本会被低通的双二阶延迟寄存器永久捕获（与 cutoff 值无关；真机上满幅直流
## 被系统保护限幅成「全局没声音」，重启才恢复）。整改三件套：
## ① 常态旁路——非 Boss 期低通整体 bypass，链上没有有状态组件，NaN 至多一声咔哒；
## ② CLEAR 不再压 Nyquist（22050 恰把极点放上单位圆，18000 留足裕量）；
## ③ Master 挂 capture 看门狗，持续满幅 2s 即自愈重建并留 logcat 现场。
const MUFFLE_CUTOFF := 900.0
const CLEAR_CUTOFF := 18000.0
const SETTINGS_PATH := "user://audio.cfg"
const DEFAULT_LINEAR := {"BGM": 1.0, "SFX": 1.0, "Voice": 1.0}

var bgm_players: Array[AudioStreamPlayer] = []
var bgm_next: int = 0          ## 双 player 轮换，实现交叉淡化时不被「同一播放器换曲」打断
var bgm_key: StringName = &""
var bgm_tween: Tween = null
var ambience_player: AudioStreamPlayer = null
var _ambience_tween: Tween = null
var _bgm_lowpass: AudioEffectLowPassFilter = null
var _bgm_effect_idx: int = -1        ## 闷音低通在 BGM 总线上的效果槽位（旁路开关要用）
var _muffle_on: bool = false         ## 闷音意图态（解除补间途中效果器仍启用，不能拿总线态当意图态）
var _muffle_tween: Tween = null
var voice_player: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []
var next_sfx_idx: int = 0

var sfx_dict: Dictionary = {}
var _missing_paths: Array[String] = []
var _linear: Dictionary = {}

# 金币拾取连击升调状态
var _gem_combo_count: int = 0
var _gem_combo_timer: float = 0.0

# 命中连击升调状态（2026-10-11）：短时间内连续命中音高缓步攀升，听觉上卖「越砍越顺」
var _hit_combo_count: int = 0
var _hit_combo_timer: float = 0.0

# 击杀连击升调状态（2026-10-15）：连杀窗内死亡音音高步步抬升；续窗计时直接读
# GameManager.frenzy_idle（距上次击杀秒数，击杀时归零），不另立一套计时器
const KILL_COMBO_WINDOW := 2.0   ## 连杀续窗：2 秒内再杀一层不断（幸存者类击杀节奏比命中稀）
const KILL_COMBO_MAX := 12       ## 阶梯封顶层数
const KILL_COMBO_STEP := 0.035   ## 每层音高步进
var _kill_combo_count: int = 0
var _kill_pitch_base: float = 1.0

## 高频音效同 key 最小间隔（毫秒）：群战同帧几十次命中/死亡时防「糊成一片+通道瞬间耗尽」。
## 只对战斗高频音生效，UI/阶段音不受限。未列出的 key 不节流。
const SFX_GAP_MS := {
	"enemy_hit": 18,
	"enemy_hit_heavy": 18,
	"enemy_hit_crit": 40,
	"player_hurt": 120,
	"enemy_death": 30,
	"enemy_death_elite": 60,
	"blade_shoot": 25,
	"talisman_throw": 25,
	"thunder_strike": 40,
	"fan_gust": 35,
	"orb_hit": 50,
	# 器型族。取值原则：① 同族两把武器同帧齐射要合并成一声（防糊）
	# ② 必须小于该族最快那把武器在极限攻速下的触发间隔（防吞音）
	# ③ 双层同 key 的族（鼓/笛）必须小于「施法 → 落点」那约 200ms，否则落点被自己吞掉
	"whoosh_light": 70,
	"whoosh_heavy": 70,
	"impact_blade": 40,
	"impact_blunt": 40,
	"impact_crack": 40,
	"metal_dart": 30,
	"flame_jet": 120,     ## 火葫芦 cd 0.42，极限攻速约 0.30s
	"drum_boom": 60,      ## 鼓的两层同 key，间隔约 200ms
	"flute_wave": 120,    ## 笛同上，120 < 200 才留得住落点那一记
	"drone_flutter": 50,
	"drone_chime": 50,
	# 敌人侧：群狼齐咬/群邪修齐射要合并成「一波攻势」而不是弹雨般几十声
	"enemy_claw": 60,
	"enemy_bolt": 50,
	"enemy_fuse": 100,     ## 引信本身 0.3s 长嘶，间隔太小会把一条嘶鸣切成碎片
	"enemy_slam": 150,
	"enemy_blink": 80,
	"enemy_poison": 120,   ## 投毒是周期技（数秒一发），同族同帧齐射合并成一声落地
	"gem_pickup": 25,
	"chest_hit": 30,
	"ui_click": 30,
	"dodge": 80,
}
var _last_sfx_ms: Dictionary = {}

# ---------------- 满幅自愈看门狗（2026-10-24）----------------
# 引擎播放器流热换与音频线程的竞态偶发 NaN 样本，一旦被有状态组件（低通寄存器/变采样器）
# 捕获就持续满幅输出——真机上被系统保护限幅成「全局没声音」，重启才恢复。整改①②已把
# 常态链上的有状态组件清空，这里是兜底：Master 挂 capture 量实际混音，连续 2 个 1s 窗
# 有 ≥50% 样本钉在满幅（正常混音瞬态削波只有零星几帧，永到不了 50%）即判管线死亡，
# 重建低通 + 全播放器停稳复播，把「永远没声音」降级为一声咔哒 + 一条 logcat 现场。
const WATCHDOG_WINDOW_SEC := 1.0
const WATCHDOG_TRIGGER_WINDOWS := 2
const WATCHDOG_PEG_RATIO := 0.5
const WATCHDOG_COOLDOWN_SEC := 20.0
var _watch_capture: AudioEffectCapture = null
var _watch_effect_idx: int = -1
var _watch_win_t: float = 0.0
var _watch_peg: int = 0
var _watch_frames: int = 0
var _watch_streak: int = 0
var _watch_cooldown: float = 0.0
var _watch_recoveries: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# 交叉淡化需要两个播放器：一个淡出旧的，一个淡入新的
	for i in range(2):
		var p := AudioStreamPlayer.new()
		p.bus = BUS_BGM
		add_child(p)
		bgm_players.append(p)

	voice_player = AudioStreamPlayer.new()
	voice_player.bus = BUS_VOICE
	add_child(voice_player)

	# 环境音与 SFX 资源改为懒加载（2026-10-21 启动卡顿专项）：原先在 _ready 同步 load
	# 111 个 wav + 2.1MB ambience，全压引擎启动阻塞段。现在推迟到首帧后（call_deferred），
	# 且任何首次使用（play_sfx / has_sfx / missing_paths / sfx_keys / 环境音同步）都会先
	# _ensure_audio_loaded() 兜底，单测与音频试听台照常取到完整注册表。
	ambience_player = AudioStreamPlayer.new()
	ambience_player.bus = BUS_BGM
	add_child(ambience_player)

	# Boss 闷音效果器常驻 BGM 总线但常态旁路（set_bgm_muffle 负责启停旁路）：
	# 2026-10-24 起不再让双二阶常挂链上——它是有状态组件，引擎偶发的 NaN 样本
	# 一旦进它的延迟寄存器就永久满幅（真机听感=全局没声音）。旁路态不参与混音，无此风险。
	var bgm_idx := AudioServer.get_bus_index(BUS_BGM)
	if bgm_idx >= 0:
		_bgm_lowpass = AudioEffectLowPassFilter.new()
		_bgm_lowpass.cutoff_hz = CLEAR_CUTOFF
		AudioServer.add_bus_effect(bgm_idx, _bgm_lowpass)
		_bgm_effect_idx = AudioServer.get_bus_effect_count(bgm_idx) - 1
		AudioServer.set_bus_effect_enabled(bgm_idx, _bgm_effect_idx, false)

	for i in range(SFX_PLAYER_COUNT):
		var p := AudioStreamPlayer.new()
		p.bus = BUS_SFX
		add_child(p)
		sfx_players.append(p)

	# 满幅看门狗的采集口（被动旁挂，不影响声音）
	_watch_capture = AudioEffectCapture.new()
	AudioServer.add_bus_effect(0, _watch_capture)
	_watch_effect_idx = AudioServer.get_bus_effect_count(0) - 1

	call_deferred("_ensure_audio_loaded")
	_load_settings()

var _audio_loaded: bool = false

## 懒加载音频资源（幂等）。首帧后由 call_deferred 触发；任何取用处也会先调它兜底。
func _ensure_audio_loaded() -> void:
	if _audio_loaded:
		return
	_audio_loaded = true
	# 环境音：循环 player，播不播由 play_bgm_key 的阶段 key 决定
	for p in AMBIENCE_PATHS:
		if ResourceLoader.exists(p):
			var s = load(p) as AudioStream
			if s is AudioStreamWAV:
				s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			elif s != null and "loop" in s:
				s.loop = true
			ambience_player.stream = s
			break
	_load_audio_assets()

func _process(delta: float) -> void:
	if _gem_combo_timer > 0.0:
		_gem_combo_timer -= delta
		if _gem_combo_timer <= 0.0:
			_gem_combo_count = 0
	if _hit_combo_timer > 0.0:
		_hit_combo_timer -= delta
		if _hit_combo_timer <= 0.0:
			_hit_combo_count = 0
		# 击杀连击断窗兜底：register_kill_pitch 只在击杀时被调，开火间隙里把层数清零，
		# 否则隔半分钟再杀一只会沿用旧阶梯高位（frenzy_idle 在游戏中才累计，菜单不涨）
		if GameManager != null and GameManager.frenzy_idle >= KILL_COMBO_WINDOW and _kill_combo_count != 0:
			_kill_combo_count = 0
	_tick_watchdog(delta)

## 满幅看门狗：统计 Master 实际混音里钉在 |样本|≥0.99 的占比，持续过半即自愈
func _tick_watchdog(delta: float) -> void:
	if _watch_capture == null:
		return
	_watch_cooldown = maxf(0.0, _watch_cooldown - delta)
	var wavail := _watch_capture.get_frames_available()
	if wavail > 0:
		var buf := _watch_capture.get_buffer(wavail)
		for f in buf:
			if absf(f.x) >= 0.99 or absf(f.y) >= 0.99:
				_watch_peg += 1
		_watch_frames += wavail
	_watch_win_t += delta
	if _watch_win_t < WATCHDOG_WINDOW_SEC:
		return
	var pegged: bool = _watch_frames > 0 \
		and float(_watch_peg) / float(_watch_frames) >= WATCHDOG_PEG_RATIO
	_watch_win_t = 0.0
	_watch_peg = 0
	_watch_frames = 0
	if not pegged:
		_watch_streak = 0
		return
	_watch_streak += 1
	if _watch_streak >= WATCHDOG_TRIGGER_WINDOWS and _watch_cooldown <= 0.0:
		_watch_streak = 0
		_recover_audio_pipeline()
		_watch_cooldown = WATCHDOG_COOLDOWN_SEC

## 管线自愈：闷音低通整器重建（清 NaN 寄存器）+ 全播放器停稳后重起 BGM/环境音
func _recover_audio_pipeline() -> void:
	_watch_recoveries += 1
	push_warning("AudioManager: 满幅混音自愈 #%d（连续 %d 窗 ≥%d%% 样本钉满幅）——重建低通并复播 BGM" % [
		_watch_recoveries, WATCHDOG_TRIGGER_WINDOWS, int(WATCHDOG_PEG_RATIO * 100)])
	# 1) 低通整器重建：旁路态下这步基本是空操作，闷音中触发则保持闷音并清干净寄存器
	var bgm_idx := AudioServer.get_bus_index(BUS_BGM)
	if bgm_idx >= 0 and _bgm_effect_idx >= 0:
		var was_enabled: bool = AudioServer.is_bus_effect_enabled(bgm_idx, _bgm_effect_idx)
		var was_muffled: bool = _bgm_lowpass != null and _bgm_lowpass.cutoff_hz <= MUFFLE_CUTOFF + 100.0
		if _muffle_tween != null and _muffle_tween.is_valid():
			_muffle_tween.kill()
		AudioServer.remove_bus_effect(bgm_idx, _bgm_effect_idx)
		_bgm_lowpass = AudioEffectLowPassFilter.new()
		_bgm_lowpass.cutoff_hz = MUFFLE_CUTOFF if (was_enabled and was_muffled) else CLEAR_CUTOFF
		AudioServer.add_bus_effect(bgm_idx, _bgm_lowpass)
		_bgm_effect_idx = AudioServer.get_bus_effect_count(bgm_idx) - 1
		AudioServer.set_bus_effect_enabled(bgm_idx, _bgm_effect_idx, was_enabled and was_muffled)
		_muffle_on = was_enabled and was_muffled
	# 2) 播放器全停稳（掐断变采样器/解码器的驻留态）再瞬时复播当前 BGM 与环境音
	for p in sfx_players:
		if p.playing:
			p.stop()
	if voice_player != null and voice_player.playing:
		voice_player.stop()
	var cur_key := String(bgm_key)
	if ambience_player != null and ambience_player.playing:
		ambience_player.stop()
	for bp in bgm_players:
		bp.stop()
	bgm_key = &""
	if cur_key != "":
		# play_bgm_key 首播路径直接全音量起奏；环境音由其内部 _sync_ambience 淡入接手
		play_bgm_key(cur_key, true)
# ---------------- 音效注册表 ----------------

func _load_audio_assets() -> void:
	# 全部由 tools/bake_sfx.py 烘焙（同 key 多变体随机播 + 播放时抖音高）
	_register_sfx("enemy_hit", _sfx_paths("enemy_hit", 3))
	_register_sfx("enemy_hit_crit", _sfx_paths("enemy_hit_crit", 3))
	_register_sfx("enemy_hit_heavy", _sfx_paths("enemy_hit_heavy", 3))
	_register_sfx("player_hurt", _sfx_paths("player_hurt", 3))
	_register_sfx("enemy_death", _sfx_paths("enemy_death", 3))
	_register_sfx("enemy_death_elite", _sfx_paths("enemy_death_elite", 2))
	_register_sfx("blade_shoot", _sfx_paths("blade_shoot", 2))
	_register_sfx("talisman_throw", _sfx_paths("talisman_throw", 2))
	_register_sfx("thunder_strike", _sfx_paths("thunder_strike", 2))
	_register_sfx("fan_gust", _sfx_paths("fan_gust", 2))
	_register_sfx("orb_hit", _sfx_paths("orb_hit", 2))
	# 器型族（近战双层：前摇 whoosh + 命中 impact；雷法双层：施法 sfx + 落点 sfx_impact）
	_register_sfx("whoosh_light", _sfx_paths("whoosh_light", 2))
	_register_sfx("whoosh_heavy", _sfx_paths("whoosh_heavy", 2))
	_register_sfx("impact_blade", _sfx_paths("impact_blade", 3))
	_register_sfx("impact_blunt", _sfx_paths("impact_blunt", 2))
	_register_sfx("impact_crack", _sfx_paths("impact_crack", 2))
	_register_sfx("metal_dart", _sfx_paths("metal_dart", 2))
	_register_sfx("flame_jet", _sfx_paths("flame_jet", 2))
	_register_sfx("drum_boom", _sfx_paths("drum_boom", 2))
	_register_sfx("flute_wave", _sfx_paths("flute_wave", 2))
	_register_sfx("drone_flutter", _sfx_paths("drone_flutter", 2))
	_register_sfx("drone_chime", _sfx_paths("drone_chime", 2))
	# 敌人专属族：敌我分源，不再借用玩家的挥砍/开火/闪避音
	_register_sfx("enemy_claw", _sfx_paths("enemy_claw", 3))
	_register_sfx("enemy_bolt", _sfx_paths("enemy_bolt", 2))
	_register_sfx("enemy_fuse", _sfx_paths("enemy_fuse", 2))
	_register_sfx("enemy_slam", _sfx_paths("enemy_slam", 2))
	_register_sfx("enemy_blink", _sfx_paths("enemy_blink", 2))
	_register_sfx("enemy_poison", _sfx_paths("enemy_poison", 2))
	_register_sfx("gem_pickup", _sfx_paths("gem_pickup", 2))
	_register_sfx("chest_hit", _sfx_paths("chest_hit", 2))
	_register_sfx("chest_open", _sfx_paths("chest_open", 2))
	_register_sfx("shop_buy", _sfx_paths("shop_buy", 2))
	_register_sfx("shop_reroll", _sfx_paths("shop_reroll", 2))
	_register_sfx("shop_lock", _sfx_paths("shop_lock", 1))
	_register_sfx("sell", _sfx_paths("sell", 1))
	_register_sfx("equip", _sfx_paths("equip", 2))
	_register_sfx("unequip", _sfx_paths("unequip", 1))
	_register_sfx("merge_success", _sfx_paths("merge_success", 2))
	_register_sfx("weapon_awaken", _sfx_paths("weapon_awaken", 2))
	_register_sfx("merge_charge", _sfx_paths("merge_charge", 2))
	_register_sfx("ui_click", _sfx_paths("ui_click", 3))
	_register_sfx("ui_confirm", _sfx_paths("ui_confirm", 2))
	_register_sfx("ui_back", _sfx_paths("ui_back", 1))
	_register_sfx("ui_error", _sfx_paths("ui_error", 2))
	_register_sfx("stat_alloc", _sfx_paths("stat_alloc", 2))
	_register_sfx("wave_start", _sfx_paths("wave_start", 1))
	_register_sfx("wave_clear", _sfx_paths("wave_clear", 1))
	_register_sfx("boss_raid", _sfx_paths("boss_raid", 1))
	_register_sfx("dodge", _sfx_paths("dodge", 2))
	_register_sfx("heal", _sfx_paths("heal", 2))
	_register_sfx("victory", _sfx_paths("victory", 1))
	_register_sfx("defeat", _sfx_paths("defeat", 1))
	_register_sfx("obelisk_blessing", _sfx_paths("obelisk_blessing", 2))
	_register_sfx("level_up", _sfx_paths("level_up", 2))
	# 随行技能
	_register_sfx("skill_dash", _sfx_paths("skill_dash", 2))
	_register_sfx("skill_buff", _sfx_paths("skill_buff", 2))
	_register_sfx("skill_aegis", _sfx_paths("skill_aegis", 2))
	_register_sfx("skill_heal", _sfx_paths("skill_heal", 2))

## 音效文件名规律：<key>_<序号>.wav，wav 与 ogg 两种产物都能认
static func _sfx_paths(name: String, count: int) -> Array:
	var out: Array = []
	for i in range(1, count + 1):
		var wav := "res://assets/audio/sfx/%s_%d.wav" % [name, i]
		if ResourceLoader.exists(wav):
			out.append(wav)
		else:
			out.append("res://assets/audio/sfx/%s_%d.ogg" % [name, i])
	return out

func _register_sfx(sfx_key: String, paths: Array) -> void:
	var streams: Array[AudioStream] = []
	for p in paths:
		if ResourceLoader.exists(p):
			var st = load(p) as AudioStream
			if st != null:
				streams.append(st)
			else:
				_missing_paths.append(p)
		else:
			_missing_paths.append(p)
	if not streams.is_empty():
		sfx_dict[sfx_key] = streams

## 注册了但加载不到的路径（单测断言用；空数组 = 注册表与素材一致）
func missing_paths() -> Array:
	if not _audio_loaded:
		_ensure_audio_loaded()
	return _missing_paths

func has_sfx(key: String) -> bool:
	if not _audio_loaded:
		_ensure_audio_loaded()
	return sfx_dict.has(key)

## 已注册且素材可用的音效 key 列表（试听台/调试用）
func sfx_keys() -> Array:
	if not _audio_loaded:
		_ensure_audio_loaded()
	return sfx_dict.keys()

# ---------------- 判据录音口 ----------------
## 只在 tests/ 的判据场景里显式开启；不开启时 play_sfx 一行分支都不多走。
## 捕获态不进播放器池、不查节流表、不消耗金币连击状态 —— 量的是"想播什么"，不是"播出什么"。

var _capturing: bool = false
var _captured: Array[Dictionary] = []

func begin_sfx_capture() -> void:
	_capturing = true
	_captured.clear()

## 取走捕获序列并关闭捕获态
func end_sfx_capture() -> Array[Dictionary]:
	_capturing = false
	return _captured

# ---------------- 播放 ----------------

func play_sfx(sfx_key: String, volume_scale: float = 1.0, pitch_override: float = 0.0) -> void:
	# 判据录音口：headless 不出声，但「这次攻击实际播了哪个 key」必须量得到。
	# 放在未注册检查之前 —— 调用点写了哑 key 这类事故（历史上真出过 play_sfx("powerUp2")）
	# 只有在这里才留得下痕迹；被节流吞掉的调用同样记录，判据量的才是真实意图。
	if _capturing:
		_captured.append({"key": sfx_key, "scale": volume_scale, "registered": sfx_dict.has(sfx_key)})
		return

	if not _audio_loaded:
		_ensure_audio_loaded()

	if not sfx_dict.has(sfx_key):
		push_warning("AudioManager: 未注册的音效 key 「%s」" % sfx_key)
		return

	# 高频音效同 key 短窗节流：防群战同帧命中爆音与通道瞬间耗尽
	var gap_ms: int = int(SFX_GAP_MS.get(sfx_key, 0))
	if gap_ms > 0:
		var now_ms := Time.get_ticks_msec()
		if now_ms - int(_last_sfx_ms.get(sfx_key, -1000000)) < gap_ms:
			return
		_last_sfx_ms[sfx_key] = now_ms

	var streams: Array = sfx_dict[sfx_key]
	var stream = streams.pick_random()
	var p = sfx_players[next_sfx_idx]
	next_sfx_idx = (next_sfx_idx + 1) % sfx_players.size()

	p.stream = stream
	p.volume_db = linear_to_db(clampf(volume_scale, 0.05, 2.5))

	if pitch_override > 0.0:
		p.pitch_scale = pitch_override
	elif sfx_key == "gem_pickup":
		# 金币连收音阶递进：短时间内连续拾取音高步步攀升，营造清脆爽感
		_gem_combo_count = mini(_gem_combo_count + 1, 16)
		_gem_combo_timer = 0.6
		p.pitch_scale = 0.94 + float(_gem_combo_count - 1) * 0.042
	elif sfx_key == "enemy_death" or sfx_key == "enemy_death_elite":
		p.pitch_scale = _kill_combo_pitch()
	else:
		p.pitch_scale = randf_range(0.92, 1.08)

	# 命中连击升调：0.6s 连击窗内每次命中音高 +3%（封顶 8 层），叠在调用方基准音高之上
	if sfx_key == "enemy_hit":
		_hit_combo_count = mini(_hit_combo_count + 1, 8)
		_hit_combo_timer = 0.6
		p.pitch_scale *= 1.0 + float(_hit_combo_count - 1) * 0.03

	p.play()

## 击杀连击音阶：2 秒续窗内连续击杀，死亡音音高沿 kill_pitch_base（敌种个性基准）步步抬升。
func _kill_combo_pitch() -> float:
	return clampf(_kill_pitch_base, 0.6, 1.6) * (1.0 + float(_kill_combo_count - 1) * KILL_COMBO_STEP)

## 击杀方（EnemyBase）在播死亡音前登记本命音高基准并推阶梯：
## 续窗判断在这里做（读 GameManager.frenzy_idle，与狂战士战意同一把击杀计时尺），
## 音高换算在 _kill_combo_pitch。
func register_kill_pitch(base: float) -> void:
	_kill_pitch_base = base
	if GameManager.frenzy_idle < KILL_COMBO_WINDOW:
		_kill_combo_count = mini(_kill_combo_count + 1, KILL_COMBO_MAX)
	else:
		_kill_combo_count = 1

func play_voice(stream: AudioStream) -> void:
	if stream:
		voice_player.stream = stream
		voice_player.play()

# ---------------- BGM 状态机 ----------------

## 按阶段 key 播 BGM：menu / battle / shop / trial / victory / defeat。同 key 正在播则什么都不做。
## instant: 为 true 或胜负结算 key 时直接以全音量瞬时起奏（0.1s 极速过渡），避免结算界面静音迟滞。
## 素材还没就位时保持现状，不报错刷屏。
func play_bgm_key(key: String, instant: bool = false) -> void:
	if key == "" or key == String(bgm_key):
		return
	# 转阶段一律解除 Boss 闷音（伏诛/战败/回合结束都会走到这里）
	set_bgm_muffle(false)
	var info: Dictionary = BGM_TABLE.get(key, {})
	var path: String = info.get("path", "")
	if path == "" or not ResourceLoader.exists(path):
		return
	var stream = load(path) as AudioStream
	if stream == null:
		return
	if stream is AudioStreamMP3:
		stream.loop = true
	elif stream is AudioStreamOggVorbis:
		stream.loop = true

	var target_db: float = float(info.get("db", -5.0))
	# 不变式：bgm_next 始终指向「当前正在播」的那个 player
	var active: AudioStreamPlayer = bgm_players[bgm_next]

	# 胜负结算场景强制瞬时起奏，第一帧声音就要轰出来
	var is_instant: bool = instant or key == "victory" or key == "defeat"

	# 首次播放（还没有任何 BGM 在响）：直接起，不做淡化
	if bgm_key == &"":
		active.stream = stream
		active.volume_db = target_db
		active.play()
		bgm_key = StringName(key)
		_sync_ambience(key)
		return

	# 交叉淡化：新的从空闲 player 载入播放，旧的同步停掉/淡出
	var idle_idx := 1 - bgm_next
	var idle: AudioStreamPlayer = bgm_players[idle_idx]
	# 竞态加固（2026-10-24）：上一轮淡出的 stop 回调若被 tween.kill() 取消，idle 会带着
	# 旧流残留在播——在播状态下换流正是引擎偶发 NaN 样本的窗口，先显式停稳再换。
	if idle.playing:
		idle.stop()
	idle.stream = stream

	if bgm_tween != null and bgm_tween.is_valid():
		bgm_tween.kill()
		# 被砍掉的旧淡出补一枪 stop：残响玩家会让下一次交叉淡化多占一个声部
		if active.playing and not is_instant:
			active.stop()

	if is_instant:
		# 极速瞬时切换：新曲直接全音量起，旧曲 0.1s 迅速收尾
		idle.volume_db = target_db
		idle.play()
		bgm_tween = create_tween().set_parallel(true)
		bgm_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		bgm_tween.tween_property(active, "volume_db", active.volume_db - 35.0, 0.1)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		bgm_tween.chain().tween_callback(active.stop)
	else:
		# 平滑交叉淡化：新曲从 -40dB 0.6s 淡入，旧曲同步 0.6s 淡出
		idle.volume_db = target_db - 40.0
		idle.play()
		bgm_tween = create_tween().set_parallel(true)
		bgm_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		bgm_tween.tween_property(idle, "volume_db", target_db, 0.6)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		bgm_tween.tween_property(active, "volume_db", active.volume_db - 30.0, 0.6)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		bgm_tween.chain().tween_callback(active.stop)

	bgm_key = StringName(key)
	bgm_next = idle_idx
	_sync_ambience(key)

## 环境音随阶段启停：局内（战斗/试炼/金币阁）淡入垫底，菜单/结算淡出。
## 与 BGM 共用总线，玩家拉 BGM 音量条时环境音同步缩放，不新增设置项。
func _sync_ambience(key: String) -> void:
	if not _audio_loaded:
		_ensure_audio_loaded()
	if ambience_player == null or ambience_player.stream == null:
		return
	var want: bool = AMBIENCE_KEYS.has(key)
	if _ambience_tween != null and _ambience_tween.is_valid():
		_ambience_tween.kill()
	if want:
		if not ambience_player.playing:
			ambience_player.volume_db = -60.0
			ambience_player.play()
		_ambience_tween = create_tween()
		_ambience_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_ambience_tween.tween_property(ambience_player, "volume_db", AMBIENCE_DB, 1.2)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	elif ambience_player.playing:
		_ambience_tween = create_tween()
		_ambience_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_ambience_tween.tween_property(ambience_player, "volume_db", -60.0, 0.8)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_ambience_tween.tween_callback(ambience_player.stop)

## Boss 战 BGM 闷音开关：登场压闷（900Hz 低通），伏诛/转阶段解除。Tween 防爆音。
## 2026-10-24 起效果器非常驻：开闷音先在透明档（CLEAR）接入再压到 900，解除时先回升到
## 透明档再整器旁路——常态链上没有有状态组件，引擎偶发 NaN 样本进不了双二阶寄存器。
func set_bgm_muffle(on: bool) -> void:
	if _bgm_lowpass == null:
		return
	var bgm_idx := AudioServer.get_bus_index(BUS_BGM)
	if bgm_idx < 0 or _bgm_effect_idx < 0:
		return
	if on == _muffle_on:
		return  # 已在目标意图态（含每次转波都来的解除调用），别空转 tween
	_muffle_on = on
	if _muffle_tween != null and _muffle_tween.is_valid():
		_muffle_tween.kill()
	if on:
		# 开闷音：透明档接入（解除补间中途折返则从当前档位续压），再压到 900Hz
		_bgm_lowpass.cutoff_hz = maxf(_bgm_lowpass.cutoff_hz, MUFFLE_CUTOFF)
		AudioServer.set_bus_effect_enabled(bgm_idx, _bgm_effect_idx, true)
		_muffle_tween = create_tween()
		_muffle_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_muffle_tween.tween_property(_bgm_lowpass, "cutoff_hz", MUFFLE_CUTOFF, 0.8)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		_muffle_tween = create_tween()
		_muffle_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_muffle_tween.tween_property(_bgm_lowpass, "cutoff_hz", CLEAR_CUTOFF, 0.8)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_muffle_tween.chain().tween_callback(func() -> void:
			if AudioServer.get_bus_index(BUS_BGM) == bgm_idx:
				AudioServer.set_bus_effect_enabled(bgm_idx, _bgm_effect_idx, false))

## 兼容旧调用：直接给一条流就播（Main 之外不该再有别处这么用）
func play_bgm(stream: AudioStream) -> void:
	if stream:
		bgm_players[bgm_next].stream = stream
		bgm_players[bgm_next].volume_db = -5.0
		bgm_players[bgm_next].play()
		bgm_key = BGM_DEFAULT_KEY

# ---------------- 音量设置（总线级，安卓用户能单独压 BGM） ----------------

## 有 SettingsManager 时整链委托给它一处：应用总线 + 落盘 settings.cfg 一次完成。
## 此前这里自己再 apply 一遍并另写一份 audio.cfg——拖一格音量同步写两个文件
func set_bus_linear(bus_name: StringName, value: float, persist: bool = true) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var v := clampf(value, 0.0, 1.0)
	_linear[bus_name] = v
	if Engine.get_main_loop() != null and has_node("/root/SettingsManager"):
		SettingsManager.set_bus_volume(bus_name, v, persist)
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(0.0001, v)))
	AudioServer.set_bus_mute(idx, v <= 0.001)
	if persist:
		_save_settings()

func get_bus_linear(bus_name: StringName) -> float:
	if Engine.get_main_loop() != null and has_node("/root/SettingsManager"):
		return SettingsManager.get_bus_volume(bus_name)
	if _linear.has(bus_name):
		return float(_linear[bus_name])
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return 1.0
	return db_to_linear(AudioServer.get_bus_volume_db(idx))

func _load_settings() -> void:
	if Engine.get_main_loop() != null and has_node("/root/SettingsManager"):
		for bus_name in [&"Master", &"BGM", &"SFX", &"Voice"]:
			_linear[String(bus_name)] = SettingsManager.get_bus_volume(bus_name)
		SettingsManager._apply_all_audio()
		return
	var cfg := ConfigFile.new()
	var err := cfg.load(SETTINGS_PATH)
	for bus_name in DEFAULT_LINEAR.keys():
		var v: float = float(DEFAULT_LINEAR[bus_name])
		if err == OK:
			var raw = cfg.get_value("audio", bus_name, v)
			if raw is float or raw is int:
				v = clampf(float(raw), 0.0, 1.0)
		var idx := AudioServer.get_bus_index(StringName(bus_name))
		if idx >= 0:
			AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(0.0001, v)))
			AudioServer.set_bus_mute(idx, v <= 0.001)
			_linear[bus_name] = v

func _save_settings() -> Error:
	var cfg := ConfigFile.new()
	for bus_name in _linear.keys():
		cfg.set_value("audio", bus_name, _linear[bus_name])
	var err := cfg.save(SETTINGS_PATH)
	if err != OK:
		push_warning("AudioManager: 保存音频设置失败 err=%d path=%s" % [err, SETTINGS_PATH])
	return err
