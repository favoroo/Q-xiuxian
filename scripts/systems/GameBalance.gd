class_name GameBalance
extends RefCounted

## 数值公式门面：全部实现已按主题拆到同目录五个 static 类（2026-10-11 拆分，降低并行调参冲突面）：
##   BalanceWave      回合/刷怪/精英Boss/危险度
##   BalanceEconomy   经验/商店定价/灵韵/残丹化灵/稀有度/货架抽取/道具档位/羁绊档位/加点白名单
##   BalanceCombat    护甲受伤/镜头创伤/受击硬直击退/长扑几何/五行异常/震退方向/集火韧性
##   BalanceTargeting 索敌分流/藏宝匣两段式索敌/武器属性折算/御灵轨道/神识分流
##   BalanceSpiritBeast 祭坛灵兽（生命成长/撕咬/嘲讽半径）
##   BalanceChest     藏宝匣（每回合数量/三档权重/击数/掉落表/玉匣送道具上限）
## 本文件只做转发：旧引用（GameBalance.xxx，22 个文件）零改动；新增公式直接进主题类，
## 需要旧入口时在这里补一行转发。两条硬性约束对四个主题类同样生效：
##   1. 需要随机数的地方由调用方传入 rng 或已经抽好的 roll，这样单测可以固定种子做确定性断言；
##   2. 入参出参只用值类型，任何依赖 Player / GameManager 状态的判断都留在调用方。
## 配套单测：tests/UnitRunner.gd（headless，不加载任何场景）。

# ---------------- 常量转发（调参改主题类，别改这里） ----------------

