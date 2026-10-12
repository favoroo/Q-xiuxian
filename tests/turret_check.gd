extends Node

## tests/turret_check.gd — 机关炮台布设/索敌/开火/上限/羁绊判定
## 运行: godot --headless --path . res://tests/TurretCheck.tscn

var _c := TestCheck.new()

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	Engine.time_scale = 1.0
	var world := Node2D.new()
	world.name = "TurretCheckWorld"
	get_tree().root.add_child(world)
	await get_tree().process_frame

	# 1. 炮台单独实例化与属性装载
	var turret_scene: PackedScene = load("res://scenes/weapons/TurretUnit.tscn")
	var t1: TurretUnit = turret_scene.instantiate() as TurretUnit
	t1.setup("jiguan_nu", 1)
	world.add_child(t1)
	t1.global_position = Vector2(100, 100)
	await get_tree().process_frame

	_c.equals(t1.weapon_def_id, "jiguan_nu", "炮台成功装载机关弩")
	_c.check(t1.is_in_group("turrets"), "炮台已自动加入 turrets 分组")
	_c.near(t1.lifetime, 12.0, 0.01, "★1 机关弩炮台寿命为 12s")
	_c.near(t1.fire_cooldown, 0.75, 0.01, "机关弩开火间隔为 0.75s")

	# 2. 炮台伤害公式
	GameManager.reset_run()
	GameManager.contraption_damage = 5.0
	GameManager.synergy_contraption_mult = 1.30
	var dmg: float = t1._final_damage()
	# base 18 + contraption 5 = 23 * 1.30 = 29.9
	_c.near(dmg, (18.0 + 5.0) * 1.30, 0.1, "炮台伤害完整吃到机关伤害加点与机关羁绊")

	# 2.5 索敌范围乘区（2026-10-11 补漏回归）：详情卡展示「范围 = 基础 × 攻击范围词条 × 范围羁绊」，
	# 机关台实际索敌必须同源 —— 面板报多大就得索多大，加点攻击范围不许对机关台失明
	GameManager.reset_run()
	t1.setup("jiguan_nu", 1)
	var base_r := float(WeaponData.get_def("jiguan_nu").get("range", 270.0))
	_c.near(t1._eff_range(), base_r, 0.01, "无加成时机关弩索敌范围为表值 %.0f" % base_r)
	GameManager.attack_range_mult = 1.5
	GameManager.synergy_range_mult = 1.2
	_c.near(t1._eff_range(), base_r * 1.5 * 1.2, 0.01, "机关台索敌范围吃到攻击范围词条与范围羁绊乘区")
	GameManager.reset_run()

	# 2.6 疾风咒 buff 口径（2026-10-11 补漏回归）：炮台开火间隔必须与法器/灵珠同乘疾风 buff 层，
	# 漏乘则疾风期间机关台不加速（玩家直觉与实际不符）
	_c.near(t1._eff_fire_cd(), 0.75, 0.01, "无 buff 时炮台开火间隔为表值 0.75s")
	GameManager.buff_attack_speed_mult = 0.6
	_c.near(t1._eff_fire_cd(), 0.45, 0.01, "疾风咒期间炮台开火间隔同乘 buff 层（0.75×0.6=0.45）")
	GameManager.reset_run()

	# 3. FloatingWeapon 布设机关与同屏上限
	var fw: Node = load("res://scenes/weapons/FloatingWeapon.tscn").instantiate()
	fw.setup("jiguan_nu", 1)
	world.add_child(fw)
	fw.set_process(false)
	fw.global_position = Vector2(200, 200)
	await get_tree().process_frame

	_c.equals(int(fw.behavior), WeaponData.Behavior.TURRET, "FloatingWeapon 行为为 TURRET")

	# 模拟 3 次开火布设（★1 上限为 2 座）
	fw.cooldown_timer = 0.0
	fw._perform_turret_attack()
	await get_tree().process_frame
	_c.equals(fw.active_turrets.size(), 1, "布设第 1 座炮台")

	fw.cooldown_timer = 0.0
	fw._perform_turret_attack()
	await get_tree().process_frame
	_c.equals(fw.active_turrets.size(), 2, "布设第 2 座炮台（达到上限）")

	var first_turret: TurretUnit = fw.active_turrets[0] as TurretUnit
	fw.cooldown_timer = 0.0
	fw._perform_turret_attack()
	await get_tree().process_frame
	_c.equals(fw.active_turrets.size(), 2, "布设第 3 座时数量保持上限 2")
	_c.check(first_turret._is_dying, "超限时最早布设的炮台自动进入消散状态")

	# 4. 波末收回测试
	var turrets := get_tree().get_nodes_in_group("turrets")
	_c.check(turrets.size() >= 3, "场上存在已布设炮台")
	for tr in turrets:
		if tr is TurretUnit:
			tr.dismiss()
	await get_tree().process_frame

	world.queue_free()
	GameManager.reset_run()

	if _c.report("TURRET_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)
