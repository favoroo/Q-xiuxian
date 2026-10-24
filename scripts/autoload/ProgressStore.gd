class_name ProgressStore
extends RefCounted

## 局外元进度存档与成就结算子系统
## 负责 user://progress.cfg 的读写、save_version 向前兼容、生涯统计累加、战报记录与成就解锁判定。

const PROGRESS_PATH := "user://progress.cfg"
const SAVE_VERSION: int = 2
const MAX_HISTORY_ENTRIES: int = 10

## 读取 best_class_counts（器类峰值生涯最佳），容错非字典存档
static func _load_best_class_counts(cfg: ConfigFile) -> Dictionary:
	var bcc = cfg.get_value("stats", "best_class_counts", {})
	return (bcc as Dictionary).duplicate() if bcc is Dictionary else {}

## 把本局各峰值并入「单局生涯最佳」（成就进度展示的数据源；成就判定仍用本局 run_ctx，口径互不影响）
static func _merge_best_run_stats(gm: Node) -> void:
	var cs: Dictionary = gm.career_stats
	var bcc: Dictionary = cs.get("best_class_counts", {})
	for cls in gm.max_class_counts:
		bcc[cls] = maxi(int(bcc.get(cls, 0)), int(gm.max_class_counts[cls]))
	cs["best_class_counts"] = bcc
	cs["best_summons"] = maxi(int(cs.get("best_summons", 0)), int(gm.max_concurrent_summons))
	cs["best_element_spread"] = maxi(int(cs.get("best_element_spread", 0)), int(gm.max_element_spread))
	cs["best_stones"] = maxi(int(cs.get("best_stones", 0)), maxi(gm.spirit_stones, gm.peak_stones))
	cs["best_dodge"] = maxf(float(cs.get("best_dodge", 0.0)), maxf(gm.get_effective_dodge(), gm.peak_dodge))
	cs["best_harvest"] = maxf(float(cs.get("best_harvest", 0.0)), maxf(gm.harvest, gm.peak_harvest))
	cs["best_healed"] = maxf(float(cs.get("best_healed", 0.0)), gm.total_hp_healed)
	cs["best_hits_taken"] = maxi(int(cs.get("best_hits_taken", 0)), int(gm.total_damage_taken_count))
	cs["best_level"] = maxi(int(cs.get("best_level", 0)), int(gm.level))

