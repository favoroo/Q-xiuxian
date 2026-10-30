extends Control

## 战绩·角色页现场预览（非判据）：出图 /tmp/career_dialog_preview.png 供人工看样式。
## 运行: /Applications/Godot.app/Contents/MacOS/Godot --path . res://tests/CareerDialogPreview.tscn
##       （非判据现场预览，不要加 --headless）

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = GameStyle.INK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 造样本：默认 4 名已解锁，覆盖「两档都有数 / 只打普通 / 未破境 / 未解锁」四种卡面状态
	GameManager.unlocked_cultivators = AchievementData.DEFAULT_CULTIVATORS.duplicate()
	GameManager.career_stats["total_runs"] = 42
	GameManager.career_stats["total_kills"] = 3712
	GameManager.career_stats["best_wave"] = 34
	GameManager.career_stats["best_danger_cleared"] = 1
	GameManager.cultivator_records = {
		"shiyue": {"runs": 26, "best_wave": 34, "best_kills": 1840, "best_wave_by_danger": [34, 27]},
		"jianchi": {"runs": 9, "best_wave": 24, "best_kills": 730, "best_wave_by_danger": [24, 0]},
		"fuzhen": {"runs": 5, "best_wave": 18, "best_kills": 402, "best_wave_by_danger": [18, 0]},
		"leifa": {"runs": 0, "best_wave": 0, "best_kills": 0, "best_wave_by_danger": [0, 0]},
	}
	GameManager.cultivator_best_danger = {"shiyue": 1, "jianchi": 0}

	var dlg := CareerDialog.new()
	add_child(dlg)
	dlg.open()
	dlg.switch_tab(1)
	await get_tree().create_timer(0.35).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("/tmp/career_dialog_preview.png")
	print("SAVED PREVIEW TO /tmp/career_dialog_preview.png")
	get_tree().quit(0)