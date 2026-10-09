class_name StyleKatanaZero
extends CultivatorBase

## 风格 D：武士零风 (Katana ZERO / Cyber-Wuxia 霓虹暗影流光)
## 特征：
## 1. 极致高对比度：纯黑玄墨剪影与冷冽硬折角
## 2. 刺穿黑暗的极高饱和度霓虹翡翠青绿 (#00FF88)
## 3. 随狂风暴烈飞舞的长围巾/剑穗残影流光
## 4. 低重心拔刀瞬杀动感，极具打击感与现代国潮锋芒

const SHADOW_BODY := Color(0.08, 0.10, 0.14)
const HIGHLIGHT_EDGE := Color(0.18, 0.24, 0.32)
const NEON_JADE := Color(0.05, 1.0, 0.55)          # 核心高亮荧光青
const NEON_JADE_GLOW := Color(0.10, 0.95, 0.60, 0.35)
const NEON_TRAIL := Color(0.0, 0.85, 0.45, 0.22)
const EYE_CYAN := Color(0.40, 1.0, 0.95)

func _draw_front() -> void:
	var scarf_wind := sin(_time * 7.0) * 4.0 if animate else 0.0
	var blade_glow := sin(_time * 5.0) * 0.15

	# 1. 锐利地影与脚底荧光残影
	draw_colored_polygon(PackedVector2Array([
		Vector2(-16, 26), Vector2(16, 26),
		Vector2(20, 31), Vector2(-12, 31)
	]), Color(0.04, 0.06, 0.08, 0.6))
	# 脚底刀芒折射微光
	draw_line(Vector2(-10, 29), Vector2(14, 29), NEON_JADE, 1.2)

	# 2. 玄墨硬折角道袍下裳
	var skirt_pts: PackedVector2Array = [
		Vector2(-10, 6), Vector2(10, 6),
		Vector2(14, 24), Vector2(4, 28),
		Vector2(-4, 25), Vector2(-12, 27)
	]
	draw_colored_polygon(skirt_pts, SHADOW_BODY)
	# 边缘受光面与荧光勾边
	draw_line(Vector2(-12, 27), Vector2(-4, 25), NEON_JADE, 1.8)
	draw_line(Vector2(4, 28), Vector2(14, 24), HIGHLIGHT_EDGE, 1.2)

	# 3. 躯干主干（暗黑硬角折线）
	var torso_pts: PackedVector2Array = [
		Vector2(-8, -8), Vector2(8, -8),
		Vector2(10, 6), Vector2(-8, 6)
	]
	draw_colored_polygon(torso_pts, SHADOW_BODY)

	# 4. 腰间佩剑微拔出鞘，露出一抹霓虹青刃
	var sword_pts: PackedVector2Array = [
		Vector2(-12, 10), Vector2(-4, 4), Vector2(16, -2), Vector2(18, 0), Vector2(-10, 12)
	]
	draw_colored_polygon(sword_pts, Color(0.12, 0.15, 0.20)) # 剑鞘
	# 拔出的一截荧光流光刀锋
	draw_line(Vector2(-12, 10), Vector2(-18, 14), NEON_JADE, 2.5)
	draw_soft_glow(Vector2(-15, 12), 6.0, NEON_JADE_GLOW, 3)

	# 5. 头部与冷峻双眼
	var head_pts: PackedVector2Array = [
		Vector2(-6, -18), Vector2(6, -18),
		Vector2(7, -8), Vector2(0, -6), Vector2(-7, -8)
	]
	draw_colored_polygon(head_pts, SHADOW_BODY)
	# 凌厉两道青光目芒（如刀刻般细长）
	draw_line(Vector2(-4.5, -11), Vector2(-1.5, -10.5), EYE_CYAN, 1.8)
	draw_line(Vector2(1.5, -10.5), Vector2(4.5, -11), EYE_CYAN, 1.8)
	draw_circle(Vector2(-3.0, -11), 1.0, Color.WHITE)
	draw_circle(Vector2(3.0, -11), 1.0, Color.WHITE)

	# 6. 武士零灵魂所在：狂暴飞舞的荧光翡翠长围巾/飘带
	var scarf_pts: PackedVector2Array = [
		Vector2(-3, -7), Vector2(4, -7),
		Vector2(12, -4 + scarf_wind * 0.3),
		Vector2(24 + scarf_wind * 0.8, -8 + scarf_wind),
		Vector2(32 + scarf_wind * 1.2, -6 + scarf_wind * 1.4), # 飘带尾端尖角
		Vector2(20 + scarf_wind * 0.6, 0 + scarf_wind * 0.5),
		Vector2(8, -1)
	]
	# 残影光晕
	draw_soft_glow(Vector2(22, -6 + scarf_wind), 12.0, NEON_JADE_GLOW, 3)
	draw_colored_polygon(scarf_pts, NEON_JADE)
	draw_line(Vector2(-3, -7), Vector2(32 + scarf_wind * 1.2, -6 + scarf_wind * 1.4), Color.WHITE, 1.0) # 锋利高光白芯

