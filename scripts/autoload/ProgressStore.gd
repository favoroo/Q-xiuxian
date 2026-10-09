class_name ProgressStore
extends RefCounted

## 局外元进度存档与成就结算子系统
## 负责 user://progress.cfg 的读写、save_version 向前兼容、生涯统计累加、战报记录与成就解锁判定。

const PROGRESS_PATH := "user://progress.cfg"
const SAVE_VERSION: int = 1
const MAX_HISTORY_ENTRIES: int = 10

static func load_into(gm: Node) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PROGRESS_PATH) == OK:
		var _ver := int(cfg.get_value("meta", "save_version", 1))
		gm.max_danger_unlocked = clampi(int(cfg.get_value("progress", "max_danger", 0)), 0, GameBalance.DANGER_MAX)

		var cults = cfg.get_value("progress", "unlocked_cultivators", [])
		if cults is Array and not cults.is_empty():
			gm.unlocked_cultivators = cults.duplicate()
		else:
			gm.unlocked_cultivators = AchievementData.DEFAULT_CULTIVATORS.duplicate()

		var itms = cfg.get_value("progress", "unlocked_items", [])
		if itms is Array and not itms.is_empty():
			gm.unlocked_items = itms.duplicate()
		else:
			gm.unlocked_items = AchievementData.DEFAULT_ITEMS.duplicate()

		var achs = cfg.get_value("progress", "unlocked_achievements", [])
		gm.unlocked_achievements = achs.duplicate() if achs is Array else []

		gm.career_stats["total_runs"] = int(cfg.get_value("stats", "total_runs", 0))
		gm.career_stats["total_wins"] = int(cfg.get_value("stats", "total_wins", 0))
		gm.career_stats["total_kills"] = int(cfg.get_value("stats", "total_kills", 0))
		gm.career_stats["best_wave"] = int(cfg.get_value("stats", "best_wave", 0))
		gm.career_stats["best_kills"] = int(cfg.get_value("stats", "best_kills", 0))
		gm.career_stats["total_stones"] = int(cfg.get_value("stats", "total_stones", 0))
		gm.career_stats["total_time"] = float(cfg.get_value("stats", "total_time", 0.0))

		var cbd = cfg.get_value("records", "cultivator_best_danger", {})
		gm.cultivator_best_danger = cbd.duplicate() if cbd is Dictionary else {}

		var hist = cfg.get_value("history", "recent_runs", [])
		gm.run_history = hist.duplicate() if hist is Array else []
	else:
		gm.unlocked_cultivators = AchievementData.DEFAULT_CULTIVATORS.duplicate()
		gm.unlocked_items = AchievementData.DEFAULT_ITEMS.duplicate()
		gm.unlocked_achievements = []
		gm.cultivator_best_danger = {}
		gm.run_history = []

	# 确保初始集合必在（防止旧档或异常数据丢失基础内容）
	for cid in AchievementData.DEFAULT_CULTIVATORS:
		if not (cid in gm.unlocked_cultivators):
			gm.unlocked_cultivators.append(cid)
	for iid in AchievementData.DEFAULT_ITEMS:
		if not (iid in gm.unlocked_items):
			gm.unlocked_items.append(iid)

static func save_from(gm: Node) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "save_version", SAVE_VERSION)
	cfg.set_value("progress", "max_danger", gm.max_danger_unlocked)
	cfg.set_value("progress", "unlocked_cultivators", gm.unlocked_cultivators)
	cfg.set_value("progress", "unlocked_items", gm.unlocked_items)
	cfg.set_value("progress", "unlocked_achievements", gm.unlocked_achievements)

	cfg.set_value("stats", "total_runs", int(gm.career_stats.get("total_runs", 0)))
	cfg.set_value("stats", "total_wins", int(gm.career_stats.get("total_wins", 0)))
	cfg.set_value("stats", "total_kills", int(gm.career_stats.get("total_kills", 0)))
	cfg.set_value("stats", "best_wave", int(gm.career_stats.get("best_wave", 0)))
	cfg.set_value("stats", "best_kills", int(gm.career_stats.get("best_kills", 0)))
	cfg.set_value("stats", "total_stones", int(gm.career_stats.get("total_stones", 0)))
	cfg.set_value("stats", "total_time", float(gm.career_stats.get("total_time", 0.0)))

	cfg.set_value("records", "cultivator_best_danger", gm.cultivator_best_danger)
	cfg.set_value("history", "recent_runs", gm.run_history)
	cfg.save(PROGRESS_PATH)

