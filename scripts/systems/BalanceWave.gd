class_name BalanceWave
extends RefCounted

## 波次曲线：刷怪节奏、精英/Boss 波、危险度梯度。全部 static 纯函数。
## 与 GameBalance 同规约：不读 autoload、不碰节点、不调全局 randf()，随机由调用方传 roll。

# ---------------- 波次与刷怪 ----------------

# 2026-10-11 波次拉长：用户口径「每波时间好短、没打什么就结束了」。
# 根因不在时长（旧曲线 W1=22s 已比土豆兄弟固定 20s 长），而在同屏敌人稀（间隔慢/批量小/
# 预算低/小怪加厚 4.5×）——「时间够但没东西打」。直解是把刷怪密度顶上去，但 10-11 预算制
# 正是为治高密度卡顿而设，峰值同屏数不能放。故取折中：波次拉长 + 预算同比例放大，
# 总击杀数变多、单波更充实，而峰值同屏数（间隔/批量）不变 ⇒ 不重引入卡顿。
# 新曲线：W1=30.5s / W5=40.5s / W10=53s / W15=65.5s / W17+ 封顶 70s，20 波总战斗 ≈17.8min（旧 ≈13.7min）。
const WAVE_DURATION_BASE := 28.0
const WAVE_DURATION_PER_WAVE := 2.5
const WAVE_DURATION_MAX := 70.0
# 2026-10-10 打击感重塑：刷怪放缓 + 批量收窄（小怪加血 3.5 倍后单敌活得更久，
# 同屏密度由更少的刷入量维持，击杀成为「低频但每下都有读数」的事件）
const SPAWN_INTERVAL_BASE := 1.60
const SPAWN_INTERVAL_MIN := 0.45
const SPAWN_INTERVAL_PER_WAVE := 0.045
const SPAWN_BATCH_EVERY_WAVES := 6.0      ## 每多 6 波，一轮多刷 1 只
const SPAWN_BATCH_BONUS_CHANCE := 0.25    ## 额外一只的概率
# 2026-10-11 土豆兄弟式克制：波内总刷入预算 —— 间隔刷怪照旧，但全波累计刷出只数封顶，
# 预算耗尽即停手。旧口径「杀几只补几只」会把同屏恒定顶到上限（第 6 波起整波满载，
# 体感无限刷怪且是持续卡顿源）；预算制下越打越空，击杀速度重新变得有意义。
# 绑定点对照（旧总量 = 时长/间隔 × 平均批量，见 tests/balance_sim_check.gd 第 5 节）：
# W1~5 预算不触发（前期手感不变）；W6 54/73 ≈ -26%、W10 76/104 ≈ -27%、W12 起批量跳档后
# 收得更狠（~-51%）、W15 103/230 ≈ -55%、W20 131/425 ≈ -69%。危险度/角色的妖潮倍率由调用方乘。
# 2026-10-11 缩图+减怪（半场 680→500）：预算全程再降约 1/3（14/3.6/90 ⇒
# W1=17 / W5=32 / W10=50 / W20=86），单怪血量基数同步 +33% 补上压力，预算缺口照旧走经验补差。
const WAVE_SPAWN_BUDGET_BASE := 14.0
const WAVE_SPAWN_BUDGET_PER_WAVE := 3.6
const WAVE_SPAWN_BUDGET_MAX := 90.0

## 波内总刷入预算（纯函数）：精英/Boss 与分裂·产卵·召唤等衍生怪不占预算
static func wave_spawn_budget(wave: int) -> int:
	return int(minf(WAVE_SPAWN_BUDGET_BASE + float(maxi(wave, 1)) * WAVE_SPAWN_BUDGET_PER_WAVE, WAVE_SPAWN_BUDGET_MAX))
