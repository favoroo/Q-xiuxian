extends Node

## 首页流星雨装饰出图台（非判据，不参与核心基线）：开 StartMenu 真渲染几秒，
## 存 PNG 后自动退出，供肉眼验收流星密度/速度/配色/简约度。
## 2026-10-30 起噩梦模式只有这层会变（流星整盘转血红），所以顺手再拍一张噩梦对照图 ——
## 两张并排看能直接确认「除流星配色外首页零改动」。
## 运行（不能加 --headless，headless 不渲染、且 StartMenu 在 headless 下不建装饰层）：
##   $G --path . res://tests/MenuMeteorShowerPreview.tscn
## 产物：/tmp/menu_meteor_shower.png（普通）/ /tmp/menu_meteor_shower_night.png（噩梦血雨）

func _ready() -> void:
	# 判据/预览环境没有真实生涯进度：进程内补「已破普通」（不落盘），否则 set_danger(1) 会被夹回 0
	var saved_best := int(GameManager.career_stats.get("best_danger_cleared", -1))
	GameManager.career_stats["best_danger_cleared"] = 0

	var menu: StartMenu = load("res://scenes/ui/StartMenu.tscn").instantiate()
	add_child(menu)
	menu.open()
	# 让首批流星错峰入场并飞一段，截到的才是常态画面
	await get_tree().create_timer(3.0).timeout
	_shot("/tmp/menu_meteor_shower.png")

	# 噩梦态：流星配色走 0.6s 情绪插值，等它换完之后再拍
	GameManager.set_danger(1)
	await get_tree().create_timer(2.0).timeout
	_shot("/tmp/menu_meteor_shower_night.png")

	GameManager.career_stats["best_danger_cleared"] = saved_best
	get_tree().quit()

func _shot(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("MENU_METEOR_SHOWER_PNG: %s" % path)
