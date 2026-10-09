class_name ManualDialog
extends BaseModalDialog

## 教程手册（传道玉简）：玩法入门、聚灵阵用法、法器/法宝/修士图鉴、进阶流派攻略。
## 继承 BaseModalDialog；图鉴内容现读
## WeaponData / ItemData / CultivatorData / StatInfoData，新增条目自动进手册。
## 法宝/修士两页标注解锁条件，每次 open() 重建以反映最新解锁状态。

const PANEL_SIZE := Vector2(880, 470)
## 正文排版宽度：880 面板 − 外边距 40 − 内容面板内边距 28 − 卡片内边距 24，再留余量
const TEXT_W := 756.0

## 五行配色（法器卡 chip 用，与 GameStyle.ELEMENT_COLORS 同源）
const ELEMENT_COLORS := GameStyle.ELEMENT_COLORS

## 法器 stat_scalings 的 key → 人话名（优先查 StatInfoData，这里补面板没有的行）
const SCALING_NAMES := {
	"melee_damage": "近战伤害",
	"ranged_damage": "远程伤害",
	"elemental_damage": "元素伤害",
	"engineering_damage": "御灵伤害",
	"crit_rate": "暴击率",
	"crit_mult_bonus": "暴击伤害",
	"armor": "护甲",
	"max_hp": "气血上限",
	"move_speed_mult": "移动速度",
	"attack_speed_mult": "攻击速度",
	"lifesteal": "吸血",
}

const BEHAVIOR_NAMES := {
	WeaponData.Behavior.MELEE: "近战",
	WeaponData.Behavior.PROJECTILE: "远程",
	WeaponData.Behavior.BURST: "轰击",
	WeaponData.Behavior.DRONE: "御灵",
}

const PROC_NAMES := {"proc_burn": "灼烧", "proc_chill": "冰缓", "proc_poison": "剧毒"}

var _items_box: VBoxContainer
var _cult_box: VBoxContainer

func _get_title_text() -> String:
	return "传 道 玉 简"

func _get_panel_size() -> Vector2:
	return PANEL_SIZE

func _get_top_bar_separation() -> int:
	return 8

func _get_tab_bar_separation() -> int:
	return 6

func _get_title_font_size() -> int:
	return 17

func _get_close_btn_min_size() -> Vector2:
	return Vector2(76, 34)

func _build_body(root_vbox: VBoxContainer) -> void:
	add_tab_button(0, "入门指南", 96.0)
	add_tab_button(1, "法器图鉴", 96.0)
	add_tab_button(2, "法宝图鉴", 96.0)
	add_tab_button(3, "修士图鉴", 96.0)
	add_tab_button(4, "进阶心法", 96.0)

	var content_panel := PanelContainer.new()
	content_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var cont_sb := GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 2, 0.0)
	cont_sb.content_margin_left = 14.0
	cont_sb.content_margin_top = 10.0
	cont_sb.content_margin_right = 14.0
	cont_sb.content_margin_bottom = 10.0
	content_panel.add_theme_stylebox_override("panel", cont_sb)
	root_vbox.add_child(content_panel)

	_pages.append(_build_basics_page(content_panel))
	_pages.append(_build_weapons_page(content_panel))
	_pages.append(_build_items_page(content_panel))
	_pages.append(_build_cultivators_page(content_panel))
	_pages.append(_build_advanced_page(content_panel))

	switch_tab(0)

func _on_opened() -> void:
	_refresh_dynamic_pages()

# ----------------- 通用小件 -----------------

