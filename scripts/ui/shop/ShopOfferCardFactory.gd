class_name ShopOfferCardFactory
extends RefCounted

## 商店货架卡工厂：单张货架卡的构建与数据装配（卡体 chrome / 头行 / 色签行 / 价格键）。
## 从 WaveShop 拆出：摆位口径与常量仍在 WaveShop（唯一真话，判据引用它们），
## 买入/锁定等操作回调经 shop 门面回流（refresh(false) 重排货架）。

## 构建一张货架卡：行①图标与名号同行、行②色签+锁定、行③加成行块+说明、行④价格/购买
## forecast 由宿主一次开屏只抄一份影子传入（与悟道 _populate_cards 同构）；
## 测试直接调本工厂时不传，item 分支内部现开一份兜底。
static func create_card(shop: WaveShop, offer: Dictionary, index: int, total_count: int = 4,
		forecast: StatForecast = null) -> Control:
	var card_w := WaveShop.offer_card_w(shop._screen, total_count)
	var inner_w: float = WaveShop.card_inner_w(card_w)
	# 卡内宽按这一屏的真卡宽传下去：预览行只在「这一档屏真装不下」时才退兜底，
	# 不许拿最窄档 124 当所有屏的尺子（20:9 宽卡上明明放得下，当前值却被砍掉）
	var data := resolve_offer_data(offer, forecast, inner_w)
	var card := _create_card_chrome(card_w, data.edge_color)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", int(WaveShop.CARD_SEP))
	vbox.alignment = BoxContainer.ALIGNMENT_BEGIN

	var sold: bool = offer.get("sold", false)
	var price: int = int(offer.get("price", 0))

	# 行①：图标与名号同行（附拥有数量/星级分布）
	vbox.add_child(_create_card_head(shop, offer, card_w, data.kind, data.title, data.icon_path, String(data.get("owned_text", "")), data.w_id))
	# 行②：色签流 + 锁定开关同行
	vbox.add_child(_create_card_tag_row(shop, offer, index, sold, data.tag, data.chip_color, data.chip_text_color, data.tag_parts, data.part_hot, data.merge_ready, data.behavior_chip, data.rec_reasons, data.tag_keys, data.w_id))
	# 行③：加成行块（土豆兄弟式：伤害置顶 / 道具逐条加成，正绿负红）+ 机制·特性说明
	var stat_rows: Array = data.stat_rows
	if not stat_rows.is_empty():
		vbox.add_child(BonusRows.build_rows_block(stat_rows, 12, inner_w))
	# 说明与加成行是两件事，各判各的空：灵兽卡没有加成行（stat_rows 恒空），
	# 原先嵌在上面那个 if 里 ⇒ 灵兽卡整张只剩名号和价格，机制说明一个字都不显示
	if not String(data.desc).is_empty():
		var desc_rt := RichTextLabel.new()
		desc_rt.bbcode_enabled = true
		desc_rt.fit_content = true
		desc_rt.scroll_active = false
		desc_rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		desc_rt.custom_minimum_size = Vector2(inner_w, 0)
		desc_rt.add_theme_font_override("normal_font", GameStyle.body_font())
		desc_rt.add_theme_font_override("bold_font", GameStyle.emph_font())
		desc_rt.add_theme_font_size_override("normal_font_size", 12)
		desc_rt.add_theme_font_size_override("bold_font_size", 12)
		desc_rt.add_theme_color_override("default_color", GameStyle.PAPER_DIM)
		desc_rt.text = GameStyle.wrap_bbcode(
			GameStyle.colorize_terms(data.desc), GameStyle.body_font(), 12, inner_w)
		vbox.add_child(desc_rt)
	# 弹性占位：纯加成卡（如药水、desc 已清空的道具）也要把价格键钉在卡底，
	# 不然货架把卡拉成等高后价格悬在半空、卡底留一大段黑
	var stretch := Control.new()
	stretch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(stretch)
	# 行④：价格/购买按钮
	vbox.add_child(_create_card_price_btn(shop, offer, index, sold, price, data.is_item, data.def, data.kind))

	card.add_child(vbox)
	if data.merge_ready:
		card.add_child(_create_merge_corner_badge(shop, data.w_id))
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	GameStyle.swipeable(card)
	return card

