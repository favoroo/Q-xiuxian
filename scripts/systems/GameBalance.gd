class_name GameBalance
extends RefCounted

## 数值公式集中地：全部 static 纯函数 —— 不读 autoload、不碰节点、不调全局 randf()。
## 两条硬性约束（破掉任何一条，这层就白建了）：
##   1. 需要随机数的地方由调用方传入 rng 或已经抽好的 roll，这样单测可以固定种子做确定性断言；
##   2. 入参出参只用值类型，任何依赖 Player / GameManager 状态的判断都留在调用方。
## 配套单测：tests/UnitRunner.gd（headless，不加载任何场景）。

# ---------------- 经验 / 等级 ----------------

const EXP_FIRST_LEVEL := 10   ## 1→2 级所需修为
const EXP_GROWTH := 1.35      ## 每级需求的环比
const EXP_FLAT := 5           ## 每级需求的固定加值

## 下一级所需修为（截断方式与历史实现保持一致）
static func exp_to_next(prev_needed: int) -> int:
	return int(float(prev_needed) * EXP_GROWTH) + EXP_FLAT

# ---------------- 护甲 / 受伤 ----------------

const ARMOR_COEF := 0.08      ## 减伤 = 1 - 1/(1+护甲×0.08)
const DAMAGE_FLOOR := 1.0     ## 实伤保底，防止高护甲把伤害抹成 0

## 面板用的减伤比例（0~1）。注意它不含 DAMAGE_FLOOR，高护甲打小伤害时面板会略优于实际
static func armor_reduction(armor: float) -> float:
	return 1.0 - (1.0 / (1.0 + maxf(0.0, armor) * ARMOR_COEF))

## 实际扣血。Player 与 HUD 从此共用同一条公式，不再各写一套
static func incoming_damage(raw: float, armor: float) -> float:
	return maxf(DAMAGE_FLOOR, raw / (1.0 + maxf(0.0, armor) * ARMOR_COEF))

# ---------------- 波次与刷怪 ----------------

const WAVE_DURATION_BASE := 20.0
const WAVE_DURATION_PER_WAVE := 2.0
const WAVE_DURATION_MAX := 60.0
const SPAWN_INTERVAL_BASE := 1.35
const SPAWN_INTERVAL_MIN := 0.30
const SPAWN_INTERVAL_PER_WAVE := 0.055
const SPAWN_BATCH_EVERY_WAVES := 4.0      ## 每多 4 波，一轮多刷 1 只
const SPAWN_BATCH_BONUS_CHANCE := 0.4     ## 额外一只的概率
const ENEMY_HP_PER_WAVE := 0.18
const ENEMY_DMG_PER_WAVE := 0.10
const ENEMY_STAT_VARIANCE := 0.10            ## 敌人属性 ±10% 随机浮动（同种怪个体差异）
const ELITE_STONE_BONUS := 25             ## 精英击杀额外灵石

static func wave_duration(wave: int) -> float:
	return minf(WAVE_DURATION_BASE + float(maxi(wave, 1)) * WAVE_DURATION_PER_WAVE, WAVE_DURATION_MAX)

## 刷怪间隔随波次收紧，到下限后不再变快（否则后期同屏爆量）
static func spawn_interval(wave: int) -> float:
	return maxf(SPAWN_INTERVAL_MIN, SPAWN_INTERVAL_BASE - float(maxi(wave, 1)) * SPAWN_INTERVAL_PER_WAVE)

## 一轮刷几只。roll 必须由调用方给（如 GameManager.rng.randf()）
static func spawn_batch(wave: int, roll: float) -> int:
	return 1 + int(float(maxi(wave, 1)) / SPAWN_BATCH_EVERY_WAVES) + (1 if roll < SPAWN_BATCH_BONUS_CHANCE else 0)

static func enemy_hp_mult(wave: int) -> float:
	return 1.0 + float(maxi(wave, 1) - 1) * ENEMY_HP_PER_WAVE

static func enemy_dmg_mult(wave: int) -> float:
	return 1.0 + float(maxi(wave, 1) - 1) * ENEMY_DMG_PER_WAVE

