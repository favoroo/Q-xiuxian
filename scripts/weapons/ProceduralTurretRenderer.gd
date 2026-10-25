class_name ProceduralTurretRenderer
extends Node2D

## 纯矢量机关炮台本体渲染器（新野兽派：平涂色块 + 粗墨描边 + 右下硬偏移投影）
## 画法纪律与共用构件见 shapes/BrutalistCommon.gd（零辉光 / 零渐变 / 零装饰纹）；
## 每件机关 = 五行主色一大块 + 撞色一处 + 墨黑，升星只走 BC.star_studs 撞色方钉。
## 注意：本渲染器局部空间（16 单位）比重器族的 26 单位小，且整体 ×ART_SCALE=1.5，
## 描边 ow 一律收窄到 0.6~1.6，否则墨线吞掉色块（细构件只剩黑团）。
##
## 【坐标契约 — 与 TurretUnit.CoreSprite / MuzzlePoint 严格对齐，不得改动】
##   · 在【画布像素】空间沿 +X 绘制（+X = 炮口/攻击朝向），炮口/兽口/臂端/焰尖落在本地 x=16；
##   · 外部把本节点 scale 设成 0.55（与旧 Sprite2D 同尺寸），节点 rotation 即索敌角；
##   · TurretUnit 的底座正圆阵盘仍由它自己的 _draw 画，本渲染器只画盘上那台机体与底盘。
##
## 灰度切换：shape == GENERIC（未实现器形）时由 TurretUnit 保留原贴图显示。
##
## 【2026-10-24 新野兽派重绘】六种器形转化要点（旧冷冽国风的辉光/渐变/机械细纹全砍）：
##   弩机＝反曲双臂主色大块 + 撞色机匣方匣 + 纸白弦与长箭（箭尖 = 炮口）；
##   阵盘＝八边主色盘体 + 墨阵环 + 撞色阵眼 + 纸白八剑（+X 剑尖 = 炮口）；
##   炮管＝主色炮身 + 撞色药室 + 墨箍 + 柄色炮架墨轮 + 膛口墨盘（口面仍到 x=16）；
##   机关兽＝主色躯干 + 撞色颅吻 + 墨喉膛 + 柄色足角 + 纸白方眼（口仍画到 x=16）；
##   投石机＝主色抛臂 + 撞色兜中弹 + 柄色架杆 + 墨转轴/纸白吊索（兜心 = 炮口）；
##   烽火台＝主色层叠台身 + 墨挑沿/门洞/火盆 + 撞色焰梢（焰尖 = 炮口）。
## 发射点一律落在本地 x=16（×ART_SCALE=24 = MuzzlePoint 本地 x）。

const BC = preload("res://scripts/weapons/shapes/BrutalistCommon.gd")

enum TurretShape {
	CROSSBOW,   ## 弩机：反曲双臂 + 弦 + 弩身 + 机匣 + 长箭（机关弩 / 凝冰机弩）
	ARRAY_DISC, ## 阵盘：八边盘体 + 阵环 + 阵眼 + 八剑放射（剑阵盘）
	CANNON,     ## 炮管：药室 + 炮身 + 墨箍 + 炮架轮（青木炮）
	BEAST,      ## 机关兽：足座 + 躯干 + 颅吻张口（喷火兽 / 寒泉兽 / 傀儡兽）
	TREBUCHET,  ## 投石机：A 架 + 抛臂 + 配重 + 索兜弹（垒石机关 / 藤萝机关）
	TOWER,      ## 烽台：层叠台身 + 女墙 + 火盆 + 焰梢（烽火台）
	GENERIC,
}

@export var shape: TurretShape = TurretShape.GENERIC
@export var element: String = "metal"
@export var star: int = 1

func configure(p_shape: TurretShape, p_element: String, p_star: int) -> void:
	shape = p_shape
	element = p_element
	star = clampi(p_star, 1, WeaponData.MAX_STAR)
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

## 本地 x=16 即炮口（×ART_SCALE = 24 = MuzzlePoint 本地 x）
const MUZZLE_X := 16.0

