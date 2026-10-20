extends Node

## 推荐系统判据（「荐」标打分）：
##   1. simulate_stats 与 StatSystem 落地语义同源：暴击/闪避到帽、攻速乘算带地板、五行真解分发
##   2. 修士契合程序化推导：正收益 mods 键 → apply 键偏好；法器 tag 专精与非灵蝶/非机关代偿
##      （扣分与契合都必须写出一句人话来源，不许只给结论）
##   3. 构建边际收益量化：暴击临上限收益归零、近战加成对剑客可打分、经济类按剩余波数折价
##   4. 法器候选：三合一升星、槽位满入背包、羁绊临门
##   5. 回气丹：缺血才值钱，满血零分
##   6. mark_offers 动态 1~3 颗：相对阈值、上限 3、全员拉胯不硬塞、幂等清旧标
##   7. 集成：RecommendSystem.build_ctx 对真实 GM 出形状正确的 ctx；alloc/shop 打标后字段齐全
## 运行: godot --headless --path . res://tests/RecommendCheck.tscn
## 退出码 0 且末行 RECOMMEND_RESULT: ALL PASS

var _c := TestCheck.new()

func _ready() -> void:
	call_deferred("_run")

# ---------------- 手工 ctx（契约见 BalanceRecommend 头注；隔离真实数据变动） ----------------

func _base_ctx() -> Dictionary:
	return {
		"stats": {
			"armor": 0.0, "max_hp": 120.0, "current_hp": 120.0, "hp_regen": 0.0,
			"lifesteal": 0.0, "crit_rate": 0.05, "crit_mult": 1.5, "attack_speed_mult": 1.0,
			"move_speed_mult": 1.0, "weapon_damage_mult": 1.0, "attack_range_mult": 1.0,
			"melee_damage": 0.0, "ranged_damage": 0.0, "elemental_damage": 0.0,
			"engineering_damage": 0.0, "harvest": 0.0,
			"dodge": 0.0, "luck": 0.0, "xp_gain_mult": 1.0, "thorns": 0.0,
		},
		"element_damage": {},
		"weapons": [{"id": "qingyun_sword", "star": 1}],
		"tag_counts": {"sword": 1},
		"cultivator": {},
		"cult_mults": {"qingyun_sword": 1.0, "huoyan_fu": 1.0, "lingdie": 1.0},
		"slots_used": 1, "slots_max": 6,
		"copies1": {},
		"stones": 100,
		"wave": 2, "victory_wave": 20,
		"crit_cap": 0.75, "dodge_cap": 0.6, "aspd_floor": 0.3,
		"contraption_mult": 1.0,
	}

## 合成道统（不读真实 CultivatorData，防数据侧改动晃到判据语义）
func _fake_cultivator(mods: Dictionary, allowed: Array = []) -> Dictionary:
	return {"name": "测试道统", "mods": mods, "allowed_tags": allowed}

