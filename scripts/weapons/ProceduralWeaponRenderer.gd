class_name ProceduralWeaponRenderer
extends Node2D

## 纯矢量法器本体渲染器（冷冽国风修仙）
## 取代 FloatingWeapon 本体那张 48×48 AI 贴图，与角色/敌人/弹丸/刀光/光束同一套矢量画风，
## 消除「Q版像素粗黑描边贴图」与「冷冽矢量」之间的画风断层。
##
## 【坐标契约 — 与 WeaponData.tip / FloatingWeapon.MuzzlePoint 严格对齐】
##   · 在【画布像素】空间沿 +X 轴绘制，器尖落在 (tip_len, 0)；
##   · 外部把本节点 scale 设成 0.55（与旧 Sprite2D 同尺寸），节点 rotation 即瞄准角；
##   · 于是器尖屏上位置 = tip_len × 0.55 == MuzzlePoint 出膛点（muzzle_len 同式），
##     出膛点、命中判定、挥砍朝向全部零改动。
##   · 非 upright 武器直接跟随节点转角；upright 重器由外部下发 rotation = -angle 保持世界竖直。
##
## 灰度切换：shape == GENERIC（未实现的大类）时由 FloatingWeapon 保留原贴图显示，
## 逐批把大类补齐（批次 1：剑/刀/匕首；批次 2：符箓/扇/印/牌令/灯/鼓/铎）。

## 器形族模块库（scripts/weapons/shapes/）：重绘接管的器形优先走族模块新画法，
## 未接管的一律回退本文件旧画法（灰度增量，不破现状）。新增/重绘器形只改族模块，别动本文件。
const WeaponShapeLibrary = preload("res://scripts/weapons/shapes/WeaponShapeLibrary.gd")
## 野兽派共用调色板/构件：本文件的 ★4 霓虹脊线取色与族模块同一处真话（别在这儿再写一份色值）
const BC = preload("res://scripts/weapons/shapes/BrutalistCommon.gd")

enum WeaponShape {
	SWORD,     ## 直剑：双刃平行、末端收锋
	SABER,     ## 弯刀：刀背直、刀腹鼓
	DAGGER,    ## 柳叶匕首：两头收尖的叶形
	TALISMAN,  ## 符箓：竖挂/横置符纸 + 朱砂印 + 灵纹
	FAN,       ## 扇：扇形扇面 + 扇骨 + 扇钉
	SEAL,      ## 印：方形印身 + 拱形印钮（巨印）
	TABLET,    ## 牌/令：竖长令牌 + 云纹 + 雷纹
	LANTERN,   ## 灯：圆腹灯笼 + 上下箍 + 流苏（天灯）
	DRUM,      ## 鼓：正视鼓面 + 鼓框 + 鼓钉（春雷鼓）
	BELL,      ## 铎：钟形铎身 + 顶部提环 + 铎舌（裂山铎）
	WHIP,      ## 鞭：短柄 + 多节渐细鞭身（藤鞭）
	SHIELD,    ## 盾：盾面 + 盾脊 + 中央盾钉（重盾）
	AXE,       ## 斧：长柄 + 单侧月牙斧刃（开山斧）
	HAMMER,    ## 锤：长柄 + 方锤头（崩浪锤）
	MACE,      ## 锏：六棱重锏 + 节环 + 锏首（六棱锏）
	RULER,     ## 尺：长条金尺 + 刻度（聚宝金尺）
	SHEARS,    ## 剪：双刃交叉 + 指环（金蛟剪）
	SHUTTLE,   ## 梭：两头尖的流线梭（浪里梭）
	NAIL,      ## 钉：方帽长钉（透骨钉）
	NEEDLES,   ## 针：成束细针（暴雨针 / 冰针）
	SLING,     ## 弹弓：Y 形弓架 + 皮兜（连环灵弹）
	CALABASH,  ## 葫芦：双腹葫芦 + 口塞（火葫芦）
	FLUTE,     ## 笛：竹笛 + 指孔 + 流苏（音笛）
	MIRROR,    ## 镜：圆镜 + 边框 + 镜柄（紫虹镜）
	BEAD,      ## 珠：多棱宝珠 + 内核（玄冥雷珠）
	AWL,       ## 锥：长锥 + 箍环（金雷锥）
	SHURIKEN,  ## 手里剑：四芒旋刃 + 弧形月牙内凹 + 中心透孔（手里剑）
	GENERIC,
}

@export var shape: WeaponShape = WeaponShape.GENERIC
@export var element: String = "metal"
@export var tip_len: float = 28.0
@export var star: int = 1
## 竖置重器（符/印/牌/灯/鼓/铎）：画布内长轴沿 Y 绘制，由宿主下发 rotation=-angle 保持世界竖直。
## 非竖置（剑/刀/扇等）：沿 +X 绘制，器尖朝瞄准方向。
@export var upright: bool = false
@export var weapon_id: String = ""

func configure(p_shape: WeaponShape, p_element: String, p_tip_len: float, p_star: int, p_upright: bool = false, p_weapon_id: String = "") -> void:
	shape = p_shape
	element = p_element
	tip_len = maxf(p_tip_len, 8.0)
	star = clampi(p_star, 1, WeaponData.MAX_STAR)
	upright = p_upright
	weapon_id = p_weapon_id
	queue_redraw()

## 数据表 "shape" 字段 → 枚举（未登记/未实现的一律 GENERIC，调用方据此保留贴图）
static func shape_from_name(s: String) -> WeaponShape:
	match s:
		"sword":
			return WeaponShape.SWORD
		"saber":
			return WeaponShape.SABER
		"dagger":
			return WeaponShape.DAGGER
		"talisman":
			return WeaponShape.TALISMAN
		"fan":
			return WeaponShape.FAN
		"seal":
			return WeaponShape.SEAL
		"tablet":
			return WeaponShape.TABLET
		"lantern":
			return WeaponShape.LANTERN
		"drum":
			return WeaponShape.DRUM
		"bell":
			return WeaponShape.BELL
		"whip":
			return WeaponShape.WHIP
		"shield":
			return WeaponShape.SHIELD
		"axe":
			return WeaponShape.AXE
		"hammer":
			return WeaponShape.HAMMER
		"mace":
			return WeaponShape.MACE
		"ruler":
			return WeaponShape.RULER
		"shears":
			return WeaponShape.SHEARS
		"shuttle":
			return WeaponShape.SHUTTLE
		"nail":
			return WeaponShape.NAIL
		"needles":
			return WeaponShape.NEEDLES
		"sling":
			return WeaponShape.SLING
		"calabash":
			return WeaponShape.CALABASH
		"flute":
			return WeaponShape.FLUTE
		"mirror":
			return WeaponShape.MIRROR
		"bead":
			return WeaponShape.BEAD
		"awl":
			return WeaponShape.AWL
		"shuriken":
			return WeaponShape.SHURIKEN
	return WeaponShape.GENERIC

## 本批是否已实现该器形（false ⇒ 调用方继续显示旧贴图，保证逐批灰度不破现状）
func is_implemented() -> bool:
	return shape != WeaponShape.GENERIC

## 五行配色：亮面 / 暗面 / 刃口流光 / HDR 起辉 / 柄色
## 2026-10-24 静态缓存：本文件 20+ 个器形绘制函数每次 _draw 各取一次，原先每次新建 5 键
## Dictionary；调色板只含常量色且无调用方改写（只读 pal["xxx"]），按 element 常驻共享。
static var _palette_cache := {}

func _palette() -> Dictionary:
	if not _palette_cache.has(element):
		_palette_cache[element] = _build_palette(element)
	return _palette_cache[element]

