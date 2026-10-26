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







@export var weapon_def_id: String = "qingyun_sword"
@export var star: int = 1

var def: Dictionary = {}
var behavior: int = WeaponData.Behavior.MELEE
var base_damage: float = 30.0
var attack_cooldown: float = 1.1
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
## 翻滚/冲刺期间压住起手（闪避技能）：落地由 Player 解除并清间隔，保证「滚动完落地才 A」。
## 只挡新的起手，正在挥出的那一拍与持续束流不受影响。
var fire_held: bool = false
var base_angle: float = 0.0        # 无目标时回归的基础槽位角（Player 下发）
var spread_angle: float = 0.0      # 多把武器间的错开角，避免重叠（Player 下发）
## 默认环绕轨道半长轴/半短轴（椭圆）：贴身护体，避免脱节
const DEFAULT_ORBIT_EXTENTS := Vector2(54.0, 40.0)
var orbit_extents: Vector2 = DEFAULT_ORBIT_EXTENTS
var dynamic_angle: float = 0.0     # 当前轨道角：有目标时滑向目标方位
var current_target: Node2D = null
var is_attacking: bool = false
## 超级悟道【紫电】的攻击计数：每 BalanceChain.CHAIN_EVERY_ATTACKS 次出手放一次连锁闪电。
var _chain_attacks: int = 0
var _arrow_rain_attacks: int = 0  ## 箭雨倾盆出手计数（只统计 PROJECTILE 行为）
var bob_phase: float = 0.0
## 每实例独立相位（2026-10-22）：bob_phase 已有随机初相，但双频叠加与待机扫视需要
## 一个不与主频锁死的慢相位，否则同场武器仍会读成"一起呼吸"。_ready 里随机播种。
var _idle_phase: float = 0.0

# ---------------- 有机感：惯性 / 待机呼吸 / 按行为分化手感（2026-10-22） ----------------
## 旧写法全场武器共用一组硬编码插值系数，且完全忽略玩家自身速度 —— 玩家跑动时武器只是
## 被父链刚性平移，像焊在身上的卫星。这里补三件事：移动惯性甩尾、双频待机呼吸、按行为分化权重。

## 玩家速度低通跟踪系数：越小越"黏"，越大越跟手。6.0 ≈ 0.17s 时间常数，起步/急停都读得出惯性
const INERTIA_TRACK := 6.0
## 惯性甩尾倍率（× 玩家速度 × 行为权重）：玩家 200px/s 时约外甩 11px，是"能看见但不飘"的量
const INERTIA_FACTOR := 0.055
## 待机上下浮动：主频 3.5rad/s（沿用原节奏）+ 一个慢副频，两层叠加破掉节拍器感
const BOB_MAIN_AMP := 2.2
const BOB_SUB_AMP := 1.4
const BOB_SUB_FREQ := 0.37
## 待机扫视：无目标时在基础槽位角上叠一层极慢正弦，武器像在"环顾"而不是死盯一个方位
const IDLE_SWEEP_AMP := 0.30        ## 弧度（≈17°）
const IDLE_SWEEP_FREQ := 0.23       ## × bob_phase 后周期约 7.8s
## 换目标瞬间的错开延迟上限：一群怪同时进射程时，各武器按随机延迟依次起手，
## 而不是同一帧集体开火（配合 COOLDOWN_JITTER 形成持续异步）
const ACQUIRE_STAGGER := 0.18

## 玩家速度低通值（WeaponHolder 局部空间无速度，必须从 Player 侧鸭类型读取）
var _smoothed_player_vel: Vector2 = Vector2.ZERO
## 上一帧是否有目标：用于检测"由闲转战"边沿，只在刚接敌那一下补错开延迟
var _had_target: bool = false

