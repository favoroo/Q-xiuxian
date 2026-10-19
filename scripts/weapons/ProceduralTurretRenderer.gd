class_name ProceduralTurretRenderer
extends Node2D

## 纯矢量机关炮台本体渲染器（冷冽国风）
## 取代 TurretUnit.CoreSprite 那张 48×48 AI 贴图，与角色/敌人/法器/弹丸同一套矢量画风。
##
## 【坐标契约 — 与 TurretUnit.CoreSprite / MuzzlePoint 严格对齐】
##   · 在【画布像素】空间沿 +X 绘制（+X = 炮口/攻击朝向），炮口落在 muzzle_len 附近；
##   · 外部把本节点 scale 设成 0.55（与旧 Sprite2D 同尺寸），节点 rotation 即索敌角；
##   · TurretUnit 的底座八角阵盘仍由它自己的 _draw 画，本渲染器只负责「盘上那台机体」。
##
## 灰度切换：shape == GENERIC（未实现器形）时由 TurretUnit 保留原贴图显示。

enum TurretShape {
	CROSSBOW,   ## 弩机：弩臂 + 弓弦 + 弩身（机关弩 / 凝冰机弩）
	ARRAY_DISC, ## 阵盘：外环阵纹 + 中心灵核 + 辐条（剑阵盘）
	CANNON,     ## 炮管：粗炮身 + 炮口 + 机座（青木炮）
	BEAST,      ## 机关兽：兽首 + 獠牙 + 颈部机括（喷火兽 / 寒泉兽 / 傀儡兽）
	TREBUCHET,  ## 投石机：抛臂 + 配重 + 石弹（垒石机关 / 藤萝机关）
	TOWER,      ## 灯塔：塔身 + 灯窗 + 塔顶火盆（烽火台）
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
const ART_SCALE := 1.5

func _draw_mount(pal: Dictionary, rx: float) -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(ART_SCALE, 0.62 * ART_SCALE))
	AdaptiveDraw.circle(self, Vector2.ZERO, rx, Color(0.03, 0.04, 0.06, 0.55))
	AdaptiveDraw.circle(self, Vector2.ZERO, rx * 0.78, pal["frame"])
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(ART_SCALE, ART_SCALE))

# ---------------- 弩机（弩臂 + 弓弦 + 弩身） ----------------
func _draw_crossbow() -> void:
	var pal := _palette()
	var edge: Color = pal["edge"]
	var metal: Color = pal["light"]
	_draw_mount(pal, 11.0)
	# 弩身（沿 +X）
	_fill_outlined(PackedVector2Array([
		Vector2(15.0, -2.0), Vector2(15.0, 2.0), Vector2(-9.0, 2.6),
		Vector2(-11.0, 0.0), Vector2(-9.0, -2.6),
	]), metal)
	# 弩臂（横向弓臂，略向前弯）
	var limb := PackedVector2Array()
	const SEG := 8
	for i in range(SEG + 1):
		var t := float(i) / float(SEG)
		limb.append(Vector2(lerpf(-4.0, 9.0, t) - sin(t * PI) * 2.5, lerpf(-10.0, -1.6, t)))
	for i in range(SEG + 1):
		var t := float(1.0 - float(i) / float(SEG))
		limb.append(Vector2(lerpf(-4.0, 9.0, t) - sin(t * PI) * 2.5, lerpf(10.0, 1.6, t)))
	draw_colored_polygon(limb, pal["dark"])
	# 弓弦
	draw_line(Vector2(-3.0, -10.0), Vector2(-3.0, 10.0), Color(0.92, 0.90, 0.82, 0.9), 0.8, true)
	# 弩箭
	draw_line(Vector2(-3.0, 0.0), Vector2(16.0, 0.0), Color(0.94, 0.92, 0.84), 1.2, true)
	draw_colored_polygon(PackedVector2Array([
		Vector2(16.0, 0.0), Vector2(12.8, -1.6), Vector2(12.8, 1.6)]), edge)
	_draw_core_fx(pal, Vector2(-6.0, 0.0), 1.5)

