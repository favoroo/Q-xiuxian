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

# ---------------- 寿命与同场上限（2026-10-25 祭坛重设计） ----------------

const LIFETIME_WAVES := 3       ## 灵兽存活回合数：召唤波起算共在场 3 个回合，第 4 个回合开始时消散（同场最多 3 只 ⇒ 滚动顶替）
const MAX_ACTIVE := 3           ## 同场灵兽数上限：满员再启动祭坛 → 顶替召唤波最早的那只

# ---------------- 分阶成长（2026-11-02 祭坛成长线重做） ----------------
## 灵兽出生阶段 = 召唤时的祭坛阶；之后每存活 1 个回合 +1 阶，最高 4 阶。
## 3 阶起体型进入「精怪」档，4 阶为「巨灵」档；体型由宿主缩放渲染器节点，本表只给倍率真值。

const MAX_STAGE := 4
## 阶段生命乘区（叠在波次成长之上）：1.0 / 1.18 / 1.42 / 1.75
const STAGE_HP_MULT: Array[float] = [1.0, 1.18, 1.42, 1.75]
## 阶段伤害乘区：1.0 / 1.14 / 1.34 / 1.60
const STAGE_DAMAGE_MULT: Array[float] = [1.0, 1.14, 1.34, 1.60]
## 阶段体型缩放：1.0 / 1.22 / 1.55 / 1.95（渲染器节点整体缩放，影子同步变大）
const STAGE_BODY_SCALE: Array[float] = [1.0, 1.22, 1.55, 1.95]
## 阶段连发数：1-2 阶保持三连，3 阶四连，4 阶五连
const STAGE_BURST_COUNT: Array[int] = [3, 3, 4, 5]
## 阶段穿透：4 阶灵羽可贯穿命中 2 个目标（pierce_left=2），其余单目标
const STAGE_PIERCE: Array[int] = [1, 1, 1, 2]
## 体型变大后近身啃咬/拥挤感知半径同步放大，避免敌人「咬不到/叠在身上」
const STAGE_CONTACT_BONUS := 8.0   ## 每阶追加的近身啃咬半径（px）
const STAGE_CROWD_BONUS := 10.0    ## 每阶追加的拥挤感知半径（px）

## 灵兽当前阶段：出生阶 + 存活回合数，封顶 MAX_STAGE
static func stage_for(altar_tier: int, waves_survived: int) -> int:
	return clampi(maxi(altar_tier, 1) + maxi(waves_survived, 0), 1, MAX_STAGE)

static func stage_hp_mult(stage: int) -> float:
	return STAGE_HP_MULT[clampi(stage, 1, MAX_STAGE) - 1]

static func stage_damage_mult(stage: int) -> float:
	return STAGE_DAMAGE_MULT[clampi(stage, 1, MAX_STAGE) - 1]

static func stage_body_scale(stage: int) -> float:
	return STAGE_BODY_SCALE[clampi(stage, 1, MAX_STAGE) - 1]

## 一轮连发数：3 阶 4 发、4 阶 5 发，其余沿用 ATTACK_INTERVAL 体系的 3 发
static func burst_count_for(stage: int) -> int:
	return STAGE_BURST_COUNT[clampi(stage, 1, MAX_STAGE) - 1]

## 灵羽可命中目标数：4 阶 2，其余 1（pierce_left 语义见 BladeProjectile：命中一次减 1）
static func pierce_for(stage: int) -> int:
	return STAGE_PIERCE[clampi(stage, 1, MAX_STAGE) - 1]

## 召唤灵兽生命（stage 默认 1 保持旧调用兼容）
static func max_hp_for_wave(wave: int, stage: int = 1) -> float:
	return BASE_HP * pow(HP_GROWTH, float(maxi(wave, 1) - 1)) * stage_hp_mult(stage)

## 灵羽单发基础伤害（命中时再乘召唤伤害乘区，由调用方乘；stage 默认 1 保持旧调用兼容）
static func damage_for_wave(wave: int, stage: int = 1) -> float:
	return BASE_DAMAGE * pow(DAMAGE_GROWTH, float(maxi(wave, 1) - 1)) * stage_damage_mult(stage)

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
const CROWD_RADIUS := 42.0      ## 拥挤感知半径（2026-10-24 拥挤状态优化）：敌人进入此范围给软分离漂移，贴脸权重最大
const CROWD_PUSH_SPEED := 110.0 ## 拥挤分离漂移速度（px/s）：被围时从人堆缓缓挤出，不瞬移不抖动
const MOVE_SPEED := 150.0       ## 追击/拉开移速（快过小怪 110，风筝甩得开近战怪）
const MOVE_ACCEL := 900.0       ## 走位加速度（px/s²）：三段风筝速度平滑过渡的斜率（2026-10-15 抽搐修复，消除硬切跳变）
const HIT_INVINCIBLE := 0.5     ## 受击无敌帧（秒）：近身啃咬逐帧结算，没有它灵兽会被一秒磨没
const TAUNT_RADIUS := 200.0     ## 嘲讽半径：敌人在这个距离内有灵兽就改追灵兽
const SEARCH_INTERVAL := 0.1    ## 索敌节流（秒）：灵兽最多 3 只，10Hz 重索足够
const IDLE_FOLLOW_DIST := 90.0  ## 无敌人时巡游回玩家身边的触发距离

## 近身啃咬判定距离：基础 CONTACT_RANGE，每阶 +8px（体型变大后同步放大）
static func contact_range_for(stage: int) -> float:
	return CONTACT_RANGE + STAGE_CONTACT_BONUS * float(clampi(stage, 1, MAX_STAGE) - 1)

## 拥挤软分离感知半径：基础 CROWD_RADIUS，每阶 +10px
static func crowd_radius_for(stage: int) -> float:
	return CROWD_RADIUS + STAGE_CROWD_BONUS * float(clampi(stage, 1, MAX_STAGE) - 1)
