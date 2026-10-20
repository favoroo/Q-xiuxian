extends RefCounted

## 长兵杂兵族矢量画法：鞭 WHIP / 盾 SHIELD / 斧 AXE / 锤 HAMMER / 锏 MACE / 尺 RULER / 剪 SHEARS
##
## 宿主 ProceduralWeaponRenderer._draw() 经 WeaponShapeLibrary 分发到此。
## 坐标契约与宿主一致：画布像素空间沿 +X 绘制，器尖/最前端精确落在 (r.tip_len, 0)；
## upright 重器（鞭/锤/锏）由宿主整体转 -90°，本模块一律沿 +X 画，不必自理朝向。
## 屏上实机尺度约 26px（节点 scale 0.55），结构细节必须在该尺度可读。
## 可用宿主能力：r._palette() / r._fill_outlined() / r._draw_shaft() / r._draw_star_fx() /
## r._draw_core_fx() / AdaptiveDraw.circle(r, ...) 等。
##
## 返回 true = 本模块接管该器形；false = 回退宿主旧画法。

## 暗描边底色（与宿主 _fill_outlined 同族，小尺寸下靠它撑轮廓）
const _OUTLINE := Color(0.06, 0.07, 0.10, 0.92)
## 朱砂/宝石红：符印侧同款固定点缀色，不随五行走
const _GEM_RED := Color(0.72, 0.14, 0.13, 0.95)
## 藤鞭花苞粉：青木藤上的灵芽点缀
const _BUD_PINK := Color(0.92, 0.62, 0.84)

static func draw_shape(shape: int, r: ProceduralWeaponRenderer) -> bool:
	match shape:
		ProceduralWeaponRenderer.WeaponShape.WHIP:
			_draw_whip(r)
		ProceduralWeaponRenderer.WeaponShape.SHIELD:
			_draw_shield(r)
		ProceduralWeaponRenderer.WeaponShape.AXE:
			_draw_axe(r)
		ProceduralWeaponRenderer.WeaponShape.HAMMER:
			_draw_hammer(r)
		ProceduralWeaponRenderer.WeaponShape.MACE:
			_draw_mace(r)
		ProceduralWeaponRenderer.WeaponShape.RULER:
			_draw_ruler(r)
		ProceduralWeaponRenderer.WeaponShape.SHEARS:
			_draw_shears(r)
		_:
			return false
	return true

# ---------------- 通用小构件 ----------------

## 均匀厚描边的填充板：_fill_outlined 的内缩是比例的，小多边形上描边太细，
## 先补一圈等宽暗折线再填，保证 26px 尺度轮廓 ≥1.6。
static func _plate(r: ProceduralWeaponRenderer, pts: PackedVector2Array, fill: Color, w: float = 1.8) -> void:
	var closed := pts.duplicate()
	closed.append(pts[0])
	r.draw_polyline(closed, _OUTLINE, w + 0.8, true)
	r._fill_outlined(pts, fill)

