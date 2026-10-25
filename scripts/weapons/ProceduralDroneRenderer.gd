class_name ProceduralDroneRenderer
extends Node2D

## 环绕御灵渲染器（新野兽派 · 平涂版）
## 为 12 个御灵类武器本体与祭坛灵兽「灵珑」画环绕体。画法与武器侧野兽派接管
## （BrutalistCommon.gd）同一口径：平涂色块 + 粗墨描边 + 右下硬偏移投影，
## 零辉光 / 零渐变 / 零装饰纹；升星只用撞色方钉（star_studs），不复旧画法的辉光档。
## 每只灵兽 = 五行主色一大块（BC.pal，灵珑用本文件专属平涂色）+ 撞色一处 + 墨黑；
## 硬边几何（多边形硬折线，自画圆弧低分段 ≤12 段）。
## 旧「冷冽国风」画法的柔和光晕 / 透光羽 / 流光点 / 飘带 / 云雷纹已全部砍除
## （_soft_glow 已删，本文件不再引用 GameStyle 取色）。
## 状态输入（宿主每帧灌入）全部保留，一律以硬边几何表达，不回退柔光：
##   speed_ratio 驱动态度（焰苗摆幅 / 灵尘）· bank_angle 只倾躯体组（足影不随动）·
##   hp_ratio 低于 0.3 显墨色裂纹 · charge_ratio 显蓄力灵光球 ·
##   spawn_glow 出场一拍（撞色硬边六角环从外向本体收拢 + 方钉内聚）· _anim_time 相位。

const BC = preload("res://scripts/weapons/shapes/BrutalistCommon.gd")

## 灵珑（祭坛灵兽）三套平涂配色（2026-10-25 重设计）：同场多只灵兽不撞色，
## 档位由祭坛召唤侧按「场上未占用最小档」分配（pick_palette_idx）。
## body/accent/pale 三键与旧 LING_BODY/LING_ACCENT/LING_PALE 同义，0 档即原配色。
const PALETTES := [
	{"body": Color(0.42, 0.80, 0.76), "accent": Color(0.96, 0.85, 0.30), "pale": Color(0.93, 0.97, 0.94)},  # 0 灵青（原配色）
	{"body": Color(0.95, 0.42, 0.34), "accent": Color(1.0, 0.78, 0.30), "pale": Color(0.97, 0.93, 0.88)},   # 1 赤焰
	{"body": Color(0.58, 0.48, 0.96), "accent": Color(0.82, 0.90, 1.0), "pale": Color(0.93, 0.95, 1.0)},    # 2 紫电
]

## 配色档位：仅灵珑（YUAN_LING）消费，宿主（SpiritBeast）召唤时灌入
var palette_idx: int = 0

## 本档主色：祭坛现身演出（灵光/灵环）取同色，让登场一拍与灵兽本体一个色系
static func body_color(idx: int) -> Color:
	return PALETTES[clampi(idx, 0, PALETTES.size() - 1)]["body"]

## 从场上灵兽列表挑一个未被占用的最小配色档（全占满时按数量取模回落）
static func pick_palette_idx(beasts: Array) -> int:
	var used := {}
	for b in beasts:
		if b != null and is_instance_valid(b):
			used[int(b.palette_idx)] = true
	for i in PALETTES.size():
		if not used.has(i):
			return i
	return beasts.size() % PALETTES.size()

enum DroneKind {
	LINGDIE,        ## 灵蝶：木色硬边四翅 + 翅尖撞色三角 + 墨身方头
	HANQUAN_YULIAN, ## 寒泉玉莲：双层八角硬边莲盘 + 撞色莲心
	HUNYUAN_ZHONG,  ## 混元钟：土色宽钟身 + 口缘撞色带 + 墨拱钮（无舌，沉稳）
	HAOJIN_LUN,     ## 昊金轮：旋转六棱轮盘 + 三根贯穿墨辐 + 撞色轴心
	LIHUO_YA,       ## 离火鸦：火色硬翼 + 墨描圆身 + 撞色焰尾三杆
	XUANWU_PEI,     ## 玄武佩：双环玉璧（主色宽环 + 撞色细环）+ 墨系绳
	YUAN_LING,      ## 灵珑：祭坛召唤灵兽，圆球光灵真身（平涂版：正圆灵魄 + 金焰苗 + 双耳芽）
	JINMING_LING,   ## 金鸣铃：白金铃身 + 口缘撞色带 + 反摆墨铃舌
	MULING_OU,      ## 木灵偶：木色偶人 + 墨关节方钉 + 胸口撞色方章
	BINGPO_ZHU,     ## 冰魄珠：六棱珠体 + 环绕六片冰晶三角 + 撞色内棱
	CHIYAN_YING,    ## 赤炎萤：火色腹块 + 墨头 + 呼吸涨缩的撞色尾灯
	TULING_SHI,     ## 土灵石：七棱山岩 + 墨裂纹 + 撞色镇岳山形一笔
	JIAN_LING       ## 剑灵：硬边剑形精魂 + 撞色剑格与剑首
}

@export var kind: DroneKind = DroneKind.LINGDIE
@export var star: int = 1

## 速度权重（0=悬停 1=全速）：仅灵珑（YUAN_LING）消费，由宿主按实际移速灌入，
## 驱动焰苗摆幅 / 尾后移动方钉灵尘
var speed_ratio: float = 0.0

## 侧倾角（弧度）：仅灵珑消费 —— 按朝向系下的横向走位 bank，只倾躯体组（耳芽/焰苗/
## 双眸/裂纹/蓄力球随动，足下影块与出场环不随）；宿主按 velocity.x * 朝向符号归一灌入，
## 左右镜像由 scale.x 承担
var bank_angle: float = 0.0