## 装配这张卡的全部数据（武器/道具/回复药三种货）：名号、图标、色签、加成行、说明、边色与「可合成」角标
## stat_rows 是卡面加成行（[名字, 幅度, 颜色]），数字由 BonusRows 从数据表直接生成，不在 desc 里手抄；
## 道具卡另有「当前 → 购买后」预览（item_stat_rows），forecast 为空时内部现开一份影子（测试路径）。
static func resolve_offer_data(offer: Dictionary, forecast: StatForecast = null,
		row_w: float = -1.0) -> Dictionary:
	var kind: String = offer.get("kind", "weapon")
	var is_potion: bool = kind == "potion"
	var is_item: bool = kind == "item"
	var is_pet: bool = kind == "pet"
	var def := {}
	var title: String
	var icon_path: String
	var tag: String
	var tag_parts: Array = []
	var tag_keys: Array = []	# 与 tag_parts 同序的流派 key：色签点按时按它取羁绊详情
	var part_hot: Array = []
	var desc: String
	var stat_rows: Array = []
	var merge_ready := false
	var chip_color: Color = GameStyle.GOLD
	var chip_text_color: Color = GameStyle.on_face_text(chip_color)
	var edge_color: Color = GameStyle.GOLD_DK
	var behavior_chip: Array = []
	var owned_text := ""
	# 「荐」推荐标（RecommendSystem 在 roll_shop 里打分写入 offer）：已售出的格子不再亮标
	var recommended: bool = bool(offer.get("recommended", false)) and not bool(offer.get("sold", false))
	var rec_reasons: Array = offer.get("recommend_reasons", [])

	if is_potion:
		title = "回复药"
		icon_path = "res://assets/art/icon_hp.png"
		tag = "回复药"
		desc = ""
		# 卡上印的是「现在买下这一口，真能回多少」：与 ShopSystem 喂给 heal() 同一条公式，
		# 再按当前缺血截断 ⇒ 数字永远不会承诺一个兑现不了的量。
		# 只写「50% 生命」判断不了要不要买（2026-10-11 用户：「商店界面也要显示生命，
		# 不然也不知道回复道具要不要买」）。满血时就是 +0，红字，别花这个钱。
		var stats := GameManager.get_player_stat_dict()
		var eff := GameBalance.potion_effective_heal(
				float(stats.get("max_hp", 0.0)), float(stats.get("current_hp", 0.0)))
		stat_rows = [["回复生命", "+%d" % int(round(eff)),
				GameStyle.GOOD if eff > 0.5 else GameStyle.BAD]]
		chip_color = GameStyle.GOOD
		chip_text_color = GameStyle.INK_TEXT
		edge_color = GameStyle.JADE_DK
	elif is_item:
		var item_id := String(offer.get("id", ""))
		def = ItemData.get_def(item_id)
		var tier := int(def.get("tier", 1))
		title = def.get("name", "?")
		icon_path = def.get("icon", "")
		tag = "%s·道具" % ItemData.tier_label(tier)
		desc = def.get("desc", "")
		# 买不动的那几档不画预览（2026-10-21）：已售出的格子、限购一件且已持有——
		# 售出卡再画「购买后」等于把这件的加成又叠一遍，是张假账；此时幅度行就是它的全部。
		var previewable := not bool(offer.get("sold", false)) \
				and not (bool(def.get("unique", false)) and GameManager.has_item(item_id))
		if previewable:
			var fc := forecast if forecast != null else StatForecast.open()
			stat_rows = item_stat_rows(def.get("apply", {}), fc, row_w)
		else:
			stat_rows = BonusRows.apply_rows(def.get("apply", {}))
		chip_color = ItemData.tier_color(tier)
		chip_text_color = GameStyle.INK_TEXT
		# T-5.1 道具卡边框接 FX_HDR 对应档（普通白不发辉、金色档 HDR 起辉）：
		edge_color = GameStyle.rarity_edge_color(tier)
		var owned_count: int = GameManager.items.count(item_id)
		if owned_count > 0:
			owned_text = "拥有 ×%d" % owned_count
	elif is_pet:
		var pet_id := String(offer.get("id", ""))
		def = PetData.get_def(pet_id)
		title = def.get("name", "灵兽")
		icon_path = ""
		tag = "灵兽·%s" % PetData.role_label(String(def.get("role", "")))
		desc = def.get("desc", "")
		stat_rows = []
		chip_color = def.get("color", GameStyle.GOLD)
		chip_text_color = GameStyle.INK_TEXT
		edge_color = chip_color.darkened(0.35)
		if GameManager.has_pet(pet_id):
			owned_text = "已拥有"
	else:
		var w_id: String = String(offer.get("id", ""))
		def = WeaponData.get_def(w_id)
		title = def.get("name", "?")
		icon_path = def.get("icon", "")
		tag = def.get("tag", "")
		owned_text = WeaponInventory.format_owned_summary(GameManager, w_id)
		var wtags: Array = def.get("tags", [])
		var will_activate := false
		for t in wtags:
			var syn: Dictionary = WeaponData.SYNERGIES.get(t, {})
			if syn.is_empty():
				continue
			# 卡面进度与「临门一档」共用 SynergyUI.badge 这一把尺子：它按角色下移后的门槛算，
			# 原先直接比原表 2/4/6，驯兽师（召唤 -1）5 件已满档却仍提示「5/6 再买一件」、绿边也错一档
			var prog: Dictionary = SynergyUI.badge(String(t), GameManager.get_tag_count(String(t)))
			tag_parts.append(String(prog["text"]))
			tag_keys.append(String(t))
			part_hot.append(bool(prog["hot"]))
			will_activate = will_activate or bool(prog["hot"])
		if not tag_parts.is_empty():
			tag = " · ".join(tag_parts)
		if will_activate:
			chip_color = GameStyle.JADE
			chip_text_color = GameStyle.INK_TEXT
			edge_color = GameStyle.JADE
		# 买下即凑齐三合一：手里同名同星差 1 把凑满 3 件（如正好 2 把，货架只卖 1 星，买这把就满 3）——
		# 统一由商品卡片右上角显示圆形主题色「合」标记指示，TagRow 不再挂文字签。
		merge_ready = not bool(offer.get("sold", false)) \
				and (GameManager.count_copies(w_id, 1) % 3) == 2
		desc = def.get("desc", "")
		# 攻击方式色签（近战朱砂 / 非近战主蓝）：def.tag 首段会被流派进度覆盖，
		# 货架上一直看不出近战远程（2026-10-11 用户），behavior 才是结构真话。
		var beh_col: Color = StatsTipFactory.behavior_color(def)
		behavior_chip = [WeaponData.behavior_label(def), beh_col, GameStyle.on_face_text(beh_col)]
		# 卡面四行统一一条规则：左边纸面值、右边你现在拿到的值，两数相同就不画箭头。
		# 伤害不再拆成「伤害 24 / 属性加成 +10」两行（2026-10-11 用户：那行读起来像武器送你属性，
		# 方向反了；玩家想看的只是"本身多痛、加成后多痛"）。
		# 卡面预算是硬的：BonusRows 行不换行、卡内宽最小 124px，且货架不许上下滑 —— 武器卡
		# 箭头只给伤害这一行用，范围/间隔也带上箭头就把面板顶出屏、卡高顶到要滚动（LayoutCheck 当场红）。
		# 道具卡 2026-10-21 起整列换成「当前→购买后」预览行（item_stat_rows），同样不增行数，
		# 同一把 124 预算由它自己的兜底退档守住，谁超宽当场退回幅度行而不破格。
		# 「每秒伤害」直接顶掉「攻击间隔」行：攻速信息本来就被它包含，还省一行给玩家验算。
		# 伤害那一行保留两字「伤害」不扩成「单发伤害」：卡内宽下限 124 而 BonusRows 不换行，
		# 引擎实测「单发伤害」+ 最宽读数（"999 → 9999.9"）= 135 已破格，同一档两字行名是 111。
		# 这条预算由单测「货架卡每一行都装得进 124 卡内宽」钉着，行名再长一档当场红；
		# 全称「单发伤害」写在两张详情卡上（那里定宽 306，装得下）。
		var slots_after := WeaponDamageReadout.slot_count_after_purchase()
		stat_rows = [["伤害", WeaponDamageReadout.arrow_text(
				WeaponData.damage_for(w_id, 1),
				WeaponDamageReadout.per_hit(w_id, 1, slots_after)), GameStyle.JADE]]
		stat_rows.append([WeaponDamageReadout.per_second_label(w_id),
				BonusRows.fmt_num(WeaponDamageReadout.per_second(w_id, 1, slots_after)),
				GameStyle.JADE])
		stat_rows.append(["攻击范围", "%.0f" % float(def.get("range", 0.0)), GameStyle.PAPER])
		var card_feats := WeaponData.card_feats(def)
		if not card_feats.is_empty():
			stat_rows.append(["特性", card_feats, GameStyle.PAPER_DIM])

	# 推荐位亮边：只在没有更具体边色语义时把中性深蓝底边提亮一档
	# （临门一档的 JADE 边、道具档位边、药水边都保留原语义，「荐」签足以表达）
	if recommended and edge_color == GameStyle.GOLD_DK:
		edge_color = GameStyle.GOLD_EDGE

	return {
		"kind": kind, "is_potion": is_potion, "is_item": is_item, "def": def,
		"title": title, "icon_path": icon_path, "tag": tag, "tag_parts": tag_parts,
		"tag_keys": tag_keys, "w_id": w_id_of_offer(offer),
		"part_hot": part_hot, "desc": desc, "stat_rows": stat_rows, "merge_ready": merge_ready,
		"chip_color": chip_color, "chip_text_color": chip_text_color,
		"edge_color": edge_color, "behavior_chip": behavior_chip,
		"recommended": recommended, "rec_reasons": rec_reasons,
		"owned_text": owned_text,
	}

