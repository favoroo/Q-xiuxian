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

# 幽冥剑气配色（御剑邪修专属：朱砂赤煞破空三角剑芒，彻底与地面的幽蓝经验水晶区分开）
const BODY_COLOR_SWORD := Color(0.96, 0.25, 0.18)       ## 朱砂赤焰剑气身
const CORE_COLOR_SWORD := Color(1.0, 0.94, 0.80)        ## 暖白高热极亮剑芯
const RIM_COLOR_SWORD := Color(0.38, 0.05, 0.06)        ## 暗黑焦红硬描边
const OUTLINE_COLOR_SWORD := Color(1.0, 0.65, 0.45, 0.85) ## 亮红外刃微芒描边

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
var sword_style: bool = false    ## 幽冥剑气形态（兼容开关：true 等价于 style == Style.SWORD）
var tint_color: Color = Color(0, 0, 0, 0) ## 主题色（alpha == 0 表示不启用主题色；>0 时优先级高于 purple_style，Boss 专属弹幕辨识用）

enum Style { ORB, SWORD, NEEDLE, TALISMAN, FLAME, VOID }
var style: int = Style.ORB
var accent_color: Color = Color(0, 0, 0, 0)   ## 强调色/主轮廓（alpha==0 表示按现有 tint_color 派生）
var core_color: Color = Color(0, 0, 0, 0)     ## 核心高光色（alpha==0 表示按 accent 派生）

## 样式配置入口（主编统一调用接口）
func set_style(s: int, accent: Color = Color(0, 0, 0, 0), core: Color = Color(0, 0, 0, 0)) -> void:
	style = s
	accent_color = accent
	core_color = core
	sword_style = (s == Style.SWORD)
	if is_inside_tree():
		queue_redraw()

## 统一形态判定（兼容 sword_style 旧开关）
func _effective_style() -> int:
	return Style.SWORD if sword_style else style

## 是否为方向性弹体（出膛对齐飞行速度角）
func _is_directional_style() -> bool:
	var s := _effective_style()
	return s == Style.SWORD or s == Style.NEEDLE or s == Style.TALISMAN

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
	style = Style.ORB
	accent_color = Color(0, 0, 0, 0)
	core_color = Color(0, 0, 0, 0)
	tint_color = Color(0, 0, 0, 0)

func _ready() -> void:
	add_to_group("enemy_bolts")
	collision_layer = 0
	collision_mask = 2  # player
	# 方向型弹体沿发射方向定向，球型/全向弹体保持 rotation = 0
	rotation = direction.angle() if _is_directional_style() else 0.0
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

## 当前弹体是否值得挂拖尾：拥挤档一律不挂；非 ORB 形态或 Boss 大弹才挂
func _trail_enabled() -> bool:
	if FxBudget.crowded:
		return false
	return (_effective_style() != Style.ORB) or scale_factor > 1.2

## 拖尾按需懒建（只在需要时挂一次，池化复用不再重建）。
## 不在 _ready 建：普通火球（占绝大多数）永不创建，既守「画多大判多大」的子节点铁律
## （判定圆之外不长任何视觉节点），也省内存。
func _ensure_trail() -> EnemyBoltTrail:
	if _trail == null or not is_instance_valid(_trail):
		_trail = EnemyBoltTrail.new()
		add_child(_trail)
	return _trail

## 色彩派生规则（守 AGENTS 视觉层铁律）：
## accent = accent_color.a > 0 ? accent_color : tint_color.lightened(0.15)（或 purple/body 派生）
## core = core_color.a > 0 ? core_color : accent.lightened(0.55)
## 暗部 = accent.darkened(0.55)
func _resolve_colors() -> Dictionary:
	var base_c: Color
	if tint_color.a > 0.0:
		base_c = tint_color
	elif purple_style:
		base_c = BODY_COLOR_PURPLE
	else:
		base_c = BODY_COLOR

	var accent: Color = accent_color if accent_color.a > 0.0 else base_c.lightened(0.15)
	var core: Color = core_color if core_color.a > 0.0 else accent.lightened(0.55)
	var dark: Color = accent.darkened(0.55)
	return {
		"accent": accent,
		"core": core,
		"dark": dark,
	}