static func _build_palette(elem: String) -> Dictionary:
	match elem:
		"wood":
			return {
				"light": Color(0.72, 0.90, 0.74), "dark": Color(0.40, 0.62, 0.44),
				"edge": Color(0.55, 1.0, 0.72), "hdr": GameStyle.FX_HDR_WOOD,
				"handle": Color(0.24, 0.20, 0.14),
			}
		"fire":
			return {
				"light": Color(1.0, 0.64, 0.24), "dark": Color(0.80, 0.28, 0.10),
				"edge": Color(1.0, 0.86, 0.42), "hdr": GameStyle.FX_HDR_FIRE,
				"handle": Color(0.20, 0.12, 0.10),
			}
		"water":
			return {
				"light": Color(0.74, 0.93, 1.0), "dark": Color(0.40, 0.66, 0.90),
				"edge": Color(0.62, 0.96, 1.0), "hdr": GameStyle.FX_HDR_WATER,
				"handle": Color(0.14, 0.18, 0.24),
			}
		"earth":
			return {
				"light": Color(0.88, 0.82, 0.64), "dark": Color(0.56, 0.48, 0.34),
				"edge": Color(0.92, 0.80, 0.44), "hdr": GameStyle.FX_HDR_EARTH,
				"handle": Color(0.18, 0.15, 0.12),
			}
		_:
			return {
				"light": Color(0.93, 0.95, 0.99), "dark": Color(0.66, 0.72, 0.82),
				"edge": Color(1.0, 0.88, 0.45), "hdr": GameStyle.FX_HDR_METAL,
				"handle": Color(0.18, 0.16, 0.22),
			}

func _draw() -> void:
	# 竖置重器：把"长轴 +X"的器形整体转 -90° ⇒ 画布长轴朝上（世界竖直，与旧贴图姿态一致）。
	# 非竖置的符箓（镇山符）保持 +X，长轴跟随瞄准方向。
	if upright:
		draw_set_transform(Vector2.ZERO, -PI * 0.5, Vector2.ONE)
	# 新画法分发：族模块已接管（返回 true）就直接画完返回，否则继续走下方旧画法
	if WeaponShapeLibrary.draw_shape(shape, self):
		return
	match shape:
		WeaponShape.SWORD:
			_draw_sword()
		WeaponShape.SABER:
			_draw_saber()
		WeaponShape.DAGGER:
			_draw_dagger()
		WeaponShape.TALISMAN:
			_draw_talisman()
		WeaponShape.FAN:
			_draw_fan()
		WeaponShape.SEAL:
			_draw_seal()
		WeaponShape.TABLET:
			_draw_tablet()
		WeaponShape.LANTERN:
			_draw_lantern()
		WeaponShape.DRUM:
			_draw_drum()
		WeaponShape.BELL:
			_draw_bell()
		WeaponShape.WHIP:
			_draw_whip()
		WeaponShape.SHIELD:
			_draw_shield()
		WeaponShape.AXE:
			_draw_axe()
		WeaponShape.HAMMER:
			_draw_hammer()
		WeaponShape.MACE:
			_draw_mace()
		WeaponShape.RULER:
			_draw_ruler()
		WeaponShape.SHEARS:
			_draw_shears()
		WeaponShape.SHUTTLE:
			_draw_shuttle()
		WeaponShape.NAIL:
			_draw_nail()
		WeaponShape.NEEDLES:
			_draw_needles()
		WeaponShape.SLING:
			_draw_sling()
		WeaponShape.CALABASH:
			_draw_calabash()
		WeaponShape.FLUTE:
			_draw_flute()
		WeaponShape.MIRROR:
			_draw_mirror()
		WeaponShape.BEAD:
			_draw_bead()
		WeaponShape.AWL:
			_draw_awl()
		WeaponShape.SHURIKEN:
			pass  ## 真实画法已由 WeaponShapeLibrary/FineShapes 接管提前返回

	# ---------------- 通用构件 ----------------

## 带暗色描边的填充多边形：外圈暗底 + 内缩亮面
## 注：描边厚度按「内缩比例」控制，比例越接近 1 描边越细。器身小（屏上约 12px 宽），
## 描边必须克制，否则整把剑糊成黑框。
func _fill_outlined(pts: PackedVector2Array, fill: Color) -> void:
	draw_colored_polygon(pts, Color(0.06, 0.07, 0.10, 0.85))
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= float(pts.size())
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(c.lerp(p, 0.955))
	draw_colored_polygon(inner, fill)

## 剑格 + 剑柄 + 剑首（三种器形共用）
func _draw_hilt(pal: Dictionary, w: float) -> void:
	var handle_len := clampf(tip_len * 0.55, 9.0, 15.0)
	var guard_h := w * 1.6
	# 剑格（横向挡手，细长条）
	var guard := PackedVector2Array([
		Vector2(1.0, -guard_h), Vector2(2.0, -guard_h * 0.5),
		Vector2(2.0, guard_h * 0.5), Vector2(1.0, guard_h),
		Vector2(-1.2, guard_h * 0.7), Vector2(-1.2, -guard_h * 0.7),
	])
	_fill_outlined(guard, pal["edge"].darkened(0.2))
	# 剑柄
	draw_line(Vector2(-1.0, 0.0), Vector2(-handle_len, 0.0), Color(0.06, 0.06, 0.08), 2.6, true)
	draw_line(Vector2(-1.0, 0.0), Vector2(-handle_len, 0.0), pal["handle"], 1.7, true)
	# 剑首
	AdaptiveDraw.circle(self, Vector2(-handle_len, 0.0), 1.7, Color(0.06, 0.06, 0.08))
	AdaptiveDraw.circle(self, Vector2(-handle_len, 0.0), 1.1, pal["edge"])

## 器尖 HDR 起辉 + 升星强化
##  ★1：器尖一点寒芒
##  ★2：寒芒变大 + 刃身浮出两粒冷光星点（器身开始「活」起来）
##  ★3：再叠一道贯穿刃脊的流转辉线（结构性强化，贴图时代只能整体变色）
##  ★4：辉线换太虚霓虹双色（电光青 HDR + 太虚紫），器尖再套一圈霓虹外环
func _draw_star_fx(pal: Dictionary, tip: Vector2, ridge_a: Vector2, ridge_b: Vector2) -> void:
	var r := 0.85 + 0.22 * float(star - 1)
	AdaptiveDraw.circle(self, tip, r * 1.25, Color(pal["hdr"].r, pal["hdr"].g, pal["hdr"].b, 0.28))
	AdaptiveDraw.circle(self, tip, r, pal["hdr"])
	AdaptiveDraw.circle(self, tip, r * 0.5, Color(1.0, 1.0, 1.0, 0.95))
	if star >= 2:
		var mid := ridge_b.lerp(ridge_a, 0.55)
		AdaptiveDraw.circle(self, mid, 1.0, Color(pal["edge"].r, pal["edge"].g, pal["edge"].b, 0.9))
		AdaptiveDraw.circle(self, ridge_b.lerp(ridge_a, 0.3), 0.9, Color(pal["edge"].r, pal["edge"].g, pal["edge"].b, 0.75))
	if star >= 4:
		# 极境：电光青脊线 + 太虚紫外描 + 器尖霓虹环（HDR 分量 >1 走引擎泛光）
		draw_line(ridge_b, ridge_a, BC.NEON_CYAN_HDR, 1.6, true)
		draw_line(ridge_b, ridge_a, BC.NEON_VIOLET, 0.8, true)
		draw_arc(tip, r * 1.9, 0.0, TAU, 20, BC.NEON_CYAN_HDR, 0.7, true)
	elif star >= 3:
		draw_line(ridge_b, ridge_a, Color(1.0, 1.0, 1.0, 0.8), 1.3, true)
		draw_line(ridge_b, ridge_a, Color(pal["edge"].r, pal["edge"].g, pal["edge"].b, 0.9), 0.6, true)

