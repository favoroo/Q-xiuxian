extends Node2D

## 破匣爆开演出看尺（一次性工具，非判据）：三档并排抓 t≈0.22s 的飞溅中段。
## 运行（不能 --headless）：$G --path . res://tests/ChestBurstPreview.tscn
## 产物 /tmp/chest_burst.png

func _ready() -> void:
	get_tree().root.size = Vector2i(960, 540)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.09, 0.11)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var world := Node2D.new()
	add_child(world)
	for tier in range(3):
		var sc := Vector2(34.0 / 96.0, 34.0 / 96.0) * 1.5 * GameBalance.chest_tier_scale(tier)
		ChestBurstFx.play(world, Vector2(220.0 + 260.0 * tier, 320.0), tier, sc * 3.0)
	await get_tree().create_timer(0.22).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("/tmp/chest_burst.png")
	print("CHEST_BURST_RESULT: SHOT /tmp/chest_burst.png")
	await get_tree().create_timer(0.6).timeout  # 让演出走完，确认自毁无报错
	get_tree().quit()