func _get_accent_color() -> Color:
	if accent_color.a > 0.0:
		return accent_color
	if tint_color.a > 0.0:
		return tint_color.lightened(0.15)
	if _effective_style() == Style.SWORD:
		return RIM_COLOR_JIANSHA if purple_style else RIM_COLOR_SWORD
	if purple_style:
		return BODY_COLOR_PURPLE.lightened(0.15)
	return BODY_COLOR.lightened(0.15)

## 弹体描边色（受击火花/湮灭效果同源取色）
func _rim_color() -> Color:
	if accent_color.a > 0.0:
		return accent_color
	if tint_color.a > 0.0:
		return tint_color
	if _effective_style() == Style.SWORD:
		return RIM_COLOR_JIANSHA if purple_style else RIM_COLOR_SWORD
	if purple_style:
		return RIM_COLOR_PURPLE
	return RIM_COLOR

## 浅色细描边色（外沿高光反差轮廓）
func _outline_color() -> Color:
	if accent_color.a > 0.0:
		return accent_color.lightened(0.35)
	if tint_color.a > 0.0:
		return tint_color.lightened(0.35)
	if _effective_style() == Style.SWORD:
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
	rotation = direction.angle() if _is_directional_style() else 0.0
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
		tr.configure(_get_accent_color())
		tr.set_active(true)
		tr.seed(global_position)
	elif _trail != null:
		_trail.set_active(false)

## 被友方/防御灵兽拦截：立刻回收入池（产生湮灭灵光碎屑，平滑消散）
func intercept() -> void:
	if _pooled:
		return
	var rim_c := _rim_color()
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
	var cur_style := style
	var cur_sword := sword_style
	var cur_accent := accent_color
	var cur_core := core_color
	var cur_tint := tint_color
	var rim_c := _rim_color()
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
		child_bolt.style = cur_style
		child_bolt.sword_style = cur_sword
		child_bolt.accent_color = cur_accent
		child_bolt.core_color = cur_core
		child_bolt.tint_color = cur_tint
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
	# 单发敌弹 3~8 条矢量原语合成 1 个 draw call（2026-11-03 绘制专项）
	BatchDraw.flush(self)
	match _effective_style():
		Style.SWORD:
			_draw_sword_bolt()
		Style.NEEDLE:
			_draw_needle_bolt()
		Style.TALISMAN:
			_draw_talisman_bolt()
		Style.FLAME:
			_draw_flame_bolt()
		Style.VOID:
			_draw_void_bolt()
		Style.ORB, _:
			_draw_orb_bolt()
	BatchDraw.flush(self)

func _draw_orb_bolt() -> void:
	var body_c: Color
	var rim_c: Color
	var outline_c: Color
	var core_c: Color
	if accent_color.a > 0.0:
		rim_c = accent_color
		body_c = accent_color.darkened(0.35)
		outline_c = accent_color.lightened(0.35)
		core_c = core_color if core_color.a > 0.0 else accent_color.lightened(0.65)
	elif tint_color.a > 0.0:
		rim_c = tint_color
		body_c = tint_color.darkened(0.35)
		outline_c = tint_color.lightened(0.35)
		core_c = tint_color.lightened(0.65)
	elif purple_style:
		body_c = BODY_COLOR_PURPLE
		rim_c = RIM_COLOR_PURPLE
		outline_c = OUTLINE_COLOR_PURPLE
		core_c = CORE_COLOR_PURPLE
	else:
		body_c = BODY_COLOR
		rim_c = RIM_COLOR
		outline_c = OUTLINE_COLOR
		core_c = CORE_COLOR
	# 绘制口径：画多大判多大（半径严格在 radius 之内）
	# 1. 弹体球身
	BatchDraw.circle(self, Vector2.ZERO, radius, body_c, 3.2)
	# 2. 内层暗色硬描边（线宽 1.4，内压立体感）
	BatchDraw.arc(self, Vector2.ZERO, maxf(radius - 1.2, 1.0), 0.0, TAU, rim_c, 1.4)
	# 3. 最外层细浅描边（线宽 1.0，外沿严格吻合 radius 判定圆，暗调地表上高反差勾边）
	BatchDraw.arc(self, Vector2.ZERO, maxf(radius - 0.5, 0.5), 0.0, TAU, outline_c, 1.0)
	# 4. 高光芯
	BatchDraw.circle(self, Vector2.ZERO, radius * 0.45, core_c, 3.2)

