extends Node

## 全局游戏设置管理器：统一持久化（user://settings.cfg）
## + 音频总线音量与静音管理 + 战斗与显示特效开关 + 声明式配置项注册表
##
## 设计目标：
## 1. 结构化持久化（按 audio / display / gameplay 分区存储）。
## 2. 声明式配置项注册表（SCHEMA），未来新增任何滑条、开关只需在此添加一行即可自动在 UI 生成。
## 3. 实时同步 AudioServer 与既有 AudioManager，保障向下兼容与单测通过。

signal setting_changed(section: StringName, key: StringName, value: Variant)
signal audio_volume_changed(bus: StringName, linear_val: float, muted: bool)

const SETTINGS_PATH := "user://settings.cfg"
const AUDIO_LEGACY_PATH := "user://audio.cfg"

## 声明式配置项注册表：定义 UI 渲染及默认值
const SCHEMA: Array[Dictionary] = [
	# --------- 灵音调律（音频总线） ---------
	{
		"section": "audio",
		"key": "master_volume",
		"title": "主音量",
		"desc": "天地乾坤整体总音量控制",
		"type": "slider",
		"bus": &"Master",
		"default": 1.0,
		"min": 0.0,
		"max": 1.0,
		"step": 0.05,
	},
	{
		"section": "audio",
		"key": "bgm_volume",
		"title": "灵乐音量",
		"desc": "背景修仙旋律与场景伴奏 (BGM)",
		"type": "slider",
		"bus": &"BGM",
		"default": 1.0,
		"min": 0.0,
		"max": 1.0,
		"step": 0.05,
	},
	{
		"section": "audio",
		"key": "sfx_volume",
		"title": "音效应量",
		"desc": "法宝出鞘、道法轰击与击杀音效 (SFX)",
		"type": "slider",
		"bus": &"SFX",
		"default": 1.0,
		"min": 0.0,
		"max": 1.0,
		"step": 0.05,
	},
	{
		"section": "audio",
		"key": "voice_volume",
		"title": "道音音量",
		"desc": "天道启示与人物心语语音 (Voice)",
		"type": "slider",
		"bus": &"Voice",
		"default": 1.0,
		"min": 0.0,
		"max": 1.0,
		"step": 0.05,
	},

	# --------- 剑意视界（战斗与画面特效） ---------
	{
		"section": "display",
		"key": "damage_numbers",
		"title": "伤害跳字",
		"desc": "呈现命中伤害、暴击惊雷与身法回避数字",
		"type": "toggle",
		"default": true,
	},
	{
		"section": "display",
		"key": "screen_shake",
		"title": "屏幕震动",
		"desc": "神兵重击、劫雷降临与受创时的镜头微震",
		"type": "toggle",
		"default": true,
	},
	{
		"section": "display",
		"key": "shake_intensity",
		"title": "屏幕震动",
		"desc": "只在诛精英、受创、天雷落劫等要紧时刻震一下；档位越高幅度越大",
		"type": "cycle",
		"default": &"standard",
		"options": [&"off", &"light", &"standard", &"heavy"],
	},
	{
		"section": "display",
		"key": "hit_stop",
		"title": "顿帧打击感",
		"desc": "法刃切入与强敌湮灭瞬间的时空凝滞微顿",
		"type": "toggle",
		"default": true,
	},
	{
		"section": "display",
		"key": "screen_flash",
		"title": "受击红晕",
		"desc": "气血受损及濒死危机时刻的全屏警示灵晕",
		"type": "toggle",
		"default": true,
	},
	{
		"section": "display",
		"key": "show_fps",
		"title": "实时帧率",
		"desc": "在界面左上方观测当前灵息流转帧率 (FPS)",
		"type": "toggle",
		"default": false,
	},
	{
		"section": "display",
		"key": "skill_btn_pos",
		"title": "技能按钮位置",
		"desc": "战斗界面随行神通释放键的停靠位置",
		"type": "cycle",
		"default": &"right_bottom",
		"options": [&"right_bottom", &"right_mid", &"left_bottom"],
	},
]

const BUS_KEY_MAP := {
	&"Master": "master_volume",
	&"BGM": "bgm_volume",
	&"SFX": "sfx_volume",
	&"Voice": "voice_volume",
}

const BUS_MUTE_MAP := {
	&"Master": "master_muted",
	&"BGM": "bgm_muted",
	&"SFX": "sfx_muted",
	&"Voice": "voice_muted",
}

## 震屏档位表（关闭 / 轻 / 标准 / 强）：倍率同时乘在位移、滚转与缩放冲击上。
## 与历史遗留的 screen_shake 布尔总开关严格同源（见 _sync_shake_pair），界面上只留一个控件。
const SHAKE_LEVEL_ORDER: Array[StringName] = [&"off", &"light", &"standard", &"heavy"]
const SHAKE_LEVEL_LABELS := {
	"off": "关闭",
	"light": "轻",
	"standard": "标准",
	"heavy": "强",
}
const SHAKE_LEVEL_MULT := {
	"off": 0.0,
	"light": 0.4,
	"standard": 1.0,
	"heavy": 1.7,
}
const SHAKE_DEFAULT_LEVEL := &"standard"

