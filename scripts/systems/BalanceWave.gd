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
# 2026-10-16 表再放宽一档（用户口径「每回合的倒计时目前是多少，适当增加一点」「怪总量不动」）：
# 28/2.5/70 ⇒ 33/2.9/80，曲线 W1=35.9s / W5=47.5s / W10=62s / W15=76.5s / W17+ 封顶 80s，
# 20 波按表跑满 ≈20.7min（旧 ≈17.8min，+16%）。WAVE_SPAWN_BUDGET_* 一个字没动 ⇒
# 每波总刷入只数、单批规模、刷怪间隔全部不变（峰值同屏不变、不加怪）。
# 这条表在 10-15 分批清剿制下只是**上限**：真正结束一回合的是「预算刷尽 + 场上清空」
# （WaveSpawner._tide_spent 提前出口，余秒折余时赏）。所以本档拉长的实际收益落在
# 「打不完预算的那一段」——中后期与深层波次原本 70s 到点、剩下的怪根本没刷出来，
# 现在多给的那 10s 让它们刷得出来；前期能打完预算的波，长度仍由击杀速度决定。
const WAVE_DURATION_BASE := 33.0
const WAVE_DURATION_PER_WAVE := 2.9
const WAVE_DURATION_MAX := 80.0
# 2026-10-10 打击感重塑：刷怪放缓 + 批量收窄（小怪加血 3.5 倍后单敌活得更久，
# 同屏密度由更少的刷入量维持，击杀成为「低频但每下都有读数」的事件）
const SPAWN_INTERVAL_BASE := 1.60
const SPAWN_INTERVAL_MIN := 0.45
const SPAWN_INTERVAL_PER_WAVE := 0.045
const SPAWN_BATCH_EVERY_WAVES := 6.0      ## 每多 6 波，一回合多刷 1 只
const SPAWN_BATCH_BONUS_CHANCE := 0.25    ## 额外一只的概率

# ---------------- 分批清剿制与并发合围（2026-10-15） ----------------
## 清剿完一批后的呼吸间隙（秒），供玩家捡拾灵石和走位调整。
## 2026-10-16 节奏紧凑化：0.8 → 0.6（配合刷新阈值爬坡，压缩批间空窗）。
const BATCH_CLEAR_COOLDOWN := 0.6
## 中后期对峙超时（秒）：若玩家未能在此时限内清剿，且未达同屏上限，允许并发注入下一批合围。
## 2026-10-16 节奏紧凑化：6.5 → 5.5（对峙容忍收紧，下一批来得更快）。
const BATCH_STALEMATE_TIMEOUT := 5.5
## 允许并发 2 批的起始波次（第 1~5 波严格单批清剿，节奏清晰）
const CONCURRENT_BATCH_MIN_WAVE := 6

# ---------------- 批次刷新阈值爬坡（2026-10-16 节奏紧凑化） ----------------
## 「场上还剩几只就开始刷下一批」的阈值随波数爬坡（原先全程 ≤1 只）。
## 口径与 WaveSpawner 判据同源：active_enemies = 场上活妖（含 dying 尸体）+ 凝聚中的预警，
## 所以阈值 3 的观感约等于 2 只活怪（尸体与 1.1s 凝聚预警各占一拍）。
## 前期严格单批清剿保留喘息，中后期并发度逐步提升，批间空窗显著缩短。
const BATCH_REFILL_EARLY := 1            ## 爬坡起点阈值（与旧行为一致）
const BATCH_REFILL_MID := 2              ## 中期阈值
const BATCH_REFILL_LATE := 3             ## 后期阈值
const BATCH_REFILL_MID_WAVE := 4         ## 第 4 波起用中期阈值
const BATCH_REFILL_LATE_WAVE := 10       ## 第 10 波起用后期阈值

## 批次刷新阈值（纯函数）：W1-3 → 1，W4-9 → 2，W10+ → 3。
## 阈值提高后 WaveSpawner 两处判定（呼吸间隙进出 + 清剿推进）必须同源读它，
## 且判定 1 补同屏上限闸（见 WaveSpawner._process_fight），防止后期临界超 cap。
static func batch_refill_threshold(wave: int) -> int:
	var w := maxi(wave, 1)
	if w >= BATCH_REFILL_LATE_WAVE:
		return BATCH_REFILL_LATE
	elif w >= BATCH_REFILL_MID_WAVE:
		return BATCH_REFILL_MID
	return BATCH_REFILL_EARLY

