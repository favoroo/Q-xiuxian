class_name ProceduralDroneRenderer
extends Node2D

## 纯矢量环绕灵宝渲染器（冷冽国风）
## 为御灵系道具（灵蝶、寒泉玉莲、混元钟）提供细腻的自转、振翅与流光视觉
## 核心起辉（2026-10-15 T-2.7）：各形态「核心一眼点」（中心亮点/灵蕊/灯焰/符印等小面积
## 最亮层）接 GameStyle.FX_HDR 五行/通用超白低档 —— 分量 >1.0 触发 WorldEnvironment
## glow 自动泛光，零额外开销。大面积本体一律保持 LDR 原色：环绕体多只同屏，
## 全体起辉会糊成一团，只让每只灵宝的中心点发光提辨识度。

enum DroneKind {
	LINGDIE,        ## 灵蝶：碧翠灵羽、生机透光羽翼、双翅轻盈扑动
	HANQUAN_YULIAN, ## 寒泉玉莲：晶莹冰魄青莲、层叠八瓣寒晶、中央灵蕊
	HUNYUAN_ZHONG,  ## 混元钟：玄铁青铜古钟、暗金饕餮符印、钟首盘龙纽
	HAOJIN_LUN,     ## 昊金轮：旋转金轮、辐条流光（2026-10-10 新增）
	LIHUO_YA,       ## 离火鸦：火羽扑翼、焰尾曳光（2026-10-10 新增）
	XUANWU_PEI,     ## 玄武佩：玄黄玉璧、云纹护身（2026-10-10 新增）
	YUAN_LING,      ## 灵珑：祭坛召唤灵兽，圆形灵魄真身 + 祭纹金印（2026-10-15 由圆团玄鹤重做：去鹤形、按圆形设计）
	JINMING_LING,   ## 金鸣铃：悬空金铃、铃舌摆鸣、云雷符纹（2026-10-11 第二批）
	MULING_OU,      ## 木灵偶：青木偶人、灵藤关节、生机符印（2026-10-11 第二批）
	BINGPO_ZHU,     ## 冰魄珠：寒冰宝珠、冰晶棱片、雪亮冰核（2026-10-11 第二批）
	CHIYAN_YING,    ## 赤炎萤：流火萤虫、薄透火翼、尾腹火光（2026-10-11 第二批）
	TULING_SHI,     ## 土灵石：符文灵石、山岩棱面、镇岳古符（2026-10-11 第二批）
	JIAN_LING       ## 剑灵：半透明剑形精魂、灵气飘带（2026-10-11 第二批）
}

@export var kind: DroneKind = DroneKind.LINGDIE
@export var star: int = 1

## 速度权重（0=悬停 1=全速）：仅灵珑（YUAN_LING）消费，由宿主按实际移速灌入，
## 驱动绒羽摆幅 / 灵纹转速 / 尾后移动灵尘
var speed_ratio: float = 0.0

## 侧倾角（弧度）：仅灵珑消费 —— 按朝向系下的横向走位 bank，只倾圆面装饰组（晕圈/足雾不随动）；
## 宿主按 velocity.x * 朝向符号 归一灌入，左右镜像由 scale.x 承担
var bank_angle: float = 0.0

## 生命比（0..1）：仅灵珑消费，由宿主（SpiritBeast）灌入 —— 灵兽不挂血条，
## 生命全由本体传达：驱动灵光晕圈/祭纹灵印/灵目明暗，低于 30% 圆面浮现裂纹与灵息闪烁
var hp_ratio: float = 1.0

## 蓄力比（0..1）：仅灵珑消费，由宿主（SpiritBeast）三连灵羽弹蓄力灌入 ——
## 面前灵光球随蓄力涨大发亮，连发时随剩余发数递减（余辉）
var charge_ratio: float = 0.0

## 出场辉光（1→0 自减）：仅灵珑消费，宿主（SpiritBeast）召唤出场时灌 1 ——
## 晕圈强闪 + 环绕灵尘从外圈向本体收拢，衔接祭坛冲击环的「现身」一拍
var spawn_glow: float = 0.0

var _anim_time: float = 0.0

## —— 重绘节流（2026-10-11 性能优化，2026-10-10/11 节流扫荡的漏网之鱼）——
## 环绕灵宝矢量 _draw 一帧几十条指令，「武器一多」时多只灵宝每帧全量重绘
## 是渲染线程热点。与 HollowKnightEnemyRenderer 同款：20Hz 节流 + 实例错相；
## _anim_time 照常逐帧推进，回绘时动画相位连续。灵宝环绕玩家永在屏内，无需屏外剔除。
## 60fps 档（2026-10-15 VisualRate 档位联动）翻倍到 40Hz：灵宝位置 60fps 环绕、
## 画面 3 帧一画会分离；低档 20Hz 维持 perf_probe 预算口径。
const HZ_LOW := 20.0               ## 省电档重绘频率
const HZ_HIGH := 40.0              ## 流畅档重绘频率
static var redraw_count: int = 0  ## 重绘发放计数（tests/PerfProbe 断言用）

static func _redraw_interval() -> float:
	return VisualRate.interval(HZ_HIGH, HZ_LOW)

var _draw_phase: float = 0.0      ## 距下次重绘的剩余时间（错相载体）

func _ready() -> void:
	# 错相：instance_id 派生初值（不碰玩法随机），多只灵宝的重绘摊到不同帧
	_draw_phase = fposmod(float(get_instance_id() % 97) * 0.001, _redraw_interval())

func _process(delta: float) -> void:
	_anim_time += delta
	spawn_glow = maxf(0.0, spawn_glow - delta / 0.35)
	if _draw_phase <= 0.0:
		_draw_phase = _redraw_interval()
		redraw_count += 1
		queue_redraw()
	else:
		_draw_phase -= delta

