class_name AstralGem
extends Area2D

## 掉落金币：拾取后转化为经验值。2026-10-10 第 6 波卡顿优化改造：
## 1. 对象池（照 BladeProjectile 模式）——击杀高频 instantiate/queue_free 归零；
## 2. 动态灯名额 GEM_LIGHT_CAP——一场战斗地上可堆积一两百颗，灯数曾随击杀线性上涨，
##    是 Forward+ 2D 光照 pass 的最大成本项；超限灯灭（矢量辉光多边形仍在，视觉不空）；
## 3. 去 set_loops 常驻 Tween——浮动改由 ProceduralLootRenderer._process 手写 sin 驱动；
## 4. 软上限保险丝 GEM_SOFT_CAP——超过后最旧宝石被强制磁吸给玩家，不消失、无经验损失。

const POOL_CAP := 160          ## 池上限：单回合同存远小于此值
const GEM_LIGHT_CAP := 5       ## 动态灯名额（与 BladeProjectile.LIGHT_CAP=6 独立计数）
const GEM_SOFT_CAP := 140      ## 场上软上限：超过后强制最旧宝石磁吸给玩家（保险丝）

@export var exp_value: int = 1
## 金币腿入账值：-1 = 与 exp_value 同值（普通金币原口径）；>=0 = 按此值入账。
## 碎晶档专用：经验足额、金币折低（见 BalanceEconomy 碎晶段）。
@export var stone_value: int = -1
@export var is_gold: bool = false:
	set(val):
		is_gold = val
		_update_visual()
## 碎金档：高频掉落的基础碎金/金砂片（暖金色、不规则小金片）。与 is_gold 互斥，金档优先。
@export var is_shard: bool = false:
	set(val):
		is_shard = val
		_update_visual()

var target_player: Node2D = null
var current_speed: float = -40.0   # 初始微反冲：有被吸附瞬间的弹性缓冲
var max_speed: float = 680.0
var acceleration: float = 850.0

var _pop_time: float = 0.0
var _pop_vel: Vector2 = Vector2.ZERO
var _trail_line: Line2D = null

@onready var sprite: Sprite2D = $Sprite2D
var loot_renderer: ProceduralLootRenderer = null

# ---------------- 对象池（照 BladeProjectile.gd 模式） ----------------
## activate 契约（出膛方必须逐项设置，缺一会出现「金色蓝灯」类脏状态）：
##   exp_value / stone_value（非碎晶置回 -1）/ global_position，随后调 activate()。
##   is_gold / is_shard 允许沿用场景默认——recycle() 入池即复位三态，
##   但新档出现时仍建议显式设（照 SpiritChest._drop_gems 的金宝口径）。
static var _pool: Array[AstralGem] = []
static var _host: Node2D = null                    ## 池宿主，挂场景根下常驻
# 2026-10-17 性能专项：由 Array 改 Dictionary（instance_id → 宝石）。
# 根因：140 颗同帧掉落的波末，activate 的 has() 与 recycle 的 erase() 各 O(n) 线性扫，
# 叠加 _try_release_fuse 找最旧颗也是线性扫 ⇒ 140×140/2 ≈ 9.8k 次比较的尖峰。
# Dictionary 保插入序（Godot 4 有序哈希表），「最旧优先」语义不变；keys()/values() 遍历兼容旧测试。
static var _active_gems: Dictionary = {}           ## 场上活宝石（id→实例，按出生序），保险丝用
static var created_count: int = 0                  ## 累计实例化次数（PerfProbe 判据）
static var reused_count: int = 0                   ## 累计复用次数（PerfProbe 判据）
static var _lit_count: int = 0                     ## 当前点亮灯数

## 场上活宝石数（HUD 性能面板消费）
static func active_gem_count() -> int:
	return _active_gems.size()

static func clear_pool() -> void:
	_pool.clear()
	_active_gems.clear()
	_lit_count = 0
	_host = null

var _pooled: bool = false
var _has_light: bool = false

static func _ensure_host(parent: Node) -> void:
	if _host != null and is_instance_valid(_host):
		return
	# 宿主随旧场景销毁过：清空全部静态引用与灯计数
	_pool.clear()
	_active_gems.clear()
	_lit_count = 0
	_host = Node2D.new()
	_host.name = "AstralGemPool"
	parent.add_child(_host)