## 统一放大 1.5：各器形都把「炮口/兽口/臂端/焰尖」画在本地 x=16，×1.5 = 24 —— 正好等于
## TurretUnit 的 MuzzlePoint 在 CoreSprite 里的本地 x。本节点 scale=1（继承 CoreSprite 的
## 0.55），于是「炮口画在哪 == 弹丸从哪出」，与旧贴图出膛点同源。
const ART_SCALE := 1.5

## 中性柄色（与重器族 GRIP 同值）：弩身/炮架/兽足/架杆等「非五行主体」的结构件
const GRIP := Color(0.70, 0.68, 0.64)
## 机座底盘色（比墨稍浅的暗板色，压住阵盘又不吃掉机体轮廓）
const MOUNT := Color(0.15, 0.16, 0.20)

func _draw() -> void:
	# draw_set_transform 是「替换」而非「叠乘」：_draw_mount 里也会重设同款变换，
	# 画完器形全程保持 ART_SCALE，否则器身退回 1.0 比例、炮口与 MuzzlePoint 分家。
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

## 机座（炮台扎根盘面的暗色底盘 + 硬投影）。
## 注意：draw_set_transform 是「替换」而非「叠乘」，这里必须把 _draw 头部的 ART_SCALE
## 一起带上，否则后续器身会退回 1.0 比例、炮口与 MuzzlePoint 分家。
func _draw_mount(rx: float) -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(ART_SCALE, ART_SCALE))
	BC.disc(self, Vector2.ZERO, rx, MOUNT, 0.8)

## 沿折线骨架按宽度渐变铺出条带（弩臂/抛臂/焰梢等「有粗细变化的杆件」的硬边外轮廓）
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

# ---------------- 弩机（反曲双臂 + 弦 + 弩身 + 机匣 + 长箭） ----------------
## 一眼读成「弩」的三剪影特征：横置反曲双臂 + 纸白长弦挂到双梢 + 沿 +X 的长弩身与出鞘弩箭。
func _draw_crossbow() -> void:
	var pal: Dictionary = BC.pal(element)
	_draw_mount(11.0)

	# 反曲弩臂：五行主色大块，从机匣两侧向前外张、再回勾到梢（先画，压在弩身之下）
	for s in [-1.0, 1.0]:
		var spine := PackedVector2Array([
			Vector2(2.4, s * 2.4), Vector2(0.0, s * 6.4),
			Vector2(-4.4, s * 10.0), Vector2(-6.6, s * 11.8),
		])
		BC.flat(self, _band(spine, 3.2, 1.3), pal["body"], 0.8)
		# 臂梢墨方（弦的挂点）
		BC.square(self, Vector2(-6.6, s * 11.8), 0.9, BC.INK, 0.6)
	# 弩弦：两梢之间向后挂成 V（纸白，待发状态）
	draw_polyline(PackedVector2Array([
		Vector2(-6.6, -11.8), Vector2(-9.2, 0.0), Vector2(-6.6, 11.8),
	]), BC.PAPER, 1.5, true)

	# 弩身：柄色长骨（前细后粗、尾端收尖，硬折线）
	BC.flat(self, PackedVector2Array([
		Vector2(MUZZLE_X, -1.8), Vector2(MUZZLE_X, 1.8), Vector2(1.0, 2.9),
		Vector2(-12.8, 3.4), Vector2(-15.0, 0.0), Vector2(-12.8, -3.4), Vector2(1.0, -2.8),
	]), GRIP, 1.4)
	# 弩槽：一道墨轨（旧双沟 + 荧光脊线砍成单线）
	draw_line(Vector2(-8.0, 0.0), Vector2(14.2, 0.0), BC.INK, 1.3, true)

	# 弩机匣：整块撞色方匣 + 墨机牙（唯一撞色块）
	BC.square(self, Vector2(-0.8, 0.0), 3.8, pal["accent"], 1.3)
	BC.square(self, Vector2(-0.8, 0.0), 1.0, BC.INK, 0.6)

	# 弩箭：纸白杆 + 墨羽 + 墨镞，箭尖正落炮口 x=16
	BC.bar(self, Vector2(-5.0, 0.0), Vector2(MUZZLE_X - 2.2, 0.0), 1.6, BC.PAPER)
	for s in [-1.0, 1.0]:
		BC.flat(self, PackedVector2Array([
			Vector2(-4.6, 0.0), Vector2(-7.4, s * 2.2), Vector2(-3.4, s * 0.8),
		]), BC.INK, 0.6)
	BC.flat(self, PackedVector2Array([
		Vector2(MUZZLE_X, 0.0), Vector2(MUZZLE_X - 3.4, -1.5), Vector2(MUZZLE_X - 3.4, 1.5),
	]), BC.INK, 0.6)

	# 升星方钉：钉在双臂中段（撞色，无光效）
	BC.star_studs(self, star, Vector2(-0.6, -6.6), Vector2(-0.6, 6.6), pal["accent"])

