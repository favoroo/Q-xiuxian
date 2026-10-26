extends Node

## 剑气凌霄判据（2026-10-26）：把「近战/横扫改成挥出完整剑弧」这件事钉死五条。
## 用户口径：①「不是发一个弹丸，是一道完整的剑弧」②「不管怎么攻击都是挥出一道剑气，
## 而不是一下近战一下剑气」。
##   ① 剑气凌霄生效后，本体 deal_damage 短路（近战 + 横扫都不再自行判伤，只放剑气）
##   ② 飞出去的剑弧真的能咬到 200px 外的敌人（伤害只此一条通道，不是「飞出去没判伤」）
##   ③ 一击一伤：贴身与远距敌人同时在场时，每个敌人只被这道剑气结算一次（不双计）
##   ④ 扇形边界：身后的敌人吃不掉血，铺在身前的贴脸敌人必须吃到（整片扇形都算）
##   ⑤ 剑气波飞满有效射程后自行回池，不残留活跃计数
##
## 运行: godot --headless --path . res://tests/SwordQiWaveCheck.tscn
## 退出码 0 且末行 SWORD_QI_RESULT: ALL PASS
## 反例（回归时必红）：
##   - 把 deal_damage 的短路删掉 ⇒ ① 报红
##   - 剑气只飞不判伤 ⇒ ② 报红
##   - 剑气去掉命中去重 ⇒ ③ 报红（同波反复结算）
##   - 判定改成整圆（不滤角度）或改成只剩远处薄环 ⇒ ④ 报红

const MAX_WAIT_FRAMES := 240

