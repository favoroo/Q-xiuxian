class_name ProceduralProjectileRenderer
extends Node2D

## 纯矢量弹道渲染器（冷冽国风修仙）
## 取代低清像素 bullet_*.png，实现高频无损旋转、精准物理咬合、动态流光与气刃尾迹
## 【注意】2026-10-16：draw_circle/draw_arc 全量接 AdaptiveDraw 自适应段数——内置版固定 64 段，
##   弹幕 29 发在场时 21 个 1~5px 小点 × 64 段 × 每发重绘是图元虚高主力之一（手机端实测 23.4k）
## 【2026-11-07 机关器形】器形选择不再只靠隐藏 PNG 的路径推断：WeaponData 可写 `bullet_art`
##   显式键（= 本枚举名小写，经 art_from_key 解析），机关 10 把各自出图；缺省仍走
##   detect_kind_from_path 兜底，SpiritBeast/SpiritPet/预览台不受影响。
##   全部器形只走 BatchDraw（单发弹体仍合 1 个 draw call），新增器形批顶点 ≤ 65，红线见
##   tests/inspect_check.gd 的顶点预算断言。

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
	TALISMAN_FROST,   ## 癸水符：玄青阴水滴形符纸 + 水波灵纹（2026-10-13 与玄冰符分家）
	TALISMAN_STONE,   ## 厚土符：灰岩碑形符纸 + 山纹刻痕（2026-10-13 与镇山符分家）
	FIRE_FLAME,       ## 三昧真火：水墨烈焰火煞 + 炽金火核
		SPIRIT_PELLET,    ## 连环灵弹：凝元翡翠光珠 + 环绕星轨
		WATER_SHUTTLE,    ## 浪里梭：青碧流线水梭 + 浪涛丝痕（2026-10-11 拓充）
		SHURIKEN,         ## 手里剑：四芒旋风飞镖 + 月牙磨刃 + 破空金芒
		GOLD_COIN,        ## 聚宝金钱镖：灿金天圆地方铜钱 + 飞旋金芒 + 招财灵印
		GENERIC_BLADE,    ## 通用法刃：虚空冷月气刃
		# —— 2026-11-07 机关专属器形（只追加不改序）——
		# 背景：机关 10 把此前只有 6 种弹丸图，其中 5 种与手武器逐字节同图
		# （机关弩==金针符、剑阵盘==庚金飞剑、藤萝/青木炮==柳叶飞刀、寒泉/凝冰==玄冰飞针、
		#  垒石/傀儡==镇山符、喷火兽==烽火台），玩家布一座机关，看见的就是自己手里那把法器的弹。
		# 美术口径（用户 2026-11-07）：机关弹统一「器械语言」= 直角/铆钉/铜铁冷色底 + 元素锋尖，
		# 法器弹保持灵性弧线与流光 —— 同元素下也要能一眼分出「谁打的」。
		BOLT_CROSSBOW,    ## 机关弩：方形钢矢 + 三片尾羽 + 铜箍
		BLADE_ARRAY,      ## 剑阵盘：短剑 + 环绕符文阵环（自转）
		EMBER_SHOT,       ## 喷火兽：暗铁壳火丸 + 内炽橙核 + 后随烟团
		ICE_SHARD,        ## 寒泉兽：棱角冰棱 + 霜枝
		VINE_THORN,       ## 藤萝机关：木刺 + 藤蔓纤维 + 附叶
		STONE_BOLT,       ## 垒石机关：重岩弹 + 后随石屑（对应高击退）
		PUPPET_ORB,       ## 傀儡兽：土黄符球 + 傀儡面纹 + 引丝
		WOOD_SHELL,       ## 青木炮：木炮壳 + 燃引信 + 烟迹
		FROST_BOLT,       ## 凝冰机弩：机弩矢（铜尾箍）+ 冰晶镞头
		BEACON_FLARE      ## 烽火台：烽火焰旗 + 上飘火星
	}

## 20Hz 错相刷新节流，与 ProceduralDroneRenderer 同步范式；60fps 档翻倍 40Hz
## （2026-10-15 VisualRate 档位联动：弹体位置 60fps 运动，画面 3 帧一画会分离；低档 20Hz 为 perf_probe 预算口径）
const HZ_LOW := 20.0
const HZ_HIGH := 40.0
static func _redraw_interval() -> float:
	return VisualRate.interval(HZ_HIGH, HZ_LOW)

@export var kind: ProjectileKind = ProjectileKind.GENERIC_BLADE
@export var elemental_tint: Color = Color.WHITE

var _lifetime_acc: float = 0.0
var _draw_phase: float = 0.0

func _ready() -> void:
	# 错相初始化：避免所有弹丸在同个物理帧扎堆 queue_redraw
	_draw_phase = fposmod(float(get_instance_id() % 97) * 0.001, _redraw_interval())
	queue_redraw()

func _process(delta: float) -> void:
	# 池化弹丸回收只隐藏本体，子渲染器 _process 不随宿主 set_physics_process(false) 停；
	# is_visible_in_tree() 连祖先判定，休眠弹在此短路（BladeProjectile._recycle 另有 set_process 开关）
	if not is_visible_in_tree():
		return
	_lifetime_acc += delta
	_draw_phase += delta
	var interval := _redraw_interval()
	if _draw_phase >= interval:
		_draw_phase -= interval
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
	elif "bullet_frost_talisman" in tex_path:
		return ProjectileKind.TALISMAN_FROST
	elif "bullet_stone_talisman" in tex_path:
		return ProjectileKind.TALISMAN_STONE
	elif "bullet_fire_flame" in tex_path:
		return ProjectileKind.FIRE_FLAME
	elif "bullet_spirit_pellet" in tex_path:
		return ProjectileKind.SPIRIT_PELLET
	elif "bullet_water_shuttle" in tex_path:
		return ProjectileKind.WATER_SHUTTLE
	elif "bullet_shuriken" in tex_path:
		return ProjectileKind.SHURIKEN
	elif "bullet_gold_coin" in tex_path or "icon_coin" in tex_path:
		return ProjectileKind.GOLD_COIN
	return ProjectileKind.GENERIC_BLADE

## 显式器形键 → ProjectileKind（2026-11-07）：WeaponData 的 `bullet_art` 字段走这里。
## 为什么要有这条通路：`bullet` 那批 PNG 运行时被 Sprite2D.self_modulate.a=0 隐掉，
## 只剩「路径当查表键」的作用；机关想各自出图又不许新造垃圾 PNG（assets 是产物、勿直改），
## 于是给数据表一个显式键。键名 = 枚举名小写（"bolt_crossbow" / "ice_shard" …），
## 不另维护映射表 —— 新增枚举自动可引用，拼错返回 -1 由调用方落回贴图路径推断。
## 判据：tests/inspect_check.gd 对每把机关的键做可解析断言，拼错跑红。
static func art_from_key(key: String) -> int:
	if key.is_empty():
		return -1
	var k := key.to_upper()
	if ProjectileKind.has(k):
		return int(ProjectileKind[k])
	return -1

func _draw() -> void:
	# 单发弹体的 6~12 条矢量原语统一合成 1 个 draw call（2026-11-03 绘制专项）
	BatchDraw.flush(self)
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
			_draw_talisman(Color(0.85, 0.28, 0.20), Color(1.0, 0.82, 0.35), TalismanShape.JAGGED,
				Color(0.86, 0.72, 0.58))
		ProjectileKind.TALISMAN_TRUE_FIRE:
			_draw_talisman(Color(0.92, 0.45, 0.12), Color(1.0, 0.92, 0.55), TalismanShape.RECT,
				Color(0.90, 0.76, 0.52))
		ProjectileKind.TALISMAN_THUNDER_FIRE:
			# 2026-11-07 与火符解撞形：原 JAGGED 与火符同剪影，改雷纹折符（FOLDED）。
			# 纸底用深紫（0.50,0.44,0.74）：proc 的灼烧 modulate 偏暖，浅紫会被烤成第二张橙符，
			# 压深后乘完落在绛紫红，与火符/真火符的橙红区隔开。
			_draw_talisman(Color(0.42, 0.34, 0.78), Color(1.0, 0.72, 0.30), TalismanShape.FOLDED,
				Color(0.50, 0.44, 0.74))
		ProjectileKind.TALISMAN_WOOD:
			_draw_talisman(Color(0.20, 0.55, 0.38), Color(0.60, 0.95, 0.70), TalismanShape.LEAF,
				Color(0.72, 0.86, 0.70))
		ProjectileKind.TALISMAN_GU:
			# 2026-11-07 与惊蛰符解撞形：原 STRIP 与惊蛰符同剪影，改虫卵形（OVAL）
			_draw_talisman(Color(0.28, 0.62, 0.16), Color(0.85, 1.0, 0.45), TalismanShape.OVAL,
				Color(0.68, 0.84, 0.58))
		ProjectileKind.TALISMAN_JINGZHE:
			# 2026-11-07 与蛊毒符解撞形：改竹节令签（BAMBOO）+ 雷弧；
			# 纸底走青碧（偏蓝），与蛊毒符的纯绿卵体拉开色相
			_draw_talisman(Color(0.20, 0.55, 0.60), Color(0.62, 0.80, 1.0), TalismanShape.BAMBOO,
				Color(0.56, 0.82, 0.86))
		ProjectileKind.TALISMAN_GOLD:
			# 2026-11-07 与真火符解撞形：原 RECT 与真火符同剪影，改令箭形（ARROW）
			_draw_talisman(Color(0.82, 0.78, 0.62), Color(0.55, 0.48, 0.22), TalismanShape.ARROW,
				Color(0.86, 0.84, 0.72))
		ProjectileKind.TALISMAN_EARTH:
			_draw_talisman(Color(0.72, 0.50, 0.22), Color(0.95, 0.80, 0.45), TalismanShape.CHUNK,
				Color(0.82, 0.70, 0.50))
		ProjectileKind.TALISMAN_ICE:
			_draw_talisman(Color(0.28, 0.65, 0.95), Color(0.85, 0.98, 1.0), TalismanShape.CRYSTAL,
				Color(0.70, 0.84, 0.94))
		ProjectileKind.TALISMAN_FROST:
			_draw_talisman(Color(0.20, 0.45, 0.72), Color(0.70, 0.95, 1.0), TalismanShape.DROPLET,
				Color(0.62, 0.76, 0.88))
		ProjectileKind.TALISMAN_STONE:
			# 2026-11-07 与镇山符解撞形：镇山符走黄褐厚岩，厚土符压成灰岩（纸底中性灰）
			_draw_talisman(Color(0.55, 0.52, 0.46), Color(0.85, 0.78, 0.60), TalismanShape.STELE,
				Color(0.62, 0.62, 0.60))
		ProjectileKind.FIRE_FLAME:
			_draw_flame()
		ProjectileKind.SPIRIT_PELLET:
			_draw_spirit_pellet()
		ProjectileKind.WATER_SHUTTLE:
			_draw_water_shuttle()
		ProjectileKind.SHURIKEN:
			_draw_shuriken()
		ProjectileKind.GOLD_COIN:
			_draw_gold_coin()
		ProjectileKind.GENERIC_BLADE:
			_draw_generic_blade()
		# —— 机关专属器形（2026-11-07）——
		ProjectileKind.BOLT_CROSSBOW:
			_draw_bolt_crossbow()
		ProjectileKind.BLADE_ARRAY:
			_draw_blade_array()
		ProjectileKind.EMBER_SHOT:
			_draw_ember_shot()
		ProjectileKind.ICE_SHARD:
			_draw_ice_shard()
		ProjectileKind.VINE_THORN:
			_draw_vine_thorn()
		ProjectileKind.STONE_BOLT:
			_draw_stone_bolt()
		ProjectileKind.PUPPET_ORB:
			_draw_puppet_orb()
		ProjectileKind.WOOD_SHELL:
			_draw_wood_shell()
		ProjectileKind.FROST_BOLT:
			_draw_frost_bolt()
		ProjectileKind.BEACON_FLARE:
			_draw_beacon_flare()
	BatchDraw.flush(self)

