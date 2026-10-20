extends RefCounted

## 符箓族矢量画法：符 TALISMAN
##
## 宿主 ProceduralWeaponRenderer._draw() 经 WeaponShapeLibrary 分发到此。
## 坐标契约与宿主一致：画布像素空间沿 +X 绘制，符头顶端精确落在 (r.tip_len, 0)；
## upright 符箓宿主已整体转 -90°（世界竖直），非竖置符（镇山符）长轴跟瞄准方向，
## 两种朝向共用同一画法。屏上实机尺度约 26px，符文细节必须在该尺度可读。
##
## 符箓语言（一眼是道符，不是卡片）：
##   · 长条符纸：宽 ≈ tip_len 的 33%，中段最宽、两端微收腰，尾端开鱼嘴符脚；
##   · 符头云勾：顶端朱笔 ∩ 形勾云括弧 + 一点卷云涡；
##   · 符身朱书：按五行变体的抽象篆意曲尺（木=虫曲纹 / 火=火舌三叉 / 金=回纹曲尺 /
##     水=涡旋波纹 / 土=山镇三横），朱砂红一笔成型，线宽 ≥1.2；
##   · 底部朱砂方印：符尾一枚方印压纸；
##   · 五行色细滚边沿符纸外缘勾勒；
##   · 结尾 _draw_star_fx 给符头灵芒。
##
## 返回 true = 本模块接管该器形；false = 回退宿主旧画法。

## 朱砂红：符文与印章固定丹砂色，不随五行走（道符的"朱书"是画种语言）
const CINNABAR := Color(0.78, 0.18, 0.12)
## 符纸半宽比例：tip_len 的 33%（30~36% 区间内，再宽就读成令牌了）
const PAPER_HW_RATIO := 0.33
## 笔画线宽下限（26px 实机尺度下必须可读）
const STROKE_MIN := 1.2

static func draw_shape(shape: int, r: ProceduralWeaponRenderer) -> bool:
	if shape == ProceduralWeaponRenderer.WeaponShape.TALISMAN:
		_draw_talisman(r)
		return true
	return false

## 符纸外轮廓（尾端符脚 → 上缘 → 符头顶点 → 下缘，闭合）
## 中段最宽、两端微收腰；尾端内凹开鱼嘴，符头顶点精确落在 (L, 0)。
static func _paper_outline(L: float, hw: float) -> PackedVector2Array:
	var upper := PackedVector2Array([
		Vector2(-L * 0.80, 0.0),        # 符脚鱼嘴内凹中点（收得深一点才像符脚）
		Vector2(-L * 0.95, -hw * 0.46),
		Vector2(-L * 0.88, -hw * 0.74),
		Vector2(-L * 0.45, -hw * 0.86),
		Vector2(L * 0.05, -hw),         # 中段最宽
		Vector2(L * 0.55, -hw * 0.94),
		Vector2(L * 0.86, -hw * 0.76),
		Vector2(L * 0.95, -hw * 0.40),
		Vector2(L, 0.0),                # 符头顶端（器尖契约点）
	])
	var pts := upper.duplicate()
	# 镜像下缘（跳过首尾轴上点，反向拼接）
	for i in range(upper.size() - 2, 0, -1):
		var p: Vector2 = upper[i]
		pts.append(Vector2(p.x, -p.y))
	return pts

