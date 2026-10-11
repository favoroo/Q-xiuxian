extends Node

## 非判据量尺：把首页「竖向这一列是怎么排的」摊开成数字，并出一张 20:9 真机比例的图。
## 运行: $G --headless --path . res://tests/StartMenuCompositionProbe.tscn      # 只要数字
##       $G --path . res://tests/StartMenuCompositionProbe.tscn -- --shot        # 另存 /tmp 图
##
## 为什么要有它：2026-10-10 用户真机图「标题上面怎么有那么大的空白间距」；
## 2026-10-11 撤掉标题大匾、把省出来的竖向空间给方块长高，风险换了一头 ——
## 卡片长高多出来的那一截会被卡内那根 expanding 弹簧吃掉，变成「卡片中间一片空」。
## 这里量的是引擎实得 rect：顶栏底 → 矩阵上下 → 卡内空洞 → 右下角按钮 → 屏底，
## 并另算一格「卡内最小需高 vs 卡片实得高」：需高超过实得 = 内容顶破卡片，当场报出来。

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
		# 逐档各出一张：竖向这一列是按屏高现算的，只看 20:9 那一张量不出 4:3 平板那一档
		for w in SIZES:
			get_tree().root.size = w
			await get_tree().create_timer(0.6).timeout   # 等入场缩放落定，别拍在半张开的中间帧
			for i in range(4):
				await get_tree().process_frame
			menu._layout_responsive()
			for i in range(4):
				await get_tree().process_frame
			var out := "/tmp/start_menu_comp_%dx%d.png" % [w.x, w.y]
			get_viewport().get_texture().get_image().save_png(out)
			print("SHOT -> %s" % out)

	get_tree().quit(0)

func _y(c: Control) -> float:
	return c.get_global_rect().position.y

func _b(c: Control) -> float:
	var r := c.get_global_rect()
	return r.position.y + r.size.y

func _dump(menu: Control, screen: Vector2) -> void:
	var top_b := _b(menu._top_bar)
	var hero_r: Rect2 = menu._hero_card.get_global_rect()
	var btn_r: Rect2 = menu._update_btn.get_global_rect()
	print("顶栏底 y=%.1f" % top_b)
	print("矩阵  y=[%.1f, %.1f] 高=%.1f（Hero 宽 %.1f）" % [
		hero_r.position.y, _b(menu._hero_card), hero_r.size.y, hero_r.size.x])
	print("按钮  x=[%.1f, %.1f] y=[%.1f, %.1f] 尺寸=%.1fx%.1f" % [
		btn_r.position.x, btn_r.position.x + btn_r.size.x,
		btn_r.position.y, _b(menu._update_btn), btn_r.size.x, btn_r.size.y,
	])
	print("空白：屏顶→矩阵 %.1f | 顶栏→矩阵 %.1f | 矩阵→按钮 %.1f | 按钮→屏底 %.1f" % [
		hero_r.position.y,
		hero_r.position.y - top_b,
		btn_r.position.y - _b(menu._hero_card),
		screen.y - (btn_r.position.y + btn_r.size.y),
	])
	# 卡内那一截空洞：expanding 弹簧实得的高。富余没摊给字号/键高时它就是最大的一项。
	var hv: Rect2 = menu._hero_void.get_global_rect()
	print("Hero 卡内空洞 %.1f（占卡高 %.0f%%）｜字号 %d｜出战键高 %.1f｜危险度键高 %.1f" % [
		hv.size.y, hv.size.y / maxf(hero_r.size.y, 1.0) * 100.0,
		menu._hero_title.get_theme_font_size("font_size"),
		menu._hero_start_btn.custom_minimum_size.y,
		menu._danger_buttons[0].custom_minimum_size.y,
	])
	_check_card(menu._hero_card, "Hero")
	for blk in menu._entry_blocks:
		var card: Control = blk["card"]
		var v: Rect2 = (blk["void"] as Control).get_global_rect()
		print("  %s 空洞 %.1f（占卡高 %.0f%%）｜名号字号 %d" % [
			String((blk["name_label"] as Label).text).replace(" ", ""),
			v.size.y, v.size.y / maxf(card.size.y, 1.0) * 100.0,
			(blk["name_label"] as Label).get_theme_font_size("font_size"),
		])
		_check_card(card, String((blk["name_label"] as Label).text).replace(" ", ""))

## 内容顶破卡片没有：卡内最小需高 vs 卡片实得高（超了就是文字/键被切出卡外）。
func _check_card(card: Control, tag: String) -> void:
	var need: float = card.get_combined_minimum_size().y
	var got: float = card.size.y
	var flag := "" if need <= got + 0.5 else "  ← 顶破 %.1f" % (need - got)
	print("  %s 需高 %.1f / 实得 %.1f%s" % [tag, need, got, flag])
