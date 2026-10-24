extends Control

## 新野兽派机关炮台【6 器形 × 10 把矩阵预览】（临时预览，非判据，必须开窗跑）
##   $G --path . res://tests/brutalist_turret_preview.tscn -- --export [-- --out <path>]
##
## 直接实例化战斗同款 ProceduralTurretRenderer，并补画 TurretUnit 同款底盘圆模拟现场。
## 每格：大 = 放大看形（1.35），小 = 实战尺寸（底盘 1.0 × CoreSprite 0.55，与战斗一致）。
## 默认导出 tests/styles/brutalist_turret_preview.png 后退出。

const DEFAULT_OUT := "tests/styles/brutalist_turret_preview.png"
const STAR := 2
const BIG_SCALE := 1.35
const COLS := 4
const CELL_W := 225.0
const CELL_H := 152.0
const GRID_X := 24.0
const GRID_Y := 52.0

## 10 把机关武器 × 器形/五行（与 WeaponData 一致）
const CELLS := [
	{"name": "机关弩", "shape": "crossbow", "element": "metal"},
	{"name": "凝冰机弩", "shape": "crossbow", "element": "water"},
	{"name": "剑阵盘", "shape": "array_disc", "element": "metal"},
	{"name": "青木炮", "shape": "cannon", "element": "wood"},
	{"name": "喷火兽", "shape": "beast", "element": "fire"},
	{"name": "寒泉兽", "shape": "beast", "element": "water"},
	{"name": "傀儡兽", "shape": "beast", "element": "earth"},
	{"name": "藤萝机关", "shape": "trebuchet", "element": "wood"},
	{"name": "垒石机关", "shape": "trebuchet", "element": "earth"},
	{"name": "烽火台", "shape": "tower", "element": "fire"},
]


func _ready() -> void:
	custom_minimum_size = Vector2(960, 540)
	size = Vector2(960, 540)
	# --cell N --zoom Z：单格放大排查（N 从 1 起）；缺省跑全矩阵
	var args := OS.get_cmdline_user_args()
	var cell_idx := -1
	var zoom := 4.0
	for i in range(args.size()):
		if args[i] == "--cell" and i + 1 < args.size():
			cell_idx = int(args[i + 1]) - 1
		elif args[i] == "--zoom" and i + 1 < args.size():
			zoom = float(args[i + 1])
	if cell_idx >= 0 and cell_idx < CELLS.size():
		_build_ui_single(cell_idx, zoom)
	else:
		_build_ui()
	await get_tree().process_frame
	await get_tree().process_frame
	_export_image()


## 单格放大：底盘同心 + 机体放大到可数像素
func _build_ui_single(cell_idx: int, zoom: float) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.10)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var s: Dictionary = CELLS[cell_idx]
	var name_lbl := Label.new()
	name_lbl.text = "%d %s" % [cell_idx + 1, String(s["name"])]
	name_lbl.position = Vector2(16, 8)
	GameStyle.label(name_lbl, 14, GameStyle.GOLD)
	add_child(name_lbl)
	_mount(s, Vector2(480.0, 290.0), zoom)


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.10)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "新野兽派 · 机关炮台 6 器形 × 10 把矩阵（每格：大=放大看形 小=实战尺寸）"
	title.position = Vector2(16, 8)
	GameStyle.label(title, 15, Color(0.93, 0.94, 0.98))
	add_child(title)

	var note := Label.new()
	note.text = "平涂色块 · 粗墨描边 · 硬投影 · 零辉光零渐变；炮口/兽口/臂端/焰尖一律本地 x=16"
	note.position = Vector2(16, 32)
	GameStyle.label(note, 10, GameStyle.GREY)
	add_child(note)

	for i in range(CELLS.size()):
		var s: Dictionary = CELLS[i]
		var x := GRID_X + float(i % COLS) * CELL_W
		var y := GRID_Y + floorf(float(i) / float(COLS)) * CELL_H

		var name_lbl := Label.new()
		name_lbl.text = "%d %s" % [i + 1, String(s["name"])]
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.position = Vector2(x, y)
		name_lbl.size = Vector2(CELL_W, 14)
		GameStyle.label(name_lbl, 10, GameStyle.GOLD)
		add_child(name_lbl)

		_mount(s, Vector2(x + CELL_W * 0.62, y + 76.0), BIG_SCALE)
		_mount(s, Vector2(x + CELL_W * 0.22, y + 112.0), 1.0)


## 复刻 TurretUnit 结构：holder（战斗缩放）→ 底盘圆 + CoreSprite(0.55) → 渲染器
func _mount(s: Dictionary, pos: Vector2, sc: float) -> void:
	var holder := Node2D.new()
	holder.position = pos
	holder.scale = Vector2.ONE * sc
	add_child(holder)

	var base := FakeBase.new()
	base.elem_col = _edge_color(String(s["element"]))
	holder.add_child(base)

	var core := Node2D.new()
	core.scale = Vector2.ONE * 0.55
	holder.add_child(core)

	var tr := ProceduralTurretRenderer.new()
	tr.configure(
		ProceduralTurretRenderer.shape_from_name(String(s["shape"])),
		String(s["element"]), STAR)
	core.add_child(tr)


func _edge_color(elem: String) -> Color:
	match elem:
		"fire":
			return Color(1.0, 0.52, 0.22, 0.9)
		"water":
			return Color(0.45, 0.78, 1.0, 0.9)
		"wood":
			return Color(0.45, 0.88, 0.50, 0.9)
		"earth":
			return Color(0.88, 0.68, 0.38, 0.9)
	return Color(0.88, 0.74, 0.42, 0.9)


func _export_image() -> void:
	var out_path := DEFAULT_OUT
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--out" and i + 1 < args.size():
			out_path = args[i + 1]
	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		var img := get_viewport().get_texture().get_image()
		if img != null and not img.is_empty():
			img.save_png(out_path)
			print("[BrutalistTurretPreview] 导出 %s" % out_path)
	print("BRUTALIST_TURRET_PREVIEW_DONE")
	get_tree().quit(0)


## TurretUnit 底盘简版复刻（正圆阵盘 + 元素阵缘），只为预览对位，不参与战斗
class FakeBase extends Node2D:
	var elem_col := Color.WHITE

	func _draw() -> void:
		draw_circle(Vector2(0.0, 1.5), 23.4, Color(0.02, 0.03, 0.05, 0.25))
		draw_circle(Vector2(0.0, 1.0), 19.4, Color(0.02, 0.03, 0.05, 0.50))
		draw_circle(Vector2.ZERO, 18.0, Color(0.08, 0.10, 0.14, 0.90))
		draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 40, elem_col, 2.0, true)
		draw_arc(Vector2.ZERO, 13.0, 0.0, TAU, 32, Color(elem_col.r, elem_col.g, elem_col.b, 0.55), 1.2, true)
