class_name MainLevel
extends Node2D

@onready var joystick: Control = $UILayer/VirtualJoystick
@onready var start_menu: Control = $UILayer/StartMenu
@onready var pause_menu: PauseMenu = $UILayer/PauseMenu
@onready var stats_dialog: Control = $UILayer/PlayerStatsDialog
@onready var settings_dialog: SettingsDialog = $UILayer/SettingsDialog
@onready var vignette_rect: ColorRect = $PostProcessLayer/SoftVignette
var dust_particles: CPUParticles2D
var _vignette_tween: Tween = null
var _low_hp_phase: float = 0.0
var _settings_return_to_pause: bool = false
var _stats_return_to_pause: bool = false
var _manual_return_to_pause: bool = false

func _ready() -> void:
	GameManager.reset_run()
	GameManager.joystick = joystick
	_setup_dust()
	_setup_map_bounds()
	$UILayer/GameHUD.pause_requested.connect(pause_menu.open)
	$UILayer/GameHUD.stats_requested.connect(func():
		_stats_return_to_pause = false
		stats_dialog.open(true)
	)
	pause_menu.stats_requested.connect(func():
		_stats_return_to_pause = true
		stats_dialog.open(false)
	)
	if $UILayer.has_node("WaveShop"):
		$UILayer/WaveShop.stats_requested.connect(func():
			_stats_return_to_pause = false
			stats_dialog.open(false)
		)
	stats_dialog.closed.connect(func():
		if _stats_return_to_pause:
			_stats_return_to_pause = false
			pause_menu.open()
	)
	pause_menu.settings_requested.connect(func():
		_settings_return_to_pause = true
		settings_dialog.open()
	)
	if start_menu.has_signal("settings_requested"):
		start_menu.settings_requested.connect(func():
			_settings_return_to_pause = false
			settings_dialog.open()
		)
	if start_menu.has_signal("career_requested") and $UILayer.has_node("CareerDialog"):
		var career_dialog: Control = $UILayer/CareerDialog
		start_menu.career_requested.connect(func():
			career_dialog.open()
		)
		# 修仙志关闭后刷新主菜单动态角签：奖励领完即灭、灵石囊入账即显
		if career_dialog.has_signal("closed") and start_menu.has_method("_refresh_dynamic_texts"):
			career_dialog.closed.connect(start_menu._refresh_dynamic_texts)
	if $UILayer.has_node("ManualDialog"):
		var manual_dialog: Control = $UILayer/ManualDialog
		if start_menu.has_signal("manual_requested"):
			start_menu.manual_requested.connect(func():
				_manual_return_to_pause = false
				manual_dialog.open()
			)
		pause_menu.manual_requested.connect(func():
			_manual_return_to_pause = true
			manual_dialog.open()
		)
		manual_dialog.closed.connect(func():
			if _manual_return_to_pause:
				_manual_return_to_pause = false
				pause_menu.open()
		)
	settings_dialog.closed.connect(func():
		if _settings_return_to_pause:
			_settings_return_to_pause = false
			pause_menu.open()
	)
	GameManager.screen_damage_pulsed.connect(_on_screen_damage_pulsed)

	# 聚灵阵信号接线：界碑的激活/充能/触发事件通知 HUD 显示对应 UI
	var hud: GameHUD = $UILayer/GameHUD
	for ob_name in ["ObeliskCenter", "ObeliskEast", "ObeliskWest"]:
		if $MapLayer.has_node(ob_name):
			var ob = $MapLayer.get_node(ob_name) as BlessingObelisk
			ob.activation_available.connect(hud.show_obelisk_activation)
			ob.activation_unavailable.connect(hud.hide_obelisk_activation)
			ob.charge_started.connect(hud.on_obelisk_charge_started)
			ob.charge_progress_updated.connect(hud.on_obelisk_charge_progress)
			ob.charge_cancelled.connect(hud.on_obelisk_charge_cancelled)
			ob.blessing_triggered.connect(hud.on_obelisk_blessing_triggered)

	# BGM 交给 AudioManager 的状态机：素材没就位就什么都不播，不再在这里硬切某一条流
	AudioManager.play_bgm_key("battle")

	# 静默检查更新（带24小时节流）
	UpdateManager.check_for_update(false)

	# 开局暂停：先显示开始界面，点「开始游戏」后再选本命法器
	start_menu.open()
	get_tree().paused = true

