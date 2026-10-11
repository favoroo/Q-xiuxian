class_name ShadowStepData
extends RefCounted

## 踏影（闪避出口）数据表：闪避不再只是「这一下没掉血」，而是把躲掉的那一下存进影里，
## 下一次冲刺踩碎它——还一口伤害、把贴身的怪推开、多一段无敌。
##
## 为什么要它（2026-10-11 实测，见 tests/DodgeDeliveryProbe.tscn）：
##   Player.take_damage 里闪避成功不消耗 0.55s 无敌帧，而只有打中才设帧 ⇒ 怪群贴身时
##   判定机会每帧都有，闪避只把「这一下」推迟几帧，落点频率仍被无敌帧钉死。
##   活体标定：14 只杂怪围住站桩玩家，闪避 0% 实测 1.99 下/秒、86% 实测 2.19 下/秒，
##   两档都贴着 1/0.55 = 1.82 的饱和线 ⇒ 纸面写着 ×10 的有效生命，实际只兑现 ×1.25。
##   两条修法各管一半：GUARD_SEC 让闪避真的降低挨打频率；影层让闪成功这件事有回报。
##
## 三条口径：
## 1. 全 static 纯函数，不读 autoload、不碰节点（与 GameBalance 同规约），数值只在本表；
## 2. BURST_RADIUS 既是判定半径也是环特效半径——画多大 == 判多大，不许用辉光糊大；
## 3. 卡面与详解里出现的踏影数字一律现读本表，别处不抄（判据 ShadowStepCheck 钉同源）。

const GUARD_SEC := 0.12        ## 闪避成功给的「残影」短无敌（秒）：不这么改，贴身时闪避等于白闪
const MAX_STACKS := 5          ## 影层上限：攒满后再闪不涨层，但会把最旧那层换成这一刀
const STORE_RATIO := 0.55      ## 躲掉的那一下，有 55% 折成影袭伤害还回去
const IFRAME_PER_STACK := 0.07 ## 踏影冲刺每层追加的无敌窗口（秒）
const PUSH_PER_STACK := 110.0  ## 踏影冲刺每层追加的击退冲量（与法器击退同一条尺子）
const BURST_RADIUS := 120.0    ## 影袭判定半径 = 落地环半径（像素）

## 这一刀躲掉后存进影里的原始伤害（未打折，打折在兑现时算，便于改比例不动历史层）
static func store_value(raw_damage: float) -> float:
	return maxf(0.0, raw_damage)

## 攒层：FIFO 换掉最旧一层 ⇒ 满层后「再闪到更好的那一刀」不白闪
static func push_ring(ring: Array, raw_damage: float) -> Array:
	var out := ring.duplicate()
	out.append(store_value(raw_damage))
	while out.size() > MAX_STACKS:
		out.pop_front()
	return out

static func stacks_of(ring: Array) -> int:
	return ring.size()

## 影里存的总伤（未打折）
static func stored_sum(ring: Array) -> float:
	var total := 0.0
	for v in ring:
		total += float(v)
	return total

## 踏影落地时对每个圈内敌人造成的伤害
static func burst_damage(ring: Array) -> float:
	return stored_sum(ring) * STORE_RATIO

## 踏影这次冲刺多出来的无敌秒数
static func iframe_bonus(ring: Array) -> float:
	return float(ring.size()) * IFRAME_PER_STACK

## 踏影落地的击退冲量（调用方再乘玩家震退乘区，与法器击退同源）
static func push_impulse(ring: Array) -> float:
	return float(ring.size()) * PUSH_PER_STACK

## 有没有东西可兑现：空影层时冲刺保持原样，不放环、不查怪
static func has_charge(ring: Array) -> bool:
	return not ring.is_empty()