# ---------------- 阵盘（外环阵纹 + 中心灵核 + 辐条） ----------------
func _draw_array_disc() -> void:
	var pal := _palette()
	var edge: Color = pal["edge"]
	# 盘面
	AdaptiveDraw.circle(self, Vector2.ZERO, 13.0, Color(0.06, 0.07, 0.10, 0.9))
	AdaptiveDraw.circle(self, Vector2.ZERO, 11.6, pal["dark"].darkened(0.15))
	# 外环阵纹
	AdaptiveDraw.arc(self, Vector2.ZERO, 12.2, 0.0, TAU, edge, 1.4, true)
	# 辐条（8 根）
	for i in range(8):
		var a := TAU * float(i) / 8.0
		draw_line(Vector2(cos(a), sin(a)) * 4.2, Vector2(cos(a), sin(a)) * 10.6,
			Color(edge.r, edge.g, edge.b, 0.75), 1.1, true)
	# 中心灵核
	AdaptiveDraw.circle(self, Vector2.ZERO, 3.4, Color(0.06, 0.07, 0.10))
	_draw_core_fx(pal, Vector2.ZERO, 1.7)

# ---------------- 炮管（粗炮身 + 炮口 + 机座） ----------------
func _draw_cannon() -> void:
	var pal := _palette()
	var edge: Color = pal["edge"]
	_draw_mount(pal, 11.0)
	# 炮身（前粗后细，沿 +X）
	_fill_outlined(PackedVector2Array([
		Vector2(16.0, -4.2), Vector2(16.0, 4.2), Vector2(-2.0, 3.0),
		Vector2(-9.0, 2.0), Vector2(-9.0, -2.0), Vector2(-2.0, -3.0),
	]), pal["light"].darkened(0.08))
	# 炮口环 + 箍
	draw_line(Vector2(15.4, -4.4), Vector2(15.4, 4.4), edge.darkened(0.15), 2.0, true)
	draw_line(Vector2(4.0, -3.8), Vector2(4.0, 3.8), pal["dark"], 1.6, true)
	draw_line(Vector2(-4.0, -2.8), Vector2(-4.0, 2.8), pal["dark"], 1.4, true)
	# 炮口内膛
	AdaptiveDraw.circle(self, Vector2(16.0, 0.0), 3.0, Color(0.04, 0.05, 0.08))
	_draw_core_fx(pal, Vector2(15.5, 0.0), 1.6)

# ---------------- 机关兽（兽首 + 双角 + 张口 + 颈部机括） ----------------
## 小尺寸下要一眼读成"兽"：靠「上宽下窄的楔形头 + 两只后掠角 + 前方张开的黑口」三个剪影特征，
## 细节（獠牙/铆钉/眼）只做点缀。
func _draw_beast() -> void:
	var pal := _palette()
	var edge: Color = pal["edge"]
	var hide_col: Color = pal["light"].darkened(0.10)
	# 颈部机括（后段，暗色方匣）
	_fill_outlined(PackedVector2Array([
		Vector2(-3.0, -5.6), Vector2(-3.0, 5.6), Vector2(-12.0, 4.4),
		Vector2(-12.0, -4.4),
	]), pal["frame"].lerp(pal["light"], 0.22))
	# 双角（后掠，从颅顶向 -X 上方伸出）
	for s in [-1.0, 1.0]:
		draw_colored_polygon(PackedVector2Array([
			Vector2(6.0, s * 3.4), Vector2(-1.5, s * 10.5), Vector2(1.0, s * 3.2),
		]), pal["dark"].darkened(0.25))
	# 颅骨（楔形：后宽前窄）
	_fill_outlined(PackedVector2Array([
		Vector2(16.0, -2.2), Vector2(13.5, -5.8), Vector2(4.0, -7.0),
		Vector2(-4.0, -5.4), Vector2(-4.0, 5.4), Vector2(4.0, 7.0),
		Vector2(13.5, 5.8), Vector2(16.0, 2.2),
	]), hide_col)
	# 张口：前方上下嘴之间楔形黑口
	draw_colored_polygon(PackedVector2Array([
		Vector2(16.2, -1.6), Vector2(9.0, -0.4), Vector2(9.0, 0.4), Vector2(16.2, 1.6),
	]), Color(0.03, 0.03, 0.05, 0.95))
	# 獠牙（口内上下各一）
	for s in [-1.0, 1.0]:
		draw_colored_polygon(PackedVector2Array([
			Vector2(14.6, s * 1.5), Vector2(16.4, s * 2.2), Vector2(13.6, s * 2.4)]),
			Color(0.96, 0.95, 0.88))
	# 鼻梁脊线
	draw_line(Vector2(15.4, 0.0), Vector2(6.0, 0.0), Color(0.06, 0.06, 0.08), 1.2, true)
	# 兽眼（HDR 起辉）
	_draw_core_fx(pal, Vector2(4.6, 0.0), 1.5)
	# 颈部铆钉
	for i in range(3):
		AdaptiveDraw.circle(self, Vector2(-6.5 - float(i) * 2.4, 0.0), 0.9, edge)

