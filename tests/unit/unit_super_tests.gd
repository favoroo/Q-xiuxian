class_name UnitSuperTests
extends UnitTestsBase

## 单测模块：超级悟道「三道」体系（卡表 / 道途阶段门控 / 候选算法 / 赠礼落地 / 不可售与不进商店）。
## 2026-10-25 重构：从「3 流派 + 2 通用」的固定配比改为「开道 → 延续 → 大成/共鸣」的
## 道途制，本文件同步改写为验证道途语义，而不是验证固定占比。
## 契约（UNIT_RESULT: ALL PASS / 退出码）由 UnitRunner 统一保证。
## 每个用例开头 reset_run，结尾也 reset_run —— 本模块会真的往 gm 里塞神通道具与武器。

func _test_super_table() -> void:
	var ids := SuperUpgradeData.all_ids()
	_c.check(ids.size() >= 15, "神通卡表至少 15 张（实为 %d）" % ids.size())
	var dup: Array = []
	var seen: Dictionary = {}
	var fields: Array = GameBalance.upgrade_fields()
	var bad_grant: Array = []
	var bad_apply: Array = []
	var bad_lane: Array = []
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
		# 道途卡（kind=lane）必须声明 line 与 stage≥1，且 line 在 LINE_LABELS 里
		if String(card.get("kind", "")) == "lane":
			var line := String(card.get("line", ""))
			if line.is_empty() or not SuperUpgradeData.LINE_LABELS.has(line):
				bad_lane.append(cid)
			if int(card.get("stage", 0)) < 1:
				bad_lane.append("%s(stage)" % cid)
		# 共鸣卡必须声明 requires_lines 且非空
		if String(card.get("kind", "")) == "resonance" \
				and (card.get("requires_lines", []) as Array).is_empty():
			bad_lane.append("%s(requires_lines)" % cid)
	_c.check(dup.is_empty(), "神通卡 id 不重复（重复: %s）" % str(dup))
	_c.check(bad_grant.is_empty(), "每张卡都绑定 tier5 + granted_only + no_sell 的神通道具（问题: %s）" % str(bad_grant))
	_c.check(bad_apply.is_empty(), "神通 apply 字段都在白名单内（非法: %s）" % str(bad_apply))
	_c.check(bad_lane.is_empty(), "道途/共鸣卡元数据完整（问题: %s）" % str(bad_lane))

	# 每条道途都必须有 stage1 开道卡，否则该道永远进不了池子
	var stage1_lines: Dictionary = {}
	for card in SuperUpgradeData.CARDS:
		if String(card.get("kind", "")) == "lane" and int(card.get("stage", 1)) == 1:
			stage1_lines[String(card.get("line", ""))] = true
	var missing_start: Array = []
	for line_key in SuperUpgradeData.LINE_LABELS.keys():
		if not stage1_lines.has(String(line_key)):
			missing_start.append(line_key)
	_c.check(missing_start.is_empty(), "每条道途都有一张开道卡（缺: %s）" % str(missing_start))

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

