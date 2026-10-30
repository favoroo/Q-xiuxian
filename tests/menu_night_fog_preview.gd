extends Node

## 非判据调参台：把首页噩梦迷雾铺在「首页色块示意」上，一次出多档浓度对比图。
## 图层直接用真的 MenuNightmareFog（含 GameStyle 现取的雾色/参数），只把 alpha_scale 覆盖成
## 各档来比浓淡；卡片色块照 StartMenu 噩梦皮肤（GameStyle.NIGHT_*）摆位，尺寸照 960×540 实位。
## 用途：改 shader 云团结构/浓度后免开整台首页，四张图并排看「雾够不够、字还读不读得清」。
## 运行（不能加 --headless）：$G --path . res://tests/MenuNightmareFogPreview.tscn
## 产物：/tmp/menu_fog_a000.png（无雾对照）/ a040 / a055 / a070

const ALPHAS := [0.0, 0.40, 0.55, 0.70]
const SHOT_TIME := 1.2

class MockMenu extends Control:
		func _draw() -> void:
			# 舞台 + 四周血朱画框（与 MenuNightmareChrome 同口径：6px 最外沿）
			draw_rect(Rect2(0, 0, 960, 540), GameStyle.NIGHT_STAGE)
			for r in [Rect2(0, 0, 960, 6), Rect2(0, 534, 960, 6),
					Rect2(0, 0, 6, 540), Rect2(954, 0, 6, 540)]:
				draw_rect(r, GameStyle.NIGHT_SEAL)
			# 卡片矩阵保持原汁原味鲜明配色（960×540 实位：左 Hero 列 + 右 2×2）
			draw_rect(Rect2(43, 66, 348, 358), GameStyle.GOLD)
			draw_rect(Rect2(405, 66, 248, 172), GameStyle.JADE)
			draw_rect(Rect2(669, 66, 248, 172), GameStyle.GOOD)
			draw_rect(Rect2(405, 252, 248, 172), GameStyle.NAVY2)
			draw_rect(Rect2(669, 252, 248, 172), GameStyle.ELEMENT)
			# 顶栏徽章带 / 危险度衬板 / 主按钮 / 角落按钮
			draw_rect(Rect2(756, 12, 96, 36), GameStyle.NAVY2)
			draw_rect(Rect2(862, 12, 74, 36), GameStyle.NAVY2)
			draw_rect(Rect2(55, 224, 324, 76), GameStyle.with_alpha(Color.BLACK, 0.82))
			draw_rect(Rect2(72, 262, 140, 28), GameStyle.NAVY2)
			draw_rect(Rect2(222, 262, 140, 28), GameStyle.NIGHT_SEAL)
			draw_rect(Rect2(55, 390, 324, 42), GameStyle.JADE)
			draw_rect(Rect2(34, 488, 76, 26), GameStyle.GOLD)
			draw_rect(Rect2(850, 488, 76, 26), GameStyle.GOLD)
			# 文字示意：大黑字 / 中号 / 小字副文案（墨字）
			var dim := GameStyle.with_alpha(GameStyle.INK_TEXT, 0.78)
			draw_rect(Rect2(55, 96, 74, 20), GameStyle.GOLD)     # PLAY 角签
			draw_rect(Rect2(55, 160, 250, 34), GameStyle.INK_TEXT)             # 「开始游戏」大标题
			draw_rect(Rect2(55, 266, 300, 11), GameStyle.NIGHT_SEAL_EDGE)     # 难度提示行
			draw_rect(Rect2(405, 92, 60, 10), GameStyle.JADE)    # CAREER 角签
			draw_rect(Rect2(405, 118, 92, 26), GameStyle.INK_TEXT)             # 「战绩」
			draw_rect(Rect2(405, 186, 210, 9), dim)                         # 副文案
			draw_rect(Rect2(669, 92, 66, 10), GameStyle.GOOD)
			draw_rect(Rect2(669, 118, 92, 26), GameStyle.INK_TEXT)
			draw_rect(Rect2(669, 186, 210, 9), dim)
			draw_rect(Rect2(405, 278, 60, 10), GameStyle.GOLD)
			draw_rect(Rect2(405, 304, 74, 26), GameStyle.INK_TEXT)
			draw_rect(Rect2(405, 372, 190, 9), dim)
			draw_rect(Rect2(669, 278, 66, 10), GameStyle.ELEMENT)
			draw_rect(Rect2(669, 304, 140, 26), GameStyle.INK_TEXT)
			draw_rect(Rect2(669, 372, 190, 9), dim)
			draw_rect(Rect2(570, 398, 78, 11), GameStyle.INK_TEXT)             # 主按钮字
			draw_rect(Rect2(772, 24, 60, 10), GameStyle.PAPER)              # 顶栏徽章字
			draw_rect(Rect2(866, 24, 62, 10), GameStyle.PAPER)

func _ready() -> void:
	for a in ALPHAS:
		var vp := SubViewport.new()
		vp.size = Vector2i(960, 540)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.disable_3d = true
		add_child(vp)

		var mock := MockMenu.new()
		mock.size = Vector2(960, 540)
		vp.add_child(mock)

		if float(a) > 0.0:
			# 真图层（雾色/宽高比/呼吸都走它的 _ready），只覆盖浓度档位
			var fog := MenuNightmareFog.new()
			fog.size = Vector2(960, 540)
			vp.add_child(fog)
			fog.set_nightmare(true, false)
			(fog.material as ShaderMaterial).set_shader_parameter("alpha_scale", float(a))

	# 让 TIME 走一段（漂移/呼吸都吃它），再出图
	await get_tree().create_timer(SHOT_TIME).timeout
	for i in range(ALPHAS.size()):
		var vp: SubViewport = get_child(i)
		for _f in range(3):
			await get_tree().process_frame
		var img := vp.get_texture().get_image()
		var path := "/tmp/menu_fog_a%03d.png" % int(round(float(ALPHAS[i]) * 100.0))
		img.save_png(path)
		print("SAVED %s" % path)
	get_tree().quit(0)
