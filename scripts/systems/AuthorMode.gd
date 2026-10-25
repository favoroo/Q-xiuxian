class_name AuthorMode
extends RefCounted

## 作者模式（Author Mode）—— 会话级测试开关，**不写任何存档**。
##
## 设计口径：
## - 开关本体是 `GameManager.author_mode`（普通成员，不进 ProgressStore / RunSave），
##   下次启动游戏自然是普通模式；关掉开关时本文件里的作弊状态一并复位。
## - 所有"作弊动作"集中在这里，GameManager / 面板 / 实体只留一行调用，
##   避免把测试逻辑散进战斗热路径。
## - 解锁类改动只做"读侧短路"（GameManager.is_*_unlocked），绝不往
##   unlocked_cultivators / unlocked_items 里写数据 —— 那是存档污染。
## - 悟道加点测试台（2026-10-25）：add_upgrade / remove_upgrade / take_super / remove_super
##   免费加删普通与超级悟道（只改账本与属性落地）。**重放触发在调用方**（AuthorAllocView）：
##   本文件若引用 AuthorStatRebuild 会构成 Player → AuthorMode → 重算器 → StatSystem/Player
##   的循环类依赖（坑 12），Player.gd 直接解析失败 —— 这条边必须留在 ui/author 侧。

## 无敌：Player.take_damage 入口直接返回
static var god_mode: bool = false
## 一击必杀：EnemyBase.take_damage 入口把伤害抬到必死
static var one_hit_kill: bool = false
## 时间加速倍率（1.0 / 2.0 / 4.0），由 GameManager 顿帧恢复与跳关共同读
static var time_scale: float = 1.0

## 关闭作者模式时把所有作弊状态复位（时间轴必须拉回 1.0，否则退出后整局慢/快放）
static func reset() -> void:
	god_mode = false
	one_hit_kill = false
	time_scale = 1.0
	Engine.time_scale = 1.0

## 当前应有的基础时间倍率：GameManager 顿帧结束、跳关落地都读它，
## 否则一次暴击顿帧就会把 2x/4x 打回 1x。
static func base_time_scale() -> float:
	return time_scale

## 循环切档 1x → 2x → 4x → 1x，返回切换后的倍率
static func cycle_time_scale() -> float:
	if time_scale < 1.5:
		time_scale = 2.0
	elif time_scale < 3.0:
		time_scale = 4.0
	else:
		time_scale = 1.0
	Engine.time_scale = time_scale
	return time_scale

## 直接把人物等级设为 target，并重算经验门槛链（与 add_experience 的升级链同源）。
## 上调的级数折算成待加点：回合末照常走悟道面板，属性收益与正常升级一致；
## 下调只改等级读数，不回收已获得的属性（测试时方便反复试构筑）。
static func set_level(gm: Node, target: int) -> void:
	var t := clampi(target, 1, 999)
	var old_level: int = int(gm.level)
	var chain: int = GameBalance.EXP_FIRST_LEVEL
	for _i in range(t - 1):
		chain = GameBalance.exp_to_next(chain)
	gm.level = t
	gm._exp_chain = chain
	gm.experience = 0
	gm.experience_to_next = maxi(1, int(round(float(chain) * float(gm.xp_require_mult))))
	if t > old_level:
		var gained := t - old_level
		gm.pending_upgrade_points += gained
		# 悟道面板正开着时，本次结算的「共几点」快照也要跟着涨，徽记详解里的
		# 「本回合连升」才对得上（作者模式边加点边调等级）
		if not gm.alloc_offers.is_empty():
			gm.alloc_points_total += gained
		gm.pending_points_changed.emit(gm.pending_upgrade_points)
		for i in range(gained):
			gm.player_leveled_up.emit(old_level + i + 1)
	gm.player_exp_changed.emit(gm.experience, gm.experience_to_next, gm.level)
	gm._mark_stats_dirty()

