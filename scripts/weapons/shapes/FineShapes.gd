extends RefCounted

## 精细小件族矢量画法：针 NEEDLES / 钉 NAIL / 梭 SHUTTLE / 弹弓 SLING / 葫芦 CALABASH / 笛 FLUTE / 扇 FAN / 锥 AWL
##
## 宿主 ProceduralWeaponRenderer._draw() 经 WeaponShapeLibrary 分发到此。
## 坐标契约与宿主一致：画布像素空间沿 +X 绘制，器尖/器口/最远针尖精确落在 (r.tip_len, 0)；
## 屏上实机尺度约 26px（节点 scale 0.55），细节必须在该尺度可读。
## 可用宿主能力：r._palette() / r._fill_outlined() / r._draw_star_fx() / r._paper() / r._ink()、
## r.tip_len / r.star / r.element / r.upright、AdaptiveDraw.circle(r, ...) / AdaptiveDraw.arc(r, ...)。
##
## 画风：空洞冷冽国风 —— 骨白亮面 / 深色暗面 / 五行荧光 / 粗暗描边 / 纯平矢量色块，禁渐变禁柔光。
## 扇形展开、针束角度一律用数学展开（极坐标），不使用 draw_set_transform。
## 中心针/器口一律用「参数式钉死」：base + dir*(L - base.x)/dir.x ≡ (L,0)，浮点零误差。
##
## 返回 true = 本模块接管该器形；false = 回退宿主旧画法。

## 通用暗描边色（与宿主 _fill_outlined 外圈同色系）
const _INK := Color(0.06, 0.07, 0.10, 0.90)
## ★4 极境霓虹取色：与野兽派族模块同一处真话（BrutalistCommon 的 NEON_CYAN_HDR / NEON_VIOLET）
const BC = preload("res://scripts/weapons/shapes/BrutalistCommon.gd")
## 玄铁匣身色（机括匣铁胎：比夜地亮两档，避免融进背景）
const _IRON := Color(0.30, 0.33, 0.42)
## 骨白（针身/钉身等冷兵亮面，不随五行走）
const _BONE := Color(0.90, 0.92, 0.88)
## 冰棱亮色 / 暗色（水行冰针专用，比 pal 更冷更透）
const _ICE_LT := Color(0.80, 0.95, 1.0)
const _ICE_DK := Color(0.42, 0.70, 0.95)

static func draw_shape(shape: int, r: ProceduralWeaponRenderer) -> bool:
	match shape:
		ProceduralWeaponRenderer.WeaponShape.NEEDLES:
			if r.element == "water":
				_draw_ice_needles(r)
			else:
				_draw_needle_box(r)
			return true
		ProceduralWeaponRenderer.WeaponShape.NAIL:
			_draw_nail(r)
			return true
		ProceduralWeaponRenderer.WeaponShape.SHUTTLE:
			_draw_shuttle(r)
			return true
		ProceduralWeaponRenderer.WeaponShape.SLING:
			_draw_sling(r)
			return true
		ProceduralWeaponRenderer.WeaponShape.CALABASH:
			_draw_calabash(r)
			return true
		ProceduralWeaponRenderer.WeaponShape.FLUTE:
			_draw_flute(r)
			return true
		ProceduralWeaponRenderer.WeaponShape.FAN:
			_draw_fan(r)
			return true
		ProceduralWeaponRenderer.WeaponShape.AWL:
			_draw_awl(r)
			return true
		ProceduralWeaponRenderer.WeaponShape.SHURIKEN:
			_draw_shuriken(r)
			return true
		_:
			return false

# ---------------- 通用小构件 ----------------

## 单根细针：粗暗描边 + 骨白针身 + 针尖寒光点。
static func _needle_line(r: ProceduralWeaponRenderer, base: Vector2, tip: Vector2,
		width: float, shaft: Color, glint: Color) -> void:
	r.draw_line(base, tip, _INK, width + 0.9, true)
	r.draw_line(base, tip, shaft, width, true)
	AdaptiveDraw.circle(r, tip, maxf(width * 0.8, 1.0), glint)
	AdaptiveDraw.circle(r, tip, maxf(width * 0.35, 0.5), Color(1.0, 1.0, 1.0, 0.95))

## 一枚冰晶棱针：细长六棱钻（暗底 + 上亮下暗棱面 + 中脊高光 + 针尖寒芒）。
## dir 单位方向，len 针长，hw 最大半宽（靠根 1/3 处）。
static func _ice_prism(r: ProceduralWeaponRenderer, base: Vector2, dir: Vector2,
		len: float, hw: float, edge: Color) -> void:
	var perp := Vector2(-dir.y, dir.x)
	var sh := base + dir * len * 0.32
	var body := PackedVector2Array([
		base + perp * hw * 0.5, sh + perp * hw, base + dir * len, sh - perp * hw, base - perp * hw * 0.5,
	])
	r.draw_colored_polygon(body, _INK)
	r.draw_colored_polygon(PackedVector2Array([
		base + perp * hw * 0.5, sh + perp * hw, base + dir * len, sh,
	]), _ICE_LT)
	r.draw_colored_polygon(PackedVector2Array([
		sh, base + dir * len, sh - perp * hw, base - perp * hw * 0.5,
	]), _ICE_DK)
	r.draw_line(sh, base + dir * len, Color(1.0, 1.0, 1.0, 0.85), 0.8, true)
	r.draw_line(base + perp * hw * 0.5, sh + perp * hw, Color(edge.r, edge.g, edge.b, 0.55), 0.7, true)
	AdaptiveDraw.circle(r, base + dir * len, 1.0, Color(1.0, 1.0, 1.0, 0.95))

## 把方向 dir 的针尖钉死到器尖 (L,0)：从 base 出发沿 dir 解出恰好的长度。
static func _pin_to_tip(base: Vector2, dir: Vector2, L: float) -> Vector2:
	return base + dir * ((L - base.x) / dir.x)