# 2026-10-11 土豆兄弟式克制：回合内总刷入预算 —— 间隔刷怪照旧，但全回合累计刷出只数封顶，
# 预算耗尽即停手。
# 2026-10-15 分批清剿制（用户口径「敌人数量太多了，无穷无尽像纯割草，看都看不过来。减少数量、
# 增强血量，杀完一波再来一波，后面关卡也能同时有两批或三批；前期 5-8，后期 8-12 或更多」）：
# 预算全程平滑削减约 26%（8.0/2.2/54 ⇒ W1=10 / W5=19 / W10=30 / W20=52），
# 单怪生命基数同步提档至 11.5（8.5→11.5，+35% 肉度，杜绝秒杀，每只动作清晰有针对性周旋），
# 经验掉落补偿乘数 MOB_KILL_EXP_MULT 提升至 1.75（10×1.75=17.5 守恒原 14×1.25=17.5 经济）。
const WAVE_SPAWN_BUDGET_BASE := 8.0
const WAVE_SPAWN_BUDGET_PER_WAVE := 2.2
const WAVE_SPAWN_BUDGET_MAX := 54.0
# 2026-10-13 深层三涨：20 波是破境波，故「波数 > 20」即等价深层波次，曲线分段
# 无需读任何模式开关（保持纯函数）。深层段预算从 W20 的 52 只起每波 +4，
# 到 135 硬顶；伤害/生命复利同步提档（见 DEEP_*_GROWTH），同屏密度
# 走 endless_swarm_mult。
# 2026-10-28 无限闯关：20 波不再是终点，只是「破境波」；DEEP_WAVE_THRESHOLD 与
# GameManager.MILESTONE_WAVE 同值，但纯函数层不读 autoload，故此处独立登记一份。
const DEEP_WAVE_THRESHOLD := 20          ## 深层分段点（破境波，> 此值走深层曲线；同 GameManager.MILESTONE_WAVE）
const DEEP_BUDGET_PER_WAVE := 4.0        ## 深层每波预算增量（自 W20 的 52 只起续算）
const DEEP_BUDGET_MAX := 135.0          ## 深层预算硬顶（约 W41 饱和）
const DEEP_DMG_GROWTH := 1.12            ## 深层每波伤害复利（20 波段是 1.06；深层加速提档）
const DEEP_HP_GROWTH := 1.22             ## 深层每波生命复利（20 波段是 1.16；深层加速提档）
const DEEP_SWARM_PER_WAVE := 0.08        ## 深层每波同屏密度增量（+8%/波，随危险度/角色倍率同乘）
const DEEP_SWARM_MAX := 2.2              ## 深层同屏密度放大硬顶

## 回合内总刷入预算（纯函数）：精英/Boss 与分裂·产卵·召唤等衍生怪不占预算。
## ≤20 波走曲线封顶 54；深层从 W20=52 续 +3/波，封顶 DEEP_BUDGET_MAX。
static func wave_spawn_budget(wave: int) -> int:
	var w := float(maxi(wave, 1))
	if w <= float(DEEP_WAVE_THRESHOLD):
		return int(round(minf(WAVE_SPAWN_BUDGET_BASE + w * WAVE_SPAWN_BUDGET_PER_WAVE, WAVE_SPAWN_BUDGET_MAX)))
	return int(round(minf(WAVE_SPAWN_BUDGET_BASE + float(DEEP_WAVE_THRESHOLD) * WAVE_SPAWN_BUDGET_PER_WAVE
		+ (w - float(DEEP_WAVE_THRESHOLD)) * DEEP_BUDGET_PER_WAVE, DEEP_BUDGET_MAX)))

## 动态同屏敌人上限（纯函数，2026-10-15 分批清剿制）：
## 前期（W1~5）5~8 只（单批），中期（W6~12）8~12 只（允许 2 批并发），后期（W13~20）12~16 只（2~3 批合围），
## 深层波次结合 endless_swarm_mult 持续增长（封顶 26）。
## 2026-10-17 性能专项绝对硬顶（用户拍板）：cap 只在刷怪口夹「基础值」，
## WaveSpawner 的最终同屏数还会乘 danger_count_mult（顶档 D1 噩梦 = 2.08）与角色敌潮倍率，
## 深层极端构建可叠到 ~95 只 —— 那是节点规模的绝对上限来源，帧率无法数学保证。
## MAX_ENEMIES_HARD_CAP 48 是「任何乘区叠满后」的最终同屏硬顶（20 波内常规峰值 ~33 不受影响）。
const MAX_ENEMIES_HARD_CAP := 48

static func max_enemies_cap(wave: int) -> int:
	var w := maxi(wave, 1)
	if w <= 5:
		return 6 + int(float(w - 1) * 0.5)
	elif w <= 12:
		return 8 + int(float(w - 5) * 0.57)
	elif w <= DEEP_WAVE_THRESHOLD:
		return 12 + int(float(w - 12) * 0.5)
	else:
		var base := 16.0 + float(w - DEEP_WAVE_THRESHOLD) * 0.4
		return int(round(minf(base * endless_swarm_mult(w), 26.0)))

const ENEMY_HP_GROWTH := 1.16             ## 每回合生命复利倍率（W5≈1.81 / W10≈3.80 / W15≈8.00 / W20≈16.89）
## 小怪基础生命整体倍率（精英/Boss 不吃这条，它们的厚度由基础值拉开）。
## 2026-10-15 分批清剿制：配合刷怪预算 -26%，单怪血量基数由 8.5 提档至 11.5（+35% 肉度），
## 告别一击秒杀与纯割草，每个怪物的走位、弹幕与动作清晰可辨，击杀有扎实手感。
const MOB_HP_BASE_MULT := 11.5
## 小怪击杀经验/金币腿补偿倍率：与 WAVE_SPAWN_BUDGET_* 联动（改预算必须同步改它）。
## 预算 -26% 后单怪掉落按 ×1.75 放大，让每波总经验收入完全守恒（10×1.75=17.5 对应原 14×1.25=17.5）。
const MOB_KILL_EXP_MULT := 1.75
## 单只小怪击杀经验（纯函数）：exp_reward × 补偿倍率取整。掉落（EnemyBase._die）与
## 刷怪补差均值统计（WaveSpawner）共用这一个出口，两边口径不许漂。
static func mob_kill_exp(exp_reward: int) -> int:
	return int(round(float(maxi(exp_reward, 0)) * MOB_KILL_EXP_MULT))
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
## 危险度梯度（danger_dmg_mult）不受影响，整条梯子一起下移。
## 2026-10-11 缩图减怪：刷入量 -33% 后基线微回 0.65→0.68（W1 单下 ≈8.5% 生命，仍在 ≤9% 窗内）。
## 2026-10-13 用户真机口径反转：「简单模式伤害好低，死都死不了」。0.68 下 W1 站进怪群
## 活 6.6s、W10 半肉 Build 活 9.3s，配合走位/回血实际不可能死。基线提至 0.80（+18%），
## W1 单下 12 = 10% 生命、站进怪群活 5.5s；W10 半肉活 7.9s——仍远低于旧 1.0 的"太痛"口径。
const ENEMY_DMG_BASE_MULT := 0.80
const ENEMY_STAT_VARIANCE := 0.10            ## 敌人属性 ±10% 随机浮动（同种怪个体差异）
const ENEMY_SPEED_VARIANCE := 0.12           ## 敌人移速 ±12% 随机浮动（土豆兄弟式快慢梯队：同屏同种怪不再整齐划一）
const ELITE_STONE_BONUS := 25             ## 精英击杀额外金币

