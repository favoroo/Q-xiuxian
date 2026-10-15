extends Control

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = GameStyle.INK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var dlg: SettingsDialog = preload("res://scenes/ui/SettingsDialog.tscn").instantiate()
	add_child(dlg)
	dlg.open()
	dlg.switch_tab(3) # 切到「其他」页签

	# 等待两帧渲染稳定后截屏
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var img := get_viewport().get_texture().get_image()
	img.save_png("/tmp/settings_other_preview.png")
	print("SAVED PREVIEW TO /tmp/settings_other_preview.png")

	# 滚到底部查看完整卡片布局
	var sys_scroll: ScrollContainer = dlg._pages[3] as ScrollContainer
	if sys_scroll:
		sys_scroll.scroll_vertical = 200
		await get_tree().process_frame
		await get_tree().process_frame
		var img_scrolled := get_viewport().get_texture().get_image()
		img_scrolled.save_png("/tmp/settings_other_scrolled_preview.png")
		print("SAVED PREVIEW TO /tmp/settings_other_scrolled_preview.png")
		sys_scroll.scroll_vertical = 0

	# 再测试打开更新历史弹窗
	dlg._open_changelog()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var img2 := get_viewport().get_texture().get_image()
	img2.save_png("/tmp/changelog_preview.png")
	print("SAVED PREVIEW TO /tmp/changelog_preview.png")

	get_tree().quit(0)
