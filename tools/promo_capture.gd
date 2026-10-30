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
## 模式：combat / boss / elite / ui_menu / ui_select / ui_alloc / ui_shop / ui_stats / ui_merge
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

## 合成镜头的推近倍率：三合一演出发生在陈列行（上阵武器那一排），全屏看每格只有 56 见方，
## 不推近根本读不出「三个吃成一个」。上限 1.7 是被 MergeFx 的图标边长夹逼出来的：
## 它把飞行体/结果图标夹在 [16, 96]，槽位 56×1.7=95.2 刚好不撞顶，再放大就会
## 「落点跟着放大、图标尺寸被夹住」而显得越推越小。
const MERGE_ZOOM := 1.65
## 合成镜头里 keeper 格在画面上的落点（逻辑像素 960×540）。
## 横向 480 居中 —— 合成层（F4）绕这一点裁切放大，居中最好摆。
## 纵向 382 是量出来的：推近 1.65 倍后面板底边在 keeper 中心下方 158.4
## （探针 MERGE_GEOM：panel 底边 488.4 − keeper 中心 330），382+158.4=540.4 刚好越过屏底，
## 画面下缘不会留黑带；★3 星章落在 282~334，正压在卡片报价键的下沿，读得清且不挡正文。
const MERGE_ANCHOR := Vector2(480.0, 382.0)
## 第 8 波能看到的主流怪种（视觉差异大：史莱姆/邪修/雷兽/花妖/蜂群）
const MOB_MIX: Array[String] = ["slime", "xiexiu", "leibeast", "flower", "fengqun", "xueyong"]
const ELITE_MIX: Array[String] = ["slime", "xiexiu", "leibeast", "fengqun"]

## 祭坛镜头的上阵武器：刻意不含机关炮台（jiguan_nu）—— 它把炮台架在角色身边，
## 正好盖住人物和碑脚那圈充能弧（2026-10-25 用户：不要配这个机关武器，会把人物遮盖掉）。
## 只留近战刀光与飞剑：打击感还在，但光效都贴着角色，不往碑上糊。
const ALTAR_WEAPONS: Array[String] = ["qingyun_sword", "gengjin_feijian"]
## 祭坛镜头的怪：只放一小撮，且全部撒在远离祭坛的外圈 ——
## 上一版满场怪把激活光柱和地面环埋了（用户：看不到那个激活的圆圈特效）。
const ALTAR_MOBS: Array[String] = ["slime", "xiexiu"]
const ALTAR_MOB_COUNT := 4
## 怪离祭坛的最小距离：祭坛判定圈 95、地面环半径约 110，推近 1.30 倍后 110 会画到
## 屏幕 143 处；取 300 保证圈内连一只怪都不沾（上一版 260 时仍有花妖压在环上）。
const ALTAR_MOB_R_MIN := 300.0
const ALTAR_MOB_R_MAX := 420.0
## 祭坛镜头的机位倍率：1.30 是量出来的上限 —— 碑顶百分比读数（碑顶上方 104 逻辑像素）
## 在 1.55 倍时会顶进 HUD 的波次条、被裁掉一半；1.30 倍下它落在 y≈150，完整可见。
## 碑体加那圈地面环仍占画面主位（环直径约 2×110×1.3=286 逻辑像素，屏高 540 的一半以上）。
const ALTAR_ZOOM := 1.30

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
		"altar":
			await _setup_altar()
		"ui_select":
			await _shot_select()
		"ui_alloc":
			await _shot_alloc()
		"ui_shop":
			await _shot_shop()
		"ui_merge":
			await _shot_merge()
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


