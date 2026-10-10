class_name HollowKnightEnemyRenderer
extends Node2D

## 敌人空洞冷冽国风程序化矢量渲染器
## 纯 GDScript CanvasItem 矢量绘制，涵盖悬浮、飞行、爬行波三大流体非复杂动作，
## 为全 14 种敌种提供高反差、骨面、虚空、灵核辉光的高辨识度妖魔拟态。

@export var config: EnemyVisualConfig:
	set(val):
		config = val
		if config != null:
			# 精英/Boss 数量少、动作分量重，保持每帧重绘；普通怪走 20Hz 节流
			_redraw_interval = REDRAW_INTERVAL_MOB if (not config.is_elite and not config.is_boss) else 0.0
		_dirty = true

# 运动驱动状态
var flip_h: bool = false:
	set(val):
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
const REDRAW_INTERVAL_MOB := 0.05   ## 普通怪重绘间隔：20Hz
const CULL_MARGIN := 64.0           ## 屏外剔除余量（px），防半身出屏闪烁
static var redraw_count: int = 0    ## 重绘发放计数（tests/PerfProbe 断言用）

var _draw_phase: float = 0.0        ## 距下次重绘的剩余时间（错相载体）
var _redraw_interval: float = REDRAW_INTERVAL_MOB
var _offscreen: bool = false
var _dirty: bool = false            ## 状态翻转（镜像/换装）时插队重绘

func _ready() -> void:
	# 错相：用 instance_id 派生初值（不碰玩法随机），把 35 只怪的重绘摊到不同帧，
	# 避免「每 N 帧一次集中重绘尖峰」把节流收益吃掉
	_draw_phase = fposmod(float(get_instance_id() % 97) * 0.001, REDRAW_INTERVAL_MOB)

func _process(delta: float) -> void:
	_time += delta
	var vp := get_viewport()
	if vp != null:
		var sp: Vector2 = vp.get_canvas_transform() * global_position
		var limit := vp.get_visible_rect().size + Vector2.ONE * CULL_MARGIN
		_offscreen = sp.x < -CULL_MARGIN or sp.y < -CULL_MARGIN \
			or sp.x > limit.x or sp.y > limit.y
		if _offscreen:
			return
	if _dirty or _draw_phase <= 0.0:
		_dirty = false
		_draw_phase = _redraw_interval
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

func draw_stroked_polygon(pts: PackedVector2Array, fill_col: Color, stroke_col: Color, stroke_w: float = 1.8) -> void:
	if pts.size() < 3:
		return
	draw_colored_polygon(pts, fill_col)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, stroke_col, stroke_w, true)

func draw_filled_ellipse(pos: Vector2, rx: float, ry: float, col: Color) -> void:
	if rx <= 0.01 or ry <= 0.01:
		return
	var segments := 24
	var pts := PackedVector2Array()
	pts.resize(segments)
	for i in range(segments):
		var ang := float(i) * TAU / float(segments)
		pts[i] = pos + Vector2(cos(ang) * rx, sin(ang) * ry)
	draw_colored_polygon(pts, col)

func draw_soft_glow(pos: Vector2, radius: float, col: Color, layers: int = 3) -> void:
	for i in range(layers, 0, -1):
		var r := radius * (float(i) / float(layers))
		var a := col.a * (0.28 / float(i))
		draw_circle(pos, r, Color(col.r, col.g, col.b, a))

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

	# 地影（高度变化驱动影子呼吸）
	var shadow_rx := 13.0 - float_y * 0.4
	draw_filled_ellipse(Vector2(0, 16), maxf(shadow_rx, 6.0), 4.0, Color(0.04, 0.05, 0.08, 0.45))

	# 脚下幽光残剑（斜横悬浮，剑身刻符文）
	var sword_pos := Vector2(-2, 11 + float_y)
	var sword_rot := deg_to_rad(14.0) + t_bank * 0.5 - adv_lean * 0.5
	var t_sword := Transform2D(sword_rot, sword_pos)
	draw_soft_glow(sword_pos, 14.0, config.col_glow * Color(1, 1, 1, 0.4), 2)
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
	draw_circle(urn_center, urn_r, config.col_primary)
	draw_arc(urn_center, urn_r, 0, TAU, 24, config.col_secondary, 2.0, true)

	# 炉身灼热地火裂纹
	var glow_c := config.col_glow if not is_critical else Color(1.2, 0.2, 0.1)
	draw_soft_glow(urn_center, urn_r * 0.9, glow_c * Color(1, 1, 1, 0.5 if not is_critical else 0.9), 2)
	draw_line(urn_center + Vector2(-6, 2), urn_center + Vector2(1, -2), glow_c, 2.0, true)
	draw_line(urn_center + Vector2(1, -2), urn_center + Vector2(5, 4), glow_c, 1.6, true)
	draw_line(urn_center + Vector2(-2, -5), urn_center + Vector2(2, 5), glow_c, 1.8, true)

	# 炉顶青铜小盖与炉耳
	draw_filled_ellipse(urn_center + Vector2(0, -urn_r + 1), 7.0, 3.2, config.col_secondary)
	draw_circle(urn_center + Vector2(0, -urn_r - 2), 2.2, config.col_accent)
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
	draw_circle(body_pos + Vector2(-2.5, -4), 1.6, Color.WHITE)
	draw_circle(body_pos + Vector2(2.5, -4), 1.6, Color.WHITE)

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
	draw_circle(center, 5.5, config.col_void)
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
	draw_arc(center, rx, 0, TAU, 28, config.col_accent, 2.0, true)

	# 内部幽微血光核心（心跳明暗）
	var core_alpha := 0.4 + sin(_time * 3.0) * 0.25
	draw_soft_glow(center, 10.0, config.col_glow * Color(1, 1, 1, core_alpha), 2)

	# 缠绕的惨白镇魂封印符布
	draw_line(center + Vector2(-rx * 0.8, -4), center + Vector2(rx * 0.7, 6), config.col_secondary, 3.2, true)
	draw_line(center + Vector2(-rx * 0.7, 5), center + Vector2(rx * 0.8, -5), config.col_secondary, 3.0, true)
	# 朱砂封灵符线
	draw_line(center + Vector2(-rx * 0.6, -3), center + Vector2(rx * 0.5, 5), Color(0.85, 0.15, 0.2), 1.2, true)

