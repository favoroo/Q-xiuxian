class_name HollowKnightEnemyRenderer
extends Node2D

## 敌人空洞冷冽国风程序化矢量渲染器
## 纯 GDScript CanvasItem 矢量绘制，涵盖悬浮、飞行、爬行波三大流体非复杂动作，
## 为全 14 种敌种提供高反差、骨面、虚空、灵核辉光的高辨识度妖魔拟态。

@export var config: EnemyVisualConfig:
	set(val):
		config = val
		if config != null:
			# 精英/Boss 数量少、动作分量重，保持每帧重绘；普通怪走档位化节流
			_is_mob = not config.is_elite and not config.is_boss
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
var gait_phase: float = 0.0
var special_state: float = 0.0  ## 特殊机制状态（丹爆引信/雷兽蓄力/Boss强化等）

var _time: float = 0.0

# —— 重绘节流（2026-10-10 性能优化）——
## 全量 _draw 每只怪一次重建几十条矢量指令，35 敌同屏就是每帧几千条，
## 是「敌人一多就卡」的头号热点。处理：普通怪降频 20Hz 重绘（本来是 10fps 帧动画风格，
## 20fps 矢量动画无感），精英/Boss 数量少保持每帧；每实例随机错相把重绘摊到不同帧
## 避免「每 N 帧一次尖峰」；屏外直接跳过重绘（_time 照常推进，回屏即恢复）。
## 60fps 档（2026-10-15 VisualRate 档位联动）：普通怪步进随物理 60Hz 翻倍，
## 20Hz 画面会露台阶，提到 30Hz；低档 20Hz 是 perf_probe 钉住的预算口径。
const HZ_MOB_LOW := 20.0            ## 省电档普通怪重绘频率
const HZ_MOB_HIGH := 30.0           ## 流畅档普通怪重绘频率
const CULL_MARGIN := 64.0           ## 屏外剔除余量（px），防半身出屏闪烁
static var redraw_count: int = 0    ## 重绘发放计数（tests/PerfProbe 断言用）

var _draw_phase: float = 0.0        ## 距下次重绘的剩余时间（错相载体）
## 普通怪 = 节流重绘；精英/Boss = 每帧（0 间隔）。默认节流（config 未赋值前与旧口径一致）
var _is_mob: bool = true
var _offscreen: bool = false
var _dirty: bool = false            ## 状态翻转（镜像/换装）时插队重绘
## 屏外剔除变换缓存：全屏敌人共享同一个 canvas_transform + visible_rect，
## 每帧只查一次引擎接口（get_viewport / get_canvas_transform / get_visible_rect），
## 避免每敌每渲染帧 3 次冗余调用。
static var _cull_frame: int = -1
static var _cull_transform: Transform2D
static var _cull_limit: Vector2
static var _cull_valid: bool = false

## 本实例的重绘间隔：精英/Boss 每帧（0），普通怪按帧率档位节流
func _redraw_interval() -> float:
	if not _is_mob:
		return 0.0
	return VisualRate.interval(HZ_MOB_HIGH, HZ_MOB_LOW)

func _ready() -> void:
	# 错相：用 instance_id 派生初值（不碰玩法随机），把 35 只怪的重绘摊到不同帧，
	# 避免「每 N 帧一次集中重绘尖峰」把节流收益吃掉
	_draw_phase = fposmod(float(get_instance_id() % 97) * 0.001, _redraw_interval())

func _process(delta: float) -> void:
	_time += delta
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

	# 全局朝向水平镜像处理
	var root_scale_x := -1.0 if flip_h else 1.0
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(root_scale_x, 1.0) * config.scale_factor)

	# 精英/魔君常驻识别环（2026-10-14 P2）：贴地呼吸骨环，满屏时一眼分出「这只厚」。
	# 画在各敌种函数之前（垫底贴地层），所有敌型一次覆盖；Boss 用更宽的朱砂双环。
	if config.is_boss or config.is_elite:
		var ring_r := config.body_radius + 8.0
		var ring_pulse := sin(_time * 2.4) * 0.06 + 0.94
		if config.is_boss:
			var boss_col := Color(0.85, 0.22, 0.28, 0.55 * ring_pulse)
			_arc(Vector2(0, 15), ring_r + 3.0, 0.0, TAU, 40, boss_col, 3.2, true)
			_arc(Vector2(0, 15), ring_r * 0.8, 0.0, TAU, 40, Color(boss_col.r, boss_col.g, boss_col.b, 0.30), 1.4, true)
		else:
			var elite_col := Color(0.92, 0.86, 0.70, 0.50 * ring_pulse)
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
		"boss":
			_draw_boss(config.is_final_boss)
		_:
			if config.is_boss:
				_draw_boss(config.is_final_boss)
			elif config.is_elite:
				_draw_golem()
			else:
				_draw_slime()

# ==================== 1. 基础几何与空洞风图元绘制工具 ====================

## 自适应圆/弧段数（2026-10-14 性能优化）：内置 draw_circle 固定 64 段，
## 小至 1px 的眸光点也付 64 三角形的钱；本渲染器的 draw_circle/draw_arc 统一走这两个包装，
## 按半径与弧角张量自适应 6~32 段。静态缓冲复用，_draw 在主线程串行执行，无重入风险。
static var _circle_buf := PackedVector2Array()
static var _stroke_buf := PackedVector2Array()

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

func draw_stroked_polygon(pts: PackedVector2Array, fill_col: Color, stroke_col: Color, stroke_w: float = 1.8) -> void:
	if pts.size() < 3:
		return
	draw_colored_polygon(pts, fill_col)
	var n := pts.size()
	_stroke_buf.resize(n + 1)
	for i in range(n):
		_stroke_buf[i] = pts[i]
	_stroke_buf[n] = pts[0]
	draw_polyline(_stroke_buf, stroke_col, stroke_w, true)

