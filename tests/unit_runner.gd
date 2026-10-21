extends Node

## 数值逻辑单元测试：纯函数 + 少量需要 GameManager 状态的商店断言
## 运行: godot --headless --path . res://tests/UnitRunner.tscn
## 这些公式以前埋在 autoload / 刷怪器里，必须起整棵场景树才能碰；
## 现在它们都在 GameBalance（static 纯函数）、随机源可由 GameManager.rng 注入，所以能直接断言。
##
## 拆分说明（2026-10-11）：测试体按主题拆到 tests/unit/ 十个模块
## （wave / combat / economy / upgrade / targeting / content / infra / consistency / spiritbeast / spiritpet，基类 UnitTestsBase）。
## 本文件只保留两件事：**与拆分前完全一致的调用顺序**（模块间有共享的 GameManager 状态，
## 顺序本身是判据的一部分，别随手重排）与最终 report。改单测进对应模块文件，别往这里堆。
##
## 2026-10-21：调用清单改成数据表（[模块, 方法名]），按 call() 顺序执行并记入 _ran，
## 末尾用反射把「各模块声明的 _test_* 」与「实际跑过的」求差 —— 漏挂的函数会显性报红，
## 不再出现「写好了却从没跑过」的死断言（本项目真实踩过：4 个 spiritpet 函数静默空转）。

var _c := TestCheck.new()
var _ran: Dictionary = {}

func _ready() -> void:
	var economy := UnitEconomyTests.new(_c)
	var combat := UnitCombatTests.new(_c)
	var wave := UnitWaveTests.new(_c)
	var upgrade := UnitUpgradeTests.new(_c)
	var targeting := UnitTargetingTests.new(_c)
	var content := UnitContentTests.new(_c)
	var infra := UnitInfraTests.new(_c)
	var consistency := UnitConsistencyTests.new(_c)
	var spiritbeast := UnitSpiritBeastTests.new(_c)
	var spiritpet := UnitSpiritPetTests.new(_c)
	var modules: Array[Node] = [economy, combat, wave, upgrade, targeting, content, infra, consistency, spiritbeast, spiritpet]
	for m in modules:
		add_child(m)

	# 调用顺序即判据（模块间共享 GameManager 状态），别随手重排。
	var plan: Array = [
		[economy, "_test_exp_curve"],
		[combat, "_test_armor"],
		[wave, "_test_wave_scaling"],
		[wave, "_test_boss_waves"],
		[wave, "_test_spawn_shape"],
		[wave, "_test_enemy_mix"],
		[wave, "_test_wave_theme"],
		[wave, "_test_new_enemy_mechanics"],
		[wave, "_test_enemy_id_prefixes"],
		[combat, "_test_enemy_bolt"],
		[economy, "_test_pricing"],
		[economy, "_test_tag_affinity"],
		[economy, "_test_harvest"],
		[economy, "_test_early_clear_bonus"],
		[economy, "_test_gem_shard"],
		[economy, "_test_rarity_weights"],
		[economy, "_test_weighted_pick"],
		[economy, "_test_synergy_levels"],
		[upgrade, "_test_upgrade_table"],
		[upgrade, "_test_upgrade_roll_filters"],
		[upgrade, "_test_alloc_session"],
		[economy, "_test_shop_determinism"],
		[economy, "_test_main_tag_pity"],
		[economy, "_test_shop_tag_soft_bias"],
		[targeting, "_test_weapon_targeting"],
		[infra, "_test_audio_wiring"],
		[infra, "_test_settings_manager"],
		[combat, "_test_screen_shake_budget"],
		[content, "_test_five_elements_system"],
		[targeting, "_test_ranged_focus_dps"],
		[content, "_test_new_stat_fields"],
		[content, "_test_item_system"],
		[content, "_test_item_pool_coverage"],
		[content, "_test_cultivator_system"],
		[content, "_test_cultivator_new_mechanics"],
		[content, "_test_cultivator_frenzy_thunder_shop"],
		[content, "_test_conversion_items_and_hooks"],
		[wave, "_test_danger_system"],
		[infra, "_test_start_in_endless"],
		[infra, "_test_achievement_and_meta_save"],
		[infra, "_test_career_milestones"],
		[infra, "_test_skin_system"],
		[infra, "_test_modal_pause_buttons"],
		[infra, "_test_fx_particle_pool"],
		[combat, "_test_knock_direction"],
		[combat, "_test_charge_geometry"],
		[combat, "_test_stat_breakdown_buff"],
		[targeting, "_test_spirit_orbit_dynamics"],
		[content, "_test_turret_and_new_cultivators"],
		[consistency, "_test_upgrade_desc_apply"],
		[consistency, "_test_icon_assets_exist"],
		[consistency, "_test_item_desc_apply"],
		[consistency, "_test_skill_desc_apply"],
		[consistency, "_test_synergy_effects_text"],
		[consistency, "_test_ui_chip_contrast"],
		[consistency, "_test_theme_presets"],
		[consistency, "_test_theme_swap_runtime"],
		[spiritbeast, "_test_spirit_beast_scaling"],
		[spiritbeast, "_test_spirit_beast_constants"],
		[spiritpet, "_test_fengdiao_vortex_formulas"],
		[spiritpet, "_test_fengdiao_ring_geometry"],
		[spiritpet, "_test_fengdiao_data_desc_consistency"],
		# 2026-10-21 补挂：这 4 个函数自 564569f 起就写好了却从未被调用（24 条断言是死代码）。
		[spiritpet, "_test_attack_pets_formulas"],
		[spiritpet, "_test_juchan_tongue_formulas"],
		[spiritpet, "_test_yulu_heal_formulas"],
		[spiritpet, "_test_xuangui_shield_formulas"],
		[combat, "_test_feel_gates"],
		[combat, "_test_hitstop_lowfps_gate"],
		[combat, "_test_weapon_phase_stagger"],
	]
	for entry in plan:
		var mod: Node = entry[0]
		var meth: String = entry[1]
		mod.call(meth)
		_ran[meth] = true

	# 挂载自检：各模块声明的 _test_* 必须「被 plan 调用」或「被某个父测试函数内部调用」。
	# 判据：该名字的调用出现次数 > func 定义次数 ⇒ 有实际调用点（含嵌套辅助）；
	# 只在 plan 里 ⇒ 顶层挂载；两者皆无 ⇒ 死代码（本项目真实踩过：4 个 spiritpet 函数）。
	var uncalled: Array[String] = []
	for m in modules:
		var src := ""
		var sp: Script = m.get_script()
		if sp != null and not String(sp.resource_path).is_empty():
			var f := FileAccess.open(sp.resource_path, FileAccess.READ)
			if f != null:
				src = f.get_as_text()
		for meth in m.get_method_list():
			var nm := String(meth["name"])
			if not nm.begins_with("_test_"):
				continue
			if _ran.has(nm) or uncalled.has(nm):
				continue
			if src.is_empty():
				continue  # 读不到源码就跳过（不制造假红）
			var calls := src.count(nm + "(")
			var defs := src.count("func " + nm + "(")
			if calls <= defs:
				uncalled.append(nm)
	_c.check(uncalled.is_empty(), "所有 _test_* 函数都已被 runner 挂载（漏挂：%s）" % str(uncalled))

	if _c.report("UNIT_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)
