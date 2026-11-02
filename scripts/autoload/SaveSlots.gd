class_name SaveSlots
extends RefCounted

## 多局存档位（2026-10-28；2026-11-02 一局一位重构）
## 5 个固定存档位，每位只承载「一局」的实时状态，不再保存同一局的历史快照：
## - 未占位的局只有 RunSave.SAVE_PATH 临时中断档；玩家在暂停菜单按「存档」才占位。
## - 占位后本局自动存档改写到该位（SaveSlots.autosave_current），进度更新即更新该位；
##   同一 run_id 永远只允许占一个位，想存第二个位会被拒绝。
## - 最多同时保留 5 局；满位时 UI 走「删一局并存入本局」的 MAKE_ROOM 流程。
## - 阵亡由 GameManager.invalidate_run_save 调 clear_run_slots(run_id)：删本局所有位 +
##   中断档，其他局的位不受影响。
## - 旧版同一局多位的快照由 migrate_legacy_once() 一次性合并，只保留进度最前的一份；
##   is_latest_for_run/load_slot 再兜一层，迁移失败也读不到旧快照。
## - 覆盖写入走 RunSave._atomic_save（同目录 .tmp → rename）：失败时旧档原样保留。
## - 落盘/读回完全复用 RunSave 的整包快照（存字段终值，绝不重放加点/道具）；这里只管
##   「run_id ↔ 位号/文件路径」与 5 位上限。

const SLOT_COUNT: int = 5
const SLOT_DIR := "user://save_slots"
const SLOT_FILE_FMT := "slot_%d.cfg"

## 判据隔离：测试把目录指到 user://test_*，避免覆盖开发机真实存档
static var _dir_override: String = ""
## 旧档合并每进程只跑一次；判据切目录时重置，便于单独验证迁移
static var _migrated: bool = false

static func set_storage_dir_for_tests(dir: String) -> void:
	_dir_override = dir
	_migrated = false

static func storage_dir() -> String:
	return _dir_override if not _dir_override.is_empty() else SLOT_DIR

static func slot_path(index: int) -> String:
	return storage_dir().path_join(SLOT_FILE_FMT % index)

static func valid_index(index: int) -> bool:
	return index >= 1 and index <= SLOT_COUNT

static func _ensure_dir() -> bool:
	var dir_path := storage_dir()
	if DirAccess.dir_exists_absolute(dir_path):
		return true
	return DirAccess.make_dir_recursive_absolute(dir_path) == OK

# ---------------- 摘要 / 列表 ----------------

## 单个存档位的摘要：空位/坏档也返回条目（列表恒画 5 行）。
## occupied=文件在；corrupt=文件在但 payload 校验不过；loadable=该位是本局最新进度
## （同一局若还有更新的一份，旧位只可删不可读）。
static func peek(index: int) -> Dictionary:
	var entry := {
		"index": index,
		"occupied": false,
		"corrupt": false,
		"cname": "",
		"loadable": false,
	}
	if not valid_index(index):
		return entry
	var path := slot_path(index)
	entry["occupied"] = FileAccess.file_exists(path)
	if not bool(entry["occupied"]):
		return entry
	var meta := RunSave.peek_at(path)
	if meta.is_empty():
		entry["corrupt"] = true
		return entry
	entry.merge(meta, true)
	entry["loadable"] = is_latest_for_run(index)
	var cid := String(entry.get("cid", ""))
	entry["cname"] = String(CultivatorData.get_def(cid).get("name", "修士"))
	return entry

static func list_slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(1, SLOT_COUNT + 1):
		out.append(peek(i))
	return out

## 已占位数（坏档也占位：必须删掉才能再存）
static func count_used() -> int:
	var n := 0
	for i in range(1, SLOT_COUNT + 1):
		if FileAccess.file_exists(slot_path(i)):
			n += 1
	return n

static func first_free_slot() -> int:
	for i in range(1, SLOT_COUNT + 1):
		if not FileAccess.file_exists(slot_path(i)):
			return i
	return -1

## 是否存在任意存档文件（含中断档/坏档）：首页坏档提示用。
static func has_any_save_file() -> bool:
	if FileAccess.file_exists(RunSave.SAVE_PATH):
		return true
	for i in range(1, SLOT_COUNT + 1):
		if FileAccess.file_exists(slot_path(i)):
			return true
	return false

# ---------------- run_id ↔ 位号 ----------------

