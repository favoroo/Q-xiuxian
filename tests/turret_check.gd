extends Node

## tests/turret_check.gd — 机关（Behavior.TURRET）手动布设 / 齐射 / 耐久维修 / 收回 判据
## 运行: python3 tools/run_test.py TurretCheck
##       （或 $G --headless --path . res://tests/TurretCheck.tscn）
##
## 2026-11-03 改版口径：
##   ① 每把机关武器只带 1 座（旧 turret_cap + (星-1) 自动布设废弃）；
##   ② 少掉的座数换算成齐射管数（★1 双管 … ★4 五管），座数→管数的换算逐星等价；
##      单发伤害另有 2026-11-03「手动操作补偿」整体 +10%（WeaponData），不在等价对账里
##   ③ 机关开火磨损耐久：<40% 降速、=0 停摆；靠近长按 1.6s 连续回填；
##   ④ 收回起固定 2 秒整备倒数（不倒扣耐久），耐久随机关带回（收回不是免费维修）；
##   ⑤ 回合末整备不清场（跨回合保留位置），下波重新接管；
##   ⑥ 布设/收回有地面法阵 + 空中器核投送：布设从人物飞向落点、收回从机关飞回人物；
##   ⑦ 维修期间有持续灵气索演出（机关端维护环 + 人物端连线），修满有扩散环收尾。
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

## 布设/收回法阵演出的脚本（无 class_name，按路径预载后比对 get_script）
const TURRET_PLACEMENT_FX := preload("res://scripts/weapons/TurretPlacementFx.gd")
## 布设/收回器核投送（人物 ↔ 机关）
const TURRET_TRANSFER_FX := preload("res://scripts/weapons/TurretTransferFx.gd")
## 维修灵气索
const TURRET_REPAIR_FX := preload("res://scripts/weapons/TurretRepairFx.gd")

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

## 假宿主（场景拿不到）：TurretHandler 对宿主全是鸭类型访问，喂一个没有场景的 Node 就能走完
class BrokenSceneHost extends Node2D:
	var active_turrets: Array = []
	var weapon_def_id: String = "jiguan_nu"
	var star: int = 1
	var is_attacking: bool = false
	## 宿主的落位下沉常量（部署演出按无类型实例访问，判据桩要给出同名字段）
	var TURRET_DIP: float = 0.06

	func turret_scene() -> PackedScene:
		return null

	func turret_cap() -> int:
		return 1

	func _begin_lunge(_dip: float, _t1: float, _t2: float, _left: bool) -> void:
		pass

	func _flash_sprite(_c: Color, _t: float) -> void:
		pass

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
	await _check_recall_anywhere()
	await _check_chest_targeting()
	await _check_scene_fallback()
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

## 找一朵指定类型的落位法阵演出（布设与收回可能同帧并存，按 kind 区分）
func _find_placement_fx(kind: int) -> Node:
	for child in _world.get_children():
		if child.get_script() == TURRET_PLACEMENT_FX and int(child.call("kind")) == kind:
			return child
	return null

## 找一枚指定方向的器核投送（布设/收回可能同帧并存）
func _find_transfer_fx(kind: int) -> Node:
	for child in _world.get_children():
		if child.get_script() == TURRET_TRANSFER_FX and int(child.call("kind")) == kind:
			return child
	return null

