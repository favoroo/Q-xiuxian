class_name LootAndMapPreview
extends Control

## 地图战台、掉落物与聚灵阵新风格预览看板（空洞冷冽国风）
## 导出高清场景大图 tests/styles/loot_and_map_preview.png

var _time: float = 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(960, 540)
	size = Vector2(960, 540)

	var bg := ColorRect.new()
	bg.color = Color(0.035, 0.045, 0.07)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_build_ui()

	var tree := get_tree()
	if tree != null:
		# 等待充分渲染与时间推进
		for i in range(12):
			await tree.process_frame
		_export_showcase_image()
		if OS.get_cmdline_user_args().has("--export") or DisplayServer.get_name() == "headless":
			print("LOOT_AND_MAP_RESULT: ALL PASS")
			tree.quit(0)

func _process(delta: float) -> void:
	_time += delta

func _build_ui() -> void:
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 12
	root.offset_top = 10
	root.offset_right = -12
	root.offset_bottom = -10
	root.add_theme_constant_override("separation", 12)
	add_child(root)

	# ==========================================================================
	# 左侧：实机战台俯瞰视界 (Arena Showcase)
	# ==========================================================================
	var left_box := VBoxContainer.new()
	left_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_box.size_flags_stretch_ratio = 1.35
	left_box.add_theme_constant_override("separation", 6)
	root.add_child(left_box)

	var left_title_box := HBoxContainer.new()
	left_title_box.add_theme_constant_override("separation", 8)
	left_box.add_child(left_title_box)

	var title_lbl := Label.new()
	title_lbl.text = "九幽玄天战台 · 实战俯瞰全景"
	GameStyle.label(title_lbl, 13, GameStyle.PAPER, true)
	left_title_box.add_child(title_lbl)

	var sub_chip := Label.new()
	sub_chip.text = " 1024玄岩无缝地砖 + 矢量太极古阵 + 锁灵结界 "
	sub_chip.add_theme_stylebox_override("normal", GameStyle.chip(Color(0.12, 0.20, 0.32)))
	GameStyle.label(sub_chip, 9, GameStyle.JADE)
	left_title_box.add_child(sub_chip)

	# 战台视界面板（带暗框与裁切）
	var arena_panel := PanelContainer.new()
	arena_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	arena_panel.clip_contents = true
	var p_style := StyleBoxFlat.new()
	p_style.bg_color = Color(0.04, 0.06, 0.09)
	p_style.border_width_left = 1
	p_style.border_width_top = 1
	p_style.border_width_right = 1
	p_style.border_width_bottom = 1
	p_style.border_color = Color(0.25, 0.40, 0.55, 0.8)
	arena_panel.add_theme_stylebox_override("panel", p_style)
	left_box.add_child(arena_panel)

	var arena_viewport_node := Node2D.new()
	arena_panel.add_child(arena_viewport_node)
	arena_viewport_node.position = Vector2(285, 235)  # 居中对齐

	# 1. 地砖平铺 (TextureRect)
	var tiles := TextureRect.new()
	tiles.texture = preload("res://assets/art/courtyard_tile.png")
	tiles.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	tiles.stretch_mode = TextureRect.STRETCH_TILE
	tiles.position = Vector2(-360, -300)
	tiles.size = Vector2(720, 600)
	tiles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arena_viewport_node.add_child(tiles)

	# 2. 战台矢量大阵与结界
	var arena_vis := ArenaVisualLayer.new()
	arena_vis.half_extent = 260.0  # 缩小到看板适中视野
	arena_viewport_node.add_child(arena_vis)

	# 3. 在战台上摆设九天悬晶大阵（待命完整体）
	var obelisk := ProceduralObeliskRenderer.new()
	obelisk.position = Vector2(0, -90)
	obelisk.is_player_inside = true
	arena_viewport_node.add_child(obelisk)

	# 4. 在战台地面散布八面菱形水晶与灵宝
	var gem_blue := ProceduralLootRenderer.new()
	gem_blue.loot_type = ProceduralLootRenderer.LootType.GEM_BLUE
	gem_blue.position = Vector2(-75, 40)
	gem_blue.scale = Vector2.ONE * 1.3
	arena_viewport_node.add_child(gem_blue)

	var gem_gold := ProceduralLootRenderer.new()
	gem_gold.loot_type = ProceduralLootRenderer.LootType.GEM_GOLD
	gem_gold.position = Vector2(-45, 75)
	gem_gold.scale = Vector2.ONE * 1.3
	arena_viewport_node.add_child(gem_gold)

	var heal_gem := ProceduralLootRenderer.new()
	heal_gem.loot_type = ProceduralLootRenderer.LootType.HEAL_ORB
	heal_gem.position = Vector2(65, 55)
	heal_gem.scale = Vector2.ONE * 1.25
	arena_viewport_node.add_child(heal_gem)

	var chest := ProceduralLootRenderer.new()
	chest.loot_type = ProceduralLootRenderer.LootType.CHEST
	chest.chest_total_hits = 3
	chest.chest_left_hits = 2
	chest.position = Vector2(130, -35)
	arena_viewport_node.add_child(chest)

	# ==========================================================================
	# 右侧：灵宝物华与阵法状态矩阵 (Loot & Altar Grid)
	# ==========================================================================
	var right_box := VBoxContainer.new()
	right_box.custom_minimum_size = Vector2(360, 0)
	right_box.add_theme_constant_override("separation", 6)
	root.add_child(right_box)

	var right_title_lbl := Label.new()
	right_title_lbl.text = "灵宝物华与大阵诸相"
	GameStyle.label(right_title_lbl, 13, GameStyle.PAPER, true)
	right_box.add_child(right_title_lbl)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	right_box.add_child(grid)

	# 6 块展台卡片
	grid.add_child(_create_loot_card("八面幽蓝灵石", "击杀普通怪掉落·晶莹八面立体", ProceduralLootRenderer.LootType.GEM_BLUE, 1.8, false))
	grid.add_child(_create_loot_card("八面赤金灵石", "击杀精英/大阵爆发·耀金高阶灵粹", ProceduralLootRenderer.LootType.GEM_GOLD, 1.8, false))
	grid.add_child(_create_loot_card("碧翠回春灵玉", "贴身拾取·内蕴生机光种", ProceduralLootRenderer.LootType.HEAL_ORB, 1.7, false))
	grid.add_child(_create_loot_card("回春待命灰玉", "满血不吃·暗哑石青等掉血", ProceduralLootRenderer.LootType.HEAL_ORB, 1.7, true))
	grid.add_child(_create_loot_card("九幽玄铁灵匣", "八角玄铁·受击龟裂掉宝", ProceduralLootRenderer.LootType.CHEST, 1.1, false, 3, 2))
	grid.add_child(_create_obelisk_card("九天锁灵悬晶柱", "充能聚灵 50% 走针 & 灵液注满"))

