extends Control

## 武器、法宝、悟道属性与飞行物【空洞冷冽国风】全要素综合画廊预览
## 验证并导出全套 20 法器、20 道具、8 属性图标与纯矢量弹道飞行物

const SCREEN_W: float = 960.0
const SCREEN_H: float = 540.0

func _ready() -> void:
	custom_minimum_size = Vector2(SCREEN_W, SCREEN_H)
	size = Vector2(SCREEN_W, SCREEN_H)
	_build_ui()
	await get_tree().process_frame
	await get_tree().process_frame
	_export_showcase_image()

func _build_ui() -> void:
	# 底板背景（深墨玄岩）
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.10)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_vbox.offset_left = 12
	main_vbox.offset_top = 8
	main_vbox.offset_right = -12
	main_vbox.offset_bottom = -8
	main_vbox.add_theme_constant_override("separation", 6)
	add_child(main_vbox)

	# 顶部标题栏
	var title_box := HBoxContainer.new()
	var title_lbl := Label.new()
	title_lbl.text = "修仙幸存者 · 空洞冷冽国风【法器 · 法宝 · 属性 · 弹道】全要素视觉矩阵"
	GameStyle.label(title_lbl, 13, GameStyle.PAPER, 0, GameStyle.INK, true)
	title_box.add_child(title_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = "   [纯矢量几何切面 · 骨玉玄铁 · 无3D厚涂]"
	GameStyle.label(sub_lbl, 10, GameStyle.JADE)
	title_box.add_child(sub_lbl)
	main_vbox.add_child(title_box)

	# 左右双分主展示区
	var body_hbox := HBoxContainer.new()
	body_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_hbox.add_theme_constant_override("separation", 10)
	main_vbox.add_child(body_hbox)

	# ----------------- 左侧：20 件法宝武器 -----------------
	var left_panel := PanelContainer.new()
	left_panel.custom_minimum_size = Vector2(460, 480)
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.add_theme_stylebox_override("panel", GameStyle.outlined_panel(Color(0.07, 0.09, 0.13), Color(0.18, 0.25, 0.38), 1, 0.0))
	body_hbox.add_child(left_panel)

	var left_vbox := VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 4)
	left_vbox.offset_left = 6
	left_vbox.offset_top = 4
	left_vbox.offset_right = -6
	left_vbox.offset_bottom = -4
	left_panel.add_child(left_vbox)

	var wep_title := Label.new()
	wep_title.text = "二十件五行法器（金木水火土 · 纯矢量切面）"
	GameStyle.label(wep_title, 11, GameStyle.GOLD, 0, GameStyle.INK, true)
	left_vbox.add_child(wep_title)

	var wep_grid := GridContainer.new()
	wep_grid.columns = 5
	wep_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wep_grid.add_theme_constant_override("h_separation", 4)
	wep_grid.add_theme_constant_override("v_separation", 4)
	left_vbox.add_child(wep_grid)

	for def_id in WeaponData.SHOP_POOL:
		var def := WeaponData.get_def(def_id)
		var card := _create_mini_icon_card(def.get("name", ""), def.get("icon", ""), GameStyle.PAPER, def.get("tag", ""))
		wep_grid.add_child(card)

	# ----------------- 右侧：法宝 + 属性 + 弹道 -----------------
	var right_vbox := VBoxContainer.new()
	right_vbox.custom_minimum_size = Vector2(460, 480)
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.add_theme_constant_override("separation", 6)
	body_hbox.add_child(right_vbox)

	# 右上：20 件法宝道具
	var item_panel := PanelContainer.new()
	item_panel.custom_minimum_size = Vector2(460, 270)
	item_panel.add_theme_stylebox_override("panel", GameStyle.outlined_panel(Color(0.07, 0.09, 0.13), Color(0.18, 0.25, 0.38), 1, 0.0))
	right_vbox.add_child(item_panel)

	var item_vbox := VBoxContainer.new()
	item_vbox.add_theme_constant_override("separation", 4)
	item_vbox.offset_left = 6
	item_vbox.offset_top = 4
	item_vbox.offset_right = -6
	item_vbox.offset_bottom = -4
	item_panel.add_child(item_vbox)

	var item_title := Label.new()
	item_title.text = "二十件灵阁法宝（凡品 · 良品 · 仙品 · 传说）"
	GameStyle.label(item_title, 11, GameStyle.JADE, 0, GameStyle.INK, true)
	item_vbox.add_child(item_title)

	var item_grid := GridContainer.new()
	item_grid.columns = 5
	item_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_grid.add_theme_constant_override("h_separation", 4)
	item_grid.add_theme_constant_override("v_separation", 4)
	item_vbox.add_child(item_grid)

	for item_id in ItemData.all_ids():
		var def := ItemData.get_def(item_id)
		var tier: int = int(def.get("tier", 1))
		var border_col: Color = ItemData.TIER_COLORS.get(tier, GameStyle.PAPER)
		var card := _create_mini_icon_card(def.get("name", ""), def.get("icon", ""), border_col, "")
		item_grid.add_child(card)

	# 右下：8 大属性图标与纯矢量弹道飞行物实机
	var bottom_panel := PanelContainer.new()
	bottom_panel.custom_minimum_size = Vector2(460, 185)
	bottom_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom_panel.add_theme_stylebox_override("panel", GameStyle.outlined_panel(Color(0.07, 0.09, 0.13), Color(0.18, 0.25, 0.38), 1, 0.0))
	right_vbox.add_child(bottom_panel)

	var bot_vbox := VBoxContainer.new()
	bot_vbox.add_theme_constant_override("separation", 4)
	bot_vbox.offset_left = 6
	bot_vbox.offset_top = 4
	bot_vbox.offset_right = -6
	bot_vbox.offset_bottom = -4
	bottom_panel.add_child(bot_vbox)

	var bot_title := Label.new()
	bot_title.text = "八大悟道属性图标 & 纯矢量弹道飞行物实机展示"
	GameStyle.label(bot_title, 11, Color(0.4, 0.8, 1.0), 0, GameStyle.INK, true)
	bot_vbox.add_child(bot_title)

	var bot_hbox := HBoxContainer.new()
	bot_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bot_hbox.add_theme_constant_override("separation", 10)
	bot_vbox.add_child(bot_hbox)

	# 属性图标行 (8 核心属性)
	var stat_grid := GridContainer.new()
	stat_grid.columns = 4
	stat_grid.add_theme_constant_override("h_separation", 4)
	stat_grid.add_theme_constant_override("v_separation", 4)
	bot_hbox.add_child(stat_grid)

	var stats := [
		["攻击", "res://assets/art/icon_atk.png"],
		["护甲", "res://assets/art/icon_armor.png"],
		["移速", "res://assets/art/icon_boots.png"],
		["攻速", "res://assets/art/icon_haste.png"],
		["气血", "res://assets/art/icon_hp.png"],
		["回血", "res://assets/art/icon_regen.png"],
		["磁吸", "res://assets/art/icon_magnet.png"],
		["灵石", "res://assets/art/icon_coin.png"],
	]
	for s_info in stats:
		var scard := _create_stat_icon_chip(s_info[0], s_info[1])
		stat_grid.add_child(scard)

	# 纯矢量弹道飞行物视窗
	var proj_box := PanelContainer.new()
	proj_box.custom_minimum_size = Vector2(210, 135)
	proj_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	proj_box.add_theme_stylebox_override("panel", GameStyle.outlined_panel(Color(0.04, 0.05, 0.08), Color(0.20, 0.35, 0.55), 1, 0.0))
	bot_hbox.add_child(proj_box)

	var proj_view := Control.new()
	proj_view.custom_minimum_size = Vector2(200, 130)
	proj_box.add_child(proj_view)

	# 动态挂载各色纯矢量弹道图元
	_mount_proj_preview(proj_view, ProceduralProjectileRenderer.ProjectileKind.SWORD_GOLD, Vector2(30, 25), "庚金飞剑")
	_mount_proj_preview(proj_view, ProceduralProjectileRenderer.ProjectileKind.DAGGER_LEAF, Vector2(100, 25), "柳叶飞刀")
	_mount_proj_preview(proj_view, ProceduralProjectileRenderer.ProjectileKind.NEEDLE_ICE, Vector2(170, 25), "玄冰飞针")
	_mount_proj_preview(proj_view, ProceduralProjectileRenderer.ProjectileKind.TALISMAN_FIRE, Vector2(30, 68), "烈火神符")
	_mount_proj_preview(proj_view, ProceduralProjectileRenderer.ProjectileKind.FIRE_FLAME, Vector2(100, 68), "三昧真火")
	_mount_proj_preview(proj_view, ProceduralProjectileRenderer.ProjectileKind.SPIRIT_PELLET, Vector2(170, 68), "连环灵弹")

	# 挂载环绕灵蝶与冰魄莲台
	var drone_fly := ProceduralDroneRenderer.new()
	drone_fly.kind = ProceduralDroneRenderer.DroneKind.LINGDIE
	drone_fly.star = 2
	drone_fly.position = Vector2(60, 110)
	drone_fly.scale = Vector2(0.85, 0.85)
	proj_view.add_child(drone_fly)

	var drone_lotus := ProceduralDroneRenderer.new()
	drone_lotus.kind = ProceduralDroneRenderer.DroneKind.HANQUAN_YULIAN
	drone_lotus.star = 2
	drone_lotus.position = Vector2(145, 110)
	drone_lotus.scale = Vector2(0.85, 0.85)
	proj_view.add_child(drone_lotus)

