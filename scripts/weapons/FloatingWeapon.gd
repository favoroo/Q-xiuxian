class_name FloatingWeapon
extends Node2D

## 环绕玩家的悬浮武器：数值/行为全部来自 WeaponData，星级影响伤害与冷却
##
## 朝向的唯一真话（2026-10-09，用户口径：「庚金飞剑发射时朝向不对，没朝敌人；不知道从哪里发射的」）：
## 本体节点 rotation == 真实瞄准方向（下称"发射帧"），贴图自己按 art_angle 反向补偿，
## 于是"剑尖指向"和"弹丸出膛方向"和"这一发的 aim_dir"三者必然同轴 —— 不再靠贴图天生朝右。
## 出膛点 = 发射帧 +X 上 muzzle_len 处，即 WeaponData 里每件武器标定的剑尖/器口。
## 旧写法是 sprite.rotation 不动、节点转成瞄准角 ⇒ 天生朝右上 35° 的飞剑，剑尖永远偏着 35°，
## 而 MuzzlePoint 又钉在贴图坐标 (20,0)（×0.55 缩放 = 11px 处，正落在剑格上），
## 所以看着就是"从剑柄附近不知道哪儿冒出来一发"。

## 未在表里标定 tip 时的兜底（判据 _test_five_elements_system 会钉住"每件都标定过"）
const FALLBACK_TIP := Vector2(20, 0)

## 近战"画多大==判多大"（2026-10-09）：判定是一个圆 —— 圆心在本体前突 MELEE_LUNGE、
## 半径 MELEE_ARC_RADIUS × arc_scale × 射程乘区。弧光由 WeaponArcRenderer 纯矢量绘制
## （2026-10-13 取代 slash_effect.png 贴图）：围绕自身轴心、半径 124 画布像素、张角 ±70°
## 的一弯细月牙，所以把月牙轴心摆到判定圆心、缩放取
## 判定半径 / SLASH_ART_OUTER ⇒ 月牙外缘正好压在判定圆的边界上。
const MELEE_LUNGE := 30.0
const MELEE_ARC_RADIUS := 75.0
const SLASH_ART_OUTER := 124.0

## 剑气出鞘扫放（2026-10-11，用户口径：「范围叠高后，剑挥一下，很远才出现一道剑气，很怪」）：
## 月牙不再出生即钉在判定外缘，而是内缘贴剑尖出生、SLASH_SWEEP_TIME 内扫放到判定几何再淡出
## —— 剑气是从剑上劈出去的，不是凭空悬在远处。终态仍是上面那条"外缘==判定半径"的同源
## 不变量，判定数值一字不动。月牙贴图的不透明带贴在外缘（0° 方向实测 102~127px、89px 起
## 半透明淡入），出生缩放按"内缘压住剑尖屏上位置 muzzle_len"反解。
const SLASH_ART_INNER := 114.0  ## 月牙中心内缘画布半径（== WeaponArcRenderer.MELEE_INNER，锥形月牙中心厚度 10px），出生"贴剑尖"反解用
const SLASH_SPAWN_INSET := 2.0  ## 出生内缘再往前探 2px，让剑尖埋进剑气里
const SLASH_SWEEP_TIME := 0.10  ## 剑气从剑尖扫放到判定外缘的时长（期间保持全亮）
const SLASH_FADE_TIME := 0.08   ## 抵达判定外缘后的淡出时长 —— 落点先亮一拍再散
const MELEE_THRUST := 26.0      ## 打击帧本体前突距离
const MELEE_STRETCH_MAX := 2.0  ## 突刺随射程乘区的前突上限倍数（只往前够，不缩水）

## 横扫（SWEEP）与近战分家（2026-10-13，用户口径：「横扫和近战玩起来没区别」）：
## 判定是「前方真扇形」——以本体为圆心查 _sweep_arc_radius() 的圆，再按角度过滤，
## 只结算 aim_dir ±SWEEP_HALF_ANGLE 里的敌人（身后的漏网，这是与近战 360° 圆判定最本质的手感差异）；
## 刀光是 WeaponArcRenderer 画的元素扇面（满亮 ±80° 与判定半角同源、外缘 124px 与近战月牙同画布约定），
## top_level 贴世界坐标 —— 扇面钉在挥出那一帧的方位上，不随本体收势转走，扇面几何 == 判定扇形。
## 节奏全面比近战沉：蓄力更深更久、前突更远、收势更慢、命中音低沉一档。
const SWEEP_ARC_RADIUS := 88.0    ## 横扫扇形基础半径（近战圆 75，横扫手更长）
const SWEEP_HALF_ANGLE := 80.0    ## 扇形半角（度）—— 与 WeaponArcRenderer 扇面满亮张角同源，改渲染要同步改这里
const SWEEP_ART_OUTER := 124.0    ## 扇面外缘画布半径（WeaponArcRenderer.OUTER）
const SWEEP_SLASH_IN_TIME := 0.09 ## 扇面扫放（扩张 + 转正）时长
const SWEEP_SLASH_FADE := 0.09    ## 扇面淡出时长
const SWEEP_WINDUP := 0.09        ## 蓄力前摇（近战 0.05）
const SWEEP_STRIKE := 0.06        ## 横扫瞬发（近战 0.04）
const SWEEP_RECOVER := 0.17       ## 沉重收势（近战 0.13）
const SWEEP_THRUST := 30.0        ## 打击帧本体前突（近战 26）
const SWEEP_RECOIL := 6.0         ## 入肉反冲（近战 4.5）
const SWEEP_CLOSE_GRACE := 26.0   ## 贴脸宽容：距离小于它不看角度（敌人受击圈 15px，扇形顶点不许漏贴身的）
const SWEEP_ANGLE_SLACK := 6.0    ## 角度宽容（度）：扇面 80°→88° 羽化边里擦到的也算中
const SWEEP_IMPACT_PITCH := 0.9   ## 横扫命中音低沉一档，与近战的亮脆分层

## 近战双层与雷法双层的相对响度（2026-10-10 音色重构）：
## 前摇破空是「动作」，无条件播、当铺垫层，所以压低；命中材质是「战果」，只在真打中时补一记。
## 旧写法只有一层，且写在打击帧 —— 一声纯空气破空挂在命中 moment，剑听上去就是棍子。
const MELEE_WHOOSH_SCALE := 1.0
const MELEE_IMPACT_SCALE := 0.95   ## 压在 enemy_hit（0.56 峰值）之下，三层同帧才不糊
const BURST_CAST_SCALE := 0.7      ## 施法层：落点才是主角，这里只起手

@export var weapon_def_id: String = "qingyun_sword"
@export var star: int = 1

var def: Dictionary = {}
var behavior: int = WeaponData.Behavior.MELEE
var base_damage: float = 30.0
var attack_cooldown: float = 1.1
## _volley_targets 排序上下文（命名方法避免每次开火 new 闭包，照 Player._sort_candidate_by_dist 先例）
var _volley_player_pos: Vector2 = Vector2.ZERO
var _volley_muzzle_pos: Vector2 = Vector2.ZERO
var attack_range: float = 150.0
var pierce: int = 1
var burst_radius: float = 80.0
var arc_scale: float = 1.0

var tip_local: Vector2 = FALLBACK_TIP  # 剑尖/器口，贴图坐标系、相对画布中心（画布像素）
var art_angle: float = 0.0             # == tip_local.angle()：这张图天生朝哪个方向
var upright: bool = false              # 重器保持世界竖直（宝灯/法牌/大印/灵藤）
var muzzle_len: float = 11.0           # 出膛点离本体中心的屏上距离 = |tip| × 贴图缩放

## 弹丸外观三件套（bullet / bullet_scale / bullet_spin）：setup 期一次性解析，
## 开火逐发不再走 ResourceLoader.exists/load 与 def.get —— 高射速齐射时每秒
## 数十次的路径哈希查找是纯浪费（路径对同一武器恒定）
var _bullet_tex: Texture2D = null
var _bullet_scale: float = 1.0
var _bullet_spins: bool = false

var cooldown_timer: float = 0.0
var base_angle: float = 0.0        # 无目标时回归的基础槽位角（Player 下发）
var spread_angle: float = 0.0      # 多把武器间的错开角，避免重叠（Player 下发）
## 默认环绕轨道半长轴/半短轴（椭圆）：贴身护体，避免脱节
const DEFAULT_ORBIT_EXTENTS := Vector2(54.0, 40.0)
var orbit_extents: Vector2 = DEFAULT_ORBIT_EXTENTS
var dynamic_angle: float = 0.0     # 当前轨道角：有目标时滑向目标方位
var current_target: Node2D = null
var is_attacking: bool = false
var bob_phase: float = 0.0
var _slash_tween: Tween = null     # 剑气出鞘扫放的全生命周期（亮扫→淡出→隐藏），再次攻击时先杀旧的
var sweep_sprite: WeaponArcRenderer = null  # 横扫专属元素扇面（top_level 世界坐标，SWEEP 才建）
var _sweep_slash_tween: Tween = null

