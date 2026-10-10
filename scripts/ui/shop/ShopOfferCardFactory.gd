class_name ShopOfferCardFactory
extends RefCounted

## 灵石阁货架卡工厂：单张货架卡的构建与数据装配（卡体 chrome / 头行 / 色签行 / 价格键）。
## 从 WaveShop 拆出：摆位口径与常量仍在 WaveShop（唯一真话，判据引用它们），
## 买入/锁定等操作回调经 shop 门面回流（refresh(false) 重排货架）。

## 构建一张货架卡：行①图标与名号同行、行②色签+锁定、行③加成行块+说明、行④价格/购买
static func create_card(shop: WaveShop, offer: Dictionary, index: int, total_count: int = 4) -> Control:
	var card_w := WaveShop.offer_card_w(shop._screen, total_count)
	var data := resolve_offer_data(offer)
	var card := _create_card_chrome(card_w, data.edge_color)
	var inner_w: float = WaveShop.card_inner_w(card_w)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", int(WaveShop.CARD_SEP))
	vbox.alignment = BoxContainer.ALIGNMENT_BEGIN

	var sold: bool = offer.get("sold", false)
	var price: int = int(offer.get("price", 0))

	# 行①：图标与名号同行
	vbox.add_child(_create_card_head(offer, card_w, data.kind, data.title, data.icon_path))
	# 行②：色签流 + 锁定开关同行
	vbox.add_child(_create_card_tag_row(shop, offer, index, sold, data.tag, data.chip_color, data.chip_text_color, data.tag_parts, data.part_hot, data.merge_ready))
	# 行③：加成行块（土豆兄弟式：伤害置顶 / 道具逐条加成，正绿负红）+ 机制·特性说明
	var stat_rows: Array = data.stat_rows
	if not stat_rows.is_empty():
		vbox.add_child(BonusRows.build_rows_block(stat_rows, 12, inner_w))
	if not String(data.desc).is_empty():
		var desc_lbl := Label.new()
		desc_lbl.text = GameStyle.wrap_cjk(data.desc, GameStyle.body_font(), 12, inner_w)
		desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		desc_lbl.custom_minimum_size = Vector2(inner_w, 0)
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		GameStyle.label(desc_lbl, 12, GameStyle.PAPER_DIM)
		vbox.add_child(desc_lbl)
	# 弹性占位：纯加成卡（如药水、desc 已清空的道具）也要把价格键钉在卡底，
	# 不然货架把卡拉成等高后价格悬在半空、卡底留一大段黑
	var stretch := Control.new()
	stretch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(stretch)
	# 行④：价格/购买按钮
	vbox.add_child(_create_card_price_btn(shop, offer, index, sold, price, data.is_item, data.def, data.kind))

	card.add_child(vbox)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	GameStyle.swipeable(card)
	return card

