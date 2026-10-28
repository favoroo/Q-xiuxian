class_name ProgressStore
extends RefCounted

## 局外元进度存档与成就结算子系统
## 负责 user://progress.cfg 的读写、save_version 向前兼容、生涯统计累加、历战实录与成就解锁判定。
## 2026-10-28 无限闯关改版：只有「阵亡」一种结算（不再有通关/无尽终局两条路），
## 难度压到两档（普通/噩梦），解锁口径改成「在难度 d 单局抵达第 20 波 = 破境」。

const PROGRESS_PATH := "user://progress.cfg"
const SAVE_VERSION: int = 3
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
		# 版本号除了诊断还兼作迁移闸：save_version < 3 的老档要在下面跑一次难度折叠。
		# 读到高于当前版本的存档（降级安装）时提示一句但不拒绝加载 —— 老档回落默认值
		# 比读不了档更可接受。
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

		# 武器解锁（2026-10-25 新增）。老档兼容靠「键在不在」分流，不靠版本号：
		#   · 老档（有档但没这个键）→ 视为全解锁，老玩家资产一件不许少；
		#   · 新档 → 按存档里的列表，稍后统一补默认池。
		var wpns = cfg.get_value("progress", "unlocked_weapons", [])
		if cfg.has_section_key("progress", "unlocked_weapons") and wpns is Array:
			gm.unlocked_weapons = wpns.duplicate()
		else:
			gm.unlocked_weapons = WeaponData.DEFS.keys().duplicate()

		var unread = cfg.get_value("progress", "unread_unlocks", [])
		gm.unread_unlocks = unread.duplicate() if unread is Array else []

		var achs = cfg.get_value("progress", "unlocked_achievements", [])
		gm.unlocked_achievements = achs.duplicate() if achs is Array else []

		gm.career_stats["total_runs"] = int(cfg.get_value("stats", "total_runs", 0))
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
		# 破境计数（带随行技能破境累计次数）。新键 milestones_with_skill 优先；
		# 老档没有这个键时回落旧键 wins_no_skill_enhance —— 老玩家进度不许丢。
		var mws := 0
		if cfg.has_section_key("stats", "milestones_with_skill"):
			mws = int(cfg.get_value("stats", "milestones_with_skill", 0))
		else:
			mws = int(cfg.get_value("stats", "wins_no_skill_enhance", 0))
		gm.career_stats["milestones_with_skill"] = mws

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
		_migrate_six_to_four(gm)

		var crec = cfg.get_value("records", "cultivator_records", {})
		gm.cultivator_records = crec.duplicate() if crec is Dictionary else {}

		# 每角色档案迁移（2026-10-28 无限闯关）：无尽试炼已下线，endless_best_wave 并进 best_wave；
		# wins 原样保留（旧档皮肤解锁兜底仍读它）。
		_migrate_cultivator_records(gm)

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

		# 历战实录（新到旧）：新键 record_log 优先，缺失时回落旧键 victory_log。
		var vlog: Array = []
		var vlog_ok := true
		if cfg.has_section_key("records", "record_log"):
			var rl = cfg.get_value("records", "record_log", [])
			if rl is Array:
				vlog = rl.duplicate()
			else:
				vlog_ok = false
		else:
			var vl = cfg.get_value("records", "victory_log", [])
			if vl is Array:
				vlog = vl.duplicate()
			else:
				vlog_ok = false
		gm.record_log = vlog

		var hist = cfg.get_value("history", "recent_runs", [])
		gm.run_history = hist.duplicate() if hist is Array else []

		# 难度 4 档 → 2 档（普通/噩梦）一次性迁移：只在 saved_ver < 3 时跑，
		# 必须放在 run_history / record_log 都读完之后（它要改写这两处的 danger 字段）。
		# 该折叠不幂等（旧 D2/D3 折成新 D1 后再折一次会降成 D0）：迁移完立刻升版落盘，
		# 否则玩家本次退出前没触发任何存档，下次启动会把噩梦档再折成普通。
		if saved_ver < 3:
			_collapse_danger_to_two(gm)
			save_from(gm)

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
		if not vlog_ok:
			bad_fields.append("record_log")
		if not (hist is Array):
			bad_fields.append("recent_runs")
		if not bad_fields.is_empty():
			push_error("ProgressStore: progress.cfg 字段类型异常（%s），对应内容已回落默认 —— 疑似存档被手改或写入中断 path=%s" % [
					"、".join(PackedStringArray(bad_fields)), PROGRESS_PATH])
			gm.pending_load_alert = "◆ 进度存档字段异常，部分进度已重置 ◆"
	else:
		if FileAccess.file_exists(PROGRESS_PATH):
			# 2026-10-24 从 warning 升级为 error：文件在但读不出来 = 玩家进度实际丢失，
			# 是需要被看见的故障（首次启动无档走上面的 OK 外路径，不进这里）
			push_error("ProgressStore: 读取局外进度失败 err=%d path=%s，已回落默认" % [load_err, PROGRESS_PATH])
			gm.pending_load_alert = "◆ 进度存档损坏，已从零开始 ◆"
		gm.unlocked_cultivators = AchievementData.DEFAULT_CULTIVATORS.duplicate()
		gm.unlocked_items = AchievementData.DEFAULT_ITEMS.duplicate()
		gm.unlocked_weapons = AchievementData.default_weapons()
		gm.unread_unlocks = []
		gm.unlocked_achievements = []
		gm.cultivator_best_danger = {}
		gm.cultivator_danger_clears = {}
		gm.cultivator_records = {}
		gm.record_log = []
		gm.run_history = []
		gm.skin_selections = {}

	# 确保初始集合必在（防止旧档或异常数据丢失基础内容）
	for cid in AchievementData.DEFAULT_CULTIVATORS:
		if not (cid in gm.unlocked_cultivators):
			gm.unlocked_cultivators.append(cid)
	for iid in AchievementData.DEFAULT_ITEMS:
		if not (iid in gm.unlocked_items):
			gm.unlocked_items.append(iid)
	# 武器：老档在上面的分支里已是全量，这里只给新档补默认池；
	# 已由成就解锁的武器不会被 default_weapons() 覆盖（它只往列表里追加，不重建）。
	for wid in AchievementData.default_weapons():
		if not (wid in gm.unlocked_weapons):
			gm.unlocked_weapons.append(wid)
	# 剔除已不在道具表里的旧 id（改版删件时会有，如 2026-10-12 的卸匣锥）：
	# 留着它「道具 N/M」会多算一件不存在的道具，且玉匣白送时可能抽到空定义。
	for i in range(gm.unlocked_items.size() - 1, -1, -1):
		if not ItemData.DEFS.has(String(gm.unlocked_items[i])):
			gm.unlocked_items.remove_at(i)
	# 角色同理：剔除已不在角色表里的旧 id（防止改版删改角色导致 N/M 分子虚高）
	for i in range(gm.unlocked_cultivators.size() - 1, -1, -1):
		if not CultivatorData.DEFS.has(String(gm.unlocked_cultivators[i])):
			gm.unlocked_cultivators.remove_at(i)
	# 武器同理：剔除已不在武器表里的旧 id（图鉴「已收录 n/m」的分子靠它不虚报）
	for i in range(gm.unlocked_weapons.size() - 1, -1, -1):
		if not WeaponData.DEFS.has(String(gm.unlocked_weapons[i])):
			gm.unlocked_weapons.remove_at(i)
	# 未读标记同理：指向已删对象的孤儿标记会让「新」角标永远销不掉
	for i in range(gm.unread_unlocks.size() - 1, -1, -1):
		var key := String(gm.unread_unlocks[i])
		var parts := key.split(":", true, 1)
		if parts.size() != 2:
			gm.unread_unlocks.remove_at(i)
			continue
		var kind := parts[0]
		var oid := parts[1]
		var alive := false
		match kind:
			"cultivator":
				alive = CultivatorData.DEFS.has(oid)
			"item":
				alive = ItemData.DEFS.has(oid)
			"weapon":
				alive = WeaponData.DEFS.has(oid)
		if not alive:
			gm.unread_unlocks.remove_at(i)
	# 成就同理：剔除已不在成就表里的旧 id
	for i in range(gm.unlocked_achievements.size() - 1, -1, -1):
		if AchievementData.get_def(String(gm.unlocked_achievements[i])).is_empty():
			gm.unlocked_achievements.remove_at(i)

