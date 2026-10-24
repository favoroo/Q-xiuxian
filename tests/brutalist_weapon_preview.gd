extends Control

## 新野兽派武器重绘【全量 27 器形矩阵预览】（非判据，必须开窗跑）
##   $G --path . res://tests/BrutalistWeaponPreview.tscn -- --export [-- --out <path>]
##
## 直接实例化战斗同款 ProceduralWeaponRenderer：已被 BrutalistXxxShapes 接管的器形
## 显示新野兽派画法，未接管的回退旧画法（=待办，进度一眼可见）。
## 每格：大=放大看形（1.35），小=实战尺寸（0.55，与 FloatingWeapon 一致）。
## 默认导出 tests/styles/brutalist_weapon_preview.png 后退出。

const DEFAULT_OUT := "tests/styles/brutalist_weapon_preview.png"
const TIP_LEN := 26.0
const STAR := 2
const BIG_SCALE := 1.35
const COLS := 7
const CELL_W := 130.0
const CELL_H := 118.0
const GRID_X := 30.0
const GRID_Y := 56.0

## 27 器形 × 代表五行（覆盖金木水火土）。顺序按族：刃 9 / 重 8 / 巧 10。
const CELLS := [
	{"name": "长剑", "shape": "sword", "element": "metal", "upright": false},
	{"name": "狂刀", "shape": "saber", "element": "fire", "upright": false},
	{"name": "飞刀", "shape": "dagger", "element": "metal", "upright": false},
	{"name": "手里剑", "shape": "shuriken", "element": "metal", "upright": false},
	{"name": "开山斧", "shape": "axe", "element": "earth", "upright": false},
	{"name": "金蛟剪", "shape": "shears", "element": "metal", "upright": false},
	{"name": "透骨钉", "shape": "nail", "element": "wood", "upright": false},
	{"name": "冰针", "shape": "needles", "element": "water", "upright": false},
	{"name": "金锥", "shape": "awl", "element": "metal", "upright": true},
	{"name": "法印", "shape": "seal", "element": "earth", "upright": true},
	{"name": "令牌", "shape": "tablet", "element": "earth", "upright": true},
	{"name": "天灯", "shape": "lantern", "element": "fire", "upright": true},
	{"name": "战鼓", "shape": "drum", "element": "wood", "upright": true},
	{"name": "裂山铎", "shape": "bell", "element": "earth", "upright": true},
	{"name": "重锤", "shape": "hammer", "element": "water", "upright": true},
	{"name": "重锏", "shape": "mace", "element": "earth", "upright": true},
	{"name": "重盾", "shape": "shield", "element": "earth", "upright": false},
	{"name": "灵符", "shape": "talisman", "element": "wood", "upright": true},
	{"name": "折扇", "shape": "fan", "element": "water", "upright": false},
	{"name": "灵鞭", "shape": "whip", "element": "wood", "upright": true},
	{"name": "金尺", "shape": "ruler", "element": "metal", "upright": false},
	{"name": "飞梭", "shape": "shuttle", "element": "water", "upright": false},
	{"name": "弹弓", "shape": "sling", "element": "wood", "upright": false},
	{"name": "火葫芦", "shape": "calabash", "element": "fire", "upright": false},
	{"name": "音笛", "shape": "flute", "element": "water", "upright": true},
	{"name": "紫虹镜", "shape": "mirror", "element": "metal", "upright": false},
	{"name": "雷珠", "shape": "bead", "element": "water", "upright": false},
]


func _ready() -> void:
	custom_minimum_size = Vector2(960, 540)
	size = Vector2(960, 540)
	_build_ui()
	await get_tree().process_frame
	await get_tree().process_frame
	_export_image()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.10)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "新野兽派 · 全武器 27 器形矩阵（显示旧画法 = 该形未接管，待办）"
	title.position = Vector2(16, 8)
	GameStyle.label(title, 15, Color(0.93, 0.94, 0.98))
	add_child(title)

	var note := Label.new()
	note.text = "平涂色块 · 粗墨描边 · 硬投影 · 零辉光零渐变（刃器 1-9 / 重器 10-17 / 巧器 18-27；每格：大=放大 小=实战）"
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

		_mount(s, Vector2(x + CELL_W * 0.56, y + 58.0), BIG_SCALE)
		_mount(s, Vector2(x + 22.0, y + 92.0), 0.55)


func _mount(s: Dictionary, pos: Vector2, sc: float) -> void:
	var wr := ProceduralWeaponRenderer.new()
	wr.configure(
		ProceduralWeaponRenderer.shape_from_name(String(s["shape"])),
		String(s["element"]), TIP_LEN, STAR, bool(s["upright"]))
	wr.position = pos
	wr.scale = Vector2.ONE * sc
	add_child(wr)


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
			print("[BrutalistWeaponPreview] 导出 %s" % out_path)
	print("BRUTALIST_WEAPON_PREVIEW_DONE")
	get_tree().quit(0)