## 幽冥剑气视觉绘制（紧凑破空掠翼三角剑芒，尺寸严格内切判定圆 radius，铁律 7：画多大判多大）
func _draw_sword_bolt() -> void:
	var body_c: Color
	var rim_c: Color
	var outline_c: Color
	var core_c: Color
	if accent_color.a > 0.0:
		rim_c = accent_color
		body_c = accent_color.darkened(0.35)
		outline_c = accent_color.lightened(0.35)
		core_c = core_color if core_color.a > 0.0 else accent_color.lightened(0.65)
	elif tint_color.a > 0.0:
		rim_c = tint_color
		body_c = tint_color.darkened(0.35)
		outline_c = tint_color.lightened(0.35)
		core_c = tint_color.lightened(0.65)
	elif purple_style:
		body_c = BODY_COLOR_JIANSHA
		rim_c = RIM_COLOR_JIANSHA
		outline_c = OUTLINE_COLOR_JIANSHA
		core_c = CORE_COLOR_JIANSHA
	else:
		body_c = BODY_COLOR_SWORD
		rim_c = RIM_COLOR_SWORD
		outline_c = OUTLINE_COLOR_SWORD
		core_c = CORE_COLOR_SWORD

	var r := radius
	# 破空掠翼锐角三角形（前尖达 r，两翼向后平滑收束，尾部内收形成掠翼破空感，尺寸紧凑不超长）
	var pts := PackedVector2Array([
		Vector2(r, 0.0),                     # 锐利前尖
		Vector2(-r * 0.75, -r * 0.70),       # 上尾翼
		Vector2(-r * 0.40, 0.0),             # 尾部内收凹角（掠翼剑羽）
		Vector2(-r * 0.75, r * 0.70)         # 下尾翼
	])
	BatchDraw.native_poly(self, pts, body_c)

	var stroke_pts := PackedVector2Array([
		Vector2(r, 0.0),
		Vector2(-r * 0.75, -r * 0.70),
		Vector2(-r * 0.40, 0.0),
		Vector2(-r * 0.75, r * 0.70),
		Vector2(r, 0.0)
	])
	BatchDraw.native_polyline(self, stroke_pts, rim_c, 1.6, true)
	# 细浅外刃亮芒线（线宽 1.0，叠在深色描边上形成亮刃反差）
	BatchDraw.native_polyline(self, stroke_pts, outline_c, 1.0, true)

	# 剑脊高能亮芯与剑心
	BatchDraw.native_line(self, Vector2(-r * 0.25, 0.0), Vector2(r * 0.75, 0.0), core_c, 1.6, true)
	BatchDraw.circle(self, Vector2(r * 0.05, 0.0), r * 0.20, core_c, 3.2)

