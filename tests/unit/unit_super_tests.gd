class_name UnitSuperTests
extends UnitTestsBase

## 单测模块：超级悟道（神通卡表 / 3+2 候选配比与构筑匹配 / 赠礼落地 / 不可售与不进商店）。
## 2026-10-25 新增。契约（UNIT_RESULT: ALL PASS / 退出码）由 UnitRunner 统一保证。
## 每个用例开头 reset_run，结尾也 reset_run —— 本模块会真的往 gm 里塞神通道具与武器。

func _test_super_table() -> void:
	var ids := SuperUpgradeData.all_ids()
	_c.check(ids.size() >= 30, "神通卡表至少 30 张（实为 %d）" % ids.size())
	var dup: Array = []
	var seen: Dictionary = {}
	var fields: Array = GameBalance.upgrade_fields()
	var bad_grant: Array = []
	var bad_apply: Array = []
	var bad_need: Array = []
	for card in SuperUpgradeData.CARDS:
		var cid := String(card.get("id", ""))
		if seen.has(cid):
			dup.append(cid)
		seen[cid] = true
		var gid := String(card.get("grant_item", ""))
		var idef := ItemData.get_def(gid)
		if idef.is_empty() or not ItemData.is_granted_only(gid) or not ItemData.is_no_sell(gid):
			bad_grant.append(cid)
			continue
		if int(idef.get("tier", 0)) != 5:
			bad_grant.append(cid)
		for k in (idef.get("apply", {}) as Dictionary).keys():
			if not (String(k) in fields):
				bad_apply.append("%s.%s" % [cid, k])
		if String(card.get("kind", "")) == "build" and (card.get("need", []) as Array).is_empty():
			bad_need.append(cid)
	_c.check(dup.is_empty(), "神通卡 id 不重复（重复: %s）" % str(dup))
	_c.check(bad_grant.is_empty(), "每张卡都绑定 tier5 + granted_only + no_sell 的神通道具（问题: %s）" % str(bad_grant))
	_c.check(bad_apply.is_empty(), "神通 apply 字段都在白名单内（非法: %s）" % str(bad_apply))
	_c.check(bad_need.is_empty(), "每张流派卡都声明了 need 标签（缺: %s）" % str(bad_need))

	# 触发关：固定 5/10/15；无尽模式 20 关后每逢 5 的倍数；胜利关 20 本身不触发
	_c.check(SuperUpgradeData.is_super_wave(5, false), "第 5 关触发超级悟道")
	_c.check(SuperUpgradeData.is_super_wave(10, false), "第 10 关触发超级悟道")
	_c.check(SuperUpgradeData.is_super_wave(15, false), "第 15 关触发超级悟道")
	_c.check(not SuperUpgradeData.is_super_wave(4, false), "第 4 关不触发")
	_c.check(not SuperUpgradeData.is_super_wave(20, false), "第 20 关胜利关不触发")
	_c.check(not SuperUpgradeData.is_super_wave(25, false), "普通模式不会打到 25 关")
	_c.check(SuperUpgradeData.is_super_wave(25, true), "无尽模式第 25 关触发")
	_c.check(not SuperUpgradeData.is_super_wave(20, true), "无尽模式第 20 关（胜利关）不触发")

	# 神通不进商店池：shop_ids 排除、pick_id 永不抽出
	GameManager.reset_run()
	var leaked: Array = []
	for sid in ItemData.shop_ids():
		if ItemData.is_granted_only(String(sid)):
			leaked.append(sid)
	_c.check(leaked.is_empty(), "shop_ids() 不含神通（泄漏: %s）" % str(leaked))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261025
	var picked_shen: Array = []
	for i in range(300):
		var pid := ItemData.pick_id(0.0, 20, [], rng, [], null)
		if pid.begins_with("shen_"):
			picked_shen.append(pid)
	_c.check(picked_shen.is_empty(), "商店抽取不会开出神通（意外: %s）" % str(picked_shen))
	GameManager.reset_run()

