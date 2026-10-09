extends Node

## 非判据量尺：把面板每一档屏宽下「画出来的边界」与「每一行占掉的高」打出来，给人看的数字版。
## 运行: $G --headless --path . res://tests/LayoutBleedProbe.tscn
##
## 为什么要有它：LayoutCheck 报的是「有没有毛病」，而「溢出多少、让位让掉多少」要看得见
## 才好判断改得对不对（用户说「有点溢出」，得有个数）。判据用同一份算术（drawn_rect 的
## 斜切口径与 LevelUpDialog.skew_x() 一致），这里只把每一格的读数摊开。
##
## 两块现场：① 悟道面板的斜切/放大余量；② 灵石阁逐行高（2026-10-09 用户：「上下滑动体验太差」
##    ⇒ 要算清「固定行吃掉了多少、货架还剩多少」，才知道该从哪一行省）。

const SIZES: Array[Vector2i] = [Vector2i(960, 720), Vector2i(960, 540), Vector2i(1204, 540)]

var _holder: Control

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	_holder = Control.new()
	_holder.name = "BleedHolder"
	_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child(_holder)
	GameManager.cultivator_id = "jianchi"
	GameManager.start_run("qingyun_sword")
	GameManager.pending_upgrade_points = 2
	GameManager.open_alloc_session()
	await get_tree().process_frame
	for w in SIZES:
		get_tree().root.size = w
		await get_tree().process_frame
		await get_tree().process_frame
		var screen: Vector2 = get_tree().root.get_visible_rect().size
		var node: Control = load("res://scenes/ui/LevelUpDialog.tscn").instantiate()
		node.visible = true
		_holder.add_child(node)
		await get_tree().process_frame
		node._on_alloc_opened()
		await get_tree().create_timer(0.6).timeout
		node._select_card(1)
		await get_tree().create_timer(0.4).timeout
		await get_tree().process_frame
		get_tree().paused = false
		print("\n===== 设计可视 %.0fx%.0f =====" % [screen.x, screen.y])
		var panel: Control = node.get_node("CenterContainer/Panel")
		var pr: Rect2 = _drawn(panel)
		print("面板 布局盒 %.0f..%.0f x %.0f..%.0f → 画出来 %.1f..%.1f" % [
			panel.get_global_rect().position.x, panel.get_global_rect().end.x,
			panel.get_global_rect().position.y, panel.get_global_rect().end.y,
			pr.position.x, pr.end.x])
		print("     离屏 左 %.1f 右 %.1f（PANEL_AIR_X=%s）" % [
			pr.position.x, screen.x - pr.end.x, str(LevelUpDialog.PANEL_AIR_X)])
		var row: Control = node.get_node(
			"CenterContainer/Panel/MarginContainer/VBox/CardScroll")
		var rr: Rect2 = row.get_global_rect()
		print("卡片行 y %.0f..%.0f（高 %.0f）" % [rr.position.y, rr.end.y, rr.size.y])
		var cont: Control = node.get_node(
			"CenterContainer/Panel/MarginContainer/VBox/CardScroll/CardsPad/CardsContainer")
		# ④ 滚动区横向不滚动 ⇒ 它会 clip，卡角画出来越界就是被削平（判据同一条尺）
		var sr: Rect2 = row.get_global_rect()
		var first: Control = cont.get_child(0) as Control
		var last: Control = cont.get_child(cont.get_child_count() - 1) as Control
		var fd: Rect2 = _drawn(first)
		var ld: Rect2 = _drawn(last)
		print("     滚动区 x %.1f..%.1f ｜ 首卡画出来 x %.1f 越界 %.1f ｜ 末卡画出来 x %.1f 越界 %.1f" % [
			sr.position.x, sr.end.x, fd.position.x,
			maxf(0.0, sr.position.x - fd.position.x), ld.end.x,
			maxf(0.0, ld.end.x - sr.end.x)])
		# ⑤ 底栏那颗按钮离**画出来的**面板右边还剩多少白（面板是平行四边形，底边整体左移）
		var ab: Control = node.get_node(
			"CenterContainer/Panel/MarginContainer/VBox/ActionBar/ConfirmButton")
		var ad: Rect2 = _drawn(ab)
		var pbox: Rect2 = panel.get_global_rect()
		var pcy: float = pbox.position.y + pbox.size.y * 0.5
		var right_at_top: float = pbox.end.x - LevelUpDialog.PANEL_SKEW_RAD * (ad.position.y - pcy)
		print("     确认领悟画出来 x %.1f..%.1f ｜ 面板画出来的右边在同一高度 %.1f ｜ 留白 %.1f" % [
			ad.position.x, ad.end.x, right_at_top, right_at_top - ad.end.x])
		var i := 0
		for card in cont.get_children():
			if not (card is Control):
				continue
			var d: Rect2 = _drawn(card)
			print("  卡#%d 画出来 x %.1f..%.1f  y %.1f..%.1f  离屏左 %.1f 离屏右 %.1f  %s" % [
				i, d.position.x, d.end.x, d.position.y, d.end.y, d.position.x, screen.x - d.end.x,
				"" if (d.position.y >= rr.position.y - 0.5 and d.end.y <= rr.end.y + 0.5)
					else "↑ 顶出这一行"])
			i += 1
		await _old_look(node, screen)
		node.queue_free()
		await get_tree().process_frame
	await _run_shop()
	print("\nBLEED_PROBE_DONE")
	get_tree().quit(0)