func _new_scroll(parent: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	return scroll

func _new_scroll_vbox(scroll: ScrollContainer, separation: int = 8) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", separation)
	scroll.add_child(box)
	return box

## 分段图文卡：段题（黄）+ 可选插图 + 正文（wrap_cjk 硬换行）
func _make_text_card(title: String, body: String, image: String = "", image_h: float = 80.0) -> Control:
	var card := PanelContainer.new()
	var sb := GameStyle.block(GameStyle.NAVY2, GameStyle.SLANT_PLATE, Vector2(2, 3))
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	card.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	card.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = "✦ " + title
	GameStyle.label(title_lbl, 15, GameStyle.YELLOW, 0, GameStyle.INK, true)
	vbox.add_child(title_lbl)

	if image != "" and ResourceLoader.exists(image):
		var img_center := CenterContainer.new()
		var tex := TextureRect.new()
		tex.texture = load(image)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(image_h * 2.0, image_h)
		img_center.add_child(tex)
		vbox.add_child(img_center)

	var body_lbl := Label.new()
	body_lbl.text = GameStyle.wrap_cjk(body, GameStyle.body_font(), 13, TEXT_W)
	GameStyle.label(body_lbl, 13, GameStyle.PAPER_DIM)
	vbox.add_child(body_lbl)

	return card

func _load_icon(path: String, tex_size: Vector2) -> TextureRect:
	var tex := TextureRect.new()
	if path != "" and ResourceLoader.exists(path):
		tex.texture = load(path)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.custom_minimum_size = tex_size
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return tex

## 图鉴小卡：图标 + 名称（+ 可选副标签），点按开 DetailTip
func _make_entry_card(icon: String, name: String, sub: String, sub_color: Color,
		on_press: Callable) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(148, 0)
	var sb := GameStyle.block(GameStyle.NAVY2, GameStyle.SLANT_PLATE, Vector2(2, 3))
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	card.add_theme_stylebox_override("panel", sb)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.set_meta("tip_title", name)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	var icon_center := CenterContainer.new()
	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(48, 48)
	icon_box.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 1, 0.0))
	var tex := _load_icon(icon, Vector2(40, 40))
	tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex.offset_left = 4
	tex.offset_top = 4
	tex.offset_right = -4
	tex.offset_bottom = -4
	icon_box.add_child(tex)
	icon_center.add_child(icon_box)
	vbox.add_child(icon_center)
	card.set_meta("icon_tex", tex)

	var name_lbl := Label.new()
	name_lbl.text = name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameStyle.label(name_lbl, 13, GameStyle.PAPER, 0, GameStyle.INK, true)
	vbox.add_child(name_lbl)

	if sub != "":
		var sub_lbl := Label.new()
		sub_lbl.text = sub
		sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		GameStyle.label(sub_lbl, 11, sub_color)
		vbox.add_child(sub_lbl)

	GameStyle.tap(card, func() -> void: on_press.call(card))
	# 整格都是热区：图框那层 PanelContainer 默认 STOP，会把「点图片」这一枪截在半路 ——
	# 真机上就成了点名字弹卡、点图没反应（用户 2026-10-09 反馈）。放在最后一步统一压子树。
	GameStyle.hotzone(card)
	return card

# ----------------- 分页 1：入门指南 -----------------

func _build_basics_page(parent: Control) -> Control:
	var scroll := _new_scroll(parent)
	var box := _new_scroll_vbox(scroll)
	for sec in ManualData.BASICS_SECTIONS:
		box.add_child(_make_text_card(
			String(sec.get("title", "")),
			String(sec.get("body", "")),
			String(sec.get("image", "")),
			float(sec.get("image_h", 80.0))
		))
	return scroll

# ----------------- 分页 2：法器图鉴 -----------------

func _build_weapons_page(parent: Control) -> Control:
	var scroll := _new_scroll(parent)
	var box := _new_scroll_vbox(scroll)

	box.add_child(_make_text_card("法器规则",
		"法器只能在波间「灵石阁」购买：上阵 %d 槽，纳戒（背包）%d 格。\n集齐 3 把同名同星可手动合成升星：每星伤害 ×%s、攻击间隔 ×%s，最高 ★%d。\n点按任意法器卡查看射程、冷却与属性受益。" % [
			WeaponData.MAX_SLOTS, WeaponData.MAX_STASH_SLOTS,
			String.num(WeaponData.STAR_DAMAGE_MULT, 1), String.num(WeaponData.STAR_COOLDOWN_MULT, 2),
			WeaponData.MAX_STAR]))

	# 按五行分组展示，与 WeaponData.DEFS 的排布同源
	for elem in WeaponData.ELEMENTS:
		var header := Label.new()
		header.text = "── %s行法器 ──" % String(StatInfoData.ELEMENT_NAMES.get(elem, elem))
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		GameStyle.label(header, 13, ELEMENT_COLORS.get(elem, GameStyle.PAPER), 0, GameStyle.INK, true)
		box.add_child(header)

		var grid := GridContainer.new()
		grid.columns = 5
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(grid)

		for wid in WeaponData.DEFS.keys():
			var def: Dictionary = WeaponData.DEFS[wid]
			var tags: Array = def.get("tags", [])
			if not (elem in tags):
				continue
			var cls := ""
			for t in tags:
				if t != elem:
					cls = String(t)
			var cls_name := String(WeaponData.SYNERGIES.get(cls, {}).get("name", cls))
			var card := _make_entry_card(
				String(def.get("icon", "")), String(def.get("name", wid)),
				cls_name, GameStyle.PAPER_DIM,
				func(anchor: Control): _open_weapon_tip(wid, anchor))
			# 吃「元素伤害」属性加成的法器挂橙红角标（图鉴与商店/属性面板同一口径）
			var icon_tex := card.get_meta("icon_tex") as TextureRect
			if icon_tex != null and icon_tex.get_parent() != null:
				GameStyle.maybe_add_element_badge(icon_tex.get_parent(), wid, 8)
			grid.add_child(card)
	return scroll

