class_name SwordPhantom
extends Node2D

## 万剑归宗（飞升悟道）的幻影剑实体（2026-10-26 重塑）。
##
## 用户口径：「一个圆圈的余波，我不知道有什么用啊，有什么伤害」→ 换成
## 「悬浮的剑系装备可以幻化出一个幻影，如果我现在有 6 把剑系装备，那就幻化出 6 把，
## 一共十二把一起进行攻击，这才有点万剑归宗的效果」。
##
## 机制：全局剑意槽（`tick_attack`）—— 任一【剑系】武器每次出手 +1，攒满 CHARGE_EVERY 层
## 就开阵：玩家身上每一把剑系武器各幻化出一道自己的幻影，凝形一拍后依次疾射，
## 各自斩向锁定的敌人，命中即散。真剑继续正常攻击，不打断原节奏。
##
## 与旧实现的差别（为什么删掉圆形余波）：
##   旧 = 近战命中累计 3 次 → 在命中点放一圈 150px 冲击波，视觉只有一圈涟漪 + 8 道短线，
##        玩家读不出「打了谁、打了多少」，也没有「万剑」的意象。
##   新 = 剑的数量直接变成齐射的数量（6 剑 = 12 把同场），伤害落在看得见的每一道幻影上。
##
## 纪律：
##   · 全程鸭类型访问敌人（has_method("take_damage")），绝不硬引用 EnemyBase / FloatingWeapon
##     —— 武器侧硬类型引用会构成循环类依赖，把 preload 打成空 PackedScene（项目坑 12/16）。
##   · 幻影命中【禁止回灌剑意】：否则一道幻影打中就算一次出手，会自激成无限剑阵。
##   · 画多大 == 判多大（铁律 6）：HIT_RADIUS 与器身可见几何同档，不用辉光糊大。
##   · 判定随机走 GameManager.rng（暴击/击退），演出随机一律不用（本文件无演出随机）。

# ---------------- 机制常量（数值唯一真话） ----------------

## 剑意槽容量：剑系武器每次出手 +1，攒满开阵。
## 8 层是「1 把剑约 8 秒一轮、6 把剑约 1.3 秒一轮」的折中 —— 剑越多越像万剑归宗，
## 这正是卡名要表达的东西；再低会吵成大招常驻，再高则一局见不到几次。
const CHARGE_EVERY := 8
## 幻影伤害占源武器单发实伤的比例（与旧圆形余波 0.75 同档，不额外膨胀）
const DAMAGE_RATIO := 0.75
## 开阵索敌半径（px）：圈内一个敌人都没有时【不消耗剑意】，怪一进圈立刻开，不浪费在空气上
const ACQUIRE_RADIUS := 300.0

# ---------------- 手感常量 ----------------

## 凝形时长：幻影从 0.35 倍炸到全尺寸并点亮，六把一起现形（看清「多出来了 6 把」）
const FORM_TIME := 0.09
## 凝形起始缩放
const FORM_SCALE_IN := 0.35
## 疾射速度（px/s）：比剑气凌霄的 420 快一倍多，读作「射出去的剑」而不是「飘过去的弧」
const DASH_SPEED := 900.0
## 单道幻影最长航程（px）：索敌半径 300 + 余量，够到锁定的每一个目标
const MAX_TRAVEL := 320.0
## 命中判定半径（px）：敌人受击圈 15px + 器身余量，与幻影器形同档（画多大==判多大）
const HIT_RADIUS := 22.0
## 逐道起射错相（秒）：六道同一帧射出会糊成一片，错开一点才读得出「一把把飞出去」
const STAGGER := 0.02
## 消散时长
const FADE_TIME := 0.16
## 器形缩放（与 FloatingWeapon 的 Sprite2D / 矢量本体同档）
const VISUAL_SCALE := 0.55
## 虚影整体不透明度：加色混合下 0.85 已经足够亮，再高会盖掉真剑
const GHOST_ALPHA := 0.85
## 命中火花（与 StrikeFx / SwordQiWave 同档，不跨引防类循环）
const SPARK_SCALE := 0.85
const CRIT_SPARK_SCALE := 1.5
const SPARK_EDGE := 14.0