# 回合 / 刷怪 / 精英 Boss / 危险度 → BalanceWave
const WAVE_DURATION_BASE := BalanceWave.WAVE_DURATION_BASE
const WAVE_DURATION_PER_WAVE := BalanceWave.WAVE_DURATION_PER_WAVE
const WAVE_DURATION_MAX := BalanceWave.WAVE_DURATION_MAX
const SPAWN_INTERVAL_BASE := BalanceWave.SPAWN_INTERVAL_BASE
const SPAWN_INTERVAL_MIN := BalanceWave.SPAWN_INTERVAL_MIN
const SPAWN_INTERVAL_PER_WAVE := BalanceWave.SPAWN_INTERVAL_PER_WAVE
const SPAWN_BATCH_EVERY_WAVES := BalanceWave.SPAWN_BATCH_EVERY_WAVES
const SPAWN_BATCH_BONUS_CHANCE := BalanceWave.SPAWN_BATCH_BONUS_CHANCE
const WAVE_SPAWN_BUDGET_MAX := BalanceWave.WAVE_SPAWN_BUDGET_MAX
const DEEP_WAVE_THRESHOLD := BalanceWave.DEEP_WAVE_THRESHOLD
const DEEP_BUDGET_PER_WAVE := BalanceWave.DEEP_BUDGET_PER_WAVE
const DEEP_BUDGET_MAX := BalanceWave.DEEP_BUDGET_MAX
const DEEP_DMG_GROWTH := BalanceWave.DEEP_DMG_GROWTH
const DEEP_HP_GROWTH := BalanceWave.DEEP_HP_GROWTH
const DEEP_SWARM_PER_WAVE := BalanceWave.DEEP_SWARM_PER_WAVE
const DEEP_SWARM_MAX := BalanceWave.DEEP_SWARM_MAX
const MAX_ENEMIES_HARD_CAP := BalanceWave.MAX_ENEMIES_HARD_CAP
const BATCH_CLEAR_COOLDOWN := BalanceWave.BATCH_CLEAR_COOLDOWN
const BATCH_STALEMATE_TIMEOUT := BalanceWave.BATCH_STALEMATE_TIMEOUT
const CONCURRENT_BATCH_MIN_WAVE := BalanceWave.CONCURRENT_BATCH_MIN_WAVE
const BATCH_REFILL_EARLY := BalanceWave.BATCH_REFILL_EARLY
const BATCH_REFILL_MID := BalanceWave.BATCH_REFILL_MID
const BATCH_REFILL_LATE := BalanceWave.BATCH_REFILL_LATE
const BATCH_REFILL_MID_WAVE := BalanceWave.BATCH_REFILL_MID_WAVE
const BATCH_REFILL_LATE_WAVE := BalanceWave.BATCH_REFILL_LATE_WAVE
const ENEMY_HP_GROWTH := BalanceWave.ENEMY_HP_GROWTH
const MOB_HP_BASE_MULT := BalanceWave.MOB_HP_BASE_MULT
const MOB_KILL_EXP_MULT := BalanceWave.MOB_KILL_EXP_MULT
const ENEMY_DMG_GROWTH := BalanceWave.ENEMY_DMG_GROWTH
const ENEMY_DMG_BASE_MULT := BalanceWave.ENEMY_DMG_BASE_MULT
const BOLT_DMG_BASE_REF := BalanceWave.BOLT_DMG_BASE_REF
# 掉落与死亡反馈几何 → BalanceWave
const ELITE_GEM_COUNT := BalanceWave.ELITE_GEM_COUNT
const GEM_SCATTER_RADIUS := BalanceWave.GEM_SCATTER_RADIUS
const ELITE_GEM_EXP := BalanceWave.ELITE_GEM_EXP
const BLINK_DISTANCE := BalanceWave.BLINK_DISTANCE
const BLINK_MAP_INSET := BalanceWave.BLINK_MAP_INSET
const SPLIT_SCATTER_RADIUS := BalanceWave.SPLIT_SCATTER_RADIUS
const MINION_SCATTER_RADIUS := BalanceWave.MINION_SCATTER_RADIUS
const HEAL_ORB_SCATTER_RADIUS := BalanceWave.HEAL_ORB_SCATTER_RADIUS
const DEATH_KICK_CAMERA := BalanceWave.DEATH_KICK_CAMERA
const DEATH_MICRO_KICK := BalanceWave.DEATH_MICRO_KICK
const STONE_FLOAT_OFFSET := BalanceWave.STONE_FLOAT_OFFSET
const CORPSE_SWELL_SCALE := BalanceWave.CORPSE_SWELL_SCALE
const ELITE_DEATH_STAGGER_DUR := BalanceWave.ELITE_DEATH_STAGGER_DUR
const ELITE_DEATH_TOPPLE_RAD := BalanceWave.ELITE_DEATH_TOPPLE_RAD
const ELITE_DEATH_COLLAPSE_DUR := BalanceWave.ELITE_DEATH_COLLAPSE_DUR
const BOSS_DEATH_TOPPLE_RAD := BalanceWave.BOSS_DEATH_TOPPLE_RAD
const BOSS_DEATH_LINGER_DUR := BalanceWave.BOSS_DEATH_LINGER_DUR
const BOSS_DEATH_FADE_DUR := BalanceWave.BOSS_DEATH_FADE_DUR
# 刷怪出生点几何 → BalanceWave
const SPAWN_INSET_MOB := BalanceWave.SPAWN_INSET_MOB
const SPAWN_MIN_DIST_MOB := BalanceWave.SPAWN_MIN_DIST_MOB
const SPAWN_PUSH_MOB := BalanceWave.SPAWN_PUSH_MOB
const SPAWN_INSET_ELITE := BalanceWave.SPAWN_INSET_ELITE
const SPAWN_MIN_DIST_ELITE := BalanceWave.SPAWN_MIN_DIST_ELITE
const SPAWN_PUSH_ELITE := BalanceWave.SPAWN_PUSH_ELITE
const SPAWN_INSET_BOSS := BalanceWave.SPAWN_INSET_BOSS
const SPAWN_MIN_DIST_BOSS := BalanceWave.SPAWN_MIN_DIST_BOSS
const SPAWN_PUSH_BOSS := BalanceWave.SPAWN_PUSH_BOSS
const SPAWN_INSET_CHEST := BalanceWave.SPAWN_INSET_CHEST
const SPAWN_MIN_DIST_CHEST := BalanceWave.SPAWN_MIN_DIST_CHEST
const SPAWN_PUSH_CHEST := BalanceWave.SPAWN_PUSH_CHEST
const ENEMY_STAT_VARIANCE := BalanceWave.ENEMY_STAT_VARIANCE
const ENEMY_SPEED_VARIANCE := BalanceWave.ENEMY_SPEED_VARIANCE
const ELITE_STONE_BONUS := BalanceWave.ELITE_STONE_BONUS
const ELITE_MUTATION_HP_PCT := BalanceWave.ELITE_MUTATION_HP_PCT
const MUT_GOLEM_SPEED_MULT := BalanceWave.MUT_GOLEM_SPEED_MULT
const MUT_GOLEM_SLAM_INTERVAL := BalanceWave.MUT_GOLEM_SLAM_INTERVAL
const MUT_GOLEM_SLAM_RADIUS := BalanceWave.MUT_GOLEM_SLAM_RADIUS
const MUT_GOLEM_SLAM_WINDUP := BalanceWave.MUT_GOLEM_SLAM_WINDUP
const MUT_GOLEM_SLAM_DMG_MULT := BalanceWave.MUT_GOLEM_SLAM_DMG_MULT
const MUT_CHILEI_INTERVAL_MULT := BalanceWave.MUT_CHILEI_INTERVAL_MULT
const MUT_CHILEI_SIDE_BOLTS := BalanceWave.MUT_CHILEI_SIDE_BOLTS
const MUT_JIANSHA_BOLT_COUNT := BalanceWave.MUT_JIANSHA_BOLT_COUNT
const MUT_JIANSHA_INTERVAL_MULT := BalanceWave.MUT_JIANSHA_INTERVAL_MULT
const MUT_JIANSHA_RANGE := BalanceWave.MUT_JIANSHA_RANGE
const ELITE_WAVES := BalanceWave.ELITE_WAVES
const BOSS_WAVES := BalanceWave.BOSS_WAVES
const BOSS_HP_BASE := BalanceWave.BOSS_HP_BASE
const BOSS_CONTACT_BASE := BalanceWave.BOSS_CONTACT_BASE
const BOSS_ATTACK_INTERVAL := BalanceWave.BOSS_ATTACK_INTERVAL
const BOSS_RING_COUNT := BalanceWave.BOSS_RING_COUNT
const BOSS_RING_COUNT_P2 := BalanceWave.BOSS_RING_COUNT_P2
const BOSS_RING_DMG_MULT := BalanceWave.BOSS_RING_DMG_MULT
const BOSS_RING_CURVE_ANG := BalanceWave.BOSS_RING_CURVE_ANG
const BOSS_RING_LAYER_DELAY := BalanceWave.BOSS_RING_LAYER_DELAY
const BOSS_BOLT_SPEED := BalanceWave.BOSS_BOLT_SPEED
const BOSS_BOLT_SCALE := BalanceWave.BOSS_BOLT_SCALE
const BOSS_FAN_WAVES := BalanceWave.BOSS_FAN_WAVES
const BOSS_FAN_WAVES_P2 := BalanceWave.BOSS_FAN_WAVES_P2
const BOSS_FAN_COUNT := BalanceWave.BOSS_FAN_COUNT
const BOSS_FAN_SPREAD := BalanceWave.BOSS_FAN_SPREAD
const BOSS_FAN_WAVE_INTERVAL := BalanceWave.BOSS_FAN_WAVE_INTERVAL
const BOSS_FAN_BASE_SPEED := BalanceWave.BOSS_FAN_BASE_SPEED
const BOSS_FAN_DMG_MULT := BalanceWave.BOSS_FAN_DMG_MULT
const BOSS_SPIRAL_DURATION := BalanceWave.BOSS_SPIRAL_DURATION
const BOSS_SPIRAL_INTERVAL := BalanceWave.BOSS_SPIRAL_INTERVAL
const BOSS_SPIRAL_ARMS := BalanceWave.BOSS_SPIRAL_ARMS
const BOSS_SPIRAL_ARMS_FINAL := BalanceWave.BOSS_SPIRAL_ARMS_FINAL
const BOSS_SPIRAL_ROT_SPEED := BalanceWave.BOSS_SPIRAL_ROT_SPEED
const BOSS_SPIRAL_BOLT_SPEED := BalanceWave.BOSS_SPIRAL_BOLT_SPEED
const BOSS_SPIRAL_ANGULAR := BalanceWave.BOSS_SPIRAL_ANGULAR
const BOSS_SPIRAL_DMG_MULT := BalanceWave.BOSS_SPIRAL_DMG_MULT
const BOSS_SPLIT_BOMB_COUNT := BalanceWave.BOSS_SPLIT_BOMB_COUNT
const BOSS_SPLIT_BOMB_COUNT_FINAL := BalanceWave.BOSS_SPLIT_BOMB_COUNT_FINAL
const BOSS_SPLIT_BOMB_SPEED := BalanceWave.BOSS_SPLIT_BOMB_SPEED
const BOSS_SPLIT_BOMB_SCALE := BalanceWave.BOSS_SPLIT_BOMB_SCALE
const BOSS_SPLIT_BOMB_FUSE := BalanceWave.BOSS_SPLIT_BOMB_FUSE
const BOSS_SPLIT_BOMB_CHILD_COUNT := BalanceWave.BOSS_SPLIT_BOMB_CHILD_COUNT
const BOSS_SPLIT_BOMB_CHILD_SPEED := BalanceWave.BOSS_SPLIT_BOMB_CHILD_SPEED
const BOSS_SPLIT_BOMB_CHILD_SCALE := BalanceWave.BOSS_SPLIT_BOMB_CHILD_SCALE
const BOSS_SPLIT_BOMB_DMG_MULT := BalanceWave.BOSS_SPLIT_BOMB_DMG_MULT
const BOSS_SPLIT_CHILD_DMG_MULT := BalanceWave.BOSS_SPLIT_CHILD_DMG_MULT
const BOSS_CHARGE_WINDUP := BalanceWave.BOSS_CHARGE_WINDUP
const BOSS_CHARGE_DURATION := BalanceWave.BOSS_CHARGE_DURATION
const BOSS_CHARGE_BRAKE := BalanceWave.BOSS_CHARGE_BRAKE
const BOSS_CHARGE_SPEED_MUL := BalanceWave.BOSS_CHARGE_SPEED_MUL
const BOSS_CHARGE_HIT_RADIUS := BalanceWave.BOSS_CHARGE_HIT_RADIUS
const BOSS_CHARGE_DMG_MULT := BalanceWave.BOSS_CHARGE_DMG_MULT
const BOSS_CHARGE_SIDE_BOLTS := BalanceWave.BOSS_CHARGE_SIDE_BOLTS
const BOSS_SKY_FIRE_COUNT := BalanceWave.BOSS_SKY_FIRE_COUNT
const BOSS_SKY_FIRE_COUNT_P2 := BalanceWave.BOSS_SKY_FIRE_COUNT_P2
const BOSS_SKY_FIRE_INTERVAL := BalanceWave.BOSS_SKY_FIRE_INTERVAL
const BOSS_SKY_FIRE_WINDUP := BalanceWave.BOSS_SKY_FIRE_WINDUP
const BOSS_SKY_FIRE_RADIUS := BalanceWave.BOSS_SKY_FIRE_RADIUS
const BOSS_SKY_FIRE_DMG_MULT := BalanceWave.BOSS_SKY_FIRE_DMG_MULT
const BOSS_SLAM_WINDUP := BalanceWave.BOSS_SLAM_WINDUP
const BOSS_SLAM_RADIUS := BalanceWave.BOSS_SLAM_RADIUS
const BOSS_SLAM_DMG_MULT := BalanceWave.BOSS_SLAM_DMG_MULT
const BOSS_SUMMON_COUNT := BalanceWave.BOSS_SUMMON_COUNT
const BOSS_SUMMON_CAP := BalanceWave.BOSS_SUMMON_CAP
const BOSS_PHASE2_AT := BalanceWave.BOSS_PHASE2_AT
const BOSS_PHASE2_INTERVAL_MULT := BalanceWave.BOSS_PHASE2_INTERVAL_MULT
const BOSS_PHASE2_SPEED_MULT := BalanceWave.BOSS_PHASE2_SPEED_MULT
const BOSS_KNOCKBACK_RESIST := BalanceWave.BOSS_KNOCKBACK_RESIST
const BOSS_STONE_REWARD := BalanceWave.BOSS_STONE_REWARD
const DANGER_MAX := BalanceWave.DANGER_MAX
const DANGER_HP_BASE := BalanceWave.DANGER_HP_BASE
const DANGER_HP_PER := BalanceWave.DANGER_HP_PER
const DANGER_DMG_BASE := BalanceWave.DANGER_DMG_BASE
const DANGER_DMG_PER := BalanceWave.DANGER_DMG_PER
const DANGER_COUNT_BASE := BalanceWave.DANGER_COUNT_BASE
const DANGER_COUNT_PER := BalanceWave.DANGER_COUNT_PER

