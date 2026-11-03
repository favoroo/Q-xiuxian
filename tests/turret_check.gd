extends Node

## tests/turret_check.gd — 机关（Behavior.TURRET）手动布设 / 齐射 / 耐久维修 / 收回 判据
## 运行: python3 tools/run_test.py TurretCheck
##       （或 $G --headless --path . res://tests/TurretCheck.tscn）
##
## 2026-11-03 改版口径：
##   ① 每把机关武器只带 1 座（旧 turret_cap + (星-1) 自动布设废弃）；
##   ② 少掉的座数换算成齐射管数（★1 双管 … ★4 五管），逐星总 DPS 与旧公式**完全相等**；
##   ③ 机关开火磨损耐久：<40% 降速、=0 停摆；靠近长按 0.8s 连续回填；
##   ④ 收回返还编制并起整备冷却，耐久随机关带回（收回不是免费维修）；
##   ⑤ 回合末整备不清场（跨回合保留位置），下波重新接管。
##
## 本判据刻意不造真 Player：TurretCommand 对宿主全是鸭类型访问，喂一个带
## weapon_holder 的 Node2D 就能跑完整条布设/收回链路（真 Player 与 HUD 按钮由
## MechanismButtonCheck 覆盖）。

var _c := TestCheck.new()
var _world: Node2D = null
## 不标类型的假宿主：要动态写 weapon_holder 这个属性
var _player = null
var _holder: Node2D = null
var _fw: Node = null
var _turret: TurretUnit = null

## 假敌人：TurretUnit 的索敌只要求「Area2D 的父节点有 take_damage」且受击区在碰撞层 4
class FakeEnemy extends Node2D:
	var hurt: Area2D = null

	func _init(pos: Vector2) -> void:
		position = pos

	func _ready() -> void:
		hurt = Area2D.new()
		hurt.collision_layer = 4
		hurt.collision_mask = 0
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 12.0
		shape.shape = circle
		hurt.add_child(shape)
		add_child(hurt)

	func take_damage(_amount: float, _knock: Variant = null, _source: Variant = null) -> void:
		pass

