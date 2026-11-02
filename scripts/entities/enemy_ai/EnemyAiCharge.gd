extends RefCounted

## 长扑冲刺支路（2026-11-02 自 EnemyBase 拆出，逐行平移零逻辑改动）：预警 → 冲刺 → 刹车 → 落空罚站
## （变异链冲段间短预警）四态状态机 + 锁向/预警线。
##
## 纪律：首参 e 为宿主敌人（不标类型，鸭类型访问——反向硬类型引用 EnemyBase 会触发
## 循环类依赖，把场景 preload 打成空包，项目坑 12/16）。含宿主成员的声明用显式类型
## （无类型参数上 := 推断必炸）。BossEnemy 覆写 _start_charge/_settle_charge_recovery，
## 模块内一律经 e._start_charge(...) 走宿主虚分发，覆写链不断。

const CHARGE_AIM_LOCK_WINDOW := 0.25  ## 预警末段锁向窗口（秒）：预警最后这段方向与预警线一起锁死

## 妖狼系长扑四态状态机（移动出口 e._pp_target_vel）：站桩预警 → 直线冲刺 → 收势刹车 → 落空罚站
## （变异链冲段间短预警）。预警带长度/真实位移/扫掠判定三件事同源取自 GameBalance.charge_reach；
## 冲刺/收势两段自己把 velocity 写死（宿主 charge_locked 那一段因此跳过吸附插值）。
static func tick_charge_lunge(e, delta: float, player: Node2D, dir: Vector2, dist_sq: float) -> void:
	# 妖狼系长扑（移动出口 _pp_target_vel）：
	#   跑道够（charge_min_range ~ charge_max_range）→ 站桩预警 → 直线冲刺 → 收势（落空则罚站）
	# 长扑的三件事必须同源，都取自 GameBalance.charge_reach：预警带长度、真实位移、扫掠判定。
	# 冲刺/收势两段自己把 velocity 写死（下面 charge_locked 那一段因此跳过吸附插值）。
	if e.charge_interval > 0.0:
		e._charge_timer -= delta
		var min_sq: float = e.charge_min_range * e.charge_min_range
		var max_sq: float = e.charge_max_range * e.charge_max_range

		# 预警阶段：原地不动，画预警线
		if e._charge_windup > 0.0:
			e._charge_windup -= delta
			e._pp_target_vel = Vector2.ZERO
			# 末段锁向（2026-10-25 玩家反馈「走到哪都被锁」）：整段预警线跟着跑位每帧刷新，
			# 读起来就是锁定。最后 CHARGE_AIM_LOCK_WINDOW 秒提前锁死方向，线端点定住 ——
			# 「线停了」就是明确的躲避信号；急停/变向从此必能走出走廊（锁向用锁定向的
			# 玩家速度，出手帧不再重算）。预警总长本就小于窗口时退化为起手即锁。
			if not e._charge_aim_locked and e._charge_windup <= CHARGE_AIM_LOCK_WINDOW:
				e._charge_dir = e._charge_aim_dir(player, dir)
				e._charge_aim_locked = true
			e._update_charge_warning(player)
			if e._charge_windup <= 0.0:
				e._start_charge(e._charge_dir if e._charge_aim_locked else e._charge_aim_dir(player, dir))

		# 冲刺阶段：起步即满速，位移由锁定段直接写进 velocity（同 Player 缩地成寸的口径）。
		# 旧写法只交一个 target_vel，让下方 900 px/s² 的吸附插值从站桩预警的 0 速去爬峰速 384
		# ⇒ 0.43s 才够到速度（锁定时长一半耗在起步上），冲刺结束后还留一段朝玩家拐弯的滑行尾巴
		# ⇒ 「画的线」「撞的段」「判的范围」是三套数，玩家只要动一下就永远碰不到它
		elif e._charge_active > 0.0:
			e._charge_active -= delta
			e.velocity = e._charge_dir * e.move_speed * e.charge_speed_mul
			e._pp_target_vel = e.velocity
			e.knockback_velocity = Vector2.ZERO
			e._clear_charge_warning()
			if e._charge_active <= 0.0:
				e._charge_brake = e.charge_brake_time

		# 收势刹车：峰速线性刹到站定。这一段也是承诺出去的位移，预警线按 GameBalance.charge_reach 已把它算进线长
		elif e._charge_brake > 0.0:
			e._charge_brake -= delta
			var brake_k: float = maxf(e._charge_brake / maxf(e.charge_brake_time, 0.0001), 0.0)
			e.velocity = e._charge_dir * (e.move_speed * e.charge_speed_mul) * brake_k
			e._pp_target_vel = e.velocity
			e.knockback_velocity = Vector2.ZERO
			if e._charge_brake <= 0.0:
				e._settle_charge_recovery()

		# 落空罚站：冲空了就是白给，玩家看得见「它过去了、站着不动」⇒ 躲开这条路才有奖励，而不只是没被打到
		elif e._charge_stagger > 0.0:
			e._charge_stagger -= delta
			e._pp_target_vel = Vector2.ZERO
			# 2026-10-23：罚站必须真的站住。旧写法只把期望速度归零，velocity 由
			# _resolve_velocity 的 move_toward(900px/s²) 从收势末速慢慢刹 —— 罚站头 0.1s
			# 仍以 40+ px/s 往前滑，判据量到 29.4px 位移（用户口径「罚站就是站桩挨打」）。
			# 收势段的线性刹车已经把速度收到接近零，这里直接钉死，不留滑行尾巴。
			e.velocity = Vector2.ZERO
			e.knockback_velocity = Vector2.ZERO

		# 链冲段间短预警（变异烈雷兽）：上一段收势后不罚站，短暂停顿再起手下一冲。
		# 每段仍有完整预警线可读，玩家能连续侧移躲完整轮；链尾才吃落空罚站。
		elif e._chain_t >= 0.0:
			e._chain_t -= delta
			e._pp_target_vel = Vector2.ZERO
			if e._chain_t <= 0.0:
				e._chain_t = -1.0
				e._charge_windup = e.charge_windup_time * e.chain_windup_mult
				e._charge_windup_total = e._charge_windup
				e._charge_aim_locked = false
				e.play_squash(Vector2(0.82, 1.2), 0.2)
				AudioManager.play_sfx("enemy_fuse", 0.35, GameManager.rng.randf_range(1.18, 1.32))

		# 空闲：冷却到 + 跑道够 → 长扑预警（硬直中不起手：预警是冲刺的蓄力段，
		# 被钉着还起手，后续 _start_charge 会从硬直滑行分支夺走位移，「定身」成空话）
		# 雷环前摇期间不抢跑：两个前摇同时开会让「站定提亮」的读法互相打断。
		elif e.charge_interval > 0.0 and e._charge_timer <= 0.0 and dist_sq > min_sq and dist_sq < max_sq and not e._pp_stun and e._ring_bolt_windup_t < 0.0:
			e._charge_timer = e.charge_interval
			e._charge_windup = e.charge_windup_time
			e._charge_windup_total = e._charge_windup
			e._charge_aim_locked = false
			e._chain_left = maxi(e.chain_charges - 1, 0)
			# 起手反馈：下蹲蓄势 + 低音量哨声（全预警体系里原本唯一「静默起手」的，现在齐了）
			e.play_squash(Vector2(0.82, 1.2), 0.24)
			AudioManager.play_sfx("enemy_fuse", 0.35, GameManager.rng.randf_range(1.18, 1.32))

