extends RefCounted

## 新野兽派器形 · 巧器族（10）：符 TALISMAN / 扇 FAN / 鞭 WHIP / 尺 RULER / 梭 SHUTTLE /
## 弹弓 SLING / 葫芦 CALABASH / 笛 FLUTE / 镜 MIRROR / 珠 BEAD
##
## 宿主 ProceduralWeaponRenderer._draw() 经 WeaponShapeLibrary 分发到此。
## 画法纪律与坐标契约见 BrutalistCommon.gd 头注释（平涂色块+粗墨描边+硬投影，沿 +X 画）。
## 器形剪影/比例参照宿主旧画法（ProceduralWeaponRenderer._draw_xxx）与旧
## TalismanShapes/LongShapes/FineShapes——保留结构性变体，砍掉纯装饰变体。
## 返回 true = 新画法接管；false = 回退旧画法（逐把灰度，未接管的会在预览里显示旧样）。

const BC = preload("res://scripts/weapons/shapes/BrutalistCommon.gd")

static func draw_shape(shape: int, r: ProceduralWeaponRenderer) -> bool:
	match shape:
		ProceduralWeaponRenderer.WeaponShape.TALISMAN:
			_talisman(r)
			return true
		ProceduralWeaponRenderer.WeaponShape.FAN:
			_fan(r)
			return true
		ProceduralWeaponRenderer.WeaponShape.WHIP:
			_whip(r)
			return true
		ProceduralWeaponRenderer.WeaponShape.RULER:
			_ruler(r)
			return true
		ProceduralWeaponRenderer.WeaponShape.SHUTTLE:
			_shuttle(r)
			return true
		ProceduralWeaponRenderer.WeaponShape.SLING:
			_sling(r)
			return true
		ProceduralWeaponRenderer.WeaponShape.CALABASH:
			_calabash(r)
			return true
		ProceduralWeaponRenderer.WeaponShape.FLUTE:
			_flute(r)
			return true
		ProceduralWeaponRenderer.WeaponShape.MIRROR:
			_mirror(r)
			return true
		ProceduralWeaponRenderer.WeaponShape.BEAD:
			_bead(r)
			return true
	return false

