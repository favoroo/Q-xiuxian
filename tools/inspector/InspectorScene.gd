extends Control

## 剑士 · 视觉检视场景 (Asset Inspector Scene)
## 支持全游戏视觉资产：
##   1. cultivator (修仙真身角色): 单体 4 视角特写 / 全量 20 位全景画廊
##   2. enemy (妖魔拟态): 单体 3 态特写 / 全量 17 种画廊 (无遗漏)
##   3. vfx (武器攻击特效): 单体 / 12 款刀光扇面 + 光束 + 火锥 + 6 种爆发全景
##   4. projectile (飞行物与弹丸): 21 种纯矢量弹丸 + 敌方飞弹特写 / 画廊
##   5. ui (界面组件与样式): GameStyle 规范样张与面板画廊
##
## 布局严格适配 960×540 核心视口规范，确保截图 100% 完整收录无截断。

const BG_COLOR := Color(0.04, 0.05, 0.08)
const GRID_COLOR := Color(0.12, 0.16, 0.24, 0.5)

var target_type: String = "cultivator"
var target_id: String = "jianchi"
var view_scale: float = 3.5
var out_path: String = "tests/inspect/preview.png"
var show_grid: bool = false
var is_gallery_mode: bool = false

var _cultivator_renderers: Array[HollowKnightCultivatorRenderer] = []
var _enemy_renderers: Array[HollowKnightEnemyRenderer] = []
var _vfx_nodes: Array[Node2D] = []

func _ready() -> void:
	_parse_arguments()
	
	DirAccess.make_dir_recursive_absolute("tests/inspect")
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	custom_minimum_size = Vector2(960, 540)
	size = Vector2(960, 540)
	
	if is_gallery_mode:
		match target_type:
			"enemy":
				_build_enemy_gallery()
			"vfx":
				_build_vfx_gallery()
			"projectile", "bullet":
				_build_projectile_gallery()
			"ui":
				_build_ui_gallery()
			"cultivator", _:
				_build_cultivator_gallery()
	else:
		match target_type:
			"enemy":
				_build_enemy_closeup(target_id)
			"vfx":
				_build_vfx_closeup(target_id)
			"projectile", "bullet":
				_build_projectile_closeup(target_id)
			"ui":
				_build_ui_gallery()
			"cultivator", _:
				_build_cultivator_closeup(target_id)
	
	_schedule_export()

func _parse_arguments() -> void:
	var args := OS.get_cmdline_user_args()
	var all_args := OS.get_cmdline_args()
	var combined_args := args + all_args
	
	for i in range(combined_args.size()):
		var arg: String = combined_args[i]
		if arg == "--target" and i + 1 < combined_args.size():
			target_type = combined_args[i + 1]
		elif arg == "--id" and i + 1 < combined_args.size():
			target_id = combined_args[i + 1]
		elif arg == "--scale" and i + 1 < combined_args.size():
			view_scale = float(combined_args[i + 1])
		elif arg == "--out" and i + 1 < combined_args.size():
			out_path = combined_args[i + 1]
		elif arg == "--grid":
			show_grid = true
		elif arg == "--gallery":
			is_gallery_mode = true

	if out_path == "tests/inspect/preview.png":
		if is_gallery_mode:
			out_path = "tests/inspect/%s_gallery_all.png" % target_type
		else:
			out_path = "tests/inspect/%s_%s_closeup.png" % [target_type, target_id]

func _schedule_export() -> void:
	var tree := get_tree()
	if tree == null:
		return
	
	for _frame in range(12):
		await tree.process_frame
	
	_export_snapshot()

func _export_snapshot() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("[Inspector] 错误: Headless 模式无法抓取 Viewport 纹理！请不要带 --headless 参数。")
		get_tree().quit(1)
		return
	
	var vp := get_viewport()
	if vp != null:
		var tex := vp.get_texture()
		if tex != null:
			var img := tex.get_image()
			if img != null and not img.is_empty():
				img.save_png(out_path)
				print("[Inspector] 成功导出高清截图至: %s" % out_path)
				print("INSPECTOR_RESULT: OK")
				get_tree().quit(0)
				return
	
	printerr("[Inspector] 导出失败: 无法获取视口图像。")
	get_tree().quit(1)

# ==============================================================================
# 1. 修仙者单角色 4 视角特写与全员画廊
# ==============================================================================