# ---------------- 精英 / Boss 波（固定关卡） ----------------

const ELITE_WAVES := [5, 15]             ## 精英波：铁甲魔傀小头目
const BOSS_WAVES := [10, 20]             ## 固定 Boss 关卡：血条上屏的魔君
const BOSS_HP_BASE := 2800.0             ## Boss 基础气血（约为精英的 5 倍）
const BOSS_CONTACT_BASE := 24.0          ## Boss 基础接触伤害
const BOSS_ATTACK_INTERVAL := 4.6        ## 特殊攻击循环间隔（秒）
const BOSS_RING_COUNT := 16              ## 环弹齐射数量
const BOSS_RING_COUNT_P2 := 8            ## 二阶段环弹增量
const BOSS_RING_DMG_MULT := 0.55         ## 环弹伤害 = 接触伤害 × 系数
const BOSS_BOLT_SPEED := 235.0           ## 环弹飞行速度
const BOSS_BOLT_SCALE := 1.5             ## 环弹视觉/碰撞放大
const BOSS_SLAM_WINDUP := 0.9            ## 震地冲击预警时长
const BOSS_SLAM_RADIUS := 175.0          ## 震地冲击半径
const BOSS_SLAM_DMG_MULT := 1.35         ## 震地伤害 = 接触伤害 × 系数
const BOSS_SUMMON_COUNT := 3             ## 召唤妖群数量
const BOSS_SUMMON_CAP := 26              ## 场面敌人达到该数后召唤不再生效
const BOSS_PHASE2_AT := 0.5              ## 二阶段触发血线（≤50%）
const BOSS_PHASE2_INTERVAL_MULT := 0.7   ## 二阶段攻击间隔缩短倍率
const BOSS_PHASE2_SPEED_MULT := 1.25     ## 二阶段移速提升
const BOSS_KNOCKBACK_RESIST := 0.18      ## Boss 击退系数（越低越推不动）
const BOSS_STONE_REWARD := 150           ## Boss 击杀额外灵石奖励

## 固定 Boss 波：10/20 波，20 波后（无尽）每 10 波再逢魔君
static func is_boss_wave(n: int) -> bool:
	return n in BOSS_WAVES or (n > BOSS_WAVES.max() and n % 10 == 0)

## 精英波：5/15 波；无尽模式 20 波后每 3 波一次（Boss 波让位）
static func is_elite_wave(n: int, endless: bool = false) -> bool:
	return n in ELITE_WAVES or (endless and n > BOSS_WAVES.max() and n % 3 == 0 and not is_boss_wave(n))

## Boss 气血：与普通敌人同一条 hp 曲线，靠基础值拉开厚度差距
static func boss_hp(wave: int) -> float:
	return BOSS_HP_BASE * enemy_hp_mult(wave)

static func boss_contact_damage(wave: int) -> float:
	return ceilf(BOSS_CONTACT_BASE * enemy_dmg_mult(wave))

# ---------------- 商店定价 ----------------

const WEAVE_WAVE_STEP := 2      ## 法器每波加价
const REROLL_BASE := 2
const REROLL_WAVE_STEP := 1     ## 重掷价随波次上升
const REROLL_COUNT_STEP := 2    ## 本波每重掷一次再涨

static func weapon_price(base: int, wave: int, price_mult: float) -> int:
	return int(float(base + (maxi(wave, 1) - 1) * WEAVE_WAVE_STEP) * price_mult)

static func potion_price(base: int, wave: int, price_mult: float) -> int:
	return int(float(base + maxi(wave, 1)) * price_mult)

static func reroll_cost(wave: int, reroll_count: int, price_mult: float) -> int:
	return int(float(REROLL_BASE + maxi(wave, 1) * REROLL_WAVE_STEP + maxi(reroll_count, 0) * REROLL_COUNT_STEP) * price_mult)

# ---------------- 灵韵（波末无偿发放并自我复利）----------------

const HARVEST_GROWTH := 1.05

static func harvest_gain(harvest: float) -> int:
	return int(round(harvest))

