extends Node

## 深层波次高负载压力基准（非判据，优化前后对照用；带窗口跑才有绘制调用数据）。
## 与 PerfRenderBench 的差别：那里冻结敌人、不装武器，只测「每敌固定渲染开销」；
## 这里复刻 20+ 波真实战斗全链路 —— 24 敌（硬上限）追击/放弹 + Boss + 8 件三星武器
## 齐射 + 伤害跳字 + 命中特效 + 百颗宝石磁吸，采帧时间分布（p50/p95/p99/最差）。
## 敌人设巨额 HP 保证数量恒定（不测死亡爆散，它有 FRAME_BUDGET 闸且非稳态负载）。
##
## 运行（窗口 + 移动管线，贴近真机口径）：
##   Godot --path . --rendering-method gl_compatibility res://tests/PerfStressBench.tscn
## 参数：--enemies 24 --secs 4 --no-numbers（归因：S3 起关跳字）--no-vfx（预留）
## 口径：关 vsync 量真实帧耗时；敌人不杀、玩家锁血、宝石手动铺场，逐段采样。
## 分阶段：S0 空场底噪 → S1 敌群（AI/物理/渲染）→ S2 全链路（+武器/弹丸/跳字/特效/宝石）
##   → S3 关跳字归因（仅 --no-numbers 时）。

var _enemies_n := 24
var _secs := 4.0
var _attr_numbers := false   ## --no-numbers：追加一段「关伤害跳字」归因采样
var _probe := false          ## --probe：S2 状态下逐层隐藏归因绘制调用
var _shot := false           ## --shot：S1/S2 采样中段各存一张视口截图到 /tmp（视觉回归用）

var _player: Node2D = null
var _enemies: Array = []
var _boss: Node = null