## 难度 6 档 → 4 档（D0~D3）老档压缩（2026-10-20 改版一次性迁移）：
## 老档的 D4/D5 战绩折进新顶档 D3，D0~D3 原样保留 —— 打过最高档的玩家不会因档位收缩丢记录。
## 位掩码先折叠高位再截断，避免 (1<<4)/(1<<5) 在 UI 里映射到不存在的档位。
## 顶档固定为历史值 3（不是当前 GameBalance.DANGER_MAX）—— 这一步描述的是「6 档时代的 4 档」，
## 用当前常量会随后续改版漂移，迁移就不可复现了。函数保持幂等。
static func _migrate_six_to_four(gm: Node) -> void:
	const TOP := 3
	var keep_mask := (1 << (TOP + 1)) - 1        # 新档位可表示的位宽，如 4 档 = 0b1111
	var high_bits := ~keep_mask                  # 被砍掉的高位，如 4 档 = 0b...11110000
	for cid in gm.cultivator_best_danger.keys():
		var best := int(gm.cultivator_best_danger[cid])
		if best > TOP:
			gm.cultivator_best_danger[cid] = TOP
	for cid in gm.cultivator_danger_clears.keys():
		var mask := int(gm.cultivator_danger_clears[cid])
		if mask & high_bits:
			mask = (mask & keep_mask) | (1 << TOP)
		gm.cultivator_danger_clears[cid] = mask & keep_mask
	var bdc := int(gm.career_stats.get("best_danger_cleared", -1))
	if bdc > TOP:
		gm.career_stats["best_danger_cleared"] = TOP

