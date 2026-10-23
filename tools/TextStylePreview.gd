extends Node

## 逐句标色预览工具（非判据）：把新手指南、手册规则卡、心法、技能、道具的关键句
## 渲染为实际带色块的卡片并截图到 /tmp/style_preview/，供目视验收排版美观度。
## 运行: $G --path . res://tools/TextStylePreview.tscn

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("/tmp/style_preview")

	# 1. 新手指南 5 页各截一张
	var tut = load("res://scenes/ui/TutorialDialog.tscn").instantiate()
	get_tree().root.add_child(tut)
	await get_tree().process_frame
	tut.open()
	for p in [0, 1, 2, 3, 4]:
		tut._go_page(p)
		await get_tree().create_timer(0.3).timeout
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("/tmp/style_preview/tut_p%d.png" % (p + 1))
	tut.close()
	tut.queue_free()
	await get_tree().create_timer(0.2).timeout

	# 2. 进阶心法卡 + 规则卡合辑
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child(host)
	var bg := ColorRect.new()
	bg.color = GameStyle.NAVY
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.add_child(scroll)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(900, 0)
	box.add_theme_constant_override("separation", 10)
	scroll.add_child(box)

	# 选几张代表性卡
	box.add_child(CodexCardFactory.make_text_card(
		"三合一升星", String(ManualData.ADVANCED_SECTIONS[0]["body"]), 860.0))
	box.add_child(CodexCardFactory.make_text_card(
		"加点优先级", String(ManualData.ADVANCED_SECTIONS[2]["body"]), 860.0))
	box.add_child(CodexCardFactory.make_text_card(
		"Boss应对", String(ManualData.ADVANCED_SECTIONS[3]["body"]), 860.0))

	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png("/tmp/style_preview/manual_cards.png")

	host.queue_free()
	await get_tree().create_timer(0.2).timeout

	# 3. 详情卡 DetailTip 代表性展示（道具玄铁令 + 属性闪避率）
	var tip_host := Control.new()
	tip_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child(tip_host)
	var anchor := Control.new()
	anchor.position = Vector2(100, 60); anchor.size = Vector2(60, 24)
	tip_host.add_child(anchor)
	DetailTip.show_over(tip_host, anchor, {
		"title": "闪避率", "chip": "属性", "chip_color": GameStyle.GOLD,
		"body": StatInfoData.brief("dodge"),
		"notes": StatInfoData.rules("dodge"),
	})
	await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	get_viewport().get_texture().get_image().save_png("/tmp/style_preview/tip_dodge.png")

	DetailTip.close_all(tip_host)
	await get_tree().create_timer(0.2).timeout

	var anchor2 := Control.new()
	anchor2.position = Vector2(500, 60); anchor2.size = Vector2(60, 24)
	tip_host.add_child(anchor2)
	DetailTip.show_over(tip_host, anchor2, {
		"title": "玄铁令", "chip": "史诗道具", "chip_color": GameStyle.RARITY_EPIC,
		"rows": [["品阶", "史诗"], ["当前持有", "1 件"]],
		"body": "被动道具：属性加成与悟道同源叠加。",
		"notes": ["被动道具：购入即永久生效，不占用上阵武器槽位。", "武器伤害大幅提升，攻速略降"],
		"foot": "在回合间商店可继续购置更多道具。",
	})
	await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	get_viewport().get_texture().get_image().save_png("/tmp/style_preview/tip_item.png")

	print("PREVIEW_ALL_SAVED")
	get_tree().quit(0)
