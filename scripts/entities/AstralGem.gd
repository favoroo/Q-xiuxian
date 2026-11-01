class_name AstralGem
extends Area2D

## 掉落金币：拾取后转化为经验值。2026-10-10 第 6 波卡顿优化改造：
## 1. 对象池（照 BladeProjectile 模式）——击杀高频 instantiate/queue_free 归零；
## 2. 动态灯名额 GEM_LIGHT_CAP——一场战斗地上可堆积一两百颗，灯数曾随击杀线性上涨，
##    是 Forward+ 2D 光照 pass 的最大成本项；超限灯灭（矢量辉光多边形仍在，视觉不空）；
## 3. 去 set_loops 常驻 Tween——浮动改由 ProceduralLootRenderer._process 手写 sin 驱动；
## 4. 软上限保险丝 GEM_SOFT_CAP——超过后最旧宝石被强制磁吸给玩家，不消失、无经验损失。
##
## 2026-11-01 车道 G（pixelfx 序列帧接入，只加演出不改掉落/数值）：
## - 拾取瞬间在入体点炸一张 collect_burst（高频灵珠靠 FxFlipbookPool 的 5/帧闸与 16px 重叠去重
##   自动限流，一波百颗齐吸也只放行稀疏几处）；
## - 金宝（is_gold 且经验 ≥ ELITE_GEM_EXP：精英/Boss 那档）额外立一根循环 loot_beam 光柱当
##   「此处有宝」的读点。loop 动画不会自回收，句柄由宝石自己持有、recycle/_exit_tree 显式归还
##   （照 BeamRenderer 口径）；开匣那捧金灵石虽是 is_gold，但同帧 3~6 颗不上光柱（不抢战斗演出池位）。

const POOL_CAP := 160          ## 池上限：单回合同存远小于此值
const GEM_LIGHT_CAP := 5       ## 动态灯名额（与 BladeProjectile.LIGHT_CAP=6 独立计数）
const GEM_SOFT_CAP := 140      ## 场上软上限：超过后强制最旧宝石磁吸给玩家（保险丝）
## 稀有金宝的「此处有宝」光柱：loop 序列帧，不自回收，句柄由宝石本体持有。
## 只立 LOOT_BEAM_HOLD 秒就收 —— 宝石能在地上躺一整个回合，常驻光柱会把 16 个池位吃光，
## 反过来卡住武器束流/火锥这些同样吃池的循环特效（限流优先级：战斗演出 > 掉落装饰）。
const LOOT_BEAM_HOLD := 1.0

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
var _beam_fx: AnimatedSprite2D = null   ## 金宝光柱句柄（loop 帧，不自回收，回收时显式归还）
var _beam_hold: float = 0.0             ## 光柱剩余驻留秒数（走本体的 _process，不另起 Tween）
var _beam_pending: bool = false         ## deferred 入场待补光柱（物理回调里掉出的金宝）

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
	if loot_renderer != null:
		loot_renderer.set_process(true)   ## 唤醒子渲染器（recycle 时显式休眠的）
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
	_spawn_beam()

func recycle() -> void:
	if _pooled:
		return
	_pooled = true
	target_player = null
	_pop_time = 0.0
	_pop_vel = Vector2.ZERO
	_stop_beam()   ## 循环帧必须显式归还池，否则句柄随池复用一路占位（照 BeamRenderer._stop_fx）
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
	# 子渲染器随本体休眠：set_process 不递归子节点、visible=false 也不停子节点 _process，
	# 不显式关的话池里上百颗宝石的渲染器每渲染帧照跑 sin 浮动与屏外剔除换算
	if loot_renderer != null:
		loot_renderer.set_process(false)
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
	# 定义 _process 会让引擎自动开进程：没有金宝光柱的宝石（绝大多数）必须显式关掉，
	# 否则池里上百颗休眠宝石每渲染帧空跑一次。光柱已在 deferred 入场那一拍立起来的就别关。
	if _beam_hold <= 0.0:
		set_process(false)
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

