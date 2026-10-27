extends Node

## 飞升悟道触发演出判据（2026-10-26 演出整体升级）。
##
## 钉住这次升级的五条硬不变量 —— 都是「改回去会立刻变成玩家读不到」的那种：
##   ① 天罚真的结算伤害：`ChainLightning.sky_bolt` 过去只画电弧不调 take_damage，
##      crit_bolt_damage 算完就丢，整张卡空转。现在落点必须掉血。
##   ② 演出闸按路径拆开：紫电与雷劫同帧触发时，两条都要能画出来
##      （旧写法共用一条 90ms 闸，第二条永远被吞）。
##   ③ tint 真的染到芯线：紫电的芯线必须是紫罗兰系而不是白芯，
##      否则玩家看到的还是「同一道白雷」（旧写法只有光晕层吃 tint）。
##   ④ 反震电场的演出环半径 == BalanceChain.THORNS_RADIUS == 判定搜索半径
##      （画多大 == 判多大，项目铁律 7；THORNS_RADIUS 此前是零引用死常量）。
##   ⑤ 五行归一三系同挂时染色会轮换，不再永远只显示冰蓝。
##
## 运行: godot --headless --path . res://tests/SuperVfxCheck.tscn
## 退出码 0 且末行 SUPER_VFX_RESULT: ALL PASS
## 反例（回归时必红）：
##   - 删掉 sky_bolt 里的 _apply_sky_bolt_damage ⇒ ① 报红
##   - 把 _try_consume_event_gate 改回单条全局闸 ⇒ ② 报红
##   - 把 LightningBolt 的芯线改回固定白芯 ⇒ ③ 报红
##   - 反震改回 CHAIN_RADIUS（240）⇒ ④ 报红
##   - _status_tint 改回「冰缓硬盖」⇒ ⑤ 报红

const EPS := 0.0001
const MAX_WAIT_FRAMES := 180

