class_name PreviewBudget
extends RefCounted

## 桌面预览像素预算（2026-10-29 桌面预览卡顿治理）
##
## 根因（本机实测）：桌面 Forward+ 的 2D 画面按【窗口像素】全量光栅化，没有隐藏的 2x/超采样
## 折扣（实测 1280×720 窗口的画面回读就是 1280×720，屏幕是 2880×1800 Retina 也不放大）。
## 于是帧长随窗口面积线性上涨——M1 + 20 敌 + 6 把武器的同负载实测：
## 1280×720（0.9MP）≈60fps、1920×1080（2.1MP）≈45fps、2560×1440（3.7MP）≈29fps、
## 2880×1800（5.2MP）≈18fps；同一局 headless（纯逻辑）只有 ~7ms/帧。
## 移动端稳是因为手机像素本来就在 1080p 量级，且跑 gl_compatibility（填充率更省）。
##
## 口径：桌面预览把【窗口像素】上限钉在 1080p，超过就等比缩回窗口。
## 只缩窗口、不改渲染倍数 —— 画面始终 1:1 像素，不糊、不掉清晰度，
## 代价只是窗口不再铺满 2K/4K 屏。玩家想更大画面时窗口仍可自由缩放到上限内。
##
## 只做桌面：移动端由平台分辨率决定，headless 判据没有真实窗口，都不参与。

const MAX_WIDTH: int = 1920      ## 预览窗口像素宽上限
const MAX_HEIGHT: int = 1080     ## 预览窗口像素高上限
const CAP_TOAST := "◆ 预览窗口已限制在 1080p（保证流畅）◆"

## 本平台是否参与像素预算（桌面原生参与，移动端 / 网页 / headless 不参与）
## 网页画布尺寸由页面 CSS 决定，改窗口尺寸会和页面布局打架（宣传站 iframe 尺寸由 web-deploy 管）。
static func enabled() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	if OS.has_feature("mobile") or OS.has_feature("web"):
		return false
	return true

## 等比缩到上限内。返回 Vector2i.ZERO = 已在预算内，不需要动。
static func clamped_size(size: Vector2i) -> Vector2i:
	if size.x <= 0 or size.y <= 0:
		return Vector2i.ZERO
	if size.x <= MAX_WIDTH and size.y <= MAX_HEIGHT:
		return Vector2i.ZERO
	var k: float = minf(float(MAX_WIDTH) / float(size.x), float(MAX_HEIGHT) / float(size.y))
	return Vector2i(maxi(int(float(size.x) * k), 1), maxi(int(float(size.y) * k), 1))

## 落地到窗口上。返回 true = 这一拍真的夹了一次（调用方据此只提示一次）。
## 注意：会触发 Window.size_changed，调用方需自己防重入。
static func apply(win: Window) -> bool:
	if win == null or not enabled():
		return false
	var target := clamped_size(win.size)
	if target == Vector2i.ZERO:
		return false
	win.size = target
	return true
