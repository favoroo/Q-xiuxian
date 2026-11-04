extends Node2D

## 角色皮肤表现力前后对比抓拍（非判据现场工具）
##
## 三种模式：
##   --chars   21 角色 × [待机A / 待机B / 奔跑A / 奔跑B]（默认皮肤），3 页
##   --skins   3 角色 × 7 皮肤 × [待机A / 待机B]，3 页（大图看系列差异）
##   --both    以上全跑
##
## 运行（必须带视口，严禁 --headless）：
##   $G --path . res://tests/SkinAccentPreview.tscn -- --chars --out-dir=res://tests/inspect/accent_before
##
## 说明：抓拍不靠真实时间等待（同一页面每格状态不同），而是暂停 SceneTree 后
## 手动调 renderer._process(delta) 推进相位，再统一等两帧落笔。
## 该调用在改造前后都成立，因此同一脚本可以先抓「改前」、改完再抓「改后」直接对比。

const OUT_DIR_DEFAULT := "res://tests/inspect/skin_accent"
const CHARS_PER_PAGE := 7
## 皮肤细分页代表：剑士（挂穗类）、灵蝶使（悬浮类）、散修（腰挂类）
const SKIN_STRIP: Array[String] = ["jianchi", "fuzhen", "sanxiu"]

var _out_dir := OUT_DIR_DEFAULT

func _ready() -> void:
	_out_dir = _arg_value("--out-dir", OUT_DIR_DEFAULT)
	var args := OS.get_cmdline_user_args()
	var both := "--both" in args
	var chars_mode := "--chars" in args or both
	var skins_mode := "--skins" in args or both
	var zoom_mode := "--zoom" in args or both
	DirAccess.make_dir_recursive_absolute(_out_dir)
	# 暂停引擎驱动，全部相位由本脚本手动推进
	get_tree().paused = true
	await get_tree().process_frame
	if chars_mode:
		await _render_chars()
	if skins_mode:
		await _render_skins()
	if zoom_mode:
		await _render_zoom()
	get_tree().quit()

