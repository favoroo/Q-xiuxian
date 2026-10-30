class_name HealOrb
extends Area2D

## 残丹/回春葫芦：走近摄灵圈吸附入口的回复珠
##   ①「走近即吸附」—— 实现了 magnet_to，Player.PickupArea（loot 层）碰到直接触发吸附；
##      同时在 _physics_process 里做拾取圈每帧复验，兼顾「满血时在圈内、掉血当拍起飞」
##      与「人在圈里珠子才落下」的场景。
##      画幅与晶石同档（≈24 px），两颗掉在地上的东西一般大。
##   ②「满血不会被拾取」—— 顶满时进圈不起飞，贴身不入口，留在原地压成灰相；掉血那一拍
##      由每帧复验放行起飞。身体与摄灵圈一离开就恢复可入口相，掉血后再靠近可正常吸附。
##   ③「回合结束时未拾取的葫芦，溢出生命值部分变成金币」—— WaveSpawner.end_wave 把场上的
##      珠子请进袖中结算：按当前缺血回血，回不上的那一截走 GameBalance.heal_overflow_stones
##      折金币并当场飘字。既不白丢治疗，也不留一颗永远躺在地上的珠子。
## 纯代码构建，无需场景文件；加入 gems 组（回合末按组遍历结算）。

const FULL_HP_EPS := 0.01            ## 视为满血的容差（每秒回血顶到上限时的浮点毛刺）
const ARRIVE_DIST := 22.0            ## 回合末结算飞抵距离
const SPRITE_SCALE := Vector2(0.375, 0.375)  ## 128 图源缩到 ≈48 px 画幅：与 AstralGem（48×48 图 ×1）同档大小
const JUDGE_RADIUS := 10.0           ## 判定圆跟着画幅一起收：与 AstralGem 那颗的半径 10 同一把尺子
const TINT_READY := Color(0.65, 1.35, 0.7)    ## 可入口
const TINT_WAITING := Color(0.50, 0.60, 0.53) ## 满血待命：看得见，但不催你

# —— 对象池（2026-10-11，照 AstralGem 模式）——
## 残丹掉落/藏宝匣葫芦每次 new()+queue_free；掉落频率低于宝石但同属击杀路径，顺手同池化。
## 回收时必须 remove_from_group("gems")：回合末结算按组请珠，池里休眠的假珠不能入账。
## 兼容约定：裸 new() + add_child 的旧路径（HealOrbCheck/预览）保持原行为不受影响。
const POOL_CAP := 64
const BASE_HEAL := 3.0        ## 默认回生命：activate 复用时重置的基准（与字段初值同源）
static var _pool: Array[HealOrb] = []
static var _host: Node2D = null
static var created_count: int = 0
static var reused_count: int = 0
static var active_count: int = 0  ## 当前在场回复珠数：HUD「宝」计数与宝石合并统计

static func clear_pool() -> void:
	_pool.clear()
	active_count = 0
	_host = null

static func _ensure_host(parent: Node) -> void:
	if _host != null and is_instance_valid(_host):
		return
	_pool.clear()
	_host = Node2D.new()
	_host.name = "HealOrbPool"
	parent.add_child(_host)

## 取一颗回复珠（优先复用）：调用方在调用后写 global_position/heal_amount 或 heal_pct，最后调 activate()
static func acquire_or_new(parent: Node) -> HealOrb:
	_ensure_host(parent)
	while not _pool.is_empty():
		var o: HealOrb = _pool.pop_back()
		if is_instance_valid(o):
			reused_count += 1
			return o
	var no := HealOrb.new()
	created_count += 1
	_host.add_child(no)
	return no

var heal_amount: float = 3.0
var heal_pct: float = 0.0   ## >0 时按玩家生命上限百分比恢复（回春葫芦用）

var target_player: Node2D = null   ## 磁吸与回合末结算飞行途中非空
var waiting_full_hp: bool = false  ## true = 此刻正被满血的身体压着，这一拍不入口；身体一离开就转回 false
var current_speed: float = -40.0
var max_speed: float = 680.0
var acceleration: float = 850.0

var _sprite: Sprite2D
var _loot_renderer: ProceduralLootRenderer
var _bob_tween: Tween = null
var _settling: bool = false        ## 回合末结算中（不再被满血闸拦下）
var _pooled: bool = false          ## 池状态标记：true = 已回池休眠（防双重回收）
var _shape: CollisionShape2D = null

