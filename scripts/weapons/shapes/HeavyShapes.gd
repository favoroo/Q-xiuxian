extends RefCounted

## 重器族矢量画法：印 SEAL / 牌令 TABLET / 灯 LANTERN / 鼓 DRUM / 铎 BELL / 镜 MIRROR / 珠 BEAD
##
## 宿主 ProceduralWeaponRenderer._draw() 经 WeaponShapeLibrary 分发到此。
## 坐标契约与宿主一致：画布像素空间沿 +X 绘制，器尖/器顶精确落在 (r.tip_len, 0)；
## 本族全为 upright 竖置重器，宿主已整体转 -90°（世界竖直），画法一律沿 +X 不必自理朝向。
## 屏上实机尺度约 26px，结构细节必须在该尺度可读：主线宽 ≥1.0、轮廓 1.6+，每件 3~5 层结构。
## 画风：空洞冷冽国风 —— 骨白亮面 / 深色暗面 / 五行荧光棱线 / 粗暗描边 / 纯平矢量色块，
## 禁渐变禁柔光（HDR 只走 _draw_star_fx / _draw_core_fx）。
##
## 参考原图：巨印（方印身+龙钮+八卦印面）、雷牌（木牌云头+雷纹+蓝电）、金霄雷令（八角玄黑+兽首+
## 大雷符）、天灯（八角灯+莲火）、春雷鼓（正视鼓面+雷纹+鼓钉）、裂山铎（钟形+提环+铎舌）、
## 紫虹镜（八角金框+紫镜心）、玄冥雷珠（多棱宝珠+星芒雷心）。比例以真实器物为准。
##
## 返回 true = 本模块接管该器形；false = 回退宿主旧画法。

## 统一暗描边色（与宿主 _fill_outlined 同系）
const OUTLINE := Color(0.06, 0.07, 0.10, 0.90)

static func draw_shape(shape: int, r: ProceduralWeaponRenderer) -> bool:
	var pal: Dictionary = r._palette()
	var L: float = r.tip_len
	match shape:
		ProceduralWeaponRenderer.WeaponShape.SEAL:
			_seal(r, pal, L)
			return true
		ProceduralWeaponRenderer.WeaponShape.TABLET:
			_tablet(r, pal, L)
			return true
		ProceduralWeaponRenderer.WeaponShape.LANTERN:
			_lantern(r, pal, L)
			return true
		ProceduralWeaponRenderer.WeaponShape.DRUM:
			_drum(r, pal, L)
			return true
		ProceduralWeaponRenderer.WeaponShape.BELL:
			_bell(r, pal, L)
			return true
		ProceduralWeaponRenderer.WeaponShape.MIRROR:
			_mirror(r, pal, L)
			return true
		ProceduralWeaponRenderer.WeaponShape.BEAD:
			_bead(r, pal, L)
			return true
	return false

# ---------------- 通用构件 ----------------