## 对象池上限（一次齐射最多 6 道，留一倍余量）
const POOL_CAP := 12

# ---------------- 状态机 ----------------

const STATE_FORM := 0   ## 凝形：原地放大点亮
const STATE_READY := 1  ## 待射：错相等待（六把同时现形后依次射出）
const STATE_DASH := 2   ## 疾射：朝锁定目标飞
const STATE_FADE := 3   ## 消散：命中或航程耗尽后化光

# ---------------- 战斗字段（出膛方在 activate 前写好） ----------------

var direction: Vector2 = Vector2.RIGHT
var target: Node2D = null        ## 锁定目标（弱引用；途中死亡则直飞原方向）
var damage: float = 0.0
var knockback_force: float = 280.0
var element: String = ""         ## 五行元素（决定幻影色温）
var weapon_def_id: String = ""   ## 器形来源（同一把剑的虚影，不是另一把武器）
var star: int = 1
var source_behavior: int = WeaponData.Behavior.MELEE
var source_weapon: Node = null   ## 机制卡命中结算用（弱引用，回池即清）
var delay: float = 0.0           ## 起射错相（秒）
var proc_burn: bool = false
var burn_ratio: float = 0.45
var burn_dur: float = 3.0
var proc_chill: float = 0.0
var chill_dur: float = 2.5
var proc_poison: bool = false
var poison_ratio: float = 0.35
var poison_dur: float = 3.0

# ---------------- 运行态 ----------------

var _state: int = STATE_FORM
var _t: float = 0.0
var _travel: float = 0.0
var _has_hit: bool = false
var _pooled: bool = false
var _has_mech: bool = false
var _mech: Dictionary = {}

var _renderer: ProceduralWeaponRenderer = null
var _trail: ProjectileTrail = null
var _tint: Color = Color.WHITE
var _upright: bool = false
var _blade_len: float = 22.0
var _use_fallback_blade: bool = false

# ---------------- 剑意槽（全局，不按武器分账） ----------------

## 当前剑意层数（0..CHARGE_EVERY）
static var _charge: int = 0

static func charge() -> int:
	return _charge

static func reset_charge() -> void:
	_charge = 0

## 剑系武器每次出手的唯一入口（FloatingWeapon._perform_attack 末尾调用）。
## 非剑系武器出手不涨剑意；万剑归宗未生效时槽恒为 0（不残留上一局/上一次的层数）。
static func tick_attack(w) -> void:
	var snap: Dictionary = StatSystem.super_hook_snapshot(GameManager)
	if float(snap.get("sword_qi", 0.0)) <= 0.0:
		_charge = 0
		return
	if w == null or not is_instance_valid(w):
		return
	if WeaponData.class_of(String(w.weapon_def_id)) != "sword":
		return
	_charge = mini(_charge + 1, CHARGE_EVERY)
	if _charge < CHARGE_EVERY:
		return
	var player: Node2D = GameManager.player
	if player == null or not is_instance_valid(player):
		return
	# 圈内没怪就把层数钳在阈值上等下一拍：剑意不在空气上浪费
	if fire_volley(w.get_parent(), player) > 0:
		_charge = 0

