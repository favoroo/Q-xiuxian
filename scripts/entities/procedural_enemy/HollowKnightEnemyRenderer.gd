class_name HollowKnightEnemyRenderer
extends Node2D

## 敌人空洞冷冽国风程序化矢量渲染器
## 纯 GDScript CanvasItem 矢量绘制，涵盖悬浮、飞行、爬行波三大流体非复杂动作，
## 为全 14 种敌种提供高反差、骨面、虚空、灵核辉光的高辨识度妖魔拟态。

@export var config: EnemyVisualConfig:
	set(val):
		config = val
		if config != null:
			# 精英 30Hz / Boss 每帧 / 普通怪档位化节流
			_is_mob = not config.is_elite and not config.is_boss
			_is_boss = config.is_boss
		_dirty = true

# 运动驱动状态
var flip_h: bool = false:
	set(val):
		# EnemyBase 每物理帧都会同步本值，不判新旧会把 _dirty 打真、
		# 把下面 20Hz 重绘节流整个废掉（2026-10-13 掉帧根因）
		if val == flip_h:
			return
		flip_h = val
		_dirty = true

var facing: String = "s"
var is_moving: bool = false
var speed_ratio: float = 1.0
var bank_angle: float = 0.0
var advance: float = 0.0
var gait_phase: float = 0.0  ## 步态相位（弧度）：EnemyBase 按实际位移推进（悬浮 6rad/s、蠕动 9rad/s × speed_ratio），摆翼/蠕波用它与位移同相；静止时冻结，待机呼吸继续用 _time
var special_state: float = 0.0  ## 蓄力/前摇进度 0→1（丹爆引信=1 / 冲刺预警 / 火球蓄力 / 精英震地 / 投毒），0 = 无蓄力

var aim_dir: Vector2 = Vector2.ZERO:  ## 全局锁敌朝向（用于法剑/眼眸精准指向）
	set(val):
		if val == aim_dir:
			return
		aim_dir = val
		if special_state > 0.0:
			_dirty = true

var recoil: float = 0.0:              ## 武器出膛后坐力（1.0 -> 0.0 快速回弹）
	set(val):
		recoil = val
		_dirty = true

var weapon_tip_pos: Vector2 = Vector2.ZERO  ## 武器器尖局部坐标（供出膛点查询）

func trigger_recoil(_dir: Vector2 = Vector2.ZERO) -> void:
	recoil = 1.0
	_dirty = true

func get_tip_local_pos() -> Vector2:
	if weapon_tip_pos != Vector2.ZERO:
		return weapon_tip_pos
	return _calc_weapon_tip_pos()

func _calc_weapon_tip_pos() -> Vector2:
	var root_scale_x := -1.0 if flip_h else 1.0
	var casting := special_state > 0.0
	var local_aim := Vector2.RIGHT
	if aim_dir.length_squared() > 0.01:
		local_aim = Vector2(aim_dir.x * root_scale_x, aim_dir.y).normalized()

	var sword_pos := Vector2.ZERO
	var sword_rot := 0.0
	if casting or recoil > 0.001:
		sword_rot = local_aim.angle()
		var pull_back := -local_aim * (5.0 * special_state + 7.0 * recoil)
		sword_pos = Vector2(2, 4) + pull_back
	else:
		sword_pos = Vector2(2, 8)
		sword_rot = deg_to_rad(20.0)

	var t_sword := Transform2D(sword_rot, sword_pos)
	var tip_in_local := t_sword * Vector2(20.0, 0.0)
	var sf := (config.scale_factor if config != null else 1.0) * ENEMY_GLOBAL_SCALE
	return Vector2(tip_in_local.x * root_scale_x, tip_in_local.y) * sf

var _time: float = 0.0

## 视线本地缓存（_draw 首帧算一次，供全部眼型共用）：全局 aim_dir 已转成本地坐标（含镜像）。
## 为零 = 无锁敌（待机/无目标），眼型退回静态。
var _local_aim_cache: Vector2 = Vector2.ZERO

## 本次绘制的水平镜像符号（_draw 里按 flip_h 现算）：地影上报要把它并进世界偏移。
var _draw_flip_x: float = 1.0

## 残血读数（0~1，1=满血）：EnemyBase 每帧同步，供喘息/失序调制。
var hp_ratio: float = 1.0:            ## 生命比例（渲染层只读，纯表现，不参与任何判定）
	set(val):
		if absf(val - hp_ratio) < 0.005:
			return
		hp_ratio = val
		_dirty = true

## 瞳孔朝目标偏移量（眼型内复用）：偏移幅度按眼半径比例，且越近看越用力。
## 返回本地坐标下的偏移向量，调用方自己加到瞳孔位置上。
## 2026-10-23 幅度实测校准：首版取 15% 眼幅，全敌种静帧对比图里三态（正常/锁敌/残血）
## 肉眼分不出来（史莱姆眼宽 2.6px ⇒ 偏移 0.4px）。改为 50% 眼幅 + 1.5px 绝对下限，
## 小眼型也读得出「瞳孔在动」；上限夹在 60% 眼幅，避免瞳孔顶出眼白。
func _gaze_offset(eye_radius: float) -> Vector2:
	if _local_aim_cache == Vector2.ZERO:
		return Vector2.ZERO
	var focus := 0.50 + 0.22 * clampf(special_state, 0.0, 1.0)
	var amp := maxf(eye_radius * focus, 1.5)
	# 上限 = 60% 眼幅，小眼型保底 1px（保证瞳孔在动读得出来）。
	# 旧写法「maxf(eye_radius, 1.0) * 0.6 + 1.0」等于在 60% 之外又加 1px，
	# 小眼型（如金蟾 1.1px）上限变 150% 眼幅，瞳孔会顶出眼白。
	return _local_aim_cache * minf(amp, maxf(eye_radius * 0.6, 1.0))

## 出手瞪视：蓄力进度过半后瞳孔/高光提亮并微胀，作第二层预警（不替代符印与预警线）
func _gaze_glare() -> float:
	return 1.0 + 0.45 * clampf((special_state - 0.35) / 0.65, 0.0, 1.0)

## 残血喘息倍率（0=满血，1=濒死）：生命越低呼吸幅度越大、节奏越慢（喘不上气）。
## 与 _time 驱动的基础呼吸相乘即可，不改任何现有静态形变公式的量级。
func _low_hp_breath() -> float:
	if hp_ratio >= 0.999:
		return 0.0
	return clampf(1.0 - hp_ratio, 0.0, 1.0)

## 残血裂痕（2026-10-23）：生命低于 40% 后，体表浮出一道随呼吸明灭的暗色裂纹。
## 为什么要有：呼吸幅度/浮沉频率这类「动态读数」在静帧里完全看不出来，而实战中玩家
## 也很难盯着某一只怪数它的呼吸节奏。一条静帧可读的裂纹才是「这只快死了」的硬读数。
## 纯绘制、不参与判定；拥挤档（同屏怪多）自动淡出，避免满屏裂纹噪声。
func _draw_hp_cracks(center: Vector2, radius: float) -> void:
	var hurt := _low_hp_breath()
	if hurt < 0.6:
		return
	var k := clampf((hurt - 0.6) / 0.4, 0.0, 1.0)
	var pulse := 0.55 + 0.45 * sin(_time * 3.4 + _phase_seed)
	var a := k * pulse * (0.35 if FxBudget.crowded else 0.62)
	var crack_col := Color(0.10, 0.02, 0.04, a)
	# 三道短裂纹：自中心偏上向外斜裂，长度按半径走（贴体，不越轮廓）
	var segs := [
		[Vector2(-0.15, -0.42), Vector2(-0.52, -0.05)],
		[Vector2(0.10, -0.30), Vector2(0.34, 0.22)],
		[Vector2(-0.28, 0.16), Vector2(-0.05, 0.48)],
	]
	for s in segs:
		var p0: Vector2 = center + Vector2(s[0].x, s[0].y) * radius
		var p1: Vector2 = center + Vector2(s[1].x, s[1].y) * radius
		var mid: Vector2 = (p0 + p1) * 0.5 + Vector2(-(p1 - p0).y, (p1 - p0).x).normalized() * 1.2
		draw_polyline(PackedVector2Array([p0, mid, p1]), crack_col, 1.3, true)

# —— 重绘节流（2026-10-10 性能优化）——
## 全量 _draw 每只怪一次重建几十条矢量指令，35 敌同屏就是每帧几千条，
## 是「敌人一多就卡」的头号热点。处理：普通怪降频 20Hz 重绘（本来是 10fps 帧动画风格，
## 20fps 矢量动画无感），精英/Boss 数量少保持每帧；每实例随机错相把重绘摊到不同帧
## 避免「每 N 帧一次尖峰」；屏外直接跳过重绘（_time 照常推进，回屏即恢复）。
## 60fps 档（2026-10-15 VisualRate 档位联动）：普通怪步进随物理 60Hz 翻倍，
## 20Hz 画面会露台阶，提到 30Hz；低档 20Hz 是 perf_probe 钉住的预算口径。
const HZ_MOB_LOW := 20.0            ## 省电档普通怪重绘频率
const HZ_MOB_HIGH := 30.0           ## 流畅档普通怪重绘频率
const HZ_ELITE := 30.0              ## 精英重绘频率（2026-10-15 起精英不再每帧全量重建）
const CULL_MARGIN := 64.0           ## 屏外剔除余量（px），防半身出屏闪烁
static var redraw_count: int = 0    ## 重绘发放计数（tests/PerfProbe 断言用）

## 敌人整体基准视觉缩放（在原有 config.scale_factor 基础上统一放大 25%，使体型更具压迫感且与碰撞体积饱满对齐）
const ENEMY_GLOBAL_SCALE := 1.25

var _draw_phase: float = 0.0        ## 距下次重绘的剩余时间（错相载体）
var _phase_seed: float = 0.0        ## 每实例呼吸相位（instance_id 派生，不碰玩法随机）
## 普通怪 = 档位节流；精英 = 30Hz；Boss = 每帧（0 间隔，数量恒 1，全量动画值得）。
## 默认按普通怪节流（config 未赋值前与旧口径一致）
var _is_mob: bool = true
var _is_boss: bool = false
var _offscreen: bool = false
var _dirty: bool = false            ## 状态翻转（镜像/换装）时插队重绘
## 屏外剔除变换缓存：全屏敌人共享同一个 canvas_transform + visible_rect，
## 每帧只查一次引擎接口（get_viewport / get_canvas_transform / get_visible_rect），
## 避免每敌每渲染帧 3 次冗余调用。
static var _cull_frame: int = -1
static var _cull_transform: Transform2D
static var _cull_limit: Vector2
static var _cull_valid: bool = false

## 本实例的重绘间隔：普通怪按帧率档位节流；精英恒 30Hz；
## Boss 每帧（0，数量恒 1，全量动画值得保每帧）
func _redraw_interval() -> float:
	if _is_boss:
		return 0.0
	if not _is_mob:
		return 1.0 / HZ_ELITE
	return VisualRate.interval(HZ_MOB_HIGH, HZ_MOB_LOW)

func _ready() -> void:
	# 错相：用 instance_id 派生初值（不碰玩法随机），把 35 只怪的重绘摊到不同帧，
	# 避免「每 N 帧一次集中重绘尖峰」把节流收益吃掉
	_draw_phase = fposmod(float(get_instance_id() % 97) * 0.001, _redraw_interval())
	_phase_seed = float(get_instance_id() % 17)

func _process(delta: float) -> void:
	_time += delta
	if recoil > 0.0:
		recoil = maxf(0.0, recoil - delta * 9.0)
		_dirty = true
	# 每帧首只怪刷新缓存，后续直接复用（get_viewport 等返回值在同一渲染帧内对所有节点相同）
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
		_offscreen = sp.x < -CULL_MARGIN or sp.y < -CULL_MARGIN \
			or sp.x > _cull_limit.x or sp.y > _cull_limit.y
		if _offscreen:
			return
	if _dirty or _draw_phase <= 0.0:
		_dirty = false
		_draw_phase = _redraw_interval()
		redraw_count += 1
		queue_redraw()
	else:
		_draw_phase -= delta

func _draw() -> void:
	if config == null:
		return

	# 全局朝向水平镜像与等比尺寸缩放处理
	var root_scale_x := -1.0 if flip_h else 1.0
	_draw_flip_x = root_scale_x
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(root_scale_x, 1.0) * (config.scale_factor * ENEMY_GLOBAL_SCALE))

	# 视线缓存（2026-10-23 全敌种瞳孔锁敌）：把全局 aim_dir 转到本地绘制坐标系（含镜像），
	# 供各眼型算瞳孔偏移。旧版只有邪修/剑煞/Boss 三处读 aim_dir 画器尖与法阵，
	# 其余 13 种怪的瞳孔钉死在脸上 —— 敌人在追你、眼睛却不看你，白白丢掉最省力的「有意识」读数。
	_local_aim_cache = Vector2.ZERO
	if aim_dir.length_squared() > 0.01:
		_local_aim_cache = Vector2(aim_dir.x * root_scale_x, aim_dir.y).normalized()

	# 精英/魔君常驻识别环（2026-10-14 P2）：贴地呼吸骨环，满屏时一眼分出「这只厚」。
	# 画在各敌种函数之前（垫底贴地层），所有敌型一次覆盖；Boss 用更宽的朱砂双环。
	# 2026-10-19 拥挤档联动：同屏敌人多时环叠环会糊，alpha 减半让位（Boss 保留主环读数）
	if config.is_boss or config.is_elite:
		var crowd_mult := 0.5 if FxBudget.crowded else 1.0
		var ring_r := config.body_radius + 8.0
		var ring_pulse := sin(_time * 2.4) * 0.06 + 0.94
		if config.is_boss:
			var boss_col := Color(0.85, 0.22, 0.28, 0.55 * ring_pulse * crowd_mult)
			_arc(Vector2(0, 15), ring_r + 3.0, 0.0, TAU, 40, boss_col, 3.2, true)
			_arc(Vector2(0, 15), ring_r * 0.8, 0.0, TAU, 40, Color(boss_col.r, boss_col.g, boss_col.b, 0.30 * crowd_mult), 1.4, true)
		else:
			var elite_col := Color(0.92, 0.86, 0.70, 0.50 * ring_pulse * crowd_mult)
			_arc(Vector2(0, 15), ring_r, 0.0, TAU, 32, elite_col, 2.4, true)

	# 根据敌种 ID 派发专属绘制管线
	match config.enemy_id:
		"slime":
			_draw_slime()
		"xiexiu":
			_draw_xiexiu()
		"danbao":
			_draw_danbao()
		"fengqun":
			_draw_fengqun()
		"flower":
			_draw_flower()
		"xueyong":
			_draw_xueyong()
		"guyao":
			_draw_guyao()
		"duyao":
			_draw_duyao()
		"yingmei":
			_draw_yingmei()
		"zhumu":
			_draw_zhumu()
		"leibeast":
			_draw_leibeast(false)
		"golem":
			_draw_golem()
		"chilei_elite":
			_draw_leibeast(true)
		"jiansha_elite":
			_draw_jiansha_elite()
		"lingyi":
			_draw_lingyi()
		"jinchan":
			_draw_jinchan()
		"hanpo":
			_draw_hanpo()
		"mowei":
			_draw_mowei()
		"xuanming_elite":
			_draw_xuanming_elite()
		"xingpan_elite":
			_draw_xingpan_elite()
		"wandu_elite":
			_draw_wandu_elite()
		"boss", "boss_chiyan", "boss_xiuluo", "boss_qianji", "boss_wangu", "boss_jianpo", "boss_xinmo":
			_draw_boss(config.is_final_boss)
		_:
			if config.is_boss:
				_draw_boss(config.is_final_boss)
			elif config.is_elite:
				_draw_golem()
			else:
				_draw_slime()

	# 残血裂痕（2026-10-23）：画在所有敌种之后（贴最上层），残血时的静帧硬读数。
	# 放在派发之后统一画，17 套绘制函数不用各改一遍，也保证不会被本体后画的图元盖住。
	_draw_hp_cracks(Vector2(0.0, config.body_radius * 0.1), config.body_radius)

# ==================== 1. 基础几何与空洞风图元绘制工具 ====================

## 自适应圆/弧段数（2026-10-14 性能优化）：内置 draw_circle 固定 64 段，
## 小至 1px 的眸光点也付 64 三角形的钱；本渲染器的 draw_circle/draw_arc 统一走这两个包装，
## 按半径与弧角张量自适应 6~32 段。静态缓冲复用，_draw 在主线程串行执行，无重入风险。
static var _circle_buf := PackedVector2Array()
static var _stroke_buf := PackedVector2Array()
## 敌种轮廓缓冲（2026-10-24 性能优化）：史莱姆 12 点 / 血蛹茧壳 16 点 / 血蛹缠带 5 点 /
## 雷兽鸟身 26 点 / 闭合椭圆描边 29 点原先每次 _draw 局部新建 Packed 数组（约千次/秒分配，
## Android 上是 GC 停顿来源），统一改静态缓冲覆写。口径同上：主线程串行，无重入风险。
static var _slime_buf := PackedVector2Array()
static var _shell_buf := PackedVector2Array()
static var _band_buf := PackedVector2Array()
static var _body_buf := PackedVector2Array()
static var _oval_stroke_buf := PackedVector2Array()

func _circle(center: Vector2, radius: float, col: Color) -> void:
	var seg := clampi(int(radius * 1.4), 6, 28)
	_circle_buf.resize(seg)
	for i in range(seg):
		var ang := float(i) * TAU / float(seg)
		_circle_buf[i] = center + Vector2(cos(ang), sin(ang)) * radius
	draw_colored_polygon(_circle_buf, col)

func _arc(center: Vector2, radius: float, start_angle: float, end_angle: float, _point_count: int, color: Color, width: float = 1.0, antialiased: bool = false) -> void:
	var seg := clampi(int(radius * absf(end_angle - start_angle) * 0.22), 6, 32)
	draw_arc(center, radius, start_angle, end_angle, seg, color, width, antialiased)

## 敌人轮廓描边色（空洞冷冽国风，低对比细勾边）：
## 2026-10-20 二次调整：用户反馈骨白粗边「太怪」。改为「本体主色提亮 + 微量强调色」，
## 即描边始终是本体的同色系浅一档，而不是白色或高饱和强调色（如丹爆的地火橙）。
## 史莱姆是暗红→淡红、影魅是虚空黑→冷灰、丹爆是青铜→浅铜，颜色各自贴合本体。
const CONTOUR_BONE := Color(0.80, 0.84, 0.89)
const CONTOUR_ACCENT_MIX := 0.12
const CONTOUR_LIGHTEN := 0.38
const CONTOUR_BONE_MIX := 0.06
const CONTOUR_ALPHA := 0.62
## 最低明度地板：本体极暗的敌种（影魅虚空黑、丹爆青铜）提亮后仍是深灰、贴黑底看不见，
## 这里按亮度缺口向骨白补一点点，保证所有敌种轮廓都能读到，但不改成白色。
const CONTOUR_MIN_VALUE := 0.42
const CONTOUR_FLOOR_MIX := 0.55
## 描边加粗倍率：仅做极轻微补偿（1.2~1.7 → 约 1.3~1.8），不做粗描边。
const STROKE_W_SCALE := 1.06
## 残血描边泛血色与掺入比例（2026-10-23）：濒死时轮廓向朱砂偏移，静帧一眼可读「这只快死了」。
const HP_CONTOUR_BLOOD := Color(0.78, 0.16, 0.20)
const HP_CONTOUR_MIX := 0.55

