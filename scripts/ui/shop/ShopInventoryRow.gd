class_name ShopInventoryRow
extends RefCounted

## 灵石阁陈列行（上阵 + 背包 + 法宝）的单格构建：槽位 / 容量签 / 分隔签 / 法宝徽记 / 空槽。
## 从 WaveShop 拆出：整行的编排（_refresh_inventory）仍在 WaveShop，
## 点选回调经 shop 门面回流（选中态与悬浮详情卡都归 shop 管）。

## 单格法器槽：不用 Button —— BaseButton 在自己的 gui_input 里 accept_event()，「按下」
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

	var border: Color = GameStyle.LINE
	var bg: Color = GameStyle.NAVY2
	if pool == "equipped":
		border = GameStyle.GOLD
		bg = GameStyle.NAVY
	if mergeable:
		border = GameStyle.JADE
	if is_sel:
		border = GameStyle.PAPER
		bg = GameStyle.NAVY.lightened(0.08)
	var sb := GameStyle.outlined_panel(bg, border, 2, 0.0)
	# 图标与星角共用的内缩：PanelContainer 把每个子节点都铺满内容区，内缩只能给在 stylebox 上
	sb.content_margin_left = 3.0
	sb.content_margin_top = 3.0
	sb.content_margin_right = 3.0
	sb.content_margin_bottom = 3.0
	slot.add_theme_stylebox_override("panel", sb)

	var icon_path: String = item.get("icon", "")
	if icon_path.is_empty():
		icon_path = WeaponData.get_def(id).get("icon", "")

	var icon_tex := TextureRect.new()
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		icon_tex.texture = load(icon_path)
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(icon_tex)

	# 吃「元素伤害」属性加成的法器挂橙红角标（与属性面板/图鉴同一口径）
	GameStyle.maybe_add_element_badge(slot, id, 8)
	GameStyle.star_label(slot, star, 11)

	# 点选认「按下与抬起都留在原地」，不认松开：划列表时格子跟着内容一起走，手指自始至终压在
	# 同一格内 ⇒ 按旧写法（BaseButton.pressed）每划一下都顺手多选一件。
	# 点击已持有的法器弹出悬浮详情卡：展示全部属性、流派与说明，并提供快捷操作（合成/换装/出售）。
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
	return slot

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

## 背包分隔签：「背包 n/9」
static func create_stash_divider() -> Control:
	var chip = PanelContainer.new()
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 1, 0.0))
	var lbl = Label.new()
	lbl.text = "背包 %d/%d" % [GameManager.stash.size(), WeaponData.MAX_STASH_SLOTS]
	chip.add_child(lbl)
	# 暗井（INK 底）上的次要小字：GREY 翻转后偏暗，换暗底次级亮字
	GameStyle.label(lbl, 11, GameStyle.PAPER_DIM)
	return chip

## 法宝分隔签：「道具 n」
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

## 已持有法宝的小徽记：按档位描边，支持点按弹出 DetailTip 详解卡
static func create_item_chip(shop: WaveShop, item_id: String, tile: float) -> Control:
	var def := ItemData.get_def(item_id)
	var chip = PanelContainer.new()
	chip.custom_minimum_size = Vector2(tile, tile)
	# 与图鉴卡/属性行同一约定：登记一下这颗徽位弹的是谁，判据不必再抄一份对照表
	chip.set_meta("tip_title", String(def.get("name", item_id)))
	# 与槽位同一口径：PASS，让「按下」那一拍冒泡到 OwnedScroll，压在法宝徽位上也划得动整排
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	var tier_num: int = int(def.get("tier", 1))
	var tier_col: Color = ItemData.tier_color(tier_num)
	chip.add_theme_stylebox_override("panel",
		GameStyle.outlined_panel(GameStyle.NAVY2, tier_col, 2, 0.0))
	var icon_tex = TextureRect.new()
	var icon_path: String = def.get("icon", "")
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		icon_tex.texture = load(icon_path)
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_tex.offset_left = 5
	icon_tex.offset_top = 5
	icon_tex.offset_right = -5
	icon_tex.offset_bottom = -5
	chip.add_child(icon_tex)

	# 划列表不算点按（同 create_inv_slot：整排在 OwnedScroll 里）
	GameStyle.tap(chip, func(): open_item_tip(shop, item_id, chip))
	return chip

## 法宝徽记的详情卡：品阶/价格 + 加成行（与货架卡同源） + 描述逐行
static func open_item_tip(shop: WaveShop, item_id: String, anchor: Control) -> void:
	var def := ItemData.get_def(item_id)
	if def.is_empty():
		return
	var tier_num: int = int(def.get("tier", 1))
	var tier_col: Color = ItemData.tier_color(tier_num)
	var rows: Array = [
		["品阶", ItemData.tier_label(tier_num), tier_col],
		["买入价格", "%d 金币" % int(def.get("price", 0)), GameStyle.JADE],
	]
	# 加成行（2026-10-11 土豆兄弟式改版）：BonusRows 从 apply 生成，与货架卡同一把尺子
	rows.append_array(BonusRows.apply_rows(def.get("apply", {})))
	var desc_lines: Array = String(def.get("desc", "")).split("\n")
	var notes: Array[String] = []
	for line in desc_lines:
		var s := String(line).strip_edges()
		if not s.is_empty():
			notes.append(s)
	DetailTip.show_over(shop, anchor, {
		"title": String(def.get("name", item_id)),
		"chip": "被动道具",
		"chip_color": tier_col,
		"rows": rows,
		"body": "被动道具：自动生效，不占武器槽，整局持续有效。",
		"notes": notes,
		"foot": "每波商店会刷新更多道具。",
	})

## 背包空位：凹槽提示容量
static func create_empty_stash_slot(tile: float) -> Control:
	var slot = PanelContainer.new()
	slot.custom_minimum_size = Vector2(maxf(20.0, tile * 0.6), tile)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := GameStyle.slot()
	style.bg_color = GameStyle.with_alpha(GameStyle.INK, 0.55)
	slot.add_theme_stylebox_override("panel", style)
	return slot
