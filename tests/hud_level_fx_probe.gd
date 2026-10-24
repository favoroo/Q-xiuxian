extends Node

## 非判据现场预览：升级动效逐帧抓拍（要真实出图，运行时不加 --headless）。
## 运行: $G --path . res://tests/HudLevelFxProbe.tscn
## 抓帧落 /tmp/lvfx_probe/，供人工核对斜切方向/星屑迸发/金光浓度（无断言，不影响判据）。
## 只实例化 GameHUD 而不 boot 整个 Main：多 Agent 并行开发时战斗链路的中间态
## （ProceduralDroneRenderer 等在途脚本）可能编译不过，预览不该被它连坐。

const BIG_EXP := 500

var _hud: Control

func _ready() -> void:
	call_deferred("_boot")

func _boot() -> void:
	# headless 无渲染：get_image() 恒 null，save_png 抛脚本错误打断 await 链，
	# quit(0) 永远执行不到 ⇒ run_test --all 里被看门狗强杀误报 TIMEOUT。
	if DisplayServer.get_name() == "headless":
		print("[HudLevelFxProbe] headless 无渲染意义，退出")
		get_tree().quit(0)
		return
	DirAccess.make_dir_recursive_absolute("/tmp/lvfx_probe")
	_hud = (load("res://scenes/ui/GameHUD.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(_hud)
	for i in 12:
		await get_tree().process_frame
	GameManager.add_experience(BIG_EXP)
	# 升级瞬间起每 4 帧抓一张，覆盖约 1s 的动效窗口
	for i in 15:
		for f in 4:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png("/tmp/lvfx_probe/f_%02d.png" % i)
	get_tree().quit(0)