func _contour_color() -> Color:
	if config == null:
		return Color(CONTOUR_BONE.r, CONTOUR_BONE.g, CONTOUR_BONE.b, CONTOUR_ALPHA)
	# 本体主色（强制不透明）为基底，掺一丝强调色保留装饰色相，再提亮并掺极少量骨白做亮度锚点
	var base_c := Color(config.col_primary.r, config.col_primary.g, config.col_primary.b, 1.0)
	base_c = base_c.lerp(config.col_accent, CONTOUR_ACCENT_MIX).lightened(CONTOUR_LIGHTEN)
	var lit := base_c.lerp(CONTOUR_BONE, CONTOUR_BONE_MIX)
	# 明度地板：越暗补越多骨白，避免深色敌种轮廓消失在黑底
	if lit.v < CONTOUR_MIN_VALUE:
		var gap := (CONTOUR_MIN_VALUE - lit.v) / CONTOUR_MIN_VALUE
		lit = lit.lerp(CONTOUR_BONE, clampf(gap, 0.0, 1.0) * CONTOUR_FLOOR_MIX)
	# 残血描边泛血（2026-10-23）：生命 ≤40% 时轮廓向朱砂偏移、并略微加亮。
	# 为什么走描边而不是裂纹：裂纹是「贴在本体上的一笔」，各敌种轮廓差异大，常常糊进本体里；
	# 描边是**全敌种同一条通路**（17 套绘制函数全部走 _contour_color），静帧一眼可读，
	# 且不吃 modulate 通道（那是闪白/冰缓/引信染色的地盘）。
	var hurt := _low_hp_breath()
	if hurt > 0.6:
		var k := clampf((hurt - 0.6) / 0.4, 0.0, 1.0)
		lit = lit.lerp(HP_CONTOUR_BLOOD, k * HP_CONTOUR_MIX).lightened(k * 0.12)
	return Color(lit.r, lit.g, lit.b, CONTOUR_ALPHA)

func draw_stroked_polygon(pts: PackedVector2Array, fill_col: Color, stroke_col: Color, stroke_w: float = 1.4) -> void:
	if pts.size() < 3:
		return
	draw_colored_polygon(pts, fill_col)
	var n := pts.size()
	_stroke_buf.resize(n + 1)
	for i in range(n):
		_stroke_buf[i] = pts[i]
	_stroke_buf[n] = pts[0]
	draw_polyline(_stroke_buf, stroke_col, stroke_w * STROKE_W_SCALE, true)

func draw_filled_ellipse(pos: Vector2, rx: float, ry: float, col: Color) -> void:
	if rx <= 0.01 or ry <= 0.01:
		return
	var segments := clampi(int(maxf(rx, ry) * 1.2), 10, 24)
	_circle_buf.resize(segments)
	for i in range(segments):
		var ang := float(i) * TAU / float(segments)
		_circle_buf[i] = pos + Vector2(cos(ang) * rx, sin(ang) * ry)
	draw_colored_polygon(_circle_buf, col)

## 双层软地影（2026-10-18 阴影统一升级）：外层大而淡的弥散影 + 内层约六成大小的接触暗核，
## 让实体「扎根地面」。
## 2026-10-28 渲染性能治理：改由全场共享的 GroundShadowLayer 统一画 —— 原写法每只怪在自己
## item 里画 2 个多边形椭圆 = 2 个绘制调用（满场 48 只 ≈ 百个调用只为几摊影子），
## 且跨 CanvasItem 不合批。这里只上报参数：位置由该层按 caster 全局变换每帧现算（跟随移动），
## 尺寸/透明度吃本渲染器的 20/30Hz 重绘节奏（与旧行为更新频率一致）。
## tint 供特殊敌种换调（如毒妖湿绿）。
func _draw_soft_shadow(pos: Vector2, rx: float, ry: float, alpha: float, tint := Color(0.04, 0.05, 0.08)) -> void:
	if config == null:
		return
	var s: float = config.scale_factor * ENEMY_GLOBAL_SCALE
	var gs := get_global_transform().get_scale()
	var world_r: Vector2 = Vector2(rx * s * gs.x, ry * s * gs.y)
	# 尸体缩小淡出时影子要跟着走：半径吃全局缩放（上面 gs 已含 view 的 scale），
	# 透明度吃宿主 view 的 modulate —— 否则重绘停止前会留下一摊不淡不缩的黑影。
	# （死亡 tween 改的是 procedural_view 的 scale/modulate，本渲染器只是它的子节点。）
	var fade := 1.0
	var host := get_parent() as CanvasItem
	if host != null:
		fade = host.modulate.a * host.self_modulate.a
	GroundShadowLayer.push(self, Vector2(pos.x * _draw_flip_x * s, pos.y * s),
		world_r.x, world_r.y, alpha * fade, tint)

## 柔光晕（2026-10-28 渲染性能治理）：原先按 layers 叠 2~3 个多边形圆（每层一个绘制调用 +
## 十几段顶点、每层一次临时数组），改为一张共享径向渐变贴图铺一个矩形：
## 同 item 内连续同贴图矩形可合批，边缘也比叠圈更干净。
## 旧叠层叠加后中心不透明度约 0.5×col.a，这里用单层 0.5 系数复现同一亮度观感。
const GLOW_ALPHA_SCALE := 0.5

func draw_soft_glow(pos: Vector2, radius: float, col: Color, _layers: int = 3) -> void:
	if radius <= 0.01 or col.a <= 0.0:
		return
	draw_texture_rect(GroundShadowLayer.soft_texture(),
		Rect2(pos.x - radius, pos.y - radius, radius * 2.0, radius * 2.0),
		false, Color(col.r, col.g, col.b, col.a * GLOW_ALPHA_SCALE))

func draw_sharp_eye(pos: Vector2, width: float, height: float, col_glow: Color, col_core: Color) -> void:
	# 绘制狭长冷眸（外层幽光 + 内层锐核）
	# 2026-10-19 灵核脉动：幽光随呼吸微胀（±10%），全敌种共享，让静态形象有生命感
	# 2026-10-23 视线锁敌：锐核沿瞄准方向偏移 15% 眼幅，蓄力过半再加 7% 并提亮 ⇒ 出手前「瞪过来」
	var eye_pulse := 1.0 + sin(_time * 3.1 + _phase_seed) * 0.10
	draw_soft_glow(pos, width * 1.5 * eye_pulse, col_glow, 2)
	var gaze: Vector2 = _gaze_offset(width)
	var core_pos: Vector2 = pos + gaze
	var core_col: Color = col_core if special_state <= 0.35 else col_core.lerp(col_glow, 0.35)
	var pts := PackedVector2Array([
		core_pos + Vector2(-width, 0),
		core_pos + Vector2(0, -height),
		core_pos + Vector2(width, 0),
		core_pos + Vector2(0, height)
	])
	draw_colored_polygon(pts, core_col)
	# 高光竖线：跟着瞳孔走，锁敌时更亮（读作「眼里的反光在动」）
	var hl_a: float = clampf(_gaze_glare() - 0.55, 0.55, 1.0)
	draw_line(core_pos + Vector2(-width * 0.7, 0), core_pos + Vector2(width * 0.7, 0),
		Color(1.0, 1.0, 1.0, hl_a), 1.2, true)

# ==================== 2. 敌种专属程序化绘制管线 ====================

## 1. 史莱姆：幽冥血煞 / 凝魂怨泥 (贴地流质行进波)
func _draw_slime() -> void:
	# 行进波：gait_phase 沿面朝方向（x+）推一道「压扁-拉伸」波，与位移同相；
	# 待机时 crawl_amp=0，只留 _time 微呼吸，静止冻结不空抖。
	# 2026-10-23 残血喘息：生命越低呼吸越沉（幅度↑、频率↓），读作「快撑不住了」
	var crawl_amp := speed_ratio if is_moving else 0.0
	var hurt := _low_hp_breath()
	var breathe := sin(_time * (2.6 - hurt * 1.1) + _phase_seed) * (0.05 + hurt * 0.045)
	var squish_x := 1.0 + breathe + sin(gait_phase) * 0.10 * crawl_amp
	var squish_y := 1.0 - breathe - sin(gait_phase) * 0.10 * crawl_amp
	var nuc_y := 2.0 - sin(gait_phase * 0.5) * 1.2 * crawl_amp

	# 底部地渍摊开：贴地双层——外层腐蚀湿痕（比本体更宽更扁的暗红流摊），内层接触暗核
	_draw_soft_shadow(Vector2(0, 14.5), 16.5 * squish_x, 4.6, 0.5)
	draw_filled_ellipse(Vector2(0, 13.0), (18.5 + sin(gait_phase) * 1.8 * crawl_amp) * squish_x, 2.6,
		Color(config.col_primary.r, config.col_primary.g, config.col_primary.b, 0.42))

	# 柔性流质血煞外轮廓（12 节点平滑蛋形，逐点叠一道自背向面推进的行进波）
	_slime_buf.resize(12)
	for i in range(12):
		var ang := float(i) / 12.0 * TAU - PI * 0.5
		var px := cos(ang) * 15.0
		var py := sin(ang) * 12.5
		if py > 0.0:
			py *= 0.9 # 底部略收，贴地感
		# 行进波以横向坐标作相位偏移，形成前后挤压的流质起伏
		var w := sin(gait_phase - px * 0.32) * 1.7 * crawl_amp
		px += cos(ang) * w
		py += sin(ang) * w * 0.6
		_slime_buf[i] = Vector2(px * squish_x, py * squish_y)
	# 外轮廓走统一骨白勾边（2026-10-20：原暗黑凝血勾边在黑底战场上完全读不出轮廓）
	draw_stroked_polygon(_slime_buf, config.col_primary, _contour_color(), 1.3)

	# 流质润泽弧（左上暗血反光，表现湿滑血胶表面，绝不用纯白光斑）
	_arc(Vector2(0, -1), 10.2, deg_to_rad(198.0), deg_to_rad(250.0), 10, Color(0.82, 0.22, 0.28, 0.28), 1.4, true)

	# 内部深渊核（随蠕动沉浮）
	draw_filled_ellipse(Vector2(0, nuc_y), 8.2 * squish_x, 6.2, config.col_void)

	# 体内灵核：深渊中悬一颗深邃幽绿怨魂核（沉暗翡翠微晕，去亮白刺眼核心）
	var core_pos := Vector2(0, nuc_y + 1.2)
	var core_pulse := 1.0 + sin(_time * 3.4 + _phase_seed) * 0.12
	draw_soft_glow(core_pos, 4.8 * core_pulse, Color(0.12, 0.60, 0.30, 0.40), 2)
	_circle(core_pos, 1.6 * core_pulse, Color(0.18, 0.76, 0.38, 0.90))
	_circle(core_pos, 0.7 * core_pulse, Color(0.40, 0.92, 0.60, 0.85))

	# 沉浮暗骨碎片（沉在深渊内部的微细杂骨，暗骨色、纤细沉底，不喧宾夺主）
	draw_line(Vector2(-5.2, 5.0 + nuc_y * 0.2), Vector2(-1.5, 1.6 + nuc_y * 0.2), config.col_secondary, 1.2, true)
	draw_line(Vector2(2.8, 5.8 - nuc_y * 0.2), Vector2(6.4, 4.0 - nuc_y * 0.2), config.col_secondary, 1.0, true)

	# 边缘滴落小珠：底缘三颗错相凝滴、拉丝坠落再收回（深血色拉丝）
	for i in range(3):
		var bx := float(i - 1) * 7.5
		var base_y := 11.6 - absf(bx) * 0.1 # 贴合底缘弧线，滴从身上起
		var cycle := fposmod(_time * 0.85 + float(i) * 0.41 + gait_phase * 0.12, 1.0)
		var drop_y := base_y + cycle * 4.2
		var drop_r := lerpf(1.8, 0.5, cycle)
		# 拉丝细颈连回本体（滴将断未断，随坠落渐淡）
		draw_line(Vector2(bx, base_y - 1.0), Vector2(bx, drop_y),
			Color(config.col_accent.r, config.col_accent.g, config.col_accent.b, 0.55 * (1.0 - cycle * 0.7)), 1.2, true)
		_circle(Vector2(bx, drop_y), drop_r, Color(config.col_accent.r, config.col_accent.g, config.col_accent.b, 0.9 - cycle * 0.4))

	# 幽冷怨魂狭瞳（深渊黑腔上部的幽碧妖眸，竖直深渊瞳裂，完全消除刺眼白线与白斑）
	# 2026-10-23 视线：瞳体随瞄准方向平移 15%，深渊瞳缝跟着走 —— 史莱姆也会「盯着你挪」
	var eye_pos := Vector2(0, nuc_y - 1.8) + _gaze_offset(2.6)
	var eye_pulse := 1.0 + sin(_time * 2.8 + _phase_seed) * 0.08
	draw_soft_glow(eye_pos, 3.6 * eye_pulse, Color(0.10, 0.52, 0.25, 0.35), 2)
	var ew := 2.6 * eye_pulse
	var eh := 1.3 * eye_pulse
	var eye_pts := PackedVector2Array([
		eye_pos + Vector2(-ew, 0),
		eye_pos + Vector2(0, -eh),
		eye_pos + Vector2(ew, 0),
		eye_pos + Vector2(0, eh)
	])
	draw_colored_polygon(eye_pts, Color(0.18, 0.72, 0.36, 0.90))
	# 竖向深渊狭瞳缝（黑瞳裂孔，冷冽阴森，纯黑无白）
	draw_line(eye_pos + Vector2(0, -eh * 0.85), eye_pos + Vector2(0, eh * 0.85), config.col_void, 1.0, true)

## 2. 御剑邪修：幽冥剑客 (御剑悬浮滑行与器尖精准指向)
func _draw_xiexiu() -> void:
	var float_y := sin(_time * 2.8) * 2.4
	var t_bank := bank_angle * 0.85
	var adv_lean := deg_to_rad(advance * 4.0)
	var root_scale_x := -1.0 if flip_h else 1.0

	# 地影（高度变化驱动影子呼吸）
	var shadow_rx := 13.0 - float_y * 0.4
	_draw_soft_shadow(Vector2(0, 16), maxf(shadow_rx, 6.0), 4.0, 0.45)

	# 悬浮行进摆幅：gait_phase 与位移同相（移动才摆），待机只留 _time 微飘
	var drift_amp := speed_ratio if is_moving else 0.0
	var hem_sway := sin(gait_phase) * 2.4 * drift_amp + sin(_time * 2.2 + _phase_seed) * 0.7

	# 背负剑鞘（先画在袍后，斜背左肩→右胯，鞘口铜环与垂穗；上端探出肩线可见）
	var sheath_a := Vector2(-9.5, -8 + float_y * 0.5)
	var sheath_b := Vector2(5, 11 + float_y * 0.5)
	draw_line(sheath_a, sheath_b, config.col_void, 4.2, true)
	draw_line(sheath_a, sheath_b, config.col_accent, 1.2, true)
	_circle(sheath_a, 2.2, config.col_secondary)
	draw_line(sheath_a + Vector2(-1.5, 1.0), sheath_a + Vector2(-3.5 + hem_sway * 0.4, 6.5), Color(0.85, 0.25, 0.25, 0.85), 1.2, true)

	# 破风墨黑长袍下摆（残破锯齿摆，飘动与悬浮同相）
	var robe_pts := PackedVector2Array([
		Vector2(-9, 10 + float_y + hem_sway),
		Vector2(-7, -4 + float_y),
		Vector2(7, -4 + float_y),
		Vector2(9, 10 + float_y - hem_sway * 0.6),
		Vector2(5, 7 + float_y + hem_sway * 0.4),
		Vector2(2, 11 + float_y - hem_sway * 0.3),
		Vector2(-2, 8 + float_y + hem_sway * 0.5),
		Vector2(-5, 12 + float_y - hem_sway * 0.4)
	])
	draw_stroked_polygon(robe_pts, config.col_primary, _contour_color(), 1.3)
	# 道袍中缝束带（冷紫滚边，增加修仙长袍层次感）
	draw_line(Vector2(0, -4 + float_y), Vector2(0, 9 + float_y), config.col_accent, 1.5, true)
	# 腰间束绦（暗紫腰带 + 垂下随飘绦带）
	draw_line(Vector2(-6, 1 + float_y), Vector2(6, 1 + float_y), config.col_accent.lightened(0.15), 2.0, true)
	draw_polyline(PackedVector2Array([
		Vector2(-4, 2 + float_y),
		Vector2(-4.5 + hem_sway * 0.5, 7 + float_y),
		Vector2(-4 - hem_sway * 0.4, 11 + float_y)
	]), config.col_accent, 1.2, true)

	# 苍白修罗骨面
	var head_pos := Vector2(0, -9 + float_y)
	var mask_pts := PackedVector2Array([
		head_pos + Vector2(-6, 5),
		head_pos + Vector2(-7, -4),
		head_pos + Vector2(0, -9),
		head_pos + Vector2(7, -4),
		head_pos + Vector2(6, 5),
		head_pos + Vector2(0, 8) # 尖下巴
	])
	draw_stroked_polygon(mask_pts, config.col_secondary, config.col_void, 1.4)
	# 道髻束发：发髻圆坨（虚空黑带勾边）+ 横贯玉簪 + 脑后垂发（随飘）
	_circle(head_pos + Vector2(0, -10.5), 2.6, config.col_void)
	_arc(head_pos + Vector2(0, -10.5), 2.6, 0.0, TAU, 10, _contour_color(), 1.1, true)
	draw_line(head_pos + Vector2(-3.5, -11.0), head_pos + Vector2(3.5, -10.0), config.col_accent.lightened(0.25), 1.4, true)
	draw_polyline(PackedVector2Array([
		head_pos + Vector2(-6, -6),
		head_pos + Vector2(-7.5 - hem_sway * 0.5, 0),
		head_pos + Vector2(-7 + hem_sway * 0.4, 6)
	]), config.col_void, 2.2, true)
	# 额前修罗血纹与冷冽单眸
	draw_line(head_pos + Vector2(0, -7), head_pos + Vector2(0, 2), Color(0.75, 0.20, 0.35, 0.85), 1.4, true)
	draw_sharp_eye(head_pos + Vector2(2, -1), 3.5, 1.8, config.col_glow, Color.WHITE)

	# ---------------- 幽冥法剑（御空悬浮 / 瞄准指向 / 剑芒器尖） ----------------
	# 姿态分派：
	# 1. 蓄力段（special_state > 0）：剑身拔升、剑尖精准朝向玩家、高频颤振蓄势、器尖聚光成芒
	# 2. 发射后坐（recoil > 0）：剑身后挫反冲后复位
	# 3. 寻常巡航：身侧斜挑悬浮浮沉
	var casting := special_state > 0.0
	var local_aim := Vector2.RIGHT
	if aim_dir.length_squared() > 0.01:
		local_aim = Vector2(aim_dir.x * root_scale_x, aim_dir.y).normalized()

	var sword_pos := Vector2.ZERO
	var sword_rot := 0.0
	if casting or recoil > 0.001:
		# 瞄准射击姿态：飞剑悬浮于身前，剑刃沿 local_aim 直指目标
		var aim_ang := local_aim.angle()
		sword_rot = aim_ang
		# 蓄力后拉（5px）+ 后坐力（7px）+ 高频灵力振颤
		var pull_back := -local_aim * (5.0 * special_state + 7.0 * recoil)
		var jitter := Vector2(-local_aim.y, local_aim.x) * (sin(_time * 48.0) * 1.4 * special_state)
		sword_pos = Vector2(2, 4 + float_y) + pull_back + jitter
	else:
		# 寻常巡航：身侧斜挑（20° 倾角，随悬浮呼吸浮沉）
		sword_pos = Vector2(2, 8 + float_y)
		sword_rot = deg_to_rad(20.0) + t_bank * 0.5 - adv_lean * 0.5

	var t_sword := Transform2D(sword_rot, sword_pos)

	# 计算器尖坐标（用于 EnemyBase 出膛点精确对其）
	var tip_in_local := t_sword * Vector2(20.0, 0.0)
	weapon_tip_pos = Vector2(tip_in_local.x * root_scale_x, tip_in_local.y) * (config.scale_factor * ENEMY_GLOBAL_SCALE)

	# 飞剑本体幽光辉芒
	var sword_glow_a := 0.45 + special_state * 0.45 + recoil * 0.5
	draw_soft_glow(sword_pos, 16.0 + special_state * 6.0, config.col_glow * Color(1, 1, 1, sword_glow_a), 2)

	# 剑身几何体（修长锐利的冷冽飞剑）
	var blade_pts := PackedVector2Array([
		t_sword * Vector2(-16, -2.2),
		t_sword * Vector2(14, -1.2),
		t_sword * Vector2(20, 0.0), # 锋刃尖端
		t_sword * Vector2(14, 1.2),
		t_sword * Vector2(-16, 2.2)
	])
	draw_stroked_polygon(blade_pts, config.col_secondary, config.col_glow, 1.4)
	# 剑脊血槽刻纹（幽光流转）
	draw_line(t_sword * Vector2(-12, 0), t_sword * Vector2(15, 0), config.col_glow, 1.2, true)
	# 剑格护手与朱砂剑穗
	draw_line(t_sword * Vector2(-12, -4.5), t_sword * Vector2(-12, 4.5), config.col_accent, 2.2, true)
	draw_line(t_sword * Vector2(-16, 0), t_sword * Vector2(-22, 2.0), Color(0.85, 0.25, 0.25), 1.6, true)

	# 蓄力期间：器尖高亮凝芒 + 锐利瞄准虚芒（给玩家极强的弹道与威胁读数）
	if casting:
		# 器尖耀眼光斑：随蓄力进度由小聚大（special_state 0→1），读得出「正在攒劲」
		var charge := clampf(special_state, 0.0, 1.0)
		_circle(tip_in_local, 2.6 + charge * 3.2, Color(0.92, 0.98, 1.0, 0.95))
		draw_soft_glow(tip_in_local, 12.0 * charge, Color(0.35, 0.85, 1.0), 3)
		# 聚能环：进度过半后器尖浮出一圈收束弧，强化「能量在汇聚」的读数
		if charge > 0.35:
			var halo_a := (charge - 0.35) / 0.65
			_arc(tip_in_local, 5.0 + charge * 3.5, -PI * 0.7, PI * 0.7, 14,
				Color(0.55, 0.92, 1.0, 0.75 * halo_a), 1.3, true)
		# 前探瞄准虚芒针（向玩家方向伸出 22px，预示出膛轨道）
		var aim_line_len := 22.0 * charge
		var aim_line_end := tip_in_local + local_aim * aim_line_len
		draw_line(tip_in_local, aim_line_end, Color(0.35, 0.85, 1.0, 0.7 * charge), 1.6, true)
		draw_circle(aim_line_end, 1.6, Color(1.0, 1.0, 1.0, 0.85 * charge))

