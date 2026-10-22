class_name EnemyBase
extends CharacterBody2D

## 敌人通用基类（行为开关式上帝基类）：8 种行为支路靠 @export 开关组装，已按支路补分节注释。
## 组件化重构暂缓（2026-10-11 决策）：涉及每帧 AI/物理逻辑，留待大型敌人扩展需求出现时单独立项。
# ---------------- 敌种行为开关（.tscn 按敌种配置；>0 启用对应行为支路） ----------------
@export var max_hp: float = 18.0
@export var move_speed: float = 110.0
@export var contact_damage: float = 12.0
@export var is_elite: bool = false
## 死亡演出分级开关（2026-10-15）：false=小怪快节奏塌缩；true=尸体滞留慢渐隐。
## BossEnemy 置 true；不用 is BossEnemy 自判，避免基类反向引用子类（循环依赖坑）。
## 精英不走这个开关，走 is_elite 分支（踉跄倾倒后照常塌缩回池）。
var death_corpse_linger: bool = false
@export var exp_reward: int = 1
@export var enemy_id: String = ""          ## 敌种标识（为空时自动由节点名推导）
## 死亡音音高基准（2026-10-15 击杀连击音阶）：敌种在这里定个性音高，连击阶梯在
## AudioManager.register_kill_pitch 上叠层。默认 1.0 = 原素材音高；低音巨物 0.85、
## 尖啸小怪 1.15 这类口径由各敌种场景/刷怪口按需覆盖。
@export var die_pitch_base: float = 1.0
@export var spritesheet_path: String = ""
# 移动方式：gait=步态腿帧（默认）/ hover=悬浮（单姿势图集 + apply_hover 浮沉前倾）/ slither=蠕动（apply_slither 行进波）
@export var locomotion_mode: String = "gait"
# 可选行为（0 = 关闭，场景按怪种配置）
@export var preferred_range: float = 0.0   ## >0：远程怪，保持该距离环绕游走
@export var bolt_interval: float = 0.0     ## >0：每隔 N 秒向玩家发射火球
@export var bolt_damage: float = 9.0
@export var charge_interval: float = 0.0   ## >0：每隔 N 秒（含预警+冲刺的整周期）朝玩家长扑一次
@export var charge_min_range: float = 120.0  ## 长扑需要的「跑道」下沿：比这更近不起手（旧写法写死 120² 在判定里）
@export var charge_max_range: float = 450.0  ## 长扑上沿：远了不追扑（旧写法写死 450²）
@export var charge_windup_time: float = 1.2  ## 站桩预警时长
@export var charge_duration: float = 0.8     ## 冲刺时长（实冲位移见 GameBalance.charge_reach，不含纸面）
@export var charge_speed_mul: float = 3.2    ## 冲刺倍速（起步即满速，不再靠加速度爬）
@export var charge_brake_time: float = 0.25  ## 收势刹车时长：峰速线性刹到站定，这段位移也计入预警线
@export var charge_hit_radius: float = 34.0  ## 冲刺走廊半宽：建议取「敌我碰撞半径之和」⇒ 预警带画多宽就判多宽
@export var charge_damage_mul: float = 1.0   ## 冲刺伤害 = contact_damage × 它（与接触伤害同一条尺子，别另起一档）
@export var charge_whiff_stagger: float = 0.9 ## 落空收势硬直：冲空罚站给玩家反打窗口（命中则不罚）
@export var explode_radius: float = 0.0    ## >0：贴近玩家 40px 后点燃 0.8s 引信自爆
@export var heal_orb_drop: int = 0         ## >0：死亡掉「残丹」回血珠而非金币
@export var bolt_count: int = 1            ## 火球扇射数量（>1 时按 bolt_spread 扇形展开）
@export var bolt_spread: float = 0.18      ## 扇射间隔角（弧度）
@export var split_count: int = 0           ## >0：血蛹系——死亡时分裂出 N 只幼体（split_scene）
@export var split_scene: PackedScene = null
@export var buff_radius: float = 0.0       ## >0：鼓妖光环——范围内同伴获得移速加成
@export var buff_speed_mult: float = 1.35  ## 光环加速倍率
@export var spawn_minion_interval: float = 0.0  ## >0：蛛母系——每隔 N 秒产一只幼体（minion_scene）
@export var minion_scene: PackedScene = null
@export var teleport_interval: float = 0.0 ## >0：影魅系——每隔 N 秒闪现到玩家侧翼
@export var charge_side_bolts: int = 0     ## >0：冲刺起步时向左右两侧各放 N 发火球（烈雷兽变异，犀牛同款）
@export var slam_interval: float = 0.0     ## >0：每隔 N 秒以自身为中心震地（铁甲魔傀常驻招式）
@export var slam_radius: float = 0.0       ## 震地半径：预警圈 = 判定圈（同源）
@export var slam_windup: float = 0.8       ## 震地预警时长
@export var slam_dmg_mult: float = 1.2     ## 震地伤害 = contact_damage × 它
# —— 精英常驻招式（2026-10-22：精英从「血厚木桩」升级为双招式；变异 = 二阶段强化）——
@export var slam_hits: int = 1             ## 震地段数：1=单段；>1 为变异多段余波（首段有预警圈，余波直接冲击）
@export var slam_echo_gap: float = 0.45    ## 多段震地的段间隔（秒）：每段给一次横向走位窗口
@export var slam_radius_grow: float = 1.15 ## 余波逐段半径扩张倍率
@export var rock_interval: float = 0.0     ## >0：落石轰炸周期（铁甲魔傀第二招式，克制贴脸风筝）
@export var rock_count: int = 3            ## 单次落石点数（首点锁玩家预判位，其余环绕散布）
@export var rock_radius: float = 85.0      ## 单点落石半径：预警圈 = 判定圈（同源）
@export var rock_windup: float = 0.9       ## 落石预警时长
@export var rock_dmg_mult: float = 0.9     ## 单点落石伤害 = contact_damage × 它
@export var rock_spread: float = 140.0     ## 落点散布半径
@export var rock_lead: float = 0.35        ## 首点预判量（玩家速度 × 它，匀速跑位会被算中）
@export var ring_bolt_interval: float = 0.0 ## >0：雷环齐射周期（赤雷兽第二招式）
@export var ring_bolt_count: int = 8       ## 雷环弹数（均布全向）
@export var ring_bolt_speed: float = 150.0 ## 雷环弹速（px/s）
@export var ring_bolt_dmg_mult: float = 0.7 ## 单颗雷环伤害 = contact_damage × 它
@export var ring_bolt_windup: float = 0.4  ## 雷环起手前摇（站定提亮）
@export var ring_bolt_curve_ang: float = 0.45 ## 雷环弧线角速度（rad/s，形成旋臂压迫）
@export var chain_charges: int = 1         ## 一轮长扑的连续冲刺段数（>1 = 变异链冲）
@export var chain_windup_mult: float = 0.6 ## 后续冲刺的预警时长倍率（首段用场景原值）
@export var field_interval: float = 0.0    ## >0：雷剑域周期（剑煞邪修第二招式）
@export var field_radius: float = 120.0    ## 领域半径：预警圈 = 判定圈（同源）
@export var field_windup: float = 0.8      ## 落域预警时长
@export var field_dmg_mult: float = 0.8    ## 每跳伤害 = contact_damage × 它（受击无敌帧节流）
@export var field_duration: float = 3.5    ## 领域持续时长（秒）
@export var blink_strike_interval: float = 0.0 ## >0：瞬身回斩周期（剑煞变异专属）
@export var blink_strike_dist: float = 230.0 ## 瞬身落点距玩家距离
@export var blink_strike_bolts: int = 2    ## 回斩剑气数量
@export var blink_strike_bolt_arc: float = 0.18 ## 回斩剑气单侧张角（弧度）
@export var heal_interval: float = 0.0     ## >0：灵医系——每隔 N 秒治疗范围内同伴
@export var heal_radius: float = 0.0       ## 治疗光环半径
@export var heal_amount: float = 0.0       ## 每跳治疗量（WaveSpawner 按回合注入，见 BalanceWave.healer_amount）
@export var always_flee: bool = false      ## true：金蟾系——恒背离玩家逃窜（土豆兄弟 Looter 对应位）
@export var stone_reward: int = 0          ## >0：击杀额外掉金币（WaveSpawner 按回合注入，见 BalanceWave.looter_stone_reward）
@export var poison_interval: float = 0.0   ## >0：每隔 N 秒朝玩家所在地投一片毒潭（毒妖系）
@export var poison_radius: float = 0.0     ## 毒潭半径：预警圈 = 判定圈（同源，画多大判多大）
@export var poison_windup: float = 0.6     ## 投毒预警时长：落点先亮圈，圈填满 = 毒潭落下
@export var poison_damage: float = 4.0     ## 毒潭每跳伤害（跳的节奏由玩家受击无敌帧钉住）
@export var poison_duration: float = 5.0   ## 毒潭持续时长（秒）
@export var death_bolt_count: int = 0      ## >0：丹爆系——引信中途被击杀时向四周环形放 N 发弹幕（土豆兄弟 Pufferfish 型）
@export var death_bolt_dmg_mult: float = 0.6  ## 死亡弹幕伤害 = bolt_damage × 它（比活体火球软一档）
@export var charge_aim_lead: float = 0.0   ## >0：长扑锁向冲向「玩家当前位置 + 玩家速度 × 它」（土豆兄弟 Goblin Shark 预判位）
@export var bolt_windup: float = 0.0       ## >0：火球出手前的蓄力预告时长（站定 + 变色，出手瞬间锁向）；0 = 不蓄力直接发

# ---------------- 运行时状态 ----------------
var current_hp: float = 60.0
var knockback_velocity: Vector2 = Vector2.ZERO
var hit_stun_timer: float = 0.0   ## 受击定身硬直计时（期间暂停主动追击速度，仅随击退滑行）
var hit_stun_resist: float = 1.0  ## 受击硬直倍率（小怪 1.0，精英 0.55，Boss 0.25）
var _hit_freeze_timer: float = 0.0 ## 局部受击卡肉定格（秒）：冻结位移吸附在刀尖，随后释放击退冲量
var _hit_jiggle_offset: Vector2 = Vector2.ZERO  ## 受击瞬间视觉微反冲偏移
var _skid_dust_timer: float = 0.0 ## 滑行擦地扬尘计时
var _death_crit_kill: bool = false      ## 致命一刀是否为暴击（暴击击杀：独立顿帧 + 缩放冲击 + 精英 HEAVY 反馈）
var facing: String = "s":
	set(val):
		# 同值短路：_update_facing_and_anim 每物理帧都写本字段，不判新旧会把
		# 动画名重建打成每帧执行，白烧缓存（照 HollowKnightEnemyRenderer.flip_h 先例）
		if val == facing:
			return
		facing = val
		_rebuild_anim_name_cache()
## 动画名缓存：facing 极少变化，但朝向/步态分支每物理帧都要 "idle_"+facing /
## "run_"+facing 拼接 + has_animation 重查（35 敌 ≈ 每秒数千次 String 分配，
## Android 稳态 GC 停顿来源），改为 facing 变更时一次性重建。
var _anim_idle: String = "idle_s"
var _anim_run: String = "run_s"
var _anim_has_run: bool = false
var anim_base_scale: Vector2 = Vector2.ONE
var juice_scale: Vector2 = Vector2.ONE
var _bolt_timer: float = 1.2
var _bolt_windup_t: float = -1.0    ## >=0 表示火球蓄力中（站定 + 变色预告，出手瞬间锁向）
var _bolt_windup_total: float = 0.0  ## 本次蓄力总时长（算 0→1 进度，供器尖聚能与灵力汇聚读数）
var _bolt_gather_cd: float = 0.0     ## 蓄力期灵力汇聚粒子续发计时（低频，走 SOUL_ORB 帧闸）
var _bolt_windup_dir: Vector2 = Vector2.ZERO  ## 蓄力期实时朝向玩家（只用于预警读法，出手那帧才锁死）
var _bolt_base_tint: Color = Color.WHITE  ## 蓄力前本体色（精英变异染色等），蓄力结束/被打断时还原
var _death_bolts_spent: bool = false  ## 死亡弹幕一命只发一次闸（防自爆与击杀路径双发）
var _charge_timer: float = 0.0
var _charge_active: float = 0.0
var _charge_dir: Vector2 = Vector2.ZERO
var _charge_windup: float = -1.0   ## >=0 表示进入冲刺预警阶段
var _charge_warning_line: Line2D = null  ## 冲刺预警线节点
var _charge_brake: float = 0.0     ## >0 收势刹车锁定段（这一段的位移同样是承诺出去的一部分）
var _charge_stagger: float = 0.0   ## >0 落空罚站：不追人、任人打（冲刺的代价，与预警的兑现配成一对）
var _charge_hit: bool = false      ## 这一冲已经结算过（一次冲刺只碾一下）
var _fuse: float = -1.0   ## >=0 表示引信已点燃
const EXPLODE_FUSE := 0.8  ## 丹爆引信时长（秒）：预警圈填满 = 引信烧完 = 自爆结算
const FLEE_WALL_BAND := 80.0       ## 金蟾软墙警告带（px）：带内背离墙外的逃离分量清零改沿墙滑行；贴墙滑行向锁存防角落抖振
var _explode_ring: AoeTelegraph = null  ## 丹爆引信预警圈（挂身上跟随，半径 = explode_radius 同源）
var _no_drop: bool = false
var _flee_slide := Vector2.ZERO    ## 金蟾贴墙滑行方向锁存：x=贴上下墙的滑行向、y=贴左右墙的滑行向（0=未贴墙）
var _minion_timer: float = 0.0     ## 产卵计时
var _teleport_timer: float = 0.0   ## 闪现计时
var _buff_timer: float = 0.0       ## 光环脉冲计时（每 0.25s 刷新一次范围内同伴）
var _aura_speed_mult: float = 1.0  ## 被鼓妖光环覆盖时的移速加成
var _aura_until_ms: int = 0        ## 光环有效期（毫秒时间戳）
var _aura_shown: bool = false      ## 光环标记是否已点亮（边沿触发：从无到有时才发一次 shockwave）
var _focus_hit_timer: float = 0.0  ## 同目标短窗集火保护计时
var _focus_hit_count: int = 0      ## 短窗内已承受直击次数
var _elite_spark_cd: float = 0.0   ## 精英/Boss 受击火花冷却（秒）：束流 tick/多段命中只冒一朵

## 步态相位（弧度）：仅在移动时按 speed_ratio 推进，供渲染器摆翼/蠕波与位移同相
var _gait_phase: float = 0.0
const GAIT_FREQ_HOVER := 6.0     ## 悬浮/飞行 步态角频率（rad/s，speed_ratio=1 时）
const GAIT_FREQ_SLITHER := 9.0   ## 蠕动 行进波角频率

# 投毒支路运行时状态（毒妖系；预警圈 = 判定圈同源，真话源在本类）
var _poison_timer: float = 0.0        ## 投毒冷却计时
var _poison_windup_t: float = -1.0    ## >=0 表示投毒预警中
var _poison_target: Vector2 = Vector2.ZERO  ## 锁定的落点（预警期间不追踪玩家，否则 0.6s 躲不开）
var _poison_ring: AoeTelegraph = null ## 落点预警圈

# 精英变异（2026-10-12，仿土豆兄弟 Elite Mutation：过血线一次性切换行为参数）
var _eid: String = ""              ## 解析后的敌种标识（_ready 落定，变异分发的依据）
var _mutated: bool = false         ## 变异只触发一次
var _elite_slam_timer: float = 0.0       ## 震地周期计时
var _elite_slam_windup_t: float = -1.0   ## >=0 表示震地预警中
var _elite_slam_ring: AoeTelegraph = null
var _heal_timer: float = 0.0       ## 灵医治疗跳计时
# —— 精英常驻招式运行时状态（2026-10-22）——
var _slam_echo_left: int = 0        ## 多段震地剩余段数（首段结算后倒数）
var _slam_echo_t: float = -1.0      ## >=0 表示余波间隔倒计时中
var _slam_echo_radius: float = 0.0  ## 本段余波半径（逐段 × slam_radius_grow）
var _rock_timer: float = 0.0        ## 落石周期计时
var _rock_windup_t: float = -1.0    ## >=0 表示落石预警中
var _rock_points: Array[Vector2] = []   ## 本次落石锁定的落点（起手帧锁死，预警期不追人）
var _rock_rings: Array[AoeTelegraph] = [] ## 落点预警圈（每个落点一个，半径 = rock_radius 同源）
var _ring_bolt_timer: float = 0.0   ## 雷环周期计时
var _ring_bolt_windup_t: float = -1.0 ## >=0 表示雷环起手前摇中
var _chain_left: int = 0            ## 本轮长扑剩余冲刺段数
var _chain_t: float = -1.0          ## >=0 表示链冲段间短预警倒计时
var _field_timer: float = 0.0       ## 雷剑域周期计时
var _field_windup_t: float = -1.0   ## >=0 表示落域预警中
var _field_target: Vector2 = Vector2.ZERO ## 锁定的落域点
var _field_ring: AoeTelegraph = null ## 落域预警圈
var _blink_strike_timer: float = 0.0 ## 瞬身回斩周期计时
var _charge_windup_total: float = 0.0 ## 本次冲刺预警总时长（链冲后段按倍率缩短，进度分母必须同源）

# 五行元素异常状态（灼烧/冰缓/剧毒）
var burn_timer: float = 0.0
var burn_dps: float = 0.0
var _burn_tick: float = 0.0
var poison_timer: float = 0.0
var poison_dps: float = 0.0
var _poison_tick: float = 0.0
var chill_timer: float = 0.0
var chill_slow: float = 0.0

# —— 五行异常体表视觉（2026-10-19 V3：灼烧火星/剧毒雾斑/冰缓霜晶 + 本体染色）——
## DoT 存续期每隔 STATUS_FX_INTERVAL 在体表续一发低频粒子（三系共用 FxBudget 帧闸），
## 灼烧/剧毒顺带染色（冰缓染色在 _effective_speed 既有链路）。染色互斥纪律：
## 冰缓 > 灼烧 > 剧毒 > 本体色；引信（_fuse>=0）与火球蓄力（_bolt_windup_t>=0）独占
## modulate，异常染色整段让位。同值短路：Godot setter 同值赋值无重绘副作用。
const STATUS_FX_INTERVAL := 0.45              ## 体表粒子续发间隔（错相靠 instance_id 相位）
const STATUS_TINT_BURN := Color(1.55, 1.05, 0.8)   ## 灼烧暖橙提亮（对齐冰缓提亮思路，不压暗）
const STATUS_TINT_POISON := Color(0.9, 1.45, 0.85) ## 剧毒青绿提亮
var _status_fx_cd: float = 0.0                ## 体表粒子续发计时（activate 时按 instance_id 错相）

@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var shadow_sprite: Sprite2D = get_node_or_null("Shadow") as Sprite2D
@onready var hit_flash_mat: ShaderMaterial = anim_sprite.material as ShaderMaterial

var gem_scene: PackedScene = preload("res://scenes/entities/AstralGem.tscn")
# —— 受击视觉零 Tween 分配化（2026-10-11 第 6 波卡顿优化）——
## 旧写法每次受击 create_tween ×2（挤压回弹 + 闪白），DoT 每 0.5s×N 敌也在持续触发；
## 35 怪高频命中的回合里 Tween 生命周期管理是实打实的分配热点。改帧内计时衰减，
## 曲线与原 Tween 一致（挤压 TRANS_BACK EASE_OUT；闪白 0.02s 拉满段在 60fps 下只有
## 1~2 帧，命中瞬间直接置峰，视觉无差）。衰减统一在 _tick_hit_fx 逐帧做。
var _squash_from: Vector2 = Vector2.ONE  ## 挤压起点（目标形变）
var _squash_t: float = 0.0               ## 挤压剩余时长
var _squash_dur: float = 0.16            ## 挤压总时长（插值分母）
var _flash_t: float = 0.0                ## 闪白剩余时长（衰减段）
var _flash_down_dur: float = 0.11        ## 本次闪白衰减总时长（归一化分母）
var _flash_swap_t: float = 0.0           ## 暴击绯金→暖白换色倒计时（普通命中为 0）
var _flash_col: Color = Color(1.0, 1.0, 0.95, 1.0)  ## 当前闪白目标色（顶点色通道驱动版）
var _run_state := RunMotion.RunMotionState.new()   ## 步态/悬浮状态载体（2026-10-17 去 meta 化，随实例池化复用）