## 土系重击地面裂痕全局限频（2026-10-16）：旧写法每把武器各自 0.85s 一道，
## 多把土系武器 × 高攻速下几乎每次命中都裂、满屏裂纹。裂痕是「重击砸地」的
## 偶发留痕而非常规命中反馈，改全武器共享一道时间闸：任一武器留痕后
## EARTH_CRACK_MIN_GAP_MS 内所有武器（含自己）的后续命中都不再出新裂痕。
## 用时间戳而非倒计时——_process 每实例各跑一遍，共享倒计时会被多把武器重复扣减。
const EARTH_CRACK_MIN_GAP_MS := 5000   ## 2026-10-19 风格统一：玉面战台去裂痕化，留痕间隔再翻倍
static var _last_earth_crack_ms: int = -999999  ## 上次留痕时间戳（负初值 = 从未留痕；GDScript 的 << 不吃负操作数）

# ---------------- 开火视觉帧内状态机（Android 稳态 GC 治理） ----------------
## 每次开火原建 3~4 个局部 Tween（后坐 1 + 枪口闪光 1 + 本体亮闪 1 + 光晕 1），
## 高攻速齐射下是每秒几十个 Tween 分配。改照 EnemyBase._tick_hit_fx 的帧内状态机范式：
## 起火时记初值，_tick_fire_fx 逐帧闭式插值回位，曲线与原 Tween 等价（EXPO 急退 + BACK 弹回）。
const RECOIL_DIST := 8.0        ## 远程后坐距离（px，沿 aim_dir 反向）
const RECOIL_BACK_TIME := 0.04  ## 后坐急退段时长
const RECOIL_RETURN_TIME := 0.12 ## 后坐弹回段时长
const TURRET_DIP := Vector2(0, 8)  ## 召唤炮台时本体下沉量
const MUZZLE_TIME := 0.09      ## 枪口闪光消退时长
const AURA_BASE_A := 0.12      ## 光晕常驻透明度（与待机脉动基线一致）
const AURA_FLASH_A := 0.45     ## 光晕点亮峰值
var _lunge_t: float = -1.0     ## >=0 表示后坐/沉身进行中；走完释放 is_attacking
var _lunge_total: float = 0.0
var _lunge_out_time: float = 0.0
var _lunge_orig: Vector2 = Vector2.ZERO
var _lunge_out: Vector2 = Vector2.ZERO
var _lunge_ends_attack: bool = false  ## 演出走完是否代释放 is_attacking
var _flash_t: float = 0.0      ## 本体亮闪剩余时间
var _flash_total: float = 0.0001
var _flash_from: Color = Color.WHITE
var _muzzle_t: float = 0.0     ## 枪口闪光剩余时间
var _muzzle_scale0: float = 0.5

## 脱程重查节流（2026-10-10 第 6 波卡顿优化）：15Hz + instance_id 错相
const RETARGET_INTERVAL := 1.0 / 15.0
var _retarget_phase: float = 0.0

# ---------------- 持续束流（BEAM 光束 / CONE 喷吐，2026-10-13） ----------------
## 与六段式攻击不同：束流不设 is_attacking（不冻结轨道与朝向），起喷后由 _tick_channel
## 逐帧续命 —— 朝向本身 15rad/s 追踪目标，光束/火锥自然跟着缓慢扫动。
## 每 TICK 结算一次，tick 伤害 = 整管伤害 × TICK / 有效冷却 ⇒ 纸面 DPS（damage/cd）即实伤。
## 冷却循环到期自动续喷（CHANNEL_HOLD > 冷却 ⇒ 目标在程内连续不断）；目标死亡/脱程即收束。
const CHANNEL_HOLD := 1.6      ## 一次起喷持续时间（秒），冷却每转一圈回来续喷
const BEAM_TICK := 0.15        ## 光束结算间隔
const CONE_TICK := 0.21        ## 喷吐结算间隔（火葫芦 0.42 冷却 = 每周期 2 跳）
const CONE_HALF_ANGLE := 28.0  ## 喷吐锥形半角（度），视觉锥宽同源
const BEAM_HALF_WIDTH := 5.0   ## 光束判定半宽（视觉束宽同源）
## 光束判定在截断点后再探出一段：射线停在挡束者表面，不补这段则挡住光束的敌人自己
## 反而打不到（判定只到它表皮）；补段长约一个敌人受击半径，只盖挡束者、不穿墙打后排。
const BEAM_HIT_OVERHANG := 24.0
var _channel_on: bool = false
var _channel_left: float = 0.0
var _channel_tick: float = 0.0
var _beam_len: float = 0.0     ## 本 tick 光束判定长度（射线命中截断，渲染同源）
## 束长射线节流（2026-10-14）：原每渲染帧 create 参数对象 + intersect_ray（60 次/秒），
## 降到 10Hz 快照 + 参数对象复用（对齐 _search_query 范式），帧间 _beam_len 向快照缓动；
## 起喷当帧强制立判（_beam_need_cast），首跳伤害长度不滞后。
const BEAM_CAST_INTERVAL := 0.1
var _beam_cast_phase: float = 0.0
var _beam_len_target: float = 0.0
var _beam_need_cast: bool = false
static var _beam_ray_query: PhysicsRayQueryParameters2D = null
var beam_renderer: BeamRenderer = null
var cone_renderer: FlameConeRenderer = null
## 光束判定矩形静态复用（照 _search_shape 模式，单线程安全，每次查询现写尺寸）
static var _beam_shape: RectangleShape2D = null
static var _beam_query: PhysicsShapeQueryParameters2D = null

@onready var sprite: Sprite2D = $Sprite2D
@onready var muzzle_point: Marker2D = $MuzzlePoint
@onready var slash_sprite: WeaponArcRenderer = $SlashEffect

var muzzle_flash: Sprite2D
var aura_sprite: Sprite2D = null
var _base_sprite_scale := Vector2(0.55, 0.55)

var projectile_scene: PackedScene = preload("res://scenes/weapons/BladeProjectile.tscn")
var burst_scene: PackedScene = preload("res://scenes/weapons/ThunderBurst.tscn")
var turret_scene: PackedScene = preload("res://scenes/weapons/TurretUnit.tscn")

var active_turrets: Array[TurretUnit] = []

const CHARGE_GLOW := Color(1.45, 1.28, 0.62)   # 五雷蓄力时的金光

## 物理查询对象 static 复用（2026-10-10 性能优化，照 BladeProjectile._search_shape 模式）：
## 三处索敌/命中查询每次 new CircleShape2D + QueryParams 是白扔的分配压力。
## 单线程使用安全，radius/transform 每次调用重设。
static var _search_shape: CircleShape2D = null
static var _search_query: PhysicsShapeQueryParameters2D = null

## 以 center 为圆心、radius 为半径查敌人受击区（碰撞层 4），max_results 控制截断数
func _query_enemies(radius: float, center: Vector2, max_results: int) -> Array:
	if _search_shape == null or _search_query == null:
		_search_shape = CircleShape2D.new()
		_search_query = PhysicsShapeQueryParameters2D.new()
		_search_query.shape = _search_shape
		_search_query.collision_mask = 4
		_search_query.collide_with_areas = true
	_search_shape.radius = radius
	_search_query.transform = Transform2D(0.0, center)
	return get_world_2d().direct_space_state.intersect_shape(_search_query, max_results)

## 必须在 add_child 之前调用
func setup(def_id: String, star_level: int) -> void:
	weapon_def_id = def_id
	star = clampi(star_level, 1, WeaponData.MAX_STAR)
	def = WeaponData.get_def(def_id)
	behavior = int(def.get("behavior", WeaponData.Behavior.MELEE))
	base_damage = WeaponData.damage_for(def_id, star)
	attack_cooldown = WeaponData.cooldown_for(def_id, star)
	attack_range = float(def.get("range", 150.0))
	pierce = int(def.get("pierce", 1))
	burst_radius = float(def.get("burst_radius", 80.0))
	arc_scale = float(def.get("arc_scale", 1.0))
	tip_local = def.get("tip", FALLBACK_TIP)
	art_angle = tip_local.angle()
	upright = bool(def.get("upright", false))
	# 弹丸纹理在 setup 期只加载一次（升星重调 setup 也只是重复赋同值，load 有引擎级缓存兜底）
	var bullet_path: String = String(def.get("bullet", ""))
	if not bullet_path.is_empty() and ResourceLoader.exists(bullet_path):
		_bullet_tex = load(bullet_path) as Texture2D
	_bullet_scale = float(def.get("bullet_scale", 1.0))
	_bullet_spins = bool(def.get("bullet_spin", false))

func _ready() -> void:
	slash_sprite.visible = false
	slash_sprite.modulate.a = 0.0
	bob_phase = randf() * TAU
	_retarget_phase = fposmod(float(get_instance_id() % 97) * 0.001, RETARGET_INTERVAL)
	## 首跳错相：同帧进树的多把武器错开首击，否则同型号武器冷却完全同相、永久齐挥
	## （放 _ready 只跑一次；setup() 会被升星重调，不能打断既有节奏）
	cooldown_timer = GameManager.rng.randf_range(0.1, 0.5)
	dynamic_angle = base_angle
	if def.is_empty():
		setup(weapon_def_id, star)
	slash_sprite.configure(WeaponArcRenderer.ArcMode.MELEE, _arc_element())
	if def.has("icon"):
		sprite.texture = load(def["icon"])
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		# 出膛点摆在发射帧（本体 +X = 瞄准方向）的剑尖处：贴图缩放后的实际屏上距离
		muzzle_len = tip_local.length() * sprite.scale.x
		muzzle_point.position = Vector2(muzzle_len, 0.0)
		_apply_facing(rotation)
		_setup_muzzle_flash()
		_setup_aura()
		if behavior == WeaponData.Behavior.SWEEP:
			_setup_sweep_sprite()
		elif behavior == WeaponData.Behavior.BEAM:
			_setup_beam_renderer()
		elif behavior == WeaponData.Behavior.CONE:
			_setup_cone_renderer()

