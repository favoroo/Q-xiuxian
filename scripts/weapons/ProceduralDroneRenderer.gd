class_name ProceduralDroneRenderer
extends Node2D

## 纯矢量环绕灵宝渲染器（冷冽国风）
## 为御灵系法宝（灵蝶、寒泉玉莲、混元钟）提供细腻的自转、振翅与流光视觉

enum DroneKind {
	LINGDIE,        ## 灵蝶：碧翠灵羽、生机透光羽翼、双翅轻盈扑动
	HANQUAN_YULIAN, ## 寒泉玉莲：晶莹冰魄青莲、层叠八瓣寒晶、中央灵蕊
	HUNYUAN_ZHONG,  ## 混元钟：玄铁青铜古钟、暗金饕餮符印、钟首盘龙纽
	HAOJIN_LUN,     ## 昊金轮：旋转金轮、辐条流光（2026-10-10 新增）
	LIHUO_YA,       ## 离火鸦：火羽扑翼、焰尾曳光（2026-10-10 新增）
	XUANWU_PEI,     ## 玄武佩：玄黄玉璧、云纹护身（2026-10-10 新增）
	XUAN_HE,        ## 玄鹤：祭坛召唤灵兽，冷白无腿悬浮灵鹤（2026-10-11 由地面走狐重做）
	JINMING_LING,   ## 金鸣铃：悬空金铃、铃舌摆鸣、云雷符纹（2026-10-11 第二批）
	MULING_OU,      ## 木灵偶：青木偶人、灵藤关节、生机符印（2026-10-11 第二批）
	BINGPO_ZHU,     ## 冰魄珠：寒冰宝珠、冰晶棱片、雪亮冰核（2026-10-11 第二批）
	CHIYAN_YING,    ## 赤炎萤：流火萤虫、薄透火翼、尾腹火光（2026-10-11 第二批）
	TULING_SHI,     ## 土灵石：符文灵石、山岩棱面、镇岳古符（2026-10-11 第二批）
	JIAN_LING       ## 剑灵：半透明剑形精魂、灵气飘带（2026-10-11 第二批）
}

@export var kind: DroneKind = DroneKind.LINGDIE
@export var star: int = 1

## 速度权重（0=悬停 1=全速）：仅玄鹤（XUAN_HE）消费，由宿主按实际移速灌入，
## 驱动展翼幅度 / 扑翼频率 / 尾羽拖曳与尾后灵尘
var speed_ratio: float = 0.0

## 侧倾角（弧度）：仅玄鹤消费 —— 按朝向系下的横向走位 bank，只倾躯体组（晕圈/足雾不随动）；
## 宿主按 velocity.x * 朝向符号 归一灌入，左右镜像由 scale.x 承担
var bank_angle: float = 0.0

## 血量比（0..1）：仅玄鹤消费，由宿主（SpiritBeast）灌入 —— 灵兽不挂血条，
## 血量全由本体传达：驱动灵光晕圈/丹顶/灵目明暗，低于 30% 浮现裂纹与灵息闪烁
var hp_ratio: float = 1.0

var _anim_time: float = 0.0

## —— 重绘节流（2026-10-11 性能优化，2026-10-10/11 节流扫荡的漏网之鱼）——
## 环绕灵宝矢量 _draw 一帧几十条指令，「武器一多」时多只灵宝每帧全量重绘
## 是渲染线程热点。与 HollowKnightEnemyRenderer 同款：20Hz 节流 + 实例错相；
## _anim_time 照常逐帧推进，回绘时动画相位连续。灵宝环绕玩家永在屏内，无需屏外剔除。
const REDRAW_INTERVAL := 0.05     ## 重绘间隔：20Hz
static var redraw_count: int = 0  ## 重绘发放计数（tests/PerfProbe 断言用）

var _draw_phase: float = 0.0      ## 距下次重绘的剩余时间（错相载体）

func _ready() -> void:
	# 错相：instance_id 派生初值（不碰玩法随机），多只灵宝的重绘摊到不同帧
	_draw_phase = fposmod(float(get_instance_id() % 97) * 0.001, REDRAW_INTERVAL)