func draw_filled_ellipse(pos: Vector2, rx: float, ry: float, col: Color) -> void:
	if rx <= 0.01 or ry <= 0.01:
		return
	var segments := clampi(int(maxf(rx, ry) * 1.2), 10, 24)
	_circle_buf.resize(segments)
	for i in range(segments):
		var ang := float(i) * TAU / float(segments)
		_circle_buf[i] = pos + Vector2(cos(ang) * rx, sin(ang) * ry)
	draw_colored_polygon(_circle_buf, col)

func draw_soft_glow(pos: Vector2, radius: float, col: Color, layers: int = 3) -> void:
	for i in range(layers, 0, -1):
		var r := radius * (float(i) / float(layers))
		var a := col.a * (0.28 / float(i))
		_circle(pos, r, Color(col.r, col.g, col.b, a))

func draw_sharp_eye(pos: Vector2, width: float, height: float, col_glow: Color, col_core: Color) -> void:
	# 绘制狭长冷眸（外层幽光 + 内层锐核）
	draw_soft_glow(pos, width * 1.5, col_glow, 2)
	var pts := PackedVector2Array([
		pos + Vector2(-width, 0),
		pos + Vector2(0, -height),
		pos + Vector2(width, 0),
		pos + Vector2(0, height)
	])
	draw_colored_polygon(pts, col_core)
	draw_line(pos + Vector2(-width * 0.7, 0), pos + Vector2(width * 0.7, 0), Color.WHITE, 1.2, true)

# ==================== 2. 敌种专属程序化绘制管线 ====================

## 1. 史莱姆：幽冥血煞 / 凝魂怨泥 (贴地流质行进波)
func _draw_slime() -> void:
	var wave := sin(_time * 4.5) * 2.2
	var squish_x := 1.0 + sin(_time * 4.5) * 0.12 * (1.0 + speed_ratio * 0.4)
	var squish_y := 1.0 - sin(_time * 4.5) * 0.12 * (1.0 + speed_ratio * 0.4)

	# 地影
	draw_filled_ellipse(Vector2(0, 14), 16.0 * squish_x, 4.5, Color(0.04, 0.05, 0.08, 0.5))

	# 柔性流质血煞外轮廓（7 节点平滑多边形）
	var pts := PackedVector2Array([
		Vector2(-14 * squish_x, 12),
		Vector2(-16 * squish_x, 4 + wave * 0.3),
		Vector2(-9 * squish_x, -8 - wave * 0.5),
		Vector2(0, -12 - wave * 0.8),
		Vector2(9 * squish_x, -8 - wave * 0.5),
		Vector2(16 * squish_x, 4 - wave * 0.3),
		Vector2(14 * squish_x, 12)
	])
	draw_stroked_polygon(pts, config.col_primary, config.col_accent, 1.8)

	# 内部深渊核
	draw_filled_ellipse(Vector2(0, 2 - wave * 0.3), 8.0 * squish_x, 6.0, config.col_void)

	# 沉浮的森白碎骨片
	draw_line(Vector2(-5, 4 + wave * 0.2), Vector2(-1, 0 + wave * 0.2), config.col_secondary, 2.0, true)
	draw_line(Vector2(3, 5 - wave * 0.2), Vector2(7, 3 - wave * 0.2), config.col_secondary, 1.8, true)

	# 幽绿怨魂单眼（微光跳动）
	var eye_pos := Vector2(0, -2 - wave * 0.4)
	draw_sharp_eye(eye_pos, 4.5, 3.0, config.col_glow, Color(0.9, 1.0, 0.8))

## 2. 御剑邪修：幽冥剑客 (御剑悬浮滑行)
func _draw_xiexiu() -> void:
	var float_y := sin(_time * 2.8) * 2.4
	var t_bank := bank_angle * 0.85
	var adv_lean := deg_to_rad(advance * 4.0)

	# 火球蓄力姿态（special_state 与 EnemyBase._bolt_windup_t 同源）：脚下幽剑后拉 3px + 剑尖聚光，
	# 与毒妖毒囊胀大同一条「蓄力读法」通道——变色预告之外再给一个形体预告
	var casting := special_state > 0.0
	var cast_pull := 3.0 * special_state

	# 地影（高度变化驱动影子呼吸）
	var shadow_rx := 13.0 - float_y * 0.4
	draw_filled_ellipse(Vector2(0, 16), maxf(shadow_rx, 6.0), 4.0, Color(0.04, 0.05, 0.08, 0.45))

	# 脚下幽光残剑（斜横悬浮，剑身刻符文）
	var sword_pos := Vector2(-2 - cast_pull, 11 + float_y)
	var sword_rot := deg_to_rad(14.0) + t_bank * 0.5 - adv_lean * 0.5
	var t_sword := Transform2D(sword_rot, sword_pos)
	var sword_glow_a := 0.4 + special_state * 0.45
	draw_soft_glow(sword_pos, 14.0, config.col_glow * Color(1, 1, 1, sword_glow_a), 2)
	if casting:
		# 剑尖聚光：出膛方向的前端一点暖白亮核，读「火球将从此处出」
		var tip_pos := t_sword * Vector2(19, 0)
		_circle(tip_pos, 2.6 + special_state * 1.6, Color(1.0, 0.85, 0.55, 0.5 + special_state * 0.4))
	var blade_pts := PackedVector2Array([
		t_sword * Vector2(-16, -2),
		t_sword * Vector2(14, -1),
		t_sword * Vector2(19, 0), # 尖锐断锋
		t_sword * Vector2(14, 1),
		t_sword * Vector2(-16, 2)
	])
	draw_stroked_polygon(blade_pts, config.col_secondary, config.col_glow, 1.4)
	# 剑格与剑柄红穗
	draw_line(t_sword * Vector2(-12, -4), t_sword * Vector2(-12, 4), config.col_accent, 2.0, true)
	draw_line(t_sword * Vector2(-16, 0), t_sword * Vector2(-21, 2), Color(0.85, 0.25, 0.25), 1.6, true)

	# 破风墨黑长袍下摆（飘逸）
	var cloth_wave := sin(_time * 4.0) * 2.0
	var robe_pts := PackedVector2Array([
		Vector2(-9, 10 + float_y + cloth_wave),
		Vector2(-7, -4 + float_y),
		Vector2(7, -4 + float_y),
		Vector2(9, 10 + float_y - cloth_wave),
		Vector2(2, 8 + float_y),
		Vector2(-2, 11 + float_y)
	])
	draw_stroked_polygon(robe_pts, config.col_primary, config.col_accent, 1.6)

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
	draw_stroked_polygon(mask_pts, config.col_secondary, config.col_void, 1.8)

	# 单侧修罗冷眸
	draw_sharp_eye(head_pos + Vector2(2, -1), 3.5, 1.8, config.col_glow, Color.WHITE)

