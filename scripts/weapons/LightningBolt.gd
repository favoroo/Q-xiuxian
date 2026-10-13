class_name LightningBolt
extends Node2D

## 五雷法牌引雷演出：从武器射向落雷点的锯齿闪电（细亮芯 + 宽光晕 + 分支电弧）
## 已接入静态对象池（POOL_CAP=16），零动态 new/queue_free 分配。

const CORE_COLOR := Color(1.0, 0.98, 0.85, 1.0)
const GLOW_COLOR := Color(0.55, 0.85, 1.0, 0.42)
const POOL_CAP := 16

static var _pool: Array[LightningBolt] = []
static var _host: Node2D = null

var _line_glow: Line2D
var _line_core: Line2D
var _line_branch_glow: Line2D
var _line_branch_core: Line2D
var _tween: Tween = null
var _is_pooled: bool = false

# ----------------- 池管理 -----------------

static func clear_cache() -> void:
	_pool.clear()
	_host = null

static func _ensure_host(scene: Node) -> void:
	if _host != null and is_instance_valid(_host):
		return
	_pool.clear()
	_host = Node2D.new()
	_host.name = "LightningBoltPool"
	_host.z_index = 25
	scene.add_child(_host)

static func acquire(parent: Node) -> LightningBolt:
	var tree := parent.get_tree()
	var scene := tree.current_scene if (tree != null and tree.current_scene != null) else parent
	_ensure_host(scene)

	while not _pool.is_empty():
		var reused: LightningBolt = _pool.pop_back()
		if is_instance_valid(reused):
			reused.visible = true
			return reused

	var bolt := LightningBolt.new()
	bolt._is_pooled = true
	_host.add_child(bolt)
	return bolt

func _recycle() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	visible = false
	if _pool.size() < POOL_CAP and is_instance_valid(_host):
		_pool.append(self)
	else:
		queue_free()

# ----------------- 生命周期与构建 -----------------

func _ready() -> void:
	_setup_lines()

func _setup_lines() -> void:
	if _line_glow != null:
		return
	_line_glow = _create_line(10.0, GLOW_COLOR)
	_line_core = _create_line(3.2, CORE_COLOR)
	_line_branch_glow = _create_line(6.0, GLOW_COLOR)
	_line_branch_core = _create_line(1.8, CORE_COLOR)

func _create_line(w: float, col: Color) -> Line2D:
	var line := Line2D.new()
	line.width = w
	line.default_color = col
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.z_index = 25
	add_child(line)
	return line

## 激活动画（出膛）：全量重置坐标、折线点与淡出 Tween
func activate(from_pos: Vector2, to_pos: Vector2, tint_col: Color, width_mult: float = 1.0) -> void:
	_setup_lines()
	if _tween != null and _tween.is_valid():
		_tween.kill()

	global_position = from_pos
	var main_points := _build_jagged_points(from_pos, to_pos)
	var branch_points := _build_branch_points(main_points, to_pos - from_pos)

	# 主干赋值
	_line_glow.points = main_points
	_line_glow.width = 10.0 * width_mult
	_line_glow.default_color = tint_col

	var core_c := CORE_COLOR if tint_col == GLOW_COLOR else Color(1.0, 0.97, 0.9, 1.0)
	_line_core.points = main_points
	_line_core.width = 3.2 * width_mult
	_line_core.default_color = core_c

	# 分支电弧赋值
	if branch_points.size() >= 2:
		_line_branch_glow.points = branch_points
		_line_branch_glow.width = 6.0 * width_mult
		_line_branch_glow.default_color = tint_col
		_line_branch_glow.visible = true

		_line_branch_core.points = branch_points
		_line_branch_core.width = 1.8 * width_mult
		_line_branch_core.default_color = core_c
		_line_branch_core.visible = true
	else:
		_line_branch_glow.visible = false
		_line_branch_core.visible = false

	modulate.a = 1.0
	visible = true

	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_callback(_recycle)

func _build_jagged_points(from_pos: Vector2, to_pos: Vector2) -> PackedVector2Array:
	var segs := maxi(int(from_pos.distance_to(to_pos) / 22.0), 6)
	var dir := to_pos - from_pos
	var side := dir.orthogonal().normalized()
	var points := PackedVector2Array()
	for i in range(segs + 1):
		var t := float(i) / float(segs)
		var p := dir * t
		if i > 0 and i < segs:
			var amp := 14.0 * sin(t * PI)
			p += side * randf_range(-amp, amp)
		points.append(p)
	return points

func _build_branch_points(main_pts: PackedVector2Array, main_dir: Vector2) -> PackedVector2Array:
	if main_pts.size() < 4:
		return PackedVector2Array()
	# 从主干 35% ~ 65% 之间随机挑一个分叉点
	var fork_idx := randi_range(int(main_pts.size() * 0.35), int(main_pts.size() * 0.65))
	var fork_origin: Vector2 = main_pts[fork_idx]
	var side_sign := 1.0 if randf() > 0.5 else -1.0
	var branch_dir := main_dir.normalized().rotated(side_sign * randf_range(0.45, 0.85))

	var branch := PackedVector2Array()
	branch.append(fork_origin)
	var len1 := randf_range(16.0, 24.0)
	branch.append(fork_origin + branch_dir * len1)
	var branch_dir2 := branch_dir.rotated(side_sign * randf_range(-0.35, 0.35))
	var len2 := randf_range(10.0, 16.0)
	branch.append(fork_origin + branch_dir * len1 + branch_dir2 * len2)
	return branch
