class_name BalanceCombat
extends RefCounted

## 战斗结算数值：护甲减伤、镜头创伤（震屏）、受击硬直/击退/斩杀反馈、妖狼长扑几何、
## 五行异常状态（灼烧/剧毒）、震退方向、集火韧性。全部 static 纯函数。
## 与 GameBalance 同规约：不读 autoload、不碰节点、不调全局 randf()。

# ---------------- 敌人招式出场错相 / 走位参数 ----------------

const BOLT_FIRST_DELAY := 1.2 ## 远程首次出手缓冲（秒）：HoverIntentCheck 依赖它 ≥0.6s
const BOLT_FIRST_JITTER := 0.8 ## 首次出手额外错相上限（秒）
const CHARGE_OPENING_DELAY := 1.0 ## 冲锋首次冷却缓冲（秒）：WolfAiCheck 依赖它 ≥0.5s
const COOLDOWN_PHASE_JITTER := 0.35 ## 周期技能首次冷却错相比例（0~35%，只延后）
const ELITE_COOLDOWN_PHASE_JITTER := 0.3 ## 精英招式首次冷却错相比例
const KITE_STRAFE_SPEED := 0.5 ## 远程保持距离带的切向绕行速度倍率（原写死 0.5）

# ---------------- 护甲 / 受伤 ----------------

const ARMOR_COEF := 0.08      ## 减伤 = 1 - 1/(1+护甲×0.08)
const DAMAGE_FLOOR := 1.0     ## 实伤保底，防止高护甲把伤害抹成 0

## 面板用的减伤比例（0~1）。注意它不含 DAMAGE_FLOOR，高护甲打小伤害时面板会略优于实际
static func armor_reduction(armor: float) -> float:
	return 1.0 - (1.0 / (1.0 + maxf(0.0, armor) * ARMOR_COEF))

## 实际扣血。Player 与 HUD 从此共用同一条公式，不再各写一套
static func incoming_damage(raw: float, armor: float) -> float:
	return maxf(DAMAGE_FLOOR, raw / (1.0 + maxf(0.0, armor) * ARMOR_COEF))

# ---------------- 玩家生命档位（读数取色的唯一一把尺）----------------
## 「什么时候算危险」只许有一处定义：HUD 那行血字的颜色、金币阁顶栏生命徽记的底色、
## 详情卡里的提示，全部走 hp_is_low。以前 0.28 只写在 GameHUD 里，
## 商店要跟着变色就得手抄一遍 —— 抄的那一份永远不会跟着改。
const HP_LOW_RATIO := 0.28      ## 剩余生命占上限低于此档 = 危险（朱砂）

## 剩余比例（0~1）；上限为 0（玩家还没生成 / 单测空载）按满血算，不许出 NaN 与除零
static func hp_ratio(cur: float, max_v: float) -> float:
	return cur / max_v if max_v > 0.0 else 1.0

static func hp_is_low(cur: float, max_v: float) -> bool:
	return max_v > 0.0 and hp_ratio(cur, max_v) < HP_LOW_RATIO

static func hp_is_full(cur: float, max_v: float) -> bool:
	return max_v > 0.0 and cur >= max_v - 0.5

# ---------------- 软顶递减（对标土豆兄弟攻速递减收益：过膝点后每份投入只兑现一半） ----------------
## 软顶不在 apply 时夹（保住 StatSystem apply/revert 对称性，卖道具能精确回退），
## 统一在读出口折算：伤害结算走 GameManager.get_weapon_damage_mult()，
## 面板与悟道卡面预读走 StatBreakdown（两边共用这一份，卡面承诺与到账不分家）。

const WDM_SOFT_KNEE := 2.0    ## 武器伤害乘区膝点：raw ≤ 2.0 全额兑现
const WDM_SOFT_RATIO := 0.5   ## 超过膝点的部分按 50% 折算
const REGEN_SOFT_KNEE := 8.0  ## 生命回复膝点（/秒）
const REGEN_SOFT_RATIO := 0.5

## 通用软顶：膝点内原值，超出部分打折
static func soft_diminish(v: float, knee: float, ratio: float) -> float:
	if v <= knee:
		return v
	return knee + (v - knee) * ratio

