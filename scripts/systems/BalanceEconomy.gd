class_name BalanceEconomy
extends RefCounted

## 经济与成长数值：经验曲线、商店定价、收益复利、残丹化灵、稀有度与货架抽取、
## 道具档位权重、流派羁绊档位、加点字段白名单。全部 static 纯函数。
## 与 GameBalance 同规约：不读 autoload、不碰节点、不调全局 randf()，随机由调用方传 roll。

# ---------------- 经验 / 等级 ----------------

const EXP_FIRST_LEVEL := 20   ## 1→2 级所需经验（2026-10-22 由 10 上调：W1 收入约 50 经验，10 会让开局一波连升 3 级）
const EXP_GROWTH := 1.28      ## 每级需求的环比（2026-10-22 由 1.42 下调：刷怪收入线性增长，1.42 指数门槛导致中后期连干 3~4 波不升级）
const EXP_FLAT := 12          ## 每级需求的固定加值（2026-10-22 由 6 上调，配合低环比保住后期门槛）

## 下一级所需经验（截断方式与历史实现保持一致）
static func exp_to_next(prev_needed: int) -> int:
	return int(float(prev_needed) * EXP_GROWTH) + EXP_FLAT

# ---------------- 商店定价 ----------------

const WEAVE_WAVE_STEP := 2      ## 武器每回合加价
const ITEM_WAVE_STEP := 2       ## 道具每回合加价（与武器同一步调）
const REROLL_BASE := 2
const REROLL_WAVE_STEP := 1             ## 重掷价随回合上升
const REROLL_COUNT_WAVE_SCALE := 0.4    ## 本回合每重掷一次的递增量 = 波次 × 0.4（至少 1），对齐土豆兄弟重掷曲线

static func weapon_price(base: int, wave: int, price_mult: float) -> int:
	return int(float(base + (maxi(wave, 1) - 1) * WEAVE_WAVE_STEP) * price_mult)

## 货架武器的实际售价：★1 就是 weapon_price；★2 起的直购成品按级乘 STAR2_PRICE_MULT。
## ★2 卖 2.7×（三合一平价是 3×）：省掉两次追梦刷新与两个栏位，但不至于冲垮 ★1 材料轨道。
## ★3 起货架不卖，公式仍按 2.7^(星-1) 兜底，留给作者模式/以后调参用。
const STAR2_PRICE_MULT := 2.7

static func weapon_offer_price(base: int, wave: int, star: int, price_mult: float) -> int:
	var p := float(weapon_price(base, wave, price_mult))
	if star >= 2:
		p *= pow(STAR2_PRICE_MULT, float(clampi(star, 2, WeaponData.MAX_STAR) - 1))
	return maxi(1, int(round(p)))

## 道具（被动道具）定价：与武器同一公式，基准价来自 ItemData 按档位定
static func item_price(base: int, wave: int, price_mult: float) -> int:
	return int(float(base + (maxi(wave, 1) - 1) * ITEM_WAVE_STEP) * price_mult)

## 灵兽定价：基准价来自 PetData，与道具同回合成长步长
static func pet_price(base: int, wave: int, price_mult: float) -> int:
	return int(float(base + (maxi(wave, 1) - 1) * ITEM_WAVE_STEP) * price_mult)

static func potion_price(base: int, wave: int, price_mult: float) -> int:
	return int(float(base + maxi(wave, 1)) * price_mult)

## 回复药回复量：按生命上限的比例。货架卡上印的数、生命详情卡里说的数、ShopSystem 真喂给
## heal() 的数，三处都从这一个出口拿（2026-10-11 用户：「商店界面也要显示生命，
## 不然也不知道回复道具要不要买」——要能判断，卡面上的数就必须是真会兑现的那个数）。
## 2026-10-24 由 0.5 收到 0.25：原值一口回半管血，压平了走位/躲技能/压血线的紧张感，
## 且随 max HP 滚雪球（后期 max 300 一口 150）。0.25 对齐铜匣葫芦 30% 上限这一档单口量级。
const POTION_HEAL_RATIO := 0.25

