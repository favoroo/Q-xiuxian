extends Node

## 提前清场判据：一波的收尾有两条出口（2026-10-12 用户口径「提前杀完还在干等，剩余时间越多
## 应该多奖励一点金币」）—— 表走完，或「妖潮已尽」（本波刷怪预算全部刷入 + 场上再无活妖）。
## 运行: $G --headless --path . res://tests/EarlyClearCheck.tscn
##
## 为什么这几枪必须打在真 spawner 上（走真 Main + 真 WaveSpawner，不手搭假状态）：
##  ① 提前收尾那条判定读的是 `_budget_used / _budget_total / GameManager.enemy_count /
##     elite_spawned` 四个现场量，任何一处接线断了都是「玩家继续干等」或「怪没刷完就把波掐了」。
##     这一枪还量**熬了多少游戏秒才收**（headless 帧率不是 60，所以按表走过的量算，不数帧）：
##     确认窗（WaveSpawner.EARLY_CLEAR_CONFIRM）写成 5 秒与写成 0.4 秒，在「波到底提前没提前」
##     这一句上差的是玩家实打实多熬的四秒半。
##  ② 三条例子（预算没刷完 / 场上还有活妖 / 精英魔君还没到场）正是**朴素写法「场上没怪就收」**
##     会当场放行、而正确写法必须拦住的三个现场 ⇒ 判据的牙齿就在这三条反例上，
##     不再另开 --selftest 抄一遍。
##  ③ 发钱走 GameManager.apply_harvest 那一次到账：金币要进袖、修为一格不许多（余时赏只给
##     金币，见 BalanceEconomy 头注），且播报里那个数必须与纯函数同源。
##  ④ 横幅只有一个 Label、同帧两条会吞掉前一条 ⇒ 「收益到账 + 余时赏」必须是一句话，
##     并且这句话不许长到撑出画布（Android 上看不见的字等于没做）。
##
## 灵石/经验两笔账用「同一波、只差余秒」的差分来量：harvest 先钉成同一个数、经验门槛抬到不会
## 连升，剩下的差额就只有余时赏一项 —— 不去猜这一波里还有几颗宝石会被吸进袖中。
## 清场用 remove_child（同帧就走 _exit_tree 注销），不用 dissolve()：消散动画 0.4s 与确认窗
## 0.4s 串起来会让「第几帧收尾」这一枪量到的是两段动画之和。

const HUD_PATH := "/root/Main/UILayer/GameHUD"
## 差分测发钱时用的余秒（13 秒 = 用户截图里那一格「第 7 波 · 0:13」）
const PROBE_SECS := 13.0
## 灵韵钉成这个数：② 要同一句里既有「金币与经验」又有余时赏（收益为 0 的角色上那句不出现），
## ⑥ 的两波也要同一个基数才比得出差额
const HARVEST_PIN := 20.0
## 反例要撑过的游戏秒：够确认窗（0.4s）落定两三回，波却一处都不该收
const HOLD_SECS := 1.0
## 一帧一帧等收尾的上限（按表走过的秒数算，与 headless 实际帧率无关）
const WAIT_SECS := 3.0

var _c := TestCheck.new()
var _spawner: WaveSpawner = null
var _hud: GameHUD = null
var _lines: Array[String] = []

func _ready() -> void:
	call_deferred("_dispatch")

func _dispatch() -> void:
	await _setup_run()
	await _run()
	get_tree().quit(0 if _c.report("EARLY_CLEAR_RESULT") else 1)