func _run() -> void:
	_check_simulate()
	_check_fit()
	_check_fit_reason_is_explained()
	_check_build_gain()
	_check_weapon_offer()
	_check_potion()
	_check_mark_rules()
	_check_integration()
	if _c.report("RECOMMEND_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

# ---------------- 1. 属性模拟语义 ----------------

func _check_simulate() -> void:
	var st := {"crit_rate": 0.74, "attack_speed_mult": 1.0, "dodge": 0.55, "max_hp": 120.0}
	var el := {}
	BalanceRecommend.simulate_stats(st, el, {"crit_rate": 0.05, "attack_speed_mult_mul": 0.8},
			0.75, 0.6, 0.3)
	_c.near(float(st["crit_rate"]), 0.75, 0.0001, "暴击模拟到帽（0.74+0.05 → 0.75，不超 CRIT_RATE_CAP）")
	_c.near(float(st["attack_speed_mult"]), 0.8, 0.0001, "攻速乘区模拟 ×0.8")
	# 乘算地板
	var st2 := {"attack_speed_mult": 0.5}
	BalanceRecommend.simulate_stats(st2, {}, {"attack_speed_mult_mul": 0.1}, 0.75, 0.6, 0.3)
	_c.near(float(st2["attack_speed_mult"]), 0.3, 0.0001, "攻速模拟不破地板（0.5×0.1 → 0.3）")
	# 闪避到帽（含角色加成后的 cap 由 ctx 传入）
	var st3 := {"dodge": 0.55}
	BalanceRecommend.simulate_stats(st3, {}, {"dodge": 0.1}, 0.75, 0.6, 0.3)
	_c.near(float(st3["dodge"]), 0.6, 0.0001, "闪避模拟到帽（0.55+0.1 → 0.6）")
	# 五行真解分发
	var el4 := {}
	BalanceRecommend.simulate_stats({}, el4, {"element_damage_all": 0.12}, 0.75, 0.6, 0.3)
	var all_ok := true
	for e in WeaponData.ELEMENTS:
		all_ok = all_ok and absf(float(el4.get(e, 0.0)) - 0.12) < 0.0001
	_c.check(all_ok, "五行真解模拟分发到全部五元素（各 +0.12）")

# ---------------- 2. 修士契合 ----------------

func _check_fit() -> void:
	# 合成剑客：暴击向偏好（mods crit_rate>0，无 allowed_tags 隔离数据侧）
	var jian := _fake_cultivator({"crit_rate": 0.15})
	var ctx := _base_ctx()
	ctx["cultivator"] = jian
	var r_crit := BalanceRecommend.score_apply({"crit_rate": 0.08}, ctx)
	var r_harvest := BalanceRecommend.score_apply({"harvest": 5.0}, ctx)
	_c.near(float(r_crit["a"]), 1.0, 0.001, "合成剑客对暴击类契合满分")
	_c.near(float(r_harvest["a"]), 0.35, 0.001, "合成剑客对经济类契合落到下限")
	# 契合的统治力在灵韵衰减后的后期验证：前期灵韵复利（5×18 波）本来就真强，模型不偏袒
	var ctx_late := _base_ctx()
	ctx_late["wave"] = 19
	var r_harvest_late := BalanceRecommend.score_apply({"harvest": 5.0}, ctx_late)
	_c.check(float(r_crit["score"]) > float(r_harvest_late["score"]),
			"后期同权重下暴击类总分高于经济类（%.2f > %.2f）" % [float(r_crit["score"]), float(r_harvest_late["score"])])
	# 合成守卫：hp_mult>1 → 气血上限是偏好
	var guard := _fake_cultivator({"hp_mult": 1.8})
	var ctx_g := _base_ctx()
	ctx_g["cultivator"] = guard
	_c.near(float(BalanceRecommend.score_apply({"max_hp": 15.0}, ctx_g)["a"]), 1.0, 0.001,
			"合成守卫对气血上限契合满分")
	# 真实数据抽查（数据侧改了这里会红）
	var jp := BalanceRecommend.preferred_keys(CultivatorData.get_def("jianchi").get("mods", {}),
			CultivatorData.get_def("jianchi").get("allowed_tags", []))
	_c.check(jp.has("crit_rate"), "真实剑客偏好表含暴击率")
	var sp := BalanceRecommend.preferred_keys(CultivatorData.get_def("shiyue").get("mods", {}),
			CultivatorData.get_def("shiyue").get("allowed_tags", []))
	_c.check(sp.has("max_hp"), "真实守卫偏好表含气血上限")

## 「契合」不许只喊结论：每个偏好键都得带得出「为什么」，且这条要随理由一起出现在详情卡里。
## 反例就是 2026-10-11 那张截图——剑客买护甲被写成「契合【剑客】护甲取向」，
## 而角色卡上剑客只有「剑系伤害 +35%」「初始暴击率 +15%」，玩家对着卡找不到这条。
func _check_fit_reason_is_explained() -> void:
	# ① 流派推导（allowed_tags）：真实剑客 + 真实「护甲提升」，走生产同款入口
	var ctx := _base_ctx()
	ctx["cultivator"] = CultivatorData.get_def("jianchi")
	var r_armor := BalanceRecommend.score_apply(
			UpgradeData.get_upgrade_def("armor_up").get("apply", {}), ctx)
	var fit := ""
	var why := ""
	for r in r_armor["reasons"]:
		var s := String(r)
		if s.contains("取向"):
			fit = s
		elif s.begins_with("因为"):
			why = s
	_c.check(not fit.is_empty(), "真实剑客买护甲仍标「契合取向」")
	_c.check(why.contains("剑系") and why.contains("护甲"),
			"契合理由跟着一句「因为…」点明流派推导（实得「%s」）" % why)
	# ② 自身属性推导（mods）：话术里的幅度必须现读角色表，不许与角色卡两套数
	var ctx2 := _base_ctx()
	ctx2["cultivator"] = _fake_cultivator({"crit_rate": 0.15})
	var r_crit := BalanceRecommend.score_apply({"crit_rate": 0.08}, ctx2)
	var why2 := ""
	for r in r_crit["reasons"]:
		if String(r).begins_with("因为"):
			why2 = String(r)
	_c.check(why2.contains("15%"), "自身来源那句带真实幅度（实得「%s」）" % why2)
	# ③ 给不出人话来源时不许硬编一句假话（armor=0 只由反震带出的护甲偏好）
	var ctx3 := _base_ctx()
	ctx3["cultivator"] = _fake_cultivator({"thorns": 1.0})
	var r3 := BalanceRecommend.score_apply({"armor": 2.0}, ctx3)
	var fit3 := false
	for r in r3["reasons"]:
		var s3 := String(r)
		if s3.contains("取向"):
			fit3 = true  # 先坐实「这句确实该出来源」，否则下面那条否定断言是空转
		_c.check(not s3.begins_with("因为"), "无来源时不编「因为…」句（实得「%s」）" % s3)
	_c.check(fit3, "反震带出的护甲偏好仍标「契合取向」")

# ---------------- 3. 构建边际收益 ----------------

func _check_build_gain() -> void:
	# 暴击临上限收益归零：同一 apply，74% 暴击时 b 远小于 5% 暴击时
	var ctx_hi := _base_ctx()
	ctx_hi["stats"]["crit_rate"] = 0.74
	var b_hi := float(BalanceRecommend.score_apply({"crit_rate": 0.04}, ctx_hi)["b"])
	var ctx_lo := _base_ctx()
	var b_lo := float(BalanceRecommend.score_apply({"crit_rate": 0.04}, ctx_lo)["b"])
	_c.check(b_hi < b_lo * 0.4, "暴击临上限的边际收益大幅衰减（hi %.3f < lo %.3f×0.4）" % [b_hi, b_lo])
	# 近战加成对持剑 build 可量化（长剑 stat_scalings 吃 melee_damage）
	var r_melee := BalanceRecommend.score_apply({"melee_damage": 5.0}, _base_ctx())
	_c.check(float(r_melee["b"]) > 0.2, "近战伤害加成对持剑 build 伤害轴显著（b=%.2f）" % float(r_melee["b"]))
	var reasons: Array = r_melee["reasons"]
	var has_dmg_reason := false
	for r in reasons:
		if String(r).contains("总伤"):
			has_dmg_reason = true
	_c.check(has_dmg_reason, "伤害轴理由提到总伤")
	# 经济类前期比后期值钱（灵韵复利，剩余波数折价）
	var ctx_early := _base_ctx()
	var ctx_late := _base_ctx()
	ctx_late["wave"] = 19
	var s_early := float(BalanceRecommend.score_apply({"harvest": 5.0}, ctx_early)["score"])
	var s_late := float(BalanceRecommend.score_apply({"harvest": 5.0}, ctx_late)["score"])
	_c.check(s_early > s_late + 0.2, "灵韵类第 2 波显著优于第 19 波（%.2f > %.2f）" % [s_early, s_late])

# ---------------- 4. 法器候选 ----------------

func _check_weapon_offer() -> void:
	# 剑客 tag 专精：剑系法器契合显著高于非剑系
	var jian := _fake_cultivator({"crit_rate": 0.15, "tag_damage": {"sword": 0.35}}, ["sword"])
	var ctx := _base_ctx()
	ctx["cultivator"] = jian
	var r_sword := BalanceRecommend.score_weapon("qingyun_sword", ctx)
	var r_fire := BalanceRecommend.score_weapon("huoyan_fu", ctx)
	_c.check(float(r_sword["a"]) >= 0.9, "剑客对剑系法器契合 ≥0.9")
	_c.check(float(r_fire["a"]) <= 0.5, "剑客对火符契合不超中性")
	_c.check(float(r_sword["score"]) > float(r_fire["score"]), "剑系法器推荐分高于非剑系")
	# 驯兽师代偿：非灵蝶惩罚 → 环绕法器契合高于近战
	var fu := _fake_cultivator({"non_drone_damage": -0.3})
	var ctx_f := _base_ctx()
	ctx_f["cultivator"] = fu
	var r_melee := BalanceRecommend.score_weapon("qingyun_sword", ctx_f)
	var a_drone := float(BalanceRecommend.score_weapon("lingdie", ctx_f)["a"])
	var a_melee := float(r_melee["a"])
	_c.check(a_drone > a_melee, "驯兽师对环绕法器契合高于近战（%.2f > %.2f）" % [a_drone, a_melee])
	# 这一刀扣在分数上就得写在理由里，否则玩家只看到一颗不亮的「荐」
	var pen := ""
	for r in r_melee["reasons"]:
		if String(r).contains("非召唤类"):
			pen = String(r)
	_c.check(pen.contains("-30%"), "非召唤惩罚那句带真实幅度（实得「%s」）" % pen)
	# 三合一：手里 2 件同名 1 星 → 协同满分 + 提「三合一」
	var ctx_m := _base_ctx()
	ctx_m["copies1"] = {"qingyun_sword": 2}
	var r_merge := BalanceRecommend.score_weapon("qingyun_sword", ctx_m)
	_c.near(float(r_merge["c"]), 1.0, 0.001, "可三合一的法器协同满分")
	var merged := false
	for r in r_merge["reasons"]:
		if String(r).contains("三合一"):
			merged = true
	_c.check(merged, "三合一理由出现")
	# 槽位满：入背包分支给「可替换」评估而不是零分
	var ctx_full := _base_ctx()
	ctx_full["slots_used"] = 6
	ctx_full["slots_max"] = 6
	var r_full := BalanceRecommend.score_weapon("huoyan_fu", ctx_full)
	_c.check(float(r_full["b"]) > 0.0 and not r_full["reasons"].is_empty(), "槽位满时入背包候选仍有评估与理由")
	# 羁绊临门：手里 1 件剑系，再买 1 件凑 2 档
	var ctx_syn := _base_ctx()
	ctx_syn["tag_counts"] = {"sword": 1}
	var r_syn := BalanceRecommend.score_weapon("gengjin_feijian", ctx_syn)
	_c.check(float(r_syn["c"]) >= 0.65, "凑齐剑系 2 档的协同 ≥0.65（实得 %.2f）" % float(r_syn["c"]))

# ---------------- 5. 回气丹 ----------------

func _check_potion() -> void:
	var ctx_low := _base_ctx()
	ctx_low["stats"]["current_hp"] = 30.0
	var offer := {"kind": "potion", "id": WeaponData.POTION_ID, "price": 10}
	var r_low := BalanceRecommend.score_potion(offer, ctx_low)
	_c.check(float(r_low["score"]) >= 0.4, "缺血 25%% 时回气丹高分（%.2f）" % float(r_low["score"]))
	var ctx_full := _base_ctx()
	var r_full := BalanceRecommend.score_potion(offer, ctx_full)
	_c.check(float(r_full["score"]) <= 0.001, "满血时回气丹零分（不值得推荐）")

# ---------------- 6. 标记规则（动态 1~3 颗） ----------------

func _check_mark_rules() -> void:
	# 相对阈值：0.76 ≥ 0.8×0.9 → 标 2 个
	var offers := [{"n": 1}, {"n": 2}, {"n": 3}, {"n": 4}, {"n": 5}]
	var scored := [
		{"index": 0, "score": 0.80, "reasons": ["甲"]},
		{"index": 1, "score": 0.76, "reasons": ["乙"]},
		{"index": 2, "score": 0.50, "reasons": []},
		{"index": 3, "score": 0.30, "reasons": []},
		{"index": 4, "score": 0.10, "reasons": []},
	]
	BalanceRecommend.mark_offers(offers, scored)
	_c.check(bool(offers[0]["recommended"]) and bool(offers[1]["recommended"]), "阈值内两条都标「荐」")
	_c.check(not bool(offers[2]["recommended"]) and not bool(offers[4]["recommended"]), "阈值外不标")
	_c.check(not String(offers[0]["recommend_reasons"][0]).is_empty(), "标上的候选带理由")
	# 上限 3：五条全在阈值内也只标 3
	var offers2 := [{"n": 1}, {"n": 2}, {"n": 3}, {"n": 4}, {"n": 5}]
	BalanceRecommend.mark_offers(offers2, [
		{"index": 0, "score": 1.0, "reasons": []},
		{"index": 1, "score": 0.95, "reasons": []},
		{"index": 2, "score": 0.92, "reasons": []},
		{"index": 3, "score": 0.91, "reasons": []},
		{"index": 4, "score": 0.90, "reasons": []},
	])
	var n_marked := 0
	for o in offers2:
		if bool(o["recommended"]):
			n_marked += 1
	_c.equals(n_marked, 3, "一屏「荐」标至多 3 颗")
	_c.check(not String(offers2[0]["recommend_reasons"][0]).is_empty(), "无理由时兜底文案补位")
	# 全员拉胯：最高分低于下限 → 一颗都不硬塞
	var offers3 := [{"n": 1}, {"n": 2}]
	BalanceRecommend.mark_offers(offers3, [
		{"index": 0, "score": 0.11, "reasons": []},
		{"index": 1, "score": 0.05, "reasons": []},
	])
	_c.check(not bool(offers3[0]["recommended"]) and not bool(offers3[1]["recommended"]),
			"全员低分不硬塞「荐」")
	# 幂等：旧标被清掉（锁定保留的货架格重刷场景）
	BalanceRecommend.mark_offers(offers3, [])
	_c.check(not bool(offers3[0]["recommended"]), "重复调用先清旧标（幂等）")

# ---------------- 7. 集成（真实 GM autoload） ----------------

func _check_integration() -> void:
	var gm := GameManager
	gm.cultivator_id = "jianchi"
	gm.drones = [{"id": "lingdie", "star": 1}]
	gm.spirit_stones = 50
	gm.wave_number = 3
	# build_ctx 形状
	var ctx := RecommendSystem.build_ctx(gm)
	_c.check(ctx.has("stats") and ctx.has("weapons") and ctx.has("tag_counts"), "build_ctx 产出契约内字段")
	_c.check((ctx["weapons"] as Array).size() == 1, "无 player 节点时上阵清单取自 drones")
	_c.near(float(ctx["crit_cap"]), 0.75, 0.0001, "ctx 暴击帽与 GM 常量同源")
	# alloc 打标：字段齐全、至少一颗「荐」
	gm.alloc_offers.append(UpgradeData.get_upgrade_def("crit_up"))
	gm.alloc_offers.append(UpgradeData.get_upgrade_def("armor_up"))
	RecommendSystem.mark_alloc_offers(gm)
	var n_rec := 0
	var all_keyed := true
	for off in gm.alloc_offers:
		all_keyed = all_keyed and off.has("recommended") and off.has("recommend_score") \
				and off.has("recommend_reasons")
		if bool(off.get("recommended", false)):
			n_rec += 1
			_c.check(not (off["recommend_reasons"] as Array).is_empty(), "标上的加点候选理由非空")
			break
	_c.check(all_keyed, "alloc 打标后三个推荐字段齐全")
	_c.check(n_rec >= 1, "alloc 至少亮一颗「荐」")
	# shop 打标：满血回气丹不亮标，法器/法宝正常参评
	gm.shop_offers = [
		{"kind": "potion", "id": WeaponData.POTION_ID, "price": 10, "sold": false, "locked": false},
		{"kind": "weapon", "id": "qingyun_sword", "price": 30, "sold": false, "locked": false},
		{"kind": "item", "id": "mibao_luopan", "price": 20, "sold": false, "locked": false},
	]
	RecommendSystem.mark_shop_offers(gm)
	var potion_off: Dictionary = gm.shop_offers[0]
	var weapon_off: Dictionary = gm.shop_offers[1]
	_c.check(not bool(potion_off.get("recommended", true)), "满血时货架回气丹不亮「荐」")
	_c.check(bool(weapon_off.get("recommended", false)), "剑客货架亮剑系法器「荐」")
	_c.check(gm.shop_offers[2].has("recommend_score"), "法宝候选也进了打分")
	# 清场：不留状态给后续测试/真机
	gm.alloc_offers.clear()
	gm.shop_offers = []
	gm.cultivator_id = ""
	gm.drones = []
	GameManager.reset_run()
	_c.equals(GameManager.cultivator_id, "", "收尾 reset_run 清空角色")