static func _draw_talisman(r: ProceduralWeaponRenderer) -> void:
	var pal: Dictionary = r._palette()
	var L: float = r.tip_len
	var star_k := 1.0 + 0.05 * float(r.star - 1)
	var hw := clampf(L * PAPER_HW_RATIO, 5.2, 7.4) * star_k
	var paper: Color = r._paper(pal)
	var ink: Color = r._ink(pal)
	var edge: Color = pal["edge"]

	var outline := _paper_outline(L, hw)

	# 五行气外晕（纯平低透明，给符纸一点底色气场）
	var aura := PackedVector2Array()
	var pivot := Vector2(L * 0.02, 0.0)
	for p in outline:
		aura.append(pivot.lerp(p, 1.14))
	r.draw_colored_polygon(aura, Color(edge.r, edge.g, edge.b, 0.12))

	# 符纸本体：暗底描边 + 纸白面
	r._fill_outlined(outline, paper)

	# 五行细滚边：沿外缘内缩一圈勾纸边
	var trim := PackedVector2Array()
	for p in outline:
		trim.append(pivot.lerp(p, 0.88))
	trim.append(trim[0])
	r.draw_polyline(trim, Color(edge.r, edge.g, edge.b, 0.75), 0.8, true)

	# 符头云勾：∩ 形勾云括弧抱住符头顶 + 中央一点卷云涡
	var head := PackedVector2Array([
		Vector2(L * 0.58, -hw * 0.50),
		Vector2(L * 0.80, -hw * 0.40),
		Vector2(L * 0.90, -hw * 0.15),
		Vector2(L * 0.90, hw * 0.15),
		Vector2(L * 0.80, hw * 0.40),
		Vector2(L * 0.58, hw * 0.50),
	])
	r.draw_polyline(head, CINNABAR, STROKE_MIN + 0.2, true)
	# 卷云涡心一点朱砂（小半径弧在 26px 尺度会糊成六边形，实心点最稳）
	AdaptiveDraw.circle(r, Vector2(L * 0.72, 0.0), hw * 0.16, CINNABAR)

	# 符身朱书：按五行变体（雷系符的 element 已归入火/木，随其主色走纹样）
	match r.element:
		"wood":
			_glyph_worm(r, L, hw)
		"fire":
			_glyph_flame(r, L, hw)
		"metal":
			_glyph_meander(r, L, hw)
		"water":
			_glyph_spiral(r, L, hw)
		"earth":
			_glyph_mountain(r, L, hw)
		_:
			_glyph_meander(r, L, hw)

	# 底部朱砂方印：符尾压一枚方印，印心留纸白十字（小尺度读成印文）
	var sc := Vector2(-L * 0.66, 0.0)
	var sq := maxf(hw * 0.36, 1.9)
	r.draw_colored_polygon(PackedVector2Array([
		sc + Vector2(-sq, -sq), sc + Vector2(sq, -sq), sc + Vector2(sq, sq), sc + Vector2(-sq, sq),
	]), Color(0.10, 0.05, 0.05, 0.85))
	var sq2 := sq * 0.82
	r.draw_colored_polygon(PackedVector2Array([
		sc + Vector2(-sq2, -sq2), sc + Vector2(sq2, -sq2), sc + Vector2(sq2, sq2), sc + Vector2(-sq2, sq2),
	]), CINNABAR)
	r.draw_line(sc + Vector2(-sq2 * 0.6, 0.0), sc + Vector2(sq2 * 0.6, 0.0),
		Color(paper.r, paper.g, paper.b, 0.85), 0.9, true)
	r.draw_line(sc + Vector2(0.0, -sq2 * 0.6), sc + Vector2(0.0, sq2 * 0.6),
		Color(paper.r, paper.g, paper.b, 0.85), 0.9, true)

	# 符头灵芒（升星：★2 符身浮星点、★3 沿轴辉线）
	r._draw_star_fx(pal, Vector2(L, 0.0), Vector2(L * 0.5, 0.0), Vector2(-L * 0.3, 0.0))

# ---------------- 符身朱书纹样（每款 2~4 笔，一笔成型优先） ----------------

## 木/毒：虫曲纹 —— S 形虫脊 + 两对侧足曲（万木灵符/蛊毒符/惊蛰符）
static func _glyph_worm(r: ProceduralWeaponRenderer, L: float, hw: float) -> void:
	r.draw_polyline(PackedVector2Array([
		Vector2(L * 0.44, 0.0),
		Vector2(L * 0.22, -hw * 0.34),
		Vector2(-L * 0.02, 0.0),
		Vector2(-L * 0.24, hw * 0.34),
		Vector2(-L * 0.44, 0.0),
	]), CINNABAR, STROKE_MIN + 0.15, true)
	r.draw_line(Vector2(L * 0.22, -hw * 0.34), Vector2(L * 0.28, -hw * 0.66), CINNABAR, STROKE_MIN, true)
	r.draw_line(Vector2(-L * 0.24, hw * 0.34), Vector2(-L * 0.30, hw * 0.66), CINNABAR, STROKE_MIN, true)
	r.draw_line(Vector2(-L * 0.02, -hw * 0.55), Vector2(-L * 0.02, hw * 0.55), CINNABAR, STROKE_MIN, true)

