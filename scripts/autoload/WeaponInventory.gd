class_name WeaponInventory
extends RefCounted

## 武器/武器持有、背包（纳戒）、三合一合成与出售子系统
## 从 GameManager 抽离，负责上阵悬浮武器、御灵（drones）与背包（stash）的统一调度。

static func drone_id(item) -> String:
	if item is Dictionary:
		return String(item.get("id", "lingdie"))
	return "lingdie"

static func drone_star(item) -> int:
	if item is Dictionary:
		return int(item.get("star", 1))
	return int(item)

static func slots_used(gm: Node) -> int:
	var used: int = gm.drones.size()
	if gm.player != null and gm.player.has_method("get_weapon_count"):
		used += gm.player.get_weapon_count()
	return used

## 获得一件武器：上阵栏位有空则上阵，否则进背包；两处都满返回 false
static func add_weapon(gm: Node, w_id: String, star: int = 1) -> bool:
	var def := WeaponData.get_def(w_id)
	if def.is_empty():
		return false
	if slots_used(gm) < gm.max_weapon_slots():
		if def.get("behavior", -1) == WeaponData.Behavior.DRONE:
			gm.drones.append({"id": w_id, "star": star})
			if gm.player != null and gm.player.has_method("sync_drones"):
				gm.player.sync_drones()
		else:
			if gm.player == null or not gm.player.has_method("add_weapon_instance"):
				return false
			gm.player.add_weapon_instance(w_id, star)
	else:
		if gm.stash.size() >= WeaponData.MAX_STASH_SLOTS:
			return false
		gm.stash.append({
			"id": w_id,
			"name": def.get("name", "?"),
			"star": star,
			"icon": def.get("icon", ""),
			"tag": def.get("tag", ""),
		})
	gm.notify_weapons_updated(get_weapons_summary(gm))
	return true

## (id, star) 的持有总数：上阵悬浮武器 + 灵蝶 + 背包
static func count_copies(gm: Node, w_id: String, star: int) -> int:
	var n := 0
	if gm.player != null and gm.player.has_method("get_equipped_weapons_data"):
		for w in gm.player.get_equipped_weapons_data():
			if w.get("id", "") == w_id and int(w.get("star", 1)) == star:
				n += 1
	for s in gm.drones:
		if drone_id(s) == w_id and drone_star(s) == star:
			n += 1
	for e in gm.stash:
		if e.get("id", "") == w_id and int(e.get("star", 1)) == star:
			n += 1
	return n

## 统计一件武器各星级当前持有量字典：{1: c1, 2: c2, 3: c3}
static func star_distribution(gm: Node, w_id: String) -> Dictionary:
	var dist := {}
	for s in range(1, WeaponData.MAX_STAR + 1):
		var c := count_copies(gm, w_id, s)
		if c > 0:
			dist[s] = c
	return dist

## 简短格式化拥有数量与星级分布（如 "★1×2  ★2×1"，若未拥有则返回空串）
static func format_owned_summary(gm: Node, w_id: String) -> String:
	var dist := star_distribution(gm, w_id)
	if dist.is_empty():
		return ""
	var parts: Array[String] = []
	for s in range(1, WeaponData.MAX_STAR + 1):
		if dist.has(s):
			parts.append("★%d×%d" % [s, int(dist[s])])
	return "  ".join(parts)

## 按 merge_weapon 的消耗顺序统计「可被消耗的副本数」（排除 keep 指定的保留件）
static func count_mergeable_copies(gm: Node, w_id: String, star: int, keep: Dictionary) -> int:
	var n := 0
	var keep_pool: String = keep.get("pool", "")
	var keep_index := int(keep.get("index", -1))
	for j in range(gm.stash.size()):
		if keep_pool == "stash" and keep_index == j:
			continue
		if gm.stash[j].get("id", "") == w_id and int(gm.stash[j].get("star", 1)) == star:
			n += 1
	for j in range(gm.drones.size()):
		if keep_pool == "drone" and keep_index == j:
			continue
		if drone_id(gm.drones[j]) == w_id and drone_star(gm.drones[j]) == star:
			n += 1
	if gm.player != null and gm.player.has_method("get_equipped_weapons_data"):
		var equipped: Array = gm.player.get_equipped_weapons_data()
		for j in range(equipped.size()):
			if keep_pool == "equipped" and keep_index == j:
				continue
			if equipped[j].get("id", "") == w_id and int(equipped[j].get("star", 1)) == star:
				n += 1
	return n