# ---------------- 符箓：纸白符身 + 符头色带 + 朱砂大印 + 一笔粗墨（样稿种子，勿改风格） ----------------
static func _talisman(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = BC.pal(r.element)
	var L: float = r.tip_len
	var hw: float = clampf(L * 0.30, 5.5, 7.5)
	# 符纸
	BC.flat(r, PackedVector2Array([
		Vector2(L * 0.82, -hw), Vector2(-L * 0.82, -hw),
		Vector2(-L * 0.82, hw), Vector2(L * 0.82, hw),
	]), BC.PAPER, 2.4)
	# 符头五行色带
	BC.flat(r, PackedVector2Array([
		Vector2(L * 0.82, -hw), Vector2(L * 0.55, -hw),
		Vector2(L * 0.55, hw), Vector2(L * 0.82, hw),
	]), pal["accent"], 1.2)
	# 朱砂大印（固定朱红，不随五行走）
	BC.square(r, Vector2(-L * 0.42, 0.0), 3.4, BC.CINNABAR)
	# 一笔符：一横一竖一挑，粗墨
	r.draw_line(Vector2(L * 0.30, -hw * 0.55), Vector2(-L * 0.06, -hw * 0.55), BC.INK, 1.8, true)
	r.draw_line(Vector2(L * 0.30, -hw * 0.55), Vector2(L * 0.30, hw * 0.25), BC.INK, 1.8, true)
	r.draw_line(Vector2(L * 0.30, hw * 0.25), Vector2(-L * 0.10, hw * 0.60), BC.INK, 1.8, true)
	BC.star_studs(r, r.star, Vector2(L * 0.12, hw * 0.5), Vector2(L * 0.12, -hw * 0.5), BC.INK)

# ---------------- 扇族分型：燎原扇(折扇基准) / 风扇·芭蕉扇(整叶扇) ----------------
## 扇只出现在横扫武器上：无出膛点契约，扇面半径可略大于 tip_len（旧画法同款口径）。
static func _fan(r: ProceduralWeaponRenderer) -> void:
	match String(r.weapon_id):
		"bajiao_fan":
			_fan_leaf(r)
		_:
			_fan_folding(r)

## 燎原扇（火，扇族基准）：低分段硬边折扇 + 撞色环带 + 三根粗骨（样稿种子，勿改风格）
static func _fan_folding(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = BC.pal(r.element)
	var R: float = maxf(r.tip_len, 22.0) * 1.02
	var half := deg_to_rad(52.0)
	const SEG := 10
	# 扇面（低分段 = 硬边多边形感）
	var pts := PackedVector2Array([Vector2.ZERO])
	for i in range(SEG + 1):
		var a := -half + 2.0 * half * float(i) / float(SEG)
		pts.append(Vector2(cos(a), sin(a)) * R)
	BC.flat(r, pts, pal["body"], 2.4)
	# 外缘撞色环带
	var band := PackedVector2Array()
	for i in range(SEG + 1):
		var a := -half + 2.0 * half * float(i) / float(SEG)
		band.append(Vector2(cos(a), sin(a)) * R)
	for i in range(SEG, -1, -1):
		var a := -half + 2.0 * half * float(i) / float(SEG)
		band.append(Vector2(cos(a), sin(a)) * R * 0.80)
	BC.flat(r, band, pal["accent"], 1.2)
	# 三根粗扇骨
	for i in range(3):
		var a := -half + 2.0 * half * float(i) / 2.0
		r.draw_line(Vector2.ZERO, Vector2(cos(a), sin(a)) * R * 0.78, BC.INK, 2.2, true)
	# 柄 + 方扇钉
	BC.bar(r, Vector2.ZERO, Vector2(-R * 0.35, 0.0), 3.2, BC.INK)
	BC.square(r, Vector2.ZERO, 2.4, pal["accent"])
	BC.star_studs(r, r.star,
		Vector2(cos(-half * 0.5), sin(-half * 0.5)) * R * 0.55,
		Vector2(cos(half * 0.5), sin(half * 0.5)) * R * 0.55, pal["accent"])

## 风扇·芭蕉扇（水）：硬边整叶扇 + 中脉侧脉 + 叶柄——与折扇的半圆骨架完全两种读法
static func _fan_leaf(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = BC.pal(r.element)
	var R: float = maxf(r.tip_len, 22.0) * 1.02
	# 芭蕉叶：硬边七点叶形（叶尖精确落 (R,0)，后根收窄）
	BC.flat(r, PackedVector2Array([
		Vector2(R, 0.0), Vector2(R * 0.62, -R * 0.34), Vector2(R * 0.16, -R * 0.42),
		Vector2(-R * 0.10, -R * 0.16), Vector2(-R * 0.10, R * 0.16),
		Vector2(R * 0.16, R * 0.42), Vector2(R * 0.62, R * 0.34),
	]), pal["body"], 2.4)
	# 中脉 + 两条侧脉（叶骨，硬直线）
	r.draw_line(Vector2(-R * 0.06, 0.0), Vector2(R * 0.92, 0.0), BC.INK, 2.2, true)
	r.draw_line(Vector2(R * 0.28, 0.0), Vector2(R * 0.60, -R * 0.24), BC.INK, 1.6, true)
	r.draw_line(Vector2(R * 0.28, 0.0), Vector2(R * 0.60, R * 0.24), BC.INK, 1.6, true)
	# 叶柄 + 方钉
	BC.bar(r, Vector2(-R * 0.08, 0.0), Vector2(-R * 0.38, 0.0), 3.2, BC.INK)
	BC.square(r, Vector2(-R * 0.06, 0.0), 2.2, pal["accent"])
	BC.star_studs(r, r.star, Vector2(R * 0.78, -R * 0.15), Vector2(R * 0.78, R * 0.15), pal["accent"])

# ---------------- 鞭：硬折线锯齿鞭身（之字形粗带，由粗到细）+ 撞色短柄 + 墨钉 ----------------
static func _whip(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = BC.pal(r.element)
	var L: float = r.tip_len
	# 鞭身折点：沿 +X 五折，振幅与带厚同步收细；根部接柄、梢部收直都压回轴线，器梢落 (L, 0)
	const SEG := 5
	var top := PackedVector2Array()
	var bot := PackedVector2Array()
	for i in range(SEG + 1):
		var t: float = float(i) / float(SEG)
		var x: float = L * t
		var amp: float = lerpf(L * 0.14, L * 0.035, t)
		var half: float = lerpf(L * 0.125, L * 0.035, t)
		var mid: float = 0.0
		if i == 0 or i == SEG:
			mid = 0.0
		elif i % 2 == 1:
			mid = amp
		else:
			mid = -amp
		top.append(Vector2(x, mid - half))
		bot.append(Vector2(x, mid + half))
	# 短柄（撞色芯，压在鞭身下面；鞭子的撞色块就是这截握柄）
	BC.bar(r, Vector2(-L * 0.32, 0.0), Vector2(L * 0.02, 0.0), 4.2, pal["accent"])
	# 锯齿鞭身（硬折线闭合带，由粗到细；细带上不再叠任何色块，避免断裂感）
	var ribbon := PackedVector2Array(top)
	for i in range(SEG, -1, -1):
		ribbon.append(bot[i])
	BC.flat(r, ribbon, pal["body"], 2.4)
	# 升星钉（墨钉随旧符箓样稿口径）：一钉在鞭身最宽的第一折折点上，一钉在握柄上
	BC.star_studs(r, r.star, Vector2(L * 0.20, L * 0.11), Vector2(-L * 0.20, 0.0), BC.INK)

# ---------------- 尺：尾端切角硬边长条 + 器首撞色端头 + 五道刻度 ----------------
static func _ruler(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = BC.pal(r.element)
	var L: float = r.tip_len
	var hw: float = L * 0.20
	# 尺身（尾端切角，硬边）
	BC.flat(r, PackedVector2Array([
		Vector2(L, -hw), Vector2(L, hw), Vector2(-L * 0.82, hw),
		Vector2(-L * 0.90, hw * 0.45), Vector2(-L * 0.90, -hw * 0.45), Vector2(-L * 0.82, -hw),
	]), pal["body"], 2.4)
	# 器首撞色端头
	BC.flat(r, PackedVector2Array([
		Vector2(L, -hw), Vector2(L, hw), Vector2(L * 0.78, hw), Vector2(L * 0.78, -hw),
	]), pal["accent"], 1.2)
	# 五道刻度（长短交错，粗墨）
	for i in range(5):
		var t: float = float(i) / 4.0
		var x: float = lerpf(L * 0.62, -L * 0.72, t)
		var tl: float = hw * (0.80 if i % 2 == 0 else 0.45)
		r.draw_line(Vector2(x, -tl), Vector2(x, tl), BC.INK, 1.4, true)
	BC.star_studs(r, r.star, Vector2(L * 0.44, 0.0), Vector2(-L * 0.22, 0.0), pal["accent"])

# ---------------- 梭：硬边六边梭形 + 器首撞色尖半 + 梭心穿线墨杆 ----------------
static func _shuttle(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = BC.pal(r.element)
	var L: float = r.tip_len
	var w: float = L * 0.30
	# 梭身（两头尖，剪影同旧画法）
	BC.flat(r, PackedVector2Array([
		Vector2(L, 0.0), Vector2(L * 0.34, -w), Vector2(-L * 0.55, -w * 0.72),
		Vector2(-L * 0.86, 0.0), Vector2(-L * 0.55, w * 0.72), Vector2(L * 0.34, w),
	]), pal["body"], 2.4)
	# 器首撞色尖半（前半三角整块）
	BC.flat(r, PackedVector2Array([
		Vector2(L, 0.0), Vector2(L * 0.34, -w), Vector2(L * 0.34, w),
	]), pal["accent"], 1.2)
	# 梭心穿线槽（粗墨短杆）
	BC.bar(r, Vector2(L * 0.12, 0.0), Vector2(-L * 0.48, 0.0), 1.8, BC.INK)
	BC.star_studs(r, r.star, Vector2(L * 0.02, -w * 0.36), Vector2(-L * 0.28, w * 0.36), pal["accent"])

# ---------------- 弹弓：五行色弓架三杆 + 粗墨 V 形兜绳 + 兜心撞色皮垫 ----------------
static func _sling(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = BC.pal(r.element)
	var L: float = r.tip_len
	# 弓架：柄 + 双叉（粗杆，墨描）
	BC.bar(r, Vector2(-L * 0.80, 0.0), Vector2(-L * 0.06, 0.0), 4.4, pal["body"])
	BC.bar(r, Vector2(-L * 0.06, 0.0), Vector2(L * 0.82, -L * 0.48), 3.4, pal["body"])
	BC.bar(r, Vector2(-L * 0.06, 0.0), Vector2(L * 0.82, L * 0.48), 3.4, pal["body"])
	# 皮兜：两叉梢间的皮革兜绳（纸暗色芯，墨芯在深色底上不可见）
	BC.bar(r, Vector2(L * 0.82, -L * 0.48), Vector2(L * 0.40, 0.0), 1.8, BC.PAPER.darkened(0.35))
	BC.bar(r, Vector2(L * 0.82, L * 0.48), Vector2(L * 0.40, 0.0), 1.8, BC.PAPER.darkened(0.35))
	# 兜心撞色皮垫
	BC.square(r, Vector2(L * 0.40, 0.0), 2.6, pal["accent"], 1.2)
	# 升星钉落在握柄上
	BC.star_studs(r, r.star, Vector2(-L * 0.64, 0.0), Vector2(-L * 0.32, 0.0), pal["accent"])

# ---------------- 葫芦：硬边折面双腹（口→小腹→收腰→大腹→尾尖）+ 撞色口塞 + 收腰墨箍 ----------------
static func _calabash(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = BC.pal(r.element)
	var L: float = r.tip_len
	# 折面葫芦身（旧平滑包络取关键折点直线化，硬边双腹剪影不变）
	BC.flat(r, PackedVector2Array([
		Vector2(L * 0.84, -L * 0.14), Vector2(L * 0.52, -L * 0.30),
		Vector2(L * 0.22, -L * 0.20), Vector2(-L * 0.05, -L * 0.44),
		Vector2(-L * 0.38, -L * 0.50), Vector2(-L * 0.60, -L * 0.36),
		Vector2(-L * 0.76, 0.0), Vector2(-L * 0.60, L * 0.36),
		Vector2(-L * 0.38, L * 0.50), Vector2(-L * 0.05, L * 0.44),
		Vector2(L * 0.22, L * 0.20), Vector2(L * 0.52, L * 0.30),
		Vector2(L * 0.84, L * 0.14),
	]), pal["body"], 2.4)
	# 口塞撞色块（器首顶到 (L, 0) 附近，根部插进口沿）
	BC.flat(r, PackedVector2Array([
		Vector2(L * 0.98, -L * 0.12), Vector2(L * 0.98, L * 0.12),
		Vector2(L * 0.80, L * 0.12), Vector2(L * 0.80, -L * 0.12),
	]), pal["accent"], 1.2)
	BC.star_studs(r, r.star, Vector2(-L * 0.30, 0.0), Vector2(-L * 0.52, 0.0), pal["accent"])

# ---------------- 笛：硬边长条笛身 + 吹口撞色帽 + 方指孔 + 端箍 + 尾端墨流苏 ----------------
static func _flute(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = BC.pal(r.element)
	var L: float = r.tip_len
	var hw: float = L * 0.14
	# 笛身
	BC.flat(r, PackedVector2Array([
		Vector2(L, -hw), Vector2(L, hw), Vector2(-L * 0.92, hw), Vector2(-L * 0.92, -hw),
	]), pal["body"], 2.2)
	# 吹口端撞色帽
	BC.flat(r, PackedVector2Array([
		Vector2(L, -hw), Vector2(L, hw), Vector2(L * 0.78, hw), Vector2(L * 0.78, -hw),
	]), pal["accent"], 1.2)
	# 四个方指孔（粗墨短竖，小尺度下比圆孔更可读）
	for i in range(4):
		var x: float = L * (0.50 - float(i) * 0.28)
		r.draw_line(Vector2(x, -hw * 0.35), Vector2(x, hw * 0.35), BC.INK, 2.2, true)
	# 两道端箍
	r.draw_line(Vector2(L * 0.66, -hw), Vector2(L * 0.66, hw), BC.INK, 1.6, true)
	r.draw_line(Vector2(-L * 0.80, -hw), Vector2(-L * 0.80, hw), BC.INK, 1.6, true)
	# 尾端流苏（短带，纸暗色芯；墨芯在深色底上不可见）
	BC.bar(r, Vector2(-L * 0.92, 0.0), Vector2(-L * 1.08, L * 0.10), 2.0, BC.PAPER.darkened(0.35))
	BC.star_studs(r, r.star, Vector2(-L * 0.50, 0.0), Vector2(-L * 0.66, 0.0), pal["accent"])

# ---------------- 镜：前移圆镜面 + 撞色镜框环 + 镜心墨钉 + 短柄 ----------------
static func _mirror(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = BC.pal(r.element)
	var L: float = r.tip_len
	var c := Vector2(L * 0.30, 0.0)
	var rad: float = L * 0.62
	# 镜柄（纸暗色芯，压在镜面下面，尾端探出；墨芯在深色底上不可见）
	BC.bar(r, Vector2(c.x - rad * 0.55, 0.0), Vector2(-L * 0.72, 0.0), 3.8, BC.PAPER.darkened(0.25))
	# 镜面（整盘前移，器首近 (L, 0)）
	BC.disc(r, c, rad, pal["body"])
	# 撞色镜框环
	BC.ring(r, c, rad * 0.74, 2.6, pal["accent"])
	# 镜心墨方钉
	BC.square(r, c, 1.5, BC.INK, 1.0)
	# 升星钉落在柄身上
	BC.star_studs(r, r.star, Vector2(-L * 0.46, 0.0), Vector2(-L * 0.62, 0.0), pal["accent"])

# ---------------- 珠：前移六棱珠体 + 旋 30° 撞色雷核 + 珠心墨钉 ----------------
static func _bead(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = BC.pal(r.element)
	var L: float = r.tip_len
	var c := Vector2(L * 0.26, 0.0)
	var rad: float = L * 0.64
	# 六棱珠体（前棱顶点指 +X，器首近 (L, 0)）
	var pts := PackedVector2Array()
	for i in range(6):
		var ang: float = TAU * float(i) / 6.0
		pts.append(c + Vector2(cos(ang), sin(ang)) * rad)
	BC.flat(r, pts, pal["body"], 2.4)
	# 撞色雷核（旋 30° 内缩六棱，与外棱交叠成十二面硬边雷纹）
	var inner := PackedVector2Array()
	for i in range(6):
		var ang2: float = TAU * float(i) / 6.0 + PI / 6.0
		inner.append(c + Vector2(cos(ang2), sin(ang2)) * rad * 0.55)
	BC.flat(r, inner, pal["accent"], 1.2)
	# 珠心墨方钉
	BC.square(r, c, 1.5, BC.INK, 1.0)
	BC.star_studs(r, r.star, Vector2(c.x + rad * 0.62, 0.0), c + Vector2(-0.31, 0.537) * rad, pal["accent"])