# ---------------- 直剑（双刃，刃身平行、末端收锋） ----------------
func _draw_sword() -> void:
	var pal := _palette()
	var L := tip_len
	var star_k := 1.0 + 0.05 * float(star - 1)
	var w := clampf(L * 0.20, 4.0, 6.2) * star_k
	var shoulder := L * 0.80          # 平行刃身到 80% 才收锋（收得太早会像飞镖）
	var ricasso := L * 0.06

	# 外晕（五行气）
	draw_colored_polygon(PackedVector2Array([
		Vector2(L * 1.02, 0.0), Vector2(shoulder, -w * 1.45),
		Vector2(-2.0, -w * 1.15), Vector2(-2.0, w * 1.15), Vector2(shoulder, w * 1.45),
	]), Color(pal["edge"].r, pal["edge"].g, pal["edge"].b, 0.13))

	# 阳面（上刃）
	_fill_outlined(PackedVector2Array([
		Vector2(L, 0.0), Vector2(shoulder, -w), Vector2(ricasso, -w),
		Vector2(ricasso * 0.4, -w * 0.9), Vector2(0.0, -w * 0.7), Vector2(0.0, 0.0),
	]), pal["light"])
	# 阴面（下刃，压暗）
	draw_colored_polygon(PackedVector2Array([
		Vector2(L, 0.0), Vector2(0.0, 0.0), Vector2(0.0, w * 0.7),
		Vector2(ricasso * 0.4, w * 0.9), Vector2(ricasso, w), Vector2(shoulder, w),
	]), pal["dark"])

	# 中脊血槽 + 刃口高光
	draw_line(Vector2(L * 0.96, 0.0), Vector2(ricasso, 0.0), pal["edge"], 1.1, true)
	draw_line(Vector2(shoulder, -w), Vector2(L * 0.99, -w * 0.12), Color(1.0, 1.0, 1.0, 0.55), 0.8, true)

	_draw_hilt(pal, w)
	_draw_star_fx(pal, Vector2(L, 0.0), Vector2(L * 0.9, 0.0), Vector2(L * 0.2, 0.0))

# ---------------- 单刃弯刀（刀背直、刀腹鼓） ----------------
func _draw_saber() -> void:
	var pal := _palette()
	var L := tip_len
	var star_k := 1.0 + 0.05 * float(star - 1)
	var w := clampf(L * 0.24, 4.4, 7.0) * star_k

	draw_colored_polygon(PackedVector2Array([
		Vector2(L * 1.02, 0.0), Vector2(L * 0.55, -w * 1.35),
		Vector2(-1.0, -w * 1.1), Vector2(-1.0, w * 1.3),
		Vector2(L * 0.5, w * 1.45),
	]), Color(pal["edge"].r, pal["edge"].g, pal["edge"].b, 0.15))

	# 刀背（上，暗面直边）
	_fill_outlined(PackedVector2Array([
		Vector2(L, 0.0), Vector2(L * 0.45, -w * 0.62), Vector2(0.0, -w * 0.82), Vector2(0.0, 0.0),
	]), pal["dark"])
	# 刀腹（下，亮面鼓起）
	_fill_outlined(PackedVector2Array([
		Vector2(L, 0.0), Vector2(L * 0.66, w * 1.06), Vector2(L * 0.30, w * 1.0),
		Vector2(0.0, w * 0.6), Vector2(0.0, 0.0),
	]), pal["light"])
	# 刀腹锋口流光
	draw_line(Vector2(L, 0.0), Vector2(L * 0.30, w * 1.0), pal["edge"], 1.2, true)

	_draw_hilt(pal, w)
	_draw_star_fx(pal, Vector2(L, 0.0), Vector2(L * 0.82, -w * 0.2), Vector2(L * 0.22, w * 0.8))

# ---------------- 柳叶匕首（两头收尖的叶形） ----------------
func _draw_dagger() -> void:
	var pal := _palette()
	var L := tip_len
	var star_k := 1.0 + 0.05 * float(star - 1)
	var w := clampf(L * 0.26, 4.0, 6.2) * star_k
	var belly := L * 0.50

	draw_colored_polygon(PackedVector2Array([
		Vector2(L * 1.02, 0.0), Vector2(belly, -w * 1.35),
		Vector2(-1.0, -w * 0.8), Vector2(-1.0, w * 0.8), Vector2(belly, w * 1.35),
	]), Color(pal["edge"].r, pal["edge"].g, pal["edge"].b, 0.15))

	_fill_outlined(PackedVector2Array([
		Vector2(L, 0.0), Vector2(belly, -w), Vector2(L * 0.14, -w * 0.42), Vector2(0.0, 0.0),
	]), pal["light"])
	_fill_outlined(PackedVector2Array([
		Vector2(L, 0.0), Vector2(0.0, 0.0), Vector2(L * 0.14, w * 0.42), Vector2(belly, w),
	]), pal["dark"])
	draw_line(Vector2(L * 0.94, 0.0), Vector2(L * 0.08, 0.0), pal["edge"], 1.0, true)

	_draw_hilt(pal, w)
	_draw_star_fx(pal, Vector2(L, 0.0), Vector2(L * 0.75, 0.0), Vector2(L * 0.2, 0.0))

# ================= 批次 2：符箓 / 扇 / 印 / 牌令 / 灯 / 鼓 / 铎 =================
# 这七类都是「无锋刃法器」，重心在器身与灵纹，不在指向。竖置类（符/印/牌/灯/鼓/铎）
# 在 _draw 里整体旋转 -90°，让画布长轴朝上；宿主再下发 rotation=-angle 保持世界竖直。

## 符纸/绢面底色：五行亮面提亮后偏向暖纸白，避免纯色卡片感
func _paper(pal: Dictionary) -> Color:
	return pal["light"].lerp(Color(0.96, 0.92, 0.82), 0.62)

## 朱砂/墨色：暗面加深，用于符纹、印钮与器身刻痕
func _ink(pal: Dictionary) -> Color:
	return pal["dark"].darkened(0.42)

## 器心起辉（竖置重器共用）：器心一点灵光 + 升星结构强化
##  ★2 两侧浮出灵光点、★3 叠一道环身辉圈（贴图时代只能整体变色）、
##  ★4 换太虚霓虹双色环（电光青外圈 + 太虚紫内圈，紫电琉璃）
func _draw_core_fx(pal: Dictionary, center: Vector2, r0: float) -> void:
	var r := r0 * (1.0 + 0.20 * float(star - 1))
	AdaptiveDraw.circle(self, center, r * 2.0, Color(pal["hdr"].r, pal["hdr"].g, pal["hdr"].b, 0.22))
	AdaptiveDraw.circle(self, center, r, pal["hdr"])
	AdaptiveDraw.circle(self, center, r * 0.5, Color(1.0, 1.0, 1.0, 0.95))
	if star >= 2:
		for i in range(2):
			var a := PI * 0.5 + PI * float(i)
			AdaptiveDraw.circle(self, center + Vector2(cos(a), sin(a)) * r * 2.4, r * 0.42,
				Color(pal["edge"].r, pal["edge"].g, pal["edge"].b, 0.85))
	if star >= 4:
		AdaptiveDraw.arc(self, center, r * 2.9, 0.0, TAU, BC.NEON_CYAN_HDR, 1.2, true)
		AdaptiveDraw.arc(self, center, r * 2.4, 0.0, TAU, BC.NEON_VIOLET, 0.9, true)
	elif star >= 3:
		AdaptiveDraw.arc(self, center, r * 2.7, 0.0, TAU,
			Color(pal["edge"].r, pal["edge"].g, pal["edge"].b, 0.55), 1.0, true)