func _draw() -> void:
	match kind:
		DroneKind.LINGDIE:
			_draw_spirit_butterfly()
		DroneKind.HANQUAN_YULIAN:
			_draw_ice_lotus()
		DroneKind.HUNYUAN_ZHONG:
			_draw_ancient_bell()
		DroneKind.HAOJIN_LUN:
			_draw_golden_wheel()
		DroneKind.LIHUO_YA:
			_draw_fire_crow()
		DroneKind.XUANWU_PEI:
			_draw_jade_pendant()
		DroneKind.YUAN_LING:
			_draw_yuan_ling()
		DroneKind.JINMING_LING:
			_draw_golden_bell()
		DroneKind.MULING_OU:
			_draw_wood_puppet()
		DroneKind.BINGPO_ZHU:
			_draw_ice_pearl()
		DroneKind.CHIYAN_YING:
			_draw_fire_firefly()
		DroneKind.TULING_SHI:
			_draw_earth_stone()
		DroneKind.JIAN_LING:
			_draw_sword_wisp()

# ----------------- 1. 灵蝶 (生机碧翠灵羽 + 振翅扑动) -----------------
func _draw_spirit_butterfly() -> void:
	# 振翅周期 (约 5Hz)
	var wing_flap := sin(_anim_time * 12.0)
	var flap_x := 0.4 + 0.6 * absf(wing_flap)

	var wing_col_base := Color(0.20, 0.65, 0.45, 0.75)
	var wing_col_edge := Color(0.55, 0.95, 0.75, 0.90)
	if star >= 2:
		wing_col_edge = Color(0.95, 0.85, 0.40, 0.95)

	# 左前翅
	var left_fore := PackedVector2Array([
		Vector2(0, 0),
		Vector2(-14.0 * flap_x, -12.0),
		Vector2(-12.0 * flap_x, -2.0),
		Vector2(-2.0, 2.0)
	])
	draw_colored_polygon(left_fore, wing_col_base)
	draw_polyline(left_fore, wing_col_edge, 1.2, true)

	# 右前翅
	var right_fore := PackedVector2Array([
		Vector2(0, 0),
		Vector2(14.0 * flap_x, -12.0),
		Vector2(12.0 * flap_x, -2.0),
		Vector2(2.0, 2.0)
	])
	draw_colored_polygon(right_fore, wing_col_base)
	draw_polyline(right_fore, wing_col_edge, 1.2, true)

	# 左后翅 (更小巧)
	var left_hind := PackedVector2Array([
		Vector2(0, 2.0),
		Vector2(-10.0 * flap_x, 6.0),
		Vector2(-7.0 * flap_x, 12.0),
		Vector2(0, 5.0)
	])
	draw_colored_polygon(left_hind, wing_col_base)
	draw_polyline(left_hind, wing_col_edge, 1.0, true)

	# 右后翅
	var right_hind := PackedVector2Array([
		Vector2(0, 2.0),
		Vector2(10.0 * flap_x, 6.0),
		Vector2(7.0 * flap_x, 12.0),
		Vector2(0, 5.0)
	])
	draw_colored_polygon(right_hind, wing_col_base)
	draw_polyline(right_hind, wing_col_edge, 1.0, true)

	# 蝶身脊柱与灵须（头部亮点接 FX_HDR_WOOD 起辉）
	draw_line(Vector2(0, -7.0), Vector2(0, 7.0), Color(0.10, 0.14, 0.18), 2.0, true)
	draw_circle(Vector2(0, -7.0), 1.6, Color(GameStyle.FX_HDR_WOOD, 0.9))
	# 触角
	draw_line(Vector2(0, -7.0), Vector2(-4.0, -11.0), Color(0.92, 0.95, 0.98), 0.8, true)
	draw_line(Vector2(0, -7.0), Vector2(4.0, -11.0), Color(0.92, 0.95, 0.98), 0.8, true)

# ----------------- 2. 寒泉玉莲 (晶莹冰魄层叠八瓣莲台) -----------------
func _draw_ice_lotus() -> void:
	var rot := _anim_time * 1.2
	var petals := 8
	var outer_r := 13.0
	var inner_r := 4.5

	# 外层八瓣青莲
	for i in range(petals):
		var ang := float(i) / float(petals) * TAU + rot
		var tip := Vector2(cos(ang) * outer_r, sin(ang) * outer_r)
		var left_ang := ang - 0.28
		var right_ang := ang + 0.28
		var side_l := Vector2(cos(left_ang) * (outer_r * 0.6), sin(left_ang) * (outer_r * 0.6))
		var side_r := Vector2(cos(right_ang) * (outer_r * 0.6), sin(right_ang) * (outer_r * 0.6))

		var poly := PackedVector2Array([Vector2.ZERO, side_l, tip, side_r])
		var col := Color(0.40, 0.75, 0.95, 0.65) if (i % 2 == 0) else Color(0.65, 0.90, 1.0, 0.85)
		draw_colored_polygon(poly, col)
		draw_polyline(PackedVector2Array([side_l, tip, side_r]), Color(0.95, 0.98, 1.0, 0.9), 1.0, false)

	# 内层灵蕊（内亮层接 HDR 低档起辉：★2+ 暖金档 / ★1 冰蓝档，保住星级冷暖差）
	draw_circle(Vector2.ZERO, inner_r, Color(0.20, 0.45, 0.70))
	draw_circle(Vector2.ZERO, inner_r * 0.5,
		Color(GameStyle.FX_HDR_METAL, 0.75) if star >= 2 else Color(GameStyle.FX_HDR_WATER, 0.65))

