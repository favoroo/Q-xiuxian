extends Node2D

## 官方横版宣传图（1920x1080）生成器
## 符合 TapTap v4 物料规范：
## 1. 1920x1080 (16:9)
## 2. 核心视觉：主要角色（剑痴大立绘）+ 飞剑法器环绕
## 3. 游戏名「剑士」清晰可见，无其他多余广告宣传文字
## 4. 4:3 安全区居中内聚，无手机边框，无外部贴片，纯引擎真实矢量渲染

func _ready() -> void:
	call_deferred("_generate")

func _generate() -> void:
	get_window().size = Vector2i(1920, 1080)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img: Image = get_viewport().get_texture().get_image()
	var out_path := "/tmp/qx_store/banner_4.png"
	var err := img.save_png(out_path)
	print("BANNER_SAVED %s err=%d size=%s" % [out_path, err, str(img.get_size())])
	get_tree().quit(0)

func _draw() -> void:
	# 1. 纯黑底色与战台微格
	draw_rect(Rect2(0, 0, 1920, 1080), Color("#0a0e17"))

	# 柔和战台同心圆弧与八卦方位辅线（烘托修仙剑阵意境）
	var center := Vector2(680, 540)
	for r in [220.0, 360.0, 500.0, 640.0]:
		draw_arc(center, r, 0, TAU, 96, Color(0.2, 0.4, 0.6, 0.12), 2.0)
	for i in range(8):
		var ang := i * TAU / 8.0
		var dir := Vector2.from_angle(ang)
		draw_line(center + dir * 180.0, center + dir * 650.0, Color(0.2, 0.4, 0.6, 0.08), 1.5)

	# 2. 环绕剑阵（青云剑、庚金飞剑）
	var sword_tex := preload("res://assets/art/cultivator_jianchi_icon.png") if ResourceLoader.exists("res://assets/art/cultivator_jianchi_icon.png") else null
	# 绘制几道灵剑剑光弧线
	for i in range(6):
		var ang := i * TAU / 6.0 + 0.3
		var pos := center + Vector2.from_angle(ang) * 320.0
		var blade_dir := Vector2.from_angle(ang + PI * 0.45)
		draw_line(pos - blade_dir * 36.0, pos + blade_dir * 36.0, Color(0.85, 0.95, 1.0, 0.75), 4.0)
		draw_line(pos - blade_dir * 32.0, pos + blade_dir * 32.0, Color(0.3, 0.8, 1.0, 0.9), 2.0)
		# 剑尖光晕
		draw_circle(pos + blade_dir * 38.0, 5.0, Color(0.5, 0.9, 1.0, 0.8))

	# 3. 居中左侧：主角剑痴大立绘（直接使用高质量矢量道统渲染或大头像）
	var icon_tex := load("res://assets/brand/app_icon.png") as Texture2D
	if icon_tex != null:
		var hero_sz := Vector2(480, 480)
		var hero_pos := center - hero_sz * 0.5
		# 背景光韵
		draw_circle(center, 250, Color(0.15, 0.35, 0.45, 0.25))
		draw_texture_rect(icon_tex, Rect2(hero_pos, hero_sz), false)

	# 4. 居中右侧：游戏标题「剑士」
	var font := load("res://fonts/MiSans-Heavy.woff2") as Font
	if font == null:
		font = load("res://fonts/MiSans-Semibold.woff2") as Font

	var title_text := "剑士"
	var font_size := 168
	var text_pos := Vector2(1160, 570)

	# 标题阴影 / 边框
	draw_string(font, text_pos + Vector2(6, 6), title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.85))
	draw_string(font, text_pos, title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("#fbf8ee"))

	# 英文副标
	var en_font := load("res://fonts/MiSans-Semibold.woff2") as Font
	draw_string(en_font, text_pos + Vector2(6, 68), "SWORDSMAN", HORIZONTAL_ALIGNMENT_LEFT, -1, 38, Color("#8892a0"))

	# 装饰横线（金系金光）
	draw_line(text_pos + Vector2(0, 100), text_pos + Vector2(380, 100), Color("#d6a847"), 4.0)