static func potion_heal_amount(max_hp: float) -> float:
	return maxf(0.0, max_hp) * POTION_HEAL_RATIO

## 这一口现在实际回得上多少：heal() 会把超出上限的那截丢掉，卡面上就不许把它算进读数。
## 满血时是 0 —— 货架卡据此出红字「+0」，买前就看得见「这钱白花」。
static func potion_effective_heal(max_hp: float, cur_hp: float) -> float:
	return minf(potion_heal_amount(max_hp), maxf(0.0, max_hp - cur_hp))

static func reroll_cost(wave: int, reroll_count: int, price_mult: float) -> int:
	var w := maxi(wave, 1)
	var count_step := maxi(1, int(floor(float(w) * REROLL_COUNT_WAVE_SCALE)))
	return int(float(REROLL_BASE + w * REROLL_WAVE_STEP + maxi(reroll_count, 0) * count_step) * price_mult)

# ---------------- 聚灵阵启动价（2026-10-25 祭坛重设计：免费一次性 → 每回合金币启动）----------------

const OBELISK_COST_BASE := 45      ## 1 波启动价（≈一件 tier3 道具，开局一波收入约 81 的六成）
const OBELISK_COST_WAVE_STEP := 3  ## 每回合加价（比货架 +2 略陡：越晚启动越贵，鼓励早用）

## 启动聚灵阵的金币价（W1=45 → W20=102），不乘 price_mult：祭坛不是货架货，不吃难度价格乘区
static func obelisk_activation_cost(wave: int) -> int:
	return OBELISK_COST_BASE + (maxi(wave, 1) - 1) * OBELISK_COST_WAVE_STEP

# ---------------- 收益（回合末无偿发放并自我复利）----------------

const HARVEST_GROWTH := 1.05

static func harvest_gain(harvest: float) -> int:
	return int(round(harvest))

## 复利只涨到 growth_wave_cap 波为止（之后持平，防止后期指数爆炸）
static func harvest_next(harvest: float, wave: int, growth_wave_cap: int) -> float:
	if wave < growth_wave_cap:
		return harvest * HARVEST_GROWTH
	return harvest

# ---------------- 敌潮预算补差 ----------------

## 回合内总刷入预算（BalanceWave.wave_spawn_budget）收紧后，被预算拦下的怪不再掉宝石，
## 经验收入随之下滑。回合末按「未刷出只数 × 均值」折成经验找平，商店/加点购买力不变。
## 均值优先用本回合实际刷出敌人的 exp_reward 均值（WaveSpawner 现场统计），
## 一只都没刷出来的极端回合才落兜底值。
const BUDGET_COMP_EXP_FALLBACK := 2.0

## 补差经验 = 未刷出只数 × 每只期望经验（未刷出 ≤0 就是 0）
static func budget_compensation_exp(shortfall: int, avg_exp: float) -> int:
	if shortfall <= 0:
		return 0
	var eff_avg := avg_exp if avg_exp > 0.0 else BUDGET_COMP_EXP_FALLBACK
	return int(round(float(shortfall) * eff_avg))

# ---------------- 金币碎金档（常态基础掉落与通胀稀释） ----------------

## 碎金掉落机制（2026-10-13 体验重塑）：
## 普通怪最容易掉落细碎的金砂/碎金片——经验腿足额给（升级节奏与经验曲线不动），
## 金币腿按 1 枚入账。从第 1 波起即作为最常见的基准掉落（50% 起步），
## 随波次平滑成长至 70% 封顶，既符合小怪掉零钱直觉，又自然平抑后期金币通胀。
## 随机由调用方拿 GameManager.rng 比对，本函数保持纯。