## 找维修灵气索（同屏最多一条）
func _find_repair_fx() -> Node:
	for child in _world.get_children():
		if child.get_script() == TURRET_REPAIR_FX:
			return child
	return null

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
## 两者必须逐星相等 —— 这验的是「座数→管数」换算本身；单发伤害的 +10% 手动操作补偿
## （2026-11-03）在 WeaponData 表值里，两边同源，不改变这条等式。
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
	# 提前预警：60% 就提示玩家去维修，但真正降速仍要等 40%
	_c.check(BalanceTurret.needs_service(50.0), "耐久 50% 就进入待修提示（提前预警）")
	_c.check(not BalanceTurret.needs_service(70.0), "耐久 70% 不提示维修")
	_c.check(not BalanceTurret.is_worn(50.0), "50% 只提示、不降速")
	_c.check(BalanceTurret.needs_service(0.0), "停摆也算待修")
	_c.check(BalanceTurret.WARN_RATIO > BalanceTurret.WORN_RATIO,
		"预警阈值必须早于降速阈值（先提示、后惩罚）")
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
	_c.near(_turret.stamina_sec, 30.0, 0.001, "机关弩耐久时长 30 秒（2026-11-03 40→30）")
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

	# 维修：连续回填，REPAIR_HOLD_SEC 秒回满
	_turret.begin_repair()
	_c.check(_turret.is_repairing(), "长按开始维修")
	# 维修过程要有持续演出：灵气索挂在战场上（人物 → 机关），不是只有 HUD 走针环
	var repair_fx := _find_repair_fx()
	_c.check(repair_fx != null, "维修期间有灵气索演出（人物 → 机关）")
	if repair_fx != null:
		_c.check(repair_fx.get_parent() == _turret.get_parent(),
			"灵气索挂在战场上而不是机关子节点（不跟着本体折叠/缩放）")
	var elapsed := 0.0
	while elapsed < BalanceTurret.REPAIR_HOLD_SEC + 0.05 and _turret.is_repairing():
		_turret._process(0.05)
		elapsed += 0.05
	_c.near(_turret.durability, BalanceTurret.MAX_DURABILITY, 0.001,
		"长按 %.1f 秒把停摆机关修满" % BalanceTurret.REPAIR_HOLD_SEC)
	_c.check(not _turret.is_repairing(), "修满后自动收手")
	_c.check(repair_fx == null or not is_instance_valid(repair_fx) or bool(repair_fx.call("is_stopping")),
		"修满后灵气索进入收束（不在场上常亮）")
	_c.check(not _turret.needs_service(), "修满后退出待修态")

	# 修到一半松手：保留已修部分（不是「充满才算」）
	_turret.durability = 0.0
	_turret.begin_repair()
	_turret._process(0.2)
	var partial := _turret.durability
	_c.check(partial > 0.0 and partial < BalanceTurret.MAX_DURABILITY, "维修中耐久实时回填")
	_turret.end_repair()
	_c.near(_turret.durability, partial, 0.001, "松手保留已修耐久（不回退）")

	# 头顶「维修中 N%」读当前耐久，不是本次维修进度（旧写法一按就从 0% 涨，玩家以为耐久归零）
	_turret.durability = 40.0
	_turret.begin_repair()
	_turret._process(0.0)
	_c.equals(_turret._readout_label.text, "维修中 40%",
		"维修中数字 = 当前耐久 40%，不是本次进度 0%")
	_c.near(_turret.repair_ratio(), 0.0, 0.001, "进度环仍从 0 起（只给走针环 / 盘缘弧用）")
	_turret.end_repair()

	# 满耐久时 begin_repair 是空操作
	_turret.durability = BalanceTurret.MAX_DURABILITY
	_turret.begin_repair()
	_c.check(not _turret.is_repairing(), "满耐久按维修是空操作")

	# 2026-11-04 取消站定限制：维修圈内可以边走边修（真机反馈站定太容易死）
	_turret.durability = 0.0
	_player.global_position = _turret.global_position + Vector2(30, 0)
	_turret.begin_repair()
	_turret._process(0.2)
	var before_move := _turret.durability
	_c.check(before_move > 0.0, "开始维修后正常回填")
	_player.global_position = _turret.global_position + Vector2(70, 0)
	_turret._process(0.2)
	_c.check(_turret.is_repairing(), "在维修圈内移动不会中断维修")
	_c.check(_turret.durability > before_move, "移动中耐久继续回填")
	_turret.end_repair()

	# 维修时机关停火：有目标、冷却到点也不出弹（维修不是白嫖，要挑安全窗口）
	_turret.durability = 40.0
	_turret.begin_repair()
	_turret._cooldown_timer = 0.0
	_turret._targets.clear()
	_turret._targets.append(_player)
	_turret._process(0.016)
	_c.check(_turret._cooldown_timer <= 0.0, "维修时机关停火（冷却未被重置）")
	_turret._targets.clear()
	_turret.end_repair()
	_turret.durability = BalanceTurret.MAX_DURABILITY
	_player.global_position = Vector2.ZERO

	# 回合末整备：停火 + 回满，且不消散
	_turret.durability = 12.0
	_turret.on_wave_end()
	_c.near(_turret.durability, BalanceTurret.MAX_DURABILITY, 0.001, "回合末整备把耐久回满")
	_c.check(not _turret._wave_active, "回合末整备停火（不等下一波不索敌）")
	_c.check(not _turret._is_dying, "回合末机关不消散（跨回合保留）")
	_turret.set_wave_active(true)
	_c.check(_turret._wave_active, "下波开始重新接管")

	# 空闲冷却钳制：无目标时 _cooldown_timer 扣成负数自动钳到 0
	_turret.current_target = null
	_turret._targets.clear()
	_turret._had_target = false
	_turret._cooldown_timer = -5.0
	_turret._process(0.016)
	_c.check(_turret._cooldown_timer >= 0.0,
		"无目标空闲时负冷却被钳到 >= 0（实得 %.4f）" % _turret._cooldown_timer)

	# 接目标首拍错峰：由闲转战首拍有 0~0.15s 错峰延迟
	_turret._cooldown_timer = 0.0
	_turret._had_target = false
	_turret.current_target = _player
	_turret._targets.append(_player)
	_turret._process(0.016)
	_c.check(_turret._had_target, "接敌后 _had_target 标为 true")
	_c.check(_turret._cooldown_timer >= 0.0 and _turret._cooldown_timer <= 0.16,
		"接目标首拍有 0~0.15 错峰（实得 %.4f）" % _turret._cooldown_timer)
	_turret._targets.clear()
	_turret.current_target = null
	_turret._had_target = false

	# 升星就地更新在役机关渲染器星钉
	_turret.setup("jiguan_nu", 3)
	if _turret._proc_renderer != null:
		_c.equals(_turret._proc_renderer.star, 3, "升星就地更新在役机关矢量渲染器 star 钉数")
	else:
		_c.check(true, "该器形无矢量渲染器，跳过星钉断言")
	_turret.setup("jiguan_nu", 1)

	# 维修范围提示：进圈亮、出圈灭，和 HUD 切「维修」态读同一个 INTERACT_RADIUS
	_turret.durability = 55.0
	_player.global_position = _turret.global_position + Vector2(BalanceTurret.INTERACT_RADIUS - 5.0, 0)
	_turret._process(0.016)
	_c.check(_turret._player_in_repair_range, "玩家进入维修半径 → 机关亮起范围提示")
	_player.global_position = _turret.global_position + Vector2(BalanceTurret.INTERACT_RADIUS + 5.0, 0)
	_turret._process(0.016)
	_c.check(not _turret._player_in_repair_range, "玩家离开维修半径 → 范围提示熄灭")
	_turret.durability = BalanceTurret.MAX_DURABILITY
	_player.global_position = Vector2.ZERO

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
	# 布设先播「人物 → 落点」的器核投送：器核没到之前本体不显形、不开火
	_c.check(not placed._arrived, "布设投送期间本体尚未显形")
	var transfer_fx := _find_transfer_fx(TURRET_TRANSFER_FX.KIND_DEPLOY)
	_c.check(transfer_fx != null, "布设有器核投送演出（不是凭空出现）")
	if transfer_fx != null:
		_c.check(transfer_fx.get_parent() == placed.get_parent(),
			"器核挂在战场上而不是机关子节点（不跟着缩放/上浮）")
		_c.check(transfer_fx.origin().distance_to(_player.global_position) < 12.0,
			"布设器核从人物身上出发")
		_c.check(transfer_fx.destination().distance_to(pos) < 2.0,
			"布设器核飞向机关落点")
	# 等器核到达：落点地面法阵这时才铺开，本体展开扶正
	await get_tree().create_timer(TURRET_TRANSFER_FX.DEPLOY_SEC + 0.06).timeout
	_c.check(placed._arrived, "器核到达后本体显形")
	var deploy_fx := _find_placement_fx(TURRET_PLACEMENT_FX.KIND_DEPLOY)
	_c.check(deploy_fx != null, "器核落地有法阵铺开演出")
	if deploy_fx != null:
		_c.check(deploy_fx.get_parent() == placed.get_parent(),
			"落位法阵挂在战场上而不是机关子节点（不跟着缩放/上浮）")

	# 空地校验：机关脚下不算空地（落点太近）
	_c.check(not TurretCommand.is_open_ground(_player, placed.global_position), "机关脚下的落点不算空地")

	# 靠近判定：交互半径（维修距离）内能拿到这台机关
	var near: TurretUnit = TurretCommand.nearest_turret(_player, _player.global_position,
		BalanceTurret.INTERACT_RADIUS)
	_c.check(near == placed, "玩家在交互半径内时能选中这台机关")

	# 收回：不限距离、只收最近一座、收回当刻即可重摆（2026-11-03 用户口径）
	placed.durability = 55.0
	var recalled: bool = TurretCommand.recall_nearest(_player, _player.global_position)
	_c.check(recalled, "收回成功")
	# 收回过程要有演出：先播折叠/收拢动画再回池，不是当场从场上抹掉
	var recall_fx := _find_placement_fx(TURRET_PLACEMENT_FX.KIND_RECALL)
	_c.check(recall_fx != null, "收回有法阵收拢演出（不是凭空消失）")
	var recall_transfer := _find_transfer_fx(TURRET_TRANSFER_FX.KIND_RECALL)
	_c.check(recall_transfer != null, "收回有器核飞回人物演出（不是只原地消失）")
	if recall_transfer != null:
		_c.check(recall_transfer.origin().distance_to(placed.global_position) < 2.0,
			"收回器核从机关身上出发")
		_c.check(recall_transfer.destination().distance_to(_player.global_position) < 14.0,
			"收回器核飞向人物身上")
	_c.check(is_instance_valid(placed) and placed.is_inside_tree(),
		"收回先播折叠动画再回池（不是当场移除）")
	_c.near(float(_fw.redeploy_timer), BalanceTurret.RECALL_COOLDOWN_SEC, 0.01,
		"收回后进入整备倒数（当前配置 = 0 秒）")
	_c.near(BalanceTurret.RECALL_COOLDOWN_SEC, 0.0, 0.001, "收回后没有等待（用户口径：立刻可部署）")
	_c.check(bool(_fw.deploy_ready()), "收回当刻就能重新布设")
	_c.near(float(_fw.pending_turret_durability), 55.0, 0.01, "收回把耐久带回本体（不是免费维修）")
	await get_tree().process_frame

	_fw.redeploy_timer = 0.0
	_c.check(bool(_fw.deploy_ready()), "编制仍可用")
	var again: TurretUnit = TurretCommand.deploy_at_player(_player)
	await get_tree().process_frame
	_c.check(again != null and is_instance_valid(again), "收回后能重新布设")
	_c.near(again.durability, 55.0, 0.01, "重放的机关沿用收回时的耐久")
	_c.near(float(_fw.pending_turret_durability), -1.0, 0.01, "布设后清掉待接管耐久")

	# 收回一座 20% 耐久机关：波末整备回满待布设耐久并清零倒数
	again.durability = 20.0
	var recalled_wave: bool = TurretCommand.recall_nearest(_player, _player.global_position)
	_c.check(recalled_wave, "收回 20% 耐久机关成功")
	_c.near(float(_fw.pending_turret_durability), 20.0, 0.01, "待布设记录 20% 耐久")
	_c.near(float(_fw.redeploy_timer), BalanceTurret.RECALL_COOLDOWN_SEC, 0.01, "收回后处于整备倒数中（当前 0 秒）")

	# 模拟 WaveSpawner 波末循环（对 player.weapon_holder 子节点调 on_wave_end）
	var p_holder = _player.get("weapon_holder") as Node
	for w in p_holder.get_children():
		if w != null and is_instance_valid(w) and w.has_method("on_wave_end"):
			w.on_wave_end()
	_c.near(float(_fw.redeploy_timer), 0.0, 0.001, "波末整备清零整备倒数")
	_c.near(float(_fw.pending_turret_durability), -1.0, 0.01, "波末整备清空待接管耐久（回满）")
	_c.check(_fw.pending_turret_durabilities.is_empty(), "待接管耐久队列已清空")
	_c.check(bool(_fw.deploy_ready()), "下波开始待布设编制立即可用")

	var wave_placed: TurretUnit = TurretCommand.deploy_at_player(_player)
	await get_tree().process_frame
	_c.check(wave_placed != null and is_instance_valid(wave_placed), "下波成功布设新机关")
	_c.near(wave_placed.durability, BalanceTurret.MAX_DURABILITY, 0.01, "下波重放的机关为满耐久")

	# 卖武器/卸下：机关立刻收回（旧版靠 10~12s 寿命兜底，新版没有寿命）
	_holder.remove_child(_fw)
	await get_tree().process_frame
	_c.check(wave_placed._is_dying, "武器离场时在役机关随之消散")
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
		_turret._had_target = true
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

	# 实际回填：0 耐久在减半后的 REPAIR_HOLD_SEC × 0.5 秒内修满
	var halved_hold := BalanceTurret.REPAIR_HOLD_SEC * 0.5
	_turret.durability = 0.0
	_turret.begin_repair()
	var t := 0.0
	while t < halved_hold + 0.05 and _turret.is_repairing():
		_turret._process(0.05)
		t += 0.05
	_c.near(_turret.durability, BalanceTurret.MAX_DURABILITY, 0.001,
		"维修用时减半后 %.2fs 修满" % halved_hold)
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
	_turret._had_target = true
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

	# 双联两座各 20/80 耐久，分别收回，重放两座各自带回耐久
	_fw.redeploy_timer = 0.0
	_player.global_position = Vector2(400, 0)
	b = TurretCommand.deploy_at_player(_player)
	await get_tree().process_frame
	_c.equals(_fw.field_turrets().size(), 2, "重新布设满两座")

	a.durability = 20.0
	b.durability = 80.0
	_fw.recall_turret(a)
	_fw.recall_turret(b)
	await get_tree().process_frame
	_c.equals(_fw.field_turrets().size(), 0, "两座均已收回")
	_c.equals(_fw.pending_turret_durabilities.size(), 2, "待布设队列记录 2 份耐久")

	# 清零倒数后重放两座（判据不等 2 秒真实时间）
	_fw.redeploy_timer = 0.0
	_player.global_position = Vector2(0, 0)
	var t1: TurretUnit = TurretCommand.deploy_at_player(_player)
	await get_tree().process_frame
	_c.check(t1 != null and is_instance_valid(t1), "成功重放第一座")

	_player.global_position = Vector2(400, 0)
	var t2: TurretUnit = TurretCommand.deploy_at_player(_player)
	await get_tree().process_frame
	_c.check(t2 != null and is_instance_valid(t2), "成功重放第二座")

	var d_list: Array[float] = [t1.durability, t2.durability]
	d_list.sort()
	_c.near(d_list[0], 20.0, 0.01, "双联重放之一带回 20 耐久")
	_c.near(d_list[1], 80.0, 0.01, "双联重放之二带回 80 耐久")
	_c.near(float(_fw.pending_turret_durability), -1.0, 0.01, "两座均重放后待布设耐久清为 -1")
	_c.check(_fw.pending_turret_durabilities.is_empty(), "两座均重放后待布设队列清空")

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


