class_name ShopSystem
extends RefCounted

## 回合间商店（金币阁）子系统
## 从 GameManager 抽离，负责货架生成、标签亲和加权抽武器、锁定保留、购买结算与重掷。

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
	# 商人·老主顾：重掷费用在纯函数结果上乘角色系数（GameBalance 保持纯函数，下限 1 金币）
	gm.reroll_cost = maxi(1, int(round(GameBalance.reroll_cost(wave, gm.reroll_count, gm.shop_price_mult) * gm.reroll_price_mult)))
	if new_wave:
		# 道具轻保底先跑：它可能顶掉一个武器格，武器保底随后再按剩余货架判断。
		apply_main_item_pity(gm, wave)
		SynergySystem.apply_main_tag_pity(gm, wave)
	# 「荐」标：在回合首保底塞货之后统一打分（保底换上去的那件也要进推荐评比）；
	# 锁定保留的旧货会被重新评分，重复调用幂等
	RecommendSystem.mark_shop_offers(gm)

## 道具轻保底（2026-10-21）：连续 ITEM_PITY_WAVES 波货架没有出现
## 「主武器伤害类别 / 角色偏好标签」的道具时，把一个未锁定的武器格换成对应道具。
## 只补能用的方向，不指定具体某件；候选仍走解锁/unique/穿透/构筑过滤四条闸。
static func apply_main_item_pity(gm: Node, wave: int) -> void:
	var relevant: Array = BalanceBuildFilter.relevant_item_tags(gm)
	if relevant.is_empty():
		gm._no_main_item_waves = 0
		return
	var has_relevant := false
	for offer in gm.shop_offers:
		if String(offer.get("kind", "")) == "item" \
				and BalanceBuildFilter.item_matches_tags(String(offer.get("id", "")), relevant):
			has_relevant = true
			break
	if has_relevant:
		gm._no_main_item_waves = 0
		return
	gm._no_main_item_waves += 1
	if gm._no_main_item_waves < BalanceBuildFilter.ITEM_PITY_WAVES:
		return
	var tier_w: Array = GameBalance.item_tier_weights(gm.luck, wave)
	var pool: Array = []
	var weights: Array = []
	for id in ItemData.DEFS.keys():
		var iid := String(id)
		if ItemData.is_granted_only(iid):
			continue
		if not gm.unlocked_items.is_empty() and not (iid in gm.unlocked_items):
			continue
		if not PierceLimit.filter_item_id(gm, iid):
			continue
		var d: Dictionary = ItemData.get_def(iid)
		if bool(d.get("unique", false)) and iid in gm.items_bought:
			continue
		if not BalanceBuildFilter.item_allowed(gm, iid):
			continue
		if not BalanceBuildFilter.item_matches_tags(iid, relevant):
			continue
		var tier := clampi(int(d.get("tier", 1)), 1, 4)
		var w := float(tier_w[tier - 1])
		if w <= 0.0:
			continue
		w *= BalanceBuildFilter.item_affinity(gm, iid)
		pool.append(iid)
		weights.append(w)
	if pool.is_empty():
		return
	for i in range(gm.shop_offers.size()):
		var offer: Dictionary = gm.shop_offers[i]
		if offer.get("locked", false) or offer.get("sold", false):
			continue
		if String(offer.get("kind", "")) != "weapon":
			continue
		var picked := String(pool[GameBalance.weighted_pick_index(weights, gm.rng.randf())])
		var idef: Dictionary = ItemData.get_def(picked)
		gm.shop_offers[i] = {
			"kind": "item", "id": picked,
			"price": GameBalance.item_price(int(idef.get("price", 20)), wave,
					gm.shop_price_mult * gm.item_price_mult),
			"sold": false, "locked": false,
		}
		gm._no_main_item_waves = 0
		return

