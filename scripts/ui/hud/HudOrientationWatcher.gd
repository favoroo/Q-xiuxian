class_name HudOrientationWatcher
extends Node

## HUD 安全区随屏幕方向重算（2026-11-03 反向横屏支持）
##
## 为什么需要轮询：Android 上 180° 翻转（正向横屏 ↔ 反向横屏）时**四个常规读数全不变**
## —— 窗口尺寸/位置、视口尺寸、`screen_get_orientation()`（项目跑 SCREEN_SENSOR_LANDSCAPE
## 时它读的是 `getRequestedOrientation`，翻转前后都返回 4）都不动，所以既不触发
## `Window.size_changed` 也不发 `NOTIFICATION_WM_SIZE_CHANGED`。
## 唯一真正变的是**安全区矩形**：刘海/圆角从左边换到了右边。
## 而 `GameHUD` 只在 `_ready()` 里算过一次 safe area ⇒ 翻转后顶栏左缘还按旧读数让位，
## 生命块压到刘海底下。
##
## 所以签名必须包含 `get_display_safe_area()`。该调用在 Android 侧是
## `getWindowVisibleDisplayFrame` + 缓存的 `getRootWindowInsets`，不走 binder IPC，
## 0.2s 一次（5/s）可忽略；稳定态下签名不变就零写入。
##
## 挂载走静态 attach（与 HudShieldBar / HudContextTips 同一套），GameHUD 只加一行调用。

## 轮询间隔：翻转是低频事件，0.2s 足够快，又不会每帧多一次 DisplayServer 调用
const POLL_SEC := 0.2

var _host: Control = null
var _last_sig: String = ""
var _accum: float = 0.0

static func attach(hud: Control) -> void:
	if hud == null:
		return
	if hud.get_node_or_null("OrientationWatcher") != null:
		return
	var w := HudOrientationWatcher.new()
	w.name = "OrientationWatcher"
	w._host = hud
	w._last_sig = w._signature()
	hud.add_child(w)

func _ready() -> void:
	# 暂停（商店/悟道/暂停菜单）期间也要跟：那些面板本身也吃刘海让位
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	_accum += delta
	if _accum < POLL_SEC:
		return
	_accum = 0.0
	var sig := _signature()
	if sig == _last_sig:
		return
	_last_sig = sig
	if is_instance_valid(_host) and _host.has_method("_apply_safe_area"):
		_host.call("_apply_safe_area")

## 变化签名：安全区 + 窗口尺寸/位置 + 视口尺寸 + 方向值。
## 安全区是主判据（180° 翻转只动它），其余三项是兜底（窗口化拖拽 / 折叠屏 / 分屏）。
func _signature() -> String:
	var vp := _host.get_viewport_rect().size if _host != null else Vector2.ZERO
	return signature(
		DisplayServer.get_display_safe_area(),
		DisplayServer.window_get_position(),
		DisplayServer.window_get_size(),
		vp,
		int(DisplayServer.screen_get_orientation()))

## 纯函数：判据可直接喂假读数验证「安全区左右互换算不算变化」，不必真转屏。
static func signature(safe: Rect2i, win_pos: Vector2i, win_size: Vector2i,
		vp_size: Vector2, orientation: int) -> String:
	return "%d,%d,%d,%d|%d,%d|%d,%d|%.1f,%.1f|%d" % [
		safe.position.x, safe.position.y, safe.size.x, safe.size.y,
		win_pos.x, win_pos.y, win_size.x, win_size.y,
		vp_size.x, vp_size.y, orientation]
