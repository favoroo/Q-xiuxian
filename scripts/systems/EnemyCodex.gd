class_name EnemyCodex
extends RefCounted

## 敌人图鉴「见过」登记：玩家在某局里遭遇过的敌种，永久进图鉴。
## 口径 = 刷出过（出生预警亮起那一刻），不是击杀过 —— 金蟾这类追不上的怪也必须收得到。
##
## 为什么单开 user://codex.cfg 而不并进 progress.cfg：
## 后者整读整写、字段清单由 ProgressStore 维护，敌人计数属图鉴域，独立文件让
## 「图鉴埋点丢一拍不影响元进度主档」，也避免动 GameManager 热区字段表。
## 「见过」单调递增（只加不减），半写坏档可容忍：读不回退即可，丢一两局记录无伤大雅。

const CODEX_PATH := "user://codex.cfg"
const KEY_SEEN := "seen_enemies"

static var _seen: Array[String] = []
static var _loaded: bool = false

static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(CODEX_PATH) == OK:
		# ConfigFile 存 PackedStringArray 读回来还是 PackedStringArray，is Array 为假 ——
		# Array(raw) 对两种都成立，别拿 `is Array` 当闸（踩过：老写法读回空档，重启图鉴全丢）
		var raw = cfg.get_value("codex", KEY_SEEN, [])
		for e in Array(raw):
			var s := String(e)
			if not s.is_empty() and not (s in _seen):
				_seen.append(s)

## 刷怪出口埋点：先 ensure_loaded 再查 —— 没查就 append 会把同一敌种重复写进档。
static func record_seen(eid: String) -> void:
	if eid.is_empty():
		return
	ensure_loaded()
	if eid in _seen:
		return
	_seen.append(eid)
	var cfg := ConfigFile.new()
	cfg.set_value("codex", KEY_SEEN, PackedStringArray(_seen))
	var err := cfg.save(CODEX_PATH)
	if err != OK:
		push_warning("EnemyCodex: 图鉴存档写入失败 err=%d（不影响战斗，仅图鉴可能少记一种）" % err)

static func is_seen(eid: String) -> bool:
	ensure_loaded()
	return eid in _seen

## 图鉴进度读数「收录 n/m」的 n：只数仍在表里的 id（改表删种时不虚报）
static func seen_count_in(catalog: Array) -> int:
	ensure_loaded()
	var n := 0
	for eid in catalog:
		if String(eid) in _seen:
			n += 1
	return n

## 判据/预览工具用：清空登记（headless 测试隔离，避免上一次运行残留）
static func reset_for_test() -> void:
	ensure_loaded()
	_seen.clear()
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists(CODEX_PATH):
		dir.remove(CODEX_PATH)
