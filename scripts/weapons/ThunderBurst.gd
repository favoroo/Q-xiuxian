class_name ThunderBurst
extends Node2D

## 五雷法牌的落雷爆发：命中范围内所有敌人一次，短暂闪光后回池休眠
##
## 对象池（2026-10-11 第 6 波卡顿优化，照 EnemyBolt/AstralGem 模式）：雷法连发时
## Node2D + PointLight2D 整套 instantiate/queue_free 归零，灯体随复用免重建。
## 兼容约定：出膛方必须走 acquire(parent, scene) → 逐项写字段 → activate()（唯一调用方
## FloatingWeapon._spawn_lightning）；_ready 只建常驻设施不触发爆发，裸 add_child 不再自动起爆。

var radius: float = 80.0
var damage: float = 35.0
var knockback_base: float = 200.0
## 落点闪光色（由 FloatingWeapon 从 WeaponData.burst_tint 下发）：光环直径仍 == 判定直径，只换色相
var tint: Color = Color(1.0, 0.95, 0.6)
## 落点形态（由 FloatingWeapon 从 WeaponData.burst_kind 下发，须在 activate() 前赋值）：
## thunder（默认，落点贴身雷光柱）/ fire_rain 火雨 / frost 冰刺 / sonic 音波 / drum 鼓震 / earth 地裂 / seal 坠印扬尘
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
const GROUND_SQUASH := 0.62          ## 俯视透视压扁比（落点光斑贴地展开，对齐双层软影与地面贴花）
static var _pool: Array[ThunderBurst] = []
static var _host: Node2D = null
static var created_count: int = 0    ## 累计 instantiate 数（PerfProbe 判据口径同 EnemyBolt）
static var reused_count: int = 0     ## 累计池复用数
## 动态落雷灯名额严格控制（收口 FxBudget.LIGHT_CAP_THUNDER）：多雷法武器同屏连发时瞬态灯最多亮 1 盏
static var _active_lights: int = 0

static func clear_pool() -> void:
	_pool.clear()
	_host = null
	_active_lights = 0

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
## 本次落雷是否成功占用动态灯名额（严格受 FxBudget.LIGHT_CAP_THUNDER 守卫）
var _has_light: bool = false
## 落点形态渲染器：常驻子节点随池复用（activate 重铺字段），不随每发 instantiate
var _kind_fx: BurstKindFx = null