## 复利只涨到 growth_wave_cap 波为止（之后持平，防止后期指数爆炸）
static func harvest_next(harvest: float, wave: int, growth_wave_cap: int) -> float:
	if wave < growth_wave_cap:
		return harvest * HARVEST_GROWTH
	return harvest

# ---------------- 悟道三选一的稀有度权重 ----------------

const RARITY_EPIC_BASE := 10.0
const RARITY_RARE := 30.0
const RARITY_TOTAL := 100.0
const RARITY_COMMON_FLOOR := 10.0
const LUCK_EPIC_PER_POINT := 1.0

## 福缘每点抬高仙品权重 1，差额从凡品里扣 —— 三档之和恒定，不会整体变稀有
static func rarity_weights(luck: float) -> Dictionary:
	var epic: float = RARITY_EPIC_BASE + maxf(0.0, luck) * LUCK_EPIC_PER_POINT
	var common: float = maxf(RARITY_COMMON_FLOOR, RARITY_TOTAL - RARITY_RARE - epic)
	return {"common": common, "rare": RARITY_RARE, "epic": epic}

# ---------------- 货架抽取 ----------------

const POTION_CHANCE := 0.22            ## 每个货架位出回气丹的概率
const TAG_AFFINITY_MIN_COPIES := 2     ## 同流派持有数达到该值才触发亲和
const TAG_AFFINITY_MULT := 2.5
const LUCK_SHOP_PER_POINT := 0.01      ## 福缘对法器权重的加法系数
const MAIN_TAG_PITY_WAVES := 2         ## 连续几波没出主流派就强制塞一件
const TAG_FILTER_BONUS := 4.0          ## 流派偏好软加权：命中角色限定 tag 的法器权重倍率
const TAG_FILTER_LEAK := 0.2           ## 未命中限定 tag 的法器保留的小权重（漏出率）

## 某流派的亲和倍率：持有不足 MIN_COPIES 件时恒为 1
static func tag_affinity_mult(copies: int) -> float:
	return TAG_AFFINITY_MULT if copies >= TAG_AFFINITY_MIN_COPIES else 1.0

## 流派偏好的软加权：角色限定流派非空时，命中 tag 的法器 ×BONUS，其余保留 LEAK 小权重。
## 替代旧版硬过滤——硬过滤在池中只有 1 件同名法器时会让货架坍缩为单一武器。
static func tag_filter_mult(weapon_tags: Array, filter_tags: Array) -> float:
	if filter_tags.is_empty():
		return 1.0
	for t in weapon_tags:
		if t in filter_tags:
			return TAG_FILTER_BONUS
	return TAG_FILTER_LEAK

static func shop_luck_mult(luck: float) -> float:
	return 1.0 + maxf(0.0, luck) * LUCK_SHOP_PER_POINT

## 权重抽奖：给定等长权重表与 [0,1) 的 roll，返回命中下标；权重全 0 或表空返回 0。
## 用「累加到 target 之前」的判定而不是「减到 ≤0」，否则权重为 0 的项在 roll 恰好为 0 时会被选中。
static func weighted_pick_index(weights: Array, roll: float) -> int:
	if weights.is_empty():
		return 0
	var total := 0.0
	for w in weights:
		total += float(w)
	if total <= 0.0:
		return 0
	var target: float = clampf(roll, 0.0, 0.999999) * total
	var acc := 0.0
	for i in range(weights.size()):
		acc += float(weights[i])
		if target < acc:
			return i
	return weights.size() - 1

# ---------------- 流派羁绊 ----------------

## 羁绊档位：持有 count 件时达到的等级（0 = 未激活）。
## threshold_shift 是角色对门槛的下移量（符阵灵童的御灵羁绊门槛），下移后最低只到 1 件。
static func synergy_level(count: int, thresholds: Array, threshold_shift: int = 0) -> int:
	var level := 0
	for i in range(thresholds.size()):
		var th := maxi(1, int(thresholds[i]) - threshold_shift)
		if count >= th:
			level = i + 1
	return level

# ---------------- 加点字段白名单 ----------------