func _ready() -> void:
	add_to_group("gems")
	# 物理状态一律 deferred：池化之后这条路径可能在物理回调里被 add_child 触发
	# （刀锋命中藏宝匣 → take_damage → _destroy → acquire_or_new 首建一颗新珠），
	# 而 flushing queries 期间改层/掩码/monitoring、或往 Area 里挂 CollisionShape2D，
	# 引擎报 "Can't change this state while flushing queries" 且这一拍的状态不生效
	# （实测 ProjectileProbe 被这条错误刷屏拖到超时）。activate/recycle 早就走 deferred 了，
	# 首建这一路得同一把尺。
	set_deferred("collision_layer", 16)  # loot：金币那一层的账，别处若要吸灵仍能看到本珠
	set_deferred("collision_mask", 2)    # player：本珠只认身体，不吃隔空吸附
	set_deferred("monitoring", true)
	set_deferred("monitorable", true)

	_sprite = Sprite2D.new()
	_sprite.texture = load("res://assets/art/icon_hp.png")
	_sprite.modulate = TINT_READY
	_sprite.scale = SPRITE_SCALE
	_sprite.visible = false
	add_child(_sprite)

	_loot_renderer = ProceduralLootRenderer.new()
	_loot_renderer.loot_type = ProceduralLootRenderer.LootType.HEAL_ORB
	_loot_renderer.self_bob = true   ## 对齐 AstralGem：浮动交由渲染器手写 sin，不挂常驻 set_loops Tween
	add_child(_loot_renderer)

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = JUDGE_RADIUS
	shape.shape = circle
	_shape = shape
	# 形状挂树只能 deferred：池化之后 _ready 可能在物理回调里被触发（刀锋打碎藏宝匣 →
	# take_damage → _destroy → acquire_or_new 首建一颗新珠），而往一个正在 flush queries 的
	# Area 里挂 CollisionShape2D，引擎报 "Can't change this state while flushing queries"
	# 且这一拍的判定不生效（实测 ProjectileProbe 被这条错误刷屏拖到 25s 超时）。
	# 判据要量这颗判定圆的，读 _shape 引用本身（见 heal_orb_check._orb_judge_radius）。
	add_child.call_deferred(shape)
	active_count += 1
	_start_bob()

## 出膛激活：池化后 _ready 只在首建时跑过，全部运行时状态在这里重铺
##（改字段签名时对照这里）。heal_amount/heal_pct 先归默认，调用方按需覆盖。
func activate() -> void:
	if _pooled:
		active_count += 1
	_pooled = false
	# 池化复用是从回收点瞬移到掉落点：不重置物理插值，真机帧率抖动时首帧会渲染旧位置滑行
	reset_physics_interpolation()
	visible = true
	heal_amount = BASE_HEAL
	heal_pct = 0.0
	target_player = null
	_settling = false
	current_speed = -40.0
	# 等一下满血灰相：回收珠可能带着 waiting 相回池，直接复位（不走 _set_waiting 的同值短路）
	waiting_full_hp = false
	if _sprite != null:
		_sprite.modulate = TINT_READY
	if _loot_renderer != null:
		_loot_renderer.is_waiting = false
	set_physics_process(true)
	if _loot_renderer != null:
		_loot_renderer.set_process(true)   ## 唤醒子渲染器（recycle 时显式休眠的）
	set_deferred("monitoring", true)
	set_deferred("monitorable", true)
	_shape.set_deferred("disabled", false)
	add_to_group("gems")
	_start_bob()

## 回收入池（替代 queue_free）：休眠物理与飘浮动画，退出 gems 组，池满或宿主失效才真释放
func recycle() -> void:
	if _pooled:
		return
	_pooled = true
	active_count = maxi(0, active_count - 1)
	target_player = null
	_settling = false
	if _bob_tween != null and _bob_tween.is_valid():
		_bob_tween.kill()
	remove_from_group("gems")
	set_physics_process(false)
	if _loot_renderer != null:
		_loot_renderer.set_process(false)   ## 子渲染器随本体休眠：set_process 不递归子节点
	_shape.set_deferred("disabled", true)
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	visible = false
	if _host == null or not is_instance_valid(_host) or _pool.size() >= POOL_CAP:
		queue_free()
		return
	_pool.append(self)

## 这一口下去有没有实效：满血（含容差）就是没实效，吃了等于白丢一份治疗
static func heal_is_useful(player: Node2D) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	if not (player is Player):
		return true
	var p := player as Player
	return p.current_health + FULL_HP_EPS < p.max_health

func _physics_process(delta: float) -> void:
	if target_player != null:
		if not is_instance_valid(target_player):
			_end_flight()
			return
		var fp := target_player as Player
		if fp == null:
			_end_flight()
			return
		# 磁吸途中若已回满（且非波末结算），停飞落回原地
		if not _settling and not heal_is_useful(fp):
			_end_flight()
			return
		_fly_to_player(delta)
		return

	# 摄灵圈吸附（若在圈内且未满血直接起飞；满血则转待命灰相）
	if _check_pickup_range():
		return

	# 贴身保底接触
	var touching := _touching_player()
	if touching == null:
		_set_waiting(false)
		return
	if not heal_is_useful(touching):
		_set_waiting(true)
		return
	_set_waiting(false)
	_collect(touching)

