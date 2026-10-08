extends Node

## 全局状态中枢：经济（灵石）、属性加点、武器持有与合成、波次推进、商店货架

signal player_hp_changed(current_hp: float, max_hp: float)
signal player_exp_changed(current_exp: int, target_exp: int, level: int)
signal player_leveled_up(level: int)
signal stats_updated(kills: int, game_time: float, spirit_stones: int)
signal game_over_triggered(victory: bool)
signal upgrade_applied(upgrade_id: String)
signal announcement_triggered(text: String)
signal weapons_updated(weapons: Array)
signal wave_changed(wave_number: int)
signal shop_opened
signal shop_closed

const VICTORY_WAVE: int = 10
## 灵田可活动范围的半径（地图地砖 ±2400，超出边界的区域会被界碑拦下）
const MAP_HALF_EXTENT: float = 1150.0

var player: Node2D = null
var joystick = null
var main_camera: Camera2D = null
var wave_spawner: Node = null

var kills: int = 0
var game_time: float = 0.0
var spirit_stones: int = 0
var level: int = 1
var experience: int = 0
var experience_to_next: int = 10
var is_game_over: bool = false

# 波次
var wave_number: int = 0
var endless_mode: bool = false
var run_started: bool = false

# 玩家属性（加点系统）
var weapon_damage_mult: float = 1.0
var attack_speed_mult: float = 1.0
var move_speed_mult: float = 1.0
var pickup_range_mult: float = 1.0
var armor: float = 0.0
var hp_regen: float = 0.0

# 商店
var shop_offers: Array = []
var reroll_cost: int = 2

# 武器库存：上阵 = 悬浮法器节点 + 灵蝶星级数组；背包 = 仅用于合成/出售的仓库
var drones: Array = []   # 上阵灵蝶的星级列表，如 [1, 2]
var stash: Array = []    # 背包，元素 {id: String, star: int}

func reset_run() -> void:
	kills = 0
	game_time = 0.0
	spirit_stones = 0
	level = 1
	experience = 0
	experience_to_next = 10
	is_game_over = false
	wave_number = 0
	endless_mode = false
	run_started = false
	weapon_damage_mult = 1.0
	attack_speed_mult = 1.0
	move_speed_mult = 1.0
	pickup_range_mult = 1.0
	armor = 0.0
	hp_regen = 0.0
	shop_offers = []
	reroll_cost = 2
	drones = []
	stash = []

func _process(delta: float) -> void:
	if not is_game_over and not get_tree().paused and player != null:
		game_time += delta
		stats_updated.emit(kills, game_time, spirit_stones)

# ---------------- 经验 / 灵石 ----------------

func add_experience(amount: int) -> void:
	if is_game_over:
		return
	experience += amount
	spirit_stones += amount
	AudioManager.play_sfx("gem_pickup")

	while experience >= experience_to_next:
		experience -= experience_to_next
		level += 1
		experience_to_next = int(experience_to_next * 1.35) + 5
		AudioManager.play_sfx("level_up")
		player_leveled_up.emit(level)

	player_exp_changed.emit(experience, experience_to_next, level)
	stats_updated.emit(kills, game_time, spirit_stones)

func add_spirit_stones(amount: int) -> void:
	spirit_stones += amount
	stats_updated.emit(kills, game_time, spirit_stones)

func register_kill(is_elite: bool = false) -> void:
	kills += 1
	if is_elite:
		spirit_stones += 25
	stats_updated.emit(kills, game_time, spirit_stones)

# ---------------- 属性加点 ----------------

func apply_upgrade(upgrade_id: String) -> void:
	match upgrade_id:
		"atk_up":
			weapon_damage_mult += 0.15
		"haste_up":
			attack_speed_mult = maxf(0.3, attack_speed_mult * 0.88)
		"armor_up":
			armor += 2.0
		"speed_up":
			move_speed_mult += 0.08
		"hp_up":
			if player and player.has_method("increase_max_hp"):
				player.increase_max_hp(25.0, 30.0)
		"pickup_up":
			pickup_range_mult += 0.4
		"coins_up":
			spirit_stones += 12
		"regen_up":
			hp_regen += 1.2
	upgrade_applied.emit(upgrade_id)

