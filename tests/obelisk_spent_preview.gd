extends Node2D

## 聚灵阵耗尽灰相出图台（非判据，不参与绿灯）：同一张地砖上并排摆两座界碑，
## 左边不碰，右边按真实链路长按充能到触发，各存一张 PNG 后自动退出。
## 为什么要有它：「用完了就该一眼看出是灰的」是纯眼睛的活 —— 单测能钉住
## 光能被关到 0、shader 参数被推到 1，钉不住「灰得够不够、还漏不漏蓝光」。
## 运行（不能加 --headless，headless 不渲染、get_image 拿到空图）：
##   $G --path . res://tests/ObeliskSpentPreview.tscn
## 产物 /tmp/obelisk_before.png 与 /tmp/obelisk_after.png

const OBELISK := preload("res://scenes/entities/BlessingObelisk.tscn")
const LEFT_POS := Vector2(300, 270)
const RIGHT_POS := Vector2(660, 270)

var _fresh: BlessingObelisk
var _spent: BlessingObelisk

func _ready() -> void:
	var tile: Texture2D = load("res://assets/art/courtyard_tile.png")
	var tw := int(tile.get_width())
	for y in range(0, int(540.0 / tw) + 2):
		for x in range(0, int(960.0 / tw) + 2):
			var s := Sprite2D.new()
			s.texture = tile
			s.position = Vector2(x * tw + tw / 2.0, y * tw + tw / 2.0)
			add_child(s)
	_fresh = OBELISK.instantiate()
	_fresh.position = LEFT_POS
	add_child(_fresh)
	_spent = OBELISK.instantiate()
	_spent.position = RIGHT_POS
	add_child(_spent)
	for i in range(6):
		await get_tree().process_frame
	_shoot("before")
	# 走真实链路：进范围 → 长按 → 充能满自动触发
	_spent.is_player_inside = true
	_spent.start_charge()
	var guard := 0
	while not _spent.is_triggered and guard < 300:
		await get_tree().create_timer(0.05, true, false, true).timeout
		guard += 1
	await get_tree().create_timer(1.2, true, false, true).timeout
	_shoot("after")
	print("SPENT light.enabled=", _spent.light.enabled, " energy=", _spent.light.energy,
			" amount=", _spent.stone_mat.get_shader_parameter("amount"),
			" ring_visible=", _spent.circle_sprite.visible)
	print("FRESH   light.enabled=", _fresh.light.enabled, " energy=", _fresh.light.energy,
			" amount=", _fresh.stone_mat.get_shader_parameter("amount"),
			" ring_visible=", _fresh.circle_sprite.visible)
	get_tree().quit(0)

func _shoot(tag: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var img := get_viewport().get_texture().get_image()
	if img != null:
		var path := "/tmp/obelisk_%s.png" % tag
		img.save_png(path)
		print("SAVED ", path, " ", img.get_size())
