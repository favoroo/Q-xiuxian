class_name ShopInventoryRow
extends RefCounted

## 商店陈列行（上阵 + 背包 + 道具）的单格构建：槽位 / 上阵空格 / 容量签 / 分隔签 / 道具徽记 / 空槽。
## 从 WaveShop 拆出：整行的编排（_refresh_inventory）仍在 WaveShop，
## 点选回调经 shop 门面回流（选中态与悬浮详情卡都归 shop 管）。

## 单格武器槽：不用 Button —— BaseButton 在自己的 gui_input 里 accept_event()，「按下」
## 那一拍不往父级冒泡 ⇒ 手指压在槽位上就划不动整排，而满仓 30 格里几乎全是槽位。
## 属性面板的槽位同一口径（PanelContainer + GameStyle.tap，见 PlayerStatsDialog._refresh_weapons）。
static func create_inv_slot(shop: WaveShop, item: Dictionary, index: int, pool: String, tile: float) -> Control:
	var id: String = item.get("id", "")
	var star: int = int(item.get("star", 1))
	var mergeable: bool = star < WeaponData.MAX_STAR and GameManager.count_copies(id, star) >= 3
	var is_sel: bool = shop.selected.get("pool", "") == pool and int(shop.selected.get("index", -1)) == index

	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(tile, tile)
	slot.mouse_filter = Control.MOUSE_FILTER_PASS

	# 两个通道各说各的：底色说「这件在哪一格池子里」，描边说「它是什么属性」，
	# 角标说「这一刻能对它做什么」（可合成=左上「合」，星级=右下 ★n）。
	# 为什么底色要现调：GameStyle 里 NAVY 与 NAVY2 早在 #29/#31 那轮色彩校准里一起翻成纯黑，
	# 拿它们当池子区分等于没区分 —— 上阵位压一层主蓝薄底，与纯黑背包位拉开（2026-10-12 出图验收）。
	# 2026-10-14 用户：上阵/背包的武器要与货架大卡同一副语言 ⇒ 外边框统一五行属性色，
	# 池位区分只交给底色，边框不再表达池位。
	var bg: Color = GameStyle.NAVY2
	var border: Color = GameStyle.weapon_element_color(id, GameStyle.LINE)
	if pool == "equipped":
		bg = GameStyle.with_alpha(GameStyle.GOLD, 0.14)
	# 描边双通道独立拆分：
	# 元素特性不侵占外框，由底部 3px 暖橙红下边框恒定指示（GameStyle.apply_elemental_bottom_bar）；
	# 外边框优先级从低到高：五行基础 → 已选中。
	# 2026-10-18 用户：可合成的 JADE 亮黄边与金系古金边同色系撞车，五行这条信息被整圈刷掉
	# ⇒ 外框永远说五行，「这一刻能合成」改由左上角「合」字徽说（与右下 ★n 同一副文字语言）。
	if is_sel:
		border = GameStyle.PAPER
		bg = bg.lightened(0.12)
	var sb := GameStyle.outlined_panel(bg, border, 2, 0.0)
	# 图标与星角共用的内缩：PanelContainer 把每个子节点都铺满内容区，内缩只能给在 stylebox 上。
	# 2026-10-12 用户真机：这一排图标「都看不清」⇒ 格子放大后内缩按比例收，把地方让给图。
	sb.content_margin_left = 2.0
	sb.content_margin_top = 2.0
	sb.content_margin_right = 2.0
	sb.content_margin_bottom = 2.0
	slot.add_theme_stylebox_override("panel", sb)

	var icon_path: String = item.get("icon", "")
	if icon_path.is_empty():
		icon_path = WeaponData.get_def(id).get("icon", "")

	var icon_tex := GameStyle.icon_texture_rect(icon_path)
	slot.add_child(icon_tex)

	# 元素武器底部暖橙红下边框（吃「元素伤害」属性加成）：恒定显示，不与可合成/选中争抢外框
	if GameStyle.is_elemental(id):
		GameStyle.apply_elemental_bottom_bar(slot, true, 3.0)

	# 星级跟着格子长：44 格上 11 号字还行，60 格上就缩成灰了
	GameStyle.star_label(slot, star, int(round(clampf(tile * 0.24, 12.0, 16.0))))

	# 可合成角标：左上角「合」字（与右下 ★n 同一副文字语言，共用 PanelContainer 铺满子节点
	# 的对齐写法，不画底以免整格刷黄）。2026-10-18 用户：JADE 亮黄边与金系古金撞色 ⇒ 合成
	# 状态不再侵占外框，外框永远说五行。
	if mergeable:
		_add_merge_badge(slot, tile)

	# 点选认「按下与抬起都留在原地」，不认松开：划列表时格子跟着内容一起走，手指自始至终压在
	# 同一格内 ⇒ 按旧写法（BaseButton.pressed）每划一下都顺手多选一件。
	# 点击已持有的武器弹出悬浮详情卡：展示全部属性、流派与说明，并提供快捷操作（合成/换装/出售）。
	GameStyle.tap(slot, func():
		if is_sel:
			shop.selected = {}
			DetailTip.close_all(shop)
			shop._refresh_inventory()
		else:
			DetailTip.close_all(shop)
			shop.selected = {"pool": pool, "index": index}
			ShopWeaponTip.open(shop, item, pool, index, slot)
			shop._refresh_inventory()
	)
	# 拖拽换装：这一格也是「按住拎起 → 拖到目标格放下」的源与落点（手势口径见 ShopDragDrop 头注）
	shop.drag_register(slot, {"pool": pool, "index": index})
	return slot

