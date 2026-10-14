class_name BurstKindFx
extends Node2D

## BURST 落点分化演出（2026-10-13）：9 把范围武器旧写法清一色「闪电柱+光环」，
## 天灯文案说火雨、画面是闪电。本渲染器按 burst_kind 出各自的落点形态：
##   fire_rain 火雨（天灯）  frost 冰刺（玄冥雷珠）  sonic 音波环（音笛）
##   drum 鼓震波（春雷鼓）   earth 地裂（裂山铎）   seal 坠印扬尘（巨印）
##   thunder 默认雷系不画（雷柱/闪电已在 ThunderBurst/LightningBolt 里）
## 全部几何由判定半径 radius 一个量派生（画多大==判多大），纯 _draw 零粒子零灯光；
## 作为 ThunderBurst 的常驻子节点随池复用，activate_fx 重铺字段即重生，零 instantiate。

var kind: String = "thunder"
var radius: float = 80.0
var tint: Color = Color.WHITE

const DUR := 0.38          ## 演出总时长（略短于 ThunderBurst 全亮档 0.45s 生命周期）
const FIREBALLS := 5       ## 火雨落点数
const FROST_SPIKES := 7    ## 冰刺数
const SONIC_RINGS := 3     ## 音波环数
const EARTH_CRACKS := 6    ## 地裂条数

var _t: float = 0.0
## 重绘节流（2026-10-14）：演出窗口内原每帧无条件重绘，0.38s 演出 20Hz 足够流畅
const REDRAW_INTERVAL := 0.05
var _draw_phase: float = 0.0

func _ready() -> void:
	_draw_phase = fposmod(float(get_instance_id() % 97) * 0.001, REDRAW_INTERVAL)
	visible = false
	set_process(false)

## 重铺字段并开演（池化复用唯一入口）
func activate_fx(p_kind: String, p_radius: float, p_tint: Color) -> void:
	kind = p_kind
	radius = p_radius
	tint = p_tint
	_t = 0.0
	if kind == "thunder" or kind == "":
		visible = false
		set_process(false)
		return
	visible = true
	set_process(true)

## 提前收场（ThunderBurst 回池时调用）
func deactivate() -> void:
	visible = false
	set_process(false)

func _process(delta: float) -> void:
	_t += delta
	if _t >= DUR:
		deactivate()
		return
	_draw_phase -= delta
	if _draw_phase <= 0.0:
		_draw_phase = REDRAW_INTERVAL
		queue_redraw()

func _draw() -> void:
	match kind:
		"fire_rain":
			_draw_fire_rain()
		"frost":
			_draw_frost()
		"sonic":
			_draw_sonic()
		"drum":
			_draw_drum()
		"earth":
			_draw_earth()
		"seal":
			_draw_seal_dust()

## 火雨：数枚三层火核从斜上方坠入判定半径，落点后留余烬
func _draw_fire_rain() -> void:
	for i in FIREBALLS:
		var ang := float(i) * 2.4 + 0.7
		var land := Vector2(cos(ang), sin(ang)) * radius * (0.2 + 0.55 * fposmod(float(i) * 0.37, 1.0))
		var fall_dur := 0.22
		var delay := float(i) * 0.045
		var p: float = clampf((_t - delay) / fall_dur, 0.0, 1.0)
		if p <= 0.0:
			continue
		if p < 1.0:
			# 坠落中：从高空二次加速坠到落点，画三层火核 + 向上彗尾
			var pos := Vector2(land.x + (1.0 - p * p) * land.x * 0.4, lerpf(-190.0, land.y, p * p))
			var s := 7.0 + 2.0 * p
			_draw_flame_drop(pos, s, 0.95)
		else:
			# 落点后余烬：小圆淡出
			var fade := 1.0 - clampf((_t - delay - fall_dur) / (DUR - fall_dur), 0.0, 1.0)
			if fade > 0.0:
				var c := Color(1.0, 0.55, 0.2, 0.5 * fade)
				draw_circle(land, 4.0 + 3.0 * (1.0 - fade), c)

