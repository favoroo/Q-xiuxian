class_name SwordPhantom
extends Node2D

## 万剑归宗（飞升悟道）的幻影剑阵（2026-10-26 三轮重塑）。
##
## 用户口径演进（三轮都在纠同一件事：幻影得「看得见、待得住、不像弹丸」）：
##   一轮「一个圆圈的余波，我不知道有什么用啊，有什么伤害」→ 删掉圆形冲击波；
##   二轮「6 把剑系装备就幻化出 6 把，一共十二把一起攻击」→ 改成按剑数幻化；
##   三轮「效果太不明显了，都没感受出来有幻象出来，改成幻象能持续一段时间，
##         攻击到一定层数之后幻象能够持续好几秒」＋「怎么还有那种弹丸类的东西飞出来」。
##
## 机制：全局剑意槽（`tick_attack`）—— 任一【剑系】武器每次出手 +1，攒满 CHARGE_EVERY 层开阵：
## 玩家身上每一把剑系武器各幻化一道自己的幻影，在真剑外圈列成剑阵并【驻场 FORMATION_TIME 秒】。
## 驻场期间每道幻影按自己的 FIRE_CD 朝圈内敌人原地劈出一弯弧光，时辰一到整体化光散去。
## 剑阵运转期间剑意不涨 —— 否则阵一散就能立刻再开，等于常驻。
##
## 为什么幻影【既不飞出去、也不发剑气】（二轮实现的两个坑）：
##   ① 二轮是「凝形 0.09s → 900px/s 疾射 → 命中即散」，整段可见寿命不到 0.3 秒，
##      玩家读到的是一枚剑形弹丸（用户原话「弹丸类的东西」），既没有「万剑归宗」的阵势，
##      也和剑气凌霄「挥出剑弧」的视觉语言打架。
##   ② 三轮若改成幻影也发剑气，场上会同时飞 6 道弧 —— 剑气凌霄「就一道剑气」的辨识度直接没了。
##   所以幻影【驻场不离轨、只在原地劈弧】：与真剑同一套语言，且整段时间都停在画面上数得清。
##
## 纪律：
##   · 全程鸭类型访问武器与敌人（has_method），绝不硬引用 EnemyBase / FloatingWeapon
##     —— 武器侧硬类型引用会构成循环类依赖，把 preload 打成空 PackedScene（项目坑 12/16）。
##   · 幻影劈斩【不吸血】：6 道同帧会把 try_lifesteal 与固定回血各刷 6 次，奶量直接翻倍。
##   · 画多大 == 判多大（铁律 6）：判定圆半径 == 弧光外缘 `SLASH_ART_OUTER × SLASH_SCALE`，
##     弧光走 top_level 世界变换，不受本体蓄势缩放影响（否则判定会跟着缩放漂）。
##   · 判定随机走 GameManager.rng（暴击/击退/出刀错相），本文件无任何演出随机（铁律 15）。

# ---------------- 机制常量（数值唯一真话） ----------------

## 剑意槽容量：剑系武器每次出手 +1，攒满开阵。
## 20 层 = 1 把剑约 20 秒一轮、6 把剑约 3.3 秒一轮；再叠上 4 秒驻场，
## 6 剑构筑读作「4 秒剑阵 / 3.3 秒收势」的呼吸节奏（10 层时 1.7s 收势太接近常驻，
## 后期五六把剑叠得太快 —— 2026-10-27 用户口径）—— 剑越多阵越密，这正是卡名的意思。
const CHARGE_EVERY := 20
## 剑阵驻场时长（秒）：用户「幻象能够持续好几秒」。4 秒够看清剑阵转小半圈、
## 够每道幻影劈 4~5 刀，又不至于长到变成常驻 buff。
const FORMATION_TIME := 4.0
## 单刀伤害 = 源武器单发实伤 × 本比例。0.25 × 每秒约 1.2 刀 ⇒ 每道幻影约补源武器 30% 输出，
## 6 道合起来是「开阵期间输出约 +180%」，对飞升悟道这个档位是够狠但不至于把数值表打穿。
const DAMAGE_RATIO := 0.25
## 开阵索敌半径（px）：圈内一个敌人都没有时【不消耗剑意】，怪一进圈立刻开，不浪费在空气上
const ACQUIRE_RADIUS := 300.0

# ---------------- 剑阵几何 ----------------

## 剑阵轨道半长轴/半短轴（px）：真剑轨道是 54×40（FloatingWeapon.DEFAULT_ORBIT_EXTENTS），
## 幻影放在 88×68 的外圈 —— 比真剑外扩约六成，「内真外虚」两圈一眼可辨；
## 初版 112×86 离角色太远，读起来像「大外面两个圈」（2026-10-27 用户口径收近）。
const ORBIT_RADII := Vector2(88.0, 68.0)
## 剑阵自转速度（rad/s）：慢转，读作「阵在运转」而不是又一圈静态贴图
const ORBIT_SPEED := 0.85

