extends Node

## 藏宝匣「自动去砸」判据（2026-10-09，用户口径：「人物靠近宝箱，这个武器不会自动去击打这个宝箱」）
##
## 旧代码的口径是"匣子只会被波及、永远不当目标"：四条索敌路径（Player 统筹分配、
## FloatingWeapon._find_target、_volley_targets、BladeProjectile 追击）一律
## `is_in_group("chests") ⇒ continue`。于是玩家走到匣子边上、四周恰好没妖时，
## 法器集体站着不动 —— 匣子明明挂在 4 号层、判定碰得到，却没人主动去打。
##
## 现在改成"匣子只补空位"，本判据钉的就是这条边界，五组各管一段：
## 1) 纯函数层：匣子不许把法器从"还活着的妖"身上拽走，哪怕匣子近得多（第 2 条用例
##    刻意把匣子摆在 40px、妖摆在 200px —— 混进同一条成本函数排序就会选匣子，红）。
##    集火模式（e_count == 1 ⇒ 全部打同一只）照旧优先于砸匣子，这条也一并钉住。
## 2) 现场层（用户报的那一条）：先立负对照 —— 无妖无匣时法器确实在打空；再摆一只匣子，
##    要求若干帧内有法器把它锁成目标、真的打到它、并在 4 秒内自己砸开。
##    少了负对照，"target 非空"可能只是残留目标在骗人；只锁不打同样不算兑现。
## 3) 弹道层：一件法器一次三发、场上只有一只妖时，多出来的那发要转向匣子，
##    而不是往同一个活物身上重复招呼。
## 4) 耐久层：按"几下"计而不按血量 —— 99999 一发放不倒满匣，且头顶读数格数 == 剩余击数。
## 5) 波末层：没砸开的匣子随余妖一起消散，且消散不掉补给（收走 ≠ 砸开）。
##
## 运行: godot --headless --path . res://tests/ChestTargetingCheck.tscn
##       反例：① 把 assign_targets_with_chests 里两段式改成一次混排 ⇒ 第 1 组报红；
##             ② 把 _find_target 的匣子回退删掉 ⇒ 第 2 组报红；
##             ③ 把 _volley_targets 的 chest_cands 追加段删掉 ⇒ 第 3 组报红；
##             ④ 把 SpiritChest.take_damage 改回一击即碎 ⇒ 第 4 组报红；
##             ⑤ 把 WaveSpawner.end_wave 的匣子消散段删掉 ⇒ 第 5 组报红。

var _c := TestCheck.new()

