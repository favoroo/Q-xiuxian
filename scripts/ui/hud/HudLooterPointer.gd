class_name HudLooterPointer
extends Control

## 屏幕边缘金蟾方位指引（2026-10-27 新增）：
## 当场上存在招财金蟾（always_flee）且金蟾不在屏幕中心视野时，在屏幕边缘显示金色指引箭头与状态标；
## 落单仓皇遁逃时，展示金色呼吸脉冲与倒计时秒数（「遁逃 5.2s」），彻底杜绝玩家找不到怪或空场傻等。

var _looter_ref: Node2D = null
var _pulse_t: float = 0.0

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
	var margin := Vector2(40.0, 36.0)

	# 判定是否在屏幕内部较深区域
	var is_deep_inside: bool = (
		target_screen_pos.x >= 70.0 and target_screen_pos.x <= vp_size.x - 70.0 and
		target_screen_pos.y >= 70.0 and target_screen_pos.y <= vp_size.y - 70.0
	)
	var is_panic: bool = bool(_looter_ref.get("_flee_panic"))
	if is_deep_inside and not is_panic:
		return

	var center: Vector2 = vp_size * 0.5
	var to_target: Vector2 = target_screen_pos - center
	if to_target.is_zero_approx():
		return

	# 屏幕边缘投射
	var half_w: float = center.x - margin.x
	var half_h: float = center.y - margin.y
	var scale_x: float = half_w / maxf(absf(to_target.x), 0.001)
	var scale_y: float = half_h / maxf(absf(to_target.y), 0.001)
	var t: float = minf(scale_x, scale_y)
	var clamped_pos: Vector2 = center + to_target * minf(t, 1.0)
	if is_deep_inside:
		clamped_pos = target_screen_pos + Vector2(0.0, -32.0)

	var dir := to_target.normalized()
	var gold_col: Color = GameStyle.GOLD
	var pulse_alpha: float = 0.85 + 0.15 * sin(_pulse_t) if is_panic else 0.95
	var draw_col := Color(gold_col.r, gold_col.g, gold_col.b, pulse_alpha)

	# 1. 箭头多边形（指着金蟾）
	if not is_deep_inside:
		var arrow_pts: PackedVector2Array = [
			clamped_pos + dir * 10.0,
			clamped_pos - dir * 6.0 + Vector2(-dir.y, dir.x) * 6.0,
			clamped_pos - dir * 6.0 - Vector2(-dir.y, dir.x) * 6.0
		]
		draw_colored_polygon(arrow_pts, draw_col)

	# 2. 状态标签底框与文字
	var esc_time: float = float(_looter_ref.get("_flee_escape_timer"))
	var tag_text: String = ""
	if is_panic and esc_time > 0.0:
		tag_text = "◆ 遁逃 %.1fs ◆" % esc_time
	else:
		tag_text = "◆ 金蟾"

	var f := GameStyle.tag_font()
	var f_size := 11
	var text_size: Vector2 = f.get_string_size(tag_text, HORIZONTAL_ALIGNMENT_LEFT, -1, f_size)
	var tag_pos := clamped_pos - dir * 18.0 - text_size * 0.5
	if is_deep_inside:
		tag_pos = clamped_pos - text_size * 0.5

	tag_pos.x = clampf(tag_pos.x, 8.0, vp_size.x - text_size.x - 12.0)
	tag_pos.y = clampf(tag_pos.y, 8.0, vp_size.y - text_size.y - 10.0)

	var pad := Vector2(5.0, 3.0)
	var bg_rect := Rect2(tag_pos - pad, text_size + pad * 2.0)
	draw_rect(bg_rect, GameStyle.INK)
	draw_rect(bg_rect, draw_col, false, 1.2)
	var font_col := GameStyle.FX_HDR_GOLD if is_panic else GameStyle.PAPER
	draw_string(f, tag_pos + Vector2(0.0, f.get_ascent(f_size)), tag_text, HORIZONTAL_ALIGNMENT_LEFT, -1, f_size, font_col)