# ---------------- 阵盘（八边盘体 + 阵环 + 阵眼 + 八剑放射） ----------------
## 剑阵盘＝「主色盘体 + 墨阵环 + 撞色阵眼 + 八口纸白小剑穿盘而出」；+X 那口剑的剑尖即炮口。
func _draw_array_disc() -> void:
	var pal: Dictionary = BC.pal(element)
	_draw_mount(11.0)

	# 八口小剑（先画，剑根压在盘体之下 ⇒ 剑像从盘缘里穿出来）
	for i in range(8):
		var ang := TAU * float(i) / 8.0
		var dir := Vector2(cos(ang), sin(ang))
		var perp := Vector2(-dir.y, dir.x)
		var root := dir * 8.2
		var tip := dir * (MUZZLE_X if i == 0 else 15.4)
		BC.flat(self, PackedVector2Array([tip, root + perp * 2.0, root - perp * 2.0]), BC.PAPER, 0.7)

	# 盘体：八边主色大块
	var oct_pts := PackedVector2Array()
	for i in range(8):
		var ang2 := TAU * (float(i) + 0.5) / 8.0
		oct_pts.append(Vector2(cos(ang2), sin(ang2)) * 12.0)
	BC.flat(self, oct_pts, pal["body"], 1.4)

	# 墨阵环（结构）+ 墨阵眼 + 撞色阵心（唯一撞色块）
	BC.ring(self, Vector2.ZERO, 8.0, 1.3, BC.INK)
	BC.disc(self, Vector2.ZERO, 4.4, BC.INK, 0.8)
	BC.disc(self, Vector2.ZERO, 2.0, pal["accent"], 0.6)

	# 升星方钉：盘面斜对角两颗
	BC.star_studs(self, star, Vector2(6.6, -6.6), Vector2(-6.6, 6.6), pal["accent"])

