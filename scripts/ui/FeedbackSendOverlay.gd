class_name FeedbackSendOverlay
extends Control

## 反馈发送进度覆盖层（2026-10-23）
##
## 盖在反馈弹窗之上的一层「忙碌态」卡片：
##   sending —— 旋转弧环 + 金色扫描条 + 分阶段状态文案 + 已等待秒数
##   success —— 金色方框大对勾 + 「反馈已送达」+ 「完 成」按钮
##
## 设计口径：
## - 全屏暗色遮罩 + 居中纸面小卡，和项目其它弹窗同一套 GameStyle 配方；
## - 自绘动画统一 30Hz 重绘（SpawnIndicator 同口径），不做每帧 queue_redraw；
## - 树暂停时也要动：process_mode = ALWAYS，tween 一律 TWEEN_PAUSE_PROCESS。

signal completed

enum State { SENDING, SUCCESS }

const SPINNER_SIZE := 88.0
const SCAN_SIZE := Vector2(280, 12)
const CHECK_SIZE := 96.0
const REDRAW_INTERVAL := 0.033

var state: State = State.SENDING
var _clock: float = 0.0
var _last_redraw: float = 0.0
var _elapsed: float = 0.0

var _dim: ColorRect
var _card: PanelContainer
var _title_lbl: Label
var _sub_lbl: Label
var _elapsed_lbl: Label
var _spinner: Spinner
var _scan: ScanBar
var _check: CheckMark
var _done_btn: Button
var _content: VBoxContainer
var _fade_tw: Tween

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()

