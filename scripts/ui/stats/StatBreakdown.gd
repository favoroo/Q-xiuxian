class_name StatBreakdown
extends RefCounted

## 属性面板聚合展示模型（2026-10-11 从 GameManager.get_stat_breakdown 迁入 ui/stats）：
## 只读 gm 现有属性与羁绊乘区，折算成属性面板/属性说明的展示口径。渲染层只读，不写状态。
##
## 参数收 Object 而不是 Node：同一个算式还要能读「属性影子」（ui/stats/StatShadow，
## 一个不挂树、不发信号的字段快照），悟道卡面那句「当前 X → 加后 Y」就是把加完这一条的
## 影子喂进来算出来的。两边共用这一份聚合，卡面承诺的数与实际长出来的数才不会分家。

static func breakdown(gm: Object) -> Dictionary:
	# 玩家未生成时的兜底读数一律取 Player 的基础常量，不许再写一份字面量
	var cur_hp: float = Player.BASE_MAX_HEALTH
	var max_hp: float = Player.BASE_MAX_HEALTH
	var base_spd: float = Player.BASE_SPEED
	if gm.player != null and is_instance_valid(gm.player):
		cur_hp = float(gm.player.current_health)
		max_hp = float(gm.player.max_health)
		base_spd = float(gm.player.base_speed)
	var total_armor: float = gm.armor + gm.synergy_armor
	var dmg_reduction: float = GameBalance.armor_reduction(total_armor)
	# 移速/攻速读数与 Player 实际口径同源：装备/加点层 × 羁绊层 × 技能 buff 层 × 站定神像
	var eff_haste: float = gm.get_effective_attack_speed_mult()
	var cdr_pct: float = (1.0 - eff_haste) * 100.0
	var eff_move: float = (gm.move_speed_mult + gm.synergy_move_speed_mult) * gm.buff_move_speed_mult
	# 伤害读数同样与运行时同形：装备/加点层（软顶折算）× 羁绊层 × 影层（影者攒着影层时面板如实反映，非影者恒为 1.0）
	var eff_dmg: float = BalanceCombat.effective_weapon_damage_mult(gm.weapon_damage_mult) * gm.synergy_damage_mult * gm.shadow_amp_mult
	return {
		"current_hp": cur_hp,
		"max_hp": max_hp,
		"hp_regen": BalanceCombat.effective_hp_regen(gm.hp_regen + gm.synergy_hp_regen),
		"armor": total_armor,
		"dmg_reduction_pct": dmg_reduction * 100.0,
		"damage_mult": eff_dmg,
		"damage_bonus_pct": (eff_dmg - 1.0) * 100.0,
		"melee_damage": gm.melee_damage,
		# 远程伤害读数 = 加点/道具层 + 弹射羁绊（synergy_ranged_damage，2026-10-17 弹射羁绊新增）
		"ranged_damage": gm.ranged_damage + gm.synergy_ranged_damage,
			"elemental_damage": gm.elemental_damage,
			"engineering_damage": gm.engineering_damage,
			"contraption_damage": gm.contraption_damage,
			"attack_speed_mult": eff_haste,
		"cdr_pct": cdr_pct,
		"move_speed": base_spd * eff_move,
		"move_speed_bonus_pct": (eff_move - 1.0) * 100.0,
		"pickup_radius": 96.0 * gm.pickup_range_mult,
		"pickup_bonus_pct": (gm.pickup_range_mult - 1.0) * 100.0,
		"attack_range_pct": (gm.attack_range_mult * gm.synergy_range_mult - 1.0) * 100.0,
		"crit_rate_pct": gm.get_crit_rate() * 100.0,
		"crit_dmg_pct": gm.get_crit_mult() * 100.0,
		"dodge_pct": gm.get_effective_dodge() * 100.0,
		"lifesteal_pct": (gm.lifesteal + gm.synergy_lifesteal) * 100.0,
		"luck": gm.luck,
		"harvest": gm.harvest,
		"xp_gain_pct": (gm.xp_gain_mult - 1.0) * 100.0,
		"knockback_pct": (gm.knockback_mult * gm.synergy_knockback_mult - 1.0) * 100.0,
		"elite_damage_pct": gm.elite_damage * 100.0,
		"free_rerolls": gm.free_rerolls,
		"bonus_pierce": gm.bonus_pierce,
		"thorns_pct": gm.thorns_pct * 100.0,
		"shop_price_pct": (gm.shop_price_mult - 1.0) * 100.0,
	}
