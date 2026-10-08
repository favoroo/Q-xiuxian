class_name WaveSpawner
extends Node2D

## 波次状态机：WAITING(选法器) → FIGHT → CLEARING(清场吸附) → SHOP → 下一波
## 第 20 波通关「渡劫成功」（双精英心魔劫）；可继续无尽

enum Phase { WAITING, FIGHT, CLEARING, SHOP }

@export var max_enemies: int = 55

var phase: int = Phase.WAITING
## 波次号的唯一来源是 GameManager.wave_number。
## 这里只留一个只读访问器：以前本地也存了一份，只有 start_wave 会同步写，
## 「继续无尽」等路径只改单例那份，两边会悄悄漂移，所以改成同一份数据。
var wave_number: int:
	get:
		return GameManager.wave_number
var wave_timer: float = 0.0
var clear_timer: float = 0.0
var spawn_timer: float = 0.0
var elite_spawned: bool = false

var slime_scene: PackedScene = preload("res://scenes/entities/SlimeEnemy.tscn")
var flower_scene: PackedScene = preload("res://scenes/entities/FlowerEnemy.tscn")
var golem_scene: PackedScene = preload("res://scenes/entities/GolemEnemy.tscn")
var leibeast_scene: PackedScene = preload("res://scenes/entities/LeiBeastEnemy.tscn")
var xiexiu_scene: PackedScene = preload("res://scenes/entities/XieXiuEnemy.tscn")
var danbao_scene: PackedScene = preload("res://scenes/entities/DanBaoEnemy.tscn")
var boss_scene: PackedScene = preload("res://scenes/entities/BossEnemy.tscn")

var _boss_ref: BossEnemy = null  ## 本波魔君引用（Boss 波超时锁关轮询用）
var _overtime_noted: bool = false

func _ready() -> void:
	GameManager.wave_spawner = self
	GameManager.shop_closed.connect(_on_shop_closed)

func _process(delta: float) -> void:
	if GameManager.is_game_over:
		return
	match phase:
		Phase.WAITING:
			if GameManager.run_started and GameManager.player != null:
				start_wave(1)
		Phase.FIGHT:
			_process_fight(delta)
		Phase.CLEARING:
			clear_timer -= delta
			if clear_timer <= 0.0:
				_open_shop()
		Phase.SHOP:
			pass

func _process_fight(delta: float) -> void:
	var player = GameManager.player
	if player == null:
		return

	wave_timer -= delta
	spawn_timer -= delta

	# Boss 波超时锁关：魔君未死则妖潮不退（停表停刷，等 Boss 伏诛再进结算）
	if GameBalance.is_boss_wave(wave_number) and wave_timer <= 0.0:
		if _boss_still_alive():
			if not _overtime_noted:
				_overtime_noted = true
				GameManager.announcement_triggered.emit("⚠ 魔君未除 · 妖潮不退 ⚠")
			return
		end_wave()
		return

	if spawn_timer <= 0.0:
		spawn_timer = GameBalance.spawn_interval(wave_number)
		_spawn_regular(player)

	# 精英波：第 5/15 波；Boss 波（第 10/20 波）改由魔君登场
	var is_elite_wave := _is_elite_wave(wave_number)
	if not _is_boss_wave(wave_number) and is_elite_wave and not elite_spawned and wave_timer < wave_duration(wave_number) - 1.5:
		elite_spawned = true
		_spawn_elite(player)

	# 固定 Boss 波：开场 1.5s 后魔君破阵（血条同步上屏）
	if _is_boss_wave(wave_number) and not elite_spawned and wave_timer < wave_duration(wave_number) - 1.5:
		elite_spawned = true
		_spawn_boss(player)

	if wave_timer <= 0.0:
		end_wave()

## 波长曲线只是 GameBalance 的一层转发，保留本方法是因为 UI/内部多处按它排程
func wave_duration(n: int) -> float:
	return GameBalance.wave_duration(n)

## 精英波判定（曲线在 GameBalance）：第 5/15 波，无尽模式 20 波后每 3 波（Boss 波让位）
func _is_elite_wave(n: int) -> bool:
	return GameBalance.is_elite_wave(n, GameManager.endless_mode)