## 开阵：玩家每一把剑系武器各幻化一道自己的幻影，齐射向最近的一圈敌人。
## holder 传武器容器（weapon_holder），player 只用来定索敌圆心与幻影宿主层。
## 返回实际放出的幻影数（0 = 圈内无敌人 / 无剑系武器，调用方据此决定是否清空剑意）。
static func fire_volley(holder: Node, player: Node2D) -> int:
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
	# 近的先分：目标比幻影多时逐个摊开，比幻影少时按序轮转（至少不出现空射）
	var center: Vector2 = player.global_position
	targets.sort_custom(func(a, b) -> bool:
		return center.distance_squared_to((a as Node2D).global_position) \
			< center.distance_squared_to((b as Node2D).global_position))
	var scene: PackedScene = _phantom_scene()
	if scene == null:
		return 0
	var parent: Node = player.get_tree().current_scene if player.get_tree() != null else holder
	if parent == null:
		return 0
	var fired := 0
	var idx := 0
	for wpn in weapons:
		var tgt: Node2D = targets[idx % targets.size()]
		idx += 1
		var wid: String = String(wpn.weapon_def_id)
		var from: Vector2 = (wpn as Node2D).global_position
		var dir: Vector2 = (tgt.global_position - from)
		dir = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
		var ph: SwordPhantom = acquire_or_new(scene, parent)
		if ph == null:
			continue
		var def: Dictionary = WeaponData.get_def(wid)
		ph.global_position = from
		ph.direction = dir
		ph.target = tgt
		ph.weapon_def_id = wid
		ph.star = int(wpn.star)
		ph.element = _element_of(wid)
		ph.damage = float(wpn._final_damage()) * DAMAGE_RATIO
		ph.knockback_force = WeaponData.knockback_for(wid, 280.0) * DAMAGE_RATIO
		ph.source_behavior = int(wpn.behavior)
		ph.source_weapon = wpn
		ph.delay = float(fired) * STAGGER
		ph.proc_burn = def.get("proc_burn", false)
		ph.burn_ratio = float(def.get("burn_ratio", 0.45))
		ph.burn_dur = float(def.get("burn_dur", 3.0))
		ph.proc_chill = float(def.get("proc_chill", 0.0))
		ph.chill_dur = float(def.get("chill_dur", 2.5))
		ph.proc_poison = def.get("proc_poison", false)
		ph.poison_ratio = float(def.get("poison_ratio", 0.35))
		ph.poison_dur = float(def.get("poison_dur", 3.0))
		ph.activate()
		fired += 1
	if fired > 0:
		# 一次齐射一声（不逐道叠），响度压在普通开火之上、暴击之下
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
	_trail = ProjectileTrail.new()
	_trail.name = "PhantomTrail"
	add_child(_trail)
	move_child(_trail, 0)   # 拖尾压在器形之下（子节点按序绘制）
	z_index = 20            # 幻影是光，压在实体与地面贴花之上
	set_physics_process(false)

func activate() -> void:
	_pooled = false
	active_count += 1
	# 池化节点休眠时停在消散点，复用是瞬移到剑旁：不重置物理插值会看到「从旧位置滑过来」
	reset_physics_interpolation()
	_state = STATE_FORM
	_t = 0.0
	_travel = 0.0
	_has_hit = false
	scale = Vector2.ONE * FORM_SCALE_IN
	rotation = direction.angle()
	modulate = Color(1.0, 1.0, 1.0, 0.0)
	visible = true
	_has_mech = OnHitEffects.any_enabled()
	_mech = OnHitEffects.snapshot() if _has_mech else {}
	_configure_visual()
	_apply_child_facing()
	if _trail != null:
		_trail.reset()
	set_physics_process(true)
	queue_redraw()

func _physics_process(delta: float) -> void:
	if _pooled:
		return
	_t += delta
	match _state:
		STATE_FORM:
			_tick_form()
		STATE_READY:
			_tick_ready(delta)
		STATE_DASH:
			_tick_dash(delta)
		STATE_FADE:
			_tick_fade()
			return
	# 凝形环与消散都靠 _draw 现算，只有这两段需要逐帧重绘
	if _state == STATE_FORM:
		queue_redraw()

## 凝形：0.35 倍炸到 1.06 再落回 1.0（过冲一拍 = 「凝」出来的实感），同时点亮
func _tick_form() -> void:
	var k: float = clampf(_t / FORM_TIME, 0.0, 1.0)
	var grow: float = lerpf(FORM_SCALE_IN, 1.06, k) if k < 0.82 else lerpf(1.06, 1.0, (k - 0.82) / 0.18)
	scale = Vector2.ONE * grow
	modulate.a = GHOST_ALPHA * clampf(k / 0.45, 0.0, 1.0)
	if _t >= FORM_TIME:
		_state = STATE_READY
		queue_redraw()

