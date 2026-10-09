extends Node

## 非判据量尺：把悟道面板每一档屏宽下「画出来的边界」打出来，给人看的数字版。
## 运行: $G --headless --path . res://tests/LayoutBleedProbe.tscn
##
## 为什么要有它：LayoutCheck 报的是「有没有毛病」，而「溢出多少、让位让掉多少」要看得见
## 才好判断改得对不对（用户说「有点溢出」，得有个数）。判据用同一份算术（drawn_rect 的
## 斜切口径与 LevelUpDialog.skew_x() 一致），这里只把每一格的读数摊开。

const SIZES: Array[Vector2i] = [Vector2i(960, 720), Vector2i(960, 540), Vector2i(1204, 540)]

var _holder: Control

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	_holder = Control.new()
	_holder.name = "BleedHolder"
	_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child(_holder)
	GameManager.cultivator_id = "jianchi"
	GameManager.start_run("qingyun_sword")
	GameManager.pending_upgrade_points = 2
	GameManager.open_alloc_session()
	await get_tree().process_frame
	for w in SIZES:
		get_tree().root.size = w
		await get_tree().process_frame
		await get_tree().process_frame
		var screen: Vector2 = get_tree().root.get_visible_rect().size
		var node: Control = load("res://scenes/ui/LevelUpDialog.tscn").instantiate()
		node.visible = true
		_holder.add_child(node)
		await get_tree().process_frame
		node._on_alloc_opened()
		await get_tree().create_timer(0.6).timeout
		node._select_card(1)
		await get_tree().create_timer(0.4).timeout
		await get_tree().process_frame
		get_tree().paused = false
		print("\n===== 设计可视 %.0fx%.0f =====" % [screen.x, screen.y])
		var panel: Control = node.get_node("CenterContainer/Panel")
		var pr: Rect2 = _drawn(panel)
		print("面板 布局盒 %.0f..%.0f x %.0f..%.0f → 画出来 %.1f..%.1f" % [
			panel.get_global_rect().position.x, panel.get_global_rect().end.x,
			panel.get_global_rect().position.y, panel.get_global_rect().end.y,
			pr.position.x, pr.end.x])
		print("     离屏 左 %.1f 右 %.1f（PANEL_AIR_X=%s）" % [
			pr.position.x, screen.x - pr.end.x, str(LevelUpDialog.PANEL_AIR_X)])
		var row: Control = node.get_node(
			"CenterContainer/Panel/MarginContainer/VBox/CardScroll")
		var rr: Rect2 = row.get_global_rect()
		print("卡片行 y %.0f..%.0f（高 %.0f）" % [rr.position.y, rr.end.y, rr.size.y])
		var cont: Control = node.get_node(
			"CenterContainer/Panel/MarginContainer/VBox/CardScroll/CardsPad/CardsContainer")
		var i := 0
		for card in cont.get_children():
			if not (card is Control):
				continue
			var d: Rect2 = _drawn(card)
			print("  卡#%d 画出来 x %.1f..%.1f  y %.1f..%.1f  离屏左 %.1f 离屏右 %.1f  %s" % [
				i, d.position.x, d.end.x, d.position.y, d.end.y, d.position.x, screen.x - d.end.x,
				"" if (d.position.y >= rr.position.y - 0.5 and d.end.y <= rr.end.y + 0.5)
					else "↑ 顶出这一行"])
			i += 1
		await _old_look(node, screen)
		node.queue_free()
		await get_tree().process_frame
	print("\nBLEED_PROBE_DONE")
	get_tree().quit(0)

## 反例复现：把这一屏摆回改之前的样子（面板布局盒铺满屏宽 + 这一行不留放大余量），
## 用同一把尺再量一遍 —— 判据的牙齿要用数字证明，不是靠说。
func _old_look(node: Control, screen: Vector2) -> void:
	var panel: Control = node.get_node("CenterContainer/Panel")
	var pad: MarginContainer = node.get_node(
		"CenterContainer/Panel/MarginContainer/VBox/CardScroll/CardsPad")
	var row: Control = node.get_node("CenterContainer/Panel/MarginContainer/VBox/CardScroll")
	var cont: Control = node.get_node(
		"CenterContainer/Panel/MarginContainer/VBox/CardScroll/CardsPad/CardsContainer")
	var old_min: Vector2 = panel.custom_minimum_size
	panel.custom_minimum_size = Vector2(screen.x, old_min.y)
	pad.add_theme_constant_override("margin_top", 0)
	pad.add_theme_constant_override("margin_bottom", 0)
	await get_tree().process_frame
	await get_tree().process_frame
	# 容器重排会把子节点的 scale 打回 1.0（引擎行为）⇒ 放大这一项重排后要自己按上
	var sel: Control = cont.get_child(1) as Control
	sel.pivot_offset = sel.size * 0.5
	sel.scale = Vector2(LevelUpDialog.SEL_SCALE, LevelUpDialog.SEL_SCALE)
	await get_tree().process_frame
	var pd: Rect2 = _drawn(panel)
	var rr: Rect2 = row.get_global_rect()
	var d: Rect2 = _drawn(sel)
	print("  [反例复现·旧摆位] 面板画出来 %.1f..%.1f → 两头各被屏幕切掉 %.1f 单位；" % [
		pd.position.x, pd.end.x, maxf(-pd.position.x, pd.end.x - screen.x)])
	print("      选中卡撑满整行再放大 → 画出来 y %.1f..%.1f，顶出这一行（y %.0f..%.0f）上 %.1f 下 %.1f" % [
		d.position.y, d.end.y, rr.position.y, rr.end.y,
		maxf(0.0, rr.position.y - d.position.y), maxf(0.0, d.end.y - rr.end.y)])
	panel.custom_minimum_size = old_min
	var g := int(LevelUpDialog.pop_gutter_y(screen.y))
	pad.add_theme_constant_override("margin_top", g)
	pad.add_theme_constant_override("margin_bottom", g)

## 与判据同一口径：get_global_rect() 已含缩放，再按这份 stylebox 的 skew 左右各伸出半个斜切
func _drawn(c: Control) -> Rect2:
	var r: Rect2 = c.get_global_rect()
	var skew := 0.0
	for key in ["panel", "normal"]:
		if c.has_theme_stylebox(key) and c.get_theme_stylebox(key) is StyleBoxFlat:
			skew = (c.get_theme_stylebox(key) as StyleBoxFlat).skew.x
			break
	var over: float = absf(skew) * r.size.y * 0.5
	return Rect2(r.position.x - over, r.position.y, r.size.x + over * 2.0, r.size.y)