## 武器伤害乘区有效值（raw 是 GameManager.weapon_damage_mult 的累加原值）
static func effective_weapon_damage_mult(raw: float) -> float:
	return soft_diminish(raw, WDM_SOFT_KNEE, WDM_SOFT_RATIO)

## 生命回复有效值（入参是加点层+羁绊层合计）
static func effective_hp_regen(raw: float) -> float:
	return soft_diminish(raw, REGEN_SOFT_KNEE, REGEN_SOFT_RATIO)

# ---------------- 暴击 / 闪避：带上限的两条读数 ----------------
## 这两条从 GameManager 的方法里抽出来（2026-10-12），因为悟道卡面要在玩家按下
## 「确认选择」之前先读出「加后是多少」：那份预读走的是同一批算式，抄第二份就会漂
## （调一次上限，卡面承诺与实际结算分家）。消费方：GameManager 的两个 getter、
## StatShadow（属性影子，见 ui/stats/StatShadow.gd）。

## 有效暴击率：加点/角色基础 + 锐金羁绊 + 幻影迷踪铃按有效闪避折算，夹软上限。
## dodge_convert 是「每 10% 有效闪避折一份暴击」的系数合计（ItemData 的 crit_per_dodge）。
static func crit_rate(base: float, synergy: float, dodge_convert: float,
		dodge_eff: float, cap: float) -> float:
	var rate := base + synergy
	if dodge_convert > 0.0:
		rate += dodge_convert * (dodge_eff / 0.1)
	return minf(rate, cap)

## 有效闪避：升级/道具累加 + 技能短时加成，夹在硬上限（含角色抬升的那一截）内。
static func effective_dodge(dodge: float, buff_dodge: float, cap: float, cap_bonus: float) -> float:
	return minf(dodge + buff_dodge, cap + cap_bonus)

# ---------------- 打击感：镜头创伤（震屏） ----------------
## 震屏的唯一数学来源。口径（2026-10-08 用户口径：「一直摇不好，这效果要留给特殊场景」）：
##   1) 普通命中 / 普通小怪死亡 **一律不发创伤**，打击感交给挤压形变 + 受击火花 + 跳字 + 顿帧；
##   2) 创伤只发给「值得看的节点」：玩家受创、精英与首领的登场/震地/伏诛、界碑聚灵阵、落雷命中；
##   3) 即便将来有人拿高频事件乱调 add_trauma，「每秒预算 ÷ 每秒衰减」把最坏稳态创伤钉死在
##      0.25（对应位移 ±0.9px）：镜头最多只剩一点轻颤，不会再整局猛摇。
##      预算给的是上限而不是"刷着刷着就归零"，所以口径要盯稳态值，别只看预算比衰减小。
##   4) 2026-10-18 用户口径：「雷法全配感觉屏幕一直在震动，不要特别高频」。根因是 AoE 落雷
##      一次劈 5~6 个敌人、每个敌人各自独立掷暴击，同帧叠出十几记 6.5px 方向冲击 + 十几笔创伤；
##      单发落雷又无条件发 0.16 创伤 + 2.8px 冲击，六把雷法叠加就成持续抖屏。对策见
##      CRIT_CAMERA_MIN_INTERVAL（暴击镜头反馈全局限流）与 ThunderBurst 的「按战果才震」。

const TRAUMA_DECAY := 3.0          ## 每秒衰减量：震停耗时 = 创伤 / 本值（2.2→3.0：创伤回零更快，不让多笔叠着拖长）
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
const KNOCKBACK_IMPULSE_SCALE := 1.10    ## 击退初速度折算系数：轻武器短击退(~9-11px)，重武器强击退(~30-38px)；整体克制，近战不追怪（2026-10-20 由 1.45 下调 ~25%）
const KNOCKBACK_DECAY_STUN := 12.0       ## 硬直期间击退衰减率：0.11s内快速到位并干脆刹停，杜绝打冰球与持续滑行
const KNOCKBACK_DECAY_FREE := 24.0       ## 硬直结束后残余击退极速清零率
const KNOCKBACK_MAX_SPEED_NORMAL := 620.0 ## 普通受击初速上限（px/s）：单次击退位移严格封顶（~50px以内）
const KNOCKBACK_MAX_SPEED_CRIT := 780.0   ## 暴击受击初速上限（px/s）：暴击击退封顶（~65px以内）
const KNOCKBACK_HEAVY_SPEED := 240.0     ## 重击判定阈值（px/s）：触发重击音效与地面摩擦扬尘
const KNOCKBACK_HEAVY_DECAY_MULT := 1.0  ## 取消重击衰减打折（杜绝把敌人甩出半屏）

