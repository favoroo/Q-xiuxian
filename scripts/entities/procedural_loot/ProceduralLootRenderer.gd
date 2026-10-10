class_name ProceduralLootRenderer
extends Node2D

## 掉落物程序化矢量渲染器（空洞冷冽国风）
## 涵盖八面菱形灵石水晶（普通/金色）、生机回春灵玉、九幽玄铁灵匣

enum LootType {
	GEM_BLUE,     ## 普通八面菱形幽蓝水晶
	GEM_GOLD,     ## 特殊八面菱形耀金水晶
	HEAL_ORB,     ## 碧翠灵心玉 / 生机回春魄
	CHEST         ## 九幽玄铁八角灵匣
}

@export var loot_type: LootType = LootType.GEM_BLUE:
	set(val):
		loot_type = val
		queue_redraw()

## 灵玉状态：true 时为满血待命灰相
@export var is_waiting: bool = false:
	set(val):
		is_waiting = val
		queue_redraw()

## 灵匣状态参数
@export var chest_total_hits: int = 3
@export var chest_left_hits: int = 3:
	set(val):
		chest_left_hits = val
		queue_redraw()

var _time: float = 0.0

func _ready() -> void:
	# 错开每颗晶石的时间相位，避免全场完全同频机械闪烁
	_time = randf() * 10.0

func _process(delta: float) -> void:
	_time += delta
	# 仅微幅驱动晶体反光高光与生机脉动，每隔几帧重绘或低频重绘
	queue_redraw()

func _draw() -> void:
	match loot_type:
		LootType.GEM_BLUE:
			_draw_rhombus_crystal(false)
		LootType.GEM_GOLD:
			_draw_rhombus_crystal(true)
		LootType.HEAL_ORB:
			_draw_heal_orb()
		LootType.CHEST:
			_draw_void_chest()

# ==============================================================================
# 1. 八面立体菱形水晶（Octahedral Crystal）
# ==============================================================================
func _draw_rhombus_crystal(is_gold: bool) -> void:
	var w: float = 12.0
	var h: float = 20.0
	var half_w: float = w * 0.5
	var half_h: float = h * 0.5
	var center_y: float = 1.0  # 晶心微凸顶点

	# 颜色定义
	var col_glow: Color
	var col_hi: Color
	var col_mid: Color
	var col_dark: Color
	var col_edge: Color

	if is_gold:
		col_glow = Color(1.0, 0.78, 0.20, 0.22)
		col_hi = Color(1.0, 0.98, 0.78, 0.98)
		col_mid = Color(0.98, 0.75, 0.20, 0.95)
		col_dark = Color(0.48, 0.32, 0.06, 0.95)
		col_edge = Color(1.0, 0.90, 0.50, 0.9)
	else:
		col_glow = Color(0.25, 0.80, 1.0, 0.22)
		col_hi = Color(0.85, 0.96, 1.0, 0.98)
		col_mid = Color(0.25, 0.68, 0.95, 0.95)
		col_dark = Color(0.08, 0.22, 0.44, 0.95)
		col_edge = Color(0.60, 0.90, 1.0, 0.9)

	# 柔光外晕
	var pulse: float = sin(_time * 3.5) * 0.08 + 1.0
	var glow_poly := PackedVector2Array([
		Vector2(0, -half_h * 1.35 * pulse),
		Vector2(half_w * 1.35 * pulse, center_y),
		Vector2(0, half_h * 1.35 * pulse),
		Vector2(-half_w * 1.35 * pulse, center_y)
	])
	draw_colored_polygon(glow_poly, col_glow)

	# 4 个立体切面（双锥八面体投影）
	var top := Vector2(0, -half_h)
	var bottom := Vector2(0, half_h)
	var left := Vector2(-half_w, center_y)
	var right := Vector2(half_w, center_y)
	var core := Vector2(0, center_y)

	# 上左面（次亮向光）
	var face_tl := PackedVector2Array([top, core, left])
	draw_colored_polygon(face_tl, col_mid)

	# 上右面（极亮强光切面）
	var face_tr := PackedVector2Array([top, right, core])
	draw_colored_polygon(face_tr, col_hi)

	# 下左面（深暗背阴底面）
	var face_bl := PackedVector2Array([left, core, bottom])
	draw_colored_polygon(face_bl, col_dark)

	# 下右面（折射次暗切面）
	var face_br := PackedVector2Array([core, right, bottom])
	draw_colored_polygon(face_br, col_mid.darkened(0.25))

	# 中脊高光棱线与外轮廓
	draw_line(top, bottom, col_hi, 1.2, true)
	draw_line(left, right, col_edge.darkened(0.1), 1.0, true)
	
	var outline := PackedVector2Array([top, right, bottom, left, top])
	draw_polyline(outline, col_edge, 1.2, true)

	# 顶点锐利耀斑闪光
	var flare_alpha: float = (sin(_time * 4.0) * 0.5 + 0.5) * 0.8
	if flare_alpha > 0.4:
		var flare_col := Color(1.0, 1.0, 1.0, (flare_alpha - 0.4) * 1.6)
		draw_circle(core, 1.4, flare_col)

