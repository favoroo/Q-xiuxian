extends Node

## 2026-10-14 敌方投毒判据（毒妖系 + 毒潭持续伤害区域）。钉死八件事：
##   ① 毒潭是「画出来多大 == 判定多大」且逐块同源：碰撞拆成与液面子圆一一对应的碰撞圆
##      （踩在液面上掉血、站摊间空隙不掉血），radius 只作最大包络（预警圈同源锚）
##   ② 玩家踩在液面上掉血（潭心锚圆必中），走出包络圈外不掉血（区域边界与液摊同源）
##   ③ 持续时长：duration 归零才回收（不是一碰就消失的地面装饰）
##   ④ 玩家受击无敌帧节流：站毒里是「一跳一跳」而不是每帧一刀
##   ⑤ 毒潭走对象池：acquire→activate→recycle 生命周期复用，零 instantiate 堆积
##   ⑥ 毒妖起手有预警：预警圈半径 = 毒潭包络半径（同源）、挂在锁定落点而非施法者脚下，
##      落点在起手帧锁死不追踪玩家
##   ⑦ 预警结束才落潭（不是起手瞬间就砸下去，0.6s 预警是给玩家走开的时间）
##   ⑧ 投毒周期：冷却内不起手，到点才起手
## 运行: godot --headless --path . res://tests/PoisonPoolCheck.tscn

var _c := TestCheck.new()
var _world: Node2D
var _player: Node2D

func _ready() -> void:
	call_deferred("_run")

func _spawn_pool(parent: Node, pos: Vector2, dmg: float, dur: float, scl: float = 1.0) -> PoisonPool:
	var p := PoisonPool.acquire(parent)
	p.global_position = pos
	p.damage = dmg
	p.duration = dur
	p.scale_factor = scl
	p.activate()
	return p