# ----------------- 1. 庚金飞剑 (双刃骨白古剑 + 庚金锐芒 + 剑气尾迹) -----------------
func _draw_gengjin_sword() -> void:
	var pulse := 1.0 + sin(_lifetime_acc * 14.0) * 0.08

	# 破空剑气长拖尾 (向 -X 轴延伸渐隐)
	var trail_outer := PackedVector2Array([
		Vector2(-6.0, -3.8),
		Vector2(-32.0, 0.0),
		Vector2(-6.0, 3.8)
	])
	BatchDraw.native_poly(self, trail_outer, Color(0.95, 0.80, 0.35, 0.15))

	var trail_inner := PackedVector2Array([
		Vector2(-10.0, -1.8),
		Vector2(-24.0, 0.0),
		Vector2(-10.0, 1.8)
	])
	BatchDraw.native_poly(self, trail_inner, Color(1.0, 0.92, 0.65, 0.30))

	# 剑气外晕 (微弱半透明冷金光晕)
	var glow_poly := PackedVector2Array([
		Vector2(16.0 * pulse, 0.0),
		Vector2(-4.0, -4.5),
		Vector2(-14.0, -2.0),
		Vector2(-18.0, 0.0),
		Vector2(-14.0, 2.0),
		Vector2(-4.0, 4.5)
	])
	BatchDraw.native_poly(self, glow_poly, Color(0.95, 0.80, 0.35, 0.22))

	# 剑身主刃 (骨白双刃，锋尖位于 +X 轴 14.0)
	var blade_top := PackedVector2Array([
		Vector2(14.0, 0.0),
		Vector2(-2.0, -3.2),
		Vector2(-10.0, -3.0),
		Vector2(-11.0, 0.0)
	])
	BatchDraw.native_poly(self, blade_top, Color(0.92, 0.94, 0.98)) # 阳面骨白

	var blade_bot := PackedVector2Array([
		Vector2(14.0, 0.0),
		Vector2(-11.0, 0.0),
		Vector2(-10.0, 3.0),
		Vector2(-2.0, 3.2)
	])
	BatchDraw.native_poly(self, blade_bot, Color(0.70, 0.76, 0.84)) # 阴面冷灰

	# 中脊骨棱脊线 (亮金冷光锐线)
	BatchDraw.native_line(self, Vector2(14.0, 0.0), Vector2(-11.0, 0.0), Color(1.0, 0.88, 0.45), 1.0, true)

	# 剑首剑格与剑柄
	BatchDraw.native_line(self, Vector2(-10.0, -3.5), Vector2(-10.0, 3.5), Color(0.20, 0.18, 0.25), 1.5, true)
	BatchDraw.native_line(self, Vector2(-10.0, 0.0), Vector2(-15.0, 0.0), Color(0.12, 0.12, 0.16), 1.5, true)
	BatchDraw.circle(self, Vector2(-15.5, 0.0), 1.2, Color(0.92, 0.76, 0.28))
	# 剑尖锋芒 HDR 起辉（T-2.4 弹头自带光感）
	BatchDraw.circle(self, Vector2(14.0, 0.0), 1.2, GameStyle.FX_HDR_METAL)

# ----------------- 1b. 流火飞剑 (炽亮橙红烧刃 + 雪亮剑锋 + 火尾) -----------------
func _draw_liuhuo_sword() -> void:
	var pulse := 1.0 + sin(_lifetime_acc * 16.0) * 0.09

	# 烈火剑气拖尾 (向 -X 轴延伸渐隐赤金彗尾)
	var trail_outer := PackedVector2Array([
		Vector2(-6.0, -4.0),
		Vector2(-34.0, 0.0),
		Vector2(-6.0, 4.0)
	])
	BatchDraw.native_poly(self, trail_outer, Color(0.95, 0.30, 0.10, 0.18))

	var trail_inner := PackedVector2Array([
		Vector2(-9.0, -2.0),
		Vector2(-24.0, 0.0),
		Vector2(-9.0, 2.0)
	])
	BatchDraw.native_poly(self, trail_inner, Color(1.0, 0.72, 0.20, 0.35))

	# 火尾外晕（暖橙半透明，比庚金的冷金晕更亮）
	var glow_poly := PackedVector2Array([
		Vector2(17.0 * pulse, 0.0),
		Vector2(-3.0, -4.8),
		Vector2(-14.0, -2.2),
		Vector2(-18.0, 0.0),
		Vector2(-14.0, 2.2),
		Vector2(-3.0, 4.8)
	])
	BatchDraw.native_poly(self, glow_poly, Color(1.0, 0.45, 0.12, 0.25))

	# 剑身上刃（炽亮橙红，阳面更亮）
	var blade_top := PackedVector2Array([
		Vector2(15.0, 0.0),
		Vector2(-2.0, -3.4),
		Vector2(-10.0, -3.0),
		Vector2(-11.0, 0.0)
	])
	BatchDraw.native_poly(self, blade_top, Color(1.0, 0.62, 0.22))
	# 剑身下刃（暗红烧刃阴面）
	var blade_bot := PackedVector2Array([
		Vector2(15.0, 0.0),
		Vector2(-11.0, 0.0),
		Vector2(-10.0, 3.0),
		Vector2(-2.0, 3.4)
	])
	BatchDraw.native_poly(self, blade_bot, Color(0.82, 0.30, 0.10))

	# 雪亮剑锋（接 FX_HDR_FIRE 炽阳超白起辉）
	var tip_poly := PackedVector2Array([
		Vector2(15.0, 0.0),
		Vector2(8.0, -1.2),
		Vector2(8.0, 1.2)
	])
	BatchDraw.native_poly(self, tip_poly, GameStyle.FX_HDR_FIRE)
	# 中脊火线
	BatchDraw.native_line(self, Vector2(14.0, 0.0), Vector2(-10.0, 0.0), Color(1.0, 0.85, 0.40), 1.0, true)
	# 剑格剑柄（玄铁暗色收尾）
	BatchDraw.native_line(self, Vector2(-9.5, -3.6), Vector2(-9.5, 3.6), Color(0.20, 0.14, 0.12), 1.5, true)
	BatchDraw.native_line(self, Vector2(-9.5, 0.0), Vector2(-14.5, 0.0), Color(0.14, 0.10, 0.10), 1.5, true)
	BatchDraw.circle(self, Vector2(-15.0, 0.0), 1.2, Color(1.0, 0.55, 0.18))

# ----------------- 2. 柳叶飞刀 (流线柳叶弯刃 + 青金光痕) -----------------
func _draw_leaf_dagger() -> void:
	# 刀尾青金破空流线
	var trail := PackedVector2Array([
		Vector2(-6.0, -2.5),
		Vector2(-26.0, 0.0),
		Vector2(-6.0, 2.5)
	])
	BatchDraw.native_poly(self, trail, Color(0.25, 0.80, 0.60, 0.22))

	var dagger_pts := PackedVector2Array([
		Vector2(11.0, 0.0),
		Vector2(2.0, -3.0),
		Vector2(-8.0, -2.0),
		Vector2(-10.0, 0.0),
		Vector2(-8.0, 2.0),
		Vector2(2.0, 3.0)
	])
	BatchDraw.native_poly(self, dagger_pts, Color(0.88, 0.92, 0.96))
	# 背脊青金流光
	BatchDraw.native_line(self, Vector2(11.0, 0.0), Vector2(-8.0, 0.0), Color(0.35, 0.85, 0.65), 1.0, true)
	# 刀尖锐芒（FX_HDR_WOOD 超白起辉）
	BatchDraw.circle(self, Vector2(11.0, 0.0), 1.1, GameStyle.FX_HDR_WOOD)
	# 刀尾配重
	BatchDraw.circle(self, Vector2(-9.0, 0.0), 1.2, Color(0.10, 0.12, 0.16))