# ---------------- 炮（药室 + 炮身 + 墨箍 + 炮架轮） ----------------
## 青木炮＝整段原木掏膛的重炮：主色炮身前细后粗再放口、撞色方药室、柄色炮架双轮。
func _draw_cannon() -> void:
	var pal: Dictionary = BC.pal(element)
	_draw_mount(12.0)

	# 炮架：柄色斜置双颊木 + 后拖尾（先画，炮身压在架上）
	BC.flat(self, PackedVector2Array([
		Vector2(-11.6, 8.6), Vector2(-8.6, 1.6), Vector2(2.6, 1.6), Vector2(5.6, 8.6),
	]), GRIP, 1.2)
	BC.flat(self, PackedVector2Array([
		Vector2(-15.0, 8.8), Vector2(-11.0, 8.8), Vector2(-11.0, 5.4), Vector2(-14.0, 4.6),
	]), GRIP, 1.0)
	# 双轮：柄色盘 + 纸白方轴（旧齿轮砍成平涂轮）
	BC.disc(self, Vector2(-7.4, 7.4), 3.2, GRIP, 0.9)
	BC.disc(self, Vector2(-14.2, 7.0), 2.0, GRIP, 0.8)
	BC.square(self, Vector2(-7.4, 7.4), 0.9, BC.PAPER, 0.6)
	BC.square(self, Vector2(-14.2, 7.0), 0.7, BC.PAPER, 0.6)

	# 炮身：五行主色大块（前细后粗再放喇叭口，沿 +X，口面到 x=16）
	BC.flat(self, PackedVector2Array([
		Vector2(-9.0, -4.2), Vector2(6.0, -4.4), Vector2(11.4, -5.6), Vector2(MUZZLE_X, -5.9),
		Vector2(MUZZLE_X, 5.9), Vector2(11.4, 5.6), Vector2(6.0, 4.4), Vector2(-9.0, 4.2),
	]), pal["body"], 1.6)
	# 药室：整块撞色方匣压在炮尾（唯一撞色块）
	BC.flat(self, PackedVector2Array([
		Vector2(-13.4, -4.6), Vector2(-7.8, -4.6), Vector2(-7.8, 4.6), Vector2(-13.4, 4.6),
	]), pal["accent"], 1.3)
	# 墨箍两道（旧三道铜箍 + 刻纹 + 木纹砍成两道墨线）
	draw_line(Vector2(-4.6, -4.5), Vector2(-4.6, 4.5), BC.INK, 1.8, true)
	draw_line(Vector2(2.6, -4.7), Vector2(2.6, 4.7), BC.INK, 1.8, true)
	# 膛口：墨盘黑洞压在口端（炮口面仍到 x=16）
	BC.disc(self, Vector2(15.4, 0.0), 3.2, BC.INK, 0.9)

	# 升星方钉：炮身上下沿
	BC.star_studs(self, star, Vector2(-0.8, -3.2), Vector2(-0.8, 3.2), pal["accent"])

# ---------------- 机关兽（足座 + 躯干 + 颅吻张口） ----------------
## 小尺度读成「兽」的三剪影：撞色楔形颅吻（口在 +X 炮口）+ 后掠柄色双角 + 主色厚躯干；
## 元素差异全落在配色上（旧冰棱/岩甲/火鬃三套背饰与肩胯齿轮全砍）。
func _draw_beast() -> void:
	var pal: Dictionary = BC.pal(element)
	_draw_mount(12.0)

	# 足与踏板：前/后各一腿 + 贴地踏板（柄色）
	for x in [6.0, -7.0]:
		BC.flat(self, PackedVector2Array([
			Vector2(x - 2.0, 1.0), Vector2(x + 2.2, 1.0), Vector2(x + 2.8, 7.0), Vector2(x - 2.6, 7.0),
		]), GRIP, 0.7)
		BC.flat(self, PackedVector2Array([
			Vector2(x - 3.4, 6.6), Vector2(x + 3.8, 6.6), Vector2(x + 3.8, 9.2), Vector2(x - 3.4, 9.2),
		]), GRIP, 0.6)

	# 躯干：五行主色大块（厚箱形；后掠双角直接并进剪影——独立细三角会被墨描边吞掉）
	BC.flat(self, PackedVector2Array([
		Vector2(7.6, -6.4), Vector2(5.2, -11.2), Vector2(3.0, -6.9),
		Vector2(-2.6, -7.4), Vector2(-5.4, -11.6), Vector2(-7.6, -6.6),
		Vector2(-10.6, -5.0), Vector2(-10.6, 4.4), Vector2(-4.0, 6.4), Vector2(7.6, 5.4),
	]), pal["body"], 1.4)

	# 颅吻：整块撞色楔形（后宽前窄，口落在 +X 炮口）
	BC.flat(self, PackedVector2Array([
		Vector2(MUZZLE_X, -2.6), Vector2(12.8, -5.6), Vector2(7.4, -6.4),
		Vector2(7.4, 6.4), Vector2(12.8, 5.6), Vector2(MUZZLE_X, 2.6),
	]), pal["accent"], 1.3)
	# 张口：墨色喉膛（一律画到 x=16，保证「弹丸从口出」）
	BC.flat(self, PackedVector2Array([
		Vector2(MUZZLE_X + 0.4, -2.0), Vector2(9.4, -0.9), Vector2(9.4, 0.9), Vector2(MUZZLE_X + 0.4, 2.0),
	]), BC.INK, 0.6)
	# 兽眼：纸白方眼（旧起辉眼砍成平涂）
	BC.square(self, Vector2(10.2, -3.4), 1.0, BC.PAPER, 0.6)

	# 升星方钉：躯干背脊两颗
	BC.star_studs(self, star, Vector2(-4.6, -4.4), Vector2(-0.8, -5.8), pal["accent"])