## 这张卡对应的武器 id（药水/道具卡返回空串）：色签的解释卡要按它现读属性账单与件数
static func w_id_of_offer(offer: Dictionary) -> String:
	return String(offer.get("id", "")) if String(offer.get("kind", "weapon")) == "weapon" else ""

## 道具加成行的「当前 → 购买后」预览（2026-10-21 用户：「加成之后属性会是多少，和悟道加点界面类似」）。
## 读数走 StatForecast.shop_lines_for（影子 + StatSystem 落地 + StatBreakdown 聚合，与到账同式），
## 卡面不另写第二套算式。形态是内联而不是悟道式注脚：加成行每字段多插一行小字会把六字段的
## 极效药丸卡顶破「货架不许竖滑」的预算（LayoutCheck shelf_fits），内联在数值位则卡高零增长。
## 逐字段三档：
## ① 面板有行的字段 → 数值位印 "X→Y"；变化按幅度语义着色（正绿负红、乘算看方向），
##    未变化（夹顶/满血回血）退 GREY——照实写"买了等于没买"，与悟道注脚同一口径；
## ② 完整 pair 装不下这一档卡内宽 → 省掉两头的「+」再试（"26%→23%"，正号只是冗余，
##    读数与颜色不变）。2026-10-22 用户指着货架问「攻击间隔前面的数字怎么没显示」：
##    原先是硬拿最窄档 124 当所有屏的尺子，宽屏上明明放得下也退成 "→Y"，起点被砍掉；
## ③ 再装不下 → 保留原幅度行（"攻击间隔 +4%"）。宁可只讲这一件道具加多少，
##    也不印一个没有起点的 "→Y"——半个承诺比没有承诺更难读。
## 面板没有行的机制项（灵兽三件、宝箱、单系/全元素、技能冷却）没有预读，保持幅度行——
## 不给玩家在属性面板里找不到的数硬凑读数。
static func item_stat_rows(apply: Dictionary, forecast: StatForecast, row_w: float = -1.0) -> Array:
	var notes: Dictionary = {}
	for line in forecast.shop_lines_for(apply):
		notes[String(line["key"])] = line
	var rows: Array = []
	# hp_heal 与 max_hp 同值成对时折叠不单列（与模型预读同一把尺 BonusRows.folded_keys）
	var folded := BonusRows.folded_keys(apply)
	for key in apply.keys():
		var k := String(key)
		if k in folded:
			continue
		var v := float(apply[key])
		var name_txt := StatInfoData.field_name(k)
		var val_txt := StatInfoData.format_amount(k, v)
		var val_col := BonusRows.stat_color(k, v)
		if notes.has(k):
			var line: Dictionary = notes[k]
			var pair := String(line["text"])
			if _row_fits(name_txt, pair, row_w):
				val_txt = pair
			else:
				var compact_pair := compact_pair_text(String(line["before"]), String(line["after"]))
				if _row_fits(name_txt, compact_pair, row_w):
					val_txt = compact_pair
			# 预览真画出来了才按「变化/未变化」换色：未变化退 GREY，照实写买了等于没买
			if val_txt != StatInfoData.format_amount(k, v):
				val_col = BonusRows.stat_color(k, v) if bool(line["changed"]) else GameStyle.GREY
		rows.append([name_txt, val_txt, val_col])
	return rows

