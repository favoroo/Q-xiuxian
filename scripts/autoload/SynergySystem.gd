class_name SynergySystem
extends RefCounted

## 流派羁绊阶梯计算与主标签保底子系统
## 从 GameManager 抽离，负责统计上阵武器标签、重算各流派阶梯加成、差值更新御灵生命及商店主标签保底。
##
## 结算口径（2026-10-11 收拢）：本文件不再持有任何羁绊幅度字面量。
## 每档加多少、写进 GameManager 哪个属性、乘还是加，全部读 WeaponData.SYNERGIES[tag].effects；
## 局内阶梯文案与图鉴长句由 SynergyUI 从同一份 effects 生成，
## UnitRunner 再走本文件的 apply_counts 把两者对账 —— 数值改一处，文案跟着变，改文案不改数值会报红。

## 上阵武器（含灵蝶）的 tag 计数——构筑方向判定的依据
static func tag_counts(gm: Node) -> Dictionary:
	var counts: Dictionary = {}
	if gm.player != null and is_instance_valid(gm.player) and gm.player.has_method("get_equipped_weapons_data"):
		for w in gm.player.get_equipped_weapons_data():
			for t in WeaponData.tags_of(w.get("id", "")):
				counts[t] = int(counts.get(t, 0)) + 1
	for s in gm.drones:
		for t in WeaponData.tags_of(WeaponInventory.drone_id(s)):
			counts[t] = int(counts.get(t, 0)) + 1
	return counts

## 角色对某流派门槛的下移量：只有召唤/机关两条道统会改，其余流派恒为 0
## 门槛折算的唯一真话在此（SynergyUI 与判据都走它，不各自比原表）
static func shift_for(tag: String) -> int:
	if tag == "spirit":
		return GameManager.spirit_threshold_adj
	if tag == "contraption":
		return GameManager.contraption_threshold_adj
	return 0

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

## 按上阵武器（含灵蝶）重算羁绊加成
static func recalc_synergies(gm: Node) -> void:
	apply_counts(gm, tag_counts(gm))

## 按「tag → 件数」结算羁绊（生产入口，判据也从这里进：不建 Player 也能钉住某一档）
## 先按 WeaponData.SYNERGY_FIELDS 全量清零再累加，漏登记的新字段会在 UnitRunner 报红
static func apply_counts(gm: Node, counts: Dictionary) -> void:
	gm.active_synergies.clear()
	for f in WeaponData.SYNERGY_FIELDS:
		gm.set(f, WeaponData.SYNERGY_BASE.get(f, 0.0))
	for tag in counts.keys():
		var info: Dictionary = WeaponData.SYNERGIES.get(tag, {})
		if info.is_empty():
			continue
		var n := int(counts[tag])
		var syn_level := GameBalance.synergy_level(n, info.get("thresholds", []), shift_for(tag))
		gm.active_synergies[tag] = {"count": n, "level": syn_level}
		if syn_level == 0:
			continue
		for eff in info.get("effects", []):
			var vals: Array = info.get(String(eff.get("list", "values")), [])
			if syn_level > vals.size():
				continue
			var field := String(eff.get("field", ""))
			if not WeaponData.SYNERGY_FIELDS.has(field):
				continue
			var v := float(vals[syn_level - 1])
			var next := float(gm.get(field)) * v if String(eff.get("op", "add")) == "mul" \
					else float(gm.get(field)) + v
			# synergy_bonus_pierce 是 int 属性，按基数类型回截，别把 float 塞进 int setter
			if typeof(WeaponData.SYNERGY_BASE.get(field, 0.0)) == TYPE_INT:
				gm.set(field, int(round(next)))
			else:
				gm.set(field, next)
	gm.bonus_pierce = gm.stat_bonus_pierce + gm.synergy_bonus_pierce
	apply_synergy_hp(gm, gm.synergy_max_hp_bonus)

## 御灵羁绊直接增减生命上限（差值法，避免叠加误差）
static func apply_synergy_hp(gm: Node, new_bonus: float) -> void:
	var delta: float = new_bonus - gm._applied_hp_bonus
	gm._applied_hp_bonus = new_bonus
	if gm.player != null and is_instance_valid(gm.player) and delta != 0.0:
		gm.player.max_health += delta
		gm.player.current_health = clampf(gm.player.current_health, 0.0, gm.player.max_health)
		gm.player_hp_changed.emit(gm.player.current_health, gm.player.max_health)

## 保底：连续 2 波货架没出现主流派武器时，第 3 波强制塞入一件
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
	# 保底候选同样受武器解锁门控（2026-10-25）：否则保底会把还没解锁的武器塞进货架，
	# 等于绕过成就体系直接发奖。池口径与商店抽卡共用 ShopSystem.unlocked_weapon_pool。
	for w_id in ShopSystem.unlocked_weapon_pool(gm):
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