# —— 受击闪白目标色（顶点色通道版，2026-10-17 性能专项）——
# 旧版是 per-instance shader uniform（19 场景 resource_local_to_scene=true ⇒ 每敌独享材质，
# 759 draw call 的主要来源）。新版全部实例共享一份直通材质，闪白由 self_modulate 承载：
# _write_flash_channel 按 flash 权重向目标色提亮写入 self_modulate —— 分量 >1 时顶点色
# 外溢成超白（HDR glow 起辉），视觉口径与旧 shader mix(flash_color) 等价。
# 提亮基点取 1.8 而非 1.0：直通材质下 mix 语义改为「向提亮色 lerp」，1.8 峰值才能贴住旧观感。
const FLASH_COL_NORMAL := Color(1.8, 1.75, 1.7)   ## 普通受击：亮白（提亮基点）
const FLASH_COL_CRIT := Color(2.4, 1.15, 0.62)    ## 暴击：绯金（红绿超白起辉）
const FLASH_COL_SWAP := Color(1.8, 1.72, 1.62)   ## 暴击换色：暖白衰减段

## 受击闪白顶点色写入（零 uniform 唯一出口）：
## flash=0 时写回纯白（直通），>0 时向 _flash_col 提亮 lerp。
## 只写 self_modulate（闪白业务独占）；modulate 仍归冰缓/引信/蓄力染色，COLOR 相乘叠加。
## 同值短路：静止值写入是幂等的，Godot setter 同值赋值无重绘副作用。
func _write_flash_channel(flash: float) -> void:
	if flash <= 0.001:
		if anim_sprite.self_modulate != Color.WHITE:
			anim_sprite.self_modulate = Color.WHITE
		if procedural_view != null and procedural_view.self_modulate != Color.WHITE:
			procedural_view.self_modulate = Color.WHITE
		return
	var tint: Color = Color.WHITE.lerp(_flash_col, clampf(flash, 0.0, 1.0))
	anim_sprite.self_modulate = tint
	if procedural_view != null:
		procedural_view.self_modulate = tint
var _hit_tilt: float = 0.0          ## 受创后仰倾角（受击瞬间沿受力反向倾斜，急刹后平滑回正）

## 屏外减负（2026-10-10 第 6 波卡顿优化）：出屏边距与节流判定缓存
const CULL_MARGIN := 64.0
const CULL_INTERVAL := 0.1          ## 屏外判定 10Hz（敌人进出屏幕是秒级事件，60Hz 判定是白烧）
var _offscreen: bool = false
var _cull_timer: float = 0.0        ## 错相初值在 _ready 按 instance_id 摊开
var dying: bool = false
var procedural_view: ProceduralEnemyView = null

# —— 敌人对象池（2026-10-13）——
## 敌人是全项目最重的节点图（双碰撞体 + 程序化视图 + local_to_scene 材质），原先每刷一只
## instantiate、每死一只 queue_free——刷怪尖峰与长局 GC 压力主要来自这里。照 BladeProjectile
## 池模式：死亡/波末消散不再 queue_free 而是出树休眠回池；桶键 = 场景路径（普通/精英天然分桶）。
## 关键约束：
##   - 池体完全出树（remove_child，不挂池宿主）——在树、登记表、"enemies" 组三者同拍，
##     池体绝不进组（否则回合末清场/get_nodes_in_group 会摸到池里的休眠体）
##   - Boss 不入池：每局只出几次，重置复杂度高，_poolable 恒 false 走老路 queue_free
##   - 出场基准快照必须在 instantiate 当刻拍（_capture_base_stats），晚一拍就被
##     _scale_to_wave / 精英变异原地改过的字段污染
const POOL_CAP_PER_KIND := 40  ## 每种敌的池上限；溢出个体直接释放（项目惯例：不把池撑大）
const ELITE_LIGHT_CAP := FxBudget.LIGHT_CAP_ELITE  ## 精英灯名额基准（实际生效走 FxBudget.elite_light_cap()，移动端减半）
static var _lit_elite_count: int = 0
var _has_elite_light: bool = false
static var _pools: Dictionary = {}     ## scene_path -> Array[EnemyBase]
static var pool_created_count: int = 0 ## 探针断言用：复用两轮零增长
static var pool_reused_count: int = 0
static var _explode_snap_pool: Array = []  ## 裂魂铃链爆快照复用栈（每层递归独占一张，clear 回栈容量不丢）

## —— 全局大面积特效时间戳闸（2026-10-16 演出去噪）——
## 静态时间戳闸（Time.get_ticks_msec）：同屏大面积演出（焦痕/爆炸环）走「最后一次放行后
## GAP 内全静默」，无论多少只怪同帧同秒触发。用时间戳不用共享倒计时——倒计时被多实例
## 各自扣一遍会加速漏闸。GDScript 坑：位移 << 不吃负操作数，初值只写普通负数。
const GROUND_SCORCH_MIN_GAP_MS := 5000   ## 自爆焦痕：屏上至多一块，与贴花 2.3s 寿命衔接（2026-10-19 去裂痕化同步翻倍）
const KILL_EXPLODE_FX_MIN_GAP_MS := 700  ## 裂魂铃爆炸环：清怪高潮不再冲击环雨，保留节奏读数
static var _last_scorch_ms: int = -999999
static var _last_kill_explode_fx_ms: int = -999999

## 全局闸通行检查：距上次放行 ≥ gap_ms 时放行并记账，否则静默拦下
static func _fx_gap_gate(gap_ms: int, slot: String) -> bool:
	var now_ms := Time.get_ticks_msec()
	var last_ms: int = _last_scorch_ms if slot == "scorch" else _last_kill_explode_fx_ms
	if now_ms - last_ms < gap_ms:
		return false
	if slot == "scorch":
		_last_scorch_ms = now_ms
	else:
		_last_kill_explode_fx_ms = now_ms
	return true
var _poolable: bool = false            ## 是否可回池（仅 acquire_or_new 出的个体为 true）
var _pooled: bool = false              ## 当前是否泡在池里
var _pool_key: String = ""
var _active: bool = false              ## activate() 幂等闸
var _assembled: bool = false           ## _ready 一次性装配闸（复用个体 _ready 不重跑）
var _base_stats: Dictionary = {}       ## instantiate 当刻的出厂字段快照（空 = 尚未拍过）

func _enter_tree() -> void:
	# 活体登记从 _ready 挪到这里：池化复用时 _ready 不重跑，登记必须与进出树严格同拍
	GameManager.register_enemy(self)

# ---------------- 生命周期与程序化外观初始化 ----------------
func _ready() -> void:
	# 一次性装配（池化复用时 _ready 不重跑，由 reset_for_reuse + activate 接管每命初始化）
	if not _assembled:
		_assembled = true
		# 全体敌人共享同一份受击闪白材质（2026-10-20 移动端 draw call 专项）：
		# 18 个敌人场景各自带一份 ShaderMaterial 子资源 → 同屏多敌种按材质分桶断批。
		# shader 已零 uniform（闪白走 self_modulate 顶点色），可让所有敌种共用同一实例，
		# 跨敌种恢复 canvas 合批。桌面/移动都生效，视觉零差异。
		var shared_mat := _get_shared_hit_flash_mat()
		if shared_mat != null:
			anim_sprite.material = shared_mat
			hit_flash_mat = shared_mat
		anim_base_scale = anim_sprite.scale
		var eid := enemy_id
		if eid.is_empty():
			eid = _deduce_enemy_id()
		_eid = eid
		# 程序化矢量视图先装配 —— 它决定图集还要不要加载（见下）
		var has_procedural: bool = _init_procedural_view(eid)

		# 图集腿帧只在「没有程序化配置」时才加载。EnemyVisualConfig.get_config 对全部敌种
		# 都有配置（含 _ 兜底分支），所以当前一只怪都不会走这里：20 张 960×960 图集解码后
		# 单张 3.5MB、合计约 70MB 常驻，是全项目最大的一块内存/显存开销，而屏上角色实际
		# 只有约 121px（192px 格 × 0.63 缩放）。spritesheet_path 与 _setup_frames 保留为兜底。
		# 注意：anim_sprite 节点不能删 —— 它不再是渲染器，而是 RunMotion 的形变状态载体
		# （步态/悬浮/蠕动的 scale·rotation·offset 写在它身上，再由 _update_facing_and_anim
		# 转发给 procedural_view），LingYi/JinChan 无图集却动画正常即是这条路径的现成反证。
		if not has_procedural:
			if spritesheet_path != "" and ResourceLoader.exists(spritesheet_path):
				_setup_frames(spritesheet_path)
			elif anim_sprite.sprite_frames != null and anim_sprite.sprite_frames.has_animation("idle"):
				anim_sprite.play("idle")
		_rebuild_anim_name_cache()
	activate()

## 每命初始化：新实例由 _ready 调入；池化复用实例由刷怪口在配置完字段后显式调入（幂等）。
## 注意只放「每命都要重来」的事，一次性装配（视图/帧集/基准快照）在 _ready 的 _assembled 闸内。
func activate() -> void:
	if _active:
		return
	_active = true
	# 小怪整体加血（GameBalance.MOB_HP_BASE_MULT）：精英/Boss 不吃这条，它们的厚度由基础值拉开。
	# 收口在 activate 这一处：WaveSpawner 刷怪、蛛母产卵、血蛹分裂、Boss 召唤全都经过这里，
	# 不用在四个刷怪口各乘一遍。2026-10-10 用户口径：「敌人都是一击秒杀，感觉不到打击感」。
	if not is_elite:
		max_hp = ceilf(max_hp * GameBalance.MOB_HP_BASE_MULT)
	current_hp = max_hp
	_flee_slide = Vector2.ZERO

	# 敌人出生时的弹性跃出感
	juice_scale = Vector2(0.3, 0.3)
	play_squash(Vector2(1.18, 0.85), 0.22)

	# 出生缓冲：封顶 1.0 秒（仍然不是「出屏第一帧就扑」，玩家有 1 秒看清这只怪逼近）。
	# 旧写法直接取 charge_interval（4.0s），而狼移速 120px/s 从 380~480px 走到冲刺下沿
	# （120px）只要 2.2~3.0s ⇒ 冷却就绪时狼已贴脸进短咬带，冲刺条件 dist>120px 永远不满足。
	# 封顶 1.0s 而非 2.0s：v0.0.7 全局砍血后狼只有 45HP，2.0s+1.2s 预警=3.2s 站桩太长，
	# 中等火力下狼在预警期间就被打死了，活不到冲刺出手那一下。
	_charge_timer = minf(charge_interval, 1.0)
	_minion_timer = spawn_minion_interval
	_teleport_timer = teleport_interval
	_elite_slam_timer = slam_interval
	_heal_timer = heal_interval
	_refresh_elite_light()
	_poison_timer = poison_interval
	# 精英常驻招式：进场即就绪（首招不立刻砸脸，给玩家 1s 看清怪再起手）
	_rock_timer = minf(rock_interval, 2.0) if rock_interval > 0.0 else 0.0
	_ring_bolt_timer = minf(ring_bolt_interval, 1.6) if ring_bolt_interval > 0.0 else 0.0
	_field_timer = minf(field_interval, 2.2) if field_interval > 0.0 else 0.0
	_blink_strike_timer = blink_strike_interval

	# 屏外判定错相：35 只怪的 10Hz 查询摊到不同帧，不扎堆
	_cull_timer = float(get_instance_id() % 6) * (CULL_INTERVAL / 6.0)

## 出厂字段快照：必须赶在刷怪口 _scale_to_wave / 精英变异原地改数之前拍（acquire 当刻调用）。
## 清单口径 = 所有「出场后会被原地改写」的导出字段：_scale_to_wave 四项 + 变异十二项 + 根节点变换。
func _capture_base_stats() -> void:
	_base_stats = {
		"max_hp": max_hp, "contact_damage": contact_damage, "move_speed": move_speed,
		"heal_amount": heal_amount, "stone_reward": stone_reward,
		"die_pitch_base": die_pitch_base,
		"charge_interval": charge_interval, "charge_side_bolts": charge_side_bolts,
		"charge_aim_lead": charge_aim_lead,
		"bolt_count": bolt_count, "bolt_interval": bolt_interval, "preferred_range": preferred_range,
		"bolt_windup": bolt_windup,
		"death_bolt_count": death_bolt_count, "death_bolt_dmg_mult": death_bolt_dmg_mult,
		"slam_interval": slam_interval, "slam_radius": slam_radius,
		"slam_windup": slam_windup, "slam_dmg_mult": slam_dmg_mult,
		"slam_hits": slam_hits, "slam_echo_gap": slam_echo_gap,
		"slam_radius_grow": slam_radius_grow,
		"rock_interval": rock_interval, "rock_count": rock_count,
		"rock_radius": rock_radius, "rock_windup": rock_windup,
		"rock_dmg_mult": rock_dmg_mult, "rock_spread": rock_spread, "rock_lead": rock_lead,
		"ring_bolt_interval": ring_bolt_interval, "ring_bolt_count": ring_bolt_count,
		"ring_bolt_speed": ring_bolt_speed, "ring_bolt_dmg_mult": ring_bolt_dmg_mult,
		"ring_bolt_windup": ring_bolt_windup, "ring_bolt_curve_ang": ring_bolt_curve_ang,
		"chain_charges": chain_charges, "chain_windup_mult": chain_windup_mult,
		"field_interval": field_interval, "field_radius": field_radius,
		"field_windup": field_windup, "field_dmg_mult": field_dmg_mult,
		"field_duration": field_duration,
		"blink_strike_interval": blink_strike_interval, "blink_strike_dist": blink_strike_dist,
		"blink_strike_bolts": blink_strike_bolts, "blink_strike_bolt_arc": blink_strike_bolt_arc,
		"poison_interval": poison_interval, "poison_radius": poison_radius,
		"poison_windup": poison_windup, "poison_damage": poison_damage,
		"poison_duration": poison_duration,
		"root_scale": scale, "root_modulate": modulate,
	}

## 池化复用的整备：出厂字段回滚 + 战斗运行时清零 + 视觉/物理节点归位。
## 新实例（_assembled=false，尚未进过树）直接跳过——出厂值本就干净，
## 且 @onready 变量（anim_sprite/hit_flash_mat）在 _ready 前还是 null，碰了会崩。
## 调用时机：刷怪口 acquire 之后、_scale_to_wave 之前。
func reset_for_reuse() -> void:
	if not _assembled:
		return
	# 1) 出厂基准回滚
	max_hp = _base_stats["max_hp"]
	contact_damage = _base_stats["contact_damage"]
	move_speed = _base_stats["move_speed"]
	heal_amount = _base_stats["heal_amount"]
	stone_reward = _base_stats["stone_reward"]
	die_pitch_base = _base_stats["die_pitch_base"]
	charge_interval = _base_stats["charge_interval"]
	charge_side_bolts = _base_stats["charge_side_bolts"]
	charge_aim_lead = _base_stats["charge_aim_lead"]
	bolt_count = _base_stats["bolt_count"]
	bolt_interval = _base_stats["bolt_interval"]
	preferred_range = _base_stats["preferred_range"]
	bolt_windup = _base_stats["bolt_windup"]
	death_bolt_count = _base_stats["death_bolt_count"]
	death_bolt_dmg_mult = _base_stats["death_bolt_dmg_mult"]
	slam_interval = _base_stats["slam_interval"]
	slam_radius = _base_stats["slam_radius"]
	slam_windup = _base_stats["slam_windup"]
	slam_dmg_mult = _base_stats["slam_dmg_mult"]
	slam_hits = _base_stats["slam_hits"]
	slam_echo_gap = _base_stats["slam_echo_gap"]
	slam_radius_grow = _base_stats["slam_radius_grow"]
	rock_interval = _base_stats["rock_interval"]
	rock_count = _base_stats["rock_count"]
	rock_radius = _base_stats["rock_radius"]
	rock_windup = _base_stats["rock_windup"]
	rock_dmg_mult = _base_stats["rock_dmg_mult"]
	rock_spread = _base_stats["rock_spread"]
	rock_lead = _base_stats["rock_lead"]
	ring_bolt_interval = _base_stats["ring_bolt_interval"]
	ring_bolt_count = _base_stats["ring_bolt_count"]
	ring_bolt_speed = _base_stats["ring_bolt_speed"]
	ring_bolt_dmg_mult = _base_stats["ring_bolt_dmg_mult"]
	ring_bolt_windup = _base_stats["ring_bolt_windup"]
	ring_bolt_curve_ang = _base_stats["ring_bolt_curve_ang"]
	chain_charges = _base_stats["chain_charges"]
	chain_windup_mult = _base_stats["chain_windup_mult"]
	field_interval = _base_stats["field_interval"]
	field_radius = _base_stats["field_radius"]
	field_windup = _base_stats["field_windup"]
	field_dmg_mult = _base_stats["field_dmg_mult"]
	field_duration = _base_stats["field_duration"]
	blink_strike_interval = _base_stats["blink_strike_interval"]
	blink_strike_dist = _base_stats["blink_strike_dist"]
	blink_strike_bolts = _base_stats["blink_strike_bolts"]
	blink_strike_bolt_arc = _base_stats["blink_strike_bolt_arc"]
	poison_interval = _base_stats["poison_interval"]
	poison_radius = _base_stats["poison_radius"]
	poison_windup = _base_stats["poison_windup"]
	poison_damage = _base_stats["poison_damage"]
	poison_duration = _base_stats["poison_duration"]
	scale = _base_stats["root_scale"]
	modulate = _base_stats["root_modulate"]
	# 2) 战斗运行时状态清零
	knockback_velocity = Vector2.ZERO
	hit_stun_timer = 0.0
	_hit_freeze_timer = 0.0
	_hit_jiggle_offset = Vector2.ZERO
	_skid_dust_timer = 0.0
	_death_crit_kill = false
	facing = "s"
	_rebuild_anim_name_cache()
	juice_scale = Vector2.ONE
	_bolt_timer = 1.2
	_bolt_windup_t = -1.0
	_bolt_windup_total = 0.0
	_bolt_gather_cd = 0.0
	_bolt_base_tint = Color.WHITE
	_death_bolts_spent = false
	_charge_active = 0.0
	_charge_dir = Vector2.ZERO
	_charge_windup = -1.0
	_charge_windup_total = 0.0
	_charge_brake = 0.0
	_charge_stagger = 0.0
	_charge_hit = false
	_fuse = -1.0
	_no_drop = false
	_buff_timer = 0.0
	_aura_speed_mult = 1.0
	_aura_until_ms = 0
	_aura_shown = false
	_focus_hit_timer = 0.0
	_focus_hit_count = 0
	_elite_spark_cd = 0.0
	_gait_phase = 0.0
	_mutated = false
	_elite_slam_windup_t = -1.0
	_slam_echo_left = 0
	_slam_echo_t = -1.0
	_slam_echo_radius = 0.0
	_rock_timer = 0.0
	_rock_windup_t = -1.0
	_rock_points.clear()
	_ring_bolt_timer = 0.0
	_ring_bolt_windup_t = -1.0
	_chain_left = 0
	_chain_t = -1.0
	_field_timer = 0.0
	_field_windup_t = -1.0
	_field_target = Vector2.ZERO
	_blink_strike_timer = 0.0
	_poison_timer = 0.0
	_poison_windup_t = -1.0
	_poison_target = Vector2.ZERO
	burn_timer = 0.0
	burn_dps = 0.0
	_burn_tick = 0.0
	poison_timer = 0.0
	poison_dps = 0.0
	_poison_tick = 0.0
	chill_timer = 0.0
	chill_slow = 0.0
	# 体表粒子续发按 instance_id 错相摊开，群怪同中异常不会同帧齐发撞帧闸
	_status_fx_cd = STATUS_FX_INTERVAL * fposmod(float(get_instance_id() % 89) * 0.011, 1.0)
	_squash_t = 0.0
	_flash_t = 0.0
	_flash_swap_t = 0.0
	_hit_tilt = 0.0
	_offscreen = false
	_pp_stun = false
	_pp_target_vel = Vector2.ZERO
	dying = false
	velocity = Vector2.ZERO
	rotation = 0.0
	# 3) 挂在身上的预警节点兜底清掉（dissolve 清场路径不经过 _die 的 _clear_*，复用前必须收）
	if is_instance_valid(_charge_warning_line):
		_charge_warning_line.queue_free()
	_charge_warning_line = null
	if is_instance_valid(_explode_ring):
		_explode_ring.queue_free()
	_explode_ring = null
	if is_instance_valid(_elite_slam_ring):
		_elite_slam_ring.queue_free()
	_elite_slam_ring = null
	if is_instance_valid(_poison_ring):
		_poison_ring.queue_free()
	_poison_ring = null
	_clear_rock_rings()
	if is_instance_valid(_field_ring):
		_field_ring.queue_free()
	_field_ring = null
	# 4) 视觉/物理节点归位（死亡塌缩 tween 会把 scale 收到 0、modulate 收到透明，必须还原）
	visible = true
	anim_sprite.scale = anim_base_scale
	anim_sprite.modulate = Color.WHITE
	anim_sprite.position = Vector2.ZERO
	anim_sprite.rotation = 0.0
	anim_sprite.offset = Vector2.ZERO
	if procedural_view != null:
		procedural_view.scale = anim_base_scale
		procedural_view.modulate = Color.WHITE
		procedural_view.position = Vector2.ZERO
		procedural_view.rotation = 0.0
	# 闪白通道复位（顶点色版）：self_modulate 归白即零闪白；材质仍指回共享 hit_flash
	# （dissolve 死亡路径会把 material 换成 _dissolve_mat，复用前必须切回）
	_write_flash_channel(0.0)
	if hit_flash_mat != null:
		if procedural_view != null:
			procedural_view.material = hit_flash_mat
		anim_sprite.material = hit_flash_mat
	set_physics_process(true)
	set_process(true)
	$CollisionShape2D.disabled = false
	$Hurtbox/CollisionShape2D.disabled = false
	_release_elite_light()

