class_name StyleKatanaZero
extends CultivatorBase

## 风格 D：武士零风 (Katana ZERO / Cyber-Wuxia 霓虹暗影流光)
## 特征：
## 1. 极致高对比度：玄墨剑客剪影与冷冽硬折角
## 2. 刺穿黑暗的极高饱和度霓虹翡翠青碧 (#00FF88)
## 3. 随狂风暴烈飞舞的长围巾/剑穗残影流光
## 4. 低重心拔刀瞬杀动感，极具打击感与现代国潮锋芒

const SHADOW_BODY := Color(0.14, 0.18, 0.24)       # 暗夜深玄蓝黑
const BODY_DARK := Color(0.09, 0.11, 0.16)         # 内部暗影折褶
const HIGHLIGHT_EDGE := Color(0.35, 0.46, 0.60)    # 冷冽轮廓边缘线
const NEON_JADE := Color(0.05, 1.0, 0.55)          # 核心高亮荧光青
const NEON_JADE_GLOW := Color(0.10, 0.95, 0.60, 0.35)
const EYE_CYAN := Color(0.40, 1.0, 0.95)

func _draw_front() -> void:
	var scarf_wind := sin(_time * 7.0) * 4.0 if animate else 0.0

	# 1. 锐利地影与脚底荧光残影
	draw_colored_polygon(PackedVector2Array([
		Vector2(-16, 26), Vector2(16, 26),
		Vector2(20, 31), Vector2(-12, 31)
	]), Color(0.04, 0.06, 0.08, 0.6))
	# 脚底刀芒折射微光
	draw_line(Vector2(-12, 29), Vector2(14, 29), NEON_JADE, 1.4)

	# 2. 双腿站姿（玄墨紧腿道靴）
	draw_line(Vector2(-6, 20), Vector2(-7, 28), SHADOW_BODY, 4.0)
	draw_line(Vector2(-6, 20), Vector2(-7, 28), HIGHLIGHT_EDGE, 1.2)
	draw_line(Vector2(6, 20), Vector2(7, 28), SHADOW_BODY, 4.0)
	draw_line(Vector2(6, 20), Vector2(7, 28), HIGHLIGHT_EDGE, 1.2)

	# 3. 玄墨硬折角道袍下裳
	var skirt_pts: PackedVector2Array = [
		Vector2(-10, 4), Vector2(10, 4),
		Vector2(14, 22), Vector2(4, 26),
		Vector2(-4, 23), Vector2(-12, 25)
	]
	draw_colored_polygon(skirt_pts, SHADOW_BODY)
	draw_polyline(skirt_pts, HIGHLIGHT_EDGE, 1.4, true)
	# 裙摆荧光切线
	draw_line(Vector2(-12, 25), Vector2(-4, 23), NEON_JADE, 2.0)

	# 4. 躯干主干（硬朗倒三角剪影）
	var torso_pts: PackedVector2Array = [
		Vector2(-10, -9), Vector2(10, -9),
		Vector2(8, 4), Vector2(-8, 4)
	]
	draw_colored_polygon(torso_pts, SHADOW_BODY)
	draw_polyline(torso_pts, HIGHLIGHT_EDGE, 1.2, true)
	# 玄金扣腰带
	draw_line(Vector2(-9, 3), Vector2(9, 3), Color(0.85, 0.72, 0.25), 2.0)

	# 5. 腰间佩剑微拔出鞘，露出一抹霓虹青刃
	var sword_pts: PackedVector2Array = [
		Vector2(-12, 9), Vector2(-4, 3), Vector2(15, -3), Vector2(17, -1), Vector2(-10, 11)
	]
	draw_colored_polygon(sword_pts, Color(0.18, 0.22, 0.28))
	draw_polyline(sword_pts, HIGHLIGHT_EDGE, 1.0, true)
	# 拔出的一截荧光流光刀锋
	draw_line(Vector2(-12, 9), Vector2(-20, 14), NEON_JADE, 3.0)
	draw_line(Vector2(-12, 9), Vector2(-20, 14), Color.WHITE, 1.2)
	draw_soft_glow(Vector2(-16, 11), 8.0, NEON_JADE_GLOW, 3)

	# 6. 头部与冷峻双眼
	var head_pts: PackedVector2Array = [
		Vector2(-7, -20), Vector2(7, -20),
		Vector2(8, -9), Vector2(0, -7), Vector2(-8, -9)
	]
	draw_colored_polygon(head_pts, SHADOW_BODY)
	draw_polyline(head_pts, HIGHLIGHT_EDGE, 1.2, true)
	# 凌厉两道青光目芒
	draw_line(Vector2(-5.0, -12), Vector2(-1.5, -11.5), EYE_CYAN, 2.0)
	draw_line(Vector2(1.5, -11.5), Vector2(5.0, -12), EYE_CYAN, 2.0)
	draw_circle(Vector2(-3.2, -12), 1.0, Color.WHITE)
	draw_circle(Vector2(3.2, -12), 1.0, Color.WHITE)

	# 7. 武士零灵魂所在：狂暴飞舞的荧光翡翠长围巾/飘带
	var scarf_pts: PackedVector2Array = [
		Vector2(-4, -8), Vector2(4, -8),
		Vector2(14, -5 + scarf_wind * 0.3),
		Vector2(26 + scarf_wind * 0.8, -10 + scarf_wind),
		Vector2(36 + scarf_wind * 1.2, -7 + scarf_wind * 1.4), # 飘带尾端尖角
		Vector2(22 + scarf_wind * 0.6, 1 + scarf_wind * 0.5),
		Vector2(8, 0)
	]
	draw_soft_glow(Vector2(24, -7 + scarf_wind), 14.0, NEON_JADE_GLOW, 3)
	draw_colored_polygon(scarf_pts, NEON_JADE)
	draw_line(Vector2(-4, -8), Vector2(36 + scarf_wind * 1.2, -7 + scarf_wind * 1.4), Color.WHITE, 1.4)

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
	draw_polyline(body_pts, HIGHLIGHT_EDGE, 1.4, true)

	# 3. 头部低俯（侧面冷酷剪影）
	var head_pts: PackedVector2Array = [
		Vector2(4, -15), Vector2(15, -11),
		Vector2(13, -4), Vector2(2, -5)
	]
	draw_colored_polygon(head_pts, SHADOW_BODY)
	draw_polyline(head_pts, HIGHLIGHT_EDGE, 1.2, true)
	# 侧面冷酷长条青眼光芒
	draw_line(Vector2(8, -8), Vector2(15, -8), EYE_CYAN, 2.2)

	# 4. 瞬杀拔刀！前方挥出的耀眼霓虹青斩击弧线
	var arc_center := Vector2(14, 4)
	draw_arc(arc_center, 24.0, deg_to_rad(-70.0), deg_to_rad(45.0), 20, NEON_JADE, 3.6, true)
	draw_arc(arc_center, 24.0, deg_to_rad(-65.0), deg_to_rad(40.0), 20, Color.WHITE, 1.6, true)
	draw_soft_glow(arc_center + Vector2(18, -10), 16.0, NEON_JADE_GLOW, 4)

	# 5. 身后笔直向后暴烈撕裂的荧光围巾
	var scarf_pts: PackedVector2Array = [
		Vector2(0, -6), Vector2(-4, -10),
		Vector2(-22 + rush_wind * 0.5, -12 + rush_wind * 0.4),
		Vector2(-40 + rush_wind, -10 + rush_wind * 0.8),
		Vector2(-20 + rush_wind * 0.3, -3),
		Vector2(-6, -2)
	]
	draw_soft_glow(Vector2(-24 + rush_wind * 0.6, -10), 14.0, NEON_JADE_GLOW, 3)
	draw_colored_polygon(scarf_pts, NEON_JADE)
	draw_line(Vector2(0, -6), Vector2(-40 + rush_wind, -10 + rush_wind * 0.8), Color.WHITE, 1.4)