## 3. 丹爆傀儡：蚀骨毒炉 (悬浮晃荡 + 沸腾胀缩)
func _draw_danbao() -> void:
	var float_y := sin(_time * 3.2) * 2.0
	var is_critical := special_state > 0.0 # 自爆点燃引信中
	var boil_pulse := sin(_time * (28.0 if is_critical else 6.0)) * (1.8 if is_critical else 0.4)

	# 地影
	draw_filled_ellipse(Vector2(0, 15), 14.0 + boil_pulse, 4.5, Color(0.04, 0.05, 0.08, 0.5))

	var urn_center := Vector2(0, 1 + float_y)
	var urn_r := 11.0 + boil_pulse

	# 鼎炉外壳
	_circle(urn_center, urn_r, config.col_primary)
	_arc(urn_center, urn_r, 0, TAU, 24, config.col_secondary, 2.0, true)

	# 炉身灼热地火裂纹
	var glow_c := config.col_glow if not is_critical else Color(1.2, 0.2, 0.1)
	draw_soft_glow(urn_center, urn_r * 0.9, glow_c * Color(1, 1, 1, 0.5 if not is_critical else 0.9), 2)
	draw_line(urn_center + Vector2(-6, 2), urn_center + Vector2(1, -2), glow_c, 2.0, true)
	draw_line(urn_center + Vector2(1, -2), urn_center + Vector2(5, 4), glow_c, 1.6, true)
	draw_line(urn_center + Vector2(-2, -5), urn_center + Vector2(2, 5), glow_c, 1.8, true)

	# 炉顶青铜小盖与炉耳
	draw_filled_ellipse(urn_center + Vector2(0, -urn_r + 1), 7.0, 3.2, config.col_secondary)
	_circle(urn_center + Vector2(0, -urn_r - 2), 2.2, config.col_accent)
	draw_line(urn_center + Vector2(-urn_r - 2, -2), urn_center + Vector2(-urn_r + 1, 2), config.col_secondary, 2.2, true)
	draw_line(urn_center + Vector2(urn_r - 1, 2), urn_center + Vector2(urn_r + 2, -2), config.col_secondary, 2.2, true)

## 4. 蜂群精：冥火毒螟 (超高频振翅飞行)
func _draw_fengqun() -> void:
	var float_y := sin(_time * 6.0) * 1.8
	var wing_phase := sin(_time * 48.0) # ~15Hz 振翅
	var wing_span := 15.0 * absf(wing_phase)

	# 轻量小地影
	draw_filled_ellipse(Vector2(0, 15), 9.0, 3.2, Color(0.04, 0.05, 0.08, 0.35))

	var body_pos := Vector2(0, float_y)

	# 前后双重半透明高频翅翼
	var left_wing_fore := PackedVector2Array([
		body_pos + Vector2(-2, -3),
		body_pos + Vector2(-6 - wing_span, -13 + wing_phase * 2.5),
		body_pos + Vector2(-5 - wing_span * 0.7, -2),
	])
	var right_wing_fore := PackedVector2Array([
		body_pos + Vector2(2, -3),
		body_pos + Vector2(6 + wing_span, -13 + wing_phase * 2.5),
		body_pos + Vector2(5 + wing_span * 0.7, -2),
	])
	var left_wing_hind := PackedVector2Array([
		body_pos + Vector2(-2, 0),
		body_pos + Vector2(-4 - wing_span * 0.75, 4 + wing_phase * 2.0),
		body_pos + Vector2(-1, 3),
	])
	var right_wing_hind := PackedVector2Array([
		body_pos + Vector2(2, 0),
		body_pos + Vector2(4 + wing_span * 0.75, 4 + wing_phase * 2.0),
		body_pos + Vector2(1, 3),
	])
	draw_colored_polygon(left_wing_hind, config.col_accent * Color(1, 1, 1, 0.55))
	draw_colored_polygon(right_wing_hind, config.col_accent * Color(1, 1, 1, 0.55))
	draw_colored_polygon(left_wing_fore, config.col_accent)
	draw_colored_polygon(right_wing_fore, config.col_accent)

	# 锋锐骨锥头胸
	var thorax_pts := PackedVector2Array([
		body_pos + Vector2(0, -9), # 尖锐头顶
		body_pos + Vector2(-5, -2),
		body_pos + Vector2(0, 4),
		body_pos + Vector2(5, -2)
	])
	draw_stroked_polygon(thorax_pts, config.col_primary, config.col_secondary, 1.6)

	# 剧毒磷光复眼
	draw_soft_glow(body_pos + Vector2(-2.5, -4), 4.0, config.col_glow, 2)
	draw_soft_glow(body_pos + Vector2(2.5, -4), 4.0, config.col_glow, 2)
	_circle(body_pos + Vector2(-2.5, -4), 1.6, Color.WHITE)
	_circle(body_pos + Vector2(2.5, -4), 1.6, Color.WHITE)

	# 下垂毒针尾囊
	var stinger_pts := PackedVector2Array([
		body_pos + Vector2(-3, 3),
		body_pos + Vector2(0, 12), # 尖毒针
		body_pos + Vector2(3, 3)
	])
	draw_stroked_polygon(stinger_pts, config.col_void, config.col_glow, 1.4)

