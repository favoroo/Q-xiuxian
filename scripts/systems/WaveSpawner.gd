class_name WaveSpawner
extends Node2D

## 波次状态机：WAITING(选法器) → FIGHT → CLEARING(清场吸附) → SHOP → 下一波
## 第 10 波通关「渡劫成功」；可继续无尽

enum Phase { WAITING, FIGHT, CLEARING, SHOP }

@export var max_enemies: int = 55

var phase: int = Phase.WAITING
var wave_number: int = 0
var wave_timer: float = 0.0
var clear_timer: float = 0.0
var spawn_timer: float = 0.0
var elite_spawned: bool = false

var slime_scene: PackedScene = preload("res://scenes/entities/SlimeEnemy.tscn")
var flower_scene: PackedScene = preload("res://scenes/entities/FlowerEnemy.tscn")
var golem_scene: PackedScene = preload("res://scenes/entities/GolemEnemy.tscn")

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

	if spawn_timer <= 0.0:
		spawn_timer = maxf(0.38, 1.4 - float(wave_number) * 0.11)
		_spawn_regular(player)

	# 精英波：第 4/7/10 波，无尽模式每 3 波
	var is_elite_wave := wave_number in [4, 7, 10] or (GameManager.endless_mode and wave_number > 10 and wave_number % 3 == 0)
	if is_elite_wave and not elite_spawned and wave_timer < wave_duration(wave_number) - 1.5:
		elite_spawned = true
		_spawn_elite(player)

	if wave_timer <= 0.0:
		end_wave()

func wave_duration(n: int) -> float:
	return minf(25.0 + float(n) * 5.0, 55.0)

func start_wave(n: int) -> void:
	wave_number = n
	GameManager.wave_number = n
	GameManager.wave_changed.emit(n)
	elite_spawned = false
	wave_timer = wave_duration(n)
	spawn_timer = 0.6
	phase = Phase.FIGHT
	GameManager.announcement_triggered.emit("✦ 第 %d 波 · 妖潮来袭 ✦" % n)

func end_wave() -> void:
	phase = Phase.CLEARING
	clear_timer = 1.0
	GameManager.announcement_triggered.emit("第 %d 波妖潮平息" % wave_number)
	# 余怪消散（不掉落）
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is EnemyBase:
			enemy.dissolve()
	# 地上灵石全部吸附给玩家
	var player = GameManager.player
	if player != null:
		for gem in get_tree().get_nodes_in_group("gems"):
			if gem is AstralGem:
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
	GameManager.roll_shop()
	GameManager.shop_opened.emit()

func _on_shop_closed() -> void:
	start_wave(wave_number + 1)

func _spawn_regular(player: Node2D) -> void:
	var enemy_count = get_tree().get_nodes_in_group("enemies").size()
	if enemy_count >= max_enemies:
		return

	var count = 1 + wave_number / 4 + (1 if randf() < 0.4 else 0)
	for i in range(count):
		var angle = randf() * TAU
		var spawn_dist = randf_range(380.0, 480.0)
		var pos = player.global_position + Vector2(cos(angle), sin(angle)) * spawn_dist
		pos = pos.clamp(Vector2.ONE * -(GameManager.MAP_HALF_EXTENT - 40.0), Vector2.ONE * (GameManager.MAP_HALF_EXTENT - 40.0))

		# 妖狼比例随波数上升
		var enemy_scene = slime_scene
		if wave_number >= 2 and randf() < minf(0.25 + wave_number * 0.06, 0.6):
			enemy_scene = flower_scene

		var enemy = enemy_scene.instantiate() as EnemyBase
		enemy.global_position = pos
		enemy.add_to_group("enemies")
		_scale_to_wave(enemy)
		get_parent().add_child(enemy)

func _spawn_elite(player: Node2D) -> void:
	var angle = randf() * TAU
	var pos = player.global_position + Vector2(cos(angle), sin(angle)) * 420.0
	pos = pos.clamp(Vector2.ONE * -(GameManager.MAP_HALF_EXTENT - 60.0), Vector2.ONE * (GameManager.MAP_HALF_EXTENT - 60.0))
	var golem = golem_scene.instantiate() as EnemyBase
	golem.global_position = pos
	golem.add_to_group("enemies")
	_scale_to_wave(golem)
	get_parent().add_child(golem)

	GameManager.announcement_triggered.emit("⚠ 铁甲魔傀破阵而入！")
	GameManager.shake_camera(5.0, 0.25)

## 随波数成长敌人属性
func _scale_to_wave(enemy: EnemyBase) -> void:
	var hp_mult := 1.0 + float(wave_number - 1) * 0.18
	var dmg_mult := 1.0 + float(wave_number - 1) * 0.08
	enemy.max_hp = ceilf(enemy.max_hp * hp_mult)
	enemy.contact_damage = ceilf(enemy.contact_damage * dmg_mult)
