extends Node

## Boss 震地冲击 / 丹爆自爆 AoE 反馈链判据：
##   1. Boss _cast_slam 后预警圈存在，半径 == GameBalance.BOSS_SLAM_RADIUS（视觉与判定同源）
##   2. 预警推进由 Boss._process 驱动 progress（0.45s/0.9s → 填充 0.5），结算后圈隐藏
##   3. 结算：圈内玩家掉血且池中出现 SHOCKWAVE 冲击波；圈外不掉血但冲击波照放（看得见炸、没被打）
##   4. 丹爆：引信预警圈半径 == explode_radius（同源）；_explode 后出现 SHOCKWAVE 且预警圈引用清理
## 运行: godot --headless --path . res://tests/BossTelegraphCheck.tscn
## 退出码 0 且末行 BOSS_TELEGRAPH_CHECK_RESULT: ALL PASS

var _c := TestCheck.new()

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	GameManager.reset_run()
	await _test_boss_slam_inside()
	await _test_boss_slam_outside()
	await _test_danbao_explode()

	if not _c.all_passed():
		print("BOSS_TELEGRAPH_CHECK_RESULT: FAILED (%d failures)" % _c.failures.size())
		get_tree().quit(1)
	else:
		print("BOSS_TELEGRAPH_CHECK_RESULT: ALL PASS (%d checks)" % _c.passed)
		get_tree().quit(0)

func _make_player() -> Player:
	GameManager.cultivator_id = "jianchi"
	var p_scene: PackedScene = load("res://scenes/entities/Player.tscn")
	var p := p_scene.instantiate() as Player
	add_child(p)
	p.max_health = 99999.0
	p.current_health = 99999.0
	p.invulnerable_time = 0.0
	GameManager.player = p
	return p

func _count_shockwaves() -> int:
	var host := get_tree().current_scene.get_node_or_null("JuiceEffectPool")
	if host == null:
		return 0
	var n := 0
	for child in host.get_children():
		if child is JuiceEffect and child.effect_type == JuiceEffect.EffectType.SHOCKWAVE:
			n += 1
	return n

func _test_boss_slam_inside() -> void:
	var boss_scene: PackedScene = load("res://scenes/entities/BossEnemy.tscn")
	var boss := boss_scene.instantiate() as BossEnemy
	add_child(boss)
	boss.global_position = Vector2(480.0, 270.0)
	boss.move_speed = 0.0

	var p := _make_player()
	p.global_position = Vector2(580.0, 270.0)  # 圈内（判定半径 175，Boss 居中）

	boss._cast_slam()
	_c.check(boss._slam_ring != null, "_cast_slam 后预警圈已创建")
	_c.check(boss._slam_ring.visible, "预警圈可见")
	_c.near(boss._slam_ring.radius, GameBalance.BOSS_SLAM_RADIUS, 0.01, "预警圈半径与判定半径同源（BOSS_SLAM_RADIUS）")
	_c.near(boss._slam_ring.progress, 0.0, 0.01, "预警起始填充进度为 0")

	boss._process(0.45)
	_c.near(boss._slam_ring.progress, 0.5, 0.01, "预警推进 0.45s/0.9s → 填充进度 0.5")

	# 等两帧让 AoeTelegraph 的 _process/_draw 真实跑一遍（绘制路径有错必须在这里爆出来）
	await get_tree().process_frame
	await get_tree().process_frame

	var waves_before := _count_shockwaves()
	var hp_before := p.current_health
	p.invulnerable_time = 0.0
	boss._process(0.5)  # 引信烧完 → 结算
	_c.check(p.current_health < hp_before, "圈内玩家被震地伤害命中（掉血）")
	_c.check(_count_shockwaves() > waves_before, "结算时生成 SHOCKWAVE 扩散冲击波")
	_c.check(not boss._slam_ring.visible, "结算后预警圈隐藏")

	# 再等两帧让 SHOCKWAVE 的 _draw 真实执行一遍
	await get_tree().process_frame
	await get_tree().process_frame

	p.queue_free()
	boss.queue_free()
	GameManager.player = null

func _test_boss_slam_outside() -> void:
	var boss_scene: PackedScene = load("res://scenes/entities/BossEnemy.tscn")
	var boss := boss_scene.instantiate() as BossEnemy
	add_child(boss)
	boss.global_position = Vector2(480.0, 270.0)
	boss.move_speed = 0.0

	var p := _make_player()
	p.global_position = Vector2(780.0, 270.0)  # 圈外（300px，仍在屏内）

	boss._cast_slam()
	var waves_before := _count_shockwaves()
	var hp_before := p.current_health
	boss._process(0.5)
	boss._process(0.5)  # 跨过 0.9s 引信 → 结算
	# 等两帧让 SHOCKWAVE 的 _draw 真实执行一遍
	await get_tree().process_frame
	await get_tree().process_frame
	_c.check(p.current_health == hp_before, "圈外玩家不掉血")
	_c.check(_count_shockwaves() > waves_before, "圈外结算同样有冲击波（看得见炸、确认没被打）")

	p.queue_free()
	boss.queue_free()
	GameManager.player = null

func _test_danbao_explode() -> void:
	var scene: PackedScene = load("res://scenes/entities/DanBaoEnemy.tscn")
	var e := scene.instantiate() as EnemyBase
	add_child(e)
	e.global_position = Vector2(480.0, 270.0)

	_c.check(e.explode_radius > 0.0, "丹爆傀儡 explode_radius > 0（前置）")
	e._ignite_explode_ring()
	_c.check(e._explode_ring != null and e._explode_ring.visible, "引信点燃后预警圈创建且可见")
	_c.near(e._explode_ring.radius, e.explode_radius, 0.01, "丹爆预警圈半径与 explode_radius 同源")
	_c.near(e._explode_ring.progress, 0.0, 0.01, "丹爆预警起始进度 0")

	var p := _make_player()
	p.global_position = Vector2(530.0, 270.0)  # 爆炸半径 90 内
	# 等两帧让预警圈的 _process/_draw 真实跑一遍
	await get_tree().process_frame
	await get_tree().process_frame
	var waves_before := _count_shockwaves()
	var hp_before := p.current_health
	e._explode(p)
	_c.check(p.current_health < hp_before, "爆炸圈内玩家掉血")
	_c.check(_count_shockwaves() > waves_before, "自爆生成 SHOCKWAVE 冲击波")
	_c.check(e._explode_ring == null, "结算后预警圈引用已清理")

	p.queue_free()
	e.queue_free()
	GameManager.player = null
