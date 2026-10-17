class_name ThunderBurst
extends Node2D

## 五雷法牌的落雷爆发：命中范围内所有敌人一次，短暂闪光后回池休眠
##
## 对象池（2026-10-11 第 6 波卡顿优化，照 EnemyBolt/AstralGem 模式）：雷法连发时
## Node2D + PointLight2D + 雷柱子节点整套 instantiate/queue_free 归零，灯体随复用免重建。
## 兼容约定：出膛方必须走 acquire(parent, scene) → 逐项写字段 → activate()（唯一调用方
## FloatingWeapon._spawn_lightning）；_ready 只建常驻设施不触发爆发，裸 add_child 不再自动起爆。

var radius: float = 80.0
var damage: float = 35.0
var knockback_base: float = 200.0
## 落点闪光色（由 FloatingWeapon 从 WeaponData.burst_tint 下发）：光环直径仍 == 判定直径，只换色相
var tint: Color = Color(1.0, 0.95, 0.6)
## 落点形态（由 FloatingWeapon 从 WeaponData.burst_kind 下发，须在 activate() 前赋值）：
## thunder（默认，天雷柱）/ fire_rain 火雨 / frost 冰刺 / sonic 音波 / drum 鼓震 / earth 地裂 / seal 坠印扬尘
var burst_kind: String = "thunder"
## 落点音 key（由 FloatingWeapon 从 WeaponData.sfx_impact 下发，须在 activate() 前赋值）
var sfx_impact_key: String = ""
var proc_burn: bool = false
var burn_dps: float = 0.0
var burn_dur: float = 3.0
var proc_chill: float = 0.0
var chill_dur: float = 2.0

# —— 对象池 ——
const POOL_CAP := 24
static var _pool: Array[ThunderBurst] = []
static var _host: Node2D = null
static var created_count: int = 0    ## 累计 instantiate 数（PerfProbe 判据口径同 EnemyBolt）
static var reused_count: int = 0     ## 累计池复用数

static func clear_pool() -> void:
	_pool.clear()
	_host = null

static func _ensure_host(parent: Node) -> void:
	if _host != null and is_instance_valid(_host):
		return
	_pool.clear()   # 旧宿主已失效，残留池引用一并作废
	_host = Node2D.new()
	_host.name = "ThunderBurstPool"
	_host.z_index = 0
	parent.add_child(_host)

## 取一次落雷（优先复用）：调用方在调用后写 radius/damage/tint 等字段，最后调 activate() 起爆。
## scene 传调用方预落的 ThunderBurst.tscn（脚本不反向 preload 自身场景，避免环引用）。
static func acquire(parent: Node, scene: PackedScene) -> ThunderBurst:
	_ensure_host(parent)
	while not _pool.is_empty():
		var b: ThunderBurst = _pool.pop_back()
		if is_instance_valid(b):
			reused_count += 1
			return b
	var nb := scene.instantiate() as ThunderBurst
	created_count += 1
	_host.add_child(nb)
	return nb

## 伤害查询的形状/参数静态复用（照 TurretUnit 口径）：每次起爆零分配；
## 同帧多发起爆共享同一形状，半径在查询前现写、查询同步完成，无跨帧持有
static var _dmg_shape: CircleShape2D = null
static var _dmg_query: PhysicsShapeQueryParameters2D = null

@onready var fx_sprite: Sprite2D = $FxSprite
@onready var light: PointLight2D = $PointLight2D

var _pooled: bool = false
## 本次落雷是否劈到人：_deal_damage 结算后置位，_bloom_or_recycle 据此分档（劈空不演大闪）
var _struck: bool = false
## 落点形态渲染器：常驻子节点随池复用（activate 重铺字段），不随每发 instantiate
var _kind_fx: BurstKindFx = null
## 雷柱与顶端电弧：常驻子节点随池复用（2026-10-15 去分配：原先每发 new 1 Line2D + 1 Curve
## + 3 Line2D 再 queue_free，雷法连发时是明确的每帧分配源；照 LightningBolt 一次建、activate 重铺）
var _beam: Line2D = null
var _beam_curve: Curve = null
var _arcs: Array[Line2D] = []

