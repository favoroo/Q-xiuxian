extends Node

## 悟道加点面板出图台（非判据）：按真机三档屏宽把面板真建一遍、真选中一张卡，存 PNG 用眼睛验收。
## 运行（不能加 --headless，headless 不渲染、拿不到图）：
##   $G --path . res://tests/LevelUpLayoutPreview.tscn      # 产物 /tmp/alloc_layout_<档>.png
##
## 为什么要有它：LayoutCheck 量的是「画出来的边界在不在屏内」，全绿只说明没被切掉，
## 说明不了「贴边贴得让人以为溢出了」。用户报的是观感 ⇒ 得有一张能看的图，
## 并且两头留多少白要能在图上量出来（图旁打印的 air 就是像素数）。
##
## 摆位算术不另编一套：直接走 LevelUpDialog 自己的 _layout_for_viewport()，
## 候选钉成文案最长的那 5 条（随机三张盖不住最坏情况），稀有度按 凡/良/仙 各留样。

## 窗口尺寸 → 设计可视：1536x690 → 1202x540（用户真机 20:9）/ 960x540 → 960x540 / 1200x900 → 960x720
const SIZES: Array[Vector2i] = [Vector2i(1536, 690), Vector2i(960, 540), Vector2i(1200, 900)]
const TAGS: Array[String] = ["20_9", "16_9", "4_3"]

var _holder: Control

func _ready() -> void:
	DisplayServer.window_set_size(SIZES[0])
	await get_tree().process_frame
	_holder = Control.new()
	_holder.name = "PreviewHolder"
	_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child(_holder)
	GameManager.cultivator_id = "jianchi"
	GameManager.start_run("qingyun_sword")
	GameManager.pending_upgrade_points = 2
	GameManager.open_alloc_session()
	_pin_worst_offers()
	for i in range(SIZES.size()):
		DisplayServer.window_set_size(SIZES[i])
		get_tree().root.size = SIZES[i]
		await get_tree().process_frame
		await get_tree().process_frame
		var screen: Vector2 = get_tree().root.get_visible_rect().size
		var node: Control = load("res://scenes/ui/LevelUpDialog.tscn").instantiate()
		node.visible = true
		_holder.add_child(node)
		await get_tree().process_frame
		node._on_alloc_opened()
		await get_tree().create_timer(0.7).timeout
		node._select_card(3)
		await get_tree().create_timer(0.5).timeout
		get_tree().paused = false
		await get_tree().process_frame
		var panel: Control = node.get_node("CenterContainer/Panel")
		var pr: Rect2 = panel.get_global_rect()
		var over: float = LevelUpDialog.skew_x(pr.size.y)
		print("===== %s · 设计可视 %.0fx%.0f =====" % [TAGS[i], screen.x, screen.y])
		print("  面板布局盒 %.1f..%.1f → 画出来 %.1f..%.1f，两头各离屏 %.1f 单位" % [
			pr.position.x, pr.end.x, pr.position.x - over, pr.end.x + over,
			pr.position.x - over])
		var cont: Control = panel.get_node(
			"MarginContainer/VBox/CardScroll/CardsPad/CardsContainer")
		print("  卡宽 %.1f 卡间缝 %.1f 卡内容宽 %.1f" % [
			node._card_w, float(cont.get_theme_constant("separation")),
			LevelUpDialog.card_inner_w(node._card_w)])
		await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		var path := "/tmp/alloc_layout_%s.png" % TAGS[i]
		img.save_png(path)
		print("  SAVED %s %s" % [path, img.get_size()])
		node.queue_free()
		await get_tree().process_frame
	print("\nALLOC_LAYOUT_DONE")
	get_tree().quit(0)

## 钉成最坏样本：desc 最长的那 5 条，且凡/良/仙各有（边框色不同、良品那枚色签更宽）
func _pin_worst_offers() -> void:
	var scored: Array = []
	for u in UpgradeData.UPGRADES:
		var plain: String = String(u.get("desc", "")).replace("[center]", "").replace("[/center]", "")
		for tag in ["[color=#ffd24d]", "[/color]", "[b]", "[/b]", "•", "\n"]:
			plain = plain.replace(tag, "")
		scored.append({"id": String(u.get("id", "")), "len": plain.length()})
	scored.sort_custom(func(a, b): return int(a["len"]) > int(b["len"]))
	var picked_ids: Array[String] = []
	for rarity in ["epic", "rare", "common"]:
		for s in scored:
			if picked_ids.size() >= GameManager.UPGRADE_OFFER_COUNT:
				break
			var uid: String = String(s["id"])
			if uid in picked_ids:
				continue
			if String(UpgradeData.get_upgrade_def(uid).get("rarity", "")) != rarity:
				continue
			picked_ids.append(uid)
	for s in scored:
		if picked_ids.size() >= GameManager.UPGRADE_OFFER_COUNT:
			break
		if String(s["id"]) not in picked_ids:
			picked_ids.append(String(s["id"]))
	var offers: Array[Dictionary] = []
	for uid in picked_ids:
		var d: Dictionary = UpgradeData.get_upgrade_def(uid).duplicate()
		d["border_color"] = UpgradeData.RARITY_COLORS.get(d.get("rarity", "common"), Color.WHITE)
		offers.append(d)
	GameManager.alloc_offers = offers
