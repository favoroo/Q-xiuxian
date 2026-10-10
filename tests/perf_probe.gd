extends Node

## 性能判据探针（2026-10-10 法器多/敌人多卡顿优化配套）
## 判据（全部 headless 可跑）：
## 1. 敌人矢量渲染重绘节流：12 只普通怪 + 1 只精英同屏 1 秒，
##    HollowKnightEnemyRenderer.redraw_count 增量 ≤ 12×25 + 70（普通怪 20Hz + 精英每帧 + 错相余量）；
##    全员移出屏幕 0.5 秒，重绘增量 ≤ 2（屏外剔除）。
## 2. 弹丸对象池：两次 acquire 同一批弹丸，created_count 零增长、reused_count 等量增长；
##    灯名额 ≤ LIGHT_CAP；activate 后视觉/物理状态就位，recycle 后休眠回池。
## 3. 满载逻辑帧耗时：35 敌 + 玩家 + 6 弹丸跑 60 物理帧，
##    Performance.TIME_PHYSICS_PROCESS 均值 ≤ 8ms（只测逻辑+物理，渲染侧另由桌面实测）。
##
## 运行：godot --headless --path . res://tests/PerfProbe.tscn
## 注意：本判据依赖真实节拍，禁止 Engine.time_scale 加速（会破坏重绘节流计时）。

var _c := TestCheck.new()

