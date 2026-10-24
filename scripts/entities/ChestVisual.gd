class_name ChestVisual
extends Node2D

## 程序绘制的藏宝匣造型：_draw 平面色块，无贴图，三档（木/铜/玉）共用一套几何，
## 靠材质配色区分品质 —— 木=棕木铁箍、铜=青铜红绸、玉=青玉金箍嵌宝。
## 结构分层（2026-10-23 质感升级）：盖檐投影 + 镶板内凹框 + 四角金属包角 +
## 挂锁（锁梁+锁体）+ 分档材质细节（木纹/绸带压褶铜扣/玉质高光带），
## 全部压在原 96×87 轮廓内 —— 轮廓不变，判定圆不受影响。
## 坐标口径沿用旧贴图画布：96×87、原点居中（匣心），宿主按
## BASE_SCALE × SIZE_MULT × 档位倍率缩放，画多大 == 判多大（AGENTS.md 铁律 7）。
## 受击闪白/受损变暗靠宿主的 modulate，CanvasItem 绘制天然吃这一套，不必另画受损相。

# ---------------- 几何（画布单位） ----------------

const HALF_W := 44.0      ## 匣体半宽：贴画布左右，×0.53 后与判定圆同宽
const BODY_TOP := -2.0    ## 盖/身接缝线
const BODY_BOT := 36.0    ## 匣底
const CHAMFER := 7.0      ## 匣底两角斜切
const LID_TOP := -38.0    ## 盖顶平台高度
const LID_FLAT := 30.0    ## 盖顶平台半宽，之外向两侧斜收成弧顶
const STRAP_CX := 28.0    ## 箍带中线离匣心
const STRAP_HW := 5.5     ## 箍带半宽
const OUTLINE := Color("1c130c")  ## 全匣统一深色勾边

## 盖顶轮廓：|x| ≤ LID_FLAT 是平台，之外线性斜收到 HALF_W 处的侧沿
static func lid_top_y(x: float) -> float:
	var ax := absf(x)
	if ax <= LID_FLAT:
		return LID_TOP
	return LID_TOP + (ax - LID_FLAT) / (HALF_W - LID_FLAT) * 12.0

## 盖顶平台处的侧沿高度（斜收终点）
static func lid_side_y() -> float:
	return lid_top_y(HALF_W)

# ---------------- 三档配色 ----------------

## 每档一套：身/盖/盖顶高光/板缝/箍带/箍带高光/锁面/锁面高光/点缀（绸带或嵌宝，无色即不画）
const PALETTES: Array[Dictionary] = [
	{ # 木匣：棕木 + 铁箍 + 铜锁
		"body": Color("7a5330"), "lid": Color("8d6338"), "lid_hi": Color("b08454"),
		"seam": Color("503620"), "strap": Color("4a4642"), "strap_hi": Color("6a655f"),
		"lock": Color("c9a227"), "lock_hi": Color("e3c25a"),
		"accent": Color(0, 0, 0, 0), "glow": Color(0, 0, 0, 0),
	},
	{ # 铜匣：青铜 + 红绸中带 + 金锁
		"body": Color("a06a34"), "lid": Color("b57d40"), "lid_hi": Color("d29a58"),
		"seam": Color("6e4520"), "strap": Color("7c4f22"), "strap_hi": Color("a8743a"),
		"lock": Color("e8c35a"), "lock_hi": Color("f5dd8e"),
		"accent": Color("b03a2e"), "glow": Color(0.91, 0.76, 0.35, 0.10),
	},
	{ # 玉匣：青玉 + 金箍 + 朱砂嵌宝
		"body": Color("2f8f6a"), "lid": Color("3fae8a"), "lid_hi": Color("67d1a8"),
		"seam": Color("1f6b4c"), "strap": Color("d9a83c"), "strap_hi": Color("f2cd6e"),
		"lock": Color("f2cd6e"), "lock_hi": Color("fce9ac"),
		"accent": Color("e2503c"), "glow": Color(0.31, 0.82, 0.65, 0.14),
	},
]

## 档位（0 木 / 1 铜 / 2 玉），写入即重绘
var tier: int = BalanceChest.TIER_WOOD:
	set(v):
		tier = clampi(v, 0, BalanceChest.TIER_COUNT - 1)
		queue_redraw()

