extends Node2D

## 空洞骑士风 · 绿衣修士（剑痴·独孤）全机位精细透视看板
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
	top_title.text = "空洞骑士风 · 绿衣修士（剑痴·独孤）全视角透视与实机看板"
	top_title.position = Vector2(24, 8)
	top_title.add_theme_font_size_override("font_size", 16)
	top_title.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	add_child(top_title)

	var sub_title := Label.new()
	sub_title.text = "骨钉缩小至精致比例（26px）· 解决侧面剑体像脚伸出的问题 · 聚焦游戏中 100% 真实用到的【待机】与【御风移动】姿态"
	sub_title.position = Vector2(26, 30)
	sub_title.add_theme_font_size_override("font_size", 10)
	sub_title.add_theme_color_override("font_color", Color(0.60, 0.75, 0.85))
	add_child(sub_title)

	# 4. 搭建 4 栏全机位卡片（宽 222px，间距 12px，起始 x: 16）
	var col_w := 222.0
	var col_h := 482.0
	var gap := 12.0
	var start_x := 16.0
	var start_y := 48.0

	var columns_data := [
		{
			"angle": CultivatorRendererBase.Angle.FRONT,
			"title": "视角 1：正面 (Front View)",
			"tag": "端正内敛 · 剑柄探肩",
			"desc": "【正面构图与透视】\n• 骨钉缩至小巧精致规格（26px）\n• 剑身大部藏于墨绿斗篷身后\n• 仅剑柄与圆形剑首探出右肩上方\n• 杜绝底部乱伸武器，视觉干净利落\n• 三层冷月灵眸呼吸脉冲，仙骨天成"
		},
		{
			"angle": CultivatorRendererBase.Angle.SIDE,
			"title": "视角 2：侧面 (Side View)",
			"tag": "后背斜挑 · 绝无伸脚违和",
			"desc": "【侧面构图与透视（重点修复）】\n• 剑身缩至合理尺寸，背负后背上方\n• 剑尖向后上方轻盈斜挑刺天\n• 下端完全收于斗篷内部（距下摆20px）\n• 彻底消除“剑像单脚伸出”的怪异视觉\n• 双手收拢胸前，尽显宗师渊渟岳峙"
		},
		{
			"angle": CultivatorRendererBase.Angle.BACK,
			"title": "视角 3：背面 (Back View)",
			"tag": "顶级背影杀 · 斗篷外挂骨钉",
			"desc": "【背面构图与透视】\n• 纯白骨钉佩于深墨绿斗篷最外层\n• 修正图层Z序，不再被斗篷遮盖\n• 斜跨细致骨纹剑带与冷白卡扣\n• 骨钉斜跨背脊，黑白明暗对抗鲜明\n• 随长波御风浮沉，背影极为潇洒"
		},
		{
			"is_sandbox": true,
			"title": "实战沙盒 (In-Game 1x)",
			"tag": "1x 实机战斗尺寸 (48px)",
			"desc": "【实战环境与动态验证】\n• 48px 原始战斗比例沙盒模拟\n• 1.6px 黄金长波浮沉，如海浪推舟\n• 左右转向时带 7.5° 优雅侧倾 (Bank)\n• 密集怪群中白面黑袍与小剑清晰可辨\n• 纯粹聚焦待机与移动，无冗余动作"
		}
	]

	for i in range(columns_data.size()):
		var rect := Rect2(start_x + i * (col_w + gap), start_y, col_w, col_h)
		_build_column_card(rect, columns_data[i])

	# 5. 自动渲染并保存样张
	_schedule_screenshot()