# ---------------- 敌群集行为（2026-10-23：分离排斥 / 包围方位） ----------------
## 背景：旧版全部直线插值追玩家，同屏 3 只以上收束到一点叠成一坨，读不出轮廓也读不出包夹意图。
## 两条都只改「转向」不改步速（合速度夹回 eff_speed），数值平衡零扰动。
## 数学在 scripts/systems/EnemyFlock.gd（static 纯函数），这里只放尺子。
const FLOCK_SEPARATION_RADIUS := 60.0   ## 分离半径（px）：约三只小怪碰撞半径之和，够把一圈摊开
## 分离推力占有效移速的比例上限。>1 是必要的：所有怪都朝玩家一个点挤，径向分量会被追引力吃掉，
## 只有横向分量能摊开队形；实测 0.85 时 6 只围挤稳态仍只摊到 18px（视觉上还是叠一起），
## 1.4 时摊到 26px+（能读出个体轮廓）。推力是「重叠瞬间」的，稳态会自己回到追击速度。
const FLOCK_SEPARATION_STRENGTH := 1.4
const FLOCK_ORBIT_BIAS_MAX := 0.52      ## 包围方位偏置上限（弧度 ≈30°，正负决定包抄顺/逆时针）
const FLOCK_ORBIT_CLOSE_RADIUS := 150.0 ## 进入该距离（px）才开始绕向自己的扇区；远处仍直线压来
const FLOCK_ORBIT_TANGENT := 0.35       ## 方位走位里混入的切向分量占比（越大越像"绕圈"）

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
const MUT_XINGPAN_RING_COUNT := 16          ## 玄天星盘变异后环弹发数
const MUT_XINGPAN_RING_INTERVAL_MULT := 0.65## 玄天星盘变异后环弹间隔倍率
const MUT_XINGPAN_BOLT_COUNT := 6           ## 玄天星盘变异后扇形狙击发数
const MUT_XINGPAN_ROCK_INTERVAL := 4.8      ## 玄天星盘变异后解锁落石间隔
const MUT_WANDU_POISON_INTERVAL_MULT := 0.6 ## 万毒祭司变异后投毒冷却倍率
const MUT_WANDU_FIELD_RADIUS_MULT := 1.25   ## 万毒祭司变异后禁区扩域倍率
const MUT_WANDU_SPAWN_INTERVAL_MULT := 0.65 ## 万毒祭司变异后召唤冷却倍率

# ---------------- 精英常驻招式（2026-10-22，W5/W15 精英从「血厚木桩」升级为双招式） ----------------
## 设计口径：精英的招牌技能从「60% 血线变异才解锁」改为「进场即常驻」，
## 变异则从「解锁技能」升格为「二阶段强化」（多段/连锁/扩域）。
## 数值全部集中在此，EnemyBase 只读；场景 .tscn 只做引用赋值。

## 铁甲魔傀·常驻震地（进场即威胁，变异后升格三连震）
const GOLEM_SLAM_INTERVAL := 4.2         ## 常驻震地周期（秒）
const GOLEM_SLAM_RADIUS := 115.0         ## 常驻震地半径（变异 130，Boss 175 的精英档）
const GOLEM_SLAM_WINDUP := 0.9           ## 常驻震地预警时长
const GOLEM_SLAM_DMG_MULT := 1.1         ## 常驻震地伤害 = 接触伤害 × 系数
const MUT_GOLEM_SLAM_HITS := 3           ## 变异震地总段数（首段 + 2 段余波）
const MUT_GOLEM_SLAM_ECHO_GAP := 0.45    ## 变异余波间隔（秒）：每段给一次横向走位窗口
const MUT_GOLEM_SLAM_RADIUS_GROW := 1.15 ## 变异余波逐段半径扩张倍率

## 铁甲魔傀·落石轰炸（第二招式：克制贴脸风筝，预判落点 + 多点预警）
const GOLEM_ROCK_INTERVAL := 6.5         ## 落石周期（秒）
const GOLEM_ROCK_COUNT := 3              ## 常驻落石点数
const MUT_GOLEM_ROCK_COUNT := 4          ## 变异落石点数
const GOLEM_ROCK_RADIUS := 85.0          ## 单点落石半径：预警圈 = 判定圈（同源）
const GOLEM_ROCK_WINDUP := 0.9           ## 落石预警时长（与震地同档，读法统一）
const GOLEM_ROCK_DMG_MULT := 0.9         ## 单点落石伤害 = 接触伤害 × 系数
const GOLEM_ROCK_SPREAD := 140.0         ## 落点散布半径（首点锁玩家预判位，其余环绕散布）
const GOLEM_ROCK_LEAD := 0.35            ## 首点预判量（玩家速度 × 它，匀速跑位会被算中）

