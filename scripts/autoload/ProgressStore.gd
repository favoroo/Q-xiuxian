class_name ProgressStore
extends RefCounted

## 局外元进度存档与成就结算子系统
## 负责 user://progress.cfg 的读写、save_version 向前兼容、生涯统计累加、战报记录与成就解锁判定。

const PROGRESS_PATH := "user://progress.cfg"
const SAVE_VERSION: int = 2
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

		var crec = cfg.get_value("records", "cultivator_records", {})
		gm.cultivator_records = crec.duplicate() if crec is Dictionary else {}

		var vlog = cfg.get_value("records", "victory_log", [])
		gm.victory_log = vlog.duplicate() if vlog is Array else []

		var miles = cfg.get_value("records", "claimed_milestones", [])
		gm.claimed_milestones = miles.duplicate() if miles is Array else []

		gm.stone_purse = int(cfg.get_value("records", "stone_purse", 0))

		var hist = cfg.get_value("history", "recent_runs", [])
		gm.run_history = hist.duplicate() if hist is Array else []
	else:
		gm.unlocked_cultivators = AchievementData.DEFAULT_CULTIVATORS.duplicate()
		gm.unlocked_items = AchievementData.DEFAULT_ITEMS.duplicate()
		gm.unlocked_achievements = []
		gm.cultivator_best_danger = {}
		gm.cultivator_records = {}
		gm.victory_log = []
		gm.claimed_milestones = []
		gm.stone_purse = 0
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
	cfg.set_value("records", "cultivator_records", gm.cultivator_records)
	cfg.set_value("records", "victory_log", gm.victory_log)
	cfg.set_value("records", "claimed_milestones", gm.claimed_milestones)
	cfg.set_value("records", "stone_purse", gm.stone_purse)
	cfg.set_value("history", "recent_runs", gm.run_history)
	cfg.save(PROGRESS_PATH)

