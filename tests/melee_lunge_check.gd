extends Node

## 近战扑咬判据（2026-10-23）：纯接触怪从「撞上来」升级为「扑上来」之后，钉死六件事：
##   ① 只有纯接触怪配了扑咬（有长扑/弹幕/震地/引信/投毒/召唤/闪现/恒逃的怪一律不配，不许招式叠叠）
##   ② 出生缓冲：刚出场不立刻扑（玩家有反应窗）
##   ③ 前摇站定：前摇段位移为零，且 special_state 在 (0,1) 内推进（渲染器据此画蓄力）
##   ④ 前摇可打断：挨打就取消，不进前扑段（不做「被钉着还扑出来」）
##   ⑤ 前扑真位移 == BalanceCombat.lunge_reach（画多大冲多远，帧率无关）
##   ⑥ 静止玩家在扑击走廊内必被咬到（伤害走既有接触结算，不新增伤害通道）
##
## 运行: godot --headless --path . res://tests/MeleeLungeCheck.tscn
## 退出码 0 且末行 MELEE_LUNGE_RESULT: ALL PASS
## 反例（回归时必红）：
##   - 把扑咬挂到雷兽/邪修等有招式的怪上 ⇒ ① 报红
##   - 前扑位移改回「按时间推进」⇒ ⑤ 在 60Hz 下少约 30% 报红
##   - 前摇不可打断 ⇒ ④ 报红
##   - 前扑不再产生位移（只做形变）⇒ ⑥ 报红

const MAX_WAIT_FRAMES := 900  ## 史莱姆 105px/s，132px 外走近到跑道约 1s，再等前摇+前扑，900 帧留足余量

