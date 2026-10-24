class_name ChestBurstFx
extends Node2D

## 破匣爆开演出：碎板飞溅 + 落地尘环 + 锁牌弹出，纯 _draw 时间轴一次性节点。
## 仿 ObeliskFx 范式：无贴图 / 无粒子节点 / 无光源；存活 ≤0.5s 后 queue_free，
## 不进任何组、不占 FxBudget 灯与发射器名额。
## 配色由宿主按档位从 ChestVisual.PALETTES 整包灌入，本节点不另起配色；
## 随机只用本地 RNG（instance_id 播种）—— 演出随机不许碰 GameManager.rng，
## 否则挪动后续玩法随机序列，测试钉不住（AGENTS.md 铁律 3）。

const DUR := 0.5             ## 演出总时长
const HZ := 40.0             ## 演出期间重绘节流（短命节点，40Hz 足够顺滑）
const GRAVITY := 620.0       ## 碎板下坠加速度（画布 px/s²）
const GROUND_SQUASH := 0.62  ## 地面尘环 2.5D 俯视压扁系数（与全场地面特效同款观感）
const GROUND_Y := 39.0       ## 尘环圆心高度 = 匣底落影处（ChestVisual 画布坐标）

## 分档强度：碎板片数 / 尘环最大半径 / 初速倍率（木<铜<玉；
## 玉匣另有的 shockwave + zoom_punch + 顿帧在宿主侧，不在这里叠）
const TIER_SHARDS: Array[int] = [5, 6, 7]
const TIER_RING: Array[float] = [30.0, 40.0, 52.0]
const TIER_SPEED: Array[float] = [1.0, 1.1, 1.25]

var _t: float = 0.0
var _redraw_timer: float = 0.0
var _tier: int = 0
var _palette: Dictionary = {}
var _shards: Array[Dictionary] = []
var _lock: Dictionary = {}

## 宿主在破匣当刻调用：挂到池层（与匣子同层），位置即匣心，canvas_scale 传
## 匣子造型的当前缩放（BASE_SCALE × SIZE_MULT × 档位倍率），碎板与匣子同口径。
static func play(host: Node, pos: Vector2, tier: int, canvas_scale: Vector2) -> void:
	if host == null or not is_instance_valid(host):
		return
	var fx := ChestBurstFx.new()
	fx._tier = clampi(tier, 0, ChestVisual.PALETTES.size() - 1)
	fx._palette = ChestVisual.PALETTES[fx._tier]
	fx.scale = canvas_scale
	host.add_child(fx)
	fx.global_position = pos

func _ready() -> void:
	# 本地 RNG：种子取自 instance_id，每口匣子的碎板轨迹各不相同且不碰玩法随机
	var rng := RandomNumberGenerator.new()
	rng.seed = int(get_instance_id() % 2147483647)
	var count: int = TIER_SHARDS[_tier]
	var spd: float = TIER_SPEED[_tier]
	# 碎板配色在身板/盖板/箍带之间轮换，一眼认出是「这口匣子」炸开的
	var shard_colors: Array = [_palette.body, _palette.lid, _palette.body, _palette.strap]
	for i in range(count):
		var ang := -PI * 0.5 + rng.randf_range(-1.15, 1.15)  # 上抛为主，向两侧铺开
		var speed := rng.randf_range(95.0, 175.0) * spd
		var w := rng.randf_range(9.0, 19.0)
		var h := rng.randf_range(4.0, 7.0)
		_shards.append({
			"pos": Vector2(rng.randf_range(-14.0, 14.0), rng.randf_range(-16.0, 10.0)),
			"vel": Vector2.from_angle(ang) * speed,
			"rot": rng.randf_range(0.0, TAU),
			"spin": rng.randf_range(-9.0, 9.0),
			"pts": PackedVector2Array([
				Vector2(-w * 0.5, -h * 0.5), Vector2(w * 0.5, -h * 0.5),
				Vector2(w * 0.5, h * 0.5), Vector2(-w * 0.5, h * 0.5),
			]),
			"color": shard_colors[i % shard_colors.size()],
		})
	# 锁牌单独弹出：跳得最高、转得最慢，「锁被砸飞」的读点
	_lock = {
		"pos": Vector2(0, -6),
		"vel": Vector2(rng.randf_range(-28.0, 28.0), -235.0 * spd),
		"rot": 0.0,
		"spin": rng.randf_range(-5.0, 5.0),
		"pts": PackedVector2Array([
			Vector2(-7, -5), Vector2(7, -5), Vector2(7, 5),
			Vector2(4, 8), Vector2(-4, 8), Vector2(-7, 5),
		]),
		"color": _palette.lock,
	}
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
	# 落地尘环：椭圆扩环外扩淡出，垫在碎板下面；铜/玉用品阶地光色，木匣用尘土色
	var ring_col: Color = _palette.glow if _palette.glow.a > 0.0 else Color(0.55, 0.45, 0.35)
	var rr: float = lerpf(7.0, TIER_RING[_tier], _ease_out_cubic(k))
	var ring_a: float = 0.55 * (1.0 - k)
	if ring_a > 0.01:
		var ring := _ellipse(Vector2(0, GROUND_Y), rr, rr * GROUND_SQUASH)
		ring.append(ring[0])
		draw_polyline(ring, Color(ring_col, ring_a), 3.0)
	# 碎板与锁牌：解析轨迹 p = p0 + v·t + ½g·t²，免积分漂移
	for s: Dictionary in _shards:
		_draw_piece(s)
	_draw_piece(_lock)

func _draw_piece(s: Dictionary) -> void:
	var k: float = clampf(_t / DUR, 0.0, 1.0)
	var a: float = 1.0 - smoothstep(0.55, 1.0, k)  # 前 55% 满显，尾段淡出
	if a <= 0.01:
		return
	var pos: Vector2 = s.pos + s.vel * _t + Vector2(0.0, 0.5 * GRAVITY * _t * _t)
	draw_set_transform(pos, s.rot + s.spin * _t, Vector2.ONE)
	var col: Color = s.color
	col.a *= a
	draw_colored_polygon(s.pts, col)
	var loop := PackedVector2Array(s.pts)
	loop.append(s.pts[0])
	draw_polyline(loop, Color(ChestVisual.OUTLINE, a), 1.2)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

static func _ease_out_cubic(k: float) -> float:
	return 1.0 - pow(1.0 - k, 3.0)

## 压扁椭圆近似（尘环用），20 边形足够平
func _ellipse(center: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(20):
		var a := TAU * float(i) / 20.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts
