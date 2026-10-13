class_name BalanceWave
extends RefCounted

## 回合曲线：刷怪节奏、精英/Boss 回合、危险度梯度。全部 static 纯函数。
## 与 GameBalance 同规约：不读 autoload、不碰节点、不调全局 randf()，随机由调用方传 roll。

# ---------------- 回合与刷怪 ----------------

# 2026-10-11 回合拉长：用户口径「每回合时间好短、没打什么就结束了」。
# 根因不在时长（旧曲线 W1=22s 已比土豆兄弟固定 20s 长），而在同屏敌人稀（间隔慢/批量小/
# 预算低/小怪加厚 4.5×）——「时间够但没东西打」。直解是把刷怪密度顶上去，但 10-11 预算制
# 正是为治高密度卡顿而设，峰值同屏数不能放。故取折中：回合拉长 + 预算同比例放大，
# 总击杀数变多、单回合更充实，而峰值同屏数（间隔/批量）不变 ⇒ 不重引入卡顿。
# 新曲线：W1=30.5s / W5=40.5s / W10=53s / W15=65.5s / W17+ 封顶 70s，20 波总战斗 ≈17.8min（旧 ≈13.7min）。
const WAVE_DURATION_BASE := 28.0
const WAVE_DURATION_PER_WAVE := 2.5
const WAVE_DURATION_MAX := 70.0
# 2026-10-10 打击感重塑：刷怪放缓 + 批量收窄（小怪加血 3.5 倍后单敌活得更久，
# 同屏密度由更少的刷入量维持，击杀成为「低频但每下都有读数」的事件）
const SPAWN_INTERVAL_BASE := 1.60
const SPAWN_INTERVAL_MIN := 0.45
const SPAWN_INTERVAL_PER_WAVE := 0.045
const SPAWN_BATCH_EVERY_WAVES := 6.0      ## 每多 6 波，一回合多刷 1 只
const SPAWN_BATCH_BONUS_CHANCE := 0.25    ## 额外一只的概率
# 2026-10-11 土豆兄弟式克制：回合内总刷入预算 —— 间隔刷怪照旧，但全回合累计刷出只数封顶，
# 预算耗尽即停手。旧口径「杀几只补几只」会把同屏恒定顶到上限（第 6 波起整回合满载，
# 体感无限刷怪且是持续卡顿源）；预算制下越打越空，击杀速度重新变得有意义。
# 绑定点对照（旧总量 = 时长/间隔 × 平均批量，见 tests/balance_sim_check.gd 第 5 节）：
# W1~5 预算不触发（前期手感不变）；W6 54/73 ≈ -26%、W10 76/104 ≈ -27%、W12 起批量跳档后
# 收得更狠（~-51%）、W15 103/230 ≈ -55%、W20 131/425 ≈ -69%。危险度/角色的敌潮倍率由调用方乘。
# 2026-10-11 缩图+减怪（半场 680→500）：预算全程再降约 1/3（14/3.6/90 ⇒
# W1=17 / W5=32 / W10=50 / W20=86），单怪生命基数同步 +33% 补上压力，预算缺口照旧走经验补差。
const WAVE_SPAWN_BUDGET_BASE := 14.0
const WAVE_SPAWN_BUDGET_PER_WAVE := 3.6
const WAVE_SPAWN_BUDGET_MAX := 90.0
# 2026-10-13 无尽深层三涨：正常局 20 波通关，故「波数 > 20」即等价无尽深层，曲线分段
# 无需读 endless_mode（保持纯函数）。深层段预算不再封顶 90，从 W20 的 86 只起每波 +4，
# 到 180 硬顶（约 W44 饱和）；伤害/生命复利同步提档（见 DEEP_*_GROWTH），同屏密度
# 走 endless_swarm_mult。四个成长率是独立旋钮，试玩后可单独回调。
const DEEP_WAVE_THRESHOLD := 20          ## 深层分段点（正常局通关波，> 此值走深层曲线）
const DEEP_BUDGET_PER_WAVE := 4.0        ## 深层每波预算增量（自 W20 的 86 续算）
const DEEP_BUDGET_MAX := 180.0           ## 深层预算硬顶（约 W44 饱和）
const DEEP_DMG_GROWTH := 1.09            ## 深层每波伤害复利（20 波段是 1.06；W40 单下 ≈11.5×基线）
const DEEP_HP_GROWTH := 1.18             ## 深层每波生命复利（20 波段是 1.16；W40 血 ≈225×基线）
const DEEP_SWARM_PER_WAVE := 0.06        ## 深层每波同屏密度增量（+6%/波，随危险度/角色倍率同乘）
const DEEP_SWARM_MAX := 2.0              ## 深层同屏密度放大硬顶（约 W37 触顶）

