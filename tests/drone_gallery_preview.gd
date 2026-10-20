extends Node2D

## 御灵灵宝画廊调形台（非判据，不参与绿灯）：两排展示 ProceduralDroneRenderer 全部 13 种形态
## 常态 star=1 + 末格灵珑蓄力态，供编辑器/真机直接看形 —— 画得好看不好看是纯眼睛的活，
## 调 ProceduralDroneRenderer 各 _draw_* 的形准与动态节奏时改完重开即可。
## 运行（不能加 --headless，headless 不渲染）：
##   $G --path . res://tests/DroneGalleryPreview.tscn
## 附带 --shot 用户参数时：渲染 2 秒后存一张整图到 /tmp 并退出（供远端出图审形）

const BG_COL := Color(0.07, 0.10, 0.16)

const KINDS: Array = [
	["灵蝶", ProceduralDroneRenderer.DroneKind.LINGDIE],
	["寒泉玉莲", ProceduralDroneRenderer.DroneKind.HANQUAN_YULIAN],
	["混元钟", ProceduralDroneRenderer.DroneKind.HUNYUAN_ZHONG],
	["昊金轮", ProceduralDroneRenderer.DroneKind.HAOJIN_LUN],
	["离火鸦", ProceduralDroneRenderer.DroneKind.LIHUO_YA],
	["玄武佩", ProceduralDroneRenderer.DroneKind.XUANWU_PEI],
	["灵珑·常态", ProceduralDroneRenderer.DroneKind.YUAN_LING],
	["金鸣铃", ProceduralDroneRenderer.DroneKind.JINMING_LING],
	["木灵偶", ProceduralDroneRenderer.DroneKind.MULING_OU],
	["冰魄珠", ProceduralDroneRenderer.DroneKind.BINGPO_ZHU],
	["赤炎萤", ProceduralDroneRenderer.DroneKind.CHIYAN_YING],
	["土灵石", ProceduralDroneRenderer.DroneKind.TULING_SHI],
	["剑灵", ProceduralDroneRenderer.DroneKind.JIAN_LING],
	["灵珑·蓄力", ProceduralDroneRenderer.DroneKind.YUAN_LING],
]

var _t: float = 0.0
var _charge_cell: ProceduralDroneRenderer = null
var _shot_frames: int = -1

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = BG_COL
	bg.size = Vector2(960, 540)
	add_child(bg)

	var title := Label.new()
	title.text = "御灵灵宝画廊（ProceduralDroneRenderer 全 13 形态）"
	title.position = Vector2(40, 16)
	GameStyle.label(title, 14, GameStyle.PAPER, 0, GameStyle.INK, true)
	add_child(title)

	for i in range(KINDS.size()):
		var col := i % 7
		var row: int = int(float(i) / 7.0)
		var pos := Vector2(90 + col * 130, 180 + row * 220)
		var d := ProceduralDroneRenderer.new()
		d.kind = KINDS[i][1]
		d.position = pos
		add_child(d)
		if i == KINDS.size() - 1:
			_charge_cell = d
		var lbl := Label.new()
		lbl.text = KINDS[i][0]
		lbl.position = pos + Vector2(-34, 34)
		GameStyle.label(lbl, 11, GameStyle.PAPER_DIM)
		add_child(lbl)

	if DisplayServer.get_name() == "headless":
		print("DroneGalleryPreview: headless 无渲染意义，直接退出")
		get_tree().quit(0)
		return
	if "--shot" in OS.get_cmdline_user_args():
		_shot_frames = 120

func _process(delta: float) -> void:
	_t += delta
	if _charge_cell != null:
		_charge_cell.charge_ratio = 0.5 + 0.5 * sin(_t * 2.5)
	if _shot_frames > 0:
		_shot_frames -= 1
		if _shot_frames == 0:
			var img := get_viewport().get_texture().get_image()
			img.save_png("/tmp/drone_gallery_preview.png")
			print("SAVED: /tmp/drone_gallery_preview.png")
			get_tree().quit(0)