## 难度 4 档 → 2 档（普通 D0 / 噩梦 D1）老档压缩（2026-10-28 无限闯关改版一次性迁移）：
## 旧 4 档 D0/D1 → 新 D0（普通），旧 D2/D3 → 新 D1（噩梦）；-1（从未破境）保持 -1。
## 封印位掩码同理折叠：旧 bit0/bit1 → 新 bit0，旧 bit2/bit3 → 新 bit1。
## run_history / record_log 里旧条目的 danger 字段一并改写，否则历史战报会指向不存在的档位。
## **有版本闸的一次性迁移**：只在 saved_ver < 3 时调用（见 load_into），跑过之后存档版本升到 3，
## 不会再进来 —— 反复折叠会把新档位也吃掉。
static func _collapse_danger_to_two(gm: Node) -> void:
	for cid in gm.cultivator_best_danger.keys():
		gm.cultivator_best_danger[cid] = _fold_danger(int(gm.cultivator_best_danger[cid]))
	for cid in gm.cultivator_danger_clears.keys():
		gm.cultivator_danger_clears[cid] = _fold_danger_mask(int(gm.cultivator_danger_clears[cid]))
	gm.career_stats["best_danger_cleared"] = _fold_danger(int(gm.career_stats.get("best_danger_cleared", -1)))
	for entry in gm.run_history:
		if entry is Dictionary:
			var e: Dictionary = entry
			e["danger"] = _fold_danger(int(e.get("danger", 0)))
	for snap in gm.record_log:
		if snap is Dictionary:
			var s: Dictionary = snap
			s["danger"] = _fold_danger(int(s.get("danger", 0)))

## 单个难度档位折叠：-1 保持 -1（从未破境），0/1 → 0，>=2 → 1
static func _fold_danger(d: int) -> int:
	if d < 0:
		return -1
	return 0 if d <= 1 else 1

## 封印位掩码折叠：旧 bit0/bit1 并入新 bit0，旧 bit2/bit3 并入新 bit1
static func _fold_danger_mask(mask: int) -> int:
	var out := 0
	if mask & 0b0001:
		out |= 0b01
	if mask & 0b0010:
		out |= 0b01
	if mask & 0b0100:
		out |= 0b10
	if mask & 0b1000:
		out |= 0b10
	return out

## 每角色档案迁移（2026-10-28 无限闯关）：无尽试炼下线，endless_best_wave 并进 best_wave（取 max），
## 键本身抹掉（不再有「无尽」这个概念）；wins 原样保留 —— 旧档皮肤解锁仍靠它兜底。
static func _migrate_cultivator_records(gm: Node) -> void:
	for cid in gm.cultivator_records.keys():
		var raw = gm.cultivator_records[cid]
		if not (raw is Dictionary):
			continue
		var rec: Dictionary = raw
		if rec.has("endless_best_wave"):
			rec["best_wave"] = maxi(int(rec.get("best_wave", 0)), int(rec["endless_best_wave"]))
			rec.erase("endless_best_wave")
		gm.cultivator_records[cid] = rec

