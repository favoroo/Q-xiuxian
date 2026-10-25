extends Node

## 祭坛灵兽判据（2026-10-11 远程吐息重做；2026-10-25 祭坛金币启动 + 灵兽寿命重设计，
## 真实 Main 场景，不打 mock）：
##   ① 祭坛触发即召唤：扣费注入爆发后 allies 登记 +1，气血按当前波次取表
##   ② 嘲讽：玩家在反方向远处，敌人仍改追嘲讽圈内的灵兽（替玩家分担火力的牙齿）
##   ③ 吐息与承伤：丹弹打得敌人掉血（灵兽在战斗）；敌人贴近后灵兽也掉血（近身啃咬真咬得到它）
##   ④ 受击无敌帧 + 战死注销：同帧两刀只结算一刀；血量耗尽消散并从 allies 注销
##   ⑤ 跨波存活：end_wave 清场（敌人消散）后灵兽仍在场 —— 血量没耗完就一直在
##   ⑥ 回合寿命：自召唤波起算满 SPIRIT_BEAST_LIFETIME_WAVES（3）个回合，回合开始即消散并注销
## 运行: godot --headless --path . res://tests/SpiritBeastCheck.tscn

const EPS := 0.6

var _c := TestCheck.new()
var _player: Player
var _beast: SpiritBeast

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

func _run() -> void:
	# 判据只关心游戏时间内的行为：祭坛触发走 feedback(HEAVY) 会开顿帧拖慢实测，关掉（不落盘）
	SettingsManager.set_val(&"display", &"hit_stop", false, false)
	Engine.time_scale = 8.0

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
	_c.check(GameManager.live_allies.is_empty(), "前置：场上没有友军（读数干净）")

	await _case_summon()
	if _beast != null:
		await _case_taunt_and_bite()
	await _case_invincible_and_death()
	if _beast != null and is_instance_valid(_beast):
		await _case_cross_wave()
		await _case_lifetime()

	Engine.time_scale = 1.0
	_quit()

## ① 祭坛触发即召唤（直接调生产入口 _begin_infusion：扣费 → 注入 0.45s → 爆发召灵兽），
## 不走 HUD 长按模拟；金币前置给足本回合启动价
func _case_summon() -> void:
	var obelisk := get_node_or_null("/root/Main/MapLayer/ObeliskCenter") as BlessingObelisk
	_c.check(obelisk != null, "① 前置：祭坛节点在（MapLayer/ObeliskCenter，单祭坛）")
	if obelisk == null:
		return
	GameManager.spirit_stones = GameBalance.obelisk_activation_cost(maxi(GameManager.wave_number, 1))
	var stones_before: int = GameManager.spirit_stones
	obelisk._begin_infusion()
	# 等注入 tween 走完（0.45s 游戏秒）→ _release_blessing 召灵兽
	await _settle(60)
	_c.check(GameManager.spirit_stones == stones_before - GameBalance.obelisk_activation_cost(maxi(GameManager.wave_number, 1)),
		"① 启动扣走本回合启动价金币（剩 %d）" % GameManager.spirit_stones)
	_c.equals(GameManager.live_allies.size(), 1, "① 祭坛触发：allies 登记 +1")
	if GameManager.live_allies.is_empty():
		return
	_beast = GameManager.live_allies[0] as SpiritBeast
	_c.check(_beast != null, "① 召唤物确实是 SpiritBeast")
	if _beast == null:
		return
	_c.check(_beast.is_in_group("allies") and not _beast.is_in_group("enemies"),
		"① 灵兽挂 allies 组且没混进 enemies（混进去会被波末清场）")
	_c.near(_beast.current_hp, GameBalance.spirit_beast_max_hp(maxi(GameManager.wave_number, 1)), EPS,
		"① 气血按当前波次取表（%.0f）" % GameBalance.spirit_beast_max_hp(maxi(GameManager.wave_number, 1)))