func _arg_value(key: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(key + "="):
			return a.substr(key.length() + 1)
	return fallback

# ----------------- 21 角色：待机/奔跑各两帧 -----------------

func _render_chars() -> void:
	var ids := CultivatorData.all_ids()
	var pages := int(ceil(float(ids.size()) / float(CHARS_PER_PAGE)))
	for page in range(pages):
		_clear()
		await get_tree().process_frame
		_setup_bg()
		var cells: Array = []
		var start := page * CHARS_PER_PAGE
		for r in range(CHARS_PER_PAGE):
			var idx := start + r
			if idx >= ids.size():
				break
			var cid: String = ids[idx]
			for col in range(4):
				var pos := Vector2(116 + float(col) * 214.0, 60 + float(r) * 74.0)
				var view := _make_view(cid, -1, pos, 1.0)
				cells.append([view, col])
				if r == 0:
					_label_col(Vector2(pos.x, 10), ["待机A", "待机B", "奔跑A", "奔跑B"][col])
			_label_char(String(CultivatorData.get_def(cid).get("name", cid)),
					Vector2(8, 52 + float(r) * 74.0), 13)
		await _apply_states(cells)
		await _capture("%s/chars_p%d.png" % [_out_dir, page + 1])

# ----------------- 3 角色 × 7 皮肤：待机两帧 -----------------

func _render_skins() -> void:
	var ids: Array[String] = SKIN_STRIP.duplicate()
	for page in range(ids.size()):
		_clear()
		await get_tree().process_frame
		_setup_bg()
		var cid := ids[page]
		var cells: Array = []
		for si in range(-1, SkinData.count()):
			var col := si + 1
			var pos_a := Vector2(78 + float(col) * 124.0, 128.0)
			var pos_b := Vector2(78 + float(col) * 124.0, 336.0)
			var va := _make_view(cid, si, pos_a, 1.0)
			var vb := _make_view(cid, si, pos_b, 1.0)
			cells.append([va, 0])
			cells.append([vb, 1])
			_label_col(Vector2(pos_a.x, 96), "原色" if si < 0 else String(SkinData.get_theme(si).get("name", "")))
		_label_title("%s · %s" % [String(CultivatorData.get_def(cid).get("name", cid)), "皮肤系列两帧"],
				Vector2(8, 14))
		await _apply_states(cells)
		await _capture("%s/skins_%s.png" % [_out_dir, cid])

# ----------------- 3 角色 × 4 状态：放大细节页 -----------------

## 一页 3 个角色，每角色 4 格（2.2 倍），用来核对发丝/挂件/衣角的毫米级差别
func _render_zoom() -> void:
	var ids := CultivatorData.all_ids()
	var per_page := 3
	var pages := int(ceil(float(ids.size()) / float(per_page)))
	for page in range(pages):
		_clear()
		await get_tree().process_frame
		_setup_bg()
		var cells: Array = []
		var start := page * per_page
		for r in range(per_page):
			var idx := start + r
			if idx >= ids.size():
				break
			var cid: String = ids[idx]
			for col in range(4):
				var pos := Vector2(150 + float(col) * 214.0, 92 + float(r) * 152.0)
				var view := _make_view(cid, -1, pos, 2.2)
				cells.append([view, col])
				if r == 0:
					_label_col(Vector2(pos.x - 12, 18), ["待机A", "待机B", "奔跑A", "奔跑B"][col])
			_label_char(String(CultivatorData.get_def(cid).get("name", cid)),
					Vector2(8, 82 + float(r) * 152.0), 14)
		await _apply_states(cells)
		await _capture("%s/zoom_p%d.png" % [_out_dir, page + 1])

# ----------------- 状态推进 -----------------

## col 0/1 = 待机 A/B；col 2/3 = 奔跑 A/B
func _apply_states(cells: Array) -> void:
	for item in cells:
		var view: ProceduralCultivatorView = item[0]
		var col: int = item[1]
		var rd = view.renderer
		if rd == null or not is_instance_valid(rd):
			continue
		if col >= 2:
			rd.current_action = CultivatorRendererBase.Action.RUN
			rd.speed_ratio = 1.0
			rd.move_dir = Vector2(0.0, 1.0)
			rd.gait_phase = 0.2 if col == 2 else 0.7
		else:
			rd.current_action = CultivatorRendererBase.Action.IDLE
		# 手动推进：A/B 差 0.42s（约 1/4 呼吸周期），待机可见发丝/挂件位移
		rd._process(1.10)
		rd._on_before_redraw()
		rd._dirty = true
		rd.queue_redraw()
		await get_tree().process_frame
		if col in [1, 3]:
			rd._process(0.42)
			rd._on_before_redraw()
			rd._dirty = true
			rd.queue_redraw()
	await get_tree().process_frame

# ----------------- 场景与控件 -----------------

func _make_view(cid: String, skin_idx: int, pos: Vector2, scl: float) -> ProceduralCultivatorView:
	var view := ProceduralCultivatorView.new()
	view.position = pos
	view.scale = Vector2(scl, scl)
	add_child(view)
	view.setup_character_id(cid, skin_idx)
	return view

func _setup_bg() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.075, 0.09, 0.14)
	bg.size = Vector2(960, 540)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

func _clear() -> void:
	for ch in get_children():
		ch.queue_free()

func _label_col(pos: Vector2, text: String, size_px: int = 12) -> void:
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_override("font", GameStyle.body_font())
	lb.add_theme_font_size_override("font_size", size_px)
	lb.add_theme_color_override("font_color", Color(0.80, 0.86, 0.95))
	lb.position = pos
	add_child(lb)

func _label_char(name: String, pos: Vector2, size_px: int = 13) -> void:
	var lb := Label.new()
	lb.text = name
	lb.add_theme_font_override("font", GameStyle.body_font())
	lb.add_theme_font_size_override("font_size", size_px)
	lb.add_theme_color_override("font_color", Color(0.62, 0.70, 0.84))
	lb.position = pos
	add_child(lb)

func _label_title(text: String, pos: Vector2) -> void:
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_override("font", GameStyle.body_font())
	lb.add_theme_font_size_override("font_size", 15)
	lb.add_theme_color_override("font_color", Color(0.90, 0.92, 0.97))
	lb.position = pos
	add_child(lb)

func _capture(path: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SKIN_ACCENT_PREVIEW_SAVED: %s" % path)