## 图鉴直购（免费）：kind = weapon / item / pet。
## 复用正常获得链路（武器满栏自动进背包、道具走属性 apply、灵兽走 PetSystem），
## 只跳过扣金币这一步 —— 作者模式的面板另有「金币 +1000/+10000」按钮供经济测试。
static func grant(gm: Node, kind: String, id: String, star: int = 1) -> bool:
	if gm == null or not gm.run_started or gm.player == null:
		return false
	var ok := false
	match kind:
		"weapon":
			ok = WeaponInventory.add_weapon(gm, id, clampi(star, 1, WeaponData.MAX_STAR))
		"item":
			ok = gm.add_item(id)
		"pet":
			ok = gm.add_pet(id)
		_:
			ok = false
	if ok:
		gm.stats_updated.emit(gm.kills, gm.game_time, gm.spirit_stones)
		AudioManager.play_sfx("shop_buy", 1.0)
	return ok

# ---------------- 悟道加点测试台（2026-10-25）：免费加 / 删，删完从初值重放 ----------------
##
## 加点走 gm.apply_upgrade（与真实结算同一条落地链路）；删除不走撤销 ——
## 撤销被上限夹住的字段会「一分不扣」永远卡在 cap。这里只改账本（counts/history/名册
## 三处同步 + harvest 名义值补偿），**账本改完由调用方触发 AuthorStatRebuild.rebuild**
## 从初值重放属性层，读数才与「真实只拿到这些层」完全一致。

## 免费加一层（不消耗待加点）。守住 max_stacks：超出上限的层真实玩法拿不到，测它没意义。
static func add_upgrade(gm: Node, upgrade_id: String, stacks: int = 1) -> bool:
	if gm == null or not gm.run_started or gm.player == null:
		return false
	var def := UpgradeData.get_upgrade_def(upgrade_id)
	if def.is_empty():
		return false
	var cap := int(def.get("max_stacks", 99))
	var can := maxi(0, cap - int(gm.upgrade_counts.get(upgrade_id, 0)))
	if can <= 0:
		gm.announcement_triggered.emit("「%s」已到 %d 层上限" % [String(def.get("title", upgrade_id)), cap])
		AudioManager.play_sfx("ui_error", 0.9)
		return false
	for _i in range(mini(stacks, can)):
		gm.apply_upgrade(upgrade_id)
	AudioManager.play_sfx("stat_alloc", 1.25)
	return true

## 免费删一层。账本三处同步（counts / history / 超级卡名册），
## harvest 按名义值补偿（重算器保留现值，见 AuthorStatRebuild 头注）。
static func remove_upgrade(gm: Node, upgrade_id: String, stacks: int = 1) -> bool:
	var removed := 0
	for _i in range(stacks):
		if not _drop_one_ledger(gm, upgrade_id):
			break
		removed += 1
	if removed == 0:
		return false
	var def := UpgradeData.get_upgrade_def(upgrade_id)
	var apply: Dictionary = def.get("apply", {}) if not def.is_empty() else {}
	if apply.has("harvest"):
		gm.harvest = maxf(0.0, gm.harvest - float(apply["harvest"]) * float(removed))
	gm.upgrade_applied.emit(upgrade_id)
	AudioManager.play_sfx("sell", 0.9)
	return true

## 清空普通悟道加点（超级悟道归 clear_supers 管），返回清掉的层数
static func clear_upgrades(gm: Node) -> int:
	var ids: Array = []
	for uid in gm.upgrade_counts.keys():
		if not UpgradeData.get_upgrade_def(String(uid)).is_empty():
			ids.append(String(uid))
	if ids.is_empty():
		return 0
	var total := 0
	for uid in ids:
		var n := int(gm.upgrade_counts.get(uid, 0))
		total += n
		var apply: Dictionary = UpgradeData.get_upgrade_def(uid).get("apply", {})
		if apply.has("harvest"):
			gm.harvest = maxf(0.0, gm.harvest - float(apply["harvest"]) * float(n))
		gm.upgrade_counts.erase(uid)
	for i in range(gm.upgrade_history.size() - 1, -1, -1):
		if String(gm.upgrade_history[i].get("id", "")) in ids:
			gm.upgrade_history.remove_at(i)
	gm.upgrade_applied.emit("")
	AudioManager.play_sfx("sell", 0.9)
	return total