## 雷芒/镜棱/枪刺视觉绘制（细长菱形，尖端 +0.98r，尾端 -0.90r，半宽 0.32r，三层层次）
func _draw_needle_bolt() -> void:
	var cols := _resolve_colors()
	var accent_c: Color = cols["accent"]
	var core_c: Color = cols["core"]
	var dark_c: Color = cols["dark"]

	var r := radius
	# 细长菱形顶点：尖端 +0.98r，尾端 -0.90r，横向半宽 0.32r
	var pts := PackedVector2Array([
		Vector2(r * 0.98, 0.0),
		Vector2(0.0, -r * 0.32),
		Vector2(-r * 0.90, 0.0),
		Vector2(0.0, r * 0.32)
	])
	# 1. 暗色填充
	BatchDraw.poly(self, pts, dark_c)

	# 2. accent 描边
	var stroke_pts := PackedVector2Array([
		Vector2(r * 0.98, 0.0),
		Vector2(0.0, -r * 0.32),
		Vector2(-r * 0.90, 0.0),
		Vector2(0.0, r * 0.32),
		Vector2(r * 0.98, 0.0)
	])
	BatchDraw.native_polyline(self, stroke_pts, accent_c, maxf(1.0, r * 0.12), true)

	# 3. core 中轴亮线
	BatchDraw.native_line(self, Vector2(-r * 0.70, 0.0), Vector2(r * 0.85, 0.0), core_c, maxf(1.0, r * 0.12), true)

## 符箓视觉绘制（矩形符纸 宽 1.25r × 高 1.55r，半对角线 ≈ 0.968r 严格内切判定圆）
func _draw_talisman_bolt() -> void:
	var cols := _resolve_colors()
	var accent_c: Color = cols["accent"]
	var core_c: Color = cols["core"]
	var dark_c: Color = cols["dark"]

	var r := radius
	var hx := r * 0.76   # 符纸半长（沿飞行方向，全长约 1.52r）
	var hy := r * 0.60   # 符纸半宽（全宽约 1.20r，半对角线 ≈ 0.968r 严格内切）

	# 1. 深色纸面填充
	var paper_pts := PackedVector2Array([
		Vector2(hx, -hy),
		Vector2(hx, hy),
		Vector2(-hx, hy),
		Vector2(-hx, -hy)
	])
	BatchDraw.poly(self, paper_pts, dark_c)

	# 2. accent 细边框
	var border_pts := PackedVector2Array([
		Vector2(hx, -hy),
		Vector2(hx, hy),
		Vector2(-hx, hy),
		Vector2(-hx, -hy),
		Vector2(hx, -hy)
	])
	BatchDraw.native_polyline(self, border_pts, accent_c, maxf(1.0, r * 0.10), true)

	# 3. 顶部小三角符头（指向 +X 前端）
	var head_pts := PackedVector2Array([
		Vector2(hx * 0.92, 0.0),
		Vector2(hx * 0.50, -hy * 0.45),
		Vector2(hx * 0.50, hy * 0.45)
	])
	BatchDraw.poly(self, head_pts, accent_c)

	# 4. 纸面中央 2~3 笔朱墨符文（core 色细线）
	var line_w := maxf(1.0, r * 0.10)
	BatchDraw.native_line(self, Vector2(-hx * 0.65, 0.0), Vector2(hx * 0.35, 0.0), core_c, line_w, true)
	BatchDraw.native_line(self, Vector2(hx * 0.15, -hy * 0.45), Vector2(hx * 0.15, hy * 0.45), core_c, line_w, true)
	BatchDraw.native_line(self, Vector2(-hx * 0.35, -hy * 0.35), Vector2(-hx * 0.20, hy * 0.35), core_c, line_w, true)

