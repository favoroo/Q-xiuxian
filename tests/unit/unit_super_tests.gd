class_name UnitSuperTests
extends UnitTestsBase

## 单测模块：飞升悟道（卡表 / 卡池闸 / 候选算法 / 赠礼落地 / 不可售与不进商店）。
## 2026-10-26 去阶段门控：候选改成「全表 − 已拿过 − 未过闸」的纯随机池，本文件同步
## 改写为验证卡池与两道真闸（灵兽闸 / 共鸣闸），不再验证阶段解锁链。
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
		# 道途卡（kind=lane）必须声明 line，且 line 在 LINE_LABELS 里
		if String(card.get("kind", "")) == "lane":
			var line := String(card.get("line", ""))
			if line.is_empty() or not SuperUpgradeData.LINE_LABELS.has(line):
				bad_lane.append(cid)
		# 共鸣卡必须声明 requires_lines 且非空
		if String(card.get("kind", "")) == "resonance" \
				and (card.get("requires_lines", []) as Array).is_empty():
			bad_lane.append("%s(requires_lines)" % cid)
	_c.check(dup.is_empty(), "神通卡 id 不重复（重复: %s）" % str(dup))
	_c.check(bad_grant.is_empty(), "每张卡都绑定 tier5 + granted_only + no_sell 的神通道具（问题: %s）" % str(bad_grant))
	_c.check(bad_apply.is_empty(), "神通 apply 字段都在白名单内（非法: %s）" % str(bad_apply))
	_c.check(bad_lane.is_empty(), "道途/共鸣卡元数据完整（问题: %s）" % str(bad_lane))

	# 去阶段门控（2026-10-26）：卡表里不该再残留 stage 字段；每条道途要有卡（否则道途签是死签）
	var stale_stage: Array = []
	for card in SuperUpgradeData.CARDS:
		if card.has("stage"):
			stale_stage.append(String(card.get("id", "")))
	_c.check(stale_stage.is_empty(), "卡表不再带 stage 字段（残留: %s）" % str(stale_stage))
	var lines_with_cards: Dictionary = {}
	for card in SuperUpgradeData.CARDS:
		if String(card.get("kind", "")) == "lane":
			lines_with_cards[String(card.get("line", ""))] = true
	var empty_lines: Array = []
	for line_key in SuperUpgradeData.LINE_LABELS.keys():
		if not lines_with_cards.has(String(line_key)):
			empty_lines.append(line_key)
	_c.check(empty_lines.is_empty(), "每条道途都有卡（缺: %s）" % str(empty_lines))

	# 触发关（无限闯关新节奏）：前中期 5/10/15/20 快速成型，深层 30/40/50 每 10 关大破境，50 关后封顶
	for w in [5, 10, 15, 20, 30, 40, 50]:
		_c.check(SuperUpgradeData.is_super_wave(w), "第 %d 关触发飞升悟道" % w)
	for w in [1, 4, 6, 9, 11, 14, 16, 19, 21, 25, 35, 45, 51, 60, 99]:
		_c.check(not SuperUpgradeData.is_super_wave(w), "第 %d 关不触发飞升悟道" % w)

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

