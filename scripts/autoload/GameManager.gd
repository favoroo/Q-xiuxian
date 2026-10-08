extends Node

## 全局状态中枢：经济（灵石）、属性加点、武器持有与合成、波次推进、商店货架

@warning_ignore("unused_signal")
signal player_hp_changed(current_hp: float, max_hp: float)
signal player_exp_changed(current_exp: int, target_exp: int, level: int)
signal player_leveled_up(level: int)
signal stats_updated(kills: int, game_time: float, spirit_stones: int)
signal game_over_triggered(victory: bool)
signal upgrade_applied(upgrade_id: String)
signal announcement_triggered(text: String)
signal weapons_updated(weapons: Array)
@warning_ignore("unused_signal")
signal wave_changed(wave_number: int)
@warning_ignore("unused_signal")
signal shop_opened
signal shop_closed
signal screen_damage_pulsed(color: Color, duration: float)

enum FeedbackTier { SMALL, MEDIUM, LARGE, HEAVY }

const VICTORY_WAVE: int = 20
## 灵田可活动范围的半径（地图地砖 ±2400，超出边界的区域会被界碑拦下）
const MAP_HALF_EXTENT: float = 1150.0

## 属性上限（防数值失控）
const DODGE_CAP: float = 0.6          ## 身法闪避硬上限
const CRIT_RATE_CAP: float = 0.75     ## 暴击率软上限
const LIFESTEAL_MAX_PER_SEC: int = 3  ## 噬元每秒最多触发次数（防高频武器无限续航）
const HARVEST_GROWTH_WAVE_CAP: int = 16  ## 灵韵复利增长截止波次

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
var attack_range_mult: float = 1.0
var armor: float = 0.0
var hp_regen: float = 0.0
var crit_rate: float = 0.05
var crit_mult: float = 1.5
var dodge: float = 0.0        ## 身法：闪避概率（硬上限 DODGE_CAP）
var lifesteal: float = 0.0    ## 噬元：命中回复 1 点气血的概率
var luck: float = 0.0         ## 福缘：提升高稀有度悟道与商店亲和权重
var harvest: float = 0.0      ## 灵韵：每波结束无偿获得等额灵石+修为，并自我复利
var locked_upgrades: Array = []  ## 被角色负面代偿锁死的加点项 id（UpgradeData 过滤用）

# 修士流派（角色）特性
var cultivator_id: String = ""
var thorns_pct: float = 0.0        ## 石岳反震：按敌方攻击力比例反弹
var spirit_threshold_adj: int = 0  ## 符阵灵童：御灵羁绊门槛下移

# 武器羁绊加成（由 recalc_synergies 每波/换装时重算）
var bonus_pierce: int = 0           ## 符箓羁绊：弹丸额外穿透
var synergy_damage_mult: float = 1.0  ## 广域羁绊：额外伤害乘区
var synergy_range_mult: float = 1.0   ## 剑系羁绊：额外攻击范围乘区
var synergy_haste_mult: float = 1.0   ## 雷法羁绊：额外攻速乘区
var synergy_max_hp_bonus: float = 0.0 ## 御灵羁绊：额外气血上限

var _lifesteal_procs: int = 0
var _lifesteal_window: float = 0.0

# 商店
var shop_offers: Array = []
var reroll_cost: int = 2
var reroll_count: int = 0          ## 本波已重掷次数（费用递增，跨波重置）
var shop_price_mult: float = 1.0   ## 商店价格系数（角色特性用，如散修 8 折）
var shop_tag_filter: Array = []    ## 非空时武器货架只出这些 tag（剑痴等流派限定）
var _no_main_tag_waves: int = 0    ## 连续未刷出主流派法器的波数（保底计数）

# 武器库存：上阵 = 悬浮法器节点 + 灵蝶星级数组；背包 = 仅用于合成/出售的仓库
var drones: Array = []   # 上阵灵蝶的星级列表，如 [1, 2]
var stash: Array = []    # 背包，元素 {id: String, star: int}

# 本局历史悟道加点记录
var upgrade_history: Array[Dictionary] = []
var upgrade_counts: Dictionary = {}

