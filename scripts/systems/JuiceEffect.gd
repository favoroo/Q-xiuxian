class_name JuiceEffect
extends Node2D

## 游戏手感核心视觉反馈池：受击火花、妖气爆散环、拾取流光与步伐轻尘
## 纯轻量级 CanvasItem 动态绘制，零额外贴图依赖。
## 命中 / 击杀 / 拾取 / 奔跑每一步都会触发这里，是全场最频繁的分配来源，所以：
##   1) 特效节点走对象池（不再每次 new Node2D + add_child 触发整套生命周期）；
##   2) 粒子用并行数组而非「每颗粒子一个 Dictionary」；
##   3) 光环插值由 Tween.interpolate_value 改成 quad 缓出的闭式解。

enum EffectType { HIT_SPARKS, DEATH_BURST, PICKUP_POP, STEP_DUST, SHOCKWAVE }

const POOL_CAP := 128        ## 常驻池上限，超出时临时新建并在用完后释放
const Z_OVERLAY := 35        ## 常规特效层级（角色之上）
const Z_DUST := 5            ## 步伐微尘层级（贴近角色阴影）

# —— 受击火花分档常量（2026-10-11 频闪治理）——
# 远程穿透/弹射/多弹齐射下每秒命中可达几十次，普通命中原 9px 过曝核心 + 12 颗
# 360px/s 长程粒子会糊成满屏白闪。普通档全面收敛（小、淡、短、贴敌）；
# 暴击档保持原样，作为「值得看」的大花时刻。全局限流见 GameFeel.hit_spark_gate。
const SPARK_CORE_R_NORMAL := 5.0      ## 普通命中闪光核半径（暴击 14）
const SPARK_CORE_A_NORMAL := 0.55     ## 普通命中闪光核峰值α（暴击 0.95）
const SPARK_SLASH_LEN_NORMAL := 14.0  ## 普通命中斩痕半长（暴击 34）
const SPARK_SLASH_W_NORMAL := 2.2     ## 普通命中斩痕线宽（暴击 4.2）
const SPARK_COUNT_NORMAL := 6         ## 普通命中粒子数（暴击 18）
const SPARK_CONE_DEG_NORMAL := 45.0   ## 普通命中锥角半开角：贴敌飞溅不进空地（暴击 62）
const SPARK_SPD_MIN_NORMAL := 110.0   ## 普通命中粒子速度下限（暴击 260）
const SPARK_SPD_MAX_NORMAL := 200.0   ## 普通命中粒子速度上限（暴击 520）
const SPARK_LEN_MIN_NORMAL := 6.0     ## 普通命中拖尾长度下限（暴击 14）
const SPARK_LEN_MAX_NORMAL := 12.0    ## 普通命中拖尾长度上限（暴击 28）

var effect_type: int = EffectType.HIT_SPARKS
var lifetime: float = 0.2
var elapsed: float = 0.0
var is_crit: bool = false
var is_elite: bool = false
var _hit_angle: float = 0.0  ## 受击主方向角（用于绘制瞬爆中心斩痕星芒）

# 粒子（并行数组，下标一一对应）。数组预热后按下标覆盖，只用 _p_count 标记有效长度，
# 每次生成不再 clear/append，也不再有「每颗粒子一个 Dictionary」。
const PARTICLE_SLOTS := 32   ## 常驻容量（精英爆散 22 颗，留余量）
const RING_SLOTS := 4

var _p_count: int = 0
var _r_count: int = 0
var _p_pos: Array[Vector2] = []
var _p_vel: Array[Vector2] = []
var _p_len: Array[float] = []
var _p_col: Array[Color] = []
var _p_w: Array[float] = []

var _r_start: Array[float] = []
var _r_max: Array[float] = []
var _r_cur: Array[float] = []
var _r_col: Array[Color] = []
var _r_w: Array[float] = []

var _overflow: bool = false