## 卡池闸（2026-10-26 去阶段门控）：只剩灵兽闸与共鸣闸，任何卡从第一次飞升起就可选
func _test_super_pool_gate() -> void:
	var counts: Dictionary = {}
	# 阶段概念已取消：没拿过任何卡时，原来的 2/3 阶卡与 1 阶卡一样随时可选
	_c.check(SuperUpgradeData.is_card_available(
		SuperUpgradeData.get_def("super_jianqi"), counts, false), "剑气凌霄随时可选")
	_c.check(SuperUpgradeData.is_card_available(
		SuperUpgradeData.get_def("super_wanjian_guizong"), counts, false),
		"万剑归宗不依赖剑气凌霄（未开剑道也随时可选）")
	_c.check(SuperUpgradeData.is_card_available(
		SuperUpgradeData.get_def("super_tianfa"), counts, false), "天罚未开雷法也随时可选")
	_c.check(SuperUpgradeData.is_card_available(
		SuperUpgradeData.get_def("super_jianyu"), counts, false), "箭雨倾盆未开箭道也随时可选")
	_c.check(SuperUpgradeData.is_card_available(
		SuperUpgradeData.get_def("super_xuehai"), counts, false), "血海护盾未开体修也随时可选")
	_c.check(SuperUpgradeData.is_card_available(
		SuperUpgradeData.get_def("super_wuxing_guiyi"), counts, false), "五行归一未开五行也随时可选")

	# 共鸣闸：requires_lines 里每条道途各 ≥1 张（「共鸣」二字的定义，不是阶段解锁）
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

	# 灵兽闸：无灵兽时灵兽卡整张空转（+灵兽栏 / 灵兽链电都无处落）
	var beast := SuperUpgradeData.get_def("super_shouxue")
	_c.check(not SuperUpgradeData.is_card_available(beast, {}, false),
		"无灵兽时兽血沸腾不可选")
	_c.check(SuperUpgradeData.is_card_available(beast, {}, true),
		"有灵兽时兽血沸腾可选")
	_c.check(not SuperUpgradeData.is_card_available(
		SuperUpgradeData.get_def("super_shouqun"), {"beast": 1}, false),
		"无灵兽时兽群不可选")
	_c.check(SuperUpgradeData.is_card_available(
		SuperUpgradeData.get_def("super_shouqun"), counts, true),
		"有灵兽时兽群可选（不再要求灵兽道已拥有卡）")

	# 权重：道途卡一律同权（与「该道途已拿几张」无关），共鸣最高，仪式最低，命中构筑 ×1.5
	var bare: Dictionary = {}
	_c.near(SuperUpgradeData.card_weight(
		SuperUpgradeData.get_def("super_jianqi"), bare), SuperUpgradeData.W_LANE, EPS,
		"道途卡基础权重")
	_c.near(SuperUpgradeData.card_weight(
		SuperUpgradeData.get_def("super_tianfa"), bare), SuperUpgradeData.W_LANE, EPS,
		"原来的 3 阶卡不再额外加权（同权）")
	_c.near(SuperUpgradeData.card_weight(reso, bare), SuperUpgradeData.W_RESONANCE, EPS,
		"共鸣卡权重最高")
	_c.near(SuperUpgradeData.card_weight(
		SuperUpgradeData.get_def("super_kaitian"), bare), SuperUpgradeData.W_RITUAL, EPS,
		"仪式卡权重最低")
	_c.near(SuperUpgradeData.card_weight(
		SuperUpgradeData.get_def("super_jianqi"), {"melee": true}),
		SuperUpgradeData.W_LANE * SuperUpgradeData.W_BUILD_BONUS, EPS,
		"命中构筑标签的道途卡权重 ×1.5")
	_c.near(SuperUpgradeData.card_weight(
		SuperUpgradeData.get_def("super_kaitian"), {"melee": true}),
		SuperUpgradeData.W_RITUAL, EPS, "仪式卡没有 need 标签，不吃构筑加权")

