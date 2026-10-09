extends Node

## 非判据现场工具：渲染教程手册五个分页并截图到项目根 tmp_manual_tab*.png，供目检排版。
## 用法（勿加 --headless）：$G --path . res://tests/ManualPreview.tscn

func _ready() -> void:
	var manual := ManualDialog.new()
	add_child(manual)
	manual.open()
	# 等两帧：一帧容器布局，一帧淡入动画
	await get_tree().process_frame
	await get_tree().process_frame
	for tab in range(5):
		manual._switch_tab(tab)
		await get_tree().process_frame
		await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://tmp_manual_tab%d.png" % tab)
		print("SAVED tmp_manual_tab%d.png" % tab)
	get_tree().quit()
