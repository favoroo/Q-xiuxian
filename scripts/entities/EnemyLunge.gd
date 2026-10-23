class_name EnemyLunge
extends RefCounted

## 近战扑咬三段状态机（2026-10-23）：纯接触怪的「出招」动作。
##
## 为什么单独立一个文件：EnemyBase 是历史热区大文件（145KB），新增行为一律落子目录新文件，
## 基类只留挂接点（见 AGENTS.md 并行协作约定）。本类只管「何时扑、往哪扑、扑多久」，
## 位移写回由宿主执行，伤害仍由宿主的接触结算发放 —— 本类不扣任何血。
##
## 三段：
##   WINDUP 站蹲前摇：原地不动，special_state 由 0 填到 1（渲染器据此画蓄力姿态），可被硬直打断
##   DASH   前扑：velocity 逐帧写死成 dir * peak_speed，位移总量 = BalanceCombat.lunge_reach
##   RECOVER 收势：原地停住，给玩家反打窗口
##
## 同源纪律：本类只算「本帧速度」，位移积分由宿主 move_and_slide 产生，
## 判据用 BalanceCombat.lunge_reach 量真实位移 —— 一处建模，三处引用（画/冲/判）。

enum Phase { IDLE, WINDUP, DASH, RECOVER }

const PHASE_NAMES := ["idle", "windup", "dash", "recover"]

var phase: int = Phase.IDLE
var phase_t: float = 0.0          ## 当前段剩余时间（秒）
var dir: Vector2 = Vector2.RIGHT  ## 本扑锁死方向（前摇结束那刻锁定，之后不再追踪）
var peak_speed: float = 0.0       ## 前扑峰速（px/s）
var remain_dist: float = 0.0      ## 前扑剩余位移（px）：按距离积分，保证总位移 == lunge_reach
var cooldown_t: float = 0.0       ## 冷却计时
var params: Dictionary = {}       ## 敌种参数（speed_mul/dash/recover/cooldown）

func configure(p: Dictionary) -> void:
	params = p
	reset()

func reset() -> void:
	phase = Phase.IDLE
	phase_t = 0.0
	dir = Vector2.RIGHT
	peak_speed = 0.0
	remain_dist = 0.0
	cooldown_t = 0.0

func is_active() -> bool:
	return phase != Phase.IDLE

## 是否处于「锁定位移」段（前扑）：宿主据此跳过速度吸附插值，直接吃本类写死的 velocity
func is_dashing() -> bool:
	return phase == Phase.DASH

## 是否处于「原地不动」段（前摇/收势）：宿主据此把期望速度归零
func is_rooted() -> bool:
	return phase == Phase.WINDUP or phase == Phase.RECOVER

## 蓄力进度 0→1（前摇段）：喂渲染器 special_state，作第二层预警读数
func charge_progress() -> float:
	if phase != Phase.WINDUP or phase_t <= 0.0:
		return 0.0
	var total: float = float(params.get("windup", BalanceCombat.LUNGE_WINDUP))
	return clampf(1.0 - phase_t / maxf(total, 0.0001), 0.0, 1.0)

