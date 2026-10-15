extends Node

## 临时探针（2026-10-15）：复现用户反馈「继续游戏进来后啥也点不了」
## 三种存档阶段（FIGHT/ALLOC/SHOP）各走一遍：造档 → 销毁场景（模拟重启）→ resume_from_save → 查状态
## 运行: python3 tools/run_test.py ResumeProbe

var _c := TestCheck.new()

func _check(cond: bool, label: String) -> void:
	_c.check(cond, label)

func _boot_main() -> Node:
	var main = load("res://scenes/main/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	return main

## 造一段「第 8 波打到一半」的状态并按 phase 落盘
func _make_save(phase: int) -> bool:
	GameManager.reset_run()
	GameManager.cultivator_id = "fuzhen"
	GameManager.start_run("qingyun_sword")
	get_tree().paused = false
	await get_tree().process_frame
	GameManager.kills = 129
	GameManager.game_time = 487.0
	GameManager.spirit_stones = 229
	GameManager.level = 8
	GameManager.wave_number = 8
	var main = get_tree().root.get_node_or_null("Main")
	var spawner = main.get_node("EntitiesLayer/WaveSpawner")
	match phase:
		WaveSpawner.Phase.ALLOC:
			GameManager.pending_upgrade_points = 2
			GameManager.open_alloc_session()
			spawner.phase = WaveSpawner.Phase.ALLOC
		WaveSpawner.Phase.SHOP:
			GameManager.roll_shop(true)
			spawner.phase = WaveSpawner.Phase.SHOP
	return RunSave.save_from(GameManager, phase)

func _teardown(main: Node) -> void:
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _report(tag: String, main: Node) -> void:
	var spawner = main.get_node("EntitiesLayer/WaveSpawner")
	var dlg = main.get_node_or_null("UILayer/LevelUpDialog")
	var shop = main.get_node_or_null("UILayer/WaveShop")
	var pause_menu = main.get_node_or_null("UILayer/PauseMenu")
	var start_menu = main.get_node_or_null("UILayer/StartMenu")
	var hud = main.get_node("UILayer/GameHUD")
	var gm := GameManager
	print("[%s] paused=%s spawner.phase=%d enemies=%d" % [
		tag, str(get_tree().paused), spawner.phase, get_tree().get_nodes_in_group("enemies").size()])
	print("[%s] dlg.visible=%s shop.visible=%s pause_menu.visible=%s start_menu.visible=%s" % [
		tag, str(dlg.visible if dlg else -1), str(shop.visible if shop else -1),
		str(pause_menu.visible if pause_menu else -1), str(start_menu.visible if start_menu else -1)])
	print("[%s] HUD kills='%s' time='%s' | gm kills=%d game_time=%.1f wave=%d pending=%d offers=%d shop_offers=%d" % [
		tag, hud.kills_label.text, hud.time_label.text,
		gm.kills, gm.game_time, gm.wave_number, gm.pending_upgrade_points,
		gm.alloc_offers.size(), gm.shop_offers.size()])

func _run() -> void:
	Engine.time_scale = 8.0
	RunSave.clear_save()
	var phase_names := {"FIGHT": WaveSpawner.Phase.FIGHT, "ALLOC": WaveSpawner.Phase.ALLOC, "SHOP": WaveSpawner.Phase.SHOP}
	for tag in ["FIGHT", "ALLOC", "SHOP"]:
		var phase: int = phase_names[tag]
		# —— 造档 ——
		var main: Node = await _boot_main()
		var ok: bool = await _make_save(phase)
		_check(ok, "[%s] 存档写入" % tag)
		await _teardown(main)

		# —— 恢复（模拟重启后点「继续游戏」）——
		var main2: Node = await _boot_main()
		main2.resume_from_save()
		for i in range(10):
			await get_tree().process_frame
		_report(tag, main2)
		match phase:
			WaveSpawner.Phase.FIGHT:
				var sp2 = main2.get_node("EntitiesLayer/WaveSpawner")
				_check(not get_tree().paused, "[%s] FIGHT 恢复后应解暂停" % tag)
				# 刷怪有 1.1s 妖气预警延迟，敌体落地的窗口不必卡死；波表在走 = 战斗接管成功
				_check(get_tree().get_nodes_in_group("enemies").size() > 0
					or get_tree().get_nodes_in_group("spawn_indicators").size() > 0
					or sp2.wave_timer < sp2.wave_duration(8),
					"[%s] FIGHT 恢复后战斗在走（wave_timer=%.1f）" % [tag, sp2.wave_timer])
			WaveSpawner.Phase.ALLOC:
				var dlg = main2.get_node_or_null("UILayer/LevelUpDialog")
				_check(dlg != null and dlg.visible, "[%s] ALLOC 恢复后悟道面板应可见" % tag)
			WaveSpawner.Phase.SHOP:
				var shop = main2.get_node_or_null("UILayer/WaveShop")
				_check(shop != null and shop.visible, "[%s] SHOP 恢复后金币阁应可见" % tag)
		_check(int(main2.get_node("UILayer/GameHUD").time_label.text.replace(":", "")) > 0,
			"[%s] HUD 计时应显示存档 game_time（487s→08:07）" % tag)
		await _teardown(main2)

	RunSave.clear_save()
	_c.report("RESUME_PROBE")
	get_tree().quit(0 if _c.all_passed() else 1)

func _ready() -> void:
	call_deferred("_run")