static var _pool: Array[JuiceEffect] = []
static var _host: Node2D = null
static var _created: int = 0
static var active_count: int = 0  ## 当前活跃特效数：HUD 性能面板消费

# ----------------- 池管理 -----------------

## 释放特效池（退出时调用）
static func clear_cache() -> void:
	_pool.clear()
	_host = null
	_created = 0

## 池状态读数（自动化验证与调试用）
static func pool_size() -> int:
	return _pool.size()

static func created_count() -> int:
	return _created

static func host_child_count() -> int:
	return 0 if (_host == null or not is_instance_valid(_host)) else _host.get_child_count()

## 池宿主：挂在场景根下的一个 Node2D（z_index 保持 0，层级仍由每个特效自己决定，
## 这样 STEP_DUST 的 5 层与其余特效的 35 层不会因为换了父节点而错位）
static func _ensure_host(scene: Node) -> void:
	if _host != null and is_instance_valid(_host):
		return
	_pool.clear()
	_created = 0
	_host = Node2D.new()
	_host.name = "JuiceEffectPool"
	scene.add_child(_host)

static func _acquire() -> JuiceEffect:
	active_count += 1
	if not _pool.is_empty():
		var reused: JuiceEffect = _pool.pop_back()
		if is_instance_valid(reused):
			return reused
		_created = maxi(0, _created - 1)
	var overflow := _created >= POOL_CAP
	var fx := JuiceEffect.new()
	fx._overflow = overflow
	if not overflow:
		_created += 1
	_host.add_child(fx)
	return fx

func _release() -> void:
	active_count = maxi(0, active_count - 1)
	set_process(false)
	visible = false
	if _overflow or not is_instance_valid(_host):
		queue_free()
		return
	if _pool.size() < POOL_CAP:
		_pool.append(self)
	else:
		queue_free()

## 复用前只重置计数（数组保留容量与内容，靠下标覆盖）
func _begin(type: int, pos: Vector2, life: float, z: int) -> void:
	effect_type = type
	lifetime = life
	elapsed = 0.0
	is_crit = false
	is_elite = false
	_p_count = 0
	_r_count = 0
	z_index = z
	global_position = pos
	modulate = Color(1, 1, 1, 1)
	visible = true
	set_process(true)
	queue_redraw()

func _add_particle(pos: Vector2, vel: Vector2, length: float, col: Color, width: float) -> void:
	var i := _p_count
	if i < _p_pos.size():
		_p_pos[i] = pos
		_p_vel[i] = vel
		_p_len[i] = length
		_p_col[i] = col
		_p_w[i] = width
	else:
		_p_pos.append(pos)
		_p_vel.append(vel)
		_p_len.append(length)
		_p_col.append(col)
		_p_w.append(width)
	_p_count = i + 1

func _add_ring(start_r: float, max_r: float, col: Color, width: float) -> void:
	var i := _r_count
	if i < _r_start.size():
		_r_start[i] = start_r
		_r_max[i] = max_r
		_r_cur[i] = start_r
		_r_col[i] = col
		_r_w[i] = width
	else:
		_r_start.append(start_r)
		_r_max.append(max_r)
		_r_cur.append(start_r)
		_r_col.append(col)
		_r_w.append(width)
	_r_count = i + 1

## 首次入树时一次性开好常驻容量，之后所有生成都走下标覆盖
func _ready() -> void:
	_p_pos.resize(PARTICLE_SLOTS)
	_p_vel.resize(PARTICLE_SLOTS)
	_p_len.resize(PARTICLE_SLOTS)
	_p_col.resize(PARTICLE_SLOTS)
	_p_w.resize(PARTICLE_SLOTS)
	_r_start.resize(RING_SLOTS)
	_r_max.resize(RING_SLOTS)
	_r_cur.resize(RING_SLOTS)
	_r_col.resize(RING_SLOTS)
	_r_w.resize(RING_SLOTS)
	_p_count = 0
	_r_count = 0
	set_process(false)

# ----------------- 每帧驱动 -----------------

