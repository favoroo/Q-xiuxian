class_name ProceduralTurretRenderer
extends Node2D

## 纯矢量机关炮台本体渲染器（冷冽国风）
## 取代 TurretUnit.CoreSprite 那张 48×48 AI 贴图，与角色/敌人/法器/弹丸同一套矢量画风。
##
## 【坐标契约 — 与 TurretUnit.CoreSprite / MuzzlePoint 严格对齐】
##   · 在【画布像素】空间沿 +X 绘制（+X = 炮口/攻击朝向），炮口落在 muzzle_len 附近；
##   · 外部把本节点 scale 设成 0.55（与旧 Sprite2D 同尺寸），节点 rotation 即索敌角；
##   · TurretUnit 的底座正圆阵盘仍由它自己的 _draw 画，本渲染器只负责「盘上那台机体」。
##
## 灰度切换：shape == GENERIC（未实现器形）时由 TurretUnit 保留原贴图显示。
##
## 【2026-10-19 重绘】六种器形按真实器物结构加厚（弩＝弩身+弩槽+弩机匣+绞盘+反曲弩臂+弦；
## 阵盘＝八边盘体+金环刻纹+内井阵眼+八剑放射；炮＝药室+炮身+箍环+炮耳+炮架轮；
## 兽＝足座+躯干+肩Hip机枢齿轮+颅吻+张口；投石＝A 架+转轴+抛臂+配重+索兜；
## 台＝层叠台身+望楼口+台顶火盆+焰梢）。发射点一律落在本地 x=16（×ART_SCALE=24）。

enum TurretShape {
	CROSSBOW,   ## 弩机：弩身 + 弩槽 + 弩机匣 + 反曲弩臂 + 弦（机关弩 / 凝冰机弩）
	ARRAY_DISC, ## 阵盘：八边盘体 + 金环刻纹 + 阵眼 + 八剑放射（剑阵盘）
	CANNON,     ## 炮管：药室 + 炮身 + 箍环 + 炮耳 + 炮架（青木炮）
	BEAST,      ## 机关兽：足座 + 躯干 + 机枢齿轮 + 颅吻张口（喷火兽 / 寒泉兽 / 傀儡兽）
	TREBUCHET,  ## 投石机：A 架 + 转轴 + 抛臂 + 配重 + 索兜（垒石机关 / 藤萝机关）
	TOWER,      ## 烽台：层叠台身 + 望楼口 + 台顶火盆 + 焰梢（烽火台）
	GENERIC,
}

@export var shape: TurretShape = TurretShape.GENERIC
@export var element: String = "metal"
@export var star: int = 1

func configure(p_shape: TurretShape, p_element: String, p_star: int) -> void:
	shape = p_shape
	element = p_element
	star = clampi(p_star, 1, 3)
	queue_redraw()

## 数据表 "turret_shape" 字段 → 枚举（未登记/未实现的一律 GENERIC，调用方据此保留贴图）
static func shape_from_name(s: String) -> TurretShape:
	match s:
		"crossbow":
			return TurretShape.CROSSBOW
		"array_disc":
			return TurretShape.ARRAY_DISC
		"cannon":
			return TurretShape.CANNON
		"beast":
			return TurretShape.BEAST
		"trebuchet":
			return TurretShape.TREBUCHET
		"tower":
			return TurretShape.TOWER
	return TurretShape.GENERIC

## 五行配色：亮面 / 暗面 / 描边流光 / HDR 起辉 / 机座色
func _palette() -> Dictionary:
	match element:
		"wood":
			return {"light": Color(0.62, 0.86, 0.64), "dark": Color(0.30, 0.54, 0.36),
				"edge": Color(0.55, 1.0, 0.72), "hdr": GameStyle.FX_HDR_WOOD,
				"frame": Color(0.26, 0.24, 0.16)}
		"fire":
			return {"light": Color(0.96, 0.62, 0.30), "dark": Color(0.66, 0.26, 0.10),
				"edge": Color(1.0, 0.86, 0.42), "hdr": GameStyle.FX_HDR_FIRE,
				"frame": Color(0.22, 0.14, 0.10)}
		"water":
			return {"light": Color(0.66, 0.88, 1.0), "dark": Color(0.30, 0.54, 0.78),
				"edge": Color(0.62, 0.96, 1.0), "hdr": GameStyle.FX_HDR_WATER,
				"frame": Color(0.16, 0.20, 0.26)}
		"earth":
			return {"light": Color(0.82, 0.74, 0.56), "dark": Color(0.48, 0.40, 0.28),
				"edge": Color(0.92, 0.80, 0.44), "hdr": GameStyle.FX_HDR_EARTH,
				"frame": Color(0.20, 0.17, 0.13)}
		_:
			return {"light": Color(0.86, 0.90, 0.96), "dark": Color(0.52, 0.58, 0.68),
				"edge": Color(1.0, 0.88, 0.45), "hdr": GameStyle.FX_HDR_METAL,
				"frame": Color(0.18, 0.18, 0.22)}

## 统一暗描边（全渲染器唯一的轮廓色，粗暗边是小尺度可读的第一保险）
const OUTLINE := Color(0.05, 0.06, 0.09, 0.95)
## 骨白亮面基色（受光面/弦/獠牙/晶棱高光共用）
const BONE := Color(0.94, 0.93, 0.86)
## 膛口/兽口等"黑洞"色
const VOID := Color(0.03, 0.035, 0.055, 0.96)

## 本地 x=16 即炮口（×ART_SCALE = 24 = MuzzlePoint 本地 x）
const MUZZLE_X := 16.0

