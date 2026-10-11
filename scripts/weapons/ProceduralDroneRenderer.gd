class_name ProceduralDroneRenderer
extends Node2D

## 纯矢量环绕灵宝渲染器（冷冽国风）
## 为御灵系法宝（灵蝶、寒泉玉莲、混元钟）提供细腻的自转、振翅与流光视觉

enum DroneKind {
	LINGDIE,        ## 灵蝶：碧翠灵羽、生机透光羽翼、双翅轻盈扑动
	HANQUAN_YULIAN, ## 寒泉玉莲：晶莹冰魄青莲、层叠八瓣寒晶、中央灵蕊
	HUNYUAN_ZHONG,  ## 混元钟：玄铁青铜古钟、暗金饕餮符印、钟首盘龙纽
	HAOJIN_LUN,     ## 昊金轮：旋转金轮、辐条流光（2026-10-10 新增）
	LIHUO_YA,       ## 离火鸦：火羽扑翼、焰尾曳光（2026-10-10 新增）
	XUANWU_PEI,     ## 玄武佩：玄黄玉璧、云纹护身（2026-10-10 新增）
	LING_HU         ## 灵狐：祭坛召唤灵兽，冷白狐形地面走兽（2026-10-11 新增）
}

@export var kind: DroneKind = DroneKind.LINGDIE
@export var star: int = 1

## 跑动权重（0=站立 1=全速）：仅地面走兽形态（LING_HU）消费，由宿主按实际移速灌入
var move_blend: float = 0.0

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
		DroneKind.HAOJIN_LUN:
			_draw_golden_wheel()
		DroneKind.LIHUO_YA:
			_draw_fire_crow()
		DroneKind.XUANWU_PEI:
			_draw_jade_pendant()
		DroneKind.LING_HU:
			_draw_spirit_fox()

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

# ----------------- 4. 昊金轮 (自转金轮 + 六辐流光) -----------------
func _draw_golden_wheel() -> void:
	var rot := _anim_time * 4.0
	var rim := Color(0.95, 0.80, 0.30) if star >= 2 else Color(0.72, 0.58, 0.22)
	# 六辐轮辐
	for i in range(6):
		var ang := float(i) / 6.0 * TAU + rot
		draw_line(Vector2.ZERO, Vector2(cos(ang) * 11.0, sin(ang) * 11.0), rim, 1.6, true)
	# 外轮圈与轴心
	draw_arc(Vector2.ZERO, 11.0, 0, TAU, 24, rim, 2.2, true)
	draw_arc(Vector2.ZERO, 7.5, 0, TAU, 18, Color(0.98, 0.90, 0.55, 0.5), 1.0, true)
	draw_circle(Vector2.ZERO, 3.0, Color(1.0, 0.92, 0.55))
	draw_circle(Vector2.ZERO, 1.4, Color(0.35, 0.26, 0.10))

# ----------------- 5. 离火鸦 (火羽扑翼 + 焰尾) -----------------
func _draw_fire_crow() -> void:
	var wing_flap := sin(_anim_time * 11.0)
	var flap_x := 0.45 + 0.55 * absf(wing_flap)
	var body := Color(0.45, 0.12, 0.08)
	var flame := Color(1.0, 0.55, 0.15, 0.85) if star < 2 else Color(1.0, 0.72, 0.25, 0.95)
	# 双翼（火羽）
	for side in [-1.0, 1.0]:
		var wing := PackedVector2Array([
			Vector2(0, -1.0),
			Vector2(side * 13.0 * flap_x, -9.0),
			Vector2(side * 10.0 * flap_x, 0.5),
			Vector2(side * 2.0, 2.5)
		])
		draw_colored_polygon(wing, Color(0.85, 0.35, 0.10, 0.80))
		draw_polyline(wing, flame, 1.1, true)
	# 焰尾三条
	for i in range(-1, 2):
		var sway := sin(_anim_time * 7.0 + float(i)) * 2.0
		draw_line(Vector2(float(i) * 2.5, 4.0), Vector2(float(i) * 3.5 + sway, 12.0), flame, 1.4, true)
	# 鸦身与金目
	draw_circle(Vector2.ZERO, 4.2, body)
	draw_circle(Vector2(0, -5.2), 2.2, body)
	draw_circle(Vector2(1.2, -5.8), 0.9, Color(1.0, 0.85, 0.30))

