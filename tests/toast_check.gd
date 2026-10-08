extends Node

## 更新浮层（Toast）摆位判据：文案 × 屏宽逐档跑真代码，等动画落定后量 rect 说话。
## 运行: godot --headless --path . res://tests/ToastCheck.tscn
##       godot --headless --path . res://tests/ToastCheck.tscn -- --selftest   （验判据有牙齿）
##
## 为什么立这条判据：这类毛病不崩、不报错、编辑器里也看不出来 —— 只有真机看得见。
##  ① 旧写法把「锚点」当「原点」：set_anchors_preset(CENTER_TOP) 之后再
##     `position = Vector2(-160, 36)`，而 Godot 的 position 是父坐标系的绝对值，
##     节点入树后这一次赋值就把浮层整块推到屏外（用户 2026-10-08 真机图：
##     左上角只剩半截「版本 (v0.0.4) ✦」）。
##  ② 旧写法固定 320 宽：长一句的失败原因装不下，字被裁。
##  ③ 滑移若去 tween 居中容器自己的 position，会把入树前算好的 offset_bottom 烘成脏值，
##     实测浮层从 y=36 掉到 y=197（容器拿一个过期的巨大 min height 垂直居中了子节点）。
##
## 尺子取引擎自己的账（Label 折行后的 min size），不另抄一份字体度量：
## 抄一份就会和代码同时错 —— get_string_size 传了 width 也只回一行高，第一版就栽在这。

const TEXTS: Array[String] = [
	"正在检查最新版本，请稍候...",
	"✦ 当前已是最新版本 (v0.0.4) ✦",
	"检查更新失败（无法连接到更新服务器），请稍后重试",
	"检查更新失败（HTTP 403 Forbidden：更新服务器返回的不是 JSON，请检查网络代理是否拦截了 api.github.com 的请求后重试）",
]

## 4:3 平板 / 16:9 基准 / 20:9 宽屏（canvas_items + expand 下可视宽恒 ≥ 960，高跟着变）
const WIDTHS: Array[int] = [720, 960, 1204]

## 等入场动画（0.2s TRANS_BACK）落定再量，读数才是静止位
const SETTLE := 0.4

var _c := TestCheck.new()

func _ready() -> void:
	if "--selftest" in OS.get_cmdline_user_args():
		await _selftest()
		get_tree().quit(0 if _c.report("TOAST_SELFTEST_RESULT") else 1)
		return
	await _run_all()
	get_tree().quit(0 if _c.report("TOAST_RESULT") else 1)

func _run_all() -> void:
	for w in WIDTHS:
		get_tree().root.size = Vector2i(w, 540)
		await get_tree().process_frame
		await get_tree().process_frame
		for t in TEXTS:
			UpdateManager.show_toast(t, GameStyle.YELLOW, 30.0)
			await get_tree().create_timer(SETTLE).timeout
			var probe: Dictionary = UpdateManager.toast_probe()
			_c.check(not probe.is_empty(), "屏宽 %d · 浮层已建" % w)
			if probe.is_empty():
				continue
			var rect: Rect2 = probe["rect"]
			# CanvasLayer.offset 只在绘制时生效，不折进控件的 global rect（实测层偏移 16 时
			# rect 仍报 y=36）—— 判据要量的是**看得见**的那一格，所以在这里把滑移加上。
			var vis := Rect2(rect.position + Vector2(0.0, probe["offset"].y), rect.size)
			_c.check(_rect_ok(vis, probe["label_min"], probe["screen"]),
				"屏宽 %d · 不出屏/居中/停在顶部那一带/装得下（实得 x=%.0f..%.0f y=%.0f..%.0f）：%s" % [
					w, vis.position.x, vis.end.x, vis.position.y, vis.end.y, t])

## 一条浮层的全部几何账：左右在屏内、横向居中、静止在顶栏下方那一带、不铺成通宽横幅、
## 文案按 Label 自己的折行账装得下
func _rect_ok(rect: Rect2, label_min: Vector2, screen: Vector2) -> bool:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return false
	if rect.position.x < 0.0 or rect.end.x > screen.x + 0.5:
		return false
	if absf(rect.get_center().x - screen.x * 0.5) > 1.0:
		return false
	if absf(rect.position.y - (UpdateManager.TOAST_TOP + UpdateManager.TOAST_SLIDE)) > 0.6:
		return false
	if rect.end.y > screen.y:
		return false
	var max_w: float = minf(UpdateManager.TOAST_MAX_W, screen.x - UpdateManager.TOAST_EDGE_MARGIN * 2.0)
	if rect.size.x > max_w + 0.5:
		return false
	if label_min.x > rect.size.x + 0.5 or label_min.y > rect.size.y + 0.5:
		return false
	return rect.size.y >= UpdateManager.TOAST_MIN_H - 0.5

## 反例必须被拦住：拿旧写法的几何喂同一条尺子（label_min 取真浮层折行后的读数）
func _selftest() -> void:
	var long_text := TEXTS[3]
	get_tree().root.size = Vector2i(960, 540)
	await get_tree().process_frame
	UpdateManager.show_toast(long_text, GameStyle.YELLOW, 30.0)
	await get_tree().create_timer(SETTLE).timeout
	var probe: Dictionary = UpdateManager.toast_probe()
	if probe.is_empty():
		_c.check(false, "selftest 前置：浮层未建")
		return
	var raw: Rect2 = probe["rect"]
	var rect := Rect2(raw.position + Vector2(0.0, probe["offset"].y), raw.size)
	var label_min: Vector2 = probe["label_min"]
	var screen: Vector2 = probe["screen"]
	var y := rect.position.y
	_c.check(_rect_ok(rect, label_min, screen),
		"正例 长文案折行后的真浮层放行（x=%.0f..%.0f y=%.0f w=%.0f h=%.0f）" % [
			rect.position.x, rect.end.x, y, rect.size.x, rect.size.y])
	_c.check(not _rect_ok(Rect2(-160, y, rect.size.x, rect.size.y), label_min, screen),
		"反例① 旧写法 x=-160（整块推到屏外）被拦住")
	_c.check(not _rect_ok(Rect2(320, y, 320, UpdateManager.TOAST_MIN_H), label_min, screen),
		"反例② 旧写法固定 320×38（裁掉长文案）被拦住")
	_c.check(not _rect_ok(Rect2(160, y, 640, rect.size.y), label_min, screen),
		"反例③ 铺成 640 通宽横幅被拦住")
	_c.check(not _rect_ok(Rect2(0, y, rect.size.x, rect.size.y), label_min, screen),
		"反例④ 贴左不居中被拦住")
	_c.check(not _rect_ok(Rect2(rect.position.x, 197, rect.size.x, rect.size.y), label_min, screen),
		"反例⑤ 烘到 y=197（容器过期 min height）被拦住")