static func load_into(gm: Node) -> void:
	var cfg := ConfigFile.new()
	var load_err := cfg.load(PROGRESS_PATH)
	if load_err == OK:
		# 版本号只作诊断：向前兼容靠下方各字段的 additive 默认值兜底，没有迁移分支。
		# 读到高于当前版本的存档（降级安装）时提示一句但不拒绝加载 —— 老档回落默认值
		# 比读不了档更可接受，真要做迁移时这里就是入口。
		var saved_ver := int(cfg.get_value("meta", "save_version", 1))
		if saved_ver > SAVE_VERSION:
			push_warning("ProgressStore: 存档版本 %d 高于当前 %d，缺字段将按默认值加载" % [saved_ver, SAVE_VERSION])

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
		# 单局生涯最佳（成就进度展示数据源，2026-10-14 新增；老档缺字段按默认值回落）
		gm.career_stats["best_class_counts"] = _load_best_class_counts(cfg)
		gm.career_stats["best_summons"] = int(cfg.get_value("stats", "best_summons", 0))
		gm.career_stats["best_element_spread"] = int(cfg.get_value("stats", "best_element_spread", 0))
		gm.career_stats["best_stones"] = int(cfg.get_value("stats", "best_stones", 0))
		gm.career_stats["best_dodge"] = float(cfg.get_value("stats", "best_dodge", 0.0))
		gm.career_stats["best_harvest"] = float(cfg.get_value("stats", "best_harvest", 0.0))
		gm.career_stats["best_healed"] = float(cfg.get_value("stats", "best_healed", 0.0))
		gm.career_stats["best_hits_taken"] = int(cfg.get_value("stats", "best_hits_taken", 0))
		gm.career_stats["best_level"] = int(cfg.get_value("stats", "best_level", 0))
		gm.career_stats["best_danger_cleared"] = int(cfg.get_value("stats", "best_danger_cleared", -1))
		gm.career_stats["wins_no_skill_enhance"] = int(cfg.get_value("stats", "wins_no_skill_enhance", 0))

		var cbd = cfg.get_value("records", "cultivator_best_danger", {})
		gm.cultivator_best_danger = cbd.duplicate() if cbd is Dictionary else {}

		var cdc = cfg.get_value("records", "cultivator_danger_clears", {})
		gm.cultivator_danger_clears = cdc.duplicate() if cdc is Dictionary else {}
		# 老档无位掩码字段：按已有最高通关难度回填低位封印
		# （能通关 Dk 意味着该角色实力覆盖 D0~Dk，2026-10-12 迁移）
		for cid in gm.cultivator_best_danger:
			if gm.cultivator_danger_clears.has(cid):
				continue
			var best_d := int(gm.cultivator_best_danger[cid])
			if best_d >= 0:
				gm.cultivator_danger_clears[cid] = (1 << (best_d + 1)) - 1

		# 难度 6 档 → 4 档压缩迁移（2026-10-20）：老档里的 D4/D5 记录整体折进新顶档 D3，
		# 保留「打到过最高档」的荣誉，不因档位收缩凭空丢封印与境界。
		_compress_danger_progress(gm)

		var crec = cfg.get_value("records", "cultivator_records", {})
		gm.cultivator_records = crec.duplicate() if crec is Dictionary else {}

		# 皮肤选择（换色皮肤，2026-10-14 新增；老档缺字段按空字典回落，全员原色）
		var sksel = cfg.get_value("progress", "skin_selections", {})
		gm.skin_selections = sksel.duplicate() if sksel is Dictionary else {}

		# 老档回填：best_danger_cleared 字段晚于每角色通关难度出现（2026-10-14），
		# 存档里没有时按各角色最高通关难度推一个，避免老玩家解锁提示误显「尚未通关」。
		if not cfg.has_section_key("stats", "best_danger_cleared"):
			var bd := -1
			for v in gm.cultivator_best_danger.values():
				bd = maxi(bd, int(v))
			gm.career_stats["best_danger_cleared"] = bd

		var vlog = cfg.get_value("records", "victory_log", [])
		gm.victory_log = vlog.duplicate() if vlog is Array else []

		var hist = cfg.get_value("history", "recent_runs", [])
		gm.run_history = hist.duplicate() if hist is Array else []

		# 2026-10-24 坏字段可见化：文件能解析但字段类型不对（手改/写入中断）时原先静默回落
		# 默认值，玩家侧读作「解锁/记录全没了」且日志零线索。异常字段集中点名一条。
		var bad_fields: Array[String] = []
		if not (cults is Array):
			bad_fields.append("unlocked_cultivators")
		if not (itms is Array):
			bad_fields.append("unlocked_items")
		if not (achs is Array):
			bad_fields.append("unlocked_achievements")
		if not (cbd is Dictionary):
			bad_fields.append("cultivator_best_danger")
		if not (cdc is Dictionary):
			bad_fields.append("cultivator_danger_clears")
		if not (crec is Dictionary):
			bad_fields.append("cultivator_records")
		if not (vlog is Array):
			bad_fields.append("victory_log")
		if not (hist is Array):
			bad_fields.append("recent_runs")
		if not bad_fields.is_empty():
			push_error("ProgressStore: progress.cfg 字段类型异常（%s），对应内容已回落默认 —— 疑似存档被手改或写入中断 path=%s" % [
					"、".join(PackedStringArray(bad_fields)), PROGRESS_PATH])
	else:
		if FileAccess.file_exists(PROGRESS_PATH):
			# 2026-10-24 从 warning 升级为 error：文件在但读不出来 = 玩家进度实际丢失，
			# 是需要被看见的故障（首次启动无档走上面的 OK 外路径，不进这里）
			push_error("ProgressStore: 读取局外进度失败 err=%d path=%s，已回落默认" % [load_err, PROGRESS_PATH])
		gm.unlocked_cultivators = AchievementData.DEFAULT_CULTIVATORS.duplicate()
		gm.unlocked_items = AchievementData.DEFAULT_ITEMS.duplicate()
		gm.unlocked_achievements = []
		gm.cultivator_best_danger = {}
		gm.cultivator_danger_clears = {}
		gm.cultivator_records = {}
		gm.victory_log = []
		gm.run_history = []
		gm.skin_selections = {}

	# 确保初始集合必在（防止旧档或异常数据丢失基础内容）
	for cid in AchievementData.DEFAULT_CULTIVATORS:
		if not (cid in gm.unlocked_cultivators):
			gm.unlocked_cultivators.append(cid)
	for iid in AchievementData.DEFAULT_ITEMS:
		if not (iid in gm.unlocked_items):
			gm.unlocked_items.append(iid)
	# 剔除已不在道具表里的旧 id（改版删件时会有，如 2026-10-12 的卸匣锥）：
	# 留着它「道具 N/M」会多算一件不存在的道具，且玉匣白送时可能抽到空定义。
	for i in range(gm.unlocked_items.size() - 1, -1, -1):
		if not ItemData.DEFS.has(String(gm.unlocked_items[i])):
			gm.unlocked_items.remove_at(i)
	# 角色同理：剔除已不在角色表里的旧 id（防止改版删改角色导致 N/M 分子虚高）
	for i in range(gm.unlocked_cultivators.size() - 1, -1, -1):
		if not CultivatorData.DEFS.has(String(gm.unlocked_cultivators[i])):
			gm.unlocked_cultivators.remove_at(i)
	# 成就同理：剔除已不在成就表里的旧 id
	for i in range(gm.unlocked_achievements.size() - 1, -1, -1):
		if AchievementData.get_def(String(gm.unlocked_achievements[i])).is_empty():
			gm.unlocked_achievements.remove_at(i)

