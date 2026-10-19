class_name EnemyBolt
extends Area2D

## 敌方火球：御剑邪修周期直射、魔君环弹齐射共用这一颗。纯代码构建，无需场景文件。
##
## 视觉口径（2026-10-08 用户指令：「这个火球怎么这么大呀，而且还有这种透明的效果、
## 虚化的效果。不要这种效果，就实际的，它的攻击范围是多大就显示多大」）：
## 	**画出来的圆 == 判定圆**。直径严格等于 2 × radius，不叠 additive 辉光、
## 	不留半透明外焰、不做脉动缩放。
## 	旧写法把 128px 的 light_radial 当「外焰」（additive + alpha 0.7）套在
## 	0.55 倍的橙红核心外面，视觉上糊开约 70~100px，而判定半径只有 8px ——
## 	玩家看到的威胁范围是真实范围的 4~8 倍（比施法者本人还大一圈），只能凭感觉躲。
## 	同口径的既有先例：Boss 震地预警圈（AoeTelegraph 按判定半径画圈，填满即结算）、
## 	玩家武器弹丸（BladeProjectile 判定半径 7，刃的可见长度也就这个量级）。
## 	⇒ 要改火球大小只动 RADIUS 一个常数，外观与碰撞一起变，不许分开设。

const RADIUS := 8.0                  ## 基准判定半径（不含 scale_factor）：外观与碰撞的唯一来源
const BODY_COLOR := Color(1.0, 0.45, 0.12)   ## 球体（烈焰橙）
const CORE_COLOR := Color(1.0, 0.87, 0.45)   ## 高光芯
const RIM_COLOR := Color(0.42, 0.07, 0.04)   ## 硬描边，压在判定圆内侧
const OUTLINE_COLOR := Color(1.0, 0.88, 0.60, 0.70)  ## 浅色细描边（暖金微光，反差勾勒）

const BODY_COLOR_PURPLE := Color(0.72, 0.28, 1.0)   ## 魔尊/子母弹球体（幽紫魔焰）
const CORE_COLOR_PURPLE := Color(0.94, 0.78, 1.0)   ## 幽紫高光芯
const RIM_COLOR_PURPLE := Color(0.24, 0.05, 0.38)   ## 幽紫硬描边
const OUTLINE_COLOR_PURPLE := Color(0.92, 0.75, 1.0, 0.70) ## 幽紫浅色细描边（冷紫高光）

# 幽冥剑气配色（御剑邪修专属：冷冽幽蓝梭形剑芒）
const BODY_COLOR_SWORD := Color(0.20, 0.75, 1.0)       ## 幽蓝剑气身
const CORE_COLOR_SWORD := Color(0.90, 0.98, 1.0)       ## 极亮纯白霜雪剑芯
const RIM_COLOR_SWORD := Color(0.06, 0.15, 0.35)       ## 深蓝锐利描边
const OUTLINE_COLOR_SWORD := Color(0.75, 0.92, 1.0, 0.75)   ## 霜雪浅蓝细描边

# 剑煞血光配色（剑煞邪修精英专属：血煞剑芒）
const BODY_COLOR_JIANSHA := Color(0.85, 0.25, 0.50)    ## 血煞剑气身
const CORE_COLOR_JIANSHA := Color(1.0, 0.90, 0.95)     ## 绯红亮芯
const RIM_COLOR_JIANSHA := Color(0.35, 0.05, 0.18)     ## 暗红描边
const OUTLINE_COLOR_JIANSHA := Color(1.0, 0.75, 0.85, 0.75) ## 绯粉细描边

# —— 对象池（2026-10-11，照 AstralGem/BladeProjectile 模式）——
## 御剑邪修周期直射 + 魔君环弹/螺旋/子母弹每次 new()+queue_free，Area2D + 碰撞体
## 全套生命周期分配是回合卡顿源。死亡/到期回池休眠，activate() 全量重置。
## 兼容约定：裸 new() + add_child 的旧路径（预览/单测）保持原行为不受影响。
const POOL_CAP := 160
const BASE_LIFETIME := 3.0   ## 场景默认寿命：activate 复用时重置的基准
static var _pool: Array[EnemyBolt] = []
static var _host: Node2D = null
static var created_count: int = 0    ## 累计 instantiate 数（PoolCheck 断言用）
static var reused_count: int = 0     ## 累计池复用数
static var active_count: int = 0     ## 当前在场（已激活未回收）火球数：HUD 性能面板消费
static var interp_reset_count: int = 0  ## 累计插值重置次数（PoolCheck 断言 activate 重置了物理插值用）

