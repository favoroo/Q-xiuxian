class_name SynergySystem
extends RefCounted

## 流派羁绊阶梯计算与主标签保底子系统
## 从 GameManager 抽离，负责统计上阵法器标签、重算各流派阶梯加成、差值更新御灵气血及商店主标签保底。

## 上阵法器（含灵蝶）的 tag 计数——构筑方向判定的依据
static func tag_counts(gm: Node) -> Dictionary:
	var counts: Dictionary = {}
	if gm.player != null and gm.player.has_method("get_equipped_weapons_data"):
		for w in gm.player.get_equipped_weapons_data():
			for t in WeaponData.tags_of(w.get("id", "")):
				counts[t] = int(counts.get(t, 0)) + 1
	for s in gm.drones:
		for t in WeaponData.tags_of(WeaponInventory.drone_id(s)):
			counts[t] = int(counts.get(t, 0)) + 1
	return counts

## 主流派：当前持有数最多且 ≥2 件的 tag
static func main_tag(gm: Node) -> String:
	var counts := tag_counts(gm)
	var best_tag := ""
	var best_n := 1
	for t in counts.keys():
		if int(counts[t]) > best_n:
			best_n = int(counts[t])
			best_tag = t
	return best_tag

## 按上阵法器（含灵蝶）重算羁绊加成
static func recalc_synergies(gm: Node) -> void:
	var counts := tag_counts(gm)
	gm.active_synergies.clear()
	gm.bonus_pierce = 0
	gm.synergy_damage_mult = 1.0
	gm.synergy_range_mult = 1.0
	gm.synergy_haste_mult = 1.0
	gm.synergy_crit_rate = 0.0
	gm.synergy_crit_mult = 0.0
	gm.synergy_hp_regen = 0.0
	gm.synergy_lifesteal = 0.0
	gm.synergy_move_speed_mult = 0.0
	gm.synergy_burn_mult = 1.0
	gm.synergy_armor = 0.0
	gm.synergy_knockback_mult = 1.0
	var hp_bonus: float = 0.0
	for tag in counts.keys():
		var info: Dictionary = WeaponData.SYNERGIES.get(tag, {})
		if info.is_empty():
			continue
		var n := int(counts[tag])
		var shift: int = gm.spirit_threshold_adj if tag == "spirit" else 0
		var syn_level := GameBalance.synergy_level(n, info.get("thresholds", []), shift)
		gm.active_synergies[tag] = {"count": n, "level": syn_level}
		if syn_level == 0:
			continue
		var v = info["values"][syn_level - 1]
		match tag:
			"sword":
				gm.synergy_range_mult += float(v)
			"talisman":
				gm.bonus_pierce += int(v)
			"thunder":
				gm.synergy_haste_mult *= float(v)
			"spirit":
				hp_bonus += float(v)
			"wide":
				gm.synergy_damage_mult += float(v)
			"metal":
				gm.synergy_crit_rate += float(v)
				var cm_list: Array = [0.20, 0.40, 0.75]
				gm.synergy_crit_mult += float(cm_list[syn_level - 1])
			"wood":
				gm.synergy_hp_regen += float(v)
				var ls_list: Array = [0.02, 0.04, 0.07]
				gm.synergy_lifesteal += float(ls_list[syn_level - 1])
			"water":
				gm.synergy_haste_mult *= float(v)
				var spd_list: Array = [0.08, 0.16, 0.25]
				gm.synergy_move_speed_mult += float(spd_list[syn_level - 1])
			"fire":
				gm.synergy_damage_mult += float(v)
				var burn_list: Array = [0.30, 0.60, 1.00]
				gm.synergy_burn_mult += float(burn_list[syn_level - 1])
			"earth":
				gm.synergy_armor += float(v)
				var kb_list: Array = [0.25, 0.50, 0.80]
				gm.synergy_knockback_mult += float(kb_list[syn_level - 1])
	gm.synergy_max_hp_bonus = hp_bonus
	apply_synergy_hp(gm, hp_bonus)

## 御灵羁绊直接增减气血上限（差值法，避免叠加误差）
static func apply_synergy_hp(gm: Node, new_bonus: float) -> void:
	var delta: float = new_bonus - gm._applied_hp_bonus
	gm._applied_hp_bonus = new_bonus
	if gm.player != null and is_instance_valid(gm.player) and delta != 0.0:
		gm.player.max_health += delta
		gm.player.current_health = clampf(gm.player.current_health, 0.0, gm.player.max_health)
		gm.player_hp_changed.emit(gm.player.current_health, gm.player.max_health)

## 保底：连续 2 波货架没出现主流派法器时，第 3 波强制塞入一件
static func apply_main_tag_pity(gm: Node, wave: int) -> void:
	var main := main_tag(gm)
	if main == "":
		gm._no_main_tag_waves = 0
		return
	var has_main := false
	for offer in gm.shop_offers:
		if offer.get("kind") == "weapon" and main in WeaponData.tags_of(offer.get("id", "")):
			has_main = true
			break
	if has_main:
		gm._no_main_tag_waves = 0
		return
	gm._no_main_tag_waves += 1
	if gm._no_main_tag_waves < GameBalance.MAIN_TAG_PITY_WAVES:
		return
	var candidates: Array = []
	for w_id in WeaponData.SHOP_POOL:
		if main in WeaponData.tags_of(w_id):
			candidates.append(w_id)
	if candidates.is_empty():
		return
	for i in range(gm.shop_offers.size()):
		var offer: Dictionary = gm.shop_offers[i]
		if offer.get("locked", false) or offer.get("sold", false):
			continue
		if offer.get("kind") != "weapon":
			continue
		var w_id: String = String(gm.rng_pick(candidates))
		var base := int(WeaponData.get_def(w_id).get("price", 20))
		gm.shop_offers[i] = {
			"kind": "weapon", "id": w_id,
			"price": GameBalance.weapon_price(base, wave, gm.shop_price_mult),
			"sold": false, "locked": false,
		}
		break
	gm._no_main_tag_waves = 0
