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

## 灵兽定价：基准价来自 PetData，与法宝同波次成长步长
static func pet_price(base: int, wave: int, price_mult: float) -> int:
	return int(float(base + (maxi(wave, 1) - 1) * ITEM_WAVE_STEP) * price_mult)

static func potion_price(base: int, wave: int, price_mult: float) -> int:
	return int(float(base + maxi(wave, 1)) * price_mult)

## 回气丹回复量：按气血上限的比例。货架卡上印的数、气血详情卡里说的数、ShopSystem 真喂给
## heal() 的数，三处都从这一个出口拿（2026-10-11 用户：「商店界面也要显示血量，
## 不然也不知道回复道具要不要买」——要能判断，卡面上的数就必须是真会兑现的那个数）。
const POTION_HEAL_RATIO := 0.5

static func potion_heal_amount(max_hp: float) -> float:
	return maxf(0.0, max_hp) * POTION_HEAL_RATIO

## 这一口现在实际回得上多少：heal() 会把超出上限的那截丢掉，卡面上就不许把它算进读数。
## 满血时是 0 —— 货架卡据此出红字「+0」，买前就看得见「这钱白花」。
static func potion_effective_heal(max_hp: float, cur_hp: float) -> float:
	return minf(potion_heal_amount(max_hp), maxf(0.0, max_hp - cur_hp))

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

# ---------------- 妖潮预算补差 ----------------

## 波内总刷入预算（BalanceWave.wave_spawn_budget）收紧后，被预算拦下的怪不再掉宝石，
## 经验收入随之下滑。波末按「未刷出只数 × 均值」折成经验找平，商店/加点购买力不变。
## 均值优先用本波实际刷出敌人的 exp_reward 均值（WaveSpawner 现场统计），
## 一只都没刷出来的极端波次才落兜底值。
const BUDGET_COMP_EXP_FALLBACK := 2.0

## 补差经验 = 未刷出只数 × 每只期望经验（未刷出 ≤0 就是 0）
static func budget_compensation_exp(shortfall: int, avg_exp: float) -> int:
	if shortfall <= 0:
		return 0
	var eff_avg := avg_exp if avg_exp > 0.0 else BUDGET_COMP_EXP_FALLBACK
	return int(round(float(shortfall) * eff_avg))

# ---------------- 提前清场余时赏 ----------------

## 一波的结束条件有两条（WaveSpawner._process_fight）：表走完，或「妖潮已尽」——本波刷怪预算
## 全部刷入且场上再无活妖。后者就是用户 2026-10-12 的口径「提前杀完还在干等」：预算制下第 7 波
## 约 22s 就把 39 只刷完，之后场地是空的，只能看着表再走二十几秒。
## 提前收尾省下的那截时间按秒折成金币，余得越多给得越多。
## 只给金币、不给修为：与「收益」那条金币+经验双入账区分开，免得提前清场顺手把升级也加速。
## 量级压在「一点点」：一波击杀进项约 2~5 枚/秒，余时赏 1 枚/秒 ≈ 其两到四成；封顶 20 枚 ⇒
## 后期就算提前 40s 清场也就多拿 20，不会把经济顶歪（一波商店货 25~90 枚）。
const EARLY_CLEAR_STONES_PER_SEC := 1.0
const EARLY_CLEAR_STONES_MAX := 20

## 余时赏金币数（纯函数）：余秒向下取整 × 每秒档位，封顶；余秒 ≤0 就是 0（表走完不给钱）
static func early_clear_stones(remaining_secs: float) -> int:
	if remaining_secs <= 0.0:
		return 0
	var secs := int(floor(remaining_secs))
	if secs <= 0:
		return 0
	return mini(int(round(float(secs) * EARLY_CLEAR_STONES_PER_SEC)), EARLY_CLEAR_STONES_MAX)

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
const PET_CHANCE := 0.12               ## 每个货架位出随行灵兽的概率
const TAG_AFFINITY_MIN_COPIES := 2     ## 同流派持有数达到该值才触发亲和（第一档）
const TAG_AFFINITY_MULT_L1 := 2.0      ## 梯度亲和第一档：持有 ≥MIN_COPIES 件 → ×L1
const TAG_AFFINITY_TIER2_COPIES := 4   ## 梯度亲和第二档门槛：持有 ≥4 件 → ×L2（深专精吸力）
const TAG_AFFINITY_MULT_L2 := 3.0
const TAG_AFFINITY_COMBO_DAMP := 0.5   ## 双流派共鸣：第二流派的亲和按该比例折算后叠加
const LUCK_SHOP_PER_POINT := 0.01      ## 福缘对法器权重的加法系数
const MAIN_TAG_PITY_WAVES := 2         ## 连续几波没出主流派就强制塞一件
const TAG_FILTER_BONUS := 4.0          ## 流派偏好软加权：命中角色限定 tag 的法器权重倍率
const TAG_FILTER_LEAK := 0.2           ## 未命中限定 tag 的法器保留的小权重（漏出率）

## 梯度亲和倍率：持有不足 MIN_COPIES 件时恒为 1；≥4 件进入第二档深专精吸力
static func tag_affinity_mult(copies: int) -> float:
	if copies < TAG_AFFINITY_MIN_COPIES:
		return 1.0
	return TAG_AFFINITY_MULT_L2 if copies >= TAG_AFFINITY_TIER2_COPIES else TAG_AFFINITY_MULT_L1

## 双流派共鸣：法器同时命中多个已激活亲和的流派（如剑系∩金系）时，
## 最高档亲和全额生效，其余已激活流派按 COMBO_DAMP 半价叠加——
## 玩家双修两流派后，交叉法器权重反超单流派，货架会主动把"正想要的那把"喂过来。
static func tag_affinity_combo(counts: Dictionary, tags: Array) -> float:
	var best := 1.0
	var second := 1.0
	for t in tags:
		var m := tag_affinity_mult(int(counts.get(t, 0)))
		if m <= 1.0:
			continue
		if m > best:
			second = best
			best = m
		elif m > second:
			second = m
	return best * (1.0 + (second - 1.0) * TAG_AFFINITY_COMBO_DAMP)

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

## 门槛下移后的阶梯表：逐档 -shift，下移后最低只到 1 件。
## 「角色把某系门槛降低」这件事的唯一折算口——档位结算、卡面进度、徽记读数、推荐打分都必须走它，
## 任何一处直接拿原表 thresholds 比大小，门槛 -1 的角色就会看到一套差一件的假进度。
static func synergy_thresholds(thresholds: Array, threshold_shift: int = 0) -> Array:
	var out: Array = []
	for th in thresholds:
		out.append(maxi(1, int(th) - threshold_shift))
	return out

## 下一档门槛（0 = 已到满档）：卡面「n/next」与「临门一档」高亮取这一个数
static func synergy_next_threshold(count: int, thresholds: Array, threshold_shift: int = 0) -> int:
	for th in synergy_thresholds(thresholds, threshold_shift):
		if count < int(th):
			return int(th)
	return 0

## 羁绊档位：持有 count 件时达到的等级（0 = 未激活）。
## threshold_shift 是角色对门槛的下移量（驯兽师的御灵羁绊门槛），下移后最低只到 1 件。
static func synergy_level(count: int, thresholds: Array, threshold_shift: int = 0) -> int:
	var level := 0
	var ths := synergy_thresholds(thresholds, threshold_shift)
	for i in range(ths.size()):
		if count >= int(ths[i]):
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
			"chest_count", "chest_quality", "chest_break",
			"pet_damage_mult", "pet_effect_mult", "pet_cooldown_mult_mul", "pet_slots",
		]