func _build_cultivator_closeup(cid: String) -> void:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	var cfg := CultivatorVisualConfig.get_config(cid)
	var char_name: String = cid
	var epithet: String = ""
	if CultivatorData.DEFS.has(cid):
		char_name = CultivatorData.DEFS[cid].get("name", cid)
		epithet = CultivatorData.DEFS[cid].get("epithet", "")
	
	var header := MarginContainer.new()
	header.offset_left = 24
	header.offset_top = 16
	header.offset_right = 936
	header.offset_bottom = 70
	add_child(header)
	
	var h_vbox := VBoxContainer.new()
	h_vbox.add_theme_constant_override("separation", 4)
	header.add_child(h_vbox)
	
	var title_hbox := HBoxContainer.new()
	title_hbox.add_theme_constant_override("separation", 12)
	h_vbox.add_child(title_hbox)
	
	var title_lbl := Label.new()
	title_lbl.text = "【修仙真身特写】 %s · %s" % [char_name, cid]
	GameStyle.label(title_lbl, 18, GameStyle.PAPER, 0, GameStyle.INK, true)
	title_hbox.add_child(title_lbl)
	
	if not epithet.is_empty():
		var ep_lbl := Label.new()
		ep_lbl.text = "「%s」" % epithet
		GameStyle.label(ep_lbl, 13, GameStyle.GOLD_EDGE)
		title_hbox.add_child(ep_lbl)
	
	var sub_lbl := Label.new()
	sub_lbl.text = "土豆兄弟式参数化·空洞仙侠素体 | 4 视角 3.5x 高清对齐与穿模检视"
	GameStyle.label(sub_lbl, 10, GameStyle.GREY)
	h_vbox.add_child(sub_lbl)
	
	var views_container := HBoxContainer.new()
	views_container.offset_left = 24
	views_container.offset_top = 80
	views_container.offset_right = 650
	views_container.offset_bottom = 500
	views_container.alignment = BoxContainer.ALIGNMENT_CENTER
	views_container.add_theme_constant_override("separation", 16)
	add_child(views_container)
	
	var angles := [
		{"title": "正面 (FRONT)", "angle": CultivatorRendererBase.Angle.FRONT, "action": CultivatorRendererBase.Action.IDLE, "tip": "剑柄出右肩，下端收于斗篷内"},
		{"title": "侧面 (SIDE)", "angle": CultivatorRendererBase.Angle.SIDE, "action": CultivatorRendererBase.Action.IDLE, "tip": "武器负于后背，严禁下沿戳出长脚"},
		{"title": "背面 (BACK)", "angle": CultivatorRendererBase.Angle.BACK, "action": CultivatorRendererBase.Action.IDLE, "tip": "法器最外层，斜跨背带分明"},
		{"title": "御风 (TILT)", "angle": CultivatorRendererBase.Angle.SIDE, "action": CultivatorRendererBase.Action.RUN, "tip": "侧倾与风阻浪涌，衣摆流体翻浪"}
	]
	
	for a in angles:
		var col := _create_cultivator_view_column(cfg, a["title"], a["angle"], a["action"], a["tip"])
		views_container.add_child(col)
	
	var info_panel := _create_cultivator_info_panel(cfg, cid)
	info_panel.offset_left = 666
	info_panel.offset_top = 80
	info_panel.offset_right = 936
	info_panel.offset_bottom = 510
	add_child(info_panel)

func _create_cultivator_view_column(cfg: CultivatorVisualConfig, title: String, angle: CultivatorRendererBase.Angle, action: CultivatorRendererBase.Action, tip: String) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(142, 410)
	box.add_theme_constant_override("separation", 6)
	
	var top_panel := PanelContainer.new()
	top_panel.add_theme_stylebox_override("panel", GameStyle.outlined_panel(Color(0.07, 0.09, 0.14), Color(0.18, 0.24, 0.35), 1, 0.0))
	var top_lbl := Label.new()
	top_lbl.text = title
	top_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameStyle.label(top_lbl, 11, GameStyle.PAPER, 0, GameStyle.INK, true)
	top_panel.add_child(top_lbl)
	box.add_child(top_panel)
	
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(142, 330)
	stage.clip_contents = true
	
	var stage_bg := ColorRect.new()
	stage_bg.color = Color(0.03, 0.04, 0.06)
	stage_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.add_child(stage_bg)
	
	var grid_overlay := Control.new()
	grid_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	grid_overlay.draw.connect(func():
		var w := 142.0
		var h := 330.0
		var cy := 190.0
		var cx := 71.0
		grid_overlay.draw_line(Vector2(0, cy + 50), Vector2(w, cy + 50), Color(0.2, 0.3, 0.45, 0.5), 1.0)
		grid_overlay.draw_line(Vector2(cx, 0), Vector2(cx, h), Color(0.15, 0.22, 0.35, 0.35), 1.0)
		if show_grid:
			for y in range(40, int(h), 40):
				grid_overlay.draw_line(Vector2(0, float(y)), Vector2(w, float(y)), GRID_COLOR, 0.5)
	)
	stage.add_child(grid_overlay)
	
	var ren := HollowKnightCultivatorRenderer.new(cfg)
	ren.current_angle = angle
	ren.current_action = action
	ren.position = Vector2(71, 190)
	ren.scale = Vector2(view_scale, view_scale)
	if action == CultivatorRendererBase.Action.RUN:
		ren.lean_angle = deg_to_rad(4.8)
		ren.speed_ratio = 1.0
		ren.move_dir = Vector2(0.8, 0.0)
	stage.add_child(ren)
	_cultivator_renderers.append(ren)
	
	box.add_child(stage)
	
	var tip_lbl := Label.new()
	tip_lbl.text = tip
	tip_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameStyle.label(tip_lbl, 9, GameStyle.GREY)
	box.add_child(tip_lbl)
	
	return box

