extends Node

## 高清商店实机截图采集器 (1920x1080)
## 采集 5 张完全符合 TapTap 规范的实机画面：
## 1. shot_1_battle: 实机战斗（剑阵环绕、法器索敌、伤害跳字）
## 2. shot_2_battle_intense: 战阵激战（多妖魔同屏、走位闪避）
## 3. shot_3_alloc: 悟道结算（五行功法、流派加点）
## 4. shot_4_shop: 回合间金币阁（法器构筑、买卖羁绊）
## 5. shot_5_cultivator: 道统择选（多宗门角色体系）

const OUT_DIR := "/tmp/qx_store"

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	get_window().size = Vector2i(1920, 1080)
	await get_tree().process_frame

	var main: Node = load("res://scenes/main/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	# 1. 采集道统选角界面 (CultivatorSelect)
	var cult_select := main.get_node_or_null("UILayer/CultivatorSelect") as Control
	var start_menu := main.get_node_or_null("UILayer/StartMenu") as Control
	var backdrop := main.get_node_or_null("UILayer/StageBackdrop") as Control
	if start_menu != null:
		start_menu.visible = false
	if cult_select != null:
		cult_select.visible = true
		if cult_select.has_method("show_select"):
			cult_select.show_select()
		await get_tree().process_frame
		await get_tree().create_timer(0.4).timeout
		await _shot("shot_5_cultivator.png")
		cult_select.visible = false

	# 确保选角幕布完全关闭，避免遮挡战斗画面
	if backdrop != null:
		backdrop.visible = false

	# 2. 开局进入实战
	GameManager.author_mode = false
	AuthorMode.god_mode = false
	GameManager.cultivator_id = "jianchi"
	GameManager.start_run("qingyun_sword")
	get_tree().paused = false
	var hud := main.get_node_or_null("UILayer/GameHUD") as Control
	if hud != null:
		hud.visible = true

	# 给玩家配置正常实战数值与多把法器
	if GameManager.player != null:
		GameManager.player.max_health = 150.0
		GameManager.player.current_health = 135.0
		GameManager.armor = 30.0
		GameManager.player_hp_changed.emit(135.0, 150.0)

	# 添置 3 把流派法器，让画面更丰富
	GameManager.add_weapon("gengjin_feijian")
	GameManager.add_weapon("thunder_burst")
	GameManager.add_weapon("wood_talisman")
	GameManager.spirit_stones = 58
	GameManager.stats_updated.emit(GameManager.kills, GameManager.game_time, GameManager.spirit_stones)

	# 等待敌人刷出并开打
	var wait_spawn := 0
	while get_tree().get_nodes_in_group("enemies").size() < 4 and wait_spawn < 300:
		await get_tree().process_frame
		wait_spawn += 1

	await _settle(1.8)
	await _shot("shot_1_battle.png")

	await _settle(3.0)
	await _shot("shot_2_battle_intense.png")

	# 3. 悟道加点界面
	GameManager.pending_upgrade_points = 1
	GameManager.open_alloc_session()
	await get_tree().create_timer(0.8).timeout
	await _shot("shot_3_alloc.png")
	var levelup := main.get_node_or_null("UILayer/LevelUpDialog") as Control
	if levelup != null:
		levelup.visible = false
	GameManager.pending_upgrade_points = 0
	GameManager.alloc_offers.clear()
	get_tree().paused = false
	await get_tree().process_frame

	# 4. 金币阁商店界面
	GameManager.spirit_stones = 46
	GameManager.player_hp_changed.emit(120.0, 150.0)
	GameManager.roll_shop()
	GameManager.shop_opened.emit()
	await get_tree().create_timer(0.8).timeout
	await _shot("shot_4_shop.png")
	var shop := main.get_node_or_null("UILayer/WaveShop") as Control
	if shop != null:
		shop.visible = false
	get_tree().paused = false

	print("ALL_STORE_SHOTS_CAPTURED")
	get_tree().quit(0)

func _settle(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		await get_tree().create_timer(0.2).timeout
		left -= 0.2
		if get_tree().paused:
			var levelup := get_node_or_null("/root/Main/UILayer/LevelUpDialog")
			if levelup != null:
				levelup.visible = false
				GameManager.pending_upgrade_points = 0
				GameManager.alloc_offers.clear()
			get_tree().paused = false

func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path := OUT_DIR + "/" + file_name
	var err := img.save_png(path)
	print("STORE_SHOT %s err=%d size=%s" % [path, err, str(img.get_size())])