# ----------------- 3. 混元古钟 (玄铁青铜古钟 + 暗金云雷纹) -----------------
func _draw_ancient_bell() -> void:
	# 钟体轮廓 (上窄下阔梯形钟身)
	var bell_poly := PackedVector2Array([
		Vector2(-6.0, -9.0),
		Vector2(6.0, -9.0),
		Vector2(9.5, 6.0),
		Vector2(11.0, 9.0),
		Vector2(-11.0, 9.0),
		Vector2(-9.5, 6.0)
	])
	# 玄铁沉稳底色
	draw_colored_polygon(bell_poly, Color(0.18, 0.22, 0.28))
	# 边缘暗金/青铜包边
	draw_polyline(bell_poly, Color(0.78, 0.68, 0.35) if star >= 2 else Color(0.40, 0.55, 0.50), 1.4, true)

	# 钟钮 (顶部吊环)
	draw_arc(Vector2(0, -10.5), 3.0, PI, TAU, 8, Color(0.85, 0.75, 0.38), 1.5)

	# 钟腹云雷横纹
	draw_line(Vector2(-8.0, 0), Vector2(8.0, 0), Color(0.85, 0.75, 0.38, 0.8), 1.2, true)
	draw_line(Vector2(-7.0, -4.0), Vector2(7.0, -4.0), Color(0.85, 0.75, 0.38, 0.6), 1.0, true)

	# 钟口下沿口缘（接 FX_HDR_METAL 古金起辉，钟的「一眼金」）
	draw_line(Vector2(-11.0, 9.0), Vector2(11.0, 9.0), Color(GameStyle.FX_HDR_METAL, 0.85), 2.0, true)

# ----------------- 4. 昊金轮 (自转金轮 + 六辐流光) -----------------
func _draw_golden_wheel() -> void:
	var rot := _anim_time * 4.0
	var rim := Color(0.95, 0.80, 0.30) if star >= 2 else Color(0.72, 0.58, 0.22)
	# 六辐轮辐
	for i in range(6):
		var ang := float(i) / 6.0 * TAU + rot
		draw_line(Vector2.ZERO, Vector2(cos(ang) * 11.0, sin(ang) * 11.0), rim, 1.6, true)
	# 外轮圈与轴心（轴心亮盘接 FX_HDR_METAL 起辉）
	draw_arc(Vector2.ZERO, 11.0, 0, TAU, 24, rim, 2.2, true)
	draw_arc(Vector2.ZERO, 7.5, 0, TAU, 18, Color(GameStyle.FX_HDR_METAL, 0.35), 1.0, true)
	draw_circle(Vector2.ZERO, 3.0, Color(GameStyle.FX_HDR_METAL, 0.9))
	draw_circle(Vector2.ZERO, 1.4, Color(0.35, 0.26, 0.10))

# ----------------- 5. 离火鸦 (火羽扑翼 + 焰尾) -----------------
func _draw_fire_crow() -> void:
	var wing_flap := sin(_anim_time * 11.0)
	var flap_x := 0.45 + 0.55 * absf(wing_flap)
	var body := Color(0.45, 0.12, 0.08)
	var flame := Color(1.0, 0.55, 0.15, 0.85) if star < 2 else Color(1.0, 0.72, 0.25, 0.95)
	# 双翼（火羽）
	for side in [-1.0, 1.0]:
		var wing := PackedVector2Array([
			Vector2(0, -1.0),
			Vector2(side * 13.0 * flap_x, -9.0),
			Vector2(side * 10.0 * flap_x, 0.5),
			Vector2(side * 2.0, 2.5)
		])
		draw_colored_polygon(wing, Color(0.85, 0.35, 0.10, 0.80))
		draw_polyline(wing, flame, 1.1, true)
	# 焰尾三条（中条接 FX_HDR_FIRE 起辉，火是离火鸦的一眼点）
	for i in range(-1, 2):
		var sway := sin(_anim_time * 7.0 + float(i)) * 2.0
		draw_line(Vector2(float(i) * 2.5, 4.0), Vector2(float(i) * 3.5 + sway, 12.0),
			Color(GameStyle.FX_HDR_FIRE, 0.8) if i == 0 else flame, 1.4, true)
	# 鸦身与金目（金目接 FX_HDR_FIRE 低档起辉）
	draw_circle(Vector2.ZERO, 4.2, body)
	draw_circle(Vector2(0, -5.2), 2.2, body)
	draw_circle(Vector2(1.2, -5.8), 0.9, Color(GameStyle.FX_HDR_FIRE, 0.85))

# ----------------- 6. 玄武佩 (玄黄玉璧 + 云纹) -----------------
func _draw_jade_pendant() -> void:
	var bob := sin(_anim_time * 2.4) * 1.2
	var off := Vector2(0, bob)
	var jade := Color(0.42, 0.50, 0.30) if star < 2 else Color(0.62, 0.58, 0.30)
	# 玉璧外环与内孔（璧形；内孔细环接 FX_HDR_EARTH 玄黄低档微光）
	draw_arc(off, 10.5, 0, TAU, 24, jade, 3.4, true)
	draw_arc(off, 4.0, 0, TAU, 16, Color(GameStyle.FX_HDR_EARTH, 0.55), 1.4, true)
	# 璧面云纹两道
	draw_arc(off + Vector2(0, -2.5), 6.8, PI * 0.15, PI * 0.85, 10, Color(0.90, 0.84, 0.55, 0.8), 1.0, true)
	draw_arc(off + Vector2(0, 2.5), 6.8, PI * 1.15, PI * 1.85, 10, Color(0.90, 0.84, 0.55, 0.8), 1.0, true)
	# 顶部系绳结
	draw_line(off + Vector2(0, -10.5), off + Vector2(0, -13.5), Color(0.70, 0.30, 0.20), 1.6, true)