static func save_from(gm: Node, target_path: String = PROGRESS_PATH) -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "save_version", SAVE_VERSION)
	cfg.set_value("progress", "unlocked_cultivators", gm.unlocked_cultivators)
	cfg.set_value("progress", "unlocked_items", gm.unlocked_items)
	cfg.set_value("progress", "unlocked_weapons", gm.unlocked_weapons)
	cfg.set_value("progress", "unlocked_achievements", gm.unlocked_achievements)
	cfg.set_value("progress", "unread_unlocks", gm.unread_unlocks)
	cfg.set_value("progress", "skin_selections", gm.skin_selections)

	cfg.set_value("stats", "total_runs", int(gm.career_stats.get("total_runs", 0)))
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
	cfg.set_value("stats", "milestones_with_skill", int(gm.career_stats.get("milestones_with_skill", 0)))

	cfg.set_value("records", "cultivator_best_danger", gm.cultivator_best_danger)
	cfg.set_value("records", "cultivator_danger_clears", gm.cultivator_danger_clears)
	cfg.set_value("records", "cultivator_records", gm.cultivator_records)
	cfg.set_value("records", "record_log", gm.record_log)
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

## 结算时汇总生涯统计、记录历战实录、判定新成就解锁并统一落盘。
## 2026-10-28 无限闯关改版：只有一条结算路径 —— 阵亡即结算。
## 破境口径：在难度 d 单局抵达第 GameManager.MILESTONE_WAVE 波 = 破境，
## 点亮该档封印并解锁下一档；不再有「通关次数」这种累计量。
static func record_run_and_check_achievements(gm: Node) -> void:
	var eff_wave := maxi(gm.wave_number, 1)
	var cid_rec: String = gm.cultivator_id if not gm.cultivator_id.is_empty() else "jianchi"
	gm.last_run_new_records = []

	var eff_stones := maxi(gm.spirit_stones, gm.peak_stones)
	var eff_dodge := maxf(gm.get_effective_dodge(), gm.peak_dodge)
	var eff_harvest := maxf(gm.harvest, gm.peak_harvest)
	_merge_best_run_stats(gm)

	# 新纪录判定基准：结算前的旧值
	var prev_best_kills := int(gm.career_stats.get("best_kills", 0))
	var prev_best_wave := int(gm.career_stats.get("best_wave", 0))
	var prev_best_danger := int(gm.career_stats.get("best_danger_cleared", -1))
	# 该角色档案的结算前副本：破境时用来对比「之前未解锁、现在已解锁」的新皮肤
	var prev_char_rec: Dictionary = gm.get_cultivator_record(cid_rec)
	var prev_char_best_danger := int(gm.cultivator_best_danger.get(gm.cultivator_id, -1))

	gm.career_stats["total_runs"] = int(gm.career_stats.get("total_runs", 0)) + 1
	gm.career_stats["total_kills"] = int(gm.career_stats.get("total_kills", 0)) + gm.kills
	gm.career_stats["best_wave"] = maxi(int(gm.career_stats.get("best_wave", 0)), eff_wave)
	gm.career_stats["best_kills"] = maxi(int(gm.career_stats.get("best_kills", 0)), gm.kills)
	gm.career_stats["total_stones"] = int(gm.career_stats.get("total_stones", 0)) + gm.spirit_stones
	gm.career_stats["total_time"] = float(gm.career_stats.get("total_time", 0.0)) + gm.game_time

	# 本局是否破境（抵达破境波）
	var broke: bool = eff_wave >= GameManager.MILESTONE_WAVE

	# 每角色生涯档案累加
	var rec: Dictionary = gm.cultivator_records.get(cid_rec, {})
	rec["runs"] = int(rec.get("runs", 0)) + 1
	rec["best_wave"] = maxi(int(rec.get("best_wave", 0)), eff_wave)
	rec["best_kills"] = maxi(int(rec.get("best_kills", 0)), gm.kills)
	gm.cultivator_records[cid_rec] = rec

	if broke and not gm.cultivator_id.is_empty():
		# 逐级解锁与新皮肤（2026-10-28）：实物/玩法层解锁排在最前，最先被结算屏展示
		if gm.danger_level > prev_best_danger and gm.danger_level < GameBalance.DANGER_MAX:
			gm.last_run_new_records.append("难度解锁 · 「%s」" % AchievementData.danger_name(gm.danger_level + 1))
		if gm.danger_level > prev_char_best_danger:
			gm.cultivator_best_danger[gm.cultivator_id] = gm.danger_level
			# 境界突破提示（该角色首次破境此难度 → 境界称号升档，纯荣誉不发奖励）
			var cdef_r := CultivatorData.get_def(gm.cultivator_id)
			gm.last_run_new_records.append("境界突破 · %s 晋入「%s」" % [
				String(cdef_r.get("name", "角色")), AchievementData.realm_for_danger(gm.danger_level)])
		# 难度封印位掩码：点亮本局破境的这一档
		var mask := int(gm.cultivator_danger_clears.get(gm.cultivator_id, 0))
		gm.cultivator_danger_clears[gm.cultivator_id] = mask | (1 << gm.danger_level)
		# 新皮肤播报：按该角色最高波数门槛逐套对比，找出「之前未解锁、现在已解锁」的皮肤。
		# 旧档兜底：wins >= skin_idx+1 的老规则也算解锁过（老玩家皮肤早就有，别重复播报）。
		var now_best_wave := int(rec.get("best_wave", 0))
		var now_wins := int(rec.get("wins", 0))
		var prev_best_wave_char := int(prev_char_rec.get("best_wave", 0))
		var prev_wins_char := int(prev_char_rec.get("wins", 0))
		var cdef_skin := CultivatorData.get_def(cid_rec)
		for si in range(SkinData.THEMES.size()):
			var theme := SkinData.get_theme(si)
			if theme.is_empty():
				continue
			var need_wave := int(theme.get("wave", 0))
			var now_open := now_best_wave >= need_wave or now_wins >= si + 1
			var was_open := prev_best_wave_char >= need_wave or prev_wins_char >= si + 1
			if not now_open or was_open:
				continue
			gm.last_run_new_records.append("新皮肤 · %s「%s」" % [
				String(cdef_skin.get("name", "角色")), String(theme.get("name", ""))])
		# 首次破境播报
		if prev_best_wave_char < GameManager.MILESTONE_WAVE:
			gm.last_run_new_records.append("首次破境 · %s" % String(cdef_skin.get("name", "角色")))

	if broke:
		# 生涯最高破境难度（成就进度「最高破境 X」口径，难度达成型成就判定不受它影响）
		gm.career_stats["best_danger_cleared"] = maxi(prev_best_danger, gm.danger_level)
		# 「万法由心」进度：本局携带随行技能破境累加
		if not gm.active_skill_id.is_empty():
			gm.career_stats["milestones_with_skill"] = int(gm.career_stats.get("milestones_with_skill", 0)) + 1

	var entry := {
		"cultivator_id": cid_rec,
		"danger": gm.danger_level,
		"wave": eff_wave,
		"kills": gm.kills,
		"level": gm.level,
		"time": gm.game_time,
		"record": eff_wave > prev_best_wave,
	}
	gm.run_history.push_front(entry)
	while gm.run_history.size() > MAX_HISTORY_ENTRIES:
		gm.run_history.pop_back()

	# 生涯新纪录：生成该局完整战报快照（白名单字段，剔除节点引用防炸档）
	if eff_wave > prev_best_wave:
		gm.record_log.push_front(_make_record_snapshot(gm, cid_rec, eff_wave))
		while gm.record_log.size() > gm.RECORD_LOG_CAP:
			gm.record_log.pop_back()

	# 新纪录文案（供结算弹窗展示）
	if gm.kills > prev_best_kills:
		gm.last_run_new_records.append("生涯新纪录 · 击杀 %d 只" % gm.kills)
	if eff_wave > prev_best_wave:
		gm.last_run_new_records.append("生涯新纪录 · 抵达第 %d 波" % eff_wave)

	var run_ctx := {
		"danger": gm.danger_level,
		"wave": eff_wave,
		"level": gm.level,
		"kills": gm.kills,
		"max_stones": eff_stones,
		"max_dodge": eff_dodge,
		"max_harvest": eff_harvest,
		"damage_taken_count": gm.total_damage_taken_count,
		"hp_healed": gm.total_hp_healed,
		"stones_spent": gm.total_stones_spent,
		"skill_casts": gm.skill_cast_count,
		"weapon_count": gm.owned_weapon_count(),
		"item_count": gm.items.size(),
		"max_summons": gm.max_concurrent_summons,
		"max_class_counts": gm.max_class_counts,
		"max_element_spread": gm.max_element_spread,
	}
	var ended_new := _settle_run_achievements(gm, run_ctx)
	save_from(gm)
	if not ended_new.is_empty():
		gm.achievements_unlocked.emit(ended_new)