# ---------------- 10b. 收回不限距离（2026-11-03 用户口径） ----------------

## 机关打不到宝箱时玩家常常站在场子另一头：收回若还要跑过去，整套阵地玩法就卡死了。
## 现在 RECALL_RADIUS <= 0 = 全场任意位置都能收回，且永远只收「离玩家最近的那一座」。
func _check_recall_anywhere() -> void:
	_c.near(BalanceTurret.RECALL_RADIUS, -1.0, 0.001, "收回半径配置为「不限距离」")
	_c.near(BalanceTurret.RECALL_COOLDOWN_SEC, 0.0, 0.001, "收回后无整备倒数")

	_fw = (load("res://scenes/weapons/FloatingWeapon.tscn") as PackedScene).instantiate()
	_fw.setup("jiguan_nu", 1)
	_holder.add_child(_fw)
	_fw.set_process(false)
	GameManager.items.append("shen_shuanglian")
	_player.global_position = Vector2.ZERO
	await get_tree().process_frame

	var near_one: TurretUnit = TurretCommand.deploy_at_player(_player)
	await get_tree().process_frame
	_player.global_position = Vector2(600, 0)
	var far_one: TurretUnit = TurretCommand.deploy_at_player(_player)
	await get_tree().process_frame
	_c.equals(_fw.field_turrets().size(), 2, "前提：场上有两座机关")

	# 玩家跑到 (1000, 1000)：离两座都远超维修交互半径
	_player.global_position = Vector2(1000, 1000)
	var cand: TurretUnit = TurretCommand.recall_candidate(_player, _player.global_position)
	_c.check(cand != null, "远离机关（超出维修交互半径）时仍能选中收回目标")
	_c.check(cand == far_one, "选中的是离玩家最近的那一座")
	var recalled: bool = TurretCommand.recall_nearest(_player, _player.global_position)
	_c.check(recalled, "远离机关也能收回")
	_c.check(far_one._is_dying, "收回的是最近的那一座")
	_c.check(not near_one._is_dying, "另一座不受影响")
	_c.equals(_fw.field_turrets().size(), 1, "收回后场上剩一座")
	_c.check(bool(_fw.deploy_ready()), "收回当刻编制就返还（可以立刻重摆）")

	# 重摆后再收一次：验证「不限距离」对每一座都成立
	var replaced: TurretUnit = TurretCommand.deploy_at_player(_player)
	await get_tree().process_frame
	_c.check(replaced != null, "远离时也能立刻重摆")
	_player.global_position = Vector2(-1000, -1000)
	var recalled2: bool = TurretCommand.recall_nearest(_player, _player.global_position)
	_c.check(recalled2, "对角另一端也能收回")

	GameManager.items.erase("shen_shuanglian")
	_holder.remove_child(_fw)
	_fw.queue_free()
	await get_tree().process_frame

