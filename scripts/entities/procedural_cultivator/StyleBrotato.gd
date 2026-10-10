class_name StyleBrotato
extends CultivatorBase

## 风格 A：土豆兄弟风 (Brotato / Western Comic Chibi)
## 特征：
## 1. 2.5px 极粗黑色轮廓线，形体饱满圆润、极度概括
## 2. 标志性的大白眼 + 偏心黑眼珠，呆萌而专注
## 3. 翡翠青绿土豆形道袍身躯，头顶圆球道髻配木簪与红绳
## 4. 夸张逗趣的修仙小飞剑，动感十足

const OUTLINE := Color(0.10, 0.12, 0.15)
const OUTLINE_W := 2.8
const ROBE_GREEN := Color(0.30, 0.78, 0.46)
const ROBE_SHADOW := Color(0.20, 0.60, 0.35)
const SKIN_TONE := Color(1.0, 0.88, 0.78)
const BELT_GOLD := Color(0.96, 0.78, 0.22)
const RED_CORD := Color(0.90, 0.24, 0.24)
const BLADE_STEEL := Color(0.88, 0.94, 1.0)
const WOOD_BROWN := Color(0.68, 0.45, 0.25)

func _draw_front() -> void:
	var bob := sin(_time * 4.0) * 1.5 if animate else 0.0
	var sword_bob := sin(_time * 3.0 + 0.6) * 2.5 if animate else 0.0

	# 1. 阴影
	draw_filled_ellipse(Vector2(0, 24), 20.0 + bob * 0.5, 6.0, Color(0.08, 0.12, 0.16, 0.30))

	# 2. 小短腿（穿黑布鞋）
	draw_stroked_ellipse(Vector2(-7, 20), 4.5, 5.0, Color(0.18, 0.20, 0.25), OUTLINE, OUTLINE_W)
	draw_stroked_ellipse(Vector2(7, 20), 4.5, 5.0, Color(0.18, 0.20, 0.25), OUTLINE, OUTLINE_W)

	# 3. 葫芦形/圆滚滚青绿道袍身体（上下两球相融）
	var body_pts := PackedVector2Array([
		Vector2(-14, 16 + bob), Vector2(-16, 2 + bob), Vector2(-13, -10 + bob),
		Vector2(-9, -20 + bob), Vector2(0, -23 + bob), Vector2(9, -20 + bob),
		Vector2(13, -10 + bob), Vector2(16, 2 + bob), Vector2(14, 16 + bob),
		Vector2(0, 18 + bob)
	])
	draw_stroked_polygon(body_pts, ROBE_GREEN, OUTLINE, OUTLINE_W)
	# 身体下部暗色弧面（增加饱满体积感）
	draw_arc(Vector2(0, 10 + bob), 12.0, 0.2, PI - 0.2, 16, ROBE_SHADOW, 4.0)

	# 4. 头顶发髻、红头绳与小木簪
	var bun_y := -24.0 + bob
	draw_line(Vector2(-10, bun_y), Vector2(10, bun_y - 2), WOOD_BROWN, OUTLINE_W + 1.0) # 横插木簪
	draw_stroked_circle(Vector2(0, bun_y), 6.5, Color(0.15, 0.16, 0.20), OUTLINE, OUTLINE_W) # 黑墨发髻
	draw_line(Vector2(-4, bun_y + 3), Vector2(4, bun_y + 3), RED_CORD, 2.4) # 红绳

	# 6. 土豆兄弟灵魂大白眼 + 偏心黑瞳
	var eye_y := -10.0 + bob
	# 左眼
	draw_stroked_ellipse(Vector2(-6, eye_y), 5.5, 6.0, Color.WHITE, OUTLINE, OUTLINE_W)
	draw_circle(Vector2(-5.0, eye_y + 0.5), 2.2, OUTLINE) # 偏心黑瞳
	draw_circle(Vector2(-5.8, eye_y - 1.0), 0.9, Color.WHITE) # 高光
	# 右眼
	draw_stroked_ellipse(Vector2(6, eye_y), 5.5, 6.0, Color.WHITE, OUTLINE, OUTLINE_W)
	draw_circle(Vector2(7.0, eye_y + 0.5), 2.2, OUTLINE) # 偏心黑瞳
	draw_circle(Vector2(6.2, eye_y - 1.0), 0.9, Color.WHITE) # 高光
	# 呆萌小嘴（微弯黑线）
	draw_arc(Vector2(0, eye_y + 6.0), 2.5, 0.1, PI - 0.1, 8, OUTLINE, 2.0)

	# 7. 左右小圆短手
	draw_stroked_circle(Vector2(-15, 6 + bob), 4.0, SKIN_TONE, OUTLINE, OUTLINE_W)
	draw_stroked_circle(Vector2(15, 6 + bob), 4.0, SKIN_TONE, OUTLINE, OUTLINE_W)

	# 8. 浮游身侧的土豆兄弟萌系飞剑
	_draw_brotato_sword(Vector2(24, 0 + sword_bob), 0.15)

