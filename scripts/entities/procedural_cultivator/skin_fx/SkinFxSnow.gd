extends RefCounted

## 霜华族（素白清冷系列）：冰川寒玉，素白出尘 —— 霜纹/冷芒/雪晶。
##
## 关键难点：这套是浅色系，容易在骨白面壳上糊成一团白。
## 效果必须强调"冷"、"对比"与"晶体感"，不能靠单纯堆叠亮度。
##
## 三条实现要点：
## ① 袍面霜纹双向调制：亮处微提并润冰蓝、暗处压暗雕刻凹凸霜脉，幅度严格控制在 0.10 以内，防白袍过曝。
## ② 缘边冰蓝冷光横扫：单向中速平滑扫过轮廓，两端平滑羽化，以冰蓝寒芒勾勒冷感轮廓。
## ③ 周天雪晶十字下落：恒定 3 颗微晶，沿小圆轨道自旋并自上而下循环飘落，中心微圆+四向细芒。

const SkinFxCommon = preload("res://scripts/entities/procedural_cultivator/skin_fx/SkinFxCommon.gd")

# ----------------- 默认参数常量 -----------------

## 整体时间周期基准（秒）
const DEFAULT_CYCLE := 6.0

## 袍面霜纹明暗调制幅度（≤0.10，亮处微提、暗处压暗）
const SHEEN_AMP := 0.085
## 霜纹空间频率 X 步进（斜向密集细纹）
const SHEEN_DX := 0.075
## 霜纹空间频率 Y 步进
const SHEEN_DY := 0.055
## 霜纹亮棱冰蓝冷光润色
const FROST_TINT := Color(0.85, 0.94, 1.0)
## 霜纹润色混合比
const FROST_TINT_BLEND := 0.35

## 缘边冷光横扫速度（圈/秒）
const SWEEP_SPEED := 0.18
## 横扫亮区半宽（顶点数，两端各 5 个顶点，总长 11 顶点）
const COMET_HALF := 5
## 横扫冷光线宽相对基础描边的增量
const RIM_WIDTH_EXTRA := 0.6
## 冰蓝寒芒基础色相（~206° 冰蓝冷青）
const RIM_HUE := 0.57
## 冰蓝寒芒微小色相展开（保持在纯冰青区间，不偏绿不偏紫）
const RIM_SPREAD := 0.003
## 冰蓝寒芒饱和度
const RIM_SAT := 0.32
## 冰蓝寒芒亮度
const RIM_VAL := 1.0
## 冰蓝寒芒中心不透明度
const RIM_ALPHA := 0.45

## 雪晶总数量（硬性纪律：≤ 3 颗）
const MOTE_COUNT := 3
## 雪晶垂直循环下落速度（圈/秒）
const MOTE_FALL_SPEED := 0.22
## 雪晶垂直循环跨度（px，从头顶至足下阴影）
const MOTE_FALL_SPAN := 44.0
## 雪晶垂直起始基准偏移（px）
const MOTE_Y_TOP := -16.0
## 雪晶自旋与轨道角速度（弧度/秒）
const MOTE_SPIN_SPEED := 3.2
## 雪晶十字臂长（px，单侧长度 2.2px，总翼展 ~4.4px）
const MOTE_ARM_LEN := 2.2
## 雪晶十字线宽（px）
const MOTE_LINE_WIDTH := 1.0
## 雪晶中心小圆半径（px）
const MOTE_CENTER_RADIUS := 0.8
## 雪晶冰白基础色（近白微蓝）
const MOTE_COLOR := Color(0.92, 0.97, 1.0)
## 雪晶最大基准不透明度
const MOTE_BASE_ALPHA := 0.85

## 3 枚雪晶的空间与相位配置（静态无随机数组：X 偏置、下落错相、轨道半径 X/Y、自旋错相、旋转方向）
const MOTE_CONFIGS: Array[Dictionary] = [
	{
		"base_x": -13.0,
		"fall_phase": 0.0,
		"orbit_rx": 3.8,
		"orbit_ry": 3.2,
		"spin_phase": 0.0,
		"rot_dir": 1.0,
	},
	{
		"base_x": 4.0,
		"fall_phase": 0.36,
		"orbit_rx": 4.5,
		"orbit_ry": 3.6,
		"spin_phase": 2.1,
		"rot_dir": -1.0,
	},
	{
		"base_x": 12.5,
		"fall_phase": 0.72,
		"orbit_rx": 3.5,
		"orbit_ry": 4.2,
		"spin_phase": 4.3,
		"rot_dir": 1.0,
	},
]