# ---------------- 出刀节奏 ----------------

## 每道幻影自己的出刀间隔（秒）：4 秒驻场里每道约劈 4~5 刀
const FIRE_CD := 0.85
## 出刀间隔抖动（±比例）：六道同相会齐射成一排，错开才读得出「一把把在劈」
const FIRE_CD_JITTER := 0.15
## 幻影索敌/出刀射程（px）：比索敌半径略收，够得着剑阵外缘的怪即可
const FIRE_RANGE := 260.0

# ---------------- 出刀动作 ----------------

const SWING_TIME := 0.24      ## 一整刀（蓄势 + 挥出 + 归位）
const SWING_WINDUP := 0.09    ## 蓄势：器身后摆压缩
const SWING_ACTIVE := 0.07    ## 挥出：弧光扫放，伤害在这一段终点结算
const SWING_BACK := deg_to_rad(26.0)  ## 蓄势后摆角
const SWING_PUNCH := 0.16     ## 挥出瞬间器身放大（一刀劈出去的爆发感）
const SLASH_LUNGE := 14.0     ## 弧光圆心相对幻影的前突距离
const SLASH_ART_OUTER := 124.0  ## == WeaponArcRenderer.OUTER（画布外缘半径，缩放基准）
const SLASH_SCALE := 0.62     ## 弧光终态缩放 ⇒ 判定半径 ≈ 77px（与真近战本体 75px 同档）
const SLASH_SCALE_IN := 0.30  ## 弧光起始缩放（从剑上扫出去）
const SLASH_HALF_DEG := 70.0  ## == WeaponArcRenderer.MELEE_HALF（张角同源）
const SLASH_ANGLE_SLACK := 6.0  ## 角度宽容（度）：羽化边擦到的也算中
const SLASH_CLOSE_GRACE := 20.0 ## 贴脸宽容：距离小于它不看角度（与 SweepHandler 同一条）

# ---------------- 外观 ----------------

const FORM_TIME := 0.10       ## 凝形时长：六把一起现形，看清「多出来了 6 把」
const FORM_SCALE_IN := 0.35   ## 凝形起始缩放
const FADE_TIME := 0.20       ## 消散时长
const VISUAL_SCALE := 0.55    ## 器形缩放（与 FloatingWeapon 的矢量本体同档）
const GHOST_ALPHA := 0.85     ## 虚影不透明度：加色混合下 0.85 足够亮，再高会盖掉真剑
const BREATH_AMP := 0.13      ## 待机呼吸幅度（相对 GHOST_ALPHA）：驻场四秒，完全不动会被读成贴图
const RETARGET_INTERVAL := 0.1  ## 索敌节流（10Hz）：6 道幻影 × 60fps 逐帧查询是白烧

# ---------------- 虚幻感套件（2026-10-27：用户口径「更有虚幻的感觉」） ----------------
# 三件套全部确定性 sin、以 _breath_phase（instance_id 播种）错相，不碰任何 RNG（铁律 15）；
# 微漂只加在渲染子节点上，判定中心 == 节点本体，纹丝不动（画判同源不破）。

const HALO_SCALE_MULT := 1.35 ## 光晕放大倍率：同器形柔光外壳，读作「能量体」而非半透明铁剑
const HALO_ALPHA := 0.26      ## 光晕相对不透明度（再乘本体 modulate.a）
const ECHO_ALPHA := 0.20      ## 轨道回声相对不透明度（再乘本体 modulate.a）
const ECHO_LAG := 0.42        ## 回声滞后角（rad）：读作虚影掠过留下的残迹
const SHIMMER_AMP := 0.16     ## 高频微闪幅度（叠在慢呼吸之上）：灵体不稳的细碎闪烁
const DRIFT_AMP := 0.8        ## 渲染微漂幅度（px）：只漂视觉子节点，判定中心不动

## 对象池上限（一次开阵最多 6 道，留一倍余量）
const POOL_CAP := 12

# ---------------- 状态机 ----------------

const STATE_FORM := 0  ## 凝形：原地放大点亮
const STATE_IDLE := 1  ## 驻场：绕玩家转圈并按节奏劈弧
const STATE_FADE := 2  ## 消散：化光回池

# ---------------- 战斗字段（开阵方在 activate 前写好） ----------------

var weapon_def_id: String = ""   ## 器形来源（同一把剑的虚影，不是另一把武器）
var star: int = 1
var element: String = ""         ## 五行元素（决定幻影色温与弧光配色）
var source_weapon: Node = null   ## 源武器（弱引用；每刀现取实伤与异常配置，回池即清）
var source_behavior: int = WeaponData.Behavior.MELEE
var orbit_phase: float = 0.0     ## 本道在剑阵里的起始方位角
var damage: float = 0.0          ## 上一刀的伤害快照（源武器失效时兜底）