## 5. 花妖：噬灵妖花 (空灵悬浮舒展)
func _draw_flower() -> void:
	var float_y := sin(_time * 2.2) * 2.6
	var petal_open := 1.0 + sin(_time * 3.5) * 0.15 # 花瓣呼吸开合

	# 地影
	draw_filled_ellipse(Vector2(0, 16), 13.0, 4.0, Color(0.04, 0.05, 0.08, 0.45))

	var center := Vector2(0, -2 + float_y)

	# 下方垂落的 3 缕柔韧水墨花蕊（如水母触须随风飘拂）
	for i in [-1, 0, 1]:
		var phase_offset := float(i) * 0.8
		var sway := sin(_time * 3.0 + phase_offset) * 4.0
		var p0 := center + Vector2(float(i) * 4.0, 6)
		var p1 := p0 + Vector2(sway * 0.5, 8)
		var p2 := p1 + Vector2(sway, 9)
		draw_polyline(PackedVector2Array([p0, p1, p2]), config.col_accent, 1.6, true)

	# 5 片放射状锋利血色花瓣
	for i in range(5):
		var ang := float(i) * (TAU / 5.0) - PI * 0.5 + sin(_time * 1.5) * 0.08
		var tip := center + Vector2(cos(ang), sin(ang)) * (16.0 * petal_open)
		var left := center + Vector2(cos(ang - 0.4), sin(ang - 0.4)) * (9.0 * petal_open)
		var right := center + Vector2(cos(ang + 0.4), sin(ang + 0.4)) * (9.0 * petal_open)
		var petal_pts := PackedVector2Array([center, left, tip, right])
		draw_stroked_polygon(petal_pts, config.col_primary, config.col_secondary, 1.4)

	# 花心深渊虚空与噬灵邪眼
	_circle(center, 5.5, config.col_void)
	draw_sharp_eye(center, 4.2, 2.5, config.col_glow, Color.WHITE)

## 6. 血蛹：九幽血茧 (贴地拱动与心跳搏动)
func _draw_xueyong() -> void:
	var pulse := sin(_time * 3.0) * 1.2
	var squish_x := 1.0 + sin(_time * 3.0) * 0.08
	var squish_y := 1.0 - sin(_time * 3.0) * 0.08

	# 地影
	draw_filled_ellipse(Vector2(0, 13), 16.0 * squish_x, 4.8, Color(0.04, 0.05, 0.08, 0.55))

	var center := Vector2(0, 2)
	var rx := (13.0 + pulse * 0.5) * squish_x
	var ry := (15.0 - pulse * 0.5) * squish_y

	# 暗红血晶茧体
	draw_filled_ellipse(center, rx, ry, config.col_primary)
	_arc(center, rx, 0, TAU, 28, config.col_accent, 2.0, true)

	# 内部幽微血光核心（心跳明暗）
	var core_alpha := 0.4 + sin(_time * 3.0) * 0.25
	draw_soft_glow(center, 10.0, config.col_glow * Color(1, 1, 1, core_alpha), 2)

	# 缠绕的惨白镇魂封印符布
	draw_line(center + Vector2(-rx * 0.8, -4), center + Vector2(rx * 0.7, 6), config.col_secondary, 3.2, true)
	draw_line(center + Vector2(-rx * 0.7, 5), center + Vector2(rx * 0.8, -5), config.col_secondary, 3.0, true)
	# 朱砂封灵符线
	draw_line(center + Vector2(-rx * 0.6, -3), center + Vector2(rx * 0.5, 5), Color(0.85, 0.15, 0.2), 1.2, true)