## 按行为分化的手感权重（setup 期一次性解析成标量，_process 热路径只读浮点，零分配）：
## 轻器（剑/刀）回轨快、转向灵；重器（横扫/束流）回轨慢、惯性大；远程居中。
var _feel_idle_track: float = 4.0   ## 无目标回归基础槽位的角速度
var _feel_aim_track: float = 8.0    ## 有目标滑向目标方位的角速度
var _feel_orbit: float = 14.0       ## 轨道位置跟随系数
var _feel_face_aim: float = 15.0    ## 有目标时的转向系数
var _feel_face_idle: float = 6.0    ## 待机转向系数
var _feel_inertia: float = 1.0      ## 惯性甩尾倍率
## 后坐的相对偏移（2026-10-22）：旧写法把「开火前那一刻的 position」当回位终点快照，
## 而攻击窗口里 bob_phase 在推进、玩家速度在变（惯性项），快照一过时就与真实轨道位差开几像素，
## 收势末尾会有一记小跳。改为记「相对实时轨道基座」的偏移，基座逐帧现算。
var _lunge_base_off: Vector2 = Vector2.ZERO
var _lunge_out_off: Vector2 = Vector2.ZERO
var _slash_tween: Tween = null     # 剑气出鞘扫放的全生命周期（亮扫→淡出→隐藏），再次攻击时先杀旧的
var sweep_sprite: WeaponArcRenderer = null  # 横扫专属元素扇面（top_level 世界坐标，SWEEP 才建）
var _sweep_slash_tween: Tween = null


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
var _lunge_ends_attack: bool = false  ## 演出走完是否代释放 is_attacking
var _flash_t: float = 0.0      ## 本体亮闪剩余时间
var _flash_total: float = 0.0001
var _flash_from: Color = Color.WHITE
var _muzzle_t: float = 0.0     ## 枪口闪光剩余时间
var _muzzle_scale0: float = 0.5

## 脱程重查节流（2026-10-10 第 6 波卡顿优化）：15Hz + instance_id 错相
const RETARGET_INTERVAL := 1.0 / 15.0
var _retarget_phase: float = 0.0

## 光束判定在截断点后再探出一段：射线停在挡束者表面，不补这段则挡住光束的敌人自己
## 反而打不到（判定只到它表皮）；补段长约一个敌人受击半径，只盖挡束者、不穿墙打后排。
const BEAM_HIT_OVERHANG := 24.0
var _channel_on: bool = false
var _channel_left: float = 0.0
var _channel_tick: float = 0.0
var _beam_len: float = 0.0     ## 本 tick 光束判定长度（射线命中截断，渲染同源）
var _beam_cast_phase: float = 0.0
var _beam_len_target: float = 0.0
var _beam_need_cast: bool = false
var beam_renderer: BeamRenderer = null
var cone_renderer: FlameConeRenderer = null

@onready var sprite: Sprite2D = $Sprite2D
@onready var muzzle_point: Marker2D = $MuzzlePoint
@onready var slash_sprite: WeaponArcRenderer = $SlashEffect

## ★3 觉醒追加打击（回风斩/回掠）专用的第二道弧光，懒建。
## 主斩月牙的扫放/淡出窗口（0.05→0.23s）与追加打击重叠，共用 $SlashEffect
## 会把主视觉拦腰截断——追加打击一律走这个独立节点。
var echo_slash_sprite: WeaponArcRenderer = null

var muzzle_flash: Sprite2D
var aura_sprite: Sprite2D = null
## ★4 极境常驻气场（太虚霓虹双弧）：懒建，降到★4 以下即卸。
## 与器身描边互补——描边贴器形轮廓，气场是绕本体的独立几何，小件也读得出极境身份。
const StarAuraFxScript := preload("res://scripts/weapons/StarAuraFx.gd")
var _star4_aura: Node2D = null
var _base_sprite_scale := Vector2(0.55, 0.55)
## 矢量法器/机关本体。非 null 时 Sprite2D 被隐蔽，由它出画面。
## 未实现的大类保持 null ⇒ 继续显示旧贴图（逐批灰度，不破现状）。
var _proc_renderer: Node2D = null

var projectile_scene: PackedScene = preload("res://scenes/weapons/BladeProjectile.tscn")
var burst_scene: PackedScene = preload("res://scenes/weapons/ThunderBurst.tscn")
var turret_scene: PackedScene = preload("res://scenes/weapons/TurretUnit.tscn")

var active_turrets: Array[TurretUnit] = []


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
		_search_query.collide_with_bodies = false  # 只查敌人 Hurtbox(Area)，不扫 body 层
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
	_resolve_feel_weights()
	# 升星重调 setup：把新星数下发矢量本体（结构强化：★2 器尖冷光点、★3 刃脊流光）
	if _proc_renderer != null:
		if _proc_renderer is ProceduralWeaponRenderer:
			(_proc_renderer as ProceduralWeaponRenderer).star = star
		elif _proc_renderer is ProceduralTurretRenderer:
			(_proc_renderer as ProceduralTurretRenderer).star = star
		_proc_renderer.queue_redraw()
	_refresh_star4_aura()

## ★4 极境常驻气场：升到极境时挂上，降星（或重建渲染器）时卸掉。
## 只在树内才建节点（setup 会在 add_child 之前被调一次）。
func _refresh_star4_aura() -> void:
	var want: bool = star >= WeaponData.MAX_STAR and is_inside_tree()
	if want and _star4_aura == null:
		_star4_aura = StarAuraFxScript.new()
		_star4_aura.name = "Star4Aura"
		add_child(_star4_aura)
	elif not want and _star4_aura != null:
		_star4_aura.queue_free()
		_star4_aura = null

