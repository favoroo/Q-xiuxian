extends RefCounted

## 鎏金族（玄衣金缕）：金属反光质感 —— 刃身同步闪光、袍面金属窄高光、金色高速游走扫光、周身金屑闪烁上浮。
##
## 关键美学铁律：
## 金属反光不是发光！金属的本质特征是「锐利的高光窄带快速扫过 + 大部分表面是暗的」。
## 绝不能画成"整条边都在发光"——那看起来像塑料管，完全丧失金属质感。
##
## 三条实现要点：
## ① 刃身同步闪光与金属高光：h.col_weapon_main 与 h.col_weapon_accent 严格同相位提亮（周期约 2.6s，
##    幅度 ≤0.18，向白金色聚拢），赋予武器锐利冷硬的金属反光；袍面叠高阶幂函数窄峰（pow(sin, 6)），
##    混入强度 ≤0.14，高光宽度仅占袍宽 15~20%，绝不大面积发亮。
## ② 金色扫光高速掠过：缘边大部分轮廓保持沉稳暗铜金微光，同时用 comet_segments 画一段高速（speed 约 0.52）
##    金芒光段（half=3~4，sat≥0.85，alpha 上限 0.9），形成强烈的金属反光快速划过的掠影。
## ③ 金粉闪烁上浮：严格限制 3 颗金屑沿 y 向上循环漂移，零随机确定性轨道；各粒子以 0.5~0.8s 错相高频
##    正弦忽明忽暗闪烁，配合极短拖尾，模拟细碎金粉在空气中翻转折光的璀璨动态。

const SkinFxCommon = preload("res://scripts/entities/procedural_cultivator/skin_fx/SkinFxCommon.gd")

# ----------------- 默认与动画周期常量 -----------------

## 基础循环周期基准（秒）
const DEFAULT_CYCLE: float = 6.0

# ----------------- 刃身金属闪光常量 -----------------

## 武器闪光周期（秒，约 2.6s 闪烁一次）
const WEAPON_CYCLE: float = 2.6
## 武器向白金色提亮的最大幅度（≤0.18 铁律）
const WEAPON_FLASH_AMP: float = 0.16
## 闪光高光聚集幂次（锐利闪光）
const WEAPON_GLINT_POWER: float = 3.0
## 白金高光目标基色
const WHITE_GOLD: Color = Color(1.0, 0.98, 0.90)

# ----------------- 袍面金属高光常量 -----------------

## 袍面金属高光带最大混入强度（≤0.14 铁律）
const SHEEN_INTENSITY: float = 0.13
## 袍面高光聚集锐度（6 次幂窄峰，使高光宽度紧凑收拢在袍宽 15~20%）
const SHEEN_POWER: float = 6.0
## 袍面高光斜向 X 空间步进
const SHEEN_DX: float = 0.024
## 袍面高光斜向 Y 空间步进
const SHEEN_DY: float = 0.018

# ----------------- 缘边高速扫光常量 -----------------

## 缘边基础暗铜金轮廓线宽偏移（px）
const RIM_BASE_WIDTH_ADD: float = 0.4
## 缘边基础暗金轮廓最小/最大透明度（暗淡克制）
const RIM_BASE_ALPHA_MIN: float = 0.18
const RIM_BASE_ALPHA_MAX: float = 0.32
## 缘边高速扫光段速度（圈/秒，约 0.45~0.60 高速区间）
const COMET_SPEED: float = 0.52
## 扫光段单侧半长（顶点数，half=3~4）
const COMET_HALF: int = 3
## 扫光段线宽偏移（px）
const COMET_WIDTH_ADD: float = 1.1
## 扫光段饱和度（sat ≥ 0.85）
const RIM_SAT: float = 0.88
## 扫光段明度
const RIM_VAL: float = 1.0
## 扫光段中心最大透明度（≤0.90 铁律）
const RIM_ALPHA: float = 0.90
## 扫光段色相展开（微小展开，保持纯正金色）
const RIM_SPREAD: float = 0.002

# ----------------- 金屑闪烁粒子常量 -----------------

## 金屑粒子数量上限（硬性性能红线：≤ 3 颗）
const MOTE_COUNT: int = 3
## 金屑上浮垂直循环总周期（秒）
const MOTE_CYCLE: float = 2.8
## 金屑垂直循环行程跨度（px）
const MOTE_SPAN_Y: float = 36.0
## 金屑垂直起点 Y 偏移（px）
const MOTE_BOTTOM_Y: float = 20.0
## 极短拖尾向下长度（px）
const MOTE_TAIL_LEN: float = 2.0

