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
	gm.hp_regen += float(mods.get("hp_regen", 0.0))
	gm.weapon_slots_override = int(mods.get("weapon_slots_max", 0))
	gm.enemy_count_mult = float(mods.get("enemy_count_mult", 1.0))
	gm.harvest_decay = float(mods.get("harvest_decay", 0.0))
	gm.xp_require_mult = float(mods.get("xp_require_mult", 1.0))
	gm.item_price_mult = float(mods.get("item_price", 1.0))
	gm.shop_slots_bonus = int(mods.get("shop_slots", 0))
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
	for i in range(start_drones):
		gm.drones.append(1)
	if start_drones > 0 and gm.player != null and gm.player.has_method("sync_drones"):
		gm.player.sync_drones()

## 修士特性的单武器伤害系数（tag 加成 × 非灵蝶/非机关惩罚 + 受击增伤）
static func damage_mult(gm: Node, w_id: String) -> float:
	var def := CultivatorData.get_def(gm.cultivator_id)
	if def.is_empty():
		return 1.0
	var mods: Dictionary = def.get("mods", {})
	var m := 1.0
	var tag_bonuses: Dictionary = mods.get("tag_damage", {})
	for t in WeaponData.tags_of(w_id):
		m *= 1.0 + float(tag_bonuses.get(t, 0.0))
	var wdef := WeaponData.get_def(w_id)
	var w_beh := int(wdef.get("behavior", -1))
	if w_beh != WeaponData.Behavior.DRONE:
		m *= 1.0 + float(mods.get("non_drone_damage", 0.0))
	if w_beh != WeaponData.Behavior.TURRET and w_beh != WeaponData.Behavior.DRONE:
		m *= 1.0 + float(mods.get("non_contraption_damage", 0.0))
	if gm.on_hit_damage_bonus > 0.0 and gm.on_hit_damage_stacks > 0:
		m *= 1.0 + gm.on_hit_damage_bonus * float(gm.on_hit_damage_stacks)
	return m
