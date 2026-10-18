extends Node

## 回复珠（回春葫芦 / 残丹）拾取判据（真实 Main 场景，不打 mock）
##   ① 摄灵圈吸附：残血走入 96 px 摄灵圈 → 当场被吸附入口，按缺血回血（与灵石同待遇）
##   ② 圈外不吸附：珠子在摄灵圈外（300 px）→ 留在原地，等走近后才吸附
##   ③ 满血圈内不吸附：顶满时走入摄灵圈不吸也不入口，压成灰相留在原地；圈内掉血当拍起飞吸附
##   ④ 走开后灰相解除：满血离开摄灵圈恢复可入口相，掉血后再靠近可正常吸附
##   ⑤ 回不上的那截折灵石：缺血 5 吃 18 → 回 5 + 溢出 13 折成灵石
##   ⑥ 波末结算走生产入口（WaveSpawner.end_wave 遍历 gems 组）：满血没捡到的葫芦请进袖中，
##      血一点不涨、溢出 18 点折 14 灵石
##   ⑦ heal() 诚实：满血回不涨血、残血精确封顶
## 运行: godot --headless --path . res://tests/HealOrbCheck.tscn
##       godot --headless --path . res://tests/HealOrbCheck.tscn -- --selftest

const EPS := 0.6              ## 血量断言容差
const STONE_EPS := 0.5        ## 灵石是整数，留半个的容差只为一眼看出差在哪
const AIR_GAP := 70.0         ## 圈内（96）身外（~24）的悬空距离
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
	var orb_r := _orb_judge_radius()
	var body_r := _judge_radius(_player)
	_c.check(orb_r > 0.0 and body_r > 0.0,
		"尺子活着：珠子与玩家的判定圆都从节点读到了（珠 %.0f / 身 %.0f）" % [orb_r, body_r])

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
	# ---- ① 摄灵圈吸附（+ 灵石对照）----
	_set_hp(0.5)
	var stones_before := GameManager.spirit_stones
	var orb := _spawn_orb(AIR_GAP, 0.15, 0.0)
	await _settle(45)
	_c.check(_eaten(orb), "摄灵圈：残血时走入圈内，葫芦被吸附吃掉")
	_c.near(_player.current_health, _player.max_health * 0.5 + _player.max_health * 0.15,
		EPS + 1.0, "摄灵圈：吸附后回满 15% 最大气血（缺血够，不该折钱）")
	_c.equals(GameManager.spirit_stones - stones_before, 0, "摄灵圈：未溢出不折灵石")

	var gem := _spawn_gem(AIR_GAP)
	await _settle(10)
	_c.check(gem.target_player != null, "对照：同一格的灵石同样被吸走")
	gem.queue_free()
	await _settle(2)

	# ---- 画多大 == 判多大：缩了画幅就必须连判定圆一起缩，与晶石用同一把尺子 ----
	var test_gem := _spawn_gem(FAR_AWAY)
	_c.near(_orb_judge_radius(), _judge_radius(test_gem), 0.5,
		"判定圆与晶石同尺（%.0f）：不许画小了还按大圈判" % _judge_radius(test_gem))
	var test_orb := _spawn_orb(FAR_AWAY, 0.15, 0.0)
	_c.near(_drawn_width(test_orb), _drawn_width(test_gem), 4.0,
		"画出来 %.0f px 宽，与晶石 %.0f px 同档" % [_drawn_width(test_orb), _drawn_width(test_gem)])
	test_orb.queue_free()
	test_gem.queue_free()
	await _settle(2)

	# ---- ② 远距离不吸附，走近才吸附 ----
	_set_hp(0.5)
	var far_orb := _spawn_orb(FAR_AWAY, 0.15, 0.0)
	await _settle(10)
	_c.check(not _eaten(far_orb), "远距离：摄灵圈外不吸附")
	_c.check(far_orb.target_player == null, "远距离：葫芦不起飞")
	# 走近：移到摄灵圈内
	far_orb.global_position = _player.global_position + Vector2(AIR_GAP, 0.0)
	await _settle(45)
	_c.check(_eaten(far_orb), "走近后：进入摄灵圈当场吸附入口")

	# ---- ③ 满血圈内不吸附 + 圈内掉血自动吸附 ----
	_set_hp(1.0)
	var watch := _spawn_orb(AIR_GAP, 0.15, 0.0)
	await _settle(6)
	_c.check(not _eaten(watch), "满血圈内：不起飞也不入口")
	_c.check(watch.waiting_full_hp, "满血圈内：转入待命")
	_c.check(not watch._sprite.visible,
		"灰相这把尺子对：sprite 从 _ready 起就隐藏，读它的 modulate 是空枪")
	_c.check(_drawn_waiting(watch), "满血圈内：压成灰相，看得出它现在不催你")
	_set_hp(0.8)   # 圈内挨一刀：每帧复验抓到这一拍并起飞
	await _settle(45)
	_c.check(_eaten(watch), "圈内掉血：每帧复验放行，吸附入口")

	# ---- ④ 走开后不追人 + 灰相不粘人 ----
	_set_hp(1.0)
	var leaver := _spawn_orb(AIR_GAP, 0.15, 0.0)
	await _settle(4)
	_c.check(_drawn_waiting(leaver), "走开前：满血在圈内，它正顶着灰相")
	leaver.global_position = _player.global_position + Vector2(FAR_AWAY, 0.0)
	await _settle(3)
	_c.check(not leaver.waiting_full_hp and not _drawn_waiting(leaver),
		"走开：离开摄灵圈灰相当场解除 —— 这颗现在靠近能回血，不许顶着作废的脸")
	_set_hp(0.5)
	await _settle(10)
	_c.check(not _eaten(leaver) and leaver.target_player == null,
		"远处掉血：珠子在圈外留在原地，不跨全图乱飞")
	_c.check(not _drawn_waiting(leaver), "残血期站在远处看它：仍是可入口相")
	leaver.global_position = _player.global_position + Vector2(AIR_GAP, 0.0)
	await _settle(45)
	_c.check(_eaten(leaver), "走回圈内：这才吸附入口")

	# ---- ⑤ 回不上的那截折灵石（缺血 5，满口 15%）----
	_set_hp((_player.max_health - 5.0) / _player.max_health)
	var partial_stones := GameManager.spirit_stones
	var partial := _spawn_orb(AIR_GAP, 0.15, 0.0)
	await _settle(45)
	_c.check(_eaten(partial), "溢出测试：珠子已被吃掉")
	_c.near(_player.current_health, _player.max_health, EPS, "溢出这一格：血只回缺血的那 5 点")
	var want_partial := GameBalance.heal_overflow_stones(_player.max_health * 0.15 - 5.0)
	_c.equals(GameManager.spirit_stones - partial_stones, want_partial,
		"溢出 13 点气血折 %d 灵石" % want_partial)

	# ---- ⑥ 波末结算（生产入口：WaveSpawner.end_wave）----
	_set_hp(1.0)
	var banked := _spawn_orb(FAR_AWAY, 0.15, 0.0)
	var end_stones := GameManager.spirit_stones
	var harvest_payout: int = GameBalance.harvest_gain(GameManager.harvest)
	var spawner: Node = GameManager.wave_spawner
	_c.check(spawner != null and spawner.has_method("end_wave"), "波末结算入口在（WaveSpawner.end_wave）")
	if spawner != null:
		spawner.set_physics_process(true)
		spawner.end_wave()
	await _settle(60)
	_c.check(_eaten(banked), "波末：留在场上的葫芦被请进袖中")
	_c.near(_player.current_health, _player.max_health, EPS, "波末满血：血一点没涨（回无可回）")
	var want_banked := GameBalance.heal_overflow_stones(_player.max_health * 0.15)
	_c.equals(GameManager.spirit_stones - end_stones,
		want_banked + harvest_payout,
		"波末满血：溢出 18 点气血折 %d 灵石（另结灵韵 %d）" % [want_banked, harvest_payout])

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
func _judge_radius(owner: Node) -> float:
	for c in owner.get_children():
		if c is CollisionShape2D and c.shape is CircleShape2D:
			return (c.shape as CircleShape2D).radius
	return -1.0