func _test_super_roll() -> void:
	GameManager.reset_run()
	# 构筑来源三选一：角色 item_tags（剑士 = melee/crit/haste）
	GameManager.cultivator_id = "jianchi"
	var tags := SuperUpgradeData.build_tag_set(GameManager)
	_c.check(tags.has("melee") and tags.has("crit") and tags.has("haste"),
		"构筑标签包含角色 item_tags（实为 %s）" % str(tags.keys()))
	# 武器 tags / scaling 也算：塞一把雷系武器进背包备选
	var thunder_id := ""
	for wid in WeaponData.DEFS.keys():
		if "thunder" in WeaponData.tags_of(String(wid)):
			thunder_id = String(wid)
			break
	if not thunder_id.is_empty():
		GameManager.stash.append({"id": thunder_id, "star": 1})
		tags = SuperUpgradeData.build_tag_set(GameManager)
		_c.check(tags.has("thunder"), "构筑标签包含武器 tags（雷系）")
		_c.check(tags.has("elemental"), "构筑标签包含武器 scaling 类别（元素）")

	# 候选配比：5 张 = 3 流派 + 2 通用，且不重复
	var offers := SuperUpgradeData.roll_offers(GameManager)
	_c.check(offers.size() == 5, "候选固定 5 张（实为 %d）" % offers.size())
	var build_n := 0
	var generic_n := 0
	var ids: Dictionary = {}
	var dup: Array = []
	for o in offers:
		if String(o.get("kind", "")) == "build":
			build_n += 1
		else:
			generic_n += 1
		var oid := String(o.get("id", ""))
		if ids.has(oid):
			dup.append(oid)
		ids[oid] = true
	_c.check(build_n == 3 and generic_n == 2,
		"候选配比为 3 流派 + 2 通用（实为 %d + %d）" % [build_n, generic_n])
	_c.check(dup.is_empty(), "同屏候选不重复（重复: %s）" % str(dup))
	# 卡面数据现取自道具定义（标题/apply 同源）
	var mismatch: Array = []
	for o in offers:
		var idef := ItemData.get_def(String(o.get("grant_item", "")))
		if String(o.get("title", "")) != String(idef.get("name", "")) \
				or (o.get("apply", {}) as Dictionary) != (idef.get("apply", {}) as Dictionary):
			mismatch.append(o.get("id", "?"))
	_c.check(mismatch.is_empty(), "卡面标题/apply 与道具定义同源（不一致: %s）" % str(mismatch))
	# 匹配到的流派卡：need 至少命中一个构筑标签（剑士池子里流派卡足够，不会触发兜底）
	var unmatched: Array = []
	for o in offers:
		if String(o.get("kind", "")) != "build":
			continue
		var card := SuperUpgradeData.get_def(String(o.get("id", "")))
		if not SuperUpgradeData.card_matches_build(card, tags):
			unmatched.append(o.get("id", "?"))
	_c.check(unmatched.is_empty(), "流派卡按当前构筑匹配（未命中: %s）" % str(unmatched))

	# 无灵兽时不出灵兽卡；有灵兽时能出
	GameManager.pets.clear()
	var pet_offered := false
	for o in offers:
		if String(o.get("grant_item", "")) == "shen_shouxue":
			pet_offered = true
	_c.check(not pet_offered, "没有灵兽时不抽灵兽卡")
	GameManager.pets.append({"id": "linghu", "star": 1})
	var pet_ok := false
	for i in range(20):
		for o in SuperUpgradeData.roll_offers(GameManager):
			if String(o.get("grant_item", "")) == "shen_shouxue":
				pet_ok = true
	_c.check(pet_ok, "有灵兽时灵兽卡进入候选池")

	# 已拿过的卡不再出现
	GameManager.reset_run()
	GameManager.cultivator_id = "jianchi"
	_c.check(SuperUpgradeData.apply(GameManager, "super_jianqi"), "剑气凌霄可以落地")
	var again: Array = []
	for i in range(20):
		for o in SuperUpgradeData.roll_offers(GameManager):
			if String(o.get("id", "")) == "super_jianqi":
				again.append(o.get("id"))
	_c.check(again.is_empty(), "已拿过的超级卡不再进候选（仍出现: %s）" % str(again))
	GameManager.reset_run()

