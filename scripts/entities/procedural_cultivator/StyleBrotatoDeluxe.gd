class_name StyleBrotatoDeluxe
extends CultivatorBase

## 风格 A 豪华版：土豆兄弟风 · 金丹符箓狂徒 (Brotato Deluxe)
## 特征：
## 1. 2.8px 经典粗黑外轮廓，形体饱满软糯
## 2. 姜黄八卦小道袍 + 玄墨护腕，胸前八卦太极徽标
## 3. 狡黠大白眼 + 嘴刁灵草，头系朱砂降魔抹额
## 4. 背后扇形展开的四色符箓令旗与雷火小木剑
## 5. 环绕周身的噼啪雷光小法球

const OUTLINE := Color(0.10, 0.12, 0.15)
const OUTLINE_W := 2.8
const ROBE_YELLOW := Color(0.98, 0.78, 0.22)
const ROBE_SHADOW := Color(0.85, 0.62, 0.12)
const ROBE_INNER_RED := Color(0.88, 0.22, 0.22)
const BELT_BLACK := Color(0.14, 0.16, 0.20)
const SKIN_TONE := Color(1.0, 0.88, 0.78)
const LIGHTNING_CYAN := Color(0.30, 0.95, 1.0)

func _draw_front() -> void:
	var bob := sin(_time * 4.2) * 1.6 if animate else 0.0
	var spark_pulse := sin(_time * 12.0) * 0.2

	# 1. 柔和硬边阴影
	draw_filled_ellipse(Vector2(0, 25), 22.0 + bob * 0.5, 6.5, Color(0.08, 0.12, 0.16, 0.32))

	# 2. 背后扇形展开的四色符箓令旗（在身体最下层）
	_draw_banner_flags(Vector2(0, -2 + bob), 0.0)

	# 3. 踩在脚下的小黑靴
	draw_stroked_ellipse(Vector2(-7.5, 21), 4.8, 5.2, BELT_BLACK, OUTLINE, OUTLINE_W)
	draw_stroked_ellipse(Vector2(7.5, 21), 4.8, 5.2, BELT_BLACK, OUTLINE, OUTLINE_W)

	# 4. 圆滚滚姜黄道袍身躯
	var body_pts := PackedVector2Array([
		Vector2(-15, 16 + bob), Vector2(-17, 2 + bob), Vector2(-14, -10 + bob),
		Vector2(-10, -21 + bob), Vector2(0, -24 + bob), Vector2(10, -21 + bob),
		Vector2(14, -10 + bob), Vector2(17, 2 + bob), Vector2(15, 16 + bob),
		Vector2(0, 19 + bob)
	])
	draw_stroked_polygon(body_pts, ROBE_YELLOW, OUTLINE, OUTLINE_W)
	# 底部饱满立体阴影
	draw_arc(Vector2(0, 11 + bob), 13.0, 0.15, PI - 0.15, 16, ROBE_SHADOW, 4.2)

	# 5. 胸前八卦太极徽标
	var bagua_center := Vector2(0, -4 + bob)
	draw_stroked_circle(bagua_center, 6.0, Color.WHITE, OUTLINE, 1.8)
	# 太极黑白鱼
	draw_circle(bagua_center + Vector2(0, -2.5), 2.8, BELT_BLACK)
	draw_circle(bagua_center + Vector2(0, 2.5), 2.8, Color.WHITE)
	draw_circle(bagua_center + Vector2(0, -2.5), 1.0, Color.WHITE)
	draw_circle(bagua_center + Vector2(0, 2.5), 1.0, BELT_BLACK)

	# 6. 玄黑腰带与红流苏
	var belt_y := 5.0 + bob
	draw_line(Vector2(-15, belt_y), Vector2(15, belt_y), OUTLINE, OUTLINE_W + 2.2)
	draw_line(Vector2(-15, belt_y), Vector2(15, belt_y), BELT_BLACK, OUTLINE_W)
	draw_stroked_circle(Vector2(0, belt_y), 3.2, ROBE_INNER_RED, OUTLINE, 1.8)
	draw_line(Vector2(0, belt_y + 3), Vector2(1, belt_y + 8), ROBE_INNER_RED, 2.0)

	# 7. 头部发髻、朱砂降魔抹额与小木簪
	var bun_y := -25.0 + bob
	draw_line(Vector2(-11, bun_y), Vector2(11, bun_y - 2), Color(0.70, 0.48, 0.28), OUTLINE_W + 1.2) # 横插木簪
	draw_stroked_circle(Vector2(0, bun_y), 7.0, BELT_BLACK, OUTLINE, OUTLINE_W)
	# 红色抹额横跨前额
	draw_line(Vector2(-12, bun_y + 7), Vector2(12, bun_y + 7), OUTLINE, OUTLINE_W + 2.0)
	draw_line(Vector2(-12, bun_y + 7), Vector2(12, bun_y + 7), ROBE_INNER_RED, OUTLINE_W)
	draw_circle(Vector2(0, bun_y + 7), 2.0, Color(1.0, 0.85, 0.20)) # 抹额金扣

	# 8. 招牌狡黠大白眼 + 嘴叼灵草
	var eye_y := -11.0 + bob
	# 左眼（稍大）
	draw_stroked_ellipse(Vector2(-6.5, eye_y), 5.8, 6.2, Color.WHITE, OUTLINE, OUTLINE_W)
	draw_circle(Vector2(-5.5, eye_y + 0.5), 2.4, OUTLINE)
	draw_circle(Vector2(-6.2, eye_y - 1.2), 1.0, Color.WHITE)
	# 右眼（微眯，体现自信狡黠）
	draw_stroked_ellipse(Vector2(6.5, eye_y), 5.2, 5.8, Color.WHITE, OUTLINE, OUTLINE_W)
	draw_circle(Vector2(7.2, eye_y + 0.5), 2.2, OUTLINE)
	draw_circle(Vector2(6.5, eye_y - 1.0), 0.9, Color.WHITE)

	# 嘴角微扬与叼着的青翠灵草
	draw_arc(Vector2(1, eye_y + 7.0), 3.0, 0.2, PI - 0.2, 8, OUTLINE, 2.0)
	# 嘴边叼着的一根灵草叶
	draw_line(Vector2(3, eye_y + 6.5), Vector2(11, eye_y + 4.5), Color(0.25, 0.80, 0.45), 2.0)
	draw_circle(Vector2(11, eye_y + 4.5), 1.5, Color(0.40, 0.95, 0.60))

	# 9. 玄黑护腕双手
	draw_stroked_circle(Vector2(-16, 7 + bob), 4.2, BELT_BLACK, OUTLINE, OUTLINE_W)
	draw_stroked_circle(Vector2(16, 7 + bob), 4.2, BELT_BLACK, OUTLINE, OUTLINE_W)

	# 10. 身旁浮游的噼啪雷火小木剑与环绕雷光球
	var sword_bob := sin(_time * 3.5 + 0.8) * 2.8 if animate else 0.0
	_draw_thunder_sword(Vector2(26, 0 + sword_bob), deg_to_rad(15.0))

	# 浮游雷火法球
	var orb_pos := Vector2(-22, -8 + sin(_time * 4.0) * 3.0)
	draw_soft_glow(orb_pos, 8.0, Color(0.30, 0.90, 1.0, 0.45 + spark_pulse), 3)
	draw_stroked_circle(orb_pos, 4.0, Color.WHITE, LIGHTNING_CYAN, 2.0)
	# 闪电小折线
	draw_line(orb_pos + Vector2(-3, 0), orb_pos + Vector2(0, -4), LIGHTNING_CYAN, 1.5)
	draw_line(orb_pos + Vector2(0, -4), orb_pos + Vector2(3, 1), LIGHTNING_CYAN, 1.5)