## 取一只敌人：池里有同种休眠体就复用，没有 instantiate 新的（出厂快照在离开池口前拍好）。
## 调用方随后 reset_for_reuse() → 配位置/成长字段 → activate() → add_child。
static func acquire_or_new(scene: PackedScene) -> EnemyBase:
	if scene == null:
		return null
	var key := scene.resource_path
	var bucket: Array = _pools.get(key, [])
	while not bucket.is_empty():
		var e := bucket.pop_back() as EnemyBase
		if is_instance_valid(e) and e._pooled:
			e._pooled = false
			pool_reused_count += 1
			return e
	var fresh := scene.instantiate() as EnemyBase
	if fresh == null:
		return null
	fresh._poolable = true
	fresh._pool_key = key
	fresh._capture_base_stats()
	pool_created_count += 1
	return fresh

## 回收一只敌人进池休眠：出树（_exit_tree 自动注销登记表）+ 退组 + 停表。
## 池满直接释放，不把池撑大（项目通行口径）。
static func _recycle(e: EnemyBase) -> void:
	if not is_instance_valid(e) or e._pooled:
		return
	e._pooled = true
	e._active = false
	e.remove_from_group("enemies")
	if e.get_parent() != null:
		e.get_parent().remove_child(e)
	e.set_physics_process(false)
	e.set_process(false)
	e.set_process_input(false)
	e.visible = false
	# 闪白通道复位（顶点色版，回池体不许带着上一命的闪白残值见调用方）
	e._write_flash_channel(0.0)
	if e.hit_flash_mat != null:
		if e.procedural_view != null:
			e.procedural_view.material = e.hit_flash_mat
		e.anim_sprite.material = e.hit_flash_mat
	var bucket: Array = _pools.get(e._pool_key, [])
	if bucket.size() >= POOL_CAP_PER_KIND:
		e.free()
		return
	bucket.append(e)
	_pools[e._pool_key] = bucket

## 尸体动画终点回调（_die / dissolve 的 tween 末尾）：池化个体回池，Boss 等未入池个体照旧释放
func _recycle_or_free() -> void:
	if _poolable:
		EnemyBase._recycle(self)
	else:
		queue_free()

## 释放池内全部休眠个体（Main._exit_tree 随场景清）：池体出树常驻，不主动放开
## 会被退出检查报成 "resources still in use at exit" 假泄漏（与 _frames_cache 同一条坑）
static func clear_pools() -> void:
	for key in _pools.keys():
		for e in _pools[key]:
			if is_instance_valid(e):
				e.free()
	_pools.clear()
	# 影魅残影池同为静态节点引用：场景 teardown 后池中节点已随树释放，必须清空防悬空复用
	for g in _ghost_idle:
		if is_instance_valid(g):
			g.free()
	_ghost_idle.clear()
	_explode_snap_pool.clear()

## 池内休眠体总数（探针/判据用）
static func pool_idle_count() -> int:
	var n := 0
	for key in _pools.keys():
		n += (_pools[key] as Array).size()
	return n

func _exit_tree() -> void:
	GameManager.unregister_enemy(self)
	_release_elite_light()

## 动态控灯：精英/魔偶挂载 PointLight2D 时，受 FxBudget.LIGHT_CAP_ELITE 额度门控，超限关灯防打穿全场上限
func _refresh_elite_light() -> void:
	var l := get_node_or_null("PointLight2D") as PointLight2D
	if l == null:
		return
	if _has_elite_light:
		l.enabled = true
		return
	if _lit_elite_count < FxBudget.elite_light_cap():
		_lit_elite_count += 1
		_has_elite_light = true
		l.enabled = true
	else:
		l.enabled = false

func _release_elite_light() -> void:
	if _has_elite_light:
		_has_elite_light = false
		_lit_elite_count = maxi(0, _lit_elite_count - 1)
	var l := get_node_or_null("PointLight2D") as PointLight2D
	if l != null:
		l.enabled = false

## 由场景根节点名推导 enemy_id：遍历 EnemyData.ID_PREFIXES 的前缀表。
## 原先这里是 16 分支 begins_with 链 —— 加一种怪要同时改 EnemyData 与 EnemyBase 两处，
## 漏改这边就静默降级成史莱姆外观。现在新增怪种只需在 ID_PREFIXES 登记一行。
## 表序即优先级（先命中先返回），故 boss / 精英这类易混前缀必须排在通用前缀之前；
## 前缀表本就互不为前缀，顺序实际无歧义。兜底仍是 slime（与旧链行为一致）。
func _deduce_enemy_id() -> String:
	var n := name.to_lower()
	for id in EnemyData.ID_PREFIXES:
		if n.begins_with(String(EnemyData.ID_PREFIXES[id])):
			return String(id)
	return "slime"

## 装配程序化矢量视图。返回 true = 已挂上渲染器（调用方据此跳过图集加载）。
## EnemyVisualConfig.get_config 对全部敌种都有配置（含 _ 兜底），当前恒返回 true。
func _init_procedural_view(eid: String) -> bool:
	if procedural_view != null:
		procedural_view.queue_free()
	procedural_view = ProceduralEnemyView.new()
	var is_boss_enemy: bool = (eid == "boss" or self.get("final_boss") != null)
	var is_final: bool = bool(self.get("final_boss")) if self.get("final_boss") != null else false
	procedural_view.setup(eid, is_elite, is_boss_enemy, is_final)
	var ok: bool = procedural_view.config != null
	if anim_sprite != null and ok:
		# 只在确实有矢量外观时才藏旧精灵 —— 否则「图集没加载 + 精灵被藏」= 场上出现隐形怪
		anim_sprite.visible = false
		# 双影子二选一（2026-10-14 P2）：矢量渲染器自画贴地影（含蓄力下蹲/浮沉呼吸联动），
		# RunMotion 驱动的 sprite 影在此分支纯叠画（两层影高度还不同，上下叠成两道）——隐藏不删，
		# 图集兜底路径（无矢量外观的怪）仍要靠它
		if shadow_sprite != null:
			shadow_sprite.visible = false
		procedural_view.position = anim_sprite.position
		procedural_view.scale = anim_sprite.scale
		if hit_flash_mat != null:
			procedural_view.material = hit_flash_mat
	add_child(procedural_view)
	return ok

## 同种敌人的帧集合逐字节相同，按「贴图路径|是否精英」缓存：
## 原先每只敌人在 _ready 里新建一套 SpriteFrames + 8 方向 ×6 帧 AtlasTexture，
## 是长局里最大的一块分配压力（比 instantiate/free 节点本身贵得多）。
## 共享后 SpriteFrames 只读，节点级状态（scale/modulate/position/frame）互不影响。
static var _frames_cache: Dictionary = {}

## 全体敌人共享的受击闪白材质（2026-10-20 移动端 draw call 专项）：
## 懒加载一次，所有敌种共用（shader 零 uniform，闪白走 self_modulate），跨敌种可合批。
static var _shared_hit_flash_mat: ShaderMaterial = null
const HIT_FLASH_SHADER := preload("res://assets/shaders/hit_flash.gdshader")

static func _get_shared_hit_flash_mat() -> ShaderMaterial:
	if _shared_hit_flash_mat == null:
		_shared_hit_flash_mat = ShaderMaterial.new()
		_shared_hit_flash_mat.shader = HIT_FLASH_SHADER
	return _shared_hit_flash_mat

## 释放共享帧缓存（退出时调用）。缓存是刻意常驻的，但不主动放开引用会被
## Godot 报成 "resources still in use at exit"，让退出日志一片假警报。
static func clear_frame_cache() -> void:
	_frames_cache.clear()
	_shared_hit_flash_mat = null

## 当前缓存的帧集合数量（调试/自动化验证用）
static func cache_size() -> int:
	return _frames_cache.size()

static func _cell_tex(tex: Texture2D, col: int, row: int) -> AtlasTexture:
	var at = AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(col * 192, row * 192, 192, 192)
	return at

## 取（或首次构建）某种怪共享的 SpriteFrames
static func _shared_frames(path: String, elite: bool) -> SpriteFrames:
	var key := "%s|%s" % [path, elite]
	if _frames_cache.has(key):
		return _frames_cache[key]
	var tex = load(path) as Texture2D
	if tex == null:
		return null
	var sf := SpriteFrames.new()
	for dir in RunMotion.DIR_ROW:
		var row: int = RunMotion.DIR_ROW[dir]
		sf.add_animation("idle_" + dir)
		sf.set_animation_speed("idle_" + dir, 1.0)
		sf.set_animation_loop("idle_" + dir, true)
		sf.add_frame("idle_" + dir, _cell_tex(tex, 0, row))

		sf.add_animation("run_" + dir)
		sf.set_animation_speed("run_" + dir, 10.0 if not elite else 8.5)
		sf.set_animation_loop("run_" + dir, true)
		for c in range(1, 5):
			sf.add_frame("run_" + dir, _cell_tex(tex, c, row))
	_frames_cache[key] = sf
	return sf

func _setup_frames(path: String) -> void:
	var sf := _shared_frames(path, is_elite)
	if sf == null:
		return
	anim_sprite.sprite_frames = sf
	anim_sprite.play("run_s")

## 按 facing 重建 idle/run 动画名缓存（装配完成与朝向变更时各调一次）
func _rebuild_anim_name_cache() -> void:
	_anim_idle = "idle_" + facing
	_anim_run = "run_" + facing
	_anim_has_run = anim_sprite != null and anim_sprite.sprite_frames != null and anim_sprite.sprite_frames.has_animation(_anim_run)

## 挤压与拉伸形变回弹（Squash & Stretch）——零 Tween 分配版：记录起点与时长，
## 回弹插值在 _tick_hit_fx 逐帧做（TRANS_BACK EASE_OUT 同款过冲曲线）。
## 连续命中时平滑从当前形变过渡，避免起点硬跳打断回弹视觉。
func play_squash(target: Vector2, duration: float = 0.16) -> void:
	if _squash_t > 0.0:
		# 已经在回弹形变中：从当前实时视觉姿态平滑承接，向 target 靠近
		_squash_from = juice_scale
		juice_scale = juice_scale.lerp(target, 0.7)
	else:
		juice_scale = target
		_squash_from = target
	_squash_t = maxf(duration, 0.001)
	_squash_dur = _squash_t

# ---------------- 每帧调度：移动 / 行为计时器 / 状态机推进 ----------------
## 2026-10-11 机械拆分：原 367 行上帝函数按支路切成「异常结算 / 有效移速 / 硬直计时 /
## 行为推进 / 速度解算 / 受击视觉 / 动画同步 / 接触结算」八个私有函数，零逻辑改动。
## 帧内中间量走 _pp_* 成员（帧首重写，不跨帧持有语义），跨函数不再拖一长串参数。

# —— _physics_process 帧内中间量 ——
var _pp_stun: bool = false                   ## 本帧受击硬直是否仍在
var _pp_target_vel: Vector2 = Vector2.ZERO   ## 本帧期望速度（各行为支路共同写这一个出口）

func _physics_process(delta: float) -> void:
	if GameManager.is_game_over or dying:
		return

	var player = GameManager.player
	if player == null:
		return

	# 灵兽嘲讽（2026-10-11 祭坛灵兽）：周身嘲讽圈内有友方灵兽时改追灵兽，替玩家分担火力。
	# 追击方向、扑咬/冲刺/自爆/火球的瞄准与接触结算都改吃这个目标；Boss 出招大脑仍锁玩家。
	var target: Node2D = _taunt_target(player)

	# 屏外缓存（2026-10-10 第 6 波卡顿优化，2026-10-11 加 10Hz 节流）：take_damage 里
	# 屏外只扣血跳过跳字与火花（音效/硬直/击退/闪白保留）。
	# 敌人进出屏幕是秒级事件，10Hz 判定足够；每敌错相劈开 transform 查询
	_cull_timer -= delta
	if _cull_timer <= 0.0:
		_cull_timer = CULL_INTERVAL
		_update_offscreen_cull()

	# 受击视觉衰减（零分配）：挤压回弹与闪白逐帧推进。
	# 必须放在行为支路之前 —— 冲刺/短咬等支路会提前 return，衰减不能跟着断
	_tick_hit_fx(delta)

	if _focus_hit_timer > 0.0:
		_focus_hit_timer -= delta
		if _focus_hit_timer <= 0.0:
			_focus_hit_count = 0
	if _elite_spark_cd > 0.0:
		_elite_spark_cd -= delta

	# 0. 五行元素异常状态结算（灼烧/剧毒跳伤；致死即结束本帧）
	if _tick_damage_over_time(delta):
		return

	# 有效移速：冰缓减速 × 鼓妖光环加速
	var eff_speed := _effective_speed(delta)
	# 五行异常体表粒子与灼烧/剧毒染色（屏外跳过粒子，染色照写保证回屏色温正确）
	_tick_status_fx(delta)

	# 1. 击退速度急刹与受击硬直定身（空洞骑士/死亡细胞风格：0帧瞬发冲量 → ~0.11s急刹刹停 → 原地僵直定身）
	_pp_stun = _tick_hit_stun(delta)
	# 硬直打断火球蓄力：起手是承诺段的前摇，被钉着还发弹，「定身」成空话（同短咬/长扑的起手纪律）
	if _pp_stun:
		_cancel_bolt_windup()

	# 2. 追击目标（平滑加速度 + 贴身防旋转抽搐）：期望速度与各行为支路推进
	var to_player: Vector2 = target.global_position - global_position
	var dist_sq: float = to_player.length_squared()
	var dir: Vector2 = to_player.normalized() if dist_sq > 0.0001 else Vector2.ZERO
	# 引入轻微加减速平滑，消除突然转向时的身躯瞬间硬切；
	# 受击硬直（hit-stun）期间主动追击速度归零，位移纯由击退速度主导，呈现土豆兄弟式的受击定身与推开感
	_pp_target_vel = Vector2.ZERO if _pp_stun else (dir * eff_speed)
	if _tick_behaviors(delta, target, dir, dist_sq, eff_speed):
		return

	# 位移解算（冲刺锁定段不插值）+ 界碑拦阻
	_resolve_velocity(delta)
	var pos_before_move: Vector2 = global_position
	move_and_slide()
	var lim: float = GameManager.MAP_HALF_EXTENT - 20.0
	global_position = global_position.clamp(Vector2(-lim, -lim), Vector2(lim, lim))
	# 触界时清零越界速度分量，避免原地满速跑步动画（只清越界方向，保留沿墙切向）
	if global_position.x >= lim and velocity.x > 0.0:
		velocity.x = 0.0
	elif global_position.x <= -lim and velocity.x < 0.0:
		velocity.x = 0.0
	if global_position.y >= lim and velocity.y > 0.0:
		velocity.y = 0.0
	elif global_position.y <= -lim and velocity.y < 0.0:
		velocity.y = 0.0

	_tick_hit_visuals(delta)
	# 屏外敌人跳过整套朝向/动画/步态视觉逻辑（2026-10-17 性能专项）：
	# 位置与行为每物理 tick 照常推进（回屏无缝），只是不再做朝向计算、RunMotion 步态
	# 形变与程序化视图属性写——屏外这些状态没人看。HollowKnightEnemyRenderer 已在
	# _process 屏外跳过重绘，这里把省的从「渲染」升级为「全部视觉逻辑」。
	# _offscreen 是 10Hz 采样（进出屏秒级事件），回屏首拍最多滞后 0.1s 补一次形变，无感。
	# 例外：受击衰减（_tick_hit_fx 已在上方跑）需要连续性，但那是独立计时推进不依赖本函数。
	if not _offscreen:
		_update_facing_and_anim(delta, dir, dist_sq)
	_resolve_contact_damage(target, pos_before_move)

## 嘲讽目标选择（2026-10-11 祭坛灵兽）：嘲讽圈内有灵兽则追最近的灵兽，否则维持追玩家。
## 灵兽最多 3 只（三座祭坛各召唤一只），全表扫描开销可忽略。
func _taunt_target(player: Node2D) -> Node2D:
	var best: Node2D = player
	var best_sq: float = GameBalance.SPIRIT_BEAST_TAUNT_RADIUS * GameBalance.SPIRIT_BEAST_TAUNT_RADIUS
	for ally in GameManager.live_allies:
		if ally == null or not is_instance_valid(ally):
			continue
		var d: float = global_position.distance_squared_to(ally.global_position)
		if d < best_sq:
			best_sq = d
			best = ally
	return best

func _update_offscreen_cull() -> void:
	var vp := get_viewport()
	if vp != null:
		var sp: Vector2 = vp.get_canvas_transform() * global_position
		var lim: Vector2 = vp.get_visible_rect().size + Vector2.ONE * CULL_MARGIN
		_offscreen = sp.x < -CULL_MARGIN or sp.y < -CULL_MARGIN or sp.x > lim.x or sp.y > lim.y

## 灼烧/剧毒跳伤结算；致死（dying）返回 true，调用方立即结束本帧
func _tick_damage_over_time(delta: float) -> bool:
	if burn_timer > 0.0:
		burn_timer -= delta
		_burn_tick += delta
		if _burn_tick >= GameBalance.DOT_TICK_INTERVAL:
			_burn_tick = 0.0
			var b_dmg := GameBalance.burn_tick_damage(burn_dps, GameManager.elemental_damage, GameManager.synergy_burn_mult)
			take_damage(b_dmg, Vector2.ZERO, false, true)
			if dying:
				return true
		if burn_timer <= 0.0:
			burn_dps = 0.0
	if poison_timer > 0.0:
		poison_timer -= delta
		_poison_tick += delta
		if _poison_tick >= GameBalance.DOT_TICK_INTERVAL:
			_poison_tick = 0.0
			var p_dmg := GameBalance.poison_tick_damage(poison_dps, GameManager.elemental_damage)
			take_damage(p_dmg, Vector2.ZERO, false, true)
			if dying:
				return true
		if poison_timer <= 0.0:
			poison_dps = 0.0
	return false

## 本体常驻染色（冰缓结束恢复用；Boss 阶段染色由子类覆写，防止被异常状态洗成白色）
func _base_tint() -> Color:
	return Color.WHITE

## 五行异常体表视觉：低频续发体表粒子 + 灼烧/剧毒本体染色。
## 染色优先级 冰缓（_effective_speed 链路）> 灼烧 > 剧毒 > 本体色；
## 引信/蓄力独占 modulate 时整段让位，不写不读。
func _tick_status_fx(delta: float) -> void:
	var burning := burn_timer > 0.0
	var poisoned := poison_timer > 0.0
	var chilled := chill_timer > 0.0
	# 染色（灼烧/剧毒；冰缓在 _effective_speed 既有链路，此处不覆盖）；
	# 异常消退当帧把本体色归还（只认自己写过的两档色，避免误洗引信/蓄力色）
	if not chilled and _fuse < 0.0 and _bolt_windup_t < 0.0:
		if burning:
			anim_sprite.modulate = STATUS_TINT_BURN
		elif poisoned:
			anim_sprite.modulate = STATUS_TINT_POISON
		elif anim_sprite.modulate == STATUS_TINT_BURN or anim_sprite.modulate == STATUS_TINT_POISON:
			anim_sprite.modulate = _base_tint()
	if not burning and not poisoned and not chilled:
		return
	# 体表粒子续发（屏外不发，帧闸在 FxParticlePool 侧兜底）
	if _offscreen:
		return
	_status_fx_cd -= delta
	if _status_fx_cd > 0.0:
		return
	_status_fx_cd = STATUS_FX_INTERVAL
	var fx_pos := global_position + Vector2(0.0, -10.0)
	if burning:
		FxParticlePool.burst(FxParticlePool.BURN_AURA, fx_pos, "fire")
	if poisoned:
		FxParticlePool.burst(FxParticlePool.POISON_AURA, fx_pos, "poison")
	if chilled:
		FxParticlePool.burst(FxParticlePool.CHILL_AURA, fx_pos, "water")

## 有效移速 = 基础 ×（1-冰缓）× 光环；顺带处理冰缓染色与光环过期待遇失效
func _effective_speed(delta: float) -> float:
	var eff_speed: float = move_speed
	if chill_timer > 0.0:
		chill_timer -= delta
		eff_speed = move_speed * (1.0 - chill_slow)
		if _fuse < 0.0:
			# 冰蓝色温改为提亮（旧版压暗红绿通道，深蓝地图上怪物直接隐形）
			anim_sprite.modulate = Color(1.15, 1.35, 1.7)
		if chill_timer <= 0.0:
			chill_slow = 0.0
			if _fuse < 0.0:
				anim_sprite.modulate = _base_tint()
	# 鼓妖光环：被覆盖期间加速，过期待遇自动失效（脚下琥珀标记同步熄灭）
	if _aura_speed_mult != 1.0 and Time.get_ticks_msec() > _aura_until_ms:
		_aura_speed_mult = 1.0
		_aura_shown = false
		if procedural_view != null:
			procedural_view.aura_level = 0.0
	return eff_speed * _aura_speed_mult