# ---------------- 武器系统 ----------------

func start_run(starter_id: String) -> void:
	run_started = true
	add_weapon(starter_id)
	announcement_triggered.emit("✦ 灵田巡守 · 斩妖护山 ✦")

func slots_used() -> int:
	var used := drones.size()
	if player != null and player.has_method("get_weapon_count"):
		used += player.get_weapon_count()
	return used

## 获得一件法器：上阵栏位有空则上阵，否则进背包；两处都满返回 false
func add_weapon(w_id: String, star: int = 1) -> bool:
	var def := WeaponData.get_def(w_id)
	if def.is_empty():
		return false
	if slots_used() < WeaponData.MAX_SLOTS:
		if def.get("behavior", -1) == WeaponData.Behavior.DRONE:
			drones.append(star)
			if player != null and player.has_method("sync_drones"):
				player.sync_drones()
		else:
			if player == null or not player.has_method("add_weapon_instance"):
				return false
			player.add_weapon_instance(w_id, star)
	else:
		if stash.size() >= WeaponData.MAX_STASH_SLOTS:
			return false
		stash.append({"id": w_id, "star": star})
	notify_weapons_updated(get_weapons_summary())
	return true

## (id, star) 的持有总数：上阵悬浮法器 + 灵蝶 + 背包
func count_copies(w_id: String, star: int) -> int:
	var n := 0
	if player != null and player.has_method("get_equipped_weapons_data"):
		for w in player.get_equipped_weapons_data():
			if w.get("id", "") == w_id and int(w.get("star", 1)) == star:
				n += 1
	if w_id == "lingdie":
		for s in drones:
			if int(s) == star:
				n += 1
	for e in stash:
		if e.get("id", "") == w_id and int(e.get("star", 1)) == star:
			n += 1
	return n

## 手动合成：keep 指定保留哪一件（pool: "equipped"/"drone"/"stash"，index 为对应池下标），
## 该件升 1 星，其余 2 件同名同星被消耗（背包 → 灵蝶 → 上阵 的顺序回收）
func merge_weapon(w_id: String, star: int, keep: Dictionary) -> bool:
	if star >= WeaponData.MAX_STAR:
		return false
	if count_copies(w_id, star) < 3:
		return false
	var need := 2

	# 1. 消耗背包副本（保留 keeper）
	var new_stash: Array = []
	for j in range(stash.size()):
		var is_keeper: bool = keep.get("pool", "") == "stash" and int(keep.get("index", -1)) == j
		if not is_keeper and stash[j].get("id", "") == w_id and int(stash[j].get("star", 1)) == star and need > 0:
			need -= 1
			continue
		if is_keeper:
			new_stash.append({"id": w_id, "star": star + 1})
		else:
			new_stash.append(stash[j])
	stash = new_stash

	# 2. 消耗上阵灵蝶（重建数组并升级 keeper）
	if w_id == "lingdie":
		var new_drones: Array = []
		for j in range(drones.size()):
			var is_keeper_d: bool = keep.get("pool", "") == "drone" and int(keep.get("index", -1)) == j
			if not is_keeper_d and int(drones[j]) == star and need > 0:
				need -= 1
				continue
			new_drones.append(star + 1 if is_keeper_d else int(drones[j]))
		drones = new_drones
		if player != null and player.has_method("sync_drones"):
			player.sync_drones()

	# 3. 消耗上阵悬浮法器（按节点引用移除，keeper 原地升级）
	var keeper_node: Node = null
	if player != null and player.has_method("get_equipped_weapons_data"):
		var equipped: Array = player.get_equipped_weapons_data()
		if keep.get("pool", "") == "equipped" and int(keep.get("index", -1)) >= 0 and int(keep.get("index", -1)) < equipped.size():
			keeper_node = equipped[int(keep.get("index", -1))].get("node")
		for j in range(equipped.size() - 1, -1, -1):
			if need <= 0:
				break
			var w: Dictionary = equipped[j]
			if w.get("node") == keeper_node:
				continue
			if w.get("id", "") == w_id and int(w.get("star", 1)) == star:
				player.remove_weapon_instance(w.get("node"))
				need -= 1

	if need > 0:
		push_warning("merge_weapon: 副本数量不足，状态已部分变更")
		notify_weapons_updated(get_weapons_summary())
		return false

	# 4. 升级保留件
	if keeper_node != null and is_instance_valid(keeper_node) and player.has_method("upgrade_weapon_instance"):
		player.upgrade_weapon_instance(keeper_node, star + 1)

	announcement_triggered.emit("✦ 三器合一 · %s ✦" % WeaponData.full_name(w_id, star + 1))
	AudioManager.play_sfx("level_up", 1.0)
	notify_weapons_updated(get_weapons_summary())
	return true