## 本局已有的有效位；同一 run 多位时取进度最前（wave→level→time）。
## 有效位一个都没有时，才退回坏档 meta 认领（save_run 原地修复），
## 绝不让坏档的高 meta 抢掉好档。
static func find_slot_for_run(run_id: String) -> int:
	if run_id.is_empty():
		return -1
	var best := -1
	var best_meta := {}
	for i in range(1, SLOT_COUNT + 1):
		var meta := RunSave.peek_at(slot_path(i))
		if meta.is_empty() or String(meta.get("run_id", "")) != run_id:
			continue
		if best < 0 or _is_better_meta(meta, best_meta):
			best = i
			best_meta = meta
	if best > 0:
		return best
	for i in range(1, SLOT_COUNT + 1):
		var meta := RunSave.peek_meta_at(slot_path(i))
		if not meta.is_empty() and String(meta.get("run_id", "")) == run_id:
			return i
	return -1

## 自动存档目标：已占位写位，未占位写临时中断档。
static func active_save_path(gm: Node) -> String:
	var idx := find_slot_for_run(String(gm.run_id))
	return slot_path(idx) if idx > 0 else RunSave.SAVE_PATH

## 本局自动存档统一入口（生产 6 处钩子都走它）。已占位写位成功后就清同 run 中断档，
## 避免同一局留两份；未占位只写中断档。
static func autosave_current(gm: Node) -> void:
	if not RunSave.autosave_allowed(gm):
		return
	var target := active_save_path(gm)
	if target != RunSave.SAVE_PATH and not _ensure_dir():
		push_warning("SaveSlots: 无法创建存档目录 %s" % storage_dir())
		return
	if not RunSave.autosave_to_path(gm, target):
		return
	if target != RunSave.SAVE_PATH:
		_drop_interrupt_for_run(String(gm.run_id))

# ---------------- 写入 ----------------

## 玩家手动存档：本局已有位原地更新；无位取第一个空位；满位返回 -1（UI 转 MAKE_ROOM）。
static func save_run(gm: Node) -> int:
	var rid := RunSave.ensure_run_id(gm)
	if rid.is_empty():
		return -1
	var idx := find_slot_for_run(rid)
	if idx < 0:
		idx = first_free_slot()
		if idx < 0:
			return -1
	if not _write_run_to_slot(gm, idx):
		return -1
	_drop_interrupt_for_run(rid)
	return idx

## 满位腾位弹窗：把本局写进指定位（允许覆盖别局）。
## 同一局已在别位则拒绝 —— 一局一位是硬约束。
static func save_run_to_slot(gm: Node, index: int) -> bool:
	if not valid_index(index):
		return false
	var rid := RunSave.ensure_run_id(gm)
	if rid.is_empty():
		return false
	var existing := find_slot_for_run(rid)
	if existing > 0 and existing != index:
		push_warning("SaveSlots: 本局已占位 %d，拒绝再写位 %d（一局一位）" % [existing, index])
		return false
	var old_valid := RunSave.peek_at(slot_path(index))
	var old_meta := old_valid if not old_valid.is_empty() else RunSave.peek_meta_at(slot_path(index))
	if not _write_run_to_slot(gm, index):
		return false
	var old_rid := String(old_meta.get("run_id", ""))
	if not old_rid.is_empty() and old_rid != rid:
		# 被替换局若还有一份更前/唯一可读的中断档，保留它（别把更新进度一起删掉）
		_drop_interrupt_if_not_better(old_rid, old_valid, not old_valid.is_empty())
	_drop_interrupt_for_run(rid)
	return true

## 判据造档底层入口：不做一局一位约束、不动中断档。
## 生产写入走 save_run / save_run_to_slot。
static func save_current(gm: Node, index: int, allow_overwrite: bool = false) -> bool:
	if not valid_index(index):
		return false
	var path := slot_path(index)
	if FileAccess.file_exists(path) and not allow_overwrite:
		push_warning("SaveSlots: 存档位 %d 已有存档，拒绝未确认的覆盖" % index)
		return false
	if not _ensure_dir():
		push_warning("SaveSlots: 无法创建存档目录 %s" % storage_dir())
		return false
	return RunSave.save_to(gm, RunSave.resolve_phase(gm), path)

static func _write_run_to_slot(gm: Node, index: int) -> bool:
	if not valid_index(index):
		return false
	if not _ensure_dir():
		push_warning("SaveSlots: 无法创建存档目录 %s" % storage_dir())
		return false
	return RunSave.save_to(gm, RunSave.resolve_phase(gm), slot_path(index))

# ---------------- 删除 / 清档 ----------------