## 内存设置字典: section -> { key: value }
var _settings: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_init_defaults()
	_load_settings()
	_apply_all_audio()

## 初始化默认配置
func _init_defaults() -> void:
	_settings.clear()
	for item in SCHEMA:
		var sec: String = item["section"]
		var k: String = item["key"]
		if not _settings.has(sec):
			_settings[sec] = {}
		_settings[sec][k] = item["default"]

	# 音频静音状态默认均为 false
	if not _settings.has("audio"):
		_settings["audio"] = {}
	for bus in BUS_MUTE_MAP.keys():
		var mute_key: String = BUS_MUTE_MAP[bus]
		if not _settings["audio"].has(mute_key):
			_settings["audio"][mute_key] = false

## 取得某项配置（无则返回 default_val）
func get_val(section: StringName, key: StringName, default_val: Variant = null) -> Variant:
	var sec_str := String(section)
	var key_str := String(key)
	if _settings.has(sec_str) and _settings[sec_str].has(key_str):
		return _settings[sec_str][key_str]
	if default_val != null:
		return default_val
	# 回落到 SCHEMA 中的默认值
	for item in SCHEMA:
		if item["section"] == sec_str and item["key"] == key_str:
			return item["default"]
	return null

## 修改某项配置并即时写盘
func set_val(section: StringName, key: StringName, val: Variant, auto_save: bool = true) -> void:
	var sec_str := String(section)
	var key_str := String(key)
	if not _settings.has(sec_str):
		_settings[sec_str] = {}
	_settings[sec_str][key_str] = val
	setting_changed.emit(section, key, val)

	# 若修改的是音频相关，即时同步 AudioServer
	for bus in BUS_KEY_MAP.keys():
		if sec_str == "audio" and key_str == BUS_KEY_MAP[bus]:
			_apply_bus_audio(bus)
			audio_volume_changed.emit(bus, float(val), is_bus_muted(bus))
			break
		elif sec_str == "audio" and key_str == BUS_MUTE_MAP[bus]:
			_apply_bus_audio(bus)
			audio_volume_changed.emit(bus, get_bus_volume(bus), bool(val))
			break

	_sync_shake_pair(sec_str, key_str)

	if auto_save:
		_save_settings()

# ----------------- 震屏便捷接口 -----------------

## 当前震屏档位。ConfigFile 存取会把 StringName 变成 String，这里统一归一化
func shake_level() -> StringName:
	return StringName(str(get_val(&"display", &"shake_intensity", SHAKE_DEFAULT_LEVEL)))

## 震屏幅度倍率：0 = 完全不震。总开关（screen_shake）关掉时档位再高也是 0
func shake_mult() -> float:
	if not bool(get_val(&"display", &"screen_shake", true)):
		return 0.0
	return float(SHAKE_LEVEL_MULT.get(str(shake_level()), 1.0))

## 档位的人话名（设置界面与详解卡用）
func shake_level_label() -> String:
	return String(SHAKE_LEVEL_LABELS.get(str(shake_level()), "标准"))

## 循环到下一档（关闭 → 轻 → 标准 → 强 → 关闭）
func shake_level_next() -> StringName:
	var i := SHAKE_LEVEL_ORDER.find(shake_level())
	return SHAKE_LEVEL_ORDER[(i + 1) % SHAKE_LEVEL_ORDER.size()]

# ----------------- 技能按钮位置（HUD 神通键停靠档位） -----------------

const SKILL_BTN_POS_ORDER: Array[StringName] = [&"right_bottom", &"right_mid", &"left_bottom"]
const SKILL_BTN_POS_LABELS: Dictionary = {"right_bottom": "右下", "right_mid": "右中", "left_bottom": "左下"}
const SKILL_BTN_POS_DEFAULT := &"right_bottom"

func skill_btn_pos() -> StringName:
	return StringName(str(get_val(&"display", &"skill_btn_pos", SKILL_BTN_POS_DEFAULT)))

## 档位的人话名（设置界面循环按钮用）
func skill_btn_pos_label() -> String:
	return String(SKILL_BTN_POS_LABELS.get(str(skill_btn_pos()), "右下"))

## 循环到下一档（右下 → 右中 → 左下 → 右下）
func skill_btn_pos_next() -> StringName:
	var i := SKILL_BTN_POS_ORDER.find(skill_btn_pos())
	return SKILL_BTN_POS_ORDER[(i + 1) % SKILL_BTN_POS_ORDER.size()]