## 赤雷兽·雷环齐射（第二招式：中距离封锁走位；变异增发）
const CHILEI_RING_INTERVAL := 5.0        ## 雷环周期（秒）
const CHILEI_RING_COUNT := 8             ## 常驻雷环弹数
const CHILEI_RING_SPEED := 150.0         ## 雷环弹速（px/s）
const CHILEI_RING_DMG_MULT := 0.7        ## 单颗雷环伤害 = 接触伤害 × 系数
const CHILEI_RING_WINDUP := 0.4          ## 雷环起手前摇（站定提亮，读得出「要放环」）
const CHILEI_RING_CURVE_ANG := 0.45      ## 雷环弧线角速度（rad/s，正顺时针，形成旋臂压迫）
const MUT_CHILEI_RING_COUNT := 12        ## 变异雷环弹数

## 赤雷兽·三连冲（变异升格：长扑不再单发，冲完接短预警再冲）
const MUT_CHILEI_CHAIN_CHARGES := 4      ## 变异后一轮长扑的连续冲刺段数
const MUT_CHILEI_CHAIN_GAP := 0.35       ## 链冲段间短预警间隔（秒）
const MUT_CHILEI_CHAIN_WINDUP_MULT := 0.6 ## 后续冲刺的预警时长倍率（首段仍用场景原值）

## 剑煞邪修·雷剑域（第二招式：在玩家脚下铺持续伤害领域，逼迫离开原位）
const JIANSHA_FIELD_INTERVAL := 7.0      ## 雷剑域周期（秒）
const JIANSHA_FIELD_RADIUS := 120.0      ## 领域半径：预警圈 = 判定圈（同源）
const JIANSHA_FIELD_WINDUP := 0.8        ## 落域预警时长
const JIANSHA_FIELD_DMG_MULT := 0.8      ## 每跳伤害 = 接触伤害 × 系数（受击无敌帧节流）
const JIANSHA_FIELD_DURATION := 3.5      ## 领域持续时长（秒）
const MUT_JIANSHA_FIELD_RADIUS_MULT := 1.25 ## 变异领域半径扩张倍率

## 剑煞邪修·瞬身回斩（变异专属：闪现到玩家侧翼后立刻扇形剑气反打）
const MUT_JIANSHA_BLINK_INTERVAL := 6.0  ## 瞬身周期（秒）
const MUT_JIANSHA_BLINK_DIST := 230.0    ## 瞬身落点距玩家距离
const MUT_JIANSHA_BLINK_BOLTS := 2       ## 回斩剑气数量
const MUT_JIANSHA_BLINK_BOLT_ARC := 0.18 ## 回斩剑气张角（弧度，单侧）

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

## 单批刷怪规模（2026-10-15 分批清剿制）：
## 前期（W1~6）4~5 只，中期（W7~12）5~6 只，后期（W13~18）6~7 只，关底（W19+）7~8 只，深层波次最高 8~9 只。
## roll 必须由调用方给（如 GameManager.rng.randf()）
static func spawn_batch(wave: int, roll: float) -> int:
	var w := float(maxi(wave, 1))
	var base := 4 + int((w - 1.0) / 6.0)
	base = mini(base, 8)
	return base + (1 if roll < SPAWN_BATCH_BONUS_CHANCE else 0)

static func enemy_hp_mult(wave: int) -> float:
	var w := maxi(wave, 1)
	if w <= DEEP_WAVE_THRESHOLD:
		return pow(ENEMY_HP_GROWTH, float(w - 1))
	## 深层从 W20 值续算，复利提档至 DEEP_HP_GROWTH（分段处连续、单调）
	return pow(ENEMY_HP_GROWTH, float(DEEP_WAVE_THRESHOLD - 1)) * pow(DEEP_HP_GROWTH, float(w - DEEP_WAVE_THRESHOLD))

## 敌人伤害的唯一倍率出口：整体基线 × 每回合复利。
## 调用方（WaveSpawner 刷怪/Boss 注入、EnemyBase 产卵·分裂·召唤小怪）只乘这一条，
## 敌弹伤害按 contact_damage/BOLT_DMG_BASE_REF 反推、Boss 环弹与震地按系数派生，全链路同源。
## 2026-10-13 深层分段：20 波内走 ENEMY_DMG_GROWTH 旧梯子不动；>20 波从
## W20 值续按 DEEP_DMG_GROWTH 复利（分段处连续），治「深层挨打不痛」。
static func enemy_dmg_mult(wave: int) -> float:
	var w := maxi(wave, 1)
	var base := ENEMY_DMG_BASE_MULT * pow(ENEMY_DMG_GROWTH, float(mini(w, DEEP_WAVE_THRESHOLD) - 1))
	if w <= DEEP_WAVE_THRESHOLD:
		return base
	return base * pow(DEEP_DMG_GROWTH, float(w - DEEP_WAVE_THRESHOLD))

