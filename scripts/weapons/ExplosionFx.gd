class_name ExplosionFx
extends Node2D

## 击杀爆炸演出（2026-10-25 血祭盛宴重做配套）：过曝核心闪 → 主冲击环扫满判定半径 →
## 血肉碎屑抛射 + 低位烟环。仿 ChestBurstFx/BurstKindFx 范式：纯 _draw 时间轴一次性节点，
## 无贴图 / 无粒子节点 / 无光源；存活 ≤0.45s 后 queue_free，不进任何组、不占 FxBudget 名额。
##
## 铁律 7 同源：主冲击环的最大半径就是爆炸判定半径本身 —— 画多大 == 判多大。
## 随机只用本地 RNG（instance_id 播种），禁碰 GameManager.rng（铁律 3/15）。
##
## pixelfx 序列帧接入（2026-11-07 车道 B）：主冲击环 + 内亮环改由 kill_blast（等离子灵爆，
## center 锚点对爆心）承担，scale_mult 按判定直径 2R 换算。过曝核心 / 烟环 / 血肉碎块保留
## （碎块是死亡细胞式手感主体）。击杀连爆时同物理帧多枚爆炸会被帧闸（预算 + 16px 重叠丢弃）
## 掐掉 sheet，故矢量主环不删：sheet 起播时压到 SHEET_RING_FALLBACK_ALPHA 当「判定边缘」底层，
## 被丢弃时按原 alpha 全量兜底（自动退回老画法，零回归）。

const DUR := 0.45            ## 演出总时长
const HZ := 40.0             ## 重绘节流（与 JuiceEffect 高帧档同口径）
const GRAVITY := 540.0       ## 碎屑下坠加速度
const GROUND_SQUASH := 0.62  ## 俯视压扁（全场地面特效同款）

const CORE_FLASH_T := 0.22   ## 核心过曝阶段占全程比例（0~0.22 是「炸开」，之后是「扩散」）
## kill_blast 起播时矢量主环压到的 alpha 系数（sheet 被帧闸丢弃时为 1.0 = 老画法全量兜底）。
## 保留这层是为了让玩家仍能从**真实判定半径**读出打击范围（sheet 环体约占画幅宽 88%，略小于 D）。
const SHEET_RING_FALLBACK_ALPHA := 0.4

## 血祭配色：绯红血肉 + 鎏金边（HDR 超白起辉），与落雷的亮蓝白拉开色相
const COL_CORE := Color(2.6, 1.8, 0.4)     ## 过曝绯金芯（= FX_HDR_CRIT 同系）
const COL_BLOOD := Color(1.5, 0.22, 0.16)  ## 血肉碎屑深红
const COL_SMOKE := Color(0.45, 0.30, 0.24) ## 低位烟尘

var _t: float = 0.0
var _redraw_timer: float = 0.0
var _radius: float = 90.0
var _shards: Array[Dictionary] = []
## 本次演出是否成功起了 kill_blast 序列帧：false 时矢量主环全量兜底（见 _play_sheet / _draw）。
var _sheet_played: bool = false

## 宿主在击杀当刻调用：radius 必须传爆炸判定半径（画判同源）。
static func play(host: Node, pos: Vector2, radius: float) -> void:
	if host == null or not is_instance_valid(host):
		return
	var fx := ExplosionFx.new()
	fx._radius = maxf(24.0, radius)
	host.add_child(fx)
	fx.global_position = pos
	# 位置落定后才起 sheet：add_child 当拍若宿主已在树内会立刻跑 _ready，那时 global_position
	# 还没写（老 _ready 只用角度/速度，不依赖位置），故 sheet 必须放到这里手动触发。
	fx._play_sheet()

