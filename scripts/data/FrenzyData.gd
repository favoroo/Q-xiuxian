class_name FrenzyData
extends RefCounted

## 战意（狂战士击杀出口）数据表：杀得越密，刀越重——每次击杀 +1 层战意，
## 每层全武器伤害 +2%；停杀 2.5 秒后战意开始流失（每秒 6 层），重新击杀立刻止住并续层。
## 「别停下来」就是全部操作——与狂战士 ×基础高伤、只有 3 槽的莽夫定位同向：
## 怪越密战意越旺，清屏断档就泄气。
##
## 三条口径（同 ShadowStepData / GuardStanceData 规约）：
## 1. 全 static 纯函数，不读 autoload、不碰节点，数值只在本表；
## 2. 层数账本在 GameManager（frenzy_stacks / frenzy_idle，RunReset 复位），
##    唯一攒点是 GameManager.register_kill，唯一流失点是 GameManager._process；
## 3. 卡面/详解里的战意数字一律现读本表（card_lines），别处不抄。

const PER_STACK := 0.02    ## 每层战意全武器伤害 +2%（乘法乘区，走 CultivatorSystem.damage_mult）
const MAX_STACKS := 20     ## 战意上限 20 层（满层 +40%）：约两波密怪才能养满，养满有成就感
const DECAY_DELAY := 2.5   ## 最后一次击杀后宽限秒数：赶路/绕位不立刻泄气
const DECAY_PER_SEC := 6.0 ## 宽限过后每秒流失层数（约 3.3 秒泄完满槽，断档有代价但不绝望）

## 击杀入账：层数 +1（封顶），宽限计时由调用方（register_kill）一并归零
static func add_stack(stacks: float) -> float:
	return minf(float(MAX_STACKS), stacks + 1.0)

## 流失：idle 超过宽限后开始每秒掉层；未超宽限原样返回
static func decay(stacks: float, idle: float, delta: float) -> float:
	if idle < DECAY_DELAY:
		return stacks
	return maxf(0.0, stacks - DECAY_PER_SEC * delta)

## 战意伤害乘区（0 层 = 1.0，满层 = 1.0 + MAX_STACKS×PER_STACK）
static func damage_mult(stacks: float) -> float:
	return 1.0 + maxf(0.0, stacks) * PER_STACK

## 卡面文案：选角/详解/图鉴同读这一份，数字现读本表（口径 3）。
## 每条一行，按详解卡最窄列宽（404）量过：加字先量宽。
static func card_lines() -> Array[String]:
	return [
		"战意：每次击杀 +1 层，每层全伤害 +%d%%（至多 %d 层）" % [int(roundf(PER_STACK * 100.0)), MAX_STACKS],
		"战意：%.1f 秒无击杀开始流失（每秒 %d 层）" % [DECAY_DELAY, int(roundf(DECAY_PER_SEC))],
	]