## 手动合成：keep 指定保留哪一件（pool: "equipped"/"drone"/"stash"，index 为对应池下标）
static func merge_weapon(gm: Node, w_id: String, star: int, keep: Dictionary) -> bool:
	if star >= WeaponData.MAX_STAR:
		return false
	if count_copies(gm, w_id, star) < 3:
		return false
	var need := 2

	if count_mergeable_copies(gm, w_id, star, keep) < need:
		push_warning("merge_weapon: 缺少 2 件可消耗的同名同星副本（keep=%s）" % str(keep))
		return false

	# 1. 消耗背包副本（保留 keeper）
	var new_stash: Array = []
	for j in range(gm.stash.size()):
		var is_keeper: bool = keep.get("pool", "") == "stash" and int(keep.get("index", -1)) == j
		if not is_keeper and gm.stash[j].get("id", "") == w_id and int(gm.stash[j].get("star", 1)) == star and need > 0:
			need -= 1
			continue
		if is_keeper:
			var k_def := WeaponData.get_def(w_id)
			new_stash.append({
				"id": w_id,
				"name": k_def.get("name", "?"),
				"star": star + 1,
				"icon": k_def.get("icon", ""),
				"tag": k_def.get("tag", ""),
			})
		else:
			new_stash.append(gm.stash[j])
	gm.stash = new_stash

	# 2. 消耗上阵灵宝（重建数组并升级 keeper）
	var is_drone_wp: bool = WeaponData.get_def(w_id).get("behavior", -1) == WeaponData.Behavior.DRONE or w_id == "lingdie"
	if is_drone_wp:
		var new_drones: Array = []
		for j in range(gm.drones.size()):
			var is_keeper_d: bool = keep.get("pool", "") == "drone" and int(keep.get("index", -1)) == j
			if not is_keeper_d and drone_id(gm.drones[j]) == w_id and drone_star(gm.drones[j]) == star and need > 0:
				need -= 1
				continue
			if is_keeper_d:
				new_drones.append({"id": w_id, "star": star + 1})
			else:
				new_drones.append(gm.drones[j])
		gm.drones = new_drones
		if gm.player != null and gm.player.has_method("sync_drones"):
			gm.player.sync_drones()

	# 3. 消耗上阵悬浮武器（按节点引用移除，keeper 原地升级）
	var keeper_node: Node = null
	if gm.player != null and gm.player.has_method("get_equipped_weapons_data"):
		var equipped: Array = gm.player.get_equipped_weapons_data()
		if keep.get("pool", "") == "equipped" and int(keep.get("index", -1)) >= 0 and int(keep.get("index", -1)) < equipped.size():
			keeper_node = equipped[int(keep.get("index", -1))].get("node")
		for j in range(equipped.size() - 1, -1, -1):
			if need <= 0:
				break
			var w: Dictionary = equipped[j]
			if w.get("node") == keeper_node:
				continue
			if w.get("id", "") == w_id and int(w.get("star", 1)) == star:
				gm.player.remove_weapon_instance(w.get("node"))
				need -= 1

	if need > 0:
		push_warning("merge_weapon: 副本数量不足，状态已部分变更")
		gm.notify_weapons_updated(get_weapons_summary(gm))
		return false

	# 4. 升级保留件
	if keeper_node != null and is_instance_valid(keeper_node) and gm.player.has_method("upgrade_weapon_instance"):
		gm.player.upgrade_weapon_instance(keeper_node, star + 1)

	gm.announcement_triggered.emit("✦ 三合一 · %s ✦" % WeaponData.full_name(w_id, star + 1))
	AudioManager.play_sfx("merge_success", 1.0)
	gm.notify_weapons_updated(get_weapons_summary(gm))
	return true