func _ready() -> void:
	slash_sprite.visible = false
	slash_sprite.modulate.a = 0.0
	bob_phase = randf() * TAU
	## 独立慢相位：同场多把武器不能一起"呼吸"，否则待机也读成方阵
	_idle_phase = randf() * TAU
	_resolve_feel_weights()
	_retarget_phase = fposmod(float(get_instance_id() % 97) * 0.001, RETARGET_INTERVAL)
	## 首跳错相：同帧进树的多把武器错开首击，否则同型号武器冷却完全同相、永久齐挥
	## （放 _ready 只跑一次；setup() 会被升星重调，不能打断既有节奏）
	cooldown_timer = GameManager.rng.randf_range(0.1, 0.5)
	dynamic_angle = base_angle
	if def.is_empty():
		setup(weapon_def_id, star)
	# setup() 通常在 add_child 之前调用（此时还不在树里，气场建不出来）：进树后补挂一次
	_refresh_star4_aura()
	slash_sprite.configure(WeaponArcRenderer.ArcMode.MELEE, _arc_element())
	if def.has("icon"):
		sprite.texture = load(def["icon"])
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		# 出膛点摆在发射帧（本体 +X = 瞄准方向）的剑尖处：贴图缩放后的实际屏上距离
		muzzle_len = tip_local.length() * sprite.scale.x
		muzzle_point.position = Vector2(muzzle_len, 0.0)
		_setup_proc_renderer()
		_apply_facing(rotation)
		_setup_muzzle_flash()
		_setup_aura()
		if behavior == WeaponData.Behavior.SWEEP:
			_setup_sweep_sprite()
		elif behavior == WeaponData.Behavior.BEAM:
			_setup_beam_renderer()
		elif behavior == WeaponData.Behavior.CONE:
			_setup_cone_renderer()

## 矢量法器本体/机关本体：悬浮法器（剑/刀/匕首/符箓等）走 ProceduralWeaponRenderer，
## 机关炮台（弩机/阵盘/炮管/机关兽/投石机/烽火台）走 ProceduralTurretRenderer，并把旧贴图隐蔽。
## 坐标契约：画布像素空间沿 +X 绘制、器尖落 tip_len / 炮口落 muzzle_len，
## 节点 scale = 旧 sprite 的 0.55 ⇒ 器尖/炮口屏上位置与 MuzzlePoint 出膛点严丝合缝，判定零改动。
func _setup_proc_renderer() -> void:
	if _proc_renderer != null:
		return
	var shape_name := String(def.get("shape", ""))
	var wshape := ProceduralWeaponRenderer.shape_from_name(shape_name)
	if wshape != ProceduralWeaponRenderer.WeaponShape.GENERIC:
		var wr := ProceduralWeaponRenderer.new()
		wr.name = "ProcWeapon"
		wr.configure(wshape, _arc_element(), tip_local.length(), star, upright, weapon_def_id)
		wr.scale = sprite.scale
		wr.z_index = sprite.z_index
		_proc_renderer = wr
		add_child(wr)
		# 贴图让位：矢量本体接管显示（与 BladeProjectile/SunOrb 同款过渡手法）
		sprite.self_modulate.a = 0.0
		return

	var turret_shape_name := String(def.get("turret_shape", ""))
	var tshape := ProceduralTurretRenderer.shape_from_name(turret_shape_name)
	if tshape != ProceduralTurretRenderer.TurretShape.GENERIC:
		var tr := ProceduralTurretRenderer.new()
		tr.name = "ProcTurret"
		tr.configure(tshape, _arc_element(), star)
		tr.scale = sprite.scale
		tr.z_index = sprite.z_index
		_proc_renderer = tr
		add_child(tr)
		# 贴图让位：矢量机关本体接管显示
		sprite.self_modulate.a = 0.0
		return

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
	aura_sprite.material = SharedMaterials.add_blend()
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
		# 矢量本体同样反向补掉本体转角，世界坐标里始终竖直
		if _proc_renderer != null:
			_proc_renderer.rotation = -angle
	else:
		var mirrored: bool = absf(wrapf(angle, -PI, PI)) > PI * 0.5
		sprite.flip_v = mirrored
		sprite.rotation = art_angle if mirrored else -art_angle
		# 矢量本体器尖本就画在 +X，跟随节点转角即天然对准目标，无需 art_angle/flip 补偿
		if _proc_renderer != null:
			_proc_renderer.rotation = 0.0

