extends Node2D

## 绿衣修士四大画风全景对比看板 (960x540 完整露出)
## 运行方式：
## 1. 命令行带界面：$G --path . res://tests/styles/CultivatorStyleGallery.tscn
## 2. 命令行截屏导图：$G --headless --path . res://tests/styles/CultivatorStyleGallery.tscn

const TILE_PATH := "res://assets/art/courtyard_tile.png"
const OUTPUT_IMG_PATH := "tests/styles/style_comparison_all.png"

func _ready() -> void:
	# 1. 铺设青砖地面地砖质感背景
	if ResourceLoader.exists(TILE_PATH):
		var tile: Texture2D = load(TILE_PATH)
		var tw := int(tile.get_width())
		for y in range(0, int(540.0 / tw) + 2):
			for x in range(0, int(960.0 / tw) + 2):
				var s := Sprite2D.new()
				s.texture = tile
				s.position = Vector2(x * tw + tw / 2.0, y * tw + tw / 2.0)
				add_child(s)

	# 2. 墨色半透明暗底，让角色与文字色彩极具表现力
	var mask := ColorRect.new()
	mask.size = Vector2(960, 540)
	mask.color = Color(0.05, 0.08, 0.12, 0.92)
	add_child(mask)

	# 3. 顶部总标题与副标题
	var title_lbl := Label.new()
	title_lbl.text = "修仙幸存者 · 四大画风定制人设全景对比看板 (纯代码绘制)"
	title_lbl.position = Vector2(24, 8)
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", Color(0.96, 0.85, 0.40))
	add_child(title_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = "各风格定制灵魂人设：土豆兄弟·符箓狂徒 | 空洞骑士·蜕蝶剑圣 | 现代像素·天青剑侠 | 武士零·断罪剑魔 (正/侧/背三向)"
	sub_lbl.position = Vector2(26, 30)
	sub_lbl.add_theme_font_size_override("font_size", 10)
	sub_lbl.add_theme_color_override("font_color", Color(0.72, 0.78, 0.88))
	add_child(sub_lbl)

	# 4. 构建 4 栏对比卡片 (x: 16, 250, 484, 718, 宽度: 226, 高度: 486, y: 48)
	var card_w := 226.0
	var card_h := 484.0
	var card_y := 48.0
	var gap := 10.0

	_build_style_card(0, Rect2(14 + 0 * (card_w + gap), card_y, card_w, card_h), "A. 土豆兄弟风", "符箓狂徒", Color(1.0, 0.82, 0.25), StyleBrotatoDeluxe)
	_build_style_card(1, Rect2(14 + 1 * (card_w + gap), card_y, card_w, card_h), "B. 空洞骑士风", "蜕蝶剑圣", Color(0.80, 0.92, 1.0), StyleHollowKnightDeluxe)
	_build_style_card(2, Rect2(14 + 2 * (card_w + gap), card_y, card_w, card_h), "C. 现代精致像素", "天青剑侠", Color(0.55, 0.82, 0.95), StyleStardewDeluxe)
	_build_style_card(3, Rect2(14 + 3 * (card_w + gap), card_y, card_w, card_h), "D. 武士零流光", "断罪剑魔", Color(0.0, 1.0, 0.70), StyleKatanaZeroDeluxe)

	# 5. 自动渲染并保存高分辨率预览图
	_schedule_screenshot()

func _build_style_card(idx: int, rect: Rect2, title: String, en_title: String, accent_col: Color, style_class: GDScript) -> void:
	# 卡片背景板（深蓝墨色带微光外框）
	var bg := ColorRect.new()
	bg.position = rect.position
	bg.size = rect.size
	bg.color = Color(0.07, 0.10, 0.16, 0.95)
	add_child(bg)

	var border := ReferenceRect.new()
	border.position = rect.position
	border.size = rect.size
	border.border_color = Color(accent_col.r, accent_col.g, accent_col.b, 0.5)
	border.border_width = 1.2
	border.editor_only = false
	add_child(border)

	# 卡片头部条纹
	var header_bar := ColorRect.new()
	header_bar.position = rect.position
	header_bar.size = Vector2(rect.size.x, 26)
	header_bar.color = Color(accent_col.r * 0.25, accent_col.g * 0.25, accent_col.b * 0.25, 0.9)
	add_child(header_bar)

	var h_lbl := Label.new()
	h_lbl.text = "%s (%s)" % [title, en_title]
	h_lbl.position = rect.position + Vector2(8, 4)
	h_lbl.add_theme_font_size_override("font_size", 11)
	h_lbl.add_theme_color_override("font_color", accent_col)
	add_child(h_lbl)

	# 角色展示区域 (高度约 180px)
	# 背景小擂台/演示台
	var stage_bg := ColorRect.new()
	stage_bg.position = rect.position + Vector2(6, 30)
	stage_bg.size = Vector2(rect.size.x - 12, 172)
	stage_bg.color = Color(0.04, 0.06, 0.10, 0.85)
	add_child(stage_bg)

	# 实机 1x 比例小人 (48px 规格) - 位于展示台左上角
	var p_1x: CultivatorBase = style_class.new()
	p_1x.current_angle = CultivatorBase.Angle.FRONT
	p_1x.scale = Vector2(0.68, 0.68)
	p_1x.position = rect.position + Vector2(28, 54)
	p_1x.animate = true
	add_child(p_1x)

	var tag_1x := Label.new()
	tag_1x.text = "1x 实机"
	tag_1x.position = rect.position + Vector2(12, 74)
	tag_1x.add_theme_font_size_override("font_size", 9)
	tag_1x.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
	add_child(tag_1x)

	# 正面特写 (Front 大视角，放大 1.45x)
	var p_front: CultivatorBase = style_class.new()
	p_front.current_angle = CultivatorBase.Angle.FRONT
	var f_sc: float = 1.65 if style_class == StyleStardew else 1.45
	p_front.scale = Vector2(f_sc, f_sc)
	p_front.position = rect.position + Vector2(130, 66)
	p_front.animate = true
	add_child(p_front)

	var tag_front := Label.new()
	tag_front.text = "正面 (Front)"
	tag_front.position = rect.position + Vector2(100, 100)
	tag_front.add_theme_font_size_override("font_size", 9)
	tag_front.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	add_child(tag_front)

	# 侧面特写 (Side 视角，放大 1.25x) - 位于下方左侧
	var p_side: CultivatorBase = style_class.new()
	p_side.current_angle = CultivatorBase.Angle.SIDE
	var s_sc: float = 1.40 if style_class == StyleStardew else 1.25
	p_side.scale = Vector2(s_sc, s_sc)
	p_side.position = rect.position + Vector2(52, 144)
	p_side.animate = true
	add_child(p_side)

	var tag_side := Label.new()
	tag_side.text = "侧面 (战斗/跑)"
	tag_side.position = rect.position + Vector2(16, 185)
	tag_side.add_theme_font_size_override("font_size", 8)
	tag_side.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	add_child(tag_side)

	# 背面特写 (Back 视角，放大 1.25x) - 位于下方右侧
	var p_back: CultivatorBase = style_class.new()
	p_back.current_angle = CultivatorBase.Angle.BACK
	p_back.scale = Vector2(s_sc, s_sc)
	p_back.position = rect.position + Vector2(165, 144)
	p_back.animate = true
	add_child(p_back)

	var tag_back := Label.new()
	tag_back.text = "背面 (背负飞剑)"
	tag_back.position = rect.position + Vector2(130, 185)
	tag_back.add_theme_font_size_override("font_size", 8)
	tag_back.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	add_child(tag_back)

	# 下方详细评测文字栏
	var info_box := Label.new()
	info_box.position = rect.position + Vector2(8, 206)
	info_box.size = Vector2(rect.size.x - 16, 270)
	info_box.autowrap_mode = TextServer.AUTOWRAP_WORD
	info_box.add_theme_font_size_override("font_size", 9)
	info_box.add_theme_color_override("font_color", Color(0.82, 0.85, 0.90))

	match idx:
		0:
			info_box.text = (
				"【定制人设：金丹符箓狂徒】\n" +
				"• 姜黄八卦小法袍 + 太极印徽标\n" +
				"• 背后扇形展开四色令旗 + 雷火小剑\n" +
				"• 嘴叼灵草狡黠大白眼，环绕雷光球\n" +
				"• 2.8px 粗黑边，百怪围攻中一眼锁定\n\n" +
				"【肉鸽割草适配度】★★★★★ (极高)\n" +
				"• 调性：诙谐萌趣又战力爆棚，极具解压爽感\n" +
				"• 动作反馈：受击挤压与挥剑形变张力极佳\n" +
				"• 推荐：最契合土豆兄弟爽快内核！"
			)
		1:
			info_box.text = (
				"【定制人设：幽冥蜕蝶剑圣】\n" +
				"• 冷白骨玉蝶面，舒展仙角带刻面阴影\n" +
				"• 深渊凹陷眼眶中泛出三层冷月月辉\n" +
				"• 双层蝉翼薄纱大披风，随风轻盈起伏\n" +
				"• 纯白修长骨钉长剑，剑尖凝聚星尘\n\n" +
				"【肉鸽割草适配度】★★★★☆ (出众)\n" +
				"• 调性：孤寂冷傲，艺术神作格调拉满\n" +
				"• 视觉层：黑白月光在深暗战场极度抓眼\n" +
				"• 推荐：追求顶级独立游戏美学首选！"
			)
		2:
			info_box.text = (
				"【定制人设：天青桃花剑侠】\n" +
				"• 精编竹斗笠微倾，额角散落飘逸碎发\n" +
				"• 天青月华流云道袍，系玄金锦缎腰封\n" +
				"• 腰悬赤朱酒葫芦与玉佩，桃花秋水剑\n" +
				"• 16-bit 现代艺术微像素，细腻温馨\n\n" +
				"【肉鸽割草适配度】★★★★☆ (优良)\n" +
				"• 调性：仙风侠气，风来之国/JRPG高级质感\n" +
				"• 沉浸感：传统修仙武侠味道最正宗纯净\n" +
				"• 推荐：国风经典与现代像素爱好者首选！"
			)
		3:
			info_box.text = (
				"【定制人设：暗夜断罪剑魔】\n" +
				"• 玄墨流浪者战甲，刺穿暗夜的双色霓虹\n" +
				"• 电光青碧 + 赛博洋红双色能量流光长带\n" +
				"• 瞬杀拔刀挥出巨大的半月斩裂空弧光\n" +
				"• 激光双目与后背赛博八卦发光电路阵\n\n" +
				"【肉鸽割草适配度】★★★★★ (爆裂)\n" +
				"• 调性：极道赛博国潮，速度感压迫感最强\n" +
				"• 打击感：高频电芒与残影光刃视觉冲击极猛\n" +
				"• 推荐：追求极致冷酷帅气与动作打击感！"
			)
	add_child(info_box)

func _schedule_screenshot() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	if img:
		DirAccess.make_dir_recursive_absolute("tests/styles")
		img.save_png(OUTPUT_IMG_PATH)
		print("[SAVED] 画风对比看板已成功导出至: %s" % OUTPUT_IMG_PATH)
		if OS.get_cmdline_user_args().has("--export") or DisplayServer.get_name() == "headless":
			get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			get_tree().quit()