## 从池取或新建。parent 传场景根（照 BladeProjectile 口径）；
## 新实例同步入宿主（_ready 即跑完），出膛方设完字段直接 activate()。
static func acquire_or_new(scene: PackedScene, parent: Node) -> AstralGem:
	_ensure_host(parent)
	_try_release_fuse()
	while not _pool.is_empty():
		var g: AstralGem = _pool.pop_back()
		if is_instance_valid(g):
			reused_count += 1
			return g
	var ng := scene.instantiate() as AstralGem
	created_count += 1
	# 首建这一路可能在物理回调里（EnemyBase._die 掉宝石）：场景自带 CollisionShape2D，
	# 正在 flush queries 时挂进树会报 "Can't change this state while flushing queries"
	# 且当拍判定不生效 ⇒ 物理步里改 deferred 入场（调用方紧接着写 global_position /
	# activate() 都不依赖已在树内：宿主与场景根都在原点，位置照旧）。
	if Engine.is_in_physics_frame():
		_host.add_child.call_deferred(ng)
	else:
		_host.add_child(ng)
	return ng

## 软上限保险丝：场上宝石数到顶后，每次出膛让最旧的一颗飞向玩家。
## 只触发磁吸不凭空消失，经验一颗不少，只是把「堆到回合末」变成「滚进兜里」。
## Dictionary 保插入序：keys() 头部即最旧颗，通常首击即中，不再线性扫全表找候选。
## 2026-10-24 修正：原先 for g in _active_gems.values() —— values() 每次调用整表拷贝一个
## Array（140 颗在场时每次掉落多一份 140 引用的分配）；改为沿 key 插入序零拷贝迭代取值，
## 「取最旧」语义与注释承诺对齐。
static func _try_release_fuse() -> void:
	if _active_gems.size() < GEM_SOFT_CAP:
		return
	for key in _active_gems:
		var g: AstralGem = _active_gems[key]
		if is_instance_valid(g) and not g._pooled and g.target_player == null \
				and GameManager.player != null:
			g.magnet_to(GameManager.player)
			return

func activate() -> void:
	_pooled = false
	# 池化复用是从回收点瞬移到掉落点：不重置物理插值，真机帧率抖动时首帧会渲染旧位置滑行
	reset_physics_interpolation()
	visible = true
	target_player = null
	current_speed = -40.0
	_pop_time = 0.0
	_pop_vel = Vector2.ZERO
	if _trail_line != null:
		_trail_line.clear_points()
		_trail_line.visible = false
	
	# 精英/Boss金宝抛物微跳演出（T-1.3）：0.2s 随机向外溅跃
	if is_gold and GameManager.rng != null:
		_pop_time = 0.2
		var angle := GameManager.rng.randf_range(0.0, TAU)
		var spd := GameManager.rng.randf_range(90.0, 150.0)
		_pop_vel = Vector2(cos(angle), sin(angle)) * spd
		set_physics_process(true)
	else:
		set_physics_process(false)   ## 静置宝石不跑物理；magnet_to 时再开

	$CollisionShape2D.set_deferred("disabled", false)
	set_deferred("monitorable", true)
	add_to_group("gems")
	_active_gems[get_instance_id()] = self
	_update_visual()
	_try_acquire_light()

func recycle() -> void:
	if _pooled:
		return
	_pooled = true
	target_player = null
	_pop_time = 0.0
	_pop_vel = Vector2.ZERO
	if _trail_line != null:
		_trail_line.clear_points()
		_trail_line.visible = false
	# 入池先清档色：池里的实例不许带着上一颗的金/碎晶状态见下一个调用方
	is_gold = false
	is_shard = false
	stone_value = -1
	_release_light()
	_active_gems.erase(get_instance_id())
	remove_from_group("gems")
	set_physics_process(false)
	$CollisionShape2D.set_deferred("disabled", true)
	set_deferred("monitorable", false)
	visible = false
	if _pool.size() >= POOL_CAP:
		queue_free()
		return
	_pool.append(self)