func _draw_back() -> void:
	var wind := sin(_time * 6.5) * 4.0 if animate else 0.0

	# 1. 地影
	draw_colored_polygon(PackedVector2Array([
		Vector2(-16, 26), Vector2(16, 26),
		Vector2(20, 31), Vector2(-12, 31)
	]), Color(0.04, 0.06, 0.08, 0.6))

	# 2. 玄墨斗篷后背剪影
	var back_pts: PackedVector2Array = [
		Vector2(-10, -9), Vector2(10, -9),
		Vector2(15, 23), Vector2(-15, 23)
	]
	draw_colored_polygon(back_pts, SHADOW_BODY)
	draw_polyline(back_pts, HIGHLIGHT_EDGE, 1.4, true)

	# 3. 背后斜负之黑色剑鞘与发光符文
	var sheath_pts: PackedVector2Array = [
		Vector2(-6, 22), Vector2(12, -14), Vector2(15, -12), Vector2(-3, 24)
	]
	draw_colored_polygon(sheath_pts, Color(0.20, 0.25, 0.32))
	draw_polyline(sheath_pts, HIGHLIGHT_EDGE, 1.0, true)
	# 剑鞘上的荧光青绿道法符文点线
	draw_line(Vector2(-1, 14), Vector2(9, -6), NEON_JADE, 2.2)
	draw_circle(Vector2(4, 4), 2.4, NEON_JADE)
	draw_soft_glow(Vector2(4, 4), 6.0, NEON_JADE_GLOW, 2)

	# 4. 后脑束发与发簪
	draw_circle(Vector2(0, -14), 8.5, SHADOW_BODY)
	draw_arc(Vector2(0, -14), 8.5, 0, TAU, 24, HIGHLIGHT_EDGE, 1.2, true)
	draw_line(Vector2(-9, -15), Vector2(9, -15), Color(0.85, 0.72, 0.25), 1.8)

	# 5. 向左右两侧暴烈吹卷的荧光围巾
	var scarf_pts: PackedVector2Array = [
		Vector2(-4, -8), Vector2(4, -8),
		Vector2(18 + wind * 0.6, -16 + wind),
		Vector2(30 + wind, -14 + wind * 1.2),
		Vector2(14 + wind * 0.4, -5),
		Vector2(-2, -6)
	]
	draw_soft_glow(Vector2(18, -12 + wind), 12.0, NEON_JADE_GLOW, 3)
	draw_colored_polygon(scarf_pts, NEON_JADE)
	draw_line(Vector2(0, -8), Vector2(30 + wind, -14 + wind * 1.2), Color.WHITE, 1.2)