# ---------------- 符箓（竖挂/横置符纸 + 朱砂印 + 灵纹） ----------------
func _draw_talisman() -> void:
	var pal := _palette()
	var L := tip_len
	var hw := clampf(L * 0.34, 5.0, 8.0) * (1.0 + 0.04 * float(star - 1))
	var paper := _paper(pal)
	var ink := _ink(pal)
	var edge: Color = pal["edge"]

	# 符尾（纸尾自然收成小尖角，不做飘带 —— 俯视小尺寸下飘带只会读成箭头）

	# 符纸主体（首端微收、尾端方正）
	_fill_outlined(PackedVector2Array([
		Vector2(L, 0.0), Vector2(L * 0.88, -hw * 0.9), Vector2(-L * 0.88, -hw),
		Vector2(-L * 0.95, 0.0), Vector2(-L * 0.88, hw), Vector2(L * 0.88, hw * 0.9),
	]), paper)

	# 符头/符尾横箍
	draw_line(Vector2(L * 0.78, -hw * 0.88), Vector2(L * 0.78, hw * 0.88), ink, 1.6, true)
	draw_line(Vector2(-L * 0.70, -hw * 0.94), Vector2(-L * 0.70, hw * 0.94), ink, 1.4, true)

	# 朱砂印（符尾近处的方印，固定朱红 —— 符箓的丹砂色不随五行走）
	var sc := Vector2(-L * 0.42, 0.0)
	var sq := hw * 0.42
	draw_colored_polygon(PackedVector2Array([
		sc + Vector2(-sq, -sq), sc + Vector2(sq, -sq), sc + Vector2(sq, sq), sc + Vector2(-sq, sq),
	]), Color(0.62, 0.12, 0.10, 0.92))

	# 灵纹：沿符轴的主脉 + 两道侧纹 + 一道横向符胆
	draw_line(Vector2(L * 0.68, 0.0), Vector2(-L * 0.12, 0.0), ink, 1.1, true)
	draw_line(Vector2(L * 0.5, -hw * 0.45), Vector2(L * 0.08, -hw * 0.45), ink, 0.9, true)
	draw_line(Vector2(L * 0.5, hw * 0.45), Vector2(L * 0.08, hw * 0.45), ink, 0.9, true)
	draw_line(Vector2(L * 0.34, -hw * 0.5), Vector2(L * 0.34, hw * 0.5),
		Color(edge.r, edge.g, edge.b, 0.6), 0.8, true)

	_draw_star_fx(pal, Vector2(L, 0.0), Vector2(L * 0.55, 0.0), Vector2(-L * 0.15, 0.0))

# ---------------- 扇（扇形扇面 + 扇骨 + 扇钉） ----------------
## 扇只出现在横扫（SWEEP）武器上：没有弹丸出膛点契约，扇面半径可略大于 tip_len，
## 免得 tip=15 的小扇子在场上比旁边法器小一圈。
func _draw_fan() -> void:
	var pal := _palette()
	var L := maxf(tip_len, 22.0)
	var half := deg_to_rad(54.0)
	var paper := _paper(pal)
	var ink := _ink(pal)
	var edge: Color = pal["edge"]
	const SEG := 22

	# 扇面外轮廓（暗底）
	var outer := PackedVector2Array([Vector2.ZERO])
	for i in range(SEG + 1):
		var a := -half + 2.0 * half * float(i) / float(SEG)
		outer.append(Vector2(cos(a), sin(a)) * L)
	draw_colored_polygon(outer, Color(0.06, 0.07, 0.10, 0.85))
	# 内缩亮面
	var inner := PackedVector2Array([Vector2.ZERO])
	for i in range(SEG + 1):
		var a := -half + 2.0 * half * float(i) / float(SEG)
		inner.append(Vector2(cos(a), sin(a)) * L * 0.95)
	draw_colored_polygon(inner, paper)

	# 扇骨（7 根，自扇钉辐射到外缘）
	for i in range(7):
		var a := -half + 2.0 * half * float(i) / 6.0
		draw_line(Vector2.ZERO, Vector2(cos(a), sin(a)) * L * 0.97, ink, 1.0, true)
	# 外缘弧光
	AdaptiveDraw.arc(self, Vector2.ZERO, L * 0.96, -half, half, Color(edge.r, edge.g, edge.b, 0.85), 1.6, true)
	# 扇柄（自扇钉向后）
	draw_line(Vector2.ZERO, Vector2(-L * 0.34, 0.0), Color(0.06, 0.06, 0.08), 3.0, true)
	draw_line(Vector2.ZERO, Vector2(-L * 0.34, 0.0), pal["handle"], 1.8, true)
	# 扇钉
	AdaptiveDraw.circle(self, Vector2.ZERO, 2.0, Color(0.06, 0.06, 0.08))
	AdaptiveDraw.circle(self, Vector2.ZERO, 1.2, edge)

	_draw_star_fx(pal, Vector2(L * 0.94, 0.0), Vector2(L * 0.55, -L * 0.36), Vector2(L * 0.55, L * 0.36))

# ---------------- 印（方印身 + 拱形提钮） ----------------
func _draw_seal() -> void:
	var pal := _palette()
	var L := tip_len
	var hw := L * 0.86
	var ink := _ink(pal)

	# 印身（方台：首端接钮、尾端是印面，略作梯形）
	_fill_outlined(PackedVector2Array([
		Vector2(L * 0.34, -hw * 0.72), Vector2(L * 0.34, hw * 0.72),
		Vector2(-L * 0.78, hw), Vector2(-L * 0.90, hw * 0.86),
		Vector2(-L * 0.90, -hw * 0.86), Vector2(-L * 0.78, -hw),
	]), pal["light"])

	# 拱形提钮（半环，落在首端）
	AdaptiveDraw.arc(self, Vector2(L * 0.52, 0.0), L * 0.30, -PI * 0.5, PI * 0.5,
		Color(0.06, 0.07, 0.10, 0.9), 4.4, true)
	AdaptiveDraw.arc(self, Vector2(L * 0.52, 0.0), L * 0.30, -PI * 0.5, PI * 0.5,
		pal["dark"], 2.6, true)

	# 印面刻痕（尾端横线 + 中央朱文竖线）
	draw_line(Vector2(-L * 0.82, -hw * 0.9), Vector2(-L * 0.82, hw * 0.9), ink, 1.4, true)
	draw_line(Vector2(-L * 0.66, 0.0), Vector2(-L * 0.02, 0.0), ink, 1.2, true)
	draw_line(Vector2(-L * 0.34, -hw * 0.55), Vector2(-L * 0.34, hw * 0.55),
		Color(pal["edge"].r, pal["edge"].g, pal["edge"].b, 0.7), 1.0, true)

	_draw_core_fx(pal, Vector2(-L * 0.2, 0.0), 1.6)

# ---------------- 牌 / 令（竖长令牌 + 云纹 + 吞口） ----------------
func _draw_tablet() -> void:
	var pal := _palette()
	var L := tip_len
	var hw := clampf(L * 0.42, 6.0, 9.0)
	var body: Color = pal["light"].darkened(0.15)
	var ink := _ink(pal)
	var edge: Color = pal["edge"]

	# 令牌主体：首端圆头、尾端方正
	_fill_outlined(PackedVector2Array([
		Vector2(L, 0.0), Vector2(L * 0.84, -hw * 0.82), Vector2(L * 0.52, -hw),
		Vector2(-L * 0.88, -hw), Vector2(-L * 0.94, 0.0), Vector2(-L * 0.88, hw),
		Vector2(L * 0.52, hw), Vector2(L * 0.84, hw * 0.82),
	]), body)

	# 云纹（沿轴主脉）+ 两侧回纹
	draw_line(Vector2(L * 0.66, 0.0), Vector2(-L * 0.22, 0.0), Color(edge.r, edge.g, edge.b, 0.85), 1.2, true)
	draw_line(Vector2(L * 0.42, -hw * 0.5), Vector2(-L * 0.42, -hw * 0.5), ink, 1.0, true)
	draw_line(Vector2(L * 0.42, hw * 0.5), Vector2(-L * 0.42, hw * 0.5), ink, 1.0, true)
	# 首端吞口（雷云兽首横箍）
	draw_line(Vector2(L * 0.78, -hw * 0.78), Vector2(L * 0.78, hw * 0.78), edge.darkened(0.2), 2.2, true)

	_draw_core_fx(pal, Vector2(-L * 0.35, 0.0), 1.6)

