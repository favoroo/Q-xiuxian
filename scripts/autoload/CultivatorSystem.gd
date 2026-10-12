class_name CultivatorSystem
extends RefCounted

## 修士流派（角色）特性子系统（2026-10-11 从 GameManager._apply_cultivator 抽离）：
## 开局应用正负代偿 mods，以及流派化的单武器伤害系数。

## 开局应用修士流派的正负代偿
static func apply_cultivator(gm: Node) -> void:
	var def := CultivatorData.get_def(gm.cultivator_id)
	if def.is_empty():
		return
	var mods: Dictionary = def.get("mods", {})
	gm.crit_rate += float(mods.get("crit_rate", 0.0))
	gm.armor += float(mods.get("armor", 0.0))
	gm.harvest += float(mods.get("harvest", 0.0))
	gm.dodge += float(mods.get("dodge", 0.0))
	gm.dodge_cap_bonus = float(mods.get("dodge_cap", 0.0))
	gm.move_speed_mult *= float(mods.get("speed_mult", 1.0))
	gm.weapon_damage_mult *= float(mods.get("damage_mult", 1.0))
	gm.attack_speed_mult = maxf(gm.ATTACK_SPEED_FLOOR, gm.attack_speed_mult * float(mods.get("haste_mult", 1.0)))
	gm.thorns_pct = float(mods.get("thorns", 0.0))
	gm.shop_price_mult = float(mods.get("shop_price", 1.0))
	gm.spirit_threshold_adj = int(mods.get("spirit_threshold_adj", 0))
	gm.contraption_threshold_adj = int(mods.get("contraption_threshold_adj", 0))
	gm.stone_interest_rate = float(mods.get("stone_interest_rate", 0.0))
	gm.stone_interest_cap = int(mods.get("stone_interest_cap", 15))
	gm.on_hit_damage_bonus = float(mods.get("on_hit_damage_bonus", 0.0))
	gm.on_hit_damage_cap_stacks = int(mods.get("on_hit_damage_cap_stacks", 10))
	gm.elemental_damage += float(mods.get("elemental", 0.0))
	gm.engineering_damage += float(mods.get("engineering", 0.0))
	gm.contraption_damage += float(mods.get("contraption", 0.0))
	gm.hp_regen += float(mods.get("hp_regen", 0.0))
	gm.weapon_slots_override = int(mods.get("weapon_slots_max", 0))
	gm.enemy_count_mult = float(mods.get("enemy_count_mult", 1.0))
	gm.harvest_decay = float(mods.get("harvest_decay", 0.0))
	gm.xp_require_mult = float(mods.get("xp_require_mult", 1.0))
	gm.item_price_mult = float(mods.get("item_price", 1.0))
	gm.shop_slots_bonus = int(mods.get("shop_slots", 0))
	gm.guard_stance = float(mods.get("guard_stance", 0.0))
	gm.heal_orb_chance = float(mods.get("heal_orb_chance", 0.0))
	gm.heal_overflow_mult = float(mods.get("heal_overflow_mult", 1.0))
	gm.alloc_offer_bonus = int(mods.get("alloc_offer_bonus", 0))
	gm.alloc_free_reroll_bonus = int(mods.get("alloc_free_reroll_bonus", 0))
	gm.collection_damage_per_unique = float(mods.get("collection_damage_per_unique", 0.0))
	gm.frenzy_enabled = float(mods.get("frenzy", 0.0))
	gm.free_rerolls += int(mods.get("free_rerolls", 0))
	gm.reroll_price_mult = float(mods.get("reroll_price", 1.0))
	gm.thunder_strike = float(mods.get("thunder_strike", 0.0))
	gm.crowd_damage_per_enemy = float(mods.get("crowd_damage_per_enemy", 0.0))
	gm.crowd_damage_cap = float(mods.get("crowd_damage_cap", 0.0))
	gm.crowd_damage_radius = float(mods.get("crowd_damage_radius", 0.0))
	gm.stone_damage_per_100 = float(mods.get("stone_damage_per_100", 0.0))
	gm.stone_damage_cap = float(mods.get("stone_damage_cap", 0.0))
	gm.kill_cd_reduction_normal = float(mods.get("kill_cd_reduction_normal", 0.0))
	gm.kill_cd_reduction_elite = float(mods.get("kill_cd_reduction_elite", 0.0))
	gm.pet_slots_bonus += int(mods.get("pet_slots", 0))
	gm.pet_offer_chance_bonus = float(mods.get("pet_offer_chance_bonus", 0.0))
	gm.pet_damage_mult += float(mods.get("pet_damage_mult", 0.0))
	var start_pet: String = String(mods.get("start_pet", ""))
	if not start_pet.is_empty():
		gm.add_pet(start_pet)
	# 需求倍率只折算判定值，修为门槛链保持原曲线（避免倍率逐层复利）
	gm.experience_to_next = maxi(1, int(round(float(gm._exp_chain) * gm.xp_require_mult)))
	gm.shop_tag_filter = def.get("allowed_tags", [])
	gm.locked_upgrades = def.get("locked_upgrades", [])
	if gm.player != null and is_instance_valid(gm.player):
		if gm.player.has_method("_setup_sprite_frames"):
			gm.player._setup_sprite_frames()
		var hp_mult := float(mods.get("hp_mult", 1.0))
		if hp_mult != 1.0:
			gm.player.max_health *= hp_mult
			gm.player.current_health = gm.player.max_health
			gm.player_hp_changed.emit(gm.player.current_health, gm.player.max_health)
	var start_drones := int(mods.get("start_drones", 0))
	var start_drone_star := maxi(1, int(mods.get("start_drone_star", 1)))
	for i in range(start_drones):
		# 开局灵蝶支持指定星级（驯兽师 ★2 双生蝶）：统一走字典条目，_drone_id/_drone_star 都认
		gm.drones.append({"id": "lingdie", "star": start_drone_star})
	if start_drones > 0 and gm.player != null and gm.player.has_method("sync_drones"):
		gm.player.sync_drones()

