extends RefCounted

## 新野兽派器形 · 刃器族（9）：剑 SWORD / 弯刀 SABER / 匕首 DAGGER / 手里剑 SHURIKEN /
## 斧 AXE / 剪 SHEARS / 钉 NAIL / 针 NEEDLES / 锥 AWL
##
## 宿主 ProceduralWeaponRenderer._draw() 经 WeaponShapeLibrary 分发到此。
## 画法纪律与坐标契约见 BrutalistCommon.gd 头注释（平涂色块+粗墨描边+硬投影，沿 +X 画）。
## 器形剪影/比例参照宿主旧画法（ProceduralWeaponRenderer._draw_xxx）与旧族模块
## （BladeShapes/FineShapes）——保留结构性变体（崩山剑土系宽刃、匕首主副双刀、
## 斧月牙刃、剪双刃指环、锥双箍环、针成束三针），砍掉纯装饰变体
## （飞刀尾环青穗、剪/锥刃口流光、锥雷纹、手里剑月牙磨刃面）。
## 2026-10-24 同形分型：同器形多把武器只靠换色读不出身份（长剑/飞剑同为金系全等），
## 剑 7 把 / 刀 2 把 / 针 2 把改按 r.weapon_id 出专属剪影，其余器形沿用基准形。
## 返回 true = 新画法接管；false = 回退旧画法（逐把灰度，未接管的会在预览里显示旧样）。

const BC = preload("res://scripts/weapons/shapes/BrutalistCommon.gd")

static func draw_shape(shape: int, r: ProceduralWeaponRenderer) -> bool:
	match shape:
		ProceduralWeaponRenderer.WeaponShape.SWORD:
			_sword(r)
			return true
		ProceduralWeaponRenderer.WeaponShape.SABER:
			_saber(r)
			return true
		ProceduralWeaponRenderer.WeaponShape.DAGGER:
			_dagger(r)
			return true
		ProceduralWeaponRenderer.WeaponShape.SHURIKEN:
			_shuriken(r)
			return true
		ProceduralWeaponRenderer.WeaponShape.AXE:
			_axe(r)
			return true
		ProceduralWeaponRenderer.WeaponShape.SHEARS:
			_shears(r)
			return true
		ProceduralWeaponRenderer.WeaponShape.NAIL:
			_nail(r)
			return true
		ProceduralWeaponRenderer.WeaponShape.NEEDLES:
			_needles(r)
			return true
		ProceduralWeaponRenderer.WeaponShape.AWL:
			_awl(r)
			return true
	return false

# ---------------- 剑族分型：长剑(基准) / 飞剑 / 青藤剑 / 桃木剑 / 流火飞剑 / 寒霜剑 / 崩山剑 ----------------
static func _sword(r: ProceduralWeaponRenderer) -> void:
	match String(r.weapon_id):
		"gengjin_feijian":
			_sword_feijian(r)
		"qingteng_jian":
			_sword_qingteng(r)
		"taomu_jian":
			_sword_taomu(r)
		"liuhuo_feijian":
			_sword_liuhuo(r)
		"hanshuang_jian":
			_sword_hanshuang(r)
		"bengshan_jian":
			_sword_bengshan(r)
		_:
			_sword_changjian(r)

