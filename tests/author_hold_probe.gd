extends Node

## 临时探针（不纳入回归基线）：验证设置徽章长按入口的接线与消费逻辑。
## headless 无鼠标，倒计时逐秒 hover 路径没法全跑，这里直接驱动回调验证关键分支：
## 1. 长按完成 → 作者模式切换 + _settings_hold_fired 置位
## 2. 紧随的 pressed 被 _on_top_set_pressed 吃掉（不开设置、不计连点）
## 3. 普通点按仍走连点计数，且与长按互不叠加

func _ready() -> void:
	var menu: Node = (load("res://scenes/ui/StartMenu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await get_tree().process_frame
	var stat := {"n": 0, "fail": 0}
	var ok := func(cond: bool, msg: String) -> void:
		stat.n += 1
		if not cond:
			stat.fail += 1
		print(("PASS " if cond else "FAIL ") + msg)

	# 前置：徽章已创建
	var btn: Button = menu.get("_top_set_btn")
	await ok.call(btn != null, "设置徽章已创建")

	# 1. 直接触发长按完成回调：应切换作者模式并置位消费标记
	var orig: bool = GameManager.author_mode
	menu._on_settings_hold_complete()
	await ok.call(GameManager.author_mode == (not orig), "长按完成切换作者模式")
	await ok.call(menu.get("_settings_hold_fired") == true, "长按完成置位松手消费标记")

	# 2. 松手那一下 pressed：被吃掉（不开设置、连点不涨）
	var settings_opened := {"v": false}
	menu.settings_requested.connect(func(): settings_opened.v = true)
	menu._on_top_set_pressed()
	await ok.call(settings_opened.v == false, "长按后的松手不开设置")
	await ok.call(menu.get("_settings_hold_fired") == false, "消费标记一次性清除")

	# 3. 普通单下点按：开设置（这是设置按钮的本职），但不切作者模式
	menu._on_top_set_pressed()
	await ok.call(settings_opened.v == true, "普通单下点按开设置")
	await ok.call(GameManager.author_mode == (not orig), "连点第 1 下不切作者模式")

	# 4. 连点 4 下（不满 5）→ 长按完成：切换作者模式并把连点清零，
	#    之后第 1 下点按回到计数 1（若没清零会顶成第 5 连点误切换）
	menu.set("_author_taps", 0)   # 隔离上一段遗留计数（探针瞬间连打，真实窗口已过）
	for _i in range(4):
		menu._on_top_set_pressed()
	var before: bool = GameManager.author_mode
	menu._on_settings_hold_complete()
	await ok.call(GameManager.author_mode == (not before), "长按完成切换作者模式")
	menu._on_top_set_pressed()   # 这一下是长按自己的松手 → 被吃掉
	settings_opened.v = false
	menu._on_top_set_pressed()   # 真正的新点按：计数 1 → 开设置、不切模式
	await ok.call(GameManager.author_mode == (not before), "长按后连点从头计数（第 1 下不切模式）")
	await ok.call(settings_opened.v == true, "长按后的新点按正常开设置")

	# 复位：探针不改会话外的任何状态
	GameManager.set_author_mode(orig)
	var all_pass: bool = stat.fail == 0
	print("HOLD_PROBE_RESULT: %s（%d 项）" % ["ALL PASS" if all_pass else "HAS FAIL", stat.n])
	get_tree().quit(0 if all_pass else 1)
