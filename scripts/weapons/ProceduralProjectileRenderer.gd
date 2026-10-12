class_name ProceduralProjectileRenderer
extends Node2D

## 纯矢量弹道渲染器（冷冽国风修仙）
## 取代低清像素 bullet_*.png，实现高频无损旋转、精准物理咬合、动态流光与气刃尾迹

enum ProjectileKind {
	SWORD_GOLD,       ## 庚金飞剑：修长冷银双刃古剑 + 庚金锋芒
	SWORD_FIRE,       ## 流火飞剑：炽亮橙红烧刃飞剑 + 雪亮剑锋（2026-10-11 拓充）
	DAGGER_LEAF,      ## 柳叶飞刀：弯月柳叶飞刃 + 青金光痕
	NEEDLE_SILVER,    ## 暴雨银针：极细破空银针 + 针尖寒芒
	NEEDLE_GOLD,      ## 庚金金针：冷金锐芒细针 + 金煞破空丝
	NEEDLE_ICE,       ## 玄冰飞针：幽蓝冰晶细棱 + 冰晶碎屑
	BONE_SPIKE,       ## 白骨煞刺：森白锐骨锥刺 + 幽阴骨气
	TALISMAN_FIRE,    ## 火焰符：炽朱离火符纸 + 暗红朱砂阵印
	TALISMAN_TRUE_FIRE, ## 真火符：橙金三昧真火符纸 + 炽白火核（2026-10-11 拓充）
	TALISMAN_THUNDER_FIRE, ## 雷火符：紫蓝雷弧缠橙红火舌符纸（2026-10-11 拓充）
	TALISMAN_WOOD,    ## 万木灵符：碧翠玉灵符纸 + 生机灵文
	TALISMAN_GU,      ## 蛊毒符：翠绿蛊虫符纸 + 幽绿毒雾（2026-10-11 拓充）
	TALISMAN_JINGZHE, ## 惊蛰符：青碧春雷符纸 + 紫蓝雷弧（2026-10-11 第二批）
	TALISMAN_GOLD,    ## 庚金符：月白锐金符纸 + 冷金符文（2026-10-11 第二批）
	TALISMAN_EARTH,   ## 厚土符：黄褐重岩符纸 + 赭石地煞灵纹
	TALISMAN_ICE,     ## 玄冰符：霜蓝透寒符纸 + 极寒冰魄灵纹
	FIRE_FLAME,       ## 三昧真火：水墨烈焰火煞 + 炽金火核
	SPIRIT_PELLET,    ## 连环灵弹：凝元翡翠光珠 + 环绕星轨
	WATER_SHUTTLE,    ## 浪里梭：青碧流线水梭 + 浪涛丝痕（2026-10-11 拓充）
	GENERIC_BLADE     ## 通用法刃：虚空冷月气刃
}

const REDRAW_INTERVAL := 0.05 ## 20Hz 错相刷新节流，与 ProceduralDroneRenderer 同步范式

@export var kind: ProjectileKind = ProjectileKind.GENERIC_BLADE
@export var elemental_tint: Color = Color.WHITE

var _lifetime_acc: float = 0.0
var _draw_phase: float = 0.0

func _ready() -> void:
	# 错相初始化：避免所有弹丸在同个物理帧扎堆 queue_redraw
	_draw_phase = fposmod(float(get_instance_id() % 97) * 0.001, REDRAW_INTERVAL)
	queue_redraw()

func _process(delta: float) -> void:
	_lifetime_acc += delta
	_draw_phase += delta
	if _draw_phase >= REDRAW_INTERVAL:
		_draw_phase -= REDRAW_INTERVAL
		queue_redraw()