func _draw() -> void:
	var p: Dictionary = PALETTES[tier]
	# 地面落影：外层弥散 + 内核接触暗斑，垫在匣底下
	draw_colored_polygon(_ellipse(Vector2(0, BODY_BOT + 3), 40.0, 6.5), Color(0, 0, 0, 0.34))
	draw_colored_polygon(_ellipse(Vector2(0, BODY_BOT + 3), 26.0, 4.4), Color(0, 0, 0, 0.62))
	# 品阶地光（纯装饰）：铜暖金/玉青碧淡光晕罩在落影上，小尺寸一眼分档，木匣无光
	if p.glow.a > 0.0:
		draw_colored_polygon(_ellipse(Vector2(0, BODY_BOT + 3), 46.0, 9.0), p.glow)

	# 匣身（底角斜切）
	var body := PackedVector2Array([
		Vector2(-HALF_W, BODY_TOP), Vector2(HALF_W, BODY_TOP),
		Vector2(HALF_W, BODY_BOT - CHAMFER), Vector2(HALF_W - CHAMFER, BODY_BOT),
		Vector2(-HALF_W + CHAMFER, BODY_BOT), Vector2(-HALF_W, BODY_BOT - CHAMFER),
	])
	draw_colored_polygon(body, p.body)
	# 盖檐投影：盖子压在匣身上的深色窄带，平地起层叠
	draw_rect(Rect2(-HALF_W + 1, BODY_TOP, HALF_W * 2.0 - 2, 3.5), p.seam)
	# 身板横缝两道
	draw_line(Vector2(-HALF_W + 2, 10), Vector2(HALF_W - 2, 10), p.seam, 2.0)
	draw_line(Vector2(-HALF_W + 2, 21), Vector2(HALF_W - 2, 21), p.seam, 2.0)
	# 三道身板各收一圈内凹框线：板面读出「镶板」结构（底板内缩多让斜切角）
	draw_rect(Rect2(-HALF_W + 4, 0.5, HALF_W * 2.0 - 8, 7.0), p.seam, false, 1.5)
	draw_rect(Rect2(-HALF_W + 4, 12.5, HALF_W * 2.0 - 8, 6.0), p.seam, false, 1.5)
	draw_rect(Rect2(-HALF_W + 5.5, 23.5, HALF_W * 2.0 - 11, 7.0), p.seam, false, 1.5)
	# 木匣板面木纹：短线错落，避开箍带位
	if tier == BalanceChest.TIER_WOOD:
		draw_line(Vector2(-18, 5), Vector2(-7, 5), p.seam, 1.5)
		draw_line(Vector2(3, 15.5), Vector2(16, 15.5), p.seam, 1.5)
		draw_line(Vector2(-15, 26.5), Vector2(-4, 26.5), p.seam, 1.5)
		draw_line(Vector2(9, 26.5), Vector2(19, 26.5), p.seam, 1.5)
	# 玉匣板面斜向玉质高光宽带
	if tier == BalanceChest.TIER_JADE:
		draw_colored_polygon(PackedVector2Array([
			Vector2(-30, BODY_BOT - 2), Vector2(-14, BODY_TOP + 4),
			Vector2(-4, BODY_TOP + 4), Vector2(-20, BODY_BOT - 2),
		]), Color(p.lid_hi, 0.30))
	# 右侧与匣底压暗，平地起体积（平面风，不用渐变）
	draw_polyline(PackedVector2Array([
		Vector2(HALF_W - 1, BODY_TOP + 1), Vector2(HALF_W - 1, BODY_BOT - CHAMFER),
		Vector2(HALF_W - CHAMFER, BODY_BOT - 1), Vector2(-HALF_W + CHAMFER, BODY_BOT - 1),
		Vector2(-HALF_W + 1, BODY_BOT - CHAMFER),
	]), p.seam, 3.0)
	# 左侧细受光棱，与右/底压暗呼应
	draw_line(Vector2(-HALF_W + 2, BODY_TOP + 2), Vector2(-HALF_W + 2, BODY_BOT - CHAMFER), p.strap_hi, 2.0)

	# 匣盖（平顶斜收弧顶）
	var lid := PackedVector2Array([
		Vector2(-HALF_W, BODY_TOP), Vector2(-HALF_W, lid_side_y()),
		Vector2(-LID_FLAT, LID_TOP), Vector2(LID_FLAT, LID_TOP),
		Vector2(HALF_W, lid_side_y()), Vector2(HALF_W, BODY_TOP),
	])
	draw_colored_polygon(lid, p.lid)
	# 盖顶平台受光带：顶面朝天，比立面亮一档
	draw_rect(Rect2(-LID_FLAT + 2, LID_TOP + 1.5, LID_FLAT * 2.0 - 4, 4.0), Color(p.lid_hi, 0.45))
	# 盖板竖缝两道（避开箍带与中带的位置）
	for sx in [-10.0, 10.0]:
		draw_line(Vector2(sx, lid_top_y(sx) + 2), Vector2(sx, BODY_TOP - 1), p.seam, 2.0)
	# 盖顶受光棱线
	draw_polyline(PackedVector2Array([
		Vector2(-HALF_W + 2, lid_side_y() - 1), Vector2(-LID_FLAT + 1, LID_TOP + 1.5),
		Vector2(LID_FLAT - 1, LID_TOP + 1.5), Vector2(HALF_W - 2, lid_side_y() - 1),
	]), p.lid_hi, 2.5)
	# 盖身接缝线：玉匣描金与金箍呼应，木/铜描深 —— 压在绸带/箍带/锁面之下
	if tier == BalanceChest.TIER_JADE:
		draw_line(Vector2(-HALF_W, BODY_TOP), Vector2(HALF_W, BODY_TOP), p.strap, 2.5)
	else:
		draw_line(Vector2(-HALF_W, BODY_TOP), Vector2(HALF_W, BODY_TOP), OUTLINE, 2.5)

	# 铜匣红绸中带：整条竖带从盖顶缠到匣底，带身两道压褶 + 盖段一枚铜扣，压在锁面下
	if tier == BalanceChest.TIER_COPPER:
		draw_colored_polygon(PackedVector2Array([
			Vector2(-8, lid_top_y(-8.0)), Vector2(8, lid_top_y(8.0)),
			Vector2(8, BODY_BOT), Vector2(-8, BODY_BOT),
		]), p.accent)
		draw_line(Vector2(-8, lid_top_y(-8.0) + 2), Vector2(-8, BODY_BOT - 1), OUTLINE, 1.5)
		draw_line(Vector2(8, lid_top_y(8.0) + 2), Vector2(8, BODY_BOT - 1), OUTLINE, 1.5)
		draw_line(Vector2(-8, 18), Vector2(8, 18), OUTLINE, 1.2)
		draw_line(Vector2(-8, 30), Vector2(8, 30), OUTLINE, 1.2)
		draw_circle(Vector2(0, -20), 2.8, p.lock)
		draw_circle(Vector2(0, -20), 2.8, OUTLINE, false, 1.0)

	# 两道箍带：盖段随盖顶轮廓斜收，身段直落到匣底；左棱受光 + 右棱压暗 + 盖段身段各一铆钉
	for cx: float in [-STRAP_CX, STRAP_CX]:
		var x0: float = cx - STRAP_HW
		var x1: float = cx + STRAP_HW
		draw_colored_polygon(PackedVector2Array([
			Vector2(x0, BODY_TOP), Vector2(x0, lid_top_y(x0)),
			Vector2(x1, lid_top_y(x1)), Vector2(x1, BODY_TOP),
		]), p.strap)
		draw_rect(Rect2(x0, BODY_TOP, STRAP_HW * 2.0, BODY_BOT - BODY_TOP), p.strap)
		draw_line(Vector2(x0 + 1.5, lid_top_y(x0) + 1), Vector2(x0 + 1.5, BODY_BOT - 2), p.strap_hi, 2.0)
		draw_line(Vector2(x1 - 1.5, lid_top_y(x1) + 1), Vector2(x1 - 1.5, BODY_BOT - 2), p.seam, 1.5)
		draw_circle(Vector2(cx, 16), 2.5, p.strap_hi)
		draw_circle(Vector2(cx, 16), 2.5, OUTLINE, false, 1.0)
		draw_circle(Vector2(cx, -20), 2.5, p.strap_hi)
		draw_circle(Vector2(cx, -20), 2.5, OUTLINE, false, 1.0)

	# 四角金属包角：顶角挂盖檐投影下缘、底角避斜切走 45° 弯，宝箱的「硬件感」主要靠这层
	_draw_corner_brackets(p)

	# 挂锁：锁梁弧形金属梁骑在锁体上（先画梁，腿端被锁体盖住）
	draw_arc(Vector2(0, -9), 7.0, PI, TAU, 12, OUTLINE, 4.4)
	draw_arc(Vector2(0, -9), 7.0, PI, TAU, 12, p.strap, 3.0)
	# 锁体牌：骑在盖身接缝上，下两角斜切
	var lock := PackedVector2Array([
		Vector2(-12, -10), Vector2(12, -10), Vector2(12, 10),
		Vector2(8, 14), Vector2(-8, 14), Vector2(-12, 10),
	])
	draw_colored_polygon(lock, p.lock)
	draw_polyline(PackedVector2Array([lock[0], lock[1], lock[2], lock[3], lock[4], lock[5], lock[0]]), OUTLINE, 2.0)
	draw_line(Vector2(-9, -7), Vector2(9, -7), p.lock_hi, 2.0)

	if tier == BalanceChest.TIER_JADE:
		# 朱砂嵌宝（加大一档 + 高光白芯）+ 下方小锁孔
		draw_circle(Vector2(0, -2), 4.5, p.accent)
		draw_circle(Vector2(0, -2), 4.5, OUTLINE, false, 1.5)
		draw_circle(Vector2(-1.4, -3.5), 1.4, GameStyle.FX_HDR_CORE)
		draw_rect(Rect2(-1.5, 4, 3, 7), OUTLINE)
	else:
		# 锁孔：圆 + 竖槽
		draw_circle(Vector2(0, 0), 3.2, OUTLINE)
		draw_rect(Rect2(-1.5, 1, 3, 8), OUTLINE)

	# 全匣外轮廓最后压一遍：盖与身各自勾边，接缝线不勾（内部结构线）
	draw_polyline(PackedVector2Array([
		body[0], body[1], body[2], body[3], body[4], body[5], body[0],
	]), OUTLINE, 2.5)
	draw_polyline(PackedVector2Array([
		lid[0], lid[1], lid[2], lid[3], lid[4], lid[5], lid[0],
	]), OUTLINE, 2.5)

