class_name BalanceSpiritPet
extends RefCounted

## 灵兽（随行伙伴）数值与回合成长公式
## 规约：全 static 纯函数，不读 autoload、不碰节点、不调全局 randf()

const DAMAGE_GROWTH: float = 1.18   ## 攻击类灵兽伤害每回合复利成长（18%，反超敌人 16% 血量成长，避免后期伤害不足）
const ECONOMY_GROWTH: float = 1.10  ## 聚宝蟾产出每回合复利成长（10%）
const SEARCH_INTERVAL: float = 0.12 ## 索敌节流（秒）

## 计算灵兽实际生效的综合伤害乘区（结合灵兽自身乘区、全局伤害乘区与元素伤害加成）
static func calc_pet_damage_mult(pet_damage_mult: float, global_damage_mult: float = 0.0, elemental_bonus: float = 0.0) -> float:
	var base := maxf(0.1, pet_damage_mult)
	var global_factor := maxf(0.1, 1.0 + global_damage_mult)
	var elem_factor := maxf(0.1, 1.0 + elemental_bonus * 0.5)
	return base * global_factor * elem_factor

## 焰灵狐火丹直接伤害：base_value(38) × wave复利 × 灵兽伤害乘区
static func fire_damage(wave: int, damage_mult: float) -> float:
	var base := 38.0 * pow(DAMAGE_GROWTH, float(maxi(wave, 1) - 1))
	return maxf(1.0, base * maxf(0.1, damage_mult))

## 焰灵狐灼烧每秒伤害：火丹直接伤害的 40%
static func fire_burn_dps(direct_damage: float) -> float:
	return maxf(1.0, direct_damage * 0.40)

## 焰灵狐灼烧持续时间（秒）
const FIRE_BURN_DURATION: float = 3.0
## 焰灵狐易伤幅度（被命中/灼烧目标受到伤害增加 15%）
const FIRE_VULNERABILITY_PCT: float = 0.15

## 雷灵雀雷击伤害：base_value(64) × wave复利 × 灵兽伤害乘区
static func thunder_damage(wave: int, damage_mult: float) -> float:
	var base := 64.0 * pow(DAMAGE_GROWTH, float(maxi(wave, 1) - 1))
	return maxf(1.0, base * maxf(0.1, damage_mult))

## 雷灵雀连锁次级目标伤害折损比（60%）
const THUNDER_CHAIN_RATIO: float = 0.60
## 雷灵雀连锁最大目标数
const THUNDER_CHAIN_MAX: int = 3
## 雷灵雀麻痹打断时长（秒）
const THUNDER_STUN_DURATION: float = 0.40

## 磐石猿震地伤害：base(34) × wave复利 × 灵兽伤害乘区
static func smash_damage(wave: int, damage_mult: float) -> float:
	var base := 34.0 * pow(DAMAGE_GROWTH, float(maxi(wave, 1) - 1))
	return maxf(1.0, base * maxf(0.1, damage_mult))

## 磐石猿震地半径：base(160) × 灵兽效果乘区
static func smash_radius(effect_mult: float) -> float:
	return clampf(160.0 * maxf(0.5, effect_mult), 100.0, 320.0)

## 磐石猿震地减速持续时间与减速比例
## 2026-10-20 调整：原「2 秒岩沼减速区」无感，改为命中即减速并延长至 3.5 秒（对齐冷却，范围内近乎常驻）
const SMASH_SLOW_DURATION: float = 3.5
const SMASH_SLOW_PCT: float = 0.50

## 玉露鹿治疗总量：(base_flat(12) + base_pct(2.0% max_hp)) × 灵兽效果乘区
## 2026-10-20 削弱：原 (20 + 2.5%maxhp)/2.5s 约 9HP/s 过强，降至约 5.5HP/s；拾取范围加成作为补偿真正接线
static func heal_value(max_health: float, effect_mult: float) -> float:
	var flat := 12.0
	var pct := max_health * 0.020
	return maxf(5.0, (flat + pct) * maxf(0.2, effect_mult))

## 玉露鹿治疗比例（保持向后兼容）：base(0.020) × 灵兽效果乘区
static func heal_ratio(effect_mult: float) -> float:
	return maxf(0.01, 0.020 * maxf(0.2, effect_mult))