## 待射：六把幻影一起现形后按各自错相依次射出（同一帧全射会糊成一片）
func _tick_ready(delta: float) -> void:
	delay -= delta
	if delay <= 0.0:
		_enter_dash()

func _enter_dash() -> void:
	_state = STATE_DASH
	_t = 0.0
	_travel = 0.0
	queue_redraw()
	if _trail != null:
		_trail.configure(_tint)
		_trail.seed_point(global_position)

func _enter_fade() -> void:
	if _state == STATE_FADE:
		return
	_state = STATE_FADE
	_t = 0.0
	queue_redraw()

## 疾射：目标还在就一路追（锁定的怪被别的武器打死就直飞原方向，不追空位）
func _tick_dash(delta: float) -> void:
	_revalidate_target()
	if target != null:
		var to: Vector2 = target.global_position - global_position
		if to.length_squared() > 1.0:
			direction = to.normalized()
	rotation = direction.angle()
	_apply_child_facing()
	var prev: Vector2 = global_position
	var step: float = DASH_SPEED * delta
	global_position = prev + direction * step
	_travel += step
	if _trail != null:
		_trail.sample(global_position, delta)
	if _hit_check(prev, step):
		_enter_fade()
		return
	if _travel >= MAX_TRAVEL:
		_enter_fade()

## 消散：化光散尽后回池
func _tick_fade() -> void:
	var k: float = clampf(_t / FADE_TIME, 0.0, 1.0)
	modulate.a = GHOST_ALPHA * (1.0 - k)
	scale = Vector2.ONE * lerpf(1.0, 1.25, k)
	if _t >= FADE_TIME:
		_recycle()

## 锁定目标失效（被打死/被清场）就放弃追踪 —— 只判 is_instance_valid 与濒死标记，
## 全程鸭类型，不碰 EnemyBase 类型引用（项目坑 12）。
func _revalidate_target() -> void:
	if target == null:
		return
	if not is_instance_valid(target) or bool(target.get("dying")):
		target = null

## 命中判定：以「上一帧位置到当前位置的中点」为圆心、半径加上半个步长做扫掠，
## 防止高速（900px/s × 30fps = 30px/帧）从 22px 判定圈里穿过去漏判。
func _hit_check(prev: Vector2, step: float) -> bool:
	var mid: Vector2 = (prev + global_position) * 0.5
	var radius: float = HIT_RADIUS + step * 0.5
	var enemy = _find_enemy(mid, radius)
	if enemy == null:
		return false
	_apply_hit(enemy)
	return true

func _find_enemy(center: Vector2, radius: float):
	var results: Array = _query_enemies(radius, center, 8)
	var best = null
	var best_d: float = INF
	for res in results:
		var col = res.get("collider")
		var enemy = col.get_parent() if col != null else null
		if enemy == null or not enemy.has_method("take_damage"):
			continue
		var d: float = center.distance_squared_to(enemy.global_position)
		if d < best_d:
			best_d = d
			best = enemy
	return best

