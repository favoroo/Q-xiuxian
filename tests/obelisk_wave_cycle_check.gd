extends Node

## 聚灵阵「回合循环」判据（2026-10-25 祭坛重设计：单祭坛 · 每回合金币启动 · 灵兽顶替/寿命/配色，
## 真实 Main 场景，不打 mock）。
## 运行: $G --headless --path . res://tests/ObeliskWaveCycleCheck.tscn
##
## 钉的机制：
##   ① 单祭坛：Main 场景里 BlessingObelisk 只有一座（MapLayer/ObeliskCenter）
##   ② 金币闸：钱不够 start_charge 硬拦（不进充能、发「金币不够启动祭坛」横幅）；够了才进
##   ③ 扣费记账：注入爆发后 spirit_stones 扣启动价、total_stones_spent 记账、祭坛进灰相
##   ④ 回合恢复：广播 wave_changed → 灰相复燃（spent_this_wave 清零、灯复燃）
##   ⑤ 价格随波上涨：第 n 回合启动价 = 45 + (n-1)*3，碑顶价格标签跟着换文案
##   ⑥ 满员顶替：场上 3 只灵兽再启动 → summon_wave 最早的那只消散，新灵兽补位（总数仍 3）
##   ⑦ 配色唯一：同场灵兽 palette_idx 互不重复（新灵兽取「最小未占用档」，顶替档当场让位）
##   ⑧ 寿命到期：wave 走到 summon_wave + LIFETIME_WAVES 时灵兽消散并注销

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

## 场地静音：刷怪器不再出人、场上妖物散掉，读数只由本判据自己写。
## 相位钉在 FIGHT：祭坛 _process 有「非战斗阶段不充能」守门，不钉相位充能会被当场掐掉。
func _quiet_arena() -> void:
	var spawner: Node = GameManager.wave_spawner
	if spawner != null:
		spawner.set_process(false)
		spawner.set_physics_process(false)
		spawner.phase = WaveSpawner.Phase.FIGHT
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is EnemyBase:
			enemy.dissolve()

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

	_case_single_altar()
	await _case_gold_gate()
	await _case_pay_and_wave_cycle()
	await _case_replacement_and_palette()
	await _case_lifetime()
	await _case_restore_price()

	Engine.time_scale = 1.0
	_quit()

## ① 单祭坛：场上只有一座界碑
func _case_single_altar() -> void:
	var map_layer := get_node_or_null("/root/Main/MapLayer")
	_c.check(map_layer != null, "① 前置：Main 的 MapLayer 可寻址")
	if map_layer == null:
		return
	var count := 0
	for child in map_layer.get_children():
		if child is BlessingObelisk:
			count += 1
	_c.equals(count, 1, "① Main 场景里只有一座聚灵阵（重设计：单祭坛）")
	_c.check(_obelisk != null, "① 前置：ObeliskCenter 可寻址")

## ② 金币闸：钱不够不进充能并给横幅；钱够才放行
func _case_gold_gate() -> void:
	_c.check(_obelisk != null, "② 前置：祭坛在")
	if _obelisk == null:
		return
	_obelisk.is_player_inside = true
	GameManager.spirit_stones = 0
	_banner_seen = ""
	_obelisk.start_charge()
	_c.check(not _obelisk.is_charging, "② 身无分文 ⇒ start_charge 硬拦，不进充能")
	_c.check(_banner_seen.contains("金币不够"), "② 硬拦时发了「金币不够」横幅（实得：%s）" % _banner_seen)
	# 给足启动价 → 放行进入充能
	GameManager.spirit_stones = GameBalance.obelisk_activation_cost(maxi(GameManager.wave_number, 1))
	_obelisk.start_charge()
	_c.check(_obelisk.is_charging, "② 钱够 ⇒ 正常进入充能")
	_obelisk.stop_charge()
	_c.check(not _obelisk.is_charging, "② 收尾：松手中断，不留充能态")

