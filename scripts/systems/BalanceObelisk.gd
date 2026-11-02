class_name BalanceObelisk
extends RefCounted

## 祭坛「灵脉阶」与血祭数值（2026-11-02 祭坛成长线重做）。
## 阶数 = max(波次阶, 启动次数阶)：不投资也会随波次自然晋阶，启动越多晋得越快。
## 全部 static 纯函数，与 GameBalance 同规约：不读 autoload、不碰节点、不调全局 randf()。
## 祭坛爆发的基础伤害/生命比例/斩杀/击退仍在 BalanceCombat，本类只叠阶数增益。

# ---------------- 灵脉阶（1~4） ----------------

const MAX_TIER := 4                 ## 祭坛最高阶：与灵兽最高阶段同数，也对应前 4 段天象主题
const WAVE_TIER_STEP := 5           ## 每 5 波自然晋 1 阶（与 BalanceWave.stage_mood_tier 同拍）
## 启动次数晋阶阈值：3/6/10 次分别到 2/3/4 阶（含本局首次免费那一档）。
## 每波最多启动一次，正常一局到 W10 左右可凭启动次数摸到 4 阶；不投资则 W16 靠波次兜底。
const ACTIVATION_TIER_THRESHOLDS: Array[int] = [3, 6, 10]

## 本波自然阶：W1-5=1，W6-10=2，W11-15=3，W16+=4
static func wave_tier(wave: int) -> int:
	return clampi(int(float(maxi(wave, 1) - 1) / float(WAVE_TIER_STEP)) + 1, 1, MAX_TIER)

## 启动次数阶：0-2=1，3-5=2，6-9=3，10+=4
static func activation_tier(activations_done: int) -> int:
	var tier := 1
	for i in ACTIVATION_TIER_THRESHOLDS.size():
		if activations_done >= ACTIVATION_TIER_THRESHOLDS[i]:
			tier = i + 2
	return mini(tier, MAX_TIER)

## 祭坛当前阶：波次自然阶与启动次数阶取高者
static func altar_tier(wave: int, activations_done: int) -> int:
	return maxi(wave_tier(wave), activation_tier(activations_done))

## 阶位中文名（横幅/手册用；不读语言表，保持纯函数）
static func tier_name(tier: int) -> String:
	var names: Array[String] = ["一阶", "二阶", "三阶", "四阶"]
	return names[clampi(tier, 1, MAX_TIER) - 1]

# ---------------- 阶数对祭坛爆发的加成 ----------------

## flat 伤害乘区：1.0 / 1.10 / 1.22 / 1.36（缓于敌血 1.16，主体价值仍给灵兽）
const TIER_DAMAGE_MULT: Array[float] = [1.0, 1.10, 1.22, 1.36]
## 按最大生命附加的绝对值：+0 / +0.5% / +1.0% / +1.5%
const TIER_HP_RATIO_BONUS: Array[float] = [0.0, 0.005, 0.010, 0.015]
## 斩杀线绝对值加成：+0 / +0.5% / +1.0% / +1.5%
## 口径护栏：W20 基础 19.6% + 1.5% = 21.1%，仍低于 Boss 二阶段 50% / 精英变异 60%。
const TIER_EXECUTE_BONUS: Array[float] = [0.0, 0.005, 0.010, 0.015]
## 击退乘区：1.0 / 1.05 / 1.10 / 1.15
const TIER_KNOCK_MULT: Array[float] = [1.0, 1.05, 1.10, 1.15]

static func tier_damage_mult(tier: int) -> float:
	return TIER_DAMAGE_MULT[clampi(tier, 1, MAX_TIER) - 1]

static func tier_hp_ratio_bonus(tier: int) -> float:
	return TIER_HP_RATIO_BONUS[clampi(tier, 1, MAX_TIER) - 1]

static func tier_execute_bonus(tier: int) -> float:
	return TIER_EXECUTE_BONUS[clampi(tier, 1, MAX_TIER) - 1]

static func tier_knock_mult(tier: int) -> float:
	return TIER_KNOCK_MULT[clampi(tier, 1, MAX_TIER) - 1]

# ---------------- 血祭（金币不足时的替代启动路径） ----------------

## 血祭代价：最大生命的 18%，至少 1 点。用 ceil 保证低血量时也扣得出 1 点。
## 只在「金币 < 启动价」时开放；扣完至少留 1 点生命，不能因血祭直接死亡。
const BLOOD_HP_RATIO := 0.18

static func blood_cost(max_hp: float) -> int:
	return maxi(1, int(ceil(maxf(max_hp, 0.0) * BLOOD_HP_RATIO)))
