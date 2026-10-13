class_name ShadowStepData
extends RefCounted

## 踏影（闪避出口）数据表：闪避不再只是「这一下没掉血」，而是把躲掉的那一下存进影里，
## 点额外技能「影爆」随时踩碎它——还一口伤害、把贴身的怪推开、多一段无敌。
## 带着影冲刺另有被动：每层加一段冲刺无敌（不消耗影层）。
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
## 4. amp_mult（攒层增伤）同样只认本表：层数在身上时武器伤害吃 amp_mult 乘区，
##    由 Player 在攒层/清空两个写点同步进 GameManager.shadow_amp_mult，别处不许另算。

const GUARD_SEC := 0.12        ## 闪避成功给的「残影」短无敌（秒）：不这么改，贴身时闪避等于白闪
const MAX_STACKS := 8          ## 影层上限：攒满后再闪不涨层，但会把最旧那层换成这一刀
const STORE_RATIO := 0.55      ## 躲掉的那一下，有 55% 折成影袭伤害还回去
const IFRAME_PER_STACK := 0.07 ## 踏影冲刺每层追加的无敌窗口（秒）
const PUSH_PER_STACK := 110.0  ## 踏影冲刺每层追加的击退冲量（与武器击退同一条尺子）
const BURST_RADIUS := 120.0    ## 影袭判定半径 = 落地环半径（像素）
const AMP_PER_STACK := 0.05    ## 每层影给的武器伤害加成（攒着就生效，满层 ×1.40）

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

## 攒层增伤乘区：影在身上时武器每一刀都吃，落地兑现清空后回 1.0
static func amp_mult(ring: Array) -> float:
	return 1.0 + float(ring.size()) * AMP_PER_STACK

## 踏影落地时对每个圈内敌人造成的伤害
static func burst_damage(ring: Array) -> float:
	return stored_sum(ring) * STORE_RATIO

## 踏影这次冲刺多出来的无敌秒数
static func iframe_bonus(ring: Array) -> float:
	return float(ring.size()) * IFRAME_PER_STACK

## 踏影落地的击退冲量（调用方再乘玩家震退乘区，与武器击退同源）
static func push_impulse(ring: Array) -> float:
	return float(ring.size()) * PUSH_PER_STACK

## 卡面文案：选角界面单独一段「额外技能」，图鉴 / 属性面板 / 角色详解同读这一份。
## 攒与放各一行，每行都要在最窄那一档（详解卡列宽 404）里就是一行：加字先量宽，
## 撑成两行会把详解卡顶出屏（判据 LayoutCheck 的「道统选择·影者」那一档在管这件事）。
## 数字一律现读本表（口径 3）：改每层幅度、层数上限、还伤比例，这几行跟着走，别处不抄。
static func card_lines() -> Array[String]:
	return [
		"攒：闪避成功 +1 层影，每层武器伤害 +%d%%（至多 %d 层）" % [
			int(roundf(AMP_PER_STACK * 100.0)), MAX_STACKS],
		"放：随时点「影爆」踩碎，把躲掉的伤害按 %d%% 还给周身敌人并推开" % [
			int(roundf(STORE_RATIO * 100.0))],
	]

## 有没有东西可兑现：空影层时冲刺保持原样，不放环、不查怪
static func has_charge(ring: Array) -> bool:
	return not ring.is_empty()