## 单个目标结算：满额实伤 + 逐敌暴击/精英乘区 + 顺飞行方向击退 + 五行异常 + 机制卡。
## 与 SwordQiWave._apply_hit 同一份代码形状（伤害已在出膛帧快照好）。
## 【不吸血、不回灌剑意】：幻影是额外齐射，吸血与剑意都只认真剑那一下，
## 否则 6 道幻影会在同一帧把吸血与剑意各刷 6 次（自激 + 奶量翻倍）。
func _apply_hit(enemy) -> void:
	var is_crit: bool = GameManager.roll_crit()
	var dmg: float = damage
	if is_crit:
		dmg *= GameManager.get_crit_mult()
	dmg *= GameManager.elite_damage_mult_for(enemy)
	var knock: Vector2 = GameManager.knockback_vec(global_position, enemy.global_position, knockback_force)
	if knock.length_squared() < 0.001:
		knock = direction * GameManager.knockback_force(knockback_force)
	enemy.take_damage(dmg, knock, is_crit)
	var spark_dir: Vector2 = knock.normalized() if knock.length_squared() > 1.0 else direction
	var spark_pos: Vector2 = enemy.global_position - spark_dir * SPARK_EDGE
	var spark_elem: Variant = "crit" if is_crit else element
	FxParticlePool.weapon_hit_spark(enemy, spark_pos, spark_elem,
		CRIT_SPARK_SCALE if is_crit else SPARK_SCALE, is_crit, spark_dir)
	if proc_burn or proc_chill > 0.0 or proc_poison:
		ProcStatus.apply(enemy, proc_burn, dmg * burn_ratio, burn_dur,
			proc_chill, chill_dur, proc_poison, dmg * poison_ratio, poison_dur)
	if _has_mech and source_weapon != null and is_instance_valid(source_weapon):
		OnHitEffects.on_weapon_hit(source_weapon, enemy, dmg, is_crit, _mech)

# ---------------- 视觉 ----------------

## 幻影外观：复用 ProceduralWeaponRenderer 画【同一把剑】的器形（形状/器尖/星级完全一致），
## 只把配色换成元素 HDR + 加色混合 + 半透明 —— 读起来是「这把剑的虚影」，
## 而不是另一把武器（用户口径：「显示效果会有一点点区别」）。
## 未实现矢量器形（GENERIC）的武器回落到 _draw 里的一枚光刃，绝不加载贴图（保持虚影一致）。
func _configure_visual() -> void:
	var def: Dictionary = WeaponData.get_def(weapon_def_id)
	var wshape: int = ProceduralWeaponRenderer.shape_from_name(String(def.get("shape", "")))
	var tip: Vector2 = def.get("tip", Vector2(22, 0))
	_upright = bool(def.get("upright", false))
	_blade_len = maxf(tip.length(), 12.0)
	_use_fallback_blade = wshape == ProceduralWeaponRenderer.WeaponShape.GENERIC
	_tint = GameStyle.fx_hdr_element(element)
	if _use_fallback_blade:
		if _renderer != null:
			_renderer.visible = false
		return
	if _renderer == null:
		_renderer = ProceduralWeaponRenderer.new()
		_renderer.name = "ProcPhantom"
		_renderer.material = SharedMaterials.add_blend()
		add_child(_renderer)
	_renderer.configure(wshape, element, _blade_len, star, _upright, weapon_def_id)
	_renderer.scale = Vector2.ONE * VISUAL_SCALE
	_renderer.modulate = _tint
	_renderer.visible = true

## 竖置重器（锤/鞭/锏等）反向补偿转角，保持世界竖直 ——
## 与 FloatingWeapon._apply_facing 同一条规则，幻影的姿态读起来才和真剑一致。
func _apply_child_facing() -> void:
	if _renderer != null and _renderer.visible:
		_renderer.rotation = (-rotation) if _upright else 0.0

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
		var k: float = clampf(_t / FORM_TIME, 0.0, 1.0)
		var ring := _tint
		ring.a = 0.55 * (1.0 - k)
		draw_arc(Vector2.ZERO, lerpf(8.0, 28.0, k), 0.0, TAU, 18, ring, 1.6, true)

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

## 回池休眠：物理与拖尾一起停（三件套同拍，项目坑 13），战果字段清残值防复用污染
func _recycle() -> void:
	if _pooled:
		return
	_pooled = true
	active_count = maxi(0, active_count - 1)
	set_physics_process(false)
	visible = false
	if _trail != null:
		_trail.reset()
	target = null
	source_weapon = null
	source_behavior = WeaponData.Behavior.MELEE
	damage = 0.0
	knockback_force = 0.0
	delay = 0.0
	_has_mech = false
	_mech.clear()
	proc_burn = false
	proc_chill = 0.0
	proc_poison = false
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