## 档位与旧布尔总开关保持同源：老存档里只有 screen_shake，而界面只暴露一个循环控件，
## 两者不同步就会出现「显示标准、实际不震」这类看不见对不上的读数
func _sync_shake_pair(sec_str: String, key_str: String) -> void:
	if sec_str != "display" or not _settings.has("display"):
		return
	if key_str != "screen_shake" and key_str != "shake_intensity":
		return
	var display: Dictionary = _settings["display"]
	if key_str == "shake_intensity":
		var should_be_on := shake_level() != &"off"
		if bool(display.get("screen_shake", true)) != should_be_on:
			display["screen_shake"] = should_be_on
			setting_changed.emit(&"display", &"screen_shake", should_be_on)
	else:
		var enabled := bool(display.get("screen_shake", true))
		var lv := shake_level()
		if not enabled and lv != &"off":
			display["shake_intensity"] = &"off"
			setting_changed.emit(&"display", &"shake_intensity", &"off")
		elif enabled and lv == &"off":
			display["shake_intensity"] = SHAKE_DEFAULT_LEVEL
			setting_changed.emit(&"display", &"shake_intensity", SHAKE_DEFAULT_LEVEL)

# ----------------- 音频便捷接口 -----------------

func get_bus_volume(bus_name: StringName) -> float:
	var key = BUS_KEY_MAP.get(bus_name, "")
	if key != "":
		return float(get_val(&"audio", StringName(key), 1.0))
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		return db_to_linear(AudioServer.get_bus_volume_db(idx))
	return 1.0

func set_bus_volume(bus_name: StringName, linear_val: float) -> void:
	var v := clampf(linear_val, 0.0, 1.0)
	var key = BUS_KEY_MAP.get(bus_name, "")
	if key != "":
		set_val(&"audio", StringName(key), v, false)
		# 若用户拖动音量大于 0，且当前处于静音态，则自动解除静音
		if v > 0.001 and is_bus_muted(bus_name):
			var mute_key = BUS_MUTE_MAP.get(bus_name, "")
			if mute_key != "":
				set_val(&"audio", StringName(mute_key), false, false)
	_apply_bus_audio(bus_name)
	_save_settings()
	audio_volume_changed.emit(bus_name, v, is_bus_muted(bus_name))

func is_bus_muted(bus_name: StringName) -> bool:
	var mute_key = BUS_MUTE_MAP.get(bus_name, "")
	if mute_key != "":
		return bool(get_val(&"audio", StringName(mute_key), false))
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		return AudioServer.is_bus_mute(idx)
	return false

func set_bus_muted(bus_name: StringName, muted: bool) -> void:
	var mute_key = BUS_MUTE_MAP.get(bus_name, "")
	if mute_key != "":
		set_val(&"audio", StringName(mute_key), muted, true)
	_apply_bus_audio(bus_name)
	audio_volume_changed.emit(bus_name, get_bus_volume(bus_name), muted)

func toggle_bus_muted(bus_name: StringName) -> bool:
	var new_muted := not is_bus_muted(bus_name)
	set_bus_muted(bus_name, new_muted)
	return new_muted

func _apply_bus_audio(bus_name: StringName) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var v := get_bus_volume(bus_name)
	var muted := is_bus_muted(bus_name)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(0.0001, v)))
	AudioServer.set_bus_mute(idx, muted or v <= 0.001)

func _apply_all_audio() -> void:
	for bus in BUS_KEY_MAP.keys():
		_apply_bus_audio(bus)

# ----------------- 重置默认与落盘 -----------------

func reset_to_defaults() -> void:
	_init_defaults()
	_apply_all_audio()
	_save_settings()
	for item in SCHEMA:
		setting_changed.emit(StringName(item["section"]), StringName(item["key"]), item["default"])
	for bus in BUS_KEY_MAP.keys():
		audio_volume_changed.emit(bus, get_bus_volume(bus), is_bus_muted(bus))

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SETTINGS_PATH)
	if err == OK:
		for sec in cfg.get_sections():
			if not _settings.has(sec):
				_settings[sec] = {}
			for k in cfg.get_section_keys(sec):
				_settings[sec][k] = cfg.get_value(sec, k)
	else:
		# 尝试从历史 user://audio.cfg 迁移
		_try_migrate_legacy_audio()

func _try_migrate_legacy_audio() -> void:
	var leg_cfg := ConfigFile.new()
	if leg_cfg.load(AUDIO_LEGACY_PATH) == OK:
		for bus in [&"BGM", &"SFX", &"Voice"]:
			var key = BUS_KEY_MAP.get(bus, "")
			if key != "" and leg_cfg.has_section_key("audio", String(bus)):
				var v = leg_cfg.get_value("audio", String(bus), 1.0)
				_settings["audio"][key] = clampf(float(v), 0.0, 1.0)
		_save_settings()

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	for sec in _settings.keys():
		var sec_dict: Dictionary = _settings[sec]
		for k in sec_dict.keys():
			cfg.set_value(sec, k, sec_dict[k])
	cfg.save(SETTINGS_PATH)
