class_name ProceduralLootRenderer
extends Node2D

## 掉落物程序化矢量渲染器（空洞冷冽国风）
## 涵盖八面菱形灵石水晶（普通/金色）、生机回春灵玉、九幽玄铁灵匣
## 2026-10-10 第 6 波卡顿优化：重绘 20Hz 节流 + instance_id 错相摊帧 + 屏外剔除
## （照 HollowKnightEnemyRenderer 现成模式）；宝石上下浮动由 _process 手写 sin 驱动
## （self_bob 默认关，只有 AstralGem 开——灵玉/灵匣的 position 由外部 tween 接管，不能抢写）。

enum LootType {
	GEM_BLUE,     ## 普通八面菱形幽蓝水晶
	GEM_GOLD,     ## 特殊八面菱形耀金水晶
	HEAL_ORB,     ## 碧翠灵心玉 / 生机回春魄
	CHEST         ## 九幽玄铁八角灵匣
}

## 重绘节流间隔（20Hz）：闪烁类动画低于此频率肉眼无感，敌人渲染器已验证
const REDRAW_INTERVAL := 0.05
## 屏外剔除外扩边距（px）：贴屏宝石辉光多不进剔除
const CULL_MARGIN := 48.0
## 宝石浮动幅度/频率（近似原 Tween 口径：-3..3 px，单程约 0.45s）
const BOB_AMP := 3.0
const BOB_SPEED := 7.0

## 累计重绘次数（PerfProbe 判据用）
static var redraw_count: int = 0

@export var loot_type: LootType = LootType.GEM_BLUE:
	set(val):
		loot_type = val
		_dirty = true

## 灵玉状态：true 时为满血待命灰相
@export var is_waiting: bool = false:
	set(val):
		is_waiting = val
		_dirty = true

## 灵匣状态参数
@export var chest_total_hits: int = 3
@export var chest_left_hits: int = 3:
	set(val):
		chest_left_hits = val
		_dirty = true

## 宝石自浮动开关：只有 AstralGem 打开；灵玉/灵匣的 position 由宿主 tween 接管
@export var self_bob: bool = false

var _time: float = 0.0
var _draw_phase: float = 0.0    ## 错相余量：到相才重绘，避免同帧百颗一齐翻 _draw
var _offscreen: bool = false
var _dirty: bool = false

func _ready() -> void:
	# 错开每颗晶石的时间相位，避免全场完全同频机械闪烁
	_time = randf() * 10.0
	_draw_phase = fposmod(float(get_instance_id() % 97) * 0.001, REDRAW_INTERVAL)

func _process(delta: float) -> void:
	_time += delta
	if self_bob:
		position.y = sin(_time * BOB_SPEED) * BOB_AMP
	var vp := get_viewport()
	if vp != null:
		var sp: Vector2 = vp.get_canvas_transform() * global_position
		var lim: Vector2 = vp.get_visible_rect().size + Vector2.ONE * CULL_MARGIN
		_offscreen = sp.x < -CULL_MARGIN or sp.y < -CULL_MARGIN or sp.x > lim.x or sp.y > lim.y
		if _offscreen:
			return   # 屏外连浮动计时都不重绘；_dirty 保留，回屏第一帧补铺状态
	_draw_phase -= delta
	if _dirty or _draw_phase <= 0.0:
		_dirty = false
		_draw_phase = REDRAW_INTERVAL
		redraw_count += 1
		queue_redraw()

func _draw() -> void:
	match loot_type:
		LootType.GEM_BLUE:
			_draw_rhombus_crystal(false)
		LootType.GEM_GOLD:
			_draw_rhombus_crystal(true)
		LootType.HEAL_ORB:
			_draw_heal_orb()
		LootType.CHEST:
			_draw_void_chest()

