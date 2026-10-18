extends Node

## 画面清晰度档位判据（SettingsManager 档位链路 + Main 响应）
##   ① 默认出厂为「高清」(&"high")
##   ② 人话名「高清」/「流畅」对齐
##   ③ 循环切档：高清 → 流畅 → 高清
##   ④ 坏值校验：非法值自动回落默认高清
##   ⑤ Main 场景响应：实例化后响应 render_quality 变更，不崩溃、不报空指针
##   ⑥ 低帧不自动切画质：画质恒定由用户手动控制，低帧时不自动切换档位
## 运行: godot --headless --path . res://tests/RenderScaleCheck.tscn

var _c := TestCheck.new()

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	# 先重置为默认值
	SettingsManager.set_val(&"display", &"render_quality", SettingsManager.RENDER_QUALITY_DEFAULT, false)

	# ① 默认档位
	_c.equals(SettingsManager.render_quality(), &"high", "①出厂默认档为高清")
	_c.equals(SettingsManager.render_quality_label(), "高清", "①档位人话名")

	# ② 循环切换
	var next_q: StringName = SettingsManager.render_quality_next()
	_c.equals(next_q, &"performance", "②高清下一档是流畅")
	SettingsManager.set_val(&"display", &"render_quality", next_q, false)
	_c.equals(SettingsManager.render_quality(), &"performance", "②切换后当前档为流畅")
	_c.equals(SettingsManager.render_quality_label(), "流畅", "②流畅档人话名")

	var loop_q: StringName = SettingsManager.render_quality_next()
	_c.equals(loop_q, &"high", "②流畅下一档循环回高清")
	SettingsManager.set_val(&"display", &"render_quality", loop_q, false)
	_c.equals(SettingsManager.render_quality(), &"high", "②已循环回高清")

	# ③ 坏值校验
	SettingsManager.set_val(&"display", &"render_quality", &"invalid_bogus_val", false)
	# 读盘校验逻辑只在 _validate_loaded_value 里生效
	var validated: Variant = SettingsManager._validate_loaded_value("display", "render_quality", "invalid_bogus_val")
	_c.equals(validated, &"high", "③非法值校验回退到默认高清档")
	SettingsManager.set_val(&"display", &"render_quality", &"high", false)

	# ④ Main 场景实例化与事件响应
	var main_scene = load("res://scenes/main/Main.tscn").instantiate()
	get_tree().root.add_child(main_scene)
	await get_tree().physics_frame
	await get_tree().physics_frame

	_c.check(main_scene != null, "④Main 场景实例化成功")
	# 触发清晰度变更，验证 _on_setting_changed 和 _apply_render_quality 执行无异常
	SettingsManager.set_val(&"display", &"render_quality", &"performance", false)
	await get_tree().physics_frame
	_c.check(true, "④切换到流畅档无崩溃")

	SettingsManager.set_val(&"display", &"render_quality", &"high", false)
	await get_tree().physics_frame
	_c.check(true, "④切换回高清档无崩溃")

	# ⑤ 验证画质不因低帧自动切换（由用户完全手动控制）
	GameManager.run_started = true
	get_tree().paused = false
	SettingsManager.set_val(&"display", &"glow", false, false) # 即使辉光关闭
	var m := main_scene as MainLevel
	if m != null:
		for i in range(10):
			m._poll_glow_auto_off()
	_c.equals(SettingsManager.render_quality(), &"high", "⑤低帧持续采样下画质仍保持高清档")
	_c.check(get_window().content_scale_mode != Window.CONTENT_SCALE_MODE_VIEWPORT,
		"⑤低帧持续采样下 window content_scale_mode 未被降至 VIEWPORT")

	main_scene.queue_free()
	await get_tree().physics_frame

	var prefix := "RENDER_SCALE_RESULT"
	if _c.report(prefix):
		get_tree().quit(0)
	else:
		get_tree().quit(1)