## 深层（>20 波）同屏密度倍率：≤20 波恒 1.0（20 波内零影响），深层每波 +8%、封顶 ×2.2。
## 纯波次函数，不读 autoload、不看模式开关；函数名 endless_swarm_mult 保留为历史口径。
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
# —— 死亡演出分级（2026-10-15）：小怪保持「膨胀 0.045s → 塌缩 0.14s」快节奏不变（高频事件不宜加重）；
# 精英在膨胀后多一段踉跄倾倒再塌缩，Boss 倾倒后尸体滞留慢渐隐（不缩零）。
const ELITE_DEATH_STAGGER_DUR := 0.12   ## 精英踉跄段时长（秒）：膨胀后慢半拍，倒地有重量感
const ELITE_DEATH_TOPPLE_RAD := 0.21    ## 精英倾倒角（rad ≈ 12°）
const ELITE_DEATH_COLLAPSE_DUR := 0.18  ## 精英塌缩段时长（秒，比小怪 0.14 略慢）
const BOSS_DEATH_TOPPLE_RAD := 0.28     ## Boss 倾倒角（rad ≈ 16°）
const BOSS_DEATH_LINGER_DUR := 0.55     ## Boss 尸体滞留时长（秒）：倒地后停一停再散
const BOSS_DEATH_FADE_DUR := 0.45       ## Boss 滞留后的渐隐时长（秒，只淡出不塌缩）

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
const BOSS_WAVE_MAX: int = 20            ## 常量缓存 BOSS_WAVES.max()，避免每帧重复全表求最大值
const BOSS_CYCLE_IDS := ["chiyan", "xiuluo", "qianji", "wangu", "jianpo", "xinmo"]
const BOSS_HP_BASE := 6200.0             ## Boss 基础生命（2026-10-15 反割草对冲：神识分流 0.12→0.15 收紧后微降 6500→6200，
                                         ## Boss TTK 保持中性 W10≈66s / W20≈46s，割草收敛全部由小怪侧与分流侧承担；
                                         ## 成型 ~46s、极端 6 剑 ~13s）
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

## 六大魔君新招式平衡常量（供 BossEnemy.gd 读取）
const BOSS_CHAIN_CHARGE_COUNT := 3          ## 修罗/狂战多段连冲次数（一阶段 3 连，二阶段 +2）
const BOSS_CHAIN_CHARGE_COUNT_P2 := 5       ## 二阶段连冲次数
const BOSS_CHAIN_CHARGE_GAP := 0.22         ## 连冲段间短蓄力时长（秒）
const BOSS_TURRET_TELEPORT_EVERY := 3       ## 静止炮台 Boss 每释放 N 招瞬移换桩一次
const BOSS_TURRET_TELEPORT_RADIUS := 210.0  ## 炮台换桩距场地中心的环半径
const BOSS_HAZARD_FIELD_COUNT := 3          ## 场地封锁招式单次铺设雷毒禁区数（二阶段 +2）
const BOSS_HAZARD_FIELD_COUNT_P2 := 5
const BOSS_HAZARD_FIELD_RADIUS := 105.0     ## 禁区半径（视觉与判定同源）
const BOSS_HAZARD_FIELD_DURATION := 4.0     ## 禁区持续时长（秒）
const BOSS_HAZARD_FIELD_WINDUP := 0.75      ## 禁区预警时长（秒）
const BOSS_HAZARD_FIELD_DMG_MULT := 0.65    ## 禁区每跳伤害系数
const BOSS_BLINK_SLASH_DIST := 115.0        ## 瞬步贴脸斩闪现至玩家身侧距离
const BOSS_BLINK_SLASH_BOLTS := 7           ## 瞬步回斩扇形飞剑数（二阶段 9）
const BOSS_BLINK_SLASH_BOLTS_P2 := 9
const BOSS_BLINK_SLASH_SPREAD := 0.20       ## 瞬步回斩扇形夹角（rad）
const BOSS_BLINK_SLASH_SPEED := 320.0       ## 瞬步回斩飞剑速度
const BOSS_BLINK_SLASH_DMG_MULT := 0.65     ## 瞬步回斩伤害系数

# ---------------- 噩梦难度专属常量与迷雾视野 ----------------
const NIGHTMARE_DUAL_BOSS_HP_MULT := 0.78  ## 噩梦双 Boss 车轮战单尊生命折算（合计 1.56 倍血量，爽快不刮痧）
const NIGHTMARE_FOG_CLEAR_RADIUS := 200.0  ## 噩梦迷雾清晰内圈半径（设计单位，真正缩小视野范围）
const NIGHTMARE_FOG_FEATHER_RADIUS := 285.0 ## 噩梦迷雾边缘羽化外沿半径（超出即进入浓黑浓雾）
const NIGHTMARE_FOG_MAX_ALPHA := 1.0       ## 迷雾外圈完全遮蔽（100% 浓雾，外部敌人与地形全被遮蔽）
const ELITE_MUTATION_HP_PCT_BASE := 0.60   ## 普通精英变异血线（<=60%）
const ELITE_MUTATION_HP_PCT_NIGHTMARE := 0.70 ## 噩梦精英变异提前至 <=70%
const BOSS_PHASE2_HP_PCT_BASE := 0.50      ## 普通 Boss 二阶段血线（<=50%）
const BOSS_PHASE2_HP_PCT_NIGHTMARE := 0.60 ## 噩梦 Boss 二阶段狂暴提前至 <=60%

## 固定 Boss 回合：10/20 波，深层（>20 波）每 5 波再逢魔君
## （2026-10-13：用户口径深层 Boss 战要保留且加密，10 → 5 波一场：25/30/35…）
static func is_boss_wave(n: int) -> bool:
	return n in BOSS_WAVES or (n > BOSS_WAVE_MAX and n % 5 == 0)