## 难度 6 档 → 4 档（D0~D3）老档压缩（2026-10-20 改版一次性迁移）：
## 老档的 D4/D5 战绩折进新顶档 D3，D0~D3 原样保留 —— 打过最高档的玩家不会因档位收缩丢记录。
## 位掩码先折叠高位再截断，避免 (1<<4)/(1<<5) 在 UI 里映射到不存在的档位。
static func _compress_danger_progress(gm: Node) -> void:
	var top := GameBalance.DANGER_MAX
	var keep_mask := (1 << (top + 1)) - 1        # 新档位可表示的位宽，如 4 档 = 0b1111
	var high_bits := ~keep_mask                  # 被砍掉的高位，如 4 档 = 0b...11110000
	for cid in gm.cultivator_best_danger.keys():
		var best := int(gm.cultivator_best_danger[cid])
		if best > top:
			gm.cultivator_best_danger[cid] = top
	for cid in gm.cultivator_danger_clears.keys():
		var mask := int(gm.cultivator_danger_clears[cid])
		if mask & high_bits:
			mask = (mask & keep_mask) | (1 << top)
		gm.cultivator_danger_clears[cid] = mask & keep_mask
	var bdc := int(gm.career_stats.get("best_danger_cleared", -1))
	if bdc > top:
		gm.career_stats["best_danger_cleared"] = top

static func save_from(gm: Node, target_path: String = PROGRESS_PATH) -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "save_version", SAVE_VERSION)
	cfg.set_value("progress", "unlocked_cultivators", gm.unlocked_cultivators)
	cfg.set_value("progress", "unlocked_items", gm.unlocked_items)
	cfg.set_value("progress", "unlocked_achievements", gm.unlocked_achievements)
	cfg.set_value("progress", "skin_selections", gm.skin_selections)

	cfg.set_value("stats", "total_runs", int(gm.career_stats.get("total_runs", 0)))
	cfg.set_value("stats", "total_wins", int(gm.career_stats.get("total_wins", 0)))
	cfg.set_value("stats", "total_kills", int(gm.career_stats.get("total_kills", 0)))
	cfg.set_value("stats", "best_wave", int(gm.career_stats.get("best_wave", 0)))
	cfg.set_value("stats", "best_kills", int(gm.career_stats.get("best_kills", 0)))
	cfg.set_value("stats", "total_stones", int(gm.career_stats.get("total_stones", 0)))
	cfg.set_value("stats", "total_time", float(gm.career_stats.get("total_time", 0.0)))
	# 单局生涯最佳（成就进度展示数据源）
	cfg.set_value("stats", "best_class_counts", gm.career_stats.get("best_class_counts", {}))
	cfg.set_value("stats", "best_summons", int(gm.career_stats.get("best_summons", 0)))
	cfg.set_value("stats", "best_element_spread", int(gm.career_stats.get("best_element_spread", 0)))
	cfg.set_value("stats", "best_stones", int(gm.career_stats.get("best_stones", 0)))
	cfg.set_value("stats", "best_dodge", float(gm.career_stats.get("best_dodge", 0.0)))
	cfg.set_value("stats", "best_harvest", float(gm.career_stats.get("best_harvest", 0.0)))
	cfg.set_value("stats", "best_healed", float(gm.career_stats.get("best_healed", 0.0)))
	cfg.set_value("stats", "best_hits_taken", int(gm.career_stats.get("best_hits_taken", 0)))
	cfg.set_value("stats", "best_level", int(gm.career_stats.get("best_level", 0)))
	cfg.set_value("stats", "best_danger_cleared", int(gm.career_stats.get("best_danger_cleared", -1)))
	cfg.set_value("stats", "wins_no_skill_enhance", int(gm.career_stats.get("wins_no_skill_enhance", 0)))

	cfg.set_value("records", "cultivator_best_danger", gm.cultivator_best_danger)
	cfg.set_value("records", "cultivator_danger_clears", gm.cultivator_danger_clears)
	cfg.set_value("records", "cultivator_records", gm.cultivator_records)
	cfg.set_value("records", "victory_log", gm.victory_log)
	# 新手指南「下次不弹出」是玩家偏好，2026-10-11 起落 user://settings.cfg
	# （SettingsManager.tutorial_muted），不再占用局外进度存档的 tutorial_seen 位。
	cfg.set_value("history", "recent_runs", gm.run_history)
	var err := _atomic_save(cfg, target_path)
	if err != OK:
		push_warning("ProgressStore: 保存局外进度失败 err=%d path=%s，尝试重试" % [err, target_path])
		err = _atomic_save(cfg, target_path)
		if err != OK:
			push_warning("ProgressStore: 重试保存局外进度仍失败 err=%d path=%s" % [err, target_path])
			var tree := Engine.get_main_loop() as SceneTree
			if tree != null and tree.root != null and tree.root.has_node("UpdateManager"):
				var um = tree.root.get_node("UpdateManager")
				if um != null and um.has_method("show_toast"):
					um.show_toast("进度保存失败（存储空间不足或权限受限）", GameStyle.BAD, 3.5)
	return err