## 结算成就收尾：只判定「结算这一刻新达成」的并追加。
## 局内 check_live_achievements 已经结掉的成就不再回判，但**保留在 last_run_new_achievements 里** ——
## 结算屏按整局汇总展示。旧写法在这里整体清空，结果中途解锁的成就只剩一闪而过的横幅，
## 结算页一张卡都不显示，玩家以为没解锁。
static func _settle_run_achievements(gm: Node, run_ctx: Dictionary) -> Array:
	var ended_new: Array = []
	for aid in AchievementData.evaluate_new_unlocks(run_ctx, gm.career_stats, gm.unlocked_achievements):
		gm.unlocked_achievements.append(aid)
		gm.last_run_new_achievements.append(aid)
		_apply_achievement_reward(gm, aid)
		ended_new.append(aid)
	return ended_new

## 局内成就即时判定（2026-10-25 解锁提示升级）：
## 只在回合结束时调一次（不是逐帧轮询），把「打到第 5 波」「攒够 100 金币」这类
## 本局中途就能满足的成就当场结掉 —— 玩家不用等到阵亡才知道自己解锁了什么。
## 与结算路径共用 evaluate_new_unlocks 与发奖逻辑，口径不会分叉。
## 返回本次新达成的成就 ID 列表（供 HUD 横幅逐条播报）。
static func check_live_achievements(gm: Node) -> Array[String]:
	var out: Array[String] = []
	if gm.author_mode or not gm.run_started or gm.is_game_over:
		return out
	var run_ctx := {
		"danger": gm.danger_level,
		"wave": gm.wave_number,
		"level": gm.level,
		"kills": gm.kills,
		"max_stones": maxi(gm.spirit_stones, gm.peak_stones),
		"max_dodge": maxf(gm.get_effective_dodge(), gm.peak_dodge),
		"max_harvest": maxf(gm.harvest, gm.peak_harvest),
		"damage_taken_count": gm.total_damage_taken_count,
		"hp_healed": gm.total_hp_healed,
		"stones_spent": gm.total_stones_spent,
		"skill_casts": gm.skill_cast_count,
		"weapon_count": gm.owned_weapon_count(),
		"item_count": gm.items.size(),
		"max_summons": gm.max_concurrent_summons,
		"max_class_counts": gm.max_class_counts,
		"max_element_spread": gm.max_element_spread,
	}
	for aid in AchievementData.evaluate_new_unlocks(run_ctx, gm.career_stats, gm.unlocked_achievements):
		gm.unlocked_achievements.append(aid)
		gm.last_run_new_achievements.append(aid)
		_apply_achievement_reward(gm, aid)
		out.append(aid)
	if not out.is_empty():
		save_from(gm)
		gm.achievements_unlocked.emit(out)
	return out

