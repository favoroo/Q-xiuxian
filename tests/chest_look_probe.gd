extends Node

## 藏宝匣「三档耐久长什么样」现场看尺（非判据预览工具，2026-10-10）
##
## 为什么要单独看：匣子的外观与耐久是同一件事的两半 —— 满匣要好看（用户口径「宝箱太简陋」），
## 挨过几下要一眼读得出来（否则头顶三格小牌就是唯一线索，而牌在匣盖上方 60px，眼睛不在那儿）。
## EntitySizeProbe 只量静止满血那一只的尺寸，看不出受损两档画成什么样，这里补齐。
##
## 口径：用真的 SpiritChest（含 SIZE_MULT 缩放链与登场 tween），靠 take_damage 推进耐久，
## 不手工设 _loot_renderer 字段 —— 那样量的是「我拼出来的样子」而不是「玩家看到的样子」。
##
## 运行（要真实渲染，不能用 --headless）:
##   $G --path . res://tests/ChestLookProbe.tscn
##   → /tmp/chest_stages.png（满匣 / 剩 2 格 / 剩 1 格 三只并排）

const BG := Color(0.02, 0.03, 0.05)
const SETTLE_FRAMES := 60

func _ready() -> void:
	Engine.time_scale = 1.0
	get_tree().root.size = Vector2i(960, 540)

	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var world := Node2D.new()
	add_child(world)

	# 满血 → 挨 1 下 → 挨 2 下：三档并排，间距取匣子宽的 1.6 倍，互不吃进对方的画
	for stage in range(3):
		var chest := SpiritChest.new()
		chest.global_position = Vector2(330 + stage * 150, 270)
		world.add_child(chest)
		for i in range(stage):
			chest.take_damage(1.0, Vector2.RIGHT)

	for i in range(SETTLE_FRAMES):
		await get_tree().process_frame

	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		print("CHEST_LOOK_RESULT: NO PIXELS（不要用 --headless）")
		get_tree().quit(1)
		return
	var out := "/tmp/chest_stages.png"
	img.save_png(out)
	print("CHEST_LOOK_RESULT: SHOT %s" % out)
	get_tree().quit(0)
