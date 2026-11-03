class_name BlinkRift
extends Node2D

## 瞬移落点符环（2026-11-03 瞬移可读性专项）。
##
## 旧链路是 `global_position = 目标点` 一帧硬切：旧位残影只能表达「它刚才在这」，
## 不能预告「它要去哪」。本组件在起手帧把落点亮在地面，符环从外向内收拢、填满即落地，
## 给玩家一段可读、可走出的反应窗。
##
## 纪律：
##   - 只画落点，不参与伤害判定、不参与索敌；半径是纯表现读数，不是命中半径。
##   - 池化消灭节点 churn：影魅/剑煞同屏可能同时闪现，逐次 new + queue_free 是 GC 尖峰源。
##   - 落点由持有者锁定（起手帧算一次），本组件不追玩家 —— 画哪落哪，躲得掉才算读招。
##   - 取色仍由调用方给（Boss 主题色 / GameStyle.BAD），不在本组件里散落硬编码。

const POOL_CAP := 16                 ## 同屏符环池上限（Boss 同时至多 1 个，小怪闪现留余量）
const REDRAW_INTERVAL := 0.033       ## 30Hz 重绘：前摇 0.3~0.42s，30Hz 足够读出收拢过程
const LIFETIME_PAD := 0.06           ## 到期后多留一瞬，与落地冲击环重叠，避免「圈先没、人后到」

const RADIUS_NORMAL := 28.0          ## 普通小怪档（影魅）
const RADIUS_ELITE := 36.0           ## 精英档（剑煞变异）
const RADIUS_BOSS := 48.0            ## 魔君档

var radius: float = RADIUS_NORMAL
var progress: float = 0.0            ## 0→1，由本组件按 _time_left 自驱；1 = 落地时刻
var color: Color = GameStyle.BAD

var _time_left: float = 0.0
var _duration: float = 0.3
var _clock: float = 0.0
var _redraw_timer: float = 0.0
var _pooled: bool = false

static var _pool: Array[BlinkRift] = []
static var active_count: int = 0
static var created_count: int = 0
static var reused_count: int = 0

## 取一只符环：出池复位 → 落点/时长/档位就位 → 入树。
## 字段必须在 add_child 前写好（_ready 只跑一次，复用不会重跑）。
static func acquire(parent: Node, pos: Vector2, duration: float, col: Color,
		rad: float = RADIUS_NORMAL) -> BlinkRift:
	if parent == null:
		return null
	var r: BlinkRift = null
	while not _pool.is_empty():
		var cand: BlinkRift = _pool.pop_back()
		if is_instance_valid(cand):
			r = cand
			reused_count += 1
			break
	if r == null:
		r = BlinkRift.new()
		created_count += 1
	r._reset(pos, duration, col, rad)
	parent.add_child(r)
	return r

func _reset(pos: Vector2, duration: float, col: Color, rad: float) -> void:
	_pooled = false
	_duration = maxf(duration, 0.001)
	_time_left = _duration + LIFETIME_PAD
	radius = maxf(rad, 1.0)
	color = col
	progress = 0.0
	_clock = 0.0
	_redraw_timer = 0.0
	global_position = pos
	visible = true
	set_process(true)
	queue_redraw()

## 外部取消（宿主伏诛/回合末消散/定身打断）：立即回池，不留无主符环。
func cancel() -> void:
	_release()

func _release() -> void:
	if _pooled:
		return
	_pooled = true
	set_process(false)
	visible = false
	if get_parent() != null:
		get_parent().remove_child(self)
	if _pool.size() < POOL_CAP:
		_pool.append(self)
	else:
		queue_free()

static func clear_pool() -> void:
	for r in _pool:
		if is_instance_valid(r):
			r.free()
	_pool.clear()
	created_count = 0
	reused_count = 0

func _enter_tree() -> void:
	active_count += 1

func _exit_tree() -> void:
	active_count -= 1

func _process(delta: float) -> void:
	if GameManager.is_game_over:
		_release()
		return
	_clock += delta
	_time_left -= delta
	progress = clampf(1.0 - maxf(_time_left, 0.0) / _duration, 0.0, 1.0)
	_redraw_timer -= delta
	if _redraw_timer <= 0.0:
		_redraw_timer = REDRAW_INTERVAL
		queue_redraw()
	if _time_left <= 0.0:
		_release()

func _draw() -> void:
	BatchDraw.flush(self)
	var t := clampf(progress, 0.0, 1.0)
	var c := color
	var pulse := 0.86 + 0.14 * sin(_clock * 17.0)
	# 地面暗底：把落点从地形上「压」出来
	BatchDraw.native_circle(self, Vector2.ZERO, radius * 0.78, Color(0.05, 0.03, 0.06, 0.42))
	# 外环：从外向内收拢，填满 = 落地。外沿给一圈描边保证贴地可读
	var ring_r := lerpf(radius * 1.58, radius, ease(t, 0.38))
	var ring_a := (0.28 + 0.58 * t) * pulse
	BatchDraw.native_arc(self, Vector2.ZERO, ring_r, 0.0, TAU, 36,
		Color(c.r, c.g, c.b, ring_a), 1.8 + 1.8 * t, true)
	# 内环反向自转：读「空间在收束」，与外环单向收缩区分开
	var inner_r := lerpf(radius * 0.92, radius * 0.34, t)
	BatchDraw.native_arc(self, Vector2.ZERO, inner_r, 0.0, TAU, 24,
		Color(c.r, c.g, c.b, ring_a * 0.55), 1.2, true)
	# 四向刻度（俯视压扁）：让符环带「阵纹」身份，不与圆形伤害圈混读
	var ticks := 4
	for i in range(ticks):
		var ang := _clock * 1.6 + float(i) * TAU / float(ticks)
		var dir := Vector2(cos(ang), sin(ang) * 0.62)
		BatchDraw.native_line(self, dir * ring_r * 0.58, dir * ring_r * 1.06,
			Color(c.r, c.g, c.b, ring_a * 0.8), 1.6 + 1.2 * t)
	# 内核：随进度胀大，末段提亮
	BatchDraw.native_circle(self, Vector2.ZERO, lerpf(2.0, radius * 0.3, t),
		Color(c.r, c.g, c.b, 0.26 + 0.5 * t))
	# 末段中心亮缝：最后一刻的「要落了」读数
	if t > 0.68:
		var k: float = (t - 0.68) / 0.32
		BatchDraw.native_line(self, Vector2(0.0, -radius * 0.72 * k),
			Vector2(0.0, radius * 0.72 * k), Color(1.0, 1.0, 1.0, 0.7 * k), 2.0)
	BatchDraw.flush(self)