## 结算时汇总生涯统计、记录战报、判定新成就解锁并统一落盘
## 两条路径：
##   1. 无尽终局（endless_mode 且非 victory）——该局已在渡劫成功时记过一次，只补无尽纪录与战报，不再累计生涯总量
##   2. 正常结算——累计生涯统计 + 每角色档案 + 渡劫成功快照 + 新纪录/里程碑提示 + 成就判定
static func record_run_and_check_achievements(gm: Node, victory: bool) -> void:
	var eff_wave := maxi(gm.wave_number, gm.VICTORY_WAVE if victory else 1)
	var cid_rec: String = gm.cultivator_id if not gm.cultivator_id.is_empty() else "jianchi"
	gm.last_run_new_records = []

	# ---------- 路径 1：无尽终局（渡劫成功后继续无尽，或开局直入无尽试炼，最终道殒） ----------
	if gm.endless_mode and not victory:
		var prev_rec_e: Dictionary = gm.get_cultivator_record(cid_rec)
		var rec_e: Dictionary = gm.cultivator_records.get(cid_rec, {})
		# 若本局是从主菜单直接开启无尽模式，生涯局数依然累加（否则一局都不计入）
		if gm.start_in_endless:
			gm.career_stats["total_runs"] = int(gm.career_stats.get("total_runs", 0)) + 1
			gm.career_stats["total_kills"] = int(gm.career_stats.get("total_kills", 0)) + gm.kills
			gm.career_stats["total_stones"] = int(gm.career_stats.get("total_stones", 0)) + gm.spirit_stones
			gm.career_stats["total_time"] = float(gm.career_stats.get("total_time", 0.0)) + gm.game_time
			rec_e["runs"] = int(rec_e.get("runs", 0)) + 1
		rec_e["endless_best_wave"] = maxi(int(rec_e.get("endless_best_wave", 0)), gm.wave_number)
		rec_e["best_kills"] = maxi(int(rec_e.get("best_kills", 0)), gm.kills)
		gm.cultivator_records[cid_rec] = rec_e
		gm.career_stats["best_wave"] = maxi(int(gm.career_stats.get("best_wave", 0)), gm.wave_number)
		gm.career_stats["best_kills"] = maxi(int(gm.career_stats.get("best_kills", 0)), gm.kills)
		if rec_e["endless_best_wave"] > prev_rec_e["endless_best_wave"]:
			gm.last_run_new_records.append("角色新纪录 · 无尽第 %d 波" % gm.wave_number)
		gm.run_history.push_front({
			"cultivator_id": cid_rec,
			"danger": gm.danger_level,
			"wave": gm.wave_number,
			"kills": gm.kills,
			"level": gm.level,
			"victory": false,
			"time": gm.game_time,
			"endless": true,
		})
		while gm.run_history.size() > MAX_HISTORY_ENTRIES:
			gm.run_history.pop_back()
		gm.last_run_new_achievements = []
		save_from(gm)
		return

	# ---------- 路径 2：正常结算 ----------
	var eff_stones := maxi(gm.spirit_stones, gm.peak_stones)
	var eff_dodge := maxf(gm.get_effective_dodge(), gm.peak_dodge)
	var eff_harvest := maxf(gm.harvest, gm.peak_harvest)

	# 新纪录判定基准：结算前的旧值
	var prev_best_kills := int(gm.career_stats.get("best_kills", 0))
	var prev_best_wave := int(gm.career_stats.get("best_wave", 0))
	var prev_wins: int = int(gm.get_cultivator_record(cid_rec).get("wins", 0))

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

	# 每角色生涯档案累加
	var rec: Dictionary = gm.cultivator_records.get(cid_rec, {})
	rec["runs"] = int(rec.get("runs", 0)) + 1
	if victory:
		rec["wins"] = int(rec.get("wins", 0)) + 1
	rec["best_kills"] = maxi(int(rec.get("best_kills", 0)), gm.kills)
	gm.cultivator_records[cid_rec] = rec

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

	# 渡劫成功：生成该局完整战报快照（白名单字段，剔除节点引用防炸档）
	if victory:
		gm.victory_log.push_front(_make_victory_snapshot(gm, cid_rec, eff_wave))
		while gm.victory_log.size() > gm.VICTORY_LOG_CAP:
			gm.victory_log.pop_back()

	# 新纪录文案（供结算弹窗展示）
	if gm.kills > prev_best_kills:
		gm.last_run_new_records.append("生涯新纪录 · 击杀 %d 只" % gm.kills)
	if victory and eff_wave > prev_best_wave:
		gm.last_run_new_records.append("生涯新纪录 · 抵御第 %d 波" % eff_wave)
	if victory and prev_wins == 0:
		var cdef := CultivatorData.get_def(cid_rec)
		gm.last_run_new_records.append("角色首胜 · %s" % String(cdef.get("name", "角色")))
	# 里程碑达标提示（只提示不自动发灵石，需在修仙志手动领取）
	for m in AchievementData.milestones_of(cid_rec):
		if prev_wins < int(m["wins"]) and int(rec["wins"]) >= int(m["wins"]):
			gm.last_run_new_records.append("里程碑达成 ·「%s」金币待领取" % String(m["title"]))

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

## 渡劫成功战报快照：只取可序列化的白名单字段（name/star/icon 等纯数据，绝不带节点引用）
static func _make_victory_snapshot(gm: Node, cid: String, wave: int) -> Dictionary:
	var weapons: Array = []
	for w in gm.get_weapons_summary():
		weapons.append({
			"name": String(w.get("name", "武器")),
			"star": int(w.get("star", 1)),
			"icon": String(w.get("icon", "")),
			"is_drone": bool(w.get("is_drone", false)),
		})
	var items: Array = []
	for iid in gm.items:
		var idef: Dictionary = ItemData.get_def(String(iid))
		if idef.is_empty():
			continue
		items.append({
			"name": String(idef.get("name", "道具")),
			"icon": String(idef.get("icon", "")),
		})
	var hp_max := 0.0
	if gm.player != null and is_instance_valid(gm.player):
		hp_max = float(gm.player.max_health)
	return {
		"cultivator_id": cid,
		"danger": gm.danger_level,
		"wave": wave,
		"kills": gm.kills,
		"level": gm.level,
		"time": gm.game_time,
		"datetime": Time.get_datetime_string_from_system(),
		"weapons": weapons,
		"items": items,
		"stats": {
			"armor": gm.armor,
			"dodge": gm.dodge,
			"crit_rate": gm.crit_rate,
			"hp_max": hp_max,
			"harvest": gm.harvest,
			"luck": gm.luck,
			"stones": gm.spirit_stones,
		},
	}
