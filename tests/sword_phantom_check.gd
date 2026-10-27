extends Node

## 万剑归宗判据（2026-10-26 三轮重塑）：把「幻影剑阵驻场」这件事钉死六条。
## 用户口径演进：①「一个圆圈的余波，我不知道有什么用啊，有什么伤害」——旧的圆形冲击波必须下线；
## ②「6 把剑系装备就幻化出 6 把，一共十二把一起攻击」——幻影数 == 剑系数；
## ③「效果太不明显了，都没感受出来有幻象出来，改成幻象能持续一段时间，
##    攻击到一定层数之后幻象能够持续好几秒」——幻影必须驻场数秒、肉眼数得清。
##   ① 只有剑系武器出手才涨剑意：斧/符出手不涨，剑系每出一刀 +1
##   ② 攒满阈值立刻开阵，幻影数 == 玩家剑系数（6 剑 = 6 道），伤害 == 源武器实伤 × DAMAGE_RATIO
##   ③ 幻影驻场 FORMATION_TIME 秒：过半一道不少、到点才散（本轮核心诉求）
##   ④ 幻影【不离轨】：驻场期间始终停在剑阵圈上，不会自己飞出去（不许再像弹丸）
##   ⑤ 幻影原地劈斩真能咬到圈内敌人（判定圆 == 弧光外缘，画多大==判多大）
##   ⑥ 剑阵运转期间剑意不涨（否则阵一散就能立刻再开，等于常驻）
##   ⑦ 圈内无怪不开阵、不消耗剑意；怪进圈后下一次出手立刻开
##
## 运行: godot --headless --path . res://tests/SwordPhantomCheck.tscn
## 退出码 0 且末行 SWORD_PHANTOM_RESULT: ALL PASS
## 反例（回归时必红）：
##   - 去掉 class_of != "sword" 的闸 ⇒ ① 报红（斧头也能攒剑意）
##   - open_formation 里写死幻影数、不遍历剑系武器 ⇒ ② 报红
##   - 把驻场时长改回「凝形完就散」（二轮实现）⇒ ③ 报红
##   - 幻影再自己飞出去（二轮的 DASH 状态）⇒ ④ 报红
##   - 幻影不判伤 / 判定半径与弧光不同源 ⇒ ⑤ 报红
##   - tick_attack 不判 formation_active ⇒ ⑥ 报红

const MAX_WAIT_FRAMES := 400
## 期望幻影数：玩家身上 6 把剑系武器（含远程剑系，同属 sword class）
const SWORD_COUNT := 6
## 驻场观察窗口（占 FORMATION_TIME 的比例）：4 秒整段跑太慢，取 60% 已足够证明「不是一闪就没」
const OBSERVE_RATIO := 0.6

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
	await _case_formation_lifetime()
	await _case_slash_hits_enemy()
	await _case_no_charge_while_forming()
	await _case_no_charge_without_targets()

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

## ②③④ 一次开阵里把「数量 / 伤害口径 / 驻场时长 / 不离轨」四件事一起验完
## （开一次阵要真跑几秒，分开验会把判据拖到超时）
func _case_formation_lifetime() -> void:
	_equip(_sword_ids())
	await _expire_formation()
	SwordPhantom.reset_charge()
	var target := _spawn_enemy(Vector2(120.0, 0.0))
	await get_tree().physics_frame

	var pre: int = SwordPhantom.active_count
	var fired: int = SwordPhantom.open_formation(_player.weapon_holder, _player)
	_c.check(fired == SWORD_COUNT, "6 把剑系武器开阵幻化 6 道幻影（实得 %d）" % fired)
	_c.check(SwordPhantom.active_count == pre + SWORD_COUNT,
		"活跃计数 +%d（实得 +%d）" % [SWORD_COUNT, SwordPhantom.active_count - pre])
	_c.check(SwordPhantom.formation_active(), "开阵后剑阵进入运转态")

	# 伤害口径：拿第一把剑算期望值（每道幻影的 damage 在出阵时快照好）
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

	# 驻场观察窗口：一道都不许少，且全程压在剑阵环带上（不离轨）
	var max_dev: float = 0.0
	var frames: int = int(SwordPhantom.FORMATION_TIME * OBSERVE_RATIO * 60.0)
	for i in range(frames):
		await get_tree().physics_frame
		if _player == null or not is_instance_valid(_player):
			break
		for child in SwordPhantom._host.get_children():
			var ph := child as SwordPhantom
			if ph == null or ph._pooled or not ph.visible or ph._state == SwordPhantom.STATE_FORM:
				continue
			# 轨道是半长轴 112 / 半短轴 86 的椭圆；出刀前突最多 SLASH_LUNGE，
			# 所以「离玩家的距离」必须落在 [86 - 前突, 112 + 前突] 这个环带里
			var d: float = _player.global_position.distance_to(ph.global_position)
			var lo: float = SwordPhantom.ORBIT_RADII.y - SwordPhantom.SLASH_LUNGE - 1.0
			var hi: float = SwordPhantom.ORBIT_RADII.x + SwordPhantom.SLASH_LUNGE + 1.0
			if d < lo:
				max_dev = maxf(max_dev, lo - d)
			elif d > hi:
				max_dev = maxf(max_dev, d - hi)
	_c.check(SwordPhantom.active_count == SWORD_COUNT,
		"驻场 %.0f%%（%.1fs）后 6 道幻影仍在场（实得 %d）"
			% [OBSERVE_RATIO * 100.0, SwordPhantom.FORMATION_TIME * OBSERVE_RATIO, SwordPhantom.active_count])
	_c.check(SwordPhantom.formation_left() > 0.0,
		"此时仍有剩余驻场时间（实得 %.2fs）" % SwordPhantom.formation_left())
	_c.check(max_dev < 1.0,
		"驻场期间幻影始终压在剑阵环带上（最大偏离 %.2fpx，未飞出去变弹丸）" % max_dev)

	# 阵末：到点才散，散完回池
	await _expire_formation()
	_c.check(SwordPhantom.active_count == 0, "驻场时长走完 + 消散后全部回池（实得 %d）" % SwordPhantom.active_count)
	_c.check(not SwordPhantom.formation_active(), "剑阵结束后回到未运转态")
	if is_instance_valid(target):
		target.queue_free()
	await get_tree().process_frame

