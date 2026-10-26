extends Node

## 万剑归宗判据（2026-10-26 重塑）：把「幻影剑阵齐射」这件事钉死五条。
## 用户口径：①「一个圆圈的余波，我不知道有什么用啊，有什么伤害」——旧的圆形冲击波必须下线；
## ②「6 把剑系装备就幻化出 6 把，一共十二把一起攻击，这才有点万剑归宗的效果」。
##   ① 只有剑系武器出手才涨剑意：斧/符/扇出手不涨，剑系每出一刀 +1
##   ② 攒满阈值立刻开阵，且幻影数 == 玩家剑系数（6 剑 = 6 道幻影，不是固定几道）
##   ③ 幻影真的斩到远处的敌人（300px 索敌圈内），伤害 == 源武器实伤 × DAMAGE_RATIO
##   ④ 圈内无敌人时不消耗剑意（层数钳在阈值上等怪进来），开阵后归零
##   ⑤ 幻影命中不回灌剑意（否则一道幻影算一次出手 → 无限自激），飞满后自行回池
##
## 运行: godot --headless --path . res://tests/SwordPhantomCheck.tscn
## 退出码 0 且末行 SWORD_PHANTOM_RESULT: ALL PASS
## 反例（回归时必红）：
##   - 去掉 class_of != "sword" 的闸 ⇒ ① 报红（斧头也能攒剑意）
##   - fire_volley 里写死幻影数、不遍历剑系武器 ⇒ ② 报红
##   - 幻影不判伤 / 伤害乘错比例 ⇒ ③ 报红
##   - 圈内无怪也清空剑意 ⇒ ④ 报红
##   - _apply_hit 里回灌 tick_attack ⇒ ⑤ 报红（自激）