func reset_run() -> void:
	Engine.time_scale = 1.0
	_hitstop_token += 1
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
	attack_range_mult = 1.0
	armor = 0.0
	hp_regen = 0.0
	crit_rate = 0.05
	crit_mult = 1.5
	dodge = 0.0
	lifesteal = 0.0
	luck = 0.0
	harvest = 0.0
	locked_upgrades = []
	cultivator_id = ""
	thorns_pct = 0.0
	spirit_threshold_adj = 0
	bonus_pierce = 0
	synergy_damage_mult = 1.0
	synergy_range_mult = 1.0
	synergy_haste_mult = 1.0
	synergy_max_hp_bonus = 0.0
	active_synergies = {}
	_applied_hp_bonus = 0.0
	_lifesteal_procs = 0
	_lifesteal_window = 0.0
	shop_offers = []
	reroll_cost = 2
	reroll_count = 0
	shop_price_mult = 1.0
	shop_tag_filter = []
	_no_main_tag_waves = 0
	drones = []
	stash = []
	upgrade_history.clear()
	upgrade_counts.clear()

func _process(delta: float) -> void:
	if not is_game_over and not get_tree().paused and player != null:
		game_time += delta
		_lifesteal_window += delta
		if _lifesteal_window >= 1.0:
			_lifesteal_window = 0.0
			_lifesteal_procs = 0
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
		"crit_up":
			crit_rate = minf(crit_rate + 0.08, CRIT_RATE_CAP)
		"critdmg_up":
			crit_mult += 0.25
		"dodge_up":
			dodge = minf(dodge + 0.07, DODGE_CAP)
		"lifesteal_up":
			lifesteal += 0.04
		"luck_up":
			luck += 6.0
		"harvest_up":
			harvest += 8.0
		"range_up":
			attack_range_mult += 0.12

	var prev_count: int = int(upgrade_counts.get(upgrade_id, 0)) + 1
	upgrade_counts[upgrade_id] = prev_count
	var def := UpgradeData.get_upgrade_def(upgrade_id)
	upgrade_history.append({
		"id": upgrade_id,
		"title": def.get("title", upgrade_id),
		"rarity": def.get("rarity", "common"),
		"rarity_label": def.get("rarity_label", "凡品"),
		"icon": def.get("icon", ""),
		"desc": def.get("desc", ""),
		"border_color": def.get("border_color", Color.WHITE),
		"level": level,
		"time": game_time,
		"count": prev_count,
	})
	upgrade_applied.emit(upgrade_id)

func get_stat_breakdown() -> Dictionary:
	var cur_hp: float = 120.0
	var max_hp: float = 120.0
	var base_spd: float = 210.0
	if player != null and is_instance_valid(player):
		cur_hp = float(player.current_health)
		max_hp = float(player.max_health)
		base_spd = float(player.base_speed)
	var dmg_reduction: float = 1.0 - (1.0 / (1.0 + armor * 0.08))
	var cdr_pct: float = (1.0 - attack_speed_mult) * 100.0
	return {
		"current_hp": cur_hp,
		"max_hp": max_hp,
		"hp_regen": hp_regen,
		"armor": armor,
		"dmg_reduction_pct": dmg_reduction * 100.0,
		"damage_mult": weapon_damage_mult,
		"damage_bonus_pct": (weapon_damage_mult - 1.0) * 100.0,
		"attack_speed_mult": attack_speed_mult,
		"cdr_pct": cdr_pct,
		"move_speed": base_spd * move_speed_mult,
		"move_speed_bonus_pct": (move_speed_mult - 1.0) * 100.0,
		"pickup_radius": 96.0 * pickup_range_mult,
		"pickup_bonus_pct": (pickup_range_mult - 1.0) * 100.0,
		"attack_range_pct": (attack_range_mult - 1.0) * 100.0,
		"crit_rate_pct": get_crit_rate() * 100.0,
		"crit_dmg_pct": crit_mult * 100.0,
		"dodge_pct": get_effective_dodge() * 100.0,
		"lifesteal_pct": lifesteal * 100.0,
		"luck": luck,
		"harvest": harvest,
	}

func get_crit_rate() -> float:
	return minf(crit_rate, CRIT_RATE_CAP)

func get_effective_dodge() -> float:
	return minf(dodge, DODGE_CAP)

## 命中时尝试噬元回血（每秒最多触发 LIFESTEAL_MAX_PER_SEC 次，防高频武器无限续航）
func try_lifesteal() -> void:
	if lifesteal <= 0.0 or player == null or not is_instance_valid(player):
		return
	if _lifesteal_procs >= LIFESTEAL_MAX_PER_SEC:
		return
	if randf() < lifesteal:
		_lifesteal_procs += 1
		player.heal(1.0, true)

## 波间灵韵结算：无偿发放等额灵石+修为，随后灵韵自我复利（第 16 波起停止增长）
func apply_harvest() -> void:
	var gain := int(round(harvest))
	if gain > 0:
		add_experience(gain)
		announcement_triggered.emit("✦ 灵韵滋养 · 灵石与修为 +%d ✦" % gain)
	if wave_number < HARVEST_GROWTH_WAVE_CAP:
		harvest *= 1.05

