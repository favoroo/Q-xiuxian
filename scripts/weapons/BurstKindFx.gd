class_name BurstKindFx
extends Node2D

## BURST 落点分化演出（2026-10-13）：9 把范围武器旧写法清一色「闪电柱+光环」，
## 天灯文案说火雨、画面是闪电。本渲染器按 burst_kind 出各自的落点形态：
##   fire_rain 火雨（天灯）  frost 冰刺（玄冥雷珠）  sonic 音波环（音笛）
##   drum 鼓震波（春雷鼓）   earth 地裂（裂山铎）   seal 坠印扬尘（巨印）
##   thunder 默认雷系不画（雷柱/闪电已在 ThunderBurst/LightningBolt 里）
## 全部几何由判定半径 radius 一个量派生（画多大==判多大），纯 _draw 零粒子零灯光；
## 作为 ThunderBurst 的常驻子节点随池复用，activate_fx 重铺字段即重生，零 instantiate。
##
## pixelfx 序列帧接入（2026-11-01 车道 F）：earth（地裂）/ frost（冰刺）两形态改由
## FxFlipbookPool 播放离线烘焙的源码序列帧承担主形态（earth_spike / ice_spikes），
## 自绘层退成「与判定半径同源的贴地底盘」并按 SHEET_BASE_ALPHA 压暗 —— 序列帧只管质感，
## 玩家仍能从底盘读出真实打击范围（铁律 7：画多大==判多大）。
## 序列帧配置缺失 / 资源未导入 / 被物理帧预算掐掉时 play() 返回 null，_sheet_played=false，
## 自动回退到下面原有的纯 _draw 形态（老画法一行未删，仍是唯一兜底）。
##
## pixelfx 序列帧接入（2026-11-07 车道 B）：线条件通刷——
##   sonic 音波环（sonic_ring）/ drum 鼓震波（thunderclap）/ seal 坠印扬尘（ground_slam）
##   三形态主形态改为 sheet；fire_rain 多枚小爆只对首枚（近中心那枚）叠一张 fire_ring。
## sonic/drum 由 sheet 整替（_sheet_played 时 _draw_* 早退，矢量环+刻度/震线全部下线，
## 代码仍在，回退 = 删掉早退那两行即复活）；seal 只把「重冲击环」交给 ground_slam，
## 扬尘环 + 10 尘点保留（坠印的「压」感靠尘，见 _draw_seal_dust）。命中半径/伤害一行不动。

var kind: String = "thunder"
var radius: float = 80.0
var tint: Color = Color.WHITE

const DUR := 0.38          ## 演出总时长（略短于 ThunderBurst 全亮档 0.45s 生命周期）
const GROUND_SQUASH := 0.62 ## 俯视透视压扁比（统一贴地基准，对齐实体双层软影与地面贴花）
const FIREBALLS := 5       ## 火雨落点数
const FROST_SPIKES := 7    ## 冰刺数
const SONIC_RINGS := 3     ## 音波环数
const EARTH_CRACKS := 6    ## 地裂条数
## fire_rain 只给首枚（近中心那枚）叠一张 fire_ring：多枚小爆逐枚播 sheet 会连环撞帧闸
## （FxFlipbookPool 同物理帧预算 + 16px 重叠丢弃），取 ~0.5 的小尺寸当单枚爆开的点缀，
## 其余四枚仍走矢量火核+余烬（见 _draw_fire_rain），一眼贴图化又不糊屏。
const FIRE_RING_SCALE_MULT := 0.5
## 序列帧接管主形态后自绘底盘的透明度系数：地裂裂缝 / 冰刺霜环压到这个档位，
## 只留「判定半径」的读法，不与 sheet 主体抢亮度（sheet 是主形态，底盘是范围脚注）。
const SHEET_BASE_ALPHA := 0.5

