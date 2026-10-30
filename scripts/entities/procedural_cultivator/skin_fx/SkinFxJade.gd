extends RefCounted

## 苍竹族（青玉竹影）：碧色玉竹意象 —— 袍面竹节暗纹、缘边竹节亮带上推、周身双缕青屑上浮。
##
## 2026-10-30 皮肤系列化重构新族模块（苍竹专属动效）。
##
## 三条实现要点：
## ① 袍面竹节纹克制轻叠：利用 sin(pt.y * k) 在袍身形成 3~4 道水平等距竹节节线，
##    亮带取青玉碧偏亮色，混入强度上限 ≤0.12，确保深邃潭青底色不被破坏。
## ② 缘边竹节亮带自下而上推移：沿轮廓顶点依 pt.y 与时间相位形成上行动态亮带，
##    局部翠芒峰值高亮、非亮区保持半透明青翠，无整圈同亮钝感，不叠加多余彗星。
## ③ 双屑上浮零随机轨道：周身两颗青屑复用周天灵气环绕算法但 y 轴采用 fposmod 持续循环上升，
##    带极短向下拖尾，粒子总数恒定 2 颗，严格恪守性能与零随机红线。

const SkinFxCommon = preload("res://scripts/entities/procedural_cultivator/skin_fx/SkinFxCommon.gd")

# ----------------- 竹节暗纹常量 -----------------
## 竹节沿 y 轴分布的空间频率（袍身 y 跨度约 36px，k=0.60 对应波长 ~10.5px，约 3~4 节）
const BAMBOO_NODE_FREQ := 0.60
## 竹节纹混入袍面的最大权重（≤0.12 铁律，防止袍面糊亮）
const SHEEN_INTENSITY := 0.10
## 竹节亮带在正弦波峰处的聚集锐度（幂次越高节线越清晰收敛）
const BAMBOO_NODE_POWER := 3.0

# ----------------- 缘边亮带上推常量 -----------------
## 缘边亮带上推周期的秒数（约 3.0 秒自下而上扫过一遍）
const RIM_CYCLE_SECONDS := 3.0
## 缘边亮带沿 y 轴的空间波长缩放（让身长内约容纳 1~1.5 道波峰）
const RIM_Y_FREQ := 0.14
## 缘边亮区的基础线宽增量（相较 base_w 的偏移）
const RIM_WIDTH_OFFSET := 0.50
## 缘边暗区与亮区的最小/最大 alpha
const RIM_ALPHA_MIN := 0.20
const RIM_ALPHA_MAX := 0.85

# ----------------- 上浮青屑粒子常量 -----------------
## 青屑上浮垂直循环总周期（秒）
const MOTE_RISE_CYCLE := 3.6
## 青屑垂直上浮总行程跨度（像素）
const MOTE_RISE_SPAN := 36.0
## 青屑垂直基准底部起始 y 偏移（像素）
const MOTE_BOTTOM_Y := 22.0
## 青屑拖尾垂直长度（像素，极短拖尾）
const MOTE_TAIL_LEN := 2.6
## 青屑水平摆动幅度（像素）
const MOTE_SWAY_X := 13.0


## 族默认参数：SkinData 主题只需写 kind: "jade"，默认行为均在此集中定义
static func defaults() -> Dictionary:
	return {
		"cycle": 6.0,
		"node_freq": BAMBOO_NODE_FREQ,
		"sheen": SHEEN_INTENSITY,
		"rim_cycle": RIM_CYCLE_SECONDS,
		"rim_y_freq": RIM_Y_FREQ,
		"mote_cycle": MOTE_RISE_CYCLE,
	}


## 重绘前钩子：苍竹维持原生沉潭青/青玉碧纯色底，不更改缓存基准色
static func on_frame(_h, _p: Dictionary) -> void:
	pass


## 袍面叠竹节纹：沿 y 轴等距分布的水平亮带，混入强度 ≤0.12 保留深潭青袍底
static func cloak_sheen(h, base: Color, pt: Vector2, p: Dictionary) -> Color:
	var freq: float = float(p.get("node_freq", BAMBOO_NODE_FREQ))
	var wave: float = sin(pt.y * freq)
	if wave <= 0.0:
		return base
	var band: float = pow(wave, BAMBOO_NODE_POWER)
	var max_sheen: float = clampf(float(p.get("sheen", SHEEN_INTENSITY)), 0.0, 0.12)
	var inner_base: Color = h._fx_base.get("cloak_inner", Color(0.14, 0.42, 0.38))
	var node_col: Color = inner_base.lightened(0.28)
	return base.lerp(node_col, max_sheen * band)