# ----------------- 3. 暴雨银针 (极细冷银破空针 + 三缕雨丝尾) -----------------
## 2026-11-07 三针解撞形：银/金/冰原先都是「一根线 + 一个光点」，混战里完全同形。
## 现在按尾法分家 —— 银针 = 三缕平行雨丝尾（最细最长），金针 = 大环首，冰针 = 晶体剪影。
func _draw_silver_needle() -> void:
	# 破空长尾迹虚影 (最细最长，撑开剪影长度)
	BatchDraw.native_line(self, Vector2(9.0, 0.0), Vector2(-34.0, 0.0), Color(0.90, 0.95, 1.0, 0.22), 2.4, true)
	# 三缕雨丝（暴雨针的「雨」字形，也是与金针/冰针的第一眼区别）
	BatchDraw.native_line(self, Vector2(7.0, 0.0), Vector2(-26.0, -2.2), Color(0.88, 0.94, 1.0, 0.48), 0.9, true)
	BatchDraw.native_line(self, Vector2(7.0, 0.0), Vector2(-26.0, 2.2), Color(0.88, 0.94, 1.0, 0.48), 0.9, true)
	# 针体核心（2026-11-07 出图后 1.0→1.3：0.5 缩放后 1px 线在暗底上几乎看不见）
	BatchDraw.native_line(self, Vector2(10.0, 0.0), Vector2(-8.0, 0.0), Color(0.98, 0.98, 1.0), 1.3, true)
	# 针尖侧棱（极短，只提亮不扩宽）
	BatchDraw.native_line(self, Vector2(10.0, 0.0), Vector2(4.0, -1.2), Color(0.92, 0.96, 1.0, 0.8), 0.8, true)
	# 针尖锐芒光点（FX_HDR_CORE 超白起辉）
	BatchDraw.circle(self, Vector2(10.0, 0.0), 1.1, GameStyle.FX_HDR_CORE)

# ----------------- 3b. 庚金金针 (冷金破空锐针 + 大环首) -----------------
func _draw_gold_needle() -> void:
	# 破空金色丝痕
	BatchDraw.native_line(self, Vector2(10.0, 0.0), Vector2(-30.0, 0.0), Color(0.95, 0.82, 0.35, 0.22), 2.2, true)
	BatchDraw.native_line(self, Vector2(8.0, 0.0), Vector2(-18.0, 0.0), Color(1.0, 0.92, 0.55, 0.55), 1.2, true)
	# 针体核心 (冷金锐锋，比银针短一截、粗一档)
	BatchDraw.native_line(self, Vector2(10.0, 0.0), Vector2(-7.0, 0.0), Color(1.0, 0.94, 0.70), 1.4, true)
	# 环首：加大的金环是金针的招牌剪影（2026-11-07 由 2.0 放大到 2.7）
	BatchDraw.arc(self, Vector2(-9.4, 0.0), 2.7, 0.0, TAU, Color(0.95, 0.82, 0.35), 1.2)
	# 环内金芯（把环填实一半，小尺寸下不至于只剩一个空心圈）
	BatchDraw.circle(self, Vector2(-9.4, 0.0), 1.1, Color(1.0, 0.90, 0.55, 0.9))
	# 倒刺
	BatchDraw.native_line(self, Vector2(1.5, 0.0), Vector2(-1.5, -2.0), Color(1.0, 0.90, 0.55, 0.85), 0.9, true)
	BatchDraw.native_line(self, Vector2(1.5, 0.0), Vector2(-1.5, 2.0), Color(1.0, 0.90, 0.55, 0.85), 0.9, true)
	# 针尖锐芒（FX_HDR_METAL 超白起辉）
	BatchDraw.circle(self, Vector2(10.0, 0.0), 1.1, GameStyle.FX_HDR_METAL)

# ----------------- 4. 玄冰飞针 (六棱冰晶锥，不再是一根线) -----------------
func _draw_ice_needle() -> void:
	# 冰晶寒气拖尾
	var trail := PackedVector2Array([
		Vector2(-6.0, -3.2),
		Vector2(-28.0, 0.0),
		Vector2(-6.0, 3.2)
	])
	BatchDraw.native_poly(self, trail, Color(0.40, 0.80, 1.0, 0.20))

	# 冰晶外晕（宽而短，把体量感顶起来）
	BatchDraw.native_line(self, Vector2(11.0, 0.0), Vector2(-9.0, 0.0), Color(0.40, 0.80, 1.0, 0.38), 4.0, true)
	# 多面六棱晶体（比旧版宽一倍：12.5 × 5.6 的短锥，剪影是「一块冰」而非「一根针」）
	var shard := PackedVector2Array([
		Vector2(12.5, 0.0), Vector2(3.0, -2.8), Vector2(-6.0, -2.2),
		Vector2(-9.0, 0.0), Vector2(-6.0, 2.2), Vector2(3.0, 2.8)])
	BatchDraw.native_poly(self, shard, Color(0.72, 0.93, 1.0))
	# 阴面（下半棱面压暗，晶体才不是一块白板）
	var shade := PackedVector2Array([
		Vector2(12.5, 0.0), Vector2(-9.0, 0.0), Vector2(-6.0, 2.2), Vector2(3.0, 2.8)])
	BatchDraw.native_poly(self, shade, Color(0.30, 0.65, 0.95))
	# 冰棱脊线
	BatchDraw.native_line(self, Vector2(12.5, 0.0), Vector2(-8.0, 0.0), Color(0.90, 0.98, 1.0), 0.9, true)
	# 两道霜枝（晶体特征）
	BatchDraw.native_line(self, Vector2(2.0, -2.4), Vector2(0.5, -4.2), Color(0.85, 0.98, 1.0, 0.8), 0.7, true)
	BatchDraw.native_line(self, Vector2(-3.0, 1.8), Vector2(-4.5, 3.4), Color(0.85, 0.98, 1.0, 0.7), 0.7, true)
	# 针尖冰晶寒芒（FX_HDR_WATER 超白起辉）
	BatchDraw.circle(self, Vector2(12.5, 0.0), 1.1, GameStyle.FX_HDR_WATER)

# ----------------- 4b. 白骨煞刺 (森白锐骨锥刺) -----------------
func _draw_bone_spike() -> void:
	# 幽阴煞气尾迹
	var trail := PackedVector2Array([
		Vector2(-4.0, -3.0),
		Vector2(-24.0, 0.0),
		Vector2(-4.0, 3.0)
	])
	BatchDraw.native_poly(self, trail, Color(0.60, 0.72, 0.75, 0.18))

	# 骨刺本体 (四边菱形锥)
	var spike_pts := PackedVector2Array([
		Vector2(13.0, 0.0),
		Vector2(0.0, -3.2),
		Vector2(-8.0, 0.0),
		Vector2(0.0, 3.2)
	])
	BatchDraw.native_poly(self, spike_pts, Color(0.92, 0.93, 0.88)) # 骨白
	# 阴暗棱面
	var shade_pts := PackedVector2Array([
		Vector2(13.0, 0.0),
		Vector2(-8.0, 0.0),
		Vector2(0.0, 3.2)
	])
	BatchDraw.native_poly(self, shade_pts, Color(0.68, 0.72, 0.68, 0.7))
	# 骨刺中脊
	BatchDraw.native_line(self, Vector2(13.0, 0.0), Vector2(-8.0, 0.0), Color(0.40, 0.45, 0.44), 1.0, true)
	# 骨尖寒芒（FX_HDR_CORE 超白起辉）
	BatchDraw.circle(self, Vector2(13.0, 0.0), 1.1, GameStyle.FX_HDR_CORE)

# ----------------- 5. 神符 (符纸形态 × 五行灵文 + 灵光飘带) -----------------
## 符纸形态（2026-10-13 形态分化）：9+ 种符箓旧写法清一色 16×10 长方形只换边框色，
## 拆成多种剪影 —— 方符/长条/叶形/晶棱/锯齿火边/厚岩八角/水滴/碑形，
## 灵文跟着形态走（叶脉/晶心/雷纹/山刻/水波），飘带与呼吸相位全形制共用。
## 2026-11-07 解撞形（用户口径「看着都一样，只是换个颜色」）：原 RECT/JAGGED/STRIP 各撞两把，
## 补折符(FOLDED)/令箭(ARROW)/虫卵(OVAL)/竹节(BAMBOO) 四种剪影，并把符纸底色按五行染开。
## STRIP 现无武器使用（蛊毒符→OVAL、惊蛰符→BAMBOO），保留枚举位不重排。
enum TalismanShape { RECT, STRIP, LEAF, CRYSTAL, JAGGED, CHUNK, DROPLET, STELE, FOLDED, ARROW, OVAL, BAMBOO }

