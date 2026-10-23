extends Node

## 宣传片实机素材录制台（开发期工具，不进发布包）
##
## 目的：为《剑士》宣传片录制 1920×1080 的真实战斗镜头与 UI 静帧。
## 与 tutorial_shot.gd 同源：必须先切 LDR 直出（桌面默认 HDR2D+ACES 会把品红压成红、整体压暗）。
##
## 用法（不能加 --headless，headless 不渲染）：
##   # 战斗镜头（输出到 /tmp/promo_capture/clip_*.avi，需配合 --write-movie）
##   $G --path . res://tools/PromoCapture.tscn --write-movie /tmp/promo_capture/clip_combat.avi \
##      --fixed-fps 60 -- --mode=combat
##
##   # UI 静帧（不需要 --write-movie，脚本自己截 viewport）
##   $G --path . res://tools/PromoCapture.tscn -- --mode=ui_alloc
##
## 模式：combat / boss / elite / ui_menu / ui_select / ui_alloc / ui_shop / ui_stats
##
## 注意：录制 1080p 时需临时把 project.godot 的 window_width_override/height_override
## 改为 1920/1080（movie maker 按窗口尺寸出图），脚本外由调用方处理。

const OUT_DIR := "/tmp/promo_capture"
const CaptureLdr = preload("res://tools/capture_ldr.gd")

## 6 件上阵武器：近战刀光 / 飞剑 / 飞刀扇 / 雷法 / 火符 / 机关炮台
const WEAPONS: Array[String] = [
	"qingyun_sword", "gengjin_feijian", "liuye_feidao",
	"wulei_paizi", "huoyan_fu", "jiguan_nu",
]
const PETS: Array[String] = ["yanhu", "leique", "xuangui"]
## 第 8 波能看到的主流怪种（视觉差异大：史莱姆/邪修/雷兽/花妖/蜂群）
const MOB_MIX: Array[String] = ["slime", "xiexiu", "leibeast", "flower", "fengqun", "xueyong"]
const ELITE_MIX: Array[String] = ["slime", "xiexiu", "leibeast", "fengqun"]

var _mode := "combat"
var _seconds := 0.0          ## 0 = 用模式默认时长；>0 覆盖（调试用）
var _frame := 0
var _t := 0.0
var _main: Node
var _spawner: Node
var _player: Node2D
var _rng := RandomNumberGenerator.new()
var _joy: Node
var _spawn_cd := 0.0
var _skill_cd := 0.0
var _author_hide_cd := 0.0
var _ui_done := false


class FakeJoystick:
	extends Node
	var dir := Vector2.RIGHT
	func get_direction() -> Vector2:
		return dir


func _ready() -> void:
	_rng.seed = 20261023
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			_mode = a.substr(7)
		elif a.begins_with("--seconds="):
			_seconds = float(a.substr(10))
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	call_deferred("_run")