## 可合成「合」字角标：左上角亮黄字 + 墨色描边（与右下 ★n 同一副文字语言、同一取色，
## 不拦输入；字号跟着格子长，口径同 star_label）。判据可按 name 找它。
static func _add_merge_badge(slot: Control, tile: float) -> Label:
	var lbl := Label.new()
	lbl.name = "MergeBadge"
	lbl.text = "合"
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_override("font", GameStyle.body_font())
	lbl.add_theme_font_size_override("font_size", int(round(clampf(tile * 0.24, 12.0, 16.0))))
	lbl.add_theme_color_override("font_color", GameStyle.JADE)
	lbl.add_theme_color_override("font_outline_color", GameStyle.INK)
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slot.add_child(lbl)
	return lbl

## 上阵容量签：「装备 n/上限n件」（限件数角色才出现）
static func create_equipped_cap_chip(used: int, max_slots: int) -> Control:
	var chip := PanelContainer.new()
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, GameStyle.JADE_DK, 1, 0.0))
	var lbl := Label.new()
	lbl.text = "装备 %d/%d（上限%d件）" % [used, max_slots, max_slots]
	chip.add_child(lbl)
	GameStyle.label(lbl, 11, GameStyle.JADE_EDGE)
	return chip

## 上阵空格：上阵区固定摆满上限格数（2026-10-11 用户：没佩戴的也要显示空格子），
## 描边带一点上阵区的金，与背包凹槽区分；只作拖拽落点（背包件拖到空格＝装备），
## 不吃输入（同背包空位：几何命中落点，gui_input 收不到也就不会被误拎起）
static func create_empty_equipped_slot(shop: WaveShop, index: int, tile: float) -> Control:
	var slot = PanelContainer.new()
	slot.custom_minimum_size = Vector2(tile, tile)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := GameStyle.slot()
	style.bg_color = GameStyle.with_alpha(GameStyle.INK, 0.55)
	style.border_color = GameStyle.with_alpha(GameStyle.GOLD, 0.45)
	slot.add_theme_stylebox_override("panel", style)
	if shop != null:
		shop.drag_register(slot, {"pool": "equipped", "index": index, "kind": "empty"})
	return slot

## 背包分隔签：「背包 n/9」；兼作拖拽落点 —— 上阵件拖到这一签上＝卸入背包
static func create_stash_divider(shop: WaveShop) -> Control:
	var chip = PanelContainer.new()
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 1, 0.0))
	var lbl = Label.new()
	lbl.text = "背包 %d/%d" % [GameManager.stash.size(), WeaponData.MAX_STASH_SLOTS]
	chip.add_child(lbl)
	# 暗井（INK 底）上的次要小字：GREY 翻转后偏暗，换暗底次级亮字
	GameStyle.label(lbl, 11, GameStyle.PAPER_DIM)
	if shop != null:
		shop.drag_register(chip, {"pool": "stash", "index": -1, "kind": "end"})
	return chip