func _draw_side() -> void:
	var bob := sin(_time * 4.2) * 1.6 if animate else 0.0
	var thrust := sin(_time * 4.2) * 3.5 if animate else 0.0

	# 1. 阴影
	draw_filled_ellipse(Vector2(2, 25), 23.0, 6.5, Color(0.08, 0.12, 0.16, 0.32))

	# 2. 背后向后招展的令旗
	_draw_banner_flags(Vector2(-4, -2 + bob), deg_to_rad(-25.0))

	# 3. 奔跑弓步双靴
	draw_stroked_ellipse(Vector2(-10, 20 + bob * 0.4), 4.8, 5.2, BELT_BLACK, OUTLINE, OUTLINE_W)
	draw_stroked_ellipse(Vector2(8, 22 - bob * 0.4), 5.2, 5.6, BELT_BLACK, OUTLINE, OUTLINE_W)

	# 4. 侧向饱满身躯
	var body_pts := PackedVector2Array([
		Vector2(-13, 16 + bob), Vector2(-16, 4 + bob), Vector2(-12, -12 + bob),
		Vector2(-4, -23 + bob), Vector2(8, -21 + bob), Vector2(15, -8 + bob),
		Vector2(16, 6 + bob), Vector2(11, 18 + bob), Vector2(-2, 19 + bob)
	])
	draw_stroked_polygon(body_pts, ROBE_YELLOW, OUTLINE, OUTLINE_W)

	# 5. 侧面发髻与抹额
	var bun_pos := Vector2(-5, -25 + bob)
	draw_line(bun_pos + Vector2(-8, 3), bun_pos + Vector2(11, -4), Color(0.70, 0.48, 0.28), OUTLINE_W + 1.2)
	draw_stroked_circle(bun_pos, 7.0, BELT_BLACK, OUTLINE, OUTLINE_W)
	draw_line(Vector2(-8, bun_pos.y + 7), Vector2(12, bun_pos.y + 9), ROBE_INNER_RED, OUTLINE_W + 1.0)

	# 6. 单颗特大专注大白眼
	var eye_pos := Vector2(9, -11 + bob)
	draw_stroked_ellipse(eye_pos, 6.8, 7.2, Color.WHITE, OUTLINE, OUTLINE_W)
	draw_circle(eye_pos + Vector2(3.0, 0), 2.8, OUTLINE)
	draw_circle(eye_pos + Vector2(2.0, -2.0), 1.2, Color.WHITE)

	# 侧面叼着的灵草向前伸展
	draw_line(eye_pos + Vector2(4, 8), eye_pos + Vector2(15, 6), Color(0.25, 0.80, 0.45), 2.2)

	# 7. 侧身玄黑腰封
	draw_line(Vector2(-14, 5 + bob), Vector2(15, 7 + bob), BELT_BLACK, OUTLINE_W + 1.5)

	# 8. 双手握雷火剑前刺
	draw_stroked_circle(Vector2(14, 5 + bob), 4.5, BELT_BLACK, OUTLINE, OUTLINE_W)
	_draw_thunder_sword(Vector2(28 + thrust, 3 + bob), deg_to_rad(65.0))