## 真现场：开局 → 等第一波进 FIGHT → 挂上播报收集器
func _setup_run() -> void:
	Engine.time_scale = 1.0
	get_tree().root.size = Vector2i(960, 540)
	var main: Node = load("res://scenes/main/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	GameManager.cultivator_id = "fuzhen"
	GameManager.start_run("qingyun_sword")
	get_tree().paused = false
	await get_tree().process_frame
	GameManager.announcement_triggered.connect(
		func(text: String) -> void: _lines.append(text))
	_spawner = GameManager.wave_spawner as WaveSpawner
	_hud = get_node_or_null(HUD_PATH) as GameHUD
	var waited := 0
	while _spawner != null and int(_spawner.phase) != int(WaveSpawner.Phase.FIGHT) and waited < 240:
		await get_tree().process_frame
		waited += 1
	_c.check(_spawner != null and int(_spawner.phase) == int(WaveSpawner.Phase.FIGHT),
		"真 spawner 已进入 FIGHT（等了 %d 帧）" % waited)
	_c.check(_hud != null, "真 HUD 已就位（量横幅要用）")

func _run() -> void:
	if _spawner == null:
		_c.check(false, "前置缺失：spawner 没到位，后续项无法比")
		return

	# ---- ① 妖潮已尽 ⇒ 提前收尾：熬了多久收的、表还剩多少 ----
	_begin_wave(7)
	_spawner._budget_used = _spawner._budget_total   # 视作本波该刷进来的已经全刷进场地
	_clear_field()
	var elapsed := await _wait_left_fight()
	var left := float(_spawner.wave_timer)
	var total := GameBalance.wave_duration(7)
	_c.check(elapsed >= 0.0, "① 预算刷尽 + 场上清空 ⇒ 已离开 FIGHT（phase=%d）" % int(_spawner.phase))
	_c.check(absf(elapsed - WaveSpawner.EARLY_CLEAR_CONFIRM) <= 0.15,
		"① 确认窗就是常量那一格：熬了 %.2fs 收尾（常量 %.2fs）" % [
			elapsed, WaveSpawner.EARLY_CLEAR_CONFIRM])
	_c.check(left > total * 0.5,
		"① 收尾发生在表走完之前：还剩 %.1fs / 共 %.1fs" % [left, total])

	# ---- ② 那句话与那个数同源：播报里的金币数 == 纯函数按收尾余秒算出来的值 ----
	var payout_line := _last_line_containing("收益到账")
	_c.check(not payout_line.is_empty(), "② 波末到账播报已发出")
	var want_bonus := GameBalance.early_clear_stones(left)
	_c.check(payout_line.find("提前 %d 秒清场 +%d 金币" % [int(floor(left)), want_bonus]) >= 0,
		"② 播报里的余秒与金币数取自收尾那一拍（实得「%s」/ 期望 +%d）" % [payout_line, want_bonus])
	_c.check(payout_line.find("金币与经验") >= 0,
		"② 灵韵那句没被余时赏顶掉（两句并成了一句）：「%s」" % payout_line)
	_c.check(want_bonus > 0, "② 这一枪量得到东西：余 %.1fs 确实给钱（%d 枚）" % [left, want_bonus])

	# ---- ③ 反例：预算还没刷完，场上空着也不许收（提前收 = 把击杀进项一起收走）----
	_begin_wave(7)
	_spawner._budget_used = _spawner._budget_total - 1
	_clear_field()
	await _hold_secs()
	_c.check(int(_spawner.phase) == int(WaveSpawner.Phase.FIGHT),
		"③ 预算差 1 只没刷完 + 场上空 ⇒ 仍在 FIGHT（朴素写法会收）")

	# ---- ④ 反例：预算刷尽了，但场上还有活妖 ----
	_begin_wave(7)
	_spawner._budget_used = _spawner._budget_total
	_clear_field()
	var keeper := _spawn_one_enemy()
	await _hold_secs()
	_c.check(keeper != null and is_instance_valid(keeper) and GameManager.enemy_count > 0,
		"④ 前置：确实有一只活妖在场（登记数 %d）" % GameManager.enemy_count)
	_c.check(int(_spawner.phase) == int(WaveSpawner.Phase.FIGHT),
		"④ 妖潮刷尽但还剩 1 只活妖 ⇒ 仍在 FIGHT（phase=%d）" % int(_spawner.phase))

	# ---- ⑤ 反例：精英波/魔君波，关底威胁还没到场 ----
	for n in [5, 10]:
		_begin_wave(n)
		_spawner._budget_used = _spawner._budget_total
		_clear_field()
		await _hold_secs()
		_c.check(not _spawner.elite_spawned and int(_spawner.phase) == int(WaveSpawner.Phase.FIGHT),
			"⑤ 第 %d 波关底未到场 ⇒ 不许提前收（elite=%s phase=%d）" % [
				n, str(_spawner.elite_spawned), int(_spawner.phase)])

	# ---- ⑥ 发钱：只给金币、给的就是纯函数那个数 ----
	var a := _payout_probe(0.0)
	var b := _payout_probe(PROBE_SECS)
	_c.equals(a["stones"], GameBalance.harvest_gain(HARVEST_PIN),
		"⑥ 表走完（余 0 秒）只结灵韵 %d，没有余时赏" % GameBalance.harvest_gain(HARVEST_PIN))
	_c.equals(b["stones"] - a["stones"], GameBalance.early_clear_stones(PROBE_SECS),
		"⑥ 余 %d 秒的差额 == early_clear_stones = %d 枚金币（A %d / B %d）" % [
			int(PROBE_SECS), GameBalance.early_clear_stones(PROBE_SECS), a["stones"], b["stones"]])
	_c.equals(b["exp"], a["exp"],
		"⑥ 余时赏不掺进修为：两波经验进账相同（%d）" % a["exp"])

	# ---- ⑦ 横幅装得下：最长那句真实读数不许探出画布 ----
	if _hud != null:
		var longest := "◆ 收益到账 · 金币与经验 +%d · 提前 %d 秒清场 +%d 金币 ◆" % [
			GameBalance.harvest_gain(GameManager.harvest) + 999,
			GameBalance.EARLY_CLEAR_STONES_MAX, GameBalance.EARLY_CLEAR_STONES_MAX]
		_hud.show_announcement(longest)
		await get_tree().process_frame
		await get_tree().process_frame
		var vp_w := _hud.get_viewport_rect().size.x
		var rect: Rect2 = _hud.banner.get_global_rect()
		_c.check(rect.size.x > 0.0 and rect.position.x >= -0.5 and rect.end.x <= vp_w + 0.5,
			"⑦ 最长到账句仍在画布内（横幅 %.0f..%.0f / 画布宽 %.0f）" % [
				rect.position.x, rect.end.x, vp_w])
	else:
		_c.check(false, "⑦ 前置缺失：HUD 没到位，横幅宽度无从量起")

# ---------------- 小工具 ----------------

## 开一波：判据要的是「这一波刚开始、什么都还没发生」那个现场。
## 顺带把灵韵与升级门槛钉住：波末那笔收益要能被这一句量到，又不能把等级顶上去。
func _begin_wave(n: int) -> void:
	GameManager.is_game_over = false
	get_tree().paused = false
	GameManager.harvest = HARVEST_PIN
	GameManager.experience = 0
	GameManager.experience_to_next = 100000
	_spawner.phase = WaveSpawner.Phase.FIGHT
	_spawner.start_wave(n)
	_clear_field()

## 场上清空：余妖同帧摘树（走 _exit_tree 注销，enemy_count 立刻归零），宝石一并请走
func _clear_field() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is Node and node.get_parent() != null:
			node.get_parent().remove_child(node)
			node.queue_free()
	for node in get_tree().get_nodes_in_group("gems"):
		if node is Node and node.get_parent() != null:
			node.get_parent().remove_child(node)
			node.queue_free()
	GameManager.enemy_count = 0

## 造一只活妖：走生产口（instantiate + add_to_group + 入树才会在登记表里）
func _spawn_one_enemy() -> EnemyBase:
	var e: EnemyBase = load("res://scenes/entities/SlimeEnemy.tscn").instantiate() as EnemyBase
	if e == null:
		return null
	e.global_position = Vector2(240.0, 0.0)
	e.add_to_group("enemies")
	_spawner.get_parent().add_child(e)
	return e

## 差分测一次波末到账：harvest 与经验门槛已由 _begin_wave 钉住，两波只差 early_secs 一项
func _payout_probe(early_secs: float) -> Dictionary:
	_begin_wave(7)
	_spawner._budget_used = _spawner._budget_total
	_clear_field()
	var stones_before := GameManager.spirit_stones
	var exp_before := GameManager.experience
	_spawner.end_wave(early_secs)
	var out := {
		"stones": GameManager.spirit_stones - stones_before,
		"exp": GameManager.experience - exp_before,
	}
	# 别让 CLEARING 走到商店/悟道面板：下一枪还要在同一现场打
	_spawner.phase = WaveSpawner.Phase.FIGHT
	get_tree().paused = false
	return out

## 撑过 HOLD_SECS 游戏秒（按表走过的量算，不看帧数：headless 的帧率不是 60）
func _hold_secs() -> void:
	var t0 := float(_spawner.wave_timer)
	var frames := 0
	while float(_spawner.wave_timer) > t0 - HOLD_SECS and frames < 3000:
		await get_tree().process_frame
		frames += 1

## 一帧一帧等 phase 离开 FIGHT，返回收尾熬了多少游戏秒（表在 FIGHT 之外不走，所以
## t0 - wave_timer 就是走过的时间）；-1.0 = 等满上限还没收
func _wait_left_fight() -> float:
	var t0 := float(_spawner.wave_timer)
	var frames := 0
	while int(_spawner.phase) == int(WaveSpawner.Phase.FIGHT) and frames < 3000:
		await get_tree().process_frame
		frames += 1
		if t0 - float(_spawner.wave_timer) > WAIT_SECS:
			return -1.0
	return t0 - float(_spawner.wave_timer)

func _last_line_containing(key: String) -> String:
	for i in range(_lines.size() - 1, -1, -1):
		if _lines[i].find(key) >= 0:
			return _lines[i]
	return ""
