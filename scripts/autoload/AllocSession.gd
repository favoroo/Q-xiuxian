class_name AllocSession
extends RefCounted

## 波后悟道结算会话子系统
## 从 GameManager 抽离，负责待加点消费、每回合免费刷新与付费重掷。

static func open_alloc_session(gm: Node) -> void:
	if gm.pending_upgrade_points <= 0:
		return
	gm.alloc_points_total = gm.pending_upgrade_points
	gm.alloc_reroll_count = 0
	gm.alloc_reroll_free_left = gm.ALLOC_FREE_REROLLS
	gm.alloc_reroll_cost = GameBalance.reroll_cost(gm.wave_number, gm.alloc_reroll_count, gm.shop_price_mult)
	roll_alloc_offers(gm)
	if gm.alloc_offers.is_empty():
		force_end_alloc(gm, "悟道已尽")
		return
	gm.alloc_opened.emit()

static func force_end_alloc(gm: Node, reason: String) -> void:
	if gm.pending_upgrade_points > 0:
		gm.announcement_triggered.emit("✦ %s · 剩余 %d 点作废 ✦" % [reason, gm.pending_upgrade_points])
	gm.pending_upgrade_points = 0
	gm.alloc_offers.clear()
	gm.pending_points_changed.emit(0)
	gm.alloc_finished.emit()

static func roll_alloc_offers(gm: Node) -> void:
	gm.alloc_offers = gm.roll_upgrades(gm.UPGRADE_OFFER_COUNT)

static func take_alloc_upgrade(gm: Node, index: int) -> bool:
	if index < 0 or index >= gm.alloc_offers.size():
		return false
	var uid: String = String(gm.alloc_offers[index].get("id", ""))
	if uid.is_empty():
		return false
	gm.apply_upgrade(uid)
	gm.pending_upgrade_points = maxi(0, gm.pending_upgrade_points - 1)
	gm.pending_points_changed.emit(gm.pending_upgrade_points)
	AudioManager.play_sfx("gem_pickup", 1.25)
	if gm.pending_upgrade_points > 0:
		roll_alloc_offers(gm)
		if gm.alloc_offers.is_empty():
			force_end_alloc(gm, "悟道已尽")
		return true
	gm.alloc_offers.clear()
	gm.alloc_finished.emit()
	return true

static func reroll_alloc(gm: Node) -> bool:
	if gm.pending_upgrade_points <= 0:
		return false
	if gm.alloc_reroll_free_left > 0:
		gm.alloc_reroll_free_left -= 1
	else:
		if gm.spirit_stones < gm.alloc_reroll_cost:
			gm.announcement_triggered.emit("灵石不够刷新悟道了")
			AudioManager.play_sfx("ui_error", 0.9)
			return false
		gm.spirit_stones -= gm.alloc_reroll_cost
		gm.alloc_reroll_count += 1
		gm.alloc_reroll_cost = GameBalance.reroll_cost(gm.wave_number, gm.alloc_reroll_count, gm.shop_price_mult)
	roll_alloc_offers(gm)
	gm.stats_updated.emit(gm.kills, gm.game_time, gm.spirit_stones)
	AudioManager.play_sfx("shop_reroll", 1.0)
	return true

static func alloc_reroll_label(gm: Node) -> String:
	if gm.alloc_reroll_free_left > 0:
		return "免费刷新悟道 (剩 %d 次)" % gm.alloc_reroll_free_left
	return "刷新悟道 (%d 灵石)" % gm.alloc_reroll_cost

static func can_reroll_alloc(gm: Node) -> bool:
	return gm.pending_upgrade_points > 0 and (gm.alloc_reroll_free_left > 0 or gm.spirit_stones >= gm.alloc_reroll_cost)
