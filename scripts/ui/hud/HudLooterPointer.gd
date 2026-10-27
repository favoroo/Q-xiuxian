class_name HudLooterPointer
extends Control

## 屏幕边缘金蟾方位指引（2026-10-27 优化）：
## 仅在招财金蟾（always_flee）脱离玩家屏幕视野（屏幕外）时，在屏幕边缘显示醒目的金色指示箭头与「金蟾」标签；
## 当金蟾在屏幕内时保持画面清爽，不显示任何悬浮文字或倒计时。

var _looter_ref: Node2D = null
var _pulse_t: float = 0.0

const SAFE_MARGIN := 36.0  ## 离屏判断边距（px）：进入屏幕此安全区内即视为在场内，隐藏指示器

func _ready() -> void:
	name = "HudLooterPointer"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(delta: float) -> void:
	_pulse_t += delta * 6.0
	if _looter_ref == null or not is_instance_valid(_looter_ref) or not _looter_ref.is_inside_tree():
		_looter_ref = _find_live_looter()

	if _looter_ref == null or not is_instance_valid(_looter_ref):
		if visible:
			visible = false
		return

	if _looter_ref.get("dying") or _looter_ref.get("_flee_burrowing"):
		if visible:
			visible = false
		return

	if not visible:
		visible = true
	queue_redraw()

func _find_live_looter() -> Node2D:
	for e in GameManager.live_enemies:
		if e != null and is_instance_valid(e) and e.get("always_flee"):
			return e
	return null

func _draw() -> void:
	if _looter_ref == null or not is_instance_valid(_looter_ref):
		return
	var vp := get_viewport()
	if vp == null:
		return
	var canvas_tf := vp.get_canvas_transform()
	var target_screen_pos: Vector2 = canvas_tf * _looter_ref.global_position
	var vp_size := get_viewport_rect().size

	# 1. 视线内判定：金蟾只要在屏幕视野内，彻底不显示任何指针或头顶悬浮文字
	var is_on_screen: bool = (
		target_screen_pos.x >= SAFE_MARGIN and target_screen_pos.x <= vp_size.x - SAFE_MARGIN and
		target_screen_pos.y >= SAFE_MARGIN and target_screen_pos.y <= vp_size.y - SAFE_MARGIN
	)
	if is_on_screen:
		return

	var center: Vector2 = vp_size * 0.5
	var to_target: Vector2 = target_screen_pos - center
	if to_target.is_zero_approx():
		return

	# 2. 屏幕边缘贴边投射
	var margin := Vector2(38.0, 32.0)
	var half_w: float = center.x - margin.x
	var half_h: float = center.y - margin.y
	var scale_x: float = half_w / maxf(absf(to_target.x), 0.001)
	var scale_y: float = half_h / maxf(absf(to_target.y), 0.001)
	var t: float = minf(scale_x, scale_y)
	var clamped_pos: Vector2 = center + to_target * minf(t, 1.0)
	var dir := to_target.normalized()

	var is_panic: bool = bool(_looter_ref.get("_flee_panic"))
	var base_gold: Color = GameStyle.GOLD
	var gold_col: Color = base_gold if not is_panic else base_gold.lerp(Color(1.0, 0.55, 0.1), 0.35 + 0.35 * sin(_pulse_t))

	# 3. 醒目外指三角箭头（双层：纯黑底描边 + 亮金填充，保证在任何地貌上极度清晰）
	var tip: Vector2 = clamped_pos + dir * 11.0
	var side_vec: Vector2 = Vector2(-dir.y, dir.x) * 6.5
	var base_center: Vector2 = clamped_pos - dir * 4.0
	var arrow_pts: PackedVector2Array = [
		tip,
		base_center + side_vec,
		base_center - side_vec
	]
	# 黑边外扩
	var outline_pts: PackedVector2Array = [
		tip + dir * 2.0,
		base_center + side_vec * 1.35 - dir * 1.5,
		base_center - side_vec * 1.35 - dir * 1.5
	]
	draw_colored_polygon(outline_pts, GameStyle.INK)
	draw_colored_polygon(arrow_pts, gold_col)

	# 4. 「金 蟾」标牌（金底黑字高对比度设计，彻底解决看不清问题）
	var tag_text := "金 蟾"
	var font := GameStyle.tag_font()
	var font_size := 12
	var text_size: Vector2 = font.get_string_size(tag_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)

	var tag_pos := clamped_pos - dir * 20.0 - text_size * 0.5
	tag_pos.x = clampf(tag_pos.x, 8.0, vp_size.x - text_size.x - 12.0)
	tag_pos.y = clampf(tag_pos.y, 8.0, vp_size.y - text_size.y - 10.0)

	var pad := Vector2(6.0, 3.0)
	var bg_rect := Rect2(tag_pos - pad, text_size + pad * 2.0)

	# 标牌外黑描边 + 金色亮底
	draw_rect(bg_rect.grow(1.5), GameStyle.INK)
	draw_rect(bg_rect, gold_col)

	# 墨黑粗字（INK_TEXT 在亮金底上 100% 对比度顶格清晰）
	var text_draw_pos := tag_pos + Vector2(0.0, font.get_ascent(font_size))
	draw_string(font, text_draw_pos, tag_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, GameStyle.INK_TEXT)