func _create_mini_icon_card(name: String, icon_path: String, border_col: Color, tag: String) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(85, 48)
	p.add_theme_stylebox_override("panel", GameStyle.outlined_panel(Color(0.09, 0.11, 0.16), border_col, 1, 0.0))

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 5)
	h.offset_left = 3
	h.offset_top = 2
	h.offset_right = -3
	h.offset_bottom = -2
	p.add_child(h)

	var trect := TextureRect.new()
	trect.custom_minimum_size = Vector2(34, 34)
	trect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	trect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		trect.texture = load(icon_path)
	h.add_child(trect)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(vbox)

	var n_lbl := Label.new()
	n_lbl.text = name
	GameStyle.label(n_lbl, 9, GameStyle.PAPER)
	vbox.add_child(n_lbl)

	if not tag.is_empty():
		var t_lbl := Label.new()
		t_lbl.text = tag.split("·")[-1] if "·" in tag else tag
		GameStyle.label(t_lbl, 8, GameStyle.GOLD)
		vbox.add_child(t_lbl)

	return p

func _create_stat_icon_chip(stat_name: String, icon_path: String) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(50, 52)
	p.add_theme_stylebox_override("panel", GameStyle.outlined_panel(Color(0.09, 0.11, 0.16), Color(0.25, 0.35, 0.50), 1, 0.0))

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)

	var trect := TextureRect.new()
	trect.custom_minimum_size = Vector2(26, 26)
	trect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	trect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	trect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if ResourceLoader.exists(icon_path):
		trect.texture = load(icon_path)
	v.add_child(trect)

	var l := Label.new()
	l.text = stat_name
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameStyle.label(l, 9, GameStyle.PAPER)
	v.add_child(l)

	return p

func _mount_proj_preview(parent: Control, kind: ProceduralProjectileRenderer.ProjectileKind, pos: Vector2, label_text: String) -> void:
	var pr := ProceduralProjectileRenderer.new()
	pr.kind = kind
	pr.position = pos
	pr.rotation = -PI * 0.25 # 右上45度飞行
	parent.add_child(pr)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.position = pos + Vector2(-16, 9)
	GameStyle.label(lbl, 8, GameStyle.GREY)
	parent.add_child(lbl)

func _export_showcase_image() -> void:
	DirAccess.make_dir_recursive_absolute("tests/styles")
	var vp := get_viewport()
	if vp != null:
		var tex := vp.get_texture()
		if tex != null:
			var img := tex.get_image()
			if img != null and not img.is_empty():
				var path := "tests/styles/weapon_and_item_gallery.png"
				img.save_png(path)
				print("[WeaponAndItemGalleryPreview] 成功导出全套法器/法宝/属性/弹道矩阵看板至: %s" % path)
	await get_tree().create_timer(0.1).timeout
	get_tree().quit()
