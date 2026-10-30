extends RefCounted

## 墨煞族（全身墨黑系列）：玄渊墨煞，隐迹潜行 —— 纯黑袍身/极暗冷芒游走/三缕墨烟。
##
## 2026-10-30 皮肤系列化重构新族模块（墨煞专属动效）。
##
## 关键美学：大部分画面是黑的，光要吝啬。绝不能画成"黑袍上挂彩灯"，
## 气质是"暗处有东西在动，但你几乎看不清"。
##
## 三条实现要点：
## ① 袍面吞噬感暗纹：仅允许微弱正弦波压暗（幅度 ≤0.04），只压暗绝不提亮，守住深邃纯黑底色。
## ② 缘边极暗冷青游走：全轮廓极暗描边（alpha ~0.22）+ 一段极慢单向游走冷光（周期 ≥8s，half=3，alpha ≤0.55），绝无逐顶点彩虹。
## ③ 周身三缕墨烟上升：恒定 3 缕，每缕以 3 层同心圆淡墨层层晕开，整体极低 alpha（≤0.16），平滑上升并伴横向正弦飘摆。

const SkinFxCommon = preload("res://scripts/entities/procedural_cultivator/skin_fx/SkinFxCommon.gd")

# ----------------- 默认参数常量 -----------------

## 整体时间周期基准（秒）
const DEFAULT_CYCLE := 8.0

## 袍面吞噬感暗纹最大压暗幅度（≤0.04 铁律，黑袍上加亮即发灰，只压暗不提亮）
const SHEEN_DARKEN_AMP := 0.035
## 吞噬暗纹空间频率 X 步进
const SHEEN_DX := 0.015
## 吞噬暗纹空间频率 Y 步进
const SHEEN_DY := 0.020

## 缘边基础极暗描边透明度（0.18 ~ 0.25）
const RIM_BASE_ALPHA := 0.22
## 缘边游走冷光周期（秒，≥8s 慢速游走）
const RIM_CYCLE_SECONDS := 9.0
## 游走光段半宽顶点数（half=2~3）
const COMET_HALF := 3
## 游走光段峰值透明度（≤0.55）
const COMET_ALPHA := 0.50
## 游走光段相对基础描边的线宽增量
const COMET_WIDTH_EXTRA := 0.5
## 游走光段色相散布（0.0：绝对单色，禁止逐顶点彩虹）
const COMET_SPREAD := 0.0

## 墨烟粒子总数（硬性纪律：≤ 3 颗）
const MOTE_COUNT := 3
## 墨烟垂直上升行程总跨度（px）
const MOTE_RISE_SPAN := 38.0
## 墨烟垂直底部起始基准偏移（px）
const MOTE_BOTTOM_Y := 20.0
## 墨烟上升循环总周期（秒）
const MOTE_RISE_CYCLE := 5.2
## 墨烟颜色相对 cloak_inner 的提亮比例
const SMOKE_LIGHTEN := 0.15

## 墨烟 3 层同心圆尺寸配置（外层 3~4px，内层 1~1.5px）
const LAYER_RADIUS_OUTER := 3.6
const LAYER_RADIUS_MID := 2.2
const LAYER_RADIUS_INNER := 1.2

## 墨烟 3 层同心圆基础透明度配置（整体 alpha 极低 ≤0.16，外层最淡最大）
const LAYER_ALPHA_OUTER := 0.045
const LAYER_ALPHA_MID := 0.090
const LAYER_ALPHA_INNER := 0.150

## 3 缕墨烟的空间与相位配置（静态无随机数组：X 偏置、错相、飘动角频、飘动幅度）
const MOTE_CONFIGS: Array[Dictionary] = [
	{
		"base_x": -7.5,
		"phase_offset": 0.0,
		"sway_speed": 1.3,
		"sway_amp": 3.2,
	},
	{
		"base_x": 1.0,
		"phase_offset": 0.36,
		"sway_speed": 1.0,
		"sway_amp": 4.0,
	},
	{
		"base_x": 8.5,
		"phase_offset": 0.72,
		"sway_speed": 1.4,
		"sway_amp": 3.6,
	},
]