## 横扫元素扇面（top_level = 世界坐标）：扇面钉在挥出那一帧的方位与地点，
## 本体收势/回轨都不会拖着它走 —— 这是「画多大==判多大」在横扫上的落点。
func _setup_sweep_sprite() -> void:
	sweep_sprite = WeaponArcRenderer.new()
	sweep_sprite.configure(WeaponArcRenderer.ArcMode.SWEEP, _arc_element())
	sweep_sprite.top_level = true
	sweep_sprite.visible = false
	sweep_sprite.modulate.a = 0.0
	add_child(sweep_sprite)

## 刀光元素：五行标签优先，无五行但有雷标签的走紫电（如雷系法器）
func _arc_element() -> String:
	var e := WeaponData.element_of(weapon_def_id)
	if e == "" and WeaponData.tags_of(weapon_def_id).has("thunder"):
		e = "thunder"
	return e

## 光束渲染器挂在器口（MuzzlePoint 与发射帧 +X 同轴，本体转向即光束转向）
func _setup_beam_renderer() -> void:
	beam_renderer = BeamRenderer.new()
	beam_renderer.name = "BeamRenderer"
	beam_renderer.position = muzzle_point.position
	beam_renderer.z_index = 5
	add_child(beam_renderer)

## 火锥渲染器同上：锚在器口，锥长 = 射程 − 器口距（判定同源由 _tick_channel 下发）
func _setup_cone_renderer() -> void:
	cone_renderer = FlameConeRenderer.new()
	cone_renderer.name = "FlameConeRenderer"
	cone_renderer.position = muzzle_point.position
	cone_renderer.z_index = 5
	add_child(cone_renderer)

func _setup_aura() -> void:
	aura_sprite = Sprite2D.new()
	var tex := load("res://assets/art/light_radial.png") as Texture2D
	if tex == null:
		return
	aura_sprite.texture = tex
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	aura_sprite.material = mat
	aura_sprite.scale = Vector2.ONE * 0.42
	aura_sprite.modulate = _get_aura_color()
	aura_sprite.modulate.a = 0.12
	# 保持 z_index = 0：避免 z=-1 掉入不透明地砖（courtyard_tile.png 位于 MapLayer z=0）下方被整块遮蔽；
	# move_child 置于首位，确保在同级武器 Sprite2D 之下正常衬底
	aura_sprite.z_index = 0
	add_child(aura_sprite)
	move_child(aura_sprite, 0)

var _cached_aura_color: Color = Color.TRANSPARENT

func _get_aura_color() -> Color:
	if _cached_aura_color.a > 0.0:
		return _cached_aura_color
	var tags: Array = WeaponData.tags_of(weapon_def_id)
	if tags.has("fire"):
		_cached_aura_color = Color(1.0, 0.42, 0.15)
	elif tags.has("water"):
		_cached_aura_color = Color(0.35, 0.75, 1.0)
	elif tags.has("thunder"):
		_cached_aura_color = Color(0.65, 0.45, 1.0)
	elif tags.has("wood") or tags.has("poison"):
		_cached_aura_color = Color(0.35, 0.85, 0.45)
	elif tags.has("earth"):
		_cached_aura_color = Color(0.85, 0.65, 0.35)
	else:
		_cached_aura_color = Color(0.95, 0.85, 0.50)
	return _cached_aura_color

## 朝向唯一入口：节点 rotation = 真实瞄准角（发射帧），贴图自己做补偿。
## - 会转的武器：贴图补掉 art_angle ⇒ 画出来的剑尖必然落在发射帧 +X 上。
##   朝左时再沿瞄准轴竖直镜像（flip_v）避免刀剑倒挂 —— 镜像会把 art_angle 变号，补偿角跟着变号。
## - upright 的重器（宝灯/法牌/大印/灵藤）：贴图反向补掉本体转角，世界坐标里始终竖直，
##   雷只从"朝目标那一侧的器口"引出（旧写法会把印玺横过来对着人）。
## MuzzlePoint 挂在节点上而不是贴图下，所以镜像/补偿都不影响它 —— 旧写法把 Marker 钉在
## Sprite2D 里，flip_v 一开剑尖和出膛点就分家。
func _apply_facing(angle: float) -> void:
	rotation = angle
	if upright:
		sprite.flip_v = false
		sprite.rotation = -angle
	else:
		var mirrored: bool = absf(wrapf(angle, -PI, PI)) > PI * 0.5
		sprite.flip_v = mirrored
		sprite.rotation = art_angle if mirrored else -art_angle

## 这一发的瞄准角：有目标就朝目标，没目标退回当前发射帧（贴图补偿由 _apply_facing 统一做）
func _aim_at(pos: Vector2) -> float:
	return (pos - global_position).angle()

## 射程乘区（攻击范围词条 + 剑系/广域羁绊）：武器侧所有"够得着多远"都从这里取，不许各算各的
func _range_mult() -> float:
	return GameManager.attack_range_mult * GameManager.synergy_range_mult

## 近战判定圆半径 —— 弧光外缘与 _deal_melee_damage 的查询圆共用这一个数
func _melee_arc_radius() -> float:
	var wide_bonus: float = (1.0 + GameManager.item_hook_sum("wide_range_mult")) if WeaponData.tags_of(weapon_def_id).has("wide") else 1.0
	return MELEE_ARC_RADIUS * arc_scale * _range_mult() * wide_bonus

## 打击帧前突倍数：范围叠得越高剑往前送得越远，剑才追得上外扩的剑气（上限 2 倍防乱飘）
func _melee_thrust_mult() -> float:
	return clampf(_range_mult(), 1.0, MELEE_STRETCH_MAX)

## 出膛色随五行走：与弹丸侧 _apply_elemental_tint 同一套异常色板（火橙/冰蓝/毒绿），
## 无异常的武器回默认暖金——弹体什么色、出膛那一瞬就什么色
func _muzzle_color() -> Color:
	if def.get("proc_burn", false):
		return Color(1.0, 0.6, 0.25, 0.95)
	if float(def.get("proc_chill", 0.0)) > 0.0:
		return Color(0.55, 0.85, 1.0, 0.95)
	if def.get("proc_poison", false):
		return Color(0.55, 1.0, 0.6, 0.95)
	return Color(1.0, 0.9, 0.55, 0.95)

## 枪口闪光（远程武器开火反馈）：叠加发光的径向光斑
func _setup_muzzle_flash() -> void:
	muzzle_flash = Sprite2D.new()
	var tex := load("res://assets/art/light_radial.png") as Texture2D
	if tex == null:
		return
	muzzle_flash.texture = tex
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	muzzle_flash.material = mat
	muzzle_flash.position = muzzle_point.position
	muzzle_flash.z_index = 6
	muzzle_flash.visible = false
	add_child(muzzle_flash)

## 本体短促亮闪（近战挥砍/远程开火共用，微光圈同步亮起）——零 Tween 分配版：
## 记下起点色，衰减在 _tick_fire_fx 逐帧插值回白/回基线
func _flash_sprite(color: Color, dur: float) -> void:
	sprite.modulate = color
	_flash_from = color
	_flash_total = maxf(dur, 0.0001)
	_flash_t = _flash_total
	if aura_sprite != null:
		aura_sprite.modulate.a = AURA_FLASH_A

## 开火视觉帧内状态机推进（后坐/沉身、本体亮闪、枪口闪光、光晕回位）
## 在 _process 每渲染帧调用；全部闭式插值，不再创建 Tween
func _tick_fire_fx(delta: float) -> void:
	# 1. 后坐（EXPO 急退 + BACK 弹回，曲线与原双段 Tween 等价）
	if _lunge_t >= 0.0:
		_lunge_t += delta
		var t: float = _lunge_t
		if t <= _lunge_out_time:
			# 急退段：EXPO EASE_OUT
			var k: float = t / _lunge_out_time
			position = _lunge_orig.lerp(_lunge_out, 1.0 - pow(2.0, -10.0 * k))
		elif t < _lunge_total:
			# 弹回段：TRANS_BACK EASE_OUT 过冲回位
			var k2: float = (t - _lunge_out_time) / (_lunge_total - _lunge_out_time)
			const BACK_S := 1.70158
			var e: float = 1.0 + (BACK_S + 1.0) * pow(k2 - 1.0, 3.0) + BACK_S * pow(k2 - 1.0, 2.0)
			position = _lunge_out.lerp(_lunge_orig, e)
		else:
			position = _lunge_orig
			_lunge_t = -1.0
			if _lunge_ends_attack:
				is_attacking = false
	# 2. 本体亮闪回白
	if _flash_t > 0.0:
		_flash_t = maxf(_flash_t - delta, 0.0)
		var fk := 1.0 - _flash_t / _flash_total
		sprite.modulate = _flash_from.lerp(Color.WHITE, fk)
	# 3. 光晕回基线（回位后由待机呼吸脉动接管）
	if aura_sprite != null and aura_sprite.modulate.a > AURA_BASE_A and _lunge_t < 0.0:
		aura_sprite.modulate.a = maxf(aura_sprite.modulate.a - delta * (AURA_FLASH_A - AURA_BASE_A) / MUZZLE_TIME, AURA_BASE_A)
	# 4. 枪口闪光：放大 + 淡出 + 到点隐藏
	if _muzzle_t > 0.0:
		_muzzle_t = maxf(_muzzle_t - delta, 0.0)
		var mk := 1.0 - _muzzle_t / MUZZLE_TIME
		muzzle_flash.scale = Vector2.ONE * lerpf(_muzzle_scale0, 0.85, mk)
		muzzle_flash.modulate.a = lerpf(0.95, 0.0, mk)
		if _muzzle_t <= 0.0:
			muzzle_flash.visible = false

