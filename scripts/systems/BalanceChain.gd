class_name BalanceChain
extends RefCounted

## 链电体系数值表（2026-10-25 超级悟道「三道」重构新增）。
##
## 铁律：全 static 纯函数，不读 autoload、不碰节点、不调全局 randf()；
## 消费侧（ChainLightning / OnHitEffects / EnemyDeathFx / Player）自己取 GameManager 状态传进来。
##
## 四路雷电（紫电 / 雷劫 / 天罚 / 反震电场）共用一套「一次事件最多打几个目标」的尺子，
## 伤害口径分两类：
##   武器派生（紫电 / 雷霆弹幕）—— 按当次命中的实伤折算，武器越强链电越强；
##   固定基值（天罚 / 雷劫 / 反震）—— 基值 + 元素/反震加成，不随武器面板漂，
##   否则后期武器面板翻几倍时，这几张「机制卡」会退化成纯数值卡。

## 一次链电最多经过几个目标（含首个）
const MAX_HOPS := 3
## 每跳伤害相对首跳的折损：第 N 跳 = 首跳 × HOP_RATIO^(N-1)
const HOP_RATIO := 0.60
## 找下一个目标的搜索半径（px）
const CHAIN_RADIUS := 240.0
## 全局限流：两次链电事件的最小间隔（毫秒）。四路共用一个值 —— 既防满屏闪电，
## 也防「紫电打死人 → 雷劫 → 再打死」的递归风暴（深度闸兜底，见 MAX_DEPTH）。
const EVENT_GAP_MS := 90
## 递归深度上限：链电结算里打死敌人会再次触发雷劫，深度闸防止无限自激
const MAX_DEPTH := 2

## 天罚（暴击落雷）：固定基值 + 元素伤害加成
## （2026-10-25 二阶段上调 60/1.5 → 100/2.0：超级悟道一局只有 3 张，必须压过普通悟道满叠）
const CRIT_BOLT_BASE := 100.0
const CRIT_BOLT_ELEM_COEF := 2.0
## 雷劫（击杀链电）：固定基值 + 元素伤害加成（二阶段 30 → 50：清群核心卡，得炸得动中期小怪）
const KILL_CHAIN_BASE := 50.0
const KILL_CHAIN_ELEM_COEF := 1.5
## 反震电场（受击放电）：固定基值 + 有效反震百分比加成（二阶段 25 → 40）
const THORNS_BOLT_BASE := 40.0
const THORNS_BOLT_COEF := 40.0
## 反震放电的搜索半径
const THORNS_RADIUS := 220.0

## 万剑归宗（剑道进阶）已改判（2026-10-26）：不再按「每 N 次命中放一圈冲击波」结算，
## 数值与状态机整体迁到 scripts/weapons/SwordPhantom.gd（CHARGE_EVERY / DAMAGE_RATIO /
## ACQUIRE_RADIUS 与凝形-疾射-消散手感常量都在那边，机制实现与常量同文件更近）。
## 本文件只保留链电/五行/箭雨/血盾/兽群这些「命中后按固定基值结算」的口径。

## 紫电（雷法开道）：每 N 次武器出手放一次连锁闪电
const CHAIN_EVERY_ATTACKS := 3

## 五行轮转（命中附加随机异常）的强度口径：异常 dps 占当次实伤比例 / 持续秒数
const WUXING_BURN_RATIO := 0.35
const WUXING_BURN_DUR := 3.0
const WUXING_CHILL := 0.30
const WUXING_CHILL_DUR := 2.5
const WUXING_POISON_RATIO := 0.30
const WUXING_POISON_DUR := 3.0
## 五行归一（五行进阶）：每次命中同时挂三系，单系口径略低于轮转的单系（烧 0.35→0.28 / 毒 0.30→0.25），
## 换「三系全在」的确定性 —— 冰缓比例与持续与轮转同源
const GUIYI_BURN_RATIO := 0.28
const GUIYI_POISON_RATIO := 0.25

## 箭雨倾盆（箭道大成）：远程武器每 N 次出手落一轮箭雨
const ARROW_RAIN_EVERY := 6
## 一轮箭雨的支数 / 散布半径 / 坠落高度 / 单支落点判定半径 / 单支伤害占武器面板实伤比例
const ARROW_RAIN_COUNT := 5
const ARROW_RAIN_SPREAD := 90.0
const ARROW_RAIN_FALL_HEIGHT := 200.0
const ARROW_RAIN_HIT_RADIUS := 55.0
const ARROW_RAIN_DAMAGE_RATIO := 0.6

## 血海护盾（体修进阶）：满血时吸血溢出结成护盾
## 护盾上限 = 最大生命 × SHIELD_CAP_RATIO；盾被打穿那一刻向周身放电
const SHIELD_CAP_RATIO := 0.6
const SHIELD_BREAK_BASE := 60.0
const SHIELD_BREAK_HP_RATIO := 0.12
const SHIELD_BREAK_RADIUS := 200.0

## 兽群（灵兽进阶）：灵兽直击附带链电 —— 首跳伤害占灵兽实伤比例 / 跳数
const PET_CHAIN_RATIO := 0.5
const PET_CHAIN_HOPS := 2

## 紫电/雷霆弹幕的第 hop_index 跳伤害（hop_index 从 0 起算，0 = 首跳全额）
static func chain_hop_damage(base_damage: float, hop_index: int) -> float:
	return base_damage * pow(HOP_RATIO, float(maxi(0, hop_index)))

## 天罚落雷伤害
static func crit_bolt_damage(elemental_damage: float) -> float:
	return CRIT_BOLT_BASE + maxf(0.0, elemental_damage) * CRIT_BOLT_ELEM_COEF

## 雷劫链电伤害
static func kill_chain_damage(elemental_damage: float) -> float:
	return KILL_CHAIN_BASE + maxf(0.0, elemental_damage) * KILL_CHAIN_ELEM_COEF

## 反震电场伤害：thorns_pct 传 GameManager.get_effective_thorns()（0.4 = 40% 反震）
static func thorns_bolt_damage(thorns_pct: float) -> float:
	return THORNS_BOLT_BASE + maxf(0.0, thorns_pct) * THORNS_BOLT_COEF

## 箭雨单支伤害（按当次出手的武器面板实伤折算，与紫电同一条「武器派生」口径）
static func arrow_rain_damage(weapon_damage: float) -> float:
	return maxf(0.0, weapon_damage) * ARROW_RAIN_DAMAGE_RATIO

## 血海护盾上限
static func shield_cap(max_hp: float) -> float:
	return maxf(0.0, max_hp) * SHIELD_CAP_RATIO

## 血海护盾破碎放电伤害：固定基值 + 最大生命比例 + 元素加成
## （体修堆血，让「血牛」的盾碎反击也跟着厚）
static func shield_break_damage(max_hp: float, elemental_damage: float) -> float:
	return SHIELD_BREAK_BASE + maxf(0.0, max_hp) * SHIELD_BREAK_HP_RATIO \
		+ maxf(0.0, elemental_damage) * CRIT_BOLT_ELEM_COEF