## HUD/商店通用的上阵列表（悬浮武器在前，灵宝在后）
static func get_weapons_summary(gm: Node) -> Array:
	var list: Array = []
	if gm.player != null and gm.player.has_method("get_equipped_weapons_data"):
		list.append_array(gm.player.get_equipped_weapons_data())
	for i in range(gm.drones.size()):
		var d_id := drone_id(gm.drones[i])
		var d_star := drone_star(gm.drones[i])
		var def := WeaponData.get_def(d_id)
		list.append({
			"id": d_id, "name": def.get("name", "武器"),
			"star": d_star,
			"icon": def.get("icon", ""), "is_drone": true,
			"tag": def.get("tag", ""), "node": null, "drone_index": i,
		})
	return list

## 按上阵 summary 下标出售（悬浮武器与灵蝶统一处理）
static func sell_weapon(gm: Node, index: int) -> bool:
	var list := get_weapons_summary(gm)
	if index < 0 or index >= list.size():
		return false
	var item: Dictionary = list[index]
	var price: int = 0
	if item.get("is_drone", false):
		var di := int(item.get("drone_index", -1))
		if di < 0 or di >= gm.drones.size():
			return false
		var d = gm.drones[di]
		price = WeaponData.sell_price(drone_id(d), drone_star(d))
		gm.drones.remove_at(di)
		if gm.player != null and gm.player.has_method("sync_drones"):
			gm.player.sync_drones()
	else:
		var node: Node = item.get("node")
		if node == null or not is_instance_valid(node):
			return false
		price = WeaponData.sell_price(item.get("id", ""), item.get("star", 1))
		gm.player.remove_weapon_instance(node)
	gm.spirit_stones += price
	gm.stats_updated.emit(gm.kills, gm.game_time, gm.spirit_stones)
	gm.notify_weapons_updated(get_weapons_summary(gm))
	AudioManager.play_sfx("sell", 1.0)
	return true

## 背包 → 上阵（上阵栏位有空位时）
static func equip_from_stash(gm: Node, index: int) -> bool:
	if index < 0 or index >= gm.stash.size():
		return false
	if slots_used(gm) >= gm.max_weapon_slots():
		gm.announcement_triggered.emit("装备已满 %d 件，先卸下一件武器" % gm.max_weapon_slots())
		AudioManager.play_sfx("ui_error", 0.9)
		return false
	var entry: Dictionary = gm.stash[index]
	var e_id: String = entry.get("id", "")
	var e_def := WeaponData.get_def(e_id)
	gm.stash.remove_at(index)
	if e_def.get("behavior", -1) == WeaponData.Behavior.DRONE:
		gm.drones.append({"id": e_id, "star": int(entry.get("star", 1))})
		if gm.player != null and gm.player.has_method("sync_drones"):
			gm.player.sync_drones()
	else:
		gm.player.add_weapon_instance(e_id, int(entry.get("star", 1)))
	gm.notify_weapons_updated(get_weapons_summary(gm))
	AudioManager.play_sfx("equip", 1.0)
	return true

## 从上阵 summary 摘下一件（灵宝摘 drones、悬浮武器摘节点实例）：unequip / 换装共用
static func _remove_summary_item(gm: Node, item: Dictionary) -> bool:
	if item.get("is_drone", false):
		var di := int(item.get("drone_index", -1))
		if di < 0 or di >= gm.drones.size():
			return false
		gm.drones.remove_at(di)
		if gm.player != null and gm.player.has_method("sync_drones"):
			gm.player.sync_drones()
		return true
	var node: Node = item.get("node")
	if node == null or not is_instance_valid(node):
		return false
	gm.player.remove_weapon_instance(node)
	return true

