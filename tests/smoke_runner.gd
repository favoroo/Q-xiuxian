extends Node

## 无头全流程冒烟测试：道统选择→本命法器→战斗→升级→灵韵结算→商店(锁/买/reroll/合成)→新波次敌种
## 运行: godot --headless --path . res://tests/SmokeRunner.tscn

var _failures: Array = []

func _check(cond: bool, label: String) -> void:
	if cond:
		print("[PASS] " + label)
	else:
		_failures.append(label)
		print("[FAIL] " + label)

func _dismiss_dialogs() -> void:
	for node_name in ["LevelUpDialog", "WaveShop", "PlayerStatsDialog", "PauseMenu"]:
		var n := get_node_or_null("/root/Main/UILayer/" + node_name)
		if n != null and n.visible:
			n.visible = false
	get_tree().paused = false

## 边等边清理弹窗（多级连升会连续弹出 LevelUpDialog 并反复暂停）
func _wait_clean(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		await get_tree().create_timer(0.2).timeout
		_dismiss_dialogs()
		left -= 0.2

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var main = load("res://scenes/main/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	# 1. 道统 + 本命法器（绕过 UI，直接走逻辑层）
	GameManager.cultivator_id = "fuzhen"
	GameManager.start_run("qingyun_sword")
	get_tree().paused = false
	_check(GameManager.run_started, "道统 fuzhen 开局")
	_check(GameManager.drones.size() == 2, "符阵灵童自带 2 灵蝶 (实际 %d)" % GameManager.drones.size())

	await get_tree().create_timer(2.0).timeout
	_check(GameManager.wave_number == 1, "第 1 波已开启")
	var enemy_count := get_tree().get_nodes_in_group("enemies").size()
	_check(enemy_count > 0, "敌人已刷出 (%d)" % enemy_count)

	# 2. 升级与加点（含新属性）
	GameManager.add_spirit_stones(500)
	for up_id in ["crit_up", "dodge_up", "lifesteal_up", "luck_up", "harvest_up", "range_up"]:
		GameManager.apply_upgrade(up_id)
	_check(GameManager.crit_rate > 0.1, "暴击率加点生效 %.2f" % GameManager.crit_rate)
	_check(GameManager.dodge > 0.05, "身法闪避加点生效")
	_check(GameManager.harvest >= 8.0, "灵韵加点生效")
	var ups := UpgradeData.get_random_upgrades(3)
	_check(ups.size() == 3, "升级三选一抽取 (得 %d 项)" % ups.size())

	# 3. 强制触发一次升级弹窗路径（验证信号链不炸），随后关闭
	GameManager.add_experience(50)
	await get_tree().process_frame
	_dismiss_dialogs()

	# 4. 结束本波 → 灵韵结算 → 商店
	var spawner: Node = GameManager.wave_spawner
	var stones_before := GameManager.spirit_stones
	spawner.end_wave()
	await _wait_clean(2.0)
	_check(GameManager.spirit_stones > stones_before, "灵韵波末结算发灵石 (+%d)" % (GameManager.spirit_stones - stones_before))
	_check(GameManager.shop_offers.size() == 4, "商店 4 货架 (实际 %d)" % GameManager.shop_offers.size())
	_dismiss_dialogs()

	# 5. 商店护栏：锁定保留 / 购买 / reroll 递增
	GameManager.toggle_lock(0)
	var locked_id: String = GameManager.shop_offers[0].get("id", "")
	GameManager.roll_shop(true)
	_check(GameManager.shop_offers[0].get("id", "") == locked_id and GameManager.shop_offers[0].get("locked", false), "锁定商品跨刷新保留")
	var cost1: int = GameManager.reroll_cost
	GameManager.reroll_shop()
	_check(GameManager.reroll_cost > cost1, "reroll 费用递增 %d→%d" % [cost1, GameManager.reroll_cost])
	var bought := false
	for i in range(GameManager.shop_offers.size()):
		if GameManager.buy_offer(i):
			bought = true
			break
	_check(bought, "购买一件商品")

	# 6. 三合一合成 + 羁绊
	GameManager.add_weapon("huoyan_fu")
	GameManager.add_weapon("huoyan_fu")
	GameManager.add_weapon("huoyan_fu")
	_check(GameManager.count_copies("huoyan_fu", 1) >= 3, "三把火焰符就位")
	_check(GameManager.bonus_pierce >= 1, "符箓羁绊穿透加成生效 (+%d)" % GameManager.bonus_pierce)
	var merged := GameManager.merge_weapon("huoyan_fu", 1, {"pool": "equipped", "index": 0})
	_check(merged, "三合一合成成功")
	_check(GameManager.active_synergies.has("talisman"), "羁绊表含符箓")

	# 7. 跳到 13 波验证新敌种 + 灵药丛
	spawner.start_wave(13)
	await _wait_clean(6.0)
	var herbs := get_tree().get_nodes_in_group("herbs").size()
	_check(herbs > 0, "灵药丛已刷新 (%d)" % herbs)
	var kinds := {}
	for e in get_tree().get_nodes_in_group("enemies"):
		kinds[e.name.get_basename()] = true
	print("[INFO] 13 波在场敌种: " + str(kinds.keys()))

	# 8. 灵药丛摧毁掉落
	var herb = get_tree().get_nodes_in_group("herbs")[0] if herbs > 0 else null
	if herb != null:
		var gems_before := get_tree().get_nodes_in_group("gems").size()
		herb.take_damage(1.0, Vector2.ZERO, false)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(get_tree().get_nodes_in_group("gems").size() > gems_before, "灵药丛摧毁后掉落补给")

	await _wait_clean(2.0)
	_dismiss_dialogs()

	if _failures.is_empty():
		print("SMOKE_RESULT: ALL PASS")
	else:
		print("SMOKE_RESULT: %d FAILURES: %s" % [_failures.size(), str(_failures)])
	get_tree().quit(0 if _failures.is_empty() else 1)
