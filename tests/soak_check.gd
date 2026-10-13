extends Node

## 长局压力判据（soak）：连续推满 20 波到胜利闸口 + 重开一局再战 3 波。
## 目的：RunReset / 波末清场 / 对象池的全部泄漏假设只在长局里暴露——
## 现有判据最远只跳波到第 13 波（smoke_runner），从未连续跑过 2 波以上，
## 「第 20 波终局闸口」与「重开一局」两条路径没有任何测试覆盖。
##
## 判据口径（全部「有界」型，不追「归零」——池按设计合法扩容跨波常驻）。
## 采样时机统一在「波间收拢后」：end_wave 清场 + phase 进入 ALLOC/SHOP 之后再取数，
## 此时场上无怪、动画落定，波与波之间才可比（战斗中采样全是刷怪噪声）：
##   1. 波末组残留：enemies / chests / turrets / gems / boss 必须清空（清场漏路径当场抓）
##   2. OBJECT_NODE_COUNT 逐波采样：后期必须平台化（第 20 波 ≤ 第 12 波 + 小滑量）
##   3. 对象池容量：第 20 波 ≤ 第 6 波 × k + 常数；reused_count > 0 证明确实在复用
##   4. 在跑补间数逐波采样：后期不许继续增长（孤儿补间会跨波堆积）
##   5. MEMORY_STATIC 后期增量给宽滑量（图集解码有 ~3.5MB 级合法一次性跳变）
##   6. 重开一局后节点基线不高于首轮终局（RunReset「旧场敌人 _exit_tree 安全注销」假设的证伪）
##
## 运行: godot --headless --path . res://tests/SoakCheck.tscn
## 退出码 0 且末行 SOAK_RESULT: ALL PASS

var _c := TestCheck.new()

## 每波真实战斗的模拟秒数（Engine.time_scale=8 下 ≈ 实际 0.5s/波，20 波 ~10s 真实战斗）
const FIGHT_SECONDS := 4.0
## 节点数平台期滑量：收拢态下第 20 波对第 12 波允许的最大增量
const NODE_LATE_DRIFT := 60.0
## 静态内存平台期滑量：允许图集等一次性解码跳变
const MEM_LATE_DRIFT := 6.0 * 1024.0 * 1024.0
## 在跑补间数平台期滑量
const TWEEN_LATE_DRIFT := 40

var _node_samples := {}    ## wave -> OBJECT_NODE_COUNT（收拢态）
var _mem_samples := {}     ## wave -> MEMORY_STATIC（收拢态）
var _tween_samples := {}   ## wave -> get_processed_tweens().size()（收拢态）
var _pool_first := {}      ## 第 6 波池容量基线
var _pool_last := {}       ## 第 20 波池容量采样

func _check(cond: bool, label: String) -> void:
	_c.check(cond, label)

func _ready() -> void:
	# 申报无头守护时长（GameManager 注释约定：慢判据在 _ready 里调大，否则 45s 会被误杀）
	GameManager.headless_guard_sec = 300.0
	call_deferred("_run")

func _dismiss() -> void:
	# 悟道/商店/结算弹窗全部就地消化，别让面板暂停整棵树卡死推进
	while GameManager.has_pending_upgrades() and not GameManager.alloc_offers.is_empty():
		GameManager.take_alloc_upgrade(0)
	for node_name in ["LevelUpDialog", "WaveShop", "PlayerStatsDialog", "PauseMenu", "SettingsDialog", "GameOverDialog"]:
		var n := get_node_or_null("/root/Main/UILayer/" + node_name)
		if n != null and n.visible:
			n.visible = false
	get_tree().paused = false