# ---------------- 10c. 机关也砸宝箱（2026-11-03 用户「不知道怎么打宝箱」） ----------------

## 旧写法 `is_in_group("chests") ⇒ continue` 让机关永远不打匣子：玩家把机关摆在匣子边上，
## 匣子一直不动，只能跑过去手动收。口径与 FloatingWeapon/ProjectileHandler 一致 ——
## 有活妖时只打妖，活妖不够填满齐射管数才把多出来的管子分给最近的匣子。
func _check_chest_targeting() -> void:
	# 用独立实例，不复用 _turret：_check_wave_end_keep 刚把它设成整备态，
	# 后段 _check_scene_fallback 还要断言它没被重新激活
	var unit := (load("res://scenes/weapons/TurretUnit.tscn") as PackedScene).instantiate() as TurretUnit
	unit.setup("jiguan_nu", 1)
	_world.add_child(unit)
	unit.global_position = Vector2(900, 0)
	unit.begin_life()
	await get_tree().process_frame

	var chest := SpiritChest.new()
	chest.tier = BalanceChest.TIER_WOOD
	_world.add_child(chest)
	chest.global_position = Vector2(1020, 0)
	await get_tree().physics_frame

	# 场上没有活妖：齐射管子全部补到匣子上
	unit._refresh_targets()
	_c.check(unit._targets.size() == 1 and unit._targets[0] == chest,
		"场上只有宝箱时机关把它当目标（旧版永远跳过 chests）")

	# 活妖数量够填满齐射管数（★1 双管 → 放 2 只妖）：匣子一根管子都不抢
	var e1 := FakeEnemy.new(Vector2(980, 0))
	var e2 := FakeEnemy.new(Vector2(1000, 40))
	_world.add_child(e1)
	_world.add_child(e2)
	await get_tree().physics_frame
	unit._refresh_targets()
	_c.equals(unit.volley, 2, "前提：★1 双管齐射")
	_c.check(unit._targets.size() == 2 and not unit._targets.has(chest),
		"活妖够分齐射管数时机关只打妖（不甩开妖去砸匣子）")

	# 活妖不够（只留 1 只）：多出来的那一管补到匣子
	e2.queue_free()
	await get_tree().physics_frame
	unit._refresh_targets()
	_c.check(unit._targets.size() == 2, "妖不够分齐射管数时，多出来的管子补到宝箱")
	if unit._targets.size() == 2:
		_c.check(unit._targets[0] == e1, "第一管仍是最近的活妖")
		_c.check(unit._targets[1] == chest, "第二管补到宝箱")

	# 真开火闭环：匣子被砸掉击数（不只是索敌表对）
	# 先把夹具里的假敌人清场：它站在机关与匣子之间，弹丸会先撞它（穿透 1 就回收了）
	e1.queue_free()
	await get_tree().physics_frame
	var hits_before: int = chest.remaining_hits
	unit._targets.clear()
	unit._targets.append(chest)
	unit.current_target = chest
	unit._cooldown_timer = 0.0
	unit._fire()
	# 弹丸从机关飞 120px 才命中（speed 420 ⇒ 约 0.3s），等够飞行时间再读击数
	await get_tree().create_timer(0.6).timeout
	_c.check(chest.remaining_hits < hits_before,
		"机关开火真的能砸掉宝箱击数（实得 %d / 原 %d）" % [chest.remaining_hits, hits_before])
	chest.queue_free()
	unit._targets.clear()
	unit.current_target = null
	unit.dismiss()
	await get_tree().process_frame

