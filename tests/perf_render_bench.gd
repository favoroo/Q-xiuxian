extends Node

## 渲染开销对照台（非判据，必须带窗口跑；--headless 没有渲染数据）。
## 用途：刷怪构成随机会让「优化前/后」的敌人种类与数量对不齐，这里按固定阵型、
## 固定数量、固定敌种阶梯加怪，逐段采样 TIME_PROCESS / 绘制调用 / 图元数，
## 给「每敌固定渲染开销」一个可复现的前后对照数字。
## 运行: Godot --path . --rendering-method gl_compatibility \
##         res://tests/PerfRenderBench.tscn -- --step 15 --steps 3 --secs 2.5 --type slime
## 口径：不推进波次（不调 start_wave，场上只有本台摆的敌人），不装武器（敌人不掉血），
## 玩家锁血防被接触打死导致数量漂移；摆完即冻结敌人物理（_physics_process 关掉）——
## 追玩家会让全部个体叠在一点，脚下地影糊成一坨、绘制量与屏占比每帧都在漂，
## 冻结后阵型固定、每敌命令数恒定，前后两轮才可比。渲染层（重绘节流/绘制调用）照常跑。

var _step := 15
var _steps := 3
var _secs := 2.5
var _type := "slime"
var _no_hud := false   ## --no-hud：隐藏战斗 HUD，用来看「固定底噪」里 UI 占多少
var _probe_map := false  ## --probe-map：逐个隐藏 MapLayer 子层，归因固定绘制开销
var _hide: PackedStringArray = PackedStringArray()  ## --hide MapLayer,AtmosphereLayer ...：逐层隐藏 Main 下的节点定位固定开销