static func clear_pool() -> void:
	_pool.clear()
	active_count = 0
	_host = null

static func _ensure_host(parent: Node) -> void:
	if _host != null and is_instance_valid(_host):
		return
	_pool.clear()   # 旧宿主已失效，残留池引用一并作废
	_host = Node2D.new()
	_host.name = "EnemyBoltPool"
	parent.add_child(_host)

## 取一颗火球（优先复用）：发射方在调用后写 global_position/direction/speed/damage/scale_factor，
## 最后调 activate() 出膛
static func acquire(parent: Node) -> EnemyBolt:
	_ensure_host(parent)
	while not _pool.is_empty():
		var b: EnemyBolt = _pool.pop_back()
		if is_instance_valid(b):
			reused_count += 1
			b._reset_defaults()
			return b
	var nb := EnemyBolt.new()
	created_count += 1
	_host.add_child(nb)
	return nb

var direction: Vector2 = Vector2.RIGHT
var speed: float = 300.0
var damage: float = 6.0
var lifetime: float = 3.0
var scale_factor: float = 1.0  ## 整体缩放（Boss 环弹/母弹比普通火球大），外观与碰撞一起缩
var radius: float = RADIUS     ## 实际判定半径 = RADIUS × scale_factor，_ready / activate 里更新

## 进阶弹幕运动与分裂属性（2026-10-13 Boss 招式重做扩展）
var angular_speed: float = 0.0   ## 弧线/螺旋偏转角速度（rad/s，正顺时针、负逆时针）
var accel: float = 0.0           ## 变速推进加速度（px/s²）
var min_speed: float = 60.0      ## 减速下限，防弹丸停滞
var split_timer: float = -1.0    ## >0 时启用子母弹倒计时，归零时原地分裂为子火球
var split_count: int = 0         ## 子母弹分裂颗数
var split_speed: float = 275.0   ## 子火球飞行速度
var split_scale: float = 1.0     ## 子火球缩放系数
var split_damage: float = 0.0    ## 子火球伤害（≤0 时按母弹 65% 折算）
var purple_style: bool = false   ## 幽紫魔焰配色（第 20 波最终 Boss 及子母弹专属）
var sword_style: bool = false    ## 幽冥剑气形态（御剑邪修专属：冷冽幽蓝梭形剑芒）

## 池状态与 _ready 建好的节点引用（复用时 activate 重铺要用）
var _pooled: bool = false
var _shape_node: CollisionShape2D = null
var _circle: CircleShape2D = null
## 世界坐标拖尾（2026-10-19）：仅剑气/Boss 大弹启用，普通火球不挂（守同屏图元预算）
var _trail: EnemyBoltTrail = null

func _reset_defaults() -> void:
	direction = Vector2.RIGHT
	rotation = 0.0
	speed = 300.0
	damage = 6.0
	scale_factor = 1.0
	angular_speed = 0.0
	accel = 0.0
	min_speed = 60.0
	split_timer = -1.0
	split_count = 0
	split_speed = 275.0
	split_scale = 1.0
	split_damage = 0.0
	purple_style = false
	sword_style = false

func _ready() -> void:
	add_to_group("enemy_bolts")
	collision_layer = 0
	collision_mask = 2  # player
	# 火球不旋转，剑气沿发射方向定向
	rotation = direction.angle() if sword_style else 0.0
	# scale_factor 由发射方在 add_child 之前写入，所以这里算一次就是终值
	radius = RADIUS * maxf(scale_factor, 0.05)

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	add_child(shape)
	_shape_node = shape
	_circle = circle

	body_entered.connect(_on_body_entered)

## 当前弹体是否值得挂拖尾：拥挤档一律不挂；剑气/Boss 大弹才挂
func _trail_enabled() -> bool:
	if FxBudget.crowded:
		return false
	return sword_style or scale_factor > 1.2

## 拖尾按需懒建（只在需要时挂一次，池化复用不再重建）。
## 不在 _ready 建：普通火球（占绝大多数）永不创建，既守「画多大判多大」的子节点铁律
## （判定圆之外不长任何视觉节点），也省内存。
func _ensure_trail() -> EnemyBoltTrail:
	if _trail == null or not is_instance_valid(_trail):
		_trail = EnemyBoltTrail.new()
		add_child(_trail)
	return _trail