# ---------------- 金宝光柱（pixelfx loot_beam，loop 帧） ----------------
## 只给「大灵石」立柱：is_gold 且单颗经验 ≥ ELITE_GEM_EXP（精英/Boss 那档）。
## 为什么不按 is_gold 一律立：开一口匣子同帧掉 3~6 颗金灵石，每颗一根光是同屏 6 根柱子；
## 而 loop 帧不自回收、16 个池位还要留给武器束流/火锥，掉落装饰不许抢战斗演出的名额。
## 碎金档（is_shard）与普通灵珠同理不上光柱 —— 它们是全场最高频物件。
func _spawn_beam() -> void:
	_stop_beam()
	if not is_gold or exp_value < GameBalance.ELITE_GEM_EXP:
		return
	if not is_inside_tree():
		# 首建这一路在物理回调里走的是 deferred 入场（见 acquire_or_new）：activate() 当拍
		# 还不在树内，FxFlipbookPool.play 的 global_position 落点与池挂载都无从谈起。
		# 而金宝恰恰全是 _die / _destroy 的物理回调里掉的，所以挂进树的那一帧再补光柱。
		_beam_pending = true
		return
	# pixelfx 接入点（回退：注释下一行）
	# anchor=bottom ⇒ 帧底对齐宝石落点；follow 由池每帧跟随本体位置（宝石被磁吸前原地不动）。
	_beam_fx = FxFlipbookPool.play(&"loot_beam", global_position, {"follow": self})
	if _beam_fx == null:
		return
	# 限流挡下（同帧池满/帧预算用尽）时保持 null，不重试：光柱是装饰，宝石本体照常可见
	_beam_hold = LOOT_BEAM_HOLD
	set_process(true)

## 归还循环帧句柄：loop 动画不自回收，不显式 stop 会一直占池位（照 BeamRenderer._stop_fx）。
## 陷阱：池满时 _spawn 会抢最老的活跃项（POOL_CAP+4 之后），这根光柱可能已被借给别的特效 ——
## 只有句柄仍挂着「跟随我」这条 meta 才归还，否则一律不动它（别人的演出不能替人 stop）。
func _stop_beam() -> void:
	_beam_pending = false
	if _beam_fx != null and is_instance_valid(_beam_fx) \
			and _beam_fx.has_meta("follow_target") and _beam_fx.get_meta("follow_target") == self:
		FxFlipbookPool.stop(_beam_fx)
	_beam_fx = null
	_beam_hold = 0.0
	# 光柱是本体唯一的 _process 用途：没有光柱就把 process 关掉，
	# 池里上百颗休眠宝石不许每渲染帧空跑一次 delta 递减（与 loot_renderer 同口径的休眠纪律）
	set_process(false)

## deferred 入场那一帧补光柱（金宝从物理回调掉出时走这条）
func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE and _beam_pending:
		_beam_pending = false
		_spawn_beam()

func _process(delta: float) -> void:
	if _beam_hold <= 0.0:
		return
	_beam_hold -= delta
	# 被池按上限收回（visible=false 且 meta 已摘）→ 句柄已不归我，直接收摊别再碰它
	if _beam_hold <= 0.0 or _beam_fx == null or not is_instance_valid(_beam_fx) or not _beam_fx.visible:
		_stop_beam()

func magnet_to(player: Node2D) -> void:
	if target_player == null:
		target_player = player
		current_speed = -50.0
		# 起飞就把光柱收掉：宝石飞向玩家时光柱钉在原地读起来像「凭空一根柱子」
		_stop_beam()
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
		# pixelfx 接入点（回退：注释下一行）
		# 入体点炸一张 collect_burst（scale_mult 0.8 让帧光比宝石本体略大一圈，读「吸进去」）。
		# 一波百颗同帧齐吸时由 FxFlipbookPool 的 5/帧闸 + 16px 重叠去重自动稀疏化，
		# 这里不做额外计数；限流挡下返回 null 也不影响下面经验入账。
		FxFlipbookPool.play(&"collect_burst", global_position, {"scale_mult": 0.8})
		JuiceEffect.spawn_pickup_pop(get_parent(), global_position, is_gold)
		if target_player.has_method("play_squash"):
			# 碎晶轻一档的 squash，给最低档一个更小的入口反馈
			_player_squash(target_player)
		GameManager.add_experience(exp_value, stone_value)
		recycle()

func _exit_tree() -> void:
	_stop_beam()   ## 场景销毁/池满真释放时也得把循环帧还回去
	if _trail_line != null and is_instance_valid(_trail_line):
		_trail_line.queue_free()
		_trail_line = null

func _player_squash(player: Node2D) -> void:
	if is_shard:
		player.play_squash(Vector2(0.98, 1.03), 0.09)
	else:
		player.play_squash(Vector2(0.96, 1.05), 0.12)