## 长扑锁向：charge_aim_lead > 0 时冲向「玩家当前位置 + 玩家速度 × lead」的预判点
## （土豆兄弟 Goblin Shark 型：匀速直线跑位会被算进来，急停/变向则让它冲空）。
## 玩家静止或无速度输入时退化为正对玩家的原方向，不引入额外误差。
static func charge_aim_dir(e, player: Node2D, fallback: Vector2) -> Vector2:
	if e.charge_aim_lead <= 0.0:
		return fallback
	var predicted: Vector2 = player.global_position + player.velocity * e.charge_aim_lead
	var to_pred: Vector2 = predicted - e.global_position
	return to_pred.normalized() if to_pred.length_squared() > 1.0 else fallback

## 开始冲刺（预警结束后调用）：方向到此锁死，之后不再追踪玩家
static func start_charge(e, dir: Vector2) -> void:
	e._charge_active = e.charge_duration
	e._charge_dir = dir
	e._charge_brake = 0.0
	e._charge_stagger = 0.0
	e._charge_hit = false
	e.play_squash(Vector2(0.78, 1.24), 0.2)
	# 起步扬尘：位移是瞬时满速，视觉就得卖「蹬地弹射」而不是「匀速滑出去」
	JuiceEffect.spawn_step_dust(e.get_parent(), e.global_position + Vector2(0, 12), dir)
	# 烈雷兽变异：冲刺起步向左右两侧各放一排火球（犀牛 Mutation 同款）
	if e.charge_side_bolts > 0:
		var base_ang := dir.angle()
		for side in [-1.0, 1.0]:
			for i in range(e.charge_side_bolts):
				var bolt := EnemyBolt.acquire(e.get_parent())
				bolt.global_position = e.global_position
				bolt.direction = Vector2.from_angle(base_ang + side * PI * 0.5 + side * float(i) * 0.22)
				bolt.speed = 300.0 * e.bolt_speed_mult
				bolt.damage = e.bolt_damage * (e.contact_damage / GameBalance.BOLT_DMG_BASE_REF)  # 缩放基准见 BalanceWave.BOLT_DMG_BASE_REF（邪修基础接触伤，四类怪共用）
				bolt.activate()
	e._clear_charge_warning()