## 依波次确定专属 Boss 标识（10/20/25/30/35/40 专属，深层 5 波一轮循环）
static func boss_id_for_wave(wave: int) -> String:
	if wave <= 10:
		return "chiyan"
	if wave <= 20:
		return "xiuluo"
	if wave <= 25:
		return "qianji"
	if wave <= 30:
		return "wangu"
	if wave <= 35:
		return "jianpo"
	if wave <= 40:
		return "xinmo"
	var idx := maxi(0, int(float(wave - 45) / 5.0)) % BOSS_CYCLE_IDS.size()
	return String(BOSS_CYCLE_IDS[idx])

## 精英回合：5/15 波；深层（>20 波）非 Boss 回合每关必逢精英（Boss 回合让位）
## 2026-10-28 无限闯关改造：原「无尽模式」开关已被取消（所有局都可超过 20 波），
## 语义固定为原无尽口径：n > BOSS_WAVE_MAX 且不是 Boss 波 ⇒ 精英波。
static func is_elite_wave(n: int, _endless: bool = false) -> bool:
	return n in ELITE_WAVES or (n > BOSS_WAVE_MAX and not is_boss_wave(n))

## 精英生成数量（纯函数）：依据波次与危险度（0~1 档，D0 普通 / D1 噩梦）确定精英怪刷新数量。
## - 主线（≤20 波）：第 5 波恒 1 只；第 15 波在 D1 噩梦升级为 2 只
## - 深层（>20 波）：
##   D0: 21~30 波 1 只，31+ 波 2 只
##   D1: 21~35 波 2 只，36+ 波 3 只
## 签名兼任 (n, danger) 与历史 (n, _endless, danger) 两种传参口径
static func elite_spawn_count_for_wave(n: int, arg2: Variant = 0, arg3: int = 0) -> int:
	if not is_elite_wave(n):
		return 0
	var danger: int = 0
	if typeof(arg2) == TYPE_BOOL:
		danger = arg3
	elif typeof(arg2) == TYPE_INT:
		danger = arg2
	var d := clampi(danger, 0, DANGER_MAX)
	if n <= BOSS_WAVE_MAX:
		if n == 15 and d >= 1:
			return 2
		return 1
	if d == 0:
		return 2 if n >= 31 else 1
	else:
		return 3 if n >= 36 else 2

## Boss 刷新数量（纯函数）：第 20/40/60 波在噩梦难度下打双 Boss 接力车轮战
static func boss_spawn_count_for_wave(wave: int, danger: int = 0) -> int:
	if not is_boss_wave(wave):
		return 0
	if danger >= 1 and wave >= 20 and wave % 20 == 0:
		return 2
	return 1

## 双 Boss 回合血量折算倍率（纯函数，单尊 0.78x，防长线刮痧）
static func boss_dual_hp_mult(wave: int, danger: int = 0) -> float:
	if boss_spawn_count_for_wave(wave, danger) > 1:
		return NIGHTMARE_DUAL_BOSS_HP_MULT
	return 1.0

## 依波次确定第二尊接力魔君 ID（与首尊互补不重样）
static func secondary_boss_id_for_wave(wave: int) -> String:
	if wave == 20:
		return "jianpo"   ## W20 首尊修罗（近战狂战），次尊剑魄（刺客回斩）
	elif wave == 40:
		return "xiuluo"   ## W40 首尊心魔（极煞统领），次尊修罗（近战冲阵）
	elif wave == 60:
		return "qianji"   ## W60 首尊轮转，次尊千机（机关炮台阵）
	var first_id := boss_id_for_wave(wave)
	var idx := BOSS_CYCLE_IDS.find(first_id)
	if idx >= 0:
		var sec_idx := (idx + 3) % BOSS_CYCLE_IDS.size()
		return String(BOSS_CYCLE_IDS[sec_idx])
	return "chiyan"

## 精英变异血线（纯函数）：普通 60%，噩梦提前至 70%
static func elite_mutation_hp_pct(danger: int = 0) -> float:
	return ELITE_MUTATION_HP_PCT_NIGHTMARE if danger >= 1 else ELITE_MUTATION_HP_PCT_BASE

## Boss 二阶段狂暴血线（纯函数）：普通 50%，噩梦提前至 60%
static func boss_phase2_hp_pct(danger: int = 0) -> float:
	return BOSS_PHASE2_HP_PCT_NIGHTMARE if danger >= 1 else BOSS_PHASE2_HP_PCT_BASE

## 危险度对敌方攻击 CD 的缩短倍率（纯函数）：噩梦加快 10%
static func danger_attack_cd_mult(danger: int = 0) -> float:
	return 0.90 if danger >= 1 else 1.0

## 危险度对敌方弹速的倍率（纯函数）：噩梦提速 8%
static func danger_bolt_speed_mult(danger: int = 0) -> float:
	return 1.08 if danger >= 1 else 1.0

## 敌方弹丸飞行速度倍率（纯函数）：
## 前期基础 1.0，1~20 波平缓成长至 1.22x，>20 波深层加速成长至封顶 1.65x
static func enemy_bolt_speed_mult(wave: int) -> float:
	var w := maxi(wave, 1)
	if w <= DEEP_WAVE_THRESHOLD:
		return 1.0 + float(w - 1) * 0.0115
	var base := 1.0 + float(DEEP_WAVE_THRESHOLD - 1) * 0.0115
	return minf(base + float(w - DEEP_WAVE_THRESHOLD) * 0.025, 1.65)