## 发起一次后坐/沉身演出（_perform_projectile_attack 与 _perform_turret_attack 共用）
## ends_attack=true 时演出走完代释放 is_attacking（替代原 Tween 的收尾回调）
func _begin_lunge(out_offset: Vector2, out_time: float, back_time: float, ends_attack: bool) -> void:
	_lunge_orig = position
	_lunge_out = _lunge_orig + out_offset
	_lunge_out_time = out_time
	_lunge_total = out_time + back_time
	_lunge_t = 0.0
	_lunge_ends_attack = ends_attack

func _process(delta: float) -> void:
	if GameManager.is_game_over:
		return

	_tick_fire_fx(delta)
	cooldown_timer -= delta
	bob_phase += delta * 3.5

	# 1. 索敌：优先保留 Player 统筹分配的智能多向目标；若目标失效或脱离射程则安全回退
	# 空目标与脱程重查统一走 15Hz + 错相：空目标分支曾逐渲染帧跑宽相位查询
	# （8 法器 × 60fps ≈ 480 次/秒，武器一多就掉帧的头号热点）；
	# 15Hz 仍快于 Player 10Hz 统筹分配，不影响开火节奏
	if current_target == null or not is_instance_valid(current_target):
		_retarget_phase -= delta
		if _retarget_phase <= 0.0:
			_retarget_phase = RETARGET_INTERVAL
			current_target = _find_target()
	else:
		var player = GameManager.player
		if player != null:
			var max_reach = attack_range * _range_mult() * 1.2
			if GameBalance.elliptical_distance(current_target.global_position - player.global_position) > max_reach:
				_retarget_phase -= delta
				if _retarget_phase <= 0.0:
					_retarget_phase = RETARGET_INTERVAL
					current_target = _find_target()

		# 2. 动态轨道：有目标时沿轨道滑向目标方位（自动换位），无目标时回归基础槽位
		if not is_attacking:
			player = GameManager.player
			var desired_angle = base_angle
			var track_speed = 4.0
			if current_target != null and player != null:
				desired_angle = (current_target.global_position - player.global_position).angle() + spread_angle
				track_speed = 8.0
			dynamic_angle = lerp_angle(dynamic_angle, desired_angle, minf(delta * track_speed, 1.0))
			var orbit_pos = Vector2(cos(dynamic_angle) * orbit_extents.x, sin(dynamic_angle) * orbit_extents.y)
			var bob_y = sin(bob_phase) * 3.0
			position = position.lerp(orbit_pos + Vector2(0, bob_y), minf(delta * 14.0, 1.0))

			# 待机器身微呼吸与灵光脉动
			var breath := sin(bob_phase) * 0.02
			sprite.scale = _base_sprite_scale * (1.0 + breath)
			if aura_sprite != null:
				aura_sprite.modulate.a = 0.12 + sin(bob_phase) * 0.05

	# 3. 朝向：有目标面向目标；无目标朝轨道外（贴图补偿与镜像都在 _apply_facing 一处算）
	if not is_attacking:
		if current_target != null:
			var target_angle = _aim_at(current_target.global_position)
			_apply_facing(lerp_angle(rotation, target_angle, minf(delta * 15.0, 1.0)))
		else:
			_apply_facing(lerp_angle(rotation, dynamic_angle, minf(delta * 6.0, 1.0)))

		# 4. 攻击
		if cooldown_timer <= 0.0 and not is_attacking:
			if behavior == WeaponData.Behavior.TURRET or current_target != null:
				_perform_attack()

	# 5. 束流推进（BEAM/CONE）：几何随朝向逐帧走，结算按 TICK 节拍
	if _channel_on:
		_tick_channel(delta)

func _perform_attack() -> void:
	cooldown_timer = attack_cooldown * GameManager.get_effective_attack_speed_mult()
	match behavior:
		WeaponData.Behavior.MELEE:
			_perform_melee_attack()
		WeaponData.Behavior.PROJECTILE:
			_perform_projectile_attack()
		WeaponData.Behavior.BURST:
			_perform_burst_attack()
		WeaponData.Behavior.TURRET:
			_perform_turret_attack()
		WeaponData.Behavior.SWEEP:
			_perform_sweep_attack()
		WeaponData.Behavior.BEAM:
			_perform_channel_attack()
		WeaponData.Behavior.CONE:
			_perform_channel_attack()

func _perform_turret_attack() -> void:
	is_attacking = true
	var player = GameManager.player
	var spawn_pos: Vector2 = player.global_position if player != null else global_position

	var alive: Array[TurretUnit] = []
	for t in active_turrets:
		if t != null and is_instance_valid(t) and not t._is_dying:
			alive.append(t)
	active_turrets = alive

	var cap := int(def.get("turret_cap", 2)) + (star - 1)
	if active_turrets.size() >= cap:
		var oldest: TurretUnit = active_turrets.pop_front() as TurretUnit
		if oldest != null and is_instance_valid(oldest):
			oldest.dismiss()

	var turret := turret_scene.instantiate() as TurretUnit
	turret.setup(weapon_def_id, star)
	turret.global_position = spawn_pos + Vector2(GameManager.rng.randf_range(-22, 22), GameManager.rng.randf_range(-16, 16))
	var battle_layer: Node = player.get_parent() if (player != null and player.get_parent() != null) else (get_tree().current_scene if get_tree() != null else self)
	battle_layer.add_child(turret)
	active_turrets.append(turret)

	# 召唤沉身演出：下沉 + 金光亮闪 → 弹性回正（帧内状态机，零 Tween）
	_begin_lunge(TURRET_DIP, 0.08, 0.12, true)
	_flash_sprite(Color(1.4, 1.3, 0.8), 0.12)

# ==================== 持续束流（BEAM 光束 / CONE 喷吐） ====================

## 束流起喷：不冻结轨道（不设 is_attacking），挂上持续时长与起手反馈；
## 冷却循环每转一圈回来续喷，所以起手音只在从收束态点燃时放（连续喷不叠音）
func _perform_channel_attack() -> void:
	if not _channel_on:
		_channel_on = true
		_beam_need_cast = true
		AudioManager.play_sfx(WeaponData.sfx_for(weapon_def_id), 0.9)
		_flash_sprite(Color(1.4, 1.25, 1.5), 0.14)
	_channel_left = CHANNEL_HOLD

func _channel_stop() -> void:
	_channel_on = false
	_channel_left = 0.0
	if beam_renderer != null:
		beam_renderer.beam_off()
	if cone_renderer != null:
		cone_renderer.cone_off()

func _tick_channel(delta: float) -> void:
	_channel_left -= delta
	if _channel_left <= 0.0 or current_target == null or not is_instance_valid(current_target):
		_channel_stop()
		return
	var reach := attack_range * _range_mult()
	_channel_tick -= delta
	if behavior == WeaponData.Behavior.BEAM:
		_beam_cast_phase -= delta
		if _beam_need_cast:
			_beam_need_cast = false
			_beam_cast_phase = BEAM_CAST_INTERVAL
			_beam_len = _beam_cast_length(reach)
			_beam_len_target = _beam_len
		elif _beam_cast_phase <= 0.0:
			_beam_cast_phase = BEAM_CAST_INTERVAL
			_beam_len_target = _beam_cast_length(reach)
		_beam_len = lerpf(_beam_len, _beam_len_target, minf(delta * 14.0, 1.0))
		# 星升视觉膨胀收一档（2026-10-15 克制化 0.18→0.08）：判定盒（_beam_deal_damage
		# 恒 BEAM_HALF_WIDTH*2.0）本就不乘它，纯视觉；★3 视觉宽 13.6→11.6，不再比判定宽出 1/3
		var w_mult := 1.0 + 0.08 * float(star - 1)
		beam_renderer.beam_on(_beam_len, BEAM_HALF_WIDTH * 2.0 * w_mult, _get_aura_color())
		if _channel_tick <= 0.0:
			_channel_tick = BEAM_TICK
			_beam_deal_damage()
	else:
		# 锥长从器口起算：判定圆心 == 器口、半径 == 锥长，渲染器同源下发
		var cone_len := maxf(40.0, reach - muzzle_len)
		cone_renderer.cone_on(cone_len, cone_len * tan(deg_to_rad(CONE_HALF_ANGLE)))
		if _channel_tick <= 0.0:
			_channel_tick = CONE_TICK
			_cone_deal_damage(cone_len)

