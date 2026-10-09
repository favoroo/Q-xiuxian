extends Node

## 回复珠（回春葫芦 / 残丹）拾取判据（真实 Main 场景，不打 mock）
##   ① 隔空不入口：珠子在 96 px 摄灵圈里、但没压上身体 → 不飞、不被吸、血不动
##      （对照：同一格灵石照旧被隔空吸走，证明不是判据环境坏了）
##   ② 贴身才入口：把人压上去 → 当场吃掉，按缺血回血
##   ③ 满血贴身也不入口：压成灰相留在原地；压着不动掉血（不会有第二次 body_entered）
##      由接触期每帧复检抓到
##   ④ 不追人：贴着满血葫芦走开后再掉血 → 珠子留在原地不动
##   ⑤ 回不上的那截折灵石：缺血 5 吃 18 → 回 5 + 溢出 13 折成灵石
##   ⑥ 波末结算走生产入口（WaveSpawner.end_wave 遍历 gems 组）：满血没捡到的葫芦请进袖中，
##      血一点不涨、溢出 18 点折 14 灵石（与藏宝匣金灵石那一路同档）
##   ⑦ heal() 诚实：满血回不涨血、残血精确封顶
## 运行: godot --headless --path . res://tests/HealOrbCheck.tscn
##       godot --headless --path . res://tests/HealOrbCheck.tscn -- --selftest
##       反例把旧写法复刻两遍（隔空就吸 / 波末吞了不折钱），证明 ①⑥ 不是空枪

const EPS := 0.6              ## 血量断言容差
const STONE_EPS := 0.5        ## 灵石是整数，留半个的容差只为一眼看出差在哪
const AIR_GAP := 70.0         ## 圈内（96）身外（~32）的悬空距离
const FAR_AWAY := 300.0       ## 明显既不在圈里也不贴身

var _c := TestCheck.new()
var _player: Player

func _ready() -> void:
	get_tree().root.size = Vector2i(960, 540)
	call_deferred("_run")

func _dismiss() -> void:
	for node_name in ["LevelUpDialog", "WaveShop", "PlayerStatsDialog", "PauseMenu", "SettingsDialog"]:
		var n := get_node_or_null("/root/Main/UILayer/" + node_name)
		if n != null and n.visible:
			n.visible = false
	get_tree().paused = false

func _settle(frames: int) -> void:
	for i in range(frames):
		await get_tree().physics_frame
		_dismiss()

