class_name BalanceChest
extends RefCounted

## 藏宝匣（宝箱）一条链路的数值（2026-10-11 寻宝流改版）：每回合刷几口、各档匣子的出现权重、
## 挨几下砸开、砸开兑现什么、玉匣每局最多送几件道具。全部 static 纯函数，与 GameBalance 同规约：
## 不读 autoload、不碰节点、不调全局 randf() —— 随机一律由调用方（WaveSpawner / SpiritChest）
## 传 GameManager.rng 已经抽好的 roll，判据可以钉住种子复现同一批匣子。
##
## 三档口径（玩家看到的名字在 ManualData，这里只管数值）：
##   木匣 0 —— 基准档，就是改版前那口匣子，出现权重恒最高
##   铜匣 1 —— 掉落量约两倍，另给一笔金币
##   玉匣 2 —— 必送一件道具（与金币阁同一个 roller，见 ItemData.pick_id），另有金币
##
## 为什么分档不加击数：高档匣若更耐砸，玩家堆「宝箱品质」反而换来更难兑现的目标，
## 砸不开就等于零收益（2026-10-11 量兑现率的口径）。击数只由「开箱省力」这一个来源往下压。

# ---------------- 档位 ----------------

const TIER_WOOD := 0
const TIER_COPPER := 1
const TIER_JADE := 2
const TIER_COUNT := 3

## 各档体型倍率（乘在 SpiritChest.SIZE_MULT 上）：判定圆与精灵同乘，画多大 == 判多大。
## 差距刻意只做一成多：档位靠材质与读数配色辨认，不靠"玉匣大得离谱"。
const TIER_SCALE: Array[float] = [1.0, 1.06, 1.14]

const TIER_NAMES: Array[String] = ["木匣", "铜匣", "玉匣"]

static func tier_name(tier: int) -> String:
	return TIER_NAMES[clampi(tier, 0, TIER_NAMES.size() - 1)]

static func tier_scale(tier: int) -> float:
	return TIER_SCALE[clampi(tier, 0, TIER_SCALE.size() - 1)]

# ---------------- 每回合刷几口 ----------------

const CHEST_COUNT_BASE := 2       ## 第 1 波就刷 2 口：寻宝流的料得在场，不能等
const CHEST_COUNT_PER_WAVES := 6  ## 每这么多波基础档 +1
const CHEST_COUNT_BASE_CAP := 4   ## 不吃加成时最多刷几口（改版前的旧口径）
const CHEST_COUNT_CAP := 8        ## 含加成的硬顶：场地只有半场 500，再多就成箱子阵

## 每回合刷出的匣子只数：基础曲线 + 「宝箱数量」加成，夹在硬顶内。
## bonus 是 GameManager.chest_count_bonus（加点与道具共用同一条字段）。
static func chest_count(wave: int, bonus: int) -> int:
	var base := mini(CHEST_COUNT_BASE + int(float(maxi(wave, 1)) / float(CHEST_COUNT_PER_WAVES)), CHEST_COUNT_BASE_CAP)
	return clampi(base + maxi(0, bonus), 0, CHEST_COUNT_CAP)

# ---------------- 各档出现权重 ----------------

## 抽档权重 [木, 铜, 玉]：只吃「宝箱品质」与已有的福缘，不吃回合。
## 底子里铜/玉在品质为 0 时也有正权重 —— 第 1 波就可能刷出铜匣，堆品质只是把占比抬上去。
const WOOD_W := 100.0
const COPPER_W_BASE := 18.0
const COPPER_W_PER_QUALITY := 6.0
const JADE_W_BASE := 3.0
const JADE_W_PER_QUALITY := 2.5
## 福缘顺带抬高档位（与悟道稀有度、货架档位同一把"缘"尺，不另立新池）
const COPPER_W_PER_LUCK := 0.4
const JADE_W_PER_LUCK := 0.5

static func tier_weights(quality: float, luck: float) -> Array[float]:
	var q := maxf(quality, 0.0)
	# 负福缘同样要压低铜匣/玉匣权重（2026-10-21），只给权重留一个极小地板防负数。
	var l := luck
	return [
		WOOD_W,
		maxf(0.01, COPPER_W_BASE + COPPER_W_PER_QUALITY * q + COPPER_W_PER_LUCK * l),
		maxf(0.01, JADE_W_BASE + JADE_W_PER_QUALITY * q + JADE_W_PER_LUCK * l),
	]

# ---------------- 挨几下砸开 ----------------

const CHEST_BREAK_HITS := 3   ## 满血匣子挨几下砸开。只数"打到了几下"，与伤害数值无关
const CHEST_MIN_HITS := 1     ## 击数地板：再多的「开箱省力」也留一下，砸这个动作不能被抹掉

static func break_hits(break_bonus: int) -> int:
	return maxi(CHEST_MIN_HITS, CHEST_BREAK_HITS - maxi(0, break_bonus))