func _draw() -> void:
	# 统一放大 1.5：各器形都把「炮口/兽口/臂端」画在本地 x=16，×1.5 = 24 —— 正好等于
	# TurretUnit 的 MuzzlePoint 在 CoreSprite 里的本地 x。本节点 scale=1（继承 CoreSprite 的
	# 0.55），于是「炮口画在哪 == 弹丸从哪出」，与旧贴图出膛点同源。
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(ART_SCALE, ART_SCALE))
	match shape:
		TurretShape.CROSSBOW:
			_draw_crossbow()
		TurretShape.ARRAY_DISC:
			_draw_array_disc()
		TurretShape.CANNON:
			_draw_cannon()
		TurretShape.BEAST:
			_draw_beast()
		TurretShape.TREBUCHET:
			_draw_trebuchet()
		TurretShape.TOWER:
			_draw_tower()

# ---------------- 通用构件 ----------------

## 带暗色描边的填充多边形（与法器渲染器同款：外圈暗底 + 内缩亮面）
func _fill_outlined(pts: PackedVector2Array, fill: Color) -> void:
	draw_colored_polygon(pts, Color(0.06, 0.07, 0.10, 0.88))
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= float(pts.size())
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(c.lerp(p, 0.94))
	draw_colored_polygon(inner, fill)

## 描边线段：暗底粗线打底 + 本色细线（细长在 26px 尺度下也必须留得住轮廓）
func _stroke(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	draw_line(a, b, OUTLINE, w + 1.5, true)
	draw_line(a, b, col, w, true)

## 描边折线：整条骨架一次打暗底再上本色（弩臂/支架/焰梢等曲线构件）
func _poly_stroke(pts: PackedVector2Array, col: Color, w: float) -> void:
	draw_polyline(pts, OUTLINE, w + 1.5, true)
	draw_polyline(pts, col, w, true)

## 轴对齐矩形四点（左上/右下）
func _box(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])

## 沿折线骨架按宽度渐变铺出条带（弩臂/炮身箍/焰梢等"有粗细变化的杆件"）
func _band(pts: PackedVector2Array, w0: float, w1: float) -> PackedVector2Array:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var n := pts.size()
	for i in range(n):
		var t := float(i) / float(maxi(n - 1, 1))
		var w := lerpf(w0, w1, t)
		var dir := Vector2.RIGHT
		if i == 0:
			dir = (pts[1] - pts[0]).normalized()
		elif i == n - 1:
			dir = (pts[n - 1] - pts[n - 2]).normalized()
		else:
			dir = (pts[i + 1] - pts[i - 1]).normalized()
		var perp := Vector2(-dir.y, dir.x)
		left.append(pts[i] + perp * w)
		right.append(pts[i] - perp * w)
	var out := PackedVector2Array()
	out.append_array(left)
	for i in range(right.size() - 1, -1, -1):
		out.append(right[i])
	return out

## 铆钉 / 机枢小圆（暗底 + 本色芯）
func _rivet(c: Vector2, r: float, col: Color) -> void:
	AdaptiveDraw.circle(self, c, r + 0.6, OUTLINE)
	AdaptiveDraw.circle(self, c, r, col)

## 齿轮（机关兽肩枢 / 炮车轮 / 弩机绞盘共用的"机关"符号）
func _gear(c: Vector2, r: float, teeth: int, col: Color, hub: Color) -> void:
	for i in range(teeth):
		var a := TAU * float(i) / float(teeth)
		var dir := Vector2(cos(a), sin(a))
		draw_line(c + dir * r * 0.80, c + dir * r * 1.30, OUTLINE, 2.2, true)
		draw_line(c + dir * r * 0.80, c + dir * r * 1.30, col, 1.2, true)
	AdaptiveDraw.circle(self, c, r * 1.06, OUTLINE)
	AdaptiveDraw.circle(self, c, r * 0.94, col)
	AdaptiveDraw.circle(self, c, r * 0.36, hub)

## 晶棱（冰晶 / 翠玉共用）：五棱尖晶 + 中脊高光
func _crystal(c: Vector2, r: float, col: Color) -> void:
	_fill_outlined(PackedVector2Array([
		c + Vector2(0.0, -r * 1.45), c + Vector2(r * 0.66, -r * 0.28),
		c + Vector2(r * 0.40, r * 1.02), c + Vector2(-r * 0.40, r * 1.02),
		c + Vector2(-r * 0.66, -r * 0.28),
	]), col)
	draw_line(c + Vector2(0.0, -r * 1.35), c + Vector2(0.0, r * 0.9),
		Color(1.0, 1.0, 1.0, 0.5), 0.7, true)

## 核心起辉 + 升星强化（★2 双肩灵光点，★3 环身辉圈）
func _draw_core_fx(pal: Dictionary, center: Vector2, r0: float) -> void:
	var r := r0 * (1.0 + 0.22 * float(star - 1))
	AdaptiveDraw.circle(self, center, r * 2.1, Color(pal["hdr"].r, pal["hdr"].g, pal["hdr"].b, 0.24))
	AdaptiveDraw.circle(self, center, r, pal["hdr"])
	AdaptiveDraw.circle(self, center, r * 0.5, Color(1.0, 1.0, 1.0, 0.95))
	if star >= 2:
		for i in range(2):
			var a := PI * 0.5 + PI * float(i)
			AdaptiveDraw.circle(self, center + Vector2(cos(a), sin(a)) * r * 2.6, r * 0.42,
				Color(pal["edge"].r, pal["edge"].g, pal["edge"].b, 0.85))
	if star >= 3:
		AdaptiveDraw.arc(self, center, r * 2.9, 0.0, TAU,
			Color(pal["edge"].r, pal["edge"].g, pal["edge"].b, 0.55), 1.0, true)

## 机座（炮台扎根盘面的暗色底盘）
## 注意：draw_set_transform 是「替换」而非「叠乘」，这里必须把 _draw 头部的 ART_SCALE
## 一起带上，画完再恢复，否则后续器身会退回 1.0 比例、炮口与 MuzzlePoint 分家。
## 2026-10-22：机座改正圆（原 0.62 y 压扁随索敌转向晃成椭圆；正圆旋转不变形）
const ART_SCALE := 1.5

