class_name UnitContentTests
extends UnitTestsBase

## 单测模块：五行武器矩阵 / 批一新属性 / 法宝系统 / 修士流派 / 机关炮台与新修士（从 tests/unit_runner.gd 拆出，2026-10-11）。
## 调用顺序与判据契约（UNIT_RESULT: ALL PASS / 退出码）由 UnitRunner 统一保证；
## _c 与 EPS 继承自 UnitTestsBase，函数体与拆分前逐字一致。
func _test_five_elements_system() -> void:
	# 1. 武器表完整性校验：69 把法器且图标资源齐全
	_c.equals(WeaponData.DEFS.size(), 69, "全武器库扩充至 69 把法器")
	_c.equals(WeaponData.SHOP_POOL.size(), 69, "商店池覆盖全部 69 把法器")
	var missing_icons: Array = []
	var missing_dual_tags: Array = []
	var no_bullet: Array = []        ## 弹丸类法器没配外观（会退回公共的 blade.png ⇒ 五把法器打出同一张火符）
	var bad_bullet: Array = []       ## 配了路径但文件不在
	var elem_counts: Dictionary = {"metal": 0, "wood": 0, "water": 0, "fire": 0, "earth": 0}
	for w_id in WeaponData.SHOP_POOL:
		var def := WeaponData.get_def(w_id)
		var icon_path: String = def.get("icon", "")
		if icon_path.is_empty() or not ResourceLoader.exists(icon_path):
			missing_icons.append(w_id)
		var bullet_path: String = String(def.get("bullet", ""))
		if int(def.get("behavior", -1)) == WeaponData.Behavior.PROJECTILE:
			if bullet_path.is_empty():
				no_bullet.append(w_id)
			elif not ResourceLoader.exists(bullet_path):
				bad_bullet.append(w_id)
		var c_tag := WeaponData.class_of(w_id)
		var e_tag := WeaponData.element_of(w_id)
		if c_tag.is_empty() or e_tag.is_empty():
			missing_dual_tags.append(w_id)
		else:
			elem_counts[e_tag] = int(elem_counts.get(e_tag, 0)) + 1
	_c.check(missing_icons.is_empty(), "68 把法器的图标文件全部就位（缺: %s）" % str(missing_icons))
	_c.check(missing_dual_tags.is_empty(), "每把法器均具备「器类+五行」双标签（缺: %s）" % str(missing_dual_tags))
	_c.check(no_bullet.is_empty(), "每把弹丸法器都配了自己的弹丸外观（缺: %s）" % str(no_bullet))
	_c.check(bad_bullet.is_empty(), "弹丸外观文件全部存在（缺文件: %s）" % str(bad_bullet))
	# 扩容后各系把数：金16/木13/水13/火13/土14（2026-10-13 束流支路紫虹镜入金系）
	var elem_expect := {"metal": 16, "wood": 13, "water": 13, "fire": 13, "earth": 14}
	for e_key in elem_counts.keys():
		_c.equals(int(elem_counts[e_key]), int(elem_expect[e_key]), "五行【%s】包含 %d 把法器" % [e_key, int(elem_expect[e_key])])

	# 1b. 攻击方式短标与货架卡紧凑特性（商店近战/远程标记，2026-10-11 用户）
	var label_missing: Array = []
	var feats_over: Array = []
	var label_of := {}
	for w2 in WeaponData.SHOP_POOL:
		var d2 := WeaponData.get_def(String(w2))
		var lab := WeaponData.behavior_label(d2)
		if lab.is_empty():
			label_missing.append(String(w2))
		label_of[String(w2)] = lab
		# 卡内宽最小 124px 且 BonusRows 行不换行 ⇒ 紧凑特性最多两段（一个分隔点）
		if WeaponData.card_feats(d2).count("·") > 1:
			feats_over.append(String(w2))
	_c.check(label_missing.is_empty(), "68 把法器的攻击方式短标全部就位（缺: %s）" % str(label_missing))
	_c.check(feats_over.is_empty(), "货架卡紧凑特性最多 2 段不溢卡宽（超宽: %s）" % str(feats_over))
	_c.equals(label_of["qingyun_sword"], "近战", "青云剑标记近战")
	_c.equals(label_of["gengjin_feijian"], "远程", "飞剑标记远程")
	_c.equals(label_of["fantian_yin"], "范围", "番天印标记范围")
	_c.equals(label_of["lingdie"], "环绕", "灵蝶标记环绕")
	_c.equals(label_of["jiguan_nu"], "机关", "机关弩标记机关")
	_c.equals(WeaponData.card_feats(WeaponData.get_def("liuye_feidao")), "穿透2·3发", "柳叶飞刀紧凑特性＝穿透2·3发（量词用「发」：projectile_count 是出膛弹丸数，不是连击段数；2026-10-14 穿透 3→2）")
	_c.equals(WeaponData.card_feats(WeaponData.get_def("qingyun_sword")), "", "青云剑无机械特性时不占卡面特性行")

	# 1b-2. 色签解释的两条数据前提（货架卡点色签弹解释卡，2026-10-11 用户「加成怎么样加成哪些」）：
	#       ① 表里用到的每一种攻击方式都得有机制解释，漏一种就是点开来一张空卡；
	#       ② stat_scalings 的每个键都得有人话名，漏一个键解释卡上就露原始英文（同一把尺的
	#           账单函数 GameBalance.stat_scaling_label 是唯一的名字来源）。
	var tip_missing: Array = []
	var used_behaviors: Array[int] = []
	for w4 in WeaponData.SHOP_POOL:
		var beh := int(WeaponData.get_def(String(w4)).get("behavior", WeaponData.Behavior.MELEE))
		if not (beh in used_behaviors):
			used_behaviors.append(beh)
		var bt: Dictionary = WeaponData.behavior_tip(beh)
		if String(bt.get("how", "")).is_empty() or (bt.get("notes", []) as Array).is_empty():
			tip_missing.append(String(w4))
	_c.check(tip_missing.is_empty(),
			"%d 种攻击方式全都有机制解释（缺: %s）" % [used_behaviors.size(), str(tip_missing)])
	_c.equals(used_behaviors.size(), 8, "商店池覆盖 8 种攻击方式（近战/远程/范围/环绕/机关/横扫/光束/喷吐）")
	var raw_key: Array = []
	for w5 in WeaponData.SHOP_POOL:
		for k in WeaponData.get_def(String(w5)).get("stat_scalings", {}).keys():
			if GameBalance.stat_scaling_label(String(k)) == String(k):
				raw_key.append("%s:%s" % [String(w5), String(k)])
	_c.check(raw_key.is_empty(), "每把法器的属性受益键都有人话名（露原始 key: %s）" % str(raw_key))

	# 1c. 货架卡加成行的横向预算：卡内宽下限 124（CARD_W_MIN 148 − OFFER_PAD_X 12×2），
	#     BonusRows 一行不换行 ⇒ 行名 + 数值超格就把整块面板顶出屏（LayoutCheck 量的是最坏屏，
	#     这里按最坏读数直接拦：谁再把行名拉长一档、或给窄卡加一行长名，当场红）。
	#     数值不读本局乘区，统一换成「999 → 9999.9」这一档最宽样本。
	var body_f: Font = GameStyle.body_font()
	var inner_min: float = WaveShop.card_inner_w(WaveShop.CARD_W_MIN)
	var worst_arrow: String = WeaponDamageReadout.arrow_text(999.0, 9999.9)
	var rows_too_wide: Array = []
	for w3 in WeaponData.SHOP_POOL:
		var d3: Dictionary = ShopOfferCardFactory.resolve_offer_data(
				{"kind": "weapon", "id": String(w3)})
		for r3 in d3.get("stat_rows", []):
			var val_txt := String(r3[1])
			if val_txt.contains("→"):
				val_txt = worst_arrow
			var need: float = GameStyle.line_max_w(String(r3[0]), body_f, 12) \
					+ GameStyle.line_max_w(val_txt, body_f, 12) + 4.0
			if need > inner_min:
				rows_too_wide.append("%s「%s」%.0f>%d" % [String(w3), String(r3[0]), need, int(inner_min)])
	_c.check(rows_too_wide.is_empty(),
			"48 把法器的货架卡每一行都装得进 %d 卡内宽（超宽: %s）" % [int(inner_min), str(rows_too_wide)])

	# 2. 土豆兄弟式属性受益折算（GameBalance.weapon_stat_bonus 纯函数）
	var earth_scalings := {"armor": 3.5}
	_c.near(GameBalance.weapon_stat_bonus(earth_scalings, {"armor": 0.0}, 1), 0.0, EPS, "0 护甲时无额外属性加成")
	_c.near(GameBalance.weapon_stat_bonus(earth_scalings, {"armor": 10.0}, 1), 35.0, EPS, "10 护甲在 ★1 番天印下转化 +35 基础伤")
	_c.near(GameBalance.weapon_stat_bonus(earth_scalings, {"armor": 10.0}, 2), 43.75, EPS, "★2 属性转化系数 ×1.25 (+43.75)")
	_c.near(GameBalance.weapon_stat_bonus(earth_scalings, {"armor": 10.0}, 3), 52.5, EPS, "★3 属性转化系数 ×1.50 (+52.5)")

	var wood_scalings := {"hp_regen": 4.5}
	_c.near(GameBalance.weapon_stat_bonus(wood_scalings, {"hp_regen": 2.0}, 1), 9.0, EPS, "2.0 气血回复在青木藤鞭下转化 +9 基础伤")

	# 2b. 加点受益法器判定（GameBalance.upgrade_benefits_weapon，悟道卡片受益图标行同源）
	_c.check(GameBalance.upgrade_benefits_weapon({"melee_damage": 2.0}, "qingyun_sword"), "近战强化让青云剑受益")
	_c.check(not GameBalance.upgrade_benefits_weapon({"melee_damage": 2.0}, "gengjin_feijian"), "近战强化不让飞剑（远程）受益")
	_c.check(GameBalance.upgrade_benefits_weapon({"ranged_damage": 2.0}, "gengjin_feijian"), "远程强化让飞剑受益")
	_c.check(not GameBalance.upgrade_benefits_weapon({"ranged_damage": 2.0}, "qingyun_sword"), "远程强化不让青云剑（近战）受益")
	_c.check(GameBalance.upgrade_benefits_weapon({"weapon_damage_mult": 0.15}, "qingyun_sword")
		and GameBalance.upgrade_benefits_weapon({"weapon_damage_mult": 0.15}, "lingdie"), "武器强化是全局乘区：近战与环绕都受益")
	_c.check(GameBalance.upgrade_benefits_weapon({"attack_speed_mult_mul": 0.88}, "lingdie"), "攻速提升让环绕灵蝶受益")
	_c.check(GameBalance.upgrade_benefits_weapon({"knockback_mult": 0.25}, "qingyun_sword"), "击退提升全体法器受益")
	_c.check(GameBalance.upgrade_benefits_weapon({"elite_damage": 0.25}, "huoyan_fu"), "斩将加成全体法器受益（对精英乘区）")
	_c.check(GameBalance.upgrade_benefits_weapon({"element_damage_wood": 0.10}, "wanmu_lingfu"), "青木真解让木系毒符受益")
	_c.check(not GameBalance.upgrade_benefits_weapon({"element_damage_wood": 0.10}, "qingyun_sword"), "青木真解不让金系青云剑受益")
	_c.check(GameBalance.upgrade_benefits_weapon({"element_damage_all": 0.06}, "qingyun_sword")
		and GameBalance.upgrade_benefits_weapon({"element_damage_all": 0.06}, "huoyan_fu"), "全元素强化五行法器都受益")
	_c.check(GameBalance.upgrade_benefits_weapon({"armor": 2.0}, "fantian_yin"), "护甲提升让吃护甲转化的巨印受益")
	_c.check(not GameBalance.upgrade_benefits_weapon({"armor": 2.0}, "qingyun_sword"), "护甲提升不让不吃护甲转化的青云剑受益")
	_c.check(GameBalance.upgrade_benefits_weapon({"max_hp": 25.0}, "hunyuan_zhong"), "生命提升让吃额外生命转化的古钟受益（异名映射）")
	_c.check(GameBalance.upgrade_benefits_weapon({"hp_regen": 1.2}, "qingmu_tengbian"), "生命回复让藤鞭受益")
	_c.check(GameBalance.upgrade_benefits_weapon({"lifesteal": 0.04}, "lingdie"), "吸血让灵蝶受益")
	_c.check(GameBalance.upgrade_benefits_weapon({"crit_rate": 0.08}, "qingyun_sword"), "暴击率让吃暴击转化的青云剑受益")
	_c.check(GameBalance.upgrade_benefits_weapon({"crit_mult": 0.25}, "gengjin_feijian"), "暴击伤害让吃暴伤转化的飞剑受益（异名映射）")
	_c.check(GameBalance.upgrade_benefits_weapon({"move_speed_mult": 0.08}, "bajiao_fan"), "移速提升让风扇受益（异名映射）")
	_c.check(GameBalance.upgrade_benefits_weapon({"harvest": 8.0}, "jubao_chi"), "收益提升让聚宝金尺受益")
	_c.check(GameBalance.upgrade_benefits_weapon({"bonus_pierce": 1.0}, "gengjin_feijian"), "破甲透劲让弹丸类飞剑受益")
	_c.check(not GameBalance.upgrade_benefits_weapon({"bonus_pierce": 1.0}, "qingyun_sword"), "破甲透劲不让近战青云剑受益")
	_c.check(not GameBalance.upgrade_benefits_weapon({"dodge": 0.07}, "qingyun_sword")
		and not GameBalance.upgrade_benefits_weapon({"pickup_range_mult": 0.4}, "lingdie")
		and not GameBalance.upgrade_benefits_weapon({"thorns": 0.35}, "hunyuan_zhong"), "闪避/拾取/反伤类不作用于任何法器")
	# 全表扫描：每条加点对全部法器判定不崩、且至少有一条加点让每把法器受益（图标行不会空摆全表）
	var all_ids: Array = WeaponData.DEFS.keys()
	var any_benefit := {}
	for u in UpgradeData.UPGRADES:
		for wid0 in all_ids:
			if GameBalance.upgrade_benefits_weapon(u.get("apply", {}), String(wid0)):
				any_benefit[wid0] = true
	_c.check(any_benefit.size() == all_ids.size(), "每把法器都至少被一条加点覆盖（%d/%d）" % [any_benefit.size(), all_ids.size()])
	# 2c. 受益链路读数与受益判定同源：upgrade_benefit_reasons 是判定的唯一出处（卡片「该不该挂这颗
	#     图标」与详情卡那句「这条悟道走的哪条链路」共用它）。全表 × 全法器逐对比对，防两条分叉。
	var diverged := 0
	for u2 in UpgradeData.UPGRADES:
		var apply2: Dictionary = u2.get("apply", {})
		for wid2 in all_ids:
			var has_reason: bool = not GameBalance.upgrade_benefit_reasons(apply2, String(wid2)).is_empty()
			if has_reason != GameBalance.upgrade_benefits_weapon(apply2, String(wid2)):
				diverged += 1
	_c.check(diverged == 0, "全表 × 全法器：有链路才算受益，判定与链路读数零分叉（%d 处不一致）" % diverged)
	_c.check(GameBalance.upgrade_benefit_reasons({"melee_damage": 2.0}, "qingyun_sword") == ["melee_damage"],
		"近战强化在青云剑上回一条链路 melee_damage（详情卡那句「走的哪条链路」取的就是它）")
	_c.check(GameBalance.upgrade_benefit_reasons({"melee_damage": 2.0}, "gengjin_feijian").is_empty(),
		"近战强化在飞剑上零链路")
	_c.check(GameBalance.upgrade_benefit_reasons({"bonus_pierce": 1.0}, "qingyun_sword").is_empty()
		and GameBalance.upgrade_benefit_reasons({"bonus_pierce": 1.0}, "gengjin_feijian") == ["bonus_pierce"],
		"贯穿只回给弹丸类链路")

	# 3. 五行羁绊与多品类环绕灵宝在 GameManager 中的结算
	GameManager.reset_run()
	GameManager.drones = [
		{"id": "hunyuan_zhong", "star": 1},
		{"id": "hunyuan_zhong", "star": 1}
	]
	GameManager.recalc_synergies()
	_c.check(GameManager.active_synergies.has("spirit") and GameManager.active_synergies.has("earth"), "上阵 2 尊混元古钟同时触发【御灵】与【厚土】双羁绊")
	_c.near(GameManager.synergy_armor, 3.0, EPS, "厚土一档提供 +3 护甲")
	_c.near(GameManager.synergy_knockback_mult, 1.25, EPS, "厚土一档提供 +25% 震退力")
	_c.near(GameManager.get_effective_armor(), 3.0, EPS, "有效护甲已计入厚土羁绊")
	GameManager.reset_run()