func _ready() -> void:
	# 常驻设施（FxSprite/PointLight2D）由场景给出；爆发行为全部在 activate()，
	# 池化首建时字段尚未写入，_ready 不读任何业务字段；休眠池关闭物理帧
	set_physics_process(false)
	_build_beam_nodes()

## 雷柱与顶端电弧一次建好（_ready 常驻设施），activate 只重铺几何与透明度
func _build_beam_nodes() -> void:
	_beam = Line2D.new()
	_beam.name = "SkyBeam"
	_beam.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_beam.end_cap_mode = Line2D.LINE_CAP_ROUND
	_beam_curve = Curve.new()
	_beam_curve.add_point(Vector2(0.25, 0.0))
	_beam_curve.add_point(Vector2(1.0, 1.0))
	_beam.width_curve = _beam_curve
	add_child(_beam)
	for i in 3:
		var arc := Line2D.new()
		arc.name = "TopArc%d" % i
		arc.width = 1.4
		arc.begin_cap_mode = Line2D.LINE_CAP_ROUND
		arc.end_cap_mode = Line2D.LINE_CAP_ROUND
		arc.default_color = Color(GameStyle.FX_HDR_LIGHTNING.r, GameStyle.FX_HDR_LIGHTNING.g, GameStyle.FX_HDR_LIGHTNING.b, 0.9)  # 与雷柱同源的 HDR 超白
		add_child(arc)
		_arcs.append(arc)