## 匣体四角 L 形金属包角：竖腿贴侧沿，顶角横腿压缝、底角斜腿跨过斜切到底沿
func _draw_corner_brackets(p: Dictionary) -> void:
	for side: float in [-1.0, 1.0]:
		var vx: float = -HALF_W + 1.5 if side < 0.0 else HALF_W - 5.5
		# 顶包角：竖腿 + 横腿成 L
		draw_rect(Rect2(vx, BODY_TOP + 4.5, 4.0, 9.0), p.strap)
		draw_rect(Rect2(vx if side < 0.0 else vx - 5.0, BODY_TOP + 4.5, 9.0, 3.5), p.strap)
		# 底包角：竖腿 + 45° 斜腿跨斜切 + 底沿横腿
		draw_rect(Rect2(vx, BODY_BOT - CHAMFER - 10.0, 4.0, 10.0), p.strap)
		draw_line(Vector2(side * (HALF_W - 2.5), BODY_BOT - CHAMFER - 1.5),
			Vector2(side * (HALF_W - 8.5), BODY_BOT - 2.5), p.strap, 4.0)
		var hx: float = -HALF_W + CHAMFER + 1.0 if side < 0.0 else HALF_W - CHAMFER - 10.0
		draw_rect(Rect2(hx, BODY_BOT - 5.0, 9.0, 3.5), p.strap)
		# 包角铆钉
		draw_circle(Vector2(vx + 2.0, BODY_TOP + 9.0), 1.8, p.strap_hi)
		draw_circle(Vector2(vx + 2.0, BODY_BOT - CHAMFER - 5.0), 1.8, p.strap_hi)

## 压扁椭圆近似（落地影用），20 边形足够平
func _ellipse(center: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(20):
		var a := TAU * float(i) / 20.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts
