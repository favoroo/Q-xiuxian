class_name WaveShop
extends Control

## 波间灵石阁：购买法器/回气丹、重掷货架；
## 上阵 + 背包统一点选后操作：三合一合成 / 上阵卸下 / 出售换灵石

signal stats_requested

@onready var stones_label: Label = $CenterContainer/Panel/MarginContainer/VBox/TopBar/StonesChip/StonesLabel
@onready var wave_label: Label = $CenterContainer/Panel/MarginContainer/VBox/TopBar/WaveLabel
@onready var offers_container: HBoxContainer = $CenterContainer/Panel/MarginContainer/VBox/OffersContainer
@onready var owned_container: HBoxContainer = $CenterContainer/Panel/MarginContainer/VBox/OwnedContainer
@onready var action_bar: HBoxContainer = $CenterContainer/Panel/MarginContainer/VBox/ActionBar
@onready var reroll_btn: Button = $CenterContainer/Panel/MarginContainer/VBox/BottomBar/RerollButton
@onready var confirm_btn: Button = $CenterContainer/Panel/MarginContainer/VBox/BottomBar/ConfirmButton

## 货架卡片的宽度与内边距：按货架格数自适应计算，防止 5/6 格货架在 960 屏宽下横向出屏
const OFFER_CARD_W := 196.0
const OFFER_PAD_X := 12.0

static func offer_card_w(count: int) -> float:
	if count >= 6:
		return 132.0
	elif count == 5:
		return 160.0
	return OFFER_CARD_W

static func offer_separation(count: int) -> int:
	if count >= 6:
		return 8
	elif count == 5:
		return 10
	return 16

var _synergy_bar: HBoxContainer = null

## 当前点选的法器：{"pool": "equipped"/"stash", "index": int}
var selected: Dictionary = {}

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameStyle.label(stones_label, 17, GameStyle.INK_TEXT)
	GameStyle.label(wave_label, 15, GameStyle.PAPER_DIM)
	GameStyle.button(reroll_btn, GameStyle.NAVY2, GameStyle.LINE, 14, GameStyle.PAPER_DIM)
	GameStyle.button(confirm_btn, GameStyle.BLUE, GameStyle.YELLOW, 18, GameStyle.PAPER, 6.0, GameStyle.INK_TEXT)
	confirm_btn.text = "出  战"
	GameManager.shop_opened.connect(_on_shop_opened)
	reroll_btn.pressed.connect(_on_reroll)
	confirm_btn.pressed.connect(_on_confirm)

	# 顶栏右侧添加「属性」按钮，方便随时查看主要/次要面板
	var top_bar: HBoxContainer = $CenterContainer/Panel/MarginContainer/VBox/TopBar
	var stats_btn := Button.new()
	stats_btn.text = "属 性"
	stats_btn.custom_minimum_size = Vector2(72, 32)
	stats_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(stats_btn, GameStyle.NAVY2, GameStyle.YELLOW, 13, GameStyle.PAPER, 4.0, GameStyle.INK_TEXT)
	stats_btn.pressed.connect(func(): stats_requested.emit())
	top_bar.add_child(stats_btn)

	# 羁绊总览行：插在顶栏之下
	_synergy_bar = HBoxContainer.new()
	_synergy_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_synergy_bar.add_theme_constant_override("separation", 10)
	var vbox: VBoxContainer = $CenterContainer/Panel/MarginContainer/VBox
	vbox.add_child(_synergy_bar)
	vbox.move_child(_synergy_bar, 1)

## 羁绊总览：激活的流派显示金色等级徽记，未激活显示灰色进度；支持点按查看详情卡
func _refresh_synergy_bar() -> void:
	if _synergy_bar == null:
		return
	for child in _synergy_bar.get_children():
		child.queue_free()
	var any := false
	for tag in GameManager.active_synergies.keys():
		var info: Dictionary = WeaponData.SYNERGIES.get(tag, {})
		if info.is_empty():
			continue
		var data: Dictionary = GameManager.active_synergies[tag]
		var n := int(data.get("count", 0))
		var lv := int(data.get("level", 0))
		var thresholds: Array = info.get("thresholds", [])
		var next := "MAX"
		for th in thresholds:
			if n < int(th):
				next = str(th)
				break
		var chip_lbl := Label.new()
		chip_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		if lv > 0:
			chip_lbl.text = " %s Lv.%d " % [info.get("name", tag), lv]
			chip_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.YELLOW))
			GameStyle.label(chip_lbl, 12, GameStyle.INK_TEXT)
		else:
			chip_lbl.text = " %s %d/%s " % [info.get("name", tag), n, next]
			chip_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.NAVY2))
			GameStyle.label(chip_lbl, 12, GameStyle.PAPER_DIM)
		chip_lbl.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
				_open_shop_synergy_tip(tag, chip_lbl)
		)
		_synergy_bar.add_child(chip_lbl)
		any = true
	_synergy_bar.visible = any

func _open_shop_synergy_tip(tag: String, anchor: Control) -> void:
	var info: Dictionary = WeaponData.SYNERGIES.get(tag, {})
	if info.is_empty():
		return
	var data: Dictionary = GameManager.active_synergies.get(tag, {"count": 0, "level": 0})
	var n: int = int(data.get("count", 0))
	var lv: int = int(data.get("level", 0))
	var th_list: Array = info.get("thresholds", [2, 4, 6])
	var rows: Array = [
		["当前持有", "%d 件法器" % n, GameStyle.YELLOW if n >= 2 else GameStyle.PAPER],
		["激活档位", "Lv.%d" % lv if lv > 0 else "未激活 (需%d件)" % int(th_list[0]), GameStyle.GOOD if lv > 0 else GameStyle.GREY],
	]
	var notes: Array[String] = [
		"同标签法器上阵达到 2 / 4 / 6 件时激活阶梯加成。",
		String(info.get("desc", "")),
	]
	DetailTip.show_over(self, anchor, {
		"title": "%s羁绊" % info.get("name", tag),
		"chip": "五行" if tag in WeaponData.ELEMENTS else "器类",
		"chip_color": GameStyle.YELLOW if tag in WeaponData.ELEMENTS else GameStyle.BLUE,
		"rows": rows,
		"body": "流派共鸣：持有越多同类法器，道法威能越强盛。",
		"notes": notes,
		"foot": "在波间灵石阁挑选同标签法器可继续提升阶位。",
	})

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		if DetailTip.close_all(self):
			get_viewport().set_input_as_handled()

func _on_shop_opened() -> void:
	selected = {}
	refresh()
	visible = true
	get_tree().paused = true
	modulate.a = 0.0
	var tw = create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.2)

func refresh() -> void:
	stones_label.text = "灵石 %d" % GameManager.spirit_stones
	wave_label.text = "第 %d 波来犯之前 · 置办法器" % (GameManager.wave_number + 1)
	if GameManager.reroll_free_left > 0:
		reroll_btn.text = "免费重掷 (剩 %d 次)" % GameManager.reroll_free_left
	else:
		reroll_btn.text = "重掷货架 (%d 灵石)" % GameManager.reroll_cost
	_refresh_synergy_bar()

	for child in offers_container.get_children():
		child.queue_free()
	var offers: Array = GameManager.shop_offers
	var count := offers.size()
	var card_w := offer_card_w(count)
	offers_container.add_theme_constant_override("separation", offer_separation(count))
	for i in range(count):
		var c := _create_offer_card(offers[i], i, count)
		offers_container.add_child(c)
		c.pivot_offset = Vector2(card_w * 0.5, 134.0)
		c.scale = Vector2(0.82, 0.82)
		c.modulate.a = 0.0
		var ctw := c.create_tween()
		ctw.tween_interval(float(i) * 0.045)
		ctw.set_parallel(true)
		ctw.tween_property(c, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		ctw.tween_property(c, "modulate:a", 1.0, 0.15)

	_refresh_inventory()

# ---------------- 上阵 + 背包栏位 ----------------

func _refresh_inventory() -> void:
	for child in owned_container.get_children():
		child.queue_free()

	var summary: Array = GameManager.get_weapons_summary()
	if summary.is_empty() and GameManager.stash.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "（周身还没有法器）"
		owned_container.add_child(empty_lbl)
		GameStyle.label(empty_lbl, 13, GameStyle.GREY)
	else:
		for i in range(summary.size()):
			owned_container.add_child(_create_inv_slot(summary[i], i, "equipped"))
		owned_container.add_child(_create_stash_divider())
		for i in range(GameManager.stash.size()):
			owned_container.add_child(_create_inv_slot(GameManager.stash[i], i, "stash"))
		# 背包空位画成凹槽提示容量；上阵较满时少画几个避免溢出
		var empty_budget: int = clampi(10 - summary.size() - GameManager.stash.size(), 0, 3)
		for i in range(mini(WeaponData.MAX_STASH_SLOTS - GameManager.stash.size(), empty_budget)):
			owned_container.add_child(_create_empty_stash_slot())

	# 已持有法宝（被动道具）陈列：小图标 + 悬浮查看说明，不参与点选操作
	if not GameManager.items.is_empty():
		owned_container.add_child(_create_items_divider())
		for item_id in GameManager.items:
			owned_container.add_child(_create_item_chip(item_id))

	_refresh_action_bar()

func _create_inv_slot(item: Dictionary, index: int, pool: String) -> Control:
	var id: String = item.get("id", "")
	var star: int = int(item.get("star", 1))
	var mergeable: bool = star < WeaponData.MAX_STAR and GameManager.count_copies(id, star) >= 3
	var is_sel: bool = selected.get("pool", "") == pool and int(selected.get("index", -1)) == index

	var btn = Button.new()
	btn.custom_minimum_size = Vector2(52, 52)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.focus_mode = Control.FOCUS_NONE

	var border: Color = GameStyle.LINE
	var bg: Color = GameStyle.NAVY2
	if pool == "equipped":
		border = GameStyle.BLUE
		bg = GameStyle.NAVY
	if mergeable:
		border = GameStyle.YELLOW
	if is_sel:
		border = GameStyle.PAPER
		bg = GameStyle.NAVY.lightened(0.08)
	var normal := GameStyle.outlined_panel(bg, border, 2, 0.0)
	var hover := GameStyle.outlined_panel(bg.lightened(0.06), border.lightened(0.2), 2, 0.0)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var icon_path: String = item.get("icon", "")
	if icon_path.is_empty():
		icon_path = WeaponData.get_def(id).get("icon", "")

	var icon_tex = TextureRect.new()
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
	btn.add_child(icon_tex)

	var star_lbl = Label.new()
	star_lbl.text = "★%d" % star
	star_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	star_lbl.add_theme_font_override("font", GameStyle.body_font())
	star_lbl.add_theme_font_size_override("font_size", 11)
	star_lbl.add_theme_color_override("font_color", GameStyle.YELLOW)
	star_lbl.add_theme_color_override("font_outline_color", GameStyle.INK)
	star_lbl.add_theme_constant_override("outline_size", 3)
	star_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	star_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	star_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	star_lbl.offset_left = 2
	star_lbl.offset_top = 2
	star_lbl.offset_right = -3
	star_lbl.offset_bottom = -2
	btn.add_child(star_lbl)

	btn.pressed.connect(func():
		if is_sel:
			selected = {}
		else:
			selected = {"pool": pool, "index": index}
		_refresh_inventory()
	)
	return btn

func _create_stash_divider() -> Control:
	var chip = PanelContainer.new()
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 1, 0.0))
	var lbl = Label.new()
	lbl.text = "背包 %d/%d" % [GameManager.stash.size(), WeaponData.MAX_STASH_SLOTS]
	chip.add_child(lbl)
	GameStyle.label(lbl, 11, GameStyle.GREY)
	return chip

func _create_items_divider() -> Control:
	var chip = PanelContainer.new()
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 1, 0.0))
	var lbl = Label.new()
	lbl.text = "法宝 %d" % GameManager.items.size()
	chip.add_child(lbl)
	GameStyle.label(lbl, 11, GameStyle.GREY)
	return chip

## 已持有法宝的小徽记：按档位描边，支持点按弹出 DetailTip 详解卡
func _create_item_chip(item_id: String) -> Control:
	var def := ItemData.get_def(item_id)
	var chip = PanelContainer.new()
	chip.custom_minimum_size = Vector2(40, 52)
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
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

	chip.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
			_open_shop_item_tip(item_id, chip)
	)
	return chip

func _open_shop_item_tip(item_id: String, anchor: Control) -> void:
	var def := ItemData.get_def(item_id)
	if def.is_empty():
		return
	var tier_num: int = int(def.get("tier", 1))
	var tier_col: Color = ItemData.tier_color(tier_num)
	var rows: Array = [
		["品阶", ItemData.tier_label(tier_num), tier_col],
		["买入灵石", "%d 灵石" % int(def.get("price", 0)), GameStyle.YELLOW],
	]
	var desc_lines: Array = String(def.get("desc", "")).split("\n")
	var notes: Array[String] = []
	for line in desc_lines:
		var s := String(line).strip_edges()
		if not s.is_empty():
			notes.append(s)
	DetailTip.show_over(self, anchor, {
		"title": String(def.get("name", item_id)),
		"chip": "法宝灵物",
		"chip_color": tier_col,
		"rows": rows,
		"body": "本命法宝：被动生效，无需占用上阵槽位，整局战斗持续庇护。",
		"notes": notes,
		"foot": "在波间灵石阁可邂逅更多稀世奇珍。",
	})

func _create_empty_stash_slot() -> Control:
	var slot = PanelContainer.new()
	slot.custom_minimum_size = Vector2(30, 52)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := GameStyle.slot()
	style.bg_color = Color(GameStyle.INK.r, GameStyle.INK.g, GameStyle.INK.b, 0.55)
	slot.add_theme_stylebox_override("panel", style)
	return slot

# ---------------- 点选操作条 ----------------

func _refresh_action_bar() -> void:
	for child in action_bar.get_children():
		child.queue_free()

	if selected.is_empty():
		var hint = Label.new()
		hint.text = "◆ 点选法器：三合一合成升星 · 上阵/卸下 · 出售换灵石 ◆"
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action_bar.add_child(hint)
		GameStyle.label(hint, 12, GameStyle.GREY)
		return

	var item := _resolve_selected()
	if item.is_empty():
		selected = {}
		_refresh_action_bar()
		return

	var id: String = item.get("id", "")
	var star: int = int(item.get("star", 1))
	var pool: String = selected.get("pool", "")
	var in_stash: bool = pool == "stash"
	var mergeable: bool = star < WeaponData.MAX_STAR and GameManager.count_copies(id, star) >= 3

	var name_lbl = Label.new()
	name_lbl.text = "%s · %s" % [WeaponData.full_name(id, star), "背包" if in_stash else "上阵中"]
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	action_bar.add_child(name_lbl)
	GameStyle.label(name_lbl, 15, GameStyle.PAPER)

	if mergeable:
		var merge_btn = Button.new()
		merge_btn.text = "三合一 ▲★%d" % (star + 1)
		merge_btn.custom_minimum_size = Vector2(128, 38)
		merge_btn.focus_mode = Control.FOCUS_NONE
		GameStyle.button(merge_btn, GameStyle.YELLOW, GameStyle.YELLOW_EDGE, 14, GameStyle.INK_TEXT, 6.0)
		var keep := {"pool": "equipped", "index": int(selected.get("index", -1))}
		if in_stash:
			keep["pool"] = "stash"
		elif item.get("is_drone", false):
			keep["pool"] = "drone"
			keep["index"] = int(item.get("drone_index", -1))
		merge_btn.pressed.connect(func():
			# 成功音由 GameManager.merge_weapon 统一播（merge_success）；
			# 这里只补「按了但没合成」的反馈，不让它听起来像成功了
			if not GameManager.merge_weapon(id, star, keep):
				AudioManager.play_sfx("ui_error", 0.9)
			selected = {}
			refresh()
		)
		action_bar.add_child(merge_btn)

	var move_btn = Button.new()
	move_btn.custom_minimum_size = Vector2(108, 38)
	move_btn.focus_mode = Control.FOCUS_NONE
	if in_stash:
		move_btn.text = "上 阵"
		move_btn.disabled = GameManager.slots_used() >= GameManager.max_weapon_slots()
		GameStyle.button(move_btn, GameStyle.GOOD if not move_btn.disabled else GameStyle.NAVY2, GameStyle.GOOD_DK, 14, GameStyle.INK_TEXT, 6.0)
		move_btn.pressed.connect(func():
			if GameManager.equip_from_stash(int(selected.get("index", -1))):
				selected = {}
				refresh()
		)
	else:
		move_btn.text = "卸入背包"
		move_btn.disabled = GameManager.stash.size() >= WeaponData.MAX_STASH_SLOTS
		GameStyle.button(move_btn, GameStyle.NAVY2, GameStyle.LINE, 14, GameStyle.PAPER, 6.0)
		move_btn.pressed.connect(func():
			if GameManager.unequip_to_stash(int(selected.get("index", -1))):
				selected = {}
				refresh()
		)
	action_bar.add_child(move_btn)

	var price := WeaponData.sell_price(id, star)
	var sell_btn = Button.new()
	sell_btn.text = "售 %d 灵石" % price
	sell_btn.custom_minimum_size = Vector2(112, 38)
	sell_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(sell_btn, GameStyle.BAD, GameStyle.BAD_DK, 14, GameStyle.PAPER, 6.0)
	sell_btn.pressed.connect(func():
		var ok := false
		if in_stash:
			ok = GameManager.sell_stash(int(selected.get("index", -1)))
		else:
			ok = GameManager.sell_weapon(int(selected.get("index", -1)))
		if ok:
			selected = {}
			refresh()
	)
	action_bar.add_child(sell_btn)

