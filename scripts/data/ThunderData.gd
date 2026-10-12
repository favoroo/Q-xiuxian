class_name ThunderData
extends RefCounted

## 天雷（雷法真君被动出口）数据表：每隔数秒自动引一道天雷劈向最近的妖兽，
## 落点小范围震荡——伤害随元素伤害成长，给「堆元素」一个看得见的兑现口。
## 全自动索敌，不用学操作；与雷法雷系/符箓亲和同向：元素越高，天雷越疼。
##
## 三条口径（同 ShadowStepData / GuardStanceData 规约）：
## 1. 全 static 纯函数，不读 autoload、不碰节点，数值只在本表；
## 2. RADIUS 既是判定半径也是环特效半径——画多大 == 判多大；
## 3. 卡面/详解里的天雷数字一律现读本表（card_lines），别处不抄。
## 计时器在 Player（_thunder_cd，随节点生灭），开关在 GameManager.thunder_strike（mod 键门控）。

const INTERVAL := 5.0         ## 落雷间隔秒数：有怪才落，落完重新计
const RETRY_INTERVAL := 0.3   ## 范围内无怪时的重试间隔（不空耗整轮冷却）
const SEEK_RANGE := 460.0     ## 索敌半径：约半屏，劈得到就要看得见
const RADIUS := 100.0         ## 落点震荡判定半径 = 环特效半径（像素）
const BASE_DAMAGE := 12.0     ## 基础雷伤（开局元素 3 时一雷 18，打得动第 1 波小怪）
const ELEMENTAL_RATIO := 2.0  ## 元素伤害转化率：每点元素伤害 +2 雷伤（堆元素的第二生命）
const PUSH_IMPULSE := 140.0   ## 落点震退冲量（调用方乘玩家震退乘区，与法器击退同一把尺子）

## 单雷伤害（未吃任何乘区；调用方自行乘短时增益乘区 buff_damage_mult）
static func bolt_damage(elemental_damage: float) -> float:
	return BASE_DAMAGE + maxf(0.0, elemental_damage) * ELEMENTAL_RATIO

## 卡面文案：选角/详解/图鉴同读这一份，数字现读本表（口径 3）。
## 每条一行，按详解卡最窄列宽（404）量过：加字先量宽。
static func card_lines() -> Array[String]:
	return [
		"天雷：每 %d 秒劈向最近妖兽，落点 %d 像素震荡" % [int(roundf(INTERVAL)), int(roundf(RADIUS))],
		"天雷：伤害 %d + 元素伤害 ×%.1f" % [int(roundf(BASE_DAMAGE)), ELEMENTAL_RATIO],
	]
