class_name RunSave
extends RefCounted

## 中断续玩（2026-10-15）：一局进度的落盘与恢复子系统
## 负责 user://run_save.cfg 的读写。与局外元进度（ProgressStore/progress.cfg）完全隔离：
## 局内档写坏半截不影响生涯/成就主档（同 EnemyCodex 的域隔离理由）。
##
## 设计口径：
## - 快照存「字段终值」，绝不重放 add_item/apply_upgrade —— 属性叠加被上限夹过、
##   道具退货回退有损，重放会失真；玩家血量终值也一并存，避免恢复路径重复施加加成。
## - 恢复只到「回合边界语义」：FIGHT/CLEARING 存为 FIGHT（本波从头打，波内收益以
##   最后一次 3 秒自动存为准）；ALLOC/SHOP 原样恢复（含候选卡/货架与锁定项）。
## - 技能 buff/战意/盾势/站定计时等瞬态不存，恢复即归零（对玩家有利）。
## - 新增单局成员时记得同步这里的存/读两侧（RunReset 头注同款提醒）；
##   tests/run_save_check.gd 用反射对账，漏存字段会报红。

const SAVE_PATH := "user://run_save.cfg"
const SAVE_VERSION: int = 1

## 最近一次 load_into 成功灌入的原始 payload（apply_player 重建玩家实体时消费）
static var _loaded_payload: Dictionary = {}

# ---------------- 对外入口 ----------------

## 是否有一份可恢复的存档（读 meta 区做轻校验，坏档视为无档）
static func has_save() -> bool:
	return has_save_at(SAVE_PATH)

static func has_save_at(path: String) -> bool:
	return not peek_at(path).is_empty()