var _t: float = 0.0
## 本次演出是否成功起了 pixelfx 序列帧（earth/frost/sonic/drum/seal 专用）：false 时自绘形态全量兜底。
var _sheet_played: bool = false
## fire_rain 首枚 fire_ring 是否已起（本函数 _draw 每帧会多次进入，防重复播放）。
var _fire_ring_played: bool = false
## 重绘节流（2026-10-14）：演出窗口内原每帧无条件重绘，0.38s 演出 20Hz 足够流畅
## 60fps 档（2026-10-15 VisualRate 档位联动）：演出 0.38s 在 60fps 下只 23 帧，
## 20Hz 每 3 帧一画会露台阶，高帧档翻倍 40Hz；低档 20Hz 是 perf_probe 预算口径。
const HZ_LOW := 20.0
const HZ_HIGH := 40.0
static func _redraw_interval() -> float:
	return VisualRate.interval(HZ_HIGH, HZ_LOW)
var _draw_phase: float = 0.0

func _ready() -> void:
	_draw_phase = fposmod(float(get_instance_id() % 97) * 0.001, _redraw_interval())
	visible = false
	set_process(false)

## 重铺字段并开演（池化复用唯一入口）
## 2026-10-23 去重：本函数原先在 activate 阶段就发 HIT_SPARK 材质微粒，但那时还不知道劈没劈到人
## （ThunderBurst._deal_damage 是同帧 deferred），于是①劈空也在空地冒粒子，②劈中时
## ThunderBurst 末尾再发一支 = 同一落点双发（实测 frost 形态同帧 2 支）。
## 现在火花统一由 ThunderBurst._deal_damage 在 hits>0 之后调 emit_hit_spark() 发一支。
func activate_fx(p_kind: String, p_radius: float, p_tint: Color) -> void:
	kind = p_kind
	radius = p_radius
	tint = p_tint
	_t = 0.0
	_sheet_played = false
	_fire_ring_played = false
	if kind == "thunder" or kind == "":
		visible = false
		set_process(false)
		return
	# pixelfx 序列帧（2026-11-01 车道 F）：地裂/冰刺的主形态交给离线烘焙序列帧，
	# 位置用 global_position（ThunderBurst 的落点）。play() 受物理帧预算闸与资源存在性保护，
	# 返回 null（未导入/被限流/池未就绪）时不抛错，自绘形态按老画法全量兜底。
	if kind == "earth":
		# 地裂：贴地层（z_ground，低于角色），石头崩起不能盖住脚下的敌人与伤害跳字
		_sheet_played = FxFlipbookPool.play(&"earth_spike", global_position, {"z_ground": true}) != null
	elif kind == "frost":
		# 冰刺：默认 Z_OVERLAY 档（冰柱从地下戳出，要盖在角色身位之上才读得出「刺穿」）
		_sheet_played = FxFlipbookPool.play(&"ice_spikes", global_position) != null
	elif kind == "sonic":
		# 音波环（烟紫冷调，bottom 锚点对落点）：sheet 环径经 scale_mult 对齐判定直径，
		# 替换 _draw_sonic 的三重矢量音波环 + 6 向短刻度（下线）。默认 Z_OVERLAY 档。
		_sheet_played = FxFlipbookPool.play(&"sonic_ring", global_position,
			{"scale_mult": _sheet_scale_mult(&"sonic_ring")}) != null
	elif kind == "drum":
		# 鼓震波（春雷鼓）：金紫 thunderclap 正好贴，z_ground 贴地（低于角色，不盖脚）。
		# 替换 _draw_drum 的重环 + 8 放射震线 + 金心环（下线）。
		_sheet_played = FxFlipbookPool.play(&"thunderclap", global_position,
			{"z_ground": true, "scale_mult": _sheet_scale_mult(&"thunderclap")}) != null
	elif kind == "seal":
		# 坠印扬尘（巨印）：玄黄土调 ground_slam 顶替矢量重冲击环，z_ground 贴地；
		# 扬尘环 + 10 尘点仍由 _draw_seal_dust 自绘（见该函数）。
		_sheet_played = FxFlipbookPool.play(&"ground_slam", global_position,
			{"z_ground": true, "scale_mult": _sheet_scale_mult(&"ground_slam")}) != null
	visible = true
	set_process(true)