## 7. 毒妖：腐沼毒蟾 (浮沉 + 背负腐毒囊)
## 特殊状态（special_state > 0）时毒囊胀大、囊内磷火转亮 —— 与投毒预警同源可读：
## 玩家看到它「鼓起来」就知道脚下要出毒潭了（预警圈负责精确落点，这里负责身份预告）。
func _draw_duyao() -> void:
	var float_y := sin(_time * 2.4) * 2.0
	var casting: bool = special_state > 0.0
	var sac_pulse: float = 1.0 + (0.35 if casting else 0.0) * absf(sin(_time * 9.0))

	# 腐沼地影（比鼓妖更湿更扁）
	draw_filled_ellipse(Vector2(0, 16), 15.5, 4.0, Color(0.04, 0.07, 0.05, 0.45))

	var body_c := Vector2(0, float_y)

	# 厚皮躯体：矮壮梨形，前宽后窄
	var body_pts := PackedVector2Array([
		body_c + Vector2(-9, -8),
		body_c + Vector2(9, -8),
		body_c + Vector2(12, 4),
		body_c + Vector2(7, 12),
		body_c + Vector2(-8, 11),
		body_c + Vector2(-12, 0)
	])
	draw_stroked_polygon(body_pts, config.col_primary, config.col_accent, 1.8)

	# 苔痕皮瘤（背上一串）
	for i in range(3):
		var bx: float = -6.0 + float(i) * 6.0
		_circle(body_c + Vector2(bx, -7.5), 1.6, config.col_accent)

	# 脓黄斑块（侧腹两团）
	draw_filled_ellipse(body_c + Vector2(-7.5, 2), 3.0, 2.2, config.col_secondary)
	draw_filled_ellipse(body_c + Vector2(7.5, 2), 3.0, 2.2, config.col_secondary)

	# 背负腐毒囊：鼓胀囊体 + 囊内核。蓄力时整囊胀大，玩家一眼读出「要投毒了」
	var sac_c := body_c + Vector2(-2.0, -14.0)
	var sac_r: float = 7.5 * sac_pulse
	draw_filled_ellipse(sac_c, sac_r, sac_r * 0.92, config.col_secondary)
	_arc(sac_c, sac_r, 0, TAU, 24, config.col_accent, 2.0, true)
	var core_alpha: float = 0.5 + (0.45 if casting else 0.0)
	draw_soft_glow(sac_c, sac_r * 0.8, config.col_glow * Color(1, 1, 1, core_alpha), 2)
	_circle(sac_c, sac_r * 0.38, config.col_glow)
	# 囊体与躯体之间的毒液导管
	draw_line(sac_c + Vector2(3.0, sac_r * 0.7), body_c + Vector2(4.0, -7.0), config.col_secondary, 2.0, true)

	# 竖瞳（毒磷火色）：蓄力时亮度提一档
	var eye_glow: Color = config.col_glow if not casting else config.col_glow.lightened(0.5)
	draw_sharp_eye(body_c + Vector2(-4.0, -3.0), 1.5, 3.2, eye_glow, Color.WHITE)
	draw_sharp_eye(body_c + Vector2(4.0, -3.0), 1.5, 3.2, eye_glow, Color.WHITE)

	# 口缝与垂涎（滴落感用相位错开的两颗）
	var mouth_y: float = body_c.y + 5.0
	draw_line(body_c + Vector2(-4.0, mouth_y), body_c + Vector2(4.0, mouth_y), config.col_secondary, 1.6, true)
	var drip := fposmod(_time * 1.6, 1.0)
	_circle(body_c + Vector2(-3.0, mouth_y + drip * 6.0), 1.2, config.col_glow)
	_circle(body_c + Vector2(3.0, mouth_y + fposmod(_time * 1.6 + 0.5, 1.0) * 6.0), 1.0, config.col_glow)

## 8. 鼓妖：白骨摄魂鼓 (律动悬浮敲击)
func _draw_guyao() -> void:
	var float_y := sin(_time * 2.6) * 2.2
	var drum_center := Vector2(0, float_y)

	# 地影
	draw_filled_ellipse(Vector2(0, 15), 15.0, 4.2, Color(0.04, 0.05, 0.08, 0.45))

	# 煞铜重鼓鼓身（略扁椭圆）
	draw_filled_ellipse(drum_center, 14.5, 12.0, config.col_primary)
	_arc(drum_center, 14.5, 0, TAU, 28, config.col_secondary, 2.2, true)

	# 鼓面太极魔纹与灵玉核心
	_arc(drum_center, 8.5, 0, TAU, 20, config.col_accent, 1.4, true)
	draw_soft_glow(drum_center, 8.0, config.col_glow * Color(1, 1, 1, 0.6), 2)
	_circle(drum_center, 3.2, config.col_glow)

	# 鼓框两侧咬合的白骨獠牙
	for i in [-1, 1]:
		var fx := float(i) * 14.0
		draw_polyline(PackedVector2Array([
			drum_center + Vector2(fx, -6),
			drum_center + Vector2(fx + float(i) * 4.0, 0),
			drum_center + Vector2(fx, 6)
		]), config.col_secondary, 2.0, true)

	# 两侧悬空交替敲击的白骨槌
	var strike_l := sin(_time * 4.0)
	var strike_r := -strike_l
	var mallet_l := drum_center + Vector2(-18.0 + strike_l * 3.0, -4)
	var mallet_r := drum_center + Vector2(18.0 - strike_r * 3.0, -4)
	draw_line(mallet_l, mallet_l + Vector2(-6, -6), config.col_secondary, 2.2, true)
	_circle(mallet_l, 2.4, config.col_secondary)
	draw_line(mallet_r, mallet_r + Vector2(6, -6), config.col_secondary, 2.2, true)
	_circle(mallet_r, 2.4, config.col_secondary)

## 9. 影魅：幽冥影煞 (流体暗影飘掠)
func _draw_yingmei() -> void:
	var float_y := sin(_time * 3.5) * 1.8
	var wave := sin(_time * 5.5) * 2.5

	# 虚空地影
	draw_filled_ellipse(Vector2(0, 15), 13.0, 3.8, Color(0.04, 0.05, 0.08, 0.4))

	var head_pos := Vector2(0, -7 + float_y)

	# 纯黑暗影躯体与撕裂雾化下摆
	var cloak_pts := PackedVector2Array([
		head_pos + Vector2(-8, 2),
		head_pos + Vector2(8, 2),
		head_pos + Vector2(11, 20 + wave * 0.6),
		head_pos + Vector2(4, 16 - wave * 0.4),
		head_pos + Vector2(-1, 22 + wave * 0.5),
		head_pos + Vector2(-9, 17 - wave * 0.6)
	])
	draw_stroked_polygon(cloak_pts, config.col_primary, config.col_accent, 1.8)

	# 双支向后弯曲的影骨角
	draw_polyline(PackedVector2Array([
		head_pos + Vector2(-4, -4),
		head_pos + Vector2(-9, -12),
		head_pos + Vector2(-12, -10)
	]), config.col_secondary, 2.2, true)
	draw_polyline(PackedVector2Array([
		head_pos + Vector2(4, -4),
		head_pos + Vector2(9, -12),
		head_pos + Vector2(12, -10)
	]), config.col_secondary, 2.2, true)

	# 苍白虚空面壳与雪白锐利狭眸
	draw_filled_ellipse(head_pos, 6.0, 5.0, config.col_void)
	draw_sharp_eye(head_pos + Vector2(-2.5, 0), 2.8, 1.5, config.col_glow, Color.WHITE)
	draw_sharp_eye(head_pos + Vector2(2.5, 0), 2.8, 1.5, config.col_glow, Color.WHITE)

