class_name LightningBolt
extends Node2D

## 五雷法牌引雷演出：从武器射向落雷点的锯齿闪电（细亮芯 + 宽光晕 + 分支电弧）
## 已接入静态对象池（POOL_CAP=16），零动态 new/queue_free 分配。
##
## T-2.5（2026-10-15）电弧余韵：主干闪灭（0.13s）后 0.2s 内从命中点散 3 条微型电弧
## 再回池——雷光「有后劲」，不再是啪一下就没了。微弧与主干共用同一把锯齿生成函数
## （build_jagged_points 参数化 seg_len/amp_max），线体池化常驻（_setup_lines 一次建），
## 淡出复用宿主 modulate（主四线先熄灯再归位 alpha，微弧吃第二段渐隐），不加灯不加粒子。

## HDR 超白核心：辉光阈值钉在 1.0，只有这条核心线溢出起辉，外层 alpha 假光晕保持 LDR 不双辉
const CORE_COLOR := GameStyle.FX_HDR_LIGHTNING
const GLOW_COLOR := Color(0.55, 0.85, 1.0, 0.42)
const POOL_CAP := 16

# —— 电弧余韵（T-2.5）——
const ARC_AFTERGLOW_COUNT := 3     ## 微型电弧条数（计划 3-5 取下限，宁缺勿糊）
const ARC_AFTERGLOW_LIFE := 0.2    ## 余韵窗口（s）
const ARC_AFTERGLOW_LEN := 20.0    ## 单条微弧最大长度（px）
const ARC_AFTERGLOW_WIDTH := 1.3   ## 微弧线宽（HDR 细芯）

static var _pool: Array[LightningBolt] = []
static var _host: Node2D = null

var _line_glow: Line2D
var _line_core: Line2D
var _line_branch_glow: Line2D
var _line_branch_core: Line2D
var _afterglow: Array[Line2D] = []
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
	_host.z_index = 0
	scene.add_child(_host)

static func acquire(parent: Node) -> LightningBolt:
	_ensure_host(parent)

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
	# 2026-10-15 视觉克制化：基准线宽整体下调 ~30%（10.0/3.2/6.0/1.8 → 7.0/2.4/4.5/1.4），
	# 多武器同屏时闪电链不再是最抢眼的常驻元素；width_mult 星升倍率不变，等比受益
	_line_glow = _create_line(7.0, GLOW_COLOR)
	_line_core = _create_line(2.4, CORE_COLOR)
	_line_branch_glow = _create_line(4.5, GLOW_COLOR)
	_line_branch_core = _create_line(1.4, CORE_COLOR)
	for i in ARC_AFTERGLOW_COUNT:
		_afterglow.append(_create_line(ARC_AFTERGLOW_WIDTH, CORE_COLOR))

func _create_line(w: float, col: Color) -> Line2D:
	var line := Line2D.new()
	line.width = w
	line.default_color = col
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.z_index = 0
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

	# 主干赋值（余韵结束后主四线被隐藏过，复用激活时先全部亮回来）
	_line_glow.visible = true
	_line_core.visible = true
	_line_glow.points = main_points
	_line_glow.width = 7.0 * width_mult
	_line_glow.default_color = tint_col

	var core_c := CORE_COLOR if tint_col == GLOW_COLOR else GameStyle.FX_HDR_CORE
	_line_core.points = main_points
	_line_core.width = 2.4 * width_mult
	_line_core.default_color = core_c

	# 分支电弧赋值
	if branch_points.size() >= 2:
		_line_branch_glow.points = branch_points
		_line_branch_glow.width = 4.5 * width_mult
		_line_branch_glow.default_color = tint_col
		_line_branch_glow.visible = true

		_line_branch_core.points = branch_points
		_line_branch_core.width = 1.4 * width_mult
		_line_branch_core.default_color = core_c
		_line_branch_core.visible = true
	else:
		_line_branch_glow.visible = false
		_line_branch_core.visible = false

	modulate.a = 1.0
	visible = true

	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# 电弧余韵（T-2.5）：主干熄灯后从命中点散微弧再回池——先灭主四线再亮微弧，
	# 节点共享同一个 modulate，分两段走免得微弧跟着主干一起被压暗
	_tween.tween_callback(_spawn_afterglow)

## 主干已淡出，从命中点向四周散 3 条微型电弧（HDR 细芯，0.2s 渐隐），演完回池。
## 微弧线与主干同为本节点子线、共享局部坐标系：origin 直接取主干折线末点（命中端）局部坐标。
func _spawn_afterglow() -> void:
	var pts := _line_core.points
	var origin := pts[pts.size() - 1] if pts.size() >= 2 else Vector2.ZERO
	for arc_line in _afterglow:
		var dir := Vector2.RIGHT.rotated(randf_range(0.0, TAU))
		var tip := origin + dir.rotated(randf_range(-0.5, 0.5)) * randf_range(ARC_AFTERGLOW_LEN * 0.6, ARC_AFTERGLOW_LEN)
		arc_line.points = build_jagged_points(origin, tip, 8.0, 5.0)
		arc_line.visible = true
	modulate.a = 1.0
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, ARC_AFTERGLOW_LIFE).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_after_afterglow)

## 余韵熄灯后把主四线藏掉再回池：池体复用靠 activate 全量重铺，隐藏只是视觉兜底
func _after_afterglow() -> void:
	for l in [_line_glow, _line_core, _line_branch_glow, _line_branch_core]:
		l.visible = false
	for arc_line in _afterglow:
		arc_line.visible = false
	_recycle()

func _build_jagged_points(from_pos: Vector2, to_pos: Vector2) -> PackedVector2Array:
	return build_jagged_points(from_pos, to_pos, 22.0, 14.0)

## 锯齿折线生成（主干/微弧共用一把尺，T-2.5 参数化）：seg_len 控制折段密度、
## amp_max 控制法向抖幅（主干沿程 sin 包络缩放，微弧短且直、抖幅直接给满）
static func build_jagged_points(from_pos: Vector2, to_pos: Vector2, seg_len: float, amp_max: float) -> PackedVector2Array:
	var segs := maxi(int(from_pos.distance_to(to_pos) / seg_len), 3)
	var dir := to_pos - from_pos
	var side := dir.orthogonal().normalized()
	var points := PackedVector2Array()
	for i in range(segs + 1):
		var t := float(i) / float(segs)
		var p := dir * t
		if i > 0 and i < segs:
			var amp := amp_max * sin(t * PI)
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
