extends Node2D

## 藏宝匣程序绘制换稿出图台（非判据，不参与绿灯）：同屏摆「旧贴图 vs 新绘制」，
## 木/铜/玉三档并排，另加一行放大特写供细节验收。
## 运行（不能加 --headless，headless 不渲染、get_image 拿到空图）：
##   $G --path . res://tests/ChestDrawPreview.tscn
## 产物 /tmp/chest_draw_preview.png（整图）与 /tmp/chest_draw_<档>.png（单匣特写）

## 与 SpiritChest 同一把尺：贴图/绘制都按 BASE_SCALE × SIZE_MULT × 档位倍率缩放
const REST_SCALE := Vector2(34.0 / 96.0, 34.0 / 96.0) * 1.5
const COL_X: Array[float] = [220.0, 480.0, 740.0]
const ROW_OLD_Y := 180.0   ## 旧贴图行（游戏实尺）
const ROW_NEW_Y := 340.0   ## 新绘制行（游戏实尺）
const ROW_ZOOM_Y := 478.0  ## 新绘制放大行（×2.4）
const TIER_TEXTURES: Array[Texture2D] = [
	preload("res://assets/art/prop_chest.png"),
	preload("res://assets/art/prop_chest_bronze.png"),
	preload("res://assets/art/prop_chest_jade.png"),
]

func _ready() -> void:
	_tile_background()
	for tier in range(3):
		var sc: Vector2 = REST_SCALE * GameBalance.chest_tier_scale(tier)
		# 旧贴图（游戏实尺）
		var old := Sprite2D.new()
		old.texture = TIER_TEXTURES[tier]
		old.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		old.scale = sc
		old.position = Vector2(COL_X[tier], ROW_OLD_Y)
		add_child(old)
		# 新绘制（游戏实尺 + 放大）
		var cv := ChestVisual.new()
		cv.tier = tier
		cv.scale = sc
		cv.position = Vector2(COL_X[tier], ROW_NEW_Y)
		add_child(cv)
		var zoom := ChestVisual.new()
		zoom.tier = tier
		zoom.scale = sc * 2.4
		zoom.position = Vector2(COL_X[tier], ROW_ZOOM_Y)
		add_child(zoom)
		_label(BalanceChest.tier_name(tier), Vector2(COL_X[tier], ROW_OLD_Y - 58))
	_label("旧·贴图", Vector2(60, ROW_OLD_Y - 30), HORIZONTAL_ALIGNMENT_LEFT)
	_label("新·绘制", Vector2(60, ROW_NEW_Y - 30), HORIZONTAL_ALIGNMENT_LEFT)
	_label("新·放大", Vector2(60, ROW_ZOOM_Y - 52), HORIZONTAL_ALIGNMENT_LEFT)

	for i in range(4):
		await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0)
		return
	_shoot("preview")
	var img := get_viewport().get_texture().get_image()
	var k := float(img.get_width()) / 960.0
	var names: Array[String] = ["wood", "copper", "jade"]
	for tier in range(3):
		_shoot(names[tier], Rect2(Vector2((COL_X[tier] - 90.0) * k, (ROW_ZOOM_Y - 100.0) * k),
				Vector2(180.0 * k, 170.0 * k)))
	get_tree().quit(0)

func _tile_background() -> void:
	var tile: Texture2D = load("res://assets/art/courtyard_tile.png")
	var tw := int(tile.get_width())
	for y in range(0, int(540.0 / tw) + 2):
		for x in range(0, int(960.0 / tw) + 2):
			var s := Sprite2D.new()
			s.texture = tile
			s.position = Vector2(x * tw + tw / 2.0, y * tw + tw / 2.0)
			add_child(s)

func _label(text: String, pos: Vector2, align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_override("font", GameStyle.display_font())
	lb.add_theme_font_size_override("font_size", 20)
	lb.add_theme_color_override("font_color", GameStyle.PAPER)
	lb.add_theme_color_override("font_outline_color", GameStyle.INK)
	lb.add_theme_constant_override("outline_size", 6)
	lb.horizontal_alignment = align
	lb.position = pos
	lb.size = Vector2(240, 28)
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		lb.position = pos - Vector2(120, 14)
	add_child(lb)

func _shoot(tag: String, crop: Rect2 = Rect2()) -> void:
	var img := get_viewport().get_texture().get_image()
	if not crop.size.is_zero_approx():
		img = img.get_region(Rect2i(Vector2i(crop.position), Vector2i(crop.size)))
	var path := "/tmp/chest_draw_%s.png" % tag
	img.save_png(path)
	print("SAVED ", path, " ", img.get_size())