## 起 kill_blast 序列帧（center 锚点对爆心，scale_mult 把画幅宽对齐判定直径 2R）。
## 判空：被帧闸掐掉（同物理帧预算用尽 / 与既有播放点 <16px 重叠）时 _sheet_played=false，
## _draw 里矢量主环按原 alpha 全量兜底 —— 击杀连爆时掉帧即自动退回老画法，不出现「炸了没画面」。
func _play_sheet() -> void:
	var conf: Dictionary = FxSheetData.get_config(&"kill_blast")
	if conf.is_empty():
		return
	var fs: Vector2 = conf.get("frame_size", Vector2.ONE)
	var base: float = float(conf.get("scale", 1.0))
	var scale_mult: float = (_radius * 2.0) / maxf(1.0, fs.x * base)
	_sheet_played = FxFlipbookPool.play(&"kill_blast", global_position, {
		"scale_mult": scale_mult,
	}) != null

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(get_instance_id() % 2147483647)
	# 7 片血肉碎屑：全向偏上抛，解析轨迹（免积分漂移），前 60% 满显尾段淡出
	for i in range(7):
		var ang := -PI * 0.5 + rng.randf_range(-1.6, 1.6)
		var speed := rng.randf_range(120.0, 260.0) * (_radius / 170.0)
		var w := rng.randf_range(4.0, 9.0)
		_shards.append({
			"pos": Vector2(rng.randf_range(-8.0, 8.0), rng.randf_range(-8.0, 4.0)),
			"vel": Vector2.from_angle(ang) * speed,
			"rot": rng.randf_range(0.0, TAU),
			"spin": rng.randf_range(-10.0, 10.0),
			"pts": PackedVector2Array([
				Vector2(-w * 0.5, -w * 0.3), Vector2(w * 0.5, -w * 0.3),
				Vector2(w * 0.5, w * 0.3), Vector2(-w * 0.5, w * 0.3),
			]),
			"color": COL_BLOOD if i % 3 != 0 else COL_CORE,
		})
	queue_redraw()

func _process(delta: float) -> void:
	_t += delta
	_redraw_timer -= delta
	if _redraw_timer <= 0.0:
		_redraw_timer = 1.0 / HZ
		queue_redraw()
	if _t >= DUR:
		queue_free()

func _draw() -> void:
	var k: float = clampf(_t / DUR, 0.0, 1.0)
	# 1. 过曝核心：前 22% 急膨到 0.4R 并急速衰减 —— 「炸点」的闪白读数
	if k < CORE_FLASH_T:
		var ck: float = k / CORE_FLASH_T
		var cr: float = lerpf(6.0, _radius * 0.40, 1.0 - (1.0 - ck) * (1.0 - ck))
		draw_circle(Vector2.ZERO, cr, Color(COL_CORE, 0.95 * (1.0 - ck)))
		draw_circle(Vector2.ZERO, cr * 0.45, Color(2.8, 2.6, 2.2, 0.9 * (1.0 - ck)))
	# 2. 主冲击环：扫满判定半径（同源铁律），线宽随进度收细；贴地压扁消立面感
	# 2026-11-07 车道 B：主冲击环改由 kill_blast 序列帧承担（见 _play_sheet）。矢量主环不删，
	# 退成「与判定半径同源」的底层 —— sheet 起播时压到 SHEET_RING_FALLBACK_ALPHA（sheet 环体只到
	# ~0.88R，这层给出真实判定边缘，铁律 7），sheet 被帧闸丢弃时按原 alpha 全量兜底。
	var rk: float = 1.0 - pow(1.0 - k, 2.0)
	var rr: float = lerpf(_radius * 0.12, _radius, rk)
	var ring_a: float = 0.9 * (1.0 - k) * (SHEET_RING_FALLBACK_ALPHA if _sheet_played else 1.0)
	if ring_a > 0.01:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, GROUND_SQUASH))
		draw_arc(Vector2.ZERO, rr, 0.0, TAU, clampi(int(rr * 1.2), 12, 40),
			Color(COL_CORE, ring_a), maxf(1.5, 6.0 * (1.0 - k * 0.6)), true)
		# 内亮环：sheet 起播时由 kill_blast 的过曝核心承担，下线；被帧闸丢弃时（not _sheet_played）
		# 仍画（回退 = 删掉下面 if 条件，恢复整段老画法）。
		if not _sheet_played:
			draw_arc(Vector2.ZERO, rr * 0.9, 0.0, TAU, clampi(int(rr), 10, 36),
				Color(2.4, 2.0, 0.8, ring_a * 0.7), 2.0, true)
		# 3. 低位烟尘环：慢半拍、矮一截，垫出「炸在地面」的厚度
		var sr: float = lerpf(_radius * 0.2, _radius * 0.75, rk)
		draw_arc(Vector2.ZERO, sr, 0.0, TAU, clampi(int(sr), 10, 32),
			Color(COL_SMOKE, 0.5 * (1.0 - k)), 5.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 4. 血肉碎屑
	for s: Dictionary in _shards:
		var a: float = 1.0 - smoothstep(0.6, 1.0, k)
		if a <= 0.01:
			continue
		var pos: Vector2 = s.pos + s.vel * _t + Vector2(0.0, 0.5 * GRAVITY * _t * _t)
		draw_set_transform(pos, s.rot + s.spin * _t, Vector2.ONE)
		var col: Color = s.color
		col.a *= a
		draw_colored_polygon(s.pts, col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