func _process(delta: float) -> void:
	elapsed += delta
	var progress := elapsed / lifetime
	if progress >= 1.0:
		_release()
		return
	progress = clampf(progress, 0.0, 1.0)

	# 光环半径：TRANS_QUAD / EASE_OUT 的闭式解
	var k := 1.0 - (1.0 - progress) * (1.0 - progress)
	for i in range(_r_count):
		_r_cur[i] = lerpf(_r_start[i], _r_max[i], k)

	# 粒子直线推进 + 速度衰减
	var decay := 1.0 - delta * 9.0
	for i in range(_p_count):
		_p_pos[i] = _p_pos[i] + _p_vel[i] * delta
		_p_vel[i] = _p_vel[i] * decay

	queue_redraw()

func _draw() -> void:
	var progress := clampf(elapsed / lifetime, 0.0, 1.0)
	var alpha := 1.0 - progress

	# 0. 受击瞬间中心闪光核与锐利斩痕光刃（空洞骑士风：黑白/青金高对比度爆发）
	# 普通命中降档：小而淡的核 + 短斩痕（防高频命中糊成满屏白闪）；暴击保留过曝大核心。
	if effect_type == EffectType.HIT_SPARKS and progress < 0.42:
		var flash_t := 1.0 - (progress / 0.42)
		var core_r := (14.0 if is_crit else SPARK_CORE_R_NORMAL) * flash_t
		var core_a := (0.95 if is_crit else SPARK_CORE_A_NORMAL) * flash_t
		draw_circle(Vector2.ZERO, core_r, Color(1.5, 1.5, 1.35, core_a))
		var slash_dir := Vector2.RIGHT.rotated(_hit_angle + PI * 0.5)
		var slash_len := (34.0 if is_crit else SPARK_SLASH_LEN_NORMAL) * (0.35 + 0.65 * flash_t)
		var slash_col := Color(1.0, 0.94, 0.68, flash_t * 0.95) if is_crit else Color(0.92, 0.98, 1.0, flash_t * 0.92)
		draw_line(-slash_dir * slash_len, slash_dir * slash_len, slash_col, (4.2 if is_crit else SPARK_SLASH_W_NORMAL) * flash_t, true)
		if is_crit:
			var cross_dir := Vector2.RIGHT.rotated(_hit_angle)
			draw_line(-cross_dir * (slash_len * 0.75), cross_dir * (slash_len * 1.15), Color(1.0, 0.42, 0.18, flash_t * 0.92), 3.4 * flash_t, true)

	# 1. 冲击光环
	for i in range(_r_count):
		var col: Color = _r_col[i]
		col.a *= alpha
		var width: float = maxf(1.0, _r_w[i] * (1.0 - progress * 0.6))
		draw_arc(Vector2.ZERO, _r_cur[i], 0.0, TAU, 32, col, width, true)

	# 2. 火花/灵尘：仍有速度时画成拖尾线段，静止后收成一个点
	for i in range(_p_count):
		var pcol: Color = _p_col[i]
		pcol.a *= alpha
		var pos: Vector2 = _p_pos[i]
		var vel: Vector2 = _p_vel[i]
		var w: float = _p_w[i]
		if vel.length_squared() > 100.0:
			var tip: Vector2 = pos + vel.normalized() * _p_len[i] * (1.0 - progress * 0.5)
			draw_line(pos, tip, pcol, w, true)
		else:
			draw_circle(pos, w, pcol)

# ----------------- 静态生成接口 -----------------

