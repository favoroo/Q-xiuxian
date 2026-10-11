class_name BalanceCombat
extends RefCounted

## 战斗结算数值：护甲减伤、镜头创伤（震屏）、受击硬直/击退/斩杀反馈、妖狼长扑几何、
## 五行异常状态（灼烧/剧毒）、震退方向、集火韧性。全部 static 纯函数。
## 与 GameBalance 同规约：不读 autoload、不碰节点、不调全局 randf()。

# ---------------- 护甲 / 受伤 ----------------

const ARMOR_COEF := 0.08      ## 减伤 = 1 - 1/(1+护甲×0.08)
const DAMAGE_FLOOR := 1.0     ## 实伤保底，防止高护甲把伤害抹成 0

## 面板用的减伤比例（0~1）。注意它不含 DAMAGE_FLOOR，高护甲打小伤害时面板会略优于实际
static func armor_reduction(armor: float) -> float:
	return 1.0 - (1.0 / (1.0 + maxf(0.0, armor) * ARMOR_COEF))

## 实际扣血。Player 与 HUD 从此共用同一条公式，不再各写一套
static func incoming_damage(raw: float, armor: float) -> float:
	return maxf(DAMAGE_FLOOR, raw / (1.0 + maxf(0.0, armor) * ARMOR_COEF))

# ---------------- 玩家气血档位（读数取色的唯一一把尺）----------------
## 「什么时候算危险」只许有一处定义：HUD 那行血字的颜色、灵石阁顶栏气血徽记的底色、
## 详情卡里的提示，全部走 hp_is_low。以前 0.28 只写在 GameHUD 里，
## 商店要跟着变色就得手抄一遍 —— 抄的那一份永远不会跟着改。
const HP_LOW_RATIO := 0.28      ## 剩余气血占上限低于此档 = 危险（朱砂）

## 剩余比例（0~1）；上限为 0（玩家还没生成 / 单测空载）按满血算，不许出 NaN 与除零
static func hp_ratio(cur: float, max_v: float) -> float:
	return cur / max_v if max_v > 0.0 else 1.0

static func hp_is_low(cur: float, max_v: float) -> bool:
	return max_v > 0.0 and hp_ratio(cur, max_v) < HP_LOW_RATIO

static func hp_is_full(cur: float, max_v: float) -> bool:
	return max_v > 0.0 and cur >= max_v - 0.5

# ---------------- 打击感：镜头创伤（震屏） ----------------
## 震屏的唯一数学来源。口径（2026-10-08 用户口径：「一直摇不好，这效果要留给特殊场景」）：
##   1) 普通命中 / 普通小怪死亡 **一律不发创伤**，打击感交给挤压形变 + 受击火花 + 跳字 + 顿帧；
##   2) 创伤只发给「值得看的节点」：玩家受创、精英与首领的登场/震地/伏诛、界碑聚灵阵、落雷命中；
##   3) 即便将来有人拿高频事件乱调 add_trauma，「每秒预算 ÷ 每秒衰减」把最坏稳态创伤钉死在
##      0.34（对应位移 ±1.4px）：镜头最多只剩一点轻颤，不会再整局猛摇。
##      预算给的是上限而不是"刷着刷着就归零"，所以口径要盯稳态值，别只看预算比衰减小。

const TRAUMA_DECAY := 2.2          ## 每秒衰减量：震停耗时 = 创伤 / 本值
const TRAUMA_BUDGET := 0.75        ## 每秒最多可累加的创伤
const SHAKE_EXPONENT := 2.0        ## 震幅 = 创伤^n：小震只轻颤，重震才猛晃

## 最坏稳态创伤：调用方每秒把预算刷满时，镜头最终停在哪一格
static func trauma_steady_state() -> float:
	return minf(1.0, TRAUMA_BUDGET / TRAUMA_DECAY)

## 本帧实际允许叠加的创伤：先按「每秒剩余预算」夹制，再夹非负。
## 调用方负责记预算流水账（见 SmoothCamera），这里只做纯夹制，便于固定断言。
static func trauma_grant(amount: float, budget_left: float) -> float:
	return clampf(amount, 0.0, maxf(budget_left, 0.0))

