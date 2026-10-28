extends Node

## 多存档位判据（2026-10-28）
##
## 用户口径：「最多 5 个手动存档；暂停时选位存入；5 位全满要选一个旧档删掉再存；
## 阵亡只清本局存下的档，别的角色/别的局的档保留」。
##
## 覆盖：
## 1) 位号/摘要/落盘：5 位固定，空位可存，摘要带角色/波次/等级/难度/时长/run_id。
## 2) 上限与覆盖：占位默认拒绝；allow_overwrite 走原子覆盖（旧档写失败仍在）。
## 3) 位隔离：删一位不动其他位；脏文件只把该位标损坏，读它返回 -1 且不改 GameManager。
## 4) 整局 roundtrip：存位 → reset → 读回 + apply_player，标量与武器重建正确。
## 5) 阵亡清档：clear_run_slots 只删同 run_id 的位；trigger_game_over 接线生效。
##
## 运行: godot --headless --path . res://tests/SaveSlotsCheck.tscn

const TEST_DIR := "user://test_save_slots"

var _c := TestCheck.new()
var _main: Node = null

func _ready() -> void:
	call_deferred("_run")

func _check(cond: bool, label: String) -> void:
	_c.check(cond, label)

func _equals(actual, expected, label: String) -> void:
	_c.equals(actual, expected, label)

