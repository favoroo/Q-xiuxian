class_name ProceduralLootRenderer
extends Node2D

## 掉落物程序化矢量渲染器（空洞冷冽国风）
## 涵盖八面菱形金币水晶（普通/金色）与生机回春灵玉；藏宝匣 2026-10-10 起改走
## assets/art/prop_chest.png 生图精灵（见 SpiritChest），不再程序化绘制。
## 2026-10-10 第 6 波卡顿优化：重绘 20Hz 节流 + instance_id 错相摊帧 + 屏外剔除
## （照 HollowKnightEnemyRenderer 现成模式）；宝石上下浮动由 _process 手写 sin 驱动
## （self_bob 默认关，只有 AstralGem 开——灵玉的 position 由外部 tween 接管，不能抢写）。

enum LootType {
	GEM_BLUE,     ## 普通八面菱形幽蓝水晶
	GEM_GOLD,     ## 特殊八面菱形耀金水晶
	HEAL_ORB,     ## 碧翠灵心玉 / 生机回春魄
	GEM_SHARD     ## 碎晶：最低面额的小水晶（淡青白、体型更小；见 BalanceEconomy 碎晶段）
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

## 宝石自浮动开关：只有 AstralGem 打开；灵玉的 position 由宿主 tween 接管
@export var self_bob: bool = false

var _time: float = 0.0
var _draw_phase: float = 0.0    ## 错相余量：到相才重绘，避免同帧百颗一齐翻 _draw
var _offscreen: bool = false
var _dirty: bool = false
## 屏外剔除变换缓存：全屏掉落物共享同一个 canvas_transform + visible_rect，
## 每帧只查一次引擎接口，避免百颗宝石每渲染帧 3 次冗余调用。
static var _cull_frame: int = -1
static var _cull_transform: Transform2D
static var _cull_limit: Vector2
static var _cull_valid: bool = false

func _ready() -> void:
	# 错开每颗晶石的时间相位，避免全场完全同频机械闪烁
	_time = randf() * 10.0
	_draw_phase = fposmod(float(get_instance_id() % 97) * 0.001, REDRAW_INTERVAL)

func _process(delta: float) -> void:
	_time += delta
	if self_bob:
		position.y = sin(_time * BOB_SPEED) * BOB_AMP
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
			_draw_rhombus_crystal(false, true)
		LootType.HEAL_ORB:
			_draw_heal_orb()

# ==============================================================================
# 1. 八面立体菱形水晶（Octahedral Crystal）
# ==============================================================================
func _draw_rhombus_crystal(is_gold: bool, is_shard: bool = false) -> void:
	# 碎晶：最低面额档，体型 0.62×、辉光/耀斑减半——判定不变只缩视觉（碰撞形状在场景里）
	var w: float = 12.0 * (0.62 if is_shard else 1.0)
	var h: float = 20.0 * (0.62 if is_shard else 1.0)
	var half_w: float = w * 0.5
	var half_h: float = h * 0.5
	var center_y: float = 1.0 * (0.62 if is_shard else 1.0)  # 晶心微凸顶点

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
		draw_circle(core, 1.4 * (0.62 if is_shard else 1.0), flare_col)

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