## 3. 丹爆傀儡：蚀骨丹炉 (三足鼎炉傀儡，引信点燃炉火暴涨)
func _draw_danbao() -> void:
	var t := _time + _phase_seed
	# 鼎身悬浮低晃（比旧圆形版更沉），引信点燃时炉身高频微颤
	var float_y := sin(t * 2.6) * 1.4
	var is_critical := special_state > 0.0 # 自爆引信点燃中
	var tremor := Vector2(sin(t * 44.0), cos(t * 37.0)) * (1.1 if is_critical else 0.0)
	var body_c := Vector2(0, -1 + float_y) + tremor
	# 引信点燃时炉膛压力胀缩（频率拉高、幅度加大）
	var boil := sin(t * (22.0 if is_critical else 5.0)) * (1.1 if is_critical else 0.35)
	var fire_h := 5.0 if not is_critical else 11.0 + boil * 2.0
	var bronze := config.col_primary.lightened(0.16)

	# 地影
	_draw_soft_shadow(Vector2(0, 15), 13.0 + boil * 0.5, 4.2, 0.5)

	# —— 三足：炉下三只粗短外撇的兽蹄足（引信点燃时随炉身微颤提起） ——
	for i in range(3):
		var fx: float = [-7.5, 0.0, 7.5][i]
		var foot_lift := (0.5 if is_critical else 0.0) * sin(t * 30.0 + float(i) * 2.1)
		var leg_pts := PackedVector2Array([
			body_c + Vector2(fx * 0.72 - 1.6, 7.5),
			body_c + Vector2(fx * 0.72 + 1.6, 7.5),
			body_c + Vector2(fx + 2.6, 13.0 - foot_lift),
			body_c + Vector2(fx - 2.6, 13.0 - foot_lift)
		])
		draw_stroked_polygon(leg_pts, bronze, config.col_void, 1.3)
		# 蹄底横垫
		draw_line(body_c + Vector2(fx - 2.6, 13.0 - foot_lift), body_c + Vector2(fx + 2.6, 13.0 - foot_lift), config.col_secondary, 1.6, true)

	# —— 鼎形炉身：束颈 + 鼓腹，青铜主体（2026-10-20 外轮廓改骨白勾边，黑底可读） ——
	var body_pts := PackedVector2Array([
		body_c + Vector2(-4.2, -9.0),
		body_c + Vector2(4.2, -9.0),
		body_c + Vector2(6.2, -6.5),
		body_c + Vector2(10.5 + boil, -1.0),
		body_c + Vector2(9.5 + boil, 6.5),
		body_c + Vector2(4.0, 9.5),
		body_c + Vector2(-4.0, 9.5),
		body_c + Vector2(-9.5 - boil, 6.5),
		body_c + Vector2(-10.5 - boil, -1.0)
	])
	draw_stroked_polygon(body_pts, bronze, _contour_color(), 1.7)
	# 腹部内衬浅铜面，让炉身体积与「器皿」质感读出来
	draw_filled_ellipse(body_c + Vector2(0, 1.5), 6.5 + boil * 0.6, 6.0, config.col_primary.lightened(0.3))

	# —— 炉口：束颈之上的圆口，铜沿 + 内透炉火 ——
	var mouth_y := -9.4
	draw_filled_ellipse(Vector2(body_c.x, body_c.y + mouth_y), 5.2, 2.0, config.col_secondary)
	draw_filled_ellipse(Vector2(body_c.x, body_c.y + mouth_y), 4.0, 1.4, config.col_void)
	var mouth_col: Color = Color(1.0, 0.42, 0.12) if not is_critical else Color(1.15, 0.25, 0.1)
	draw_filled_ellipse(Vector2(body_c.x, body_c.y + mouth_y), 3.0 + boil * 0.4, 1.0, mouth_col)

	# —— 炉口焰火：引信点燃时暴涨的三股火舌（折形火苗，冷冽硬边，3点三角形防自交） ——
	var flame_col := config.col_glow if not is_critical else config.col_glow.lerp(Color(1.0, 0.22, 0.1), 0.55)
	for i in range(3):
		var f_off: float = [-2.8, 0.0, 2.8][i]
		var f_h: float = maxf(1.8, fire_h * ([0.6, 1.0, 0.6][i]))
		var f_wob := sin(t * (9.0 if not is_critical else 26.0) + float(i) * 2.4) * 1.2
		var flame_pts := PackedVector2Array([
			body_c + Vector2(f_off - 1.2, mouth_y - 0.4),
			body_c + Vector2(f_off + f_wob, mouth_y - f_h),
			body_c + Vector2(f_off + 1.2, mouth_y - 0.4)
		])
		draw_colored_polygon(flame_pts, Color(flame_col.r, flame_col.g, flame_col.b, 0.9))

	# —— 炉身裂纹：细折线灼缝（常态暗色，点燃时透红光加宽） ——
	var crack_w := 1.1 + (0.7 if is_critical else 0.0) + boil * 0.2
	var crack_col: Color = Color(config.col_accent.r, config.col_accent.g, config.col_accent.b, 0.4) \
		if not is_critical else Color(1.1, 0.3, 0.14, 0.95)
	draw_polyline(PackedVector2Array([
		body_c + Vector2(-7.5, -3.0), body_c + Vector2(-5.0, 1.0),
		body_c + Vector2(-6.5, 5.5)
	]), crack_col, crack_w, true)
	draw_polyline(PackedVector2Array([
		body_c + Vector2(7.0, -4.0), body_c + Vector2(4.5, 0.0),
		body_c + Vector2(6.5, 4.5)
	]), crack_col, crack_w, true)
	if is_critical:
		# 点燃态：裂纹缝里透出脉动炉红光晕（读数：内压已到极限）
		draw_soft_glow(body_c + Vector2(-5.5, 1.0), 5.5, crack_col, 2)
		draw_soft_glow(body_c + Vector2(5.5, 0.0), 5.5, crack_col, 2)

	# —— 双立耳：炉沿两侧短粗上挑的青铜鼎耳 ——
	for i in [-1, 1]:
		var ear_pts := PackedVector2Array([
			body_c + Vector2(float(i) * 6.4, -8.2),
			body_c + Vector2(float(i) * 9.2, -11.6),
			body_c + Vector2(float(i) * 7.8, -12.8),
			body_c + Vector2(float(i) * 5.2, -9.4)
		])
		draw_stroked_polygon(ear_pts, config.col_secondary, config.col_void, 1.2)

	# —— 错金铭文：腹面三枚金钉竖排 ——
	for i in range(3):
		_circle(body_c + Vector2(0.0, -1.5 + float(i) * 3.0), 0.9, config.col_secondary)

## 4. 蜂群精：冥火毒螟 (冥火核 + 三只毒螟环绕飞舞，超高频振翅)
func _draw_fengqun() -> void:
	var center := Vector2(0, sin(_time * 6.0) * 1.6)
	var swarm_amp := speed_ratio if is_moving else 0.0

	# 轻量小地影
	_draw_soft_shadow(Vector2(0, 15), 9.0, 3.2, 0.35)

	# 冥火核：群魂共衔的一团剧毒磷火（身份核心，_time 呼吸明灭）
	var core_pulse := 1.0 + sin(_time * 5.2 + _phase_seed) * 0.16
	draw_soft_glow(center, 9.5 * core_pulse, config.col_glow * Color(1, 1, 1, 0.55), 3)
	_circle(center, 3.4 * core_pulse, config.col_glow)
	_circle(center, 1.5, Color(0.92, 1.0, 0.94, 0.95))
	# 核周两粒高速游走的余烬（冥火活性读数）
	for i in range(2):
		var ea := _time * 5.0 + float(i) * PI
		_circle(center + Vector2(cos(ea) * 5.5, sin(ea) * 4.0), 0.9, Color(config.col_glow.r, config.col_glow.g, config.col_glow.b, 0.8))

	# 三只小毒螟绕核飞舞：gait_phase 与位移同相推进公转，待机时 _time 保持巡绕；
	# 疾飞（is_moving）时轨道沿行进方向（x+）拉长成编队
	for i in range(3):
		var ph := float(i) * TAU / 3.0 + _phase_seed * 0.7
		var orbit := _time * 1.7 + gait_phase * 1.1 + ph
		var rx := 8.0 + sin(_time * 2.3 + ph) * 1.2
		var ry := 5.6 + cos(_time * 1.9 + ph) * 0.9
		rx *= 1.0 + swarm_amp * 0.42
		ry *= 1.0 - minf(swarm_amp * 0.16, 0.28)
		var bp := center + Vector2(cos(orbit) * rx, sin(orbit) * ry)
		# 头朝轨道切线（飞行前进方向）
		var tb := Transform2D(Vector2(-sin(orbit), cos(orbit) * 0.8).angle(), bp)
		var flap := absf(sin(_time * 52.0 + ph * 2.0)) # ~13Hz 高频振翅

		# 薄翼（青碧半透明，锚在胸节上随振翅扫掠，画在虫体下层）
		draw_colored_polygon(PackedVector2Array([
			tb * Vector2(-0.9, -0.4), tb * Vector2(-2.8, -2.1 - flap * 1.6), tb * Vector2(0.3, -0.7),
		]), config.col_accent * Color(1, 1, 1, 0.55))
		draw_colored_polygon(PackedVector2Array([
			tb * Vector2(0.6, -0.7), tb * Vector2(-1.6, -3.3 - flap * 2.4), tb * Vector2(3.4, -1.2 - flap * 0.8),
		]), config.col_accent * Color(1, 1, 1, 0.85))

		# 骨白毒腹（幽冥骨蜂体色：骨壳 + 暗色体节缝 + 毒针磷光尖）
		draw_stroked_polygon(PackedVector2Array([
			tb * Vector2(-0.5, -1.6), tb * Vector2(-3.6, -1.1), tb * Vector2(-5.5, 0.0),
			tb * Vector2(-3.6, 1.1), tb * Vector2(-0.5, 1.6),
		]), config.col_secondary, config.col_void, 1.1)
		draw_line(tb * Vector2(-1.8, -1.4), tb * Vector2(-1.8, 1.4), config.col_primary, 1.1, true)
		draw_line(tb * Vector2(-3.6, -1.0), tb * Vector2(-3.6, 1.0), config.col_primary, 1.0, true)
		_circle(tb * Vector2(-6.2, 0.0), 0.7, config.col_glow)

		# 胸节与头颅（骨甲连体）
		_circle(tb * Vector2(1.0, 0.0), 1.7, config.col_secondary)
		_circle(tb * Vector2(2.7, 0.0), 1.1, config.col_secondary)
		# 剧毒磷光复眼 + 前探触角
		_circle(tb * Vector2(3.2, -0.3), 0.6, config.col_glow)
		draw_line(tb * Vector2(3.3, -0.8), tb * Vector2(4.4, -1.9 - flap * 0.5), config.col_secondary, 0.7, true)
		draw_line(tb * Vector2(3.3, 0.5), tb * Vector2(4.6, 0.3), config.col_secondary, 0.7, true)

## 5. 花妖：噬灵妖花 (空灵悬浮舒展，妖花前倾索食)
func _draw_flower() -> void:
	var hurt := _low_hp_breath()
	# 残血：整株垂头（下坠 1.2px + 花瓣开合变弱），读作「蔫了」
	var float_y := sin(_time * (2.2 - hurt * 0.9)) * 2.6 + hurt * 1.2
	var petal_open := 1.0 + sin(_time * 3.5) * (0.15 - hurt * 0.09) # 花瓣呼吸开合（残血收拢）
	# 移动时整株沿面朝方向前倾摇摆（gait 与位移同相），待机只留微晃
	var crawl_amp := speed_ratio if is_moving else 0.0
	var lean := sin(gait_phase) * 0.16 * crawl_amp + sin(_time * 1.6 + _phase_seed) * 0.04
	var center := Vector2(sin(lean) * 9.0, -2 + float_y)

	# 地影
	_draw_soft_shadow(Vector2(0, 16), 13.0, 4.0, 0.45)

	# 花茎：从花头垂到根部，随前倾弯成弧线，茎上细刺
	var stem_base := Vector2(0, 15.0)
	var stem_mid := stem_base.lerp(center + Vector2(0, 8), 0.5) + Vector2(sin(lean) * 5.0, 0)
	draw_polyline(PackedVector2Array([center + Vector2(0, 7), stem_mid, stem_base]), config.col_accent, 2.6, true)
	draw_line(stem_mid + Vector2(-2.5, 0), stem_mid + Vector2(2.5, 1.0), config.col_accent.lightened(0.2), 1.0, true)
	# 根须三缕（贴地抓取的墨紫细须）
	for i in [-1, 0, 1]:
		var tw := sin(_time * 2.4 + float(i)) * 2.0
		draw_polyline(PackedVector2Array([
			stem_base, stem_base + Vector2(float(i) * 3.5 + tw * 0.4, 1.5),
			stem_base + Vector2(float(i) * 5.5 + tw, 3.0)
		]), config.col_accent * Color(1, 1, 1, 0.7), 1.2, true)

	# 苞叶层：花头下方 3 片托叶（骨白花萼，衬在花瓣后）
	for i in range(3):
		var bang := PI * 0.32 + float(i) * PI * 0.18
		var bx := cos(bang)
		var by := sin(bang)
		draw_stroked_polygon(PackedVector2Array([
			center + Vector2(bx * 4.0, by * 4.0 + 2.0),
			center + Vector2(bx * 11.0, by * 10.0 + 3.0),
			center + Vector2(bx * 6.5, by * 13.0 + 4.0),
		]), config.col_secondary * Color(1, 1, 1, 0.85), config.col_void, 1.1)

	# 5 片放射状锋利血色花瓣（外深内浅双色：外层大瓣 + 内层亮瓣错相半格）
	for i in range(5):
		var ang := float(i) * (TAU / 5.0) - PI * 0.5 + lean + sin(_time * 1.5) * 0.08
		var tip := center + Vector2(cos(ang), sin(ang)) * (16.0 * petal_open)
		var left := center + Vector2(cos(ang - 0.42), sin(ang - 0.42)) * (9.5 * petal_open)
		var right := center + Vector2(cos(ang + 0.42), sin(ang + 0.42)) * (9.5 * petal_open)
		draw_stroked_polygon(PackedVector2Array([center, left, tip, right]), config.col_primary, _contour_color(), 1.3)
		# 瓣面血络中脉
		draw_line(center + Vector2(cos(ang), sin(ang)) * 4.0, center + Vector2(cos(ang), sin(ang)) * 14.5 * petal_open,
			config.col_accent.lightened(0.15), 1.0, true)
		var ang_in := ang + PI / 5.0
		var tip_in := center + Vector2(cos(ang_in), sin(ang_in)) * (10.5 * petal_open)
		var l_in := center + Vector2(cos(ang_in - 0.34), sin(ang_in - 0.34)) * (5.5 * petal_open)
		var r_in := center + Vector2(cos(ang_in + 0.34), sin(ang_in + 0.34)) * (5.5 * petal_open)
		draw_stroked_polygon(PackedVector2Array([center, l_in, tip_in, r_in]),
			config.col_primary.lightened(0.28), config.col_void, 0.9)

	# 花心锯齿口器：虚空喉口中一圈向内咬合的骨白獠牙（吞噬读点）
	_circle(center, 6.0, config.col_void)
	for i in range(8):
		var sang := float(i) * TAU / 8.0 + _time * 0.5
		var s_out_l := center + Vector2(cos(sang - 0.28), sin(sang - 0.28)) * 5.6
		var s_out_r := center + Vector2(cos(sang + 0.28), sin(sang + 0.28)) * 5.6
		var s_tip := center + Vector2(cos(sang), sin(sang)) * 2.6
		draw_colored_polygon(PackedVector2Array([s_out_l, s_tip, s_out_r]), config.col_secondary)

	# 花蕊毒粉光点：3 粒磷粉绕花心螺旋升腾（噬灵读点）
	for i in range(3):
		var pa := _time * 2.2 + float(i) * TAU / 3.0
		var pr := 7.5 + sin(_time * 3.0 + float(i) * 2.1) * 2.5
		var pp := center + Vector2(cos(pa) * pr, sin(pa) * pr * 0.7 - 3.0)
		_circle(pp, 1.1, Color(config.col_glow.r, config.col_glow.g, config.col_glow.b, 0.85))

	# 噬灵邪眼（口器中央）
	draw_sharp_eye(center, 4.2, 2.5, config.col_glow, Color.WHITE)

