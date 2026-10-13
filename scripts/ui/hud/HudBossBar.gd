class_name HudBossBar
extends PanelContainer

## 魔君血条（固定 Boss 关专用，信号驱动上屏/收起）：顶部居中红斜切大色块 + 魔君名号，P5 剪纸风与顶栏一致。
## 从 GameHUD 拆出：血条自连 boss_hp_changed / boss_defeated，本层自治。

var _title_label: Label = null
var _bar: ProgressBar = null
var _fill_style: StyleBoxFlat = null
var _phase_tick: ColorRect = null
var _active: bool = false
var _phase2_marked: bool = false
## 补间持久句柄：Boss 每次命中都发信号，局部 tween 不 kill 会每秒堆几十个（2026-10-13 掉帧根因）。
## 血条值与登场/退场特效分两个句柄：血条 tween 不许杀到登场的 scale 回弹，否则条会停在半大。
## _phase_tween 只在跨 50% 线那一拍用（一回合至多一次），单发无堆积风险。
var _fx_tween: Tween = null
var _bar_tween: Tween = null
var _phase_tween: Tween = null

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
	_fill_style = styles[1] as StyleBoxFlat
	row.add_child(_bar)

	# 50% 狂暴分界刻度：位置 = GameBalance.BOSS_PHASE2_AT（与 _enter_phase2 判定同源，画在哪 == 何时变）。
	# 用锚点钉在轨中点（不写死 300 —— 实际宽由 HBox 分配），常态低调的点缀黄竖线，跨线时闪一下。
	_phase_tick = ColorRect.new()
	_phase_tick.color = GameStyle.with_alpha(GameStyle.JADE, 0.6)
	_phase_tick.anchor_left = GameBalance.BOSS_PHASE2_AT
	_phase_tick.anchor_right = GameBalance.BOSS_PHASE2_AT
	_phase_tick.offset_left = -1.0
	_phase_tick.offset_right = 1.0
	_phase_tick.offset_top = 0.0
	_phase_tick.offset_bottom = 0.0
	_phase_tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(_phase_tick)

## 跨 50% 线的演出（一回合至多一次）：填充色朱砂→狂暴紫（与魔君本体 _tint 同色系语义），
## 刻度闪一下。只动已有的 _fill_style 实例颜色与 _phase_tick.modulate，不新建样式、不堆 Tween。
func _mark_phase2() -> void:
	_phase2_marked = true
	if _fill_style != null:
		_fill_style.bg_color = GameStyle.SHADOW
	if _phase_tick != null:
		if _phase_tween != null and _phase_tween.is_valid():
			_phase_tween.kill()
		_phase_tick.modulate = Color(3.0, 3.0, 3.0, 1.0)
		_phase_tween = create_tween()
		_phase_tween.tween_property(_phase_tick, "modulate", Color.WHITE, 0.5)

func _on_boss_hp_changed(cur: float, max_v: float, title: String) -> void:
	if not _active:
		_active = true
		_title_label.text = title
		_bar.max_value = max_v
		_bar.value = cur
		# 新一位魔君登场：复位狂暴演出（血条跨回合常驻，色与刻度回初始）
		_phase2_marked = false
		if _fill_style != null:
			_fill_style.bg_color = GameStyle.BAD
		if _phase_tick != null:
			_phase_tick.modulate = Color.WHITE
		modulate.a = 1.0
		visible = true
		# 登场弹跳：与 banner / 等级徽章同款 BACK 缓动
		if _fx_tween != null and _fx_tween.is_valid():
			_fx_tween.kill()
		_fx_tween = create_tween()
		_fx_tween.tween_property(self, "scale", Vector2.ONE, 0.22)\
			.from(Vector2(0.6, 0.6)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		return
	if not _phase2_marked and max_v > 0.0 and cur <= max_v * GameBalance.BOSS_PHASE2_AT:
		_mark_phase2()
	if absf(_bar.value - cur) > 0.5:
		if _bar_tween != null and _bar_tween.is_valid():
			_bar_tween.kill()
		_bar_tween = create_tween()
		_bar_tween.tween_property(_bar, "value", cur, 0.15)

func _on_boss_defeated(_title: String) -> void:
	_active = false
	if _fx_tween != null and _fx_tween.is_valid():
		_fx_tween.kill()
	_fx_tween = create_tween()
	_fx_tween.tween_property(self, "modulate:a", 0.0, 0.3)
	_fx_tween.tween_callback(func():
		visible = false
		modulate.a = 1.0)

## 供冒烟测试与调试断言：血条当前是否上屏
func is_showing() -> bool:
	return visible