## 回合内总刷入预算（纯函数）：精英/Boss 与分裂·产卵·召唤等衍生怪不占预算。
## ≤20 波走旧曲线封顶 90；深层从 W20=86 续 +4/波，封顶 DEEP_BUDGET_MAX。
static func wave_spawn_budget(wave: int) -> int:
	var w := float(maxi(wave, 1))
	if w <= float(DEEP_WAVE_THRESHOLD):
		return int(minf(WAVE_SPAWN_BUDGET_BASE + w * WAVE_SPAWN_BUDGET_PER_WAVE, WAVE_SPAWN_BUDGET_MAX))
	return int(minf(WAVE_SPAWN_BUDGET_BASE + float(DEEP_WAVE_THRESHOLD) * WAVE_SPAWN_BUDGET_PER_WAVE
		+ (w - float(DEEP_WAVE_THRESHOLD)) * DEEP_BUDGET_PER_WAVE, DEEP_BUDGET_MAX))
const ENEMY_HP_GROWTH := 1.16             ## 每回合生命复利倍率（W5≈1.81 / W10≈3.80 / W15≈8.00 / W20≈16.89）
## 小怪基础生命整体倍率（精英/Boss 不吃这条，它们的厚度由基础值拉开）。
## 2026-10-10 打击感重塑：小怪厚度抬高、受击硬直、击退、火花、闪白这些反馈充分展现，杜绝一击秒杀。
## 2026-10-11 缩图减怪：刷入量 -33% 后单怪 +33% 血（4.5→6.0）补上压力，「少而硬」。
const MOB_HP_BASE_MULT := 6.0
const ENEMY_DMG_GROWTH := 1.06            ## 每回合接触伤害复利倍率（前松后紧：W10≈1.69 / W20≈3.03）
## 敌伤整体基线倍率：所有敌人伤害的唯一总闸。
## 折进 enemy_dmg_mult 这一个出口 ⇒ 接触 / 冲刺 / 短咬 / 自爆 / 火球 / Boss 接触·环弹·震地
## 与 Boss 召唤的小怪全部同源跟着走，任何敌人脚本都不许再自己乘一遍。
## 2026-10-11 用户真机口径：「敌人伤害降低一点，我简单难度都感觉很容易死」。
## 根因：小怪厚度抬到 MOB_HP_BASE_MULT(4.5) 后怪在场时间变长，挨打频率顶到玩家无敌帧上限
##（0.55s/下 = 1.82 下/秒）——单下伤害直接等于每秒进伤。旧基线下危险度 0 裸装（120 血/0 甲）
## 站进常用杂怪群（基础接触伤 14）第 1 波单下发 14 = 11.7% 生命、只活 4.7s，第 5 波只剩 3.7s，
## 最低档没有试错空间，故把基线降到 0.65（W1 单下 10 = 8.3% 生命、活 6.6s；W5 活 5.5s）。
## 尺子与档位口径见 tests/balance_sim_check.gd 第 5 节「挨打侧生存余量」。
## 六档危险度的 +12%/档梯度（danger_dmg_mult）不受影响，整条梯子一起下移。
## 2026-10-11 缩图减怪：刷入量 -33% 后基线微回 0.65→0.68（W1 单下 ≈8.5% 生命，仍在 ≤9% 窗内）。
## 2026-10-13 用户真机口径反转：「简单模式伤害好低，死都死不了」。0.68 下 W1 站进怪群
## 活 6.6s、W10 半肉 Build 活 9.3s，配合走位/回血实际不可能死。基线提至 0.80（+18%），
## W1 单下 12 = 10% 生命、站进怪群活 5.5s；W10 半肉活 7.9s——仍远低于旧 1.0 的"太痛"口径。
const ENEMY_DMG_BASE_MULT := 0.80
const ENEMY_STAT_VARIANCE := 0.10            ## 敌人属性 ±10% 随机浮动（同种怪个体差异）
const ENEMY_SPEED_VARIANCE := 0.12           ## 敌人移速 ±12% 随机浮动（土豆兄弟式快慢梯队：同屏同种怪不再整齐划一）
const ELITE_STONE_BONUS := 25             ## 精英击杀额外金币

# ---------------- 精英变异（2026-10-12，仿土豆兄弟 Elite Mutation） ----------------
## 精英过血线触发一次性行为变异：坦克出震地、突进加侧射、远程压近身。
## 阈值与倍率集中在此（铁律 1），EnemyBase._enter_mutation() 只读不写。
const ELITE_MUTATION_HP_PCT := 0.6           ## 精英变异触发血线（≤60%）
const MUT_GOLEM_SPEED_MULT := 1.35           ## 铁甲巨怪变异：移速提升
const MUT_GOLEM_SLAM_INTERVAL := 3.2         ## 铁甲巨怪变异：震地周期（秒）
const MUT_GOLEM_SLAM_RADIUS := 130.0         ## 铁甲巨怪变异：震地半径（Boss 175 的精英档）
const MUT_GOLEM_SLAM_WINDUP := 0.8           ## 铁甲巨怪变异：震地预警时长
const MUT_GOLEM_SLAM_DMG_MULT := 1.2         ## 铁甲巨怪变异：震地伤害 = 接触伤害 × 系数
const MUT_CHILEI_INTERVAL_MULT := 0.55       ## 烈雷兽变异：长扑周期缩短倍率
const MUT_CHILEI_SIDE_BOLTS := 1             ## 烈雷兽变异：冲刺起步向左右各放的火球数
const MUT_JIANSHA_BOLT_COUNT := 5            ## 剑客亡灵变异：剑气 3→5 连
const MUT_JIANSHA_INTERVAL_MULT := 0.7       ## 剑客亡灵变异：剑气间隔缩短倍率
const MUT_JIANSHA_RANGE := 180.0             ## 剑客亡灵变异：风筝距离 280→180（压近身）

## 灵医每跳治疗量：随回合复利成长（与敌人伤害同一条 dmg 曲线，保治疗与输出同量级对抗。
## 2026-10-13 改走 enemy_hp_mult 同源出口，深层复利提档自动跟涨）
static func healer_amount(wave: int) -> float:
	return 6.0 * enemy_hp_mult(wave)

## 毒妖投毒每跳伤害：随回合成长（与接触伤害同一条 dmg 曲线）。
## 口径说明：毒潭是持续区域伤害，玩家在圈内按受击无敌帧（0.55s）节流 ⇒ 站满 5 秒约 9 跳。
## 每跳伤害对齐「接触伤害 × 0.5」档位（比蹭一下轻、比站着挨打疼），随回合复利自动跟涨。
## 命名与 BalanceCombat.poison_tick_damage（玩家剧毒 DoT 的两参版）刻意区分：那是玩家侧
## 异常状态的跳字公式，这里是敌人投放区域的每跳伤害，同一个词在两条链上语义不同。
static func poison_area_damage(wave: int) -> float:
	return 3.0 * enemy_dmg_mult(wave)

## 毒潭半径：随回合小幅扩张（前期 62 → 后期封顶 84，控制后期地面覆盖面积）
static func poison_radius(wave: int) -> float:
	return minf(62.0 + float(maxi(wave, 1) - 6) * 1.5, 84.0)

## 金蟾击杀金币：随回合成长（与金币经济同量级）
static func looter_stone_reward(wave: int) -> int:
	return 12 + int(2.5 * float(maxi(wave, 1)))

static func wave_duration(wave: int) -> float:
	return minf(WAVE_DURATION_BASE + float(maxi(wave, 1)) * WAVE_DURATION_PER_WAVE, WAVE_DURATION_MAX)

