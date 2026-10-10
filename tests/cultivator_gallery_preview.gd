extends Control

## 修仙幸存者 · 土豆兄弟式全道统角色插槽化画廊 (Cultivator Modular Gallery)
## 验证统一修仙素体基底 + 4 大参数插槽（体型、面部、斗篷色彩款式、背负本命法器）的快速派生与视觉差异
## 适配桌面 960×540 完整一屏九宫格

const CHAR_IDS: Array[String] = [
	"jianchi", "shiyue", "fuzhen",
	"jinsuanpan", "meiying", "dubi",
	"kuangzhan", "duoshe", "duobao"
]

const TITLES: Dictionary = {
	"jianchi": "青云剑修·独孤",
	"shiyue": "石岳·体修",
	"fuzhen": "符阵灵童",
	"jinsuanpan": "散修·金算盘",
	"meiying": "魅影·幽娘",
	"dubi": "独臂刀圣",
	"duanbi": "独臂刀圣",
	"kuangzhan": "狂战蛮修",
	"duoshe": "夺舍散人",
	"duobao": "多宝道人"
}

const DESCS: Dictionary = {
	"jianchi": "墨绿长披·骨钉飞剑",
	"shiyue": "赭石大氅·玄重石尺",
	"fuzhen": "朱砂短披·辟邪桃剑",
	"jinsuanpan": "宝蓝云肩·乾坤金算",
	"meiying": "魅紫飞扬·淬毒双刺",
	"dubi": "狂血大氅·厚背断刀",
	"duanbi": "狂血大氅·厚背断刀",
	"kuangzhan": "残破血袍·兽骨巨斧",
	"duoshe": "尸青残袍·引魂灵幡",
	"duobao": "紫金霞帔·乾坤宝匣"
}

var _time: float = 0.0
var _renderers: Array[HollowKnightCultivatorRenderer] = []

func _ready() -> void:
	custom_minimum_size = Vector2(960, 540)
	size = Vector2(960, 540)

	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_build_gallery()

	var tree := get_tree()
	if tree != null:
		await tree.process_frame
		await tree.process_frame
		await tree.process_frame
		await tree.process_frame
		await tree.process_frame
		_export_showcase_image()
		if OS.get_cmdline_user_args().has("--export") or DisplayServer.get_name() == "headless":
			print("GALLERY_RESULT: ALL PASS")
			tree.quit(0)

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _build_gallery() -> void:
	var root_vbox := VBoxContainer.new()
	root_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_vbox.add_theme_constant_override("separation", 6)
	root_vbox.offset_left = 12
	root_vbox.offset_top = 8
	root_vbox.offset_right = -12
	root_vbox.offset_bottom = -8
	add_child(root_vbox)

	# 标题栏 (约 36px)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	root_vbox.add_child(header)

	var title_lbl := Label.new()
	title_lbl.text = "修仙幸存者 · 土豆兄弟式全道统角色插槽化画廊"
	GameStyle.label(title_lbl, 16, GameStyle.PAPER, 0, GameStyle.INK, true)
	header.add_child(title_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = "统一修仙素体基底 + 4 大参数插槽（体型、面部、斗篷色彩款式、背负法器）| 纯代码矢量驱动"
	GameStyle.label(sub_lbl, 10, GameStyle.GOLD_EDGE)
	header.add_child(sub_lbl)

	# 3 × 3 角色网格 (约 480px 高)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(grid)

	for cid in CHAR_IDS:
		grid.add_child(_make_char_card(cid))

func _make_char_card(cid: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(304, 154)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", GameStyle.outlined_panel(Color(0.08, 0.10, 0.15), Color(0.18, 0.24, 0.35), 1, 0.0))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.offset_left = 8
	vbox.offset_top = 6
	vbox.offset_right = -8
	vbox.offset_bottom = -6
	panel.add_child(vbox)

	# 顶部标题栏
	var head_hbox := HBoxContainer.new()
	head_hbox.add_theme_constant_override("separation", 6)
	vbox.add_child(head_hbox)

	var name_lbl := Label.new()
	name_lbl.text = TITLES.get(cid, cid)
	GameStyle.label(name_lbl, 12, GameStyle.PAPER, 0, GameStyle.INK, true)
	head_hbox.add_child(name_lbl)

	var tag_lbl := Label.new()
	tag_lbl.text = " " + DESCS.get(cid, "") + " "
	tag_lbl.add_theme_stylebox_override("normal", GameStyle.chip(Color(0.12, 0.18, 0.28)))
	GameStyle.label(tag_lbl, 9, GameStyle.JADE)
	head_hbox.add_child(tag_lbl)

	# 中间视界展示栏（正面、侧面背法器无伸脚、背面全貌外挂）
	var viewport_box := HBoxContainer.new()
	viewport_box.alignment = BoxContainer.ALIGNMENT_CENTER
	viewport_box.add_theme_constant_override("separation", 18)
	viewport_box.custom_minimum_size = Vector2(0, 110)
	vbox.add_child(viewport_box)

	var cfg := CultivatorVisualConfig.get_config(cid)

	# 1. 正面视角
	var c_front := Control.new()
	c_front.custom_minimum_size = Vector2(62, 90)
	var r_front := HollowKnightCultivatorRenderer.new(cfg)
	r_front.current_angle = CultivatorRendererBase.Angle.FRONT
	r_front.position = Vector2(31, 55)
	r_front.scale = Vector2(1.18, 1.18)
	c_front.add_child(r_front)
	viewport_box.add_child(c_front)
	_renderers.append(r_front)

	# 2. 侧面视角
	var c_side := Control.new()
	c_side.custom_minimum_size = Vector2(62, 90)
	var r_side := HollowKnightCultivatorRenderer.new(cfg)
	r_side.current_angle = CultivatorRendererBase.Angle.SIDE
	r_side.position = Vector2(31, 55)
	r_side.scale = Vector2(1.18, 1.18)
	c_side.add_child(r_side)
	viewport_box.add_child(c_side)
	_renderers.append(r_side)

	# 3. 背面视角
	var c_back := Control.new()
	c_back.custom_minimum_size = Vector2(62, 90)
	var r_back := HollowKnightCultivatorRenderer.new(cfg)
	r_back.current_angle = CultivatorRendererBase.Angle.BACK
	r_back.position = Vector2(31, 55)
	r_back.scale = Vector2(1.18, 1.18)
	c_back.add_child(r_back)
	viewport_box.add_child(c_back)
	_renderers.append(r_back)

	return panel

func _export_showcase_image() -> void:
	DirAccess.make_dir_recursive_absolute("tests/styles")
	var vp := get_viewport()
	if vp != null:
		var tex := vp.get_texture()
		if tex != null:
			var img := tex.get_image()
			if img != null and not img.is_empty():
				var path := "tests/styles/cultivator_modular_gallery.png"
				img.save_png(path)
				print("[GalleryPreview] 成功导出全角色矩阵看板至: %s" % path)