# ---------------- 运行态 ----------------

var _state: int = STATE_FORM
var _age: float = 0.0
var _life_left: float = FORMATION_TIME
var _shot_cd: float = 0.0
var _swing_age: float = -1.0      ## <0 = 没在出刀
var _hit_done: bool = false
var _swing_back: float = 0.0
var _swing_lunge: float = 0.0
var _pooled: bool = false
var _def: Dictionary = {}
var _breath_phase: float = 0.0
var _target: Node2D = null
var _retarget_phase: float = 0.0

var _renderer: ProceduralWeaponRenderer = null
var _halo: ProceduralWeaponRenderer = null   ## 光晕外壳：放大同器形，能量体外辉
var _echo: ProceduralWeaponRenderer = null   ## 轨道回声：top_level 滞后位残迹
var _slash_arc: WeaponArcRenderer = null
var _tint: Color = Color.WHITE
var _upright: bool = false
var _blade_len: float = 22.0
var _use_fallback_blade: bool = false

# ---------------- 剑意槽与剑阵状态（全局，不按武器分账） ----------------

## 当前剑意层数（0..CHARGE_EVERY）
static var _charge: int = 0
## 在场剑阵数：>0 表示剑阵正在运转（期间剑意不涨，避免开阵即常驻）
static var _forming_count: int = 0
## 每次开阵把阵首方位推进一点（纯演出，用固定步进而非 RNG —— 铁律 15）
static var _ring_phase: float = 0.0

static func charge() -> int:
	return _charge

static func reset_charge() -> void:
	_charge = 0

## 剑阵是否正在运转
static func formation_active() -> bool:
	return _forming_count > 0

## 剑阵剩余时间（判据与 HUD 用；无阵时返回 0）
static func formation_left() -> float:
	var best: float = 0.0
	if _host == null or not is_instance_valid(_host):
		return best
	for child in _host.get_children():
		var ph := child as SwordPhantom
		if ph != null and not ph._pooled and ph._life_left > best:
			best = ph._life_left
	return best

## 剑系武器每次出手的唯一入口（FloatingWeapon._perform_attack 末尾调用）。
## 非剑系武器出手不涨剑意；万剑归宗未生效时槽恒为 0（不残留上一局/上一次的层数）。
## 剑阵运转期间不再攒意 —— 否则剑阵一结束立刻又能开，等于常驻。
static func tick_attack(w) -> void:
	var snap: Dictionary = StatSystem.super_hook_snapshot(GameManager)
	if float(snap.get("sword_qi", 0.0)) <= 0.0:
		_charge = 0
		return
	if w == null or not is_instance_valid(w):
		return
	if WeaponData.class_of(String(w.weapon_def_id)) != "sword":
		return
	if formation_active():
		return
	_charge = mini(_charge + 1, CHARGE_EVERY)
	if _charge < CHARGE_EVERY:
		return
	var player: Node2D = GameManager.player
	if player == null or not is_instance_valid(player):
		return
	# 圈内没怪就把层数钳在阈值上等下一拍：剑意不在空气上浪费
	if open_formation(w.get_parent(), player) > 0:
		_charge = 0

## 开阵：玩家每一把剑系武器各幻化一道自己的幻影，在真剑外圈列成剑阵驻场。
## holder 传武器容器（weapon_holder），player 只用来定剑阵圆心与幻影宿主层。
## 返回实际放出的幻影数（0 = 圈内无敌人 / 无剑系武器 / 阵已在运转，调用方据此决定是否清空剑意）。
static func open_formation(holder: Node, player: Node2D) -> int:
	if formation_active():
		return 0
	if holder == null or not is_instance_valid(holder):
		return 0
	if player == null or not is_instance_valid(player):
		return 0
	var weapons: Array = []
	for child in holder.get_children():
		if child == null or not is_instance_valid(child):
			continue
		var wid_v: Variant = child.get("weapon_def_id")
		if not (wid_v is String):
			continue
		var wid: String = String(wid_v)
		if wid.is_empty() or WeaponData.class_of(wid) != "sword":
			continue
		weapons.append(child)
	if weapons.is_empty():
		return 0
	var targets: Array = ChainLightning.collect_in_radius(player.global_position, ACQUIRE_RADIUS)
	if targets.is_empty():
		return 0
	var scene: PackedScene = _phantom_scene()
	if scene == null:
		return 0
	var parent: Node = player.get_tree().current_scene if player.get_tree() != null else holder
	if parent == null:
		return 0
	_ring_phase = fposmod(_ring_phase + 0.7, TAU)
	var count: int = weapons.size()
	var fired := 0
	for i in range(count):
		var wpn = weapons[i]
		var wid: String = String(wpn.weapon_def_id)
		var ph: SwordPhantom = acquire_or_new(scene, parent)
		if ph == null:
			continue
		var ang: float = _ring_phase + TAU * float(i) / float(count)
		ph.orbit_phase = ang
		ph.global_position = player.global_position + Vector2(
			cos(ang) * ORBIT_RADII.x, sin(ang) * ORBIT_RADII.y)
		ph.weapon_def_id = wid
		ph.star = int(wpn.star)
		ph.element = _element_of(wid)
		ph.damage = float(wpn._final_damage()) * DAMAGE_RATIO
		ph.source_behavior = int(wpn.behavior)
		ph.source_weapon = wpn
		ph.activate()
		fired += 1
	if fired > 0:
		# 一次开阵一声（不逐道叠），响度压在普通开火之上、暴击之下
		AudioManager.play_sfx("sword_qi_wave", 0.75)
		GameFeel.micro_kick(GameManager, Vector2.ZERO, 2.4)
	return fired