# 经验 / 定价 / 灵韵 / 稀有度 / 货架 / 道具档位 / 白名单 → BalanceEconomy
const EXP_FIRST_LEVEL := BalanceEconomy.EXP_FIRST_LEVEL
const EXP_GROWTH := BalanceEconomy.EXP_GROWTH
const EXP_FLAT := BalanceEconomy.EXP_FLAT
const WEAVE_WAVE_STEP := BalanceEconomy.WEAVE_WAVE_STEP
const ITEM_WAVE_STEP := BalanceEconomy.ITEM_WAVE_STEP
const REROLL_BASE := BalanceEconomy.REROLL_BASE
const REROLL_WAVE_STEP := BalanceEconomy.REROLL_WAVE_STEP
const REROLL_COUNT_WAVE_SCALE := BalanceEconomy.REROLL_COUNT_WAVE_SCALE
const HARVEST_GROWTH := BalanceEconomy.HARVEST_GROWTH
const HEAL_OVERFLOW_STONE_PER_HP := BalanceEconomy.HEAL_OVERFLOW_STONE_PER_HP
const HEAL_OVERFLOW_STONE_CAP := BalanceEconomy.HEAL_OVERFLOW_STONE_CAP
const GEM_SHARD_STONE_VALUE := BalanceEconomy.GEM_SHARD_STONE_VALUE
const GEM_SHARD_BASE_CHANCE := BalanceEconomy.GEM_SHARD_BASE_CHANCE
const GEM_SHARD_START_WAVE := BalanceEconomy.GEM_SHARD_START_WAVE
const GEM_SHARD_CHANCE_CAP := BalanceEconomy.GEM_SHARD_CHANCE_CAP
const EARLY_CLEAR_STONES_PER_SEC := BalanceEconomy.EARLY_CLEAR_STONES_PER_SEC
const EARLY_CLEAR_STONES_MAX := BalanceEconomy.EARLY_CLEAR_STONES_MAX
const RARITY_TOTAL := BalanceEconomy.RARITY_TOTAL
const RARITY_COMMON_FLOOR := BalanceEconomy.RARITY_COMMON_FLOOR
const RARITY_LUCK_PER_POINT := BalanceEconomy.RARITY_LUCK_PER_POINT
const RARITY_RARE_BASE := BalanceEconomy.RARITY_RARE_BASE
const RARITY_RARE_PER_WAVE := BalanceEconomy.RARITY_RARE_PER_WAVE
const RARITY_RARE_CAP := BalanceEconomy.RARITY_RARE_CAP
const RARITY_EPIC_WAVE := BalanceEconomy.RARITY_EPIC_WAVE
const RARITY_EPIC_PER_WAVE := BalanceEconomy.RARITY_EPIC_PER_WAVE
const RARITY_EPIC_CAP := BalanceEconomy.RARITY_EPIC_CAP
const RARITY_LEGEND_WAVE := BalanceEconomy.RARITY_LEGEND_WAVE
const RARITY_LEGEND_PER_WAVE := BalanceEconomy.RARITY_LEGEND_PER_WAVE
const RARITY_LEGEND_CAP := BalanceEconomy.RARITY_LEGEND_CAP
const POTION_CHANCE := BalanceEconomy.POTION_CHANCE
const ITEM_CHANCE := BalanceEconomy.ITEM_CHANCE
const PET_CHANCE := BalanceEconomy.PET_CHANCE
const POTION_HEAL_RATIO := BalanceEconomy.POTION_HEAL_RATIO
const TAG_AFFINITY_MIN_COPIES := BalanceEconomy.TAG_AFFINITY_MIN_COPIES
const TAG_AFFINITY_MULT_L1 := BalanceEconomy.TAG_AFFINITY_MULT_L1
const TAG_AFFINITY_TIER2_COPIES := BalanceEconomy.TAG_AFFINITY_TIER2_COPIES
const TAG_AFFINITY_MULT_L2 := BalanceEconomy.TAG_AFFINITY_MULT_L2
const TAG_AFFINITY_COMBO_DAMP := BalanceEconomy.TAG_AFFINITY_COMBO_DAMP
const LUCK_SHOP_PER_POINT := BalanceEconomy.LUCK_SHOP_PER_POINT
const MAIN_TAG_PITY_WAVES := BalanceEconomy.MAIN_TAG_PITY_WAVES
const TAG_FILTER_BONUS := BalanceEconomy.TAG_FILTER_BONUS
const TAG_FILTER_LEAK := BalanceEconomy.TAG_FILTER_LEAK
const ITEM_TIER_WAVES := BalanceEconomy.ITEM_TIER_WAVES
const ITEM_TIER_COMMON_FLOOR := BalanceEconomy.ITEM_TIER_COMMON_FLOOR
const LUCK_ITEM_MULT_PER_POINT := BalanceEconomy.LUCK_ITEM_MULT_PER_POINT
const ITEM_TIER_RARE_PER_WAVE := BalanceEconomy.ITEM_TIER_RARE_PER_WAVE
const ITEM_TIER_RARE_CAP := BalanceEconomy.ITEM_TIER_RARE_CAP
const ITEM_TIER_EPIC_PER_WAVE := BalanceEconomy.ITEM_TIER_EPIC_PER_WAVE
const ITEM_TIER_EPIC_CAP := BalanceEconomy.ITEM_TIER_EPIC_CAP
const ITEM_TIER_LEGEND_PER_WAVE := BalanceEconomy.ITEM_TIER_LEGEND_PER_WAVE
const ITEM_TIER_LEGEND_CAP := BalanceEconomy.ITEM_TIER_LEGEND_CAP