## 受击灵芒火花：沿打击方向呈扇形爆开。
## 分档（2026-10-11 频闪治理）：普通命中小而贴敌（粒子少、射程短、锥角窄），
## 暴击保留大花。高频命中下是否放行由调用方走 GameFeel.hit_spark_gate 限流。
static func spawn_hit_sparks(parent: Node, pos: Vector2, hit_dir: Vector2, crit: bool = false) -> void:
	if not _ready_to_spawn(parent):
		return
	# 视口兜底：打中了看不见的目标（屏外妖物/藏宝匣）也不许在屏内露出特效。
	# EnemyBase._offscreen 是 10Hz 采样且留有 64px 边缘带，拦不住边缘泄露，这里用实时画布变换终审。
	if not _pos_in_viewport(parent, pos):
		return
	var fx := _acquire()
	fx._begin(EffectType.HIT_SPARKS, pos, 0.22 if not crit else 0.28, Z_OVERLAY)
	fx.is_crit = crit

	var count := SPARK_COUNT_NORMAL if not crit else 18
	var base_angle := hit_dir.angle() if hit_dir.length_squared() > 0.01 else randf() * TAU
	fx._hit_angle = base_angle
	var cone := deg_to_rad(SPARK_CONE_DEG_NORMAL if not crit else 62.0)

	var core_col := Color(0.95, 0.99, 1.0, 1.0) if not crit else Color(1.0, 0.96, 0.70, 1.0)
	var glow_col := Color(0.35, 0.75, 1.0, 0.95) if not crit else Color(1.0, 0.60, 0.15, 0.95)

	for i in range(count):
		var a := base_angle + randf_range(-cone, cone)
		var spd := randf_range(SPARK_SPD_MIN_NORMAL, SPARK_SPD_MAX_NORMAL) if not crit else randf_range(260.0, 520.0)
		var col := core_col if randf() < 0.45 else glow_col
		fx._add_particle(
			Vector2.ZERO,
			Vector2(cos(a), sin(a)) * spd,
			randf_range(SPARK_LEN_MIN_NORMAL, SPARK_LEN_MAX_NORMAL) if not crit else randf_range(14.0, 28.0),
			col,
			3.0 if not crit else 4.0)

	# 暴击追加一记微型扩散光斑环
	if crit:
		fx._add_ring(4.0, 32.0, Color(1.0, 0.88, 0.4, 0.85), 3.2)

## 妖物死灭爆散：灵气崩解环 + 散逸灵尘。
## overkill_ratio = 致命一刀的溢出伤害 / 最大气血（0~1.5）：大数字暴击把妖物「打爆」，
## 爆散环径与灵尘量随溢出比例放大（2026-10-10 斩杀反馈）。
## crit_kill = 致命一刀是暴击：追加一圈暴击同款鎏金冲击环，暴击斩杀与普通伏诛一眼可辨（2026-10-11）。
static func spawn_death_burst(parent: Node, pos: Vector2, elite: bool = false, overkill_ratio: float = 0.0, crit_kill: bool = false) -> void:
	if not _ready_to_spawn(parent):
		return
	# 同火花：屏外击杀的爆散环不生成（尸体塌缩 0.14s 就没，爆散却要放 0.4s，最像「空地凭空特效」）
	if not _pos_in_viewport(parent, pos):
		return
	var boost := 1.0 + clampf(overkill_ratio, 0.0, 1.5) * 0.5
	var fx := _acquire()
	fx._begin(EffectType.DEATH_BURST, pos, 0.32 if not elite else 0.45, Z_OVERLAY)
	fx.is_elite = elite
	fx.is_crit = crit_kill

	# 冲击扩散光环
	var ring_col := Color(0.45, 0.8, 1.0, 0.8) if not elite else Color(1.0, 0.85, 0.3, 0.95)
	fx._add_ring(6.0, (36.0 if not elite else 64.0) * boost, ring_col, (3.5 if not elite else 5.0) * lerpf(1.0, boost, 0.5))
	if elite:
		fx._add_ring(2.0, 42.0 * boost, Color(1.0, 1.0, 0.9, 0.9), 2.5)
	# 暴击斩杀追加一记鎏金冲击环（比主环更锐更快，复用暴击火花的金环色温）
	if crit_kill:
		fx._add_ring(3.0, 48.0 * boost, Color(1.0, 0.88, 0.4, 0.9), 3.2)

	# 崩散灵气粒子
	var count := int(round((10.0 if not elite else 22.0) * boost))
	for i in range(count):
		var a := randf() * TAU
		var spd := (randf_range(90.0, 220.0) if not elite else randf_range(140.0, 360.0)) * lerpf(1.0, boost, 0.6)
		var col := Color(0.7, 0.9, 1.0, 0.9) if not elite else Color(1.0, 0.75 + randf() * 0.25, 0.3, 0.9)
		fx._add_particle(
			Vector2.ZERO,
			Vector2(cos(a), sin(a)) * spd,
			randf_range(6.0, 14.0),
			col,
			2.0 if not elite else 3.0)