## 单个货架位：按概率分流 回气丹 / 道具 / 武器
static func gen_offer(gm: Node, wave: int) -> Dictionary:
	var roll: float = gm.rng.randf()
	if roll < GameBalance.POTION_CHANCE:
		return {
			"kind": "potion", "id": WeaponData.POTION_ID,
			"price": GameBalance.potion_price(WeaponData.POTION_BASE_PRICE, wave, gm.shop_price_mult),
			"sold": false, "locked": false,
		}
	if roll < GameBalance.POTION_CHANCE + GameBalance.ITEM_CHANCE:
		# 池子按「本局已购入」排重 unique 道具：卖掉的那件也不解禁（详情卡上那句
		# 「出售后本局不再出现」与这里是同一个账本），非 unique 的照旧可以反复上架。
		var item_id := ItemData.pick_id(gm.luck, wave, gm.items_bought, gm.rng, gm.unlocked_items, gm)
		if item_id != "":
			var idef := ItemData.get_def(item_id)
			return {
				"kind": "item", "id": item_id,
				"price": GameBalance.item_price(int(idef.get("price", 20)), wave, gm.shop_price_mult * gm.item_price_mult),
				"sold": false, "locked": false,
			}
		# 道具池抽空 → 本格落回武器
	var pet_bonus: float = float(gm.pet_offer_chance_bonus)
	if roll < GameBalance.POTION_CHANCE + GameBalance.ITEM_CHANCE + GameBalance.PET_CHANCE + pet_bonus:
		# 只有在灵兽栏未满且能抽出未拥有灵兽时才出灵兽，否则落回武器
		if gm.pets.size() < gm.max_pet_slots():
			var pet_id := PetData.pick_id(gm.pets, gm.rng)
			if pet_id != "":
				var pdef := PetData.get_def(pet_id)
				var base_price := int(pdef.get("base_price", 35))
				return {
					"kind": "pet", "id": pet_id,
					"price": GameBalance.pet_price(base_price, wave, gm.shop_price_mult),
					"sold": false, "locked": false,
				}
	var w_id := weighted_weapon_pick(gm)
	# ★2 成品（2026-10-25）：武器格有概率直接刷成 2 星，给升星路补一条金币捷径。
	# 临门一脚（手里同名 ★2 已 2 件，差 1 合 ★3）时抬概率地板 —— 追梦加权负责让同名多刷，
	# 这里负责让「刷出来的那件正好是 ★2」。无头/单测环境 count_copies 全走鸭子接口，安全。
	var star := 1
	var near_merge2: bool = (WeaponInventory.count_copies(gm, w_id, 2) % 3) == 2
	if gm.rng.randf() < GameBalance.weapon_star2_chance(wave, gm.luck, near_merge2):
		star = 2
	var base := int(WeaponData.get_def(w_id).get("price", 20))
	return {
		"kind": "weapon", "id": w_id, "star": star,
		"price": GameBalance.weapon_offer_price(base, wave, star, gm.shop_price_mult),
		"sold": false, "locked": false,
	}

## 梯度亲和（含双流派共鸣叠加）+ 流派偏好软加权 + 同名追梦加权抽武器
static func weighted_weapon_pick(gm: Node) -> String:
	var pool: Array = unlocked_weapon_pool(gm)
	var counts := SynergySystem.tag_counts(gm)
	var luck_mult := GameBalance.shop_luck_mult(gm.luck)
	var weights: Array = []
	for w_id in pool:
		var w := luck_mult
		w *= GameBalance.tag_affinity_combo(counts, WeaponData.tags_of(w_id))
		w *= GameBalance.tag_filter_mult(WeaponData.tags_of(w_id), gm.shop_tag_filter)
		w *= _dream_affinity_mult(gm, String(w_id))
		weights.append(w)
	var idx := GameBalance.weighted_pick_index(weights, gm.rng.randf())
	return String(pool[idx])