## GameManager.apply_upgrade() 认得的字段名。数据表写了不在这里的键 = 静默无效，
## 单测靠它把拼写错误挡在编译期之外。
static func upgrade_fields() -> Array:
	return [
		"weapon_damage_mult", "attack_speed_mult_mul", "armor", "move_speed_mult",
		"attack_range_mult", "pickup_range_mult", "hp_regen", "crit_rate", "crit_mult",
		"dodge", "lifesteal", "luck", "harvest", "spirit_stones", "max_hp", "hp_heal",
	]

# ---------------- 多武器智能索敌与分流分配 ----------------

const DANGER_ZONE_RADIUS := 75.0  ## 贴身危急警戒半径（防暴毙优先集火区）

## 为多把在场法器智能分配攻击目标（纯函数：无副作用、无节点依赖、确定性回归）
## weapons_info: Array[Dictionary]，每项包含 { "base_angle": float, "range": float, "prev_id": int }
## enemies_info: Array[Dictionary]，每项包含 { "id": int, "dist": float, "angle": float }
## 返回 Array[int]，长度等于 weapons_info.size()，每项对应 enemies_info 的下标（-1 为无目标）
static func assign_weapon_targets(weapons_info: Array, enemies_info: Array, danger_radius: float = DANGER_ZONE_RADIUS) -> Array:
	var w_count := weapons_info.size()
	var e_count := enemies_info.size()
	var result: Array = []
	for i in range(w_count):
		result.append(-1)

	if w_count == 0 or e_count == 0:
		return result

	# 1. 若仅单一目标，所有在射程内的武器集中集火该目标（集火模式）
	if e_count == 1:
		var single_dist: float = float(enemies_info[0].get("dist", 0.0))
		for i in range(w_count):
			var w_range: float = float(weapons_info[i].get("range", 150.0))
			if single_dist <= w_range:
				result[i] = 0
		return result

	var assigned_counts := {}
	for e_idx in range(e_count):
		assigned_counts[e_idx] = 0

	# 2. 贴身危急威胁优先防守：
	# 若有敌人突破到贴身危险区（<= danger_radius），优先为每个贴身敌人分配角度最契合的武器解围
	var danger_enemy_indices: Array[int] = []
	for e_idx in range(e_count):
		var d: float = float(enemies_info[e_idx].get("dist", 9999.0))
		if d <= danger_radius:
			danger_enemy_indices.append(e_idx)

	for danger_e_idx in danger_enemy_indices:
		var e_ang: float = float(enemies_info[danger_e_idx].get("angle", 0.0))
		var e_dist: float = float(enemies_info[danger_e_idx].get("dist", 0.0))
		var best_w_idx := -1
		var best_diff := 999.0
		for w_idx in range(w_count):
			if result[w_idx] != -1:
				continue
			var w_range: float = float(weapons_info[w_idx].get("range", 150.0))
			if e_dist > w_range:
				continue
			var w_ang: float = float(weapons_info[w_idx].get("base_angle", 0.0))
			var diff := absf(wrapf(e_ang - w_ang, -PI, PI))
			if diff < best_diff:
				best_diff = diff
				best_w_idx = w_idx
		if best_w_idx != -1:
			result[best_w_idx] = danger_e_idx
			assigned_counts[danger_e_idx] = int(assigned_counts.get(danger_e_idx, 0)) + 1

	# 3. 对其余武器进行多向扇区分流分配：
	# 综合考量目标占用惩罚、扇区角度契合度、距离权重及目标粘滞性
	for w_idx in range(w_count):
		if result[w_idx] != -1:
			continue

		var w_info: Dictionary = weapons_info[w_idx]
		var w_range: float = float(w_info.get("range", 150.0))
		var w_base_angle: float = float(w_info.get("base_angle", 0.0))
		var prev_id: int = int(w_info.get("prev_id", 0))

		var best_e_idx := -1
		var lowest_cost := 9999999.0

		for e_idx in range(e_count):
			var e_info: Dictionary = enemies_info[e_idx]
			var e_dist: float = float(e_info.get("dist", 9999.0))
			if e_dist > w_range:
				continue

			var e_ang: float = float(e_info.get("angle", 0.0))
			var e_id: int = int(e_info.get("id", 0))
			var count_assigned: int = int(assigned_counts.get(e_idx, 0))
			var angle_diff := absf(wrapf(e_ang - w_base_angle, -PI, PI))

			# 成本函数：
			# - 已被分配惩罚（500 分/武器）：强烈驱使武器挑选未被覆盖的不同方向敌人，防止 Overkill
			# - 扇区契合度（0~120 分）：使槽位方位更顺路的武器迎战该侧敌人
			# - 相对距离（0~80 分）：同方向优先打击距离更近的敌人
			# - 目标粘滞奖励（-40 分）：当前已锁定敌人拥有微弱粘滞优势，防止帧间目标抖动
			var stickiness_bonus := 40.0 if (prev_id != 0 and prev_id == e_id) else 0.0
			var cost: float = float(count_assigned) * 500.0 \
				+ (angle_diff / PI) * 120.0 \
				+ (e_dist / maxf(1.0, w_range)) * 80.0 \
				- stickiness_bonus

			if cost < lowest_cost:
				lowest_cost = cost
				best_e_idx = e_idx

		if best_e_idx != -1:
			result[w_idx] = best_e_idx
			assigned_counts[best_e_idx] = int(assigned_counts.get(best_e_idx, 0)) + 1

	return result