# ----------------- 6. 玄武佩 (玄黄玉璧 + 云纹) -----------------
func _draw_jade_pendant() -> void:
	var bob := sin(_anim_time * 2.4) * 1.2
	var off := Vector2(0, bob)
	var jade := Color(0.42, 0.50, 0.30) if star < 2 else Color(0.62, 0.58, 0.30)
	# 玉璧外环与内孔（璧形）
	draw_arc(off, 10.5, 0, TAU, 24, jade, 3.4, true)
	draw_arc(off, 4.0, 0, TAU, 16, Color(0.88, 0.80, 0.50), 1.4, true)
	# 璧面云纹两道
	draw_arc(off + Vector2(0, -2.5), 6.8, PI * 0.15, PI * 0.85, 10, Color(0.90, 0.84, 0.55, 0.8), 1.0, true)
	draw_arc(off + Vector2(0, 2.5), 6.8, PI * 1.15, PI * 1.85, 10, Color(0.90, 0.84, 0.55, 0.8), 1.0, true)
	# 顶部系绳结
	draw_line(off + Vector2(0, -10.5), off + Vector2(0, -13.5), Color(0.70, 0.30, 0.20), 1.6, true)

# ----------------- 7. 灵狐 (祭坛召唤灵兽：冷白狐形地面走兽) -----------------
## 体型比御灵法宝大一圈（它是地面走兽，不是环绕小件），碰撞半径 14 与画幅同源。
## 面朝 +x，朝向由宿主翻转 scale.x；四条腿按 move_blend 跑动交错，尾巴常时扫雪式摆动。
func _draw_spirit_fox() -> void:
	var body_col := Color(0.82, 0.88, 0.95)
	var edge_col := Color(0.45, 0.80, 1.00)
	var glow_col := Color(0.60, 0.95, 1.00)

	# 大尾巴（身后，常时摆动）
	var sway := sin(_anim_time * 3.2) * 2.5
	var tail := PackedVector2Array([
		Vector2(-10.0, -2.0),
		Vector2(-22.0, -10.0 + sway),
		Vector2(-26.0, -2.0 + sway),
		Vector2(-20.0, 4.0 + sway * 0.5),
		Vector2(-9.0, 4.0)
	])
	draw_colored_polygon(tail, body_col.darkened(0.15))
	var tail_outline := tail.duplicate()
	tail_outline.append(tail[0])
	draw_polyline(tail_outline, edge_col, 1.2, true)

	# 四条腿（跑动时前后交错摆）
	var leg_phase := [0.0, PI, PI, 0.0]
	var leg_x := [12.0, 9.0, -4.0, -7.0]
	for i in range(4):
		var swing: float = sin(_anim_time * 10.0 + leg_phase[i]) * 3.0 * move_blend
		draw_line(Vector2(leg_x[i], 6.0), Vector2(leg_x[i] + swing, 14.0), body_col.darkened(0.25), 2.0, true)

	# 躯干（横卧椭圆，16 边形）
	var body := PackedVector2Array()
	for i in range(16):
		var a := float(i) / 16.0 * TAU
		body.append(Vector2(cos(a) * 14.0, sin(a) * 8.0))
	draw_colored_polygon(body, body_col)
	var body_outline := body.duplicate()
	body_outline.append(body[0])
	draw_polyline(body_outline, edge_col, 1.2, true)

	# 头（前上方）+ 吻部
	draw_circle(Vector2(13.0, -8.0), 6.0, body_col)
	draw_arc(Vector2(13.0, -8.0), 6.0, 0.0, TAU, 16, edge_col, 1.2, true)
	var snout := PackedVector2Array([
		Vector2(16.0, -8.0),
		Vector2(21.0, -6.5),
		Vector2(16.5, -4.5)
	])
	draw_colored_polygon(snout, body_col.darkened(0.1))

	# 双耳（尖立）
	var ear_l := PackedVector2Array([Vector2(10.0, -12.0), Vector2(9.0, -19.0), Vector2(13.0, -14.0)])
	var ear_r := PackedVector2Array([Vector2(14.0, -13.0), Vector2(15.5, -20.0), Vector2(17.5, -12.5)])
	draw_colored_polygon(ear_l, body_col)
	draw_polyline(ear_l, edge_col, 1.0, true)
	draw_colored_polygon(ear_r, body_col)
	draw_polyline(ear_r, edge_col, 1.0, true)

	# 霜蓝灵目（发光点）
	draw_circle(Vector2(15.0, -9.0), 1.6, glow_col)
	draw_circle(Vector2(15.0, -9.0), 0.7, Color.WHITE)