## 起爆激活：视觉重置 → 落点形态 → 演出与结算。复用时 _ready 已跑过一次，
## 所有依赖字段的状态必须在这里按当前字段值重铺（重置清单：tint/radius/sfx/_struck/burst_kind）
func activate() -> void:
	_pooled = false
	visible = true
	# 劈没劈到人由同帧 deferred 的 _deal_damage 置位（先于 _bloom_or_recycle 回调）
	_struck = false
	# 动态灯名额严格限制：最多 LIGHT_CAP_THUNDER 盏，超额不耗 GPU 动态光源
	if not _has_light and _active_lights < FxBudget.LIGHT_CAP_THUNDER:
		_has_light = true
		_active_lights += 1
	light.energy = 0.0

	var base_scale := Vector2(1.0, GROUND_SQUASH)
	fx_sprite.scale = base_scale * 0.2
	fx_sprite.modulate = Color(tint.r, tint.g, tint.b, 0.0)
	light.color = tint
	# 2026-11-01 去线条化：旧写法在落点立一根 200px 天空雷柱 + 2 条顶端电弧 ——
	# 顶端悬在空气里，高星连发时满屏竖线。现在与天罚/天雷同口径，只在落点身位内
	# 点亮一道贴身光柱（JuiceEffect.SKY_STRIKE，不生成任何 Line2D/折线）。
	# 只给雷系（fire_rain/frost/earth 等的落点形态由 BurstKindFx 各自交代，
	# 火雨再立一根雷柱就是「文案说火雨画面是闪电」的旧错位）
	if burst_kind == "thunder" or burst_kind == "":
		JuiceEffect.spawn_sky_strike(get_parent(), global_position, tint)
	# 2026-11-01 二次收束：不再叠 lightning_strike 序列帧。那张图单帧 240×264（0.85 缩放后
	# 画幅 204×224，是身位光柱的 4 倍高、接近半屏），而落雷形态是每发范围武器都放一次的
	# 高频演出 —— 多把雷系武器同开时同屏叠三四道 200px 巨雷，正是用户说的「雷又乱又乱」。
	# 天罚（暴击那一发，低频高光）继续用这张图；范围武器落雷只留贴身光柱 + 落点环 + 光斑。
	if _kind_fx == null:
		_kind_fx = BurstKindFx.new()
		_kind_fx.name = "KindFx"
		add_child(_kind_fx)
	_kind_fx.activate_fx(burst_kind, radius, tint)
	# 火雨热浪区上报（T-6.1，可选默认关时静态入口首行短路）：落点一团热盖住整轮坠雨演出
	if burst_kind == "fire_rain":
		HeatDistortionFx.report(get_tree().root, global_position, radius, 0.9, BurstKindFx.DUR + 0.2)

	# 劈空收档（2026-10-11 频闪治理）：落点先只演「小印记」——低α小光环 + 落点音。
	# 同帧 deferred 的 _deal_damage 结算完战果后由 _bloom_or_recycle 分档：劈空快速收场，
	# 劈到人再补全亮大闪（爆散环/震屏仍在 _deal_damage）。与 FloatingWeapon 近战 hits>0 门控同构。
	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(fx_sprite, "modulate:a", 0.45, 0.05)
	tw.tween_property(fx_sprite, "scale", base_scale * (radius * 1.1 / 128.0), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if _has_light:
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
		if _has_light:
			ftw.parallel().tween_property(light, "energy", 0.0, 0.12)
		ftw.chain().tween_callback(_recycle)
		return
	var tw = create_tween()
	tw.set_parallel(true)
	var base_scale := Vector2(1.0, GROUND_SQUASH)
	tw.tween_property(fx_sprite, "modulate:a", 0.95, 0.05)
	tw.tween_property(fx_sprite, "scale", base_scale * (radius * 2.0 / 128.0), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if _has_light:
		tw.tween_property(light, "energy", 2.2, 0.06)
	tw.chain().tween_property(fx_sprite, "modulate:a", 0.0, 0.18)
	if _has_light:
		tw.parallel().tween_property(light, "energy", 0.0, 0.2)
	tw.chain().tween_callback(_recycle)

## 回收入池（替代 queue_free）：灯光熄灭、池满或宿主失效才真释放
func _recycle() -> void:
	if _pooled:
		return
	_pooled = true
	visible = false
	light.energy = 0.0
	if _has_light:
		_has_light = false
		_active_lights = maxi(0, _active_lights - 1)
	if _kind_fx != null:
		_kind_fx.deactivate()
	if _host == null or not is_instance_valid(_host) or _pool.size() >= POOL_CAP:
		queue_free()
		return
	_pool.append(self)

func _deal_damage() -> void:
	var space_state = get_world_2d().direct_space_state
	if _dmg_shape == null or _dmg_query == null:
		_dmg_shape = CircleShape2D.new()
		_dmg_query = PhysicsShapeQueryParameters2D.new()
		_dmg_query.shape = _dmg_shape
		_dmg_query.collision_mask = 4
		_dmg_query.collide_with_areas = true
		_dmg_query.collide_with_bodies = false  # 只查敌人 Hurtbox(Area)，不扫 body 层
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
			GameManager.try_lifesteal(WeaponData.Behavior.BURST)
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
	# 2026-10-23 去重：按落点形态只发**一支**——
	#   雷系（thunder/空）走本处的 lightning 碎屑；
	#   其余形态交给 BurstKindFx.emit_hit_spark()（火雨 EMBER / 冰霜水 / 地裂土 / 坠印金 / 鼓音波）。
	#   原先 BurstKindFx 在 activate 阶段就发一支、这里再发一支 ⇒ 同一落点同帧双发（实测 2 支）。
	if burst_kind == "thunder" or burst_kind == "":
		FxParticlePool.burst(FxParticlePool.HIT_SPARK, global_position, "lightning", 1.0)
	elif _kind_fx != null:
		_kind_fx.emit_hit_spark()
	# 落雷震屏「按战果才震」（2026-10-18 用户口径：全雷法配装屏幕一直在震，别这么高频）：
	# 单发落雷不再无条件震——六把雷法轮着砸，每发都震就是持续抖屏。只有真正打出战果
	# （一发收 ≥3 命，或劈到精英）才给一记镜头冲击，普通落雷只留火花/音效。
	# 量按战果给：收多命加码、劈到精英再加码。
	var trauma := 0.0
	if kills >= 3:
		trauma += 0.12
	if hit_elite:
		trauma += 0.14
	if trauma > 0.0:
		GameManager.add_trauma(trauma)
		# 落雷垂直向下的方向性镜头微冲击 + 触觉震颤
		GameManager.kick_camera(Vector2.DOWN, 2.8)
		GameFeel.vibrate(25, 0.6)
	if kills >= 3 or hit_elite:
		GameManager.zoom_punch(0.025, 0.14)