## 元素口径与 FloatingWeapon._arc_element 同源（含雷系的 tags 兜底），
## 但不回调宿主私有方法，保持本文件对 FloatingWeapon 零依赖。
static func _element_of(wid: String) -> String:
	var e: String = WeaponData.element_of(wid)
	if e.is_empty() and WeaponData.tags_of(wid).has("thunder"):
		e = "thunder"
	return e

# ---------------- 生命周期 ----------------

func _ready() -> void:
	z_index = 20            # 幻影是光，压在实体与地面贴花之上
	_breath_phase = fposmod(float(get_instance_id() % 89) * 0.071, TAU)
	_slash_arc = WeaponArcRenderer.new()
	_slash_arc.name = "PhantomSlash"
	_slash_arc.configure(WeaponArcRenderer.ArcMode.MELEE, "metal")
	# top_level：弧光吃世界变换，不受本体蓄势缩放/呼吸影响 —— 否则「画多大==判多大」会跟着漂
	_slash_arc.top_level = true
	_slash_arc.visible = false
	add_child(_slash_arc)
	set_physics_process(false)

func activate() -> void:
	_pooled = false
	active_count += 1
	_forming_count += 1
	# 池化节点休眠时停在消散点，复用是瞬移到剑阵位：不重置物理插值会看到「从旧位置滑过来」
	reset_physics_interpolation()
	_def = WeaponData.get_def(weapon_def_id)
	_state = STATE_FORM
	_age = 0.0
	_life_left = FORMATION_TIME
	# 首刀错相：六道同帧出刀会齐射成一排，各给一个随机起点（走玩法 RNG，判据钉得住）
	_shot_cd = GameManager.rng.randf_range(0.15, FIRE_CD * 0.85)
	_retarget_phase = fposmod(float(get_instance_id() % 71) * 0.001, RETARGET_INTERVAL)
	_swing_age = -1.0
	_hit_done = false
	_swing_back = 0.0
	_swing_lunge = 0.0
	_target = null
	scale = Vector2.ONE * FORM_SCALE_IN
	rotation = orbit_phase + PI * 0.5
	modulate = Color(1.0, 1.0, 1.0, 0.0)
	visible = true
	_configure_visual()
	_apply_child_facing()
	if _slash_arc != null:
		_slash_arc.configure(WeaponArcRenderer.ArcMode.MELEE, element)
		_slash_arc.visible = false
		_slash_arc.modulate.a = 0.0
	set_physics_process(true)
	queue_redraw()

func _physics_process(delta: float) -> void:
	if _pooled:
		return
	_age += delta
	match _state:
		STATE_FORM:
			_tick_form()
		STATE_IDLE:
			_tick_idle(delta)
		STATE_FADE:
			_tick_fade()
			return
	if _state == STATE_FORM:
		queue_redraw()

## 凝形：0.35 倍炸到 1.06 再落回 1.0（过冲一拍 = 「凝」出来的实感），同时点亮
func _tick_form() -> void:
	var k: float = clampf(_age / FORM_TIME, 0.0, 1.0)
	var grow: float = lerpf(FORM_SCALE_IN, 1.06, k) if k < 0.82 else lerpf(1.06, 1.0, (k - 0.82) / 0.18)
	scale = Vector2.ONE * grow
	modulate.a = GHOST_ALPHA * clampf(k / 0.45, 0.0, 1.0)
	if _age >= FORM_TIME:
		_state = STATE_IDLE
		scale = Vector2.ONE
		modulate.a = GHOST_ALPHA
		if _echo != null and not _use_fallback_blade:
			_echo.visible = true   # 回声只在驻场段亮
		queue_redraw()