## Boss 波判定（固定关卡）：第 10/20 波，无尽每 10 波
func _is_boss_wave(n: int) -> bool:
	return GameBalance.is_boss_wave(n)

func start_wave(n: int) -> void:
	GameManager.wave_number = n
	GameManager.wave_changed.emit(n)
	elite_spawned = false
	_boss_ref = null
	_overtime_noted = false
	wave_timer = wave_duration(n)
	spawn_timer = 0.6
	phase = Phase.FIGHT
	_spawn_herbs()
	if _is_boss_wave(n):
		GameManager.announcement_triggered.emit("✦ 第 %d 波 · 魔君压境 ✦" % n)
		AudioManager.play_sfx("boss_raid", 0.9)
		AudioManager.play_bgm_key("trial")
	elif _is_elite_wave(n):
		GameManager.announcement_triggered.emit("✦ 第 %d 波 · 妖潮来袭 ✦" % n)
		AudioManager.play_sfx("boss_raid", 0.9)
		AudioManager.play_bgm_key("trial")
	else:
		GameManager.announcement_triggered.emit("✦ 第 %d 波 · 妖潮来袭 ✦" % n)
		AudioManager.play_sfx("wave_start", 0.9)
		AudioManager.play_bgm_key("battle")

## 灵药丛：每波在竞技场随机位置刷 2~4 丛，诱导玩家为补给冒险走位
func _spawn_herbs() -> void:
	var player = GameManager.player
	if player == null:
		return
	var count := mini(2 + int(wave_number / 6.0), 4)
	var lim := GameManager.MAP_HALF_EXTENT - 160.0
	for i in range(count):
		var herb := SpiritHerb.new()
		var pos := Vector2(GameManager.rng.randf_range(-lim, lim), GameManager.rng.randf_range(-lim, lim))
		if pos.distance_to(player.global_position) < 150.0:
			pos += Vector2(220.0, 0.0)
		herb.global_position = pos
		get_parent().add_child(herb)

func end_wave() -> void:
	phase = Phase.CLEARING
	clear_timer = 1.0
	AudioManager.play_sfx("wave_clear", 0.9)
	GameManager.announcement_triggered.emit("第 %d 波妖潮平息" % wave_number)
	# 灵韵结算：无偿灵石+修为，随后复利增长
	GameManager.apply_harvest()
	# 余怪消散（不掉落）
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is EnemyBase:
			enemy.dissolve()
	# 地上灵石/残丹全部吸附给玩家
	var player = GameManager.player
	if player != null:
		for gem in get_tree().get_nodes_in_group("gems"):
			if gem.has_method("magnet_to"):
				gem.magnet_to(player)

func _open_shop() -> void:
	phase = Phase.SHOP
	if wave_number >= GameManager.VICTORY_WAVE and not GameManager.endless_mode:
		GameManager.trigger_game_over(true)
		return
	_open_shop_inner()

func open_shop() -> void:
	## 结算界面「继续无尽」入口
	if phase == Phase.SHOP:
		_open_shop_inner()

func _open_shop_inner() -> void:
	AudioManager.play_bgm_key("shop")
	GameManager.roll_shop(true)
	GameManager.shop_opened.emit()

func _on_shop_closed() -> void:
	start_wave(wave_number + 1)

func _spawn_regular(player: Node2D) -> void:
	var enemy_count = get_tree().get_nodes_in_group("enemies").size()
	if enemy_count >= max_enemies:
		return

	var count := GameBalance.spawn_batch(wave_number, GameManager.rng.randf())
	for i in range(count):
		var angle := GameManager.rng.randf() * TAU
		var spawn_dist := GameManager.rng.randf_range(380.0, 480.0)
		var pos = player.global_position + Vector2(cos(angle), sin(angle)) * spawn_dist
		pos = pos.clamp(Vector2.ONE * -(GameManager.MAP_HALF_EXTENT - 40.0), Vector2.ONE * (GameManager.MAP_HALF_EXTENT - 40.0))

		var enemy = _pick_enemy_scene().instantiate() as EnemyBase
		enemy.global_position = pos
		enemy.add_to_group("enemies")
		_scale_to_wave(enemy)
		get_parent().add_child(enemy)