var _enemies: Array[EnemyBase] = []
var _spawn_root: Node2D = null
var _player: Node2D = null

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		var has_next: bool = i + 1 < args.size()
		match String(args[i]):
			"--step": _step = int(String(args[i + 1])) if has_next else _step
			"--steps": _steps = int(String(args[i + 1])) if has_next else _steps
			"--secs": _secs = float(String(args[i + 1])) if has_next else _secs
			"--type": _type = String(args[i + 1]) if has_next else _type
			"--hide": _hide = String(args[i + 1]).split(",") if has_next else _hide
		if String(args[i]) == "--no-hud":
			_no_hud = true
		if String(args[i]) == "--probe-map":
			_probe_map = true

	var main = load("res://scenes/main/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	SettingsManager.set_val(&"display", &"screen_flash", false)
	GameManager.cultivator_id = "jianchi"
	GameManager.start_run("qingyun_sword")
	get_tree().paused = false
	_dismiss_dialogs()
	var hud := get_node_or_null("/root/Main/UILayer/GameHUD")
	if _no_hud and hud != null:
		hud.visible = false
	for n in _hide:
		var target := get_node_or_null("/root/Main/" + n)
		if target is CanvasItem:
			(target as CanvasItem).visible = false
		elif target is CanvasLayer:
			(target as CanvasLayer).visible = false
	await get_tree().process_frame
	_spawn_root = Node2D.new()
	_spawn_root.name = "BenchEnemies"
	get_tree().root.add_child(_spawn_root)
	_player = GameManager.player
	print("[BENCH] start type=%s step=%d steps=%d secs=%.1f" % [_type, _step, _steps, _secs])
	# 静态装饰烘焙状态（归因固定开销用）：MapLayer 里谁还在可见状态、烘焙图有没有挂上
	var map_layer := get_node_or_null("/root/Main/MapLayer")
	if map_layer != null:
		var parts: Array[String] = []
		for child in map_layer.get_children():
			var on := child is CanvasItem and (child as CanvasItem).visible
			parts.append("%s:%s" % [child.name, "on" if on else "off"])
		print("[BENCH] baked=%s MapLayer=[%s]" % [str(BakedDecorTexture.is_baked()), ", ".join(parts)])

	if _probe_map:
		await get_tree().create_timer(1.2).timeout
		await _probe_map_layer()
		get_tree().quit(0)
		return

	for step_i in range(_steps):
		for i in range(_step):
			if not _spawn_one(_enemies.size()):
				break
		await get_tree().create_timer(0.4).timeout
		_dismiss_dialogs()
		await _sample("n=%d" % _enemies.size())
	_flush_counts()
	get_tree().quit(0)

## 环形阵型：第 i 只按黄金角铺开、半径随圈数外扩，避免叠在一点互相挤开把脚下地影糊成一坨。
func _spawn_one(index: int) -> bool:
	var scene: PackedScene = load("res://scenes/entities/SlimeEnemy.tscn")
	if _type != "slime":
		scene = load("res://scenes/entities/%sEnemy.tscn" % _type.capitalize())
	if scene == null or _player == null or not is_instance_valid(_player):
		return false
	var e := EnemyBase.acquire_or_new(scene)
	if e == null:
		return false
	e.reset_for_reuse()
	var ang := float(index) * 2.39996
	var radius := 90.0 + 46.0 * float(index % 6)
	_spawn_root.add_child(e)
	e.global_position = _player.global_position + Vector2(cos(ang), sin(ang) * 0.62) * radius
	e.add_to_group("enemies")
	e.activate()
	e.scale = Vector2.ONE
	# 冻结在阵位上：不追玩家、不接触结算，阵型与屏占比整段不变
	e.set_physics_process(false)
	_enemies.append(e)
	return true

func _sample(tag: String) -> void:
	# 预热：让本段新增敌人的首轮重绘/材质提交落在采样窗外
	var warm := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - warm) / 1000.0 < 0.5:
		await get_tree().process_frame
	var proc_s: Array[float] = []
	var phys_s: Array[float] = []
	var draw_max := 0
	var prim_max := 0
	var fps_sum := 0.0
	var frames := 0
	var start := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - start) / 1000.0 < _secs:
		await get_tree().process_frame
		frames += 1
		proc_s.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		phys_s.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		draw_max = maxi(draw_max, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		prim_max = maxi(prim_max, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
		fps_sum += float(Engine.get_frames_per_second())
		if _player != null and is_instance_valid(_player):
			_player.max_health = 999999.0
			_player.current_health = 999999.0
	if frames == 0:
		return
	proc_s.sort()
	var proc_med := proc_s[proc_s.size() >> 1]
	print("[BENCH] %s fps=%.1f proc_med=%.2fms proc_avg=%.2fms phys=%.2fms draws=%d prims=%d" % [
		tag, fps_sum / float(frames), proc_med, _mean(proc_s), _mean(phys_s),
		draw_max, prim_max])
	# 归因用：烘焙是否已生效（生效后 MapLayer 的静态矢量层会退场）
	print("[BENCH] baked=%s" % str(BakedDecorTexture.is_baked()))

## 归因模式（--probe-map）：逐个隐藏 MapLayer 的子层，打印各自吃掉的绘制调用。
## 只用于定位「固定底噪」在哪一层，不参与前后对照。
func _probe_map_layer() -> void:
	var map_layer := get_node_or_null("/root/Main/MapLayer")
	if map_layer == null:
		print("[BENCH] probe-map: MapLayer 不存在")
		return
	var kids := map_layer.get_children()
	var base := await _sample_draws()
	print("[BENCH] probe-map 全开 draws=%d（子层 %d 个）" % [base, kids.size()])
	for child in kids:
		if not (child is CanvasItem):
			continue
		var item := child as CanvasItem
		item.visible = false
		var d := await _sample_draws()
		print("[BENCH] probe-map 隐藏 %s(%s) → draws=%d（-%.0f）" % [
			child.name, item.get_script().resource_path.get_file() if item.get_script() != null else item.get_class(),
			d, base - d])
		item.visible = true

func _sample_draws() -> int:
	await get_tree().process_frame
	await get_tree().process_frame
	var acc := 0
	for i in range(12):
		await get_tree().process_frame
		acc += int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	return int(round(float(acc) / 12.0))

func _mean(v: Array[float]) -> float:
	var s := 0.0
	for x in v:
		s += x
	return s / float(maxi(v.size(), 1))

func _flush_counts() -> void:
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	print("[BENCH] end enemies=%d draws=%d" % [_enemies.size(), draws])

func _dismiss_dialogs() -> void:
	for node_name in ["LevelUpDialog", "WaveShop", "PlayerStatsDialog", "PauseMenu", "SettingsDialog",
		"StartMenu", "SkillSelect", "StartWeaponSelect", "CultivatorSelect", "TutorialDialog", "StageBackdrop"]:
		var n := get_node_or_null("/root/Main/UILayer/" + node_name)
		if n != null and n.visible:
			n.visible = false
	get_tree().paused = false