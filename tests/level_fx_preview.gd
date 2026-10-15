extends Control

## Lv 徽记升级动效现场预览（非判据）：把 GameHUD 真身摆进来触发一次升级，
## 在特效生命周期内按毫秒定点抓帧，裁左上角徽记区拼成胶片存 /tmp/level_fx_strip.png。
## 运行: $G --path . res://tests/LevelFxPreview.tscn   （必须真渲染，不加 --headless）
## 用途：调这套反馈的「量」时看真实画出来的那一圈有多大、几片星屑，不靠脑补。

const OUT := "/tmp/level_fx_strip.png"
## 取景框：Lv 徽记所在的顶栏左段
const CROP := Rect2i(200, 40, 340, 150)
const ZOOM := 2
## 抓帧时刻（触发后毫秒）：覆盖淡入→峰值→扩散尾段→退场
const SHOTS_MS := [20, 60, 110, 170, 240, 320]

var _hud: Control
## _ready 里的 await 会把控制权交回帧循环，_process 可能先跑 ⇒ 未布防前不抓帧
var _armed := false
var _t0 := 0
var _next := 0
var _shots: Array[Image] = []

func _ready() -> void:
	# 本仓开局即 paused（判据要手动 unpause），预览里徽记 tween 必须真跑起来才抓得到中间帧
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud = (load("res://scenes/ui/GameHUD.tscn") as PackedScene).instantiate()
	add_child(_hud)
	# 等排版出徽记真实尺寸，否则光环按 0 尺寸扩散；再等一帧真出图（首帧要等 ~1.7s 编译着色器，
	# 不等它会把第 1 个抓帧时刻整个吃掉，胶片首格还是全黑）
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	prints("preview ready, badge size =", (_hud.get_node("TopContainer/LeftBox/LevelBadge") as Control).size)
	_hud._on_leveled_up(7)
	_t0 = Time.get_ticks_msec()
	_armed = true

func _process(_d: float) -> void:
	if not _armed:
		if Time.get_ticks_msec() > 8000:
			get_tree().quit()
		return
	var elapsed := Time.get_ticks_msec() - _t0
	if _next >= SHOTS_MS.size():
		return
	if elapsed > 3000:
		prints("preview timeout, shots taken =", _shots.size())
		if _shots.size() > 0:
			_stitch()
		get_tree().quit()
		return
	if elapsed < SHOTS_MS[_next]:
		return
	var img := get_viewport().get_texture().get_image()
	var part := img.get_region(CROP)
	part.convert(Image.FORMAT_RGBA8)
	part.resize(CROP.size.x * ZOOM, CROP.size.y * ZOOM, Image.INTERPOLATE_NEAREST)
	_shots.append(part)
	prints("shot", _next, "t_ms", elapsed)
	_next += 1
	if _next >= SHOTS_MS.size():
		_stitch()
		get_tree().quit()

## 3 列 × 2 行拼胶片，格间留 4px 黑缝
func _stitch() -> void:
	var cell := _shots[0].get_size()
	var cols := 3
	var rows := int(ceil(float(_shots.size()) / cols))
	var gap := 4
	var strip := Image.create(cell.x * cols + gap * (cols - 1), cell.y * rows + gap * (rows - 1), false, _shots[0].get_format())
	strip.fill(Color(0.06, 0.07, 0.09))
	for i in _shots.size():
		var col := i % cols
		var row := int(floor(float(i) / float(cols)))
		var pos := Vector2i(col * (cell.x + gap), row * (cell.y + gap))
		strip.blit_rect(_shots[i], Rect2i(Vector2i.ZERO, cell), pos)
	strip.save_png(OUT)
	prints("saved", OUT, strip.get_size())
