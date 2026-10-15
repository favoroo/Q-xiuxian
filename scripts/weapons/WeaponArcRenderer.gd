class_name WeaponArcRenderer
extends Node2D

## 元素刀光渲染器（2026-10-13）：取代 slash_effect.png / sweep_effect.png 的纯矢量实现。
## 差异化思路照 ProceduralDroneRenderer：五行元素各自一套「主色/亮芯/外缘形态」——
##   金：白金亮刃 + 前缘亮线    木：藤绿刃 + 拖缘叶刺    水：冰蓝刃 + 晶棱
##   火：橙红刃 + 火舌卷边      土：赭黄厚刃 + 台阶岩缘    雷：紫电刃 + 锯齿电弧
## 对外契约（WeaponAimCheck 钉死，一字不动）：
##   外缘半径 OUTER(124) × scale == 判定几何外缘；所有形态点缀都不许刺出 OUTER。
##   近战月牙张角 ±70° / 横扫扇面 ±80° 与判定同源；显隐只由 visible + modulate.a 驱动
##   （FloatingWeapon 的扫放/淡出 tween 照旧只动 position/scale/modulate.a，本渲染器零 tween）。

enum ArcMode { MELEE, SWEEP }

const OUTER := 124.0            ## 外缘画布半径 == FloatingWeapon.SLASH_ART_OUTER / SWEEP_ART_OUTER
const MELEE_INNER := 110.0      ## 近战月牙中心内缘（中心厚度 14px，两端收尖）== FloatingWeapon.SLASH_ART_INNER（出生"贴剑尖"反解用）
const MELEE_HALF := deg_to_rad(70.0)   ## 近战月牙张角，与 slash 旧贴图同源
const SWEEP_HALF := deg_to_rad(80.0)   ## 横扫月牙张角 == FloatingWeapon.SWEEP_HALF_ANGLE
const SWEEP_INNER := 104.0      ## 横扫月牙中心内缘（中心厚度 20px，比近战 14px 宽，雄浑大月牙）

const _ARC_STEPS := 30          ## 外缘采样段数
## 重绘节流（2026-10-14）：亮起窗口内原每帧无条件重绘，火舌/电弧微动 20Hz 足够
## 60fps 档（2026-10-15 VisualRate 档位联动）：刃光跟随挥砍运动，画面 3 帧一画会有
## 「位置顺、画面卡」分离感，高帧档翻倍到 40Hz；低档 20Hz 是 perf_probe 钉住的预算口径。
const HZ_LOW := 20.0
const HZ_HIGH := 40.0
static func _redraw_interval() -> float:
	return VisualRate.interval(HZ_HIGH, HZ_LOW)
static var redraw_count: int = 0  ## 重绘计数（perf_probe 节流判据消费）

var mode: ArcMode = ArcMode.MELEE
var element: String = "metal"   ## metal/wood/water/fire/earth/thunder，空串回落 metal
var _anim: float = 0.0          ## 亮起窗口内推相位：火舌/电弧微动
var _draw_phase: float = 0.0

func configure(p_mode: ArcMode, p_element: String) -> void:
	mode = p_mode
	element = p_element if p_element != "" else "metal"