## 创伤 → 震幅系数（0~1），位移与滚转都乘它
static func shake_amount(trauma: float) -> float:
	return pow(clampf(trauma, 0.0, 1.0), SHAKE_EXPONENT)

## 一次给定量能震多久（秒）：设置项文案与调参时的直观读数
static func shake_duration(trauma: float) -> float:
	return clampf(trauma, 0.0, 1.0) / TRAUMA_DECAY

# ---------------- 打击感：受击硬直 / 击退衰减 / 斩杀反馈 ----------------
## 这一组常量钉住「空洞骑士/死亡细胞风格」刀刀入肉、分级短击退与干脆刹停的手感读数（2026-10-10 打击感重构）。

const HIT_STUN_NORMAL := 0.14            ## 普通受击硬直（秒）：短促击退（~0.11s）后原地定身抽搐，期间主动追击归零
const HIT_STUN_CRIT := 0.20              ## 暴击受击硬直（秒）：更扎实的原地受创定身
const HIT_FREEZE_NORMAL := 0.035         ## 普通命中局部受创抽搐/定格时长（秒，~2帧）
const HIT_FREEZE_CRIT := 0.065           ## 暴击命中局部受创抽搐/定格时长（秒，~4帧）
const KNOCKBACK_IMPULSE_SCALE := 1.45    ## 击退初速度折算系数：轻武器短击退(~11-14px)，重武器强击退(~40-50px)
const KNOCKBACK_DECAY_STUN := 12.0       ## 硬直期间击退衰减率：0.11s内快速到位并干脆刹停，杜绝打冰球与持续滑行
const KNOCKBACK_DECAY_FREE := 24.0       ## 硬直结束后残余击退极速清零率
const KNOCKBACK_MAX_SPEED_NORMAL := 620.0 ## 普通受击初速上限（px/s）：单次击退位移严格封顶（~50px以内）
const KNOCKBACK_MAX_SPEED_CRIT := 780.0   ## 暴击受击初速上限（px/s）：暴击击退封顶（~65px以内）
const KNOCKBACK_HEAVY_SPEED := 240.0     ## 重击判定阈值（px/s）：触发重击音效与地面摩擦扬尘
const KNOCKBACK_HEAVY_DECAY_MULT := 1.0  ## 取消重击衰减打折（杜绝把怪物甩出半屏）
const KILL_KNOCKBACK_MULT := 1.3         ## 致命一刀击退适度放大
const KILL_LAUNCH_DURATION := 0.12       ## 尸体飞出急刹滑程（秒）
const KILL_LAUNCH_MAX := 42.0            ## 尸体飞出位移上限（px，防尸体像冰球一样滑出屏幕）
const KILL_HITSTOP_DURATION := 0.03      ## 击杀微顿帧时长（秒）
const KILL_HITSTOP_SCALE := 0.10         ## 击杀微顿帧时间倍率
const KILL_HITSTOP_MIN_INTERVAL := 0.12  ## 击杀顿帧最小间隔（尸潮限流，防连续顿帧锁死节奏）
const CRIT_TRAUMA_NORMAL := 0.12         ## 普通暴击追加创伤（2026-10-11：暴击从「只冲不摇」升级为可见摇晃；走每秒预算，最坏稳态不变）
const CRIT_TRAUMA_ELITE := 0.28          ## 精英暴击创伤（既有口径，提出来与普通暴击并列成表）
const CRIT_KILL_HITSTOP_DURATION := 0.055 ## 暴击击杀顿帧时长（秒）：比普通击杀微顿帧更「实」
const CRIT_KILL_HITSTOP_SCALE := 0.06    ## 暴击击杀顿帧时间倍率
const CRIT_KILL_HITSTOP_MIN_INTERVAL := 0.18 ## 暴击击杀顿帧最小间隔（秒，独立限流防锁死）
const CRIT_KILL_OVERKILL_FLOOR := 0.45   ## 暴击击杀的死亡爆散规模保底（溢出伤害不足时也按此放大）
const ZHUMU_MINION_CAP := 30             ## 百目妖产卵的场面硬上限（2026-10-10 随整体减潮由 45 下调）