## 6. 血蛹：九幽血茧 (贴地拱动与心跳搏动)
func _draw_xueyong() -> void:
	var crawl_amp := speed_ratio if is_moving else 0.0
	# 2026-10-23 残血：心跳变快变浅（搏动幅度衰减、频率上抬）—— 濒死的茧在急促抽动
	var hurt := _low_hp_breath()
	var pulse := sin(_time * (3.0 + hurt * 1.6)) * (1.2 - hurt * 0.5)
	var squish_x := 1.0 + sin(_time * 3.0) * (0.08 + hurt * 0.03)
	var squish_y := 1.0 - sin(_time * 3.0) * (0.08 + hurt * 0.03)

	# 地影
	_draw_soft_shadow(Vector2(0, 13), 16.0 * squish_x, 4.8, 0.55)

	var center := Vector2(0, 2)
	var rx := (13.0 + pulse * 0.5) * squish_x
	var ry := (15.0 - pulse * 0.5) * squish_y

	# 暗红血晶茧体：轮廓叠一道自尾向头的 slither 拱波（与 gait_phase 同相，移动才起波）
	_shell_buf.resize(16)
	for i in range(16):
		var ang := float(i) / 16.0 * TAU
		var px := cos(ang) * rx
		var py := sin(ang) * ry
		var arch := sin(gait_phase - px * 0.28) * 1.7 * crawl_amp
		_shell_buf[i] = center + Vector2(px, py + arch)
	draw_stroked_polygon(_shell_buf, config.col_primary, _contour_color(), 1.4)

	# 内部幽微血光核心（心跳明暗）
	var core_alpha := 0.4 + sin(_time * 3.0) * 0.25
	draw_soft_glow(center, 10.0, config.col_glow * Color(1, 1, 1, core_alpha), 2)

	# 缠带缝隙透血光：带间四道血缝随 _time 错相呼吸明灭（先画缝，缠带压缝上）
	for g in range(4):
		var gy := -7.5 + float(g) * 5.0
		var blink := 0.25 + 0.55 * maxf(sin(_time * 2.6 + float(g) * 1.7 + _phase_seed), 0.0)
		var ghw := rx * sqrt(maxf(1.0 - (gy / ry) * (gy / ry), 0.04)) * 0.62
		draw_line(center + Vector2(-ghw, gy), center + Vector2(ghw, gy),
			Color(config.col_glow.r, config.col_glow.g, config.col_glow.b, blink * 0.75), 1.6, true)

	# 茧壳缠带：5 道骨白封印布带交叉缠绕，中段下坠模拟裹贴茧面，暗色勾边分段
	for k in range(5):
		var y0 := -10.0 + float(k) * 5.0
		var slant := 3.0 if k % 2 == 0 else -3.0
		_band_buf.resize(5)
		for s in range(5):
			var t := float(s) / 4.0
			var dy := y0 + slant * (t * 2.0 - 1.0)
			var sag := sin(t * PI) * 2.2
			# 半宽按「带实际落点高度」夹到茧面内，防下坠段戳出轮廓
			var ry_eff := maxf(ry - absf(dy + sag), 1.0)
			var hw := rx * sqrt(maxf(1.0 - ((dy + sag) / ry) * ((dy + sag) / ry), 0.04)) * (ry_eff / ry)
			_band_buf[s] = center + Vector2((t * 2.0 - 1.0) * hw, dy + sag)
		# 暗底宽描边 + 骨白带身 = 粗黑勾边缠带
		draw_polyline(_band_buf, config.col_void, 4.8, true)
		draw_polyline(_band_buf, config.col_secondary, 3.2, true)
		# 布面织纹：沿带的暗色细中线
		draw_polyline(_band_buf, config.col_primary.lightened(0.1), 0.8, true)
		# 隔带朱砂封灵符线
		if k % 2 == 1:
			draw_polyline(_band_buf, Color(0.85, 0.15, 0.2, 0.9), 1.1, true)

	# 顶端 2~3 根短触须微颤（将裂未裂的探知读点）
	for i in range(3):
		var bx := -2.5 + float(i) * 2.5
		var tw := sin(_time * 6.5 + float(i) * 2.2) * 1.6
		var root := center + Vector2(bx, -ry + 1.5)
		var tip := root + Vector2(bx * 0.5 + tw, -6.0)
		draw_polyline(PackedVector2Array([
			root, root + Vector2(bx * 0.25 + tw * 0.5, -3.2), tip
		]), config.col_secondary, 1.2, true)
		_circle(tip, 0.9, config.col_glow)

## 7. 毒妖：腐沼毒蟾 (浮沉 + 背负腐毒囊)
## 特殊状态（special_state > 0）时毒囊胀大、囊内磷火转亮 —— 与投毒预警同源可读：
## 玩家看到它「鼓起来」就知道脚下要出毒潭了（预警圈负责精确落点，这里负责身份预告）。
func _draw_duyao() -> void:
	var float_y := sin(_time * 2.4) * 1.6
	var charge := clampf(special_state, 0.0, 1.0)  # 投毒蓄力 0→1 连续进度（出手后回落到 0）
	var sac_swell := 1.0 + charge * 0.42 + sin(_time * (3.0 + charge * 7.0)) * (0.04 + charge * 0.08)

	# 腐沼地影（比鼓妖更湿更扁）
	_draw_soft_shadow(Vector2(0, 16), 15.5, 4.0, 0.45, Color(0.04, 0.07, 0.05))

	var body_c := Vector2(0, float_y + 1.0)

	# 发达后腿蹲伏：两侧鼓起的股部肌肉块 + 收拢贴地的折叠脚（先画在躯干后）
	for i in [-1.0, 1.0]:
		var thigh := body_c + Vector2(i * 9.0, 6.0)
		# 股部提亮两档带轮廓，读得出「蛙蹲」的肌肉块
		draw_filled_ellipse(thigh, 6.0, 7.5, config.col_primary.lightened(0.18))
		_arc(thigh, 6.0, PI * (0.5 if i < 0 else -0.5), PI * (1.5 if i < 0 else 0.5), 12, config.col_void, 1.4, true)
		# 股上疣粒两枚（与背疣同调）
		_circle(thigh + Vector2(i * 1.5, -2.5), 1.2, config.col_accent.lightened(0.1))
		_circle(thigh + Vector2(i * 2.5, 1.2), 1.0, config.col_accent.lightened(0.1))
		# 折叠收拢的脚：贴地外撇，三趾骨白短爪（不外伸出轮廓）
		var foot := body_c + Vector2(i * 9.5, 13.0)
		draw_line(thigh + Vector2(i * 1.0, 6.5), foot, config.col_primary.lightened(0.1), 3.0, true)
		draw_line(foot, foot + Vector2(i * 2.5, 1.5), config.col_secondary, 1.3, true)
		draw_line(foot, foot + Vector2(i * 0.5, 2.5), config.col_secondary, 1.3, true)
		draw_line(foot, foot + Vector2(i * -1.5, 2.0), config.col_secondary, 1.3, true)

	# 厚皮躯体：宽扁蹲伏蛙形，肩窄胯宽
	var body_pts := PackedVector2Array([
		body_c + Vector2(-8, -9),
		body_c + Vector2(8, -9),
		body_c + Vector2(12, 2),
		body_c + Vector2(9, 12),
		body_c + Vector2(3, 13.5),
		body_c + Vector2(-3, 13.5),
		body_c + Vector2(-9, 12),
		body_c + Vector2(-12, 2)
	])
	draw_stroked_polygon(body_pts, config.col_primary, _contour_color(), 1.4)

	# 前趾两枚（腹下扒地）
	for i in [-1.0, 1.0]:
		draw_line(body_c + Vector2(i * 3.5, 12.5), body_c + Vector2(i * 4.5, 15.0), config.col_primary.darkened(0.1), 2.2, true)
		draw_line(body_c + Vector2(i * 4.5, 15.0), body_c + Vector2(i * 3.2, 15.6), config.col_secondary, 1.0, true)
		draw_line(body_c + Vector2(i * 4.5, 15.0), body_c + Vector2(i * 5.8, 15.6), config.col_secondary, 1.0, true)

	# 背部毒囊疣粒：两排错列（后排 4 前排 3），苔绿鼓粒带暗勾边与高光
	for i in range(4):
		var wx := -6.0 + float(i) * 4.0
		var wy := -7.2 + absf(float(i) - 1.5) * 0.6
		var wr := 1.7 + (0.5 if i % 2 == 0 else 0.0) + charge * 0.5
		_circle(body_c + Vector2(wx, wy), wr, config.col_accent.lightened(0.12))
		_arc(body_c + Vector2(wx, wy), wr, 0, TAU, 8, config.col_void, 1.0, true)
		_circle(body_c + Vector2(wx - wr * 0.3, wy - wr * 0.35), wr * 0.35, config.col_secondary * Color(1, 1, 1, 0.55))
	for i in range(3):
		var wx2 := -4.0 + float(i) * 4.0
		var wr2 := 1.4 + charge * 0.4
		_circle(body_c + Vector2(wx2, -4.0), wr2, config.col_accent.darkened(0.15))
		_arc(body_c + Vector2(wx2, -4.0), wr2, 0, TAU, 8, config.col_void, 0.9, true)

	# 脓黄斑块（侧腹两团）
	draw_filled_ellipse(body_c + Vector2(-8.0, 4.0), 3.0, 2.2, config.col_secondary)
	draw_filled_ellipse(body_c + Vector2(8.0, 4.0), 3.0, 2.2, config.col_secondary)

	# 背负腐毒囊：鼓胀囊体 + 囊内核。投毒蓄力（special_state 0→1）时囊体渐胀渐亮、
	# 囊面血丝透绿光，出手后 special_state 归零自然回落
	var sac_c := body_c + Vector2(-2.0, -13.5 - charge * 2.0)
	var sac_r: float = 7.5 * sac_swell
	draw_filled_ellipse(sac_c, sac_r, sac_r * 0.92, config.col_secondary)
	_arc(sac_c, sac_r, 0, TAU, 24, config.col_void, 1.6, true)
	var core_alpha: float = 0.45 + charge * 0.5
	draw_soft_glow(sac_c, sac_r * 0.9, config.col_glow * Color(1, 1, 1, core_alpha), 2)
	# 囊面绷起的毒液血丝（蓄力越足越显）
	for i in range(3):
		var va := float(i) * TAU / 3.0 + 0.6
		draw_line(sac_c + Vector2(cos(va), sin(va)) * sac_r * 0.25,
			sac_c + Vector2(cos(va), sin(va)) * sac_r * 0.8,
			Color(config.col_glow.r, config.col_glow.g, config.col_glow.b, 0.25 + charge * 0.6), 1.1, true)
	_circle(sac_c, sac_r * (0.34 + charge * 0.12), config.col_glow)
	# 囊体与躯体之间的毒液导管（蓄力时脉动加粗）
	draw_line(sac_c + Vector2(3.0, sac_r * 0.7), body_c + Vector2(4.0, -7.0), config.col_secondary, 2.0 + charge * 1.2, true)

	# 竖瞳（毒磷火色）：蓄力时亮度随进度提档
	var eye_glow: Color = config.col_glow if charge <= 0.0 else config.col_glow.lightened(0.5 * charge)
	draw_sharp_eye(body_c + Vector2(-4.0, -1.5), 1.5, 3.2, eye_glow, Color.WHITE)
	draw_sharp_eye(body_c + Vector2(4.0, -1.5), 1.5, 3.2, eye_glow, Color.WHITE)

	# 宽口缝上翘 + 口角毒涎（两角各挂一条错相滴落的毒丝）
	var mouth_y: float = body_c.y + 6.0
	draw_polyline(PackedVector2Array([
		body_c + Vector2(-6.0, mouth_y - 1.0), body_c + Vector2(0, mouth_y + 1.0), body_c + Vector2(6.0, mouth_y - 1.0)
	]), config.col_void, 2.0, true)
	draw_polyline(PackedVector2Array([
		body_c + Vector2(-5.4, mouth_y - 1.2), body_c + Vector2(0, mouth_y + 0.6), body_c + Vector2(5.4, mouth_y - 1.2)
	]), config.col_secondary, 1.2, true)
	for i in [-1.0, 1.0]:
		var drip := fposmod(_time * 1.5 + (0.5 if i < 0.0 else 0.0), 1.0)
		var cx: float = i * 5.6
		draw_line(body_c + Vector2(cx, mouth_y - 0.5), body_c + Vector2(cx + i * 0.4, mouth_y + drip * 6.5),
			Color(config.col_glow.r, config.col_glow.g, config.col_glow.b, 0.7 - drip * 0.5), 1.1, true)
		_circle(body_c + Vector2(cx + i * 0.4, mouth_y + drip * 6.5), lerpf(1.3, 0.5, drip), config.col_glow)

## 8. 鼓妖：白骨摄魂鼓 (律动悬浮敲击)
## 2026-10-19 强化：鼓面补太极S分界线、云雷纹环与鼓钉圈，鼓身加骨箍条与骨珠穗，
## 双骨槌按 0.55s 节拍交替敲击（缓举快落、落槌瞬间震纹扩散、鼓身随拍微颤）。
## 鼓妖无蓄力行为，全部律动由 _time 驱动。
func _draw_guyao() -> void:
	var beat_period := 0.55  ## 单槌节拍周期（秒）
	var beat := _time / beat_period - floorf(_time / beat_period)
	# 击槌侧别：偶数拍击右、奇数拍击左，左右交替
	var striker := 1.0 if fposmod(floorf(_time / beat_period), 2.0) < 0.5 else -1.0
	# 槌头举幅 0=贴面 1=举至最高点：节拍前 12% 为落槌贴面瞬间，随后缓举、末段快落
	var amp := 0.0
	if beat >= 0.12:
		if beat < 0.68:
			amp = sin((beat - 0.12) / 0.56 * PI * 0.5)
		else:
			amp = cos((beat - 0.68) / 0.32 * PI * 0.5)
	# 落槌瞬间整鼓的节拍微颤（前 15% 衰减）
	var knock := 1.0 - clampf(beat / 0.15, 0.0, 1.0)
	var float_y := sin(_time * 2.6) * 2.2 - knock * 0.8
	var drum_center := Vector2(0, float_y)

	# 地影（随拍微胀）
	_draw_soft_shadow(Vector2(0, 15), 15.0 + knock * 1.2, 4.2, 0.45)

	# 煞铜重鼓鼓身（略扁椭圆，半径随拍微胀）
	var body_rx := 14.5 + knock * 0.5
	draw_filled_ellipse(drum_center, body_rx, 12.0, config.col_primary)
	_arc(drum_center, body_rx, 0, TAU, 28, _contour_color(), 1.4, true)

	# 鼓身下缘三道骨箍条（蒙皮箍骨感）
	for i in [-1, 0, 1]:
		var bx := float(i) * 7.5
		draw_line(drum_center + Vector2(bx, 8.5), drum_center + Vector2(bx * 1.15, 11.5), config.col_secondary, 1.5, true)

	# 鼓面太极魔纹与灵玉核心（补太极S分界线，阴阳魔纹读得清）
	_arc(drum_center, 8.5, 0, TAU, 20, config.col_accent, 1.4, true)
	_arc(drum_center + Vector2(0, -4.25), 4.25, -PI * 0.5, PI * 0.5, 12, config.col_accent, 1.1, true)
	_arc(drum_center + Vector2(0, 4.25), 4.25, PI * 0.5, PI * 1.5, 12, config.col_accent, 1.1, true)
	draw_soft_glow(drum_center, 8.0, config.col_glow * Color(1, 1, 1, 0.6), 2)
	_circle(drum_center, 3.2, config.col_glow)

	# 云雷纹环：8 枚雷纹钩饰绕灵核排布（骨白细线，冷冽仪轨感）
	for i in range(8):
		var cloud_ang := float(i) * TAU / 8.0 + 0.39
		var rad_v := Vector2(cos(cloud_ang), sin(cloud_ang))
		var tan_v := Vector2(-rad_v.y, rad_v.x)
		var cloud_base := drum_center + rad_v * 6.2
		draw_polyline(PackedVector2Array([
			cloud_base + tan_v * 2.0,
			cloud_base - tan_v * 1.1,
			cloud_base - tan_v * 1.1 + rad_v * 1.5,
			cloud_base + tan_v * 0.5 + rad_v * 1.5,
		]), config.col_secondary, 1.0, true)

	# 鼓钉圈：16 颗骨白钉头压周，圈定鼓面边界
	for i in range(16):
		var nail_ang := float(i) * TAU / 16.0
		_circle(drum_center + Vector2(cos(nail_ang), sin(nail_ang)) * (body_rx - 1.4), 0.9, config.col_secondary)

	# 鼓框两侧咬合的白骨獠牙
	for i in [-1, 1]:
		var fx := float(i) * 14.0
		draw_polyline(PackedVector2Array([
			drum_center + Vector2(fx, -6),
			drum_center + Vector2(fx + float(i) * 4.0, 0),
			drum_center + Vector2(fx, 6)
		]), config.col_secondary, 2.0, true)

	# 鼓身下悬三缕骨珠穗（_time 微风摆荡）
	for i in [-1, 0, 1]:
		var tassel_sway := sin(_time * 2.6 + float(i) * 1.1) * 2.0
		var tassel_top := drum_center + Vector2(float(i) * 5.0, 10.0)
		var tassel_mid := tassel_top + Vector2(tassel_sway * 0.4, 3.2)
		var tassel_end := tassel_mid + Vector2(tassel_sway, 3.0)
		draw_polyline(PackedVector2Array([tassel_top, tassel_mid, tassel_end]), config.col_secondary, 1.2, true)
		_circle(tassel_end, 1.1, config.col_secondary)

	# 双白骨槌交替敲击：击拍侧走缓举快落节拍，另一侧悬停待命
	for s in [-1.0, 1.0]:
		var is_striker: bool = s == striker
		var hit_pt := drum_center + Vector2(s * 8.0, -1.0)
		var raise_pt := drum_center + Vector2(s * 16.5, -13.0)
		var mallet_head := hit_pt
		if is_striker:
			mallet_head = hit_pt.lerp(raise_pt, amp)
		else:
			mallet_head = drum_center + Vector2(s * 18.0, -4.0 - (0.55 + sin(_time * 2.2 + s) * 0.06) * 2.0)
		# 槌柄：虚空黑描边 + 骨白杆
		var handle_end := mallet_head + Vector2(s * 6.5, -6.0)
		draw_line(mallet_head, handle_end, config.col_void, 3.0, true)
		draw_line(mallet_head, handle_end, config.col_secondary, 2.0, true)
		# 槌头：骨球 + 灵玉高光点
		_circle(mallet_head, 2.6, config.col_secondary)
		_circle(mallet_head + Vector2(-s * 0.7, -0.7), 1.0, config.col_glow)
		# 震纹：落槌后前 30% 节拍里，一圈摄魂灵纹自击点扩散
		if is_striker and beat < 0.3:
			var rip := beat / 0.3
			_arc(hit_pt, 3.0 + rip * 8.0, 0, TAU, 16, config.col_glow * Color(1, 1, 1, (1.0 - rip) * 0.5), 1.3, true)