## 三层火核（照 ProceduralProjectileRenderer._draw_flame 的配色层次）
func _draw_flame_drop(pos: Vector2, s: float, a: float) -> void:
	var tail := PackedVector2Array([
		pos + Vector2(-s * 0.5, 0), pos + Vector2(0, -s * 2.2), pos + Vector2(s * 0.5, 0)])
	draw_colored_polygon(tail, Color(0.85, 0.25, 0.12, 0.5 * a))
	draw_circle(pos, s, Color(0.85, 0.25, 0.12, 0.75 * a))
	draw_circle(pos, s * 0.62, Color(1.0, 0.65, 0.20, 0.9 * a))
	draw_circle(pos, s * 0.3, Color(1.0, 0.95, 0.85, a))

## 冰霜：冰刺从落点圈内拔地戳出（ stagger 生长），末端霜环淡去
func _draw_frost() -> void:
	for i in FROST_SPIKES:
		var ring_r := radius * (0.35 if i < 3 else 0.72)
		var ang := float(i) * 2.399 + 0.4   # 黄金角散布
		var base := Vector2(cos(ang), sin(ang)) * ring_r
		var grow: float = clampf((_t - float(i) * 0.03) / 0.12, 0.0, 1.0)
		if grow <= 0.0:
			continue
		var fade := 1.0 - clampf((_t - 0.24) / (DUR - 0.24), 0.0, 1.0)
		var h := (20.0 + 8.0 * fposmod(float(i) * 0.53, 1.0)) * grow
		var w := 5.5 * grow
		var a := 0.9 * fade
		# 冰刺是微倾的三角晶柱，向外倒伏
		var lean := base.normalized() * 6.0
		draw_colored_polygon(PackedVector2Array([
			base + Vector2(-w, 0), base + Vector2(w, 0), base + lean + Vector2(0, -h)]),
			Color(tint.r, tint.g, tint.b, 0.75 * a))
		draw_line(base + Vector2(0, -2), base + lean + Vector2(0, -h), Color(0.92, 0.98, 1.0, a), 1.6)
	# 霜环：演出末段贴着判定半径内缘淡去
	var ring_p: float = clampf(_t / 0.2, 0.0, 1.0)
	var ring_a := 0.4 * (1.0 - clampf((_t - 0.2) / (DUR - 0.2), 0.0, 1.0))
	if ring_a > 0.0:
		draw_arc(Vector2.ZERO, radius * 0.9 * ring_p, 0.0, TAU, 40, Color(tint.r, tint.g, tint.b, ring_a), 2.0)

## 音波：三重细环递进扩散（音笛是声波不是雷）
func _draw_sonic() -> void:
	for i in SONIC_RINGS:
		var p: float = clampf((_t - float(i) * 0.07) / 0.24, 0.0, 1.0)
		if p <= 0.0:
			continue
		var r := radius * (0.2 + 0.8 * p)
		var a := 0.75 * (1.0 - p)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 44, Color(tint.r, tint.g, tint.b, a), 2.6 - p)
		# 环上 6 个方向的短促波纹刻度，强化「声波推出去」的读法
		if p < 0.7:
			for k in 6:
				var ang := float(k) * TAU / 6.0 + float(i) * 0.3
				var dir := Vector2(cos(ang), sin(ang))
				draw_line(dir * (r - 4.0), dir * (r + 4.0), Color(0.9, 0.97, 1.0, a * 0.8), 1.4)

## 鼓震：一记重环砸开 + 8 条放射震线（春雷滚滚的闷击感）
func _draw_drum() -> void:
	var p: float = clampf(_t / 0.3, 0.0, 1.0)
	var a := 0.85 * (1.0 - p)
	if a > 0.0:
		draw_arc(Vector2.ZERO, radius * p, 0.0, TAU, 44, Color(tint.r, tint.g, tint.b, a), 5.0 - 3.0 * p)
		for k in 8:
			var ang := float(k) * TAU / 8.0 + 0.2
			var dir := Vector2(cos(ang), sin(ang))
			draw_line(dir * radius * 0.2 * p, dir * radius * 0.85 * p,
				Color(tint.r, tint.g, tint.b, a * 0.6), 1.8)
	# 鼓面回弹：中心小圆两拍脉冲
	var pulse := 1.0 + 0.35 * sin(_t * 28.0) * maxf(0.0, 1.0 - _t / 0.25)
	draw_arc(Vector2.ZERO, 10.0 * pulse, 0.0, TAU, 20, Color(1.0, 0.95, 0.8, 0.7 * (1.0 - p)), 2.0)