const MAX_WAIT_FRAMES := 300
## 期望幻影数：玩家身上 6 把剑系武器（含远程剑系，同属 sword class）
const SWORD_COUNT := 6

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
	_world.name = "SwordPhantomWorld"
	get_tree().root.add_child(_world)
	await get_tree().process_frame

	_player = load("res://scenes/entities/Player.tscn").instantiate() as Player
	_world.add_child(_player)
	_player.global_position = Vector2.ZERO
	await get_tree().process_frame

	_c.check(SuperUpgradeData.apply(GameManager, "super_wanjian_guizong"), "前置：万剑归宗落地")
	_c.check(float(StatSystem.super_hook_snapshot(GameManager).get("sword_qi", 0.0)) > 0.0,
		"前置：sword_qi hook 生效")

	await _case_only_sword_charges()
	await _case_volley_count_matches_swords()
	await _case_phantom_hits_far_enemy()
	await _case_no_charge_without_targets()
	await _case_no_self_charge_and_recycle()

	print("SWORD_PHANTOM_CHECK 判据跑完")
	Engine.time_scale = 1.0
	if _c.report("SWORD_PHANTOM_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

## ① 只有剑系武器出手才涨剑意（斧/符等近战武器不算）
func _case_only_sword_charges() -> void:
	_equip([])
	SwordPhantom.reset_charge()
	var axe := _make_weapon("kaishan_fu")
	SwordPhantom.tick_attack(axe)
	_c.check(SwordPhantom.charge() == 0, "非剑系武器（斧）出手不涨剑意（实得 %d）" % SwordPhantom.charge())
	axe.queue_free()
	var sword := _make_weapon("qingyun_sword")
	SwordPhantom.tick_attack(sword)
	_c.check(SwordPhantom.charge() == 1, "剑系武器出手 +1 剑意（实得 %d）" % SwordPhantom.charge())
	sword.queue_free()
	await get_tree().process_frame

## ② 幻影数 == 玩家剑系数；③ 伤害口径 == 源武器实伤 × DAMAGE_RATIO
func _case_volley_count_matches_swords() -> void:
	_equip(_sword_ids())
	await _drain_phantoms()
	SwordPhantom.reset_charge()
	var target := _spawn_enemy(Vector2(120.0, 0.0))
	await get_tree().physics_frame
	var pre: int = SwordPhantom.active_count
	var fired: int = SwordPhantom.fire_volley(_player.weapon_holder, _player)
	_c.check(fired == SWORD_COUNT, "6 把剑系武器开阵放出 6 道幻影（实得 %d）" % fired)
	_c.check(SwordPhantom.active_count == pre + SWORD_COUNT,
		"活跃计数 +%d（实得 +%d）" % [SWORD_COUNT, SwordPhantom.active_count - pre])
	# 伤害口径：拿第一把剑算期望值（每把剑的幻影 damage 都应在出膛时快照好）
	var first: FloatingWeapon = _player.weapon_holder.get_child(0) as FloatingWeapon
	var expect: float = first._final_damage() * SwordPhantom.DAMAGE_RATIO
	var found := false
	for child in SwordPhantom._host.get_children():
		var ph := child as SwordPhantom
		if ph == null or ph._pooled or not ph.visible:
			continue
		if ph.weapon_def_id == first.weapon_def_id:
			_c.near(ph.damage, expect, 0.01, "幻影伤害 == 源武器实伤 × %.2f" % SwordPhantom.DAMAGE_RATIO)
			found = true
			break
	_c.check(found, "找得到源武器对应的那道幻影")
	if is_instance_valid(target):
		target.queue_free()
	await _drain_phantoms()

## ③ 幻影真的斩到 300px 索敌圈内的远处敌人
func _case_phantom_hits_far_enemy() -> void:
	_equip(_sword_ids())
	SwordPhantom.reset_charge()
	var far := _spawn_enemy(Vector2(260.0, 0.0))
	await get_tree().physics_frame
	var hp_before: float = far.current_hp
	var fired: int = SwordPhantom.fire_volley(_player.weapon_holder, _player)
	_c.check(fired > 0, "260px 外的敌人能被开阵锁定（放出 %d 道幻影）" % fired)
	var hit := false
	for i in range(MAX_WAIT_FRAMES):
		await get_tree().physics_frame
		if not is_instance_valid(far):
			hit = true
			break
		if far.current_hp < hp_before:
			hit = true
			break
	_c.check(hit, "幻影飞出去斩到 260px 外的敌人（远超近战 75px 判定圆）")
	if is_instance_valid(far):
		far.queue_free()
	await _drain_phantoms()

## ④ 圈内无敌人：不消耗剑意（层数钳在阈值上等怪进来）
func _case_no_charge_without_targets() -> void:
	_equip(_sword_ids())
	_clear_enemies()
	SwordPhantom.reset_charge()
	var sword := _player.weapon_holder.get_child(0) as FloatingWeapon
	for i in range(SwordPhantom.CHARGE_EVERY):
		SwordPhantom.tick_attack(sword)
	_c.check(SwordPhantom.charge() == SwordPhantom.CHARGE_EVERY,
		"圈内无怪时剑意不消耗，钳在阈值上（实得 %d / %d）" % [SwordPhantom.charge(), SwordPhantom.CHARGE_EVERY])
	_c.check(SwordPhantom.active_count == 0, "无怪时不开阵（活跃幻影为 0）")
	# 怪一进圈，下一次出手立刻开阵并把剑意清零
	var target := _spawn_enemy(Vector2(80.0, 0.0))
	await get_tree().physics_frame
	SwordPhantom.tick_attack(sword)
	_c.check(SwordPhantom.active_count > 0, "怪进圈后下一次出手立刻开阵")
	_c.check(SwordPhantom.charge() == 0, "开阵后剑意归零（实得 %d）" % SwordPhantom.charge())
	if is_instance_valid(target):
		target.queue_free()
	await _drain_phantoms()

## ⑤ 幻影命中不回灌剑意；飞满后自行回池
func _case_no_self_charge_and_recycle() -> void:
	_equip(_sword_ids())
	SwordPhantom.reset_charge()
	var target := _spawn_enemy(Vector2(90.0, 0.0))
	await get_tree().physics_frame
	SwordPhantom.fire_volley(_player.weapon_holder, _player)
	_c.check(SwordPhantom.charge() == 0, "开阵后剑意为 0")
	# 让幻影一路飞完（命中或航程耗尽），期间剑意必须一直是 0 —— 幻影不算出手
	var charged_again := false
	for i in range(MAX_WAIT_FRAMES):
		await get_tree().physics_frame
		if SwordPhantom.charge() != 0:
			charged_again = true
			break
		if SwordPhantom.active_count == 0:
			break
	_c.check(not charged_again, "幻影命中不回灌剑意（不自激成无限剑阵）")
	_c.check(SwordPhantom.active_count == 0, "幻影飞满后自行回池（活跃计数归零，不留账）")
	if is_instance_valid(target):
		target.queue_free()
	await get_tree().process_frame
	GameManager.reset_run()

# ---------------- 辅助 ----------------

## 剑系武器清单（全部 class_of == "sword"）：近战剑 / 横扫剑 / 远程剑系各两把
func _sword_ids() -> Array:
	return ["qingyun_sword", "chiyan_dao", "gengjin_feijian", "liuye_feidao", "qingteng_jian", "bengshan_jian"]

## 换上指定武器：先清空 weapon_holder，再逐把建进去（parent = 武器容器）
func _equip(ids: Array) -> void:
	for child in _player.weapon_holder.get_children():
		_player.weapon_holder.remove_child(child)
		child.queue_free()
	for id in ids:
		var wid := String(id)
		if WeaponData.get_def(wid).is_empty():
			continue
		var w := _make_weapon(wid, _player.weapon_holder)
		w.position = Vector2.ZERO

## 建一把真武器（_final_damage / _arc_element 需要进树）。
## 关掉 _process：武器会自己按冷却开火，多出来的幻影会污染计数断言。
func _make_weapon(wid: String, parent: Node = null) -> FloatingWeapon:
	var w := _fw_scene.instantiate() as FloatingWeapon
	w.weapon_def_id = wid
	w.def = WeaponData.get_def(wid)
	w.behavior = int(w.def.get("behavior", WeaponData.Behavior.MELEE))
	w.attack_range = float(w.def.get("range", 150.0))
	(parent if parent != null else _world).add_child(w)
	w.global_position = _player.global_position if parent != null else Vector2.ZERO
	w.set_process(false)
	return w

func _spawn_enemy(pos: Vector2) -> EnemyBase:
	var scene: PackedScene = load("res://scenes/entities/SlimeEnemy.tscn")
	var e := scene.instantiate() as EnemyBase
	e.global_position = pos
	e.add_to_group("enemies")
	_world.add_child(e)
	return e

func _clear_enemies() -> void:
	for node in GameManager.live_enemies.duplicate():
		if is_instance_valid(node):
			node.queue_free()
	GameManager.live_enemies.clear()
	GameManager.enemy_count = 0

## 等上一用例的幻影全部飞完回池：跨用例串场会让「回池计数 / 不自激」误报
func _drain_phantoms() -> void:
	for i in range(MAX_WAIT_FRAMES):
		if SwordPhantom.active_count == 0:
			return
		await get_tree().physics_frame