## 这一发的瞄准角：有目标就朝目标，没目标退回当前发射帧（贴图补偿由 _apply_facing 统一做）
func _aim_at(pos: Vector2) -> float:
	return (pos - global_position).angle()

## 射程乘区（攻击范围词条 + 剑系/广域羁绊 + 近战/横扫专有乘区）：武器侧所有"够得着多远"都从这里取，不许各算各的
func _range_mult() -> float:
	return WeaponDamageReadout.range_mult_for(weapon_def_id)

## 本体挥砍判定几何乘区（不含剑气凌霄的翻倍，保持本体干脆利落不虚胖；含开山重刃谱 wide 加成）
func _body_range_mult() -> float:
	var mult: float = GameManager.attack_range_mult * GameManager.synergy_range_mult
	if WeaponData.tags_of(weapon_def_id).has("wide"):
		mult *= (1.0 + GameManager.item_hook_sum("wide_range_mult"))
	return mult

## 实际有效攻击范围（基础射程 × 射程乘区）
func effective_range() -> float:
	return attack_range * _range_mult()

## 按行为解析手感权重（2026-10-22）：旧写法长剑与重锤共用一套轨道插值，全武器读起来同质。
## 这里只调"视觉跟随手感"，不碰任何判定几何与数值：轻器回轨快、转向灵；
## 重器回轨慢、惯性大（甩尾更明显），远程/施法居中；束流要稳，转向最慢但惯性最小。
func _resolve_feel_weights() -> void:
	match behavior:
		WeaponData.Behavior.MELEE:
			_feel_idle_track = 5.0; _feel_aim_track = 9.0; _feel_orbit = 16.0
			_feel_face_aim = 16.0; _feel_face_idle = 7.0; _feel_inertia = 0.8
		WeaponData.Behavior.SWEEP:
			_feel_idle_track = 3.0; _feel_aim_track = 6.0; _feel_orbit = 10.0
			_feel_face_aim = 11.0; _feel_face_idle = 4.5; _feel_inertia = 1.5
		WeaponData.Behavior.BEAM, WeaponData.Behavior.CONE:
			_feel_idle_track = 3.5; _feel_aim_track = 7.0; _feel_orbit = 11.0
			_feel_face_aim = 9.0; _feel_face_idle = 5.0; _feel_inertia = 0.6
		WeaponData.Behavior.TURRET:
			_feel_idle_track = 3.5; _feel_aim_track = 6.5; _feel_orbit = 11.0
			_feel_face_aim = 10.0; _feel_face_idle = 5.0; _feel_inertia = 1.2
		_:  # PROJECTILE / BURST：标准档
			_feel_idle_track = 4.0; _feel_aim_track = 8.0; _feel_orbit = 14.0
			_feel_face_aim = 15.0; _feel_face_idle = 6.0; _feel_inertia = 1.0

## 实时轨道静止点（2026-10-22）：按当前 dynamic_angle / 惯性 / 呼吸现算一个静止点，
## 回收与后坐都朝它收敛 —— 不再依赖动作开始时的位置快照。
func _compute_orbit_pos() -> Vector2:
	var orbit_pos := Vector2(cos(dynamic_angle) * orbit_extents.x, sin(dynamic_angle) * orbit_extents.y)
	var inertia: Vector2 = -_smoothed_player_vel * INERTIA_FACTOR * _feel_inertia
	var bob_y: float = sin(bob_phase) * BOB_MAIN_AMP + sin(bob_phase * BOB_SUB_FREQ + _idle_phase) * BOB_SUB_AMP
	return orbit_pos + inertia + Vector2(0.0, bob_y)

## 收势：从当前位置弹性回正到「实时」轨道静止点（替代 Tween 到旧快照）
## 用 tween_method 逐帧现算终点 —— 动作窗口里目标还在动、惯性还在变，终点跟着走才不会脱手
func _begin_recover(duration: float, trans: int) -> void:
	var from: Vector2 = position
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_method(func(e: float) -> void:
		position = from.lerp(_compute_orbit_pos(), e)
	, 0.0, 1.0, duration).set_trans(trans).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2.ONE, duration).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_callback(func(): is_attacking = false)