## 道具分隔签：「道具 n」
static func create_items_divider() -> Control:
	var chip = PanelContainer.new()
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 1, 0.0))
	var lbl = Label.new()
	lbl.text = "道具 %d" % GameManager.items.size()
	chip.add_child(lbl)
	GameStyle.label(lbl, 11, GameStyle.PAPER_DIM)
	return chip

## 已持有道具的小徽记：按档位描边，支持点按弹出 DetailTip 详解卡
static func create_item_chip(shop: WaveShop, item_id: String, tile: float) -> Control:
	var def := ItemData.get_def(item_id)
	var chip = PanelContainer.new()
	chip.custom_minimum_size = Vector2(tile, tile)
	# 与图鉴卡/属性行同一约定：登记一下这颗徽位弹的是谁，判据不必再抄一份对照表
	chip.set_meta("tip_title", String(def.get("name", item_id)))
	# 与槽位同一口径：PASS，让「按下」那一拍冒泡到 OwnedScroll，压在道具徽位上也划得动整排
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	var tier_num: int = int(def.get("tier", 1))
	var tier_col: Color = ItemData.tier_color(tier_num)
	chip.add_theme_stylebox_override("panel",
		GameStyle.outlined_panel(GameStyle.NAVY2, tier_col, 2, 0.0))
	var icon_path: String = def.get("icon", "")
	var icon_tex := GameStyle.icon_texture_rect(icon_path)
	icon_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_tex.offset_left = 5
	icon_tex.offset_top = 5
	icon_tex.offset_right = -5
	icon_tex.offset_bottom = -5
	chip.add_child(icon_tex)

	# 划列表不算点按（同 create_inv_slot：整排在 OwnedScroll 里）
	GameStyle.tap(chip, func(): open_item_tip(shop, item_id, chip))
	return chip

## 道具徽记的详情卡：品阶/原价/出售返还 + 加成行（与货架卡同源） + 描述逐行 + 【出售】那颗键。
## 2026-10-12 用户：「商店里的这些道具啊，如果有买到不想要的，也可以卖掉」—— 武器与灵兽一直
## 卖得掉，道具这一类原先点进去只有读数没有操作：买错了整局背着（被动道具不占槽、没法卸），
## 这一屏是唯一能反悔的地方。出售走 GameManager.sell_item，加过的属性同一条链路退回。
static func open_item_tip(shop: WaveShop, item_id: String, anchor: Control) -> void:
	var def := ItemData.get_def(item_id)
	if def.is_empty():
		return
	var tier_num: int = int(def.get("tier", 1))
	var tier_col: Color = ItemData.tier_color(tier_num)
	var refund := ItemData.sell_price(item_id)
	var rows: Array = [
		["品阶", ItemData.tier_label(tier_num), tier_col],
		["原价", "%d 金币" % int(def.get("price", 0)), GameStyle.PAPER_DIM],
		["出售返还", "%d 金币" % refund, GameStyle.JADE],
	]
	# 加成行（2026-10-11 土豆兄弟式改版）：BonusRows 从 apply 生成，与货架卡同一把尺子
	rows.append_array(BonusRows.apply_rows(def.get("apply", {})))
	var desc_lines: Array = String(def.get("desc", "")).split("\n")
	var notes: Array[String] = []
	for line in desc_lines:
		var s := String(line).strip_edges()
		if not s.is_empty():
			notes.append(s)
	notes.append("出售按原价一半回收金币，加过的属性当场退回（与武器、灵兽同一条口径）。")
	var unique := bool(def.get("unique", false))
	var foot := "每回合商店会刷新更多道具。"
	if unique:
		foot = "本局限购一件：出售后这一件不再上架。"
	# 万兽笼这类「退了当场灵兽栏超编」的：键摆着但按不动，理由印在键上
	# （与武器详情卡「装备已满」「背包已满」那颗灰键同一条口径 —— 不许按下去什么也没发生）
	var slots_given := int((def.get("apply", {}) as Dictionary).get("pet_slots", 0))
	var over_pets := slots_given > 0 and GameManager.pets.size() > GameManager.max_pet_slots() - slots_given
	if over_pets:
		foot = "灵兽栏已超编：先出售灵兽再退这一件。"
	var on_sell := func():
		if GameManager.sell_item(item_id):
			shop.refresh(false)
	var actions: Array = [[{
		"text": "先出售灵兽" if over_pets else "出售 (+%d 金币)" % refund,
		"disabled": over_pets,
		"color": GameStyle.BAD,
		"edge_color": GameStyle.BAD_DK,
		"text_color": GameStyle.PAPER,
		"callback": on_sell,
	}]]
	DetailTip.show_over(shop, anchor, {
		"title": String(def.get("name", item_id)),
		"chip": "被动道具",
		"chip_color": tier_col,
		"rows": rows,
		"body": "被动道具：自动生效，不占武器槽，整局持续有效。",
		"notes": notes,
		"foot": foot,
		"actions": actions,
	})