## 结算时汇总生涯统计、记录战报、判定新成就解锁并统一落盘
static func record_run_and_check_achievements(gm: Node, victory: bool) -> void:
	var eff_wave := maxi(gm.wave_number, gm.VICTORY_WAVE if victory else 1)
	var eff_stones := maxi(gm.spirit_stones, gm.peak_stones)
	var eff_dodge := maxf(gm.get_effective_dodge(), gm.peak_dodge)
	var eff_harvest := maxf(gm.harvest, gm.peak_harvest)

	gm.career_stats["total_runs"] = int(gm.career_stats.get("total_runs", 0)) + 1
	if victory:
		gm.career_stats["total_wins"] = int(gm.career_stats.get("total_wins", 0)) + 1
	gm.career_stats["total_kills"] = int(gm.career_stats.get("total_kills", 0)) + gm.kills
	gm.career_stats["best_wave"] = maxi(int(gm.career_stats.get("best_wave", 0)), eff_wave)
	gm.career_stats["best_kills"] = maxi(int(gm.career_stats.get("best_kills", 0)), gm.kills)
	gm.career_stats["total_stones"] = int(gm.career_stats.get("total_stones", 0)) + gm.spirit_stones
	gm.career_stats["total_time"] = float(gm.career_stats.get("total_time", 0.0)) + gm.game_time

	if victory and not gm.cultivator_id.is_empty():
		var prev_d := int(gm.cultivator_best_danger.get(gm.cultivator_id, -1))
		if gm.danger_level > prev_d:
			gm.cultivator_best_danger[gm.cultivator_id] = gm.danger_level

	var cid_rec: String = gm.cultivator_id if not gm.cultivator_id.is_empty() else "jianchi"
	var entry := {
		"cultivator_id": cid_rec,
		"danger": gm.danger_level,
		"wave": eff_wave,
		"kills": gm.kills,
		"level": gm.level,
		"victory": victory,
		"time": gm.game_time,
	}
	gm.run_history.push_front(entry)
	while gm.run_history.size() > MAX_HISTORY_ENTRIES:
		gm.run_history.pop_back()

	var run_ctx := {
		"victory": victory,
		"danger": gm.danger_level,
		"wave": eff_wave,
		"level": gm.level,
		"kills": gm.kills,
		"max_stones": eff_stones,
		"max_dodge": eff_dodge,
		"max_harvest": eff_harvest,
	}
	var newly := AchievementData.evaluate_new_unlocks(run_ctx, gm.career_stats, gm.unlocked_achievements)
	gm.last_run_new_achievements = []
	for aid in newly:
		gm.unlocked_achievements.append(aid)
		gm.last_run_new_achievements.append(aid)
		var adef := AchievementData.get_def(aid)
		var rtype := String(adef.get("reward_type", ""))
		var rid := String(adef.get("reward_id", ""))
		if rtype == "cultivator" and not rid.is_empty() and not (rid in gm.unlocked_cultivators):
			gm.unlocked_cultivators.append(rid)
		elif rtype == "item" and not rid.is_empty() and not (rid in gm.unlocked_items):
			gm.unlocked_items.append(rid)
	save_from(gm)
	if not gm.last_run_new_achievements.is_empty():
		gm.achievements_unlocked.emit(gm.last_run_new_achievements)
