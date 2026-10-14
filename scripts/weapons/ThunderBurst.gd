class_name ThunderBurst
extends Node2D

## 五雷法牌的落雷爆发：命中范围内所有敌人一次，短暂闪光后回池休眠
##
## 对象池（2026-10-11 第 6 波卡顿优化，照 EnemyBolt/AstralGem 模式）：雷法连发时
## Node2D + PointLight2D + 雷柱/镇岳印子节点整套 instantiate/queue_free 归零，灯体随复用免重建。
## 兼容约定：出膛方必须走 acquire(parent, scene) → 逐项写字段 → activate()（唯一调用方
## FloatingWeapon._spawn_lightning）；_ready 只建常驻设施不触发爆发，裸 add_child 不再自动起爆。

var radius: float = 80.0
var damage: float = 35.0
var knockback_base: float = 200.0
## 落点闪光色（由 FloatingWeapon 从 WeaponData.burst_tint 下发）：光环直径仍 == 判定直径，只换色相
var tint: Color = Color(1.0, 0.95, 0.6)
## 落点"砸下来的东西"（番天镇岳印 = 程序化玄石大印 SealImpactFx）；false = 只留光环与光柱
var show_seal: bool = false
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

static func _ensure_host(parent: Node) -> void:
	if _host != null and is_instance_valid(_host):
		return
	_pool.clear()   # 旧宿主已失效，残留池引用一并作废
	_host = Node2D.new()
	_host.name = "ThunderBurstPool"
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

func _ready() -> void:
	# 常驻设施（FxSprite/PointLight2D）由场景给出；爆发行为全部在 activate()，
	# 池化首建时字段尚未写入，_ready 不读任何业务字段
	pass

## 起爆激活：视觉重置 → 雷柱/镇岳印 → 演出与结算。复用时 _ready 已跑过一次，
## 所有依赖字段的状态必须在这里按当前字段值重铺（重置清单：tint/radius/show_seal/sfx/_struck/burst_kind）
func activate() -> void:
	_pooled = false
	visible = true
	# 劈没劈到人由同帧 deferred 的 _deal_damage 置位（先于 _bloom_or_recycle 回调）
	_struck = false
	# 上一发的雷柱与镇岳印已在爆发中淡出，直接清掉再铺新的
	for c in get_children():
		if c is Line2D or c is SealImpactFx or (c is Sprite2D and c != fx_sprite):
			c.queue_free()
	fx_sprite.scale = Vector2.ONE * 0.2
	fx_sprite.modulate = Color(tint.r, tint.g, tint.b, 0.0)
	light.color = tint
	# 天雷柱只给雷系（fire_rain/frost/earth 等的落点形态由 BurstKindFx 各自交代，
	# 火雨再立一根雷柱就是「文案说火雨画面是闪电」的旧错位）
	if burst_kind == "thunder" or burst_kind == "":
		_spawn_sky_beam()
	_spawn_impact_seal()
	if _kind_fx == null:
		_kind_fx = BurstKindFx.new()
		_kind_fx.name = "KindFx"
		add_child(_kind_fx)
	_kind_fx.activate_fx(burst_kind, radius, tint)

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
	if _kind_fx != null:
		_kind_fx.deactivate()
	if _host == null or not is_instance_valid(_host) or _pool.size() >= POOL_CAP:
		queue_free()
		return
	_pool.append(self)

## 落点之物：把武器真正砸下去的那件东西画在爆心（尺寸由 radius 一个量决定，与判定同源）
## 巨印的印体是纯矢量 SealImpactFx（2026-10-14 取代 AI 位图 weapon_earth_seal.png）
func _spawn_impact_seal() -> void:
	if not show_seal:
		return
	var seal := SealImpactFx.new()
	seal.size = radius * 1.4
	seal.tint = tint
	seal.z_index = 21
	seal.modulate = Color(1.0, 1.0, 1.0, 0.95)
	add_child(seal)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(seal, "scale", Vector2.ONE, 0.08).from(Vector2.ONE * 1.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(seal, "modulate:a", 0.0, 0.34).set_delay(0.06)

## 天雷柱：从天而降的竖直雷光，强化「雷从天上来」的落点感知
func _spawn_sky_beam() -> void:
	var beam := Line2D.new()
	beam.points = PackedVector2Array([Vector2(0.0, -200.0), Vector2(0.0, 0.0)])
	beam.width = maxf(radius * 0.12, 8.0)
	beam.default_color = Color(1.0, 0.97, 0.8, 0.8)
	beam.begin_cap_mode = Line2D.LINE_CAP_ROUND
	beam.end_cap_mode = Line2D.LINE_CAP_ROUND
	var curve := Curve.new()
	curve.add_point(Vector2(0.25, 0.0))
	curve.add_point(Vector2(1.0, 1.0))
	beam.width_curve = curve
	add_child(beam)
	var btw = create_tween()
	btw.tween_property(beam, "modulate:a", 0.0, 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

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
			if proc_burn and enemy.has_method("apply_burn"):
				enemy.apply_burn(burn_dps, burn_dur)
			if proc_chill > 0.0 and enemy.has_method("apply_chill"):
				enemy.apply_chill(proc_chill, chill_dur)
			GameManager.try_lifesteal()
			hits += 1
			if (enemy.get("dying") == true) and not was_dying:
				kills += 1
			if enemy.get("is_elite") == true:
				hit_elite = true
			if is_crit:
				had_crit = true
		if had_crit:
			GameManager.crit_hit_stop()
		# 劈空（hits==0）提前返回：不爆散、不震屏，落点小印记由 _bloom_or_recycle 走快速收场档
	if hits == 0:
		return
	# 劈到人：放行 _bloom_or_recycle 的全亮大闪档
	_struck = true
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
	if kills >= 3 or hit_elite:
		GameManager.zoom_punch(0.025, 0.14)
