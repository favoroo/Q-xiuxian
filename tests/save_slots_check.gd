extends Node

## 多局存档位判据（2026-10-28；2026-11-02 一局一位重构）
##
## 用户口径：「一轮游戏只能有一个存档位；玩家存档后进度更新自动写回该位；
## 同一局不能产生第二个位；最多保留 5 局；阵亡删本局档；旧版同局多份快照合并，
## 只留进度最前的一份，旧快照不可读。」
##
## 覆盖：
## 1) 一局一位：首次 save_run 占第一个空位；再存仍同一位；进度变化由 active_save_path
##    路由回写；同 run 中断档被清，不会留两份。
## 2) 多局与上限：新 run 依次占 2..5；满 5 局后第 6 局 save_run 返回 -1 且不覆盖任何位。
## 3) 最近一局/旧快照：latest_save_path 合并中断档 + 5 位；同 run 只留进度最前；
##    旧快照 peek.loadable=false、load_slot 返回 -1。
## 4) 满位腾位 UI：MAKE_ROOM 二次确认替换，旧局位被本局原子覆盖。
## 5) 旧档迁移：同 run 多位只留最前；更前的中断档提升进存档位；坏档不动。
## 6) 阵亡/作废：invalidate_run_save 置落盘锁并删本局位，其他局保留；trigger_game_over 接线。
##
## 运行: python3 tools/run_test.py SaveSlotsCheck

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
	_clear_all_saves()
	_main = load("res://scenes/main/Main.tscn").instantiate()
	get_tree().root.add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame

	await _test_one_slot_per_run()
	await _test_multi_runs_and_full()
	await _test_latest_and_stale()
	await _test_make_room_ui()
	await _test_pause_save_ui()
	_test_migration()
	await _test_death_and_lock()

	# 收尾
	_clear_all_saves()
	SaveSlots.set_storage_dir_for_tests("")
	get_tree().paused = false
	if _c.report("SAVESLOTS_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

# ---------------- 1) 一局一位 + 自动跟进 ----------------

func _test_one_slot_per_run() -> void:
	_clear_all_saves()
	_fresh_start("fuzhen", "qingyun_sword")
	GameManager.run_id = "run-a"
	GameManager.wave_number = 5
	GameManager.level = 3

	_equals(SaveSlots.active_save_path(GameManager), RunSave.SAVE_PATH,
		"未占位时自动存档走临时中断档")
	var idx := SaveSlots.save_run(GameManager)
	_equals(idx, 1, "首次手动存档占第一个空位")
	_check(not FileAccess.file_exists(RunSave.SAVE_PATH), "占位后同局中断档被清，不留两份")
	_equals(SaveSlots.active_save_path(GameManager), SaveSlots.slot_path(1),
		"占位后自动存档路由到该位")
	var e1 := SaveSlots.peek(1)
	_equals(int(e1.get("wave", 0)), 5, "位 1 摘要波次 5")
	_equals(String(e1.get("run_id", "")), "run-a", "位 1 摘要 run_id 归属本局")

	# 进度推进：模拟自动存档按 active_save_path 回写（headless 下自动钩子不落盘）
	GameManager.wave_number = 6
	GameManager.level = 4
	_check(RunSave.save_to(GameManager, WaveSpawner.Phase.FIGHT,
		SaveSlots.active_save_path(GameManager)), "推进后按路由回写成功")
	_equals(int(SaveSlots.peek(1).get("wave", 0)), 6, "同一位跟随进度更新到第 6 波")

	var idx2 := SaveSlots.save_run(GameManager)
	_equals(idx2, 1, "同局再次存档仍写回原位")
	_check(not FileAccess.file_exists(SaveSlots.slot_path(2)), "同局不会顺手占第二位")

# ---------------- 2) 多局与 5 位上限 ----------------

func _test_multi_runs_and_full() -> void:
	_clear_all_saves()
	var expected := 1
	for i in range(1, 6):
		_fresh_start("fuzhen", "qingyun_sword")
		GameManager.run_id = "run-%d" % i
		GameManager.wave_number = 2 + i
		var idx := SaveSlots.save_run(GameManager)
		_equals(idx, expected, "第 %d 局占第 %d 位" % [i, expected])
		expected += 1
	_equals(SaveSlots.count_used(), 5, "5 局全部占满")
	_equals(SaveSlots.first_free_slot(), -1, "满位后没有空位")

	# 第 6 局：save_run 拒绝，且不覆盖任何旧局
	_fresh_start("fuzhen", "qingyun_sword")
	GameManager.run_id = "run-6"
	GameManager.wave_number = 99
	_equals(SaveSlots.save_run(GameManager), -1, "满位时第 6 局 save_run 返回 -1")
	_equals(int(SaveSlots.peek(1).get("wave", 0)), 3, "拒绝后位 1 内容未变")
	_equals(String(SaveSlots.peek(1).get("run_id", "")), "run-1", "位 1 仍是第 1 局")

# ---------------- 3) 最近一局 / 旧快照闸 ----------------

func _test_latest_and_stale() -> void:
	_clear_all_saves()
	var now := int(Time.get_unix_time_from_system())
	# 位 1/2：两局；位 3：run-a 的更前进度（同 run 多位，模拟旧版遗留）
	_write_slot_raw(1, "run-a", 5, 3, now)
	_write_slot_raw(2, "run-b", 3, 2, now + 10)
	_write_slot_raw(3, "run-a", 9, 6, now + 5)
	_write_interrupt_raw("run-c", 2, 1, now + 20)

	_equals(SaveSlots.latest_save_path(), RunSave.SAVE_PATH,
		"最近一局取最新落盘：中断档 run-c")
	_check(not SaveSlots.is_latest_for_run(1), "位 1 是 run-a 的旧快照")
	_check(SaveSlots.is_latest_for_run(3), "位 3 是 run-a 的最新进度")
	_check(not bool(SaveSlots.peek(1).get("loadable", true)), "旧快照标不可读")
	_check(bool(SaveSlots.peek(3).get("loadable", true)), "最新快照可读")

	GameManager.reset_run()
	_equals(SaveSlots.load_slot(GameManager, 1), -1, "旧快照 load_slot 返回 -1")
	_equals(SaveSlots.load_slot(GameManager, 3), WaveSpawner.Phase.FIGHT, "最新快照可读回")
	_equals(GameManager.wave_number, 9, "读回的是 run-a 第 9 波，不是第 5 波")

	# 中断档更前时，latest 选中断档；同 run 位 3 变成旧快照
	_write_interrupt_raw("run-a", 10, 7, now + 30)
	_equals(SaveSlots.latest_save_path(), RunSave.SAVE_PATH,
		"同 run 中断档更前时续中断档")
	_check(not SaveSlots.is_latest_for_run(3), "位 3 被更前的中断档压成旧快照")

# ---------------- 4) 满位腾位 UI ----------------

func _test_make_room_ui() -> void:
	_clear_all_saves()
	var now := int(Time.get_unix_time_from_system())
	for i in range(1, 6):
		_write_slot_raw(i, "run-old-%d" % i, 4 + i, 2, now + i)

	_fresh_start("fuzhen", "qingyun_sword")
	GameManager.run_id = "run-current"
	GameManager.wave_number = 12
	GameManager.level = 5

	var dlg = _main._save_dialog
	_check(dlg != null, "Main 运行时挂上了存档管理弹窗")
	dlg.open_make_room()
	await get_tree().process_frame
	_equals(int(dlg._selected), -1, "满位时不默认选中（必须让玩家选替换哪局）")

	dlg._on_slot_pressed(1)
	dlg._on_primary_pressed()   # 第一下：进入「再点确认替换」
	_equals(int(SaveSlots.peek(1).get("wave", 0)), 5, "替换确认前旧档内容不变")
	dlg._on_primary_pressed()   # 第二下：替换
	await get_tree().process_frame
	var e1 := SaveSlots.peek(1)
	_equals(String(e1.get("run_id", "")), "run-current", "位 1 已换成当前局")
	_equals(int(e1.get("wave", 0)), 12, "位 1 波次 = 当前局第 12 波")
	_check(not FileAccess.file_exists(RunSave.SAVE_PATH), "替换后当前局中断档被清")
	_equals(SaveSlots.find_slot_for_run("run-current"), 1, "当前局占位归属正确")
	dlg.dismiss()
	get_tree().paused = false

# ---------------- 4b) 暂停菜单存档接线 ----------------

func _test_pause_save_ui() -> void:
	_clear_all_saves()
	var pause = _main.get_node("UILayer/PauseMenu")

	# 正常路径：直接写本局唯一位，成功后暂停菜单保持打开
	_fresh_start("fuzhen", "qingyun_sword")
	GameManager.run_id = "run-pause"
	GameManager.wave_number = 5
	pause.open()
	pause._on_save_pressed()
	await get_tree().process_frame
	_equals(SaveSlots.find_slot_for_run("run-pause"), 1, "暂停菜单直接存档写入位 1")
	_check(pause.visible, "存档成功后暂停菜单保持打开")
	# 直接收起（不走 close 动画），避免下一段 open 撞上未完成的关闭 Tween
	pause._kill_close_tween()
	pause.visible = false
	pause._closing = false
	get_tree().paused = false

	# 满位且本局未占位：暂停菜单藏起，Main 打开 MAKE_ROOM 腾位弹窗
	for i in range(2, 6):
		_fresh_start("fuzhen", "qingyun_sword")
		GameManager.run_id = "run-p%d" % i
		GameManager.wave_number = i
		_equals(SaveSlots.save_run(GameManager), i, "准备满位：第 %d 位" % i)
	_fresh_start("fuzhen", "qingyun_sword")
	GameManager.run_id = "run-pfull"
	GameManager.wave_number = 9
	pause.open()
	pause._on_save_pressed()
	await get_tree().process_frame
	_check(not pause.visible, "满位时暂停菜单让位给腾位弹窗")
	var dlg = _main._save_dialog
	_check(dlg != null and dlg.visible, "Main 打开 MAKE_ROOM 腾位弹窗")
	_equals(int(dlg._mode), SaveManageDialog.Mode.MAKE_ROOM, "弹窗处于 MAKE_ROOM 模式")
	dlg.dismiss()
	_main._save_return_to_pause = false
	get_tree().paused = false

# ---------------- 5) 旧档迁移 ----------------

func _test_migration() -> void:
	_clear_all_saves()
	SaveSlots.set_storage_dir_for_tests(TEST_DIR)  # 重置 _migrated，允许本段单独跑迁移
	var now := int(Time.get_unix_time_from_system())
	_write_slot_raw(1, "run-a", 5, 3, now)
	_write_slot_raw(2, "run-a", 9, 6, now + 5)
	_write_slot_raw(3, "run-b", 3, 2, now + 10)
	_write_corrupt_slot(4)
	_write_interrupt_raw("run-a", 10, 7, now + 20)

	var removed := SaveSlots.migrate_legacy_once()
	_check(removed > 0, "迁移清理了同局重复/旧中断档（removed=%d）" % removed)
	_equals(int(SaveSlots.peek(2).get("wave", 0)), 10, "更前的中断档被提升进位 2（第 10 波）")
	_check(not bool(SaveSlots.peek(1).get("occupied", false)), "同 run 旧位 1 已删")
	_equals(String(SaveSlots.peek(3).get("run_id", "")), "run-b", "别局位 3 保留")
	_check(bool(SaveSlots.peek(4).get("corrupt", false)), "坏档位保留（留给玩家手删）")
	_check(not FileAccess.file_exists(RunSave.SAVE_PATH), "迁移后旧中断档已清")
	_equals(SaveSlots.migrate_legacy_once(), 0, "迁移每进程只跑一次")

# ---------------- 6) 阵亡 / 作废锁 ----------------

func _test_death_and_lock() -> void:
	_clear_all_saves()
	# A) 直接作废：落盘锁 + 本局位删除，别局不动
	_fresh_start("fuzhen", "qingyun_sword")
	GameManager.run_id = "run-lock"
	GameManager.wave_number = 4
	_equals(SaveSlots.save_run(GameManager), 1, "作废锁测试局占位 1")
	_fresh_start("fuzhen", "qingyun_sword")
	GameManager.run_id = "run-alive"
	GameManager.wave_number = 3
	_equals(SaveSlots.save_run(GameManager), 2, "别局占位 2")

	GameManager.run_id = "run-lock"
	GameManager.invalidate_run_save()
	_check(GameManager.run_invalidated, "致死判定后 run_invalidated 置真")
	_check(not bool(SaveSlots.peek(1).get("occupied", false)), "作废后本局位立刻删除")
	_check(bool(SaveSlots.peek(2).get("occupied", false)), "作废不动别局位")
	_check(not RunSave.save_from(GameManager, WaveSpawner.Phase.FIGHT),
		"作废锁拒绝任何落盘（死亡演出期间强退也保不住档）")
	GameManager.reset_run()
	_check(not GameManager.run_invalidated, "reset_run 复位作废锁")

	# B) trigger_game_over 接线：只清本局，别局保留
	_clear_all_saves()
	_fresh_start("fuzhen", "qingyun_sword")
	GameManager.run_id = "run-dead2"
	GameManager.wave_number = 8
	_equals(SaveSlots.save_run(GameManager), 1, "阵亡局占位 1")
	_fresh_start("fuzhen", "qingyun_sword")
	GameManager.run_id = "run-alive2"
	GameManager.wave_number = 3
	_equals(SaveSlots.save_run(GameManager), 2, "别局占位 2")

	GameManager.run_id = "run-dead2"
	GameManager.wave_number = 8
	GameManager.author_mode = true  # 不写生涯/成就主档
	GameManager.trigger_game_over()
	GameManager.author_mode = false
	_check(not bool(SaveSlots.peek(1).get("occupied", false)), "trigger_game_over 删本局位")
	_check(bool(SaveSlots.peek(2).get("occupied", false)), "trigger_game_over 不动别局位")
	_equals(String(SaveSlots.peek(2).get("run_id", "")), "run-alive2", "别局 run-alive2 仍在")
	GameManager.reset_run()
	get_tree().paused = false

# ---------------- 工具 ----------------

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

func _clear_all_saves() -> void:
	SaveSlots.clear_all()
	RunSave.clear_save()

func _write_slot_raw(index: int, rid: String, wave: int, level: int, ts: int,
		cid: String = "fuzhen") -> bool:
	if not SaveSlots.valid_index(index):
		return false
	DirAccess.make_dir_recursive_absolute(SaveSlots.storage_dir())
	var cfg := _make_raw_cfg(rid, wave, level, ts, cid)
	return cfg.save(SaveSlots.slot_path(index)) == OK

func _write_interrupt_raw(rid: String, wave: int, level: int, ts: int,
		cid: String = "fuzhen") -> bool:
	var cfg := _make_raw_cfg(rid, wave, level, ts, cid)
	return cfg.save(RunSave.SAVE_PATH) == OK

## 裸档也必须过 RunSave.peek_at/load_from 的校验：角色存在 + 至少一把武器
func _make_raw_cfg(rid: String, wave: int, level: int, ts: int, cid: String) -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "save_version", RunSave.SAVE_VERSION)
	cfg.set_value("meta", "app_version", "test")
	cfg.set_value("meta", "time_unix", ts)
	cfg.set_value("meta", "wave", wave)
	cfg.set_value("meta", "level", level)
	cfg.set_value("meta", "cid", cid)
	cfg.set_value("meta", "danger", 0)
	cfg.set_value("meta", "play_time", float(wave * 10))
	cfg.set_value("meta", "run_id", rid)
	cfg.set_value("run", "payload", {
		"wave_number": wave,
		"run_id": rid,
		"cultivator_id": cid,
		"weapons": [{"id": "qingyun_sword", "star": 1}],
		"run_started": true,
		"level": level,
		"danger_level": 0,
		"game_time": float(wave * 10),
		"phase": WaveSpawner.Phase.FIGHT,
	})
	return cfg

func _write_corrupt_slot(index: int) -> void:
	DirAccess.make_dir_recursive_absolute(SaveSlots.storage_dir())
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "save_version", RunSave.SAVE_VERSION)
	cfg.set_value("meta", "wave", 0)
	cfg.set_value("run", "payload", {})
	cfg.save(SaveSlots.slot_path(index))

func _exit_tree() -> void:
	SaveSlots.clear_all()
	SaveSlots.set_storage_dir_for_tests("")
	RunSave.clear_save()