## 兜底档的紧凑 pair：省掉两头冗余的正号（"+26%→+23%" → "26%→23%"），数字一位不改
static func compact_pair_text(before: String, after: String) -> String:
	return "%s→%s" % [before.trim_prefix("+"), after.trim_prefix("+")]

## 单行宽度预算：行名 + 数值 + 列缝 4 要装进这一档卡内宽（BonusRows 行不换行的硬约束）。
## row_w 缺省（测试/无屏上下文）按最窄档 CARD_W_MIN 算；真上屏时由 create_card 传本屏卡内宽，
## 宽屏不该被最窄档的尺子误伤（2026-10-22 攻击间隔预览丢起点）。
static func _row_fits(name_txt: String, val_txt: String, row_w: float = -1.0) -> bool:
	var body := GameStyle.body_font()
	var need := GameStyle.line_max_w(name_txt, body, 12) \
			+ GameStyle.line_max_w(val_txt, body, 12) + 4.0
	var budget: float = row_w if row_w > 0.0 else WaveShop.card_inner_w(WaveShop.CARD_W_MIN)
	return need <= budget

## 点「荐」签 = 看推荐理由：统一走 RecommendTip（与悟道卡同一张卡，不再各留一份实现）。
static func _open_recommend_tip(host: Control, anchor: Control, reasons: Array, offer: Dictionary) -> void:
	RecommendTip.open(host, anchor, reasons, float(offer.get("recommend_score", 0.0)))