## 生命比（0..1）：仅灵珑消费，由宿主（SpiritBeast）灌入 —— 灵兽不挂血条，
## 生命全由本体传达：灵目墨色浓淡，低于 30% 浮现镜像墨色裂纹（随灵息闪烁）
var hp_ratio: float = 1.0

## 蓄力比（0..1）：仅灵珑消费，由宿主（SpiritBeast）三连灵羽弹蓄力灌入 ——
## 面前撞色灵光圆盘随蓄力涨大，连发时随剩余发数递减（余辉）
var charge_ratio: float = 0.0

## 出场辉光（1→0 自减）：仅灵珑消费，宿主（SpiritBeast）召唤出场时灌 1 ——
## 撞色硬边六角环从外圈向本体收拢 + 六颗方钉内聚，衔接祭坛冲击环的「现身」一拍
var spawn_glow: float = 0.0

## 受击闪白（1→0 自减）：仅灵珑消费，宿主（SpiritBeast）受击时灌 1 ——
## 平涂色块（圆身/耳芽/焰苗）整体向月白提亮一拍回落，墨环保持纯黑：
## 不走宿主 modulate 全节点提亮（那会把墨描边一起提灰，毁野兽派轮廓）
var hit_flash: float = 0.0

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
	hit_flash = maxf(0.0, hit_flash - delta / 0.16)
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

# ----------------- 共用小构件 -----------------

## 五行归属：与 WeaponData 各御灵 tags 的五元素一致，取 BC.pal 平涂配色
func _elem() -> String:
	match kind:
		DroneKind.HANQUAN_YULIAN, DroneKind.BINGPO_ZHU:
			return "water"
		DroneKind.HUNYUAN_ZHONG, DroneKind.XUANWU_PEI, DroneKind.TULING_SHI:
			return "earth"
		DroneKind.HAOJIN_LUN, DroneKind.JINMING_LING, DroneKind.JIAN_LING:
			return "metal"
		DroneKind.LIHUO_YA, DroneKind.CHIYAN_YING:
			return "fire"
		_:
			return "wood"  # LINGDIE / MULING_OU

## 正 N 边形顶点（硬边轮盘/珠体/莲盘共用，rot 为整体转角）
func _ngon(c: Vector2, radius: float, n: int, rot: float = 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(n):
		var a: float = rot + TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a), sin(a)) * radius)
	return pts

## 椭圆多边形采样（灵珑足下硬边影块）
func _ellipse_polygon(center: Vector2, rx: float, ry: float, segs: int = 16) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segs):
		var a: float = float(i) / float(segs) * TAU
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts

## 躯体组统一绕 pivot 旋转 bank（足影/出场环不转 —— 悬浮侧倾只倾身体）
func _rot_pts(pts: PackedVector2Array, pivot: Vector2, a: float) -> PackedVector2Array:
	if absf(a) < 0.0005:
		return pts
	var out := PackedVector2Array()
	for p in pts:
		out.append(pivot + (p - pivot).rotated(a))
	return out

func _rot_one(p: Vector2, pivot: Vector2, a: float) -> Vector2:
	return pivot + (p - pivot).rotated(a)

## 绕原点整体旋转（铃/剑/石等自身摆动共用，复用 _rot_pts）
func _rot_all(pts: PackedVector2Array, a: float) -> PackedVector2Array:
	return _rot_pts(pts, Vector2.ZERO, a)

# ----------------- 1. 灵蝶（木 · 硬边四翅 + 翅尖撞色） -----------------
## 旧画法转化：透光羽翼/翅脉/伴飞灵粉/梢端莹光全砍。四翅改平涂硬边多边形，
## 前翅尖一整块撞色三角（唯一的「亮处」），蝶身压成粗墨竖杆 + 方头。
func _draw_spirit_butterfly() -> void:
	var pal: Dictionary = BC.pal(_elem())
	var body: Color = pal["body"]
	var accent: Color = pal["accent"]
	# 振翅周期（与旧拍同频，约 5Hz）
	var flap_x := 0.40 + 0.60 * absf(sin(_anim_time * 12.0))
	# 后翅（主色暗档，先画压在前翅下面）
	for side in [-1.0, 1.0]:
		var hind := PackedVector2Array([
			Vector2(side * 1.0, 2.0), Vector2(side * 10.0 * flap_x, 5.0),
			Vector2(side * 7.0 * flap_x, 11.0), Vector2(side * 0.5, 5.5),
		])
		BC.flat(self, hind, body.darkened(0.22), 1.4)
	# 前翅（主色大块）+ 翅尖撞色三角（随翅收展）
	for side in [-1.0, 1.0]:
		var fore := PackedVector2Array([
			Vector2(side * 1.0, -1.0), Vector2(side * 14.0 * flap_x, -12.0),
			Vector2(side * 11.0 * flap_x, -1.5), Vector2(side * 1.5, 2.0),
		])
		BC.flat(self, fore, body, 1.8)
		var tip_tri := PackedVector2Array([
			Vector2(side * 14.0 * flap_x, -12.0), Vector2(side * 11.0 * flap_x, -1.5),
			Vector2(side * 7.0 * flap_x, -6.0),
		])
		BC.flat(self, tip_tri, accent, 1.0)
	# 躯干粗墨竖杆 + 方头
	BC.bar(self, Vector2(0, -7.0), Vector2(0, 7.0), 3.0, BC.INK)
	BC.square(self, Vector2(0, -8.8), 1.8, body.darkened(0.40), 1.2)
	# 触角（两根硬墨线）
	draw_line(Vector2(0, -10.0), Vector2(-4.0, -13.5), BC.INK, 1.4, true)
	draw_line(Vector2(0, -10.0), Vector2(4.0, -13.5), BC.INK, 1.4, true)
	# 升星方钉（左右前翅中段）
	BC.star_studs(self, star, Vector2(-5.0, -5.5), Vector2(5.0, -5.5), accent)

