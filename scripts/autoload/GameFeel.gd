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