## 受击卡肉/硬直计时与击退急刹擦地扬尘；返回硬直是否仍在
func _tick_hit_stun(delta: float) -> bool:
	var is_in_hit_freeze := _hit_freeze_timer > 0.0
	if is_in_hit_freeze:
		_hit_freeze_timer -= delta
	var is_in_hit_stun := hit_stun_timer > 0.0
	if is_in_hit_stun:
		hit_stun_timer -= delta

		# 击退急刹擦地烟尘（节流优化：仅在刚被击退的首段低频触发，防怪群受击时地面持续喷白尘）
		if is_in_hit_stun and knockback_velocity.length_squared() > 14400.0:
			_skid_dust_timer -= delta
			if _skid_dust_timer <= 0.0:
				_skid_dust_timer = 0.12
				JuiceEffect.spawn_step_dust(get_parent(), global_position + Vector2(0, 12), knockback_velocity)
	return is_in_hit_stun

## 行为支路推进：远程风筝 / 扑咬状态机 / 自爆引信 / 火球 / 产卵 / 光环 / 闪现。
## 期望速度统一写 _pp_target_vel；返回 true = 自爆已结算（_explode 内部已走死亡流），调用方立即结束本帧。
func _tick_behaviors(delta: float, player: Node2D, dir: Vector2, dist_sq: float, eff_speed: float) -> bool:
	# 金蟾系：恒背离玩家逃窜（土豆兄弟 Looter：击杀爆金币的限时宝藏怪）
	# 软墙绕场滑行（2026-10-15 行为优化）：旧版只「清零朝墙外分量改沿墙滑行」，滑行方向
	# 每帧按玩家相对位置重算、恰在墙中线随位置翻号 ⇒ 玩家一偏离场心，金蟾被径向逃推一路
	# 楔进角落趴窝（角落死锁分支要两轴同时触界才救，太晚；墙中段翻向还会抖振失速）。
	# 现在贴墙瞬间把滑行方向锁进 _flee_slide（选「远离近端墙角」的环流侧），沿墙期间保持
	# 锁存不随玩家翻向；被推抵相邻墙带时原地转 90° 接下一面墙（绕场环流）；只有被击退
	# 脱离墙带才释放回径向逃离。观感：贴边界带绕场流窜，不进角、不贴墙原地抽搐。
	if always_flee and not _pp_stun:
		var wall_lim: float = GameManager.MAP_HALF_EXTENT - 20.0
		var t_edge: float = wall_lim - FLEE_WALL_BAND
		var flee_dir := -dir
		if _flee_slide != Vector2.ZERO:
			# 环流保持：仍贴着约束它的那面墙就照锁存方向流；抵上相邻墙带即转 90° 接下一面
			if _flee_slide.x == 0.0:
				if absf(global_position.x) <= t_edge:
					_flee_slide = Vector2.ZERO
				elif absf(global_position.y) >= t_edge and signf(_flee_slide.y) == signf(global_position.y):
					_flee_slide = Vector2(-signf(global_position.x), 0.0)
			else:
				if absf(global_position.y) <= t_edge:
					_flee_slide = Vector2.ZERO
				elif absf(global_position.x) >= t_edge and signf(_flee_slide.x) == signf(global_position.x):
					_flee_slide = Vector2(0.0, -signf(global_position.y))
			if _flee_slide != Vector2.ZERO:
				flee_dir = _flee_slide
		if _flee_slide == Vector2.ZERO and flee_dir.length_squared() > 0.0001:
			# 径向逃离触墙：锁存为「远离近端墙角」的环流方向（贴墙恰在中线上的罕见退化取顺时针）
			if flee_dir.x > 0.0 and global_position.x > t_edge:
				_flee_slide = Vector2(0.0, -signf(global_position.y) if global_position.y != 0.0 else 1.0)
			elif flee_dir.x < 0.0 and global_position.x < -t_edge:
				_flee_slide = Vector2(0.0, -signf(global_position.y) if global_position.y != 0.0 else 1.0)
			elif flee_dir.y > 0.0 and global_position.y > t_edge:
				_flee_slide = Vector2(-signf(global_position.x) if global_position.x != 0.0 else 1.0, 0.0)
			elif flee_dir.y < 0.0 and global_position.y < -t_edge:
				_flee_slide = Vector2(-signf(global_position.x) if global_position.x != 0.0 else 1.0, 0.0)
			if _flee_slide != Vector2.ZERO:
				flee_dir = _flee_slide
		if flee_dir.length_squared() < 0.0001:
			# 退化兜底（玩家与金蟾重合等罕见情形）：朝场心走，绝不原地钉死
			flee_dir = (-global_position).normalized() if global_position.length_squared() > 0.0001 else Vector2.UP
		_pp_target_vel = flee_dir.normalized() * eff_speed

	# 远程怪：保持距离，近了退、远了进、合适距离环绕游走
	if not always_flee and not _pp_stun and preferred_range > 0.0:
		var dist := sqrt(dist_sq)
		if dist < preferred_range - 30.0:
			_pp_target_vel = -dir * eff_speed * 0.8
		elif dist <= preferred_range + 30.0:
			_pp_target_vel = Vector2(-dir.y, dir.x) * eff_speed * 0.5

	# 妖狼系长扑（移动出口 _pp_target_vel）：
	#   跑道够（charge_min_range ~ charge_max_range）→ 站桩预警 → 直线冲刺 → 收势（落空则罚站）
	# 长扑的三件事必须同源，都取自 GameBalance.charge_reach：预警带长度、真实位移、扫掠判定。
	# 冲刺/收势两段自己把 velocity 写死（下面 charge_locked 那一段因此跳过吸附插值）。
	if charge_interval > 0.0:
		_charge_timer -= delta
		var min_sq: float = charge_min_range * charge_min_range
		var max_sq: float = charge_max_range * charge_max_range

		# 预警阶段：原地不动，画预警线
		if _charge_windup > 0.0:
			_charge_windup -= delta
			_pp_target_vel = Vector2.ZERO
			_update_charge_warning(player)
			if _charge_windup <= 0.0:
				_start_charge(_charge_aim_dir(player, dir))

		# 冲刺阶段：起步即满速，位移由锁定段直接写进 velocity（同 Player 缩地成寸的口径）。
		# 旧写法只交一个 target_vel，让下方 900 px/s² 的吸附插值从站桩预警的 0 速去爬峰速 384
		# ⇒ 0.43s 才够到速度（锁定时长一半耗在起步上），冲刺结束后还留一段朝玩家拐弯的滑行尾巴
		# ⇒ 「画的线」「撞的段」「判的范围」是三套数，玩家只要动一下就永远碰不到它
		elif _charge_active > 0.0:
			_charge_active -= delta
			velocity = _charge_dir * move_speed * charge_speed_mul
			_pp_target_vel = velocity
			knockback_velocity = Vector2.ZERO
			_clear_charge_warning()
			if _charge_active <= 0.0:
				_charge_brake = charge_brake_time

		# 收势刹车：峰速线性刹到站定。这一段也是承诺出去的位移，预警线按 GameBalance.charge_reach 已把它算进线长
		elif _charge_brake > 0.0:
			_charge_brake -= delta
			var brake_k: float = maxf(_charge_brake / maxf(charge_brake_time, 0.0001), 0.0)
			velocity = _charge_dir * (move_speed * charge_speed_mul) * brake_k
			_pp_target_vel = velocity
			knockback_velocity = Vector2.ZERO
			if _charge_brake <= 0.0:
				_settle_charge_recovery()

		# 落空罚站：冲空了就是白给，玩家看得见「它过去了、站着不动」⇒ 躲开这条路才有奖励，而不只是没被打到
		elif _charge_stagger > 0.0:
			_charge_stagger -= delta
			_pp_target_vel = Vector2.ZERO

		# 链冲段间短预警（变异烈雷兽）：上一段收势后不罚站，短暂停顿再起手下一冲。
		# 每段仍有完整预警线可读，玩家能连续侧移躲完整轮；链尾才吃落空罚站。
		elif _chain_t >= 0.0:
			_chain_t -= delta
			_pp_target_vel = Vector2.ZERO
			if _chain_t <= 0.0:
				_chain_t = -1.0
				_charge_windup = charge_windup_time * chain_windup_mult
				_charge_windup_total = _charge_windup
				play_squash(Vector2(0.82, 1.2), 0.2)
				AudioManager.play_sfx("enemy_fuse", 0.35, GameManager.rng.randf_range(1.18, 1.32))

		# 空闲：冷却到 + 跑道够 → 长扑预警（硬直中不起手：预警是冲刺的蓄力段，
		# 被钉着还起手，后续 _start_charge 会从硬直滑行分支夺走位移，「定身」成空话）
		# 雷环前摇期间不抢跑：两个前摇同时开会让「站定提亮」的读法互相打断。
		elif charge_interval > 0.0 and _charge_timer <= 0.0 and dist_sq > min_sq and dist_sq < max_sq and not _pp_stun and _ring_bolt_windup_t < 0.0:
			_charge_timer = charge_interval
			_charge_windup = charge_windup_time
			_charge_windup_total = _charge_windup
			_chain_left = maxi(chain_charges - 1, 0)
			# 起手反馈：下蹲蓄势 + 低音量哨声（全预警体系里原本唯一「静默起手」的，现在齐了）
			play_squash(Vector2(0.82, 1.2), 0.24)
			AudioManager.play_sfx("enemy_fuse", 0.35, GameManager.rng.randf_range(1.18, 1.32))

	# 丹爆傀儡：贴近点燃引信，原地颤抖后自爆
	if explode_radius > 0.0:
		if _fuse < 0.0:
			if dist_sq < 1600.0:
				_fuse = EXPLODE_FUSE
				_hit_jiggle_offset = Vector2.ZERO  # 引信颤抖要独占位移抖动，受击微反冲残量先归位
				anim_sprite.modulate = Color(2.2, 0.9, 0.6)
				play_squash(Vector2(1.2, 0.82), 0.3)
				AudioManager.play_sfx("enemy_fuse", 1.0)   ## 引信是递进爆点的倒计时，不是灵宝触体的钟
				_ignite_explode_ring()
		else:
			_fuse -= delta
			_pp_target_vel = Vector2.ZERO
			if _explode_ring != null:
				_explode_ring.progress = 1.0 - _fuse / EXPLODE_FUSE
			# 引信颤抖：旧写法只抖 anim_sprite，程序化白模下它是隐藏节点（视图藏在 procedural_view），
			# 玩家看到的白模一动不动。两套载体同拍抖，哪套在用都读得到。
			var fuse_jitter := GameManager.rng.randf_range(-1.6, 1.6)
			anim_sprite.position.x = fuse_jitter
			if procedural_view != null:
				procedural_view.position.x = fuse_jitter
			if _fuse <= 0.0:
				anim_sprite.position.x = 0.0
				if procedural_view != null:
					procedural_view.position.x = 0.0
				_explode(player)
				return true

	# 御剑邪修：保持距离的同时周期性发射火球（先蓄力预告，蓄力满才出手）
	if bolt_interval > 0.0 and _fuse < 0.0:
		if _bolt_windup_t >= 0.0:
			# 蓄力段：站定 + 本体提亮变色，出手方向每帧跟玩家（只作读法，出手那帧才锁死）
			_pp_target_vel = Vector2.ZERO
			_bolt_windup_dir = (player.global_position - global_position).normalized()
			_tick_bolt_windup(delta)
			if _bolt_windup_t <= 0.0:
				_fire_bolt(player)
		else:
			_bolt_timer -= delta
			if _bolt_timer <= 0.0 and dist_sq < 396900.0 and not _pp_stun:
				_bolt_timer = bolt_interval
				_start_bolt_windup()

	# 蛛母系：周期性产卵（受同屏上限约束，不冲破刷怪口的上限）
	if spawn_minion_interval > 0.0 and minion_scene != null and _fuse < 0.0:
		_minion_timer -= delta
		if _minion_timer <= 0.0:
			_minion_timer = spawn_minion_interval
			if GameManager.enemy_count < GameBalance.ZHUMU_MINION_CAP:
				_spawn_minion()

	# 鼓妖光环：每 0.25s 给范围内同伴刷新一次加速
	if buff_radius > 0.0:
		_buff_timer -= delta
		if _buff_timer <= 0.0:
			_buff_timer = 0.25
			_pulse_buff_aura()

	# 影魅系：周期性闪现到玩家侧翼（自爆引信点燃时不闪现，避免爆点漂移）
	if teleport_interval > 0.0 and _fuse < 0.0:
		_teleport_timer -= delta
		if _teleport_timer <= 0.0:
			_teleport_timer = teleport_interval
			_teleport_near_player(player)

	# 铁甲魔傀·震地：预警圈「填满式」倒计时 → 结算（与 Boss 震地同一套视觉语言）
	if slam_interval > 0.0 and _fuse < 0.0:
		if _elite_slam_windup_t >= 0.0:
			_elite_slam_windup_t -= delta
			_pp_target_vel = Vector2.ZERO
			if _elite_slam_ring != null:
				_elite_slam_ring.progress = 1.0 - _elite_slam_windup_t / maxf(slam_windup, 0.001)
			if _elite_slam_windup_t <= 0.0:
				_resolve_elite_slam(player)
		else:
			_elite_slam_timer -= delta
			# 与落石互斥：同一时刻只亮一种预警，避免双圈叠读
			if _elite_slam_timer <= 0.0 and _rock_windup_t < 0.0 and dist_sq < slam_radius * slam_radius * 2.25:
				_elite_slam_timer = slam_interval
				_start_elite_slam()
	# 变异震地余波独立推进：预警段被硬直/其他支路打断也要把已承诺的段数结完
	_tick_slam_echo(delta, player)

	# 铁甲魔傀·落石轰炸：起手锁多个落点 → 每个落点亮填满式预警圈 → 逐个结算。
	# 首点锁玩家预判位（rock_lead），其余绕首点按 rock_spread 散布 —— 克制原地站桩与匀速跑位。
	if rock_interval > 0.0 and _fuse < 0.0:
		if _rock_windup_t >= 0.0:
			_rock_windup_t -= delta
			_pp_target_vel = Vector2.ZERO
			var rock_progress: float = 1.0 - _rock_windup_t / maxf(rock_windup, 0.001)
			for ring in _rock_rings:
				if ring != null and is_instance_valid(ring):
					ring.progress = rock_progress
			if _rock_windup_t <= 0.0:
				_resolve_rock_barrage(player)
		else:
			_rock_timer -= delta
			# 与冲刺/震地互斥：冲刺锁定段不砸石（落点追不上自己），震地预警中不叠第二种圈
			if _rock_timer <= 0.0 and dist_sq < 640000.0 and not _pp_stun \
					and _charge_windup < 0.0 and _charge_active <= 0.0 and _charge_brake <= 0.0 \
					and _elite_slam_windup_t < 0.0:
				_rock_timer = rock_interval
				_start_rock_barrage(player)

	# 赤雷兽·雷环齐射：短前摇站定提亮 → 全向均布弧线雷弹（旋臂压迫走位）
	if ring_bolt_interval > 0.0 and _fuse < 0.0:
		if _ring_bolt_windup_t >= 0.0:
			_ring_bolt_windup_t -= delta
			_pp_target_vel = Vector2.ZERO
			if procedural_view != null:
				procedural_view.special_state = clampf(1.0 - _ring_bolt_windup_t / maxf(ring_bolt_windup, 0.001), 0.0, 1.0)
			if _ring_bolt_windup_t <= 0.0:
				_fire_ring_bolts()
		else:
			_ring_bolt_timer -= delta
			# 与冲刺/落石互斥：冲刺锁定段或落石预警中不放环（冲刺中站定开环会撕裂位移）
			if _ring_bolt_timer <= 0.0 and dist_sq < 640000.0 and not _pp_stun \
					and _charge_windup < 0.0 and _charge_active <= 0.0 and _charge_brake <= 0.0 \
					and _rock_windup_t < 0.0:
				_ring_bolt_timer = ring_bolt_interval
				_start_ring_bolt_cast()

	# 剑煞邪修·雷剑域：在玩家脚下铺持续伤害领域（复用毒潭骨架，染血煞色）
	if field_interval > 0.0 and _fuse < 0.0:
		if _field_windup_t >= 0.0:
			_field_windup_t -= delta
			_pp_target_vel = Vector2.ZERO
			if _field_ring != null:
				_field_ring.progress = 1.0 - _field_windup_t / maxf(field_windup, 0.001)
				_field_ring.global_position = _field_target
			if _field_windup_t <= 0.0:
				_drop_field()
		else:
			_field_timer -= delta
			if _field_timer <= 0.0 and dist_sq < 640000.0 and not _pp_stun:
				_field_timer = field_interval
				_field_target = player.global_position
				_start_field_cast()

	# 剑煞邪修·瞬身回斩（变异专属）：闪现侧翼 + 立刻扇形剑气反打
	if blink_strike_interval > 0.0 and _fuse < 0.0:
		_blink_strike_timer -= delta
		if _blink_strike_timer <= 0.0 and not _pp_stun:
			_blink_strike_timer = blink_strike_interval
			_blink_strike(player)

	# 灵医系：周期性治疗范围内同伴（土豆兄弟 Healer：制造优先击杀目标）
	if heal_interval > 0.0 and _fuse < 0.0:
		_heal_timer -= delta
		if _heal_timer <= 0.0:
			_heal_timer = heal_interval
			_pulse_heal()

	# 毒妖系：周期性朝玩家所在地投一片毒潭（持续伤害区域，进入即按周期掉血）
	if poison_interval > 0.0 and _fuse < 0.0:
		if _poison_windup_t >= 0.0:
			# 预警阶段：原地不动，落点圈填满 = 毒潭落下。
			# 落点在起手那一帧锁死、之后不追踪玩家 —— 0.6s 还追踪的话玩家永远躲不开（同短咬口径）
			_poison_windup_t -= delta
			_pp_target_vel = Vector2.ZERO
			if _poison_ring != null:
				_poison_ring.progress = 1.0 - _poison_windup_t / maxf(poison_windup, 0.001)
				# 预警圈每帧钉回落点：预警期间被击退/位移也不把圈带跑（落点早已锁死）
				_poison_ring.global_position = _poison_target
			if _poison_windup_t <= 0.0:
				_drop_poison()
		else:
			_poison_timer -= delta
			if _poison_timer <= 0.0 and dist_sq < poison_radius * poison_radius * 6.25:
				_poison_timer = poison_interval
				_poison_target = player.global_position
				_start_poison_cast()

	return false

## 速度解算：冲刺/收势锁定段由状态机逐帧写死（不交给插值、不被硬直夺走）；
## 受击卡肉定格期完全静止且保持击退冲量；硬直期间位移纯由击退主导并快速衰减；平时吸附插值追击
func _resolve_velocity(delta: float) -> void:
	var charge_locked := _charge_active > 0.0 or _charge_brake > 0.0
	if charge_locked:
		# velocity 已由状态机逐帧写死 ⇒ 既不交给吸附插值去改，
		# 也不被受击硬直夺走（commit-through，与旧写法「硬直期间冲刺照冲」同一条口径）
		pass
	elif _hit_freeze_timer > 0.0:
		# 受击卡肉定格（空洞骑士/死亡细胞风格）：冻结位移吸附在刀尖，
		# 期间速度归零且不衰减 knockback_velocity，定格计时结束后才释放并衰减击退冲量
		velocity = Vector2.ZERO
	elif _pp_stun:
		velocity = knockback_velocity
		# 衰减在赋予 velocity 之后执行：第 0 帧吃满初速，并在 ~0.11s 内快速到位并完全刹停
		var decay_rate: float = GameBalance.KNOCKBACK_DECAY_STUN
		if knockback_velocity.length_squared() > 16.0:
			knockback_velocity = knockback_velocity.lerp(Vector2.ZERO, minf(delta * decay_rate, 1.0))
		else:
			knockback_velocity = Vector2.ZERO
	else:
		velocity = velocity.move_toward(_pp_target_vel, 900.0 * delta)
		# 硬直结束时残余击退彻底清零，杜绝边追击边滑步的打冰球现象
		knockback_velocity = Vector2.ZERO

