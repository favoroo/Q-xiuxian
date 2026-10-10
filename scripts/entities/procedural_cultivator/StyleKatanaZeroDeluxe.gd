class_name StyleKatanaZeroDeluxe
extends CultivatorBase

## 风格 D 豪华版：武士零风 · 暗夜断罪剑魔 (Katana ZERO Deluxe)
## 特征：
## 1. 玄墨战衣 + 冷钢护甲，硬折角破损流浪者风衣
## 2. 赛博双色碰撞：电光青碧 (#00FFAA) 与 赛博洋红霓虹紫 (#FF007F)
## 3. 长达数十像素的暴烈双色能量流光围巾，随狂风撕裂飞扬
## 4. 半遮面激光冷芒双目与高频等离子太刀瞬斩
## 5. 后背发光赛博八卦电路阵与脚底电浆碎屑

const SUIT_BLACK := Color(0.11, 0.14, 0.19)
const ARMOR_STEEL := Color(0.28, 0.35, 0.46)
const RIM_HIGHLIGHT := Color(0.45, 0.58, 0.72)
const NEON_CYAN := Color(0.0, 1.0, 0.65)           # 核心电光青
const NEON_MAGENTA := Color(1.0, 0.05, 0.50)        # 赛博洋红紫
const NEON_GLOW_CYAN := Color(0.0, 1.0, 0.65, 0.38)
const NEON_GLOW_MAGENTA := Color(1.0, 0.05, 0.50, 0.35)

