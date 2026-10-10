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
## 4. 宝石系统（2026-10-10 第 6 波卡顿优化）：120 颗宝石同屏 1 秒，
##    ProceduralLootRenderer.redraw_count 增量 ≤ 120×25+60（20Hz 节流 + 错相余量，未节流约 7200）；
##    全员移出屏幕 0.5 秒，重绘增量 ≤ 2（屏外剔除）；120 颗在场只点亮 GEM_LIGHT_CAP 盏灯；
##    回收再取两轮，第二轮 created 零增长、reused 等量增长（对象池）；
##    场上宝石数超 GEM_SOFT_CAP 后，最旧一颗被强制 magnet_to（软上限保险丝，无经验损失）。
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

	# ================= 4. 宝石系统：节流 + 屏外剔除 + 灯名额 + 对象池 + 软上限保险丝 =================
	# 满载战斗期间敌人死亡会掉宝石，先全部回池，避免残留宝石占用灯名额污染判据
	for g in AstralGem._active_gems.duplicate():
		if is_instance_valid(g):
			g.recycle()
	# 玩家挪离宝石网格（原点距 (60,40) 仅 ~72px，拾取圈会把判据宝石吃掉一颗）
	player.global_position = Vector2(480.0, 500.0)
	var gem_scene: PackedScene = load("res://scenes/entities/AstralGem.tscn")
	var gem_created0: int = AstralGem.created_count
	var gem_reused0: int = AstralGem.reused_count
	var gems: Array[AstralGem] = []
	for i in range(120):
		var g := AstralGem.acquire_or_new(gem_scene, world)
		g.global_position = Vector2(60.0 + float(i % 20) * 44.0, 40.0 + float(i / 20) * 44.0)
		g.exp_value = 1
		g.is_gold = false
		g.activate()
		gems.append(g)
	_check(AstralGem.created_count == gem_created0 + 120,
		"宝石首轮 120 颗全量新建 (%d/%d)" % [AstralGem.created_count - gem_created0, 120])

	# 重绘节流：屏内 120 颗跑 1.0s，20Hz + 错相 ⇒ ≤ 120×25 + 余量（未节流约 7200）
	var gem_redraw_before: int = ProceduralLootRenderer.redraw_count
	await get_tree().create_timer(1.0).timeout
	var gem_redraw_inscreen: int = ProceduralLootRenderer.redraw_count - gem_redraw_before
	_check(gem_redraw_inscreen <= 3060,
		"宝石重绘节流：120 颗 1s 重绘 ≤ 3060（实得 %d）" % gem_redraw_inscreen)

	# 屏外剔除
	for g in gems:
		g.global_position = Vector2(-4000.0, -4000.0)
	gem_redraw_before = ProceduralLootRenderer.redraw_count
	await get_tree().create_timer(0.5).timeout
	var gem_redraw_off: int = ProceduralLootRenderer.redraw_count - gem_redraw_before
	_check(gem_redraw_off <= 2, "宝石屏外剔除：出屏 0.5s 重绘 ≤ 2（实得 %d）" % gem_redraw_off)

	# 灯名额：120 颗在场只点亮 GEM_LIGHT_CAP 盏
	var gem_lit := 0
	for g in gems:
		var lt := g.get_node_or_null("PointLight2D") as PointLight2D
		if lt != null and lt.visible:
			gem_lit += 1
	_check(gem_lit == AstralGem.GEM_LIGHT_CAP,
		"宝石灯名额：120 颗只点亮 %d 盏（上限 %d）" % [gem_lit, AstralGem.GEM_LIGHT_CAP])

	# 对象池：回收全部再取，零新建全复用
	for g in gems:
		g.recycle()
	_check(AstralGem._pool.size() == 120, "宝石 120 颗全部回池 (%d)" % AstralGem._pool.size())
	var gems2: Array[AstralGem] = []
	for i in range(120):
		var g := AstralGem.acquire_or_new(gem_scene, world)
		g.global_position = Vector2(60.0 + float(i % 20) * 44.0, 40.0 + float(i / 20) * 44.0)
		g.exp_value = 1
		g.is_gold = (i % 30 == 0)   ## 混入金宝验证 activate 状态重铺
		g.activate()
		gems2.append(g)
	_check(AstralGem.created_count == gem_created0 + 120,
		"宝石第二轮零新建 (%d/%d)" % [AstralGem.created_count - gem_created0, 120])
	_check(AstralGem.reused_count == gem_reused0 + 120,
		"宝石第二轮复用计数 +120 (%d)" % (AstralGem.reused_count - gem_reused0))
	_check(gems2[1].is_gold == false and gems2[0].is_gold == true,
		"activate 后金宝/普宝视觉状态重铺正确")

	# 软上限保险丝：场上 120 颗再补 21 颗 ⇒ 第 141 颗起最旧的被强制吸附
	for i in range(21):
		var g := AstralGem.acquire_or_new(gem_scene, world)
		g.global_position = Vector2(-480.0 + float(i) * 8.0, 480.0)
		g.exp_value = 1
		g.is_gold = false
		g.activate()
		gems2.append(g)
	var fused := 0
	for g in gems2:
		if g.target_player != null:
			fused += 1
	_check(fused >= 1, "软上限保险丝：超 GEM_SOFT_CAP 后最旧宝石被强制吸附（吸附中 %d 颗）" % fused)

	# 清场（清场统一放文件尾）
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