# ----------------- 2. 寒泉玉莲（水 · 双层八角莲盘 + 撞色莲心） -----------------
## 旧画法转化：八瓣凝露/反旋光环/HDR 灵蕊全砍。改双层八角硬边莲盘（内层转 22.5°
## 压出层叠瓣感），莲心一枚撞色圆盘 + 墨方钉。
func _draw_ice_lotus() -> void:
	var pal: Dictionary = BC.pal(_elem())
	var body: Color = pal["body"]
	var accent: Color = pal["accent"]
	var rot := _anim_time * 1.2
	# 外层八角莲盘（慢旋）
	BC.flat(self, _ngon(Vector2.ZERO, 13.5, 8, rot), body, 2.0)
	# 内层莲盘（转 22.5° 错瓣，主色暗档 —— 层叠瓣）
	BC.flat(self, _ngon(Vector2.ZERO, 8.8, 8, rot + PI / 8.0), body.darkened(0.28), 1.4)
	# 八道墨色瓣缝（外环放射短墨线，把圆盘读成八瓣莲）
	for i in range(8):
		var a: float = rot + PI / 8.0 + TAU * float(i) / 8.0
		draw_line(Vector2(cos(a), sin(a)) * 8.0, Vector2(cos(a), sin(a)) * 12.6, BC.INK, 1.6, true)
	# 莲心（撞色圆盘 + 小墨方芯 —— 芯用裸方点，方钉描边会吞掉撞色）
	BC.disc(self, Vector2.ZERO, 4.8, accent, 1.4)
	draw_rect(Rect2(Vector2(-0.8, -0.8), Vector2(1.6, 1.6)), BC.INK)
	# 升星方钉（外盘对瓣位置）
	BC.star_studs(self, star, Vector2(10.5, 0.0).rotated(rot), Vector2(-10.5, 0.0).rotated(rot), accent)

# ----------------- 3. 混元钟（土 · 宽钟身 + 口缘撞色带） -----------------
## 旧画法转化：云雷横纹/兽面呼吸符点/钟声余韵音弧全砍。宽钟身平涂 + 口缘一整条
## 撞色带 + 墨拱钮 + 墨方符钉，整钟绕顶轻摆（摆感保留）。
func _draw_ancient_bell() -> void:
	var pal: Dictionary = BC.pal(_elem())
	var body: Color = pal["body"]
	var accent: Color = pal["accent"]
	var sway := sin(_anim_time * 2.2) * 0.10
	# 钟钮拱（低分段硬折半环：墨描 + 主色芯，深底上也能读出钮）
	var loop := PackedVector2Array()
	for i in range(5):
		var a: float = PI + PI * float(i) / 4.0
		loop.append(Vector2(0, -10.0) + Vector2(cos(a), sin(a)) * 3.4)
	draw_polyline(_rot_all(loop, sway), BC.INK, 3.6, true)
	draw_polyline(_rot_all(loop, sway), body, 1.6, true)
	# 钟身（上窄下阔硬梯形，随 sway 摆；拔高钟身避免读成斗笠）
	var bell := PackedVector2Array([
		Vector2(-5.0, -10.0), Vector2(5.0, -10.0),
		Vector2(10.0, 6.5), Vector2(11.5, 10.0),
		Vector2(-11.5, 10.0), Vector2(-10.0, 6.5),
	])
	BC.flat(self, _rot_all(bell, sway), body, 2.2)
	# 口缘撞色带（钟的「一眼亮」，随 sway 摆）
	var rim := PackedVector2Array([
		Vector2(-10.2, 6.0), Vector2(10.2, 6.0), Vector2(11.5, 10.0), Vector2(-11.5, 10.0),
	])
	BC.flat(self, _rot_all(rim, sway), accent, 1.2)
	# 钟腹墨方符钉（替代旧兽面呼吸点）
	BC.square(self, Vector2(0, 0.0).rotated(sway), 2.0, BC.INK, 1.0)
	# 升星方钉（钟腹两肩）
	BC.star_studs(self, star, Vector2(-4.5, -4.5).rotated(sway), Vector2(4.5, -4.5).rotated(sway), accent)

# ----------------- 4. 昊金轮（金 · 旋转六棱轮盘 + 贯穿墨辐） -----------------
## 旧画法转化：反旋虚光轮/辐梢流光点/HDR 轴心全砍。六棱轮盘整体旋转（硬边自转感），
## 三根贯穿墨辐 + 撞色轴心盘。
func _draw_golden_wheel() -> void:
	var pal: Dictionary = BC.pal(_elem())
	var body: Color = pal["body"]
	var accent: Color = pal["accent"]
	var rot := _anim_time * 4.0
	# 六棱轮盘（整体旋转）
	BC.flat(self, _ngon(Vector2.ZERO, 13.0, 6, rot), body, 2.4)
	# 三根贯穿辐条（六辐，粗墨，随轮转）
	for i in range(3):
		var a: float = rot + PI * float(i) / 3.0
		var dir := Vector2(cos(a), sin(a))
		draw_line(-dir * 11.0, dir * 11.0, BC.INK, 2.2, true)
	# 轴心撞色盘 + 小墨方芯（裸方点，方钉描边会吞掉撞色）
	BC.disc(self, Vector2.ZERO, 4.0, accent, 1.4)
	draw_rect(Rect2(Vector2(-0.8, -0.8), Vector2(1.6, 1.6)), BC.INK)
	# 升星方钉（两根辐条中段，随轮转）
	var sa: float = rot + PI / 6.0
	var sb: float = rot + PI + PI / 6.0
	BC.star_studs(self, star, Vector2(cos(sa), sin(sa)) * 7.5, Vector2(cos(sb), sin(sb)) * 7.5, accent)