## 3 颗金屑的静态配置：基准 X 偏移、垂直上浮相位偏移、闪烁周期（0.5~0.8s）、闪烁错相、基准半径（1.0~1.5px）
const MOTE_CONFIGS: Array[Dictionary] = [
	{
		"base_x": -10.5,
		"rise_phase": 0.0,
		"sparkle_period": 0.58,
		"sparkle_phase": 0.0,
		"base_radius": 1.3,
		"sway_freq": 2.1,
		"sway_amp": 2.8,
	},
	{
		"base_x": 3.0,
		"rise_phase": 0.36,
		"sparkle_period": 0.72,
		"sparkle_phase": 2.4,
		"base_radius": 1.1,
		"sway_freq": 2.6,
		"sway_amp": 2.4,
	},
	{
		"base_x": 11.0,
		"rise_phase": 0.73,
		"sparkle_period": 0.64,
		"sparkle_phase": 4.5,
		"base_radius": 1.4,
		"sway_freq": 1.9,
		"sway_amp": 3.0,
	},
]


# ----------------- 6 个静态接口 -----------------

## 族默认参数：SkinData 主题只需写 kind: "gold"，默认参数均在此集中定义
static func defaults() -> Dictionary:
	return {
		"cycle": DEFAULT_CYCLE,
		"weapon_cycle": WEAPON_CYCLE,
		"weapon_flash_amp": WEAPON_FLASH_AMP,
		"sheen": SHEEN_INTENSITY,
		"sheen_power": SHEEN_POWER,
		"sheen_dx": SHEEN_DX,
		"sheen_dy": SHEEN_DY,
		"comet_speed": COMET_SPEED,
		"comet_half": COMET_HALF,
		"rim_sat": RIM_SAT,
		"rim_val": RIM_VAL,
		"rim_alpha": RIM_ALPHA,
		"mote_cycle": MOTE_CYCLE,
	}


## 重绘前钩子：刃身与装饰同相位提亮，向白金色聚拢闪烁，赋予金属高光感
static func on_frame(h, p: Dictionary) -> void:
	var base_dict: Dictionary = h._fx_base
	var base_main: Color = base_dict.get("weapon_main", Color(1.0, 0.93, 0.72))
	var base_accent: Color = base_dict.get("weapon_accent", Color(1.0, 0.85, 0.35, 0.9))
	var time: float = float(h._time)
	var weapon_cycle: float = maxf(float(p.get("weapon_cycle", WEAPON_CYCLE)), 0.1)
	var flash_amp: float = clampf(float(p.get("weapon_flash_amp", WEAPON_FLASH_AMP)), 0.0, 0.18)

	# 周期约 2.6s，利用幂函数提取出尖锐的闪烁波峰（金属高光闪耀）
	var flash_wave: float = sin(time * (TAU / weapon_cycle))
	if flash_wave <= 0.0:
		h.col_weapon_main = base_main
		h.col_weapon_accent = base_accent
		return

	var glint: float = pow(flash_wave, WEAPON_GLINT_POWER)
	var flash_ratio: float = glint * flash_amp
	h.col_weapon_main = base_main.lerp(WHITE_GOLD, flash_ratio)
	var lit_accent: Color = base_accent.lerp(WHITE_GOLD, flash_ratio)
	lit_accent.a = base_accent.a
	h.col_weapon_accent = lit_accent


## 袍面叠金属窄高光：斜向扫过高阶窄峰（pow(sin, 6)），混入强度 ≤0.14，高光占袍宽 15~20%
static func cloak_sheen(h, base: Color, pt: Vector2, p: Dictionary) -> Color:
	var phase: float = SkinFxCommon.phase_of(h, p)
	var dx: float = float(p.get("sheen_dx", SHEEN_DX))
	var dy: float = float(p.get("sheen_dy", SHEEN_DY))
	var wave: float = sin((pt.x * dx + pt.y * dy - phase) * TAU)
	if wave <= 0.0:
		return base

	var power: float = float(p.get("sheen_power", SHEEN_POWER))
	var band: float = pow(wave, power)
	var sheen_max: float = clampf(float(p.get("sheen", SHEEN_INTENSITY)), 0.0, 0.14)
	var edge_base: Color = h._fx_base.get("cloak_edge", Color(1.0, 0.80, 0.30))
	return base.lerp(edge_base, sheen_max * band)