## AoE 结算冲击波：一道环从圆心扫到判定半径（Boss 震地 / 丹爆自爆的「伤害来源」读法）。
## 与预警圈同源：max_radius 必须传判定半径本身——扫过的范围就是受伤的范围。
static func spawn_shockwave(parent: Node, pos: Vector2, max_radius: float, col: Color, duration: float = 0.32) -> void:
	if not _ready_to_spawn(parent):
		return
	# 同爆散：结算点不在屏内就不放（屏外凭空一圈没有信息量）
	if not _pos_in_viewport(parent, pos):
		return
	var fx := _acquire()
	fx._begin(EffectType.SHOCKWAVE, pos, duration, Z_OVERLAY)
	# 主环扫满判定半径；内亮环略滞后收窄，给扩散加一点层次
	fx._add_ring(max_radius * 0.12, max_radius, col, 6.0)
	fx._add_ring(max_radius * 0.06, max_radius * 0.9, col.lightened(0.45), 2.5)

## 灵石入体微缩流光
static func spawn_pickup_pop(parent: Node, pos: Vector2, is_gold: bool = false) -> void:
	if not _ready_to_spawn(parent):
		return
	var fx := _acquire()
	fx._begin(EffectType.PICKUP_POP, pos, 0.18, Z_OVERLAY)
	var c := Color(0.35, 0.8, 1.0, 0.85) if not is_gold else Color(1.0, 0.88, 0.35, 0.95)
	fx._add_ring(16.0, 2.0, c, 2.0)

## 步伐轻尘（奔跑时的脚底微尘）
static func spawn_step_dust(parent: Node, pos: Vector2, move_dir: Vector2) -> void:
	if not _ready_to_spawn(parent):
		return
	var fx := _acquire()
	fx._begin(EffectType.STEP_DUST, pos, 0.20, Z_DUST)

	var puff_dir := -move_dir.normalized()
	for i in range(3):
		var a := puff_dir.angle() + randf_range(-0.5, 0.5)
		var spd := randf_range(20.0, 50.0)
		fx._add_particle(
			Vector2(randf_range(-4, 4), randf_range(-2, 2)),
			Vector2(cos(a), sin(a)) * spd,
			0.0,
			Color(0.7, 0.8, 0.92, 0.35),
			randf_range(1.8, 3.2))

## 所有 spawn 的前置：拿到有效场景根并保证池宿主已就位
static func _ready_to_spawn(parent: Node) -> bool:
	if parent == null or not is_instance_valid(parent):
		return false
	var scene := _scene_root_for(parent)
	if scene == null:
		return false
	_ensure_host(scene)
	return _host != null and is_instance_valid(_host)

## 命中/爆散类特效的视口终审：位置投到屏幕坐标后不在可见矩形内（再收 8px 防边缘露半截）就不发。
## 拿不到视口（极端 headless 环境）时按可见放行——宁可多画，不误杀正常反馈。
static func _pos_in_viewport(parent: Node, pos: Vector2) -> bool:
	var vp := parent.get_viewport()
	if vp == null:
		return true
	var screen := vp.get_canvas_transform() * pos
	return vp.get_visible_rect().grow(-8.0).has_point(screen)

## 取池宿主应挂的场景根（测试里 current_scene 为空时退回向上找 root 的直接子节点）
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
