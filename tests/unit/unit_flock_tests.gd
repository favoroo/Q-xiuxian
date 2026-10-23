class_name UnitFlockTests
extends UnitTestsBase

## 单测模块：敌群集行为（分离排斥 / 包围方位）与近战扑咬几何（2026-10-23 新增）。
##
## 判据只碰纯函数与状态机本体，不搭场景：
##   EnemyFlock.separation_push / orbit_dir / combine  —— static 纯函数，可直接断言
##   EnemyLunge 三段状态机 —— RefCounted，可直接 new 出来逐帧 tick
##   BalanceCombat.lunge_reach / lunge_params —— 几何闭式解与敌种配表
## 真实物理链路（前扑真位移、真咬到人）由 tests/MeleeLungeCheck.tscn 场景判据钉住。

func _test_flock_separation() -> void:
	# 分离排斥：贴得越近推得越狠、濒死个体不占位、封顶不吃叠加
	var radius := GameBalance.FLOCK_SEPARATION_RADIUS
	var max_push := 100.0
	var me := Vector2.ZERO

	# ① 无邻居 → 零推力（不许给空场里的怪凭空加力）
	EnemyFlock.invalidate_grid()
	_c.near(EnemyFlock.separation_push(me, [], 1, radius, max_push).length(), 0.0, EPS,
		"空邻居表 → 零推力")

	# ② 单邻居在正右方 → 向左推
	var fake := FakeNeighbor.new(Vector2(10, 0), false)
	EnemyFlock.invalidate_grid()
	var push := EnemyFlock.separation_push(me, [fake], 1, radius, max_push)
	_c.check(push.x < 0.0, "邻居在右 → 被向左推（实得 x=%.2f）" % push.x)
	_c.check(push.length() <= max_push + EPS, "单邻居推力不超过上限")

	# ③ 距离越近推力越大（同向单邻居，10px vs 30px）
	var near_n := FakeNeighbor.new(Vector2(10, 0), false)
	var far_n := FakeNeighbor.new(Vector2(30, 0), false)
	EnemyFlock.invalidate_grid()
	var p_near := EnemyFlock.separation_push(me, [near_n], 1, radius, max_push)
	EnemyFlock.invalidate_grid()
	var p_far := EnemyFlock.separation_push(me, [far_n], 1, radius, max_push)
	_c.check(p_near.length() > p_far.length(),
		"越近推得越狠（10px=%.1f > 30px=%.1f）" % [p_near.length(), p_far.length()])

	# ④ 超出半径的邻居完全不参与
	var out_n := FakeNeighbor.new(Vector2(radius + 5.0, 0), false)
	EnemyFlock.invalidate_grid()
	_c.near(EnemyFlock.separation_push(me, [out_n], 1, radius, max_push).length(), 0.0, EPS,
		"半径外邻居不推")

	# ⑤ 濒死个体不占位（它已不在战术盘面上，还推人会把同伴顶开）
	var dying_n := FakeNeighbor.new(Vector2(10, 0), true)
	EnemyFlock.invalidate_grid()
	_c.near(EnemyFlock.separation_push(me, [dying_n], 1, radius, max_push).length(), 0.0, EPS,
		"濒死个体不参与推挤")

	# ⑥ 自身不计入（instance_id 相同）
	var self_n := FakeNeighbor.new(Vector2(5, 0), false)
	EnemyFlock.invalidate_grid()
	_c.near(EnemyFlock.separation_push(me, [self_n], self_n.get_instance_id(), radius, max_push).length(),
		0.0, EPS, "自己不会推自己")

	# ⑦ 四邻夹击时推力封顶（归一化封顶：多只挤在一处不会叠成失控推力）
	var ring: Array = []
	for i in range(4):
		ring.append(FakeNeighbor.new(Vector2.from_angle(float(i) * TAU / 4.0) * 6.0, false))
	EnemyFlock.invalidate_grid()
	var p_ring := EnemyFlock.separation_push(me, ring, 1, radius, max_push)
	_c.check(p_ring.length() <= max_push + EPS,
		"四邻夹击推力仍不超上限（实得 %.2f）" % p_ring.length())

	# ⑧ 强度为 0 时整条支路关闭（平衡兜底开关）
	_c.near(EnemyFlock.separation_push(me, [fake], 1, radius, 0.0).length(), 0.0, EPS,
		"max_push=0 → 零推力（可整条关闭）")

	# ⑨ 合速度夹回步速：转向不许变成无限加速（留 15% 余量摊队形，但绝不失控）
	var v := EnemyFlock.combine(Vector2(100, 0), Vector2(0, 100), 100.0)
	_c.near(v.length(), 100.0 * EnemyFlock.COMBINE_SLACK, 0.01,
		"合速度夹回 max_speed × SLACK（分离不会造出无限加速怪）")
	var v_slow := EnemyFlock.combine(Vector2(40, 0), Vector2(0, 30), 100.0)
	_c.near(v_slow.length(), 50.0, 0.01, "未超上限时合速度原样保留")
	_c.check(EnemyFlock.COMBINE_SLACK <= 1.15, "SLACK 不超过 1.15（与场景判据的超速阈值同口径）")