# ==============================================================================
# 1. 八面立体菱形水晶（Octahedral Crystal）
# ==============================================================================
func _draw_rhombus_crystal(is_gold: bool) -> void:
	var w: float = 12.0
	var h: float = 20.0
	var half_w: float = w * 0.5
	var half_h: float = h * 0.5
	var center_y: float = 1.0  # 晶心微凸顶点

	# 颜色定义
	var col_glow: Color
	var col_hi: Color
	var col_mid: Color
	var col_dark: Color
	var col_edge: Color

	if is_gold:
		col_glow = Color(1.0, 0.78, 0.20, 0.22)
		col_hi = Color(1.0, 0.98, 0.78, 0.98)
		col_mid = Color(0.98, 0.75, 0.20, 0.95)
		col_dark = Color(0.48, 0.32, 0.06, 0.95)
		col_edge = Color(1.0, 0.90, 0.50, 0.9)
	else:
		col_glow = Color(0.25, 0.80, 1.0, 0.22)
		col_hi = Color(0.85, 0.96, 1.0, 0.98)
		col_mid = Color(0.25, 0.68, 0.95, 0.95)
		col_dark = Color(0.08, 0.22, 0.44, 0.95)
		col_edge = Color(0.60, 0.90, 1.0, 0.9)

	# 柔光外晕
	var pulse: float = sin(_time * 3.5) * 0.08 + 1.0
	var glow_poly := PackedVector2Array([
		Vector2(0, -half_h * 1.35 * pulse),
		Vector2(half_w * 1.35 * pulse, center_y),
		Vector2(0, half_h * 1.35 * pulse),
		Vector2(-half_w * 1.35 * pulse, center_y)
	])
	draw_colored_polygon(glow_poly, col_glow)

	# 4 个立体切面（双锥八面体投影）
	var top := Vector2(0, -half_h)
	var bottom := Vector2(0, half_h)
	var left := Vector2(-half_w, center_y)
	var right := Vector2(half_w, center_y)
	var core := Vector2(0, center_y)

	# 上左面（次亮向光）
	var face_tl := PackedVector2Array([top, core, left])
	draw_colored_polygon(face_tl, col_mid)

	# 上右面（极亮强光切面）
	var face_tr := PackedVector2Array([top, right, core])
	draw_colored_polygon(face_tr, col_hi)

	# 下左面（深暗背阴底面）
	var face_bl := PackedVector2Array([left, core, bottom])
	draw_colored_polygon(face_bl, col_dark)

	# 下右面（折射次暗切面）
	var face_br := PackedVector2Array([core, right, bottom])
	draw_colored_polygon(face_br, col_mid.darkened(0.25))

	# 中脊高光棱线与外轮廓
	draw_line(top, bottom, col_hi, 1.2, true)
	draw_line(left, right, col_edge.darkened(0.1), 1.0, true)
	
	var outline := PackedVector2Array([top, right, bottom, left, top])
	draw_polyline(outline, col_edge, 1.2, true)

	# 顶点锐利耀斑闪光
	var flare_alpha: float = (sin(_time * 4.0) * 0.5 + 0.5) * 0.8
	if flare_alpha > 0.4:
		var flare_col := Color(1.0, 1.0, 1.0, (flare_alpha - 0.4) * 1.6)
		draw_circle(core, 1.4, flare_col)

# ==============================================================================
# 2. 碧翠灵心玉 / 生机回春魄（Emerald Soul Gem）
# ==============================================================================
func _draw_heal_orb() -> void:
	var w: float = 14.0
	var h: float = 19.0
	var pulse: float = sin(_time * 3.0) * 0.1 + 0.95

	var col_body: Color
	var col_core: Color
	var col_rim: Color
	var col_halo: Color

	if is_waiting:
		# 满血待命暗哑灰相
		col_body = Color(0.28, 0.35, 0.30, 0.85)
		col_core = Color(0.45, 0.55, 0.48, 0.70)
		col_rim = Color(0.50, 0.60, 0.52, 0.65)
		col_halo = Color(0.2, 0.3, 0.25, 0.0)
	else:
		# 生机透亮翡翠青玉
		col_body = Color(0.12, 0.68, 0.42, 0.95)
		col_core = Color(0.65, 1.25, 0.85, 0.98)
		col_rim = Color(0.85, 1.15, 0.95, 0.95)
		col_halo = Color(0.20, 0.85, 0.50, 0.22)

	# 外围生机晕轮
	if not is_waiting:
		draw_circle(Vector2(0, 2), 12.0 * pulse, col_halo)

	# 温润水滴灵玉外廓（贝塞尔平滑点集）
	var pts := PackedVector2Array()
	var segments := 24
	var top := Vector2(0, -h * 0.5)
	pts.append(top)
	for i in range(segments + 1):
		var angle := PI * 0.05 + (PI * 0.9) * (float(i) / float(segments))
		var r_x := w * 0.5
		var r_y := h * 0.38
		var center := Vector2(0, h * 0.12)
		pts.append(center + Vector2(cos(angle) * r_x, sin(angle) * r_y))
	pts.append(top)

	# 绘制玉髓本体
	draw_colored_polygon(pts, col_body)
	draw_polyline(pts, col_rim, 1.3, true)

	# 内部浮动的晶莹灵核
	var inner_center := Vector2(0, 1.5)
	if not is_waiting:
		var inner_pulse := sin(_time * 4.5) * 0.15 + 0.9
		draw_circle(inner_center, 3.8 * inner_pulse, col_core)
		draw_circle(inner_center + Vector2(-1.0, -1.2), 1.2, Color(1.0, 1.0, 1.0, 0.9))
	else:
		draw_circle(inner_center, 2.8, col_core)