## 上阵件 → 背包条目（卸下 / 换装共用同一种打包）
static func _to_stash_entry(item: Dictionary) -> Dictionary:
	var u_id: String = item.get("id", "")
	var u_def := WeaponData.get_def(u_id)
	return {
		"id": u_id,
		"name": item.get("name", u_def.get("name", "?")),
		"star": int(item.get("star", 1)),
		"icon": item.get("icon", u_def.get("icon", "")),
		"tag": item.get("tag", u_def.get("tag", "")),
	}

## 上阵 → 背包（summary 下标；背包有空位时）
static func unequip_to_stash(gm: Node, index: int) -> bool:
	var list := get_weapons_summary(gm)
	if index < 0 or index >= list.size():
		return false
	if gm.stash.size() >= WeaponData.MAX_STASH_SLOTS:
		gm.announcement_triggered.emit("背包已满，先出售一些武器")
		AudioManager.play_sfx("ui_error", 0.9)
		return false
	var item: Dictionary = list[index]
	if not _remove_summary_item(gm, item):
		return false
	gm.stash.append(_to_stash_entry(item))
	gm.notify_weapons_updated(get_weapons_summary(gm))
	AudioManager.play_sfx("unequip", 1.0)
	return true

## 背包 → 上阵「换装」（旧口径，保留给既有判据）：上阵未满时等同 equip_from_stash；
## 已满时走 equip_stash_into_slot 的替换语义。
static func swap_into_equipped(gm: Node, stash_index: int, equipped_index: int) -> bool:
	if stash_index < 0 or stash_index >= gm.stash.size():
		return false
	if slots_used(gm) < gm.max_weapon_slots():
		return equip_from_stash(gm, stash_index)
	return equip_stash_into_slot(gm, stash_index, equipped_index)

## 背包 → 上阵指定格（拖拽落点语义，2026-10-11 用户：拖到已佩戴的武器上＝替换）：
## 指向已占用格＝替换那一格（换下的一件回背包被腾出的原位 stash_index，不是排到队尾）；
## 指向空格/越界＝直接装备（上阵次序固定「悬浮武器在前、灵宝在后」，新件落在队尾）。
## 反方向（上阵件拖到背包里的某一件上）走这同一个函数：互换的两个半边本来就是一件事。
## 同池替换认「位置」（2026-10-11 用户：替换要落在原来那一格，不是把整排顺序打乱）：
## 灵宝顶灵宝＝原地改 drones[di]（环绕方位不动）；悬浮武器顶悬浮武器＝新实例挂在 holder
## 队尾，再 reorder_weapons 换回被顶掉的那一格。跨池（灵宝换悬浮武器）没有可落的位置，
## 新件按 summary 口径落在自己那一池的队尾。
static func equip_stash_into_slot(gm: Node, stash_index: int, slot_index: int) -> bool:
	if stash_index < 0 or stash_index >= gm.stash.size():
		return false
	var list := get_weapons_summary(gm)
	if slot_index < 0 or slot_index >= list.size():
		# 空格＝直接装备；headless/异常态没有玩家节点时非灵宝接不住，先验后动
		var e_def0 := WeaponData.get_def(String(gm.stash[stash_index].get("id", "")))
		if e_def0.get("behavior", -1) != WeaponData.Behavior.DRONE \
				and (gm.player == null or not gm.player.has_method("add_weapon_instance")):
			return false
		return equip_from_stash(gm, stash_index)
	var entry: Dictionary = gm.stash[stash_index]
	var entry_id: String = String(entry.get("id", ""))
	var entry_star: int = int(entry.get("star", 1))
	var e_def := WeaponData.get_def(entry_id)
	var as_drone: bool = e_def.get("behavior", -1) == WeaponData.Behavior.DRONE
	# 悬浮武器要有玩家节点才接得住（headless/异常态）：先验完再动手，不做半截回滚
	if not as_drone and (gm.player == null or not gm.player.has_method("add_weapon_instance")):
		return false
	var item: Dictionary = list[slot_index]
	var was_drone: bool = item.get("is_drone", false)
	if was_drone and as_drone:
		var di := int(item.get("drone_index", -1))
		if di < 0 or di >= gm.drones.size():
			return false
		gm.drones[di] = {"id": entry_id, "star": entry_star}
		if gm.player != null and gm.player.has_method("sync_drones"):
			gm.player.sync_drones()
	else:
		if not _remove_summary_item(gm, item):
			return false
		if as_drone:
			gm.drones.append({"id": entry_id, "star": entry_star})
			if gm.player != null and gm.player.has_method("sync_drones"):
				gm.player.sync_drones()
		else:
			gm.player.add_weapon_instance(entry_id, entry_star)
			if not was_drone and gm.player.has_method("reorder_weapons"):
				# 新实例在 holder 队尾：换回被顶掉的那一格（summary 里悬浮武器在前，
				# 所以上阵下标就是 holder 下标）
				var n: int = gm.player.get_weapon_count()
				gm.player.reorder_weapons(n - 1, clampi(slot_index, 0, n - 1))
	gm.stash.remove_at(stash_index)
	gm.stash.insert(mini(stash_index, gm.stash.size()), _to_stash_entry(item))
	gm.notify_weapons_updated(get_weapons_summary(gm))
	AudioManager.play_sfx("equip", 1.0)
	return true