## 刷怪间隔随回合收紧，到下限后不再变快（否则后期同屏爆量）
static func spawn_interval(wave: int) -> float:
	return maxf(SPAWN_INTERVAL_MIN, SPAWN_INTERVAL_BASE - float(maxi(wave, 1)) * SPAWN_INTERVAL_PER_WAVE)

## 一回合刷几只。roll 必须由调用方给（如 GameManager.rng.randf()）
static func spawn_batch(wave: int, roll: float) -> int:
	return 1 + int(float(maxi(wave, 1)) / SPAWN_BATCH_EVERY_WAVES) + (1 if roll < SPAWN_BATCH_BONUS_CHANCE else 0)

static func enemy_hp_mult(wave: int) -> float:
	var w := maxi(wave, 1)
	if w <= DEEP_WAVE_THRESHOLD:
		return pow(ENEMY_HP_GROWTH, float(w - 1))
	## 深层从 W20 值续算，复利提档至 DEEP_HP_GROWTH（分段处连续、单调）
	return pow(ENEMY_HP_GROWTH, float(DEEP_WAVE_THRESHOLD - 1)) * pow(DEEP_HP_GROWTH, float(w - DEEP_WAVE_THRESHOLD))

## 敌人伤害的唯一倍率出口：整体基线 × 每回合复利。
## 调用方（WaveSpawner 刷怪/Boss 注入、EnemyBase 产卵·分裂·召唤小怪）只乘这一条，
## 敌弹伤害按 contact_damage/BOLT_DMG_BASE_REF 反推、Boss 环弹与震地按系数派生，全链路同源。
## 2026-10-13 深层分段：正常局（≤20 波）走 ENEMY_DMG_GROWTH 旧梯子不动；>20 波从
## W20 值续按 DEEP_DMG_GROWTH 复利（分段处连续），治「无尽后期挨打不痛」。
static func enemy_dmg_mult(wave: int) -> float:
	var w := maxi(wave, 1)
	var base := ENEMY_DMG_BASE_MULT * pow(ENEMY_DMG_GROWTH, float(mini(w, DEEP_WAVE_THRESHOLD) - 1))
	if w <= DEEP_WAVE_THRESHOLD:
		return base
	return base * pow(DEEP_DMG_GROWTH, float(w - DEEP_WAVE_THRESHOLD))

## 无尽深层同屏密度倍率：≤20 波恒 1.0（正常局零影响），深层每波 +6%、封顶 ×2.0。
## 调用方 WaveSpawner._spawn_regular 乘在同屏上限上，与 danger_count_mult、
## 角色敌潮倍率同乘——只放天花板，刷入量仍由 wave_spawn_budget 闸住。
static func endless_swarm_mult(wave: int) -> float:
	var w := maxi(wave, 1)
	if w <= DEEP_WAVE_THRESHOLD:
		return 1.0
	return minf(1.0 + DEEP_SWARM_PER_WAVE * float(w - DEEP_WAVE_THRESHOLD), DEEP_SWARM_MAX)

## 敌弹（火球）伤害缩放基准：bolt_damage × (contact_damage / 本值)，让火球跟着回合复利走。
## 这个分母就是 XieXiuEnemy.tscn 的 contact_damage 初值（13.0），而消费它的不止邪修一家：
## 影魅、剑煞精英（26.0）、烈雷兽变异（18.0）全都借它当标尺。所以改任何一方的 .tscn
## 接触伤害前先看这里 —— 分母不动而分子被调，火球伤害会静默漂移（改 13→16 即 +23%），
## 且没有任何编译期或运行期提示。
const BOLT_DMG_BASE_REF := 13.0

