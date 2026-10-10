class_name StyleHollowKnightDeluxe
extends CultivatorBase

## 风格 B 豪华版：空洞骑士风 · 幽冥蜕蝶剑圣 (Hollow Knight Deluxe)
## 特征：
## 1. 雕琢精致的冷白骨玉面壳，优美舒展的蝶翼仙角
## 2. 深渊凹陷眸眶中的冷月灵光眼（三层柔和羽化月辉）
## 3. 双层蝉翼薄纱大披风（外层深渊暗紫墨蓝，内层幽冷翡翠），多重轻盈破口
## 4. 纯白修长月光骨钉长剑，剑尖凝聚纯白星尘光粒
## 5. 胸前骨质聚灵珠与脚底虚空冷雾

const VOID_BLACK := Color(0.06, 0.07, 0.10)
const BONE_WHITE := Color(0.95, 0.96, 0.98)
const BONE_SHADOW := Color(0.78, 0.82, 0.88)
const CLOAK_OUTER := Color(0.12, 0.15, 0.22)       # 外层深渊冷紫蓝
const CLOAK_INNER := Color(0.18, 0.38, 0.30)       # 内层幽绿薄纱
const CLOAK_EDGE := Color(0.35, 0.65, 0.52)        # 边缘冷玉月辉
const MOON_EYE := Color(0.98, 1.0, 1.0)
const MOON_GLOW := Color(0.70, 0.90, 1.0, 0.45)

func _draw_front() -> void:
	var float_y := sin(_time * 2.6) * 2.2 if animate else 0.0
	var cloak_wave := sin(_time * 3.2) * 2.8 if animate else 0.0

	# 1. 虚空冷雾与脚底地影
	draw_filled_ellipse(Vector2(0, 33), 18.0, 5.0, Color(0.04, 0.05, 0.08, 0.55))
	draw_arc(Vector2(0, 33), 20.0, 0, TAU, 32, Color(0.40, 0.80, 0.68, 0.18 + sin(_time * 3.0) * 0.08), 1.4, true)

	# 2. 背后背负之纯白月光长骨钉
	_draw_deluxe_nail(Vector2(-2, -10 + float_y), deg_to_rad(-24.0))

	# 3. 双层如翼大披风
	# 内层幽绿薄纱（露在底端两侧）
	var inner_cloak: PackedVector2Array = [
		Vector2(0, -4 + float_y),
		Vector2(-16, 12 + float_y),
		Vector2(-15 + cloak_wave * 0.3, 30 + float_y),
		Vector2(0, 27 + float_y),
		Vector2(15 - cloak_wave * 0.3, 30 + float_y),
		Vector2(16, 12 + float_y)
	]
	draw_colored_polygon(inner_cloak, CLOAK_INNER)

	# 外层深渊暗披风（带破损裂口锐角）
	var outer_cloak: PackedVector2Array = [
		Vector2(0, -6 + float_y),
		Vector2(-9, -2 + float_y),
		Vector2(-14, 15 + float_y),
		Vector2(-12 + cloak_wave * 0.4, 28 + float_y), # 左侧破损尖角
		Vector2(-7, 24 + float_y),
		Vector2(-3, 31 + float_y),                     # 中间长尖角
		Vector2(2, 26 + float_y),
		Vector2(8 + cloak_wave * 0.3, 29 + float_y),   # 右侧尖角
		Vector2(14, 15 + float_y),
		Vector2(9, -2 + float_y)
	]
	draw_colored_polygon(outer_cloak, CLOAK_OUTER)
	draw_polyline(outer_cloak, CLOAK_EDGE, 1.2, true)

	# 4. 胸前骨质锁扣与聚灵珠
	var chest_pos := Vector2(0, -3 + float_y)
	draw_soft_glow(chest_pos, 7.0, Color(0.40, 0.90, 0.75, 0.4), 2)
	draw_circle(chest_pos, 3.2, BONE_WHITE)
	draw_circle(chest_pos, 1.5, Color(0.20, 0.85, 0.65))

	# 5. 冷白骨玉蝶面头部与修长仙角
	var head_center := Vector2(0, -15 + float_y)

	# 蝶翼仙角（左角与右角优雅向外蜿蜒展开）
	var l_horn: PackedVector2Array = [
		head_center + Vector2(-6, -4),
		head_center + Vector2(-14, -18),
		head_center + Vector2(-12, -28), # 角尖高耸
		head_center + Vector2(-6, -20),
		head_center + Vector2(-3, -8)
	]
	draw_colored_polygon(l_horn, BONE_WHITE)
	# 角质倒角背光阴影
	draw_colored_polygon(PackedVector2Array([
		head_center + Vector2(-6, -4),
		head_center + Vector2(-14, -18),
		head_center + Vector2(-12, -28),
		head_center + Vector2(-10, -18)
	]), BONE_SHADOW)

	var r_horn: PackedVector2Array = [
		head_center + Vector2(3, -8),
		head_center + Vector2(6, -20),
		head_center + Vector2(12, -28),  # 右角尖
		head_center + Vector2(14, -18),
		head_center + Vector2(6, -4)
	]
	draw_colored_polygon(r_horn, BONE_WHITE)
	draw_colored_polygon(PackedVector2Array([
		head_center + Vector2(3, -8),
		head_center + Vector2(6, -20),
		head_center + Vector2(12, -28),
		head_center + Vector2(10, -18)
	]), BONE_SHADOW)

	# 骨面主轮廓（优雅鹅蛋微尖形）
	var mask_pts: PackedVector2Array = [
		head_center + Vector2(-9.5, -4),
		head_center + Vector2(-8, 6),
		head_center + Vector2(0, 9.5), # 下巴微尖
		head_center + Vector2(8, 6),
		head_center + Vector2(9.5, -4),
		head_center + Vector2(0, -9)
	]
	draw_colored_polygon(mask_pts, BONE_WHITE)
	draw_polyline(mask_pts, BONE_SHADOW, 1.2, true)

	# 6. 深渊凹陷眸眶中的冷月灵眸（带三层多重月晕）
	var l_eye := head_center + Vector2(-4.2, 0.8)
	var r_eye := head_center + Vector2(4.2, 0.8)

	# 凹陷漆黑眼眶
	draw_filled_ellipse(l_eye, 3.8, 5.2, VOID_BLACK)
	draw_filled_ellipse(r_eye, 3.8, 5.2, VOID_BLACK)

	# 月辉外晕
	draw_soft_glow(l_eye, 6.0, MOON_GLOW, 3)
	draw_soft_glow(r_eye, 6.0, MOON_GLOW, 3)

	# 空灵泪滴状月眸白芯
	draw_filled_ellipse(l_eye + Vector2(0.2, -0.2), 2.4, 3.8, MOON_EYE)
	draw_filled_ellipse(r_eye + Vector2(-0.2, -0.2), 2.4, 3.8, MOON_EYE)

