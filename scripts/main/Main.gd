class_name MainLevel
extends Node2D

@onready var joystick: Control = $UILayer/VirtualJoystick
@onready var start_menu: Control = $UILayer/StartMenu
@onready var pause_menu: PauseMenu = $UILayer/PauseMenu
@onready var stats_dialog: Control = $UILayer/PlayerStatsDialog
@onready var settings_dialog: SettingsDialog = $UILayer/SettingsDialog
@onready var vignette_rect: ColorRect = $PostProcessLayer/SoftVignette
var dust_particles: CPUParticles2D
var petal_particles: CPUParticles2D
var _vignette_tween: Tween = null
var _low_hp_phase: float = 0.0
var _settings_return_to_pause: bool = false
var _stats_return_to_pause: bool = false
var _manual_return_to_pause: bool = false

func _ready() -> void:
	# 帧率上限（2026-10-14 性能优化）：默认锁 30（物理同步 30Hz，靠插值保持平滑）；
	# 设置里可开「高帧率模式」升 60。headless 判据依赖自由帧节奏（time_scale 竞态余量），跳过。
	_apply_fps_limit()
	SettingsManager.setting_changed.connect(_on_setting_changed)
	GameManager.reset_run()
	GameManager.joystick = joystick
	_setup_atmosphere()
	_setup_map_bounds()
	_setup_stage_backdrop()
	# 开局在主菜单/选人阶段默认隐藏战斗 HUD 与虚拟摇杆，避免在主页背景中透出
	$UILayer/GameHUD.visible = false
	if joystick != null:
		joystick.visible = false
	if not GameManager.weapons_updated.is_connected(_on_weapons_updated):
		GameManager.weapons_updated.connect(_on_weapons_updated)
	$UILayer/GameHUD.pause_requested.connect(pause_menu.open)
	$UILayer/GameHUD.stats_requested.connect(func():
		_stats_return_to_pause = false
		stats_dialog.open(true)
	)
	pause_menu.stats_requested.connect(func():
		_stats_return_to_pause = true
		stats_dialog.open(false)
	)
	if $UILayer.has_node("LevelUpDialog"):
		var lvl_dialog: Control = $UILayer/LevelUpDialog
		if lvl_dialog.has_signal("pause_requested"):
			lvl_dialog.pause_requested.connect(func():
				pause_menu.open(false)
			)
		if lvl_dialog.has_signal("stats_requested"):
			lvl_dialog.stats_requested.connect(func():
				_stats_return_to_pause = false
				stats_dialog.open(false)
			)
	if $UILayer.has_node("WaveShop"):
		var wave_shop: Control = $UILayer/WaveShop
		wave_shop.stats_requested.connect(func():
			_stats_return_to_pause = false
			stats_dialog.open(false)
		)
		if wave_shop.has_signal("pause_requested"):
			wave_shop.pause_requested.connect(func():
				pause_menu.open(false)
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
		# 修仙志关闭后回刷主菜单顶栏与卡片副行文案
		if career_dialog.has_signal("closed") and start_menu.has_method("_refresh_dynamic_texts"):
			career_dialog.closed.connect(start_menu._refresh_dynamic_texts)
	# 中断续玩：主菜单「继续游戏」按钮 → 按存档重建整局
	if start_menu.has_signal("resume_requested"):
		start_menu.resume_requested.connect(resume_from_save)
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
		# 商店顶栏「图鉴」按钮 / 羁绊详情卡「查看该流派武器」：直达武器图鉴并预选流派筛选；
		# 关闭后回落到仍开着的商店，不走暂停菜单回退
		if $UILayer.has_node("WaveShop"):
			$UILayer/WaveShop.manual_requested.connect(func(tag: String):
				_manual_return_to_pause = false
				manual_dialog.open_weapons_page(tag)
			)
	settings_dialog.closed.connect(func():
		if _settings_return_to_pause:
			_settings_return_to_pause = false
			pause_menu.open()
	)
	if not GameManager.screen_damage_pulsed.is_connected(_on_screen_damage_pulsed):
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

	# BGM 交给 AudioManager 的状态机：开局在主菜单与选人阶段播放 menu，进入回合后由 WaveSpawner 切 battle/trial
	AudioManager.play_bgm_key("menu")

	# 静默检查更新（带24小时节流）
	UpdateManager.check_for_update(false)

	# 开局暂停：默认先显示开始界面，点「开始游戏」后再选本命武器；
	# 局内「重新开始 / 再战一局」重载场景带 restart_to_select 标记时，跳过主菜单直落选角
	get_tree().paused = true
	var go_select: bool = GameManager.restart_to_select
	GameManager.restart_to_select = false
	var cult_select: Control = $UILayer.get_node_or_null("CultivatorSelect")
	if go_select and cult_select != null and cult_select.has_method("show_select"):
		cult_select.show_select()
	else:
		start_menu.open()

## 中断续玩入口（StartMenu「继续游戏」按钮 resume_requested 消费）：
## 灌回整局状态 → 重建玩家实体 → 按存档阶段分发（FIGHT 重开本波 / ALLOC 复现候选卡 / SHOP 复现货架）。
## 树从 _ready 起就是暂停态，全程保持暂停直到 FIGHT 路径显式解暂停——
## 否则 WaveSpawner 的 WAITING 分支会抢跑 start_wave(1)。
func resume_from_save() -> void:
	var saved_phase := RunSave.load_into(GameManager)
	if saved_phase < 0:
		# 坏档降级：按没有存档处理，回落主菜单
		RunSave.clear_save()
		start_menu.open()
		return
	RunSave.apply_player(GameManager)
	var backdrop = get_node_or_null("UILayer/StageBackdrop")
	if backdrop != null:
		backdrop.visible = false
	$UILayer/GameHUD.visible = true
	if joystick != null:
		joystick.visible = true
	# 瞬态归位（对玩家有利）：顿帧时间轴、技能 buff/战意/盾势在 _fill 未覆盖即默认零值，
	# 这里只兜 Engine.time_scale 与存档计时器
	Engine.time_scale = 1.0
	GameManager._autosave_cd = GameManager.AUTOSAVE_INTERVAL
	# HUD 无 _ready 全量兜底的几路读数补发对齐信号（波次/武器由 start_wave 与
	# notify_weapons_updated 触发，血量/经验/三读数/待加点角标必须手动补）
	GameManager.player_hp_changed.emit(GameManager.player.current_health, GameManager.player.max_health)
	GameManager.player_exp_changed.emit(GameManager.experience, GameManager.experience_to_next, GameManager.level)
	GameManager.stats_updated.emit(GameManager.kills, GameManager.game_time, GameManager.spirit_stones)
	GameManager.pending_points_changed.emit(GameManager.pending_upgrade_points)
	start_menu.visible = false
	var spawner := $MapLayer/EntitiesLayer/WaveSpawner as WaveSpawner
	match saved_phase:
		WaveSpawner.Phase.ALLOC:
			spawner.phase = WaveSpawner.Phase.ALLOC
			# 面板从存档 alloc_offers 原样重建卡片（_on_alloc_opened 不重 roll），
			# 绝不能走 open_alloc_session —— 那会把候选卡换成新一批
			GameManager.alloc_opened.emit()
			AudioManager.play_bgm_key("shop")
		WaveSpawner.Phase.SHOP:
			spawner.phase = WaveSpawner.Phase.SHOP
			AudioManager.play_bgm_key("shop")
			GameManager.shop_opened.emit()
		_:
			# FIGHT/CLEARING：本波从头重打，金币/经验/血量以最后一次自动存档为准
			_run_resumed_fight(spawner)

## FIGHT 恢复路径单独一拍：start_wave 会按存档波次重建（预算/匣子/金蟾抽定 + HUD 对齐），
## 解暂停后 WaveSpawner._process 才接管刷怪。defer 到下一帧，让本帧先跳过 WAITING 分支。
func _run_resumed_fight(spawner: WaveSpawner) -> void:
	await get_tree().process_frame
	if not is_inside_tree() or GameManager.is_game_over:
		return
	get_tree().paused = false
	spawner.start_wave(GameManager.wave_number)

## 帧率上限落地：高帧率模式开 = 60，关 = 30；无头判据不锁帧
func _apply_fps_limit() -> void:
	if DisplayServer.get_name() == "headless":
		return
	Engine.max_fps = 60 if bool(SettingsManager.get_val(&"display", &"fps_60", false)) else 30

func _on_setting_changed(section: StringName, key: StringName, _value: Variant) -> void:
	if section == &"display" and key == &"fps_60":
		_apply_fps_limit()

func _exit_tree() -> void:
	# 归还 autoload 引用槽：场景释放后 Player / WaveSpawner / Joystick 已被释放，
	# 留着悬空引用会让 knockback_vec 等消费点 deref freed object 崩溃。
	GameManager.player = null
	GameManager.wave_spawner = null
	GameManager.joystick = null
	# 静态缓存（敌人共享帧集 / 敌人对象池 / 跳字池 / 特效池与样式表）随场景释放，
	# 不然退出时会报 "resources still in use at exit" 的假泄漏警报。
	EnemyBase.clear_frame_cache()
	EnemyBase.clear_pools()
	PoisonPool.clear_pool()
	GroundDecal.clear_pool()
	DamageNumber.clear_cache()
	JuiceEffect.clear_cache()
	LightningBolt.clear_cache()

func _setup_atmosphere() -> void:
	# 1. 灵尘微光浮游粒子（跟随玩家，主菜单暂停时也持续飘动）
	dust_particles = CPUParticles2D.new()
	dust_particles.process_mode = Node.PROCESS_MODE_ALWAYS
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

	# 2. 飘落灵叶与霜露微粒（带微弱自转与左下斜倾飘风，主菜单暂停时也持续飘落）
	petal_particles = CPUParticles2D.new()
	petal_particles.process_mode = Node.PROCESS_MODE_ALWAYS
	petal_particles.amount = 14
	petal_particles.lifetime = 4.2
	petal_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	petal_particles.emission_rect_extents = Vector2(480, 280)
	petal_particles.gravity = Vector2(-7.0, 15.0)
	petal_particles.initial_velocity_min = 5.0
	petal_particles.initial_velocity_max = 15.0
	petal_particles.angular_velocity_min = -25.0
	petal_particles.angular_velocity_max = 25.0
	petal_particles.scale_amount_min = 1.6
	petal_particles.scale_amount_max = 2.8
	petal_particles.color = Color(0.80, 0.92, 1.0, 0.30)
	$AtmosphereLayer.add_child(petal_particles)

	# 3. 极低对比度缓动薄雾片（增加深邃空间感，零 PointLight2D 开销）
	_setup_ambient_mist()

func _setup_ambient_mist() -> void:
	var mist_tex: Texture2D = preload("res://assets/art/light_radial.png")
	var atmo_layer: Node2D = $AtmosphereLayer
	var mist_configs: Array[Dictionary] = [
		{"pos": Vector2(-180.0, -150.0), "scale": Vector2(8.5, 7.0), "alpha": 0.045, "drift": Vector2(60.0, 30.0), "dur": 22.0},
		{"pos": Vector2(200.0, 140.0), "scale": Vector2(10.0, 8.0), "alpha": 0.050, "drift": Vector2(-50.0, -40.0), "dur": 28.0},
		{"pos": Vector2(0.0, 260.0), "scale": Vector2(9.0, 7.5), "alpha": 0.040, "drift": Vector2(40.0, -25.0), "dur": 18.0},
	]
	for cfg in mist_configs:
		var sprite := Sprite2D.new()
		sprite.texture = mist_tex
		sprite.position = cfg.pos
		sprite.scale = cfg.scale
		sprite.modulate = Color(0.20, 0.65, 0.90, cfg.alpha)
		atmo_layer.add_child(sprite)
		var tw := create_tween().set_loops()
		tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw.tween_property(sprite, "position", cfg.pos + cfg.drift, cfg.dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(sprite, "position", cfg.pos, cfg.dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _process(delta: float) -> void:
	if GameManager.player != null and is_instance_valid(GameManager.player):
		var p_pos: Vector2 = GameManager.player.global_position
		if dust_particles != null:
			dust_particles.global_position = p_pos
		if petal_particles != null:
			petal_particles.global_position = p_pos

			# 濒死生命警示脉冲（阈值走 GameBalance.hp_is_low：与 HUD 血字、灵石阁徽记同一把尺）
			var p = GameManager.player
			# 开关走 GameFeel 每帧 memo：本分支每渲染帧执行，原 get_val 每帧 2 个 String 分配
			var in_low_hp: bool = GameFeel.screen_flash_enabled() and GameBalance.hp_is_low(p.current_health, p.max_health)
			if in_low_hp:
				_low_hp_phase += delta * 4.5
				var pulse: float = (sin(_low_hp_phase) * 0.5 + 0.5) * 0.45
				if vignette_rect != null and vignette_rect.material is ShaderMaterial:
					var mat = vignette_rect.material as ShaderMaterial
					if _vignette_tween == null or not _vignette_tween.is_valid():
						mat.set_shader_parameter("tint_color", Color(0.85, 0.1, 0.1, 0.15 + pulse * 0.25))
						mat.set_shader_parameter("vignette_opacity", 0.55 + pulse * 0.25)
			elif _low_hp_phase > 0.0:
				_low_hp_phase = 0.0
				if vignette_rect != null and vignette_rect.material is ShaderMaterial:
					var mat = vignette_rect.material as ShaderMaterial
					if _vignette_tween == null or not _vignette_tween.is_valid():
						mat.set_shader_parameter("tint_color", Color(0.0, 0.0, 0.0, 0.1))
						mat.set_shader_parameter("vignette_opacity", 0.5)

func _on_weapons_updated(weapons: Array) -> void:
	if not weapons.is_empty():
		if $UILayer.has_node("GameHUD"):
			$UILayer/GameHUD.visible = true
		if joystick != null:
			joystick.visible = true

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

	# 1. 场外压暗：边界到地砖边缘的四块遮罩（保持深渊压暗，去蓝取中性墨色）
	var dim := Color(0.02, 0.02, 0.03, 0.66)
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

	# 2. 地面程序化微细节层：石板裂缝、青苔暗斑、剑痕、碎石、阵外刻痕与深渊剪影（纯静态一次性 _draw）
	var ground_decor := GroundDecorLayer.new()
	ground_decor.half_extent = half
	map.add_child(ground_decor)

	# 3. 战台程序化矢量层：中心太极四象大阵 + 四方灵脉槽 + 锁灵结界光墙与青铜镇魂阵角
	var arena_vis := ArenaVisualLayer.new()
	arena_vis.half_extent = half
	map.add_child(arena_vis)

## 选人阶段黑幕托底
## 链式对话框（选角 → 选技能 → 选武器）用「先淡出再淡入下一个」的非重叠时序，
## 中间空帧会透过 0.88~0.90 的半透明遮罩露出底下冻结的战场（地砖/玩家/HUD），
## 观感是「闪一下游戏场景」。此常驻纯黑幕布在选人期间盖住世界层 + GameHUD + VirtualJoystick，
## 对话框在其上淡入淡出，中间帧是纯黑；选完武器在 StartWeaponSelect._choose 淡出回调里隐藏。
func _setup_stage_backdrop() -> void:
	var backdrop := ColorRect.new()
	backdrop.name = "StageBackdrop"
	backdrop.color = GameStyle.INK
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 开局即显示：从首帧起盖住冻结的战场，消除「先闪一下地图再淡入菜单」的观感。
	# 选人链路（CultivatorSelect）会在玩家进入选人时显式接管其显隐。
	backdrop.visible = true
	var ui: CanvasLayer = $UILayer
	ui.add_child(backdrop)
	# 层级：GameHUD 之后、对话框之前 —— 盖住 VirtualJoystick + GameHUD，但被选人对话框盖在下面
	ui.move_child(backdrop, ui.get_node("GameHUD").get_index() + 1)
	# 审计：幕布只许出现在选人链路，开局后（run_started）任何复亮都是整屏黑闪的元凶，
	# debug 包直接打警告定位翻转点（真机「玩着玩着全屏闪一下」排查通道）
	backdrop.visibility_changed.connect(func():
		if OS.is_debug_build() and backdrop.visible and GameManager.run_started:
			push_warning("StageBackdrop 在对局中被点亮——整屏黑闪嫌疑，请检查选人链路的显隐接管")
	)