## 祭坛激活镜头：站桩长按充能 → 金铢注入 → 全屏冲击爆发。
##
## 2026-10-25 用户反馈「怪太多看不到激活的圆圈特效」「不要配机关武器，会遮住人物」：
## 上一版用 _arm_player 的满配六武器 + 满场怪，结果炮台架在角色身边、伤害数字糊满屏，
## 碑脚那圈走针弧和激活光柱全被埋掉。这一版：
##   ① 只装两把贴身武器（ALTAR_WEAPONS，无炮台），把碑前那块留空；
##   ② 只放 6 只怪、全部撒在 260~380 的外圈，祭坛 110 半径内是干净的；
##   ③ 镜头推近到祭坛（ALTAR_ZOOM），碑体+地面环占画面主位。
func _setup_altar() -> void:
	await _arm_player(9)
	await _settle(0.3)
	# 换成「贴脸两把刀」的配置：先把 _arm_player 装好的六件清掉再重装，
	# 否则机关炮台还在场（它就是遮住人物的那个）
	for w in GameManager.player.get_equipped_weapons_data():
		var node: Node = w.get("node")
		if node != null and is_instance_valid(node):
			GameManager.player.remove_weapon_instance(node)
	for i in range(ALTAR_WEAPONS.size()):
		GameManager.add_weapon(ALTAR_WEAPONS[i])
	# 金币给足（启动价随波上涨，不够会被 start_charge 硬拦）
	GameManager.add_spirit_stones(2000)
	await get_tree().process_frame

	var ob := _main.get_node_or_null("MapLayer/ObeliskCenter") as BlessingObelisk
	if ob == null:
		push_error("祭坛镜头：找不到 ObeliskCenter")
		get_tree().quit(1)
		return
	# 把玩家挪到碑前（判定圈 95 内，站 78 够）—— 再近角色会整个压在碑体上，
	# 把晶柱和碑脚那圈走针弧一起挡住，而这一镜要看的就是那圈环。
	# 站得比判定圈再远一点（86）也仍在 95 内，但相机跟着玩家下移，碑顶那块百分比读数
	# 才不会顶进 HUD 的波次条里（推近 1.55 倍后那行字正好压在条上）。
	GameManager.player.global_position = ob.global_position + Vector2(0, 86)
	if _joy != null:
		_joy.set("dir", Vector2.ZERO)
	await _settle(0.35)
	# 镜头推到祭坛：SmoothCamera 的 _base_zoom 与 zoom 都要写（见 _arm_player 注释）
	var cam := _main.get_node_or_null("SmoothCamera")
	if cam != null:
		cam.set("_base_zoom", Vector2(ALTAR_ZOOM, ALTAR_ZOOM))
		cam.set("zoom", Vector2(ALTAR_ZOOM, ALTAR_ZOOM))
	await _settle(0.5)

	# 清场：_arm_player 的 start_wave 之后 WaveSpawner 已经自己刷了几只，
	# 不清掉的话画面里会多出一撮、读数也会变成「余妖 9/4」。只留脚本撒的那 4 只。
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e):
			e.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	# 只放一小撮怪，且全在外圈（祭坛判定圈 95、地面环约 110，圈内必须干净）
	await _ring_spawn_around(ALTAR_MOBS, ALTAR_MOB_COUNT, ob.global_position,
			ALTAR_MOB_R_MIN, ALTAR_MOB_R_MAX)
	# 关掉 WaveSpawner 自己的补怪：把预算钉成「刚好刷完这 4 只」，
	# 补怪闸门（_budget_used < _budget_total）就永远不成立。
	# 读数口径：余妖 = (total − used) + 场上活妖 = 0 + 4 = 4，分母 4 —— 自洽。
	_spawner.set("max_enemies", 0)
	_spawner.set("_budget_total", ALTAR_MOB_COUNT)
	_spawner.set("_budget_used", ALTAR_MOB_COUNT)
	_spawner.set("_looter_pending", false)
	await _settle(0.4)

	# 长按充能：直接调实体的 start_charge（等价于 HUD 圆键按住），0.8s 充满自动进注金
	# 首次免费档记作已消耗：这一镜要拍「金铢飞入」的收费档演出（2026-10-30）
	GameManager.obelisk_activations = 1
	print("MARK altar_charge frame=%d" % Engine.get_frames_drawn())
	ob.start_charge()
	await _settle(0.8)          # CHARGE_TIME：碑脚弧走满一圈
	print("MARK altar_infuse frame=%d" % Engine.get_frames_drawn())
	await _settle(0.5)          # INFUSION_DUR 0.45：金铢飞入
	print("MARK altar_burst frame=%d" % Engine.get_frames_drawn())
	await _settle(1.6)          # 激活光柱 0.7 + 冲击环 0.5 + 余韵
	print("PROMO_DONE mode=%s frames=%d" % [_mode, _frame])
	get_tree().quit(0)


## 以 center 为心、在 [r_min, r_max] 环带里撒 n 只怪（祭坛镜头专用：避开碑前那块空地）
func _ring_spawn_around(pool: Array[String], n: int, center: Vector2,
		r_min: float, r_max: float) -> void:
	for i in range(n):
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(r_min, r_max)
		var pos := center + Vector2(cos(a), sin(a)) * r
		var lim := GameManager.MAP_HALF_EXTENT - 40.0
		pos = pos.clamp(Vector2(-lim, -lim), Vector2(lim, lim))
		_spawn_one(pool[_rng.randi() % pool.size()], pos)
	_account_spawns(n)
	await get_tree().process_frame


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
	var elapsed := 0.0
	while elapsed < seconds:
		if not is_instance_valid(_player) or GameManager.is_game_over:
			break
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	print("PROMO_DONE mode=%s frames=%d" % [_mode, _frame])
	get_tree().quit(0)


