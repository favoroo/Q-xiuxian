extends Node

## 非判据量尺：把首页「竖向这一列是怎么排的」摊开成数字，并出一张 20:9 真机比例的图。
## 运行: $G --headless --path . res://tests/StartMenuCompositionProbe.tscn      # 只要数字
##       $G --path . res://tests/StartMenuCompositionProbe.tscn -- --shot        # 另存 /tmp 图
##
## 为什么要有它：2026-10-10 用户真机图「标题上面怎么有那么大的空白间距」。
## 中央区是 CenterContainer 里一整个居中 VBox ⇒ 上下空白天然相等，但顶栏另算一段，
## 眼睛看到的是「标题离顶栏远、离底部也远」，光看代码猜不出各段实际多少 px。
## 这里量的是引擎实得 rect：顶栏底 → 标题顶 → 矩阵上下 → 横幅上下 → 屏底。

const SIZES: Array[Vector2i] = [Vector2i(960, 720), Vector2i(960, 540), Vector2i(1204, 540)]

var _holder: Control

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	_holder = Control.new()
	_holder.name = "CompositionHolder"
	_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().root.add_child(_holder)

	var menu: Control = load("res://scenes/ui/StartMenu.tscn").instantiate()
	_holder.add_child(menu)
	menu.open()
	await get_tree().create_timer(0.8).timeout

	for w in SIZES:
		get_tree().root.size = w
		await get_tree().process_frame
		await get_tree().process_frame
		var screen: Vector2 = get_tree().root.get_visible_rect().size
		menu._layout_responsive()
		await get_tree().process_frame
		print("\n===== 设计可视 %s =====" % str(screen))
		_dump(menu, screen)

	if "--shot" in OS.get_cmdline_user_args():
		get_tree().root.size = Vector2i(1204, 540)
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		menu._layout_responsive()
		for i in range(4):
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("/tmp/start_menu_comp.png")
		print("\nSHOT -> /tmp/start_menu_comp.png")

	get_tree().quit(0)

func _y(c: Control) -> float:
	return c.get_global_rect().position.y

func _b(c: Control) -> float:
	var r := c.get_global_rect()
	return r.position.y + r.size.y

func _dump(menu: Control, screen: Vector2) -> void:
	var top_b := _b(menu._top_bar)
	var title_r: Rect2 = menu._title_block.get_global_rect()
	var hero_r: Rect2 = menu._hero_card.get_global_rect()
	var banner_r: Rect2 = menu._banner_panel.get_global_rect()
	print("顶栏底 y=%.1f" % top_b)
	print("标题  y=[%.1f, %.1f] 高=%.1f" % [title_r.position.y, _b(menu._title_block), title_r.size.y])
	print("矩阵  y=[%.1f, %.1f] 高=%.1f" % [hero_r.position.y, _b(menu._hero_card), hero_r.size.y])
	print("横幅  y=[%.1f, %.1f] 高=%.1f" % [banner_r.position.y, _b(menu._banner_panel), banner_r.size.y])
	print("空白：屏顶→标题 %.1f | 顶栏→标题 %.1f | 标题→矩阵 %.1f | 矩阵→横幅 %.1f | 横幅→屏底 %.1f" % [
		title_r.position.y,
		title_r.position.y - top_b,
		hero_r.position.y - _b(menu._title_block),
		banner_r.position.y - _b(menu._hero_card),
		screen.y - (banner_r.position.y + banner_r.size.y),
	])