# 护甲 / 创伤 / 硬直击退 / 长扑 / 异常状态 / 震退 / 集火 → BalanceCombat
const ARMOR_COEF := BalanceCombat.ARMOR_COEF
const DAMAGE_FLOOR := BalanceCombat.DAMAGE_FLOOR
const HP_LOW_RATIO := BalanceCombat.HP_LOW_RATIO
const TRAUMA_DECAY := BalanceCombat.TRAUMA_DECAY
const TRAUMA_BUDGET := BalanceCombat.TRAUMA_BUDGET
const SHAKE_EXPONENT := BalanceCombat.SHAKE_EXPONENT
const HIT_STUN_NORMAL := BalanceCombat.HIT_STUN_NORMAL
const HIT_STUN_CRIT := BalanceCombat.HIT_STUN_CRIT
const HIT_FREEZE_NORMAL := BalanceCombat.HIT_FREEZE_NORMAL
const HIT_FREEZE_CRIT := BalanceCombat.HIT_FREEZE_CRIT
const KNOCKBACK_IMPULSE_SCALE := BalanceCombat.KNOCKBACK_IMPULSE_SCALE
const KNOCKBACK_DECAY_STUN := BalanceCombat.KNOCKBACK_DECAY_STUN
const KNOCKBACK_DECAY_FREE := BalanceCombat.KNOCKBACK_DECAY_FREE
const KNOCKBACK_MAX_SPEED_NORMAL := BalanceCombat.KNOCKBACK_MAX_SPEED_NORMAL
const KNOCKBACK_MAX_SPEED_CRIT := BalanceCombat.KNOCKBACK_MAX_SPEED_CRIT
const KNOCKBACK_HEAVY_SPEED := BalanceCombat.KNOCKBACK_HEAVY_SPEED
const KNOCKBACK_HEAVY_DECAY_MULT := BalanceCombat.KNOCKBACK_HEAVY_DECAY_MULT
const KILL_HITSTOP_DURATION := BalanceCombat.KILL_HITSTOP_DURATION
const KILL_HITSTOP_SCALE := BalanceCombat.KILL_HITSTOP_SCALE
const KILL_HITSTOP_MIN_INTERVAL := BalanceCombat.KILL_HITSTOP_MIN_INTERVAL
const HITSTOP_TIMESCALE_FLOOR := BalanceCombat.HITSTOP_TIMESCALE_FLOOR
const CRIT_TRAUMA_NORMAL := BalanceCombat.CRIT_TRAUMA_NORMAL
const CRIT_TRAUMA_ELITE := BalanceCombat.CRIT_TRAUMA_ELITE
const CRIT_KILL_HITSTOP_DURATION := BalanceCombat.CRIT_KILL_HITSTOP_DURATION
const CRIT_KILL_HITSTOP_SCALE := BalanceCombat.CRIT_KILL_HITSTOP_SCALE
const CRIT_KILL_HITSTOP_MIN_INTERVAL := BalanceCombat.CRIT_KILL_HITSTOP_MIN_INTERVAL
const MICRO_KICK_MIN_INTERVAL := BalanceCombat.MICRO_KICK_MIN_INTERVAL
const BOSS_HEAVY_HIT_PCT := BalanceCombat.BOSS_HEAVY_HIT_PCT
const BOSS_HEAVY_HIT_TRAUMA := BalanceCombat.BOSS_HEAVY_HIT_TRAUMA
const BOSS_HEAVY_HIT_COOLDOWN := BalanceCombat.BOSS_HEAVY_HIT_COOLDOWN
const ZHUMU_MINION_CAP := BalanceCombat.ZHUMU_MINION_CAP
const CHARGE_BRAKE_END_SPEED_PCT := BalanceCombat.CHARGE_BRAKE_END_SPEED_PCT
const BURN_STACK_RATIO := BalanceCombat.BURN_STACK_RATIO
const POISON_STACK_RATIO := BalanceCombat.POISON_STACK_RATIO
const BURN_ELEM_TICK_COEF := BalanceCombat.BURN_ELEM_TICK_COEF
const POISON_ELEM_TICK_COEF := BalanceCombat.POISON_ELEM_TICK_COEF
const DOT_TICK_INTERVAL := BalanceCombat.DOT_TICK_INTERVAL
const KNOCK_DIR_EPS := BalanceCombat.KNOCK_DIR_EPS
const FOCUS_FIRE_WINDOW := BalanceCombat.FOCUS_FIRE_WINDOW
const FOCUS_FIRE_HIT2_MULT := BalanceCombat.FOCUS_FIRE_HIT2_MULT
const FOCUS_FIRE_HIT3_MULT := BalanceCombat.FOCUS_FIRE_HIT3_MULT