func _process(delta: float) -> void:
	_anim_time += delta
	if _draw_phase <= 0.0:
		_draw_phase = REDRAW_INTERVAL
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
		DroneKind.XUAN_HE:
			_draw_xuan_he()
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

	# 蝶身脊柱与灵须
	draw_line(Vector2(0, -7.0), Vector2(0, 7.0), Color(0.10, 0.14, 0.18), 2.0, true)
	draw_circle(Vector2(0, -7.0), 1.6, Color(0.92, 0.95, 0.98))
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

	# 内层灵蕊
	draw_circle(Vector2.ZERO, inner_r, Color(0.20, 0.45, 0.70))
	draw_circle(Vector2.ZERO, inner_r * 0.5, Color(1.0, 0.95, 0.80) if star >= 2 else Color(0.90, 0.98, 1.0))

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

	# 钟口下沿口缘
	draw_line(Vector2(-11.0, 9.0), Vector2(11.0, 9.0), Color(0.92, 0.82, 0.42), 2.0, true)

# ----------------- 4. 昊金轮 (自转金轮 + 六辐流光) -----------------
func _draw_golden_wheel() -> void:
	var rot := _anim_time * 4.0
	var rim := Color(0.95, 0.80, 0.30) if star >= 2 else Color(0.72, 0.58, 0.22)
	# 六辐轮辐
	for i in range(6):
		var ang := float(i) / 6.0 * TAU + rot
		draw_line(Vector2.ZERO, Vector2(cos(ang) * 11.0, sin(ang) * 11.0), rim, 1.6, true)
	# 外轮圈与轴心
	draw_arc(Vector2.ZERO, 11.0, 0, TAU, 24, rim, 2.2, true)
	draw_arc(Vector2.ZERO, 7.5, 0, TAU, 18, Color(0.98, 0.90, 0.55, 0.5), 1.0, true)
	draw_circle(Vector2.ZERO, 3.0, Color(1.0, 0.92, 0.55))
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
	# 焰尾三条
	for i in range(-1, 2):
		var sway := sin(_anim_time * 7.0 + float(i)) * 2.0
		draw_line(Vector2(float(i) * 2.5, 4.0), Vector2(float(i) * 3.5 + sway, 12.0), flame, 1.4, true)
	# 鸦身与金目
	draw_circle(Vector2.ZERO, 4.2, body)
	draw_circle(Vector2(0, -5.2), 2.2, body)
	draw_circle(Vector2(1.2, -5.8), 0.9, Color(1.0, 0.85, 0.30))

# ----------------- 6. 玄武佩 (玄黄玉璧 + 云纹) -----------------
func _draw_jade_pendant() -> void:
	var bob := sin(_anim_time * 2.4) * 1.2
	var off := Vector2(0, bob)
	var jade := Color(0.42, 0.50, 0.30) if star < 2 else Color(0.62, 0.58, 0.30)
	# 玉璧外环与内孔（璧形）
	draw_arc(off, 10.5, 0, TAU, 24, jade, 3.4, true)
	draw_arc(off, 4.0, 0, TAU, 16, Color(0.88, 0.80, 0.50), 1.4, true)
	# 璧面云纹两道
	draw_arc(off + Vector2(0, -2.5), 6.8, PI * 0.15, PI * 0.85, 10, Color(0.90, 0.84, 0.55, 0.8), 1.0, true)
	draw_arc(off + Vector2(0, 2.5), 6.8, PI * 1.15, PI * 1.85, 10, Color(0.90, 0.84, 0.55, 0.8), 1.0, true)
	# 顶部系绳结
	draw_line(off + Vector2(0, -10.5), off + Vector2(0, -13.5), Color(0.70, 0.30, 0.20), 1.6, true)