static func delete_slot(index: int) -> bool:
	if not valid_index(index):
		return false
	var valid_meta := RunSave.peek_at(slot_path(index))
	var meta := valid_meta if not valid_meta.is_empty() else RunSave.peek_meta_at(slot_path(index))
	if not _delete_slot_file(index):
		return false
	var rid := String(meta.get("run_id", ""))
	if not rid.is_empty():
		_drop_interrupt_if_not_better(rid, valid_meta, not valid_meta.is_empty())
	return true

## 阵亡清档：删本局所有位，并无条件清本局中断档（本局已终结，绝不留可续状态）。
## 返回删除的位数，便于判据断言。
static func clear_run_slots(run_id: String) -> int:
	if run_id.is_empty():
		return 0
	var removed := 0
	for i in range(1, SLOT_COUNT + 1):
		var meta := _slot_meta(i)
		if meta.is_empty():
			continue
		if String(meta.get("run_id", "")) == run_id and _delete_slot_file(i):
			removed += 1
	_drop_interrupt_for_run(run_id)
	return removed

static func clear_all() -> void:
	for i in range(1, SLOT_COUNT + 1):
		_delete_slot_file(i)

static func _delete_slot_file(index: int) -> bool:
	if not valid_index(index):
		return false
	var path := slot_path(index)
	if not FileAccess.file_exists(path):
		return false
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return false
	return dir.remove(path.get_file()) == OK

## 位内容：优先有效档，坏档才退回 meta（与 find_slot_for_run 同口径）。
static func _slot_meta(index: int) -> Dictionary:
	if not valid_index(index):
		return {}
	var meta := RunSave.peek_at(slot_path(index))
	if not meta.is_empty():
		return meta
	return RunSave.peek_meta_at(slot_path(index))

# ---------------- 读档 ----------------

static func load_slot(gm: Node, index: int) -> int:
	if not valid_index(index):
		return -1
	if not is_latest_for_run(index):
		push_warning("SaveSlots: 位 %d 不是本局最新进度，拒绝读档（旧快照只能删）" % index)
		return -1
	return RunSave.load_from(gm, slot_path(index))

## 该位是否为本 run 的最新进度：同 run 的中断档/其他位若有更前的快照，返回 false。
## 这是迁移失败时的兜底闸：旧快照不可读，只能删。
static func is_latest_for_run(index: int) -> bool:
	if not valid_index(index):
		return false
	var meta := RunSave.peek_at(slot_path(index))
	if meta.is_empty():
		return false
	var rid := String(meta.get("run_id", ""))
	if rid.is_empty():
		return true  # 旧档无归属，无法比较，按唯一档放行
	var best := meta
	var interrupt := RunSave.peek_at(RunSave.SAVE_PATH)
	if not interrupt.is_empty() and String(interrupt.get("run_id", "")) == rid \
			and _is_better_meta(interrupt, best):
		best = interrupt
	for i in range(1, SLOT_COUNT + 1):
		if i == index:
			continue
		var other := RunSave.peek_at(slot_path(i))
		if other.is_empty() or String(other.get("run_id", "")) != rid:
			continue
		if _is_better_meta(other, best):
			best = other
	return best == meta

# ---------------- 最近一局 / 迁移 ----------------

## 首页「继续游戏」的目标：SAVE_PATH + 5 位合并；同一局只留进度最前一份，
## 跨局取 time_unix 最新。只认有效档，坏档跳过。
static func latest_save_path() -> String:
	var candidates: Array[Dictionary] = []
	var interrupt := RunSave.peek_at(RunSave.SAVE_PATH)
	if not interrupt.is_empty():
		candidates.append({"path": RunSave.SAVE_PATH, "meta": interrupt})
	for i in range(1, SLOT_COUNT + 1):
		var p := slot_path(i)
		var meta := RunSave.peek_at(p)
		if not meta.is_empty():
			candidates.append({"path": p, "meta": meta})
	if candidates.is_empty():
		return ""
	var by_run: Dictionary = {}
	var runless: Array[Dictionary] = []
	for c in candidates:
		var meta: Dictionary = c["meta"]
		var rid := String(meta.get("run_id", ""))
		if rid.is_empty():
			runless.append(c)
			continue
		if not by_run.has(rid):
			by_run[rid] = c
			continue
		var cur: Dictionary = by_run[rid]
		var cur_meta: Dictionary = cur["meta"]
		if _is_better_meta(meta, cur_meta):
			by_run[rid] = c
	var final_list: Array[Dictionary] = []
	for c in by_run.values():
		if c is Dictionary:
			final_list.append(c)
	final_list.append_array(runless)
	var best: Dictionary = {}
	var best_ts := -1
	for c in final_list:
		var meta: Dictionary = c["meta"]
		var ts := int(meta.get("time_unix", 0))
		if ts > best_ts:
			best_ts = ts
			best = c
	return String(best.get("path", ""))