func _run() -> void:
	# 主题色钉死默认档（荧绿），与官网截图同口径
	GameStyle.apply_theme_color(SettingsManager.THEME_DEFAULT)
	DisplayServer.window_set_size(Vector2i(1920, 1080))

	_main = load("res://scenes/main/Main.tscn").instantiate()
	get_tree().root.add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame

	if _mode == "ui_menu":
		# 主菜单原样（_ready 已 open），只等横幅入场动画走完
		await _settle(1.2)
		await _snap("ui_menu.png")
		get_tree().quit(0)
		return

	# —— 进局：跳过开始菜单与黑幕，直接开局 ——
	_main.get_node("UILayer/StartMenu").visible = false
	var backdrop := _main.get_node_or_null("UILayer/StageBackdrop") as Control
	if backdrop != null:
		backdrop.visible = false

	GameManager.cultivator_id = "jianchi"
	# 免死走作者模式的 god_mode（Player.take_damage 入口直接返回）：Boss 接触伤害能一击见底，
	# 帧内补血来不及。作者模式会在顶栏/面板多出「作者」按钮，由 _hide_author_buttons 每帧压掉。
	GameManager.set_author_mode(true)
	AuthorMode.god_mode = true
	GameManager.start_run("qingyun_sword")
	GameManager.player.add_to_group("player")
	_player = GameManager.player
	_spawner = GameManager.wave_spawner

	# 摇杆替换成脚本驱动，让角色按圆周走位（真实游戏里是手指拖出来的）
	_joy = FakeJoystick.new()
	_joy.name = "PromoJoystick"
	get_tree().root.add_child(_joy)
	GameManager.joystick = _joy

	# 出图色彩校准：切 LDR 直出（必须在首拍截图前，切完等两帧重建帧缓冲）
	CaptureLdr.apply(get_viewport(), _main)
	# 录制时帧率本来就低于 60（movie maker 逐帧渲染），Main 的自动降档会误判成卡顿，
	# 关掉辉光并在画面上弹「已自动关闭辉光」的提示条 —— 宣传片里不能出现这句。
	_main.set("_glow_auto_offed", true)
	_main.set("_glow_toasted", true)
	_main.set("_glow_low_streak", 0)
	await get_tree().process_frame
	await get_tree().process_frame

	match _mode:
		"combat":
			await _setup_combat()
		"boss":
			await _setup_boss()
		"elite":
			await _setup_elite()
		"ui_select":
			await _shot_select()
		"ui_alloc":
			await _shot_alloc()
		"ui_shop":
			await _shot_shop()
		"ui_stats":
			await _shot_stats()
		_:
			push_error("未知模式: " + _mode)
			get_tree().quit(1)


# ---------------- 战斗镜头 ----------------

func _setup_combat() -> void:
	await _arm_player(8)
	await _settle(0.4)
	# 首屏就铺满敌潮，避免开场空场
	await _ring_spawn(MOB_MIX, 22, 170.0, 330.0)
	await _settle(1.2)
	await _run_fight(_seconds if _seconds > 0.0 else 13.0)


func _setup_boss() -> void:
	await _arm_player(20)
	await _settle(0.4)
	await _ring_spawn(MOB_MIX, 16, 190.0, 350.0)
	# 第 20 波开场 1.5s 后魔君破阵；这里等它自己登场
	await _settle(2.2)
	await _run_fight(_seconds if _seconds > 0.0 else 12.0)


func _setup_elite() -> void:
	await _arm_player(15)
	await _settle(0.4)
	await _ring_spawn(ELITE_MIX, 18, 180.0, 340.0)
	await _settle(2.0)
	await _run_fight(_seconds if _seconds > 0.0 else 9.0)


## 统一装配：满配武器 + 灵兽 + 指定波次开局
func _arm_player(wave: int) -> void:
	for i in range(1, WEAPONS.size()):
		GameManager.add_weapon(WEAPONS[i])
	for p in PETS:
		GameManager.add_pet(p)
	GameManager.add_spirit_stones(999)
	GameManager.pending_upgrade_points = 6
	# HUD 读数：击杀数给个像样的进度（宣传画面里 0 杀显得空）
	GameManager.kills = wave * 17
	# 相机收紧一档：1920×1080 下 1.1 倍会把竞技场边界拍进画内（场外是纯黑虚空，很跳）。
	# 必须同时写 _base_zoom：SmoothCamera 的 zoom_punch/回弹都往 _base_zoom 收敛，只改 zoom 会被拉回。
	var cam := _main.get_node_or_null("SmoothCamera")
	if cam != null:
		cam.set("_base_zoom", Vector2(1.45, 1.45))
		cam.set("zoom", Vector2(1.45, 1.45))
	# 直接开波（绕开 WAITING 分支自动开第 1 波）
	get_tree().paused = false
	_spawner.start_wave(wave)
	await get_tree().process_frame
	_hide_author_buttons()