# ---------------- 11. 场景兜底（真机「布设报不能布设」的最后一层保险） ----------------

## 导出包里机关场景可能拿不到（空 PackedScene / 场景根没挂脚本，坑 12 同源）：
## 以前 acquire_or_new 直接返回 null ⇒ 布设键有 ×N 读数却点不出机关，且没有任何可查的原因。
## 现在必须兜底成「代码按同结构搭一台」，onready 三件套（CoreSprite/MuzzlePoint/BaseRing）
## 一个都不能少，否则 _ready 一进树就报错。
func _check_scene_fallback() -> void:
	var unit := TurretUnit.acquire_or_new(null)
	_c.check(unit != null, "机关场景为空也能拿到一台机关（代码兜底）")
	if unit == null:
		return
	_c.check(unit.get_node_or_null("CoreSprite") is Sprite2D, "兜底机关有 CoreSprite（Sprite2D）")
	_c.check(unit.get_node_or_null("CoreSprite/MuzzlePoint") is Marker2D, "兜底机关有 MuzzlePoint（Marker2D）")
	_c.check(unit.get_node_or_null("BaseRing") is Node2D, "兜底机关有 BaseRing")
	unit.setup("jiguan_nu", 1)
	_world.add_child(unit)
	await get_tree().process_frame
	unit.begin_life(-1.0)
	_c.near(unit.durability, BalanceTurret.MAX_DURABILITY, 0.01, "兜底机关开局满耐久")

	# 宿主完全给不出场景时，布设链路也得走通（不再返回 null 让玩家干瞪眼）
	var host := BrokenSceneHost.new()
	_world.add_child(host)
	var made = TurretHandler.deploy(host, unit.global_position + Vector2(200, 0))
	_c.check(made != null, "宿主没有机关场景时仍能布设（走兜底）")
	_c.check(TurretHandler.last_error.is_empty(), "兜底成功时原因码保持空")
	if made != null:
		made.dismiss()
	host.queue_free()
	unit.dismiss()
	await get_tree().process_frame
	_c.check(not _turret._wave_active, "回合末整备停火")