# —— 命中反馈全局限流（2026-10-11 频闪治理）——
## 远程穿透/弹射/多弹齐射下每秒命中可达几十次，逐刀全量反馈会糊成满屏频闪+持续抖屏。
## 普通命中按最小间隔放行；暴击/精英作为「值得看」的节点直通（闸不消耗）。
const HIT_SPARK_MIN_INTERVAL := 0.08     ## 普通命中火花全局限流最小间隔（秒，≈12 次/秒封顶）
const KILL_BURST_MIN_INTERVAL := 0.10    ## 普通小怪死亡爆散全局限流最小间隔（秒，精英/Boss 直通）
const MICRO_KICK_MIN_INTERVAL := 0.09    ## 普通命中/普通击杀镜头微冲击全局限流最小间隔（秒）

# ---------------- 妖狼系长扑：实冲位移 / 走廊扫掠几何 ----------------
## 长扑是承诺型攻击：预警画多长，就得真撞得出多远、真判得了多宽。
## 位移之所以有闭式解，是因为冲刺段绕开了 900 px/s² 的速度吸附（起步即满速、收势线性刹停）——
## 旧写法让吸附插值自己爬速度，纸面 307px 实际要拖出一段"朝玩家拐弯"的滑行尾巴，
## 于是画的线、冲的段、判的口径是三套数（用户 2026-10-10：「根本冲刺不到我」）。

const CHARGE_BRAKE_END_SPEED_PCT := 0.0  ## 收势终点速度 = 峰速 × 它（0 = 刹到站定；>0 保留前滚，位移随之变长）

## 长扑真实位移（px）= 匀速冲刺段 + 线性收势段（梯形面积，故刹车项取一半）
static func charge_reach(peak_speed: float, dash_time: float, brake_time: float) -> float:
	return maxf(peak_speed, 0.0) * (maxf(dash_time, 0.0) + maxf(brake_time, 0.0) * (1.0 + CHARGE_BRAKE_END_SPEED_PCT) * 0.5)