## 把「判定直径 = 2 * radius」换算成 sheet 的 scale_mult：目标世界直径 D → D / (frame_size.x * 基础scale)。
## 与 FxFlipbookPool._spawn 的缩放口径一致（最终 scale = 基础scale * scale_mult）。
## 说明：这几张 sheet 的可见环体约占画幅宽 88%，故实际环径略小于 D（约 0.88D）——
## 宁可略小于判定边界，也不越界糊大（铁律 7 的保守侧）。
func _sheet_scale_mult(id: StringName) -> float:
	var conf: Dictionary = FxSheetData.get_config(id)
	if conf.is_empty():
		return 1.0
	var fs: Vector2 = conf.get("frame_size", Vector2.ONE)
	var base: float = float(conf.get("scale", 1.0))
	return (radius * 2.0) / maxf(1.0, fs.x * base)

## 命中首拍材质微粒（由 ThunderBurst._deal_damage 在确认 hits>0 后调用一次）。
## 与 ThunderBurst 自己的雷光碎屑二选一：雷系走 lightning，其余形态走各自元素，
## 避免同一落点同帧两支 HIT_SPARK（2026-10-23）。
func emit_hit_spark() -> void:
	match kind:
		"fire_rain":
			FxParticlePool.burst(FxParticlePool.EMBER, global_position, "fire", 0.65)
		"frost":
			FxParticlePool.burst(FxParticlePool.HIT_SPARK, global_position, "water", 0.65)
		"earth":
			FxParticlePool.burst(FxParticlePool.HIT_SPARK, global_position, "earth", 0.7)
		"seal":
			FxParticlePool.burst(FxParticlePool.HIT_SPARK, global_position, "gold", 0.75)
		"drum", "sonic":
			FxParticlePool.burst(FxParticlePool.SOUL_ORB, global_position, "lightning", 0.6)

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
		_draw_phase = _redraw_interval()
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
		var land := Vector2(cos(ang), sin(ang) * GROUND_SQUASH) * radius * (0.2 + 0.55 * fposmod(float(i) * 0.37, 1.0))
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
			# 落点后余烬：带透视压扁贴地淡出
			# 2026-11-07 车道 B：首枚（i=0，5 枚里落点最近中心的那枚）落点当拍起一张 fire_ring 贴图，
			# 其余四枚仍走矢量火核/余烬 —— 只给首枚，逐枚播 sheet 会连环撞帧闸（见 FIRE_RING_SCALE_MULT）。
			# play() 判空静默放弃（被 16px 重叠/帧预算丢弃时该枚退回矢量余烬）。
			# 回退 = 删掉下面 if 块，本形态即回到纯矢量多枚小爆。
			if i == 0 and not _fire_ring_played:
				_fire_ring_played = true
				FxFlipbookPool.play(&"fire_ring", to_global(land),
					{"scale_mult": FIRE_RING_SCALE_MULT})
			var fade := 1.0 - clampf((_t - delay - fall_dur) / (DUR - fall_dur), 0.0, 1.0)
			if fade > 0.0:
				var c := Color(1.0, 0.55, 0.2, 0.5 * fade)
				draw_set_transform(land, 0.0, Vector2(1.0, GROUND_SQUASH))
				AdaptiveDraw.circle(self, Vector2.ZERO, 4.0 + 3.0 * (1.0 - fade), c, 3.2)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## 三层火核（照 ProceduralProjectileRenderer._draw_flame 的配色层次）
func _draw_flame_drop(pos: Vector2, s: float, a: float) -> void:
	var tail := PackedVector2Array([
		pos + Vector2(-s * 0.5, 0), pos + Vector2(0, -s * 2.2), pos + Vector2(s * 0.5, 0)])
	draw_colored_polygon(tail, Color(0.85, 0.25, 0.12, 0.5 * a))
	AdaptiveDraw.circle(self, pos, s, Color(0.85, 0.25, 0.12, 0.75 * a), 3.2)
	AdaptiveDraw.circle(self, pos, s * 0.62, Color(1.0, 0.65, 0.20, 0.9 * a), 3.2)
	AdaptiveDraw.circle(self, pos, s * 0.3, GameStyle.FX_HDR_FIRE, 3.2)

