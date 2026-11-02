extends Node

## 祭坛成长线判据（2026-11-02：灵脉阶 + 灵兽分阶 + 血祭），真实 Main 场景，不打 mock。
## ① 初始阶：W1 未启动 ⇒ 祭坛 1 阶、渲染器 tier=1
## ② 血祭：金币 0 + 生命足够 ⇒ HUD 键面「血祭/耗18%」、进充能、爆发后扣 18% 生命、
##    金币不变、启动次数 +1、灵兽出生阶=当前祭坛阶
## ③ 晋阶：启动次数跨 3 ⇒ 祭坛 2 阶、渲染器 tier=2、新灵兽出生阶=2
## ④ 灵兽成长：存活 1/2 回合各 +1 阶、生命上限增加，满寿命消散
## ⑤ 波次兜底：wave=16 + wave_changed ⇒ 祭坛 4 阶（不依赖启动次数）
## 运行: $G --headless --path . res://tests/ObeliskEvolutionCheck.tscn

var _c := TestCheck.new()
var _player: Player
var _obelisk: BlessingObelisk
var _banner_seen := ""

func _ready() -> void:
	get_tree().root.size = Vector2i(960, 540)
	call_deferred("_run")

func _dismiss() -> void:
	for node_name in ["LevelUpDialog", "WaveShop", "PlayerStatsDialog", "PauseMenu", "SettingsDialog"]:
		var n := get_node_or_null("/root/Main/UILayer/" + node_name)
		if n != null and n.visible:
			n.visible = false
	get_tree().paused = false

func _settle(frames: int) -> void:
	for i in range(frames):
		await get_tree().physics_frame
		_dismiss()

## 场地静音：刷怪器不再出人、场上妖物散掉，血祭扣血/灵兽数值只由本判据自己写
func _quiet_arena() -> void:
	var spawner: Node = GameManager.wave_spawner
	if spawner != null:
		spawner.set_process(false)
		spawner.set_physics_process(false)
		spawner.phase = WaveSpawner.Phase.FIGHT
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is EnemyBase:
			enemy.dissolve()
	GameManager.hp_regen = 0.0
	GameManager.synergy_hp_regen = 0.0