func _ready() -> void:
	_draw_phase = fposmod(float(get_instance_id() % 97) * 0.001, _redraw_interval())
	set_process(false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		set_process(visible)
		if visible:
			queue_redraw()
		else:
			_anim = 0.0

func _process(delta: float) -> void:
	_anim += delta
	_draw_phase -= delta
	if _draw_phase <= 0.0:
		_draw_phase = _redraw_interval()
		redraw_count += 1
		queue_redraw()

## 元素调色板：main 主刃色 / core 近白亮芯 / glow 低透明外晕
static func _palette(elem: String) -> Dictionary:
	match elem:
		"fire":
			return {"main": Color(1.0, 0.52, 0.16), "core": Color(1.0, 0.95, 0.80), "glow": Color(0.85, 0.25, 0.12)}
		"water":
			return {"main": Color(0.42, 0.78, 1.0), "core": Color(0.90, 0.98, 1.0), "glow": Color(0.22, 0.48, 0.95)}
		"wood":
			return {"main": Color(0.42, 0.90, 0.50), "core": Color(0.85, 1.0, 0.80), "glow": Color(0.18, 0.60, 0.28)}
		"earth":
			return {"main": Color(0.92, 0.70, 0.38), "core": Color(1.0, 0.95, 0.75), "glow": Color(0.60, 0.42, 0.18)}
		"thunder":
			return {"main": Color(0.70, 0.55, 1.0), "core": Color(0.95, 0.90, 1.0), "glow": Color(0.42, 0.28, 0.90)}
		_:
			return {"main": Color(0.95, 0.93, 0.82), "core": Color(1.0, 1.0, 0.96), "glow": Color(0.85, 0.75, 0.45)}

## 外缘形态：返回该角度上的外缘半径（永不超过 OUTER —— 画多大==判多大的硬顶）
func _edge_radius(ang: float, out: float) -> float:
	match element:
		"fire":
			# 火舌卷边：4.5 个波峰的尖脉冲，从刃面向外燎（相位随 _anim 走，像火苗在舔）
			var spike := pow(absf(sin(ang * 2.25 + _anim * 9.0)), 3.0)
			return out - 6.0 + spike * 6.0
		"earth":
			# 台阶岩缘：每 18° 一级错落（幅度收敛，别把细刃扭成波浪）
			var step := deg_to_rad(18.0)
			return out if int(floor(ang / step)) % 2 == 0 else out - 4.0
		_:
			return out

## 月牙厚度剖面：u∈[0,1] 沿弧从拖尾端(-half)到前缘端(+half)。
## 两端收尖成针；峰偏向前缘（skew 1.35 把峰推到 u≈0.59），拖尾侧更薄更长，带挥砍速度感。
static func _taper(u: float) -> float:
	return pow(sin(PI * pow(u, 1.35)), 0.85)

## 锥形弧带：厚度沿弧按 _taper 渐变，两端收尖的真正月牙形（取代等宽圆环带）
func _band_tapered(r_out: float, half: float, thick_max: float, col: Color, shaped_edge: bool) -> void:
	var pts := PackedVector2Array()
	pts.resize((_ARC_STEPS + 1) * 2)
	for i in _ARC_STEPS + 1:
		var a := -half + (half * 2.0) * float(i) / float(_ARC_STEPS)
		var ro: float = _edge_radius(a, r_out) if shaped_edge else r_out
		pts[i] = Vector2(cos(a), sin(a)) * ro
	for i in _ARC_STEPS + 1:
		var a := half - (half * 2.0) * float(i) / float(_ARC_STEPS)
		var u := (a + half) / (half * 2.0)
		var ro: float = _edge_radius(a, r_out) if shaped_edge else r_out
		# 收尖端保留 0.8px 最小厚度：内外缘完全重合的零面积接缝会导致三角化失败
		pts[_ARC_STEPS + 1 + i] = Vector2(cos(a), sin(a)) * (ro - maxf(thick_max * _taper(u), 0.8))
	draw_colored_polygon(pts, col)

## 刃口亮线：贴外缘的细线（跟随火舌/岩缘形态内收 2px，不刺出刃带）
func _edge_line(r_out: float, half: float, col: Color, width: float, shaped_edge: bool) -> void:
	var pts := PackedVector2Array()
	pts.resize(_ARC_STEPS + 1)
	for i in _ARC_STEPS + 1:
		var a := -half + (half * 2.0) * float(i) / float(_ARC_STEPS)
		var ro: float = _edge_radius(a, r_out) if shaped_edge else r_out
		pts[i] = Vector2(cos(a), sin(a)) * (ro - 2.0)
	draw_polyline(pts, col, width)

func _draw() -> void:
	var pal := _palette(element)
	var main: Color = pal["main"]
	var core: Color = pal["core"]
	var glow: Color = pal["glow"]
	if mode == ArcMode.MELEE:
		_draw_crescent(main, core, glow)
	else:
		_draw_sweep_crescent(main, core, glow)
	_draw_accents(main, core, glow)

## 近战月牙：两端收尖的锥形细刃（中心厚 14px），四层叠画——
## 气芒 / 根部薄透底 / 刃口半层提亮（刃口亮、根部透）/ 贴外缘细亮线
func _draw_crescent(main: Color, core: Color, glow: Color) -> void:
	var thick := OUTER - MELEE_INNER
	glow.a = 0.10
	_band_tapered(OUTER, MELEE_HALF, thick + 7.0, glow, true)
	main.a = 0.40
	_band_tapered(OUTER, MELEE_HALF, thick, main, true)
	main.a = 0.65
	_band_tapered(OUTER, MELEE_HALF, thick * 0.55, main, true)
	core.a = 0.95
	_edge_line(OUTER, MELEE_HALF * 0.92, core, 1.8, true)

## 横扫月牙：与近战同源同构，张角更开阔（±80° vs ±70°）、中心更厚（20px vs 14px），
## 凌厉大月牙斩波；锥形收尖 + 刃口渐亮的层次与近战一致。
func _draw_sweep_crescent(main: Color, core: Color, glow: Color) -> void:
	var thick := OUTER - SWEEP_INNER
	glow.a = 0.12
	_band_tapered(OUTER, SWEEP_HALF, thick + 8.0, glow, true)
	main.a = 0.42
	_band_tapered(OUTER, SWEEP_HALF, thick, main, true)
	main.a = 0.68
	_band_tapered(OUTER, SWEEP_HALF, thick * 0.55, main, true)
	core.a = 0.95
	_edge_line(OUTER, SWEEP_HALF * 0.92, core, 2.2, true)

## 元素形态点缀（全部收在 OUTER 以内）
func _draw_accents(main: Color, core: Color, glow: Color) -> void:
	var half: float = MELEE_HALF if mode == ArcMode.MELEE else SWEEP_HALF
	match element:
		"metal":
			# 前缘亮线：刃口朝前的一侧更亮，像磨过的锋（收在锥形刃带厚度足够的中前段）
			var lead := PackedVector2Array()
			for i in 9:
				var a := half * 0.35 + (half * 0.5) * float(i) / 8.0
				lead.append(Vector2(cos(a), sin(a)) * (OUTER - 3.0))
			var c := core
			c.a = 1.0
			draw_polyline(lead, c, 1.8)
		"water":
			# 晶棱：-40°/0°/+40° 三枚小菱晶嵌在外缘
			var c := core
			c.a = 0.95
			for deg in [-40.0, 0.0, 40.0]:
				var a := deg_to_rad(deg)
				var dir := Vector2(cos(a), sin(a))
				var tan := Vector2(-sin(a), cos(a))
				var base := dir * (OUTER - 7.0)
				draw_colored_polygon(PackedVector2Array([
					base + tan * 3.5, dir * OUTER, base - tan * 3.5, dir * (OUTER - 12.0)]), c)
		"wood":
			# 拖缘叶刺：后半缘一串回勾的小三角刺（藤蔓抽打感；起点让开收尖的尾端）
			var c := main
			c.a = 0.95
			var deg := -rad_to_deg(half) + 24.0
			while deg < 6.0:
				var a := deg_to_rad(deg)
				var dir := Vector2(cos(a), sin(a))
				var tan := Vector2(-sin(a), cos(a))
				var base := dir * (OUTER - 5.0)
				draw_colored_polygon(PackedVector2Array([
					base, base + tan * 5.5 - dir * 3.0, base - dir * 5.0]), c)
				deg += 16.0
		"fire":
			# 余烬：刃带里三粒顺流漂移的火星
			var c := core
			for i in 3:
				var ph := fposmod(_anim * 2.2 + float(i) * 0.37, 1.0)
				var a := -half + half * 2.0 * ph
				var r := OUTER - 6.0 - float(i) * 2.5
				c.a = 0.9 * (1.0 - ph)
				draw_circle(Vector2(cos(a), sin(a)) * r, 1.6, c)
		"earth":
			# 碎岩纹：刃带内三条深色裂纹
			var c := Color(0.25, 0.18, 0.08, 0.55)
			for deg in [-28.0, 2.0, 34.0]:
				var a := deg_to_rad(deg)
				var dir := Vector2(cos(a), sin(a))
				draw_line(dir * (OUTER - 11.0), dir * (OUTER - 3.5) + Vector2(-sin(a), cos(a)) * 2.5, c, 1.4)
		"thunder":
			# 锯齿电弧：沿刃带中段折线窜动
			var pts := PackedVector2Array()
			var steps := 14
			for i in steps + 1:
				var a := -half + half * 2.0 * float(i) / float(steps)
				var r := OUTER - 8.0 + (3.0 if i % 2 == 0 else -3.0)
				pts.append(Vector2(cos(a), sin(a)) * r)
			var c := core
			c.a = 0.9
			draw_polyline(pts, c, 1.4)
