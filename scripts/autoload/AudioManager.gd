extends Node

## 全局音频管理：多通道并发池 + 灵石连续拾取音阶攀升（Combo Pitch Climbing）

var bgm_player: AudioStreamPlayer
var voice_player: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []
var next_sfx_idx: int = 0

var sfx_dict: Dictionary = {}

# 灵石拾取连击升调状态
var _gem_combo_count: int = 0
var _gem_combo_timer: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	bgm_player = AudioStreamPlayer.new()
	bgm_player.bus = &"Master"
	bgm_player.volume_db = -5.0
	add_child(bgm_player)

	voice_player = AudioStreamPlayer.new()
	voice_player.bus = &"Master"
	voice_player.volume_db = 2.0
	add_child(voice_player)

	for i in range(16):
		var p = AudioStreamPlayer.new()
		p.bus = &"Master"
		add_child(p)
		sfx_players.append(p)

	_load_audio_assets()

func _process(delta: float) -> void:
	if _gem_combo_timer > 0.0:
		_gem_combo_timer -= delta
		if _gem_combo_timer <= 0.0:
			_gem_combo_count = 0

func _load_audio_assets() -> void:
	_register_sfx("blade_shoot", ["res://assets/audio/sfx/knifeSlice.ogg", "res://assets/audio/sfx/knifeSlice2.ogg"])
	_register_sfx("enemy_hit", ["res://assets/audio/sfx/chop.ogg"])
	_register_sfx("orb_hit", ["res://assets/audio/sfx/metalClick.ogg"])
	_register_sfx("gem_pickup", ["res://assets/audio/sfx/handleCoins.ogg"])
	_register_sfx("level_up", ["res://assets/audio/sfx/powerUp2.ogg", "res://assets/audio/sfx/powerUp6.ogg"])
	_register_sfx("obelisk_blessing", ["res://assets/audio/sfx/laser1.ogg"])

func _register_sfx(sfx_key: String, paths: Array) -> void:
	var streams: Array[AudioStream] = []
	for p in paths:
		if ResourceLoader.exists(p):
			var st = load(p) as AudioStream
			if st != null:
				streams.append(st)
	if not streams.is_empty():
		sfx_dict[sfx_key] = streams

func play_sfx(sfx_key: String, volume_scale: float = 1.0, pitch_override: float = 0.0) -> void:
	if not sfx_dict.has(sfx_key):
		return

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

func play_bgm(stream: AudioStream) -> void:
	if stream:
		bgm_player.stream = stream
		bgm_player.play()
