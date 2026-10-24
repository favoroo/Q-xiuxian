extends Node

## EnemyFilter 共享过滤口径判据：影爆/盾势/落雷/蛮兵计数/祭坛冲击波统一走的那份
## 「遍历 enemies 组 → 剔除无效/垂死/自体/匣子/灵草 → 半径圈」现在只有一份定义。
## 本判据钉住三件事：
##   1. 基本圈定：圈内怪在列、圈外怪不在、垂死怪不在、最近的取得到
##   2. 「不算敌人」豁免：匣子/灵草即使被挂进 enemies 组也不许进结果
##      （这是本口径存在的意义——将来新增「组里但不算敌人」的东西只改 EnemyFilter 一处）
##   3. 自体豁免：裂魂铃式「不炸自己」由 from_self 参数承担
## 运行: godot --headless --path . res://tests/EnemyFilterCheck.tscn
## 退出码 0 且末行 ENEMYFILTER_RESULT: ALL PASS

var _c := TestCheck.new()
var _world: Node2D

func _check(cond: bool, label: String) -> void:
	_c.check(cond, label)

func _ready() -> void:
	call_deferred("_run")

## 布一只史莱姆在给定位置（不做波次缩放，裸数值好算）。
## 头less 直跑场景时 tscn 的 ext_resource 脚本偶发加载不出（裸 CharacterBody2D），
## set_script 显式补挂，保证 as EnemyBase 转换可用。
func _spawn_enemy(pos: Vector2) -> EnemyBase:
	var e := load("res://scenes/entities/SlimeEnemy.tscn").instantiate() as EnemyBase
	if e == null:
		var raw := load("res://scenes/entities/SlimeEnemy.tscn").instantiate() as CharacterBody2D
		raw.set_script(load("res://scripts/entities/EnemyBase.gd"))
		e = raw as EnemyBase
	e.global_position = pos
	_world.add_child(e)
	e.add_to_group("enemies")
	return e

