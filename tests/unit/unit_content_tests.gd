class_name UnitContentTests
extends UnitTestsBase

## 单测模块：五行武器矩阵 / 批一新属性 / 法宝系统 / 修士流派 / 机关炮台与新修士（从 tests/unit_runner.gd 拆出，2026-10-11）。
## 调用顺序与判据契约（UNIT_RESULT: ALL PASS / 退出码）由 UnitRunner 统一保证；
## _c 与 EPS 继承自 UnitTestsBase，函数体与拆分前逐字一致。
func _test_five_elements_system() -> void:
	# 1. 武器表完整性校验：38 把法器（含机关支路 3 把）且图标资源齐全
	_c.equals(WeaponData.DEFS.size(), 38, "全武器库扩充至 38 把法器")
	_c.equals(WeaponData.SHOP_POOL.size(), 38, "商店池覆盖全部 38 把法器")
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
	_c.check(missing_icons.is_empty(), "38 把法器的图标文件全部就位（缺: %s）" % str(missing_icons))
	_c.check(missing_dual_tags.is_empty(), "每把法器均具备「器类+五行」双标签（缺: %s）" % str(missing_dual_tags))
	_c.check(no_bullet.is_empty(), "每把弹丸法器都配了自己的弹丸外观（缺: %s）" % str(no_bullet))
	_c.check(bad_bullet.is_empty(), "弹丸外观文件全部存在（缺文件: %s）" % str(bad_bullet))
	# 扩容后各系把数：金11/木7/水6/火7/土7（含机关 3 把）
	var elem_expect := {"metal": 11, "wood": 7, "water": 6, "fire": 7, "earth": 7}
	for e_key in elem_counts.keys():
		_c.equals(int(elem_counts[e_key]), int(elem_expect[e_key]), "五行【%s】包含 %d 把法器" % [e_key, int(elem_expect[e_key])])

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

	# 档位权重：第 1 波只有凡品，传说第 14 波才解锁；福缘抬高高档
	var w1: Array = GameBalance.item_tier_weights(0.0, 1)
	_c.check(float(w1[0]) > 0.0 and float(w1[1]) == 0.0 and float(w1[3]) == 0.0, "第 1 波只出凡品法宝")
	var w15: Array = GameBalance.item_tier_weights(0.0, 15)
	_c.check(float(w15[3]) > 0.0, "第 15 波传说法宝解锁")
	var w_luck: Array = GameBalance.item_tier_weights(40.0, 15)
	_c.check(float(w_luck[3]) > float(w15[3]), "福缘抬高传说权重")

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
	_c.equals(GameBalance.item_price(45, 9, 1.0), 45 + 8 * 2, "仙品法宝第 9 波 +16")
	_c.equals(GameBalance.item_price(45, 9, 0.8), int((45.0 + 16.0) * 0.8), "法宝价吃商店折扣")

	# 残丹化灵：回不上的那截气血折灵石（汇率与藏宝匣金灵石那一路同档，单颗封顶）
	_c.equals(GameBalance.heal_overflow_stones(0.0), 0, "没溢出就不给钱")
	_c.equals(GameBalance.heal_overflow_stones(-5.0), 0, "负数按 0 收")
	_c.equals(GameBalance.heal_overflow_stones(18.0), 14, "满口 18 点溢出 → 14 灵石（≈3 颗金灵石）")
	_c.equals(GameBalance.heal_overflow_stones(13.0), 10, "缺血 5 吃 18：溢出 13 → 10 灵石")
	_c.equals(GameBalance.heal_overflow_stones(45.0), 15, "高气血上限的 45 点溢出仍封顶 15")
	_c.check(GameBalance.HEAL_OVERFLOW_STONE_CAP <= 15, "折灵石单颗封顶不超过 15（不滚成巨款）")