## 缘边竹节亮带自下而上推移：沿轮廓逐顶点画青翠描边，亮度峰值随时间从下往上扫
static func draw_rim(h, pts: PackedVector2Array, base_w: float, p: Dictionary) -> void:
	var cn := pts.size()
	if cn < 2:
		return
	var time: float = h._time
	var rim_cycle: float = maxf(float(p.get("rim_cycle", RIM_CYCLE_SECONDS)), 0.5)
	var phase: float = fposmod(time / rim_cycle, 1.0)
	var y_freq: float = float(p.get("rim_y_freq", RIM_Y_FREQ))
	var edge_base: Color = h._fx_base.get("cloak_edge", Color(0.46, 0.90, 0.74))

	var rim_cols := PackedColorArray()
	rim_cols.resize(cn)
	for i in range(cn):
		var pt := pts[i]
		# 相位波峰随时间向上移动（y 越小，需要 phase 越大来匹配波峰）
		var wave: float = 0.5 + 0.5 * cos(pt.y * y_freq + phase * TAU)
		var peak: float = pow(wave, 2.5)
		var alpha: float = lerpf(RIM_ALPHA_MIN, RIM_ALPHA_MAX, peak)
		var col: Color = edge_base.lightened(0.20 * peak)
		col.a = alpha
		rim_cols[i] = col

	h.draw_polyline_colors(pts, rim_cols, base_w + RIM_WIDTH_OFFSET, true)


## 常驻粒子：2 颗青屑上浮循环，带极短拖尾
static func draw_motes(h, float_y: float, p: Dictionary) -> void:
	var time: float = h._time
	var idle_phase: float = h._idle_phase
	var width_scale: float = h.width_scale
	var edge_base: Color = h._fx_base.get("cloak_edge", Color(0.46, 0.90, 0.74))
	var cycle: float = maxf(float(p.get("mote_cycle", MOTE_RISE_CYCLE)), 0.5)

	var bottom_y: float = MOTE_BOTTOM_Y + float_y
	var top_y: float = bottom_y - MOTE_RISE_SPAN

	# 2 颗青屑（严格 ≤ 3 颗性能红线）
	for i in range(2):
		var t_mote: float = time + float(i) * (cycle * 0.5) + idle_phase * 0.4
		var prog: float = fposmod(t_mote / cycle, 1.0)
		# 垂直平滑上升 + 微弱正弦波浮动
		var my: float = lerpf(bottom_y, top_y, prog) + sin(t_mote * 2.4) * 2.0
		# 水平左右周期性摇曳
		var side_sign: float = -1.0 if i == 0 else 1.0
		var mx: float = (sin(t_mote * 1.6 + float(i) * 1.8) * MOTE_SWAY_X + side_sign * 3.0) * width_scale
		# 两端平滑淡入淡出包络
		var envelope: float = sin(prog * PI)
		var alpha: float = envelope * 0.65
		if alpha <= 0.01:
			continue

		var radius: float = 1.3 if i == 0 else 1.1
		var mote_col := Color(edge_base.r, edge_base.g, edge_base.b, alpha)
		# 极短向下拖尾（速度方向向上，拖尾指向下方）
		var tail_x: float = cos(t_mote * 1.6 + float(i) * 1.8) * 0.8 * width_scale
		var tail_col := Color(edge_base.r, edge_base.g, edge_base.b, alpha * 0.45)
		h.draw_line(Vector2(mx, my), Vector2(mx - tail_x, my + MOTE_TAIL_LEN), tail_col, 1.0)
		h._circle(Vector2(mx, my), radius, mote_col)


## 眼柔光调整：原样返回（苍竹不收窄眼柔光）
static func eye_glow_adjust(_h, radius: float, col: Color, _p: Dictionary) -> Dictionary:
	return {"radius": radius, "color": col}