## 受击视觉零分配衰减（2026-10-11）：挤压回弹（TRANS_BACK EASE_OUT 同款过冲曲线）
## 与闪白衰减逐帧推进，替代原先每次受击 create_tween ×2 的分配热点
func _tick_hit_fx(delta: float) -> void:
	if _squash_t > 0.0:
		_squash_t = maxf(0.0, _squash_t - delta)
		var t := 1.0 - _squash_t / _squash_dur
		var c1 := 1.70158
		var e := 1.0 + (c1 + 1) * pow(t - 1.0, 3.0) + c1 * pow(t - 1.0, 2.0)
		juice_scale = _squash_from.lerp(Vector2.ONE, clampf(e, 0.0, 1.0))
	if _flash_t > 0.0:
		_flash_t = maxf(0.0, _flash_t - delta)
		_write_flash_channel(clampf(_flash_t / _flash_down_dur, 0.0, 1.0))
	if _flash_swap_t > 0.0:
		_flash_swap_t -= delta
		if _flash_swap_t <= 0.0:
			_flash_col = FLASH_COL_SWAP

## 受击视觉：微反冲回弹（非自爆抖动期间生效，同步作用于精灵与程序化矢量视图）与后仰倾角衰减
func _tick_hit_visuals(delta: float) -> void:
	if _hit_jiggle_offset.length_squared() > 0.01:
		_hit_jiggle_offset = _hit_jiggle_offset.lerp(Vector2.ZERO, minf(delta * 24.0, 1.0))
	else:
		_hit_jiggle_offset = Vector2.ZERO
	if _fuse < 0.0:
		anim_sprite.position = _hit_jiggle_offset
		if procedural_view != null:
			procedural_view.position = anim_sprite.position

	# 受创后仰倾角衰减
	if absf(_hit_tilt) > 0.005:
		_hit_tilt = lerpf(_hit_tilt, 0.0, minf(delta * 14.0, 1.0))
	else:
		_hit_tilt = 0.0

## 朝向迟滞 + 三档步态动画（步态腿帧 / 悬浮 / 蠕动）+ 程序化矢量视图同步
func _update_facing_and_anim(delta: float, dir: Vector2, dist_sq: float) -> void:
	# 3. Sprite 方向 & 动画（带迟滞滤波 + 贴近锁定 + 移速步频自适应）
	# 当敌人与玩家极度贴近（小于 18px）时锁定原有朝向，避免围绕玩家中心旋转时的抽风风扇效应
	if dist_sq > 324.0 and dir.length_squared() > 0.01:
		var face: Array = RunMotion.facing_stable(dir, facing, anim_sprite.flip_h, 32.0)
		if face[0] != "":
			facing = face[0]
			anim_sprite.flip_h = face[1]

	var current_base := anim_base_scale * juice_scale
	var current_speed := velocity.length()
	var speed_ratio: float = (current_speed / move_speed) if move_speed > 0.0 else 1.0
	# 受击硬直期间强制停步：不踏步、不迈腿；正常移动且实际位移足够才播跑步动画
	var is_moving := (not _pp_stun) and current_speed > maxf(20.0, move_speed * 0.2)

	if locomotion_mode == "hover":
		# 悬浮：不切腿帧（单姿势图集），浮沉/侧倾/纵向意图由程序驱动。
		# 侧倾喂**实际位移方向**而不是「面向玩家」的方向：邪修这类带 preferred_range 的
		# 远程怪会后退放风筝，用面向方向 bank 的话，逼近与后撤倾同一个方向，玩家分不清
		#（2026-10-09 用户现场：「踩着黑雾的为什么背对着走向我」——它其实在往后撤）。
		# advance = 位移与面向的夹角余弦：+1 压过来 / -1 后撤 / ≈0 环绕侧滑。
		# 受击定身期间归零：那一拍已有 play_squash + 微反冲在发反馈，不叠第二处。
		var vel_dir := Vector2.ZERO
		if is_moving and current_speed > 0.01:
			vel_dir = velocity / current_speed
		var advance := 0.0
		if not _pp_stun:
			advance = vel_dir.dot(dir)
		RunMotion.select_anim(anim_sprite, _anim_idle, false)
		RunMotion.apply_hover(_run_state, anim_sprite, current_base, is_moving, vel_dir, delta, speed_ratio, shadow_sprite, advance)
	elif locomotion_mode == "slither":
		# 蠕动：贴地行进波（scale 伸缩），无悬浮无前倾
		RunMotion.select_anim(anim_sprite, _anim_idle, false)
		RunMotion.apply_slither(_run_state, anim_sprite, current_base, is_moving, delta, speed_ratio, shadow_sprite)
	else:
		# 步态腿帧：有图集才切腿帧；程序化敌种没有帧集，但形变链路照走
		#（RunMotion.apply 对 null 帧集内部按 4 帧 / 10fps 默认推进步态相位）
		if _anim_has_run and is_moving:
			RunMotion.select_anim(anim_sprite, _anim_run, true)
			RunMotion.apply(_run_state, anim_sprite, current_base, true, anim_sprite.flip_h, absf(dir.x), delta, speed_ratio, 0.0, shadow_sprite)
		elif _anim_has_run:
			RunMotion.select_anim(anim_sprite, _anim_idle, false)
			RunMotion.apply(_run_state, anim_sprite, current_base, false, anim_sprite.flip_h, 0.0, delta, 1.0, 0.0, shadow_sprite)
		elif is_moving:
			RunMotion.apply(_run_state, anim_sprite, current_base, true, anim_sprite.flip_h, absf(dir.x), delta, speed_ratio, 0.0, shadow_sprite)
		else:
			RunMotion.apply(_run_state, anim_sprite, current_base, false, anim_sprite.flip_h, 0.0, delta)

	# 3.5 同步程序化矢量视图
	if procedural_view != null:
		procedural_view.facing = facing
		procedural_view.flip_h = anim_sprite.flip_h
		procedural_view.scale = anim_sprite.scale
		procedural_view.modulate = anim_sprite.modulate
		procedural_view.is_moving = is_moving
		procedural_view.speed_ratio = speed_ratio
		if _pp_stun:
			procedural_view.bank_angle = _hit_tilt
		elif locomotion_mode == "hover":
			var vel_dir := Vector2.ZERO
			if is_moving and current_speed > 0.01:
				vel_dir = velocity / current_speed
			procedural_view.bank_angle = deg_to_rad(vel_dir.x * 6.5)
			procedural_view.advance = vel_dir.dot(dir)
			if _bolt_windup_t >= 0.0:
				procedural_view.aim_dir = _bolt_windup_dir
			elif dir.length_squared() > 0.01:
				procedural_view.aim_dir = dir
			else:
				procedural_view.aim_dir = Vector2.ZERO
		# 步态相位：仅移动时按 speed_ratio 推进（蠕动波频更高），渲染器摆翼/蠕波与位移同相
		if is_moving:
			_gait_phase += delta * speed_ratio * (GAIT_FREQ_SLITHER if locomotion_mode == "slither" else GAIT_FREQ_HOVER)
		procedural_view.gait_phase = _gait_phase
		# 蓄力/前摇进度同步（全运动模式通用，0→1 填满即出手；火球蓄力的真话源在 _tick_bolt_windup，这里不覆盖）
		if _fuse >= 0.0:
			procedural_view.special_state = 1.0
		elif _charge_windup >= 0.0:
			procedural_view.special_state = 1.0 - _charge_windup / maxf(_charge_windup_total, 0.001)
		elif _bolt_windup_t >= 0.0:
			pass
		elif _elite_slam_windup_t >= 0.0:
			procedural_view.special_state = 1.0 - _elite_slam_windup_t / maxf(slam_windup, 0.001)
		elif _poison_windup_t >= 0.0:
			procedural_view.special_state = 1.0 - _poison_windup_t / maxf(poison_windup, 0.001)
		else:
			procedural_view.special_state = 0.0

## 冲刺走廊扫掠结算 + 追击目标接触伤害判定（石岳反震只认玩家，灵兽无反震）
func _resolve_contact_damage(target: Node2D, pos_before_move: Vector2) -> void:
	# 3.6 冲刺走廊扫掠结算：判定走的是「狼身这一帧扫过的那一段」，独立于本体碰撞。
	# 旧写法长扑只有下面那条身位滑碰（狼 19.5 + 玩家 14 = 33.5px）这一个出口，
	# 而预警 0.8s 够玩家横移 168px ⇒ 只要动一下就必然躲开，整个技能形同虚设
	#（2026-10-10 用户现场：「根本冲刺不到我」）。扫掠判定保证冲刺走廊覆盖。
	# 伤害只走目标自己的 take_damage 这一个口子：玩家侧的无敌帧/闪避/护甲/受创反馈全复用，
	# 不在这里发第二次反馈；一个 flag 钉死「一次冲刺只碾一下」。
	var charge_locked := _charge_active > 0.0 or _charge_brake > 0.0
	if charge_locked and not _charge_hit:
		var closest: Vector2 = GameBalance.seg_closest_point(pos_before_move, global_position, target.global_position)
		if closest.distance_to(target.global_position) <= charge_hit_radius:
			_charge_hit = true
			if target is Player:
				var hp_before_charge: float = target.current_health
				target.take_damage(contact_damage * charge_damage_mul, global_position)
				# 石岳/玄武反震：与接触伤害同一个口径，实际被打中才反弹
				var eff_thorns: float = GameManager.get_effective_thorns()
				if eff_thorns > 0.0 and target.current_health < hp_before_charge:
					take_damage(contact_damage * eff_thorns, Vector2.ZERO, false)
			elif target.has_method("take_damage"):
				target.take_damage(contact_damage * charge_damage_mul)

	# 4. 接触伤害判定：撞到谁咬谁（玩家走无敌帧/反震那套，灵兽走自己的受击无敌帧）
	# thorns 读侧备忘（2026-10-17 性能专项）：站定护甲钩子走 item_hook_sum 缓存，但接触结算
	# 每碰撞体都查一遍仍属重复读——同一物理帧多敌贴身时（群怪围玩家）每敌一次 Dictionary
	# 链。挪到循环外读一次（站定态 60Hz 内不会变，失效点在 add_item/sell_item）。
	var col_count := get_slide_collision_count()
	if col_count > 0:
		var thorns_cache: float = -1.0   # 懒读：首个命中玩家的碰撞体才拉一次
		for i in range(col_count):
			var col = get_slide_collision(i)
			var collider = col.get_collider()
			if collider is Player:
				var hp_before: float = collider.current_health
				collider.take_damage(contact_damage, global_position)
				# 石岳/玄武反震：实际被打中才反弹（闪避/无敌帧不触发）
				if collider.current_health < hp_before:
					if thorns_cache < 0.0:
						thorns_cache = GameManager.get_effective_thorns()
					if thorns_cache > 0.0:
						take_damage(contact_damage * thorns_cache, Vector2.ZERO, false)
			elif collider != null and collider.is_in_group("allies") and collider.has_method("take_damage"):
				collider.take_damage(contact_damage)

# ---------------- 受击结算 / 硬直 / 击退 / 掉落 ----------------
func take_damage(amount: float, knockback: Vector2, is_crit: bool = false, from_dot: bool = false) -> void:
	if dying:
		return
	# 普通小怪同目标短窗集火保护：防多把武器同帧命中瞬间蒸发，保证受击硬直/击退/闪白充分展现
	if not from_dot and not is_elite:
		if _focus_hit_timer <= 0.0:
			_focus_hit_count = 0
		amount *= GameBalance.focus_fire_mult(_focus_hit_count)
		_focus_hit_count += 1
		_focus_hit_timer = GameBalance.FOCUS_FIRE_WINDOW
	# 作者模式·一击必杀：抬到必死（Boss 也吃这一刀）。放在集火削减之后，保证不会被削回不致死；
	# 其余受击流程照常走，死亡爆散/掉落/连杀音阶都还是真流程，方便验收击杀表现。
	if GameManager.author_mode and AuthorMode.one_hit_kill:
		amount = maxf(amount, current_hp + max_hp)
	current_hp -= amount
	# 精英变异血线检查（只触发一次；Boss 走自己的二阶段，_enter_mutation 内部按敌种分发）
	if not _mutated and is_elite and current_hp > 0.0 and current_hp <= max_hp * GameBalance.ELITE_MUTATION_HP_PCT:
		_enter_mutation()
	# 致命一刀不再发命中火花：尸体 0.185s 就塌缩没，火花要放 0.22s，会在空处留一道白闪；
	# 击杀点反馈由 _die() 的死亡爆散一力承担（视觉不丢，只是不再双发）
	var lethal := current_hp <= 0.0

	# 击退冲量瞬发与武器分级（空洞骑士/死亡细胞风格：第 0 帧爆发、轻武器短击退~12px、重武器强击退~45px）
	var elite_scale: float = 0.55 if is_elite else 1.0
	var crit_kb_mult: float = 1.25 if is_crit else 1.0
	var raw_kb := knockback * (GameBalance.KNOCKBACK_IMPULSE_SCALE * elite_scale * crit_kb_mult)
	var max_spd: float = GameBalance.KNOCKBACK_MAX_SPEED_CRIT if is_crit else GameBalance.KNOCKBACK_MAX_SPEED_NORMAL
	if raw_kb.length() > max_spd:
		raw_kb = raw_kb.normalized() * max_spd
	knockback_velocity = raw_kb

	# 受击硬直定身（hit-stun）与后仰姿态：
	# 受击当帧立即暂停主动 AI 追击速度，并在极速刹停后原地僵直定身；DoT tick 不触发硬直以保手感纯粹
	if not from_dot:
		var base_stun: float = GameBalance.HIT_STUN_CRIT if is_crit else GameBalance.HIT_STUN_NORMAL
		hit_stun_timer = maxf(hit_stun_timer, base_stun * elite_scale * hit_stun_resist)
		var freeze_dur: float = GameBalance.HIT_FREEZE_CRIT if is_crit else GameBalance.HIT_FREEZE_NORMAL
		_hit_freeze_timer = maxf(_hit_freeze_timer, freeze_dur * elite_scale * hit_stun_resist)
		if knockback.length_squared() > 10.0:
			_hit_tilt = -knockback.normalized().x * deg_to_rad(14.0)

	# 1. 声音与震动（分层听觉：入肉撕裂+低频下潜 + 肉眼可见的方向性顿挫冲击）
	# 暴击：声音+暴击顿帧+方向冲撞+zoom punch+创伤；DoT 暴击不出声但仍给镜头反馈
	# 普通命中（非 DoT）：方向性微冲击 + 入肉声，走全局限流闸
	if is_crit:
		if not from_dot:
			AudioManager.play_sfx("enemy_hit", 1.25, GameManager.rng.randf_range(1.08, 1.22))
			AudioManager.play_sfx("enemy_hit_crit", 1.35, GameManager.rng.randf_range(0.95, 1.05))
		GameManager.crit_hit_stop()
		# 镜头震动特权留给精英/首领：普通小怪暴击不发镜头冲击、缩放与创伤，
		# 避免高频割草时持续累加创伤导致屏幕常态抖动；打击感由顿帧、音效、跳字与暴击方向环承担。
		if is_elite and GameFeel.crit_camera_gate():
			GameManager.kick_camera(knockback, 6.5)
			GameFeel.zoom_punch(GameManager, 0.022, 0.12)
			GameManager.add_trauma(GameBalance.CRIT_TRAUMA_ELITE)
			GameFeel.vibrate(26, 0.65)
		# 暴击方向环（2026-10-14 受击火花「重构替代品」，只给暴击）：0.11s 极小光环，
		# 补「这一刀从哪来」的方向读数。暴击本身低频，且入口有 JuiceEffect 帧预算（≤6/帧）
		# 与视口双闸兜底，不会复现 2026-10-11 高频命中「空白处乱闪」的刷屏问题。
		# 致命一刀不发：击杀点反馈由 _die 的死亡爆散一力承担（同一次事件只许一处发反馈）。
		if not from_dot and not lethal:
			JuiceEffect.spawn_impact_pop(get_parent(), global_position,
				Color(1.0, 0.42, 0.22, 0.85), knockback)
	elif not from_dot:
		# 普通命中：移除镜头 micro_kick，保证屏幕稳定不颤抖；打击感由怪物受击形变、闪白、硬直与音效承担
		var pitch: float = GameManager.rng.randf_range(0.94, 1.08) if not is_elite else 0.85
		AudioManager.play_sfx("enemy_hit", 1.15 if not is_elite else 0.95, pitch)
		if is_elite or raw_kb.length() > GameBalance.KNOCKBACK_HEAVY_SPEED:
			AudioManager.play_sfx("enemy_hit_heavy", 1.00, GameManager.rng.randf_range(0.92, 1.06))

	# 精英/Boss 专属受击火花（2026-10-20）：小怪高频割草仍不发（防满屏乱闪的历史教训），
	# 但精英/Boss 同屏恒 1 只、体型大，非暴击直击若无火花则打击感空落。锚在体表受击侧（向攻击来向偏移），
	# 顺击退方向 ~100° 扇形喷溅。暴击已有方向环+镜头组承担，不重复发；DoT/致命/屏外不发。
	# 单只冷却 ELITE_HIT_SPARK_INTERVAL 防束流 tick 逐帧刷屏；照常受 FxParticlePool 4/帧预算与视口兜底。
	if is_elite and not is_crit and not from_dot and not lethal and not _offscreen and _elite_spark_cd <= 0.0:
		_elite_spark_cd = GameBalance.ELITE_HIT_SPARK_INTERVAL
		# Boss 用 death_corpse_linger 标记区分（避免基类反向引用 BossEnemy 子类）
		var is_boss: bool = death_corpse_linger
		var spark_scale: float = GameBalance.BOSS_HIT_SPARK_SCALE if is_boss else GameBalance.ELITE_HIT_SPARK_SCALE
		var edge: float = GameBalance.BOSS_HIT_SPARK_EDGE_OFFSET if is_boss else GameBalance.ELITE_HIT_SPARK_EDGE_OFFSET
		var kb_dir: Vector2 = knockback.normalized() if knockback.length_squared() > 1.0 else Vector2.ZERO
		var spark_pos: Vector2 = global_position - kb_dir * edge if kb_dir != Vector2.ZERO else global_position
		var spark_elem: String = "crit" if is_boss else "gold"
		FxParticlePool.burst(FxParticlePool.HIT_SPARK, spark_pos, spark_elem, spark_scale, false, kb_dir)

	# 跳字（2026-10-10 屏外减负）：屏外一概不发（玩家看不见，白烧分配）；
	# DoT tick 常驻发跳字。音效/硬直/击退/闪白/顿帧全部保留 —— 打击感读数不变。
	# combo_key = 自身 instance_id：同一敌人短窗（0.25s）内的连续伤害由 DamageNumber 聚合成
	# 一条（128×3），束流/喷吐/DoT 高频命中不再逐发刷屏、互顶看不清，池 96 溢出 new+free 抖动消失。
	# 只合并显示条数，不合并伤害数值（集火保护仍按每发计）。
	if not _offscreen:
		DamageNumber.spawn(get_parent(), global_position, int(amount), is_crit, "", get_instance_id())
	var squash_target := GameBalance.hit_squash_target(knockback, is_crit)
	play_squash(squash_target, 0.16)

	# 受击微反冲视觉位移（Jiggle Recoil）：受击当帧向击退方向微颤并同步至程序化视图
	if not from_dot and knockback.length_squared() > 10.0:
		_hit_jiggle_offset = knockback.normalized() * (4.2 if is_crit else 2.8)
		anim_sprite.position = _hit_jiggle_offset
		if procedural_view != null:
			procedural_view.position = anim_sprite.position

	# 3. 受击闪白（分级：普通亮白 vs 暴击绯金，加实留存时间）——零 Tween 分配版。
	# 2026-10-17 性能专项：per-instance shader uniform（打断批处理的元凶）改为共享材质 +
	# 顶点色通道 —— self_modulate 只属于闪白业务（modulate 仍归冰缓/引信/蓄力染色），
	# CPU 侧按 flash 权重向目标色提亮写入，衰减沿 _tick_hit_fx 同一计时推进。
	# 换色语义保留：暴击先绯金、0.02s 后换暖白再衰减（_flash_swap_t）；
	# 抗糊保护：当前闪白仍处前段（>0.4）且非暴击升级时，不暴力刷满，避免持续集火下糊成全白剪影；
	# 调柔口径不变：普通受击峰值 0.60（重叠集火 0.40），时长 0.08s，透出怪物暗色轮廓与动作。
	var is_fresh_flash := _flash_t <= 0.0 or (_flash_down_dur > 0.0 and (_flash_t / _flash_down_dur) <= 0.4) or is_crit
	if is_fresh_flash:
		var peak_flash: float = 0.60 if not is_crit else 1.0
		if not is_crit and _focus_hit_count > 1:
			peak_flash = 0.40
		if is_crit:
			_flash_col = FLASH_COL_CRIT
			_flash_t = 0.12
			_flash_down_dur = 0.12
			_flash_swap_t = 0.02
		else:
			_flash_col = FLASH_COL_NORMAL
			_flash_t = 0.08
			_flash_down_dur = 0.08
			_flash_swap_t = 0.0
		_write_flash_channel(peak_flash)

	if lethal:
		# 致命一刀不做任何位移：knockback_velocity 只作死亡镜头反馈的方向读数，
		# 精英 kick_camera / 斩杀反馈在 _die 中分派。
		# 暴击击杀特写：更实的独立顿帧（小怪不抽动镜头，精英伏诛走 HEAVY 自带更大顿帧/缩放）
		_death_crit_kill = is_crit and not from_dot
		if _death_crit_kill:
			if not is_elite:
				GameFeel.crit_kill_hit_stop(GameManager)
		# 击杀微顿帧（GameFeel 限流）：减潮加肉后击杀是低频事件，这一记「确认感」值得给；
		# DoT 跳死不发（那不是玩家亲手砍的一刀），精英伏诛走 LARGE 反馈自带顿帧不重复发
		elif not from_dot and not is_elite:
			GameManager.kill_hit_stop()
		_die()

	## 施加【离火灼烧】：按秒持续扣血，受离火羁绊与元素伤害增伤，多源叠加共鸣