## 弹体描边色（拖尾同源取色，读得出「这是什么弹」）
func _rim_color() -> Color:
	if sword_style:
		return RIM_COLOR_JIANSHA if purple_style else RIM_COLOR_SWORD
	if purple_style:
		return RIM_COLOR_PURPLE
	return RIM_COLOR

## 浅色细描边色（外沿高光反差轮廓）
func _outline_color() -> Color:
	if sword_style:
		return OUTLINE_COLOR_JIANSHA if purple_style else OUTLINE_COLOR_SWORD
	if purple_style:
		return OUTLINE_COLOR_PURPLE
	return OUTLINE_COLOR

## 出膛激活：池化后 _ready 只在首建时跑过，所有依赖字段的视觉与物理状态
## 必须在这里按当前字段值重铺。重置清单（改字段签名时对照这里）：
##   direction/speed/damage/lifetime/scale_factor ⇒ radius/碰撞圆/寿命
func activate() -> void:
	_pooled = false
	active_count += 1
	# 池化复用是从回收点瞬移到出膛点：不重置物理插值，真机帧率抖动时首帧会渲染旧位置滑行
	reset_physics_interpolation()
	interp_reset_count += 1
	visible = true
	rotation = direction.angle() if sword_style else 0.0
	radius = RADIUS * maxf(scale_factor, 0.05)
	if _circle != null:
		_circle.radius = radius
		queue_redraw()
	lifetime = BASE_LIFETIME
	set_physics_process(true)
	# 碰撞恢复必须走 deferred：同一帧「回收→复用」时，回收的 disabled=true deferred
	# 会在帧末 flush，直接赋值的 false 会被它覆盖（照 BladeProjectile.activate 同一条坑）
	set_deferred("monitoring", true)
	_shape_node.set_deferred("disabled", false)

	# 拖尾按当前形态决定挂不挂；挂上则清史从出膛点起笔
	if _trail_enabled():
		var tr := _ensure_trail()
		tr.configure(_rim_color())
		tr.set_active(true)
		tr.seed(global_position)
	elif _trail != null:
		_trail.set_active(false)

## 被友方/防御灵兽拦截：立刻回收入池（产生湮灭灵光碎屑，平滑消散）
func intercept() -> void:
	if _pooled:
		return
	var rim_c := RIM_COLOR
	if sword_style:
		rim_c = RIM_COLOR_JIANSHA if purple_style else RIM_COLOR_SWORD
	elif purple_style:
		rim_c = RIM_COLOR_PURPLE
	if is_inside_tree() and get_parent() != null:
		JuiceEffect.spawn_impact_pop(get_parent(), global_position, rim_c, direction)
	_recycle()

## 子母弹到期分裂：母弹先回池腾位，再在原地呈环形散射出 split_count 颗高速子火球
func _explode_split() -> void:
	if _pooled:
		return
	var host_parent := get_parent()
	var cur_pos := global_position
	var count := split_count
	var child_spd := split_speed
	var child_scl := split_scale
	var child_dmg := split_damage if split_damage > 0.0 else maxf(1.0, damage * 0.65)
	var is_purple := purple_style
	var rim_c := RIM_COLOR_PURPLE if is_purple else RIM_COLOR
	if is_inside_tree() and host_parent != null:
		JuiceEffect.spawn_impact_pop(host_parent, cur_pos, rim_c, direction)
	AudioManager.play_sfx("enemy_bolt", 0.75, 1.18)
	_recycle()
	if host_parent == null or not is_instance_valid(host_parent) or count <= 0:
		return
	for i in range(count):
		var ang := TAU * float(i) / float(count)
		var child_bolt := EnemyBolt.acquire(host_parent)
		child_bolt.global_position = cur_pos
		child_bolt.direction = Vector2(cos(ang), sin(ang))
		child_bolt.speed = child_spd
		child_bolt.damage = child_dmg
		child_bolt.scale_factor = child_scl
		child_bolt.purple_style = is_purple
		child_bolt.activate()

## 回收入池（替代 queue_free）：休眠物理与碰撞，池满或宿主失效才真释放
func _recycle() -> void:
	if _pooled:
		return
	_pooled = true
	active_count = maxi(0, active_count - 1)
	set_physics_process(false)
	set_deferred("monitoring", false)
	_shape_node.set_deferred("disabled", true)
	visible = false
	if _trail != null:
		_trail.set_active(false)
	_reset_defaults()
	if _host == null or not is_instance_valid(_host) or _pool.size() >= POOL_CAP:
		queue_free()
		return
	_pool.append(self)