## 定向受击挤压（Squash & Stretch）：按击退轴选形变，玩家/敌人同一把尺子（2026-10-15 从
## EnemyBase 上移为共用纯函数）。无击退向量时给默认水平压扁；有击退时沿冲击轴压扁、垂直轴拉长。
static func hit_squash_target(knockback: Vector2, is_crit: bool) -> Vector2:
	if knockback.length_squared() < 10.0:
		return Vector2(1.36, 0.70) if is_crit else Vector2(1.24, 0.80)
	var k_norm := knockback.normalized()
	if absf(k_norm.x) >= absf(k_norm.y):
		return Vector2(0.68, 1.38) if is_crit else Vector2(0.76, 1.26)   # 水平冲击：横压竖拉
	else:
		return Vector2(1.38, 0.68) if is_crit else Vector2(1.26, 0.76)   # 垂直冲击：竖压横拉
# ---------------- 打击音：伤害驱动的响度/音高（2026-10-23，参考死亡细胞）----------------
## 死亡细胞的手感来源之一：同一把武器，小伤害是「啪」，大伤害是「咚」——响度与音高都跟着
## 这一刀的份量走。这里只做「倍率」，调用方仍叠自己的随机抖音高与暴击基准音高，两者相乘。
## 口径：以「本次伤害占目标最大生命的比例」为尺（不看绝对伤害——W20 的 300 点和 W1 的 30 点
## 占血比可能一样，听感就该一样重）。比例超过参考值后线性加码，封顶各常数。
const HIT_SFX_DAMAGE_REF := 0.18       ## 参考伤害占比：单次打掉目标 18% 生命算「一记狠的」
const HIT_SFX_VOLUME_MAX_BONUS := 0.22 ## 大伤害最多额外 +22% 响度（线性到顶，避免盖住 BGM）
const HIT_SFX_PITCH_MAX_DROP := 0.12   ## 大伤害最多降 12% 音高（越重越沉）
const HIT_SFX_HEAVY_RATIO := 0.35      ## 单次打掉 35% 生命：追加 enemy_hit_heavy 重击层

## 伤害占比归一化到 0~1：参考值以下 = 0（普通命中保持原样），从参考值到重击线线性加码，
## 到 HIT_SFX_HEAVY_RATIO 满额（正好与「追加一层重击音」同一根线，听感与分层同步）。
## 上限为 0 时按 0 处理（防除零）。
static func hit_sfx_weight(damage: float, max_hp: float) -> float:
	if max_hp <= 0.0:
		return 0.0
	var ratio := damage / max_hp
	return clampf((ratio - HIT_SFX_DAMAGE_REF) / (HIT_SFX_HEAVY_RATIO - HIT_SFX_DAMAGE_REF), 0.0, 1.0)

## 命中音效的响度倍率（1.0 ~ 1.0+MAX_BONUS）
static func hit_sfx_volume(damage: float, max_hp: float) -> float:
	return 1.0 + HIT_SFX_VOLUME_MAX_BONUS * hit_sfx_weight(damage, max_hp)

## 命中音效的音高倍率（1.0 ~ 1.0-MAX_DROP，大伤害更低沉）
static func hit_sfx_pitch(damage: float, max_hp: float) -> float:
	return 1.0 - HIT_SFX_PITCH_MAX_DROP * hit_sfx_weight(damage, max_hp)

