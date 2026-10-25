class_name ProceduralLootRenderer
extends Node2D

## 掉落物程序化矢量渲染器（空洞冷冽国风）
## 涵盖八面菱形金币水晶与生机回春灵玉；藏宝匣 2026-10-18 起回归程序绘制，
## 走 ChestVisual（scripts/entities/ChestVisual.gd）。
## 2026-10-10 第 6 波卡顿优化：重绘 20Hz 节流 + instance_id 错相摊帧 + 屏外剔除
## （照 HollowKnightEnemyRenderer 现成模式）；宝石上下浮动由 _process 手写 sin 驱动
## （self_bob 默认关，只有 AstralGem 开——灵玉的 position 由外部 tween 接管，不能抢写）。

enum LootType {
	GEM_BLUE,     ## 普通八面菱形幽蓝水晶
	GEM_GOLD,     ## 特殊八面菱形耀金水晶
	HEAL_ORB,     ## 碧翠灵心玉 / 生机回春魄
	GEM_SHARD     ## 碎金：基础高频掉落的暖金细屑/金砂片（面额 1 金币；见 BalanceEconomy 碎金段）
}

## 重绘节流间隔（20Hz）：闪烁类动画低于此频率肉眼无感，敌人渲染器已验证
const REDRAW_INTERVAL := 0.05
## 屏外剔除外扩边距（px）：贴屏宝石辉光多不进剔除
const CULL_MARGIN := 48.0
## 宝石浮动幅度/频率（近似原 Tween 口径：-3..3 px，单程约 0.45s）
const BOB_AMP := 3.0
const BOB_SPEED := 7.0

## 视觉全局基础缩放系数（调小掉落物体积，更小巧精致且不遮挡战场敌人）
const VISUAL_SCALE := 0.82

## 累计重绘次数（PerfProbe 判据用）
static var redraw_count: int = 0

@export var loot_type: LootType = LootType.GEM_BLUE:
	set(val):
		if val == loot_type:
			return
		loot_type = val
		_dirty = true

## 灵玉状态：true 时为满血待命灰相
@export var is_waiting: bool = false:
	set(val):
		if val == is_waiting:
			return
		is_waiting = val
		_dirty = true

## 宝石自浮动开关：只有 AstralGem 打开；灵玉的 position 由宿主 tween 接管
@export var self_bob: bool = false

var _time: float = 0.0
var _draw_phase: float = 0.0    ## 错相余量：到相才重绘，避免同帧百颗一齐翻 _draw
var _offscreen: bool = false
var _dirty: bool = false
var _last_bob_offset: float = 0.0  ## 当前帧自浮动偏移差量（支持外部任意基准坐标）
## 屏外剔除变换缓存：全屏掉落物共享同一个 canvas_transform + visible_rect，
## 每帧只查一次引擎接口，避免百颗宝石每渲染帧 3 次冗余调用。
static var _cull_frame: int = -1
static var _cull_transform: Transform2D
static var _cull_limit: Vector2
static var _cull_valid: bool = false

func _ready() -> void:
	# 错开每颗晶石的时间相位，避免全场完全同频机械闪烁（按 instance_id 确定错相，零全局 randf 依赖）
	_time = float(get_instance_id() % 360) * 0.1
	_draw_phase = fposmod(float(get_instance_id() % 97) * 0.001, REDRAW_INTERVAL)

func _process(delta: float) -> void:
	# 池化宿主回收只隐藏自身，子节点 _process 不会连带停（set_process 不递归、visible 不拦 _process）；
	# is_visible_in_tree() 连祖先一起判定，宿主隐藏时在此整体短路兜底（宿主侧 recycle 另有 set_process 开关）
	if not is_visible_in_tree():
		return
	_time += delta
	if self_bob:
		var cur_bob := sin(_time * BOB_SPEED) * BOB_AMP
		position.y += (cur_bob - _last_bob_offset)
		_last_bob_offset = cur_bob
	elif _last_bob_offset != 0.0:
		position.y -= _last_bob_offset
		_last_bob_offset = 0.0
	var frame := Engine.get_frames_drawn()
	if frame != _cull_frame:
		_cull_frame = frame
		var vp := get_viewport()
		_cull_valid = vp != null
		if _cull_valid:
			_cull_transform = vp.get_canvas_transform()
			_cull_limit = vp.get_visible_rect().size + Vector2.ONE * CULL_MARGIN
	if _cull_valid:
		var sp: Vector2 = _cull_transform * global_position
		_offscreen = sp.x < -CULL_MARGIN or sp.y < -CULL_MARGIN or sp.x > _cull_limit.x or sp.y > _cull_limit.y
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
		LootType.GEM_SHARD:
			_draw_gold_shard()
		LootType.HEAL_ORB:
			_draw_heal_orb()

