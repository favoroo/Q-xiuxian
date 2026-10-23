extends Node

## 精英/Boss 受击火花判据（2026-10-20，2026-10-23 扩充冲突回归 + 门控下沉）
## 目标：只有「精英/Boss 的非暴击、非 DoT、非致命直击」才补一朵体表火花；
## 普通小怪、暴击、DoT、致命一刀、节奏闸窗内的连击一律不发。
##
## 断言链：
##   ① 精英非暴击直击 → FxParticlePool 活跃发射器 +1；
##   ② Boss（death_corpse_linger 标记）非暴击直击 → +1；
##   ③ 普通小怪直击 → +0（历史教训：高频割草不糊屏）；
##   ④ 精英 DoT（from_dot）→ +0；
##   ⑤ 精英暴击 → +0（暴击已有方向环+镜头组，不重复）；
##   ⑥ 精英连续两次直击（同帧）→ 只 +1（全局节奏闸兜底）；
##   ⑦ 精英致命一刀 → 首个新增发射器不是 HIT_SPARK（amount=6），由死亡爆散承担。
##   ⑧-⑪ 武器侧统一门控回归（四条冲突，走真实 BladeProjectile 入口）：
##       ⑧ 弹丸打精英：EnemyBase 1 支 + 弹丸侧被闸挡 = 同帧 1 支（原为 2 支双发）；
##       ⑨ 弹丸致命一刀：武器侧不发（原仍发 1 支）；
##       ⑩ 弹丸屏外命中：武器侧不发（原无视口门控）；
##       ⑪ 精英暴击：EnemyBase 跳过、武器侧放行 = 恰好 1 支（不重复也不空缺）。
##   ⑫-⑬ 2026-10-23 全局时间戳闸（替代每敌倒计时）：
##       ⑫ 束流 tick 连打（间隔 0.15s > 旧冷却 0.08s）→ 全局闸 220ms 收敛，4 tick 只发 2 支；
##       ⑬ 两只精英同帧各挨一刀 → 全局闸下只 1 支（每敌倒计时时代是 2 支）。
##
## 运行: godot --headless --path . res://tests/EliteHitSparkCheck.tscn
## 反例（判据的牙齿）：
##   ① 去掉 is_elite 门 → ③（小怪）报红；
##   ② 去掉 not is_crit 门 → ⑤ 报红；
##   ③ 去掉 not from_dot 门 → ④ 报红；
##   ④ 去掉全局节奏闸 → ⑥ 报红；
##   ⑤ 把 lethal 判定漏掉 → ⑦ 报红；
##   ⑥ 把 _hit_feedback_allowed 的 is_elite 分支删掉 → ⑧ 报红；
##   ⑦ 把 _hit_feedback_allowed 的 dying 分支删掉 → ⑨ 报红；
##   ⑧ 把 _hit_feedback_allowed 的视口分支删掉 → ⑩ 报红；
##   ⑨ 把 is_crit 放行分支删掉 → ⑪ 报红（精英暴击一粒粒子都不剩）；
##   ⑩ 把 ENEMY 分支的全局时间戳闸删掉 → ⑫⑬ 报红。
## 计数口径：burst 新增发射器是同步 append 到 _active_emitters，finished 只在帧处理时触发，
## 所以「调用前/后同函数内取 size」是可靠的；不依赖 headless 的粒子 finished 是否触发。

var _c := TestCheck.new()
var _world: Node2D
var _pool: FxParticlePool

## 只带 GameManager 视口门控要读的位置（照 beam_cone_check 桩体先例）
class StubPlayer:
	extends Node2D
	var current_health: float = 120.0
	var max_health: float = 120.0

func _ready() -> void:
	GameManager.reset_run()
	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)
	var stub := StubPlayer.new()
	_world.add_child(stub)
	stub.global_position = get_viewport().get_visible_rect().get_center()
	GameManager.player = stub
	_pool = FxParticlePool.new()
	add_child(_pool)
	call_deferred("_run")