func _draw_mount(pal: Dictionary, rx: float) -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(ART_SCALE, ART_SCALE))
	AdaptiveDraw.circle(self, Vector2.ZERO, rx, Color(0.03, 0.04, 0.06, 0.55))
	AdaptiveDraw.circle(self, Vector2.ZERO, rx * 0.78, pal["frame"])

# ---------------- 弩机（弩身 + 弩槽 + 弩机匣 + 反曲弩臂 + 弦） ----------------
## 一眼读成"弩"的三剪影特征：横置反曲双臂 + 骨白长弦挂到机牙 + 沿 +X 的长弩身与出鞘弩箭。
## 金＝单箭青铜机弩；水＝凝冰三连弩（多晶棱、冰壳覆臂）。
func _draw_crossbow() -> void:
	var pal := _palette()
	var ice := element == "water"
	var lite: Color = pal["light"]
	var face: Color = pal["light"].lerp(BONE, 0.40)
	var shade: Color = pal["dark"]
	var wood: Color = pal["frame"].lerp(pal["dark"], 0.30)
	_draw_mount(pal, 11.0)

	# 反曲弩臂：从机匣两侧向前外张出、再回勾到梢（先画，压在弩身之下）
	for s in [-1.0, 1.0]:
		var spine := PackedVector2Array([
			Vector2(2.4, s * 2.4), Vector2(0.0, s * 6.4),
			Vector2(-4.4, s * 10.0), Vector2(-6.6, s * 11.8),
		])
		_fill_outlined(_band(spine, 2.2, 0.9), lite if ice else shade.lightened(0.10))
		# 臂梢滑轮（弦槽）
		_rivet(Vector2(-6.6, s * 11.8), 1.0, pal["edge"])
	# 弩弦：两梢之间向后挂到机牙（待发状态 = 折成 V）
	var string_pts := PackedVector2Array([
		Vector2(-6.6, -11.8), Vector2(-9.2, 0.0), Vector2(-6.6, 11.8)])
	draw_polyline(string_pts, OUTLINE, 2.4, true)
	draw_polyline(string_pts, BONE, 1.1, true)

	# 弩身（沿 +X 的长木骨，前细后粗）
	_fill_outlined(PackedVector2Array([
		Vector2(MUZZLE_X, -1.7), Vector2(MUZZLE_X, 1.7), Vector2(1.0, 2.9),
		Vector2(-9.0, 3.4), Vector2(-13.6, 2.2), Vector2(-13.6, -2.0),
		Vector2(-9.0, -3.1), Vector2(1.0, -2.8),
	]), wood)
	# 受光骨面（上半亮、下半暗，纯平两块）
	draw_colored_polygon(PackedVector2Array([
		Vector2(MUZZLE_X - 0.6, -0.3), Vector2(1.0, -0.4), Vector2(-9.0, -0.6),
		Vector2(-13.2, -0.6), Vector2(-13.2, -1.9), Vector2(-9.0, -2.8),
		Vector2(1.0, -2.5), Vector2(MUZZLE_X - 0.6, -1.4),
	]), face)
	# 弩槽（轨道两道暗沟 + 中央亮脊）
	draw_line(Vector2(-9.0, -1.15), Vector2(14.6, -0.62), OUTLINE, 1.3, true)
	draw_line(Vector2(-9.0, 1.15), Vector2(14.6, 0.62), OUTLINE, 1.3, true)
	draw_line(Vector2(-9.0, 0.0), Vector2(15.0, 0.0), Color(pal["edge"].r, pal["edge"].g, pal["edge"].b, 0.45), 0.9, true)
	# 弩托尾（后端铜帽 + 挂环）
	_fill_outlined(_box(-15.0, -2.6, -12.8, 2.8), pal["edge"].darkened(0.18))
	_rivet(Vector2(-14.0, 0.0), 0.9, wood)

	# 弩机匣（牙 + 望山 + 悬刀）：机括方匣压在弩身中段
	_fill_outlined(_box(-4.6, -4.0, 3.0, 4.0), pal["frame"].lerp(lite, 0.20))
	# 绞盘齿轮（上弦机构）
	_gear(Vector2(-0.6, 0.0), 2.5, 7, pal["edge"].darkened(0.10), wood)
	# 望山（瞄准缺口的立牙）+ 悬刀（扳机，向后下方伸出）
	_fill_outlined(PackedVector2Array([
		Vector2(2.0, -4.0), Vector2(3.2, -4.0), Vector2(3.2, -6.6), Vector2(2.0, -6.0),
	]), pal["edge"])
	_poly_stroke(PackedVector2Array([Vector2(-0.4, 3.6), Vector2(-2.2, 6.6), Vector2(-4.6, 7.6)]),
		pal["edge"].darkened(0.12), 1.5)

	# 弩箭：主箭沿 +X，箭尖正落在炮口 x=16
	_draw_bolt(pal, Vector2(0.0, 0.0), MUZZLE_X, ice)
	if ice:
		# 凝冰三连弩：上下两路副箭（短半格，主箭仍守炮口）
		_draw_bolt(pal, Vector2(0.0, -3.3), 13.2, true)
		_draw_bolt(pal, Vector2(0.0, 3.3), 13.2, true)
		# 冰壳覆臂 + 机匣霜晶
		_crystal(Vector2(1.6, -5.6), 2.0, lite)
		_crystal(Vector2(1.6, 5.6), 2.0, lite)
		_crystal(Vector2(-8.4, -5.2), 1.6, lite)
		_crystal(Vector2(-8.4, 5.2), 1.6, lite)
		_crystal(Vector2(-11.0, 0.0), 2.2, lite)
		# 霜环套住箭口
		AdaptiveDraw.arc(self, Vector2(MUZZLE_X - 1.0, 0.0), 3.4, 0.0, TAU,
			Color(pal["edge"].r, pal["edge"].g, pal["edge"].b, 0.7), 1.2, true)
	else:
		# 机关弩：弩臂根部的铜饰 + 机匣两侧铆钉
		for s in [-1.0, 1.0]:
			_rivet(Vector2(2.2, s * 4.6), 1.0, pal["edge"])
		_fill_outlined(PackedVector2Array([
			Vector2(-6.4, -3.4), Vector2(-6.4, 3.4), Vector2(-9.4, 3.0), Vector2(-9.4, -3.0),
		]), pal["edge"].darkened(0.22))
	# 机枢起辉（升星机制入口）
	_draw_core_fx(pal, Vector2(-0.6, 0.0), 1.3)