# ==============================================================================
# 0. 地面柔光接触阴影（全场统一 2026-10-18 规范：外弥散 + 内暗核）
# ==============================================================================
func _draw_ground_shadow(ground_y: float, rx: float, ry: float, base_alpha: float = 0.46) -> void:
	# 阴影始终贴地：抵消当前帧自浮动偏移（_last_bob_offset 摆动量），保证地面阴影在世界中恒定贴地
	var shadow_center_y := ground_y - _last_bob_offset
	# 当浮在最高处（_last_bob_offset < 0），物体离地远，影子略微收窄且变淡；靠近地面时影子更实更深
	var bob_factor := clampf(1.0 - (_last_bob_offset / (BOB_AMP * 1.5)) * 0.18, 0.78, 1.22)
	var eff_rx := rx * bob_factor
	var eff_ry := ry * bob_factor
	var eff_alpha := base_alpha * bob_factor
	var center := Vector2(0.0, shadow_center_y)

	# 双层软影：外层柔和弥散，内层接触暗核（全场 2026-10 统一高拟真接触投影）
	for layer in range(2):
		var k := 1.0 if layer == 0 else 0.58
		var a := eff_alpha * 0.52 if layer == 0 else minf(eff_alpha * 1.55, 0.90)
		var pts := PackedVector2Array()
		pts.resize(16)
		for i in range(16):
			var ang := TAU * float(i) / 16.0
			pts[i] = center + Vector2(cos(ang) * eff_rx * k, sin(ang) * eff_ry * k)
		var depth := 1.0 if layer == 0 else 0.25
		draw_colored_polygon(pts, Color(0.02 * depth, 0.03 * depth, 0.05 * depth, a))

