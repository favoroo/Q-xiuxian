class_name MenuNightmareChrome
extends Control

## 噩梦态首页画框：贴屏幕最外沿一圈血朱压边，把整屏「封」进夜色里。
##
## 为什么不用全屏雾 / 暗角 shader（2026-10-29 实测结论）：
##   首页卡片矩阵在 960×540 下占 x≈43~917 / y≈66~514，`nightmare_fog` 的清晰半径 200px /
##   羽化 285px 换算到屏幕后，整圈血雾环都落在卡片矩形「背后」（只在 14~16px 的缝里漏几缕）；
##   挂到卡片之上又会在卡面横切一道环，把可读性压掉。所以氛围改由「舞台底色 + 卡片换色 +
##   这圈画框 + 血雨流星」四件套承担，画框是其中唯一压在 UI 之上的那件。
##
## 位置口径：6px 只吃屏幕最外沿 —— 卡片矩阵左右各留 43px、顶栏带 66px、屏底带 52px，
## 两颗角按钮离屏底 26px / 离左右边 34px，画框永远不会压到任何可点控件。
## 自绘而不是四条 ColorRect：不新增布局节点，layout_check 只量节点、不量 _draw 产物；
## meta 仍按 ResultFx / MenuMeteorShower 的装饰层惯例标 layout_bleed。

## 画框厚度（px）：再粗就会往卡片矩阵的留白里咬
const FRAME_W := 6.0
## 进出场时长（s）：与背景底色补间（0.45s）同拍，略慢一点收尾
const ANIM_TIME := 0.55

var _blend := 0.0
var _tween: Tween

## 分辨率/横竖屏切换后画框要按新尺寸重画（_draw 只吃 queue_redraw，不会自动跟随）
func _ready() -> void:
	resized.connect(queue_redraw)

## 装到宿主（StartMenu）最底层：矩阵离屏边还有 43px，压在卡片「下面」也不会被盖住
static func install(host: Control) -> MenuNightmareChrome:
	var chrome := MenuNightmareChrome.new()
	chrome.name = "MenuNightmareChrome"
	chrome.set_anchors_preset(Control.PRESET_FULL_RECT)
	chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chrome.process_mode = Node.PROCESS_MODE_ALWAYS
	chrome.set_meta("layout_bleed", true)
	chrome.visible = false
	host.add_child(chrome)
	return chrome

## 切氛围：animate=false 用于开菜单时静默同步（不闪不补间）
func set_nightmare(active: bool, animate: bool = true) -> void:
	var target := 1.0 if active else 0.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
		_tween = null
	if not animate or absf(_blend - target) < 0.001:
		_blend = target
		_refresh()
		return
	visible = true
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_method(_set_blend, _blend, target, ANIM_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _set_blend(v: float) -> void:
	_blend = v
	_refresh()

func _refresh() -> void:
	visible = _blend > 0.001
	queue_redraw()

func _draw() -> void:
	var a := clampf(_blend, 0.0, 1.0)
	if a <= 0.001:
		return
	var col := GameStyle.with_alpha(GameStyle.NIGHT_SEAL, a)
	var w := FRAME_W
	var sz := size
	# 上下通宽 + 左右只补中间段，四角不叠两次（半透明色叠加会亮一块）
	draw_rect(Rect2(0.0, 0.0, sz.x, w), col)
	draw_rect(Rect2(0.0, sz.y - w, sz.x, w), col)
	draw_rect(Rect2(0.0, w, w, sz.y - 2.0 * w), col)
	draw_rect(Rect2(sz.x - w, w, w, sz.y - 2.0 * w), col)