## HUD/商店通用的上阵列表（悬浮法器在前，灵蝶在后）
func get_weapons_summary() -> Array:
	var list: Array = []
	if player != null and player.has_method("get_equipped_weapons_data"):
		list.append_array(player.get_equipped_weapons_data())
	for i in range(drones.size()):
		var def := WeaponData.get_def("lingdie")
		list.append({
			"id": "lingdie", "name": def.get("name", "灵蝶"),
			"star": int(drones[i]),
			"icon": def.get("icon", ""), "is_drone": true,
			"tag": def.get("tag", ""), "node": null, "drone_index": i,
		})
	return list

func notify_weapons_updated(weapons: Array) -> void:
	weapons_updated.emit(weapons)

## 按上阵 summary 下标出售（悬浮法器与灵蝶统一处理）
func sell_weapon(index: int) -> bool:
	var list := get_weapons_summary()
	if index < 0 or index >= list.size():
		return false
	var item: Dictionary = list[index]
	var price: int = 0
	if item.get("is_drone", false):
		var di := int(item.get("drone_index", -1))
		if di < 0 or di >= drones.size():
			return false
		price = WeaponData.sell_price("lingdie", int(drones[di]))
		drones.remove_at(di)
		if player != null and player.has_method("sync_drones"):
			player.sync_drones()
	else:
		var node: Node = item.get("node")
		if node == null or not is_instance_valid(node):
			return false
		price = WeaponData.sell_price(item.get("id", ""), item.get("star", 1))
		player.remove_weapon_instance(node)
	spirit_stones += price
	stats_updated.emit(kills, game_time, spirit_stones)
	notify_weapons_updated(get_weapons_summary())
	AudioManager.play_sfx("gem_pickup", 0.9)
	return true

## 背包 → 上阵（上阵栏位有空位时）
func equip_from_stash(index: int) -> bool:
	if index < 0 or index >= stash.size():
		return false
	if slots_used() >= WeaponData.MAX_SLOTS:
		announcement_triggered.emit("上阵已满 6 件，先卸下一件法器")
		return false
	var entry: Dictionary = stash[index]
	stash.remove_at(index)
	if entry.get("id", "") == "lingdie":
		drones.append(int(entry.get("star", 1)))
		if player != null and player.has_method("sync_drones"):
			player.sync_drones()
	else:
		player.add_weapon_instance(entry.get("id", ""), int(entry.get("star", 1)))
	notify_weapons_updated(get_weapons_summary())
	AudioManager.play_sfx("powerUp2", 0.8)
	return true

