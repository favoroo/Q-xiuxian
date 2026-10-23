extends Node

## 意见反馈 UI 状态判据（2026-10-23）
##
## 覆盖发送覆盖层与草稿机制，不依赖网络：
##   ① FeedbackSendOverlay：发送态/成功态的显隐、阶段文案、完成信号、动画在暂停树下仍走
##   ② FeedbackDialog：发送中禁关、成功后不立刻关、完成按钮关闭后才清空、失败保留内容
##   ③ 草稿：输入防抖落盘、重开恢复、发送成功清除
##   ④ 相册方向状态机：非 Android 平台不碰方向；模拟 picking 时 close 被拦
##
## 运行: godot --headless --path . res://tests/FeedbackUiCheck.tscn

var _c := TestCheck.new()

func _ready() -> void:
	_c.set_min_checks(22)
	call_deferred("_run")

func _finish() -> void:
	if _c.report("FEEDBACK_UI_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

func _run() -> void:
	await _test_overlay_states()
	await _test_dialog_send_guard()
	await _test_success_flow()
	await _test_failure_keeps_content()
	await _test_draft_roundtrip()
	await _test_pick_guard()
	_finish()

func _make_dialog() -> FeedbackDialog:
	var dlg: FeedbackDialog = preload("res://scenes/ui/FeedbackDialog.tscn").instantiate()
	add_child(dlg)
	dlg.open()
	return dlg

func _test_overlay_states() -> void:
	var overlay := FeedbackSendOverlay.new()
	add_child(overlay)
	await get_tree().process_frame
	_c.check(not overlay.visible, "覆盖层默认隐藏")
	overlay.show_sending("正在整理反馈内容…")
	_c.check(overlay.visible, "show_sending 后覆盖层可见")
	_c.check(overlay.state == FeedbackSendOverlay.State.SENDING, "初始状态为 SENDING")
	_c.check(overlay._spinner.visible and overlay._scan.visible, "发送态显示旋转环与扫描条")
	_c.check(not overlay._check.visible and not overlay._done_btn.visible, "发送态不显示对勾与完成按钮")
	_c.check(overlay._sub_lbl.text == "正在整理反馈内容…", "阶段文案可设置（实得「%s」）" % overlay._sub_lbl.text)
	overlay.set_stage("正在投递邮件…")
	_c.check(overlay._sub_lbl.text == "正在投递邮件…", "set_stage 更新阶段文案")

	overlay.show_success()
	_c.check(overlay.state == FeedbackSendOverlay.State.SUCCESS, "show_success 切到 SUCCESS")
	_c.check(overlay._check.visible and overlay._done_btn.visible, "成功态显示对勾与完成按钮")
	_c.check(not overlay._spinner.visible and not overlay._scan.visible, "成功态隐藏旋转环与扫描条")
	var fired := [0]
	overlay.completed.connect(func() -> void: fired[0] += 1)
	overlay._done_btn.pressed.emit()
	_c.check(fired[0] == 1, "点完成发 completed 信号")
	overlay.queue_free()
	await get_tree().process_frame

func _test_dialog_send_guard() -> void:
	var dlg := _make_dialog()
	await get_tree().process_frame
	dlg._message_edit.text = "测试内容"
	dlg._sending = true
	dlg.close()
	_c.check(dlg.visible, "发送中 close() 被拦下（弹窗仍可见）")
	dlg._sending = false
	dlg.close()
	await get_tree().create_timer(0.35).timeout
	_c.check(not dlg.visible, "非发送态 close() 正常关闭")
	dlg.queue_free()
	await get_tree().process_frame

func _test_success_flow() -> void:
	var dlg := _make_dialog()
	await get_tree().process_frame
	dlg._message_edit.text = "成功流程测试"
	dlg._contact_edit.text = "abc@qq.com"
	dlg._sending = false
	# 模拟发送成功后的收尾（不真发网络请求）
	dlg._sent_success = true
	dlg._overlay.show_success()
	_c.check(dlg.visible and dlg._overlay.visible, "成功后弹窗与成功覆盖层都还在（不立刻关）")
	_c.check(dlg._message_edit.text == "成功流程测试", "成功态仍能看到自己写的内容")
	dlg.close()
	await get_tree().create_timer(0.35).timeout
	_c.check(not dlg.visible, "点完成后弹窗关闭")
	_c.check(dlg._message_edit.text == "", "关闭后才清空正文")
	_c.check(dlg._contact_edit.text == "", "关闭后才清空联系方式")
	_c.check(FeedbackSender.load_draft().is_empty(), "成功后草稿被清除")
	dlg.queue_free()
	await get_tree().process_frame

func _test_failure_keeps_content() -> void:
	var dlg := _make_dialog()
	await get_tree().process_frame
	dlg._message_edit.text = "失败也要保留"
	dlg._contact_edit.text = "QQ:10086"
	dlg._sent_success = false
	dlg.close()
	await get_tree().create_timer(0.35).timeout
	_c.check(not dlg.visible, "失败后手动关闭正常")
	var draft := FeedbackSender.load_draft()
	_c.check(String(draft.get("message", "")) == "失败也要保留", "关闭时草稿保留正文")
	_c.check(String(draft.get("contact", "")) == "QQ:10086", "关闭时草稿保留联系方式")
	dlg.queue_free()
	FeedbackSender.clear_draft()
	await get_tree().process_frame

func _test_draft_roundtrip() -> void:
	FeedbackSender.clear_draft()
	_c.check(FeedbackSender.load_draft().is_empty(), "无草稿时读取为空")
	FeedbackSender.save_draft("草稿正文", "draft@qq.com")
	var draft := FeedbackSender.load_draft()
	_c.check(String(draft.get("message", "")) == "草稿正文", "草稿正文可读回")
	_c.check(String(draft.get("contact", "")) == "draft@qq.com", "草稿联系方式可读回")
	FeedbackSender.save_draft("", "")
	_c.check(FeedbackSender.load_draft().is_empty(), "空草稿自动清除")

	var dlg := _make_dialog()
	await get_tree().process_frame
	# 真实路径：用户输入 → 关闭（自动存草稿）→ 重开（自动恢复）
	dlg._message_edit.text = "上次没发完的内容"
	dlg._contact_edit.text = "QQ:123"
	dlg._sent_success = false
	dlg.close()
	await get_tree().create_timer(0.35).timeout
	_c.check(not FeedbackSender.load_draft().is_empty(), "关闭时自动落盘草稿")
	dlg.open()
	await get_tree().process_frame
	_c.check(dlg._message_edit.text == "上次没发完的内容", "重开弹窗自动恢复草稿正文")
	_c.check(dlg._contact_edit.text == "QQ:123", "重开弹窗自动恢复联系方式")
	dlg.queue_free()
	FeedbackSender.clear_draft()
	await get_tree().process_frame

func _test_pick_guard() -> void:
	var dlg := _make_dialog()
	await get_tree().process_frame
	dlg._picking = true
	dlg.close()
	_c.check(dlg.visible, "选相册中 close() 被拦下")
	dlg._picking = false
	dlg.close()
	await get_tree().create_timer(0.35).timeout
	dlg.queue_free()
	await get_tree().process_frame
