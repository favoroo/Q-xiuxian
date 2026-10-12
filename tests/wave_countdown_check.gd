extends Node

## 顶栏波次倒计时判据：「第 N 波 · M:SS」那串字与芯片底部那根线，必须跟着真正决定
## 这一波结束的那两个数走 —— spawner.wave_timer 与 GameBalance.wave_duration(n)。
## 运行: $G --headless --path . res://tests/WaveCountdownCheck.tscn
##       $G --headless --path . res://tests/WaveCountdownCheck.tscn -- --selftest
##
## 立条目的现场（2026-10-11 用户提问「每波回合有对应的倒计时提示吗」）：非 Boss 波的
## 结束条件**只有一个** —— WaveSpawner._process_fight 里 wave_timer 走到 0，场上怪清没清
## 都不算 ⇒ 这根表就是关卡长度，而顶栏原来只有整局正计时，玩家零刻度。补读数容易，
## 难的是别让它长成第二套时间，所以这里钉四件事：
##   ① 秒数 = ceili(spawner.wave_timer)：判据从读数文本里把秒数抠出来，再与 spawner
##      那一格比 —— 控件若自己起一张表，抠出来的数就对不上。
##   ② 线长 = wave_timer / wave_duration(n)：分母随波次变（第 1 波 26s、第 12 波 44s），
##      写死 60 的写法会把第 12 波剩 22s 画成 0.37 长，而它该是一半 —— selftest 拦住它。
##   ③ Boss 波（第 10 波）整条不出现（用户当轮指令「boss 战就不用倒计时了」）：那一段
##      表走到 0 也不开下一波（魔君未死停表锁关），画一个会卡在 0:00 的读数只会让人以为坏了。
##   ④ 波次一结束（phase 离开 FIGHT）线就收：不许留一根停在 0:00 的假进度。
##
## 两处取舍：
##  · 走真 Main（start_run + 真 WaveSpawner + 真 GameHUD），不手工搭一个假 spawner 状态：
##    这条判据要防的是「接线断了」，只有生产入口才量得到。
##  · 顶栏会不会被这串字推出屏，归 LayoutCheck 量（它灌 HudWaveCountdown.worst_case_text()
##    这个最长真实样本）；这里只钉「那个样本确实是最长的真实读数」，不重复量几何。

const HUD_PATH := "/root/Main/UILayer/GameHUD"
## 线长容差：一帧（time_scale 1）走 1/60 秒，占最短一波 22s 的 0.08%，取两帧宽再放宽一档
const EPS := 0.02
## 等 spawner 进 FIGHT 的帧数上限（超了就是现场没搭起来，直接报红而不是默默少跑几项）
const WAIT_FRAMES := 240

var _c := TestCheck.new()
var _spawner: Node = null
var _wc: HudWaveCountdown = null

func _ready() -> void:
	call_deferred("_dispatch")

func _dispatch() -> void:
	var selftest := "--selftest" in OS.get_cmdline_user_args()
	await _setup_run()
	if selftest:
		await _selftest()
	else:
		await _run()
	get_tree().quit(0 if _c.report("WAVE_COUNTDOWN_SELFTEST_RESULT" if selftest else "WAVE_COUNTDOWN_RESULT") else 1)

## 真现场：开局 → 等第一波进入 FIGHT → 取真 HUD 里那颗倒计时控件
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
	_spawner = GameManager.wave_spawner
	var hud := get_node_or_null(HUD_PATH) as GameHUD
	_wc = hud.wave_countdown if hud != null else null
	var waited := 0
	while _spawner != null and int(_spawner.phase) != int(WaveSpawner.Phase.FIGHT) and waited < WAIT_FRAMES:
		await get_tree().process_frame
		waited += 1
	_c.check(_spawner != null and int(_spawner.phase) == int(WaveSpawner.Phase.FIGHT),
		"真 spawner 已进入 FIGHT（第 %d 波，等了 %d 帧）" % [GameManager.wave_number, waited])
	# 尺子活着：控件没建起来时后面每一项都无从比起，先在这里明说而不是跑成空转
	_c.check(_wc != null, "顶栏波次倒计时控件已建（WaveChip 里那颗）")

