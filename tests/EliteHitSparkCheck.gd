extends Node

## 精英/Boss 受击火花判据（2026-10-20）
## 目标：只有「精英/Boss 的非暴击、非 DoT、非致命直击」才补一朵体表火花；
## 普通小怪、暴击、DoT、致命一刀、冷却窗内的连击一律不发。
##
## 断言链：
##   ① 精英非暴击直击 → FxParticlePool 活跃发射器 +1；
##   ② Boss（death_corpse_linger 标记）非暴击直击 → +1；
##   ③ 普通小怪直击 → +0（历史教训：高频割草不糊屏）；
##   ④ 精英 DoT（from_dot）→ +0；
##   ⑤ 精英暴击 → +0（暴击已有方向环+镜头组，不重复）；
##   ⑥ 精英连续两次直击（同帧）→ 只 +1（冷却窗兜底）；
##   ⑦ 精英致命一刀 → 首个新增发射器不是 HIT_SPARK（amount=6），由死亡爆散承担。
##
## 运行: godot --headless --path . res://tests/EliteHitSparkCheck.tscn
## 反例（判据的牙齿）：
##   ① 去掉 is_elite 门 → ③（小怪）报红；
##   ② 去掉 not is_crit 门 → ⑤ 报红；
##   ③ 去掉 not from_dot 门 → ④ 报红；
##   ④ 去掉 _elite_spark_cd 冷却 → ⑥ 报红；
##   ⑤ 把 lethal 判定漏掉 → ⑦ 报红。
## 计数口径：burst 新增发射器是同步 append 到 _active_emitters，finished 只在帧处理时触发，
## 所以「调用前/后同函数内取 size」是可靠的；不依赖 headless 的粒子 finished 是否触发。

var _c := TestCheck.new()
var _world: Node2D
var _pool: FxParticlePool

func _ready() -> void:
	GameManager.reset_run()
	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)
	_pool = FxParticlePool.new()
	add_child(_pool)
	call_deferred("_run")

func _run() -> void:
	# 常量转发就位（防 GameBalance 漏转发导致读 0）
	_c.check(GameBalance.ELITE_HIT_SPARK_INTERVAL > 0.0, "常量转发：火花冷却 > 0")
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
func _reset_hit_budget() -> void:
	FxParticlePool._last_hit_frame = -1
	FxParticlePool._hit_count_this_frame = 0