const ENEMY_HP_GROWTH := 1.16             ## 每波气血复利倍率（W5≈1.81 / W10≈3.80 / W15≈8.00 / W20≈16.89）
## 小怪基础血量整体倍率（精英/Boss 不吃这条，它们的厚度由基础值拉开）。
## 2026-10-10 打击感重塑：小怪厚度抬高、受击硬直、击退、火花、闪白这些反馈充分展现，杜绝一击秒杀。
## 2026-10-11 缩图减怪：刷入量 -33% 后单怪 +33% 血（4.5→6.0）补上压力，「少而硬」。
const MOB_HP_BASE_MULT := 6.0
const ENEMY_DMG_GROWTH := 1.06            ## 每波接触伤害复利倍率（前松后紧：W10≈1.69 / W20≈3.03）
## 敌伤整体基线倍率：所有敌人伤害的唯一总闸。
## 折进 enemy_dmg_mult 这一个出口 ⇒ 接触 / 冲刺 / 短咬 / 自爆 / 火球 / Boss 接触·环弹·震地
## 与 Boss 召唤的小怪全部同源跟着走，任何敌人脚本都不许再自己乘一遍。
## 2026-10-11 用户真机口径：「敌人伤害降低一点，我简单难度都感觉很容易死」。
## 根因：小怪厚度抬到 MOB_HP_BASE_MULT(4.5) 后怪在场时间变长，挨打频率顶到玩家无敌帧上限
##（0.55s/下 = 1.82 下/秒）——单下伤害直接等于每秒进伤。旧基线下危险度 0 裸装（120 血/0 甲）
## 站进常用杂怪群（基础接触伤 14）第 1 波单下发 14 = 11.7% 气血、只活 4.7s，第 5 波只剩 3.7s，
## 最低档没有试错空间，故把基线降到 0.65（W1 单下 10 = 8.3% 气血、活 6.6s；W5 活 5.5s）。
## 尺子与档位口径见 tests/balance_sim_check.gd 第 5 节「挨打侧生存余量」。
## 六档危险度的 +12%/档梯度（danger_dmg_mult）不受影响，整条梯子一起下移。
## 2026-10-11 缩图减怪：刷入量 -33% 后基线微回 0.65→0.68（W1 单下 ≈8.5% 气血，仍在 ≤9% 窗内）。
const ENEMY_DMG_BASE_MULT := 0.68
const ENEMY_STAT_VARIANCE := 0.10            ## 敌人属性 ±10% 随机浮动（同种怪个体差异）
const ENEMY_SPEED_VARIANCE := 0.12           ## 敌人移速 ±12% 随机浮动（土豆兄弟式快慢梯队：同屏同种怪不再整齐划一）
const ELITE_STONE_BONUS := 25             ## 精英击杀额外灵石

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

## 灵医每跳治疗量：随波次复利成长（与敌人伤害同一条 dmg 曲线，保治疗与输出同量级对抗）
static func healer_amount(wave: int) -> float:
	return 6.0 * pow(ENEMY_HP_GROWTH, float(maxi(wave, 1) - 1))

## 金蟾击杀金币：随波次成长（与灵石经济同量级）
static func looter_stone_reward(wave: int) -> int:
	return 12 + int(2.5 * float(maxi(wave, 1)))

static func wave_duration(wave: int) -> float:
	return minf(WAVE_DURATION_BASE + float(maxi(wave, 1)) * WAVE_DURATION_PER_WAVE, WAVE_DURATION_MAX)

## 刷怪间隔随波次收紧，到下限后不再变快（否则后期同屏爆量）
static func spawn_interval(wave: int) -> float:
	return maxf(SPAWN_INTERVAL_MIN, SPAWN_INTERVAL_BASE - float(maxi(wave, 1)) * SPAWN_INTERVAL_PER_WAVE)

## 一轮刷几只。roll 必须由调用方给（如 GameManager.rng.randf()）
static func spawn_batch(wave: int, roll: float) -> int:
	return 1 + int(float(maxi(wave, 1)) / SPAWN_BATCH_EVERY_WAVES) + (1 if roll < SPAWN_BATCH_BONUS_CHANCE else 0)

static func enemy_hp_mult(wave: int) -> float:
	return pow(ENEMY_HP_GROWTH, float(maxi(wave, 1) - 1))

## 敌人伤害的唯一倍率出口：整体基线 × 每波复利。
## 调用方（WaveSpawner 刷怪/Boss 注入、EnemyBase 产卵·分裂·召唤小怪）只乘这一条，
## 敌弹伤害按 contact_damage/13 反推、Boss 环弹与震地按系数派生，全链路同源。
static func enemy_dmg_mult(wave: int) -> float:
	return ENEMY_DMG_BASE_MULT * pow(ENEMY_DMG_GROWTH, float(maxi(wave, 1) - 1))