## 地裂：锯齿裂缝从爆心爬出去 + 碎石块崩起（裂山铎）
func _draw_earth() -> void:
	var p: float = clampf(_t / 0.16, 0.0, 1.0)
	var fade := 1.0 - clampf((_t - 0.22) / (DUR - 0.22), 0.0, 1.0)
	var crack_col := Color(0.16, 0.11, 0.05, 0.8 * fade)
	for i in EARTH_CRACKS:
		var ang := float(i) * TAU / float(EARTH_CRACKS) + 0.35
		var dir := Vector2(cos(ang), sin(ang))
		var tan := Vector2(-sin(ang), cos(ang))
		var reach := radius * (0.55 + 0.35 * fposmod(float(i) * 0.61, 1.0)) * p
		var pts := PackedVector2Array()
		for k in 4:
			var d := reach * float(k + 1) / 4.0
			var jag := (3.5 if k % 2 == 0 else -3.5) * (1.0 - float(k) / 5.0)
			pts.append(dir * d + tan * jag)
		draw_polyline(pts, crack_col, 2.4)
		# 裂缝沿线的亮土边（裂口翻起的新土）
		draw_polyline(pts, Color(tint.r, tint.g, tint.b, 0.35 * fade), 0.9)
	# 崩起的碎石块：easeOutBack 弹出后定格，随尾段淡出
	for i in 5:
		var ang := float(i) * 1.9 + 0.9
		var pos := Vector2(cos(ang), sin(ang)) * radius * (0.3 + 0.4 * fposmod(float(i) * 0.43, 1.0))
		var bp: float = clampf((_t - float(i) * 0.02) / 0.14, 0.0, 1.0)
		if bp <= 0.0:
			continue
		var s := (3.0 + 2.0 * fposmod(float(i) * 0.77, 1.0)) * (1.0 + 2.7 * pow(bp - 1.0, 3.0) + 1.7 * pow(bp - 1.0, 2.0))
		draw_colored_polygon(PackedVector2Array([
			pos + Vector2(-s, s * 0.5), pos + Vector2(0, -s), pos + Vector2(s, s * 0.4)]),
			Color(tint.r * 0.85, tint.g * 0.8, tint.b * 0.7, 0.85 * fade))

## 坠印扬尘（巨印落点形态，2026-10-15 重构）：大印不再画实体——旧 SealImpactFx 方印
## 是一张糊在爆心的大图，违和。改读「砸下去之后地面发生什么」：一记快速砸开的
## 重冲击环压场 + 一圈低扬尘环 + 尘点四溅，全部几何由 radius 派生（画多大==判多大）
func _draw_seal_dust() -> void:
	var fade := 1.0 - clampf((_t - 0.22) / (DUR - 0.22), 0.0, 1.0)
	# 重冲击环：0.16s 内从爆心砸到判定内缘，粗→细快速收细，给出「重物落地的第一拍」
	var slam_p: float = clampf(_t / 0.16, 0.0, 1.0)
	if slam_p > 0.0 and slam_p < 1.0:
		var slam_r := radius * (0.15 + 0.75 * slam_p)
		var slam_a := 0.75 * (1.0 - slam_p) * maxf(fade, 0.35)
		draw_arc(Vector2.ZERO, slam_r, 0.0, TAU, 44,
			Color(tint.r, tint.g, tint.b, slam_a), 6.5 - 4.5 * slam_p)
	# 低扬尘环：冲击环过后贴地翻起，慢速外扩
	var p: float = clampf(_t / 0.3, 0.0, 1.0)
	var a := 0.4 * (1.0 - p)
	if a > 0.0:
		var dust := Color(tint.r * 0.7, tint.g * 0.65, tint.b * 0.55, a)
		draw_arc(Vector2.ZERO, radius * (0.4 + 0.6 * p), 0.0, TAU, 40, dust, 3.0 - p)
		for k in 10:
			var ang := float(k) * TAU / 10.0 + 0.15
			var dir := Vector2(cos(ang), sin(ang))
			var r := radius * (0.35 + 0.55 * p)
			draw_circle(dir * r, 2.0, dust)
