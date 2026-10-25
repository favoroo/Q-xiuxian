class_name CodexCollection
extends RefCounted

## 武器/道具/悟道图鉴的「实战收录」登记（2026-10-25 锁图鉴：一步步给信息）。
## 口径 = 局内真的见过一次（买下武器、拿到道具、悟道卡进过候选池），不是解锁过。
## 与 EnemyCodex 同一套设计：
##   · 独立存档 user://codex_collection.cfg —— 图鉴埋点丢一拍不影响局外元进度主档，
##     也不去动 progress.cfg 的字段表（那张表归 ProgressStore 维护）；
##   · 单调递增（只加不减），半写坏档可容忍：读不回退即可，丢一两局记录无伤大雅；
##   · 为什么另开文件而不复用 codex.cfg：EnemyCodex 整读整写自己的文件，
##     两个类共写同一个文件会互相覆盖对方刚写的键。
##
## 未收录的条目在图鉴里只显示名字与剪影，不剧透数值与词条 —— 想看清就得先在局内用一次。

const CODEX_PATH := "user://codex_collection.cfg"
const KEY_WEAPONS := "seen_weapons"
const KEY_ITEMS := "seen_items"
const KEY_UPGRADES := "seen_upgrades"

static var _weapons: Array[String] = []
static var _items: Array[String] = []
static var _upgrades: Array[String] = []
static var _loaded: bool = false

static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(CODEX_PATH) != OK:
		return
	_weapons = _read_list(cfg, KEY_WEAPONS)
	_items = _read_list(cfg, KEY_ITEMS)
	_upgrades = _read_list(cfg, KEY_UPGRADES)

## ConfigFile 存 PackedStringArray 读回来还是 PackedStringArray，is Array 为假 ——
## 用 Array(raw) 统一两种类型（EnemyCodex 踩过：拿 `is Array` 当闸会读回空档）。
static func _read_list(cfg: ConfigFile, key: String) -> Array[String]:
	var out: Array[String] = []
	var raw = cfg.get_value("codex", key, [])
	for e in Array(raw):
		var s := String(e)
		if not s.is_empty() and not (s in out):
			out.append(s)
	return out

static func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("codex", KEY_WEAPONS, PackedStringArray(_weapons))
	cfg.set_value("codex", KEY_ITEMS, PackedStringArray(_items))
	cfg.set_value("codex", KEY_UPGRADES, PackedStringArray(_upgrades))
	var err := cfg.save(CODEX_PATH)
	if err != OK:
		push_warning("CodexCollection: 图鉴存档写入失败 err=%d（不影响战斗，仅图鉴可能少记一条）" % err)

static func record_weapon(wid: String) -> void:
	if wid.is_empty():
		return
	ensure_loaded()
	if wid in _weapons:
		return
	_weapons.append(wid)
	_save()

static func record_item(iid: String) -> void:
	if iid.is_empty():
		return
	ensure_loaded()
	if iid in _items:
		return
	_items.append(iid)
	_save()

static func record_upgrade(uid: String) -> void:
	if uid.is_empty():
		return
	ensure_loaded()
	if uid in _upgrades:
		return
	_upgrades.append(uid)
	_save()

static func is_weapon_seen(wid: String) -> bool:
	ensure_loaded()
	return wid in _weapons

static func is_item_seen(iid: String) -> bool:
	ensure_loaded()
	return iid in _items

static func is_upgrade_seen(uid: String) -> bool:
	ensure_loaded()
	return uid in _upgrades

## 图鉴页头「已收录 n/m」的分子：只数仍在表里的 id（改表删件时不虚报）
static func weapon_seen_count() -> int:
	ensure_loaded()
	var n := 0
	for wid in WeaponData.DEFS.keys():
		if String(wid) in _weapons:
			n += 1
	return n

static func item_seen_count() -> int:
	ensure_loaded()
	var n := 0
	for iid in ItemData.shop_ids():
		if String(iid) in _items:
			n += 1
	return n

## 判据/预览工具用：清空登记（headless 测试隔离，避免上一次运行残留）
static func reset_for_test() -> void:
	_loaded = true
	_weapons.clear()
	_items.clear()
	_upgrades.clear()
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists(CODEX_PATH):
		dir.remove(CODEX_PATH)