# ----------------- 7. 玄鹤 (祭坛召唤灵兽：冷白无腿悬浮灵鹤) -----------------
## 悬浮滑翔姿态：修长颈线 + 双层滑翔翼 + 飘带尾羽，无腿 —— 悬浮感由常时浮沉 bob
## 与足下灵雾传达，绝不做地面步态。画幅与旧灵狐同档（碰撞半径 14 与画幅同源）。
## 面朝 +x，朝向由宿主翻转 scale.x；speed_ratio 驱动展翼/扑翼频率/尾羽拖曳与尾后灵尘；
## bank_angle 只倾躯体组（晕圈/足雾不随动）。
## 血量由本体传达（hp_ratio）：满血灵光充盈；血少晕圈/丹顶/灵目转暗；低于 30%
## 躯干浮现霜蓝裂纹、灵息闪烁 —— 灵兽不挂血条。
func _draw_xuan_he() -> void:
	var body_col := Color(0.90, 0.94, 0.98)
	var belly_col := Color(0.97, 0.99, 1.00)
	var far_col := Color(0.56, 0.68, 0.82, 0.92)
	var edge_col := Color(0.45, 0.78, 1.00)
	var glow_col := Color(0.60, 0.95, 1.00)
	var gold_col := Color(0.95, 0.80, 0.38)
	# 灵息强度：满血 1.0，随血量衰减（保底 0.25 不致全熄）
	var spirit: float = 0.25 + 0.75 * clampf(hp_ratio, 0.0, 1.0)
	# 濒死程度与灵息闪烁
	var low: float = clampf((0.30 - hp_ratio) / 0.30, 0.0, 1.0)
	var flicker: float = 1.0 - low * (0.5 + 0.5 * sin(_anim_time * 14.0)) * 0.45
	# 悬浮浮沉（只作用躯体组）；滑翔扑翼：慢频小摆，移动随速度加快加深；展翼比随速度张开
	var bob: float = sin(_anim_time * 2.6) * 1.8
	var flap: float = sin(_anim_time * (2.6 + 4.2 * speed_ratio)) * (1.2 + 2.6 * speed_ratio)
	var spread: float = 0.35 + 0.65 * clampf(speed_ratio, 0.0, 1.0)
	var pivot := Vector2(0.0, -2.0 + bob)

	# 足下灵雾（贴地，不随 bank/bob —— 悬浮高度的语言）
	var mist_a: float = (0.10 + 0.04 * sin(_anim_time * 2.4)) * spirit * flicker
	draw_colored_polygon(_ellipse_polygon(Vector2(0.0, 16.0), 14.0, 3.2, 14), Color(0.55, 0.85, 1.0, mist_a))
	draw_colored_polygon(_ellipse_polygon(Vector2(0.0, 16.0), 8.0, 2.0, 12), Color(0.75, 0.92, 1.0, mist_a * 0.8))

	# 周身灵光晕圈（血量的第一语言）：柔光为主，环线只留一点若有若无的轮廓
	var aura_a: float = (0.85 + 0.15 * sin(_anim_time * 3.0)) * spirit * flicker
	_soft_glow(Vector2(0.0, -3.0), 21.0, Color(0.50, 0.85, 1.0, 0.10 * aura_a))
	draw_arc(Vector2(0.0, -3.0), 20.0, 0.0, TAU, 28, Color(0.60, 0.92, 1.0, 0.11 * aura_a), 1.0, true)

	# 飘带尾羽三条（相位错摆，移动时向后拉长），尾尖霜白灵光
	for i in range(3):
		var fi := float(i - 1)
		var sway := sin(_anim_time * 3.0 + fi * 0.9) * (2.0 + 2.0 * speed_ratio)
		var seg_len: float = 11.0 + 6.0 * speed_ratio
		var tail_base := Vector2(-10.0, -1.0 + fi * 1.8)
		var ribbon := PackedVector2Array([
			tail_base,
			tail_base + Vector2(-seg_len * 0.4, -1.5 + fi * 1.0 + sway * 0.4),
			tail_base + Vector2(-seg_len * 0.75, fi * 2.0 + sway * 0.8),
			tail_base + Vector2(-seg_len, fi * 2.8 + sway * 1.3)
		])
		var tip := ribbon[ribbon.size() - 1]
		_draw_ribbon(_rot_pts(ribbon, pivot, bank_angle), 2.8, 0.7, Color(0.62, 0.86, 1.0, 0.68 * spirit * flicker))
		draw_circle(_rot_one(tip, pivot, bank_angle), 2.4, Color(0.70, 0.94, 1.0, 0.22 * spirit * flicker))
		draw_circle(_rot_one(tip, pivot, bank_angle), 1.2, Color(0.95, 0.98, 1.0, 0.5 * spirit * flicker))

	# 远翼（背层，暗色小一号，反相微摆）
	var wr := Vector2(2.5, -7.0)
	var far_wing := PackedVector2Array([
		wr + Vector2(3.0, -1.8),
		wr + Vector2(-1.5 - 4.5 * spread, -8.5 - flap * 0.8),
		wr + Vector2(-7.0 - 6.0 * spread, -8.0 - flap * 0.5),
		wr + Vector2(-5.5 - 5.5 * spread, -3.5 - flap * 0.25),
		wr + Vector2(-1.5, 0.2)
	])
	draw_colored_polygon(_rot_pts(far_wing, pivot, bank_angle), far_col)
	draw_polyline(_closed(_rot_pts(far_wing, pivot, bank_angle)), edge_col.darkened(0.25), 1.0, true)

	# 躯干（流线长梭）+ 腹部亮层
	var body_pts := PackedVector2Array([
		Vector2(-12.0, -0.5),
		Vector2(-9.0, -5.0),
		Vector2(-3.0, -7.8),
		Vector2(4.0, -7.0),
		Vector2(8.5, -4.0),
		Vector2(9.2, -0.5),
		Vector2(4.5, 2.6),
		Vector2(-2.5, 3.4),
		Vector2(-9.5, 2.4)
	])
	var body_rot := _rot_pts(body_pts, pivot, bank_angle)
	draw_colored_polygon(body_rot, body_col)
	draw_polyline(_closed(body_rot), edge_col, 1.2, true)
	var belly_pts := PackedVector2Array([
		Vector2(7.0, -0.2),
		Vector2(4.0, 2.2),
		Vector2(-2.5, 2.9),
		Vector2(-8.5, 1.8),
		Vector2(-5.5, -1.2),
		Vector2(2.0, -1.6)
	])
	draw_colored_polygon(_rot_pts(belly_pts, pivot, bank_angle), Color(belly_col, 0.85))

	# 濒死裂纹（霜蓝发光折线，随 low 显影）
	if low > 0.0:
		var crack_col := Color(0.55, 0.92, 1.0, (0.35 + 0.45 * low) * flicker)
		draw_polyline(_rot_pts(PackedVector2Array([Vector2(-5.0, -4.5), Vector2(-2.0, -1.0), Vector2(-4.5, 2.2)]), pivot, bank_angle), crack_col, 1.1, true)
		draw_polyline(_rot_pts(PackedVector2Array([Vector2(3.0, -5.0), Vector2(5.0, -1.5), Vector2(3.5, 1.8)]), pivot, bank_angle), crack_col, 0.9, true)

	# 颈部 S 曲线（渐宽带状）+ 中线高光
	var neck_pts := PackedVector2Array([
		Vector2(6.5, -4.5),
		Vector2(10.0, -5.8),
		Vector2(13.0, -8.2),
		Vector2(15.0, -10.8),
		Vector2(16.0, -12.2)
	])
	_draw_ribbon(_rot_pts(neck_pts, pivot, bank_angle), 5.0, 2.8, body_col)
	draw_polyline(_rot_pts(neck_pts, pivot, bank_angle), Color(belly_col, 0.7), 1.0, true)

	# 头 + 尖长的嘴 + 丹顶 + 冠羽 + 灵目
	var head_pos := _rot_one(Vector2(16.0, -12.6), pivot, bank_angle)
	draw_circle(head_pos, 3.1, body_col)
	draw_arc(head_pos, 3.1, 0.0, TAU, 14, edge_col, 1.0, true)
	var beak := PackedVector2Array([
		head_pos + Vector2(2.0, -1.1),
		head_pos + Vector2(9.2, 0.9),
		head_pos + Vector2(1.9, 0.9)
	])
	draw_colored_polygon(beak, Color(0.72, 0.58, 0.30))
	draw_polyline(_closed(beak), Color(0.45, 0.36, 0.18), 0.8, true)
	# 丹顶（血量指示之一：随 hp_ratio 明暗）
	var crown_a: float = (0.35 + 0.65 * clampf(hp_ratio, 0.0, 1.0)) * flicker
	draw_circle(head_pos + Vector2(-0.4, -3.6), 2.8, Color(gold_col, 0.30 * crown_a))
	draw_circle(head_pos + Vector2(-0.4, -3.6), 1.4, Color(gold_col, crown_a))
	# 冠羽后拂两缕（偶发飘动）
	var crest_sway := sin(_anim_time * 3.7) * 1.2
	draw_polyline(_rot_pts(PackedVector2Array([
		Vector2(14.6, -13.8), Vector2(11.8, -14.6 + crest_sway * 0.5), Vector2(10.0, -13.2 + crest_sway)
	]), pivot, bank_angle), Color(edge_col, 0.75), 1.1, true)
	draw_polyline(_rot_pts(PackedVector2Array([
		Vector2(14.2, -13.0), Vector2(11.0, -12.6 + crest_sway * 0.4), Vector2(9.2, -10.8 + crest_sway * 0.8)
	]), pivot, bank_angle), Color(edge_col, 0.5), 0.9, true)
	# 霜蓝灵目（晕圈 + 瞳 + 高光，随 hp_ratio 明暗）
	var eye_pos := head_pos + Vector2(1.2, -0.7)
	var eye_a: float = (0.30 + 0.70 * clampf(hp_ratio, 0.0, 1.0)) * flicker
	draw_circle(eye_pos, 2.4, Color(glow_col, 0.22 * eye_a))
	draw_circle(eye_pos, 1.2, Color(glow_col, eye_a))
	draw_circle(eye_pos + Vector2(-0.3, -0.4), 0.5, Color(1.0, 1.0, 1.0, eye_a))

	# 近翼（顶层大滑翔翼：后掠翼面 + 两枚分叉羽尖夹 V 形缺口 + 前缘高光 + 羽枝）
	var near_wing := PackedVector2Array([
		wr + Vector2(1.5, -1.0),
		wr + Vector2(-2.5 - 4.5 * spread, -9.5 - flap),
		wr + Vector2(-8.5 - 7.5 * spread, -10.5 - flap * 0.65),
		wr + Vector2(-6.5 - 6.5 * spread, -6.0 - flap * 0.4),
		wr + Vector2(-10.5 - 8.0 * spread, -4.0 - flap * 0.2),
		wr + Vector2(-5.5, -0.5)
	])
	var near_rot := _rot_pts(near_wing, pivot, bank_angle)
	draw_colored_polygon(near_rot, Color(0.84, 0.91, 0.97, 0.82))
	draw_polyline(_closed(near_rot), edge_col, 1.1, true)
	# 前缘高光
	draw_polyline(_rot_pts(PackedVector2Array([near_wing[0], near_wing[1]]), pivot, bank_angle), Color(belly_col, 0.9), 1.2, true)
	# 羽枝两道（向两枚羽尖收拢的霜蓝细线）
	draw_polyline(_rot_pts(PackedVector2Array([wr + Vector2(-1.5, -1.0), near_wing[2] + Vector2(1.0, 0.8)]), pivot, bank_angle), Color(edge_col, 0.40), 0.9, true)
	draw_polyline(_rot_pts(PackedVector2Array([wr + Vector2(-1.8, -0.4), near_wing[4] + Vector2(1.2, 0.6)]), pivot, bank_angle), Color(edge_col, 0.32), 0.9, true)

	# 移动灵尘（尾后三粒，随速度显隐）
	if speed_ratio > 0.25:
		var dust_a := 0.35 * speed_ratio
		for i in range(3):
			var di := float(i)
			var mp := Vector2(-14.0 - di * 4.2, 1.5 + di * 1.6 + sin(_anim_time * 7.0 + di * 1.1) * 1.6)
			draw_circle(mp, 1.7 - di * 0.35, Color(0.70, 0.92, 1.0, dust_a * (1.0 - di * 0.28)))