## 上阵 → 背包（summary 下标；背包有空位时）
func unequip_to_stash(index: int) -> bool:
	var list := get_weapons_summary()
	if index < 0 or index >= list.size():
		return false
	if stash.size() >= WeaponData.MAX_STASH_SLOTS:
		announcement_triggered.emit("背包已满，先出售一些法器")
		return false
	var item: Dictionary = list[index]
	if item.get("is_drone", false):
		var di := int(item.get("drone_index", -1))
		if di < 0 or di >= drones.size():
			return false
		drones.remove_at(di)
		if player != null and player.has_method("sync_drones"):
			player.sync_drones()
	else:
		var node: Node = item.get("node")
		if node == null or not is_instance_valid(node):
			return false
		player.remove_weapon_instance(node)
	stash.append({"id": item.get("id", ""), "star": int(item.get("star", 1))})
	notify_weapons_updated(get_weapons_summary())
	AudioManager.play_sfx("orb_hit", 0.8)
	return true

## 按背包下标出售
func sell_stash(index: int) -> bool:
	if index < 0 or index >= stash.size():
		return false
	var entry: Dictionary = stash[index]
	var price := WeaponData.sell_price(entry.get("id", ""), int(entry.get("star", 1)))
	stash.remove_at(index)
	spirit_stones += price
	stats_updated.emit(kills, game_time, spirit_stones)
	notify_weapons_updated(get_weapons_summary())
	AudioManager.play_sfx("gem_pickup", 0.9)
	return true

# ---------------- 波间商店 ----------------

func roll_shop() -> void:
	shop_offers.clear()
	var wave := maxi(wave_number, 1)
	for i in range(4):
		if randf() < 0.22:
			shop_offers.append({
				"kind": "potion", "id": WeaponData.POTION_ID,
				"price": WeaponData.POTION_BASE_PRICE + wave, "sold": false,
			})
		else:
			var w_id: String = WeaponData.SHOP_POOL.pick_random()
			shop_offers.append({
				"kind": "weapon", "id": w_id,
				"price": int(WeaponData.get_def(w_id).get("price", 20)) + (wave - 1) * 2,
				"sold": false,
			})
	reroll_cost = 2 + wave

func buy_offer(index: int) -> bool:
	if index < 0 or index >= shop_offers.size():
		return false
	var offer: Dictionary = shop_offers[index]
	if offer.get("sold", false) or spirit_stones < int(offer.get("price", 0)):
		return false
	var ok := false
	if offer.get("kind") == "potion":
		if player != null and player.has_method("heal"):
			player.heal(player.max_health * 0.5)
			ok = true
	else:
		ok = add_weapon(offer.get("id", ""))
		if not ok:
			announcement_triggered.emit("上阵与背包都满了，先出售一些吧")
			return false
	if not ok:
		return false
	spirit_stones -= int(offer.get("price", 0))
	offer["sold"] = true
	stats_updated.emit(kills, game_time, spirit_stones)
	AudioManager.play_sfx("gem_pickup", 1.1)
	return true

func reroll_shop() -> bool:
	if spirit_stones < reroll_cost:
		return false
	spirit_stones -= reroll_cost
	roll_shop()
	stats_updated.emit(kills, game_time, spirit_stones)
	AudioManager.play_sfx("orb_hit", 0.9)
	return true

func confirm_shop() -> void:
	get_tree().paused = false
	shop_closed.emit()

# ---------------- 流程 ----------------

func shake_camera(intensity: float = 3.5, duration: float = 0.12) -> void:
	if main_camera and main_camera.has_method("shake"):
		main_camera.shake(intensity, duration)

func trigger_hitstop(duration: float = 0.025) -> void:
	Engine.time_scale = 0.15
	get_tree().create_timer(duration * 0.15, true, false, true).timeout.connect(
		func(): Engine.time_scale = 1.0
	)

func trigger_game_over(victory: bool = false) -> void:
	if is_game_over:
		return
	is_game_over = true
	game_over_triggered.emit(victory)

## 结算界面「继续无尽」：关闭结算并转入下一波商店
func continue_endless() -> void:
	endless_mode = true
	is_game_over = false
	get_tree().paused = false
	if wave_spawner != null and wave_spawner.has_method("open_shop"):
		wave_spawner.open_shop()