## 单支弩箭：箭杆 + 尾羽 + 箭尖（tip_x 决定落点，主箭必须落在 MUZZLE_X）
func _draw_bolt(pal: Dictionary, base: Vector2, tip_x: float, ice: bool) -> void:
	var tail := base.x - 5.4
	# 箭杆
	draw_line(Vector2(tail, base.y), Vector2(tip_x, base.y), OUTLINE, 2.3, true)
	draw_line(Vector2(tail, base.y), Vector2(tip_x, base.y), BONE, 1.15, true)
	# 尾羽（两片后掠）
	for s in [-1.0, 1.0]:
		draw_colored_polygon(PackedVector2Array([
			Vector2(tail + 0.4, base.y), Vector2(tail - 2.6, base.y + s * 2.0),
			Vector2(tail + 1.6, base.y + s * 0.7),
		]), pal["edge"].darkened(0.15))
	# 箭尖
	if ice:
		_crystal(Vector2(tip_x - 0.8, base.y), 1.5, pal["light"])
	else:
		_fill_outlined(PackedVector2Array([
			Vector2(tip_x, base.y), Vector2(tip_x - 3.4, base.y - 1.5),
			Vector2(tip_x - 3.4, base.y + 1.5),
		]), pal["edge"])

# ---------------- 阵盘（八边盘体 + 金环刻纹 + 阵眼 + 八剑放射） ----------------
## 剑阵盘＝「石盘 + 环刻阵纹 + 盘心阵眼 + 八口小剑穿盘而出」；+X 那口剑的剑尖即炮口。
func _draw_array_disc() -> void:
	var pal := _palette()
	var edge: Color = pal["edge"]
	var face: Color = pal["light"].lerp(BONE, 0.30)
	# 八口小剑（先画，剑根压在盘体之下 ⇒ 剑像从盘缘里穿出来）
	for i in range(8):
		var a := TAU * float(i) / 8.0
		var dir := Vector2(cos(a), sin(a))
		var perp := Vector2(-dir.y, dir.x)
		var root := dir * 8.4
		var tip := dir * (MUZZLE_X if i == 0 else 15.4)
		# 剑身（骨白双刃，中脊压暗）
		_fill_outlined(PackedVector2Array([
			tip, root + perp * 1.55, root - perp * 1.55,
		]), face)
		draw_line(root, tip, Color(0.10, 0.11, 0.15, 0.85), 0.8, true)
		# 剑格（铜色横档）+ 剑首
		draw_line(root + perp * 2.5, root - perp * 2.5, edge, 1.7, true)
		_rivet(dir * 6.6, 0.8, edge.darkened(0.15))
	# 盘体：外八边（暗石）→ 斜面亮环 → 内井（近黑）
	var oct_o := PackedVector2Array()
	var oct_m := PackedVector2Array()
	for i in range(8):
		var a := TAU * (float(i) + 0.5) / 8.0
		oct_o.append(Vector2(cos(a), sin(a)) * 12.0)
		oct_m.append(Vector2(cos(a), sin(a)) * 10.6)
	_fill_outlined(oct_o, pal["dark"].darkened(0.28))
	_fill_outlined(oct_m, pal["dark"])
	# 斜面受光：只在左上两段打骨白亮边（纯平色块，不做渐变）
	for i in [4, 5]:
		var p0: Vector2 = oct_m[i]
		var p1: Vector2 = oct_m[(i + 1) % 8]
		draw_colored_polygon(PackedVector2Array([p0, p1, p1 * 0.90, p0 * 0.90]),
			Color(face.r, face.g, face.b, 0.5))
	# 金环阵纹 + 环上刻纹短齿
	AdaptiveDraw.arc(self, Vector2.ZERO, 8.4, 0.0, TAU, edge, 1.6, true)
	AdaptiveDraw.arc(self, Vector2.ZERO, 6.9, 0.0, TAU,
		Color(edge.r, edge.g, edge.b, 0.55), 1.0, true)
	var ticks := 16 + 4 * (star - 1)
	for i in range(ticks):
		var a := TAU * float(i) / float(ticks)
		var dir := Vector2(cos(a), sin(a))
		draw_line(dir * 7.2, dir * 8.1, Color(edge.r, edge.g, edge.b, 0.85), 0.9, true)
	# 盘心内井 + 阵眼
	AdaptiveDraw.circle(self, Vector2.ZERO, 5.6, Color(0.04, 0.05, 0.075, 0.96))
	AdaptiveDraw.arc(self, Vector2.ZERO, 5.6, 0.0, TAU, Color(0.02, 0.025, 0.04, 0.9), 1.2, true)
	_draw_core_fx(pal, Vector2.ZERO, 1.9)