## 可上货架的武器池（2026-10-25 武器解锁）：按 unlocked_weapons 过滤。
## 池被滤空时回落全池 —— 与 ItemData.pick_id 同一兜底口径，货架绝不留空格。
## unlocked_weapons 为空数组同样视为「不过滤」（异常档兜底，正常档 ProgressStore 会回灌默认池）。
static func unlocked_weapon_pool(gm: Node) -> Array:
	if gm == null or gm.unlocked_weapons.is_empty():
		return WeaponData.SHOP_POOL
	var pool: Array = []
	for w_id in WeaponData.SHOP_POOL:
		if String(w_id) in gm.unlocked_weapons:
			pool.append(w_id)
	return pool if not pool.is_empty() else WeaponData.SHOP_POOL

## 同名追梦加权（2026-10-24）：按手里这把武器的最高星级与同星件数取倍率。
## 三合一是「3 件换 1 件」，合成后标签件数掉 2 ⇒ 流派亲和反而变弱，越合越刷不到自己那把，
## 27 把 ★1 的追梦在数学上走不完。这一层只补同名武器的权重，不动标签亲和的算法。
static func _dream_affinity_mult(gm: Node, w_id: String) -> float:
	var best_star := 0
	var best_copies := 0
	for s in range(1, WeaponData.MAX_STAR + 1):
		var c := WeaponInventory.count_copies(gm, w_id, s)
		if c > 0:
			best_star = s
			best_copies = c
	return GameBalance.owned_weapon_affinity_mult(best_star, best_copies)

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
				# 回复量与货架卡上印的那个数是同一条公式（GameBalance.potion_heal_amount）
				gm.player.heal(GameBalance.potion_heal_amount(gm.player.max_health))
				ok = true
		"item":
			ok = gm.add_item(offer.get("id", ""))
			if not ok:
				gm.announcement_triggered.emit("此道具每局限购一件")
				AudioManager.play_sfx("ui_error", 0.9)
				return false
		"pet":
			var pet_id: String = String(offer.get("id", ""))
			if gm.pets.size() >= gm.max_pet_slots():
				gm.announcement_triggered.emit("灵兽栏已满，先出售一些吧")
				AudioManager.play_sfx("ui_error", 0.9)
				return false
			if pet_id in gm.pets:
				gm.announcement_triggered.emit("此灵兽已随行")
				AudioManager.play_sfx("ui_error", 0.9)
				return false
			ok = gm.add_pet(pet_id)
			if not ok:
				gm.announcement_triggered.emit("契约灵兽失败")
				AudioManager.play_sfx("ui_error", 0.9)
				return false
		_:
			# 货架可以卖 ★2 成品：星数随 offer 走，缺省 ★1（保底塞进来的武器与旧存档都不带 star 键）
			ok = WeaponInventory.add_weapon(gm, offer.get("id", ""), int(offer.get("star", 1)))
			if not ok:
				gm.announcement_triggered.emit("装备与背包都满了，先出售一些吧")
				AudioManager.play_sfx("ui_error", 0.9)
				return false
	if not ok:
		return false
	var price_paid := int(offer.get("price", 0))
	gm.spirit_stones -= price_paid
	gm.total_stones_spent += price_paid
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
		gm.total_stones_spent += gm.reroll_cost
		gm.reroll_count += 1
	roll_shop(gm, false)
	gm.stats_updated.emit(gm.kills, gm.game_time, gm.spirit_stones)
	AudioManager.play_sfx("shop_reroll", 1.0)
	return true

static func confirm_shop(gm: Node) -> void:
	gm.get_tree().paused = false
	gm.shop_closed.emit()
	# 悟道/金币阁整段回合间流程都在暂停，镜头原语在恢复的这一拍才吃得到：
	# 一记轻 punch 给「回场开打」一个可感的起点（幅度小，不与下一波开场的刷怪音/震屏抢戏）
	GameFeel.zoom_punch(gm, 0.025, 0.12)
