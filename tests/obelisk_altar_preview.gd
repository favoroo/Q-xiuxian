extends Node2D

## 祭坛「灵脉阶 × 召唤次数」整坛调形台（非判据，不参与绿灯）：
## 四座真实 BlessingObelisk 并排，展示两个独立读数 ——
##   阶数（水晶大小/阵盘/灵光） 1→4；
##   召唤次数（环绕火苗数量） 0 / 3 / 5 / 8。
## 供改 ObeliskOrbiters / sunburst 灵光 / 水晶形体时直接看整坛效果。
## 运行（不能加 --headless，headless 不渲染）：
##   $G --path . res://tests/ObeliskAltarPreview.tscn
## 附带 --shot 时渲染 2 秒后存一张整图到 /tmp/obelisk_altar_preview.png 并退出。

const OBELISK := preload("res://scenes/entities/BlessingObelisk.tscn")
const BG_COL := Color(0.07, 0.10, 0.16)
const X_STEP := 226.0
const ORIGIN_Y := 300.0
const TIERS := [1, 2, 3, 4]
const ORBITS := [0, 3, 5, 8]

var _altars: Array[BlessingObelisk] = []

func _ready() -> void:
	# 地砖底：与真实祭坛激活预览同一张，方便看光/火苗在地面上的观感
	var tile: Texture2D = load("res://assets/art/courtyard_tile.png")
	if tile != null:
		var tw := int(tile.get_width())
		for y in range(0, int(540.0 / tw) + 2):
			for x in range(0, int(960.0 / tw) + 2):
				var s := Sprite2D.new()
				s.texture = tile
				s.position = Vector2(x * tw + tw / 2.0, y * tw + tw / 2.0)
				add_child(s)
	else:
		var bg := ColorRect.new()
		bg.color = BG_COL
		bg.size = Vector2(960, 540)
		add_child(bg)

	var title := Label.new()
	title.text = "祭坛整坛调形台：水晶看阶数，环绕火苗看召唤次数"
	title.position = Vector2(40, 16)
	GameStyle.label(title, 14, GameStyle.CHALK, 0, GameStyle.INK, true)
	add_child(title)

	for i in range(4):
		var tier: int = TIERS[i]
		var x: float = 140.0 + X_STEP * float(i)
		var ob := OBELISK.instantiate() as BlessingObelisk
		ob.position = Vector2(x, ORIGIN_Y)
		add_child(ob)
		# 预览直接覆写档位：真实祭坛 _ready 会按 GameManager 现价定档，这里四座要并排展示
		ob._obelisk_tier = tier
		ob._obelisk_renderer.tier = tier
		ob._orbiters.set_tier(tier)
		ob._orbiters.set_count(ORBITS[i])
		ob.is_player_inside = true
		if ob.light != null:
			ob.light.energy = ob._tier_light_energy()
		_altars.append(ob)

		var lbl := Label.new()
		lbl.text = "%s · 召唤 %d 次" % [GameBalance.obelisk_tier_name(tier), ORBITS[i]]
		lbl.position = Vector2(x - 90.0, 430.0)
		lbl.size = Vector2(180, 24)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		GameStyle.label(lbl, 14, GameStyle.CHALK, 0, GameStyle.INK, true)
		add_child(lbl)

	if DisplayServer.get_name() == "headless":
		print("ObeliskAltarPreview: headless 无渲染意义，直接退出")
		get_tree().quit(0)
		return
	if "--shot" in OS.get_cmdline_user_args():
		_auto_shot()

func _auto_shot() -> void:
	await get_tree().create_timer(2.0, true, false, true).timeout
	# 4 座真实祭坛首帧装配较慢：先让渲染服务器真正出一帧，避免抓到全黑图
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("/tmp/obelisk_altar_preview.png")
	print("SAVED: /tmp/obelisk_altar_preview.png")
	get_tree().quit(0)

func _process(_delta: float) -> void:
	# 让四座祭坛的阵盘各转各的，方便看出环数差
	for i in range(_altars.size()):
		var ob := _altars[i]
		if ob != null and is_instance_valid(ob) and ob.circle_sprite != null:
			ob.circle_sprite.rotation += _delta * (0.3 + 0.08 * float(i))