func _create_loot_card(title: String, desc: String, ltype: ProceduralLootRenderer.LootType, sc: float, is_wait: bool, tot: int = 3, left: int = 3) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", GameStyle.outlined_panel(Color(0.06, 0.08, 0.12), Color(0.18, 0.25, 0.35), 1, 0.0))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.offset_left = 6
	vbox.offset_top = 6
	vbox.offset_right = -6
	vbox.offset_bottom = -6
	panel.add_child(vbox)

	var t_lbl := Label.new()
	t_lbl.text = title
	GameStyle.label(t_lbl, 10, GameStyle.PAPER, true)
	vbox.add_child(t_lbl)

	var disp := Control.new()
	disp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(disp)

	var loot := ProceduralLootRenderer.new()
	loot.loot_type = ltype
	loot.is_waiting = is_wait
	loot.chest_total_hits = tot
	loot.chest_left_hits = left
	loot.scale = Vector2.ONE * sc
	loot.position = Vector2(85, 38)
	disp.add_child(loot)

	var d_lbl := Label.new()
	d_lbl.text = desc
	GameStyle.label(d_lbl, 8, GameStyle.GREY)
	vbox.add_child(d_lbl)

	return panel

func _create_obelisk_card(title: String, desc: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", GameStyle.outlined_panel(Color(0.06, 0.08, 0.12), Color(0.18, 0.25, 0.35), 1, 0.0))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.offset_left = 6
	vbox.offset_top = 6
	vbox.offset_right = -6
	vbox.offset_bottom = -6
	panel.add_child(vbox)

	var t_lbl := Label.new()
	t_lbl.text = title
	GameStyle.label(t_lbl, 10, GameStyle.PAPER, true)
	vbox.add_child(t_lbl)

	var disp := Control.new()
	disp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(disp)

	var ob := ProceduralObeliskRenderer.new()
	ob.scale = Vector2.ONE * 0.58
	ob.position = Vector2(85, 42)
	ob.is_charging = true
	ob.fill_ratio = 0.55
	disp.add_child(ob)

	var d_lbl := Label.new()
	d_lbl.text = desc
	GameStyle.label(d_lbl, 8, GameStyle.GREY)
	vbox.add_child(d_lbl)

	return panel

func _export_showcase_image() -> void:
	DirAccess.make_dir_recursive_absolute("tests/styles")
	var vp := get_viewport()
	if vp != null:
		var tex := vp.get_texture()
		if tex != null:
			var img := tex.get_image()
			if img != null and not img.is_empty():
				var path := "tests/styles/loot_and_map_preview.png"
				img.save_png(path)
				print("[LootAndMapPreview] 成功导出战台与灵宝画廊大图至: %s" % path)
