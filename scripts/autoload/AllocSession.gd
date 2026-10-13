class_name AllocSession
extends RefCounted

## 回合后悟道结算会话子系统
## 从 GameManager 抽离，负责待加点消费、每回合免费刷新与付费重掷。

static func open_alloc_session(gm: Node) -> void:
	if gm.pending_upgrade_points <= 0:
		return
	gm.alloc_points_total = gm.pending_upgrade_points
	gm.alloc_reroll_count = 0
	# 学者·博学：每回合免费刷新在基准之上加成（alloc_free_reroll_bonus，缺省 0）
	gm.alloc_reroll_free_left = gm.ALLOC_FREE_REROLLS + gm.alloc_free_reroll_bonus
	gm.alloc_reroll_cost = GameBalance.reroll_cost(gm.wave_number, gm.alloc_reroll_count, gm.shop_price_mult)
	roll_alloc_offers(gm)
	if gm.alloc_offers.is_empty():
		force_end_alloc(gm, "升级已尽")
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
	# 学者·博学：候选数在基准之上加成（alloc_offer_bonus，缺省 0）
	gm.alloc_offers = gm.roll_upgrades(gm.UPGRADE_OFFER_COUNT + gm.alloc_offer_bonus)
	# 「荐」标：按当前角色+构筑打分（开面板/翻屏/刷新都汇在这条路，只此一处）
	RecommendSystem.mark_alloc_offers(gm)

static func take_alloc_upgrade(gm: Node, index: int) -> bool:
	if index < 0 or index >= gm.alloc_offers.size():
		return false
	var uid: String = String(gm.alloc_offers[index].get("id", ""))
	if uid.is_empty():
		return false
	gm.apply_upgrade(uid)
	gm.pending_upgrade_points = maxi(0, gm.pending_upgrade_points - 1)
	gm.pending_points_changed.emit(gm.pending_upgrade_points)
	AudioManager.play_sfx("stat_alloc", 1.25)
	if gm.pending_upgrade_points > 0:
		roll_alloc_offers(gm)
		if gm.alloc_offers.is_empty():
			force_end_alloc(gm, "升级已尽")
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
			gm.announcement_triggered.emit("金币不够刷新升级了")
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
		return "免费刷新升级 (剩 %d 次)" % gm.alloc_reroll_free_left
	return "刷新升级 (%d 金币)" % gm.alloc_reroll_cost

static func can_reroll_alloc(gm: Node) -> bool:
	return gm.pending_upgrade_points > 0 and (gm.alloc_reroll_free_left > 0 or gm.spirit_stones >= gm.alloc_reroll_cost)
