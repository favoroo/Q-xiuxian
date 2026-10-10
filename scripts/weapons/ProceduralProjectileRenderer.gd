class_name ProceduralProjectileRenderer
extends Node2D

## 纯矢量弹道渲染器（冷冽国风修仙）
## 取代低清像素 bullet_*.png，实现高频无损旋转、精准物理咬合、动态流光与气刃尾迹

enum ProjectileKind {
	SWORD_GOLD,       ## 庚金飞剑：修长冷银双刃古剑 + 庚金锋芒
	DAGGER_LEAF,      ## 柳叶飞刀：弯月柳叶飞刃 + 青金光痕
	NEEDLE_SILVER,    ## 暴雨银针：极细破空银针 + 针尖寒芒
	NEEDLE_ICE,       ## 玄冰飞针：幽蓝冰晶细棱 + 冰晶碎屑
	TALISMAN_FIRE,    ## 火焰符：炽朱离火符纸 + 暗红朱砂阵印
	TALISMAN_WOOD,    ## 万木灵符：碧翠玉灵符纸 + 生机灵文
	FIRE_FLAME,       ## 三昧真火：水墨烈焰火煞 + 炽金火核
	SPIRIT_PELLET,    ## 连环灵弹：凝元翡翠光珠 + 环绕星轨
	GENERIC_BLADE     ## 通用法刃：虚空冷月气刃
}

@export var kind: ProjectileKind = ProjectileKind.GENERIC_BLADE
@export var elemental_tint: Color = Color.WHITE

var _lifetime_acc: float = 0.0

func _ready() -> void:
	queue_redraw()

func _process(delta: float) -> void:
	_lifetime_acc += delta
	# 某些带流光/呼吸的弹丸轻微刷新绘制
	if kind == ProjectileKind.FIRE_FLAME or kind == ProjectileKind.SPIRIT_PELLET:
		queue_redraw()

## 根据贴图路径或武器 ID 自适应识别弹丸品类
static func detect_kind_from_path(tex_path: String) -> ProjectileKind:
	if "bullet_gold_sword" in tex_path:
		return ProjectileKind.SWORD_GOLD
	elif "bullet_leaf_dagger" in tex_path:
		return ProjectileKind.DAGGER_LEAF
	elif "bullet_silver_needle" in tex_path:
		return ProjectileKind.NEEDLE_SILVER
	elif "bullet_ice_needle" in tex_path:
		return ProjectileKind.NEEDLE_ICE
	elif "bullet_fire_talisman" in tex_path:
		return ProjectileKind.TALISMAN_FIRE
	elif "bullet_wood_talisman" in tex_path:
		return ProjectileKind.TALISMAN_WOOD
	elif "bullet_fire_flame" in tex_path:
		return ProjectileKind.FIRE_FLAME
	elif "bullet_spirit_pellet" in tex_path:
		return ProjectileKind.SPIRIT_PELLET
	return ProjectileKind.GENERIC_BLADE

func _draw() -> void:
	match kind:
		ProjectileKind.SWORD_GOLD:
			_draw_gengjin_sword()
		ProjectileKind.DAGGER_LEAF:
			_draw_leaf_dagger()
		ProjectileKind.NEEDLE_SILVER:
			_draw_silver_needle()
		ProjectileKind.NEEDLE_ICE:
			_draw_ice_needle()
		ProjectileKind.TALISMAN_FIRE:
			_draw_talisman(Color(0.85, 0.28, 0.20), Color(1.0, 0.82, 0.35))
		ProjectileKind.TALISMAN_WOOD:
			_draw_talisman(Color(0.20, 0.55, 0.38), Color(0.60, 0.95, 0.70))
		ProjectileKind.FIRE_FLAME:
			_draw_flame()
		ProjectileKind.SPIRIT_PELLET:
			_draw_spirit_pellet()
		ProjectileKind.GENERIC_BLADE:
			_draw_generic_blade()

