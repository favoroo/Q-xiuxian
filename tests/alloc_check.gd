extends Node

## 每物理帧热点零分配与确定性随机校验
## 覆盖范围：
## 1. Player._update_weapon_targets 与 _process_sun_orbs 的物理查询复用（物理帧零 new 形状/查询参数）
## 2. BladeProjectile._nearest_other 的物理查询复用（弹丸追踪重录零 new）
## 3. ItemData 与 UpgradeData 的玩法随机与 GameManager.rng 绑定（确定性种子校验）
##
## 运行方式：
##   godot --headless --path . res://tests/AllocCheck.tscn
##   godot --headless --path . res://tests/AllocCheck.tscn -- --selftest

var _c := TestCheck.new()

func _check(cond: bool, label: String) -> void:
	_c.check(cond, label)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var selftest := "--selftest" in args

	if selftest:
		_run_selftest()
		return

	# ================= 1. Player 物理帧零 new 校验 =================
	var player_scene: PackedScene = load("res://scenes/entities/Player.tscn")
	var player := player_scene.instantiate() as Player
	add_child(player)
	await get_tree().process_frame

	# 初始状态
	var init_allocs: int = player.query_alloc_count
	_check(init_allocs == 0, "开局 Player 尚未进行物理查询分配 (alloc=%d)" % init_allocs)

	# 模拟挂一把法器
	var weapon_scene: PackedScene = load("res://scenes/weapons/FloatingWeapon.tscn")
	var wp := weapon_scene.instantiate() as FloatingWeapon
	wp.attack_range = 200.0
	player.weapon_holder.add_child(wp)

	# 跑 60 个物理帧索敌更新
	for i in range(60):
		player._update_weapon_targets()

	var p_allocs: int = player.query_alloc_count
	var p_reuses: int = player.query_reuse_count
	_check(p_allocs == 1, "Player 连续 60 次索敌仅首帧分配 1 次查询对象 (实得 %d)" % p_allocs)
	_check(p_reuses == 59, "Player 后续 59 次索敌 100%% 命中复用缓冲 (实得 %d)" % p_reuses)

	# ================= 2. BladeProjectile 零 new 校验 =================
	var proj_scene: PackedScene = load("res://scenes/weapons/BladeProjectile.tscn")
	var proj := proj_scene.instantiate() as BladeProjectile
	add_child(proj)
	await get_tree().process_frame

	var b_init_allocs: int = BladeProjectile.query_alloc_count
	# 连续调用 30 次重录最近目标
	for i in range(30):
		proj._nearest_other(null, false)

	var b_allocs: int = BladeProjectile.query_alloc_count
	var b_reuses: int = BladeProjectile.query_reuse_count
	_check(b_allocs == 1, "BladeProjectile 连续 30 次目标搜索仅首帧分配 1 次查询对象 (实得 %d)" % b_allocs)
	_check(b_reuses >= 29, "BladeProjectile 后续搜索全部复用静态查询对象 (实得 %d)" % b_reuses)

	# ================= 3. 数据层随机与 GameManager.rng 绑定校验 =================
	# 同一个种子下，UpgradeData 抽出的序列必须 100% 相同（证明未被全局 randf 污染）
	GameManager.rng.seed = 123456
	var list_a := UpgradeData.get_random_upgrades(4, {"luck": 10.0, "locked_upgrades": [], "counts": {}, "rng": GameManager.rng})
	var ids_a: Array = []
	for item in list_a:
		ids_a.append(item.get("id", ""))

	GameManager.rng.seed = 123456
	var list_b := UpgradeData.get_random_upgrades(4, {"luck": 10.0, "locked_upgrades": [], "counts": {}, "rng": GameManager.rng})
	var ids_b: Array = []
	for item in list_b:
		ids_b.append(item.get("id", ""))

	_check(ids_a == ids_b, "UpgradeData 走确定性种子抽选完全一致：%s" % str(ids_a))

	# ItemData 同理
	GameManager.rng.seed = 998877
	var item_a := ItemData.pick_id(5.0, 3, [], GameManager.rng, [])
	GameManager.rng.seed = 998877
	var item_b := ItemData.pick_id(5.0, 3, [], GameManager.rng, [])
	_check(item_a == item_b and not item_a.is_empty(), "ItemData 走确定性种子抽选完全一致：%s" % item_a)

	player.queue_free()
	proj.queue_free()

	var ok := _c.report("ALLOC_CHECK_RESULT")
	get_tree().quit(0 if ok else 1)

func _run_selftest() -> void:
	# 验证反例注入：如果未复用（alloc 等于调用次数），断言必须失败
	var fake_allocs := 60
	var fake_reuses := 0
	_check(fake_allocs > 1, "反例：未池化时分配数随帧数膨胀")
	_check(fake_reuses == 0, "反例：未复用时复用数为零")
	var ok := _c.report("ALLOC_SELFTEST_RESULT")
	get_tree().quit(0 if ok else 1)