func _draw_side() -> void:
	var float_y := sin(_time * 2.6) * 2.2 if animate else 0.0
	var cloak_wave := sin(_time * 3.6) * 4.0 if animate else 0.0

	# 1. 地影
	draw_filled_ellipse(Vector2(2, 33), 18.0, 5.0, Color(0.04, 0.05, 0.08, 0.55))

	# 2. 侧向大披风如蝶翼后拖
	var cloak_pts: PackedVector2Array = [
		Vector2(2, -6 + float_y),
		Vector2(-4, 0 + float_y),
		Vector2(-15 + cloak_wave, 12 + float_y),
		Vector2(-20 + cloak_wave * 1.3, 29 + float_y),
		Vector2(-9 + cloak_wave * 0.7, 26 + float_y),
		Vector2(-2, 30 + float_y),
		Vector2(6, 18 + float_y),
		Vector2(6, 0 + float_y)
	]
	draw_colored_polygon(cloak_pts, CLOAK_OUTER)
	draw_polyline(cloak_pts, CLOAK_EDGE, 1.2, true)

	# 3. 侧面冷白骨面
	var head_center := Vector2(2, -15 + float_y)
	var mask_pts: PackedVector2Array = [
		head_center + Vector2(-7, -4),
		head_center + Vector2(-5, 6),
		head_center + Vector2(3, 9.5),
		head_center + Vector2(9, 3),
		head_center + Vector2(7, -6),
		head_center + Vector2(0, -9)
	]
	draw_colored_polygon(mask_pts, BONE_WHITE)

	# 侧面后仰仙角（凌厉刺天）
	var horn_pts: PackedVector2Array = [
		head_center + Vector2(-3, -6),
		head_center + Vector2(-12, -18),
		head_center + Vector2(-16, -29),
		head_center + Vector2(-6, -21),
		head_center + Vector2(2, -8)
	]
	draw_colored_polygon(horn_pts, BONE_WHITE)
	draw_colored_polygon(PackedVector2Array([
		head_center + Vector2(-3, -6),
		head_center + Vector2(-12, -18),
		head_center + Vector2(-16, -29),
		head_center + Vector2(-8, -17)
	]), BONE_SHADOW)

	# 4. 侧面单侧冷月眼眸
	var eye_pos := head_center + Vector2(4.5, 0.8)
	draw_filled_ellipse(eye_pos, 3.8, 5.2, VOID_BLACK)
	draw_soft_glow(eye_pos, 6.5, MOON_GLOW, 3)
	draw_filled_ellipse(eye_pos + Vector2(0.3, -0.2), 2.4, 4.0, MOON_EYE)

	# 5. 单手挺起纯白长骨钉前刺（击剑突刺姿态）
	_draw_deluxe_nail(Vector2(16, 8 + float_y), deg_to_rad(62.0))