# ----------------- 5. 离火鸦（火 · 硬翼 + 焰尾三杆） -----------------
## 旧画法转化：透光火羽/焰喙 HDR 金目/上浮火星余烬全砍。双翼平涂硬三角随扑动收展，
## 头身合一块暗档硬边剪影（圆盘小件会被粗墨环吃掉），撞色留给焰喙 + 金目 + 焰尾三杆。
func _draw_fire_crow() -> void:
	var pal: Dictionary = BC.pal(_elem())
	var body: Color = pal["body"]
	var accent: Color = pal["accent"]
	var flap_x := 0.45 + 0.55 * absf(sin(_anim_time * 11.0))
	# 双翼（主色硬三角，扑动）
	for side in [-1.0, 1.0]:
		var wing := PackedVector2Array([
			Vector2(side * 1.5, -2.0), Vector2(side * 13.0 * flap_x, -9.5),
			Vector2(side * 9.0 * flap_x, 0.5), Vector2(side * 1.5, 2.5),
		])
		BC.flat(self, wing, body, 1.6)
	# 焰尾三杆（撞色，随相位摆）
	for i in range(3):
		var sway: float = sin(_anim_time * 7.0 + float(i) * 1.1) * 1.6
		var bx: float = (float(i) - 1.0) * 3.0
		BC.bar(self, Vector2(bx, 5.0), Vector2(bx * 1.4 + sway, 11.5), 2.2, accent)
	# 头身一体剪影（主色暗档，一块读出头与腹）
	var deep := body.darkened(0.35)
	BC.flat(self, PackedVector2Array([
		Vector2(0.0, -9.0), Vector2(2.8, -7.6), Vector2(3.4, -4.6), Vector2(4.6, -0.5),
		Vector2(3.0, 5.0), Vector2(-3.0, 5.0), Vector2(-4.6, -0.5),
		Vector2(-3.4, -4.6), Vector2(-2.8, -7.6),
	]), deep, 1.4)
	# 撞色焰喙（顶出墨描边之外的硬三角）
	draw_colored_polygon(PackedVector2Array([
		Vector2(-1.5, -8.0), Vector2(1.5, -8.0), Vector2(0.0, -11.0),
	]), accent)
	# 金目两粒（硬边方点，落在头身亮芯内）
	draw_rect(Rect2(Vector2(-2.0, -6.4), Vector2(1.5, 1.5)), accent)
	draw_rect(Rect2(Vector2(0.5, -6.4), Vector2(1.5, 1.5)), accent)
	# 升星方钉（腹身两侧）
	BC.star_studs(self, star, Vector2(-2.4, 1.5), Vector2(2.4, 1.5), accent)

# ----------------- 6. 玄武佩（土 · 双环玉璧 + 墨系绳） -----------------
## 旧画法转化：璧面云纹/对称流云/绳结坠珠莹光全砍。主色宽环 + 撞色细环的双环璧，
## 墨短绳 + 墨方坠，环上布硬边方钉（悬浮起伏保留）。
func _draw_jade_pendant() -> void:
	var pal: Dictionary = BC.pal(_elem())
	var body: Color = pal["body"]
	var accent: Color = pal["accent"]
	var off := Vector2(0, sin(_anim_time * 2.4) * 1.2)
	# 外璧宽环（主色）+ 内璧细环（撞色）
	BC.ring(self, off, 10.5, 3.6, body)
	BC.ring(self, off, 5.6, 2.2, accent)
	# 系绳（墨短杆）与绳结坠（墨方钉，轻摆）
	BC.bar(self, off + Vector2(0, -10.5), off + Vector2(0, -13.8), 2.0, BC.INK)
	var bead_x := sin(_anim_time * 2.8) * 1.2
	BC.square(self, off + Vector2(bead_x, -15.4), 1.6, BC.INK, 1.0)
	# 璧环硬边布点：左右墨钉 + 升星撞色钉（上下）
	BC.square(self, off + Vector2(-10.5, 0.0), 1.4, BC.INK, 1.0)
	BC.square(self, off + Vector2(10.5, 0.0), 1.4, BC.INK, 1.0)
	BC.star_studs(self, star, off + Vector2(0.0, 10.5), off + Vector2(0.0, -10.5), accent)

