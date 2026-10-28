class_name SaveSlots
extends RefCounted

## 手动存档位（2026-10-28）：与自动中断档（RunSave / user://run_save.cfg）分离的
## 5 个玩家存档位，每位一个文件，写坏一位不影响其他位与生涯主档（同 RunSave 的域隔离理由）。
##
## 口径：
## - 落盘/读回完全复用 RunSave 的整包快照（存字段终值，绝不重放加点/道具）；
##   这里只管「位号 ↔ 文件路径/摘要」与 5 位上限。
## - 自动存档不占位：首页「继续游戏」仍走 RunSave.SAVE_PATH。
## - 阵亡清档只清本局：每个存档带 run_id，GameManager.trigger_game_over 调
##   clear_run_slots(run_id)，其他角色/其他局停在存档位里的进度不受影响。
## - 覆盖写入走 RunSave._atomic_save（同目录 .tmp → rename）：失败时旧档原样保留。

const SLOT_COUNT: int = 5
const SLOT_DIR := "user://save_slots"
const SLOT_FILE_FMT := "slot_%d.cfg"

## 判据隔离：测试把目录指到 user://test_save_slots，避免覆盖开发机真实存档
static var _dir_override: String = ""

static func set_storage_dir_for_tests(dir: String) -> void:
	_dir_override = dir

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

## 单个存档位的摘要：空位/坏档也返回条目（列表恒画 5 行）。
## occupied=文件在；corrupt=文件在但 meta/payload 解析不出；其余字段同 RunSave.peek_at。
static func peek(index: int) -> Dictionary:
	var entry := {
		"index": index,
		"occupied": false,
		"corrupt": false,
		"cname": "",
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

## 存当前局到指定位。allow_overwrite=false 时拒绝写已占位（正常流程由弹窗先删后存）；
## 满位「删除并存入」走 true —— 原子覆盖，写失败旧档仍在。
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

static func delete_slot(index: int) -> bool:
	if not valid_index(index):
		return false
	var path := slot_path(index)
	if not FileAccess.file_exists(path):
		return false
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return false
	return dir.remove(path.get_file()) == OK

static func load_slot(gm: Node, index: int) -> int:
	if not valid_index(index):
		return -1
	return RunSave.load_from(gm, slot_path(index))

## 阵亡清档：只删 run_id 相同的位（本局存下的），其他局的档保留。
## 返回删除数量，便于判据断言。
static func clear_run_slots(run_id: String) -> int:
	if run_id.is_empty():
		return 0
	var removed := 0
	for i in range(1, SLOT_COUNT + 1):
		var meta := RunSave.peek_at(slot_path(i))
		if meta.is_empty():
			continue
		if String(meta.get("run_id", "")) == run_id and delete_slot(i):
			removed += 1
	return removed

static func clear_all() -> void:
	for i in range(1, SLOT_COUNT + 1):
		delete_slot(i)