## 这一击是否重到需要追加重击音层（暴击走 crit 自己的完整主体，不叠本层）
static func hit_sfx_is_heavy(damage: float, max_hp: float) -> bool:
	return max_hp > 0.0 and damage / max_hp >= HIT_SFX_HEAVY_RATIO

const KILL_HITSTOP_DURATION := 0.03      ## 击杀微顿帧时长（秒）
const KILL_HITSTOP_SCALE := 0.45         ## 击杀微顿帧时间倍率（0.40 地板之上，保留轻于暴击的层次）
const KILL_HITSTOP_MIN_INTERVAL := 0.25  ## 击杀顿帧最小间隔（尸潮限流：≤4Hz，防连续顿帧把节奏切碎）
## 顿帧时间倍率安全地板：极端近 0 的停顿会让物理步与渲染交换链抢相位，真机 vsync 下
## 呈送黑帧（整屏含 UI 闪一下的元凶之一）。2026-10-20 由 0.15 抬到 0.40：玩家移动不再豁免
## 顿帧（改为与世界同步变慢），若地板仍近 0，玩家会每帧被拖到近静止再放开 ⇒ 反而「走一顿一顿」。
## 0.40 让世界只慢到 40%，保留可见顿挫层次而不卡步。
const HITSTOP_TIMESCALE_FLOOR := 0.40
## 顿帧低帧降频闸（2026-10-17 真机 UI 频闪治理）：实测 fps 低于阈值时，暴击/击杀/暴击击杀
## 三路顿帧的最小间隔统一乘降频系数——低端机 GPU bound（稳态 ~42fps）下三路各 0.10~0.18s
## 的限流叠加起来每 ~0.1s 就把时间轴压到地板一次，冻结-恢复循环在交换链上呈黑帧频闪
## （整屏含 UI 一起闪）。降频把占空比砍半；fps 回升后自动恢复原节奏。
const HITSTOP_LOWFPS_FLOOR := 45.0        ## 低帧判定阈值（fps，GameFeel 以 1s 粒度采样）
const HITSTOP_LOWFPS_INTERVAL_MULT := 2.0 ## 低帧时顿帧最小间隔倍率
const CRIT_TRAUMA_NORMAL := 0.20         ## 普通暴击追加创伤（从 0.12 上调：平方后产生可见轻颤，稳态仍严格受每秒预算保护）
const CRIT_TRAUMA_ELITE := 0.32          ## 精英暴击创伤（既有口径，提出来与普通暴击并列成表）

# —— 精英/Boss 专属受击火花（2026-10-20，2026-10-23 改全局节奏闸）——
## 小怪高频割草不发火花（历史教训：满屏乱闪）；精英/Boss 同屏恒 1 只、体型大，挨打没火花缺打击感，
## 故仅对 is_elite 的非暴击直击补一朵轻火花，锚在体表受击侧。暴击另有方向环，不重复发。
## 2026-10-23：由「每敌倒计时 0.08s」改为**全局时间戳闸**。根因：0.08s 短于束流 tick(0.15s)
## 拦不住，且倒计时在多实例下各自扣一遍；改成全局时间戳后全屏同一时刻至多一朵，
## 束流 tick / 多段命中 / 多武器齐射 / 多精英同帧都收敛成一朵。取值 = 火花寿命 0.22s。
const ELITE_HIT_SPARK_GAP_MS := 220      ## 精英/Boss 火花全局最小间隔（毫秒）：= HIT_SPARK 寿命，屏上至多一朵
const ELITE_HIT_SPARK_SCALE := 1.10      ## 精英火花缩放倍率
const BOSS_HIT_SPARK_SCALE := 1.35       ## Boss 火花缩放倍率（体型更大，略放大）
const ELITE_HIT_SPARK_EDGE_OFFSET := 20.0 ## 精英火花由中心向攻击来向偏移（px），落在体表而非几何中心
const BOSS_HIT_SPARK_EDGE_OFFSET := 32.0  ## Boss 火花体表偏移（px）
## 暴击镜头反馈全局限流（2026-10-18 雷法抖屏治理）：落雷/横扫一次命中 5~6 个敌人，
## 每个敌人各自掷暴击 → 同帧叠出十几记 6.5px 方向冲击 + 十几笔创伤，镜头整片狂晃。
## 暴击的「这一刀从哪来」交给方向环/跳字/顿帧，镜头反馈（kick+zoom+trauma）全局限流成一记。
## 0.25s ≈ 每秒最多 4 记；实测全雷法六把满星配装：移动帧占比 71%→40%、平均位移 2.77→1.2px。
const CRIT_CAMERA_MIN_INTERVAL := 0.25   ## 暴击镜头反馈（方向冲击+缩放+创伤）全局限流最小间隔（秒）
const CRIT_KILL_HITSTOP_DURATION := 0.055 ## 暴击击杀顿帧时长（秒）：比普通击杀微顿帧更「实」
const CRIT_KILL_HITSTOP_SCALE := 0.40    ## 暴击击杀顿帧时间倍率（扎实顿挫，落在安全地板 0.40 上）
const CRIT_KILL_HITSTOP_MIN_INTERVAL := 0.30 ## 暴击击杀顿帧最小间隔（秒，独立限流防锁死）
const ZHUMU_MINION_CAP := 30             ## 百目妖产卵的场面硬上限（2026-10-10 随整体减潮由 45 下调）