const GEM_SHARD_STONE_VALUE := 1        ## 碎金金币面额
const GEM_SHARD_BASE_CHANCE := 0.50     ## 首波基准概率（最容易掉落：过半为碎金）
const GEM_SHARD_START_WAVE := 1         ## 自第 1 波直接生效
const GEM_SHARD_RISE_PER_WAVE := 0.012  ## 随波次递增步长（约在 W18 达到封顶）
const GEM_SHARD_CHANCE_CAP := 0.70      ## 碎金率上限：保住约三成普通灵石与精英大金石的高光

## 本回合普通怪掉落为碎金的概率（第 1 波从基准起步，单调递增，封顶 GEM_SHARD_CHANCE_CAP）
static func gem_shard_chance(wave: int) -> float:
	if wave <= 0:
		return 0.0
	return minf(GEM_SHARD_CHANCE_CAP, GEM_SHARD_BASE_CHANCE + float(wave - 1) * GEM_SHARD_RISE_PER_WAVE)

# ---------------- 提前清场余时赏 ----------------

## 一波的结束条件有两条（WaveSpawner._process_fight）：表走完，或「敌潮已尽」——本回合刷怪预算
## 全部刷入且场上再无活妖。后者就是用户 2026-10-12 的口径「提前杀完还在干等」：预算制下第 7 波
## 约 22s 就把 39 只刷完，之后场地是空的，只能看着表再走二十几秒。
## 提前收尾省下的那截时间按秒折成金币，余得越多给得越多。
## 只给金币、不给经验：与「收益」那条金币+经验双入账区分开，免得提前清场顺手把升级也加速。
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

# ---------------- 残丹化灵（回合末没贴上去吃掉的回复珠）----------------

## 回不上的那截生命折成金币：每点 0.8。钉在藏宝匣另一路上 —— 满口 18 点 ×0.8 ≈ 14，
## 与「约四成掉 3 颗金币（各 5 经验/金币）」同档，砸匣子两条路不等价也不悬殊。
const HEAL_OVERFLOW_STONE_PER_HP := 0.8
## 单颗封顶：生命上限越高、15% 口越大，不封顶就滚成巨款
const HEAL_OVERFLOW_STONE_CAP := 15

## 溢出生命 → 金币数（0 溢出就是 0，负数按 0 收）
static func heal_overflow_stones(overflow_hp: float) -> int:
	if overflow_hp <= 0.0:
		return 0
	return clampi(int(round(overflow_hp * HEAL_OVERFLOW_STONE_PER_HP)), 0, HEAL_OVERFLOW_STONE_CAP)

# ---------------- 悟道候选的稀有度权重 ----------------

## 四档稀有度模型（2026-10-13 对齐土豆兄弟：普通/稀有/史诗/传说，与道具 tier 同一套词表与颜色）：
## 高档权重 = min(上限, 每波步长 × (波次 − 解锁波)) × 福缘乘区；普通取 100 减去其余三档（有地板）。
## 波次递进让高稀有「后期稳定可及但永远稀有」，上限封顶防福缘堆叠失控。
const RARITY_TOTAL := 100.0
const RARITY_COMMON_FLOOR := 10.0       ## 普通档权重地板，防归零
const RARITY_LUCK_PER_POINT := 0.01     ## 福缘乘区：每点使高稀有概率 ×(1+1%)（土豆兄弟同款）
# 稀有档：第 1 波起基础 30，随波缓升
const RARITY_RARE_WAVE := 1
const RARITY_RARE_BASE := 30.0
const RARITY_RARE_PER_WAVE := 0.8
const RARITY_RARE_CAP := 45.0
# 史诗档：第 5 波解锁
const RARITY_EPIC_WAVE := 5
const RARITY_EPIC_PER_WAVE := 2.0
const RARITY_EPIC_CAP := 28.0
# 传说档：第 11 波解锁
const RARITY_LEGEND_WAVE := 11
const RARITY_LEGEND_PER_WAVE := 1.2
const RARITY_LEGEND_CAP := 12.0

