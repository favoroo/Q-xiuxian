class_name GameFeel
extends RefCounted

## 打击感（Game-Feel）门面子系统
## 从 GameManager 抽离，负责镜头创伤震屏、缩放冲击、顿帧（Hit-Stop）与受击红晕脉冲。

static func add_trauma(gm: Node, amount: float) -> void:
	if shake_mult_memo() <= 0.0:
		return
	if gm.main_camera != null and is_instance_valid(gm.main_camera) and gm.main_camera.has_method("add_trauma"):
		gm.main_camera.add_trauma(amount)

static func zoom_punch(gm: Node, scale_amount: float = 0.05, duration: float = 0.18) -> void:
	if shake_mult_memo() <= 0.0:
		return
	if gm.main_camera != null and is_instance_valid(gm.main_camera) and gm.main_camera.has_method("zoom_punch"):
		gm.main_camera.zoom_punch(scale_amount, duration)

static func shake_camera(gm: Node, intensity: float = 3.5, duration: float = 0.12) -> void:
	if shake_mult_memo() <= 0.0:
		return
	if gm.main_camera != null and is_instance_valid(gm.main_camera) and gm.main_camera.has_method("shake"):
		gm.main_camera.shake(intensity, duration)

static func kick_camera(gm: Node, dir: Vector2, strength: float = 3.0) -> void:
	if shake_mult_memo() <= 0.0:
		return
	if gm.main_camera != null and is_instance_valid(gm.main_camera) and gm.main_camera.has_method("kick_directional"):
		gm.main_camera.kick_directional(dir, strength)

# ---------------- 设置每帧 memo（Android 稳态 GC 治理） ----------------
## get_val 每次调用分配 2 个 String（StringName→String 转换），shake_mult 一次 ≈ 6 个分配；
## 单次暴击命中链原来要穿透读 8 次 get_val（16 String），高频命中下是稳态 GC 停顿来源。
## 这里按帧号缓存本帧读过的开关值：同一帧内首次读取穿透 SettingsManager，之后全帧吃 memo。
## 设置变更最迟下一帧生效——一帧滞后玩家不可感，免接 setting_changed 信号。
## 测试需要同帧生效时调 invalidate_memo()。
static var _memo_frame: int = -1
static var _memo_shake_mult: float = 1.0
static var _memo_hit_stop: bool = true
static var _memo_haptics: bool = true
static var _memo_damage_numbers: bool = true
static var _memo_screen_flash: bool = true

static func _refresh_memo() -> void:
	var f := Engine.get_process_frames()
	if f == _memo_frame:
		return
	_memo_frame = f
	_memo_shake_mult = SettingsManager.shake_mult()
	_memo_hit_stop = bool(SettingsManager.get_val(&"display", &"hit_stop", true))
	_memo_haptics = bool(SettingsManager.get_val(&"display", &"haptics", true))
	_memo_damage_numbers = bool(SettingsManager.get_val(&"display", &"damage_numbers", true))
	_memo_screen_flash = bool(SettingsManager.get_val(&"display", &"screen_flash", true))

## 本帧的震屏幅度倍率（shake_mult 的每帧 memo 版）
static func shake_mult_memo() -> float:
	_refresh_memo()
	return _memo_shake_mult

static func hit_stop_enabled() -> bool:
	_refresh_memo()
	return _memo_hit_stop

static func haptics_enabled() -> bool:
	_refresh_memo()
	return _memo_haptics

## 跳字开关（DamageNumber.spawn 每次命中读取，走 memo 免 String 分配）
static func damage_numbers_enabled() -> bool:
	_refresh_memo()
	return _memo_damage_numbers

## 红屏/濒死脉冲开关（Main 每帧读取）
static func screen_flash_enabled() -> bool:
	_refresh_memo()
	return _memo_screen_flash

## 强制下帧首读重新穿透（测试或特殊同步场景用；正常游戏流一帧 TTL 自然过期）
static func invalidate_memo() -> void:
	_memo_frame = -1

## 零延迟触觉反馈（Android 真机马达振动，桌面端静默忽略）
static func vibrate(duration_ms: int = 18, amplitude: float = 0.5) -> void:
	if not haptics_enabled():
		return
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(duration_ms, amplitude)

## 顿帧时长 30fps 补偿（2026-10-14）：顿帧的感知强度由「连续冻结的渲染帧数」决定，
## 锁 30 帧后 33.3ms 帧长使击杀微顿帧 0.03s 只剩 ~1 帧（≈一帧正常画面，趋近无感），
## 统一乘 1.5 恢复等效感知（0.03s→45ms≈1.4 帧）。切回 60 帧模式时顿帧略沉，属可接受权衡。
const HITSTOP_FPS_COMPENSATION := 1.5