func _test_super_apply() -> void:
	GameManager.reset_run()
	# 纯数值卡：apply 当帧生效
	var before_melee: float = GameManager.melee_damage
	var before_range: float = GameManager.attack_range_mult
	_c.check(SuperUpgradeData.apply(GameManager, "super_jianqi"), "剑气凌霄落地成功")
	_c.near(GameManager.melee_damage - before_melee, 15.0, EPS, "剑气凌霄近战伤害 +15")
	_c.near(GameManager.attack_range_mult - before_range, 0.25, EPS, "剑气凌霄攻击范围 +25%")
	_c.check(GameManager.items.has("shen_jianqi"), "神通进入道具持有列表")
	var hist: Dictionary = GameManager.upgrade_history.back() if not GameManager.upgrade_history.is_empty() else {}
	_c.check(String(hist.get("rarity", "")) == "mythic", "升级记录标记为逆天档")
	_c.check(not GameManager.sell_item("shen_jianqi"), "神通不可出售")
	_c.check(GameManager.items.has("shen_jianqi"), "出售被拒后神通仍在")

	# 新奇机制①：武器槽位 +1
	GameManager.reset_run()
	var base_slots := GameManager.max_weapon_slots()
	_c.check(SuperUpgradeData.apply(GameManager, "super_kaitian"), "开天辟地落地成功")
	_c.check(GameManager.max_weapon_slots() == base_slots + 1,
		"开天辟地让武器槽位 +1（%d → %d）" % [base_slots, GameManager.max_weapon_slots()])

	# 新奇机制②：击杀返还冷却的 hook 读数
	GameManager.reset_run()
	_c.check(SuperUpgradeData.apply(GameManager, "super_shalu"), "杀戮节奏落地成功")
	_c.near(GameManager.item_hook_sum("kill_cd_refund"), 0.08, EPS, "杀戮节奏 hook 读数 8%")

	# 灵兽栏 +1 与生命成对字段（hp_heal 与 max_hp 同值，卡面折叠不冒孤儿回血行）
	GameManager.reset_run()
	var pet_before := GameManager.max_pet_slots()
	_c.check(SuperUpgradeData.apply(GameManager, "super_shouxue"), "兽血沸腾落地成功")
	_c.check(GameManager.max_pet_slots() == pet_before + 1, "兽血沸腾让灵兽栏 +1")
	var hp_apply: Dictionary = ItemData.get_def("shen_shengsheng").get("apply", {})
	_c.check(absf(float(hp_apply.get("hp_heal", 0.0)) - float(hp_apply.get("max_hp", 0.0))) <= EPS,
		"神通的生命上限与回血同值成对")

	# 会话层：take 后记账、发 finished、本关不再弹
	GameManager.reset_run()
	GameManager.wave_number = 5
	GameManager.super_alloc_offers = SuperUpgradeData.roll_offers(GameManager)
	_c.check(GameManager.super_alloc_offers.size() == 5, "会话候选 5 张")
	var finished := [false]
	var cb := func(): finished[0] = true
	GameManager.super_alloc_finished.connect(cb)
	_c.check(SuperAllocSession.take(GameManager, 0), "会话取卡成功")
	GameManager.super_alloc_finished.disconnect(cb)
	_c.check(finished[0], "取卡后发出 super_alloc_finished")
	_c.check(GameManager.super_alloc_done_waves.has(5), "本关记账为已结算")
	_c.check(not SuperAllocSession.should_open(GameManager), "同一关不会重复触发")
	_c.check(GameManager.super_cards_taken.size() == 1, "已拿卡记录 +1")
	GameManager.reset_run()