func _run() -> void:
	Engine.time_scale = 10.0
	_world = Node2D.new()
	_world.name = "EnemyFilterCheckWorld"
	get_tree().root.add_child(_world)
	await get_tree().process_frame

	var origin := Vector2.ZERO

	# ---------- 0. 前置：实例脚本挂载成功（无脚本时 as EnemyBase 全为 null，判据会测个空） ----------
	var probe := _spawn_enemy(Vector2(9999, 9999))
	_check(probe != null and probe.get_script() != null, "前置：敌人实例挂上了 EnemyBase 脚本")
	probe.queue_free()
	await get_tree().process_frame

	# ---------- 1. 基本圈定 ----------
	var inner := _spawn_enemy(Vector2(50, 0))     # 圈内
	var outer := _spawn_enemy(Vector2(300, 0))    # 圈外
	await get_tree().process_frame

	var got := EnemyFilter.collect(GameManager.live_enemies, origin, 100.0)
	_check(got.size() == 1 and got[0] == inner,
		"半径圈内只圈到 1 只（实得 %d 只）" % got.size())

	got = EnemyFilter.collect(GameManager.live_enemies, origin, INF)
	_check(got.size() == 2, "radius=INF 全场圈定（实得 %d 只）" % got.size())

	_check(EnemyFilter.count_in_range(GameManager.live_enemies, origin, 100.0) == 1,
		"count_in_range 只数圈内 1 只")
	_check(EnemyFilter.count_in_range(GameManager.live_enemies, origin, INF) == 2,
		"count_in_range 全场 2 只")

	# ---------- 2. 垂死怪不算 ----------
	inner.dying = true
	got = EnemyFilter.collect(GameManager.live_enemies, origin, 100.0)
	_check(got.is_empty(), "垂死怪（dying 置位）不进圈定结果")
	inner.dying = false

	# ---------- 3. 「不算敌人」豁免：匣子/灵草即使混进 enemies 组也被剔除 ----------
	# 这是口径统一的正面判据：将来任何「在 enemies 组里但不算敌人」的新东西
	# （召唤物、圈套等）只在 EnemyFilter 加一行，Player/EnemyBase 全部自动跟上。
	# 注意 inner 还活着且不挂 chests —— 它就该在结果里；断言的是匣子/灵草不在列。
	var chest_like := _spawn_enemy(Vector2(60, 0))
	chest_like.add_to_group("chests")   # 模拟「在 enemies 组里但算匣子」
	var herb_like := _spawn_enemy(Vector2(70, 0))
	herb_like.add_to_group("herbs")     # 灵草前瞻位：同样豁免
	got = EnemyFilter.collect(GameManager.live_enemies, origin, 100.0)
	_check(not got.has(chest_like) and not got.has(herb_like),
		"匣子/灵草即使挂在 enemies 组也不进圈定结果")
	_check(got.has(inner), "不挂豁免组的普通怪照常在列（inner）")
	_check(EnemyFilter.count_in_range(GameManager.live_enemies, origin, 100.0) == got.size(),
		"count_in_range 与 collect 同口径（%d/%d）" % [EnemyFilter.count_in_range(GameManager.live_enemies, origin, 100.0), got.size()])

	# 清掉普通怪后：圈里只剩匣子/灵草 ⇒ collect 空、nearest null
	inner.queue_free()
	await get_tree().process_frame
	_check(EnemyFilter.collect(GameManager.live_enemies, origin, 100.0).is_empty(),
		"圈里只剩匣子/灵草 ⇒ collect 为空")
	_check(EnemyFilter.nearest(GameManager.live_enemies, origin, 100.0) == null,
		"nearest 同口径豁免（圈里只剩匣子/灵草 ⇒ null）")

	# ---------- 4. 自体豁免（裂魂铃口径：不炸自己） ----------
	var self_e := _spawn_enemy(Vector2(20, 0))
	var other := _spawn_enemy(Vector2(80, 0))
	got = EnemyFilter.collect(GameManager.live_enemies, origin, 100.0, self_e)
	_check(not got.has(self_e) and got.has(other),
		"from_self 被剔除、场上其余怪保留（实得 %d 只）" % got.size())

	# 清场再验 nearest：不带第 4 组的残留（否则 20px 的 self_e 会比 30px 的 near_a 更近）
	for e in [self_e, other]:
		e.queue_free()
	await get_tree().process_frame

	# ---------- 5. nearest 取最近 ----------
	var near_a := _spawn_enemy(Vector2(30, 0))
	var near_b := _spawn_enemy(Vector2(90, 0))
	_check(EnemyFilter.nearest(GameManager.live_enemies, origin, 100.0) == near_a,
		"nearest 取圈内最近的一只")
	_check(EnemyFilter.nearest(GameManager.live_enemies, origin, 25.0) == null,
		"搜索半径内一只都没有 ⇒ nearest 返回 null")

	# ---------- 6. 清场豁免（清场过程中组里还挂着垂死/将释放节点的情况） ----------
	# queue_free 后组随 _exit_tree 自动出组，组里不会有悬空引用——这条钉的是
	# 「全部存活怪置 dying（节点还在树上、塌缩动画在跑）后连续查询不炸且全部豁免」。
	# 在场的还有 outer（300px）与 chest_like/herb_like（豁免组），一并处置。
	outer.dying = true
	near_a.dying = true
	near_b.dying = true
	var still_ok := true
	for i in range(3):
		got = EnemyFilter.collect(GameManager.live_enemies, origin, INF)
		if not got.is_empty():
			still_ok = false
	_check(still_ok, "清场动画期间连续查询不炸、垂死怪全部豁免")

	for child in _world.get_children():
		if is_instance_valid(child):
			child.queue_free()
	_world.queue_free()
	Engine.time_scale = 1.0

	if _c.report("ENEMYFILTER_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)