# ==============================================================================
# 3. 九幽玄铁八角灵匣（Void Reliquary）
# ==============================================================================
## 外观对齐手册插图 assets/art/prop_chest.png（2026-10-10 用户口径：「游戏里的宝箱太简陋，
## 手册里那个好看」）。旧画法只有一块黑八边形 + 四枚金三角 + 一道横封条，缺了插图里
## 最认得出的三样：青玉斜切面板、四角包金护甲、压住匣面的朱砂符纸风车。
## 尺寸口径：局部 34×30（×SpiritChest.SIZE_MULT 后 51×45），最外圈仍在判定圆之内
## （局部半径 17 == 25.5px ÷ 1.5）—— 不加外溢辉光，铁律 7「画多大 == 判多大」。
## 符纸/裂纹的角度全部查定数表，不在这里 randf()：一帧一个样等于每帧抖动。
func _draw_void_chest() -> void:
	var hw := 17.0
	var hh := 15.0
	var bevel := 6.4

	var col_rim := Color(0.035, 0.035, 0.045)      # 玄铁外框（最深）
	var col_jade := Color(0.55, 0.58, 0.44)        # 青玉斜面板
	var col_well := Color(0.10, 0.08, 0.12)        # 匣心墨井
	var col_gold := Color(0.73, 0.65, 0.40)        # 四角包金
	var col_seal := Color(0.78, 0.26, 0.26)        # 朱砂符纸
	var col_ink := Color(0.05, 0.04, 0.07, 0.92)   # 墨线勾边
	var col_leak := Color(0.30, 0.80, 1.00)        # 灵光（匣内漏出，只在井沿）

	var dmg: float = 1.0 - float(chest_left_hits) / float(maxi(1, chest_total_hits))
	var pulse: float = sin(_time * 2.6) * 0.5 + 0.5

	# ── 0. 落地影：匣子钉在场地上，不飘
	draw_filled_ellipse(Vector2(0.0, hh + 2.0), hw * 0.80, 2.6, Color(0.02, 0.025, 0.04, 0.55))

	# ── 1. 玄铁外框
	var rim := _octagon(hw, hh, bevel, 0.0)
	draw_colored_polygon(rim, col_rim)

	# ── 2. 青玉斜切面板：外框与墨井之间八块梯形，按「左上受光」分档
	#    带宽对齐插图：prop_chest.png 的玉带占匣宽约 18%，缩得太窄就只剩一圈黑
	var panel := _octagon(hw, hh, bevel, 1.7)
	var well := _octagon(hw, hh, bevel, 7.4)
	# 边序 0=顶 1=右上斜 2=右 3=右下斜 4=底 5=左下斜 6=左 7=左上斜
	var shade := [1.00, 0.70, 0.58, 0.50, 0.60, 0.78, 0.92, 1.00]
	for i in range(8):
		var quad := PackedVector2Array([
			panel[i], panel[(i + 1) % 8], well[(i + 1) % 8], well[i]])
		var facet := _shade(col_jade, float(shade[i]))
		quad.append(quad[0])
		draw_colored_polygon(quad, facet)
		draw_polyline(quad, col_ink, 0.7, false)
		# 面板外沿一道亮边，读得出「斜切」而不是「平涂」
		draw_line(panel[i], panel[(i + 1) % 8], _shade(col_jade, float(shade[i]) * 1.35), 0.8)

	# ── 3. 匣心墨井与井沿漏光（漏光画在井沿内侧，不糊到匣外）
	draw_colored_polygon(well, col_well)
	draw_polyline(_closed(well), col_ink, 1.0, false)
	draw_polyline(_closed(_octagon(hw, hh, bevel, 6.6)),
		Color(col_leak.r, col_leak.g, col_leak.b, 0.10 + 0.09 * pulse + dmg * 0.26), 1.1, false)

	# ── 4. 四角包金护甲：贴斜切边、向两侧直边各延一截（叠描四层出金属厚度）
	var run := 4.4
	for k in range(4):
		var pts := _bracket_pts(hw, hh, bevel, run, k)
		draw_polyline(pts, col_ink, 3.2, false)
		draw_polyline(pts, _shade(col_gold, 0.52), 2.6, false)
		draw_polyline(pts, col_gold, 1.9, false)
		draw_polyline(pts, _shade(col_gold, 1.30), 0.8, false)

	# ── 5. 朱砂封灵符纸：六条压住面板，末端带切向偏斜成风车
	for s in range(CHEST_SEAL_ANGLES.size()):
		_draw_talisman(CHEST_SEAL_ANGLES[s], CHEST_SEAL_LEN[s], col_seal, col_ink, dmg)

	# ── 6. 匣心灵核：朱砂环托六棱玄铁钮 + 核内紫府微光
	_draw_chest_core(dmg, pulse)

	# ── 7. 受击龟裂：先压一层匣面暗沉（越裂越旧），再画亮缝 ——
	#    顺序反了会把刚崩开的裂口一起糊暗，读不出"快开了"
	if dmg > 0.01:
		draw_colored_polygon(rim, Color(0.02, 0.015, 0.03, dmg * 0.30))
		_draw_chest_cracks(dmg)

	# ── 8. 外轮廓最后压一道，保证斜切面板的接缝不吃掉匣形
	draw_polyline(_closed(rim), col_ink, 1.3, false)