func _run() -> void:
	SaveSlots.set_storage_dir_for_tests(TEST_DIR)
	SaveSlots.clear_all()
	_main = load("res://scenes/main/Main.tscn").instantiate()
	get_tree().root.add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame

	_fresh_start("fuzhen", "qingyun_sword")
	GameManager.run_id = "run-a"
	GameManager.wave_number = 5
	GameManager.level = 3
	GameManager.danger_level = 1
	GameManager.game_time = 123.0

	# ---- 1) 落盘与摘要 ----
	_check(SaveSlots.save_current(GameManager, 1), "空位 1 可落盘")
	var e1 := SaveSlots.peek(1)
	_check(bool(e1.get("occupied", false)), "位 1 落盘后 occupied")
	_check(not bool(e1.get("corrupt", false)), "位 1 不是坏档")
	_equals(int(e1.get("wave", 0)), 5, "摘要波次 5")
	_equals(int(e1.get("level", 0)), 3, "摘要等级 3")
	_equals(String(e1.get("cid", "")), "fuzhen", "摘要角色 id")
	_equals(int(e1.get("danger", 0)), 1, "摘要难度 1")
	_c.near(float(e1.get("play_time", 0.0)), 123.0, 0.01, "摘要时长 123s")
	_equals(String(e1.get("run_id", "")), "run-a", "摘要 run_id 归属本局")
	_check(FileAccess.file_exists(SaveSlots.slot_path(1)), "位 1 文件确实落盘")

	# ---- 2) 上限与覆盖 ----
	_check(not SaveSlots.save_current(GameManager, 1), "占位默认拒绝覆盖（必须先删/确认）")
	_equals(int(SaveSlots.peek(1).get("wave", 0)), 5, "拒绝覆盖后位 1 内容未变")
	GameManager.wave_number = 6
	_check(SaveSlots.save_current(GameManager, 1, true), "allow_overwrite 可原子覆盖")
	_equals(int(SaveSlots.peek(1).get("wave", 0)), 6, "覆盖后摘要波次 6")
	GameManager.wave_number = 5

	# 填满 5 位：1~4 属 run-a，5 属 run-b
	for i in [2, 3, 4]:
		_check(SaveSlots.save_current(GameManager, i), "位 %d 可落盘" % i)
	GameManager.run_id = "run-b"
	_check(SaveSlots.save_current(GameManager, 5), "位 5 可落盘（另一局）")
	_equals(SaveSlots.count_used(), 5, "5 位全满")
	_equals(SaveSlots.first_free_slot(), -1, "全满时没有空位")

	# ---- 3) 位隔离与坏档 ----
	_check(SaveSlots.delete_slot(3), "删位 3 成功")
	_check(not SaveSlots.peek(3).get("occupied", false), "位 3 已空")
	_check(bool(SaveSlots.peek(1).get("occupied", false)), "删位 3 不动位 1")
	_check(bool(SaveSlots.peek(5).get("occupied", false)), "删位 3 不动位 5")

	_write_corrupt_slot(2)
	_check(bool(SaveSlots.peek(2).get("occupied", false)), "坏档位仍占位")
	_check(bool(SaveSlots.peek(2).get("corrupt", false)), "坏档位标 corrupt")
	_check(not bool(SaveSlots.peek(1).get("corrupt", false)), "坏档不影响位 1 摘要")
	GameManager.wave_number = 999
	_equals(SaveSlots.load_slot(GameManager, 2), -1, "读坏档返回 -1")
	_equals(GameManager.wave_number, 999, "读坏档失败不改 GameManager 字段")

	# ---- 4) roundtrip ----
	GameManager.run_id = "run-a"
	GameManager.wave_number = 8
	GameManager.level = 4
	_check(SaveSlots.save_current(GameManager, 4, true), "位 4 写入 roundtrip 快照（覆盖旧档）")
	GameManager.reset_run()
	_equals(SaveSlots.load_slot(GameManager, 4), WaveSpawner.Phase.FIGHT, "读位 4 返回 FIGHT")
	_equals(GameManager.wave_number, 8, "读回波次 8")
	_equals(GameManager.level, 4, "读回等级 4")
	_equals(GameManager.run_id, "run-a", "读回 run_id")
	RunSave.apply_player(GameManager)
	_check(not GameManager.player.get_equipped_weapons_data().is_empty(), "读回后武器重建")

	# ---- 5) 阵亡清档 ----
	var removed := SaveSlots.clear_run_slots("run-a")
	_equals(removed, 2, "clear_run_slots(run-a) 删掉位 1/4 两份")
	_check(not SaveSlots.peek(1).get("occupied", false), "位 1（run-a）已清")
	_check(not SaveSlots.peek(4).get("occupied", false), "位 4（run-a）已清")
	_check(bool(SaveSlots.peek(5).get("occupied", false)), "位 5（run-b）保留")
	_check(bool(SaveSlots.peek(2).get("occupied", false)), "坏档位保留（留给玩家手删）")

	# trigger_game_over 接线：本局 id 的档随阵亡清掉，别的局不动
	GameManager.run_id = "run-current"
	GameManager.cultivator_id = "fuzhen"
	GameManager.run_started = true
	GameManager.wave_number = 9
	_check(SaveSlots.save_current(GameManager, 1), "阵亡前本局档写回位 1")
	GameManager.author_mode = true   # 不写生涯/成就主档
	GameManager.trigger_game_over()
	GameManager.author_mode = false
	_check(not SaveSlots.peek(1).get("occupied", false), "阵亡后本局手动档已清")
	_check(bool(SaveSlots.peek(5).get("occupied", false)), "阵亡不动其他局的档")
	GameManager.reset_run()

	# ---- 6) 弹窗入口：存档模式选空位存入 / 满位删除并存入 ----
	SaveSlots.clear_all()
	GameManager.run_id = "run-ui"
	GameManager.run_started = true
	GameManager.cultivator_id = "fuzhen"
	GameManager.wave_number = 11
	GameManager.level = 5
	var dlg = _main._save_dialog
	_check(dlg != null, "Main 运行时挂上了存档管理弹窗")
	dlg.open_save()
	await get_tree().process_frame
	_equals(int(dlg._selected), 1, "存档模式默认选中第一个空位")
	dlg._on_primary_pressed()
	await get_tree().process_frame
	_check(bool(SaveSlots.peek(1).get("occupied", false)), "弹窗「存入」真的落盘位 1")
	_equals(int(SaveSlots.peek(1).get("wave", 0)), 11, "弹窗存入的快照波次 11")
	dlg.dismiss()

	# 用户现场：同一局玩到第 13 波，想覆盖刚存到第 1 波的档 —— 即便还有其他空位也必须允许
	GameManager.wave_number = 13
	dlg.open_save()
	await get_tree().process_frame
	_equals(int(dlg._selected), 2, "有空位时默认仍选第一个空位")
	dlg._on_slot_pressed(1)
	dlg._on_primary_pressed()   # 第一下：进入「再点确认覆盖」
	_equals(int(SaveSlots.peek(1).get("wave", 0)), 11, "覆盖确认前旧档内容不变")
	dlg._on_primary_pressed()   # 第二下：覆盖
	await get_tree().process_frame
	_equals(int(SaveSlots.peek(1).get("wave", 0)), 13, "选中已有存档可直接覆盖（第 13 波）")
	_check(not bool(SaveSlots.peek(2).get("occupied", false)), "覆盖位 1 不会顺手写位 2")
	dlg.dismiss()

	# 满 5 位：打开存档模式不默认选中，点旧档 → 二次确认覆盖
	for i in range(1, SaveSlots.SLOT_COUNT + 1):
		SaveSlots.save_current(GameManager, i, true)
	GameManager.wave_number = 14
	dlg.open_save()
	await get_tree().process_frame
	_equals(int(dlg._selected), -1, "满档时不默认选中（必须让玩家选覆盖哪个）")
	dlg._on_slot_pressed(1)
	dlg._on_primary_pressed()      # 第一下：进入「再点确认覆盖」
	dlg._on_primary_pressed()      # 第二下：覆盖
	await get_tree().process_frame
	_equals(int(SaveSlots.peek(1).get("wave", 0)), 14, "满位时选中旧档可直接覆盖位 1")
	dlg.dismiss()

	# 收尾
	SaveSlots.clear_all()
	SaveSlots.set_storage_dir_for_tests("")
	RunSave.clear_save()
	if _c.report("SAVESLOTS_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

## 模拟「全新场景开局」：与 run_save_check 同一套手法（测试复用同一个 Main 场景）
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
	GameManager.wave_number = 1

func _write_corrupt_slot(index: int) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "save_version", RunSave.SAVE_VERSION)
	cfg.set_value("meta", "wave", 0)
	cfg.set_value("run", "payload", {})
	cfg.save(SaveSlots.slot_path(index))

func _exit_tree() -> void:
	SaveSlots.clear_all()
	SaveSlots.set_storage_dir_for_tests("")
	RunSave.clear_save()