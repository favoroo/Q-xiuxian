extends Node2D

## 空洞骑士风 · 绿衣修士全套动作与实战全景检视看板
## 运行方式：$G --path . res://tests/HollowKnightCultivatorPreview.tscn

const TILE_PATH := "res://assets/art/courtyard_tile.png"
const OUT_PATH := "tests/styles/hollow_knight_actions_showcase.png"

func _ready() -> void:
	# 1. 铺设地砖背景
	if ResourceLoader.exists(TILE_PATH):
		var tile: Texture2D = load(TILE_PATH)
		var tw := int(tile.get_width())
		for y in range(0, int(540.0 / tw) + 2):
			for x in range(0, int(960.0 / tw) + 2):
				var s := Sprite2D.new()
				s.texture = tile
				s.position = Vector2(x * tw + tw / 2.0, y * tw + tw / 2.0)
				add_child(s)

	# 2. 墨夜渐变底板
	var mask := ColorRect.new()
	mask.size = Vector2(960, 540)
	mask.color = Color(0.04, 0.06, 0.09, 0.94)
	add_child(mask)

	# 3. 顶部总标题
	var top_title := Label.new()
	top_title.text = "空洞骑士风 · 绿衣修士（剑痴·独孤）全套动作高精程序化看板"
	top_title.position = Vector2(24, 8)
	top_title.add_theme_font_size_override("font_size", 16)
	top_title.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	add_child(top_title)

	var sub_title := Label.new()
	sub_title.text = "全动作状态机规格：待机 (Idle)  |  奔跑 (Run)  |  冲刺 (Dash)  |  月牙斩击 (Attack)  |  受击 (Hit)  •  纯代码抗锯齿矢量绘制"
	sub_title.position = Vector2(26, 30)
	sub_title.add_theme_font_size_override("font_size", 10)
	sub_title.add_theme_color_override("font_color", Color(0.60, 0.75, 0.85))
	add_child(sub_title)

	# 4. 搭建 5 栏动作卡片（每栏宽 178px，间距 10px，起始 x: 14）
	var col_w := 178.0
	var col_h := 480.0
	var gap := 10.0
	var start_x := 14.0
	var start_y := 48.0

	var actions_data := [
		{
			"action": CultivatorRendererBase.Action.IDLE,
			"title": "1. 待机 (Idle)",
			"desc": "• 轻盈出尘浮沉微动\n• 蝉翼墨绿道披随风翻浪\n• 冷月灵眸呼吸脉冲\n• 纯白骨钉斜插后背\n• 脚底升腾虚空清气"
		},
		{
			"action": CultivatorRendererBase.Action.RUN,
			"title": "2. 奔跑 (Run)",
			"desc": "• 疾走大前倾姿态\n• 移速步频相位自适应\n• 双层墨绿道披如翼大张\n• 布料多层波浪物理\n• 骨钉随奔跑步伐颠簸"
		},
		{
			"action": CultivatorRendererBase.Action.DASH,
			"title": "3. 冲刺 (Dash)",
			"desc": "• 经典空洞「蛾翼冲刺」\n• 极低重心俯冲形变\n• 纯白冷月光轨拖尾 (Trail)\n• 披风如薄刃割裂空气\n• 骨钉向前笔直平刺"
		},
		{
			"action": CultivatorRendererBase.Action.ATTACK,
			"title": "4. 斩击 (Attack)",
			"desc": "• 挥出纯白「月牙弧光剑气」\n• 骨钉下劈横斩连贯发力\n• 青玉光晕与剑气残影\n• 极具压迫感击中反馈\n• 剑修挥剑协同动作"
		},
		{
			"action": CultivatorRendererBase.Action.HIT,
			"title": "5. 受击 (Hit)",
			"desc": "• 身躯受击硬直形变\n• 披风紧裹护身防御\n• 全身白霜护体闪光\n• 虚空微粒震颤散射\n• 无敌帧半透频闪兼容"
		}
	]

	for i in range(actions_data.size()):
		var rect := Rect2(start_x + i * (col_w + gap), start_y, col_w, col_h)
		_build_action_card(rect, actions_data[i])

	# 5. 自动渲染并保存样张
	_schedule_screenshot()

