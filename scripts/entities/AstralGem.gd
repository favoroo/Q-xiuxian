class_name AstralGem
extends Area2D

## 掉落灵石：拾取后转化为经验值。2026-10-10 第 6 波卡顿优化改造：
## 1. 对象池（照 BladeProjectile 模式）——击杀高频 instantiate/queue_free 归零；
## 2. 动态灯名额 GEM_LIGHT_CAP——一场战斗地上可堆积一两百颗，灯数曾随击杀线性上涨，
##    是 Forward+ 2D 光照 pass 的最大成本项；超限灯灭（矢量辉光多边形仍在，视觉不空）；
## 3. 去 set_loops 常驻 Tween——浮动改由 ProceduralLootRenderer._process 手写 sin 驱动；
## 4. 软上限保险丝 GEM_SOFT_CAP——超过后最旧宝石被强制磁吸给玩家，不消失、无经验损失。

const POOL_CAP := 160          ## 池上限：单波同存远小于此值
const GEM_LIGHT_CAP := 8       ## 动态灯名额（与 BladeProjectile.LIGHT_CAP=6 独立计数）
const GEM_SOFT_CAP := 140      ## 场上软上限：超过后强制最旧宝石磁吸给玩家（保险丝）

@export var exp_value: int = 1
@export var is_gold: bool = false:
	set(val):
		is_gold = val
		_update_visual()

var target_player: Node2D = null
var current_speed: float = -40.0   # 初始微反冲：有被吸附瞬间的弹性缓冲
var max_speed: float = 680.0
var acceleration: float = 850.0

@onready var sprite: Sprite2D = $Sprite2D
var loot_renderer: ProceduralLootRenderer = null

# ---------------- 对象池（照 BladeProjectile.gd 模式） ----------------
## activate 契约（出膛方必须逐项设置，缺一会出现「金色蓝灯」类脏状态）：
##   exp_value / is_gold（普宝也要显式置 false）/ global_position，随后调 activate()。
static var _pool: Array[AstralGem] = []
static var _host: Node2D = null                    ## 池宿主，挂场景根下常驻
static var _active_gems: Array[AstralGem] = []     ## 场上活宝石（按出生序），保险丝用
static var created_count: int = 0                  ## 累计实例化次数（PerfProbe 判据）
static var reused_count: int = 0                   ## 累计复用次数（PerfProbe 判据）
static var _lit_count: int = 0                     ## 当前点亮灯数

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
	_host.add_child(ng)
	return ng

## 软上限保险丝：场上宝石数到顶后，每次出膛让最旧的一颗飞向玩家。
## 只触发磁吸不凭空消失，经验一颗不少，只是把「堆到波末」变成「滚进兜里」。
static func _try_release_fuse() -> void:
	if _active_gems.size() < GEM_SOFT_CAP:
		return
	for g in _active_gems:
		if is_instance_valid(g) and not g._pooled and g.target_player == null \
				and GameManager.player != null:
			g.magnet_to(GameManager.player)
			return

func activate() -> void:
	_pooled = false
	visible = true
	target_player = null
	current_speed = -40.0
	set_physics_process(false)   ## 静置宝石不跑物理；magnet_to 时再开
	$CollisionShape2D.set_deferred("disabled", false)
	set_deferred("monitorable", true)
	add_to_group("gems")
	if not _active_gems.has(self):
		_active_gems.append(self)
	_update_visual()
	_try_acquire_light()

func recycle() -> void:
	if _pooled:
		return
	_pooled = true
	target_player = null
	_release_light()
	_active_gems.erase(self)
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
		light.visible = true
		return
	if _lit_count < GEM_LIGHT_CAP:
		_lit_count += 1
		_has_light = true
		light.visible = true
	else:
		light.visible = false

func _release_light() -> void:
	if _has_light:
		_lit_count = maxi(0, _lit_count - 1)
		_has_light = false
	var light := get_node_or_null("PointLight2D") as PointLight2D
	if light != null:
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
		loot_renderer.loot_type = ProceduralLootRenderer.LootType.GEM_GOLD if is_gold else ProceduralLootRenderer.LootType.GEM_BLUE
	var light = get_node_or_null("PointLight2D") as PointLight2D
	if light != null:
		light.color = Color(1.0, 0.85, 0.35) if is_gold else Color(0.4, 0.8, 1.0)

func magnet_to(player: Node2D) -> void:
	if target_player == null:
		target_player = player
		current_speed = -50.0
		set_physics_process(true)

func _physics_process(delta: float) -> void:
	if target_player == null or not is_instance_valid(target_player):
		set_physics_process(false)
		return
	var dir = (target_player.global_position - global_position).normalized()
	var dist = global_position.distance_to(target_player.global_position)
	current_speed = minf(max_speed, current_speed + acceleration * delta)
	global_position += dir * current_speed * delta

	if dist < 22.0:
		JuiceEffect.spawn_pickup_pop(get_parent(), global_position, is_gold)
		if target_player.has_method("play_squash"):
			target_player.play_squash(Vector2(0.96, 1.05), 0.12)
		GameManager.add_experience(exp_value)
		recycle()