# 索敌 / 藏宝匣 / 折算 / 御灵 / 神识分流 → BalanceTargeting
const DANGER_ZONE_RADIUS := BalanceTargeting.DANGER_ZONE_RADIUS
const TARGETING_ELLIPSE_Y_RATIO := BalanceTargeting.TARGETING_ELLIPSE_Y_RATIO
const VIEWPORT_SAFE_HALF_EXTENTS := BalanceTargeting.VIEWPORT_SAFE_HALF_EXTENTS
const APPLY_WEAPON_STAT_MAP := BalanceTargeting.APPLY_WEAPON_STAT_MAP
const SPIRIT_BASE_RADIUS := BalanceTargeting.SPIRIT_BASE_RADIUS
const SPIRIT_MIN_RADIUS := BalanceTargeting.SPIRIT_MIN_RADIUS
const SPIRIT_MAX_REACH := BalanceTargeting.SPIRIT_MAX_REACH
const SPIRIT_DANGER_DIST := BalanceTargeting.SPIRIT_DANGER_DIST
const SPIRIT_SECTOR_HALF_ANGLE := BalanceTargeting.SPIRIT_SECTOR_HALF_ANGLE
const SPIRIT_BASE_ANGULAR_SPEED := BalanceTargeting.SPIRIT_BASE_ANGULAR_SPEED
const SPIRIT_CONTACT_DUTY := BalanceTargeting.SPIRIT_CONTACT_DUTY
const SPIRIT_CONTACT_DUTY_PER_STAR := BalanceTargeting.SPIRIT_CONTACT_DUTY_PER_STAR
const MULTI_WEAPON_LOAD_PER_EXTRA := BalanceTargeting.MULTI_WEAPON_LOAD_PER_EXTRA