## ⑤ 幻影原地劈斩真的咬到圈内敌人（判定半径 == 弧光外缘，画多大==判多大）
func _case_slash_hits_enemy() -> void:
	_equip(_sword_ids())
	await _expire_formation()
	SwordPhantom.reset_charge()
	# 敌人放在剑阵外缘外侧一点：只有劈斩真的够得着才掉血
	var target := _spawn_enemy(Vector2(150.0, 0.0))
	await get_tree().physics_frame
	var hp_before: float = target.current_hp
	SwordPhantom.open_formation(_player.weapon_holder, _player)
	var hit := false
	for i in range(MAX_WAIT_FRAMES):
		await get_tree().physics_frame
		if not is_instance_valid(target):
			hit = true
			break
		if target.current_hp < hp_before:
			hit = true
			break
	_c.check(hit, "剑阵劈斩咬到 150px 处的敌人（远超近战 75px 本体圆）")
	if is_instance_valid(target):
		target.queue_free()
	await _expire_formation()

## ⑥ 剑阵运转期间剑意不涨（否则阵一散就能立刻再开，等于常驻）
func _case_no_charge_while_forming() -> void:
	_equip(_sword_ids())
	await _expire_formation()
	SwordPhantom.reset_charge()
	var target := _spawn_enemy(Vector2(120.0, 0.0))
	await get_tree().physics_frame
	SwordPhantom.open_formation(_player.weapon_holder, _player)
	var sword := _player.weapon_holder.get_child(0) as FloatingWeapon
	for i in range(SwordPhantom.CHARGE_EVERY * 2):
		SwordPhantom.tick_attack(sword)
	_c.check(SwordPhantom.charge() == 0,
		"剑阵运转期间出手不攒剑意（实得 %d，否则阵一散立刻又能开）" % SwordPhantom.charge())
	if is_instance_valid(target):
		target.queue_free()
	await _expire_formation()

## ⑦ 圈内无敌人：不消耗剑意（层数钳在阈值上等怪进来），开阵后归零
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
	await _expire_formation()
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
## 关掉 _process：武器会自己按冷却开火，多出来的剑意会污染计数断言。
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

## 把当前剑阵快进到阵末再等它散完回池。
## 用例之间必须清场（跨用例串场会让计数/不自激断言误报），但真等 4 秒会把判据拖到超时，
## 所以直接拨 _life_left 到 0 —— 「驻场真的持续好几秒」这条由 _case_formation_lifetime
## 里真跑 60% 窗口来证明，收尾快进不削弱那条断言。
func _expire_formation() -> void:
	if SwordPhantom._host != null and is_instance_valid(SwordPhantom._host):
		for child in SwordPhantom._host.get_children():
			var ph := child as SwordPhantom
			if ph != null and not ph._pooled:
				ph._life_left = 0.0
	for i in range(MAX_WAIT_FRAMES):
		if SwordPhantom.active_count == 0:
			return
		await get_tree().physics_frame