# ---------------- 武器属性受益折算（仿土豆兄弟属性加成） ----------------

## 纯函数：根据武器设定的 stat_scalings 与玩家当前属性状态，计算出附加在基础伤害上的数值增量
## stat_scalings: { "armor": 3.5, "crit_rate": 40.0, ... }
## player_stats: { "armor": float, "crit_rate": float, "hp_regen": float, ... }
## star: 星级，每升一星该法器的属性转化效率提升 25%（★1: 1.0x, ★2: 1.25x, ★3: 1.5x）
static func weapon_stat_bonus(stat_scalings: Dictionary, player_stats: Dictionary, star: int = 1) -> float:
	if stat_scalings.is_empty():
		return 0.0
	var bonus: float = 0.0
	var star_mult: float = 1.0 + 0.25 * float(clampi(star, 1, 3) - 1)
	for key in stat_scalings.keys():
		var coef: float = float(stat_scalings[key])
		var val: float = 0.0
		match key:
			"armor":
				val = maxf(0.0, float(player_stats.get("armor", 0.0)))
			"max_hp_bonus":
				val = maxf(0.0, float(player_stats.get("max_hp", 100.0)) - 100.0)
			"hp_regen":
				val = maxf(0.0, float(player_stats.get("hp_regen", 0.0)))
			"lifesteal":
				val = maxf(0.0, float(player_stats.get("lifesteal", 0.0)))
			"crit_rate":
				val = maxf(0.0, float(player_stats.get("crit_rate", 0.05)) - 0.05)
			"crit_mult_bonus":
				val = maxf(0.0, float(player_stats.get("crit_mult", 1.5)) - 1.5)
			"move_speed_bonus":
				val = maxf(0.0, float(player_stats.get("move_speed_mult", 1.0)) - 1.0)
			"cdr_bonus":
				val = maxf(0.0, 1.0 - float(player_stats.get("attack_speed_mult", 1.0)))
			"damage_bonus":
				val = maxf(0.0, float(player_stats.get("weapon_damage_mult", 1.0)) - 1.0)
			"range_bonus":
				val = maxf(0.0, float(player_stats.get("attack_range_mult", 1.0)) - 1.0)
		bonus += val * coef
	return bonus * star_mult

static func stat_scaling_label(key: String) -> String:
	match key:
		"armor": return "护甲"
		"max_hp_bonus": return "额外气血"
		"hp_regen": return "气血回复"
		"lifesteal": return "吸血率"
		"crit_rate": return "额外会心"
		"crit_mult_bonus": return "额外暴伤"
		"move_speed_bonus": return "移速加成"
		"cdr_bonus": return "掐诀神速"
		"damage_bonus": return "法伤加成"
		"range_bonus": return "范围加成"
	return key