## 阶段门控：stage1 随时可用；stage2 需该道已拥有 ≥1；stage3 需 ≥2；共鸣需两条道各 ≥1
func _test_super_stage_gate() -> void:
	var counts: Dictionary = {}
	var stage2 := SuperUpgradeData.get_def("super_wanjian_guizong")
	var stage1 := SuperUpgradeData.get_def("super_jianqi")
	_c.check(SuperUpgradeData.is_card_available(stage1, counts, false),
		"未开道时 stage1 可选")
	_c.check(not SuperUpgradeData.is_card_available(stage2, counts, false),
		"未开道时 stage2 不可选（阶段门控）")
	counts["sword"] = 1
	_c.check(SuperUpgradeData.is_card_available(stage2, counts, false),
		"已开剑道 1 张后 stage2 可选")
	var stage3 := SuperUpgradeData.get_def("super_tianfa")
	counts["thunder"] = 1
	_c.check(not SuperUpgradeData.is_card_available(stage3, counts, false),
		"雷法仅 1 张时 stage3 不可选")
	counts["thunder"] = 2
	_c.check(SuperUpgradeData.is_card_available(stage3, counts, false),
		"雷法 2 张后 stage3 可选")

	# 二阶段道途门控：箭道 stage3 / 体修·五行·灵兽 stage2
	var jianyu := SuperUpgradeData.get_def("super_jianyu")
	_c.check(not SuperUpgradeData.is_card_available(jianyu, {"arrow": 1}, false),
		"箭道仅 1 张时箭雨倾盆不可选")
	_c.check(SuperUpgradeData.is_card_available(jianyu, {"arrow": 2}, false),
		"箭道 2 张后箭雨倾盆可选")
	_c.check(not SuperUpgradeData.is_card_available(
		SuperUpgradeData.get_def("super_xuehai"), {}, false),
		"未开体修时血海护盾不可选")
	_c.check(SuperUpgradeData.is_card_available(
		SuperUpgradeData.get_def("super_xuehai"), {"body": 1}, false),
		"体修 1 张后血海护盾可选")
	_c.check(SuperUpgradeData.is_card_available(
		SuperUpgradeData.get_def("super_wuxing_guiyi"), {"wuxing": 1}, false),
		"五行 1 张后五行归一可选")

	# 共鸣：需要雷法 + 箭道各 ≥1
	var reso := SuperUpgradeData.get_def("super_leiting_danmu")
	var two: Dictionary = {"thunder": 1}
	_c.check(not SuperUpgradeData.is_card_available(reso, two, false),
		"只有雷法时共鸣卡不可选")
	two["arrow"] = 1
	_c.check(SuperUpgradeData.is_card_available(reso, two, false),
		"雷法 + 箭道各 1 张时共鸣卡可选")

	# 灵蕴五行（共鸣）：灵兽 + 五行各 ≥1，且有灵兽在场
	var ly := SuperUpgradeData.get_def("super_lingyun_wuxing")
	_c.check(not SuperUpgradeData.is_card_available(ly, {"beast": 1}, true),
		"只有灵兽道时灵蕴五行不可选")
	_c.check(not SuperUpgradeData.is_card_available(ly, {"beast": 1, "wuxing": 1}, false),
		"两条道齐了但没灵兽，灵蕴五行仍不可选")
	_c.check(SuperUpgradeData.is_card_available(ly, {"beast": 1, "wuxing": 1}, true),
		"灵兽 + 五行各 1 张且有灵兽时灵蕴五行可选")

	# 灵兽闸：无灵兽时兽血沸腾不可选
	var beast := SuperUpgradeData.get_def("super_shouxue")
	_c.check(not SuperUpgradeData.is_card_available(beast, {}, false),
		"无灵兽时兽血沸腾不可选")
	_c.check(SuperUpgradeData.is_card_available(beast, {}, true),
		"有灵兽时兽血沸腾可选")
	_c.check(not SuperUpgradeData.is_card_available(
		SuperUpgradeData.get_def("super_shouqun"), {"beast": 1}, false),
		"无灵兽时兽群不可选（即使灵兽道已开）")
	_c.check(SuperUpgradeData.is_card_available(
		SuperUpgradeData.get_def("super_shouqun"), {"beast": 1}, true),
		"灵兽道 1 张且有灵兽时兽群可选")

func _test_super_roll() -> void:
	GameManager.reset_run()
	GameManager.cultivator_id = "jianchi"
	var tags := SuperUpgradeData.build_tag_set(GameManager)
	_c.check(tags.has("melee") and tags.has("crit"),
		"构筑标签包含角色 item_tags（实为 %s）" % str(tags.keys()))

	# ① 第一次悟道：只能开道 —— 候选里不许出现 stage≥2 或共鸣卡
	var offers := SuperUpgradeData.roll_offers(GameManager)
	_c.check(offers.size() == SuperUpgradeData.OFFER_COUNT,
		"候选固定 %d 张（实为 %d）" % [SuperUpgradeData.OFFER_COUNT, offers.size()])
	var premature: Array = []
	for o in offers:
		var cdef := SuperUpgradeData.get_def(String(o.get("id", "")))
		if int(cdef.get("stage", 0)) >= 2 or String(cdef.get("kind", "")) == "resonance":
			premature.append(o.get("id", "?"))
	_c.check(premature.is_empty(), "第一次悟道不出进阶/共鸣卡（越阶: %s）" % str(premature))
	_c.check(_has_unique_ids(offers), "同屏候选不重复")
	_c.check(_max_same_line(offers) <= SuperUpgradeData.MAX_PER_LINE,
		"同屏同道途不超过 %d 张（实为 %d）" % [SuperUpgradeData.MAX_PER_LINE, _max_same_line(offers)])

	# ② 已开剑道一张后：必须出现「延续」卡（剑道 stage2 或已有道途的后续阶段）
	GameManager.super_cards_taken.append("super_jianqi")
	var offers2: Array = []
	for i in range(12):
		var o2 := SuperUpgradeData.roll_offers(GameManager)
		var has_cont := false
		for o in o2:
			if String(o.get("lane_chip", "")) == "延续" or String(o.get("lane_chip", "")) == "大成":
				has_cont = true
		if has_cont and o2.size() == SuperUpgradeData.OFFER_COUNT:
			offers2 = o2
			break
	_c.check(not offers2.is_empty(), "已开一道后候选里出现延续/大成卡")

	# ③ 手握两条道后，共鸣卡进入可用池
	var counts: Dictionary = {"thunder": 1, "arrow": 1}
	var reso := SuperUpgradeData.get_def("super_leiting_danmu")
	_c.check(SuperUpgradeData.is_card_available(reso, counts, false),
		"雷法 + 箭道各 1 张时共鸣卡进池")

	# ④ 卡面数据现取自道具定义（标题/apply 同源）
	var mismatch: Array = []
	for o in offers:
		var idef := ItemData.get_def(String(o.get("grant_item", "")))
		if String(o.get("title", "")) != String(idef.get("name", "")) \
				or (o.get("apply", {}) as Dictionary) != (idef.get("apply", {}) as Dictionary):
			mismatch.append(o.get("id", "?"))
	_c.check(mismatch.is_empty(), "卡面标题/apply 与道具定义同源（不一致: %s）" % str(mismatch))

	# ⑤ 已拿过的卡不再出现
	GameManager.reset_run()
	GameManager.cultivator_id = "jianchi"
	_c.check(SuperUpgradeData.apply(GameManager, "super_jianqi"), "剑气凌霄可以落地")
	_c.check(GameManager.super_cards_taken.has("super_jianqi"), "落地后 super_cards_taken 包含 super_jianqi（实为: %s）" % str(GameManager.super_cards_taken))
	var again: Array = []
	for i in range(20):
		for o in SuperUpgradeData.roll_offers(GameManager):
			if String(o.get("id", "")) == "super_jianqi":
				again.append(o.get("id"))
	_c.check(again.is_empty(), "已拿过的超级卡不再进候选（仍出现: %s）" % str(again))
	GameManager.reset_run()
	GameManager.cultivator_id = ""