## ② 嘲讽 + ③ 吐息与承伤
func _case_taunt_and_bite() -> void:
	# 玩家挪到灵兽反方向远处：敌人若还往玩家走，读数会当场反掉
	_player.global_position = _beast.global_position + Vector2(-400.0, 0.0)
	var slime := _spawn_slime(_beast.global_position + Vector2(150.0, 0.0))
	_c.check(slime != null, "② 前置：妖物已生成")
	if slime == null:
		return
	slime.max_hp = 99999.0     ## 挡住吐息致死，只观察走位与承伤
	slime.current_hp = 99999.0
	_c.check(150.0 < GameBalance.SPIRIT_BEAST_TAUNT_RADIUS, "② 布置成立：敌人在嘲讽圈内")
	await _settle(2)
	var x_before: float = slime.global_position.x
	# 嘲讽观察窗：妖物朝灵兽追（x 减小）。灵兽风筝后撤的方向与妖物来向一致，窗口内读数稳定
	await _settle(20)
	_c.check(is_instance_valid(slime), "② 观察窗内妖物还在")
	if not is_instance_valid(slime):
		return
	_c.check(slime.global_position.x < x_before - 5.0,
		"② 嘲讽：玩家在 -400 方向，妖物仍朝灵兽（x 减小方向）追（%.0f → %.0f）" % [x_before, slime.global_position.x])

	# ③ 吐息：灵兽远程丹弹打得妖物掉血（弹速 380 + 追踪，风筝走位下命中率有保障）
	await _settle(150)
	_c.check(is_instance_valid(slime), "③ 观察窗内妖物还在")
	if is_instance_valid(slime):
		_c.check(slime.current_hp < 99999.0, "③ 吐息：妖物被灵兽丹弹打掉血（%.0f）" % slime.current_hp)
	# ③ 承伤：灵兽 150 移速风筝甩得开 110 的小怪，自然追不上——
	# 直接把妖物贴脸传送进近身啃咬圈，验证「无碰撞体积后敌人贴近仍咬得到灵兽」
	if is_instance_valid(slime):
		slime.global_position = _beast.global_position + Vector2(10.0, 0.0)
		await _settle(4)
	_c.check(_beast.current_hp < _beast.max_hp, "③ 承伤：妖物贴近后灵兽被近身啃咬掉血（%.0f / %.0f）" % [_beast.current_hp, _beast.max_hp])

## ④ 受击无敌帧 + 战死注销（另召一只干净的，不与 ① 那只的承伤读数打架）
func _case_invincible_and_death() -> void:
	var beast2 := (load("res://scenes/entities/SpiritBeast.tscn") as PackedScene).instantiate() as SpiritBeast
	_player.get_parent().add_child(beast2)
	beast2.global_position = _player.global_position + Vector2(60.0, 0.0)
	await _settle(2)
	_c.check(GameManager.live_allies.has(beast2), "④ 前置：第二只灵兽已登记")
	beast2.take_damage(10.0)
	beast2.take_damage(10.0)   # 无敌帧内第二刀：敌人接触是逐帧结算，没这层帧灵兽一秒被磨没
	_c.near(beast2.current_hp, beast2.max_hp - 10.0, EPS, "④ 受击无敌帧：同帧两刀只结算一刀")
	beast2._invincible_timer = 0.0
	beast2.take_damage(99999.0)
	_c.check(beast2._dying, "④ 血量耗尽进入消散")
	await _settle(40)
	_c.check(not is_instance_valid(beast2), "④ 战死：节点已消散")
	_c.check(not GameManager.live_allies.has(beast2), "④ 战死：已从 allies 注销")

## ⑤ 跨波存活：end_wave 清场四组（敌人消散为证），灵兽不在其中 ⇒ 血量没耗完就一直在
func _case_cross_wave() -> void:
	var spawner: Node = GameManager.wave_spawner
	_c.check(spawner != null and spawner.has_method("end_wave"), "⑤ 前置：波末结算入口在（WaveSpawner.end_wave）")
	if spawner == null:
		return
	spawner.end_wave()
	await _settle(60)
	_c.check(get_tree().get_nodes_in_group("enemies").is_empty(), "⑤ 对照：场上妖物已被波末清场")
	_c.check(is_instance_valid(_beast) and not _beast.is_queued_for_deletion(),
		"⑤ 跨波存活：灵兽血量没耗完，波末清场后仍在场")
	_c.check(GameManager.live_allies.has(_beast), "⑤ 跨波存活：allies 登记仍在")

## ⑥ 回合寿命（2026-10-25 重设计）：寿命内跨波不散，满 SPIRIT_BEAST_LIFETIME_WAVES
## 个回合后的回合开始（wave_changed）即消散并注销 —— 直接调灵兽自己的寿命闸，不广播假波次
func _case_lifetime() -> void:
	_c.check(is_instance_valid(_beast), "⑥ 前置：灵兽还在场")
	if not is_instance_valid(_beast):
		return
	# 寿命内最后一回合开始：仍在场
	_beast._on_wave_changed(_beast.summon_wave + GameBalance.SPIRIT_BEAST_LIFETIME_WAVES - 1)
	await _settle(2)
	_c.check(is_instance_valid(_beast) and not _beast._dying,
		"⑥ 寿命内：第 %d 回合开始仍在场（召唤波 %d）" % [
				GameBalance.SPIRIT_BEAST_LIFETIME_WAVES, _beast.summon_wave])
	# 满寿命回合开始：消散 + 注销
	_beast._on_wave_changed(_beast.summon_wave + GameBalance.SPIRIT_BEAST_LIFETIME_WAVES)
	await _settle(60)
	_c.check(not is_instance_valid(_beast), "⑥ 寿命尽头：灵兽已消散")
	_c.check(not GameManager.live_allies.has(_beast), "⑥ 寿命尽头：已从 allies 注销")

func _spawn_slime(pos: Vector2) -> EnemyBase:
	var slime: EnemyBase = (load("res://scenes/entities/SlimeEnemy.tscn") as PackedScene).instantiate() as EnemyBase
	_player.get_parent().add_child(slime)
	slime.global_position = pos
	return slime

func _quit() -> void:
	if _c.report("SPIRITBEAST_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)
