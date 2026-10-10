extends Node

## 数值逻辑单元测试：纯函数 + 少量需要 GameManager 状态的商店断言
## 运行: godot --headless --path . res://tests/UnitRunner.tscn
## 这些公式以前埋在 autoload / 刷怪器里，必须起整棵场景树才能碰；
## 现在它们都在 GameBalance（static 纯函数）、随机源可由 GameManager.rng 注入，所以能直接断言。
##
## 拆分说明（2026-10-11）：测试体按主题拆到 tests/unit/ 七个模块
## （wave / combat / economy / upgrade / targeting / content / infra，基类 UnitTestsBase）。
## 本文件只保留两件事：**与拆分前完全一致的调用顺序**（模块间有共享的 GameManager 状态，
## 顺序本身是判据的一部分，别随手重排）与最终 report。改单测进对应模块文件，别往这里堆。

var _c := TestCheck.new()

func _ready() -> void:
	var economy := UnitEconomyTests.new(_c)
	var combat := UnitCombatTests.new(_c)
	var wave := UnitWaveTests.new(_c)
	var upgrade := UnitUpgradeTests.new(_c)
	var targeting := UnitTargetingTests.new(_c)
	var content := UnitContentTests.new(_c)
	var infra := UnitInfraTests.new(_c)
	for m: Node in [economy, combat, wave, upgrade, targeting, content, infra]:
		add_child(m)

	economy._test_exp_curve()
	combat._test_armor()
	wave._test_wave_scaling()
	wave._test_boss_waves()
	wave._test_spawn_shape()
	wave._test_enemy_mix()
	combat._test_enemy_bolt()
	economy._test_pricing()
	economy._test_harvest()
	economy._test_rarity_weights()
	economy._test_weighted_pick()
	economy._test_synergy_levels()
	upgrade._test_upgrade_table()
	upgrade._test_upgrade_roll_filters()
	upgrade._test_alloc_session()
	economy._test_shop_determinism()
	economy._test_main_tag_pity()
	economy._test_shop_tag_soft_bias()
	targeting._test_weapon_targeting()
	infra._test_audio_wiring()
	infra._test_settings_manager()
	combat._test_screen_shake_budget()
	content._test_five_elements_system()
	targeting._test_ranged_focus_dps()
	content._test_new_stat_fields()
	content._test_item_system()
	content._test_cultivator_system()
	wave._test_danger_system()
	infra._test_start_in_endless()
	infra._test_achievement_and_meta_save()
	infra._test_career_milestones()
	combat._test_knock_direction()
	combat._test_charge_geometry()
	targeting._test_spirit_orbit_dynamics()
	content._test_turret_and_new_cultivators()

	if _c.report("UNIT_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)
