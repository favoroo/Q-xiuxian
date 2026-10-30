extends Node2D

## 选人界面皮肤栏预览（非判据现场工具）：逐角色整幅实拍选人界面，
## 验收皮肤栏 8 格（原色 + 6 系列）的色标条、选中框、锁定态。
## 运行（必须带视口，严禁 --headless）：
##   $G --path . res://tests/SkinSlotPreview.tscn
## 产物：tests/inspect/skin_slot_<cid>.png
##
## 坑：_select_cultivator 在 cid == _selected_id（默认 jianchi）时直接 return，
## 所以首个角色必须走 _rebuild_all()，否则详情卡永远不建。

const CIDS: Array[String] = ["jianchi", "fuzhen", "bawang"]
const SETTLE_FRAMES := 20

func _ready() -> void:
	GameManager.author_mode = true

	var sel := CultivatorSelect.new()
	sel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(sel)
	sel.visible = true
	for i in range(SETTLE_FRAMES):
		await get_tree().process_frame

	for cid in CIDS:
		sel.set("_selected_id", cid)
		sel.call("_rebuild_all")
		for i in range(SETTLE_FRAMES):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var full := get_viewport().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute("res://tests/inspect")
		full.save_png("res://tests/inspect/skin_slot_%s.png" % cid)
		print("SKIN_SLOT_SAVED: %s" % cid)

	GameManager.author_mode = false
	get_tree().quit()