## 驻场：走剑阵轨道 → 到点劈弧 → 时辰到了开始化光。
## 顺序有讲究：先算动作相位（后摆/前突）→ 再定位（轨道位 + 前突）→ 再摆弧光（top_level 世界变换）
## → 最后结算伤害。伤害必须落在「本帧已经摆好的位置」上，否则判定会比画面晚一帧。
func _tick_idle(delta: float) -> void:
	_life_left -= delta
	if _life_left <= 0.0:
		_enter_fade()
		return
	_tick_target(delta)
	_tick_swing_phase(delta)
	_tick_orbit()
	_update_slash_arc()
	_tick_hit()
	_tick_fire(delta)
	# 驻场呼吸 + 高频微闪：慢呼吸防读成贴图，细碎 shimmer 读「灵体不稳」
	var breath: float = 1.0 - BREATH_AMP * 0.5 + BREATH_AMP * 0.5 * sin(_age * 3.1 + _breath_phase)
	var shimmer: float = 1.0 - SHIMMER_AMP * 0.5 + SHIMMER_AMP * 0.5 * sin(_age * 17.3 + _breath_phase * 3.7)
	modulate.a = GHOST_ALPHA * breath * shimmer
	# 渲染微漂：只漂视觉子节点（≤1px），判定中心 = 节点本体纹丝不动（画判同源不破）
	var drift := Vector2(
		sin(_age * 9.1 + _breath_phase), cos(_age * 7.3 + _breath_phase * 1.3)) * DRIFT_AMP
	if _renderer != null:
		_renderer.position = drift
	if _halo != null:
		_halo.position = drift * 1.6   # 光晕漂得比本体略散，辉光更「活」
	_update_echo()

## 轨道回声：同器形副本摆在轨道滞后位（ang − ECHO_LAG），读作虚影掠过留下的残迹。
## 轨道解析可算，不用存位置历史；top_level 自己吃世界变换，透明度随本体 modulate 叠乘呼吸。
func _update_echo() -> void:
	if _echo == null or not _echo.visible:
		return
	var player: Node2D = GameManager.player
	if player == null or not is_instance_valid(player):
		return
	var lag_ang: float = orbit_phase + _age * ORBIT_SPEED - ECHO_LAG
	_echo.global_position = player.global_position + Vector2(
		cos(lag_ang) * ORBIT_RADII.x, sin(lag_ang) * ORBIT_RADII.y)
	# 竖置重器回声同守「世界竖直」，其余朝轨道切线（与无目标时的出刀朝向同源）
	_echo.global_rotation = 0.0 if _upright else lag_ang + PI * 0.5

## 索敌（10Hz 节流 + 实例错相）：剑阵要打「圈内最近的那只」，不是永远追同一个
func _tick_target(delta: float) -> void:
	if _target != null and (not is_instance_valid(_target) or bool(_target.get("dying"))):
		_target = null
	_retarget_phase -= delta
	if _retarget_phase > 0.0:
		return
	_retarget_phase = RETARGET_INTERVAL
	_target = _find_target()

## 出刀朝向：有目标瞄目标，没目标朝轨道外侧（剑阵外扩的姿态）
func _aim_dir() -> Vector2:
	if _target != null and is_instance_valid(_target):
		var to: Vector2 = _target.global_position - global_position
		if to.length_squared() > 1.0:
			return to.normalized()
	return Vector2.RIGHT.rotated(orbit_phase + _age * ORBIT_SPEED + PI * 0.5)

## 轨道：以玩家为圆心的外圈椭圆，整阵按 ORBIT_SPEED 缓慢自转；出刀时叠前突与后摆
func _tick_orbit() -> void:
	var player: Node2D = GameManager.player
	if player == null or not is_instance_valid(player):
		_enter_fade()
		return
	var ang: float = orbit_phase + _age * ORBIT_SPEED
	var dir: Vector2 = _aim_dir()
	global_position = player.global_position + Vector2(
		cos(ang) * ORBIT_RADII.x, sin(ang) * ORBIT_RADII.y) + dir * _swing_lunge
	rotation = dir.angle() + _swing_back
	_apply_child_facing()

## 出刀三段的动作相位：蓄势后摆 → 挥出前突 → 归位。只算姿态，不碰判定与位置。
func _tick_swing_phase(delta: float) -> void:
	if _swing_age < 0.0:
		return
	_swing_age += delta
	var hit_at: float = SWING_WINDUP + SWING_ACTIVE
	if _swing_age < SWING_WINDUP:
		var k: float = _swing_age / SWING_WINDUP
		_swing_back = -SWING_BACK * k
		_swing_lunge = 0.0
		scale = Vector2.ONE * (1.0 - 0.08 * k)
	elif _swing_age < hit_at:
		var k: float = (_swing_age - SWING_WINDUP) / SWING_ACTIVE
		_swing_back = -SWING_BACK * (1.0 - k)
		_swing_lunge = SLASH_LUNGE * k
		scale = Vector2.ONE * (1.0 + SWING_PUNCH * k)
	else:
		var k: float = clampf((_swing_age - hit_at) / maxf(SWING_TIME - hit_at, 0.001), 0.0, 1.0)
		_swing_back = 0.0
		_swing_lunge = SLASH_LUNGE * (1.0 - k)
		scale = Vector2.ONE * (1.0 + SWING_PUNCH * (1.0 - k))
	if _swing_age >= SWING_TIME:
		_swing_age = -1.0
		_swing_back = 0.0
		_swing_lunge = 0.0
		scale = Vector2.ONE
		if _slash_arc != null:
			_slash_arc.visible = false