func _test_super_apply() -> void:
	GameManager.reset_run()
	# 机制卡：apply 为空，机制靠 hook 读侧生效
	var before_range: float = GameManager.item_hook_sum("melee_range_mult")
	_c.check(SuperUpgradeData.apply(GameManager, "super_jianqi"), "剑气凌霄落地成功")
	_c.near(GameManager.item_hook_sum("melee_range_mult") - before_range, 1.0, EPS,
		"剑气凌霄近战范围倍率 +100%")
	_c.check(GameManager.items.has("shen_jianqi"), "神通进入道具持有列表")
	var hist: Dictionary = GameManager.upgrade_history.back() if not GameManager.upgrade_history.is_empty() else {}
	_c.check(String(hist.get("rarity", "")) == "mythic", "升级记录标记为逆天档")
	_c.check(not GameManager.sell_item("shen_jianqi"), "神通不可出售")
	_c.check(GameManager.items.has("shen_jianqi"), "出售被拒后神通仍在")

	# 开天辟地：槽位 +1
	GameManager.reset_run()
	var base_slots := GameManager.max_weapon_slots()
	_c.check(SuperUpgradeData.apply(GameManager, "super_kaitian"), "开天辟地落地成功")
	_c.check(GameManager.max_weapon_slots() == base_slots + 1,
		"开天辟地让武器槽位 +1（%d → %d）" % [base_slots, GameManager.max_weapon_slots()])

	# 献祭：槽位 -1 但下限 1（不许把角色压成零武器）
	GameManager.reset_run()
	GameManager.weapon_slots_override = 1
	_c.check(SuperUpgradeData.apply(GameManager, "super_xianji"), "献祭落地成功")
	_c.check(GameManager.max_weapon_slots() == 1,
		"献祭不会把武器槽压到 1 以下（实为 %d）" % GameManager.max_weapon_slots())

	# 杀戮节奏 hook 读数
	GameManager.reset_run()
	_c.check(SuperUpgradeData.apply(GameManager, "super_shalu"), "杀戮节奏落地成功")
	_c.near(GameManager.item_hook_sum("kill_cd_refund"), 0.08, EPS, "杀戮节奏 hook 读数 8%")

	# 灵兽栏 +1
	GameManager.reset_run()
	var pet_before := GameManager.max_pet_slots()
	_c.check(SuperUpgradeData.apply(GameManager, "super_shouxue"), "兽血沸腾落地成功")
	_c.check(GameManager.max_pet_slots() == pet_before + 1, "兽血沸腾让灵兽栏 +1")

	# 新机制 hook 读数：各自落地后 item_hook_sum 能读到
	var hook_cases: Array = [
		["super_wanjian_qifa", "projectile_count_bonus", 2.0],
		["super_tanmu", "projectile_bounce_bonus", 2.0],
		["super_zidian", "attack_chain_lightning", 1.0],
		["super_leijie", "kill_chain_lightning", 1.0],
		["super_tianfa", "crit_sky_bolt", 1.0],
		["super_fanzhen_dianchang", "thorns_electric", 1.0],
		["super_wuxing_lunzhuan", "wuxing_rotation_chance", 0.35],
		["super_wanjian_guizong", "sword_qi", 1.0],
		["super_leiting_danmu", "projectile_chain_lightning", 1.0],
		# 二阶段（2026-10-25）：箭雨 / 血盾 / 归一 / 兽群 / 灵蕴
		["super_jianyu", "arrow_rain_every", 6.0],
		["super_xuehai", "lifesteal_overflow_shield", 1.0],
		["super_wuxing_guiyi", "wuxing_all", 1.0],
		["super_shouqun", "pet_chain_lightning", 1.0],
		["super_lingyun_wuxing", "pet_wuxing_chance", 0.6],
	]
	for case in hook_cases:
		GameManager.reset_run()
		var cid := String(case[0])
		var hook := String(case[1])
		var expect := float(case[2])
		_c.check(SuperUpgradeData.apply(GameManager, cid), "机制卡 %s 落地成功" % cid)
		_c.near(GameManager.item_hook_sum(hook), expect, EPS,
			"机制卡 %s 的 hook %s 读数正确" % [cid, hook])

	# 会话层：take 后记账、发 finished、本关不再弹
	GameManager.reset_run()
	GameManager.wave_number = 5
	GameManager.super_alloc_offers = SuperUpgradeData.roll_offers(GameManager)
	_c.check(GameManager.super_alloc_offers.size() == SuperUpgradeData.OFFER_COUNT,
		"会话候选 %d 张" % SuperUpgradeData.OFFER_COUNT)
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