func _draw_back() -> void:
	var bob := sin(_time * 4.2) * 1.6 if animate else 0.0

	# 1. 阴影
	draw_filled_ellipse(Vector2(0, 25), 22.0 + bob * 0.5, 6.5, Color(0.08, 0.12, 0.16, 0.32))

	# 2. 背后四色符箓令旗（完整对称展现）
	_draw_banner_flags(Vector2(0, -2 + bob), 0.0)

	# 3. 后脑双靴
	draw_stroked_ellipse(Vector2(-7.5, 21), 4.8, 5.2, BELT_BLACK, OUTLINE, OUTLINE_W)
	draw_stroked_ellipse(Vector2(7.5, 21), 4.8, 5.2, BELT_BLACK, OUTLINE, OUTLINE_W)

	# 4. 圆滚滚后背与大太极印
	var body_pts := PackedVector2Array([
		Vector2(-15, 16 + bob), Vector2(-17, 2 + bob), Vector2(-14, -10 + bob),
		Vector2(-10, -21 + bob), Vector2(0, -24 + bob), Vector2(10, -21 + bob),
		Vector2(14, -10 + bob), Vector2(17, 2 + bob), Vector2(15, 16 + bob),
		Vector2(0, 19 + bob)
	])
	draw_stroked_polygon(body_pts, ROBE_YELLOW, OUTLINE, OUTLINE_W)

	# 后背大太极印纹
	var bagua_center := Vector2(0, -2 + bob)
	draw_stroked_circle(bagua_center, 7.5, Color.WHITE, OUTLINE, 2.0)
	draw_circle(bagua_center + Vector2(0, -3.2), 3.5, BELT_BLACK)
	draw_circle(bagua_center + Vector2(0, 3.2), 3.5, Color.WHITE)

	# 后腰带
	draw_line(Vector2(-15, 5 + bob), Vector2(15, 5 + bob), BELT_BLACK, OUTLINE_W + 1.5)

	# 5. 后脑发髻与木簪
	var bun_y := -25.0 + bob
	draw_line(Vector2(-12, bun_y), Vector2(12, bun_y - 2), Color(0.70, 0.48, 0.28), OUTLINE_W + 1.4)
	draw_stroked_circle(Vector2(0, bun_y), 7.8, BELT_BLACK, OUTLINE, OUTLINE_W)
	draw_line(Vector2(-6, bun_y + 4), Vector2(6, bun_y + 4), ROBE_INNER_RED, 2.8)

