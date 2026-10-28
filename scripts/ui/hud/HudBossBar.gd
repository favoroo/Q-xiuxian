class_name HudBossBar
extends PanelContainer

## 魔君血条（固定 Boss 关专用，信号驱动上屏/收起）：底部居中红斜切大色块 + 魔君名号，P5 剪纸风与顶栏一致。
## 从 GameHUD 拆出：血条自连 boss_hp_changed / boss_defeated，本层自治。
##
## 摆位（2026-10-25 用户：血条「显示在接近这个界面中间，挡住很多东西」）：
## 原先钉 PRESET_CENTER_TOP + offset_top=140，在 960×540 设计画布上落在 y 140..178 ——
## 正是玩家与敌潮扎堆的上半屏，且全宽 480。上缘第二排已被「余妖」芯片/羁绊徽记/横幅占满，
## 无处安放 ⇒ 改为贴屏幕下缘居中（y 492..526），与右下技能键（默认中心 y=430）和屏心视野都不打架。
## 尺寸同步收一档：480×38 → 360×34，进度条 300×16 → 230×12，只留「是谁 + 还剩多少」两条读数。

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

## 50% 刻度线的常态色（色表基准，与 _ready 初值同源）。用常量而不是「读当前色再回填」：
## 补间被打断时当前色会停在中间值，拿它当基准会把刻度永久留在闪过的颜色上。
const PHASE_TICK_BASE := Color("ffd23f")  # GameStyle.JADE
const PHASE_TICK_ALPHA := 0.6

## 血条盒尺寸与贴底摆位（设计单位）：总宽/总高、底边距、进度条最小宽与高、名号字号。
## 底边距留 20 —— 真机手势条压在屏底，贴死会被系统条盖住半截（与 HudEditOverlay 底栏同档）。
const BAR_W := 360.0
const BAR_H := 34.0
const BOTTOM_MARGIN := 20.0
const TRACK_MIN_W := 230.0
const TRACK_H := 12.0
const TITLE_FONT := 13
## 登场滑入量：从屏底外 26 单位抬到落定位，配 BACK 回弹读作「从地里顶上来」
const ENTER_LIFT := 26.0
## 判据应力样本用的名号：WaveSpawner 实际会发「火焰Boss / 最终Boss / 回响Boss」三条，
## 都是 6 个字符宽，取哪条都代表最坏宽度；BossEnemy 的默认值「敌潮Boss」同档
const WORST_TITLE := "最终Boss"

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", GameStyle.block(GameStyle.BAD_DK, GameStyle.SLANT_BAND, Vector2(3, 4)))
	# 底居中锚：换屏比时横向恒居中、纵向恒贴底，不随画布高度漂到半屏
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left = -BAR_W * 0.5
	offset_right = BAR_W * 0.5
	offset_top = -BOTTOM_MARGIN - BAR_H
	offset_bottom = -BOTTOM_MARGIN
	pivot_offset = Vector2(BAR_W * 0.5, BAR_H * 0.5)
	_build_row()
	GameManager.boss_hp_changed.connect(_on_boss_hp_changed)
	GameManager.boss_defeated.connect(_on_boss_defeated)

func _build_row() -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	add_child(row)

	_title_label = Label.new()
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameStyle.label(_title_label, TITLE_FONT, GameStyle.CHALK)
	row.add_child(_title_label)

	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(TRACK_MIN_W, TRACK_H)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar.show_percentage = false
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var styles: Array = GameStyle.bar_styles(GameStyle.with_alpha(Color(0.06, 0.04, 0.06), 0.9), GameStyle.BAD)
	_bar.add_theme_stylebox_override("background", styles[0])
	_bar.add_theme_stylebox_override("fill", styles[1])
	_fill_style = styles[1] as StyleBoxFlat
	row.add_child(_bar)

	# 狂暴分界刻度：位置 = GameBalance.boss_phase2_hp_pct（与 _enter_phase2 判定同源，画在哪 == 何时变）。
	# 用锚点钉在轨对应血线上（实际宽由 HBox 分配），常态低调的点缀黄竖线，跨线时闪一下。
	var p2_at := GameBalance.boss_phase2_hp_pct(GameManager.danger_level)
	_phase_tick = ColorRect.new()
	_phase_tick.color = GameStyle.with_alpha(PHASE_TICK_BASE, PHASE_TICK_ALPHA)
	_phase_tick.anchor_left = p2_at
	_phase_tick.anchor_right = p2_at
	_phase_tick.offset_left = -1.0
	_phase_tick.offset_right = 1.0
	_phase_tick.offset_top = 0.0
	_phase_tick.offset_bottom = 0.0
	_phase_tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(_phase_tick)