func _test_new_stat_fields() -> void:
	# 字段落地：apply 幅度确实写进对应属性
	GameManager.reset_run()
	GameManager._apply_stat_fields({"xp_gain_mult": 0.15, "knockback_mult": 0.35, "elite_damage": 0.25, "free_rerolls": 1.0}, "test")
	_c.near(GameManager.xp_gain_mult, 1.15, EPS, "悟性 +15% 落地")
	_c.near(GameManager.knockback_mult, 1.35, EPS, "震退 +35% 落地")
	_c.near(GameManager.elite_damage, 0.25, EPS, "斩将 +25% 落地")
	_c.equals(GameManager.free_rerolls, 1, "免费重掷 +1 落地")

	# 悟性：只放大修为，灵石按原价入账（不双重受益）
	GameManager.reset_run()
	GameManager.xp_gain_mult = 1.5
	GameManager.add_experience(4)   # 4×1.5=6，低于 10 的升级门槛，不触发升级扣减
	_c.equals(GameManager.experience, 6, "悟性 1.5x：4 点来源 → 6 点修为")
	_c.equals(GameManager.spirit_stones, 4, "灵石不受悟性放大")

	# 五行真解：全元素加成摊到五行，单元素只加一格
	GameManager.reset_run()
	GameManager._apply_stat_fields({"element_damage_all": 0.06}, "test")
	for e in WeaponData.ELEMENTS:
		_c.near(float(GameManager.element_damage.get(e, 0.0)), 0.06, EPS, "element_damage_all 摊到【%s】" % e)
	_c.near(GameManager.element_damage_mult("huoyan_fu"), 1.06, EPS, "火焰符吃到全元素 +6%")
	_c.near(GameManager.element_damage_mult("qingyun_sword"), 1.06, EPS, "青云剑（金）也吃到 +6%")
	GameManager._apply_stat_fields({"element_damage_fire": 0.12}, "test")
	_c.near(GameManager.element_damage_mult("huoyan_fu"), 1.18, EPS, "离火单系再 +12% → 合计 1.18")
	_c.near(GameManager.element_damage_mult("qingyun_sword"), 1.06, EPS, "金系不受离火加成")

	# 震退：玩家属性 × 厚土羁绊同一条乘区
	GameManager.reset_run()
	GameManager.knockback_mult = 1.5
	GameManager.synergy_knockback_mult = 1.25
	_c.near(GameManager.knockback_force(100.0), 187.5, EPS, "震退 1.5 × 厚土 1.25 = 187.5")
	GameManager.reset_run()
	_c.near(GameManager.knockback_force(100.0), 100.0, EPS, "重置后击退回归基础值")

	# 斩将：只认 is_elite 标记（精英与魔君都带），普通怪不受影响
	GameManager.reset_run()
	GameManager.elite_damage = 0.25
	var elite_stub := EnemyBase.new()
	elite_stub.is_elite = true
	var grunt_stub := EnemyBase.new()
	grunt_stub.is_elite = false
	_c.near(GameManager.elite_damage_mult_for(elite_stub), 1.25, EPS, "精英吃到斩将 +25%")
	_c.near(GameManager.elite_damage_mult_for(grunt_stub), 1.0, EPS, "普通怪不吃斩将")
	elite_stub.free()
	grunt_stub.free()
	GameManager.reset_run()

	# 免费重掷：先消耗次数，用完才付灵石；roll_shop(new_wave) 重置
	GameManager.reset_run()
	GameManager.free_rerolls = 2
	GameManager.wave_number = 3
	GameManager.spirit_stones = 100
	GameManager.rng.seed = 555
	GameManager.roll_shop(true)
	_c.equals(GameManager.reroll_free_left, 2, "新一波货架重置免费重掷次数")
	var stones_before := GameManager.spirit_stones
	GameManager.reroll_shop()
	_c.equals(GameManager.reroll_free_left, 1, "第一次重掷消耗免费次数")
	_c.equals(GameManager.spirit_stones, stones_before, "免费重掷不扣灵石")
	GameManager.reroll_shop()
	GameManager.reroll_shop()
	_c.equals(GameManager.reroll_free_left, 0, "免费次数用完")
	_c.equals(GameManager.spirit_stones, stones_before - GameBalance.reroll_cost(3, 0, 1.0), "第三次重掷开始付灵石（按第 1 次付费价）")
	GameManager.reset_run()