# ---------------- 炮（药室 + 炮身 + 箍环 + 炮耳 + 炮架） ----------------
## 青木炮＝整段原木掏膛的重炮：后段方药室、前段喇叭口、铜箍三道、双轮炮架。
func _draw_cannon() -> void:
	var pal := _palette()
	var edge: Color = pal["edge"]
	var lite: Color = pal["light"]
	var face: Color = pal["light"].lerp(BONE, 0.34)
	var shade: Color = pal["dark"]
	var timber: Color = pal["frame"].lerp(pal["dark"], 0.42)
	_draw_mount(pal, 12.0)

	# 炮架：斜置双颊木 + 后拖尾 + 双轮（先画，炮身压在架上）
	_fill_outlined(PackedVector2Array([
		Vector2(-11.6, 8.6), Vector2(-8.6, 1.6), Vector2(2.6, 1.6), Vector2(5.6, 8.6),
		Vector2(2.6, 8.6), Vector2(1.0, 4.6), Vector2(-6.0, 4.6), Vector2(-8.6, 8.6),
	]), timber)
	_fill_outlined(PackedVector2Array([
		Vector2(-15.0, 8.8), Vector2(-11.0, 8.8), Vector2(-11.0, 5.4), Vector2(-14.0, 4.6),
	]), timber)
	_gear(Vector2(-7.4, 7.4), 3.4, 6, timber.lightened(0.10), shade)
	_gear(Vector2(-14.2, 7.0), 2.2, 6, timber.lightened(0.06), shade)
	# 炮耳（架与身的轴榫）
	for s in [-1.0, 1.0]:
		_rivet(Vector2(-0.4, s * 5.0), 1.5, edge.darkened(0.18))

	# 药室（尾段方匣）
	_fill_outlined(_box(-13.4, -4.6, -8.2, 4.6), shade)
	draw_line(Vector2(-13.4, -1.6), Vector2(-8.4, -1.6), Color(face.r, face.g, face.b, 0.55), 1.0, true)
	_rivet(Vector2(-10.8, 0.0), 1.2, edge)
	# 炮身（前细后粗再放喇叭口，沿 +X）
	_fill_outlined(PackedVector2Array([
		Vector2(-9.0, -4.2), Vector2(6.0, -4.4), Vector2(11.4, -5.6), Vector2(MUZZLE_X, -5.9),
		Vector2(MUZZLE_X, 5.9), Vector2(11.4, 5.6), Vector2(6.0, 4.4), Vector2(-9.0, 4.2),
	]), lite.darkened(0.10))
	# 受光面 / 背光面（上下两块纯平色）
	draw_colored_polygon(PackedVector2Array([
		Vector2(-9.0, -4.0), Vector2(6.0, -4.2), Vector2(11.4, -5.4), Vector2(15.4, -5.7),
		Vector2(15.4, -1.2), Vector2(-9.0, -1.0),
	]), face)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-9.0, 1.6), Vector2(15.4, 1.9), Vector2(15.4, 5.7), Vector2(11.4, 5.4),
		Vector2(6.0, 4.2), Vector2(-9.0, 4.0),
	]), shade)
	# 木纹（沿身的两道细暗线）
	for y in [-2.6, 3.0]:
		draw_line(Vector2(-7.0, y), Vector2(12.0, y * 1.15), Color(0.06, 0.08, 0.10, 0.45), 0.9, true)
	# 箍环三道（铜口）
	for x in [-5.0, 2.0, 12.8]:
		var h: float = 4.3 + (float(x) + 5.0) * 0.11
		_stroke(Vector2(float(x), -h), Vector2(float(x), h), edge.darkened(0.12), 1.9)
	# 刻纹（炮身侧面的「木」字道纹，小尺度读成"青木"而非铁炮）
	draw_line(Vector2(-1.6, -2.6), Vector2(-1.6, 2.2), Color(0.06, 0.08, 0.10, 0.75), 1.1, true)
	draw_line(Vector2(-3.4, -1.0), Vector2(0.2, -1.0), Color(0.06, 0.08, 0.10, 0.75), 1.1, true)
	draw_line(Vector2(-3.2, 1.4), Vector2(0.0, 1.4), Color(0.06, 0.08, 0.10, 0.75), 1.1, true)
	# 炮口：喇叭口端面 + 内膛黑洞 + 膛内起辉
	AdaptiveDraw.circle(self, Vector2(MUZZLE_X, 0.0), 4.6, edge.darkened(0.20))
	AdaptiveDraw.circle(self, Vector2(MUZZLE_X, 0.0), 3.5, Color(0.04, 0.05, 0.08))
	_draw_core_fx(pal, Vector2(MUZZLE_X - 0.6, 0.0), 1.7)

