class_name RecommendSystem
extends RefCounted

## 推荐系统胶水层：从 GameManager 收集当前构筑上下文 → BalanceRecommend 纯函数打分 →
## 把 recommended / recommend_score / recommend_reasons 写回 offer 字典，UI 只读不判。
## 与 ShopSystem / AllocSession 同一惯例：class_name 静态模块，不注册 autoload。
##
## 打分口径与权重全部在 BalanceRecommend（systems 层，纯函数可单测）；
## 这里只做「GM 状态 → 值类型 ctx」的搬运，不改任何游戏状态。

## 悟道加点候选打标（roll_alloc_offers 末尾调用：开面板/翻屏/刷新三条路都汇在这里）
static func mark_alloc_offers(gm: Node) -> void:
	var offers: Array = gm.alloc_offers
	if offers.is_empty():
		return
	var ctx := build_ctx(gm)
	var scored: Array = []
	for i in range(offers.size()):
		var off: Dictionary = offers[i]
		var r: Dictionary = BalanceRecommend.score_apply(off.get("apply", {}), ctx)
		scored.append({"index": i, "score": float(r["score"]), "reasons": r["reasons"]})
	BalanceRecommend.mark_offers(offers, scored)

## 金币阁货架打标（roll_shop 末尾调用：开商店/重掷/锁定保留三条路都汇在这里）
static func mark_shop_offers(gm: Node) -> void:
	var offers: Array = gm.shop_offers
	if offers.is_empty():
		return
	var ctx := build_ctx(gm)
	# 候选武器的角色特性系数先补进 cult_mults（上阵件的在 build_ctx 里已备好）
	var mults: Dictionary = ctx["cult_mults"]
	for off in offers:
		if String(off.get("kind", "")) != "weapon" or off.get("sold", false):
			continue
		var wid := String(off.get("id", ""))
		if not mults.has(wid):
			mults[wid] = CultivatorSystem.damage_mult(gm, wid)
	var scored: Array = []
	for i in range(offers.size()):
		var off: Dictionary = offers[i]
		if off.get("sold", false):
			continue  # 已售出的格子不参与推荐
		var r: Dictionary = BalanceRecommend.score_offer(off, ctx)
		scored.append({"index": i, "score": float(r["score"]), "reasons": r["reasons"]})
	BalanceRecommend.mark_offers(offers, scored)

## 收集打分上下文（值类型快照，契约见 BalanceRecommend 头注）。
## player 不在场（单测/局外）时武器只数 drones 与背包，全链路不许崩。
static func build_ctx(gm: Node) -> Dictionary:
	var stats: Dictionary = gm.get_player_stat_dict()
	# get_player_stat_dict 不带的三个面板外读数（推荐轴要用），就地补齐
	stats["dodge"] = gm.get_effective_dodge()
	stats["luck"] = gm.luck
	stats["xp_gain_mult"] = gm.xp_gain_mult
	stats["thorns"] = gm.thorns_pct

	var weapons: Array = []
	# 同名同星件数按星分开记：货架会卖 ★1 与 ★2 两种成品，三合一各算各的轨道
	# （2026-10-25：原来只有 copies1，★2 商品的三合一判定会被错算成 ★1 的件数）。
	var copies1: Dictionary = {}
	var copies2: Dictionary = {}
	var has_player_weapons: bool = gm.player != null and is_instance_valid(gm.player) \
			and gm.player.has_method("get_equipped_weapons_data")
	if has_player_weapons:
		for w in gm.player.get_equipped_weapons_data():
			var wid := String(w.get("id", ""))
			var wstar := int(w.get("star", 1))
			weapons.append({"id": wid, "star": wstar})
			if wstar == 1:
				copies1[wid] = int(copies1.get(wid, 0)) + 1
			elif wstar == 2:
				copies2[wid] = int(copies2.get(wid, 0)) + 1
	for d in gm.drones:
		var wid := WeaponInventory.drone_id(d)
		var star := WeaponInventory.drone_star(d)
		weapons.append({"id": wid, "star": star})
		if star == 1:
			copies1[wid] = int(copies1.get(wid, 0)) + 1
		elif star == 2:
			copies2[wid] = int(copies2.get(wid, 0)) + 1
	for e in gm.stash:
		var estar := int(e.get("star", 1))
		if estar == 1:
			var wid := String(e.get("id", ""))
			copies1[wid] = int(copies1.get(wid, 0)) + 1
		elif estar == 2:
			var wid2 := String(e.get("id", ""))
			copies2[wid2] = int(copies2.get(wid2, 0)) + 1

	var cult_mults: Dictionary = {}
	for w in weapons:
		var wid := String(w["id"])
		if not cult_mults.has(wid):
			cult_mults[wid] = CultivatorSystem.damage_mult(gm, wid)

	return {
		"stats": stats,
		"element_damage": (gm.element_damage as Dictionary).duplicate(),
		"weapons": weapons,
		"tag_counts": SynergySystem.tag_counts(gm),
		"cultivator": CultivatorData.get_def(gm.cultivator_id),
		"cult_mults": cult_mults,
		"slots_used": WeaponInventory.slots_used(gm),
		"slots_max": gm.max_weapon_slots(),
		"copies1": copies1,
		"copies2": copies2,
		"stones": int(gm.spirit_stones),
		"wave": maxi(int(gm.wave_number), 1),
		"victory_wave": int(gm.VICTORY_WAVE),
		"crit_cap": float(gm.CRIT_RATE_CAP),
		"dodge_cap": float(gm.DODGE_CAP) + float(gm.dodge_cap_bonus),
		"aspd_floor": float(gm.ATTACK_SPEED_FLOOR),
		"contraption_mult": float(gm.synergy_contraption_mult),
	}
