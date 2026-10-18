extends Node

## 池化 / 缓存的自动化验证：分配上限、跨局复用、同种敌人共享帧集、缓存命中成本
## 运行: godot --headless --path . res://tests/PoolCheck.tscn
## 说明：这里不启动战斗，只用一个裸 Node2D 当宿主，避免刷怪自己产生跳字/特效污染计数。

var _c := TestCheck.new()

## 断言与输出格式统一走 tests/check.gd
func _check(cond: bool, label: String) -> void:
	_c.check(cond, label)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	Engine.time_scale = 10.0
	var world := Node2D.new()
	world.name = "PoolCheckWorld"
	get_tree().root.add_child(world)
	await get_tree().process_frame

	_check(DamageNumber._scene_root_for(world) != null, "前置：池宿主可定位到场景根")

	# ---------- 1. 帧集共享缓存（显式构建路径） ----------
	# 2026-10-13 起程序化敌种不再自动加载图集（AtlasSkipCheck 钉那条不变量），
	# 所以这里不再靠「刷怪顺带建帧集」取样，改为直接走 _shared_frames 显式构建，
	# 验的仍是同一个东西：同键共享、异键分槽、缓存命中不重建。
	var slime_scene: PackedScene = load("res://scenes/entities/SlimeEnemy.tscn")
	var danbao_scene: PackedScene = load("res://scenes/entities/DanBaoEnemy.tscn")
	var e1 := slime_scene.instantiate() as EnemyBase
	var e2 := slime_scene.instantiate() as EnemyBase
	var e3 := danbao_scene.instantiate() as EnemyBase
	world.add_child(e1)
	world.add_child(e2)
	world.add_child(e3)

	# 前置反证：程序化敌种自身不该建帧集（省内存的核心，异常时这里先报红）
	_check(e1.anim_sprite.sprite_frames == null, "前置：程序化敌人自身不建帧集")
	_check(EnemyBase.cache_size() == 0, "前置：刷怪未顺带解码图集 (实际 %d)" % EnemyBase.cache_size())

	var f1 := EnemyBase._shared_frames("res://assets/art/pawn_red_8dir.png", false)
	var f2 := EnemyBase._shared_frames("res://assets/art/pawn_red_8dir.png", false)
	var f3 := EnemyBase._shared_frames("res://assets/art/pawn_red_8dir.png", false)
	_check(f1 != null and f2 != null, "敌人帧集已构建")
	_check(f1.get_instance_id() == f2.get_instance_id(), "同一贴图共享同一 SpriteFrames")
	# pawn_red_8dir 同时是史莱姆与丹宝的贴图 → 也应命中同一份缓存
	_check(f1.get_instance_id() == f3.get_instance_id(), "同贴图的不同怪种也共享帧集")
	_check(EnemyBase.cache_size() == 1, "一张图只缓存一份 (实际 %d)" % EnemyBase.cache_size())

	# ---------- 2. 缓存命中成本远低于重建 ----------
	EnemyBase.clear_frame_cache()
	var t_build := Time.get_ticks_usec()
	EnemyBase._shared_frames("res://assets/art/pawn_red_8dir.png", false)
	t_build = Time.get_ticks_usec() - t_build
	var t_hit := Time.get_ticks_usec()
	EnemyBase._shared_frames("res://assets/art/pawn_red_8dir.png", false)
	t_hit = Time.get_ticks_usec() - t_hit
	_check(t_hit < t_build, "缓存命中快于重建 (%dµs vs %dµs)" % [t_hit, t_build])
	_check(EnemyBase.cache_size() == 1, "clear 后重建仍只占一份缓存")
	_check(EnemyBase._shared_frames("res://assets/art/pawn_red_8dir.png", true) != null, "精英档独立缓存键")
	_check(EnemyBase.cache_size() == 2, "精英/普通分键 (实际 %d)" % EnemyBase.cache_size())
	EnemyBase.clear_frame_cache()

	for e in [e1, e2, e3]:
		world.remove_child(e)
		e.free()

	# ---------- 3. 跳字池：分配上限 + 完全复用 ----------
	# 摆点收进可见矩形内（+20/+40 起步）：2026-10-11 起跳字/特效入口有视口兜底，
	# 屏外位置 spawn 会被静音拦截，池化计数必须在屏内打点才准
	var cap: int = DamageNumber.POOL_CAP
	for i in range(60):
		DamageNumber.spawn(world, Vector2(20 + 10 * i, 40), 10 + i)
	_check(DamageNumber.created_count() == 60, "首轮创建 60 个跳字节点 (%d)" % DamageNumber.created_count())
	_check(DamageNumber.host_child_count() == 60, "跳字全部挂在池宿主下 (%d)" % DamageNumber.host_child_count())
	# 跳字走 _process（渲染时钟），宿主必须关闭物理插值，否则真机帧率抖动时数字悬在错位上
	_check(DamageNumber._host.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF,
		"跳字池宿主已关闭物理插值（真机错位乱闪治理）")

	await get_tree().create_timer(1.0).timeout
	_check(DamageNumber.pool_size() == 60, "存活期结束后 60 个全部回池 (%d)" % DamageNumber.pool_size())

	for i in range(60):
		DamageNumber.spawn(world, Vector2(20 + 10 * i, 40), 20 + i, true)
	_check(DamageNumber.created_count() == 60, "第二轮零新建，全部复用 (%d)" % DamageNumber.created_count())

	# 超出上限：溢出节点用完即释放，不把池撑大
	for i in range(cap + 104):
		DamageNumber.spawn(world, Vector2(20 + i, 40), i)
	_check(DamageNumber.created_count() == cap, "常驻新建数不超过 POOL_CAP (%d/%d)" % [DamageNumber.created_count(), cap])
	await get_tree().create_timer(1.0).timeout
	_check(DamageNumber.host_child_count() <= cap, "溢出节点已释放，宿主子节点数回落 (%d)" % DamageNumber.host_child_count())

	# ---------- 4. 特效池 ----------
	# （2026-10-12 死亡爆散整体下线，池回收判据改由结算冲击环承担——同一套 acquire/_release 通路）
	for i in range(40):
		JuiceEffect.spawn_shockwave(world, Vector2(20 + i, 30 + i), 24.0, Color.WHITE, 0.2)
	_check(JuiceEffect.created_count() == 40, "首轮创建 40 个特效节点 (%d)" % JuiceEffect.created_count())
	_check(JuiceEffect._host.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF,
		"特效池宿主已关闭物理插值（真机错位乱闪治理）")
	await get_tree().create_timer(0.6).timeout
	_check(JuiceEffect.pool_size() == 40, "特效全部回池 (%d)" % JuiceEffect.pool_size())
	for i in range(40):
		JuiceEffect.spawn_shockwave(world, Vector2(20 + i, 30 + i), 24.0, Color.WHITE, 0.2)
	_check(JuiceEffect.created_count() == 40, "第二轮特效零新建 (%d)" % JuiceEffect.created_count())

	# ---------- 5. 特效并行数组：下标覆盖 + 复用归零 ----------
	var fx := JuiceEffect.new()
	world.add_child(fx)
	fx._begin(JuiceEffect.EffectType.SHOCKWAVE, Vector2.ZERO, 0.2, JuiceEffect.Z_OVERLAY)
	_check(fx._p_pos.size() == JuiceEffect.PARTICLE_SLOTS, "入树后一次性开好常驻容量 (%d)" % fx._p_pos.size())
	for i in range(12):
		fx._add_particle(Vector2.ZERO, Vector2.RIGHT, 10.0, Color.WHITE, 2.0)
	fx._add_ring(4.0, 28.0, Color.WHITE, 3.0)
	_check(fx._p_count == 12 and fx._r_count == 1, "粒子/光环按下标写入并计数 (%d/%d)" % [fx._p_count, fx._r_count])
	fx._begin(JuiceEffect.EffectType.STEP_DUST, Vector2.ONE, 0.2, JuiceEffect.Z_DUST)
	_check(fx._p_count == 0 and fx.z_index == JuiceEffect.Z_DUST, "复用后计数归零、层级重设")
	_check(fx._p_pos.size() == JuiceEffect.PARTICLE_SLOTS, "复用不清容量，仍走覆盖路径")
	world.remove_child(fx)
	fx.free()

	# ---------- 5.5 敌方火球池（2026-10-11）：出膛 / 回收 / 复用 / 判定圆重铺 ----------
	var bolt_a := EnemyBolt.acquire(world)
	bolt_a.global_position = Vector2.ZERO
	bolt_a.direction = Vector2.RIGHT
	bolt_a.activate()
	var bolt_created := EnemyBolt.created_count
	_check(bolt_created >= 1, "火球池首轮新建 1 颗 (%d)" % bolt_created)
	bolt_a._recycle()
	_check(EnemyBolt._pool.size() == 1 and not bolt_a.visible, "回收后回池休眠并隐身 (%d)" % EnemyBolt._pool.size())
	var bolt_b := EnemyBolt.acquire(world)
	_check(bolt_b == bolt_a and EnemyBolt.created_count == bolt_created, "第二次 acquire 复用同一实例不新建")
	bolt_b.scale_factor = GameBalance.BOSS_BOLT_SCALE
	# 复用出膛是从回收点瞬移：activate 必须重置物理插值，否则插值把首帧渲染成
	# 「从旧位置滑过来」（真机旧位置闪一下的元凶）。headless 读不到插值矩阵，用计数钩子钉住调用。
	var interp_resets_before := EnemyBolt.interp_reset_count
	bolt_b.global_position = Vector2(10000, 10000)
	bolt_b.activate()
	_check(bolt_b.visible and not bolt_b._pooled, "复用出膛后可见且激活")
	_check(EnemyBolt.interp_reset_count == interp_resets_before + 1,
		"复用出膛重置了物理插值（无旧位置滑行）")
	_check((bolt_b._circle as CircleShape2D).radius == EnemyBolt.RADIUS * GameBalance.BOSS_BOLT_SCALE,
		"复用激活按 scale_factor 重铺判定圆")
	_check(bolt_b.lifetime == EnemyBolt.BASE_LIFETIME, "复用激活重置寿命（残值不清会出膛即逝）")
	bolt_b._recycle()

	# ---------- 5.6 回复珠池（2026-10-11）：出膛 / 回收 / 复用 / gems 组语义 ----------
	var orb_a := HealOrb.acquire_or_new(world)
	orb_a.global_position = Vector2(50, 50)
	orb_a.heal_pct = 0.15
	orb_a.activate()
	var orb_created := HealOrb.created_count
	_check(orb_created >= 1, "回复珠池首轮新建 1 颗 (%d)" % orb_created)
	_check(orb_a.is_in_group("gems"), "激活后在 gems 组（波末结算可见）")
	orb_a.recycle()
	_check(not orb_a.is_in_group("gems") and HealOrb._pool.size() == 1, "回收后退出 gems 组并入池")
	var orb_b := HealOrb.acquire_or_new(world)
	_check(orb_b == orb_a and HealOrb.created_count == orb_created, "第二次 acquire 复用同一实例不新建")
	orb_b.activate()
	_check(orb_b.heal_pct == 0.0 and orb_b.heal_amount == HealOrb.BASE_HEAL, "复用激活重置回血参数")
	_check(orb_b.is_in_group("gems") and orb_b.visible, "复用激活重新入组并可见")
	orb_b.recycle()

	# ---------- 5.7 引雷池（LightningBolt）：出膛 / 回收 / 复用 ----------
	var l_bolt_a := LightningBolt.acquire(world)
	l_bolt_a.activate(Vector2(20, 20), Vector2(100, 100), Color.CYAN, 1.0)
	_check(l_bolt_a.visible, "引雷激活后可见")
	l_bolt_a._recycle()
	_check(not l_bolt_a.visible and LightningBolt._pool.size() == 1, "引雷回收后隐身并回池")
	var l_bolt_b := LightningBolt.acquire(world)
	_check(l_bolt_b == l_bolt_a, "引雷第二次 acquire 复用同一实例")
	l_bolt_b.activate(Vector2(20, 20), Vector2(80, 80), Color.WHITE, 1.2)
	# 基准线宽 2026-10-18 简化 7.0→4.5：4.5 × 1.2 = 5.4
	_check(l_bolt_b.visible and is_equal_approx(l_bolt_b._line_glow.width, 5.4), "引雷复用激活按 width_mult 重置线宽")
	# 5.7b 引雷与地面大阵层级守卫：宿主与特效线不抬高全局 z_index 盖压角色
	_check(LightningBolt._host.z_index <= 0, "引雷池宿主 z_index 不抬高压人")
	_check(l_bolt_b._line_core.z_index <= 0, "引雷折线 z_index 不盖压角色")
	if ThunderBurst._host != null:
		_check(ThunderBurst._host.z_index <= 0, "落雷池宿主 z_index 不抬高压人")
	l_bolt_b._recycle()

	# ---------- 5.7c 落雷池（ThunderBurst）：落雷灯动态名额守卫 ----------
	var tb_scene: PackedScene = load("res://scenes/weapons/ThunderBurst.tscn")
	var tb1 := ThunderBurst.acquire(world, tb_scene)
	tb1.activate()
	var tb2 := ThunderBurst.acquire(world, tb_scene)
	tb2.activate()
	_check(ThunderBurst._active_lights <= FxBudget.LIGHT_CAP_THUNDER,
		"落雷并发时活跃灯数 %d ≤ 名额上限 %d" % [ThunderBurst._active_lights, FxBudget.LIGHT_CAP_THUNDER])
	_check(tb1._has_light != tb2._has_light, "名额饱和时仅先到者分得动态灯")
	tb1._recycle()
	tb2._recycle()
	_check(ThunderBurst._active_lights == 0, "落雷回收后活跃灯数全部归零")

	# ---------- 5.8 弹丸湮灭微闪（IMPACT_POP）与限流闸 ----------
	var pop_pre := JuiceEffect.created_count()
	for i in range(12):
		JuiceEffect.spawn_impact_pop(world, Vector2(50 + i * 2, 50), Color.GOLD, Vector2.RIGHT)
	_check(JuiceEffect.created_count() - pop_pre <= JuiceEffect.IMPACT_POP_FRAME_BUDGET, "湮灭微闪受单帧预算限流闸截断")

	# ---------- 5.9 敌人对象池（2026-10-13）：出怪 / 回收 / 复用 / 复用整备归零 ----------
	# 敌人是全项目最重的节点图，池化验收钉四条：回收出树退组注销、复用零新建、
	# reset_for_reuse 把「成长/变异/异常/形变」污染全滚回出厂、activate 血量公式不重算错。
	var e_created0: int = EnemyBase.pool_created_count
	var e_reused0: int = EnemyBase.pool_reused_count
	var mob_a := EnemyBase.acquire_or_new(slime_scene)
	mob_a.reset_for_reuse()  # 新实例空转（_assembled=false）
	mob_a.add_to_group("enemies")
	mob_a.global_position = Vector2(100, 100)
	world.add_child(mob_a)   # 首次入树：_ready 装配 + activate
	mob_a.activate()         # 幂等闸空转
	_check(EnemyBase.pool_created_count == e_created0 + 1, "敌人池首轮新建 1 只 (%d)" % (EnemyBase.pool_created_count - e_created0))
	_check(GameManager.live_enemies.has(mob_a), "入树即在活体登记表")
	var mob_base_hp: float = mob_a._base_stats["max_hp"]
	# 弄脏：成长后的血量 / 燃烧 / 变异 / 击退 / 出生缩放 / 变异染色
	mob_a.max_hp = 9999.0
	mob_a.burn_timer = 2.0
	mob_a._mutated = true
	mob_a.knockback_velocity = Vector2(99, 0)
	mob_a.scale = Vector2(0.4, 0.4)
	mob_a.anim_sprite.modulate = Color(1.5, 0.65, 0.6)
	EnemyBase._recycle(mob_a)
	_check(mob_a.get_parent() == null and not mob_a.is_in_group("enemies"), "回收后出树并退 enemies 组")
	_check(not GameManager.live_enemies.has(mob_a), "回收后注销活体登记表")
	_check(EnemyBase.pool_idle_count() == 1, "池内休眠 1 只 (%d)" % EnemyBase.pool_idle_count())
	var mob_b := EnemyBase.acquire_or_new(slime_scene)
	_check(mob_b == mob_a and EnemyBase.pool_created_count == e_created0 + 1, "第二次 acquire 复用同一实例零新建")
	_check(EnemyBase.pool_reused_count == e_reused0 + 1, "复用计数 +1 (%d)" % (EnemyBase.pool_reused_count - e_reused0))
	mob_b.reset_for_reuse()
	_check(mob_b.max_hp == mob_base_hp, "复用整备回滚出厂血量（成长污染清零，实际 %.1f vs %.1f）" % [mob_b.max_hp, mob_base_hp])
	_check(mob_b.burn_timer == 0.0 and not mob_b._mutated and mob_b.knockback_velocity == Vector2.ZERO, "复用整备清零异常/变异/击退")
	_check(mob_b.scale == Vector2.ONE and mob_b.anim_sprite.modulate == Color.WHITE, "复用整备还原出生缩放与染色")
	world.add_child(mob_b)
	mob_b.activate()
	var expect_hp: float = ceilf(mob_base_hp * GameBalance.MOB_HP_BASE_MULT)
	_check(mob_b.max_hp == expect_hp and mob_b.current_hp == expect_hp,
		"复用激活血量 = 出厂 × 小怪血量系数（实际 %.1f vs %.1f）" % [mob_b.max_hp, expect_hp])
	_check(GameManager.live_enemies.has(mob_b), "复用入树重新登记")
	EnemyBase._recycle(mob_b)
	EnemyBase.clear_pools()
	_check(EnemyBase.pool_idle_count() == 0, "clear_pools 清空休眠体")

	# ---------- 6. 缓存清理不影响运行中对象 ----------
	DamageNumber.clear_cache()
	JuiceEffect.clear_cache()
	LightningBolt.clear_cache()
	_check(DamageNumber.created_count() == 0 and JuiceEffect.created_count() == 0, "clear_cache 归零计数")
	DamageNumber.spawn(world, Vector2(40, 40), 1)
	_check(DamageNumber.created_count() == 1, "清理后可重新建池并继续工作")

	# ---------- 7. 动态灯预算账目（全场 PointLight2D 预分配 ≤ GLOBAL_LIGHT_CAP） ----------
	_check(FxBudget.get_allocated_light_cap() <= FxBudget.GLOBAL_LIGHT_CAP,
		"灯账目 %d ≤ 硬顶 %d" % [FxBudget.get_allocated_light_cap(), FxBudget.GLOBAL_LIGHT_CAP])

	world.free()
	Engine.time_scale = 1.0

	if _c.report("POOL_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)