func _run() -> void:
	var main = load("res://scenes/main/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await _settle(2)
	GameManager.cultivator_id = ""
	GameManager.start_run("qingyun_sword")
	await _settle(2)
	_player = GameManager.player as Player
	_c.check(_player != null, "玩家已生成")
	if _player == null:
		_quit()
		return
	_quiet_arena()
	await _settle(4)
	_quiet_arena()
	_c.check(get_tree().get_nodes_in_group("enemies").is_empty(), "场地已静音（没有妖物会来改血量）")
	_c.check(AIR_GAP < _player.pickup_radius() and AIR_GAP > _contact_dist(),
		"布置成立：%.0f px 确实在摄灵圈（%.0f）里、身体接触线（%.0f）外" % [
			AIR_GAP, _player.pickup_radius(), _contact_dist()])
	_c.check(_orb_judge_radius() > 0.0 and _judge_radius(_player) > 0.0,
		"尺子活着：珠子与玩家的判定圆都从节点读到了（读到 -1 就是量了个空）")

	if "--selftest" in OS.get_cmdline_user_args():
		await _selftest()
	else:
		await _main_cases()
	_quit()

## 场地静音：刷怪器不再出人、场上妖物散掉，血量只由本判据自己写
func _quiet_arena() -> void:
	var spawner: Node = GameManager.wave_spawner
	if spawner != null:
		spawner.set_process(false)
		spawner.set_physics_process(false)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is EnemyBase:
			enemy.dissolve()
	GameManager.hp_regen = 0.0
	GameManager.synergy_hp_regen = 0.0

func _main_cases() -> void:
	# ---- ① 隔空不入口（+ 灵石对照）----
	_set_hp(0.5)
	var stones_before := GameManager.spirit_stones
	var orb := _spawn_orb(AIR_GAP, 0.15, 0.0)
	var orb_home: Vector2 = orb.global_position
	var gem := _spawn_gem(AIR_GAP)
	await _settle(10)
	_c.check(not _eaten(orb), "隔空：葫芦没被吃掉")
	_c.check(orb.target_player == null, "隔空：葫芦也没起飞（不追人）")
	_c.near(orb.global_position.distance_to(orb_home), 0.0, 1.0, "隔空：葫芦在原地一动没动")
	_c.near(_player.current_health, _player.max_health * 0.5, EPS + 1.0, "隔空：血没动")
	_c.equals(GameManager.spirit_stones - stones_before, 0, "隔空：也没偷偷折灵石")
	_c.check(gem.target_player != null, "对照：同一格的灵石照旧被隔空吸走（问题不在判据环境）")

	# ---- 画多大 == 判多大：缩了画幅就必须连判定圆一起缩，与晶石用同一把尺子 ----
	_c.near(_judge_radius(orb), _judge_radius(gem), 0.5,
		"判定圆与晶石同尺（%.0f）：不许画小了还按大圈判" % _judge_radius(gem))
	_c.near(_drawn_width(orb), _drawn_width(gem), 4.0,
		"画出来 %.0f px 宽，与晶石 %.0f px 同档" % [_drawn_width(orb), _drawn_width(gem)])

	# ---- ② 贴身才入口 ----
	_step_on(orb)
	await _settle(4)
	_c.check(_eaten(orb), "贴身：压上去当场入口")
	_c.near(_player.current_health, _player.max_health * 0.5 + _player.max_health * 0.15,
		EPS + 1.0, "贴身：回满 15% 最大气血（缺血够，不该折钱）")

	# ---- ③ 满血贴身不入口 + 压着掉血自动入口 ----
	_set_hp(1.0)
	var watch := _spawn_orb(0.0, 0.15, 0.0)
	_step_on(watch)
	await _settle(4)
	_c.check(not _eaten(watch), "满血贴身：也不入口")
	_c.check(watch.waiting_full_hp, "满血贴身：转入待命")
	_c.equals(watch._sprite.modulate, HealOrb.TINT_WAITING, "满血贴身：压成灰相，看得出它现在不催你")
	_set_hp(0.8)   # 压着葫芦挨一刀：不会有第二次 body_entered
	await _settle(4)
	_c.check(_eaten(watch), "压着葫芦掉血：接触期每帧复检抓到这一拍")

	# ---- ④ 走开后不追人 ----
	_set_hp(1.0)
	var leaver := _spawn_orb(0.0, 0.15, 0.0)
	_step_on(leaver)
	await _settle(4)
	leaver.global_position = _player.global_position + Vector2(FAR_AWAY, 0.0)
	await _settle(2)   # 真人是「走出去」，接触名单要一拍才落地；这一拍之后才算 separation
	_c.check(leaver._touching_player() == null, "走开：引擎接触名单里已经没有玩家身体")
	_set_hp(0.5)
	await _settle(12)
	_c.check(not _eaten(leaver) and leaver.target_player == null,
		"走开后再掉血：珠子留在原地，不追着人飞")
	_step_on(leaver)
	await _settle(4)
	_c.check(_eaten(leaver), "再走回去压上：这才入口")

	# ---- ⑤ 回不上的那截折灵石（缺血 5，满口 15%）----
	_set_hp((_player.max_health - 5.0) / _player.max_health)
	var partial_stones := GameManager.spirit_stones
	var partial := _spawn_orb(0.0, 0.15, 0.0)
	_step_on(partial)
	await _settle(4)
	_c.near(_player.current_health, _player.max_health, EPS, "溢出这一格：血只回缺血的那 5 点")
	var want_partial := GameBalance.heal_overflow_stones(_player.max_health * 0.15 - 5.0)
	_c.equals(GameManager.spirit_stones - partial_stones, want_partial,
		"溢出 13 点气血折 %d 灵石" % want_partial)

	# ---- ⑥ 波末结算（生产入口：WaveSpawner.end_wave）----
	_set_hp(1.0)
	var banked := _spawn_orb(FAR_AWAY, 0.15, 0.0)
	var banked_gem := _spawn_gem(FAR_AWAY)
	var end_stones := GameManager.spirit_stones
	# end_wave 里除了结算珠子还会发灵韵（apply_harvest → add_experience 同额进灵石），
	# 那一笔要先按同一条纯函数算出来摘掉，否则量的是两件事的和。
	# 对照用的灵石格也一样：它入袖中时按 exp_value 同时记一笔灵石，读数要在它被 free 前先取走。
	var harvest_payout: int = GameBalance.harvest_gain(GameManager.harvest)
	var gem_payout: int = banked_gem.exp_value
	var spawner: Node = GameManager.wave_spawner
	_c.check(spawner != null and spawner.has_method("end_wave"), "波末结算入口在（WaveSpawner.end_wave）")
	if spawner != null:
		spawner.end_wave()
	await _settle(60)
	_c.check(_eaten(banked), "波末：留在场上的葫芦被请进袖中")
	_c.near(_player.current_health, _player.max_health, EPS, "波末满血：血一点没涨（回无可回）")
	var want_banked := GameBalance.heal_overflow_stones(_player.max_health * 0.15)
	_c.equals(GameManager.spirit_stones - end_stones,
		want_banked + harvest_payout + gem_payout,
		"波末满血：溢出 18 点气血折 %d 灵石（同场结算的灵石格 %d、灵韵 %d 已按同一公式计入）" % [
			want_banked, gem_payout, harvest_payout])
	_c.check(_eaten(banked_gem) or banked_gem.target_player != null, "波末：灵石同样被吸进袖中")

	# ---- ⑦ heal() 诚实 ----
	_set_hp(1.0)
	_player.heal(20.0, true)
	_c.near(_player.current_health, _player.max_health, EPS, "heal：满血回血不涨血")
	_player.current_health = _player.max_health - 7.0
	_player.heal(20.0, true)
	_c.near(_player.current_health, _player.max_health, EPS, "heal：残血精确封顶到上限（不会溢）")

func _spawn_orb(offset_x: float, pct: float, amount: float) -> HealOrb:
	var orb := HealOrb.new()
	orb.heal_pct = pct
	orb.heal_amount = amount
	_player.get_parent().add_child(orb)
	orb.global_position = _player.global_position + Vector2(offset_x, 0.0)
	return orb

func _spawn_gem(offset_x: float) -> AstralGem:
	var gem := preload("res://scenes/entities/AstralGem.tscn").instantiate() as AstralGem
	_player.get_parent().add_child(gem)
	gem.global_position = _player.global_position + Vector2(offset_x, 0.0)
	return gem

## 判定半径：现读子节点里那个圆形碰撞形状。
## 不能按名字取 —— 纯代码建出来的节点是 @CollisionShape2D@57 这种占位名，
## 按名字取会静默走回退值，量到的就不是珠子真正带在身上那一圈。
func _judge_radius(owner: Node) -> float:
	for c in owner.get_children():
		if c is CollisionShape2D and c.shape is CircleShape2D:
			return (c.shape as CircleShape2D).radius
	return -1.0

## 画出来的宽度（图元宽 × sprite 缩放）：缩到多大要看这个，不看常数
func _drawn_width(node: Node) -> float:
	var sp: Sprite2D = null
	if node is AstralGem:
		sp = (node as AstralGem).sprite
	elif node is HealOrb:
		sp = (node as HealOrb)._sprite
	if sp == null or sp.texture == null:
		return -1.0
	return float(sp.texture.get_width()) * sp.scale.x

## 把人压到珠子上（生产里等价于「走过去站住」；珠子自己实现接触判定，不靠玩家摄灵圈）
func _step_on(orb: HealOrb) -> void:
	orb.global_position = _player.global_position

## 身体接触线 = 玩家碰撞圆半径 + 珠子碰撞圆半径（两处都现读节点，不抄常数）
func _contact_dist() -> float:
	return _judge_radius(_player) + _orb_judge_radius()

## 临时建一颗珠子只为量它的判定圆：读数在 free 之前取走，量不到就报 -1（宁可判据红也别哑）
func _orb_judge_radius() -> float:
	var probe := HealOrb.new()
	add_child(probe)
	var r := _judge_radius(probe)
	probe.free()
	return r

func _set_hp(pct: float) -> void:
	_player.current_health = _player.max_health * pct
	GameManager.player_hp_changed.emit(_player.current_health, _player.max_health)

## 珠子是否已被吃掉：queue_free 在帧末真的 free 掉了，直接调方法会打在 freed 实例上。
## 参数故意不标 Node —— 标了类型反而会在传 freed 引用时先炸一次「不是期望类的子类」。
func _eaten(node) -> bool:
	return not is_instance_valid(node) or node.is_queued_for_deletion()

## 反例 A：旧写法 —— 回复珠实现 magnet_to，走进摄灵圈就被隔空吸走
class SuckedOrb extends HealOrb:
	func magnet_to(player: Node2D) -> void:
		if target_player == null:
			target_player = player
			current_speed = -50.0
			if _bob_tween != null and _bob_tween.is_valid():
				_bob_tween.kill()

	func _physics_process(delta: float) -> void:
		if target_player == null or not is_instance_valid(target_player):
			return
		var p := target_player as Player
		if p == null:
			return
		var dist := global_position.distance_to(p.global_position)
		var dir: Vector2 = (p.global_position - global_position).normalized()
		current_speed = minf(max_speed, current_speed + acceleration * delta)
		global_position += dir * current_speed * delta
		if dist < ARRIVE_DIST:
			p.heal(p.max_health * heal_pct)
			queue_free()

## 反例 B：旧写法 —— 波末把葫芦吞了，回不上的那一截直接蒸发（不给灵石）
class UnpaidOrb extends HealOrb:
	func _collect(p: Player) -> void:
		p.heal(p.max_health * heal_pct)
		queue_free()

func _selftest() -> void:
	# 反例 A：① 那一枪必须抓到隔空吸附
	_set_hp(0.5)
	var hp_before: float = _player.current_health
	var bad := SuckedOrb.new()
	bad.heal_pct = 0.15
	_player.get_parent().add_child(bad)
	bad.global_position = _player.global_position + Vector2(AIR_GAP, 0.0)
	await _settle(40)
	_c.check(_eaten(bad) or bad.target_player != null, "反例A① 走进摄灵圈就被隔空吸走：被点名")
	_c.check(_player.current_health > hp_before, "反例A② 人没贴上去血就回了：被点名")

	# 反例 B：⑥ 那一枪必须抓到「吞了不给钱」
	_set_hp(1.0)
	var stones_before := GameManager.spirit_stones
	# end_wave 顺带发的灵韵要先摘掉（与 ⑥ 同一处理），否则量的是两笔的和
	var harvest_a: int = GameBalance.harvest_gain(GameManager.harvest)
	var unpaid := UnpaidOrb.new()
	unpaid.heal_pct = 0.15
	_player.get_parent().add_child(unpaid)
	unpaid.global_position = _player.global_position + Vector2(FAR_AWAY, 0.0)
	var spawner: Node = GameManager.wave_spawner
	if spawner != null:
		spawner.end_wave()
	await _settle(60)
	_c.check(_eaten(unpaid), "反例B① 波末珠子确实被吞掉（不然这一枪量不到东西）")
	_c.equals(GameManager.spirit_stones - stones_before, harvest_a,
		"反例B② 溢出的 18 点气血蒸发了、一块灵石没给（只结了灵韵 %d）" % harvest_a)

	# 正例：同一条尺子换到新珠子上必须真的给钱（不然上面那枪是空枪）
	_set_hp(1.0)
	var paid_before := GameManager.spirit_stones
	var harvest_b: int = GameBalance.harvest_gain(GameManager.harvest)
	var paid := _spawn_orb(FAR_AWAY, 0.15, 0.0)
	if spawner != null:
		spawner.end_wave()
	await _settle(60)
	_c.check(_eaten(paid), "正例B① 新珠子波末也被请进袖中")
	_c.equals(GameManager.spirit_stones - paid_before,
		GameBalance.heal_overflow_stones(_player.max_health * 0.15) + harvest_b,
		"正例B② 溢出的 18 点气血折成 %d 灵石（另结灵韵 %d）" % [
			GameBalance.heal_overflow_stones(_player.max_health * 0.15), harvest_b])

func _quit() -> void:
	var prefix: String = "HEAL_ORB_SELFTEST_RESULT" if "--selftest" in OS.get_cmdline_user_args() else "HEAL_ORB_RESULT"
	if _c.report(prefix):
		get_tree().quit(0)
	else:
		get_tree().quit(1)