# ---------------- 灯（圆腹灯笼 + 上下箍 + 灯骨 + 流苏） ----------------
## 长轴必须沿本地 +X（竖置时 -90° 转成世界竖直）：bx 是长轴半径、by 是短轴半径。
func _draw_lantern() -> void:
	var pal := _palette()
	var L := tip_len
	var bx := L * 0.66
	var by := L * 0.56
	var ink := _ink(pal)
	var edge: Color = pal["edge"]
	const SEG := 20

	# 灯腹（暗底 + 内缩亮面）
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in range(SEG):
		var a := TAU * float(i) / float(SEG)
		outer.append(Vector2(cos(a) * bx, sin(a) * by))
		inner.append(Vector2(cos(a) * bx * 0.94, sin(a) * by * 0.94))
	draw_colored_polygon(outer, Color(0.06, 0.07, 0.10, 0.85))
	draw_colored_polygon(inner, pal["light"])

	# 纵向灯骨（沿长轴三道，垂直于长轴方向错开）
	for i in range(3):
		var yo := (float(i) - 1.0) * by * 0.52
		draw_line(Vector2(-bx * 0.86, yo), Vector2(bx * 0.86, yo), Color(ink.r, ink.g, ink.b, 0.55), 0.9, true)

	# 上下箍（垂直于长轴，落在长轴两端）
	draw_line(Vector2(bx * 0.72, -by * 0.66), Vector2(bx * 0.72, by * 0.66), edge.darkened(0.3), 2.2, true)
	draw_line(Vector2(-bx * 0.72, -by * 0.66), Vector2(-bx * 0.72, by * 0.66), edge.darkened(0.3), 2.2, true)
	# 流苏（自下箍向尾端拖出）
	draw_line(Vector2(-bx * 0.9, 0.0), Vector2(-bx - L * 0.34, 0.0), edge, 1.4, true)
	draw_line(Vector2(-bx - L * 0.20, 0.0), Vector2(-bx - L * 0.28, L * 0.10), Color(edge.r, edge.g, edge.b, 0.6), 1.0, true)

	_draw_core_fx(pal, Vector2.ZERO, 1.7)

# ---------------- 鼓（正视鼓面 + 鼓框 + 鼓钉） ----------------
## 俯视视角下鼓是「鼓面朝向镜头」：画正圆鼓面 + 内圈鼓框 + 一圈鼓钉 + 中央鼓心，
## 比侧视桶身更容易一眼认出是鼓（侧视桶身在俯视里只会读成一颗蛋）。
func _draw_drum() -> void:
	var pal := _palette()
	var L := tip_len
	var r := L * 0.94
	var edge: Color = pal["edge"]
	var ink := _ink(pal)
	const SEG := 24

	# 鼓面（暗底 + 内缩亮面）
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in range(SEG):
		var a := TAU * float(i) / float(SEG)
		outer.append(Vector2(cos(a) * r, sin(a) * r))
		inner.append(Vector2(cos(a) * r * 0.90, sin(a) * r * 0.90))
	draw_colored_polygon(outer, Color(0.06, 0.07, 0.10, 0.85))
	draw_colored_polygon(inner, pal["light"].darkened(0.08))

	# 内圈鼓框
	AdaptiveDraw.arc(self, Vector2.ZERO, r * 0.72, 0.0, TAU, edge.darkened(0.2), 1.6, true)
	# 鼓面蒙皮纹（十字 + 斜纹，暗示绷紧的皮面）
	draw_line(Vector2(-r * 0.62, 0.0), Vector2(r * 0.62, 0.0), Color(ink.r, ink.g, ink.b, 0.45), 0.9, true)
	draw_line(Vector2(0.0, -r * 0.62), Vector2(0.0, r * 0.62), Color(ink.r, ink.g, ink.b, 0.45), 0.9, true)
	# 一圈鼓钉（8 颗，压在鼓框上）
	for i in range(8):
		var a := TAU * float(i) / 8.0 + PI / 8.0
		AdaptiveDraw.circle(self, Vector2(cos(a), sin(a)) * r * 0.81, 1.0, edge)

	_draw_core_fx(pal, Vector2.ZERO, 1.7)

# ---------------- 铎（钟形铎身 + 顶部提环 + 铎舌） ----------------
func _draw_bell() -> void:
	var pal := _palette()
	var L := tip_len
	var top_w := L * 0.26
	var bot_w := L * 0.70
	var ink := _ink(pal)
	var edge: Color = pal["edge"]

	# 铎身：首端窄、尾端（铎口）外张
	_fill_outlined(PackedVector2Array([
		Vector2(L * 0.88, -top_w * 0.5), Vector2(L * 0.72, -top_w),
		Vector2(-L * 0.74, -bot_w), Vector2(-L * 0.92, -bot_w * 1.04),
		Vector2(-L * 0.92, bot_w * 1.04), Vector2(-L * 0.74, bot_w),
		Vector2(L * 0.72, top_w), Vector2(L * 0.88, top_w * 0.5),
	]), pal["light"].darkened(0.06))

	# 铎口沿 + 身中两道弦纹
	draw_line(Vector2(-L * 0.88, -bot_w * 1.0), Vector2(-L * 0.88, bot_w * 1.0), edge.darkened(0.2), 2.2, true)
	draw_line(Vector2(-L * 0.35, -bot_w * 0.72), Vector2(-L * 0.35, bot_w * 0.72), Color(ink.r, ink.g, ink.b, 0.6), 1.1, true)
	draw_line(Vector2(L * 0.05, -top_w * 1.05), Vector2(L * 0.05, top_w * 1.05), Color(ink.r, ink.g, ink.b, 0.6), 1.1, true)

	# 顶部提环
	AdaptiveDraw.arc(self, Vector2(L * 0.95, 0.0), L * 0.10, -PI * 0.6, PI * 0.6, edge, 1.6, true)
	# 铎舌
	draw_line(Vector2(0.0, 0.0), Vector2(-L * 0.62, 0.0), ink, 1.2, true)
	AdaptiveDraw.circle(self, Vector2(-L * 0.66, 0.0), 1.3, edge)

	_draw_core_fx(pal, Vector2(-L * 0.1, 0.0), 1.6)

# ================= 批次 3：鞭 / 盾 / 斧 / 锤 / 锏 / 尺 / 剪 / 梭 / 钉 / 针 / 弹弓 / 葫芦 / 笛 / 镜 / 珠 / 锥 =================
# 统一约定：沿本地 +X 画，器首（打击端/器口）落在 tip_len 附近；竖置类由 _draw 头部统一转 -90°。

## 长柄类共用：自中心向尾端拖一根柄（-X 方向）
## 柄色必须比背景亮一档 —— pal["handle"] 是深木色，画在深蓝夜地上整根柄会消失，
## 于是只看得见锤头/斧刃，武器读成"悬空的铁块"。
func _draw_shaft(pal: Dictionary, length: float, width: float) -> void:
	var wood: Color = pal["handle"].lerp(pal["light"], 0.45)
	draw_line(Vector2(-length, 0.0), Vector2(0.0, 0.0), Color(0.06, 0.06, 0.08), width + 1.4, true)
	draw_line(Vector2(-length, 0.0), Vector2(0.0, 0.0), wood, width, true)
	# 柄身一侧高光，避免整根糊成一条平色
	draw_line(Vector2(-length, -width * 0.28), Vector2(0.0, -width * 0.28),
		Color(pal["light"].r, pal["light"].g, pal["light"].b, 0.55), width * 0.3, true)

# ---------------- 鞭（短柄 + 多节渐细鞭身） ----------------
func _draw_whip() -> void:
	var pal := _palette()
	var L := tip_len
	var edge: Color = pal["edge"]
	# 鞭身：由粗到细的波状带（上下两条曲线夹成的渐变带，别用细线，小尺寸下会看不见）
	const SEG := 12
	var top := PackedVector2Array()
	var bot := PackedVector2Array()
	for i in range(SEG + 1):
		var t := float(i) / float(SEG)
		var x := lerpf(0.0, L, t)
		var wave := sin(t * PI * 2.2) * L * 0.14
		var half := lerpf(L * 0.10, L * 0.025, t)
		top.append(Vector2(x, wave - half))
		bot.append(Vector2(x, wave + half))
	var ribbon := top.duplicate()
	for i in range(bot.size() - 1, -1, -1):
		ribbon.append(bot[i])
	draw_colored_polygon(ribbon, pal["light"].darkened(0.12))
	# 鞭脊流光
	var ridge := PackedVector2Array()
	for i in range(SEG + 1):
		var t := float(i) / float(SEG)
		ridge.append(Vector2(lerpf(0.0, L, t), sin(t * PI * 2.2) * L * 0.14))
	draw_polyline(ridge, Color(edge.r, edge.g, edge.b, 0.85), 1.2, true)
	# 短柄
	_draw_shaft(pal, L * 0.34, 3.0)
	# 鞭梢灵光
	AdaptiveDraw.circle(self, Vector2(L, sin(PI * 2.2) * L * 0.14), 1.6, pal["hdr"])
	_draw_star_fx(pal, Vector2(L, sin(PI * 2.2) * L * 0.14), Vector2(L * 0.7, 0.0), Vector2(L * 0.3, 0.0))

# ---------------- 盾（盾面 + 盾脊 + 中央盾钉） ----------------
func _draw_shield() -> void:
	var pal := _palette()
	var L := tip_len
	var hh := L * 0.54
	var edge: Color = pal["edge"]
	# 盾面：上宽下尖的尖顶盾，器首朝 +X
	_fill_outlined(PackedVector2Array([
		Vector2(L * 0.96, 0.0), Vector2(L * 0.34, -hh * 0.80), Vector2(-L * 0.74, -hh),
		Vector2(-L * 0.90, 0.0), Vector2(-L * 0.74, hh), Vector2(L * 0.34, hh * 0.80),
	]), pal["light"])
	# 盾脊（沿长轴）+ 横箍
	draw_line(Vector2(L * 0.84, 0.0), Vector2(-L * 0.80, 0.0), Color(edge.r, edge.g, edge.b, 0.9), 1.6, true)
	draw_line(Vector2(L * 0.02, -hh * 0.74), Vector2(L * 0.02, hh * 0.74), pal["dark"], 1.4, true)
	# 中央盾钉
	AdaptiveDraw.circle(self, Vector2(L * 0.04, 0.0), 2.0, Color(0.06, 0.06, 0.08))
	AdaptiveDraw.circle(self, Vector2(L * 0.04, 0.0), 1.2, edge)
	_draw_core_fx(pal, Vector2(L * 0.04, 0.0), 1.1)

# ---------------- 斧（长柄 + 单侧月牙斧刃） ----------------
func _draw_axe() -> void:
	var pal := _palette()
	var L := tip_len
	var edge: Color = pal["edge"]
	_draw_shaft(pal, L * 0.78, 2.6)
	# 斧刃：半月形，刃口朝 +X（外弧用采样点，保证是圆弧而不是折线）
	var blade := PackedVector2Array()
	const BSEG := 22
	for i in range(BSEG + 1):
		var a := -PI * 0.40 + PI * 0.80 * float(i) / float(BSEG)
		blade.append(Vector2(L * 0.18 + cos(a) * L * 0.82, sin(a) * L * 0.86))
	for i in range(BSEG, -1, -1):
		var a := -PI * 0.30 + PI * 0.60 * float(i) / float(BSEG)
		blade.append(Vector2(L * 0.18 + cos(a) * L * 0.30, sin(a) * L * 0.34))
	_fill_outlined(blade, pal["light"])
	# 斧背厚脊
	draw_line(Vector2(L * 0.20, -L * 0.40), Vector2(L * 0.20, L * 0.40), pal["dark"], 2.0, true)
	# 刃口流光
	draw_polyline(PackedVector2Array([
		Vector2(L * 0.18 + cos(-PI * 0.40) * L * 0.82, sin(-PI * 0.40) * L * 0.86),
		Vector2(L * 0.18 + L * 0.82, 0.0),
		Vector2(L * 0.18 + cos(PI * 0.40) * L * 0.82, sin(PI * 0.40) * L * 0.86),
	]), Color(edge.r, edge.g, edge.b, 0.95), 1.6, true)
	_draw_star_fx(pal, Vector2(L * 0.98, 0.0), Vector2(L * 0.6, -L * 0.5), Vector2(L * 0.6, L * 0.5))

# ---------------- 锤（长柄 + 方锤头） ----------------
func _draw_hammer() -> void:
	var pal := _palette()
	var L := tip_len
	var edge: Color = pal["edge"]
	_draw_shaft(pal, L * 0.82, 2.8)
	# 方锤头（器首端，带上下包边）
	var hw := L * 0.30
	_fill_outlined(PackedVector2Array([
		Vector2(L * 1.0, -hw), Vector2(L * 1.0, hw), Vector2(L * 0.42, hw * 1.05),
		Vector2(L * 0.42, -hw * 1.05),
	]), pal["light"].darkened(0.05))
	draw_line(Vector2(L * 0.94, -hw), Vector2(L * 0.94, hw), edge.darkened(0.15), 1.6, true)
	draw_line(Vector2(L * 0.48, -hw * 1.02), Vector2(L * 0.48, hw * 1.02), pal["dark"], 1.4, true)
	_draw_core_fx(pal, Vector2(L * 0.7, 0.0), 1.2)

# ---------------- 锏（六棱重锏 + 节环 + 锏首） ----------------
func _draw_mace() -> void:
	var pal := _palette()
	var L := tip_len
	var w := L * 0.24
	var edge: Color = pal["edge"]
	# 六棱锏身：器首略细、中段最宽
	_fill_outlined(PackedVector2Array([
		Vector2(L * 0.94, -w * 0.62), Vector2(L * 0.94, w * 0.62),
		Vector2(-L * 0.72, w), Vector2(-L * 0.80, 0.0), Vector2(-L * 0.72, -w),
	]), pal["light"].darkened(0.06))
	# 棱线
	draw_line(Vector2(L * 0.90, 0.0), Vector2(-L * 0.74, 0.0), Color(edge.r, edge.g, edge.b, 0.7), 1.2, true)
	# 节环两道
	for i in range(2):
		var x := L * (0.5 - float(i) * 0.55)
		draw_line(Vector2(x, -w * 0.9), Vector2(x, w * 0.9), pal["dark"], 1.6, true)
	# 锏首（柄端圆环）
	AdaptiveDraw.arc(self, Vector2(-L * 0.92, 0.0), L * 0.10, 0.0, TAU, edge, 1.6, true)
	_draw_core_fx(pal, Vector2(L * 0.45, 0.0), 1.3)

# ---------------- 尺（长条金尺 + 刻度） ----------------
func _draw_ruler() -> void:
	var pal := _palette()
	var L := tip_len
	var hw := L * 0.20
	var ink := _ink(pal)
	var edge: Color = pal["edge"]
	_fill_outlined(PackedVector2Array([
		Vector2(L, -hw), Vector2(L, hw), Vector2(-L * 0.90, hw * 0.92),
		Vector2(-L * 0.94, 0.0), Vector2(-L * 0.90, -hw * 0.92),
	]), pal["light"])
	# 刻度（5 道）
	for i in range(5):
		var t := float(i) / 4.0
		var x := lerpf(L * 0.84, -L * 0.78, t)
		var len := hw * (0.85 if i % 2 == 0 else 0.5)
		draw_line(Vector2(x, -len), Vector2(x, len), ink, 0.9, true)
	draw_line(Vector2(L * 0.96, 0.0), Vector2(-L * 0.86, 0.0), Color(edge.r, edge.g, edge.b, 0.55), 0.8, true)
	_draw_core_fx(pal, Vector2(-L * 0.2, 0.0), 1.2)

# ---------------- 剪（双刃交叉 + 指环） ----------------
func _draw_shears() -> void:
	var pal := _palette()
	var L := tip_len
	var edge: Color = pal["edge"]
	# 两片剪刃：自中心向 +X 张开成 V
	for s in [-1.0, 1.0]:
		_fill_outlined(PackedVector2Array([
			Vector2(L, s * L * 0.30), Vector2(L * 0.94, s * L * 0.12),
			Vector2(-L * 0.12, s * L * 0.02), Vector2(-L * 0.12, s * L * 0.16),
		]), pal["light"])
		# 刃口
		draw_line(Vector2(L, s * L * 0.30), Vector2(-L * 0.08, s * L * 0.09),
			Color(edge.r, edge.g, edge.b, 0.9), 1.2, true)
		# 指环（固定 24 段：小半径下自适应段数会把圆画成六边形）
		draw_arc(Vector2(-L * 0.62, s * L * 0.28), L * 0.20, 0.0, TAU, 24, edge.darkened(0.15), 1.8, true)
	# 转轴
	AdaptiveDraw.circle(self, Vector2(-L * 0.14, 0.0), 1.8, Color(0.06, 0.06, 0.08))
	AdaptiveDraw.circle(self, Vector2(-L * 0.14, 0.0), 1.0, edge)
	_draw_star_fx(pal, Vector2(L * 0.96, L * 0.22), Vector2(L * 0.6, L * 0.1), Vector2(L * 0.2, 0.0))

# ---------------- 梭（两头尖的流线梭） ----------------
func _draw_shuttle() -> void:
	var pal := _palette()
	var L := tip_len
	var w := L * 0.30
	var edge: Color = pal["edge"]
	_fill_outlined(PackedVector2Array([
		Vector2(L, 0.0), Vector2(L * 0.34, -w), Vector2(-L * 0.55, -w * 0.72),
		Vector2(-L * 0.86, 0.0), Vector2(-L * 0.55, w * 0.72), Vector2(L * 0.34, w),
	]), pal["light"])
	# 梭心线槽
	draw_line(Vector2(L * 0.72, 0.0), Vector2(-L * 0.62, 0.0), Color(edge.r, edge.g, edge.b, 0.75), 1.2, true)
	draw_line(Vector2(L * 0.30, -w * 0.55), Vector2(-L * 0.40, -w * 0.4), pal["dark"], 0.9, true)
	draw_line(Vector2(L * 0.30, w * 0.55), Vector2(-L * 0.40, w * 0.4), pal["dark"], 0.9, true)
	_draw_star_fx(pal, Vector2(L, 0.0), Vector2(L * 0.5, 0.0), Vector2(-L * 0.2, 0.0))

# ---------------- 钉（方帽长钉） ----------------
func _draw_nail() -> void:
	var pal := _palette()
	var L := tip_len
	var w := clampf(L * 0.16, 2.2, 3.4)
	var edge: Color = pal["edge"]
	# 钉身（向 +X 收尖）
	_fill_outlined(PackedVector2Array([
		Vector2(L * 0.86, 0.0), Vector2(L * 0.36, -w), Vector2(-L * 0.52, -w * 0.86),
		Vector2(-L * 0.58, 0.0), Vector2(-L * 0.52, w * 0.86), Vector2(L * 0.36, w),
	]), pal["light"])
	# 方帽（尾端）
	_fill_outlined(PackedVector2Array([
		Vector2(-L * 0.50, -w * 2.1), Vector2(-L * 0.50, w * 2.1),
		Vector2(-L * 0.78, w * 1.9), Vector2(-L * 0.78, -w * 1.9),
	]), pal["dark"])
	draw_line(Vector2(L * 0.70, 0.0), Vector2(-L * 0.40, 0.0), Color(edge.r, edge.g, edge.b, 0.8), 0.9, true)
	_draw_star_fx(pal, Vector2(L * 0.86, 0.0), Vector2(L * 0.5, 0.0), Vector2(L * 0.05, 0.0))

# ---------------- 针（成束细针） ----------------
func _draw_needles() -> void:
	var pal := _palette()
	var L := tip_len
	var edge: Color = pal["edge"]
	# 三根细针并排（上/中/下），针尖朝 +X
	for i in range(3):
		var off := (float(i) - 1.0) * L * 0.20
		draw_line(Vector2(-L * 0.62, off), Vector2(L, off * 0.35),
			Color(0.06, 0.06, 0.08), 2.2, true)
		draw_line(Vector2(-L * 0.62, off), Vector2(L, off * 0.35), pal["light"], 1.1, true)
		AdaptiveDraw.circle(self, Vector2(L, off * 0.35), 0.8, edge)
	# 束口（尾端缠绳）
	draw_line(Vector2(-L * 0.62, -L * 0.26), Vector2(-L * 0.62, L * 0.26), pal["handle"], 2.6, true)
	_draw_star_fx(pal, Vector2(L * 0.9, 0.0), Vector2(L * 0.4, 0.0), Vector2(0.0, 0.0))

# ---------------- 弹弓（Y 形弓架 + 皮兜） ----------------
func _draw_sling() -> void:
	var pal := _palette()
	var L := tip_len
	var edge: Color = pal["edge"]
	# 弓架：柄 + 两根分叉
	var frame: Color = pal["dark"].lerp(pal["light"], 0.35)
	draw_line(Vector2(-L * 0.80, 0.0), Vector2(-L * 0.10, 0.0), Color(0.06, 0.06, 0.08), 4.4, true)
	draw_line(Vector2(-L * 0.80, 0.0), Vector2(-L * 0.10, 0.0), frame, 2.8, true)
	for s in [-1.0, 1.0]:
		draw_line(Vector2(-L * 0.10, 0.0), Vector2(L * 0.72, s * L * 0.46), Color(0.06, 0.06, 0.08), 3.6, true)
		draw_line(Vector2(-L * 0.10, 0.0), Vector2(L * 0.72, s * L * 0.46), frame, 2.1, true)
	# 皮兜（两叉之间的弧）
	AdaptiveDraw.arc(self, Vector2(L * 0.30, 0.0), L * 0.52, -PI * 0.36, PI * 0.36,
		Color(edge.r, edge.g, edge.b, 0.85), 1.4, true)
	_draw_core_fx(pal, Vector2(L * 0.30, 0.0), 1.3)

# ---------------- 葫芦（双腹葫芦 + 口塞） ----------------
func _draw_calabash() -> void:
	var pal := _palette()
	var L := tip_len
	var edge: Color = pal["edge"]
	# 葫芦整体轮廓（一笔画成：小腹 → 收腰 → 大腹 → 尾端收口）
	# 用「平滑插值 + 足够采样」保证侧影是连续曲线，否则低采样会读成两个多边形拼一起。
	const SEG := 40
	var pts := PackedVector2Array()
	for i in range(SEG + 1):
		pts.append(Vector2(_calabash_x(float(i) / float(SEG), L), -_calabash_w(float(i) / float(SEG), L)))
	for i in range(SEG + 1):
		var t := 1.0 - float(i) / float(SEG)
		pts.append(Vector2(_calabash_x(t, L), _calabash_w(t, L)))
	_fill_outlined(pts, pal["light"].darkened(0.05))
	# 收腰箍
	draw_line(Vector2(L * 0.12, -L * 0.13), Vector2(L * 0.12, L * 0.13), edge.darkened(0.2), 2.0, true)
	# 口塞（器首）
	draw_line(Vector2(L * 0.74, -L * 0.10), Vector2(L * 0.74, L * 0.10), pal["handle"], 2.8, true)
	# 大腹灵纹弧
	draw_arc(Vector2(-L * 0.30, 0.0), L * 0.30, -PI * 0.45, PI * 0.45, 20,
		Color(edge.r, edge.g, edge.b, 0.5), 1.0, true)
	_draw_core_fx(pal, Vector2(-L * 0.30, 0.0), 1.6)

## 葫芦包络：t=0 器口 → t=1 尾端。半径按 小腹/收腰/大腹/收口 四段平滑过渡。
func _calabash_w(t: float, L: float) -> float:
	if t < 0.26:
		var k := t / 0.26
		return lerpf(L * 0.17, L * 0.31, sin(k * PI * 0.5))
	if t < 0.44:
		var k := (t - 0.26) / 0.18
		return lerpf(L * 0.31, L * 0.14, sin(k * PI * 0.5))
	if t < 0.86:
		var k := (t - 0.44) / 0.42
		return lerpf(L * 0.14, L * 0.52, sin(k * PI * 0.5))
	var k := (t - 0.86) / 0.14
	return lerpf(L * 0.52, L * 0.02, k * k)

func _calabash_x(t: float, L: float) -> float:
	return lerpf(L * 0.72, -L * 0.86, t)

# ---------------- 笛（竹笛 + 指孔 + 流苏） ----------------
func _draw_flute() -> void:
	var pal := _palette()
	var L := tip_len
	var hw := L * 0.14
	var ink := _ink(pal)
	var edge: Color = pal["edge"]
	_fill_outlined(PackedVector2Array([
		Vector2(L, -hw), Vector2(L, hw), Vector2(-L * 0.92, hw), Vector2(-L * 0.92, -hw),
	]), pal["light"].darkened(0.08))
	# 指孔 4 个
	for i in range(4):
		var x := L * (0.5 - float(i) * 0.28)
		AdaptiveDraw.circle(self, Vector2(x, 0.0), hw * 0.42, ink)
	# 端箍
	draw_line(Vector2(L * 0.94, -hw), Vector2(L * 0.94, hw), edge.darkened(0.2), 1.6, true)
	draw_line(Vector2(-L * 0.86, -hw), Vector2(-L * 0.86, hw), edge.darkened(0.2), 1.6, true)
	# 流苏
	draw_line(Vector2(-L * 0.92, 0.0), Vector2(-L * 1.10, 0.0), edge, 1.2, true)
	draw_line(Vector2(-L * 1.02, 0.0), Vector2(-L * 1.08, L * 0.18), Color(edge.r, edge.g, edge.b, 0.6), 1.0, true)
	_draw_core_fx(pal, Vector2(L * 0.1, 0.0), 1.2)

# ---------------- 镜（圆镜 + 边框 + 镜柄） ----------------
func _draw_mirror() -> void:
	var pal := _palette()
	var L := tip_len
	var r := L * 0.62
	var edge: Color = pal["edge"]
	# 镜面（暗底 + 亮面）
	AdaptiveDraw.circle(self, Vector2.ZERO, r, Color(0.06, 0.07, 0.10, 0.85))
	AdaptiveDraw.circle(self, Vector2.ZERO, r * 0.90, pal["light"])
	# 镜框
	AdaptiveDraw.arc(self, Vector2.ZERO, r * 0.95, 0.0, TAU, edge.darkened(0.1), 2.0, true)
	# 镜面高光斜带
	draw_line(Vector2(-r * 0.5, r * 0.35), Vector2(r * 0.3, -r * 0.5),
		Color(1.0, 1.0, 1.0, 0.45), 1.6, true)
	# 镜柄（朝尾端）
	draw_line(Vector2(-r * 0.9, 0.0), Vector2(-L * 0.98, 0.0), Color(0.06, 0.06, 0.08), 3.2, true)
	draw_line(Vector2(-r * 0.9, 0.0), Vector2(-L * 0.98, 0.0), pal["handle"], 2.0, true)
	_draw_core_fx(pal, Vector2.ZERO, 1.6)

# ---------------- 珠（多棱宝珠 + 内核） ----------------
func _draw_bead() -> void:
	var pal := _palette()
	var L := tip_len
	var r := L * 0.62
	var edge: Color = pal["edge"]
	# 六棱珠体
	var pts := PackedVector2Array()
	for i in range(6):
		var a := TAU * float(i) / 6.0 + PI / 6.0
		pts.append(Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, Color(0.06, 0.07, 0.10, 0.85))
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(p * 0.90)
	draw_colored_polygon(inner, pal["light"].darkened(0.05))
	# 棱线
	for i in range(6):
		draw_line(Vector2.ZERO, pts[i] * 0.9, Color(edge.r, edge.g, edge.b, 0.55), 0.9, true)
	# 珠心
	_draw_core_fx(pal, Vector2.ZERO, 1.8)

# ---------------- 锥（长锥 + 箍环） ----------------
func _draw_awl() -> void:
	var pal := _palette()
	var L := tip_len
	var w := clampf(L * 0.20, 3.0, 5.0)
	var edge: Color = pal["edge"]
	# 锥身：尾端宽、器首收成尖
	_fill_outlined(PackedVector2Array([
		Vector2(L, 0.0), Vector2(L * 0.18, -w), Vector2(-L * 0.72, -w * 0.72),
		Vector2(-L * 0.80, 0.0), Vector2(-L * 0.72, w * 0.72), Vector2(L * 0.18, w),
	]), pal["light"])
	# 箍环两道
	for i in range(2):
		var x := -L * (0.10 + float(i) * 0.34)
		draw_line(Vector2(x, -w * 0.92), Vector2(x, w * 0.92), pal["dark"], 1.8, true)
	draw_line(Vector2(L * 0.9, 0.0), Vector2(-L * 0.6, 0.0), Color(edge.r, edge.g, edge.b, 0.75), 1.0, true)
	_draw_star_fx(pal, Vector2(L, 0.0), Vector2(L * 0.5, 0.0), Vector2(-L * 0.1, 0.0))

# ---------------- 手里剑（四芒旋刃 + 月牙磨刃 + 中心透孔） ----------------
func _draw_shuriken() -> void:
	# 兜底旧画法，正常分发已被 WeaponShapeLibrary 接管
	var pal := _palette()
	var L := tip_len
	var r_hole := L * 0.20
	AdaptiveDraw.circle(self, Vector2.ZERO, L, pal["dark"])
	AdaptiveDraw.circle(self, Vector2.ZERO, r_hole, Color(0.06, 0.07, 0.10, 0.95))
	_draw_star_fx(pal, Vector2(L, 0.0), Vector2(L * 0.6, 0.0), Vector2(r_hole * 1.5, 0.0))