func _open_weapon_tip(wid: String, anchor: Control) -> void:
	var def := WeaponData.get_def(wid)
	if def.is_empty():
		return
	var elem := ""
	for t in def.get("tags", []):
		if t in WeaponData.ELEMENTS:
			elem = String(t)
	var chip_color: Color = ELEMENT_COLORS.get(elem, GameStyle.BLUE)

	var rows: Array = [
		["路数", String(BEHAVIOR_NAMES.get(def.get("behavior", 0), "近战")), chip_color],
		["伤害", "%d" % int(def.get("damage", 0)), GameStyle.YELLOW],
		["攻击间隔", "%s 秒" % String.num(float(def.get("cooldown", 1.0)), 2), GameStyle.PAPER],
		["射程/范围", "%d" % int(def.get("range", 0)), GameStyle.PAPER],
		["买入灵石", "%d 灵石" % int(def.get("price", 0)), GameStyle.YELLOW],
	]
	if int(def.get("pierce", 0)) > 0:
		rows.append(["贯穿", "%d 敌" % int(def["pierce"]), GameStyle.PAPER])
	if int(def.get("projectile_count", 1)) > 1:
		rows.append(["齐射", "%d 枚" % int(def["projectile_count"]), GameStyle.PAPER])
	for proc_key in PROC_NAMES.keys():
		if def.has(proc_key):
			rows.append(["异常状态", PROC_NAMES[proc_key], chip_color])

	var notes: Array[String] = []
	var scalings: Dictionary = def.get("stat_scalings", {})
	if not scalings.is_empty():
		var names: Array[String] = []
		for key in scalings.keys():
			var k := String(key)
			names.append(String(SCALING_NAMES.get(k, StatInfoData.field_name(k))))
		notes.append("属性受益：" + "、".join(names))
	notes.append("集齐 3 把同名同星可在灵石阁合成升星")

	DetailTip.show_over(self, anchor, {
		"title": String(def.get("name", wid)),
		"chip": " " + String(def.get("tag", "")) + " ",
		"chip_color": chip_color,
		"rows": rows,
		"body": String(def.get("desc", "")),
		"notes": notes,
		"foot": "法器仅在波间灵石阁有售",
	})

# ----------------- 分页 3：法宝图鉴 -----------------

func _build_items_page(parent: Control) -> Control:
	var scroll := _new_scroll(parent)
	_items_box = _new_scroll_vbox(scroll)
	return scroll

func _rebuild_items_page() -> void:
	for c in _items_box.get_children():
		c.queue_free()
	_items_box.add_child(_make_text_card("法宝规则",
		"法宝是买即生效的被动奇珍，无限持有、不占法器栏位。\n品阶越高现身越晚、价格越贵：凡品开局即有，良品、仙品、传说随波次陆续现身。\n点按任意法宝卡查看效果与入手价。"))

	for tier in [1, 2, 3, 4]:
		var tier_col: Color = ItemData.tier_color(tier)
		var header := Label.new()
		header.text = "── %s ──" % ItemData.tier_label(tier)
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		GameStyle.label(header, 13, tier_col, 0, GameStyle.INK, true)
		_items_box.add_child(header)

		var grid := GridContainer.new()
		grid.columns = 5
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_items_box.add_child(grid)

		for iid in ItemData.DEFS.keys():
			var def: Dictionary = ItemData.DEFS[iid]
			if int(def.get("tier", 1)) != tier:
				continue
			var unlocked := GameManager.is_item_unlocked(iid)
			var card := _make_entry_card(
				String(def.get("icon", "")), String(def.get("name", iid)),
				"" if unlocked else "未入阁", GameStyle.GREY,
				func(anchor: Control): _open_item_tip(iid, anchor))
			if not unlocked:
				(card.get_meta("icon_tex") as TextureRect).modulate = Color(0.4, 0.4, 0.5, 0.7)
			grid.add_child(card)