## 跨 50% 线的演出（一回合至多一次）：填充色朱砂→狂暴紫（与魔君本体 _tint 同色系语义），
## 刻度闪一下。只动已有的 _fill_style 实例颜色与 _phase_tick 的色值，不新建样式、不堆 Tween。
## 闪法用「底色→纸白→底色」的色相跳变，不用超白：HUD 与世界同处 HDR 根视口，
## modulate/color 分量 >1.0 会被 WorldEnvironment glow 当起辉源，而 glow_intensity
## 战斗中还随拥挤档升降 —— 观感就是整层 UI 跟着闪。
func _mark_phase2() -> void:
	_phase2_marked = true
	if _fill_style != null:
		_fill_style.bg_color = GameStyle.SHADOW
	if _phase_tick != null:
		if _phase_tween != null and _phase_tween.is_valid():
			_phase_tween.kill()
		var base := GameStyle.with_alpha(PHASE_TICK_BASE, PHASE_TICK_ALPHA)
		_phase_tick.color = GameStyle.CHALK
		_phase_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_phase_tween.tween_property(_phase_tick, "color", base, 0.5)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

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
			var p2_ratio := GameBalance.boss_phase2_hp_pct(GameManager.danger_level)
			_phase_tick.anchor_left = p2_ratio
			_phase_tick.anchor_right = p2_ratio
		modulate.a = 1.0
		visible = true
		# 登场：自屏底外顶上来 + 弹跳（与 banner / 等级徽章同款 BACK 缓动），配 boss_raid 低吼同拍。
		# 从下面上来而不是从上面压落：血条现在就住在屏底，从上面下来等于穿过整个战斗视野。
		var rest_top := -BOTTOM_MARGIN - BAR_H
		var rest_bottom := -BOTTOM_MARGIN
		if _fx_tween != null and _fx_tween.is_valid():
			_fx_tween.kill()
		_fx_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_fx_tween.set_parallel()
		_fx_tween.tween_property(self, "scale", Vector2.ONE, 0.22)\
			.from(Vector2(0.7, 0.7)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_fx_tween.tween_property(self, "offset_top", rest_top, 0.25)\
			.from(rest_top + ENTER_LIFT).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_fx_tween.tween_property(self, "offset_bottom", rest_bottom, 0.25)\
			.from(rest_bottom + ENTER_LIFT).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		return
	if not _phase2_marked and max_v > 0.0 and cur <= max_v * GameBalance.boss_phase2_hp_pct(GameManager.danger_level):
		_mark_phase2()
	if absf(_bar.value - cur) > 0.5:
		if _bar_tween != null and _bar_tween.is_valid():
			_bar_tween.kill()
		_bar_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_bar_tween.tween_property(_bar, "value", cur, 0.15)

func _on_boss_defeated(_title: String) -> void:
	_active = false
	if _fx_tween != null and _fx_tween.is_valid():
		_fx_tween.kill()
	_fx_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fx_tween.tween_property(self, "modulate:a", 0.0, 0.3)
	_fx_tween.tween_callback(func():
		visible = false
		modulate.a = 1.0)

## 供冒烟测试与调试断言：血条当前是否上屏
func is_showing() -> bool:
	return visible

## 判据取值口（与 HudWaveLeft.show_as_worst_case 同一约定）：
## 把血条钉成「最长名号 + 已落位」再量。不走 _on_boss_hp_changed —— 那条路会起登场补间，
## 量到的是从屏底外往上滑的中间帧，摆位对不对看不出来。
func show_as_worst_case() -> void:
	_active = true
	_title_label.text = WORST_TITLE
	_bar.max_value = 1.0
	_bar.value = 1.0
	if _fx_tween != null and _fx_tween.is_valid():
		_fx_tween.kill()
	scale = Vector2.ONE
	offset_top = -BOTTOM_MARGIN - BAR_H
	offset_bottom = -BOTTOM_MARGIN
	modulate.a = 1.0
	visible = true

## 判据读的名号（生产信号里的最长一档）
func readout_title() -> String:
	return _title_label.text if _title_label != null else ""