## 根据贴图路径或武器 ID 自适应识别弹丸品类
static func detect_kind_from_path(tex_path: String) -> ProjectileKind:
	if "bullet_gold_sword" in tex_path:
		return ProjectileKind.SWORD_GOLD
	elif "bullet_fire_sword" in tex_path:
		return ProjectileKind.SWORD_FIRE
	elif "bullet_leaf_dagger" in tex_path:
		return ProjectileKind.DAGGER_LEAF
	elif "bullet_silver_needle" in tex_path:
		return ProjectileKind.NEEDLE_SILVER
	elif "bullet_gold_needle" in tex_path:
		return ProjectileKind.NEEDLE_GOLD
	elif "bullet_ice_needle" in tex_path:
		return ProjectileKind.NEEDLE_ICE
	elif "bullet_bone_spike" in tex_path:
		return ProjectileKind.BONE_SPIKE
	elif "bullet_fire_talisman" in tex_path:
		return ProjectileKind.TALISMAN_FIRE
	elif "bullet_true_fire_talisman" in tex_path:
		return ProjectileKind.TALISMAN_TRUE_FIRE
	elif "bullet_thunder_fire_talisman" in tex_path:
		return ProjectileKind.TALISMAN_THUNDER_FIRE
	elif "bullet_wood_talisman" in tex_path:
		return ProjectileKind.TALISMAN_WOOD
	elif "bullet_gu_talisman" in tex_path:
		return ProjectileKind.TALISMAN_GU
	elif "bullet_jingzhe_fu" in tex_path:
		return ProjectileKind.TALISMAN_JINGZHE
	elif "bullet_gengjin_fu" in tex_path:
		return ProjectileKind.TALISMAN_GOLD
	elif "bullet_earth_talisman" in tex_path:
		return ProjectileKind.TALISMAN_EARTH
	elif "bullet_ice_talisman" in tex_path:
		return ProjectileKind.TALISMAN_ICE
	elif "bullet_fire_flame" in tex_path:
		return ProjectileKind.FIRE_FLAME
	elif "bullet_spirit_pellet" in tex_path:
		return ProjectileKind.SPIRIT_PELLET
	elif "bullet_water_shuttle" in tex_path:
		return ProjectileKind.WATER_SHUTTLE
	return ProjectileKind.GENERIC_BLADE

func _draw() -> void:
	match kind:
		ProjectileKind.SWORD_GOLD:
			_draw_gengjin_sword()
		ProjectileKind.SWORD_FIRE:
			_draw_liuhuo_sword()
		ProjectileKind.DAGGER_LEAF:
			_draw_leaf_dagger()
		ProjectileKind.NEEDLE_SILVER:
			_draw_silver_needle()
		ProjectileKind.NEEDLE_GOLD:
			_draw_gold_needle()
		ProjectileKind.NEEDLE_ICE:
			_draw_ice_needle()
		ProjectileKind.BONE_SPIKE:
			_draw_bone_spike()
		ProjectileKind.TALISMAN_FIRE:
			_draw_talisman(Color(0.85, 0.28, 0.20), Color(1.0, 0.82, 0.35))
		ProjectileKind.TALISMAN_TRUE_FIRE:
			_draw_talisman(Color(0.92, 0.45, 0.12), Color(1.0, 0.92, 0.55))
		ProjectileKind.TALISMAN_THUNDER_FIRE:
			_draw_talisman(Color(0.42, 0.34, 0.78), Color(1.0, 0.72, 0.30))
		ProjectileKind.TALISMAN_WOOD:
			_draw_talisman(Color(0.20, 0.55, 0.38), Color(0.60, 0.95, 0.70))
		ProjectileKind.TALISMAN_GU:
			_draw_talisman(Color(0.28, 0.62, 0.16), Color(0.85, 1.0, 0.45))
		ProjectileKind.TALISMAN_JINGZHE:
			_draw_talisman(Color(0.20, 0.55, 0.60), Color(0.65, 1.0, 0.85))
		ProjectileKind.TALISMAN_GOLD:
			_draw_talisman(Color(0.82, 0.78, 0.62), Color(0.55, 0.48, 0.22))
		ProjectileKind.TALISMAN_EARTH:
			_draw_talisman(Color(0.72, 0.50, 0.22), Color(0.95, 0.80, 0.45))
		ProjectileKind.TALISMAN_ICE:
			_draw_talisman(Color(0.28, 0.65, 0.95), Color(0.85, 0.98, 1.0))
		ProjectileKind.FIRE_FLAME:
			_draw_flame()
		ProjectileKind.SPIRIT_PELLET:
			_draw_spirit_pellet()
		ProjectileKind.WATER_SHUTTLE:
			_draw_water_shuttle()
		ProjectileKind.GENERIC_BLADE:
			_draw_generic_blade()