func _process(delta: float) -> void:
	if _mode.begins_with("ui_") or _player == null:
		return
	_frame += 1
	_t += delta

	# 祭坛镜头：站桩，不走位、不补怪 —— 充能要人留在判定圈内，满场怪会埋掉光柱。
	# 只保留血条演出与作者按钮压制（这两件事在祭坛画面里同样需要）。
	if _mode == "altar":
		if _player != null and is_instance_valid(_player):
			var hp_a := float(_player.get("current_health"))
			var max_hp_a := float(_player.get("max_health"))
			if hp_a > max_hp_a * 0.42:
				_player.set("current_health", maxf(max_hp_a * 0.42, hp_a - max_hp_a * delta * 0.085))
			else:
				_player.set("current_health", minf(max_hp_a, hp_a + max_hp_a * delta * 0.16))
		if _author_hide_cd <= 0.0:
			_author_hide_cd = 0.25
			_hide_author_buttons()
		_author_hide_cd -= delta
		if _joy != null:
			_joy.set("dir", Vector2.ZERO)
		return

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


# ---------------- 合成镜头（视频，需配合 --write-movie） ----------------

## 商店三合一演出：镜头推近到**陈列行**（上阵武器那一排）—— 合成动画就发生在那里。
##
## 2026-10-25 用户反馈「完全看不到武器图标了，缩放位置不对」：上一版把镜头对准了
## 上方货架卡片行（OffersScroll），而 MergeFx 的三枚图标是从陈列行（OwnedScroll）
## 起飞、飞进陈列行里的 keeper 格，两处隔着一整排卡片 ⇒ 图标被推到画面最下缘、
## 还被 F4 的说明条压掉一半。取景必须钉在 keeper 格本身。
##
## 节奏：★2→★3 觉醒（1 次）+ ★3→★4 极境（1 次），两记迸发就是宣传片要踩的两拍。
## 每次合成都走真实点击链路（GameStyle.tap → ShopWeaponTip → 详情卡按钮 → MergeFx），
## 不是直接调 merge_weapon，否则拍不到飞行/蓄力/星章。
func _shot_merge() -> void:
	await _arm_player(6)
	# 上阵 6 格已被 _arm_player 填满 ⇒ 后加的会进背包，正好当合成材料。
	# 背包上限 5 格：先铺 5 件 ★2 长剑，合成吃 2 件后剩 3 件，再补 2 件 ★3 就能合第二记。
	for i in range(5):
		GameManager.add_weapon("qingyun_sword", 2)
	GameManager.add_spirit_stones(500)
	GameManager.roll_shop(true)
	var shop := _main.get_node_or_null("UILayer/WaveShop") as WaveShop
	if shop == null:
		push_error("合成镜头：找不到 WaveShop")
		get_tree().quit(1)
		return
	shop._on_shop_opened()
	await _settle(0.5)
	shop.owned_scroll.scroll_horizontal = 0
	await _settle(0.2)
	var k1 := _merge_keeper(shop, "qingyun_sword", 2)
	if k1.is_empty():
		push_error("合成镜头：陈列行里找不到 ★2 长剑槽位")
		get_tree().quit(1)
		return
	await _frame_on_merge_slot(shop, k1["slot"])
	await _settle(0.4)
	# 第一记：★2 → ★3 觉醒
	_mark("burst1_tap")
	await _trigger_merge_tap(shop, k1)
	await _settle(2.5)
	# 第二记：★3 → ★4 极境
	for i in range(2):
		GameManager.add_weapon("qingyun_sword", 3)
	shop.refresh_owned()
	await _settle(0.3)
	var k2 := _merge_keeper(shop, "qingyun_sword", 3)
	if not k2.is_empty():
		await _frame_on_merge_slot(shop, k2["slot"])
		await _settle(0.35)
		_mark("burst2_tap")
		await _trigger_merge_tap(shop, k2)
		await _settle(3.0)
	print("PROMO_DONE mode=%s frames=%d" % [_mode, _frame])
	get_tree().quit(0)


## 打点：把「这一刻」的成片秒数写进日志，供合成层精确对齐踩点。
## 用 Engine.get_frames_drawn() 而不是墙钟 —— movie maker 下它是逐帧出片的计数，
## 除以录制帧率就是成片时间轴上的秒数（MergeFx 迸发在 tap 后 LIFT+fly+charge，
## ★3 ≈ 0.51s、★4 ≈ 0.58s，见 MergeFx 常量）。
func _mark(tag: String) -> void:
	print("MARK %s frame=%d" % [tag, Engine.get_frames_drawn()])