## 装配这张卡的全部数据（武器/道具/药水三种货）：名号、图标、色签、加成行、说明、边色与「可合成」角标
## stat_rows 是卡面加成行（[名字, 幅度, 颜色]），数字由 BonusRows 从数据表直接生成，不在 desc 里手抄
static func resolve_offer_data(offer: Dictionary) -> Dictionary:
	var kind: String = offer.get("kind", "weapon")
	var is_potion: bool = kind == "potion"
	var is_item: bool = kind == "item"
	var def := {}
	var title: String
	var icon_path: String
	var tag: String
	var tag_parts: Array = []
	var part_hot: Array = []
	var desc: String
	var stat_rows: Array = []
	var merge_ready := false
	var chip_color: Color = GameStyle.GOLD
	var chip_text_color: Color = GameStyle.PAPER
	var edge_color: Color = GameStyle.GOLD_DK

	if is_potion:
		title = "回复药"
		icon_path = "res://assets/art/icon_hp.png"
		tag = "药水"
		desc = ""
		# 卡上印的是「现在买下这一口，真能回多少」：与 ShopSystem 喂给 heal() 同一条公式，
		# 再按当前缺血截断 ⇒ 数字永远不会承诺一个兑现不了的量。
		# 只写「50% 生命」判断不了要不要买（2026-10-11 用户：「商店界面也要显示血量，
		# 不然也不知道回复道具要不要买」）。满血时就是 +0，红字，别花这个钱。
		var stats := GameManager.get_player_stat_dict()
		var eff := GameBalance.potion_effective_heal(
				float(stats.get("max_hp", 0.0)), float(stats.get("current_hp", 0.0)))
		stat_rows = [["回复气血", "+%d" % int(round(eff)),
				GameStyle.GOOD if eff > 0.5 else GameStyle.BAD]]
		chip_color = GameStyle.GOOD
		chip_text_color = GameStyle.INK_TEXT
		edge_color = GameStyle.JADE_DK
	elif is_item:
		def = ItemData.get_def(offer.get("id", ""))
		var tier := int(def.get("tier", 1))
		title = def.get("name", "?")
		icon_path = def.get("icon", "")
		tag = "%s·道具" % ItemData.tier_label(tier)
		desc = def.get("desc", "")
		stat_rows = BonusRows.apply_rows(def.get("apply", {}))
		chip_color = ItemData.tier_color(tier)
		chip_text_color = GameStyle.INK_TEXT
		edge_color = ItemData.tier_color(tier).darkened(0.35)
	else:
		var w_id: String = String(offer.get("id", ""))
		def = WeaponData.get_def(w_id)
		title = def.get("name", "?")
		icon_path = def.get("icon", "")
		tag = def.get("tag", "")
		var wtags: Array = def.get("tags", [])
		var will_activate := false
		for t in wtags:
			var syn: Dictionary = WeaponData.SYNERGIES.get(t, {})
			if syn.is_empty():
				continue
			var n := GameManager.get_tag_count(t)
			var next := "MAX"
			var hot := false
			var th_arr: Array = syn.get("thresholds", [])
			for th in th_arr:
				if n < int(th):
					next = str(th)
					hot = (n + 1 == int(th))
					break
			tag_parts.append("%s %d/%s" % [syn.get("name", t), n, next])
			part_hot.append(hot)
			will_activate = will_activate or hot
		if not tag_parts.is_empty():
			tag = " · ".join(tag_parts)
		if will_activate:
			chip_color = GameStyle.JADE
			chip_text_color = GameStyle.INK_TEXT
			edge_color = GameStyle.JADE
		# 买下即凑齐三合一：手里同名同星正好 2 把（货架只卖 1 星，买这把就满 3）——
		# 绿边 + 「可合成」角标，与背包槽位 mergeable 绿边同口径。==2 才提示：
		# 手里已有 3 把说明早已凑齐（该先去合成），买了变 4 把不叫「凑齐」。
		merge_ready = not bool(offer.get("sold", false)) \
				and GameManager.count_copies(w_id, 1) == 2
		if merge_ready:
			edge_color = GameStyle.JADE
		desc = def.get("desc", "")
		# 伤害置顶（土豆兄弟口径）：货架卡最显眼处就是这把武器的 1 星伤害
		stat_rows = [["伤害", BonusRows.fmt_num(WeaponData.damage_for(w_id, 1)), GameStyle.JADE]]
		# 玩家属性已经能喂给这把武器额外伤害时，亮一行加成额（买前就能看到这把有多吃属性）
		var bonus_dmg := GameManager.get_weapon_stat_bonus(w_id, 1)
		if bonus_dmg > 0.05:
			stat_rows.append(["属性加成", "+%d" % int(round(bonus_dmg)), GameStyle.GOOD])

	return {
		"kind": kind, "is_potion": is_potion, "is_item": is_item, "def": def,
		"title": title, "icon_path": icon_path, "tag": tag, "tag_parts": tag_parts,
		"part_hot": part_hot, "desc": desc, "stat_rows": stat_rows, "merge_ready": merge_ready,
		"chip_color": chip_color, "chip_text_color": chip_text_color,
		"edge_color": edge_color,
	}

## 卡体：斜切面板 + 四边内容边距（OFFER_PAD_X / CARD_PAD_Y 口径在 WaveShop，判据按它量）
static func _create_card_chrome(card_w: float, edge_color: Color) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(card_w, 0)
	var style := GameStyle.card(edge_color, 3.0, Vector2(5, 5))
	style.content_margin_left = WaveShop.OFFER_PAD_X
	style.content_margin_top = WaveShop.CARD_PAD_Y
	style.content_margin_right = WaveShop.OFFER_PAD_X
	style.content_margin_bottom = WaveShop.CARD_PAD_Y
	card.add_theme_stylebox_override("panel", style)
	return card

## 行①：图标框（含五行角标）与名号同行，名号按 card_name_w 切硬换行
static func _create_card_head(offer: Dictionary, card_w: float, kind: String, title: String, icon_path: String) -> HBoxContainer:
	var head := HBoxContainer.new()
	head.name = "CardHead"
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 6)

	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(WaveShop.CARD_ICON, WaveShop.CARD_ICON)
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 2, 0.0))

	var icon_tex := TextureRect.new()
	if ResourceLoader.exists(icon_path):
		icon_tex.texture = load(icon_path)
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.custom_minimum_size = Vector2(WaveShop.CARD_ICON - 10.0, WaveShop.CARD_ICON - 10.0)
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_child(icon_tex)

	if kind == "weapon":
		GameStyle.maybe_add_element_badge(icon_box, String(offer.get("id", "")), 8)
	head.add_child(icon_box)

	var name_w: float = WaveShop.card_name_w(card_w)
	var title_lbl := Label.new()
	title_lbl.text = GameStyle.wrap_cjk(title, GameStyle.display_font(), 17, name_w)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_lbl.custom_minimum_size = Vector2(name_w, 0)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(title_lbl)
	GameStyle.label(title_lbl, 17, GameStyle.PAPER, 0, GameStyle.INK, true)
	return head

