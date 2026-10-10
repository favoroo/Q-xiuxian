class_name StyleHollowKnight
extends CultivatorBase

## 风格 B：空洞骑士风 (Hollow Knight / Gothic Insect Silk Cultivator)
## 特征：
## 1. 幽白空灵的发光双眼（无瞳孔），纯黑玄玉面壳
## 2. 昆虫角质与修仙飞天髻融合的凌厉双角发簪
## 3. 破损蝉翼质感的墨绿/灰绿冷冽长披风，孤寂飘逸
## 4. 纯白修长骨钉飞剑，极简冷兵器寒芒

const VOID_BLACK := Color(0.08, 0.09, 0.12)
const CLOAK_GREEN := Color(0.18, 0.36, 0.28)
const CLOAK_DARK := Color(0.11, 0.22, 0.17)
const CLOAK_EDGE := Color(0.26, 0.52, 0.40)
const EYE_WHITE := Color(0.96, 0.98, 1.0)
const EYE_GLOW := Color(0.80, 0.92, 1.0, 0.40)
const NAIL_WHITE := Color(0.92, 0.95, 0.98)
const NAIL_SHADOW := Color(0.65, 0.72, 0.80)

func _draw_front() -> void:
	var float_y := sin(_time * 2.8) * 2.0 if animate else 0.0
	var cloak_sway := sin(_time * 3.5) * 2.5 if animate else 0.0

	# 1. 虚空幽白地影与清气
	draw_filled_ellipse(Vector2(0, 32), 16.0, 4.5, Color(0.04, 0.06, 0.08, 0.45))
	draw_arc(Vector2(0, 32), 18.0, 0, TAU, 24, Color(0.35, 0.75, 0.60, 0.18 + sin(_time * 3.0) * 0.05), 1.2, true)

	# 2. 背后大角度斜贯背负之纯白骨钉（剑柄探出右肩，剑尖探出左下摆）
	_draw_hollow_nail(Vector2(1, -2 + float_y), deg_to_rad(152.0))

	# 3. 破损墨绿蝉翼道披（多层叠落，有破口锐角）
	var cloak_pts: PackedVector2Array = [
		Vector2(0, -6 + float_y),        # 领口正中
		Vector2(-9, -2 + float_y),
		Vector2(-15, 14 + float_y),
		Vector2(-13 + cloak_sway * 0.4, 28 + float_y), # 左侧破损尖角
		Vector2(-8, 25 + float_y),
		Vector2(-4, 30 + float_y),       # 中间垂尖
		Vector2(2, 26 + float_y),
		Vector2(9 + cloak_sway * 0.3, 29 + float_y),  # 右侧破损尖角
		Vector2(14, 14 + float_y),
		Vector2(9, -2 + float_y)
	]
	draw_colored_polygon(cloak_pts, CLOAK_GREEN)
	# 披风暗面阴影折褶
	var fold_pts: PackedVector2Array = [
		Vector2(0, -6 + float_y), Vector2(4, 10 + float_y),
		Vector2(9 + cloak_sway * 0.3, 29 + float_y), Vector2(2, 26 + float_y)
	]
	draw_colored_polygon(fold_pts, CLOAK_DARK)
	# 披风清冷边缘亮线
	draw_polyline(cloak_pts, CLOAK_EDGE, 1.2, true)

	# 4. 纯黑玄面头部
	var head_center := Vector2(0, -14 + float_y)
	draw_circle(head_center, 9.5, VOID_BLACK)

	# 5. 昆虫角质与飞天髻融合的修长双角（向左右上挑）
	var left_horn: PackedVector2Array = [
		head_center + Vector2(-6, -4),
		head_center + Vector2(-12, -18),
		head_center + Vector2(-9, -26), # 左角尖
		head_center + Vector2(-4, -18),
		head_center + Vector2(-2, -8)
	]
	draw_colored_polygon(left_horn, VOID_BLACK)

	var right_horn: PackedVector2Array = [
		head_center + Vector2(2, -8),
		head_center + Vector2(4, -18),
		head_center + Vector2(9, -26),  # 右角尖
		head_center + Vector2(12, -18),
		head_center + Vector2(6, -4)
	]
	draw_colored_polygon(right_horn, VOID_BLACK)

	# 6. 标志性的幽白空灵发光眼洞（无瞳孔，泪滴微倾斜）
	var l_eye := head_center + Vector2(-4.2, 0.5)
	var r_eye := head_center + Vector2(4.2, 0.5)
	# 幽白外晕
	draw_soft_glow(l_eye, 5.0, EYE_GLOW, 3)
	draw_soft_glow(r_eye, 5.0, EYE_GLOW, 3)
	# 实心白眼（空洞泪滴卵形）
	draw_filled_ellipse(l_eye, 2.6, 4.0, EYE_WHITE)
	draw_filled_ellipse(r_eye, 2.6, 4.0, EYE_WHITE)

