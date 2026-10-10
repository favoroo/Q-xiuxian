extends Node

## 顶栏波次倒计时现场预览台（非判据）：把真游戏驱动到三种波次状态，截顶栏那一格放大看。
## 运行（**不能加 --headless**，headless 不渲染拿不到图）：
##   $G --path . res://tests/WaveCountdownPreview.tscn
## 产物 /tmp/wave_countdown_shots/{mid,urgent,boss}.png（整屏）+ 同名 _chip.png（芯片 ×4 放大）。
##
## 为什么值得单独立一台：判据量的是「秒数与线长对不对得上 spawner 那一格」，
## 量不到「那条 3 高的线在 15 号字底下露没露出来、有没有压住字、告急那一下读不读得出来」——
## 这类只有真出图看得见（ObeliskReadout 拆分时就栽过一次：判据全绿、画出来是默认灰对勾）。

const OUT_DIR := "/tmp/wave_countdown_shots"
## 芯片放大倍率：3 设计像素高的线在 960×540 原图里根本看不出名堂
const ZOOM := 4

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(Vector2i(960, 540))
	var main: Node = load("res://scenes/main/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	main.get_node("UILayer/StartMenu").visible = false
	GameManager.cultivator_id = "jianchi"
	GameManager.start_run("qingyun_sword")
	get_tree().paused = false

	var spawner: Node = GameManager.wave_spawner
	var hud: GameHUD = main.get_node("UILayer/GameHUD")
	# 开局横幅与震屏先落定，截的才是静止位
	await get_tree().create_timer(2.6).timeout

	spawner.wave_timer = 14.0
	await _grab(hud, "mid")
	spawner.wave_timer = 3.0
	await _grab(hud, "urgent")
	spawner.start_wave(10)
	await get_tree().create_timer(2.6).timeout
	await _grab(hud, "boss")

	print("已出图 → %s（mid / urgent / boss，各配 _chip.png 放大 %d 倍）" % [OUT_DIR, ZOOM])
	get_tree().quit(0)

func _grab(hud: GameHUD, tag: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_tree().root.get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT_DIR, tag])
	var chip: Control = hud.wave_countdown.get_parent()
	var r := chip.get_global_rect().grow(6.0)
	var crop := img.get_region(Rect2i(Vector2i(int(r.position.x), int(r.position.y)), Vector2i(int(r.size.x), int(r.size.y))))
	crop.resize(int(crop.get_size().x) * ZOOM, int(crop.get_size().y) * ZOOM, Image.INTERPOLATE_NEAREST)
	crop.save_png("%s/%s_chip.png" % [OUT_DIR, tag])
	print("%s ⇒ %s · 芯片格 %.0f×%.0f" % [tag, hud.wave_countdown.readout_text(), crop.get_size().x / float(ZOOM), crop.get_size().y / float(ZOOM)])
