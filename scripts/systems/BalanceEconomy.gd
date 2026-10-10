class_name BalanceEconomy
extends RefCounted

## 经济与成长数值：经验曲线、商店定价、灵韵复利、残丹化灵、稀有度与货架抽取、
## 法宝档位权重、流派羁绊档位、加点字段白名单。全部 static 纯函数。
## 与 GameBalance 同规约：不读 autoload、不碰节点、不调全局 randf()，随机由调用方传 roll。

# ---------------- 经验 / 等级 ----------------

const EXP_FIRST_LEVEL := 10   ## 1→2 级所需修为
const EXP_GROWTH := 1.35      ## 每级需求的环比
const EXP_FLAT := 5           ## 每级需求的固定加值

## 下一级所需修为（截断方式与历史实现保持一致）
static func exp_to_next(prev_needed: int) -> int:
	return int(float(prev_needed) * EXP_GROWTH) + EXP_FLAT

# ---------------- 商店定价 ----------------

const WEAVE_WAVE_STEP := 2      ## 法器每波加价
const ITEM_WAVE_STEP := 2       ## 法宝每波加价（与法器同一步调）
const REROLL_BASE := 2
const REROLL_WAVE_STEP := 1     ## 重掷价随波次上升
const REROLL_COUNT_STEP := 2    ## 本波每重掷一次再涨

static func weapon_price(base: int, wave: int, price_mult: float) -> int:
	return int(float(base + (maxi(wave, 1) - 1) * WEAVE_WAVE_STEP) * price_mult)

## 法宝（被动道具）定价：与法器同一公式，基准价来自 ItemData 按档位定
static func item_price(base: int, wave: int, price_mult: float) -> int:
	return int(float(base + (maxi(wave, 1) - 1) * ITEM_WAVE_STEP) * price_mult)

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

# ---------------- 残丹化灵（波末没贴上去吃掉的回复珠）----------------

## 回不上的那截气血折成灵石：每点 0.8。钉在藏宝匣另一路上 —— 满口 18 点 ×0.8 ≈ 14，
## 与「约四成掉 3 颗金灵石（各 5 修为/灵石）」同档，砸匣子两条路不等价也不悬殊。
const HEAL_OVERFLOW_STONE_PER_HP := 0.8
## 单颗封顶：气血上限越高、15% 口越大，不封顶就滚成巨款
const HEAL_OVERFLOW_STONE_CAP := 15

## 溢出气血 → 灵石数（0 溢出就是 0，负数按 0 收）
static func heal_overflow_stones(overflow_hp: float) -> int:
	if overflow_hp <= 0.0:
		return 0
	return clampi(int(round(overflow_hp * HEAL_OVERFLOW_STONE_PER_HP)), 0, HEAL_OVERFLOW_STONE_CAP)

# ---------------- 悟道候选的稀有度权重 ----------------

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

const POTION_CHANCE := 0.15            ## 每个货架位出回气丹的概率
const ITEM_CHANCE := 0.30              ## 每个货架位出法宝（被动道具）的概率
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

# ---------------- 法宝（被动道具）档位权重 ----------------

## 各档位最早出现的波次（下标 1~4 对应 tier 1~4，0 为占位）：高档法宝随波次解锁
const ITEM_TIER_WAVES := [0, 1, 4, 9, 14]
const ITEM_TIER_BASE := [0.0, 60.0, 30.0, 9.0, 1.0]   ## 无福缘时的档位基础权重

## 法宝档位权重：返回长度 4 的数组（tier1~4）。福缘抬高高档权重（差额从凡品扣），
## 未到解锁波次的档位权重清零；凡品有权重地板防归零
static func item_tier_weights(luck: float, wave: int) -> Array:
	var l := maxf(0.0, luck)
	var w := [ITEM_TIER_BASE[1], ITEM_TIER_BASE[2], ITEM_TIER_BASE[3], ITEM_TIER_BASE[4]]
	w[3] += l * 0.15
	w[2] += l * 0.35
	w[0] = maxf(10.0, w[0] - l * 0.5)
	for i in range(4):
		if maxi(wave, 1) < int(ITEM_TIER_WAVES[i + 1]):
			w[i] = 0.0
	return w

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
		"xp_gain_mult", "knockback_mult", "free_rerolls", "elite_damage", "shop_price_mul",
		"melee_damage", "ranged_damage", "elemental_damage", "engineering_damage",
		"element_damage_all", "element_damage_metal", "element_damage_wood",
		"element_damage_water", "element_damage_fire", "element_damage_earth",
		"bonus_pierce", "thorns",
	]