## 藏掉作者模式在顶栏/商店/悟道面板里多出来的「作者」按钮（宣传画面里不能出现）
func _hide_author_buttons() -> void:
	for node in get_tree().root.find_children("*", "Button", true, false):
		if node is Button and String(node.name) == "AuthorButton":
			node.visible = false


## HUD「余妖 N/M」读数自洽。
## WaveSpawner 的算式是 left = (total − used) + 场上活妖；脚本补的怪必须记进 used，
## 否则分子会凭空多一份（出现「余妖 118/97」）。记账正确后 left = total − 击杀数，
## 于是读数就是会随战斗递减的「N/40」，和正常一局同形。
## 金蟾档期顺手关掉（它会让分母凭空 +1）。
const HUD_WAVE_TOTAL := 40

func _sync_wave_budget() -> void:
	_spawner.set("max_enemies", 30)
	_spawner.set("_looter_pending", false)
	_spawner.set("_looter_done", true)
	_spawner.set("_budget_total", HUD_WAVE_TOTAL)


## 脚本刷了 n 只怪：同步记进刷怪预算，读数才不会飘
func _account_spawns(n: int) -> void:
	_spawner.set("_budget_used", int(_spawner.get("_budget_used")) + n)


## 战斗循环：脚本驱动走位 + 持续补怪 + 定时放技能，直到帧数走完
func _run_fight(seconds: float) -> void:
	var total := int(seconds * 60.0)
	var start_frame := _frame
	while _frame - start_frame < total:
		if not is_instance_valid(_player) or GameManager.is_game_over:
			break
		await get_tree().process_frame
	print("PROMO_DONE mode=%s frames=%d" % [_mode, _frame])
	get_tree().quit(0)


func _process(delta: float) -> void:
	if _mode.begins_with("ui_") or _player == null:
		return
	_frame += 1
	_t += delta

	# 血条演出：god_mode 让伤害全免，血条会一直是满的（画面像没在打）。
	# 这里手动制造「掉血 → 回血」的起伏，只改读数，不影响生死判定。
	if _player != null and is_instance_valid(_player):
		var hp := float(_player.get("current_health"))
		var max_hp := float(_player.get("max_health"))
		if hp > max_hp * 0.42:
			_player.set("current_health", maxf(max_hp * 0.42, hp - max_hp * delta * 0.085))
		else:
			_player.set("current_health", minf(max_hp, hp + max_hp * delta * 0.16))

	# 作者模式按钮每次显隐刷新都可能被重新点亮，每帧压一次（宣传画面里不能出现）
	if _author_hide_cd <= 0.0:
		_author_hide_cd = 0.25
		_hide_author_buttons()
	_author_hide_cd -= delta

	# Boss 血条：让它在镜头里持续下降，否则满血僵条看着像没在打
	if _mode == "boss":
		var boss := get_tree().get_first_node_in_group("boss")
		if boss != null and is_instance_valid(boss) and not bool(boss.get("dying")):
			var bhp := float(boss.get("current_hp"))
			var bmax := float(boss.get("max_hp"))
			if bhp > bmax * 0.16:
				boss.set("current_hp", maxf(bmax * 0.16, bhp - bmax * delta * 0.075))

	# 圆周走位（半径 140，周期 6s）+ 轻微内收外扩，避免机械感
	var ang := _t * TAU / 6.0
	var r := 140.0 + 26.0 * sin(_t * 1.7)
	if _joy != null:
		# 切向速度方向：让角色沿圆周跑而不是向外漂
		_joy.dir = Vector2(-sin(ang), cos(ang)).normalized()

	# 补怪：同屏太少就补一批，维持视觉密度。脚本刷的怪不占预算，
	# 所以每批之后把预算重新铺满，让 WaveSpawner 自己接着补（两套刷怪节奏才不打架）。
	_spawn_cd -= delta
	if _spawn_cd <= 0.0 and GameManager.enemy_count < 34:
		_spawn_cd = 0.2
		_spawn_batch()
	_sync_wave_budget()

	# 技能冷却好就放，制造位移与光效节奏；闪避带必暴窗口，落地那一刀有跳字
	_skill_cd -= delta
	if _skill_cd <= 0.0:
		_skill_cd = 1.9
		if _player.has_method("try_activate_skill"):
			_player.try_activate_skill()


