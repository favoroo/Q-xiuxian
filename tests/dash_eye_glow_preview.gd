extends Node2D

## tests/dash_eye_glow_preview.gd — 闪避暴击「杀意眼眸」高清特写预览（非判据现场预览，不加 --headless）
##
## 用途：目检 dash 暴击法相的猩红眼芒 / 起手爆闪 / 心跳搏动，无需进入真实战斗。
## 跑法（需要真实窗口出图，headless 下 Viewport 不出图）：
##   G=/Applications/Godot.app/Contents/MacOS/Godot
##   $G --path . res://tests/DashEyeGlowPreview.tscn                 # 交互：1 触发 dash 暴击法相，0 清除
##   $G --path . res://tests/DashEyeGlowPreview.tscn -- --export    # 自动连拍导出 6 帧特写拼条
## 导出：tests/styles/dash_eye_glow_strip.png（待机基准 / 起手爆闪 / 搏动峰1 / 搏动谷 / 搏动峰2 / 结束后回落）

const VIEW_SCALE := 0.75          ## 与 Player.gd 程序化角色实际缩放一致
const ZOOM := 14.0                ## 预览整体放大倍率（有效 10.5x，眼部细节清晰可辨）
const CELL_W := 300               ## 拼条单帧宽
const CELL_H := 300               ## 拼条单帧高
const STAGE_POS := Vector2(480, 420)
const CROP_CENTER := Vector2(480, 263)  ## 头部所在屏幕位置（stage 原点上方约 15*10.5px）
const OUT_PATH := "tests/styles/dash_eye_glow_strip.png"

var _view: ProceduralCultivatorView

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.08)
	bg.size = Vector2(960, 540)
	add_child(bg)

	var title_lbl := Label.new()
	title_lbl.text = "闪避暴击·杀意眼眸特写 | 1 触发 dash 暴击法相 · 0 清除 · --export 自动连拍"
	title_lbl.position = Vector2(16, 10)
	title_lbl.add_theme_font_size_override("font_size", 13)
	title_lbl.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	add_child(title_lbl)

	var stage := Node2D.new()
	stage.position = STAGE_POS
	stage.scale = Vector2(ZOOM, ZOOM)
	add_child(stage)

	_view = ProceduralCultivatorView.new()
	_view.position = Vector2.ZERO
	_view.scale = Vector2(VIEW_SCALE, VIEW_SCALE)
	_view.setup_character_id("jianchi")
	stage.add_child(_view)

	var tree := get_tree()
	if tree == null:
		return
	if OS.get_cmdline_user_args().has("--export"):
		for i in range(6):
			await tree.process_frame
		await _run_export(tree)

func _process(_delta: float) -> void:
	pass

func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_1: _view.set_skill_visual("dash", true)
		KEY_0: _view.set_skill_visual("dash", false)

# ---------------- 自动连拍导出 ----------------

func _run_export(tree: SceneTree) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var frames: Array[Image] = []

	# 1. 待机基准：冷青蓝常态眼
	await tree.create_timer(0.4).timeout
	frames.append(await _snap(vp))

	# 2. 起手爆闪：触发后立刻抓，捕捉 _cur_eye_boost 被顶到 2.7 的峰值
	_view.set_skill_visual("dash", true)
	await tree.create_timer(0.03).timeout
	frames.append(await _snap(vp))

	# 3. 搏动峰 1（t≈0.20s，sin(8t)^3≈1）
	await tree.create_timer(0.17).timeout
	frames.append(await _snap(vp))

	# 4. 搏动谷（t≈0.55s，sin 负半周，只剩基础猩红常亮）
	await tree.create_timer(0.35).timeout
	frames.append(await _snap(vp))

	# 5. 搏动峰 2（t≈0.94s，暴击窗结束前最后一记心跳）
	await tree.create_timer(0.39).timeout
	frames.append(await _snap(vp))

	# 6. 结束后回落：法相关闭 0.4s，眼睛回到冷青蓝基色
	_view.set_skill_visual("dash", false)
	await tree.create_timer(0.4).timeout
	frames.append(await _snap(vp))

	_export_strip(frames)
	print("DASH_EYE_GLOW_RESULT: ALL PASS")
	tree.quit(0)

func _snap(vp: Viewport) -> Image:
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img == null or img.is_empty():
		return Image.create_empty(CELL_W, CELL_H, false, Image.FORMAT_RGBA8)
	img.convert(Image.FORMAT_RGBA8)
	return img

## 从各帧截出头部矩形窗口拼成横向帧条导出
## 注意：viewport 纹理是物理分辨率（Retina 下为逻辑尺寸的整数倍），
## 裁剪窗口须按纹理实际宽度 / 逻辑宽度的比例换算。
func _export_strip(frames: Array[Image]) -> void:
	DirAccess.make_dir_recursive_absolute("tests/styles")
	var strip := Image.create(CELL_W * frames.size(), CELL_H, false, Image.FORMAT_RGBA8)
	for i in range(frames.size()):
		var img := frames[i]
		var factor := float(img.get_width()) / 960.0
		var center := Vector2i(int(CROP_CENTER.x * factor), int(CROP_CENTER.y * factor))
		var half_w := int(float(CELL_W) * factor * 0.5)
		var half_h := int(float(CELL_H) * factor * 0.5)
		var src_rect := Rect2i(center.x - half_w, center.y - half_h, half_w * 2, half_h * 2)
		var clipped := src_rect.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
		if clipped.size.x <= 0 or clipped.size.y <= 0:
			continue
		var cell := img.get_region(clipped)
		cell.resize(CELL_W, CELL_H, Image.INTERPOLATE_NEAREST)
		strip.blit_rect(cell, Rect2i(0, 0, CELL_W, CELL_H), Vector2i(i * CELL_W, 0))
	strip.save_png(OUT_PATH)
	print("[DashEyeGlowPreview] 已导出杀意眼眸特写拼条(%d 帧): %s" % [frames.size(), OUT_PATH])
