extends Control

## 非判据现场预览：幽蓝灵枢 UI 套件样张。
## 运行（不加 --headless，要真出图）：
##   $G --path . res://tests/UiStylePreview.tscn
## 打开后自动排一块样张、存 /tmp/ui_style_preview.png、自行退出。

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = GameStyle.INK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 标题大匾（灵蓝 + 网点）
	var title := PanelContainer.new()
	title.position = Vector2(240, 40)
	var tst := GameStyle.block(GameStyle.GOLD, GameStyle.SLANT_BLOCK, Vector2(8, 9))
	tst.content_margin_left = 30.0
	tst.content_margin_top = 8.0
	tst.content_margin_right = 30.0
	tst.content_margin_bottom = 12.0
	title.add_theme_stylebox_override("panel", tst)
	GameStyle.halftone(title, Color(0.95, 0.98, 1.0, 0.14))
	var tl := Label.new()
	tl.text = "修 仙 幸 存 者"
	GameStyle.label(tl, 40, GameStyle.INK_TEXT, 0, GameStyle.INK, true)
	title.add_child(tl)
	add_child(title)

	# 色带卡一排：凡/良/仙/传 + 选中态
	var accents := [GameStyle.RARITY_COMMON, GameStyle.RARITY_RARE, GameStyle.RARITY_EPIC,
		GameStyle.RARITY_LEGEND, GameStyle.GOLD]
	var names := ["凡品", "良品", "仙品", "传说", "已选 ✦"]
	for i in range(accents.size()):
		var c := PanelContainer.new()
		c.position = Vector2(60 + i * 172.0, 160)
		c.custom_minimum_size = Vector2(150, 130)
		var st := GameStyle.card(accents[i])
		st.content_margin_left = 10.0
		st.content_margin_top = 10.0
		c.add_theme_stylebox_override("panel", st)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		var nl := Label.new()
		nl.text = names[i]
		GameStyle.label(nl, 15, GameStyle.PAPER, 0, GameStyle.INK, true)
		v.add_child(nl)
		var dl := Label.new()
		dl.text = "武器总伤害 +15%\n墨面托纸白字"
		GameStyle.label(dl, 12, GameStyle.PAPER_DIM)
		v.add_child(dl)
		var chip := Label.new()
		chip.text = " 剑系 "
		chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		chip.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.JADE_DK))
		GameStyle.label(chip, 11, GameStyle.JADE)
		v.add_child(chip)
		c.add_child(v)
		add_child(c)

	# 按钮三颗：主行动灵蓝 / 次要墨底 / 危险朱砂
	var b1 := Button.new()
	b1.text = "开 始 游 戏"
	b1.position = Vector2(60, 340)
	b1.custom_minimum_size = Vector2(220, 48)
	GameStyle.button(b1, GameStyle.GOLD, GameStyle.GOLD_EDGE, 18, GameStyle.INK_TEXT)
	add_child(b1)
	var b2 := Button.new()
	b2.text = "修 仙 志"
	b2.position = Vector2(310, 340)
	b2.custom_minimum_size = Vector2(160, 48)
	GameStyle.button(b2, GameStyle.NAVY2, GameStyle.GOLD, 15, GameStyle.PAPER)
	add_child(b2)
	var b3 := Button.new()
	b3.text = "兵 解 重 修"
	b3.position = Vector2(500, 340)
	b3.custom_minimum_size = Vector2(160, 48)
	GameStyle.button(b3, GameStyle.BAD, GameStyle.JADE, 15, GameStyle.PAPER)
	add_child(b3)

	# 弹窗大面板 + 侧签行 + 进度条
	var dlg := PanelContainer.new()
	dlg.position = Vector2(60, 420)
	dlg.custom_minimum_size = Vector2(400, 90)
	dlg.add_theme_stylebox_override("panel", GameStyle.dialog_panel())
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 6)
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(360, 30)
	var rst := GameStyle.side_card(GameStyle.JADE, 0.0)
	rst.content_margin_left = 10.0
	row.add_theme_stylebox_override("panel", rst)
	var rl := Label.new()
	rl.text = "青玉侧签行 · 灵石 12847"
	GameStyle.label(rl, 13, GameStyle.PAPER)
	row.add_child(rl)
	dv.add_child(row)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(360, 16)
	bar.max_value = 100
	bar.value = 62
	bar.show_percentage = false
	var bs := GameStyle.bar_styles(GameStyle.INK, GameStyle.GOLD)
	bar.add_theme_stylebox_override("background", bs[0])
	bar.add_theme_stylebox_override("fill", bs[1])
	dv.add_child(bar)
	dlg.add_child(dv)
	add_child(dlg)

	var note := Label.new()
	note.text = "幽蓝灵枢样张 · 硬影/厚底边/色带卡/冷冽仙侠"
	note.position = Vector2(510, 460)
	GameStyle.label(note, 12, GameStyle.GREY)
	add_child(note)

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		var tex := get_viewport().get_texture()
		var img := tex.get_image() if tex != null else null
		if img != null:
			img.save_png("/tmp/ui_style_preview.png")
	get_tree().quit(0)
