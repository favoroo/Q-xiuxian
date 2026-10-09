class_name WeaponInventory
extends RefCounted

## 武器/法器持有、背包（纳戒）、三合一合成与出售子系统
## 从 GameManager 抽离，负责上阵悬浮法器、御灵（drones）与背包（stash）的统一调度。

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

## 获得一件法器：上阵栏位有空则上阵，否则进背包；两处都满返回 false
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

## (id, star) 的持有总数：上阵悬浮法器 + 灵蝶 + 背包
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

	# 3. 消耗上阵悬浮法器（按节点引用移除，keeper 原地升级）
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

	gm.announcement_triggered.emit("✦ 三器合一 · %s ✦" % WeaponData.full_name(w_id, star + 1))
	AudioManager.play_sfx("merge_success", 1.0)
	gm.notify_weapons_updated(get_weapons_summary(gm))
	return true

## HUD/商店通用的上阵列表（悬浮法器在前，灵宝在后）
static func get_weapons_summary(gm: Node) -> Array:
	var list: Array = []
	if gm.player != null and gm.player.has_method("get_equipped_weapons_data"):
		list.append_array(gm.player.get_equipped_weapons_data())
	for i in range(gm.drones.size()):
		var d_id := drone_id(gm.drones[i])
		var d_star := drone_star(gm.drones[i])
		var def := WeaponData.get_def(d_id)
		list.append({
			"id": d_id, "name": def.get("name", "灵宝"),
			"star": d_star,
			"icon": def.get("icon", ""), "is_drone": true,
			"tag": def.get("tag", ""), "node": null, "drone_index": i,
		})
	return list

## 按上阵 summary 下标出售（悬浮法器与灵蝶统一处理）
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
		gm.announcement_triggered.emit("上阵已满 %d 件，先卸下一件法器" % gm.max_weapon_slots())
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

## 上阵 → 背包（summary 下标；背包有空位时）
static func unequip_to_stash(gm: Node, index: int) -> bool:
	var list := get_weapons_summary(gm)
	if index < 0 or index >= list.size():
		return false
	if gm.stash.size() >= WeaponData.MAX_STASH_SLOTS:
		gm.announcement_triggered.emit("背包已满，先出售一些法器")
		AudioManager.play_sfx("ui_error", 0.9)
		return false
	var item: Dictionary = list[index]
	if item.get("is_drone", false):
		var di := int(item.get("drone_index", -1))
		if di < 0 or di >= gm.drones.size():
			return false
		gm.drones.remove_at(di)
		if gm.player != null and gm.player.has_method("sync_drones"):
			gm.player.sync_drones()
	else:
		var node: Node = item.get("node")
		if node == null or not is_instance_valid(node):
			return false
		gm.player.remove_weapon_instance(node)
	var u_id: String = item.get("id", "")
	var u_def := WeaponData.get_def(u_id)
	gm.stash.append({
		"id": u_id,
		"name": item.get("name", u_def.get("name", "?")),
		"star": int(item.get("star", 1)),
		"icon": item.get("icon", u_def.get("icon", "")),
		"tag": item.get("tag", u_def.get("tag", "")),
	})
	gm.notify_weapons_updated(get_weapons_summary(gm))
	AudioManager.play_sfx("unequip", 1.0)
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
