extends Node2D

## 皮肤系列对照预览（非判据现场工具）：重点验「墨煞 vs 虹霓」这两套墨黑底系列
## 是否真能分辨 —— 渲染 2 角色 × 4 时间相位 × 2 系列，大尺寸并排。
## 运行（必须带视口，严禁 --headless）：
##   $G --path . res://tests/SkinSeriesCompare.tscn
## 产物：tests/inspect/skin_series_compare.png

const OUT_PATH := "res://tests/inspect/skin_series_compare.png"
const CIDS: Array[String] = ["jianchi", "bawang"]
const SERIES: Array[int] = [3, 5]   # 3=墨煞 5=虹霓
const PHASES: Array[float] = [0.0, 1.75, 3.5, 5.25]

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.11)
	bg.size = Vector2(960, 540)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	for r in range(CIDS.size()):
		var cid := CIDS[r]
		for c in range(SERIES.size()):
			var skin_idx := SERIES[c]
			for p in range(PHASES.size()):
				var view := ProceduralCultivatorView.new()
				# 行 = 角色 × 系列（2 角色 × 2 系列 = 4 行），列 = 时间相位
				var row := r * SERIES.size() + c
				view.position = Vector2(130 + p * 205.0, 96 + row * 132.0)
				view.scale = Vector2(1.15, 1.15)
				add_child(view)
				view.setup_character_id(cid, skin_idx)
				# 把渲染器时间钉到指定相位，抓不同时刻的样子
				var rr = view.get("renderer")
				if rr != null:
					rr._time = PHASES[p]
					rr._on_before_redraw()
					rr.queue_redraw()
				var lb := Label.new()
				lb.text = "%s · %s · t=%.1fs" % [
					String(CultivatorData.get_def(cid).get("name", cid)),
					String(SkinData.get_theme(skin_idx).get("name", "")), PHASES[p]]
				lb.add_theme_font_override("font", GameStyle.body_font())
				lb.add_theme_font_size_override("font_size", 12)
				lb.add_theme_color_override("font_color", Color(0.92, 0.93, 0.96))
				lb.position = view.position + Vector2(-30, 54)
				add_child(lb)

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://tests/inspect")
	img.save_png(OUT_PATH)
	print("SKIN_SERIES_COMPARE_SAVED: %s" % OUT_PATH)
	get_tree().quit()