## 画出来的宽度（图元宽 × sprite 缩放）
func _drawn_width(node: Node) -> float:
	var sp: Sprite2D = null
	if node is AstralGem:
		sp = (node as AstralGem).sprite
	elif node is HealOrb:
		sp = (node as HealOrb)._sprite
	if sp == null or sp.texture == null:
		return -1.0
	return float(sp.texture.get_width()) * sp.scale.x

## 玩家看得见的那一相：由 _loot_renderer.is_waiting 决定
func _drawn_waiting(orb: HealOrb) -> bool:
	if orb == null or not is_instance_valid(orb):
		return false
	return orb._loot_renderer.is_waiting

## 身体接触线 = 玩家碰撞圆半径 + 珠子碰撞圆半径
func _contact_dist() -> float:
	return _judge_radius(_player) + _orb_judge_radius()

func _orb_judge_radius() -> float:
	var probe := HealOrb.new()
	add_child(probe)
	var r := _judge_radius(probe)
	if r <= 0.0 and probe._shape != null and probe._shape.shape is CircleShape2D:
		r = (probe._shape.shape as CircleShape2D).radius
	probe.free()
	return r

func _set_hp(pct: float) -> void:
	_player.current_health = _player.max_health * pct
	GameManager.player_hp_changed.emit(_player.current_health, _player.max_health)

func _eaten(node) -> bool:
	if not is_instance_valid(node) or node.is_queued_for_deletion():
		return true
	if node is HealOrb and node._pooled:
		return true
	if node is AstralGem and node._pooled:
		return true
	return false

