class_name BossBeam
extends Area2D

## Boss 激光束攻击实体（纯代码构建，无需场景文件）。
## 范围视觉与判定同源：伤害走廊矩形与视觉束宽束长严格 1:1 对齐。
## 结构：Area2D + CollisionShape2D(RectangleShape2D)，沿局部 +X 延伸。
## 三段状态机：CHARGE(charge_time) → FIRE(fire_time) → FADE(0.12s) → recycle。

const MAX_INSTANCES := 8
const FADE_TIME := 0.12
const TICK_INTERVAL := 0.12

enum State {
	INACTIVE = 0,
	CHARGE = 1,
	FIRE = 2,
	FADE = 3,
}

# --- 实例字段 ---
var length: float = GameBalance.BOSS_LASER_LENGTH
var width: float = GameBalance.BOSS_LASER_WIDTH
var charge_time: float = GameBalance.BOSS_LASER_CHARGE
var fire_time: float = GameBalance.BOSS_LASER_FIRE
var sweep_speed: float = 0.0
var damage: float = 10.0
var tint: Color = GameStyle.BAD
var follow: Node2D = null
var firing: bool = false

var _state: State = State.INACTIVE
var _timer: float = 0.0
var _tick_timer: float = 0.0
var _fade_alpha: float = 1.0
var _pooled: bool = false

var _shape_node: CollisionShape2D = null
var _rect_shape: RectangleShape2D = null

# --- 静态对象池 ---
static var _pool: Array[BossBeam] = []
static var _active: Array[BossBeam] = []

static func clear_pool() -> void:
	_pool.clear()
	_active.clear()

static func acquire(parent: Node) -> BossBeam:
	var b: BossBeam = null
	while not _pool.is_empty():
		var cand: BossBeam = _pool.pop_back()
		if is_instance_valid(cand):
			b = cand
			break
	if b != null:
		if b.get_parent() != parent:
			if b.get_parent() != null:
				b.get_parent().remove_child(b)
			parent.add_child(b)
		_active.append(b)
		return b

	# 清洗 _active 中已释放的节点
	var valid_active: Array[BossBeam] = []
	for a in _active:
		if is_instance_valid(a):
			valid_active.append(a)
	_active = valid_active

	# 未达上限则新建
	if _active.size() < MAX_INSTANCES:
		b = BossBeam.new()
		b.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		parent.add_child(b)
		_active.append(b)
		return b

	# 满 8 个，复用最老（_active[0]）
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
	collision_layer = 0
	collision_mask = 2 # 仅检测玩家层（Layer 2）
	monitoring = false
	monitorable = false
	visible = false
	set_process(false)
	set_physics_process(false)
	_ensure_collision()

func _ensure_collision() -> void:
	if _shape_node == null:
		_shape_node = CollisionShape2D.new()
		_rect_shape = RectangleShape2D.new()
		_shape_node.shape = _rect_shape
		add_child(_shape_node)
	_shape_node.set_deferred("disabled", true)

func activate(origin_pos: Vector2, dir: Vector2, opts: Dictionary = {}) -> void:
	_pooled = false
	global_position = origin_pos
	if dir.length_squared() > 0.0001:
		rotation = dir.angle()
	else:
		rotation = 0.0

	length = float(opts.get("length", GameBalance.BOSS_LASER_LENGTH))
	width = float(opts.get("width", GameBalance.BOSS_LASER_WIDTH))
	charge_time = float(opts.get("charge_time", GameBalance.BOSS_LASER_CHARGE))
	fire_time = float(opts.get("fire_time", GameBalance.BOSS_LASER_FIRE))
	sweep_speed = float(opts.get("sweep_speed", 0.0))
	damage = float(opts.get("damage", 10.0))
	tint = opts.get("tint", GameStyle.BAD)
	follow = opts.get("follow", null)

	_ensure_collision()
	_rect_shape.size = Vector2(length, width)
	_shape_node.position = Vector2(length * 0.5, 0.0)

	firing = false
	_state = State.CHARGE
	_timer = 0.0
	_tick_timer = 0.0
	_fade_alpha = 1.0

	reset_physics_interpolation()
	set_deferred("monitoring", false)
	_shape_node.set_deferred("disabled", true)

	visible = true
	set_process(true)
	set_physics_process(true)
	queue_redraw()

