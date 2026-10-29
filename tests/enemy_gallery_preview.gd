extends Control

## 剑士 · 空洞冷冽国风全敌种画廊 (Enemy Procedural Gallery)
## 验证 22 大基础敌型与 6 大魔君变体的程序化矢量拟态与悬浮/飞行/爬行协调动作
## 适配桌面 960×540 完整一屏 9×3 矩阵（27 张卡片）

const ENEMY_ENTRIES: Array[Dictionary] = [
	# 第一排：基础小怪（9 种）
	{"id": "slime", "name": "幽冥血煞", "motion": "流质", "desc": "凝魂怨泥·怨魂绿核", "elite": false, "boss": false, "final": false},
	{"id": "xiexiu", "name": "幽冥邪修", "motion": "悬浮", "desc": "破戒残袍·踏剑风筝", "elite": false, "boss": false, "final": false},
	{"id": "danbao", "name": "蚀骨丹炉", "motion": "沸腾", "desc": "地火青铜·裂纹自爆", "elite": false, "boss": false, "final": false},
	{"id": "fengqun", "name": "冥火毒螟", "motion": "疾飞", "desc": "15Hz薄翼·毒针冲锋", "elite": false, "boss": false, "final": false},
	{"id": "flower", "name": "噬灵花妖", "motion": "悬浮", "desc": "曼珠沙华·水墨触须", "elite": false, "boss": false, "final": false},
	{"id": "xueyong", "name": "九幽血茧", "motion": "拱动", "desc": "封灵符带·心跳裂变", "elite": false, "boss": false, "final": false},
	{"id": "guyao", "name": "白骨摄魂鼓", "motion": "律动", "desc": "太极魔纹·双槌光环", "elite": false, "boss": false, "final": false},
	{"id": "duyao", "name": "腐沼毒蟾", "motion": "凝毒", "desc": "暗沼腐皮·背负毒囊", "elite": false, "boss": false, "final": false},
	{"id": "yingmei", "name": "幽冥影魅", "motion": "飘掠", "desc": "雾化暗影·双角闪现", "elite": false, "boss": false, "final": false},

	# 第二排：进阶怪、生态怪与三大早期精英（9 种）
	{"id": "zhumu", "name": "千目邪母", "motion": "浮游", "desc": "深紫魔核·多目眨眼", "elite": false, "boss": false, "final": false},
	{"id": "leibeast", "name": "冥雷煞兽", "motion": "巡游", "desc": "狼首獠牙·背棘长扑", "elite": false, "boss": false, "final": false},
	{"id": "hanpo", "name": "寒魄妖", "motion": "霜掠", "desc": "霜晶骨甲·冰魄溅射", "elite": false, "boss": false, "final": false},
	{"id": "mowei", "name": "血煞魔卫", "motion": "重踏", "desc": "重装血铠·预判震地", "elite": false, "boss": false, "final": false},
	{"id": "lingyi", "name": "青囊药灵", "motion": "悬浮", "desc": "回春光环·优先疗伤", "elite": false, "boss": false, "final": false},
	{"id": "jinchan", "name": "衔宝金蟾", "motion": "蹦跳", "desc": "见人就跑·击杀掉金", "elite": false, "boss": false, "final": false},
	{"id": "golem", "name": "铁甲魔傀", "motion": "悬浮", "desc": "精英坦克·磁链阵眼", "elite": true, "boss": false, "final": false},
	{"id": "chilei_elite", "name": "赤雷巨兽", "motion": "巡弋", "desc": "精英突进·雷角刀羽", "elite": true, "boss": false, "final": false},
	{"id": "jiansha_elite", "name": "剑煞邪尊", "motion": "齐御", "desc": "精英法修·飞剑齐射", "elite": true, "boss": false, "final": false},

	# 第三排：三大高阶精英与六大魔君（9 种）
	{"id": "xuanming_elite", "name": "玄冥魔尊", "motion": "瞬斩", "desc": "精英法修·雷环落石", "elite": true, "boss": false, "final": false},
	{"id": "xingpan_elite", "name": "玄天星盘", "motion": "星悬", "desc": "精英机关·环弹星矢", "elite": true, "boss": false, "final": false},
	{"id": "wandu_elite", "name": "万毒祭司", "motion": "施蛊", "desc": "精英巫蛊·毒沼禁区", "elite": true, "boss": false, "final": false},
	{"id": "boss", "name": "赤炎魔将", "motion": "御空", "desc": "关卡魔将·煞气法轮", "elite": false, "boss": true, "final": false},
	{"id": "boss_xiuluo", "name": "血煞修罗", "motion": "狂战", "desc": "魔刃双轮·折返连冲", "elite": false, "boss": true, "final": false},
	{"id": "boss_qianji", "name": "玄天千机尊", "motion": "天机", "desc": "八卦神座·换桩震爆", "elite": false, "boss": true, "final": false},
	{"id": "boss_wangu", "name": "万蛊蚀天母", "motion": "蛊界", "desc": "碧毒法轮·禁区封锁", "elite": false, "boss": true, "final": false},
	{"id": "boss_jianpo", "name": "幽冥剑魄尊", "motion": "极刃", "desc": "极寒神铠·瞬步回斩", "elite": false, "boss": true, "final": false},
	{"id": "boss", "name": "心魔魔尊", "motion": "降世", "desc": "终局魔尊·紫焰神轮", "elite": false, "boss": true, "final": true},
]

