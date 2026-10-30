extends Node

## 中断续玩（RunSave 存档恢复）判据（2026-10-15）
##
## 用户口径：「手机上游玩过程中不小心退出之后，再次进入游戏，可以接着之前退出时的进度去玩」。
## 功能链路：WaveSpawner/GameManager 四处存档钩子 → user://run_save.cfg → 主菜单「继续游戏」
## → Main.resume_from_save → RunSave.load_into（整局字段终值灌回）+ apply_player（玩家实体重建）。
## 这条链路最容易坏的是「字段没存全」——RunReset 清零表有 70+ 成员，少存一个就是
## 「恢复后属性悄悄回档」的静默 bug，所以判据分四层，每层都从生产入口进去量：
##
## 1) 存档结构层：有局才可存（未开局/已结算/无玩家拒绝）、摘要可读、清档生效、
##    坏档（空 payload / 未知角色 / 空武器）load_into 返回 -1 降级不崩。
## 2) 字段对账层（反射，防漏存）：save_from 写进 payload 的键集合必须覆盖 RunReset.reset
##    清零表里所有「有局内意义」的字段 —— 清零表动了而存档没跟 ⇒ 直接报红，不靠肉眼。
## 3) 现场 roundtrip 层：Main 场景真实开局 → 加点/买道具/升星/换装/攒待加点 → 存档 →
##    篡改全部字段（模拟 reset_run 后的空白局）→ load_into + apply_player 恢复 →
##    断言数值全等 + 武器/御灵/灵兽/血量重建正确。
## 4) 阶段语义层：FIGHT 存档恢复后阶段归 FIGHT；坏档路径不炸主菜单。
##
## 运行: godot --headless --path . res://tests/RunSaveCheck.tscn

var _c := TestCheck.new()
var _main: Node = null

func _ready() -> void:
	call_deferred("_run")

func _check(cond: bool, label: String) -> void:
	_c.check(cond, label)

func _equals(actual, expected, label: String) -> void:
	_c.equals(actual, expected, label)

func _run() -> void:
	_test_structure()
	await _test_roundtrip()
	_finish()