func _run() -> void:
	# 常量转发就位（防 GameBalance 漏转发导致读 0）
	_c.check(GameBalance.ELITE_HIT_SPARK_GAP_MS > 0, "常量转发：火花全局闸 > 0ms")
	_c.check(GameBalance.ELITE_HIT_SPARK_GAP_MS >= 200,
		"全局闸 ≥ 200ms（须覆盖 HIT_SPARK 0.22s 寿命，屏上至多一朵）")
	_c.check(GameBalance.BOSS_HIT_SPARK_SCALE >= GameBalance.ELITE_HIT_SPARK_SCALE, "Boss 火花缩放不小于精英")

	# ① 精英非暴击直击 → +1
	var elite := _make(true, false, 9999.0)
	_c.equals(_hit_delta(elite, 10.0, Vector2(100, 0), false, false), 1, "精英非暴击直击补一朵火花")

	# ② Boss（death_corpse_linger 标记）非暴击直击 → +1
	var boss := _make(true, true, 9999.0)
	_c.equals(_hit_delta(boss, 10.0, Vector2(100, 0), false, false), 1, "Boss 非暴击直击补一朵火花")

	# ③ 普通小怪直击 → +0
	var mob := _make(false, false, 9999.0)
	_c.equals(_hit_delta(mob, 10.0, Vector2(100, 0), false, false), 0, "普通小怪直击不发火花")

	# ④ 精英 DoT → +0
	var elite_dot := _make(true, false, 9999.0)
	_c.equals(_hit_delta(elite_dot, 3.0, Vector2.ZERO, false, true), 0, "精英 DoT tick 不发火花")

	# ⑤ 精英暴击 → +0（不额外发；暴击方向环走 JuiceEffect，不入本池）
	var elite_crit := _make(true, false, 9999.0)
	_c.equals(_hit_delta(elite_crit, 10.0, Vector2(100, 0), true, false), 0, "精英暴击不额外发火花")

	# ⑥ 冷却窗：同帧连续两次直击只 +1
	var elite_cd := _make(true, false, 9999.0)
	var base := _pool._active_emitters.size()
	_reset_hit_budget()
	elite_cd.take_damage(10.0, Vector2(100, 0), false, false)
	var after_first := _pool._active_emitters.size()
	elite_cd.take_damage(10.0, Vector2(100, 0), false, false)
	var after_second := _pool._active_emitters.size()
	_c.equals(after_first - base, 1, "冷却窗：第一击发一朵")
	_c.equals(after_second - after_first, 0, "冷却窗：第二击被冷却拦下（不刷屏）")

	# ⑦ 致命一刀：首朵新增发射器不是 HIT_SPARK，交给死亡爆散
	var elite_lethal := _make(true, false, 5.0)
	var before := _pool._active_emitters.size()
	_reset_hit_budget()
	elite_lethal.take_damage(10.0, Vector2(100, 0), false, false)
	var added := _pool._active_emitters.size() - before
	var first_kind_amount := _pool._active_emitters[before].amount if added > 0 else -1
	_c.check(first_kind_amount != 6, "致命一刀的首个发射器不是 HIT_SPARK（实得 amount=%d）" % first_kind_amount)

	# ⑧ 弹丸打精英：EnemyBase 发 1 支，弹丸侧必须被统一闸挡下（原为同帧 2 支双发）
	# 走真实 BladeProjectile._on_area_entered 入口（不只测闸函数），这样「删掉弹丸侧的闸调用」也会报红
	var elite_proj := _make(true, false, 9999.0)
	var proj8 := _make_projectile(elite_proj.global_position)
	var before8 := _pool._active_emitters.size()
	_reset_hit_budget()
	proj8._on_area_entered(_hurtbox_of(elite_proj))
	var after8 := _pool._active_emitters.size()
	_c.equals(after8 - before8, 1, "⑧ 弹丸打精英：同一次命中只 1 支（EnemyBase 专属，弹丸侧不重复）")

	# ⑨ 弹丸致命一刀：武器侧不发（击杀反馈归死亡爆散）
	var mob_lethal := _make(false, false, 5.0)
	var proj9 := _make_projectile(mob_lethal.global_position)
	var before9 := _pool._active_emitters.size()
	_reset_hit_budget()
	proj9._on_area_entered(_hurtbox_of(mob_lethal))
	var after9 := _pool._active_emitters.size()
	_c.check(mob_lethal.dying, "⑨ 弹丸致命一刀：敌人已 dying")
	_c.equals(after9 - before9, 0, "⑨ 弹丸致命一刀：武器侧不发火花（原仍发 1 支）")

	# ⑩ 屏外命中：武器侧不发（历史「空地闪白」教训）
	var mob_off := _make(false, false, 9999.0)
	var vp := get_viewport().get_visible_rect()
	mob_off.global_position = vp.position + vp.size + Vector2(600.0, 400.0)
	mob_off._offscreen = true
	var proj10 := _make_projectile(mob_off.global_position)
	var before10 := _pool._active_emitters.size()
	_reset_hit_budget()
	proj10._on_area_entered(_hurtbox_of(mob_off))
	var after10 := _pool._active_emitters.size()
	_c.equals(after10 - before10, 0, "⑩ 屏外命中：武器侧不发火花（原无视口门控）")

	# ⑪ 精英暴击：EnemyBase 跳过、武器侧按暴击规格放行 ⇒ 恰好 1 支（不重复也不空缺）
	var elite_crit2 := _make(true, false, 9999.0)
	var proj11 := _make_projectile(elite_crit2.global_position)
	var before11 := _pool._active_emitters.size()
	_reset_hit_budget()
	GameManager.force_crit_left = 1.0   # 钉死必暴，不吃 rng
	proj11._on_area_entered(_hurtbox_of(elite_crit2))
	GameManager.force_crit_left = 0.0
	var after11 := _pool._active_emitters.size()
	_c.equals(after11 - before11, 1, "⑪ 精英暴击：恰好 1 支（EnemyBase 跳过，武器侧暴击规格补上）")
	# 暴击规格：amount=6 的 HIT_SPARK，scale 应比非暴击大（弹丸暴击 1.5）
	if after11 > before11:
		var em: GPUParticles2D = _pool._active_emitters[before11]
		_c.check(em.amount == 6 and (em.process_material as ParticleProcessMaterial).scale_max > 0.3,
			"⑪ 精英暴击火花走暴击规格（amount=%d scale_max=%.2f）" % [
				em.amount, (em.process_material as ParticleProcessMaterial).scale_max])

	# ⑫ 全局时间戳闸：束流 tick 连打（间隔 0.15s，旧每敌冷却 0.08s 拦不住）
	# 220ms 全局闸下，4 次 tick 覆盖 0.45s ⇒ 只放行第 1、第 4 次（0ms / 450ms）
	var elite_tick := _make(true, false, 9999.0)
	_reset_hit_budget()
	var tick_count := 0
	for tick in range(4):
		var before_t := _pool._active_emitters.size()
		elite_tick.take_damage(1.0, Vector2(100, 0), false, false)
		tick_count += _pool._active_emitters.size() - before_t
		if tick < 3:
			await get_tree().create_timer(0.15).timeout
	_c.equals(tick_count, 2, "⑫ 束流 tick 连打 4 次（间隔 0.15s）：全局闸收敛为 2 支（旧每敌 0.08s 冷却会是 4 支）")

	# ⑬ 两只精英同帧各挨一刀：全局闸下只 1 支（每敌倒计时时代是 2 支）
	var elite_a := _make(true, false, 9999.0)
	var elite_b := _make(true, false, 9999.0)
	_reset_hit_budget()
	var before13 := _pool._active_emitters.size()
	elite_a.take_damage(10.0, Vector2(100, 0), false, false)
	elite_b.take_damage(10.0, Vector2(-100, 0), false, false)
	var after13 := _pool._active_emitters.size()
	_c.equals(after13 - before13, 1, "⑬ 两只精英同帧各挨一刀：全局闸下只 1 支（屏上至多一朵）")

	# ⑭ 落雷落点去重（2026-10-23）：frost 形态原先 BurstKindFx(activate) 发一支 + ThunderBurst 发一支
	# = 同一落点同帧 2 支。现在火花统一由 _deal_damage 在 hits>0 后按形态发一支。
	# 先清掉前面用例留在场上的精英（否则落雷半径 80 会连带打中它们，
	# 那会多出一支「精英受击火花」——那是另一处语义，不属于落点去重口径）
	for child in _world.get_children():
		if child is EnemyBase:
			_world.remove_child(child)
			child.free()
	await get_tree().physics_frame
	var foe := _make_foe(get_viewport().get_visible_rect().get_center())
	# 桩敌的 Hurtbox 需要至少一帧让物理服务器登记，否则落雷 intersect_shape 查不到
	await get_tree().physics_frame
	await get_tree().physics_frame
	var burst: ThunderBurst = ThunderBurst.acquire(_world, load("res://scenes/weapons/ThunderBurst.tscn"))
	burst.global_position = foe.global_position
	burst.radius = 80.0
	burst.damage = 10.0
	burst.burst_kind = "frost"
	_reset_hit_budget()
	var before14 := _pool._active_emitters.size()
	burst.activate()
	var after_activate := _pool._active_emitters.size()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var after_deal := _pool._active_emitters.size()
	_c.equals(after_activate - before14, 0, "⑭ 落雷 activate 阶段不再预发火花（劈空不许空地冒粒子）")
	_c.equals(after_deal - before14, 1, "⑭ 落雷命中后按形态只发 1 支（原 frost 同帧 2 支）")

	_world.free()
	remove_child(_pool)
	_pool.free()
	FxParticlePool.clear_cache()

	if _c.report("ELITEHITSPARK_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

## 造一只敌人（slime 场景），按参数设 is_elite / Boss 标记 / 血量，摆到视口中心并保证在屏
func _make(elite: bool, boss: bool, hp: float) -> EnemyBase:
	var scene: PackedScene = load("res://scenes/entities/SlimeEnemy.tscn")
	var e := scene.instantiate() as EnemyBase
	e.is_elite = elite
	if boss:
		e.death_corpse_linger = true
	_world.add_child(e)
	e.activate()
	e.max_hp = hp
	e.current_hp = hp
	e.global_position = get_viewport().get_visible_rect().get_center()
	e._offscreen = false
	return e

## 打一刀并返回 FxParticlePool 活跃发射器增量（同函数内取 size，不受 finished 影响）
func _hit_delta(e: EnemyBase, amount: float, knockback: Vector2, is_crit: bool, from_dot: bool) -> int:
	var before := _pool._active_emitters.size()
	_reset_hit_budget()
	e.take_damage(amount, knockback, is_crit, from_dot)
	return _pool._active_emitters.size() - before

## 每物理帧限流窗口：清掉上一帧计数，保证每刀都能进池（不被 4/帧预算误伤）
## 同时清全局精英火花时间戳：让每条用例从「闸已就绪」的干净态起跑（⑥⑫⑬ 自己控制窗内连击）
func _reset_hit_budget() -> void:
	FxParticlePool._last_hit_frame = -1
	FxParticlePool._hit_count_this_frame = 0
	FxParticlePool._last_elite_spark_ms = -999999

## 造一发弹丸（直接 add_child 走 _ready，不经过对象池；判据只测命中回调）
func _make_projectile(at: Vector2) -> BladeProjectile:
	var p: BladeProjectile = load("res://scenes/weapons/BladeProjectile.tscn").instantiate()
	p.damage = 10.0
	p.knockback_base = 140.0
	p.pierce_left = 1
	_world.add_child(p)
	p.global_position = at
	return p

## 造一个桩敌（带 Hurtbox Area，供落雷/弹丸的物理查询命中；只需 take_damage 与 dying 字段）
class ProbeFoe:
	extends Node2D
	var dying: bool = false
	func take_damage(_amount: float, _knockback: Vector2, _crit: bool = false, _from_dot: bool = false) -> void:
		pass

func _make_foe(at: Vector2) -> Node2D:
	var foe := ProbeFoe.new()
	_world.add_child(foe)
	foe.global_position = at
	var area := Area2D.new()
	area.collision_layer = 4
	area.collision_mask = 0
	foe.add_child(area)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 16.0
	shape.shape = circle
	area.add_child(shape)
	return foe

## 给敌人挂一个 Hurtbox（BladeProjectile._on_area_entered 只读 area.get_parent()）
func _hurtbox_of(target: Node) -> Area2D:
	var area := Area2D.new()
	area.collision_layer = 4
	area.collision_mask = 0
	target.add_child(area)
	return area
