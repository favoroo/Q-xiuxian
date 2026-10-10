class_name HudBossBar
extends PanelContainer

## 魔君血条（固定 Boss 关专用，信号驱动上屏/收起）：顶部居中红斜切大色块 + 魔君名号，P5 剪纸风与顶栏一致。
## 从 GameHUD 拆出：血条自连 boss_hp_changed / boss_defeated，本层自治。

var _title_label: Label = null
var _bar: ProgressBar = null
var _active: bool = false

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", GameStyle.block(GameStyle.BAD_DK, GameStyle.SLANT_BAND, Vector2(4, 5)))
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	offset_left = -240.0
	offset_right = 240.0
	offset_top = 140.0
	offset_bottom = 178.0
	pivot_offset = Vector2(240.0, 19.0)
	_build_row()
	GameManager.boss_hp_changed.connect(_on_boss_hp_changed)
	GameManager.boss_defeated.connect(_on_boss_defeated)

func _build_row() -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	add_child(row)

	_title_label = Label.new()
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameStyle.label(_title_label, 15, GameStyle.CHALK)
	row.add_child(_title_label)

	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(300, 16)
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar.show_percentage = false
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var styles: Array = GameStyle.bar_styles(GameStyle.with_alpha(Color(0.06, 0.04, 0.06), 0.9), GameStyle.BAD)
	_bar.add_theme_stylebox_override("background", styles[0])
	_bar.add_theme_stylebox_override("fill", styles[1])
	row.add_child(_bar)

func _on_boss_hp_changed(cur: float, max_v: float, title: String) -> void:
	if not _active:
		_active = true
		_title_label.text = title
		_bar.max_value = max_v
		_bar.value = cur
		modulate.a = 1.0
		visible = true
		# 登场弹跳：与 banner / 等级徽章同款 BACK 缓动
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector2.ONE, 0.22)\
			.from(Vector2(0.6, 0.6)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	elif absf(_bar.value - cur) > 0.5:
		var tw := create_tween()
		tw.tween_property(_bar, "value", cur, 0.15)

func _on_boss_defeated(_title: String) -> void:
	_active = false
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func():
		visible = false
		modulate.a = 1.0)

## 供冒烟测试与调试断言：血条当前是否上屏
func is_showing() -> bool:
	return visible