## 灵石阁：把 VBox 每一行的实得高摊开，再报「最高那张卡需要的高 vs 滚动区给的高」。
## 后者大于前者 = 这一屏必须竖着滑（用户 2026-10-09 报的就是这个）。
## 两档货架都量：5 格（默认）与 6 格（多宝道人 +1）—— 格数越多卡越窄、说明折得越多，
## 6 格才是竖向的最坏情况。
func _run_shop() -> void:
	for i in range(5):
		GameManager.apply_upgrade("melee_up")
		GameManager.apply_upgrade("elemental_up")
	GameManager.add_item(String(ItemData.all_ids()[0]))
	if ItemData.all_ids().size() > 1:
		GameManager.add_item(String(ItemData.all_ids()[1]))
	# 最坏样本要摆出「上阵 + 满背包 + 法宝」这一行。本量尺不建 Player，而 add_weapon 没有
	# player 节点就进不了上阵栏 ⇒ 直接灌 WaveShop._refresh_inventory 现读的那两份字段。
	GameManager.stash.clear()
	for wid in ["qingyun_sword", "huoyan_fu", "chiyan_dao", "liuye_feidao", "wulei_paizi",
			"gengjin_feijian", "bajiao_fan", "fantian_yin", "fentian_baodeng"]:
		var wdef: Dictionary = WeaponData.get_def(wid)
		if wdef.is_empty() or GameManager.stash.size() >= WeaponData.MAX_STASH_SLOTS:
			continue
		GameManager.stash.append({"id": wid, "name": wdef.get("name", "?"), "star": 1,
			"icon": wdef.get("icon", ""), "tag": wdef.get("tag", "")})
	GameManager.drones.append({"id": "lingdie", "star": 1})
	GameManager.drones.append({"id": "lingdie", "star": 1})
	GameManager.drones.append({"id": "lingdie", "star": 1})
	GameManager.recalc_synergies()
	for count in [GameManager.SHOP_BASE_SLOTS, GameManager.SHOP_BASE_SLOTS + 1]:
		GameManager.shop_slots_bonus = count - GameManager.SHOP_BASE_SLOTS
		GameManager.roll_shop(true)
		_stress_offers()
		for w in SIZES:
			await _shop_rows(w, count)

## 把货架钉成「最长文案 + 一半挂着锁定」：随机三张盖不住最坏情况，哪一句会撑破格子是数据决定的
func _stress_offers() -> void:
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

