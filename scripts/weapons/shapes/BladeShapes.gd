extends RefCounted

## 刃器族矢量画法：剑 SWORD / 弯刀 SABER / 匕首（飞刀）DAGGER
##
## 宿主 ProceduralWeaponRenderer._draw() 经 WeaponShapeLibrary 分发到此。
## 坐标契约与宿主一致：画布像素空间沿 +X 绘制，器尖精确落在 (r.tip_len, 0)；
## 屏上实机尺度约 26px（节点 scale 0.55），细节必须在该尺度可读。
## 可用宿主能力：r._palette() / r._fill_outlined() / r._draw_star_fx()、
## r.tip_len / r.star / r.element / r.upright、AdaptiveDraw.circle(r, ...)。
##
## 本族覆盖（10 把）：
##   SWORD×7：青云长剑 / 庚金飞剑（金）、青藤剑 / 桃木剑（木）、寒霜剑（水）、
##            崩山剑（土·厚重宽刃崩口重剑）、流火飞剑（火）
##   SABER×2：烈焰刀 / 血饮狂刀（火，长刀更凶：血槽+锯齿）
##   DAGGER×1：柳叶飞刀（金 ⇒ 画成分开的两把柳叶飞镖，主刀尖顶 (tip_len,0)
##             对齐出膛点，副刀后下错开，各自带横档/短柄/尾环青穗）
##
## 比例红线（治「剑像尺子」）：直剑刃宽 ≈ tip_len 的 13.5%，收锋点推到 86.5%，
## 剑格总宽 ≤ 刃宽 2.1 倍；弯刀刀背内凹、刀腹外鼓拉大对比，治「像胡萝卜」。
##
## 返回 true = 本模块接管该器形；false = 回退宿主旧画法。

## 直剑刃半宽 / tip_len —— 全宽 = 2× ≈ 15%（红线 12~16%；旧画法 w=0.20 即全宽 40%，
## 被用户判为「宽钝像尺子」）。半宽 7.5% + 86.5% 收锋 ⇒ 剑尖夹角约 58°，细长锐利。
const SWORD_W_RATIO := 0.075
## 崩山重剑半宽比：厚重宽刃是它的特征，全宽放到 ~21%
const SWORD_W_RATIO_HEAVY := 0.105
## 直剑收锋起点（刃长比例）：85~88% 才收锋，剑尖段细长
const SWORD_SHOULDER := 0.865
## 剑格半高 / 刃半宽：总高 = 1.6× 刃宽，红线是不超过 2.2 倍且要「秀气」
const GUARD_HALF := 1.6
## 弯刀半宽 / tip_len：dao 比剑宽一档，全厚（背凹+腹鼓）约 28%
const SABER_W_RATIO := 0.13
## 血饮狂刀 tip_len≈29.7、烈焰刀≈26.0：长度阈值区分「更凶」变体（血槽+锯齿）
const SABER_FIERCE_MIN_L := 28.0
## 飞刀半宽 / tip_len：柳叶形细长，叶全宽 ≈ 1.7×w ≈ 17%（屏上仍要认得出）
const DAGGER_W_RATIO := 0.10
## 刀穗青色（飞刀原图尾穗，固定不随五行）
const TASSEL_COLOR := Color(0.42, 0.92, 0.85)

static func draw_shape(shape: int, r: ProceduralWeaponRenderer) -> bool:
	match shape:
		ProceduralWeaponRenderer.WeaponShape.SWORD:
			_draw_sword(r)
			return true
		ProceduralWeaponRenderer.WeaponShape.SABER:
			_draw_saber(r)
			return true
		ProceduralWeaponRenderer.WeaponShape.DAGGER:
			_draw_dagger(r)
			return true
	return false

