extends Node2D

## 雷系演出合成看尺（一次性工具，非判据）。
## 三组并排：天罚（贴身光柱 + lightning_strike 序列帧）、链电（体缘连线 + 缠身电）、范围武器落雷。
## 运行（不能 --headless）：$G --path . res://tests/ChainBoltPreview.tscn
## 产物 /tmp/chain_bolt_a.png（t≈0.02s 电弧在亮）与 /tmp/chain_bolt_b.png（t≈0.35s 序列帧中段）
##
## 2026-11-07 电刀重做后的样子：链电只剩「体缘连线弧 + 缠身电」两种图形，
## 两端都钉在敌人身上 —— 头顶那根悬空竖雷柱已下线（用户口径「不要飞到空气里」）。

const TIANFA := Vector2(180, 320)
const CHAIN: Array[Vector2] = [Vector2(430, 300), Vector2(500, 380), Vector2(575, 300)]
const BURST := Vector2(800, 320)

func _ready() -> void:
	get_tree().root.size = Vector2i(960, 540)
	var bg := ColorRect.new()
	bg.size = Vector2(960, 540)
	bg.color = Color(0.06, 0.09, 0.11)
	add_child(bg)
	var world := Node2D.new()
	add_child(world)
	var marks: Array[Node2D] = []
	for p in CHAIN:
		var mark := _Dummy.new()
		mark.position = p
		world.add_child(mark)
		marks.append(mark)
	# 天罚：光柱 + 序列帧同点（游戏里 sky_bolt 的组合）
	JuiceEffect.spawn_sky_strike(world, TIANFA, GameStyle.FX_HDR_LIGHTNING)
	FxFlipbookPool.play(&"lightning_strike", TIANFA)
	# 链电：相邻两怪之间一条体缘连线 + 每只怪身上一簇缠身电
	for i in marks.size():
		JuiceEffect.spawn_body_arcs(world, marks[i].global_position, GameStyle.FX_HDR_ZIDIAN,
			JuiceEffect.BODY_ARC_RADIUS, JuiceEffect.BODY_ARC_COUNT, marks[i])
		if i > 0:
			var bolt := LightningBolt.acquire(world)
			if bolt != null:
				bolt.activate_tracked(marks[i - 1], marks[i], Vector2.ZERO, Vector2.ZERO,
					ChainLightning.LINK_EDGE_TRIM, ChainLightning.LINK_EDGE_TRIM, true,
					GameStyle.FX_HDR_ZIDIAN, ChainLightning.BOLT_WIDTH)
	# 范围武器落雷：只有贴身光柱（本次收束后的样子）
	JuiceEffect.spawn_sky_strike(world, BURST, GameStyle.FX_HDR_LIGHTNING)
	# 抓帧必须等「这一帧真的画完了」：create_timer 走的是 idle 时钟，首帧前截图会拿到纯黑
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/chain_bolt_a.png")
	var live := 0
	if LightningBolt._host != null:
		for child in LightningBolt._host.get_children():
			var b := child as LightningBolt
			if b != null and b.visible and b._line_core.visible and b._line_core.points.size() >= 2:
				live += 1
	print("CHAIN_BOLT_RESULT: SHOT /tmp/chain_bolt_a|b|c.png (可见电弧 %d 条)" % live)
	await get_tree().create_timer(0.33).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/chain_bolt_b.png")
	await get_tree().create_timer(0.9).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/chain_bolt_c.png")
	await get_tree().create_timer(0.2).timeout
	get_tree().quit()

class _Dummy extends Node2D:
	func _draw() -> void:
		draw_circle(Vector2.ZERO, 16.0, Color(0.35, 0.42, 0.5, 0.9))
		draw_circle(Vector2(0, 14), 5.0, Color(0.2, 0.24, 0.3, 0.9))
