extends Node2D

## 皮肤系列预览（非判据现场工具）：全矩阵抓拍
##
## 默认：3 位代表角色 × (原色 + 6 套系列) 矩阵，产物 tests/inspect/skin_preview.png
## --all：21 名角色 × (原色 + 6 套系列) 全矩阵，产物 tests/inspect/skin_preview_all.png
##        （逐角色巡检用：一次看清某系列在哪些角色身上撞色）
##
## 运行（必须带视口，严禁 --headless）：
##   $G --path . res://tests/SkinPreview.tscn
##   $G --path . res://tests/SkinPreview.tscn -- --all

const OUT_PATH := "res://tests/inspect/skin_preview.png"
const OUT_PATH_ALL := "res://tests/inspect/skin_preview_all.png"
const CIDS: Array[String] = ["jianchi", "fuzhen", "kuangzhan"]

## 全矩阵每页列数（7 = 原色 + 6 套）；21 角色分 3 页，每页 7 行
const ALL_COLS := 7
const ALL_ROWS_PER_PAGE := 7
## 全矩阵栅格：列宽/行高按 960×540 视口铺满（7 列 × 128px、7 行 × 74px）
const ALL_CELL_W := 128.0
const ALL_CELL_H := 74.0
const ALL_COL_X := 34.0   ## 首列 x（左侧留给角色名）
const ALL_ROW_Y := 20.0   ## 首行 y
const ALL_VIEW_SCALE := 0.85

func _ready() -> void:
	var all_mode := "--all" in OS.get_cmdline_user_args()
	if all_mode:
		await _render_all()
	else:
		await _render_sample()

func _render_sample() -> void:
	_setup_bg()
	for r in range(CIDS.size()):
		var cid := CIDS[r]
		for c in range(-1, SkinData.count()):
			var view := _make_view(cid, c, Vector2(78 + (c + 1) * 118.0, 132 + r * 172.0), 1.45)
			_label_skin(view, c)
		_label_char(cid, Vector2(8, 120 + r * 172.0))
	await _capture(OUT_PATH)

## 21 角色全矩阵：每页 7 角色 × 7 皮肤，3 页共 21 角色
func _render_all() -> void:
	var all_ids := CultivatorData.all_ids()
	var per_page := ALL_ROWS_PER_PAGE
	var pages := int(ceil(float(all_ids.size()) / float(per_page)))
	for page in range(pages):
		_clear_children()
		_setup_bg()
		var start := page * per_page
		for r in range(per_page):
			var idx := start + r
			if idx >= all_ids.size():
				break
			var cid: String = all_ids[idx]
			for c in range(-1, SkinData.count()):
				var col := c + 1
				var pos := Vector2(ALL_COL_X + float(col) * ALL_CELL_W + ALL_CELL_W * 0.5,
						ALL_ROW_Y + float(r) * ALL_CELL_H + 46.0)
				var view := _make_view(cid, c, pos, ALL_VIEW_SCALE)
				# 皮肤名压在列头（只在首行画，避免每格重复遮住小人）
				if r == 0:
					_label_skin_col(pos, c)
			_label_char(cid, Vector2(4, ALL_ROW_Y + float(r) * ALL_CELL_H + 34.0), 11)
		await _capture(OUT_PATH_ALL.get_basename() + "_p%d.png" % (page + 1), false)
	get_tree().quit()

func _setup_bg() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.10, 0.16)
	bg.size = Vector2(960, 540)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

func _clear_children() -> void:
	for ch in get_children():
		ch.queue_free()

func _make_view(cid: String, skin_idx: int, pos: Vector2, scl: float) -> ProceduralCultivatorView:
	var view := ProceduralCultivatorView.new()
	view.position = pos
	view.scale = Vector2(scl, scl)
	add_child(view)
	view.setup_character_id(cid, skin_idx)
	return view

func _label_skin(view: ProceduralCultivatorView, skin_idx: int, size_px: int = 14) -> void:
	var lb := Label.new()
	lb.text = "原色" if skin_idx == -1 else String(SkinData.get_theme(skin_idx).get("name", ""))
	lb.add_theme_font_override("font", GameStyle.body_font())
	lb.add_theme_font_size_override("font_size", size_px)
	lb.add_theme_color_override("font_color", Color(0.92, 0.93, 0.96))
	lb.position = view.position + Vector2(-16, 58)
	add_child(lb)

## 全矩阵列头标签（皮肤名，画在首行上方）
func _label_skin_col(view_pos: Vector2, skin_idx: int) -> void:
	var lb := Label.new()
	lb.text = "原色" if skin_idx == -1 else String(SkinData.get_theme(skin_idx).get("name", ""))
	lb.add_theme_font_override("font", GameStyle.body_font())
	lb.add_theme_font_size_override("font_size", 11)
	lb.add_theme_color_override("font_color", Color(0.92, 0.93, 0.96))
	lb.position = view_pos + Vector2(-12, -44)
	add_child(lb)

func _label_char(cid: String, pos: Vector2, size_px: int = 14) -> void:
	var lb := Label.new()
	lb.text = String(CultivatorData.get_def(cid).get("name", cid))
	lb.add_theme_font_override("font", GameStyle.body_font())
	lb.add_theme_font_size_override("font_size", size_px)
	lb.add_theme_color_override("font_color", Color(0.65, 0.72, 0.85))
	lb.position = pos
	add_child(lb)

## 等几帧让渲染器真正画完再抓拍。quit=true 时抓完即退出（单页模式用）。
func _capture(path: String, quit: bool = true) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://tests/inspect")
	img.save_png(path)
	print("SKIN_PREVIEW_SAVED: %s" % path)
	if quit:
		get_tree().quit()
