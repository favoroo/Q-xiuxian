extends Control

## 意见反馈弹窗现场预览（非判据）：出图到 /tmp/feedback_preview*.png 供人工看样式。
## 运行: godot --path . res://tests/FeedbackPreview.tscn （不要加 --headless）

func _ready() -> void:
	# 预览脚本会触发草稿自动保存；开跑前先清干净，避免把测试文案留在真机档里
	FeedbackSender.clear_draft()
	var bg := ColorRect.new()
	bg.color = GameStyle.INK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var dlg: FeedbackDialog = preload("res://scenes/ui/FeedbackDialog.tscn").instantiate()
	add_child(dlg)
	dlg.open()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var img := get_viewport().get_texture().get_image()
	img.save_png("/tmp/feedback_preview.png")
	print("SAVED PREVIEW TO /tmp/feedback_preview.png")

	# 填一段文案 + 造一张假截图，看有内容时的排布
	dlg._message_edit.text = "第 8 波打 BOSS 时，画面右边偶尔会闪一下黑条，重开一局又没有了。"
	dlg._on_message_changed()
	dlg._contact_edit.text = "12345678@qq.com"
	var test_img := Image.create(1200, 675, false, Image.FORMAT_RGB8)
	test_img.fill(Color(0.15, 0.35, 0.55))
	dlg._shot_bytes = test_img.save_jpg_to_buffer(0.85)
	dlg._shot_name = FeedbackSender.build_attachment_filename()
	dlg._shot_mime = "image/jpeg"
	dlg._shot_size = dlg._shot_bytes.size()
	dlg._thumb.texture = ImageTexture.create_from_image(test_img)
	dlg._thumb_frame.visible = true
	dlg._remove_btn.visible = true
	dlg._shot_info.text = "%s · 1200×675 · %s" % [dlg._shot_name, Version.format_bytes(dlg._shot_size)]
	dlg._shot_info.add_theme_color_override("font_color", GameStyle.PAPER)
	await get_tree().process_frame
	await get_tree().process_frame
	var img2 := get_viewport().get_texture().get_image()
	img2.save_png("/tmp/feedback_preview_filled.png")
	print("SAVED PREVIEW TO /tmp/feedback_preview_filled.png")

	# 发送中覆盖层（旋转环 + 扫描条 + 阶段文案）
	dlg._overlay.show_sending("正在上传截图…")
	await get_tree().create_timer(0.5).timeout
	var img3 := get_viewport().get_texture().get_image()
	img3.save_png("/tmp/feedback_preview_sending.png")
	print("SAVED PREVIEW TO /tmp/feedback_preview_sending.png")

	# 成功态（大对勾 + 完成按钮）
	dlg._overlay.show_success()
	await get_tree().create_timer(0.6).timeout
	var img4 := get_viewport().get_texture().get_image()
	img4.save_png("/tmp/feedback_preview_success.png")
	print("SAVED PREVIEW TO /tmp/feedback_preview_success.png")

	FeedbackSender.clear_draft()
	get_tree().quit(0)