## 光束长度：从器口沿发射帧 +X 打射线，命中首个受击区即截断（光束被第一个敌人挡住），
## 否则打满射程。返回值为判定与渲染的唯一真话（画多远==判多远）。
func _beam_cast_length(reach: float) -> float:
	var max_len := maxf(40.0, reach - muzzle_len)
	var from := muzzle_point.global_position
	var dir := Vector2.RIGHT.rotated(global_rotation)
	if _beam_ray_query == null:
		_beam_ray_query = PhysicsRayQueryParameters2D.create(from, from + dir * max_len, 4, [])
		_beam_ray_query.collide_with_areas = true
		_beam_ray_query.hit_from_inside = true
	else:
		_beam_ray_query.from = from
		_beam_ray_query.to = from + dir * max_len
	var hit := get_world_2d().direct_space_state.intersect_ray(_beam_ray_query)
	if hit.is_empty():
		return max_len
	return maxf(8.0, from.distance_to(hit["position"]))

## 光束 tick 结算：矩形沿束查询，线上敌人一起吃；tick 伤害 = 整管 × TICK/有效冷却
func _beam_deal_damage() -> void:
	if _beam_shape == null or _beam_query == null:
		_beam_shape = RectangleShape2D.new()
		_beam_query = PhysicsShapeQueryParameters2D.new()
		_beam_query.shape = _beam_shape
		_beam_query.collision_mask = 4
		_beam_query.collide_with_areas = true
	var from := muzzle_point.global_position
	var dir := Vector2.RIGHT.rotated(global_rotation)
	var judge_len := _beam_len + BEAM_HIT_OVERHANG
	_beam_shape.size = Vector2(judge_len, BEAM_HALF_WIDTH * 2.0)
	_beam_query.transform = Transform2D(global_rotation, from + dir * judge_len * 0.5)
	var results := get_world_2d().direct_space_state.intersect_shape(_beam_query, 16)
	var eff_cd: float = maxf(0.05, attack_cooldown * GameManager.get_effective_attack_speed_mult())
	var tick_dmg := _final_damage() * BEAM_TICK / eff_cd
	var kb_force := WeaponData.knockback_for(weapon_def_id, 60.0) * 0.15  # 持续束只留一点点推感
	for res in results:
		var col = res["collider"]
		var parent = col.get_parent() if col != null else null
		if parent != null and parent.has_method("take_damage"):
			var enemy = parent
			var dmg := tick_dmg
			var is_crit: bool = GameManager.roll_crit()
			if is_crit:
				dmg *= GameManager.get_crit_mult()
			dmg *= GameManager.elite_damage_mult_for(enemy)
			var knock: Vector2 = GameManager.knockback_vec(global_position, enemy.global_position, kb_force)
			enemy.take_damage(dmg, knock, is_crit)
			GameManager.try_lifesteal(behavior)

## 喷吐 tick 结算：器口为圆心查锥长半径的圆，再按半角过滤（贴脸宽容与横扫同口径），
## 命中挂灼烧。tick 伤害同源折算 ⇒ 纸面 dmg/cd + 常驻灼烧即实伤。
func _cone_deal_damage(cone_len: float) -> void:
	var from := muzzle_point.global_position
	var aim_dir := Vector2.RIGHT.rotated(global_rotation)
	var half_ang := deg_to_rad(CONE_HALF_ANGLE)
	var results := _query_enemies(cone_len, from, 24)
	var eff_cd: float = maxf(0.05, attack_cooldown * GameManager.get_effective_attack_speed_mult())
	var cycle_dmg := _final_damage()
	var tick_dmg := cycle_dmg * CONE_TICK / eff_cd
	var kb_force := WeaponData.knockback_for(weapon_def_id, 95.0) * 0.25
	var proc_burn: bool = def.get("proc_burn", false)
	var burn_dps := cycle_dmg * float(def.get("burn_ratio", 0.4))
	var burn_dur := float(def.get("burn_dur", 2.5))
	for res in results:
		var col = res["collider"]
		var parent = col.get_parent() if col != null else null
		if parent != null and parent.has_method("take_damage"):
			var enemy = parent
			var to_enemy: Vector2 = enemy.global_position - from
			if to_enemy.length() > SWEEP_CLOSE_GRACE and absf(aim_dir.angle_to(to_enemy)) > half_ang:
				continue
			var dmg := tick_dmg
			var is_crit: bool = GameManager.roll_crit()
			if is_crit:
				dmg *= GameManager.get_crit_mult()
			dmg *= GameManager.elite_damage_mult_for(enemy)
			var knock: Vector2 = GameManager.knockback_vec(global_position, enemy.global_position, kb_force)
			enemy.take_damage(dmg, knock, is_crit)
			ProcStatus.apply(enemy, proc_burn, burn_dps, burn_dur, 0.0, 0.0, false, 0.0, 0.0)
			GameManager.try_lifesteal(behavior)

func _final_damage() -> float:
	var stat_bonus: float = GameManager.get_weapon_stat_bonus(weapon_def_id, star)
	return (base_damage + stat_bonus) * GameManager.get_weapon_damage_mult() * GameManager.synergy_damage_mult * GameManager.shadow_amp_mult * GameManager.buff_damage_mult * GameManager.cultivator_damage_mult(weapon_def_id) * GameManager.element_damage_mult(weapon_def_id) * GameManager.get_multi_weapon_damage_mult()

func _perform_projectile_attack() -> void:
	is_attacking = true

	var aim_dir = Vector2.RIGHT.rotated(rotation)
	if current_target != null:
		aim_dir = (current_target.global_position - global_position).normalized()
		# 开火这一帧就把发射帧拧到目标方位：贴图补偿跟着走，剑尖与出膛方向同轴
		_apply_facing(aim_dir.angle())

	# 后坐动画：极速后座冲击（0.04s）+ 弹性回正，凸显远程出膛爆发力（帧内状态机，零 Tween）
	_begin_lunge(-aim_dir * RECOIL_DIST, RECOIL_BACK_TIME, RECOIL_RETURN_TIME, true)

	# 开火反馈：枪口闪光 + 本体亮闪（状态机版本：起火时记初值，_tick_fire_fx 推进）
	if muzzle_flash != null:
		muzzle_flash.rotation = randf() * TAU
		_muzzle_scale0 = randf_range(0.42, 0.52)
		muzzle_flash.scale = Vector2.ONE * _muzzle_scale0
		muzzle_flash.modulate = _muzzle_color()
		muzzle_flash.visible = true
		_muzzle_t = MUZZLE_TIME
	_flash_sprite(Color(1.35, 1.35, 1.35), 0.12)

	var p_count: int = maxi(1, int(def.get("projectile_count", 1)))
	var tags: Array = WeaponData.tags_of(weapon_def_id)
	if tags.has("talisman") or int(def.get("behavior", -1)) == WeaponData.Behavior.PROJECTILE:
		p_count += int(round(GameManager.item_hook_sum("projectile_count_bonus")))
	var p_spread: float = float(def.get("spread_angle", 0.2))
	var p_bounce: int = int(def.get("bounce_count", 0))
	var final_dmg: float = _final_damage()
	# 弹丸外观按武器归位（2026-10-09 才真正接上）：WeaponData 的 bullet / bullet_scale / bullet_spin
	# 三个字段 2026-10-08 就写进表里了，但出膛那一圈从来没读它 —— 运行时五把远程武器
	# 打出去的全是 BladeProjectile.tscn 里那张公共火符（用户口径：「不知道从哪里发射出来的」）。
	# 2026-10-16 起改为 setup 期解析缓存（_bullet_tex 等），开火热路径零资源查找。
	# 逐发锁定：一次三发的武器，每一发各咬一个最近的敌人。
	# 旧写法三发全按同一个 aim_dir 扇形散开 ⇒ 只剩一个敌人时两边那两发飞过头顶（仿真：350px
	# 处散布侧偏 70+px，而判定只有 7px + 受击圈 15px），群怪时又因为不追踪而大量空放。
	# 现在"扇形疾射…贯穿群敌"按文案兑现：出膛照旧扇形错开，各自追上自己咬定的那一个；
	# 场上只剩一个敌人时三发也统统归它 —— 单点爆发不再靠运气。
	var volley: Array[Node2D] = _volley_targets(p_count)

	for idx in range(p_count):
		# 弹丸走对象池（2026-10-10 性能优化）：不再 instantiate/queue_free 高频往复
		var p := BladeProjectile.acquire_or_new(projectile_scene, get_tree().current_scene)
		p.global_position = muzzle_point.global_position
		var offset_ang := 0.0
		if p_count > 1:
			offset_ang = (float(idx) - float(p_count - 1) * 0.5) * p_spread
		# 出膛方向与追踪：每发优先分配不同敌人；超出目标数的多余弹丸不再全部追踪同一小怪（防散射变秒杀炮），
		# 精英/Boss 允许最多 2 发锁定，其余保持扇形散角飞出。
		var shot_dir: Vector2 = aim_dir
		var locked: Node2D = null
		if idx < volley.size():
			locked = volley[idx]
		elif not volley.is_empty():
			var first_t: Node2D = volley[0]
			if first_t != null and is_instance_valid(first_t) and first_t.get("is_elite") == true and idx == 1:
				locked = first_t
		if locked != null and is_instance_valid(locked):
			var to_lock: Vector2 = locked.global_position - muzzle_point.global_position
			if to_lock.length_squared() > 1.0:
				shot_dir = to_lock.normalized()
		p.homing_target = locked
		p.direction = shot_dir.rotated(offset_ang)
		p.damage = final_dmg
		p.knockback_base = WeaponData.knockback_for(weapon_def_id, 140.0)
		p.pierce_left = WeaponData.capped_pierce(pierce + GameManager.bonus_pierce)
		p.bounce_left = p_bounce
		p.bullet_texture = _bullet_tex
		p.bullet_scale = _bullet_scale
		p.spin = _bullet_spins
		# 吸血分档：弹丸按远程系数（机关炮台在 TurretUnit 里另填 TURRET）
		p.source_behavior = WeaponData.Behavior.PROJECTILE
		if def.get("proc_burn", false):
			p.proc_burn = true
			p.burn_dps = final_dmg * float(def.get("burn_ratio", 0.4))
			p.burn_dur = float(def.get("burn_dur", 3.0))
		if float(def.get("proc_chill", 0.0)) > 0.0:
			p.proc_chill = float(def.get("proc_chill", 0.35))
			p.chill_dur = float(def.get("chill_dur", 2.0))
		if def.get("proc_poison", false):
			p.proc_poison = true
			p.poison_dps = final_dmg * float(def.get("poison_ratio", 0.3))
			p.poison_dur = float(def.get("poison_dur", 2.5))
		# 池化后 _ready 先于字段赋值跑过，由 activate 按当前字段值统一铺视觉与物理状态
		p.activate()
		# 射程倍率必须在 activate 之后乘：activate 会把 lifetime 重置回 BASE_LIFETIME，
		# 之前乘会被覆盖成死代码
		p.lifetime *= _range_mult()

	AudioManager.play_sfx(WeaponData.sfx_for(weapon_def_id))

