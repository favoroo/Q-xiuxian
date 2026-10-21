extends Node

## 安卓返回键判据（2026-10-21）
##
## 用户口径：「手机上侧滑返回就直接退出游戏了，很容易误操作」。
## 根因：Godot 默认 `application/config/quit_on_go_back = true`，安卓侧滑/返回键一到，
## `SceneTree._main_window_go_back()` 直接 `_quit = true` 秒退整局，且完全绕开游戏内
## 那套 `ui_cancel`（ESC）分层返回逻辑。本判据锁住修复后的四条不变量：
##
##   ① 项目设置与运行时 SceneTree 的 quit_on_go_back 均为 false；
##   ② Main 场景里挂了 BackNavigator；
##   ③ 局内战斗按返回 —— 开暂停菜单、绝不发 exit_confirmed（不再秒退）；
##   ④ 局外主菜单按返回 —— 第一次只武装「再按一次」提示，第二次才 exit_confirmed；
##      遮罩弹窗（设置）开着时按返回 —— 只关弹窗，不退出。
##
## 运行: godot --headless --path . res://tests/BackNavCheck.tscn
##
## 说明：判据自建一个独立 BackNavigator 来驱动（不改动 Main 上那只 —— 它的 exit_confirmed
## 直连 get_tree().quit()，真触发会把判据进程杀掉）。路由逻辑与真机完全同一份代码。

var _c := TestCheck.new()
var _main: Node = null
var _nav: Node = null
var _exit_count := 0

func _ready() -> void:
	call_deferred("_run")

func _check(cond: bool, label: String) -> void:
	_c.check(cond, label)

func _run() -> void:
	_main = load("res://scenes/main/Main.tscn").instantiate()
	get_tree().root.add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame

	_test_settings()
	await _test_battle_back_opens_pause()
	await _test_menu_needs_double_press()
	await _test_modal_consumes_back()

	_finish()

func _finish() -> void:
	if _c.report("BACKNAV_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

# ---------------- ① 设置层 ----------------

func _test_settings() -> void:
	var proj = ProjectSettings.get_setting("application/config/quit_on_go_back", true)
	_check(proj == false, "项目设置 quit_on_go_back 已关闭（返回键不再由引擎直接退出）（实际 %s）" % str(proj))
	_check(get_tree().is_quit_on_go_back() == false, "运行时 SceneTree.quit_on_go_back 为 false")
	# ② Main 挂载
	var nav := _main.get_node_or_null("BackNavigator")
	_check(nav != null, "Main 场景已挂载 BackNavigator")
	# 复用 Main 上的节点做驱动（但先摘掉它的 exit→quit 连接不可行，故另建独立实例）
	_nav = load("res://scripts/systems/BackNavigator.gd").new()
	_nav.name = "BackNavProbe"
	_nav.exit_confirmed.connect(func(): _exit_count += 1)
	add_child(_nav)
	_check(_nav.has_method("route_back"), "BackNavigator 暴露 route_back 入口")

# ---------------- ③ 局内：开暂停菜单，不退出 ----------------

func _test_battle_back_opens_pause() -> void:
	var pause := _main.get_node_or_null("UILayer/PauseMenu")
	var start := _main.get_node_or_null("UILayer/StartMenu")
	var gd := _main.get_node_or_null("UILayer/GameOverDialog")
	_check(pause != null and start != null and gd != null, "前置：Main 的 UILayer 各屏幕节点就绪")
	if pause == null or start == null or gd == null:
		return

	# 造一个「局内战斗」态：已开局、未结算、主菜单藏起、无弹窗
	GameManager.run_started = true
	GameManager.is_game_over = false
	start.visible = false
	gd.visible = false
	pause.visible = false
	get_tree().paused = false
	_exit_count = 0

	_nav.route_back()
	await get_tree().process_frame

	_check(_exit_count == 0, "局内按返回：绝不退出（不发 exit_confirmed）")
	_check(pause.visible, "局内按返回：暂停菜单被唤出（返回键并入了 ui_cancel 分层链）")

	# 收尾：关掉暂停菜单、复原局内标志
	if pause.visible:
		pause.close(false)
		await get_tree().process_frame
	GameManager.run_started = false
	get_tree().paused = false

# ---------------- ④ 局外主菜单：二次确认 ----------------

func _test_menu_needs_double_press() -> void:
	var start := _main.get_node_or_null("UILayer/StartMenu")
	var pause := _main.get_node_or_null("UILayer/PauseMenu")
	if start == null:
		return
	# 造「主菜单」态：未开局、主菜单可见、无暂停菜单、无弹窗、未暂停
	GameManager.run_started = false
	GameManager.is_game_over = false
	start.visible = true
	if pause != null:
		pause.visible = false
	get_tree().paused = true   # 主菜单是暂停态
	_exit_count = 0

	_nav.route_back()
	await get_tree().process_frame
	_check(_exit_count == 0, "主菜单第一次按返回：只提示「再按一次」，不退出")
	_check(_nav.is_exit_armed(), "主菜单第一次按返回：进入二次确认等待窗口")

	_nav.route_back()
	await get_tree().process_frame
	_check(_exit_count == 1, "主菜单短时间内再按一次返回：确认退出（发 1 次 exit_confirmed）")

	# 武装状态在退出后应被清空
	await get_tree().create_timer(0.05).timeout
	get_tree().paused = false

# ---------------- ④b 遮罩弹窗开着：先关弹窗，不退出 ----------------

func _test_modal_consumes_back() -> void:
	var settings := _main.get_node_or_null("UILayer/SettingsDialog")
	if settings == null:
		return
	GameManager.run_started = false
	GameManager.is_game_over = false
	var start := _main.get_node_or_null("UILayer/StartMenu")
	if start != null:
		start.visible = true
	get_tree().paused = true
	settings.open()
	await get_tree().process_frame
	_check(settings.visible, "前置：设置弹窗已打开")

	_exit_count = 0
	_nav.route_back()
	# 关闭是 0.16s 淡出 tween，等它落定
	for _i in range(40):
		if not settings.visible:
			break
		await get_tree().process_frame
		await get_tree().create_timer(0.02).timeout

	_check(_exit_count == 0, "设置弹窗开着时按返回：不退出")
	_check(not settings.visible, "设置弹窗开着时按返回：只把弹窗关掉")
	get_tree().paused = false
