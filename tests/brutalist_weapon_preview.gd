extends Control

## 新野兽派武器重绘【全量矩阵预览 · 含同形分型 + 升星三联】（非判据，必须开窗跑）
##   $G --path . res://tests/BrutalistWeaponPreview.tscn -- --export [-- --out <path>]
##
## 直接实例化战斗同款 ProceduralWeaponRenderer：已被 BrutalistXxxShapes 接管的器形
## 显示新野兽派画法，未接管的回退旧画法（=待办，进度一眼可见）。
## 2026-10-24 增列同形分型格：剑 7 把 / 刀 2 把 / 针 2 把 / 扇 2 把 / 牌 2 把，
## 每格按真实 weapon_id 走战斗同款分型画法（cell 带 "wid"）。
## 每格三联同尺寸挂载 ★1 / ★2 / ★3（升星档：★2 墨描加粗 / ★3 鎏金芯线），一眼核对梯度。
## 默认导出 tests/styles/brutalist_weapon_preview.png 后退出。

const DEFAULT_OUT := "tests/styles/brutalist_weapon_preview.png"
const TIP_LEN := 26.0
const MOUNT_SCALE := 0.8
const COLS := 7
const CELL_W := 130.0
const CELL_H := 80.0
const GRID_X := 30.0
const GRID_Y := 48.0

## 5 行 × 7 列：第一行 = 剑族 7 把全分型（本轮重点），其余按族排布。
const CELLS := [
	{"name": "长剑", "shape": "sword", "element": "metal", "upright": false, "wid": "qingyun_sword"},
	{"name": "飞剑", "shape": "sword", "element": "metal", "upright": false, "wid": "gengjin_feijian"},
	{"name": "青藤剑", "shape": "sword", "element": "wood", "upright": false, "wid": "qingteng_jian"},
	{"name": "桃木剑", "shape": "sword", "element": "wood", "upright": false, "wid": "taomu_jian"},
	{"name": "流火飞剑", "shape": "sword", "element": "fire", "upright": false, "wid": "liuhuo_feijian"},
	{"name": "寒霜剑", "shape": "sword", "element": "water", "upright": false, "wid": "hanshuang_jian"},
	{"name": "崩山剑", "shape": "sword", "element": "earth", "upright": false, "wid": "bengshan_jian"},
	{"name": "烈焰刀", "shape": "saber", "element": "fire", "upright": false, "wid": "chiyan_dao"},
	{"name": "血饮狂刀", "shape": "saber", "element": "fire", "upright": false, "wid": "xueyin_dao"},
	{"name": "暴雨针", "shape": "needles", "element": "metal", "upright": false, "wid": "baoyu_liuhuazhen"},
	{"name": "冰针", "shape": "needles", "element": "water", "upright": false, "wid": "xuanbing_feizhen"},
	{"name": "飞刀", "shape": "dagger", "element": "metal", "upright": false},
	{"name": "手里剑", "shape": "shuriken", "element": "metal", "upright": false},
	{"name": "开山斧", "shape": "axe", "element": "earth", "upright": false},
	{"name": "金蛟剪", "shape": "shears", "element": "metal", "upright": false},
	{"name": "透骨钉", "shape": "nail", "element": "wood", "upright": false},
	{"name": "金锥", "shape": "awl", "element": "metal", "upright": true},
	{"name": "法印", "shape": "seal", "element": "earth", "upright": true},
	{"name": "雷牌", "shape": "tablet", "element": "earth", "upright": true, "wid": "wulei_paizi"},
	{"name": "金霄雷令", "shape": "tablet", "element": "metal", "upright": true, "wid": "jinxiao_leiling"},
	{"name": "天灯", "shape": "lantern", "element": "fire", "upright": true},
	{"name": "战鼓", "shape": "drum", "element": "wood", "upright": true},
	{"name": "裂山铎", "shape": "bell", "element": "earth", "upright": true},
	{"name": "重锤", "shape": "hammer", "element": "water", "upright": true},
	{"name": "重锏", "shape": "mace", "element": "earth", "upright": true},
	{"name": "重盾", "shape": "shield", "element": "earth", "upright": false},
	{"name": "灵符", "shape": "talisman", "element": "wood", "upright": true},
	{"name": "芭蕉扇", "shape": "fan", "element": "water", "upright": false, "wid": "bajiao_fan"},
	{"name": "燎原扇", "shape": "fan", "element": "fire", "upright": false, "wid": "liaoyuan_shan"},
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
	title.text = "新野兽派 · 全武器矩阵（首行=剑族分型；显示旧画法 = 该形未接管，待办）"
	title.position = Vector2(16, 8)
	GameStyle.label(title, 15, Color(0.93, 0.94, 0.98))
	add_child(title)

	var note := Label.new()
	note.text = "平涂色块 · 粗墨描边 · 硬投影 · 零辉光零渐变（每格三联 = ★1 / ★2 / ★3 升星档对照）"
	note.position = Vector2(16, 30)
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

		_mount(s, Vector2(x + 24.0, y + 46.0), MOUNT_SCALE, 1)
		_mount(s, Vector2(x + 65.0, y + 46.0), MOUNT_SCALE, 2)
		_mount(s, Vector2(x + 106.0, y + 46.0), MOUNT_SCALE, 3)


func _mount(s: Dictionary, pos: Vector2, sc: float, st: int) -> void:
	var wr := ProceduralWeaponRenderer.new()
	wr.configure(
		ProceduralWeaponRenderer.shape_from_name(String(s["shape"])),
		String(s["element"]), TIP_LEN, st, bool(s["upright"]), String(s.get("wid", "")))
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