## 10. 百目妖：千目邪母 (多目微眨沉重悬浮)
func _draw_zhumu() -> void:
	var float_y := sin(_time * 1.8) * 2.2
	var center := Vector2(0, float_y)

	# 庞大地影
	draw_filled_ellipse(Vector2(0, 18), 20.0, 5.5, Color(0.04, 0.05, 0.08, 0.5))

	# 巨大深紫魔核躯体
	draw_filled_ellipse(center, 18.0, 15.0, config.col_primary)
	_arc(center, 18.0, 0, TAU, 32, config.col_accent, 2.2, true)

	# 下方蠕动的微弱触手
	for i in range(-2, 3):
		var sx := float(i) * 5.0
		var tw := sin(_time * 3.0 + float(i)) * 3.0
		draw_polyline(PackedVector2Array([
			center + Vector2(sx, 12),
			center + Vector2(sx + tw * 0.5, 18),
			center + Vector2(sx + tw, 23)
		]), config.col_primary, 2.2, true)

	# 主魔眼（正中央巨眼）
	draw_filled_ellipse(center, 7.5, 5.5, config.col_void)
	draw_sharp_eye(center, 5.5, 3.5, config.col_glow, Color(1.0, 0.9, 0.3))

	# 围绕周身的 6 颗小魔眼（具有独立的随机眨眼周期）
	var eye_offsets := [
		Vector2(-10, -6), Vector2(10, -6),
		Vector2(-12, 3), Vector2(12, 3),
		Vector2(-5, 9), Vector2(5, 9)
	]
	for idx in range(eye_offsets.size()):
		var offset: Vector2 = eye_offsets[idx]
		var blink := sin(_time * 4.0 + float(idx) * 1.8)
		if blink > -0.6: # 未眨眼时睁开
			var ep := center + offset
			_circle(ep, 2.8, config.col_secondary)
			_circle(ep, 1.6, config.col_void)
			_circle(ep, 0.8, config.col_glow)

## 11. 雷兽 / 赤雷兽 (低伏巡游与雷煞暴突)
func _draw_leibeast(is_elite: bool) -> void:
	var float_y := sin(_time * 3.6) * 1.5
	var crouch := special_state * 2.0 # 蓄力下蹲形变

	# 地影
	var shd_rx := 18.0 if not is_elite else 23.0
	draw_filled_ellipse(Vector2(0, 14), shd_rx, 4.8, Color(0.04, 0.05, 0.08, 0.5))

	var body_center := Vector2(0, 1 + float_y + crouch)

	# 骨甲凶兽四足低伏剪影
	var beast_pts := PackedVector2Array([
		body_center + Vector2(-16, 8),
		body_center + Vector2(-14, 0),
		body_center + Vector2(-7, -7), # 弓背
		body_center + Vector2(7, -7),
		body_center + Vector2(14, 0),
		body_center + Vector2(16, 8),
		body_center + Vector2(7, 6),
		body_center + Vector2(-7, 6)
	])
	draw_stroked_polygon(beast_pts, config.col_primary, config.col_accent, 2.0)

	# 背部向后倾斜的锋利雷棘骨刺（4 根）
	for i in range(4):
		var px := -9.0 + float(i) * 5.0
		var spike_h := (6.0 + float(i) * 1.5) if not is_elite else (9.0 + float(i) * 2.0)
		draw_polyline(PackedVector2Array([
			body_center + Vector2(px, -6),
			body_center + Vector2(px - 4.0, -6 - spike_h),
			body_center + Vector2(px + 2.0, -6)
		]), config.col_secondary, 2.0, true)

	# 头部狼首骨面与獠牙
	var head_pos := body_center + Vector2(12, -2)
	var mask_pts := PackedVector2Array([
		head_pos + Vector2(-4, -4),
		head_pos + Vector2(6, -2), # 尖吻
		head_pos + Vector2(2, 4),
		head_pos + Vector2(-4, 3)
	])
	draw_stroked_polygon(mask_pts, config.col_secondary, config.col_void, 1.8)
	# 獠牙
	draw_line(head_pos + Vector2(3, 2), head_pos + Vector2(4, 6), config.col_secondary, 1.6, true)

	# 精英独占：巨大冲天分叉赤金雷角
	if is_elite:
		draw_polyline(PackedVector2Array([
			head_pos + Vector2(-2, -4),
			head_pos + Vector2(0, -14),
			head_pos + Vector2(6, -18)
		]), config.col_secondary, 2.4, true)
		draw_line(head_pos + Vector2(0, -11), head_pos + Vector2(-5, -15), config.col_secondary, 2.0, true)

	# 暴虐电弧双眸
	draw_sharp_eye(head_pos + Vector2(0, -1), 3.0, 1.4, config.col_glow, Color.WHITE)