## 伤害结算：挥出段终点那一帧结算一次（本帧位置已由 _tick_orbit 摆好）
func _tick_hit() -> void:
	if _hit_done or _swing_age < 0.0:
		return
	if _swing_age < SWING_WINDUP + SWING_ACTIVE:
		return
	_hit_done = true
	_apply_slash_hit()

## 弧光扫放：蓄势段不显，挥出段从 0.30 倍扫到终态（此时判定圆 == 弧光外缘），归位段淡出
func _update_slash_arc() -> void:
	if _slash_arc == null:
		return
	var hit_at: float = SWING_WINDUP + SWING_ACTIVE
	if _swing_age < SWING_WINDUP:
		_slash_arc.visible = false
		return
	# top_level：自己摆世界变换，本体缩放/转角一概不吃（画判同源）
	var dir: Vector2 = _aim_dir()
	_slash_arc.global_position = global_position + dir * SLASH_LUNGE
	_slash_arc.global_rotation = dir.angle()
	if _swing_age < hit_at:
		var k: float = (_swing_age - SWING_WINDUP) / SWING_ACTIVE
		_slash_arc.visible = true
		_slash_arc.scale = Vector2.ONE * lerpf(SLASH_SCALE_IN, SLASH_SCALE, k)
		_slash_arc.modulate.a = 1.0
		return
	var k: float = clampf((_swing_age - hit_at) / maxf(SWING_TIME - hit_at, 0.001), 0.0, 1.0)
	_slash_arc.visible = true   # 命中帧可能正好落在这条分支的第一帧，visible 必须无条件置真
	_slash_arc.scale = Vector2.ONE * SLASH_SCALE
	_slash_arc.modulate.a = 1.0 - k
	if k >= 1.0:
		_slash_arc.visible = false

## 出刀计时：冷却到点就起一刀；圈内没怪时不空劈也不烧穿冷却（目标一进来立刻出刀）
func _tick_fire(delta: float) -> void:
	if _swing_age >= 0.0:
		return
	_shot_cd -= delta
	if _shot_cd > 0.0:
		return
	if _target == null or not is_instance_valid(_target):
		_shot_cd = 0.0
		return
	_swing_age = 0.0
	_hit_done = false
	_shot_cd = FIRE_CD * GameManager.rng.randf_range(1.0 - FIRE_CD_JITTER, 1.0 + FIRE_CD_JITTER)

## 单刀结算：判定圆半径 == 弧光外缘（画多大==判多大），再按张角过滤 ——
## 与 SweepHandler 同一份代码形状，只是伤害已在出刀帧按源武器实伤快照好。
## 【不吸血、不回灌剑意】：幻影是额外的一刀，吸血只认真剑那一下。
func _apply_slash_hit() -> void:
	var base_dmg: float = _shot_damage()
	if base_dmg <= 0.0:
		return
	var dir: Vector2 = _aim_dir()
	var center: Vector2 = global_position + dir * SLASH_LUNGE
	var radius: float = SLASH_ART_OUTER * SLASH_SCALE
	var half: float = deg_to_rad(SLASH_HALF_DEG + SLASH_ANGLE_SLACK)
	var results: Array = _query_enemies(radius, center, 12)
	if results.is_empty():
		return
	var kb_force: float = WeaponData.knockback_for(weapon_def_id, 280.0) * DAMAGE_RATIO
	var proc_burn: bool = bool(_def.get("proc_burn", false))
	var proc_chill: float = float(_def.get("proc_chill", 0.0))
	var proc_poison: bool = bool(_def.get("proc_poison", false))
	var any_proc: bool = proc_burn or proc_chill > 0.0 or proc_poison
	var has_mech: bool = OnHitEffects.any_enabled()
	var mech: Dictionary = OnHitEffects.snapshot() if has_mech else {}
	for res in results:
		var col = res.get("collider")
		var enemy = col.get_parent() if col != null else null
		if enemy == null or not enemy.has_method("take_damage"):
			continue
		var to_enemy: Vector2 = enemy.global_position - center
		if to_enemy.length() > SLASH_CLOSE_GRACE and absf(dir.angle_to(to_enemy)) > half:
			continue
		var dmg: float = base_dmg
		var is_crit: bool = GameManager.roll_crit()
		if is_crit:
			dmg *= GameManager.get_crit_mult()
		dmg *= GameManager.elite_damage_mult_for(enemy)
		var knock: Vector2 = GameManager.knockback_vec(center, enemy.global_position, kb_force)
		enemy.take_damage(dmg, knock, is_crit)
		if any_proc:
			ProcStatus.apply(enemy, proc_burn,
				dmg * float(_def.get("burn_ratio", 0.45)), float(_def.get("burn_dur", 3.0)),
				proc_chill, float(_def.get("chill_dur", 2.5)),
				proc_poison, dmg * float(_def.get("poison_ratio", 0.35)), float(_def.get("poison_dur", 3.0)))
		if has_mech and source_weapon != null and is_instance_valid(source_weapon):
			OnHitEffects.on_weapon_hit(source_weapon, enemy, dmg, is_crit, mech)