func _run() -> void:
	if _wc == null or _spawner == null:
		_c.check(false, "前置缺失：spawner 或倒计时控件没到位，后续项无法比")
		return

	# ---- ① 第 1 波：秒数与线长都跟着 spawner 那一格 ----
	_spawner.wave_timer = 12.4
	await get_tree().process_frame
	var total_1 := GameBalance.wave_duration(1)
	_c.check(_secs_shown() == float(int(ceili(_spawner.wave_timer))),
		"第 1 波 · 读数秒数 == ceili(spawner.wave_timer)（实得 %s / 表 %.2f）" % [_readout(), _spawner.wave_timer])
	_c.check(_near(_wc.bar_ratio(), float(_spawner.wave_timer) / total_1),
		"第 1 波 · 线长 == 剩余/本波总长 %.1fs（实得 %.3f）" % [total_1, _wc.bar_ratio()])
	_c.check(_wc.has_bar(), "第 1 波 · 芯片底部有线")

	# ---- ② 与整局时长无关：灌一个离谱的 game_time 当干扰 ----
	GameManager.game_time = 1234.0
	_spawner.wave_timer = 12.4
	await get_tree().process_frame
	_c.check(_secs_shown() != 34.0 and _secs_shown() != 1234.0,
		"读数不跟整局 game_time（灌了 1234s 干扰，实读 %s）" % _readout())

	# ---- ③ 分母随波次变：第 12 波总长 44s，剩 22s 必须正好一半 ----
	_spawner.start_wave(12)
	await get_tree().process_frame
	_spawner.wave_timer = 22.0
	await get_tree().process_frame
	var total_12 := GameBalance.wave_duration(12)
	_c.check(not _near(total_12, total_1), "第 12 波总长已随波次变长（%.1fs vs %.1fs）" % [total_12, total_1])
	_c.check(_near(_wc.bar_ratio(), 22.0 / total_12),
		"第 12 波 · 剩 22s 线长 == 22/%.0f = 0.500（实得 %.3f）" % [total_12, _wc.bar_ratio()])
	_c.check(_secs_shown() == 22.0, "第 12 波 · 读数 0:22（实得 %s）" % _readout())

	# ---- ④ 告急：最后 5 秒转朱砂，6 秒还不该转 ----
	_spawner.wave_timer = 4.2
	await get_tree().process_frame
	_c.check(_wc.is_urgent() and _wc.shown_color() == GameStyle.BAD,
		"剩 4.2s 整颗芯片转朱砂（实得 %s）" % _readout())
	_spawner.wave_timer = 6.0
	await get_tree().process_frame
	_c.check(not _wc.is_urgent() and _wc.shown_color() == GameStyle.GOLD,
		"剩 6.0s 还是主蓝（实得 %s）" % _readout())

	# ---- ⑤ 线画多长就是多长：不探出芯片、也不许只按布局框算 ----
	_spawner.wave_timer = 22.0
	await get_tree().process_frame
	_c.check(_wc.size.x > 0.0, "芯片内宽已量到（%.1f）" % _wc.size.x)
	_c.check(_near(_wc.fill_width(), _wc.size.x * _wc.bar_ratio(), 0.02),
		"线长 == 比例 × 芯片内宽（内宽 %.1f，画到 %.1f）" % [_wc.size.x, _wc.fill_width()])
	_c.check(_wc.fill_width() <= _wc.size.x + 0.02, "线不探出芯片")

	# ---- ⑥ 波次一结束线就收（表停在 0:00 的假进度不许留） ----
	_spawner.wave_timer = 0.01
	await get_tree().process_frame
	await get_tree().process_frame
	_c.check(int(_spawner.phase) != int(WaveSpawner.Phase.FIGHT), "表走到 0 已由生产路径收尾（phase=%d）" % int(_spawner.phase))
	_c.check(not _wc.has_bar() and _wc.fill_width() == 0.0,
		"波次结束后线已收（读数 %s）" % _readout())
	_c.check(_readout() == "第 12 波", "波次结束只剩纯波号（实得 %s）" % _readout())

	# ---- ⑦ Boss 波（第 10 波）：不给倒计时、不画线（用户当轮指令） ----
	_spawner.start_wave(10)
	await get_tree().process_frame
	_c.check(_readout() == "第 10 波", "Boss 波读数不带时间（实得 %s）" % _readout())
	_c.check(not _wc.has_bar(), "Boss 波芯片底部不画线")
	_c.check(_wc.fill_width() == 0.0, "Boss 波没画任何进度")

	# ---- ⑧ 最长真实读数 == LayoutCheck 灌的那串样本 ----
	# 样本串里的秒数跟着波长封顶走（2026-10-11 WAVE_DURATION_MAX 60→70 ⇒ 尾巴是 1:10 不是 1:00）
	_c.check(HudWaveCountdown.worst_case_text() == "第 99 波 · 1:10",
		"最坏样本 = 最长真实读数（实得 %s；波长封顶 %.0fs）" % [
			HudWaveCountdown.worst_case_text(), GameBalance.wave_duration(99)])

	# ---- ⑨ 那串样本真能把芯片撑宽：否则 LayoutCheck 的溢出判据是在量一条短读数放行 ----
	var chip: Control = _wc.get_parent()
	var w_short := chip.size.x
	_wc.show_as_worst_case()
	await get_tree().process_frame
	await get_tree().process_frame
	var w_worst := chip.size.x
	_c.check(w_worst > w_short,
		"最坏样本确实比当前读数宽（芯片内宽 %.1f → %.1f），量的是长的那串" % [w_short, w_worst])
	var vp_w := _wc.get_viewport_rect().size.x
	_c.check(chip.get_global_rect().end.x <= vp_w + 0.5,
		"灌满最坏样本后芯片仍在画布内（右沿 %.1f / 画布宽 %.0f）" % [chip.get_global_rect().end.x, vp_w])

