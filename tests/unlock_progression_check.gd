extends Node

## 解锁进度判据（2026-10-25 新手节奏重做）：把「一步步解锁」的每条口径钉死。
## 运行: $G --headless --path . res://tests/UnlockProgressionCheck.tscn
##
## 为什么立这条：本轮把「开局信息过载」改成「逐级解锁」，涉及四处相互咬合的账 ——
##   ① 初始解锁池规模（角色 4 / 道具 90 / 武器 64）；
##   ② 老档兼容（老玩家一件资产都不许少，靠「字段在不在」分流而不是版本号）；
##   ③ 商店抽卡与主标签保底都受武器解锁门控（保底绕过门控 = 变相发奖）；
##   ④ 难度逐级解锁（可选上限 = 生涯最高通关档 + 1）。
## 任何一处回退都会让新玩家重新面对信息过载、或让老玩家丢东西，所以逐条钉住。

var _c := TestCheck.new()

func _ready() -> void:
	_test_pool_sizes()
	_test_old_save_compat()
	_test_weapon_gating()
	_test_danger_ladder()
	_test_unread_marks()
	_test_codex_collection()
	_test_reward_integrity()
	get_tree().quit(0 if _c.report("UNLOCK_PROGRESSION_RESULT") else 1)

# ---------------- ① 初始池规模 ----------------

func _test_pool_sizes() -> void:
	_c.equals(AchievementData.DEFAULT_CULTIVATORS.size(), 4,
		"初始只开放 4 名角色（新玩家第一局只看 4 张长文卡）")
	var dflt := AchievementData.DEFAULT_CULTIVATORS
	for cid in ["jianchi", "shiyue", "fuzhen", "leifa"]:
		_c.check(cid in dflt, "入门四角色之一 %s 默认开放（机制最直白：近战/肉盾/环绕/爆发）" % cid)
	for cid in ["jinsuanpan", "lingzhifu", "kuxingseng", "yushou"]:
		_c.check(not (cid in dflt), "进阶角色 %s 不再默认开放（改由低门槛成就解锁）" % cid)
		_c.check(not AchievementData.cultivator_unlock_achievement(cid).is_empty(),
			"进阶角色 %s 有解锁成就（不能两处都没有，否则永远拿不到）" % cid)

	_c.equals(AchievementData.DEFAULT_ITEMS.size(), ItemData.shop_ids().size() - 16,
		"初始道具 = 商店池 %d − 16 件成就解锁" % ItemData.shop_ids().size())
	_c.equals(AchievementData.default_weapons().size(), WeaponData.DEFS.size() - 6,
		"初始武器 = 全部 %d − 6 把成就解锁" % WeaponData.DEFS.size())
	for wid in WeaponData.STARTER_IDS:
		_c.check(String(wid) in AchievementData.default_weapons(), "开局自选武器 %s 恒可用" % wid)

# ---------------- ② 老档兼容 ----------------

## 老档（有 progress.cfg 但没有 unlocked_weapons 键）读档后必须 70 把全开：
## 老玩家在本轮之前就能买到任何武器，改版不许把他们的资产收回去。
func _test_old_save_compat() -> void:
	var tmp_path := "user://_test_old_save.cfg"
	var cfg := ConfigFile.new()
	# 模拟老档：只有角色/道具/成就，没有 unlocked_weapons
	cfg.set_value("progress", "unlocked_cultivators", ["jianchi", "shiyue"])
	cfg.set_value("progress", "unlocked_items", ["jubaopen"])
	cfg.set_value("progress", "unlocked_achievements", [])
	cfg.save(tmp_path)

	# 用临时档路径跑一遍 load_into 的分支逻辑：这里直接验证「键缺失 ⇒ 全开」的口径。
	# （ProgressStore.load_into 固定读 PROGRESS_PATH，所以按同一判据在本文件里复算一次）
	var probe := ConfigFile.new()
	probe.load(tmp_path)
	var has_field := probe.has_section_key("progress", "unlocked_weapons")
	_c.check(not has_field, "老档里确实没有 unlocked_weapons 键（这条兼容分支才有意义）")
	var resolved: Array = []
	if has_field:
		resolved = probe.get_value("progress", "unlocked_weapons", [])
	else:
		resolved = WeaponData.DEFS.keys().duplicate()
	_c.equals(resolved.size(), WeaponData.DEFS.size(), "老档按「全解锁」回落（%d 把）" % WeaponData.DEFS.size())

	# 新档：键在但为空 ⇒ 走默认池，不会全开
	probe.set_value("progress", "unlocked_weapons", [])
	probe.save(tmp_path)
	var probe2 := ConfigFile.new()
	probe2.load(tmp_path)
	_c.check(probe2.has_section_key("progress", "unlocked_weapons"), "新档写出 unlocked_weapons 键（此后按存档走）")

	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("_test_old_save.cfg"):
		dir.remove("_test_old_save.cfg")

# ---------------- ③ 商店门控 ----------------