## 单刀伤害：源武器还在就现取实伤（剑阵 4 秒里玩家可能又吃到加成），失效则用开阵快照
func _shot_damage() -> float:
	if source_weapon != null and is_instance_valid(source_weapon) and source_weapon.has_method("_final_damage"):
		damage = float(source_weapon._final_damage()) * DAMAGE_RATIO
	return damage

func _enter_fade() -> void:
	if _state == STATE_FADE:
		return
	_state = STATE_FADE
	_age = 0.0
	_swing_age = -1.0
	_swing_back = 0.0
	_swing_lunge = 0.0
	if _slash_arc != null:
		_slash_arc.visible = false
	if _echo != null:
		_echo.visible = false
	if _renderer != null:
		_renderer.position = Vector2.ZERO
	if _halo != null:
		_halo.position = Vector2.ZERO
	queue_redraw()

## 消散：化光散尽后回池
func _tick_fade() -> void:
	var k: float = clampf(_age / FADE_TIME, 0.0, 1.0)
	modulate.a = GHOST_ALPHA * (1.0 - k)
	scale = Vector2.ONE * lerpf(1.0, 1.28, k)
	if _age >= FADE_TIME:
		_recycle()

## 索敌：幻影自己射程内最近的活敌（濒死标记跳过），全程鸭类型（项目坑 12）
func _find_target():
	var results: Array = _query_enemies(FIRE_RANGE, global_position, 12)
	var best = null
	var best_d: float = INF
	for res in results:
		var col = res.get("collider")
		var enemy = col.get_parent() if col != null else null
		if enemy == null or not enemy.has_method("take_damage"):
			continue
		if bool(enemy.get("dying")):
			continue
		var d: float = global_position.distance_squared_to(enemy.global_position)
		if d < best_d:
			best_d = d
			best = enemy
	return best

# ---------------- 视觉 ----------------

## 幻影外观：复用 ProceduralWeaponRenderer 画【同一把剑】的器形（形状/器尖/星级完全一致），
## 只把配色换成元素 HDR + 加色混合 + 半透明 —— 读起来是「这把剑的虚影」，
## 而不是另一把武器（用户口径：「显示效果会有一点点区别」）。
## 未实现矢量器形（GENERIC）的武器回落到 _draw 里的一枚光刃，绝不加载贴图（保持虚影一致）。
func _configure_visual() -> void:
	var def: Dictionary = _def if not _def.is_empty() else WeaponData.get_def(weapon_def_id)
	var wshape: int = ProceduralWeaponRenderer.shape_from_name(String(def.get("shape", "")))
	var tip: Vector2 = def.get("tip", Vector2(22, 0))
	_upright = bool(def.get("upright", false))
	_blade_len = maxf(tip.length(), 12.0)
	_use_fallback_blade = wshape == ProceduralWeaponRenderer.WeaponShape.GENERIC
	_tint = GameStyle.fx_hdr_element(element)
	if _use_fallback_blade:
		# 光刃兜底形态不配光晕/回声 —— 矢量器形都没有，虚影套件无从复制
		if _renderer != null:
			_renderer.visible = false
		if _halo != null:
			_halo.visible = false
		if _echo != null:
			_echo.visible = false
		return
	if _halo == null:
		_halo = ProceduralWeaponRenderer.new()
		_halo.name = "ProcPhantomHalo"
		_halo.material = SharedMaterials.add_blend()
		add_child(_halo)
		move_child(_halo, 0)   # 光晕垫在主器形底下
	if _renderer == null:
		_renderer = ProceduralWeaponRenderer.new()
		_renderer.name = "ProcPhantom"
		_renderer.material = SharedMaterials.add_blend()
		add_child(_renderer)
	if _echo == null:
		_echo = ProceduralWeaponRenderer.new()
		_echo.name = "ProcPhantomEcho"
		_echo.material = SharedMaterials.add_blend()
		# top_level：回声吃「轨道滞后位」的世界变换，不吃本体转角/缩放
		_echo.top_level = true
		add_child(_echo)
	_halo.configure(wshape, element, _blade_len, star, _upright, weapon_def_id)
	_halo.scale = Vector2.ONE * VISUAL_SCALE * HALO_SCALE_MULT
	_halo.modulate = Color(_tint.r, _tint.g, _tint.b, HALO_ALPHA)
	_halo.visible = true
	_renderer.configure(wshape, element, _blade_len, star, _upright, weapon_def_id)
	_renderer.scale = Vector2.ONE * VISUAL_SCALE
	_renderer.modulate = _tint
	_renderer.visible = true
	_echo.configure(wshape, element, _blade_len, star, _upright, weapon_def_id)
	_echo.scale = Vector2.ONE * VISUAL_SCALE
	_echo.modulate = Color(_tint.r, _tint.g, _tint.b, ECHO_ALPHA)
	_echo.visible = false   # 回声只在驻场段亮（凝形/消散段隐藏）

