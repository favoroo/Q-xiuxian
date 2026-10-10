class_name HudFpsCounter
extends Label

## 左下角 FPS 读数：默认关，设置·显示页控制显隐。
## 从 GameHUD 拆出：自管显隐监听与每帧读数。

var _timer: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 钉左下角而不是写死 y=514：窗口比 16:9 高时设计高度会涨（expand），写死就漂到半屏
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 16.0
	offset_top = -26.0
	offset_right = 120.0
	offset_bottom = -8.0
	GameStyle.label(self, 12, GameStyle.PAPER_DIM)
	text = "FPS: 60"
	_update_visibility()
	SettingsManager.setting_changed.connect(func(sec: StringName, key: StringName, _val: Variant):
		if sec == &"display" and key == &"show_fps":
			_update_visibility()
	)

func _update_visibility() -> void:
	visible = bool(SettingsManager.get_val(&"display", &"show_fps", false))

func _process(delta: float) -> void:
	if not visible:
		return
	_timer += delta
	if _timer >= 0.25:
		_timer = 0.0
		var fps := Engine.get_frames_per_second()
		text = "FPS: %d" % fps
		var fps_col := GameStyle.GOOD if fps >= 55 else (GameStyle.JADE if fps >= 35 else GameStyle.BAD)
		add_theme_color_override("font_color", fps_col)
