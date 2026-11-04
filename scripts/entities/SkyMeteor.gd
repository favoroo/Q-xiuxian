class_name SkyMeteor
extends Node2D

## 陨石坠落视觉实体（纯视觉，零碰撞零伤害）。
## 范围视觉与判定同源：落点阴影外圈半径严格等于 opts.radius（与 BossEnemy 判定半径同源）。
## 坠落体：从 target + (lateral, -fall_height) 加速坠落至 target。
## 落地当帧触发 pixelfx 特效，0.25s 尾焰散尽后自动回池。

const MAX_INSTANCES := 6
const LINGER_DURATION := 0.25

enum State {
	INACTIVE = 0,
	FALLING = 1,
	LANDED = 2,
}

# --- 实例字段 ---
var landed: bool = false
var radius: float = GameBalance.BOSS_METEOR_RADIUS
var fall_height: float = 420.0
var lateral: float = 0.0
var tint: Color = Color(1.0, 0.45, 0.15)
var fx_id: StringName = &"meteor_fall"

var _state: State = State.INACTIVE
var _timer: float = 0.0
var _fall_time: float = GameBalance.BOSS_METEOR_FALL
var _linger_timer: float = 0.0
var _start_offset: Vector2 = Vector2.ZERO
var _pooled: bool = false
var _activate_count: int = 0
var _opts_cache: Dictionary = {}

# --- 静态对象池 ---
static var _pool: Array[SkyMeteor] = []
static var _active: Array[SkyMeteor] = []

static func clear_pool() -> void:
	_pool.clear()
	_active.clear()

static func acquire(parent: Node) -> SkyMeteor:
	var m: SkyMeteor = null
	while not _pool.is_empty():
		var cand: SkyMeteor = _pool.pop_back()
		if is_instance_valid(cand):
			m = cand
			break
	if m != null:
		if m.get_parent() != parent:
			if m.get_parent() != null:
				m.get_parent().remove_child(m)
			parent.add_child(m)
		_active.append(m)
		return m

	var valid_active: Array[SkyMeteor] = []
	for a in _active:
		if is_instance_valid(a):
			valid_active.append(a)
	_active = valid_active

	if _active.size() < MAX_INSTANCES:
		m = SkyMeteor.new()
		m.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		parent.add_child(m)
		_active.append(m)
		return m

	# 满 6 个，复用最老（_active[0]）
	var oldest := _active[0]
	oldest.recycle()
	_pool.erase(oldest)
	if oldest.get_parent() != parent:
		if oldest.get_parent() != null:
			oldest.get_parent().remove_child(oldest)
		parent.add_child(oldest)
	_active.append(oldest)
	return oldest

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	visible = false
	set_process(false)

func activate(target: Vector2, fall_time: float, opts: Dictionary = {}) -> void:
	_pooled = false
	global_position = target
	rotation = 0.0
	visible = true
	landed = false
	_state = State.FALLING
	_timer = 0.0
	_linger_timer = 0.0
	_opts_cache = opts

	_fall_time = maxf(fall_time, 0.05)
	radius = float(opts.get("radius", GameBalance.BOSS_METEOR_RADIUS))
	fall_height = float(opts.get("fall_height", 420.0))
	tint = opts.get("tint", Color(1.0, 0.45, 0.15))
	fx_id = opts.get("fx_id", &"meteor_fall")

	_activate_count += 1
	if opts.has("lateral"):
		lateral = float(opts["lateral"])
	else:
		# 表现层随机：本地 RNG，使用 instance_id 与激活计数播种，绝不碰 GameManager.rng
		var rng := RandomNumberGenerator.new()
		rng.seed = int((get_instance_id() + _activate_count * 1337) % 2147483647)
		lateral = rng.randf_range(-120.0, 120.0)

	_start_offset = Vector2(lateral, -fall_height)

	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	reset_physics_interpolation()
	set_process(true)
	queue_redraw()