func _test_item_system() -> void:
	# 数据表完整性：apply 键都在白名单内、档位合法、图标就位、定价为正
	var fields: Array = GameBalance.upgrade_fields()
	var bad_keys: Array = []
	var bad_meta: Array = []
	for item_id in ItemData.all_ids():
		var def := ItemData.get_def(item_id)
		for key in def.get("apply", {}).keys():
			if not (key in fields):
				bad_keys.append("%s.%s" % [item_id, key])
		var tier := int(def.get("tier", 0))
		if tier < 1 or tier > 4:
			bad_meta.append("%s.tier=%d" % [item_id, tier])
		if int(def.get("price", 0)) <= 0:
			bad_meta.append("%s.price" % item_id)
		var icon_path: String = def.get("icon", "")
		if icon_path.is_empty() or not ResourceLoader.exists(icon_path):
			bad_meta.append("%s.icon" % item_id)
	_c.check(bad_keys.is_empty(), "法宝 apply 字段都在白名单内（非法: %s）" % str(bad_keys))
	_c.check(bad_meta.is_empty(), "法宝 档位/价格/图标 元数据齐全（异常: %s）" % str(bad_meta))

	# 档位权重：第 1 波只有普通，传说第 14 波才解锁；福缘乘区抬高高档
	var w1: Array = GameBalance.item_tier_weights(0.0, 1)
	_c.check(float(w1[0]) > 0.0 and float(w1[1]) == 0.0 and float(w1[3]) == 0.0, "第 1 波只出普通法宝")
	var w15: Array = GameBalance.item_tier_weights(0.0, 15)
	_c.check(float(w15[3]) > 0.0, "第 15 波传说法宝解锁")
	var w_luck: Array = GameBalance.item_tier_weights(40.0, 15)
	_c.check(float(w_luck[3]) > float(w15[3]), "福缘抬高传说权重")
	# 波次递进与封顶：高档随波次增长、不越上限；四档之和恒为 100
	var w20: Array = GameBalance.item_tier_weights(0.0, 20)
	_c.near(float(w20[1]), GameBalance.ITEM_TIER_RARE_CAP, EPS, "第 20 波稀有触顶")
	_c.near(float(w20[2]), 22.0, EPS, "第 20 波史诗 2.0×11=22（未触顶 25）")
	_c.check(float(w20[3]) <= GameBalance.ITEM_TIER_LEGEND_CAP, "传说不越上限")
	_c.near(float(w20[0]) + float(w20[1]) + float(w20[2]) + float(w20[3]), 100.0, EPS, "四档之和恒为 100")
	_c.check(float(GameBalance.item_tier_weights(0.0, 19)[3]) > float(w15[3]), "传说权重随波次递进")

	# 抽取确定性 + unique 剔除
	var rng := RandomNumberGenerator.new()
	rng.seed = 31415
	var pick_a := ItemData.pick_id(0.0, 15, [], rng)
	rng.seed = 31415
	_c.equals(ItemData.pick_id(0.0, 15, [], rng), pick_a, "同种子 → 同法宝")
	_c.check(pick_a != "", "第 15 波池子非空")
	var no_unique := true
	rng.seed = 2718
	for i in range(50):
		if ItemData.pick_id(0.0, 15, ["tisi_kuilei"], rng) == "tisi_kuilei":
			no_unique = false
	_c.check(no_unique, "已持有的 unique 法宝不会再次上架")
	# 池抽空（unique 已持有）时仍有非 unique 法宝可抽
	_c.check(ItemData.pick_id(0.0, 15, ["tisi_kuilei"], null) != "", "仍有非 unique 法宝可抽")

	# 购买落地：属性加成走与悟道同一条链路
	GameManager.reset_run()
	_c.check(GameManager.add_item("jubaopen"), "聚宝盆购买成功")
	_c.near(GameManager.harvest, 6.0, EPS, "聚宝盆灵韵 +6 落地")
	_c.check(GameManager.has_item("jubaopen"), "已持有列表登记")
	# 取舍型：狂血丹 +伤害 -护甲
	GameManager.add_item("kuangxue_dan")
	_c.near(GameManager.weapon_damage_mult, 1.18, EPS, "狂血丹伤害 +18%")
	_c.near(GameManager.armor, -2.0, EPS, "狂血丹护甲 -2（负面代偿）")
	# unique 限购
	_c.check(GameManager.add_item("tisi_kuilei"), "替死傀儡首购成功")
	_c.check(not GameManager.add_item("tisi_kuilei"), "替死傀儡不可重复购买")
	_c.equals(GameManager.items.count("tisi_kuilei"), 1, "unique 法宝仅持一件")

	# 商店购买链路：item offer 扣灵石、生效、标记售出
	GameManager.reset_run()
	GameManager.wave_number = 5
	GameManager.spirit_stones = 100
	GameManager.shop_offers = [{
		"kind": "item", "id": "mibao_luopan",
		"price": GameBalance.item_price(int(ItemData.get_def("mibao_luopan").get("price", 12)), 5, 1.0),
		"sold": false, "locked": false,
	}]
	var stones0 := GameManager.spirit_stones
	_c.check(GameManager.buy_offer(0), "法宝货架位购买成功")
	_c.near(GameManager.luck, 5.0, EPS, "觅宝罗盘福缘 +5 落地")
	_c.check(GameManager.spirit_stones < stones0, "购买扣了灵石")
	_c.check(bool(GameManager.shop_offers[0].get("sold", false)), "售出标记已打")

	# 替死傀儡：致死时消耗并免死（UnitRunner 无玩家节点，验证消耗语义即可）
	GameManager.reset_run()
	_c.check(not GameManager.try_revive(), "没有傀儡时免死不触发")
	GameManager.add_item("tisi_kuilei")
	_c.check(GameManager.try_revive(), "傀儡挡下致死一击")
	_c.check(not GameManager.has_item("tisi_kuilei"), "傀儡挡劫后消耗")
	_c.check(not GameManager.try_revive(), "一次性：第二次致死不再免死")

	# 回春葫芦 hook 求和（两件叠加）
	GameManager.reset_run()
	GameManager.add_item("huichun_hulu")
	GameManager.add_item("huichun_hulu")
	_c.near(GameManager.item_hook_sum("wave_heal_pct"), 0.30, EPS, "两件回春葫芦波末回血叠加到 30%")
	GameManager.reset_run()

	# 法宝定价与公式同源
	_c.equals(GameBalance.item_price(45, 9, 1.0), 45 + 8 * 2, "史诗法宝第 9 波 +16")
	_c.equals(GameBalance.item_price(45, 9, 0.8), int((45.0 + 16.0) * 0.8), "法宝价吃商店折扣")

	# 残丹化灵：回不上的那截气血折灵石（汇率与藏宝匣金灵石那一路同档，单颗封顶）
	_c.equals(GameBalance.heal_overflow_stones(0.0), 0, "没溢出就不给钱")
	_c.equals(GameBalance.heal_overflow_stones(-5.0), 0, "负数按 0 收")
	_c.equals(GameBalance.heal_overflow_stones(18.0), 14, "满口 18 点溢出 → 14 灵石（≈3 颗金灵石）")
	_c.equals(GameBalance.heal_overflow_stones(13.0), 10, "缺血 5 吃 18：溢出 13 → 10 灵石")
	_c.equals(GameBalance.heal_overflow_stones(45.0), 15, "高气血上限的 45 点溢出仍封顶 15")
	_c.check(GameBalance.HEAL_OVERFLOW_STONE_CAP <= 15, "折灵石单颗封顶不超过 15（不滚成巨款）")

