extends Control

## 音效与 BGM 试听台：支持 6 大场景正式 BGM 即点试听与全量 SFX 轮播。
## 用法：godot --path . res://tests/AudioGallery.tscn   （要真实出声，不要加 --headless）
##   R = 重听全部 SFX　空格 = 重播当前 / 暂停　Esc = 退出

const SFX_GAP := 0.42         ## 每条音效之间的间隔（秒）
const BGM_HOLD := 6.0         ## 自动轮播时每段 BGM 试听时长

const BGM_LABELS := {
	"menu": "主菜单 (menu · 60 BPM 古铜钟磬/幽谷泛音)",
	"battle": "战斗 (battle · 120 BPM 冷冽古琴/仪式战鼓)",
	"shop": "商店 (shop · 76 BPM 冷月寒玉微磬/静谧)",
	"trial": "Boss/精英 (trial · 144 BPM 压迫暗脉冲/古金重击)",
	"victory": "胜利 (victory · 88 BPM 破晓钟琴/零延迟起奏)",
	"defeat": "失败 (defeat · 58 BPM 沉鼓碎筝/零延迟起奏)",
}

@onready var title: Label = $Title
@onready var current: Label = $Current

var _keys: Array = []
var _bgm_keys: Array = ["menu", "battle", "shop", "trial", "victory", "defeat"]
var _idx: int = 0
var _phase: int = 0            ## 0=逐条音效 1=BGM 2=结束或手动点选
var _timer: float = 0.0
var _last_key: String = ""

func _ready() -> void:
	_keys = AudioManager.sfx_keys()
	_keys.sort()
	_idx = 0
	_phase = 0
	_timer = 0.2
	title.text = "音效与 BGM 试听台 · %d 个音效 / %d 首 BGM（可点下方按钮直切 BGM）" % [_keys.size(), _bgm_keys.size()]
	current.text = "准备…"

	_build_bgm_buttons()

	if DisplayServer.get_name() == "headless":
		print("[AUDIO_GALLERY] Headless 模式自动跳过试听，音效 key 数量: %d, BGM 数量: %d" % [_keys.size(), _bgm_keys.size()])
		await get_tree().create_timer(0.1).timeout
		get_tree().quit(0)

func _build_bgm_buttons() -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.position = Vector2(32, 160)
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 12)
	add_child(grid)

	for bkey in _bgm_keys:
		var btn := Button.new()
		btn.text = BGM_LABELS.get(bkey, bkey)
		btn.custom_minimum_size = Vector2(430, 42)
		GameStyle.button(btn, GameStyle.NAVY2, GameStyle.GOLD, 14, GameStyle.PAPER)
		var k: String = bkey
		btn.pressed.connect(func():
			_phase = 2
			AudioManager.play_bgm_key(k, true)
			_last_key = "BGM " + k
			_show("手动试听 BGM · " + BGM_LABELS.get(k, k))
		)
		grid.add_child(btn)

func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return

	match _phase:
		0:
			if _idx >= _keys.size():
				_phase = 1
				_idx = 0
				_timer = 0.2
				return
			_last_key = String(_keys[_idx])
			AudioManager.play_sfx(_last_key, 1.0, 1.0)
			_show("SFX  %d/%d  %s" % [_idx + 1, _keys.size(), _last_key])
			_idx += 1
			_timer = SFX_GAP
		1:
			if _idx >= _bgm_keys.size():
				_phase = 2
				_show("全部播完 · 点下方按钮切 BGM / R 重听全部 / 空格 重播当前")
				return
			var key := String(_bgm_keys[_idx])
			AudioManager.play_bgm_key(key, true)
			_last_key = "BGM " + key
			_show("BGM  %d/%d  %s" % [_idx + 1, _bgm_keys.size(), BGM_LABELS.get(key, key)])
			_idx += 1
			_timer = BGM_HOLD
		2:
			_timer = 1.0

func _show(text: String) -> void:
	current.text = text
	print("[GALLERY] " + text)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and not event.pressed:
		return
	match String(event.as_text()).to_lower():
		"esc":
			get_tree().quit()
		"r":
			_keys = AudioManager.sfx_keys()
			_keys.sort()
			_idx = 0
			_phase = 0
			_timer = 0.1
		" ":
			if _last_key.begins_with("BGM"):
				var k := _last_key.replace("BGM ", "")
				AudioManager.bgm_key = &""
				AudioManager.play_bgm_key(k, true)
			elif AudioManager.has_sfx(_last_key):
				AudioManager.play_sfx(_last_key, 1.0, 1.0)
			_show("重播 · " + _last_key)
			_timer = SFX_GAP