## 椭圆多边形采样（玄鹤足下灵雾等共用）
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

## 沿折线生成由 w0 渐变到 w1 的带状多边形并填充（玄鹤颈部/飘带尾羽共用）
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
	# 铃口缘与云雷横纹
	var rim_y := 7.0
	draw_line(Vector2(-8.5, rim_y).rotated(sway), Vector2(8.5, rim_y).rotated(sway), Color(0.95, 0.86, 0.45), 1.8, true)
	draw_line(Vector2(-6.5, -2.0).rotated(sway), Vector2(6.5, -2.0).rotated(sway), Color(0.88, 0.76, 0.38, 0.7), 1.0, true)
	# 铃舌（随摆反向荡）
	var clapper_x := -sway * 40.0
	draw_line(Vector2(clapper_x * 0.4, 4.0).rotated(sway), Vector2(clapper_x, 10.0), gold, 1.4, true)
	draw_circle(Vector2(clapper_x, 11.0), 1.8, Color(1.0, 0.90, 0.55))
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
	# 胸口生机符印（呼吸明暗）
	var mark_a := 0.55 + 0.3 * sin(_anim_time * 3.0)
	draw_circle(off + Vector2(0, 1.0), 1.6, Color(0.75, 1.0, 0.55, mark_a))
	# 头顶灵芽
	draw_line(off + Vector2(0, -11.0), off + Vector2(1.5, -13.5), Color(0.55, 0.95, 0.50), 1.3, true)

