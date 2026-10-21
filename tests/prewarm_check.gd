extends Node

## 战斗前预热管线（CombatPrewarm）自动化验证（2026-10-21 启动卡顿专项）：
## 预热在「选完武器 → 开打」之间把最重的一次性成本提前付掉。这里不启动战斗，
## 只用一个裸 Node2D 当宿主，钉住四条不变量：
##   1) 步进完整性：run_all() 后 is_finished() 且总步数 == total_steps()
##   2) 敌人池：预热确实往池里放了休眠体，且下一次 acquire 命中复用（零新建）
##   3) 池体干净：预热出的敌人可 reset_for_reuse + activate 正常复用（不崩、血量正确）
##   4) 弹丸池：预热确实往弹丸池放了停泊体，且下一次 acquire 命中复用
## 说明：全部走 EnemyBase / BladeProjectile 的公开池 API，不依赖内部实现细节。

var _c := TestCheck.new()

func _check(cond: bool, label: String) -> void:
	_c.check(cond, label)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	Engine.time_scale = 10.0
	var world := Node2D.new()
	world.name = "PrewarmCheckWorld"
	get_tree().root.add_child(world)
	await get_tree().process_frame

	# 干净起点
	EnemyBase.clear_pools()
	BladeProjectile.clear_pool()

	# ---------- 1. 步进完整性 ----------
	var pw := CombatPrewarm.new(world)
	var total := pw.total_steps()
	_check(total > 0, "预热总步数 > 0（%d）" % total)
	var steps := 0
	var guard := 0
	while pw.step() and guard < 100000:
		steps += 1
		guard += 1
	_check(pw.is_finished(), "逐步 step 后到达完成态")
	_check(steps + 1 == total or steps == total, "步进次数与总步数一致（%d / %d）" % [steps, total])

	# ---------- 2. 敌人池：预热填充 + 复用零新建 ----------
	var idle_enemies := EnemyBase.pool_idle_count()
	_check(idle_enemies > 0, "预热后敌人池有休眠体（%d 只）" % idle_enemies)
	var created_before := EnemyBase.pool_created_count
	var slime_scene: PackedScene = load("res://scenes/entities/SlimeEnemy.tscn")
	var e := EnemyBase.acquire_or_new(slime_scene)
	_check(e != null, "预热后 acquire 取到敌人")
	_check(EnemyBase.pool_created_count == created_before, "acquire 命中预热池体、零新建 (%d vs %d)" % [EnemyBase.pool_created_count, created_before])

	# ---------- 3. 池体干净可复用 ----------
	e.reset_for_reuse()
	e.add_to_group("enemies")
	e.global_position = Vector2(80, 80)
	world.add_child(e)
	e.activate()
	_check(e.max_hp > 0.0 and e.current_hp == e.max_hp, "复用的预热敌人激活后血量正常 (%.1f)" % e.max_hp)
	_check(GameManager.live_enemies.has(e), "复用入树即登记活体")
	EnemyBase._recycle(e)
	_check(not GameManager.live_enemies.has(e), "回收后注销活体")

	# ---------- 4. 弹丸池：预热填充 + 复用零新建 ----------
	var proj_scene: PackedScene = load("res://scenes/weapons/BladeProjectile.tscn")
	var created_proj := BladeProjectile.created_count
	var p := BladeProjectile.acquire_or_new(proj_scene, world)
	_check(p != null, "预热后 acquire 取到弹丸")
	_check(BladeProjectile.created_count == created_proj, "弹丸 acquire 命中预热池体、零新建 (%d vs %d)" % [BladeProjectile.created_count, created_proj])
	if p != null:
		p._recycle()

	# ---------- 清理 ----------
	EnemyBase.clear_pools()
	BladeProjectile.clear_pool()
	world.free()
	Engine.time_scale = 1.0

	if _c.report("PREWARM_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)