## 火/雷火：火舌三叉 —— 三道朝符头的焰尖折线（火炎符/真火符/雷火符）
static func _glyph_flame(r: ProceduralWeaponRenderer, L: float, hw: float) -> void:
	for i in range(3):
		var x0 := L * (0.34 - float(i) * 0.24)
		r.draw_polyline(PackedVector2Array([
			Vector2(x0 - L * 0.09, -hw * 0.52),
			Vector2(x0, 0.0),
			Vector2(x0 - L * 0.09, hw * 0.52),
		]), CINNABAR, STROKE_MIN + 0.1, true)

## 金：回纹曲尺 —— 一道直角曲尺长笔 + 金针竖笔（金针符/庚金符）
static func _glyph_meander(r: ProceduralWeaponRenderer, L: float, hw: float) -> void:
	r.draw_polyline(PackedVector2Array([
		Vector2(L * 0.42, -hw * 0.52),
		Vector2(L * 0.42, hw * 0.16),
		Vector2(L * 0.12, hw * 0.16),
		Vector2(L * 0.12, -hw * 0.52),
		Vector2(-L * 0.18, -hw * 0.52),
		Vector2(-L * 0.18, hw * 0.30),
		Vector2(-L * 0.44, hw * 0.30),
	]), CINNABAR, STROKE_MIN + 0.1, true)
	r.draw_line(Vector2(-L * 0.44, -hw * 0.42), Vector2(-L * 0.06, -hw * 0.42), CINNABAR, STROKE_MIN, true)

## 水：涡旋波纹 —— 三枚渐小水涡沿轴排布（玄冰符/癸水符）
## 用采样螺旋折线而非 AdaptiveDraw.arc：小半径弧自适应段数只有 6 段，会画成开口六边形。
static func _glyph_spiral(r: ProceduralWeaponRenderer, L: float, hw: float) -> void:
	for i in range(3):
		var t := float(i) / 2.0
		var cx := lerpf(L * 0.30, -L * 0.30, t)
		var rad := lerpf(hw * 0.46, hw * 0.30, t)
		var y0 := lerpf(-hw * 0.28, hw * 0.28, t)
		var pts := PackedVector2Array()
		const SEG := 14
		for s in range(SEG + 1):
			var a := PI * 0.9 + PI * 1.5 * float(s) / float(SEG)
			var k := float(s) / float(SEG)
			pts.append(Vector2(cx, y0) + Vector2(cos(a), sin(a)) * rad * (1.0 - k * 0.55))
		r.draw_polyline(pts, CINNABAR, STROKE_MIN, true)

## 土：山镇三横 —— 中脊一竖 + 两侧短横压底横（镇山符/厚土符）
static func _glyph_mountain(r: ProceduralWeaponRenderer, L: float, hw: float) -> void:
	r.draw_line(Vector2(-L * 0.34, 0.0), Vector2(L * 0.38, 0.0), CINNABAR, STROKE_MIN + 0.15, true)
	r.draw_line(Vector2(-L * 0.34, -hw * 0.55), Vector2(-L * 0.34, hw * 0.55), CINNABAR, STROKE_MIN + 0.1, true)
	r.draw_line(Vector2(-L * 0.34, -hw * 0.55), Vector2(L * 0.14, -hw * 0.55), CINNABAR, STROKE_MIN, true)
	r.draw_line(Vector2(-L * 0.34, hw * 0.55), Vector2(L * 0.14, hw * 0.55), CINNABAR, STROKE_MIN, true)