# ---------------- 五行异常施加（灼烧 / 冰缓 / 剧毒） ----------------

func apply_burn(dps: float, duration: float) -> void:
	if dying:
		return
	var active_dps: float = burn_dps if burn_timer > 0.0 else 0.0
	burn_dps = GameBalance.stack_burn_dps(active_dps, dps)
	burn_timer = maxf(burn_timer, duration)

## 施加【玄水冰缓】：降低移动速度并附加冰蓝色温
func apply_chill(slow_pct: float, duration: float) -> void:
	if dying:
		return
	chill_slow = maxf(chill_slow, clampf(slow_pct, 0.1, 0.7))
	chill_timer = maxf(chill_timer, duration)

## 施加【青木剧毒】：持续毒素侵蚀，受元素伤害增伤
func apply_poison(dps: float, duration: float) -> void:
	if dying:
		return
	var active_dps: float = poison_dps if poison_timer > 0.0 else 0.0
	poison_dps = GameBalance.stack_poison_dps(active_dps, dps)
	poison_timer = maxf(poison_timer, duration)

## 施加【罡风卷定】（灵兽·灵风貂）：牵引初速 + 钉身 + 吹散在途扑击蓄力。
## 位移复用受击硬直滑行段（_resolve_velocity：velocity = knockback_velocity 后按
## KNOCKBACK_DECAY_STUN 指数急刹），调用方用 BalanceSpiritPet.pull_impulse 反解出
## 「恰好刹停在定身环」的初速，本函数不再过 take_damage 的击退限速（那是武器刀的尺子，
## 卷位移的目标是到环，不是推多远）。伤害由调用方另走 take_damage（复用飘字/集火保护）。
## 长扑承诺段不夺（项目口径：冲刺一旦起步 commit-through，wolf_ai_check 判据在守）；
## 但预警站桩直接吹散 —— 挂着「定身」还把人扑出去，文案就是假的。
## 哨兵注意：_charge_windup 的「不在该阶段」是 -1.0 而不是 0.0，
## 写 0.0 会让本帧末的预警到点分支照常发射。冷却无需重置：进蓄力时 _charge_timer
## 已按整周期回满，吹散不会导致立刻再扑。
func apply_vortex_pin(pull_velocity: Vector2, pin_sec: float) -> void:
	if dying:
		return
	hit_stun_timer = maxf(hit_stun_timer, pin_sec)
	knockback_velocity = pull_velocity
	if _charge_windup > 0.0:
		_charge_windup = -1.0
		_clear_charge_warning()

## 自爆结算：范围内伤玩家，不掉落、不计击杀奖励
# ---------------- 行为支路：自爆 ----------------

func _explode(player: Node2D) -> void:
	if dying:
		return
	_clear_explode_ring()
	# 冲击波扫到 explode_radius 为止：扫过的范围就是受伤的范围（与判定同源）
	JuiceEffect.spawn_shockwave(get_parent(), global_position, explode_radius, GameStyle.BAD)
	# 爆点留焦痕（纯视觉贴花，判定已在上方结算）。焦痕走全局共享闸（同 FloatingWeapon 裂痕
	# 同一治理口径）：成群丹爆接连自爆不再把地面糊满黑斑，屏上至多一块焦痕。
	if _fx_gap_gate(GROUND_SCORCH_MIN_GAP_MS, "scorch"):
		GroundDecal.spawn(get_parent(), global_position, GroundDecal.Kind.SCORCH, explode_radius * 0.7)
	GameManager.feedback(GameManager.FeedbackTier.MEDIUM)
	# 自爆也算战果：进击杀连击音阶（精英基准抬档同 _die 口径）
	AudioManager.register_kill_pitch(die_pitch_base * 1.12)
	AudioManager.play_sfx("enemy_death_elite", 0.9)
	if player.global_position.distance_to(global_position) <= explode_radius:
		# 目标可能是被嘲讽改追的灵兽：Player 走两参受创链路，其余鸭子分派单参（同短咬口径）
		if player is Player:
			player.take_damage(contact_damage * 2.0, global_position)
		elif player.has_method("take_damage"):
			player.take_damage(contact_damage * 2.0)
	_no_drop = true
	_die()

## 死亡弹幕：引信中途被击杀时向四周环形溅射（伤害走 bolt_damage 同一把回合缩放尺，幅度软一档）
func _fire_death_bolts() -> void:
	for i in range(maxi(1, death_bolt_count)):
		var bolt := EnemyBolt.acquire(get_parent())
		bolt.global_position = global_position
		bolt.direction = Vector2.from_angle(TAU * float(i) / float(maxi(1, death_bolt_count)))
		bolt.damage = bolt_damage * death_bolt_dmg_mult * (contact_damage / GameBalance.BOLT_DMG_BASE_REF)
		bolt.activate()
	AudioManager.play_sfx("enemy_bolt", 0.6, 0.8)

## 点燃丹爆引信预警圈：半径 = 判定半径（同源），引信烧完圈正好填满
func _ignite_explode_ring() -> void:
	if _explode_ring == null:
		_explode_ring = AoeTelegraph.new()
		_explode_ring.radius = explode_radius
		add_child(_explode_ring)
	_explode_ring.progress = 0.0
	_explode_ring.visible = true

## 清理丹爆预警圈（自爆结算 / 引信中途被杀时调用）
func _clear_explode_ring() -> void:
	if _explode_ring != null and is_instance_valid(_explode_ring):
		_explode_ring.queue_free()
	_explode_ring = null

## 开始冲刺（预警结束后调用）：方向到此锁死，之后不再追踪玩家
# ---------------- 行为支路：长扑冲刺 ----------------

## 长扑锁向：charge_aim_lead > 0 时冲向「玩家当前位置 + 玩家速度 × lead」的预判点
## （土豆兄弟 Goblin Shark 型：匀速直线跑位会被算进来，急停/变向则让它冲空）。
## 玩家静止或无速度输入时退化为正对玩家的原方向，不引入额外误差。
func _charge_aim_dir(player: Node2D, fallback: Vector2) -> Vector2:
	if charge_aim_lead <= 0.0:
		return fallback
	var predicted: Vector2 = player.global_position + player.velocity * charge_aim_lead
	var to_pred: Vector2 = predicted - global_position
	return to_pred.normalized() if to_pred.length_squared() > 1.0 else fallback

func _start_charge(dir: Vector2) -> void:
	_charge_active = charge_duration
	_charge_dir = dir
	_charge_brake = 0.0
	_charge_stagger = 0.0
	_charge_hit = false
	play_squash(Vector2(0.78, 1.24), 0.2)
	# 起步扬尘：位移是瞬时满速，视觉就得卖「蹬地弹射」而不是「匀速滑出去」
	JuiceEffect.spawn_step_dust(get_parent(), global_position + Vector2(0, 12), dir)
	# 烈雷兽变异：冲刺起步向左右两侧各放一排火球（犀牛 Mutation 同款）
	if charge_side_bolts > 0:
		var base_ang := dir.angle()
		for side in [-1.0, 1.0]:
			for i in range(charge_side_bolts):
				var bolt := EnemyBolt.acquire(get_parent())
				bolt.global_position = global_position
				bolt.direction = Vector2.from_angle(base_ang + side * PI * 0.5 + side * float(i) * 0.22)
				bolt.damage = bolt_damage * (contact_damage / GameBalance.BOLT_DMG_BASE_REF)  # 缩放基准见 BalanceWave.BOLT_DMG_BASE_REF（邪修基础接触伤，四类怪共用）
				bolt.activate()
	_clear_charge_warning()

## 收势落空判定：要等整段承诺（冲刺 + 刹车）的扫掠都结算完才许罚站。
## 冲刺归零那一帧的命中判定在本函数之后才跑（扫掠在 move_and_slide 之后），
## 在冲刺段末尾判会漏掉"最后一帧才够到人"的那一冲 ⇒ 碾到了还罚站，玩家看不懂。
## 落空才罚站（这是玩家侧身一步的奖励）；碾到人则不罚。
## 链冲（变异烈雷兽）：还有剩余段数就不罚站，改走段间短预警；链尾才按原口径结算。
func _settle_charge_recovery() -> void:
	if _chain_left > 0:
		_chain_left -= 1
		_chain_t = GameBalance.MUT_CHILEI_CHAIN_GAP
		return
	if not _charge_hit and charge_whiff_stagger > 0.0:
		_charge_stagger = charge_whiff_stagger
		play_squash(Vector2(1.22, 0.78), 0.18)

## 更新冲刺预警线（预警期间每帧调用）
func _update_charge_warning(player: Node2D) -> void:
	if _charge_warning_line == null:
		_charge_warning_line = Line2D.new()
		# 带宽 = 判定走廊直径。Line2D 默认圆头端帽，所以画出来那颗胶囊就是
		# 「玩家中心到本帧扫掠线段 ≤ charge_hit_radius」的点集本身 ⇒ 画多大 == 判多大
		_charge_warning_line.width = charge_hit_radius * 2.0
		_charge_warning_line.default_color = Color(1.0, 0.4, 0.2, 0.2)
		add_child(_charge_warning_line)

	# 更新端点：画「真撞得到的那一段」，不是画到玩家身上。
	# 旧写法线恒等于当前距离，玩家站在 450px 时线长 450、而冲刺只有 ~307px
	# ⇒ 预告虚报 143px（看得见的那条线必须就是它真能撞到的范围）。
	# 线长与扫掠判定、与判据 ⑧ 的实测位移，三处都取自 GameBalance.charge_reach 这一个式子。
	# 预判型（charge_aim_lead>0）画预判点方向：玩家看线就能读出「它在算我的跑位」，
	# 每帧跟玩家速度更新，出手那帧在 _start_charge 里锁死 —— 线始终就是真冲刺路径。
	# 端点方向：预判型冲向预判点（方向每帧跟玩家速度），普通型正对玩家。
	# 线长仍被 clamp 到 charge_reach 真实可达距离 —— 画出来的永远就是冲得到的那段。
	var aim_target: Vector2 = player.global_position + player.velocity * charge_aim_lead
	var local_target: Vector2 = aim_target - global_position
	var reach: float = GameBalance.charge_reach(move_speed * charge_speed_mul, charge_duration, charge_brake_time)
	if local_target.length() > reach:
		local_target = local_target.normalized() * reach
	# 原地覆写点 1 位置，避免每帧 clear_points + add_point 重建 PackedVector2Array
	if _charge_warning_line.get_point_count() < 2:
		_charge_warning_line.clear_points()
		_charge_warning_line.add_point(Vector2.ZERO)
		_charge_warning_line.add_point(local_target)
	else:
		_charge_warning_line.set_point_position(1, local_target)

	# 闪烁效果：宽带只能压透明度，否则一条带子糊掉半个场地（稀缺反馈预算）。
	# 基线从 0.15 提到 0.20：0.05~0.25 的旧区间在亮地面/密集弹幕里几乎读不出来。
	var alpha: float = 0.20 + 0.12 * sin(_charge_windup * 12.0)
	_charge_warning_line.default_color.a = alpha

## 清理预警线
func _clear_charge_warning() -> void:
	if _charge_warning_line != null:
		_charge_warning_line.queue_free()
		_charge_warning_line = null

## 发射火球（御剑邪修；bolt_count>1 时按 bolt_spread 扇形展开，剑煞邪修三连击）
# ---------------- 行为支路：远程火球 ----------------

const BOLT_WINDUP_TINT := Color(1.9, 1.35, 0.85)  ## 蓄力本体暖色提亮（比自爆引信的 2.2 档淡，一读是「要出手」不是「要炸了」）
const BOLT_GATHER_INTERVAL := 0.12  ## 蓄力期灵力汇聚粒子续发间隔（低频，走 FxParticlePool 的 SOUL_ORB 帧闸）
const BOLT_GATHER_OFFSET := 26.0    ## 汇聚粒子相对器尖的初始偏移半径（从身周收束向器尖）

## 起手蓄力：站定 + 变色 + 形变 + 低音量引信声。方向不在此锁（出手那帧才锁，蓄力期只作预告读法）
func _start_bolt_windup() -> void:
	_bolt_windup_t = maxf(bolt_windup, 0.05)
	_bolt_windup_total = _bolt_windup_t
	_bolt_gather_cd = 0.0
	_bolt_base_tint = anim_sprite.modulate
	anim_sprite.modulate = BOLT_WINDUP_TINT
	play_squash(Vector2(1.14, 0.88), _bolt_windup_t)
	AudioManager.play_sfx("enemy_fuse", 0.4)
	# 起手当帧就进施法姿态（>0 即 casting），避免首帧剑仍停在巡航位再跳一下
	if procedural_view != null:
		procedural_view.special_state = 0.001

## 蓄力期推进（每物理帧）：算 0→1 进度写进 special_state（驱动器尖聚能球由小到大），
## 并低频续发向器尖收束的灵力微粒。器尖聚能 = 施法「正在攒劲」的可读读数。
func _tick_bolt_windup(delta: float) -> void:
	_bolt_windup_t -= delta
	var progress: float = 0.0
	if _bolt_windup_total > 0.001:
		progress = clampf(1.0 - _bolt_windup_t / _bolt_windup_total, 0.0, 1.0)
	if procedural_view != null:
		procedural_view.special_state = progress
		procedural_view.aim_dir = _bolt_windup_dir
	# 灵力汇聚微粒：只对施法读法有意义的邪修系（有法剑器尖）发放，且走 SOUL_ORB 帧闸
	if _bolt_gather_cd <= 0.0 and procedural_view != null:
		_bolt_gather_cd = BOLT_GATHER_INTERVAL
		var tip: Vector2 = procedural_view.get_weapon_tip_global_pos()
		var out_dir: Vector2 = (_bolt_windup_dir if _bolt_windup_dir.length_squared() > 0.001 else Vector2.RIGHT)
		# 从器尖反向偏移一圈外沿出发，粒子顺向收束到器尖（FX 内部有上浮/汇聚感）
		var gather_pos: Vector2 = tip - out_dir * BOLT_GATHER_OFFSET
		FxParticlePool.burst(FxParticlePool.SOUL_ORB, gather_pos, _bolt_gather_color(), 0.8, false, out_dir)
	else:
		_bolt_gather_cd -= delta

## 灵力汇聚/打断四散的配色：剑煞血红、御剑幽蓝（与弹体色温同源）
func _bolt_gather_color() -> Color:
	var is_jiansha := (enemy_id == "jiansha_elite" or name.to_lower().begins_with("jiansha"))
	return GameStyle.FX_HDR_CRIT if is_jiansha else GameStyle.FX_HDR_WATER

## 蓄力被打断（受击硬直等）时还原本体色，蓄力作废不补发（硬直窗口就是玩家的反打奖励）
## 同时把已聚拢的灵力「炸散」：一撮微粒反向迸出，强化「打断成功」的反馈读数
func _cancel_bolt_windup() -> void:
	if _bolt_windup_t < 0.0:
		return
	_bolt_windup_t = -1.0
	_bolt_windup_total = 0.0
	anim_sprite.modulate = _bolt_base_tint
	if procedural_view != null:
		procedural_view.position.x = 0.0
		procedural_view.special_state = 0.0
		# 打断四散：从器尖处迸一小撮灵光（bypass 帧闸：低频、且这是玩家挣来的反馈，不该被受击火花挤掉）
		var tip: Vector2 = procedural_view.get_weapon_tip_global_pos()
		FxParticlePool.burst(FxParticlePool.SOUL_ORB, tip, _bolt_gather_color(), 1.0, true)

func _fire_bolt(player: Node2D) -> void:
	_bolt_windup_t = -1.0
	_bolt_windup_total = 0.0
	anim_sprite.modulate = _bolt_base_tint
	# 出手方向最后锁死：蓄力期玩家已看过预告，锁死的是「预告过的那个方向」
	var base_dir: Vector2 = (player.global_position - global_position).normalized()

	# 出膛点对齐法剑器尖（避免从肚脐中心凭空刷出）
	var spawn_pos: Vector2 = global_position
	if procedural_view != null:
		spawn_pos = procedural_view.get_weapon_tip_global_pos()
		procedural_view.trigger_recoil(base_dir)

	var is_jiansha := (enemy_id == "jiansha_elite" or name.to_lower().begins_with("jiansha"))
	for i in range(maxi(1, bolt_count)):
		# 火球走对象池（2026-10-11）：远程妖周期直射不再走 instantiate/free
		var bolt := EnemyBolt.acquire(get_parent())
		bolt.global_position = spawn_pos
		var offset_ang := 0.0
		if bolt_count > 1:
			offset_ang = (float(i) - float(bolt_count - 1) * 0.5) * bolt_spread
		bolt.direction = base_dir.rotated(offset_ang)
		bolt.damage = bolt_damage * (contact_damage / GameBalance.BOLT_DMG_BASE_REF)  # 随回合缩放比例与接触伤害一致（基准取邪修基础值 13）
		bolt.sword_style = true
		bolt.purple_style = is_jiansha
		bolt.activate()
	play_squash(Vector2(1.16, 0.84), 0.16)
	AudioManager.play_sfx("enemy_bolt", 0.7)
	if get_parent() != null:
		# 出膛爆闪色温与弹体同源（火球炽阳 / 剑气水系 / 剑煞绯金），HDR 起辉读得出「这是什么弹」
		var pop_col := GameStyle.FX_HDR_CRIT if is_jiansha else GameStyle.FX_HDR_WATER
		JuiceEffect.spawn_impact_pop(get_parent(), spawn_pos, pop_col, base_dir)

## 鼓妖光环：范围内同伴获得短时加速（0.4s 有效期，光环脉冲每 0.25s 续期）
# ---------------- 行为支路：鼓妖光环 ----------------

func _pulse_buff_aura() -> void:
	var radius_sq := buff_radius * buff_radius
	for e in GameManager.live_enemies:
		if e == self or not (e is EnemyBase) or e.dying:
			continue
		if global_position.distance_squared_to(e.global_position) <= radius_sq:
			e.receive_aura(buff_speed_mult, 400)

## 被鼓妖光环覆盖：取最高倍率，过期待遇由 _physics_process 自动清除。
## 首次被罩到（边沿）发一圈冲击波提示「它被加速了」；常驻脉冲只续期不再发，防刷屏。
func receive_aura(mult: float, duration_ms: int) -> void:
	if dying:
		return
	_aura_speed_mult = maxf(_aura_speed_mult, mult)
	_aura_until_ms = Time.get_ticks_msec() + duration_ms
	if not _aura_shown:
		_aura_shown = true
		if procedural_view != null:
			procedural_view.aura_level = 1.0
		JuiceEffect.spawn_shockwave(get_parent(), global_position, 22.0, GameStyle.JADE, 0.24)

## 蛛母产卵：幼体在自身周围落点，生命/伤害按当前回合 × 危险度缩放（与 WaveSpawner._scale_to_wave 同一把尺子）
# ---------------- 行为支路：产卵 / 闪现 / 分裂 ----------------

func _spawn_minion() -> void:
	if minion_scene == null:
		return
	var m := EnemyBase.acquire_or_new(minion_scene)
	if m == null:
		return
	m.reset_for_reuse()
	var angle := GameManager.rng.randf() * TAU
	m.global_position = global_position + Vector2(cos(angle), sin(angle)) * GameBalance.MINION_SCATTER_RADIUS
	m.max_hp = ceilf(m.max_hp * GameBalance.enemy_hp_mult(GameManager.wave_number) * GameBalance.danger_hp_mult(GameManager.danger_level))
	m.contact_damage = ceilf(m.contact_damage * GameBalance.enemy_dmg_mult(GameManager.wave_number) * GameBalance.danger_dmg_mult(GameManager.danger_level))
	m.add_to_group("enemies")
	m.activate()
	get_parent().call_deferred("add_child", m)
	play_squash(Vector2(1.22, 0.78), 0.2)
	# 产卵不是击杀：pitch_override 直传，绕开击杀连击阶梯（也不推层）
	AudioManager.play_sfx("enemy_death", 0.5, 1.3)

