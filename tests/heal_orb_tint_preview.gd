extends Node

## 回复珠两相出图对比（非判据，要真实出图，别加 --headless）
## 用法：godot --path . res://tests/HealOrbTintPreview.tscn
##
## 为什么立这个现场工具：满血待命那颗只是「压成灰相」，色差不一眼就得重做。
## 这里把四档并排画出来 —— 可入口 / 满血待命 / 波末飞行途中 / 已被吃掉 ——
## 与判据共用 HealOrb 的同一对常数（TINT_READY / TINT_WAITING），不另调一份色值。

func _ready() -> void:
	var title := Label.new()
	title.text = "回复珠两相：左=可入口  右=满血待命（同一个 sprite，只换 modulate）"
	title.add_theme_font_override("font", GameStyle.display_font())
	title.add_theme_font_size_override("font_size", 20)
	title.position = Vector2(24, 16)
	add_child(title)

	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.09, 0.13)
	bg.size = Vector2(960, 540)
	bg.z_index = -1
	add_child(bg)

	# 四格：可入口 / 待命 / 待命 + 名牌 / 已吃掉（空位，免得以为漏画）
	_spot(Vector2(180, 260), HealOrb.TINT_READY, "可入口 TINT_READY")
	_spot(Vector2(420, 260), HealOrb.TINT_WAITING, "满血待命 TINT_WAITING")
	_spot(Vector2(660, 260), HealOrb.TINT_READY, "波末结算中（飞进袖中）")
	_spot(Vector2(860, 260), Color(0, 0, 0, 0), "已入口 → 空手（只剩判定圈示意）")

	if DisplayServer.get_name() == "headless":
		await get_tree().create_timer(0.1).timeout
		get_tree().quit(0)

func _spot(pos: Vector2, tint: Color, caption: String) -> void:
	var holder := Node2D.new()
	holder.position = pos
	add_child(holder)

	var orb := HealOrb.new()
	holder.add_child(orb)
	orb.global_position = pos
	# 判据同源：色相直接取 HealOrb 自己那对常数，不在这里重画一颗珠子
	orb._set_waiting(tint == HealOrb.TINT_WAITING)
	if tint != HealOrb.TINT_WAITING and tint.a > 0.0:
		orb._sprite.modulate = tint

	# 判定圈画出来：视觉=判定（贴身那一圈 = 珠子圆 + 玩家身体圆）。
	# 半径从珠子自己的碰撞形状现读，不在这里抄一份 —— 它改小了这里跟着走。
	# 注意别按节点名取：纯代码建出来的节点是 @CollisionShape2D@N 这种占位名。
	var ring_r := 10.0
	for c in orb.get_children():
		if c is CollisionShape2D and c.shape is CircleShape2D:
			ring_r = (c.shape as CircleShape2D).radius
			break
	var ring := Line2D.new()
	ring.width = 2.0
	ring.default_color = Color(1.0, 0.82, 0.35, 0.7)
	ring.closed = true
	for i in range(32):
		var a := TAU * float(i) / 32.0
		ring.add_point(Vector2(cos(a), sin(a)) * ring_r)
	holder.add_child(ring)

	var label := Label.new()
	label.text = caption
	label.add_theme_font_override("font", GameStyle.body_font())
	label.add_theme_font_size_override("font_size", 16)
	label.position = pos + Vector2(-84, 60)
	add_child(label)