## 符纸角度（弧度）与长度定数表：不对称摆位，看着像人贴的而不是转出来的
const CHEST_SEAL_ANGLES: Array[float] = [
	-1.36, -0.32, 0.74, 1.79, 2.62, 3.86]
const CHEST_SEAL_LEN: Array[float] = [13.4, 12.2, 13.8, 12.6, 13.2, 12.0]

func _draw_talisman(ang: float, length: float, col_seal: Color, col_ink: Color, dmg: float) -> void:
	var dir := Vector2(cos(ang), sin(ang))
	var perp := Vector2(-dir.y, dir.x)
	var skew := 1.7                                  # 末端切向偏移 → 风车旋向
	var inner := dir * 3.4 + perp * (skew * 0.28)
	var outer := dir * length + perp * skew
	# 外端撕口：两侧不等宽，纸角像被灵气燎过
	var pts := PackedVector2Array([
		inner + perp * 2.05,
		outer + perp * 2.25,
		outer + perp * 0.6 - dir * 0.9,
		outer - perp * 1.80,
		inner - perp * 1.95,
	])
	pts.append(pts[0])
	draw_colored_polygon(pts, col_seal.darkened(dmg * 0.22))
	draw_polyline(pts, col_seal.darkened(0.55), 0.7, false)
	# 纸面符墨：两道横划 + 一竖，压在纸的中段
	for t in [0.38, 0.62]:
		var c: Vector2 = inner.lerp(outer, t)
		draw_line(c - perp * 1.45, c + perp * 1.45, col_ink, 0.8)
	var mid: Vector2 = inner.lerp(outer, 0.5)
	draw_line(mid - dir * 2.0, mid + dir * 2.0, col_ink, 0.7)
	# 受击后纸角翘起：外端压一道暗面
	if dmg > 0.34:
		draw_line(outer - perp * 1.5, outer + perp * 1.9, col_seal.darkened(0.62), 1.0)

## 灵核：朱砂环托底 + 六棱玄铁钮（上亮下暗）+ 核心紫府光，随呼吸明暗
func _draw_chest_core(dmg: float, pulse: float) -> void:
	var col_ink := Color(0.05, 0.04, 0.07, 0.92)
	# 插图里钮座是一圈被六棱钮吃掉一半的朱砂环 —— 少了它，匣心就只剩一颗孤零零的紫点
	draw_circle(Vector2(0.0, 1.0), 6.4, Color(0.50, 0.14, 0.16))
	draw_circle(Vector2(0.0, 1.0), 6.4, Color(0.05, 0.04, 0.06, 0.5))
	var hex_hi := PackedVector2Array()
	var hex_lo := PackedVector2Array()
	for i in range(6):
		var a := deg_to_rad(-90.0 + float(i) * 60.0)
		hex_hi.append(Vector2(cos(a), sin(a)) * 4.0 + Vector2(0.0, -1.5))
		hex_lo.append(Vector2(cos(a), sin(a)) * 5.6 + Vector2(0.0, 0.9))
	draw_colored_polygon(_closed(hex_lo), Color(0.15, 0.13, 0.16))
	draw_colored_polygon(_closed(hex_hi), Color(0.32, 0.28, 0.37))
	draw_polyline(_closed(hex_lo), col_ink, 1.0, false)
	draw_polyline(_closed(hex_hi), col_ink, 0.8, false)
	# 钮面斜切：左上一格受光、右下一格背光，读得出这是个「凸出来的钮」
	draw_line(hex_hi[5], hex_hi[0], Color(0.80, 0.76, 0.88, 0.55), 0.9)
	draw_line(hex_hi[2], hex_hi[3], Color(0.06, 0.05, 0.09, 0.6), 0.9)
	# 核心：受损越重光越暗，砸到最后一格前一刻是「快开了」而不是「没东西」
	var glow := Color(0.62, 0.36, 0.86, (0.55 + 0.35 * pulse) * (1.0 - dmg * 0.45))
	draw_circle(Vector2(0.0, -1.0), 2.3, glow)
	draw_circle(Vector2(0.0, -1.0), 1.1, Color(0.92, 0.80, 1.0, 0.85 * (1.0 - dmg * 0.5)))