# ----------------- 1. 庚金飞剑 (双刃骨白古剑 + 庚金锐芒 + 剑气尾迹) -----------------
func _draw_gengjin_sword() -> void:
	# 剑气外晕 (微弱半透明冷金光晕)
	var glow_poly := PackedVector2Array([
		Vector2(16.0, 0.0),
		Vector2(-4.0, -4.5),
		Vector2(-14.0, -2.0),
		Vector2(-18.0, 0.0),
		Vector2(-14.0, 2.0),
		Vector2(-4.0, 4.5)
	])
	draw_colored_polygon(glow_poly, Color(0.95, 0.80, 0.35, 0.22))

	# 剑身主刃 (骨白双刃，锋尖位于 +X 轴 14.0)
	var blade_top := PackedVector2Array([
		Vector2(14.0, 0.0),
		Vector2(-2.0, -3.2),
		Vector2(-10.0, -3.0),
		Vector2(-11.0, 0.0)
	])
	draw_colored_polygon(blade_top, Color(0.92, 0.94, 0.98)) # 阳面骨白

	var blade_bot := PackedVector2Array([
		Vector2(14.0, 0.0),
		Vector2(-11.0, 0.0),
		Vector2(-10.0, 3.0),
		Vector2(-2.0, 3.2)
	])
	draw_colored_polygon(blade_bot, Color(0.70, 0.76, 0.84)) # 阴面冷灰

	# 中脊骨棱脊线 (亮金冷光锐线)
	draw_line(Vector2(14.0, 0.0), Vector2(-11.0, 0.0), Color(1.0, 0.88, 0.45), 1.0, true)

	# 剑首剑格与剑柄
	draw_line(Vector2(-10.0, -3.5), Vector2(-10.0, 3.5), Color(0.20, 0.18, 0.25), 1.5, true)
	draw_line(Vector2(-10.0, 0.0), Vector2(-15.0, 0.0), Color(0.12, 0.12, 0.16), 1.5, true)
	draw_circle(Vector2(-15.5, 0.0), 1.2, Color(0.92, 0.76, 0.28))

# ----------------- 2. 柳叶飞刀 (流线柳叶弯刃 + 青金光痕) -----------------
func _draw_leaf_dagger() -> void:
	var dagger_pts := PackedVector2Array([
		Vector2(11.0, 0.0),
		Vector2(2.0, -3.0),
		Vector2(-8.0, -2.0),
		Vector2(-10.0, 0.0),
		Vector2(-8.0, 2.0),
		Vector2(2.0, 3.0)
	])
	draw_colored_polygon(dagger_pts, Color(0.88, 0.92, 0.96))
	# 背脊青金流光
	draw_line(Vector2(11.0, 0.0), Vector2(-8.0, 0.0), Color(0.35, 0.85, 0.65), 1.0, true)
	# 刀尾配重
	draw_circle(Vector2(-9.0, 0.0), 1.2, Color(0.10, 0.12, 0.16))

# ----------------- 3. 暴雨银针 (极细冷银破空针) -----------------
func _draw_silver_needle() -> void:
	# 破空虚影
	draw_line(Vector2(10.0, 0.0), Vector2(-12.0, 0.0), Color(0.95, 0.95, 1.0, 0.35), 2.2, true)
	# 针体核心
	draw_line(Vector2(10.0, 0.0), Vector2(-8.0, 0.0), Color(0.98, 0.98, 1.0), 1.0, true)
	# 针尖锐芒光点
	draw_circle(Vector2(10.0, 0.0), 1.0, Color.WHITE)

# ----------------- 4. 玄冰飞针 (晶莹透光幽蓝冰锥) -----------------
func _draw_ice_needle() -> void:
	# 冰晶外晕
	draw_line(Vector2(12.0, 0.0), Vector2(-10.0, 0.0), Color(0.40, 0.80, 1.0, 0.40), 3.0, true)
	# 多面晶体锥体
	var top_pts := PackedVector2Array([
		Vector2(12.0, 0.0),
		Vector2(-1.0, -2.0),
		Vector2(-8.0, -1.5),
		Vector2(-8.0, 0.0)
	])
	draw_colored_polygon(top_pts, Color(0.70, 0.92, 1.0))
	var bot_pts := PackedVector2Array([
		Vector2(12.0, 0.0),
		Vector2(-8.0, 0.0),
		Vector2(-8.0, 1.5),
		Vector2(-1.0, 2.0)
	])
	draw_colored_polygon(bot_pts, Color(0.30, 0.65, 0.95))
	# 冰棱脊线
	draw_line(Vector2(12.0, 0.0), Vector2(-8.0, 0.0), Color(0.90, 0.98, 1.0), 0.8, true)