# ---------------- 投石机（抛臂 + 配重 + 石弹） ----------------
func _draw_trebuchet() -> void:
	var pal := _palette()
	var edge: Color = pal["edge"]
	var wood: Color = pal["frame"].lerp(pal["light"], 0.45)
	# 底座三角架
	draw_line(Vector2(-11.0, 6.0), Vector2(0.0, -3.0), wood, 2.6, true)
	draw_line(Vector2(-11.0, -6.0), Vector2(0.0, -3.0), wood, 2.6, true)
	draw_line(Vector2(-11.0, 6.0), Vector2(-11.0, -6.0), wood, 2.2, true)
	# 抛臂（斜向 +X 上方）
	draw_line(Vector2(-8.0, 3.0), Vector2(16.0, -8.0), Color(0.06, 0.06, 0.08), 3.2, true)
	draw_line(Vector2(-8.0, 3.0), Vector2(16.0, -8.0), wood, 2.0, true)
	# 配重（尾端石块）
	AdaptiveDraw.circle(self, Vector2(-9.0, 3.6), 3.0, Color(0.06, 0.07, 0.10))
	AdaptiveDraw.circle(self, Vector2(-9.0, 3.6), 2.2, pal["dark"])
	# 石弹（臂端）
	AdaptiveDraw.circle(self, Vector2(16.0, -8.0), 2.8, Color(0.06, 0.07, 0.10))
	AdaptiveDraw.circle(self, Vector2(16.0, -8.0), 2.0, pal["light"])
	# 抛索
	draw_line(Vector2(16.0, -8.0), Vector2(12.0, -10.5), edge, 0.9, true)
	_draw_core_fx(pal, Vector2(-1.0, 0.0), 1.4)

# ---------------- 灯塔（塔身 + 灯窗 + 塔顶火盆） ----------------
func _draw_tower() -> void:
	var pal := _palette()
	var edge: Color = pal["edge"]
	# 塔身（下宽上窄）
	_fill_outlined(PackedVector2Array([
		Vector2(-6.0, -10.0), Vector2(6.0, -10.0), Vector2(8.5, 8.0),
		Vector2(-8.5, 8.0),
	]), pal["dark"].darkened(0.1))
	# 塔身腰箍
	draw_line(Vector2(-7.4, -2.0), Vector2(7.4, -2.0), edge.darkened(0.25), 1.6, true)
	draw_line(Vector2(-8.0, 4.0), Vector2(8.0, 4.0), edge.darkened(0.25), 1.6, true)
	# 灯窗（HDR 起辉的方窗）
	draw_rect(Rect2(-2.6, -7.4, 5.2, 4.6), Color(0.04, 0.05, 0.08), true)
	draw_rect(Rect2(-2.0, -6.8, 4.0, 3.4), Color(pal["hdr"].r, pal["hdr"].g, pal["hdr"].b, 0.85), true)
	# 塔顶火盆
	draw_line(Vector2(-5.0, -10.6), Vector2(5.0, -10.6), edge, 1.8, true)
	AdaptiveDraw.circle(self, Vector2(0.0, -12.4), 2.2, Color(pal["hdr"].r, pal["hdr"].g, pal["hdr"].b, 0.35))
	AdaptiveDraw.circle(self, Vector2(0.0, -12.4), 1.4, pal["hdr"])
	_draw_core_fx(pal, Vector2(0.0, -5.0), 1.4)