## 单档权重：解锁波之前为 0，之后按步长线性增长、乘福缘后封顶
static func _rarity_growth(base: float, per_wave: float, cap: float, unlock_wave: int, wave: int, luck_mult: float) -> float:
	var w := maxi(wave, 1)
	if w < unlock_wave:
		return 0.0
	return minf(cap, (base + per_wave * float(w - unlock_wave)) * luck_mult)

## 悟道稀有度权重：返回 {common, rare, epic, legendary}，四档之和恒为 100（普通取余）
static func rarity_weights(luck: float, wave: int = 1) -> Dictionary:
	# 负福缘要真的降概率（2026-10-21）：旧版 max(0,luck) 让「攻速换福缘」的道具代价为空。
	var lm := clampf(1.0 + luck * RARITY_LUCK_PER_POINT, 0.1, 10.0)
	var legendary := _rarity_growth(0.0, RARITY_LEGEND_PER_WAVE, RARITY_LEGEND_CAP, RARITY_LEGEND_WAVE, wave, lm)
	var epic := _rarity_growth(0.0, RARITY_EPIC_PER_WAVE, RARITY_EPIC_CAP, RARITY_EPIC_WAVE, wave, lm)
	var rare := _rarity_growth(RARITY_RARE_BASE, RARITY_RARE_PER_WAVE, RARITY_RARE_CAP, RARITY_RARE_WAVE, wave, lm)
	var common := maxf(RARITY_COMMON_FLOOR, RARITY_TOTAL - rare - epic - legendary)
	return {"common": common, "rare": rare, "epic": epic, "legendary": legendary}

# ---------------- 货架抽取 ----------------

const POTION_CHANCE := 0.05            ## 每个货架位出回复药的概率（特供：约4波见1次）
const ITEM_CHANCE := 0.35              ## 每个货架位出道具的概率（2026-10-13 由 0.45 下调：道具无栏位硬顶，过供会滚属性）
const PET_CHANCE := 0.05               ## 每个货架位出随行灵兽的概率（御兽师有额外加成）

# ---------------- 货架 ★2 成品（2026-10-25）----------------
## 武器格有概率直接刷成 ★2 成品，给「3 件换 1 件」的升星路补一条金币捷径：
## ★3 需 3 件 ★2（≈8.1 倍 ★1 基准价）、★4 需 9 件（≈24 倍），用钱换时间，不白送。
## 三重闸门：解锁波次（前期买不起也凑不出）→ 波次线性成长 × 福缘 → 封顶；
## 手里同名 ★2 已 2 件（差 1 合 ★3）时抬到地板值，保证「临门一脚」刷得出来。

const STAR2_UNLOCK_WAVE := 4       ## ★2 成品最早出现的回合（前 3 波经济与构筑都没起步）
const STAR2_PER_WAVE := 0.02       ## 解锁后每个武器格每波 +2% 线性成长
const STAR2_CAP := 0.18            ## 单个武器格出 ★2 的概率上限（约每 2 次商店见 1 件）
const STAR2_NEAR_MERGE_FLOOR := 0.35  ## 同名 ★2 已 2 件（差 1 合 ★3）时的概率地板

## 单个武器格出 ★2 成品的概率。luck 乘区复用 shop_luck_mult（与货架权重同一把尺），
## near_merge 由调用方按 count_copies(id, 2) % 3 == 2 现判。
static func weapon_star2_chance(wave: int, luck: float, near_merge: bool) -> float:
	var w := maxi(wave, 1)
	if w < STAR2_UNLOCK_WAVE:
		return 0.0
	var c := minf(STAR2_CAP,
			STAR2_PER_WAVE * float(w - STAR2_UNLOCK_WAVE + 1) * shop_luck_mult(luck))
	if near_merge:
		c = maxf(c, STAR2_NEAR_MERGE_FLOOR)
	return c

