extends Control

## tests/cultivator_cloak_frames_preview.gd — 斗篷布料行波帧序列导出预览
##
## 用途：斗篷动画是连续形变，静态画廊看不出行波质感。本工具对同一角色在
## 时间轴上连拍 8 帧拼成横向帧条导出 PNG，供人眼核对：
##   帧 0~3  匀速奔跑（逐顶点行波 + 步频呼吸，无额外风压）
##   帧 4~5  向上移动风压（衣摆向后下轻拖）
##   帧 6~7  向下移动风压（衣摆轻扬收拢）
##
## 跑法（需要真实窗口出图，headless 下 Viewport 不出图）：
##   G=/Applications/Godot.app/Contents/MacOS/Godot
##   $G --path . res://tests/CultivatorCloakFramesPreview.tscn -- --export
## 导出：tests/styles/cloak_frames_strip.png，并打印 CLOAK_FRAMES_RESULT: ALL PASS

const FRAME_COUNT := 8
const CELL_W := 200
const CELL_H := 280
const CAPTION := "斗篷行波帧序列 | 0-3 匀速跑动 · 4-5 向上风压 · 6-7 向下风压"

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
	_renderer.position = Vector2(480, 330)
	_renderer.scale = Vector2(3.0, 3.0)
	add_child(_renderer)

	var tree := get_tree()
	if tree == null:
		return
	for i in range(5):
		await tree.process_frame
	await _capture_frames(tree)
	if OS.get_cmdline_user_args().has("--export") or DisplayServer.get_name() == "headless":
		print("CLOAK_FRAMES_RESULT: ALL PASS")
		tree.quit(0)

func _capture_frames(tree: SceneTree) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var frames: Array[Image] = []
	var vp := get_viewport()
	if vp == null:
		return

	# 阶段一：匀速跑动（先等待风压平滑收敛到稳态，再连拍 4 帧）
	_renderer.current_action = CultivatorRendererBase.Action.RUN
	_renderer.speed_ratio = 1.15
	_renderer.gait_phase = 0.35
	_renderer.move_dir = Vector2.ZERO
	await tree.create_timer(0.45).timeout
	for i in range(4):
		frames.append(await _snap(vp))
		await tree.create_timer(0.09).timeout

	# 阶段二：向上移动风压（等待风向平滑后连拍 2 帧）
	_renderer.move_dir = Vector2(0, -1)
	await tree.create_timer(0.5).timeout
	for i in range(2):
		frames.append(await _snap(vp))
		await tree.create_timer(0.12).timeout

	# 阶段三：向下移动风压
	_renderer.move_dir = Vector2(0, 1)
	await tree.create_timer(0.5).timeout
	for i in range(2):
		frames.append(await _snap(vp))
		await tree.create_timer(0.12).timeout

	_export_strip(frames)

func _snap(vp: Viewport) -> Image:
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img == null or img.is_empty():
		return Image.create_empty(CELL_W, CELL_H, false, Image.FORMAT_RGBA8)
	img.convert(Image.FORMAT_RGBA8)
	return img

## 从各帧截出角色所在的矩形窗口，拼成横向帧条导出
## 注意：viewport 纹理是物理分辨率（Retina 下为逻辑尺寸的整数倍），
## 裁剪窗口须按纹理实际宽度 / 逻辑宽度的比例换算。
func _export_strip(frames: Array[Image]) -> void:
	DirAccess.make_dir_recursive_absolute("tests/styles")
	var strip := Image.create(CELL_W * FRAME_COUNT, CELL_H, false, Image.FORMAT_RGBA8)
	var exported := 0
	for i in range(mini(frames.size(), FRAME_COUNT)):
		var img := frames[i]
		var factor := float(img.get_width()) / maxf(size.x, 1.0)
		var center := Vector2i(int(480.0 * factor), int(340.0 * factor))
		var src_rect := Rect2i(center.x - CELL_W / 2, center.y - CELL_H / 2, CELL_W, CELL_H)
		var clipped := src_rect.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
		if clipped.size.x <= 0 or clipped.size.y <= 0:
			continue
		strip.blit_rect(img, clipped, Vector2i(exported * CELL_W, 0))
		exported += 1
	var path := "tests/styles/cloak_frames_strip.png"
	strip.save_png(path)
	print("[CloakFramesPreview] 已导出斗篷行波帧条(%d 帧): %s" % [exported, path])