## paper_col：符纸底色（2026-11-07 染纸）。用户口径「看着都一样，只是换个颜色」——
## 旧写法 11 把符共用同一种米白纸，只有边框/灵文换色，混战里就只剩「一张纸」的印象。
## 现在整张纸按五行染色；数值刻意压在 0.6~0.9 中低饱和区，乘上 proc 的 modulate 不会烧白。
## 符尾飘带幅度按形制分档：碑/厚岩/方符沉，折符/锯齿火边/令箭飘 —— 轻重读得出来。
func _draw_talisman(border_col: Color, rune_col: Color, shape: TalismanShape = TalismanShape.RECT,
		paper_col: Color = Color(0.92, 0.88, 0.78)) -> void:
	var wave_t := _lifetime_acc * 14.0
	var ribbon_amp := 1.0
	match shape:
		TalismanShape.STELE, TalismanShape.CHUNK, TalismanShape.RECT:
			ribbon_amp = 0.55
		TalismanShape.FOLDED, TalismanShape.JAGGED, TalismanShape.ARROW:
			ribbon_amp = 1.25
	var wave_y := sin(wave_t) * 1.2 * ribbon_amp
	var ribbon_run := 16.0 + 8.0 * ribbon_amp

	# 符尾飘带流光 (自符底向后拖曳的两缕灵光)
	BatchDraw.native_line(self, Vector2(-8.0, -3.0), Vector2(-8.0 - ribbon_run, -4.5 + wave_y), border_col * Color(1, 1, 1, 0.35), 1.2, true)
	BatchDraw.native_line(self, Vector2(-8.0, 3.0), Vector2(-8.0 - ribbon_run, 4.5 - wave_y), border_col * Color(1, 1, 1, 0.35), 1.2, true)

	var paper := paper_col
	var rune_pulse: Color = rune_col * (0.95 + 0.15 * sin(wave_t * 0.7))
	match shape:
		TalismanShape.RECT:
			# 方符：16×10 正气符纸
			var rect := Rect2(-8.0, -5.0, 16.0, 10.0)
			BatchDraw.native_rect(self, rect, paper, true)
			BatchDraw.native_rect(self, rect, border_col, false, 1.0)
			BatchDraw.circle(self, Vector2(5.0, 0.0), 1.8, border_col)
			BatchDraw.native_line(self, Vector2(3.0, 0.0), Vector2(-5.0, 0.0), rune_pulse, 1.2, true)
			BatchDraw.native_line(self, Vector2(-1.0, -2.5), Vector2(-1.0, 2.5), rune_pulse, 1.0, true)
			BatchDraw.native_line(self, Vector2(-4.0, -2.0), Vector2(-4.0, 2.0), rune_pulse, 0.8, true)
		TalismanShape.STRIP:
			# 长条符：20×6 狭长令签
			var rect := Rect2(-10.0, -3.0, 20.0, 6.0)
			BatchDraw.native_rect(self, rect, paper, true)
			BatchDraw.native_rect(self, rect, border_col, false, 1.0)
			BatchDraw.circle(self, Vector2(7.0, 0.0), 1.4, border_col)
			BatchDraw.native_line(self, Vector2(4.0, 0.0), Vector2(-7.0, 0.0), rune_pulse, 1.0, true)
			BatchDraw.native_line(self, Vector2(-3.0, -1.5), Vector2(-3.0, 1.5), rune_pulse, 0.8, true)
		TalismanShape.LEAF:
			# 叶形符：前尖后圆的灵叶
			var leaf := PackedVector2Array([
				Vector2(10.0, 0.0), Vector2(3.0, -5.0), Vector2(-6.0, -4.0),
				Vector2(-9.0, 0.0), Vector2(-6.0, 4.0), Vector2(3.0, 5.0)])
			BatchDraw.native_poly(self, leaf, paper)
			leaf.append(leaf[0])
			BatchDraw.native_polyline(self, leaf, border_col, 1.0, true)
			# 叶脉灵文
			BatchDraw.native_line(self, Vector2(8.0, 0.0), Vector2(-7.0, 0.0), rune_pulse, 1.0, true)
			BatchDraw.native_line(self, Vector2(2.0, 0.0), Vector2(-2.0, -2.6), rune_pulse, 0.8, true)
			BatchDraw.native_line(self, Vector2(2.0, 0.0), Vector2(-2.0, 2.6), rune_pulse, 0.8, true)
		TalismanShape.CRYSTAL:
			# 晶棱符：六棱冰晶
			var hex := PackedVector2Array([
				Vector2(10.0, 0.0), Vector2(4.0, -4.5), Vector2(-5.0, -4.5),
				Vector2(-9.0, 0.0), Vector2(-5.0, 4.5), Vector2(4.0, 4.5)])
			BatchDraw.native_poly(self, hex, paper)
			hex.append(hex[0])
			BatchDraw.native_polyline(self, hex, border_col, 1.0, true)
			# 晶心灵纹（内小菱形）
			var core := PackedVector2Array([
				Vector2(4.0, 0.0), Vector2(0.0, -2.0), Vector2(-4.0, 0.0), Vector2(0.0, 2.0), Vector2(4.0, 0.0)])
			BatchDraw.native_polyline(self, core, rune_pulse, 1.0, true)
		TalismanShape.JAGGED:
			# 锯齿火边符：符尾撕出火焰卷边
			var jag := PackedVector2Array([
				Vector2(9.0, -4.5), Vector2(-7.0, -5.0), Vector2(-10.0, -2.5),
				Vector2(-7.5, 0.0), Vector2(-10.0, 2.5), Vector2(-7.0, 5.0), Vector2(9.0, 4.5)])
			BatchDraw.native_poly(self, jag, paper)
			jag.append(jag[0])
			BatchDraw.native_polyline(self, jag, border_col, 1.0, true)
			BatchDraw.circle(self, Vector2(5.5, 0.0), 1.6, border_col)
			# 火纹灵文（三折跃动）
			BatchDraw.native_polyline(self, PackedVector2Array([
				Vector2(3.0, -1.5), Vector2(0.0, 1.5), Vector2(-3.0, -1.5), Vector2(-5.5, 1.0)]),
				rune_pulse, 1.0, true)
		TalismanShape.CHUNK:
			# 厚岩八角符：镇山的厚重手感
			var oct := PackedVector2Array([
				Vector2(6.0, -5.0), Vector2(-4.0, -6.0), Vector2(-9.0, -2.5), Vector2(-9.0, 2.5),
				Vector2(-4.0, 6.0), Vector2(6.0, 5.0), Vector2(9.0, 2.0), Vector2(9.0, -2.0)])
			BatchDraw.native_poly(self, oct, paper)
			oct.append(oct[0])
			BatchDraw.native_polyline(self, oct, border_col, 1.4, true)
			# 山形灵纹
			BatchDraw.native_polyline(self, PackedVector2Array([
				Vector2(-5.0, 2.5), Vector2(-1.5, -2.0), Vector2(1.5, 1.0), Vector2(4.5, -2.5)]),
				rune_pulse, 1.2, true)
		TalismanShape.DROPLET:
			# 水滴符：阴水前悬一滴
			var drop := PackedVector2Array([
				Vector2(10.0, 0.0), Vector2(3.0, -5.5), Vector2(-4.0, -5.0),
				Vector2(-8.0, -1.5), Vector2(-8.0, 1.5), Vector2(-4.0, 5.0), Vector2(3.0, 5.5)])
			BatchDraw.native_poly(self, drop, paper)
			drop.append(drop[0])
			BatchDraw.native_polyline(self, drop, border_col, 1.0, true)
			# 水波灵纹（圆心 + 半弧）
			BatchDraw.circle(self, Vector2(0.0, 0.0), 1.3, rune_pulse)
			BatchDraw.arc(self, Vector2(0.0, 0.0), 3.2, -1.2, 1.2, rune_pulse, 0.9)
		TalismanShape.STELE:
			# 碑形符：上窄下高的石碑（2026-11-07 拉高收窄 —— 与镇山符的八角厚岩分开）
			var stele := PackedVector2Array([
				Vector2(7.0, -6.2), Vector2(-5.5, -7.0), Vector2(-7.0, 7.0), Vector2(5.5, 6.4)])
			BatchDraw.native_poly(self, stele, paper)
			stele.append(stele[0])
			BatchDraw.native_polyline(self, stele, border_col, 1.2, true)
			# 碑额横刻 + 竖纹
			BatchDraw.native_line(self, Vector2(4.5, -4.0), Vector2(-3.5, -4.6), rune_pulse, 1.0, true)
			BatchDraw.native_line(self, Vector2(0.0, -2.2), Vector2(-1.0, 5.2), rune_pulse, 1.0, true)
		TalismanShape.FOLDED:
			# 折符（2026-11-07 雷火符）：上下缘折出雷纹锯齿，与火符的火焰卷边（JAGGED）彻底分家
			var folded := PackedVector2Array([
				Vector2(10.0, 0.0),
				Vector2(3.0, -4.6), Vector2(0.0, -2.2), Vector2(-4.0, -4.6), Vector2(-7.0, -1.2),
				Vector2(-9.0, 0.0),
				Vector2(-7.0, 1.2), Vector2(-4.0, 4.6), Vector2(0.0, 2.2), Vector2(3.0, 4.6)])
			BatchDraw.native_poly(self, folded, paper)
			folded.append(folded[0])
			BatchDraw.native_polyline(self, folded, border_col, 1.0, true)
			# 灵文：一道折雷 + 雷核
			BatchDraw.native_polyline(self, PackedVector2Array([
				Vector2(4.5, -1.6), Vector2(1.0, 1.4), Vector2(-2.0, -1.4), Vector2(-5.0, 1.2)]),
				rune_pulse, 1.1, true)
			BatchDraw.circle(self, Vector2(4.5, 0.0), 1.2, rune_pulse)
		TalismanShape.ARROW:
			# 令箭形（2026-11-07 庚金符）：尖首 + 燕尾，锐金器类的「箭头」剪影
			var arrow := PackedVector2Array([
				Vector2(13.0, 0.0), Vector2(3.0, -3.2), Vector2(-5.0, -4.6),
				Vector2(-8.0, -1.6), Vector2(-8.0, 1.6), Vector2(-5.0, 4.6), Vector2(3.0, 3.2)])
			BatchDraw.native_poly(self, arrow, paper)
			arrow.append(arrow[0])
			BatchDraw.native_polyline(self, arrow, border_col, 1.1, true)
			# 灵文：金脊贯线 + 一道锐锋折线
			BatchDraw.native_line(self, Vector2(11.0, 0.0), Vector2(-6.5, 0.0), rune_pulse, 1.0, true)
			BatchDraw.native_polyline(self, PackedVector2Array([
				Vector2(2.0, -2.6), Vector2(-1.0, 0.0), Vector2(2.0, 2.6)]), rune_pulse, 0.9, true)
			BatchDraw.circle(self, Vector2(13.0, 0.0), 1.0, rune_col)
		TalismanShape.OVAL:
			# 虫卵形（2026-11-07 蛊毒符）：前窄后圆的卵体 + 盘曲蛊虫灵文
			var egg := PackedVector2Array([
				Vector2(9.0, 0.0), Vector2(5.0, -3.4), Vector2(0.0, -4.8), Vector2(-5.0, -3.8),
				Vector2(-8.0, -1.4), Vector2(-8.0, 1.4), Vector2(-5.0, 3.8), Vector2(0.0, 4.8),
				Vector2(5.0, 3.4)])
			BatchDraw.native_poly(self, egg, paper)
			egg.append(egg[0])
			BatchDraw.native_polyline(self, egg, border_col, 1.1, true)
			# 灵文：一条盘曲的蛊虫 + 卵核
			BatchDraw.native_polyline(self, PackedVector2Array([
				Vector2(4.5, 0.3), Vector2(1.5, -2.2), Vector2(-2.0, 1.8),
				Vector2(-5.0, -0.8), Vector2(-6.5, 0.6)]), rune_pulse, 1.0, true)
			BatchDraw.circle(self, Vector2(4.5, 0.3), 1.0, rune_pulse)
		TalismanShape.BAMBOO:
			# 竹节令签（2026-11-07 惊蛰符）：狭长签身 + 两道竹节横刻 + 春雷弧。
			# 2026-11-07 出图后拉长收窄（26×5.6）：蛊毒符是绿卵、它必须先是「一根签」，
			# 否则同为毒系绿色、乘完 modulate 色相一样，只剩长度差。
			var bamboo := PackedVector2Array([
				Vector2(13.0, 0.0), Vector2(9.0, -2.7), Vector2(1.0, -2.9), Vector2(-9.0, -2.6),
				Vector2(-13.0, 0.0), Vector2(-9.0, 2.6), Vector2(1.0, 2.9), Vector2(9.0, 2.7)])
			BatchDraw.native_poly(self, bamboo, paper)
			bamboo.append(bamboo[0])
			BatchDraw.native_polyline(self, bamboo, border_col, 1.0, true)
			# 竹节横刻（两道）
			BatchDraw.native_line(self, Vector2(4.0, -2.7), Vector2(4.0, 2.7), rune_pulse, 0.9, true)
			BatchDraw.native_line(self, Vector2(-6.0, -2.6), Vector2(-6.0, 2.6), rune_pulse, 0.9, true)
			# 春雷弧（惊蛰）
			BatchDraw.native_polyline(self, PackedVector2Array([
				Vector2(9.5, -1.6), Vector2(6.0, 0.6), Vector2(2.5, -1.4)]), rune_col, 1.0, true)

