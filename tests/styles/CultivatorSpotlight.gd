extends Node2D

## 四大画风高清特写与实战拟真聚光镜 (960x540)
## 依次生成 4 大画风的 3.5x 超高解析度细节图与实战拟真战场切片
## 产物保存在 tests/styles/spotlight_*.png

const TILE_PATH := "res://assets/art/courtyard_tile.png"

func _get_styles_config() -> Array[Dictionary]:
	return [
		{
			"id": "brotato",
			"name": "土豆兄弟风 · 金丹符箓狂徒 (Brotato Deluxe)",
			"class": StyleBrotatoDeluxe,
			"accent": Color(1.0, 0.82, 0.25),
			"slogan": "姜黄八卦法袍 · 太极金印 · 四色令旗扇形齐出 · 嘴叼灵草狡黠灵动",
			"desc": "打破纯色绿袍束缚，塑造极富个性的金丹雷法道霸狂徒！\n背后四色令旗与雷火木剑威风凛凛，2.8px 粗黑边在满屏怪群中视觉统治力最强，打击感极具 Q 弹解压张力。"
		},
		{
			"id": "hollow_knight",
			"name": "空洞骑士风 · 幽冥蜕蝶剑圣 (Hollow Knight Deluxe)",
			"class": StyleHollowKnightDeluxe,
			"accent": Color(0.80, 0.92, 1.0),
			"slogan": "冷白骨玉面壳 · 舒展仙角带刻面阴影 · 纯白月光骨钉 · 双层破晓蝉翼道披",
			"desc": "极致的哥特仙侠美学！冷白骨玉面具下凹陷出深渊眼眶，三层冷月灵眸清冷神秘。\n双层如破晓蝉翼的大披风随风飘拂，纯白骨钉长剑直刺苍穹，艺术格调出尘绝伦。"
		},
		{
			"id": "stardew",
			"name": "现代精致像素 · 天青桃花剑侠 (Stardew / Eastward Deluxe)",
			"class": StyleStardewDeluxe,
			"accent": Color(0.55, 0.82, 0.95),
			"slogan": "精编竹斗笠 · 天青月华流云道袍 · 腰悬赤朱酒葫芦与玉佩 · 桃花秋水剑",
			"desc": "告别古早粗糙色块，采用风来之国/星露谷现代 16-bit 艺术级微像素。\n温润的天青色阶与月华内衬，精巧的赤朱酒葫芦与桃花金装青锋，国风仙侠意境最正宗纯正。"
		},
		{
			"id": "katana_zero",
			"name": "武士零流光 · 暗夜断罪剑魔 (Katana ZERO Deluxe)",
			"class": StyleKatanaZeroDeluxe,
			"accent": Color(0.0, 1.0, 0.70),
			"slogan": "玄墨战甲风衣 · 赛博电光青与洋红双色碰撞 · 暴烈流光能量围巾 · 瞬杀半月斩",
			"desc": "极致硬核的高对比视觉！电光青碧与赛博洋红双色能量在暗夜中剧烈撕裂。\n极低重心俯冲斩出巨大的半月裂空弧光，后背发光八卦电路阵，速度感与破坏爽感全场最强！"
		}
	]

var _current_idx: int = 0

func _ready() -> void:
	_render_next_style()

func _render_next_style() -> void:
	var configs := _get_styles_config()
	if _current_idx >= configs.size():
		print("[ALL DONE] 4 大画风高清聚光镜样张全部导出完毕！")
		get_tree().quit()
		return

	# 清空之前绘制
	for c in get_children():
		c.queue_free()

	var cfg: Dictionary = configs[_current_idx]
	_build_spotlight_view(cfg)

	# 等待 4 帧以完成渲染和着色
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

		if DisplayServer.get_name() != "headless":
			var tex := get_viewport().get_texture()
			var img := tex.get_image() if tex != null else null
			if img:
				var out_path := "tests/styles/spotlight_%s.png" % cfg["id"]
				img.save_png(out_path)
				print("[SAVED SPOTLIGHT] %s -> %s" % [cfg["name"], out_path])

	_current_idx += 1
	_render_next_style()

