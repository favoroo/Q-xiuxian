extends RefCounted

## 新野兽派器形 · 重器族（8）：印 SEAL / 牌 TABLET / 灯 LANTERN / 鼓 DRUM /
## 铎 BELL / 锤 HAMMER / 锏 MACE / 盾 SHIELD
##
## 宿主 ProceduralWeaponRenderer._draw() 经 WeaponShapeLibrary 分发到此。
## 画法纪律与坐标契约见 BrutalistCommon.gd 头注释（平涂色块+粗墨描边+硬投影，沿 +X 画）。
## 这族多为 upright 竖置重器：宿主已统一旋转，族内永远沿 +X 画，器首落在 (r.tip_len, 0) 附近。
## 器形剪影/比例参照宿主旧画法（ProceduralWeaponRenderer._draw_xxx）与旧 HeavyShapes。
## 返回 true = 新画法接管；false = 回退旧画法（逐把灰度，未接管的会在预览里显示旧样）。

const BC = preload("res://scripts/weapons/shapes/BrutalistCommon.gd")

## 柄/钮通用柄色（同锤柄样稿 BC.PAPER.darkened(0.25) 的常量化，深蓝夜地上可读）
const GRIP := Color(0.70, 0.68, 0.64)

static func draw_shape(shape: int, r: ProceduralWeaponRenderer) -> bool:
	match shape:
		ProceduralWeaponRenderer.WeaponShape.HAMMER:
			_hammer(r)
			return true
		ProceduralWeaponRenderer.WeaponShape.DRUM:
			_drum(r)
			return true
		ProceduralWeaponRenderer.WeaponShape.SEAL:
			_seal(r)
			return true
		ProceduralWeaponRenderer.WeaponShape.TABLET:
			_tablet(r)
			return true
		ProceduralWeaponRenderer.WeaponShape.LANTERN:
			_lantern(r)
			return true
		ProceduralWeaponRenderer.WeaponShape.BELL:
			_bell(r)
			return true
		ProceduralWeaponRenderer.WeaponShape.MACE:
			_mace(r)
			return true
		ProceduralWeaponRenderer.WeaponShape.SHIELD:
			_shield(r)
			return true
	return false