const TAG_AFFINITY_MIN_COPIES := 2     ## 同流派持有数达到该值才触发亲和（第一档）
const TAG_AFFINITY_MULT_L1 := 2.0      ## 梯度亲和第一档：持有 ≥MIN_COPIES 件 → ×L1
const TAG_AFFINITY_TIER2_COPIES := 4   ## 梯度亲和第二档门槛：持有 ≥4 件 → ×L2（深专精吸力）
const TAG_AFFINITY_MULT_L2 := 3.0
const TAG_AFFINITY_COMBO_DAMP := 0.5   ## 双流派共鸣：第二流派的亲和按该比例折算后叠加
const LUCK_SHOP_PER_POINT := 0.01      ## 幸运对武器权重的加法系数
const MAIN_TAG_PITY_WAVES := 2         ## 连续几波没出主流派就强制塞一件
const TAG_FILTER_BONUS := 4.0          ## 流派偏好软加权：命中角色限定 tag 的武器权重倍率
const TAG_FILTER_LEAK := 0.2           ## 未命中限定 tag 的武器保留的小权重（漏出率）

## 梯度亲和倍率：持有不足 MIN_COPIES 件时恒为 1；≥4 件进入第二档深专精吸力
static func tag_affinity_mult(copies: int) -> float:
	if copies < TAG_AFFINITY_MIN_COPIES:
		return 1.0
	return TAG_AFFINITY_MULT_L2 if copies >= TAG_AFFINITY_TIER2_COPIES else TAG_AFFINITY_MULT_L1

## 双流派共鸣：武器同时命中多个已激活亲和的流派（如剑系∩金系）时，
## 最高档亲和全额生效，其余已激活流派按 COMBO_DAMP 半价叠加——
## 玩家双修两流派后，交叉武器权重反超单流派，货架会主动把"正想要的那把"喂过来。
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

## 流派偏好的软加权：角色限定流派非空时，命中 tag 的武器 ×BONUS，其余保留 LEAK 小权重。
## 替代旧版硬过滤——硬过滤在池中只有 1 件同名武器时会让货架坍缩为单一武器。
static func tag_filter_mult(weapon_tags: Array, filter_tags: Array) -> float:
	if filter_tags.is_empty():
		return 1.0
	for t in weapon_tags:
		if t in filter_tags:
			return TAG_FILTER_BONUS
	return TAG_FILTER_LEAK

static func shop_luck_mult(luck: float) -> float:
	return clampf(1.0 + luck * LUCK_SHOP_PER_POINT, 0.1, 10.0)

# ---------------- 同名追梦加权（2026-10-24）----------------

## 三合一升星会「3 件换 1 件」：合成后手里同名武器只剩 1 把，标签件数掉 2，
## 于是流派亲和（按标签件数加权）反而在升星后变弱 —— 想凑 27 把 ★1 追 ★4 时，
## 越合越刷不到自己那把，追梦在数学上根本走不完。
## 这里按「手里同名武器的最高星级」给该武器单独的权重倍率，把升星的空缺补回来：
## 持有 ★1 ×2.2 / ★2 ×4.5 / ★3 ×8.0；已有 ★4 且没有低星散件时回落 1.0（追梦已达成）。
## 上限压在 8.0：再高会让货架坍缩成单一武器，玩家就没有构筑选择的余地了。
const DREAM_AFFINITY_BY_STAR: Array[float] = [2.2, 4.5, 8.0]
## 临门一脚（同星已凑到 2 件，再 1 件就能合）额外乘的加成：让「差一件」真的刷得出来
const DREAM_AFFINITY_NEAR_MERGE := 1.6

