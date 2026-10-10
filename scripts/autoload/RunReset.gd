class_name RunReset
extends RefCounted

## 单局状态整体复位（2026-10-11 从 GameManager.reset_run 抽离）：
## 70+ 个单局成员的显式类型化清零（不用字符串 set，保住静态检查）。
## 新增单局成员时在这里补一行默认值——头注就是提醒你这件事的。

static func reset(gm: Node) -> void:
	Engine.time_scale = 1.0
	gm._hitstop_token += 1
	gm.rng.randomize()
	gm.kills = 0
	gm.game_time = 0.0
	gm.spirit_stones = 0
	gm.level = 1
	gm.experience = 0
	gm.experience_to_next = GameBalance.EXP_FIRST_LEVEL
	gm.is_game_over = false
	gm.pending_upgrade_points = 0
	gm.wave_number = 0
	gm.endless_mode = false
	gm.run_started = false
	gm.weapon_damage_mult = 1.0
	gm.melee_damage = 0.0
	gm.ranged_damage = 0.0
	gm.elemental_damage = 0.0
	gm.engineering_damage = 0.0
	gm.attack_speed_mult = 1.0
	gm.move_speed_mult = 1.0
	gm.pickup_range_mult = 1.0
	gm.attack_range_mult = 1.0
	gm.armor = 0.0
	gm.hp_regen = 0.0
	gm.crit_rate = 0.05
	gm.crit_mult = 1.5
	gm.dodge = 0.0
	gm.lifesteal = 0.0
	gm.luck = 0.0
	gm.harvest = 0.0
	gm.xp_gain_mult = 1.0
	gm.knockback_mult = 1.0
	gm.elite_damage = 0.0
	gm.free_rerolls = 0
	gm.element_damage = {}
	gm.locked_upgrades = []
	gm.cultivator_id = ""
	gm.thorns_pct = 0.0
	gm.spirit_threshold_adj = 0
	gm.contraption_threshold_adj = 0
	gm.stone_interest_rate = 0.0
	gm.stone_interest_cap = 15
	gm.on_hit_damage_bonus = 0.0
	gm.on_hit_damage_cap_stacks = 10
	gm.on_hit_damage_stacks = 0
	gm.on_hit_damage_timer = 0.0
	gm.total_damage_taken_count = 0
	gm.total_hp_healed = 0.0
	gm.max_concurrent_summons = 0
	gm.dodge_cap_bonus = 0.0
	gm.weapon_slots_override = 0
	gm.enemy_count_mult = 1.0
	gm.harvest_decay = 0.0
	gm.xp_require_mult = 1.0
	gm.item_price_mult = 1.0
	gm.shop_slots_bonus = 0
	gm.pending_skill_id = "dash"
	gm.active_skill_id = ""
	gm.buff_move_speed_mult = 1.0
	gm.buff_attack_speed_mult = 1.0
	gm._exp_chain = GameBalance.EXP_FIRST_LEVEL
	gm.stat_bonus_pierce = 0
	gm.synergy_bonus_pierce = 0
	gm.bonus_pierce = 0
	gm.synergy_damage_mult = 1.0
	gm.synergy_range_mult = 1.0
	gm.synergy_haste_mult = 1.0
	gm.synergy_max_hp_bonus = 0.0
	gm.synergy_engineering_damage = 0.0
	gm.synergy_crit_rate = 0.0
	gm.synergy_crit_mult = 0.0
	gm.synergy_hp_regen = 0.0
	gm.synergy_lifesteal = 0.0
	gm.synergy_move_speed_mult = 0.0
	gm.synergy_burn_mult = 1.0
	gm.synergy_armor = 0.0
	gm.synergy_knockback_mult = 1.0
	gm.synergy_contraption_mult = 1.0
	gm.active_synergies = {}
	gm._applied_hp_bonus = 0.0
	gm._lifesteal_procs = 0
	gm._lifesteal_window = 0.0
	gm._hud_tick = 0.0
	gm.shop_offers = []
	gm.reroll_cost = 2
	gm.reroll_count = 0
	gm.reroll_free_left = 0
	gm.shop_price_mult = 1.0
	gm.shop_tag_filter = []
	gm._no_main_tag_waves = 0
	gm.alloc_offers.clear()  # Array[Dictionary] 定型数组：经 Node 属性通道不能赋裸 []，原地清空
	gm.alloc_points_total = 0
	gm.alloc_reroll_cost = 2
	gm.alloc_reroll_count = 0
	gm.alloc_reroll_free_left = 0
	gm.items = []
	gm.drones = []
	gm.stash = []
	gm.upgrade_history.clear()
	gm.upgrade_counts.clear()
	gm.last_run_new_achievements = []
	gm.peak_stones = 0
	gm.peak_dodge = 0.0
	gm.peak_harvest = 0.0
	# 敌人活体登记跟着清：旧场敌人随后 _exit_tree 注销是安全空操作
	gm.live_enemies.clear()
	gm.enemy_count = 0
