class_name ExplosionFx
extends Node2D

## 击杀爆炸演出（2026-10-25 血祭盛宴重做配套）：过曝核心闪 → 主冲击环扫满判定半径 →
## 血肉碎屑抛射 + 低位烟环。仿 ChestBurstFx/BurstKindFx 范式：纯 _draw 时间轴一次性节点，
## 无贴图 / 无粒子节点 / 无光源；存活 ≤0.45s 后 queue_free，不进任何组、不占 FxBudget 名额。
##
## 铁律 7 同源：主冲击环的最大半径就是爆炸判定半径本身 —— 画多大 == 判多大。
## 随机只用本地 RNG（instance_id 播种），禁碰 GameManager.rng（铁律 3/15）。

const DUR := 0.45            ## 演出总时长
const HZ := 40.0             ## 重绘节流（与 JuiceEffect 高帧档同口径）
const GRAVITY := 540.0       ## 碎屑下坠加速度
const GROUND_SQUASH := 0.62  ## 俯视压扁（全场地面特效同款）

const CORE_FLASH_T := 0.22   ## 核心过曝阶段占全程比例（0~0.22 是「炸开」，之后是「扩散」）

## 血祭配色：绯红血肉 + 鎏金边（HDR 超白起辉），与落雷的亮蓝白拉开色相
const COL_CORE := Color(2.6, 1.8, 0.4)     ## 过曝绯金芯（= FX_HDR_CRIT 同系）
const COL_BLOOD := Color(1.5, 0.22, 0.16)  ## 血肉碎屑深红
const COL_SMOKE := Color(0.45, 0.30, 0.24) ## 低位烟尘

var _t: float = 0.0
var _redraw_timer: float = 0.0
var _radius: float = 90.0
var _shards: Array[Dictionary] = []

## 宿主在击杀当刻调用：radius 必须传爆炸判定半径（画判同源）。
static func play(host: Node, pos: Vector2, radius: float) -> void:
	if host == null or not is_instance_valid(host):
		return
	var fx := ExplosionFx.new()
	fx._radius = maxf(24.0, radius)
	host.add_child(fx)
	fx.global_position = pos

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
	var rk: float = 1.0 - pow(1.0 - k, 2.0)
	var rr: float = lerpf(_radius * 0.12, _radius, rk)
	var ring_a: float = 0.9 * (1.0 - k)
	if ring_a > 0.01:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, GROUND_SQUASH))
		draw_arc(Vector2.ZERO, rr, 0.0, TAU, clampi(int(rr * 1.2), 12, 40),
			Color(COL_CORE, ring_a), maxf(1.5, 6.0 * (1.0 - k * 0.6)), true)
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
