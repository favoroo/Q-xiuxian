class_name BalanceSpiritBeast
extends RefCounted

## 祭坛召唤灵兽的数值（2026-10-15 三连灵羽弹重做）：生命/灵羽伤害随回合成长、嘲讽半径、
## 风筝走位与蓄力三连节奏。全部 static 纯函数，与 GameBalance 同规约：
## 不读 autoload、不碰节点、不调全局 randf()。

# ---------------- 成长曲线 ----------------

const BASE_HP := 220.0          ## 1 波召唤时的生命（要真能替玩家扛：约等于十几下小怪接触）
const HP_GROWTH := 1.10         ## 每回合生命复利倍率（低于敌人 1.16：后期灵兽会被磨死，符合"生命耗尽即散"）
const BASE_DAMAGE := 28.0       ## 1 波召唤时的灵羽单发伤害（2026-10-15 三连灵羽弹重做：16→28，一轮 3 发）
const DAMAGE_GROWTH := 1.08     ## 每回合伤害复利倍率

## 召唤灵兽生命
static func max_hp_for_wave(wave: int) -> float:
	return BASE_HP * pow(HP_GROWTH, float(maxi(wave, 1) - 1))

## 灵羽单发基础伤害（命中时再乘召唤伤害乘区，由调用方乘）
static func damage_for_wave(wave: int) -> float:
	return BASE_DAMAGE * pow(DAMAGE_GROWTH, float(maxi(wave, 1) - 1))

# ---------------- 行为节奏 ----------------

const ATTACK_INTERVAL := 1.6    ## 一轮三连灵羽弹的冷却（秒）：蓄力+三连为一轮，轮间隔（2026-10-15 三连重做：1.0 单发→1.6 一轮）
const BURST_COUNT := 3          ## 一轮连吐的灵羽弹数（突突突三连）
const BURST_GAP := 0.12         ## 连发间隔（秒）：每发后坐+音调递进
const CHARGE_TIME := 0.35       ## 吐息前蓄力时间（秒）：嘴边灵光球涨大（渲染器 charge_ratio 0→1）
const PREFER_RANGE_MIN := 110.0 ## 风筝甜区下沿：目标近过它就后退拉开（拖着被嘲讽追它的敌人绕圈）
const PREFER_RANGE_MAX := 190.0 ## 风筝甜区上沿 / 吐息出手距离：目标远过它就追近，进区即出手
const PROJECTILE_SPEED := 420.0 ## 灵羽弹飞行速度（2026-10-15 由 380 提速：三连节奏下追踪补命中仍保留）
const STRAFE_SPEED_RATIO := 0.5 ## 甜区内切向环绕的移速占比（绕圈输出，不傻站）
const CONTACT_RANGE := 30.0     ## 近身啃咬判定距离：无碰撞体积后敌人贴到这个距离仍咬得到它
const MOVE_SPEED := 150.0       ## 追击/拉开移速（快过小怪 110，风筝甩得开近战怪）
const MOVE_ACCEL := 900.0       ## 走位加速度（px/s²）：三段风筝速度平滑过渡的斜率（2026-10-15 抽搐修复，消除硬切跳变）
const HIT_INVINCIBLE := 0.5     ## 受击无敌帧（秒）：近身啃咬逐帧结算，没有它灵兽会被一秒磨没
const TAUNT_RADIUS := 200.0     ## 嘲讽半径：敌人在这个距离内有灵兽就改追灵兽
const SEARCH_INTERVAL := 0.1    ## 索敌节流（秒）：灵兽最多 3 只，10Hz 重索足够
const IDLE_FOLLOW_DIST := 90.0  ## 无敌人时巡游回玩家身边的触发距离