# ---------------- 锤：粗柄 + 方头 + 撞面撞色（样稿种子，勿改风格） ----------------
static func _hammer(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = BC.pal(r.element)
	var L: float = r.tip_len
	var hh: float = clampf(L * 0.33, 6.0, 8.5)
	# 柄
	BC.bar(r, Vector2(-L * 0.78, 0.0), Vector2(L * 0.45, 0.0), 4.0, GRIP)
	# 方锤头
	BC.flat(r, PackedVector2Array([
		Vector2(L * 0.40, -hh), Vector2(L, -hh), Vector2(L, hh), Vector2(L * 0.40, hh),
	]), pal["body"])
	# 撞面撞色块
	BC.flat(r, PackedVector2Array([
		Vector2(L * 0.76, -hh), Vector2(L, -hh), Vector2(L, hh), Vector2(L * 0.76, hh),
	]), pal["accent"], 1.2)
	# 柄尾方钉
	BC.square(r, Vector2(-L * 0.82, 0.0), 2.4, pal["accent"])
	BC.star_studs(r, r.star, Vector2(L * 0.58, -hh * 0.45), Vector2(L * 0.58, hh * 0.45), pal["accent"])

# ---------------- 鼓：平涂鼓面 + 撞色环 + 方鼓心（样稿种子，勿改风格） ----------------
static func _drum(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = BC.pal(r.element)
	var rad: float = r.tip_len * 0.80
	BC.disc(r, Vector2.ZERO, rad, pal["body"])
	BC.ring(r, Vector2.ZERO, rad * 0.62, 3.6, pal["accent"])
	BC.square(r, Vector2.ZERO, 2.6, BC.INK, 1.0)
	BC.star_studs(r, r.star,
		Vector2(rad * 0.48, rad * 0.48), Vector2(-rad * 0.48, rad * 0.48), pal["accent"])

# ---------------- 印：方台印身 + 拱形印钮 + 撞色印面（巨印） ----------------
## 旧画法转化：方台梯形印身（顶窄底宽）+ 低分段拱钮（顶点落 (L,0) 附近）+
## 印面做成整块撞色方章 + 墨心，砍掉八卦格与荧光滚边。
static func _seal(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = BC.pal(r.element)
	var L: float = r.tip_len
	# 印身：硬折线方台，顶窄底宽（压手感）
	var top_x: float = L * 0.42
	var bot_x: float = -L * 0.76
	var wt: float = L * 0.58
	var wb: float = L * 0.68
	BC.flat(r, PackedVector2Array([
		Vector2(top_x, -wt), Vector2(top_x, wt),
		Vector2(bot_x, wb), Vector2(bot_x, -wb),
	]), pal["body"])
	# 拱形印钮：6 段硬折半环，外缘顶点落到 (L*0.92, 0) 附近
	var ax: float = L * 0.42
	var rr: float = L * 0.50
	var ri: float = rr * 0.44
	var arch := PackedVector2Array()
	for i in range(7):
		var a: float = -PI * 0.5 + PI * float(i) / 6.0
		arch.append(Vector2(ax + cos(a) * rr, sin(a) * rr))
	for i in range(7):
		var b: float = PI * 0.5 - PI * float(i) / 6.0
		arch.append(Vector2(ax + cos(b) * ri, sin(b) * ri))
	BC.flat(r, arch, GRIP, 1.8)
	# 印面：整块撞色方章 + 墨心（唯一撞色块）
	BC.square(r, Vector2(-L * 0.42, 0.0), L * 0.26, pal["accent"], 1.6)
	BC.square(r, Vector2(-L * 0.42, 0.0), 1.8, BC.INK, 1.0)
	BC.star_studs(r, r.star, Vector2(L * 0.10, -L * 0.40), Vector2(L * 0.10, L * 0.40), pal["accent"])

# ---------------- 牌族分型：雷牌(矩形基准) / 金霄雷令(尖顶令牌) ----------------
static func _tablet(r: ProceduralWeaponRenderer) -> void:
	match String(r.weapon_id):
		"jinxiao_leiling":
			_tablet_ling(r)
		_:
			_tablet_paizi(r)

## 雷牌（土，牌族基准）：矩形牌身 + 撞色圆牌头 + 牌心雷纹 + 上下墨箍
## 旧画法转化：矩形牌身（底角斜切）+ 半圆牌头（顶点精确落 (L,0)，整块撞色）+
## 头心穿绳圆孔 + 吞口箍/尾箍，砍掉云卷/滚边，只留一道雷纹当唯一纹样。
## 图标验收（2026-10-25）：牌头由 4 段加细到 8 段、挂孔由方块改圆、牌心补雷纹折线，
## 原先「马赛克感」来自低分段折边 + 三块大色块拼贴，128px 图标下读不出是雷牌。
static func _tablet_paizi(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = BC.pal(r.element)
	var L: float = r.tip_len
	var hw: float = clampf(L * 0.40, 6.0, 9.0)
	var cap_c: float = L - hw
	var bot_x: float = -L * 0.80
	# 牌身：矩形 + 尾端两角斜切
	BC.flat(r, PackedVector2Array([
		Vector2(cap_c, -hw), Vector2(cap_c, hw),
		Vector2(bot_x + hw * 0.55, hw), Vector2(bot_x, hw * 0.35),
		Vector2(bot_x, -hw * 0.35), Vector2(bot_x + hw * 0.55, -hw),
	]), pal["body"])
	# 圆牌头：8 段硬边半圆帽（段数够细，缩进 UI 图标不再是多边形台阶），整块撞色
	var cap := PackedVector2Array()
	for i in range(9):
		var a: float = -PI * 0.5 + PI * float(i) / 8.0
		cap.append(Vector2(cap_c + cos(a) * hw, sin(a) * hw))
	cap.append(Vector2(cap_c, hw))
	cap.append(Vector2(cap_c, -hw))
	BC.flat(r, cap, pal["accent"], 2.0)
	# 穿绳孔：圆孔（方块孔在图标里读成一格马赛克）
	r.draw_circle(Vector2(cap_c + hw * 0.44, 0.0), hw * 0.25, BC.INK)
	# 牌心雷纹：一块 ⚡ 实心折线（左倾闪电），牌面唯一纹样；实心多边形不用描边，
	# 细线折线在缩放后会糊成一团斜杠，六角折边才是图标尺度下能读出的雷形
	var top_x: float = L * 0.34
	var span: float = L * 0.62
	var half_lat: float = hw * 0.62
	r.draw_colored_polygon(PackedVector2Array([
		_bolt_pt(top_x, span, half_lat, 0.555, 0.00),
		_bolt_pt(top_x, span, half_lat, 0.000, 0.60),
		_bolt_pt(top_x, span, half_lat, 0.500, 0.60),
		_bolt_pt(top_x, span, half_lat, 0.444, 1.00),
		_bolt_pt(top_x, span, half_lat, 1.000, 0.40),
		_bolt_pt(top_x, span, half_lat, 0.500, 0.40),
	]), BC.INK)
	# 上下墨箍（吞口箍 + 尾箍），中间整段留白给雷纹
	r.draw_line(Vector2(L * 0.44, -hw * 0.74), Vector2(L * 0.44, hw * 0.74), BC.INK, 2.0, true)
	r.draw_line(Vector2(-L * 0.52, -hw * 0.84), Vector2(-L * 0.52, hw * 0.84), BC.INK, 1.8, true)
	BC.star_studs(r, r.star, Vector2(-L * 0.66, -hw * 0.50), Vector2(-L * 0.66, hw * 0.50), pal["accent"])

## 雷纹归一化坐标 → 牌面坐标：lat 0~1 为横向（-half_lat..+half_lat），down 0~1 为
## 从 top_x 沿牌身向下的行程（共 span）。归一化形状取自标准闪电折线，别按像素手调。
static func _bolt_pt(top_x: float, span: float, half_lat: float, lat: float, down: float) -> Vector2:
	return Vector2(top_x - span * down, (lat - 0.5) * 2.0 * half_lat)

## 金霄雷令（金）：上尖六棱令牌 + 撞色横带 + 令心墨印——尖顶令与矩形牌剪影不同
static func _tablet_ling(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = BC.pal(r.element)
	var L: float = r.tip_len
	var hw: float = clampf(L * 0.34, 5.0, 7.5)
	# 令体：上尖六棱（尖顶精确 (L,0)，下端平齐双斜切）
	BC.flat(r, PackedVector2Array([
		Vector2(L, 0.0), Vector2(L * 0.62, -hw), Vector2(-L * 0.34, -hw),
		Vector2(-L * 0.58, -hw * 0.45), Vector2(-L * 0.58, hw * 0.45),
		Vector2(-L * 0.34, hw), Vector2(L * 0.62, hw),
	]), pal["body"])
	# 撞色横带 + 墨箍（令牌读法：一带一箍）
	BC.bar(r, Vector2(L * 0.40, -hw * 0.72), Vector2(L * 0.40, hw * 0.72), 2.6, pal["accent"])
	BC.bar(r, Vector2(-L * 0.30, -hw * 0.72), Vector2(-L * 0.30, hw * 0.72), 2.0, BC.INK)
	# 令心墨方印
	BC.square(r, Vector2(L * 0.04, 0.0), 2.0, BC.INK, 1.0)
	BC.star_studs(r, r.star, Vector2(L * 0.52, 0.0), Vector2(-L * 0.44, 0.0), pal["accent"])

# ---------------- 灯：圆腹灯笼 + 上下墨箍 + 撞色灯心 + 提环（天灯） ----------------
## 旧画法转化：圆盘灯腹（火主色一大块）+ 两道垂直长轴的墨箍 + 柄色拱形提环 +
## 撞色菱形火苗 + 一根墨流苏，砍掉灯骨线与三束流苏。
static func _lantern(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = BC.pal(r.element)
	var L: float = r.tip_len
	var rad: float = L * 0.60
	# 灯腹：大圆盘
	BC.disc(r, Vector2.ZERO, rad, pal["body"])
	# 上下箍：两道垂直长轴的粗墨箍（纯墨线，避免杆影糊住灯腹）
	r.draw_line(Vector2(rad * 0.52, -rad * 0.52), Vector2(rad * 0.52, rad * 0.52), BC.INK, 2.6, true)
	r.draw_line(Vector2(-rad * 0.52, -rad * 0.52), Vector2(-rad * 0.52, rad * 0.52), BC.INK, 2.6, true)
	# 顶部提环：4 段硬折小拱（柄色），拱脚落在灯腹圆周上，顶点落 (L*0.82, 0) 附近
	var ax: float = L * 0.42
	var rr: float = L * 0.40
	var ri: float = rr * 0.50
	var arch := PackedVector2Array()
	for i in range(5):
		var a: float = -PI * 0.5 + PI * float(i) / 4.0
		arch.append(Vector2(ax + cos(a) * rr, sin(a) * rr))
	for i in range(5):
		var b: float = PI * 0.5 - PI * float(i) / 4.0
		arch.append(Vector2(ax + cos(b) * ri, sin(b) * ri))
	BC.flat(r, arch, GRIP, 1.6)
	# 灯心：硬边菱形火苗（唯一撞色块）
	BC.flat(r, PackedVector2Array([
		Vector2(rad * 0.42, 0.0), Vector2(0.0, -rad * 0.34),
		Vector2(-rad * 0.30, 0.0), Vector2(0.0, rad * 0.34),
	]), pal["accent"], 1.2)
	# 底部流苏：一根粗墨短穗
	BC.bar(r, Vector2(-rad * 0.92, 0.0), Vector2(-rad * 1.42, 0.0), 1.8, BC.INK)
	BC.star_studs(r, r.star, Vector2(rad * 0.35, -rad * 0.42), Vector2(rad * 0.35, rad * 0.42), pal["accent"])

# ---------------- 铎：钟形铎身 + 提环 + 撞色口沿 + 铎舌（裂山铎） ----------------
## 旧画法转化：上窄下宽硬折线钟身 + 外撇口沿（整块撞色带）+ 柄色提环 + 墨铎舌方丸，
## 砍掉棱线/回纹/弦纹。
static func _bell(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = BC.pal(r.element)
	var L: float = r.tip_len
	var tw: float = L * 0.25
	var bw: float = L * 0.52
	var top_x: float = L * 0.50
	var bot_x: float = -L * 0.62
	var lip_x: float = -L * 0.78
	var lip_w: float = bw * 1.16
	# 铎身：首端窄、尾端外张的硬折线钟形
	BC.flat(r, PackedVector2Array([
		Vector2(top_x, -tw), Vector2(top_x, tw),
		Vector2(bot_x, bw), Vector2(lip_x, lip_w),
		Vector2(lip_x, -lip_w), Vector2(bot_x, -bw),
	]), pal["body"])
	# 口沿撞色带（唯一撞色块，外缘与铎身撇口同线）
	BC.flat(r, PackedVector2Array([
		Vector2(bot_x - L * 0.02, -bw * 1.02), Vector2(lip_x, -lip_w),
		Vector2(lip_x, lip_w), Vector2(bot_x - L * 0.02, bw * 1.02),
	]), pal["accent"], 1.2)
	# 顶部提环：6 段硬折小拱（柄色），拱脚落在铎顶面上，顶点落 (L*0.86, 0) 附近
	var rr: float = L * 0.36
	var ri: float = rr * 0.48
	var arch := PackedVector2Array()
	for i in range(7):
		var a: float = -PI * 0.5 + PI * float(i) / 6.0
		arch.append(Vector2(top_x + cos(a) * rr, sin(a) * rr))
	for i in range(7):
		var b: float = PI * 0.5 - PI * float(i) / 6.0
		arch.append(Vector2(top_x + cos(b) * ri, sin(b) * ri))
	BC.flat(r, arch, GRIP, 1.6)
	# 铎舌：粗墨舌杆 + 方舌丸（悬向铎口）
	r.draw_line(Vector2(L * 0.18, 0.0), Vector2(-L * 0.46, 0.0), BC.INK, 1.8, true)
	BC.square(r, Vector2(-L * 0.50, 0.0), 1.7, BC.INK, 1.0)
	BC.star_studs(r, r.star, Vector2(0.0, -L * 0.20), Vector2(0.0, L * 0.20), pal["accent"])

# ---------------- 锏：六棱重锏身 + 撞色锏首 + 节环（六棱锏） ----------------
## 旧画法转化：通长六棱柱侧影（撞面平头、尾端收尖）+ 锤样同款撞色打击端 +
## 两道墨节环 + 短粗柄 + 柄端方钉，砍掉荧光棱线与通长脊线。
static func _mace(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = BC.pal(r.element)
	var L: float = r.tip_len
	var w: float = clampf(L * 0.21, 3.6, 5.4)
	# 柄：短粗柄杆（画在锏身之后，只露出尾段）
	BC.bar(r, Vector2(-L * 0.90, 0.0), Vector2(-L * 0.56, 0.0), 4.2, GRIP)
	# 锏身：器首平撞面、尾端收方的硬折线柱身
	BC.flat(r, PackedVector2Array([
		Vector2(L * 0.94, -w * 0.55), Vector2(L * 0.94, w * 0.55),
		Vector2(L * 0.76, w), Vector2(-L * 0.56, w),
		Vector2(-L * 0.62, 0.0), Vector2(-L * 0.56, -w),
		Vector2(L * 0.76, -w),
	]), pal["body"])
	# 撞色锏首（打击端一块，锤样同款口径）
	BC.flat(r, PackedVector2Array([
		Vector2(L * 0.94, -w * 0.55), Vector2(L * 0.94, w * 0.55),
		Vector2(L * 0.76, w), Vector2(L * 0.76, -w),
	]), pal["accent"], 1.4)
	# 节环两道（纯墨线微宽出锏身，避免杆影把锏身切成碎块）
	r.draw_line(Vector2(L * 0.40, -w * 1.08), Vector2(L * 0.40, w * 1.08), BC.INK, 2.6, true)
	r.draw_line(Vector2(-L * 0.06, -w * 1.08), Vector2(-L * 0.06, w * 1.08), BC.INK, 2.6, true)
	# 柄端方钉（柄色帽）
	BC.square(r, Vector2(-L * 0.90, 0.0), 2.4, GRIP, 1.0)
	BC.star_studs(r, r.star, Vector2(L * 0.16, -w * 0.52), Vector2(L * 0.16, w * 0.52), pal["accent"])

# ---------------- 盾：尖顶盾面 + 撞色盾脊 + 墨横箍（重盾） ----------------
## 旧画法转化：尖顶六边盾（剪影同旧）+ 沿长轴一条细长撞色盾脊 + 一道纯墨横箍，
## 砍掉荧光脊线与中央盾钉（横箍与升星钉已够读）。
static func _shield(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = BC.pal(r.element)
	var L: float = r.tip_len
	var hh: float = L * 0.54
	# 盾面：器首朝 +X 的尖顶六边盾
	BC.flat(r, PackedVector2Array([
		Vector2(L * 0.96, 0.0), Vector2(L * 0.34, -hh * 0.80),
		Vector2(-L * 0.74, -hh), Vector2(-L * 0.90, 0.0),
		Vector2(-L * 0.74, hh), Vector2(L * 0.34, hh * 0.80),
	]), pal["body"])
	# 横箍：一道垂直长轴的纯墨箍（先画，压在盾脊之下）
	r.draw_line(Vector2(-L * 0.20, -hh * 0.58), Vector2(-L * 0.20, hh * 0.58), BC.INK, 2.4, true)
	# 盾脊撞色条：沿长轴一块细长撞色（唯一撞色块，连续不打断）
	BC.flat(r, PackedVector2Array([
		Vector2(L * 0.80, -L * 0.05), Vector2(L * 0.80, L * 0.05),
		Vector2(-L * 0.60, L * 0.065), Vector2(-L * 0.60, -L * 0.065),
	]), pal["accent"], 1.2)
	BC.star_studs(r, r.star, Vector2(-L * 0.42, -hh * 0.42), Vector2(-L * 0.42, hh * 0.42), pal["accent"])