# ----------------- 7. 灵珑（祭坛灵兽：圆球光灵） -----------------
## 「灵珑」圆球光灵重做（2026-10-24 三次修改）：推倒人脸脸窗方案 —— 无脸圆球 +
## 特征部件，形体语言对齐随行灵兽 PetData 的圆球光灵（灵动可爱口径），画风仍归
## 野兽派平涂（硬投影 + 粗墨环），保留全部状态输入 ——
##   · 正圆灵青圆盘（BC.disc），呼吸半径 13.5±0.8；生命低落整体转暗（无脸下生命由本体传达）；
##   · 无脸：仅左上月白高光一点，随灵息呼吸明灭；
##   · 头顶金焰苗（单块双焰舌硬边多边形，随 speed 摆幅摇曳）+ 耳芽两粒（深灵青小圆耳，
##     画在圆身之前、根部藏进墨环后，修旧双角「浮针」断开感）；
##   · 环绕灵尘双星（撞色小方钉沿扁椭圆慢速绕体，画在圆身之前绕后遮挡，灵动一拍）；
##   · 足下硬边影块、出场撞色六角环收拢 + 方钉内聚、濒死墨裂纹、蓄力撞色圆盘 +
##     墨方钉旋绕、尾后移动灵尘全部保留。
## 本体沿 y 轴镜像对称，面朝 +x 语义由蓄力球与移动灵尘承担，scale.x 翻转后形态不变；
## bank_angle 只倾躯体组（圆身旋转不变免转点，耳芽/焰苗/高光/裂纹/蓄力球随动，
## 足影/出场环不随动），speed_ratio 驱动焰苗摆幅 / 尾后灵尘。
func _draw_yuan_ling() -> void:
	# 本只灵珑的调色板（2026-10-25 三套配色：同场不撞色，宿主灌 palette_idx）
	var ling_pal: Dictionary = PALETTES[clampi(palette_idx, 0, PALETTES.size() - 1)]
	var ling_body: Color = ling_pal["body"]
	var ling_acc: Color = ling_pal["accent"]
	var ling_pale: Color = ling_pal["pale"]
	# 灵息强度：满血 1.0，随生命衰减（保底 0.25 不致全熄）；濒死程度与灵息闪烁
	var spirit: float = 0.25 + 0.75 * clampf(hp_ratio, 0.0, 1.0)
	var low: float = clampf((0.30 - hp_ratio) / 0.30, 0.0, 1.0)
	var flicker: float = 1.0 - low * (0.5 + 0.5 * sin(_anim_time * 14.0)) * 0.45
	# 出场辉光：1→0 自减，硬边现身一拍
	var sg: float = clampf(spawn_glow, 0.0, 1.0)
	# 受击闪白：1→0 自减（约 0.16s），平涂块提亮回落
	var hf: float = clampf(hit_flash, 0.0, 1.0)
	# 常用色（撞色 / 墨，带 alpha 派生色多处用，先取好）
	var acc := ling_acc
	var ink := BC.INK

	# 悬浮呼吸起伏（灵身随呼吸整体上浮下沉，与旧拍同频）
	var bob: float = sin(_anim_time * 2.6) * 1.8
	var pivot := Vector2(0.0, -2.0 + bob)
	var core_r: float = 13.5 + 0.8 * sin(_anim_time * 2.4)

	# 1. 足下硬边影块（贴地低分段椭圆平涂暗影，出场时外扩；不随 bank）
	draw_colored_polygon(
		_ellipse_polygon(Vector2(0.0, 16.5), 16.0 + 6.0 * sg, 3.6, 8),
		Color(ink.r, ink.g, ink.b, BC.SHADOW.a * (0.55 + 0.25 * sg)))

	# 2. 出场现身一拍（spawn_glow 1→0：撞色硬边六角环向本体收拢 + 六颗方钉内聚；不随 bank）
	if sg > 0.01:
		var ring_r: float = lerpf(8.0, 30.0, sg)
		var hexa := PackedVector2Array()
		for i in range(7):
			var a: float = TAU * float(i) / 6.0 - PI * 0.5
			hexa.append(pivot + Vector2(cos(a), sin(a)) * ring_r)
		draw_polyline(hexa, Color(acc.r, acc.g, acc.b, sg), 2.4, true)
		for i in range(6):
			var a2: float = TAU * float(i) / 6.0 + _anim_time * 2.0
			var sq_c := pivot + Vector2(cos(a2), sin(a2)) * ring_r
			var hs: float = 1.2 + 1.2 * sg
			draw_rect(Rect2(sq_c - Vector2(hs, hs), Vector2(hs * 2.0, hs * 2.0)),
				Color(acc.r, acc.g, acc.b, sg))

	# 3. 耳芽两粒（深灵青小圆耳，画在圆身之前、根部藏进墨环后 —— 修旧双角「浮针」断开感；随 bank）
	for side in [-1.0, 1.0]:
		var ear_c := _rot_one(pivot + Vector2(side * core_r * 0.66, -core_r * 0.80), pivot, bank_angle)
		draw_circle(ear_c, core_r * 0.20 + 1.1, ink)
		draw_circle(ear_c, core_r * 0.20, ling_body.darkened(0.25).lerp(ling_pale, hf * 0.75))

	# 4. 环绕灵尘双星（撞色小方钉沿扁椭圆慢速绕体，画在圆身之前 —— 绕到身后被灵魄
	#    挡住、绕到两侧探头，是真「环绕」而不是贴面漂浮；随 bank）
	for i in range(2):
		var oa: float = _anim_time * 1.7 + PI * float(i)
		var op := _rot_one(pivot + Vector2(cos(oa) * (core_r + 7.5),
			sin(oa) * (core_r * 0.32 + 1.0) - 1.0), pivot, bank_angle)
		var osz: float = 1.8 - 0.4 * float(i)
		draw_rect(Rect2(op - Vector2(osz, osz), Vector2(osz * 2.0, osz * 2.0)),
			Color(acc.r, acc.g, acc.b, 0.9))

	# 5. 正圆灵魄身（圆对 bank 旋转不变，disc 免转点；硬投影 + 粗墨环 + 灵青平涂；
	#    生命低落时圆身整体转暗 —— 无脸口径下生命仍由本体传达）
	var body_col: Color = ling_body.darkened(0.30 * (1.0 - spirit)).lerp(ling_pale, hf * 0.75)
	BC.disc(self, pivot, core_r, body_col, 2.4)

	# 6. 头顶金焰苗（单块双焰舌硬边多边形：主舌高挑、侧舌外倾，根部压住墨环；
	#    随 speed 摆幅摇曳；随 bank）
	var crest_sway: float = sin(_anim_time * 2.4) * (0.06 + 0.12 * speed_ratio)
	var crown := PackedVector2Array([
		pivot + Vector2(-core_r * 0.26, -core_r * 0.62),
		pivot + Vector2(-core_r * 0.30 - crest_sway * 6.0, -core_r * 1.12),
		pivot + Vector2(-core_r * 0.08, -core_r * 0.92),
		pivot + Vector2(core_r * 0.10 + crest_sway * 18.0, -core_r * 1.52),
		pivot + Vector2(core_r * 0.22, -core_r * 0.86),
		pivot + Vector2(core_r * 0.26, -core_r * 0.62),
	])
	BC.flat(self, _rot_pts(crown, pivot, bank_angle), acc.lerp(ling_pale, hf * 0.6), 1.4)

	# 7. 月白高光一点（无脸口径：单点亮斑代替五官，随灵息呼吸明灭；随 bank）
	var hl_a: float = 0.55 + 0.25 * sin(_anim_time * 2.6)
	draw_circle(_rot_one(pivot + Vector2(-core_r * 0.30, -core_r * 0.34), pivot, bank_angle),
		core_r * 0.17, Color(ling_pale.r, ling_pale.g, ling_pale.b, hl_a))

	# 8. 濒死裂纹（hp_ratio < 0.3 浮现的墨色裂痕，左右镜像一对，随灵息闪烁；随 bank）
	if low > 0.0:
		var crack_a: float = (0.35 + 0.45 * low) * flicker
		var crack_col := Color(ink.r, ink.g, ink.b, crack_a)
		var crack_r := PackedVector2Array([
			pivot + Vector2(4.5, -core_r * 0.62), pivot + Vector2(2.5, -core_r * 0.10),
			pivot + Vector2(5.0, core_r * 0.35),
		])
		draw_polyline(_rot_pts(crack_r, pivot, bank_angle), crack_col, 1.6, true)
		var crack_l := PackedVector2Array()
		for p3 in crack_r:
			crack_l.append(Vector2(pivot.x - (p3.x - pivot.x), p3.y))
		draw_polyline(_rot_pts(crack_l, pivot, bank_angle), crack_col, 1.3, true)

	# 9. 面前蓄力灵光球（charge_ratio 驱动：撞色圆盘涨大 + 三颗墨方钉旋绕，硬边零辉光；随 bank）
	if charge_ratio > 0.01:
		var cp := _rot_one(pivot + Vector2(18.5, 0.0), pivot, bank_angle)
		var cr: float = 2.0 + 5.0 * charge_ratio
		var ca: float = clampf(charge_ratio * spirit * flicker, 0.0, 1.0)
		BC.disc(self, cp, cr, Color(acc.r, acc.g, acc.b, ca), 1.6)
		for i in range(3):
			var sa: float = _anim_time * 7.0 + TAU * float(i) / 3.0
			var sq_p := cp + Vector2(cos(sa), sin(sa)) * (cr + 3.0)
			draw_rect(Rect2(sq_p - Vector2(1.2, 1.2), Vector2(2.4, 2.4)),
				Color(ink.r, ink.g, ink.b, ca))

	# 10. 移动灵尘（speed_ratio > 0.2：尾后三颗撞色小方钉，随速度显隐）
	if speed_ratio > 0.2:
		for i in range(3):
			var di := float(i)
			var mp := pivot + Vector2(-core_r - 4.0 - di * 5.0,
				core_r * 0.2 + di * 2.0 + sin(_anim_time * 7.5 + di * 1.2) * 1.8)
			var ds: float = (1.0 - di * 0.28) * clampf(speed_ratio, 0.0, 1.0)
			draw_rect(Rect2(mp - Vector2(1.4, 1.4) * ds, Vector2(2.8, 2.8) * ds),
				Color(acc.r, acc.g, acc.b, 0.85 * ds))

	# 11. 升星方钉（耳芽中心；灵兽宿主不设 star，恒 1 时自动不画）
	BC.star_studs(self, star,
		_rot_one(pivot + Vector2(-core_r * 0.66, -core_r * 0.80), pivot, bank_angle),
		_rot_one(pivot + Vector2(core_r * 0.66, -core_r * 0.80), pivot, bank_angle), acc)

