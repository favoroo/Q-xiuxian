extends Node

## 新手指南弹窗预览（非判据）：截几页看排版。运行（不能加 --headless）：
##   $G --path . res://tools/TutorialDialogPreview.tscn
## 产物 /tmp/tutorial_shots/preview_p<N>.png

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("/tmp/tutorial_shots")
	var dlg: TutorialDialog = load("res://scenes/ui/TutorialDialog.tscn").instantiate()
	get_tree().root.add_child(dlg)
	await get_tree().process_frame
	dlg.open()
	for p in [1, 3, 5]:
		dlg._go_page(p)
		await get_tree().create_timer(0.4).timeout
		await get_tree().process_frame
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png("/tmp/tutorial_shots/preview_p%d.png" % (p + 1))
		print("PREVIEW saved page ", p + 1)
	print("PREVIEW_DONE")
	get_tree().quit(0)