# ---------------- 掉落与死亡反馈几何（铁律 1：调掉落只改这里，不翻 EnemyBase） ----------------
## 这一组原先散在 EnemyBase._die / _teleport_near_player / _split_offspring / _spawn_minion 里，
## 调「掉几颗、散多远、闪多远」得翻逻辑文件。现在与 ELITE_STONE_BONUS、碎晶率同属一个文件，
## 同一个「掉落经济」不再被拆在两处。
const ELITE_GEM_COUNT := 5              ## 精英宝石数（普通怪恒 1 颗）
const GEM_SCATTER_RADIUS := 24.0        ## 多颗宝石的方形散布半径（±px；单颗不散）
const ELITE_GEM_EXP := 8                ## 精英单颗宝石经验（普通怪吃自己的 exp_reward）
const BLINK_DISTANCE := 210.0           ## 影魅闪现距离：绕玩家侧翼落到这个半径上
const BLINK_MAP_INSET := 40.0           ## 闪现落点的边界内缩（不许闪出竞技场）
const SPLIT_SCATTER_RADIUS := 26.0      ## 血蛆死亡分裂幼体的散布半径
const MINION_SCATTER_RADIUS := 34.0     ## 蛛母产卵落点半径
const HEAL_ORB_SCATTER_RADIUS := 16.0   ## 灵药滋生额外回复珠的偏移半径（±px）
const DEATH_KICK_CAMERA := 8.5          ## 精英伏诛震屏强度
const DEATH_MICRO_KICK := 2.5           ## 普通怪死亡微冲量（px，确认感；走全局限流闸）
const STONE_FLOAT_OFFSET := 30.0        ## 金蟾金币飘字相对尸体的上抬量
const CORPSE_SWELL_SCALE := 1.28        ## 死灭膨胀幅度（Anticipation 那一下）

# ---------------- 刷怪出生点几何（铁律 1：五处刷怪口共用，调出生安全距离只改这里） ----------------
## 土豆兄弟式全图随机出生 + 远离玩家安全区：随机抽一点，距玩家太近就沿径向推开再夹回场内。
## 原先这段十行样板在 WaveSpawner 里内联了五份，参数各自漂移（常规怪能比精英贴边界 15px 更近），
## 调「出生安全距离」一件事要同步改 4~5 处。现在实现收敛为 WaveSpawner._spawn_pos_away_from_player，
## 三档参数在此登记：常规怪 / 精英系（精英·金蟾）/ Boss。藏宝匣是第四档（推开不走径向）。
const SPAWN_INSET_MOB := 45.0           ## 常规怪：竞技场边界内缩
const SPAWN_MIN_DIST_MOB := 130.0       ## 常规怪：距玩家的最小安全距离
const SPAWN_PUSH_MOB := 160.0           ## 常规怪：太近时沿径向推开的距离
const SPAWN_INSET_ELITE := 60.0         ## 精英系：边界内缩（比常规怪少贴 15px 边）
const SPAWN_MIN_DIST_ELITE := 180.0     ## 精英系：最小安全距离
const SPAWN_PUSH_ELITE := 220.0         ## 精英系：推开距离
const SPAWN_INSET_BOSS := 60.0          ## Boss：边界内缩
const SPAWN_MIN_DIST_BOSS := 200.0      ## Boss：最小安全距离（登场更要面子）
const SPAWN_PUSH_BOSS := 240.0          ## Boss：推开距离
const SPAWN_INSET_CHEST := 130.0        ## 藏宝匣：边界内缩（诱玩家走位，别贴边）
const SPAWN_MIN_DIST_CHEST := 130.0     ## 藏宝匣：最小安全距离
const SPAWN_PUSH_CHEST := 180.0         ## 藏宝匣：推开距离（不走径向，固定向右）

# ---------------- 精英 / Boss 回合（固定关卡） ----------------

