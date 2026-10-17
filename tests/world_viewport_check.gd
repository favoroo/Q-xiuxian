extends Node

## 世界视口（SubViewport 化）判据（2026-10-17 #06）：
##   ① 结构不变量：World 在位、UILayer 仍是 Main 直接子节点、SubViewport 输入全关
##      （handle_input_locally=false + gui_disable_input：输入只走根 viewport 的 UILayer）
##   ② k 映射：设置档 high=1.0 / performance=0.5；手动改画质清自动 override
##   ③ 尺寸同步：SubViewport size = 设计视口 × k，size_2d_override 锁设计单位坐标系
##   ④ 剔除一致性：相机在 SubViewport 内 active，敌人屏外判定 _offscreen 收敛
##      （钉住 size_2d_override 语义——canvas_transform 反映相机、剔除换算不因缩放失真）
##   ⑤ 池宿主：GameManager.world_root 登记且 JuiceEffectPool 挂在 world_root 下
## 运行: godot --headless --path . res://tests/WorldViewportCheck.tscn
## 退出码 0 且末行 WORLD_VP_RESULT: ALL PASS

var _c := TestCheck.new()

func _check(cond: bool, label: String) -> void:
	_c.check(cond, label)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var main: Node = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var m := main as MainLevel
	_check(m != null, "Main 场景实例化")
	if m == null:
		get_tree().quit(1)
		return

	# ① 结构不变量
	var container := main.get_node_or_null("WorldContainer") as SubViewportContainer
	var wvp := main.get_node_or_null("WorldContainer/WorldViewport") as SubViewport
	var world := main.get_node_or_null("WorldContainer/WorldViewport/World") as Node2D
	var uilayer := main.get_node_or_null("UILayer") as CanvasLayer
	_check(container != null and wvp != null and world != null, "①WorldContainer/WorldViewport/World 三层在位")
	_check(uilayer != null and uilayer.get_parent() == main, "①UILayer 仍是 Main 直接子节点（UI 留根 viewport）")
	_check(wvp.handle_input_locally == false, "①SubViewport 不本地处理输入（输入全走根 viewport）")
	_check(wvp.gui_disable_input, "①SubViewport gui 输入关闭")
	_check(not wvp.physics_object_picking, "①SubViewport 物理拾取关闭（拾取只在 UI 侧）")
	_check(not container.stretch, "①容器 stretch 关闭（k=0.75 非整数比需手动管理 SubViewport 尺寸）")

	# ② k 映射与 ③ 尺寸同步（headless 下 _sync_world_viewport 也生效：纯逻辑属性）
	var vp_rect: Vector2 = get_viewport().get_visible_rect().size
	_check(GameManager.world_root == world, "②GameManager.world_root 登记为 World 节点")
	var want_high := Vector2i(roundi(vp_rect.x * MainLevel.WORLD_SCALE_HIGH), roundi(vp_rect.y * MainLevel.WORLD_SCALE_HIGH))
	_check(wvp.size == want_high, "②默认高清档世界视口 = 设计视口 ×1.0")
	_check(Vector2(wvp.size_2d_override) == vp_rect.round(), "③override 尺寸 = 设计视口（坐标系锁设计单位）")
	_check(wvp.size_2d_override_stretch, "③size_2d_override_stretch 开启")

	SettingsManager.set_val(&"display", &"render_quality", &"performance", false)
	var want_perf := Vector2i(roundi(vp_rect.x * MainLevel.WORLD_SCALE_PERF), roundi(vp_rect.y * MainLevel.WORLD_SCALE_PERF))
	_check(wvp.size == want_perf, "②流畅档世界视口 = 设计视口 ×0.5")
	_check(Vector2(wvp.size_2d_override) == vp_rect.round(), "③流畅档 override 仍 = 设计视口")

	# 手动改画质清自动 override（_apply_render_quality 重置）
	m._world_scale_override = MainLevel.WORLD_SCALE_BALANCED
	SettingsManager.set_val(&"display", &"render_quality", &"high", false)
	_check(m._world_scale_override == 0.0, "②手动改画质清自动 override")
	_check(wvp.size == want_high, "②清后回高清档尺寸")

	# ④ 剔除一致性：相机在 SubViewport 内 active；敌人屏外判定收敛
	_check(wvp.get_camera_2d() == main.get_node("WorldContainer/WorldViewport/World/SmoothCamera"),
		"④SmoothCamera 是世界 SubViewport 的 active 相机")
	_check(main.get_viewport().get_camera_2d() == null,
		"④根 viewport 无相机（UI 层不受相机影响）")
	var slime_scene: PackedScene = load("res://scenes/entities/SlimeEnemy.tscn")
	_check(slime_scene != null, "④前置：SlimeEnemy.tscn 可加载")
	if slime_scene != null:
		# 主菜单态玩家未注册（EnemyBase._physics_process 首行 return），直接驱动剔除；
		# _update_offscreen_cull 内部走 wvp.get_canvas_transform()，钉住 override 语义
		var cull_e := slime_scene.instantiate() as EnemyBase
		cull_e.position = Vector2(-4000.0, -4000.0)
		world.get_node("EntitiesLayer").add_child(cull_e)
		await get_tree().process_frame
		cull_e._update_offscreen_cull()
		_check(cull_e._offscreen, "④屏外敌人 _offscreen 收敛（缩放不破坏剔除语义）")
		var sp: Vector2 = wvp.get_canvas_transform() * Vector2(-4000.0, -4000.0)
		_check(not wvp.get_visible_rect().grow(EnemyBase.CULL_MARGIN).has_point(sp),
			"④投影换算确认 (-4000,-4000) 在世界视口可见域外")
		world.get_node("EntitiesLayer").remove_child(cull_e)
		cull_e.free()

	# ⑤ 池宿主：JuiceEffectPool 挂在 world_root 下（JuiceEffect._scene_root_for 走 world_root）。
	# 池是懒建（首次发射特效才 _ensure_host），判据直接驱动一次建池验证挂载点。
	JuiceEffect._ensure_host(GameManager.world_root)
	_check(world.get_node_or_null("JuiceEffectPool") != null,
		"⑤JuiceEffectPool 挂在 world_root（World）下")

	SettingsManager.set_val(&"display", &"render_quality", &"high", false)
	main.queue_free()
	await get_tree().process_frame

	if not _c.all_passed():
		print("WORLD_VP_RESULT: FAILED (%d failures)" % _c.failures.size())
		get_tree().quit(1)
	else:
		print("WORLD_VP_RESULT: ALL PASS (%d checks)" % _c.passed)
		get_tree().quit(0)
