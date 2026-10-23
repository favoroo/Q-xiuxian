class_name WeaponCodexBuilder
extends RefCounted

## 图鉴·武器页 builder：流派筛选条（固定不滚）+ 武器网格（滚动区内）。
## 由 ManualDialog 委托构建（与 scripts/ui/stats/ 的 builder 同惯例）。
## 筛选状态存 dialog.weapon_class_filter / weapon_element_filter（各 "" = 该行全部），
## 两行独立点选、同时选中时取交集（例：剑系 ∩ 火系 = 带火属性的剑）；
## 点 chip 走 dialog._on_filter_chip_tapped(group, tag) 触发重建，chips 选中态由 restyle_chips() 统一重涂。
##
## 筛选口径与商店羁绊签同源：tag 命中 WeaponData.tags_of(wid) 即入选，
## 「机关·剑阵盘」这类双器类武器会同时出现在机关与剑系两组（与羁绊结算一致）。

## 卡面两件事都不点就能看见：三签（攻击方式·器类·五行）+ 关键数值行，
## 完整属性/射程/异常仍走点按详情卡
const STAT_LINE_FMT := "伤%d·%s秒·%d价"


## 组装整页：两行筛选 chips + 滚动网格区（写回 dialog._weapons_box）。返回页根（进 dialog._pages）。
static func build_page(dialog: ManualDialog, parent: Control) -> Control:
	var page := VBoxContainer.new()
	page.name = "WeaponsPage"
	page.add_theme_constant_override("separation", 6)
	parent.add_child(page)

	# 筛选条钉在滚动区上方：选完流派内容区重滚，筛选条不跟着内容滚走。
	# 两行各带「全部」：类型与元素可以同时选，清一条不影响另一条。
	page.add_child(_build_filter_row(dialog, "class", "类型", WeaponData.CLASSES))
	page.add_child(_build_filter_row(dialog, "element", "元素", WeaponData.ELEMENTS))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	dialog._weapons_box = box
	# 这里只搭壳不填卡：内容交给 dialog._ensure_page(1)（第一次切到武器页才建），
	# 否则图鉴一加载就把 38 张卡铺出来、打开时又重铺一遍。
	return page


## 按当前筛选填网格区：「全部」按五行分组（传统排布）；只锁一条线 = 该 tag 一组 + 羁绊说明；
## 两条线同时锁 = 交集一把平铺，标题并列两个流派名。
static func rebuild(dialog: ManualDialog) -> void:
	var box: VBoxContainer = dialog._weapons_box
	if box == null:
		return
	var cls_tag := dialog.weapon_class_filter
	var elem_tag := dialog.weapon_element_filter
	if cls_tag == "" and elem_tag == "":
		box.add_child(dialog._make_text_card("武器规则",
			"武器只能在回合间商店购买：上阵 %d 槽，背包 %d 格。\n集齐 3 把同名同星可合成升星：每星伤害 ×%s、攻击间隔 ×%s，最高 ★%d。\n点任意武器卡看射程、冷却与属性受益。" % [
				WeaponData.MAX_SLOTS, WeaponData.MAX_STASH_SLOTS,
				String.num(WeaponData.STAR_DAMAGE_MULT, 1), String.num(WeaponData.STAR_COOLDOWN_MULT, 2),
				WeaponData.MAX_STAR]))
		for elem in WeaponData.ELEMENTS:
			box.add_child(_group_header(
				"── %s行武器 ──" % String(StatInfoData.ELEMENT_NAMES.get(elem, elem)),
				GameStyle.ELEMENT_COLORS.get(elem, GameStyle.PAPER)))
			box.add_child(_weapon_grid(dialog, func(wid: String) -> bool:
				return String(elem) in WeaponData.tags_of(wid)))
		return

	var keep := func(wid: String) -> bool:
		var tags := WeaponData.tags_of(wid)
		if cls_tag != "" and not (cls_tag in tags):
			return false
		if elem_tag != "" and not (elem_tag in tags):
			return false
		return true
	var count := 0
	for wid in WeaponData.DEFS.keys():
		if WeaponData.DEFS[wid].has("tags") and bool(keep.call(String(wid))):
			count += 1
	var head_col: Color = GameStyle.GOLD
	if elem_tag != "":
		head_col = GameStyle.ELEMENT_COLORS.get(elem_tag, GameStyle.GOLD)
	box.add_child(_group_header("── %s · %d 把 ──" % [_filter_title(cls_tag, elem_tag), count], head_col))
	# 羁绊阶梯与进阶攻略页同源（SYNERGIES.thresholds + SynergyUI.synergy_desc），图鉴口径不随局内门槛调整变化。
	# 两条线同时选中时按上阵武器各自算羁绊（筛选只影响列出的卡，不影响羁绊口径），分行标注免得看串。
	var both := cls_tag != "" and elem_tag != ""
	for tag in [cls_tag, elem_tag]:
		if String(tag) != "":
			box.add_child(_synergy_desc(String(tag), both))
	if count == 0:
		box.add_child(dialog._make_text_card("没有匹配的武器",
			"「%s」里没有同时满足的武器。点上方「全部」放宽其中一条筛选。" % _filter_title(cls_tag, elem_tag)))
		return
	box.add_child(_weapon_grid(dialog, keep))