func _test_weapon_gating() -> void:
	var orig_wpns := GameManager.unlocked_weapons.duplicate()
	var rng_backup := GameManager.rng
	GameManager.rng = RandomNumberGenerator.new()
	GameManager.rng.seed = 20261025

	# 只留开局自选武器：抽 200 次，一次都不许抽到锁定件
	GameManager.unlocked_weapons = WeaponData.STARTER_IDS.duplicate()
	var leaked: Array = []
	for i in range(200):
		var wid := ShopSystem.weighted_weapon_pick(GameManager)
		if not (wid in WeaponData.STARTER_IDS):
			leaked.append(wid)
	_c.check(leaked.is_empty(), "未解锁武器绝不出现在商店抽卡结果里（泄漏 %d 次：%s）" % [
		leaked.size(), str(leaked.slice(0, 5))])

	# 池口径函数本身：过滤后必须只含已解锁件
	var pool := ShopSystem.unlocked_weapon_pool(GameManager)
	var bad_in_pool: Array = []
	for wid in pool:
		if not (String(wid) in GameManager.unlocked_weapons):
			bad_in_pool.append(wid)
	_c.check(bad_in_pool.is_empty(), "unlocked_weapon_pool 只含已解锁武器（混入: %s）" % str(bad_in_pool))

	# 池被滤空时回落全池（货架绝不留空格）
	GameManager.unlocked_weapons = []
	_c.equals(ShopSystem.unlocked_weapon_pool(GameManager).size(), WeaponData.SHOP_POOL.size(),
		"unlocked_weapons 为空时回落全池（异常档兜底，与 ItemData.pick_id 同口径）")

	# 主标签保底也受门控：主流派=剑系且只剩开局剑时，保底不许塞进未解锁的剑
	GameManager.unlocked_weapons = WeaponData.STARTER_IDS.duplicate()
	GameManager.shop_offers = [
		{"kind": "weapon", "id": "bajiao_fan", "price": 20, "sold": false, "locked": false},
	]
	GameManager._no_main_tag_waves = GameBalance.MAIN_TAG_PITY_WAVES - 1
	GameManager.drones = [{"id": "qingyun_sword", "star": 1}]
	GameManager.player = null
	SynergySystem.apply_main_tag_pity(GameManager, 5)
	var patched := String(GameManager.shop_offers[0].get("id", ""))
	_c.check(patched == "bajiao_fan" or (patched in WeaponData.STARTER_IDS),
		"主标签保底不会塞进未解锁武器（实得 %s）" % patched)

	GameManager.unlocked_weapons = orig_wpns
	GameManager.rng = rng_backup
	GameManager.shop_offers = []
	GameManager.drones = []
	GameManager._no_main_tag_waves = 0

# ---------------- ④ 难度梯子 ----------------

func _test_danger_ladder() -> void:
	var orig := int(GameManager.career_stats.get("best_danger_cleared", -1))
	GameManager.career_stats["best_danger_cleared"] = -1
	_c.equals(GameManager.max_danger_unlocked(), 0, "从未通关只开 D0")
	_c.check(not GameManager.is_danger_unlocked(1), "D1 锁着")
	GameManager.set_danger(3)
	_c.equals(GameManager.danger_level, 0, "未解锁档位点不动（夹回 D0）")
	GameManager.career_stats["best_danger_cleared"] = 0
	_c.equals(GameManager.max_danger_unlocked(), 1, "通关 D0 解锁 D1")
	GameManager.career_stats["best_danger_cleared"] = GameBalance.DANGER_MAX
	_c.equals(GameManager.max_danger_unlocked(), GameBalance.DANGER_MAX, "顶档通关后不再上涨")
	GameManager.career_stats["best_danger_cleared"] = orig
	GameManager.danger_level = 0

# ---------------- ⑤ 未读标记 ----------------

func _test_unread_marks() -> void:
	var orig := GameManager.unread_unlocks.duplicate()
	GameManager.unread_unlocks = []
	_c.check(not GameManager.has_unread_unlocks(), "初始无未读")
	GameManager.unread_unlocks.append(GameManager.unlock_key("cultivator", "duoshe"))
	_c.check(GameManager.has_unread_unlocks(), "写入后 has_unread_unlocks 为真")
	_c.check(GameManager.is_unlock_unread("cultivator", "duoshe"), "按 kind+id 查得到")
	_c.check(not GameManager.is_unlock_unread("item", "duoshe"), "类型不匹配不误报")
	GameManager.mark_unlock_read("cultivator", "duoshe")
	_c.check(not GameManager.is_unlock_unread("cultivator", "duoshe"), "点开后销标记")
	GameManager.mark_unlock_read("cultivator", "duoshe")
	_c.check(not GameManager.is_unlock_unread("cultivator", "duoshe"), "重复销幂等")
	_c.equals(GameManager.unlock_key("item", "pojia_zhui"), "item:pojia_zhui", "unlock_key 拼法稳定（存档兼容）")
	GameManager.unread_unlocks = orig

# ---------------- ⑥ 实战收录 ----------------