func _exit_tree() -> void:
	# 静态缓存（敌人共享帧集 / 跳字池 / 特效池与样式表）随场景释放，
	# 不然退出时会报 "resources still in use at exit" 的假泄漏警报。
	EnemyBase.clear_frame_cache()
	DamageNumber.clear_cache()
	JuiceEffect.clear_cache()

func _setup_dust() -> void:
	dust_particles = CPUParticles2D.new()
	dust_particles.amount = 26
	dust_particles.lifetime = 3.2
	dust_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust_particles.emission_rect_extents = Vector2(480, 280)
	dust_particles.gravity = Vector2(0.0, -8.0)
	dust_particles.initial_velocity_min = 4.0
	dust_particles.initial_velocity_max = 12.0
	dust_particles.scale_amount_min = 1.2
	dust_particles.scale_amount_max = 2.4
	dust_particles.color = Color(0.35, 0.85, 1.0, 0.28)
	$AtmosphereLayer.add_child(dust_particles)

func _process(delta: float) -> void:
	if GameManager.player != null and is_instance_valid(GameManager.player):
		if dust_particles != null:
			dust_particles.global_position = GameManager.player.global_position

		# 濒死血量警示脉冲（生命值低于 28% 时边缘微红呼吸跳动）
		var p = GameManager.player
		if bool(SettingsManager.get_val(&"display", &"screen_flash", true)) and p.max_health > 0.0 and (p.current_health / p.max_health) < 0.28:
			_low_hp_phase += delta * 4.5
			var pulse: float = (sin(_low_hp_phase) * 0.5 + 0.5) * 0.45
			if vignette_rect != null and vignette_rect.material is ShaderMaterial:
				var mat = vignette_rect.material as ShaderMaterial
				if _vignette_tween == null or not _vignette_tween.is_valid():
					mat.set_shader_parameter("tint_color", Color(0.85, 0.1, 0.1, 0.15 + pulse * 0.25))
					mat.set_shader_parameter("vignette_opacity", 0.55 + pulse * 0.25)

func _on_screen_damage_pulsed(tint: Color, dur: float) -> void:
	if not bool(SettingsManager.get_val(&"display", &"screen_flash", true)):
		return
	if vignette_rect == null or not (vignette_rect.material is ShaderMaterial):
		return
	var mat = vignette_rect.material as ShaderMaterial
	if _vignette_tween != null and _vignette_tween.is_valid():
		_vignette_tween.kill()
	mat.set_shader_parameter("tint_color", tint)
	mat.set_shader_parameter("vignette_opacity", 0.95)
	_vignette_tween = create_tween()
	# 死亡那一刻场景树随即被结算界面 paused，不放开的话红闪会冻在最红的一帧
	_vignette_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_vignette_tween.tween_method(
		func(alpha: float):
			mat.set_shader_parameter("vignette_opacity", lerpf(0.5, 0.95, alpha)),
		1.0, 0.0, dur
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_vignette_tween.tween_callback(func():
		mat.set_shader_parameter("tint_color", Color(0.0, 0.0, 0.0, 0.1))
		mat.set_shader_parameter("vignette_opacity", 0.5)
	)

## 灵田界碑与战台装饰：可活动范围（GameManager.MAP_HALF_EXTENT）之外压暗，
## 战场中心太极四象古阵与九天锁灵结界光墙（由 ArenaVisualLayer 矢量渲染）
func _setup_map_bounds() -> void:
	var map: Node2D = $MapLayer
	var half: float = GameManager.MAP_HALF_EXTENT
	var ground_half: float = 2400.0

	# 1. 场外压暗：边界到地砖边缘的四块遮罩（保持深渊幽冥压暗）
	var dim := Color(0.02, 0.04, 0.09, 0.66)
	var bands := [
		[Vector2(-ground_half, -ground_half), Vector2(ground_half * 2.0, ground_half - half)],
		[Vector2(-ground_half, half), Vector2(ground_half * 2.0, ground_half - half)],
		[Vector2(-ground_half, -half), Vector2(ground_half - half, half * 2.0)],
		[Vector2(half, -half), Vector2(ground_half - half, half * 2.0)],
	]
	for b in bands:
		var rect := ColorRect.new()
		rect.color = dim
		rect.position = b[0]
		rect.size = b[1]
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map.add_child(rect)

	# 2. 战台程序化矢量层：中心太极四象大阵 + 四方灵脉槽 + 锁灵结界光墙与青铜镇魂阵角
	var arena_vis := ArenaVisualLayer.new()
	arena_vis.half_extent = half
	map.add_child(arena_vis)