## ★3 觉醒追加打击的第二道弧光：与主斩同模式同元素，层级对齐 $SlashEffect，
## 金色由调用方 modulate 覆盖。只在 ★3 武器第一次追加打击时创建（全生命周期复用）。
func get_echo_slash(mode: WeaponArcRenderer.ArcMode) -> WeaponArcRenderer:
	if echo_slash_sprite == null:
		echo_slash_sprite = WeaponArcRenderer.new()
		echo_slash_sprite.configure(mode, _arc_element())
		# 横扫扇面钉世界坐标（与 _setup_sweep_sprite 同一约定）：扇面留在挥出那一帧的方位，
		# 不随本体收势转走；近战月牙跟随本体（局部坐标）。
		echo_slash_sprite.top_level = (mode == WeaponArcRenderer.ArcMode.SWEEP)
		echo_slash_sprite.z_index = slash_sprite.z_index
		echo_slash_sprite.visible = false
		echo_slash_sprite.modulate.a = 0.0
		add_child(echo_slash_sprite)
	return echo_slash_sprite




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
	muzzle_flash.material = SharedMaterials.add_blend()
	muzzle_flash.position = muzzle_point.position
	muzzle_flash.z_index = 6
	muzzle_flash.visible = false
	add_child(muzzle_flash)

## 本体短促亮闪（近战挥砍/远程开火共用，微光圈同步亮起）——零 Tween 分配版：
## 记下起点色，衰减在 _tick_fire_fx 逐帧插值回白/回基线
func _flash_sprite(color: Color, dur: float) -> void:
	sprite.modulate = color
	if _proc_renderer != null:
		_proc_renderer.modulate = color
	_flash_from = color
	_flash_total = maxf(dur, 0.0001)
	_flash_t = _flash_total
	if aura_sprite != null:
		aura_sprite.modulate.a = AURA_FLASH_A

## 本体色 tween：贴图与矢量本体同步推进（BURST 蓄力金光/引雷亮闪等演出）
func _tw_modulate(tw: Tween, color: Color, dur: float) -> void:
	tw.parallel().tween_property(sprite, "modulate", color, dur)
	if _proc_renderer != null:
		tw.parallel().tween_property(_proc_renderer, "modulate", color, dur)

## 开火视觉帧内状态机推进（后坐/沉身、本体亮闪、枪口闪光、光晕回位）
## 在 _process 每渲染帧调用；全部闭式插值，不再创建 Tween
func _tick_fire_fx(delta: float) -> void:
	# 1. 后坐（EXPO 急退 + BACK 弹回，曲线与原双段 Tween 等价）
	# 2026-10-22 改为「相对实时轨道基座」的偏移插值：基座逐帧现算，
	# 收势末尾不再弹回几帧前的旧坐标（bob/惯性在动作窗口里一直在变）。
	if _lunge_t >= 0.0:
		_lunge_t += delta
		var t: float = _lunge_t
		var base := _compute_orbit_pos()
		if t <= _lunge_out_time:
			# 急退段：EXPO EASE_OUT
			var k: float = t / _lunge_out_time
			position = base + _lunge_base_off.lerp(_lunge_out_off, 1.0 - pow(2.0, -10.0 * k))
		elif t < _lunge_total:
			# 弹回段：TRANS_BACK EASE_OUT 过冲回位
			var k2: float = (t - _lunge_out_time) / (_lunge_total - _lunge_out_time)
			const BACK_S := 1.70158
			var e: float = 1.0 + (BACK_S + 1.0) * pow(k2 - 1.0, 3.0) + BACK_S * pow(k2 - 1.0, 2.0)
			position = base + _lunge_out_off.lerp(_lunge_base_off, e)
		else:
			position = base + _lunge_base_off
			_lunge_t = -1.0
			if _lunge_ends_attack:
				is_attacking = false
	# 2. 本体亮闪回白
	if _flash_t > 0.0:
		_flash_t = maxf(_flash_t - delta, 0.0)
		var fk := 1.0 - _flash_t / _flash_total
		sprite.modulate = _flash_from.lerp(Color.WHITE, fk)
		if _proc_renderer != null:
			_proc_renderer.modulate = sprite.modulate
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