## 领悟一张超级悟道卡（作者模式不设阶段门控/灵兽门控，测试台要能任意组合）
static func take_super(gm: Node, card_id: String) -> bool:
	if gm == null or not gm.run_started or gm.player == null:
		return false
	if card_id in gm.super_cards_taken:
		gm.announcement_triggered.emit("这张超级悟道已领悟")
		AudioManager.play_sfx("ui_error", 0.9)
		return false
	if not SuperUpgradeData.apply(gm, card_id):
		return false
	AudioManager.play_sfx("stat_alloc", 1.25)
	return true

## 撤销一张超级悟道卡：连它赠予的神通道具一起收走（那是它效果的唯一载体）
static func remove_super(gm: Node, card_id: String) -> bool:
	var card := SuperUpgradeData.get_def(card_id)
	if card.is_empty():
		return false
	var gid := String(card.get("grant_item", ""))
	if not _super_removal_allowed(gm, gid):
		return false
	if not gid.is_empty() and gm.has_item(gid):
		# consume_item 维护 unique_item_count 与三类 hook 缓存；属性层由重放回退
		gm.consume_item(gid)
	if not _drop_one_ledger(gm, card_id):
		return false
	gm.super_cards_taken.erase(card_id)
	gm.upgrade_applied.emit(card_id)
	AudioManager.play_sfx("sell", 0.9)
	return true

## 撤销全部超级悟道卡（被槽位守卫拦下的跳过），返回实际撤销的张数
static func clear_supers(gm: Node) -> int:
	var ids: Array = []
	for cid in gm.super_cards_taken:
		ids.append(String(cid))
	var removed := 0
	for cid in ids:
		if remove_super(gm, String(cid)):
			removed += 1
	return removed

## 待加点直接调拨（测真实悟道面板用）：与 set_level 同口径同步会话快照
static func grant_points(gm: Node, n: int) -> void:
	if n == 0:
		return
	gm.pending_upgrade_points = maxi(0, gm.pending_upgrade_points + n)
	if not gm.alloc_offers.is_empty():
		gm.alloc_points_total += n
	gm.pending_points_changed.emit(gm.pending_upgrade_points)

## 从 counts/history 里扣掉最后一条同 id 记录（counts 归零即 erase）
static func _drop_one_ledger(gm: Node, ledger_id: String) -> bool:
	var n := int(gm.upgrade_counts.get(ledger_id, 0))
	if n <= 0:
		return false
	if n <= 1:
		gm.upgrade_counts.erase(ledger_id)
	else:
		gm.upgrade_counts[ledger_id] = n - 1
	for i in range(gm.upgrade_history.size() - 1, -1, -1):
		if String(gm.upgrade_history[i].get("id", "")) == ledger_id:
			gm.upgrade_history.remove_at(i)
			break
	return true

## 撤销神通的槽位守卫（照 sell_item 的灵兽槽守卫口径）：撤了会让已上阵/已带灵兽超编就拒绝
static func _super_removal_allowed(gm: Node, gid: String) -> bool:
	if gid.is_empty():
		return true
	var idef := ItemData.get_def(gid)
	if idef.is_empty():
		return true
	var name_txt := String(idef.get("name", gid))
	var pet_slots := int(idef.get("apply", {}).get("pet_slots", 0))
	if pet_slots > 0 and gm.pets.size() > gm.max_pet_slots() - pet_slots:
		gm.announcement_triggered.emit("灵兽栏将超编，先移除灵兽再撤销【%s】" % name_txt)
		AudioManager.play_sfx("ui_error", 0.9)
		return false
	var slot_bonus := int(idef.get("weapon_slot_bonus", 0))
	if slot_bonus > 0 and gm.slots_used() > gm.max_weapon_slots() - slot_bonus:
		gm.announcement_triggered.emit("上阵武器数将超过槽位上限，先下阵一把再撤销【%s】" % name_txt)
		AudioManager.play_sfx("ui_error", 0.9)
		return false
	return true