func _check(cond: bool, label: String) -> void:
	_c.check(cond, label)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var world := Node2D.new()
	world.name = "PerfProbeWorld"
	get_tree().root.add_child(world)
	await get_tree().process_frame

	# ================= 1. 敌人渲染重绘节流 =================
	var slime_scene: PackedScene = load("res://scenes/entities/SlimeEnemy.tscn")
	var elite_scene: PackedScene = load("res://scenes/entities/ChileiEliteEnemy.tscn")
	var mobs: Array[Node] = []
	for i in range(12):
		var e := slime_scene.instantiate() as EnemyBase
		e.position = Vector2(120.0 + 50.0 * i, 200.0)   # 全部落在 960×540 视口内
		world.add_child(e)
		mobs.append(e)
	var elite := elite_scene.instantiate() as EnemyBase
	elite.position = Vector2(480.0, 420.0)
	world.add_child(elite)
	mobs.append(elite)
	await get_tree().process_frame
	await get_tree().process_frame

	var redraw_before: int = HollowKnightEnemyRenderer.redraw_count
	# 跑 1.0 秒真实节拍
	var t_wait := get_tree().create_timer(1.0)
	await t_wait.timeout
	var redraw_inscreen: int = HollowKnightEnemyRenderer.redraw_count - redraw_before
	print("PERF: 屏内 13 怪 1s 重绘次数 = %d（阈值 ≤ 370）" % redraw_inscreen)
	_check(redraw_inscreen <= 370,
		"重绘节流生效：13 怪 1s 重绘 ≤ 370（实得 %d，未节流时约 780）" % redraw_inscreen)

	# 全员移出屏幕：0.5s 内应几乎零重绘
	for e in mobs:
		e.position = Vector2(-4000.0, -4000.0)
	redraw_before = HollowKnightEnemyRenderer.redraw_count
	await get_tree().create_timer(0.5).timeout
	var redraw_offscreen: int = HollowKnightEnemyRenderer.redraw_count - redraw_before
	_check(redraw_offscreen <= 2,
		"屏外剔除生效：13 怪出屏 0.5s 重绘 ≤ 2（实得 %d）" % redraw_offscreen)

	for e in mobs:
		world.remove_child(e)
		e.free()
	mobs.clear()

	# ================= 2. 弹丸对象池 + 灯光上限 =================
	var proj_scene: PackedScene = load("res://scenes/weapons/BladeProjectile.tscn")
	var created0: int = BladeProjectile.created_count
	var reused0: int = BladeProjectile.reused_count
	var projs: Array[BladeProjectile] = []
	for i in range(8):
		var p := BladeProjectile.acquire_or_new(proj_scene, world)
		p.global_position = Vector2(100.0 * i, 100.0)
		p.direction = Vector2.RIGHT
		p.lifetime = 5.0        # 探针期间不让它自灭
		p.bullet_texture = load("res://assets/art/blade.png")
		p.activate()
		projs.append(p)
	_check(BladeProjectile.created_count == created0 + 8,
		"首轮 8 发弹丸全量新建 (%d/%d)" % [BladeProjectile.created_count - created0, 8])
	_check(BladeProjectile.reused_count == reused0,
		"首轮零复用 (%d)" % (BladeProjectile.reused_count - reused0))

	# 灯光名额：8 发在场，点亮的 ≤ LIGHT_CAP
	var lit := 0
	for p in projs:
		if p.glow != null and p.glow.visible:
			lit += 1
	_check(lit == BladeProjectile.LIGHT_CAP,
		"8 发在场只点亮 %d 盏灯（上限 %d）" % [lit, BladeProjectile.LIGHT_CAP])
	# activate 状态就位
	_check(projs[0].visible and not projs[0]._pooled, "activate 后弹丸可见且不在池")

	# 回收全部，再取 8 发：应零新建全复用
	for p in projs:
		p._recycle()
	_check(BladeProjectile._pool.size() == 8, "8 发全部回池 (%d)" % BladeProjectile._pool.size())
	_check(not projs[0].visible and projs[0]._pooled, "回收后弹丸休眠不可见")

	var projs2: Array[BladeProjectile] = []
	for i in range(8):
		var p := BladeProjectile.acquire_or_new(proj_scene, world)
		p.global_position = Vector2(100.0 * i, 300.0)
		p.lifetime = 5.0   # 调用方契约：lifetime 由出膛方设置
		p.activate()
		projs2.append(p)
	_check(BladeProjectile.created_count == created0 + 8,
		"第二轮零新建，全部复用 (%d/%d)" % [BladeProjectile.created_count - created0, 8])
	_check(BladeProjectile.reused_count == reused0 + 8,
		"第二轮复用计数 +8 (%d)" % (BladeProjectile.reused_count - reused0))
	# 池是后进先出：上一轮回收时后 2 发未持灯，本轮换手后灯名额应让给先取出的
	var lit2 := 0
	for p in projs2:
		lit2 += 1 if (p.glow != null and p.glow.visible) else 0
	_check(lit2 == BladeProjectile.LIGHT_CAP, "复用后灯名额重新分配至满 (%d)" % lit2)
	for p in projs2:
		p._recycle()

	# ================= 3. 满载逻辑帧耗时 =================
	var player := (load("res://scenes/entities/Player.tscn").instantiate() as Player)
	world.add_child(player)
	GameManager.player = player
	await get_tree().process_frame

	var horde: Array[Node] = []
	for i in range(35):
		var e := slime_scene.instantiate() as EnemyBase
		var ang := TAU * float(i) / 35.0
		e.position = player.global_position + Vector2(cos(ang), sin(ang)) * (220.0 + 4.0 * i)
		world.add_child(e)
		horde.append(e)
	var flying: Array[BladeProjectile] = []
	for i in range(6):
		var p := BladeProjectile.acquire_or_new(proj_scene, world)
		p.global_position = player.global_position + Vector2(-600.0 + 120.0 * i, -260.0)
		p.direction = Vector2(cos(0.3), sin(0.3))
		p.lifetime = 3.0
		p.activate()
		flying.append(p)

	# 预热 10 帧让物理 broadphase 与渲染状态收敛，再量 60 帧物理帧耗时
	for i in range(10):
		await get_tree().physics_frame
	var t_sum := 0.0
	for i in range(60):
		await get_tree().physics_frame
		t_sum += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	var avg_ms := t_sum / 60.0 * 1000.0
	print("PERF: 35 敌 + 6 弹丸物理帧均耗时 = %.2f ms（阈值 ≤ 8）" % avg_ms)
	_check(avg_ms <= 8.0, "满载逻辑帧耗时 ≤ 8ms（实得 %.2fms，含 35 怪 AI + Jolt 物理 + 6 弹丸）" % avg_ms)

	# 清场
	for p in flying:
		p._recycle()
	for e in horde:
		world.remove_child(e)
		e.free()
	world.remove_child(player)
	player.free()
	GameManager.player = null
	world.free()

	if _c.report("PERF_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)