# ----------------- 10. 冰魄珠 (寒冰宝珠 + 环绕冰晶棱片 + 雪亮冰核) -----------------
func _draw_ice_pearl() -> void:
	var rot := _anim_time * 1.8
	var ice := Color(0.55, 0.85, 1.0, 0.9) if star < 2 else Color(0.75, 0.95, 1.0)
	# 珠体（半透明幽蓝）与内核
	draw_circle(Vector2.ZERO, 7.0, Color(0.40, 0.70, 0.95, 0.45))
	draw_circle(Vector2.ZERO, 7.0, Color(0.55, 0.85, 1.0, 0.12))
	draw_arc(Vector2.ZERO, 7.0, 0, TAU, 20, ice, 1.4, true)
	draw_circle(Vector2(0.5, -0.5), 2.2, Color(0.98, 1.0, 1.0, 0.95))
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
	var glow := Color(1.0, 0.62, 0.16, 0.9)
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
	# 尾腹火光（呼吸闪烁）
	var lamp_a := 0.65 + 0.35 * sin(_anim_time * 6.0)
	draw_circle(Vector2(0, 4.2), 2.2, Color(glow, lamp_a))
	draw_circle(Vector2(0, 4.2), 3.6, Color(1.0, 0.55, 0.15, 0.18 * lamp_a))
	# 触须
	draw_line(Vector2(-1.0, -5.6), Vector2(-2.6, -8.0), Color(0.45, 0.18, 0.10), 1.0, true)
	draw_line(Vector2(1.0, -5.6), Vector2(2.6, -8.0), Color(0.45, 0.18, 0.10), 1.0, true)