# 祭坛灵兽 → BalanceSpiritBeast
const SPIRIT_BEAST_TAUNT_RADIUS := BalanceSpiritBeast.TAUNT_RADIUS
const SPIRIT_BEAST_ATTACK_INTERVAL := BalanceSpiritBeast.ATTACK_INTERVAL
const SPIRIT_BEAST_BURST_COUNT := BalanceSpiritBeast.BURST_COUNT
const SPIRIT_BEAST_BURST_GAP := BalanceSpiritBeast.BURST_GAP
const SPIRIT_BEAST_CHARGE_TIME := BalanceSpiritBeast.CHARGE_TIME
const SPIRIT_BEAST_PREFER_RANGE_MIN := BalanceSpiritBeast.PREFER_RANGE_MIN
const SPIRIT_BEAST_PREFER_RANGE_MAX := BalanceSpiritBeast.PREFER_RANGE_MAX
const SPIRIT_BEAST_PROJECTILE_SPEED := BalanceSpiritBeast.PROJECTILE_SPEED
const SPIRIT_BEAST_STRAFE_SPEED_RATIO := BalanceSpiritBeast.STRAFE_SPEED_RATIO
const SPIRIT_BEAST_CONTACT_RANGE := BalanceSpiritBeast.CONTACT_RANGE
const SPIRIT_BEAST_MOVE_SPEED := BalanceSpiritBeast.MOVE_SPEED
const SPIRIT_BEAST_MOVE_ACCEL := BalanceSpiritBeast.MOVE_ACCEL
const SPIRIT_BEAST_HIT_INVINCIBLE := BalanceSpiritBeast.HIT_INVINCIBLE
const SPIRIT_BEAST_SEARCH_INTERVAL := BalanceSpiritBeast.SEARCH_INTERVAL
const SPIRIT_BEAST_IDLE_FOLLOW_DIST := BalanceSpiritBeast.IDLE_FOLLOW_DIST

# 藏宝匣（宝箱）：数量 / 三档 / 击数 / 掉落 → BalanceChest
const CHEST_BREAK_HITS := BalanceChest.CHEST_BREAK_HITS
const CHEST_MIN_HITS := BalanceChest.CHEST_MIN_HITS
const CHEST_COUNT_CAP := BalanceChest.CHEST_COUNT_CAP
const CHEST_TIER_COUNT := BalanceChest.TIER_COUNT
const CHEST_TIER_SCALE := BalanceChest.TIER_SCALE
const CHEST_JADE_ITEM_GRANT_CAP := BalanceChest.JADE_ITEM_GRANT_CAP
const CHEST_REWARD_HEAL_CAP := BalanceChest.REWARD_HEAL_CAP

# ---------------- 函数转发（签名原样，实现进主题类） ----------------

# 经验 / 定价 / 灵韵 / 化灵 / 稀有度 / 货架 / 档位 / 羁绊 / 白名单 → BalanceEconomy
static func exp_to_next(prev_needed: int) -> int:
	return BalanceEconomy.exp_to_next(prev_needed)

static func weapon_price(base: int, wave: int, price_mult: float) -> int:
	return BalanceEconomy.weapon_price(base, wave, price_mult)

static func item_price(base: int, wave: int, price_mult: float) -> int:
	return BalanceEconomy.item_price(base, wave, price_mult)

static func pet_price(base: int, wave: int, price_mult: float) -> int:
	return BalanceEconomy.pet_price(base, wave, price_mult)

static func potion_price(base: int, wave: int, price_mult: float) -> int:
	return BalanceEconomy.potion_price(base, wave, price_mult)

## 回气丹这一口回多少：货架卡、生命详情卡与 ShopSystem 的 heal() 共用这一条
static func potion_heal_amount(max_hp: float) -> float:
	return BalanceEconomy.potion_heal_amount(max_hp)

## 这一口实际回得上多少（按当前缺血截断）：货架卡与生命详情卡的读数出口
static func potion_effective_heal(max_hp: float, cur_hp: float) -> float:
	return BalanceEconomy.potion_effective_heal(max_hp, cur_hp)

static func reroll_cost(wave: int, reroll_count: int, price_mult: float) -> int:
	return BalanceEconomy.reroll_cost(wave, reroll_count, price_mult)

static func harvest_gain(harvest: float) -> int:
	return BalanceEconomy.harvest_gain(harvest)

static func harvest_next(harvest: float, wave: int, growth_wave_cap: int) -> float:
	return BalanceEconomy.harvest_next(harvest, wave, growth_wave_cap)

static func heal_overflow_stones(overflow_hp: float) -> int:
	return BalanceEconomy.heal_overflow_stones(overflow_hp)

static func rarity_weights(luck: float, wave: int = 1) -> Dictionary:
	return BalanceEconomy.rarity_weights(luck, wave)

static func tag_affinity_mult(copies: int) -> float:
	return BalanceEconomy.tag_affinity_mult(copies)

static func tag_affinity_combo(counts: Dictionary, tags: Array) -> float:
	return BalanceEconomy.tag_affinity_combo(counts, tags)

static func tag_filter_mult(weapon_tags: Array, filter_tags: Array) -> float:
	return BalanceEconomy.tag_filter_mult(weapon_tags, filter_tags)

static func shop_luck_mult(luck: float) -> float:
	return BalanceEconomy.shop_luck_mult(luck)

static func item_tier_weights(luck: float, wave: int) -> Array:
	return BalanceEconomy.item_tier_weights(luck, wave)

static func weighted_pick_index(weights: Array, roll: float) -> int:
	return BalanceEconomy.weighted_pick_index(weights, roll)

static func synergy_thresholds(thresholds: Array, threshold_shift: int = 0) -> Array:
	return BalanceEconomy.synergy_thresholds(thresholds, threshold_shift)

static func synergy_next_threshold(count: int, thresholds: Array, threshold_shift: int = 0) -> int:
	return BalanceEconomy.synergy_next_threshold(count, thresholds, threshold_shift)