func _test_flock_orbit() -> void:
	# 包围方位：偏置旋转追击方向、混入切向、正负决定包抄侧
	var dir := Vector2.RIGHT
	var bias_pos := GameBalance.FLOCK_ORBIT_BIAS_MAX
	var d_pos := EnemyFlock.orbit_dir(dir, bias_pos, GameBalance.FLOCK_ORBIT_TANGENT)
	var d_neg := EnemyFlock.orbit_dir(dir, -bias_pos, GameBalance.FLOCK_ORBIT_TANGENT)
	_c.check(is_equal_approx(d_pos.length(), 1.0), "包抄方向是单位向量")
	_c.check(d_pos.y > 0.0 and d_neg.y < 0.0,
		"正偏置向下绕、负偏置向上绕（%s vs %s）" % [str(d_pos), str(d_neg)])
	# 偏置为 0 → 原方向（不改变直冲）
	var d0 := EnemyFlock.orbit_dir(dir, 0.0, 0.5)
	_c.check(d0.is_equal_approx(dir), "偏置为 0 → 保持原追击方向")
	# 退化方向不产生 NaN
	var dz := EnemyFlock.orbit_dir(Vector2.ZERO, 0.3, 0.5)
	_c.check(dz.is_equal_approx(Vector2.ZERO), "零向量输入 → 原样返回（不产生 NaN）")
	# 偏置上限不超过常量（防止走成纯绕圈）
	_c.check(absf(GameBalance.FLOCK_ORBIT_BIAS_MAX) < PI * 0.5,
		"包抄偏置上限小于 90°（不至于绕成纯切向）")