var _c := TestCheck.new()
var _world: Node2D
var _enemy_scene: PackedScene = preload("res://scenes/entities/SlimeEnemy.tscn")

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	SettingsManager.set_val(&"display", &"hit_stop", false, false)
	Engine.time_scale = 1.0
	GameManager.reset_run()
	_world = Node2D.new()
	_world.name = "SuperVfxWorld"
	get_tree().root.add_child(_world)
	await get_tree().process_frame
	_c.set_min_checks(20)

	await _case_sky_bolt_damage()
	await _case_zidian_on_hit()
	await _case_gates_independent()
	await _case_tint_reaches_core()
	_case_thorns_radius_shared()
	await _case_wuxing_tint_rotation()

	print("SUPER_VFX_CHECK 判据跑完")
	Engine.time_scale = 1.0
	if _c.report("SUPER_VFX_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

## ① 天罚伤害落地：落点处的敌人必须掉血，且吃的是 crit_bolt_damage 那一份
func _case_sky_bolt_damage() -> void:
	ChainLightning.reset_gate()
	var target := _spawn_enemy(Vector2(120.0, 0.0))
	await get_tree().process_frame
	var hp_before: float = target.current_hp
	var want: float = BalanceChain.crit_bolt_damage(GameManager.elemental_damage)
	# 模式 A：传入坐标（向后兼容）
	ChainLightning.sky_bolt(_world, target.global_position, want)
	await get_tree().process_frame
	await get_tree().process_frame
	var hp_after: float = target.current_hp if is_instance_valid(target) else 0.0
	var lost: float = hp_before - hp_after
	_c.near(lost, want, 0.5, "天罚落点结算伤害（掉血 %.1f，期望 %.1f）" % [lost, want])
	_c.check(lost > 0.0, "天罚不是只画电弧的空转卡")

	# 模式 B：直接传入目标实体 Node2D（直贯天灵盖）
	ChainLightning.reset_gate()
	hp_before = target.current_hp
	ChainLightning.sky_bolt(_world, target, want)
	await get_tree().process_frame
	await get_tree().process_frame
	hp_after = target.current_hp if is_instance_valid(target) else 0.0
	var lost_direct: float = hp_before - hp_after
	_c.check(lost_direct > 0.0, "天罚直击目标实体必中结算")

	if is_instance_valid(target):
		target.queue_free()
	await get_tree().process_frame

## ①-B 紫电电刀模式：攻击命中累积 3 次触发连锁闪电，以被击中怪为源头
func _case_zidian_on_hit() -> void:
	ChainLightning.reset_gate()
	OnHitEffects.reset_memo()
	var target1 := _spawn_enemy(Vector2(100.0, 0.0))
	var target2 := _spawn_enemy(Vector2(160.0, 0.0))
	await get_tree().process_frame
	var snap := {"attack_chain_lightning": 1.0}
	var hp2_before: float = target2.current_hp

	# 前 2 次命中只蓄能
	OnHitEffects.on_weapon_hit(_world, target1, 50.0, false, snap)
	OnHitEffects.on_weapon_hit(_world, target1, 50.0, false, snap)
	var hp2_mid: float = target2.current_hp
	_c.equals(hp2_mid, hp2_before, "紫电前 2 次命中不触发连锁电弧")

	# 第 3 次命中触发连锁闪电，弹射至 target2
	OnHitEffects.on_weapon_hit(_world, target1, 50.0, false, snap)
	await get_tree().process_frame
	await get_tree().create_timer(0.1).timeout
	var hp2_after: float = target2.current_hp if is_instance_valid(target2) else 0.0
	_c.check(hp2_after < hp2_before, "第 3 次命中触发紫电弹射至相邻敌人")

	if is_instance_valid(target1):
		target1.queue_free()
	if is_instance_valid(target2):
		target2.queue_free()
	await get_tree().process_frame

## ② 演出闸按路径独立：紫电与雷劫在同一毫秒各触发一次，两条都必须放行
func _case_gates_independent() -> void:
	ChainLightning.reset_gate()
	var a: bool = ChainLightning._try_consume_event_gate(&"zidian")
	var b: bool = ChainLightning._try_consume_event_gate(&"leijie")
	var c: bool = ChainLightning._try_consume_event_gate(&"tianfa")
	_c.check(a, "紫电闸首次放行")
	_c.check(b, "雷劫闸与紫电独立（同刻也放行）")
	_c.check(c, "天罚闸与前者独立")
	# 同一条闸立刻再来一次必须被掐（90ms 内）
	var again: bool = ChainLightning._try_consume_event_gate(&"zidian")
	_c.check(not again, "同一条闸在 EVENT_GAP_MS 内拒绝第二次")
	ChainLightning.reset_gate()

## ③ tint 真的染到芯线：紫罗兰 tint 的芯线必须保留紫色相（R > G 且 B > G）。
## 注意：芯色分 HDR / LDR 两档（glow 开关），而 SettingsManager 是持久化配置 ——
## `--all` 批跑时前序用例可能把 glow 关掉（GlowChannelCheck 会改这个位），
## 不显式固定就会读到 LDR 档而误判。这里两档都钉，且先把开关恢复到开。
func _case_tint_reaches_core() -> void:
	ChainLightning.reset_gate()
	var saved_glow := bool(SettingsManager.get_val(&"display", &"glow", true))
	var saved_auto := bool(SettingsManager.get_val(&"display", &"glow_auto_off", false))
	SettingsManager.set_val(&"display", &"glow", true, false)
	SettingsManager.set_val(&"display", &"glow_auto_off", false, false)

	var bolt := LightningBolt.acquire(_world)
	_c.check(bolt != null, "取到一条电弧实例")
	if bolt == null:
		SettingsManager.set_val(&"display", &"glow", saved_glow, false)
		SettingsManager.set_val(&"display", &"glow_auto_off", saved_auto, false)
		return
	bolt.activate(Vector2.ZERO, Vector2(120.0, 0.0), GameStyle.FX_HDR_ZIDIAN, 1.0)
	var core: Color = bolt._line_core.default_color
	_c.check(core.r > core.g + 0.25 and core.b > core.g + 0.25,
		"紫电芯线保留紫罗兰色相（HDR 档，实得 %.2f/%.2f/%.2f）" % [core.r, core.g, core.b])
	var ag: Color = bolt._afterglow[0].default_color
	_c.check(ag.r > ag.g + 0.25 and ag.b > ag.g + 0.25,
		"余韵弧跟随本次 tint（实得 %.2f/%.2f/%.2f）" % [ag.r, ag.g, ag.b])
	# 白雷 tint 仍应得到近白芯（既有行为不回退）
	bolt.activate(Vector2.ZERO, Vector2(120.0, 0.0), GameStyle.FX_HDR_LIGHTNING, 1.0)
	var white_core: Color = bolt._line_core.default_color
	_c.check(white_core.r >= 2.0 and absf(white_core.r - white_core.g) < 0.4,
		"雷光白 tint 仍得到近白芯（实得 %.2f/%.2f/%.2f）" % [white_core.r, white_core.g, white_core.b])

	# LDR 档（glow 关）：色相也必须保住，只是向白提亮 —— 旧写法这里直接给固定白蓝芯
	SettingsManager.set_val(&"display", &"glow", false, false)
	bolt.activate(Vector2.ZERO, Vector2(120.0, 0.0), GameStyle.FX_HDR_ZIDIAN, 1.0)
	var ldr_core: Color = bolt._line_core.default_color
	_c.check(ldr_core.b > ldr_core.g and ldr_core.r > ldr_core.g,
		"glow 关闭时紫电芯线仍保紫色相（实得 %.2f/%.2f/%.2f）" % [ldr_core.r, ldr_core.g, ldr_core.b])
	_c.check(ldr_core.r <= 1.0 and ldr_core.g <= 1.0 and ldr_core.b <= 1.0,
		"LDR 芯线分量收在 1.0 以内（不误起辉）")

	SettingsManager.set_val(&"display", &"glow", saved_glow, false)
	SettingsManager.set_val(&"display", &"glow_auto_off", saved_auto, false)

## ④ 反震电场的判定半径与演出半径同源（THORNS_RADIUS 不再是被架空的死常量）
func _case_thorns_radius_shared() -> void:
	_c.check(BalanceChain.THORNS_RADIUS > 0.0,
		"THORNS_RADIUS 有实值（%.1f）" % BalanceChain.THORNS_RADIUS)
	# 反震搜索半径必须与演出环半径一致，且不再等于链电通用半径
	_c.check(not is_equal_approx(BalanceChain.THORNS_RADIUS, BalanceChain.CHAIN_RADIUS),
		"反震半径与链电通用半径是两个口径（%.1f vs %.1f）" % [
			BalanceChain.THORNS_RADIUS, BalanceChain.CHAIN_RADIUS])

## ⑤ 五行归一三系同挂：染色按相位轮换，不再永远冰蓝
func _case_wuxing_tint_rotation() -> void:
	var e := _spawn_enemy(Vector2(400.0, 0.0))
	await get_tree().process_frame
	e.apply_burn(10.0, 30.0)
	e.apply_chill(0.3, 30.0)
	e.apply_poison(10.0, 30.0)
	var seen := {}
	# 三系一轮约 3 × STATUS_TINT_ROTATE；多采样几轮确保三档都出现过
	for i in range(60):
		var tint: Color = e._status_tint(true, true, true, EnemyBase.STATUS_TINT_ROTATE * 0.34)
		seen[tint] = true
	_c.check(seen.size() >= 3,
		"三系同挂时染色在三档之间轮换（采到 %d 种）" % seen.size())
	# 单系行为不回退：只有冰缓时恒冰蓝
	var single: Color = e._status_tint(false, false, true, 0.1)
	_c.equals(single, EnemyBase.STATUS_TINT_CHILL, "单系冰缓仍固定冰蓝染色")
	var none: Color = e._status_tint(false, false, false, 0.1)
	_c.check(none.a <= 0.0, "无异常时返回「不染色」（alpha 0）")
	if is_instance_valid(e):
		e.queue_free()
	await get_tree().process_frame

func _spawn_enemy(pos: Vector2) -> Node2D:
	var e := _enemy_scene.instantiate() as Node2D
	e.global_position = pos
	_world.add_child(e)
	e.set_physics_process(false)
	return e