## 标题里的流派名：单条 = 「火系」，两条 = 「剑系 · 火系」
static func _filter_title(cls_tag: String, elem_tag: String) -> String:
	var parts: Array[String] = []
	for tag in [cls_tag, elem_tag]:
		var t := String(tag)
		if t != "":
			parts.append(String(WeaponData.SYNERGIES.get(t, {}).get("name", t)))
	return " · ".join(parts)


## 羁绊说明一行；with_name 时行首报出流派名，两条线并列时不会看串
static func _synergy_desc(tag: String, with_name: bool) -> Label:
	var syn: Dictionary = WeaponData.SYNERGIES.get(tag, {})
	var th: Array = syn.get("thresholds", [2, 4, 6])
	var prefix := ("%s羁绊：" % String(syn.get("name", tag))) if with_name else ""
	var desc_lbl := Label.new()
	desc_lbl.text = GameStyle.wrap_cjk(
		"%s上阵集齐 %d / %d / %d 件激活羁绊：%s" % [
			prefix, int(th[0]), int(th[1]), int(th[2]), SynergyUI.synergy_desc(tag)],
		GameStyle.body_font(), 12, ManualDialog.TEXT_W)
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameStyle.label(desc_lbl, 12, GameStyle.PAPER_DIM)
	return desc_lbl


## 重涂全部筛选 chips：选中主蓝底墨字、未选灰蓝底暗字，与商店羁绊签/页签选中态同一套语言
## （GOLD 常量现值就是主蓝 #4fc3f7，历史名沿用；点缀黄是 JADE）
static func restyle_chips(dialog: ManualDialog) -> void:
	for key in dialog._filter_chips.keys():
		var chip_lbl: Label = dialog._filter_chips[key]
		if not is_instance_valid(chip_lbl):
			continue
		var group := String(chip_lbl.get_meta("filter_group", "class"))
		var cur := dialog.weapon_class_filter if group == "class" else dialog.weapon_element_filter
		if String(chip_lbl.get_meta("filter_tag", "")) == cur:
			chip_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.GOLD))
			GameStyle.label(chip_lbl, 12, GameStyle.INK_TEXT, 0, GameStyle.INK, true)
		else:
			chip_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.NAVY2))
			GameStyle.label(chip_lbl, 12, GameStyle.PAPER_DIM)