# ----------------- 6. 三昧真火 (流光火核与烈火水滴 + 喷射焰尾) -----------------
func _draw_flame() -> void:
	var pulse := 1.0 + sin(_lifetime_acc * 18.0) * 0.12

	# 喷射尾焰 (向 -X 延伸)
	var flame_trail := PackedVector2Array([
		Vector2(-4.0, -3.5),
		Vector2(-28.0, 0.0),
		Vector2(-4.0, 3.5)
	])
	BatchDraw.native_poly(self, flame_trail, Color(0.95, 0.35, 0.10, 0.30))

	# 外层暗赤火煞
	var outer_flame := PackedVector2Array([
		Vector2(10.0 * pulse, 0.0),
		Vector2(2.0, -5.5 * pulse),
		Vector2(-6.0, -4.0),
		Vector2(-8.0, 0.0),
		Vector2(-6.0, 4.0),
		Vector2(2.0, 5.5 * pulse)
	])
	BatchDraw.native_poly(self, outer_flame, Color(0.85, 0.25, 0.15, 0.75))

	# 中层炽金烈焰
	var mid_flame := PackedVector2Array([
		Vector2(8.0 * pulse, 0.0),
		Vector2(1.0, -3.5 * pulse),
		Vector2(-4.0, -2.5),
		Vector2(-5.0, 0.0),
		Vector2(-4.0, 2.5),
		Vector2(1.0, 3.5 * pulse)
	])
	BatchDraw.native_poly(self, mid_flame, Color(1.0, 0.65, 0.20, 0.90))

	# 内层白炽真火灵核（FX_HDR_FIRE 超白起辉）
	BatchDraw.circle(self, Vector2(2.0, 0.0), 2.2 * pulse, GameStyle.FX_HDR_FIRE)

# ----------------- 7. 连环灵弹 (翡翠灵珠 + 环绕星环 + 灵光彗尾) -----------------
func _draw_spirit_pellet() -> void:
	# 后随凝元灵尘虚影
	BatchDraw.circle(self, Vector2(-8.0, 0.0), 3.0, Color(0.20, 0.65, 0.45, 0.35))
	BatchDraw.circle(self, Vector2(-16.0, 0.0), 1.8, Color(0.20, 0.65, 0.45, 0.18))

	# 翡翠灵珠核心
	BatchDraw.circle(self, Vector2.ZERO, 5.0, Color(0.20, 0.65, 0.45))
	BatchDraw.circle(self, Vector2(1.0, -1.0), 3.0, Color(0.45, 0.88, 0.68))
	BatchDraw.circle(self, Vector2(1.5, -1.5), 1.2, GameStyle.FX_HDR_WOOD) # 高光超白起辉

	# 环绕自转星环 (极细倾斜椭圆)
	var ring_ang := _lifetime_acc * 8.0
	var ring_pts := PackedVector2Array()
	var segs := 16
	for i in range(segs + 1):
		var t := float(i) / float(segs) * TAU
		var pt := Vector2(cos(t) * 7.5, sin(t) * 3.0).rotated(ring_ang)
		ring_pts.append(pt)
	BatchDraw.native_polyline(self, ring_pts, Color(0.70, 1.0, 0.85, 0.65), 1.0, true)

# ----------------- 7b. 浪里梭 (青碧流线纺锤 + 浪涛丝痕) -----------------
func _draw_water_shuttle() -> void:
	# 水痕尾迹（两道青蓝丝线向后拖，延长破空）
	BatchDraw.native_line(self, Vector2(-6.0, -2.4), Vector2(-28.0, -4.6), Color(0.35, 0.75, 1.0, 0.40), 1.2, true)
	BatchDraw.native_line(self, Vector2(-6.0, 2.4), Vector2(-28.0, 4.6), Color(0.35, 0.75, 1.0, 0.40), 1.2, true)
	# 梭身上半（冷青阳面）
	var body_top := PackedVector2Array([
		Vector2(13.0, 0.0),
		Vector2(2.0, -3.6),
		Vector2(-9.0, -2.0),
		Vector2(-11.0, 0.0)
	])
	BatchDraw.native_poly(self, body_top, Color(0.45, 0.85, 0.95))
	# 梭身下半（玄青阴面）
	var body_bot := PackedVector2Array([
		Vector2(13.0, 0.0),
		Vector2(-11.0, 0.0),
		Vector2(-9.0, 2.0),
		Vector2(2.0, 3.6)
	])
	BatchDraw.native_poly(self, body_bot, Color(0.16, 0.45, 0.62))
	# 中线浪纹（银白波光线，随时间波动）
	var wave := PackedVector2Array()
	var phase_shift := _lifetime_acc * 6.0
	for i in range(7):
		var t := -9.0 + float(i) * 3.4
		wave.append(Vector2(t, 0.55 * sin(float(i) * 2.1 + phase_shift)))
	BatchDraw.native_polyline(self, wave, Color(0.85, 0.98, 1.0, 0.9), 0.9, true)
	# 梭尖寒芒（FX_HDR_WATER 超白起辉）
	BatchDraw.circle(self, Vector2(13.0, 0.0), 1.0, GameStyle.FX_HDR_WATER)

# ----------------- 8. 通用法刃 (冷月气刃) -----------------
func _draw_generic_blade() -> void:
	# 虚影气刃拖尾
	var trail := PackedVector2Array([
		Vector2(-4.0, -2.5),
		Vector2(-24.0, 0.0),
		Vector2(-4.0, 2.5)
	])
	BatchDraw.native_poly(self, trail, Color(0.85, 0.92, 0.98, 0.18))

	var blade_pts := PackedVector2Array([
		Vector2(12.0, 0.0),
		Vector2(0.0, -3.5),
		Vector2(-8.0, 0.0),
		Vector2(0.0, 3.5)
	])
	BatchDraw.native_poly(self, blade_pts, Color(0.90, 0.94, 0.98))
	BatchDraw.native_line(self, Vector2(12.0, 0.0), Vector2(-8.0, 0.0), Color(0.35, 0.85, 0.65), 1.0, true)
	# 刃尖寒光起辉
	BatchDraw.circle(self, Vector2(12.0, 0.0), 1.2, GameStyle.FX_HDR_CORE)