# —— 命中反馈全局限流（2026-10-11 频闪治理）——
## 远程穿透/弹射/多弹齐射下每秒命中可达几十次，逐刀全量反馈会糊成满屏频闪+持续抖屏。
## 普通档按最小间隔放行；精英/暴击作为「值得看」的节点直通（闸不消耗）。
const MICRO_KICK_MIN_INTERVAL := 0.14    ## 普通命中/普通击杀镜头微冲击全局限流最小间隔（秒，0.09→0.14 削高频抖动）
## Boss 挨大比例掉血的镜头回应（2026-10-14）：单次伤害 ≥ 最大生命该比例时发一笔轻创伤，
## 让「砍疼 Boss」有回响（Boss 平时只有自己的招式发反馈，被打几乎 silent）。
## 仍走每秒创伤预算闸 + 每 Boss 独立冷却，群攻刷伤时不会变成持续抖屏。
const BOSS_HEAVY_HIT_PCT := 0.06         ## 触发阈值：单次伤害占 Boss 最大生命比例
const BOSS_HEAVY_HIT_TRAUMA := 0.10      ## 触发创伤（轻档：平方后仅可见轻颤，远低于暴击档）
const BOSS_HEAVY_HIT_COOLDOWN := 0.5     ## 每 Boss 触发冷却（秒）

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

# ---------------- 近战扑咬（2026-10-23：纯接触怪从「撞上来」升级为「扑上来」） ----------------
## 背景：史莱姆/花妖/蜂群/血蛹这类纯接触怪只有被动滑碰伤害 —— 贴上来，「撞」出伤害，没有出招动作。
## 与长扑/火球/震地这些有前摇的招式放在一起，普通怪的活物感是断档的。扑咬补的就是这一档：
## 站蹲前摇（可读、可躲）→ 短促前扑 → 收势。
##
## 三条纪律与长扑同款：
##   ① 伤害零新增 —— 前扑的位移把身体送进既有接触带，伤害仍由 _resolve_contact_damage 结算；
##   ② 几何同源 —— 前扑真实位移 = lunge_reach(峰速, 扑击时长)，与判据量的位移同一把尺子；
##   ③ 前摇可打断 —— 站蹲段挨打就取消，不做「被钉着还扑出来」（同火球蓄力口径）。

const LUNGE_WINDUP := 0.34        ## 站蹲前摇（秒）：下蹲 + 本体提亮，玩家看到就知道要扑
const LUNGE_SPEED_MUL := 2.1      ## 前扑峰速 = 移速 × 它（默认档，敌种可覆写）
const LUNGE_DASH_TIME := 0.16     ## 前扑时长（秒）：短促一扑，不是长距离冲锋
const LUNGE_RECOVER := 0.22       ## 收势（秒）：扑完短暂停住，给玩家反打窗口
const LUNGE_COOLDOWN := 2.2       ## 冷却（秒）：扑空后隔这么久才再起手
const LUNGE_MIN_RANGE := 46.0     ## 下沿：太近不起手（贴脸时接触伤害已在生效，别叠动作）
const LUNGE_MAX_RANGE := 132.0    ## 上沿硬顶：再远连扑出去也够不着，老老实实走位
## 起手可达距离的接触余量（px）：前扑必须真的能把身子送进接触带，否则「有招式但永远咬不到」。
## 取「敌我碰撞半径之和」量级（小怪 18 + 玩家 14 ≈ 32），留 2px 容差。
const LUNGE_CONTACT_MARGIN := 34.0