# ---------------- 砸开兑现什么 ----------------

## 奖励表（唯一真话，SpiritChest 逐项消费，卡面/图鉴文案与它同源）：
##   heal_chance —— 掉回春葫芦的概率，否则掉一捧金币
##   heal_pct    —— 葫芦按生命上限的回复比例
##   gem_count   —— 金币颗数，gem_exp 每颗经验
##   stones      —— 直接进袖的金币（0 = 不掉金币）
##   grant_item  —— 是否必送一件随机道具（只有玉匣）
const REWARD_WOOD := {
	"heal_chance": 0.4, "heal_pct": 0.15, "gem_count": 3, "gem_exp": 5,
	"stones": 0, "grant_item": false,
}
const REWARD_COPPER := {
	"heal_chance": 0.4, "heal_pct": 0.30, "gem_count": 6, "gem_exp": 5,
	"stones": 6, "grant_item": false,
}
const REWARD_JADE := {
	"heal_chance": 0.0, "heal_pct": 0.0, "gem_count": 5, "gem_exp": 5,
	"stones": 18, "grant_item": true,
}

static func reward_of(tier: int) -> Dictionary:
	match clampi(tier, 0, TIER_COUNT - 1):
		TIER_COPPER:
			return REWARD_COPPER
		TIER_JADE:
			return REWARD_JADE
		_:
			return REWARD_WOOD

## 玉匣每局最多送出几件道具：一件道具值 15~90 金币，白送到 3 件已经是一条 build，
## 再往上会把金币阁掏空成背景板。超上限的玉匣退回铜匣奖励 ×jade_fallback_mult。
const JADE_ITEM_GRANT_CAP := 3
const JADE_FALLBACK_MULT := 1.5

## 单口匣子回复量上限：堆满一条寻宝流（悟道「宝箱掉落」+道具「满匣诀」）也不许一口回满血。
const REWARD_HEAL_CAP := 0.60

## 上限满后玉匣退回的量：按铜匣奖励整体放缩（葫芦概率/回复、金币颗数、金币都算上）
static func jade_fallback_reward() -> Dictionary:
	var base: Dictionary = REWARD_COPPER.duplicate()
	base["heal_chance"] = minf(1.0, float(base["heal_chance"]) * JADE_FALLBACK_MULT)
	base["heal_pct"] = float(base["heal_pct"]) * JADE_FALLBACK_MULT
	base["gem_count"] = int(round(float(base["gem_count"]) * JADE_FALLBACK_MULT))
	base["stones"] = int(round(float(base["stones"]) * JADE_FALLBACK_MULT))
	base["grant_item"] = false
	return base

# ---------------- 开箱收益乘区 ----------------

## 悟道「宝箱掉落」与道具「满匣诀」把同一口匣子的兑现量整体放大（GameManager.chest_reward_mult）。
##   放大：gem_count（金币颗数）、stones（金币）、heal_pct（葫芦回复比例，封顶 REWARD_HEAL_CAP）
##   不放大：heal_chance（掉葫芦的概率——那条由危险度乘区单独管）、gem_exp（每颗金币经验，不吹经验曲线）、grant_item
##   只抬不罚：mult < 1.0 按 1.0 算，字段被回退到 1.0 以下也不许把掉落砍下去。
static func scale_reward(reward: Dictionary, mult: float) -> Dictionary:
	var m := maxf(1.0, mult)
	var out: Dictionary = reward.duplicate()
	out["gem_count"] = int(round(float(out.get("gem_count", 0)) * m))
	out["stones"] = int(round(float(out.get("stones", 0)) * m))
	out["heal_pct"] = minf(float(out.get("heal_pct", 0.0)) * m, REWARD_HEAL_CAP)
	return out

# ---------------- 危险度乘区 ----------------

## 葫芦掉落概率随危险度递减：高难度治疗更稀缺，让难档更难。
## 与 BalanceWave.danger_*_mult 同模式——纯函数，danger 由调用方（SpiritChest）传
## GameManager.danger_level，乘在奖励表 heal_chance 上。奖励表 heal_chance 是普通档基准，
## 普通(0)=×1.0 → 噩梦(1)=×0.65（0.40 基准压到 0.26，适中不刮痧）。
## 2026-10-28 噩梦难度均衡档重塑：降幅调整为 -35%，噩梦终值 ×0.65。
const DANGER_HEAL_MULT_BASE := 1.0     ## 普通档(D0)葫芦概率乘区基线
const DANGER_HEAL_MULT_PER := -0.35    ## 每档危险度葫芦概率 -35%（D1 = 1.0 - 0.35 = 0.65）

static func danger_heal_chance_mult(danger: int) -> float:
	return maxf(0.0, DANGER_HEAL_MULT_BASE + float(clampi(danger, 0, BalanceWave.DANGER_MAX)) * DANGER_HEAL_MULT_PER)
