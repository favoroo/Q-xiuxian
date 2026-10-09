extends Node

## 灵石阁出图台（非判据）：按真机三档屏宽把面板真建一遍、灌满最坏样本、点选一件法器，
## 存 PNG 用眼睛验收。运行（不能加 --headless，headless 不渲染、拿不到图）：
##   $G --path . res://tests/ShopLayoutPreview.tscn      # 产物 /tmp/shop_<档>.png
##
## 为什么要有它：LayoutCheck 那条「货架不许上下滑」量的是数字（最高那张卡要多高 vs 滚动区
## 给多高），全绿只说明放得下，说明不了为省竖向预算新排的这三处版看着对不对 ——
## ① 图标与名号同行；② 锁定从独占一行压成色签行右端一枚角键；③ 羁绊行右端挂「怎么用？」
## （原先那一整行操作提示收进了点按可得的详情卡）。样本与判据同源：同一批最长文案 +
## 满背包 + 点选后的操作条，别在这儿另编一套参数。

## 窗口尺寸 → 设计可视：1536x690 → 1202x540（用户真机 20:9）/ 960x540 → 960x540 / 1200x900 → 960x720
const SIZES: Array[Vector2i] = [Vector2i(1536, 690), Vector2i(960, 540), Vector2i(1200, 900)]
const TAGS: Array[String] = ["20_9", "16_9", "4_3"]

var _holder: Control

func _ready() -> void:
	DisplayServer.window_set_size(SIZES[0])
	await get_tree().process_frame
	_holder = Control.new()
	_holder.name = "ShopPreviewHolder"
	_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child(_holder)
	GameManager.cultivator_id = "jianchi"
	GameManager.start_run("qingyun_sword")
	GameManager.add_spirit_stones(500)
	_stress_inventory()
	for i in range(SIZES.size()):
		for count in [GameManager.SHOP_BASE_SLOTS, GameManager.SHOP_BASE_SLOTS + 1]:
			await _shoot(SIZES[i], TAGS[i], count)
	print("\nSHOP_PREVIEW_DONE")
	get_tree().quit(0)

## 陈列行与操作条是这一屏的两行固定开销：真机上背包会满、玩家一定会点选法器 ⇒ 灌满
func _stress_inventory() -> void:
	GameManager.stash.clear()
	for wid in ["qingyun_sword", "huoyan_fu", "chiyan_dao", "liuye_feidao", "wulei_paizi",
			"gengjin_feijian", "bajiao_fan", "fantian_yin", "fentian_baodeng"]:
		var def: Dictionary = WeaponData.get_def(wid)
		if def.is_empty() or GameManager.stash.size() >= WeaponData.MAX_STASH_SLOTS:
			continue
		GameManager.stash.append({"id": wid, "name": def.get("name", "?"), "star": 1,
			"icon": def.get("icon", ""), "tag": def.get("tag", "")})
	GameManager.drones.clear()
	GameManager.items.clear()
	GameManager.add_item(String(ItemData.all_ids()[0]))
	if ItemData.all_ids().size() > 1:
		GameManager.add_item(String(ItemData.all_ids()[1]))

## 把货架钉成最长文案：随机三张盖不住最坏情况，哪一句会撑破格子是数据决定的
func _pin_offers() -> void:
	var offers: Array = GameManager.shop_offers
	if offers.size() >= 2:
		offers[0] = {"kind": "potion", "id": WeaponData.POTION_ID, "price": 11,
			"sold": false, "locked": false}
		offers[1] = {"kind": "item", "id": String(ItemData.all_ids()[0]), "price": 14,
			"sold": false, "locked": false}
	var long_ids: Array[String] = ["chiyan_dao", "liuye_feidao", "wulei_paizi"]
	for i in range(mini(long_ids.size(), maxi(offers.size() - 2, 0))):
		offers[2 + i] = {"kind": "weapon", "id": long_ids[i], "price": 41,
			"sold": false, "locked": i % 2 == 0}

func _shoot(size: Vector2i, tag: String, count: int) -> void:
	DisplayServer.window_set_size(size)
	get_tree().root.size = size
	await get_tree().process_frame
	await get_tree().process_frame
	GameManager.shop_slots_bonus = maxi(0, count - GameManager.SHOP_BASE_SLOTS)
	GameManager.roll_shop(true)
	_pin_offers()
	var screen: Vector2 = get_tree().root.get_visible_rect().size
	var node: Control = load("res://scenes/ui/WaveShop.tscn").instantiate()
	node.visible = true
	_holder.add_child(node)
	await get_tree().process_frame
	node._on_shop_opened()
	await get_tree().create_timer(0.7).timeout
	# 点选背包里的一件 ⇒ 操作条出现，这一屏最坏的一档（货架能占的高最少）
	node.selected = {"pool": "stash", "index": 0}
	node._refresh_inventory()
	await get_tree().create_timer(0.5).timeout
	await get_tree().process_frame
	var scroll: ScrollContainer = node.offers_scroll
	var need_h := 0.0
	for card in node.offers_container.get_children():
		if card is Control:
			need_h = maxf(need_h, (card as Control).get_combined_minimum_size().y)
	var path := "/tmp/shop_%s_%d格.png" % [tag, count]
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOP %s 货架%d格 设计可视 %.0fx%.0f · 滚动区高 %.0f / 最高卡需 %.0f → %s · %s" % [
		tag, count, screen.x, screen.y, scroll.size.y, need_h,
		"一屏放完" if need_h <= scroll.size.y + 1.0 else "▲ 要上下滑", path])
	node.queue_free()
	await get_tree().process_frame