## 读存档摘要（主菜单「继续游戏」/ 多存档列表共用）：无档/坏档返回空字典。
## payload 非空也在摘要层校验 —— 文件在但整包是空的坏档，列表直接标「损坏」，
## 不会等到玩家点「读档」才炸。
static func peek_at(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return {}
	var payload = cfg.get_value("run", "payload", null)
	if not (payload is Dictionary) or (payload as Dictionary).is_empty():
		return {}
	var wave := int(cfg.get_value("meta", "wave", 0))
	if wave < 1:
		return {}
	return {
		"wave": wave,
		"level": int(cfg.get_value("meta", "level", 1)),
		"cid": String(cfg.get_value("meta", "cid", "")),
		"danger": int(cfg.get_value("meta", "danger", 0)),
		"play_time": float(cfg.get_value("meta", "play_time", 0.0)),
		"time_unix": int(cfg.get_value("meta", "time_unix", 0)),
		"run_id": String(cfg.get_value("meta", "run_id", "")),
		"app_version": String(cfg.get_value("meta", "app_version", "")),
		"save_version": int(cfg.get_value("meta", "save_version", 0)),
	}

static func peek_summary() -> Dictionary:
	return peek_at(SAVE_PATH)

## 删除存档（阵亡结算后本局终结；返回主菜单不删 —— 那正是「不小心退出」的一种）
static func clear_save() -> void:
	clear_at(SAVE_PATH)

static func clear_at(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var dir := DirAccess.open(path.get_base_dir())
	if dir != null and dir.file_exists(path.get_file()):
		dir.remove(path.get_file())

## 阶段归并：WAITING/CLEARING 一律按 FIGHT 存（本波从头重打），其余原样保留。
## 自动存与手动存档位共用，别在第二处再抄一遍映射。
static func resolve_phase(gm: Node) -> int:
	if gm.wave_spawner == null:
		return WaveSpawner.Phase.FIGHT
	var phase: int = gm.wave_spawner.phase
	if phase == WaveSpawner.Phase.WAITING or phase == WaveSpawner.Phase.CLEARING:
		return WaveSpawner.Phase.FIGHT
	return phase

## 本局唯一标识的兜底：旧档（无 run_id）读入后补发一个，后续存档才能按局清理
static func ensure_run_id(gm: Node) -> String:
	var rid := String(gm.run_id)
	if rid.is_empty():
		rid = GameManager.make_run_id()
		gm.run_id = rid
	return rid

## 游戏内自动存档的统一入口（headless 判据一律不落盘，防测试污染真机档）。
## 阶段从 wave_spawner 现读：WAITING/CLEARING 归并进 FIGHT，ALLOC/SHOP 原样保留。
static func autosave_current(gm: Node) -> void:
	if DisplayServer.get_name() == "headless":
		return
	# 作者模式：不写中断续玩档。作弊局若留下快照，退出作者模式后「继续游戏」
	# 会以普通模式复现一份跳关/全解锁的存档 —— 会话级开关必须连局内档一起堵。
	if bool(gm.get("author_mode")):
		return
	save_from(gm, resolve_phase(gm))

## 落盘整局快照。phase 由调用方给定（测试直呼；游戏内走 autosave_current）。
static func save_from(gm: Node, phase: int) -> bool:
	return save_to(gm, phase, SAVE_PATH)

## 指定目标文件的落盘入口（多存档位复用同一份整包口径）。
static func save_to(gm: Node, phase: int, path: String) -> bool:
	if not gm.run_started or gm.is_game_over or gm.wave_number < 1:
		return false
	var p = gm.player
	if p == null or not is_instance_valid(p):
		return false
	var d := {}
	_dump_scalars(gm, d)
	_dump_collections(gm, d)
	# 玩家实体终值（血量三件套）+ 上阵悬浮武器（绝不能带 node 引用，防炸档）
	d["p_max_health"] = float(p.max_health)
	d["p_health"] = float(p.current_health)
	d["p_base_speed"] = float(p.base_speed)
	var ws := []
	if p.has_method("get_equipped_weapons_data"):
		for w in p.get_equipped_weapons_data():
			ws.append({"id": String(w.get("id", "")), "star": int(w.get("star", 1))})
	if ws.is_empty():
		# 该分支只在异常态（跑局中却拿不到上阵武器）触发，正常流程至少 1 把；静默会导致
		# 「自动存档看似在跑但从没落盘」的隐性丢档，必须留痕
		push_warning("RunSave: 上阵武器列表为空，本次局内存档跳过（wave=%d）" % gm.wave_number)
		return false
	d["weapons"] = ws
	d["phase"] = phase

	var cfg := ConfigFile.new()
	cfg.set_value("meta", "save_version", SAVE_VERSION)
	cfg.set_value("meta", "app_version", Version.APP_VERSION)
	cfg.set_value("meta", "time_unix", Time.get_unix_time_from_system())
	# 摘要三件套：主菜单「继续游戏」/ 多存档列表不解析整包 payload 就能出文案
	cfg.set_value("meta", "wave", gm.wave_number)
	cfg.set_value("meta", "level", gm.level)
	cfg.set_value("meta", "cid", gm.cultivator_id)
	# 多存档（2026-10-28）：难度/时长/本局唯一 id 只喂列表显示与阵亡清档，读档判定仍看 payload
	cfg.set_value("meta", "danger", gm.danger_level)
	cfg.set_value("meta", "play_time", gm.game_time)
	cfg.set_value("meta", "run_id", ensure_run_id(gm))
	cfg.set_value("run", "payload", d)
	var err := _atomic_save(cfg, path)
	if err != OK:
		push_warning("RunSave: 保存局内进度失败 err=%d path=%s，尝试重试" % [err, path])
		err = _atomic_save(cfg, path)
	if err != OK:
		push_warning("RunSave: 重试保存局内进度仍失败 err=%d path=%s（放弃，等下个存档点）" % [err, path])
		return false
	return true

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

## 灌回一局状态（仅 autoload 字段；玩家实体交给 apply_player）。
## 返回存档时的阶段（WaveSpawner.Phase.*），无档/坏档返回 -1。
## 2026-10-24 坏档可见化：无档（正常首次启动）保持静默；文件存在但解析/校验失败
## 一律 push_error 点名原因 —— 玩家报「续玩档丢了」时日志里能区分到底是哪种失败。
static func load_into(gm: Node) -> int:
	return load_from(gm, SAVE_PATH)

## 指定文件灌回（多存档位复用同一份校验/灌回口径）。
static func load_from(gm: Node, path: String) -> int:
	_loaded_payload = {}
	if not FileAccess.file_exists(path):
		return -1
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		push_error("RunSave: 续玩档存在但解析失败 path=%s（文件损坏或被截断），本次按无档处理" % path)
		return -1
	# 版本闸只告警不做迁移：目前新增的都是可选字段，缺字段按默认值读即可。
	# 真出现破坏性改版时，再在这里按 saved_ver 分支迁移（ProgressStore 是现成范式）。
	var saved_ver := int(cfg.get_value("meta", "save_version", 1))
	if saved_ver > SAVE_VERSION:
		push_warning("RunSave: 续玩档版本 %d 高于当前 %d，缺字段按默认值加载 path=%s" % [saved_ver, SAVE_VERSION, path])
	var d = cfg.get_value("run", "payload", {})
	if not (d is Dictionary):
		push_error("RunSave: 续玩档 payload 非字典（实得类型 %d）path=%s" % [typeof(d), path])
		return -1
	var data: Dictionary = d
	if data.is_empty() or int(data.get("wave_number", 0)) < 1:
		push_error("RunSave: 续玩档 payload 波数无效（wave_number=%s）path=%s" % [str(data.get("wave_number", "缺字段")), path])
		return -1
	if String(data.get("cultivator_id", "")).is_empty() \
			or CultivatorData.get_def(String(data.get("cultivator_id", ""))).is_empty():
		push_error("RunSave: 续玩档 cultivator_id 无效（%s）path=%s" % [String(data.get("cultivator_id", "")), path])
		return -1
	var ws = data.get("weapons", [])
	if not (ws is Array) or (ws as Array).is_empty():
		push_error("RunSave: 续玩档 weapons 非数组或为空 path=%s" % path)
		return -1
	_fill_scalars(gm, data)
	_fill_collections(gm, data)
	_loaded_payload = data
	return int(data.get("phase", WaveSpawner.Phase.FIGHT))

## 重建玩家实体：外观、上阵武器、御灵分身、随行灵兽、血量三件套。
## 必须在 load_into 之后调用（消费 _loaded_payload）；血量要在换装触发羁绊重算之后再覆写，
## 保证 _applied_hp_bonus 台账与羁绊重算口径一致、saved 终值不被二次加减。
static func apply_player(gm: Node) -> void:
	if _loaded_payload.is_empty():
		return
	var p = gm.player
	if p == null or not is_instance_valid(p):
		return
	# 外观：开局时 cultivator_id 为空把形象藏了，按存档道统重刷
	if p.has_method("_setup_sprite_frames"):
		p._setup_sprite_frames()
	# 清干净 weapon_holder 旧实例再按存档重挂：恢复可能发生在「本局已 start_run 过」
	# 的场景树上（如重开同进程），旧悬浮武器不清会叠出双份
	if p.has_method("equipped_cleanup"):
		p.equipped_cleanup()
		for c in p.weapon_holder.get_children():
			if is_instance_valid(c):
				p.weapon_holder.remove_child(c)
				c.free()
	# 上阵悬浮武器：直接挂实例，不走 WeaponInventory.add_weapon（免得空槽判断进背包）
	for w in _loaded_payload.get("weapons", []):
		var w_id := String(w.get("id", ""))
		if w_id.is_empty() or WeaponData.get_def(w_id).is_empty():
			continue
		if p.has_method("add_weapon_instance"):
			p.add_weapon_instance(w_id, int(w.get("star", 1)))
	# 通知链：recalc_synergies 重算羁绊（阈值字段已灌回）+ HUD 武器排重建 + 峰值账本
	gm.notify_weapons_updated(gm.get_weapons_summary())
	# 御灵分身与随行灵兽（数据数组已灌回，同步幂等）
	if p.has_method("sync_drones"):
		p.sync_drones()
	PetSystem.sync_pet_instances(gm)
	if p.has_method("_sync_pickup_radius"):
		p._sync_pickup_radius()
	# 血量终值最后覆写：羁绊重算的 +max_hp 已计过台账，这里不许再叠加
	p.max_health = float(_loaded_payload.get("p_max_health", p.max_health))
	p.current_health = clampf(float(_loaded_payload.get("p_health", p.max_health)), 1.0, p.max_health)
	p.base_speed = float(_loaded_payload.get("p_base_speed", p.base_speed))

# ---------------- 标量收集 / 灌回（显式类型化，与 RunReset 同一门规） ----------------

static func _dump_scalars(gm: Node, d: Dictionary) -> void:
	# —— 一局进度标量 ——
	d["kills"] = gm.kills
	d["game_time"] = gm.game_time
	d["spirit_stones"] = gm.spirit_stones
	d["level"] = gm.level
	d["experience"] = gm.experience
	d["experience_to_next"] = gm.experience_to_next
	d["pending_upgrade_points"] = gm.pending_upgrade_points
	d["wave_number"] = gm.wave_number
	d["run_started"] = gm.run_started
	d["danger_level"] = gm.danger_level
	d["peak_stones"] = gm.peak_stones
	d["peak_dodge"] = gm.peak_dodge
	d["peak_harvest"] = gm.peak_harvest
	d["cultivator_id"] = gm.cultivator_id
	d["run_id"] = gm.run_id
	# —— 隐藏账本（突破古玉成长 / 经验门槛链 / 玉匣送出计数 / 主流派保底计数）——
	d["_exp_chain"] = gm._exp_chain
	d["chest_item_grants"] = gm.chest_item_grants
	d["_no_main_tag_waves"] = gm._no_main_tag_waves
	d["_no_main_item_waves"] = gm._no_main_item_waves
	# —— 属性加点/道具层终值 ——
	d["weapon_damage_mult"] = gm.weapon_damage_mult
	d["melee_damage"] = gm.melee_damage
	d["ranged_damage"] = gm.ranged_damage
	d["elemental_damage"] = gm.elemental_damage
	d["engineering_damage"] = gm.engineering_damage
	d["contraption_damage"] = gm.contraption_damage
	d["attack_speed_mult"] = gm.attack_speed_mult
	d["move_speed_mult"] = gm.move_speed_mult
	d["pickup_range_mult"] = gm.pickup_range_mult
	d["attack_range_mult"] = gm.attack_range_mult
	d["armor"] = gm.armor
	d["hp_regen"] = gm.hp_regen
	d["crit_rate"] = gm.crit_rate
	d["crit_mult"] = gm.crit_mult
	d["dodge"] = gm.dodge
	d["lifesteal"] = gm.lifesteal
	d["luck"] = gm.luck
	d["harvest"] = gm.harvest
	d["xp_gain_mult"] = gm.xp_gain_mult
	d["knockback_mult"] = gm.knockback_mult
	d["elite_damage"] = gm.elite_damage
	d["skill_cooldown_mult"] = gm.skill_cooldown_mult
	d["free_rerolls"] = gm.free_rerolls
	d["stat_bonus_pierce"] = gm.stat_bonus_pierce
	# —— 宝箱 / 灵兽层 ——
	d["chest_count_bonus"] = gm.chest_count_bonus
	d["chest_quality"] = gm.chest_quality
	d["chest_break_bonus"] = gm.chest_break_bonus
	d["chest_reward_mult"] = gm.chest_reward_mult
	d["pet_slots_bonus"] = gm.pet_slots_bonus
	d["pet_damage_mult"] = gm.pet_damage_mult
	d["pet_effect_mult"] = gm.pet_effect_mult
	d["pet_cooldown_mult"] = gm.pet_cooldown_mult
	d["pet_offer_chance_bonus"] = gm.pet_offer_chance_bonus
	# —— 角色流派特性终值 ——
	d["thorns_pct"] = gm.thorns_pct
	d["spirit_threshold_adj"] = gm.spirit_threshold_adj
	d["contraption_threshold_adj"] = gm.contraption_threshold_adj
	d["dodge_cap_bonus"] = gm.dodge_cap_bonus
	d["weapon_slots_override"] = gm.weapon_slots_override
	d["enemy_count_mult"] = gm.enemy_count_mult
	d["harvest_decay"] = gm.harvest_decay
	d["xp_require_mult"] = gm.xp_require_mult
	d["item_price_mult"] = gm.item_price_mult
	d["shop_slots_bonus"] = gm.shop_slots_bonus
	d["stone_interest_rate"] = gm.stone_interest_rate
	d["stone_interest_cap"] = gm.stone_interest_cap
	d["on_hit_damage_bonus"] = gm.on_hit_damage_bonus
	d["on_hit_damage_cap_stacks"] = gm.on_hit_damage_cap_stacks
	d["guard_stance"] = gm.guard_stance
	d["shield_hp"] = gm.shield_hp   ## 血海护盾存量：跨回合保留，随档存取（区别于盾势 shield_charge 的当帧蓄能豁免）
	d["heal_orb_chance"] = gm.heal_orb_chance
	d["heal_overflow_mult"] = gm.heal_overflow_mult
	d["alloc_offer_bonus"] = gm.alloc_offer_bonus
	d["alloc_free_reroll_bonus"] = gm.alloc_free_reroll_bonus
	d["collection_damage_per_unique"] = gm.collection_damage_per_unique
	d["unique_item_count"] = gm.unique_item_count
	d["frenzy_enabled"] = gm.frenzy_enabled
	d["thunder_strike"] = gm.thunder_strike
	d["reroll_price_mult"] = gm.reroll_price_mult
	d["crowd_damage_per_enemy"] = gm.crowd_damage_per_enemy
	d["crowd_damage_cap"] = gm.crowd_damage_cap
	d["crowd_damage_radius"] = gm.crowd_damage_radius
	d["stone_damage_per_100"] = gm.stone_damage_per_100
	d["stone_damage_cap"] = gm.stone_damage_cap
	d["kill_cd_reduction_normal"] = gm.kill_cd_reduction_normal
	d["kill_cd_reduction_elite"] = gm.kill_cd_reduction_elite
	d["kuxingseng_mode"] = gm.kuxingseng_mode
	d["still_damage_bonus"] = gm.still_damage_bonus
	d["still_haste_bonus"] = gm.still_haste_bonus
	d["still_armor_bonus"] = gm.still_armor_bonus
	d["still_pickup_bonus"] = gm.still_pickup_bonus
	d["still_regen_bonus"] = gm.still_regen_bonus
	d["move_damage_penalty"] = gm.move_damage_penalty
	d["move_haste_penalty"] = gm.move_haste_penalty
	d["total_damage_taken_count"] = gm.total_damage_taken_count
	d["total_stones_spent"] = gm.total_stones_spent
	d["skill_cast_count"] = gm.skill_cast_count
	d["total_hp_healed"] = gm.total_hp_healed
	d["max_concurrent_summons"] = gm.max_concurrent_summons
	d["max_element_spread"] = gm.max_element_spread
	# —— 技能（extra_skill_id 理论上随角色可派生，直接存省派生链）——
	d["pending_skill_id"] = gm.pending_skill_id
	d["active_skill_id"] = gm.active_skill_id
	d["extra_skill_id"] = gm.extra_skill_id
	# —— 商店会话（FIGHT 档下这些是旧值也无妨：下一波 roll_shop(true) 会重置）——
	d["shop_price_mult"] = gm.shop_price_mult
	d["reroll_cost"] = gm.reroll_cost
	d["reroll_count"] = gm.reroll_count
	d["reroll_free_left"] = gm.reroll_free_left
	d["reroll_price_mult"] = gm.reroll_price_mult
	# —— 悟道会话 ——
	d["alloc_points_total"] = gm.alloc_points_total
	d["alloc_reroll_cost"] = gm.alloc_reroll_cost
	d["alloc_reroll_count"] = gm.alloc_reroll_count
	d["alloc_reroll_free_left"] = gm.alloc_reroll_free_left

static func _dump_collections(gm: Node, d: Dictionary) -> void:
	d["element_damage"] = gm.element_damage.duplicate()
	d["locked_upgrades"] = gm.locked_upgrades.duplicate()
	d["max_class_counts"] = gm.max_class_counts.duplicate()
	d["_wave_end_growth"] = gm._wave_end_growth.duplicate()
	d["upgrade_counts"] = gm.upgrade_counts.duplicate()
	d["shop_tag_filter"] = gm.shop_tag_filter.duplicate()
	d["shop_offers"] = gm.shop_offers.duplicate(true)
	d["items"] = gm.items.duplicate()
	d["items_bought"] = gm.items_bought.duplicate()
	d["pets"] = gm.pets.duplicate()
	d["drones"] = gm.drones.duplicate(true)
	d["stash"] = gm.stash.duplicate(true)
	# 定型数组：整包快照（元素含 Color，ConfigFile 原生支持）
	d["alloc_offers"] = gm.alloc_offers.duplicate(true)
	d["upgrade_history"] = gm.upgrade_history.duplicate(true)
	# 超级悟道（2026-10-25）：已结算关卡 / 已拿卡 / 当前候选（面板开着时退出要原样重建）
	d["super_alloc_offers"] = gm.super_alloc_offers.duplicate(true)
	d["super_alloc_done_waves"] = gm.super_alloc_done_waves.duplicate()
	d["super_cards_taken"] = gm.super_cards_taken.duplicate()

static func _fill_scalars(gm: Node, d: Dictionary) -> void:
	gm.kills = int(d.get("kills", 0))
	gm.game_time = float(d.get("game_time", 0.0))
	gm.spirit_stones = int(d.get("spirit_stones", 0))
	gm.level = int(d.get("level", 1))
	gm.experience = int(d.get("experience", 0))
	gm.experience_to_next = int(d.get("experience_to_next", GameBalance.EXP_FIRST_LEVEL))
	gm.pending_upgrade_points = int(d.get("pending_upgrade_points", 0))
	gm.wave_number = int(d.get("wave_number", 1))
	gm.run_started = bool(d.get("run_started", true))
	# 老中断档可能存着收缩前的 D4/D5（2026-10-20 难度收为 4 档），夹回顶档再继续
	gm.danger_level = clampi(int(d.get("danger_level", 0)), 0, GameBalance.DANGER_MAX)
	gm.peak_stones = int(d.get("peak_stones", 0))
	gm.peak_dodge = float(d.get("peak_dodge", 0.0))
	gm.peak_harvest = float(d.get("peak_harvest", 0.0))
	gm.cultivator_id = String(d.get("cultivator_id", ""))
	gm.run_id = String(d.get("run_id", ""))
	ensure_run_id(gm)  # 旧档无 run_id：补发一个，后续阵亡才能按局清手动档
	gm._exp_chain = int(d.get("_exp_chain", GameBalance.EXP_FIRST_LEVEL))
	gm.chest_item_grants = int(d.get("chest_item_grants", 0))
	gm._no_main_tag_waves = int(d.get("_no_main_tag_waves", 0))
	gm._no_main_item_waves = int(d.get("_no_main_item_waves", 0))
	gm.weapon_damage_mult = float(d.get("weapon_damage_mult", 1.0))
	gm.melee_damage = float(d.get("melee_damage", 0.0))
	gm.ranged_damage = float(d.get("ranged_damage", 0.0))
	gm.elemental_damage = float(d.get("elemental_damage", 0.0))
	gm.engineering_damage = float(d.get("engineering_damage", 0.0))
	gm.contraption_damage = float(d.get("contraption_damage", 0.0))
	gm.attack_speed_mult = float(d.get("attack_speed_mult", 1.0))
	gm.move_speed_mult = float(d.get("move_speed_mult", 1.0))
	gm.pickup_range_mult = float(d.get("pickup_range_mult", 1.0))
	gm.attack_range_mult = float(d.get("attack_range_mult", 1.0))
	gm.armor = float(d.get("armor", 0.0))
	gm.hp_regen = float(d.get("hp_regen", 0.0))
	gm.crit_rate = float(d.get("crit_rate", 0.05))
	gm.crit_mult = float(d.get("crit_mult", 1.5))
	gm.dodge = float(d.get("dodge", 0.0))
	gm.lifesteal = float(d.get("lifesteal", 0.0))
	gm.luck = float(d.get("luck", 0.0))
	gm.harvest = float(d.get("harvest", 0.0))
	gm.xp_gain_mult = float(d.get("xp_gain_mult", 1.0))
	gm.knockback_mult = float(d.get("knockback_mult", 1.0))
	gm.elite_damage = float(d.get("elite_damage", 0.0))
	gm.skill_cooldown_mult = float(d.get("skill_cooldown_mult", 0.0))
	gm.free_rerolls = int(d.get("free_rerolls", 0))
	gm.stat_bonus_pierce = int(d.get("stat_bonus_pierce", 0))
	gm.chest_count_bonus = int(d.get("chest_count_bonus", 0))
	gm.chest_quality = float(d.get("chest_quality", 0.0))
	gm.chest_break_bonus = int(d.get("chest_break_bonus", 0))
	gm.chest_reward_mult = float(d.get("chest_reward_mult", 1.0))
	gm.pet_slots_bonus = int(d.get("pet_slots_bonus", 0))
	gm.pet_damage_mult = float(d.get("pet_damage_mult", 1.0))
	gm.pet_effect_mult = float(d.get("pet_effect_mult", 1.0))
	gm.pet_cooldown_mult = float(d.get("pet_cooldown_mult", 1.0))
	gm.pet_offer_chance_bonus = float(d.get("pet_offer_chance_bonus", 0.0))
	gm.thorns_pct = float(d.get("thorns_pct", 0.0))
	gm.spirit_threshold_adj = int(d.get("spirit_threshold_adj", 0))
	gm.contraption_threshold_adj = int(d.get("contraption_threshold_adj", 0))
	gm.dodge_cap_bonus = float(d.get("dodge_cap_bonus", 0.0))
	gm.weapon_slots_override = int(d.get("weapon_slots_override", 0))
	gm.enemy_count_mult = float(d.get("enemy_count_mult", 1.0))
	gm.harvest_decay = float(d.get("harvest_decay", 0.0))
	gm.xp_require_mult = float(d.get("xp_require_mult", 1.0))
	gm.item_price_mult = float(d.get("item_price_mult", 1.0))
	gm.shop_slots_bonus = int(d.get("shop_slots_bonus", 0))
	gm.stone_interest_rate = float(d.get("stone_interest_rate", 0.0))
	gm.stone_interest_cap = int(d.get("stone_interest_cap", 30))
	gm.on_hit_damage_bonus = float(d.get("on_hit_damage_bonus", 0.0))
	gm.on_hit_damage_cap_stacks = int(d.get("on_hit_damage_cap_stacks", 10))
	gm.guard_stance = float(d.get("guard_stance", 0.0))
	gm.shield_hp = float(d.get("shield_hp", 0.0))
	gm.heal_orb_chance = float(d.get("heal_orb_chance", 0.0))
	gm.heal_overflow_mult = float(d.get("heal_overflow_mult", 1.0))
	gm.alloc_offer_bonus = int(d.get("alloc_offer_bonus", 0))
	gm.alloc_free_reroll_bonus = int(d.get("alloc_free_reroll_bonus", 0))
	gm.collection_damage_per_unique = float(d.get("collection_damage_per_unique", 0.0))
	gm.unique_item_count = int(d.get("unique_item_count", 0))
	gm.frenzy_enabled = float(d.get("frenzy_enabled", 0.0))
	gm.thunder_strike = float(d.get("thunder_strike", 0.0))
	gm.reroll_price_mult = float(d.get("reroll_price_mult", 1.0))
	gm.crowd_damage_per_enemy = float(d.get("crowd_damage_per_enemy", 0.0))
	gm.crowd_damage_cap = float(d.get("crowd_damage_cap", 0.0))
	gm.crowd_damage_radius = float(d.get("crowd_damage_radius", 0.0))
	gm.stone_damage_per_100 = float(d.get("stone_damage_per_100", 0.0))
	gm.stone_damage_cap = float(d.get("stone_damage_cap", 0.0))
	gm.kill_cd_reduction_normal = float(d.get("kill_cd_reduction_normal", 0.0))
	gm.kill_cd_reduction_elite = float(d.get("kill_cd_reduction_elite", 0.0))
	gm.kuxingseng_mode = float(d.get("kuxingseng_mode", 0.0))
	gm.still_damage_bonus = float(d.get("still_damage_bonus", 0.0))
	gm.still_haste_bonus = float(d.get("still_haste_bonus", 0.0))
	gm.still_armor_bonus = float(d.get("still_armor_bonus", 0.0))
	gm.still_pickup_bonus = float(d.get("still_pickup_bonus", 0.0))
	gm.still_regen_bonus = float(d.get("still_regen_bonus", 0.0))
	gm.move_damage_penalty = float(d.get("move_damage_penalty", 0.0))
	gm.move_haste_penalty = float(d.get("move_haste_penalty", 0.0))
	gm.total_damage_taken_count = int(d.get("total_damage_taken_count", 0))
	gm.total_stones_spent = int(d.get("total_stones_spent", 0))
	gm.skill_cast_count = int(d.get("skill_cast_count", 0))
	gm.total_hp_healed = float(d.get("total_hp_healed", 0.0))
	gm.max_concurrent_summons = int(d.get("max_concurrent_summons", 0))
	gm.max_element_spread = int(d.get("max_element_spread", 0))
	gm.pending_skill_id = String(d.get("pending_skill_id", "dash"))
	gm.active_skill_id = String(d.get("active_skill_id", ""))
	gm.extra_skill_id = String(d.get("extra_skill_id", ""))
	gm.shop_price_mult = float(d.get("shop_price_mult", 1.0))
	gm.reroll_cost = int(d.get("reroll_cost", 2))
	gm.reroll_count = int(d.get("reroll_count", 0))
	gm.reroll_free_left = int(d.get("reroll_free_left", 0))
	gm.alloc_points_total = int(d.get("alloc_points_total", 0))
	gm.alloc_reroll_cost = int(d.get("alloc_reroll_cost", 2))
	gm.alloc_reroll_count = int(d.get("alloc_reroll_count", 0))
	gm.alloc_reroll_free_left = int(d.get("alloc_reroll_free_left", 0))

static func _fill_collections(gm: Node, d: Dictionary) -> void:
	var elem = d.get("element_damage", null)
	if elem is Dictionary:
		gm.element_damage = (elem as Dictionary).duplicate()
	var bcc = d.get("max_class_counts", null)
	if bcc is Dictionary:
		gm.max_class_counts = (bcc as Dictionary).duplicate()
	var weg = d.get("_wave_end_growth", null)
	if weg is Dictionary:
		gm._wave_end_growth = (weg as Dictionary).duplicate()
	var ucs = d.get("upgrade_counts", null)
	if ucs is Dictionary:
		gm.upgrade_counts = (ucs as Dictionary).duplicate()
	for f in ["locked_upgrades", "shop_tag_filter", "shop_offers", "items", "items_bought", "pets", "drones", "stash"]:
		var arr = d.get(f, null)
		if arr is Array:
			gm.set(f, (arr as Array).duplicate(true))
	# 超级悟道三个定型数组：同样原地重建（Array[int] / Array[String] / Array[Dictionary]）
	var sdo = d.get("super_alloc_offers", null)
	gm.super_alloc_offers.clear()
	if sdo is Array:
		for e in sdo:
			if e is Dictionary:
				# 候选里可能有旧版本已删除的卡（2026-10-25 卡池从 34 张缩到 18 张并改道途制）：
				# 按当前卡表过滤，面板不会铺出查不到定义的空卡。
				if SuperUpgradeData.get_def(String((e as Dictionary).get("id", ""))).is_empty():
					continue
				gm.super_alloc_offers.append(e)
	var sdw = d.get("super_alloc_done_waves", null)
	gm.super_alloc_done_waves.clear()
	if sdw is Array:
		for w in sdw:
			gm.super_alloc_done_waves.append(int(w))
	var sct = d.get("super_cards_taken", null)
	gm.super_cards_taken.clear()
	if sct is Array:
		for c in sct:
			gm.super_cards_taken.append(String(c))
	# 背包条目是购买时刻的字段快照（id/name/star/icon/tag 整包存盘）：跨版本更新若改过
	# 武器图标/文案，老档会顶着旧图，而货架卡读实时表 ⇒ 商店上下面不上（2026-10-24 灵兽
	# 图标不同款问题的武器版）。还原后按实时表重刷可刷字段（id/star 保留）；表里已查不到
	# 的陈旧 id 原样保留，别把玩家仅存的旧件刷成空白。
	for e in (gm.stash as Array):
		if not (e is Dictionary):
			continue
		var se: Dictionary = e
		var s_def := WeaponData.get_def(String(se.get("id", "")))
		if s_def.is_empty():
			continue
		for k in ["name", "icon", "tag"]:
			var sv: String = s_def.get(k, "")
			if not sv.is_empty():
				se[k] = sv
	# 定型数组不能整包赋值（Array[Dictionary] 通道），只能原地清空再逐个塞
	var offers = d.get("alloc_offers", null)
	gm.alloc_offers.clear()
	if offers is Array:
		for e in offers:
			if e is Dictionary:
				gm.alloc_offers.append(e)
	var hist = d.get("upgrade_history", null)
	gm.upgrade_history.clear()
	if hist is Array:
		for e in hist:
			if e is Dictionary:
				gm.upgrade_history.append(e)