## 竖置重器（锤/鞭/锏等）反向补偿转角，保持世界竖直 ——
## 与 FloatingWeapon._apply_facing 同一条规则，幻影的姿态读起来才和真剑一致。
func _apply_child_facing() -> void:
	var fix: float = (-rotation) if _upright else 0.0
	if _renderer != null and _renderer.visible:
		_renderer.rotation = fix
	if _halo != null and _halo.visible:
		_halo.rotation = fix

func _draw() -> void:
	# 矢量器形未实现时的光刃兜底（与器尖同长，不引入贴图）
	if _use_fallback_blade:
		var c := _tint
		c.a = 0.9
		draw_colored_polygon(PackedVector2Array([
			Vector2(0.0, -2.2), Vector2(_blade_len * 0.82, -1.4), Vector2(_blade_len, 0.0),
			Vector2(_blade_len * 0.82, 1.4), Vector2(0.0, 2.2),
		]), c)
	# 凝形灵环：向外推开的一圈虚影光，给「幻化出来」一个读点（不依赖任何池化特效）
	if _state == STATE_FORM:
		var k: float = clampf(_age / FORM_TIME, 0.0, 1.0)
		var ring := _tint
		ring.a = 0.55 * (1.0 - k)
		draw_arc(Vector2.ZERO, lerpf(8.0, 30.0, k), 0.0, TAU, 18, ring, 1.6, true)

# ---------------- 对象池（照 SwordQiWave / BladeProjectile 范式） ----------------

static var _pool: Array[SwordPhantom] = []
static var _host: Node2D = null
static var created_count: int = 0
static var reused_count: int = 0
static var active_count: int = 0
static var _scene_cache: PackedScene = null

static var _search_shape: CircleShape2D = null
static var _search_query: PhysicsShapeQueryParameters2D = null

## 场景按需 load（不在文件头 preload 自己的 .tscn —— 那会构成脚本↔场景自引用）
static func _phantom_scene() -> PackedScene:
	if _scene_cache == null:
		_scene_cache = load("res://scenes/weapons/SwordPhantom.tscn") as PackedScene
	return _scene_cache

static func clear_pool() -> void:
	_pool.clear()
	active_count = 0
	_forming_count = 0
	_host = null
	_charge = 0
	_scene_cache = null

static func _ensure_host(parent: Node) -> void:
	if _host != null and is_instance_valid(_host):
		return
	_pool.clear()
	_host = Node2D.new()
	_host.name = "SwordPhantomPool"
	parent.add_child(_host)

static func acquire_or_new(scene: PackedScene, parent: Node) -> SwordPhantom:
	_ensure_host(parent)
	while not _pool.is_empty():
		var p: SwordPhantom = _pool.pop_back()
		if is_instance_valid(p):
			reused_count += 1
			return p
	var np := scene.instantiate() as SwordPhantom
	if np == null:
		return null
	created_count += 1
	_host.add_child(np)
	return np

## 回池休眠：物理与弧光一起停（三件套同拍，项目坑 13），战果字段清残值防复用污染
func _recycle() -> void:
	if _pooled:
		return
	_pooled = true
	active_count = maxi(0, active_count - 1)
	_forming_count = maxi(0, _forming_count - 1)
	set_physics_process(false)
	visible = false
	if _echo != null:
		_echo.visible = false
	if _slash_arc != null:
		_slash_arc.visible = false
		_slash_arc.modulate.a = 0.0
	if _renderer != null:
		_renderer.position = Vector2.ZERO
	if _halo != null:
		_halo.position = Vector2.ZERO
	_target = null
	source_weapon = null
	source_behavior = WeaponData.Behavior.MELEE
	damage = 0.0
	_swing_age = -1.0
	_hit_done = false
	_shot_cd = 0.0
	_life_left = 0.0
	_def.clear()
	if _host == null or not is_instance_valid(_host) or _pool.size() >= POOL_CAP:
		queue_free()
		return
	_pool.append(self)

## 以 center 为圆心查敌人受击区（碰撞层 4），与 FloatingWeapon._query_enemies 同参数
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
