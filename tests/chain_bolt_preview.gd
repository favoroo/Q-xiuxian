extends Node2D

## 雷系演出合成看尺（一次性工具，非判据）。
## 三组并排：天罚（贴身光柱 + lightning_strike 序列帧）、链电逐跳竖直落雷、范围武器落雷。
## 运行（不能 --headless）：$G --path . res://tests/ChainBoltPreview.tscn
## 产物 /tmp/chain_bolt_a.png（t≈0.02s 电弧在亮）与 /tmp/chain_bolt_b.png（t≈0.35s 序列帧中段）

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
	for p in CHAIN:
		var mark := _Dummy.new()
		mark.position = p
		world.add_child(mark)
	# 天罚：光柱 + 序列帧同点（游戏里 sky_bolt 的组合）
	JuiceEffect.spawn_sky_strike(world, TIANFA, GameStyle.FX_HDR_LIGHTNING)
	FxFlipbookPool.play(&"lightning_strike", TIANFA)
	# 链电：逐跳竖直落雷
	for i in CHAIN.size():
		ChainLightning._draw_hop_bolt(world, CHAIN[i], GameStyle.FX_HDR_ZIDIAN)
		JuiceEffect.spawn_body_arcs(world, CHAIN[i], GameStyle.FX_HDR_ZIDIAN)
	# 范围武器落雷：只有贴身光柱（本次收束后的样子）
	JuiceEffect.spawn_sky_strike(world, BURST, GameStyle.FX_HDR_LIGHTNING)
	await get_tree().create_timer(0.02).timeout
	get_viewport().get_texture().get_image().save_png("/tmp/chain_bolt_a.png")
	await get_tree().create_timer(0.33).timeout
	get_viewport().get_texture().get_image().save_png("/tmp/chain_bolt_b.png")
	await get_tree().create_timer(0.9).timeout
	get_viewport().get_texture().get_image().save_png("/tmp/chain_bolt_c.png")
	print("CHAIN_BOLT_RESULT: SHOT /tmp/chain_bolt_a|b|c.png")
	await get_tree().create_timer(0.2).timeout
	get_tree().quit()

class _Dummy extends Node2D:
	func _draw() -> void:
		draw_circle(Vector2.ZERO, 16.0, Color(0.35, 0.42, 0.5, 0.9))
		draw_circle(Vector2(0, 14), 5.0, Color(0.2, 0.24, 0.3, 0.9))