## 前扑真实位移（px）：匀速段面积。收势段原地刹住不产生位移，故只有冲刺项。
## 与 charge_reach 同一个建模思路：先有闭式解，再让「画的」「冲的」「判的」都取它。
static func lunge_reach(peak_speed: float, dash_time: float) -> float:
	return maxf(peak_speed, 0.0) * maxf(dash_time, 0.0)

## 起手距离上限（px）：前扑能覆盖的距离 + 接触余量，且不超过 LUNGE_MAX_RANGE 硬顶。
## 这是「有招式却永远咬不到」的根治 —— 旧写法用固定 132px 上沿，
## 而史莱姆一扑只有 33.6px，132px 起手扑完还剩 98px，动作演了、伤害永远不结算。
static func lunge_engage_range(peak_speed: float, dash_time: float) -> float:
	return minf(lunge_reach(peak_speed, dash_time) + LUNGE_CONTACT_MARGIN, LUNGE_MAX_RANGE)

## 敌种扑咬参数（eid → 参数；空字典 = 该敌种不扑）。
## 只给「纯接触、无其他招式」的四种。排除口径：
##   有长扑的（雷兽/赤雷）、有震地落石的（铁甲魔傀）、有弹幕的（邪修/剑煞）、
##   有引信自爆的（丹爆）、有投毒的（毒妖）、有召唤/光环/治疗的（蛛母/鼓妖/灵医）、
##   有闪现的（影魅）、恒逃的（金蟾）。
## 血蛹的分裂是死亡触发、不影响活体行为，故仍给扑咬。
static func lunge_params(eid: String) -> Dictionary:
	match eid:
		"slime":
			return {"speed_mul": 2.0, "dash": 0.16, "recover": 0.24, "cooldown": 2.4}
		"flower":
			return {"speed_mul": 2.3, "dash": 0.14, "recover": 0.20, "cooldown": 2.0}
		"fengqun":
			return {"speed_mul": 1.8, "dash": 0.13, "recover": 0.18, "cooldown": 2.6}
		"xueyong":
			return {"speed_mul": 2.2, "dash": 0.17, "recover": 0.26, "cooldown": 2.8}
	return {}

# ---------------- 五行异常状态（灼烧 / 剧毒）叠层与结算 ----------------

const BURN_STACK_RATIO := 0.25         ## 多源灼烧叠层共鸣系数：已处于灼烧时，叠加新灼烧量的 25%
const POISON_STACK_RATIO := 0.50       ## 剧毒叠层累加系数
## 叠层共鸣帽（2026-10-24）：累积 DPS 不超过「本次施加量 × 帽倍率」，且**只挡增长不回落**——
## 弱源或弹射衰减跳的少量施加不许拉低已叠高的强源异常。原本两系都无上限线性成长
## （蛊毒符 ★1 打 30s boss 毒 DPS 滚到 ~84 vs 基准 5.6），长战斗必超模。
## 帽值口径：普通怪 3~6 秒死亡内基本叠不满（无感），boss 战有界——剧毒 6 次施加到顶（×3）、
## 灼烧 7 次到顶（×2.5），满层后蛊毒符毒伤 16.8/s ≈ 其直伤 16/s，DoT 定位保留、滚雪球封死。
## 官方尺子 sustained_single_dps 与 BalanceSimCheck 仍按「单次施加基准量」标定（有界低估 ≤ ×帽）。
const POISON_CAP_MULT := 3.0
const BURN_CAP_MULT := 2.5
const BURN_ELEM_TICK_COEF := 0.40      ## 每点元素伤害对每次灼烧跳字（0.5s）的额外伤害加成
const POISON_ELEM_TICK_COEF := 0.30    ## 每点元素伤害对每次剧毒跳字（0.5s）的额外伤害加成
const DOT_TICK_INTERVAL := 0.50        ## DoT 跳字结算周期（秒）

