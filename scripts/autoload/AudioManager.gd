extends Node

## 全局音频管理：总线分层（Master/BGM/SFX/Voice）+ 16 通道并发池
## + 灵石连续拾取音阶攀升（Combo Pitch Climbing）+ BGM 状态机交叉淡化 + 音量设置持久化
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
const SETTINGS_PATH := "user://audio.cfg"
const DEFAULT_LINEAR := {"BGM": 1.0, "SFX": 1.0, "Voice": 1.0}

var bgm_players: Array[AudioStreamPlayer] = []
var bgm_next: int = 0          ## 双 player 轮换，实现交叉淡化时不被「同一播放器换曲」打断
var bgm_key: StringName = &""
var bgm_tween: Tween = null
var voice_player: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []
var next_sfx_idx: int = 0

var sfx_dict: Dictionary = {}
var _missing_paths: Array[String] = []
var _linear: Dictionary = {}

# 灵石拾取连击升调状态
var _gem_combo_count: int = 0
var _gem_combo_timer: float = 0.0

## 高频音效同 key 最小间隔（毫秒）：群战同帧几十次命中/死亡时防「糊成一片+通道瞬间耗尽」。
## 只对战斗高频音生效，UI/阶段音不受限。未列出的 key 不节流。
const SFX_GAP_MS := {
	"enemy_hit": 18,
	"enemy_hit_heavy": 18,
	"enemy_hit_crit": 40,
	"player_hurt": 120,
	"enemy_death": 30,
	"enemy_death_elite": 60,
	"sword_swing": 30,
	"blade_shoot": 25,
	"talisman_throw": 25,
	"thunder_strike": 40,
	"fan_gust": 35,
	"orb_hit": 30,
	"gem_pickup": 25,
	"chest_hit": 30,
	"ui_click": 30,
	"dodge": 80,
}
var _last_sfx_ms: Dictionary = {}

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

	for i in range(SFX_PLAYER_COUNT):
		var p := AudioStreamPlayer.new()
		p.bus = BUS_SFX
		add_child(p)
		sfx_players.append(p)

	_load_audio_assets()
	_load_settings()

func _process(delta: float) -> void:
	if _gem_combo_timer > 0.0:
		_gem_combo_timer -= delta
		if _gem_combo_timer <= 0.0:
			_gem_combo_count = 0

# ---------------- 音效注册表 ----------------

func _load_audio_assets() -> void:
	# 全部由 tools/bake_sfx.py 烘焙（同 key 多变体随机播 + 播放时抖音高）
	_register_sfx("enemy_hit", _sfx_paths("enemy_hit", 3))
	_register_sfx("enemy_hit_crit", _sfx_paths("enemy_hit_crit", 3))
	_register_sfx("enemy_hit_heavy", _sfx_paths("enemy_hit_heavy", 3))
	_register_sfx("player_hurt", _sfx_paths("player_hurt", 3))
	_register_sfx("enemy_death", _sfx_paths("enemy_death", 3))
	_register_sfx("enemy_death_elite", _sfx_paths("enemy_death_elite", 2))
	_register_sfx("sword_swing", _sfx_paths("sword_swing", 2))
	_register_sfx("blade_shoot", _sfx_paths("blade_shoot", 2))
	_register_sfx("talisman_throw", _sfx_paths("talisman_throw", 2))
	_register_sfx("thunder_strike", _sfx_paths("thunder_strike", 2))
	_register_sfx("fan_gust", _sfx_paths("fan_gust", 2))
	_register_sfx("orb_hit", _sfx_paths("orb_hit", 2))
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
	# 随行神通
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
	return _missing_paths

func has_sfx(key: String) -> bool:
	return sfx_dict.has(key)

## 已注册且素材可用的音效 key 列表（试听台/调试用）
func sfx_keys() -> Array:
	return sfx_dict.keys()

# ---------------- 播放 ----------------

func play_sfx(sfx_key: String, volume_scale: float = 1.0, pitch_override: float = 0.0) -> void:
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
		# 灵石连收音阶递进：短时间内连续拾取音高步步攀升，营造清脆爽感
		_gem_combo_count = mini(_gem_combo_count + 1, 16)
		_gem_combo_timer = 0.6
		p.pitch_scale = 0.94 + float(_gem_combo_count - 1) * 0.042
	else:
		p.pitch_scale = randf_range(0.92, 1.08)

	p.play()

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
		return

	# 交叉淡化：新的从空闲 player 载入播放，旧的同步停掉/淡出
	var idle_idx := 1 - bgm_next
	var idle: AudioStreamPlayer = bgm_players[idle_idx]
	idle.stream = stream

	if bgm_tween != null and bgm_tween.is_valid():
		bgm_tween.kill()

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

## 兼容旧调用：直接给一条流就播（Main 之外不该再有别处这么用）
func play_bgm(stream: AudioStream) -> void:
	if stream:
		bgm_players[bgm_next].stream = stream
		bgm_players[bgm_next].volume_db = -5.0
		bgm_players[bgm_next].play()
		bgm_key = BGM_DEFAULT_KEY

# ---------------- 音量设置（总线级，安卓用户能单独压 BGM） ----------------

func set_bus_linear(bus_name: StringName, value: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var v := clampf(value, 0.0, 1.0)
	_linear[bus_name] = v
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(0.0001, v)))
	AudioServer.set_bus_mute(idx, v <= 0.001)
	if Engine.get_main_loop() != null and has_node("/root/SettingsManager"):
		SettingsManager.set_bus_volume(bus_name, v)
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
			v = float(cfg.get_value("audio", bus_name, v))
		var idx := AudioServer.get_bus_index(StringName(bus_name))
		if idx >= 0:
			AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(0.0001, v)))
			AudioServer.set_bus_mute(idx, v <= 0.001)
			_linear[bus_name] = v

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	for bus_name in _linear.keys():
		cfg.set_value("audio", bus_name, _linear[bus_name])
	cfg.save(SETTINGS_PATH)
