class_name BalanceSpiritPet
extends RefCounted

## 灵兽（随行伙伴）数值与波次成长公式
## 规约：全 static 纯函数，不读 autoload、不碰节点、不调全局 randf()

const DAMAGE_GROWTH: float = 1.09   ## 攻击类灵兽伤害每波复利成长（9%）
const ECONOMY_GROWTH: float = 1.10  ## 聚宝蟾产出每波复利成长（10%）
const SEARCH_INTERVAL: float = 0.12 ## 索敌节流（秒）

## 焰灵狐火丹伤害：base_value(18) × wave复利 × 灵兽伤害乘区
static func fire_damage(wave: int, damage_mult: float) -> float:
	var base := 18.0 * pow(DAMAGE_GROWTH, float(maxi(wave, 1) - 1))
	return maxf(1.0, base * maxf(0.1, damage_mult))

## 雷灵雀雷击伤害：base_value(36) × wave复利 × 灵兽伤害乘区
static func thunder_damage(wave: int, damage_mult: float) -> float:
	var base := 36.0 * pow(DAMAGE_GROWTH, float(maxi(wave, 1) - 1))
	return maxf(1.0, base * maxf(0.1, damage_mult))

## 磐石猿震退伤害：base(12) × wave复利 × 灵兽伤害乘区
static func smash_damage(wave: int, damage_mult: float) -> float:
	var base := 12.0 * pow(DAMAGE_GROWTH, float(maxi(wave, 1) - 1))
	return maxf(1.0, base * maxf(0.1, damage_mult))

## 玉露鹿治疗比例：base(0.012) × 灵兽效果乘区
static func heal_ratio(effect_mult: float) -> float:
	return maxf(0.005, 0.012 * maxf(0.2, effect_mult))

## 聚宝蟾波末产出灵石：base(8) × wave复利 × 灵兽效果乘区
static func harvest_stones(wave: int, effect_mult: float) -> int:
	var base := 8.0 * pow(ECONOMY_GROWTH, float(maxi(wave, 1) - 1))
	return maxi(3, int(round(base * maxf(0.2, effect_mult))))

## 灵风貂风涡半径：base(220) × 灵兽效果乘区
static func vortex_radius(effect_mult: float) -> float:
	return clampf(220.0 * maxf(0.5, effect_mult), 120.0, 480.0)

## 灵风貂定身环横轴半径（px）：被卷到的敌人刹停在索敌椭圆（y 按 TARGETING_ELLIPSE_Y_RATIO
## 压扁，圆环会在正上/正下方骗过近战椭圆索敌）的这一段落点上。两头都有硬账：
## 下界 = 接触伤害判定（玩家 14 + 敌身 ~19.5 ≈ 34px）的 2 倍余量，定住的怪贴不到人；
## 上界 = 最弱近战射程（血饮狂刀 120），卷来的目标必然被近战自动锁到。
const MELEE_RING := 120.0

## 灵风貂卷击伤害：base(8) × wave复利 × 灵兽伤害乘区（伤害是添头，价值在定身窗口）
static func vortex_damage(wave: int, damage_mult: float) -> float:
	var base := 8.0 * pow(DAMAGE_GROWTH, float(maxi(wave, 1) - 1))
	return maxf(1.0, base * maxf(0.1, damage_mult))

## 灵风貂定身时长：base(1.5) × 受击硬直抗性（小怪 1.0 / 精英 0.55 / Boss 0.25），地板 0.25s
static func pin_duration(stun_resist: float) -> float:
	return maxf(0.25, 1.5 * clampf(stun_resist, 0.0, 1.0))

## 灵风貂牵引冲量初速：硬直滑行段位移 = v0 × dt/(1-decay·dt) ≈ v0 / KNOCKBACK_DECAY_STUN，
## 反解 v0 = 位移 × 12 ⇒ 指数急刹恰好停在定身环上（与 _resolve_velocity 同一套位移模型）。
## 距离上限天然被风涡半径圈住，本函数不封顶；负数钳 0（已在环上的目标只定身不位移）。
static func pull_impulse(distance: float) -> float:
	return maxf(0.0, distance) * 12.0

## 玄甲龟拦截半径：base(95) × 灵兽效果乘区
static func intercept_radius(effect_mult: float) -> float:
	return clampf(95.0 * maxf(0.5, effect_mult), 60.0, 200.0)

## 行为冷却：base_cd × 灵兽节拍乘区（地板 0.5s）
static func cooldown(base_cd: float, cooldown_mult: float) -> float:
	if base_cd <= 0.0:
		return 0.0
	return maxf(0.5, base_cd * clampf(cooldown_mult, 0.25, 2.0))