## 影魅闪现：瞬移到玩家侧翼 210px 处（落点受界碑约束），原地留一个淡出剪影当残影
func _teleport_near_player(player: Node2D) -> void:
	_spawn_teleport_ghost()
	var angle := GameManager.rng.randf() * TAU
	var pos: Vector2 = player.global_position + Vector2(cos(angle), sin(angle)) * GameBalance.BLINK_DISTANCE
	var lim: float = GameManager.MAP_HALF_EXTENT - GameBalance.BLINK_MAP_INSET
	global_position = pos.clamp(Vector2(-lim, -lim), Vector2(lim, lim))
	play_squash(Vector2(1.3, 0.7), 0.2)
	AudioManager.play_sfx("enemy_blink", 0.8)   ## 妖异残影是「下坠」，不许借玩家缩地成寸的 dodge

## 闪现残影：在旧位置生成一个本体的半透明剪影，快速淡出（区别于命中火花）
## 程序化视图走矢量剪影（复用同一份 EnemyVisualConfig）；无程序化配置才回退图集帧。
## 2026-10-13：图集在程序化敌种下不再加载，这条回退分支当前不会命中，保留为兜底。
func _spawn_teleport_ghost() -> void:
	if procedural_view != null and procedural_view.config != null:
		_spawn_vector_ghost()
		return
	if anim_sprite == null or anim_sprite.sprite_frames == null:
		return
	var tex := anim_sprite.sprite_frames.get_frame_texture(anim_sprite.animation, anim_sprite.frame)
	if tex == null:
		return
	var ghost := Sprite2D.new()
	ghost.texture = tex
	ghost.position = position  # 与本体同父节点，本地坐标即等价位置
	ghost.flip_h = anim_sprite.flip_h
	ghost.offset = anim_sprite.offset
	ghost.scale = anim_sprite.global_scale
	ghost.z_index = anim_sprite.z_index
	ghost.modulate = Color(0.55, 0.75, 1.0, 0.5)
	get_parent().add_child(ghost)
	var tw := ghost.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ghost, "modulate:a", 0.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(ghost, "scale", ghost.scale * 0.85, 0.25)
	tw.chain().tween_callback(ghost.queue_free)

## 矢量残影：复用静态池里的剪影渲染器，染成妖异蓝后淡出回池（2026-10-19 零 GC 专项）。
## 旧写法每次闪现 HollowKnightEnemyRenderer.new() + 淡出 queue_free，高密度影魅波是
## 节点构造/销毁 churn 热点。池化消灭节点 churn；淡出仍走 tween——闪现是秒级低频事件，
## 且 EnemyBase 无静态逐帧 tick 载体，tween 分配可忽略。
## 不继承受击闪白材质（残影要的是剪影，不是再闪一下）。
const GHOST_POOL_CAP := 10              ## 残影渲染器池上限；溢出个体淡出后直接释放
static var _ghost_idle: Array = []      ## 闲置残影渲染器（HollowKnightEnemyRenderer，出树休眠）

func _spawn_vector_ghost() -> void:
	var ghost: HollowKnightEnemyRenderer
	if _ghost_idle.is_empty():
		ghost = HollowKnightEnemyRenderer.new()
	else:
		ghost = _ghost_idle.pop_back()
	ghost.config = procedural_view.config
	ghost.facing = procedural_view.facing
	ghost.flip_h = procedural_view.flip_h
	ghost.is_moving = procedural_view.is_moving
	ghost.speed_ratio = procedural_view.speed_ratio
	ghost.position = position
	ghost.scale = procedural_view.scale
	ghost.z_index = anim_sprite.z_index
	ghost.modulate = Color(0.55, 0.75, 1.0, 0.5)
	ghost.visible = true
	get_parent().add_child(ghost)
	var tw := ghost.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ghost, "modulate:a", 0.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(ghost, "scale", ghost.scale * 0.85, 0.25)
	tw.chain().tween_callback(EnemyBase._recycle_vector_ghost.bind(ghost))

## 残影淡出收尾：出树回池（池满直接释放）；场景退出时经 clear_pools 统一清
static func _recycle_vector_ghost(ghost: HollowKnightEnemyRenderer) -> void:
	if not is_instance_valid(ghost):
		return
	if ghost.get_parent() != null:
		ghost.get_parent().remove_child(ghost)
	ghost.visible = false
	if _ghost_idle.size() < GHOST_POOL_CAP:
		_ghost_idle.append(ghost)
	else:
		ghost.queue_free()

## 血蛹分裂：死亡时裂出 N 只幼体（幼体按当前回合 × 危险度缩放；自爆/消散不触发）
func _split_offspring() -> void:
	for i in range(split_count):
		var child := EnemyBase.acquire_or_new(split_scene)
		if child == null:
			continue
		child.reset_for_reuse()
		var angle := TAU * float(i) / float(split_count) + GameManager.rng.randf() * 0.5
		child.global_position = global_position + Vector2(cos(angle), sin(angle)) * GameBalance.SPLIT_SCATTER_RADIUS
		child.max_hp = ceilf(child.max_hp * GameBalance.enemy_hp_mult(GameManager.wave_number) * GameBalance.danger_hp_mult(GameManager.danger_level))
		child.contact_damage = ceilf(child.contact_damage * GameBalance.enemy_dmg_mult(GameManager.wave_number) * GameBalance.danger_dmg_mult(GameManager.danger_level))
		child.add_to_group("enemies")
		child.activate()
		get_parent().call_deferred("add_child", child)

# ---------------- 行为支路：精英变异·震地（铁甲巨怪） ----------------

func _start_elite_slam() -> void:
	_elite_slam_windup_t = slam_windup
	if _elite_slam_ring == null:
		_elite_slam_ring = AoeTelegraph.new()
		add_child(_elite_slam_ring)
	# 半径每帧按当前字段钉死：变异升档 / 池化复用后字段会变，圈必须与本次判定同源
	_elite_slam_ring.radius = slam_radius
	_elite_slam_ring.progress = 0.0
	_elite_slam_ring.visible = true
	AudioManager.play_sfx("enemy_fuse", 0.6)
	play_squash(Vector2(0.82, 1.2), 0.4)

func _resolve_elite_slam(player: Node2D) -> void:
	_elite_slam_windup_t = -1.0
	if _elite_slam_ring != null:
		_elite_slam_ring.visible = false
	if dying:
		return
	JuiceEffect.spawn_shockwave(get_parent(), global_position, slam_radius, GameStyle.BAD)
	# 落点留震裂（纯视觉贴花，判定已在下方结算）
	GroundDecal.spawn(get_parent(), global_position, GroundDecal.Kind.CRACK, slam_radius)
	AudioManager.play_sfx("enemy_slam", 0.8)
	if player != null and player.global_position.distance_to(global_position) <= slam_radius:
		var slam_dmg := maxf(1.0, contact_damage * slam_dmg_mult)
		if player is Player:
			player.take_damage(slam_dmg, global_position)
		elif player.has_method("take_damage"):
			player.take_damage(slam_dmg)
	# 变异多段震地：首段结算后按 slam_echo_gap 间隔追加余波，半径逐段 ×slam_radius_grow。
	# 余波不再亮预警圈（首段圈已给出「以本体为圆心」的读法），只靠冲击环 + 裂痕 + 音效读段。
	# 震屏/反馈只在首段发一次（坑6：同一次挨打只许一处发反馈）。
	if slam_hits > 1:
		_slam_echo_left = slam_hits - 1
		_slam_echo_t = slam_echo_gap
		_slam_echo_radius = slam_radius * slam_radius_grow

## 变异震地余波：按段间隔结算，半径逐段扩张；每段独立判玩家是否在圈内
func _tick_slam_echo(delta: float, player: Node2D) -> void:
	if _slam_echo_t < 0.0:
		return
	_slam_echo_t -= delta
	if _slam_echo_t > 0.0:
		return
	if _slam_echo_left <= 0:
		_slam_echo_t = -1.0
		return
	if dying or get_parent() == null:
		_slam_echo_t = -1.0
		return
	JuiceEffect.spawn_shockwave(get_parent(), global_position, _slam_echo_radius, GameStyle.BAD)
	GroundDecal.spawn(get_parent(), global_position, GroundDecal.Kind.CRACK, _slam_echo_radius)
	AudioManager.play_sfx("enemy_slam", 0.65, 1.08)
	if player != null and is_instance_valid(player) and player.global_position.distance_to(global_position) <= _slam_echo_radius:
		var slam_dmg := maxf(1.0, contact_damage * slam_dmg_mult)
		if player is Player:
			player.take_damage(slam_dmg, global_position)
		elif player.has_method("take_damage"):
			player.take_damage(slam_dmg)
	_slam_echo_left -= 1
	_slam_echo_radius *= slam_radius_grow
	_slam_echo_t = slam_echo_gap if _slam_echo_left > 0 else -1.0

# ---------------- 行为支路：铁甲魔傀·落石轰炸 ----------------

## 起手落石：锁定 rock_count 个落点，每点挂一个填满式预警圈（半径 = rock_radius 同源）。
## 首点锁玩家预判位（rock_lead），其余绕玩家均布 + 抖动散布 —— 原地站桩必吃首点，
## 绕圈跑位则可能踩进散布点，逼迫玩家做「短距离变向」而不是无脑绕大圈。
func _start_rock_barrage(player: Node2D) -> void:
	_rock_windup_t = rock_windup
	_rock_points.clear()
	_clear_rock_rings()
	var lead: Vector2 = player.velocity * rock_lead if player is CharacterBody2D else Vector2.ZERO
	var first: Vector2 = player.global_position + lead
	_rock_points.append(first)
	var count: int = maxi(rock_count, 1)
	for i in range(1, count):
		# 均布角 + 随机相位抖动：多点不叠在同一方向，玩家读得出「这片区域都要躲」
		var ang: float = TAU * float(i) / float(maxi(count - 1, 1)) + GameManager.rng.randf_range(-0.35, 0.35)
		var dist: float = GameManager.rng.randf_range(rock_spread * 0.45, rock_spread)
		_rock_points.append(first + Vector2(cos(ang), sin(ang)) * dist)
	var parent := get_parent()
	if parent == null:
		return
	for p in _rock_points:
		var ring := AoeTelegraph.new()
		ring.radius = rock_radius
		ring.progress = 0.0
		parent.add_child(ring)
		ring.global_position = p
		_rock_rings.append(ring)
	play_squash(Vector2(0.84, 1.18), 0.3)
	AudioManager.play_sfx("enemy_fuse", 0.6)

## 落石结算：逐点判玩家是否在半径内；每点留焦痕与冲击环（画多大判多大）。
## 音效只在首点发一次：多点同帧叠 3~4 重 enemy_slam 会糊成一片噪音。
func _resolve_rock_barrage(player: Node2D) -> void:
	_rock_windup_t = -1.0
	_clear_rock_rings()
	if dying or get_parent() == null:
		return
	var first := true
	for p in _rock_points:
		JuiceEffect.spawn_shockwave(get_parent(), p, rock_radius, GameStyle.BAD, 0.3)
		GroundDecal.spawn(get_parent(), p, GroundDecal.Kind.SCORCH, rock_radius * 0.6)
		if first:
			AudioManager.play_sfx("enemy_slam", 0.85)
			first = false
		if player != null and is_instance_valid(player) and player.global_position.distance_to(p) <= rock_radius:
			var rock_dmg := maxf(1.0, contact_damage * rock_dmg_mult)
			if player is Player:
				player.take_damage(rock_dmg, p)
			elif player.has_method("take_damage"):
				player.take_damage(rock_dmg)
	_rock_points.clear()

## 清理落石预警圈（结算 / 死亡 / 池化复用前调用）
func _clear_rock_rings() -> void:
	for ring in _rock_rings:
		if ring != null and is_instance_valid(ring):
			ring.queue_free()
	_rock_rings.clear()

# ---------------- 行为支路：赤雷兽·雷环齐射 ----------------

## 雷环起手：短前摇站定，给玩家「要放全向环」的读法（前摇比震地短，但弹速慢可绕）
func _start_ring_bolt_cast() -> void:
	_ring_bolt_windup_t = maxf(ring_bolt_windup, 0.05)
	play_squash(Vector2(1.16, 0.86), _ring_bolt_windup_t)
	AudioManager.play_sfx("enemy_fuse", 0.5, 1.1)
	if procedural_view != null:
		procedural_view.special_state = 0.001

## 雷环出膛：全向均布，弧线角速度让弹幕形成旋臂（正面缝隙会转走，不能站桩等）
func _fire_ring_bolts() -> void:
	_ring_bolt_windup_t = -1.0
	if dying or get_parent() == null:
		return
	if procedural_view != null:
		procedural_view.special_state = 0.0
	var count: int = maxi(ring_bolt_count, 1)
	var dmg := maxf(1.0, contact_damage * ring_bolt_dmg_mult)
	var offset_ang := GameManager.rng.randf() * TAU
	for i in range(count):
		var ang := offset_ang + TAU * float(i) / float(count)
		var bolt := EnemyBolt.acquire(get_parent())
		bolt.global_position = global_position
		bolt.direction = Vector2(cos(ang), sin(ang))
		bolt.speed = ring_bolt_speed
		bolt.damage = dmg
		bolt.angular_speed = ring_bolt_curve_ang
		bolt.activate()
	play_squash(Vector2(1.2, 0.8), 0.16)
	AudioManager.play_sfx("enemy_bolt", 0.7)
	if get_parent() != null:
		JuiceEffect.spawn_impact_pop(get_parent(), global_position, GameStyle.BAD, Vector2.ZERO)

# ---------------- 行为支路：剑煞邪修·雷剑域 ----------------

## 落域起手：锁定玩家脚下，亮填满式预警圈（半径 = field_radius 同源）
func _start_field_cast() -> void:
	_field_windup_t = maxf(field_windup, 0.05)
	if _field_ring == null:
		_field_ring = AoeTelegraph.new()
		add_child(_field_ring)
	_field_ring.radius = field_radius
	_field_ring.progress = 0.0
	_field_ring.visible = true
	_field_ring.global_position = _field_target
	play_squash(Vector2(0.86, 1.16), field_windup)
	AudioManager.play_sfx("enemy_fuse", 0.55, 0.9)

## 落域：在锁定点铺一片持续伤害领域（复用 PoisonPool 骨架，血煞染色走 modulate 乘法）
func _drop_field() -> void:
	_field_windup_t = -1.0
	if _field_ring != null:
		_field_ring.visible = false
	if dying or get_parent() == null:
		return
	var pool := PoisonPool.acquire(get_parent())
	pool.global_position = _field_target
	pool.damage = maxf(1.0, contact_damage * field_dmg_mult)
	pool.duration = field_duration
	# 预警圈半径 = field_radius ⇒ 领域判定必须同源：scale_factor 驱动外观与碰撞一起缩
	pool.scale_factor = field_radius / PoisonPool.RADIUS
	pool.activate()
	# 血煞染色：modulate 是乘法，复用同一套毒潭几何不新增绘制路径。
	# 必须在 activate 之后写（池化复用的 _reset_defaults 不管 modulate，毒妖路径会显式归白）
	pool.modulate = Color(1.55, 0.45, 0.55)
	JuiceEffect.spawn_shockwave(get_parent(), _field_target, field_radius, GameStyle.BAD, 0.28)
	AudioManager.play_sfx("enemy_poison", 1.0, 0.85)
	play_squash(Vector2(1.2, 0.8), 0.16)

# ---------------- 行为支路：剑煞邪修·瞬身回斩（变异专属） ----------------

## 瞬身到玩家侧翼 + 立刻扇形剑气反打：先给残影读「它换了位置」，再出弹读「从哪打来」。
## 落点受界碑约束，避免卡进地图外；剑气走 sword_style + purple_style（剑煞血光配色）。
func _blink_strike(player: Node2D) -> void:
	if player == null or not is_instance_valid(player):
		return
	_spawn_teleport_ghost()
	var angle := GameManager.rng.randf() * TAU
	var pos: Vector2 = player.global_position + Vector2(cos(angle), sin(angle)) * blink_strike_dist
	var lim: float = GameManager.MAP_HALF_EXTENT - GameBalance.BLINK_MAP_INSET
	global_position = pos.clamp(Vector2(-lim, -lim), Vector2(lim, lim))
	play_squash(Vector2(1.3, 0.7), 0.2)
	AudioManager.play_sfx("enemy_blink", 0.8)
	if dying or get_parent() == null:
		return
	var base_dir: Vector2 = (player.global_position - global_position).normalized()
	var count: int = maxi(blink_strike_bolts, 1)
	var dmg := bolt_damage * (contact_damage / GameBalance.BOLT_DMG_BASE_REF)
	for i in range(count):
		var offset_ang := (float(i) - float(count - 1) * 0.5) * blink_strike_bolt_arc * 2.0
		var bolt := EnemyBolt.acquire(get_parent())
		bolt.global_position = global_position
		bolt.direction = base_dir.rotated(offset_ang)
		bolt.damage = dmg
		bolt.sword_style = true
		bolt.purple_style = true
		bolt.activate()
	AudioManager.play_sfx("enemy_bolt", 0.65, 1.1)

# ---------------- 行为支路：灵医治疗 ----------------

func _pulse_heal() -> void:
	var radius_sq := heal_radius * heal_radius
	var healed_any := false
	for e in GameManager.live_enemies:
		if e == self or not (e is EnemyBase) or e.dying:
			continue
		if global_position.distance_squared_to(e.global_position) > radius_sq:
			continue
		if e.current_hp >= e.max_hp:
			continue
		e.receive_heal(heal_amount)
		healed_any = true
	# 2026-10-16 演出去噪：演出环每跳只发一次（旧写法 if 缩进在 for 内，一跳奶到 N 个
	# 残血同伴就同帧叠 N 个 240px 大绿圈 + N 重音效——治疗环是全游戏最大的冲击环，群奶糊屏）。
	# 治疗本身照常逐个结算；「谁在被奶」的受者读数由 receive_heal 里的 heal_rise 逐个亮，不丢信息。
	if healed_any:
		JuiceEffect.spawn_shockwave(get_parent(), global_position, heal_radius, GameStyle.GOOD, 0.35)
		AudioManager.play_sfx("heal", 0.5)
		play_squash(Vector2(1.18, 0.84), 0.18)

func receive_heal(amount: float) -> void:
	if dying:
		return
	current_hp = minf(max_hp, current_hp + amount)
	if not _offscreen:
		DamageNumber.spawn(get_parent(), global_position, int(amount), false, "+%d" % int(amount))
		# 治疗可视出口（2026-10-14 P1）：受者身上升起青绿灵光，满屏也能读出「谁在被奶」
		JuiceEffect.spawn_heal_rise(get_parent(), global_position)
	play_squash(Vector2(1.1, 0.9), 0.14)

# ---------------- 行为支路：投毒（持续伤害区域） ----------------

## 起手投毒：锁定落点、亮预警圈、发蓄力形变与音效。
## 预警圈（AoeTelegraph）半径 = poison_radius 本身 ⇒ 圈画多大，落下的毒潭就判多大。
func _start_poison_cast() -> void:
	_poison_windup_t = poison_windup
	if _poison_ring == null:
		_poison_ring = AoeTelegraph.new()
		_poison_ring.radius = poison_radius
		add_child(_poison_ring)
	_poison_ring.progress = 0.0
	_poison_ring.global_position = _poison_target  ## 预警圈挂在锁定落点（毒潭将落于此，而非施法者脚下）
	_poison_ring.visible = true
	play_squash(Vector2(0.86, 1.18), poison_windup)
	AudioManager.play_sfx("enemy_fuse", 0.55)

## 落潭：预警结束，在锁定落点铺一片毒潭（走对象池，见 PoisonPool）。
## 伤害按回合 × 危险度缩放（与接触伤害同一条尺子：WaveSpawner 在 _scale_to_wave 里注入）。
func _drop_poison() -> void:
	_poison_windup_t = -1.0
	if _poison_ring != null:
		_poison_ring.visible = false
	if dying or get_parent() == null:
		return
	var pool := PoisonPool.acquire(get_parent())
	pool.global_position = _poison_target
	pool.damage = maxf(1.0, poison_damage)
	pool.duration = poison_duration
	# 预警圈半径 = poison_radius ⇒ 落潭判定必须同源：scale_factor 驱动外观与碰撞一起缩
	pool.scale_factor = poison_radius / PoisonPool.RADIUS
	pool.activate()
	JuiceEffect.spawn_shockwave(get_parent(), _poison_target, poison_radius, GameStyle.POISON, 0.28)
	AudioManager.play_sfx("enemy_poison", 1.0, GameManager.rng.randf_range(0.92, 1.08))
	play_squash(Vector2(1.2, 0.8), 0.16)

## 清理投毒预警圈（死亡 / 池化复用前调用）
func _clear_poison_ring() -> void:
	if _poison_ring != null and is_instance_valid(_poison_ring):
		_poison_ring.queue_free()
	_poison_ring = null

# ---------------- 精英变异（Mutation） ----------------