## 把一颗色签登记成「点得动、且判据认得出它该弹哪张卡」。
## hotzone 负责收「按下」那一拍：外层 GameStyle.swipeable 随后会把它降成 PASS，
## PASS 仍自己收事件、只是不再拦冒泡 ⇒ 货架照样划得动（见 GameStyle.swipeable 头注）。
## meta 是给判据读的：代码建的 Label 同名会被引擎改名（@Label@N），按名字找就是静默拿 null。
static func _mark_chip_tappable(node: Control, tip: Dictionary) -> void:
	GameStyle.hotzone(node)
	node.set_meta("chip_tip", tip)

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

## 行①：图标框（五行外框 + 元素特性下边框）与名号同行（右侧上下排列名号与持有信息），名号按 card_name_w 切硬换行
static func _create_card_head(shop: WaveShop, offer: Dictionary, card_w: float, kind: String, title: String, icon_path: String, owned_text: String = "", w_id: String = "") -> HBoxContainer:
	var head := HBoxContainer.new()
	head.name = "CardHead"
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 6)

	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(WaveShop.CARD_ICON, WaveShop.CARD_ICON)
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 边框双通道正交设计：
	# 1. 外边框（四周）：五行属性统一色（金古金/木绿/水蓝/火赤红/土棕土），无属性武器走 LINE
	# 2. 下边框：吃「元素伤害」属性加成的武器，底部挂 3px 暖橙红 ELEMENT 光带，与五行外框互不干扰
	var border_color: Color = GameStyle.LINE
	var is_elem := false
	if kind == "weapon":
		var wid := w_id if not w_id.is_empty() else String(offer.get("id", ""))
		border_color = GameStyle.weapon_element_color(wid, GameStyle.LINE)
		is_elem = GameStyle.is_elemental(wid)
	elif kind == "item":
		var idef := ItemData.get_def(String(offer.get("id", "")))
		var itier := int(idef.get("tier", 1))
		border_color = GameStyle.rarity_edge_color(itier)
	elif kind == "pet":
		var pdef := PetData.get_def(String(offer.get("id", "")))
		border_color = pdef.get("color", GameStyle.GOLD)
	icon_box.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, border_color, 2, 0.0))

	if kind == "pet":
		var p_id: String = String(offer.get("id", ""))
		var pet_preview := Control.new()
		pet_preview.custom_minimum_size = Vector2(WaveShop.CARD_ICON - 4.0, WaveShop.CARD_ICON - 4.0)
		pet_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pet_preview.draw.connect(func():
			PetIconDraw.draw_orb(pet_preview, PetData.get_def(p_id))
		)
		icon_box.add_child(pet_preview)
	else:
		# 贴合框体尺寸（保留 2px 外框余量），统一走 GameStyle.icon_texture_rect 启用线性滤波平滑
		var icon_tex := GameStyle.icon_texture_rect(
			icon_path,
			Vector2(WaveShop.CARD_ICON - 4.0, WaveShop.CARD_ICON - 4.0)
		)
		icon_box.add_child(icon_tex)

	# 元素武器底部暖橙红下边框装饰条
	if is_elem:
		GameStyle.apply_elemental_bottom_bar(icon_box, true, 3.0)
		# 元素特性点按解释：点击图标框也能查看元素武器加成账单（接通 ShopChipTips.open_element）
		var wid := w_id if not w_id.is_empty() else String(offer.get("id", ""))
		icon_box.mouse_filter = Control.MOUSE_FILTER_PASS
		GameStyle.tap(icon_box, func() -> void: ShopChipTips.open(shop, icon_box, {"kind": "element", "w_id": wid}))

	head.add_child(icon_box)

	var name_w: float = WaveShop.card_name_w(card_w)
	var title_box := VBoxContainer.new()
	title_box.name = "TitleBox"
	title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	title_box.add_theme_constant_override("separation", 1)
	title_box.custom_minimum_size = Vector2(name_w, 0)
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var title_lbl := Label.new()
	title_lbl.name = "TitleLabel"
	title_lbl.text = GameStyle.wrap_cjk(title, GameStyle.display_font(), 16, name_w)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_lbl.custom_minimum_size = Vector2(name_w, 0)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_box.add_child(title_lbl)
	GameStyle.label(title_lbl, 16, GameStyle.PAPER, 0, GameStyle.INK, true)

	if not owned_text.is_empty():
		var owned_lbl := Label.new()
		owned_lbl.name = "OwnedLabel"
		owned_lbl.text = owned_text
		owned_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		owned_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		owned_lbl.custom_minimum_size = Vector2(name_w, 0)
		owned_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		owned_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_box.add_child(owned_lbl)
		GameStyle.label(owned_lbl, 10, GameStyle.JADE_DK, 0, GameStyle.INK, true)

	head.add_child(title_box)
	return head