# ----------------- 7c. 手里剑 (四芒旋风飞镖 + 月牙磨刃 + 破空冷金残影) -----------------
func _draw_shuriken() -> void:
	var pulse := 1.0 + sin(_lifetime_acc * 16.0) * 0.08
	const R := 13.0
	var r_hole := R * 0.22

	# 飞旋破空残影气环（微弱冷月白晕）
	BatchDraw.arc(self, Vector2.ZERO, R * 0.95 * pulse, 0.0, TAU, Color(0.92, 0.95, 1.0, 0.15), 1.4)
	BatchDraw.arc(self, Vector2.ZERO, R * 0.72, 0.0, TAU, Color(1.0, 0.88, 0.45, 0.20), 1.0)

	# 构造四芒曲刃轮廓与磨刃面
	var outer_poly := PackedVector2Array()
	var bevel_polys: Array[PackedVector2Array] = []
	var belly_lines: Array[PackedVector2Array] = []

	const N_BACK := 10
	const N_BELLY := 10

	for k in range(4):
		var ang := float(k) * PI * 0.5

		# 背弧：从 -66° 平滑升起到 0° 尖端 (r=1.0)
		var seg_back := PackedVector2Array()
		for i in range(N_BACK + 1):
			var t := float(i) / float(N_BACK)
			var a := deg_to_rad(-66.0 + 66.0 * t)
			var r_val := 0.38 + 0.62 * pow(t, 2.2)
			seg_back.append(Vector2(cos(a), sin(a)) * r_val)

		# 腹弧：从 0° 尖端深深内凹至 +18° 谷底 (r=0.28)
		var seg_belly := PackedVector2Array()
		for i in range(1, N_BELLY + 1):
			var t := float(i) / float(N_BELLY)
			var a := deg_to_rad(18.0 * t)
			var r_val := 1.0 - 0.72 * pow(sin(t * PI * 0.5), 0.8)
			seg_belly.append(Vector2(cos(a), sin(a)) * r_val)

		# 谷底折角小齿（+20° r=0.35 -> +24° r=0.38 与下臂 -66° 咬合）
		var a_notch := deg_to_rad(20.0)
		var a_end := deg_to_rad(24.0)
		var seg_notch := PackedVector2Array([
			Vector2(cos(a_notch), sin(a_notch)) * 0.35,
			Vector2(cos(a_end), sin(a_end)) * 0.38,
		])

		var arm := PackedVector2Array()
		arm.append_array(seg_back)
		arm.append_array(seg_belly)
		arm.append_array(seg_notch)

		for p in arm:
			outer_poly.append(p.rotated(ang) * R)

		var belly_rot := PackedVector2Array()
		for p in seg_belly:
			belly_rot.append(p.rotated(ang) * R)
		belly_lines.append(belly_rot)

		# 内凹月牙磨刃亮面
		var b_poly := PackedVector2Array()
		for p in seg_belly:
			b_poly.append(p.rotated(ang) * R)
		for idx in range(seg_belly.size() - 1, -1, -1):
			var p := seg_belly[idx]
			var dist_tip := 1.0 - p.length()
			var w_bevel := minf(0.12, dist_tip * 0.22)
			var inner_p := p * (1.0 - w_bevel / maxf(0.2, p.length()))
			b_poly.append(inner_p.rotated(ang) * R)
		bevel_polys.append(b_poly)

	# 1. 暗底轮廓
	var outer_bg := PackedVector2Array()
	for p in outer_poly:
		outer_bg.append(p * 1.05)
	BatchDraw.native_poly(self, outer_bg, Color(0.06, 0.07, 0.10, 0.90))

	# 2. 玄铁暗钢身
	BatchDraw.native_poly(self, outer_poly, Color(0.26, 0.30, 0.38))

	# 3. 亮银内刃磨光面
	for bp in bevel_polys:
		BatchDraw.native_poly(self, bp, Color(0.90, 0.94, 0.98))

	# 4. 锋口冷金流光线
	for bl in belly_lines:
		BatchDraw.native_polyline(self, bl, Color(1.0, 0.88, 0.45), 1.0, true)

	# 5. 中心透孔
	BatchDraw.circle(self, Vector2.ZERO, r_hole, Color(0.06, 0.07, 0.10, 0.95))
	BatchDraw.arc(self, Vector2.ZERO, r_hole, 0.0, TAU, Color(1.0, 0.88, 0.45, 0.85), 1.0, true)

	# 6. 四尖寒芒起辉
	for k in range(4):
		var ang := float(k) * PI * 0.5
		var tip_pt := Vector2(R, 0.0).rotated(ang)
		BatchDraw.circle(self, tip_pt, 1.1, GameStyle.FX_HDR_METAL)

# ----------------- 7d. 聚宝金钱镖 (天圆地方古金钱 + 飞旋金芒 + 招财灵印) -----------------
func _draw_gold_coin() -> void:
	var pulse := 1.0 + sin(_lifetime_acc * 18.0) * 0.08
	const R := 10.5
	var r_inner := R * 0.72
	var half_hole := R * 0.28

	# 1. 破空飞旋外芒气环（流金光轮 + 拖尾虚影）
	BatchDraw.arc(self, Vector2.ZERO, R * 1.35 * pulse, 0.0, TAU, Color(1.0, 0.88, 0.35, 0.16), 1.6)
	BatchDraw.arc(self, Vector2.ZERO, R * 1.12, 0.0, TAU, Color(1.0, 0.95, 0.55, 0.28), 1.0)

	# 破空金气拖尾（向 -X 轴延伸渐隐）
	var trail_poly := PackedVector2Array([
		Vector2(-4.0, -4.5),
		Vector2(-26.0, 0.0),
		Vector2(-4.0, 4.5)
	])
	BatchDraw.native_poly(self, trail_poly, Color(0.96, 0.80, 0.25, 0.20))

	# 2. 4 道对称的切向金色飞旋小锋刃（飞旋离心流光）
	for k in range(4):
		var a := float(k) * PI * 0.5 + _lifetime_acc * 14.0
		var p_blade := Vector2(cos(a), sin(a)) * R
		var p_tip := Vector2(cos(a + 0.35), sin(a + 0.35)) * (R * 1.28)
		BatchDraw.native_line(self, p_blade, p_tip, Color(1.0, 0.92, 0.45, 0.65), 1.2, true)

	# 3. 铜钱主体外圆（天圆）
	BatchDraw.circle(self, Vector2.ZERO, R, Color(0.85, 0.68, 0.18))      # 古金底色
	BatchDraw.circle(self, Vector2.ZERO, R * 0.92, Color(0.98, 0.82, 0.24)) # 阳面灿金
	BatchDraw.arc(self, Vector2.ZERO, R, 0.0, TAU, Color(0.70, 0.50, 0.12), 1.2, true) # 鎏金外轮廓

	# 4. 同心外郭凸缘（铸造压印线）
	BatchDraw.arc(self, Vector2.ZERO, r_inner, 0.0, TAU, Color(0.82, 0.62, 0.15), 1.0, true)

	# 5. 中心方孔（天圆地方）
	var hole_rect := Rect2(-half_hole, -half_hole, half_hole * 2.0, half_hole * 2.0)
	BatchDraw.native_rect(self, hole_rect, Color(0.10, 0.12, 0.16, 0.96), true) # 中心深色透空
	BatchDraw.native_rect(self, hole_rect, Color(0.70, 0.52, 0.12), false, 1.0) # 内方孔铜郭线

	# 6. 四方招财灵纹刻线（上下左右小符文）
	var mark_col := Color(0.75, 0.55, 0.12)
	BatchDraw.native_line(self, Vector2(0, -r_inner + 1.2), Vector2(0, -half_hole - 1.0), mark_col, 1.0, true)
	BatchDraw.native_line(self, Vector2(0, r_inner - 1.2), Vector2(0, half_hole + 1.0), mark_col, 1.0, true)
	BatchDraw.native_line(self, Vector2(-r_inner + 1.2, 0), Vector2(-half_hole - 1.0, 0), mark_col, 1.0, true)
	BatchDraw.native_line(self, Vector2(r_inner - 1.2, 0), Vector2(half_hole + 1.0, 0), mark_col, 1.0, true)

	# 7. 边缘超白反光起辉点（FX_HDR_GOLD + FX_HDR_METAL）
	var gleam_pos := Vector2(R * 0.65, -R * 0.65)
	BatchDraw.circle(self, gleam_pos, 1.3, GameStyle.FX_HDR_GOLD)
	BatchDraw.circle(self, -gleam_pos * 0.8, 0.9, GameStyle.FX_HDR_METAL)

# ======================================================================================
# 机关专属器形（2026-11-07）
# 器械语言 = 直角/铆钉/铜铁冷色底 + 元素锋尖；法器弹保持灵性弧线。同元素下也能分出「谁打的」。
# 尺寸口径：本体沿 +X 画 24~30px，配表内 bullet_scale 0.5~0.6 ⇒ 屏上 ~12~18px，
# 与手武器弹丸（庚金飞剑 17px / 符纸 ~11px）同档，不靠「画大一点」骗辨识度。
# 每个器形的批顶点 ≈ 30~65，远低于手里剑的 ~570（性能闸见 tests/inspect_check.gd）。
# ======================================================================================

# ----------------- 机关弩：方形钢矢（三棱镞 + 三片尾羽 + 铜箍） -----------------
func _draw_bolt_crossbow() -> void:
	# 弦风：两道极淡的平行尾气，给「弩」一个抛射方向感
	BatchDraw.native_line(self, Vector2(-13.0, -1.0), Vector2(-26.0, -2.4), Color(0.72, 0.74, 0.80, 0.22), 1.0, true)
	BatchDraw.native_line(self, Vector2(-13.0, 1.0), Vector2(-26.0, 2.4), Color(0.72, 0.74, 0.80, 0.22), 1.0, true)
	# 矢杆（冷钢直杆，机械感靠「直」）
	BatchDraw.native_line(self, Vector2(-14.0, 0.0), Vector2(7.0, 0.0), Color(0.76, 0.80, 0.86), 1.8, true)
	# 尾羽两片（方硬不飘）
	var fin_top := PackedVector2Array([
		Vector2(-13.6, 0.0), Vector2(-8.4, -3.4), Vector2(-9.8, 0.0)])
	BatchDraw.native_poly(self, fin_top, Color(0.86, 0.88, 0.92))
	var fin_bot := PackedVector2Array([
		Vector2(-13.6, 0.0), Vector2(-8.4, 3.4), Vector2(-9.8, 0.0)])
	BatchDraw.native_poly(self, fin_bot, Color(0.66, 0.70, 0.78))
	# 铜箍（铆在杆上的机件）
	BatchDraw.native_rect(self, Rect2(-3.2, -1.3, 3.0, 2.6), Color(0.88, 0.72, 0.30))
	# 三棱镞
	var head := PackedVector2Array([
		Vector2(12.5, 0.0), Vector2(6.4, -2.6), Vector2(6.4, 2.6)])
	BatchDraw.native_poly(self, head, Color(0.93, 0.95, 0.98))
	var head_shade := PackedVector2Array([
		Vector2(12.5, 0.0), Vector2(6.4, 0.0), Vector2(6.4, 2.6)])
	BatchDraw.native_poly(self, head_shade, Color(0.62, 0.66, 0.74))
	# 镞尖寒芒
	BatchDraw.circle(self, Vector2(12.5, 0.0), 1.0, GameStyle.FX_HDR_METAL)