func _enter_mutation() -> void:
	match _eid:
		"golem":
			# 二阶段：常驻震地升格三连震（半径/伤害同步升档），落石增点，移速提升
			move_speed *= GameBalance.MUT_GOLEM_SPEED_MULT
			slam_interval = GameBalance.MUT_GOLEM_SLAM_INTERVAL
			slam_radius = GameBalance.MUT_GOLEM_SLAM_RADIUS
			slam_windup = GameBalance.MUT_GOLEM_SLAM_WINDUP
			slam_dmg_mult = GameBalance.MUT_GOLEM_SLAM_DMG_MULT
			slam_hits = GameBalance.MUT_GOLEM_SLAM_HITS
			slam_echo_gap = GameBalance.MUT_GOLEM_SLAM_ECHO_GAP
			slam_radius_grow = GameBalance.MUT_GOLEM_SLAM_RADIUS_GROW
			rock_count = GameBalance.MUT_GOLEM_ROCK_COUNT
			_elite_slam_timer = 1.2
		"chilei_elite":
			# 二阶段：长扑周期缩短 + 侧翼洒弹 + 三连冲 + 雷环增发
			charge_interval *= GameBalance.MUT_CHILEI_INTERVAL_MULT
			charge_side_bolts = GameBalance.MUT_CHILEI_SIDE_BOLTS
			chain_charges = GameBalance.MUT_CHILEI_CHAIN_CHARGES
			chain_windup_mult = GameBalance.MUT_CHILEI_CHAIN_WINDUP_MULT
			ring_bolt_count = GameBalance.MUT_CHILEI_RING_COUNT
		"jiansha_elite":
			# 二阶段：剑气 3→5 连、压近身、雷剑域扩域、解锁瞬身回斩
			bolt_count = GameBalance.MUT_JIANSHA_BOLT_COUNT
			bolt_interval *= GameBalance.MUT_JIANSHA_INTERVAL_MULT
			preferred_range = GameBalance.MUT_JIANSHA_RANGE
			field_radius *= GameBalance.MUT_JIANSHA_FIELD_RADIUS_MULT
			blink_strike_interval = GameBalance.MUT_JIANSHA_BLINK_INTERVAL
			blink_strike_dist = GameBalance.MUT_JIANSHA_BLINK_DIST
			blink_strike_bolts = GameBalance.MUT_JIANSHA_BLINK_BOLTS
			blink_strike_bolt_arc = GameBalance.MUT_JIANSHA_BLINK_BOLT_ARC
			_blink_strike_timer = 1.5
		_:
			return
	_mutated = true
	anim_sprite.modulate = Color(1.5, 0.65, 0.6)
	play_squash(Vector2(1.3, 0.75), 0.3)
	GameManager.announcement_triggered.emit("◆ 精英狂暴化 ◆")
	AudioManager.play_sfx("boss_raid", 0.9, 0.85)
	GameManager.feedback(GameManager.FeedbackTier.MEDIUM)

static var _dissolve_shader: Shader = null
static var _shared_noise_tex: ImageTexture = null
## 溶解材质实例（每实例懒建一次常驻）：死亡/清场消散时挂在动画节点上，
## 回池时由 reset_for_reuse/_recycle 切回 hit_flash_mat 覆盖
var _dissolve_mat: ShaderMaterial = null

static func _get_dissolve_shader() -> Shader:
	if _dissolve_shader == null:
		_dissolve_shader = load("res://assets/shaders/dissolve.gdshader") as Shader
	return _dissolve_shader

static func _get_noise_texture() -> ImageTexture:
	if _shared_noise_tex != null:
		return _shared_noise_tex
	var img := Image.create(64, 64, false, Image.FORMAT_L8)
	for y in range(64):
		for x in range(64):
			var n1 := sin(float(x) * 0.35 + sin(float(y) * 0.42) * 2.0) * 0.5 + 0.5
			var n2 := sin(float(x) * 0.73 - float(y) * 0.65) * 0.5 + 0.5
			var v := clampf(n1 * 0.6 + n2 * 0.4, 0.0, 1.0)
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	_shared_noise_tex = ImageTexture.create_from_image(img)
	return _shared_noise_tex

func _start_dissolve(duration: float, edge_col: Color, tw: Tween) -> void:
	# 溶解材质实例常驻复用（2026-10-16 GC 治理）：AOE 群杀同帧死十余只时，
	# 原先每次死亡都 ShaderMaterial.new() + 匿名闭包是集中分配热点。
	# shader/噪声贴图本就静态共享，材质实例懒建一次，之后只就地改参数；
	# 回池侧 reset_for_reuse/_recycle 已有「切回 hit_flash_mat」逻辑，无需再清。
	if _dissolve_mat == null:
		_dissolve_mat = ShaderMaterial.new()
		_dissolve_mat.shader = _get_dissolve_shader()
		_dissolve_mat.set_shader_parameter("noise_texture", _get_noise_texture())
	_dissolve_mat.set_shader_parameter("dissolve_amount", 0.0)
	_dissolve_mat.set_shader_parameter("edge_width", 0.06)
	_dissolve_mat.set_shader_parameter("edge_color", edge_col)
	if procedural_view != null:
		procedural_view.material = _dissolve_mat
	anim_sprite.material = _dissolve_mat
	tw.parallel().tween_property(_dissolve_mat, "shader_parameter/dissolve_amount", 1.0, duration)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## 回合结束时的消散：不掉落、不计数
# ---------------- 死亡与清场 ----------------

func dissolve() -> void:
	if dying or not is_inside_tree():
		return
	dying = true
	set_physics_process(false)
	# 清场路径不经过 _die 的 _clear_*：挂在父节点上的落石预警圈必须在这里收，
	# 否则回合末消散后圈还留在地面（自身子节点的 field/slam 圈随节点隐藏，可不动）
	_clear_rock_rings()
	if _field_ring != null and is_instance_valid(_field_ring):
		_field_ring.visible = false
	$CollisionShape2D.set_deferred("disabled", true)
	$Hurtbox/CollisionShape2D.set_deferred("disabled", true)
	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(anim_sprite, "modulate:a", 0.0, 0.4)
	tw.tween_property(anim_sprite, "scale", anim_sprite.scale * 0.6, 0.4)
	if procedural_view != null:
		tw.tween_property(procedural_view, "modulate:a", 0.0, 0.4)
		tw.tween_property(procedural_view, "scale", procedural_view.scale * 0.6, 0.4)
	_start_dissolve(0.4, GameStyle.FX_HDR_SHADOW, tw)
	tw.chain().tween_callback(_recycle_or_free)
	## （池化：原 queue_free——尸体塌缩落定后出树回池，下一波同种怪零 instantiate 复用）

func _die() -> void:
	if dying or not is_inside_tree():
		return
	dying = true
	GameManager.register_kill(is_elite, _death_crit_kill)
	# 死亡弹幕（土豆兄弟 Pufferfish 型）：引信中途被击杀的丹爆傀儡溅射一圈丹火。
	# 只认「被提前击杀」（_fuse > 0，引信还没烧完）；自己烧完的自爆走 _explode 已有 AoE 结算，
	# 再补一圈弹就是同一次死亡惩罚两回。回合末消散（dissolve）不经过这里，天然不触发。
	if death_bolt_count > 0 and _fuse > 0.0 and not _death_bolts_spent and not _no_drop:
		_death_bolts_spent = true
		_fire_death_bolts()

	# 血蛹系：临死分裂出幼体（自爆/回合末消散不触发）
	if split_count > 0 and split_scene != null and not _no_drop:
		_split_offspring()

	# 清理预警线（如果存在）
	_clear_charge_warning()
	_clear_explode_ring()
	_clear_poison_ring()
	_clear_rock_rings()
	if _elite_slam_ring != null and is_instance_valid(_elite_slam_ring):
		_elite_slam_ring.queue_free()
	_elite_slam_ring = null
	if _field_ring != null and is_instance_valid(_field_ring):
		_field_ring.queue_free()
	_field_ring = null

	# 金蟾系：击杀额外爆金币（回合末消散/自爆不算战果）
	if stone_reward > 0 and not _no_drop:
		GameManager.add_spirit_stones(stone_reward)
		DamageNumber.spawn(get_parent(), global_position + Vector2(0.0, -GameBalance.STONE_FLOAT_OFFSET), stone_reward, false, "+%d 金币" % stone_reward)
		AudioManager.play_sfx("gem_pickup", 0.9)

	# 击杀反馈分级震屏（死亡爆散视觉已于 2026-10-12 整体下线：击杀反馈 = 尸体塌缩 + 跳字 + 音效）
	# 2026-10-13 轻量重建：一小撮敌种主色碎屑 + 微环（JuiceEffect 侧有帧预算闸 + 视口门控，
	# 不与尸体塌缩抢戏），只在伤害击杀路径放；回合末消散走 dissolve 不经过这里
	if procedural_view != null and procedural_view.config != null:
		JuiceEffect.spawn_death_burst(get_parent(), global_position, procedural_view.config.col_primary, is_elite)
		# 击杀余韵（2026-10-14 P1）：敌种主色贴地残晕，给每秒多次的击杀留 0.55s 地面读数。
		# 池容量 16 与寿命 0.55s 双重兜底，极高频击杀下自动复用最旧残晕，不会糊满地面
		var glow_r: float = 26.0 if not is_elite else 38.0
		GroundDecal.spawn_tinted(get_parent(), global_position, glow_r, procedural_view.config.col_primary)
		# 死亡演出（精简去躁：普通小怪死亡已有贴地残晕与塌缩消散，省去高频 DEATH_WISP 粒子；精英/Boss 保持完整灵光碎屑 + 冲击环）：
		if not _no_drop:
			if is_elite or death_corpse_linger:
				var burst_scale: float = 1.8 if death_corpse_linger else 1.25
				var wave_r: float = 72.0 if death_corpse_linger else 48.0
				FxParticlePool.burst(FxParticlePool.DEATH_BURST, global_position, "gold", burst_scale)
				JuiceEffect.spawn_shockwave(get_parent(), global_position, wave_r, GameStyle.FX_HDR_GOLD, 0.22)
				# 幽魂消散（2026-10-19）：塌缩前一刻器尖/灵核蓄满再炸开，给厚血敌人一个「气数已尽」的收束
				FxParticlePool.burst(FxParticlePool.DEATH_WISP, global_position, "shadow", burst_scale, true)
	if is_elite:
		GameManager.kick_camera(knockback_velocity, GameBalance.DEATH_KICK_CAMERA)
		# 暴击斩杀精英/首领启用 HEAVY 档（此前预留未用）：更重的创伤/顿帧/缩放冲击
		if _death_crit_kill:
			GameManager.feedback(GameManager.FeedbackTier.HEAVY)
		else:
			GameManager.feedback(GameManager.FeedbackTier.LARGE)
		# 击杀连击音阶：播音前登记本命音高基准并推阶梯（elite 基准抬半档与普通怪分层）
		AudioManager.register_kill_pitch(die_pitch_base * 1.12)
		AudioManager.play_sfx("enemy_death_elite", 1.0)
	else:
		# 普通敌人死亡不推镜头，保持视野平稳；击杀确认感由死亡消散、音效与击杀连击音阶表达
		AudioManager.register_kill_pitch(die_pitch_base)
		AudioManager.play_sfx("enemy_death", 0.90)

	var gem_count = 1 if not is_elite else GameBalance.ELITE_GEM_COUNT
	if _no_drop:
		gem_count = 0
	if heal_orb_drop > 0 and gem_count > 0:
		gem_count = 0
		# 回复珠走对象池（2026-10-11，与宝石同一条路）
		var orb := HealOrb.acquire_or_new(get_parent())
		orb.global_position = global_position
		orb.heal_amount = float(heal_orb_drop)
		orb.activate()
	# 灵植夫·灵药滋生：死亡按概率额外掉一颗回复珠（与本体掉落独立，不占金币位）。
	# 2026-10-21 灵草袋同走这条概率腿：角色天赋 + 道具 hook 相加后夹 100%。
	var orb_chance: float = minf(1.0, GameManager.heal_orb_chance + GameManager.item_hook_sum("heal_orb_chance"))
	if orb_chance > 0.0 and not _no_drop and GameManager.rng.randf() < orb_chance:
		var extra_orb := HealOrb.acquire_or_new(get_parent())
		extra_orb.global_position = global_position + Vector2(
			GameManager.rng.randf_range(-GameBalance.HEAL_ORB_SCATTER_RADIUS, GameBalance.HEAL_ORB_SCATTER_RADIUS),
				GameManager.rng.randf_range(-GameBalance.HEAL_ORB_SCATTER_RADIUS, GameBalance.HEAL_ORB_SCATTER_RADIUS))
		extra_orb.heal_amount = HealOrb.BASE_HEAL
		extra_orb.activate()
	# 裂魂铃·击杀爆炸：尸体处一记小震荡，半径 = 判定（同源），伤害随元素成长（BalanceCombat 公式）。
	# 回合末消散（_no_drop）不触发：清场不算击杀战果，不该白拿爆炸链。
	var ex_base := GameManager.item_hook_sum("kill_explode")
	if ex_base > 0.0 and not _no_drop:
		var ex_radius := GameManager.item_hook_sum("kill_explode_radius")
		var ex_dmg := BalanceCombat.kill_explode_damage(ex_base, GameManager.elemental_damage) * GameManager.buff_damage_mult
		var ex_impulse := BalanceCombat.KILL_EXPLODE_IMPULSE * GameManager.knockback_mult
		# live_enemies 快照走静态复用数组栈（2026-10-19 零 GC 专项）：
		# 旧写法每次击杀 duplicate() 一次新数组，群杀链爆时同帧几十次分配。
		# 递归安全：链式 take_damage 里嵌套的 _die 会再取一张快照（每层独占一张），
		# 用完 clear() 回栈容量不丢，稳态零分配。
		var snap: Array = _explode_snap_pool.pop_back() if not _explode_snap_pool.is_empty() else []
		snap.append_array(GameManager.live_enemies)
		for e in snap:
			if e == null or not is_instance_valid(e) or e.dying or e == self:
				continue
			if e.is_in_group("chests") or e.is_in_group("herbs"):
				continue
			var ex_off: Vector2 = e.global_position - global_position
			if ex_off.length() > ex_radius:
				continue
			var ex_dir := ex_off.normalized() if ex_off.length_squared() > 0.0001 else Vector2.UP
			e.take_damage(ex_dmg, ex_dir * ex_impulse)
		snap.clear()
		_explode_snap_pool.push_back(snap)
		# 2026-10-16 演出去噪：伤害/击退照常逐次结算（玩法零改动），金色爆炸环走全局限频——
		# 旧写法每次击杀一发 90px 环，清怪高潮连环爆炸时是冲击环雨。伤害与环同源只是读法惯例，
		# 环限频不改爆炸链实际范围；链爆读数由受击方 take_damage 自己的受击反馈补足。
		if _fx_gap_gate(KILL_EXPLODE_FX_MIN_GAP_MS, "kill_explode_fx"):
			JuiceEffect.spawn_shockwave(get_parent(), global_position, ex_radius, GameStyle.GOLD_FX_EDGE, 0.25)
	for i in range(gem_count):
		# 宝石走对象池（2026-10-10 第 6 波卡顿优化）：击杀高频 instantiate/queue_free 归零
		var gem := AstralGem.acquire_or_new(gem_scene, get_tree().current_scene)
		var offset = Vector2.ZERO if gem_count == 1 else Vector2(
				GameManager.rng.randf_range(-GameBalance.GEM_SCATTER_RADIUS, GameBalance.GEM_SCATTER_RADIUS),
				GameManager.rng.randf_range(-GameBalance.GEM_SCATTER_RADIUS, GameBalance.GEM_SCATTER_RADIUS))
		gem.global_position = global_position + offset
		# 小怪经验走反割草补偿倍率（BalanceWave.mob_kill_exp）：预算 -20% 后单只 ×1.25 找平每波收入。
		# 精英在下面立即被 ELITE_GEM_EXP 覆写，不吃这条。金币腿（stone_value=-1 随 exp_value 同值）
		# 自动同比放大 —— 数量 ×0.8 × 单只 ×1.25 = 每波金币收入持平；碎金档显式置 1 枚不受影响。
		gem.exp_value = GameBalance.mob_kill_exp(exp_reward)
		gem.is_gold = is_elite   ## 金宝视觉统一由 is_gold 驱动（灯色在 _update_visual 里跟色）
		if is_elite:
			gem.exp_value = GameBalance.ELITE_GEM_EXP
		else:
			# 碎金档（2026-10-13 体验重塑）：普通怪按回合概率掉基础碎金/金砂片 ——
			# 经验腿足额给（exp_value 不动），只有金币腿折到 1，符合小怪掉零钱直觉且平抑后期通胀。
			# 精英/Boss 金宝石不 roll，保住高光时刻足额回报；碎金率见 BalanceEconomy。
			if GameManager.rng.randf() < GameBalance.gem_shard_chance(GameManager.wave_number):
				gem.is_shard = true
				gem.stone_value = GameBalance.GEM_SHARD_STONE_VALUE
		gem.activate()

	set_physics_process(false)
	$CollisionShape2D.set_deferred("disabled", true)
	$Hurtbox/CollisionShape2D.set_deferred("disabled", true)
	# 尸体停帧后 _tick_hit_fx / _tick_hit_visuals 都不再跑：闪白、挤压、受击微反冲一律就地归位，
	# 别让尸体挂着半截闪白或歪着半格消散
	_squash_t = 0.0
	juice_scale = Vector2.ONE
	_flash_t = 0.0
	_flash_swap_t = 0.0
	_hit_jiggle_offset = Vector2.ZERO
	anim_sprite.position = Vector2.ZERO
	if procedural_view != null:
		procedural_view.position = Vector2.ZERO
	_write_flash_channel(0.0)

	# 死灭动画分级（2026-10-15）：小怪保持「膨胀 0.045s → 塌缩 0.14s」快节奏（高频事件不宜加重）；
	# 精英膨胀后多一段踉跄倾倒再塌缩（慢半拍，倒地有重量感）；Boss 倾倒后尸体滞留慢渐隐
	#（不缩零，谢幕读数更足）。安全性：进本段前物理/碰撞已断，回合末 dissolve() 对 dying 短路，
	# 拉长演出只多留几帧绘制，不影响回收与清场。
	# 倾倒方向跟随致命一刀的受力侧（_hit_tilt 符号：后仰角与击退水平分量同号），垂直击杀默认右倾。
	var topple_sign := signf(_hit_tilt) if _hit_tilt != 0.0 else 1.0
	var tw = create_tween()
	var swell_scale := anim_base_scale * Vector2(GameBalance.CORPSE_SWELL_SCALE, GameBalance.CORPSE_SWELL_SCALE)
	tw.tween_property(anim_sprite, "scale", swell_scale, 0.045)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if procedural_view != null:
		tw.parallel().tween_property(procedural_view, "scale", swell_scale, 0.045)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	if is_elite or death_corpse_linger:
		# 踉跄/倾倒段：精英与 Boss 共有的「慢半拍」
		var topple_rad: float = GameBalance.BOSS_DEATH_TOPPLE_RAD if death_corpse_linger else GameBalance.ELITE_DEATH_TOPPLE_RAD
		var topple_dur: float = 0.15 if death_corpse_linger else GameBalance.ELITE_DEATH_STAGGER_DUR
		tw.chain().tween_property(anim_sprite, "rotation", topple_sign * topple_rad, topple_dur)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if procedural_view != null:
			tw.parallel().tween_property(procedural_view, "rotation", topple_sign * topple_rad, topple_dur)\
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	if death_corpse_linger:
		# Boss：倒地后尸体滞留一停，再只淡出不塌缩（「大妖伏诛」1.2s 消融）
		tw.chain().tween_interval(GameBalance.BOSS_DEATH_LINGER_DUR)
		tw.set_parallel(true)
		var fade_dur: float = 1.2
		tw.tween_property(anim_sprite, "modulate:a", 0.0, fade_dur)
		if procedural_view != null:
			tw.tween_property(procedural_view, "modulate:a", 0.0, fade_dur)
		if shadow_sprite != null and shadow_sprite.visible:
			tw.tween_property(shadow_sprite, "modulate:a", 0.0, fade_dur)
		_start_dissolve(fade_dur, GameStyle.FX_HDR_GOLD, tw)
	else:
		# 小怪（0.4s）/精英（0.8s）：原地消融塌缩消散（T-3.1 接入 dissolve shader）
		var collapse_dur: float = 0.8 if is_elite else 0.4
		var edge_col: Color = GameStyle.FX_HDR_GOLD if is_elite else GameStyle.FX_HDR_SHADOW
		tw.set_parallel(true)
		tw.tween_property(anim_sprite, "scale", Vector2.ZERO, collapse_dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_property(anim_sprite, "modulate:a", 0.0, collapse_dur)
		if procedural_view != null:
			tw.tween_property(procedural_view, "scale", Vector2.ZERO, collapse_dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			tw.tween_property(procedural_view, "modulate:a", 0.0, collapse_dur)
		_start_dissolve(collapse_dur, edge_col, tw)
	# 尸体不再沿击退方向滑出：致命一刀既已击杀，就不该再有击退位移 ——
	# 原地塌缩才是「这一下打死了」的读数（旧斩杀击飞会在消散中把尸体推出最多 42px）
	tw.chain().tween_callback(_recycle_or_free)