func _test_lunge_geometry() -> void:
	# 前扑位移闭式解：峰速 × 时长
	_c.near(BalanceCombat.lunge_reach(210.0, 0.16), 210.0 * 0.16, EPS,
		"前扑位移 = 峰速 × 扑击时长")
	_c.near(BalanceCombat.lunge_reach(-50.0, 0.2), 0.0, EPS, "负峰速不产生负位移")
	_c.near(BalanceCombat.lunge_reach(200.0, 0.0), 0.0, EPS, "零时长位移为零")
	# 只给纯接触怪配扑咬，有别的招式的怪一律不配（否则招式叠叠）
	var should_lunge := ["slime", "flower", "fengqun", "xueyong"]
	var should_not := ["xiexiu", "danbao", "duyao", "guyao", "lingyi", "zhumu",
		"leibeast", "chilei_elite", "jiansha_elite", "golem", "yingmei", "jinchan", "boss"]
	for eid in should_lunge:
		_c.check(not BalanceCombat.lunge_params(eid).is_empty(), "%s 配了扑咬" % eid)
	for eid in should_not:
		_c.check(BalanceCombat.lunge_params(eid).is_empty(), "%s 不配扑咬（已有其他招式/特殊行为）" % eid)
	# 配表数值自洽：前扑距离必须够跨过下沿与目标半径，否则扑了也咬不到
	for eid in should_lunge:
		var p: Dictionary = BalanceCombat.lunge_params(eid)
		_c.check(float(p["dash"]) > 0.0, "%s 扑击时长 > 0" % eid)
		_c.check(float(p["speed_mul"]) > 1.0, "%s 前扑峰速高于常规移速" % eid)
		_c.check(float(p["recover"]) > 0.0, "%s 有收势窗口（给玩家反打）" % eid)
		_c.check(float(p["cooldown"]) > 0.0, "%s 有冷却" % eid)
	# 起手上限必须落在「扑得到」的范围内（这条钉住「有招式却永远咬不到」的回归）
	for speed in [85.0, 92.0, 105.0, 115.0, 120.0, 138.0, 168.0]:
		for eid in should_lunge:
			var p2: Dictionary = BalanceCombat.lunge_params(eid)
			var peak: float = speed * float(p2["speed_mul"])
			var reach: float = BalanceCombat.lunge_reach(peak, float(p2["dash"]))
			var engage: float = BalanceCombat.lunge_engage_range(peak, float(p2["dash"]))
			_c.check(engage <= reach + BalanceCombat.LUNGE_CONTACT_MARGIN + EPS,
				"%s @%.0fpx/s：起手上限不超出「前扑位移 + 接触余量」（engage %.1f / reach %.1f）"
					% [eid, speed, engage, reach])