func _resolve_selected() -> Dictionary:
	if selected.is_empty():
		return {}
	var pool: String = selected.get("pool", "")
	var index := int(selected.get("index", -1))
	if pool == "stash":
		if index < 0 or index >= GameManager.stash.size():
			return {}
		return GameManager.stash[index]
	var summary: Array = GameManager.get_weapons_summary()
	if index < 0 or index >= summary.size():
		return {}
	return summary[index]

# ---------------- 货架 ----------------

func _create_offer_card(offer: Dictionary, index: int, total_count: int = 4) -> Control:
	var card_w := offer_card_w(total_count)
	var kind: String = offer.get("kind", "weapon")
	var is_potion: bool = kind == "potion"
	var is_item: bool = kind == "item"
	var def := {}
	var title: String
	var icon_path: String
	var tag: String
	var desc: String
	var chip_color: Color = GameStyle.BLUE
	var chip_text_color: Color = GameStyle.PAPER
	var edge_color: Color = GameStyle.BLUE_DK
	if is_potion:
		title = "回气丹"
		icon_path = "res://assets/art/icon_hp.png"
		tag = "丹药"
		desc = "服下立刻恢复五成气血"
		chip_color = GameStyle.GOOD
		chip_text_color = GameStyle.INK_TEXT
		edge_color = GameStyle.YELLOW_DK
	elif is_item:
		def = ItemData.get_def(offer.get("id", ""))
		var tier := int(def.get("tier", 1))
		title = def.get("name", "?")
		icon_path = def.get("icon", "")
		tag = "%s·法宝" % ItemData.tier_label(tier)
		desc = def.get("desc", "")
		chip_color = ItemData.tier_color(tier)
		chip_text_color = GameStyle.INK_TEXT
		edge_color = ItemData.tier_color(tier).darkened(0.35)
	else:
		var w_id: String = String(offer.get("id", ""))
		def = WeaponData.get_def(w_id)
		title = WeaponData.star_text(1) + " " + def.get("name", "?")
		icon_path = def.get("icon", "")
		tag = def.get("tag", "")
		# 双维羁绊进度：「剑系 1/2 · 锐金 1/2」提示离下一档还差几件，若买下能激活则金色高亮
		var wtags: Array = def.get("tags", [])
		var tag_parts: Array = []
		var will_activate := false
		for t in wtags:
			var syn: Dictionary = WeaponData.SYNERGIES.get(t, {})
			if not syn.is_empty():
				var n := GameManager.get_tag_count(t)
				var next := "MAX"
				var th_arr: Array = syn.get("thresholds", [])
				for th in th_arr:
					if n < int(th):
						next = str(th)
						if n + 1 == int(th):
							will_activate = true
						break
				tag_parts.append("%s %d/%s" % [syn.get("name", t), n, next])
		if not tag_parts.is_empty():
			tag = " · ".join(tag_parts)
		if will_activate:
			chip_color = GameStyle.YELLOW
			chip_text_color = GameStyle.INK_TEXT
			edge_color = GameStyle.YELLOW
		desc = def.get("desc", "")
		var bonus_dmg := GameManager.get_weapon_stat_bonus(w_id, 1)
		if bonus_dmg > 0.05:
			desc += "\n(当前属性额外伤害 +%d)" % int(round(bonus_dmg))

	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(card_w, 268.0)
	var inner_w: float = card_w - OFFER_PAD_X * 2.0
	var style = StyleBoxFlat.new()
	style.bg_color = GameStyle.NAVY
	style.skew = Vector2(deg_to_rad(3.0), 0)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 5
	style.border_color = edge_color
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 0
	style.shadow_offset = Vector2(5, 5)
	style.content_margin_left = OFFER_PAD_X
	style.content_margin_top = 10.0
	style.content_margin_right = OFFER_PAD_X
	style.content_margin_bottom = 10.0
	card.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 6)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var icon_box = PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(62, 62)
	icon_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 2, 0.0))
	var icon_tex = TextureRect.new()
	if ResourceLoader.exists(icon_path):
		icon_tex.texture = load(icon_path)
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.custom_minimum_size = Vector2(50, 50)
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_box.add_child(icon_tex)
	vbox.add_child(icon_box)

	var title_lbl = Label.new()
	title_lbl.text = GameStyle.wrap_cjk(title, GameStyle.display_font(), 17, inner_w)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.custom_minimum_size = Vector2(inner_w, 0)
	vbox.add_child(title_lbl)
	GameStyle.label(title_lbl, 17, GameStyle.PAPER, 0, GameStyle.INK, true)

	var tag_txt := GameStyle.wrap_cjk(" " + tag + " ", GameStyle.body_font(), 11, inner_w - 6.0)
	var tag_lbl = Label.new()
	tag_lbl.text = tag_txt
	tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 贴着字走的色签：折行宽要钉成「最宽那一行」，不钉会被容器压成一个字一行
	# （判据 LayoutCheck 在灵石阁上抓到的就是这一格：框 5×191、文案竖着排）
	tag_lbl.custom_minimum_size = Vector2(GameStyle.chip_pin_w(tag_txt, GameStyle.body_font(), 11), 0)
	tag_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag_lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tag_lbl.add_theme_stylebox_override("normal", GameStyle.chip(chip_color))
	vbox.add_child(tag_lbl)
	GameStyle.label(tag_lbl, 11, chip_text_color)

	# 描述：换行切进文本，不交给引擎折行（见 GameStyle.wrap_cjk 头注）
	var desc_lbl = Label.new()
	desc_lbl.text = GameStyle.wrap_cjk(desc, GameStyle.body_font(), 12, inner_w)
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.custom_minimum_size = Vector2(inner_w, 0)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(desc_lbl)
	GameStyle.label(desc_lbl, 12, GameStyle.PAPER_DIM)

	var sold: bool = offer.get("sold", false)
	var price: int = int(offer.get("price", 0))
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(0, 34)
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	GameStyle.button(btn, GameStyle.YELLOW, GameStyle.PAPER, 14, GameStyle.INK_TEXT, 6.0)
	btn.text = "%d 灵石" % price
	if sold:
		btn.text = "已 售 出"
		btn.disabled = true
	elif GameManager.spirit_stones < price:
		btn.disabled = true
	elif is_item and bool(def.get("unique", false)) and GameManager.has_item(offer.get("id", "")):
		btn.disabled = true
		btn.text = "已 持 有"
	elif kind == "weapon" and GameManager.slots_used() >= GameManager.max_weapon_slots() \
			and GameManager.stash.size() >= WeaponData.MAX_STASH_SLOTS:
		btn.disabled = true
		btn.text = "上阵背包已满"
	elif kind == "weapon" and GameManager.slots_used() >= GameManager.max_weapon_slots():
		btn.text = "%d 灵石 · 入背包" % price
	btn.pressed.connect(func():
		if GameManager.buy_offer(index):
			refresh()
	)
	vbox.add_child(btn)

	# 锁定开关：锁定的商品波次结束后保留到下一波
	if not sold:
		var locked: bool = offer.get("locked", false)
		var lock_btn = Button.new()
		lock_btn.custom_minimum_size = Vector2(0, 26)
		lock_btn.focus_mode = Control.FOCUS_NONE
		lock_btn.text = "已锁定 · 留到下波" if locked else "锁 定"
		GameStyle.button(lock_btn, GameStyle.YELLOW if locked else GameStyle.NAVY2,
			GameStyle.YELLOW_DK if locked else GameStyle.LINE, 12,
			GameStyle.INK_TEXT if locked else GameStyle.PAPER_DIM, 4.0)
		lock_btn.pressed.connect(func():
			GameManager.toggle_lock(index)
			refresh()
		)
		vbox.add_child(lock_btn)
	card.add_child(vbox)
	return card

func _on_reroll() -> void:
	GameManager.reroll_shop()
	refresh()

func _on_confirm() -> void:
	AudioManager.play_sfx("orb_hit", 1.0)
	visible = false
	GameManager.confirm_shop()