func _build_column_card(rect: Rect2, data: Dictionary) -> void:
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
	header.size = Vector2(rect.size.x, 26)
	header.color = Color(0.12, 0.25, 0.20, 0.95)
	add_child(header)

	var h_lbl := Label.new()
	h_lbl.text = data["title"]
	h_lbl.position = rect.position + Vector2(8, 4)
	h_lbl.add_theme_font_size_override("font_size", 11)
	h_lbl.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	add_child(h_lbl)

	# 舞台展示区
	var stage := ColorRect.new()
	stage.position = rect.position + Vector2(6, 30)
	stage.size = Vector2(rect.size.x - 12, 230)
	stage.color = Color(0.03, 0.05, 0.08, 0.95)
	add_child(stage)

	var is_sandbox: bool = data.get("is_sandbox", false)

	if is_sandbox:
		# 实战沙盒模拟（在 48px 比例下展示前后侧视角与怪群）
		var center := stage.position + Vector2(stage.size.x * 0.5, stage.size.y * 0.5)

		# 模拟敌人红块围攻
		for ang in [0.0, 1.3, 2.6, 3.9, 5.2]:
			var enemy_pos := center + Vector2(cos(ang) * 65, sin(ang) * 42)
			var e_box := ColorRect.new()
			e_box.size = Vector2(16, 16)
			e_box.position = enemy_pos - Vector2(8, 8)
			e_box.color = Color(0.8, 0.2, 0.25, 0.65)
			add_child(e_box)

		# 3 位 1x 比例修士（分别面朝正面、侧面、背面）
		var p1 := HollowKnightCultivatorRenderer.new()
		p1.current_angle = CultivatorRendererBase.Angle.FRONT
		p1.scale = Vector2(0.95, 0.95)
		p1.position = center + Vector2(-42, 0)
		add_child(p1)

		var p2 := HollowKnightCultivatorRenderer.new()
		p2.current_angle = CultivatorRendererBase.Angle.SIDE
		p2.scale = Vector2(0.95, 0.95)
		p2.position = center + Vector2(0, 0)
		add_child(p2)

		var p3 := HollowKnightCultivatorRenderer.new()
		p3.current_angle = CultivatorRendererBase.Angle.BACK
		p3.scale = Vector2(0.95, 0.95)
		p3.position = center + Vector2(42, 0)
		add_child(p3)

		var tag_s := Label.new()
		tag_s.text = "正面 · 侧面 · 背面 (1x 实战)"
		tag_s.position = rect.position + Vector2(35, 235)
		tag_s.add_theme_font_size_override("font_size", 9)
		tag_s.add_theme_color_override("font_color", Color(0.7, 0.85, 0.95))
		add_child(tag_s)
	else:
		# 1. 2.6x 高清特写角色
		var p_big := HollowKnightCultivatorRenderer.new()
		p_big.current_angle = data["angle"]
		p_big.scale = Vector2(2.6, 2.6)
		p_big.position = rect.position + Vector2(111, 130)
		add_child(p_big)

		var tag_big := Label.new()
		tag_big.text = "2.6x 特写 (%s)" % data["tag"]
		tag_big.position = rect.position + Vector2(10, 34)
		tag_big.add_theme_font_size_override("font_size", 8)
		tag_big.add_theme_color_override("font_color", Color(0.6, 0.75, 0.85))
		add_child(tag_big)

		# 2. 1x 实机小人（48px 规格）
		var p_1x := HollowKnightCultivatorRenderer.new()
		p_1x.current_angle = data["angle"]
		p_1x.scale = Vector2(0.95, 0.95)
		p_1x.position = rect.position + Vector2(111, 218)
		add_child(p_1x)

		var tag_1x := Label.new()
		tag_1x.text = "1x 实机"
		tag_1x.position = rect.position + Vector2(95, 240)
		tag_1x.add_theme_font_size_override("font_size", 8)
		tag_1x.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
		add_child(tag_1x)

	# 3. 说明文本
	var desc := Label.new()
	desc.position = rect.position + Vector2(10, 268)
	desc.size = Vector2(rect.size.x - 20, 205)
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
		print("[SAVED SHOWCASE] 空洞全视角透视样张已成功导出至: %s" % OUT_PATH)
	if OS.get_cmdline_user_args().has("--export") or DisplayServer.get_name() == "headless":
		get_tree().quit()