# ----------------- 剑阵盘：短剑 + 环绕符文阵环（自转） -----------------
func _draw_blade_array() -> void:
	var ring_ang := _lifetime_acc * 3.2
	# 阵环：倾斜椭圆（旋转 = 自转阵盘），用 9 段 polyline 控制顶点
	var ring_pts := PackedVector2Array()
	var segs := 9
	for i in range(segs + 1):
		var t := float(i) / float(segs) * TAU
		ring_pts.append(Vector2(cos(t) * 11.0, sin(t) * 4.2).rotated(ring_ang))
	BatchDraw.native_polyline(self, ring_pts, Color(0.78, 0.90, 1.0, 0.55), 0.9, true)
	# 阵环上的四个符位（阵盘读作「阵」的关键：环上有节点，不是一根光弧）
	for k in range(4):
		var a := ring_ang + float(k) * PI * 0.5
		BatchDraw.circle(self, Vector2(cos(a) * 11.0, sin(a) * 4.2), 0.9, Color(1.0, 0.88, 0.45, 0.9))

	# 短剑阳面 / 阴面
	var top := PackedVector2Array([
		Vector2(13.0, 0.0), Vector2(2.0, -3.0), Vector2(-7.0, -2.4), Vector2(-8.5, 0.0)])
	BatchDraw.native_poly(self, top, Color(0.90, 0.93, 0.98))
	var bot := PackedVector2Array([
		Vector2(13.0, 0.0), Vector2(-8.5, 0.0), Vector2(-7.0, 2.4), Vector2(2.0, 3.0)])
	BatchDraw.native_poly(self, bot, Color(0.64, 0.70, 0.80))
	# 剑脊 + 剑格剑柄
	BatchDraw.native_line(self, Vector2(13.0, 0.0), Vector2(-8.5, 0.0), Color(1.0, 0.88, 0.45), 0.9, true)
	BatchDraw.native_line(self, Vector2(-7.6, -3.0), Vector2(-7.6, 3.0), Color(0.24, 0.22, 0.30), 1.4, true)
	BatchDraw.native_line(self, Vector2(-7.6, 0.0), Vector2(-12.0, 0.0), Color(0.16, 0.16, 0.20), 1.4, true)
	# 剑尖
	BatchDraw.circle(self, Vector2(13.0, 0.0), 1.0, GameStyle.FX_HDR_METAL)

# ----------------- 喷火兽：暗铁壳火丸（内炽橙核 + 后随烟团） -----------------
func _draw_ember_shot() -> void:
	# 后随烟团（暗暖灰，越远越淡）
	BatchDraw.circle(self, Vector2(-9.0, 0.0), 3.4, Color(0.28, 0.24, 0.24, 0.30))
	BatchDraw.circle(self, Vector2(-14.0, 0.0), 2.2, Color(0.24, 0.21, 0.22, 0.18))
	# 泄出的火舌
	BatchDraw.native_line(self, Vector2(-4.6, 0.0), Vector2(-9.4, -2.2), Color(1.0, 0.55, 0.18, 0.55), 1.6, true)
	BatchDraw.native_line(self, Vector2(-4.6, 0.0), Vector2(-9.4, 2.2), Color(1.0, 0.55, 0.18, 0.55), 1.6, true)
	# 铁壳（暗）→ 熔层 → 白炽核
	BatchDraw.circle(self, Vector2.ZERO, 5.2, Color(0.32, 0.24, 0.22))
	BatchDraw.arc(self, Vector2.ZERO, 5.2, 0.0, TAU, Color(0.56, 0.44, 0.34, 0.9), 1.2)
	BatchDraw.circle(self, Vector2.ZERO, 3.6, Color(1.0, 0.52, 0.14))
	BatchDraw.circle(self, Vector2(0.6, -0.4), 1.9, GameStyle.FX_HDR_FIRE)

# ----------------- 寒泉兽：棱角冰棱（冷蓝六面体 + 霜枝） -----------------
func _draw_ice_shard() -> void:
	# 寒气拖尾
	var mist := PackedVector2Array([
		Vector2(-6.0, -3.4), Vector2(-26.0, 0.0), Vector2(-6.0, 3.4)])
	BatchDraw.native_poly(self, mist, Color(0.40, 0.80, 1.0, 0.18))
	# 冰棱本体（六面棱柱侧面；2026-11-07 出图后加宽 ±4.4 —— 第一版太窄，屏上仍像一根针）
	var shard := PackedVector2Array([
		Vector2(14.0, 0.0), Vector2(6.0, -4.4), Vector2(-4.0, -3.2),
		Vector2(-9.5, 0.0), Vector2(-4.0, 3.2), Vector2(6.0, 4.4)])
	BatchDraw.native_poly(self, shard, Color(0.74, 0.94, 1.0))
	# 阴面
	var shade := PackedVector2Array([
		Vector2(14.0, 0.0), Vector2(-9.5, 0.0), Vector2(-4.0, 3.2), Vector2(6.0, 4.4)])
	BatchDraw.native_poly(self, shade, Color(0.34, 0.68, 0.96))
	# 棱脊 + 霜枝
	BatchDraw.native_line(self, Vector2(14.0, 0.0), Vector2(-8.5, 0.0), Color(0.92, 0.99, 1.0), 0.9, true)
	BatchDraw.native_line(self, Vector2(4.0, -3.9), Vector2(2.2, -6.0), Color(0.86, 0.98, 1.0, 0.8), 0.7, true)
	BatchDraw.native_line(self, Vector2(-3.0, 3.0), Vector2(-4.6, 5.0), Color(0.86, 0.98, 1.0, 0.7), 0.7, true)
	# 冰棱尖 + 尾端断裂口
	BatchDraw.circle(self, Vector2(14.0, 0.0), 1.0, GameStyle.FX_HDR_WATER)
	BatchDraw.native_line(self, Vector2(-9.5, -2.0), Vector2(-9.5, 2.0), Color(0.30, 0.62, 0.90), 1.2, true)

# ----------------- 藤萝机关：木刺（藤蔓纤维 + 附叶） -----------------
func _draw_vine_thorn() -> void:
	# 藤蔓纤维（两道后拖）
	BatchDraw.native_line(self, Vector2(-7.0, -1.6), Vector2(-24.0, -4.4), Color(0.35, 0.62, 0.34, 0.42), 1.1, true)
	BatchDraw.native_line(self, Vector2(-7.0, 1.6), Vector2(-22.0, 4.0), Color(0.35, 0.62, 0.34, 0.34), 1.1, true)
	# 附叶（一眼认出「木/藤」）
	var leaf := PackedVector2Array([
		Vector2(-4.0, -1.0), Vector2(-10.0, -5.4), Vector2(-14.0, -2.6), Vector2(-8.0, -0.4)])
	BatchDraw.native_poly(self, leaf, Color(0.40, 0.72, 0.38, 0.85))
	# 木刺本体
	var thorn := PackedVector2Array([
		Vector2(13.0, 0.0), Vector2(3.0, -3.0), Vector2(-9.0, -1.6),
		Vector2(-9.0, 1.6), Vector2(3.0, 3.0)])
	BatchDraw.native_poly(self, thorn, Color(0.66, 0.52, 0.30))
	# 阴面
	var shade := PackedVector2Array([
		Vector2(13.0, 0.0), Vector2(-9.0, 0.0), Vector2(-9.0, 1.6), Vector2(3.0, 3.0)])
	BatchDraw.native_poly(self, shade, Color(0.46, 0.36, 0.22))
	# 刺脊 + 侧生小刺
	BatchDraw.native_line(self, Vector2(13.0, 0.0), Vector2(-8.0, 0.0), Color(0.86, 0.78, 0.48), 0.9, true)
	BatchDraw.native_line(self, Vector2(2.0, -2.2), Vector2(-0.5, -4.2), Color(0.86, 0.78, 0.48, 0.85), 0.7, true)
	# 刺尖（木系 HDR）
	BatchDraw.circle(self, Vector2(13.0, 0.0), 1.0, GameStyle.FX_HDR_WOOD)