func _build_action_card(rect: Rect2, data: Dictionary) -> void:
	# 卡片背景
	var bg := ColorRect.new()
	bg.position = rect.position
	bg.size = rect.size
	bg.color = Color(0.06, 0.09, 0.14, 0.92)
	add_child(bg)

	var border := ReferenceRect.new()
	border.position = rect.position
	border.size = rect.size
	border.border_color = Color(0.35, 0.75, 0.60, 0.45)
	border.border_width = 1.0
	border.editor_only = false
	add_child(border)

	# 头部标题条
	var header := ColorRect.new()
	header.position = rect.position
	header.size = Vector2(rect.size.x, 24)
	header.color = Color(0.12, 0.25, 0.20, 0.95)
	add_child(header)

	var h_lbl := Label.new()
	h_lbl.text = data["title"]
	h_lbl.position = rect.position + Vector2(8, 3)
	h_lbl.add_theme_font_size_override("font_size", 11)
	h_lbl.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	add_child(h_lbl)

	# 舞台展示区
	var stage := ColorRect.new()
	stage.position = rect.position + Vector2(6, 28)
	stage.size = Vector2(rect.size.x - 12, 230)
	stage.color = Color(0.03, 0.05, 0.08, 0.95)
	add_child(stage)

	# 1. 2.1x 特写角色（侧面视角）
	var p_big := HollowKnightCultivatorRenderer.new()
	p_big.current_action = data["action"]
	p_big.current_angle = CultivatorRendererBase.Angle.SIDE
	p_big.scale = Vector2(2.1, 2.1)
	p_big.position = rect.position + Vector2(88, 126)
	p_big.attack_progress = 0.45
	p_big.dash_progress = 0.5
	p_big.hit_progress = 0.4
	add_child(p_big)

	var tag_big := Label.new()
	tag_big.text = "2.1x 细节特写"
	tag_big.position = rect.position + Vector2(10, 32)
	tag_big.add_theme_font_size_override("font_size", 8)
	tag_big.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
	add_child(tag_big)

	# 2. 1x 实机小人（48px 规格，展示正面与侧面）
	var p_1x_front := HollowKnightCultivatorRenderer.new()
	p_1x_front.current_action = data["action"]
	p_1x_front.current_angle = CultivatorRendererBase.Angle.FRONT
	p_1x_front.scale = Vector2(0.9, 0.9)
	p_1x_front.position = rect.position + Vector2(45, 215)
	p_1x_front.attack_progress = 0.45
	add_child(p_1x_front)

	var p_1x_side := HollowKnightCultivatorRenderer.new()
	p_1x_side.current_action = data["action"]
	p_1x_side.current_angle = CultivatorRendererBase.Angle.SIDE
	p_1x_side.scale = Vector2(0.9, 0.9)
	p_1x_side.position = rect.position + Vector2(130, 215)
	p_1x_side.attack_progress = 0.45
	add_child(p_1x_side)

	var tag_1x := Label.new()
	tag_1x.text = "1x 实机正面 / 侧面"
	tag_1x.position = rect.position + Vector2(40, 240)
	tag_1x.add_theme_font_size_override("font_size", 8)
	tag_1x.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	add_child(tag_1x)

	# 3. 说明文本
	var desc := Label.new()
	desc.position = rect.position + Vector2(8, 264)
	desc.size = Vector2(rect.size.x - 16, 205)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc.text = data["desc"]
	desc.add_theme_font_size_override("font_size", 9)
	desc.add_theme_color_override("font_color", Color(0.80, 0.86, 0.92))
	add_child(desc)

func _schedule_screenshot() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	if img:
		DirAccess.make_dir_recursive_absolute("tests/styles")
		img.save_png(OUT_PATH)
		print("[SAVED SHOWCASE] 空洞动作样张已成功导出至: %s" % OUT_PATH)
	if OS.get_cmdline_user_args().has("--export") or DisplayServer.get_name() == "headless":
		get_tree().quit()