# ---------------- 机关兽（足座 + 躯干 + 机枢齿轮 + 颅吻张口） ----------------
## 小尺度读成"兽"的三剪影：楔形颅吻（口在 +X 炮口）+ 后掠双角 + 背甲/鬃棱；
## 躯干与四肢只做机关化的方块与齿轮，元素差异全落在「口部机构 + 背甲形态」两处。
func _draw_beast() -> void:
	var pal := _palette()
	var edge: Color = pal["edge"]
	var lite: Color = pal["light"]
	var face: Color = pal["light"].lerp(BONE, 0.36)
	var shade: Color = pal["dark"]
	var plate: Color = pal["frame"].lerp(pal["dark"], 0.30)
	var heavy := element == "earth"          ## 傀儡兽：整体加宽、岩甲压背
	_draw_mount(pal, 12.0)

	# 足与底座（前/后各一腿 + 贴地踏板）
	for x in [6.0, -7.0]:
		_fill_outlined(PackedVector2Array([
			Vector2(x - 2.0, 1.0), Vector2(x + 2.2, 1.0), Vector2(x + 2.8, 7.0),
			Vector2(x - 2.6, 7.0),
		]), plate)
		_fill_outlined(_box(x - 3.4, 6.6, x + 3.8, 9.2), shade)
		_rivet(Vector2(x + 0.1, 3.6), 1.3, edge.darkened(0.20))
	draw_line(Vector2(-9.0, 8.0), Vector2(8.0, 8.0), OUTLINE, 2.2, true)
	# 胯/肩机枢齿轮（"机关"二字的来源）
	_gear(Vector2(-6.8, 0.6), 3.0, 7, plate.lightened(0.10), shade)
	_gear(Vector2(5.6, 0.2), 2.4, 6, plate.lightened(0.10), shade)

	# 躯干（厚箱形，上亮下暗）
	var body := PackedVector2Array([
		Vector2(7.6, -6.4), Vector2(-4.0, -7.4), Vector2(-10.6, -5.0),
		Vector2(-10.6, 4.4), Vector2(-4.0, 6.4), Vector2(7.6, 5.4),
	])
	_fill_outlined(body, plate if heavy else shade)
	draw_colored_polygon(PackedVector2Array([
		Vector2(7.2, -6.0), Vector2(-4.0, -7.0), Vector2(-10.2, -4.6),
		Vector2(-10.2, -2.2), Vector2(7.2, -2.6),
	]), (lite if heavy else plate).lightened(0.10))
	# 躯干侧面的甲片缝（三道短竖线）
	for i in range(3):
		var x := -7.0 + float(i) * 4.2
		draw_line(Vector2(x, -2.0), Vector2(x, 3.6), Color(0.05, 0.06, 0.09, 0.7), 1.0, true)

	# 背甲 / 鬃棱（元素差异①）
	match element:
		"water":
			# 寒泉兽：沿脊柱一排冰棱
			for i in range(5):
				var t := float(i) / 4.0
				var bx := lerpf(-8.0, 6.0, t)
				var hgt := lerpf(3.4, 5.2, sin(t * PI))
				_fill_outlined(PackedVector2Array([
					Vector2(bx - 1.5, -6.6), Vector2(bx + 0.4, -6.6 - hgt), Vector2(bx + 2.0, -6.4),
				]), lite)
		"earth":
			# 傀儡兽：背负岩甲乱石（两块大岩 + 一块压顶）
			_fill_outlined(PackedVector2Array([
				Vector2(-9.6, -6.2), Vector2(-6.0, -11.4), Vector2(-0.6, -9.6), Vector2(-2.0, -6.0),
			]), shade.lightened(0.14))
			_fill_outlined(PackedVector2Array([
				Vector2(-1.4, -8.0), Vector2(2.6, -12.6), Vector2(7.4, -8.6), Vector2(5.0, -6.2),
			]), lite.darkened(0.16))
			_rivet(Vector2(-5.0, -8.6), 1.1, edge.darkened(0.30))
		_:
			# 喷火兽：颈后火鬃（三片火舌向后上方挑）
			for i in range(3):
				var t := float(i) / 2.0
				var bx := lerpf(-2.0, 6.4, t)
				_fill_outlined(PackedVector2Array([
					Vector2(bx - 1.4, -6.2), Vector2(bx + 1.2, -11.6 + t * 1.8), Vector2(bx + 2.6, -6.0),
				]), Color(pal["hdr"].r, pal["hdr"].g, pal["hdr"].b, 0.9))

	# 后掠双角
	for s in [-1.0, 1.0]:
		_fill_outlined(PackedVector2Array([
			Vector2(9.6, s * 4.6), Vector2(4.2, s * 10.4), Vector2(7.6, s * 4.0),
		]), shade.darkened(0.22))

	# 颅吻（楔形：后宽前窄，口落在 +X 炮口）
	_fill_outlined(PackedVector2Array([
		Vector2(MUZZLE_X, -2.6), Vector2(12.8, -5.6), Vector2(7.4, -6.4),
		Vector2(7.4, 6.4), Vector2(12.8, 5.6), Vector2(MUZZLE_X, 2.6),
	]), face if not heavy else lite.darkened(0.06))
	# 额甲 + 鼻梁脊线
	draw_colored_polygon(PackedVector2Array([
		Vector2(12.4, -5.0), Vector2(8.0, -5.8), Vector2(8.0, -2.6), Vector2(13.6, -2.2),
	]), shade)
	draw_line(Vector2(15.4, 0.0), Vector2(8.6, 0.0), Color(0.06, 0.06, 0.09, 0.85), 1.2, true)
	# 兽眼（起辉）
	_draw_core_fx(pal, Vector2(10.0, -3.2), 1.15)

	# 张口（元素差异②）：喉膛黑洞一律画到 x=16，保证"弹丸从口出"
	draw_colored_polygon(PackedVector2Array([
		Vector2(MUZZLE_X + 0.4, -2.0), Vector2(9.4, -0.9), Vector2(9.4, 0.9), Vector2(MUZZLE_X + 0.4, 2.0),
	]), VOID)
	match element:
		"fire":
			# 喷火兽：口内火门（喉中一记火锥）+ 上下铜闸 + 獠牙
			draw_colored_polygon(PackedVector2Array([
				Vector2(MUZZLE_X, 0.0), Vector2(10.2, -1.7), Vector2(10.2, 1.7),
			]), Color(pal["hdr"].r, pal["hdr"].g, pal["hdr"].b, 0.92))
			for s in [-1.0, 1.0]:
				_fill_outlined(PackedVector2Array([
					Vector2(MUZZLE_X, s * 2.2), Vector2(11.0, s * 3.0), Vector2(11.0, s * 5.2),
					Vector2(MUZZLE_X, s * 4.0),
				]), edge.darkened(0.22))
				draw_colored_polygon(PackedVector2Array([
					Vector2(14.4, s * 1.7), Vector2(15.9, s * 2.6), Vector2(13.2, s * 2.8),
				]), BONE)
		"water":
			# 寒泉兽：上下冰牙 + 口前霜锥
			for s in [-1.0, 1.0]:
				_crystal(Vector2(14.0, s * 2.6), 1.3, lite)
			_fill_outlined(PackedVector2Array([
				Vector2(MUZZLE_X + 1.0, 0.0), Vector2(11.0, -1.5), Vector2(11.0, 1.5),
			]), Color(pal["edge"].r, pal["edge"].g, pal["edge"].b, 0.85))
		_:
			# 傀儡兽：石栅封口（两道竖闸，像磨盘出料口）
			for x in [12.2, 14.6]:
				draw_line(Vector2(x, -1.8), Vector2(x, 1.8), BONE.darkened(0.25), 1.2, true)
			for s in [-1.0, 1.0]:
				_fill_outlined(PackedVector2Array([
					Vector2(MUZZLE_X, s * 2.4), Vector2(10.6, s * 3.2), Vector2(10.6, s * 5.6),
					Vector2(MUZZLE_X, s * 4.4),
				]), shade)