## 12. 铁甲魔傀（精英）：幽冥玄铁巨傀 (重力悬浮磁场)
func _draw_golem() -> void:
	var float_y := sin(_time * 2.0) * 1.8
	var center := Vector2(0, -2 + float_y)

	# 沉重巨地影
	draw_filled_ellipse(Vector2(0, 18), 22.0, 6.0, Color(0.04, 0.05, 0.08, 0.6))

	# 青黑玄铁核心胸铠
	var chest_pts := PackedVector2Array([
		center + Vector2(-12, 10),
		center + Vector2(-15, -4),
		center + Vector2(0, -12),
		center + Vector2(15, -4),
		center + Vector2(12, 10),
		center + Vector2(0, 14)
	])
	draw_stroked_polygon(chest_pts, config.col_primary, config.col_accent, 2.4)

	# 胸口旋转的幽蓝菱形阵眼灵石
	var rot := _time * 1.2
	var gem_pts := PackedVector2Array([
		center + Vector2(cos(rot), sin(rot)) * 6.0,
		center + Vector2(cos(rot + PI * 0.5), sin(rot + PI * 0.5)) * 6.0,
		center + Vector2(cos(rot + PI), sin(rot + PI)) * 6.0,
		center + Vector2(cos(rot + PI * 1.5), sin(rot + PI * 1.5)) * 6.0
	])
	draw_soft_glow(center, 12.0, config.col_glow, 2)
	draw_colored_polygon(gem_pts, config.col_glow)

	# 浮空两侧的玄铁巨盾肩甲（随移速微幅起伏滞后）
	for i in [-1, 1]:
		var fx := float(i) * 19.0
		var sh_pts := PackedVector2Array([
			center + Vector2(fx - 4, -8),
			center + Vector2(fx + 4, -8),
			center + Vector2(fx + 5, 8),
			center + Vector2(fx - 5, 8)
		])
		draw_stroked_polygon(sh_pts, config.col_secondary, config.col_accent, 1.8)

	# 头顶方形青铜古面
	var head_pts := PackedVector2Array([
		center + Vector2(-7, -12),
		center + Vector2(7, -12),
		center + Vector2(6, -20),
		center + Vector2(-6, -20)
	])
	draw_stroked_polygon(head_pts, config.col_primary, config.col_secondary, 2.0)
	draw_line(center + Vector2(-4, -16), center + Vector2(4, -16), config.col_glow, 1.8, true)

## 13. 剑煞邪修（精英）：万剑煞宗残魂 (三剑齐御悬浮)
func _draw_jiansha_elite() -> void:
	var float_y := sin(_time * 2.8) * 2.2
	var center := Vector2(0, float_y)

	# 地影
	draw_filled_ellipse(Vector2(0, 16), 16.0, 4.5, Color(0.04, 0.05, 0.08, 0.5))

	# 火球蓄力姿态（special_state 同源）：三剑向身后收拢 3px 并提亮，读「聚气将发」
	var cast_pull := 3.0 * special_state
	var cast_bright := 0.4 + special_state * 0.45

	# 背后呈扇形悬浮的 3 柄冷冽煞剑（主剑在中央，双侧副剑）
	for i in range(3):
		var ang_offset := deg_to_rad(-24.0 + float(i) * 24.0)
		var sw_pos := center + Vector2(cos(ang_offset + PI * 0.5), sin(ang_offset + PI * 0.5) - 1.0) * (-12.0 - cast_pull)
		var sw_rot := ang_offset + deg_to_rad(150.0)
		var t_sw := Transform2D(sw_rot, sw_pos)
		draw_soft_glow(sw_pos, 10.0, config.col_glow * Color(1, 1, 1, cast_bright), 2)
		var sw_pts := PackedVector2Array([
			t_sw * Vector2(-15, -2),
			t_sw * Vector2(16, -1),
			t_sw * Vector2(21, 0),
			t_sw * Vector2(16, 1),
			t_sw * Vector2(-15, 2)
		])
		draw_stroked_polygon(sw_pts, config.col_secondary, config.col_glow, 1.6)
		if special_state > 0.0 and i == 1:
			# 中间主剑剑尖聚光：火球出膛方位预告
			var tip := t_sw * Vector2(21, 0)
			_circle(tip, 2.4 + special_state * 1.6, Color(1.0, 0.85, 0.55, 0.5 + special_state * 0.4))

	# 墨黑金纹魔袍
	var robe_pts := PackedVector2Array([
		center + Vector2(-10, 12),
		center + Vector2(-8, -4),
		center + Vector2(8, -4),
		center + Vector2(10, 12),
		center + Vector2(0, 9)
	])
	draw_stroked_polygon(robe_pts, config.col_primary, config.col_accent, 2.0)

	# 苍白修罗骨面带垂直血痕
	var head_pos := center + Vector2(0, -9)
	var mask_pts := PackedVector2Array([
		head_pos + Vector2(-7, 6),
		head_pos + Vector2(-8, -5),
		head_pos + Vector2(0, -11),
		head_pos + Vector2(8, -5),
		head_pos + Vector2(7, 6),
		head_pos + Vector2(0, 9)
	])
	draw_stroked_polygon(mask_pts, config.col_secondary, config.col_void, 2.0)
	draw_line(head_pos + Vector2(0, -8), head_pos + Vector2(0, 7), Color(0.85, 0.15, 0.25), 1.6, true)
	draw_sharp_eye(head_pos + Vector2(-3, 0), 3.2, 1.6, config.col_glow, Color.WHITE)
	draw_sharp_eye(head_pos + Vector2(3, 0), 3.2, 1.6, config.col_glow, Color.WHITE)