## 绘制背后展开的四色令旗（红、蓝、黄、绿）
func _draw_banner_flags(center: Vector2, rot_offset: float) -> void:
	var flags := [
		{"ang": deg_to_rad(-45.0) + rot_offset, "col": Color(0.92, 0.25, 0.25), "len": 28.0}, # 朱雀火旗
		{"ang": deg_to_rad(-20.0) + rot_offset, "col": Color(0.20, 0.70, 0.95), "len": 32.0}, # 玄武水旗
		{"ang": deg_to_rad(20.0) + rot_offset, "col": Color(0.95, 0.85, 0.20), "len": 32.0},  # 麒麟土旗
		{"ang": deg_to_rad(45.0) + rot_offset, "col": Color(0.25, 0.85, 0.45), "len": 28.0}   # 青龙木旗
	]
	for f in flags:
		var f_ang: float = f["ang"]
		var f_col: Color = f["col"]
		var f_len: float = f["len"]
		var dir := Vector2(sin(f_ang), -cos(f_ang))
		var tip: Vector2 = center + dir * f_len
		# 旗杆
		draw_line(center, tip, Color(0.65, 0.45, 0.25), 2.2)
		# 三角旗面
		var perp: Vector2 = Vector2(-dir.y, dir.x) * 7.0
		var flag_pts: PackedVector2Array = [
			tip,
			center + dir * (f_len * 0.45) + perp,
			center + dir * (f_len * 0.45)
		]
		draw_stroked_polygon(flag_pts, f_col, OUTLINE, 1.8)

## 绘制带雷火光芒的小木剑
func _draw_thunder_sword(pos: Vector2, rot: float) -> void:
	var t := Transform2D(rot, pos)
	# 剑身胖厚带雷纹
	var blade_pts: PackedVector2Array = [
		t * Vector2(0, -24),
		t * Vector2(6.0, -17),
		t * Vector2(5.0, 7),
		t * Vector2(-5.0, 7),
		t * Vector2(-6.0, -17)
	]
	draw_stroked_polygon(blade_pts, Color(0.95, 0.98, 1.0), OUTLINE, OUTLINE_W)
	# 剑心闪电电纹
	draw_line(t * Vector2(0, -20), t * Vector2(2, -10), LIGHTNING_CYAN, 2.0)
	draw_line(t * Vector2(2, -10), t * Vector2(-2, 0), LIGHTNING_CYAN, 2.0)
	draw_line(t * Vector2(-2, 0), t * Vector2(0, 6), LIGHTNING_CYAN, 2.0)

	# 纯金剑格
	var guard_pts: PackedVector2Array = [
		t * Vector2(-9, 7), t * Vector2(9, 7),
		t * Vector2(7, 11), t * Vector2(-7, 11)
	]
	draw_stroked_polygon(guard_pts, Color(0.98, 0.82, 0.24), OUTLINE, OUTLINE_W)

	# 剑柄
	draw_line(t * Vector2(0, 11), t * Vector2(0, 19), Color(0.60, 0.40, 0.22), OUTLINE_W + 1.0)
	draw_stroked_circle(t * Vector2(0, 21), 3.8, Color(0.98, 0.82, 0.24), OUTLINE, OUTLINE_W)