## 修士特性的单武器伤害系数（tag 加成 × 非灵蝶/非机关惩罚 + 受击增伤）
static func damage_mult(gm: Node, w_id: String) -> float:
	var m := 1.0
	# ---- 法宝·属性转化乘区（2026-10-12 土豆兄弟式转化件：系数全在 ItemData 额外字段，
	# item_hook_sum 现算；与角色无关，无角色时同样生效，所以必须在 def 早退之前结算） ----
	var cvt_speed: float = gm.item_hook_sum("dmg_per_move_speed")
	if cvt_speed > 0.0:
		# 疾风刃：移速每超基础 10% 折算一份（移速 = 加点乘区 + 玄水羁绊，同一根轴）
		var speed_excess: float = gm.move_speed_mult + gm.synergy_move_speed_mult - 1.0
		if speed_excess > 0.0:
			m *= 1.0 + speed_excess * 10.0 * cvt_speed
	var cvt_armor: float = gm.item_hook_sum("dmg_per_armor")
	if cvt_armor > 0.0:
		m *= 1.0 + maxf(0.0, gm.get_effective_armor()) * cvt_armor
	var cvt_stones: float = gm.item_hook_sum("dmg_per_100_stones")
	if cvt_stones > 0.0:
		m *= 1.0 + minf(gm.spirit_stones / 100.0 * cvt_stones, gm.item_hook_sum("stone_dmg_cap"))
	var still: float = gm.item_hook_sum("still_damage")
	if still > 0.0 and gm.still_time >= maxf(0.1, gm.item_hook_sum("still_seconds")):
		m *= 1.0 + still
	# 三昧归真：上阵法器少于 4 把时，每少 1 把加一份全伤害
	var empty_slot_bonus: float = gm.item_hook_sum("dmg_per_empty_slot")
	if empty_slot_bonus > 0.0:
		var current_slots: int = gm.slots_used()
		if current_slots < 4:
			m *= 1.0 + float(4 - current_slots) * empty_slot_bonus
	# 读气血的两条：玩家不在场（局外/单测空载）时跳过，不出 NaN
	if gm.player != null and is_instance_valid(gm.player):
		var cvt_hp: float = gm.item_hook_sum("dmg_per_max_hp")
		if cvt_hp > 0.0:
			m *= 1.0 + gm.player.max_health / 50.0 * cvt_hp
		var cvt_missing: float = gm.item_hook_sum("dmg_per_missing_hp")
		if cvt_missing > 0.0:
			var missing: float = 1.0 - BalanceCombat.hp_ratio(gm.player.current_health, gm.player.max_health)
			if missing > 0.0:
				m *= 1.0 + missing * 10.0 * cvt_missing
	# ---- 角色特性乘区 ----
	var def := CultivatorData.get_def(gm.cultivator_id)
	if def.is_empty():
		return m
	var mods: Dictionary = def.get("mods", {})
	var tag_bonuses: Dictionary = mods.get("tag_damage", {})
	for t in WeaponData.tags_of(w_id):
		m *= 1.0 + float(tag_bonuses.get(t, 0.0))
	var wdef := WeaponData.get_def(w_id)
	var w_beh := int(wdef.get("behavior", -1))
	if w_beh != WeaponData.Behavior.DRONE:
		m *= 1.0 + float(mods.get("non_drone_damage", 0.0))
	if w_beh != WeaponData.Behavior.TURRET and w_beh != WeaponData.Behavior.DRONE:
		m *= 1.0 + float(mods.get("non_contraption_damage", 0.0))
	# 非专精器类惩罚（通用键）：武器不带指定 tag 时吃对应修正，符修/霸王的代偿代价走这里
	var non_tag: Dictionary = mods.get("non_tag_damage", {})
	for t in non_tag:
		if not WeaponData.tags_of(w_id).has(String(t)):
			m *= 1.0 + float(non_tag[t])
	if gm.on_hit_damage_bonus > 0.0 and gm.on_hit_damage_stacks > 0:
		m *= 1.0 + gm.on_hit_damage_bonus * float(gm.on_hit_damage_stacks)
	# 收藏家·图鉴：每持有一种不同法宝全伤害加成（种数账本在 GameManager.add_item/consume_item 维护）
	if gm.collection_damage_per_unique > 0.0 and gm.unique_item_count > 0:
		m *= 1.0 + gm.collection_damage_per_unique * float(gm.unique_item_count)
	# 狂战士·战意：击杀攒的层数全伤害加成（攒/流失账本在 GameManager，幅度在 FrenzyData）
	if gm.frenzy_enabled > 0.0 and gm.frenzy_stacks > 0.0:
		m *= FrenzyData.damage_mult(gm.frenzy_stacks)
	# 蛮兵·陷阵：感知圈内的妖兽每只一份全伤害加成（敌潮 ×1.5 的闭环：围得越密砍得越狠）
	if gm.crowd_damage_per_enemy > 0.0 and gm.nearby_enemy_count > 0:
		m *= 1.0 + minf(gm.nearby_enemy_count * gm.crowd_damage_per_enemy, gm.crowd_damage_cap)
	# 守财奴·财可通神：随身金币每 100 枚一份全伤害加成（与结息闭环：攒钱就是攒刀）
	if gm.stone_damage_per_100 > 0.0:
		m *= 1.0 + minf(gm.spirit_stones / 100.0 * gm.stone_damage_per_100, gm.stone_damage_cap)
	return m