func _draw_front() -> void:
	var scarf_wind := sin(_time * 7.5) * 4.5 if animate else 0.0
	var spark_flicker := sin(_time * 15.0) * 0.15

	# 1. 锐利多边形地影与地面电浆光晕
	draw_colored_polygon(PackedVector2Array([
		Vector2(-18, 27), Vector2(18, 27),
		Vector2(24, 32), Vector2(-14, 32)
	]), Color(0.03, 0.05, 0.08, 0.65))
	# 地面折射的双色电火花
	draw_line(Vector2(-14, 30), Vector2(6, 30), NEON_CYAN, 1.5)
	draw_line(Vector2(6, 30), Vector2(18, 30), NEON_MAGENTA, 1.5)

	# 2. 双腿站姿（紧绷战靴配冷钢护膝）
	draw_line(Vector2(-7, 20), Vector2(-8, 28), SUIT_BLACK, 4.5)
	draw_circle(Vector2(-7.5, 23), 2.2, ARMOR_STEEL) # 护膝
	draw_line(Vector2(7, 20), Vector2(8, 28), SUIT_BLACK, 4.5)
	draw_circle(Vector2(7.5, 23), 2.2, ARMOR_STEEL)

	# 3. 破损流浪者风衣下裳（利落硬折角）
	var coat_pts: PackedVector2Array = [
		Vector2(-11, 4), Vector2(11, 4),
		Vector2(16, 23), Vector2(5, 27),
		Vector2(-5, 24), Vector2(-14, 26)
	]
	draw_colored_polygon(coat_pts, SUIT_BLACK)
	draw_polyline(coat_pts, RIM_HIGHLIGHT, 1.4, true)
	# 边缘电光切线
	draw_line(Vector2(-14, 26), Vector2(-5, 24), NEON_CYAN, 2.0)
	draw_line(Vector2(5, 27), Vector2(16, 23), NEON_MAGENTA, 1.8)

	# 4. 上身倒三角躯干与金属护肩
	var torso_pts: PackedVector2Array = [
		Vector2(-11, -10), Vector2(11, -10),
		Vector2(9, 4), Vector2(-9, 4)
	]
	draw_colored_polygon(torso_pts, SUIT_BLACK)
	draw_polyline(torso_pts, RIM_HIGHLIGHT, 1.2, true)
	# 左右合金护肩
	draw_stroked_circle(Vector2(-11, -9), 3.2, ARMOR_STEEL, RIM_HIGHLIGHT, 1.0)
	draw_stroked_circle(Vector2(11, -9), 3.2, ARMOR_STEEL, RIM_HIGHLIGHT, 1.0)

	# 5. 腰间双剑鞘与拔出的一截高频等离子太刀
	var sheath_pts: PackedVector2Array = [
		Vector2(-14, 10), Vector2(-4, 3), Vector2(16, -4), Vector2(18, -2), Vector2(-11, 12)
	]
	draw_colored_polygon(sheath_pts, Color(0.18, 0.22, 0.28))
	draw_polyline(sheath_pts, RIM_HIGHLIGHT, 1.0, true)
	# 拔出的一截青芒等离子刃
	draw_line(Vector2(-14, 10), Vector2(-23, 15), NEON_CYAN, 3.2)
	draw_line(Vector2(-14, 10), Vector2(-23, 15), Color.WHITE, 1.4)
	draw_soft_glow(Vector2(-18, 12), 10.0, NEON_GLOW_CYAN, 3)

	# 6. 头部、狂放碎发与激光双目
	var head_pts: PackedVector2Array = [
		Vector2(-8, -22), Vector2(8, -22),
		Vector2(9, -10), Vector2(0, -8), Vector2(-9, -10)
	]
	draw_colored_polygon(head_pts, SUIT_BLACK)
	draw_polyline(head_pts, RIM_HIGHLIGHT, 1.2, true)
	# 额前散落的硬折角发丝
	draw_line(Vector2(-6, -22), Vector2(-8, -13), SUIT_BLACK, 2.5)
	draw_line(Vector2(6, -22), Vector2(8, -13), SUIT_BLACK, 2.5)

	# 激光冷芒双目（青蓝与洋红交相辉映）
	draw_line(Vector2(-5.5, -13), Vector2(-1.5, -12.5), NEON_CYAN, 2.2)
	draw_line(Vector2(1.5, -12.5), Vector2(5.5, -13), NEON_MAGENTA, 2.2)
	draw_circle(Vector2(-3.5, -13), 1.1, Color.WHITE)
	draw_circle(Vector2(3.5, -13), 1.1, Color.WHITE)

	# 7. 武士零灵魂所在：狂暴飞舞的双色能量流光长围巾
	# 双层渐变光带（内层青碧，外层洋红拖尾）
	var scarf_pts: PackedVector2Array = [
		Vector2(-5, -9), Vector2(5, -9),
		Vector2(15, -6 + scarf_wind * 0.3),
		Vector2(28 + scarf_wind * 0.8, -11 + scarf_wind),
		Vector2(40 + scarf_wind * 1.2, -8 + scarf_wind * 1.4), # 极长尖端
		Vector2(24 + scarf_wind * 0.6, 2 + scarf_wind * 0.5),
		Vector2(9, 1)
	]
	draw_soft_glow(Vector2(28, -8 + scarf_wind), 16.0, NEON_GLOW_CYAN, 3)
	draw_soft_glow(Vector2(38 + scarf_wind, -8 + scarf_wind), 12.0, NEON_GLOW_MAGENTA, 3)
	draw_colored_polygon(scarf_pts, NEON_CYAN)
	# 洋红拖尾尖角
	draw_colored_polygon(PackedVector2Array([
		Vector2(24 + scarf_wind * 0.6, 2 + scarf_wind * 0.5),
		Vector2(40 + scarf_wind * 1.2, -8 + scarf_wind * 1.4),
		Vector2(32 + scarf_wind, 4 + scarf_wind)
	]), NEON_MAGENTA)
	# 纯白能量高光中芯
	draw_line(Vector2(-5, -9), Vector2(40 + scarf_wind * 1.2, -8 + scarf_wind * 1.4), Color.WHITE, 1.4)