func _test_super_roll() -> void:
	GameManager.reset_run()
	GameManager.cultivator_id = "jianchi"
	var tags := SuperUpgradeData.build_tag_set(GameManager)
	_c.check(tags.has("melee") and tags.has("crit"),
		"构筑标签包含角色 item_tags（实为 %s）" % str(tags.keys()))

	# ① 纯随机池：五张候选，同屏不重复、同道途 ≤ MAX_PER_LINE，且每张都过了闸
	var offers := SuperUpgradeData.roll_offers(GameManager)
	_c.check(offers.size() == SuperUpgradeData.OFFER_COUNT,
		"候选固定 %d 张（实为 %d）" % [SuperUpgradeData.OFFER_COUNT, offers.size()])
	_c.check(_has_unique_ids(offers), "同屏候选不重复")
	_c.check(_max_same_line(offers) <= SuperUpgradeData.MAX_PER_LINE,
		"同屏同道途不超过 %d 张（实为 %d）" % [SuperUpgradeData.MAX_PER_LINE, _max_same_line(offers)])
	var bad_gate: Array = []
	for o in offers:
		if not SuperUpgradeData.is_card_available(
				SuperUpgradeData.get_def(String(o.get("id", ""))), {}, false):
			bad_gate.append(o.get("id", "?"))
	_c.check(bad_gate.is_empty(), "候选都过了卡池闸（越闸: %s）" % str(bad_gate))

	# ② 去阶段门控：没开任何道时，原来的 2/3 阶卡也在同一个池子里（多抽几轮必见）
	var advanced_ids: Array = ["super_wanjian_guizong", "super_tianfa", "super_jianyu", "super_xuehai"]
	var saw_advanced := false
	for i in range(60):
		for o in SuperUpgradeData.roll_offers(GameManager):
			if String(o.get("id", "")) in advanced_ids:
				saw_advanced = true
				break
		if saw_advanced:
			break
	_c.check(saw_advanced, "未开道时原来的 2/3 阶卡也在随机池里（60 轮没抽到）")

	# ③ 手握两条道后，共鸣卡进池（这道闸还在：它就是「共鸣」二字的定义）
	GameManager.super_cards_taken.append("super_zidian")
	GameManager.super_cards_taken.append("super_wanjian_qifa")
	var saw_reso := false
	for i in range(40):
		for o in SuperUpgradeData.roll_offers(GameManager):
			if String(o.get("id", "")) == "super_leiting_danmu":
				saw_reso = true
				break
		if saw_reso:
			break
	_c.check(saw_reso, "雷法 + 箭道各 1 张后共鸣卡进池（40 轮没抽到）")
	GameManager.super_cards_taken.clear()

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
	_c.check(not StrikeFx.sword_qi_active(), "未拿剑气凌霄时近战/横扫仍走本体判定")
	# 机制卡：apply 为空，机制靠 hook 读侧生效
	var before_range: float = GameManager.item_hook_sum("melee_range_mult")
	_c.check(SuperUpgradeData.apply(GameManager, "super_jianqi"), "剑气凌霄落地成功")
	_c.near(GameManager.item_hook_sum("melee_range_mult") - before_range, 1.0, EPS,
		"剑气凌霄近战范围倍率 +100%")
	_c.check(GameManager.items.has("shen_jianqi"), "神通进入道具持有列表")
	_c.check(StrikeFx.sword_qi_active(), "剑气凌霄生效后近战/横扫改放剑气（本体不再判伤）")
	_c.near(WeaponDamageReadout.range_mult_for("qingyun_sword"), 2.0, EPS,
		"剑气凌霄让长剑射程乘区翻倍（1.0 → 2.0）")
	_c.near(WeaponDamageReadout.effective_range("qingyun_sword"), 210.0, EPS,
		"剑气凌霄让长剑有效索敌射程翻倍（105 → 210）")
	_c.near(WeaponDamageReadout.range_mult_for("gengjin_feijian"), 1.0, EPS,
		"剑气凌霄不影响远程飞剑射程乘区")
	_c.near(WeaponDamageReadout.range_mult_for("qingmu_tengbian"), 2.0, EPS,
		"剑气凌霄让藤鞭横扫射程乘区翻倍")
	var dummy_w := FloatingWeapon.new()
	dummy_w.weapon_def_id = "qingyun_sword"
	dummy_w.behavior = WeaponData.Behavior.MELEE
	dummy_w.attack_range = 105.0
	_c.near(dummy_w.effective_range(), 210.0, EPS, "长剑有效索敌与开火射程翻倍为 210")
	_c.near(dummy_w._body_range_mult(), 1.0, EPS, "长剑本体判定圆乘区维持 1.0 不虚胖")
	_c.near(MeleeHandler.arc_radius(dummy_w), 75.0, EPS, "长剑本体挥砍判定半径维持标准 75px")
	# 本体判定整段让位：剑气凌霄生效时 deal_damage 直接短路（伤害只由飞出的剑弧结算）
	_c.check(MeleeHandler.deal_damage(dummy_w, Vector2.RIGHT) == 0,
		"剑气凌霄生效后近战本体不再自行判伤（不留第二段收账）")
	_c.check(SweepHandler.deal_damage(dummy_w, Vector2.RIGHT) == 0,
		"剑气凌霄生效后横扫本体不再自行判伤")
	dummy_w.free()

	# 验证进树状态下近战武器触发 StrikeFx.try_fire_sword_qi_wave 甩出一道完整飞行剑弧（SwordQiWave）
	var fw_scene: PackedScene = preload("res://scenes/weapons/FloatingWeapon.tscn")
	var real_w = fw_scene.instantiate()
	real_w.weapon_def_id = "qingyun_sword"
	real_w.def = WeaponData.get_def("qingyun_sword")
	real_w.behavior = WeaponData.Behavior.MELEE
	real_w.attack_range = 105.0   # 真场景默认 150，这里钉成长剑标定值，断言才对得上 210
	add_child(real_w)
	var pre_active: int = SwordQiWave.active_count
	var wave: SwordQiWave = StrikeFx.try_fire_sword_qi_wave(real_w, Vector2.RIGHT)
	_c.check(wave != null, "剑气凌霄挥刀成功甩出一道飞行剑弧")
	_c.check(SwordQiWave.active_count == pre_active + 1, "剑气波活跃计数 +1")
	if wave != null:
		_c.near(wave.lifetime, SwordQiWave.travel_time_for(210.0), EPS,
			"剑气寿命按 210px 翻倍有效射程反推")
		# 飞行距离护栏（2026-10-26 用户：「剑气的飞行距离短一点」）：
		# 波心只飞到「刃缘前缘够到索敌距离」，不许整段飞满有效射程再白送一个外缘半径
		var dist: float = SwordQiWave.travel_distance_for(210.0)
		_c.check(dist < 210.0, "剑气波心飞行距离短于有效射程（实得 %.1f < 210）" % dist)
		_c.check(dist + SwordQiWave.ART_OUTER * SwordQiWave.ART_SCALE >= 210.0,
			"但刃缘仍覆盖满索敌距离（%.1f ≥ 210，锁定圈内不漏怪）"
				% (dist + SwordQiWave.ART_OUTER * SwordQiWave.ART_SCALE))
		var spawn_pos: Vector2 = wave.global_position
		wave._physics_process(1.0)   # 推进 1s（远超寿命）→ 按寿命自行回收，模拟实战飞完消散
		_c.check(wave.global_position.distance_to(spawn_pos) > 100.0, "剑气波是向前飞行的实体而非原地特效")
		_c.check(not wave.visible, "剑气波到寿命后休眠（视觉撤场）")
		_c.check(SwordQiWave.active_count == pre_active, "剑气波回收后活跃计数归零（池化不留账）")
	real_w.queue_free()

	var hist: Dictionary = GameManager.upgrade_history.back() if not GameManager.upgrade_history.is_empty() else {}
	_c.check(String(hist.get("rarity", "")) == "mythic", "升级记录标记为逆天档")
	_c.check(not GameManager.sell_item("shen_jianqi"), "神通不可出售")
	_c.check(GameManager.items.has("shen_jianqi"), "出售被拒后神通仍在")

	# 开天辟地：槽位 +1
	GameManager.reset_run()
	var base_slots: int = GameManager.max_weapon_slots()
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
	var pet_before: int = GameManager.max_pet_slots()
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

	# 燃血催诀（2026-10-27）：飞升表里唯一的技能冷却入口，走 apply 正式属性而非 hook。
	# 钉子钉到 SkillData 换算后的秒数，防止将来改 SKILL_CD_CAP / final_stats 时这张卡静默失效。
	GameManager.reset_run()
	_c.check(SuperUpgradeData.apply(GameManager, "super_cuijue"), "燃血催诀落地成功")
	_c.near(GameManager.skill_cooldown_mult, 0.40, EPS, "燃血催诀技能冷却缩减 40%")
	_c.near(float(SkillData.final_stats("gale", "")["cooldown"]), 7.5 * 0.60, EPS,
		"燃血催诀让疾行冷却 7.5s → 4.5s")

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