## 纯函数：同名追梦权重倍率。max_star = 手里该武器最高星级（0 = 未持有）；
## copies_at_max = 该星级现有件数（≥2 视为临门一脚）。
static func owned_weapon_affinity_mult(max_star: int, copies_at_max: int) -> float:
	if max_star <= 0:
		return 1.0
	if max_star >= WeaponData.MAX_STAR:
		return 1.0
	var m: float = DREAM_AFFINITY_BY_STAR[clampi(max_star, 1, WeaponData.MAX_STAR) - 1]
	if copies_at_max >= 2:
		m *= DREAM_AFFINITY_NEAR_MERGE
	return m

# ---------------- 道具（被动道具）档位权重 ----------------

## 各档位最早出现的回合（下标 1~4 对应 tier 1~4，0 为占位）：高档道具随回合解锁
## 2026-10-13 对齐土豆兄弟：解锁后概率按步长随波次线性增长、乘福缘后封顶，普通档取余托底。
const ITEM_TIER_WAVES := [0, 1, 4, 9, 14]
const ITEM_TIER_COMMON_FLOOR := 10.0     ## 普通档权重地板，防归零
const LUCK_ITEM_MULT_PER_POINT := 0.01   ## 福缘乘区：每点使高档概率 ×(1+1%)
const ITEM_TIER_RARE_PER_WAVE := 3.0     ## 稀有档每波步长
const ITEM_TIER_RARE_CAP := 40.0
const ITEM_TIER_EPIC_PER_WAVE := 2.0     ## 史诗档每波步长
const ITEM_TIER_EPIC_CAP := 25.0
const ITEM_TIER_LEGEND_PER_WAVE := 0.8   ## 传说档每波步长
const ITEM_TIER_LEGEND_CAP := 8.0

## 单档概率：未达解锁波为 0，之后 步长 ×(波次 − 解锁波) 线性增长，乘福缘后封顶
static func _item_tier_growth(per_wave: float, cap: float, unlock_wave: int, wave: int, luck_mult: float) -> float:
	var w := maxi(wave, 1)
	if w < unlock_wave:
		return 0.0
	return minf(cap, per_wave * float(w - unlock_wave) * luck_mult)

## 道具档位权重：返回长度 4 的数组（tier1~4），四档之和恒为 100（普通取余）。
## 高档 = 波次递进 × 福缘乘区后封顶；未到解锁回合的档位权重为 0。
static func item_tier_weights(luck: float, wave: int) -> Array:
	var lm := clampf(1.0 + luck * LUCK_ITEM_MULT_PER_POINT, 0.1, 10.0)
	var legendary := _item_tier_growth(ITEM_TIER_LEGEND_PER_WAVE, ITEM_TIER_LEGEND_CAP, int(ITEM_TIER_WAVES[4]), wave, lm)
	var epic := _item_tier_growth(ITEM_TIER_EPIC_PER_WAVE, ITEM_TIER_EPIC_CAP, int(ITEM_TIER_WAVES[3]), wave, lm)
	var rare := _item_tier_growth(ITEM_TIER_RARE_PER_WAVE, ITEM_TIER_RARE_CAP, int(ITEM_TIER_WAVES[2]), wave, lm)
	var common := maxf(ITEM_TIER_COMMON_FLOOR, 100.0 - rare - epic - legendary)
	return [common, rare, epic, legendary]

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
## 「角色把某系门槛降低」这件事的唯一折算口——档位结算、卡面进度、徽记读数都必须走它，
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
		"xp_gain_mult", "knockback_mult", "free_rerolls", "revive_charges", "elite_damage", "shop_price_mul",
			"melee_damage", "ranged_damage", "elemental_damage", "engineering_damage", "contraption_damage",
		"element_damage_all", "element_damage_metal", "element_damage_wood",
		"element_damage_water", "element_damage_fire", "element_damage_earth",
			"bonus_pierce", "thorns",
			"chest_count", "chest_quality", "chest_reward",
			"pet_damage_mult", "pet_effect_mult", "pet_cooldown_mult_mul", "pet_slots",
			"skill_cooldown_mult",
		]
