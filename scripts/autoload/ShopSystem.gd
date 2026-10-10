class_name ShopSystem
extends RefCounted

## 波间商店（灵石阁）子系统
## 从 GameManager 抽离，负责货架生成、标签亲和加权抽法器、锁定保留、购买结算与重掷。

## 生成货架：new_wave=true 时重置重掷计数；锁定且未售出的商品原样保留
static func roll_shop(gm: Node, new_wave: bool = false) -> void:
	if new_wave:
		gm.reroll_count = 0
		gm.reroll_free_left = gm.free_rerolls
	var wave := maxi(gm.wave_number, 1)
	var old: Array = gm.shop_offers
	var new_offers: Array = []
	for i in range(gm.SHOP_BASE_SLOTS + gm.shop_slots_bonus):
		if i < old.size() and old[i].get("locked", false) and not old[i].get("sold", false):
			new_offers.append(old[i])
		else:
			new_offers.append(gen_offer(gm, wave))
	gm.shop_offers = new_offers
	gm.reroll_cost = GameBalance.reroll_cost(wave, gm.reroll_count, gm.shop_price_mult)
	if new_wave:
		SynergySystem.apply_main_tag_pity(gm, wave)

## 单个货架位：按概率分流 回气丹 / 法宝 / 法器
static func gen_offer(gm: Node, wave: int) -> Dictionary:
	var roll: float = gm.rng.randf()
	if roll < GameBalance.POTION_CHANCE:
		return {
			"kind": "potion", "id": WeaponData.POTION_ID,
			"price": GameBalance.potion_price(WeaponData.POTION_BASE_PRICE, wave, gm.shop_price_mult),
			"sold": false, "locked": false,
		}
	if roll < GameBalance.POTION_CHANCE + GameBalance.ITEM_CHANCE:
		var item_id := ItemData.pick_id(gm.luck, wave, gm.items, gm.rng, gm.unlocked_items)
		if item_id != "":
			var idef := ItemData.get_def(item_id)
			return {
				"kind": "item", "id": item_id,
				"price": GameBalance.item_price(int(idef.get("price", 20)), wave, gm.shop_price_mult * gm.item_price_mult),
				"sold": false, "locked": false,
			}
		# 法宝池抽空 → 本格落回法器
	var w_id := weighted_weapon_pick(gm)
	var base := int(WeaponData.get_def(w_id).get("price", 20))
	return {
		"kind": "weapon", "id": w_id,
		"price": GameBalance.weapon_price(base, wave, gm.shop_price_mult),
		"sold": false, "locked": false,
	}

## 标签亲和 + 流派偏好软加权抽法器
static func weighted_weapon_pick(gm: Node) -> String:
	var pool: Array = WeaponData.SHOP_POOL
	var counts := SynergySystem.tag_counts(gm)
	var luck_mult := GameBalance.shop_luck_mult(gm.luck)
	var weights: Array = []
	for w_id in pool:
		var w := luck_mult
		var best_aff := 1.0
		for t in WeaponData.tags_of(w_id):
			best_aff = maxf(best_aff, GameBalance.tag_affinity_mult(int(counts.get(t, 0))))
		w *= best_aff
		w *= GameBalance.tag_filter_mult(WeaponData.tags_of(w_id), gm.shop_tag_filter)
		weights.append(w)
	var idx := GameBalance.weighted_pick_index(weights, gm.rng.randf())
	return String(pool[idx])

static func toggle_lock(gm: Node, index: int) -> void:
	if index < 0 or index >= gm.shop_offers.size():
		return
	var offer: Dictionary = gm.shop_offers[index]
	if offer.get("sold", false):
		return
	offer["locked"] = not offer.get("locked", false)
	AudioManager.play_sfx("shop_lock", 1.0)

static func buy_offer(gm: Node, index: int) -> bool:
	if index < 0 or index >= gm.shop_offers.size():
		return false
	var offer: Dictionary = gm.shop_offers[index]
	if offer.get("sold", false) or gm.spirit_stones < int(offer.get("price", 0)):
		return false
	var ok := false
	match String(offer.get("kind", "weapon")):
		"potion":
			if gm.player != null and gm.player.has_method("heal"):
				gm.player.heal(gm.player.max_health * 0.5)
				ok = true
		"item":
			ok = gm.add_item(offer.get("id", ""))
			if not ok:
				gm.announcement_triggered.emit("此道具每局限购一件")
				AudioManager.play_sfx("ui_error", 0.9)
				return false
		_:
			ok = WeaponInventory.add_weapon(gm, offer.get("id", ""))
			if not ok:
				gm.announcement_triggered.emit("装备与背包都满了，先出售一些吧")
				AudioManager.play_sfx("ui_error", 0.9)
				return false
	if not ok:
		return false
	gm.spirit_stones -= int(offer.get("price", 0))
	offer["sold"] = true
	gm.stats_updated.emit(gm.kills, gm.game_time, gm.spirit_stones)
	AudioManager.play_sfx("shop_buy", 1.0)
	return true

static func reroll_shop(gm: Node) -> bool:
	if gm.reroll_free_left > 0:
		gm.reroll_free_left -= 1
	else:
		if gm.spirit_stones < gm.reroll_cost:
			return false
		gm.spirit_stones -= gm.reroll_cost
		gm.reroll_count += 1
	roll_shop(gm, false)
	gm.stats_updated.emit(gm.kills, gm.game_time, gm.spirit_stones)
	AudioManager.play_sfx("shop_reroll", 1.0)
	return true

static func confirm_shop(gm: Node) -> void:
	gm.get_tree().paused = false
	gm.shop_closed.emit()
