class_name KillHasteData
extends RefCounted

## 杀戮节奏（飞升神通）数据表：杀得越密，全武器攻速越快。
## 每次击杀 +1 层，每层攻速 +3%（攻击间隔 ÷ 1.03）；至多 10 层 = +30%。
## 停杀 3 秒后开始衰减，每秒掉 2 层 —— 与狂战士战意（FrenzyData）同一套
## 「击杀续层、断档泄气」的节奏，只是把伤害换成了攻速。
##
## 三条口径（同 FrenzyData 规约）：
## 1. 全 static 纯函数，不读 autoload、不碰节点，数值只在本表；
## 2. 层数账本在 GameManager（kill_haste_stacks / kill_haste_idle，RunReset 复位），
##    唯一攒点是 GameManager.register_kill，唯一流失点是 GameManager._process；
## 3. 消费点 GameManager.get_effective_attack_speed_mult（StatShadow 预读走同一函数）。
##
## 「攻速 +30%」按 1/(1+0.30) 取攻击间隔乘区：满层间隔 ×0.769 ≈ 快 30%，
## 不是「攻击间隔 -30%」（后者等价 +42.9% 攻速）。卡面数字现读本表。

const ATTACK_SPEED_PER_STACK := 0.03  ## 每层攻速 +3%
const MAX_STACKS := 10                 ## 上限 10 层 = +30% 攻速
const DECAY_DELAY := 3.0               ## 最后一次击杀后宽限秒数
const DECAY_PER_SEC := 2.0             ## 宽限过后每秒流失层数（满层 5 秒泄完）

## 击杀入账：层数 +1（封顶），宽限计时由调用方（register_kill）一并归零
static func add_stack(stacks: float) -> float:
	return minf(float(MAX_STACKS), stacks + 1.0)

## 流失：idle 超过宽限后开始每秒掉层；未超宽限原样返回
static func decay(stacks: float, idle: float, delta: float) -> float:
	if idle < DECAY_DELAY:
		return stacks
	return maxf(0.0, stacks - DECAY_PER_SEC * delta)

## 攻速层数 → 攻击间隔乘区（0 层 = 1.0，满层 = 1/1.30；再乘进攻速面板同一乘区）
static func attack_speed_mult(stacks: float) -> float:
	var s: float = clampf(stacks, 0.0, float(MAX_STACKS))
	return 1.0 / (1.0 + s * ATTACK_SPEED_PER_STACK)