## 每物理帧推进。返回本帧应写入的速度（Vector2.ZERO = 宿主自己决定追击速度）。
## 参数：delta、与目标的距离（px）、朝向目标的方向、宿主移速、是否处于硬直。
## 返回值的语义：
##   is_dashing() 为 true 时 → 调用方必须直接采用本返回值（锁定段，不插值）
##   is_rooted()  为 true 时 → 返回 ZERO，调用方把期望速度归零
##   IDLE         时 → 返回 ZERO，调用方走正常追击
func tick(delta: float, dist: float, to_target: Vector2, move_speed: float, stunned: bool) -> Vector2:
	if cooldown_t > 0.0:
		cooldown_t = maxf(0.0, cooldown_t - delta)
	if phase == Phase.IDLE:
		# 起手上限按「本扑真能覆盖的距离」现算，不用固定 132px：
		# 固定上沿会让短扑怪（史莱姆一扑 33.6px）在 90px 外起手，动作演完还剩 56px 够不着，
		# 招式永远咬不到人。engage_range = lunge_reach + 接触余量。
		var peak: float = move_speed * float(params.get("speed_mul", BalanceCombat.LUNGE_SPEED_MUL))
		var engage: float = BalanceCombat.lunge_engage_range(
			peak, float(params.get("dash", BalanceCombat.LUNGE_DASH_TIME)))
		if not stunned and cooldown_t <= 0.0 and dist >= BalanceCombat.LUNGE_MIN_RANGE \
				and dist <= engage:
			_start_windup(to_target)
		return Vector2.ZERO
	if phase == Phase.WINDUP:
		# 前摇可打断：挨打就取消（与火球蓄力同一条纪律），不惩罚冷却 —— 打断本身就是奖励
		if stunned:
			_cancel()
			return Vector2.ZERO
		phase_t -= delta
		if phase_t <= 0.0:
			_start_dash(to_target, move_speed)
		return Vector2.ZERO
	if phase == Phase.DASH:
		# 按「剩余位移」推进，而不是按剩余时间：一帧内的位移 = min(峰速×delta, 剩余)，
		# 这样总位移恒等于 lunge_reach，与帧率无关（按时间推进会在末帧丢掉不足一帧的零头，
		# 60Hz 下实测少 30%，画出来的前扑和真冲出去的就对不上了）。
		# 段位切换延后一帧：剩余归零的那次 tick 仍照发最后一步位移，下一 tick 才切收势。
		# 若在归零当帧就切段，宿主会按「收势钉住」把这一步丢掉，位移又短一截。
		if remain_dist <= 0.0001:
			_start_recover()
			return Vector2.ZERO
		var step: float = minf(peak_speed * delta, remain_dist)
		remain_dist = maxf(0.0, remain_dist - step)
		return dir * (step / maxf(delta, 0.0001))
	# RECOVER
	phase_t -= delta
	if phase_t <= 0.0:
		phase = Phase.IDLE
		phase_t = 0.0
		cooldown_t = float(params.get("cooldown", BalanceCombat.LUNGE_COOLDOWN))
	return Vector2.ZERO

func _start_windup(to_target: Vector2) -> void:
	phase = Phase.WINDUP
	phase_t = float(params.get("windup", BalanceCombat.LUNGE_WINDUP))
	dir = to_target.normalized() if to_target.length_squared() > 0.0001 else Vector2.RIGHT

func _start_dash(to_target: Vector2, move_speed: float) -> void:
	phase = Phase.DASH
	peak_speed = move_speed * float(params.get("speed_mul", BalanceCombat.LUNGE_SPEED_MUL))
	# 总位移取闭式解 —— 与判据、与渲染读数同一把尺子
	remain_dist = BalanceCombat.lunge_reach(peak_speed, float(params.get("dash", BalanceCombat.LUNGE_DASH_TIME)))
	phase_t = float(params.get("dash", BalanceCombat.LUNGE_DASH_TIME))
	# 前摇期间方向每帧更新（只是预告），出手那帧锁死 —— 玩家侧移就能躲开
	dir = to_target.normalized() if to_target.length_squared() > 0.0001 else dir

func _start_recover() -> void:
	phase = Phase.RECOVER
	phase_t = float(params.get("recover", BalanceCombat.LUNGE_RECOVER))

func _cancel() -> void:
	phase = Phase.IDLE
	phase_t = 0.0
	# 打断 = 这只怪这一轮白起了，得从头再攒。给满冷却（不是打折）：
	# 打折会让「打断前摇」变成「它更快再来一次」，与奖励玩家反打的意图相反。
	cooldown_t = float(params.get("cooldown", BalanceCombat.LUNGE_COOLDOWN))

## 本扑真实位移（供判据与调试读数）：与 BalanceCombat.lunge_reach 同一把尺子
func reach() -> float:
	return BalanceCombat.lunge_reach(peak_speed, float(params.get("dash", BalanceCombat.LUNGE_DASH_TIME)))
