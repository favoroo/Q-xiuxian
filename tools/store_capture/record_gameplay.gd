extends Node

## 录制 18 秒纯实机战斗录屏（无任何额外字幕、无外部包装，纯游戏原生画面与音效）
## 满足 TapTap 实机录屏（gameplay_demo_video）全部规范要求：
## 1. 长度 18 秒（>15 秒）
## 2. 1280x720 16:9
## 3. 前 5 秒即为核心玩法战斗，持续展示 > 10 秒
## 4. 无额外人声配音及字幕，无画中画，无设备边框

var _timer: float = 0.0
const RECORD_DURATION: float = 18.0

func _ready() -> void:
	call_deferred("_start")

func _start() -> void:
	var main: Node = load("res://scenes/main/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	for ui_name in ["StartMenu", "CultivatorSelect", "StageBackdrop"]:
		var ui := main.get_node_or_null("UILayer/" + ui_name) as Control
		if ui != null:
			ui.visible = false

	var hud := main.get_node_or_null("UILayer/GameHUD") as Control
	if hud != null:
		hud.visible = true

	GameManager.cultivator_id = "jianchi"
	GameManager.start_run("qingyun_sword")
	get_tree().paused = false

	# 开启无敌避免录制中途暴毙
	GameManager.author_mode = true
	AuthorMode.god_mode = true

	# 添置几把法器，让战斗画面更加酷炫
	GameManager.add_weapon("gengjin_feijian")
	GameManager.add_weapon("thunder_burst")
	GameManager.add_weapon("wood_talisman")

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= RECORD_DURATION:
		print("GAMEPLAY_RECORD_FINISHED %f s" % _timer)
		get_tree().quit(0)