# ----------------- 7. 灵珑 (祭坛召唤灵兽：圆形灵兽幼兽 + 祭纹金印 + 灵动祥云) -----------------
## 圆形灵兽「灵珑」（2026-10-15 按圆形设计重做）：
## 以圆球灵身为主体（不伸脖子/不生巨翼），参考随行灵兽（SpiritPet）圆萌仙侠范式——
## 圆滚滚的玉青灵魄躯体 + 贴头小巧灵耳 + 软糯祥云短尾 + 灵动双眸。
## 特效华丽层次丰富：足下祥云灵雾 + 周身三层明灭柔光晕 + 6 粒交叉轨道自转星尘 +
## 蓄力面前流转灵珠 + 濒死霜青裂纹与灵息闪烁。
## 面朝 +x，朝向由宿主翻转 scale.x；speed_ratio 驱动耳尾轻摇与尾后灵尘；
## bank_angle 驱动微倾；生命全由本体传达（hp_ratio 驱动灵目、周身辉光）。
func _draw_yuan_ling() -> void:
	var body_col := Color(0.82, 0.94, 0.93)          ## 核心真身玉青
	var belly_col := Color(0.95, 0.99, 0.99)         ## 月白高光
	var edge_col := Color(0.42, 0.76, 0.84)          ## 霜青描边
	var glow_col := Color(0.58, 0.95, 0.98)          ## 泽青灵光
	var ear_inner := Color(0.98, 0.86, 0.86, 0.85)   ## 内耳粉玉色

	# 灵息强度：满血 1.0，随生命衰减（保底 0.25 不致全熄）
	var spirit: float = 0.25 + 0.75 * clampf(hp_ratio, 0.0, 1.0)
	# 濒死程度与灵息闪烁
	var low: float = clampf((0.30 - hp_ratio) / 0.30, 0.0, 1.0)
	var flicker: float = 1.0 - low * (0.5 + 0.5 * sin(_anim_time * 14.0)) * 0.45
	# 出场辉光：1→0 自减，瞬间强闪与灵尘收束
	var sg: float = clampf(spawn_glow, 0.0, 1.0)

	# 悬浮呼吸起伏
	var bob: float = sin(_anim_time * 2.6) * 1.8
	var pivot := Vector2(0.0, -2.0 + bob)
	var core_r: float = 13.5 + 0.8 * sin(_anim_time * 2.4)

	# 1. 足下祥云灵雾（贴地层，随呼吸微缩；出场时暴涨）
	var mist_a: float = (0.12 + 0.05 * sin(_anim_time * 2.2)) * spirit * flicker + 0.12 * sg
	draw_colored_polygon(_ellipse_polygon(Vector2(0.0, 16.5), 18.0 + 4.0 * sg, 4.0, 16), Color(0.52, 0.86, 0.92, mist_a))
	draw_colored_polygon(_ellipse_polygon(Vector2(0.0, 16.5), 11.0, 2.6, 12), Color(0.76, 0.95, 0.98, mist_a * 0.85))

	# 2. 周身三层多重灵光晕圈（深浅呼应，外柔内实）
	var aura_a: float = (0.85 + 0.15 * sin(_anim_time * 3.0)) * spirit * flicker
	_soft_glow(pivot, 28.0 + 10.0 * sg, Color(0.46, 0.85, 0.92, 0.12 * aura_a + 0.12 * sg), 4)
	draw_arc(pivot, 24.0, 0.0, TAU, 32, Color(0.56, 0.92, 0.96, 0.12 * aura_a + 0.15 * sg), 1.1, true)
	draw_arc(pivot, 18.5, 0.0, TAU, 28, Color(0.65, 0.95, 0.98, 0.16 * aura_a), 0.9, true)

	# 3. 环绕自转星尘六粒（椭圆轨道，出场时从外围向核心聚拢）
	for i in range(6):
		var ang := _anim_time * 1.0 + float(i) * TAU / 6.0
		var orbit_r: float = lerpf(21.0, 34.0, sg)
		var mp := pivot + Vector2(cos(ang) * orbit_r, sin(ang) * orbit_r * 0.52)
		var twk := 0.5 + 0.5 * sin(_anim_time * 3.4 + float(i) * 1.6)
		draw_circle(mp, 1.3 + 0.5 * twk + 0.9 * sg, Color(0.72, 0.96, 1.0, (0.18 + 0.32 * twk) * spirit * flicker + 0.35 * sg))

	# 4. 软糯祥云短尾（在躯干背后，随悬停呼吸与移动轻摇，不破外轮廓）
	var tail_swing := sin(_anim_time * 3.2) * (1.2 + 2.0 * speed_ratio)
	var tail_base := pivot + Vector2(-core_r * 0.85, core_r * 0.28 + tail_swing)
	draw_circle(tail_base, 5.0, Color(edge_col, 0.5 * spirit * flicker))
	draw_circle(tail_base + Vector2(-2.0, -1.0), 4.2, Color(body_col, 0.95))
	draw_circle(tail_base + Vector2(-4.2, -0.5), 2.8, Color(belly_col, 0.9))
	draw_circle(tail_base + Vector2(-5.6, -0.2), 1.3, Color(1.0, 1.0, 1.0, 0.8 * spirit * flicker))

	# 5. 头顶小巧灵耳（左右一对圆润萌耳，随速度微摆）
	var ear_tilt := sin(_anim_time * 2.8) * (0.05 + 0.12 * speed_ratio)
	# 左耳（偏后侧）
	var ear_l := PackedVector2Array([
		Vector2(-core_r * 0.65, -core_r * 0.45),
		Vector2(-core_r * 0.92, -core_r * 1.15 - ear_tilt * 4.0),
		Vector2(-core_r * 0.25, -core_r * 0.85)
	])
	draw_colored_polygon(_rot_pts(ear_l, pivot, bank_angle), edge_col.darkened(0.1))
	draw_polyline(_closed(_rot_pts(ear_l, pivot, bank_angle)), edge_col, 1.0, true)
	var in_ear_l := PackedVector2Array([
		Vector2(-core_r * 0.6, -core_r * 0.55),
		Vector2(-core_r * 0.82, -core_r * 1.05 - ear_tilt * 3.5),
		Vector2(-core_r * 0.32, -core_r * 0.82)
	])
	draw_colored_polygon(_rot_pts(in_ear_l, pivot, bank_angle), ear_inner)
	draw_circle(_rot_one(Vector2(-core_r * 0.92, -core_r * 1.15), pivot, bank_angle), 1.2, Color(glow_col, 0.8 * spirit * flicker))

	# 右耳（前侧近景）
	var ear_r := PackedVector2Array([
		Vector2(-core_r * 0.1, -core_r * 0.85),
		Vector2(core_r * 0.18, -core_r * 1.28 + ear_tilt * 3.0),
		Vector2(core_r * 0.52, -core_r * 0.68)
	])
	draw_colored_polygon(_rot_pts(ear_r, pivot, bank_angle), body_col)
	draw_polyline(_closed(_rot_pts(ear_r, pivot, bank_angle)), edge_col, 1.1, true)
	var in_ear_r := PackedVector2Array([
		Vector2(-core_r * 0.05, -core_r * 0.88),
		Vector2(core_r * 0.16, -core_r * 1.18 + ear_tilt * 2.5),
		Vector2(core_r * 0.45, -core_r * 0.74)
	])
	draw_colored_polygon(_rot_pts(in_ear_r, pivot, bank_angle), ear_inner)
	draw_circle(_rot_one(Vector2(core_r * 0.18, -core_r * 1.28), pivot, bank_angle), 1.4, Color(glow_col, 0.9 * spirit * flicker))

	# 6. 圆形真身灵魄（多层玉青同心体，通透饱满）
	draw_circle(pivot, core_r * 1.18, Color(0.70, 0.92, 0.94, 0.35 * spirit * flicker))
	var core_poly := _rot_pts(_ellipse_polygon(Vector2(0.0, -2.0), core_r, core_r, 24), pivot, bank_angle)
	draw_colored_polygon(core_poly, body_col)
	draw_polyline(_closed(core_poly), edge_col, 1.3, true)

	# 腹部与面部月白亮层
	draw_colored_polygon(_rot_pts(_ellipse_polygon(Vector2(2.2, 0.5), core_r * 0.72, core_r * 0.55, 18), pivot, bank_angle), Color(belly_col, 0.85))

	# 核心内部流转的仙灵道纹（缓慢对旋，透射仙气）
	var inner_r := core_r * 0.8
	draw_arc(_rot_one(Vector2(0.0, -2.0), pivot, bank_angle), inner_r, 0.0, TAU, 24, Color(edge_col, 0.30 * spirit * flicker), 0.9, true)
	var rune_a: float = (0.28 + 0.22 * sin(_anim_time * 2.2)) * spirit * flicker
	var spin1: float = _anim_time * (0.7 + 1.4 * speed_ratio) + bank_angle * 1.5
	var spin2: float = -_anim_time * (0.5 + 1.0 * speed_ratio) + bank_angle * 1.5
	draw_arc(_rot_one(Vector2(0.0, -2.0), pivot, bank_angle), inner_r * 0.65, spin1, spin1 + 2.2, 16, Color(glow_col, rune_a), 1.1, true)
	draw_arc(_rot_one(Vector2(0.0, -2.0), pivot, bank_angle), inner_r * 0.45, spin2, spin2 + 1.8, 14, Color(edge_col, rune_a * 0.75), 0.9, true)

	# 7. 濒死裂纹（灵体受损浮现的霜青裂痕）
	if low > 0.0:
		var crack_col := Color(0.55, 0.94, 0.98, (0.35 + 0.45 * low) * flicker)
		draw_polyline(_rot_pts(PackedVector2Array([Vector2(-6.0, -8.0), Vector2(-2.5, -3.0), Vector2(-5.0, 2.0)]), pivot, bank_angle), crack_col, 1.2, true)
		draw_polyline(_rot_pts(PackedVector2Array([Vector2(3.0, -9.0), Vector2(5.5, -3.5), Vector2(3.5, 2.5)]), pivot, bank_angle), crack_col, 1.0, true)

	# 8. 灵动双眸（端正微侧双眼：黑青瞳底 + 泽青灵光环 + 双高光点，炯炯有神）
	var eye_a: float = (0.30 + 0.70 * clampf(hp_ratio, 0.0, 1.0)) * flicker
	# 左眼（略小略偏内）
	var eye_l_pos := _rot_one(Vector2(2.4, -2.6), pivot, bank_angle)
	draw_circle(eye_l_pos, 2.8, Color(glow_col, 0.22 * eye_a))
	draw_circle(eye_l_pos, 1.8, Color(0.12, 0.32, 0.38, 0.95 * eye_a))
	draw_circle(eye_l_pos, 0.9, Color(glow_col, eye_a))
	draw_circle(eye_l_pos + Vector2(-0.4, -0.5), 0.55, Color(1.0, 1.0, 1.0, eye_a))
	draw_circle(eye_l_pos + Vector2(0.4, 0.3), 0.3, Color(1.0, 1.0, 1.0, 0.7 * eye_a))

	# 右眼（略大居前侧，主视眼）
	var eye_r_pos := _rot_one(Vector2(8.6, -1.8), pivot, bank_angle)
	draw_circle(eye_r_pos, 3.2, Color(glow_col, 0.25 * eye_a))
	draw_circle(eye_r_pos, 2.2, Color(0.12, 0.32, 0.38, 0.95 * eye_a))
	draw_circle(eye_r_pos, 1.1, Color(glow_col, eye_a))
	draw_circle(eye_r_pos + Vector2(-0.5, -0.6), 0.7, Color(1.0, 1.0, 1.0, eye_a))
	draw_circle(eye_r_pos + Vector2(0.5, 0.4), 0.35, Color(1.0, 1.0, 1.0, 0.75 * eye_a))

	# 腮边淡淡仙晕（粉玉红晕，增加生动灵气感）
	draw_circle(_rot_one(Vector2(1.5, 1.8), pivot, bank_angle), 1.8, Color(0.98, 0.78, 0.80, 0.30 * spirit * flicker))
	draw_circle(_rot_one(Vector2(9.5, 2.6), pivot, bank_angle), 2.2, Color(0.98, 0.78, 0.80, 0.35 * spirit * flicker))

	# 9. 面前蓄力灵光球（三连灵羽弹蓄力：随 charge_ratio 膨胀发亮，伴随三颗旋绕光珠；白芯接 FX_HDR_CORE 起辉）
	if charge_ratio > 0.01:
		var cp := _rot_one(Vector2(18.5, -1.0), pivot, bank_angle)
		var cr: float = 2.0 + 5.0 * charge_ratio
		var ca: float = charge_ratio * spirit * flicker
		_soft_glow(cp, cr * 2.0, Color(0.52, 0.90, 0.98, 0.20 * ca))
		draw_circle(cp, cr, Color(0.72, 0.95, 0.98, 0.65 * ca))
		draw_circle(cp, cr * 0.55, Color(GameStyle.FX_HDR_CORE, 0.90 * ca))
		for i in range(3):
			var sa := _anim_time * 7.0 + float(i) * TAU / 3.0
			draw_circle(cp + Vector2(cos(sa), sin(sa)) * (cr + 3.0), 1.0, Color(0.85, 0.98, 1.0, 0.7 * ca))

	# 10. 移动灵尘（尾后散逸的三粒流光灵珠，随速度显隐）
	if speed_ratio > 0.2:
		var dust_a := 0.45 * speed_ratio
		for i in range(3):
			var di := float(i)
			var mp := pivot + Vector2(-core_r - 4.0 - di * 4.8, core_r * 0.2 + di * 1.8 + sin(_anim_time * 7.5 + di * 1.2) * 1.8)
			draw_circle(mp, 1.9 - di * 0.4, Color(0.68, 0.92, 0.98, dust_a * (1.0 - di * 0.26)))