## ③ 扣费记账 + ④ 回合恢复 + ⑤ 价格随波上涨
func _case_pay_and_wave_cycle() -> void:
	var cost := GameBalance.obelisk_activation_cost(maxi(GameManager.wave_number, 1))
	GameManager.spirit_stones = cost
	var spent_before: int = GameManager.total_stones_spent
	_obelisk.start_charge()
	# 等充能 0.8s + 注入 0.45s 全程走完 → _release_blessing（100 帧游戏秒 ≈ 1.67s）
	await _settle(100)
	_c.check(_obelisk.spent_this_wave, "③ 触发后祭坛进本回合灰相")
	_c.equals(GameManager.spirit_stones, 0, "③ 扣费：金币扣走启动价 %d" % cost)
	_c.equals(GameManager.total_stones_spent, spent_before + cost, "③ 记账：total_stones_spent 同步累加")
	_c.check(GameManager.live_allies.size() == 1, "③ 爆发后场上 1 只灵兽")

	# ④ 广播 wave_changed（下一回合）：灰相复燃
	var next_wave: int = maxi(GameManager.wave_number, 1) + 1
	GameManager.wave_number = next_wave
	GameManager.wave_changed.emit(next_wave)
	await _settle(4)
	_c.check(not _obelisk.spent_this_wave, "④ 新回合 wave_changed ⇒ 灰相复燃（可再启动）")
	_c.check(_obelisk.light.enabled, "④ 复燃：灯光重新点亮")

	# ⑤ 价格随波上涨：价格收在 HUD 激活键的键面小字上（2026-10-26 起碑顶不再悬浮常驻文字）
	var cost2 := GameBalance.obelisk_activation_cost(next_wave)
	_c.check(cost2 > cost, "⑤ 启动价随波上涨（%d → %d）" % [cost, cost2])
	var hud := get_node_or_null("/root/Main/UILayer/GameHUD")
	# 注意取 _obelisk_widget（真正的 HudObeliskButton）；_obelisk_btn 是它内部的 Button
	var ob_btn: HudObeliskButton = hud._obelisk_widget if hud != null else null
	_c.check(ob_btn != null and ob_btn.get_price_label() != null, "⑤ 前置：HUD 祭坛激活键与其价格小字在")
	if ob_btn != null:
		ob_btn.show_obelisk_activation(_obelisk)
		await _settle(2)
		var price_lbl: Label = ob_btn.get_price_label()
		_c.check(price_lbl.text.contains(str(cost2)),
			"⑤ 键面价格写着新价（实得：%s）" % price_lbl.text)
		# 金币不足时价格转差额（朱砂）
		GameManager.spirit_stones = 0
		await _settle(2)
		_c.check(price_lbl.text.contains("差"), "⑤ 身无分文 ⇒ 键面标出「差」多少（实得：%s）" % price_lbl.text)
		GameManager.spirit_stones = cost2   # 留够下一Case的启动费
		await _settle(2)

## ⑥ 满员顶替 + ⑦ 配色唯一：补两只占满 3 席，再启动 → 最老的消散、新兽补位、配色互不重复
func _case_replacement_and_palette() -> void:
	# 场上已有 ③ 召的第一只（配色 0 档）；再补两只占住 1/2 档
	var beast_scene: PackedScene = load("res://scenes/entities/SpiritBeast.tscn")
	var beast2 := beast_scene.instantiate() as SpiritBeast
	beast2.palette_idx = 1
	_player.get_parent().add_child(beast2)
	beast2.global_position = _player.global_position + Vector2(40.0, 0.0)
	var beast3 := beast_scene.instantiate() as SpiritBeast
	beast3.palette_idx = 2
	_player.get_parent().add_child(beast3)
	beast3.global_position = _player.global_position + Vector2(-40.0, 0.0)
	await _settle(4)
	_c.equals(GameManager.live_allies.size(), 3, "⑥ 前置：场上 3 只灵兽（席满）")

	# 把第一只标记为「最老」（召唤波更早），顶替逻辑按 summon_wave 找它
	var oldest := GameManager.live_allies[0] as SpiritBeast
	oldest.summon_wave = maxi(GameManager.wave_number - 1, 0)

	# 第 4 次启动：满员顶替
	_obelisk.start_charge()
	await _settle(100)
	_c.check(_obelisk.spent_this_wave, "⑥ 第 4 次启动照常执行（祭坛每回合都能用）")
	await _settle(60)   # 等被顶替者的消散 tween 走完
	_c.check(not is_instance_valid(oldest), "⑥ 最老的一只已被顶替消散")
	_c.equals(GameManager.live_allies.size(), 3, "⑥ 顶替后总数仍为 3（一进一出，不是 4 只）")

	# ⑦ 配色唯一：同场灵兽 palette_idx 互不重复
	var palettes: Array[int] = []
	for ally in GameManager.live_allies:
		if ally is SpiritBeast and is_instance_valid(ally):
			palettes.append((ally as SpiritBeast).palette_idx)
	var uniq := {}
	for p in palettes:
		uniq[p] = true
	_c.check(palettes.size() == 3 and uniq.size() == 3,
		"⑦ 同场三只配色档互不重复（实得：%s）" % str(palettes))

## ⑧ 寿命到期：wave 走到 summon_wave + LIFETIME_WAVES 时消散注销（直接调灵兽寿命闸，不广播假波次）
func _case_lifetime() -> void:
	var beast := GameManager.live_allies[0] as SpiritBeast
	_c.check(beast != null, "⑧ 前置：场上还有灵兽")
	if beast == null:
		return
	beast._on_wave_changed(beast.summon_wave + GameBalance.SPIRIT_BEAST_LIFETIME_WAVES)
	await _settle(60)
	_c.check(not is_instance_valid(beast), "⑧ 满 3 回合 ⇒ 灵兽消散")
	_c.check(not GameManager.live_allies.has(beast), "⑧ 消散后已从 allies 注销")

## 收尾对照：灰相后激活键自动隐藏 —— 价格信息跟着键走，碑上不再有任何字
func _case_restore_price() -> void:
	await _settle(30)   # 等 0.2s 淡出补间在 time_scale 下走完
	var hud := get_node_or_null("/root/Main/UILayer/GameHUD")
	# 注意取 _obelisk_widget（真正的 HudObeliskButton）；_obelisk_btn 是它内部的 Button
	var ob_btn: HudObeliskButton = hud._obelisk_widget if hud != null else null
	_c.check(ob_btn != null and not ob_btn.visible,
		"收尾：灰相后激活键自动隐藏，键面价格随之撤下（碑体不再有任何悬浮文字）")

func _quit() -> void:
	if _c.report("OBELISK_WAVE_CYCLE_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)
