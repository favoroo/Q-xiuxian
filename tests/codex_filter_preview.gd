extends Node

## 非判据现场工具：渲染图鉴武器页的流派筛选态并截图到项目根 tmp_codex_*.png，供目检排版。
## 用法（勿加 --headless）：$G --path . res://tests/CodexFilterPreview.tscn

func _ready() -> void:
	var manual := ManualDialog.new()
	add_child(manual)
	manual.open()
	await _frames(2)
	manual.switch_tab(0)
	await _frames(2)
	_snap("tmp_codex_all.png")
	manual.open_weapons_page("spirit")
	await _frames(2)
	_snap("tmp_codex_spirit.png")
	manual.open_weapons_page("fire")
	await _frames(2)
	_snap("tmp_codex_fire.png")
	get_tree().quit(0)

func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _snap(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var tex := get_viewport().get_texture()
	var img := tex.get_image() if tex != null else null
	if img != null:
		img.save_png("res://" + path)
		print("SAVED " + path)