## 9. 影魅：幽冥影煞 (半透虚空幽灵：黑袍躯 + 骨白鬼面 + 下摆飘带触手)
func _draw_yingmei() -> void:
	var t := _time + _phase_seed
	var float_y := sin(t * 3.5) * 1.8
	# 移动时整体前探、飘带向后拖曳；静止时垂直下垂缓摆
	var drift := (sin(gait_phase) * 2.5 * speed_ratio) if is_moving else 0.0
	var head_pos := Vector2(drift * 0.4, -8 + float_y)

	# 虚空地影
	_draw_soft_shadow(Vector2(0, 15), 12.0, 3.6, 0.35)

	# —— 下摆飘带触手：4 条虚空黑烟带，gait/_time 驱动相位错开的飘舞 ——
	for i in range(4):
		var u := float(i) - 1.5
		var root_x := u * 5.0
		var sway := sin(t * 4.2 + float(i) * 1.3) * 3.0 + drift * (1.0 + absf(u) * 0.3)
		var mid := head_pos + Vector2(root_x + sway * 0.4, 14.5)
		var tip := mid + Vector2(sway - drift * 0.8, 7.5 + sin(t * 5.0 + float(i)) * 1.5)
		var w := 3.4 - absf(u) * 0.6
		var ribbon := PackedVector2Array([
			head_pos + Vector2(root_x - w, 7.0),
			mid + Vector2(-w * 0.65, 0),
			tip,
			mid + Vector2(w * 0.65, 0),
			head_pos + Vector2(root_x + w, 7.0)
		])
		# 双层透明：外层幽紫残烟更淡，内层虚空黑主带
		draw_colored_polygon(ribbon, Color(config.col_accent.r, config.col_accent.g, config.col_accent.b, 0.35))
		draw_colored_polygon(PackedVector2Array([
			head_pos + Vector2(root_x - w * 0.6, 7.5),
			mid + Vector2(-w * 0.35, 0), tip,
			mid + Vector2(w * 0.35, 0),
			head_pos + Vector2(root_x + w * 0.6, 7.5)
		]), Color(config.col_primary.r, config.col_primary.g, config.col_primary.b, 0.92))

	# —— 虚空黑袍躯：钟形罩体，肩窄裾宽，半透分层 ——
	var cloak_pts := PackedVector2Array([
		head_pos + Vector2(-5.5, -1.0),
		head_pos + Vector2(5.5, -1.0),
		head_pos + Vector2(10.5, 7.0 + sin(t * 4.0) * 0.8),
		head_pos + Vector2(9.0, 13.0),
		head_pos + Vector2(0, 11.5),
		head_pos + Vector2(-9.0, 13.0),
		head_pos + Vector2(-10.5, 7.0 - sin(t * 4.0) * 0.8)
	])
	draw_stroked_polygon(cloak_pts, Color(config.col_primary.r, config.col_primary.g, config.col_primary.b, 0.92), _contour_color(), 1.4)
	# 袍内残烟：一层更淡的幽紫内衬雾团
	draw_filled_ellipse(head_pos + Vector2(0, 6.0), 6.0, 5.0, Color(config.col_accent.r, config.col_accent.g, config.col_accent.b, 0.22))

	# —— 骨白鬼脸面具：面无表情，两眼洞 + 竖裂口 ——
	var mask_pts := PackedVector2Array([
		head_pos + Vector2(-5.5, -4.0),
		head_pos + Vector2(5.5, -4.0),
		head_pos + Vector2(6.0, 1.0),
		head_pos + Vector2(0, 5.5),
		head_pos + Vector2(-6.0, 1.0)
	])
	draw_stroked_polygon(mask_pts, Color(config.col_secondary.r, config.col_secondary.g, config.col_secondary.b, 0.95), config.col_void, 1.4)
	# 眼洞（虚空黑洞，底浮妖紫瞳光）
	# 2026-10-23 视线：瞳光在眼洞内偏移（眼洞是固定黑洞，瞳光游走 = 面具后有人在看）
	for i in [-1, 1]:
		draw_filled_ellipse(head_pos + Vector2(float(i) * 2.6, -1.0), 1.7, 2.2, config.col_void)
		_circle(head_pos + Vector2(float(i) * 2.6, -0.6) + _gaze_offset(1.7), 0.8, config.col_glow)
	# 裂口嘴缝（面无表情，只一道竖裂）
	draw_line(head_pos + Vector2(0, 1.5), head_pos + Vector2(0, 4.5), config.col_void, 1.3, true)

	# —— 双支向后弯曲的影骨角（角根埋进面具上缘，画在面具之上确保相连） ——
	for i in [-1, 1]:
		draw_stroked_polygon(PackedVector2Array([
			head_pos + Vector2(float(i) * 2.0, -4.5),
			head_pos + Vector2(float(i) * 6.5, -13.5),
			head_pos + Vector2(float(i) * 11.0, -12.0),
			head_pos + Vector2(float(i) * 5.5, -8.0),
			head_pos + Vector2(float(i) * 5.5, -3.5)
		]), config.col_secondary, config.col_void, 1.1)

## 10. 百目妖：千目邪母 (多目微眨沉重悬浮)
## 2026-10-19 强化：大小错落的双层眼阵（中圈 6 + 外圈 8，共 14 颗），每颗独立频率
## 错开眨眼（闭眼画眼缝而非消失）；中央主目改竖瞳，眼眶骨白勾边、眼白血丝放射。
## 产卵怪无蓄力行为，全部节奏由 _time 驱动。
func _draw_zhumu() -> void:
	var float_y := sin(_time * 1.8) * 2.2
	var center := Vector2(0, float_y)

	# 庞大地影
	_draw_soft_shadow(Vector2(0, 18), 20.0, 5.5, 0.5)

	# 巨大深紫魔核躯体
	draw_filled_ellipse(center, 18.0, 15.0, config.col_primary)
	_arc(center, 18.0, 0, TAU, 32, _contour_color(), 1.4, true)

	# 皮下血肉筋络（两条脉纹，衬托千目邪母的活体感）
	_arc(center + Vector2(-6, 2), 9.0, PI * 0.15, PI * 0.85, 12, config.col_accent * Color(1, 1, 1, 0.5), 1.0, true)
	_arc(center + Vector2(6, -1), 8.5, PI * 1.2, PI * 1.85, 12, config.col_accent * Color(1, 1, 1, 0.5), 1.0, true)

	# 下方蠕动的微弱触手
	for i in range(-2, 3):
		var sx := float(i) * 5.0
		var tw := sin(_time * 3.0 + float(i)) * 3.0
		draw_polyline(PackedVector2Array([
			center + Vector2(sx, 12),
			center + Vector2(sx + tw * 0.5, 18),
			center + Vector2(sx + tw, 23)
		]), config.col_primary, 2.0, true)

	# 主魔眼（正中央巨眼，竖瞳）：骨白外眶 → 虚空眼白 → 血丝 → 金红虹膜 → 竖瞳
	draw_filled_ellipse(center, 8.2, 6.2, config.col_secondary)
	draw_filled_ellipse(center, 7.0, 5.2, config.col_void)
	# 眼白血丝：从虹膜外缘向眼白放射 6 条（血肉色，静态排布）
	for i in range(6):
		var vein_ang := float(i) * TAU / 6.0 + 0.4
		var vein_rad := Vector2(cos(vein_ang), sin(vein_ang))
		draw_line(center + vein_rad * 3.6, center + vein_rad * (5.6 if absf(vein_rad.x) > 0.6 else 4.2),
			config.col_accent, 0.8, true)
	var iris_pulse := 1.0 + sin(_time * 2.4 + _phase_seed) * 0.07
	# 2026-10-23 视线：整颗虹膜+竖瞳沿瞄准方向游走（巨眼是这只怪的主读点，必须真的在看你）
	var iris_c: Vector2 = center + _gaze_offset(4.0)
	draw_filled_ellipse(iris_c, 4.0 * iris_pulse, 4.4 * iris_pulse, config.col_glow)
	# 竖瞳：狭长虚空黑裂 + 冷冽高光
	draw_filled_ellipse(iris_c, 1.15, 3.9, config.col_void)
	_circle(iris_c + Vector2(-1.6, -1.5), 0.7, Color(1.0, 0.97, 0.85, 0.9))

	# 周身 14 颗邪眼（offset/radius/freq/phase 四元组）：
	# 频率互质错开，任意时刻总有几颗在眨；闭眼画骨白眼缝，睁眼分大中小三层
	var eye_specs: Array = [
		# —— 中圈 6 颗主副眼 ——
		[Vector2(-10, -6), 2.8, 3.7, 0.0], [Vector2(10, -6), 2.6, 4.3, 1.1],
		[Vector2(-12, 3), 2.7, 4.9, 2.3], [Vector2(12, 3), 2.5, 3.3, 0.7],
		[Vector2(-5, 9), 2.6, 5.3, 3.1], [Vector2(5, 9), 2.4, 3.9, 1.7],
		# —— 外圈 8 颗小眼（贴边缘，大小错落）——
		[Vector2(0, -11.5), 1.9, 4.7, 2.6], [Vector2(-6.5, -10), 1.6, 3.5, 0.9],
		[Vector2(6.5, -10), 1.7, 5.1, 3.5], [Vector2(-15.0, -1), 1.5, 4.1, 1.4],
		[Vector2(15.0, -1), 1.6, 3.1, 2.9], [Vector2(-8, 12), 1.7, 4.5, 0.3],
		[Vector2(8, 12), 1.5, 5.5, 2.0], [Vector2(0, 13.2), 1.6, 3.3, 4.1],
	]
	for idx in range(eye_specs.size()):
		var spec: Array = eye_specs[idx]
		var ep: Vector2 = center + spec[0]
		var er: float = spec[1]
		var blink: float = sin(_time * spec[2] + spec[3] + _phase_seed * 0.61)
		if blink <= -0.72:
			# 闭眼：骨白眼缝横线 + 两端骨结（错开的眨眼节奏读得见）
			draw_line(ep + Vector2(-er * 0.9, 0), ep + Vector2(er * 0.9, 0), config.col_secondary, 1.3, true)
			_circle(ep + Vector2(-er * 0.9, 0), 0.5, config.col_secondary)
			_circle(ep + Vector2(er * 0.9, 0), 0.5, config.col_secondary)
			continue
		# 睁眼：骨白外眶勾边 → 虚空眼白 → 邪眸光核
		_arc(ep, er, 0, TAU, 12, config.col_secondary, 1.1, true)
		_circle(ep, er * 0.85, config.col_void)
		# 中圈 6 颗补放射血丝，外圈小眼省略（性能预算）
		if idx < 6:
			for v in range(3):
				var v_ang: float = float(v) * TAU / 3.0 + spec[3]
				var v_dir := Vector2(cos(v_ang), sin(v_ang))
				draw_line(ep + v_dir * (er * 0.5), ep + v_dir * (er * 1.5), config.col_accent, 0.7, true)
		# 眸核微脉动（相位错开，密密麻麻的金红邪眸逐颗呼吸）
		# 2026-10-23 视线：14 颗副眼瞳核同向偏移 —— 一整片眼阵齐刷刷盯过来，是这只怪最强的压迫感来源
		var pupil_r := er * (0.42 + sin(_time * 2.9 + spec[3] * 1.7) * 0.06)
		_circle(ep + _gaze_offset(er * 0.85), pupil_r, config.col_glow)

## 羽片：从 base 到 tip 的一片渐细羽毛（中段微微外扩做出羽面弧度），自带黑描边。
func _draw_feather(base: Vector2, tip: Vector2, w_base: float, w_mid: float,
		fill: Color, stroke: Color, stroke_w: float = 1.0) -> void:
	var d := tip - base
	var dlen := d.length()
	if dlen < 0.5:
		return
	var n := d / dlen
	var p := Vector2(-n.y, n.x)
	var mid := base + d * 0.55
	draw_stroked_polygon(PackedVector2Array([
		base + p * w_base, mid + p * w_mid, tip, mid - p * w_mid, base - p * w_base
	]), fill, stroke, stroke_w)

## 高段数椭圆填充（鸟身/鸟颅专用）：_circle 与 _arc 都按半径自适应段数，
## 半径 5~8 只给 6~11 段，画圆身会变成多边形「桶」；这里固定 28 段保证圆润。
static var _oval_buf := PackedVector2Array()

func _draw_oval(center: Vector2, rx: float, ry: float, col: Color) -> void:
	var seg := 28
	_oval_buf.resize(seg)
	for i in range(seg):
		var ang := float(i) * TAU / float(seg)
		_oval_buf[i] = center + Vector2(cos(ang) * rx, sin(ang) * ry)
	draw_colored_polygon(_oval_buf, col)

## 高段数椭圆描边（同上，闭合 polyline 而非 arc）。缓冲覆写口径同 _oval_buf。
func _stroke_oval(center: Vector2, rx: float, ry: float, col: Color, width: float) -> void:
	var seg := 28
	_oval_stroke_buf.resize(seg + 1)
	for i in range(seg + 1):
		var ang := float(i) * TAU / float(seg)
		_oval_stroke_buf[i] = center + Vector2(cos(ang) * rx, sin(ang) * ry)
	draw_polyline(_oval_stroke_buf, col, width, true)

## 11. 雷兽 / 赤雷兽 (雷鸦·振翅飞行兽)
## 2026-10-22 整只重画：旧版是贴地四足走兽，四条腿只有髋/膝/蹄三点、单一相位对角摆动，
## 观感僵硬（用户现场否决「四肢类走路效果太差」）；中途两版膜翼兽也读不清（半透明翼膜在黑底上
## 只剩一根白线、钩爪像掸子）。现在按猛禽画：圆身鸟躯 + 钩喙鸟首 + 扇形分离飞羽双翼 +
## 尾羽扇 + 收拢鸟爪，动感全交给振翅/尾羽摆动。蓄力时双翼高举收拢、身体前倾、
## 冠羽与翼尖电弧提亮——冲撞预警读数与原版一致。
func _draw_leibeast(is_elite: bool) -> void:
	var t := _time + _phase_seed
	var charge := clampf(special_state, 0.0, 1.0) # 冲刺蓄力 0→1 进度
	# 振翅相位：移动时吃 gait_phase（与位移同相）；静止时 gait_phase 冻结，改用 _time 慢拍
	var flap := sin(gait_phase if is_moving else t * 2.6)
	var flap_amp := 0.62 if is_moving else 0.22
	# 悬浮浮沉：移动时由步态二次谐波驱动，静止时低频呼吸
	var bob := (sin(gait_phase * 2.0) * 1.5 * speed_ratio) if is_moving else (sin(t * 2.4) * 1.1)
	# 蓄力：整体下沉蓄劲；出手后坐（recoil 1→0）身体向上回弹
	var sink := charge * 2.4 - recoil * 1.8
	var body_c := Vector2(0, -2.0 + bob + sink)
	var lean := charge * 0.16 - recoil * 0.10 # 蓄力前倾角

	# 悬空地影：小、淡，读出离地高度（鸟不落地）
	_draw_soft_shadow(Vector2(0, 15), (11.0 if not is_elite else 13.5), 3.2, 0.28)

	# 前倾旋转变换（绕躯干中心 body_c）
	var pure_rot := Transform2D(lean, Vector2.ZERO)
	var rot := Transform2D(lean, body_c - pure_rot * body_c)

	# 振翅角：正=翼尖上抬（上扑）；蓄力时整体收拢后掠，后坐时展开
	var wing_ang := flap * flap_amp - charge * 0.34 + recoil * 0.22
	var arc_a := clampf(charge * 0.9 + (speed_ratio * 0.45 if is_moving else 0.0), 0.0, 1.0)
	var wscale := 1.0 if not is_elite else 1.06

	# —— 双翼：远翼（后上、压暗）先画，近翼（前下、亮）后画 ——
	# 翼形 = 一根粗骨臂（肩→腕）+ 腕节外扇的 5 片长初级飞羽 + 臂下 3 片短次级飞羽。
	# 飞羽是分离的独立羽片（各带黑描边），所以翼形靠羽片读出来，不依赖大片半透明膜。
	for layer in range(2):
		var is_near: bool = layer == 1
		# 两翼分层：远翼抬到肩上方（几乎向上扇）、更小更暗；近翼压到肩下、更大更亮。
		# 2026-10-22 修：两翼角度差只有 22°、根点只差 2px 时，远翼整片被近翼盖住，
		# 侧视读成「只有一只翅膀」。
		var root := body_c + (Vector2(-3.4, -6.8) if not is_near else Vector2(-0.4, -2.4))
		var ang := wing_ang * (1.0 if is_near else 0.80) + (deg_to_rad(-12.0) if is_near else deg_to_rad(30.0))
		var wt := rot * Transform2D(ang, root)
		var sw := (1.0 if is_near else 0.74) * wscale
		var fea_fill := config.col_accent if is_near else config.col_accent.darkened(0.42)
		# 翼骨臂：用羽色掺本体色（纯本体色在赤雷兽上偏红棕，会和躯干糊成一根横管）
		var arm_fill := fea_fill.lerp(config.col_primary, 0.45)
		# 羽片描边：羽色压暗一档的「暗缝」，既能分出羽片又不至于像虚空黑硬边把羽勾成刀锋。
		# （用亮色描边试过：羽片之间失去分隔，整扇翼糊成一团毛）
		var fea_stroke := fea_fill.darkened(0.44)
		var arm_stroke := arm_fill.darkened(0.36)
		# 骨臂：肩→腕的粗羽臂（与躯干同色，只靠黑描边分界，避免在身前一横亮条）
		var s_pt: Vector2 = wt * (Vector2(0.6, 1.0) * sw)
		var w_pt: Vector2 = wt * (Vector2(-6.2, -8.8) * sw)
		_draw_feather(s_pt, w_pt, 2.6 if is_near else 2.1, 2.9 if is_near else 2.3,
			arm_fill, arm_stroke, 1.1)
		# 初级飞羽：自腕节扇形展开（越靠翼尖越长），蓄力收翼时羽扇夹紧
		# 末片收到接近水平（不再下垂到躯干下缘），否则会读成一根横插的棍
		var fan := [
			Vector2(-13.6, -13.2), Vector2(-17.4, -10.0), Vector2(-19.6, -5.8),
			Vector2(-20.2, -1.6), Vector2(-18.4, 2.0)
		]
		for k in range(fan.size()):
			var u := float(k) / float(fan.size() - 1)
			var tp: Vector2 = fan[k]
			# 收翼：羽尖向腕节回缩（charge 越大越夹）
			var tp_c := w_pt + (wt * (tp * sw) - w_pt) * (1.0 - charge * 0.26)
			_draw_feather(w_pt, tp_c, 1.5 if is_near else 1.2, 2.2 if is_near else 1.8,
				fea_fill.lerp(config.col_secondary, 0.42 * (1.0 - u * 0.7)), fea_stroke, 0.9)
		# 次级飞羽：臂下两片短羽，填住翼面内侧（贴臂走，不外伸成横条）
		for k in range(2):
			var u := float(k) / 1.0
			var b_pt: Vector2 = wt * (Vector2(-1.4 - u * 3.0, -2.4 - u * 3.6) * sw)
			var e_pt: Vector2 = wt * (Vector2(-7.4 - u * 4.2, -1.2 - u * 3.0) * sw)
			_draw_feather(b_pt, e_pt, 1.3, 1.9, fea_fill.darkened(0.16), fea_stroke, 0.8)
		# 翼尖电弧：移动或蓄力时最外侧羽尖噼啪放电（读数：雷压在翼上攒着）
		if arc_a > 0.05:
			var tip0: Vector2 = w_pt + (wt * (fan[0] * sw) - w_pt) * (1.0 - charge * 0.26)
			var d_out := (tip0 - w_pt).normalized()
			var jag := tip0 + d_out * 2.4 + Vector2(1.8, -1.2)
			draw_polyline(PackedVector2Array([
				tip0, jag, tip0 + d_out * 4.4 + Vector2(-0.6, -2.6)
			]), Color(config.col_glow.r, config.col_glow.g, config.col_glow.b, arc_a * 0.85), 1.1, true)

	# —— 尾羽扇：四/五片骨羽自尾根向后下展开，随振翅轻摆 ——
	var tail_sway := (sin(gait_phase * 0.7 + 1.2) * 0.14) if is_moving else (sin(t * 1.6) * 0.08)
	var tail_root: Vector2 = rot * (body_c + Vector2(-6.6, 2.6))
	var tail_n := 4 if not is_elite else 5
	for k in range(tail_n):
		var u := float(k) / float(tail_n - 1) - 0.5 # -0.5..0.5
		# 尾羽向后下铺开（约 148°），长度中等，读成一把尾扇而不是毛团
		var ang := deg_to_rad(148.0) + u * 0.52 + tail_sway
		var flen := (10.2 - absf(u) * 1.4) * (1.0 if not is_elite else 1.14)
		var tp: Vector2 = rot * (body_c + Vector2(-7.0 + cos(ang) * flen, 1.8 + sin(ang) * flen))
		_draw_feather(tail_root, tp, 1.2, 1.6,
			config.col_accent.darkened(0.18).lerp(config.col_secondary, 0.28),
			config.col_accent.darkened(0.46), 0.8)

	# —— 躯干：斜置蛋形鸟身（前高后低的飞行姿态）——
	# 2026-10-22 修：正圆躯干 + 上下半圈覆羽色块，被腰线横切读成「西瓜」。
	# 现在躯干整体沿 -12° 斜置（前胸抬、后腰沉），覆羽只做「背上一块圆羽斑」，
	# 不再用腰线分割；体积靠翼根阴影与腹部亮斑读。
	var body_rx := 7.6 if not is_elite else 8.8
	var body_ry := 5.6 if not is_elite else 6.6
	var body_fill := config.col_primary.lerp(config.col_accent, 0.34)
	var body_tilt := deg_to_rad(-12.0)
	# 躯干局部坐标系：以 body_c 为中心、按 body_tilt 斜置
	var bt := rot * Transform2D(body_tilt, body_c)
	_body_buf.resize(26)
	for i in range(26):
		var a := float(i) * TAU / 26.0
		# 后腰（cos<0）略收、前胸（cos>0）略鼓 → 蛋形
		var taper := 1.0 + 0.06 * maxf(cos(a), 0.0) - 0.04 * maxf(-cos(a), 0.0)
		_body_buf[i] = bt * Vector2(cos(a) * body_rx * taper, sin(a) * body_ry)
	draw_stroked_polygon(_body_buf, body_fill, config.col_primary.darkened(0.40), 1.3)
	# 体积只用「上缘高光 + 下缘暗影」两条弧读（不再叠内部斑块：三块椭圆叠在一起会读成熊猫眼）
	_arc(bt * Vector2(-0.6, -0.4), body_rx * 0.74, deg_to_rad(206.0), deg_to_rad(316.0), 16,
		config.col_accent.darkened(0.06), 1.5, true)
	_arc(bt * Vector2(0.8, 0.8), body_rx * 0.82, deg_to_rad(24.0), deg_to_rad(150.0), 16,
		config.col_primary.darkened(0.34), 2.0, true)
	# 胸侧雷纹（折线闪电，蓄力时提亮；只做身份记号，压在前胸）
	var bolt_col := config.col_accent.lerp(config.col_glow, charge * 0.7)
	draw_polyline(PackedVector2Array([
		bt * Vector2(3.2, -1.6), bt * Vector2(1.8, 0.6),
		bt * Vector2(3.4, 1.0), bt * Vector2(2.0, 3.2)
	]), bolt_col, 1.2, true)

	# —— 鸟首：蓝颅 + 骨白钩喙 + 骨白雷角 + 锐眸 ——
	# 2026-10-22 定稿。踩过的坑：①骨白填充→读成灰白石头；②整圈亮描边→读成月牙；
	# ③颈楔→灰方块；④双细冠→两块木板；⑤draw_sharp_eye 自带 2 层软光晕，把喙整个盖掉、
	# 在黑底上糊成一坨白。现在：颅用与躯干同族的蓝色（不掺灰），亮色只给喙/角/眸，
	# 眸自绘小锐菱形（不加光晕），喙做大做实心并从颅右前方伸出。
	var hk := 1.0 if not is_elite else 1.14
	var head_pos: Vector2 = rot * (body_c + Vector2(4.0, -7.0 + charge * 1.8))
	# 颅：蓝色主体（与躯干同族，略亮一档）+ 暗描边
	var skull_fill := body_fill.lightened(0.10)
	_draw_oval(head_pos, 5.0 * hk, 4.6 * hk, skull_fill)
	_stroke_oval(head_pos, 5.0 * hk, 4.6 * hk, config.col_primary.darkened(0.40), 1.2)
	# 骨白雷角：一支实心粗三角自颅顶向后上方掠出（蓄力前倾），角根压进颅体
	var horn_len := (7.2 if not is_elite else 9.6) * hk
	var hb_a: Vector2 = head_pos + Vector2(-2.2, -3.1) * hk
	var hb_b: Vector2 = head_pos + Vector2(2.0, -2.2) * hk
	var ht: Vector2 = head_pos + Vector2(-horn_len * 0.46 + charge * 2.4, -3.4 * hk - horn_len)
	var horn_col := config.col_secondary.darkened(0.10).lerp(config.col_glow, charge * 0.85)
	draw_stroked_polygon(PackedVector2Array([hb_a, ht, hb_b]), horn_col,
		config.col_primary.darkened(0.52), 1.2)
	if charge > 0.10:
		_circle(ht, 0.8, Color(config.col_glow.r, config.col_glow.g, config.col_glow.b, charge * 0.9))
	# 骨白钩喙：厚实楔形自颅右前方伸出，尖端下钩（整只鸟最亮的硬边）
	# 2026-10-22 修：喙只有 ~5px 高，中间那条暗「喙缝」会把它劈成上下两条白细条，
	# 读成「两根筷子」——喙缝直接删掉，改由喙的下缘折角表达上下喙。
	# 喙形：喙根贴颅（宽约 3px），向前收窄到喙尖，尖端再下钩（钩子靠最后两点折出）
	# 喙尺寸铁律：喙长 ≈ 颅半径（5px），喙高 ≈ 3px。之前喙长 9px、高 5px，
	# 占掉半张脸，整只读成「铲子」。喙根压进颅体，尖端用最后两点折出下钩。
	draw_stroked_polygon(PackedVector2Array([
		head_pos + Vector2(1.4, -2.0) * hk,  # 上喙根（压进颅体）
		head_pos + Vector2(7.4, -0.9) * hk,  # 上喙前缘
		head_pos + Vector2(8.6, 0.6) * hk,   # 喙尖
		head_pos + Vector2(7.4, 1.9) * hk,   # 下钩
		head_pos + Vector2(4.6, 1.5) * hk,   # 下喙缘
		head_pos + Vector2(1.4, 1.9) * hk    # 下喙根（压进颅体）
	]), config.col_secondary, config.col_primary.darkened(0.52), 1.1)
	# 锐眸：自绘小菱形（不用 draw_sharp_eye：它自带 2 层软光晕会糊成大块白）
	# 2026-10-23 视线：菱形瞳核与高光沿瞄准方向偏移，猛禽锁定猎物的读法
	var eye_p: Vector2 = head_pos + Vector2(1.4, -2.2) * hk + _gaze_offset(1.6)
	var eye_w := 1.6 * hk
	var eye_h := 1.0 * hk
	draw_colored_polygon(PackedVector2Array([
		eye_p + Vector2(-eye_w, 0), eye_p + Vector2(0, -eye_h),
		eye_p + Vector2(eye_w, 0), eye_p + Vector2(0, eye_h)
	]), config.col_glow)
	_circle(eye_p + Vector2(0.3, 0), 0.55, config.col_glow.lightened(0.55))
	if charge > 0.5:
		# 蓄力瞳焰拖尾（前探方向）
		draw_line(eye_p + Vector2(eye_w, 0), eye_p + Vector2(eye_w + charge * 3.4, 0),
			config.col_glow, 1.2, true)


