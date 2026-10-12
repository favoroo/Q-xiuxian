class_name BalanceSpiritBeast
extends RefCounted

## 祭坛召唤灵兽的数值（2026-10-11 远程吐息重做）：气血/丹弹伤害随波次成长、嘲讽半径、
## 风筝走位与吐息节奏。全部 static 纯函数，与 GameBalance 同规约：
## 不读 autoload、不碰节点、不调全局 randf()。

# ---------------- 成长曲线 ----------------

const BASE_HP := 220.0          ## 1 波召唤时的气血（要真能替玩家扛：约等于十几下小怪接触）
const HP_GROWTH := 1.10         ## 每波气血复利倍率（低于敌人 1.16：后期灵兽会被磨死，符合"血量耗尽即散"）
const BASE_DAMAGE := 16.0       ## 1 波召唤时的丹弹基础伤害
const DAMAGE_GROWTH := 1.08     ## 每波伤害复利倍率

## 召唤灵兽气血
static func max_hp_for_wave(wave: int) -> float:
	return BASE_HP * pow(HP_GROWTH, float(maxi(wave, 1) - 1))

## 丹弹基础伤害（命中时再乘召唤伤害乘区，由调用方乘）
static func damage_for_wave(wave: int) -> float:
	return BASE_DAMAGE * pow(DAMAGE_GROWTH, float(maxi(wave, 1) - 1))

# ---------------- 行为节奏 ----------------

const ATTACK_INTERVAL := 1.0    ## 吐息冷却（秒）：远程+风筝输出环境比贴脸安全，频率略低于旧撕咬抵回
const PREFER_RANGE_MIN := 110.0 ## 风筝甜区下沿：目标近过它就后退拉开（拖着被嘲讽追它的敌人绕圈）
const PREFER_RANGE_MAX := 190.0 ## 风筝甜区上沿 / 吐息出手距离：目标远过它就追近，进区即出手
const PROJECTILE_SPEED := 380.0 ## 丹弹飞行速度（低于法器剑丸 470：追踪修正补命中，别快得像法器）
const STRAFE_SPEED_RATIO := 0.5 ## 甜区内切向环绕的移速占比（绕圈输出，不傻站）
const CONTACT_RANGE := 30.0     ## 近身啃咬判定距离：无碰撞体积后敌人贴到这个距离仍咬得到它
const MOVE_SPEED := 150.0       ## 追击/拉开移速（快过小怪 110，风筝甩得开近战怪）
const HIT_INVINCIBLE := 0.5     ## 受击无敌帧（秒）：近身啃咬逐帧结算，没有它灵兽会被一秒磨没
const TAUNT_RADIUS := 200.0     ## 嘲讽半径：敌人在这个距离内有灵兽就改追灵兽
const SEARCH_INTERVAL := 0.1    ## 索敌节流（秒）：灵兽最多 3 只，10Hz 重索足够
const IDLE_FOLLOW_DIST := 90.0  ## 无敌人时巡游回玩家身边的触发距离