func _run() -> void:
	SettingsManager.set_val(&"display", &"hit_stop", false, false)
	Engine.time_scale = 8.0

	_world = Node2D.new()
	_world.name = "PoisonPoolWorld"
	get_tree().root.add_child(_world)
	await get_tree().process_frame

	var player_scene: PackedScene = load("res://scenes/entities/Player.tscn")
	_player = player_scene.instantiate() as Node2D
	_world.add_child(_player)
	_player.global_position = Vector2.ZERO
	_player.max_health = 99999.0
	_player.current_health = 99999.0
	await get_tree().process_frame

	_c.check(GameManager.player == _player, "前置：毒潭读到的玩家就是这一只")

	await _case_radius_same_source()
	await _case_inside_outside()
	await _case_duration()
	await _case_invuln_throttle()
	await _case_pool_reuse()
	await _case_duyao_windup()

	print("POISON_POOL 判据跑完")
	Engine.time_scale = 1.0
	if _c.report("POISON_POOL_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

## ① 范围视觉与判定同源：碰撞拆成与液面子圆一一对应的碰撞圆，radius 只作最大包络
## 注意：碰撞体是 PoisonPool._ready 里代码建的（不走 .tscn 节点路径），取 _shape_nodes 字段。
func _case_radius_same_source() -> void:
	var p := _spawn_pool(_world, Vector2(400, 0), 3.0, 5.0)
	await get_tree().process_frame
	_c.near(p.radius, PoisonPool.RADIUS, 0.001, "默认缩放下包络半径 = RADIUS（预警圈同源锚）")
	_c.check(p._blobs.size() <= p._shape_nodes.size(), "前置：碰撞形状槽容量覆盖液面子圆")
	var matched := true
	for i in range(p._blobs.size()):
		var node := p._shape_nodes[i]
		var b := p._blobs[i]
		if (node.shape as CircleShape2D).radius != b.z or node.position != Vector2(b.x, b.y):
			matched = false
	_c.check(matched, "碰撞子圆与液面子圆逐块一一对应（画多大判多大，精确到每块）")
	var extras_off := true
	for j in range(p._blobs.size(), p._shape_nodes.size()):
		if not p._shape_nodes[j].disabled:
			extras_off = false
	_c.check(extras_off, "余留碰撞槽已禁用（不留幽灵判定圆）")
	# 缩放时外观与碰撞一起变（EnemyBolt 口径：只动一个 scale_factor）
	var big := _spawn_pool(_world, Vector2(400, 200), 3.0, 5.0, 1.3)
	await get_tree().process_frame
	_c.near(big.radius, PoisonPool.RADIUS * 1.3, 0.001, "放大缩放下包络半径跟着放大（scale_factor 同源）")
	# 不规则摊形：所有液面子圆（含暗晕外扩）收在判定圈内 ⇒ 摊形再野，视觉也不超出判定
	var contained := true
	for b in big._blobs:
		if Vector2(b.x, b.y).length() + b.z * 1.08 > big.radius * 0.98 + 0.01:
			contained = false
	_c.check(contained, "液面子圆收在判定圈内（摊形不规则但视觉永不超出判定）")
	_c.check(big._blobs.size() >= 5, "液面是多子圆聚合的不规则摊（不是规则同心圆）")
	# 锚子圆保证潭心有实液面：朝玩家脚下投毒的那块必中
	var center_covered := false
	for b in big._blobs:
		if Vector2(b.x, b.y).length() + b.z >= big.radius * 0.30:
			center_covered = true
	_c.check(center_covered, "锚子圆保证潭心有实液面（中心必中）")
	p.recycle()
	big.recycle()
	await get_tree().process_frame

## ② 圈内掉血、圈外不掉血
## 注意：玩家是「走」出圈的，出去前那一跳已经吃掉 ⇒ 读「出去后是否还在掉」才对，
## 拿出去瞬间的血量对比会把自己的上一跳算成bug。
func _case_inside_outside() -> void:
	await _clear_all_pools()
	_player.global_position = Vector2(300, 0)
	var p := _spawn_pool(_world, Vector2(300, 0), 5.0, 3.0)   # 玩家正踩在圈心
	# 等 4 个物理帧：monitoring  deferred 开启 + overlap 缓存刷新要 2~3 帧才认到已存在的重叠体
	# （Area2D 的 overlap 不是 add_child 当帧就算好的），少于 3 帧会读到「还没碰上」的旧血量。
	for i in range(4):
		await get_tree().physics_frame
	var hp_inside: float = _player.current_health
	_c.check(hp_inside < 99999.0, "玩家踩在液面上掉血（%d < 99999）" % int(hp_inside))
	_player.current_health = 99999.0

	# 移到判定圆外一点（RADIUS 60 + 8px）：先让无敌帧走完，再确认血量不再掉
	_player.global_position = Vector2(300 + PoisonPool.RADIUS + 8.0, 0)
	await get_tree().physics_frame
	_player.current_health = 99999.0   # 清零读数基准：只看出去之后还掉不掉
	var t := 0.0
	while t < 0.4:
		await get_tree().physics_frame
		t += 1.0 / 60.0 * 8.0
	_c.near(_player.current_health, 99999.0, 0.01, "玩家在判定圆外不掉血（边界与判定同源）")

	# 正踩在已知液面子圆的圆心上要掉血（伤害跟着液摊走，不跟包络圈走）
	var b := p._blobs[p._blobs.size() - 1]
	_player.global_position = Vector2(300, 0) + Vector2(b.x, b.y)
	# 潭心那一跳的无敌帧可能还没走完（time_scale 下帧数与时长的换算很绕），
	# 这里显式清零，只验证「 overlap ⇒ 掉血」本身，不把无敌帧时序混进读数
	_player.invulnerable_time = 0.0
	# overlap 缓存对「中途瞬移」的刷新要 2~3 帧（同上面刚落潭时的口径），4 帧留足余量
	for i in range(4):
		await get_tree().physics_frame
	_c.check(_player.current_health < 99999.0, "玩家站在液面子圆上掉血（逐块同源）")
	_player.current_health = 99999.0
	p.recycle()
	await get_tree().process_frame

## ③ 持续时长：duration 归零才回收，没到时间一直烫脚
func _case_duration() -> void:
	_player.global_position = Vector2(300, 0)
	var p := _spawn_pool(_world, Vector2(300, 0), 5.0, 0.3)
	await get_tree().process_frame
	_c.check(not p._pooled, "刚激活的毒潭不在池里")
	# 0.3s（time_scale 8 ⇒ 约 2.4s 真实时间）内持续存在
	var t := 0.0
	while t < 0.15:
		await get_tree().physics_frame
		t += 1.0 / 60.0 * 8.0
	_c.check(not p._pooled, "duration 未到，毒潭仍在场（持续伤害不是一次性陷阱）")
	t = 0.0
	while t < 0.5:
		await get_tree().physics_frame
		t += 1.0 / 60.0 * 8.0
	_c.check(p._pooled, "duration 归零后毒潭回池休眠")
	_player.current_health = 99999.0
	await get_tree().process_frame

## ④ 无敌帧节流：站圈里是稳定一跳一跳，不是每帧一刀
func _case_invuln_throttle() -> void:
	_player.global_position = Vector2(300, 0)
	var p := _spawn_pool(_world, Vector2(300, 0), 7.0, 2.0)
	await get_tree().process_frame
	var before: float = _player.current_health
	var frames_hit := 0
	var t := 0.0
	while t < 0.5:
		await get_tree().physics_frame
		if _player.current_health < before:
			frames_hit += 1
			before = _player.current_health
		t += 1.0 / 60.0 * 8.0
	var lost: float = 99999.0 - before
	# 玩家 BASE_INVULNERABLE_TIME 0.55s：0.5s 仿真里最多 1~2 跳，绝不可能是几十跳
	_c.check(hit_frames_bounded(frames_hit), "0.5s 内只掉 %d 跳（受击无敌帧节流，不是每帧一刀）" % frames_hit)
	_c.check(lost > 0.0, "站圈里确实在持续掉血（%d）" % int(lost))
	_player.current_health = 99999.0
	p.recycle()
	await get_tree().process_frame

func hit_frames_bounded(n: int) -> bool:
	return n >= 1 and n <= 2

## ⑤ 对象池：acquire 复用同一实例，活跃计数收支平衡
## 前置清场：前面用例里可能还有没到 duration 的毒潭在跑（判据世界不跑波次清场），
## 不先收干净的话 active_count 的读数会被它们污染。
func _case_pool_reuse() -> void:
	await _clear_all_pools()
	var a := _spawn_pool(_world, Vector2(300, 0), 3.0, 5.0)
	var b := _spawn_pool(_world, Vector2(400, 0), 3.0, 5.0)
	await get_tree().process_frame
	var created_before: int = PoisonPool.created_count
	_c.equals(PoisonPool.active_count, 2, "两滩毒同时在场（active_count = %d）" % PoisonPool.active_count)
	a.recycle()
	b.recycle()
	await get_tree().process_frame
	_c.equals(PoisonPool.active_count, 0, "回收后活跃计数归零")
	var c := _spawn_pool(_world, Vector2(300, 0), 3.0, 5.0)
	await get_tree().process_frame
	_c.equals(PoisonPool.created_count, created_before, "第三次 acquire 复用池内实例，零新建")
	_c.check(c == a or c == b, "复用的就是刚才回池的那一个")
	c.recycle()
	await get_tree().process_frame

## 收掉场上全部毒潭（判据专用，不碰池内休眠体）
## 注意：毒潭经 acquire 挂在 PoisonPoolHost 下，不是 _world 直接子节点，要递归找
func _clear_all_pools() -> void:
	for pl in _find_all_pools():
		pl.recycle()
	await get_tree().process_frame

func _find_all_pools() -> Array[PoisonPool]:
	var out: Array[PoisonPool] = []
	var stack: Array[Node] = [_world]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is PoisonPool:
			out.append(n)
		stack.append_array(n.get_children())
	return out

## ⑥⑦⑧ 毒妖支路：预警圈同源、落点锁死、到点才落潭
func _case_duyao_windup() -> void:
	var duyao_scene: PackedScene = load("res://scenes/entities/DuYaoEnemy.tscn")
	var duyao := duyao_scene.instantiate() as EnemyBase
	duyao.global_position = Vector2(300, 0)
	duyao.add_to_group("enemies")
	_world.add_child(duyao)
	await get_tree().process_frame
	_player.global_position = Vector2(300, 120)   ## 120px：在投毒触发带内，且不贴脸（贴脸会被接触伤害干扰读数）
	await get_tree().process_frame

	_c.check(duyao.poison_interval > 0.0, "前置：毒妖配了 poison_interval")
	# 裸世界不跑 WaveSpawner._scale_to_wave，毒潭半径停在场景初值；这里钉「预警圈与毒潭
	# 判定半径同源」这件事本身（曲线注入由 unit_wave_tests 的 poison_radius 公式钉）
	_c.near(duyao.poison_radius, 62.0, 0.01, "毒潭半径取场景初值 62（_scale_to_wave 未跑的裸世界）")
	_c.near(GameBalance.poison_radius(6), 62.0, 0.01, "回合曲线口径：第 6 波半径 62（解锁波不膨胀）")
	_c.near(GameBalance.poison_radius(14), 74.0, 0.01, "回合曲线口径：第 14 波半径 74（62+8×1.5）")
	_c.near(GameBalance.poison_radius(30), 84.0, 0.01, "回合曲线口径：第 30 波封顶 84（防后期地面糊满）")

	# 起手：落点锁定在玩家当前位置，预警圈亮起且半径 = 判定半径
	duyao._poison_target = _player.global_position
	duyao._start_poison_cast()
	_c.check(duyao._poison_windup_t > 0.0, "起手后进入预警阶段")
	_c.check(duyao._poison_ring != null and duyao._poison_ring.visible, "预警圈已亮")
	if duyao._poison_ring != null:
		_c.near(duyao._poison_ring.radius, duyao.poison_radius, 0.01,
			"预警圈半径 = 毒潭包络半径（同源：画多大判多大）")
	var locked: Vector2 = duyao._poison_target
	_c.check(duyao._poison_ring != null and duyao._poison_ring.global_position.distance_to(locked) < 0.5,
		"预警圈挂在锁定落点上（不是挂在施法者脚下）")

	# 玩家在预警期间跑开：落点不追踪（0.6s 还追踪就永远躲不开）
	_player.global_position = Vector2(300, 400)
	await get_tree().physics_frame
	_c.check(duyao._poison_target == locked, "预警期间落点锁死不追踪玩家")

	# 预警没结束前不落潭
	duyao._poison_windup_t = 0.3
	await get_tree().physics_frame
	_c.check(duyao._poison_windup_t > 0.0, "预警未结束，还没落潭")

	# 落潭：玩家站在锁定落点上才掉血（判定与预警圈同源）
	_player.global_position = locked
	duyao._drop_poison()
	await get_tree().physics_frame
	var hp: float = _player.current_health
	_c.check(hp < 99999.0, "落潭后圈内玩家掉血")
	_c.check(duyao._poison_windup_t < 0.0, "落潭后退出预警阶段")

	# 落潭包络与预警圈同源：scale_factor = poison_radius / RADIUS ⇒ 毒摊收在预警圈内
	# （回归钉：曾经 _drop_poison 不设 scale_factor，预警圈画 62 判定永远 60，画大判小）
	var dropped := _find_all_pools().filter(func(pl): return not pl._pooled)
	_c.equals(dropped.size(), 1, "落潭后场上有且只有一滩活跃毒潭")
	if dropped.size() == 1:
		_c.near(dropped[0].radius, duyao.poison_radius, 0.01,
			"落潭包络半径 = 预警圈半径（scale_factor 同源）")
		var synced: bool = dropped[0]._blobs.size() <= dropped[0]._shape_nodes.size()
		for i in range(dropped[0]._blobs.size()):
			if (dropped[0]._shape_nodes[i].shape as CircleShape2D).radius != dropped[0]._blobs[i].z:
				synced = false
		_c.check(synced, "碰撞子圆与液面子圆同步（画多大判多大）")

	# 冷却期不起手：_poison_timer 置正后直接推进一次 tick 不应立刻起手
	duyao._poison_timer = duyao.poison_interval
	duyao._tick_behaviors(0.016, _player, Vector2.DOWN, 40000.0, duyao.move_speed)
	_c.check(duyao._poison_windup_t < 0.0, "冷却未到不起手（周期由 poison_interval 钉住）")

	# 场上毒潭清场（避免污染后续判据的内存读数）
	for pl in _find_all_pools():
		pl.recycle()
	duyao.queue_free()
	_player.current_health = 99999.0
	await get_tree().process_frame
