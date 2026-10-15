extends Node

## 首页菱形流星雨装饰出图台（非判据，不参与核心基线）：开 StartMenu 真渲染几秒，
## 存 PNG 后自动退出，供肉眼验收流星密度/速度/配色/简约度。
## 运行（不能加 --headless，headless 不渲染、且 StartMenu 在 headless 下不建装饰层）：
##   $G --path . res://tests/MenuMeteorShowerPreview.tscn   # 窗口一闪即退，产物 /tmp/menu_meteor_shower.png

func _ready() -> void:
	var menu: StartMenu = load("res://scenes/ui/StartMenu.tscn").instantiate()
	add_child(menu)
	menu.open()
	# 让首批流星错峰入场并飞一段，截到的才是常态画面
	await get_tree().create_timer(3.0).timeout
	if DisplayServer.get_name() != "headless":
		var img := get_viewport().get_texture().get_image()
		img.save_png("/tmp/menu_meteor_shower.png")
		print("MENU_METEOR_SHOWER_PNG: /tmp/menu_meteor_shower.png")
	get_tree().quit()