func _build_spotlight_view(cfg: Dictionary) -> void:
	# 1. 地砖背景
	if ResourceLoader.exists(TILE_PATH):
		var tile: Texture2D = load(TILE_PATH)
		var tw := int(tile.get_width())
		for y in range(0, int(540.0 / tw) + 2):
			for x in range(0, int(960.0 / tw) + 2):
				var s := Sprite2D.new()
				s.texture = tile
				s.position = Vector2(x * tw + tw / 2.0, y * tw + tw / 2.0)
				add_child(s)

	# 2. 暗夜渐变遮罩
	var mask := ColorRect.new()
	mask.size = Vector2(960, 540)
	mask.color = Color(0.05, 0.07, 0.11, 0.94)
	add_child(mask)

	var accent: Color = cfg["accent"]
	var style_cls: GDScript = cfg["class"]

	# 3. 顶部大匾
	var top_bar := ColorRect.new()
	top_bar.position = Vector2(20, 16)
	top_bar.size = Vector2(920, 54)
	top_bar.color = Color(0.08, 0.12, 0.18, 0.95)
	add_child(top_bar)

	var bar_line := ColorRect.new()
	bar_line.position = Vector2(20, 16)
	bar_line.size = Vector2(920, 3)
	bar_line.color = accent
	add_child(bar_line)

	var title_lbl := Label.new()
	title_lbl.text = cfg["name"]
	title_lbl.position = Vector2(36, 23)
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", accent)
	add_child(title_lbl)

	var slogan_lbl := Label.new()
	slogan_lbl.text = cfg["slogan"]
	slogan_lbl.position = Vector2(38, 46)
	slogan_lbl.add_theme_font_size_override("font_size", 11)
	slogan_lbl.add_theme_color_override("font_color", Color(0.85, 0.90, 0.95))
	add_child(slogan_lbl)

	# 4. 左侧大特写区：【正面 (Front) 3.2x 超清展示】
	var left_stage := ColorRect.new()
	left_stage.position = Vector2(20, 80)
	left_stage.size = Vector2(330, 440)
	left_stage.color = Color(0.07, 0.10, 0.15, 0.9)
	add_child(left_stage)

	var l_tag := Label.new()
	l_tag.text = "【视角 1】正面特写 (Front View · 3.2x 细节)"
	l_tag.position = Vector2(32, 92)
	l_tag.add_theme_font_size_override("font_size", 12)
	l_tag.add_theme_color_override("font_color", accent)
	add_child(l_tag)

	var p_front: CultivatorBase = style_cls.new()
	p_front.current_angle = CultivatorBase.Angle.FRONT
	p_front.scale = Vector2(3.2, 3.2)
	p_front.position = Vector2(185, 290)
	p_front.animate = true
	add_child(p_front)

	# 5. 中间区域：【侧面 (Side) 2.6x 战斗姿态】与【背面 (Back) 2.6x 背负姿态】
	# 侧面卡片
	var side_stage := ColorRect.new()
	side_stage.position = Vector2(362, 80)
	side_stage.size = Vector2(285, 214)
	side_stage.color = Color(0.07, 0.10, 0.15, 0.9)
	add_child(side_stage)

	var s_tag := Label.new()
	s_tag.text = "【视角 2】侧面战斗/奔跑 (Side · 2.6x)"
	s_tag.position = Vector2(374, 90)
	s_tag.add_theme_font_size_override("font_size", 11)
	s_tag.add_theme_color_override("font_color", Color(0.8, 0.9, 0.95))
	add_child(s_tag)

	var p_side: CultivatorBase = style_cls.new()
	p_side.current_angle = CultivatorBase.Angle.SIDE
	p_side.scale = Vector2(2.6, 2.6)
	p_side.position = Vector2(504, 202)
	p_side.animate = true
	add_child(p_side)

	# 背面卡片
	var back_stage := ColorRect.new()
	back_stage.position = Vector2(362, 306)
	back_stage.size = Vector2(285, 214)
	back_stage.color = Color(0.07, 0.10, 0.15, 0.9)
	add_child(back_stage)

	var b_tag := Label.new()
	b_tag.text = "【视角 3】背面背负飞剑 (Back · 2.6x)"
	b_tag.position = Vector2(374, 316)
	b_tag.add_theme_font_size_override("font_size", 11)
	b_tag.add_theme_color_override("font_color", Color(0.8, 0.9, 0.95))
	add_child(b_tag)

	var p_back: CultivatorBase = style_cls.new()
	p_back.current_angle = CultivatorBase.Angle.BACK
	p_back.scale = Vector2(2.6, 2.6)
	p_back.position = Vector2(504, 428)
	p_back.animate = true
	add_child(p_back)

	# 6. 右侧区域：【实战 1x 模拟沙盒】与【设计精义详解】
	var right_stage := ColorRect.new()
	right_stage.position = Vector2(658, 80)
	right_stage.size = Vector2(282, 440)
	right_stage.color = Color(0.07, 0.10, 0.15, 0.9)
	add_child(right_stage)

	var r_tag := Label.new()
	r_tag.text = "【实战场地拟真】1x 原始游戏比例 (48px)"
	r_tag.position = Vector2(670, 92)
	r_tag.add_theme_font_size_override("font_size", 11)
	r_tag.add_theme_color_override("font_color", accent)
	add_child(r_tag)

	# 实战擂台模拟盘 (模拟怪群围攻下的辨识度)
	var arena := ColorRect.new()
	arena.position = Vector2(670, 116)
	arena.size = Vector2(258, 160)
	arena.color = Color(0.03, 0.05, 0.08, 0.95)
	add_child(arena)

	# 模拟地面脚底法阵光环与飞剑环绕
	var arena_center := arena.position + Vector2(129, 80)

	# 模拟周围敌人暗影红圈
	for ang in [0.0, 1.3, 2.5, 3.8, 5.0]:
		var enemy_pos := arena_center + Vector2(cos(ang) * 75, sin(ang) * 45)
		var e_col := ColorRect.new()
		e_col.size = Vector2(18, 18)
		e_col.position = enemy_pos - Vector2(9, 9)
		e_col.color = Color(0.75, 0.20, 0.25, 0.6)
		add_child(e_col)

	# 玩家实战角色 (1x 规格)
	var p_sim: CultivatorBase = style_cls.new()
	p_sim.current_angle = CultivatorBase.Angle.SIDE
	p_sim.scale = Vector2(0.9, 0.9)
	p_sim.position = arena_center
	p_sim.animate = true
	add_child(p_sim)

	var sim_note := Label.new()
	sim_note.text = "↑ 在密集怪群与红光包围中测试角色轮廓清晰度"
	sim_note.position = Vector2(670, 282)
	sim_note.add_theme_font_size_override("font_size", 9)
	sim_note.add_theme_color_override("font_color", Color(0.65, 0.72, 0.80))
	add_child(sim_note)

	# 艺术理念与评析面板
	var desc_box := Label.new()
	desc_box.position = Vector2(670, 310)
	desc_box.size = Vector2(258, 200)
	desc_box.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_box.text = (
		"【设计精析与手感预测】\n\n" +
		cfg["desc"] + "\n\n" +
		"• 纯代码矢量/几何原生绘制\n" +
		"• 任意缩放无颗粒感与锯齿模糊\n" +
		"• 原生支持正/侧/背三向动态切换"
	)
	desc_box.add_theme_font_size_override("font_size", 10)
	desc_box.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
	add_child(desc_box)