# ---------------- 投石机（A 架 + 抛臂 + 配重 + 索兜弹） ----------------
## 垒石机关（土）/ 藤萝机关（木）＝柄色 A 架 + 主色抛臂 + 柄色配重匣 + 撞色兜中弹；
## 抛臂前扬、索兜垂到 x=16 —— 兜中之弹正是出膛的那一发。
func _draw_trebuchet() -> void:
	var pal: Dictionary = BC.pal(element)
	_draw_mount(12.5)

	# 底梁（柄色长板）
	BC.flat(self, PackedVector2Array([
		Vector2(-13.5, 7.7), Vector2(12.5, 7.7), Vector2(12.5, 9.9), Vector2(-13.5, 9.9),
	]), GRIP, 1.0)
	# A 形支架：两根收分腿 + 横撑（柄色硬折板，旧齿轮转轴砍成墨盘）
	BC.flat(self, PackedVector2Array([
		Vector2(-9.0, 8.6), Vector2(-6.8, 8.6), Vector2(1.4, -2.2), Vector2(0.0, -2.2),
	]), GRIP, 1.0)
	BC.flat(self, PackedVector2Array([
		Vector2(6.8, 8.6), Vector2(9.0, 8.6), Vector2(1.2, -2.2), Vector2(-0.2, -2.2),
	]), GRIP, 1.0)
	BC.flat(self, PackedVector2Array([
		Vector2(-4.6, 3.0), Vector2(4.8, 3.0), Vector2(4.8, 4.6), Vector2(-4.6, 4.6),
	]), GRIP, 0.8)

	# 抛臂：五行主色大块（尾低挂配重 → 过转轴 → 前扬到臂端）
	var tail_pt := Vector2(-11.6, 5.4)
	var tip_pt := Vector2(9.6, -8.6)
	BC.flat(self, _band(PackedVector2Array([tail_pt, Vector2(0.6, -2.4), tip_pt]), 2.6, 1.5),
		pal["body"], 0.9)

	# 配重（尾端吊石匣）：两根纸白吊索 + 柄色方匣（旧织纹/「土」字纹砍掉）
	draw_line(tail_pt, Vector2(-13.4, 6.2), BC.PAPER, 1.1, true)
	draw_line(tail_pt, Vector2(-10.2, 6.2), BC.PAPER, 1.1, true)
	BC.flat(self, PackedVector2Array([
		Vector2(-14.2, 6.0), Vector2(-9.0, 6.0), Vector2(-9.0, 10.2), Vector2(-14.2, 10.2),
	]), GRIP, 1.1)

	# 转轴：墨盘 + 纸白方轴
	BC.disc(self, Vector2(0.6, -2.4), 2.6, BC.INK, 0.8)
	BC.square(self, Vector2(0.6, -2.4), 0.9, BC.PAPER, 0.6)

	# 索兜 + 撞色石弹（兜中之物中心正落在 x=16 = 炮口；唯一撞色块）
	var ammo := Vector2(MUZZLE_X, 0.0)
	draw_line(tip_pt, ammo + Vector2(-2.6, -1.6), BC.PAPER, 1.1, true)
	draw_line(tip_pt, ammo + Vector2(-1.4, 3.0), BC.PAPER, 1.1, true)
	BC.flat(self, PackedVector2Array([
		ammo + Vector2(-3.4, 1.2), ammo + Vector2(3.4, 1.2), ammo + Vector2(2.0, 4.0),
		ammo + Vector2(-2.2, 4.0),
	]), BC.INK, 0.8)
	BC.flat(self, PackedVector2Array([
		ammo + Vector2(-0.4, -3.2), ammo + Vector2(2.8, -1.4), ammo + Vector2(2.2, 2.2),
		ammo + Vector2(-2.4, 2.6), ammo + Vector2(-3.0, -1.2),
	]), pal["accent"], 1.1)

	# 升星方钉：抛臂中段两颗
	BC.star_studs(self, star, Vector2(-5.2, 1.2), Vector2(-2.0, -0.9), pal["accent"])