func _perform_burst_attack() -> void:
	is_attacking = true

	var target_pos = global_position + Vector2.RIGHT.rotated(rotation) * 30.0
	if current_target != null and is_instance_valid(current_target):
		target_pos = current_target.global_position

	var strike_dir := (target_pos - global_position).normalized()
	# 发射帧对准落雷点：upright 的重器（宝灯/法牌/大印）本体保持竖直，只让雷从"朝目标那一侧的器口"引出
	_apply_facing(strike_dir.angle())
	var orig_pos := position
	var cast_pos := orig_pos + Vector2(0.0, -16.0)

	# 施法演出：法牌升起蓄力、金光微颤 → 引雷落于目标 → 前突回落
	# 旧写法在这儿硬编码 orb_hit（钟），把表里配的 thunder_strike 整个架空了 ——
	# 六把落雷系武器听起来全是「敲钟 + 祝福铃」。取音一律回表。
	AudioManager.play_sfx(WeaponData.sfx_for(weapon_def_id), BURST_CAST_SCALE)
	var tw = create_tween()
	tw.tween_property(self, "position", cast_pos, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "scale", Vector2(1.22, 1.22), 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(sprite, "modulate", CHARGE_GLOW, 0.10)
	for i in range(3):
		tw.tween_property(self, "position", cast_pos + Vector2(randf_range(-2.5, 2.5), randf_range(-2.5, 2.5)), 0.035)
	tw.tween_callback(func(): _spawn_lightning(target_pos))
	tw.tween_property(self, "position", orig_pos + strike_dir * 12.0, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(sprite, "modulate", Color(1.9, 1.85, 1.45), 0.05)
	tw.tween_property(self, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "position", orig_pos, 0.15).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(sprite, "modulate", Color.WHITE, 0.18)
	tw.tween_callback(func(): is_attacking = false)

## 引雷：锯齿闪电从武器射向落雷点，落雷爆发在 ThunderBurst.activate() 里结算
func _spawn_lightning(target_pos: Vector2) -> void:
	# 屏外落点不引雷：电柱从屏内的器口一路画到屏外，屏内那一段就是「凭空一道白光」。
	# 伤害照常由 ThunderBurst 结算（落点视觉在屏外本就不可见，爆散环另有 JuiceEffect 视口兜底）。
	var player: Node2D = GameManager.player
	var battle_layer: Node = player.get_parent() if (player != null and player.get_parent() != null) else (get_tree().current_scene if get_tree() != null else self)
	if player == null or GameBalance.is_in_viewport(target_pos, player.global_position):
		var bolt := LightningBolt.acquire(battle_layer)
		var w_mult := 1.0 + 0.18 * float(star - 1)
		var b_tint: Color = def.get("burst_tint", LightningBolt.GLOW_COLOR)
		bolt.activate(muzzle_point.global_position, target_pos, b_tint, w_mult)

	# 落雷走对象池（2026-10-11 第 6 波卡顿优化）：acquire → 写字段 → activate 起爆
	var burst = ThunderBurst.acquire(battle_layer, burst_scene)
	burst.global_position = target_pos
	burst.radius = burst_radius * _range_mult()
	var final_dmg := _final_damage()
	burst.damage = final_dmg
	burst.knockback_base = WeaponData.knockback_for(weapon_def_id, 200.0)
	burst.tint = def.get("burst_tint", burst.tint)
	burst.burst_kind = String(def.get("burst_kind", "thunder"))
	# 落点音必须在 activate() 之前下发：activate 里就播它
	burst.sfx_impact_key = WeaponData.sfx_impact_for(weapon_def_id)
	if def.get("proc_burn", false):
		burst.proc_burn = true
		burst.burn_dps = final_dmg * float(def.get("burn_ratio", 0.5))
		burst.burn_dur = float(def.get("burn_dur", 3.0))
	if float(def.get("proc_chill", 0.0)) > 0.0:
		burst.proc_chill = float(def.get("proc_chill", 0.0))
		burst.chill_dur = float(def.get("chill_dur", 2.0))
	burst.activate()

func _perform_melee_attack() -> void:
	is_attacking = true

	var aim_dir = Vector2.RIGHT.rotated(rotation)
	if current_target != null:
		aim_dir = (current_target.global_position - global_position).normalized()

	var aim_angle = aim_dir.angle()
	var orig_pos = position
	var windup_pos = orig_pos - aim_dir * 8.0
	var thrust_pos = orig_pos + aim_dir * (MELEE_THRUST * _melee_thrust_mult())

	# 挥砍弧光：终态 = 月牙轴心摆在判定圆心、缩放取 判定半径/月牙外缘 ⇒ 月牙外缘 == 那一帧查询圆的边界。
	# 月牙自身张角 ±70°，本体从 aim-swing 扫到 aim+swing（swing ≤ 60°）时它一直罩着瞄准轴，
	# 所以打出去的那一下和看得到的那一片是同一处。
	# 出生几何反解成"内缘贴剑尖"（muzzle_len），打击帧再扫放到终态 —— 剑气出鞘，不是远处凭空冒出。
	var swing := deg_to_rad(45.0) * arc_scale
	_apply_facing(aim_angle - swing)
	if _slash_tween != null and _slash_tween.is_valid():
		_slash_tween.kill()  # 极速攻速下上一次扫放没走完就得让位，防新旧两个 tween 抢同一个节点
	var slash_scale_end := _melee_arc_radius() / SLASH_ART_OUTER
	var slash_scale_in := clampf(slash_scale_end * 0.35, 26.0 / SLASH_ART_OUTER, slash_scale_end)
	var slash_pos_end := Vector2(MELEE_LUNGE, 0.0)
	var slash_pos_in := Vector2(muzzle_len + SLASH_SPAWN_INSET - SLASH_ART_INNER * slash_scale_in, 0.0)
	slash_sprite.visible = false
	slash_sprite.modulate.a = 0.0
	slash_sprite.position = slash_pos_in
	slash_sprite.scale = Vector2.ONE * slash_scale_in
	slash_sprite.rotation = 0.0

	# 三段式近战节奏：前摇微撤蓄势 (0.05s) → 极速瞬扫涂抹 (0.04s) → 弹性卸力回正 (0.13s)
	# 音效跟着这套节奏分两层：起手一声破空（动作，挥空也得有），咬到肉才补材质声（战果）。
	# 旧写法只有一层、且挂在打击帧 —— 于是一把剑和一根棍子听起来完全一样。
	AudioManager.play_sfx(WeaponData.sfx_for(weapon_def_id), MELEE_WHOOSH_SCALE)
	var tw = create_tween()
	# 1. 蓄力前摇（Anticipation）：刀身轻微后撤、微缩积蓄张力
	tw.tween_property(self, "position", windup_pos, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "scale", Vector2(0.92, 1.08), 0.05)

	# 2. 打击瞬发（Active）：爆发极速横扫，先结算伤害、再只在咬到肉时点亮月牙刀光
	# 2026-10-11 挥空门控：旧写法先亮月牙后结算，于是一整片剑气先在空地上冒出来 ——
	# 空挥时（目标在前摇 0.05s 里被另一把武器打死或击飞出判定圆，或 15Hz 脱程重查窗口里
	# 仍锁着 1.2× 射程外的目标）月牙照样满亮扫放，「打空气」全在这一句。
	# 判定几何一个字没动（画多大==判多大）：空挥保留完整突刺动作、器身闪光与破空声，
	# 命中才补月牙/材质声/反冲。
	tw.chain().tween_callback(func():
		_flash_sprite(Color(1.5, 1.5, 1.5), 0.12)
		var hits := _deal_melee_damage(aim_dir)
		if hits > 0:
			_try_spawn_earth_crack(global_position + aim_dir * MELEE_LUNGE, _melee_arc_radius() * 0.85)
			slash_sprite.visible = true
			slash_sprite.modulate.a = 1.0
			# 剑气出鞘：从剑尖处全亮扫放到判定几何（终态 == 查询圆边界），落点亮一拍再急速淡出；
			# 显隐生命周期整段归这条 tween 管（收招回调不再代管隐藏，防把淡出拦腰截断）
			_slash_tween = create_tween()
			_slash_tween.set_parallel(true)
			_slash_tween.tween_property(slash_sprite, "position", slash_pos_end, SLASH_SWEEP_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_slash_tween.tween_property(slash_sprite, "scale", Vector2.ONE * slash_scale_end, SLASH_SWEEP_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_slash_tween.chain().tween_property(slash_sprite, "modulate:a", 0.0, SLASH_FADE_TIME)
			_slash_tween.chain().tween_callback(func(): slash_sprite.visible = false)
			# 材质层只在真咬到肉时响；空挥只剩 50ms 前那一声破空
			AudioManager.play_sfx(WeaponData.sfx_impact_for(weapon_def_id), MELEE_IMPACT_SCALE)
			# 刀刃入肉阻力感：武器微反冲回弹
			position -= aim_dir * 4.5
	)
	tw.tween_property(self, "position", thrust_pos, 0.04).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "rotation", aim_angle + swing, 0.04).set_trans(Tween.TRANS_EXPO)
	tw.parallel().tween_property(self, "scale", Vector2(1.15, 0.92), 0.04)

	# 3. 卸力后摇（Recovery）：TRANS_BACK 弹性回正至环绕槽位
	tw.chain().set_parallel(true)
	tw.tween_property(self, "position", orig_pos, 0.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2.ONE, 0.13).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_callback(func():
		is_attacking = false
	)

func _deal_melee_damage(aim_dir: Vector2) -> int:
	var results := _query_enemies(_melee_arc_radius(), global_position + aim_dir * MELEE_LUNGE, 24)
	var hit_count := 0
	# 返回值语义 = 「可见命中数」：屏外目标的伤害/击退/异常照常结算，但不计入计数——
	# 打击帧回调拿它门控月牙/材质声/反冲，咬到看不见的目标时不许在屏内亮刀光
	var player: Node2D = GameManager.player
	var vp_center: Vector2 = player.global_position if player != null else global_position
	# 整刀属性管线只算一次：同刀乘区为常量（最多 24 目标共享），避免逐目标重算 _final_damage（9-13 次 item_hook_sum + 20 键 dict + equipped_cleanup 全子节点遍历）
	var base_dmg := _final_damage()
	# 2026-10-14 风险溢价：近战击退兜底 240→280（贴脸换控场），弹丸仍 140
	var kb_force := WeaponData.knockback_for(weapon_def_id, 280.0)
	# 五行异常开关与近战吸血同为整刀常量：原来逐目标 item_hook_sum 全量遍历 items，
	# 24 目标 × 8 武器每挥砍近千次字典查找。注意异常施加保持 has_method 鸭类型——
	# 武器脚本硬引用 EnemyBase（as EnemyBase）实测会把弹丸 preload 打成空 PackedScene（循环类依赖坑）
	var proc_burn: bool = def.get("proc_burn", false)
	var proc_chill: float = float(def.get("proc_chill", 0.0))
	var proc_poison: bool = def.get("proc_poison", false)
	var any_proc: bool = proc_burn or proc_chill > 0.0 or proc_poison
	var flat_ls: float = GameManager.item_hook_sum("melee_lifesteal_flat")
	var can_flat_heal: bool = flat_ls > 0.0 and player != null and is_instance_valid(player) and player.has_method("heal")

	for res in results:
		var col = res["collider"]
		var parent = col.get_parent() if col != null else null
		if parent != null and parent.has_method("take_damage"):
			var enemy = parent
			var dmg := base_dmg
			var is_crit: bool = GameManager.roll_crit()
			if is_crit:
				dmg *= GameManager.get_crit_mult()
			dmg *= GameManager.elite_damage_mult_for(enemy)
			var knock = GameManager.knockback_vec(global_position, enemy.global_position, kb_force)
			enemy.take_damage(dmg, knock, is_crit)
			if GameBalance.is_in_viewport(enemy.global_position, vp_center):
				hit_count += 1
			if any_proc:
				ProcStatus.apply(enemy, proc_burn,
					dmg * float(def.get("burn_ratio", 0.45)), float(def.get("burn_dur", 3.0)),
					proc_chill, float(def.get("chill_dur", 2.5)),
					proc_poison, dmg * float(def.get("poison_ratio", 0.35)), float(def.get("poison_dur", 3.0)))
			GameManager.try_lifesteal(behavior)
			# 开山重刃谱：近战命中额外吸收生命
			if can_flat_heal:
				player.heal(flat_ls, true)
	# 一挥扫中一片也只算「打了几下」，不是「打了几件事」：
	# 震屏与顿帧由 EnemyBase.take_damage 按目标重要性发放，武器侧不再重复叠加
	return hit_count

# ==================== 横扫（SWEEP）：前方真扇形，沉重三段 ====================

## 横扫扇形半径 —— 扇面外缘与 _deal_sweep_damage 的查询半径共用这一个数（画多大==判多大）
func _sweep_arc_radius() -> float:
	var wide_bonus: float = (1.0 + GameManager.item_hook_sum("wide_range_mult")) if WeaponData.tags_of(weapon_def_id).has("wide") else 1.0
	return SWEEP_ARC_RADIUS * arc_scale * _range_mult() * wide_bonus

## 横扫三段：深蓄力（0.09s）→ 大幅扫出（0.06s，本体扫过整片 160° 扇形）→ 沉重收势（0.17s）。
## 挥空门控与近战同口径：扇面/材质声/反冲只在真咬到肉时发，空挥保留完整动作与破空声。
func _perform_sweep_attack() -> void:
	is_attacking = true

	var aim_dir: Vector2 = Vector2.RIGHT.rotated(rotation)
	if current_target != null:
		aim_dir = (Vector2(current_target.global_position) - global_position).normalized()
	var aim_angle := aim_dir.angle()
	var orig_pos := position
	var windup_pos: Vector2 = orig_pos - aim_dir * 12.0
	var thrust_pos: Vector2 = orig_pos + aim_dir * (SWEEP_THRUST * _melee_thrust_mult())

	# 起手预置到扇形前缘，打击帧扫到后缘 —— 横扫本体真的扫过整片扇形
	var half_ang := deg_to_rad(SWEEP_HALF_ANGLE)
	_apply_facing(aim_angle - half_ang)
	if _sweep_slash_tween != null and _sweep_slash_tween.is_valid():
		_sweep_slash_tween.kill()  # 与 _slash_tween 同一防抢道约定
	var reach := _sweep_arc_radius()
	if sweep_sprite != null:
		sweep_sprite.visible = false
		sweep_sprite.modulate.a = 0.0

	AudioManager.play_sfx(WeaponData.sfx_for(weapon_def_id), MELEE_WHOOSH_SCALE)
	var tw = create_tween()
	# 1. 蓄力前摇：重器后撤更深、压扁拉长更夸张（横扫的「沉」先在蓄力里交代）
	tw.tween_property(self, "position", windup_pos, SWEEP_WINDUP).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "scale", Vector2(0.88, 1.12), SWEEP_WINDUP)
	# 2. 横扫瞬发：先结算扇形判定，咬到肉才亮金色扇面 + 低沉材质声 + 反冲
	tw.chain().tween_callback(func():
		_flash_sprite(Color(1.5, 1.5, 1.5), 0.14)
		var hits := _deal_sweep_damage(aim_dir)
		if hits > 0:
			_try_spawn_earth_crack(global_position + aim_dir * (reach * 0.55), reach * 0.75)
			if sweep_sprite != null:
				# 扇面从判定几何的 50% 扩张扫放到 100%、同时从偏前缘 18° 转正到瞄准轴 ——
				# 「一扫一大片」的拖扫感；终态外缘 == 判定半径、张角 == 判定半角（同源不变量）
				sweep_sprite.global_position = global_position
				sweep_sprite.global_rotation = aim_angle - deg_to_rad(18.0)
				sweep_sprite.scale = Vector2.ONE * (reach / SWEEP_ART_OUTER) * 0.5
				sweep_sprite.visible = true
				sweep_sprite.modulate.a = 1.0
				_sweep_slash_tween = create_tween()
				_sweep_slash_tween.set_parallel(true)
				_sweep_slash_tween.tween_property(sweep_sprite, "scale", Vector2.ONE * (reach / SWEEP_ART_OUTER), SWEEP_SLASH_IN_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				_sweep_slash_tween.tween_property(sweep_sprite, "global_rotation", aim_angle, SWEEP_SLASH_IN_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				_sweep_slash_tween.chain().tween_property(sweep_sprite, "modulate:a", 0.0, SWEEP_SLASH_FADE)
				_sweep_slash_tween.chain().tween_callback(func(): sweep_sprite.visible = false)
				AudioManager.play_sfx(WeaponData.sfx_impact_for(weapon_def_id), MELEE_IMPACT_SCALE, SWEEP_IMPACT_PITCH)
				position -= aim_dir * SWEEP_RECOIL
	)
	tw.tween_property(self, "position", thrust_pos, SWEEP_STRIKE).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "rotation", aim_angle + half_ang, SWEEP_STRIKE).set_trans(Tween.TRANS_EXPO)
	tw.parallel().tween_property(self, "scale", Vector2(1.22, 0.85), SWEEP_STRIKE)
	# 3. 沉重收势：回弹时间比近战长一档
	tw.chain().set_parallel(true)
	tw.tween_property(self, "position", orig_pos, SWEEP_RECOVER).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2.ONE, SWEEP_RECOVER).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_callback(func():
		is_attacking = false
	)

## 横扫扇形结算：圆形查询后按角度过滤 —— 只结算 aim_dir ±（半角+宽容）内的敌人
## （贴脸 SWEEP_CLOSE_GRACE 不看角度），身后的怪这一扫够不着。返回值语义同近战 = 可见命中数，
## 打击帧回调拿它门控扇面/材质声/反冲。属性管线、暴击、异常、吸血与近战同一份代码形状。
func _deal_sweep_damage(aim_dir: Vector2) -> int:
	var origin := global_position
	var half_ang := deg_to_rad(SWEEP_HALF_ANGLE + SWEEP_ANGLE_SLACK)
	var results := _query_enemies(_sweep_arc_radius(), origin, 24)
	var hit_count := 0
	var player: Node2D = GameManager.player
	var vp_center: Vector2 = player.global_position if player != null else global_position
	var base_dmg := _final_damage()
	# 2026-10-14 风险溢价：横扫击退兜底 240→300（重控场分支，与表内 340~680 一致）
	var kb_force := WeaponData.knockback_for(weapon_def_id, 300.0)
	var proc_burn: bool = def.get("proc_burn", false)
	var proc_chill: float = float(def.get("proc_chill", 0.0))
	var proc_poison: bool = def.get("proc_poison", false)
	var any_proc: bool = proc_burn or proc_chill > 0.0 or proc_poison
	var flat_ls: float = GameManager.item_hook_sum("melee_lifesteal_flat")
	var can_flat_heal: bool = flat_ls > 0.0 and player != null and is_instance_valid(player) and player.has_method("heal")

	for res in results:
		var col = res["collider"]
		var parent = col.get_parent() if col != null else null
		if parent != null and parent.has_method("take_damage"):
			var enemy = parent
			# 扇形过滤：横扫只打正前方弧面（身后的漏网是横扫与近战的本质差异）
			var to_enemy: Vector2 = enemy.global_position - origin
			if to_enemy.length() > SWEEP_CLOSE_GRACE and absf(aim_dir.angle_to(to_enemy)) > half_ang:
				continue
			var dmg := base_dmg
			var is_crit: bool = GameManager.roll_crit()
			if is_crit:
				dmg *= GameManager.get_crit_mult()
			dmg *= GameManager.elite_damage_mult_for(enemy)
			var knock = GameManager.knockback_vec(global_position, enemy.global_position, kb_force)
			enemy.take_damage(dmg, knock, is_crit)
			if GameBalance.is_in_viewport(enemy.global_position, vp_center):
				hit_count += 1
			if any_proc:
				ProcStatus.apply(enemy, proc_burn,
					dmg * float(def.get("burn_ratio", 0.45)), float(def.get("burn_dur", 3.0)),
					proc_chill, float(def.get("chill_dur", 2.5)),
					proc_poison, dmg * float(def.get("poison_ratio", 0.35)), float(def.get("poison_dur", 3.0)))
			GameManager.try_lifesteal(behavior)
			# 开山重刃谱：横扫同属近身挥砍，吸血钩子照旧生效
			if can_flat_heal:
				player.heal(flat_ls, true)
	return hit_count

func _find_target() -> Node2D:
	var player = GameManager.player
	if player == null:
		return null
	# 以玩家为圆心外接查询，再用椭圆等效距离与同屏可见性过滤选优
	var eff_range := attack_range * _range_mult()
	var results := _query_enemies(eff_range, player.global_position, 32)

	var nearest: Node2D = null
	var min_dist: float = 999999.0
	var nearest_on_screen: bool = false
	var chest: Node2D = null
	var chest_dist: float = 999999.0
	var chest_on_screen: bool = false
	for res in results:
		var col = res["collider"]
		var parent = col.get_parent() if col != null else null
		if parent != null and parent.has_method("take_damage"):
			var enemy = parent as Node2D
			if enemy == null or enemy.is_in_group("herbs"):
				continue
			var d := GameBalance.elliptical_distance(enemy.global_position - player.global_position)
			if d > eff_range:
				continue
			var on_scr := GameBalance.is_in_viewport(enemy.global_position, player.global_position)
			if enemy.is_in_group("chests"):
				if chest == null or (on_scr and not chest_on_screen) or (on_scr == chest_on_screen and d < chest_dist):
					chest_dist = d
					chest_on_screen = on_scr
					chest = enemy
				continue  # 匣子另册记账，见下面 return
			if nearest == null or (on_scr and not nearest_on_screen) or (on_scr == nearest_on_screen and d < min_dist):
				min_dist = d
				nearest_on_screen = on_scr
				nearest = enemy
	# 射程内还有活妖就不去砸匣子：匣子只补"这一件武器本来要打空气"的那个空
	return nearest if nearest != null else chest

## 逐发分配锁定目标：主目标（Player 按扇区统筹分配的那一个）排第一，其余按同屏优先 + 离炮口的远近补齐。
## 返回长度 = min(场上可用人手, n)，调用方按 idx % size 取用 ⇒ 怪少时多发自然归约到同一个敌人。
## 纯索敌，不改任何数值：弹丸拿到目标后按 BladeProjectile.HOMING_TURN_RATE 自己拐过去。
func _volley_targets(n: int) -> Array[Node2D]:
	var out: Array[Node2D] = []
	if n <= 0:
		return out
	if current_target != null and is_instance_valid(current_target):
		out.append(current_target)
	if n <= 1:
		return out
	var player = GameManager.player
	if player == null:
		return out
	var eff_range := attack_range * _range_mult()
	var results := _query_enemies(eff_range, player.global_position, 32)
	var muzzle_pos: Vector2 = muzzle_point.global_position
	var player_pos: Vector2 = player.global_position
	var cands: Array[Node2D] = []
	var chest_cands: Array[Node2D] = []
	for res in results:
		var col = res.get("collider")
		if col == null or col.get_parent() == null:
			continue
		var e := col.get_parent() as Node2D
		if e == null or not e.has_method("take_damage") or e.is_in_group("herbs"):
			continue
		if out.has(e):
			continue
		if GameBalance.elliptical_distance(e.global_position - player_pos) > eff_range:
			continue
		if e.is_in_group("chests"):
			chest_cands.append(e)
			continue
		cands.append(e)
	# 同屏可见优先，同屏状态一致时离炮口近的先被咬住
	# 命名方法排序避免每次开火 new 闭包（照 Player._sort_candidate_by_dist 先例）
	_volley_player_pos = player_pos
	_volley_muzzle_pos = muzzle_pos
	cands.sort_custom(_sort_volley_by_proximity)
	chest_cands.sort_custom(_sort_volley_by_proximity)
	for e in cands:
		if out.size() >= n:
			break
		out.append(e)
	# 场上妖不够分的时候，多出来的那几发不许往同一个活物身上重复招呼：
	# 脚边有匣子就顺手砸匣子（匣子掉补给，重复的那发只掉一个"过量"）
	for c in chest_cands:
		if out.size() >= n:
			break
		out.append(c)
	return out

## _volley_targets 排序：同屏可见优先，同屏状态一致时离炮口近的先被咬住。
## 命名方法（非闭包）避免每次开火分配 Callable；上下文经 _volley_player_pos/_volley_muzzle_pos 传入。
func _sort_volley_by_proximity(a: Node2D, b: Node2D) -> bool:
	var a_on := GameBalance.is_in_viewport(a.global_position, _volley_player_pos)
	var b_on := GameBalance.is_in_viewport(b.global_position, _volley_player_pos)
	if a_on != b_on:
		return a_on
	return _volley_muzzle_pos.distance_squared_to(a.global_position) < _volley_muzzle_pos.distance_squared_to(b.global_position)

## 土系重击地面贴花接入（开山斧/崩山剑/奔浪锤等命中敌群时克制留痕）
## 全武器共享一道全局时间闸（静态时间戳，非逐实例倒计时）——裂痕是重击砸地的
## 偶发留痕，不是每次命中的常规反馈；命中演出本身（月牙/扇面/闪光/材质声）不受影响
func _try_spawn_earth_crack(hit_pos: Vector2, hit_radius: float) -> void:
	var tags: Array = WeaponData.tags_of(weapon_def_id)
	if not tags.has("earth"):
		return
	var now_ms := Time.get_ticks_msec()
	if now_ms - _last_earth_crack_ms < EARTH_CRACK_MIN_GAP_MS:
		return
	_last_earth_crack_ms = now_ms
	var player: Node2D = GameManager.player
	var battle_layer: Node = player.get_parent() if (player != null and player.get_parent() != null) else (get_tree().current_scene if get_tree() != null else self)
	if battle_layer != null and is_inside_tree():
		GroundDecal.spawn(battle_layer, hit_pos, GroundDecal.Kind.CRACK, hit_radius)