static func synergy_level(count: int, thresholds: Array, threshold_shift: int = 0) -> int:
	return BalanceEconomy.synergy_level(count, thresholds, threshold_shift)

static func upgrade_fields() -> Array:
	return BalanceEconomy.upgrade_fields()

# 回合 / 刷怪 / 精英 Boss / 危险度 → BalanceWave
static func wave_duration(wave: int) -> float:
	return BalanceWave.wave_duration(wave)

static func spawn_interval(wave: int) -> float:
	return BalanceWave.spawn_interval(wave)

static func spawn_batch(wave: int, roll: float) -> int:
	return BalanceWave.spawn_batch(wave, roll)

## 批次刷新阈值爬坡（节奏紧凑化）：场上存活 ≤ 此值即刷下一批（W1-3 → 1 / W4-9 → 2 / W10+ → 3）
static func batch_refill_threshold(wave: int) -> int:
	return BalanceWave.batch_refill_threshold(wave)

## 回合内总刷入预算（土豆兄弟式克制）：预算耗尽即停手，场上越打越空
static func wave_spawn_budget(wave: int) -> int:
	return BalanceWave.wave_spawn_budget(wave)

## 动态同屏敌人上限（分批清剿制）
static func max_enemies_cap(wave: int) -> int:
	return BalanceWave.max_enemies_cap(wave)

## 刷怪预算未花完部分的回合末经验补差（减潮不减收入）
static func budget_compensation_exp(shortfall: int, avg_exp: float) -> int:
	return BalanceEconomy.budget_compensation_exp(shortfall, avg_exp)

## 提前清场（敌潮已尽）的回合末余时赏：只给金币，按本回合剩余秒数折
static func early_clear_stones(remaining_secs: float) -> int:
	return BalanceEconomy.early_clear_stones(remaining_secs)

## 普通怪掉落为碎晶的概率（后期稀释金币腿，经验腿不砍；见 BalanceEconomy 碎晶段）
static func gem_shard_chance(wave: int) -> float:
	return BalanceEconomy.gem_shard_chance(wave)

static func enemy_hp_mult(wave: int) -> float:
	return BalanceWave.enemy_hp_mult(wave)

static func enemy_dmg_mult(wave: int) -> float:
	return BalanceWave.enemy_dmg_mult(wave)

## 无尽深层同屏密度倍率（≤20 波恒 1.0，曲线在 BalanceWave）
static func endless_swarm_mult(wave: int) -> float:
	return BalanceWave.endless_swarm_mult(wave)

static func healer_amount(wave: int) -> float:
	return BalanceWave.healer_amount(wave)

## 单只小怪击杀经验（含反割草补偿倍率，曲线在 BalanceWave）
static func mob_kill_exp(exp_reward: int) -> int:
	return BalanceWave.mob_kill_exp(exp_reward)

static func looter_stone_reward(wave: int) -> int:
	return BalanceWave.looter_stone_reward(wave)

static func poison_area_damage(wave: int) -> float:
	return BalanceWave.poison_area_damage(wave)

static func poison_radius(wave: int) -> float:
	return BalanceWave.poison_radius(wave)

static func is_boss_wave(n: int) -> bool:
	return BalanceWave.is_boss_wave(n)

static func is_elite_wave(n: int, endless: bool = false) -> bool:
	return BalanceWave.is_elite_wave(n, endless)

static func boss_hp(wave: int) -> float:
	return BalanceWave.boss_hp(wave)

static func boss_contact_damage(wave: int) -> float:
	return BalanceWave.boss_contact_damage(wave)

static func danger_hp_mult(danger: int) -> float:
	return BalanceWave.danger_hp_mult(danger)

static func danger_dmg_mult(danger: int) -> float:
	return BalanceWave.danger_dmg_mult(danger)

static func danger_count_mult(danger: int) -> float:
	return BalanceWave.danger_count_mult(danger)

# 护甲 / 创伤 / 硬直击退 / 长扑 / 异常状态 / 震退 / 集火 → BalanceCombat
static func armor_reduction(armor: float) -> float:
	return BalanceCombat.armor_reduction(armor)

static func incoming_damage(raw: float, armor: float) -> float:
	return BalanceCombat.incoming_damage(raw, armor)

## 玩家生命读数分档：HUD 血字与金币阁生命徽记同一把尺（0 = 空载，按满血放行）
static func hp_ratio(cur: float, max_v: float) -> float:
	return BalanceCombat.hp_ratio(cur, max_v)

static func hp_is_low(cur: float, max_v: float) -> bool:
	return BalanceCombat.hp_is_low(cur, max_v)

static func hp_is_full(cur: float, max_v: float) -> bool:
	return BalanceCombat.hp_is_full(cur, max_v)

static func trauma_steady_state() -> float:
	return BalanceCombat.trauma_steady_state()

static func trauma_grant(amount: float, budget_left: float) -> float:
	return BalanceCombat.trauma_grant(amount, budget_left)

static func shake_amount(trauma: float) -> float:
	return BalanceCombat.shake_amount(trauma)

static func shake_duration(trauma: float) -> float:
	return BalanceCombat.shake_duration(trauma)

static func charge_reach(peak_speed: float, dash_time: float, brake_time: float) -> float:
	return BalanceCombat.charge_reach(peak_speed, dash_time, brake_time)

static func seg_closest_point(seg_a: Vector2, seg_b: Vector2, p: Vector2) -> Vector2:
	return BalanceCombat.seg_closest_point(seg_a, seg_b, p)

static func stack_burn_dps(current_dps: float, incoming_dps: float) -> float:
	return BalanceCombat.stack_burn_dps(current_dps, incoming_dps)

static func stack_poison_dps(current_dps: float, incoming_dps: float) -> float:
	return BalanceCombat.stack_poison_dps(current_dps, incoming_dps)