# ---------------- 烽台（层叠台身 + 女墙 + 火盆 + 焰梢） ----------------
## 烽火台保持竖直剪影（三层收分主色台身 + 墨挑沿 + 柄色女墙），台顶火盆的撞色焰梢向 +X 甩出、
## 焰尖正落在 x=16 —— 炮台转向索敌时，等于「烽烟朝着敌人扫过去」，出膛点与判定同源。
func _draw_tower() -> void:
	var pal: Dictionary = BC.pal(element)
	_draw_mount(11.0)

	# 三层收分台身（自下而上）：每层一块主色 + 一道压顶墨挑沿；顶层女墙齿并进台身剪影
	var tiers := [
		{"y0": 9.0, "y1": 2.0, "x0": 9.4, "x1": 7.0, "eave": 8.6},
		{"y0": 2.0, "y1": -4.2, "x0": 6.6, "x1": 5.0, "eave": 6.2},
		{"y0": -4.2, "y1": -9.6, "x0": 4.6, "x1": 3.6, "eave": 5.4},
	]
	for ti in range(tiers.size()):
		var t: Dictionary = tiers[ti]
		var y0: float = t["y0"]
		var y1: float = t["y1"]
		var x0: float = t["x0"]
		var x1: float = t["x1"]
		var eave: float = t["eave"]
		var eave_pts := PackedVector2Array([
			Vector2(-eave, y1 - 1.4), Vector2(eave, y1 - 1.4),
			Vector2(eave, y1 + 0.2), Vector2(-eave, y1 + 0.2),
		])
		if ti == tiers.size() - 1:
			# 顶层：挑沿先画（压在台身之下），并进剪影的女墙齿才立得出来
			BC.flat(self, eave_pts, BC.INK, 0.9)
			BC.flat(self, PackedVector2Array([
				Vector2(-x0, y0), Vector2(x0, y0), Vector2(x1, y1),
				Vector2(x1, -11.8), Vector2(2.0, -11.8), Vector2(2.0, -10.6),
				Vector2(0.8, -10.6), Vector2(0.8, -11.8), Vector2(-0.8, -11.8),
				Vector2(-0.8, -10.6), Vector2(-2.0, -10.6), Vector2(-2.0, -11.8),
				Vector2(-x1, -11.8), Vector2(-x1, y1),
			]), pal["body"], 1.2)
		else:
			BC.flat(self, PackedVector2Array([
				Vector2(-x0, y0), Vector2(x0, y0), Vector2(x1, y1), Vector2(-x1, y1),
			]), pal["body"], 1.2)
			BC.flat(self, eave_pts, BC.INK, 0.9)

	# 台基门洞（底层正中一道墨方口）
	BC.square(self, Vector2(0.0, 6.6), 1.7, BC.INK, 0.7)

	# 台顶火盆：墨色盆身（旧盆沿亮线砍掉）
	BC.flat(self, PackedVector2Array([
		Vector2(-4.0, -12.6), Vector2(4.0, -12.6), Vector2(2.6, -10.6), Vector2(-2.6, -10.6),
	]), BC.INK, 0.9)

	# 焰梢：撞色硬折带从火盆口向 +X 甩出，焰尖落在 x=16（= 出膛点；旧飞火/起辉砍掉）
	var spine := PackedVector2Array([
		Vector2(1.0, -12.4), Vector2(7.6, -11.2), Vector2(12.6, -7.2), Vector2(MUZZLE_X, -0.6),
	])
	BC.flat(self, _band(spine, 2.8, 1.2), pal["accent"], 1.2)

	# 升星方钉：中层台身两颗
	BC.star_studs(self, star, Vector2(-3.4, -1.0), Vector2(3.4, -1.0), pal["accent"])