func _test_lunge_state_machine() -> void:
	# 三段状态机：站蹲可打断 → 前扑锁速度 → 收势 → 冷却
	var l := EnemyLunge.new()
	l.configure(BalanceCombat.lunge_params("slime"))
	var move_speed := 105.0

	# ① 太近/太远都不起手
	_c.check(l.tick(0.016, BalanceCombat.LUNGE_MIN_RANGE - 10.0, Vector2.RIGHT, move_speed, false) == Vector2.ZERO,
		"贴脸（低于下沿）不起手")
	_c.check(l.phase == EnemyLunge.Phase.IDLE, "贴脸时仍在待机段")
	var engage := BalanceCombat.lunge_engage_range(move_speed * float(l.params["speed_mul"]),
		float(l.params["dash"]))
	_c.check(l.tick(0.016, engage + 10.0, Vector2.RIGHT, move_speed, false) == Vector2.ZERO,
		"超出起手上限（%.0fpx）不起手" % engage)
	_c.check(l.phase == EnemyLunge.Phase.IDLE, "超远时仍在待机段")

	# ② 进入跑道 → 前摇（取跑道中点，保证落在 [下沿, 起手上限] 内）
	var mid := (BalanceCombat.LUNGE_MIN_RANGE + engage) * 0.5
	l.tick(0.016, mid, Vector2.RIGHT, move_speed, false)
	_c.check(l.phase == EnemyLunge.Phase.WINDUP, "进入跑道 → 站蹲前摇")
	_c.check(l.is_rooted(), "前摇段是原地钉住")
	_c.near(l.charge_progress(), 0.0, 0.01, "刚起手时进度为 0（蓄力读数从零起）")
	l.tick(0.05, mid, Vector2.RIGHT, move_speed, false)
	var prog_a := l.charge_progress()
	_c.check(prog_a > 0.0 and prog_a < 1.0, "前摇进度随帧推进在 (0,1) 内（实得 %.2f）" % prog_a)

	# ③ 前摇被硬直打断
	l.tick(0.016, mid, Vector2.RIGHT, move_speed, true)
	_c.check(l.phase == EnemyLunge.Phase.IDLE, "前摇挨打即取消（不做被钉着还扑出来）")
	_c.check(l.cooldown_t > 0.0, "打断后进入完整冷却（不是打折：否则打断反而让它更快再来）")

	# ④ 冷却走完 → 重新进前摇（冷却归零那一帧就会起手，同一帧内完成）→ 走完 → 前扑
	var guard := 0
	while l.phase == EnemyLunge.Phase.IDLE and guard < 600:
		l.tick(0.016, mid, Vector2.RIGHT, move_speed, false)
		guard += 1
	_c.check(l.phase == EnemyLunge.Phase.WINDUP, "冷却走完 → 重新站蹲")
	guard = 0
	while l.phase == EnemyLunge.Phase.WINDUP and guard < 200:
		l.tick(0.016, mid, Vector2.RIGHT, move_speed, false)
		guard += 1
	_c.check(l.phase == EnemyLunge.Phase.DASH, "前摇走完 → 前扑段")
	_c.check(l.is_dashing(), "前扑段是锁定位移段")
	var dash_vel := l.tick(0.016, mid, Vector2.RIGHT, move_speed, false)
	_c.near(dash_vel.length(), move_speed * float(l.params["speed_mul"]), 0.01,
		"前扑速度 = 移速 × speed_mul")
	# 前扑段不被硬直夺走（commit-through）
	var dash_vel_stunned := l.tick(0.016, mid, Vector2.RIGHT, move_speed, true)
	_c.near(dash_vel_stunned.length(), dash_vel.length(), 0.01,
		"前扑段被硬直也不中断（承诺段）")

	# ⑤ 前扑位移积分 == lunge_reach（帧率无关：末帧零头也要算进去）
	# 用全新状态机量位移 —— 上面的速度断言已经消耗了前两帧，同一实例接着量会少算。
	for frame_len in [0.016, 0.033]:
		var lm := EnemyLunge.new()
		lm.configure(BalanceCombat.lunge_params("slime"))
		lm.tick(0.016, mid, Vector2.RIGHT, move_speed, false)
		guard = 0
		while lm.phase == EnemyLunge.Phase.WINDUP and guard < 400:
			lm.tick(0.016, mid, Vector2.RIGHT, move_speed, false)
			guard += 1
		var expected_reach := lm.reach()
		var travelled := 0.0
		guard = 0
		while lm.phase == EnemyLunge.Phase.DASH and guard < 400:
			var vm := lm.tick(frame_len, mid, Vector2.RIGHT, move_speed, false)
			travelled += vm.length() * frame_len
			guard += 1
		_c.near(travelled, expected_reach, 0.5,
			"%.0ffps 帧长下前扑位移 == lunge_reach（%.2f vs %.2f）" % [1.0 / frame_len, travelled, expected_reach])

	# ⑥ 收势 → 冷却 → 待机（先把主实例的扑击段走完）
	guard = 0
	while l.phase == EnemyLunge.Phase.DASH and guard < 400:
		l.tick(0.016, mid, Vector2.RIGHT, move_speed, false)
		guard += 1
	_c.check(l.phase == EnemyLunge.Phase.RECOVER, "扑完进入收势段")
	_c.check(l.is_rooted(), "收势段原地停住")
	guard = 0
	while l.phase == EnemyLunge.Phase.RECOVER and guard < 200:
		l.tick(0.016, mid, Vector2.RIGHT, move_speed, false)
		guard += 1
	_c.check(l.phase == EnemyLunge.Phase.IDLE, "收势走完回到待机")
	_c.check(l.cooldown_t > 0.0, "回待机后进入冷却")
	# 冷却期内即使进跑道也不起手
	l.tick(0.016, mid, Vector2.RIGHT, move_speed, false)
	_c.check(l.phase == EnemyLunge.Phase.IDLE, "冷却未满不起手")

	# ⑦ reset 清空（池化复用不许带上一命段位）
	l.reset()
	_c.check(l.phase == EnemyLunge.Phase.IDLE and l.cooldown_t == 0.0, "reset 清空段位与冷却")

## 假的邻居节点：只提供 separation_push 需要的两个读口（get_instance_id / global_position / dying）
class FakeNeighbor:
	extends Node2D
	var dying: bool = false
	func _init(pos: Vector2, is_dying: bool) -> void:
		global_position = pos
		dying = is_dying