# ==============================================================================
# 2. 碧翠灵心玉 / 生机回春魄（Emerald Soul Gem）
# ==============================================================================
func _draw_heal_orb() -> void:
	var w: float = 14.0
	var h: float = 19.0
	var pulse: float = sin(_time * 3.0) * 0.1 + 0.95

	var col_body: Color
	var col_core: Color
	var col_rim: Color
	var col_halo: Color

	if is_waiting:
		# 满血待命暗哑灰相
		col_body = Color(0.28, 0.35, 0.30, 0.85)
		col_core = Color(0.45, 0.55, 0.48, 0.70)
		col_rim = Color(0.50, 0.60, 0.52, 0.65)
		col_halo = Color(0.2, 0.3, 0.25, 0.0)
	else:
		# 生机透亮翡翠青玉
		col_body = Color(0.12, 0.68, 0.42, 0.95)
		col_core = Color(0.65, 1.25, 0.85, 0.98)
		col_rim = Color(0.85, 1.15, 0.95, 0.95)
		col_halo = Color(0.20, 0.85, 0.50, 0.22)

	# 外围生机晕轮
	if not is_waiting:
		draw_circle(Vector2(0, 2), 12.0 * pulse, col_halo)

	# 温润水滴灵玉外廓（贝塞尔平滑点集）
	var pts := PackedVector2Array()
	var segments := 24
	var top := Vector2(0, -h * 0.5)
	pts.append(top)
	for i in range(segments + 1):
		var angle := PI * 0.05 + (PI * 0.9) * (float(i) / float(segments))
		var r_x := w * 0.5
		var r_y := h * 0.38
		var center := Vector2(0, h * 0.12)
		pts.append(center + Vector2(cos(angle) * r_x, sin(angle) * r_y))
	pts.append(top)

	# 绘制玉髓本体
	draw_colored_polygon(pts, col_body)
	draw_polyline(pts, col_rim, 1.3, true)

	# 内部浮动的晶莹灵核
	var inner_center := Vector2(0, 1.5)
	if not is_waiting:
		var inner_pulse := sin(_time * 4.5) * 0.15 + 0.9
		draw_circle(inner_center, 3.8 * inner_pulse, col_core)
		draw_circle(inner_center + Vector2(-1.0, -1.2), 1.2, Color(1.0, 1.0, 1.0, 0.9))
	else:
		draw_circle(inner_center, 2.8, col_core)

# ==============================================================================
# 3. 九幽玄铁八角灵匣（Void Reliquary）
# ==============================================================================
func _draw_void_chest() -> void:
	var w: float = 34.0
	var h: float = 26.0
	var bevel: float = 5.5

	var col_iron := Color(0.06, 0.08, 0.12, 1.0)        # 玄黑铸铁
	var col_edge := Color(0.28, 0.36, 0.46, 1.0)        # 冷青铜边饰
	var col_gold := Color(0.88, 0.72, 0.24, 0.95)       # 暗金包角与符扣
	var col_seal := Color(0.78, 0.22, 0.20, 0.92)       # 朱砂封灵印
	var col_glow := Color(0.25, 0.85, 1.0, 0.35)        # 灵核漏光

	# 1. 匣底八角体
	var hw := w * 0.5
	var hh := h * 0.5
	var body_poly := PackedVector2Array([
		Vector2(-hw + bevel, -hh),
		Vector2(hw - bevel, -hh),
		Vector2(hw, -hh + bevel),
		Vector2(hw, hh - bevel),
		Vector2(hw - bevel, hh),
		Vector2(-hw + bevel, hh),
		Vector2(-hw, hh - bevel),
		Vector2(-hw, -hh + bevel)
	])
	draw_colored_polygon(body_poly, col_iron)
	draw_polyline(body_poly, col_edge, 1.4, true)

	# 2. 匣盖层次横梁
	var lid_y := -hh + 8.0
	draw_line(Vector2(-hw + 2.0, lid_y), Vector2(hw - 2.0, lid_y), col_edge, 1.2)

	# 3. 四角鎏金护甲
	var corners := [
		Vector2(-hw + 1.0, -hh + 1.0),
		Vector2(hw - 1.0, -hh + 1.0),
		Vector2(-hw + 1.0, hh - 1.0),
		Vector2(hw - 1.0, hh - 1.0)
	]
	for c in corners:
		var dir_x := 1.0 if c.x < 0 else -1.0
		var dir_y := 1.0 if c.y < 0 else -1.0
		var corner_tri := PackedVector2Array([
			c,
			c + Vector2(dir_x * 5.0, 0),
			c + Vector2(0, dir_y * 5.0)
		])
		draw_colored_polygon(corner_tri, col_gold)

	# 4. 横跨匣身的朱砂封条
	var seal_rect := Rect2(-hw * 0.75, -2.5, w * 0.75, 5.0)
	draw_rect(seal_rect, col_seal, true)
	draw_line(Vector2(-hw * 0.75, -2.5), Vector2(hw * 0.75 - hw * 0.75, -2.5), Color(1.0, 0.6, 0.6, 0.7), 1.0)

	# 5. 中央锁灵符核（菱形青玉）
	var core_poly := PackedVector2Array([
		Vector2(0, -4.5),
		Vector2(5.5, 0),
		Vector2(0, 4.5),
		Vector2(-5.5, 0)
	])
	draw_colored_polygon(core_poly, col_gold)
	draw_circle(Vector2.ZERO, 2.2, col_glow)

	# 6. 受击损毁龟裂（根据已损击数）
	var damage_ratio: float = 1.0 - float(chest_left_hits) / float(max(1, chest_total_hits))
	if damage_ratio > 0.01:
		# 裂纹随受击程度扩张
		var crack_col := Color(1.0, 0.85, 0.4, 0.85)
		draw_line(Vector2(0, 0), Vector2(-8.0 * damage_ratio, -7.0 * damage_ratio), crack_col, 1.1)
		draw_line(Vector2(0, 0), Vector2(10.0 * damage_ratio, 6.0 * damage_ratio), crack_col, 1.1)
		if damage_ratio > 0.5:
			draw_line(Vector2(-4.0, -3.5), Vector2(-12.0, 2.0), crack_col, 1.0)
			draw_line(Vector2(5.0, 3.0), Vector2(12.0, -4.0), crack_col, 1.0)