# ==============================================================================
# 1. 八面立体菱形水晶（Octahedral Crystal）
# ==============================================================================
func _draw_rhombus_crystal(is_gold: bool, is_shard: bool = false) -> void:
	# 整体应用 VISUAL_SCALE 视觉缩放，碎晶再乘 0.62——判定不变只缩视觉
	var w: float = 12.0 * VISUAL_SCALE * (0.62 if is_shard else 1.0)
	var h: float = 20.0 * VISUAL_SCALE * (0.62 if is_shard else 1.0)
	var half_w: float = w * 0.5
	var half_h: float = h * 0.5
	var center_y: float = 0.8 * VISUAL_SCALE * (0.62 if is_shard else 1.0)  # 晶心微凸顶点

	# 先铺地面阴影（贴地高度在晶石下端尖角下方微距）
	var shadow_y := half_h + 2.5 * VISUAL_SCALE
	var shadow_rx := half_w * 1.15
	var shadow_ry := half_w * 0.42
	var shadow_alpha := 0.18 if is_shard else (0.42 if is_gold else 0.36)
	_draw_ground_shadow(shadow_y, shadow_rx, shadow_ry, shadow_alpha)

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
	elif is_shard:
		# 更淡的青白色：与普通蓝水晶同色系但低饱和、低明度差，读得出"更小更便宜"
		col_glow = Color(0.55, 0.95, 0.88, 0.12)
		col_hi = Color(0.92, 1.0, 0.98, 0.9)
		col_mid = Color(0.55, 0.88, 0.82, 0.85)
		col_dark = Color(0.16, 0.38, 0.36, 0.85)
		col_edge = Color(0.75, 0.96, 0.92, 0.75)
	else:
		col_glow = Color(0.25, 0.80, 1.0, 0.22)
		col_hi = Color(0.85, 0.96, 1.0, 0.98)
		col_mid = Color(0.25, 0.68, 0.95, 0.95)
		col_dark = Color(0.08, 0.22, 0.44, 0.95)
		col_edge = Color(0.60, 0.90, 1.0, 0.9)

	# 柔光外晕与 4s 周期微光呼吸（T-1.5）
	var breathe: float = sin(_time * (TAU / 4.0)) * 0.18 + 0.82
	col_glow.a *= breathe
	var pulse: float = sin(_time * 3.5) * 0.08 + 1.0
	var glow_poly := PackedVector2Array([
		Vector2(0, -half_h * 1.32 * pulse),
		Vector2(half_w * 1.32 * pulse, center_y),
		Vector2(0, half_h * 1.32 * pulse),
		Vector2(-half_w * 1.32 * pulse, center_y)
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

	# 精致细节：上右强光面内部微晶折射光斑
	if not is_shard:
		var facet_inner := PackedVector2Array([
			top * 0.65 + core * 0.35,
			right * 0.60 + core * 0.40,
			core
		])
		draw_colored_polygon(facet_inner, Color(col_hi.r, col_hi.g, col_hi.b, 0.45))

	# 中脊高光棱线与外轮廓（1.0 精致细线）
	draw_line(top, bottom, col_hi, 1.0, true)
	draw_line(left, right, col_edge.darkened(0.1), 0.9, true)
	
	var outline := PackedVector2Array([top, right, bottom, left, top])
	draw_polyline(outline, col_edge, 1.0, true)

	# 晶核锐利耀斑闪光
	var flare_alpha: float = (sin(_time * 4.0) * 0.5 + 0.5) * 0.85
	if flare_alpha > 0.4:
		var flare_col := Color(1.0, 1.0, 1.0, (flare_alpha - 0.4) * 1.6)
		draw_circle(core, 1.2 * VISUAL_SCALE * (0.62 if is_shard else 1.0), flare_col)

# ==============================================================================
# 1b. 碎金片 / 碎金屑（Gold Shard Nugget）
# ==============================================================================
func _draw_gold_shard() -> void:
	# 不规则金属碎块：打破菱形对称，按 instance_id 确定 3 种自然金砂/金片切面造型
	var var_idx: int = get_instance_id() % 3

	var p_top: Vector2
	var p_right: Vector2
	var p_bottom: Vector2
	var p_left: Vector2
	var p_mid: Vector2

	match var_idx:
		0:
			# 造型 1：斜切多棱金片
			p_top = Vector2(0.5, -6.5) * VISUAL_SCALE
			p_right = Vector2(4.5, -0.5) * VISUAL_SCALE
			p_bottom = Vector2(-0.5, 6.0) * VISUAL_SCALE
			p_left = Vector2(-4.5, 1.5) * VISUAL_SCALE
			p_mid = Vector2(0.0, 0.2) * VISUAL_SCALE
		1:
			# 造型 2：微扁平金屑
			p_top = Vector2(-1.0, -5.5) * VISUAL_SCALE
			p_right = Vector2(5.5, 0.5) * VISUAL_SCALE
			p_bottom = Vector2(1.0, 5.5) * VISUAL_SCALE
			p_left = Vector2(-5.0, -0.5) * VISUAL_SCALE
			p_mid = Vector2(-0.5, -0.5) * VISUAL_SCALE
		_:
			# 造型 3：角锥碎金粒
			p_top = Vector2(1.5, -6.0) * VISUAL_SCALE
			p_right = Vector2(4.8, 1.5) * VISUAL_SCALE
			p_bottom = Vector2(-1.5, 5.8) * VISUAL_SCALE
			p_left = Vector2(-4.2, -1.5) * VISUAL_SCALE
			p_mid = Vector2(0.5, -0.2) * VISUAL_SCALE

	# 地面微小接触暗影
	var shadow_y := 6.5 * VISUAL_SCALE
	_draw_ground_shadow(shadow_y, 4.8 * VISUAL_SCALE, 1.9 * VISUAL_SCALE, 0.32)

	# 暖金金属色系（明快黄铜金，不同于精英的刺眼大金石，呈现细碎精炼金砂质感）
	var col_glow := Color(0.95, 0.75, 0.22, 0.14)
	var col_hi := Color(1.0, 0.95, 0.65, 0.96)
	var col_mid := Color(0.92, 0.70, 0.18, 0.95)
	var col_dark := Color(0.44, 0.26, 0.06, 0.95)
	var col_edge := Color(0.98, 0.86, 0.42, 0.85)

	# 顺时针凸四边形外晕（严格无自交）
	var pulse: float = sin(_time * 3.5) * 0.08 + 1.0
	var glow_poly := PackedVector2Array([
		p_top * 1.30 * pulse,
		p_right * 1.30 * pulse,
		p_bottom * 1.30 * pulse,
		p_left * 1.30 * pulse
	])
	draw_colored_polygon(glow_poly, col_glow)

	# 4 个三角切面（全三角形，无退化与剖分崩溃风险）
	var face_bright := PackedVector2Array([p_top, p_right, p_mid])
	draw_colored_polygon(face_bright, col_hi)

	var face_mid := PackedVector2Array([p_top, p_mid, p_left])
	draw_colored_polygon(face_mid, col_mid)

	var face_dark := PackedVector2Array([p_left, p_mid, p_bottom])
	draw_colored_polygon(face_dark, col_dark)

	var face_notch := PackedVector2Array([p_mid, p_right, p_bottom])
	draw_colored_polygon(face_notch, col_mid.darkened(0.20))

	# 内部金属棱线与高光外轮廓（精致 0.9 细线）
	draw_line(p_top, p_bottom, col_hi, 0.9, true)
	draw_line(p_left, p_right, col_edge.darkened(0.15), 0.8, true)
	# 细节：金属折角反光短纹
	draw_line(p_mid, (p_top + p_right) * 0.5, col_hi, 0.8, true)

	var outline := PackedVector2Array([p_top, p_right, p_bottom, p_left, p_top])
	draw_polyline(outline, col_edge, 0.9, true)

	# 顶点微小金属反光星芒
	var flare_alpha: float = (sin(_time * 4.2) * 0.5 + 0.5) * 0.85
	if flare_alpha > 0.45:
		var flare_col := Color(1.0, 1.0, 0.85, (flare_alpha - 0.45) * 1.6)
		draw_circle(p_mid, 0.9 * VISUAL_SCALE, flare_col)

# ==============================================================================
# 2. 碧翠回春葫芦 / 生机灵魄（Emerald Gourd / Soul Gem）
# ==============================================================================
func _draw_heal_orb() -> void:
	var w: float = 13.5 * VISUAL_SCALE
	var h: float = 18.0 * VISUAL_SCALE
	var pulse: float = sin(_time * 3.0) * 0.1 + 0.95

	# 地面阴影：紧贴葫芦下肚底端下方微距
	var shadow_y := h * 0.5 + 2.5 * VISUAL_SCALE
	_draw_ground_shadow(shadow_y, w * 0.55, w * 0.22, 0.38 if not is_waiting else 0.20)

	var col_body: Color
	var col_body_light: Color
	var col_core: Color
	var col_rim: Color
	var col_halo: Color
	var col_tie: Color

	if is_waiting:
		# 满血待命暗哑灰相
		col_body = Color(0.28, 0.35, 0.30, 0.85)
		col_body_light = Color(0.35, 0.44, 0.38, 0.85)
		col_core = Color(0.45, 0.55, 0.48, 0.70)
		col_rim = Color(0.50, 0.60, 0.52, 0.65)
		col_halo = Color(0.2, 0.3, 0.25, 0.0)
		col_tie = Color(0.45, 0.40, 0.35, 0.75)
	else:
		# 生机透亮翡翠青玉
		col_body = Color(0.12, 0.68, 0.42, 0.95)
		col_body_light = Color(0.25, 0.88, 0.58, 0.95)
		col_core = Color(0.65, 1.25, 0.85, 0.98)
		col_rim = Color(0.85, 1.15, 0.95, 0.95)
		col_halo = Color(0.20, 0.85, 0.50, 0.22)
		col_tie = Color(0.98, 0.78, 0.25, 0.95)   # 仙家金丝系绳

	# 外围生机晕轮与 4s 周期微光呼吸（T-1.5）
	var breathe_heal: float = sin(_time * (TAU / 4.0)) * 0.2 + 0.8
	col_halo.a *= breathe_heal
	if not is_waiting:
		draw_circle(Vector2(0, 1.0 * VISUAL_SCALE), 10.0 * VISUAL_SCALE * pulse, col_halo)

	# 仙家宝葫芦精致外轮廓（双肚收腰曲线）
	# 上肚中心在 -h*0.14，下肚中心在 h*0.18，腰部在 h*0.02
	var pts := PackedVector2Array()
	var top_mouth := Vector2(0, -h * 0.48)
	pts.append(top_mouth)

	# 右半边：上肚圆弧 -> 腰部内凹 -> 下肚圆弧 -> 底部
	var r_upper_x := w * 0.34
	var r_upper_y := h * 0.22
	var c_upper := Vector2(0, -h * 0.16)

	var r_lower_x := w * 0.50
	var r_lower_y := h * 0.30
	var c_lower := Vector2(0, h * 0.18)

	var waist_y := h * 0.02
	var waist_x := w * 0.26

	var segs := 10
	# 右上肚弧度（-PI*0.4 到 PI*0.1）
	for i in range(segs + 1):
		var a := -PI * 0.45 + (PI * 0.55) * (float(i) / float(segs))
		pts.append(c_upper + Vector2(cos(a) * r_upper_x, sin(a) * r_upper_y))
	# 右收腰过渡点
	pts.append(Vector2(waist_x, waist_y))
	# 右下肚弧度（-PI*0.08 到 PI*0.5）
	for i in range(segs + 1):
		var a := -PI * 0.08 + (PI * 0.58) * (float(i) / float(segs))
		pts.append(c_lower + Vector2(cos(a) * r_lower_x, sin(a) * r_lower_y))

	# 底部中心
	var bottom := Vector2(0, c_lower.y + r_lower_y)
	pts.append(bottom)

	# 左半边对称
	for i in range(segs + 1):
		var a := PI * 0.5 + (PI * 0.58) * (float(i) / float(segs))
		pts.append(c_lower + Vector2(cos(a) * r_lower_x, sin(a) * r_lower_y))
	pts.append(Vector2(-waist_x, waist_y))
	for i in range(segs + 1):
		var a := PI * 0.90 + (PI * 0.55) * (float(i) / float(segs))
		pts.append(c_upper + Vector2(cos(a) * r_upper_x, sin(a) * r_upper_y))
	pts.append(top_mouth)

	# 绘制葫芦玉髓本体
	draw_colored_polygon(pts, col_body)

	# 精致向光面：右上侧弧形翡翠润泽高光面
	if not is_waiting:
		var hl_pts := PackedVector2Array([
			c_lower + Vector2(r_lower_x * 0.15, -r_lower_y * 0.6),
			c_lower + Vector2(r_lower_x * 0.75, 0.0),
			c_lower + Vector2(r_lower_x * 0.40, r_lower_y * 0.6),
			c_lower + Vector2(r_lower_x * 0.05, 0.0)
		])
		draw_colored_polygon(hl_pts, Color(col_body_light.r, col_body_light.g, col_body_light.b, 0.35))

	# 绘制精致外边缘线条（1.1px 细线）
	draw_polyline(pts, col_rim, 1.1, true)

	# 细节：葫芦束腰金丝系绳
	var tie_left := Vector2(-waist_x - 0.5, waist_y)
	var tie_right := Vector2(waist_x + 0.5, waist_y)
	draw_line(tie_left, tie_right, col_tie, 1.2, true)
	# 系绳小结/坠饰
	draw_circle(Vector2(waist_x * 0.2, waist_y + 1.2 * VISUAL_SCALE), 1.0 * VISUAL_SCALE, col_tie)

	# 细节：顶端葫芦口圈与塞子
	var plug_top := top_mouth + Vector2(0, -1.8 * VISUAL_SCALE)
	draw_line(top_mouth + Vector2(-1.8 * VISUAL_SCALE, 0), top_mouth + Vector2(1.8 * VISUAL_SCALE, 0), col_tie, 1.1, true)
	draw_line(top_mouth, plug_top, col_rim, 1.2, true)

	# 内部浮动的晶莹灵核（下肚内部生机核）
	var inner_center := Vector2(0, c_lower.y)
	if not is_waiting:
		var inner_pulse := sin(_time * 4.5) * 0.15 + 0.9
		draw_circle(inner_center, 3.0 * VISUAL_SCALE * inner_pulse, col_core)
		draw_circle(inner_center + Vector2(-0.8, -0.9) * VISUAL_SCALE, 0.9 * VISUAL_SCALE, Color(1.0, 1.0, 1.0, 0.92))
	else:
		draw_circle(inner_center, 2.2 * VISUAL_SCALE, col_core)
