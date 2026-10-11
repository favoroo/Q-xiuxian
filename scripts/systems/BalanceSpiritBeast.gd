class_name BalanceSpiritBeast
extends RefCounted

## 祭坛召唤灵兽的数值（2026-10-11 祭坛强化）：气血/撕咬伤害随波次成长、嘲讽半径、
## 追击与攻击节奏。全部 static 纯函数，与 GameBalance 同规约：
## 不读 autoload、不碰节点、不调全局 randf()。

# ---------------- 成长曲线 ----------------

const BASE_HP := 220.0          ## 1 波召唤时的气血（要真能替玩家扛：约等于十几下小怪接触）
const HP_GROWTH := 1.10         ## 每波气血复利倍率（低于敌人 1.16：后期灵兽会被磨死，符合"血量耗尽即散"）
const BASE_DAMAGE := 16.0       ## 1 波召唤时的撕咬基础伤害
const DAMAGE_GROWTH := 1.08     ## 每波伤害复利倍率

## 召唤灵兽气血
static func max_hp_for_wave(wave: int) -> float:
	return BASE_HP * pow(HP_GROWTH, float(maxi(wave, 1) - 1))

## 撕咬基础伤害（命中时再乘召唤伤害乘区，由调用方乘）
static func damage_for_wave(wave: int) -> float:
	return BASE_DAMAGE * pow(DAMAGE_GROWTH, float(maxi(wave, 1) - 1))

# ---------------- 行为节奏 ----------------

const ATTACK_INTERVAL := 0.85   ## 撕咬冷却（秒）
const ATTACK_RANGE := 30.0      ## 撕咬出手距离（嘴够得到的距离；敌人身位 ~19 + 灵兽身位 14 内必然够到）
const MOVE_SPEED := 150.0       ## 追击移速（快过小怪 110，追得上逃窜的远程怪）
const KNOCK_FORCE := 140.0      ## 撕咬击退力度（轻武器档，别把敌人推出嘲讽圈）
const HIT_INVINCIBLE := 0.5     ## 受击无敌帧（秒）：敌人接触伤害逐帧结算，没有它灵兽会被一秒磨没
const TAUNT_RADIUS := 200.0     ## 嘲讽半径：敌人在这个距离内有灵兽就改追灵兽
const SEARCH_INTERVAL := 0.1    ## 索敌节流（秒）：灵兽最多 3 只，10Hz 重索足够
const IDLE_FOLLOW_DIST := 90.0  ## 无敌人时巡游回玩家身边的触发距离