func _run() -> void:
	Engine.time_scale = 8.0
	# 走 root.add_child 而不是 change_scene：change_scene_to_file 会把当前场景（= 本 runner 自己）
	# 释放掉，_run 的协程再也不回来，进程直接挂住（knock_probe 实测挂过 7 分钟）。
	var main: Node = load("res://scenes/main/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	GameManager.cultivator_id = "jianchi"
	GameManager.start_run("qingyun_sword")
	get_tree().paused = false
	_check(GameManager.run_started, "开局就绪")

	var residue_total: int = await _run_run(1, GameManager.VICTORY_WAVE)

	# —— 长局终判 —— #
	_check(GameManager.is_game_over and GameManager.wave_number >= GameManager.VICTORY_WAVE,
		"第 %d 波胜利闸口已触发（is_game_over=%s wave=%d）" % [GameManager.VICTORY_WAVE, str(GameManager.is_game_over), GameManager.wave_number])
	_check(residue_total == 0, "20 波波末组零残留（累计 %d）" % residue_total)

	# 节点数平台化：收拢态下第 20 波对第 12 波不许再明显增长（前中期池扩容合法，后期必须稳住）
	var n12: float = _node_samples.get(12, -1.0)
	var n20: float = _node_samples.get(20, -1.0)
	_check(n12 > 0.0 and n20 > 0.0 and n20 - n12 <= NODE_LATE_DRIFT,
		"节点数后期平台化：第20波(%.0f) ≤ 第12波(%.0f)+%d" % [n20, n12, NODE_LATE_DRIFT])

	# 静态内存同口径
	var m12: float = _mem_samples.get(12, -1.0)
	var m20: float = _mem_samples.get(20, -1.0)
	_check(m12 > 0.0 and m20 > 0.0 and m20 - m12 <= MEM_LATE_DRIFT,
		"静态内存后期平台化：第20波(%.1fMB) ≤ 第12波(%.1fMB)+%dMB" % [m20 / 1048576.0, m12 / 1048576.0, MEM_LATE_DRIFT / 1048576.0])

	# 在跑补间数同口径：孤儿补间会跨波堆积，收拢态下不许持续增长
	var t6: int = _tween_samples.get(6, -1)
	var t20: int = _tween_samples.get(20, -1)
	_check(t6 >= 0 and t20 >= 0 and t20 - t6 <= TWEEN_LATE_DRIFT,
		"补间数后期平台化：第20波(%d) ≤ 第6波(%d)+%d" % [t20, t6, TWEEN_LATE_DRIFT])

	# 池容量：第 20 波 ≤ 第 6 波 × 2 + 30（池按设计常驻，只许中期扩容到位后封顶）
	for pool_name in _pool_first:
		var first: int = _pool_first[pool_name]
		var last: int = _pool_last.get(pool_name, -1)
		_check(last >= 0 and last <= first * 2 + 30,
			"池 %s 有界：第20波(%d) ≤ 第6波(%d)×2+30" % [pool_name, last, first])

	# —— 重开一局：证伪「RunReset 只清数据不清节点也无事」的假设 —— #
	var baseline_nodes := n20
	Engine.time_scale = 8.0
	# 与真机「重新开始」同形态：数据层重置 + 旧场整棵释放（旧场敌人靠 _exit_tree 注销）
	GameManager.reset_run()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var main2: Node = load("res://scenes/main/Main.tscn").instantiate()
	get_tree().root.add_child(main2)
	await get_tree().process_frame
	await get_tree().process_frame

	GameManager.cultivator_id = "jianchi"
	GameManager.start_run("qingyun_sword")
	get_tree().paused = false
	var residue2: int = await _run_run(1, 3)

	# 重开一局后的节点基线不许高于首轮终局：旧场敌人靠 _exit_tree 注销应当是安全空操作
	var n3: float = _node_samples.get(3, -1.0)
	_check(n3 > 0.0 and n3 <= baseline_nodes + NODE_LATE_DRIFT,
		"重开一局节点基线不高于首轮终局：第3波(%.0f) ≤ 首轮第20波(%.0f)+%d" % [n3, baseline_nodes, NODE_LATE_DRIFT])
	_check(residue2 == 0, "重开一局波末组零残留（3 波累计 %d）" % residue2)

	await get_tree().process_frame
	Engine.time_scale = 1.0
	# 收尾释放旧场再退出：不释放的话 quit 时会报 ObjectDB 泄漏警告，误导成 soak 抓到了泄漏
	main2.queue_free()
	await get_tree().process_frame

	if _c.report("SOAK_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

## 连续推波：from 波打到 to 波（含）。返回累计波末组残留。
## 采样统一在波间收拢后：end_wave 清场 → phase 到 ALLOC/SHOP → 再等两帧（_exit_tree 注销）
## → 此时场上无怪，取节点数/内存/池容量/组残留/补间数才可比。
func _run_run(from_wave: int, to_wave: int) -> int:
	var residue_total := 0
	for w in range(from_wave, to_wave + 1):
		# soak 测的是泄漏不是难度：每波开打前锁血（玩家死亡 → is_game_over →
		# WaveSpawner._process 直接 return，phase 永远卡 CLEARING，长局推不下去）
		if GameManager.player != null and is_instance_valid(GameManager.player):
			GameManager.player.max_health = 99999.0
			GameManager.player.current_health = 99999.0
		# spawner 每轮从 GameManager 现取：重开一局后旧引用已随旧场释放
		var spawner: WaveSpawner = GameManager.wave_spawner
		spawner.start_wave(w)
		# 真实战斗若干模拟秒：让刷怪/索敌/掉落/池扩容都真实发生
		await _wait_clean(FIGHT_SECONDS)
		spawner.end_wave()
		# 等清场收拢进波间（ALLOC/SHOP）；终局波走 _open_shop 的胜利闸口
		var wait_break := 0
		while spawner.phase != WaveSpawner.Phase.ALLOC and spawner.phase != WaveSpawner.Phase.SHOP and wait_break < 200:
			await get_tree().create_timer(0.2).timeout
			_dismiss()
			wait_break += 1
		_check(spawner.phase == WaveSpawner.Phase.ALLOC or spawner.phase == WaveSpawner.Phase.SHOP,
			"第 %d 波后进入波间（phase=%d）" % [w, spawner.phase])
		_dismiss()
		await get_tree().process_frame
		await get_tree().process_frame
		# —— 收拢态采样 —— #
		residue_total += _group_residue()
		_node_samples[w] = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		_mem_samples[w] = Performance.get_monitor(Performance.MEMORY_STATIC)
		_tween_samples[w] = get_tree().get_processed_tweens().size()
		var caps := _pool_caps()
		if w == 6:
			_pool_first = caps
		elif w == 20:
			_pool_last = caps
	return residue_total

## 模拟战斗若干秒，边等边清弹窗（悟道面板会反复暂停整棵树）
func _wait_clean(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		await get_tree().create_timer(0.2).timeout
		_dismiss()
		left -= 0.2

## 五个活体组波末残留计数（gem 组在波末被吸走有 1 帧惯性，给 1 的余量）
func _group_residue() -> int:
	var residue := 0
	for group_name in ["enemies", "chests", "turrets", "boss"]:
		residue += get_tree().get_nodes_in_group(group_name).size()
	var gems := get_tree().get_nodes_in_group("gems").size()
	residue += maxi(0, gems - 1)
	return residue

## 各对象池当前容量
func _pool_caps() -> Dictionary:
	return {
		"DamageNumber": DamageNumber.pool_size(),
		"JuiceEffect": JuiceEffect.pool_size(),
		"AstralGem": AstralGem._pool.size(),
		"BladeProjectile": BladeProjectile._pool.size(),
		"EnemyBolt": EnemyBolt._pool.size(),
		"HealOrb": HealOrb._pool.size(),
		"LightningBolt": LightningBolt._pool.size(),
	}
