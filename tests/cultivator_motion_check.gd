extends Node

## 程序化修士「动作流畅度 + 自然眨眼」判据（2026-10-23，2026-10-24 重钉浮沉判据）
##
## 背景：玩家档角色内部绘制从 30Hz 提到 60Hz；眨眼从固定 4.17s 单眨改为
## 随机 2~6s + 30% 连眨 + 15% 半眨的连续眼睑状态机。本判据钉住这几条不变量：
##   1. 奔跑浮沉与步态解耦（2026-10-24）：吃独立 _float_phase 而非 gait_phase，
##      合成峰值 ≤1.4px，双频叠加不成节拍器；改前是 sin(gait_phase*TAU)*2.4
##      与 Player 的 squash 同相叠峰，观感「一蹦一跳」
##   2. 玩家档重绘间隔 = 60Hz（REDRAW_INTERVAL_HIGHFPS ≈ 0.0167）
##   3. 眨眼调度：60 秒内 10~30 次、至少一次连眨、全程无单帧跳变 > 0.5
##
## 运行：python3 tools/run_test.py CultivatorMotionCheck
##   或 godot --headless --path . res://tests/CultivatorMotionCheck.tscn

var _c := TestCheck.new()

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_redraw_rate()
	_test_run_float_sync()
	_test_blink_schedule()
	_test_blink_smoothness()

	if not _c.all_passed():
		print("CULTIVATOR_MOTION_RESULT: FAILED (%d failures)" % _c.failures.size())
		get_tree().quit(1)
	else:
		print("CULTIVATOR_MOTION_RESULT: ALL PASS (%d checks)" % _c.passed)
		get_tree().quit(0)

func _test_redraw_rate() -> void:
	var interval: float = CultivatorRendererBase.REDRAW_INTERVAL_HIGHFPS
	_c.near(interval, 1.0 / 60.0, 0.0015, "玩家档重绘间隔为 60Hz（%.4fs）" % interval)
	_c.check(interval < CultivatorRendererBase.REDRAW_INTERVAL,
			"玩家档必须快于画廊/头像档（%.4f < %.4f）" % [interval, CultivatorRendererBase.REDRAW_INTERVAL])

func _test_run_float_sync() -> void:
	var r := HollowKnightCultivatorRenderer.new(CultivatorVisualConfig.get_config("jianchi"))
	add_child(r)
	r.current_action = CultivatorRendererBase.Action.RUN
	r._run_blend = 1.0

	# 1. 与步态解耦：改 gait_phase 不许影响浮沉（2026-10-24 重钉）
	#    旧判据钉的是「同相位同值」，那条正是「一蹦一跳」的来源，已废
	r._float_phase = 0.23
	r.gait_phase = 0.0
	var got_a := r._run_float_y()
	r.gait_phase = 0.62
	var got_b := r._run_float_y()
	_c.near(got_a, got_b, 0.0001,
			"奔跑浮沉与步态解耦（gait 0.00/0.62 同值 %.3f）" % got_a)

	# 2. 随时间必须变化（防退化成常量）+ 合成峰值收在 1.4px 内：这是「别蹦」的硬指标
	var amp_sum: float = HollowKnightCultivatorRenderer.GLIDE_MAIN_AMP \
			+ HollowKnightCultivatorRenderer.GLIDE_SUB_AMP
	_c.check(amp_sum <= 1.4,
			"漂移合成峰值 ≤1.4px（%.2f，旧实现 2.4px 且与 squash 叠峰）" % amp_sum)
	var peak := 0.0
	var lo := 0.0
	var hi := 0.0
	for i in range(240):
		r._float_phase = float(i) / 240.0 * TAU
		var y := r._run_float_y()
		peak = maxf(peak, absf(y))
		lo = minf(lo, y)
		hi = maxf(hi, y)
	_c.check(peak <= amp_sum + 0.0001,
			"全相位扫描峰值不超过合成幅度（实得 %.3f ≤ %.3f）" % [peak, amp_sum])
	_c.check(hi - lo > 0.9,
			"全相位扫描确有起伏（峰谷差 %.2f）" % (hi - lo))

	# 3. 双频不同拍：主副频不成整数倍，否则退化成单一节拍器
	var sub: float = HollowKnightCultivatorRenderer.GLIDE_SUB_FREQ
	_c.check(absf(sub - roundf(sub)) > 0.15,
			"副频非整数倍主频（%.2f），不锁相成节拍器" % sub)

	# 4. 待机浮沉与奔跑浮沉是不同公式，混合权重 0/1 必须能取到两端
	r._run_blend = 0.0
	var idle_y := r._body_float_y()
	r._run_blend = 1.0
	var run_y := r._body_float_y()
	_c.check(absf(idle_y - run_y) > 0.001 or absf(idle_y) < 0.001,
			"RUN↔IDLE 混合权重 0/1 取到不同端（idle %.2f / run %.2f）" % [idle_y, run_y])

	# 5. 漂移相位连续：逐帧推进不得有跳变（副频非整数倍，fmod 回绕会每 0.7s 抖 ~0.6px）
	r._float_phase = 0.0
	r._run_blend = 1.0
	r.speed_ratio = 1.0
	var dt := 1.0 / 60.0
	var prev_y := r._run_float_y()
	var max_step := 0.0
	for i in range(600):  # 10 秒，跨过多个潜在回绕点
		r._process(dt)
		var y := r._run_float_y()
		max_step = maxf(max_step, absf(y - prev_y))
		prev_y = y
	# 理论单帧最大 ~0.15px；留 2 倍余量，只抓回绕级跳变（0.6px）
	_c.check(max_step < 0.3,
			"漂移相位逐帧连续无回绕跳变（10s 内最大单帧 %.3fpx）" % max_step)
	r.queue_free()