var _c := TestCheck.new()
var _world: Node2D
var _player: Player
var _fw_scene: PackedScene = preload("res://scenes/weapons/FloatingWeapon.tscn")

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	SettingsManager.set_val(&"display", &"hit_stop", false, false)
	Engine.time_scale = 1.0
	GameManager.reset_run()

	_world = Node2D.new()
	_world.name = "SwordQiWorld"
	get_tree().root.add_child(_world)
	await get_tree().process_frame

	_player = load("res://scenes/entities/Player.tscn").instantiate() as Player
	_world.add_child(_player)
	_player.global_position = Vector2.ZERO
	await get_tree().process_frame

	# 拿神通：剑气凌霄（hook 读侧生效，本体判定让位）
	_c.check(SuperUpgradeData.apply(GameManager, "super_jianqi"), "前置：剑气凌霄落地")
	_c.check(StrikeFx.sword_qi_active(), "前置：剑气凌霄处于生效态")

	await _case_body_damage_disabled()
	await _case_hits_far_enemy()
	await _case_no_double_dip()
	await _case_arc_shape()
	await _case_recycles()

	print("SWORD_QI_CHECK 判据跑完")
	Engine.time_scale = 1.0
	if _c.report("SWORD_QI_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

## ① 本体判定让位：两把 handler 的 deal_damage 都直接返回 0（伤害只由剑弧结算）
func _case_body_damage_disabled() -> void:
	var w := _make_weapon()
	var melee_hits: int = MeleeHandler.deal_damage(w, Vector2.RIGHT)
	var sweep_hits: int = SweepHandler.deal_damage(w, Vector2.RIGHT)
	_c.check(melee_hits == 0, "近战本体判定让位（返回值 %d，应为 0）" % melee_hits)
	_c.check(sweep_hits == 0, "横扫本体判定让位（返回值 %d，应为 0）" % sweep_hits)
	w.queue_free()
	await get_tree().process_frame

## ② 剑气真能咬到远处敌人：200px 外的靶子（本体 75px 圆绝对够不到）必须掉血
func _case_hits_far_enemy() -> void:
	var w := _make_weapon()
	var target := _spawn_enemy(Vector2(200.0, 0.0))
	var hp_before: float = target.current_hp
	var wave: SwordQiWave = StrikeFx.try_fire_sword_qi_wave(w, Vector2.RIGHT)
	_c.check(wave != null, "挥刀甩出剑气波")
	if wave == null:
		target.queue_free()
		w.queue_free()
		return
	var hit := false
	for i in range(MAX_WAIT_FRAMES):
		await get_tree().physics_frame
		if not is_instance_valid(target):
			hit = true
			break
		if target.current_hp < hp_before:
			hit = true
			break
	_c.check(hit, "剑气咬到 200px 外的敌人（远超本体 75px 判定圆）")
	w.queue_free()
	if is_instance_valid(target):
		target.queue_free()
	await get_tree().process_frame

## ③ 一击一伤：同一道剑气对同一敌人只结算一次（停在弧带里也不反复扣血）
func _case_no_double_dip() -> void:
	# 上一个用例的剑气可能还在飞：不清干净，它会把「第二次扣血」记到这道波头上
	await _drain_waves()
	var w := _make_weapon()
	# 敌人放到剑气的飞行路径上，让它长时间处在刃带范围内
	var target := _spawn_enemy(Vector2(90.0, 0.0))
	var wave: SwordQiWave = StrikeFx.try_fire_sword_qi_wave(w, Vector2.RIGHT)
	if wave == null:
		_c.fail("剑气波未生成，跳过一击一伤用例")
		target.queue_free()
		w.queue_free()
		return
	var prev_hp: float = target.current_hp
	var drops := 0
	for i in range(60):
		await get_tree().physics_frame
		if not is_instance_valid(target):
			drops += 1
			break
		if target.current_hp < prev_hp:
			drops += 1
			prev_hp = target.current_hp
	_c.check(drops <= 1, "同一道剑气对同一敌人只结算一次（实得 %d 次扣血）" % drops)
	w.queue_free()
	if is_instance_valid(target):
		target.queue_free()
	await get_tree().process_frame

## ④ 扇形边界：身后的敌人不吃伤害，但贴身的敌人（在扇区内）必须吃到
## —— 剑弧扫过去是整片气，不是只在远处开一个洞
func _case_arc_shape() -> void:
	await _drain_waves()
	var w := _make_weapon()
	var behind := _spawn_enemy(Vector2(-170.0, 0.0))
	var near := _spawn_enemy(Vector2(30.0, 0.0))
	var behind_hp: float = behind.current_hp
	var near_hp: float = near.current_hp
	var wave: SwordQiWave = StrikeFx.try_fire_sword_qi_wave(w, Vector2.RIGHT)
	if wave != null:
		for i in range(40):
			await get_tree().physics_frame
			if not is_instance_valid(wave) or wave._pooled:
				break
	_c.check(is_instance_valid(behind) and behind.current_hp >= behind_hp - 0.001,
		"波心反方向（-X 170px）的敌人不吃剑气伤害（扇区外）")
	_c.check(is_instance_valid(near) and near.current_hp < near_hp,
		"贴脸敌人（+X 30px）同样吃剑气伤害（整片扇形都算，不留弧心空洞）")
	if is_instance_valid(behind):
		behind.queue_free()
	if is_instance_valid(near):
		near.queue_free()
	w.queue_free()
	await get_tree().process_frame

## ⑤ 到寿命自行回池：活跃计数回到 0，不泄漏
func _case_recycles() -> void:
	var w := _make_weapon()
	var pre: int = SwordQiWave.active_count
	var wave: SwordQiWave = StrikeFx.try_fire_sword_qi_wave(w, Vector2.RIGHT)
	_c.check(SwordQiWave.active_count == pre + 1, "剑气出膛活跃计数 +1")
	if wave != null:
		var frames := int(ceil(wave.lifetime * 60.0)) + 10
		for i in range(frames):
			await get_tree().physics_frame
		_c.check(SwordQiWave.active_count == pre, "剑气飞满寿命后回池（活跃计数归零，不留账）")
		_c.check(not wave.visible, "回池后视觉撤场（visible=false）")
	w.queue_free()
	await get_tree().process_frame
	GameManager.reset_run()

## 建一把真武器（要进树才能跑 _final_damage/_arc_element 与池宿主）。
## 必须关掉 _process：武器会自己按冷却索敌开火，多出来的剑气波会污染
## 「一击一伤 / 弧心空洞 / 回池计数」三条断言。
## 等上一用例的剑气全部飞完回池：跨用例串波会让「一击一伤 / 回池计数」误报
func _drain_waves() -> void:
	for i in range(MAX_WAIT_FRAMES):
		if SwordQiWave.active_count == 0:
			return
		await get_tree().physics_frame

func _make_weapon() -> FloatingWeapon:
	var w := _fw_scene.instantiate() as FloatingWeapon
	w.weapon_def_id = "qingyun_sword"
	w.def = WeaponData.get_def("qingyun_sword")
	w.behavior = WeaponData.Behavior.MELEE
	w.attack_range = 105.0
	_world.add_child(w)
	w.global_position = Vector2.ZERO
	w.set_process(false)
	return w

func _spawn_enemy(pos: Vector2) -> EnemyBase:
	var scene: PackedScene = load("res://scenes/entities/SlimeEnemy.tscn")
	var e := scene.instantiate() as EnemyBase
	e.global_position = pos
	e.add_to_group("enemies")
	_world.add_child(e)
	return e