## 14. 敌潮魔君 & 心魔魔尊 (BOSS / 魔神君临御空)
func _draw_boss(final_boss: bool) -> void:
	var float_y := sin(_time * 2.2) * 2.8
	var center := Vector2(0, -4 + float_y)

	# 霸者超大地影
	draw_filled_ellipse(Vector2(0, 26), 28.0, 7.5, Color(0.04, 0.05, 0.08, 0.65))

	# 背后悬浮的魔轮（普通 Boss 为 4 骨刃环，第 20 波魔尊为 8 符文神魔紫焰法轮）
	var wheel_rot := _time * (0.6 if not final_boss else 0.8)
	var blade_count := 8 if final_boss else 4
	var wheel_radius := 26.0 if not final_boss else 32.0
	draw_soft_glow(center, wheel_radius * 1.1, config.col_glow * Color(1, 1, 1, 0.4), 2)
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
	draw_stroked_polygon(armor_pts, config.col_primary, config.col_accent, 2.5)

	# 胸口核心魔眼
	draw_soft_glow(center, 12.0, config.col_glow, 2)
	draw_filled_ellipse(center, 7.0, 5.0, config.col_void)
	draw_sharp_eye(center, 5.5, 3.2, config.col_glow, Color.WHITE)

	# 鬼王骨面与冲天魔角（心魔魔尊带有九幽分叉魔冠）
	var head_pos := center + Vector2(0, -18)
	var mask_pts := PackedVector2Array([
		head_pos + Vector2(-9, 7),
		head_pos + Vector2(-11, -5),
		head_pos + Vector2(0, -13),
		head_pos + Vector2(11, -5),
		head_pos + Vector2(9, 7),
		head_pos + Vector2(0, 11)
	])
	draw_stroked_polygon(mask_pts, config.col_secondary, config.col_void, 2.2)

	# 巨大魔角
	draw_polyline(PackedVector2Array([
		head_pos + Vector2(-6, -6),
		head_pos + Vector2(-14, -18),
		head_pos + Vector2(-11, -25)
	]), config.col_secondary, 3.0, true)
	draw_polyline(PackedVector2Array([
		head_pos + Vector2(6, -6),
		head_pos + Vector2(14, -18),
		head_pos + Vector2(11, -25)
	]), config.col_secondary, 3.0, true)

	if final_boss:
		# 皇冠分叉中央角
		draw_polyline(PackedVector2Array([
			head_pos + Vector2(-3, -11),
			head_pos + Vector2(0, -22),
			head_pos + Vector2(3, -11)
		]), config.col_accent, 2.2, true)

	# 燃烧神魔双目
	draw_sharp_eye(head_pos + Vector2(-4, 0), 4.2, 2.0, config.col_glow, Color.WHITE)
	draw_sharp_eye(head_pos + Vector2(4, 0), 4.2, 2.0, config.col_glow, Color.WHITE)

## 15. 灵医：青囊药灵 (悬浮治疗者，背悬回春光环)
func _draw_lingyi() -> void:
	var float_y := sin(_time * 3.0) * 2.0
	var center := Vector2(0, -4 + float_y)

	# 地影
	draw_filled_ellipse(Vector2(0, 15), 12.0, 3.6, Color(0.04, 0.05, 0.08, 0.4))

	# 背后缓慢旋转的回春光环（治疗者的身份标识）
	var halo_rot := _time * 0.9
	draw_soft_glow(center, 16.0, config.col_glow * Color(1, 1, 1, 0.35), 2)
	_arc(center, 13.0, 0, TAU, 24, config.col_accent, 1.4, true)
	for i in range(4):
		var ang := halo_rot + float(i) * (TAU / 4.0)
		var r_pos := center + Vector2(cos(ang), sin(ang)) * 13.0
		_circle(r_pos, 1.8, config.col_glow)

	# 药童袍躯（上窄下宽的斗篷轮廓）
	var robe_pts := PackedVector2Array([
		center + Vector2(-6, -6),
		center + Vector2(6, -6),
		center + Vector2(10, 12),
		center + Vector2(0, 16),
		center + Vector2(-10, 12)
	])
	draw_stroked_polygon(robe_pts, config.col_primary, config.col_accent, 1.8)

	# 胸前绷带十字（月白布条）
	draw_line(center + Vector2(-4, 2), center + Vector2(4, 2), config.col_secondary, 2.4, true)
	draw_line(center + Vector2(0, -2), center + Vector2(0, 6), config.col_secondary, 2.4, true)

	# 头面与温润圆眸
	var head_pos := center + Vector2(0, -10)
	draw_filled_ellipse(head_pos, 5.5, 5.0, config.col_void)
	_circle(head_pos + Vector2(-2.2, 0), 1.6, config.col_glow)
	_circle(head_pos + Vector2(2.2, 0), 1.6, config.col_glow)

## 16. 金蟾：衔宝金蟾 (胖圆宝兽，口衔铜钱)
func _draw_jinchan() -> void:
	var float_y := sin(_time * 4.0) * 2.4
	var hop := absf(sin(_time * 4.0)) * (1.0 + speed_ratio * 0.6)
	var center := Vector2(0, -2 + float_y - hop * 2.0)

	# 地影随跳跃缩放
	var shadow_w := 14.0 - hop * 3.0
	draw_filled_ellipse(Vector2(0, 15), shadow_w, 4.0, Color(0.04, 0.05, 0.08, 0.4))

	# 宝气金光罩
	draw_soft_glow(center, 18.0, config.col_glow * Color(1, 1, 1, 0.4), 2)

	# 胖圆蟾躯与腹甲
	draw_filled_ellipse(center, 13.5, 11.0, config.col_primary)
	draw_filled_ellipse(center + Vector2(0, 3), 8.5, 6.0, config.col_secondary)
	_arc(center, 13.5, 0, TAU, 26, config.col_accent, 1.6, true)

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
	var head_pos := center + Vector2(0, -7)
	_circle(head_pos + Vector2(-4, 0), 2.6, config.col_void)
	_circle(head_pos + Vector2(4, 0), 2.6, config.col_void)
	_circle(head_pos + Vector2(-4, -0.5), 1.1, config.col_glow)
	_circle(head_pos + Vector2(4, -0.5), 1.1, config.col_glow)