## 成就达成播报文案（局内横幅与结算屏共用一套口径，别在两处各拼一遍）
static func achievement_banner_text(aid: String) -> String:
	var adef := AchievementData.get_def(aid)
	if adef.is_empty():
		return ""
	var rtype := String(adef.get("reward_type", ""))
	var label := AchievementData.reward_label(adef)
	if label.is_empty():
		return "◆ 成就「%s」达成 ◆" % String(adef.get("name", ""))
	return "◆ 成就「%s」· %s：%s ◆" % [
		String(adef.get("name", "")), label, String(adef.get("reward_name", ""))]

## 发放成就奖励：按 reward_type 把对象塞进对应解锁池，并记一条未读标记供各界面挂「新」角标。
## "none" 纯荣誉型只点亮成就本身（2026-10-25 起已无条目使用，保留兜底分支）。
static func _apply_achievement_reward(gm: Node, aid: String) -> void:
	var adef := AchievementData.get_def(aid)
	var rtype := String(adef.get("reward_type", ""))
	var rid := String(adef.get("reward_id", ""))
	if rid.is_empty():
		return
	var added := false
	if rtype == "cultivator" and not (rid in gm.unlocked_cultivators):
		gm.unlocked_cultivators.append(rid)
		added = true
	elif rtype == "item" and not (rid in gm.unlocked_items):
		gm.unlocked_items.append(rid)
		added = true
	elif rtype == "weapon" and not (rid in gm.unlocked_weapons):
		gm.unlocked_weapons.append(rid)
		added = true
	if added:
		var key := GameManager.unlock_key(rtype, rid)
		if not (key in gm.unread_unlocks):
			gm.unread_unlocks.append(key)

## 历战实录快照（生涯新纪录那一局）：只取可序列化的白名单字段（name/star/icon 等纯数据，绝不带节点引用）
static func _make_record_snapshot(gm: Node, cid: String, wave: int) -> Dictionary:
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