## 火球/龙息视觉绘制（主球 0.92r + 尾部多边形火舌 ≤ -0.95r，暖白 core 球 0.42r，尾部朝 -X）
func _draw_flame_bolt() -> void:
	var cols := _resolve_colors()
	var accent_c: Color = cols["accent"]
	var core_c: Color = cols["core"]
	var dark_c: Color = cols["dark"]

	var r := radius

	# 1. 尾部 3 片火舌（多边形，尾端朝向 -X，不超出 -0.95r）
	# 主中火舌（尖端 -0.95r）
	var tail_center := PackedVector2Array([
		Vector2(-r * 0.25, -r * 0.28),
		Vector2(-r * 0.95, 0.0),
		Vector2(-r * 0.25, r * 0.28)
	])
	BatchDraw.poly(self, tail_center, dark_c)

	# 上火舌（尖端 -0.85r, -0.36r，距心 ≈ 0.923r）
	var tail_upper := PackedVector2Array([
		Vector2(-r * 0.15, -r * 0.20),
		Vector2(-r * 0.85, -r * 0.36),
		Vector2(-r * 0.40, -r * 0.52)
	])
	BatchDraw.poly(self, tail_upper, dark_c)

	# 下火舌（尖端 -0.85r, 0.36r，距心 ≈ 0.923r）
	var tail_lower := PackedVector2Array([
		Vector2(-r * 0.15, r * 0.20),
		Vector2(-r * 0.85, r * 0.36),
		Vector2(-r * 0.40, r * 0.52)
	])
	BatchDraw.poly(self, tail_lower, dark_c)

	# 内层亮火舌（尖端 -0.75r）
	var tail_inner := PackedVector2Array([
		Vector2(-r * 0.20, -r * 0.16),
		Vector2(-r * 0.75, 0.0),
		Vector2(-r * 0.20, r * 0.16)
	])
	BatchDraw.poly(self, tail_inner, accent_c)

	# 2. 主球 0.92r
	BatchDraw.circle(self, Vector2.ZERO, r * 0.92, accent_c, 3.2)
	BatchDraw.arc(self, Vector2.ZERO, maxf(r * 0.92 - 0.5, 0.5), 0.0, TAU, dark_c, 1.0)

	# 3. 暖白 core 球 0.42r
	var warm_white := Color(1.0, 0.96, 0.88)
	var flame_core := core_c.lerp(warm_white, 0.55)
	BatchDraw.circle(self, Vector2(r * 0.05, 0.0), r * 0.42, flame_core, 3.2)
	BatchDraw.circle(self, Vector2(r * 0.10, 0.0), r * 0.20, Color.WHITE, 3.2)

## 虚空/魔弹视觉绘制（内核 0.55r + accent 外环 0.86r + 环上 3 枚菱形碎晶 0.16r）
func _draw_void_bolt() -> void:
	var cols := _resolve_colors()
	var accent_c: Color = cols["accent"]
	var core_c: Color = cols["core"]
	var dark_c: Color = cols["dark"]

	var r := radius
	var void_black := dark_c.darkened(0.75)
	void_black.a = 1.0

	# 1. 近乎黑色的内核 0.55r
	BatchDraw.circle(self, Vector2.ZERO, r * 0.55, void_black, 3.2)
	BatchDraw.arc(self, Vector2.ZERO, maxf(r * 0.55 - 0.5, 0.5), 0.0, TAU, dark_c, 1.0)

	# 2. accent 外环（线宽 0.14r，半径 0.86r）
	var ring_w := maxf(1.0, r * 0.14)
	BatchDraw.arc(self, Vector2.ZERO, r * 0.86, 0.0, TAU, accent_c, ring_w)

	# 3. 环上 3 枚小菱形碎晶（距心 0.86r，尺寸 0.16r，沿圆周对称分布）
	var shard_r := r * 0.86
	var half_s := r * 0.08  # 半尺寸 0.08r（全尺寸 0.16r）
	for i in range(3):
		var ang := float(i) * (TAU / 3.0)
		var c := Vector2(cos(ang), sin(ang)) * shard_r
		var u_rad := Vector2(cos(ang), sin(ang))
		var u_tan := Vector2(-sin(ang), cos(ang))
		var shard_pts := PackedVector2Array([
			c + u_rad * half_s,
			c + u_tan * half_s,
			c - u_rad * half_s,
			c - u_tan * half_s
		])
		BatchDraw.poly(self, shard_pts, core_c)

func _physics_process(delta: float) -> void:
	if angular_speed != 0.0:
		direction = direction.rotated(angular_speed * delta)
		if _is_directional_style():
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
