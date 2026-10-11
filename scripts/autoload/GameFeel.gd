class_name GameFeel
extends RefCounted

## 打击感（Game-Feel）门面子系统
## 从 GameManager 抽离，负责镜头创伤震屏、缩放冲击、顿帧（Hit-Stop）与受击红晕脉冲。

static func add_trauma(gm: Node, amount: float) -> void:
	if SettingsManager.shake_mult() <= 0.0:
		return
	if gm.main_camera != null and is_instance_valid(gm.main_camera) and gm.main_camera.has_method("add_trauma"):
		gm.main_camera.add_trauma(amount)

static func zoom_punch(gm: Node, scale_amount: float = 0.05, duration: float = 0.18) -> void:
	if SettingsManager.shake_mult() <= 0.0:
		return
	if gm.main_camera != null and is_instance_valid(gm.main_camera) and gm.main_camera.has_method("zoom_punch"):
		gm.main_camera.zoom_punch(scale_amount, duration)

static func shake_camera(gm: Node, intensity: float = 3.5, duration: float = 0.12) -> void:
	if SettingsManager.shake_mult() <= 0.0:
		return
	if gm.main_camera != null and is_instance_valid(gm.main_camera) and gm.main_camera.has_method("shake"):
		gm.main_camera.shake(intensity, duration)

static func kick_camera(gm: Node, dir: Vector2, strength: float = 3.0) -> void:
	if SettingsManager.shake_mult() <= 0.0:
		return
	if gm.main_camera != null and is_instance_valid(gm.main_camera) and gm.main_camera.has_method("kick_directional"):
		gm.main_camera.kick_directional(dir, strength)

## 零延迟触觉反馈（Android 真机马达振动，桌面端静默忽略）
static func vibrate(duration_ms: int = 18, amplitude: float = 0.5) -> void:
	if not bool(SettingsManager.get_val(&"display", &"haptics", true)):
		return
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(duration_ms, amplitude)

static func hit_stop(gm: Node, duration: float = 0.045, target_scale: float = 0.05) -> void:
	if not bool(SettingsManager.get_val(&"display", &"hit_stop", true)):
		return
	gm._hitstop_token += 1
	var token: int = gm._hitstop_token
	Engine.time_scale = target_scale
	gm.get_tree().create_timer(duration, true, false, true).timeout.connect(func():
		if gm._hitstop_token == token:
			Engine.time_scale = 1.0
	)

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
## 远程穿透/弹射/多弹齐射下每秒命中可达几十次，逐刀全量「火花+微震」会糊成满屏频闪与持续抖屏。
## 口径与 kill_hit_stop 一致：普通命中按最小间隔放行（到点才收下一发，持续高频下是匀速节奏而非全量），
## 暴击/精英作为「值得看」的节点直通且不消耗间隔窗口。now_ms 可注入以便单测钉时间。

static var _last_hit_spark_ms: int = 0

## 普通命中火花闸：间隔内拒绝，暴击直通。被拒的那次命中仍有闪白/挤压/跳字兜底。
static func hit_spark_gate(crit: bool, now_ms: int = -1) -> bool:
	if crit:
		return true
	var now: int = Time.get_ticks_msec() if now_ms < 0 else now_ms
	if now - _last_hit_spark_ms < int(GameBalance.HIT_SPARK_MIN_INTERVAL * 1000.0):
		return false
	_last_hit_spark_ms = now
	return true

static var _last_kill_burst_ms: int = 0

## 普通小怪死亡爆散闸：间隔内拒绝，精英/Boss 直通（不消耗普通档窗口）。
static func kill_burst_gate(elite: bool, now_ms: int = -1) -> bool:
	if elite:
		return true
	var now: int = Time.get_ticks_msec() if now_ms < 0 else now_ms
	if now - _last_kill_burst_ms < int(GameBalance.KILL_BURST_MIN_INTERVAL * 1000.0):
		return false
	_last_kill_burst_ms = now
	return true

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
			hit_stop(gm, 0.035, 0.08)
		gm.FeedbackTier.LARGE:
			add_trauma(gm, 0.38)
			hit_stop(gm, 0.065, 0.04)
			zoom_punch(gm, 0.035, 0.15)
		gm.FeedbackTier.HEAVY:
			add_trauma(gm, 0.70)
			hit_stop(gm, 0.09, 0.02)
			zoom_punch(gm, 0.06, 0.22)

static func pulse_damage_vignette(gm: Node, color: Color = Color(0.85, 0.12, 0.12, 0.65), duration: float = 0.22) -> void:
	gm.screen_damage_pulsed.emit(color, duration)
