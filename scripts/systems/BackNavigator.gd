extends Node

## 安卓系统「返回」统一路由（2026-10-21）
##
## 问题：Godot 默认 `application/config/quit_on_go_back = true` —— 安卓侧滑/返回键一到，
## `SceneTree._main_window_go_back()` 直接把 `_quit = true`，整局秒退，且**这条路径不经过**
## 游戏里那套 `ui_cancel`（ESC）分层返回逻辑，玩家一次误触就丢进度。
##
## 方案：关掉引擎的「返回即退出」，改为**把返回键翻译成一次 `ui_cancel`**，直接复用全项目
## 既有的 ESC 分层返回栈（暂停菜单 / 各种弹窗 / 详情卡 / 选人链路…… 各自都在 `_unhandled_input`
## 里处理 `ui_cancel`，且顺序天然按 UI 叠放由深到浅）。只有「整棵 UI 都没人消费」时，
## 才走「再按一次返回键退出」的二次确认 —— 与安卓通用习惯一致，也彻底消灭误触秒退。
##
## 关键口径：
## 1. 只在没有界面消费返回键时才可能退出；**局内战斗中无论如何不退出**（战斗里暂停菜单一定会
##    消费这条 ui_cancel；万一异常态没人消费，也绝不退出，只兜底开暂停菜单）。
## 2. 退出走 `exit_confirmed` 信号，由宿主（Main）接 `get_tree().quit()` —— 本节点不自己 quit，
##    方便判据拦截信号做断言，也避免「路由层直接杀进程」这种不可测写法。
## 3. `quit_on_go_back` 在项目设置里已置 false，这里再在运行时兜底设一次（防设置被误改）。
## 4. 通知不受暂停门控（`_notification` 直接投递），但节点自身仍是 ALWAYS，保证暂停态可路由。

## 二次确认窗口（秒）：错过就重新从第一次算
const EXIT_CONFIRM_SEC: float = 2.5
const EXIT_TOAST_TEXT := "再按一次返回键，退出游戏"

## 二段确认后发出；由宿主接 get_tree().quit()
signal exit_confirmed

var _exit_armed_at: float = -1.0e9   ## 上次「已提醒退出」的时间戳；-1e9 = 未武装
var _busy: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 运行时兜底：即便项目设置被改回 true，也不许返回键直接杀进程
	if get_tree() != null:
		get_tree().set_quit_on_go_back(false)

func _notification(what: int) -> void:
	# 只接「系统返回」这一条；应用暂停/关窗的存档兜底在 GameManager._notification 里，互不干扰
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		call_deferred("route_back")

## 判据读数：是否已进入「再按一次退出」的等待窗口
func is_exit_armed() -> bool:
	return _exit_armed_at >= 0.0

## 主入口：把系统返回并进 ui_cancel 分层返回链；无人消费时才可能退出
func route_back() -> void:
	if _busy:
		return
	_busy = true
	var handled := _push_cancel()
	if handled:
		_reset_arm()
		_busy = false
		return

	# 整棵 UI 都没人消费这记返回
	if GameManager.run_started and not GameManager.is_game_over:
		# 局内战斗：绝不允许返回键退出。正常应由 PauseMenu 消费；异常态下兜底开暂停菜单
		_reset_arm()
		_try_open_pause()
		_busy = false
		return

	# 局外（主菜单 / 选角 / 结算后）：二次确认退出，防误触
	_handle_root_exit()
	_busy = false

## 合成一次 ui_cancel 打进引擎，走真机同一套拾取/分层链；返回「是否被消费」
## 按下后必须补一发 release：Input 会把合成 action 记进动作状态，只按不放会让 ui_cancel
## 卡在「一直按着」，后续 ESC 判定（is_action_just_pressed / echo 逻辑）跟着失真。
func _push_cancel() -> bool:
	var down := InputEventAction.new()
	down.action = &"ui_cancel"
	down.pressed = true
	down.strength = 1.0
	get_tree().root.push_input(down)
	var handled := get_viewport().is_input_handled()

	var up := InputEventAction.new()
	up.action = &"ui_cancel"
	up.pressed = false
	up.strength = 0.0
	get_tree().root.push_input(up)

	return handled

func _handle_root_exit() -> void:
	var now := float(Time.get_ticks_msec()) * 0.001
	if now - _exit_armed_at <= EXIT_CONFIRM_SEC:
		_exit_armed_at = -1.0e9
		exit_confirmed.emit()
		return
	_exit_armed_at = now
	UpdateManager.show_toast(EXIT_TOAST_TEXT, GameStyle.GOLD, EXIT_CONFIRM_SEC)

func _reset_arm() -> void:
	_exit_armed_at = -1.0e9

func _try_open_pause() -> void:
	var cs := get_tree().current_scene
	if cs == null:
		return
	# 鸭类型取用：本层是 systems/，不硬引用 UI 类名，免得给测试或裁剪引入编译期依赖
	var pm = cs.get_node_or_null("UILayer/PauseMenu")
	if pm != null and pm.has_method("open") and not pm.visible:
		pm.open()