static func hit_stop(gm: Node, duration: float = 0.045, target_scale: float = 0.05) -> void:
	if not hit_stop_enabled():
		return
	gm._hitstop_token += 1
	# 时间缩放不得低于安全地板（GameBalance.HITSTOP_TIMESCALE_FLOOR）：
	# 极端近 0 停顿引发物理与渲染交换链丢帧/黑帧（真机整屏闪一下的元凶之一）
	Engine.time_scale = clampf(target_scale, GameBalance.HITSTOP_TIMESCALE_FLOOR, 1.0)
	# 零分配恢复（2026-10-14）：只写真实毫秒截止时刻，GameManager._process 到点还原；
	# 原实现每次顿帧 create_timer 分配 SceneTreeTimer + 闭包。重复顿帧天然延期（覆写更晚时刻）。
	gm._hitstop_deadline_ms = Time.get_ticks_msec() + int(duration * HITSTOP_FPS_COMPENSATION * 1000.0)

static var _last_crit_hitstop_ms: int = 0
const CRIT_HITSTOP_MIN_INTERVAL := 0.10

## 暴击命中顿帧（限流版）：普通暴击命中顿帧走独立最小间隔闸，
## 防止多穿透/高攻速/连击下每秒十几发暴击连续把时间轴压死。
static func crit_hit_stop(gm: Node) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_crit_hitstop_ms < int(CRIT_HITSTOP_MIN_INTERVAL * 1000.0):
		return
	_last_crit_hitstop_ms = now
	hit_stop(gm, 0.038, 0.16)

static var _last_kill_hitstop_ms: int = 0

## 击杀微顿帧（限流版）：小怪伏诛那一刀的「确认感」。
## 口径：击杀仍属高频事件，KILL_HITSTOP_MIN_INTERVAL 最小间隔保证最坏稳态只是持续轻顿，
## 不会把时间锁死；普通命中与 DoT 跳死不走这里（2026-10-10 打击感重塑）。
static func kill_hit_stop(gm: Node) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_kill_hitstop_ms < int(GameBalance.KILL_HITSTOP_MIN_INTERVAL * 1000.0):
		return
	_last_kill_hitstop_ms = now
	hit_stop(gm, GameBalance.KILL_HITSTOP_DURATION, GameBalance.KILL_HITSTOP_SCALE)

static var _last_crit_kill_hitstop_ms: int = 0

## 暴击击杀顿帧（限流版）：比普通击杀微顿帧更「实」，卖致命暴击的终结特写。
## 独立于 kill_hit_stop 的流水账（暴击斩杀会跳过普通击杀顿帧直接走这里，互不重发）。
static func crit_kill_hit_stop(gm: Node) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_crit_kill_hitstop_ms < int(GameBalance.CRIT_KILL_HITSTOP_MIN_INTERVAL * 1000.0):
		return
	_last_crit_kill_hitstop_ms = now
	hit_stop(gm, GameBalance.CRIT_KILL_HITSTOP_DURATION, GameBalance.CRIT_KILL_HITSTOP_SCALE)

# ---------------- 命中反馈全局限流（2026-10-11 频闪治理） ----------------
## 远程穿透/弹射/多弹齐射下每秒命中可达几十次，逐刀全量「爆散+微震」会糊成满屏频闪与持续抖屏。
## 口径与 kill_hit_stop 一致：普通档按最小间隔放行（到点才收下一发，持续高频下是匀速节奏而非全量），
## （受击火花 / 死亡爆散已整体下线，其 hit_spark_gate / kill_burst_gate 一并移除；重构替代品时另起新闸。）

static var _last_micro_kick_ms: int = 0

## 镜头微冲击闸：普通命中 2.8px / 普通击杀 2.5px 的方向性微冲击走这里排队，
## 间隔内静默丢弃；暴击 6.5px / 精英击杀 8.5px 不走此闸（调用方直接 kick_camera）。
static func micro_kick_gate(now_ms: int = -1) -> bool:
	var now: int = Time.get_ticks_msec() if now_ms < 0 else now_ms
	if now - _last_micro_kick_ms < int(GameBalance.MICRO_KICK_MIN_INTERVAL * 1000.0):
		return false
	_last_micro_kick_ms = now
	return true

## 限流版方向性微冲击：闸通过才发（shake_mult=0 时 kick_camera 内部照旧静默）
static func micro_kick(gm: Node, dir: Vector2, strength: float = 3.0) -> void:
	if micro_kick_gate():
		kick_camera(gm, dir, strength)


static func feedback(gm: Node, tier: int) -> void:
	match tier:
		gm.FeedbackTier.SMALL:
			add_trauma(gm, 0.08)
		gm.FeedbackTier.MEDIUM:
			add_trauma(gm, 0.18)
			hit_stop(gm, 0.035, 0.22)
		gm.FeedbackTier.LARGE:
			add_trauma(gm, 0.38)
			hit_stop(gm, 0.065, 0.16)
			zoom_punch(gm, 0.035, 0.15)
		gm.FeedbackTier.HEAVY:
			add_trauma(gm, 0.70)
			hit_stop(gm, 0.09, 0.12)
			zoom_punch(gm, 0.06, 0.22)

static func pulse_damage_vignette(gm: Node, color: Color = Color(0.85, 0.12, 0.12, 0.65), duration: float = 0.22) -> void:
	gm.screen_damage_pulsed.emit(color, duration)
