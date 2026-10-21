extends RefCounted

## 截图工具的「出图色彩校准」共用助手（开发期专用，tools/ 与 tests/ 均不进发布包）。
##
## 为什么需要：桌面调试端默认 use_hdr_2d = true，2D 层走 HDR 缓冲 + ACES 色调映射
## （Main.tscn Environment.tonemap_mode = 3）。ACES 会把整体压暗，并把高饱和的品红
## #ff006e 偏成「纯红」——于是同一局游戏，桌面截图又暗又红，而手机（移动端强制 LDR、
## use_hdr_2d 恒 false，见 Main._apply_glow_channel）却是又亮又是正常品红。
## 截图是给玩家看的、要和真机观感一致，所以出图前统一切到「移动端那条渲染路径」：
##   use_hdr_2d = false（LDR 直出，不压暗、不偏色）
##   glow_hdr_threshold = 0.85（LDR 起辉阈值，近纯白亮部仍能起辉，与 GLOW_LDR_THRESHOLD 同源）
##
## 用法（在实例化 Main.tscn 之后、开拍之前调用一次即可）：
##   const CaptureLdr = preload("res://tools/capture_ldr.gd")
##   CaptureLdr.apply(get_viewport(), main)
## 注意：本助手只改渲染通道，不改游戏逻辑；切 use_hdr_2d 后建议等一两帧再截，
## 让帧缓冲重建完成（本函数已 await 两帧）。

const LDR_GLOW_THRESHOLD := 0.85  ## 与 Main.GLOW_LDR_THRESHOLD 同值（LDR 起辉阈值）

## 把视口切到 LDR 直出并落 LDR 起辉阈值。main 传 Main.tscn 实例（用来找 WorldEnvironment）。
static func apply(viewport: Viewport, main: Node) -> void:
	if viewport == null:
		return
	# 1. 关 HDR 2D：ACES 不再作用在 2D 层，画面回到真机（移动端）那条亮而准的直出。
	viewport.use_hdr_2d = false
	# 2. 起辉阈值降到 LDR 档：无 HDR 缓冲时超白会被钳到 1.0，阈值不放低就永远不起辉。
	if main != null:
		var we := main.get_node_or_null("WorldEnvironment") as WorldEnvironment
		if we != null and we.environment != null:
			we.environment.glow_hdr_threshold = LDR_GLOW_THRESHOLD
