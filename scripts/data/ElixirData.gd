class_name ElixirData
extends RefCounted

## 药爆（药王·额外技能）数据表：摔药罐——对自身回一口血，同时把药力炸向周身敌人
## （一次性毒伤，不挂持续中毒），并开一小段全伤害增益反打窗口。
## 旧版「服丹」是治疗溢出存药池再手动喝掉，实测攒放节奏太绕（2026-10-13 用户实测反馈）：
## 重做后与治疗技能同构——冷却好了就能放，回血比例固定、不吃溢出存储。
##
## 三条口径（同 ShadowStepData / ThunderData 规约）：
## 1. 全 static 纯函数，不读 autoload、不碰节点，数值只在本表；
## 2. BURST_RADIUS 既是判定半径也是环特效半径——画多大 == 判多大，不许用辉光糊大；
## 3. 卡面/详解里的药爆数字一律现读本表（card_lines），别处不抄。
## 技能是 HEAL 类带冷却（SkillData.Kind.HEAL，cooldown 字段真话在本表仅半径/比例等机制数），
## 免资源门控：冷却好了随时能放，战斗外按不动（与随行技能同一道闸）。

## 毒雾判定半径 = 环特效半径（像素）：影爆 120 的同档周身爆发，比治疗体感大一圈
const BURST_RADIUS := 130.0
## 自身回血 = 最大生命 × 该比例（对标治疗技能 35% 的一半略强：它是附赠不是主菜）
const HEAL_HP_RATIO := 0.18
## 毒雾基础伤害（不吃武器 tag 乘区；调用方乘短时增益乘区 buff_damage_mult）
## 走毒系口径：随 GameManager.elemental_damage 成长，给「堆元素」第二个兑现口
const BASE_DAMAGE := 10.0
const ELEMENTAL_RATIO := 1.2  ## 每点元素伤害 +1.2 毒伤（天雷是 2.0，毒雾低一档）
## 毒雾击退冲量（调用方乘玩家震退乘区，与武器击退同一把尺子）
const PUSH_IMPULSE := 90.0
## 药力反打：施放后全伤害增益持续（秒）与加成幅度（旧服丹 25% 太顶，重做后降档）
const BUFF_DURATION := 5.0
const BUFF_DAMAGE := 0.12

## 毒雾单次伤害（未吃任何乘区；调用方自行乘 GameManager.buff_damage_mult）
static func burst_damage(elemental_damage: float) -> float:
	return BASE_DAMAGE + maxf(0.0, elemental_damage) * ELEMENTAL_RATIO

## 药爆回血量（按当前最大生命算）
static func heal_amount(max_health: float) -> float:
	return max_health * HEAL_HP_RATIO

## 服丹后全伤害乘区（Player 写 GameManager.buff_damage_mult，到期回 1.0）
static func buff_mult() -> float:
	return 1.0 + BUFF_DAMAGE

## 卡面文案：选角/详解/图鉴同读这一份，数字现读本表（口径 3）。
## 每条一行，按详解卡最窄列宽（404）量过：加字先量宽。
static func card_lines() -> Array[String]:
	return [
		"摔药罐：回复 %d%% 生命，周身 %d 像素内敌人受一次毒伤" % [
			int(roundf(HEAL_HP_RATIO * 100.0)), int(roundf(BURST_RADIUS))],
		"毒伤 %d + 元素伤害 ×%.1f；%d 秒内全伤害 +%d%%（冷却 %d 秒）" % [
			int(roundf(BASE_DAMAGE)), ELEMENTAL_RATIO, int(roundf(BUFF_DURATION)),
			int(roundf(BUFF_DAMAGE * 100.0)), COOLDOWN],
	]

const COOLDOWN := 12.0  ## 药爆冷却秒数（真话在 SkillData.DEFS.elixir.cooldown，此处仅为卡面显示）


