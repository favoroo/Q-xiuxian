class_name JuiceEffect
extends Node2D

## 游戏手感核心视觉反馈池：拾取流光、结算冲击环与步伐轻尘
## 纯轻量级 CanvasItem 动态绘制，零额外贴图依赖。
## （2026-10-11 用户拍板：受击火花整体下线——远程高频命中下仍是「空白处乱闪」，
## 后续会重构一套逻辑不一样的命中反馈；届时另起炉灶，不在此处复活旧火花。）
## （2026-10-12 用户拍板：死亡爆散整体下线——尸体塌缩后爆散独留空地，
## 正是「攻击时凭空乱闪的白色东西」本体；击杀反馈只剩尸体塌缩 + 跳字 + 音效。）
## 拾取 / 奔跑 / AoE 结算都会触发这里，是全场最频繁的分配来源，所以：
##   1) 特效节点走对象池（不再每次 new Node2D + add_child 触发整套生命周期）；
##   2) 粒子用并行数组而非「每颗粒子一个 Dictionary」；
##   3) 光环插值由 Tween.interpolate_value 改成 quad 缓出的闭式解。

enum EffectType { PICKUP_POP, STEP_DUST, SHOCKWAVE, IMPACT_POP, DEATH_BURST, HEAL_RISE }

const POOL_CAP := 128        ## 常驻池上限，超出时临时新建并在用完后释放
const Z_OVERLAY := 35        ## 常规特效层级（角色之上）
const Z_DUST := 5            ## 步伐微尘层级（贴近角色阴影）
const GROUND_SQUASH := 0.62  ## 俯视透视压扁比（地面冲击波贴地扩散基准）

const IMPACT_POP_FRAME_BUDGET := 6  ## 弹丸湮灭闪单物理帧预算限流闸，防止高穿透齐射糊屏
static var _last_pop_frame: int = -1
static var _pop_count_this_frame: int = 0

const DEATH_BURST_FRAME_BUDGET := 3  ## 死亡爆散单物理帧预算闸：群杀同帧爆开时最多 3 处，宁缺勿糊
static var _last_burst_frame: int = -1
static var _burst_count_this_frame: int = 0

## 重绘节流（2026-10-14 性能优化）：原 _process 每帧无条件 queue_redraw，
## 15 个活跃特效就是 15 次/帧重绘；粒子/光环数学每帧照跑（并行数组零分配很便宜），
## 只有重绘降 20Hz 并按 instance_id 错相，短促特效视觉上无感。
## （锁 30 帧后 30Hz 节流 = 帧长，等于每帧重绘，故取 20Hz 保持真实节流收益）
## 60fps 档（2026-10-15 VisualRate 档位联动）翻倍到 40Hz：冲击环半径 60fps 扩张、
## 画面 3 帧一画会台阶化；低档 20Hz 维持 perf_probe 预算口径。
const HZ_LOW := 20.0
const HZ_HIGH := 40.0
static func _redraw_interval() -> float:
	return VisualRate.interval(HZ_HIGH, HZ_LOW)

var effect_type: int = EffectType.PICKUP_POP
var lifetime: float = 0.2
var elapsed: float = 0.0

# 粒子（并行数组，下标一一对应）。数组预热后按下标覆盖，只用 _p_count 标记有效长度，
# 每次生成不再 clear/append，也不再有「每颗粒子一个 Dictionary」。
const PARTICLE_SLOTS := 32   ## 常驻容量（死亡爆散下线后实战粒子只剩步伐轻尘 3 颗，容量留足余量）
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
var _draw_phase: float = 0.0  ## 距下次重绘的剩余时间（错相载体）

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
	# 特效在 _process 里推进（渲染时钟），宿主开着物理插值会与插值中的实体错相位
	# ——真机帧率抖动时特效落点与画面上的实体错位乱闪（同 Player 关 WeaponHolder 插值一条坑）
	_host.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
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
	_p_count = 0
	_r_count = 0
	z_index = z
	global_position = pos
	modulate = Color(1, 1, 1, 1)
	visible = true
	_draw_phase = fposmod(float(get_instance_id() % 97) * 0.001, _redraw_interval())
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

	if _draw_phase <= 0.0:
		_draw_phase = _redraw_interval()
		queue_redraw()
	else:
		_draw_phase -= delta

func _draw() -> void:
	var progress := clampf(elapsed / lifetime, 0.0, 1.0)
	var alpha := 1.0 - progress
	var is_ground := effect_type == EffectType.SHOCKWAVE

	# 0. 冲击光环（弧段数随半径自适应；若是地面冲击波则施加俯视透视压扁，消除立面悬浮感）
	if is_ground:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, GROUND_SQUASH))
	for i in range(_r_count):
		var col: Color = _r_col[i]
		col.a *= alpha
		var width: float = maxf(1.0, _r_w[i] * (1.0 - progress * 0.6))
		draw_arc(Vector2.ZERO, _r_cur[i], 0.0, TAU, clampi(int(_r_cur[i] * 1.2), 10, 32), col, width, true)
	if is_ground:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 1. 灵尘：仍有速度时画成拖尾线段，静止后收成一个点
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

## 金币入体微缩流光：入体环用扩散方向（2→16），并叠 4 粒向内收束灵光微粒（T-1.5 强化）
static func spawn_pickup_pop(parent: Node, pos: Vector2, is_gold: bool = false) -> void:
	if not _ready_to_spawn(parent):
		return
	var fx := _acquire()
	fx._begin(EffectType.PICKUP_POP, pos, 0.18, Z_OVERLAY)
	var c := Color(0.35, 0.8, 1.0, 0.85) if not is_gold else Color(1.0, 0.88, 0.35, 0.95)
	fx._add_ring(2.0, 16.0, c, 2.0)
	for i in range(4):
		var ang := float(i) * (TAU / 4.0) + (0.2 if is_gold else 0.0)
		var p_off := Vector2(cos(ang), sin(ang)) * 8.0
		var p_vel := -p_off * 5.0
		fx._add_particle(p_off, p_vel, 2.0, c.lightened(0.2), 2.0)

