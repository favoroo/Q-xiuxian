extends Node2D

## 祭坛水晶「灵脉四阶」调形台（非判据，不参与绿灯）：并排摆 1~4 阶的常驻形态，
## 供改 ProceduralObeliskRenderer 的 tier 分支时直接看形。水晶高度/宽度、悬晶数量、
## 阵盘内环、青玉→鎏金混色都应逐级增强。
## 运行（不能加 --headless，headless 不渲染）：
##   $G --path . res://tests/ObeliskTierPreview.tscn
## 附带 --shot 时渲染 2 秒后存一张整图到 /tmp/obelisk_tiers.png 并退出。

const BG_COL := Color(0.07, 0.10, 0.16)
const ORIGIN_Y := 330.0
const X_STEP := 226.0

var _renderers: Array[ProceduralObeliskRenderer] = []
var _t: float = 0.0

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = BG_COL
	bg.size = Vector2(960, 540)
	add_child(bg)

	var title := Label.new()
	title.text = "祭坛水晶 · 灵脉四阶调形台（ProceduralObeliskRenderer.tier）"
	title.position = Vector2(40, 16)
	GameStyle.label(title, 14, GameStyle.CHALK, 0, GameStyle.INK, true)
	add_child(title)

	# 地面基准线：四座祭坛同一落地点，方便比较晶柱高度
	var floor_line := Line2D.new()
	floor_line.points = PackedVector2Array([Vector2(40, 374), Vector2(920, 374)])
	floor_line.width = 1.0
	floor_line.default_color = Color(0.28, 0.38, 0.50, 0.55)
	add_child(floor_line)

	for i in range(4):
		var tier: int = i + 1
		var x: float = 140.0 + X_STEP * float(i)
		var r := ProceduralObeliskRenderer.new()
		r.tier = tier
		r.is_player_inside = true
		r.position = Vector2(x, ORIGIN_Y)
		add_child(r)
		_renderers.append(r)

		var lbl := Label.new()
		lbl.text = "灵脉%s" % GameBalance.obelisk_tier_name(tier)
		lbl.position = Vector2(x - 60.0, 440.0)
		lbl.size = Vector2(120, 24)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		GameStyle.label(lbl, 14, GameStyle.CHALK, 0, GameStyle.INK, true)
		add_child(lbl)

	if DisplayServer.get_name() == "headless":
		print("ObeliskTierPreview: headless 无渲染意义，直接退出")
		get_tree().quit(0)
		return
	if "--shot" in OS.get_cmdline_user_args():
		_auto_shot()

func _auto_shot() -> void:
	await get_tree().create_timer(2.0, true, false, true).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("/tmp/obelisk_tiers.png")
	print("SAVED: /tmp/obelisk_tiers.png")
	get_tree().quit(0)

func _process(delta: float) -> void:
	_t += delta
	for i in range(_renderers.size()):
		_renderers[i].ring_rotation = _t * (0.22 + 0.05 * float(i))