## 12. 铁甲魔傀（精英）：幽冥玄铁巨傀 (重力悬浮磁场)
## 2026-10-19 强化：双层叠甲肩盾+甲脊骨刺、胸铠全身铆钉与甲缝青铜勾线、胸口核心炉光点光；
## 新增双臂巨拳。震地蓄力（special_state 0→1，EnemyBase _elite_slam_windup_t 接线）时
## 双臂与身体上抬蓄劲、核心炉光随进度增亮，出手瞬间 special_state 归零、躯体回落砸地。
func _draw_golem() -> void:
	# 蓄力姿态：0=常态悬浮，0→1 蓄劲上抬；用缓入曲线让「攒劲」有重量感
	var charge := clampf(special_state, 0.0, 1.0)
	var lift := charge * charge  # 缓入：起手慢、临近出手抬得快
	var float_y := sin(_time * 2.0) * 1.8 - lift * 5.0
	var center := Vector2(0, -2 + float_y)
	# 蓄力时甲缝灵光全面提亮（读数：玄铁要压不住了）
	var forge_bright := 1.0 + charge * 1.6

	# 沉重巨地影（蓄力抬升时影子收缩变淡，落回时砸实）
	_draw_soft_shadow(Vector2(0, 18), 22.0 - lift * 3.0, 6.0 - lift * 0.8, 0.6 - lift * 0.18)

	# 青黑玄铁核心胸铠
	var chest_pts := PackedVector2Array([
		center + Vector2(-12, 10),
		center + Vector2(-15, -4),
		center + Vector2(0, -12),
		center + Vector2(15, -4),
		center + Vector2(12, 10),
		center + Vector2(0, 14)
	])
	draw_stroked_polygon(chest_pts, config.col_primary, _contour_color(), 1.5)

	# 甲缝勾线：胸铠左右斜向分甲缝 + 中轴缝（青铜灵流铭纹，蓄力时随炉光提亮）
	var seam_col := config.col_accent * Color(forge_bright, forge_bright, forge_bright, 0.9)
	draw_polyline(PackedVector2Array([
		center + Vector2(-15, -4), center + Vector2(-8, -1), center + Vector2(-10, 8),
	]), seam_col, 1.2, true)
	draw_polyline(PackedVector2Array([
		center + Vector2(15, -4), center + Vector2(8, -1), center + Vector2(10, 8),
	]), seam_col, 1.2, true)

	# 全身铆钉：沿胸铠轮廓排一圈骨白钉头
	var rivet_spots := [
		Vector2(-13.5, -2), Vector2(-11.5, 8.5), Vector2(-6, 12), Vector2(6, 12),
		Vector2(11.5, 8.5), Vector2(13.5, -2), Vector2(-8, -8), Vector2(8, -8),
	]
	for spot in rivet_spots:
		_circle(center + spot, 0.95, config.col_secondary)

	# 胸口核心炉光：点光炉口（draw_soft_glow 灵核幽火），亮度随蓄力进度增亮
	var glow_r := 12.0 * (0.7 + charge * 0.9)
	var glow_a := 0.45 + charge * 0.5
	draw_soft_glow(center, glow_r, config.col_glow * Color(1, 1, 1, glow_a), 3)

	# 胸口旋转的幽蓝菱形阵眼灵石（蓄力时转速随炉压加快）
	var rot := _time * (1.2 + charge * 2.2)
	var gem_pts := PackedVector2Array([
		center + Vector2(cos(rot), sin(rot)) * 6.0,
		center + Vector2(cos(rot + PI * 0.5), sin(rot + PI * 0.5)) * 6.0,
		center + Vector2(cos(rot + PI), sin(rot + PI)) * 6.0,
		center + Vector2(cos(rot + PI * 1.5), sin(rot + PI * 1.5)) * 6.0
	])
	draw_colored_polygon(gem_pts, config.col_glow.lightened(charge * 0.4))
	_circle(center, 1.8, Color(0.95, 1.0, 1.0, 0.9))

	# 浮空两侧的玄铁巨盾肩甲：双层叠甲 + 甲脊骨刺（随蓄力上抬外张）
	for i in [-1, 1]:
		var fx := float(i) * 19.0
		var fy := -lift * 4.0
		var sh_pts := PackedVector2Array([
			center + Vector2(fx - 4, -8 + fy),
			center + Vector2(fx + 4, -8 + fy),
			center + Vector2(fx + 5, 8 + fy),
			center + Vector2(fx - 5, 8 + fy)
		])
		draw_stroked_polygon(sh_pts, config.col_secondary, _contour_color(), 1.3)
		# 上层叠甲片（错缝压叠，深一档玄铁色出层次）
		var sh2_pts := PackedVector2Array([
			center + Vector2(fx - 3.4, -12.5 + fy),
			center + Vector2(fx + 3.4, -12.5 + fy),
			center + Vector2(fx + 4.2, -7.5 + fy),
			center + Vector2(fx - 4.2, -7.5 + fy)
		])
		draw_stroked_polygon(sh2_pts, config.col_primary, _contour_color(), 1.2)
		# 甲脊骨刺（朝外上方三支）
		draw_polyline(PackedVector2Array([
			center + Vector2(fx - 2.0, -12.5 + fy), center + Vector2(fx + float(i) * 2.0, -16.0 + fy),
		]), config.col_secondary, 1.6, true)
		draw_polyline(PackedVector2Array([
			center + Vector2(fx, -12.5 + fy), center + Vector2(fx + float(i) * 0.5, -16.8 + fy),
		]), config.col_secondary, 1.6, true)
		draw_polyline(PackedVector2Array([
			center + Vector2(fx + 2.0, -12.5 + fy), center + Vector2(fx - float(i) * 1.5, -16.0 + fy),
		]), config.col_secondary, 1.6, true)
		# 盾面铆钉三颗（虚空黑沉孔） + 灵流铭线
		for k in range(3):
			_circle(center + Vector2(fx, -5.0 + float(k) * 4.5 + fy), 0.8, config.col_void)
		draw_line(center + Vector2(fx - 3.0, 2.5 + fy), center + Vector2(fx + 3.0, 2.5 + fy), seam_col, 1.0, true)

	# —— 双臂巨拳（画在肩甲与胸铠之上，拳体在前可读）：
	# 常态垂于胸铠下缘两侧，蓄力时整臂上抬收向身侧（举臂读招，出手归零砸落） ——
	for s in [-1.0, 1.0]:
		var shoulder := center + Vector2(s * 15.0, -5.0 - lift * 3.0)
		var elbow := center + Vector2(s * 14.0, 4.0 - lift * 7.0)
		var fist := center + Vector2(s * 12.5, 11.0 - lift * 17.0)
		# 上臂/前臂玄铁节杆（骨白亮边勾出深色杆体轮廓，黑底/胸铠上均可读）
		draw_line(shoulder, elbow, config.col_secondary, 5.2, true)
		draw_line(shoulder, elbow, config.col_primary, 3.6, true)
		draw_line(elbow, fist, config.col_secondary, 5.2, true)
		draw_line(elbow, fist, config.col_primary, 3.6, true)
		_circle(elbow, 2.2, config.col_secondary)
		# 巨拳：骨白铁拳（与骨盾同系，深色胸铠上高反差）+ 虚空黑指节铆钉
		var fist_pts := PackedVector2Array([
			fist + Vector2(-3.4, -2.6), fist + Vector2(3.4, -2.6),
			fist + Vector2(4.2, 1.4), fist + Vector2(2.2, 3.8),
			fist + Vector2(-2.6, 3.8), fist + Vector2(-4.2, 1.4),
		])
		draw_stroked_polygon(fist_pts, config.col_secondary, config.col_void, 1.2)
		for k in range(3):
			_circle(fist + Vector2(-1.8 + float(k) * 1.8, -1.4), 0.7, config.col_void)
		# 蓄力满握：拳缝灵光渐亮（攒劲读数）
		if charge > 0.3:
			var grip := (charge - 0.3) / 0.7
			draw_line(fist + Vector2(-3.0, 0.4), fist + Vector2(3.0, 0.4),
				config.col_glow * Color(1, 1, 1, 0.7 * grip), 1.4, true)

	# 头顶方形青铜古面（蓄力随身抬）
	var head_pts := PackedVector2Array([
		center + Vector2(-7, -12),
		center + Vector2(7, -12),
		center + Vector2(6, -20),
		center + Vector2(-6, -20)
	])
	draw_stroked_polygon(head_pts, config.col_primary, config.col_secondary, 1.4)
	# 额缝青铜铭线与目缝灵光（蓄力时目缝增亮成读数）
	draw_line(center + Vector2(0, -20), center + Vector2(0, -17.5), config.col_accent, 1.2, true)
	draw_line(center + Vector2(-4, -16), center + Vector2(4, -16),
		config.col_glow.lightened(charge * 0.5), 1.8 + charge * 0.8, true)

## 13. 剑煞邪修（精英）：万剑煞宗残魂 (破碎红袍人形 + 环绕剑阵收束瞄准)
func _draw_jiansha_elite() -> void:
	var t := _time + _phase_seed
	var float_y := sin(t * 2.8) * 2.2
	var center := Vector2(0, float_y)
	var root_scale_x := -1.0 if flip_h else 1.0
	var charge := clampf(special_state, 0.0, 1.0)
	var casting := special_state > 0.0
	var local_aim := Vector2.RIGHT
	if aim_dir.length_squared() > 0.01:
		local_aim = Vector2(aim_dir.x * root_scale_x, aim_dir.y).normalized()
	var aim_ang := local_aim.angle()

	# 地影
	_draw_soft_shadow(Vector2(0, 16), 15.0, 4.5, 0.5)

	# —— 破碎红袍人形躯（与邪修同语言、更邪气） ——
	# 垂袖（两侧断袖随悬浮摆动）
	var sleeve_sway := sin(t * 3.4) * 1.2
	for i in [-1, 1]:
		var sleeve_pts := PackedVector2Array([
			center + Vector2(float(i) * 6.0, -6.0),
			center + Vector2(float(i) * 12.5, 1.0 + sleeve_sway * float(i)),
			center + Vector2(float(i) * 10.5, 7.0 + sleeve_sway),
			center + Vector2(float(i) * 6.5, 3.0)
		])
		draw_stroked_polygon(sleeve_pts, config.col_primary, _contour_color(), 1.2)
	# 袍身：束领宽摆，下缘锯齿残破
	var cloth_wave := sin(t * 3.0) * 1.0
	var robe_pts := PackedVector2Array([
		center + Vector2(-6.0, -8.0),
		center + Vector2(6.0, -8.0),
		center + Vector2(10.5, 4.0),
		center + Vector2(11.5, 12.0 + cloth_wave),
		center + Vector2(7.5, 9.0),
		center + Vector2(4.0, 13.0 - cloth_wave),
		center + Vector2(0.0, 9.5),
		center + Vector2(-4.5, 13.5 + cloth_wave),
		center + Vector2(-8.0, 9.5),
		center + Vector2(-11.0, 12.0 - cloth_wave),
		center + Vector2(-10.0, 4.0)
	])
	draw_stroked_polygon(robe_pts, config.col_primary, _contour_color(), 1.5)
	# 血煞交领（V 形红滚边）与中缝
	draw_line(center + Vector2(-5.5, -7.5), center + Vector2(0.0, -2.0), config.col_accent, 1.8, true)
	draw_line(center + Vector2(5.5, -7.5), center + Vector2(0.0, -2.0), config.col_accent, 1.8, true)
	draw_line(center + Vector2(0.0, -2.0), center + Vector2(0.0, 9.0), Color(config.col_accent.r, config.col_accent.g, config.col_accent.b, 0.5), 1.2, true)
	# 胸口血煞灵核（蓄力时透亮）
	var core_a := 0.55 + charge * 0.45
	draw_soft_glow(center + Vector2(0, 1.0), 5.0, config.col_glow * Color(1, 1, 1, core_a), 2)
	_circle(center + Vector2(0, 1.0), 1.8, config.col_glow)

	# —— 骨白鬼脸 + 墨黑兜帽 ——
	var head_pos := center + Vector2(0, -12.5)
	# 兜帽（罩在颅顶的残破黑纱）
	var hood_pts := PackedVector2Array([
		head_pos + Vector2(-8.0, 2.0),
		head_pos + Vector2(-6.0, -6.5),
		head_pos + Vector2(0, -9.5),
		head_pos + Vector2(6.0, -6.5),
		head_pos + Vector2(8.0, 2.0),
		head_pos + Vector2(0, -2.5)
	])
	draw_stroked_polygon(hood_pts, config.col_primary, _contour_color(), 1.3)
	# 鬼脸面具（尖下巴，面无表情才冷冽）
	var mask_pts := PackedVector2Array([
		head_pos + Vector2(-6.0, -2.0),
		head_pos + Vector2(-6.5, 2.5),
		head_pos + Vector2(0, 7.5),
		head_pos + Vector2(6.5, 2.5),
		head_pos + Vector2(6.0, -2.0),
		head_pos + Vector2(0, -4.0)
	])
	draw_stroked_polygon(mask_pts, config.col_secondary, config.col_void, 1.4)
	# 面门血裂（额至颊一道邪纹）
	draw_polyline(PackedVector2Array([
		head_pos + Vector2(2.5, -3.0), head_pos + Vector2(1.0, 0.5), head_pos + Vector2(3.0, 4.0)
	]), Color(0.85, 0.15, 0.25, 0.9), 1.2, true)
	# 血煞冷眸（双狭缝，蓄力时更凶）
	draw_sharp_eye(head_pos + Vector2(-3.0, 0.5), 2.4, 1.3, config.col_glow, Color.WHITE)
	draw_sharp_eye(head_pos + Vector2(3.0, 0.5), 2.4, 1.3, config.col_glow, Color.WHITE)

	# —— 剑阵：4 柄血煞剑气环绕体旋，蓄力时收束成扇指向目标 ——
	# 每柄剑双位：轨道位（椭圆环绕，切向）与收束位（沿 aim 方向扇形排开），按 charge 插值
	var spin := t * 1.3
	var sword_n := 4
	# pass 0 = 背侧半环（先画垫底），pass 1 = 身前半环（后画压身）
	for pass_idx in range(2):
		for i in range(sword_n):
			var ang := spin + float(i) * (TAU / float(sword_n))
			if (sin(ang) < 0.0) != (pass_idx == 0):
				continue
			var orbit_pos := center + Vector2(cos(ang), sin(ang) * 0.55) * 13.5
			var orbit_rot := ang + PI * 0.5
			var fan_i := float(i) - float(sword_n - 1) * 0.5
			# 出手后坐（recoil 1→0）期间剑阵保持收束、再弹回环绕
			var converge := maxf(charge, recoil * 0.85)
			var conv_pos := center + local_aim * (8.0 - absf(fan_i) * 1.5) \
				+ Vector2(-local_aim.y, local_aim.x) * fan_i * 5.5
			var conv_rot := aim_ang + fan_i * 0.24
			var sw_pos := orbit_pos.lerp(conv_pos, converge)
			var sw_rot := lerp_angle(orbit_rot, conv_rot, converge)
			var t_sw := Transform2D(sw_rot, sw_pos)
			# 剑光幽芒（蓄力时提亮）
			draw_soft_glow(sw_pos, 6.0, config.col_glow * Color(1, 1, 1, 0.28 + charge * 0.4), 1)
			# 血色剑气剑身（细窄灵剑，不遮人形）
			var sw_pts := PackedVector2Array([
				t_sw * Vector2(-7.5, -1.3),
				t_sw * Vector2(6.0, -0.8),
				t_sw * Vector2(10, 0),
				t_sw * Vector2(6.0, 0.8),
				t_sw * Vector2(-7.5, 1.3)
			])
			draw_stroked_polygon(sw_pts, config.col_accent, config.col_glow, 1.0)
			draw_line(t_sw * Vector2(-4, 0), t_sw * Vector2(8, 0), config.col_secondary, 0.9, true)
			# 主剑（收束扇中央那柄）：器尖标定 + 蓄力读数
			if i == int(sword_n / 2.0):
				var tip := t_sw * Vector2(10, 0)
				weapon_tip_pos = Vector2(tip.x * root_scale_x, tip.y) * (config.scale_factor * ENEMY_GLOBAL_SCALE)
				if casting:
					_circle(tip, 2.4 + charge * 3.0, Color(1.0, 0.90, 0.95, 0.95))
					draw_soft_glow(tip, 14.0 * charge, config.col_glow, 3)
					if charge > 0.35:
						var halo_a := (charge - 0.35) / 0.65
						_arc(tip, 5.0 + charge * 3.2, -PI * 0.7, PI * 0.7, 14,
							Color(1.0, 0.55, 0.65, 0.75 * halo_a), 1.3, true)
					var aim_line_end := tip + local_aim * (24.0 * charge)
					draw_line(tip, aim_line_end, Color(1.0, 0.35, 0.50, 0.75 * charge), 1.8, true)
					draw_circle(aim_line_end, 1.8, Color.WHITE)