static func burn_tick_damage(burn_dps: float, elemental_damage: float, synergy_burn_mult: float = 1.0) -> float:
	return BalanceCombat.burn_tick_damage(burn_dps, elemental_damage, synergy_burn_mult)

static func poison_tick_damage(poison_dps: float, elemental_damage: float) -> float:
	return BalanceCombat.poison_tick_damage(poison_dps, elemental_damage)

static func knock_dir(source: Vector2, enemy_pos: Vector2, player_pos: Vector2) -> Vector2:
	return BalanceCombat.knock_dir(source, enemy_pos, player_pos)

static func focus_fire_mult(recent_hits: int) -> float:
	return BalanceCombat.focus_fire_mult(recent_hits)

static func hit_squash_target(knockback: Vector2, is_crit: bool) -> Vector2:
	return BalanceCombat.hit_squash_target(knockback, is_crit)

# 祭坛灵兽 → BalanceSpiritBeast
static func spirit_beast_max_hp(wave: int) -> float:
	return BalanceSpiritBeast.max_hp_for_wave(wave)

static func spirit_beast_damage(wave: int) -> float:
	return BalanceSpiritBeast.damage_for_wave(wave)

# 藏宝匣（宝箱）：数量 / 三档 / 击数 / 掉落 → BalanceChest
static func chest_count(wave: int, bonus: int) -> int:
	return BalanceChest.chest_count(wave, bonus)

static func chest_tier_weights(quality: float, luck: float) -> Array[float]:
	return BalanceChest.tier_weights(quality, luck)

static func chest_break_hits(break_bonus: int) -> int:
	return BalanceChest.break_hits(break_bonus)

static func chest_tier_scale(tier: int) -> float:
	return BalanceChest.tier_scale(tier)

static func chest_tier_name(tier: int) -> String:
	return BalanceChest.tier_name(tier)

static func chest_reward(tier: int) -> Dictionary:
	return BalanceChest.reward_of(tier)

static func chest_jade_fallback_reward() -> Dictionary:
	return BalanceChest.jade_fallback_reward()

static func chest_reward_scaled(reward: Dictionary, mult: float) -> Dictionary:
	return BalanceChest.scale_reward(reward, mult)

static func danger_heal_chance_mult(danger: int) -> float:
	return BalanceChest.danger_heal_chance_mult(danger)

# 索敌 / 藏宝匣 / 折算 / 御灵 / 神识分流 → BalanceTargeting
static func elliptical_distance(offset: Vector2, y_ratio: float = TARGETING_ELLIPSE_Y_RATIO) -> float:
	return BalanceTargeting.elliptical_distance(offset, y_ratio)

static func is_in_viewport(pos: Vector2, center: Vector2, half_extents: Vector2 = VIEWPORT_SAFE_HALF_EXTENTS) -> bool:
	return BalanceTargeting.is_in_viewport(pos, center, half_extents)

static func assign_weapon_targets(weapons_info: Array, enemies_info: Array, danger_radius: float = DANGER_ZONE_RADIUS) -> Array:
	return BalanceTargeting.assign_weapon_targets(weapons_info, enemies_info, danger_radius)

static func assign_targets_with_chests(weapons_info: Array, enemies_info: Array, chests_info: Array) -> Array:
	return BalanceTargeting.assign_targets_with_chests(weapons_info, enemies_info, chests_info)

static func weapon_stat_bonus(stat_scalings: Dictionary, player_stats: Dictionary, star: int = 1) -> float:
	return BalanceTargeting.weapon_stat_bonus(stat_scalings, player_stats, star)

## 属性加伤的逐项明细（伤害单位），UI 的「属性加伤账单」读它，总额即上面那条
static func weapon_stat_bonus_parts(stat_scalings: Dictionary, player_stats: Dictionary, star: int = 1) -> Dictionary:
	return BalanceTargeting.weapon_stat_bonus_parts(stat_scalings, player_stats, star)

static func stat_scaling_label(key: String) -> String:
	return BalanceTargeting.stat_scaling_label(key)

static func upgrade_benefits_weapon(apply: Dictionary, w_id: String) -> bool:
	return BalanceTargeting.upgrade_benefits_weapon(apply, w_id)

## 这条加点通过哪些属性链路强化某件武器（受益判定同源，只多回一份「为什么是它」）
static func upgrade_benefit_reasons(apply: Dictionary, w_id: String) -> Array[String]:
	return BalanceTargeting.upgrade_benefit_reasons(apply, w_id)

static func spirit_orbit_angular_speed(
	base_speed: float = SPIRIT_BASE_ANGULAR_SPEED,
	attack_speed_mult: float = 1.0,
	synergy_haste_mult: float = 1.0,
	in_combat: bool = false,
	max_star: int = 1,
	orb_count: int = 1
) -> float:
	return BalanceTargeting.spirit_orbit_angular_speed(base_speed, attack_speed_mult, synergy_haste_mult, in_combat, max_star, orb_count)

static func compute_spirit_orbit(
	orb_angles: Array,
	enemies_info: Array,
	base_radius: float = SPIRIT_BASE_RADIUS,
	min_radius: float = SPIRIT_MIN_RADIUS,
	max_reach: float = SPIRIT_MAX_REACH
) -> Dictionary:
	return BalanceTargeting.compute_spirit_orbit(orb_angles, enemies_info, base_radius, min_radius, max_reach)

static func multi_weapon_damage_mult(slot_count: int, drone_count: int = 0) -> float:
	return BalanceTargeting.multi_weapon_damage_mult(slot_count, drone_count)

## 环绕灵宝接触结算占空比（按星级）：sustained_single_dps 与平衡仿真共用的实伤折算尺
static func spirit_contact_duty(star: int = 1) -> float:
	return BalanceTargeting.spirit_contact_duty(star)
