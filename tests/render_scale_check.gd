extends Node

## 画面清晰度档位判据（SettingsManager 档位链路 + Main 响应）
##   ① 默认出厂为「高清」(&"high")
##   ② 人话名「高清」/「流畅」对齐
##   ③ 循环切档：高清 → 流畅 → 高清
##   ④ 坏值校验：非法值自动回落默认高清
##   ⑤ Main 场景响应：实例化后响应 render_quality 变更，不崩溃、不报空指针
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
	# 触发清晰度变更，验证 _on_setting_changed 和 _apply_render_quality 执行无异常；
	# 并断言档位真的落到世界 SubViewport 尺寸上（2026-10-17 #06 世界级缩放）
	var wvp: SubViewport = main_scene.get_node("WorldContainer/WorldViewport")
	var vp_rect: Vector2 = get_viewport().get_visible_rect().size
	SettingsManager.set_val(&"display", &"render_quality", &"performance", false)
	await get_tree().physics_frame
	_c.check(true, "④切换到流畅档无崩溃")
	var want_perf: Vector2 = Vector2(roundi(vp_rect.x * main_scene.WORLD_SCALE_PERF), roundi(vp_rect.y * main_scene.WORLD_SCALE_PERF))
	_c.equals(Vector2(wvp.size), want_perf, "④流畅档世界视口为半分辨率")
	_c.check(wvp.size_2d_override_stretch, "④size_2d_override_stretch 开启（坐标系锁设计单位）")
	_c.equals(Vector2(wvp.size_2d_override), vp_rect.round(), "④override 尺寸等于设计视口")

	SettingsManager.set_val(&"display", &"render_quality", &"high", false)
	await get_tree().physics_frame
	_c.check(true, "④切换回高清档无崩溃")
	var want_high: Vector2 = Vector2(roundi(vp_rect.x * main_scene.WORLD_SCALE_HIGH), roundi(vp_rect.y * main_scene.WORLD_SCALE_HIGH))
	_c.equals(Vector2(wvp.size), want_high, "④高清档世界视口为原生分辨率")

	main_scene.queue_free()
	await get_tree().physics_frame

	var prefix := "RENDER_SCALE_RESULT"
	if _c.report(prefix):
		get_tree().quit(0)
	else:
		get_tree().quit(1)
