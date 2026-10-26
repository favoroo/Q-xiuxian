extends Node

## 飞升悟道出图台（非判据）：把普通悟道与飞升悟道两屏真建一遍、各出一张 PNG，
## 用眼睛验收「两屏一眼分得开」——判据只量得到文案与结构，量不到卡面染色。
## 运行（不能加 --headless，headless 不渲染、拿不到图）：
##   $G --path . res://tests/SuperAllocVisualPreview.tscn      # 产物 /tmp/alloc_<档>.png
##
## 两屏共用同一套摆位与选中流程（飞升面板继承普通面板），所以并排出图时
## 差异只可能来自 ① 面板赤红皮 ② 卡面淡红染底/加粗红框/红图标框，
## 正是这次改动的全部内容。

const SIZES: Array[Vector2i] = [Vector2i(1536, 690), Vector2i(960, 540)]
const TAGS: Array[String] = ["20_9", "16_9"]

var _holder: Control

func _ready() -> void:
	DisplayServer.window_set_size(SIZES[0])
	await get_tree().process_frame
	_holder = Control.new()
	_holder.name = "AllocPreviewHolder"
	_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child(_holder)
	for i in range(SIZES.size()):
		await _shoot_normal(SIZES[i], TAGS[i])
		await _shoot_super(SIZES[i], TAGS[i])
	print("\nSUPER_ALLOC_PREVIEW_DONE")
	get_tree().quit(0)

## 普通悟道屏：回合后统一加点那屏，5 张候选、带刷新键
func _shoot_normal(size: Vector2i, tag: String) -> void:
	await _prep(size)
	GameManager.pending_upgrade_points = 1
	# 节点必须先入树（_ready 才连上 alloc_opened），再开会话，否则面板收不到打开信号
	var node: Control = load("res://scenes/ui/LevelUpDialog.tscn").instantiate()
	_holder.add_child(node)
	await get_tree().process_frame
	AllocSession.open_alloc_session(GameManager)
	await get_tree().create_timer(0.6).timeout
	node._can_interact = true
	node._select_card(0)
	await get_tree().create_timer(0.4).timeout
	await _shot("/tmp/alloc_normal_%s.png" % tag)
	node.queue_free()
	get_tree().paused = false
	await get_tree().process_frame

## 飞升悟道屏：第 5/10/15 回合的专属屏，5 张逆天卡、无刷新键
func _shoot_super(size: Vector2i, tag: String) -> void:
	await _prep(size)
	GameManager.wave_number = 5
	var node: Control = load("res://scenes/ui/SuperAllocDialog.tscn").instantiate()
	_holder.add_child(node)
	await get_tree().process_frame
	SuperAllocSession.open(GameManager)
	await get_tree().create_timer(0.6).timeout
	node._can_interact = true
	node._select_card(0)
	await get_tree().create_timer(0.4).timeout
	await _shot("/tmp/alloc_super_%s.png" % tag)
	node.queue_free()
	get_tree().paused = false
	await get_tree().process_frame

func _prep(size: Vector2i) -> void:
	DisplayServer.window_set_size(size)
	get_tree().root.size = size
	GameManager.reset_run()
	GameManager.cultivator_id = "jianchi"
	await get_tree().process_frame
	await get_tree().process_frame

func _shot(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP 出图（headless 不渲染）: %s" % path)
		return
	# 必须等这一帧真画完再取纹理：直接在 process_frame 后取，拿到的是还没提交的空图
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var tex := get_viewport().get_texture()
	var img := tex.get_image() if tex != null else null
	if img != null and not img.is_empty():
		img.save_png(path)
		print("SHOT %s（%dx%d）" % [path, img.get_width(), img.get_height()])
	else:
		print("SHOT FAILED %s" % path)
