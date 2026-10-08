extends Node

## 音效试听台：把已注册的音效按顺序播一遍，再各播一段 BGM，屏幕与控制台同步显示 key。
## 用法：godot --path . res://tests/AudioGallery.tscn   （要真实出声，不要加 --headless）
##   R = 重听全部　空格 = 重播当前这条　Esc = 退出
## 目的：音效好不好听只能在设备上用耳朵判，这里只负责「一条不落全过一遍 + 名字对得上」。

const SFX_GAP := 0.42         ## 每条音效之间的间隔（秒）
const BGM_HOLD := 6.0         ## 每段 BGM 试听时长

@onready var title: Label = $Title
@onready var current: Label = $Current

var _keys: Array = []
var _bgm_keys: Array = []
var _idx: int = 0
var _phase: int = 0            ## 0=逐条音效 1=BGM 2=结束待重听
var _timer: float = 0.0
var _last_key: String = ""

func _ready() -> void:
	_keys = AudioManager.sfx_keys()
	_keys.sort()
	_bgm_keys = AudioManager.BGM_TABLE.keys()
	_bgm_keys.sort()
	_idx = 0
	_phase = 0
	_timer = 0.2          # 留一点时间让 autoload 稳定，然后马上开始播第一条
	title.text = "音效试听台 · %d 个 key / %d 段 BGM" % [_keys.size(), _bgm_keys.size()]
	current.text = "准备…"

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
			AudioManager.play_sfx(_last_key, 1.0, 1.0)  # 固定音高，听的就是原始素材
			_show("SFX  %d/%d  %s" % [_idx + 1, _keys.size(), _last_key])
			_idx += 1
			_timer = SFX_GAP
		1:
			if _idx >= _bgm_keys.size():
				_phase = 2
				_show("全部播完 · R 重听 / 空格 重播当前")
				return
			var key := String(_bgm_keys[_idx])
			AudioManager.play_bgm_key(key)
			_last_key = "BGM " + key
			_show("BGM  %d/%d  %s" % [_idx + 1, _bgm_keys.size(), key])
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
				AudioManager.play_bgm_key(_last_key.replace("BGM ", ""))
			elif AudioManager.has_sfx(_last_key):
				AudioManager.play_sfx(_last_key, 1.0, 1.0)
			_show("重播 · " + _last_key)
			_timer = SFX_GAP