## 7. 鼓妖：白骨摄魂鼓 (律动悬浮敲击)
func _draw_guyao() -> void:
	var float_y := sin(_time * 2.6) * 2.2
	var drum_center := Vector2(0, float_y)

	# 地影
	draw_filled_ellipse(Vector2(0, 15), 15.0, 4.2, Color(0.04, 0.05, 0.08, 0.45))

	# 煞铜重鼓鼓身（略扁椭圆）
	draw_filled_ellipse(drum_center, 14.5, 12.0, config.col_primary)
	draw_arc(drum_center, 14.5, 0, TAU, 28, config.col_secondary, 2.2, true)

	# 鼓面太极魔纹与灵玉核心
	draw_arc(drum_center, 8.5, 0, TAU, 20, config.col_accent, 1.4, true)
	draw_soft_glow(drum_center, 8.0, config.col_glow * Color(1, 1, 1, 0.6), 2)
	draw_circle(drum_center, 3.2, config.col_glow)

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
	draw_circle(mallet_l, 2.4, config.col_secondary)
	draw_line(mallet_r, mallet_r + Vector2(6, -6), config.col_secondary, 2.2, true)
	draw_circle(mallet_r, 2.4, config.col_secondary)

## 8. 影魅：幽冥影煞 (流体暗影飘掠)
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

## 9. 百目妖：千目邪母 (多目微眨沉重悬浮)
func _draw_zhumu() -> void:
	var float_y := sin(_time * 1.8) * 2.2
	var center := Vector2(0, float_y)

	# 庞大地影
	draw_filled_ellipse(Vector2(0, 18), 20.0, 5.5, Color(0.04, 0.05, 0.08, 0.5))

	# 巨大深紫魔核躯体
	draw_filled_ellipse(center, 18.0, 15.0, config.col_primary)
	draw_arc(center, 18.0, 0, TAU, 32, config.col_accent, 2.2, true)

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
			draw_circle(ep, 2.8, config.col_secondary)
			draw_circle(ep, 1.6, config.col_void)
			draw_circle(ep, 0.8, config.col_glow)

## 10. 雷兽 / 赤雷兽 (低伏巡游与雷煞暴突)
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

## 11. 铁甲魔傀（精英）：幽冥玄铁巨傀 (重力悬浮磁场)
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

## 12. 剑煞邪修（精英）：万剑煞宗残魂 (三剑齐御悬浮)
func _draw_jiansha_elite() -> void:
	var float_y := sin(_time * 2.8) * 2.2
	var center := Vector2(0, float_y)

	# 地影
	draw_filled_ellipse(Vector2(0, 16), 16.0, 4.5, Color(0.04, 0.05, 0.08, 0.5))

	# 背后呈扇形悬浮的 3 柄冷冽煞剑（主剑在中央，双侧副剑）
	for i in range(3):
		var ang_offset := deg_to_rad(-24.0 + float(i) * 24.0)
		var sw_pos := center + Vector2(cos(ang_offset + PI * 0.5), sin(ang_offset + PI * 0.5) - 1.0) * -12.0
		var sw_rot := ang_offset + deg_to_rad(150.0)
		var t_sw := Transform2D(sw_rot, sw_pos)
		draw_soft_glow(sw_pos, 10.0, config.col_glow * Color(1, 1, 1, 0.4), 2)
		var sw_pts := PackedVector2Array([
			t_sw * Vector2(-15, -2),
			t_sw * Vector2(16, -1),
			t_sw * Vector2(21, 0),
			t_sw * Vector2(16, 1),
			t_sw * Vector2(-15, 2)
		])
		draw_stroked_polygon(sw_pts, config.col_secondary, config.col_glow, 1.6)

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

## 13. 妖潮魔君 & 心魔魔尊 (BOSS / 魔神君临御空)
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
	draw_arc(center, wheel_radius * 0.8, 0, TAU, 32, config.col_accent, 2.0, true)

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