func _create_cultivator_info_panel(cfg: CultivatorVisualConfig, _cid: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", GameStyle.outlined_panel(Color(0.06, 0.08, 0.12), Color(0.20, 0.28, 0.42), 1, 0.0))
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.offset_left = 12
	vbox.offset_top = 10
	vbox.offset_right = -12
	vbox.offset_bottom = -10
	panel.add_child(vbox)
	
	var head := Label.new()
	head.text = "◆ 4 大插槽参数清单"
	GameStyle.label(head, 13, GameStyle.GOLD_EDGE, 0, GameStyle.INK, true)
	vbox.add_child(head)
	
	var b_dict: Dictionary = cfg.body
	vbox.add_child(_make_kv_label("1. 体型", "缩放: %.2f | 宽: %.2f\n高: %.2f | 头身比: %.2f" % [
		b_dict.get("scale", 1.0), b_dict.get("width_scale", 1.0),
		b_dict.get("height_scale", 1.0), b_dict.get("head_scale", 1.0)
	]))
	
	var f_dict: Dictionary = cfg.face
	vbox.add_child(_make_kv_label("2. 面部", "面壳: %s\n头饰: %s\n眼眸: %s" % [
		f_dict.get("mask_style", "oval_chin"),
		f_dict.get("horns_style", "none"),
		f_dict.get("eye_style", "hollow_oval")
	]))
	
	var c_dict: Dictionary = cfg.cloak
	var c_out: Color = c_dict.get("col_outer", Color.BLACK)
	var c_inn: Color = c_dict.get("col_inner", Color.BLACK)
	var c_edg: Color = c_dict.get("col_edge", Color.BLACK)
	vbox.add_child(_make_kv_label("3. 斗篷", "款式: %s | 胸饰: %s\n外色: #%s\n内衬: #%s\n边缘: #%s" % [
		c_dict.get("cloak_style", "split_flowing"),
		c_dict.get("chest_ornament", "pearl"),
		c_out.to_html(false),
		c_inn.to_html(false),
		c_edg.to_html(false)
	]))
	
	var w_dict: Dictionary = cfg.weapon
	var w_col: Color = w_dict.get("col_main", Color.WHITE)
	vbox.add_child(_make_kv_label("4. 法器", "种类: %s\n主色: #%s\n背带: %s" % [
		w_dict.get("weapon_type", "bone_nail"),
		w_col.to_html(false),
		w_dict.get("strap_style", "diagonal")
	]))
	
	return panel

func _build_cultivator_gallery() -> void:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	
	var title_lbl := Label.new()
	title_lbl.text = "剑士 · 全道统修仙角色动态全景走廊画廊 (全量 %d 位)" % CultivatorData.DEFS.size()
	title_lbl.position = Vector2(24, 12)
	GameStyle.label(title_lbl, 16, GameStyle.PAPER, 0, GameStyle.INK, true)
	root.add_child(title_lbl)
	
	var sub_lbl := Label.new()
	sub_lbl.text = "纯代码参数化矢量驱动 · 正面 / 侧面背剑 / 背面全貌统一对齐"
	sub_lbl.position = Vector2(24, 34)
	GameStyle.label(sub_lbl, 10, GameStyle.GOLD_EDGE)
	root.add_child(sub_lbl)
	
	var cols := 5
	var card_w := 174.0
	var card_h := 106.0
	var pad_x := 8.0
	var pad_y := 6.0
	var start_x := 25.0
	var start_y := 56.0
	
	var keys: Array = CultivatorData.DEFS.keys()
	for i in keys.size():
		var cid: String = String(keys[i])
		var c := i % cols
		var r := i / cols
		var pos := Vector2(start_x + c * (card_w + pad_x), start_y + r * (card_h + pad_y))
		
		var card := _build_cultivator_gallery_card(cid, card_w, card_h)
		card.position = pos
		root.add_child(card)

func _build_cultivator_gallery_card(cid: String, cw: float, ch: float) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(cw, ch)
	card.add_theme_stylebox_override("panel", GameStyle.outlined_panel(Color(0.07, 0.09, 0.14), Color(0.18, 0.24, 0.35), 1, 0.0))
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.offset_left = 4
	vbox.offset_top = 4
	vbox.offset_right = -4
	vbox.offset_bottom = -4
	card.add_child(vbox)
	
	var def: Dictionary = CultivatorData.DEFS.get(cid, {})
	var cname: String = def.get("name", cid)
	
	var title_lbl := Label.new()
	title_lbl.text = "%s (%s)" % [cname, cid]
	GameStyle.label(title_lbl, 10, GameStyle.PAPER, 0, GameStyle.INK, true)
	vbox.add_child(title_lbl)
	
	var vp_box := HBoxContainer.new()
	vp_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vp_box.add_theme_constant_override("separation", 6)
	vp_box.custom_minimum_size = Vector2(0, 78)
	vbox.add_child(vp_box)
	
	var cfg := CultivatorVisualConfig.get_config(cid)
	var perspectives := [
		{"angle": CultivatorRendererBase.Angle.FRONT},
		{"angle": CultivatorRendererBase.Angle.SIDE},
		{"angle": CultivatorRendererBase.Angle.BACK}
	]
	
	for p in perspectives:
		var c_view := Control.new()
		c_view.custom_minimum_size = Vector2(48, 76)
		c_view.clip_contents = true
		
		var ren := HollowKnightCultivatorRenderer.new(cfg)
		ren.current_angle = p["angle"]
		ren.position = Vector2(24, 48)
		ren.scale = Vector2(0.9, 0.9)
		c_view.add_child(ren)
		_cultivator_renderers.append(ren)
		
		vp_box.add_child(c_view)
	
	return card

# ==============================================================================
# 2. 妖魔拟态特写与全景 (动态拉取全部 17 种妖魔)
# ==============================================================================

func _build_enemy_closeup(eid: String) -> void:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	var cfg := EnemyVisualConfig.get_config(eid)
	var ename: String = cfg.display_name if not cfg.display_name.is_empty() else eid
	
	var header := MarginContainer.new()
	header.offset_left = 24
	header.offset_top = 16
	header.offset_right = 936
	header.offset_bottom = 70
	add_child(header)
	
	var h_vbox := VBoxContainer.new()
	h_vbox.add_theme_constant_override("separation", 4)
	header.add_child(h_vbox)
	
	var title_hbox := HBoxContainer.new()
	title_hbox.add_theme_constant_override("separation", 12)
	h_vbox.add_child(title_hbox)
	
	var title_lbl := Label.new()
	title_lbl.text = "【妖魔拟态特写】 %s · %s" % [ename, eid]
	GameStyle.label(title_lbl, 18, GameStyle.PAPER, 0, GameStyle.INK, true)
	title_hbox.add_child(title_lbl)
	
	var tag_text := "精英" if cfg.is_elite else ("妖王Boss" if cfg.is_boss else "普通妖魔")
	var tag_lbl := Label.new()
	tag_lbl.text = "「%s」" % tag_text
	GameStyle.label(tag_lbl, 13, GameStyle.GOLD_EDGE)
	title_hbox.add_child(tag_lbl)
	
	var sub_lbl := Label.new()
	sub_lbl.text = "冷冽空洞国风程序化妖魔渲染管线 | 动态骨甲、虚空与灵核高光检视"
	GameStyle.label(sub_lbl, 10, GameStyle.GREY)
	h_vbox.add_child(sub_lbl)
	
	var views_container := HBoxContainer.new()
	views_container.offset_left = 24
	views_container.offset_top = 80
	views_container.offset_right = 650
	views_container.offset_bottom = 500
	views_container.alignment = BoxContainer.ALIGNMENT_CENTER
	views_container.add_theme_constant_override("separation", 20)
	add_child(views_container)
	
	var modes := [
		{"title": "静止正向 (IDLE)", "moving": false, "flip": false, "tip": "灵核幽火呼吸与周天环绕"},
		{"title": "御风移动 (MOVING)", "moving": true, "flip": false, "tip": "流体行波爬行/振翅疾飞/前倾"},
		{"title": "折返镜像 (FLIP_H)", "moving": true, "flip": true, "tip": "水平左右转向轴心镜像对称"}
	]
	
	for m in modes:
		var col := _create_enemy_view_column(cfg, m["title"], m["moving"], m["flip"], m["tip"])
		views_container.add_child(col)
	
	var info_panel := _create_enemy_info_panel(cfg, eid)
	info_panel.offset_left = 666
	info_panel.offset_top = 80
	info_panel.offset_right = 936
	info_panel.offset_bottom = 510
	add_child(info_panel)

func _create_enemy_view_column(cfg: EnemyVisualConfig, title: String, is_moving: bool, flip_h: bool, tip: String) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(190, 410)
	box.add_theme_constant_override("separation", 6)
	
	var top_panel := PanelContainer.new()
	top_panel.add_theme_stylebox_override("panel", GameStyle.outlined_panel(Color(0.07, 0.09, 0.14), Color(0.18, 0.24, 0.35), 1, 0.0))
	var top_lbl := Label.new()
	top_lbl.text = title
	top_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameStyle.label(top_lbl, 11, GameStyle.PAPER, 0, GameStyle.INK, true)
	top_panel.add_child(top_lbl)
	box.add_child(top_panel)
	
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(190, 330)
	stage.clip_contents = true
	
	var stage_bg := ColorRect.new()
	stage_bg.color = Color(0.03, 0.04, 0.06)
	stage_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.add_child(stage_bg)
	
	var ren := HollowKnightEnemyRenderer.new()
	ren.config = cfg
	ren.is_moving = is_moving
	ren.flip_h = flip_h
	ren.position = Vector2(95, 180)
	var sc: float = 3.2
	ren.scale = Vector2(sc, sc)
	stage.add_child(ren)
	_enemy_renderers.append(ren)
	
	box.add_child(stage)
	
	var tip_lbl := Label.new()
	tip_lbl.text = tip
	tip_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameStyle.label(tip_lbl, 9, GameStyle.GREY)
	box.add_child(tip_lbl)
	
	return box

func _create_enemy_info_panel(cfg: EnemyVisualConfig, _eid: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", GameStyle.outlined_panel(Color(0.06, 0.08, 0.12), Color(0.20, 0.28, 0.42), 1, 0.0))
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.offset_left = 12
	vbox.offset_top = 10
	vbox.offset_right = -12
	vbox.offset_bottom = -10
	panel.add_child(vbox)
	
	var head := Label.new()
	head.text = "◆ 妖魔外观参数清单"
	GameStyle.label(head, 13, GameStyle.GOLD_EDGE, 0, GameStyle.INK, true)
	vbox.add_child(head)
	
	var loco_str := "悬浮御风 (HOVER)"
	if cfg.locomotion == EnemyVisualConfig.LocomotionType.FLIGHT:
		loco_str = "振翅疾飞 (FLIGHT)"
	elif cfg.locomotion == EnemyVisualConfig.LocomotionType.CRAWL:
		loco_str = "贴地蠕动 (CRAWL)"
	
	vbox.add_child(_make_kv_label("1. 运动型态", loco_str))
	vbox.add_child(_make_kv_label("2. 尺寸几何", "碰撞半径: %.1f px\n缩放系数: %.2f" % [cfg.body_radius, cfg.scale_factor]))
	vbox.add_child(_make_kv_label("3. 五官挂饰", "灵眸款式: %s\n专属饰物: %s" % [cfg.eye_type, cfg.ornament_type]))
	vbox.add_child(_make_kv_label("4. 冷冽色阶", "主躯: #%s\n骨甲: #%s\n辉光: #%s" % [
		cfg.col_primary.to_html(false),
		cfg.col_secondary.to_html(false),
		cfg.col_glow.to_html(false)
	]))
	
	return panel

func _build_enemy_gallery() -> void:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	
	var all_enemy_ids: Array = EnemyGuideData.catalog_ids()
	
	var title_lbl := Label.new()
	title_lbl.text = "剑士 · 妖魔万象动态全景画廊 (全量 %d 种)" % all_enemy_ids.size()
	title_lbl.position = Vector2(24, 12)
	GameStyle.label(title_lbl, 16, GameStyle.PAPER, 0, GameStyle.INK, true)
	root.add_child(title_lbl)
	
	var sub_lbl := Label.new()
	sub_lbl.text = "空洞冷冽国风妖魔拟态 · 包含常规 12 妖、3 大精英、赤炎魔将与衔宝金蟾"
	sub_lbl.position = Vector2(24, 34)
	GameStyle.label(sub_lbl, 10, GameStyle.GOLD_EDGE)
	root.add_child(sub_lbl)
	
	var cols := 6
	var card_w := 145.0
	var card_h := 142.0
	var pad_x := 8.0
	var pad_y := 6.0
	var start_x := 25.0
	var start_y := 56.0
	
	for i in all_enemy_ids.size():
		var eid: String = String(all_enemy_ids[i])
		var c := i % cols
		var r := i / cols
		var pos := Vector2(start_x + c * (card_w + pad_x), start_y + r * (card_h + pad_y))
		
		var card := _build_enemy_gallery_card(eid, card_w, card_h)
		card.position = pos
		root.add_child(card)

func _build_enemy_gallery_card(eid: String, cw: float, ch: float) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(cw, ch)
	card.add_theme_stylebox_override("panel", GameStyle.outlined_panel(Color(0.07, 0.09, 0.14), Color(0.18, 0.24, 0.35), 1, 0.0))
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.offset_left = 4
	vbox.offset_top = 4
	vbox.offset_right = -4
	vbox.offset_bottom = -4
	card.add_child(vbox)
	
	var cfg := EnemyVisualConfig.get_config(eid)
	var title_lbl := Label.new()
	var dname: String = EnemyGuideData.display_name(eid)
	title_lbl.text = "%s (%s)" % [dname, eid]
	GameStyle.label(title_lbl, 10, GameStyle.PAPER, 0, GameStyle.INK, true)
	vbox.add_child(title_lbl)
	
	var vp := Control.new()
	vp.custom_minimum_size = Vector2(cw - 8, ch - 24)
	vp.clip_contents = true
	
	var ren := HollowKnightEnemyRenderer.new()
	ren.config = cfg
	ren.is_moving = true
	ren.position = Vector2((cw - 8) / 2.0, (ch - 24) / 2.0 + 4)
	ren.scale = Vector2(1.15, 1.15)
	vp.add_child(ren)
	_enemy_renderers.append(ren)
	
	vbox.add_child(vp)
	return card

# ==============================================================================
# 3. 武器攻击特效与元素法相 (VFX Gallery & Closeup)
# ==============================================================================

func _build_vfx_gallery() -> void:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	
	var title_lbl := Label.new()
	title_lbl.text = "剑士 · 武器攻击特效与元素法相全景画廊 (VFX Gallery)"
	title_lbl.position = Vector2(24, 12)
	GameStyle.label(title_lbl, 16, GameStyle.PAPER, 0, GameStyle.INK, true)
	root.add_child(title_lbl)
	
	var sub_lbl := Label.new()
	sub_lbl.text = "纯代码 _draw 几何判定同源 · 六元素近战刀光 / 六元素横扫扇面 / 贯日紫光束 / 三昧真火锥 / 六道法印爆发"
	sub_lbl.position = Vector2(24, 32)
	GameStyle.label(sub_lbl, 10, GameStyle.GOLD_EDGE)
	root.add_child(sub_lbl)
	
	var elems := ["metal", "fire", "water", "wood", "earth", "thunder"]
	var elem_names := ["金·锐金", "火·炽焰", "水·玄冰", "木·荆棘", "土·重岩", "雷·紫电"]
	
	# 上排：六元素近战刀光 (MELEE)
	var row1_lbl := Label.new()
	row1_lbl.text = "◆ 六元素近战挥砍弧光 (MELEE)"
	row1_lbl.position = Vector2(24, 52)
	GameStyle.label(row1_lbl, 11, GameStyle.JADE, 0, GameStyle.INK, true)
	root.add_child(row1_lbl)
	
	for i in elems.size():
		var pos := Vector2(65 + i * 148, 115)
		var arc := WeaponArcRenderer.new()
		arc.configure(WeaponArcRenderer.ArcMode.MELEE, elems[i])
		arc.position = pos
		arc.scale = Vector2.ONE * 0.44
		arc.visible = true
		arc.modulate.a = 1.0
		root.add_child(arc)
		_vfx_nodes.append(arc)
		
		var lbl := Label.new()
		lbl.text = elem_names[i]
		lbl.position = pos + Vector2(-36, 32)
		GameStyle.label(lbl, 9, GameStyle.PAPER_DIM)
		root.add_child(lbl)
	
	# 中排：六元素横扫扇面 (SWEEP)
	var row2_lbl := Label.new()
	row2_lbl.text = "◆ 六元素横扫大范围扇面 (SWEEP)"
	row2_lbl.position = Vector2(24, 185)
	GameStyle.label(row2_lbl, 11, GameStyle.JADE, 0, GameStyle.INK, true)
	root.add_child(row2_lbl)
	
	for i in elems.size():
		var pos := Vector2(65 + i * 148, 250)
		var fan := WeaponArcRenderer.new()
		fan.configure(WeaponArcRenderer.ArcMode.SWEEP, elems[i])
		fan.position = pos
		fan.scale = Vector2.ONE * 0.44
		fan.visible = true
		fan.modulate.a = 1.0
		root.add_child(fan)
		_vfx_nodes.append(fan)
		
		var lbl := Label.new()
		lbl.text = elem_names[i]
		lbl.position = pos + Vector2(-36, 32)
		GameStyle.label(lbl, 9, GameStyle.PAPER_DIM)
		root.add_child(lbl)
	
	# 下排：持续攻击 (Beam & Cone) + 6 种 BURST 落地法阵
	var row3_lbl := Label.new()
	row3_lbl.text = "◆ 持续贯通攻击 (BEAM/CONE) 与 六道法印落点形态 (BURST)"
	row3_lbl.position = Vector2(24, 325)
	GameStyle.label(row3_lbl, 11, GameStyle.JADE, 0, GameStyle.INK, true)
	root.add_child(row3_lbl)
	
	# 1. 激光光束
	var beam := BeamRenderer.new()
	beam.position = Vector2(30, 395)
	root.add_child(beam)
	beam.beam_on(150.0, 7.5, Color(0.75, 0.55, 1.0))
	_vfx_nodes.append(beam)
	var beam_lbl := Label.new()
	beam_lbl.text = "紫虹镜 · 光束"
	beam_lbl.position = Vector2(30, 420)
	GameStyle.label(beam_lbl, 9, GameStyle.PAPER_DIM)
	root.add_child(beam_lbl)
	
	# 2. 喷火锥
	var cone := FlameConeRenderer.new()
	cone.position = Vector2(210, 395)
	root.add_child(cone)
	cone.cone_on(110.0, 50.0)
	_vfx_nodes.append(cone)
	var cone_lbl := Label.new()
	cone_lbl.text = "真火 · 烈焰锥"
	cone_lbl.position = Vector2(210, 420)
	GameStyle.label(cone_lbl, 9, GameStyle.PAPER_DIM)
	root.add_child(cone_lbl)
	
	# 3. BURST 落地法相 6 种
	var burst_kinds := ["fire_rain", "frost", "sonic", "drum", "earth", "seal"]
	var burst_names := ["火雨法阵", "玄冰霜煞", "音波震环", "春雷天鼓", "地裂岩突", "镇魔封印"]
	var tints := [Color(1.0, 0.52, 0.18), Color(0.45, 0.75, 1.0), Color(0.35, 0.75, 1.0),
		Color(0.5, 0.85, 0.5), Color(0.80, 0.66, 0.38), Color(0.88, 0.74, 0.46)]
	
	for i in burst_kinds.size():
		var bx := 370 + (i % 3) * 185
		var by := 390 + (i / 3) * 85
		var fx := BurstKindFx.new()
		fx.position = Vector2(bx, by)
		root.add_child(fx)
		fx.activate_fx(burst_kinds[i], 32.0, tints[i])
		_vfx_nodes.append(fx)
		
		var blbl := Label.new()
		blbl.text = burst_names[i]
		blbl.position = Vector2(bx - 26, by + 30)
		GameStyle.label(blbl, 9, GameStyle.PAPER_DIM)
		root.add_child(blbl)

func _build_vfx_closeup(vfx_id: String) -> void:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	var title_lbl := Label.new()
	title_lbl.text = "【特效法相特写】 %s" % vfx_id
	title_lbl.position = Vector2(24, 20)
	GameStyle.label(title_lbl, 18, GameStyle.PAPER, 0, GameStyle.INK, true)
	add_child(title_lbl)
	
	var center := Vector2(480, 270)
	if vfx_id.ends_with("_sweep"):
		var elem := vfx_id.trim_suffix("_sweep")
		var fan := WeaponArcRenderer.new()
		fan.configure(WeaponArcRenderer.ArcMode.SWEEP, elem)
		fan.position = center
		fan.scale = Vector2.ONE * 1.5
		fan.visible = true
		fan.modulate.a = 1.0
		add_child(fan)
	elif vfx_id.ends_with("_slash") or vfx_id in ["metal", "fire", "water", "wood", "earth", "thunder"]:
		var elem := vfx_id.trim_suffix("_slash")
		var arc := WeaponArcRenderer.new()
		arc.configure(WeaponArcRenderer.ArcMode.MELEE, elem)
		arc.position = center
		arc.scale = Vector2.ONE * 1.5
		arc.visible = true
		arc.modulate.a = 1.0
		add_child(arc)
	elif vfx_id == "beam":
		var beam := BeamRenderer.new()
		beam.position = Vector2(240, 270)
		add_child(beam)
		beam.beam_on(480.0, 16.0, Color(0.75, 0.55, 1.0))
	elif vfx_id == "cone" or vfx_id == "flame_cone":
		var cone := FlameConeRenderer.new()
		cone.position = Vector2(260, 270)
		add_child(cone)
		cone.cone_on(350.0, 150.0)
	else:
		var fx := BurstKindFx.new()
		fx.position = center
		add_child(fx)
		fx.activate_fx(vfx_id, 90.0, Color(1.0, 0.65, 0.25))

# ==============================================================================
# 4. 飞行物与弹丸 (Projectile Gallery & Closeup)
# ==============================================================================

func _build_projectile_gallery() -> void:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	
	var title_lbl := Label.new()
	title_lbl.text = "剑士 · 全量法器飞行物与弹道纯矢量画廊 (Projectile Gallery)"
	title_lbl.position = Vector2(24, 12)
	GameStyle.label(title_lbl, 16, GameStyle.PAPER, 0, GameStyle.INK, true)
	root.add_child(title_lbl)
	
	var sub_lbl := Label.new()
	sub_lbl.text = "纯代码 CanvasItem 矢量绘制 · 高频无损旋转、精准物理咬合、动态流光与气刃尾迹"
	sub_lbl.position = Vector2(24, 32)
	GameStyle.label(sub_lbl, 10, GameStyle.GOLD_EDGE)
	root.add_child(sub_lbl)
	
	var kinds := [
		{"kind": ProceduralProjectileRenderer.ProjectileKind.SWORD_GOLD, "name": "庚金飞剑", "tag": "双刃金剑"},
		{"kind": ProceduralProjectileRenderer.ProjectileKind.SWORD_FIRE, "name": "流火飞剑", "tag": "烧刃火剑"},
		{"kind": ProceduralProjectileRenderer.ProjectileKind.DAGGER_LEAF, "name": "柳叶飞刀", "tag": "青金弯月"},
		{"kind": ProceduralProjectileRenderer.ProjectileKind.NEEDLE_SILVER, "name": "暴雨银针", "tag": "破空银芒"},
		{"kind": ProceduralProjectileRenderer.ProjectileKind.NEEDLE_GOLD, "name": "庚金金针", "tag": "金煞细丝"},
		{"kind": ProceduralProjectileRenderer.ProjectileKind.NEEDLE_ICE, "name": "玄冰飞针", "tag": "透骨冰棱"},
		{"kind": ProceduralProjectileRenderer.ProjectileKind.BONE_SPIKE, "name": "白骨煞刺", "tag": "森白骨煞"},
		{"kind": ProceduralProjectileRenderer.ProjectileKind.TALISMAN_FIRE, "name": "火焰符", "tag": "离火朱砂"},
		{"kind": ProceduralProjectileRenderer.ProjectileKind.TALISMAN_TRUE_FIRE, "name": "真火符", "tag": "三昧真火"},
		{"kind": ProceduralProjectileRenderer.ProjectileKind.TALISMAN_THUNDER_FIRE, "name": "雷火符", "tag": "雷弧火舌"},
		{"kind": ProceduralProjectileRenderer.ProjectileKind.TALISMAN_WOOD, "name": "万木灵符", "tag": "碧翠生机"},
		{"kind": ProceduralProjectileRenderer.ProjectileKind.TALISMAN_GU, "name": "蛊毒符", "tag": "幽绿毒雾"},
		{"kind": ProceduralProjectileRenderer.ProjectileKind.TALISMAN_JINGZHE, "name": "惊蛰符", "tag": "青碧春雷"},
		{"kind": ProceduralProjectileRenderer.ProjectileKind.TALISMAN_GOLD, "name": "庚金符", "tag": "月白锐金"},
		{"kind": ProceduralProjectileRenderer.ProjectileKind.TALISMAN_EARTH, "name": "厚土符", "tag": "黄褐地煞"},
		{"kind": ProceduralProjectileRenderer.ProjectileKind.TALISMAN_ICE, "name": "玄冰符", "tag": "霜蓝极寒"},
		{"kind": ProceduralProjectileRenderer.ProjectileKind.TALISMAN_FROST, "name": "癸水符", "tag": "玄阴水滴"},
		{"kind": ProceduralProjectileRenderer.ProjectileKind.TALISMAN_STONE, "name": "镇山符", "tag": "重石碑印"},
		{"kind": ProceduralProjectileRenderer.ProjectileKind.FIRE_FLAME, "name": "烈焰火煞", "tag": "炽金火核"},
		{"kind": ProceduralProjectileRenderer.ProjectileKind.SPIRIT_PELLET, "name": "连环灵弹", "tag": "翡翠星轨"},
		{"kind": ProceduralProjectileRenderer.ProjectileKind.WATER_SHUTTLE, "name": "浪里梭", "tag": "浪涛丝痕"},
	]
	
	var cols := 7
	var card_w := 122.0
	var card_h := 142.0
	var pad_x := 6.0
	var pad_y := 6.0
	var start_x := 35.0
	var start_y := 56.0
	
	for i in kinds.size():
		var c := i % cols
		var r := i / cols
		var pos := Vector2(start_x + c * (card_w + pad_x), start_y + r * (card_h + pad_y))
		
		var panel := PanelContainer.new()
		panel.position = pos
		panel.custom_minimum_size = Vector2(card_w, card_h)
		panel.add_theme_stylebox_override("panel", GameStyle.outlined_panel(Color(0.07, 0.09, 0.14), Color(0.18, 0.24, 0.35), 1, 0.0))
		root.add_child(panel)
		
		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 2)
		vbox.offset_left = 4
		vbox.offset_top = 4
		vbox.offset_right = -4
		vbox.offset_bottom = -4
		panel.add_child(vbox)
		
		var name_lbl := Label.new()
		name_lbl.text = kinds[i]["name"]
		GameStyle.label(name_lbl, 10, GameStyle.PAPER, 0, GameStyle.INK, true)
		vbox.add_child(name_lbl)
		
		var tag_lbl := Label.new()
		tag_lbl.text = kinds[i]["tag"]
		GameStyle.label(tag_lbl, 8, GameStyle.JADE)
		vbox.add_child(tag_lbl)
		
		var stage := Control.new()
		stage.custom_minimum_size = Vector2(card_w - 8, 92)
		stage.clip_contents = true
		vbox.add_child(stage)
		
		var pr := ProceduralProjectileRenderer.new()
		pr.kind = kinds[i]["kind"]
		pr.position = Vector2((card_w - 8) / 2.0, 46)
		pr.rotation = -PI * 0.25
		pr.scale = Vector2.ONE * 1.8
		stage.add_child(pr)

func _build_projectile_closeup(pid: String) -> void:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	var title_lbl := Label.new()
	title_lbl.text = "【弹道飞行物矢量特写】 %s" % pid
	title_lbl.position = Vector2(24, 20)
	GameStyle.label(title_lbl, 18, GameStyle.PAPER, 0, GameStyle.INK, true)
	add_child(title_lbl)
	
	var pr := ProceduralProjectileRenderer.new()
	pr.kind = ProceduralProjectileRenderer.detect_kind_from_path(pid)
	pr.position = Vector2(480, 270)
	pr.rotation = -PI * 0.25
	pr.scale = Vector2.ONE * 5.0
	add_child(pr)

# ==============================================================================
# 5. 界面组件与样式样张 (UI Gallery)
# ==============================================================================

func _build_ui_gallery() -> void:
	var bg := ColorRect.new()
	bg.color = GameStyle.INK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	# 标题大匾
	var title := PanelContainer.new()
	title.position = Vector2(260, 16)
	var tst := GameStyle.block(GameStyle.GOLD, GameStyle.SLANT_BLOCK, Vector2(8, 9))
	tst.content_margin_left = 24.0
	tst.content_margin_top = 6.0
	tst.content_margin_right = 24.0
	tst.content_margin_bottom = 8.0
	title.add_theme_stylebox_override("panel", tst)
	GameStyle.halftone(title, Color(0.95, 0.98, 1.0, 0.14))
	var tl := Label.new()
	tl.text = "修 仙 幸 存 者 · UI 视 觉 规 范 样 张"
	GameStyle.label(tl, 20, GameStyle.INK_TEXT, 0, GameStyle.INK, true)
	title.add_child(tl)
	add_child(title)
	
	# 五档色带卡
	var accents := [GameStyle.RARITY_COMMON, GameStyle.RARITY_RARE, GameStyle.RARITY_EPIC,
		GameStyle.RARITY_LEGEND, GameStyle.GOLD]
	var names := ["普通 (Common)", "稀有 (Rare)", "史诗 (Epic)", "传说 (Legend)", "选中 (Selected ✦)"]
	for i in range(accents.size()):
		var c := PanelContainer.new()
		c.position = Vector2(40 + i * 178.0, 75)
		c.custom_minimum_size = Vector2(166, 125)
		var st := GameStyle.card(accents[i])
		st.content_margin_left = 10.0
		st.content_margin_top = 8.0
		c.add_theme_stylebox_override("panel", st)
		
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		var nl := Label.new()
		nl.text = names[i]
		GameStyle.label(nl, 12, GameStyle.PAPER, 0, GameStyle.INK, true)
		v.add_child(nl)
		
		var dl := Label.new()
		dl.text = "无圆角无渐变\n斜切平行四边形\n深蓝底 + 纸白字"
		GameStyle.label(dl, 10, GameStyle.PAPER_DIM)
		v.add_child(dl)
		
		var chip := Label.new()
		chip.text = " 剑系 · 金 "
		chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		chip.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.JADE_DK))
		GameStyle.label(chip, 9, GameStyle.JADE)
		v.add_child(chip)
		
		c.add_child(v)
		add_child(c)
	
	# 按钮组件体系
	var btn_lbl := Label.new()
	btn_lbl.text = "◆ 按钮规范：主行动灵金 / 次要墨底 / 危险朱砂"
	btn_lbl.position = Vector2(40, 220)
	GameStyle.label(btn_lbl, 11, GameStyle.JADE, 0, GameStyle.INK, true)
	add_child(btn_lbl)
	
	var b1 := Button.new()
	b1.text = "主 行 动 按 钮"
	b1.position = Vector2(40, 245)
	b1.custom_minimum_size = Vector2(200, 42)
	GameStyle.button(b1, GameStyle.GOLD, GameStyle.GOLD_EDGE, 14, GameStyle.INK_TEXT)
	add_child(b1)
	
	var b2 := Button.new()
	b2.text = "次 要 功 能"
	b2.position = Vector2(260, 245)
	b2.custom_minimum_size = Vector2(170, 42)
	GameStyle.button(b2, GameStyle.NAVY2, GameStyle.GOLD, 13, GameStyle.PAPER)
	add_child(b2)
	
	var b3 := Button.new()
	b3.text = "重 修 / 兵 解"
	b3.position = Vector2(450, 245)
	b3.custom_minimum_size = Vector2(160, 42)
	GameStyle.button(b3, GameStyle.BAD, GameStyle.JADE, 13, GameStyle.PAPER)
	add_child(b3)
	
	# 弹窗、侧签与进度条
	var dlg_lbl := Label.new()
	dlg_lbl.text = "◆ 弹窗面板 (Dialog Panel)、侧签行 (Side Card) 与 进度条 (Progress Bar)"
	dlg_lbl.position = Vector2(40, 310)
	GameStyle.label(dlg_lbl, 11, GameStyle.JADE, 0, GameStyle.INK, true)
	add_child(dlg_lbl)
	
	var dlg := PanelContainer.new()
	dlg.position = Vector2(40, 335)
	dlg.custom_minimum_size = Vector2(440, 150)
	dlg.add_theme_stylebox_override("panel", GameStyle.dialog_panel())
	
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 8)
	dv.offset_left = 14
	dv.offset_top = 14
	dv.offset_right = -14
	dv.offset_bottom = -14
	
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(410, 28)
	var rst := GameStyle.side_card(GameStyle.JADE, 0.0)
	rst.content_margin_left = 10.0
	row.add_theme_stylebox_override("panel", rst)
	var rl := Label.new()
	rl.text = "青玉侧签行 · 灵石 12847 · 悟道点数 5"
	GameStyle.label(rl, 12, GameStyle.PAPER)
	row.add_child(rl)
	dv.add_child(row)
	
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(410, 16)
	bar.max_value = 100
	bar.value = 68
	bar.show_percentage = false
	var bs := GameStyle.bar_styles(GameStyle.INK, GameStyle.GOLD)
	bar.add_theme_stylebox_override("background", bs[0])
	bar.add_theme_stylebox_override("fill", bs[1])
	dv.add_child(bar)
	
	var bar_desc := Label.new()
	bar_desc.text = "修为凝练进度: 68% (距离下一重境界尚需 320 经验)"
	GameStyle.label(bar_desc, 10, GameStyle.PAPER_DIM)
	dv.add_child(bar_desc)
	
	dlg.add_child(dv)
	add_child(dlg)

func _make_kv_label(category: String, content: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var cat_lbl := Label.new()
	cat_lbl.text = category
	GameStyle.label(cat_lbl, 11, GameStyle.JADE, 0, GameStyle.INK, true)
	box.add_child(cat_lbl)
	var val_lbl := Label.new()
	val_lbl.text = content
	GameStyle.label(val_lbl, 9, GameStyle.PAPER)
	box.add_child(val_lbl)
	return box