# ---------------- 武器系统 ----------------

func start_run(starter_id: String) -> void:
	run_started = true
	_apply_cultivator()
	add_weapon(starter_id)
	announcement_triggered.emit("✦ 灵田巡守 · 斩妖护山 ✦")

## 开局应用修士流派的正负代偿
func _apply_cultivator() -> void:
	var def := CultivatorData.get_def(cultivator_id)
	if def.is_empty():
		return
	var mods: Dictionary = def.get("mods", {})
	crit_rate += float(mods.get("crit_rate", 0.0))
	armor += float(mods.get("armor", 0.0))
	harvest += float(mods.get("harvest", 0.0))
	move_speed_mult *= float(mods.get("speed_mult", 1.0))
	weapon_damage_mult *= float(mods.get("damage_mult", 1.0))
	thorns_pct = float(mods.get("thorns", 0.0))
	shop_price_mult = float(mods.get("shop_price", 1.0))
	spirit_threshold_adj = int(mods.get("spirit_threshold_adj", 0))
	shop_tag_filter = def.get("allowed_tags", [])
	locked_upgrades = def.get("locked_upgrades", [])
	if player != null and is_instance_valid(player):
		var hp_mult := float(mods.get("hp_mult", 1.0))
		if hp_mult != 1.0:
			player.max_health *= hp_mult
			player.current_health = player.max_health
			player_hp_changed.emit(player.current_health, player.max_health)
	var start_drones := int(mods.get("start_drones", 0))
	for i in range(start_drones):
		drones.append(1)
	if start_drones > 0 and player != null and player.has_method("sync_drones"):
		player.sync_drones()

## 修士特性的单武器伤害系数（tag 加成 × 非灵蝶惩罚）
func cultivator_damage_mult(w_id: String) -> float:
	var def := CultivatorData.get_def(cultivator_id)
	if def.is_empty():
		return 1.0
	var mods: Dictionary = def.get("mods", {})
	var m := 1.0
	var tag_bonuses: Dictionary = mods.get("tag_damage", {})
	for t in WeaponData.tags_of(w_id):
		m *= 1.0 + float(tag_bonuses.get(t, 0.0))
	var wdef := WeaponData.get_def(w_id)
	if int(wdef.get("behavior", -1)) != WeaponData.Behavior.DRONE:
		m *= 1.0 + float(mods.get("non_drone_damage", 0.0))
	return m

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
		stash.append({
			"id": w_id,
			"name": def.get("name", "?"),
			"star": star,
			"icon": def.get("icon", ""),
			"tag": def.get("tag", ""),
		})
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
			var k_def := WeaponData.get_def(w_id)
			new_stash.append({
				"id": w_id,
				"name": k_def.get("name", "?"),
				"star": star + 1,
				"icon": k_def.get("icon", ""),
				"tag": k_def.get("tag", ""),
			})
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
	recalc_synergies()
	weapons_updated.emit(weapons)

# ---------------- 流派羁绊 ----------------

## 当前激活的羁绊：{tag: {"count": int, "level": int}}，level 0 = 未激活
var active_synergies: Dictionary = {}

var _applied_hp_bonus: float = 0.0  ## 御灵羁绊已应用到玩家的气血上限增量

## 按上阵法器（含灵蝶）重算羁绊加成；换装/合成/出售后由 notify_weapons_updated 统一触发
func recalc_synergies() -> void:
	var counts := _tag_counts()
	active_synergies.clear()
	bonus_pierce = 0
	synergy_damage_mult = 1.0
	synergy_range_mult = 1.0
	synergy_haste_mult = 1.0
	var hp_bonus: float = 0.0
	for tag in counts.keys():
		var info: Dictionary = WeaponData.SYNERGIES.get(tag, {})
		if info.is_empty():
			continue
		var n := int(counts[tag])
		var syn_level := 0
		var thresholds: Array = info.get("thresholds", [])
		for i in range(thresholds.size()):
			var th := int(thresholds[i])
			if tag == "spirit":
				th = maxi(1, th - spirit_threshold_adj)
			if n >= th:
				syn_level = i + 1
		active_synergies[tag] = {"count": n, "level": syn_level}
		if syn_level == 0:
			continue
		var v = info["values"][syn_level - 1]
		match tag:
			"sword":
				synergy_range_mult += float(v)
			"talisman":
				bonus_pierce += int(v)
			"thunder":
				synergy_haste_mult *= float(v)
			"spirit":
				hp_bonus += float(v)
			"wide":
				synergy_damage_mult += float(v)
	synergy_max_hp_bonus = hp_bonus
	_apply_synergy_hp(hp_bonus)

