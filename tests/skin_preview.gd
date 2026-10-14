extends Node2D

## 换色皮肤预览（非判据现场工具）：3 位代表角色 × (原色 + 6 套主题皮肤) 矩阵抓拍
## 运行（必须带视口，严禁 --headless）：
##   $G --path . res://tests/SkinPreview.tscn
## 产物：tests/inspect/skin_preview.png

const OUT_PATH := "res://tests/inspect/skin_preview.png"
const CIDS: Array[String] = ["jianchi", "fuzhen", "kuangzhan"]

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.10, 0.16)
	bg.size = Vector2(960, 540)
	add_child(bg)

	for r in range(CIDS.size()):
		var cid := CIDS[r]
		for c in range(-1, SkinData.count()):
			var view := ProceduralCultivatorView.new()
			view.position = Vector2(78 + (c + 1) * 118.0, 132 + r * 172.0)
			view.scale = Vector2(1.45, 1.45)
			add_child(view)
			view.setup_character_id(cid, c)

			var lb := Label.new()
			lb.text = "原色" if c == -1 else String(SkinData.get_theme(c).get("name", ""))
			lb.add_theme_font_override("font", GameStyle.body_font())
			lb.add_theme_font_size_override("font_size", 14)
			lb.add_theme_color_override("font_color", Color(0.92, 0.93, 0.96))
			lb.position = view.position + Vector2(-16, 58)
			add_child(lb)

		var name_lb := Label.new()
		name_lb.text = String(CultivatorData.get_def(cid).get("name", cid))
		name_lb.add_theme_font_override("font", GameStyle.body_font())
		name_lb.add_theme_font_size_override("font_size", 14)
		name_lb.add_theme_color_override("font_color", Color(0.65, 0.72, 0.85))
		name_lb.position = Vector2(8, 120 + r * 172.0)
		add_child(name_lb)

	# 等两帧让渲染器真正画完再抓拍
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://tests/inspect")
	img.save_png(OUT_PATH)
	print("SKIN_PREVIEW_SAVED: %s" % OUT_PATH)
	get_tree().quit()