## 平滑采样弧（替代 AdaptiveDraw.arc：小半径自适应段数太少，画出来是六边形/菱形）。
static func _arc(r: ProceduralWeaponRenderer, c: Vector2, rad: float,
		a0: float, a1: float, col: Color, w: float) -> void:
	var seg := maxi(10, int(rad * 2.0))
	var pts := PackedVector2Array()
	for i in range(seg + 1):
		var a := lerpf(a0, a1, float(i) / float(seg))
		pts.append(c + Vector2(cos(a), sin(a)) * rad)
	r.draw_polyline(pts, col, w, true)

# ---------------- 暴雨针：玄铁机括针匣 + 扇形针束（金） ----------------
## 参考 weapon_needle_pouch：尾端斜切玄铁机括小匣（铁胎 + 金棱线 + 匣口朝 +X 大张、掀盖露针排），
## 匣口扇形暴射 14 根长短参差细针（骨白针身 + 金寒光针尖），中心针精确顶到 (L,0)。
static func _draw_needle_box(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = r._palette()
	var L: float = r.tip_len
	var edge: Color = pal["edge"]        # 金：匣棱线 + 针尖寒芒
	var shaft := _BONE                   # 骨白针身（冷兵定色，不随五行走）
	var mouth_x := -L * 0.34             # 匣口所在截面
	var h := L * 0.24                    # 匣半高

	# ---- 机括匣（先画，压在针束根部之下）----
	var box := PackedVector2Array([
		Vector2(-L * 0.92, -h * 0.82),   # 尾上
		Vector2(mouth_x, -h),            # 口上唇
		Vector2(mouth_x, h),             # 口下唇
		Vector2(-L * 0.92, h * 0.88),    # 尾下
		Vector2(-L * 0.98, 0.0),         # 尾端斜切尖
	])
	r.draw_colored_polygon(box, _INK)
	r.draw_colored_polygon(PackedVector2Array([
		box[0] * 0.96, box[1] * 0.97, box[2] * 0.97, box[3] * 0.96, box[4] * 0.97,
	]), _IRON)
	# 匣面斜向铁脊高光（纯平一条，破掉大平板）
	r.draw_line(Vector2(-L * 0.88, -h * 0.5), Vector2(mouth_x - L * 0.04, -h * 0.62),
		Color(1.0, 1.0, 1.0, 0.18), 1.4, true)
	# 匣口金棱（大张的口沿）
	r.draw_line(Vector2(mouth_x, -h), Vector2(mouth_x, h), edge, 1.8, true)
	# 口内暗膛 + 待发针排（匣口里能看见一排针尾，强化「机括连发」）
	r.draw_colored_polygon(PackedVector2Array([
		Vector2(mouth_x, -h * 0.78), Vector2(mouth_x - L * 0.10, -h * 0.55),
		Vector2(mouth_x - L * 0.10, h * 0.55), Vector2(mouth_x, h * 0.78),
	]), Color(0.03, 0.03, 0.05, 0.95))
	for i in range(5):
		var ry := lerpf(-h * 0.5, h * 0.5, float(i) / 4.0)
		r.draw_line(Vector2(mouth_x - L * 0.09, ry), Vector2(mouth_x - L * 0.01, ry),
			Color(shaft.r, shaft.g, shaft.b, 0.8), 0.8, true)
	# 掀开的匣盖（自口上唇向前上方斜挑的实心薄铁板：铁面 + 金边 + 内侧亮线）
	var lid := PackedVector2Array([
		Vector2(mouth_x - L * 0.02, -h * 0.98), Vector2(-L * 0.02, -L * 0.60),
		Vector2(L * 0.06, -L * 0.46), Vector2(mouth_x + L * 0.06, -h * 0.70),
	])
	r.draw_colored_polygon(lid, _IRON.darkened(0.10))
	r.draw_polyline(lid + PackedVector2Array([lid[0]]), Color(edge.r, edge.g, edge.b, 0.85), 1.0, true)
	r.draw_line(Vector2(mouth_x + L * 0.02, -h * 0.80), Vector2(L * 0.02, -L * 0.52),
		Color(1.0, 1.0, 1.0, 0.25), 1.0, true)
	# 机括齿轮 + 铆钉
	_arc(r, Vector2(-L * 0.58, h * 0.10), L * 0.085, 0.0, TAU, Color(edge.r, edge.g, edge.b, 0.85), 1.2)
	AdaptiveDraw.circle(r, Vector2(-L * 0.58, h * 0.10), 0.9, edge)
	for rx in [-L * 0.84, -L * 0.44]:
		AdaptiveDraw.circle(r, Vector2(rx, h * 0.60), 0.7, Color(edge.r, edge.g, edge.b, 0.6))

	# ---- 扇形针束（14 根，长短参差，中心针钉死 (L,0)）----
	const N := 14
	const SPREAD := 0.44
	for i in range(N):
		var u := float(i) / float(N - 1)
		var a := lerpf(-SPREAD, SPREAD, u)
		var dir := Vector2(cos(a), sin(a))
		var base := Vector2(mouth_x, lerpf(-h * 0.72, h * 0.72, u))
		var tip: Vector2
		if i * 2 == N - 2 or i * 2 == N - 1:
			tip = _pin_to_tip(base, dir, L)                 # 中央两枚钉死满长
		else:
			var centerf := 1.0 - absf(2.0 * u - 1.0)
			var jit := 0.86 + 0.10 * cos(float(i) * 2.4)    # 参差抖动（确定性）
			var rad := (L - mouth_x) * (0.60 + 0.40 * centerf) * jit
			tip = base + dir * rad
		var wdt := lerpf(0.85, 1.15, 1.0 - absf(2.0 * u - 1.0))   # 中心针略粗
		_needle_line(r, base, tip, wdt, shaft, edge)

	r._draw_star_fx(pal, Vector2(L, 0.0), Vector2(L * 0.55, 0.0), Vector2(mouth_x, 0.0))

# ---------------- 冰针：5 根冰晶棱针束（水） ----------------
## 参考 weapon_ice_needle：无数理匣，纯冰晶棱针扇形射出，中心针钉死 (L,0)。
static func _draw_ice_needles(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = r._palette()
	var edge: Color = pal["edge"]
	var L: float = r.tip_len
	var mouth_x := -L * 0.30

	# 寒气外晕（纯平低透明的冰蓝扇面）
	r.draw_colored_polygon(PackedVector2Array([
		Vector2(mouth_x, 0.0), Vector2(L * 0.86, -L * 0.34),
		Vector2(L, 0.0), Vector2(L * 0.86, L * 0.34),
	]), Color(edge.r, edge.g, edge.b, 0.12))

	const N := 5
	const SPREAD := 0.34
	for i in range(N):
		var u := float(i) / float(N - 1)
		var a := lerpf(-SPREAD, SPREAD, u)
		var dir := Vector2(cos(a), sin(a))
		var base := Vector2(mouth_x, lerpf(-L * 0.07, L * 0.07, u))
		var tip: Vector2
		if i == 2:
			tip = _pin_to_tip(base, dir, L)                 # 中心针钉死满长
		else:
			var centerf := 1.0 - absf(2.0 * u - 1.0)
			var rad := (L - mouth_x) * (0.78 + 0.16 * centerf) * (0.92 + 0.06 * float(i % 2))
			tip = base + dir * rad
		_ice_prism(r, base, (tip - base).normalized(), tip.distance_to(base), L * 0.085, edge)

	# 束根冰晶结（针从一团寒气里长出）
	AdaptiveDraw.circle(r, Vector2(mouth_x + L * 0.02, 0.0), L * 0.07, Color(_ICE_LT.r, _ICE_LT.g, _ICE_LT.b, 0.8))
	r._draw_star_fx(pal, Vector2(L, 0.0), Vector2(L * 0.55, 0.0), Vector2(mouth_x, 0.0))

# ---------------- 透骨钉：方帽长钉 + 棱线 + 钉尖冷光（木/暗） ----------------
## 参考 weapon_tougu_ding：骨白钉身收尖到 (L,0)，玄铁方帽压尾，绿光沿中脊棱线。
static func _draw_nail(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = r._palette()
	var L: float = r.tip_len
	var edge: Color = pal["edge"]
	var w := clampf(L * 0.11, 1.8, 2.7) * (1.0 + 0.05 * float(r.star - 1))
	var cap_x := -L * 0.46                # 钉帽前沿

	# 钉身（向 +X 收尖到 (L,0)）：暗底 + 上阳面骨白 + 下阴面灰骨（冷兵定色，不随五行绿走）
	var body := PackedVector2Array([
		Vector2(L, 0.0), Vector2(L * 0.34, -w), Vector2(cap_x, -w * 0.9),
		Vector2(cap_x, w * 0.9), Vector2(L * 0.34, w),
	])
	r.draw_colored_polygon(body, _INK)
	r.draw_colored_polygon(PackedVector2Array([
		Vector2(L, 0.0), Vector2(L * 0.34, -w), Vector2(cap_x, -w * 0.9), Vector2(cap_x, 0.0),
	]), _BONE)
	r.draw_colored_polygon(PackedVector2Array([
		Vector2(L, 0.0), Vector2(cap_x, 0.0), Vector2(cap_x, w * 0.9), Vector2(L * 0.34, w),
	]), _BONE.darkened(0.40))
	# 中脊棱线（五行荧光）+ 侧棱刻面
	r.draw_line(Vector2(L * 0.92, 0.0), Vector2(cap_x, 0.0), Color(edge.r, edge.g, edge.b, 0.9), 1.0, true)
	r.draw_line(Vector2(L * 0.38, -w * 0.45), Vector2(cap_x, -w * 0.42), Color(1.0, 1.0, 1.0, 0.35), 0.7, true)

	# 玄铁方帽（尾端小铁块 + 顶面亮 + 金绿包边）
	var cap := PackedVector2Array([
		Vector2(cap_x, -w * 1.7), Vector2(cap_x, w * 1.7),
		Vector2(-L * 0.68, w * 1.5), Vector2(-L * 0.72, 0.0), Vector2(-L * 0.68, -w * 1.5),
	])
	r.draw_colored_polygon(cap, _INK)
	r.draw_colored_polygon(PackedVector2Array([
		cap[0] * 0.96, cap[1] * 0.96, cap[2] * 0.95, cap[3] * 0.95, cap[4] * 0.95,
	]), _IRON)
	r.draw_line(Vector2(cap_x - L * 0.01, -w * 1.5), Vector2(cap_x - L * 0.01, w * 1.5),
		Color(edge.r, edge.g, edge.b, 0.7), 1.2, true)
	r.draw_line(Vector2(-L * 0.66, -w * 1.2), Vector2(cap_x - L * 0.04, -w * 1.4),
		Color(1.0, 1.0, 1.0, 0.3), 0.8, true)

	r._draw_star_fx(pal, Vector2(L, 0.0), Vector2(L * 0.6, 0.0), Vector2(cap_x, 0.0))

# ---------------- 浪里梭：两头尖流线梭 + 两侧水翼 + 梭心光（水） ----------------
## 参考 weapon_langli_suo：深色铁芯 + 骨白梭尖，青绿水翼自梭身旋出，前尖钉死 (L,0)。
static func _draw_shuttle(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = r._palette()
	var L: float = r.tip_len
	var edge: Color = pal["edge"]
	var w := L * 0.17 * (1.0 + 0.05 * float(r.star - 1))
	var tail := -L * 0.90
	var fin := Color(0.20, 0.62, 0.55)    # 水翼青绿（参考图定色，不随五行）

	# 后掠水翼（先画，压在梭身之下）：上/下各一弯月形，暗描边
	for s in [-1.0, 1.0]:
		var wing := PackedVector2Array([
			Vector2(L * 0.10, s * w * 0.4), Vector2(-L * 0.22, s * L * 0.44),
			Vector2(-L * 0.52, s * L * 0.34), Vector2(-L * 0.26, s * w * 0.5),
		])
		var wing_o := PackedVector2Array()
		for p in wing:
			wing_o.append(Vector2(p.x, p.y * 1.18 + s * 0.7))
		r.draw_colored_polygon(wing_o, _INK)
		r.draw_colored_polygon(wing, fin)
		r.draw_line(Vector2(L * 0.02, s * w * 0.5), Vector2(-L * 0.42, s * L * 0.34),
			Color(1.0, 1.0, 1.0, 0.25), 0.8, true)

	# 梭身（双尖透镜形）：暗底 + 铁芯身 + 两端骨白梭尖
	var body := PackedVector2Array([
		Vector2(L, 0.0), Vector2(L * 0.16, -w), Vector2(tail * 0.42, -w * 0.6),
		Vector2(tail, 0.0), Vector2(tail * 0.42, w * 0.6), Vector2(L * 0.16, w),
	])
	r.draw_colored_polygon(body, _INK)
	r.draw_colored_polygon(PackedVector2Array([
		Vector2(L, 0.0), Vector2(L * 0.16, -w), Vector2(tail * 0.42, -w * 0.6),
		Vector2(tail, 0.0), Vector2(L * 0.16, 0.0),
	]), pal["light"])
	r.draw_colored_polygon(PackedVector2Array([
		Vector2(L, 0.0), Vector2(L * 0.16, w), Vector2(tail * 0.42, w * 0.6),
		Vector2(tail, 0.0), Vector2(L * 0.16, 0.0),
	]), pal["dark"])
	# 铁芯中段（深色箍带，破掉整条骨白）
	r.draw_colored_polygon(PackedVector2Array([
		Vector2(L * 0.06, -w * 0.92), Vector2(-L * 0.30, -w * 0.78),
		Vector2(-L * 0.30, w * 0.78), Vector2(L * 0.06, w * 0.92),
	]), _IRON)
	# 梭心线槽（贯穿流光）
	r.draw_line(Vector2(L * 0.88, 0.0), Vector2(tail * 0.86, 0.0), Color(edge.r, edge.g, edge.b, 0.9), 1.2, true)
	# 梭心光（中点一颗冷光）
	AdaptiveDraw.circle(r, Vector2(-L * 0.10, 0.0), 1.5, Color(pal["hdr"].r, pal["hdr"].g, pal["hdr"].b, 0.9))
	AdaptiveDraw.circle(r, Vector2(-L * 0.10, 0.0), 0.7, Color(1.0, 1.0, 1.0, 0.95))

	r._draw_star_fx(pal, Vector2(L, 0.0), Vector2(L * 0.55, 0.0), Vector2(tail * 0.5, 0.0))

# ---------------- 弹弓：Y 形木弓架 + 皮筋 + 皮兜含灵珠（木） ----------------
## 参考 weapon_sling：枯木 Y 架 + 缠绳握柄，皮筋绷向皮兜，兜中一颗绿纹灵珠，
## 珠前缘精确顶到器尖 (L,0)。
static func _draw_sling(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = r._palette()
	var L: float = r.tip_len
	var edge: Color = pal["edge"]
	var wood := Color(0.46, 0.38, 0.28)                  # 枯木棕（参考图定色，不随五行走）
	var fork := Vector2(-L * 0.20, 0.0)                 # Y 分叉点
	var prong := Vector2(L * 0.38, 0.0)                 # 弓梢 x
	var pry := L * 0.40                                 # 弓梢半开度
	var bead_r := L * 0.13
	var pouch := Vector2(L - bead_r - L * 0.02, 0.0)    # 珠心：前缘钉死 (L,0)

	# 柄（尾端 -X → 分叉点）+ 缠绳握把
	r.draw_line(Vector2(-L * 0.88, 0.0), fork, _INK, 5.2, true)
	r.draw_line(Vector2(-L * 0.88, 0.0), fork, wood, 3.4, true)
	for i in range(3):
		var x := lerpf(-L * 0.74, -L * 0.38, float(i) / 2.0)
		r.draw_line(Vector2(x, -2.0), Vector2(x, 2.0), wood.darkened(0.45), 1.2, true)
	# 两弓梢（分叉 → 上下弓梢）
	for s in [-1.0, 1.0]:
		r.draw_line(fork, Vector2(prong.x, s * pry), _INK, 4.2, true)
		r.draw_line(fork, Vector2(prong.x, s * pry), wood, 2.6, true)
		# 弓梢缠绳头
		r.draw_line(Vector2(prong.x - L * 0.05, s * (pry - L * 0.05)),
			Vector2(prong.x + L * 0.02, s * (pry + L * 0.02)), wood.darkened(0.45), 1.4, true)
		AdaptiveDraw.circle(r, Vector2(prong.x + L * 0.02, s * (pry + L * 0.02)), 1.0, edge.darkened(0.1))
	# 皮筋（两弓梢 → 皮兜两侧，绷紧的暗弦）
	for s in [-1.0, 1.0]:
		r.draw_line(Vector2(prong.x, s * pry), pouch + Vector2(-L * 0.05, s * bead_r * 0.9),
			Color(0.10, 0.08, 0.07, 0.95), 1.1, true)
	# 皮兜（承珠的小皮杯，压在珠后）
	r.draw_colored_polygon(PackedVector2Array([
		pouch + Vector2(-bead_r * 1.1, -bead_r * 1.3), pouch + Vector2(-bead_r * 0.2, -bead_r * 0.9),
		pouch + Vector2(-bead_r * 0.2, bead_r * 0.9), pouch + Vector2(-bead_r * 1.1, bead_r * 1.3),
	]), pal["handle"].lerp(pal["dark"], 0.3))
	# 灵珠（兜内发光宝珠：暗圈 + 灵光核 + 高光点）
	AdaptiveDraw.circle(r, pouch, bead_r + 0.8, _INK)
	AdaptiveDraw.circle(r, pouch, bead_r, pal["light"])
	AdaptiveDraw.circle(r, pouch, bead_r * 0.55, Color(pal["hdr"].r, pal["hdr"].g, pal["hdr"].b, 0.95))
	AdaptiveDraw.circle(r, pouch + Vector2(-bead_r * 0.3, -bead_r * 0.3), bead_r * 0.25, Color(1.0, 1.0, 1.0, 0.9))

	r._draw_star_fx(pal, Vector2(L, 0.0), pouch, fork)

# ---------------- 火葫芦：双腹葫芦 + 口塞 + 藤蔓 + 葫身火纹（火，口朝 +X） ----------------
## 参考 weapon_fire_calabash：深赭葫身、金火纹缠腰、大腹绘太极、颈口拔塞喷火，
## 葫口（喷口=器尖）精确落在 (L,0)。
static func _draw_calabash(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = r._palette()
	var L: float = r.tip_len
	var edge: Color = pal["edge"]
	var ink: Color = r._ink(pal)
	var body_col: Color = pal["dark"].darkened(0.18)     # 深赭葫胎（参考图是暗色描金葫芦）
	var mouth_r := L * 0.13

	# 葫芦轮廓（口 t=0 在 x=L → 尾 t=1 收圆）
	var pts := PackedVector2Array()
	const SEG := 30
	for i in range(SEG + 1):
		var t := float(i) / float(SEG)
		pts.append(Vector2(_gourd_x(t, L), -_gourd_r(t, L)))
	for i in range(SEG + 1):
		var t := 1.0 - float(i) / float(SEG)
		pts.append(Vector2(_gourd_x(t, L), _gourd_r(t, L)))
	r._fill_outlined(pts, body_col)
	# 上半受光亮面（纯平一条亮带，破掉大平板）
	var lit := PackedVector2Array()
	for i in range(SEG + 1):
		var t := float(i) / float(SEG)
		lit.append(Vector2(_gourd_x(t, L), -_gourd_r(t, L)))
	for i in range(SEG + 1):
		var t := 1.0 - float(i) / float(SEG)
		lit.append(Vector2(_gourd_x(t, L), -_gourd_r(t, L) * 0.45))
	r.draw_colored_polygon(lit, Color(pal["light"].r, pal["light"].g, pal["light"].b, 0.35))

	# 收腰金箍
	var waist_x := _gourd_x(0.52, L)
	r.draw_line(Vector2(waist_x, -_gourd_r(0.52, L)), Vector2(waist_x, _gourd_r(0.52, L)),
		edge.darkened(0.1), 1.8, true)

	# 大腹火纹：两道金弧 + 中央火舌纹 + 太极心（大腹在尾端，火舌尖朝口 +X）
	var belly_c := Vector2(_gourd_x(0.78, L), 0.0)
	var belly_r := _gourd_r(0.78, L)
	_arc(r, belly_c, belly_r * 0.78, -PI * 0.55, PI * 0.55, Color(edge.r, edge.g, edge.b, 0.7), 1.0)
	_arc(r, belly_c, belly_r * 0.52, PI * 0.45, PI * 1.55, Color(edge.r, edge.g, edge.b, 0.5), 1.0)
	r.draw_polyline(PackedVector2Array([
		belly_c + Vector2(-belly_r * 0.26, -belly_r * 0.30), belly_c + Vector2(belly_r * 0.08, 0.0),
		belly_c + Vector2(-belly_r * 0.26, belly_r * 0.30),
	]), Color(edge.r, edge.g, edge.b, 0.9), 1.1, true)
	# 太极心（大腹中央一枚小阴阳点，骨白/暗墨两半）
	AdaptiveDraw.circle(r, belly_c + Vector2(belly_r * 0.34, 0.0), 1.6, Color(0.92, 0.90, 0.82, 0.9))
	AdaptiveDraw.circle(r, belly_c + Vector2(belly_r * 0.34, 0.0), 0.8, ink)

	# 藤蔓（自颈后向 -Y 卷出的卷须）
	var vine := Color(0.30, 0.46, 0.26)
	r.draw_polyline(PackedVector2Array([
		Vector2(_gourd_x(0.12, L), -_gourd_r(0.12, L)),
		Vector2(_gourd_x(0.08, L), -L * 0.26),
		Vector2(_gourd_x(0.24, L), -L * 0.34),
		Vector2(_gourd_x(0.36, L), -L * 0.26),
	]), vine, 1.2, true)
	_arc(r, Vector2(_gourd_x(0.40, L), -L * 0.24), L * 0.05, 0.0, TAU, vine, 1.0)

	# 口塞 + 葫口（喷口即器尖，落在 (L,0)）
	var mouth := Vector2(L, 0.0)
	# 塞身（颈口一段木塞，拔起一半露喷口）
	r.draw_line(Vector2(_gourd_x(0.04, L), 0.0), mouth - Vector2(L * 0.03, 0.0), pal["handle"], mouth_r * 1.5, true)
	# 口沿金环
	_arc(r, mouth - Vector2(L * 0.015, 0.0), mouth_r, -PI * 0.5, PI * 0.5, edge, 1.5)
	# 喷口火光（器尖火芯）
	AdaptiveDraw.circle(r, mouth, mouth_r * 0.75, Color(pal["hdr"].r, pal["hdr"].g, pal["hdr"].b, 0.9))
	AdaptiveDraw.circle(r, mouth, mouth_r * 0.35, Color(1.0, 0.95, 0.85, 0.95))

	r._draw_star_fx(pal, mouth, Vector2(_gourd_x(0.30, L), 0.0), belly_c)

## 葫芦包络：t=0 器口(x=L) → t=1 尾端收圆。半径走 颈→小腹→腰→大腹→尾 五段平滑。
static func _gourd_x(t: float, L: float) -> float:
	return lerpf(L, -L * 0.90, t)

static func _gourd_r(t: float, L: float) -> float:
	if t < 0.14:
		return lerpf(L * 0.13, L * 0.15, t / 0.14)
	if t < 0.46:
		return L * 0.15 + L * 0.11 * sin((t - 0.14) / 0.32 * PI)   # 小腹
	if t < 0.58:
		return L * 0.15                                            # 收腰
	if t < 0.90:
		return L * 0.15 + L * 0.33 * sin((t - 0.58) / 0.32 * PI)   # 大腹
	var k := (t - 0.90) / 0.10
	return lerp(L * 0.15, L * 0.02, k * k)                         # 尾端收圆

# ---------------- 音笛：竹笛管身 + 吹孔 + 4 指孔 + 尾端流苏穗（水，竖置） ----------------
## 参考 weapon_flute：竹青管身、暗节横箍、首端膜孔、四指孔、尾端拖一束蓝紫丝穗。
## 竖置（upright）由宿主整体转 -90°，本画法仍按 +X 长轴：head=器尖=L。
static func _draw_flute(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = r._palette()
	var L: float = r.tip_len
	var edge: Color = pal["edge"]
	var ink: Color = r._ink(pal)
	# 笛身偏竹青：pal 亮面往冷绿靠一点，避免读成纯冰条
	var bamboo: Color = pal["light"].lerp(Color(0.42, 0.72, 0.60), 0.35)
	var hw := L * 0.12 * (1.0 + 0.05 * float(r.star - 1))
	var head := L
	var tail := -L * 0.84

	# 管身（暗底 + 上亮下暗）
	r.draw_colored_polygon(PackedVector2Array([
		Vector2(head, -hw - 0.7), Vector2(head, hw + 0.7), Vector2(tail, hw + 0.7), Vector2(tail, -hw - 0.7),
	]), _INK)
	r.draw_colored_polygon(PackedVector2Array([
		Vector2(head, -hw), Vector2(head, 0.0), Vector2(tail, 0.0), Vector2(tail, -hw),
	]), bamboo)
	r.draw_colored_polygon(PackedVector2Array([
		Vector2(head, 0.0), Vector2(head, hw), Vector2(tail, hw), Vector2(tail, 0.0),
	]), bamboo.darkened(0.30))

	# 竹节横箍 3 道 + 首尾金口
	for i in range(3):
		var x := lerpf(head * 0.78, tail * 0.72, float(i) / 2.0)
		r.draw_line(Vector2(x, -hw), Vector2(x, hw), Color(ink.r, ink.g, ink.b, 0.75), 1.1, true)
	r.draw_line(Vector2(head - L * 0.05, -hw), Vector2(head - L * 0.05, hw), edge.darkened(0.1), 1.5, true)
	r.draw_line(Vector2(tail + L * 0.05, -hw), Vector2(tail + L * 0.05, hw), edge.darkened(0.1), 1.5, true)

	# 膜孔（靠首端的贴笛膜方孔）+ 吹孔
	r.draw_colored_polygon(PackedVector2Array([
		Vector2(head * 0.62, -hw * 0.42), Vector2(head * 0.72, -hw * 0.42),
		Vector2(head * 0.72, hw * 0.42), Vector2(head * 0.62, hw * 0.42),
	]), ink)
	# 4 指孔（暗孔 + 一点反光）
	for i in range(4):
		var x := lerpf(head * 0.44, tail * 0.52, float(i) / 3.0)
		AdaptiveDraw.circle(r, Vector2(x, 0.0), hw * 0.40, ink)
		AdaptiveDraw.circle(r, Vector2(x - hw * 0.12, -hw * 0.12), hw * 0.14, Color(1.0, 1.0, 1.0, 0.25))

	# 尾端流苏穗（系绳 + 结珠 + 散开的蓝紫丝线，明显拖出尾外）
	var tassel := Color(0.45, 0.50, 0.95)
	var knot := Vector2(tail - L * 0.10, 0.0)
	r.draw_line(Vector2(tail, 0.0), knot, edge, 1.2, true)
	AdaptiveDraw.circle(r, knot, 1.5, edge.darkened(0.1))
	for i in range(5):
		var fy := lerpf(-1.0, 1.0, float(i) / 4.0)
		r.draw_line(knot, knot + Vector2(-L * 0.16, fy * L * 0.15), tassel, 1.0, true)
	# 穗口束线
	r.draw_line(knot + Vector2(-L * 0.09, -L * 0.10), knot + Vector2(-L * 0.09, L * 0.10),
		Color(tassel.r, tassel.g, tassel.b, 0.7), 0.9, true)

	r._draw_star_fx(pal, Vector2(head, 0.0), Vector2(head * 0.5, 0.0), Vector2(0.0, 0.0))

# ---------------- 扇：扇形展开扇面 + 扇骨放射 + 扇钉 + 扇尾坠（水/火） ----------------
## 参考 weapon_fan / weapon_liaoyuan_shan：纸白扇面 + 深色放射扇骨 + 外缘收口，
## 水扇=冰蓝波纹 + 中央雪晶，火扇=外缘焰舌 + 朱橙焰纹。弧中点钉死 (L,0)。
static func _draw_fan(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = r._palette()
	var L: float = maxf(r.tip_len, 20.0)
	var edge: Color = pal["edge"]
	var ink: Color = r._ink(pal)
	var is_fire := r.element == "fire"
	var P := Vector2(-L * 0.30, 0.0)     # 扇钉（扇骨汇聚点）
	var R := L * 1.30                     # 外弧半径：P.x + R == L，弧中点精确落在 (L,0)
	var Ri := L * 0.26                    # 内半径（扇面不铺到钉，露骨）
	var half := deg_to_rad(60.0)          # 扇面半张角
	const SEG := 26

	# 扇面底色（环形扇区）：暗底外扩一圈 → 纸白面 + 极轻五行底色
	var paper: Color = r._paper(pal).lerp(pal["light"], 0.18)
	r.draw_colored_polygon(_sector(P, R + 1.0, Ri - 0.8, half, SEG), _INK)
	r.draw_colored_polygon(_sector(P, R, Ri, half, SEG), paper)
	# 下半压暗（阴阳折面感）
	r.draw_colored_polygon(_sector(P, R, Ri, half, SEG, true), Color(pal["dark"].r, pal["dark"].g, pal["dark"].b, 0.22))

	# 扇面纹（五行主题各一款）
	if is_fire:
		# 放射焰纹：三对朱橙焰楔
		for i in range(3):
			var a0 := lerpf(-half * 0.75, half * 0.75, float(i) / 2.0)
			for s in [-1.0, 1.0]:
				var a: float = a0 + s * 0.10
				var d0 := Vector2(cos(a - 0.14), sin(a - 0.14))
				var d1 := Vector2(cos(a + 0.14), sin(a + 0.14))
				r.draw_colored_polygon(PackedVector2Array([
					P + d0 * (Ri + (R - Ri) * 0.30), P + d0 * R * 0.97,
					P + Vector2(cos(a), sin(a)) * R * 0.78, P + d1 * R * 0.97,
					P + d1 * (Ri + (R - Ri) * 0.30),
				]), Color(pal["light"].r, pal["light"].g, pal["light"].b, 0.55))
		# 外缘火舌（沿弧一排三角焰尖，越过外棱线一点）
		for i in range(7):
			var a := lerpf(-half * 0.88, half * 0.88, float(i) / 6.0)
			var tipd := Vector2(cos(a), sin(a))
			var m := P + tipd * R
			var fl := P + tipd * (R + L * 0.10)
			var p1 := P + tipd.rotated(0.11) * R * 0.99
			var p2 := P + tipd.rotated(-0.11) * R * 0.99
			r.draw_colored_polygon(PackedVector2Array([p1, fl, p2]), Color(edge.r, edge.g, edge.b, 0.9))
	else:
		# 水扇：两道冰蓝同心波纹 + 中央雪晶（六角菱星）
		for i in range(2):
			var wr := lerpf(Ri + (R - Ri) * 0.40, R * 0.92, float(i))
			_arc(r, P, wr, -half, half, Color(edge.r, edge.g, edge.b, 0.5), 1.0)
		var cc := P + Vector2(1.0, 0.0) * (Ri + (R - Ri) * 0.62)
		for i in range(6):
			var a := TAU * float(i) / 6.0
			var d := Vector2(cos(a), sin(a))
			r.draw_line(cc, cc + d * L * 0.16, Color(edge.r, edge.g, edge.b, 0.85), 1.0, true)
			r.draw_line(cc + d * L * 0.10, cc + d * L * 0.10 + d.rotated(0.6) * L * 0.05,
				Color(edge.r, edge.g, edge.b, 0.6), 0.8, true)
		AdaptiveDraw.circle(r, cc, 1.2, Color(1.0, 1.0, 1.0, 0.9))

	# 扇骨（8 根，自扇钉放射到外缘，深色清晰压在扇面上）
	for i in range(8):
		var a := lerpf(-half, half, float(i) / 7.0)
		var d := Vector2(cos(a), sin(a))
		r.draw_line(P + d * Ri * 0.42, P + d * R * 0.985, Color(ink.r, ink.g, ink.b, 0.95), 1.2, true)
	# 外缘收口（深色边骨 + 五行亮棱）
	_arc(r, P, R, -half, half, Color(0.08, 0.09, 0.13, 0.95), 2.6)
	_arc(r, P, R + 1.0, -half, half, Color(edge.r, edge.g, edge.b, 0.9), 1.2)

	# 扇柄（自扇钉向尾 -X，骨白亮柄）
	var grip := P + Vector2(-L * 0.26, 0.0)
	r.draw_line(P, grip, _INK, 3.4, true)
	r.draw_line(P, grip, Color(0.82, 0.80, 0.72), 1.9, true)
	# 扇钉（汇聚点的金属钉）
	AdaptiveDraw.circle(r, P, 1.9, _INK)
	AdaptiveDraw.circle(r, P, 1.0, edge)
	# 扇尾坠（钉下系穗：短绳 + 结珠 + 丝线）
	var t0 := grip + Vector2(-L * 0.02, L * 0.02)
	r.draw_line(grip, t0, edge, 1.0, true)
	AdaptiveDraw.circle(r, t0 + Vector2(-L * 0.03, 0.0), 1.0, edge.darkened(0.1))
	for i in range(3):
		var fy := lerpf(-1.0, 1.0, float(i) / 2.0)
		r.draw_line(t0 + Vector2(-L * 0.03, 0.0), t0 + Vector2(-L * 0.11, fy * L * 0.08),
			Color(edge.r, edge.g, edge.b, 0.7), 0.9, true)

	r._draw_star_fx(pal, Vector2(L, 0.0), P + Vector2(cos(0.35), sin(0.35)) * R * 0.6,
		P + Vector2(cos(-0.35), sin(-0.35)) * R * 0.6)

## 环形扇区多边形（外弧 -half→half，内弧 half→-half 闭合）。lower=true 时只取下半（y>0）做压暗。
static func _sector(P: Vector2, R: float, Ri: float, half: float, seg: int, lower: bool = false) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(seg + 1):
		var a := lerpf(-half, half, float(i) / float(seg))
		if lower and sin(a) < 0.0:
			continue
		pts.append(P + Vector2(cos(a), sin(a)) * R)
	for i in range(seg + 1):
		var a := lerpf(half, -half, float(i) / float(seg))
		if lower and sin(a) < 0.0:
			continue
		pts.append(P + Vector2(cos(a), sin(a)) * Ri)
	return pts

# ---------------- 锥（金雷锥：棱面长锥 + 双箍环 + 雷纹） ----------------
static func _draw_awl(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = r._palette()
	var L: float = r.tip_len
	var star_k := 1.0 + 0.05 * float(r.star - 1)
	var w: float = clampf(L * 0.11, 2.2, 3.6) * star_k
	var edge: Color = pal["edge"]
	var tail := -L * 0.55
	# 五行气外晕
	r.draw_colored_polygon(PackedVector2Array([
		Vector2(L * 1.02, 0.0), Vector2(L * 0.3, -w * 1.3), Vector2(tail, -w * 1.3),
		Vector2(tail, w * 1.3), Vector2(L * 0.3, w * 1.3),
	]), Color(edge.r, edge.g, edge.b, 0.12))
	# 锥身：暗底 + 上亮面骨白 / 下暗面压棱（六棱锥的两个可见面）
	var body := PackedVector2Array([
		Vector2(L, 0.0), Vector2(L * 0.30, -w), Vector2(tail, -w),
		Vector2(tail - w * 0.35, 0.0), Vector2(tail, w), Vector2(L * 0.30, w),
	])
	r._fill_outlined(body, pal["light"])
	r.draw_colored_polygon(PackedVector2Array([
		Vector2(L, 0.0), Vector2(L * 0.30, 0.0), Vector2(tail - w * 0.2, 0.0),
		Vector2(tail, w), Vector2(L * 0.30, w),
	]), pal["dark"])
	# 锥面一道雷纹折线（金雷锥的雷意）
	r.draw_polyline(PackedVector2Array([
		Vector2(L * 0.80, -w * 0.32), Vector2(L * 0.64, w * 0.04),
		Vector2(L * 0.71, w * 0.10), Vector2(L * 0.52, w * 0.42),
	]), Color(edge.r, edge.g, edge.b, 0.95), 1.0, true)
	# 双箍环（靠尾三分之一，箍住锥尾）
	for i in range(2):
		var x := tail + L * (0.12 + 0.13 * float(i))
		r.draw_line(Vector2(x, -w * 1.0), Vector2(x, w * 1.0), _INK, 2.0, true)
		r.draw_line(Vector2(x, -w * 0.9), Vector2(x, w * 0.9), edge, 1.1, true)
		# 尾端小锥首
		AdaptiveDraw.circle(r, Vector2(tail - w * 0.35, 0.0), w * 0.55, _INK)
		AdaptiveDraw.circle(r, Vector2(tail - w * 0.35, 0.0), w * 0.32, edge)
		# 锥尖冷光
		r._draw_star_fx(pal, Vector2(L, 0.0), Vector2(L * 0.7, 0.0), Vector2(L * 0.2, 0.0))

# ---------------- 手里剑（四芒旋刃 + 弧形月牙内凹 + 中心透孔，金系暗器） ----------------
## 参考忍者手里剑：玄铁暗钢锻造，四片曲刃等距 90° 展开呈十字旋转风车，
## 外背凸弧隆起、内腹深深内凹月牙并带标志性小尖牙折角（notch），
## 内凹月牙磨出锋利银白刃面，正中心镂空圆孔，主尖精确钉死 (L,0)。
static func _draw_shuriken(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = r._palette()
	var L: float = r.tip_len
	var star_k := 1.0 + 0.04 * float(r.star - 1)
	var edge: Color = pal["edge"]
	var steel_dark: Color = pal["dark"].lerp(_IRON, 0.5)
	var bevel_light: Color = pal["light"]
	var r_hole := L * 0.20

	# 1. 构造四臂连续轮廓与内凹磨刃多边形
	var outer_poly := PackedVector2Array()
	var bevel_polys: Array[PackedVector2Array] = []
	var belly_lines: Array[PackedVector2Array] = []
	var back_lines: Array[PackedVector2Array] = []

	const N_BACK := 14
	const N_BELLY := 14

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

		# 谷底折角小尖牙 Notch（+20° r=0.35 -> +24° r=0.38 与下臂 -66° 咬合）
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
			outer_poly.append(p.rotated(ang) * L * star_k)

		# 记录背弧与月牙腹线
		var back_rot := PackedVector2Array()
		for p in seg_back:
			back_rot.append(p.rotated(ang) * L * star_k)
		back_lines.append(back_rot)

		var belly_rot := PackedVector2Array()
		for p in seg_belly:
			belly_rot.append(p.rotated(ang) * L * star_k)
		belly_lines.append(belly_rot)

		# 内凹月牙磨刀亮面（沿月牙腹线平滑内缩，绝不自交）
		var b_poly := PackedVector2Array()
		for p in seg_belly:
			b_poly.append(p.rotated(ang) * L * star_k)
		for idx in range(seg_belly.size() - 1, -1, -1):
			var p := seg_belly[idx]
			var dist_tip := 1.0 - p.length()
			var w_bevel := minf(0.12, dist_tip * 0.22)
			var inner_p := p * (1.0 - w_bevel / maxf(0.2, p.length()))
			b_poly.append(inner_p.rotated(ang) * L * star_k)
		bevel_polys.append(b_poly)

	# 2. 五行气外晕
	var halo := PackedVector2Array()
	for p in outer_poly:
		halo.append(p * 1.08)
	r.draw_colored_polygon(halo, Color(edge.r, edge.g, edge.b, 0.12))

	# 3. 外暗底描边
	var outer_bg := PackedVector2Array()
	for p in outer_poly:
		outer_bg.append(p * 1.035)
	r.draw_colored_polygon(outer_bg, _INK)

	# 4. 玄铁暗钢主体
	r.draw_colored_polygon(outer_poly, steel_dark)

	# 5. 四面雪亮内凹磨刃（Bevel）
	for bp in bevel_polys:
		r.draw_colored_polygon(bp, bevel_light)

	# 6. 刃口流光线（内凹锋口亮冷金，外凸背弧微弱冷银高光）
	for bl in belly_lines:
		r.draw_polyline(bl, Color(edge.r, edge.g, edge.b, 0.95), 1.1, true)
	for bkl in back_lines:
		r.draw_polyline(bkl, Color(1.0, 1.0, 1.0, 0.45), 0.8, true)

	# 7. 中心透孔（圆孔 + 内外金属环）
	AdaptiveDraw.circle(r, Vector2.ZERO, r_hole, Color(0.06, 0.07, 0.10, 0.95))
	AdaptiveDraw.arc(r, Vector2.ZERO, r_hole, 0.0, TAU, edge.darkened(0.15), 1.4, true)
	AdaptiveDraw.arc(r, Vector2.ZERO, r_hole * 1.32, 0.0, TAU, Color(_INK.r, _INK.g, _INK.b, 0.75), 1.0, true)

	# 8. 器尖起辉与升星光效
	# ★1 主尖 (L,0) 一点寒芒
	r._draw_star_fx(pal, Vector2(L, 0.0), Vector2(L * 0.6, 0.0), Vector2(r_hole * 1.5, 0.0))
	# 其余三尖也带微弱寒芒
	for k in range(1, 4):
		var ang := float(k) * PI * 0.5
		var tip_k := Vector2(L, 0.0).rotated(ang)
		AdaptiveDraw.circle(r, tip_k, 0.8, Color(pal["hdr"].r, pal["hdr"].g, pal["hdr"].b, 0.6))
	# ★3 极品升星：四尖之间环绕一道冷月旋风光环；★4 极境换成太虚霓虹双色环
	if r.star >= 4:
		AdaptiveDraw.arc(r, Vector2.ZERO, L * 0.88, 0.0, TAU, BC.NEON_CYAN_HDR, 1.2, true)
		AdaptiveDraw.arc(r, Vector2.ZERO, L * 0.72, 0.0, TAU, BC.NEON_VIOLET, 0.9, true)
	elif r.star >= 3:
		AdaptiveDraw.arc(r, Vector2.ZERO, L * 0.88, 0.0, TAU, Color(edge.r, edge.g, edge.b, 0.45), 1.1, true)