var _c := TestCheck.new()
var _world: Node2D
var _player: Player

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	# 判据只关心位移与扣血：关顿帧（不落盘）、时间缩放钉 1.0（避免帧采样窗被拉长）
	SettingsManager.set_val(&"display", &"hit_stop", false, false)
	Engine.time_scale = 1.0
	GameManager.reset_run()

	_world = Node2D.new()
	_world.name = "MeleeLungeWorld"
	get_tree().root.add_child(_world)
	await get_tree().process_frame

	_player = load("res://scenes/entities/Player.tscn").instantiate() as Player
	_world.add_child(_player)
	_player.global_position = Vector2.ZERO
	await get_tree().process_frame

	_c.check(GameManager.player == _player, "前置：敌人读到的玩家就是这一只")
	_c.check(not GameManager.is_game_over, "前置：对局未结束（否则怪不动）")

	await _case_first_life_activate_before_tree()
	await _case_config_coverage()
	await _case_windup_rooted_and_interruptible()
	await _case_dash_reach()
	await _case_bite()

	print("MELEE_LUNGE_CHECK 判据跑完")
	Engine.time_scale = 1.0
	if _c.report("MELEE_LUNGE_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

## ⓪ 刷怪口真实顺序回归：acquire → reset_for_reuse → activate → add_child。
## activate 跑在 _ready 之前时 _eid 还没解析，旧写法会让首命新实例 lunge=null
## （只有死过回池的复用体才有扑咬，第 1 波全员不扑）。这里直接按刷怪口顺序复现。
func _case_first_life_activate_before_tree() -> void:
	var scene: PackedScene = load("res://scenes/entities/SlimeEnemy.tscn")
	var e := EnemyBase.acquire_or_new(scene)
	_c.check(e != null, "池口取到史莱姆实例")
	if e == null:
		return
	e.reset_for_reuse()
	e.activate()  # 刷怪口顺序：activate 先于 add_child（此时 _ready 尚未跑）
	_c.check(e.lunge != null, "首命新实例在进树前 activate 也装配了扑咬（刷怪口时序回归）")
	# 不经过 add_child，直接释放：_poolable 个体尚未入池，free 干净
	e.free()

## ① 配表覆盖：只给纯接触怪
func _case_config_coverage() -> void:
	var lunge_ids := ["slime", "flower", "fengqun", "xueyong"]
	var no_lunge_ids := ["xiexiu", "danbao", "duyao", "guyao", "lingyi", "zhumu",
		"leibeast", "chilei_elite", "jiansha_elite", "golem", "yingmei", "jinchan"]
	for eid in lunge_ids:
		_c.check(not BalanceCombat.lunge_params(eid).is_empty(), "%s 配了扑咬" % eid)
	for eid in no_lunge_ids:
		_c.check(BalanceCombat.lunge_params(eid).is_empty(),
			"%s 不配扑咬（已有其他招式/特殊行为，不叠招式）" % eid)

## ②③④ 出生缓冲 / 前摇站定 / 前摇可打断
func _case_windup_rooted_and_interruptible() -> void:
	var e := _spawn("res://scenes/entities/SlimeEnemy.tscn", Vector2(70.0, 0.0))
	_c.check(e.lunge != null, "史莱姆实例装配了扑咬状态机")
	if e.lunge == null:
		e.queue_free()
		return

	# 出生缓冲：activate 当帧冷却有值，不立刻扑
	_c.check(e.lunge.cooldown_t > 0.0 or e.lunge.phase == EnemyLunge.Phase.IDLE,
		"出场瞬间不立刻进前扑段（出生缓冲）")

	# 等它起手（进入 WINDUP）
	var entered_windup := false
	var pos_at_windup := Vector2.ZERO
	for i in range(MAX_WAIT_FRAMES):
		await get_tree().physics_frame
		if not is_instance_valid(e) or e.dying:
			break
		if e.lunge.phase == EnemyLunge.Phase.WINDUP:
			entered_windup = true
			pos_at_windup = e.global_position
			break
	_c.check(entered_windup, "史莱姆走进跑道后进入站蹲前摇")
	if entered_windup:
		# 前摇段位移必须为零（站桩预警是承诺段之前的读法，不能一边走一边蓄）
		var windup_pos_start := e.global_position
		var prog_seen := 0.0
		var moved := 0.0
		for i in range(12):
			await get_tree().physics_frame
			if not is_instance_valid(e) or e.dying:
				break
			if e.lunge.phase != EnemyLunge.Phase.WINDUP:
				break
			prog_seen = maxf(prog_seen, e.lunge.charge_progress())
			moved = maxf(moved, e.global_position.distance_to(windup_pos_start))
		_c.check(moved < 2.0, "前摇段原地站定（位移 %.2f px < 2px）" % moved)
		_c.check(prog_seen > 0.0, "前摇进度在推进（special_state 有读数，实得 %.2f）" % prog_seen)

		# 前摇可打断：给一次硬直，必须取消
		if e.lunge.phase == EnemyLunge.Phase.WINDUP:
			e.take_damage(1.0, Vector2.RIGHT * 40.0, false)
			await get_tree().physics_frame
			await get_tree().physics_frame
			_c.check(e.lunge.phase == EnemyLunge.Phase.IDLE,
				"前摇挨打即取消（不做被钉着还扑出来）")
	e.queue_free()
	await get_tree().process_frame

## ⑤⑥ 前扑真位移 == lunge_reach；静止玩家在走廊内必被咬到
func _case_dash_reach_and_bite() -> void:
	# 放在「前扑刚好够得着」的距离起手（与 BalanceCombat.lunge_engage_range 同源，不写死像素）
	var probe_speed := 105.0
	var probe_params: Dictionary = BalanceCombat.lunge_params("slime")
	var engage := BalanceCombat.lunge_engage_range(
		probe_speed * float(probe_params["speed_mul"]), float(probe_params["dash"]))
	var start := Vector2((BalanceCombat.LUNGE_MIN_RANGE + engage) * 0.5, 0.0)
	var e := _spawn("res://scenes/entities/SlimeEnemy.tscn", start)
	if e.lunge == null:
		_c.fail("史莱姆实例装配了扑咬状态机（配置覆盖用例已报，这里不再重复）")
		e.queue_free()
		return

## ⑤ 前扑自由空跑位移 == lunge_reach（玩家主动让开，量纯位移）
func _case_dash_reach() -> void:
	var probe_speed := 105.0
	var probe_params: Dictionary = BalanceCombat.lunge_params("slime")
	var engage := BalanceCombat.lunge_engage_range(
		probe_speed * float(probe_params["speed_mul"]), float(probe_params["dash"]))
	var start := Vector2((BalanceCombat.LUNGE_MIN_RANGE + engage) * 0.5, 0.0)
	var e := _spawn("res://scenes/entities/SlimeEnemy.tscn", start)
	if e.lunge == null:
		_c.fail("史莱姆实例装配了扑咬状态机（配置覆盖用例已报，这里不再重复）")
		e.queue_free()
		return

	var dash_start_pos := Vector2.ZERO
	var dash_end_pos := Vector2.ZERO
	var saw_dash := false
	var dir_at_dash := Vector2.ZERO
	for i in range(MAX_WAIT_FRAMES):
		await get_tree().physics_frame
		if not is_instance_valid(e) or e.dying:
			break
		if e.lunge.is_dashing():
			if not saw_dash:
				saw_dash = true
				dash_start_pos = e.global_position
				dir_at_dash = e.lunge.dir
				# 量「自由空跑」位移：起手当帧把玩家挪出走廊，避免敌人被碰撞体顶住只走 25px
				_player.global_position = Vector2(0.0, 420.0)
			dash_end_pos = e.global_position
		elif saw_dash:
			break

	_c.check(saw_dash, "史莱姆真的进入前扑段（不是只做形变）")
	if saw_dash:
		var expected: float = BalanceCombat.lunge_reach(e.move_speed * float(e.lunge.params["speed_mul"]),
			float(e.lunge.params["dash"]))
		var actual := dash_start_pos.distance_to(dash_end_pos)
		_c.near(actual, expected, 2.0,
			"前扑自由空跑位移 == lunge_reach（%.1f vs %.1f）" % [actual, expected])
		# 前扑方向必须朝起手时的玩家方位（不许背身扑）
		var toward: Vector2 = dash_start_pos - Vector2(start.x - 60.0, 0.0)
		_c.check(dir_at_dash.x < -0.3,
			"前扑方向朝玩家（玩家在左侧，dir.x=%.2f 应为负）" % dir_at_dash.x)

	# 收势段也必须原地钉住：旧写法只归零期望速度，DASH 末帧的残余速度
	# 会被 900px/s² 吸附刹车带出滑行尾巴，实际总位移超出 lunge_reach。
	var recover_pos := Vector2.ZERO
	var recover_moved := 0.0
	var saw_recover := false
	for i in range(120):
		await get_tree().physics_frame
		if not is_instance_valid(e) or e.dying:
			break
		if e.lunge.phase == EnemyLunge.Phase.RECOVER:
			if not saw_recover:
				saw_recover = true
				recover_pos = e.global_position
			recover_moved = maxf(recover_moved, e.global_position.distance_to(recover_pos))
		elif saw_recover:
			break
	_c.check(saw_recover, "扑完进入收势段")
	if saw_recover:
		_c.check(recover_moved < 2.0, "收势段原地钉住（位移 %.2f px < 2px，不拖滑行尾巴）" % recover_moved)
	e.queue_free()
	_player.global_position = Vector2.ZERO
	await get_tree().process_frame

## ⑥ 静止玩家在扑击走廊内必被咬到
func _case_bite() -> void:
	var probe_speed := 105.0
	var probe_params: Dictionary = BalanceCombat.lunge_params("slime")
	var engage := BalanceCombat.lunge_engage_range(
		probe_speed * float(probe_params["speed_mul"]), float(probe_params["dash"]))
	var start := Vector2((BalanceCombat.LUNGE_MIN_RANGE + engage) * 0.5, 0.0)
	var e := _spawn("res://scenes/entities/SlimeEnemy.tscn", start)
	if e.lunge == null:
		e.queue_free()
		return

	var hp_before: float = _player.current_health
	var bit := false
	var saw_dash := false
	for i in range(MAX_WAIT_FRAMES):
		await get_tree().physics_frame
		if not is_instance_valid(e) or e.dying:
			break
		if e.lunge.is_dashing():
			saw_dash = true
		if _player.current_health < hp_before:
			bit = true
			break

	_c.check(saw_dash, "扑咬确实进入前扑段（不是只做形变）")
	_c.check(bit, "静止玩家在扑击走廊内被咬到（伤害走既有接触结算，未新增伤害通道）")
	if bit:
		var expected: float = GameBalance.incoming_damage(e.contact_damage, GameManager.get_effective_armor())
		var actual: float = hp_before - _player.current_health
		_c.near(actual, expected, 0.01, "扑咬伤害与 contact_damage 同源（不是另起一档伤害）")
	e.queue_free()

func _spawn(scene_path: String, pos: Vector2) -> EnemyBase:
	var scene: PackedScene = load(scene_path)
	var e := scene.instantiate() as EnemyBase
	e.global_position = pos
	e.add_to_group("enemies")
	_world.add_child(e)
	# 摆到跑道里需要先走一段：activate 已由 _ready 调用
	return e