## 施加灼烧后的新 DPS：未灼烧时全额起算，已灼烧时在保留最高值基础上叠加 25% 共鸣伤害；
## 累积不越过「本次施加量 × BURN_CAP_MULT」，弱源不回落
static func stack_burn_dps(current_dps: float, incoming_dps: float) -> float:
	if current_dps <= 0.0:
		return maxf(0.0, incoming_dps)
	var grown := maxf(current_dps, incoming_dps) + maxf(0.0, incoming_dps) * BURN_STACK_RATIO
	var cap := maxf(maxf(0.0, incoming_dps) * BURN_CAP_MULT, maxf(0.0, current_dps))
	return minf(grown, cap)

## 施加剧毒后的新 DPS：持续累加；累积不越过「本次施加量 × POISON_CAP_MULT」，弱源不回落
static func stack_poison_dps(current_dps: float, incoming_dps: float) -> float:
	var cur := maxf(0.0, current_dps)
	var grown := cur + maxf(0.0, incoming_dps) * POISON_STACK_RATIO
	var cap := maxf(maxf(0.0, incoming_dps) * POISON_CAP_MULT, cur)
	return minf(grown, cap)

## 单次灼烧跳字（每 0.5s）实际结算伤害：受元素伤害属性与离火羁绊倍率双重增幅
static func burn_tick_damage(burn_dps: float, elemental_damage: float, synergy_burn_mult: float = 1.0) -> float:
	var base_tick := maxf(0.0, burn_dps) * DOT_TICK_INTERVAL + maxf(0.0, elemental_damage) * BURN_ELEM_TICK_COEF
	return maxf(1.0, base_tick * maxf(1.0, synergy_burn_mult))

## 单次剧毒跳字（每 0.5s）实际结算伤害：受元素伤害属性增幅
static func poison_tick_damage(poison_dps: float, elemental_damage: float) -> float:
	var base_tick := maxf(0.0, poison_dps) * DOT_TICK_INTERVAL + maxf(0.0, elemental_damage) * POISON_ELEM_TICK_COEF
	return maxf(1.0, base_tick)

# ---------------- 裂魂铃·击杀爆炸（2026-10-12） ----------------

const KILL_EXPLODE_IMPULSE := 110.0     ## 爆炸震退冲量基数（再乘玩家击退属性）
const KILL_EXPLODE_ELEM_COEF := 1.5     ## 元素伤害对爆炸的成长系数
## 尸爆口径（2026-10-25 血祭盛宴重做）：HP% 部分的随波封顶 —— 防 Boss 十万血炸出天文数字
const KILL_EXPLODE_HP_CAP_BASE := 400.0
const KILL_EXPLODE_HP_CAP_GROWTH := 1.14

## 击杀爆炸伤害 = 道具基数（ItemData 额外字段 kill_explode）+ 元素成长
## + 被杀敌人最大生命 × hp_ratio（血祭盛宴的尸爆口径，封顶随波复利；普通裂魂铃 hp_ratio=0 不吃这条）。
## 半径在 kill_explode_radius。
static func kill_explode_damage(base: float, elemental_damage: float,
		killed_max_hp: float = 0.0, hp_ratio: float = 0.0, wave: int = 1) -> float:
	var dmg := maxf(0.0, base) + maxf(0.0, elemental_damage) * KILL_EXPLODE_ELEM_COEF
	if hp_ratio > 0.0 and killed_max_hp > 0.0:
		var cap := KILL_EXPLODE_HP_CAP_BASE * pow(KILL_EXPLODE_HP_CAP_GROWTH, float(maxi(wave, 1) - 1))
		dmg += minf(killed_max_hp * hp_ratio, cap)
	return dmg

# ---------------- 震退方向 ----------------

const KNOCK_DIR_EPS := 0.0001   ## 方向退化为零向量的判定阈值（比的是长度平方）