## 发起一次后坐/沉身演出（ProjectileHandler/TurretHandler 共用）
## ends_attack=true 时演出走完代释放 is_attacking（替代原 Tween 的收尾回调）
func _begin_lunge(out_offset: Vector2, out_time: float, back_time: float, ends_attack: bool) -> void:
	# 记「相对轨道基座的偏移」而非绝对坐标：演出期间基座随玩家/目标继续移动
	_lunge_base_off = position - _compute_orbit_pos()
	_lunge_out_off = _lunge_base_off + out_offset
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
	# 空闲期冷却钳制（2026-10-22）：旧写法无目标时 cooldown_timer 一路扣成深负数，
	# 等一群怪同时进射程，所有武器同一帧判定 <=0 ⇒ 集体齐射（「一起打」最直接的成因）。
	# 钳到 0 后各武器只剩自身相位差，接敌时按各自节奏起手。
	if cooldown_timer < 0.0 and current_target == null:
		cooldown_timer = 0.0

	# 玩家速度低通（惯性甩尾用）：Player 在 _physics_process 维护 velocity，武器只读不写
	var p: Node2D = GameManager.player
	if p is CharacterBody2D:
		var pv: Vector2 = (p as CharacterBody2D).velocity
		_smoothed_player_vel = _smoothed_player_vel.lerp(pv, minf(delta * INERTIA_TRACK, 1.0))
	else:
		_smoothed_player_vel = _smoothed_player_vel.lerp(Vector2.ZERO, minf(delta * INERTIA_TRACK, 1.0))

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
			var max_reach := effective_range() * 1.2
			if GameBalance.elliptical_distance(current_target.global_position - player.global_position) > max_reach:
				_retarget_phase -= delta
				if _retarget_phase <= 0.0:
					_retarget_phase = RETARGET_INTERVAL
					current_target = _find_target()

	# 2. 动态轨道：有目标时沿轨道滑向目标方位（自动换位），无目标时回归基础槽位
	# 2026-10-22 修：整段原先嵌在「有目标」的 else 里 —— 场上没怪时武器既不回槽位也不呼吸，
	# 就那么僵在半空（最容易被读成"死板"的一处）。现在无论有无目标都跑轨道。
	if not is_attacking:
		var player = GameManager.player
		var desired_angle = base_angle
		var track_speed := _feel_idle_track
		if current_target != null and player != null:
			desired_angle = (current_target.global_position - player.global_position).angle() + spread_angle
			track_speed = _feel_aim_track
		else:
			# 待机扫视：在基础槽位角上叠一层极慢正弦，武器缓缓"环顾"而非死盯一个方位
			desired_angle += sin(bob_phase * IDLE_SWEEP_FREQ + _idle_phase) * IDLE_SWEEP_AMP
		dynamic_angle = lerp_angle(dynamic_angle, desired_angle, minf(delta * track_speed, 1.0))
		var orbit_pos = Vector2(cos(dynamic_angle) * orbit_extents.x, sin(dynamic_angle) * orbit_extents.y)
		# 惯性甩尾：轨道目标点反向偏移到玩家速度的反方向 —— 玩家跑动时武器拖在后头、
		# 急停时向前荡回，配合下面的位置 lerp 自然形成弹簧感（纯视觉偏移，判定圆心仍用 global_position）
		var inertia: Vector2 = -_smoothed_player_vel * INERTIA_FACTOR * _feel_inertia
		# 双频呼吸：主频沿用原节奏，叠一层慢副频 + 实例独立相位，破掉"全场一起上下"的节拍器感
		# 2026-10-24：两组 sin 同帧各算一次复用（原先 bob/breath/aura 三处重复求值，
		# 8 武器 × 60fps ≈ 2880 次/秒的冗余 sin）
		var bob_main := sin(bob_phase)
		var bob_sub := sin(bob_phase * BOB_SUB_FREQ + _idle_phase)
		var bob_y: float = bob_main * BOB_MAIN_AMP + bob_sub * BOB_SUB_AMP
		position = position.lerp(orbit_pos + inertia + Vector2(0, bob_y), minf(delta * _feel_orbit, 1.0))

		# 待机器身微呼吸与灵光脉动（同样双频，避免与邻居同拍）
		var breath := bob_main * 0.014 + bob_sub * 0.010
		sprite.scale = _base_sprite_scale * (1.0 + breath)
		if _proc_renderer != null:
			_proc_renderer.scale = sprite.scale
		if aura_sprite != null:
			aura_sprite.modulate.a = 0.12 + bob_main * 0.035 + bob_sub * 0.02

	# 3. 朝向：有目标面向目标；无目标朝轨道外（贴图补偿与镜像都在 _apply_facing 一处算）
	if not is_attacking:
		if current_target != null:
			# 远程/落雷走预判点（拦截横移目标），近战/横扫/束流仍瞄当前位置：
			# 近战有扇形余量、束流持续追踪，预判只会让刀口提前甩过目标
			var aim_pos: Vector2 = current_target.global_position
			if behavior == WeaponData.Behavior.PROJECTILE:
				aim_pos = ProjectileHandler.lead_aim_pos(self, current_target)
			var target_angle = _aim_at(aim_pos)
			_apply_facing(lerp_angle(rotation, target_angle, minf(delta * _feel_face_aim, 1.0)))
		else:
			_apply_facing(lerp_angle(rotation, dynamic_angle, minf(delta * _feel_face_idle, 1.0)))

		# 接敌边沿：由闲转战那一下补一个随机延迟，一群怪同时进射程时按各自延迟依次起手
		var has_target: bool = current_target != null
		if has_target and not _had_target:
			cooldown_timer = maxf(cooldown_timer, GameManager.rng.randf_range(0.0, ACQUIRE_STAGGER))
		_had_target = has_target

		# 4. 攻击
		if cooldown_timer <= 0.0 and not is_attacking and not fire_held:
			if behavior == WeaponData.Behavior.TURRET or current_target != null:
				_perform_attack()

	# 5. 束流推进（BEAM/CONE）：几何随朝向逐帧走，结算按 TICK 节拍
	if _channel_on:
		_tick_channel(delta)

