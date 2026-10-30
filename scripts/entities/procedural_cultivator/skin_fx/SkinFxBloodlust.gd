extends RefCounted

## 赤霄族（杀气）：赤焰丹霞，全套里杀气最重的一套 —— 高频锯齿脉动/杀气脉动/血雾下沉。
##
## 三条实现要点：
## ① 杀气脉动：眼瞳 alpha 随低频正弦呼吸（周期约 2.4s，幅度 ±15%），斩痕与光晕强制取赤金锋色，
##    袍面不叠油膜保持暗朱纯净。
## ② 锯齿沸腾：缘边赤光沿轮廓做三角波锯齿分布，且全圈以 0.8s 周期高频脉动，体现杀气沸腾；
##    描边宽度加宽 base_w + 0.8px。
## ③ 血雾下沉：三颗暗朱血雾颗粒沿 y 轴反向向下循环下沉，双层同心圆扩散柔化，无硬点低 alpha。

const SkinFxCommon = preload("res://scripts/entities/procedural_cultivator/skin_fx/SkinFxCommon.gd")

## 眼瞳杀气低频呼吸周期（秒）
const EYE_PULSE_PERIOD: float = 2.4
## 眼瞳杀气呼吸幅度（±15%）
const EYE_PULSE_AMP: float = 0.15
## 缘边脉动周期（秒，高频急促）
const RIM_CYCLE: float = 0.8
## 缘边锯齿波沿轮廓段数
const RIM_TEETH: float = 5.0
## 缘边锯齿波游走速度
const RIM_SPEED: float = 1.8
## 缘边描边额外宽度（px）
const RIM_WIDTH_ADD: float = 0.8
## 缘边描边基础透明度
const RIM_BASE_ALPHA: float = 0.35
## 缘边描边脉动透明度增量
const RIM_ALPHA_SPAN: float = 0.55
## 缘边描边峰值提亮幅度
const RIM_LIGHTEN_MAX: float = 0.35

## 血雾颗粒总数（硬上限 3 颗，玩家 60Hz 重绘性能红线）
const MOTE_COUNT: int = 3
## 血雾下沉周期（秒）
const MOTE_CYCLE: float = 2.4
## 血雾下沉垂直跨度（px）
const MOTE_SPAN_Y: float = 30.0
## 血雾生成顶部 Y 偏移（相对于 float_y）
const MOTE_TOP_Y: float = -8.0
## 3 颗血雾的基础 X 偏移（相对于中心，乘以 width_scale）
const MOTE_X_OFFSETS: Array[float] = [-9.5, 1.5, 9.0]
## 3 颗血雾的相位偏移（均匀错开下沉时机）
const MOTE_PHASE_OFFSETS: Array[float] = [0.0, 0.36, 0.71]
## 3 颗血雾的内圈尺寸（px，严格落在 1.2~1.8px 区间）
const MOTE_SIZES: Array[float] = [1.3, 1.7, 1.4]
## 3 颗血雾的水平微漂移频率
const MOTE_DRIFT_FREQS: Array[float] = [1.4, 1.8, 1.2]
## 3 颗血雾的水平微漂移幅度（px）
const MOTE_DRIFT_AMPS: Array[float] = [2.2, 2.6, 2.0]
## 血雾内圈峰值透明度（比灵气 0.35+ 显著偏低，体现雾感）
const MOTE_INNER_ALPHA_MAX: float = 0.22
## 血雾外圈扩散半径倍率
const MOTE_OUTER_RADIUS_MULT: float = 2.0
## 血雾外圈扩散透明度倍率
const MOTE_OUTER_ALPHA_MULT: float = 0.40

## 眼柔光向赤金锋偏色权重
const EYE_GLOW_LERP: float = 0.25

## 族默认参数：SkinData 主题只需写 kind + 想偏离默认的键
static func defaults() -> Dictionary:
	return {
		"eye_pulse_period": EYE_PULSE_PERIOD,
		"eye_pulse_amp": EYE_PULSE_AMP,
		"rim_cycle": RIM_CYCLE,
		"rim_teeth": RIM_TEETH,
		"rim_speed": RIM_SPEED,
		"rim_width_add": RIM_WIDTH_ADD,
		"mote_cycle": MOTE_CYCLE,
		"eye_glow_lerp": EYE_GLOW_LERP,
	}

## 重绘前重算宿主缓存色：眼瞳杀气脉动 + 赤金斩痕
static func on_frame(h, p: Dictionary) -> void:
	var base_eye: Color = h._fx_base["eye_glow"]
	var eye_period: float = maxf(float(p.get("eye_pulse_period", EYE_PULSE_PERIOD)), 0.1)
	var eye_amp: float = float(p.get("eye_pulse_amp", EYE_PULSE_AMP))
	var pulse: float = sin(float(h._time) * (TAU / eye_period))
	var new_a: float = clampf(base_eye.a * (1.0 + eye_amp * pulse), 0.0, 1.0)
	h.col_eye_glow = Color(base_eye.r, base_eye.g, base_eye.b, new_a)

	var edge_base: Color = h._fx_base["cloak_edge"]
	h.col_slash_arc = edge_base
	h.col_slash_glow = edge_base