func _shop_rows(w: Vector2i, count: int) -> void:
	get_tree().root.size = w
	await get_tree().process_frame
	await get_tree().process_frame
	var screen: Vector2 = get_tree().root.get_visible_rect().size
	var node: Control = load("res://scenes/ui/WaveShop.tscn").instantiate()
	node.visible = true
	_holder.add_child(node)
	await get_tree().process_frame
	node._on_shop_opened()
	await get_tree().create_timer(0.6).timeout
	get_tree().paused = false
	print("\n===== 灵石阁 · 设计可视 %.0fx%.0f · 货架 %d 格 =====" % [screen.x, screen.y, count])
	var vbox: VBoxContainer = node.get_node("CenterContainer/Panel/MarginContainer/VBox")
	for ch in vbox.get_children():
		if not (ch is Control) or not (ch as Control).visible:
			continue
		var c := ch as Control
		print("  %-14s y %3.0f..%3.0f  高 %3.0f" % [String(c.name),
			c.position.y, c.position.y + c.size.y, c.size.y])
	var panel: Control = node.get_node("CenterContainer/Panel")
	print("  面板布局盒 %.0fx%.0f（屏 %.0fx%.0f）" % [
		panel.size.x, panel.size.y, screen.x, screen.y])
	_report_rows(node, "未点选")
	# 点选一件法器 ⇒ 操作条出现，这一屏的最坏情况
	var sum: Array = GameManager.get_weapons_summary()
	if not sum.is_empty():
		node.selected = {"pool": "equipped", "index": 0}
	elif not GameManager.stash.is_empty():
		node.selected = {"pool": "stash", "index": 0}
	node._refresh_inventory()
	await get_tree().create_timer(0.6).timeout
	await get_tree().process_frame
	_report_rows(node, "点选后")
	node.queue_free()
	await get_tree().process_frame

## 竖向：最高那张卡需要的高 vs 滚动区给的高；横向：陈列行与货架的可用宽
func _report_rows(node: Control, tag: String) -> void:
	var ab: Control = node.get_node("CenterContainer/Panel/MarginContainer/VBox/ActionBar")
	var scroll: ScrollContainer = node.offers_scroll
	var need_h := 0.0
	var tallest: Control = null
	for card in node.offers_container.get_children():
		if card is Control:
			var mh: float = (card as Control).get_combined_minimum_size().y
			if mh > need_h:
				need_h = mh
				tallest = card as Control
	var content_w: float = node.offers_container.size.x
	print("  [%s] 操作条%s · 滚动区高 %.0f / 最高卡需 %.0f → %s · 横向 %s（内容 %.0f / 可视 %.0f）" % [
		tag, "可见" if ab.visible else "未出现", scroll.size.y, need_h,
		"不用竖滑" if need_h <= scroll.size.y + 1.0 else "▲ 要竖滑 %.0f" % (need_h - scroll.size.y),
		"要滑" if scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO else "锁死",
		content_w, scroll.size.x])
	print("      陈列行最小宽 %.0f / 面板可用 %.0f → %s" % [
		node.owned_container.get_combined_minimum_size().x,
		WaveShop.panel_inner_w(node._screen),
		"▲ 横向摆不下" if node.owned_container.get_combined_minimum_size().x \
			> WaveShop.panel_inner_w(node._screen) + 1.0 else "放得下"])
	if tallest == null:
		return
	print("  ┌ 最高那张卡（%.0f）内部逐件：" % need_h)
	var stack: Array[Control] = [tallest]
	while not stack.is_empty():
		var cur: Control = stack.pop_back()
		for g in cur.get_children():
			if g is Control:
				stack.append(g)
		if cur == tallest or cur.size.y <= 0.0:
			continue
		var depth := 0
		var pr := cur.get_parent()
		while pr != null and pr != tallest:
			depth += 1
			pr = pr.get_parent()
		var txt := ""
		if cur is Label:
			txt = " 「%s」" % String((cur as Label).text).replace("\n", "⏎")
		elif cur is Button:
			txt = " 「%s」" % String((cur as Button).text).replace("\n", "⏎")
		print("  │ %s%-16s 最小高 %3.0f 实得 %3.0f 最小宽 %3.0f%s" % [
			"  ".repeat(depth + 1), String(cur.name) + ":" + cur.get_class(),
			cur.get_combined_minimum_size().y, cur.size.y,
			cur.get_combined_minimum_size().x, txt])