## 治疗上飘（2026-10-14 P1 灵医可视出口）：被治疗目标身上升起 3 颗青绿灵光。
## 「谁在被奶」是玩家最该读到的信息（治疗者优先击杀的判断依据），灵医自己的
## 治疗冲击环（EnemyBase._pulse_heal）只标施法者，这里标受者。
static func spawn_heal_rise(parent: Node, pos: Vector2) -> void:
	if not _ready_to_spawn(parent):
		return
	if not _pos_in_viewport(parent, pos):
		return
	var fx := _acquire()
	fx._begin(EffectType.HEAL_RISE, pos, 0.45, Z_OVERLAY)
	var c := Color(0.45, 0.92, 0.62, 0.85)
	# 收缩小环压住目标轮廓（从身位圈收到中心），读「灵气入体」
	fx._add_ring(14.0, 4.0, c, 2.0)
	# 三颗上浮微粒（错位错速，衰减拖出余韵）
	for i in range(3):
		var off_x := (float(i) - 1.0) * 5.0
		fx._add_particle(
			Vector2(off_x, 4.0),
			Vector2(off_x * 0.6, -34.0 - float(i) * 9.0),
			2.5,
			c.lightened(0.25 if i == 1 else 0.0),
			2.2 - float(i) * 0.3)

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

## 弹丸湮灭微闪：弹丸因命中消亡时，在弹丸当前位置产生的冷冽灵光溃散（0.11s）。
## 【设计铁律】不同于挂在敌人身上的旧受击火花：它严格锚定在弹丸自身碰撞位置，
## 并受严格的单渲染帧限流闸（<=6发/帧）与视口门控双重保护，绝不空地乱闪、绝不糊屏。
## 限流闸用渲染帧计数（特效本体在 _process 里推进），不再用物理帧——双钟混用在真机
## 帧率抖动时会让预算闸与玩家实际看到的帧对不上。
static func spawn_impact_pop(parent: Node, pos: Vector2, col: Color, impact_dir: Vector2 = Vector2.ZERO) -> void:
	if not _ready_to_spawn(parent):
		return
	if not _pos_in_viewport(parent, pos):
		return

	var current_frame := Engine.get_frames_drawn()
	if current_frame != _last_pop_frame:
		_last_pop_frame = current_frame
		_pop_count_this_frame = 0
	if _pop_count_this_frame >= IMPACT_POP_FRAME_BUDGET:
		return
	_pop_count_this_frame += 1

	var fx := _acquire()
	fx._begin(EffectType.IMPACT_POP, pos, 0.11, Z_OVERLAY)
	# 极小光环消散 (2px -> 9px)
	fx._add_ring(2.0, 9.0, col, 1.8)

	# 2~3 颗细小灵气碎屑（沿命中反向轻微迸射）
	var base_angle := (-impact_dir).angle() if impact_dir.length_squared() > 0.001 else randf() * TAU
	for i in range(3):
		var a := base_angle + randf_range(-0.6, 0.6)
		var spd := randf_range(30.0, 65.0)
		fx._add_particle(
			Vector2.ZERO,
			Vector2(cos(a), sin(a)) * spd,
			3.0,
			col,
			1.2)

## 死亡爆散（轻量重建版，2026-10-13）：敌人死亡点迸出一小撮本种主色碎屑 + 微环。
## 【与旧死亡爆散的区别】旧版「尸体塌缩后独留空地乱闪」被整体下线；这版只做一小撮
## 带颜色信息的碎屑（碎屑色 = 敌种主色，读得出「死的是什么」），且严格受单渲染帧
## 预算闸（<=3 处/帧，群杀同帧宁缺勿糊）与视口门控双重保护，不与尸体塌缩抢戏。
static func spawn_death_burst(parent: Node, pos: Vector2, col: Color, elite: bool = false) -> void:
	if not _ready_to_spawn(parent):
		return
	if not _pos_in_viewport(parent, pos):
		return

	var current_frame := Engine.get_frames_drawn()
	if current_frame != _last_burst_frame:
		_last_burst_frame = current_frame
		_burst_count_this_frame = 0
	if _burst_count_this_frame >= DEATH_BURST_FRAME_BUDGET:
		return
	_burst_count_this_frame += 1

	var fx := _acquire()
	fx._begin(EffectType.DEATH_BURST, pos, 0.22, Z_OVERLAY)
	# 微环：从尸体塌缩尺寸向外淡出一小圈，给「这一下打死了」一个落点
	fx._add_ring(4.0, 16.0 if not elite else 24.0, col, 2.0)
	# 4~6 颗碎屑（精英加倍）：全向迸射 + 轻微向上偏置（受重力直觉的假象，比纯圆形更「爆」）
	var count := 8 if elite else 5
	for i in range(count):
		var a := randf() * TAU
		var spd := randf_range(60.0, 130.0)
		fx._add_particle(
			Vector2(randf_range(-2, 2), randf_range(-2, 2)),
			Vector2(cos(a), sin(a)) * spd + Vector2(0.0, -30.0),
			0.0,
			Color(col.r, col.g, col.b, randf_range(0.65, 0.95)),
			randf_range(1.5, 2.8))

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
