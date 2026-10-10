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
		"title": "音乐音量",
		"desc": "背景音乐 (BGM)",
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
		"title": "音效音量",
		"desc": "战斗与击杀音效 (SFX)",
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
		"title": "语音音量",
		"desc": "角色台词与提示语音 (Voice)",
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
		"desc": "显示命中伤害、暴击与闪避数字",
		"type": "toggle",
		"default": true,
	},
	{
		"section": "display",
		"key": "screen_shake",
		"title": "屏幕震动",
		"desc": "重击与受击时的镜头微震",
		"type": "toggle",
		"default": true,
	},
	{
		"section": "display",
		"key": "shake_intensity",
		"title": "屏幕震动",
		"desc": "只在击杀精英、受击等关键时刻震动；档位越高幅度越大",
		"type": "cycle",
		"default": &"standard",
		"options": [&"off", &"light", &"standard", &"heavy"],
	},
		{
			"section": "display",
			"key": "hit_stop",
			"title": "顿帧打击感",
			"desc": "命中与击杀强敌时的微顿帧（增强打击感）",
			"type": "toggle",
			"default": true,
		},
		{
			"section": "display",
			"key": "haptics",
			"title": "触觉震动",
			"desc": "受创与暴击时触发手柄/手机轻微震动反馈",
			"type": "toggle",
			"default": true,
		},
		{
			"section": "display",
			"key": "screen_flash",
			"title": "受击红晕",
			"desc": "受伤及濒死时屏幕边缘的暗红警示效果",
			"type": "toggle",
			"default": true,
		},
	{
		"section": "display",
		"key": "show_fps",
		"title": "实时帧率",
		"desc": "左上角显示当前帧率 (FPS)",
		"type": "toggle",
		"default": false,
	},

	# --------- 操作按钮布局（技能键 / 祭坛键自由拖动，操作页调整） ---------
	# 归一化中心点（相对设计视口 0..1），换屏比不漂移；缩放为底尺寸倍率
	# 默认值直接引用下面的常量，不在这里重抄一遍数字：两处各写一份，改了一处就会
	# 出现「设置页显示的是 A、reset 之后实际生效的是 B」这种对不上的读数
	{
		"section": "display",
		"key": "skill_btn_xy",
		"title": "技能按钮位置",
		"desc": "随行神通键的归一化屏幕中心点",
		"type": "layout",
		"default": SKILL_BTN_XY_DEFAULT,
	},
	{
		"section": "display",
		"key": "skill_btn_scale",
		"title": "技能按钮大小",
		"desc": "随行神通键的尺寸缩放倍率",
		"type": "layout",
		"default": 1.0,
	},
	{
		"section": "display",
		"key": "obelisk_btn_xy",
		"title": "祭坛按钮位置",
		"desc": "聚灵阵激活键的归一化屏幕中心点",
		"type": "layout",
		"default": OBELISK_BTN_XY_DEFAULT,
	},
	{
		"section": "display",
		"key": "obelisk_btn_scale",
		"title": "祭坛按钮大小",
		"desc": "聚灵阵激活键的尺寸缩放倍率",
		"type": "layout",
		"default": 1.0,
	},

	# --------- 仙途指引（开局自动弹指南的偏好；开关本体在指南卡底部） ---------
	{
		"section": "ui",
		"key": "tutorial_muted",
		"title": "下次不弹出",
		"desc": "勾上后点开始游戏不再自动弹新手指南，主菜单与设置页的手动入口不受影响",
		"type": "toggle",
		"default": false,
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
	_follow_legacy_layout_default()
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

# ----------------- 操作按钮布局（技能键 / 祭坛键自由拖动） -----------------

## 缩放倍率上下限（操作页滑杆与拖动摆位共用同一夹取）
const BTN_SCALE_MIN := 0.6
const BTN_SCALE_MAX := 1.8
## 归一化中心点默认值 = 960×540 基准下旧的「右下」摆位
## 两颗键同径（76 圆），默认上下叠成一列：技能键 816..892 × 392..468，
## 祭坛键 816..892 × 292..368 —— 两圆之间留 BTN_DEFAULT_EDGE_GAP 的设计像素空隙。
## 以前是 0 空隙（两圈描边正好相切），用户 2026-10-11 真机图：看着就是两颗键压在一起，
## 且手指落在相切那条线上时拾取给谁全看运气。空隙口径由 UnitRunner 钉住。
const SKILL_BTN_XY_DEFAULT := Vector2(854.0 / 960.0, 430.0 / 540.0)
const OBELISK_BTN_XY_DEFAULT := Vector2(854.0 / 960.0, 330.0 / 540.0)
## 默认摆位下两颗键圆边之间的最小间距（设计像素，按 960×540 基准算）
const BTN_DEFAULT_EDGE_GAP := 24.0

func skill_btn_xy() -> Vector2:
	return _norm_xy(get_val(&"display", &"skill_btn_xy", SKILL_BTN_XY_DEFAULT))

func set_skill_btn_xy(norm: Vector2, auto_save: bool = true) -> void:
	set_val(&"display", &"skill_btn_xy", _norm_xy(norm), auto_save)

func skill_btn_scale() -> float:
	return _btn_scale(get_val(&"display", &"skill_btn_scale", 1.0))

func set_skill_btn_scale(scale_f: float, auto_save: bool = true) -> void:
	set_val(&"display", &"skill_btn_scale", _btn_scale(scale_f), auto_save)

func obelisk_btn_xy() -> Vector2:
	return _norm_xy(get_val(&"display", &"obelisk_btn_xy", OBELISK_BTN_XY_DEFAULT))

func set_obelisk_btn_xy(norm: Vector2, auto_save: bool = true) -> void:
	set_val(&"display", &"obelisk_btn_xy", _norm_xy(norm), auto_save)

func obelisk_btn_scale() -> float:
	return _btn_scale(get_val(&"display", &"obelisk_btn_scale", 1.0))

func set_obelisk_btn_scale(scale_f: float, auto_save: bool = true) -> void:
	set_val(&"display", &"obelisk_btn_scale", _btn_scale(scale_f), auto_save)

## 恢复两个按钮的出厂摆位（位置 + 大小一起回默认）
func reset_button_layout() -> void:
	set_val(&"display", &"skill_btn_xy", SKILL_BTN_XY_DEFAULT)
	set_val(&"display", &"skill_btn_scale", 1.0)
	set_val(&"display", &"obelisk_btn_xy", OBELISK_BTN_XY_DEFAULT)
	set_val(&"display", &"obelisk_btn_scale", 1.0)

## v0.0.17 及更早的出厂摆位：祭坛键与技能键 0 空隙相切
const OBELISK_BTN_XY_LEGACY := Vector2(854.0 / 960.0, 354.0 / 540.0)

## 出厂摆位换代的一次性跟随。
## 为什么需要：`_save_settings()` 是把整份 `_settings`（含从没碰过的默认项）一次写盘的，
## 所以老玩家只要改过任意一个设置，上一版的出厂坐标就已经落在存档里 —— 只改常量他们永远跟不到，
## 屏幕上还是那颗相切的旧键。这里只认「存档值正好等于旧出厂位」这一种情况：
## 玩家自己拖过的位置一律不碰。
func _follow_legacy_layout_default() -> void:
	if not _settings.has("display"):
		return
	var sec: Dictionary = _settings["display"]
	var v: Variant = sec.get("obelisk_btn_xy", null)
	if v is Vector2 and (v as Vector2).is_equal_approx(OBELISK_BTN_XY_LEGACY):
		sec["obelisk_btn_xy"] = OBELISK_BTN_XY_DEFAULT

# ----------------- 仙途指引（新手指南自动弹出） -----------------

## 新手指南是否已被玩家勾掉「下次不弹出」：true = 点开始游戏不再自动弹。
## 只影响自动弹这一条路径；主菜单/设置页的手动入口永远能翻（见 StartMenu._on_guide_pressed、
## SettingsDialog 底部「新手指南」按钮），所以勾掉之后玩家还能自己点开并取消勾选。
func tutorial_muted() -> bool:
	return bool(get_val(&"ui", &"tutorial_muted", false))

## 写入勾选态并即时落盘 user://settings.cfg（偏好，不进 progress.cfg）
func set_tutorial_muted(muted: bool) -> void:
	set_val(&"ui", &"tutorial_muted", muted)

func _norm_xy(v: Variant) -> Vector2:
	var p := v as Vector2
	return Vector2(clampf(p.x, 0.0, 1.0), clampf(p.y, 0.0, 1.0))

func _btn_scale(v: Variant) -> float:
	return clampf(float(v), BTN_SCALE_MIN, BTN_SCALE_MAX)

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