# ---------------- 精英 / Boss 波（固定关卡） ----------------

const ELITE_WAVES := [5, 15]             ## 精英波：铁甲魔傀小头目
const BOSS_WAVES := [10, 20]             ## 固定 Boss 关卡：血条上屏的魔君
const BOSS_HP_BASE := 6500.0             ## Boss 基础气血（适配神识分流与新法器基数：W10≈2.5万 / W20≈11万；成型 ~45s、极端 6 剑 ~12s）
const BOSS_CONTACT_BASE := 24.0          ## Boss 基础接触伤害
const BOSS_ATTACK_INTERVAL := 4.6        ## 特殊攻击循环间隔（秒）
const BOSS_RING_COUNT := 16              ## 环弹齐射数量
const BOSS_RING_COUNT_P2 := 8            ## 二阶段环弹增量
const BOSS_RING_DMG_MULT := 0.55         ## 环弹伤害 = 接触伤害 × 系数
const BOSS_BOLT_SPEED := 235.0           ## 环弹飞行速度
const BOSS_BOLT_SCALE := 1.5             ## 环弹视觉/碰撞放大
const BOSS_SLAM_WINDUP := 0.9            ## 震地冲击预警时长
const BOSS_SLAM_RADIUS := 175.0          ## 震地冲击半径
const BOSS_SLAM_DMG_MULT := 1.35         ## 震地伤害 = 接触伤害 × 系数
const BOSS_SUMMON_COUNT := 3             ## 召唤妖群数量
const BOSS_SUMMON_CAP := 16              ## 场面敌人达到该数后召唤不再生效（2026-10-10 随整体减潮下调）
const BOSS_PHASE2_AT := 0.5              ## 二阶段触发血线（≤50%）
const BOSS_PHASE2_INTERVAL_MULT := 0.7   ## 二阶段攻击间隔缩短倍率
const BOSS_PHASE2_SPEED_MULT := 1.25     ## 二阶段移速提升
const BOSS_KNOCKBACK_RESIST := 0.18      ## Boss 击退系数（越低越推不动）
const BOSS_STONE_REWARD := 150           ## Boss 击杀额外灵石奖励

## 固定 Boss 波：10/20 波，20 波后（无尽）每 10 波再逢魔君
static func is_boss_wave(n: int) -> bool:
	return n in BOSS_WAVES or (n > BOSS_WAVES.max() and n % 10 == 0)

## 精英波：5/15 波；无尽模式 20 波后每 3 波一次（Boss 波让位）
static func is_elite_wave(n: int, endless: bool = false) -> bool:
	return n in ELITE_WAVES or (endless and n > BOSS_WAVES.max() and n % 3 == 0 and not is_boss_wave(n))

## Boss 气血：与普通敌人同一条 hp 曲线，靠基础值拉开厚度差距
static func boss_hp(wave: int) -> float:
	return BOSS_HP_BASE * enemy_hp_mult(wave)

static func boss_contact_damage(wave: int) -> float:
	return ceilf(BOSS_CONTACT_BASE * enemy_dmg_mult(wave))

# ---------------- 危险度（通关解锁的难度梯度，仿土豆兄弟 Danger 0~5） ----------------

const DANGER_MAX := 5
const DANGER_HP_BASE := 1.08    ## 简单档基线气血（不再是 ×1.0 纯裸，给入门档一点压力）
const DANGER_HP_PER := 0.30    ## 每档妖兽气血 +30%
const DANGER_DMG_BASE := 1.04  ## 简单档基线伤害
const DANGER_DMG_PER := 0.16   ## 每档妖兽伤害 +16%
const DANGER_COUNT_BASE := 1.08  ## 简单档基线妖潮规模
const DANGER_COUNT_PER := 0.20  ## 每档妖潮规模 +20%

static func danger_hp_mult(danger: int) -> float:
	return DANGER_HP_BASE + float(clampi(danger, 0, DANGER_MAX)) * DANGER_HP_PER

static func danger_dmg_mult(danger: int) -> float:
	return DANGER_DMG_BASE + float(clampi(danger, 0, DANGER_MAX)) * DANGER_DMG_PER

static func danger_count_mult(danger: int) -> float:
	return DANGER_COUNT_BASE + float(clampi(danger, 0, DANGER_MAX)) * DANGER_COUNT_PER