## 上阵两格互换位置（summary 下标；拖拽换位用）：两件同为悬浮武器 ⇒ 换 weapon_holder
## 子节点次序（环绕角度随次序重排，见 Player.reorder_weapons）；同为灵宝 ⇒ 换 drones
## 数组次序。混池不换：summary 固定「悬浮武器在前、灵宝在后」，跨池次序没有可落的数据。
static func swap_equipped_slots(gm: Node, i: int, j: int) -> bool:
	if i < 0 or j < 0 or i == j:
		return false
	var list := get_weapons_summary(gm)
	if i >= list.size() or j >= list.size():
		return false
	var a: Dictionary = list[i]
	var b: Dictionary = list[j]
	var a_drone: bool = a.get("is_drone", false)
	var b_drone: bool = b.get("is_drone", false)
	if a_drone != b_drone:
		return false
	if a_drone:
		var ai := int(a.get("drone_index", -1))
		var bi := int(b.get("drone_index", -1))
		if ai < 0 or bi < 0 or ai >= gm.drones.size() or bi >= gm.drones.size():
			return false
		var tmp = gm.drones[ai]
		gm.drones[ai] = gm.drones[bi]
		gm.drones[bi] = tmp
		if gm.player != null and gm.player.has_method("sync_drones"):
			gm.player.sync_drones()
	else:
		if gm.player == null or not gm.player.has_method("reorder_weapons"):
			return false
		gm.player.reorder_weapons(i, j)
	gm.notify_weapons_updated(get_weapons_summary(gm))
	AudioManager.play_sfx("ui_click", 1.0)
	return true

## 背包内拖拽排序：把 from 号移到 to 号（其余顺移）。to 允许给到 size（背包空位/分隔签的
## 「挪到队尾」），夹进 [0, size-1] 后与 from 相同就是原地不动，返回 false 不算一次操作。
static func reorder_stash(gm: Node, from: int, to: int) -> bool:
	if from < 0 or from >= gm.stash.size():
		return false
	to = clampi(to, 0, gm.stash.size() - 1)
	if from == to:
		return false
	var entry: Dictionary = gm.stash[from]
	gm.stash.remove_at(from)
	gm.stash.insert(to, entry)
	gm.notify_weapons_updated(get_weapons_summary(gm))
	AudioManager.play_sfx("ui_click", 1.0)
	return true

## 按背包下标出售
static func sell_stash(gm: Node, index: int) -> bool:
	if index < 0 or index >= gm.stash.size():
		return false
	var entry: Dictionary = gm.stash[index]
	var price := WeaponData.sell_price(entry.get("id", ""), int(entry.get("star", 1)))
	gm.stash.remove_at(index)
	gm.spirit_stones += price
	gm.stats_updated.emit(gm.kills, gm.game_time, gm.spirit_stones)
	gm.notify_weapons_updated(get_weapons_summary(gm))
	AudioManager.play_sfx("sell", 1.0)
	return true