func _test_blink_schedule() -> void:
	var r := HollowKnightCultivatorRenderer.new(CultivatorVisualConfig.get_config("jianchi"))
	add_child(r)
	r.current_action = CultivatorRendererBase.Action.IDLE
	# 固定 seed 保证可复现（不依赖 instance_id 的运行时值）
	r._blink_rng.seed = 12345
	r._blink_wait = 0.0
	r._blink_t = -1.0
	r._blink_burst_left = 0

	var dt := 1.0 / 60.0
	var elapsed := 0.0
	var blink_count := 0
	var burst_seen := false
	var last_active := false
	var prev_value := 0.0
	var max_jump := 0.0
	var values: Array[float] = []
	while elapsed < 60.0:
		r._tick_blink(dt)
		elapsed += dt
		var active := r._blink_t >= 0.0
		if active and not last_active:
			blink_count += 1
			# 连眨：一次触发后 burst_left > 0 说明后面还有
			if r._blink_burst_left > 0:
				burst_seen = true
		last_active = active
		var v: float = r._blink_value
		values.append(v)
		max_jump = maxf(max_jump, absf(v - prev_value))
		prev_value = v

	_c.check(blink_count >= 10 and blink_count <= 30,
			"60 秒内眨眼次数落在自然区间 10~30（实得 %d）" % blink_count)
	_c.check(burst_seen, "60 秒内至少出现一次连眨（burst_left > 0）")
	_c.check(max_jump <= 0.5,
			"眨眼全程无单帧跳变 > 0.5（最大 %.3f，60fps 下）" % max_jump)
	# 至少要真的闭到接近全闭一次，防「永远半眨」的退化
	var peak := 0.0
	for v in values:
		peak = maxf(peak, v)
	_c.check(peak >= 0.95, "至少一次完整闭眼（峰值 %.2f）" % peak)
	r.queue_free()

func _test_blink_smoothness() -> void:
	var r := HollowKnightCultivatorRenderer.new(CultivatorVisualConfig.get_config("jianchi"))
	add_child(r)
	# 包络本身在 60fps 采样下的最大单帧增量
	var dt := 1.0 / 60.0
	var prev := 0.0
	var max_step := 0.0
	var t := 0.0
	var dur := HollowKnightCultivatorRenderer.BLINK_CLOSE_TIME \
			+ HollowKnightCultivatorRenderer.BLINK_HOLD_TIME \
			+ HollowKnightCultivatorRenderer.BLINK_OPEN_TIME
	while t <= dur:
		var v: float = r._blink_envelope(t)
		max_step = maxf(max_step, absf(v - prev))
		prev = v
		t += dt
	_c.check(max_step < 0.35, "眨眼包络单帧最大增量 < 0.35（实得 %.3f）" % max_step)
	# 紧张动作快速睁眼：0.05s 内从 1 到 0
	r.current_action = CultivatorRendererBase.Action.HIT
	r._blink_value = 1.0
	var steps := 0
	while r._blink_value > 0.0 and steps < 10:
		r._tick_blink(1.0 / 60.0)
		steps += 1
	_c.check(steps <= 4, "HIT 中断眨眼后 0.05s 内睁眼（%d 帧）" % steps)
	r.queue_free()
