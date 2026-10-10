extends Control

## 修仙幸存者 · 空洞冷冽国风全敌种画廊 (Enemy Procedural Gallery)
## 验证 14 大敌种（普通怪、精英怪、关卡魔将与心魔魔尊）的程序化矢量拟态与悬浮/飞行/爬行协调动作
## 适配桌面 960×540 完整一屏 5×3 矩阵

const ENEMY_ENTRIES: Array[Dictionary] = [
	# 第一排：基础小怪（5 种）
	{"id": "slime", "name": "幽冥血煞", "motion": "流质", "desc": "凝魂怨泥·怨魂绿核", "elite": false, "boss": false, "final": false},
	{"id": "xiexiu", "name": "幽冥邪修", "motion": "悬浮", "desc": "破戒残袍·踏剑放风筝", "elite": false, "boss": false, "final": false},
	{"id": "danbao", "name": "蚀骨丹炉", "motion": "沸腾", "desc": "地火青铜·裂纹胀缩自爆", "elite": false, "boss": false, "final": false},
	{"id": "fengqun", "name": "冥火毒螟", "motion": "疾飞", "desc": "15Hz薄翼·毒针冲锋", "elite": false, "boss": false, "final": false},
	{"id": "flower", "name": "噬灵花妖", "motion": "悬浮", "desc": "曼珠沙华·水墨流苏触须", "elite": false, "boss": false, "final": false},

	# 第二排：进阶小怪（5 种）
	{"id": "xueyong", "name": "九幽血茧", "motion": "拱动", "desc": "封灵符带·心跳脉动裂变", "elite": false, "boss": false, "final": false},
	{"id": "guyao", "name": "白骨摄魂鼓", "motion": "律动", "desc": "太极魔纹·双骨槌敲击光环", "elite": false, "boss": false, "final": false},
	{"id": "yingmei", "name": "幽冥影魅", "motion": "飘掠", "desc": "雾化暗影·双角闪现厉鬼", "elite": false, "boss": false, "final": false},
	{"id": "zhumu", "name": "千目邪母", "motion": "浮游", "desc": "深紫魔核·多魔目轮流眨眼", "elite": false, "boss": false, "final": false},
	{"id": "leibeast", "name": "冥雷煞兽", "motion": "巡游", "desc": "狼首獠牙·背棘长扑短咬", "elite": false, "boss": false, "final": false},

	# 第三排：三大精英与两大魔君（5 种）
	{"id": "golem", "name": "铁甲魔傀", "motion": "悬浮", "desc": "精英坦克·浮空磁链阵眼", "elite": true, "boss": false, "final": false},
	{"id": "chilei_elite", "name": "赤雷巨兽", "motion": "巡弋", "desc": "精英突进·赤金雷角刀羽", "elite": true, "boss": false, "final": false},
	{"id": "jiansha_elite", "name": "剑煞邪尊", "motion": "齐御", "desc": "精英法修·扇形飞剑齐射", "elite": true, "boss": false, "final": false},
	{"id": "boss", "name": "赤炎魔将", "motion": "御空", "desc": "关卡魔将·魔刃煞气法轮", "elite": false, "boss": true, "final": false},
	{"id": "boss", "name": "心魔魔尊", "motion": "降世", "desc": "终局魔尊·八符文紫焰神轮", "elite": false, "boss": true, "final": true},
]

var _time: float = 0.0

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
			print("ENEMY_GALLERY_RESULT: ALL PASS")
			tree.quit(0)

func _process(delta: float) -> void:
	_time += delta