func _draw_side() -> void:
	var rush_wind := sin(_time * 8.0) * 5.0 if animate else 0.0

	# 1. 低姿态冲刺斜向地影
	draw_colored_polygon(PackedVector2Array([
		Vector2(-24, 25), Vector2(18, 25),
		Vector2(24, 30), Vector2(-18, 30)
	]), Color(0.04, 0.06, 0.08, 0.65))

	# 2. 凌厉后掠身形（极低重心大前倾）
	var body_pts: PackedVector2Array = [
		Vector2(-14, 22), Vector2(8, 20),
		Vector2(14, 8), Vector2(6, -6),
		Vector2(-4, -12), Vector2(-16, 2)
	]
	draw_colored_polygon(body_pts, SHADOW_BODY)
	draw_polyline(body_pts, HIGHLIGHT_EDGE, 1.2, true)

	# 3. 头部低俯（侧面冷酷剪影）
	var head_pts: PackedVector2Array = [
		Vector2(4, -14), Vector2(14, -10),
		Vector2(12, -4), Vector2(2, -5)
	]
	draw_colored_polygon(head_pts, SHADOW_BODY)
	# 侧面冷酷长条青眼光芒
	draw_line(Vector2(8, -8), Vector2(14, -8), EYE_CYAN, 2.0)

	# 4. 瞬杀拔刀！前方挥出的耀眼霓虹青斩击弧线
	var arc_center := Vector2(14, 4)
	draw_arc(arc_center, 24.0, deg_to_rad(-70.0), deg_to_rad(45.0), 16, NEON_JADE, 3.2, true)
	draw_arc(arc_center, 24.0, deg_to_rad(-65.0), deg_to_rad(40.0), 16, Color.WHITE, 1.4, true)
	# 斩击残影羽化面
	draw_soft_glow(arc_center + Vector2(18, -10), 14.0, NEON_JADE_GLOW, 4)

	# 5. 身后笔直向后暴烈撕裂的荧光围巾（速度感拉满）
	var scarf_pts: PackedVector2Array = [
		Vector2(0, -6), Vector2(-4, -10),
		Vector2(-22 + rush_wind * 0.5, -12 + rush_wind * 0.4),
		Vector2(-38 + rush_wind, -10 + rush_wind * 0.8), # 极长拖尾
		Vector2(-20 + rush_wind * 0.3, -4),
		Vector2(-6, -2)
	]
	draw_colored_polygon(scarf_pts, NEON_JADE)
	draw_line(Vector2(0, -6), Vector2(-38 + rush_wind, -10 + rush_wind * 0.8), Color.WHITE, 1.2)

func _draw_back() -> void:
	var wind := sin(_time * 6.5) * 4.0 if animate else 0.0

	# 1. 地影
	draw_colored_polygon(PackedVector2Array([
		Vector2(-16, 26), Vector2(16, 26),
		Vector2(20, 31), Vector2(-12, 31)
	]), Color(0.04, 0.06, 0.08, 0.6))

	# 2. 玄墨斗篷后背剪影（如苍松峭壁）
	var back_pts: PackedVector2Array = [
		Vector2(-10, -8), Vector2(10, -8),
		Vector2(15, 24), Vector2(-15, 24)
	]
	draw_colored_polygon(back_pts, SHADOW_BODY)
	draw_line(Vector2(-15, 24), Vector2(15, 24), HIGHLIGHT_EDGE, 1.2)

	# 3. 背后斜负之黑色剑鞘与发光符文
	var sheath_pts: PackedVector2Array = [
		Vector2(-6, 22), Vector2(12, -14), Vector2(15, -12), Vector2(-3, 24)
	]
	draw_colored_polygon(sheath_pts, Color(0.14, 0.18, 0.24))
	# 剑鞘上的荧光青绿道法符文点线
	draw_line(Vector2(-1, 14), Vector2(9, -6), NEON_JADE, 1.8)
	draw_circle(Vector2(4, 4), 2.0, NEON_JADE)

	# 4. 后脑束发与发簪
	draw_circle(Vector2(0, -14), 8.0, SHADOW_BODY)
	draw_line(Vector2(-8, -16), Vector2(8, -16), HIGHLIGHT_EDGE, 1.5)

	# 5. 向左右两侧暴烈吹卷的荧光围巾
	var scarf_pts: PackedVector2Array = [
		Vector2(-4, -8), Vector2(4, -8),
		Vector2(18 + wind * 0.6, -16 + wind),
		Vector2(28 + wind, -14 + wind * 1.2),
		Vector2(12 + wind * 0.4, -6),
		Vector2(-2, -6)
	]
	draw_soft_glow(Vector2(18, -12 + wind), 10.0, NEON_JADE_GLOW, 3)
	draw_colored_polygon(scarf_pts, NEON_JADE)
	draw_line(Vector2(0, -8), Vector2(28 + wind, -14 + wind * 1.2), Color.WHITE, 1.0)