## 链电数值表：跳数折损与各路固定基值
func _test_chain_balance() -> void:
	_c.near(BalanceChain.chain_hop_damage(100.0, 0), 100.0, EPS, "链电首跳全额")
	_c.near(BalanceChain.chain_hop_damage(100.0, 1), 100.0 * BalanceChain.HOP_RATIO, EPS,
		"链电第二跳按 HOP_RATIO 折损")
	_c.check(BalanceChain.chain_hop_damage(100.0, 2) < BalanceChain.chain_hop_damage(100.0, 1),
		"链电伤害逐跳递减")
	_c.check(BalanceChain.crit_bolt_damage(0.0) > 0.0, "天罚基础伤害为正")
	_c.check(BalanceChain.crit_bolt_damage(20.0) > BalanceChain.crit_bolt_damage(0.0),
		"天罚随元素伤害成长")
	_c.check(BalanceChain.kill_chain_damage(0.0) > 0.0, "雷劫基础伤害为正")
	_c.check(BalanceChain.thorns_bolt_damage(0.4) > BalanceChain.thorns_bolt_damage(0.0),
		"反震电场随反震成长")
	# 二阶段数值表：箭雨 / 血盾 / 尸爆口径
	_c.near(BalanceChain.arrow_rain_damage(100.0), 60.0, EPS, "箭雨单支按武器实伤 60% 折算")
	_c.near(BalanceChain.shield_cap(200.0), 120.0, EPS, "血海护盾上限为最大生命 60%")
	_c.check(BalanceChain.shield_break_damage(200.0, 0.0) > BalanceChain.SHIELD_BREAK_BASE,
		"护盾破碎放电随最大生命加成")
	# 血祭盛宴尸爆口径：附加死者生命 25%，封顶随波复利；裂魂铃（hp_ratio=0）不受影响
	var ex_super := BalanceCombat.kill_explode_damage(120.0, 0.0, 1000.0, 0.25, 5)
	_c.near(ex_super, 120.0 + 250.0, EPS, "尸爆附加死者生命 25%（W5 封顶 400 之上不触顶）")
	var ex_capped := BalanceCombat.kill_explode_damage(120.0, 0.0, 100000.0, 0.25, 5)
	_c.check(ex_capped < 120.0 + 100000.0 * 0.25, "Boss 级血量的尸爆被随波封顶截住")
	_c.near(BalanceCombat.kill_explode_damage(40.0, 10.0),
		40.0 + 10.0 * BalanceCombat.KILL_EXPLODE_ELEM_COEF, EPS, "裂魂铃仍只吃基伤 + 元素")

func _has_unique_ids(offers: Array) -> bool:
	var seen: Dictionary = {}
	for o in offers:
		var oid := String(o.get("id", ""))
		if seen.has(oid):
			return false
		seen[oid] = true
	return true

func _max_same_line(offers: Array) -> int:
	var counts: Dictionary = {}
	for o in offers:
		var line := String(o.get("line", ""))
		if line.is_empty():
			continue
		counts[line] = int(counts.get(line, 0)) + 1
	var mx := 0
	for k in counts.keys():
		mx = maxi(mx, int(counts[k]))
	return mx