## 反例 A：满血也盲目吸附（白白浪费掉落的治疗）
class BlindFullHpOrb extends HealOrb:
	func magnet_to(player: Node2D) -> void:
		target_player = player
		current_speed = -50.0

## 反例 B：波末把葫芦吞了，回不上的那一截直接蒸发（不给灵石）
class UnpaidOrb extends HealOrb:
	func _collect(p: Player) -> void:
		p.heal(p.max_health * heal_pct)
		queue_free()

## 反例 C：灰相只在进圈时写，走开不再清除，导致走远后依然顶着作废脸
class StickyOrb extends HealOrb:
	func _physics_process(delta: float) -> void:
		var p := GameManager.player as Player
		if p != null and is_instance_valid(p):
			if global_position.distance_to(p.global_position) <= p.pickup_radius():
				if not heal_is_useful(p):
					_set_waiting(true)

func _selftest() -> void:
	# 反例 A：满血盲目吸附应当被识别（正例不吸附）
	_set_hp(1.0)
	var bad := BlindFullHpOrb.new()
	bad.heal_pct = 0.15
	_player.get_parent().add_child(bad)
	bad.global_position = _player.global_position + Vector2(AIR_GAP, 0.0)
	bad.magnet_to(_player)
	_c.check(bad.target_player != null, "反例A① 满血时盲目起飞：被模拟")
	bad.queue_free()
	await _settle(2)

	# 正例 A：正常珠子满血在圈内绝不起飞
	_set_hp(1.0)
	var good := _spawn_orb(AIR_GAP, 0.15, 0.0)
	await _settle(10)
	_c.check(not _eaten(good) and good.target_player == null, "正例A② 正常珠子满血在圈内不起飞留在原地")
	good.queue_free()
	await _settle(2)

	# 反例 C：走开后灰相粘住
	_set_hp(1.0)
	var sticky := StickyOrb.new()
	sticky.heal_pct = 0.15
	_player.get_parent().add_child(sticky)
	sticky.global_position = _player.global_position + Vector2(AIR_GAP, 0.0)
	await _settle(4)
	_c.check(sticky.waiting_full_hp and _drawn_waiting(sticky), "反例C① 满血在圈内压成灰相")
	sticky.global_position = _player.global_position + Vector2(FAR_AWAY, 0.0)
	await _settle(4)
	_c.check(_drawn_waiting(sticky), "反例C② 旧写法走开灰相未清除：被点名")
	sticky.queue_free()
	await _settle(2)

	# 正例 C：走开后灰相正常解除
	_set_hp(1.0)
	var fresh := _spawn_orb(AIR_GAP, 0.15, 0.0)
	await _settle(4)
	_c.check(_drawn_waiting(fresh), "正例C① 满血在圈内压成灰相")
	fresh.global_position = _player.global_position + Vector2(FAR_AWAY, 0.0)
	await _settle(4)
	_c.check(not fresh.waiting_full_hp and not _drawn_waiting(fresh), "正例C② 离开圈后灰相解除")
	fresh.queue_free()
	await _settle(2)

	# 反例 B：波末吞了不给钱
	_set_hp(1.0)
	var stones_before := GameManager.spirit_stones
	var harvest_a: int = GameBalance.harvest_gain(GameManager.harvest)
	var unpaid := UnpaidOrb.new()
	unpaid.heal_pct = 0.15
	_player.get_parent().add_child(unpaid)
	unpaid.global_position = _player.global_position + Vector2(FAR_AWAY, 0.0)
	var spawner: Node = GameManager.wave_spawner
	if spawner != null:
		spawner.set_physics_process(true)
		spawner.end_wave()
	await _settle(60)
	_c.check(_eaten(unpaid), "反例B① 波末珠子确实被吞掉")
	_c.equals(GameManager.spirit_stones - stones_before, harvest_a,
		"反例B② 溢出气血蒸发只结灵韵：被点名")

	# 正例 B：正常珠子波末折钱
	_set_hp(1.0)
	var paid_before := GameManager.spirit_stones
	var harvest_b: int = GameBalance.harvest_gain(GameManager.harvest)
	var paid := _spawn_orb(FAR_AWAY, 0.15, 0.0)
	if spawner != null:
		spawner.set_physics_process(true)
		spawner.end_wave()
	await _settle(60)
	_c.check(_eaten(paid), "正例B① 珠子波末被请进袖中")
	_c.equals(GameManager.spirit_stones - paid_before,
		GameBalance.heal_overflow_stones(_player.max_health * 0.15) + harvest_b,
		"正例B② 溢出气血正确折算成灵石")

func _quit() -> void:
	var prefix: String = "HEAL_ORB_SELFTEST_RESULT" if "--selftest" in OS.get_cmdline_user_args() else "HEAL_ORB_RESULT"
	if _c.report(prefix):
		get_tree().quit(0)
	else:
		get_tree().quit(1)