## 椭圆多边形采样（足下灵雾、灵珑圆身等共用）
func _ellipse_polygon(center: Vector2, rx: float, ry: float, segs: int = 16) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segs):
		var a := float(i) / float(segs) * TAU
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts

## 闭合折线（多边形描边用：末点补回首点）
func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	out.append(pts[0])
	return out

## 沿折线生成由 w0 渐变到 w1 的带状多边形并填充（飘带/缎带状部件共用）
func _draw_ribbon(pts: PackedVector2Array, w0: float, w1: float, col: Color) -> void:
	var n := pts.size()
	if n < 2:
		return
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in range(n):
		var dir: Vector2
		if i == 0:
			dir = pts[1] - pts[0]
		elif i == n - 1:
			dir = pts[n - 1] - pts[n - 2]
		else:
			dir = pts[i + 1] - pts[i - 1]
		var nor := dir.normalized().orthogonal() * (lerpf(w0, w1, float(i) / float(n - 1)) * 0.5)
		left.append(pts[i] + nor)
		right.append(pts[i] - nor)
	var poly := PackedVector2Array(left)
	for i in range(n - 1, -1, -1):
		poly.append(right[i])
	draw_colored_polygon(poly, col)

## 躯体组统一绕 pivot 旋转 bank（晕圈/足雾不转 —— 悬浮侧倾只倾身体）
func _rot_pts(pts: PackedVector2Array, pivot: Vector2, a: float) -> PackedVector2Array:
	if absf(a) < 0.0005:
		return pts
	var out := PackedVector2Array()
	for p in pts:
		out.append(pivot + (p - pivot).rotated(a))
	return out