## 多边形质心
static func _centroid(pts: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in pts:
		c += p
	return c / float(pts.size())

## 以某点为中心缩放多边形（外晕 / 内缩面板用）
static func _scaled_about(pts: PackedVector2Array, center: Vector2, k: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(center + (p - center) * k)
	return out

## 沿折线的法向（相邻两点差分，端点自动退化）
static func _normal_at(spine: PackedVector2Array, i: int) -> Vector2:
	var a := spine[maxi(i - 1, 0)]
	var b := spine[mini(i + 1, spine.size() - 1)]
	var d := (b - a).normalized()
	return Vector2(-d.y, d.x)

## 变宽折线 → 闭合带状多边形（鞭身/剪刃共用）
static func _ribbon(spine: PackedVector2Array, halfw: PackedFloat32Array) -> PackedVector2Array:
	var top := PackedVector2Array()
	var bot := PackedVector2Array()
	for i in range(spine.size()):
		var n := _normal_at(spine, i)
		top.append(spine[i] + n * halfw[i])
		bot.append(spine[i] - n * halfw[i])
	var out := top
	for i in range(bot.size() - 1, -1, -1):
		out.append(bot[i])
	return out

## 菱形宝石（尺首/锤面/盾鼻共用）
static func _gem(r: ProceduralWeaponRenderer, pos: Vector2, s: float, col: Color) -> void:
	r.draw_colored_polygon(PackedVector2Array([
		pos + Vector2(s, 0.0), pos + Vector2(0.0, -s * 0.72),
		pos + Vector2(-s, 0.0), pos + Vector2(0.0, s * 0.72),
	]), _OUTLINE)
	r.draw_colored_polygon(PackedVector2Array([
		pos + Vector2(s * 0.72, 0.0), pos + Vector2(0.0, -s * 0.5),
		pos + Vector2(-s * 0.72, 0.0), pos + Vector2(0.0, s * 0.5),
	]), col)
	r.draw_line(pos + Vector2(-s * 0.3, -s * 0.18), pos + Vector2(s * 0.2, -s * 0.32),
		Color(1.0, 1.0, 1.0, 0.8), 0.7, true)

## 金属系器形要真金面：metal 调色板 light 是骨白，掺 edge 金才读得出「金尺/金蛟」
static func _gold(pal: Dictionary) -> Dictionary:
	return {
		"light": pal["light"].lerp(pal["edge"], 0.62),
		"dark": pal["edge"].darkened(0.48),
	}

# ---------------- 鞭 · 青木藤鞭（木，upright） ----------------
## 短柄缠绳 + 一整波正弦 S 形渐细藤身（两端零点 ⇒ 鞭梢精确落 (L,0)）
## + 4 道节环 + 交错倒刺 + 藤叶与灵芽花苞。
static func _draw_whip(r: ProceduralWeaponRenderer) -> void:
	var pal := r._palette()
	var L := r.tip_len
	var edge: Color = pal["edge"]
	# 短柄（藤骨深棕）+ 缠绳三道 + 柄头小珠
	r._draw_shaft(pal, L * 0.30, 2.8)
	for i in range(3):
		var hx := -L * (0.08 + float(i) * 0.09)
		r.draw_line(Vector2(hx, -1.6), Vector2(hx, 1.6), pal["handle"].lerp(Color.WHITE, 0.22), 1.0, true)
	AdaptiveDraw.circle(r, Vector2(-L * 0.30, 0.0), 1.6, _OUTLINE)
	AdaptiveDraw.circle(r, Vector2(-L * 0.30, 0.0), 0.9, edge)
	# 藤身脊柱：sin(t·2π) 全波 S 弯，t=1 归零 ⇒ 鞭梢恰在 (L,0)
	const SEG := 26
	var spine := PackedVector2Array()
	var halfw := PackedFloat32Array()
	for i in range(SEG + 1):
		var t := float(i) / float(SEG)
		var y := sin(t * TAU) * L * (0.30 - 0.12 * t)
		spine.append(Vector2(lerpf(L * 0.02, L, t), y))
		halfw.append(lerpf(L * 0.115, L * 0.026, t))
	# 外晕（木气）
	r.draw_colored_polygon(_scaled_about(_ribbon(spine, halfw), Vector2(L * 0.5, 0.0), 1.16),
		Color(edge.r, edge.g, edge.b, 0.10))
	# 藤身带（渐细 ribbon）+ 鞭脊流光
	_plate(r, _ribbon(spine, halfw), pal["dark"].lerp(pal["light"], 0.55), 1.4)
	r.draw_polyline(spine, Color(edge.r, edge.g, edge.b, 0.7), 1.0, true)
	# 节环 4 道：t=0.2/0.4/0.6/0.8 横截暗带
	for i in range(1, 5):
		var idx := int(round(float(i) * 0.2 * float(SEG)))
		var n := _normal_at(spine, idx)
		var h := halfw[idx]
		r.draw_line(spine[idx] - n * h, spine[idx] + n * h, pal["dark"].darkened(0.5), 1.3, true)
	# 倒刺：沿鞭身两侧交错外挑的小三角
	for i in range(6):
		var idx2 := int(round((0.14 + float(i) * 0.135) * float(SEG)))
		var s := 1.0 if i % 2 == 0 else -1.0
		var n2 := _normal_at(spine, idx2) * s
		var a := (spine[mini(idx2 + 1, SEG)] - spine[maxi(idx2 - 1, 0)]).normalized()
		var h2 := halfw[idx2]
		var b := spine[idx2] + n2 * h2 * 0.7
		r.draw_colored_polygon(PackedVector2Array([
			b + a * h2 * 0.5, b - a * h2 * 0.5, spine[idx2] + n2 * (h2 + L * 0.06),
		]), pal["dark"].darkened(0.3))
	# 藤叶：三片（近梢一片回挑，不许越过 (L,0) 器尖线）
	_whip_leaf(r, spine, 7, L, pal, -1.0, 0.62)
	_whip_leaf(r, spine, 14, L, pal, 1.0, 0.85)
	_whip_leaf(r, spine, 22, L, pal, -1.0, -0.75)
	# 灵芽花苞
	var bud_i := 19
	var bud_n := _normal_at(spine, bud_i)
	var bud_p := spine[bud_i] + bud_n * (halfw[bud_i] + 1.1)
	AdaptiveDraw.circle(r, bud_p, 1.4, _OUTLINE)
	AdaptiveDraw.circle(r, bud_p, 0.9, _BUD_PINK)
	r._draw_star_fx(pal, Vector2(L, 0.0), spine[spine.size() - 5], spine[6])

static func _whip_leaf(r: ProceduralWeaponRenderer, spine: PackedVector2Array, idx: int,
		L: float, pal: Dictionary, side: float, along: float) -> void:
	var n := _normal_at(spine, idx) * side
	var t := (spine[mini(idx + 1, spine.size() - 1)] - spine[maxi(idx - 1, 0)]).normalized()
	var dir := (n * 0.75 + t * along).normalized()
	var base := spine[idx] + n * 0.5
	var len := L * 0.12
	var wid := L * 0.048
	var s2 := dir.orthogonal()
	_plate(r, PackedVector2Array([
		base, base + dir * len * 0.55 + s2 * wid, base + dir * len, base + dir * len * 0.55 - s2 * wid,
	]), pal["light"], 1.2)
	r.draw_line(base, base + dir * len, pal["dark"].darkened(0.3), 0.8, true)

# ---------------- 盾 · 玄武灵盾（土，MELEE） ----------------
## 倒水滴形盾：骨白厚边 + 玄墨盾面 + 中央玄武盾钮（龟甲纹 + 缠蛇环）+ 大盾钉 + 鼻端宝石。
static func _draw_shield(r: ProceduralWeaponRenderer) -> void:
	var pal := r._palette()
	var L := r.tip_len
	var edge: Color = pal["edge"]
	var hh := L * 0.50
	var face := PackedVector2Array([
		Vector2(L, 0.0),
		Vector2(L * 0.52, -hh * 0.66), Vector2(L * 0.20, -hh),
		Vector2(-L * 0.42, -hh * 0.92), Vector2(-L * 0.80, -hh * 0.56), Vector2(-L * 0.90, 0.0),
		Vector2(-L * 0.80, hh * 0.56), Vector2(-L * 0.42, hh * 0.92),
		Vector2(L * 0.20, hh), Vector2(L * 0.52, hh * 0.66),
	])
	var cen := _centroid(face)
	# 土气外晕
	r.draw_colored_polygon(_scaled_about(face, cen, 1.07), Color(edge.r, edge.g, edge.b, 0.12))
	# 骨白盾沿（厚）+ 玄墨盾面（内缩）
	_plate(r, face, pal["light"], 2.2)
	var inner := _scaled_about(face, cen, 0.80)
	r.draw_colored_polygon(inner, pal["dark"].darkened(0.16))
	# 盾面石纹：两道斜裂 + 沿内缘描金
	r.draw_line(Vector2(L * 0.30, -hh * 0.42), Vector2(-L * 0.10, -hh * 0.66),
		Color(0.06, 0.07, 0.10, 0.55), 0.9, true)
	r.draw_line(Vector2(-L * 0.30, hh * 0.50), Vector2(-L * 0.66, hh * 0.22),
		Color(0.06, 0.07, 0.10, 0.55), 0.9, true)
	r.draw_polyline(inner, Color(edge.r, edge.g, edge.b, 0.4), 0.8, true)
	# 盾脊：自盾钮直抵鼻端器尖
	r.draw_line(Vector2(L * 0.10, 0.0), Vector2(L * 0.94, 0.0), Color(edge.r, edge.g, edge.b, 0.85), 1.4, true)
	r.draw_line(Vector2(L * 0.10, 0.0), Vector2(L * 0.94, 0.0), Color(1.0, 1.0, 1.0, 0.4), 0.6, true)
	# 玄武盾钮：金环 + 龟甲（同心圆 + 六辐甲片线）+ 缠蛇弧
	var boss := Vector2(L * 0.04, 0.0)
	var br := L * 0.21
	AdaptiveDraw.circle(r, boss, br + 1.2, _OUTLINE)
	AdaptiveDraw.circle(r, boss, br, edge.darkened(0.18))
	AdaptiveDraw.circle(r, boss, br * 0.66, pal["dark"].darkened(0.15))
	for i in range(6):
		var a := TAU * float(i) / 6.0 + PI / 12.0
		r.draw_line(boss + Vector2(cos(a), sin(a)) * br * 0.22, boss + Vector2(cos(a), sin(a)) * br * 0.64,
			edge.darkened(0.05), 0.9, true)
	AdaptiveDraw.arc(r, boss, br * 0.30, 0.0, TAU, edge.darkened(0.1), 1.0, true)
	# 蛇：绕钮一圈开口环（玄武「龟蛇」的蛇身意象）
	AdaptiveDraw.arc(r, boss, br * 1.34, -2.5, 2.1, Color(edge.r, edge.g, edge.b, 0.8), 1.2, true)
	AdaptiveDraw.circle(r, boss + Vector2(cos(2.1), sin(2.1)) * br * 1.34, 1.0, edge)
	# 大盾钉：压在盾沿转折上的六颗
	for p in [face[1], face[2], face[3], face[6], face[7], face[8]]:
		AdaptiveDraw.circle(r, p, 1.8, _OUTLINE)
		AdaptiveDraw.circle(r, p, 1.0, pal["light"].lerp(edge, 0.5))
	# 鼻端宝石
	_gem(r, Vector2(L * 0.60, 0.0), L * 0.055, _GEM_RED)
	r._draw_core_fx(pal, boss, 1.2)

# ---------------- 斧 · 开山斧（土，SWEEP） ----------------
## 长柄缠绳 + 单侧大月牙斧刃（外弧精确过 (L,0)）+ 刃口两道崩口 + 斧背楔 + 箍环。
static func _draw_axe(r: ProceduralWeaponRenderer) -> void:
	var pal := r._palette()
	var L := r.tip_len
	var edge: Color = pal["edge"]
	# 长柄 + 尾端缠绳 + 柄头包铁
	r._draw_shaft(pal, L * 0.86, 2.8)
	for i in range(3):
		var hx := -L * (0.52 + float(i) * 0.11)
		r.draw_line(Vector2(hx, -1.8), Vector2(hx + 1.6, 1.8), pal["handle"].lerp(Color.WHITE, 0.22), 1.0, true)
	AdaptiveDraw.circle(r, Vector2(-L * 0.86, 0.0), 1.7, _OUTLINE)
	AdaptiveDraw.circle(r, Vector2(-L * 0.86, 0.0), 1.0, edge.darkened(0.2))
	# 斧背楔（柄后配重块）
	_plate(r, PackedVector2Array([
		Vector2(L * 0.10, -L * 0.13), Vector2(-L * 0.12, -L * 0.10),
		Vector2(-L * 0.17, 0.0), Vector2(-L * 0.12, L * 0.10), Vector2(L * 0.10, L * 0.13),
	]), pal["dark"].lerp(pal["light"], 0.25), 1.6)
	# 月牙斧刃：外弧半径 R=L*0.90、圆心 L*0.10 ⇒ 弧顶恰落 (L,0)
	var c := Vector2(L * 0.10, 0.0)
	var R := L * 0.90
	var A := 0.62
	const BSEG := 16
	var blade := PackedVector2Array()
	for i in range(BSEG + 1):
		var a := -A + 2.0 * A * float(i) / float(BSEG)
		blade.append(c + Vector2(cos(a) * R, sin(a) * R * 1.02))
	for i in range(BSEG, -1, -1):
		var a2 := -A * 0.92 + 2.0 * A * 0.92 * float(i) / float(BSEG)
		blade.append(c + Vector2(cos(a2) * L * 0.30, sin(a2) * L * 0.32))
	# 土气外晕
	r.draw_colored_polygon(_scaled_about(blade, c, 1.05), Color(edge.r, edge.g, edge.b, 0.10))
	_plate(r, blade, pal["light"], 2.0)
	# 刃面斜光：贴外弧内侧一道渐窄亮带（用两条折线夹出斜面感）
	var bevel := PackedVector2Array()
	for i in range(BSEG + 1):
		var a3 := -A * 0.86 + 2.0 * A * 0.86 * float(i) / float(BSEG)
		bevel.append(c + Vector2(cos(a3) * R * 0.80, sin(a3) * R * 0.82))
	r.draw_polyline(bevel, Color(1.0, 1.0, 1.0, 0.30), 1.1, true)
	# 刃口流光
	var shine := PackedVector2Array()
	for i in range(BSEG + 1):
		var a4 := -A + 2.0 * A * float(i) / float(BSEG)
		shine.append(c + Vector2(cos(a4) * R * 0.985, sin(a4) * R * 1.005))
	r.draw_polyline(shine, Color(edge.r, edge.g, edge.b, 0.9), 1.2, true)
	# 崩口：刃口上下两道暗色三角缺口（砍过硬东西的痕迹）
	for s in [-1.0, 1.0]:
		var a5: float = s * 0.42
		var e5 := c + Vector2(cos(a5) * R, sin(a5) * R * 1.02)
		var n5 := Vector2(cos(a5), sin(a5))
		var t5 := n5.orthogonal()
		r.draw_colored_polygon(PackedVector2Array([
			e5 + t5 * L * 0.05, e5 - t5 * L * 0.045, e5 - n5 * L * 0.062,
		]), _OUTLINE)
	# 斧眼箍环：斧刃接柄处两道缠箍
	for i in range(2):
		var hx2 := L * (0.14 + float(i) * 0.09)
		r.draw_line(Vector2(hx2, -L * 0.26), Vector2(hx2, L * 0.26), pal["dark"].darkened(0.35), 1.8, true)
		r._draw_star_fx(pal, Vector2(L, 0.0), c + Vector2(R * 0.92, 0.0), Vector2(L * 0.24, 0.0))

# ---------------- 锤 · 崩浪锤（水，upright） ----------------
## 长柄缠绳 + 多棱锤头（八角倒角 + 下半侧面压暗）+ 玄面冰蓝浪纹 + 双箍环 + 面心宝石。
static func _draw_hammer(r: ProceduralWeaponRenderer) -> void:
	var pal := r._palette()
	var L := r.tip_len
	var edge: Color = pal["edge"]
	# 长柄 + 缠绳
	r._draw_shaft(pal, L * 0.80, 3.4)
	for i in range(3):
		var hx := -L * (0.44 + float(i) * 0.11)
		r.draw_line(Vector2(hx, -1.9), Vector2(hx + 1.7, 1.9), pal["handle"].lerp(Color.WHITE, 0.22), 1.0, true)
	var h := L * 0.34
	var x0 := L * 0.32
	# 锤头八角轮廓：前端面平直落在 x=L，四角倒棱
	var head := PackedVector2Array([
		Vector2(L, -h * 0.58), Vector2(L, h * 0.58),
		Vector2(L * 0.95, h), Vector2(x0 + L * 0.10, h),
		Vector2(x0, h * 0.66), Vector2(x0, -h * 0.66),
		Vector2(x0 + L * 0.10, -h), Vector2(L * 0.95, -h),
	])
	var cen := _centroid(head)
	r.draw_colored_polygon(_scaled_about(head, cen, 1.06), Color(edge.r, edge.g, edge.b, 0.10))
	_plate(r, head, pal["light"], 2.0)
	# 下半侧面压暗（多棱体的第二分面）
	r.draw_colored_polygon(PackedVector2Array([
		Vector2(L, h * 0.16), Vector2(L, h * 0.58), Vector2(L * 0.95, h),
		Vector2(x0 + L * 0.10, h), Vector2(x0, h * 0.66), Vector2(x0, h * 0.16),
	]), pal["dark"])
	r.draw_line(Vector2(x0 + L * 0.02, h * 0.16), Vector2(L * 0.98, h * 0.16),
		Color(0.06, 0.07, 0.10, 0.5), 0.9, true)
	# 玄面内嵌：正面凿一块深水面板，浪纹刻在上面
	var face := _scaled_about(head, cen, 0.78)
	r.draw_colored_polygon(face, pal["dark"].darkened(0.38))
	r.draw_polyline(face, Color(edge.r, edge.g, edge.b, 0.45), 0.8, true)
	# 冰蓝浪纹两道（正弦折线，俯视小尺寸读得出「水」）
	for row in range(2):
		var yc := lerpf(-h * 0.26, h * 0.30, float(row))
		var wave := PackedVector2Array()
		for i in range(13):
			var t := float(i) / 12.0
			wave.append(Vector2(lerpf(x0 + L * 0.16, L * 0.90, t),
				yc + sin(t * TAU * 1.5 + float(row) * PI) * h * 0.11))
		r.draw_polyline(wave, Color(pal["light"].r, pal["light"].g, pal["light"].b, 0.85), 1.0, true)
	# 箍环两道：锤头接柄处
	for i in range(2):
		var hx2 := x0 - L * 0.02 + float(i) * L * 0.07
		r.draw_line(Vector2(hx2, -h * 1.08), Vector2(hx2, h * 1.08), _OUTLINE, 2.6, true)
		r.draw_line(Vector2(hx2, -h * 1.08), Vector2(hx2, h * 1.08), edge.darkened(0.15), 1.2, true)
	# 顶面两枚包角凸钉
	for px in [x0 + L * 0.14, L * 0.86]:
		AdaptiveDraw.circle(r, Vector2(px, -h), 1.5, _OUTLINE)
		AdaptiveDraw.circle(r, Vector2(px, -h), 0.8, pal["light"])
	# 面心红宝石
	_gem(r, Vector2(L * 0.62, -h * 0.04), L * 0.055, _GEM_RED)
	r._draw_core_fx(pal, Vector2(L * 0.64, 0.0), 1.2)

# ---------------- 锏 · 六棱锏（土，upright） ----------------
## 六棱重身：俯视露三分面（中面骨白亮 + 上下暗面 + 两道棱线）+ 3 道节环 + 锏首配重珠 + 尾环。
static func _draw_mace(r: ProceduralWeaponRenderer) -> void:
	var pal := r._palette()
	var L := r.tip_len
	var edge: Color = pal["edge"]
	# 锏身轮廓：尾粗、中段最宽、前段收尖，尖精确落 (L,0)
	var body := PackedVector2Array([
		Vector2(-L * 0.78, -L * 0.13), Vector2(L * 0.05, -L * 0.21), Vector2(L * 0.55, -L * 0.19),
		Vector2(L * 0.90, -L * 0.08), Vector2(L, 0.0),
		Vector2(L * 0.90, L * 0.08), Vector2(L * 0.55, L * 0.19), Vector2(L * 0.05, L * 0.21),
		Vector2(-L * 0.78, L * 0.13),
	])
	var cen := _centroid(body)
	r.draw_colored_polygon(_scaled_about(body, cen, 1.06), Color(edge.r, edge.g, edge.b, 0.10))
	# 暗面打底（上下两个斜棱面共用）
	_plate(r, body, pal["dark"].lerp(pal["light"], 0.18), 2.0)
	# 中棱亮面：六棱正对镜头的那一面
	var mid := PackedVector2Array([
		Vector2(-L * 0.78, -L * 0.052), Vector2(L * 0.05, -L * 0.085), Vector2(L * 0.55, -L * 0.075),
		Vector2(L * 0.90, -L * 0.028), Vector2(L, 0.0),
		Vector2(L * 0.90, L * 0.028), Vector2(L * 0.55, L * 0.075), Vector2(L * 0.05, L * 0.085),
		Vector2(-L * 0.78, L * 0.052),
	])
	r.draw_colored_polygon(mid, pal["light"])
	# 两道棱线（分面交界，五行荧光）
	for s in [-1.0, 1.0]:
		var ridge := PackedVector2Array()
		for p in mid:
			if absf(p.y) > L * 0.02:
				ridge.append(Vector2(p.x, s * absf(p.y)))
		r.draw_polyline(ridge, Color(edge.r, edge.g, edge.b, 0.75), 0.9, true)
	# 节环 3 道：暗带横截 + 环心亮线
	for i in range(3):
		var x := L * (-0.45 + float(i) * 0.42)
		var half := L * 0.20 * (1.0 - absf(float(i) - 1.0) * 0.06)
		r.draw_line(Vector2(x, -half), Vector2(x, half), pal["dark"].darkened(0.45), 2.4, true)
		r.draw_line(Vector2(x, -half), Vector2(x, half), Color(edge.r, edge.g, edge.b, 0.55), 0.8, true)
	# 锏首（尾端喇叭箍）+ 尾环
	_plate(r, PackedVector2Array([
		Vector2(-L * 0.76, -L * 0.175), Vector2(-L * 0.88, -L * 0.14),
		Vector2(-L * 0.92, 0.0), Vector2(-L * 0.88, L * 0.14), Vector2(-L * 0.76, L * 0.175),
	]), edge.darkened(0.25), 1.6)
	AdaptiveDraw.arc(r, Vector2(-L * 0.98, 0.0), L * 0.085, 0.0, TAU, _OUTLINE, 2.4, true)
	AdaptiveDraw.arc(r, Vector2(-L * 0.98, 0.0), L * 0.085, 0.0, TAU, edge.darkened(0.1), 1.2, true)
	# 前段箍 + 亮面上两粒星钉
	r.draw_line(Vector2(L * 0.80, -L * 0.10), Vector2(L * 0.80, L * 0.10), pal["dark"].darkened(0.4), 1.6, true)
	for px in [L * 0.18, L * 0.62]:
		AdaptiveDraw.circle(r, Vector2(px, 0.0), 1.0, Color(edge.r, edge.g, edge.b, 0.9))
	r._draw_star_fx(pal, Vector2(L, 0.0), Vector2(L * 0.7, 0.0), Vector2(-L * 0.3, 0.0))

# ---------------- 尺 · 聚宝金尺（金，SWEEP） ----------------
## 长条金尺：上亮下暗双分面 + 8 道刻度 + 中脉财气流光 + 如意云头尺首（三瓣 + 红宝石）。
static func _draw_ruler(r: ProceduralWeaponRenderer) -> void:
	var pal := r._palette()
	var gold := _gold(pal)
	var L := r.tip_len
	var edge: Color = pal["edge"]
	var ink: Color = pal["edge"].darkened(0.55)
	# 如意云头尺首（先画，被尺身压住根部）：中央大瓣 + 两侧小瓣
	AdaptiveDraw.circle(r, Vector2(-L * 0.94, 0.0), L * 0.13, _OUTLINE)
	AdaptiveDraw.circle(r, Vector2(-L * 0.94, 0.0), L * 0.105, gold["light"])
	for s in [-1.0, 1.0]:
		var lob := Vector2(-L * 0.99, s * L * 0.085)
		AdaptiveDraw.circle(r, lob, L * 0.062, _OUTLINE)
		AdaptiveDraw.circle(r, lob, L * 0.045, gold["dark"].lerp(gold["light"], 0.5))
	# 尺身：器首平口恰在 x=L，尾端收斜角接尺首
	var bar := PackedVector2Array([
		Vector2(L, -L * 0.095), Vector2(L, L * 0.095),
		Vector2(-L * 0.84, L * 0.125), Vector2(-L * 0.90, 0.0), Vector2(-L * 0.84, -L * 0.125),
	])
	r.draw_colored_polygon(_scaled_about(bar, Vector2(L * 0.05, 0.0), 1.05),
		Color(edge.r, edge.g, edge.b, 0.10))
	_plate(r, bar, gold["light"], 1.8)
	# 下缘暗分面（厚度）+ 上缘骨白高光
	r.draw_colored_polygon(PackedVector2Array([
		Vector2(L, L * 0.045), Vector2(L, L * 0.095),
		Vector2(-L * 0.84, L * 0.125), Vector2(-L * 0.84, L * 0.055),
	]), gold["dark"])
	r.draw_line(Vector2(L * 0.96, -L * 0.075), Vector2(-L * 0.82, -L * 0.10),
		Color(1.0, 1.0, 1.0, 0.45), 0.8, true)
	# 刻度 8 道：沿上缘长短交替（近距读成「尺」的关键特征）
	for i in range(8):
		var t := float(i) / 7.0
		var x := lerpf(L * 0.80, -L * 0.52, t)
		var hw := lerpf(L * 0.095, L * 0.125, (L * 0.86 - x) / (L * 1.7))
		var len := hw * (0.62 if i % 2 == 0 else 0.30)
		r.draw_line(Vector2(x, -hw * 0.95), Vector2(x, -hw * 0.95 + len), ink, 0.9, true)
	# 中脉财气线 + 器首端面金口
	r.draw_line(Vector2(L * 0.90, L * 0.012), Vector2(-L * 0.66, L * 0.012),
		Color(edge.r, edge.g, edge.b, 0.6), 0.8, true)
	r.draw_line(Vector2(L, -L * 0.09), Vector2(L, L * 0.09), edge, 1.4, true)
	# 尺首云眼红宝石
	_gem(r, Vector2(-L * 0.94, 0.0), L * 0.042, _GEM_RED)
	r._draw_star_fx(pal, Vector2(L, 0.0), Vector2(L * 0.5, 0.0), Vector2(-L * 0.2, 0.0))

# ---------------- 剪 · 金蛟剪（金，SWEEP） ----------------
## 真剪刀结构：两片龙须弯刃自中央铰轴交叉成 X、各自接一根指环（上刃接下环），
## 双刃尖对称张开、最前端 x 恰为 L（剪切点 = 出膛点 (L,0)）。
static func _draw_shears(r: ProceduralWeaponRenderer) -> void:
	var pal := r._palette()
	var gold := _gold(pal)
	var L := r.tip_len
	var edge: Color = pal["edge"]
	# 后片刃（下尖上环）先画，前片压上，铰轴最后盖缝
	for pass_i in range(2):
		var s := 1.0 if pass_i == 0 else -1.0
		_shear_blade(r, pal, gold, L, s, pass_i == 1)
	# 铰轴钉：暗底 + 金环 + 宝心
	AdaptiveDraw.circle(r, Vector2.ZERO, 2.6, _OUTLINE)
	AdaptiveDraw.circle(r, Vector2.ZERO, 1.7, edge.darkened(0.15))
	AdaptiveDraw.circle(r, Vector2.ZERO, 0.8, Color(1.0, 1.0, 1.0, 0.9))
	r._draw_star_fx(pal, Vector2(L, 0.0), Vector2(L * 0.72, 0.0), Vector2(L * 0.15, 0.0))

## 单片蛟刃：指环 → 铰轴 → 刃尖（两片刃尖合拢于器尖 (L,0)，闭合的剪刀）
static func _shear_blade(r: ProceduralWeaponRenderer, pal: Dictionary, gold: Dictionary,
		L: float, s: float, front: bool) -> void:
	var edge: Color = pal["edge"]
	var tip := Vector2(L, 0.0)
	var ring := Vector2(-L * 0.52, -s * L * 0.20)
	# 脊柱贝塞尔：出环 → 过铰轴偏置（鼓腹弯月）→ 到刃尖
	var p0 := ring + (Vector2.ZERO - ring).normalized() * L * 0.05
	var p1 := Vector2(L * 0.10, -s * L * 0.085)
	const BSEG := 16
	var spine := PackedVector2Array()
	var halfw := PackedFloat32Array()
	for i in range(BSEG + 1):
		var t := float(i) / float(BSEG)
		var u := 1.0 - t
		spine.append(p0 * (u * u) + p1 * (2.0 * u * t) + tip * (t * t))
		# 半宽：柄细、腹部最宽、近尖急收
		halfw.append(L * (0.034 + 0.048 * sin(t * PI)) * (1.0 - clampf((t - 0.62) / 0.38, 0.0, 1.0) * 0.92))
	var band := _ribbon(spine, halfw)
	# 把带体首尾钉到几何端点上：刃尖恰在 (L, s·0.24L)，柄端收到一点（指环盖住根部）
	# （_ribbon 顶点序：0..BSEG 上侧、BSEG+1..末位 下侧反序 ⇒ 尖部夹在下标 BSEG / BSEG+1）
	band[0] = spine[0]
	band[band.size() - 1] = spine[0]
	band[BSEG] = tip
	band[BSEG + 1] = tip
	_plate(r, band, gold["light"] if front else gold["light"].darkened(0.14), 1.6)
	# 刃口流光（外缘半程）
	var shine := PackedVector2Array()
	for i in range(5, BSEG + 1):
		var n := _normal_at(spine, i) * s
		shine.append(spine[i] + n * halfw[i])
	r.draw_polyline(shine, Color(edge.r, edge.g, edge.b, 0.9), 1.1, true)
	# 鳞纹：刃腹三道短斜线
	for i in range(3):
		var idx := 8 + i * 2
		var n2 := _normal_at(spine, idx) * s
		var a2 := (spine[idx + 1] - spine[idx - 1]).normalized()
		r.draw_line(spine[idx] + n2 * halfw[idx] * 0.7 + a2 * 1.2,
			spine[idx] - n2 * halfw[idx] * 0.7 - a2 * 1.2,
			Color(gold["dark"].r, gold["dark"].g, gold["dark"].b, 0.7), 0.8, true)
	# 龙须突刺 + 龙眼：近尖处
	var hi := 13
	var n3 := _normal_at(spine, hi) * s
	var a3 := (spine[hi + 1] - spine[hi - 1]).normalized()
	var barb_b := spine[hi] + n3 * halfw[hi] * 0.8
	r.draw_colored_polygon(PackedVector2Array([
		barb_b + a3 * 1.6, barb_b - a3 * 1.4, spine[hi] + n3 * (halfw[hi] + L * 0.085),
	]), gold["dark"])
	AdaptiveDraw.circle(r, spine[hi + 1] + n3 * halfw[hi + 1] * 0.35, 0.9, _OUTLINE)
	# 指环：暗底粗环 + 金面
	AdaptiveDraw.arc(r, ring, L * 0.115, 0.0, TAU, _OUTLINE, 3.2, true)
	AdaptiveDraw.arc(r, ring, L * 0.115, 0.0, TAU, gold["dark"].lerp(gold["light"], 0.4), 1.7, true)