## 假玩家：TurretCommand 读的是 player.weapon_holder 这个**属性**（真 Player 是 @onready var），
## 所以宿主必须自带同名字段；位类型不是 CharacterBody2D ⇒ 落点走「静止朝下」分支。
## current_health 两件套：机关的 stat_scalings 带 hp_regen / max_hp_bonus 时，
## StatSystem.player_stat_dict 会读这两项（真 Player 恒有）。
class FakePlayer extends Node2D:
	var weapon_holder: Node2D = null
	var current_health: float = 100.0
	var max_health: float = 100.0

	func heal(amount: float, _silent: bool = false) -> float:
		var before := current_health
		current_health = minf(max_health, current_health + amount)
		return current_health - before

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	await _build_stage()
	_check_data_table()
	_check_volley_dps_parity()
	_check_durability_math()
	await _check_entity_lifecycle()
	await _check_deploy_and_recall()
	await _check_volley_targets()
	await _check_proc_wiring()
	await _check_maintenance_progression()
	await _check_extra_charges()
	await _check_wave_end_keep()
	await _teardown()
	if _c.report("TURRET_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

func _build_stage() -> void:
	GameManager.reset_run()
	_world = Node2D.new()
	_world.name = "TurretCheckWorld"
	get_tree().root.add_child(_world)
	_player = FakePlayer.new()
	_player.name = "FakePlayer"
	_world.add_child(_player)
	_holder = Node2D.new()
	_holder.name = "WeaponHolder"
	_player.add_child(_holder)
	_player.weapon_holder = _holder
	GameManager.player = _player
	GameManager.run_started = true
	await get_tree().process_frame
	await get_tree().physics_frame

func _teardown() -> void:
	if _turret != null and is_instance_valid(_turret):
		_turret.dismiss()
	await get_tree().process_frame
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
	await get_tree().process_frame
	GameManager.player = null
	GameManager.run_started = false
	GameManager.reset_run()
	TurretUnit.clear_pool()

# ---------------- 1. 数据表 ----------------

func _check_data_table() -> void:
	var turret_ids: Array = []
	for wid in WeaponData.DEFS.keys():
		var def: Dictionary = WeaponData.DEFS[wid]
		if int(def.get("behavior", -1)) != WeaponData.Behavior.TURRET:
			continue
		turret_ids.append(wid)
		_c.check(float(def.get("turret_fire_cd", 0.0)) > 0.0, "%s 声明了开火间隔" % wid)
		_c.check(float(def.get("turret_stamina", 0.0)) > 0.0, "%s 声明了耐久时长" % wid)
		_c.check(not def.has("turret_lifetime"), "%s 已移除寿命字段（机关不再到点消散）" % wid)
		_c.check(not def.has("turret_cap"), "%s 已移除旧座数字段（每把只带一座）" % wid)
		_c.check("contraption" in WeaponData.tags_of(wid), "%s 带 contraption 机关标签" % wid)
	_c.equals(turret_ids.size(), 10, "机关武器共 10 把（实得 %d）" % turret_ids.size())

	# 齐射管数 = 旧座数：★1 2 管 … ★4 5 管
	var wants: Array[int] = [2, 3, 4, 5]
	for i in 4:
		_c.equals(WeaponData.turret_volley(i + 1), wants[i],
			"★%d 齐射 %d 管（= 旧炮台座数）" % [i + 1, wants[i]])
	_c.equals(GameBalance.turrets_per_weapon(), 1, "每把机关武器同时只在场 1 座")

# ---------------- 2. 逐星 DPS 与旧座数公式等价 ----------------

## 旧口径：star 星的总 DPS = 座数(★+1) × 单发 ÷ (turret_fire_cd × 觉醒 cd_mult) + 单层灼烧。
## 新口径：整把武器 = 单管直伤 × 齐射(★+1) ÷ 同一间隔 + 单层灼烧。
## 两者必须逐星相等 —— 这是「手动布设不砍数值」的全部依据。
func _check_volley_dps_parity() -> void:
	for wid in ["jiguan_nu", "jianzhen_pan", "penhuo_jiguanshou", "leishi_jiguan", "fenghuo_tai"]:
		var def := WeaponData.get_def(wid)
		if def.is_empty():
			continue
		for star in [1, 2, 3, 4]:
			var dmg := WeaponData.damage_for(wid, star)
			var interval := WeaponData.turret_fire_interval(wid, star)
			var old_total := dmg * float(star + 1) / interval
			if def.get("proc_burn", false):
				old_total += dmg * float(def.get("burn_ratio", 0.4)) \
					* minf(1.0, float(def.get("burn_dur", 2.5)) / interval)
			_c.near(WeaponData.sustained_weapon_dps(wid, star), old_total, 0.001,
				"%s ★%d 总 DPS 与旧「%d 座各自开火」等价" % [wid, star, star + 1])

# ---------------- 3. 耐久纯函数 ----------------

func _check_durability_math() -> void:
	# 连续开火恰好 STAMINA_SEC 秒磨到底：每发扣「该发间隔」对应的份额
	var interval := 0.5
	var per_shot := BalanceTurret.wear_per_shot(interval)
	_c.near(per_shot * (BalanceTurret.STAMINA_SEC / interval), BalanceTurret.MAX_DURABILITY, 0.001,
		"按开火间隔折算的磨损：连续开火 %d 秒正好磨满一条" % int(BalanceTurret.STAMINA_SEC))
	# 攻速翻倍不会更快磨坏：每秒磨损与间隔无关
	_c.near(BalanceTurret.wear_per_shot(0.25) * 4.0, BalanceTurret.wear_per_shot(0.5) * 2.0, 0.001,
		"单位时间磨损与开火间隔无关（加速只加快打完这段时间）")

	_c.check(not BalanceTurret.is_worn(100.0), "满耐久不算磨损")
	_c.check(BalanceTurret.is_worn(39.0), "耐久低于 40% 进入磨损档")
	_c.check(not BalanceTurret.is_worn(41.0), "耐久高于 40% 不降速")
	_c.near(BalanceTurret.fire_interval_mult(39.0), BalanceTurret.WORN_FIRE_INTERVAL_MULT, 0.001,
		"磨损档开火间隔 ×%.1f" % BalanceTurret.WORN_FIRE_INTERVAL_MULT)
	_c.near(BalanceTurret.fire_interval_mult(100.0), 1.0, 0.001, "完好档不降速")
	_c.check(BalanceTurret.is_broken(0.0), "耐久归零 = 停摆")
	_c.check(not BalanceTurret.is_broken(0.1), "耐久 0.1 仍可开火")
	_c.near(BalanceTurret.repair_per_sec() * BalanceTurret.REPAIR_HOLD_SEC,
		BalanceTurret.MAX_DURABILITY, 0.001,
		"长按 %.1f 秒正好回满一条耐久" % BalanceTurret.REPAIR_HOLD_SEC)

	# 落点：移动反方向外沿 / 静止朝下；空地校验用最近机关距离
	var off := BalanceTurret.deploy_offset(Vector2.RIGHT)
	_c.near(off.x, -BalanceTurret.DEPLOY_OFFSET, 0.001, "向右移动时机关落在身后")
	_c.near(BalanceTurret.deploy_offset(Vector2.ZERO).y, BalanceTurret.DEPLOY_OFFSET, 0.001,
		"静止时机关落在脚下偏下")
	_c.check(not BalanceTurret.is_open_ground(BalanceTurret.MIN_TURRET_SPACING - 1.0), "机身旁不算空地")
	_c.check(BalanceTurret.is_open_ground(BalanceTurret.MIN_TURRET_SPACING), "够远才算空地")

# ---------------- 4. 机关实体生命周期 ----------------

func _check_entity_lifecycle() -> void:
	var scene: PackedScene = load("res://scenes/weapons/TurretUnit.tscn")
	_turret = scene.instantiate() as TurretUnit
	_turret.setup("jiguan_nu", 1)
	_world.add_child(_turret)
	_turret.global_position = Vector2(300, 300)
	_turret.begin_life()
	await get_tree().process_frame

	_c.equals(_turret.weapon_def_id, "jiguan_nu", "机关成功装载机关弩")
	_c.check(_turret.is_in_group("turrets"), "机关自动加入 turrets 分组")
	_c.near(_turret.fire_cooldown, WeaponData.turret_fire_interval("jiguan_nu", 1), 0.01,
		"开火间隔 = 表值 × 觉醒 cd_mult（与 DPS 尺子同源）")
	_c.near(_turret.stamina_sec, 40.0, 0.001, "机关弩耐久时长 40 秒")
	_c.equals(_turret.volley, 2, "★1 机关弩双管齐射")
	_c.near(_turret.durability, BalanceTurret.MAX_DURABILITY, 0.001, "新布设机关满耐久")

	# 磨损 39%：降速档生效（停摆闸另有判据）
	_turret.durability = 39.0
	_turret.queue_redraw()
	var base_cd := _turret.fire_cooldown
	_c.near(_turret._eff_fire_cd(), base_cd * BalanceTurret.WORN_FIRE_INTERVAL_MULT, 0.01,
		"磨损档实际开火间隔 ×1.5")
	_c.check(_turret.needs_service(), "磨损档要维修（HUD 待修芯片同源）")

	# 停摆：有目标也不出手（_fire 会把冷却重置到 >=0.12；冷却停在 0 = 没出手）
	_turret.durability = 0.0
	_turret._cooldown_timer = 0.0
	_turret._search_timer = 0.0
	_turret.current_target = _player
	_turret._targets.append(_player)
	_turret._process(0.016)
	_c.check(_turret._cooldown_timer <= 0.0,
		"停摆机关即使有目标也不开火（冷却未被重置，实得 %.4f）" % _turret._cooldown_timer)
	_c.check(_turret.is_broken(), "停摆状态可读")
	# 收掉这条只用来验「不开火」的假目标：留着它这台机关下一帧会真的朝它出弹
	_turret._targets.clear()
	_turret.current_target = null

	# 维修：连续回填，0.8 秒回满
	_turret.begin_repair()
	_c.check(_turret.is_repairing(), "长按开始维修")
	var elapsed := 0.0
	while elapsed < BalanceTurret.REPAIR_HOLD_SEC + 0.05 and _turret.is_repairing():
		_turret._process(0.05)
		elapsed += 0.05
	_c.near(_turret.durability, BalanceTurret.MAX_DURABILITY, 0.001,
		"长按 %.1f 秒把停摆机关修满" % BalanceTurret.REPAIR_HOLD_SEC)
	_c.check(not _turret.is_repairing(), "修满后自动收手")
	_c.check(not _turret.needs_service(), "修满后退出待修态")

	# 修到一半松手：保留已修部分（不是「充满才算」）
	_turret.durability = 0.0
	_turret.begin_repair()
	_turret._process(0.2)
	var partial := _turret.durability
	_c.check(partial > 0.0 and partial < BalanceTurret.MAX_DURABILITY, "维修中耐久实时回填")
	_turret.end_repair()
	_c.near(_turret.durability, partial, 0.001, "松手保留已修耐久（不回退）")

	# 满耐久时 begin_repair 是空操作
	_turret.durability = BalanceTurret.MAX_DURABILITY
	_turret.begin_repair()
	_c.check(not _turret.is_repairing(), "满耐久按维修是空操作")

	# 回合末整备：停火 + 回满，且不消散
	_turret.durability = 12.0
	_turret.on_wave_end()
	_c.near(_turret.durability, BalanceTurret.MAX_DURABILITY, 0.001, "回合末整备把耐久回满")
	_c.check(not _turret._wave_active, "回合末整备停火（不等下一波不索敌）")
	_c.check(not _turret._is_dying, "回合末机关不消散（跨回合保留）")
	_turret.set_wave_active(true)
	_c.check(_turret._wave_active, "下波开始重新接管")

# ---------------- 5. 手动布设 / 收回 ----------------

func _check_deploy_and_recall() -> void:
	_fw = (load("res://scenes/weapons/FloatingWeapon.tscn") as PackedScene).instantiate()
	_fw.setup("jiguan_nu", 1)
	_holder.add_child(_fw)
	_fw.set_process(false)
	await get_tree().process_frame

	_c.check(bool(_fw.is_mechanism()), "机关弩被识别为机关武器")
	_c.equals(TurretCommand.ready_count(_player), 1, "上阵一把机关弩 = 1 份待布设编制")
	_c.equals(TurretCommand.deny_reason(_player), "", "脚下空地可以布设")

	var pos := TurretCommand.deploy_candidate_pos(_player)
	var placed: TurretUnit = TurretCommand.deploy_at_player(_player)
	await get_tree().process_frame
	_c.check(placed != null and is_instance_valid(placed), "布设成功")
	_c.equals(_fw.active_turrets.size(), 1, "一把武器只站一座机关")
	_c.check(placed.global_position.distance_to(pos) < 1.0, "落点就是调用方给的空地点")
	_c.equals(TurretCommand.ready_count(_player), 0, "编制用掉后待布设归零")
	_c.equals(TurretCommand.deny_reason(_player), "no_charge", "没编制时布设被拒")

	# 空地校验：机关脚下不算空地（落点太近）
	_c.check(not TurretCommand.is_open_ground(_player, placed.global_position), "机关脚下的落点不算空地")

	# 靠近判定：90px 内能拿到这台机关
	var near: TurretUnit = TurretCommand.nearest_turret(_player, _player.global_position,
		BalanceTurret.INTERACT_RADIUS)
	_c.check(near == placed, "玩家在交互半径内时能选中这台机关")

	# 收回：编制返还 + 整备冷却 + 耐久带回
	placed.durability = 55.0
	var recalled: bool = TurretCommand.recall_nearest(_player, _player.global_position)
	_c.check(recalled, "收回成功")
	_c.check(float(_fw.redeploy_timer) > 0.0, "收回后进入整备冷却")
	_c.check(not bool(_fw.deploy_ready()), "整备冷却期间不能重放")
	_c.near(float(_fw.pending_turret_durability), 55.0, 0.01, "收回把耐久带回本体（不是免费维修）")
	await get_tree().process_frame

	# 冷却走完 → 可重放，且新机关沿用带回的耐久
	_fw.redeploy_timer = 0.0
	_c.check(bool(_fw.deploy_ready()), "整备冷却结束后恢复编制")
	var again: TurretUnit = TurretCommand.deploy_at_player(_player)
	await get_tree().process_frame
	_c.check(again != null and is_instance_valid(again), "收回后能重新布设")
	_c.near(again.durability, 55.0, 0.01, "重放的机关沿用收回时的耐久")
	_c.near(float(_fw.pending_turret_durability), -1.0, 0.01, "布设后清掉待接管耐久")

	# 卖武器/卸下：机关立刻收回（旧版靠 10~12s 寿命兜底，新版没有寿命）
	_holder.remove_child(_fw)
	await get_tree().process_frame
	_c.check(again._is_dying, "武器离场时在役机关随之消散")
	_fw.queue_free()

# ---------------- 6. 齐射取目标（一管一个） ----------------

func _check_volley_targets() -> void:
	_turret.durability = BalanceTurret.MAX_DURABILITY
	# 齐射管数走 getter（星级管数 + 加点/道具加成）：「连环机括」那类加成走同一个出口
	GameManager.turret_volley_bonus = 3.0
	_c.equals(_turret.volley, 5, "★1 双管 + 3 管加成 = 五管齐射（加成走同一出口）")
	_turret.global_position = Vector2(500, 500)
	_turret.current_target = null
	_turret._targets.clear()
	var enemies: Array = []
	for i in 5:
		var e := FakeEnemy.new(Vector2(560.0 + float(i) * 18.0, 500.0))
		_world.add_child(e)
		enemies.append(e)
	await get_tree().physics_frame
	await get_tree().physics_frame

	_turret._refresh_targets()
	_c.equals(_turret._targets.size(), 5, "五管齐射一次取满 5 个目标")
	var uniq := {}
	for t in _turret._targets:
		uniq[t.get_instance_id()] = true
	_c.equals(uniq.size(), 5, "五个目标互不相同（不是同一发画五遍）")

	for e in enemies:
		e.queue_free()
	await get_tree().physics_frame
	await get_tree().process_frame
	_turret._refresh_targets()
	_c.equals(_turret._targets.size(), 0, "无敌人时索敌表为空")
	GameManager.turret_volley_bonus = 0.0

# ---------------- 7. 五行异常接线（2026-11-03 补漏） ----------------

func _check_proc_wiring() -> void:
	var cases: Array = [["hanquan_shou", "proc_chill"], ["tengluo_jiguan", "proc_poison"],
		["penhuo_jiguanshou", "proc_burn"]]
	for case in cases:
		var wid: String = String(case[0])
		var key: String = String(case[1])
		_turret.setup(wid, 1)
		_turret.global_position = Vector2(700, 700)
		_turret.begin_life()
		await get_tree().process_frame
		var e := FakeEnemy.new(Vector2(760, 700))
		_world.add_child(e)
		await get_tree().physics_frame
		await get_tree().physics_frame
		_turret._refresh_targets()
		_c.check(not _turret._targets.is_empty(), "%s 能锁到目标" % wid)
		_turret._cooldown_timer = 0.0
		_turret._process(0.016)
		await get_tree().process_frame
		var latest := _latest_projectile()
		_c.check(latest != null, "%s 出手生成了弹丸" % wid)
		if latest != null:
			var diag := "（最新弹丸 chill=%.2f poison=%s burn=%s）" % [
				latest.proc_chill, str(latest.proc_poison), str(latest.proc_burn)]
			match key:
				"proc_chill":
					_c.check(latest.proc_chill > 0.0,
						"%s 的冰缓真的挂到弹丸上了（旧版只接了灼烧）%s" % [wid, diag])
				"proc_poison":
					_c.check(latest.proc_poison,
						"%s 的剧毒真的挂到弹丸上了（旧版只接了灼烧）%s" % [wid, diag])
				"proc_burn":
					_c.check(latest.proc_burn, "%s 的灼烧仍然生效%s" % [wid, diag])
		e.queue_free()
		await get_tree().physics_frame

func _latest_projectile() -> BladeProjectile:
	# 判据读「最近一次出膛」的那一发：池化复用不会把节点移到宿主末尾（复用弹丸留在原
	# 子节点下标上），所以拼「最后一个孩子」会读上一发的残值。activate() 每次出膛把
	# launch_id 抬一档，按最大 launch_id 找才是真·最新一发。
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var host := scene.get_node_or_null("BladeProjectilePool")
	if host == null:
		return null
	var found: BladeProjectile = null
	var best_id := -1
	for child in host.get_children():
		if child is BladeProjectile and is_instance_valid(child) and not child._pooled and child.launch_id > best_id:
			best_id = child.launch_id
			found = child
	return found

# ---------------- 8. 机关养成（耐久 / 维修 / 停摆兜底） ----------------

func _check_maintenance_progression() -> void:
	_turret.setup("jiguan_nu", 1)
	_turret.global_position = Vector2(300, 300)
	_turret.begin_life()
	await get_tree().process_frame

	_c.near(_turret.effective_stamina(), _turret.stamina_sec, 0.001, "无加成时实际耐久 = 表值")
	GameManager.turret_stamina_mul = 1.5
	_c.near(_turret.effective_stamina(), _turret.stamina_sec * 1.5, 0.001,
		"耐久乘区（机关养护 / 机枢油）拉长实际耐久")
	_c.near(_turret.repair_hold_sec(), BalanceTurret.REPAIR_HOLD_SEC, 0.001,
		"无加成时维修用时 = %.1fs" % BalanceTurret.REPAIR_HOLD_SEC)
	GameManager.turret_repair_haste_mul = 0.5
	_c.near(_turret.repair_hold_sec(), BalanceTurret.REPAIR_HOLD_SEC * 0.5, 0.001,
		"维修用时乘区减半（机关养护叠层）")

	# 实际回填：0 耐久在减半后的 0.4s 内修满
	_turret.durability = 0.0
	_turret.begin_repair()
	var t := 0.0
	while t < 0.45 and _turret.is_repairing():
		_turret._process(0.05)
		t += 0.05
	_c.near(_turret.durability, BalanceTurret.MAX_DURABILITY, 0.001, "维修用时减半后 0.4s 修满")
	GameManager.turret_stamina_mul = 1.0
	GameManager.turret_repair_haste_mul = 1.0

	# 停摆兜底（恒机芯）：无道具完全停工，有道具半速继续
	_c.check(_turret.broken_haste() <= 0.0, "无道具时停摆 = 完全停工")
	_turret.durability = 0.0
	_turret._cooldown_timer = 0.0
	_turret._search_timer = 1.0
	_turret._targets.clear()
	_turret._targets.append(_player)
	_turret._process(0.016)
	_c.check(_turret._cooldown_timer <= 0.0, "无恒机芯时停摆不开火")
	GameManager.items.append("hengjixin")
	_c.near(_turret.broken_haste(), 0.5, 0.001, "恒机芯让停摆倍率 = 0.5")
	_turret._cooldown_timer = 0.0
	_turret._search_timer = 1.0
	_turret._targets.clear()
	_turret._targets.append(_player)
	_turret._process(0.016)
	_c.check(_turret._cooldown_timer > 0.0, "带恒机芯时停摆仍以半速开火（冷却被重置）")
	GameManager.items.erase("hengjixin")
	_turret._targets.clear()
	_turret.current_target = null
	_turret.durability = BalanceTurret.MAX_DURABILITY

# ---------------- 9. 双联神机（编制 +1） ----------------

func _check_extra_charges() -> void:
	_fw = (load("res://scenes/weapons/FloatingWeapon.tscn") as PackedScene).instantiate()
	_fw.setup("jiguan_nu", 1)
	_holder.add_child(_fw)
	_fw.set_process(false)
	_player.global_position = Vector2.ZERO
	await get_tree().process_frame
	_c.equals(int(_fw.turret_cap()), 1, "默认编制 1 座")
	GameManager.items.append("shen_shuanglian")
	_c.equals(int(_fw.turret_cap()), 2, "双联神机让每把武器编制翻倍")
	_c.equals(TurretCommand.ready_count(_player), 2, "编制 2 时待布设读数是 2")

	var a: TurretUnit = TurretCommand.deploy_at_player(_player)
	await get_tree().process_frame
	# 第二座要离第一座 ≥ MIN_TURRET_SPACING，先把人挪开
	_player.global_position = Vector2(400, 0)
	var b: TurretUnit = TurretCommand.deploy_at_player(_player)
	await get_tree().process_frame
	_c.check(a != null and b != null and a != b, "同一把武器可以布设两座")
	_c.equals(_fw.field_turrets().size(), 2, "场上两座都在编制表里")
	_c.equals(TurretCommand.ready_count(_player), 0, "两座落完后编制用尽")

	# 点名收回最近的那一座
	_player.global_position = b.global_position + Vector2(20, 0)
	var recalled: bool = TurretCommand.recall_nearest(_player, _player.global_position)
	await get_tree().process_frame
	_c.check(recalled, "多编制下能收回其中一座")
	_c.check(b._is_dying, "收回的是最近的那一座（点名收回）")
	_c.check(not a._is_dying, "另一座不受影响")
	_c.equals(_fw.field_turrets().size(), 1, "收回后场上只剩一座")

	GameManager.items.erase("shen_shuanglian")
	_holder.remove_child(_fw)
	_fw.queue_free()
	await get_tree().process_frame


# ---------------- 10. 跨回合保留 ----------------

func _check_wave_end_keep() -> void:
	_turret.durability = 20.0
	_turret.on_wave_end()
	await get_tree().process_frame
	_c.check(is_instance_valid(_turret) and _turret.is_inside_tree(), "回合末整备后机关仍在场上")
	_c.near(_turret.durability, BalanceTurret.MAX_DURABILITY, 0.001, "回合末整备耐久回满")
	_c.check(not _turret._wave_active, "回合末整备停火")