## 收势落空判定：要等整段承诺（冲刺 + 刹车）的扫掠都结算完才许罚站。
## 冲刺归零那一帧的命中判定在本函数之后才跑（扫掠在 move_and_slide 之后），
## 在冲刺段末尾判会漏掉"最后一帧才够到人"的那一冲 ⇒ 碾到了还罚站，玩家看不懂。
## 落空才罚站（这是玩家侧身一步的奖励）；碾到人则不罚。
## 链冲（变异烈雷兽）：还有剩余段数就不罚站，改走段间短预警；链尾才按原口径结算。
static func settle_charge_recovery(e) -> void:
	if e._chain_left > 0:
		e._chain_left -= 1
		e._chain_t = GameBalance.MUT_CHILEI_CHAIN_GAP
		return
	if not e._charge_hit and e.charge_whiff_stagger > 0.0:
		e._charge_stagger = e.charge_whiff_stagger
		e.play_squash(Vector2(1.22, 0.78), 0.18)
		# 2026-10-23：罚站起手当帧就把速度钉死。收势刹车走完时 velocity 还有 ~180px/s
		# （brake_k 未完全归零），交给下一帧的 900px/s² 吸附插值刹会滑出 29px ——
		# 判据实测「罚站 0.9s 内位移 29.4px」，与用户口径「罚站就是站桩挨打」相悖。
		e.velocity = Vector2.ZERO
		e.knockback_velocity = Vector2.ZERO

## 更新冲刺预警线（预警期间每帧调用）
static func update_charge_warning(e, player: Node2D) -> void:
	if e._charge_warning_line == null:
		e._charge_warning_line = Line2D.new()
		# 带宽 = 判定走廊直径。Line2D 默认圆头端帽，所以画出来那颗胶囊就是
		# 「玩家中心到本帧扫掠线段 ≤ charge_hit_radius」的点集本身 ⇒ 画多大 == 判多大
		e._charge_warning_line.width = e.charge_hit_radius * 2.0
		e._charge_warning_line.default_color = Color(1.0, 0.4, 0.2, 0.2)
		e.add_child(e._charge_warning_line)

	# 更新端点：画「真撞得到的那一段」，不是画到玩家身上。
	# 旧写法线恒等于当前距离，玩家站在 450px 时线长 450、而冲刺只有 ~307px
	# ⇒ 预告虚报 143px（看得见的那条线必须就是它真能撞到的范围）。
	# 线长与扫掠判定、与判据 ⑧ 的实测位移，三处都取自 GameBalance.charge_reach 这一个式子。
	# 预判型（charge_aim_lead>0）画预判点方向：玩家看线就能读出「它在算我的跑位」，
	# 每帧跟玩家速度更新；末段锁向后改画已锁的 _charge_dir（单位向量 × reach，长度不变）——
	# 线端点定住不再跟人，「线停了」就是「要冲了」。两种态线长都 == 真实可达距离。
	var reach: float = GameBalance.charge_reach(e.move_speed * e.charge_speed_mul, e.charge_duration, e.charge_brake_time)
	var local_target: Vector2
	if e._charge_aim_locked:
		local_target = e._charge_dir * reach
	else:
		var aim_target: Vector2 = player.global_position + player.velocity * e.charge_aim_lead
		local_target = aim_target - e.global_position
		if local_target.length() > reach:
			local_target = local_target.normalized() * reach
	# 原地覆写点 1 位置，避免每帧 clear_points + add_point 重建 PackedVector2Array
	if e._charge_warning_line.get_point_count() < 2:
		e._charge_warning_line.clear_points()
		e._charge_warning_line.add_point(Vector2.ZERO)
		e._charge_warning_line.add_point(local_target)
	else:
		e._charge_warning_line.set_point_position(1, local_target)

	# 闪烁效果：宽带只能压透明度，否则一条带子糊掉半个场地（稀缺反馈预算）。
	# 基线从 0.15 提到 0.20：0.05~0.25 的旧区间在亮地面/密集弹幕里几乎读不出来。
	# 锁向后停闪、定在 0.34（略高于闪烁峰 0.32）：端点停住 + 亮度走稳，
	# 双信号合成「方向已定」的读数。
	var alpha: float = 0.34 if e._charge_aim_locked else 0.20 + 0.12 * sin(e._charge_windup * 12.0)
	e._charge_warning_line.default_color.a = alpha

## 清理预警线
static func clear_charge_warning(e) -> void:
	if e._charge_warning_line != null:
		e._charge_warning_line.queue_free()
		e._charge_warning_line = null