## 眼睛柔光半径缩放（收窄至 0.70）
const EYE_GLOW_RADIUS_MUL := 0.70
## 眼睛柔光提亮混合比（向纯白插值 0.30）
const EYE_GLOW_WHITEN := 0.30
## 眼睛提亮目标纯白微蓝
const EYE_TARGET_COLOR := Color(0.98, 0.99, 1.0)

# ----------------- 6 个静态接口 -----------------

## 族默认参数：SkinData 主题只需写 kind + 想偏离默认的键
static func defaults() -> Dictionary:
	return {
		"cycle": DEFAULT_CYCLE,
		"sheen_amp": SHEEN_AMP,
		"sheen_dx": SHEEN_DX,
		"sheen_dy": SHEEN_DY,
		"sweep_speed": SWEEP_SPEED,
		"comet_half": COMET_HALF,
		"rim_alpha": RIM_ALPHA,
		"mote_fall_speed": MOTE_FALL_SPEED,
		"eye_glow_radius_mul": EYE_GLOW_RADIUS_MUL,
		"eye_glow_whiten": EYE_GLOW_WHITEN,
	}

## 重绘前钩子：霜华族使用固定素白与冰蓝基准色，无需随时间重算颜色缓存
static func on_frame(_h, _p: Dictionary) -> void:
	pass

## 袍面叠斜向霜纹：利用正弦波调制明暗双向细纹，亮处微提并润冰蓝，暗处压暗形成晶体凹凸，幅度严格 ≤0.10
static func cloak_sheen(h, base: Color, pt: Vector2, p: Dictionary) -> Color:
	var phase: float = SkinFxCommon.phase_of(h, p)
	var amp: float = float(p.get("sheen_amp", SHEEN_AMP))
	var dx: float = float(p.get("sheen_dx", SHEEN_DX))
	var dy: float = float(p.get("sheen_dy", SHEEN_DY))

	# 斜向密集正弦细纹（-1.0 ~ 1.0）
	var wave: float = sin((pt.x * dx + pt.y * dy + phase) * TAU)
	if wave >= 0.0:
		var lit: Color = base.lightened(wave * amp)
		return lit.lerp(FROST_TINT, wave * amp * FROST_TINT_BLEND)
	else:
		return base.darkened(-wave * amp)

## 缘边冰蓝冷光横扫：沿轮廓逐顶点画寒芒描边，一段亮区随时间单向平滑扫过轮廓，两端羽化
static func draw_rim(h, pts: PackedVector2Array, base_w: float, p: Dictionary) -> void:
	var cn: int = pts.size()
	if cn < 2:
		return
	var cur_time: float = float(h._time)
	var idle_p: float = float(h._idle_phase)
	var sweep_spd: float = float(p.get("sweep_speed", SWEEP_SPEED))
	var sweep_progress: float = fposmod(cur_time * sweep_spd + idle_p * 0.05, 1.0)
	var comet_center: int = int(sweep_progress * float(cn))
	var half: int = int(p.get("comet_half", COMET_HALF))

	var edge_base: Color = h._fx_base.get("cloak_edge", Color(0.72, 0.92, 1.0))
	var edge_h: float = edge_base.h if edge_base.s > 0.01 else RIM_HUE
	var rim_alpha: float = float(p.get("rim_alpha", RIM_ALPHA))

	var seg: Array = SkinFxCommon.comet_segments(
		pts,
		comet_center,
		half,
		edge_h,
		0.0,
		RIM_SPREAD,
		RIM_SAT,
		RIM_VAL,
		rim_alpha
	)
	var comet_pts: PackedVector2Array = seg[0]
	var comet_cols: PackedColorArray = seg[1]

	# 柔化两端羽化：中间饱满、两端平滑归零，防亮带首尾硬切
	var seg_count: int = comet_cols.size()
	var half_f: float = float(half)
	for i in range(seg_count):
		var dist: float = absf(float(i - half)) / maxf(half_f, 1.0)
		var feather: float = clampf(1.0 - dist * dist, 0.0, 1.0)
		comet_cols[i].a *= feather

	if comet_pts.size() >= 2:
		h.draw_polyline_colors(comet_pts, comet_cols, base_w + RIM_WIDTH_EXTRA, true)