func _draw() -> void:
	if sword_style:
		_draw_sword_bolt()
		return
	var body_c := BODY_COLOR_PURPLE if purple_style else BODY_COLOR
	var rim_c := RIM_COLOR_PURPLE if purple_style else RIM_COLOR
	var outline_c := OUTLINE_COLOR_PURPLE if purple_style else OUTLINE_COLOR
	var core_c := CORE_COLOR_PURPLE if purple_style else CORE_COLOR
	# 绘制口径：画多大判多大（半径严格在 radius 之内）
	# 1. 弹体球身
	draw_circle(Vector2.ZERO, radius, body_c)
	# 2. 内层暗色硬描边（线宽 1.4，内压立体感）
	draw_arc(Vector2.ZERO, maxf(radius - 1.2, 1.0), 0.0, TAU, 24, rim_c, 1.4, true)
	# 3. 最外层细浅描边（线宽 1.0，外沿严格吻合 radius 判定圆，暗调地表上高反差勾边）
	draw_arc(Vector2.ZERO, maxf(radius - 0.5, 0.5), 0.0, TAU, 24, outline_c, 1.0, true)
	# 4. 高光芯
	draw_circle(Vector2.ZERO, radius * 0.45, core_c)

## 幽冥剑气视觉绘制（几何尺寸严格内切判定圆 radius，铁律 7：画多大判多大）
func _draw_sword_bolt() -> void:
	var body_c := BODY_COLOR_JIANSHA if purple_style else BODY_COLOR_SWORD
	var rim_c := RIM_COLOR_JIANSHA if purple_style else RIM_COLOR_SWORD
	var outline_c := OUTLINE_COLOR_JIANSHA if purple_style else OUTLINE_COLOR_SWORD
	var core_c := CORE_COLOR_JIANSHA if purple_style else CORE_COLOR_SWORD

	var r := radius
	# 锐利剑梭多边形（前尖达到 r，侧刃向后收束）
	var pts := PackedVector2Array([
		Vector2(r, 0.0),
		Vector2(-r * 0.2, -r * 0.65),
		Vector2(-r * 0.75, -r * 0.25),
		Vector2(-r * 0.55, 0.0),
		Vector2(-r * 0.75, r * 0.25),
		Vector2(-r * 0.2, r * 0.65)
	])
	draw_colored_polygon(pts, body_c)

	var stroke_pts := PackedVector2Array([
		Vector2(r, 0.0),
		Vector2(-r * 0.2, -r * 0.65),
		Vector2(-r * 0.75, -r * 0.25),
		Vector2(-r * 0.55, 0.0),
		Vector2(-r * 0.75, r * 0.25),
		Vector2(-r * 0.2, r * 0.65),
		Vector2(r, 0.0)
	])
	draw_polyline(stroke_pts, rim_c, 1.6, true)
	# 细浅寒芒刃线（线宽 1.0，叠在深色描边上形成亮刃微芒）
	draw_polyline(stroke_pts, outline_c, 1.0, true)

	# 剑脊高能亮芯
	draw_line(Vector2(-r * 0.45, 0.0), Vector2(r * 0.7, 0.0), core_c, 1.8, true)
	draw_circle(Vector2(r * 0.1, 0.0), r * 0.25, core_c)

func _physics_process(delta: float) -> void:
	if angular_speed != 0.0:
		direction = direction.rotated(angular_speed * delta)
		if sword_style:
			rotation = direction.angle()
	if accel != 0.0:
		speed = maxf(min_speed, speed + accel * delta)
	position += direction * speed * delta
	if _trail != null:
		_trail.sample(global_position, delta)
	lifetime -= delta
	if split_timer > 0.0:
		split_timer -= delta
		if split_timer <= 0.0:
			_explode_split()
			return
	if lifetime <= 0.0:
		_recycle()

func _on_body_entered(body: Node) -> void:
	if body is Player:
		# 受击火花/跳字统一由 Player.take_damage 发放（与 BladeProjectile 同一约定）：
		# 弹体侧再发一份，闪避/无敌帧会在没掉血时凭空闪白光，真命中又和玩家侧双发
		body.take_damage(damage)
		_recycle()
