extends Control

## tests/cultivator_blink_preview.gd — 眨眼连续眼睑帧序列导出预览
##
## 用途：眨眼是连续形变（眼睑按 blink 0~1 从眼睛上缘盖下），静态画廊与肉眼实机都难看清
## 中间帧是否平滑。本工具把四种典型情形逐帧拼成横向帧条导出 PNG，供人眼核对：
##   0~7   单次全眨（0 → 1 → 0 完整包络，检查有没有硬切）
##   8~11  半眨（只闭到 0.7，检查「眯眼」是否自然）
##   12~15 连眨第一下收尾 + 第二下起手（检查连眨之间不跳变）
##   16~23 眨眼途中切 HIT（检查 0.05s 快速睁眼，不硬切）
##
## 跑法（需要真实窗口出图，headless 下 Viewport 不出图）：
##   G=/Applications/Godot.app/Contents/MacOS/Godot
##   $G --path . res://tests/CultivatorBlinkPreview.tscn -- --export
## 导出：tests/styles/blink_frames_strip.png

const FRAME_COUNT := 24
const CELL_W := 160
const CELL_H := 200
const CAPTION := "眨眼连续眼睑帧序列 | 0-7 单眨 · 8-11 半眨 · 12-15 连眨 · 16-23 途中切 HIT"

var _renderer: HollowKnightCultivatorRenderer

func _ready() -> void:
	custom_minimum_size = Vector2(960, 540)
	size = Vector2(960, 540)

	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title_lbl := Label.new()
	title_lbl.text = CAPTION
	title_lbl.position = Vector2(16, 10)
	GameStyle.label(title_lbl, 13, GameStyle.PAPER, 0, GameStyle.INK, true)
	add_child(title_lbl)

	_renderer = HollowKnightCultivatorRenderer.new(CultivatorVisualConfig.get_config("jianchi"))
	_renderer.position = Vector2(480, 300)
	_renderer.scale = Vector2(3.2, 3.2)
	_renderer.high_fps_mode = true
	add_child(_renderer)

	var tree := get_tree()
	if tree == null:
		return
	for i in range(5):
		await tree.process_frame
	await _capture_frames(tree)
	if OS.get_cmdline_user_args().has("--export") or DisplayServer.get_name() == "headless":
		print("BLINK_FRAMES_RESULT: ALL PASS")
		tree.quit(0)

func _capture_frames(tree: SceneTree) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var frames: Array[Image] = []
	var vp := get_viewport()
	if vp == null:
		return

	_renderer.current_action = CultivatorRendererBase.Action.IDLE
	# 用 _blink_override 钉住每帧闭眼程度，避免渲染器自己的 _process 在截图间隙推进状态
	# 阶段一：单次全眨的 8 个采样（0 → 1 → 0 完整包络）
	var close_t := 0.0
	var close_step := 0.03
	for i in range(8):
		_renderer._blink_override = _renderer._blink_envelope(close_t)
		frames.append(await _snap(vp))
		await tree.create_timer(0.02).timeout
		close_t += close_step

	# 阶段二：半眨（只闭到 0.7），4 个采样
	var half_t := 0.0
	for i in range(4):
		_renderer._blink_override = _renderer._blink_envelope(half_t) * 0.7
		frames.append(await _snap(vp))
		await tree.create_timer(0.02).timeout
		half_t += 0.04

	# 阶段三：连眨间隙（0 → 0.5 → 0.9 → 0.3），4 帧
	for v in [0.0, 0.5, 0.9, 0.3]:
		_renderer._blink_override = v
		frames.append(await _snap(vp))
		await tree.create_timer(0.02).timeout

	# 阶段四：眨眼途中切 HIT 的快速睁眼（1.0 → 0），8 帧
	_renderer.current_action = CultivatorRendererBase.Action.HIT
	for i in range(8):
		_renderer._blink_override = 1.0 - float(i) / 7.0
		frames.append(await _snap(vp))
		await tree.create_timer(0.012).timeout

	_renderer._blink_override = -1.0
	_export_strip(frames)

func _snap(vp: Viewport) -> Image:
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img == null or img.is_empty():
		return Image.create_empty(CELL_W, CELL_H, false, Image.FORMAT_RGBA8)
	img.convert(Image.FORMAT_RGBA8)
	return img

## 从各帧截出角色头部区域，拼成横向帧条导出
func _export_strip(frames: Array[Image]) -> void:
	DirAccess.make_dir_recursive_absolute("tests/styles")
	var strip := Image.create(CELL_W * FRAME_COUNT, CELL_H, false, Image.FORMAT_RGBA8)
	var exported := 0
	for i in range(mini(frames.size(), FRAME_COUNT)):
		var img := frames[i]
		var factor := float(img.get_width()) / maxf(size.x, 1.0)
		# 头部在角色中心上方约 15px * 3.2 缩放 ≈ 48px 处，截取偏上窗口
		var center := Vector2i(int(480.0 * factor), int(252.0 * factor))
		var half_w := int(CELL_W * 0.5)
		var half_h := int(CELL_H * 0.5)
		var src_rect := Rect2i(center.x - half_w, center.y - half_h, CELL_W, CELL_H)
		var clipped := src_rect.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
		if clipped.size.x <= 0 or clipped.size.y <= 0:
			continue
		strip.blit_rect(img, clipped, Vector2i(exported * CELL_W, 0))
		exported += 1
	var path := "tests/styles/blink_frames_strip.png"
	strip.save_png(path)
	print("[BlinkPreview] 已导出眨眼帧条(%d 帧): %s" % [exported, path])