func _open_item_tip(iid: String, anchor: Control) -> void:
	var def := ItemData.get_def(iid)
	if def.is_empty():
		return
	var tier_num := int(def.get("tier", 1))
	var tier_col := ItemData.tier_color(tier_num)
	var rows: Array = [
		["品阶", ItemData.tier_label(tier_num), tier_col],
		["买入灵石", "%d 灵石" % int(def.get("price", 0)), GameStyle.YELLOW],
	]
	var desc_lines := String(def.get("desc", "")).split("\n")
	var notes: Array[String] = []
	for line in desc_lines:
		if line.strip_edges() != "":
			notes.append(line.strip_edges())
	var foot := ""
	if not GameManager.is_item_unlocked(iid):
		var ach := AchievementData.item_unlock_achievement(iid)
		if not ach.is_empty():
			foot = "入阁条件：" + String(ach.get("cond_desc", ""))
	elif bool(def.get("unique", false)):
		foot = "每局限购一件"

	DetailTip.show_over(self, anchor, {
		"title": String(def.get("name", iid)),
		"chip": " " + ItemData.tier_label(tier_num) + " ",
		"chip_color": tier_col,
		"rows": rows,
		"notes": notes,
		"foot": foot,
	})

# ----------------- 分页 4：修士图鉴 -----------------

func _build_cultivators_page(parent: Control) -> Control:
	var scroll := _new_scroll(parent)
	_cult_box = _new_scroll_vbox(scroll)
	return scroll

func _rebuild_cultivators_page() -> void:
	for c in _cult_box.get_children():
		c.queue_free()
	_cult_box.add_child(_make_text_card("道统规则",
		"每名修士都是「超能力 + 严苛负面代偿」的不对称设计：选人是本局最重要的流派决定。\n初始开放四名道统，其余通过「修仙志」的天道功绩解锁。"))

	for cid in CultivatorData.DEFS.keys():
		var def: Dictionary = CultivatorData.DEFS[cid]
		_cult_box.add_child(_make_cultivator_row(cid, def))