func _rot_one(p: Vector2, pivot: Vector2, a: float) -> Vector2:
	return pivot + (p - pivot).rotated(a)

## 多层同心圆柔光（HollowKnightEnemyRenderer.draw_soft_glow 的轻量同款，内亮外淡）
func _soft_glow(pos: Vector2, radius: float, col: Color, layers: int = 3) -> void:
	for i in range(layers):
		var f := float(i + 1) / float(layers)
		draw_circle(pos, radius * f, Color(col.r, col.g, col.b, col.a * (1.0 - f * 0.7)))

# ----------------- 8. 金鸣铃 (悬空金铃 + 摆动铃舌 + 云雷纹) -----------------
func _draw_golden_bell() -> void:
	var sway := sin(_anim_time * 3.0) * 0.12
	var gold := Color(0.95, 0.80, 0.30) if star >= 2 else Color(0.72, 0.60, 0.26)
	# 吊绳
	draw_line(Vector2(0, -14), Vector2(0, -9.5), Color(0.60, 0.50, 0.22), 1.4, true)
	# 铃身（上窄下阔钟形，随 sway 轻摆）
	var bell := PackedVector2Array([
		Vector2(-4.5, -9.5).rotated(sway),
		Vector2(4.5, -9.5).rotated(sway),
		Vector2(7.5, 4.0).rotated(sway),
		Vector2(8.5, 7.0).rotated(sway),
		Vector2(-8.5, 7.0).rotated(sway),
		Vector2(-7.5, 4.0).rotated(sway)
	])
	draw_colored_polygon(bell, Color(0.30, 0.26, 0.14))
	draw_polyline(bell, gold, 1.4, true)
	# 铃口缘与云雷横纹（口缘亮线接 FX_HDR_METAL 起辉，铃的「一眼金」）
	var rim_y := 7.0
	draw_line(Vector2(-8.5, rim_y).rotated(sway), Vector2(8.5, rim_y).rotated(sway), Color(GameStyle.FX_HDR_METAL, 0.85), 1.8, true)
	draw_line(Vector2(-6.5, -2.0).rotated(sway), Vector2(6.5, -2.0).rotated(sway), Color(0.88, 0.76, 0.38, 0.7), 1.0, true)
	# 铃舌（随摆反向荡；舌珠接 FX_HDR_METAL 低档起辉）
	var clapper_x := -sway * 40.0
	draw_line(Vector2(clapper_x * 0.4, 4.0).rotated(sway), Vector2(clapper_x, 10.0), gold, 1.4, true)
	draw_circle(Vector2(clapper_x, 11.0), 1.8, Color(GameStyle.FX_HDR_METAL, 0.85))
	# 铃身符点
	draw_circle(Vector2(0, -5.5).rotated(sway), 1.3, Color(0.98, 0.92, 0.60, 0.9))