## 行②：流派色签流（临门一档亮绿）+「可合成」角标 + 未售出时的锁定开关
static func _create_card_tag_row(shop: WaveShop, offer: Dictionary, index: int, sold: bool, tag: String, chip_color: Color, chip_text_color: Color, tag_parts: Array, part_hot: Array, merge_ready: bool = false) -> HBoxContainer:
	var tag_row := HBoxContainer.new()
	tag_row.name = "TagRow"
	tag_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_row.add_theme_constant_override("separation", 4)

	var tag_flow := HFlowContainer.new()
	tag_flow.name = "TagFlow"
	tag_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag_flow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag_flow.add_theme_constant_override("h_separation", 4)
	tag_flow.add_theme_constant_override("v_separation", 2)
	tag_row.add_child(tag_flow)

	var chip_defs: Array = []
	if tag_parts.is_empty():
		chip_defs.append([tag, chip_color, chip_text_color])
	else:
		for i in range(tag_parts.size()):
			var hot_i: bool = bool(part_hot[i])
			chip_defs.append([tag_parts[i],
				GameStyle.JADE if hot_i else chip_color,
				GameStyle.INK_TEXT if hot_i else chip_text_color])
	# 「买下即凑齐三合一」角标：绿面墨字，与背包 mergeable 绿边同口径
	if merge_ready:
		chip_defs.append(["可合成", GameStyle.JADE, GameStyle.INK_TEXT])
	for cd in chip_defs:
		var chip_txt: String = " %s " % cd[0]
		var chip_lbl := Label.new()
		chip_lbl.text = chip_txt
		chip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip_lbl.custom_minimum_size = Vector2(GameStyle.chip_pin_w(chip_txt, GameStyle.body_font(), 11), 0)
		chip_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip_lbl.add_theme_stylebox_override("normal", GameStyle.chip(cd[1]))
		tag_flow.add_child(chip_lbl)
		GameStyle.label(chip_lbl, 11, cd[2])

	if not sold:
		var locked: bool = offer.get("locked", false)
		var lock_btn := Button.new()
		lock_btn.name = "LockButton"
		lock_btn.custom_minimum_size = Vector2(WaveShop.CARD_LOCK_W, WaveShop.CARD_LOCK_H)
		lock_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		lock_btn.focus_mode = Control.FOCUS_NONE
		lock_btn.text = "已锁" if locked else "锁定"
		GameStyle.button(lock_btn, GameStyle.JADE if locked else GameStyle.NAVY2,
			GameStyle.JADE_DK if locked else GameStyle.LINE, 11,
			GameStyle.INK_TEXT if locked else GameStyle.PAPER_DIM, 4.0)
		lock_btn.pressed.connect(func():
			GameManager.toggle_lock(index)
			shop.refresh(false)
		)
		tag_row.add_child(lock_btn)
	return tag_row

## 行④：价格/购买按钮（已售出、缺钱、道具已持有、装备背包全满四类禁用口径）
static func _create_card_price_btn(shop: WaveShop, offer: Dictionary, index: int, sold: bool, price: int, is_item: bool, def: Dictionary, kind: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, WaveShop.CARD_PRICE_H)
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	GameStyle.button(btn, GameStyle.JADE, GameStyle.JADE_EDGE, 14, GameStyle.INK_TEXT, 6.0)
	btn.text = "%d 金币" % price
	if sold:
		btn.text = "已 售 出"
		btn.disabled = true
	elif GameManager.spirit_stones < price:
		btn.disabled = true
		# 买不起要留着那颗灰键、并且把差额写在脸上：上一版只把键置灰，
		# 灰面与纯黑面板同色 ⇒ 真机上看起来像「这一格没有按钮」（2026-10-11 用户指令）。
		# 差额是「再打一波就买得起」的判断依据，比一个灰块有用。
		btn.text = "%d 金币 · 差 %d" % [price, price - GameManager.spirit_stones]
	elif is_item and bool(def.get("unique", false)) and GameManager.has_item(offer.get("id", "")):
		btn.disabled = true
		btn.text = "已 持 有"
	elif kind == "weapon" and GameManager.slots_used() >= GameManager.max_weapon_slots() \
			and GameManager.stash.size() >= WeaponData.MAX_STASH_SLOTS:
		btn.disabled = true
		btn.text = "装备背包已满"
	elif kind == "weapon" and GameManager.slots_used() >= GameManager.max_weapon_slots():
		btn.text = "%d 金币 · 入背包" % price
	btn.pressed.connect(func():
		if GameManager.buy_offer(index):
			shop.refresh(false)
	)
	return btn