func _draw_side() -> void:
	var rush_wind := sin(_time * 8.5) * 5.5 if animate else 0.0

	# 1. 极低重心冲刺地影
	draw_colored_polygon(PackedVector2Array([
		Vector2(-26, 26), Vector2(20, 26),
		Vector2(26, 31), Vector2(-20, 31)
	]), Color(0.03, 0.05, 0.08, 0.70))

	# 2. 贴地俯冲身躯（战意倾泻）
	var body_pts: PackedVector2Array = [
		Vector2(-16, 23), Vector2(9, 21),
		Vector2(16, 8), Vector2(7, -7),
		Vector2(-5, -13), Vector2(-18, 3)
	]
	draw_colored_polygon(body_pts, SUIT_BLACK)
	draw_polyline(body_pts, RIM_HIGHLIGHT, 1.4, true)

	# 3. 头部低俯
	var head_pts: PackedVector2Array = [
		Vector2(5, -16), Vector2(17, -11),
		Vector2(14, -3), Vector2(3, -5)
	]
	draw_colored_polygon(head_pts, SUIT_BLACK)
	draw_polyline(head_pts, RIM_HIGHLIGHT, 1.2, true)
	draw_line(Vector2(9, -9), Vector2(17, -9), NEON_CYAN, 2.4) # 侧向激光眼

	# 4. 瞬杀拔刀！前方挥出的双色霓虹半月斩裂空弧光
	var arc_center := Vector2(16, 4)
	# 外层洋红烈芒
	draw_arc(arc_center, 28.0, deg_to_rad(-75.0), deg_to_rad(50.0), 24, NEON_MAGENTA, 4.2, true)
	# 内层电光青核心
	draw_arc(arc_center, 27.0, deg_to_rad(-70.0), deg_to_rad(45.0), 24, NEON_CYAN, 2.8, true)
	draw_arc(arc_center, 27.0, deg_to_rad(-65.0), deg_to_rad(40.0), 24, Color.WHITE, 1.5, true)
	draw_soft_glow(arc_center + Vector2(20, -10), 18.0, NEON_GLOW_CYAN, 4)

	# 5. 身后撕裂拖曳的超长能量围巾
	var scarf_pts: PackedVector2Array = [
		Vector2(0, -7), Vector2(-5, -11),
		Vector2(-25 + rush_wind * 0.5, -14 + rush_wind * 0.4),
		Vector2(-46 + rush_wind, -11 + rush_wind * 0.8), # 极长拖尾
		Vector2(-22 + rush_wind * 0.3, -3),
		Vector2(-7, -2)
	]
	draw_soft_glow(Vector2(-30 + rush_wind * 0.6, -11), 16.0, NEON_GLOW_CYAN, 3)
	draw_colored_polygon(scarf_pts, NEON_CYAN)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-25 + rush_wind * 0.5, -14 + rush_wind * 0.4),
		Vector2(-46 + rush_wind, -11 + rush_wind * 0.8),
		Vector2(-35 + rush_wind, -4)
	]), NEON_MAGENTA)
	draw_line(Vector2(0, -7), Vector2(-46 + rush_wind, -11 + rush_wind * 0.8), Color.WHITE, 1.5)

func _draw_back() -> void:
	var wind := sin(_time * 7.0) * 4.5 if animate else 0.0

	# 1. 地影
	draw_colored_polygon(PackedVector2Array([
		Vector2(-18, 27), Vector2(18, 27),
		Vector2(24, 32), Vector2(-14, 32)
	]), Color(0.03, 0.05, 0.08, 0.65))

	# 2. 玄墨风衣后背剪影
	var back_pts: PackedVector2Array = [
		Vector2(-11, -10), Vector2(11, -10),
		Vector2(16, 24), Vector2(-16, 24)
	]
	draw_colored_polygon(back_pts, SUIT_BLACK)
	draw_polyline(back_pts, RIM_HIGHLIGHT, 1.4, true)

	# 3. 后背发光的赛博八卦电路阵
	var hex_center := Vector2(0, 5)
	draw_arc(hex_center, 6.0, 0, TAU, 6, NEON_CYAN, 1.5, true) # 六角符文
	draw_circle(hex_center, 2.0, NEON_MAGENTA)
	draw_line(hex_center + Vector2(0, -6), hex_center + Vector2(0, -12), NEON_CYAN, 1.2) # 能量导线
	draw_soft_glow(hex_center, 8.0, NEON_GLOW_CYAN, 2)

	# 4. 背后斜负之黑色刀鞘与发光符文
	var sheath_pts: PackedVector2Array = [
		Vector2(-7, 23), Vector2(13, -15), Vector2(16, -13), Vector2(-4, 25)
	]
	draw_colored_polygon(sheath_pts, Color(0.22, 0.28, 0.36))
	draw_polyline(sheath_pts, RIM_HIGHLIGHT, 1.0, true)
	draw_line(Vector2(-2, 14), Vector2(10, -6), NEON_CYAN, 2.4)
	draw_circle(Vector2(5, 4), 2.6, NEON_MAGENTA)

	# 5. 后脑长发与向两侧暴烈吹卷的能量围巾
	draw_circle(Vector2(0, -15), 9.0, SUIT_BLACK)
	draw_arc(Vector2(0, -15), 9.0, 0, TAU, 24, RIM_HIGHLIGHT, 1.2, true)

	var scarf_pts: PackedVector2Array = [
		Vector2(-5, -9), Vector2(5, -9),
		Vector2(20 + wind * 0.6, -18 + wind),
		Vector2(34 + wind, -15 + wind * 1.2),
		Vector2(15 + wind * 0.4, -6),
		Vector2(-3, -6)
	]
	draw_soft_glow(Vector2(20, -14 + wind), 14.0, NEON_GLOW_CYAN, 3)
	draw_colored_polygon(scarf_pts, NEON_CYAN)
	draw_line(Vector2(0, -9), Vector2(34 + wind, -15 + wind * 1.2), Color.WHITE, 1.4)