## 敌人配比（合计 24 = GameBalance.MAX_ENEMIES_HARD_CAP）：近战群 + 远程放弹 + 深层老手 + 精英
const MOB_MIX := [
	["res://scenes/entities/SlimeEnemy.tscn", 6],
	["res://scenes/entities/FengQunEnemy.tscn", 4],
	["res://scenes/entities/DanBaoEnemy.tscn", 3],
	["res://scenes/entities/XieXiuEnemy.tscn", 3],
	["res://scenes/entities/HanPoEnemy.tscn", 3],
	["res://scenes/entities/MoWeiEnemy.tscn", 2],
	["res://scenes/entities/GuYaoEnemy.tscn", 1],
	["res://scenes/entities/ChileiEliteEnemy.tscn", 1],
	["res://scenes/entities/JianshaEliteEnemy.tscn", 1],
]
## 8 件三星武器全行为覆盖：弹丸×3 + 近战 + 横扫 + 爆发 + 火锥 + 雷击
const WEAPON_MIX := [
	"gengjin_feijian", "liuye_feidao", "shoulijian", "qingyun_sword",
	"qingmu_tengbian", "bihai_chaoyindi", "sanmei_huohu", "wulei_paizi",
]
const GEM_COUNT := 100

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		var has_next: bool = i + 1 < args.size()
		match String(args[i]):
			"--enemies": _enemies_n = int(String(args[i + 1])) if has_next else _enemies_n
			"--secs": _secs = float(String(args[i + 1])) if has_next else _secs
		if String(args[i]) == "--no-numbers":
			_attr_numbers = true
		if String(args[i]) == "--probe":
			_probe = true
		if String(args[i]) == "--shot":
			_shot = true

	# 关 vsync / 帧率帽：量真实单帧成本而非被显示刷新率钳制
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	# 压测窗口置顶（2026-11-03 归因修正）：窗口被编辑器/其他窗口遮住时 macOS 会停止呈现，
	# RENDER_TOTAL_DRAW_CALLS_IN_FRAME 冻结在上一帧（曾实测全阶段恒 176），采样全失真。
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)

	var main = load("res://scenes/main/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	SettingsManager.set_val(&"display", &"screen_flash", false)
	GameManager.cultivator_id = "jianchi"
	GameManager.start_run("qingyun_sword")
	get_tree().paused = false
	_dismiss_dialogs()
	await get_tree().process_frame
	_player = GameManager.player
	# 锁血：高负载下接触伤害照常结算，但玩家不能死（死了结算面板会中断采样）
	_player.max_health = 9999999.0
	_player.current_health = 9999999.0
	print("[STRESS] start enemies=%d secs=%.1f attr_numbers=%s" % [_enemies_n, _secs, str(_attr_numbers)])

	# ---------- S0 空场底噪 ----------
	await _sample("S0_empty")

	# ---------- S1 敌群（AI + 物理 + 渲染 + 敌弹） ----------
	_spawn_horde(_enemies_n)
	_spawn_boss()
	await _sample("S1_horde%d+boss" % _enemies.size())

	# ---------- S2 全链路（+8 武器齐射 + 跳字 + 特效 + 宝石磁吸） ----------
	for w_id in WEAPON_MIX:
		_player.add_weapon_instance(w_id, 3)
	_spawn_gems(GEM_COUNT)
	await _sample("S2_full_weapons%d_gems%d" % [WEAPON_MIX.size(), GEM_COUNT])

	# ---------- S3 归因：关伤害跳字 ----------
	if _attr_numbers:
		SettingsManager.set_val(&"display", &"damage_numbers", false)
		await _sample("S3_no_numbers")
		SettingsManager.set_val(&"display", &"damage_numbers", true)

	# ---------- 归因探针：S2 状态下逐层隐藏量绘制调用 ----------
	if _probe:
		await _probe_layers()

	_cleanup()
	get_tree().quit(0)

## 逐层隐藏归因：每藏一类对象量一次 draws，差值即该类的绘制调用占用。
## 读取顺序即归因报告；藏完全部恢复可见，不影响后续清理。
func _probe_layers() -> void:
	var full := await _probe_draws("全开")
	_census()
	var main := get_node_or_null("/root/Main")
	# 候选层：UILayer / MapLayer / 敌群 / Boss / 宝石宿主 / 跳字池 / 弹丸池 / 武器架
	var targets: Array = []
	if main != null:
		for n in main.get_children():
			if n is CanvasItem or n is CanvasLayer:
				targets.append([n.name, n])
	targets.append(["<enemies_group>", null])
	targets.append(["<gems_host>", get_node_or_null("/root/StressGems")])
	targets.append(["<dmg_pool>", null])
	targets.append(["<proj_pool>", null])
	targets.append(["<weapon_holder>", _player.get_node_or_null("WeaponHolder") if _player != null else null])
	for pair in targets:
		var label: String = String(pair[0])
		var node = pair[1]
		if label == "<enemies_group>":
			for e in get_tree().get_nodes_in_group("enemies"):
				if e is CanvasItem:
					(e as CanvasItem).visible = false
			var d := await _probe_draws(label)
			print("[PROBE] 隐藏 %s → draws=%d（-%d）" % [label, d, full - d])
			for e in get_tree().get_nodes_in_group("enemies"):
				if e is CanvasItem:
					(e as CanvasItem).visible = true
			continue
		if label == "<dmg_pool>":
			node = _find_named("DamageNumberPool")
		if label == "<proj_pool>":
			node = _find_named("BladeProjectilePool")
		if node == null or not is_instance_valid(node):
			continue
		if node is CanvasItem:
			(node as CanvasItem).visible = false
		elif node is CanvasLayer:
			(node as CanvasLayer).visible = false
		else:
			continue
		var d2 := await _probe_draws(label)
		print("[PROBE] 隐藏 %s → draws=%d（-%d）" % [label, d2, full - d2])
		if node is CanvasItem:
			(node as CanvasItem).visible = true
		elif node is CanvasLayer:
			(node as CanvasLayer).visible = true

func _find_named(node_name: String) -> Node:
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur.name == node_name:
			return cur
		stack.append_array(cur.get_children())
	return null

func _probe_draws(label: String) -> int:
	await get_tree().process_frame
	await get_tree().process_frame
	var acc := 0
	for i in range(10):
		await get_tree().process_frame
		acc += int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	return int(round(float(acc) / 10.0))

## 可见 CanvasItem 普查：draws 归因的旁证（谁占了节点/谁可能在画）
func _census() -> void:
	var by_class: Dictionary = {}
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		stack.append_array(cur.get_children())
		if cur is CanvasItem and (cur as CanvasItem).is_visible_in_tree():
			var cls := cur.get_class()
			if cur.get_script() != null:
				cls = String(cur.get_script().resource_path.get_file()).get_basename() + ":" + cls
			by_class[cls] = int(by_class.get(cls, 0)) + 1
	var keys := by_class.keys()
	keys.sort_custom(func(a, b): return int(by_class[a]) > int(by_class[b]))
	var parts: Array[String] = []
	for k in keys:
		parts.append("%s=%d" % [k, int(by_class[k])])
	print("[PROBE] 可见画布项普查: %s" % ", ".join(parts))

func _spawn_horde(total: int) -> void:
	var idx := 0
	for pair in MOB_MIX:
		var scene: PackedScene = load(String(pair[0]))
		var count: int = int(pair[1])
		for j in range(count):
			if idx >= total:
				break
			var e := EnemyBase.acquire_or_new(scene)
			if e == null:
				continue
			e.reset_for_reuse()
			get_tree().root.add_child(e)
			var ang := float(idx) * 2.39996
			var radius := 110.0 + 14.0 * float(idx % 12)
			e.global_position = _player.global_position + Vector2(cos(ang), sin(ang) * 0.62) * radius
			e.add_to_group("enemies")
			e.activate()
			# 巨额 HP：武器照打、跳字照跳、特效照发，但怪不死 —— 数量恒定才可前后对照
			e.max_hp = 99999999.0
			e.current_hp = 99999999.0
			_enemies.append(e)
			idx += 1

func _spawn_boss() -> void:
	var scene: PackedScene = load("res://scenes/entities/BossEnemy.tscn")
	_boss = scene.instantiate()
	get_tree().root.add_child(_boss)
	_boss.global_position = _player.global_position + Vector2(240.0, -80.0)
	_boss.max_hp = 99999999.0
	_boss.current_hp = 99999999.0

func _spawn_gems(n: int) -> void:
	var gem_scene: PackedScene = load("res://scenes/entities/AstralGem.tscn")
	var host := Node2D.new()
	host.name = "StressGems"
	get_tree().root.add_child(host)
	for i in range(n):
		var g := AstralGem.acquire_or_new(gem_scene, host)
		var ang := float(i) * 2.39996
		var radius := 160.0 + 3.0 * float(i % 40)
		g.global_position = _player.global_position + Vector2(cos(ang), sin(ang) * 0.6) * radius
		g.exp_value = 1
		g.is_gold = (i % 25 == 0)
		g.activate()

## 采样中段视口截图（视觉回归：合批描线是否画对）
func _shot_mid(tag: String) -> void:
	if not _shot:
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("/tmp/stress_%s.png" % tag)
	print("[STRESS] shot saved /tmp/stress_%s.png" % tag)

func _sample(tag: String) -> void:
	# 预热：让新上阵对象的首次重绘/材质提交/池预热落在采样窗外
	var warm := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - warm) / 1000.0 < 0.8:
		await get_tree().process_frame
		_keepalive()

	var frames: Array[float] = []     ## 墙钟帧间隔（含渲染），ms
	var proc_s: Array[float] = []
	var phys_s: Array[float] = []
	var draw_max := 0
	var draw_sum := 0
	var prim_max := 0
	var mem0: int = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var last_us := Time.get_ticks_usec()
	var start := Time.get_ticks_msec()
	var shot_done := false
	while (Time.get_ticks_msec() - start) / 1000.0 < _secs:
		await get_tree().process_frame
		if not shot_done and (Time.get_ticks_msec() - start) / 1000.0 > _secs * 0.5:
			shot_done = true
			await _shot_mid(tag)
		var now_us := Time.get_ticks_usec()
		frames.append(float(now_us - last_us) / 1000.0)
		last_us = now_us
		proc_s.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		phys_s.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		var d := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		draw_max = maxi(draw_max, d)
		draw_sum += d
		prim_max = maxi(prim_max, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
		_keepalive()
	if frames.is_empty():
		return
	frames.sort()
	proc_s.sort()
	phys_s.sort()
	var n := frames.size()
	var mem_delta_mb := float(int(Performance.get_monitor(Performance.MEMORY_STATIC)) - mem0) / 1048576.0
	# 超帧统计：>16.7ms 视为掉帧（60fps 口径），>33.3ms 视为严重卡顿
	var over16 := 0
	var over33 := 0
	for f in frames:
		if f > 16.7:
			over16 += 1
		if f > 33.3:
			over33 += 1
	print("[STRESS] %s frames=%d fps=%.1f | frame min=%.2f p50=%.2f p95=%.2f p99=%.2f max=%.2f ms | >16.7ms:%d >33.3ms:%d" % [
		tag, n, 1000.0 / _mean(frames), frames[0], frames[n >> 1], frames[int(n * 0.95)], frames[int(n * 0.99)], frames[n - 1], over16, over33])
	print("[STRESS] %s proc p50=%.2f p99=%.2f ms | phys p50=%.2f p99=%.2f ms | draws avg=%d max=%d prims max=%d | nodes=%d memΔ=%.1fMB" % [
		tag, proc_s[n >> 1], proc_s[int(n * 0.99)], phys_s[n >> 1], phys_s[int(n * 0.99)],
		int(float(draw_sum) / float(maxi(n, 1))), draw_max, prim_max,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), mem_delta_mb])
	print("[STRESS] %s live: projectiles=%d dmg_numbers=%d gems=%d pool(proj)=%d pool(num)=%d" % [
		tag, BladeProjectile.active_count, DamageNumber.active_count, AstralGem._active_gems.size(),
		BladeProjectile._pool.size(), DamageNumber.pool_size()])

func _keepalive() -> void:
	# 采样期间持续锁血（被围殴时 contact damage 每帧结算，不能让人死了）
	if _player != null and is_instance_valid(_player):
		_player.current_health = 9999999.0

func _cleanup() -> void:
	for g in AstralGem._active_gems.duplicate():
		if is_instance_valid(g):
			g.recycle()
	for e in _enemies:
		if is_instance_valid(e):
			e.queue_free()
	_enemies.clear()
	if is_instance_valid(_boss):
		_boss.queue_free()
	DamageNumber.clear_cache()

func _mean(v: Array[float]) -> float:
	var s := 0.0
	for x in v:
		s += x
	return s / float(maxi(v.size(), 1))

func _dismiss_dialogs() -> void:
	for node_name in ["LevelUpDialog", "WaveShop", "PlayerStatsDialog", "PauseMenu", "SettingsDialog",
		"StartMenu", "SkillSelect", "StartWeaponSelect", "CultivatorSelect", "TutorialDialog", "StageBackdrop"]:
		var n := get_node_or_null("/root/Main/UILayer/" + node_name)
		if n != null and n.visible:
			n.visible = false
	get_tree().paused = false
