class_name DamageNumber
extends Node2D

## 伤害跳字：扇形抛物线漂移 + 暴击弹性过冲（先冲过头再回落）。
## 高频命中下走节点池：一次命中不再 new Node2D + Label + Tween，
## 运动曲线改由 _process 手写（时序与原来的并行 Tween 完全对齐），命中峰值时零分配。

## 时序（秒）：漂移阶段 → 回落阶段 → 淡出阶段
const PHASE_DRIFT := 0.52
const PHASE_SETTLE := 0.22
const PHASE_FADE := 0.16
const POP_DUR_NORMAL := 0.10
const POP_DUR_CRIT := 0.12
const POOL_CAP := 96      ## 常驻池上限，超出时临时新建并在用完后释放

static var _normal_settings: LabelSettings
static var _crit_settings: LabelSettings
static var _heal_settings: LabelSettings

static var _pool: Array[DamageNumber] = []
static var _host: Node2D = null
static var _created: int = 0

var _label: Label = null
var _overflow: bool = false
var _t: float = 0.0
var _origin: Vector2 = Vector2.ZERO
var _drift_x: float = 0.0
var _rise_y: float = 0.0
var _is_crit: bool = false

## 释放池与样式缓存（退出时调用），避免常驻引用被判成资源泄漏
static func clear_cache() -> void:
	_pool.clear()
	_host = null
	_created = 0
	_normal_settings = null
	_crit_settings = null
	_heal_settings = null

## 池状态读数（自动化验证与调试用）
static func pool_size() -> int:
	return _pool.size()

static func created_count() -> int:
	return _created

static func host_child_count() -> int:
	return 0 if (_host == null or not is_instance_valid(_host)) else _host.get_child_count()

## 样式表只建一次，所有跳字共享（避免 GC 抖动）
static func _ensure_settings() -> void:
	if _normal_settings != null:
		return

	_normal_settings = LabelSettings.new()
	_normal_settings.font = GameStyle.body_font()
	_normal_settings.font_size = 14
	_normal_settings.font_color = GameStyle.PAPER
	_normal_settings.outline_size = 4
	_normal_settings.outline_color = Color(0.02, 0.03, 0.06, 0.92)

	_crit_settings = LabelSettings.new()
	_crit_settings.font = GameStyle.display_font()
	_crit_settings.font_size = 20
	_crit_settings.font_color = GameStyle.YELLOW
	_crit_settings.outline_size = 5
	_crit_settings.outline_color = Color(0.04, 0.02, 0.0, 0.96)

	_heal_settings = LabelSettings.new()
	_heal_settings.font = GameStyle.body_font()
	_heal_settings.font_size = 15
	_heal_settings.font_color = GameStyle.GOOD
	_heal_settings.outline_size = 4
	_heal_settings.outline_color = Color(0.02, 0.03, 0.06, 0.95)

## 池宿主：常驻场景根下的一个 Node2D，跳字全部挂在它下面、用完不摘（省掉反复 reparent）
static func _ensure_host(scene: Node) -> void:
	if _host != null and is_instance_valid(_host):
		return
	# 换局（Main 重建）后旧宿主连同池内节点一起被释放，必须清空引用防止拿到野对象
	_pool.clear()
	_created = 0
	_host = Node2D.new()
	_host.name = "DamageNumberPool"
	_host.z_index = 50
	scene.add_child(_host)

static func _acquire() -> DamageNumber:
	if not _pool.is_empty():
		var reused: DamageNumber = _pool.pop_back()
		if is_instance_valid(reused):
			return reused
		_created = maxi(0, _created - 1)
	var overflow := _created >= POOL_CAP
	var n := DamageNumber.new()
	n._overflow = overflow
	if not overflow:
		_created += 1
	_host.add_child(n)
	return n

## 取池宿主应挂的场景根。
## 测试里 Main 是手动 add_child 到 root 的，此时 tree.current_scene 为空 → 退回向上找 root 的直接子节点。
static func _scene_root_for(node: Node) -> Node:
	var tree := node.get_tree()
	if tree == null:
		return null
	if tree.current_scene != null and is_instance_valid(tree.current_scene):
		return tree.current_scene
	var cur: Node = node
	while cur.get_parent() != null and cur.get_parent() != tree.root:
		cur = cur.get_parent()
	return cur