static func latest_save_summary() -> Dictionary:
	var path := latest_save_path()
	if path.is_empty():
		return {}
	var summary := RunSave.peek_at(path)
	if summary.is_empty():
		return {}
	summary["path"] = path
	return summary

## 旧版迁移（只跑一次）：同一 run 多位只留进度最前；SAVE_PATH 若更前则提升进该局位。
## 返回清理/合并的文件数，首页用来提示一次。
static func migrate_legacy_once() -> int:
	if _migrated:
		return 0
	_migrated = true
	var removed := 0
	# 1) 每个 run 的有效位里挑进度最前的一份
	var best_by_run: Dictionary = {}
	for i in range(1, SLOT_COUNT + 1):
		var meta := RunSave.peek_at(slot_path(i))
		if meta.is_empty():
			continue
		var rid := String(meta.get("run_id", ""))
		if rid.is_empty():
			continue  # 旧档无归属，不参与合并
		if not best_by_run.has(rid):
			best_by_run[rid] = {"index": i, "meta": meta}
			continue
		var cur: Dictionary = best_by_run[rid]
		var cur_meta: Dictionary = cur["meta"]
		if _is_better_meta(meta, cur_meta):
			best_by_run[rid] = {"index": i, "meta": meta}
	# 2) 中断档与同位冲突：更前的提升进存档位，较差的直接删
	var interrupt := RunSave.peek_at(RunSave.SAVE_PATH)
	if not interrupt.is_empty():
		var rid := String(interrupt.get("run_id", ""))
		if not rid.is_empty() and best_by_run.has(rid):
			var best: Dictionary = best_by_run[rid]
			var best_meta: Dictionary = best["meta"]
			if _is_better_meta(interrupt, best_meta):
				if _ensure_dir() and RunSave.copy_save(RunSave.SAVE_PATH, slot_path(int(best["index"]))):
					best["meta"] = interrupt
					RunSave.clear_save()
					removed += 1
			else:
				RunSave.clear_save()
				removed += 1
	# 3) 删掉同 run 的旧位（只留 best_by_run）
	for i in range(1, SLOT_COUNT + 1):
		var meta := RunSave.peek_at(slot_path(i))
		if meta.is_empty():
			continue
		var rid := String(meta.get("run_id", ""))
		if rid.is_empty() or not best_by_run.has(rid):
			continue
		var best: Dictionary = best_by_run[rid]
		if int(best["index"]) != i and _delete_slot_file(i):
			removed += 1
	return removed

# ---------------- 中断档清理 / 进度比较 ----------------

## 无条件清同 run 的中断档：调用方刚把当前进度写进存档位，中断档只会是旧副本。
static func _drop_interrupt_for_run(run_id: String) -> void:
	if run_id.is_empty():
		return
	var meta := RunSave.peek_meta_at(RunSave.SAVE_PATH)
	if not meta.is_empty() and String(meta.get("run_id", "")) == run_id:
		RunSave.clear_save()

## 删位/替换旧局时用：中断档若比该位更前，或该位本身是坏档/空位，保留可读的中断档。
## 坏中断档本身跑不起来，直接删掉。
static func _drop_interrupt_if_not_better(run_id: String, slot_valid_meta: Dictionary,
		slot_had_valid: bool) -> void:
	if run_id.is_empty():
		return
	var meta := RunSave.peek_meta_at(RunSave.SAVE_PATH)
	if meta.is_empty() or String(meta.get("run_id", "")) != run_id:
		return
	var valid := RunSave.peek_at(RunSave.SAVE_PATH)
	if valid.is_empty():
		RunSave.clear_save()
		return
	if not slot_had_valid:
		return  # 旧位是坏档：中断档是这局唯一能跑的状态，别删
	if _is_better_meta(valid, slot_valid_meta):
		return
	RunSave.clear_save()

## 同一局两份快照的“进度更前”判定：波次优先，其次等级，最后落盘时间。
static func _is_better_meta(a: Dictionary, b: Dictionary) -> bool:
	var wa := int(a.get("wave", 0))
	var wb := int(b.get("wave", 0))
	if wa != wb:
		return wa > wb
	var la := int(a.get("level", 1))
	var lb := int(b.get("level", 1))
	if la != lb:
		return la > lb
	return int(a.get("time_unix", 0)) > int(b.get("time_unix", 0))