func _run() -> void:
	SettingsManager.set_val(&"display", &"hit_stop", false, false)
	Engine.time_scale = 8.0
	GameManager.announcement_triggered.connect(func(t: String) -> void: _banner_seen = t)

	var main = load("res://scenes/main/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await _settle(2)
	GameManager.cultivator_id = ""
	GameManager.start_run("qingyun_sword")
	await _settle(2)
	_player = GameManager.player as Player
	_c.check(_player != null, "前置：玩家已生成")
	if _player == null:
		_quit()
		return
	_quiet_arena()
	await _settle(4)
	_obelisk = get_node_or_null("/root/Main/MapLayer/ObeliskCenter") as BlessingObelisk
	_c.check(_obelisk != null, "前置：祭坛节点可寻址")
	if _obelisk == null:
		_quit()
		return

	_case_initial_tier()
	await _case_blood_ritual()
	await _case_tier_up_on_activation()
	await _case_beast_stage_growth()
	await _case_wave_floor_tier()

	Engine.time_scale = 1.0
	_quit()

## ① 初始阶：W1 未启动，祭坛 1 阶，水晶渲染器同档
func _case_initial_tier() -> void:
	_c.equals(_obelisk._obelisk_tier, 1, "① 初始祭坛阶=1（W1 未启动）")
	_c.check(_obelisk._obelisk_renderer != null and _obelisk._obelisk_renderer.tier == 1,
		"① 水晶渲染器 tier=1")

## ② 血祭：金币 0、生命足够，键面切血祭；爆发后扣 18% 生命、金币不变、启动次数 +1、灵兽出生阶对
func _case_blood_ritual() -> void:
	GameManager.obelisk_activations = 1          # 免费档已用过，回到按波收费口径
	# 模拟首次免费召唤已经发生：基座应有 1 枚火苗；本 Case 再召一次后变 2 枚
	_obelisk._orbiters.set_count(GameManager.obelisk_activations)
	GameManager.spirit_stones = 0
	_player.current_health = _player.max_health
	var hp_before: float = _player.current_health
	var blood_cost := GameBalance.obelisk_blood_cost(_player.max_health)
	_obelisk.is_player_inside = true

	# HUD 键面：金币不足但血够 ⇒ 主文案「血祭」、价格「耗18%」
	var hud := get_node_or_null("/root/Main/UILayer/GameHUD")
	var ob_btn: HudObeliskButton = hud._obelisk_widget if hud != null else null
	_c.check(ob_btn != null, "② 前置：HUD 祭坛键在")
	if ob_btn != null:
		ob_btn.show_obelisk_activation(_obelisk)
		await get_tree().process_frame
		await get_tree().process_frame
		_c.equals(ob_btn.get_btn().text, "血祭", "② 金币不足且血够 ⇒ 键面主文案切「血祭」")
		_c.equals(ob_btn.get_price_label().text, "耗18%", "② 键面价格写「耗18%」")

	_banner_seen = ""
	_obelisk.start_charge()
	_c.check(_obelisk.is_charging and _obelisk._blood_mode, "② 血祭可用 ⇒ 进充能且标记血祭模式")
	await _settle(100)   # 充能 0.8s + 注入 0.45s（8 倍速）
	_c.check(_obelisk.spent_this_wave, "② 血祭爆发后祭坛进本回合灰相")
	_c.equals(GameManager.spirit_stones, 0, "② 血祭不扣金币")
	_c.equals(GameManager.obelisk_activations, 2, "② 血祭照常计入启动次数（1→2）")
	_c.check(_obelisk._orbiters != null and _obelisk._orbiters.orbiter_count() == 2,
		"② 累计召唤 2 次 ⇒ 基座 2 枚环绕火苗")
	_c.near(_player.current_health, maxf(1.0, hp_before - float(blood_cost)), 0.6,
		"② 血祭扣 18%% 最大生命（%d）" % blood_cost)
	_c.check(_banner_seen.contains("血祭"), "② 血祭横幅（实得：%s）" % _banner_seen)
	_c.equals(GameManager.live_allies.size(), 1, "② 血祭爆发后场上 1 只灵兽")
	if GameManager.live_allies.is_empty():
		return
	var beast := GameManager.live_allies[0] as SpiritBeast
	_c.check(beast != null, "② 召唤物是 SpiritBeast")
	if beast == null:
		return
	_c.equals(beast.altar_tier, _obelisk._obelisk_tier, "② 灵兽出生阶=当前祭坛阶")
	_c.equals(beast.stage, beast.altar_tier, "② 灵兽当回合阶段=出生阶")
	_c.near(beast.max_hp, GameBalance.spirit_beast_max_hp(beast.summon_wave, beast.stage), 0.6,
		"② 灵兽生命按出生阶取表")

## ③ 晋阶：下一次启动次数跨 3 ⇒ 祭坛 2 阶、水晶换档、新灵兽出生阶 2
func _case_tier_up_on_activation() -> void:
	# 先走一个回合：祭坛复燃，场上灵兽按存活回合晋阶（这里只关心祭坛）
	var next_wave: int = maxi(GameManager.wave_number, 1) + 1
	GameManager.wave_number = next_wave
	GameManager.wave_changed.emit(next_wave)
	await _settle(4)
	_c.check(not _obelisk.spent_this_wave, "③ 新回合祭坛复燃")
	_c.check(GameManager.obelisk_activations == 2, "③ 前置：启动次数 2（下一次跨 3）")

	GameManager.spirit_stones = GameBalance.obelisk_activation_cost(next_wave, GameManager.obelisk_activations)
	_obelisk.is_player_inside = true
	_banner_seen = ""
	_obelisk.start_charge()
	await _settle(100)
	_c.equals(GameManager.obelisk_activations, 3, "③ 启动次数到 3")
	_c.check(_obelisk._orbiters != null and _obelisk._orbiters.orbiter_count() == 3,
		"③ 累计召唤 3 次 ⇒ 基座 3 枚环绕火苗")
	_c.equals(_obelisk._obelisk_tier, 2, "③ 启动次数跨 3 ⇒ 祭坛晋 2 阶")
	_c.check(_obelisk._obelisk_renderer != null and _obelisk._obelisk_renderer.tier == 2,
		"③ 水晶渲染器同步 tier=2")
	_c.check(_banner_seen.contains("灵脉晋阶"), "③ 晋阶横幅（实得：%s）" % _banner_seen)
	_c.equals(GameManager.live_allies.size(), 2, "③ 晋阶这一发也召出灵兽（场上 2 只）")
	if GameManager.live_allies.size() < 2:
		return
	var newest := GameManager.live_allies[GameManager.live_allies.size() - 1] as SpiritBeast
	_c.check(newest != null, "③ 新召唤物是 SpiritBeast")
	if newest == null:
		return
	_c.equals(newest.altar_tier, 2, "③ 新灵兽出生阶=晋阶后的 2 阶")
	_c.equals(newest.stage, 2, "③ 新灵兽当回合阶段=2")

## ④ 灵兽成长：新灵兽存活 1/2 回合各 +1 阶、生命上限增加，满寿命消散
func _case_beast_stage_growth() -> void:
	if GameManager.live_allies.size() < 2:
		_c.check(false, "④ 前置：场上至少有 2 只灵兽")
		return
	var beast := GameManager.live_allies[GameManager.live_allies.size() - 1] as SpiritBeast
	if beast == null:
		_c.check(false, "④ 前置：新灵兽可寻址")
		return
	var hp_before: float = beast.max_hp
	var cur_before: float = beast.current_hp
	var stage_before: int = beast.stage
	beast._on_wave_changed(beast.summon_wave + 1)
	await _settle(2)
	_c.equals(beast.stage, mini(stage_before + 1, GameBalance.SPIRIT_BEAST_MAX_STAGE),
		"④ 存活 1 回合 ⇒ 阶段 +1（%d→%d）" % [stage_before, beast.stage])
	_c.check(beast.max_hp > hp_before, "④ 阶段 +1 ⇒ 生命上限增加（%.0f→%.0f）" % [hp_before, beast.max_hp])
	_c.check(beast.current_hp >= cur_before, "④ 升阶只补上限差额，当前生命不倒退")
	var hp_after_first: float = beast.max_hp
	beast._on_wave_changed(beast.summon_wave + 2)
	await _settle(2)
	_c.check(beast.stage >= mini(stage_before + 2, GameBalance.SPIRIT_BEAST_MAX_STAGE),
		"④ 存活 2 回合 ⇒ 阶段再 +1（实得 %d）" % beast.stage)
	_c.check(beast.max_hp >= hp_after_first, "④ 阶段继续成长 ⇒ 生命上限不回落")
	# 满寿命：召唤波起算第 3 个回合结束，下一次回合开始消散
	beast._on_wave_changed(beast.summon_wave + GameBalance.SPIRIT_BEAST_LIFETIME_WAVES)
	await _settle(60)
	_c.check(not is_instance_valid(beast), "④ 满寿命 ⇒ 灵兽消散")
	_c.check(not GameManager.live_allies.has(beast), "④ 消散后已从 allies 注销")

## ⑤ 波次兜底：不依赖启动次数，W16 起来祭坛直接 4 阶
func _case_wave_floor_tier() -> void:
	GameManager.wave_number = 16
	GameManager.wave_changed.emit(16)
	await _settle(4)
	_c.equals(_obelisk._obelisk_tier, 4, "⑤ W16 波次兜底 ⇒ 祭坛 4 阶")
	_c.check(_obelisk._obelisk_renderer != null and _obelisk._obelisk_renderer.tier == 4,
		"⑤ 水晶渲染器同步 tier=4")
	_c.check(not _obelisk.spent_this_wave, "⑤ 波次晋阶同时完成上回合灰相复燃")

func _quit() -> void:
	if _c.report("OBELISK_EVOLUTION_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)