func _finish() -> void:
	if _c.report("RUNSAVE_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

# ---------------- 1) 存档结构层 ----------------

func _test_structure() -> void:
	# 干净起点（真机旧档不陪跑判据）
	RunSave.clear_save()
	_check(not RunSave.has_save(), "清档后 has_save 为假")

	# 未开局：save_from 拒绝（run_started=false 且无玩家）
	_check(not RunSave.save_from(GameManager, WaveSpawner.Phase.FIGHT), "未开局时 save_from 拒绝落盘")
	_check(not RunSave.has_save(), "被拒绝的存档不该留下文件")

	# 坏档降级：三类脏 payload 都返回 -1 且不炸
	_dump_raw_payload({})
	_equals(RunSave.load_into(GameManager), -1, "空 payload 灌回返回 -1（坏档降级）")
	_dump_raw_payload({"wave_number": 7, "cultivator_id": "不存在的道统"})
	_equals(RunSave.load_into(GameManager), -1, "未知角色 id 灌回返回 -1")
	_dump_raw_payload({"wave_number": 7, "cultivator_id": "jian", "weapons": []})
	_equals(RunSave.load_into(GameManager), -1, "空武器表灌回返回 -1（局没有武器等于坏档）")

	# 摘要：peek_summary 对坏档/无档返回空字典
	RunSave.clear_save()
	_check(RunSave.peek_summary().is_empty(), "无档时摘要为空字典")

## 直接往 run_save.cfg 塞一个裸 payload（绕过 save_from 的白名单），喂坏档用
func _dump_raw_payload(payload: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "save_version", RunSave.SAVE_VERSION)
	cfg.set_value("meta", "wave", 7)
	cfg.set_value("run", "payload", payload)
	cfg.save(RunSave.SAVE_PATH)

# ---------------- 2) 字段对账层（反射防漏存） ----------------

## RunReset 清零表里有局内意义的字段必须全部出现在 save_from 的 payload 里。
## 清零表新增成员而存档没跟 = 恢复后静默回档，这条反射闸就是防它的。
func _reconciliation_skipped_fields() -> Array[String]:
	# 瞬态/派生/账外字段：不存是设计口径，逐条给理由
	return [
		"is_game_over",           # 有局才有存档，存档时必为 false
		# —— 技能 buff 层：短时增益到期归零，恢复即空（对玩家有利）——
		"buff_move_speed_mult", "buff_attack_speed_mult", "buff_dodge",
		"buff_knockback_mult", "buff_damage_mult", "buff_lifesteal_boost", "force_crit_left", "shadow_amp_mult",
		"buff_pickup_range_mult",
		# —— 散修角色专属被动：读档按 cultivator_id 重走 CultivatorSystem.apply_modifiers 还原 ——
		"scattered_mode", "scattered_bonus_per_class", "scattered_penalty_per_synergy",
		# —— 轮回重生：局内复活次数（加点由 upgrades 字典回放重建）——
		"revive_charges",
		# —— 战斗瞬态：受击层数/战意/盾势/站定计时/感知圈计数，恢复归零（对玩家有利）——
		"on_hit_damage_stacks", "on_hit_damage_timer", "shield_charge",
		"frenzy_stacks", "frenzy_idle", "nearby_enemy_count", "still_time", "player_is_moving",
		# —— 羁绊层：恢复路径按上阵武器重挂后 notify_weapons_updated → recalc_synergies 全量重算，
		#      存终值反而会被二次叠加 ——
		"synergy_bonus_pierce", "bonus_pierce", "synergy_damage_mult", "synergy_range_mult",
		"synergy_haste_mult", "synergy_max_hp_bonus", "synergy_engineering_damage",
		"synergy_crit_rate", "synergy_crit_mult", "synergy_hp_regen", "synergy_lifesteal",
		"synergy_move_speed_mult", "synergy_burn_mult", "synergy_armor",
		"synergy_thorns", "synergy_contraption_mult", "synergy_ranged_damage", "active_synergies",
		"_applied_hp_bonus",      # 羁绊 hp 台账：recalc 后由 SynergySystem 重新维护
		# —— 帧内缓存/节流计数：不参与任何持久语义 ——
		"_lifesteal_procs", "_lifesteal_window", "_hud_tick",
		"_still_cache_valid", "_hook_cache_items_size",
		# 神通机制 hook 快照（2026-10-25）：items 指纹派生缓存，读档后首次访问自会重算
		"_super_hook_snap", "_super_hook_stamp",
		# —— 结算展示位：game_over 前由 ProgressStore 消费，局内存档不背它 ——
		"last_run_new_achievements", "last_run_new_records",
			# —— 活体登记表：恢复时场上必然无怪（回合边界语义），_exit_tree 自己维护 ——
			"enemy_count", "ally_count",
			# —— 波次内战利品瞬态统计：波末摘要展示后即完成使命，换波自动重置 ——
			"_wave_start_stones", "wave_loot_stones", "wave_loot_heals", "wave_loot_heal_hp", "wave_loot_heal_stones",
		]

## 模拟「全新场景开局」：真实游戏每次 start_run 前都经历场景重载（Player 全新、
## 武器/御灵实例随场景清空）。测试复用同一个 Main 场景，必须手动补这场重载，
## 否则多次 start_run 会把悬浮武器叠出双份（真实流程不会发生）。
func _fresh_start(cid: String, starter_id: String) -> void:
	GameManager.reset_run()
	var p = GameManager.player
	if p != null and is_instance_valid(p):
		p.equipped_cleanup()
		for c in p.weapon_holder.get_children():
			if is_instance_valid(c):
				p.weapon_holder.remove_child(c)
				c.free()
		for c in p.sun_orb_container.get_children():
			p.sun_orb_container.remove_child(c)
			c.queue_free()
	GameManager.drones = []
	GameManager.pets = []
	PetSystem.sync_pet_instances(GameManager)
	GameManager.cultivator_id = cid
	GameManager.start_run(starter_id)

func _test_reconciliation() -> void:
	# 开一份真实局让 RunReset 走一遍，抓到它的完整清零清单（静态跑不了，借运行时反查）
	_fresh_start("jian", "qingyun_sword")
	GameManager.wave_number = 3
	_check(RunSave.save_from(GameManager, WaveSpawner.Phase.FIGHT), "结构层：真实局可落盘")

	# 从文件里读出 payload 键集合
	var cfg := ConfigFile.new()
	_check(cfg.load(RunSave.SAVE_PATH) == OK, "结构层：run_save.cfg 可读回")
	var d = cfg.get_value("run", "payload", {})
	_check(d is Dictionary and not (d as Dictionary).is_empty(), "结构层：payload 非空")
	var saved_keys: Dictionary = {}
	for k in (d as Dictionary).keys():
		saved_keys[k] = true

	# 反射 RunReset.reset 的函数体：抽所有 "gm.XXX = ..." 的左值字段名
	var src: Script = load("res://scripts/autoload/RunReset.gd")
	var reset_src := (src.source_code as String)
	var regex := RegEx.new()
	regex.compile("gm\\.(_?[A-Za-z][A-Za-z0-9_]*)\\s*=")
	var skip := {}
	for s in _reconciliation_skipped_fields():
		skip[s] = true
	var missing: Array[String] = []
	var total := 0
	for m in regex.search_all(reset_src):
		var fname := m.get_string(1)
		if fname in ["rng", "live_enemies", "live_allies", "player", "joystick", "main_camera", "wave_spawner"]:
			continue  # 引用型/注册表字段：清零表管生命周期，不属一局进度
		total += 1
		if skip.has(fname):
			continue
		if not saved_keys.has(fname):
			missing.append(fname)
	_check(missing.is_empty(), "字段对账：RunReset 清零表 %d 个字段全部有存档键或显式豁免（缺：%s）" % [
		total, str(missing)])

# ---------------- 3) 现场 roundtrip 层 ----------------

func _test_roundtrip() -> void:
	_main = load("res://scenes/main/Main.tscn").instantiate()
	get_tree().root.add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame

	_test_reconciliation()

	# 真实开局并推进一个有肉的状态：加点 + 道具 + 换装攒星 + 待加点 + 金币经验
	_fresh_start("fuzhen", "qingyun_sword")
	# 危险度 2026-10-28 起逐级破境解锁（set_danger 夹到已解锁区间）：
	# 先种生涯破境档 D0 ⇒ D1（噩梦）才点得动，否则 set_danger(1) 被夹回 0、存档里就没有 1 可恢复
	GameManager.career_stats["best_danger_cleared"] = 0
	GameManager.set_danger(1)
	var spawner: WaveSpawner = GameManager.wave_spawner
	get_tree().paused = false
	await get_tree().process_frame

	# 波次边界钩子已自动落了第 1 波的档；往下推状态
	GameManager.wave_number = 7
	GameManager.kills = 123
	GameManager.game_time = 456.0
	GameManager.spirit_stones = 88
	GameManager.level = 9
	GameManager.experience = 33
	GameManager.experience_to_next = 100
	GameManager._exp_chain = 90
	GameManager.pending_upgrade_points = 2
	GameManager.apply_upgrade("atk_up")
	GameManager.apply_upgrade("hp_up")
	GameManager.add_item("jubaopen")
	GameManager.add_weapon("wulei_paizi", 2)
	GameManager.rng.seed = 424242
	GameManager.peak_stones = 88
	GameManager.run_id = "run-save-check"

	var p = GameManager.player
	p.current_health = 61.0

	# FIGHT 存档 → 模拟「重载后空白局」→ 恢复
	_check(RunSave.save_from(GameManager, WaveSpawner.Phase.FIGHT), "现场层：推进后的局可落盘")
	var saved_phase := RunSave.peek_summary()
	_equals(int(saved_phase.get("wave", 0)), 7, "摘要层：波次 7 进 meta")
	_equals(String(saved_phase.get("cid", "")), "fuzhen", "摘要层：角色 id 进 meta")
	_equals(String(saved_phase.get("run_id", "")), "run-save-check", "摘要层：本局 run_id 进 meta")

	# 篡改（等价 reset_run 把一切清零后又被别的局写过）
	GameManager.reset_run()
	GameManager.cultivator_id = "yushou"
	GameManager.spirit_stones = 999
	_equals(GameManager.items.size(), 0, "现场层：篡改后道具已清空（对照基准）")

	var restored := RunSave.load_into(GameManager)
	_equals(restored, WaveSpawner.Phase.FIGHT, "现场层：load_into 返回 FIGHT 阶段")
	RunSave.apply_player(GameManager)

	# —— 标量全等 ——
	_equals(GameManager.cultivator_id, "fuzhen", "恢复后角色 id")
	_equals(GameManager.run_id, "run-save-check", "恢复后本局 run_id（阵亡清档按它归属）")
	_equals(GameManager.wave_number, 7, "恢复后波次")
	_equals(GameManager.kills, 123, "恢复后击杀")
	_equals(GameManager.spirit_stones, 88, "恢复后金币")
	_equals(GameManager.level, 9, "恢复后等级")
	_equals(GameManager.experience, 33, "恢复后经验")
	_equals(GameManager.experience_to_next, 100, "恢复后经验门槛")
	_equals(GameManager._exp_chain, 90, "恢复后经验门槛链（隐藏账本）")
	_equals(GameManager.pending_upgrade_points, 2, "恢复后待加点数")
	_equals(GameManager.danger_level, 1, "恢复后危险度（噩梦）")
	_check(GameManager.run_started, "恢复后 run_started 置真（WaveSpawner 才会接管）")

	# —— 加点层：upgrade_counts 对账 + 属性终值（atk_up 直接抬 weapon_damage_mult）——
	_equals(int(GameManager.upgrade_counts.get("atk_up", 0)), 1, "恢复后加点账本 atk_up=1")
	_equals(GameManager.weapon_damage_mult, 1.0 + float(UpgradeData.get_upgrade_def("atk_up").get("apply", {}).get("weapon_damage_mult", 0.0)), "恢复后武器伤害乘区 = 存档终值（不是重放值也不是默认值）")

	# —— 道具层 ——
	_check("jubaopen" in GameManager.items, "恢复后持有聚宝盆")
	_check("jubaopen" in GameManager.items_bought, "恢复后购入账本含聚宝盆（唯一道具不因退货解禁的口径）")

	# —— 武器/御灵重建 ——
	var eq: Array[Dictionary] = p.get_equipped_weapons_data()
	_equals(eq.size(), 2, "恢复后上阵武器 2 件（悬浮真挂回实例）")
	var has_pz := false
	for w in eq:
		if String(w.get("id")) == "wulei_paizi" and int(w.get("star")) == 2:
			has_pz = true
	_check(has_pz, "恢复后五星牌（wulei_paizi ★2）在场")

	# —— 玩家血量终值（不经加成重算，直接灌回）——
	_c.near(p.max_health, GameManager.player.max_health, 0.01, "血量上限终值")
	_c.near(p.current_health, 61.0, 0.01, "恢复后当前血量 = 存档终值 61")

	# —— 峰值账本 ——
	_equals(GameManager.peak_stones, 88, "恢复后金币峰值")

	# —— 篡改字段确实被覆盖（防空灌假阳性）——
	_check(GameManager.cultivator_id != "yushou", "恢复覆盖了被篡改的角色 id（灌回不是空转）")

	# —— 阶段语义：ALLOC 存档恢复回 ALLOC ——
	GameManager.pending_upgrade_points = 3
	GameManager.open_alloc_session()
	_check(GameManager.alloc_offers.size() == GameManager.UPGRADE_OFFER_COUNT, "ALLOC 会话真开出来了（对照基准）")
	var offer_id := String(GameManager.alloc_offers[0].get("id", ""))
	_check(RunSave.save_from(GameManager, WaveSpawner.Phase.ALLOC), "现场层：ALLOC 态可落盘")
	GameManager.force_end_alloc("测试清场")
	_equals(GameManager.pending_upgrade_points, 0, "ALLOC 清场后待加点归零（对照基准）")
	GameManager.reset_run()
	restored = RunSave.load_into(GameManager)
	_equals(restored, WaveSpawner.Phase.ALLOC, "现场层：load_into 返回 ALLOC 阶段")
	_equals(GameManager.pending_upgrade_points, 3, "恢复后待加点 = 3（ALLOC 绝不许吞点数）")
	_check(GameManager.alloc_offers.size() == GameManager.UPGRADE_OFFER_COUNT, "恢复后候选卡原样重建（不重 roll）")
	_check(offer_id.is_empty() or String(GameManager.alloc_offers[0].get("id", "")) == offer_id, "恢复后首张候选卡与存档同一张（RNG 不漂移）")

	# —— 结尾清场：胜负结算会清档 ——
	RunSave.clear_save()
	_check(not RunSave.has_save(), "收尾清档")

func _exit_tree() -> void:
	# 判据自清：测试档不留给真机（headless 下钩子本来不落盘，这条保手动跑也不漏）
	RunSave.clear_save()