const ELITE_WAVES := [5, 15]             ## 精英回合：铁甲魔傀小头目
const BOSS_WAVES := [10, 20]             ## 固定 Boss 关卡：血条上屏的魔君
const BOSS_HP_BASE := 6500.0             ## Boss 基础生命（适配神识分流与新武器基数：W10≈2.5万 / W20≈11万；成型 ~45s、极端 6 剑 ~12s）
const BOSS_CONTACT_BASE := 24.0          ## Boss 基础接触伤害
const BOSS_ATTACK_INTERVAL := 3.8        ## 特殊攻击循环间隔（秒）
const BOSS_RING_COUNT := 16              ## 环弹齐射数量
const BOSS_RING_COUNT_P2 := 8            ## 二阶段环弹增量
const BOSS_RING_DMG_MULT := 0.55         ## 环弹伤害 = 接触伤害 × 系数
const BOSS_RING_CURVE_ANG := 0.85        ## 双层交错环弹弧线偏转角速度（rad/s）
const BOSS_RING_LAYER_DELAY := 0.28      ## 双层环弹第 2 层发射间隔（秒）
const BOSS_BOLT_SPEED := 235.0           ## 环弹飞行速度
const BOSS_BOLT_SCALE := 1.5             ## 环弹视觉/碰撞放大
const BOSS_FAN_WAVES := 3                ## 扇形连射狙击波数
const BOSS_FAN_WAVES_P2 := 4             ## 二阶段扇形连射波数
const BOSS_FAN_COUNT := 5                ## 每波扇形火球数
const BOSS_FAN_SPREAD := 0.18            ## 扇形相邻弹夹角（rad）
const BOSS_FAN_WAVE_INTERVAL := 0.22     ## 扇形连射波间间隔（秒）
const BOSS_FAN_BASE_SPEED := 250.0       ## 扇形首波弹速（逐波 +45）
const BOSS_FAN_DMG_MULT := 0.50          ## 扇形弹伤害 = 接触伤害 × 系数
const BOSS_SPIRAL_DURATION := 1.2        ## 螺旋风暴持续时长（秒）
const BOSS_SPIRAL_INTERVAL := 0.09       ## 螺旋风暴喷射步进间隔（秒）
const BOSS_SPIRAL_ARMS := 2              ## 基础螺旋臂数
const BOSS_SPIRAL_ARMS_FINAL := 4        ## 魔尊/狂暴螺旋臂数
const BOSS_SPIRAL_ROT_SPEED := 3.6       ## 螺旋旋转角速度（rad/s）
const BOSS_SPIRAL_BOLT_SPEED := 240.0    ## 螺旋弹飞行速度
const BOSS_SPIRAL_ANGULAR := 0.48        ## 螺旋弹自身微弧偏转（rad/s）
const BOSS_SPIRAL_DMG_MULT := 0.45       ## 螺旋弹伤害 = 接触伤害 × 系数
const BOSS_SPLIT_BOMB_COUNT := 2         ## 分裂子母弹：母弹颗数
const BOSS_SPLIT_BOMB_COUNT_FINAL := 3   ## 狂暴/魔尊母弹颗数
const BOSS_SPLIT_BOMB_SPEED := 135.0     ## 母弹飞行速度（慢速压迫）
const BOSS_SPLIT_BOMB_SCALE := 2.2       ## 母弹视觉/碰撞放大倍数（半径同源）
const BOSS_SPLIT_BOMB_FUSE := 0.95       ## 母弹飞行分裂引信（秒）
const BOSS_SPLIT_BOMB_CHILD_COUNT := 8   ## 母弹分裂出的子火球数
const BOSS_SPLIT_BOMB_CHILD_SPEED := 275.0 ## 子火球扩散速度
const BOSS_SPLIT_BOMB_CHILD_SCALE := 1.0 ## 子火球缩放
const BOSS_SPLIT_BOMB_DMG_MULT := 0.70   ## 母弹直击伤害系数
const BOSS_SPLIT_CHILD_DMG_MULT := 0.45  ## 子火球伤害系数
const BOSS_CHARGE_WINDUP := 0.75         ## Boss 破阵冲锋预警时长（秒）
const BOSS_CHARGE_DURATION := 0.55       ## Boss 破阵冲锋持续时长（秒）
const BOSS_CHARGE_BRAKE := 0.20          ## Boss 破阵冲锋收势刹车时长（秒）
const BOSS_CHARGE_SPEED_MUL := 3.4       ## Boss 破阵冲锋移速倍率
const BOSS_CHARGE_HIT_RADIUS := 36.0     ## Boss 破阵冲锋走廊判定半径（与预警线宽同源）
const BOSS_CHARGE_DMG_MULT := 1.25       ## Boss 破阵冲锋伤害系数
const BOSS_CHARGE_SIDE_BOLTS := 2        ## 冲锋起步向两侧各洒出的封路火球数
const BOSS_SKY_FIRE_COUNT := 3           ## 追踪天火连环轰炸落点数
const BOSS_SKY_FIRE_COUNT_P2 := 4        ## 二阶段追踪天火落点数
const BOSS_SKY_FIRE_INTERVAL := 0.32     ## 天火落点生成间隔（秒）
const BOSS_SKY_FIRE_WINDUP := 0.85       ## 单处天火预警时长（秒）
const BOSS_SKY_FIRE_RADIUS := 95.0       ## 天火轰炸半径（预警圈与结算同源）
const BOSS_SKY_FIRE_DMG_MULT := 1.15     ## 天火轰炸伤害 = 接触伤害 × 系数
const BOSS_SLAM_WINDUP := 0.9            ## 震地冲击预警时长
const BOSS_SLAM_RADIUS := 175.0          ## 震地冲击半径
const BOSS_SLAM_DMG_MULT := 1.35         ## 震地伤害 = 接触伤害 × 系数
const BOSS_SUMMON_COUNT := 3             ## 召唤妖群数量
const BOSS_SUMMON_CAP := 16              ## 场面敌人达到该数后召唤不再生效（2026-10-10 随整体减潮下调）
const BOSS_PHASE2_AT := 0.5              ## 二阶段触发血线（≤50%）
const BOSS_PHASE2_INTERVAL_MULT := 0.7   ## 二阶段攻击间隔缩短倍率
const BOSS_PHASE2_SPEED_MULT := 1.25     ## 二阶段移速提升
const BOSS_KNOCKBACK_RESIST := 0.18      ## Boss 击退系数（越低越推不动）
const BOSS_STONE_REWARD := 150           ## Boss 击杀额外金币奖励