# ----------------- 12. 土灵石 (符文灵石 + 山岩棱面 + 镇岳古符) -----------------
func _draw_earth_stone() -> void:
	var rot := sin(_anim_time * 1.6) * 0.15
	var rock := Color(0.45, 0.38, 0.26) if star < 2 else Color(0.56, 0.47, 0.32)
	var rune := Color(0.95, 0.80, 0.38)
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
	# 镇岳符印（山形三峰，发光呼吸）
	var mark_a := 0.6 + 0.3 * sin(_anim_time * 2.8)
	var m := Vector2(0.5, -1.0).rotated(rot)
	draw_polyline(PackedVector2Array([
		m + Vector2(-3.2, 1.8), m + Vector2(-1.1, -1.8), m + Vector2(0.6, 0.6),
		m + Vector2(2.0, -2.4), m + Vector2(3.8, 1.8)
	]), Color(rune, mark_a), 1.2, true)

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
	# 剑格与剑柄灵珠
	draw_line(Vector2(-5.5, -3.0).rotated(tilt), Vector2(-5.5, 3.0).rotated(tilt), edge, 1.3, true)
	draw_circle(Vector2(-7.5, 0.0).rotated(tilt), 1.5, Color(0.90, 0.98, 1.0, 0.9))
	# 剑尖灵光
	draw_circle(Vector2(13.0, 0.0).rotated(tilt), 1.2 + 0.3 * sin(_anim_time * 6.0), Color(1.0, 1.0, 1.0, 0.85))