## 眼睛柔光半径大幅收窄（乘 0.45，黑袍上只留一点冷光）
const EYE_GLOW_RADIUS_MUL := 0.45
## 眼睛柔光透明度缩放（乘 0.70）
const EYE_GLOW_ALPHA_MUL := 0.70


# ----------------- 6 个静态接口 -----------------

## 族默认参数：SkinData 主题只需写 kind + 想偏离默认的键
static func defaults() -> Dictionary:
	return {
		"cycle": DEFAULT_CYCLE,
		"sheen_amp": SHEEN_DARKEN_AMP,
		"sheen_dx": SHEEN_DX,
		"sheen_dy": SHEEN_DY,
		"rim_base_alpha": RIM_BASE_ALPHA,
		"rim_cycle": RIM_CYCLE_SECONDS,
		"comet_half": COMET_HALF,
		"comet_alpha": COMET_ALPHA,
		"mote_cycle": MOTE_RISE_CYCLE,
		"eye_glow_radius_mul": EYE_GLOW_RADIUS_MUL,
		"eye_glow_alpha_mul": EYE_GLOW_ALPHA_MUL,
	}


## 重绘前钩子：墨煞为静态黑底与固定冷光，严禁色相流转（防黑袍变彩袍），空实现
static func on_frame(_h, _p: Dictionary) -> void:
	pass


## 袍面吞噬感暗纹：仅允许微弱正弦波压暗（幅度 ≤0.04），只压暗绝不提亮，保留深邃墨黑底
static func cloak_sheen(h, base: Color, pt: Vector2, p: Dictionary) -> Color:
	var phase: float = SkinFxCommon.phase_of(h, p)
	var amp: float = minf(float(p.get("sheen_amp", SHEEN_DARKEN_AMP)), 0.04)
	var dx: float = float(p.get("sheen_dx", SHEEN_DX))
	var dy: float = float(p.get("sheen_dy", SHEEN_DY))
	# 正弦波波动（0.0 ~ 1.0），仅在波幅内微弱压暗，永不提亮
	var wave: float = 0.5 + 0.5 * sin((pt.x * dx + pt.y * dy + phase) * TAU)
	return base.darkened(wave * amp)


## 缘边极暗冷青游走：基础极暗描边 + 单段缓慢游走光段（周期 ≥8s，half=3，alpha ≤0.55）
static func draw_rim(h, pts: PackedVector2Array, base_w: float, p: Dictionary) -> void:
	var cn: int = pts.size()
	if cn < 2:
		return
	var cur_time: float = float(h._time)
	var idle_p: float = float(h._idle_phase)
	var edge_base: Color = h._fx_base.get("cloak_edge", Color(0.22, 0.42, 0.52))

	# 1. 沿轮廓的基础极暗冷青描边（维持暗黑轮廓基础，不刺眼）
	var base_alpha: float = float(p.get("rim_base_alpha", RIM_BASE_ALPHA))
	var base_rim_col: Color = Color(edge_base.r, edge_base.g, edge_base.b, base_alpha)
	h.draw_polyline(pts, base_rim_col, base_w, true)

	# 2. 沿缘边极慢游走的极暗冷青光段（周期 ≥8s，half=2~3，alpha ≤0.55）
	var rim_cycle: float = maxf(float(p.get("rim_cycle", RIM_CYCLE_SECONDS)), 8.0)
	var comet_prog: float = fposmod(cur_time / rim_cycle + idle_p * 0.05, 1.0)
	var comet_center: int = int(comet_prog * float(cn))
	var half: int = int(p.get("comet_half", COMET_HALF))
	var comet_alpha: float = minf(float(p.get("comet_alpha", COMET_ALPHA)), 0.55)

	# 纯冷青单色游走：spread=0.0，绝不逐顶点彩虹流转
	var seg: Array = SkinFxCommon.comet_segments(
		pts,
		comet_center,
		half,
		edge_base.h,
		0.0,
		COMET_SPREAD,
		edge_base.s,
		edge_base.v,
		comet_alpha
	)
	var comet_pts: PackedVector2Array = seg[0]
	var comet_cols: PackedColorArray = seg[1]

	# 两端平滑羽化，避免光段首尾产生硬切边缘
	var seg_count: int = comet_cols.size()
	var half_f: float = float(half)
	for i in range(seg_count):
		var dist: float = absf(float(i - half)) / maxf(half_f, 1.0)
		var feather: float = clampf(1.0 - dist * dist, 0.0, 1.0)
		comet_cols[i].a *= feather

	if comet_pts.size() >= 2:
		h.draw_polyline_colors(comet_pts, comet_cols, base_w + COMET_WIDTH_EXTRA, true)