## 背包空位：凹槽提示容量；兼作拖拽落点（拖到空位＝卸到队尾 / 背包件挪到队尾）
static func create_empty_stash_slot(shop: WaveShop, tile: float) -> Control:
	var slot = PanelContainer.new()
	slot.custom_minimum_size = Vector2(maxf(20.0, tile * 0.6), tile)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := GameStyle.slot()
	style.bg_color = GameStyle.with_alpha(GameStyle.INK, 0.55)
	slot.add_theme_stylebox_override("panel", style)
	if shop != null:
		shop.drag_register(slot, {"pool": "stash", "index": -1, "kind": "end"})
	return slot

## 灵兽分界条
static func create_pets_divider() -> Control:
	var chip = PanelContainer.new()
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 1, 0.0))
	var lbl = Label.new()
	lbl.text = "灵兽 %d/%d" % [GameManager.pets.size(), GameManager.max_pet_slots()]
	chip.add_child(lbl)
	GameStyle.label(lbl, 11, GameStyle.PAPER_DIM)
	return chip

## 已持有灵兽的小徽记：绘制光灵圆球，支持点按弹出 DetailTip 详解卡与出售操作
static func create_pet_chip(shop: WaveShop, pet_id: String, tile: float) -> Control:
	var def := PetData.get_def(pet_id)
	var chip = PanelContainer.new()
	chip.custom_minimum_size = Vector2(tile, tile)
	chip.set_meta("tip_title", String(def.get("name", pet_id)))
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	var color: Color = def.get("color", GameStyle.GOLD)
	chip.add_theme_stylebox_override("panel",
		GameStyle.outlined_panel(GameStyle.NAVY2, color, 2, 0.0))

	var preview := Control.new()
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.draw.connect(func():
		var sz := preview.size
		var center := sz * 0.5
		var r: float = sz.x * 0.28
		var halo: Color = def.get("halo_color", Color(1.0, 1.0, 1.0, 0.3))
		preview.draw_circle(center, r * 1.5, halo)
		preview.draw_circle(center, r, color)
		preview.draw_circle(center + Vector2(-r * 0.25, -r * 0.25), r * 0.35, Color(1.0, 1.0, 1.0, 0.85))
	)
	chip.add_child(preview)

	GameStyle.tap(chip, func(): open_pet_tip(shop, pet_id, chip))
	return chip

## 灵兽详情卡：包含定位/技能描述/出售返还按钮
static func open_pet_tip(shop: WaveShop, pet_id: String, anchor: Control) -> void:
	var def := PetData.get_def(pet_id)
	if def.is_empty():
		return
	var color: Color = def.get("color", GameStyle.GOLD)
	var refund := PetData.sell_price(pet_id)
	var rows: Array = [
		["定位", "灵兽 · %s" % PetData.role_label(String(def.get("role", ""))), color],
		["原价", "%d 金币" % int(def.get("base_price", 0)), GameStyle.PAPER_DIM],
		["出售返还", "%d 金币" % refund, GameStyle.JADE],
	]
	var on_sell := func():
		if GameManager.sell_pet(pet_id):
			shop.refresh(false)
	var actions: Array = [
		{
			"text": "出售灵兽 (+%d 金币)" % refund,
			"color": GameStyle.BAD,
			"edge_color": GameStyle.BAD_DK,
			"text_color": GameStyle.PAPER,
			"callback": on_sell,
		}
	]
	DetailTip.show_over(shop, anchor, {
		"title": String(def.get("name", pet_id)),
		"chip": "灵兽",
		"chip_color": color,
		"rows": rows,
		"body": String(def.get("desc", "")),
		"notes": ["灵兽：跟随主角战斗，无敌免死，跨回合存活。", "出售后释放栏位，并可再次在商店刷出。"],
		"foot": "当前灵兽栏位：%d/%d" % [GameManager.pets.size(), GameManager.max_pet_slots()],
		"actions": actions,
	})
