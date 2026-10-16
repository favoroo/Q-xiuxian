class_name GuardStanceData
extends RefCounted

## 盾势（守卫受击出口）数据表：护甲挡下的伤害不再只是「少掉了点血」，而是存进盾势槽，
## 蓄满自动炸开——还一圈伤害、把贴身的怪震开。与踏影同构（受击版攒/放），但全自动：
## 守卫没有第二颗按钮，蓄满即放，不用学任何操作——「站着挨打」本身就是攒大招。
##
## 三条口径（同 ShadowStepData 规约）：
## 1. 全 static 纯函数，不读 autoload、不碰节点，数值只在本表；
## 2. BURST_RADIUS 既是判定半径也是环特效半径——画多大 == 判多大；
## 3. 卡面/详解里出现的盾势数字一律现读本表（card_lines），别处不抄。
## 蓄能账单在 GameManager.shield_charge（单局字段，RunReset 复位），由 Player.take_damage
## 在受击点写入、蓄满当帧兑现清空——判定窗口与受击 0.55s 无敌帧同源，不会超频连炸。

const CAP_HP_RATIO := 0.5   ## 盾势槽上限 = 最大生命 ×50%：血越厚槽越深，与守卫 hp_mult×1.8 天然同向
const STORE_RATIO := 1.0    ## 被护甲挡下的那部分伤害 100% 存进盾势（护甲越厚存得越快，叠甲有第二重回报）
const BURST_RATIO := 1.2    ## 爆发伤害 = 蓄能 ×1.2：存得多还得更多，挨打有红利
const BURST_RADIUS := 140.0 ## 震荡判定半径 = 环特效半径（像素）
const PUSH_IMPULSE := 260.0 ## 震退冲量（调用方乘玩家震退乘区，与武器击退同一把尺子）

## —— 盾势爆发演出（纯视觉参数；环半径仍只认 BURST_RADIUS——画多大 == 判多大）——
const BURST_RING_DURATION := 0.45 ## 盾势落地冲击环时长（秒，JuiceEffect.spawn_shockwave 读）
const BURST_ZOOM_PUNCH := 0.04    ## 盾势镜头微缩强（zoom punch；低频爆发技只给一档轻缩放）

## 槽上限（生命变化时现算，不缓存——加点/道具提血后下一刀自动按新上限走）
static func cap_of(max_health: float) -> float:
	return maxf(1.0, max_health * CAP_HP_RATIO)

## 蓄能：这一刀被护甲挡下的部分（raw - reduced）存进槽里，顶到上限为止
static func add_charge(charge: float, blocked: float, max_health: float) -> float:
	return minf(cap_of(max_health), charge + maxf(0.0, blocked) * STORE_RATIO)

## 蓄满判定：满即自动爆发（Player.take_damage 里判，判完清空）
static func is_full(charge: float, max_health: float) -> bool:
	return charge >= cap_of(max_health)

## 爆发对每个圈内敌人造成的伤害
static func burst_damage(charge: float) -> float:
	return charge * BURST_RATIO

## 卡面文案：选角/详解/图鉴同读这一份，数字现读本表（口径 3）。
## 每条一行，按详解卡最窄列宽（404）量过：加字先量宽。
static func card_lines() -> Array[String]:
	return [
		"攒：护甲挡下的伤害 %d%% 存入盾势（至多 %d%% 生命）" % [
			int(roundf(STORE_RATIO * 100.0)), int(roundf(CAP_HP_RATIO * 100.0))],
		"放：蓄满自动爆发，按 %d%% 还给周身敌人并震开" % [
			int(roundf(BURST_RATIO * 100.0))],
	]