# ---------------- 直剑（双刃平行、86.5% 处收细锋） ----------------
static func _draw_sword(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = r._palette()
	var L: float = r.tip_len
	var star_k := 1.0 + 0.05 * float(r.star - 1)
	var heavy: bool = r.element == "earth"
	var w: float = clampf(L * (SWORD_W_RATIO_HEAVY if heavy else SWORD_W_RATIO), 1.5, 4.0) * star_k
	var sh: float = L * (0.84 if heavy else SWORD_SHOULDER)
	var edge: Color = pal["edge"]
	# 桃木剑无金属寒光：刃口流光与外晕都压素
	var wood: bool = r.element == "wood"
	var glow_a := 0.20 if wood else 0.55
	# 桃木剑（木且长刃 ≥26，青藤剑 24 不中）：暖橙棕木质剑身（提亮，深底上要读得出），不走木系绿、不留金属高光
	var taomu: bool = wood and L >= 26.0
	var body_light: Color = Color(0.82, 0.52, 0.34) if taomu else pal["light"]
	var body_dark: Color = Color(0.50, 0.28, 0.17) if taomu else pal["dark"]
	var ridge_col: Color = Color(0.96, 0.72, 0.44) if taomu else edge

	# 五行气外晕（比刃身宽一圈的淡色轮廓；尾端收在剑格后缘，不外露成短横条）
	r.draw_colored_polygon(PackedVector2Array([
		Vector2(L * 1.03, 0.0), Vector2(sh, -w * 1.5), Vector2(0.4, -w * 1.2),
		Vector2(0.4, w * 1.2), Vector2(sh, w * 1.5),
	]), Color(edge.r, edge.g, edge.b, 0.10 if wood else 0.13))

	# 金系双剑分立：飞剑（远程穿透御剑）vs 长剑（近战手持道剑）
	var is_feijian: bool = (r.weapon_id == "gengjin_feijian") or (r.element == "metal" and (r.weapon_id.is_empty() and L < 28.5))
	var is_qingyun: bool = (r.weapon_id == "qingyun_sword") or (r.element == "metal" and not is_feijian)

	# 全刃（暗底描边 + 骨白亮面）：剑格处略窄、中段平行、86.5% 起收细锋
	r._fill_outlined(PackedVector2Array([
		Vector2(L, 0.0), Vector2(sh, -w), Vector2(L * 0.2, -w * 0.96),
		Vector2(0.4, -w * 0.74), Vector2(0.4, w * 0.74), Vector2(L * 0.2, w * 0.96), Vector2(sh, w),
	]), body_light)
	# 阴面（下半压暗）→ 阴阳刃面对比
	r.draw_colored_polygon(PackedVector2Array([
		Vector2(L, 0.0), Vector2(0.4, 0.0), Vector2(0.4, w * 0.72),
		Vector2(L * 0.2, w * 0.94), Vector2(sh, w),
	]), body_dark)
	# 中脊血槽（贯穿全刃的主线，细于刃半宽否则吃掉亮面）+ 上刃口流光
	r.draw_line(Vector2(L * 0.97, 0.0), Vector2(0.8, 0.0), Color(ridge_col.r, ridge_col.g, ridge_col.b, 0.8), 0.75, true)
	r.draw_polyline(PackedVector2Array([Vector2(sh, -w * 0.96), Vector2(L * 0.985, -w * 0.1)]),
		Color(1.0, 1.0, 1.0, glow_a), 0.7, true)

	# 五行专属细节
	match r.element:
		"metal":
			if is_feijian:
				# 庚金飞剑：贯穿剑身的金色金煞脊槽（双道金煞，宽约 0.38w，暗金底 + 纯金高光）
				var rw := clampf(w * 0.38, 0.9, 1.4)
				r.draw_colored_polygon(PackedVector2Array([
					Vector2(L * 0.92, 0.0),
					Vector2(sh * 0.95, -rw),
					Vector2(0.8, -rw * 0.8),
					Vector2(0.8, rw * 0.8),
					Vector2(sh * 0.95, rw),
				]), Color(0.86, 0.68, 0.25, 0.95))
				# 脊心雪亮金芒线
				r.draw_line(Vector2(L * 0.94, 0.0), Vector2(0.8, 0.0), Color(1.0, 0.95, 0.68), 0.75, true)
			elif is_qingyun:
				# 青云长剑：中脊淡青流光细槽（青云剑气道韵）
				r.draw_line(Vector2(L * 0.96, 0.0), Vector2(0.8, 0.0), Color(0.45, 0.85, 0.80, 0.75), 0.75, true)
		"earth":
			# 崩山重剑：上刃两道崩口锯齿（暗色 V 缺口咬进刃口）
			for i in range(2):
				var nx := L * (0.5 + 0.16 * float(i))
				r.draw_colored_polygon(PackedVector2Array([
					Vector2(nx, -w * 1.02), Vector2(nx + w * 0.95, -w * 1.02),
					Vector2(nx + w * 0.48, -w * 0.3),
				]), Color(0.06, 0.07, 0.10, 0.92))
		"fire":
			# 流火飞剑：刃身下侧两道火舌纹
			for i in range(2):
				var fx := L * (0.45 + 0.18 * float(i))
				r.draw_colored_polygon(PackedVector2Array([
					Vector2(fx, w * 0.55), Vector2(fx + w * 0.7, w * 0.2),
					Vector2(fx + w * 0.35, w * 0.62),
				]), Color(edge.r, edge.g, edge.b, 0.75))
		"water":
			# 寒霜剑：尖区三道斜生霜花
			for i in range(3):
				var cx := L * (0.55 + 0.12 * float(i))
				r.draw_line(Vector2(cx, -w * 0.5), Vector2(cx + w * 0.55, w * 0.3),
					Color(1.0, 1.0, 1.0, 0.5), 0.9, true)
		"wood":
			if taomu:
				# 桃木剑：暗红木身 + 七星连珠刻痕（雷击桃木，无藤无寒光）
				for i in range(7):
					var sx := lerpf(L * 0.62, L * 0.16, float(i) / 6.0)
					var sy := sin(float(i) * 1.1) * w * 0.4
					AdaptiveDraw.circle(r, Vector2(sx, sy), 0.6, Color(0.92, 0.86, 0.66, 0.85))
			else:
				# 青藤剑：藤蔓绕刃根 + 灵光点 + 木纹短线
				var vine := PackedVector2Array()
				for i in range(7):
					var t := float(i) / 6.0
					vine.append(Vector2(lerpf(L * 0.32, 1.0, t), sin(t * PI * 2.4) * w * 0.85))
				r.draw_polyline(vine, Color(0.35, 0.75, 0.45, 0.9), 1.1, true)
				for i in range(4):
					AdaptiveDraw.circle(r, Vector2(L * (0.34 + 0.13 * float(i)), 0.0), 0.55,
						Color(1.0, 1.0, 1.0, 0.8))
				r.draw_line(Vector2(L * 0.25, w * 0.4), Vector2(L * 0.55, w * 0.5),
					Color(edge.r, edge.g, edge.b, 0.3), 0.9, true)

	var handle_len := clampf(L * 0.40, 6.5, 11.0)
	if is_feijian:
		_draw_feijian_guard_and_handle(r, pal, w, handle_len * 0.88)
	elif is_qingyun:
		_draw_qingyun_guard_and_handle(r, pal, w, handle_len)
	else:
		_draw_guard_and_handle(r, pal, w, handle_len,
			Color(0.55, 0.24, 0.18) if taomu else pal["edge"])
	r._draw_star_fx(pal, Vector2(L, 0.0), Vector2(L * 0.85, 0.0), Vector2(L * 0.15, 0.0))

## 秀气剑格（总宽 ≤2.2×刃宽）+ 柄 + 圆首 —— 直剑通用
static func _draw_guard_and_handle(r: ProceduralWeaponRenderer, pal: Dictionary, w: float,
		handle_len: float, guard_col: Color) -> void:
	var gh := w * GUARD_HALF
	r._fill_outlined(PackedVector2Array([
		Vector2(2.6, -gh), Vector2(3.2, -gh * 0.35), Vector2(3.2, gh * 0.35),
		Vector2(2.6, gh), Vector2(0.8, gh * 0.7), Vector2(0.8, -gh * 0.7),
	]), guard_col.darkened(0.25))
	r.draw_line(Vector2(0.8, 0.0), Vector2(-handle_len, 0.0), Color(0.06, 0.06, 0.08), 2.6, true)
	r.draw_line(Vector2(0.8, 0.0), Vector2(-handle_len, 0.0), pal["handle"], 1.6, true)
	AdaptiveDraw.circle(r, Vector2(-handle_len, 0.0), 1.5, Color(0.06, 0.06, 0.08))
	AdaptiveDraw.circle(r, Vector2(-handle_len, 0.0), 1.0, pal["edge"])

## 庚金飞剑：金色后掠展翼剑格 + 玄铁金箍短柄 + 菱形破空金首（利落无穗，专司御剑飞射）
static func _draw_feijian_guard_and_handle(r: ProceduralWeaponRenderer, pal: Dictionary, w: float, handle_len: float) -> void:
	var gh := w * 1.85
	# 展翼飞翅护手（两侧向后倾掠，形同破空飞羽）
	var wing := PackedVector2Array([
		Vector2(2.8, 0.0),
		Vector2(1.8, -gh * 0.45),
		Vector2(-0.8, -gh),
		Vector2(-1.9, -gh * 0.82),
		Vector2(0.5, -gh * 0.25),
		Vector2(0.5, gh * 0.25),
		Vector2(-1.9, gh * 0.82),
		Vector2(-0.8, gh),
		Vector2(1.8, gh * 0.45),
	])
	r._fill_outlined(wing, pal["edge"].darkened(0.18))
	# 护手中央金色破风菱核
	r.draw_colored_polygon(PackedVector2Array([
		Vector2(2.4, 0.0), Vector2(1.4, -1.2), Vector2(0.4, 0.0), Vector2(1.4, 1.2),
	]), Color(1.0, 0.92, 0.55))
	# 玄铁短柄 + 金箍
	r.draw_line(Vector2(0.8, 0.0), Vector2(-handle_len, 0.0), Color(0.06, 0.06, 0.08), 2.4, true)
	r.draw_line(Vector2(0.8, 0.0), Vector2(-handle_len, 0.0), pal["handle"], 1.5, true)
	r.draw_line(Vector2(-handle_len * 0.45, -0.9), Vector2(-handle_len * 0.45, 0.9), pal["edge"], 1.0, true)
	# 剑首：菱形破风首
	var tip_pos := Vector2(-handle_len, 0.0)
	var pommel := PackedVector2Array([
		tip_pos + Vector2(0.8, 0.0),
		tip_pos + Vector2(-1.0, -1.5),
		tip_pos + Vector2(-2.2, 0.0),
		tip_pos + Vector2(-1.0, 1.5),
	])
	r.draw_colored_polygon(pommel, Color(0.06, 0.06, 0.08))
	var pommel_inner := PackedVector2Array([
		tip_pos + Vector2(0.4, 0.0),
		tip_pos + Vector2(-1.0, -1.0),
		tip_pos + Vector2(-1.7, 0.0),
		tip_pos + Vector2(-1.0, 1.0),
	])
	r.draw_colored_polygon(pommel_inner, pal["edge"])

## 青云长剑：青钢云形剑格 + 嵌青云玉 + 端庄道剑柄 + 飘逸青云剑穗
static func _draw_qingyun_guard_and_handle(r: ProceduralWeaponRenderer, pal: Dictionary, w: float, handle_len: float) -> void:
	var gh := w * GUARD_HALF
	# 青钢色四方剑格（端庄古朴）
	var guard_col := Color(0.40, 0.48, 0.58)
	r._fill_outlined(PackedVector2Array([
		Vector2(2.6, -gh), Vector2(3.4, -gh * 0.35), Vector2(3.4, gh * 0.35),
		Vector2(2.6, gh), Vector2(0.8, gh * 0.7), Vector2(0.8, -gh * 0.7),
	]), guard_col.darkened(0.20))
	# 护手中央镶嵌青云碧玉（菱形宝玉 + 亮点）
	r.draw_colored_polygon(PackedVector2Array([
		Vector2(2.2, -1.6), Vector2(3.2, 0.0), Vector2(2.2, 1.6), Vector2(1.2, 0.0),
	]), Color(0.06, 0.10, 0.15))
	r.draw_colored_polygon(PackedVector2Array([
		Vector2(2.2, -1.1), Vector2(2.9, 0.0), Vector2(2.2, 1.1), Vector2(1.5, 0.0),
	]), Color(0.22, 0.90, 0.80))
	AdaptiveDraw.circle(r, Vector2(2.0, -0.4), 0.4, Color(1.0, 1.0, 1.0, 0.95))
	# 剑柄（道剑手柄）
	r.draw_line(Vector2(0.8, 0.0), Vector2(-handle_len, 0.0), Color(0.06, 0.06, 0.08), 2.6, true)
	r.draw_line(Vector2(0.8, 0.0), Vector2(-handle_len, 0.0), Color(0.22, 0.22, 0.28), 1.6, true)
	# 剑首（青钢圆首 + 挂环）
	var h_end := Vector2(-handle_len, 0.0)
	AdaptiveDraw.circle(r, h_end, 1.6, Color(0.06, 0.06, 0.08))
	AdaptiveDraw.circle(r, h_end, 1.1, guard_col)
	# 青云剑穗（双股下垂流苏，自然飘逸）
	var tas_col := Color(0.32, 0.84, 0.80, 0.90)
	r.draw_line(h_end, h_end + Vector2(-w * 0.9, w * 0.95), Color(0.06, 0.06, 0.08), 1.6, true)
	r.draw_line(h_end, h_end + Vector2(-w * 0.9, w * 0.95), tas_col, 0.9, true)
	r.draw_line(h_end, h_end + Vector2(-w * 0.45, w * 1.35), Color(0.06, 0.06, 0.08), 1.6, true)
	r.draw_line(h_end, h_end + Vector2(-w * 0.45, w * 1.35), tas_col, 0.9, true)
	# 剑穗坠珠
	AdaptiveDraw.circle(r, h_end + Vector2(-w * 0.9, w * 0.95), 0.65, Color(0.25, 0.95, 0.85))
	AdaptiveDraw.circle(r, h_end + Vector2(-w * 0.45, w * 1.35), 0.65, Color(0.25, 0.95, 0.85))

# ---------------- 弯刀（刀背内凹、刀腹外鼓，对比拉满治「胡萝卜」） ----------------
static func _draw_saber(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = r._palette()
	var L: float = r.tip_len
	var star_k := 1.0 + 0.05 * float(r.star - 1)
	var w: float = clampf(L * SABER_W_RATIO, 3.0, 5.4) * star_k
	var edge: Color = pal["edge"]
	var fierce: bool = L >= SABER_FIERCE_MIN_L
	const SEG := 10

	# 刀背（上缘）：二次贝塞尔，中段向内（轴向）凹（Pc 抬到弦内侧 ⇒ 真内凹）
	var back := PackedVector2Array()
	for i in range(SEG + 1):
		var t := float(i) / float(SEG)
		var q := Vector2(lerpf(lerpf(-1.0, L * 0.5, t), lerpf(L * 0.5, L, t), t),
			lerpf(lerpf(-w * 0.62, -w * 0.10, t), lerpf(-w * 0.10, 0.0, t), t))
		back.append(q)
	# 刀腹（下缘）：二次贝塞尔，中段大幅外鼓（与内凹刀背对比拉满）
	var belly := PackedVector2Array()
	for i in range(SEG + 1):
		var t := float(i) / float(SEG)
		var q := Vector2(lerpf(lerpf(-1.0, L * 0.58, t), lerpf(L * 0.58, L, t), t),
			lerpf(lerpf(w * 0.6, w * 1.55, t), lerpf(w * 1.55, 0.0, t), t))
		belly.append(q)

	# 外晕（只放大 y，不越过器尖）
	var halo := back.duplicate()
	for i in range(belly.size() - 1, -1, -1):
		halo.append(Vector2(belly[i].x, belly[i].y * 1.3))
	r.draw_colored_polygon(halo, Color(edge.r, edge.g, edge.b, 0.14))

	# 刀身（暗底亮面）：背 + 反序腹闭合，器尖精确落 (L,0)
	var body := back.duplicate()
	for i in range(belly.size() - 1, -1, -1):
		body.append(belly[i])
	r._fill_outlined(body, pal["light"])
	# 阴阳面：贴背窄带压暗（只占刀厚上缘，留出刀腹亮面）
	var dark := back.duplicate()
	dark.append(Vector2(L, 0.0))
	for i in range(back.size() - 1, -1, -1):
		dark.append(Vector2(back[i].x, back[i].y * 0.45))
	r.draw_colored_polygon(dark, Color(pal["dark"].r, pal["dark"].g, pal["dark"].b, 0.9))
	# 刀腹锋口流光（沿外鼓弧线）
	r.draw_polyline(belly, Color(edge.r, edge.g, edge.b, 0.95), 1.1, true)

	if fierce:
		# 血饮狂刀：近背血槽（深红沟线）+ 刀腹后段锯齿崩口
		var groove := PackedVector2Array()
		for i in range(7):
			var t := 0.18 + float(i) / 6.0 * 0.62
			groove.append(Vector2(L * t, lerpf(-w * 0.30, -w * 0.06, t)))
		r.draw_polyline(groove, Color(0.55, 0.07, 0.09, 0.95), 1.2, true)
		for i in range(2):
			var bx := belly[SEG - 3 + i]
			r.draw_colored_polygon(PackedVector2Array([
				bx + Vector2(-w * 0.5, 0.0), bx + Vector2(w * 0.5, 0.0),
				bx + Vector2(0.0, -w * 0.55),
			]), Color(0.06, 0.07, 0.10, 0.92))
	# 刀首环（近尖刀背小环）
	var ring := Vector2(L * 0.8, -w * 0.16)
	AdaptiveDraw.circle(r, ring, 1.3, Color(0.06, 0.06, 0.08))
	AdaptiveDraw.circle(r, ring, 0.7, pal["dark"])

	# 弯刀盘形护手 + 短柄
	r._fill_outlined(PackedVector2Array([
		Vector2(2.2, -w * 0.95), Vector2(3.4, -w * 0.4), Vector2(3.4, w * 0.4),
		Vector2(2.2, w * 1.05), Vector2(0.2, w * 0.8), Vector2(0.2, -w * 0.8),
	]), pal["edge"].darkened(0.3))
	var hl := clampf(L * 0.34, 6.0, 9.5)
	r.draw_line(Vector2(0.8, 0.0), Vector2(-hl, 0.0), Color(0.06, 0.06, 0.08), 2.8, true)
	r.draw_line(Vector2(0.8, 0.0), Vector2(-hl, 0.0), pal["handle"], 1.7, true)
	AdaptiveDraw.circle(r, Vector2(-hl, 0.0), 1.5, Color(0.06, 0.06, 0.08))
	AdaptiveDraw.circle(r, Vector2(-hl, 0.0), 1.0, pal["edge"])

	r._draw_star_fx(pal, Vector2(L, 0.0), Vector2(L * 0.8, -w * 0.2), Vector2(L * 0.4, w * 1.0))

# ---------------- 柳叶飞刀 ×2（分开的两把飞镖：主刀钉 tip、副刀后下错开，不共尾不扎束） ----------------
static func _draw_dagger(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = r._palette()
	var L: float = r.tip_len
	# 主刀：刀尖精确顶 (L,0)，轴线即瞄准轴；副刀：后缩 16%、下沉拉开间距，一眼是两把
	_draw_one_dart(r, pal, Vector2.ZERO, 1.0, 0.0)
	_draw_one_dart(r, pal, Vector2(-L * 0.16, L * 0.14), 0.86, 0.16)
	# 器尖 HDR 只挂主刀（出膛点）
	r._draw_star_fx(pal, Vector2(L, 0.0), Vector2(L * 0.7, 0.0), Vector2(L * 0.3, 0.0))

## 单把柳叶飞镖：细长柳叶刃 + 一字横档 + 短柄 + 尾环双股青穗（穗短而分股，别连在一起）
static func _draw_one_dart(r: ProceduralWeaponRenderer, pal: Dictionary,
		off: Vector2, k: float, darken: float) -> void:
	var L: float = r.tip_len * k
	var w: float = clampf(L * DAGGER_W_RATIO * 1.2, 2.2, 3.6)
	var edge: Color = pal["edge"]
	var tip := off + Vector2(L, 0.0)
	# 刃身：上缘直、下缘微鼓的柳叶，尖落 off+(L,0)
	r._fill_outlined(PackedVector2Array([
		tip,
		off + Vector2(L * 0.58, -w * 0.80), off + Vector2(L * 0.30, -w * 0.58),
		off + Vector2(L * 0.25, 0.0),
		off + Vector2(L * 0.30, w * 0.58), off + Vector2(L * 0.58, w * 0.95),
	]), pal["light"].darkened(darken))
	# 下缘阴面
	r.draw_colored_polygon(PackedVector2Array([
		tip, off + Vector2(L * 0.25, 0.0),
		off + Vector2(L * 0.30, w * 0.58), off + Vector2(L * 0.58, w * 0.95),
	]), pal["dark"].darkened(darken))
	# 脊线
	r.draw_line(off + Vector2(L * 0.92, 0.0), off + Vector2(L * 0.28, 0.0),
		Color(edge.r, edge.g, edge.b, 0.85), 0.9, true)
	# 一字横档（小挡手）
	var gx := off.x + L * 0.25
	r.draw_line(Vector2(gx, off.y - w * 0.85), Vector2(gx, off.y + w * 0.85),
		Color(0.06, 0.06, 0.08), 1.8, true)
	r.draw_line(Vector2(gx, off.y - w * 0.7), Vector2(gx, off.y + w * 0.7),
		edge.darkened(0.2 + darken), 1.0, true)
	# 短柄
	r.draw_line(off + Vector2(L * 0.25, 0.0), off + Vector2(L * 0.06, 0.0),
		Color(0.06, 0.06, 0.08), 2.2, true)
	r.draw_line(off + Vector2(L * 0.25, 0.0), off + Vector2(L * 0.06, 0.0),
		pal["handle"], 1.4, true)
	# 尾环 + 双股青穗（短、下垂分股，别拉成硬直箭羽）
	var ring := off + Vector2(L * 0.03, 0.0)
	AdaptiveDraw.circle(r, ring, 1.3, Color(0.06, 0.06, 0.08))
	AdaptiveDraw.circle(r, ring, 0.7, edge.darkened(darken))
	var tas := TASSEL_COLOR.darkened(darken)
	r.draw_line(ring + Vector2(-0.8, 0.0), ring + Vector2(-w * 0.75, w * 0.75), tas, 0.9, true)
	r.draw_line(ring + Vector2(-0.8, 0.0), ring + Vector2(-w * 0.35, w * 1.0), tas, 0.9, true)
