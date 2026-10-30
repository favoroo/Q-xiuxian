extends RefCounted

## 炫彩族（虹霓）：墨底油膜幻彩 —— 缘边/眼瞳/武器流光沿色环流转。
##
## 2026-10-22 原实现住在 HollowKnightCultivatorRenderer 的 4 条硬编码分支里；
## 2026-10-30 皮肤系列化重构时原样搬入本模块，行为与参数一字未改（仅改成静态接口）。
##
## 三条铁律（搬移时保留，别"顺手修"）：
## ① 袍身若参与色相流转会在大面积上跑成彩袍/发棕 —— 必须用 locked 名单钉死 cloak_outer/inner，
##    虹彩只交给 sheen 与缘边。
## ② 非炫彩皮肤必须在宿主 _sync_config 里清空 _fx 并复位基准色，否则同一渲染器实例换皮肤会串色。
## ③ _cloak_gradient 的 film_h 直接吃 base.h（已含时间相位），再加 phase 会让转速翻倍。

const SkinFxCommon = preload("res://scripts/entities/procedural_cultivator/skin_fx/SkinFxCommon.gd")

## 族默认参数：SkinData 主题只需写 kind + 想偏离默认的键
static func defaults() -> Dictionary:
	return {
		"cycle": 7.0,
		"hue_offsets": {
			"cloak_outer": 0.0, "cloak_inner": 0.0, "cloak_edge": 0.0,
			"eye_glow": 0.06, "eye_core": 0.02,
			"weapon_main": 0.22, "weapon_shadow": 0.16, "weapon_accent": 0.30,
			"slash_arc": 0.10, "gold": 0.34, "jade": 0.12, "tassel": 0.40,
		},
		"locked": ["cloak_outer", "cloak_inner"],
		"sheen": 0.075,
		"sheen_dx": 0.010,
		"sheen_dy": 0.015,
		"rim_glow": 0.50,
		"rim_sat": 0.80,
		"rim_spread": 0.055,
		"comet_half": 3,
		"comet_speed": 0.22,
	}

## 重绘前重算全部缓存色（S/V 取自 _fx_base 快照）
static func on_frame(h, p: Dictionary) -> void:
	var phase := SkinFxCommon.phase_of(h, p)
	var offs: Dictionary = p.get("hue_offsets", {})
	var locked: Array = p.get("locked", [])
	var base: Dictionary = h._fx_base
	h.col_cloak_outer = base["cloak_outer"] if locked.has("cloak_outer") \
			else SkinFxCommon.hue_shift(base["cloak_outer"], phase, float(offs.get("cloak_outer", 0.0)))
	h.col_cloak_inner = base["cloak_inner"] if locked.has("cloak_inner") \
			else SkinFxCommon.hue_shift(base["cloak_inner"], phase, float(offs.get("cloak_inner", 0.0)))
	h.col_cloak_edge = SkinFxCommon.hue_shift(base["cloak_edge"], phase, float(offs.get("cloak_edge", 0.0)))
	h.col_eye_glow = SkinFxCommon.hue_shift(base["eye_glow"], phase, float(offs.get("eye_glow", 0.0)))
	h.col_eye_core = SkinFxCommon.hue_shift(base["eye_core"], phase, float(offs.get("eye_core", 0.0)), 2.2)
	h.col_weapon_main = SkinFxCommon.hue_shift(base["weapon_main"], phase, float(offs.get("weapon_main", 0.0)), 1.6)
	h.col_weapon_shadow = SkinFxCommon.hue_shift(base["weapon_shadow"], phase, float(offs.get("weapon_shadow", 0.0)))
	h.col_weapon_accent = SkinFxCommon.hue_shift(base["weapon_accent"], phase, float(offs.get("weapon_accent", 0.0)))
	h.col_gold = SkinFxCommon.hue_shift(base["gold"], phase, float(offs.get("gold", 0.0)))
	h.col_jade = SkinFxCommon.hue_shift(base["jade"], phase, float(offs.get("jade", 0.0)))
	h.col_tassel_red = SkinFxCommon.hue_shift(base["tassel"], phase, float(offs.get("tassel", 0.0)))
	h.col_slash_arc = SkinFxCommon.hue_shift(base["slash_arc"], phase, float(offs.get("slash_arc", 0.0)), 1.4)
	h.col_slash_glow = h.col_cloak_edge

## 袍面油膜虹彩：色相随衣褶坐标斜向偏移 + 明暗带交替，强度低以保黑底
static func cloak_sheen(h, base: Color, pt: Vector2, p: Dictionary) -> Color:
	var phase := SkinFxCommon.phase_of(h, p)
	var sheen := float(p.get("sheen", 0.075))
	var dx := float(p.get("sheen_dx", 0.010))
	var dy := float(p.get("sheen_dy", 0.015))
	# 纵向伪光照由宿主 _cloak_gradient 负责，这里只叠油膜
	var film_h := fposmod(base.h + phase + pt.x * dx + pt.y * dy, 1.0)
	var band := 0.5 + 0.5 * sin((pt.x * dx + pt.y * dy + phase) * TAU * 2.0)
	var film := Color.from_hsv(film_h, clampf(0.55 + 0.30 * band, 0.0, 1.0),
			clampf(base.v + 0.16 * band, 0.0, 1.0), base.a)
	return base.lerp(film, sheen * band)

## 缘边常驻彩虹描边（逐顶点色相环绕）+ 沿轮廓游走的棱镜光段，无需技能激活
static func draw_rim(h, pts: PackedVector2Array, base_w: float, p: Dictionary) -> void:
	var cn := pts.size()
	if cn < 2:
		return
	var phase := SkinFxCommon.phase_of(h, p)
	var rim_glow := float(p.get("rim_glow", 0.50))
	var rim_sat := float(p.get("rim_sat", 0.80))
	var edge_base: Color = h._fx_base["cloak_edge"]
	var edge_h := edge_base.h

	var rim_cols := SkinFxCommon.rim_rainbow_cols(pts, edge_h, phase, rim_sat, 1.0, rim_glow)
	h.draw_polyline_colors(pts, rim_cols, base_w + 0.5, true)

	var comet_center := int(fposmod(h._time * float(p.get("comet_speed", 0.22))
			+ h._idle_phase * 0.05, 1.0) * float(cn))
	var seg := SkinFxCommon.comet_segments(pts, comet_center, int(p.get("comet_half", 3)),
			edge_h, phase + 0.5, float(p.get("rim_spread", 0.055)), 0.90, 1.0, rim_glow * 0.9)
	var comet_pts: PackedVector2Array = seg[0]
	var comet_cols: PackedColorArray = seg[1]
	if comet_pts.size() >= 2:
		h.draw_polyline_colors(comet_pts, comet_cols, base_w + 1.2, true)

## 炫彩族不加常驻粒子（原实现无）
static func draw_motes(_h, _float_y: float, _p: Dictionary) -> void:
	pass

## 收窄眼部柔光半径并压 alpha，让骨白面壳保持干净，只留眼窝虹彩
static func eye_glow_adjust(_h, radius: float, col: Color, _p: Dictionary) -> Dictionary:
	return {
		"radius": radius * 0.60,
		"color": Color(col.r, col.g, col.b, col.a * 0.78),
	}