## 怪物配比表：随波次引入新威胁（雷兽冲锋 → 邪修剑气 → 丹爆傀儡）
func _pick_enemy_scene() -> PackedScene:
	var roll := GameManager.rng.randf()
	if wave_number >= 12 and roll < 0.12:
		return danbao_scene
	if wave_number >= 8 and roll < 0.27:
		return xiexiu_scene
	if wave_number >= 5 and roll < 0.42:
		return leibeast_scene
	if wave_number >= 2 and roll < 0.42 + minf(0.25 + wave_number * 0.06, 0.6) * 0.58:
		return flower_scene
	return slime_scene

func _spawn_elite(player: Node2D) -> void:
	var angle := GameManager.rng.randf() * TAU
	var pos = player.global_position + Vector2(cos(angle), sin(angle)) * 420.0
	pos = pos.clamp(Vector2.ONE * -(GameManager.MAP_HALF_EXTENT - 60.0), Vector2.ONE * (GameManager.MAP_HALF_EXTENT - 60.0))
	var golem = golem_scene.instantiate() as EnemyBase
	golem.global_position = pos
	golem.add_to_group("enemies")
	_scale_to_wave(golem)
	get_parent().add_child(golem)

	GameManager.announcement_triggered.emit("⚠ 铁甲魔傀破阵而入！")
	GameManager.shake_camera(5.0, 0.25)

## 随波数成长敌人属性（曲线见 GameBalance），同种怪个体 ±10% 浮动
func _scale_to_wave(enemy: EnemyBase) -> void:
	var variance: float = GameManager.rng.randf_range(
		1.0 - GameBalance.ENEMY_STAT_VARIANCE,
		1.0 + GameBalance.ENEMY_STAT_VARIANCE
	)
	enemy.max_hp = ceilf(enemy.max_hp * GameBalance.enemy_hp_mult(wave_number) * variance)
	enemy.contact_damage = ceilf(enemy.contact_damage * GameBalance.enemy_dmg_mult(wave_number) * variance)

## 固定 Boss 关：血量/伤害按 GameBalance 波次公式注入，称号与演出随关卡推进
func _spawn_boss(player: Node2D) -> void:
	var angle := GameManager.rng.randf() * TAU
	var pos = player.global_position + Vector2(cos(angle), sin(angle)) * 460.0
	pos = pos.clamp(Vector2.ONE * -(GameManager.MAP_HALF_EXTENT - 60.0), Vector2.ONE * (GameManager.MAP_HALF_EXTENT - 60.0))

	var boss := boss_scene.instantiate() as BossEnemy
	boss.global_position = pos
	boss.add_to_group("enemies")
	boss.add_to_group("boss")
	boss.max_hp = GameBalance.boss_hp(wave_number)
	boss.contact_damage = GameBalance.boss_contact_damage(wave_number)
	boss.attack_interval = GameBalance.BOSS_ATTACK_INTERVAL
	boss.final_boss = wave_number >= GameManager.VICTORY_WAVE
	boss.boss_title = _boss_title()
	_boss_ref = boss
	get_parent().add_child(boss)

	GameManager.announcement_triggered.emit(_boss_announcement())
	GameManager.shake_camera(7.0, 0.35)

## 本波魔君存活与否（Boss 波超时锁关的判据）
func _boss_still_alive() -> bool:
	return _boss_ref != null and is_instance_valid(_boss_ref) and not _boss_ref.dying

func _boss_title() -> String:
	if wave_number > GameManager.VICTORY_WAVE:
		return "妖皇回响"     ## 无尽波次的轮回魔君
	if wave_number >= GameManager.VICTORY_WAVE:
		return "心魔魔尊"     ## 第 20 波最终关
	return "赤炎魔将"         ## 第 10 波首个 Boss 关

func _boss_announcement() -> String:
	if wave_number == GameManager.VICTORY_WAVE:
		return "⚠ 心魔劫 · 心魔魔尊现世！"
	if wave_number > GameManager.VICTORY_WAVE:
		return "⚠ 妖皇回响 · 轮回魔君再临！"
	return "⚠ Boss 波 · 赤炎魔将破阵而入！"