## 常驻粒子：3 缕墨烟缓慢上升，每缕为 3 层同心圆淡墨晕染，极低 alpha（≤0.16），横向正弦飘摆
static func draw_motes(h, float_y: float, p: Dictionary) -> void:
	var cur_time: float = float(h._time)
	var idle_p: float = float(h._idle_phase)
	var ws: float = float(h.width_scale) if "width_scale" in h else 1.0
	var cycle: float = maxf(float(p.get("mote_cycle", MOTE_RISE_CYCLE)), 1.0)
	var inner_base: Color = h._fx_base.get("cloak_inner", Color(0.075, 0.082, 0.102))
	var smoke_col: Color = inner_base.lightened(SMOKE_LIGHTEN)

	var bottom_y: float = MOTE_BOTTOM_Y + float_y
	var top_y: float = bottom_y - MOTE_RISE_SPAN

	for i in range(MOTE_COUNT):
		var cfg: Dictionary = MOTE_CONFIGS[i]
		var base_x: float = float(cfg["base_x"])
		var phase_offset: float = float(cfg["phase_offset"])
		var sway_speed: float = float(cfg["sway_speed"])
		var sway_amp: float = float(cfg["sway_amp"])

		# 垂直平滑循环上升进度（0.0 ~ 1.0）
		var prog: float = fposmod(cur_time / cycle + phase_offset + idle_p * 0.06, 1.0)
		var my: float = lerpf(bottom_y, top_y, prog)

		# 横向平滑飘动：正弦摆动模拟烟气上升时的袅袅飘移
		var sway: float = sin(cur_time * sway_speed + prog * TAU + phase_offset * 3.0) * sway_amp * ws
		var mx: float = (base_x + sway) * ws
		var pos: Vector2 = Vector2(mx, my)

		# 上升全过程的平滑淡入淡出包络（底部与顶部渐隐，无跳变）
		var envelope: float = sin(prog * PI)
		if envelope <= 0.01:
			continue

		# 3 层同心圆绘制（外层最大最淡，内层微小稍显，单层 alpha 严格 ≤ 0.16）
		# 1. 外层：漫散烟晕（3~4px）
		var col_out: Color = Color(smoke_col.r, smoke_col.g, smoke_col.b, LAYER_ALPHA_OUTER * envelope)
		h._circle(pos, LAYER_RADIUS_OUTER, col_out)

		# 2. 中层：过渡烟身
		var col_mid: Color = Color(smoke_col.r, smoke_col.g, smoke_col.b, LAYER_ALPHA_MID * envelope)
		h._circle(pos, LAYER_RADIUS_MID, col_mid)

		# 3. 内层：微小烟核（1~1.5px）
		var col_in: Color = Color(smoke_col.r, smoke_col.g, smoke_col.b, LAYER_ALPHA_INNER * envelope)
		h._circle(pos, LAYER_RADIUS_INNER, col_in)


## 眼柔光调整：大幅收窄半径（乘 0.45）并压低 alpha（乘 0.70），颜色保持不变，留微弱冷芒
static func eye_glow_adjust(_h, radius: float, col: Color, p: Dictionary) -> Dictionary:
	var rad_mul: float = float(p.get("eye_glow_radius_mul", EYE_GLOW_RADIUS_MUL))
	var alpha_mul: float = float(p.get("eye_glow_alpha_mul", EYE_GLOW_ALPHA_MUL))
	return {
		"radius": radius * rad_mul,
		"color": Color(col.r, col.g, col.b, col.a * alpha_mul),
	}