func recycle() -> void:
	if _pooled:
		return
	_pooled = true
	visible = false
	set_process(false)
	landed = false
	_state = State.INACTIVE
	_timer = 0.0
	_linger_timer = 0.0
	_opts_cache.clear()
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	reset_physics_interpolation()
	queue_redraw()

	_active.erase(self)
	if not _pool.has(self) and _pool.size() < MAX_INSTANCES:
		_pool.append(self)

func _process(delta: float) -> void:
	if GameManager.is_game_over:
		recycle()
		return

	if _state == State.INACTIVE:
		set_process(false)
		return

	if _state == State.FALLING:
		_timer += delta
		queue_redraw()
		if _timer >= _fall_time:
			# 落地当帧
			landed = true
			_state = State.LANDED
			_linger_timer = LINGER_DURATION
			var scale_mult: float = float(_opts_cache.get("scale_mult", maxf(0.8, radius / 120.0)))
			FxFlipbookPool.play(fx_id, global_position, {
				"scale_mult": scale_mult,
				"z_ground": true,
			})
	elif _state == State.LANDED:
		_linger_timer -= delta
		queue_redraw()
		if _linger_timer <= 0.0:
			recycle()

func _draw() -> void:
	if _state == State.INACTIVE or not visible:
		return

	var t: float = 1.0
	if _state == State.FALLING:
		t = clampf(_timer / _fall_time, 0.0, 1.0)

	# 1. 地面落点阴影（始终在 target == local Vector2.ZERO 画半径 = radius 的圆）
	# 细边界弧（alpha 0.5，这是判定边界，线宽 2px）
	var ring_col := Color(tint.r, tint.g, tint.b, 0.5)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 36, ring_col, 2.0, true)

	# 随坠落进度收紧的内填充（alpha 0.10→0.25）
	var fill_alpha := lerpf(0.10, 0.25, t)
	if _state == State.LANDED:
		fill_alpha *= maxf(0.0, _linger_timer / LINGER_DURATION)
	var fill_col := Color(tint.r, tint.g, tint.b, fill_alpha)
	var inner_r := radius * lerpf(1.0, 0.15, t)
	draw_circle(Vector2.ZERO, inner_r, fill_col)

	# 2. 坠落体（仅在 FALLING 阶段绘制；从 target + (lateral, -fall_height) 到 target）
	if _state == State.FALLING:
		var k := t * t # 加速下坠 (t*t)
		var body_pos := _start_offset * (1.0 - k)

		# 尾焰沿速度反向延伸（即指向 _start_offset 方向）
		var tail_dir := _start_offset.normalized()

		# 3 段火尾
		# 段 1（内焰，亮白金橙）
		var p1 := body_pos + tail_dir * 14.0
		draw_line(body_pos, p1, Color(1.0, 0.90, 0.50, 0.85), 9.0)
		draw_circle(p1, 4.5, Color(1.0, 0.90, 0.50, 0.85))

		# 段 2（中焰，炽烈橙红）
		var p2 := body_pos + tail_dir * 30.0
		draw_line(p1, p2, Color(1.0, 0.45, 0.15, 0.65), 6.5)
		draw_circle(p2, 3.25, Color(1.0, 0.45, 0.15, 0.65))

		# 段 3（外焰，焦黑暗红）
		var p3 := body_pos + tail_dir * 50.0
		draw_line(p2, p3, Color(0.85, 0.20, 0.10, 0.40), 4.0)
		draw_circle(p3, 2.0, Color(0.85, 0.20, 0.10, 0.40))

		# 12px 岩核（直径 12px，半径 6px）+ 外圈暖色描边 + 自转
		var rock_col := Color(0.22, 0.18, 0.20)
		draw_circle(body_pos, 6.0, rock_col)
		var rim_col := Color(1.0, 0.65, 0.25, 0.95)
		draw_arc(body_pos, 6.0, 0.0, TAU, 16, rim_col, 2.0, true)

		# 自转纹理细线
		var rot_ang := t * TAU * 1.5
		var r_dir := Vector2(cos(rot_ang), sin(rot_ang)) * 4.5
		draw_line(body_pos - r_dir, body_pos + r_dir, Color(0.40, 0.32, 0.30), 1.5)