func _draw_side() -> void:
	var bob := sin(_time * 4.0) * 1.5 if animate else 0.0
	var sword_thrust := sin(_time * 4.0) * 3.0 if animate else 0.0

	# 1. 阴影
	draw_filled_ellipse(Vector2(2, 24), 22.0, 6.0, Color(0.08, 0.12, 0.16, 0.30))

	# 2. 侧向步伐（前腿屈后腿蹬，战意十足）
	draw_stroked_ellipse(Vector2(-9, 19 + bob * 0.4), 4.5, 5.0, Color(0.18, 0.20, 0.25), OUTLINE, OUTLINE_W)
	draw_stroked_ellipse(Vector2(7, 21 - bob * 0.4), 5.0, 5.5, Color(0.18, 0.20, 0.25), OUTLINE, OUTLINE_W)

	# 3. 侧面饱满身躯（前突小肚子，后翘小衣摆）
	var body_pts := PackedVector2Array([
		Vector2(-12, 16 + bob), Vector2(-15, 4 + bob), Vector2(-11, -12 + bob),
		Vector2(-4, -22 + bob), Vector2(7, -20 + bob), Vector2(14, -8 + bob),
		Vector2(15, 6 + bob), Vector2(10, 17 + bob), Vector2(-2, 18 + bob)
	])
	draw_stroked_polygon(body_pts, ROBE_GREEN, OUTLINE, OUTLINE_W)

	# 4. 侧面发髻向后斜挑
	var bun_pos := Vector2(-4, -24 + bob)
	draw_line(bun_pos + Vector2(-8, 3), bun_pos + Vector2(10, -4), WOOD_BROWN, OUTLINE_W + 1.0)
	draw_stroked_circle(bun_pos, 6.5, Color(0.15, 0.16, 0.20), OUTLINE, OUTLINE_W)
	draw_line(bun_pos + Vector2(-2, 4), bun_pos + Vector2(4, 4), RED_CORD, 2.4)

	# 5. 侧面单颗特大呆萌大眼（直勾勾瞪向前方）
	var eye_pos := Vector2(8, -10 + bob)
	draw_stroked_ellipse(eye_pos, 6.5, 7.0, Color.WHITE, OUTLINE, OUTLINE_W)
	draw_circle(eye_pos + Vector2(2.5, 0), 2.8, OUTLINE) # 瞪向右前方的黑瞳
	draw_circle(eye_pos + Vector2(1.8, -1.8), 1.1, Color.WHITE) # 高光
	# 侧面坚毅/专注小嘴
	draw_line(eye_pos + Vector2(1, 8), eye_pos + Vector2(6, 7), OUTLINE, 2.2)

	# 7. 双手前伸持剑突刺
	draw_stroked_circle(Vector2(14, 4 + bob), 4.2, SKIN_TONE, OUTLINE, OUTLINE_W)
	_draw_brotato_sword(Vector2(26 + sword_thrust, 2 + bob), deg_to_rad(65.0))

func _draw_back() -> void:
	var bob := sin(_time * 4.0) * 1.5 if animate else 0.0

	# 1. 阴影
	draw_filled_ellipse(Vector2(0, 24), 20.0 + bob * 0.5, 6.0, Color(0.08, 0.12, 0.16, 0.30))

	# 2. 双脚（后视角）
	draw_stroked_ellipse(Vector2(-7, 20), 4.5, 5.0, Color(0.18, 0.20, 0.25), OUTLINE, OUTLINE_W)
	draw_stroked_ellipse(Vector2(7, 20), 4.5, 5.0, Color(0.18, 0.20, 0.25), OUTLINE, OUTLINE_W)

	# 3. 圆滚滚绿色后背
	var body_pts := PackedVector2Array([
		Vector2(-14, 16 + bob), Vector2(-16, 2 + bob), Vector2(-13, -10 + bob),
		Vector2(-9, -20 + bob), Vector2(0, -23 + bob), Vector2(9, -20 + bob),
		Vector2(13, -10 + bob), Vector2(16, 2 + bob), Vector2(14, 16 + bob),
		Vector2(0, 18 + bob)
	])
	draw_stroked_polygon(body_pts, ROBE_GREEN, OUTLINE, OUTLINE_W)

	# 5. 背后斜插的大飞剑（土豆兄弟经典武器外挂）
	var sword_pos := Vector2(-2, -4 + bob)
	_draw_brotato_sword(sword_pos, deg_to_rad(-35.0))

	# 6. 后脑发髻（完整展现红绳与横穿木簪）
	var bun_y := -24.0 + bob
	draw_line(Vector2(-12, bun_y), Vector2(12, bun_y - 2), WOOD_BROWN, OUTLINE_W + 1.2)
	draw_stroked_circle(Vector2(0, bun_y), 7.2, Color(0.15, 0.16, 0.20), OUTLINE, OUTLINE_W)
	draw_line(Vector2(-5, bun_y + 2), Vector2(5, bun_y + 2), RED_CORD, 2.5)

	# 7. 左右两侧萌系小手
	draw_stroked_circle(Vector2(-15, 6 + bob), 4.0, SKIN_TONE, OUTLINE, OUTLINE_W)
	draw_stroked_circle(Vector2(15, 6 + bob), 4.0, SKIN_TONE, OUTLINE, OUTLINE_W)

## 辅助函数：绘制土豆兄弟标志性粗描边圆胖小飞剑
func _draw_brotato_sword(pos: Vector2, rot: float) -> void:
	var t := Transform2D(rot, pos)
	# 剑身胖厚
	var blade_pts: PackedVector2Array = [
		t * Vector2(0, -22),   # 剑尖微钝
		t * Vector2(5.5, -16),
		t * Vector2(4.5, 6),
		t * Vector2(-4.5, 6),
		t * Vector2(-5.5, -16)
	]
	draw_stroked_polygon(blade_pts, BLADE_STEEL, OUTLINE, OUTLINE_W)
	draw_line(t * Vector2(0, -18), t * Vector2(0, 5), Color(0.70, 0.82, 0.95), 1.5) # 剑身倒角亮线

	# 金色护手
	var guard_pts: PackedVector2Array = [
		t * Vector2(-8, 6), t * Vector2(8, 6),
		t * Vector2(6, 10), t * Vector2(-6, 10)
	]
	draw_stroked_polygon(guard_pts, BELT_GOLD, OUTLINE, OUTLINE_W)

	# 剑柄与圆头剑首
	draw_line(t * Vector2(0, 10), t * Vector2(0, 18), OUTLINE, OUTLINE_W + 2.0)
	draw_line(t * Vector2(0, 10), t * Vector2(0, 18), WOOD_BROWN, OUTLINE_W)
	draw_stroked_circle(t * Vector2(0, 20), 3.5, BELT_GOLD, OUTLINE, OUTLINE_W)