# ----------------- 8. 金鸣铃（金 · 白金铃身 + 反摆墨铃舌） -----------------
## 旧画法转化：云雷横纹/符点莹光/声波弧全砍。白金铃身平涂 + 口缘撞色带 + 墨拱钮，
## 铃舌改墨杆 + 墨盘随摆反向荡（摆感保留），与混元钟以「有舌有绳、白身」区分。
func _draw_golden_bell() -> void:
	var pal: Dictionary = BC.pal(_elem())
	var body: Color = pal["body"]
	var accent: Color = pal["accent"]
	var sway := sin(_anim_time * 3.0) * 0.12
	# 吊绳（墨短杆，不随摆）
	BC.bar(self, Vector2(0, -14.5), Vector2(0, -9.5), 1.8, BC.INK)
	# 钟钮小拱（低分段硬折线：墨描 + 白金芯，随摆）
	var loop := PackedVector2Array()
	for i in range(5):
		var a: float = PI + PI * float(i) / 4.0
		loop.append(Vector2(0, -9.5) + Vector2(cos(a), sin(a)) * 2.8)
	draw_polyline(_rot_all(loop, sway), BC.INK, 3.2, true)
	draw_polyline(_rot_all(loop, sway), body, 1.4, true)
	# 铃身（上窄下阔钟形，随 sway 轻摆）
	var bell := PackedVector2Array([
		Vector2(-4.5, -9.5), Vector2(4.5, -9.5),
		Vector2(7.5, 4.0), Vector2(8.5, 7.0),
		Vector2(-8.5, 7.0), Vector2(-7.5, 4.0),
	])
	BC.flat(self, _rot_all(bell, sway), body, 2.0)
	# 口缘撞色带（铃的「一眼金」）
	var rim := PackedVector2Array([
		Vector2(-7.7, 4.6), Vector2(7.7, 4.6), Vector2(8.5, 7.0), Vector2(-8.5, 7.0),
	])
	BC.flat(self, _rot_all(rim, sway), accent, 1.2)
	# 铃舌（随摆反向荡：墨杆 + 墨盘，悬在口缘下方不压撞色带）
	var clapper_x := -sway * 40.0
	BC.bar(self, Vector2(0, 7.5).rotated(sway), Vector2(clapper_x, 11.0), 1.6, BC.INK)
	draw_circle(Vector2(clapper_x, 12.2), 1.9, BC.INK)
	# 升星方钉（铃身两肩）
	BC.star_studs(self, star, Vector2(-3.5, -5.5).rotated(sway), Vector2(3.5, -5.5).rotated(sway), accent)