static func _build_filter_row(dialog: ManualDialog, group: String, group_label: String, tags: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var g_lbl := Label.new()
	g_lbl.text = group_label
	GameStyle.label(g_lbl, 12, GameStyle.GREY)
	row.add_child(g_lbl)
	row.add_child(_make_filter_chip(dialog, group, "", "全部"))
	for tag in tags:
		row.add_child(_make_filter_chip(dialog, group, String(tag),
			String(WeaponData.SYNERGIES.get(tag, {}).get("name", tag))))
	return row


static func _make_filter_chip(dialog: ManualDialog, group: String, tag: String, text: String) -> Label:
	var chip_lbl := Label.new()
	chip_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	chip_lbl.text = " %s " % text
	chip_lbl.set_meta("filter_tag", tag)
	chip_lbl.set_meta("filter_group", group)
	# 锚点不回送也无需高亮联动：chips 不弹详情卡，点了只重建网格。
	# 两行各有一枚「全部」（tag 都是 ""），字典键要按行分开存，否则后建的会覆盖前一枚。
	GameStyle.tap(chip_lbl, func() -> void: dialog._on_filter_chip_tapped(group, tag))
	dialog._filter_chips[tag if tag != "" else "all_" + group] = chip_lbl
	restyle_chips(dialog)
	return chip_lbl


static func _group_header(text: String, color: Color) -> Label:
	var header := Label.new()
	header.text = text
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameStyle.label(header, 13, color, 0, GameStyle.INK, true)
	return header


static func _weapon_grid(dialog: ManualDialog, keep: Callable) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for wid in WeaponData.DEFS.keys():
		var def: Dictionary = WeaponData.DEFS[wid]
		if not def.has("tags"):
			continue
		if not bool(keep.call(String(wid))):
			continue
		grid.add_child(_make_weapon_card(dialog, String(wid), def))
	return grid


static func _make_weapon_card(dialog: ManualDialog, wid: String, def: Dictionary) -> PanelContainer:
	var stat_line := STAT_LINE_FMT % [
		int(def.get("damage", 0)),
		String.num(float(def.get("cooldown", 1.0)), 2),
		int(def.get("price", 0)),
	]
	var card := dialog._make_entry_card(
		String(def.get("icon", "")), String(def.get("name", wid)),
		"", GameStyle.PAPER_DIM,
		func(anchor: Control): dialog._open_weapon_tip(wid, anchor),
		stat_line, card_chips(wid, def))
	card.set_meta("wid", wid)		# 判据按 id 现算期望签文，不从卡面文字反推
	# 元素件 = 图标框那一圈暖橙红描边（图鉴与商店/属性面板同一口径）。
	# 原先贴右上角的「元素」色块已撤：48 见方的图标框上它要遮掉一角，而这一屏是要人扫着比的。
	var icon_tex := card.get_meta("icon_tex") as TextureRect
	if icon_tex != null and GameStyle.is_elemental(wid):
		var icon_box := icon_tex.get_parent() as Control
		if icon_box != null:
			icon_box.add_theme_stylebox_override("panel",
					GameStyle.outlined_panel(GameStyle.INK, GameStyle.ELEMENT, 1, 0.0))
	return card


## 卡面三签：攻击方式 + 器类（双器类武器如「机关·剑阵盘」给两枚）+ 五行。
## 词表就是筛选 chip 那批名字（WeaponData.SYNERGIES[].name），取色与商店货架卡行②同源
## （behavior 走 StatsTipFactory.behavior_color，五行走 GameStyle.ELEMENT_COLORS）——
## 同一件事在商店/图鉴/详情卡必须是同一副样子（2026-10-11 用户：图鉴只有点开才看得到
## 属性，横向比不了，「召唤/火系/水系」这种要一眼扫得出来）。
## 器类/五行签先排，攻击方式签排队首，但**同词不插第二遍**：天灯的器类「范围」就是它的
## 攻击方式、喷火兽的「机关」同理（两套词表共用这些人话），一张卡上并排两张同词签
## 看着像画坏了；留器类那一枚，因为筛选与羁绊算的是它。
static func card_chips(wid: String, def: Dictionary) -> Array:
	var out: Array = []
	for t in WeaponData.tags_of(wid):
		var tag := String(t)
		var syn: Dictionary = WeaponData.SYNERGIES.get(tag, {})
		if syn.is_empty():
			continue
		var nm := String(syn.get("name", tag))
		if tag in WeaponData.ELEMENTS:
			var elem_col: Color = GameStyle.ELEMENT_COLORS.get(tag, GameStyle.GOLD)
			out.append([nm, elem_col, GameStyle.on_face_text(elem_col)])
		else:
			out.append([nm, GameStyle.NAVY2, GameStyle.INK_TEXT])
	var beh := WeaponData.behavior_label(def)
	if not _chips_have(out, beh):
		var beh_col: Color = StatsTipFactory.behavior_color(def)
		out.insert(0, [beh, beh_col, GameStyle.on_face_text(beh_col)])
	return out


static func _chips_have(chips: Array, text: String) -> bool:
	for cd in chips:
		if String(cd[0]) == text:
			return true
	return false