## 翻滚期间起手闸门（闪避技能）。落地由 Player 解除，紧接着清间隔放行。
func set_fire_held(held: bool) -> void:
	fire_held = held

## 技能重置普攻（闪避落地）：清掉本拍剩余的攻击间隔，冷却一转回来立刻出手。
## 只清计时器，不强切 is_attacking：正在挥出的那一拍动作与判定同拍，截断会让这一刀落在空处。
func reset_attack_cooldown() -> void:
	cooldown_timer = 0.0

## 杀戮节奏（神通）：击杀返还一部分当前冷却。以「本次实际攻击间隔」为一份，
## 而不是按剩余秒数折算 —— 否则攻速越快，同样的返还比例越没感觉。
func refund_cooldown(pct: float) -> void:
	if pct <= 0.0:
		return
	var unit: float = attack_cooldown * GameManager.get_effective_attack_speed_mult()
	cooldown_timer = maxf(0.0, cooldown_timer - unit * pct)

## 每拍冷却相位抖动（2026-10-22）：旧写法每次都精确重置同一时长，同冷却武器一旦相位对上
## 就永久锁相——全场武器齐挥齐收、像一台机器在打拍子（首跳错相只能救第一次）。
## 每拍乘 ±COOLDOWN_JITTER 的随机系数：期望 DPS 不变（均值≈1.0），但相位持续漂移，
## 几拍后各武器自然异步出手，玩家看到的是此起彼伏而非方阵齐射。
const COOLDOWN_JITTER := 0.08

func _perform_attack() -> void:
	var cd := attack_cooldown * GameManager.get_effective_attack_speed_mult()
	cooldown_timer = cd * GameManager.rng.randf_range(1.0 - COOLDOWN_JITTER, 1.0 + COOLDOWN_JITTER)
	# 七种攻击行为实现已拆 scripts/weapons/handlers/（首参传自身，鸭类型防循环依赖）；
	# 本类保留状态成员、冷却分发与开火视觉状态机。
	match behavior:
		WeaponData.Behavior.MELEE:
			MeleeHandler.perform(self)
		WeaponData.Behavior.PROJECTILE:
			ProjectileHandler.perform(self)
		WeaponData.Behavior.BURST:
			BurstHandler.perform(self)
		WeaponData.Behavior.TURRET:
			TurretHandler.perform(self)
		WeaponData.Behavior.SWEEP:
			SweepHandler.perform(self)
		WeaponData.Behavior.BEAM, WeaponData.Behavior.CONE:
			ChannelHandler.perform_channel(self)
	_tick_chain_lightning()
	_tick_arrow_rain()
	# 神通【万剑归宗】：剑系武器出手攒剑意，攒满即全体剑器幻化齐射（SwordPhantom 内部判剑系）
	SwordPhantom.tick_attack(self)