# ---------------- 灯名额（照 BladeProjectile._try_acquire_light 模式） ----------------
func _try_acquire_light() -> void:
	var light := get_node_or_null("PointLight2D") as PointLight2D
	if light == null:
		return
	if _has_light:
		light.enabled = true
		light.visible = true
		return
	# 灯名额走 FxBudget 拥挤档（2026-10-17）：高压战斗掉落灯减半让位带宽，敌潮退去回满
	if _lit_count < FxBudget.gem_light_cap():
		_lit_count += 1
		_has_light = true
		light.enabled = true
		light.visible = true
	else:
		light.enabled = false
		light.visible = false

func _release_light() -> void:
	if _has_light:
		_lit_count = maxi(0, _lit_count - 1)
		_has_light = false
	var light := get_node_or_null("PointLight2D") as PointLight2D
	if light != null:
		light.enabled = false
		light.visible = false

func _ready() -> void:
	add_to_group("gems")
	if sprite != null:
		sprite.visible = false
	if loot_renderer == null:
		loot_renderer = ProceduralLootRenderer.new()
		add_child(loot_renderer)
	loot_renderer.self_bob = true   ## 浮动由渲染器 _process 手写 sin 驱动，不再用常驻 Tween
	set_physics_process(false)      ## 静置宝石不跑物理；magnet_to 时再开
	_update_visual()
	_try_acquire_light()

func _update_visual() -> void:
	if loot_renderer != null:
		if is_gold:
			loot_renderer.loot_type = ProceduralLootRenderer.LootType.GEM_GOLD
		elif is_shard:
			loot_renderer.loot_type = ProceduralLootRenderer.LootType.GEM_SHARD
		else:
			loot_renderer.loot_type = ProceduralLootRenderer.LootType.GEM_BLUE
		var light = get_node_or_null("PointLight2D") as PointLight2D
		if light != null:
			# 碎金档：暖金细芒、亮度压低一档，与精英耀金大光区别开
			if is_gold:
				light.color = Color(1.0, 0.85, 0.35)
			elif is_shard:
				light.color = Color(0.95, 0.80, 0.35)
			else:
				light.color = Color(0.4, 0.8, 1.0)

func _ensure_trail() -> void:
	if _trail_line != null and is_instance_valid(_trail_line):
		return
	_trail_line = Line2D.new()
	_trail_line.top_level = true
	_trail_line.width = 2.4
	_trail_line.default_color = GameStyle.FX_HDR_GOLD
	_trail_line.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_trail_line.visible = false
	add_child(_trail_line)

func magnet_to(player: Node2D) -> void:
	if target_player == null:
		target_player = player
		current_speed = -50.0
		_ensure_trail()
		if _trail_line != null:
			_trail_line.default_color = GameStyle.FX_HDR_GOLD if is_gold else GameStyle.FX_HDR_WATER
			_trail_line.clear_points()
			_trail_line.visible = true
		set_physics_process(true)

func _physics_process(delta: float) -> void:
	if _pop_time > 0.0:
		_pop_time -= delta
		global_position += _pop_vel * delta
		_pop_vel = _pop_vel.move_toward(Vector2.ZERO, 600.0 * delta)
		if _pop_time <= 0.0 and target_player == null:
			set_physics_process(false)
			return

	if target_player == null or not is_instance_valid(target_player):
		if _pop_time <= 0.0:
			set_physics_process(false)
		return

	var dir = (target_player.global_position - global_position).normalized()
	var dist = global_position.distance_to(target_player.global_position)
	current_speed = minf(max_speed, current_speed + acceleration * delta)
	global_position += dir * current_speed * delta

	if _trail_line != null and _trail_line.visible:
		_trail_line.add_point(global_position)
		if _trail_line.get_point_count() > 5:
			_trail_line.remove_point(0)

	if dist < 22.0:
		if _trail_line != null:
			_trail_line.clear_points()
			_trail_line.visible = false
		JuiceEffect.spawn_pickup_pop(get_parent(), global_position, is_gold)
		if target_player.has_method("play_squash"):
			# 碎晶轻一档的 squash，给最低档一个更小的入口反馈
			_player_squash(target_player)
		GameManager.add_experience(exp_value, stone_value)
		recycle()

func _exit_tree() -> void:
	if _trail_line != null and is_instance_valid(_trail_line):
		_trail_line.queue_free()
		_trail_line = null

func _player_squash(player: Node2D) -> void:
	if is_shard:
		player.play_squash(Vector2(0.98, 1.03), 0.09)
	else:
		player.play_squash(Vector2(0.96, 1.05), 0.12)