func recycle() -> void:
	if _pooled:
		return
	_pooled = true
	firing = false
	visible = false
	set_process(false)
	set_physics_process(false)
	set_deferred("monitoring", false)
	if _shape_node != null:
		_shape_node.set_deferred("disabled", true)
		_shape_node.position = Vector2.ZERO
	if _rect_shape != null:
		_rect_shape.size = Vector2.ZERO
	rotation = 0.0
	follow = null
	_state = State.INACTIVE
	_timer = 0.0
	_tick_timer = 0.0
	_fade_alpha = 1.0
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	reset_physics_interpolation()
	queue_redraw()

	_active.erase(self)
	if not _pool.has(self) and _pool.size() < MAX_INSTANCES:
		_pool.append(self)

func _physics_process(delta: float) -> void:
	if GameManager.is_game_over:
		recycle()
		return

	if _state == State.INACTIVE:
		set_physics_process(false)
		return

	if follow != null:
		if is_instance_valid(follow):
			global_position = follow.global_position
		else:
			follow = null

	_timer += delta

	match _state:
		State.CHARGE:
			if _timer >= charge_time:
				_state = State.FIRE
				firing = true
				_timer = 0.0
				_tick_timer = 0.0
				set_deferred("monitoring", true)
				if _shape_node != null:
					_shape_node.set_deferred("disabled", false)
		State.FIRE:
			if sweep_speed != 0.0:
				rotation += sweep_speed * delta
			_tick_timer -= delta
			if _tick_timer <= 0.0:
				if monitoring:
					_tick_timer = TICK_INTERVAL
					_check_damage()
				else:
					_tick_timer = 0.0
			if _timer >= fire_time:
				_state = State.FADE
				firing = false
				_timer = 0.0
				set_deferred("monitoring", false)
				if _shape_node != null:
					_shape_node.set_deferred("disabled", true)
		State.FADE:
			_fade_alpha = maxf(0.0, 1.0 - (_timer / FADE_TIME))
			if _timer >= FADE_TIME:
				recycle()

func _process(_delta: float) -> void:
	if GameManager.is_game_over:
		recycle()
		return

	if _state == State.INACTIVE:
		set_process(false)
		return

	if follow != null and is_instance_valid(follow):
		global_position = follow.global_position

	queue_redraw()

func _check_damage() -> void:
	if not monitoring:
		return
	for body in get_overlapping_bodies():
		if body != null and is_instance_valid(body) and body.has_method("take_damage"):
			body.take_damage(damage)

func _draw() -> void:
	if _state == State.INACTIVE or not visible:
		return

	match _state:
		State.CHARGE:
			var progress := clampf(_timer / maxf(charge_time, 0.001), 0.0, 1.0)
			var line_w := lerpf(2.0, width, progress)
			var line_alpha := lerpf(0.25, 0.75, progress)
			var line_col := Color(tint.r, tint.g, tint.b, line_alpha)
			draw_line(Vector2.ZERO, Vector2(length, 0.0), line_col, line_w)

			# origin 处一个半径 width*0.5 的亮芯圆
			var r_origin := width * 0.5
			draw_circle(Vector2.ZERO, r_origin, line_col)
			var core_col := Color(1.0, 1.0, 1.0, lerpf(0.5, 0.95, progress))
			draw_circle(Vector2.ZERO, r_origin * 0.5, core_col)

		State.FIRE, State.FADE:
			var end_pt := Vector2(length, 0.0)
			var fa := _fade_alpha

			# 1. 外辉 (width * 1.5, alpha 0.16)
			var w_outer := width * 1.5
			var c_outer := Color(tint.r, tint.g, tint.b, 0.16 * fa)
			draw_line(Vector2.ZERO, end_pt, c_outer, w_outer)
			draw_circle(Vector2.ZERO, w_outer * 0.5, c_outer)
			draw_circle(end_pt, w_outer * 0.5, c_outer)

			# 2. 主体 (width, alpha 0.62)
			var w_main := width
			var c_main := Color(tint.r, tint.g, tint.b, 0.62 * fa)
			draw_line(Vector2.ZERO, end_pt, c_main, w_main)
			draw_circle(Vector2.ZERO, w_main * 0.5, c_main)
			draw_circle(end_pt, w_main * 0.5, c_main)

			# 3. 白芯 (width * 0.22, alpha 0.95)
			var w_core := width * 0.22
			var c_core := Color(1.0, 1.0, 1.0, 0.95 * fa)
			draw_line(Vector2.ZERO, end_pt, c_core, w_core)
			draw_circle(Vector2.ZERO, w_core * 0.5, c_core)
			draw_circle(end_pt, w_core * 0.5, c_core)