## 武器震退的单位方向：以「受击点 − 施力点」的径向为主，但绝不把敌人往玩家身上推。
## 为什么要另算一支：BURST 类武器的落点是索敌分配（BalanceTargeting.assign_weapon_targets）
## 按角度扇区分的，常常砸在离玩家两三百像素的另一侧敌人上 —— 纯径向就会把「落点与玩家之间」
## 那圈敌人往玩家脸上拱（用户 2026-10-08：镇岳印「震一下，把敌人一波一波推到我身边来」）。
## 改法：径向带朝玩家的分量时把那一支投影掉 ⇒ 敌人侧身滑开；三点共线的纯对撞退化为直接外推。
## 输出恒为单位向量，所以各武器的击退力度数值一个字都不改。纯函数：入参出参只用值类型。
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

# ---------------- 聚灵阵释放（2026-10-25 祭坛重设计：伤害随波成长，别让固定 85 后期挠痒） ----------------

const OBELISK_DAMAGE_BASE := 120.0   ## 1 波全屏伤害（原固定 85：W1 抬到 120 让首次启动就有「大招感」）
const OBELISK_DAMAGE_GROWTH := 1.14  ## 每回合伤害复利（缓于敌血 1.16：相对威力随波缓降，鼓励灵兽价值 > 伤害价值）
const OBELISK_KNOCK_BASE := 340.0    ## 1 波击退力度
const OBELISK_KNOCK_WAVE_STEP := 10.0 ## 每回合击退加成（线性小步，与伤害复利同向）

## 按最大生命 % 的附加伤害分量（2026-10-26 新增）：flat 复利 1.14 缓于敌血 1.16，
## 后期对 Boss/精英的相对威力持续掉线；这条按 max_hp 折算的附加分量跟着敌血走，
## 保证后期一刀对厚血单位仍有交代（W1=2% → W20=11.5%，Boss W20 从 9% 削血提到 ~20%）。
const OBELISK_HP_RATIO_BASE := 0.02       ## 1 波按最大生命的附加比例（2%）
const OBELISK_HP_RATIO_WAVE_STEP := 0.005 ## 每回合 +0.5%（线性小步，W20=11.5%）

## 斩杀线（2026-10-26 新增）：受击前已在斩杀线下的敌人直接致命一刀收尾，让后期祭坛
## 从「全屏挨一刀」升级成「团本开怪+残血收割器」。前期阈值低（仅清将死垃圾）、
## 后期阈值升到 ~20%，让残血 Boss/精英也能被祭坛一刀封喉（Boss 二阶段 50% 与精英变异 60%
## 都在斩杀线之上，触发顺序不被绕过）。
const OBELISK_EXECUTE_BASE := 0.12        ## 1 波斩杀线（最大生命的 12%）
const OBELISK_EXECUTE_WAVE_STEP := 0.004  ## 每回合 +0.4%（W20≈19.6%）

## 全屏冲击伤害（flat 分量；按最大生命 % 与斩杀另算，调用方在 BlessingObelisk 拼装）
static func obelisk_blessing_damage(wave: int) -> float:
	return OBELISK_DAMAGE_BASE * pow(OBELISK_DAMAGE_GROWTH, float(maxi(wave, 1) - 1))

## 按最大生命折算的附加伤害比例（W1=2% → W20=11.5%）
static func obelisk_blessing_hp_ratio(wave: int) -> float:
	return OBELISK_HP_RATIO_BASE + float(maxi(wave, 1) - 1) * OBELISK_HP_RATIO_WAVE_STEP

## 斩杀血线（≤ 此比例的敌人受祭坛冲击直接致命；W1=12% → W20≈19.6%）
static func obelisk_execute_threshold(wave: int) -> float:
	return OBELISK_EXECUTE_BASE + float(maxi(wave, 1) - 1) * OBELISK_EXECUTE_WAVE_STEP

## 全屏击退力度
static func obelisk_knock_force(wave: int) -> float:
	return OBELISK_KNOCK_BASE + float(maxi(wave, 1) - 1) * OBELISK_KNOCK_WAVE_STEP

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