## 反例库：把三种坏写法各自的数拿出来，与真控件此刻的读数比 —— 拦住才算有牙齿。
## 正例则要求真控件放行，证明这些牙齿不是空咬。
func _selftest() -> void:
	if _wc == null or _spawner == null:
		_c.check(false, "selftest 前置：现场没搭起来")
		return
	_spawner.wave_timer = 12.4
	await get_tree().process_frame
	var total_1 := GameBalance.wave_duration(1)

	_c.check(_secs_shown() == float(int(ceili(_spawner.wave_timer))),
		"正例 真实现放行：读数 0:13（实得 %s）" % _readout())
	_c.check(_near(_wc.bar_ratio(), 12.4 / total_1),
		"正例 真实现放行：线长 == 12.4/%.0f（实得 %.3f）" % [total_1, _wc.bar_ratio()])

	# 反例① 分母写死 60s（第 1 波总长 26s，会把半程画成 0.207）
	_c.check(not _near(_wc.bar_ratio(), 12.4 / 60.0),
		"反例① 分母写死 60s 被拦住（那样算得 %.3f，实得 %.3f）" % [12.4 / 60.0, _wc.bar_ratio()])
	# 反例② 读数拿整局时长凑（game_time 1234s 的尾巴是 34s）
	GameManager.game_time = 1234.0
	await get_tree().process_frame
	_c.check(not _near(_secs_shown(), 34.0),
		"反例② 读数改用整局 game_time 被拦住（那样会是 0:34，实得 %s）" % _readout())
	GameManager.game_time = 0.0
	# 反例③ 自己另起一张表：把 spawner 那格改掉后读数必须跟着改
	_spawner.wave_timer = 7.3
	await get_tree().process_frame
	_c.check(_secs_shown() == 8.0,
		"反例③ 控件自己攒表（读数不动）被拦住（改表后实得 %s）" % _readout())
	# 反例④ Boss 波也画线 / 也报秒
	_spawner.start_wave(10)
	await get_tree().process_frame
	_c.check(not _wc.has_bar() and _readout().find(":") < 0,
		"反例④ Boss 波仍画线报秒被拦住（实得 %s）" % _readout())
	# 反例⑤ 波次结束后线还停在 0:00
	_spawner.start_wave(3)
	await get_tree().process_frame
	_spawner.wave_timer = 0.01
	await get_tree().process_frame
	await get_tree().process_frame
	_c.check(int(_spawner.phase) != int(WaveSpawner.Phase.FIGHT) and not _wc.has_bar(),
		"反例⑤ 波末留一条停着的假线被拦住（phase=%d，线 %s）" % [int(_spawner.phase), str(_wc.has_bar())])
	# 反例⑥ 数字与线各说各话（数字说剩 8 秒、线还剩一半）
	_spawner.start_wave(3)
	await get_tree().process_frame
	_spawner.wave_timer = 4.2
	await get_tree().process_frame
	# 线是连续的、数字进位到整秒（ceili），所以同源的定义是「线反推回剩余秒数」与读数
	# 相差不足 1 秒 —— 差一整秒以上就说明两处不是同一个数。
	var left_from_bar := _wc.bar_ratio() * GameBalance.wave_duration(3)
	_c.check(absf(left_from_bar - _secs_shown()) < 1.0,
		"正例 数字与线同源：线反推 %.2fs vs 读数 %.0fs（差须不足 1 秒）" % [left_from_bar, _secs_shown()])
	_c.check(absf(0.5 * GameBalance.wave_duration(3) - _secs_shown()) >= 1.0,
		"反例⑥ 线按另一套比例画（0.5 ⇒ %.1fs）与读数 %.0fs 对不上，被拦住" % [
			0.5 * GameBalance.wave_duration(3), _secs_shown()])

# ---------------- 取值小工具 ----------------

func _readout() -> String:
	return _wc.readout_text()

## 从读数文本里把「还剩几秒」抠出来（"第 N 波 · M:SS" → 秒；不带倒计时时回 -1）。
## 判据只认这一条解析路：它是从**画出来的那串字**倒推的，控件换成另一张表就会露馅。
func _secs_shown() -> float:
	var text := _wc.readout_text()
	var idx := text.find(HudWaveCountdown.SEP)
	if idx < 0:
		return -1.0
	var parts := text.substr(idx + HudWaveCountdown.SEP.length()).split(":")
	if parts.size() != 2:
		return -1.0
	return float(int(parts[0]) * 60 + int(parts[1]))

func _near(a: float, b: float, eps: float = EPS) -> bool:
	return absf(a - b) <= eps