## 行②：流派色签流（临门一档亮绿）+「可合成」角标 + 未售出时的锁定开关
## behavior_chip 非空时插队在最前（[近战/远程/范围/环绕/机关, 面, 字]，仅武器卡有）；
## rec_reasons 非空时最先挂「荐」推荐签（点按弹推荐理由）
## 每一颗色签都点得出解释（2026-10-11 用户：「点击也要弹出来对应的解释，加成怎么样加成哪些」）：
## chip_tips 与 chip_defs 同序，{} 表示这颗没解释可看（回复药/道具的档位签）。
## 热区挂在签上、锚点也回送签本身：这两件事在 HUD 那批徽记上栽过一次（lambda 按值捕获 null）。
static func _create_card_tag_row(shop: WaveShop, offer: Dictionary, index: int, sold: bool, tag: String, chip_color: Color, chip_text_color: Color, tag_parts: Array, part_hot: Array, merge_ready: bool = false, behavior_chip: Array = [], rec_reasons: Array = [], tag_keys: Array = [], w_id: String = "") -> HBoxContainer:
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

	# 「荐」推荐签：摆在整排色签最前（推荐是这张卡最要紧的一句话），点按看理由
	if not rec_reasons.is_empty():
		var rec_lbl := Label.new()
		rec_lbl.name = "RecommendBadge"
		rec_lbl.text = " 荐 "
		rec_lbl.custom_minimum_size = Vector2(GameStyle.compact_chip_pin_w(" 荐 ", GameStyle.body_font(), 10), 0)
		rec_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rec_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rec_lbl.add_theme_stylebox_override("normal", GameStyle.compact_chip(GameStyle.JADE))
		tag_flow.add_child(rec_lbl)
		GameStyle.label(rec_lbl, 10, GameStyle.INK_TEXT)
		_mark_chip_tappable(rec_lbl, {"kind": "recommend"})
		GameStyle.tap(rec_lbl, func() -> void: _open_recommend_tip(shop, rec_lbl, rec_reasons, offer))

	var chip_defs: Array = []
	var chip_tips: Array = []
	if not behavior_chip.is_empty():
		chip_defs.append(behavior_chip)
		chip_tips.append({"kind": "behavior", "w_id": w_id})
	# 档位/流派签与攻击方式签是两件事，各判各的：behavior_chip 只有武器卡有，
	# 原先档位签嵌在它那个 if 里 ⇒ 道具/回复药/灵兽卡整排色签一颗都没有，只剩锁定键
	# （2026-10-24 用户：战旗卡上连「史诗·道具」都看不见）
	if tag_parts.is_empty():
		if not tag.is_empty():
			chip_defs.append([tag, chip_color, GameStyle.on_face_text(chip_color)])
			chip_tips.append({})	# 药水/道具/灵兽这一颗没有阶梯可解释（卡上那几行就是它的全部）
	else:
		for i in range(tag_parts.size()):
			var hot_i: bool = bool(part_hot[i])
			var chip_face: Color = GameStyle.JADE if hot_i else chip_color
			chip_defs.append([tag_parts[i],
				chip_face,
				GameStyle.on_face_text(chip_face)])
			chip_tips.append({"kind": "synergy", "tag": String(tag_keys[i]), "w_id": w_id})
	for ci in range(chip_defs.size()):
		var cd: Array = chip_defs[ci]
		var chip_txt: String = " %s " % cd[0]
		var chip_lbl := Label.new()
		chip_lbl.text = chip_txt
		chip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip_lbl.custom_minimum_size = Vector2(GameStyle.compact_chip_pin_w(chip_txt, GameStyle.body_font(), 10), 0)
		chip_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip_lbl.add_theme_stylebox_override("normal", GameStyle.compact_chip(cd[1]))
		tag_flow.add_child(chip_lbl)
		GameStyle.label(chip_lbl, 10, cd[2])
		var tip: Dictionary = chip_tips[ci]
		if tip.is_empty():
			continue
		_mark_chip_tappable(chip_lbl, tip)
		GameStyle.tap(chip_lbl, func() -> void: ShopChipTips.open(shop, chip_lbl, tip))

	if not sold:
		var locked: bool = offer.get("locked", false)
		var lock_btn := Button.new()
		lock_btn.name = "LockButton"
		lock_btn.custom_minimum_size = Vector2(WaveShop.CARD_LOCK_W, WaveShop.CARD_LOCK_H)
		lock_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		lock_btn.focus_mode = Control.FOCUS_NONE
		lock_btn.text = "已锁" if locked else "锁定"
		GameStyle.button(lock_btn, GameStyle.JADE if locked else GameStyle.NAVY2,
			GameStyle.JADE_DK if locked else GameStyle.LINE, 10,
			GameStyle.INK_TEXT if locked else GameStyle.PAPER_DIM, 3.0)
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
	elif kind == "pet" and GameManager.pets.size() >= GameManager.max_pet_slots():
		btn.disabled = true
		btn.text = "灵兽栏已满"
	elif kind == "pet" and GameManager.has_pet(offer.get("id", "")):
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