# ----------------- 9. 木灵偶（木 · 偶人 + 墨关节 + 撞色方章） -----------------
## 旧画法转化：生机符印呼吸辉光/关节莹光点/芽梢莹点全砍。偶人全平涂：圆头方眼 +
## 硬梯形躯干 + 短木杆四肢（摆臂保留）+ 墨方关节钉，胸口一枚撞色方章。
func _draw_wood_puppet() -> void:
	var pal: Dictionary = BC.pal(_elem())
	var body: Color = pal["body"]
	var accent: Color = pal["accent"]
	var off := Vector2(0, sin(_anim_time * 2.6) * 1.2)
	var limb := body.darkened(0.32)
	var arm_sw := sin(_anim_time * 3.4) * 2.0
	# 四肢（短木杆，先画压在躯干下；摆臂保留）
	BC.bar(self, off + Vector2(-1.8, 6.0), off + Vector2(-2.6, 11.5), 2.8, limb)
	BC.bar(self, off + Vector2(1.8, 6.0), off + Vector2(2.6, 11.5), 2.8, limb)
	BC.bar(self, off + Vector2(-3.0, -1.5), off + Vector2(-8.5, 1.5 + arm_sw), 2.8, limb)
	BC.bar(self, off + Vector2(3.0, -1.5), off + Vector2(8.5, 1.5 - arm_sw), 2.8, limb)
	# 躯干（硬梯形主色块）
	BC.flat(self, PackedVector2Array([
		off + Vector2(-3.5, -3.0), off + Vector2(3.5, -3.0),
		off + Vector2(2.5, 6.0), off + Vector2(-2.5, 6.0),
	]), body, 1.8)
	# 头（圆盘）+ 方眼两粒（硬边墨块，落在亮芯内）
	BC.disc(self, off + Vector2(0, -7.2), 4.4, body, 1.4)
	draw_rect(Rect2(off + Vector2(-2.0, -7.8), Vector2(1.3, 1.5)), BC.INK)
	draw_rect(Rect2(off + Vector2(0.7, -7.8), Vector2(1.3, 1.5)), BC.INK)
	# 头顶灵芽（两根短杆）
	BC.bar(self, off + Vector2(0, -11.0), off + Vector2(-2.4, -14.0), 1.6, limb)
	BC.bar(self, off + Vector2(0, -11.0), off + Vector2(2.4, -14.0), 1.6, limb)
	# 胸口撞色方章（唯一撞色块）
	BC.square(self, off + Vector2(0, 1.0), 2.0, accent, 1.2)
	# 四肢关节墨钉（硬边）
	for jp in [Vector2(-3.0, -1.5), Vector2(3.0, -1.5), Vector2(-1.8, 6.0), Vector2(1.8, 6.0)]:
		draw_rect(Rect2(off + jp - Vector2(0.9, 0.9), Vector2(1.8, 1.8)), BC.INK)
	# 升星方钉（双肩）
	BC.star_studs(self, star, off + Vector2(-4.6, -3.4), off + Vector2(4.6, -3.4), accent)

# ----------------- 10. 冰魄珠（水 · 六棱珠体 + 环绕冰晶三角） -----------------
## 旧画法转化：半透明幽蓝珠体/雪亮冰核 HDR/寒雾微光/雪芒闪烁全砍。六棱硬边珠体
## （反向微旋）+ 撞色内棱六边 + 六片环绕冰晶三角（自转保留）。
func _draw_ice_pearl() -> void:
	var pal: Dictionary = BC.pal(_elem())
	var body: Color = pal["body"]
	var accent: Color = pal["accent"]
	var rot := _anim_time * 1.8
	var spike := body.darkened(0.22)
	# 六片环绕冰晶（硬边三角，自转）
	for i in range(6):
		var ang: float = rot + TAU * float(i) / 6.0
		var c := Vector2(cos(ang), sin(ang)) * 10.5
		var tip := c + Vector2(cos(ang), sin(ang)) * 4.5
		var pl := c + Vector2(cos(ang + 0.55), sin(ang + 0.55)) * 2.4
		var pr := c + Vector2(cos(ang - 0.55), sin(ang - 0.55)) * 2.4
		BC.flat(self, PackedVector2Array([pl, tip, pr]), spike, 1.2)
	# 六棱珠体（反向微旋，主色大块）
	BC.flat(self, _ngon(Vector2.ZERO, 7.5, 6, -rot * 0.5), body, 2.0)
	# 内棱撞色六边形（错 30°，冰核）
	BC.flat(self, _ngon(Vector2.ZERO, 4.2, 6, -rot * 0.5 + PI / 6.0), accent, 1.0)
	# 升星方钉（珠体上下）
	BC.star_studs(self, star, Vector2(0, -5.8), Vector2(0, 5.8), accent)