# ----------------- 9. 木灵偶 (青木偶人 + 灵藤关节 + 生机符印) -----------------
func _draw_wood_puppet() -> void:
	var bob := sin(_anim_time * 2.6) * 1.2
	var off := Vector2(0, bob)
	var wood := Color(0.52, 0.40, 0.24) if star < 2 else Color(0.64, 0.50, 0.30)
	var vine := Color(0.35, 0.75, 0.40)
	# 头（圆木雕）与躯干
	draw_circle(off + Vector2(0, -7.0), 4.0, wood)
	var torso := PackedVector2Array([
		off + Vector2(-3.5, -3.0), off + Vector2(3.5, -3.0),
		off + Vector2(2.5, 6.0), off + Vector2(-2.5, 6.0)
	])
	draw_colored_polygon(torso, wood)
	draw_polyline(torso, vine, 1.0, true)
	# 双臂（灵藤束连，微张摆动）
	var arm_sw := sin(_anim_time * 3.4) * 2.0
	draw_line(off + Vector2(-3.0, -1.5), off + Vector2(-8.5, 1.5 + arm_sw), vine, 1.6, true)
	draw_line(off + Vector2(3.0, -1.5), off + Vector2(8.5, 1.5 - arm_sw), vine, 1.6, true)
	# 双腿
	draw_line(off + Vector2(-1.8, 6.0), off + Vector2(-2.6, 11.0), vine, 1.6, true)
	draw_line(off + Vector2(1.8, 6.0), off + Vector2(2.6, 11.0), vine, 1.6, true)
	# 胸口生机符印（呼吸明暗；接 FX_HDR_WOOD 青碧起辉）
	var mark_a := 0.55 + 0.3 * sin(_anim_time * 3.0)
	draw_circle(off + Vector2(0, 1.0), 1.6, Color(GameStyle.FX_HDR_WOOD, 0.8 * mark_a))
	# 头顶灵芽
	draw_line(off + Vector2(0, -11.0), off + Vector2(1.5, -13.5), Color(0.55, 0.95, 0.50), 1.3, true)

# ----------------- 10. 冰魄珠 (寒冰宝珠 + 环绕冰晶棱片 + 雪亮冰核) -----------------
func _draw_ice_pearl() -> void:
	var rot := _anim_time * 1.8
	var ice := Color(0.55, 0.85, 1.0, 0.9) if star < 2 else Color(0.75, 0.95, 1.0)
	# 珠体（半透明幽蓝）与内核（雪亮冰核接 FX_HDR_WATER 低档起辉）
	draw_circle(Vector2.ZERO, 7.0, Color(0.40, 0.70, 0.95, 0.45))
	draw_circle(Vector2.ZERO, 7.0, Color(0.55, 0.85, 1.0, 0.12))
	draw_arc(Vector2.ZERO, 7.0, 0, TAU, 20, ice, 1.4, true)
	draw_circle(Vector2(0.5, -0.5), 2.2, Color(GameStyle.FX_HDR_WATER, 0.8))
	# 六片环绕冰晶棱片（自转）
	for i in range(6):
		var ang := float(i) / 6.0 * TAU + rot
		var c := Vector2(cos(ang), sin(ang)) * 10.5
		var spike := PackedVector2Array([
			c + Vector2(cos(ang + 0.5), sin(ang + 0.5)) * 2.6,
			c + Vector2(cos(ang), sin(ang)) * 4.6,
			c + Vector2(cos(ang - 0.5), sin(ang - 0.5)) * 2.6
		])
		draw_colored_polygon(spike, Color(0.75, 0.95, 1.0, 0.85))
	# 寒雾微光
	draw_arc(Vector2.ZERO, 13.0, 0, TAU, 24, Color(0.70, 0.92, 1.0, 0.18), 1.0, true)