## 敌方技能/攻击周期缩短倍率（纯函数，周期越短出手越快）：
## 前期基础 1.0，1~20 波收紧至 0.85x，>20 波加速收紧至下限 0.55x
static func enemy_attack_cd_mult(wave: int) -> float:
	var w := maxi(wave, 1)
	if w <= DEEP_WAVE_THRESHOLD:
		return maxf(0.85, 1.0 - float(w - 1) * 0.0079)
	var base := 1.0 - float(DEEP_WAVE_THRESHOLD - 1) * 0.0079
	return maxf(0.55, base - float(w - DEEP_WAVE_THRESHOLD) * 0.018)

## 远程怪齐射增发数量（纯函数）：
## W1~15 为 0（单发火球）；W16~24 额外 +1 发（扇射雏形）；W25+ 额外 +2 发
static func enemy_bonus_bolts(wave: int) -> int:
	var w := maxi(wave, 1)
	if w >= 25:
		return 2
	elif w >= 16:
		return 1
	return 0

# ---------------- 五波一阶天象与场景氛围主题（纯函数） ----------------
## 阶段天象档位：W1-5 -> 0, W6-10 -> 1, W11-15 -> 2, W16-20 -> 3, W21-25 -> 4, W26+ -> 5+
static func stage_mood_tier(wave: int) -> int:
	return int(float(maxi(wave, 1) - 1) / 5.0)

## 场景天象主题字典（纯函数，所有颜色与速度参数由此产出）：
## 供 Main 与 ArenaVisualLayer 对齐地砖、调色、结界边缘流光与灵枢符印
static func stage_theme_for_wave(wave: int, danger: int = 0) -> Dictionary:
	var w := maxi(wave, 1)
	var tier := stage_mood_tier(w)
	var is_boss := is_boss_wave(w)
	var out: Dictionary = {}
	
	match tier:
		0:
			# 第 1~5 波：青冥灵台（清冷玄玉，青玉暖灰 + 幽冷玉蓝结界）
			out = {
				"name": "青冥灵台",
				"tier": tier,
				"is_boss": is_boss,
				"ground_base": Color(0.208, 0.243, 0.263, 1.0),
				"ground_gap": Color(0.10, 0.13, 0.15, 1.0),
				"tone_modulate": Color(0.85, 0.88, 0.96, 1.0),
				"barrier_base": Color(0.12, 0.36, 0.58, 0.65),
				"barrier_flow": Color(0.55, 1.35, 2.00, 0.95),
				"flow_speed": 0.035,
				"pulse_speed": 0.9,
				"taiji_cyan": Color(0.25, 0.70, 0.90),
				"taiji_gold": Color(0.85, 0.70, 0.25),
				"taiji_rot_speed": 0.07,
				"talisman_flow_period": 8.0,
			}
		1:
			# 第 6~10 波：寒魄雷劫（幽蓝寒潭 + 幽紫电弧结界）
			out = {
				"name": "寒魄雷劫",
				"tier": tier,
				"is_boss": is_boss,
				"ground_base": Color(0.165, 0.205, 0.265, 1.0),
				"ground_gap": Color(0.08, 0.11, 0.16, 1.0),
				"tone_modulate": Color(0.80, 0.85, 1.02, 1.0),
				"barrier_base": Color(0.20, 0.26, 0.60, 0.72),
				"barrier_flow": Color(0.85, 1.25, 2.30, 1.00),
				"flow_speed": 0.045,
				"pulse_speed": 1.15,
				"taiji_cyan": Color(0.35, 0.75, 1.00),
				"taiji_gold": Color(0.70, 0.55, 0.95),
				"taiji_rot_speed": 0.09,
				"talisman_flow_period": 7.0,
			}
		2:
			# 第 11~15 波：赤煞劫火（炽金焦岩 + 赤铜流火结界）
			out = {
				"name": "赤煞劫火",
				"tier": tier,
				"is_boss": is_boss,
				"ground_base": Color(0.235, 0.195, 0.185, 1.0),
				"ground_gap": Color(0.14, 0.09, 0.09, 1.0),
				"tone_modulate": Color(0.95, 0.84, 0.80, 1.0),
				"barrier_base": Color(0.55, 0.25, 0.14, 0.75),
				"barrier_flow": Color(2.10, 1.15, 0.45, 1.00),
				"flow_speed": 0.055,
				"pulse_speed": 1.35,
				"taiji_cyan": Color(0.95, 0.55, 0.25),
				"taiji_gold": Color(1.00, 0.80, 0.30),
				"taiji_rot_speed": 0.11,
				"talisman_flow_period": 6.0,
			}
		3:
			# 第 16~20 波：九幽血劫（玄黑血褐 + 朱砂血煞光幕）
			out = {
				"name": "九幽血劫",
				"tier": tier,
				"is_boss": is_boss,
				"ground_base": Color(0.185, 0.135, 0.165, 1.0),
				"ground_gap": Color(0.11, 0.06, 0.09, 1.0),
				"tone_modulate": Color(0.92, 0.78, 0.85, 1.0),
				"barrier_base": Color(0.60, 0.12, 0.22, 0.82),
				"barrier_flow": Color(2.20, 0.55, 0.65, 1.05),
				"flow_speed": 0.065,
				"pulse_speed": 1.60,
				"taiji_cyan": Color(0.95, 0.25, 0.35),
				"taiji_gold": Color(0.85, 0.65, 0.25),
				"taiji_rot_speed": 0.13,
				"talisman_flow_period": 5.2,
			}
		4:
			# 第 21~25 波：虚空紫极（极夜深紫 + 幽紫魔焰天幕）
			out = {
				"name": "虚空紫极",
				"tier": tier,
				"is_boss": is_boss,
				"ground_base": Color(0.145, 0.125, 0.215, 1.0),
				"ground_gap": Color(0.08, 0.06, 0.14, 1.0),
				"tone_modulate": Color(0.88, 0.76, 1.00, 1.0),
				"barrier_base": Color(0.48, 0.14, 0.68, 0.85),
				"barrier_flow": Color(1.85, 0.75, 2.30, 1.10),
				"flow_speed": 0.075,
				"pulse_speed": 1.85,
				"taiji_cyan": Color(0.75, 0.35, 0.95),
				"taiji_gold": Color(0.95, 0.70, 0.35),
				"taiji_rot_speed": 0.16,
				"talisman_flow_period": 4.5,
			}
		_:
			# 第 26 波+：混沌冥狱（高频流转金煞紫极，每 5 波高压轮换）
			var sub_cycle := (tier - 5) % 3
			var base_col := Color(0.13, 0.11, 0.18, 1.0)
			var gap_col := Color(0.07, 0.05, 0.10, 1.0)
			var bar_base := Color(0.55, 0.18, 0.35, 0.88)
			var bar_flow := Color(2.30, 0.90, 1.40, 1.15)
			if sub_cycle == 1:
				base_col = Color(0.16, 0.12, 0.12, 1.0)
				bar_base = Color(0.65, 0.15, 0.15, 0.88)
				bar_flow = Color(2.40, 1.20, 0.40, 1.20)
			elif sub_cycle == 2:
				base_col = Color(0.11, 0.15, 0.18, 1.0)
				bar_base = Color(0.15, 0.45, 0.55, 0.88)
				bar_flow = Color(0.80, 2.00, 2.40, 1.15)
			out = {
				"name": "混沌冥狱",
				"tier": tier,
				"is_boss": is_boss,
				"ground_base": base_col,
				"ground_gap": gap_col,
				"tone_modulate": Color(0.92, 0.80, 0.92, 1.0),
				"barrier_base": bar_base,
				"barrier_flow": bar_flow,
				"flow_speed": 0.085,
				"pulse_speed": 2.1,
				"taiji_cyan": Color(0.95, 0.45, 0.65),
				"taiji_gold": Color(1.00, 0.85, 0.45),
				"taiji_rot_speed": 0.20,
				"talisman_flow_period": 3.8,
			}

	# 噩梦难度专属血煞色调修正：石板更暗、石缝幽红、天象压暗带赤紫冷调
	if danger >= 1:
		var gb: Color = out["ground_base"]
		var gg: Color = out["ground_gap"]
		var tm: Color = out["tone_modulate"]
		var bb: Color = out["barrier_base"]
		var bf: Color = out["barrier_flow"]
		out["ground_base"] = gb.darkened(0.16).lerp(Color(0.20, 0.10, 0.13, 1.0), 0.35)
		out["ground_gap"] = gg.lerp(Color(0.24, 0.05, 0.07, 1.0), 0.55)
		out["tone_modulate"] = tm.lerp(Color(0.86, 0.74, 0.86, 1.0), 0.50)
		out["barrier_base"] = bb.lerp(Color(0.65, 0.12, 0.25, 0.86), 0.45)
		out["barrier_flow"] = bf.lerp(Color(2.15, 0.65, 0.85, 1.15), 0.40)
	return out

