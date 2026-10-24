extends Control

## 新野兽派御灵重绘【13 形态 + 灵珑状态矩阵预览】（非判据，必须开窗跑）
##   $G --path . res://tests/brutalist_drone_preview.tscn -- --export [-- --out <path>]
##
## 直接实例化战斗同款 ProceduralDroneRenderer：13 种 DroneKind 各一格，
## 另加灵珑巡航 / 蓄力 / 濒死 / 出场状态格验证硬边状态演出。
## 每格：大=放大看形（1.35），小=实战尺寸（0.55，与 SunOrb 挂载一致）。
## 默认导出 tests/styles/brutalist_drone_preview.png 后退出。

const DEFAULT_OUT := "tests/styles/brutalist_drone_preview.png"
const STAR := 2
const BIG_SCALE := 1.35
const COLS := 4
const CELL_W := 226.0
const CELL_H := 112.0
const GRID_X := 26.0
const GRID_Y := 52.0

## 13 形态 + 3 个灵珑状态格（speed/hp/charge/spawn 为灵珑宿主灌入口模拟）
const CELLS := [
	{"name": "灵蝶", "kind": ProceduralDroneRenderer.DroneKind.LINGDIE},
	{"name": "寒泉玉莲", "kind": ProceduralDroneRenderer.DroneKind.HANQUAN_YULIAN},
	{"name": "混元钟", "kind": ProceduralDroneRenderer.DroneKind.HUNYUAN_ZHONG},
	{"name": "昊金轮", "kind": ProceduralDroneRenderer.DroneKind.HAOJIN_LUN},
	{"name": "离火鸦", "kind": ProceduralDroneRenderer.DroneKind.LIHUO_YA},
	{"name": "玄武佩", "kind": ProceduralDroneRenderer.DroneKind.XUANWU_PEI},
	{"name": "金鸣铃", "kind": ProceduralDroneRenderer.DroneKind.JINMING_LING},
	{"name": "木灵偶", "kind": ProceduralDroneRenderer.DroneKind.MULING_OU},
	{"name": "冰魄珠", "kind": ProceduralDroneRenderer.DroneKind.BINGPO_ZHU},
	{"name": "赤炎萤", "kind": ProceduralDroneRenderer.DroneKind.CHIYAN_YING},
	{"name": "土灵石", "kind": ProceduralDroneRenderer.DroneKind.TULING_SHI},
	{"name": "剑灵", "kind": ProceduralDroneRenderer.DroneKind.JIAN_LING},
	{"name": "灵珑·巡航", "kind": ProceduralDroneRenderer.DroneKind.YUAN_LING, "speed": 0.55},
	{"name": "灵珑·蓄力", "kind": ProceduralDroneRenderer.DroneKind.YUAN_LING, "charge": 0.9},
	{"name": "灵珑·濒死", "kind": ProceduralDroneRenderer.DroneKind.YUAN_LING, "hp": 0.15},
	{"name": "灵珑·出场", "kind": ProceduralDroneRenderer.DroneKind.YUAN_LING, "spawn": 0.85},
]


func _ready() -> void:
	custom_minimum_size = Vector2(960, 540)
	size = Vector2(960, 540)
	_build_ui()
	# 等几帧让动画相位展开（振翅/旋转/呼吸都走到可见位），再抓屏
	for i in range(8):
		await get_tree().process_frame
	_export_image()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.10)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "新野兽派 · 御灵 13 形态矩阵（平涂色块 · 粗墨描边 · 硬投影 · 零辉光零渐变）"
	title.position = Vector2(16, 8)
	GameStyle.label(title, 15, Color(0.93, 0.94, 0.98))
	add_child(title)

	var note := Label.new()
	note.text = "每格：大=放大看形（1.35） 小=实战尺寸（0.55）；星级一律 ★2（撞色方钉口径）"
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

		_mount(s, Vector2(x + CELL_W * 0.62, y + 56.0), BIG_SCALE)
		_mount(s, Vector2(x + 24.0, y + 90.0), 0.55)


func _mount(s: Dictionary, pos: Vector2, sc: float) -> void:
	var d := ProceduralDroneRenderer.new()
	d.kind = s["kind"]
	d.star = STAR
	d.speed_ratio = float(s.get("speed", 0.0))
	d.hp_ratio = float(s.get("hp", 1.0))
	d.charge_ratio = float(s.get("charge", 0.0))
	d.spawn_glow = float(s.get("spawn", 0.0))
	d.position = pos
	d.scale = Vector2.ONE * sc
	add_child(d)
	# 冻结动画相位：抓屏时机受窗口启动抖动影响，各形态统一钉在 0.40s
	# （振翅全开 / 轮盘转过一档 / 铃摆可见），保证导出图逐次可比
	d._anim_time = 0.40
	d.set_process(false)


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
			print("[BrutalistDronePreview] 导出 %s" % out_path)
	print("BRUTALIST_DRONE_PREVIEW_DONE")
	get_tree().quit(0)