# ---------------- 投石机（A 架 + 转轴 + 抛臂 + 配重 + 索兜） ----------------
## 垒石机关（土）＝深色木 A 架 + 石弹索兜；藤萝机关（木）＝竹白抛臂缠藤、兜里换翠玉晶。
## 抛臂前扬、索兜垂到 x=16 —— 兜中之弹正是出膛的那一发。
func _draw_trebuchet() -> void:
	var pal := _palette()
	var edge: Color = pal["edge"]
	var vine := element == "wood"
	var lite: Color = pal["light"]
	var timber: Color = (lite.lerp(BONE, 0.45) if vine else pal["frame"].lerp(pal["dark"], 0.34))
	var dark: Color = pal["dark"].darkened(0.18)
	_draw_mount(pal, 12.5)

	# 底梁 + 支脚
	_stroke(Vector2(-13.0, 8.8), Vector2(12.0, 8.8), timber, 2.4)
	for x in [-13.0, 12.0]:
		_fill_outlined(_box(x - 1.8, 7.6, x + 1.8, 10.0), dark)
	# A 形支架（双腿 + 横撑）
	_stroke(Vector2(-8.2, 8.4), Vector2(0.6, -2.4), timber, 2.6)
	_stroke(Vector2(8.2, 8.4), Vector2(0.6, -2.4), timber, 2.6)
	_stroke(Vector2(-4.4, 3.6), Vector2(4.8, 3.6), timber.darkened(0.12), 1.8)
	# 支架上的垛口刻纹（土机关的方孔）
	if not vine:
		for i in range(2):
			var y := 5.6 - float(i) * 2.6
			draw_rect(Rect2(-2.0, y, 2.0, 1.6), Color(0.05, 0.06, 0.09, 0.75), true)

	# 抛臂：尾低（挂配重）→ 过转轴 → 前扬到臂端
	var tail_pt := Vector2(-11.6, 5.4)
	var tip_pt := Vector2(9.6, -8.6)
	_fill_outlined(_band(PackedVector2Array([tail_pt, Vector2(0.6, -2.4), tip_pt]), 2.0, 1.3),
		timber.lightened(0.08))
	if vine:
		# 缠藤：沿臂三道藤环 + 三片叶
		for i in range(3):
			var t := 0.25 + float(i) * 0.28
			var p: Vector2 = tail_pt.lerp(tip_pt, t)
			AdaptiveDraw.arc(self, p, 2.4, -0.9, 2.2, Color(edge.r, edge.g, edge.b, 0.85), 1.1, true)
		for i in range(3):
			var t := 0.18 + float(i) * 0.32
			var p: Vector2 = tail_pt.lerp(tip_pt, t)
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(-0.6, -1.6), p + Vector2(2.4, -3.4), p + Vector2(1.4, -0.6),
			]), lite)
	else:
		# 木臂榫钉
		for i in range(3):
			var t := 0.2 + float(i) * 0.3
			_rivet(tail_pt.lerp(tip_pt, t), 0.9, edge.darkened(0.15))
	# 转轴齿轮（臂与架的枢轴）
	_gear(Vector2(0.6, -2.4), 3.2, 8, dark.lightened(0.16), edge.darkened(0.25))
	# 臂端滑轮
	_rivet(tip_pt, 1.3, edge)

	# 配重（尾端吊石匣）：两道吊索 + 一块方匣
	draw_line(tail_pt, Vector2(-13.4, 6.4), BONE.darkened(0.30), 0.9, true)
	draw_line(tail_pt, Vector2(-10.2, 6.4), BONE.darkened(0.30), 0.9, true)
	if vine:
		# 藤萝：编筐配重（横竖织纹）
		_fill_outlined(_box(-14.2, 6.0, -9.0, 10.2), timber.darkened(0.10))
		for i in range(2):
			var y := 7.2 + float(i) * 2.0
			draw_line(Vector2(-14.0, y), Vector2(-9.2, y), edge.darkened(0.10), 1.0, true)
	else:
		# 垒石：厚土石匣（刻一道「土」字纹）
		_fill_outlined(_box(-14.2, 5.8, -9.0, 10.4), lite.darkened(0.24))
		draw_line(Vector2(-13.0, 7.0), Vector2(-10.2, 7.0), Color(0.06, 0.07, 0.10, 0.8), 1.1, true)
		draw_line(Vector2(-11.6, 7.0), Vector2(-11.6, 9.4), Color(0.06, 0.07, 0.10, 0.8), 1.1, true)

	# 索兜 + 弹（兜中之物中心正落在 x=16 = 炮口）
	var ammo := Vector2(MUZZLE_X, 0.0)
	draw_line(tip_pt, ammo + Vector2(-2.6, -1.6), BONE.darkened(0.28), 0.9, true)
	draw_line(tip_pt, ammo + Vector2(-1.4, 3.0), BONE.darkened(0.28), 0.9, true)
	_fill_outlined(PackedVector2Array([
		ammo + Vector2(-3.4, 1.2), ammo + Vector2(3.4, 1.2), ammo + Vector2(2.0, 4.0),
		ammo + Vector2(-2.2, 4.0),
	]), dark)
	if vine:
		_crystal(ammo, 2.6, lite)
	else:
		# 石弹：多棱乱石 + 顶面受光
		_fill_outlined(PackedVector2Array([
			ammo + Vector2(-0.4, -3.2), ammo + Vector2(2.8, -1.4), ammo + Vector2(2.2, 2.2),
			ammo + Vector2(-2.4, 2.6), ammo + Vector2(-3.0, -1.2),
		]), lite.darkened(0.18))
		draw_line(ammo + Vector2(-2.4, -1.6), ammo + Vector2(2.0, -1.2),
			Color(BONE.r, BONE.g, BONE.b, 0.45), 1.0, true)
		# 备弹两枚（压在底梁上，读成"垒石"）
		_rivet(Vector2(6.6, 6.4), 2.2, lite.darkened(0.26))
		_rivet(Vector2(9.4, 7.0), 1.6, lite.darkened(0.34))
	_draw_core_fx(pal, Vector2(0.6, -2.4), 1.3)