## 反例复现：把这一屏摆回改之前的样子（面板布局盒铺满屏宽 + 这一行不留放大余量），
## 用同一把尺再量一遍 —— 判据的牙齿要用数字证明，不是靠说。
func _old_look(node: Control, screen: Vector2) -> void:
	var panel: Control = node.get_node("CenterContainer/Panel")
	var pad: MarginContainer = node.get_node(
		"CenterContainer/Panel/MarginContainer/VBox/CardScroll/CardsPad")
	var row: Control = node.get_node("CenterContainer/Panel/MarginContainer/VBox/CardScroll")
	var cont: Control = node.get_node(
		"CenterContainer/Panel/MarginContainer/VBox/CardScroll/CardsPad/CardsContainer")
	var old_min: Vector2 = panel.custom_minimum_size
	panel.custom_minimum_size = Vector2(screen.x, old_min.y)
	pad.add_theme_constant_override("margin_top", 0)
	pad.add_theme_constant_override("margin_bottom", 0)
	var old_pad_x := Vector2(pad.get_theme_constant("margin_left"),
		pad.get_theme_constant("margin_right"))
	pad.add_theme_constant_override("margin_left", 0)
	pad.add_theme_constant_override("margin_right", 0)
	await get_tree().process_frame
	await get_tree().process_frame
	# 容器重排会把子节点的 scale 打回 1.0（引擎行为）⇒ 放大这一项重排后要自己按上
	var sel: Control = cont.get_child(1) as Control
	sel.pivot_offset = sel.size * 0.5
	sel.scale = Vector2(LevelUpDialog.SEL_SCALE, LevelUpDialog.SEL_SCALE)
	await get_tree().process_frame
	var pd: Rect2 = _drawn(panel)
	var rr: Rect2 = row.get_global_rect()
	var d: Rect2 = _drawn(sel)
	print("  [反例复现·旧摆位] 面板画出来 %.1f..%.1f → 两头各被屏幕切掉 %.1f 单位；" % [
		pd.position.x, pd.end.x, maxf(-pd.position.x, pd.end.x - screen.x)])
	print("      选中卡撑满整行再放大 → 画出来 y %.1f..%.1f，顶出这一行（y %.0f..%.0f）上 %.1f 下 %.1f" % [
		d.position.y, d.end.y, rr.position.y, rr.end.y,
		maxf(0.0, rr.position.y - d.position.y), maxf(0.0, d.end.y - rr.end.y)])
	var ocont: Control = cont
	var ofirst: Rect2 = _drawn(ocont.get_child(0) as Control)
	var orow: Rect2 = row.get_global_rect()
	print("      滚动区不留卡角白 → 首卡画出来 x %.1f 越过滚动区左边界 %.1f，被 clip 削掉 %.1f 单位" % [
		ofirst.position.x, orow.position.x, maxf(0.0, orow.position.x - ofirst.position.x)])
	panel.custom_minimum_size = old_min
	var g := int(LevelUpDialog.pop_gutter_y(screen.y))
	pad.add_theme_constant_override("margin_top", g)
	pad.add_theme_constant_override("margin_bottom", g)
	pad.add_theme_constant_override("margin_left", int(old_pad_x.x))
	pad.add_theme_constant_override("margin_right", int(old_pad_x.y))

## 与判据同一口径：get_global_rect() 已含缩放，再按这份 stylebox 的 skew 左右各伸出半个斜切
func _drawn(c: Control) -> Rect2:
	var r: Rect2 = c.get_global_rect()
	var skew := 0.0
	for key in ["panel", "normal"]:
		if c.has_theme_stylebox(key) and c.get_theme_stylebox(key) is StyleBoxFlat:
			skew = (c.get_theme_stylebox(key) as StyleBoxFlat).skew.x
			break
	var over: float = absf(skew) * r.size.y * 0.5
	return Rect2(r.position.x - over, r.position.y, r.size.x + over * 2.0, r.size.y)