func _make_cultivator_row(cid: String, def: Dictionary) -> Control:
	var unlocked := GameManager.is_cultivator_unlocked(cid)
	var row := PanelContainer.new()
	var sb := GameStyle.block(GameStyle.NAVY2 if unlocked else GameStyle.INK.lightened(0.02),
		GameStyle.SLANT_PLATE, Vector2(2, 3))
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	sb.border_color = GameStyle.LINE if unlocked else GameStyle.LINE.darkened(0.3)
	row.add_theme_stylebox_override("panel", sb)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	row.add_child(hbox)

	# 头像
	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(56, 56)
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_box.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 1, 0.0))
	var tex := _load_icon(String(def.get("icon", "")), Vector2(48, 48))
	tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex.offset_left = 4
	tex.offset_top = 4
	tex.offset_right = -4
	tex.offset_bottom = -4
	if not unlocked:
		tex.modulate = Color(0.4, 0.4, 0.5, 0.7)
	icon_box.add_child(tex)
	hbox.add_child(icon_box)

	# 名号 + 题词 + 优劣
	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 2)
	hbox.add_child(text_col)

	var name_lbl := Label.new()
	name_lbl.text = String(def.get("name", cid))
	GameStyle.label(name_lbl, 15, GameStyle.PAPER if unlocked else GameStyle.PAPER_DIM, 0, GameStyle.INK, true)
	text_col.add_child(name_lbl)

	var epithet_lbl := Label.new()
	epithet_lbl.text = String(def.get("epithet", ""))
	GameStyle.label(epithet_lbl, 11, GameStyle.GREY)
	text_col.add_child(epithet_lbl)

	var equip_str: String = String(def.get("start_equip", ""))
	if not equip_str.is_empty():
		var equip_lbl := Label.new()
		equip_lbl.text = "✦ " + equip_str
		GameStyle.label(equip_lbl, 12, GameStyle.YELLOW)
		text_col.add_child(equip_lbl)

	for pro in def.get("pros", []):
		var pro_lbl := Label.new()
		pro_lbl.text = "＋ " + String(pro)
		GameStyle.label(pro_lbl, 12, GameStyle.GOOD)
		text_col.add_child(pro_lbl)
	for con in def.get("cons", []):
		var con_lbl := Label.new()
		con_lbl.text = "－ " + String(con)
		GameStyle.label(con_lbl, 12, GameStyle.BAD)
		text_col.add_child(con_lbl)

	# 解锁状态
	var status_lbl := Label.new()
	status_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if unlocked:
		status_lbl.text = " 已入门 "
		status_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.GOOD_DK))
		GameStyle.label(status_lbl, 12, GameStyle.GOOD)
	else:
		status_lbl.text = " 未解锁 "
		status_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.LINE))
		GameStyle.label(status_lbl, 12, GameStyle.GREY)
		var ach := AchievementData.cultivator_unlock_achievement(cid)
		if not ach.is_empty():
			var cond_lbl := Label.new()
			cond_lbl.text = "解锁条件：" + String(ach.get("cond_desc", ""))
			GameStyle.label(cond_lbl, 11, GameStyle.YELLOW)
			text_col.add_child(cond_lbl)
	hbox.add_child(status_lbl)

	return row

# ----------------- 分页 5：进阶心法 -----------------

func _build_advanced_page(parent: Control) -> Control:
	var scroll := _new_scroll(parent)
	var box := _new_scroll_vbox(scroll)

	box.add_child(_make_synergy_card())
	box.add_child(_make_stat_guide_card())
	for guide in ManualData.BUILD_GUIDES:
		box.add_child(_make_build_card(guide))
	for sec in ManualData.ADVANCED_SECTIONS:
		box.add_child(_make_text_card(String(sec.get("title", "")), String(sec.get("body", ""))))
	return scroll

## 流派羁绊一览：现读 WeaponData.SYNERGIES，器类 5 行 + 五行 5 行
func _make_synergy_card() -> Control:
	var card := PanelContainer.new()
	var sb := GameStyle.block(GameStyle.NAVY2, GameStyle.SLANT_PLATE, Vector2(2, 3))
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	card.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	card.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = "✦ 流派羁绊"
	GameStyle.label(title_lbl, 15, GameStyle.YELLOW, 0, GameStyle.INK, true)
	vbox.add_child(title_lbl)

	var intro_lbl := Label.new()
	intro_lbl.text = GameStyle.wrap_cjk(
		"持有同一标签的法器达 2 / 4 / 6 件时逐级激活羁绊加成。器类与五行两条线互不冲突、同时生效——凑羁绊是中期发力的核心。",
		GameStyle.body_font(), 13, TEXT_W)
	GameStyle.label(intro_lbl, 13, GameStyle.PAPER_DIM)
	vbox.add_child(intro_lbl)

	for group in [["器类", WeaponData.CLASSES], ["五行", WeaponData.ELEMENTS]]:
		var g_lbl := Label.new()
		g_lbl.text = "─ %s ─" % String(group[0])
		GameStyle.label(g_lbl, 12, GameStyle.GREY)
		vbox.add_child(g_lbl)
		for tag in group[1]:
			var syn: Dictionary = WeaponData.SYNERGIES.get(tag, {})
			if syn.is_empty():
				continue
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 10)
			vbox.add_child(line)
			var name_lbl := Label.new()
			name_lbl.text = String(syn.get("name", tag))
			name_lbl.custom_minimum_size = Vector2(64, 0)
			GameStyle.label(name_lbl, 13, GameStyle.BLUE_EDGE if group[0] == "器类" else GameStyle.YELLOW,
				0, GameStyle.INK, true)
			line.add_child(name_lbl)
			var desc_lbl := Label.new()
			desc_lbl.text = String(syn.get("desc", ""))
			GameStyle.label(desc_lbl, 12, GameStyle.PAPER_DIM)
			line.add_child(desc_lbl)
	return card