## 固定 Boss 回合：10/20 波，20 回合后（无尽）每 5 波再逢魔君
## （2026-10-13：用户口径深层 Boss 战要保留且加密，10 → 5 波一场：25/30/35…）
static func is_boss_wave(n: int) -> bool:
	return n in BOSS_WAVES or (n > BOSS_WAVES.max() and n % 5 == 0)

## 精英回合：5/15 波；无尽模式 20 回合后每 3 波一次（Boss 回合让位）
static func is_elite_wave(n: int, endless: bool = false) -> bool:
	return n in ELITE_WAVES or (endless and n > BOSS_WAVES.max() and n % 3 == 0 and not is_boss_wave(n))

## Boss 生命：与普通敌人同一条 hp 曲线，靠基础值拉开厚度差距
static func boss_hp(wave: int) -> float:
	return BOSS_HP_BASE * enemy_hp_mult(wave)

static func boss_contact_damage(wave: int) -> float:
	return ceilf(BOSS_CONTACT_BASE * enemy_dmg_mult(wave))

# ---------------- 危险度（通关解锁的难度梯度，仿土豆兄弟 Danger 0~5） ----------------

const DANGER_MAX := 5
const DANGER_HP_BASE := 1.08    ## 简单档基线生命（不再是 ×1.0 纯裸，给入门档一点压力）
const DANGER_HP_PER := 0.30    ## 每档敌人生命 +30%
const DANGER_DMG_BASE := 1.04  ## 简单档基线伤害
const DANGER_DMG_PER := 0.16   ## 每档敌人伤害 +16%
const DANGER_COUNT_BASE := 1.08  ## 简单档基线敌潮规模
const DANGER_COUNT_PER := 0.20  ## 每档敌潮规模 +20%

static func danger_hp_mult(danger: int) -> float:
	return DANGER_HP_BASE + float(clampi(danger, 0, DANGER_MAX)) * DANGER_HP_PER

static func danger_dmg_mult(danger: int) -> float:
	return DANGER_DMG_BASE + float(clampi(danger, 0, DANGER_MAX)) * DANGER_DMG_PER

static func danger_count_mult(danger: int) -> float:
	return DANGER_COUNT_BASE + float(clampi(danger, 0, DANGER_MAX)) * DANGER_COUNT_PER