func _check(cond: bool, label: String) -> void:
	_c.check(cond, label)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_pure_priority()
	await _test_live()
	if _c.report("CHESTTARGET_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

# ---------------- 1) 纯函数：匣子只吃闲着的法器 ----------------

func _test_pure_priority() -> void:
	var w1: Array = [{"base_angle": 0.0, "range": 300.0, "prev_id": 0}]
	var w2: Array = [
		{"base_angle": 0.0, "range": 300.0, "prev_id": 0},
		{"base_angle": PI, "range": 300.0, "prev_id": 0},
	]
	var w_short: Array = [
		{"base_angle": 0.0, "range": 300.0, "prev_id": 0},
		{"base_angle": PI, "range": 100.0, "prev_id": 0},
	]
	var chest_near: Array = [{"id": 777, "dist": 40.0, "angle": 0.0}]
	var enemy_far: Array = [{"id": 555, "dist": 200.0, "angle": 0.0}]

	var r1: Array = GameBalance.assign_targets_with_chests(w1, enemy_far, chest_near)
	_check(int(r1[0]) == 0, "一把法器 + 一只妖 + 一只更近的匣子 ⇒ 打妖不打匣（实得 %d）" % int(r1[0]))

	var r2: Array = GameBalance.assign_targets_with_chests(w_short, enemy_far, chest_near)
	_check(int(r2[0]) == 0 and int(r2[1]) == 1,
		"够不着妖的那件短射程法器 ⇒ 补位去砸匣子（实得 %s，匣子下标应为 1）" % str(r2))

	# 集火模式照旧优先：两件都够得着同一只妖时，不许因为脚边有匣子就分一件走
	var r6: Array = GameBalance.assign_targets_with_chests(w2, enemy_far, chest_near)
	_check(int(r6[0]) == 0 and int(r6[1]) == 0,
		"两件法器都够得着同一只妖 ⇒ 仍全部集火，匣子一律不抢（实得 %s）" % str(r6))

	var r3: Array = GameBalance.assign_targets_with_chests(w1, [], chest_near)
	_check(int(r3[0]) == 0, "场上无妖 ⇒ 匣子就是目标（实得 %d）" % int(r3[0]))

	var r4: Array = GameBalance.assign_targets_with_chests(w1, enemy_far, [])
	_check(int(r4[0]) == 0, "无匣子时与原有分配完全一致")

	# 匣子超出该件法器的射程时不许硬锁：dist 400 > range 300
	var r5: Array = GameBalance.assign_targets_with_chests(
		w1, [], [{"id": 777, "dist": 400.0, "angle": 0.0}])
	_check(int(r5[0]) == -1, "匣子在该件法器射程外 ⇒ 无事可做（实得 %d）" % int(r5[0]))

# ---------------- 现场层 ----------------

var _main: Node
var _spawner: WaveSpawner

func _weapons() -> Array[FloatingWeapon]:
	var out: Array[FloatingWeapon] = []
	var holder := GameManager.player.weapon_holder as Node
	for i in range(holder.get_child_count()):
		var w := holder.get_child(i) as FloatingWeapon
		if w != null and is_instance_valid(w):
			out.append(w)
	return out

func _clear_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Node2D:
			e.queue_free()

func _spawn_chest(offset: Vector2) -> SpiritChest:
	var chest := SpiritChest.new()
	chest.global_position = GameManager.player.global_position + offset
	_spawner.get_parent().add_child(chest)
	return chest

func _pips_of(chest: SpiritChest) -> SpiritChest.HitPips:
	## 匣子的读数与碰撞盒都是纯代码建的（节点名是 @HitPips@N），只能按类型遍历取
	for child in chest.get_children():
		if child is SpiritChest.HitPips:
			return child as SpiritChest.HitPips
	return null

func _test_live() -> void:
	_main = load("res://scenes/main/Main.tscn").instantiate()
	get_tree().root.add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame

	GameManager.cultivator_id = "fuzhen"
	GameManager.start_run("qingyun_sword")
	get_tree().paused = false
	await get_tree().create_timer(2.0).timeout

	_spawner = GameManager.wave_spawner
	GameManager.player.max_health = 99999.0
	GameManager.player.current_health = 99999.0
	# 冻住波次状态机：不再刷怪、不结算，剩下的都是这一档判据自己的道具
	_clear_enemies()
	_spawner.phase = WaveSpawner.Phase.ALLOC

	await _test_idle_then_target_chest()
	await _test_enemy_outranks_chest()
	await _test_durability()
	await _test_wave_end_dissolve()

## 2) 用户报的那一条：脚边有匣子、场上无妖 ⇒ 法器要自己动
func _test_idle_then_target_chest() -> void:
	for i in range(12):
		_clear_enemies()
		await get_tree().process_frame
		var chests := get_tree().get_nodes_in_group("chests")
		for ch in chests:
			ch.queue_free()

	var idle_weapons := 0
	for w in _weapons():
		if w.current_target == null:
			idle_weapons += 1
	_check(idle_weapons == _weapons().size() and _weapons().size() > 0,
		"负对照：无妖无匣时法器确实在打空（%d/%d 件无目标）" % [idle_weapons, _weapons().size()])

	var chest := _spawn_chest(Vector2(70.0, 0.0))
	var chest_id := chest.get_instance_id()
	var max_h := chest.max_hits
	var targeted := false
	var hits_taken := 0
	var broken := false
	for i in range(240):
		_clear_enemies()
		await get_tree().process_frame
		for w in _weapons():
			var t := w.current_target
			if t != null and is_instance_valid(t) and t.get_instance_id() == chest_id:
				targeted = true
		if not is_instance_valid(chest):
			broken = true
			hits_taken = max_h
			break
		hits_taken = maxi(hits_taken, max_h - chest.remaining_hits)
	_check(targeted, "脚边有匣子、场上无妖 ⇒ 法器把匣子锁成目标（旧写法：匣子被索敌跳过，永远打空）")
	_check(hits_taken > 0, "锁上之后真的打到了（吃到 %d/%d 下）" % [hits_taken, max_h])
	_check(broken, "无妖时脚边的匣子会被法器自己砸开（用户要的完整结果，不是只『看一眼』）")

## 3) 有妖时匣子不许抢目标 —— 匣子摆在 40px、妖摆在 120px，两者都在射程内
func _test_enemy_outranks_chest() -> void:
	var enemy := _spawner.slime_scene.instantiate() as Node2D
	enemy.global_position = GameManager.player.global_position + Vector2(120.0, 0.0)
	_spawner.get_parent().add_child(enemy)
	var chest := _spawn_chest(Vector2(40.0, 0.0))
	await get_tree().process_frame

	var w := _weapons()[0]
	var got := w._find_target()
	_check(got != null and got != chest and got.has_method("take_damage")
		and not got.is_in_group("chests"),
		"射程内还有活妖 ⇒ 匣子再近也不抢目标（实得 %s）" % str(got))

	# 多出来的那几发不许往同一个活物身上重复招呼：够得着匣子就改砸匣子
	var chest_id := chest.get_instance_id()
	var volley := w._volley_targets(3)
	var volley_has_chest := false
	for t in volley:
		if t != null and is_instance_valid(t) and t.get_instance_id() == chest_id:
			volley_has_chest = true
	_check(volley_has_chest,
		"一次三发、场上只有一只妖 ⇒ 多出来的那发转向匣子而不是重复打同一只（实得 %d 发）" % volley.size())

	chest.queue_free()
	enemy.queue_free()
	_clear_enemies()
	await get_tree().process_frame

## 4) 耐久与读数
func _test_durability() -> void:
	var chest := _spawn_chest(Vector2(70.0, 0.0))
	await get_tree().process_frame

	_check(chest.max_hits == GameBalance.CHEST_BREAK_HITS
		and chest.remaining_hits == GameBalance.CHEST_BREAK_HITS,
		"满匣击数 == GameBalance.CHEST_BREAK_HITS（%d）" % GameBalance.CHEST_BREAK_HITS)

	var pips_full := _pips_of(chest)
	_check(pips_full != null and pips_full.total == chest.max_hits and pips_full.left >= pips_full.total,
		"满匣时读数不亮牌（left >= total ⇒ _draw 直接 return），且格数 == 总击数")

	var gems_before := get_tree().get_nodes_in_group("gems").size()
	chest.take_damage(99999.0, Vector2.ZERO, false)
	_check(not chest.dying and chest.remaining_hits == GameBalance.CHEST_BREAK_HITS - 1,
		"第一下砸不开：耐久按几下计，不吃伤害数值（剩余 %d）" % chest.remaining_hits)
	_check(get_tree().get_nodes_in_group("gems").size() == gems_before, "没砸开就不掉东西")

	var pips := _pips_of(chest)
	_check(pips != null and pips.left == chest.remaining_hits,
		"头顶小牌格数 == 剩余击数（读数与机制同源，实得 %d / %d）" % [pips.left, chest.remaining_hits])

	for i in range(GameBalance.CHEST_BREAK_HITS - 1):
		chest.take_damage(1.0, Vector2.ZERO, false)
	var broke := chest.dying
	await get_tree().process_frame
	await get_tree().process_frame
	_check(get_tree().get_nodes_in_group("gems").size() > gems_before,
		"挨够 %d 下即砸开并掉落补给" % GameBalance.CHEST_BREAK_HITS)
	_check(broke, "砸开后 dying 置位（与 EnemyBase 同名，ThunderBurst 按它跳过已结算目标）")

## 5) 波末收走没砸开的匣子
func _test_wave_end_dissolve() -> void:
	var chest := _spawn_chest(Vector2(90.0, 0.0))
	await get_tree().process_frame
	var gems_before := get_tree().get_nodes_in_group("gems").size()

	_spawner.end_wave()
	_spawner.phase = WaveSpawner.Phase.ALLOC   # 别让它顺势开商店/弹面板
	_check(chest.dying, "波末未砸开的匣子随余妖一起消散（dying 置位）")

	var pips := _pips_of(chest)
	_check(pips == null or not pips.visible, "消散中的匣子不再亮读数")

	await get_tree().create_timer(0.6).timeout
	_check(not is_instance_valid(chest), "消散动画走完即离场（不逐波堆积成箱子阵）")
	_check(get_tree().get_nodes_in_group("gems").size() <= gems_before,
		"消散不掉补给：波末收走 ≠ 砸开")