## 袍面叠色：杀气靠缘边和粒子，袍面保持暗朱干净，原样返回 base
static func cloak_sheen(_h, base: Color, _pt: Vector2, _p: Dictionary) -> Color:
	return base

## 缘边赤光高频锯齿脉冲：逐顶点赤金描边，轮廓三角波锯齿 + 全圈 0.8s 周期高频脉动
static func draw_rim(h, pts: PackedVector2Array, base_w: float, p: Dictionary) -> void:
	var n: int = pts.size()
	if n < 2:
		return
	var edge_base: Color = h._fx_base["cloak_edge"]
	var rim_cycle: float = maxf(float(p.get("rim_cycle", RIM_CYCLE)), 0.1)
	var teeth: float = float(p.get("rim_teeth", RIM_TEETH))
	var speed: float = float(p.get("rim_speed", RIM_SPEED))
	var w_add: float = float(p.get("rim_width_add", RIM_WIDTH_ADD))

	# 全圈随时间高频脉动（周期约 0.8s，三角波脉冲）
	var t_global: float = float(h._time) / rim_cycle
	var global_pulse: float = 0.60 + 0.40 * absf(fposmod(t_global, 1.0) * 2.0 - 1.0)

	var cols: PackedColorArray = PackedColorArray()
	cols.resize(n)
	var inv_n: float = 1.0 / float(maxi(n, 1))
	for i in range(n):
		var t_spatial: float = float(i) * inv_n * teeth - float(h._time) * speed
		# 轮廓锯齿三角波：abs(fposmod(t, 1.0) * 2.0 - 1.0)
		var saw: float = absf(fposmod(t_spatial, 1.0) * 2.0 - 1.0)
		var intensity: float = saw * global_pulse
		var c: Color = edge_base.lightened(RIM_LIGHTEN_MAX * intensity)
		c.a = clampf(RIM_BASE_ALPHA + RIM_ALPHA_SPAN * intensity, 0.0, 1.0)
		cols[i] = c

	h.draw_polyline_colors(pts, cols, base_w + w_add, true)

## 常驻粒子：3 颗暗朱血雾颗粒沿 y 方向反向向下循环下沉，双层同心圆扩散柔化
static func draw_motes(h, float_y: float, p: Dictionary) -> void:
	var inner_base: Color = h._fx_base["cloak_inner"]
	var mist_col: Color = inner_base.lerp(Color(0.52, 0.08, 0.08), 0.35)
	var time: float = float(h._time)
	var cycle: float = maxf(float(p.get("mote_cycle", MOTE_CYCLE)), 0.1)
	var ws: float = float(h.width_scale)

	for i in range(MOTE_COUNT):
		var phase_off: float = MOTE_PHASE_OFFSETS[i]
		# y 方向向下循环下沉（时间增加，prog 0->1，y 从上向下移动）
		var prog: float = fposmod(time / cycle + phase_off, 1.0)
		var y: float = float_y + MOTE_TOP_Y + prog * MOTE_SPAN_Y

		var base_x: float = MOTE_X_OFFSETS[i] * ws
		var drift: float = sin(time * MOTE_DRIFT_FREQS[i] + float(i) * 1.7) * MOTE_DRIFT_AMPS[i]
		var pos: Vector2 = Vector2(base_x + drift, y)

		# 呼吸淡入淡出（两端透明，中段可见）
		var fade: float = sin(prog * PI)
		var inner_a: float = fade * MOTE_INNER_ALPHA_MAX
		var outer_a: float = inner_a * MOTE_OUTER_ALPHA_MULT

		var r_inner: float = MOTE_SIZES[i]
		var r_outer: float = r_inner * MOTE_OUTER_RADIUS_MULT

		# 外层更大更淡（扩散雾晕），内层柔和（雾核）
		h._circle(pos, r_outer, Color(mist_col.r, mist_col.g, mist_col.b, outer_a))
		h._circle(pos, r_inner, Color(mist_col.r, mist_col.g, mist_col.b, inner_a))

## 眼柔光调整：不压 alpha（杀气保持明亮），原样返回 radius，颜色偏向赤红（赤金锋 lerp 0.25）
static func eye_glow_adjust(h, radius: float, col: Color, p: Dictionary) -> Dictionary:
	var edge_base: Color = h._fx_base["cloak_edge"]
	var lerp_k: float = float(p.get("eye_glow_lerp", EYE_GLOW_LERP))
	var target_col: Color = Color(edge_base.r, edge_base.g, edge_base.b, col.a)
	var final_col: Color = col.lerp(target_col, lerp_k)
	final_col.a = col.a
	return {
		"radius": radius,
		"color": final_col,
	}