## 周天 3 枚雪晶旋转下落：沿小圆轨道旋转，同时 y 方向循环下落，绘制为十字小晶（中心小圆 + 短十字线）
static func draw_motes(h, float_y: float, p: Dictionary) -> void:
	var cur_time: float = float(h._time)
	var idle_p: float = float(h._idle_phase)
	var ws: float = float(h.width_scale) if "width_scale" in h else 1.0
	var fall_spd: float = float(p.get("mote_fall_speed", MOTE_FALL_SPEED))

	for i in range(MOTE_COUNT):
		var cfg: Dictionary = MOTE_CONFIGS[i]
		var base_x: float = float(cfg["base_x"]) * ws
		var fall_phase: float = float(cfg["fall_phase"])
		var orbit_rx: float = float(cfg["orbit_rx"])
		var orbit_ry: float = float(cfg["orbit_ry"])
		var spin_phase: float = float(cfg["spin_phase"])
		var rot_dir: float = float(cfg["rot_dir"])

		# 垂直缓慢下落循环：连续时间推进使 fall_progress 从 0 增至 1，自上而下漂落
		var fall_progress: float = fposmod(cur_time * fall_spd + fall_phase + idle_p * 0.08, 1.0)
		var fall_y: float = MOTE_Y_TOP + fall_progress * MOTE_FALL_SPAN

		# 小圆轨道旋转（sin/cos 双轴）
		var spin_t: float = cur_time * MOTE_SPIN_SPEED * rot_dir + spin_phase + idle_p * 0.15
		var ox: float = cos(spin_t) * orbit_rx
		var oy: float = sin(spin_t) * orbit_ry

		var center_pos: Vector2 = Vector2(base_x + ox, fall_y + oy + float_y)

		# 上下两端羽化淡入淡出，防循环接缝跳变
		var edge_fade: float = sin(fall_progress * PI)
		var alpha: float = MOTE_BASE_ALPHA * edge_fade
		if alpha <= 0.01:
			continue

		var cur_col: Color = Color(MOTE_COLOR.r, MOTE_COLOR.g, MOTE_COLOR.b, alpha)

		# 1. 中心微圆
		h._circle(center_pos, MOTE_CENTER_RADIUS, cur_col)

		# 2. 十字微晶（两条短十字线，随旋转角自旋）
		var rot_angle: float = spin_t * 0.75
		var arm1: Vector2 = Vector2(cos(rot_angle), sin(rot_angle)) * MOTE_ARM_LEN
		var arm2: Vector2 = Vector2(-sin(rot_angle), cos(rot_angle)) * MOTE_ARM_LEN
		h.draw_line(center_pos - arm1, center_pos + arm1, cur_col, MOTE_LINE_WIDTH, true)
		h.draw_line(center_pos - arm2, center_pos + arm2, cur_col, MOTE_LINE_WIDTH, true)

## 眼柔光调整：收窄光晕半径至 0.70，颜色向纯白提亮 0.30，保持 alpha 不动
static func eye_glow_adjust(_h, radius: float, col: Color, p: Dictionary) -> Dictionary:
	var rad_mul: float = float(p.get("eye_glow_radius_mul", EYE_GLOW_RADIUS_MUL))
	var whiten: float = float(p.get("eye_glow_whiten", EYE_GLOW_WHITEN))
	var target_col: Color = Color(EYE_TARGET_COLOR.r, EYE_TARGET_COLOR.g, EYE_TARGET_COLOR.b, col.a)
	return {
		"radius": radius * rad_mul,
		"color": col.lerp(target_col, whiten),
	}