## 椭圆/圆轮廓采样点（rx 沿 +X=竖置长轴，ry 沿垂直）
static func _ell(center: Vector2, rx: float, ry: float, seg: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in seg:
		var a := TAU * float(i) / float(seg)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts

## 暗底 + 内缩亮面的填充椭圆（小尺度下靠暗底撑出轮廓）
static func _ell_fill(r: ProceduralWeaponRenderer, center: Vector2, rx: float, ry: float, col: Color, seg: int = 26) -> void:
	r.draw_colored_polygon(_ell(center, rx, ry, seg), OUTLINE)
	r.draw_colored_polygon(_ell(center, rx * 0.90, ry * 0.90, seg), col)

## 折线雷纹 / 电蛇：自 a 到 b 的锯齿带（垂向摆幅 amp）
static func _bolt(r: ProceduralWeaponRenderer, a: Vector2, b: Vector2, amp: float, seg: int, col: Color, w: float) -> void:
	var dir := (b - a).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([a])
	for i in range(1, seg):
		var t := float(i) / float(seg)
		var off := amp * (1.0 if i % 2 == 0 else -1.0)
		pts.append(a.lerp(b, t) + perp * off)
	pts.append(b)
	r.draw_polyline(pts, col, w, true)

## 雷纹双色描边：宽荧光底 + 细近白芯（在 26px 尺度下读成一道带电的棱线）
static func _bolt_fx(r: ProceduralWeaponRenderer, a: Vector2, b: Vector2, amp: float, seg: int, edge: Color, w: float) -> void:
	_bolt(r, a, b, amp, seg, Color(edge.r, edge.g, edge.b, 0.9), w)
	_bolt(r, a, b, amp, seg, Color(0.92, 0.97, 1.0, 0.95), maxf(w - 0.9, 0.7))

# ---------------- 印：fantian_yin 巨印（土） ----------------
## 方印身（下宽上窄显厚重）+ 拱形印钮（顶端精确落 (L,0)）+ 底部印文刻痕（八卦格）
static func _seal(r: ProceduralWeaponRenderer, pal: Dictionary, L: float) -> void:
	var ink: Color = r._ink(pal)
	var edge: Color = pal["edge"]
	var star_k := 1.0 + 0.05 * float(r.star - 1)
	var hw := L * 0.66 * star_k        # 印身上半宽（方印：宽厚）
	var bw := hw * 1.10                # 印面下半宽（下宽 = 压手感）
	var top_x := L * 0.50              # 印身上沿（钮座，压低让印钮更壮）
	var bot_x := -L * 0.78             # 印面（器底）

	# 印身（暗底 + 亮面梯形）
	r._fill_outlined(PackedVector2Array([
		Vector2(top_x, -hw), Vector2(top_x, hw),
		Vector2(bot_x, bw), Vector2(bot_x, -bw),
	]), pal["light"])
	# 侧面暗面（右侧一条压暗带，撑出方台体积）
	r.draw_colored_polygon(PackedVector2Array([
		Vector2(top_x, hw * 0.30), Vector2(top_x, hw), Vector2(bot_x, bw), Vector2(bot_x, bw * 0.55),
	]), pal["dark"].darkened(0.12))
	# 印身滚边（五行荧光内框）
	r.draw_line(Vector2(top_x - L * 0.05, -hw * 0.78), Vector2(bot_x + L * 0.06, -bw * 0.80),
		Color(edge.r, edge.g, edge.b, 0.55), 1.0, true)
	r.draw_line(Vector2(top_x - L * 0.05, hw * 0.78), Vector2(bot_x + L * 0.06, bw * 0.80),
		Color(edge.r, edge.g, edge.b, 0.55), 1.0, true)

	# 拱形印钮（实心半环提手，外缘 apex 精确落 (L,0)）
	var R := L - top_x
	var Ri := R * 0.46
	var arch := PackedVector2Array()
	for i in range(13):
		var a := -PI * 0.5 + PI * float(i) / 12.0
		arch.append(Vector2(top_x, 0.0) + Vector2(cos(a), sin(a)) * R)
	for i in range(13):
		var a := PI * 0.5 - PI * float(i) / 12.0
		arch.append(Vector2(top_x, 0.0) + Vector2(cos(a), sin(a)) * Ri)
	r.draw_colored_polygon(arch, OUTLINE)
	var arch_in := PackedVector2Array()
	for p in arch:
		arch_in.append(Vector2(top_x, 0.0) + (p - Vector2(top_x, 0.0)) * 0.90)
	r.draw_colored_polygon(arch_in, pal["dark"])
	# 钮顶棱线（五行荧光）
	AdaptiveDraw.arc(r, Vector2(top_x, 0.0), R * 0.94, -PI * 0.5, PI * 0.5,
		Color(edge.r, edge.g, edge.b, 0.85), 1.2, true)
	# 钮座横箍
	r.draw_line(Vector2(top_x, -hw), Vector2(top_x, hw), edge.darkened(0.2), 2.0, true)

	# 底部印文刻痕（八卦格：方框 + 十字 + 四角荧光点）
	var fc := Vector2(bot_x + L * 0.22, 0.0)
	var sq := hw * 0.60
	r.draw_line(fc + Vector2(-sq, -sq), fc + Vector2(sq, -sq), ink, 1.2, true)
	r.draw_line(fc + Vector2(-sq, sq), fc + Vector2(sq, sq), ink, 1.2, true)
	r.draw_line(fc + Vector2(-sq, -sq), fc + Vector2(-sq, sq), ink, 1.2, true)
	r.draw_line(fc + Vector2(sq, -sq), fc + Vector2(sq, sq), ink, 1.2, true)
	r.draw_line(fc + Vector2(0, -sq), fc + Vector2(0, sq), ink, 1.0, true)
	r.draw_line(fc + Vector2(-sq, 0), fc + Vector2(sq, 0), ink, 1.0, true)
	for s in [-1.0, 1.0]:
		AdaptiveDraw.circle(r, fc + Vector2(s * sq * 0.5, sq * 0.5), 1.0, edge)
		AdaptiveDraw.circle(r, fc + Vector2(s * sq * 0.5, -sq * 0.5), 1.0, edge)

	r._draw_core_fx(pal, Vector2(L * 0.02, 0.0), 1.5)
	r._draw_star_fx(pal, Vector2(L, 0.0), Vector2(top_x, 0.0), Vector2(bot_x * 0.5, 0.0))

# ---------------- 牌 / 令：TABLET ----------------
## 按五行分流：金（metal）= 金霄雷令（八角玄黑 + 兽首 + 飞挑尖角 + 大雷符，更威）；
## 其余（土）= 五雷令牌（竖木牌 + 云头 + 穿绳 + 雷纹折线 + 五行滚边）。
static func _tablet(r: ProceduralWeaponRenderer, pal: Dictionary, L: float) -> void:
	if r.element == "metal":
		_tablet_ling(r, pal, L)
	else:
		_tablet_pai(r, pal, L)

## 五雷令牌（土）：圆头木牌 + 云头 + 穿绳孔 + 中轴雷纹 + 两侧回纹 + 滚边
static func _tablet_pai(r: ProceduralWeaponRenderer, pal: Dictionary, L: float) -> void:
	var ink: Color = r._ink(pal)
	var edge: Color = pal["edge"]
	var star_k := 1.0 + 0.05 * float(r.star - 1)
	var hw := L * 0.44 * star_k
	var sh := L * 0.50                 # 肩部（云头起点）
	var bot := -L * 0.86
	var body: Color = pal["light"].darkened(0.12)

	# 牌身（首端接云头、尾端方中带圆）
	r._fill_outlined(PackedVector2Array([
		Vector2(sh, -hw), Vector2(sh, hw),
		Vector2(bot + L * 0.10, hw), Vector2(bot, hw * 0.55),
		Vector2(bot, -hw * 0.55), Vector2(bot + L * 0.10, -hw),
	]), body)
	# 暗面（右侧压暗）
	r.draw_colored_polygon(PackedVector2Array([
		Vector2(sh, hw * 0.30), Vector2(sh, hw), Vector2(bot + L * 0.10, hw), Vector2(bot + L * 0.10, hw * 0.30),
	]), pal["dark"].darkened(0.10))

	# 云头（顶部半圆，apex 落 (L,0)）+ 两侧云卷
	var R := L - sh
	var head := PackedVector2Array([Vector2(sh, -R)])
	for i in range(1, 12):
		var a := -PI * 0.5 + PI * float(i) / 12.0
		head.append(Vector2(sh, 0.0) + Vector2(cos(a), sin(a)) * R)
	head.append(Vector2(sh, R))
	r.draw_colored_polygon(head, OUTLINE)
	var head_in := PackedVector2Array([Vector2(sh, -R * 0.86)])
	for i in range(1, 12):
		var a := -PI * 0.5 + PI * float(i) / 12.0
		head_in.append(Vector2(sh, 0.0) + Vector2(cos(a), sin(a)) * R * 0.86)
	head_in.append(Vector2(sh, R * 0.86))
	r.draw_colored_polygon(head_in, body)
	AdaptiveDraw.arc(r, Vector2(sh + R * 0.55, -R * 0.62), R * 0.30, -PI * 0.2, PI * 0.9, edge.darkened(0.1), 1.4, true)
	AdaptiveDraw.arc(r, Vector2(sh + R * 0.55, R * 0.62), R * 0.30, -PI * 0.9, PI * 0.2, edge.darkened(0.1), 1.4, true)

	# 穿绳孔（云头中一点）
	AdaptiveDraw.circle(r, Vector2(sh + R * 0.42, 0.0), 1.7, OUTLINE)
	AdaptiveDraw.circle(r, Vector2(sh + R * 0.42, 0.0), 0.9, edge)

	# 五行滚边（沿牌面内框）
	r.draw_line(Vector2(sh - L * 0.02, -hw * 0.74), Vector2(bot + L * 0.14, -hw * 0.74),
		Color(edge.r, edge.g, edge.b, 0.7), 1.1, true)
	r.draw_line(Vector2(sh - L * 0.02, hw * 0.74), Vector2(bot + L * 0.14, hw * 0.74),
		Color(edge.r, edge.g, edge.b, 0.7), 1.1, true)

	# 中轴雷纹折线 + 两侧回纹短横
	_bolt_fx(r, Vector2(sh - L * 0.04, 0.0), Vector2(bot + L * 0.22, 0.0), hw * 0.30, 7, edge, 1.8)
	for s in [-1.0, 1.0]:
		r.draw_line(Vector2(L * 0.10, s * hw * 0.44), Vector2(-L * 0.30, s * hw * 0.44), ink, 1.0, true)
		r.draw_line(Vector2(-L * 0.30, s * hw * 0.44), Vector2(-L * 0.30, s * hw * 0.20), ink, 1.0, true)

	r._draw_core_fx(pal, Vector2(-L * 0.30, 0.0), 1.4)
	r._draw_star_fx(pal, Vector2(L, 0.0), Vector2(sh, 0.0), Vector2(bot * 0.5, 0.0))

## 金霄雷令（金）：八角玄黑令体 + 顶部令尖/兽首 + 两侧飞挑尖角 + 双层金框 + 大雷符
static func _tablet_ling(r: ProceduralWeaponRenderer, pal: Dictionary, L: float) -> void:
	var edge: Color = pal["edge"]
	var star_k := 1.0 + 0.05 * float(r.star - 1)
	var Ro := L * 0.74 * star_k
	var cx := Vector2(-L * 0.06, 0.0)   # 八角令体中心（略偏尾，给令尖留量）

	# 八角令体（暗底 + 玄黑面）：顶点朝 +X（令尖基座）
	var oct := PackedVector2Array()
	for i in range(8):
		var a := TAU * float(i) / 8.0
		oct.append(cx + Vector2(cos(a), sin(a)) * Ro)
	r.draw_colored_polygon(oct, OUTLINE)
	var oct_in := PackedVector2Array()
	for p in oct:
		oct_in.append(cx + (p - cx) * 0.90)
	r.draw_colored_polygon(oct_in, pal["dark"].darkened(0.30))   # 玄黑令面

	# 两侧飞挑尖角（上肩外挑，令旗感）
	for s in [-1.0, 1.0]:
		var base := cx + Vector2(Ro * 0.55, s * Ro * 0.62)
		var tipw := cx + Vector2(Ro * 1.02, s * Ro * 1.02)
		var back := cx + Vector2(Ro * 0.95, s * Ro * 0.45)
		r._fill_outlined(PackedVector2Array([base, tipw, back]), edge.darkened(0.15))

	# 顶部令尖（apex 落 (L,0)）+ 兽首双眼
	var apex := Vector2(L, 0.0)
	var shx := cx.x + Ro * 0.86
	r._fill_outlined(PackedVector2Array([
		apex, Vector2(shx, -Ro * 0.34), Vector2(shx - Ro * 0.18, 0.0), Vector2(shx, Ro * 0.34),
	]), edge.darkened(0.05))
	for s in [-1.0, 1.0]:
		AdaptiveDraw.circle(r, Vector2(shx - Ro * 0.10, s * Ro * 0.16), 1.1, pal["hdr"])

	# 双层金框（外圈 + 内圈，威仪层次）
	AdaptiveDraw.arc(r, cx, Ro * 0.90, 0.0, TAU, edge, 2.0, true)
	AdaptiveDraw.arc(r, cx, Ro * 0.66, 0.0, TAU, edge.darkened(0.25), 1.2, true)

	# 大雷符（贯穿令面的粗电蛇 + 分叉）
	_bolt_fx(r, Vector2(cx.x + Ro * 0.42, -Ro * 0.30), Vector2(cx.x - Ro * 0.46, Ro * 0.34),
		Ro * 0.34, 6, edge, 2.6)
	_bolt_fx(r, Vector2(cx.x + Ro * 0.10, -Ro * 0.05), Vector2(cx.x + Ro * 0.52, -Ro * 0.42),
		Ro * 0.16, 3, edge, 1.4)

	r._draw_core_fx(pal, cx, 1.6)
	r._draw_star_fx(pal, apex, Vector2(shx, 0.0), cx)

# ---------------- 灯：fentian_baodeng 天灯（火） ----------------
## 圆腹灯笼 + 上下箍 + 纵骨架线 + 顶部提手（落 (L,0)）+ 底部流苏 + 腹内火光
static func _lantern(r: ProceduralWeaponRenderer, pal: Dictionary, L: float) -> void:
	var ink: Color = r._ink(pal)
	var edge: Color = pal["edge"]
	var star_k := 1.0 + 0.05 * float(r.star - 1)
	var Rb := L * 0.54 * star_k
	var bc := Vector2(L * 0.04, 0.0)    # 灯腹中心（略偏首，给提手留量）
	var cap_t := bc.x + Rb * 0.86       # 上箍 x
	var cap_b := bc.x - Rb * 0.86       # 下箍 x

	# 灯腹（暗底 + 暖面）
	_ell_fill(r, bc, Rb, Rb * 1.06, pal["light"], 24)

	# 纵骨架线（沿长轴三道，压暗）
	for i in range(3):
		var yo := (float(i) - 1.0) * Rb * 0.52
		r.draw_line(Vector2(cap_b, yo), Vector2(cap_t, yo), Color(ink.r, ink.g, ink.b, 0.55), 0.9, true)

	# 上下箍（横向色带 + 荧光边）
	for cx in [cap_t, cap_b]:
		var hh := Rb * 0.62
		r.draw_colored_polygon(PackedVector2Array([
			Vector2(cx - L * 0.05, -hh), Vector2(cx + L * 0.05, -hh * 0.86),
			Vector2(cx + L * 0.05, hh * 0.86), Vector2(cx - L * 0.05, hh),
		]), pal["dark"])
		r.draw_line(Vector2(cx, -hh), Vector2(cx, hh), Color(edge.r, edge.g, edge.b, 0.85), 1.1, true)

	# 顶部提手（实心半环，外缘 apex 精确落 (L,0)）+ 盖箍
	var top_x := cap_t + L * 0.04
	var R := L - top_x
	var arch := PackedVector2Array()
	for i in range(13):
		var a := -PI * 0.5 + PI * float(i) / 12.0
		arch.append(Vector2(top_x, 0.0) + Vector2(cos(a), sin(a)) * R)
	for i in range(13):
		var a := PI * 0.5 - PI * float(i) / 12.0
		arch.append(Vector2(top_x, 0.0) + Vector2(cos(a), sin(a)) * R * 0.42)
	r.draw_colored_polygon(arch, OUTLINE)
	var arch_in := PackedVector2Array()
	for p in arch:
		arch_in.append(Vector2(top_x, 0.0) + (p - Vector2(top_x, 0.0)) * 0.88)
	r.draw_colored_polygon(arch_in, pal["dark"])
	r.draw_line(Vector2(top_x, -Rb * 0.5), Vector2(top_x, Rb * 0.5), edge.darkened(0.15), 2.0, true)

	# 底部流苏（自下箍拖出三束）
	for s in [-1.0, 0.0, 1.0]:
		r.draw_line(Vector2(cap_b - L * 0.04, s * Rb * 0.22), Vector2(-L * 0.92, s * Rb * 0.30),
			Color(edge.r, edge.g, edge.b, 0.8), 1.1, true)
	AdaptiveDraw.circle(r, Vector2(-L * 0.94, 0.0), 1.3, edge)

	# 腹内火光（火舌 + 起辉）
	var flame := PackedVector2Array([
		bc + Vector2(Rb * 0.30, 0.0), bc + Vector2(-Rb * 0.05, -Rb * 0.34),
		bc + Vector2(-Rb * 0.34, 0.0), bc + Vector2(-Rb * 0.05, Rb * 0.34),
	])
	r.draw_colored_polygon(flame, pal["edge"])
	# 焰芯（向心缩小的近白小菱，纯平色块，不做渐变）
	var core_flame := PackedVector2Array()
	for p in flame:
		core_flame.append(bc + (p - bc) * 0.5)
	r.draw_colored_polygon(core_flame, Color(1.0, 0.95, 0.7, 0.95))
	r._draw_core_fx(pal, bc, 1.7)
	r._draw_star_fx(pal, Vector2(L, 0.0), Vector2(top_x, 0.0), bc)

# ---------------- 鼓：chunlei_gu 春雷鼓（木） ----------------
## 正视圆鼓面 + 顶部鼓环（落 (L,0)）+ 鼓框 + 一圈鼓钉 + 鼓面雷纹 + 中心光晕
static func _drum(r: ProceduralWeaponRenderer, pal: Dictionary, L: float) -> void:
	var ink: Color = r._ink(pal)
	var edge: Color = pal["edge"]
	var star_k := 1.0 + 0.05 * float(r.star - 1)
	var R := L * 0.74 * star_k
	var dc := Vector2(L * 0.10, 0.0)    # 鼓面中心（偏首，顶环补到 L）

	# 鼓框外圈（暗底）+ 蒙皮面
	_ell_fill(r, dc, R, R, pal["light"].darkened(0.06), 28)
	# 鼓框（皮圈与腔体分界）
	AdaptiveDraw.arc(r, dc, R * 0.86, 0.0, TAU, pal["dark"], 2.2, true)
	AdaptiveDraw.arc(r, dc, R * 0.86, 0.0, TAU, Color(edge.r, edge.g, edge.b, 0.6), 1.0, true)

	# 一圈鼓钉（压在鼓框上）
	for i in range(12):
		var a := TAU * float(i) / 12.0
		var p := dc + Vector2(cos(a), sin(a)) * R * 0.93
		AdaptiveDraw.circle(r, p, 1.1, Color(0.06, 0.06, 0.08))
		AdaptiveDraw.circle(r, p, 0.6, edge)

	# 鼓面雷纹（十字电蛇 + 内环回纹）
	_bolt_fx(r, dc + Vector2(R * 0.52, -R * 0.16), dc + Vector2(-R * 0.52, R * 0.16), R * 0.20, 6, edge, 1.6)
	_bolt_fx(r, dc + Vector2(-R * 0.16, -R * 0.52), dc + Vector2(R * 0.16, R * 0.52), R * 0.20, 6, edge, 1.6)
	AdaptiveDraw.arc(r, dc, R * 0.40, 0.0, TAU, Color(ink.r, ink.g, ink.b, 0.7), 1.0, true)

	# 顶部鼓环（系绳环，实心半环，外缘 apex 精确落 (L,0)）
	var ring_x := dc.x + R * 0.92
	var Rr := L - ring_x
	var arch := PackedVector2Array()
	for i in range(13):
		var a := -PI * 0.5 + PI * float(i) / 12.0
		arch.append(Vector2(ring_x, 0.0) + Vector2(cos(a), sin(a)) * Rr)
	for i in range(13):
		var a := PI * 0.5 - PI * float(i) / 12.0
		arch.append(Vector2(ring_x, 0.0) + Vector2(cos(a), sin(a)) * Rr * 0.40)
	r.draw_colored_polygon(arch, OUTLINE)
	var arch_in := PackedVector2Array()
	for p in arch:
		arch_in.append(Vector2(ring_x, 0.0) + (p - Vector2(ring_x, 0.0)) * 0.86)
	r.draw_colored_polygon(arch_in, edge.darkened(0.15))

	r._draw_core_fx(pal, dc, 1.8)
	r._draw_star_fx(pal, Vector2(L, 0.0), dc + Vector2(R * 0.5, 0.0), dc - Vector2(R * 0.5, 0.0))

# ---------------- 铎：lieshan_duo 裂山铎（土） ----------------
## 钟形铎身（上窄下宽）+ 顶部提环（落 (L,0)）+ 铎口微撇 + 铎舌 + 身棱线 + 回纹带
static func _bell(r: ProceduralWeaponRenderer, pal: Dictionary, L: float) -> void:
	var ink: Color = r._ink(pal)
	var edge: Color = pal["edge"]
	var star_k := 1.0 + 0.05 * float(r.star - 1)
	var tw := L * 0.24 * star_k         # 顶部半宽（窄）
	var bw := L * 0.58 * star_k         # 底部半宽（宽）
	var top_x := L * 0.50
	var bot_x := -L * 0.62
	var lip_x := -L * 0.80
	var lip_w := bw * 1.16

	# 铎身（钟形：首端窄、尾端外张，侧面微鼓）
	r._fill_outlined(PackedVector2Array([
		Vector2(top_x, -tw), Vector2(top_x, tw),
		Vector2(lerpf(top_x, bot_x, 0.5), lerp(tw, bw, 0.62)),
		Vector2(bot_x, bw), Vector2(lip_x, lip_w), Vector2(lip_x, -lip_w), Vector2(bot_x, -bw),
		Vector2(lerpf(top_x, bot_x, 0.5), -lerp(tw, bw, 0.62)),
	]), pal["light"].darkened(0.04))
	# 暗面（一侧压暗成体积）
	r.draw_colored_polygon(PackedVector2Array([
		Vector2(top_x, tw * 0.30), Vector2(top_x, tw),
		Vector2(lerpf(top_x, bot_x, 0.5), lerp(tw, bw, 0.62)),
		Vector2(bot_x, bw), Vector2(bot_x, bw * 0.45),
	]), pal["dark"].darkened(0.10))

	# 身棱线（沿长轴两道，随喇叭口外扩）
	for s in [-1.0, 1.0]:
		var ridge := PackedVector2Array([
			Vector2(top_x, s * tw * 0.5),
			Vector2(lerpf(top_x, bot_x, 0.5), s * lerp(tw, bw, 0.62) * 0.7),
			Vector2(lip_x, s * lip_w * 0.62),
		])
		r.draw_polyline(ridge, Color(ink.r, ink.g, ink.b, 0.6), 1.0, true)

	# 回纹带（近顶一道横箍 + 锯齿）
	r.draw_line(Vector2(top_x - L * 0.06, -tw * 0.9), Vector2(top_x - L * 0.06, tw * 0.9), edge.darkened(0.2), 1.8, true)
	_bolt(r, Vector2(top_x - L * 0.16, -tw * 0.7), Vector2(top_x - L * 0.16, tw * 0.7), tw * 0.28, 5,
		Color(edge.r, edge.g, edge.b, 0.8), 1.0)

	# 铎口撇沿（外翻唇口）
	r.draw_line(Vector2(lip_x, -lip_w), Vector2(lip_x, lip_w), edge.darkened(0.1), 2.2, true)
	r.draw_line(Vector2(lip_x + L * 0.05, -bw), Vector2(lip_x + L * 0.05, bw), Color(ink.r, ink.g, ink.b, 0.6), 1.0, true)

	# 顶部提环（实心半环，外缘 apex 精确落 (L,0)）
	var R := L - top_x
	var arch := PackedVector2Array()
	for i in range(13):
		var a := -PI * 0.5 + PI * float(i) / 12.0
		arch.append(Vector2(top_x, 0.0) + Vector2(cos(a), sin(a)) * R)
	for i in range(13):
		var a := PI * 0.5 - PI * float(i) / 12.0
		arch.append(Vector2(top_x, 0.0) + Vector2(cos(a), sin(a)) * R * 0.42)
	r.draw_colored_polygon(arch, OUTLINE)
	var arch_in := PackedVector2Array()
	for p in arch:
		arch_in.append(Vector2(top_x, 0.0) + (p - Vector2(top_x, 0.0)) * 0.88)
	r.draw_colored_polygon(arch_in, edge.darkened(0.10))

	# 铎舌（自内悬向铎口，末端丸）
	r.draw_line(Vector2(top_x * 0.3, 0.0), Vector2(lip_x * 0.80, 0.0), ink, 1.4, true)
	AdaptiveDraw.circle(r, Vector2(lip_x * 0.82, 0.0), 1.6, edge)

	r._draw_core_fx(pal, Vector2(-L * 0.05, 0.0), 1.5)
	r._draw_star_fx(pal, Vector2(L, 0.0), Vector2(top_x, 0.0), Vector2(lip_x * 0.5, 0.0))

# ---------------- 镜：zihong_jing 紫虹镜（金，BEAM，镜口=器尖） ----------------
## 圆镜（镜面顶 (L,0) 即光束器口）+ 金边框 + 内框 + 镜面高光弧 + 中心镜灵 + 尾端镜柄
static func _mirror(r: ProceduralWeaponRenderer, pal: Dictionary, L: float) -> void:
	var edge: Color = pal["edge"]
	var star_k := 1.0 + 0.05 * float(r.star - 1)
	var R := L * 0.60 * star_k
	var cx := L - R                     # 镜心偏首，使镜顶精确落 (L,0)
	var c := Vector2(cx, 0.0)

	# 镜背（暗底 + 骨白镜面）
	_ell_fill(r, c, R, R, pal["light"], 28)
	# 镜心紫虹（紫虹镜的镜面固有冷紫，独立于五行金属配色，只做纯平色块不渐变）
	var amethyst := Color(0.62, 0.48, 0.80)
	AdaptiveDraw.circle(r, c, R * 0.76, amethyst.darkened(0.18))
	AdaptiveDraw.circle(r, c, R * 0.60, amethyst.lightened(0.12))

	# 金边框 + 内框（双层）
	AdaptiveDraw.arc(r, c, R * 0.94, 0.0, TAU, edge, 2.2, true)
	AdaptiveDraw.arc(r, c, R * 0.74, 0.0, TAU, edge.darkened(0.28), 1.1, true)

	# 镜面高光弧（左上斜带）
	AdaptiveDraw.arc(r, c, R * 0.52, PI * 0.15, PI * 0.85, Color(1.0, 1.0, 1.0, 0.5), 1.6, true)
	AdaptiveDraw.arc(r, c, R * 0.66, -PI * 0.35, -PI * 0.05, Color(1.0, 1.0, 1.0, 0.3), 1.0, true)

	# 镜柄（自镜底向尾端 + 柄首）
	var hx0 := c.x - R * 0.82
	var hx1 := -L * 0.96
	r.draw_line(Vector2(hx0, 0.0), Vector2(hx1, 0.0), Color(0.06, 0.06, 0.08), 3.4, true)
	r.draw_line(Vector2(hx0, 0.0), Vector2(hx1, 0.0), pal["handle"].lerp(pal["light"], 0.40), 2.0, true)
	r.draw_line(Vector2(hx0, -0.5), Vector2(hx1, -0.5), Color(pal["light"].r, pal["light"].g, pal["light"].b, 0.5), 0.7, true)
	# 柄箍
	r.draw_line(Vector2(hx0 + L * 0.06, -2.2), Vector2(hx0 + L * 0.06, 2.2), edge.darkened(0.1), 1.6, true)
	AdaptiveDraw.circle(r, Vector2(hx1, 0.0), 1.8, Color(0.06, 0.06, 0.08))
	AdaptiveDraw.circle(r, Vector2(hx1, 0.0), 1.0, edge)

	# 中心镜灵光点
	r._draw_core_fx(pal, c, 1.7)
	r._draw_star_fx(pal, Vector2(L, 0.0), c + Vector2(R * 0.5, 0.0), c - Vector2(R * 0.5, 0.0))

# ---------------- 珠：xuanming_leizhu 玄冥雷珠（水/雷） ----------------
## 多棱宝珠（十二面棱、明暗分割）+ 棱线荧光 + 内核星芒雷光 + 顶珠落 (L,0)
static func _bead(r: ProceduralWeaponRenderer, pal: Dictionary, L: float) -> void:
	var edge: Color = pal["edge"]
	var star_k := 1.0 + 0.05 * float(r.star - 1)
	var R := L * 0.86 * star_k
	var c := Vector2(L - R, 0.0)        # 珠心偏首，使珠顶精确落 (L,0)
	var N := 12

	# 外圈暗底
	r.draw_colored_polygon(_ell(c, R, R, N), OUTLINE)
	# 十二面棱：按朝向分亮暗（顶/左上受光 = 亮，底/右 = 暗），做出多面体明暗分割
	var ring := _ell(c, R * 0.97, R * 0.97, N)
	for i in range(N):
		var a0 := TAU * float(i) / float(N)
		var a1 := TAU * float(i + 1) / float(N)
		var am := (a0 + a1) * 0.5
		var face: Color
		if cos(am) > 0.15:
			face = pal["light"]
		elif cos(am) > -0.35:
			face = pal["light"].darkened(0.22)
		else:
			face = pal["dark"].darkened(0.18)
		r.draw_colored_polygon(PackedVector2Array([c, ring[i], ring[(i + 1) % N]]), face)
	# 棱线（自珠心辐射到各顶点，五行荧光）
	for i in range(N):
		r.draw_line(c, ring[i], Color(edge.r, edge.g, edge.b, 0.32), 0.7, true)
	# 轮廓荧光边
	AdaptiveDraw.arc(r, c, R * 0.97, 0.0, TAU, Color(edge.r, edge.g, edge.b, 0.55), 1.0, true)

	# 内核星芒雷光（八芒冷星）
	var spikes := PackedVector2Array()
	for i in range(8):
		var a := TAU * float(i) / 8.0
		var out := c + Vector2(cos(a), sin(a)) * R * 0.62
		var inr := c + Vector2(cos(a + PI / 8.0), sin(a + PI / 8.0)) * R * 0.20
		spikes.append(out)
		spikes.append(inr)
	r.draw_colored_polygon(spikes, Color(0.85, 0.95, 1.0, 0.92))
	# 一道电蛇裂珠（雷意）
	_bolt_fx(r, c + Vector2(R * 0.55, -R * 0.40), c + Vector2(-R * 0.50, R * 0.55), R * 0.20, 6, edge, 1.5)

	r._draw_core_fx(pal, c, 1.9)
	r._draw_star_fx(pal, Vector2(L, 0.0), c + Vector2(R * 0.5, 0.0), c - Vector2(R * 0.5, 0.0))
