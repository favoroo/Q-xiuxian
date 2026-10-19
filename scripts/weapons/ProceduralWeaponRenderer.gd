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
## 逐批把大类补齐（本批：剑/刀/匕首）。

enum WeaponShape { SWORD, SABER, DAGGER, GENERIC }

@export var shape: WeaponShape = WeaponShape.GENERIC
@export var element: String = "metal"
@export var tip_len: float = 28.0
@export var star: int = 1

func configure(p_shape: WeaponShape, p_element: String, p_tip_len: float, p_star: int) -> void:
	shape = p_shape
	element = p_element
	tip_len = maxf(p_tip_len, 8.0)
	star = clampi(p_star, 1, 3)
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
	return WeaponShape.GENERIC

## 本批是否已实现该器形（false ⇒ 调用方继续显示旧贴图，保证逐批灰度不破现状）
func is_implemented() -> bool:
	return shape != WeaponShape.GENERIC

## 五行配色：亮面 / 暗面 / 刃口流光 / HDR 起辉 / 柄色
func _palette() -> Dictionary:
	match element:
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
	match shape:
		WeaponShape.SWORD:
			_draw_sword()
		WeaponShape.SABER:
			_draw_saber()
		WeaponShape.DAGGER:
			_draw_dagger()

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
func _draw_star_fx(pal: Dictionary, tip: Vector2, ridge_a: Vector2, ridge_b: Vector2) -> void:
	var r := 0.85 + 0.22 * float(star - 1)
	AdaptiveDraw.circle(self, tip, r * 1.25, Color(pal["hdr"].r, pal["hdr"].g, pal["hdr"].b, 0.28))
	AdaptiveDraw.circle(self, tip, r, pal["hdr"])
	AdaptiveDraw.circle(self, tip, r * 0.5, Color(1.0, 1.0, 1.0, 0.95))
	if star >= 2:
		var mid := ridge_b.lerp(ridge_a, 0.55)
		AdaptiveDraw.circle(self, mid, 1.0, Color(pal["edge"].r, pal["edge"].g, pal["edge"].b, 0.9))
		AdaptiveDraw.circle(self, ridge_b.lerp(ridge_a, 0.3), 0.9, Color(pal["edge"].r, pal["edge"].g, pal["edge"].b, 0.75))
	if star >= 3:
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