func _test_cultivator_system() -> void:
	# 数据表完整性：20 名修士，每名都有 名称/称号/图标/天赋/代价/独立形象 字段
	_c.equals(CultivatorData.all_ids().size(), 20, "修士扩充至 20 名")
	var bad: Array = []
	for cid in CultivatorData.all_ids():
		var d := CultivatorData.get_def(cid)
		for f in ["name", "epithet", "icon", "sprite", "pros", "cons", "mods", "start_equip"]:
			if not d.has(f):
				bad.append("%s.%s" % [cid, f])
		if not ResourceLoader.exists(String(d.get("icon", ""))):
			bad.append("%s.icon" % cid)
		# 独立形象字段非空即可（图集生成中由 Player 回退 pawn_blue 兜底）
		if String(d.get("sprite", "")).is_empty():
			bad.append("%s.sprite" % cid)
	_c.check(bad.is_empty(), "修士元数据齐全（缺: %s）" % str(bad))

	# 魅影（Ghost 原型）：闪避上限抬到 90%，锁死罡气护体；
	# 重做后走「高血高回复换输出」：血量 ×1.3、回复 +1.5、全武器伤害 -20%（伤害来源交给影层）
	GameManager.reset_run()
	GameManager.cultivator_id = "meiying"
	GameManager._apply_cultivator()
	_c.near(GameManager.dodge, 0.30, EPS, "魅影初始闪避 +30%")
	GameManager.dodge = 1.0
	_c.near(GameManager.get_effective_dodge(), 0.9, EPS, "魅影闪避上限 90%（其余人 60%）")
	_c.check("armor_up" in GameManager.locked_upgrades, "魅影锁死罡气护体")
	_c.near(GameManager.hp_regen, 1.5, EPS, "魅影初始回复 +1.5/秒（高回复定位）")
	_c.near(GameManager.weapon_damage_mult, 0.80, EPS, "魅影全武器伤害 -20%（负面代偿）")
	if GameManager.player != null:
		_c.near(GameManager.player.max_health, 120.0 * 1.30, EPS, "魅影最大生命 ×1.3（站得住怪堆）")
	_c.near(GameManager.shadow_amp_mult, 1.0, EPS, "影层增伤乘区初始为 1.0（没攒层不加伤）")

	# 加成技能是「移速那个」神行术：闪避加成 ×2 = +100%，释放期间真的每下都闪
	# （用户口径「加成技能应该是加移速那个，释放后可以百分百闪避」）
	_c.equals(CultivatorData.get_synergy_skill_id("meiying"), "gale",
			"影者契合的加成技能是神行术（移速那个），不再是缩地成寸")
	var mei_gale: Dictionary = SkillData.final_stats("gale", "meiying")
	_c.near(float(mei_gale["dodge_add"]), 1.0, EPS, "影者神行术闪避加成 +50%×2=+100%")
	_c.near(float(mei_gale["power"]), 0.60, EPS, "影者神行术移速仍是 +60%（只改闪避加成）")
	_c.near(float(mei_gale["duration"]), 4.0, EPS, "影者神行术持续仍是 4 秒")
	_c.equals(CultivatorData.get_def("meiying").get("skill_mods", {}).get("dash", null), null,
			"影者不再强化缩地成寸（冲刺回归基础距离，加成技能只此一个")

	# 额外技能槽：影者绑影爆，其余角色无；影爆免冷却、不走选择界面
	_c.equals(CultivatorData.get_extra_skill_id("meiying"), "shadowburst", "影者绑定额外技能影爆（随角色，不走五选一）")
	_c.check(CultivatorData.get_extra_skill_id("shiyue").is_empty(), "守卫无额外技能（extra_skill 缺省空串）")
	var sb: Dictionary = SkillData.get_def("shadowburst")
	_c.equals(int(sb.get("kind", -1)), SkillData.Kind.BURST, "影爆是 BURST 类（资源门控而非 CD）")
	_c.near(float(sb.get("cooldown", -1.0)), 0.0, EPS, "影爆数据表免冷却")
	_c.near(float(SkillData.final_stats("shadowburst", "meiying")["cooldown"]), 0.0, EPS,
			"final_stats 不给影爆抬 1s 冷却下限（BURST 豁免）")
	_c.check(not SkillData.OFFER_IDS.has("shadowburst"), "影爆不进选择界面候选池")

	# 卡面分段（用户 2026-10-11：攒影/影爆的说明单独开一段，不和其他天赋放在一块）。
	# 从生产入口量：真建一遍选角界面、读那几段渲染出来的文字，不看表读表。
	GameManager.cultivator_id = "meiying"
	var cs_mei := CultivatorSelect.new()
	add_child(cs_mei)
	cs_mei.show_select()   # 一次成型：不再 _select_cultivator，免得 queue_free 的旧一代混进计数
	var card_rows := _detail_info_rows(cs_mei._detail_panel)
	_c.check(card_rows.has("绝技"), "选角卡面：额外技能自己成一段（实得分段 %s）" % str(card_rows.keys()))
	_c.equals(card_rows.get("天赋", []).size(), 2, "影者天赋段只显示两条角色天赋，专属机制独立列出")
	_c.check(not str(card_rows.get("天赋", [])).contains("影"), "天赋段里不再夹带攒影/影爆那一句")
	# 渲染出来的行带 BBCode 与 wrap_cjk 硬换行；比较解析后的文字，避免复抄机制文案。
	var rendered: Array[String] = []
	for r in card_rows.get("绝技", []):
		rendered.append(String(r).replace("\n", ""))
	var want: Array[String] = []
	for w in ShadowStepData.card_lines():
		want.append(String(w))
	_c.equals(str(rendered), str(want), "绝技段逐行 == ShadowStepData.card_lines（数字现读机制表，别处不抄）")
	_c.check(str(card_rows.get("绝技", [])).contains("+%d%%" % int(roundf(ShadowStepData.AMP_PER_STACK * 100.0))),
			"段内每层增伤数与本表 AMP_PER_STACK 同源")
	cs_mei.queue_free()

	# 独臂刀圣（One Armed 原型）：上阵槽上限为 3，伤害 ×1.5（2026-10-12 战意重做后下调）、施法更快
	GameManager.reset_run()
	GameManager.cultivator_id = "dubi"
	GameManager._apply_cultivator()
	_c.equals(GameManager.max_weapon_slots(), 3, "独臂刀圣上阵槽上限为 3")
	_c.near(GameManager.weapon_damage_mult, 1.5, EPS, "独臂刀圣伤害 ×1.5（战意乘区另算）")
	_c.near(GameManager.attack_speed_mult, 0.7, EPS, "独臂刀圣施法间隔 ×0.7")

	# 狂战蛮修（Loud 原型）：妖潮 +50%，灵韵每波流失 3 点再复利；流失下限为 0
	GameManager.reset_run()
	GameManager.cultivator_id = "kuangzhan"
	GameManager._apply_cultivator()
	_c.near(GameManager.enemy_count_mult, 1.5, EPS, "狂战蛮修妖潮 +50%")
	GameManager.harvest = 10.0
	GameManager.wave_number = 2
	GameManager.apply_harvest()
	_c.near(GameManager.harvest, (10.0 - 3.0) * GameBalance.HARVEST_GROWTH, EPS, "灵韵先流失 3 点再复利")
	GameManager.harvest = 1.0
	GameManager.apply_harvest()
	_c.check(GameManager.harvest >= 0.0, "灵韵流失不会扣成负数（负值会被复利放大）")

	# 夺舍散人（Mutant 原型）：修为需求 ×0.6，且倍率不逐层复利
	GameManager.reset_run()
	GameManager.cultivator_id = "duoshe"
	GameManager._apply_cultivator()
	_c.equals(GameManager.experience_to_next, int(round(GameBalance.EXP_FIRST_LEVEL * 0.6)), "夺舍散人首级门槛 10→6")
	GameManager.add_experience(GameManager.experience_to_next)
	_c.equals(GameManager.level, 2, "夺舍散人升到 2 级")
	_c.equals(GameManager.experience_to_next, int(round(float(GameBalance.exp_to_next(GameBalance.EXP_FIRST_LEVEL)) * 0.6)), "第 2 级门槛 = 原链 ×0.6（不复利）")

	# 多宝道人：货架 +1 格、法宝 75 折
	GameManager.reset_run()
	GameManager.cultivator_id = "duobao"
	GameManager._apply_cultivator()
	GameManager.wave_number = 2
	GameManager.rng.seed = 777
	GameManager.roll_shop(true)
	_c.equals(GameManager.shop_offers.size(), GameManager.SHOP_BASE_SLOTS + 1, "多宝道人货架 %d 格" % (GameManager.SHOP_BASE_SLOTS + 1))
	_c.near(GameManager.item_price_mult, 0.75, EPS, "多宝道人法宝 75 折")

	# 苦行僧：站定伤害 +50% / 攻速 +54% / 护甲 +5；移动伤害 -60% / 攻速大减 / 移速 -10%
	GameManager.reset_run()
	GameManager.cultivator_id = "kuxingseng"
	GameManager._apply_cultivator()
	_c.near(GameManager.move_speed_mult, 0.90, EPS, "苦行僧基础移速 -10%")
	_c.check(GameManager.has_still_mechanic(), "苦行僧天生激活站定机制")
	# 移动中状态
	GameManager.still_time = 0.0
	GameManager.player_is_moving = true
	_c.near(GameManager.get_effective_armor(), 0.0, EPS, "苦行僧移动中无额外护甲")
	_c.near(CultivatorSystem.damage_mult(GameManager, "qingyun_sword"), 0.40, EPS, "苦行僧移动中全伤害 -60% (1.0 → 0.40)")
	_c.near(GameManager.get_effective_attack_speed_mult(), 1.60, EPS, "苦行僧移动中攻击间隔 +60% (1.0 → 1.60)")
	# 站定中状态
	GameManager.still_time = 0.5
	GameManager.player_is_moving = false
	_c.near(GameManager.get_effective_armor(), 5.0, EPS, "苦行僧站定时护甲 +5")
	_c.near(CultivatorSystem.damage_mult(GameManager, "qingyun_sword"), 1.50, EPS, "苦行僧站定时全伤害 +50% (1.0 → 1.50)")
	_c.near(GameManager.get_effective_attack_speed_mult(), 0.65, EPS, "苦行僧站定时攻击间隔 -35% (1.0 → 0.65)")

	# 回归：常规修士不污染通用机制
	GameManager.reset_run()
	GameManager.cultivator_id = "jianchi"
	GameManager._apply_cultivator()
	_c.equals(GameManager.max_weapon_slots(), WeaponData.MAX_SLOTS, "常规修士槽位 6")
	_c.near(GameManager.enemy_count_mult, 1.0, EPS, "常规修士妖潮规模不变")
	GameManager.dodge = 1.0
	_c.near(GameManager.get_effective_dodge(), GameManager.DODGE_CAP, EPS, "常规修士闪避上限仍 60%")

	# 道统选择界面上下分层与开局装备验证
	_c.check(not CultivatorData.get_start_equip("fuzhen").is_empty(), "符阵灵童明确说明开局额外自带装备")
	_c.check(CultivatorData.get_start_equip("jianchi").is_empty(), "无额外装备的角色不标注开局装备")

	# 御兽师契合技能加成有效性（修复 power_add 死键，强化文案正常渲染）
	var yushou_syn_sid := CultivatorData.get_synergy_skill_id("yushou")
	_c.equals(yushou_syn_sid, "renewal", "御兽师契合治疗技能")
	var yushou_enh := SkillData.enhance_desc(yushou_syn_sid, "yushou")
	_c.check(not yushou_enh.is_empty(), "御兽师契合治疗强化文案非空（实得: %s）" % yushou_enh)
	_c.check(yushou_enh.contains("回复量"), "御兽师契合强化文案包含回复量加成")
	var cs := CultivatorSelect.new()
	add_child(cs)
	cs.show_select()
	_c.equals(cs._roster_grid.get_child_count(), 20, "道统选择界面下半部分两排网格展示 20 张形象小卡片")
	_c.check(cs._detail_panel.visible, "道统选择界面上半部分详解大卡片正常可见")
	cs._select_cultivator("fuzhen")
	_c.equals(cs._selected_id, "fuzhen", "点击小卡片即时切换至对应修士")
	cs.queue_free()

	GameManager.reset_run()

## 走一遍详解卡中列，返回 {分类色签: [该段正文各行]}。
## 认的是渲染出来的形状（色签 + 正文盒），不认节点名：代码建的控件名带 @N 后缀，按名取会拿到空。
func _detail_info_rows(host: Control) -> Dictionary:
	var out: Dictionary = {}
	var pending: Array = [host]
	while not pending.is_empty():
		var n: Node = pending.pop_back()
		for c in n.get_children():
			pending.append(c)
		if not (n is HBoxContainer) or n.get_child_count() < 2:
			continue
		var hb := n as HBoxContainer
		var tag_lbl := hb.get_child(0) as Label
		var vb := hb.get_child(1) as VBoxContainer
		if tag_lbl == null or vb == null:
			continue
		var lines: Array[String] = []
		for l in vb.get_children():
			if l is RichTextLabel:
				var plain := String((l as RichTextLabel).text).replace("[lb]", "\n")
				var regex := RegEx.new()
				regex.compile("\\[/?(?:color|b|i|u|s|font_size|font|outline_size|outline_color)(?:=[^\\]]*)?\\]")
				lines.append(regex.sub(plain, "", true))
			elif l is Label:
				lines.append(String((l as Label).text))
		if not lines.is_empty():
			out[String(tag_lbl.text).strip_edges()] = lines
	return out

# ---------------- 震退方向 ----------------

## 法器震退的方向判据：以落点径向为主，但任何一次震退都不许带「朝玩家」的分量。
## 现场（用户 2026-10-08）：番天镇岳印的落点是按角度扇区分给各法器的，常常砸在玩家外侧的敌人上，
## 纯径向就把「落点与玩家之间」那一圈敌人一波一波拱到身上 —— 不崩不报错，只有真机挨打才发现。

func _test_turret_and_new_cultivators() -> void:
	# 1. 机关法器基础定义与行为校验
	for wid in ["jiguan_nu", "jianzhen_pan", "penhuo_jiguanshou"]:
		var wdef := WeaponData.get_def(wid)
		_c.equals(int(wdef.get("behavior", -1)), WeaponData.Behavior.TURRET, "%s 行为为 TURRET" % wid)
		_c.check("contraption" in WeaponData.tags_of(wid), "%s 包含 contraption 机关标签" % wid)
		_c.check(float(wdef.get("turret_lifetime", 0.0)) > 0.0, "%s 声明了炮台寿命" % wid)
		_c.check(float(wdef.get("turret_fire_cd", 0.0)) > 0.0, "%s 声明了开火间隔" % wid)

	# 2. 机关羁绊阶梯结算
	GameManager.reset_run()
	_c.near(GameManager.synergy_contraption_mult, 1.0, EPS, "无机关法器时羁绊乘区为 1.0")

	# 3. 机关师（jiguan）：机关门槛 -1，初始机关伤害 +3
	GameManager.cultivator_id = "jiguan"
	GameManager._apply_cultivator()
	_c.equals(GameManager.contraption_threshold_adj, 1, "机关师机关门槛下移 1")
	_c.near(GameManager.contraption_damage, 3.0, EPS, "机关师初始机关伤害 +3")

	# 4. 灵植夫（lingzhifu）：2026-10-11 身份重做「灵药滋生」——收益 +12、伤害 ×0.90、掉珠率与溢出倍率
	GameManager.reset_run()
	GameManager.cultivator_id = "lingzhifu"
	GameManager._apply_cultivator()
	_c.near(GameManager.harvest, 12.0, EPS, "灵植夫初始收益 +12")
	_c.near(GameManager.weapon_damage_mult, 0.90, EPS, "灵植夫全武器伤害 ×0.90（重做后放宽）")

	# 5. 雷法真君（leifa）：元素伤害 +3，雷系/符箓加成，剑系减伤
	GameManager.reset_run()
	GameManager.cultivator_id = "leifa"
	GameManager._apply_cultivator()
	_c.near(GameManager.elemental_damage, 3.0, EPS, "雷法真君初始元素伤害 +3")
	_c.near(GameManager.cultivator_damage_mult("jinlei_zhui"), 1.30, EPS, "雷法真君雷系法器伤害 +30%")
	_c.near(GameManager.cultivator_damage_mult("qingyun_sword"), 0.60, EPS, "雷法真君剑系法器伤害 -40%")

	# 6. 守财奴（shoucainu）：结息 8%
	GameManager.reset_run()
	GameManager.cultivator_id = "shoucainu"
	GameManager._apply_cultivator()
	_c.near(GameManager.stone_interest_rate, 0.08, EPS, "守财奴结息比率 8%")
	GameManager.spirit_stones = 100
	GameManager.wave_number = 1
	GameManager.apply_harvest()
	_c.equals(GameManager.spirit_stones, 108, "100 灵石结息 8% 到账 8 枚灵石")

	# 7. 嗜血魔修（shixue）：受击增伤
	GameManager.reset_run()
	GameManager.cultivator_id = "shixue"
	GameManager._apply_cultivator()
	_c.near(GameManager.armor, -3.0, EPS, "嗜血魔修初始护甲 -3")
	_c.near(GameManager.cultivator_damage_mult("qingyun_sword"), 1.0, EPS, "受击前无额外增伤")
	GameManager.on_player_hit(10.0)
	_c.equals(GameManager.on_hit_damage_stacks, 1, "受击 1 次叠 1 层")
	_c.near(GameManager.cultivator_damage_mult("qingyun_sword"), 1.03, EPS, "受击 1 次增伤 +3%")
	GameManager.reset_run()

	# 7.5 驯兽师（fuzhen）本体强化：开局双生蝶 + 召唤伤害 + 灵宝专精乘区
	GameManager.reset_run()
	GameManager.cultivator_id = "fuzhen"
	GameManager._apply_cultivator()
	_c.equals(GameManager.drones.size(), 1, "驯兽师开局 1 条护蝶（2026-10-11 收：原 2 条★2 白送三波收入）")
	_c.equals(GameManager._drone_star(GameManager.drones[0]), 2, "驯兽师开局护蝶 ★2（分身为二）")
	_c.near(GameManager.engineering_damage, 2.0, EPS, "驯兽师召唤伤害 +2")
	_c.near(GameManager.cultivator_damage_mult("lingdie"), 1.12, EPS, "驯兽师灵宝专精 +12%")
	_c.near(GameManager.cultivator_damage_mult("qingyun_sword"), 0.7, EPS, "驯兽师非召唤武器伤害 -30% 保留")
	_c.equals(WeaponData.drone_orb_count(1), 1, "★1 灵宝单具")
	_c.equals(WeaponData.drone_orb_count(2), 2, "★2 灵宝分身为二")
	_c.equals(WeaponData.drone_orb_count(3), 3, "★3 灵宝分身为三")
	GameManager.reset_run()

	# 7.6 灵符子（fuxiu）：符箓专精 +35%，非符箓 -25%（non_tag_damage 通用键首用）
	GameManager.reset_run()
	GameManager.cultivator_id = "fuxiu"
	GameManager._apply_cultivator()
	_c.near(GameManager.elemental_damage, 2.0, EPS, "灵符子初始元素伤害 +2")
	_c.near(GameManager.cultivator_damage_mult("huoyan_fu"), 1.35, EPS, "灵符子符箓法器伤害 +35%")
	_c.near(GameManager.cultivator_damage_mult("qingyun_sword"), 0.75, EPS, "灵符子非符箓法器伤害 -25%")
	_c.near(GameManager.cultivator_damage_mult("bajiao_fan"), 0.75, EPS, "灵符子横扫法器同样吃 -25% 代偿")
	GameManager.reset_run()

	# 7.7 霸王（bawang）：横扫专精 +30%，非横扫 -25%
	GameManager.reset_run()
	GameManager.cultivator_id = "bawang"
	GameManager._apply_cultivator()
	_c.near(GameManager.armor, 2.0, EPS, "霸王初始护甲 +2")
	_c.near(GameManager.cultivator_damage_mult("bajiao_fan"), 1.30, EPS, "霸王横扫法器伤害 +30%")
	_c.near(GameManager.cultivator_damage_mult("qingyun_sword"), 0.75, EPS, "霸王非横扫法器伤害 -25%")
	_c.near(GameManager.cultivator_damage_mult("huoyan_fu"), 0.75, EPS, "霸王符箓法器同样吃 -25% 代偿")
	GameManager.reset_run()

	# 7.8 两名专精修士的成就解锁判定（器类峰值账本 → run_ctx → is_condition_met）
	_c.check(AchievementData.is_condition_met("ach_cult_fuxiu", {"max_class_counts": {"talisman": 4}}, {}),
		"同时上阵 4 件符箓法器达成【万符朝宗】")
	_c.check(not AchievementData.is_condition_met("ach_cult_fuxiu", {"max_class_counts": {"talisman": 3}}, {}),
		"3 件符箓法器不达成【万符朝宗】")
	_c.check(AchievementData.is_condition_met("ach_cult_bawang", {"max_class_counts": {"wide": 4}}, {}),
		"同时上阵 4 件横扫法器达成【横扫千军】")
	_c.check(not AchievementData.is_condition_met("ach_cult_bawang", {}, {}),
		"无器类峰值账本时不达成【横扫千军】")
	_c.equals(AchievementData.cultivator_unlock_achievement("fuxiu").get("id", ""), "ach_cult_fuxiu", "灵符子反查解锁成就一致")
	_c.equals(AchievementData.cultivator_unlock_achievement("bawang").get("id", ""), "ach_cult_bawang", "霸王反查解锁成就一致")
	_c.equals(AchievementData.cultivator_unlock_achievement("juechen").get("id", ""), "ach_cult_juechen", "绝尘反查解锁成就一致")
	_c.check(AchievementData.is_condition_met("ach_cult_juechen", {"max_class_counts": {"sword": 4}}, {}),
		"同时上阵 4 件剑类法器达成【心剑通神】")
	_c.check(not AchievementData.is_condition_met("ach_cult_juechen", {"max_class_counts": {"sword": 3}}, {}),
		"3 件剑类法器不达成【心剑通神】")

	# 7.8.1 2026-10-12 新增流派/试炼成就判定（纯荣誉型，不发奖励）
	_c.check(AchievementData.is_condition_met("ach_style_thunder", {"max_class_counts": {"thunder": 4}}, {}),
		"同时上阵 4 件雷法法器达成【五雷正法】")
	_c.check(not AchievementData.is_condition_met("ach_style_thunder", {"max_class_counts": {"thunder": 3}}, {}),
		"3 件雷法法器不达成【五雷正法】")
	_c.check(AchievementData.is_condition_met("ach_style_wuxing", {"max_element_spread": 5}, {}),
		"五行同阵（5 元素齐聚）达成【五行同阵】")
	_c.check(not AchievementData.is_condition_met("ach_style_wuxing", {"max_element_spread": 4}, {}),
		"4 种元素不达成【五行同阵】")
	_c.check(AchievementData.is_condition_met("ach_feat_nightmare", {"victory": true, "danger": 3}, {}),
		"通关噩梦达成【征服噩梦】")
	_c.check(not AchievementData.is_condition_met("ach_feat_nightmare", {"victory": true, "danger": 2}, {}),
		"通关困难不达成【征服噩梦】")
	_c.check(AchievementData.is_condition_met("ach_feat_extreme", {"victory": true, "danger": 5}, {}),
		"通关极限达成【征服极限】")
	_c.check(AchievementData.is_condition_met("ach_feat_endless", {"endless": true, "wave": 25}, {}),
		"无尽第 25 波达成【无尽行者】")
	_c.check(not AchievementData.is_condition_met("ach_feat_endless", {"endless": true, "wave": 24}, {}),
		"无尽第 24 波不达成【无尽行者】")
	_c.check(not AchievementData.is_condition_met("ach_feat_endless", {"victory": true, "wave": 25}, {}),
		"非无尽路径抵达 25 波不达成【无尽行者】")
	_c.check(AchievementData.is_condition_met("ach_grind_kills", {}, {"total_kills": 5000}),
		"累计击杀 5000 达成【千杀灭生】")
	_c.check(AchievementData.is_condition_met("ach_grind_wins", {}, {"total_wins": 10}),
		"累计通关 10 次达成【十渡天劫】")

	# 7.8.2 成就进度短句（选人页解锁提示数据源，口径 = career_stats 单局生涯最佳）
	_c.equals(AchievementData.progress_text("ach_cult_bawang", {"best_class_counts": {"wide": 2}}),
		"单局最佳 2/4 件", "【横扫千军】进度随器类峰值推进")
	_c.equals(AchievementData.progress_text("ach_cult_bawang", {}),
		"单局最佳 0/4 件", "无峰值记录时【横扫千军】进度从 0 起")
	_c.equals(AchievementData.progress_text("ach_cult_kuangzhan", {"total_kills": 1230}),
		"累计击杀 1230/1500", "【百战不殆】进度读累计击杀")
	_c.equals(AchievementData.progress_text("ach_cult_duoshe", {"total_wins": 3}),
		"已通关 3 次", "【初次通关】进度读累计通关")
	_c.equals(AchievementData.progress_text("ach_cult_dubi", {"best_danger_cleared": 1}),
		"最高通关「普通」", "【极限挑战】进度读最高通关难度")
	_c.equals(AchievementData.progress_text("ach_cult_dubi", {}),
		"尚未通关任意难度", "从未通关时【极限挑战】显示兜底文案")
	_c.equals(AchievementData.progress_text("ach_feat_endless", {}),
		"", "无量化口径的成就返回空串（调用方不显示进度行）")

	# 7.9 绝尘（斩灭凝神）：杀怪减神通 CD 与持续期预扣无缝衔接
	GameManager.reset_run()
	GameManager.cultivator_id = "juechen"
	GameManager._apply_cultivator()
	_c.near(GameManager.weapon_damage_mult, 0.80, EPS, "绝尘全武器基础伤害 ×0.80")
	_c.near(GameManager.kill_cd_reduction_normal, 0.4, EPS, "绝尘普通怪冷却返还 0.4s")
	_c.near(GameManager.kill_cd_reduction_elite, 2.0, EPS, "绝尘精英怪冷却返还 2.0s")
	var dummy_p := Player.new()
	GameManager.player = dummy_p
	dummy_p.skill_cd_left = 5.0
	dummy_p.skill_active_left = 0.0
	GameManager.register_kill(false)
	_c.near(dummy_p.skill_cd_left, 4.6, EPS, "冷却中击杀普通怪直接扣减 0.4s CD")
	GameManager.register_kill(true)
	_c.near(dummy_p.skill_cd_left, 2.6, EPS, "冷却中击杀精英怪直接扣减 2.0s CD")
	dummy_p.refund_skill_cooldown(10.0)
	_c.near(dummy_p.skill_cd_left, 0.0, EPS, "冷却扣减下限钳在 0.0")
	# 持续生效期间预扣后续冷却
	dummy_p.skill_active_left = 3.0
	dummy_p._skill_pending_cd = 3.0
	GameManager.register_kill(false)
	_c.near(dummy_p._skill_pending_cd, 2.6, EPS, "神通持续期间击杀预扣待进入冷却 0.4s")
	GameManager.register_kill(true)
	_c.near(dummy_p._skill_pending_cd, 0.6, EPS, "神通持续期间击杀精英预扣 2.0s")
	GameManager.register_kill(true)
	_c.near(dummy_p._skill_pending_cd, 0.0, EPS, "持续期间预扣至 0.0")
	dummy_p._begin_skill_cooldown()
	_c.near(dummy_p.skill_cd_left, 0.0, EPS, "预扣归零后结束持续期直接就绪，零延迟无缝连发")
	GameManager.player = null
	dummy_p.free()
	GameManager.reset_run()
	_c.near(GameManager.kill_cd_reduction_normal, 0.0, EPS, "reset_run 复位绝尘冷却返还参数")

	# 7. 数据表三件御灵装备属性强化验证（射程全面扩展至 >= 170px，伤害 >= 20）
	for sid in ["lingdie", "hanquan_yulian", "hunyuan_zhong"]:
		var sdef := WeaponData.get_def(sid)
		_c.check(float(sdef.get("range", 0.0)) >= 170.0, "御灵法器 %s 射程强化至 >= 170px（当前 %.0f）" % [sid, float(sdef.get("range", 0.0))])
		_c.check(float(sdef.get("damage", 0.0)) >= 20.0, "御灵法器 %s 基础伤害 >= 20（当前 %.0f）" % [sid, float(sdef.get("damage", 0.0))])
		_c.check(float(sdef.get("knockback", 0.0)) >= 160.0, "御灵法器 %s 击退强化至 >= 160（当前 %.0f）" % [sid, float(sdef.get("knockback", 0.0))])

	# 8. 召唤羁绊两收益验证（气血 / 召唤伤害）
	#    2026-10-11 撤销了那条环绕专属伤害乘区（局内曾叫「灵宝伤害」），幅度全折进召唤伤害这条加法。
	GameManager.reset_run()
	GameManager.drones = [1, 1]  # 2 件护蝶
	SynergySystem.recalc_synergies(GameManager)
	_c.near(GameManager.synergy_max_hp_bonus, 15.0, EPS, "2 召唤获得 +15 气血上限")
	_c.near(GameManager.synergy_engineering_damage, 4.0, EPS, "2 召唤获得 +4 召唤伤害（幅度折自原环绕乘区档）")
	var stat_dict := GameManager.get_player_stat_dict()
	_c.near(float(stat_dict.get("engineering_damage", 0.0)), 4.0, EPS, "角色属性表包含召唤羁绊召唤伤害")
	# 召唤不许再往全局武器伤害里写：护蝶同带木标签，这里实得 1.06 全部来自木系第 1 档
	_c.near(GameManager.synergy_damage_mult, 1.06, EPS, "召唤不给武器伤害乘区（1.06 全是木系那档）")
	SynergySystem.apply_counts(GameManager, {"spirit": 2})
	_c.near(GameManager.synergy_damage_mult, 1.0, EPS, "单算召唤第 1 档：武器伤害乘区纹丝不动")
	GameManager.reset_run()

	# 8. 多法器神识分流与同目标短窗集火韧性验证
	# 2026-10-15 反割草收紧：分流系数 0.12→0.15（6 把总输出 3.75x→3.43x）
	_c.near(GameBalance.multi_weapon_damage_mult(1), 1.0, EPS, "单把法器神识效率 100%")
	_c.near(GameBalance.multi_weapon_damage_mult(6), 1.0 / 1.75, EPS, "6 把法器单把神识分流系数 ~57.1%（总有效倍率 3.43x）")
	var prev_tot := 0.0
	var tot_monotonic := true
	for n_slots in range(1, 7):
		var tot := float(n_slots) * GameBalance.multi_weapon_damage_mult(n_slots)
		if tot <= prev_tot:
			tot_monotonic = false
		prev_tot = tot
	_c.check(tot_monotonic, "1~6 把法器总有效倍率严格单调递增（多戴必正收益）")
	# 2026-10-11 召唤流校准：御灵按半权计神识分流（召唤物自主作战不占主人神识）
	_c.near(GameBalance.multi_weapon_damage_mult(6, 0), 1.0 / 1.75, EPS, "纯非召唤 6 把分流不受御灵半权影响（仍 ~57.1%）")
	_c.near(GameBalance.multi_weapon_damage_mult(6, 6), 1.0 / 1.30, EPS, "6 御灵半权分流：有效 3 把 ⇒ 单把 ~76.9%（以多打少不再被拖死）")
	_c.check(GameBalance.multi_weapon_damage_mult(6, 6) > GameBalance.multi_weapon_damage_mult(6, 0),
		"同槽位下御灵半权分流系数高于全额口径")
	_c.near(GameBalance.focus_fire_mult(0), 1.0, EPS, "短窗第 1 击全额 100%")
	_c.near(GameBalance.focus_fire_mult(1), 0.70, EPS, "短窗第 2 击折算 70%")
	_c.near(GameBalance.focus_fire_mult(2), 0.50, EPS, "短窗第 3 击折算 50%")
	_c.near(GameBalance.focus_fire_mult(5), 0.50, EPS, "短窗后续连击保底 50%")