## 进拾取圈这一拍：由 Player.PickupArea.area_entered 触发（与灵石同一个口）。
## 若当前满血则不起飞，留在原地等掉血那一拍。
func magnet_to(player: Node2D) -> void:
	if target_player != null or _settling or is_queued_for_deletion():
		return
	if not heal_is_useful(player):
		return
	target_player = player
	current_speed = -50.0
	_begin_flight()

## 每帧复验：人回到圈里 / 圈里满血转残血 —— 这一拍补 area_entered 的单次触发。
func _check_pickup_range() -> bool:
	var p := GameManager.player as Player
	if p == null or not is_instance_valid(p):
		return false
	var radius: float = p.pickup_radius() if p.has_method("pickup_radius") else 96.0
	if global_position.distance_to(p.global_position) > radius:
		return false
	if not heal_is_useful(p):
		_set_waiting(true)
		return true
	magnet_to(p)
	return target_player != null

## 起飞：悬浮交由物理位移接管
func _begin_flight() -> void:
	if _loot_renderer != null:
		_loot_renderer.self_bob = false
		_loot_renderer.position.y = 0.0
	if _bob_tween != null and _bob_tween.is_valid():
		_bob_tween.kill()

## 停飞落回：磁吸被满血闸拦截时用，珠子恢复悬浮等下一拍
func _end_flight() -> void:
	target_player = null
	current_speed = -40.0
	_start_bob()

## 飞向玩家并落袋（磁吸与回合末结算两条路共用）
func _fly_to_player(delta: float) -> void:
	var p := target_player as Player
	if p == null:
		_end_flight()
		return
	var dist := global_position.distance_to(p.global_position)
	var dir: Vector2 = (p.global_position - global_position).normalized()
	current_speed = minf(max_speed, current_speed + acceleration * delta)
	global_position += dir * current_speed * delta
	if dist < ARRIVE_DIST:
		_collect(p)

## 现在压着本珠的玩家身体（没有就 null）。
## 先做 40px 距离平方门控（接触线仅 24px），玩家不在近旁时不调 get_overlapping_bodies()，
## 省掉全场每颗葫芦每物理帧一次 Array 分配与物理空间查询（2026-10-13 优化）。
func _touching_player() -> Player:
	var p := GameManager.player
	if p != null and is_instance_valid(p):
		if global_position.distance_squared_to(p.global_position) > 1600.0:
			return null
	for body in get_overlapping_bodies():
		if body is Player:
			return body as Player
	return null

## 回合末结算：这一路不再等玩家走过来，请进袖中；回不上的那截折金币
func settle_for_wave_end(player: Node2D) -> void:
	if _settling or target_player != null or is_queued_for_deletion() or not (player is Player):
		return
	_set_waiting(false)
	_settling = true
	target_player = player
	current_speed = -50.0
	_begin_flight()

## 落袋：回得上的回血，回不上的溢出折金币 —— 贴身与回合末两条入口共用这一把尺子
func _collect(p: Player) -> void:
	var intended := heal_amount
	if heal_pct > 0.0:
		intended = p.max_health * heal_pct
	var missing := maxf(0.0, p.max_health - p.current_health)
	var landed := minf(intended, missing)
	var overflow := maxf(0.0, intended - landed)

	JuiceEffect.spawn_pickup_pop(get_parent(), global_position, false, Color(0.25, 0.95, 0.55, 0.9))
	if landed > 0.0 and p.has_method("heal"):
		p.heal(landed)
	var stones := GameBalance.heal_overflow_stones(overflow)
	# 灵植夫·灵药滋生：溢出折金币倍率（GameBalance 保持纯函数，角色乘区在调用侧兑现）
	if stones > 0 and GameManager.heal_overflow_mult != 1.0:
		stones = int(round(float(stones) * GameManager.heal_overflow_mult))
		if stones > 0:
			GameManager.add_spirit_stones(stones)
			DamageNumber.spawn(get_parent(), global_position, stones, false, "+%d 金币" % stones)
			AudioManager.play_sfx("gem_pickup", 1.25)
		GameManager.record_wave_heal(landed, stones)
		target_player = null
	recycle()

func _set_waiting(value: bool) -> void:
	# 没变就不回写：接触这一路每帧都跑，重复赋值会把渲染器持续打脏，20Hz 重绘节流白做。
	if waiting_full_hp == value:
		return
	waiting_full_hp = value
	if _sprite != null:
		_sprite.modulate = TINT_WAITING if value else TINT_READY
	if _loot_renderer != null:
		_loot_renderer.is_waiting = value

func _start_bob() -> void:
	if _bob_tween != null and _bob_tween.is_valid():
		_bob_tween.kill()
	# 浮动已交由 ProceduralLootRenderer.self_bob 手写 sin 驱动（对齐 AstralGem），
	# 不再每颗珠子挂一个常驻 set_loops() Tween（2026-10-13 优化）。
	if _loot_renderer != null:
		_loot_renderer.self_bob = true

func _exit_tree() -> void:
	if not _pooled:
		active_count = maxi(0, active_count - 1)