## 14. 敌潮魔君 & 心魔魔尊 (BOSS / 魔神君临御空)
## 2026-10-19 强化：层叠肩甲+肩尖骨刺、盔梁面脊、背后魔焰披风飘带（_time 飘动）、
## 身侧魔刃与胸口旋转魔核；final 形态加更深虚空雾场与更冷幽光极光。
## 读招姿态：special_state 0→1 蓄力时魔刃收束指向 aim_dir、魔轮缩紧提速、魔核增亮、
## 上身前倾攒劲；recoil 爆发瞬间刃前探、轮外张、魔核闪白（蓄力/爆发两态可读）。
func _draw_boss(final_boss: bool) -> void:
	var charge := clampf(special_state, 0.0, 1.0)
	var burst := clampf(recoil, 0.0, 1.0)
	var surge := maxf(charge, burst)
	var root_scale_x := -1.0 if flip_h else 1.0
	var local_aim := Vector2.RIGHT
	if aim_dir.length_squared() > 0.01:
		local_aim = Vector2(aim_dir.x * root_scale_x, aim_dir.y).normalized()

	var float_y := sin(_time * 2.2) * 2.8
	# 蓄力前倾攒劲，爆发瞬间前探后坐
	var center := Vector2(charge * 2.2 + burst * 3.0, -4 + float_y)

	# 霸者超大地影（蓄力时压得更实）
	_draw_soft_shadow(Vector2(0, 26), 28.0 + charge * 1.5, 7.5, 0.65)

	# —— final 形态：背后虚空雾场（吞光黑域）+ 外圈冷冽极光细环，魔尊压迫感 ——
	if final_boss:
		var void_r := 30.0 + sin(_time * 1.6) * 1.2
		draw_filled_ellipse(center + Vector2(0, -2), void_r * 0.9, void_r, Color(0.02, 0.015, 0.04, 0.55))
		_arc(center + Vector2(0, -2), void_r, 0, TAU, 32, Color(0.05, 0.03, 0.09, 0.8), 2.2, true)
		_arc(center, void_r + 3.0, _time * 0.5, _time * 0.5 + PI * 1.2, 24, config.col_glow * Color(1, 1, 1, 0.25), 1.2, true)

	# —— 背后魔焰披风飘带：3 缕自肩后拖尾，_time 飘动，蓄力时焰色转亮 ——
	var ribbon_col := config.col_accent * Color(1, 1, 1, 0.55 + charge * 0.3)
	for i in range(3):
		var sway := sin(_time * 2.6 + float(i) * 1.9) * 3.4
		var rib_top := center + Vector2(-float(i) * 7.0 - 4.0, -8)
		var rib_mid := rib_top + Vector2(-sway * 0.6 - 3.0, 12)
		var rib_end := rib_mid + Vector2(-sway, 13)
		draw_polyline(PackedVector2Array([rib_top, rib_mid, rib_end]), ribbon_col, 2.6, true)

	# —— 背后魔轮（普通 4 骨刃环 / 魔尊 8 符文法轮）：蓄力缩紧提速、爆发外张 ——
	var wheel_rot := _time * ((0.6 if not final_boss else 0.8) + charge * 1.6)
	var blade_count := 8 if final_boss else 4
	# final 法轮 32→29.5，与 body_radius+15% 延展预算对齐
	var wheel_radius := (26.0 if not final_boss else 29.5) - charge * 2.5 + burst * 3.0
	draw_soft_glow(center, wheel_radius * 1.1, config.col_glow * Color(1, 1, 1, 0.4 + surge * 0.3), 2)
	_arc(center, wheel_radius * 0.8, 0, TAU, 32, config.col_accent, 2.0, true)

	for i in range(blade_count):
		var ang := wheel_rot + float(i) * (TAU / float(blade_count))
		var b_pos := center + Vector2(cos(ang), sin(ang)) * wheel_radius
		var b_rot := ang + PI * 0.5
		var t_b := Transform2D(b_rot, b_pos)
		var b_pts := PackedVector2Array([
			t_b * Vector2(-3, -7),
			t_b * Vector2(0, -14), # 尖刃
			t_b * Vector2(3, -7),
			t_b * Vector2(0, 0)
		])
		draw_stroked_polygon(b_pts, config.col_secondary, config.col_glow, 1.6)
		# 蓄力时刃根符点亮环（读数：法轮在聚能）
		if charge > 0.35 and i % 2 == 0:
			_circle(b_pos, 1.3 * charge, config.col_glow)

	# —— 身侧魔刃（法器）：巡航斜悬，蓄力收束指向目标，爆发前探斩出 ——
	var blade_pos := center + Vector2(-12.0, 6.0)
	var blade_rot := deg_to_rad(210.0)
	if charge > 0.0 or burst > 0.001:
		blade_rot = local_aim.angle()
		blade_pos = center + Vector2(4, -2) + local_aim * (burst * 9.0 - charge * 6.0)
	var t_blade := Transform2D(blade_rot, blade_pos)
	draw_soft_glow(blade_pos, 13.0 + surge * 7.0, config.col_glow * Color(1, 1, 1, 0.3 + surge * 0.45), 2)
	var blade_pts := PackedVector2Array([
		t_blade * Vector2(-14, -3),
		t_blade * Vector2(15, -1.8),
		t_blade * Vector2(21, 0), # 刃尖
		t_blade * Vector2(15, 1.8),
		t_blade * Vector2(-14, 3),
	])
	draw_stroked_polygon(blade_pts, config.col_secondary, config.col_glow, 1.5)
	# 刃脊血槽与护格
	draw_line(t_blade * Vector2(-10, 0), t_blade * Vector2(17, 0), config.col_glow, 1.2, true)
	draw_line(t_blade * Vector2(-10, -5), t_blade * Vector2(-10, 5), config.col_accent, 2.2, true)

	# 威严魔王重铠身躯与魔袍四摆
	var armor_pts := PackedVector2Array([
		center + Vector2(-16, 20),
		center + Vector2(-19, -6),
		center + Vector2(-10, -18),
		center + Vector2(10, -18),
		center + Vector2(19, -6),
		center + Vector2(16, 20),
		center + Vector2(0, 15)
	])
	draw_stroked_polygon(armor_pts, config.col_primary, _contour_color(), 1.6)
	# 腹甲三段刻线（重铠层次）
	for i in range(3):
		var ab_y := 2.0 + float(i) * 5.0
		draw_line(center + Vector2(-14.0 + float(i) * 1.5, ab_y), center + Vector2(14.0 - float(i) * 1.5, ab_y), config.col_accent * Color(1, 1, 1, 0.55), 1.2, true)

	# —— 层叠肩甲：玄铁面 + 骨白缘 + 肩尖骨刺（外接圆在 body_radius 预算内）——
	for s in [-1.0, 1.0]:
		var pauld_pts := PackedVector2Array([
			center + Vector2(s * 13, -16),
			center + Vector2(s * 21, -11),
			center + Vector2(s * 20, -2),
			center + Vector2(s * 12, -6),
		])
		draw_stroked_polygon(pauld_pts, config.col_primary, _contour_color(), 1.5)
		draw_line(center + Vector2(s * 12.8, -15), center + Vector2(s * 20.2, -10.3), config.col_secondary, 1.3, true)
		draw_polyline(PackedVector2Array([center + Vector2(s * 20.0, -8), center + Vector2(s * 25.5, -13.5)]), config.col_secondary, 2.0, true)
		_circle(center + Vector2(s * 16.5, -8), 1.0, config.col_secondary)

	# —— 胸口旋转魔核：虚空晶壳 + 菱形核体，随蓄力/爆发增亮提速 ——
	var core_rot := _time * (1.0 + surge * 3.2)
	var core_r := 6.2 + surge * 2.2
	draw_soft_glow(center, 9.0 + surge * 10.0, config.col_glow * Color(1, 1, 1, 0.5 + surge * 0.4), 3)
	draw_filled_ellipse(center, core_r * 1.18, core_r, config.col_void)
	var core_pts := PackedVector2Array([
		center + Vector2(cos(core_rot), sin(core_rot)) * core_r,
		center + Vector2(cos(core_rot + PI * 0.5), sin(core_rot + PI * 0.5)) * core_r * 0.72,
		center + Vector2(cos(core_rot + PI), sin(core_rot + PI)) * core_r,
		center + Vector2(cos(core_rot + PI * 1.5), sin(core_rot + PI * 1.5)) * core_r * 0.72,
	])
	draw_stroked_polygon(core_pts, config.col_glow.lightened(surge * 0.5), config.col_void, 1.2)
	_circle(center, 1.6 + surge * 1.4, Color(1.0, 1.0, 1.0, 0.85 + surge * 0.15))

	# 鬼王骨面（盔梁中脊 + 面门血槽）与冲天魔角（心魔魔尊带九幽分叉魔冠）
	var head_pos := center + Vector2(0, -18)
	var mask_pts := PackedVector2Array([
		head_pos + Vector2(-9, 7),
		head_pos + Vector2(-11, -5),
		head_pos + Vector2(0, -13),
		head_pos + Vector2(11, -5),
		head_pos + Vector2(9, 7),
		head_pos + Vector2(0, 11)
	])
	draw_stroked_polygon(mask_pts, config.col_secondary, config.col_void, 1.5)
	# 盔梁中脊与颊侧护板线（骨面分块，冷冽甲胄感）
	draw_line(head_pos + Vector2(0, -12.5), head_pos + Vector2(0, 10), config.col_void, 1.4, true)
	draw_line(head_pos + Vector2(-8.5, -3), head_pos + Vector2(-6.5, 6), config.col_void, 1.0, true)
	draw_line(head_pos + Vector2(8.5, -3), head_pos + Vector2(6.5, 6), config.col_void, 1.0, true)

	# 巨大魔角（角根护甲块）
	draw_polyline(PackedVector2Array([
		head_pos + Vector2(-6, -6),
		head_pos + Vector2(-14, -18),
		head_pos + Vector2(-11, -25)
	]), config.col_secondary, 2.4, true)
	draw_polyline(PackedVector2Array([
		head_pos + Vector2(6, -6),
		head_pos + Vector2(14, -18),
		head_pos + Vector2(11, -25)
	]), config.col_secondary, 2.4, true)
	_circle(head_pos + Vector2(-6.5, -7), 1.6, config.col_void)
	_circle(head_pos + Vector2(6.5, -7), 1.6, config.col_void)

	if final_boss:
		# 皇冠分叉中央角 + 两侧小分叉（魔冠更盛）
		draw_polyline(PackedVector2Array([
			head_pos + Vector2(-3, -11),
			head_pos + Vector2(0, -22),
			head_pos + Vector2(3, -11)
		]), config.col_accent, 1.8, true)
		draw_line(head_pos + Vector2(-12.5, -19.5), head_pos + Vector2(-16.0, -23.0), config.col_accent, 1.4, true)
		draw_line(head_pos + Vector2(12.5, -19.5), head_pos + Vector2(16.0, -23.0), config.col_accent, 1.4, true)

	# 燃烧神魔双目（蓄力/爆发时瞳焰提亮）
	var eye_col := config.col_glow.lightened(surge * 0.45)
	draw_sharp_eye(head_pos + Vector2(-4, 0), 4.2, 2.0, eye_col, Color.WHITE)
	draw_sharp_eye(head_pos + Vector2(4, 0), 4.2, 2.0, eye_col, Color.WHITE)

## 15. 灵医：青囊药灵 (荷叶帽药童灵，背葫举杵周期性施治)
func _draw_lingyi() -> void:
	var t := _time + _phase_seed
	var float_y := sin(t * 3.0) * 2.0
	var center := Vector2(0, -4 + float_y)
	# 治疗脉冲周期（3.6s 一轮）：前 1.2s 举杵发光施治，其余待机
	var cyc := fposmod(t, 3.6)
	var lift := sin(cyc / 1.2 * PI) if cyc < 1.2 else 0.0

	# 地影
	_draw_soft_shadow(Vector2(0, 15), 12.0, 3.6, 0.4)

	# —— 肩后药葫芦：双肚葫芦随施治节拍摇动，口泛治疗青光 ——
	var gourd_c := center + Vector2(-10.0, -5.0 + sin(t * 9.0) * 1.2 * lift)
	draw_filled_ellipse(gourd_c + Vector2(0, 3.0), 3.6, 4.0, config.col_secondary) # 大肚
	draw_filled_ellipse(gourd_c + Vector2(0.8, -2.2), 2.2, 2.4, config.col_secondary) # 小肚
	draw_line(gourd_c + Vector2(1.4, -4.2), gourd_c + Vector2(2.2, -6.4), config.col_accent, 1.6, true) # 葫芦口颈
	if lift > 0.15:
		draw_soft_glow(gourd_c + Vector2(2.2, -6.4), 5.0 * lift, config.col_glow, 2)
	# 系葫斜绦（跨胸束带）
	draw_line(gourd_c + Vector2(1.0, 0.0), center + Vector2(6.0, -5.5), config.col_accent, 1.2, true)

	# —— 药童袍躯：窄肩宽摆，下缘荷叶式飘摆 ——
	var hem := sin(t * 3.4) * 1.2
	var robe_pts := PackedVector2Array([
		center + Vector2(-6.0, -7.0),
		center + Vector2(6.0, -7.0),
		center + Vector2(9.5, 6.0),
		center + Vector2(10.5, 13.0 + hem),
		center + Vector2(5.0, 11.0),
		center + Vector2(0.0, 14.0 - hem),
		center + Vector2(-5.0, 11.0),
		center + Vector2(-10.0, 13.0 + hem),
		center + Vector2(-9.0, 6.0)
	])
	draw_stroked_polygon(robe_pts, config.col_primary, _contour_color(), 1.4)
	# 袍前十字徽记（月白绷带布条）
	draw_line(center + Vector2(-3.5, 0.0), center + Vector2(3.5, 0.0), config.col_secondary, 2.2, true)
	draw_line(center + Vector2(0.0, -3.5), center + Vector2(0.0, 3.5), config.col_secondary, 2.2, true)

	# —— 右侧垂袖持杵：施治节拍把捣药杵高高举起 ——
	var hand := center + Vector2(9.0, -1.0 - lift * 7.0)
	var sleeve_pts := PackedVector2Array([
		center + Vector2(5.5, -6.0),
		hand + Vector2(-1.0, -2.5),
		hand + Vector2(2.0, 1.0),
		center + Vector2(8.5, 2.0)
	])
	draw_stroked_polygon(sleeve_pts, config.col_primary, _contour_color(), 1.2)
	# 捣药杵（骨白杵杆，尖朝上）
	var pestle_top := hand + Vector2(1.5, -8.0 - lift * 2.0)
	draw_line(hand + Vector2(0.5, 2.0), pestle_top, config.col_secondary, 2.6, true)
	_circle(pestle_top, 1.8, config.col_secondary)
	if lift > 0.15:
		# 杵尖治疗青光 + 升腾回春光粒
		draw_soft_glow(pestle_top, 7.0 * lift, config.col_glow, 2)
		for i in range(3):
			var rise := fposmod(t * 2.2 + float(i) * 0.33, 1.0)
			_circle(pestle_top + Vector2(sin(rise * TAU + float(i)) * 3.0, -rise * 9.0),
				1.2 * (1.0 - rise) * lift,
				Color(config.col_glow.r, config.col_glow.g, config.col_glow.b, lift * (1.0 - rise)))

	# —— 头面：墨黑虚面无机圆眸（先画脸，帽压顶） ——
	var head_pos := center + Vector2(0, -11.0)
	draw_filled_ellipse(head_pos, 5.0, 4.5, config.col_void)
	_circle(head_pos + Vector2(-2.0, 0), 1.5, config.col_glow)
	_circle(head_pos + Vector2(2.0, 0), 1.5, config.col_glow)
	# 荷叶帽：宽大叶盘微微前倾 + 叶脉
	var leaf_pts := PackedVector2Array([
		head_pos + Vector2(-10.5, -3.0),
		head_pos + Vector2(-4.0, -6.5),
		head_pos + Vector2(0, -8.5),
		head_pos + Vector2(4.0, -6.5),
		head_pos + Vector2(10.5, -3.0),
		head_pos + Vector2(0, -1.5)
	])
	draw_stroked_polygon(leaf_pts, config.col_accent, _contour_color(), 1.3)
	draw_line(head_pos + Vector2(0, -8.0), head_pos + Vector2(-6.0, -3.2), config.col_primary, 0.8, true)
	draw_line(head_pos + Vector2(0, -8.0), head_pos + Vector2(6.0, -3.2), config.col_primary, 0.8, true)
	draw_line(head_pos + Vector2(0, -8.0), head_pos + Vector2(0, -2.0), config.col_primary, 0.8, true)
	# 系帽颍带
	draw_line(head_pos + Vector2(-4.5, -2.0), head_pos + Vector2(-2.5, 4.0), config.col_secondary, 0.8, true)
	draw_line(head_pos + Vector2(4.5, -2.0), head_pos + Vector2(2.5, 4.0), config.col_secondary, 0.8, true)

