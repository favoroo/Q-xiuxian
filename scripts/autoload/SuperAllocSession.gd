class_name SuperAllocSession
extends RefCounted

## 超级悟道会话子系统（2026-10-25）
## 从 GameManager 抽离，管三选一之外的五选一：每 5 关一次、不可刷新、选完才轮到普通悟道。
## 候选抽法（3 张流派 + 2 张通用）与落地（赠送神通道具）都在 SuperUpgradeData。

static func should_open(gm: Node) -> bool:
	if not SuperUpgradeData.is_super_wave(gm.wave_number):
		return false
	return not (gm.wave_number in gm.super_alloc_done_waves)

static func open(gm: Node) -> void:
	gm.super_alloc_offers = SuperUpgradeData.roll_offers(gm)
	if gm.super_alloc_offers.is_empty():
		# 卡池抽空（卡池 24 张全拿完才会发生，正常跑不到）：记账放行，别把回合卡死
		_finish(gm)
		return
	gm.super_alloc_opened.emit()

static func take(gm: Node, index: int) -> bool:
	if index < 0 or index >= gm.super_alloc_offers.size():
		return false
	var card_id := String(gm.super_alloc_offers[index].get("id", ""))
	if card_id.is_empty():
		return false
	if not SuperUpgradeData.apply(gm, card_id):
		return false
	AudioManager.play_sfx("stat_alloc", 1.45)
	_finish(gm)
	return true

static func _finish(gm: Node) -> void:
	if not (gm.wave_number in gm.super_alloc_done_waves):
		gm.super_alloc_done_waves.append(gm.wave_number)
	gm.super_alloc_offers.clear()
	gm.super_alloc_finished.emit()
