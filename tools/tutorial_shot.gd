extends Node

## 新手指南实机截图台（非判据）：驱动真实游戏到各状态，viewport 截 PNG 供 TutorialDialog 当教学配图。
## 运行（不能加 --headless，headless 不渲染拿不到图）：
##   $G --path . res://tools/TutorialShot.tscn
## 产物 /tmp/tutorial_shots/*.png，验收后拷入 assets_raw/tutorial_shots/（源）与 assets/art/tutorial/（引用）。

const OUT_DIR := "/tmp/tutorial_shots"

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	# 窗口钉到桌面调试口径 960×540（AGENTS.md）：与设计分辨率 1:1，避掉 1280×720 override 窗口下
	# 视口外圈露白底的问题（shop/alloc 弹窗截过一圈白边，2026-10-11）。
	DisplayServer.window_set_size(Vector2i(960, 540))
	# 真实主场景：UILayer/HUD/祭坛/宝箱/商店/悟道全套都在里面
	var main: Node = load("res://scenes/main/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	# 跳过开始菜单直接开局（不走 _on_start_pressed，避开新手指南门控）
	main.get_node("UILayer/StartMenu").visible = false
	GameManager.cultivator_id = "jianchi"
	GameManager.start_run("qingyun_sword")
	get_tree().paused = false

	# 1. 场景：第 1 波进行中，中央聚灵阵在画内（等开场横幅淡掉）
	await get_tree().create_timer(3.0).timeout
	await _snap("shot_field.png")

	# 2. 战斗：敌潮围拢 + HUD + 右下神通按钮 + 摇杆
	await get_tree().create_timer(5.0).timeout
	await _snap("shot_combat.png")

	# 3. 羁绊：塞两件火系点亮加成，开属性面板（右侧羁绊栏）
	GameManager.add_weapon("chiyan_dao")
	GameManager.add_weapon("huoyan_fu")
	await get_tree().process_frame
	var stats: Control = main.get_node("UILayer/PlayerStatsDialog")
	stats.open(false)
	await get_tree().create_timer(0.7).timeout
	await _snap("shot_synergy.png")
	stats.visible = false
	get_tree().paused = false
	await get_tree().process_frame

	# 4. 商店：roll_shop 不发 shop_opened 信号（那由波次状态机发），像 shop_layout_preview
	#    一样直调 _on_shop_opened()（锁定/重掷/出战/陈列星标可见）
	GameManager.add_spirit_stones(300)
	GameManager.roll_shop(true)
	var shop: Control = main.get_node("UILayer/WaveShop")
	shop._on_shop_opened()
	await get_tree().create_timer(0.9).timeout
	await _snap("shot_shop.png")
	shop.visible = false
	get_tree().paused = false
	await get_tree().process_frame

	# 5. 悟道：攒 5 点开加点会（5 张候选 + 免费刷新按钮）
	GameManager.pending_upgrade_points = 5
	GameManager.open_alloc_session()
	await get_tree().create_timer(0.9).timeout
	await _snap("shot_alloc.png")

	print("TUTORIAL_SHOTS_DONE")
	get_tree().quit(0)

func _snap(fname: String) -> void:
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		print("SHOT skip (headless) ", fname)
		return
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		print("SHOT FAIL(null) ", fname)
		return
	img.save_png(OUT_DIR + "/" + fname)
	print("SHOT saved ", fname)