## 玉露鹿生机加速与拾取范围加成
const YULU_BUFF_DURATION: float = 2.0
const YULU_SPEED_BONUS: float = 0.15
const YULU_PICKUP_BONUS: float = 0.40

## 聚宝蟾回合末产出金币：base(8) × wave复利 × 灵兽效果乘区
static func harvest_stones(wave: int, effect_mult: float) -> int:
	var base := 8.0 * pow(ECONOMY_GROWTH, float(maxi(wave, 1) - 1))
	return maxi(3, int(round(base * maxf(0.2, effect_mult))))

## 聚宝蟾战斗中单次金舌吸宝数量（兜底常量）
const JUCHAN_ATTRACT_COUNT: int = 5

## 聚宝蟾金舌鞭击伤害：base(30) × wave复利 × 灵兽伤害乘区
## 2026-10-20 重做：去掉战中「金舌吸宝」（回收掉落物鸡肋无感），改为鞭击最近敌人
static func tongue_damage(wave: int, damage_mult: float) -> float:
	var base := 30.0 * pow(DAMAGE_GROWTH, float(maxi(wave, 1) - 1))
	return maxf(1.0, base * maxf(0.1, damage_mult))

## 灵风貂风涡半径：base(220) × 灵兽效果乘区
static func vortex_radius(effect_mult: float) -> float:
	return clampf(220.0 * maxf(0.5, effect_mult), 120.0, 480.0)

## 灵风貂定身环横轴半径（px）：被卷到的敌人刹停在索敌椭圆（y 按 TARGETING_ELLIPSE_Y_RATIO
## 压扁，圆环会在正上/正下方骗过近战椭圆索敌）的这一段落点上。两头都有硬账：
## 下界 = 接触伤害判定（玩家 14 + 敌身 ~19.5 ≈ 34px）的 2 倍余量，定住的怪贴不到人；
## 上界 = 最弱近战射程（血饮狂刀 120），卷来的目标必然被近战自动锁到。
const MELEE_RING := 120.0

## 灵风貂卷击伤害：base(24) × wave复利 × 灵兽伤害乘区
static func vortex_damage(wave: int, damage_mult: float) -> float:
	var base := 24.0 * pow(DAMAGE_GROWTH, float(maxi(wave, 1) - 1))
	return maxf(1.0, base * maxf(0.1, damage_mult))

## 灵风貂定身时长：base(1.5) × 受击硬直抗性（小怪 1.0 / 精英 0.55 / Boss 0.25），地板 0.25s
static func pin_duration(stun_resist: float) -> float:
	return maxf(0.25, 1.5 * clampf(stun_resist, 0.0, 1.0))

## 灵风貂减速比例与持续时间
const VORTEX_SLOW_PCT: float = 0.40
const VORTEX_SLOW_DURATION: float = 2.0

## 灵风貂牵引冲量初速：硬直滑行段位移 = v0 × dt/(1-decay·dt) ≈ v0 / KNOCKBACK_DECAY_STUN，
## 反解 v0 = 位移 × 12 ⇒ 指数急刹恰好停在定身环上（与 _resolve_velocity 同一套位移模型）。
static func pull_impulse(distance: float) -> float:
	return maxf(0.0, distance) * 12.0

## 玄甲龟拦截/拒马半径：base(120) × 灵兽效果乘区
static func intercept_radius(effect_mult: float) -> float:
	return clampf(120.0 * maxf(0.5, effect_mult), 60.0, 240.0)

## 玄甲龟拒马震退距离
const XUANGUI_REPEL_FORCE: float = 100.0
## 玄甲护符濒危护盾基准吸收量（波1）
const XUANGUI_SHIELD_AMOUNT: float = 25.0

## 玄甲护符护盾量：基准(25) × wave复利（1.10/波，与聚宝蟾经济成长同拍，保证中后期仍能兜底）
static func shield_amount(wave: int) -> float:
	return XUANGUI_SHIELD_AMOUNT * pow(ECONOMY_GROWTH, float(maxi(wave, 1) - 1))

## 行为冷却：base_cd × 灵兽节拍乘区（地板 0.5s）
static func cooldown(base_cd: float, cooldown_mult: float) -> float:
	if base_cd <= 0.0:
		return 0.0
	return maxf(0.5, base_cd * clampf(cooldown_mult, 0.25, 2.0))