## Boss 生命：与普通敌人同一条 hp 曲线，靠基础值拉开厚度差距
static func boss_hp(wave: int) -> float:
	return BOSS_HP_BASE * enemy_hp_mult(wave)

static func boss_contact_damage(wave: int) -> float:
	return ceilf(BOSS_CONTACT_BASE * enemy_dmg_mult(wave))

# ---------------- 危险度（全部开放的难度梯度，D0 ~ D1 共 2 档） ----------------
## 2026-10-28 梯度重塑：普通(D0)与噩梦(D1)两档。
## 普通(D0)：基线生命 ×1.16、伤害 ×1.05、敌潮 ×1.16
## 噩梦(D1)（均衡档，配合迷雾与双 Boss 机制）：
## 生命 ×1.65（+42%）、伤害 ×1.40（+33%）、敌潮 ×1.45（+25%）
## 步进 PER 分别为：HP 0.49 / DMG 0.35 / COUNT 0.29

const DANGER_MAX := 1
const DANGER_HP_BASE := 1.16    ## 普通档(D0)基线生命
const DANGER_HP_PER := 0.49     ## 每档敌人生命步进（D1 = 1.16 + 0.49 = ×1.65，均衡档）
const DANGER_DMG_BASE := 1.05   ## 普通档(D0)基线伤害
const DANGER_DMG_PER := 0.35    ## 每档敌人伤害步进（D1 = 1.05 + 0.35 = ×1.40，均衡档）
const DANGER_COUNT_BASE := 1.16 ## 普通档(D0)基线敌潮规模
const DANGER_COUNT_PER := 0.29  ## 每档敌潮规模步进（D1 = 1.16 + 0.29 = ×1.45，均衡档）

static func danger_hp_mult(danger: int) -> float:
	return DANGER_HP_BASE + float(clampi(danger, 0, DANGER_MAX)) * DANGER_HP_PER

static func danger_dmg_mult(danger: int) -> float:
	return DANGER_DMG_BASE + float(clampi(danger, 0, DANGER_MAX)) * DANGER_DMG_PER

static func danger_count_mult(danger: int) -> float:
	return DANGER_COUNT_BASE + float(clampi(danger, 0, DANGER_MAX)) * DANGER_COUNT_PER