# ----------------- 5. 火木神符 (长方形古朴符纸 + 朱砂/青灵符纹) -----------------
func _draw_talisman(border_col: Color, rune_col: Color) -> void:
	# 符纸底板 (16x10px 长方形，居中偏左以便视觉朝向)
	var rect := Rect2(-8.0, -5.0, 16.0, 10.0)
	# 符纸骨黄质感
	draw_rect(rect, Color(0.92, 0.88, 0.78), true)
	# 边框勾勒
	draw_rect(rect, border_col, false, 1.0)
	# 符头朱砂印
	draw_circle(Vector2(5.0, 0.0), 1.8, border_col)
	# 符胆灵文线条 (朱砂/青灵阵纹)
	draw_line(Vector2(3.0, 0.0), Vector2(-5.0, 0.0), rune_col, 1.2, true)
	draw_line(Vector2(-1.0, -2.5), Vector2(-1.0, 2.5), rune_col, 1.0, true)
	draw_line(Vector2(-4.0, -2.0), Vector2(-4.0, 2.0), rune_col, 0.8, true)

# ----------------- 6. 三昧真火 (流光火核与烈火水滴) -----------------
func _draw_flame() -> void:
	var pulse := 1.0 + sin(_lifetime_acc * 18.0) * 0.12
	# 外层暗赤火煞
	var outer_flame := PackedVector2Array([
		Vector2(10.0 * pulse, 0.0),
		Vector2(2.0, -5.5 * pulse),
		Vector2(-6.0, -4.0),
		Vector2(-8.0, 0.0),
		Vector2(-6.0, 4.0),
		Vector2(2.0, 5.5 * pulse)
	])
	draw_colored_polygon(outer_flame, Color(0.85, 0.25, 0.15, 0.75))

	# 中层炽金烈焰
	var mid_flame := PackedVector2Array([
		Vector2(8.0 * pulse, 0.0),
		Vector2(1.0, -3.5 * pulse),
		Vector2(-4.0, -2.5),
		Vector2(-5.0, 0.0),
		Vector2(-4.0, 2.5),
		Vector2(1.0, 3.5 * pulse)
	])
	draw_colored_polygon(mid_flame, Color(1.0, 0.65, 0.20, 0.90))

	# 内层白炽真火灵核
	draw_circle(Vector2(2.0, 0.0), 2.2 * pulse, Color(1.0, 0.95, 0.85))

# ----------------- 7. 连环灵弹 (翡翠灵珠 + 环绕星环) -----------------
func _draw_spirit_pellet() -> void:
	# 翡翠灵珠核心
	draw_circle(Vector2.ZERO, 5.0, Color(0.20, 0.65, 0.45))
	draw_circle(Vector2(1.0, -1.0), 3.0, Color(0.45, 0.88, 0.68))
	draw_circle(Vector2(1.5, -1.5), 1.2, Color(0.95, 1.0, 0.95)) # 高光

	# 环绕自转星环 (极细倾斜椭圆)
	var ring_ang := _lifetime_acc * 8.0
	var ring_pts := PackedVector2Array()
	var segs := 16
	for i in range(segs + 1):
		var t := float(i) / float(segs) * TAU
		var pt := Vector2(cos(t) * 7.5, sin(t) * 3.0).rotated(ring_ang)
		ring_pts.append(pt)
	draw_polyline(ring_pts, Color(0.70, 1.0, 0.85, 0.65), 1.0, true)

# ----------------- 8. 通用法刃 (冷月气刃) -----------------
func _draw_generic_blade() -> void:
	var blade_pts := PackedVector2Array([
		Vector2(12.0, 0.0),
		Vector2(0.0, -3.5),
		Vector2(-8.0, 0.0),
		Vector2(0.0, 3.5)
	])
	draw_colored_polygon(blade_pts, Color(0.90, 0.94, 0.98))
	draw_line(Vector2(12.0, 0.0), Vector2(-8.0, 0.0), Color(0.35, 0.85, 0.65), 1.0, true)