## 商品右上角圆形合成标记：当手里差 1 件即可凑齐三合一时（如已有 2 件 1 星），
## 在商品卡片右上角显示圆形标记，背景为主题色（GOLD，跟随换肤），黑字「合」。
static func _create_merge_corner_badge(shop: WaveShop, w_id: String) -> Control:
	var overlay := Control.new()
	overlay.name = "MergeCornerOverlay"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var badge_size := 20.0
	var badge := Label.new()
	badge.name = "MergeCornerBadge"
	badge.text = "合"
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.custom_minimum_size = Vector2(badge_size, badge_size)
	badge.size = Vector2(badge_size, badge_size)
	badge.mouse_filter = Control.MOUSE_FILTER_PASS

	var sb := StyleBoxFlat.new()
	sb.bg_color = GameStyle.GOLD
	var r := int(round(badge_size * 0.5))
	sb.corner_radius_top_left = r
	sb.corner_radius_top_right = r
	sb.corner_radius_bottom_right = r
	sb.corner_radius_bottom_left = r
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = GameStyle.INK
	GameStyle.register_theme_box(sb, &"bg_color", &"main")

	badge.add_theme_stylebox_override("normal", sb)
	badge.add_theme_font_override("font", GameStyle.emph_font())
	badge.add_theme_font_size_override("font_size", 11)
	badge.add_theme_color_override("font_color", GameStyle.INK)

	badge.anchor_left = 1.0
	badge.anchor_right = 1.0
	badge.anchor_top = 0.0
	badge.anchor_bottom = 0.0
	badge.offset_left = -badge_size + 8.0
	badge.offset_right = 8.0
	badge.offset_top = -1.0
	badge.offset_bottom = badge_size - 1.0

	GameStyle.tap(badge, func() -> void:
		ShopChipTips.open_merge(shop, badge, w_id)
	)

	overlay.add_child(badge)
	return overlay