## 御灵羁绊直接增减气血上限（差值法，避免叠加误差）
func _apply_synergy_hp(new_bonus: float) -> void:
	var delta := new_bonus - _applied_hp_bonus
	_applied_hp_bonus = new_bonus
	if player != null and is_instance_valid(player) and delta != 0.0:
		player.max_health += delta
		player.current_health = clampf(player.current_health, 0.0, player.max_health)
		player_hp_changed.emit(player.current_health, player.max_health)

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
	var u_id: String = item.get("id", "")
	var u_def := WeaponData.get_def(u_id)
	stash.append({
		"id": u_id,
		"name": item.get("name", u_def.get("name", "?")),
		"star": int(item.get("star", 1)),
		"icon": item.get("icon", u_def.get("icon", "")),
		"tag": item.get("tag", u_def.get("tag", "")),
	})
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

## 生成货架：new_wave=true 时重置重掷计数；锁定且未售出的商品原样保留
func roll_shop(new_wave: bool = false) -> void:
	if new_wave:
		reroll_count = 0
	var wave := maxi(wave_number, 1)
	var old := shop_offers
	var new_offers: Array = []
	for i in range(4):
		if i < old.size() and old[i].get("locked", false) and not old[i].get("sold", false):
			new_offers.append(old[i])
		else:
			new_offers.append(_gen_offer(wave))
	shop_offers = new_offers
	reroll_cost = int((2 + wave + reroll_count * 2) * shop_price_mult)
	if new_wave:
		_apply_main_tag_pity(wave)

## 单个货架位：22% 回气丹，否则按标签亲和权重抽法器
func _gen_offer(wave: int) -> Dictionary:
	if randf() < 0.22:
		return {
			"kind": "potion", "id": WeaponData.POTION_ID,
			"price": int((WeaponData.POTION_BASE_PRICE + wave) * shop_price_mult),
			"sold": false, "locked": false,
		}
	var w_id := _weighted_weapon_pick()
	var base := int(WeaponData.get_def(w_id).get("price", 20))
	return {
		"kind": "weapon", "id": w_id,
		"price": int((base + (wave - 1) * 2) * shop_price_mult),
		"sold": false, "locked": false,
	}

## 标签亲和加权抽法器：持有 ≥2 件同 tag 法器时该 tag 权重 ×2.5；福缘每点 +1% 权重
func _weighted_weapon_pick() -> String:
	var pool: Array = WeaponData.SHOP_POOL
	if not shop_tag_filter.is_empty():
		var filtered: Array = []
		for w_id in pool:
			for t in WeaponData.tags_of(w_id):
				if t in shop_tag_filter:
					filtered.append(w_id)
					break
		if not filtered.is_empty():
			pool = filtered
	var counts := _tag_counts()
	var total := 0.0
	var weights: Array = []
	for w_id in pool:
		var w := 1.0
		for t in WeaponData.tags_of(w_id):
			if int(counts.get(t, 0)) >= 2:
				w *= 2.5
		w *= 1.0 + luck * 0.01
		weights.append(w)
		total += w
	var r := randf() * total
	for i in range(pool.size()):
		r -= weights[i]
		if r <= 0.0:
			return pool[i]
	return pool.back()

## 上阵法器（含灵蝶）的 tag 计数——构筑方向判定的依据
func _tag_counts() -> Dictionary:
	var counts: Dictionary = {}
	if player != null and player.has_method("get_equipped_weapons_data"):
		for w in player.get_equipped_weapons_data():
			for t in WeaponData.tags_of(w.get("id", "")):
				counts[t] = int(counts.get(t, 0)) + 1
	for _s in drones:
		for t in WeaponData.tags_of("lingdie"):
			counts[t] = int(counts.get(t, 0)) + 1
	return counts

func get_tag_count(tag: String) -> int:
	return int(_tag_counts().get(tag, 0))

## 主流派：当前持有数最多且 ≥2 件的 tag
func _main_tag() -> String:
	var counts := _tag_counts()
	var best_tag := ""
	var best_n := 1
	for t in counts.keys():
		if int(counts[t]) > best_n:
			best_n = int(counts[t])
			best_tag = t
	return best_tag