# ----------------- 垒石机关：重岩弹（圆钝石球 + 后随石屑） -----------------
func _draw_stone_bolt() -> void:
	# 石屑（重物拽出的尘带）
	BatchDraw.circle(self, Vector2(-9.5, 1.2), 3.0, Color(0.52, 0.44, 0.34, 0.28))
	BatchDraw.circle(self, Vector2(-14.5, 2.2), 1.9, Color(0.48, 0.41, 0.32, 0.18))
	# 石球本体（圆钝，不做尖头 —— 剪影就是「砸」）
	BatchDraw.circle(self, Vector2.ZERO, 6.0, Color(0.60, 0.50, 0.36))
	BatchDraw.arc(self, Vector2.ZERO, 6.0, 0.0, TAU, Color(0.40, 0.33, 0.24, 0.9), 1.2)
	# 受光棱面
	BatchDraw.circle(self, Vector2(1.2, -1.4), 3.8, Color(0.80, 0.68, 0.48))
	# 石纹裂口（两道，读得出「岩」不是「球」）
	BatchDraw.native_line(self, Vector2(-3.6, -2.4), Vector2(0.4, 0.6), Color(0.36, 0.30, 0.22, 0.85), 0.9, true)
	BatchDraw.native_line(self, Vector2(0.4, 0.6), Vector2(-1.2, 3.2), Color(0.36, 0.30, 0.22, 0.7), 0.8, true)
	BatchDraw.circle(self, Vector2(4.2, -3.2), 1.0, GameStyle.FX_HDR_EARTH)

# ----------------- 傀儡兽：方形符石（傀儡符印 + 引丝） -----------------
## 2026-11-07 第一版画成「土黄圆球 + 两只眼」，出图一看与垒石机关的重岩弹几乎同形同色。
## 现在改成「块面方石 + 高亮符印」：剪影从圆变方、亮度集中在符印 —— 一个是砸的石头，一个是带符的傀儡。
func _draw_puppet_orb() -> void:
	# 引丝（御灵傀儡的悬丝，两道向后上方）
	BatchDraw.native_line(self, Vector2(-4.0, -4.0), Vector2(-15.0, -7.5), Color(0.78, 0.86, 1.0, 0.40), 0.8, true)
	BatchDraw.native_line(self, Vector2(-4.0, 4.0), Vector2(-15.0, 7.5), Color(0.78, 0.86, 1.0, 0.40), 0.8, true)
	# 石屑
	BatchDraw.circle(self, Vector2(-11.5, 1.8), 2.0, Color(0.48, 0.41, 0.32, 0.20))
	# 方形符石（块面，与垒石机关的圆石一眼分家）
	var block := PackedVector2Array([
		Vector2(8.5, -4.6), Vector2(-7.0, -5.6), Vector2(-9.0, 4.8), Vector2(7.0, 5.4)])
	BatchDraw.native_poly(self, block, Color(0.58, 0.45, 0.26))
	# 受光棱面（上半）
	var face := PackedVector2Array([
		Vector2(8.5, -4.6), Vector2(-7.0, -5.6), Vector2(-7.7, -0.4), Vector2(7.8, 0.2)])
	BatchDraw.native_poly(self, face, Color(0.74, 0.61, 0.38))
	# 石棱描边
	block.append(block[0])
	BatchDraw.native_polyline(self, block, Color(0.88, 0.74, 0.42), 1.1, true)
	# 傀儡符印：亮圆 + 十字刻痕（读作「符」而不是「石头」）
	BatchDraw.circle(self, Vector2(0.2, 0.4), 2.4, Color(0.98, 0.82, 0.42, 0.95))
	BatchDraw.native_line(self, Vector2(-1.6, 0.4), Vector2(2.0, 0.4), Color(0.34, 0.24, 0.10), 0.9, true)
	BatchDraw.native_line(self, Vector2(0.2, -1.4), Vector2(0.2, 2.2), Color(0.34, 0.24, 0.10), 0.9, true)
	# 土系起辉
	BatchDraw.circle(self, Vector2(-4.2, 3.4), 1.0, GameStyle.FX_HDR_EARTH)

# ----------------- 青木炮：木炮壳（燃引信 + 烟迹） -----------------
func _draw_wood_shell() -> void:
	# 烟迹
	BatchDraw.circle(self, Vector2(-9.0, 0.0), 3.2, Color(0.34, 0.34, 0.30, 0.26))
	BatchDraw.circle(self, Vector2(-14.0, 0.0), 2.0, Color(0.30, 0.30, 0.28, 0.16))
	# 木壳（钝头炮弹，比藤萝刺粗、比石球方）
	var shell := PackedVector2Array([
		Vector2(11.0, 0.0), Vector2(8.0, -3.6), Vector2(1.0, -4.4), Vector2(-7.0, -3.6),
		Vector2(-10.0, 0.0), Vector2(-7.0, 3.6), Vector2(1.0, 4.4), Vector2(8.0, 3.6)])
	BatchDraw.native_poly(self, shell, Color(0.58, 0.46, 0.26))
	# 青铜箍（机关炮的「炮」感；2026-11-07 出图后加宽提亮 —— 原 2.8 宽在 0.55 缩放下看不见）
	BatchDraw.native_rect(self, Rect2(-1.6, -4.4, 3.4, 8.8), Color(0.92, 0.74, 0.30))
	# 木纹（两道顺纹）
	BatchDraw.native_line(self, Vector2(7.0, -2.0), Vector2(-7.0, -2.0), Color(0.76, 0.64, 0.36, 0.8), 0.8, true)
	BatchDraw.native_line(self, Vector2(7.0, 2.0), Vector2(-7.0, 2.0), Color(0.42, 0.32, 0.16, 0.8), 0.8, true)
	# 炮口木灵光（钝头炮壳靠这块绿光才读得出「灵炮」而不是一坨木头）
	var muzzle := PackedVector2Array([
		Vector2(11.5, 0.0), Vector2(7.2, -2.6), Vector2(7.2, 2.6)])
	BatchDraw.native_poly(self, muzzle, Color(0.62, 0.94, 0.56, 0.92))
	BatchDraw.circle(self, Vector2(11.5, 0.0), 1.2, GameStyle.FX_HDR_WOOD)
	# 引信 + 火花
	BatchDraw.native_line(self, Vector2(3.0, -4.2), Vector2(-1.0, -8.0), Color(0.90, 0.82, 0.60), 0.9, true)
	BatchDraw.circle(self, Vector2(-1.0, -8.0), 1.2, GameStyle.FX_HDR_FIRE)

# ----------------- 凝冰机弩：机弩矢（铜尾箍）+ 冰晶镞头 -----------------
func _draw_frost_bolt() -> void:
	# 霜气尾迹
	BatchDraw.native_line(self, Vector2(-12.0, 0.0), Vector2(-26.0, 0.0), Color(0.55, 0.85, 1.0, 0.24), 1.6, true)
	# 矢杆
	BatchDraw.native_line(self, Vector2(-12.0, 0.0), Vector2(5.0, 0.0), Color(0.74, 0.82, 0.90), 1.6, true)
	# 铜尾箍（与机关弩同族的机件）
	BatchDraw.native_rect(self, Rect2(-12.0, -1.4, 2.6, 2.8), Color(0.82, 0.64, 0.28))
	# 尾羽两片
	var fin_top := PackedVector2Array([
		Vector2(-8.2, 0.0), Vector2(-3.4, -3.0), Vector2(-4.8, 0.0)])
	BatchDraw.native_poly(self, fin_top, Color(0.74, 0.84, 0.94))
	var fin_bot := PackedVector2Array([
		Vector2(-8.2, 0.0), Vector2(-3.4, 3.0), Vector2(-4.8, 0.0)])
	BatchDraw.native_poly(self, fin_bot, Color(0.54, 0.66, 0.82))
	# 冰晶镞（菱形，与机关弩的三角形钢镞一眼分家）
	var head := PackedVector2Array([
		Vector2(13.0, 0.0), Vector2(7.0, -2.8), Vector2(3.0, 0.0), Vector2(7.0, 2.8)])
	BatchDraw.native_poly(self, head, Color(0.80, 0.96, 1.0))
	var head_shade := PackedVector2Array([
		Vector2(13.0, 0.0), Vector2(3.0, 0.0), Vector2(7.0, 2.8)])
	BatchDraw.native_poly(self, head_shade, Color(0.36, 0.70, 0.96))
	# 镞尖寒芒
	BatchDraw.circle(self, Vector2(13.0, 0.0), 1.0, GameStyle.FX_HDR_WATER)

# ----------------- 烽火台：烽火焰旗 + 上飘火星 -----------------
func _draw_beacon_flare() -> void:
	var pulse := 1.0 + sin(_lifetime_acc * 17.0) * 0.10
	# 焰旗尾（烽火台的「烽」：一面赤旗被火拽在身后）
	var banner := PackedVector2Array([
		Vector2(-4.0, -2.8), Vector2(-17.0, -1.4), Vector2(-11.0, 0.0),
		Vector2(-17.0, 1.4), Vector2(-4.0, 2.8)])
	BatchDraw.native_poly(self, banner, Color(0.90, 0.34, 0.12, 0.72))
	# 外层赤焰 / 中层炽金 / 白炽核
	var outer := PackedVector2Array([
		Vector2(11.0 * pulse, 0.0), Vector2(4.0, -5.0), Vector2(-3.0, -4.0),
		Vector2(-6.0, 0.0), Vector2(-3.0, 4.0), Vector2(4.0, 5.0)])
	BatchDraw.native_poly(self, outer, Color(0.90, 0.28, 0.12, 0.80))
	var mid := PackedVector2Array([
		Vector2(8.5 * pulse, 0.0), Vector2(2.5, -3.0), Vector2(-3.0, -2.4),
		Vector2(-4.5, 0.0), Vector2(-3.0, 2.4), Vector2(2.5, 3.0)])
	BatchDraw.native_poly(self, mid, Color(1.0, 0.64, 0.20, 0.92))
	BatchDraw.circle(self, Vector2(1.8, 0.0), 2.0 * pulse, GameStyle.FX_HDR_FIRE)
	# 上飘火星（烽烟的余烬，与纯火球的区别）
	BatchDraw.circle(self, Vector2(-1.0, -7.0), 1.0, Color(1.0, 0.72, 0.30, 0.85))
	BatchDraw.circle(self, Vector2(-6.0, -10.0), 0.8, Color(1.0, 0.62, 0.24, 0.55))