# ----------------- 1. 庚金飞剑 (双刃骨白古剑 + 庚金锐芒 + 剑气尾迹) -----------------
func _draw_gengjin_sword() -> void:
	var pulse := 1.0 + sin(_lifetime_acc * 14.0) * 0.08

	# 破空剑气长拖尾 (向 -X 轴延伸渐隐)
	var trail_outer := PackedVector2Array([
		Vector2(-6.0, -3.8),
		Vector2(-32.0, 0.0),
		Vector2(-6.0, 3.8)
	])
	draw_colored_polygon(trail_outer, Color(0.95, 0.80, 0.35, 0.15))

	var trail_inner := PackedVector2Array([
		Vector2(-10.0, -1.8),
		Vector2(-24.0, 0.0),
		Vector2(-10.0, 1.8)
	])
	draw_colored_polygon(trail_inner, Color(1.0, 0.92, 0.65, 0.30))

	# 剑气外晕 (微弱半透明冷金光晕)
	var glow_poly := PackedVector2Array([
		Vector2(16.0 * pulse, 0.0),
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

# ----------------- 1b. 流火飞剑 (炽亮橙红烧刃 + 雪亮剑锋 + 火尾) -----------------
func _draw_liuhuo_sword() -> void:
	var pulse := 1.0 + sin(_lifetime_acc * 16.0) * 0.09

	# 烈火剑气拖尾 (向 -X 轴延伸渐隐赤金彗尾)
	var trail_outer := PackedVector2Array([
		Vector2(-6.0, -4.0),
		Vector2(-34.0, 0.0),
		Vector2(-6.0, 4.0)
	])
	draw_colored_polygon(trail_outer, Color(0.95, 0.30, 0.10, 0.18))

	var trail_inner := PackedVector2Array([
		Vector2(-9.0, -2.0),
		Vector2(-24.0, 0.0),
		Vector2(-9.0, 2.0)
	])
	draw_colored_polygon(trail_inner, Color(1.0, 0.72, 0.20, 0.35))

	# 火尾外晕（暖橙半透明，比庚金的冷金晕更亮）
	var glow_poly := PackedVector2Array([
		Vector2(17.0 * pulse, 0.0),
		Vector2(-3.0, -4.8),
		Vector2(-14.0, -2.2),
		Vector2(-18.0, 0.0),
		Vector2(-14.0, 2.2),
		Vector2(-3.0, 4.8)
	])
	draw_colored_polygon(glow_poly, Color(1.0, 0.45, 0.12, 0.25))

	# 剑身上刃（炽亮橙红，阳面更亮）
	var blade_top := PackedVector2Array([
		Vector2(15.0, 0.0),
		Vector2(-2.0, -3.4),
		Vector2(-10.0, -3.0),
		Vector2(-11.0, 0.0)
	])
	draw_colored_polygon(blade_top, Color(1.0, 0.62, 0.22))
	# 剑身下刃（暗红烧刃阴面）
	var blade_bot := PackedVector2Array([
		Vector2(15.0, 0.0),
		Vector2(-11.0, 0.0),
		Vector2(-10.0, 3.0),
		Vector2(-2.0, 3.4)
	])
	draw_colored_polygon(blade_bot, Color(0.82, 0.30, 0.10))

	# 雪亮剑锋（剑尖最亮一点，右端高光楔）
	var tip_poly := PackedVector2Array([
		Vector2(15.0, 0.0),
		Vector2(8.0, -1.2),
		Vector2(8.0, 1.2)
	])
	draw_colored_polygon(tip_poly, Color(1.0, 0.96, 0.86))
	# 中脊火线
	draw_line(Vector2(14.0, 0.0), Vector2(-10.0, 0.0), Color(1.0, 0.85, 0.40), 1.0, true)
	# 剑格剑柄（玄铁暗色收尾）
	draw_line(Vector2(-9.5, -3.6), Vector2(-9.5, 3.6), Color(0.20, 0.14, 0.12), 1.5, true)
	draw_line(Vector2(-9.5, 0.0), Vector2(-14.5, 0.0), Color(0.14, 0.10, 0.10), 1.5, true)
	draw_circle(Vector2(-15.0, 0.0), 1.2, Color(1.0, 0.55, 0.18))

# ----------------- 2. 柳叶飞刀 (流线柳叶弯刃 + 青金光痕) -----------------
func _draw_leaf_dagger() -> void:
	# 刀尾青金破空流线
	var trail := PackedVector2Array([
		Vector2(-6.0, -2.5),
		Vector2(-26.0, 0.0),
		Vector2(-6.0, 2.5)
	])
	draw_colored_polygon(trail, Color(0.25, 0.80, 0.60, 0.22))

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
	# 破空长尾迹虚影 (细且长)
	draw_line(Vector2(10.0, 0.0), Vector2(-32.0, 0.0), Color(0.90, 0.95, 1.0, 0.22), 2.2, true)
	draw_line(Vector2(8.0, 0.0), Vector2(-20.0, 0.0), Color(0.95, 0.98, 1.0, 0.50), 1.2, true)
	# 针体核心
	draw_line(Vector2(10.0, 0.0), Vector2(-8.0, 0.0), Color(0.98, 0.98, 1.0), 1.0, true)
	# 针尖锐芒光点
	draw_circle(Vector2(10.0, 0.0), 1.1, Color.WHITE)

# ----------------- 3b. 庚金金针 (冷金破空锐针) -----------------
func _draw_gold_needle() -> void:
	# 破空金色丝痕
	draw_line(Vector2(10.0, 0.0), Vector2(-32.0, 0.0), Color(0.95, 0.82, 0.35, 0.22), 2.2, true)
	draw_line(Vector2(8.0, 0.0), Vector2(-20.0, 0.0), Color(1.0, 0.92, 0.55, 0.55), 1.2, true)
	# 针体核心 (冷金锐锋)
	draw_line(Vector2(10.0, 0.0), Vector2(-8.0, 0.0), Color(1.0, 0.94, 0.70), 1.0, true)
	# 针尖锐芒
	draw_circle(Vector2(10.0, 0.0), 1.1, Color(1.0, 0.98, 0.88))

# ----------------- 4. 玄冰飞针 (晶莹透光幽蓝冰锥) -----------------
func _draw_ice_needle() -> void:
	# 冰晶寒气拖尾
	var trail := PackedVector2Array([
		Vector2(-4.0, -2.5),
		Vector2(-28.0, 0.0),
		Vector2(-4.0, 2.5)
	])
	draw_colored_polygon(trail, Color(0.40, 0.80, 1.0, 0.20))

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

# ----------------- 4b. 白骨煞刺 (森白锐骨锥刺) -----------------
func _draw_bone_spike() -> void:
	# 幽阴煞气尾迹
	var trail := PackedVector2Array([
		Vector2(-4.0, -3.0),
		Vector2(-24.0, 0.0),
		Vector2(-4.0, 3.0)
	])
	draw_colored_polygon(trail, Color(0.60, 0.72, 0.75, 0.18))

	# 骨刺本体 (四边菱形锥)
	var spike_pts := PackedVector2Array([
		Vector2(13.0, 0.0),
		Vector2(0.0, -3.2),
		Vector2(-8.0, 0.0),
		Vector2(0.0, 3.2)
	])
	draw_colored_polygon(spike_pts, Color(0.92, 0.93, 0.88)) # 骨白
	# 阴暗棱面
	var shade_pts := PackedVector2Array([
		Vector2(13.0, 0.0),
		Vector2(-8.0, 0.0),
		Vector2(0.0, 3.2)
	])
	draw_colored_polygon(shade_pts, Color(0.68, 0.72, 0.68, 0.7))
	# 骨刺中脊
	draw_line(Vector2(13.0, 0.0), Vector2(-8.0, 0.0), Color(0.40, 0.45, 0.44), 1.0, true)

# ----------------- 5. 神符 (长方形古朴符纸 + 朱砂/五行灵文 + 灵光飘带) -----------------
func _draw_talisman(border_col: Color, rune_col: Color) -> void:
	var wave_t := _lifetime_acc * 14.0
	var wave_y := sin(wave_t) * 1.2

	# 符尾飘带流光 (自符底向后拖曳的两缕灵光)
	draw_line(Vector2(-8.0, -3.0), Vector2(-24.0, -4.5 + wave_y), border_col * Color(1, 1, 1, 0.35), 1.2, true)
	draw_line(Vector2(-8.0, 3.0), Vector2(-24.0, 4.5 - wave_y), border_col * Color(1, 1, 1, 0.35), 1.2, true)

	# 符纸底板 (16x10px 长方形，居中偏左以便视觉朝向)
	var rect := Rect2(-8.0, -5.0, 16.0, 10.0)
	# 符纸骨黄质感
	draw_rect(rect, Color(0.92, 0.88, 0.78), true)
	# 边框勾勒
	draw_rect(rect, border_col, false, 1.0)
	# 符头朱砂印
	draw_circle(Vector2(5.0, 0.0), 1.8, border_col)
	# 符胆灵文线条 (朱砂/青灵阵纹，带轻微呼吸)
	var rune_pulse: Color = rune_col * (0.95 + 0.15 * sin(wave_t * 0.7))
	draw_line(Vector2(3.0, 0.0), Vector2(-5.0, 0.0), rune_pulse, 1.2, true)
	draw_line(Vector2(-1.0, -2.5), Vector2(-1.0, 2.5), rune_pulse, 1.0, true)
	draw_line(Vector2(-4.0, -2.0), Vector2(-4.0, 2.0), rune_pulse, 0.8, true)

# ----------------- 6. 三昧真火 (流光火核与烈火水滴 + 喷射焰尾) -----------------
func _draw_flame() -> void:
	var pulse := 1.0 + sin(_lifetime_acc * 18.0) * 0.12

	# 喷射尾焰 (向 -X 延伸)
	var flame_trail := PackedVector2Array([
		Vector2(-4.0, -3.5),
		Vector2(-28.0, 0.0),
		Vector2(-4.0, 3.5)
	])
	draw_colored_polygon(flame_trail, Color(0.95, 0.35, 0.10, 0.30))

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

# ----------------- 7. 连环灵弹 (翡翠灵珠 + 环绕星环 + 灵光彗尾) -----------------
func _draw_spirit_pellet() -> void:
	# 后随凝元灵尘虚影
	draw_circle(Vector2(-8.0, 0.0), 3.0, Color(0.20, 0.65, 0.45, 0.35))
	draw_circle(Vector2(-16.0, 0.0), 1.8, Color(0.20, 0.65, 0.45, 0.18))

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

# ----------------- 7b. 浪里梭 (青碧流线纺锤 + 浪涛丝痕) -----------------
func _draw_water_shuttle() -> void:
	# 水痕尾迹（两道青蓝丝线向后拖，延长破空）
	draw_line(Vector2(-6.0, -2.4), Vector2(-28.0, -4.6), Color(0.35, 0.75, 1.0, 0.40), 1.2, true)
	draw_line(Vector2(-6.0, 2.4), Vector2(-28.0, 4.6), Color(0.35, 0.75, 1.0, 0.40), 1.2, true)
	# 梭身上半（冷青阳面）
	var body_top := PackedVector2Array([
		Vector2(13.0, 0.0),
		Vector2(2.0, -3.6),
		Vector2(-9.0, -2.0),
		Vector2(-11.0, 0.0)
	])
	draw_colored_polygon(body_top, Color(0.45, 0.85, 0.95))
	# 梭身下半（玄青阴面）
	var body_bot := PackedVector2Array([
		Vector2(13.0, 0.0),
		Vector2(-11.0, 0.0),
		Vector2(-9.0, 2.0),
		Vector2(2.0, 3.6)
	])
	draw_colored_polygon(body_bot, Color(0.16, 0.45, 0.62))
	# 中线浪纹（银白波光线，随时间波动）
	var wave := PackedVector2Array()
	var phase_shift := _lifetime_acc * 6.0
	for i in range(7):
		var t := -9.0 + float(i) * 3.4
		wave.append(Vector2(t, 0.55 * sin(float(i) * 2.1 + phase_shift)))
	draw_polyline(wave, Color(0.85, 0.98, 1.0, 0.9), 0.9, true)
	# 梭尖寒芒
	draw_circle(Vector2(13.0, 0.0), 0.9, Color(0.92, 1.0, 1.0))

# ----------------- 8. 通用法刃 (冷月气刃) -----------------
func _draw_generic_blade() -> void:
	# 虚影气刃拖尾
	var trail := PackedVector2Array([
		Vector2(-4.0, -2.5),
		Vector2(-24.0, 0.0),
		Vector2(-4.0, 2.5)
	])
	draw_colored_polygon(trail, Color(0.85, 0.92, 0.98, 0.18))

	var blade_pts := PackedVector2Array([
		Vector2(12.0, 0.0),
		Vector2(0.0, -3.5),
		Vector2(-8.0, 0.0),
		Vector2(0.0, 3.5)
	])
	draw_colored_polygon(blade_pts, Color(0.90, 0.94, 0.98))
	draw_line(Vector2(12.0, 0.0), Vector2(-8.0, 0.0), Color(0.35, 0.85, 0.65), 1.0, true)