## 五弱修士机制重做（2026-10-11）：盾势/服丹/灵药滋生/博学/图鉴五组新 mod 键的钉点。
## 运行时链路（受击蓄能、服丹回血）由 tests/GuardStanceCheck / tests/ElixirCheck 钉，这里只钉
## 数据表 → apply 落地 → 乘区兑现这一路的数字同源。
func _test_cultivator_new_mechanics() -> void:
	# —— 守卫·盾势：纯函数同源（槽上限/蓄能钳制/满判定/爆发系数）——
	_c.near(GuardStanceData.cap_of(200.0), 200.0 * GuardStanceData.CAP_HP_RATIO, EPS, "盾势槽 = 气血 × %.0f%%" % (GuardStanceData.CAP_HP_RATIO * 100.0))
	_c.near(GuardStanceData.add_charge(0.0, 30.0, 200.0), 30.0 * GuardStanceData.STORE_RATIO, EPS, "挡下 30 按比率蓄能")
	_c.near(GuardStanceData.add_charge(90.0, 30.0, 200.0), GuardStanceData.cap_of(200.0), EPS, "蓄能顶到上限为止")
	_c.check(GuardStanceData.is_full(GuardStanceData.cap_of(200.0), 200.0), "到上限判满")
	_c.near(GuardStanceData.burst_damage(100.0), 100.0 * GuardStanceData.BURST_RATIO, EPS, "爆发 = 蓄能 × %.1f" % GuardStanceData.BURST_RATIO)
	# 守卫 apply 落地
	GameManager.reset_run()
	GameManager.cultivator_id = "shiyue"
	GameManager._apply_cultivator()
	_c.check(GameManager.guard_stance > 0.0, "守卫盾势开关落地")
	_c.near(GameManager.shield_charge, 0.0, EPS, "开局盾势为空")

	# —— 药王·药爆：纯函数 + 绑定 + 带冷却 ——
	_c.near(ElixirData.heal_amount(200.0), 200.0 * ElixirData.HEAL_HP_RATIO, EPS, "药爆回血 = 气血 × %.0f%%" % (ElixirData.HEAL_HP_RATIO * 100.0))
	_c.near(ElixirData.burst_damage(3.0), ElixirData.BASE_DAMAGE + 3.0 * ElixirData.ELEMENTAL_RATIO, EPS, "药爆毒伤 = 基础 + 元素 × %.1f" % ElixirData.ELEMENTAL_RATIO)
	_c.near(ElixirData.buff_mult(), 1.0 + ElixirData.BUFF_DAMAGE, EPS, "药爆增伤乘区与本表同源")
	_c.equals(CultivatorData.get_extra_skill_id("yaowang"), "elixir", "药王绑定额外技能药爆（随角色，不走五选一）")
	var el: Dictionary = SkillData.get_def("elixir")
	_c.equals(int(el.get("kind", -1)), SkillData.Kind.HEAL, "药爆是 HEAL 类（治疗+毒雾爆发）")
	_c.near(float(SkillData.final_stats("elixir", "yaowang")["cooldown"]), ElixirData.COOLDOWN, EPS, "final_stats 读取药爆冷却 %.1fs" % ElixirData.COOLDOWN)
	_c.check(not SkillData.OFFER_IDS.has("elixir"), "药爆不进选择界面候选池")
	_c.equals(str(CultivatorData.get_extra_desc("yaowang")), str(ElixirData.card_lines()), "药爆卡面说明现读 ElixirData（别处不抄）")

	# —— 灵植夫·灵药滋生：掉珠率与溢出折灵石倍率落地 ——
	GameManager.reset_run()
	GameManager.cultivator_id = "lingzhifu"
	GameManager._apply_cultivator()
	_c.near(GameManager.heal_orb_chance, 0.15, EPS, "灵植夫敌人 15% 额外掉回复珠")
	_c.near(GameManager.heal_overflow_mult, 2.0, EPS, "灵植夫回复珠溢出折灵石 ×2")
	GameManager.reset_run()
	GameManager.cultivator_id = "jianchi"
	GameManager._apply_cultivator()
	_c.near(GameManager.heal_orb_chance, 0.0, EPS, "非灵植夫不掉额外回复珠（数据门控，非 id 门控）")
	_c.near(GameManager.heal_overflow_mult, 1.0, EPS, "非灵植夫溢出折灵石倍率 1.0")

	# —— 学者·博学：候选 +1、免费刷新 +1，开会话真兑现 ——
	GameManager.reset_run()
	GameManager.cultivator_id = "duoshe"
	GameManager._apply_cultivator()
	_c.equals(GameManager.alloc_offer_bonus, 1, "学者悟道候选 +1 落地")
	_c.equals(GameManager.alloc_free_reroll_bonus, 1, "学者每回合免费刷新 +1 落地")
	GameManager.pending_upgrade_points = 1
	GameManager.open_alloc_session()
	_c.equals(GameManager.alloc_offers.size(), GameManager.UPGRADE_OFFER_COUNT + 1, "学者悟道一屏 %d 张卡" % (GameManager.UPGRADE_OFFER_COUNT + 1))
	_c.equals(GameManager.alloc_reroll_free_left, GameManager.ALLOC_FREE_REROLLS + 1, "学者每回合 %d 次免费刷新" % (GameManager.ALLOC_FREE_REROLLS + 1))
	GameManager.pending_upgrade_points = 0

	# —— 收藏家·图鉴：每种不同法宝全伤害 +2%，种数账本两写点维护 ——
	GameManager.reset_run()
	GameManager.cultivator_id = "duobao"
	GameManager._apply_cultivator()
	_c.near(GameManager.collection_damage_per_unique, 0.02, EPS, "收藏家图鉴每件加成落地")
	_c.near(GameManager.cultivator_damage_mult("qingyun_sword"), 1.0, EPS, "空收藏无加成")
	GameManager.add_item("jubaopen")
	GameManager.add_item("jubaopen")
	_c.equals(GameManager.unique_item_count, 1, "重复购买同种法宝种数不涨")
	_c.near(GameManager.cultivator_damage_mult("qingyun_sword"), 1.02, EPS, "1 种法宝 +2%")
	GameManager.add_item("qiankun_dai")
	_c.equals(GameManager.unique_item_count, 2, "新种法宝种数 +1")
	_c.near(GameManager.cultivator_damage_mult("qingyun_sword"), 1.04, EPS, "2 种法宝 +4%")
	GameManager.consume_item("jubaopen")
	_c.equals(GameManager.unique_item_count, 2, "还有一件同种时种数不掉")
	GameManager.consume_item("jubaopen")
	_c.equals(GameManager.unique_item_count, 1, "消耗掉最后一件同种，种数 -1")
	_c.near(GameManager.cultivator_damage_mult("qingyun_sword"), 1.02, EPS, "图鉴加成跟着种数回落")
	GameManager.reset_run()
	GameManager.cultivator_id = "jianchi"
	GameManager._apply_cultivator()
	GameManager.add_item("jubaopen")
	_c.near(GameManager.cultivator_damage_mult("qingyun_sword"), 1.35, EPS, "非收藏家买法宝不给图鉴加成（剑痴仍只有剑系 +35%）")
	GameManager.reset_run()