func _ring_spawn(pool: Array[String], n: int, r_min: float, r_max: float) -> void:
	for i in range(n):
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(r_min, r_max)
		_spawn_one(pool[_rng.randi() % pool.size()], _player.global_position + Vector2(cos(a), sin(a)) * r)
	_account_spawns(n)
	await get_tree().process_frame


func _spawn_batch() -> void:
	var pool: Array[String] = ELITE_MIX if _mode == "elite" else MOB_MIX
	var n := _rng.randi_range(2, 4)
	for i in range(n):
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(280.0, 420.0)
		var pos: Vector2 = _player.global_position + Vector2(cos(a), sin(a)) * r
		var lim := GameManager.MAP_HALF_EXTENT - 40.0
		pos = pos.clamp(Vector2(-lim, -lim), Vector2(lim, lim))
		_spawn_one(pool[_rng.randi() % pool.size()], pos)
	_account_spawns(n)


func _spawn_one(key: String, pos: Vector2) -> void:
	var path: String = String(EnemyData.MOBS.get(key, {}).get("scene_path", ""))
	if path.is_empty():
		return
	var scene := load(path) as PackedScene
	if scene == null:
		return
	var e := EnemyBase.acquire_or_new(scene)
	if e == null:
		return
	e.reset_for_reuse()
	e.global_position = pos
	e.add_to_group("enemies")
	_spawner._scale_to_wave(e)
	e.activate()
	_spawner.get_parent().add_child(e)
	e.scale = Vector2.ONE
	# 宣传片要的是「打得动」：血量砍到 1/6，武器一出手就有击杀爆炸与伤害跳字
	e.max_hp = maxf(8.0, e.max_hp / 6.0)
	e.current_hp = e.max_hp


# ---------------- UI 静帧 ----------------

func _shot_select() -> void:
	var cs := _main.get_node_or_null("UILayer/CultivatorSelect")
	if cs != null and cs.has_method("show_select"):
		cs.show_select()
	await _settle(1.0)
	await _snap("ui_select.png")
	get_tree().quit(0)


func _shot_alloc() -> void:
	await _arm_player(6)
	GameManager.pending_upgrade_points = 5
	GameManager.open_alloc_session()
	await _settle(1.0)
	await _snap("ui_alloc.png")
	get_tree().quit(0)


func _shot_shop() -> void:
	await _arm_player(6)
	GameManager.add_spirit_stones(500)
	GameManager.roll_shop(true)
	var shop := _main.get_node_or_null("UILayer/WaveShop") as Control
	if shop != null:
		shop._on_shop_opened()
	await _settle(1.1)
	await _snap("ui_shop.png")
	get_tree().quit(0)


func _shot_stats() -> void:
	await _arm_player(6)
	GameManager.add_weapon("chiyan_dao")
	GameManager.add_weapon("huoyan_fu")
	await get_tree().process_frame
	var stats := _main.get_node_or_null("UILayer/PlayerStatsDialog") as Control
	if stats != null:
		stats.open(false)
	await _settle(1.0)
	await _snap("ui_stats.png")
	get_tree().quit(0)


# ---------------- 工具 ----------------

func _settle(sec: float) -> void:
	var frames := maxi(1, int(round(sec * 60.0)))
	for i in range(frames):
		await get_tree().process_frame


func _snap(fname: String) -> void:
	await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		print("SNAP FAIL(null) ", fname)
		return
	img.save_png(OUT_DIR + "/" + fname)
	print("SNAP saved %s (%dx%d)" % [fname, img.get_width(), img.get_height()])
