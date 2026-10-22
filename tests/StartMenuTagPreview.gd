extends Node

## 非判据现场工具：渲染主菜单（960×540 / 1204×540 两档）并截图到项目根
## tmp_startmenu_<宽>x<高>[_<主题>].png，供目检角签可读性。
## 每档顺手切一次主题色（荧绿 → 品红）再拍一张：角签色标必须跟着换肤，
## 不许停在建卡那一刻的旧色（ColorRect 那种不走注册表的写法就会漏）。
## 用法：$G --path . res://tests/StartMenuTagPreview.tscn

const SIZES := [Vector2i(960, 540), Vector2i(1204, 540)]

func _ready() -> void:
	for sz in SIZES:
		var vp := SubViewport.new()
		vp.size = sz
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.disable_3d = true
		add_child(vp)

		var menu := StartMenu.new()
		menu.set_anchors_preset(Control.PRESET_FULL_RECT)
		vp.add_child(menu)
		menu.open()

		# 入场是错峰缩放/淡入补间，等它落定再截
		await get_tree().create_timer(1.4).timeout
		await _shot(vp, "res://tmp_startmenu_%dx%d.png" % [sz.x, sz.y])

		# 换肤现场：菜单不重建，靠注册表把主题色件原地改色
		GameStyle.apply_theme_color(&"pink")
		await get_tree().process_frame
		await _shot(vp, "res://tmp_startmenu_%dx%d_pink.png" % [sz.x, sz.y])
		GameStyle.apply_theme_color(&"lime")

		vp.queue_free()
		await get_tree().process_frame

	get_tree().quit(0)

func _shot(vp: SubViewport, path: String) -> void:
	for _i in range(3):
		await get_tree().process_frame
	var img := vp.get_texture().get_image()
	if img == null:
		print("NO IMAGE %s" % path)
		return
	img.save_png(path)
	print("SAVED %s" % path)