## 神通【紫电】：每 BalanceChain.CHAIN_EVERY_ATTACKS 次出手，放一次连锁闪电。
## 首跳伤害按武器面板实伤折算 —— 武器越强紫电越强，读起来是「你的攻击带电」而不是「白送固定伤害」。
## 炮台不在此列（TurretHandler 召出的炮台独立开火，不走本方法）。
##
## 2026-10-26 演出重做：旧写法从「武器自身」起跳 —— 近战武器就贴在怪脸上，第一段弧短到
## 被 MIN_BOLT_LEN 掐掉，玩家只看到自己正在砍的那只身上闪了一下白点，读不出「紫电」。
## 现在改成从**玩家**起跳、首跳认领武器当前锁定的目标：电弧从玩家身上甩出去串住正在砍的
## 敌人，再逐跳连到周围怪身上 —— 这才是「把各个敌人连起来」的画面。
func _tick_chain_lightning() -> void:
	var snap := StatSystem.super_hook_snapshot(GameManager)
	if float(snap.get("attack_chain_lightning", 0.0)) <= 0.0:
		_chain_attacks = 0
		return
	_chain_attacks += 1
	if _chain_attacks < BalanceChain.CHAIN_EVERY_ATTACKS:
		return
	_chain_attacks = 0
	var hops: int = BalanceChain.MAX_HOPS + int(float(snap.get("chain_hop_bonus", 0.0)))
	var player: Node2D = GameManager.player
	var origin: Vector2 = player.global_position if player != null and is_instance_valid(player) else global_position
	var first: Node2D = current_target if current_target != null and is_instance_valid(current_target) else null
	# 玩家身上起跳点补一记紫色爆闪：电弧的起点在角色身上，没有这一下会读成「凭空出现」
	if player != null and is_instance_valid(player):
		JuiceEffect.spawn_bolt_pop(player, origin, GameStyle.FX_HDR_ZIDIAN)
	ChainLightning.strike(self, origin, first, _final_damage(), hops,
		GameStyle.FX_HDR_ZIDIAN, &"zidian", "chain_zap")

## 神通【箭雨倾盆】：远程武器每 BalanceChain.ARROW_RAIN_EVERY 次出手，朝当前目标区
## 落一轮箭雨（伤害按武器面板实伤折算，与紫电同一条「武器派生」口径）。
## 只有 PROJECTILE 行为计数 —— 这是箭道的大成卡，近战/束流不该蹭到。
func _tick_arrow_rain() -> void:
	if behavior != WeaponData.Behavior.PROJECTILE:
		return
	var snap := StatSystem.super_hook_snapshot(GameManager)
	if float(snap.get("arrow_rain_every", 0.0)) <= 0.0:
		_arrow_rain_attacks = 0
		return
	_arrow_rain_attacks += 1
	if _arrow_rain_attacks < int(snap.get("arrow_rain_every", 0.0)):
		return
	_arrow_rain_attacks = 0
	# 落点中心：当前锁定目标优先；没目标就找最近敌人；都找不到不放（不浪费这轮）。
	# 手写最近循环而不调 EnemyFilter.nearest —— 后者签名带 EnemyBase 类型，
	# 武器脚本沾类型引用会触发循环类依赖（项目坑 12）。
	var center := Vector2.INF
	if current_target != null and is_instance_valid(current_target):
		center = (current_target as Node2D).global_position
	else:
		var best: Node2D = null
		var best_d := 1200.0
		for node in GameManager.live_enemies:
			var e := node as Node2D
			if e == null or not is_instance_valid(e) or bool(e.get("dying")):
				continue
			var d: float = global_position.distance_to(e.global_position)
			if d < best_d:
				best_d = d
				best = e
		if best != null:
			center = best.global_position
	if center == Vector2.INF:
		return
	ArrowRain.play(self, center, BalanceChain.arrow_rain_damage(_final_damage()))









func _final_damage() -> float:
	var stat_bonus: float = GameManager.get_weapon_stat_bonus(weapon_def_id, star)
	return (base_damage + stat_bonus) * GameManager.get_weapon_damage_mult() * GameManager.synergy_damage_mult * GameManager.shadow_amp_mult * GameManager.buff_damage_mult * GameManager.cultivator_damage_mult(weapon_def_id) * GameManager.element_damage_mult(weapon_def_id) * GameManager.get_multi_weapon_damage_mult()









func _find_target() -> Node2D:
	var player = GameManager.player
	if player == null:
		return null
	# 以玩家为圆心外接查询，再用椭圆等效距离与同屏可见性过滤选优
	var eff_range := effective_range()
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






# ==================== 判据兼容转发（实现已拆 handlers/） ====================

## 束流起喷/推进：beam_cone_check 判据直调这两个入口，保留转发面
func _perform_channel_attack() -> void:
	ChannelHandler.perform_channel(self)

func _tick_channel(delta: float) -> void:
	ChannelHandler.tick(self, delta)

## 逐发齐射目标分配：chest_targeting_check 判据直调，保留转发面
func _volley_targets(n: int) -> Array[Node2D]:
	return ProjectileHandler.volley_targets(self, n)

## 各行为起手入口：weapon_aim_check / perf_probe 等判据直调，保留转发面
func _perform_melee_attack() -> void:
	MeleeHandler.perform(self)

func _perform_sweep_attack() -> void:
	SweepHandler.perform(self)

func _perform_projectile_attack() -> void:
	ProjectileHandler.perform(self)

func _perform_burst_attack() -> void:
	BurstHandler.perform(self)

func _perform_turret_attack() -> void:
	TurretHandler.perform(self)