## 起爆激活：视觉重置 → 雷柱 → 演出与结算。复用时 _ready 已跑过一次，
## 所有依赖字段的状态必须在这里按当前字段值重铺（重置清单：tint/radius/sfx/_struck/burst_kind）
func activate() -> void:
	_pooled = false
	visible = true
	# 劈没劈到人由同帧 deferred 的 _deal_damage 置位（先于 _bloom_or_recycle 回调）
	_struck = false
	# 雷柱与电弧是常驻子节点，先整体藏起再按形态决定是否亮出
	_beam.visible = false
	for arc in _arcs:
		arc.visible = false
	fx_sprite.scale = Vector2.ONE * 0.2
	fx_sprite.modulate = Color(tint.r, tint.g, tint.b, 0.0)
	light.color = tint
	# 天雷柱只给雷系（fire_rain/frost/earth 等的落点形态由 BurstKindFx 各自交代，
	# 火雨再立一根雷柱就是「文案说火雨画面是闪电」的旧错位）
	if burst_kind == "thunder" or burst_kind == "":
		_spawn_sky_beam()
	if _kind_fx == null:
		_kind_fx = BurstKindFx.new()
		_kind_fx.name = "KindFx"
		add_child(_kind_fx)
	_kind_fx.activate_fx(burst_kind, radius, tint)
	# 火雨热浪区上报（T-6.1，可选默认关时静态入口首行短路）：落点一团热盖住整轮坠雨演出
	if burst_kind == "fire_rain":
		HeatDistortionFx.report(get_tree().root, global_position, radius, 0.9, BurstKindFx.DUR + 0.2)

	# 劈空收档（2026-10-11 频闪治理）：落点先只演「小印记」——低α小光环 + 窄雷柱 + 落点音。
	# 同帧 deferred 的 _deal_damage 结算完战果后由 _bloom_or_recycle 分档：劈空快速收场，
	# 劈到人再补全亮大闪（爆散环/震屏仍在 _deal_damage）。与 FloatingWeapon 近战 hits>0 门控同构。
	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(fx_sprite, "modulate:a", 0.45, 0.05)
	tw.tween_property(fx_sprite, "scale", Vector2.ONE * (radius * 1.1 / 128.0), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(light, "energy", 0.9, 0.06)
	tw.chain().tween_callback(_bloom_or_recycle)

	_deal_damage.call_deferred()
	# 爆散环挪到 _deal_damage 按战果发放：劈空的落雷不该在空地上炸一簇蓝白特效。
	# 落点音留在这儿无条件播 —— 「雷落下来了」是发生过的事，劈不劈空都响。
	# 旧写法硬编码 obelisk_blessing（石碑的祝福铃），于是雷牌/巨印/宝灯落下全是一串铃铛。
	AudioManager.play_sfx(sfx_impact_key if sfx_impact_key != "" else "thunder_strike", 1.0)

## 落点分档：_deal_damage（同帧 deferred，必先于此回调跑完）已写好 _struck ——
## 劈空快速淡出回收，劈到人补全亮大闪再回收。
func _bloom_or_recycle() -> void:
	if not _struck:
		var ftw = create_tween()
		ftw.set_parallel(true)
		ftw.tween_property(fx_sprite, "modulate:a", 0.0, 0.10)
		ftw.parallel().tween_property(light, "energy", 0.0, 0.12)
		ftw.chain().tween_callback(_recycle)
		return
	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(fx_sprite, "modulate:a", 0.95, 0.05)
	tw.tween_property(fx_sprite, "scale", Vector2.ONE * (radius * 2.0 / 128.0), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(light, "energy", 2.2, 0.06)
	tw.chain().tween_property(fx_sprite, "modulate:a", 0.0, 0.18)
	tw.parallel().tween_property(light, "energy", 0.0, 0.2)
	tw.chain().tween_callback(_recycle)

## 回收入池（替代 queue_free）：灯光熄灭、池满或宿主失效才真释放
func _recycle() -> void:
	if _pooled:
		return
	_pooled = true
	visible = false
	light.energy = 0.0
	_beam_fade = -1.0
	if _beam != null:
		_beam.visible = false
	for arc in _arcs:
		arc.visible = false
	set_physics_process(false)
	if _kind_fx != null:
		_kind_fx.deactivate()
	if _host == null or not is_instance_valid(_host) or _pool.size() >= POOL_CAP:
		queue_free()
		return
	_pool.append(self)

## 天雷柱：从天而降的竖直雷光，强化「雷从天上来」的落点感知。
## T-2.5 余韵：消散瞬间顶端电弧四散（复用 LightningBolt.build_jagged_points 一把锯齿尺），
## 3 条短线从柱顶向斜上散开 HDR 渐隐——「雷柱散成电花」。
## 节点全部常驻（_build_beam_nodes），这里只重铺几何/宽度并点亮，淡出用帧内插值状态机。
const BEAM_TOP := Vector2(0.0, -200.0)
const BEAM_FADE_DUR := 0.13
var _beam_fade: float = -1.0  ## ≥0 = 淡出进行中（剩余秒数），-1 = 未在演

func _spawn_sky_beam() -> void:
	_beam.points = PackedVector2Array([BEAM_TOP, Vector2(0.0, 0.0)])
	# 2026-10-15 视觉克制化：柱宽系数 0.12→0.09、地板 8→6（雷柱是竖直演出线，
	# 判定是水平圆 _dmg_shape.radius，缩柱宽不碰判定）
	_beam.width = maxf(radius * 0.09, 6.0)
	_beam.default_color = Color(GameStyle.FX_HDR_LIGHTNING.r * 0.85, GameStyle.FX_HDR_LIGHTNING.g * 0.85, GameStyle.FX_HDR_LIGHTNING.b * 0.85, 0.8)  # HDR 超白：天雷柱核心过辉光阈值起辉
	_beam.modulate.a = 1.0
	_beam.visible = true
	# 顶端电弧：随机取向的锯齿短线，仅重铺 points，节点零新建
	for i in 3:
		var arc := _arcs[i]
		var dir := Vector2.UP.rotated(deg_to_rad(-55.0 + 55.0 * float(i)))
		var tip := BEAM_TOP + dir.rotated(randf_range(-0.3, 0.3)) * randf_range(26.0, 42.0)
		arc.points = LightningBolt.build_jagged_points(BEAM_TOP, tip, 9.0, 6.0)
		arc.modulate.a = 1.0
		arc.visible = true
	_beam_fade = BEAM_FADE_DUR
	set_physics_process(true)

## 雷柱/电弧淡出帧内插值：替代每次落雷 4 个 Tween 的旧写法（_process 由 activate 间歇驱动不保证，
## 这里由宿主 physics 帧推进；雷柱只活 0.13s，用 _physics_process 常驻推进开销可忽略）
func _physics_process(delta: float) -> void:
	if _beam_fade < 0.0:
		set_physics_process(false)
		return
	_beam_fade -= delta
	var t := clampf(_beam_fade / BEAM_FADE_DUR, 0.0, 1.0)
	_beam.modulate.a = t * t  # TRANS_QUAD EASE_IN 的解析形
	for arc in _arcs:
		arc.modulate.a = 1.0 - (1.0 - t) * (1.0 - t)  # TRANS_QUAD EASE_OUT 的解析形
	if _beam_fade <= 0.0:
		_beam_fade = -1.0
		_beam.visible = false
		for arc in _arcs:
			arc.visible = false
		set_physics_process(false)

func _deal_damage() -> void:
	var space_state = get_world_2d().direct_space_state
	if _dmg_shape == null or _dmg_query == null:
		_dmg_shape = CircleShape2D.new()
		_dmg_query = PhysicsShapeQueryParameters2D.new()
		_dmg_query.shape = _dmg_shape
		_dmg_query.collision_mask = 4
		_dmg_query.collide_with_areas = true
	_dmg_shape.radius = radius
	_dmg_query.transform = Transform2D(0.0, global_position)
	var results = space_state.intersect_shape(_dmg_query, 24)

	var had_crit := false
	var hits := 0
	var kills := 0
	var hit_elite := false
	for res in results:
		var col = res["collider"]
		if col and col.get_parent() and col.get_parent().has_method("take_damage"):
			var enemy = col.get_parent()
			var is_crit: bool = GameManager.roll_crit()
			var crit_m: float = GameManager.get_crit_mult()
			var dmg: float = damage * (crit_m if is_crit else 1.0) * GameManager.elite_damage_mult_for(enemy)
			# 震退方向走统一出口：落雷点常在玩家外侧，纯径向会把落点内侧那圈敌人往玩家身上拱
			var knock: Vector2 = GameManager.knockback_vec(global_position, enemy.global_position, knockback_base)
			# 藏宝匣（SpiritChest）也有 take_damage 但没有 dying/is_elite 字段，
			# 所以一律走 get()：取不到就当 false，不许在这里炸一场落雷
			var was_dying: bool = enemy.get("dying") == true
			enemy.take_damage(dmg, knock, is_crit)
			ProcStatus.apply(enemy, proc_burn, burn_dps, burn_dur, proc_chill, chill_dur, false, 0.0, 0.0)
			GameManager.try_lifesteal()
			hits += 1
			if (enemy.get("dying") == true) and not was_dying:
				kills += 1
			if enemy.get("is_elite") == true:
				hit_elite = true
			if is_crit:
				had_crit = true
	# 劈空（hits==0）提前返回：不爆散、不震屏，落点小印记由 _bloom_or_recycle 走快速收场档
	if hits == 0:
		return
	if had_crit:
		GameManager.crit_hit_stop()
	# 劈到人：放行 _bloom_or_recycle 的全亮大闪档
	_struck = true
	# 命中火花溅射（T-2.5）：雷光超白碎屑，吃 FxParticlePool 既有 HIT_FRAME_BUDGET 帧闸
	# （2026-10-16 减量 scale 1.2→1.0；雷刺元素在池内已分化为短命高初速电刺形态）
	FxParticlePool.burst(FxParticlePool.HIT_SPARK, global_position, "lightning", 1.0)
	# 落雷是本作少数「值得抖一下」的节点，量按战果给：劈到就轻震，收掉多命/劈到精英才加码
	var trauma := 0.16
	if kills >= 3:
		trauma += 0.10
	if hit_elite:
		trauma += 0.14
	GameManager.add_trauma(trauma)
	# 落雷垂直向下的方向性镜头微冲击 + 触觉震颤
	GameManager.kick_camera(Vector2.DOWN, 2.8)
	GameFeel.vibrate(25, 0.6)
	# 屏幕微亮脉冲（T-2.5）：复用既有 vignette 脉冲通道（信号签名不变，不碰 GameManager），
	# 反向打亮——冷蓝白低透明 0.16s 快速衰减，与受击红闪同路不同色；屏闪设置关则静默
	GameManager.pulse_damage_vignette(Color(0.75, 0.85, 1.0, 0.22), 0.16)
	if kills >= 3 or hit_elite:
		GameManager.zoom_punch(0.025, 0.14)
