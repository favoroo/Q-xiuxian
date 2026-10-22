extends Node2D

## 虹霓炫彩皮肤验收抓拍（非判据现场工具）
## 运行（必须带视口，严禁 --headless）：
##   $G --path . res://tests/ChromaSkinPreview.tscn
## 产物：tests/inspect/chroma_skin_preview.png
## 布局：3 位角色 × 4 个时间相位，验证「同一轮廓只换色 + 色相流转」；
##       底部一排为普通皮肤对照组（应保持静态）。

const OUT_PATH := "res://tests/inspect/chroma_skin_preview.png"
const CIDS: Array[String] = ["jianchi", "fuzhen", "kuangzhan"]
const PHASES: Array[float] = [0.0, 1.75, 3.5, 5.25]  # 7s 周期的 0/90/180/270 度

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.055, 0.065, 0.095)
	bg.size = Vector2(960, 540)
	add_child(bg)

	for r in range(CIDS.size()):
		var cid := CIDS[r]
		for c in range(PHASES.size()):
			var view := ProceduralCultivatorView.new()
			view.position = Vector2(92 + c * 132.0, 120 + r * 140.0)
			view.scale = Vector2(1.3, 1.3)
			add_child(view)
			view.setup_character_id(cid, 5)
			var rr: HollowKnightCultivatorRenderer = view.renderer
			rr._time = PHASES[c]
			rr._on_before_redraw()
			rr.queue_redraw()

			var lb := Label.new()
			lb.text = "%ds" % int(PHASES[c])
			lb.add_theme_font_override("font", GameStyle.body_font())
			lb.add_theme_font_size_override("font_size", 11)
			lb.add_theme_color_override("font_color", Color(0.72, 0.78, 0.9))
			lb.position = view.position + Vector2(-10, 52)
			add_child(lb)

		var name_lb := Label.new()
		name_lb.text = String(CultivatorData.get_def(cid).get("name", cid))
		name_lb.add_theme_font_override("font", GameStyle.body_font())
		name_lb.add_theme_font_size_override("font_size", 13)
		name_lb.add_theme_color_override("font_color", Color(0.65, 0.72, 0.85))
		name_lb.position = Vector2(10, 108 + r * 140.0)
		add_child(name_lb)

	# 对照组：同一角色 原色 / 鎏金 / 虹霓
	var controls: Array = [["原色", -1], ["鎏金", 4], ["虹霓", 5]]
	for i in range(controls.size()):
		var view2 := ProceduralCultivatorView.new()
		view2.position = Vector2(600 + i * 110.0, 452)
		view2.scale = Vector2(1.0, 1.0)
		add_child(view2)
		view2.setup_character_id("jianchi", int(controls[i][1]))
		var lb2 := Label.new()
		lb2.text = String(controls[i][0])
		lb2.add_theme_font_override("font", GameStyle.body_font())
		lb2.add_theme_font_size_override("font_size", 11)
		lb2.add_theme_color_override("font_color", Color(0.72, 0.78, 0.9))
		lb2.position = view2.position + Vector2(-10, 42)
		add_child(lb2)

	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://tests/inspect")
	img.save_png(OUT_PATH)
	print("CHROMA_PREVIEW_SAVED: %s" % OUT_PATH)
	get_tree().quit()