## 16. 金蟾：衔宝金蟾 (胖圆宝兽，口衔铜钱)
func _draw_jinchan() -> void:
	var float_y := sin(_time * 4.0) * 2.4
	var hop := absf(sin(_time * 4.0)) * (1.0 + speed_ratio * 0.6)
	var center := Vector2(0, -2 + float_y - hop * 2.0)

	# 地影随跳跃缩放
	var shadow_w := 14.0 - hop * 3.0
	_draw_soft_shadow(Vector2(0, 15), shadow_w, 4.0, 0.4)

	# 宝气金光罩
	draw_soft_glow(center, 18.0, config.col_glow * Color(1, 1, 1, 0.4), 2)

	# 胖圆蟾躯与腹甲
	draw_filled_ellipse(center, 13.5, 11.0, config.col_primary)
	draw_filled_ellipse(center + Vector2(0, 3), 8.5, 6.0, config.col_secondary)
	_arc(center, 13.5, 0, TAU, 26, _contour_color(), 1.4, true)

	# 背后三枚古铜钱纹（方孔钱）
	for i in range(3):
		var c_pos := center + Vector2(float(i - 1) * 7.0, -6.0)
		_circle(c_pos, 3.0, config.col_accent)
		draw_rect(Rect2(c_pos - Vector2(1.0, 1.0), Vector2(2.0, 2.0)), config.col_primary)

	# 口衔大宝钱（身份标识：会转动的方孔金币）
	var coin_pos := center + Vector2(0, 5.5)
	var coin_squish := 0.55 + absf(sin(_time * 2.2)) * 0.45
	draw_filled_ellipse(coin_pos, 5.0, 5.0 * coin_squish, config.col_glow)
	draw_rect(Rect2(coin_pos - Vector2(1.4, 1.4 * coin_squish), Vector2(2.8, 2.8 * coin_squish)), config.col_primary)

	# 圆润鼓眼
	# 2026-10-23 视线：瞳光在金蟾大眼球里偏移，读作「它在盯着我的金币跑」
	var head_pos := center + Vector2(0, -7)
	_circle(head_pos + Vector2(-4, 0), 2.6, config.col_void)
	_circle(head_pos + Vector2(4, 0), 2.6, config.col_void)
	_circle(head_pos + Vector2(-4, -0.5) + _gaze_offset(1.1), 1.1, config.col_glow)
	_circle(head_pos + Vector2(4, -0.5) + _gaze_offset(1.1), 1.1, config.col_glow)

## 17. 寒魄妖 (九幽霜魄，三发弧线冰魄，死后溅射)
func _draw_hanpo() -> void:
	var float_y := sin(_time * 2.6 + _phase_seed) * 2.2
	var center := Vector2(0, -3 + float_y)
	var surge := clampf(special_state, 0.0, 1.0)

	# 地影
	_draw_soft_shadow(Vector2(0, 15), 13.0, 3.8, 0.42, Color(0.04, 0.08, 0.12))

	# 环绕三枚浮空玄冰魄晶（施法时外扩提亮）
	var orbit_r := 15.0 + surge * 4.0
	var orbit_rot := _time * 2.5
	for i in range(3):
		var a := orbit_rot + TAU * float(i) / 3.0
		var p_crystal := center + Vector2(cos(a), sin(a)) * orbit_r
		var shard_pts := PackedVector2Array([
			p_crystal + Vector2(0, -3.8),
			p_crystal + Vector2(2.0, 0),
			p_crystal + Vector2(0, 3.8),
			p_crystal + Vector2(-2.0, 0)
		])
		draw_stroked_polygon(shard_pts, config.col_secondary, config.col_accent, 1.0)
		_circle(p_crystal, 1.0, config.col_glow)

	# 冰晶道袍躯壳
	var hem := sin(_time * 3.0) * 1.5
	var robe_pts := PackedVector2Array([
		center + Vector2(-7.5, -6.0),
		center + Vector2(7.5, -6.0),
		center + Vector2(10.0, 5.0),
		center + Vector2(11.0, 12.0 + hem),
		center + Vector2(0.0, 14.0 - hem * 0.5),
		center + Vector2(-11.0, 12.0 - hem),
		center + Vector2(-10.0, 5.0)
	])
	draw_stroked_polygon(robe_pts, config.col_primary, _contour_color(), 1.3)
	# 胸前菱形霜核
	var core_pts := PackedVector2Array([
		center + Vector2(0, -2.0),
		center + Vector2(3.5, 2.0),
		center + Vector2(0, 6.0),
		center + Vector2(-3.5, 2.0)
	])
	draw_colored_polygon(core_pts, config.col_glow)

	# 苍白霜面与极寒双瞳
	var head_pos := center + Vector2(0, -9.0)
	draw_filled_ellipse(head_pos, 5.2, 4.8, config.col_void)
	_circle(head_pos + Vector2(-2.2, -0.5), 1.4, config.col_glow)
	_circle(head_pos + Vector2(2.2, -0.5), 1.4, config.col_glow)
	# 极寒双角
	draw_line(head_pos + Vector2(-3.5, -3.0), head_pos + Vector2(-6.5, -8.0), config.col_secondary, 1.6, true)
	draw_line(head_pos + Vector2(3.5, -3.0), head_pos + Vector2(6.5, -8.0), config.col_secondary, 1.6, true)

## 18. 血煞魔卫 (重装重铠魔卫，持巨骨重盾，冲撞+震地)
func _draw_mowei() -> void:
	var charge := clampf(special_state, 0.0, 1.0)
	var float_y := sin(_time * 2.2 + _phase_seed) * 1.5 - charge * 3.5
	var center := Vector2(0, -2 + float_y)

	# 厚重地影
	_draw_soft_shadow(Vector2(0, 17), 18.0 - charge * 2.0, 5.0, 0.55)

	# 重装血煞胸甲
	var plate_pts := PackedVector2Array([
		center + Vector2(-11.0, 9.0),
		center + Vector2(-13.0, -3.0),
		center + Vector2(0.0, -10.0),
		center + Vector2(13.0, -3.0),
		center + Vector2(11.0, 9.0),
		center + Vector2(0.0, 12.0)
	])
	draw_stroked_polygon(plate_pts, config.col_primary, _contour_color(), 1.6)

	# 胸铠血槽纹路
	draw_line(center + Vector2(0, -8), center + Vector2(0, 9), config.col_accent, 1.6, true)
	draw_line(center + Vector2(-9, -1), center + Vector2(-3, 6), config.col_accent, 1.2, true)
	draw_line(center + Vector2(9, -1), center + Vector2(3, 6), config.col_accent, 1.2, true)

	# 左侧巨盾（厚实骨铁塔盾，带血煞尖刺）
	var shield_x := -13.0 if not flip_h else 13.0
	var shield_pos := center + Vector2(shield_x, 2.0 - charge * 2.0)
	var shield_pts := PackedVector2Array([
		shield_pos + Vector2(-4.0, -11.0),
		shield_pos + Vector2(4.0, -11.0),
		shield_pos + Vector2(5.0, 6.0),
		shield_pos + Vector2(0.0, 12.0),
		shield_pos + Vector2(-5.0, 6.0)
	])
	draw_stroked_polygon(shield_pts, config.col_secondary, _contour_color(), 1.5)
	# 盾面血煞符印
	draw_circle(shield_pos + Vector2(0, 0), 2.2, config.col_glow)

	# 恶鬼骨面与血瞳
	var head_pos := center + Vector2(0, -8.0)
	draw_filled_ellipse(head_pos, 5.5, 5.0, config.col_void)
	_circle(head_pos + Vector2(-2.2, 0), 1.5, config.col_glow)
	_circle(head_pos + Vector2(2.2, 0), 1.5, config.col_glow)
	# 冲天鬼角
	draw_line(head_pos + Vector2(-3.5, -3.0), head_pos + Vector2(-7.5, -9.5), config.col_secondary, 2.0, true)
	draw_line(head_pos + Vector2(3.5, -3.0), head_pos + Vector2(7.5, -9.5), config.col_secondary, 2.0, true)

## 19. 玄冥魔尊 (精英：幽冥玄煞，旋臂冥雷环+落石大阵+瞬身回斩)
func _draw_xuanming_elite() -> void:
	var charge := clampf(special_state, 0.0, 1.0)
	var float_y := sin(_time * 2.0 + _phase_seed) * 2.0 - charge * 4.0
	var center := Vector2(0, -3 + float_y)

	# 庞大精英地影
	_draw_soft_shadow(Vector2(0, 20), 24.0, 6.5, 0.60)

	# 背部幽冥法轮环（缓慢自转 + 狂暴时加速）
	var ring_rot := _time * (0.8 + charge * 1.5)
	var ring_r := 23.0
	_arc(center + Vector2(0, -4), ring_r, 0.0, TAU, 32, config.col_accent * Color(1, 1, 1, 0.55), 1.5, true)
	for k in range(8):
		var a := ring_rot + TAU * float(k) / 8.0
		var orb_pos := center + Vector2(0, -4) + Vector2(cos(a), sin(a)) * ring_r
		_circle(orb_pos, 1.8, config.col_glow)

	# 玄冥魔神墨袍与重肩甲
	var robe_pts := PackedVector2Array([
		center + Vector2(-15.0, -6.0),
		center + Vector2(-12.0, -11.0),
		center + Vector2(0.0, -14.0),
		center + Vector2(12.0, -11.0),
		center + Vector2(15.0, -6.0),
		center + Vector2(17.0, 10.0),
		center + Vector2(11.0, 16.0),
		center + Vector2(0.0, 14.0),
		center + Vector2(-11.0, 16.0),
		center + Vector2(-17.0, 10.0)
	])
	draw_stroked_polygon(robe_pts, config.col_primary, _contour_color(), 1.6)

	# 肩部玄铁骨刺
	draw_line(center + Vector2(-14, -8), center + Vector2(-20, -15), config.col_secondary, 2.4, true)
	draw_line(center + Vector2(14, -8), center + Vector2(20, -15), config.col_secondary, 2.4, true)

	# 胸口玄冥炉心
	draw_soft_glow(center + Vector2(0, 1), 14.0, config.col_glow * Color(1, 1, 1, 0.6 + charge * 0.4), 2)
	_circle(center + Vector2(0, 1), 3.2, config.col_secondary)

	# 冥神鬼冠头面
	var head_pos := center + Vector2(0, -11.0)
	draw_filled_ellipse(head_pos, 6.2, 5.5, config.col_void)
	_circle(head_pos + Vector2(-2.8, -0.5), 1.8, config.col_glow)
	_circle(head_pos + Vector2(2.8, -0.5), 1.8, config.col_glow)
	# 冲天骨冠
	draw_polyline(PackedVector2Array([
		head_pos + Vector2(-4.0, -4.5),
		head_pos + Vector2(0.0, -12.0),
		head_pos + Vector2(4.0, -4.5)
	]), config.col_secondary, 1.8, true)

## 20. 玄天星盘 (精英：静止弹幕炮台，双层逆向星刻环+四角镇物棱晶+璀璨星核)
func _draw_xingpan_elite() -> void:
	var charge := clampf(special_state, 0.0, 1.0)
	var burst := clampf(recoil, 0.0, 1.0)
	var center := Vector2(0, -2)

	# 坚实沉重的大型地影（不动如山）
	_draw_soft_shadow(Vector2(0, 18), 24.0, 6.0, 0.65)

	# 1. 八角玄天星盘底座（八边形厚甲盘）
	var base_pts := PackedVector2Array()
	var base_r := 21.0
	for i in range(8):
		var ang := float(i) * TAU / 8.0 + PI / 8.0
		base_pts.append(center + Vector2(cos(ang), sin(ang)) * base_r)
	draw_stroked_polygon(base_pts, config.col_primary, _contour_color(), 1.8)

	# 八角内衬金错纹路
	var inner_pts := PackedVector2Array()
	var inner_r := 16.5
	for i in range(8):
		var ang := float(i) * TAU / 8.0 + PI / 8.0
		inner_pts.append(center + Vector2(cos(ang), sin(ang)) * inner_r)
	draw_polyline(inner_pts, config.col_accent * Color(1, 1, 1, 0.65), 1.2, true)
	if inner_pts.size() > 0:
		draw_line(inner_pts[inner_pts.size() - 1], inner_pts[0], config.col_accent * Color(1, 1, 1, 0.65), 1.2, true)

	# 2. 正反双层旋转刻度环
	# 外层顺时针旋转刻度环（蓄力时收束提速）
	var rot_speed_outer := (0.6 + charge * 2.2)
	var rot_outer := _time * rot_speed_outer
	var ring_outer_r := 18.0 - charge * 2.0 + burst * 2.5
	_arc(center, ring_outer_r, 0.0, TAU, 32, config.col_secondary * Color(1, 1, 1, 0.75), 1.6, true)
	for k in range(8):
		var a := rot_outer + TAU * float(k) / 8.0
		var pt := center + Vector2(cos(a), sin(a)) * ring_outer_r
		_circle(pt, 1.4, config.col_glow)

	# 内层逆时针旋转符文环
	var rot_speed_inner := -(0.8 + charge * 2.5)
	var rot_inner := _time * rot_speed_inner
	var ring_inner_r := 12.0 - charge * 1.5
	_arc(center, ring_inner_r, 0.0, TAU, 28, config.col_accent, 1.4, true)
	for k in range(4):
		var a := rot_inner + TAU * float(k) / 4.0
		var p1 := center + Vector2(cos(a), sin(a)) * (ring_inner_r - 2.0)
		var p2 := center + Vector2(cos(a), sin(a)) * (ring_inner_r + 2.0)
		draw_line(p1, p2, config.col_glow, 1.5, true)

	# 3. 四角悬浮镇物棱晶（随时间微浮，向外伸展）
	var crystal_dist := 22.0 + sin(_time * 2.4) * 1.2 + charge * 2.0
	for k in range(4):
		var a := float(k) * TAU / 4.0 + PI / 4.0
		var c_pos := center + Vector2(cos(a), sin(a)) * crystal_dist
		var dir := Vector2(cos(a), sin(a))
		var norm := Vector2(-dir.y, dir.x)
		var cry_pts := PackedVector2Array([
			c_pos + dir * 4.5,
			c_pos + norm * 2.2,
			c_pos - dir * 2.5,
			c_pos - norm * 2.2
		])
		draw_stroked_polygon(cry_pts, config.col_secondary, config.col_glow, 1.2)
		draw_line(center + Vector2(cos(a), sin(a)) * inner_r, c_pos - dir * 2.0, config.col_accent * Color(1, 1, 1, 0.45), 1.0, true)

	# 4. 中央璀璨星核阵眼（极光辉光，蓄力时爆亮）
	var glow_r := 12.0 + charge * 8.0 + burst * 6.0
	var glow_alpha := 0.6 + charge * 0.4
	draw_soft_glow(center, glow_r, config.col_glow * Color(1, 1, 1, glow_alpha), 2)
	_circle(center, 4.8 + charge * 1.2, config.col_void)
	_circle(center, 3.2 + charge * 0.8, config.col_glow)
	_circle(center, 1.5, Color(1.0, 1.0, 1.0, 0.95))

## 21. 万毒祭司 (精英：南荒九幽万毒祭司，墨绿蛊袍+双角蛊骨冠+三方环绕毒香炉)
func _draw_wandu_elite() -> void:
	var charge := clampf(special_state, 0.0, 1.0)
	var float_y := sin(_time * 2.2 + _phase_seed) * 2.2 - charge * 3.0
	var center := Vector2(0, -4 + float_y)

	# 悬浮地影
	_draw_soft_shadow(Vector2(0, 19), 20.0, 5.5, 0.55)

	# 1. 祭司周身环绕飘浮的 3 枚碧绿毒香炉 / 蛊火宝珠
	var orb_rot := _time * (1.2 + charge * 1.8)
	var orb_dist := 21.0 + sin(_time * 2.8) * 1.5 + charge * 4.0
	for k in range(3):
		var a := orb_rot + TAU * float(k) / 3.0
		var orb_pos := center + Vector2(cos(a) * orb_dist, sin(a) * (orb_dist * 0.65) - 2.0)
		draw_soft_glow(orb_pos, 8.0 + charge * 4.0, config.col_glow * Color(1, 1, 1, 0.55), 2)
		_circle(orb_pos, 3.0, config.col_primary)
		_circle(orb_pos, 2.0, config.col_glow)
		_circle(orb_pos, 1.0, Color(0.9, 1.0, 0.85, 0.95))
		var smoke_end := orb_pos + Vector2(sin(_time * 3.5 + float(k)) * 3.0, -6.0)
		draw_line(orb_pos, smoke_end, config.col_accent * Color(1, 1, 1, 0.5), 1.2, true)

	# 2. 墨绿巫蛊祭袍躯干
	var robe_pts := PackedVector2Array([
		center + Vector2(-12.0, -8.0),
		center + Vector2(-9.0, -13.0),
		center + Vector2(0.0, -15.0),
		center + Vector2(9.0, -13.0),
		center + Vector2(12.0, -8.0),
		center + Vector2(14.0, 8.0),
		center + Vector2(9.0, 16.0),
		center + Vector2(0.0, 13.0),
		center + Vector2(-9.0, 16.0),
		center + Vector2(-14.0, 8.0)
	])
	draw_stroked_polygon(robe_pts, config.col_primary, _contour_color(), 1.6)

	# 祭袍两侧垂挂的翠毒妖纹破布条
	draw_line(center + Vector2(-10.0, 10.0), center + Vector2(-12.0, 20.0), config.col_accent, 1.8, true)
	draw_line(center + Vector2(10.0, 10.0), center + Vector2(12.0, 20.0), config.col_accent, 1.8, true)

	# 3. 胸口幽绿蛊阵印记
	draw_soft_glow(center + Vector2(0, 0), 11.0, config.col_glow * Color(1, 1, 1, 0.5 + charge * 0.4), 2)
	for k in range(3):
		var a := float(k) * TAU / 3.0 - PI / 2.0
		var rune_p := center + Vector2(0, 0) + Vector2(cos(a), sin(a)) * 3.6
		draw_line(center + Vector2(0, 0), rune_p, config.col_accent, 1.5, true)
	_circle(center + Vector2(0, 0), 2.0, config.col_glow)

	# 4. 惨白蛊骨冠与头面
	var head_pos := center + Vector2(0, -12.0)
	draw_filled_ellipse(head_pos, 5.5, 5.0, config.col_void)
	var horn_l := PackedVector2Array([
		head_pos + Vector2(-3.0, -3.0),
		head_pos + Vector2(-7.5, -8.0),
		head_pos + Vector2(-11.0, -14.0),
		head_pos + Vector2(-8.5, -13.0),
		head_pos + Vector2(-5.0, -6.0)
	])
	var horn_r := PackedVector2Array([
		head_pos + Vector2(3.0, -3.0),
		head_pos + Vector2(7.5, -8.0),
		head_pos + Vector2(11.0, -14.0),
		head_pos + Vector2(8.5, -13.0),
		head_pos + Vector2(5.0, -6.0)
	])
	draw_stroked_polygon(horn_l, config.col_secondary, _contour_color(), 1.2)
	draw_stroked_polygon(horn_r, config.col_secondary, _contour_color(), 1.2)

	# 狭长幽绿蛊瞳（带视线锁敌偏移）
	var pupil_shift := _local_aim_cache * 1.0
	_circle(head_pos + Vector2(-2.2, 0.0) + pupil_shift, 1.4, config.col_glow)
	_circle(head_pos + Vector2(2.2, 0.0) + pupil_shift, 1.4, config.col_glow)