## 陈列行里找第一件 (id, star) 的槽位：返回 {slot, pool, index, item}，找不到返回空字典。
## 上阵与背包都找 —— 上阵满 6 件时材料只能落在背包里，只认 equipped 会一无所获。
func _merge_keeper(shop: WaveShop, w_id: String, star: int) -> Dictionary:
	if shop == null or shop.owned_container == null:
		return {}
	var summary: Array = GameManager.get_weapons_summary()
	for child in shop.owned_container.get_children():
		if not (child is Control) or not child.has_meta("drag_src"):
			continue
		var src: Dictionary = child.get_meta("drag_src")
		var pool := String(src.get("pool", ""))
		var idx := int(src.get("index", -1))
		var it: Dictionary = {}
		if pool == "equipped" and idx >= 0 and idx < summary.size():
			it = summary[idx]
		elif pool == "stash" and idx >= 0 and idx < GameManager.stash.size():
			it = GameManager.stash[idx]
		if it.is_empty():
			continue
		if String(it.get("id", "")) == w_id and int(it.get("star", 1)) == star:
			return {"slot": child as Control, "pool": pool, "index": idx, "item": it}
	return {}


## 把镜头推到「keeper 格落在 MERGE_ANCHOR」的位置。
## 量矩形必须在改 scale **之前**做，且改完要等一帧让容器重排 —— get_global_rect()
## 会跟着父级 scale 一起缩放，先量后改才不会把锚点算歪（上一版就栽在这）。
func _frame_on_merge_slot(shop: WaveShop, slot: Control) -> void:
	var center := shop.get_node_or_null("CenterContainer") as Control
	if center == null or slot == null or not is_instance_valid(slot):
		return
	# 先归位再量：上一记合成后容器可能还带着旧 scale
	center.pivot_offset = Vector2.ZERO
	center.scale = Vector2.ONE
	center.position = Vector2.ZERO
	await get_tree().process_frame
	await get_tree().process_frame
	var rect: Rect2 = slot.get_global_rect()
	if rect.size == Vector2.ZERO:
		return
	var target: Vector2 = rect.get_center()
	center.pivot_offset = Vector2.ZERO
	center.scale = Vector2(MERGE_ZOOM, MERGE_ZOOM)
	center.position = MERGE_ANCHOR - target * MERGE_ZOOM
	await get_tree().process_frame
	await get_tree().process_frame
	var after: Rect2 = slot.get_global_rect()
	# 探针：确认 keeper 真的落在锚点上（推镜算错时这里是唯一能看出偏移的地方）
	var panel := shop.get_node_or_null("CenterContainer/Panel") as Control
	print("MERGE_GEOM slot=%s panel=%s row=%s" % [
		str(after), str(panel.get_global_rect() if panel != null else Rect2()),
		str(shop.owned_scroll.get_global_rect() if shop.owned_scroll != null else Rect2())])


## 走真实点击链路触发三合一：tap 槽位 → 详情卡 → 按「◆ 三合一 ◆」按钮。
## 直接调 merge_weapon 会跳过 MergeFx（飞行/蓄力/星章全靠它演）。
func _trigger_merge_tap(shop: WaveShop, keeper: Dictionary) -> void:
	var slot: Control = keeper.get("slot")
	if slot == null or not is_instance_valid(slot):
		return
	var pool := String(keeper.get("pool", ""))
	var idx := int(keeper.get("index", -1))
	var item: Dictionary = keeper.get("item", {})
	# 与 ShopInventoryRow 的 tap 回调同一条路径（含选中描边）
	DetailTip.close_all(shop)
	shop.selected = {"pool": pool, "index": idx}
	ShopWeaponTip.open(shop, item, pool, idx, slot)
	shop._refresh_inventory()
	await get_tree().process_frame
	await get_tree().process_frame
	# 详情卡里的三合一键：按文案认，不按节点序 —— 卡里还有装备/出售两个键，顺序会随池位变
	var btn := _find_merge_button(shop)
	if btn == null:
		push_error("合成镜头：详情卡里没有三合一按钮（凑齐 3 件了吗？）")
		return
	btn.pressed.emit()


## 在详情卡的操作按钮里找三合一那颗
func _find_merge_button(root: Node) -> Button:
	for node in root.find_children("*", "Button", true, false):
		var b := node as Button
		if b != null and b.text.begins_with("◆ 三合一"):
			return b
	return null


# ---------------- 工具 ----------------

func _settle(sec: float) -> void:
	# 按真实时间累积而不是数帧：movie maker 的 --fixed-fps 决定 delta（30/60 都可能），
	# 数帧会让「等 1 秒」在 30fps 录制下变成 2 秒（2026-10-25 合成镜头 14.9s 的原因）。
	var waited := 0.0
	while waited < sec:
		await get_tree().process_frame
		waited += get_process_delta_time()


func _snap(fname: String) -> void:
	await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		print("SNAP FAIL(null) ", fname)
		return
	img.save_png(OUT_DIR + "/" + fname)
	print("SNAP saved %s (%dx%d)" % [fname, img.get_width(), img.get_height()])