# ----------------- 11. 赤炎萤（火 · 硬腹块 + 呼吸尾灯） -----------------
## 旧画法转化：薄透火翼/灯焰热晕环/触须莹光点全砍。火色大腹块 + 暗档小翼压身下 +
## 墨头墨须，尾灯改撞色圆盘呼吸涨缩缩在腹尾（萤的一眼点保留，不压腹块）。
func _draw_fire_firefly() -> void:
	var pal: Dictionary = BC.pal(_elem())
	var body: Color = pal["body"]
	var accent: Color = pal["accent"]
	var flap_x := 0.40 + 0.60 * absf(sin(_anim_time * 14.0))
	var deep := body.darkened(0.25)
	# 薄翼两扇（硬边三角，扑动；主色暗档压在身下）
	for side in [-1.0, 1.0]:
		var wing := PackedVector2Array([
			Vector2(side * 1.5, -3.0), Vector2(side * 9.5 * flap_x, -10.5),
			Vector2(side * 7.0 * flap_x, -3.0),
		])
		BC.flat(self, wing, deep, 1.2)
	# 尾腹（主色大块，头小腹大）
	BC.flat(self, PackedVector2Array([
		Vector2(-3.8, -1.0), Vector2(3.8, -1.0), Vector2(2.8, 7.0), Vector2(-2.8, 7.0),
	]), body, 1.6)
	# 头（墨盘）与触须（两根墨线）
	BC.disc(self, Vector2(0, -3.8), 2.6, BC.INK, 1.0)
	draw_line(Vector2(-1.0, -5.8), Vector2(-2.8, -8.4), BC.INK, 1.2, true)
	draw_line(Vector2(1.0, -5.8), Vector2(2.8, -8.4), BC.INK, 1.2, true)
	# 尾灯（撞色圆盘，呼吸涨缩 —— 萤的一眼点，缩在腹尾不吞腹块）
	var lamp_r: float = 2.2 + 0.6 * sin(_anim_time * 6.0)
	BC.disc(self, Vector2(0, 5.6), lamp_r, accent, 1.0)
	# 升星方钉（腹背）
	BC.star_studs(self, star, Vector2(-2.2, 0.8), Vector2(2.2, 0.8), accent)

# ----------------- 12. 土灵石（土 · 七棱山岩 + 撞色镇岳一笔） -----------------
## 旧画法转化：符文呼吸辉光/山脚环绕浮尘全砍。七棱山岩平涂微晃（晃感保留）+
## 墨裂纹两道（镜像保留）+ 撞色山形一笔镇岳符。
func _draw_earth_stone() -> void:
	var pal: Dictionary = BC.pal(_elem())
	var body: Color = pal["body"]
	var accent: Color = pal["accent"]
	var rot := sin(_anim_time * 1.6) * 0.15
	# 石体（七棱山岩断面，微晃）
	var stone := PackedVector2Array([
		Vector2(-6.5, -7.5), Vector2(0.0, -9.8), Vector2(6.5, -7.5),
		Vector2(8.5, 2.0), Vector2(3.0, 9.5), Vector2(-3.0, 9.5), Vector2(-8.5, 2.0),
	])
	BC.flat(self, _rot_all(stone, rot), body, 2.2)
	# 岩面裂纹两道（墨，镜像）
	draw_line(Vector2(-4.0, -4.5).rotated(rot), Vector2(-1.5, 0.5).rotated(rot), BC.INK, 1.4, true)
	draw_line(Vector2(4.0, -4.5).rotated(rot), Vector2(1.5, 0.5).rotated(rot), BC.INK, 1.4, true)
	# 镇岳符（撞色山形折线，一笔三峰）
	var m := Vector2(0.0, 0.5).rotated(rot)
	draw_polyline(PackedVector2Array([
		m + Vector2(-3.6, 2.2), m + Vector2(-1.4, -2.0), m + Vector2(0.2, 0.8),
		m + Vector2(2.0, -2.6), m + Vector2(4.2, 2.2),
	]), accent, 2.0, true)
	# 升星方钉（石面两肩）
	BC.star_studs(self, star, Vector2(-4.5, -2.5).rotated(rot), Vector2(4.5, -2.5).rotated(rot), accent)

# ----------------- 13. 剑灵（金 · 硬边剑形精魂） -----------------
## 旧画法转化：半透明剑身/灵气飘带/刃口流光/剑尖 HDR 灵光全砍。实心硬边剑：
## 主色剑身收锋 + 墨剑脊 + 撞色剑格 + 墨剑柄 + 撞色剑首方钉（悬浮轻倾保留）。
func _draw_sword_wisp() -> void:
	var pal: Dictionary = BC.pal(_elem())
	var body: Color = pal["body"]
	var accent: Color = pal["accent"]
	var tilt := sin(_anim_time * 2.2) * 0.2
	# 剑身（长四边形 + 收锋剑尖，主色大块，随 tilt 轻倾）
	var blade := PackedVector2Array([
		Vector2(14.0, 0.0), Vector2(2.0, -3.6), Vector2(-5.5, -2.4),
		Vector2(-5.5, 2.4), Vector2(2.0, 3.6),
	])
	BC.flat(self, _rot_all(blade, tilt), body, 2.0)
	# 剑脊墨线
	draw_line(Vector2(12.0, 0.0).rotated(tilt), Vector2(-4.5, 0.0).rotated(tilt), BC.INK, 1.2, true)
	# 剑格（撞色横杆）
	BC.bar(self, Vector2(-5.5, -4.2).rotated(tilt), Vector2(-5.5, 4.2).rotated(tilt), 2.8, accent)
	# 剑柄（墨杆）与剑首（撞色方钉）
	BC.bar(self, Vector2(-5.5, 0.0).rotated(tilt), Vector2(-10.5, 0.0).rotated(tilt), 2.4, BC.INK)
	BC.square(self, Vector2(-11.8, 0.0).rotated(tilt), 1.8, accent, 1.2)
	# 升星方钉（剑身前后段）
	BC.star_studs(self, star, Vector2(8.0, 0.0).rotated(tilt), Vector2(-2.0, 0.0).rotated(tilt), accent)