## 长剑（剑族基准）：平行刃 + 斜切硬尖 + 一字格（样稿种子，勿改风格）
static func _sword_changjian(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = BC.pal(r.element)
	var L: float = r.tip_len
	var w: float = clampf(L * 0.115, 2.8, 4.6)
	# 平行刃 + 斜切硬尖
	BC.flat(r, PackedVector2Array([
		Vector2(L, 0.0), Vector2(L - w * 1.1, -w), Vector2(0.0, -w),
		Vector2(0.0, w), Vector2(L - w * 1.1, w),
	]), pal["body"])
	# 尖部撞色块（唯一装饰）
	BC.flat(r, PackedVector2Array([
		Vector2(L, 0.0), Vector2(L - w * 1.1, -w), Vector2(L - w * 1.1, w),
	]), pal["accent"], 1.4)
	# 一字剑格
	BC.flat(r, PackedVector2Array([
		Vector2(-0.5, -w * 1.75), Vector2(1.5, -w * 1.75),
		Vector2(1.5, w * 1.75), Vector2(-0.5, w * 1.75),
	]), pal["accent"], 1.6)
	# 柄 + 方首
	BC.bar(r, Vector2(-1.0, 0.0), Vector2(-L * 0.38, 0.0), 3.0, BC.INK)
	BC.square(r, Vector2(-L * 0.42, 0.0), 2.2, pal["body"])
	BC.star_studs(r, r.star, Vector2(L * 0.45, 0.0), Vector2(L * 0.2, 0.0), pal["accent"])

## 飞剑（金，无格）：双收尖细长菱镖 + 后掠双翼，无剑格——与长剑(平行刃+一字格)拉开
static func _sword_feijian(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = BC.pal(r.element)
	var L: float = r.tip_len
	var w: float = clampf(L * 0.085, 2.0, 3.2)
	# 后掠双翼（燕翼硬三角）：先画压在下层，自菱腰向后张开
	for s in [-1.0, 1.0]:
		BC.flat(r, PackedVector2Array([
			Vector2(L * 0.46, s * w * 0.55), Vector2(-L * 0.08, s * L * 0.32), Vector2(-L * 0.22, s * L * 0.14),
		]), pal["body"], 1.5)
	# 剑身：细长菱（前尖精确 (L,0)，后尖交到尾杆）
	BC.flat(r, PackedVector2Array([
		Vector2(L, 0.0), Vector2(L * 0.40, -w), Vector2(L * 0.02, 0.0), Vector2(L * 0.40, w),
	]), pal["body"])
	# 中脊撞色菱块（唯一装饰）
	BC.flat(r, PackedVector2Array([
		Vector2(L * 0.58, 0.0), Vector2(L * 0.50, -w * 0.72), Vector2(L * 0.42, 0.0), Vector2(L * 0.50, w * 0.72),
	]), pal["accent"], 1.0)
	# 短墨尾杆 + 撞色方尾
	BC.bar(r, Vector2(L * 0.04, 0.0), Vector2(-L * 0.30, 0.0), 2.4, BC.INK)
	BC.square(r, Vector2(-L * 0.34, 0.0), 1.6, pal["accent"], 1.1)
	BC.star_studs(r, r.star, Vector2(L * 0.70, 0.0), Vector2(-L * 0.12, 0.0), pal["accent"])

## 青藤剑（木）：宽柳叶身 + 基部对生叶芽，无金属格——叶形与长剑直刃拉开
static func _sword_qingteng(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = BC.pal(r.element)
	var L: float = r.tip_len
	var w: float = clampf(L * 0.15, 3.2, 5.0)
	# 叶身：两头收尖的宽柳叶（比飞刀厚实一档，器尖精确 (L,0)）
	BC.flat(r, PackedVector2Array([
		Vector2(L, 0.0), Vector2(L * 0.52, -w), Vector2(L * 0.06, -w * 0.55),
		Vector2(L * 0.06, w * 0.55), Vector2(L * 0.52, w),
	]), pal["body"])
	# 基部对生叶芽（撞色两小叶）
	BC.flat(r, PackedVector2Array([
		Vector2(L * 0.14, -w * 0.5), Vector2(L * 0.28, -w * 1.4), Vector2(L * 0.33, -w * 0.5),
	]), pal["accent"], 1.1)
	BC.flat(r, PackedVector2Array([
		Vector2(L * 0.14, w * 0.5), Vector2(L * 0.28, w * 1.4), Vector2(L * 0.33, w * 0.5),
	]), pal["accent"], 1.1)
	# 墨箍 + 木柄 + 方首
	BC.bar(r, Vector2(L * 0.04, -w * 0.75), Vector2(L * 0.04, w * 0.75), 2.2, BC.INK)
	BC.bar(r, Vector2(L * 0.02, 0.0), Vector2(-L * 0.42, 0.0), 3.0, BC.INK)
	BC.square(r, Vector2(-L * 0.46, 0.0), 2.2, pal["accent"], 1.2)
	BC.star_studs(r, r.star, Vector2(L * 0.62, 0.0), Vector2(L * 0.26, 0.0), pal["accent"])

## 桃木剑（木）：木条直身平斜切头 + 两道缠箍 + 无金属格——与青藤剑叶身、长剑直刃都不同
static func _sword_taomu(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = BC.pal(r.element)
	var L: float = r.tip_len
	var w: float = clampf(L * 0.10, 2.6, 3.8)
	# 木条剑身：刃口不开锋（平斜切头），器尖精确 (L,0)
	BC.flat(r, PackedVector2Array([
		Vector2(L, 0.0), Vector2(L - w * 1.6, -w), Vector2(L * 0.04, -w),
		Vector2(L * 0.04, w), Vector2(L - w * 1.6, w),
	]), pal["body"])
	# 两道缠箍（前撞色后墨，木剑读法全靠缠箍）
	BC.bar(r, Vector2(L * 0.56, -w * 1.25), Vector2(L * 0.56, w * 1.25), 2.0, pal["accent"])
	BC.bar(r, Vector2(L * 0.36, -w * 1.25), Vector2(L * 0.36, w * 1.25), 2.0, BC.INK)
	# 木柄直出（无格）+ 方首
	BC.bar(r, Vector2(L * 0.04, 0.0), Vector2(-L * 0.44, 0.0), 3.4, BC.INK)
	BC.square(r, Vector2(-L * 0.48, 0.0), 2.0, pal["body"], 1.2)
	BC.star_studs(r, r.star, Vector2(L * 0.76, 0.0), Vector2(L * 0.16, 0.0), pal["accent"])

## 流火飞剑（火，无格）：细直身 + 脊背两朵火舌锯齿——火舌是身份，与长剑/烈焰刀都拉开
static func _sword_liuhuo(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = BC.pal(r.element)
	var L: float = r.tip_len
	var w: float = clampf(L * 0.10, 2.6, 4.0)
	# 剑身：直刃 + 脊背两朵火舌（锯齿硬折线），器尖精确 (L,0)
	BC.flat(r, PackedVector2Array([
		Vector2(L, 0.0), Vector2(L - w * 1.2, -w),
		Vector2(L * 0.52, -w * 2.0), Vector2(L * 0.40, -w),
		Vector2(L * 0.26, -w * 2.0), Vector2(L * 0.14, -w),
		Vector2(0.0, -w), Vector2(0.0, w), Vector2(L - w * 1.2, w),
	]), pal["body"])
	# 火舌撞色（两朵火舌尖各补一小块）
	BC.flat(r, PackedVector2Array([
		Vector2(L * 0.50, -w * 1.72), Vector2(L * 0.52, -w * 2.0), Vector2(L * 0.42, -w * 1.72),
	]), pal["accent"], 0.9)
	BC.flat(r, PackedVector2Array([
		Vector2(L * 0.24, -w * 1.72), Vector2(L * 0.26, -w * 2.0), Vector2(L * 0.16, -w * 1.72),
	]), pal["accent"], 0.9)
	# 无格（飞剑族）：墨短柄 + 撞色方尾
	BC.bar(r, Vector2(0.0, 0.0), Vector2(-L * 0.30, 0.0), 2.6, BC.INK)
	BC.square(r, Vector2(-L * 0.34, 0.0), 1.8, pal["accent"], 1.2)
	BC.star_studs(r, r.star, Vector2(L * 0.66, w * 0.5), Vector2(L * 0.10, 0.0), pal["accent"])

## 寒霜剑（水）：宽根长冰凌 + 向前斜出的侧生冰枝 + 方首——冰棱分叉方向朝器尖，
## 与飞剑的后掠翼（向后）方向相反，两种「带翼尖器」不撞剪影
static func _sword_hanshuang(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = BC.pal(r.element)
	var L: float = r.tip_len
	var w: float = clampf(L * 0.15, 3.2, 5.0)
	# 侧生冰枝（上下各一根向前斜出，先画压下层）
	BC.flat(r, PackedVector2Array([
		Vector2(L * 0.44, -w * 0.42), Vector2(L * 0.68, -w * 1.55), Vector2(L * 0.57, -w * 0.28),
	]), pal["body"], 1.2)
	BC.flat(r, PackedVector2Array([
		Vector2(L * 0.28, w * 0.42), Vector2(L * 0.50, w * 1.55), Vector2(L * 0.41, w * 0.28),
	]), pal["body"], 1.2)
	# 冰凌主锋：宽根长锥，器尖精确 (L,0)
	BC.flat(r, PackedVector2Array([
		Vector2(L, 0.0), Vector2(L * 0.16, -w), Vector2(L * 0.16, w),
	]), pal["body"])
	# 尖前撞色菱（冰晶）
	BC.flat(r, PackedVector2Array([
		Vector2(L * 0.74, 0.0), Vector2(L * 0.65, -w * 0.45), Vector2(L * 0.56, 0.0), Vector2(L * 0.65, w * 0.45),
	]), pal["accent"], 1.0)
	# 墨箍 + 短柄 + 撞色方首
	BC.bar(r, Vector2(L * 0.14, 0.0), Vector2(-L * 0.34, 0.0), 3.0, BC.INK)
	BC.square(r, Vector2(-L * 0.39, 0.0), 2.1, pal["accent"], 1.2)
	BC.star_studs(r, r.star, Vector2(L * 0.34, 0.0), Vector2(-L * 0.14, 0.0), pal["accent"])

## 崩山剑（土）：崩山阔刃——前缘斜切收锋的宽砍刃 + 短粗柄，块头比长剑大两档
static func _sword_bengshan(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = BC.pal(r.element)
	var L: float = r.tip_len
	var h: float = L * 0.21
	# 阔刃：上缘斜切收锋（器尖精确 (L,0)），根缘直角
	BC.flat(r, PackedVector2Array([
		Vector2(L, 0.0), Vector2(L * 0.80, -h), Vector2(L * 0.12, -h),
		Vector2(L * 0.12, h * 0.78), Vector2(L * 0.62, h * 0.78),
	]), pal["body"])
	# 刃根撞色方箍
	BC.square(r, Vector2(L * 0.24, -h * 0.30), h * 0.30, pal["accent"], 1.3)
	# 短粗柄 + 大方首
	BC.bar(r, Vector2(L * 0.12, 0.0), Vector2(-L * 0.34, 0.0), 3.6, BC.INK)
	BC.square(r, Vector2(-L * 0.39, 0.0), 2.4, pal["body"])
	BC.star_studs(r, r.star, Vector2(L * 0.46, -h * 0.28), Vector2(L * 0.46, h * 0.28), pal["accent"])

# ---------------- 刀族分型：血饮狂刀(基准弯刀) / 烈焰刀(刀根火苗) ----------------
static func _saber(r: ProceduralWeaponRenderer) -> void:
	match String(r.weapon_id):
		"chiyan_dao":
			_saber_chiyan(r)
		_:
			_saber_xueyin(r)

## 血饮狂刀（火，刀族基准）：直背 + 鼓腹硬折线 + 背脊撞色条（样稿种子，勿改风格）
static func _saber_xueyin(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = BC.pal(r.element)
	var L: float = r.tip_len
	var w: float = clampf(L * 0.17, 3.2, 5.2)
	# 刀身：直背 + 鼓腹，硬折线不磨圆角
	BC.flat(r, PackedVector2Array([
		Vector2(0.0, -w), Vector2(L - w, -w), Vector2(L, -w * 0.22),
		Vector2(L - w * 0.66, w * 0.74), Vector2(L * 0.55, w * 1.35), Vector2(1.5, w * 1.04),
	]), pal["body"])
	# 背脊撞色条
	BC.flat(r, PackedVector2Array([
		Vector2(0.8, -w), Vector2(L - w * 1.1, -w),
		Vector2(L - w * 1.3, -w * 0.52), Vector2(1.4, -w * 0.48),
	]), pal["accent"], 1.2)
	# 一字格 + 柄 + 方首
	BC.flat(r, PackedVector2Array([
		Vector2(-0.5, -w * 1.5), Vector2(1.5, -w * 1.5),
		Vector2(1.5, w * 1.5), Vector2(-0.5, w * 1.5),
	]), pal["accent"], 1.6)
	BC.bar(r, Vector2(-1.0, 0.0), Vector2(-L * 0.36, 0.0), 3.0, BC.INK)
	BC.square(r, Vector2(-L * 0.40, 0.0), 2.2, pal["body"])
	BC.star_studs(r, r.star, Vector2(L * 0.42, w * 0.5), Vector2(L * 0.2, w * 0.8), pal["accent"])

## 烈焰刀（火）：鼓腹弯刀身 + 刀根脊上一大朵撞色火苗——与血饮狂刀(净身)靠火苗块区分
static func _saber_chiyan(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = BC.pal(r.element)
	var L: float = r.tip_len
	var w: float = clampf(L * 0.17, 3.2, 5.2)
	# 火苗块（先画压下层）：自刀根脊后探出的一大朵撞色火舌
	BC.flat(r, PackedVector2Array([
		Vector2(L * 0.14, -w * 0.7), Vector2(L * 0.26, -w * 2.4), Vector2(L * 0.44, -w * 1.0),
		Vector2(L * 0.36, -w * 0.4), Vector2(L * 0.20, -w * 0.3),
	]), pal["accent"], 1.1)
	# 刀身：与血饮狂刀同构（直背 + 鼓腹硬折线），器尖精确 (L,0)
	BC.flat(r, PackedVector2Array([
		Vector2(0.0, -w), Vector2(L - w, -w), Vector2(L, -w * 0.22),
		Vector2(L - w * 0.66, w * 0.74), Vector2(L * 0.55, w * 1.35), Vector2(1.5, w * 1.04),
	]), pal["body"])
	# 一字格 + 柄 + 方首
	BC.flat(r, PackedVector2Array([
		Vector2(-0.5, -w * 1.5), Vector2(1.5, -w * 1.5),
		Vector2(1.5, w * 1.5), Vector2(-0.5, w * 1.5),
	]), pal["accent"], 1.6)
	BC.bar(r, Vector2(-1.0, 0.0), Vector2(-L * 0.36, 0.0), 3.0, BC.INK)
	BC.square(r, Vector2(-L * 0.40, 0.0), 2.2, pal["body"])
	BC.star_studs(r, r.star, Vector2(L * 0.42, w * 0.5), Vector2(L * 0.2, w * 0.8), pal["accent"])

# ---------------- 匕首（柳叶飞刀）：主刀钉器尖 + 副刀后下错开，硬折线柳叶刃 ----------------
static func _dagger(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = BC.pal(r.element)
	var L: float = r.tip_len
	# 副刀：后缩下沉错开压下层（武器身份：分开的两把飞刀，同旧 BladeShapes 构图）
	_dart(r, pal, Vector2(-L * 0.16, L * 0.18), 0.84)
	# 主刀：刀尖精确顶 (L,0) 对齐出膛点
	_dart(r, pal, Vector2.ZERO, 1.0)
	# 升星方钉：主刀刃身一颗，★3 再补副刀刃身一颗（双刀齐升）
	BC.star_studs(r, r.star,
		Vector2(L * 0.38, 0.0), Vector2(-L * 0.16 + L * 0.84 * 0.38, L * 0.18), pal["accent"])

## 单把飞刀：细长硬折线柳叶刃 + 撞色一字横档 + 墨短柄方尾（砍尾环青穗）
static func _dart(r: ProceduralWeaponRenderer, pal: Dictionary, off: Vector2, k: float) -> void:
	var L: float = r.tip_len * k
	var w: float = clampf(L * 0.10, 1.8, 2.8)
	# 刃身：细长柳叶（肩宽收窄、根收拢，尖角细长不磨角）
	BC.flat(r, PackedVector2Array([
		off + Vector2(L, 0.0),
		off + Vector2(L * 0.55, -w),
		off + Vector2(L * 0.12, -w * 0.55),
		off + Vector2(L * 0.12, w * 0.55),
		off + Vector2(L * 0.55, w),
	]), pal["body"])
	# 一字横档（撞色，箍住刃根）
	BC.flat(r, PackedVector2Array([
		off + Vector2(L * 0.13, -w * 1.4), off + Vector2(L * 0.05, -w * 1.4),
		off + Vector2(L * 0.05, w * 1.4), off + Vector2(L * 0.13, w * 1.4),
	]), pal["accent"], 1.4)
	# 短柄 + 方尾
	BC.bar(r, off + Vector2(L * 0.05, 0.0), off + Vector2(-L * 0.06, 0.0), 2.0, BC.INK)
	BC.square(r, off + Vector2(-L * 0.075, 0.0), 1.2, pal["body"], 1.0)

# ---------------- 手里剑：硬边四芒星 + 撞色心环 + 墨透孔 ----------------
static func _shuriken(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = BC.pal(r.element)
	var L: float = r.tip_len
	# 四芒星：四尖落正交方向（主尖精确 (L,0)），谷点落 45° 方向，全直边硬折线
	# （旧背弧/腹弧/月牙磨刃全部折线化成八点星，保留四芒旋刃剪影与中心透孔）
	var vr: float = L * 0.42
	var ck: float = 0.7071
	BC.flat(r, PackedVector2Array([
		Vector2(L, 0.0), Vector2(vr * ck, vr * ck),
		Vector2(0.0, L), Vector2(-vr * ck, vr * ck),
		Vector2(-L, 0.0), Vector2(-vr * ck, -vr * ck),
		Vector2(0.0, -L), Vector2(vr * ck, -vr * ck),
	]), pal["body"])
	# 中心透孔（墨盘带硬投影）+ 撞色心环（旧「内外金属环」的平涂化）
	BC.disc(r, Vector2.ZERO, L * 0.20, BC.INK, 1.0)
	BC.ring(r, Vector2.ZERO, L * 0.30, 1.8, pal["accent"])
	BC.star_studs(r, r.star, Vector2(L * 0.58, 0.0), Vector2(L * 0.34, 0.0), pal["accent"])

# ---------------- 斧（开山斧）：粗长柄 + 硬折线月牙刃 + 刃背撞色厚脊 ----------------
static func _axe(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = BC.pal(r.element)
	var L: float = r.tip_len
	# 长柄：自柄尾穿进月牙缺口、藏进刃根（压在刃下层）
	BC.bar(r, Vector2(-L * 0.80, 0.0), Vector2(L * 0.56, 0.0), 3.4, BC.PAPER.darkened(0.25))
	# 柄尾方钉
	BC.square(r, Vector2(-L * 0.84, 0.0), 2.0, pal["accent"], 1.2)
	# 月牙刃：外缘两段折线鼓出（月牙弧硬折线化），内缘 V 形大缺口咬向刃根，刃尖精确 (L,0)
	BC.flat(r, PackedVector2Array([
		Vector2(L * 0.12, -L * 0.72), Vector2(L * 0.62, -L * 0.52), Vector2(L, 0.0),
		Vector2(L * 0.62, L * 0.52), Vector2(L * 0.12, L * 0.72), Vector2(L * 0.55, 0.0),
	]), pal["body"])
	# 厚脊撞色竖块：压在刃背，让月牙缺口敞开成「透空的月牙弯」
	BC.bar(r, Vector2(L * 0.10, -L * 0.66), Vector2(L * 0.10, L * 0.66), 3.0, pal["accent"])
	BC.star_studs(r, r.star, Vector2(L * 0.56, -L * 0.20), Vector2(L * 0.56, L * 0.20), pal["accent"])

# ---------------- 剪（金蛟剪）：双刃 V 形交叉 + 墨柄连指环 + 撞色转轴 ----------------
static func _shears(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = BC.pal(r.element)
	var L: float = r.tip_len
	# 两片剪刃：自转轴向 +X 张开成 V（下刃后画压上层，旧同构），直边厚身细长条
	for s in [-1.0, 1.0]:
		# 柄梗：自刃根连到指环（旧画法刃与环脱开，这里补一根墨梗保住剪刀读法）
		BC.bar(r, Vector2(-L * 0.08, s * L * 0.12), Vector2(-L * 0.50, s * L * 0.28), 2.0, BC.INK)
		# 指环（墨环白芯，旧 edge 弧环的平涂化）
		BC.ring(r, Vector2(-L * 0.58, s * L * 0.30), L * 0.18, 2.2, pal["body"])
		# 剪刃：加厚硬边四边条（太薄会被硬投影吃成双影），刃尖精确落 (L, ±0.30L)
		BC.flat(r, PackedVector2Array([
			Vector2(L, s * L * 0.30), Vector2(L * 0.88, s * L * 0.10),
			Vector2(-L * 0.10, s * L * 0.03), Vector2(-L * 0.10, s * L * 0.22),
		]), pal["body"])
	# 转轴方钉（撞色，铆在双刃交点上）
	BC.square(r, Vector2(-L * 0.12, 0.0), 1.9, pal["accent"])
	# 升星方钉落指环心（环心铆钉；细刃身会被钉的墨描边切断剪影，故不落刃上）
	BC.star_studs(r, r.star, Vector2(-L * 0.58, L * 0.30), Vector2(-L * 0.58, -L * 0.30), pal["accent"])

# ---------------- 钉（透骨钉）：方帽撞色 + 直脊长钉身 ----------------
static func _nail(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = BC.pal(r.element)
	var L: float = r.tip_len
	var w: float = clampf(L * 0.11, 1.8, 2.8)
	# 钉身：方直长脊向 +X 收尖（尖段拉长保住「钉尖」读法），钉尖精确 (L,0)
	BC.flat(r, PackedVector2Array([
		Vector2(L, 0.0), Vector2(L * 0.52, -w),
		Vector2(-L * 0.44, -w), Vector2(-L * 0.44, w),
		Vector2(L * 0.52, w),
	]), pal["body"])
	# 方帽（撞色一方铁帽压尾，前沿咬住钉身）
	BC.flat(r, PackedVector2Array([
		Vector2(-L * 0.40, -w * 1.9), Vector2(-L * 0.70, -w * 1.9),
		Vector2(-L * 0.70, w * 1.9), Vector2(-L * 0.40, w * 1.9),
	]), pal["accent"], 1.4)
	BC.star_studs(r, r.star, Vector2(L * 0.42, 0.0), Vector2(L * 0.12, 0.0), pal["accent"])

# ---------------- 针族分型：暴雨针(成束基准) / 冰针(单根冰凌) ----------------
static func _needles(r: ProceduralWeaponRenderer) -> void:
	match String(r.weapon_id):
		"xuanbing_feizhen":
			_needle_ice(r)
		_:
			_needles_rain(r)

## 暴雨针（金，针族基准）：成束三针 + 撞色束口（样稿种子，勿改风格）
static func _needles_rain(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = BC.pal(r.element)
	var L: float = r.tip_len
	# 三根细针并排（上/中/下）：中心针精确顶 (L,0)，上下针向尖收敛（旧宿主画法同构）
	for i in range(3):
		var off: float = (float(i) - 1.0) * L * 0.20
		var tip := Vector2(L, off * 0.35)
		var tail := Vector2(-L * 0.66, off)
		# 细针用 draw_line 直画（BC.bar 的描边对细针太肥）：硬投影 + 墨身 + 主色芯
		r.draw_line(tail + Vector2(2.0, 2.0), tip + Vector2(2.0, 2.0), BC.SHADOW, 4.6, true)
		r.draw_line(tail, tip, BC.INK, 2.2, true)
		r.draw_line(tail, tip, pal["body"], 1.0, true)
	# 束口（撞色竖箍缠住针尾）
	BC.bar(r, Vector2(-L * 0.58, -L * 0.26), Vector2(-L * 0.58, L * 0.26), 2.6, pal["accent"])
	BC.star_studs(r, r.star, Vector2(L * 0.45, 0.0), Vector2(-L * 0.30, 0.0), pal["accent"])

## 冰针（水）：单根长冰凌 + 侧生两根小冰刺——与暴雨针的三针束拉开剪影
static func _needle_ice(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = BC.pal(r.element)
	var L: float = r.tip_len
	# 侧生冰刺（上下各一小棱、向后收，先画压下层）
	BC.flat(r, PackedVector2Array([
		Vector2(L * 0.46, 0.0), Vector2(L * 0.22, -L * 0.24), Vector2(L * 0.08, 0.0),
	]), pal["body"], 1.0)
	BC.flat(r, PackedVector2Array([
		Vector2(L * 0.28, 0.0), Vector2(L * 0.06, L * 0.22), Vector2(-L * 0.06, 0.0),
	]), pal["body"], 1.0)
	# 主冰针：一根长冰凌（中心针精确顶 (L,0)）
	r.draw_line(Vector2(-L * 0.42, 0.0) + Vector2(2.0, 2.0), Vector2(L, 0.0) + Vector2(2.0, 2.0), BC.SHADOW, 4.6, true)
	r.draw_line(Vector2(-L * 0.42, 0.0), Vector2(L, 0.0), BC.INK, 2.2, true)
	r.draw_line(Vector2(-L * 0.42, 0.0), Vector2(L, 0.0), pal["body"], 1.0, true)
	# 尾箍（撞色）+ 星钉
	BC.bar(r, Vector2(-L * 0.34, -L * 0.11), Vector2(-L * 0.34, L * 0.11), 2.2, pal["accent"])
	BC.star_studs(r, r.star, Vector2(L * 0.60, 0.0), Vector2(-L * 0.14, 0.0), pal["accent"])

# ---------------- 锥（金雷锥）：硬折线长锥 + 前撞色后墨双箍环 + 方锥尾 ----------------
static func _awl(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = BC.pal(r.element)
	var L: float = r.tip_len
	var w: float = clampf(L * 0.12, 2.2, 3.4)
	var tail: float = -L * 0.55
	# 锥身：尾宽首尖硬折线长锥（六棱锥折线化），锥尖精确 (L,0)
	BC.flat(r, PackedVector2Array([
		Vector2(L, 0.0), Vector2(L * 0.30, -w), Vector2(tail, -w),
		Vector2(tail - w * 0.45, 0.0), Vector2(tail, w), Vector2(L * 0.30, w),
	]), pal["body"])
	# 双箍环：前撞色后墨、拉开间距（旧双箍环平涂化，砍雷纹折线）
	BC.bar(r, Vector2(-L * 0.26, -w * 1.15), Vector2(-L * 0.26, w * 1.15), 2.2, pal["accent"])
	BC.bar(r, Vector2(-L * 0.46, -w * 1.15), Vector2(-L * 0.46, w * 1.15), 2.2, BC.INK)
	# 方锥尾（旧圆锥首方块化）
	BC.square(r, Vector2(tail - w * 0.75, 0.0), w * 0.62, pal["body"], 1.2)
	BC.star_studs(r, r.star, Vector2(L * 0.55, 0.0), Vector2(L * 0.22, 0.0), pal["accent"])