## 生成一条跳字。parent 仅用于定位场景树，节点实际挂在池宿主下（保持既有调用签名）
static func spawn(parent: Node, pos: Vector2, amount: int, is_crit: bool = false, custom_text: String = "") -> void:
	if not bool(SettingsManager.get_val(&"display", &"damage_numbers", true)):
		return
	if parent == null or not is_instance_valid(parent):
		return
	var scene := _scene_root_for(parent)
	if scene == null:
		return

	_ensure_settings()
	_ensure_host(scene)

	var text := custom_text
	var settings := _heal_settings
	if custom_text == "":
		if is_crit:
			text = str(amount) + "!"
			settings = _crit_settings
		else:
			text = str(amount)
			settings = _normal_settings

	var n := _acquire()
	if n == null or not is_instance_valid(n):
		return
	n._start(
		pos + Vector2(randf_range(-12.0, 12.0), -12.0),
		text, settings, is_crit,
		randf_range(-26.0, 26.0),
		randf_range(32.0, 42.0) if not is_crit else randf_range(40.0, 52.0)
	)

func _ready() -> void:
	if _label == null:
		_label = Label.new()
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.position = Vector2(-35.0, -12.0)
		_label.custom_minimum_size = Vector2(70.0, 24.0)
		add_child(_label)
	visible = false
	set_process(false)

## TRANS_BACK / EASE_OUT 的等价闭式解（Godot Tween 用的是同一条曲线）
static func _back_out(x: float) -> float:
	x = clampf(x, 0.0, 1.0) - 1.0
	return 1.0 + 2.70158 * x * x * x + 1.70158 * x * x

func _start(world_pos: Vector2, text: String, settings: LabelSettings, crit: bool, drift_x: float, rise_y: float) -> void:
	_label.text = text
	_label.label_settings = settings
	global_position = world_pos
	_origin = position
	_drift_x = drift_x
	_rise_y = rise_y
	_is_crit = crit
	_t = 0.0
	modulate = Color(1, 1, 1, 1)
	scale = Vector2(0.5, 0.5) if crit else Vector2(0.85, 0.85)
	visible = true
	set_process(true)

func _process(delta: float) -> void:
	_t += delta
	if _t >= PHASE_DRIFT + PHASE_SETTLE + PHASE_FADE:
		_release()
		return

	# 1. 位移：X 侧移 + Y 上冲，二次缓出（先冲得快再稳住）
	var e := clampf(_t / PHASE_DRIFT, 0.0, 1.0)
	e = 1.0 - (1.0 - e) * (1.0 - e)
	position = _origin + Vector2(_drift_x * e, -_rise_y * e)

	# 2. 尺寸：弹出（暴击带过冲）→ 平台 → 回落
	var s: float
	if _is_crit:
		if _t < POP_DUR_CRIT:
			s = lerpf(0.5, 1.35, _back_out(_t / POP_DUR_CRIT))
		elif _t < PHASE_DRIFT:
			s = 1.35
		else:
			s = lerpf(1.35, 1.0, clampf((_t - PHASE_DRIFT) / PHASE_SETTLE, 0.0, 1.0))
	else:
		if _t < POP_DUR_NORMAL:
			s = lerpf(0.85, 1.05, _back_out(_t / POP_DUR_NORMAL))
		elif _t < PHASE_DRIFT:
			s = 1.05
		else:
			s = lerpf(1.05, 0.9, clampf((_t - PHASE_DRIFT) / PHASE_SETTLE, 0.0, 1.0))
	scale = Vector2(s, s)

	# 3. 淡出
	var fade_at := PHASE_DRIFT + PHASE_SETTLE
	modulate.a = 1.0 if _t < fade_at else 1.0 - clampf((_t - fade_at) / PHASE_FADE, 0.0, 1.0)

func _release() -> void:
	set_process(false)
	visible = false
	if _overflow or not is_instance_valid(_host):
		queue_free()
		return
	if _pool.size() < POOL_CAP:
		_pool.append(self)
	else:
		queue_free()