func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = GameStyle.dim_overlay(0.55)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_card = PanelContainer.new()
	# 高度交给内容自然撑开：固定 292 会把「发送中」和「成功」两种内容都拉出空档，
	# 宽 420 钉住是为了让文案按固定宽度折行。
	_card.custom_minimum_size = Vector2(420, 0)
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.add_to_group(DawnJoystick.UI_PRESS_HOLD_GROUP)
	_card.add_theme_stylebox_override("panel", GameStyle.dialog_panel(GameStyle.INK))
	center.add_child(_card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	_card.add_child(margin)

	_content = VBoxContainer.new()
	_content.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_theme_constant_override("separation", 12)
	margin.add_child(_content)

	var visual_box := CenterContainer.new()
	visual_box.custom_minimum_size = Vector2(0, CHECK_SIZE + 6)
	_content.add_child(visual_box)

	_spinner = Spinner.new()
	_spinner.custom_minimum_size = Vector2(SPINNER_SIZE, SPINNER_SIZE)
	_spinner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_box.add_child(_spinner)

	_check = CheckMark.new()
	_check.custom_minimum_size = Vector2(CHECK_SIZE, CHECK_SIZE)
	_check.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_check.visible = false
	visual_box.add_child(_check)

	_title_lbl = Label.new()
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameStyle.label(_title_lbl, 18, GameStyle.PAPER, 0, GameStyle.INK, true)
	_content.add_child(_title_lbl)

	_sub_lbl = Label.new()
	_sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub_lbl.custom_minimum_size = Vector2(360, 34)
	GameStyle.label(_sub_lbl, 12, GameStyle.PAPER_DIM)
	_content.add_child(_sub_lbl)

	_scan = ScanBar.new()
	_scan.custom_minimum_size = SCAN_SIZE
	_scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var scan_box := CenterContainer.new()
	scan_box.add_child(_scan)
	_content.add_child(scan_box)

	_elapsed_lbl = Label.new()
	_elapsed_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameStyle.label(_elapsed_lbl, 11, GameStyle.GREY)
	_content.add_child(_elapsed_lbl)

	_done_btn = Button.new()
	_done_btn.text = "完 成"
	_done_btn.custom_minimum_size = Vector2(120, 34)
	_done_btn.focus_mode = Control.FOCUS_NONE
	_done_btn.visible = false
	GameStyle.button(_done_btn, GameStyle.GOLD, GameStyle.GOLD_EDGE, 14, GameStyle.INK_TEXT, 5.0)
	_done_btn.pressed.connect(func() -> void: completed.emit())
	var done_box := CenterContainer.new()
	done_box.add_child(_done_btn)
	_content.add_child(done_box)

## 进入发送态。stage 是首句状态文案（如「正在整理反馈内容…」）。
func show_sending(stage: String = "正在发送反馈…") -> void:
	state = State.SENDING
	_clock = 0.0
	_last_redraw = 0.0
	_elapsed = 0.0
	visible = true
	_spinner.visible = true
	_scan.visible = true
	_check.visible = false
	_done_btn.visible = false
	_title_lbl.text = "正在发送反馈…"
	_sub_lbl.text = stage
	_elapsed_lbl.text = ""
	_kill_fade()
	modulate.a = 0.0
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(self, "modulate:a", 1.0, GameStyle.UI_FADE_IN)

## 更新阶段文案（整理内容 → 上传截图 → 投递邮件）
func set_stage(text: String) -> void:
	if is_instance_valid(_sub_lbl):
		_sub_lbl.text = text

## 进入成功态：对勾拍入 + 完成按钮出现
func show_success() -> void:
	state = State.SUCCESS
	visible = true
	modulate.a = 1.0
	_kill_fade()
	_spinner.visible = false
	_scan.visible = false
	_check.visible = true
	_done_btn.visible = true
	_title_lbl.text = "反馈已送达"
	_sub_lbl.text = "感谢道友的反馈，作者会尽快查看"
	_elapsed_lbl.text = ""
	GameStyle.pop_in(_check, 0.0, 0.7)
	GameStyle.pop_in(_done_btn, 0.12, 0.85)

## 淡出覆盖层（失败时回到表单）
func hide_overlay() -> void:
	if not visible:
		return
	_kill_fade()
	_fade_tw = create_tween()
	_fade_tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tw.tween_property(self, "modulate:a", 0.0, GameStyle.UI_FADE_OUT)
	_fade_tw.tween_callback(func() -> void:
		# 淡出途中若又被 show_sending/show_success 拉起，这次回调不能把新内容藏掉
		if _fade_tw != null and _fade_tw.is_valid() and modulate.a <= 0.01:
			visible = false
	)

func _kill_fade() -> void:
	if _fade_tw != null and _fade_tw.is_valid():
		_fade_tw.kill()
	_fade_tw = null

func _process(delta: float) -> void:
	if not visible or state != State.SENDING:
		return
	_clock += delta
	_elapsed += delta
	if _elapsed >= 8.0:
		_elapsed_lbl.text = "网络较慢，已等待 %d 秒…" % int(_elapsed)
	if _clock - _last_redraw >= REDRAW_INTERVAL:
		_last_redraw = _clock
		_spinner.clock = _clock
		_scan.clock = _clock
		_spinner.queue_redraw()
		_scan.queue_redraw()

# ---------------- 自绘小件 ----------------

## 旋转弧环：底圈淡墨 + 一段主色弧 + 弧头圆点
class Spinner extends Control:
	var clock: float = 0.0

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(c.x, c.y) - 6.0
		if r <= 2.0:
			return
		draw_arc(c, r, 0.0, TAU, 64, GameStyle.with_alpha(GameStyle.INK, 0.14), 5.0, true)
		var start := clock * 4.2
		var sweep := TAU * 0.30
		draw_arc(c, r, start, start + sweep, 40, GameStyle.GOLD, 5.0, true)
		draw_circle(c + Vector2.RIGHT.rotated(start + sweep) * r, 3.2, GameStyle.GOLD_EDGE)

## 金色扫描条：墨框轨道 + 来回滑动的金色块
class ScanBar extends Control:
	var clock: float = 0.0

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w <= 4.0 or h <= 2.0:
			return
		draw_rect(Rect2(Vector2.ZERO, size), GameStyle.with_alpha(GameStyle.INK, 0.10), true)
		draw_rect(Rect2(Vector2.ZERO, size), GameStyle.INK, false, 2.0)
		var block_w := w * 0.28
		var t := fmod(clock * 0.55, 1.0)
		t = absf(t * 2.0 - 1.0)          # 往返
		var x := t * maxf(0.0, w - block_w)
		draw_rect(Rect2(x + 2.0, 2.0, maxf(0.0, block_w - 4.0), h - 4.0), GameStyle.GOLD, true)

## 成功对勾：金色方块 + 黑粗勾
class CheckMark extends Control:
	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w <= 8.0 or h <= 8.0:
			return
		draw_rect(Rect2(Vector2.ZERO, size), GameStyle.GOLD, true)
		draw_rect(Rect2(Vector2.ZERO, size), GameStyle.INK, false, 3.0)
		var pts := PackedVector2Array([
			Vector2(w * 0.24, h * 0.53),
			Vector2(w * 0.43, h * 0.72),
			Vector2(w * 0.78, h * 0.30),
		])
		draw_polyline(pts, GameStyle.INK, 7.0, true)
