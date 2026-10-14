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
## 5. 受击视觉零分配 + zoom punch 合并 + 落雷池 + 屏外判定节流：
##    挂上真 SmoothCamera 后，12 次普通命中（is_crit=false）全程 get_processed_tweens() 零增长
##    （含 zoom_punch 路径覆盖：camera 就位后不再 null-shortcut）；
##    12 次暴击命中（is_crit=true）因 SmoothCamera 幅值合并只允许 ≤1 个 zoom tween；
##    0.3s 内闪白参数归零、juice_scale 回正（帧内计时衰减在跑）；
##    落雷 acquire 两轮，第二轮零新建全复用；敌人在屏外 0.5s 内 _offscreen 收敛为 true（10Hz 节流不失效）。
## 6. 环绕灵宝重绘节流（2026-10-11 武器多卡顿优化）：单只灵宝 1 秒
##    ProceduralDroneRenderer.redraw_count 增量 ≤ 25（20Hz 节流 + 错相首拍余量，未节流时 60）。
## 8. 稳态分配率（2026-10-13 Android GC 停顿治理）：
##    8a. RunMotion.facing_stable 复用暂存数组（连续两次调用返回同一实例 = 零 Array 分配）；
##    8b. 35 敌满载 60 物理帧 MEMORY_STATIC 净增量有界（Godot 4 无 OS.get_allocated_memory，
##        净增量测不出 alloc/free churn，故以 8a/8c/8d 行为断言为主、本条为兜底）；
##    8c. 敌人动画名缓存正确（_anim_run == "run_" + facing，朝向变更后仍同源）；
##    8d. 武器连续开火窗口 get_processed_tweens() 增量 ≤ 2（开火视觉零 Tween 化）；
##    8e. 设置变更走 GameFeel 每帧 memo，下一帧生效。
## 9. 重绘节流补网（2026-10-14 逻辑帧治理）：
##    9a. 玩家级修士渲染器 high_fps_mode 1 秒 redraw_count 增量 ≤ 38（30Hz，旧每帧模式约 60+）；
##    9b. AoeTelegraph 预警圈 1 秒重绘 ≤ 38（30Hz，旧每帧无条件 queue_redraw）；
##    9c. WeaponArcRenderer 元素刀光亮起窗口 1 秒重绘 ≤ 38（30Hz）；
##    9d. hit_stop 零分配：压下时间轴 + 写 _hitstop_deadline_ms，GameManager._process 到点还原。
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
	print("PERF: 屏内 13 怪（含 Player 追击）1s 重绘次数 = %d（阈值 ≤ 370）" % redraw_inscreen)
	_check(redraw_inscreen <= 370,
		"重绘节流生效（Player 在场）：13 怪 1s 重绘 ≤ 370（实得 %d，flip_h 写穿时约 780）" % redraw_inscreen)

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
	var mem_before: int = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	for i in range(60):
		await get_tree().physics_frame
		t_sum += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	var avg_ms := t_sum / 60.0 * 1000.0
	print("PERF: 35 敌 + 6 弹丸物理帧均耗时 = %.2f ms（阈值 ≤ 8）" % avg_ms)
	_check(avg_ms <= 8.0, "满载逻辑帧耗时 ≤ 8ms（实得 %.2fms，含 35 怪 AI + Jolt 物理 + 6 弹丸）" % avg_ms)

	# ================= 8b. 满载窗口 MEMORY_STATIC 净增量有界 =================
	# 沿用 soak_check 的 MEMORY_STATIC 口径：只兜「泄漏式增长」，阈值给宽档。
	# 稳态 churn（alloc/free 相抵）由 8a/8c/8d 的行为断言钉住，净增量测不出来。
	var mem_delta: int = int(Performance.get_monitor(Performance.MEMORY_STATIC)) - mem_before
	print("PERF: 35 敌 × 60 物理帧 MEMORY_STATIC 净增量 = %.2f MB（阈值 ≤ 2.0）" % (float(mem_delta) / 1048576.0))
	_check(mem_delta <= 2 * 1048576,
		"满载稳态无泄漏式增长：35 敌 × 60 帧 MEMORY_STATIC ≤ 2MB（实得 %.2fMB）" % (float(mem_delta) / 1048576.0))

	# ================= 8a/8c. facing_stable 暂存数组身份 + 动画名缓存 =================
	# 8a：暂存数组语义探测——第三次调用改写暂存后，先前返回的 face_a 内容随之变化，
	# 证明两次调用返回的是同一实例（= 调用路径零 Array 分配；若每次新分配，face_a 不会被动）。
	var face_a: Array = RunMotion.facing_stable(Vector2(0.0, 1.0), "", false)   # 南向
	var face_before: String = String(face_a[0])
	RunMotion.facing_stable(Vector2(1.0, 0.0), "", false)                        # 东向：覆写暂存
	_check(face_before == "s" and String(face_a[0]) == "e",
		"facing_stable 复用暂存数组：后续调用覆写先前返回（零 Array 分配的直接证据）")
	var face_b: Array = RunMotion.facing_stable(Vector2(0.0, 1.0), "", false)
	_check(String(face_b[0]) == "s" and bool(face_b[1]) == false,
		"facing_stable 返回值仍正确（南向，不翻转）")
	# 8c：动画名缓存与朝向同源（缓存字段 == 手拼字符串）
	var anim_e: EnemyBase = horde[0] as EnemyBase
	if anim_e != null:
		_check(anim_e._anim_idle == "idle_" + anim_e.facing and anim_e._anim_run == "run_" + anim_e.facing,
			"敌人动画名缓存与 facing 同源（%s → %s/%s）" % [anim_e.facing, anim_e._anim_idle, anim_e._anim_run])
		# 强拧朝向走 setter，缓存应跟着重建
		anim_e.facing = "n"
		_check(anim_e._anim_run == "run_n",
			"facing setter 触发动画名缓存重建（n → run_n）")

	# ================= 4. 宝石系统：节流 + 屏外剔除 + 灯名额 + 对象池 + 软上限保险丝 =================
	# 满载战斗期间敌人死亡会掉宝石，先全部回池，避免残留宝石占用灯名额污染判据
	for g in AstralGem._active_gems.duplicate():
		if is_instance_valid(g):
			g.recycle()
	# 玩家挪离宝石网格（原点距 (60,40) 仅 ~72px，拾取圈会把判据宝石吃掉一颗）
	player.global_position = Vector2(380.0, 400.0)
	var gem_scene: PackedScene = load("res://scenes/entities/AstralGem.tscn")
	var gem_created0: int = AstralGem.created_count
	var gem_reused0: int = AstralGem.reused_count
	var gems: Array[AstralGem] = []
	for i in range(120):
		var g := AstralGem.acquire_or_new(gem_scene, world)
		g.global_position = Vector2(60.0 + float(i % 20) * 44.0, 40.0 + floorf(float(i) / 20.0) * 44.0)
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
		g.global_position = Vector2(60.0 + float(i % 20) * 44.0, 40.0 + floorf(float(i) / 20.0) * 44.0)
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
		g.global_position = Vector2(-380.0 + float(i) * 8.0, 380.0)
		g.exp_value = 1
		g.is_gold = false
		g.activate()
		gems2.append(g)
	var fused := 0
	for g in gems2:
		if g.target_player != null:
			fused += 1
	_check(fused >= 1, "软上限保险丝：超 GEM_SOFT_CAP 后最旧宝石被强制吸附（吸附中 %d 颗）" % fused)

	# ================= 5. 受击视觉零分配 + 落雷池 + 屏外判定节流 =================
	# 5a. 受击零 Tween 分配 + zoom punch 路径覆盖：
	#     旧写法每次 take_damage 建 2 个 Tween（挤压+闪白）；现在衰减走帧内计时。
	#     挂上真 SmoothCamera 后，普通命中（is_crit=false）不应产生任何 Tween（zoom_punch 只在暴击分支内）；
	#     12 次暴击命中（is_crit=true）因幅值合并只允许 ≤1 个 zoom tween。
	var cam := SmoothCamera.new()
	world.add_child(cam)
	await get_tree().process_frame
	# 5a-1. 普通命中零 Tween（含 zoom_punch 路径：camera 就位后 zoom_punch 不再 null-shortcut）
	var hit_e := slime_scene.instantiate() as EnemyBase
	hit_e.position = Vector2(300.0, 300.0)
	# 防止小怪 12 刀直接死掉，影响暴击段断言
	hit_e.max_hp = 9999.0
	hit_e.current_hp = 9999.0
	world.add_child(hit_e)
	await get_tree().process_frame
	var tweens_before: int = get_tree().get_processed_tweens().size()
	for i in range(12):
		hit_e.take_damage(5.0, Vector2(30.0, 0.0), false)
	var tween_delta: int = get_tree().get_processed_tweens().size() - tweens_before
	_check(tween_delta == 0, "普通命中零 Tween（含 zoom_punch 路径覆盖）：12 次受击 Tween 零增长（实得 %+d）" % tween_delta)
	await get_tree().create_timer(0.3).timeout
	var flash_val: float = float(hit_e.hit_flash_mat.get_shader_parameter("flash_modifier"))
	_check(flash_val <= 0.001, "闪白帧内计时衰减归零（实得 %.3f）" % flash_val)
	_check(hit_e.juice_scale.distance_to(Vector2.ONE) < 0.02, "挤压回弹帧内计时归位")
	# 5a-2. 暴击命中 zoom punch 合并：12 次同帧暴击最多只建 1 个 zoom tween
	var crit_tweens_before: int = get_tree().get_processed_tweens().size()
	for i in range(12):
		hit_e.take_damage(5.0, Vector2(30.0, 0.0), true)
	var crit_tween_delta: int = get_tree().get_processed_tweens().size() - crit_tweens_before
	_check(crit_tween_delta <= 1, "暴击 zoom punch 幅值合并：12 次暴击 ≤1 Tween（实得 %d）" % crit_tween_delta)
	world.remove_child(hit_e)
	hit_e.free()
	cam.queue_free()

	# 5b. 屏外判定 10Hz 节流不失效：出屏 0.5s 内 _offscreen 必须收敛为 true
	var cull_e := slime_scene.instantiate() as EnemyBase
	cull_e.position = Vector2(-4000.0, -4000.0)
	world.add_child(cull_e)
	await get_tree().create_timer(0.5).timeout
	_check(cull_e._offscreen, "屏外判定节流后仍收敛（10Hz + 错相）")
	world.remove_child(cull_e)
	cull_e.free()

	# 5c. 落雷对象池：acquire 两轮，第二轮零新建全复用
	var tb_scene: PackedScene = load("res://scenes/weapons/ThunderBurst.tscn")
	var tb_created0: int = ThunderBurst.created_count
	var tb_reused0: int = ThunderBurst.reused_count
	var bursts: Array[ThunderBurst] = []
	for i in range(3):
		var tb := ThunderBurst.acquire(world, tb_scene)
		tb.global_position = Vector2(200.0 + 60.0 * float(i), 300.0)
		tb.radius = 70.0
		tb.damage = 1.0
		tb.activate()
		bursts.append(tb)
	_check(ThunderBurst.created_count == tb_created0 + 3,
		"落雷首轮 3 发全量新建 (%d/%d)" % [ThunderBurst.created_count - tb_created0, 3])
	_check(ThunderBurst.reused_count == tb_reused0, "落雷首轮零复用 (%d)" % (ThunderBurst.reused_count - tb_reused0))
	# 等一帧让 call_deferred 的 _deal_damage 结算完，避免回收后残留延迟调用
	await get_tree().process_frame
	for tb in bursts:
		tb._recycle()
	_check(ThunderBurst._pool.size() == 3, "落雷 3 发全部回池 (%d)" % ThunderBurst._pool.size())
	var bursts2: Array[ThunderBurst] = []
	for i in range(3):
		var tb := ThunderBurst.acquire(world, tb_scene)
		tb.global_position = Vector2(-200.0 - 60.0 * float(i), 300.0)
		tb.radius = 70.0
		tb.damage = 1.0
		tb.activate()
		bursts2.append(tb)
	_check(ThunderBurst.created_count == tb_created0 + 3, "落雷第二轮零新建")
	_check(ThunderBurst.reused_count == tb_reused0 + 3, "落雷第二轮复用计数 +3")
	await get_tree().process_frame
	for tb in bursts2:
		tb._recycle()

	# ================= 6. 环绕灵宝渲染重绘节流（2026-10-11 武器多卡顿优化） =================
	## 灵宝矢量 _draw 一帧几十条指令，武器多时曾每帧全量重绘。节流到 20Hz 后
	## 1 秒重绘 ≤ 25（20 次节流拍 + 错相首拍余量，未节流时 60）。
	var drone := ProceduralDroneRenderer.new()
	drone.kind = ProceduralDroneRenderer.DroneKind.LINGDIE
	drone.position = Vector2(480.0, 160.0)   # 屏内
	world.add_child(drone)
	await get_tree().process_frame
	var drone_before: int = ProceduralDroneRenderer.redraw_count
	await get_tree().create_timer(1.0).timeout
	var drone_redraw: int = ProceduralDroneRenderer.redraw_count - drone_before
	print("PERF: 灵宝 1s 重绘次数 = %d（阈值 ≤ 25）" % drone_redraw)
	_check(drone_redraw <= 25,
		"灵宝重绘节流生效：1s ≤ 25（实得 %d，未节流时 60）" % drone_redraw)
	drone.queue_free()

	# ================= 7. 第 10 波 Boss 战现场复刻（flip_h 节流 + Boss 血条 Tween + 道具缓存 + 44 弹丸） =================
	## 复刻用户实机截图（第 10 波：敌 12 弹 44 宝 24 字 35）：
	## 7a. Player 在场时 EnemyBase 每物理帧写 flip_h，验证 setter 同值短路不打穿 20Hz 重绘节流；
	## 7b. HudBossBar + Boss 在场，20 次 Boss 受击 + 20 次满血 player.heal，活跃 Tween 增量 ≤ 2；
	## 7c. 20 件道具在身，item_hook_sum 走缓存，2000 次连续查询耗时 ≤ 4ms；
	## 7d. 44 弹丸 + 35 敌同屏 30 物理帧，逻辑+物理单帧均耗时 ≤ 10ms。
	for g in AstralGem._active_gems.duplicate():
		if is_instance_valid(g):
			g.recycle()
	for e in horde:
		e.global_position = Vector2(-4000.0, -4000.0)
	var track_mobs: Array[EnemyBase] = []
	for i in range(12):
		var e := slime_scene.instantiate() as EnemyBase
		e.position = Vector2(120.0 + 50.0 * float(i), 200.0)
		world.add_child(e)
		track_mobs.append(e)
	player.global_position = Vector2(480.0, 270.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var track_redraw0: int = HollowKnightEnemyRenderer.redraw_count
	await get_tree().create_timer(0.5).timeout
	var track_redraw: int = HollowKnightEnemyRenderer.redraw_count - track_redraw0
	_check(track_redraw <= 165,
		"Player 在场追击下 12 怪 0.5s 重绘 ≤ 165（实得 %d，flip_h 写穿时约 360）" % track_redraw)
	for e in track_mobs:
		world.remove_child(e)
		e.free()
	track_mobs.clear()

	var boss_bar := HudBossBar.new()
	world.add_child(boss_bar)
	var boss_scene: PackedScene = load("res://scenes/entities/BossEnemy.tscn")
	var boss := boss_scene.instantiate() as BossEnemy
	boss.max_hp = 50000.0
	boss.current_hp = 50000.0
	boss.position = player.global_position + Vector2(220.0, 0.0)
	world.add_child(boss)
	await get_tree().process_frame

	player.current_health = player.max_health
	var boss_tw_before: int = get_tree().get_processed_tweens().size()
	for i in range(20):
		boss.take_damage(30.0, Vector2.ZERO, false)
		player.heal(2.0, true)
	await get_tree().process_frame
	var boss_tw_delta: int = get_tree().get_processed_tweens().size() - boss_tw_before
	_check(boss_tw_delta <= 2,
		"Boss 20 连击 + 满血吸血 20 次 Tween 不堆积（增量 %d ≤ 2，旧泄漏时 ≥ 20）" % boss_tw_delta)

	var all_item_ids: Array = ItemData.DEFS.keys()
	for i in range(mini(20, all_item_ids.size())):
		GameManager.add_item(String(all_item_ids[i]))
	var t_hook0 := Time.get_ticks_usec()
	var hook_acc := 0.0
	for i in range(500):
		hook_acc += GameManager.item_hook_sum("crit_per_dodge")
		hook_acc += GameManager.item_hook_sum("still_dodge")
		hook_acc += GameManager.item_hook_sum("still_knockback")
		hook_acc += GameManager.item_hook_sum("kill_explode")
	var hook_ms := float(Time.get_ticks_usec() - t_hook0) / 1000.0
	_check(hook_ms <= 4.0 and hook_acc >= 0.0,
		"20 件道具下 2000 次 item_hook_sum 缓存耗时 ≤ 4ms（实得 %.2fms）" % hook_ms)

	# 补齐到 44 发弹丸（flying 已有 6 发，再取 38 发）
	for i in range(38):
		var p := BladeProjectile.acquire_or_new(proj_scene, world)
		p.global_position = player.global_position + Vector2(-400.0 + 20.0 * float(i), -180.0)
		p.direction = Vector2.RIGHT.rotated(float(i) * 0.14)
		p.lifetime = 5.0
		p.activate()
		flying.append(p)
	# 帧耗时取中位而非均值：多 Agent 并行开发时同一台机常有多个 headless Godot 抢 CPU
	#（实测基线同判据均值可冲到 12~26ms 而空闲时个位数），均值口径会把无关负载误报成回归。
	# 90 帧窗口让中位数把毛刺充分滤掉；约 1.5s，可接受。
	var w10_samples: Array[float] = []
	for i in range(90):
		await get_tree().physics_frame
		w10_samples.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) + Performance.get_monitor(Performance.TIME_PROCESS))
	w10_samples.sort()
	var w10_ms: float = w10_samples[45] * 1000.0
	print("PERF: 第 10 波满载（Boss + 35 敌 + 44 弹丸 + 20 道具）帧耗时中位 = %.2f ms（阈值 ≤ 12）" % w10_ms)
	_check(w10_ms <= 12.0,
		"第 10 波满载（Boss + 敌群 + 44 弹丸 + 20 道具）帧耗时中位 ≤ 12ms（实得 %.2fms）" % w10_ms)

	# ================= 8d. 武器开火视觉零 Tween 化 =================
	# 旧写法每次开火建 3~4 个局部 Tween（后坐+枪口闪光+本体亮闪+光晕）；
	# 现在走帧内状态机，连续开火窗口内活跃 Tween 增量 ≤ 2（平滑相机 zoom punch 等外部余量）。
	var fw := (load("res://scenes/weapons/FloatingWeapon.tscn").instantiate() as FloatingWeapon)
	fw.setup("gengjin_feijian", 1)   # 弹丸系：覆盖 后坐+枪口闪光+亮闪 全链
	fw.position = player.global_position + Vector2(60.0, -40.0)
	world.add_child(fw)
	# 炮门全开：冷却清零 + 给一个屏内目标，_perform_attack 每帧可发
	fw.cooldown_timer = 0.0
	fw.is_attacking = false
	await get_tree().process_frame
	var fire_tw_before: int = get_tree().get_processed_tweens().size()
	for i in range(12):
		fw.cooldown_timer = 0.0
		fw.is_attacking = false
		fw._perform_attack()
	var fire_tw_delta: int = get_tree().get_processed_tweens().size() - fire_tw_before
	print("PERF: 12 次弹丸开火 Tween 增量 = %d（阈值 ≤ 2）" % fire_tw_delta)
	_check(fire_tw_delta <= 2,
		"开火视觉零 Tween：12 次弹丸开火活跃 Tween 增量 ≤ 2（实得 %d，旧写法约 36~48）" % fire_tw_delta)
	# 演出确实在跑：开火后一帧内后坐状态应激活，走完后 is_attacking 归 false
	_check(fw._lunge_t >= 0.0, "后坐状态机已激活（开火即起演）")
	await get_tree().create_timer(0.25).timeout
	_check(not fw.is_attacking, "后坐演出走完自动释放 is_attacking（回调语义等价原 Tween）")
	fw.queue_free()
	await get_tree().process_frame

	# ================= 8e. 设置每帧 memo 生效语义 =================
	# GameFeel 门面走按帧 memo：改设置后同帧读到旧值、下一帧读到新值（一帧 TTL）。
	GameFeel.invalidate_memo()
	SettingsManager.set_val(&"display", &"shake_intensity", &"off")
	GameFeel.invalidate_memo()
	var same_frame_mult: float = GameFeel.shake_mult_memo()
	_check(same_frame_mult <= 0.0, "shake_intensity=off 后 memo 读数为 0（memo 已失效重拉）")
	SettingsManager.set_val(&"display", &"shake_intensity", &"standard")
	GameFeel.invalidate_memo()
	_check(GameFeel.shake_mult_memo() > 0.0, "恢复 standard 后 memo 读数 > 0")

	# ================= 9. 重绘节流补网（2026-10-14 逻辑帧治理） =================
	# 9a. 玩家级修士渲染器 30Hz：high_fps_mode 原每帧全量重绘（444 处 draw_ × 60fps
	#     是逻辑帧最大单一开销），降频后 1 秒 redraw_count 增量应 ≈30（阈值 ≤ 38）。
	var cr := HollowKnightCultivatorRenderer.new(CultivatorVisualConfig.get_config("jianchi"))
	cr.high_fps_mode = true
	world.add_child(cr)
	var cr_before: int = CultivatorRendererBase.redraw_count
	await get_tree().create_timer(1.0).timeout
	var cr_delta: int = CultivatorRendererBase.redraw_count - cr_before
	print("PERF: 玩家级修士渲染器 1s 重绘 = %d（阈值 ≤ 38）" % cr_delta)
	_check(cr_delta <= 38, "玩家渲染器 30Hz 节流：1s 重绘 ≤ 38（实得 %d，旧每帧模式约 60+）" % cr_delta)
	_check(cr_delta >= 20, "玩家渲染器仍在重绘（节流不能把动画卡死，下限 20）")
	world.remove_child(cr)
	cr.free()

	# 9b. 预警圈 30Hz 节流：原每渲染帧无条件 queue_redraw（2 条 48 段弧/帧）。
	var tg := AoeTelegraph.new()
	tg.progress = 0.5
	world.add_child(tg)
	var tg_before: int = AoeTelegraph.redraw_count
	await get_tree().create_timer(1.0).timeout
	var tg_delta: int = AoeTelegraph.redraw_count - tg_before
	print("PERF: 预警圈 1s 重绘 = %d（阈值 ≤ 38）" % tg_delta)
	_check(tg_delta <= 38, "AoeTelegraph 30Hz 节流：1s 重绘 ≤ 38（实得 %d，旧写法约 60+）" % tg_delta)
	_check(tg_delta >= 20, "AoeTelegraph 仍在重绘（下限 20）")
	world.remove_child(tg)
	tg.free()

	# 9c. 元素刀光 30Hz 节流：亮起窗口内原每帧重绘。
	#     先隐后显逼出 VISIBILITY_CHANGED（默认 visible=true 直接 add 不会触发通知，
	#     _process 会被 _ready 的 set_process(false) 关掉）
	var arc := WeaponArcRenderer.new()
	arc.configure(WeaponArcRenderer.ArcMode.MELEE, "fire")
	arc.visible = false
	world.add_child(arc)
	arc.visible = true
	var arc_before: int = WeaponArcRenderer.redraw_count
	await get_tree().create_timer(1.0).timeout
	var arc_delta: int = WeaponArcRenderer.redraw_count - arc_before
	print("PERF: 元素刀光 1s 重绘 = %d（阈值 ≤ 38）" % arc_delta)
	_check(arc_delta <= 38, "WeaponArcRenderer 30Hz 节流：1s 重绘 ≤ 38（实得 %d，旧写法约 60+）" % arc_delta)
	_check(arc_delta >= 20, "WeaponArcRenderer 仍在重绘（下限 20）")
	world.remove_child(arc)
	arc.free()

	# 9d. 顿帧零分配：hit_stop 不再建 SceneTreeTimer（旧实现每次顿帧 create_timer + 闭包）。
	#     恢复由 GameManager._process 按 _hitstop_deadline_ms 轮询。
	SettingsManager.set_val(&"display", &"hit_stop", true, false)
	GameFeel.invalidate_memo()
	GameFeel.hit_stop(GameManager, 0.05, 0.2)
	_check(Engine.time_scale < 1.0, "hit_stop 压下时间轴（time_scale < 1.0）")
	_check(GameManager._hitstop_deadline_ms > 0, "hit_stop 写下恢复截止时刻（零 Timer 分配口径）")
	await get_tree().create_timer(0.2).timeout
	_check(absf(Engine.time_scale - 1.0) < 0.001, "GameManager._process 到点还原 time_scale = 1.0")

	world.remove_child(boss)
	boss.free()
	world.remove_child(boss_bar)
	boss_bar.free()
	DamageNumber.clear_cache()
	JuiceEffect.clear_cache()
	GameManager.reset_run()

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