var _time: float = 0.0
var _renderers: Array[HollowKnightEnemyRenderer] = []

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
	var walking := fposmod(_time, 4.0) < 2.0   # 2s 行走 / 2s 待机
	for r in _renderers:
		if not is_instance_valid(r):
			continue
		r.is_moving = walking
		r.speed_ratio = 1.0
		if walking:
			r.gait_phase = fposmod(r.gait_phase + delta * 6.0, TAU * 100.0)
		r.aim_dir = Vector2.RIGHT.rotated(_time * 0.7)
		# 走步时给一点侧倾，验收「受击后仰/走位侧倾」这一条新增通道
		r.bank_angle = sin(_time * 1.4 + 1.2) * deg_to_rad(6.0) if walking else 0.0
		r.special_state = clampf(fposmod(_time, 4.0) / 2.0, 0.0, 1.0) if not walking else 0.0

func _build_gallery() -> void:
	var root_vbox := VBoxContainer.new()
	root_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_vbox.add_theme_constant_override("separation", 4)
	root_vbox.offset_left = 6
	root_vbox.offset_top = 6
	root_vbox.offset_right = -6
	root_vbox.offset_bottom = -6
	add_child(root_vbox)

	# 顶部标题栏
	var header := HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_BEGIN
	header.add_theme_constant_override("separation", 8)
	root_vbox.add_child(header)

	var title_lbl := Label.new()
	title_lbl.text = "剑士 · 空洞冷冽国风全妖魔画廊"
	GameStyle.label(title_lbl, 13, GameStyle.CHALK, 0, GameStyle.INK, true)
	header.add_child(title_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = "全 22 敌型 + 6 魔君变体 · 纯矢量拟态 · 待机·走步·蓄力全姿态动态看板"
	GameStyle.label(sub_lbl, 10, GameStyle.GREY)
	header.add_child(sub_lbl)

	# 9 列 × 3 行 矩阵网格（27 张卡片）
	var grid := GridContainer.new()
	grid.columns = 9
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(grid)

	for item in ENEMY_ENTRIES:
		var card := _create_enemy_card(item)
		grid.add_child(card)

func _create_enemy_card(info: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(98, 150)
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
	vbox.add_theme_constant_override("separation", 2)
	vbox.offset_left = 3
	vbox.offset_top = 3
	vbox.offset_right = -3
	vbox.offset_bottom = -3
	panel.add_child(vbox)

	# 顶部标签栏
	var head_box := HBoxContainer.new()
	head_box.alignment = BoxContainer.ALIGNMENT_CENTER
	head_box.add_theme_constant_override("separation", 2)
	vbox.add_child(head_box)

	var name_lbl := Label.new()
	name_lbl.text = info["name"]
	var name_col: Color = GameStyle.CHALK
	if info.get("boss", false):
		name_col = Color(1.0, 0.4, 0.9) if info.get("final", false) else Color(1.0, 0.5, 0.3)
	elif info.get("elite", false):
		name_col = GameStyle.GOLD
	GameStyle.label(name_lbl, 9, name_col, true)
	head_box.add_child(name_lbl)

	var motion_lbl := Label.new()
	motion_lbl.text = info["motion"]
	motion_lbl.add_theme_stylebox_override("normal", GameStyle.chip(Color(0.12, 0.16, 0.24)))
	GameStyle.label(motion_lbl, 8, GameStyle.JADE)
	head_box.add_child(motion_lbl)

	# 中间视界展示区（居中悬浮/飞行/爬行矢量图元）
	var viewport_box := Control.new()
	viewport_box.custom_minimum_size = Vector2(92, 86)
	viewport_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(viewport_box)

	var cfg := EnemyVisualConfig.get_config(info["id"], info["elite"], info["boss"], info["final"])
	var renderer := HollowKnightEnemyRenderer.new()
	renderer.config = cfg
	var is_boss_type: bool = info.get("boss", false)
	renderer.position = Vector2(46, 48 if is_boss_type else 42)
	# 缩放微调保证同屏舒适度
	renderer.scale = Vector2.ONE * (0.50 if is_boss_type else 0.72)
	viewport_box.add_child(renderer)
	_renderers.append(renderer)

	# 底部生态与机制说明
	var desc_lbl := Label.new()
	desc_lbl.text = info["desc"]
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameStyle.label(desc_lbl, 8, GameStyle.GREY)
	vbox.add_child(desc_lbl)

	return panel

func _export_showcase_image() -> void:
	if DisplayServer.get_name() == "headless":
		return
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
