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
	await _test_boss_sky_fire()
	await _test_boss_split_bomb_and_curve()
	await _test_boss_patterns_and_charge()

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
	var host := (GameManager.world_root if GameManager.world_root != null else get_tree().current_scene).get_node_or_null("JuiceEffectPool")
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

func _test_boss_sky_fire() -> void:
	var boss_scene: PackedScene = load("res://scenes/entities/BossEnemy.tscn")
	var boss := boss_scene.instantiate() as BossEnemy
	add_child(boss)
	boss.global_position = Vector2(480.0, 270.0)
	boss.move_speed = 0.0
	boss._attack_timer = 999.0

	var p := _make_player()
	p.global_position = Vector2(620.0, 270.0)
	p.velocity = Vector2.ZERO

	boss._cast_sky_fire(p)
	boss._process(0.01)  # 首颗天火立即落地预警
	_c.check(boss._active_sky_fires.size() == 1, "天火连环首枚预警圈已创建")
	var fire0: Dictionary = boss._active_sky_fires[0]
	var tg0: AoeTelegraph = fire0.telegraph
	_c.check(tg0 != null and is_instance_valid(tg0), "天火预警圈实例有效")
	_c.near(tg0.radius, GameBalance.BOSS_SKY_FIRE_RADIUS, 0.01, "天火预警圈半径与判定半径同源（BOSS_SKY_FIRE_RADIUS）")

	var waves_before := _count_shockwaves()
	var hp_before := p.current_health
	p.invulnerable_time = 0.0
	# 推进 0.86s 使第 1 颗天火结算炸开
	boss._process(0.86)
	_c.check(p.current_health < hp_before, "天火圈内玩家被炸中掉血")
	_c.check(_count_shockwaves() > waves_before, "天火结算生成 SHOCKWAVE 扩散冲击波")

	await get_tree().process_frame
	p.queue_free()
	boss._die()
	boss.queue_free()
	GameManager.player = null

func _test_boss_split_bomb_and_curve() -> void:
	var boss_scene: PackedScene = load("res://scenes/entities/BossEnemy.tscn")
	var boss := boss_scene.instantiate() as BossEnemy
	boss.final_boss = true
	add_child(boss)
	boss.global_position = Vector2(480.0, 270.0)
	boss.move_speed = 0.0
	boss._attack_timer = 999.0

	var p := _make_player()
	p.global_position = Vector2(700.0, 270.0)

	# 1. 测试分裂子母弹
	var active_before := EnemyBolt.active_count
	boss._cast_split_bomb(p)
	var mother_count := GameBalance.BOSS_SPLIT_BOMB_COUNT_FINAL
	_c.equals(EnemyBolt.active_count - active_before, mother_count, "魔尊子母弹发射 %d 颗母弹" % mother_count)

	# 取一颗刚激活的母弹校验半径同源与分裂
	var mother_bolt: EnemyBolt = null
	if EnemyBolt._host != null:
		for child in EnemyBolt._host.get_children():
			if child is EnemyBolt and not child._pooled and child.split_count > 0:
				mother_bolt = child
				break
	_c.check(mother_bolt != null, "池宿主中存在已激活的子母弹母体")
	if mother_bolt != null:
		_c.near(mother_bolt.radius, EnemyBolt.RADIUS * GameBalance.BOSS_SPLIT_BOMB_SCALE, 0.01, "母弹视觉半径与碰撞半径严格同源")
		_c.check(mother_bolt.purple_style, "母弹启用幽紫魔焰配色")
		var count_before_split := EnemyBolt.active_count
		# 推进引信触发原地分裂（母弹 -1，子火球 +8 ⇒ 净增 7）
		mother_bolt._physics_process(GameBalance.BOSS_SPLIT_BOMB_FUSE + 0.05)
		_c.equals(EnemyBolt.active_count - count_before_split, GameBalance.BOSS_SPLIT_BOMB_CHILD_COUNT - 1,
			"母弹到期分裂为 %d 颗子火球并回收母弹" % GameBalance.BOSS_SPLIT_BOMB_CHILD_COUNT)

	# 2. 测试弧线弹偏转与对象池重置
	var curve_bolt := EnemyBolt.acquire(self)
	curve_bolt.global_position = Vector2(200.0, 200.0)
	curve_bolt.direction = Vector2.RIGHT
	curve_bolt.angular_speed = 1.0
	curve_bolt.purple_style = true
	curve_bolt.activate()
	curve_bolt._physics_process(0.5)
	_c.check(curve_bolt.direction.y > 0.3, "弧线火球按 angular_speed 发生顺时针方向旋转")
	curve_bolt._recycle()

	var reused_bolt := EnemyBolt.acquire(self)
	_c.near(reused_bolt.angular_speed, 0.0, 0.001, "火球回池复用后 angular_speed 已归零")
	_c.equals(reused_bolt.split_count, 0, "火球回池复用后 split_count 已归零")
	_c.check(not reused_bolt.purple_style, "火球回池复用后 purple_style 已重置")
	reused_bolt._recycle()

	# 清理在场弹丸
	if EnemyBolt._host != null:
		for child in EnemyBolt._host.get_children():
			if child is EnemyBolt and not child._pooled:
				child._recycle()

	p.queue_free()
	boss.queue_free()
	GameManager.player = null

func _test_boss_patterns_and_charge() -> void:
	var boss_scene: PackedScene = load("res://scenes/entities/BossEnemy.tscn")
	var boss := boss_scene.instantiate() as BossEnemy
	add_child(boss)
	boss.global_position = Vector2(480.0, 270.0)
	boss._attack_timer = 999.0

	var p := _make_player()
	p.global_position = Vector2(720.0, 270.0)

	_c.check(not (BossEnemy.Pattern.SKY_FIRE in boss._patterns), "第 10 波一阶段暂不开放天火轰炸")
	boss._enter_phase2()
	_c.check(BossEnemy.Pattern.SKY_FIRE in boss._patterns and BossEnemy.Pattern.SPIRAL in boss._patterns,
		"半血狂暴解锁追踪天火与螺旋风暴")

	# 测试破阵冲锋预警线宽度与判定同源
	boss._cast_charge(p)
	_c.check(boss._charge_warning_line != null, "Boss 破阵冲锋已生成胶囊预警带")
	if boss._charge_warning_line != null:
		_c.near(boss._charge_warning_line.width, GameBalance.BOSS_CHARGE_HIT_RADIUS * 2.0, 0.01,
			"Boss 冲锋预警带线宽 == 2 × BOSS_CHARGE_HIT_RADIUS（视觉与扫掠同源）")

	p.queue_free()
	boss._die()
	boss.queue_free()
	GameManager.player = null