## 冰霜：冰刺从落点圈内拔地戳出（ stagger 生长），末端霜环淡去
## 序列帧接管时（_sheet_played）冰刺本体交给 ice_spikes，本函数退到 _draw_frost_footprint 兜底。
func _draw_frost() -> void:
	if _sheet_played:
		_draw_frost_footprint()
		return
	for i in FROST_SPIKES:
		var ring_r := radius * (0.35 if i < 3 else 0.72)
		var ang := float(i) * 2.399 + 0.4   # 黄金角散布
		var base := Vector2(cos(ang), sin(ang) * GROUND_SQUASH) * ring_r
		var grow: float = clampf((_t - float(i) * 0.03) / 0.12, 0.0, 1.0)
		if grow <= 0.0:
			continue
		var fade := 1.0 - clampf((_t - 0.24) / (DUR - 0.24), 0.0, 1.0)
		var h := (20.0 + 8.0 * fposmod(float(i) * 0.53, 1.0)) * grow
		var w := 5.5 * grow
		var a := 0.9 * fade
		# 冰刺是微倾的三角晶柱，向外倒伏
		var lean := Vector2(base.x, base.y / GROUND_SQUASH).normalized() * 6.0
		draw_colored_polygon(PackedVector2Array([
			base + Vector2(-w, 0), base + Vector2(w, 0), base + lean + Vector2(0, -h)]),
			Color(tint.r, tint.g, tint.b, 0.75 * a))
		draw_line(base + Vector2(0, -2), base + lean + Vector2(0, -h), GameStyle.FX_HDR_WATER, 1.6)
	# 霜环：演出末段贴着判定半径内缘淡去（贴地透视压扁）
	var ring_p: float = clampf(_t / 0.2, 0.0, 1.0)
	var ring_a := 0.4 * (1.0 - clampf((_t - 0.2) / (DUR - 0.2), 0.0, 1.0))
	if ring_a > 0.0:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, GROUND_SQUASH))
		draw_arc(Vector2.ZERO, radius * 0.9 * ring_p, 0.0, TAU, 40, Color(tint.r, tint.g, tint.b, ring_a), 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## 冰刺形态的贴地底盘（序列帧接管时的自绘层）：只留与判定半径同源的霜环 ——
## 半径 0.9R 外缘仍由玩家肉眼可读（画多大==判多大），冰刺本体不重复画（sheet 已有整排冰柱）。
func _draw_frost_footprint() -> void:
	var ring_p: float = clampf(_t / 0.18, 0.0, 1.0)
	var ring_a := 0.4 * SHEET_BASE_ALPHA * (1.0 - clampf((_t - 0.18) / (DUR - 0.18), 0.0, 1.0))
	if ring_a <= 0.0:
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, GROUND_SQUASH))
	draw_arc(Vector2.ZERO, radius * 0.9 * ring_p, 0.0, TAU, 40, Color(tint.r, tint.g, tint.b, ring_a), 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## 音波：三重细环递进扩散（音笛是声波不是雷，贴地环状推进）
## 2026-11-07 车道 B：主形态改由 sonic_ring 序列帧承担（见 activate_fx），
## 三重矢量环 + 环上 6 向短刻度一并下线。_sheet_played 时早退不画矢量层；
## 被帧闸丢弃时回退到下面原矢量实现。回退 = 删掉下一行早退即复活纯矢量音波。
func _draw_sonic() -> void:
	if _sheet_played:
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, GROUND_SQUASH))
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
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## 鼓震：一记重环砸开 + 8 条放射震线（春雷滚滚的闷击感，贴地压扁展开）
## 2026-11-07 车道 B：主形态改由 thunderclap 序列帧承担（见 activate_fx，z_ground 贴地），
## 矢量重环 + 8 放射震线 + 金心环一并下线。_sheet_played 时早退不画矢量层；
## 被帧闸丢弃时回退到下面原矢量实现。回退 = 删掉下一行早退即复活纯矢量鼓震。
func _draw_drum() -> void:
	if _sheet_played:
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, GROUND_SQUASH))
	var p: float = clampf(_t / 0.3, 0.0, 1.0)
	var a := 0.85 * (1.0 - p)
	if a > 0.0:
		draw_arc(Vector2.ZERO, radius * p, 0.0, TAU, 44, Color(tint.r, tint.g, tint.b, a), 5.0 - 3.0 * p)
		for k in 8:
			var ang := float(k) * TAU / 8.0 + 0.2
			var dir := Vector2(cos(ang), sin(ang))
			draw_line(dir * radius * 0.2 * p, dir * radius * 0.85 * p,
				Color(tint.r, tint.g, tint.b, a * 0.6), 1.8)
	# 鼓面回弹：中心小圆两拍脉冲（接 FX_HDR_GOLD 泛光起辉）
	var pulse := 1.0 + 0.35 * sin(_t * 28.0) * maxf(0.0, 1.0 - _t / 0.25)
	draw_arc(Vector2.ZERO, 10.0 * pulse, 0.0, TAU, 20, GameStyle.FX_HDR_GOLD, 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## 地裂：锯齿裂缝从爆心爬出去 + 碎石块崩起（裂山铎，贴地透视展开）
## 序列帧接管时（_sheet_played）石柱崩起交给 earth_spike，本函数退到 _draw_earth_footprint 兜底。
func _draw_earth() -> void:
	if _sheet_played:
		_draw_earth_footprint()
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, GROUND_SQUASH))
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
		# 裂缝沿线的亮土边（裂口翻起的新土，接 FX_HDR_EARTH）
		draw_polyline(pts, GameStyle.FX_HDR_EARTH, 0.9)
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
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## 地裂形态的贴地底盘（序列帧接管时的自绘层）：只留锯齿裂缝（0.55~0.9R，判定同源），
## 碎石块交给 earth_spike 的崩起石柱，不重复画；整层压到 SHEET_BASE_ALPHA 让 sheet 当主体。
func _draw_earth_footprint() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, GROUND_SQUASH))
	var p: float = clampf(_t / 0.16, 0.0, 1.0)
	var fade := (1.0 - clampf((_t - 0.22) / (DUR - 0.22), 0.0, 1.0)) * SHEET_BASE_ALPHA
	if fade <= 0.0:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var crack_col := Color(0.16, 0.11, 0.05, 0.8 * fade)
	var glow := GameStyle.FX_HDR_EARTH
	glow.a *= fade
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
		draw_polyline(pts, crack_col, 2.0)
		draw_polyline(pts, glow, 0.8)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## 坠印扬尘（巨印落点形态，2026-10-15 重构）：一记快速砸开的重冲击环压场 + 贴地扬尘环