func _test_cultivator_frenzy_thunder_shop() -> void:
	# —— 狂战士·战意：纯函数同源（攒层/上限/乘区/宽限/流失/保底）——
	_c.near(FrenzyData.add_stack(0.0), 1.0, EPS, "击杀 +1 层")
	_c.near(FrenzyData.add_stack(float(FrenzyData.MAX_STACKS)), float(FrenzyData.MAX_STACKS), EPS, "层数顶到上限为止")
	_c.near(FrenzyData.damage_mult(0.0), 1.0, EPS, "0 层无加成")
	_c.near(FrenzyData.damage_mult(float(FrenzyData.MAX_STACKS)), 1.0 + float(FrenzyData.MAX_STACKS) * FrenzyData.PER_STACK, EPS, "满层 +%d%%" % int(roundf(float(FrenzyData.MAX_STACKS) * FrenzyData.PER_STACK * 100.0)))
	_c.near(FrenzyData.decay(10.0, FrenzyData.DECAY_DELAY - 0.1, 1.0), 10.0, EPS, "宽限内不流失")
	_c.near(FrenzyData.decay(10.0, FrenzyData.DECAY_DELAY + 0.1, 1.0), 10.0 - FrenzyData.DECAY_PER_SEC, EPS, "过宽限按速率流失")
	_c.near(FrenzyData.decay(1.0, FrenzyData.DECAY_DELAY + 0.1, 1.0), 0.0, EPS, "流失保底归零不为负")
	# 狂战士 apply 落地 + 击杀攒层（register_kill 唯一攒点）
	GameManager.reset_run()
	GameManager.cultivator_id = "dubi"
	GameManager._apply_cultivator()
	_c.check(GameManager.frenzy_enabled > 0.0, "狂战士战意开关落地")
	_c.near(GameManager.frenzy_stacks, 0.0, EPS, "开局战意为 0")
	GameManager.register_kill()
	GameManager.register_kill()
	_c.near(GameManager.frenzy_stacks, 2.0, EPS, "两次击杀攒 2 层")
	_c.near(GameManager.cultivator_damage_mult("qingyun_sword"), FrenzyData.damage_mult(2.0), EPS, "2 层战意全伤害 +%d%%" % int(roundf(FrenzyData.PER_STACK * 200.0)))
	for i in range(FrenzyData.MAX_STACKS + 5):
		GameManager.register_kill()
	_c.near(GameManager.frenzy_stacks, float(FrenzyData.MAX_STACKS), EPS, "连杀封顶 %d 层" % FrenzyData.MAX_STACKS)
	_c.near(GameManager.frenzy_idle, 0.0, EPS, "每次击杀把流失宽限计时归零")
	# 流失走 GameManager._process（直接拨时钟，不烧真秒）
	GameManager._process(FrenzyData.DECAY_DELAY - 0.2)
	_c.near(GameManager.frenzy_stacks, float(FrenzyData.MAX_STACKS), EPS, "宽限内时钟空转不掉层")
	GameManager._process(1.0)   # 这一拍越过宽限 → 当拍开始泄
	_c.check(GameManager.frenzy_stacks < float(FrenzyData.MAX_STACKS), "越过宽限开始流失")
	# 非狂战士：击杀不攒层（数据门控，非 id 门控）
	GameManager.reset_run()
	GameManager.cultivator_id = "jianchi"
	GameManager._apply_cultivator()
	GameManager.register_kill()
	_c.near(GameManager.frenzy_stacks, 0.0, EPS, "非狂战士击杀不攒战意")
	_c.near(GameManager.cultivator_damage_mult("qingyun_sword"), 1.35, EPS, "非狂战士无战意乘区（剑痴仍只有剑系 +35%）")

	# —— 雷法真君·天雷：纯函数同源 + 开关落地 ——
	_c.near(ThunderData.bolt_damage(0.0), ThunderData.BASE_DAMAGE, EPS, "0 元素雷伤 = 基础值")
	_c.near(ThunderData.bolt_damage(3.0), ThunderData.BASE_DAMAGE + 3.0 * ThunderData.ELEMENTAL_RATIO, EPS, "雷伤随元素成长")
	GameManager.reset_run()
	GameManager.cultivator_id = "leifa"
	GameManager._apply_cultivator()
	_c.check(GameManager.thunder_strike > 0.0, "雷法天雷开关落地")
	GameManager.reset_run()
	GameManager.cultivator_id = "jianchi"
	GameManager._apply_cultivator()
	_c.near(GameManager.thunder_strike, 0.0, EPS, "非雷法不落雷（数据门控）")

	# —— 商人·老主顾：每波首掷免费 + 重掷半价，走 ShopSystem 既有免单口径 ——
	GameManager.reset_run()
	GameManager.cultivator_id = "jinsuanpan"
	GameManager._apply_cultivator()
	_c.equals(GameManager.free_rerolls, 1, "商人每波免费重掷 +1 落地")
	_c.near(GameManager.reroll_price_mult, 0.5, EPS, "商人重掷半价落地")
	GameManager.wave_number = 1
	GameManager.roll_shop(true)
	_c.equals(GameManager.reroll_free_left, 1, "开波货架重置出 1 次免费重掷")
	var want_cost: int = maxi(1, int(round(GameBalance.reroll_cost(1, 0, GameManager.shop_price_mult) * 0.5)))
	_c.equals(GameManager.reroll_cost, want_cost, "重掷价 = 纯函数结果 × 0.5（GameBalance 不掺角色）")
	GameManager.spirit_stones = 100
	GameManager.reroll_shop()
	_c.equals(GameManager.spirit_stones, 100, "首掷走免费次数，一枚不花")
	_c.equals(GameManager.reroll_count, 0, "免费重掷不推进计费次数")
	GameManager.reroll_shop()
	_c.equals(GameManager.spirit_stones, 100 - want_cost, "第二掷付半价 %d 灵石" % want_cost)
	# 非商人：无免费次数、全价
	GameManager.reset_run()
	GameManager.cultivator_id = "jianchi"
	GameManager._apply_cultivator()
	GameManager.wave_number = 1
	GameManager.roll_shop(true)
	_c.equals(GameManager.reroll_free_left, 0, "非商人无免费重掷")
	_c.equals(GameManager.reroll_cost, GameBalance.reroll_cost(1, 0, 1.0), "非商人重掷全价（乘区 1.0）")
	GameManager.reset_run()