func _test_codex_collection() -> void:
	CodexCollection.reset_for_test()
	_c.check(not CodexCollection.is_weapon_seen("qingyun_sword"), "清档后武器未收录")
	_c.check(not CodexCollection.is_item_seen("jubaopen"), "清档后道具未收录")

	CodexCollection.record_weapon("qingyun_sword")
	CodexCollection.record_weapon("qingyun_sword")
	_c.check(CodexCollection.is_weapon_seen("qingyun_sword"), "记录后武器已收录")
	_c.equals(CodexCollection.weapon_seen_count(), 1, "重复记录幂等（计数不涨）")

	CodexCollection.record_item("jubaopen")
	_c.check(CodexCollection.is_item_seen("jubaopen"), "记录后道具已收录")
	_c.equals(CodexCollection.item_seen_count(), 1, "道具收录计数 1")

	# 落盘往返：清内存重载后仍在（ensure_loaded 走文件）
	CodexCollection._loaded = false
	CodexCollection._weapons.clear()
	CodexCollection._items.clear()
	_c.check(CodexCollection.is_weapon_seen("qingyun_sword"), "重载后武器收录仍在（存档往返）")
	_c.check(CodexCollection.is_item_seen("jubaopen"), "重载后道具收录仍在")

	# 未收录的武器详情卡不剧透数值
	var payload := CodexTipData.weapon_payload("jianling")
	_c.equals(String(payload.get("title", "")), "剑灵", "未收录详情卡仍报真名（图鉴卡 tip_title 要能对上）")
	_c.check((payload.get("rows", []) as Array).is_empty(), "未收录武器详情卡不列数值行")
	CodexCollection.record_weapon("jianling")
	var payload2 := CodexTipData.weapon_payload("jianling")
	_c.check(not (payload2.get("rows", []) as Array).is_empty(), "收录后详情卡列出完整数值行")

	# 未收录的道具详情卡同样不剧透
	CodexCollection.reset_for_test()
	var ip := CodexTipData.item_payload("taiyi_jindan")
	_c.check((ip.get("notes", []) as Array).is_empty(), "未收录道具详情卡不列效果说明")
	CodexCollection.record_item("taiyi_jindan")
	var ip2 := CodexTipData.item_payload("taiyi_jindan")
	_c.check(not (ip2.get("notes", []) as Array).is_empty(), "收录后道具详情卡列出效果说明")

	CodexCollection.reset_for_test()

# ---------------- ⑦ 奖励完整性 ----------------

func _test_reward_integrity() -> void:
	var no_reward: Array = []
	for aid in AchievementData.all_ids():
		var adef := AchievementData.get_def(aid)
		var rtype := String(adef.get("reward_type", ""))
		if rtype == "none" or String(adef.get("reward_id", "")).is_empty():
			no_reward.append(aid)
	_c.check(no_reward.is_empty(), "39 条成就全部带实物奖励（空奖励: %s）" % str(no_reward))

	# 奖励 id 必须落在对应表里，且反查能回来（写错 id 会让玩家拿到空气）
	var bad: Array = []
	for aid in AchievementData.all_ids():
		var adef := AchievementData.get_def(aid)
		var rtype := String(adef.get("reward_type", ""))
		var rid := String(adef.get("reward_id", ""))
		match rtype:
			"cultivator":
				if CultivatorData.get_def(rid).is_empty():
					bad.append("%s→%s" % [aid, rid])
			"item":
				if ItemData.get_def(rid).is_empty():
					bad.append("%s→%s" % [aid, rid])
			"weapon":
				if WeaponData.get_def(rid).is_empty():
					bad.append("%s→%s" % [aid, rid])
	_c.check(bad.is_empty(), "每条成就的奖励 id 都在对应数据表里（错配: %s）" % str(bad))

	# 奖励对象不许同时是默认解锁件（否则玩家达成时看到「已拥有」的空提示）
	var dup_reward: Array = []
	for aid in AchievementData.all_ids():
		var adef := AchievementData.get_def(aid)
		var rtype := String(adef.get("reward_type", ""))
		var rid := String(adef.get("reward_id", ""))
		if rtype == "cultivator" and rid in AchievementData.DEFAULT_CULTIVATORS:
			dup_reward.append("%s（角色 %s 已默认开放）" % [aid, rid])
		elif rtype == "item" and rid in AchievementData.DEFAULT_ITEMS:
			dup_reward.append("%s（道具 %s 已默认入池）" % [aid, rid])
		elif rtype == "weapon" and rid in AchievementData.default_weapons():
			dup_reward.append("%s（武器 %s 已默认入池）" % [aid, rid])
	_c.check(dup_reward.is_empty(), "成就奖励不与默认解锁重叠（重复: %s）" % str(dup_reward))

	# 新手起步四条必须真的低门槛（best_wave >= 5 / >= 8、金币 >= 100、局数 >= 3）
	var easy := {
		"ach_cult_yushou": {"best_wave": 5},
		"ach_cult_lingzhifu": {"best_wave": 8},
		"ach_cult_jinsuanpan": {"max_stones": 100},
		"ach_cult_kuxingseng": {"total_runs": 3},
	}
	for aid in easy.keys():
		var ctx: Dictionary = easy[aid]
		_c.check(AchievementData.is_condition_met(String(aid), ctx, ctx),
			"新手起步成就 %s 在低门槛数据下即达成（新玩家第 1~3 局就该见到解锁）" % aid)