## 保底：连续 2 波货架没出现主流派法器时，第 3 波强制塞入一件
func _apply_main_tag_pity(wave: int) -> void:
	var main := _main_tag()
	if main == "":
		_no_main_tag_waves = 0
		return
	var has_main := false
	for offer in shop_offers:
		if offer.get("kind") == "weapon" and main in WeaponData.tags_of(offer.get("id", "")):
			has_main = true
			break
	if has_main:
		_no_main_tag_waves = 0
		return
	_no_main_tag_waves += 1
	if _no_main_tag_waves < 2:
		return
	# 找一个未锁定的法器位替换
	var candidates: Array = []
	for w_id in WeaponData.SHOP_POOL:
		if main in WeaponData.tags_of(w_id):
			candidates.append(w_id)
	if candidates.is_empty():
		return
	for i in range(shop_offers.size()):
		var offer: Dictionary = shop_offers[i]
		if offer.get("locked", false) or offer.get("sold", false):
			continue
		if offer.get("kind") != "weapon":
			continue
		var w_id: String = candidates.pick_random()
		var base := int(WeaponData.get_def(w_id).get("price", 20))
		shop_offers[i] = {
			"kind": "weapon", "id": w_id,
			"price": int((base + (wave - 1) * 2) * shop_price_mult),
			"sold": false, "locked": false,
		}
		break
	_no_main_tag_waves = 0

func toggle_lock(index: int) -> void:
	if index < 0 or index >= shop_offers.size():
		return
	var offer: Dictionary = shop_offers[index]
	if offer.get("sold", false):
		return
	offer["locked"] = not offer.get("locked", false)
	AudioManager.play_sfx("orb_hit", 0.7)

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
	reroll_count += 1
	roll_shop(false)
	stats_updated.emit(kills, game_time, spirit_stones)
	AudioManager.play_sfx("orb_hit", 0.9)
	return true

func confirm_shop() -> void:
	get_tree().paused = false
	shop_closed.emit()

# ---------------- 流程与打击感系统 ----------------

var _hitstop_token: int = 0

## 创伤度叠加震屏
func add_trauma(amount: float) -> void:
	if main_camera != null and is_instance_valid(main_camera) and main_camera.has_method("add_trauma"):
		main_camera.add_trauma(amount)

## 镜头缩放冲击
func zoom_punch(scale_amount: float = 0.05, duration: float = 0.18) -> void:
	if main_camera != null and is_instance_valid(main_camera) and main_camera.has_method("zoom_punch"):
		main_camera.zoom_punch(scale_amount, duration)

func shake_camera(intensity: float = 3.5, duration: float = 0.12) -> void:
	if main_camera != null and is_instance_valid(main_camera) and main_camera.has_method("shake"):
		main_camera.shake(intensity, duration)

## 真实时间顿帧（Hit-Stop / Freeze Frame），不受 Engine.time_scale 影响
func hit_stop(duration: float = 0.045, target_scale: float = 0.05) -> void:
	_hitstop_token += 1
	var token := _hitstop_token
	Engine.time_scale = target_scale
	get_tree().create_timer(duration, true, false, true).timeout.connect(func():
		if _hitstop_token == token:
			Engine.time_scale = 1.0
	)

## 兼容旧调用
func trigger_hitstop(duration: float = 0.045) -> void:
	hit_stop(duration)

## game-feel 重要性分级反馈聚合接口（包含相机创伤、顿帧与镜头冲击）
func feedback(tier: int) -> void:
	match tier:
		FeedbackTier.SMALL:
			add_trauma(0.08)
		FeedbackTier.MEDIUM:
			add_trauma(0.18)
			hit_stop(0.035, 0.08)
		FeedbackTier.LARGE:
			add_trauma(0.38)
			hit_stop(0.065, 0.04)
			zoom_punch(0.035, 0.15)
		FeedbackTier.HEAVY:
			add_trauma(0.70)
			hit_stop(0.09, 0.02)
			zoom_punch(0.06, 0.22)

## 触发全屏受击红晕脉冲
func pulse_damage_vignette(color: Color = Color(0.85, 0.12, 0.12, 0.65), duration: float = 0.22) -> void:
	screen_damage_pulsed.emit(color, duration)

func trigger_game_over(victory: bool = false) -> void:
	if is_game_over:
		return
	Engine.time_scale = 1.0
	_hitstop_token += 1
	is_game_over = true
	game_over_triggered.emit(victory)

## 结算界面「继续无尽」：关闭结算并转入下一波商店
func continue_endless() -> void:
	endless_mode = true
	is_game_over = false
	get_tree().paused = false
	if wave_spawner != null and wave_spawner.has_method("open_shop"):
		wave_spawner.open_shop()