# ----------------- 11. 赤炎萤 (流火萤虫 + 薄透火翼 + 尾腹火光) -----------------
func _draw_fire_firefly() -> void:
	var wing_flap := sin(_anim_time * 14.0)
	var flap_x := 0.4 + 0.6 * absf(wing_flap)
	var shell := Color(0.72, 0.26, 0.10) if star < 2 else Color(0.88, 0.36, 0.12)
	# 薄透火翼（两扇，扑动）
	for side in [-1.0, 1.0]:
		var wing := PackedVector2Array([
			Vector2(side * 1.5, -3.0),
			Vector2(side * 9.0 * flap_x, -10.0),
			Vector2(side * 7.5 * flap_x, -3.5)
		])
		draw_colored_polygon(wing, Color(1.0, 0.55, 0.20, 0.35))
		draw_polyline(wing, Color(1.0, 0.75, 0.35, 0.7), 0.9, true)
	# 甲壳躯干（头小腹大）
	draw_circle(Vector2(0, -3.5), 2.6, Color(0.35, 0.14, 0.08))
	var abdomen := PackedVector2Array([
		Vector2(-3.4, -1.0), Vector2(3.4, -1.0), Vector2(2.4, 5.5), Vector2(-2.4, 5.5)
	])
	draw_colored_polygon(abdomen, shell)
	draw_polyline(abdomen, Color(1.0, 0.55, 0.20, 0.8), 1.0, true)
	# 尾腹火光（呼吸闪烁；灯焰接 FX_HDR_FIRE 起辉，萤虫的一眼点）
	var lamp_a := 0.65 + 0.35 * sin(_anim_time * 6.0)
	draw_circle(Vector2(0, 4.2), 2.2, Color(GameStyle.FX_HDR_FIRE, 0.85 * lamp_a))
	draw_circle(Vector2(0, 4.2), 3.6, Color(1.0, 0.55, 0.15, 0.18 * lamp_a))
	# 触须
	draw_line(Vector2(-1.0, -5.6), Vector2(-2.6, -8.0), Color(0.45, 0.18, 0.10), 1.0, true)
	draw_line(Vector2(1.0, -5.6), Vector2(2.6, -8.0), Color(0.45, 0.18, 0.10), 1.0, true)

# ----------------- 12. 土灵石 (符文灵石 + 山岩棱面 + 镇岳古符) -----------------
func _draw_earth_stone() -> void:
	var rot := sin(_anim_time * 1.6) * 0.15
	var rock := Color(0.45, 0.38, 0.26) if star < 2 else Color(0.56, 0.47, 0.32)
	# 石体（不规则六边山岩断面，微晃）
	var stone := PackedVector2Array([
		Vector2(-6.5, -8.0).rotated(rot), Vector2(3.5, -9.5).rotated(rot),
		Vector2(9.0, -2.0).rotated(rot), Vector2(7.0, 7.5).rotated(rot),
		Vector2(-3.0, 9.5).rotated(rot), Vector2(-9.0, 2.5).rotated(rot)
	])
	draw_colored_polygon(stone, rock)
	draw_polyline(stone, Color(0.80, 0.68, 0.40), 1.3, true)
	# 岩面裂纹两道
	draw_line(Vector2(-4.0, -5.0).rotated(rot), Vector2(1.5, 1.0).rotated(rot), Color(0.28, 0.22, 0.14, 0.8), 1.0, true)
	draw_line(Vector2(1.5, 1.0).rotated(rot), Vector2(-0.5, 6.5).rotated(rot), Color(0.28, 0.22, 0.14, 0.6), 1.0, true)
	# 镇岳符印（山形三峰，发光呼吸；接 FX_HDR_EARTH 玄黄起辉）
	var mark_a := 0.6 + 0.3 * sin(_anim_time * 2.8)
	var m := Vector2(0.5, -1.0).rotated(rot)
	draw_polyline(PackedVector2Array([
		m + Vector2(-3.2, 1.8), m + Vector2(-1.1, -1.8), m + Vector2(0.6, 0.6),
		m + Vector2(2.0, -2.4), m + Vector2(3.8, 1.8)
	]), Color(GameStyle.FX_HDR_EARTH, 0.8 * mark_a), 1.2, true)

# ----------------- 13. 剑灵 (半透明剑形精魂 + 灵气飘带) -----------------
func _draw_sword_wisp() -> void:
	var tilt := sin(_anim_time * 2.2) * 0.2
	var blade := Color(0.72, 0.92, 1.0, 0.80) if star < 2 else Color(0.85, 0.98, 1.0, 0.92)
	var edge := Color(0.55, 0.90, 1.0, 0.9)
	# 灵气飘带（剑柄后方两条相位飘动的丝带）
	for i in range(2):
		var ribbon := PackedVector2Array()
		for k in range(6):
			var t := float(k) / 5.0
			ribbon.append(Vector2(-4.0 - t * 9.0, (1.2 + float(i) * 2.2) * sin(_anim_time * 5.0 + t * 4.0 + float(i) * 1.8) * (1.0 - t * 0.4)))
		draw_polyline(ribbon, Color(0.60, 0.92, 1.0, 0.5 - float(i) * 0.15), 1.1, true)
	# 剑身（半透明青白，随 tilt 轻倾）
	var body := PackedVector2Array([
		Vector2(13.0, 0.0).rotated(tilt), Vector2(-1.0, -2.4).rotated(tilt),
		Vector2(-6.0, 0.0).rotated(tilt), Vector2(-1.0, 2.4).rotated(tilt)
	])
	draw_colored_polygon(body, Color(blade, 0.55))
	draw_polyline(body, edge, 1.1, true)
	draw_line(Vector2(12.0, 0.0).rotated(tilt), Vector2(-5.0, 0.0).rotated(tilt), Color(1.0, 1.0, 1.0, 0.75), 0.9, true)
	# 剑格与剑柄灵珠（柄珠接 FX_HDR_CORE 低档微辉）
	draw_line(Vector2(-5.5, -3.0).rotated(tilt), Vector2(-5.5, 3.0).rotated(tilt), edge, 1.3, true)
	draw_circle(Vector2(-7.5, 0.0).rotated(tilt), 1.5, Color(GameStyle.FX_HDR_CORE, 0.7))
	# 剑尖灵光（接 FX_HDR_CORE 白芯超白起辉，剑灵的一眼点）
	draw_circle(Vector2(13.0, 0.0).rotated(tilt), 1.2 + 0.3 * sin(_anim_time * 6.0), Color(GameStyle.FX_HDR_CORE, 0.9))