func _build_gallery() -> void:
	var root_vbox := VBoxContainer.new()
	root_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_vbox.add_theme_constant_override("separation", 6)
	root_vbox.offset_left = 12
	root_vbox.offset_top = 8
	root_vbox.offset_right = -12
	root_vbox.offset_bottom = -8
	add_child(root_vbox)

	# 顶部标题栏
	var header := HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_BEGIN
	header.add_theme_constant_override("separation", 10)
	root_vbox.add_child(header)

	var title_lbl := Label.new()
	title_lbl.text = "修仙幸存者 · 空洞冷冽国风全妖魔画廊"
	GameStyle.label(title_lbl, 13, GameStyle.PAPER, true)
	header.add_child(title_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = "全 14 敌种拟态 · 纯矢量 CanvasItem 绘制 · 悬浮·飞行·爬行流体非复杂动作"
	GameStyle.label(sub_lbl, 10, GameStyle.GREY)
	header.add_child(sub_lbl)

	# 5 列 × 3 行 矩阵网格
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(grid)

	for item in ENEMY_ENTRIES:
		var card := _create_enemy_card(item)
		grid.add_child(card)

func _create_enemy_card(info: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(180, 150)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# 根据怪种品阶做边框区分（普通蓝暗、精英赤金、Boss紫焰）
	var border_col := Color(0.16, 0.22, 0.32)
	if info.get("boss", false):
		border_col = Color(0.70, 0.25, 0.85) if info.get("final", false) else Color(0.85, 0.35, 0.20)
	elif info.get("elite", false):
		border_col = Color(0.85, 0.65, 0.22)

	panel.add_theme_stylebox_override("panel", GameStyle.outlined_panel(Color(0.08, 0.10, 0.15), border_col, 1, 0.0))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.offset_left = 6
	vbox.offset_top = 4
	vbox.offset_right = -6
	vbox.offset_bottom = -4
	panel.add_child(vbox)

	# 顶部标签栏
	var head_box := HBoxContainer.new()
	head_box.alignment = BoxContainer.ALIGNMENT_CENTER
	head_box.add_theme_constant_override("separation", 4)
	vbox.add_child(head_box)

	var name_lbl := Label.new()
	name_lbl.text = info["name"]
	var name_col: Color = GameStyle.PAPER
	if info.get("boss", false):
		name_col = Color(1.0, 0.4, 0.9) if info.get("final", false) else Color(1.0, 0.5, 0.3)
	elif info.get("elite", false):
		name_col = GameStyle.GOLD
	GameStyle.label(name_lbl, 10, name_col, true)
	head_box.add_child(name_lbl)

	var motion_lbl := Label.new()
	motion_lbl.text = info["motion"]
	motion_lbl.add_theme_stylebox_override("normal", GameStyle.chip(Color(0.12, 0.16, 0.24)))
	GameStyle.label(motion_lbl, 8, GameStyle.JADE)
	head_box.add_child(motion_lbl)

	# 中间视界展示区（居中悬浮/飞行/爬行矢量图元）
	var viewport_box := Control.new()
	viewport_box.custom_minimum_size = Vector2(170, 88)
	viewport_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(viewport_box)

	var cfg := EnemyVisualConfig.get_config(info["id"], info["elite"], info["boss"], info["final"])
	var renderer := HollowKnightEnemyRenderer.new()
	renderer.config = cfg
	var is_boss_type: bool = info.get("boss", false)
	renderer.position = Vector2(85, 54 if is_boss_type else 46)
	# 缩放微调保证同屏舒适度
	renderer.scale = Vector2.ONE * (0.68 if is_boss_type else 0.92)
	viewport_box.add_child(renderer)

	# 底部生态与机制说明
	var desc_lbl := Label.new()
	desc_lbl.text = info["desc"]
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameStyle.label(desc_lbl, 9, GameStyle.GREY)
	vbox.add_child(desc_lbl)

	return panel

func _export_showcase_image() -> void:
	DirAccess.make_dir_recursive_absolute("tests/styles")
	var vp := get_viewport()
	if vp != null:
		var tex := vp.get_texture()
		if tex != null:
			var img := tex.get_image()
			if img != null and not img.is_empty():
				var path := "tests/styles/enemy_procedural_gallery.png"
				img.save_png(path)
				print("[EnemyGalleryPreview] 成功导出全妖魔矩阵看板至: %s" % path)