## 2026-11-07 车道 B：重冲击环改由 ground_slam 序列帧承担（见 activate_fx，z_ground 贴地）；
## 扬尘环 + 10 尘点保留（坠印的「压」感靠尘，尘点同时是表现粒子/点绘，不删）。
## 被帧闸丢弃时回退到下面原矢量冲击环。回退 = 删掉 `if not _sheet_played:` 与其缩进即复活纯矢量重冲击环。
func _draw_seal_dust() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, GROUND_SQUASH))
	var fade := 1.0 - clampf((_t - 0.22) / (DUR - 0.22), 0.0, 1.0)
	# 重冲击环：0.16s 内从爆心砸到判定内缘，粗→细快速收细，给出「重物落地的第一拍」（接 FX_HDR_CORE 起辉）
	if not _sheet_played:
		var slam_p: float = clampf(_t / 0.16, 0.0, 1.0)
		if slam_p > 0.0 and slam_p < 1.0:
			var slam_r := radius * (0.15 + 0.75 * slam_p)
			draw_arc(Vector2.ZERO, slam_r, 0.0, TAU, 44,
				GameStyle.FX_HDR_CORE, 6.5 - 4.5 * slam_p)
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
			AdaptiveDraw.circle(self, dir * r, 2.0, dust, 3.2)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