## 缘边金色扫光高速游走：逐顶点暗铜金底色描边 + 高速金芒游走光段
static func draw_rim(h, pts: PackedVector2Array, base_w: float, p: Dictionary) -> void:
	var cn: int = pts.size()
	if cn < 2:
		return

	var edge_base: Color = h._fx_base.get("cloak_edge", Color(1.0, 0.80, 0.30))

	# 1. 逐顶点描边：暗金古铜低调勾勒，保持大部分轮廓暗淡沉稳（alpha ≤ 0.32），绝不整圈塑料发光
	var rim_cols: PackedColorArray = PackedColorArray()
	rim_cols.resize(cn)
	for i in range(cn):
		var pt_y: float = pts[i].y
		var y_fade: float = clampf((pt_y + 6.0) / 36.0, 0.0, 1.0)
		var c: Color = edge_base.darkened(0.40 + 0.15 * y_fade)
		c.a = lerpf(RIM_BASE_ALPHA_MAX, RIM_BASE_ALPHA_MIN, y_fade)
		rim_cols[i] = c
	h.draw_polyline_colors(pts, rim_cols, base_w + RIM_BASE_WIDTH_ADD, true)

	# 2. 高速金属光斑掠过（速度 0.45~0.60，half=3~4，高饱和高亮）
	var time: float = float(h._time)
	var idle_phase: float = float(h._idle_phase)
	var comet_speed: float = float(p.get("comet_speed", COMET_SPEED))
	var comet_center: int = int(fposmod(time * comet_speed + idle_phase * 0.05, 1.0) * float(cn))
	var half: int = int(p.get("comet_half", COMET_HALF))
	var rim_sat: float = clampf(float(p.get("rim_sat", RIM_SAT)), 0.85, 1.0)
	var rim_val: float = float(p.get("rim_val", RIM_VAL))
	var rim_alpha: float = clampf(float(p.get("rim_alpha", RIM_ALPHA)), 0.0, 0.90)

	var seg: Array = SkinFxCommon.comet_segments(
		pts,
		comet_center,
		half,
		edge_base.h,
		0.0,
		RIM_SPREAD,
		rim_sat,
		rim_val,
		rim_alpha
	)
	var comet_pts: PackedVector2Array = seg[0]
	var comet_cols: PackedColorArray = seg[1]

	# 两端平滑二次羽化衰减，使金属高光两端柔和收敛，中心聚光最亮
	var seg_count: int = comet_cols.size()
	var half_f: float = float(half)
	for i in range(seg_count):
		var dist: float = absf(float(i - half)) / maxf(half_f, 1.0)
		var feather: float = clampf(1.0 - dist * dist, 0.0, 1.0)
		comet_cols[i].a *= feather

	if comet_pts.size() >= 2:
		h.draw_polyline_colors(comet_pts, comet_cols, base_w + COMET_WIDTH_ADD, true)


## 常驻粒子：3 颗金屑闪烁上浮，各颗高频忽明忽暗错相闪动，带极短拖尾
static func draw_motes(h, float_y: float, p: Dictionary) -> void:
	var edge_base: Color = h._fx_base.get("cloak_edge", Color(1.0, 0.80, 0.30))
	var time: float = float(h._time)
	var idle_phase: float = float(h._idle_phase)
	var ws: float = float(h.width_scale) if "width_scale" in h else 1.0
	var cycle: float = maxf(float(p.get("mote_cycle", MOTE_CYCLE)), 0.5)

	var bottom_y: float = MOTE_BOTTOM_Y + float_y
	var top_y: float = bottom_y - MOTE_SPAN_Y

	for i in range(MOTE_COUNT):
		var cfg: Dictionary = MOTE_CONFIGS[i]
		var rise_phase: float = float(cfg["rise_phase"])
		var prog: float = fposmod(time / cycle + rise_phase + idle_phase * 0.08, 1.0)
		var my: float = lerpf(bottom_y, top_y, prog)

		var base_x: float = float(cfg["base_x"]) * ws
		var sway_freq: float = float(cfg["sway_freq"])
		var sway_amp: float = float(cfg["sway_amp"])
		var mx: float = base_x + sin(time * sway_freq + rise_phase * TAU) * sway_amp

		# 上浮全行程两端平滑淡入淡出包络
		var envelope: float = sin(prog * PI)

		# 核心闪烁：周期 0.5~0.8s 的高频正弦忽明忽暗（金粉翻转折光）
		var sp_period: float = float(cfg["sparkle_period"])
		var sp_phase: float = float(cfg["sparkle_phase"])
		var sp_wave: float = sin(time * (TAU / sp_period) + sp_phase + idle_phase * 0.4)
		var sparkle: float = pow(0.5 + 0.5 * sp_wave, 2.0)
		var flash_alpha: float = lerpf(0.12, 0.95, sparkle)

		var final_alpha: float = envelope * flash_alpha
		if final_alpha <= 0.02:
			continue

		# 闪光峰值向亮白金提亮
		var mote_col: Color = edge_base.lerp(WHITE_GOLD, sparkle * 0.40)
		mote_col.a = final_alpha

		var base_radius: float = float(cfg["base_radius"])
		var r: float = clampf(base_radius + (sparkle - 0.5) * 0.3, 1.0, 1.5)

		# 极短向下拖尾（速度向上，拖尾留于下方）
		var tail_col: Color = Color(edge_base.r, edge_base.g, edge_base.b, final_alpha * 0.40)
		h.draw_line(Vector2(mx, my), Vector2(mx, my + MOTE_TAIL_LEN), tail_col, 1.0)
		h._circle(Vector2(mx, my), r, mote_col)


## 眼柔光调整：金光不需要收窄眼柔光，金色眼睛本就该亮，原样返回
static func eye_glow_adjust(_h, radius: float, col: Color, _p: Dictionary) -> Dictionary:
	return {"radius": radius, "color": col}
