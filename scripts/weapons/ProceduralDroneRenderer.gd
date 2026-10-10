class_name ProceduralDroneRenderer
extends Node2D

## 纯矢量环绕灵宝渲染器（冷冽国风）
## 为御灵系法宝（灵蝶、寒泉玉莲、混元钟）提供细腻的自转、振翅与流光视觉

enum DroneKind {
	LINGDIE,        ## 灵蝶：碧翠灵羽、生机透光羽翼、双翅轻盈扑动
	HANQUAN_YULIAN, ## 寒泉玉莲：晶莹冰魄青莲、层叠八瓣寒晶、中央灵蕊
	HUNYUAN_ZHONG   ## 混元钟：玄铁青铜古钟、暗金饕餮符印、钟首盘龙纽
}

@export var kind: DroneKind = DroneKind.LINGDIE
@export var star: int = 1

var _anim_time: float = 0.0

func _process(delta: float) -> void:
	_anim_time += delta
	queue_redraw()

func _draw() -> void:
	match kind:
		DroneKind.LINGDIE:
			_draw_spirit_butterfly()
		DroneKind.HANQUAN_YULIAN:
			_draw_ice_lotus()
		DroneKind.HUNYUAN_ZHONG:
			_draw_ancient_bell()

# ----------------- 1. 灵蝶 (生机碧翠灵羽 + 振翅扑动) -----------------
func _draw_spirit_butterfly() -> void:
	# 振翅周期 (约 5Hz)
	var wing_flap := sin(_anim_time * 12.0)
	var flap_x := 0.4 + 0.6 * absf(wing_flap)

	var wing_col_base := Color(0.20, 0.65, 0.45, 0.75)
	var wing_col_edge := Color(0.55, 0.95, 0.75, 0.90)
	if star >= 2:
		wing_col_edge = Color(0.95, 0.85, 0.40, 0.95)

	# 左前翅
	var left_fore := PackedVector2Array([
		Vector2(0, 0),
		Vector2(-14.0 * flap_x, -12.0),
		Vector2(-12.0 * flap_x, -2.0),
		Vector2(-2.0, 2.0)
	])
	draw_colored_polygon(left_fore, wing_col_base)
	draw_polyline(left_fore, wing_col_edge, 1.2, true)

	# 右前翅
	var right_fore := PackedVector2Array([
		Vector2(0, 0),
		Vector2(14.0 * flap_x, -12.0),
		Vector2(12.0 * flap_x, -2.0),
		Vector2(2.0, 2.0)
	])
	draw_colored_polygon(right_fore, wing_col_base)
	draw_polyline(right_fore, wing_col_edge, 1.2, true)

	# 左后翅 (更小巧)
	var left_hind := PackedVector2Array([
		Vector2(0, 2.0),
		Vector2(-10.0 * flap_x, 6.0),
		Vector2(-7.0 * flap_x, 12.0),
		Vector2(0, 5.0)
	])
	draw_colored_polygon(left_hind, wing_col_base)
	draw_polyline(left_hind, wing_col_edge, 1.0, true)

	# 右后翅
	var right_hind := PackedVector2Array([
		Vector2(0, 2.0),
		Vector2(10.0 * flap_x, 6.0),
		Vector2(7.0 * flap_x, 12.0),
		Vector2(0, 5.0)
	])
	draw_colored_polygon(right_hind, wing_col_base)
	draw_polyline(right_hind, wing_col_edge, 1.0, true)

	# 蝶身脊柱与灵须
	draw_line(Vector2(0, -7.0), Vector2(0, 7.0), Color(0.10, 0.14, 0.18), 2.0, true)
	draw_circle(Vector2(0, -7.0), 1.6, Color(0.92, 0.95, 0.98))
	# 触角
	draw_line(Vector2(0, -7.0), Vector2(-4.0, -11.0), Color(0.92, 0.95, 0.98), 0.8, true)
	draw_line(Vector2(0, -7.0), Vector2(4.0, -11.0), Color(0.92, 0.95, 0.98), 0.8, true)

# ----------------- 2. 寒泉玉莲 (晶莹冰魄层叠八瓣莲台) -----------------
func _draw_ice_lotus() -> void:
	var rot := _anim_time * 1.2
	var petals := 8
	var outer_r := 13.0
	var inner_r := 4.5

	# 外层八瓣青莲
	for i in range(petals):
		var ang := float(i) / float(petals) * TAU + rot
		var tip := Vector2(cos(ang) * outer_r, sin(ang) * outer_r)
		var left_ang := ang - 0.28
		var right_ang := ang + 0.28
		var side_l := Vector2(cos(left_ang) * (outer_r * 0.6), sin(left_ang) * (outer_r * 0.6))
		var side_r := Vector2(cos(right_ang) * (outer_r * 0.6), sin(right_ang) * (outer_r * 0.6))

		var poly := PackedVector2Array([Vector2.ZERO, side_l, tip, side_r])
		var col := Color(0.40, 0.75, 0.95, 0.65) if (i % 2 == 0) else Color(0.65, 0.90, 1.0, 0.85)
		draw_colored_polygon(poly, col)
		draw_polyline(PackedVector2Array([side_l, tip, side_r]), Color(0.95, 0.98, 1.0, 0.9), 1.0, false)

	# 内层灵蕊
	draw_circle(Vector2.ZERO, inner_r, Color(0.20, 0.45, 0.70))
	draw_circle(Vector2.ZERO, inner_r * 0.5, Color(1.0, 0.95, 0.80) if star >= 2 else Color(0.90, 0.98, 1.0))

# ----------------- 3. 混元古钟 (玄铁青铜古钟 + 暗金云雷纹) -----------------
func _draw_ancient_bell() -> void:
	# 钟体轮廓 (上窄下阔梯形钟身)
	var bell_poly := PackedVector2Array([
		Vector2(-6.0, -9.0),
		Vector2(6.0, -9.0),
		Vector2(9.5, 6.0),
		Vector2(11.0, 9.0),
		Vector2(-11.0, 9.0),
		Vector2(-9.5, 6.0)
	])
	# 玄铁沉稳底色
	draw_colored_polygon(bell_poly, Color(0.18, 0.22, 0.28))
	# 边缘暗金/青铜包边
	draw_polyline(bell_poly, Color(0.78, 0.68, 0.35) if star >= 2 else Color(0.40, 0.55, 0.50), 1.4, true)

	# 钟钮 (顶部吊环)
	draw_arc(Vector2(0, -10.5), 3.0, PI, TAU, 8, Color(0.85, 0.75, 0.38), 1.5)

	# 钟腹云雷横纹
	draw_line(Vector2(-8.0, 0), Vector2(8.0, 0), Color(0.85, 0.75, 0.38, 0.8), 1.2, true)
	draw_line(Vector2(-7.0, -4.0), Vector2(7.0, -4.0), Color(0.85, 0.75, 0.38, 0.6), 1.0, true)

	# 钟口下沿口缘
	draw_line(Vector2(-11.0, 9.0), Vector2(11.0, 9.0), Color(0.92, 0.82, 0.42), 2.0, true)
