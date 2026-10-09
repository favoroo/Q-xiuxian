extends SceneTree

## 角标布局探针（判据）：复现 PanelContainer + element_badge 的真实布局行为。
## 背景：入树前 get_combined_minimum_size() 拿到兜底字体的偏大度量（实测 32×22 vs 真值 20×12），
## 预采尺寸定偏移会把角标撑大糊住图标。现行配方 = 零尺寸矩形钉右上角 + 生长方向朝左/下，
## 由引擎在入树后按真实 min size 自行撑开。
## 本探针钉两条判据（对比尺寸一律用【入树后】的实时 min size）：
##   1. holder 被 PanelContainer 铺满 52×52（外层吃满是设计意图）
##   2. 角标 Label 矩形 == 实时 min size、钉在 holder 右上角（不许残留偏大矩形）
## 运行：$G --headless --path . --script res://tests/badge_probe.gd

func _init() -> void:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(52, 52)

	var icon := TextureRect.new()
	box.add_child(icon)

	# 与 GameStyle.element_badge 相同的结构：plain Control 外壳 + 零尺寸锚点 Label + 生长方向
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(holder)

	var lbl := Label.new()
	lbl.text = "元素"
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("ff8a3d")
	sb.content_margin_left = 2.0
	sb.content_margin_right = 2.0
	lbl.add_theme_stylebox_override("normal", sb)
	lbl.add_theme_font_size_override("font_size", 8)
	holder.add_child(lbl)
	lbl.anchor_left = 1.0
	lbl.anchor_right = 1.0
	lbl.anchor_top = 0.0
	lbl.anchor_bottom = 0.0
	lbl.offset_left = -1.0
	lbl.offset_right = -1.0
	lbl.offset_top = 1.0
	lbl.offset_bottom = 1.0
	lbl.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	lbl.grow_vertical = Control.GROW_DIRECTION_END

	box.add_child(Label.new())  # 模拟 star_lbl 这类第三个填充子节点

	root.add_child(box)
	await process_frame
	await process_frame
	await process_frame

	var fails: Array[String] = []
	var live_ms := lbl.get_combined_minimum_size()  # 入树后真值，别用入树前快照
	print("holder rect: ", holder.get_rect())
	print("label  rect: ", lbl.get_rect(), " live min_size: ", live_ms)

	if not holder.get_rect().size.is_equal_approx(Vector2(52, 52)):
		fails.append("holder 未被铺满 52x52")
	if lbl.get_rect().size.x > live_ms.x + 0.5 or lbl.get_rect().size.y > live_ms.y + 0.5:
		fails.append("label 大于实时 min size（rect=%s, min=%s）" % [lbl.get_rect().size, live_ms])
	if lbl.get_rect().size.x < live_ms.x - 0.5 or lbl.get_rect().size.y < live_ms.y - 0.5:
		fails.append("label 小于实时 min size，文字会被裁（rect=%s, min=%s）" % [lbl.get_rect().size, live_ms])
	var want_pos := Vector2(52.0 - 1.0 - live_ms.x, 1.0)
	if lbl.get_rect().position.distance_to(want_pos) > 1.0:
		fails.append("label 未钉在右上角（pos=%s，期望≈%s）" % [lbl.get_rect().position, want_pos])

	if fails.is_empty():
		print("BADGE_PROBE_RESULT: ALL PASS")
	else:
		for f in fails:
			print("[FAIL] ", f)
		print("BADGE_PROBE_RESULT: FAIL")
	quit(0 if fails.is_empty() else 1)