## 原子保存 ConfigFile：先写入同目录下的 .tmp 文件，成功后再重命名覆盖目标文件，
## 避免直接覆盖写入过程中发生强退或断电导致原存档损坏截断。
static func _atomic_save(cfg: ConfigFile, target_path: String) -> Error:
	var base_dir := target_path.get_base_dir()
	var file_name := target_path.get_file()
	var tmp_name := file_name + ".tmp"
	var tmp_path := (base_dir + "/" + tmp_name) if not base_dir.is_empty() else tmp_name
	var err := cfg.save(tmp_path)
	if err != OK:
		return err
	var dir := DirAccess.open(base_dir)
	if dir == null:
		return DirAccess.get_open_error()
	var r := dir.rename(tmp_name, file_name)
	if r != OK:
		# 跨平台兼容兜底：若系统不支持原子替换已存在文件，先清理目标再重命名
		if dir.file_exists(file_name):
			dir.remove(file_name)
			r = dir.rename(tmp_name, file_name)
	if r != OK:
		dir.remove(tmp_name)
		return r
	return OK

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
		_merge_best_run_stats(gm)
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
		# 无尽终局也判定成就（无尽行者这类只在无尽路径能达成；累计类照常兜底）
		var run_ctx_e := {
			"victory": false,
			"endless": true,
			"danger": gm.danger_level,
			"wave": gm.wave_number,
			"level": gm.level,
			"kills": gm.kills,
			"max_stones": maxi(gm.spirit_stones, gm.peak_stones),
			"max_dodge": maxf(gm.get_effective_dodge(), gm.peak_dodge),
			"max_harvest": maxf(gm.harvest, gm.peak_harvest),
			"damage_taken_count": gm.total_damage_taken_count,
			"hp_healed": gm.total_hp_healed,
			"max_summons": gm.max_concurrent_summons,
			"max_class_counts": gm.max_class_counts,
			"max_element_spread": gm.max_element_spread,
		}
		gm.last_run_new_achievements = []
		for aid in AchievementData.evaluate_new_unlocks(run_ctx_e, gm.career_stats, gm.unlocked_achievements):
			gm.unlocked_achievements.append(aid)
			gm.last_run_new_achievements.append(aid)
			_apply_achievement_reward(gm, aid)
		save_from(gm)
		if not gm.last_run_new_achievements.is_empty():
			gm.achievements_unlocked.emit(gm.last_run_new_achievements)
		return

	# ---------- 路径 2：正常结算 ----------
	var eff_stones := maxi(gm.spirit_stones, gm.peak_stones)
	var eff_dodge := maxf(gm.get_effective_dodge(), gm.peak_dodge)
	var eff_harvest := maxf(gm.harvest, gm.peak_harvest)
	_merge_best_run_stats(gm)

	# 新纪录判定基准：结算前的旧值
	var prev_best_kills := int(gm.career_stats.get("best_kills", 0))
	var prev_best_wave := int(gm.career_stats.get("best_wave", 0))
	var prev_wins: int = int(gm.get_cultivator_record(cid_rec).get("wins", 0))

	gm.career_stats["total_runs"] = int(gm.career_stats.get("total_runs", 0)) + 1
	if victory:
		gm.career_stats["total_wins"] = int(gm.career_stats.get("total_wins", 0)) + 1
		# 「万法由心」进度：本局携带随行技能通关累加
		if not gm.active_skill_id.is_empty():
			gm.career_stats["wins_no_skill_enhance"] = int(gm.career_stats.get("wins_no_skill_enhance", 0)) + 1
	gm.career_stats["total_kills"] = int(gm.career_stats.get("total_kills", 0)) + gm.kills
	gm.career_stats["best_wave"] = maxi(int(gm.career_stats.get("best_wave", 0)), eff_wave)
	gm.career_stats["best_kills"] = maxi(int(gm.career_stats.get("best_kills", 0)), gm.kills)
	gm.career_stats["total_stones"] = int(gm.career_stats.get("total_stones", 0)) + gm.spirit_stones
	gm.career_stats["total_time"] = float(gm.career_stats.get("total_time", 0.0)) + gm.game_time

	if victory and not gm.cultivator_id.is_empty():
		var prev_d := int(gm.cultivator_best_danger.get(gm.cultivator_id, -1))
		if gm.danger_level > prev_d:
			gm.cultivator_best_danger[gm.cultivator_id] = gm.danger_level
			# 境界突破提示（该角色首次通关此难度 → 境界称号升档，纯荣誉不发奖励）
			var cdef_r := CultivatorData.get_def(gm.cultivator_id)
			gm.last_run_new_records.append("境界突破 · %s 晋入「%s」" % [
				String(cdef_r.get("name", "角色")), AchievementData.realm_for_danger(gm.danger_level)])
		# 难度封印位掩码：点亮本局通关的这一档
		var mask := int(gm.cultivator_danger_clears.get(gm.cultivator_id, 0))
		gm.cultivator_danger_clears[gm.cultivator_id] = mask | (1 << gm.danger_level)
	if victory:
		# 生涯最高通关难度（成就进度「最高通关 X」口径，难度达成型成就判定不受它影响）
		gm.career_stats["best_danger_cleared"] = maxi(
			int(gm.career_stats.get("best_danger_cleared", -1)), gm.danger_level)

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

	var run_ctx := {
		"victory": victory,
		"endless": false,
		"danger": gm.danger_level,
		"wave": eff_wave,
		"level": gm.level,
		"kills": gm.kills,
		"max_stones": eff_stones,
		"max_dodge": eff_dodge,
		"max_harvest": eff_harvest,
		"damage_taken_count": gm.total_damage_taken_count,
		"hp_healed": gm.total_hp_healed,
		"max_summons": gm.max_concurrent_summons,
		"max_class_counts": gm.max_class_counts,
		"max_element_spread": gm.max_element_spread,
	}
	var newly := AchievementData.evaluate_new_unlocks(run_ctx, gm.career_stats, gm.unlocked_achievements)
	gm.last_run_new_achievements = []
	for aid in newly:
		gm.unlocked_achievements.append(aid)
		gm.last_run_new_achievements.append(aid)
		_apply_achievement_reward(gm, aid)
		save_from(gm)
	if not gm.last_run_new_achievements.is_empty():
		gm.achievements_unlocked.emit(gm.last_run_new_achievements)

## 发放成就奖励："none" 纯荣誉型只点亮成就本身，不动角色/道具池
static func _apply_achievement_reward(gm: Node, aid: String) -> void:
	var adef := AchievementData.get_def(aid)
	var rtype := String(adef.get("reward_type", ""))
	var rid := String(adef.get("reward_id", ""))
	if rtype == "cultivator" and not rid.is_empty() and not (rid in gm.unlocked_cultivators):
		gm.unlocked_cultivators.append(rid)
	elif rtype == "item" and not rid.is_empty() and not (rid in gm.unlocked_items):
		gm.unlocked_items.append(rid)

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