# ---------------- 烽台（层叠台身 + 望楼口 + 台顶火盆 + 焰梢） ----------------
## 烽火台保持竖直剪影（三层收分台身 + 压顶横沿 + 女墙），台顶火盆的焰梢向 +X 甩出、
## 焰尖正落在 x=16 —— 炮台转向索敌时，等于"烽烟朝着敌人扫过去"，出膛点与判定同源。
func _draw_tower() -> void:
	var pal := _palette()
	var edge: Color = pal["edge"]
	var hdr: Color = pal["hdr"]
	var stone: Color = pal["dark"].darkened(0.16)
	var stone_lit: Color = pal["light"].lerp(BONE, 0.22)
	_draw_mount(pal, 11.0)

	# 三层收分台身（自下而上），每层顶一道外挑横沿
	var tiers := [
		{"y0": 9.0, "y1": 2.0, "x0": 9.4, "x1": 7.0, "eave": 8.6},
		{"y0": 2.0, "y1": -4.2, "x0": 6.6, "x1": 5.0, "eave": 6.2},
		{"y0": -4.2, "y1": -9.6, "x0": 4.6, "x1": 3.6, "eave": 5.4},
	]
	for t in tiers:
		var y0: float = t["y0"]
		var y1: float = t["y1"]
		var x0: float = t["x0"]
		var x1: float = t["x1"]
		_fill_outlined(PackedVector2Array([
			Vector2(-x0, y0), Vector2(x0, y0), Vector2(x1, y1), Vector2(-x1, y1),
		]), stone)
		# 受光左半 + 背光右半（纯平两块，出体积）
		draw_colored_polygon(PackedVector2Array([
			Vector2(-x0 + 0.6, y0 - 0.6), Vector2(-0.6, y0 - 0.6),
			Vector2(-0.6, y1 + 0.6), Vector2(-x1 + 0.6, y1 + 0.6),
		]), Color(stone_lit.r, stone_lit.g, stone_lit.b, 0.30))
		# 挑沿（压顶的横条，向两侧探出）
		_fill_outlined(_box(-t["eave"], y1 - 1.8, t["eave"], y1 + 0.2), stone.lightened(0.10))
	# 砌筑缝（每层两道竖缝 + 一道横线，小尺度读成"砖石"）
	for i in range(tiers.size()):
		var t: Dictionary = tiers[i]
		var y0: float = t["y0"]
		var y1: float = t["y1"]
		draw_line(Vector2(-t["x0"] * 0.55, y1 + 1.2), Vector2(-t["x0"] * 0.55, y0 - 0.6),
			Color(0.05, 0.06, 0.09, 0.6), 0.9, true)
		draw_line(Vector2(t["x0"] * 0.5, y1 + 1.2), Vector2(t["x0"] * 0.5, y0 - 0.6),
			Color(0.05, 0.06, 0.09, 0.6), 0.9, true)
	# 女墙（顶层垛口，三齿）
	for i in range(3):
		var x := -3.0 + float(i) * 3.0
		_fill_outlined(_box(x - 1.0, -11.6, x + 1.0, -9.8), stone_lit.darkened(0.20))
	# 望楼口（中层两道暗窗 + 窗内火光）
	for x in [-2.4, 1.4]:
		draw_rect(Rect2(x - 0.9, -2.6, 1.8, 3.6), Color(0.04, 0.05, 0.08), true)
		draw_line(Vector2(x, -2.0), Vector2(x, 0.6), Color(hdr.r, hdr.g, hdr.b, 0.85), 1.0, true)
	# 台基门洞（底层正中一道拱口）
	draw_rect(Rect2(-1.6, 4.4, 3.2, 4.6), Color(0.04, 0.05, 0.08), true)
	draw_line(Vector2(-1.6, 4.6), Vector2(1.6, 4.6), edge.darkened(0.20), 1.0, true)

	# 台顶火盆（盆身 + 盆沿）
	_fill_outlined(PackedVector2Array([
		Vector2(-4.0, -12.6), Vector2(4.0, -12.6), Vector2(2.6, -10.6), Vector2(-2.6, -10.6),
	]), pal["frame"].lerp(pal["light"], 0.24))
	draw_line(Vector2(-4.0, -12.8), Vector2(4.0, -12.8), edge, 1.8, true)

	# 焰梢：从火盆口向 +X 甩出，焰尖落在 x=16（= 出膛点）
	var spine := PackedVector2Array([
		Vector2(1.0, -12.4), Vector2(7.6, -11.2), Vector2(12.6, -7.2), Vector2(MUZZLE_X, -0.6),
	])
	_fill_outlined(_band(spine, 3.0, 1.5), Color(hdr.r, hdr.g, hdr.b, 0.80))
	draw_colored_polygon(_band(spine, 1.5, 0.5), Color(edge.r, edge.g, edge.b, 0.95))
	# 焰梢上的三片飞火（沿骨架外挑的小三角）
	for i in range(3):
		var t := 0.3 + float(i) * 0.24
		var p: Vector2 = spine[1].lerp(spine[2], t)
		draw_colored_polygon(PackedVector2Array([
			p + Vector2(-0.6, -1.2), p + Vector2(1.6, -4.2), p + Vector2(1.8, -1.0),
		]), Color(hdr.r, hdr.g, hdr.b, 0.7))
	# 盆中火核 + 焰尖起辉（升星机制入口）
	_draw_core_fx(pal, Vector2(0.0, -12.8), 1.35)
	_draw_core_fx(pal, Vector2(MUZZLE_X - 0.4, 0.0), 1.5)
