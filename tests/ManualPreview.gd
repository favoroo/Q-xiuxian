extends Node

## 非判据现场工具：渲染教程手册七个分页并截图到项目根 tmp_manual_tab*.png，供目检排版。
## 用法：$G --headless --path . res://tests/ManualPreview.tscn

func _ready() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(960, 540)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)

	var manual := ManualDialog.new()
	vp.add_child(manual)
	manual.open()

	for _i in range(6):
		await get_tree().process_frame

	var names := ["weapons", "items", "upgrades", "pets", "cultivators", "enemies", "advanced"]
	for tab in range(7):
		manual._switch_tab(tab)
		manual._build_page(tab)
		for _i in range(6):
			await get_tree().process_frame
		var tex := vp.get_texture()
		if tex != null:
			var img := tex.get_image()
			if img != null:
				img.save_png("res://tmp_manual_tab%d_%s.png" % [tab, names[tab]])
				print("SAVED tmp_manual_tab%d_%s.png" % [tab, names[tab]])

	get_tree().quit(0)