## 2026-10-12 流派闭环：法宝转化件（item_hook_sum 现算）+ 武器交叉格补洞 + 蛮兵陷阵/守财奴财可通神
func _test_conversion_items_and_hooks() -> void:
	# —— 新内容在库：13 件法宝 + 8 把法器进池 ——
	for iid in ["jifeng_ren", "huanying_ling", "shanyue_jia", "xuepan_guyu", "jubao_pen",
			"ranxue_fu", "budong_yin", "liehun_ling",
			"taijin_jing", "yimu_sui", "xuanshui_po", "lihuo_shenjing", "houtu_shenyuan"]:
		_c.check(not ItemData.get_def(iid).is_empty(), "法宝在库：%s" % iid)
	for wid in ["taomu_jian", "guishui_fu", "houtu_fu", "jinxiao_leiling",
			"xuanming_leizhu", "qingmu_pao", "ningbing_nu", "fenghuo_tai"]:
		_c.check(not WeaponData.get_def(wid).is_empty(), "新法器在库：%s" % wid)
		_c.check(wid in WeaponData.SHOP_POOL, "新法器进商店池：%s" % wid)
	# 交叉格补齐：原 8 个空洞格（各仅 1 把）现在都凑得出羁绊 2 件档
	for pair in [["sword", "wood"], ["talisman", "water"], ["talisman", "earth"], ["thunder", "metal"],
			["thunder", "water"], ["contraption", "wood"], ["contraption", "water"], ["contraption", "fire"]]:
		var cell_n := 0
		for id in WeaponData.DEFS.keys():
			var tags: Array = WeaponData.get_def(id).get("tags", [])
			if pair[0] in tags and pair[1] in tags:
				cell_n += 1
		_c.check(cell_n >= 2, "交叉格 %s×%s 至少 2 把（实得 %d）" % [pair[0], pair[1], cell_n])

	# —— 转化乘区：与角色无关，裸局也生效（def 早退之前结算）——
	GameManager.reset_run()
	_c.near(GameManager.cultivator_damage_mult("qingyun_sword"), 1.0, EPS, "裸局无转化乘区")
	GameManager.add_item("shanyue_jia")
	GameManager.armor = 10.0
	_c.near(GameManager.cultivator_damage_mult("qingyun_sword"), 1.0 + 10.0 * 0.015, EPS, "山岳战甲：每点护甲 +1.5%")
	GameManager.reset_run()
	GameManager.add_item("jifeng_ren")
	_c.near(GameManager.cultivator_damage_mult("qingyun_sword"), 1.0, EPS, "疾风刃：基础移速无加成")
	GameManager.move_speed_mult = 1.3
	_c.near(GameManager.cultivator_damage_mult("qingyun_sword"), 1.0 + 0.3 * 10.0 * 0.04, EPS, "疾风刃：移速 +30% → 伤害 +12%")
	GameManager.reset_run()
	GameManager.add_item("jubao_pen")
	GameManager.spirit_stones = 500
	_c.near(GameManager.cultivator_damage_mult("qingyun_sword"), 1.0 + 5.0 * 0.03, EPS, "聚宝盆：500 灵石 → +15%")
	GameManager.spirit_stones = 99999
	_c.near(GameManager.cultivator_damage_mult("qingyun_sword"), 1.30, EPS, "聚宝盆：封顶 +30%")
	GameManager.reset_run()
	GameManager.add_item("budong_yin")
	_c.near(GameManager.cultivator_damage_mult("qingyun_sword"), 1.0, EPS, "明王印：未站定不生效")
	GameManager.still_time = 1.0
	_c.near(GameManager.cultivator_damage_mult("qingyun_sword"), 1.30, EPS, "明王印：站定 1 秒 → +30%")
	GameManager.reset_run()
	GameManager.add_item("ranxue_fu")
	_c.near(GameManager.cultivator_damage_mult("qingyun_sword"), 1.0, EPS, "燃血符：无玩家空载安全跳过（不出 NaN）")
	# 幻影迷踪铃：闪避转暴击（get_crit_rate 兑现；在基础暴击率上看增量）
	GameManager.reset_run()
	var base_crit := GameManager.get_crit_rate()
	GameManager.add_item("huanying_ling")
	GameManager.dodge = 0.3
	_c.near(GameManager.get_crit_rate(), base_crit + 0.15, EPS, "迷踪铃：30% 闪避 → +15% 暴击率")
	# 裂魂铃：爆炸公式同源 + unique 限购 + 账本
	_c.near(BalanceCombat.kill_explode_damage(40.0, 0.0), 40.0, EPS, "裂魂铃 0 元素 = 基数")
	_c.near(BalanceCombat.kill_explode_damage(40.0, 10.0), 40.0 + 10.0 * BalanceCombat.KILL_EXPLODE_ELEM_COEF, EPS, "裂魂铃伤害随元素成长")
	GameManager.reset_run()
	_c.check(GameManager.add_item("liehun_ling"), "裂魂铃首件购入")
	_c.check(not GameManager.add_item("liehun_ling"), "裂魂铃 unique 限购一件")
	_c.near(GameManager.item_hook_sum("kill_explode"), 40.0, EPS, "裂魂铃爆炸基数入 item_hook 账本")
	GameManager.reset_run()

	# —— 蛮兵·陷阵：mods 落地 + 按圈内线敌数乘区（注意 damage_mult 不进本函数，只有钩子乘区）——
	GameManager.reset_run()
	GameManager.cultivator_id = "kuangzhan"
	GameManager._apply_cultivator()
	_c.near(GameManager.crowd_damage_per_enemy, 0.03, EPS, "蛮兵陷阵系数落地")
	_c.near(GameManager.crowd_damage_radius, 260.0, EPS, "蛮兵陷阵感知半径落地")
	GameManager.nearby_enemy_count = 5
	_c.near(GameManager.cultivator_damage_mult("qingyun_sword"), 1.0 + 5.0 * 0.03, EPS, "5 敌在圈 → +15%")
	GameManager.nearby_enemy_count = 100
	_c.near(GameManager.cultivator_damage_mult("qingyun_sword"), 1.45, EPS, "陷阵封顶 +45%")
	# —— 守财奴·财可通神：持币增伤 + 封顶 ——
	GameManager.reset_run()
	GameManager.cultivator_id = "shoucainu"
	GameManager._apply_cultivator()
	GameManager.spirit_stones = 1000
	_c.near(GameManager.cultivator_damage_mult("qingyun_sword"), 1.20, EPS, "财可通神：1000 灵石 → +20%")
	GameManager.spirit_stones = 99999
	_c.near(GameManager.cultivator_damage_mult("qingyun_sword"), 1.50, EPS, "财可通神封顶 +50%")
	# 对照：剑痴两钩子全关（数据门控，非 id 门控）
	GameManager.reset_run()
	GameManager.cultivator_id = "jianchi"
	GameManager._apply_cultivator()
	GameManager.nearby_enemy_count = 10
	GameManager.spirit_stones = 1000
	_c.near(GameManager.cultivator_damage_mult("qingyun_sword"), 1.35, EPS, "剑痴无陷阵/财可通神（仍只有剑系 +35%）")
	GameManager.reset_run()

	# ==================== 2026-10-12 深度联动与站定流法宝（14 件）机制测试 ====================
	# 1. 站定/入定流
	_c.check(not GameManager.has_still_mechanic(), "开局无站定流法宝")
	GameManager.add_item("ruding_xiang")
	_c.check(GameManager.has_still_mechanic(), "购入入定香后激活站定判定")
	GameManager.still_time = 0.0
	_c.near(GameManager.get_effective_dodge(), 0.0, EPS, "移动中入定香无闪避")
	_c.near(GameManager.get_effective_armor(), 0.0, EPS, "移动中入定香无护甲")
	GameManager.still_time = 0.5
	_c.near(GameManager.get_effective_dodge(), 0.25, EPS, "站定时入定香闪避 +25%")
	_c.near(GameManager.get_effective_armor(), 3.0, EPS, "站定时入定香护甲 +3")

	GameManager.add_item("xuanwu_fashan")
	_c.near(GameManager.get_effective_thorns(), 0.6, EPS, "站定时玄武法坛反伤 +60%")
	var base_kb := GameManager.knockback_force(100.0)
	GameManager.still_time = 0.0
	_c.near(GameManager.knockback_force(100.0), 100.0, EPS, "移动中击退力为基准")
	GameManager.still_time = 1.0
	_c.near(GameManager.knockback_force(100.0), 180.0, EPS, "站定时玄武法坛击退力 +80%")

	GameManager.add_item("jingang_shenxiang")
	GameManager.still_time = 0.0
	_c.near(GameManager.get_effective_attack_speed_mult(), 1.0, EPS, "移动中金刚神像不缩短攻击间隔")
	_c.near(GameManager.move_speed_mult, 0.92, EPS, "金刚神像常驻移速 -8%")
	GameManager.still_time = 0.5
	_c.near(GameManager.get_effective_attack_speed_mult(), 0.70, EPS, "站定时金刚神像攻击间隔缩短 30% (1.0 → 0.70)")
	GameManager.attack_speed_mult = 0.35
	_c.near(GameManager.get_effective_attack_speed_mult(), GameManager.ATTACK_SPEED_FLOOR, EPS, "金刚神像站定攻速不跌破 ATTACK_SPEED_FLOOR 地板")
	GameManager.attack_speed_mult = 1.0

	GameManager.add_item("panshi_yin")
	GameManager.still_time = 1.0
	_c.near(CultivatorSystem.damage_mult(GameManager, "qingyun_sword"), 1.45, EPS, "磐石印站定 1 秒后全伤害 +45%")
	GameManager.reset_run()

	# 2. 角色联动：三昧归真少武器增伤
	GameManager.add_item("sanmei_guizhen")
	# 0 把上阵武器（空载）视为少 4 把，全伤害 +60%
	_c.near(CultivatorSystem.damage_mult(GameManager, "qingyun_sword"), 1.60, EPS, "三昧归真 0 武器 → +60%")
	GameManager.reset_run()

	# 3. 随行神通冷却缩减：凝神符
	var gale_base_cd := float(SkillData.final_stats("gale", "")["cooldown"])
	_c.near(gale_base_cd, 9.0, EPS, "加速基准冷却 9.0s")
	GameManager.add_item("ningshen_fu")
	var gale_mod_cd := float(SkillData.final_stats("gale", "")["cooldown"])
	_c.near(gale_mod_cd, 8.1, EPS, "凝神符：加速冷却缩减 10% (9.0 → 8.1s)")
	GameManager.reset_run()

	# 4. 波末永久成长：突破古玉
	_c.check(GameManager.add_item("tupo_guyu"), "突破古玉首件购入")
	_c.check(not GameManager.add_item("tupo_guyu"), "突破古玉 unique 限购一件")
	var prev_regen := GameManager.hp_regen
	var prev_ls := GameManager.lifesteal
	GameManager.apply_harvest()
	_c.near(GameManager.hp_regen, prev_regen + 0.5, EPS, "突破古玉波末 +0.5 回复")
	_c.near(GameManager.lifesteal, prev_ls + 0.01, EPS, "突破古玉波末 +1% 吸血")
	GameManager.reset_run()

	# 5. 武器持有分布统计与卡面展示文案
	_test_weapon_owned_summary()

func _test_weapon_owned_summary() -> void:
	GameManager.reset_run()
	_c.check(GameManager.get_weapon_owned_summary("changjian") == "", "空载时无拥有文案")
	_c.check(GameManager.get_weapon_star_distribution("changjian").is_empty(), "空载时分布字典为空")

	# 模拟背包持有 2把1星、1把2星
	GameManager.stash.append({"id": "changjian", "star": 1})
	GameManager.stash.append({"id": "changjian", "star": 1})
	GameManager.stash.append({"id": "changjian", "star": 2})
	var dist := GameManager.get_weapon_star_distribution("changjian")
	_c.check(int(dist.get(1, 0)) == 2 and int(dist.get(2, 0)) == 1, "统计2把1星1把2星")
	_c.check(GameManager.get_weapon_owned_summary("changjian") == "★1×2  ★2×1", "持有摘要格式化为 ★1×2  ★2×1")
	GameManager.reset_run()