func _test_cultivator_system() -> void:
	# 数据表完整性：15 名修士，每名都有 名称/称号/图标/天赋/代价/独立形象 字段
	_c.equals(CultivatorData.all_ids().size(), 15, "修士扩充至 15 名")
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

	# 魅影（Ghost 原型）：闪避上限抬到 90%，锁死罡气护体
	GameManager.reset_run()
	GameManager.cultivator_id = "meiying"
	GameManager._apply_cultivator()
	_c.near(GameManager.dodge, 0.30, EPS, "魅影初始闪避 +30%")
	GameManager.dodge = 1.0
	_c.near(GameManager.get_effective_dodge(), 0.9, EPS, "魅影闪避上限 90%（其余人 60%）")
	_c.check("armor_up" in GameManager.locked_upgrades, "魅影锁死罡气护体")

	# 独臂刀圣（One Armed 原型）：上阵槽上限为 3，伤害 ×1.65、施法更快
	GameManager.reset_run()
	GameManager.cultivator_id = "dubi"
	GameManager._apply_cultivator()
	_c.equals(GameManager.max_weapon_slots(), 3, "独臂刀圣上阵槽上限为 3")
	_c.near(GameManager.weapon_damage_mult, 1.65, EPS, "独臂刀圣伤害 ×1.65")
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
	var cs := CultivatorSelect.new()
	add_child(cs)
	cs.show_select()
	_c.equals(cs._roster_grid.get_child_count(), 15, "道统选择界面下半部分两排网格展示 15 张形象小卡片")
	_c.check(cs._detail_panel.visible, "道统选择界面上半部分详解大卡片正常可见")
	cs._select_cultivator("fuzhen")
	_c.equals(cs._selected_id, "fuzhen", "点击小卡片即时切换至对应修士")
	cs.queue_free()

	GameManager.reset_run()

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

	# 3. 机关师（jiguan）：机关门槛 -1，初始召唤伤害 +3
	GameManager.cultivator_id = "jiguan"
	GameManager._apply_cultivator()
	_c.equals(GameManager.contraption_threshold_adj, 1, "机关师机关门槛下移 1")
	_c.near(GameManager.engineering_damage, 3.0, EPS, "机关师初始召唤伤害 +3")

	# 4. 灵植夫（lingzhifu）：收益 +12，全武器伤害 ×0.85
	GameManager.reset_run()
	GameManager.cultivator_id = "lingzhifu"
	GameManager._apply_cultivator()
	_c.near(GameManager.harvest, 12.0, EPS, "灵植夫初始收益 +12")
	_c.near(GameManager.weapon_damage_mult, 0.85, EPS, "灵植夫全武器伤害 ×0.85")

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

	# 7. 数据表三件御灵装备属性强化验证（射程全面扩展至 >= 170px，伤害 >= 20）
	for sid in ["lingdie", "hanquan_yulian", "hunyuan_zhong"]:
		var sdef := WeaponData.get_def(sid)
		_c.check(float(sdef.get("range", 0.0)) >= 170.0, "御灵法器 %s 射程强化至 >= 170px（当前 %.0f）" % [sid, float(sdef.get("range", 0.0))])
		_c.check(float(sdef.get("damage", 0.0)) >= 20.0, "御灵法器 %s 基础伤害 >= 20（当前 %.0f）" % [sid, float(sdef.get("damage", 0.0))])
		_c.check(float(sdef.get("knockback", 0.0)) >= 160.0, "御灵法器 %s 击退强化至 >= 160（当前 %.0f）" % [sid, float(sdef.get("knockback", 0.0))])

	# 8. 召唤羁绊工程伤害与气血双收益验证
	GameManager.reset_run()
	GameManager.drones = [1, 1]  # 2 件护蝶
	SynergySystem.recalc_synergies(GameManager)
	_c.near(GameManager.synergy_max_hp_bonus, 15.0, EPS, "2 召唤获得 +15 气血上限")
	_c.near(GameManager.synergy_engineering_damage, 2.0, EPS, "2 召唤获得 +2 召唤伤害加成")
	var stat_dict := GameManager.get_player_stat_dict()
	_c.near(float(stat_dict.get("engineering_damage", 0.0)), 2.0, EPS, "角色属性表包含召唤羁绊工程伤害")
	GameManager.reset_run()

	# 8. 多法器神识分流与同目标短窗集火韧性验证
	_c.near(GameBalance.multi_weapon_damage_mult(1), 1.0, EPS, "单把法器神识效率 100%")
	_c.near(GameBalance.multi_weapon_damage_mult(6), 1.0 / 1.6, EPS, "6 把法器单把神识分流系数 62.5%（总有效倍率 3.75x）")
	var prev_tot := 0.0
	var tot_monotonic := true
	for n_slots in range(1, 7):
		var tot := float(n_slots) * GameBalance.multi_weapon_damage_mult(n_slots)
		if tot <= prev_tot:
			tot_monotonic = false
		prev_tot = tot
	_c.check(tot_monotonic, "1~6 把法器总有效倍率严格单调递增（多戴必正收益）")
	_c.near(GameBalance.focus_fire_mult(0), 1.0, EPS, "短窗第 1 击全额 100%")
	_c.near(GameBalance.focus_fire_mult(1), 0.70, EPS, "短窗第 2 击折算 70%")
	_c.near(GameBalance.focus_fire_mult(2), 0.50, EPS, "短窗第 3 击折算 50%")
	_c.near(GameBalance.focus_fire_mult(5), 0.50, EPS, "短窗后续连击保底 50%")