func _draw_back() -> void:
	var float_y := sin(_time * 2.6) * 2.2 if animate else 0.0
	var cloak_wave := sin(_time * 3.2) * 2.8 if animate else 0.0

	# 1. 地影
	draw_filled_ellipse(Vector2(0, 33), 18.0, 5.0, Color(0.04, 0.05, 0.08, 0.55))

	# 2. 后脑骨玉冠与双角
	var head_center := Vector2(0, -15 + float_y)
	draw_circle(head_center, 9.5, BONE_WHITE)
	draw_arc(head_center, 9.5, 0, TAU, 24, BONE_SHADOW, 1.2, true)

	# 双角对称刺空
	var l_horn: PackedVector2Array = [
		head_center + Vector2(-6, -4),
		head_center + Vector2(-14, -18),
		head_center + Vector2(-12, -28),
		head_center + Vector2(-6, -20),
		head_center + Vector2(-3, -8)
	]
	draw_colored_polygon(l_horn, BONE_WHITE)
	var r_horn: PackedVector2Array = [
		head_center + Vector2(3, -8),
		head_center + Vector2(6, -20),
		head_center + Vector2(12, -28),
		head_center + Vector2(14, -18),
		head_center + Vector2(6, -4)
	]
	draw_colored_polygon(r_horn, BONE_WHITE)

	# 3. 全覆盖破损大披风
	var cloak_pts: PackedVector2Array = [
		Vector2(-9, -6 + float_y), Vector2(9, -6 + float_y),
		Vector2(16, 14 + float_y),
		Vector2(13 + cloak_wave * 0.4, 30 + float_y),
		Vector2(6, 26 + float_y),
		Vector2(0, 32 + float_y),
		Vector2(-6, 26 + float_y),
		Vector2(-14 - cloak_wave * 0.4, 30 + float_y),
		Vector2(-16, 14 + float_y)
	]
	draw_colored_polygon(cloak_pts, CLOAK_OUTER)
	draw_polyline(cloak_pts, CLOAK_EDGE, 1.2, true)

	# 4. 背后正中垂直背负的长骨钉
	_draw_deluxe_nail(Vector2(0, 0 + float_y), deg_to_rad(-8.0))

## 绘制月光纯白修长骨钉（锋芒如雪）
func _draw_deluxe_nail(pos: Vector2, rot: float) -> void:
	var t := Transform2D(rot, pos)
	# 极其修长锋利的纯白剑身
	var nail_pts: PackedVector2Array = [
		t * Vector2(0, -36), # 极长剑尖
		t * Vector2(3.0, -26),
		t * Vector2(3.0, 13),
		t * Vector2(-3.0, 13),
		t * Vector2(-3.0, -26)
	]
	draw_colored_polygon(nail_pts, BONE_WHITE)
	# 剑脊暗面
	var shadow_pts: PackedVector2Array = [
		t * Vector2(0, -36),
		t * Vector2(3.0, -26),
		t * Vector2(3.0, 13),
		t * Vector2(0, 13)
	]
	draw_colored_polygon(shadow_pts, BONE_SHADOW)
	# 剑尖凝聚纯白星尘光粒
	draw_circle(t * Vector2(0, -36), 2.2, Color.WHITE)
	draw_soft_glow(t * Vector2(0, -36), 6.0, MOON_GLOW, 2)
	# 骨质剑柄
	draw_line(t * Vector2(0, 13), t * Vector2(0, 22), BONE_WHITE, 2.5)
	draw_circle(t * Vector2(0, 23), 2.6, BONE_SHADOW)