## 点到线段最近点：冲刺走廊的扫掠判定用（本帧起点→终点就是狼身扫过的那一段）。
## 退化处理：线段零长时投影分母兜底 ⇒ 自动降级为点距，地图边界 clamp 那一帧不会误判成穿墙撞人。
static func seg_closest_point(seg_a: Vector2, seg_b: Vector2, p: Vector2) -> Vector2:
	var ab := seg_b - seg_a
	if ab.length_squared() < KNOCK_DIR_EPS:
		return seg_a
	var t := clampf((p - seg_a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return seg_a + ab * t

# ---------------- 五行异常状态（灼烧 / 剧毒）叠层与结算 ----------------

const BURN_STACK_RATIO := 0.25         ## 多源灼烧叠层共鸣系数：已处于灼烧时，叠加新灼烧量的 25%
const POISON_STACK_RATIO := 0.50       ## 剧毒叠层累加系数
const BURN_ELEM_TICK_COEF := 0.40      ## 每点元素伤害对每次灼烧跳字（0.5s）的额外伤害加成
const POISON_ELEM_TICK_COEF := 0.30    ## 每点元素伤害对每次剧毒跳字（0.5s）的额外伤害加成
const DOT_TICK_INTERVAL := 0.50        ## DoT 跳字结算周期（秒）

## 施加灼烧后的新 DPS：未灼烧时全额起算，已灼烧时在保留最高值基础上叠加 25% 共鸣伤害
static func stack_burn_dps(current_dps: float, incoming_dps: float) -> float:
	if current_dps <= 0.0:
		return maxf(0.0, incoming_dps)
	return maxf(current_dps, incoming_dps) + maxf(0.0, incoming_dps) * BURN_STACK_RATIO

## 施加剧毒后的新 DPS：持续累加
static func stack_poison_dps(current_dps: float, incoming_dps: float) -> float:
	return maxf(0.0, current_dps) + maxf(0.0, incoming_dps) * POISON_STACK_RATIO

## 单次灼烧跳字（每 0.5s）实际结算伤害：受元素伤害属性与离火羁绊倍率双重增幅
static func burn_tick_damage(burn_dps: float, elemental_damage: float, synergy_burn_mult: float = 1.0) -> float:
	var base_tick := maxf(0.0, burn_dps) * DOT_TICK_INTERVAL + maxf(0.0, elemental_damage) * BURN_ELEM_TICK_COEF
	return maxf(1.0, base_tick * maxf(1.0, synergy_burn_mult))

## 单次剧毒跳字（每 0.5s）实际结算伤害：受元素伤害属性增幅
static func poison_tick_damage(poison_dps: float, elemental_damage: float) -> float:
	var base_tick := maxf(0.0, poison_dps) * DOT_TICK_INTERVAL + maxf(0.0, elemental_damage) * POISON_ELEM_TICK_COEF
	return maxf(1.0, base_tick)

# ---------------- 震退方向 ----------------

const KNOCK_DIR_EPS := 0.0001   ## 方向退化为零向量的判定阈值（比的是长度平方）

## 法器震退的单位方向：以「受击点 − 施力点」的径向为主，但绝不把敌人往玩家身上推。
## 为什么要另算一支：BURST 类法器的落点是索敌分配（BalanceTargeting.assign_weapon_targets）
## 按角度扇区分的，常常砸在离玩家两三百像素的另一侧敌人上 —— 纯径向就会把「落点与玩家之间」
## 那圈敌人往玩家脸上拱（用户 2026-10-08：镇岳印「震一下，把敌人一波一波推到我身边来」）。
## 改法：径向带朝玩家的分量时把那一支投影掉 ⇒ 敌人侧身滑开；三点共线的纯对撞退化为直接外推。
## 输出恒为单位向量，所以各法器的击退力度数值一个字都不改。纯函数：入参出参只用值类型。
static func knock_dir(source: Vector2, enemy_pos: Vector2, player_pos: Vector2) -> Vector2:
	var radial := enemy_pos - source
	if radial.length_squared() < KNOCK_DIR_EPS:
		radial = enemy_pos - player_pos          # 施力点压在敌人身上：改按远离玩家推
	if radial.length_squared() < KNOCK_DIR_EPS:
		return Vector2.ZERO                      # 敌人和玩家重合，没有方向可言
	var dir := radial.normalized()
	var away := enemy_pos - player_pos
	if away.length_squared() < KNOCK_DIR_EPS:
		return dir                               # 敌人正贴在玩家身上：维持径向
	away = away.normalized()
	var along: float = dir.dot(away)
	if along >= 0.0:
		return dir                               # 本来就朝外，径向原样保留
	var out := dir - away * along                # 去掉「朝玩家」那一分量
	if out.length_squared() < KNOCK_DIR_EPS:
		return away                              # 纯对撞（玩家—敌人—落点共线）：直接外推
	return out.normalized()

# ---------------- 同目标短窗集火韧性（防一帧蒸发，保障受击打击感） ----------------

const FOCUS_FIRE_WINDOW := 0.22      ## 集火保护短窗（秒）
const FOCUS_FIRE_HIT2_MULT := 0.70  ## 窗口内第 2 击伤害倍率
const FOCUS_FIRE_HIT3_MULT := 0.50  ## 窗口内第 3 击及后续伤害倍率

## 纯函数：根据短窗内已有直击命中次数（recent_hits，0 = 窗口首击），计算本次直击受击乘区
static func focus_fire_mult(recent_hits: int) -> float:
	if recent_hits <= 0:
		return 1.0
	if recent_hits == 1:
		return FOCUS_FIRE_HIT2_MULT
	return FOCUS_FIRE_HIT3_MULT