func _draw_side() -> void:
	var float_y := sin(_time * 2.8) * 2.0 if animate else 0.0
	var cloak_sway := sin(_time * 4.0) * 3.5 if animate else 0.0

	# 1. 虚空地影
	draw_filled_ellipse(Vector2(2, 32), 16.0, 4.5, Color(0.04, 0.06, 0.08, 0.45))

	# 2. 侧向大披风（后掠如翼）
	var cloak_pts: PackedVector2Array = [
		Vector2(2, -6 + float_y),
		Vector2(-4, 0 + float_y),
		Vector2(-14 + cloak_sway, 12 + float_y),
		Vector2(-18 + cloak_sway * 1.2, 28 + float_y), # 拖曳后尾
		Vector2(-8 + cloak_sway * 0.6, 26 + float_y),
		Vector2(-2, 29 + float_y),
		Vector2(6, 18 + float_y),
		Vector2(6, 0 + float_y)
	]
	# 侧面后背背负之骨钉（贴合后背斗篷，剑尖向后上方斜挑）
	_draw_hollow_nail(Vector2(-7, 2 + float_y), deg_to_rad(-24.0))
	draw_colored_polygon(cloak_pts, CLOAK_GREEN)
	draw_polyline(cloak_pts, CLOAK_EDGE, 1.2, true)

	# 3. 纯黑玄面侧颜
	var head_center := Vector2(2, -14 + float_y)
	draw_circle(head_center, 9.0, VOID_BLACK)

	# 4. 后挑双角（侧视重叠后仰，锋芒毕露）
	var horn_pts: PackedVector2Array = [
		head_center + Vector2(-3, -6),
		head_center + Vector2(-10, -18),
		head_center + Vector2(-14, -28), # 后掠角尖
		head_center + Vector2(-5, -20),
		head_center + Vector2(2, -8)
	]
	draw_colored_polygon(horn_pts, VOID_BLACK)

	# 5. 单侧幽白眼洞（专注凝视前方）
	var eye_pos := head_center + Vector2(4.5, 0.5)
	draw_soft_glow(eye_pos, 5.5, EYE_GLOW, 3)
	draw_filled_ellipse(eye_pos, 2.6, 4.2, EYE_WHITE)

func _draw_back() -> void:
	var float_y := sin(_time * 2.8) * 2.0 if animate else 0.0
	var cloak_sway := sin(_time * 3.5) * 2.5 if animate else 0.0

	# 1. 虚空地影
	draw_filled_ellipse(Vector2(0, 32), 16.0, 4.5, Color(0.04, 0.06, 0.08, 0.45))

	# 2. 背后全覆盖的墨绿残破斗篷（作为深色底衬）
	var cloak_pts: PackedVector2Array = [
		Vector2(-8, -6 + float_y), Vector2(8, -6 + float_y),
		Vector2(15, 14 + float_y),
		Vector2(12 + cloak_sway * 0.4, 29 + float_y),
		Vector2(5, 27 + float_y),
		Vector2(0, 31 + float_y),
		Vector2(-6, 26 + float_y),
		Vector2(-13 - cloak_sway * 0.4, 29 + float_y),
		Vector2(-15, 14 + float_y)
	]
	draw_colored_polygon(cloak_pts, CLOAK_GREEN)
	draw_polyline(cloak_pts, CLOAK_EDGE, 1.2, true)

	# 3. 后背斜跨剑带
	var p_top := Vector2(8, -6 + float_y)
	var p_bot := Vector2(-8, 18 + float_y)
	draw_line(p_top, p_bot, Color(0.05, 0.08, 0.12, 0.95), 3.0)
	draw_line(p_top, p_bot, CLOAK_EDGE, 1.0)
	var center := (p_top + p_bot) * 0.5
	draw_circle(center, 2.8, NAIL_WHITE)
	draw_circle(center, 1.4, VOID_BLACK)

	# 4. 在斗篷最外层绘制斜跨背负的长骨钉！
	_draw_hollow_nail(Vector2(1, -2 + float_y), deg_to_rad(152.0))

	# 5. 纯黑后脑与双角
	var head_center := Vector2(0, -14 + float_y)
	draw_circle(head_center, 9.5, VOID_BLACK)

	var left_horn: PackedVector2Array = [
		head_center + Vector2(-6, -4),
		head_center + Vector2(-12, -18),
		head_center + Vector2(-9, -26),
		head_center + Vector2(-4, -18),
		head_center + Vector2(-2, -8)
	]
	draw_colored_polygon(left_horn, VOID_BLACK)
	var right_horn: PackedVector2Array = [
		head_center + Vector2(2, -8),
		head_center + Vector2(4, -18),
		head_center + Vector2(9, -26),
		head_center + Vector2(12, -18),
		head_center + Vector2(6, -4)
	]
	draw_colored_polygon(right_horn, VOID_BLACK)

## 辅助函数：绘制空洞骑士极简纯白修长骨钉
func _draw_hollow_nail(pos: Vector2, rot: float) -> void:
	var t := Transform2D(rot, pos)
	# 小巧精致的纯白骨钉（总长仅约 26px，绝不拖出斗篷底部）
	var nail_pts: PackedVector2Array = [
		t * Vector2(0, -15),  # 剑尖
		t * Vector2(2.4, -9),
		t * Vector2(2.0, 3),
		t * Vector2(-2.0, 3),
		t * Vector2(-2.4, -9)
	]
	draw_colored_polygon(nail_pts, NAIL_WHITE)
	draw_colored_polygon(PackedVector2Array([
		t * Vector2(0, -15), t * Vector2(2.4, -9),
		t * Vector2(2.0, 3), t * Vector2(0, 3)
	]), NAIL_SHADOW)
	draw_line(t * Vector2(0, -13), t * Vector2(0, 2), Color(1.0, 1.0, 1.0, 0.9), 1.0)
	var guard_pts: PackedVector2Array = [
		t * Vector2(-3.0, 3), t * Vector2(3.0, 3),
		t * Vector2(2.2, 5.5), t * Vector2(-2.2, 5.5)
	]
	draw_colored_polygon(guard_pts, NAIL_SHADOW)
	draw_line(t * Vector2(0, 5.5), t * Vector2(0, 10.5), NAIL_WHITE, 2.0)
	draw_circle(t * Vector2(0, 11), 1.6, NAIL_WHITE)
	draw_circle(t * Vector2(0, 11), 0.8, NAIL_SHADOW)