## 龟裂：从灵核向外炸的折线，格数越少裂得越远、越密
func _draw_chest_cracks(dmg: float) -> void:
	var crack_col := Color(1.0, 0.86, 0.52, 0.85)
	var n := clampi(int(ceilf(dmg * 5.0)), 1, 5)
	for i in range(n):
		var ang := deg_to_rad(-90.0 + float(i) * 137.0)
		var dir := Vector2(cos(ang), sin(ang))
		var reach := 5.0 + dmg * 11.0
		var pts := PackedVector2Array()
		var t := 3.0
		var side := 1.0
		while t < reach:
			var perp := Vector2(-dir.y, dir.x) * side * (1.1 + dmg * 1.3)
			pts.append(dir * t + perp)
			side = -side
			t += 2.6
		if pts.size() < 2:
			continue
		pts.insert(0, dir * 2.6)
		# 先垫一道墨槽再压亮缝，裂口才有「崩开」的厚度而不是画上去的线
		draw_polyline(pts, Color(0.03, 0.02, 0.04, 0.75), 2.3, false)
		draw_polyline(pts, crack_col, 1.0, false)
		# 主裂两侧各带一条细支裂
		if dmg > 0.5 and pts.size() > 2:
			var fork: Vector2 = pts[pts.size() - 2]
			draw_line(fork, fork + dir.rotated(0.9) * 3.4, crack_col.darkened(0.15), 0.8)

## 八角框顶点集：inset 往里缩，斜切按 0.55 系数跟缩（缩多了匣形会变成方盒）
func _octagon(hw: float, hh: float, bevel: float, inset: float) -> PackedVector2Array:
	var a: float = hw - inset
	var b: float = hh - inset
	var v: float = clampf(bevel - inset * 0.55, 1.2, minf(a, b))
	return PackedVector2Array([
		Vector2(-a + v, -b), Vector2(a - v, -b),
		Vector2(a, -b + v), Vector2(a, b - v),
		Vector2(a - v, b), Vector2(-a + v, b),
		Vector2(-a, b - v), Vector2(-a, -b + v),
	])

## 第 k 枚包角护甲的折线（k=0 右上 / 1 右下 / 2 左下 / 3 左上）：
## 沿直边一截 → 贴斜切边 → 再沿相邻直边一截
func _bracket_pts(hw: float, hh: float, bevel: float, run: float, k: int) -> PackedVector2Array:
	var inset := 1.3
	var a: float = hw - inset
	var b: float = hh - inset
	var v: float = clampf(bevel - inset * 0.55, 1.2, minf(a, b))
	var sx := 1.0 if (k == 0 or k == 1) else -1.0
	var sy := 1.0 if (k == 1 or k == 2) else -1.0
	return PackedVector2Array([
		Vector2(sx * (a - v - run), sy * b),
		Vector2(sx * (a - v), sy * b),
		Vector2(sx * a, sy * (b - v)),
		Vector2(sx * a, sy * (b - v - run)),
	])

## 首尾同点闭合成一圈（draw_polyline 自己不闭合）
func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	out.append(pts[0])
	return out

## 按倍率调明度（只动 rgb，alpha 保住）—— Color * float 会连 alpha 一起乘，不能用
func _shade(c: Color, m: float) -> Color:
	return Color(c.r * m, c.g * m, c.b * m, c.a)

func draw_filled_ellipse(center: Vector2, rx: float, ry: float, col: Color, segments: int = 20) -> void:
	var pts := PackedVector2Array()
	for i in range(segments):
		var theta := (float(i) / float(segments)) * TAU
		pts.append(center + Vector2(cos(theta) * rx, sin(theta) * ry))
	draw_colored_polygon(pts, col)