## 属性词条解读：现读 StatInfoData 的一句话说明
func _make_stat_guide_card() -> Control:
	var card := PanelContainer.new()
	var sb := GameStyle.block(GameStyle.NAVY2, GameStyle.SLANT_PLATE, Vector2(2, 3))
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	card.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	card.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = "✦ 属性词条 · 这是什么"
	GameStyle.label(title_lbl, 15, GameStyle.YELLOW, 0, GameStyle.INK, true)
	vbox.add_child(title_lbl)

	var intro_lbl := Label.new()
	intro_lbl.text = GameStyle.wrap_cjk(
		"局内点右上「境界」打开属性面板，每条属性还能点按看结算公式与上限。以下是常用词条的一句话解读：",
		GameStyle.body_font(), 13, TEXT_W)
	GameStyle.label(intro_lbl, 13, GameStyle.PAPER_DIM)
	vbox.add_child(intro_lbl)

	for sid in ManualData.STAT_GUIDE_IDS:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		vbox.add_child(line)
		var name_lbl := Label.new()
		name_lbl.text = StatInfoData.title(sid)
		name_lbl.custom_minimum_size = Vector2(96, 0)
		GameStyle.label(name_lbl, 12, GameStyle.BLUE_EDGE, 0, GameStyle.INK, true)
		line.add_child(name_lbl)
		var brief_lbl := Label.new()
		brief_lbl.text = GameStyle.wrap_cjk(StatInfoData.brief(sid), GameStyle.body_font(), 12, TEXT_W - 116.0)
		brief_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		GameStyle.label(brief_lbl, 12, GameStyle.PAPER_DIM)
		line.add_child(brief_lbl)
	return card

## 流派攻略卡
func _make_build_card(guide: Dictionary) -> Control:
	var card := PanelContainer.new()
	var sb := GameStyle.block(GameStyle.NAVY2, GameStyle.SLANT_PLATE, Vector2(2, 3))
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	sb.border_width_bottom = 4
	sb.border_color = GameStyle.BLUE
	card.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	card.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = "✦ 流派 · " + String(guide.get("name", ""))
	GameStyle.label(title_lbl, 15, GameStyle.BLUE_EDGE, 0, GameStyle.INK, true)
	vbox.add_child(title_lbl)

	var wps: Array[String] = []
	for w in guide.get("weapons", []):
		wps.append(String(w))
	var rows := [
		["推荐道统", String(guide.get("cultivator", ""))],
		["核心法器", "、".join(wps)],
		["关键羁绊", String(guide.get("synergies", ""))],
		["加点顺序", String(guide.get("upgrades", ""))],
		["推荐法宝", String(guide.get("items", ""))],
	]
	for r in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		vbox.add_child(line)
		var k_lbl := Label.new()
		k_lbl.text = String(r[0])
		k_lbl.custom_minimum_size = Vector2(72, 0)
		GameStyle.label(k_lbl, 12, GameStyle.GREY)
		line.add_child(k_lbl)
		var v_lbl := Label.new()
		v_lbl.text = String(r[1])
		GameStyle.label(v_lbl, 12, GameStyle.PAPER)
		line.add_child(v_lbl)

	var tips_lbl := Label.new()
	tips_lbl.text = GameStyle.wrap_cjk(String(guide.get("tips", "")), GameStyle.body_font(), 12, TEXT_W)
	GameStyle.label(tips_lbl, 12, GameStyle.PAPER_DIM)
	vbox.add_child(tips_lbl)
	return card

## 每次打开重建受解锁状态影响的两页
func _refresh_dynamic_pages() -> void:
	if is_instance_valid(_items_box):
		_rebuild_items_page()
	if is_instance_valid(_cult_box):
		_rebuild_cultivators_page()
	# 五页都过一遍：卡片是 PanelContainer（默认 STOP），会把「按下」那一拍吃掉，
	# 外层 ScrollContainer 收不到按下就锁不住手指拖动 → 真机上灰色卡片区域滑不动。
	# 放在这里而不是 _build_ui 末尾：法宝/修士两页每次 open 都重建子树，得重刷一遍。
	for p in _pages:
		GameStyle.swipeable(p as Control)
