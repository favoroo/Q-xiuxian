class_name AuthorShopView
extends VBoxContainer

## 作者模式专用的嵌入式商店视图
##
## 将真实商店界面的货架购买、锁定、重掷与下方的装备/纳戒背包/道具/灵兽陈列行
## 完整搬进作者模式面板，供作者模式下实时管理、合成、出售装备，以及验证商店界面的实际效果。

signal state_changed(kind: String)
signal inventory_changed(kind: String)
signal manual_requested(tag: String)

var selected: Dictionary = {}
var drag_ctl: ShopDragDrop = null
var _author_panel: Control = null
var _screen: Vector2 = Vector2(960, 540)

# 顶栏控件
var stones_label: Label = null
var _hp_chip: ShopHpChip = null
var reroll_btn: Button = null
var _synergy_box: HBoxContainer = null
var _info_bar: HBoxContainer = null

# 货架区控件
var offers_scroll: ScrollContainer = null
var offers_container: HBoxContainer = null

# 陈列行控件
var owned_scroll: ScrollContainer = null
var owned_container: HBoxContainer = null

func _init(author_panel: Control) -> void:
	_author_panel = author_panel

func get_tip_host() -> Control:
	return self

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)

	drag_ctl = ShopDragDrop.new(self)
	drag_ctl.name = "ShopDragDrop"
	add_child(drag_ctl)

	_build_ui()

func _build_ui() -> void:
	# 1. 顶栏：金币、生命徽记、重掷按钮、说明按钮
	var top_row := HBoxContainer.new()
	top_row.name = "TopRow"
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_theme_constant_override("separation", 10)
	add_child(top_row)

	# 金币读数徽记
	var stones_box := PanelContainer.new()
	stones_box.name = "StonesBox"
	stones_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stones_box.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, GameStyle.GOLD, 1, 0.0))
	var sm := MarginContainer.new()
	sm.add_theme_constant_override("margin_left", 10)
	sm.add_theme_constant_override("margin_right", 10)
	sm.add_theme_constant_override("margin_top", 3)
	sm.add_theme_constant_override("margin_bottom", 3)
	var stones_h := HBoxContainer.new()
	stones_h.add_theme_constant_override("separation", 6)
	var icon_gold := GameStyle.icon_texture_rect("res://assets/art/icon_gold.png", Vector2(16, 16))
	stones_h.add_child(icon_gold)
	stones_label = Label.new()
	stones_label.name = "StonesLabel"
	stones_label.text = "0 金币"
	GameStyle.label(stones_label, 14, GameStyle.INK_TEXT)
	stones_h.add_child(stones_label)
	sm.add_child(stones_h)
	stones_box.add_child(sm)
	top_row.add_child(stones_box)

	# 生命徽记
	_hp_chip = ShopHpChip.new(self)
	top_row.add_child(_hp_chip)

	# 弹性空白，把重掷与帮助推到右侧
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(spacer)

	# 重掷按钮
	reroll_btn = Button.new()
	reroll_btn.name = "RerollButton"
	reroll_btn.custom_minimum_size = Vector2(130, 28)
	reroll_btn.focus_mode = Control.FOCUS_NONE
	reroll_btn.text = "重掷货架"
	GameStyle.button(reroll_btn, GameStyle.NAVY2, GameStyle.LINE, 12, GameStyle.PAPER_DIM)
	reroll_btn.pressed.connect(_on_reroll)
	top_row.add_child(reroll_btn)

	# 规则说明按钮
	var help_btn := Button.new()
	help_btn.name = "HelpButton"
	help_btn.text = "怎么用？"
	help_btn.custom_minimum_size = Vector2(76, 28)
	help_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(help_btn, GameStyle.NAVY2, GameStyle.LINE, 12, GameStyle.PAPER_DIM, 4.0)
	help_btn.pressed.connect(_open_usage_tip)
	top_row.add_child(help_btn)

	# 2. 流派羁绊行
	_info_bar = HBoxContainer.new()
	_info_bar.name = "InfoBar"
	_info_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_synergy_box = HBoxContainer.new()
	_synergy_box.name = "SynergyBox"
	_synergy_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_synergy_box.add_theme_constant_override("separation", 6)
	_info_bar.add_child(_synergy_box)
	add_child(_info_bar)

	# 3. 货架滚动区域（横向滑动）
	offers_scroll = ScrollContainer.new()
	offers_scroll.name = "OffersScroll"
	offers_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	offers_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	offers_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	offers_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	GameStyle.scrollable(offers_scroll)

	var offers_pad := MarginContainer.new()
	offers_pad.add_theme_constant_override("margin_left", int(WaveShop.OFFER_PAD_X))
	offers_pad.add_theme_constant_override("margin_right", int(WaveShop.OFFER_PAD_X))
	offers_pad.add_theme_constant_override("margin_top", 4)
	offers_pad.add_theme_constant_override("margin_bottom", 4)
	offers_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	offers_pad.size_flags_vertical = Control.SIZE_EXPAND_FILL

	offers_container = HBoxContainer.new()
	offers_container.name = "OffersContainer"
	offers_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	offers_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	offers_container.alignment = BoxContainer.ALIGNMENT_CENTER
	offers_pad.add_child(offers_container)
	offers_scroll.add_child(offers_pad)
	add_child(offers_scroll)

	# 分割线
	var sep := HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = GameStyle.LINE
	line.thickness = 1
	sep.add_theme_stylebox_override("separator", line)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sep)

	# 4. 陈列行滚动区域（上阵 + 背包 + 灵兽 + 道具）
	owned_scroll = ScrollContainer.new()
	owned_scroll.name = "OwnedScroll"
	owned_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	owned_scroll.custom_minimum_size = Vector2(0, WaveShop.INV_SLOT + 14.0)
	owned_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	owned_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	GameStyle.scrollable(owned_scroll)

	owned_container = HBoxContainer.new()
	owned_container.name = "OwnedContainer"
	owned_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	owned_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	owned_container.add_theme_constant_override("separation", int(WaveShop.INV_GAP))
	owned_scroll.add_child(owned_container)
	add_child(owned_scroll)

	# 滑动手势
	GameStyle.swipeable(offers_scroll)
	GameStyle.swipeable(owned_scroll)

func drag_register(slot: Control, src: Dictionary) -> void:
	if drag_ctl != null:
		drag_ctl.register_slot(slot, src)

## 外部统一刷新接口：重建货架与陈列行
func refresh(animate: bool = false) -> void:
	var vp := get_viewport_rect().size
	if vp.x > 0.0 and vp.y > 0.0:
		_screen = vp

	# 顶栏读数
	if stones_label != null:
		stones_label.text = "%d 金币" % GameManager.spirit_stones
	if _hp_chip != null:
		var cur_hp := 0.0
		var max_hp := 0.0
		if GameManager.has_method("get_player_stat_dict"):
			var hp_stats: Dictionary = GameManager.get_player_stat_dict()
			cur_hp = float(hp_stats.get("current_hp", 0.0))
			max_hp = float(hp_stats.get("max_hp", 0.0))
		if cur_hp <= 0.0 and max_hp <= 0.0 and GameManager.player != null and is_instance_valid(GameManager.player):
			var ch: Variant = GameManager.player.get("current_health")
			var mh: Variant = GameManager.player.get("max_health")
			if ch != null and mh != null:
				cur_hp = float(ch)
				max_hp = float(mh)
		if cur_hp <= 0.0 and max_hp <= 0.0:
			cur_hp = 100.0
			max_hp = 100.0
		_hp_chip.set_value(cur_hp, max_hp)

	# 重掷按钮状态
	_update_reroll_button()

	# 羁绊总览
	_refresh_synergy_bar()

	# 货架刷新
	_refresh_offers(animate)

	# 陈列行刷新
	_refresh_inventory()

func refresh_inventory() -> void:
	selected = {}
	refresh(false)

func refresh_readouts() -> void:
	refresh(false)

func _update_reroll_button() -> void:
	if reroll_btn == null:
		return
	if GameManager.reroll_free_left > 0:
		reroll_btn.text = "免费重掷 (剩 %d 次)" % GameManager.reroll_free_left
		reroll_btn.disabled = false
	else:
		reroll_btn.text = "重掷货架 (%d 金币)" % GameManager.reroll_cost
		reroll_btn.disabled = GameManager.spirit_stones < GameManager.reroll_cost

func _refresh_synergy_bar() -> void:
	if _synergy_box == null:
		return
	for child in _synergy_box.get_children():
		child.queue_free()
	for tag in GameManager.active_synergies.keys():
		if not WeaponData.SYNERGIES.has(tag):
			continue
		var chip_lbl: Label = SynergyUI.create_chip(tag, 11, func(c: Control) -> void:
			_open_synergy_tip(tag, c)
		)
		_synergy_box.add_child(chip_lbl)

func _open_synergy_tip(tag: String, anchor: Control) -> void:
	SynergyUI.open_tip(self, anchor, tag, "", "", [], [
		{"text": "查看该流派武器", "callback": func() -> void: manual_requested.emit(tag)},
	])

func _refresh_offers(animate: bool) -> void:
	if offers_container == null:
		return
	# 货架若是空的（例如战斗中途打开作者模式），自动生成当前波次货架
	if GameManager.shop_offers.is_empty():
		ShopSystem.roll_shop(GameManager)

	for child in offers_container.get_children():
		child.queue_free()

	var offers: Array = GameManager.shop_offers
	var count := offers.size()
	offers_container.add_theme_constant_override("separation", WaveShop.offer_separation(_screen))

	var forecast := StatForecast.open()
	for i in range(count):
		var card: Control = ShopOfferCardFactory.create_card(self, offers[i], i, count, forecast)
		offers_container.add_child(card)
		if animate:
			GameStyle.pop_in(card, float(i) * 0.04)

func _refresh_inventory() -> void:
	if owned_container == null:
		return
	if selected.is_empty():
		DetailTip.close_all(self)

	var keep_x: float = owned_scroll.scroll_horizontal
	for child in owned_container.get_children():
		child.queue_free()

	var summary: Array = GameManager.get_weapons_summary()
	var max_slots: int = GameManager.max_weapon_slots()
	var eq_count: int = maxi(max_slots, summary.size())
	var slot_capped: bool = max_slots < WeaponData.MAX_SLOTS

	var empty_budget: int = clampi(10 - eq_count - GameManager.stash.size(), 0, 3)
	var free_tiles: int = mini(WeaponData.MAX_STASH_SLOTS - GameManager.stash.size(), empty_budget)

	var n_tile: int = eq_count + GameManager.stash.size() + free_tiles + GameManager.items.size() + GameManager.pets.size()
	var n_chip: int = (2 if slot_capped else 1) + (1 if not GameManager.items.is_empty() else 0) + (1 if not GameManager.pets.is_empty() else 0)
	var tile := WaveShop.inv_slot_for(WaveShop.panel_inner_w(_screen), n_tile, n_chip)

	if slot_capped:
		owned_container.add_child(ShopInventoryRow.create_equipped_cap_chip(summary.size(), max_slots))
	for i in range(eq_count):
		if i < summary.size():
			owned_container.add_child(ShopInventoryRow.create_inv_slot(self, summary[i], i, "equipped", tile))
		else:
			owned_container.add_child(ShopInventoryRow.create_empty_equipped_slot(self, i, tile))
	owned_container.add_child(ShopInventoryRow.create_stash_divider(self))
	for i in range(GameManager.stash.size()):
		owned_container.add_child(ShopInventoryRow.create_inv_slot(self, GameManager.stash[i], i, "stash", tile))
	for i in range(free_tiles):
		owned_container.add_child(ShopInventoryRow.create_empty_stash_slot(self, tile))

	# 灵兽
	if not GameManager.pets.is_empty():
		owned_container.add_child(ShopInventoryRow.create_pets_divider())
		for pet_id in GameManager.pets:
			owned_container.add_child(ShopInventoryRow.create_pet_chip(self, pet_id, tile))

	# 道具
	if not GameManager.items.is_empty():
		owned_container.add_child(ShopInventoryRow.create_items_divider())
		for item_id in GameManager.items:
			owned_container.add_child(ShopInventoryRow.create_item_chip(self, item_id, tile))

	GameStyle.swipeable(owned_container)
	if keep_x > 0.0:
		_keep_row_scroll(keep_x)

func _keep_row_scroll(x: float) -> void:
	if x <= 0.0 or owned_scroll == null:
		return
	var sc := owned_scroll
	get_tree().process_frame.connect(func():
		if sc == null or not is_instance_valid(sc):
			return
		get_tree().process_frame.connect(func():
			if sc != null and is_instance_valid(sc):
				sc.scroll_horizontal = int(round(x))
		, CONNECT_ONE_SHOT)
	, CONNECT_ONE_SHOT)

func _on_reroll() -> void:
	if ShopSystem.reroll_shop(GameManager):
		refresh(true)
		state_changed.emit("stones")

func _open_usage_tip() -> void:
	var help_btn := get_node_or_null("TopRow/HelpButton") as Control
	var anchor: Control = help_btn if help_btn != null else self
	var max_slots: int = GameManager.max_weapon_slots()
	var slot_txt: String = "%d 件（本角色上限）" % max_slots if max_slots < WeaponData.MAX_SLOTS else "%d 件" % max_slots
	var rows: Array = [
		["武器槽", slot_txt, GameStyle.JADE if max_slots < WeaponData.MAX_SLOTS else GameStyle.PAPER],
		["背包格数", "%d 格" % WeaponData.MAX_STASH_SLOTS, GameStyle.PAPER],
		["货架格数", "%d 格" % GameManager.shop_offers.size(), GameStyle.PAPER],
	]
	var notes: Array[String] = [
		"先点中一件武器，才能升星、换装或出售。",
		"格子边框：外框色＝五行，黄框＝可合成，白框＝选中；底部橙红边＝受【元素伤害】加成。",
		"道具与灵兽买错可退：点徽记开详情，【出售】半价回收。",
		"拖动换装：拖到上阵格＝装备，拖到武器上＝替换，拖到背包＝卸下。",
		"三合一：三把同名同星合成升一星（最高 ★4）。",
		"「锁定」：这格留到下回合，重掷不换。",
		"「重掷」：换一批候选；每回合有免费次数，用完扣金币。",
	]
	DetailTip.show_over(self, anchor, {
		"title": "商店与背包使用指南",
		"chip": "操作规则",
		"chip_color": GameStyle.GOLD_DK,
		"rows": rows,
		"notes": notes,
		"foot": "作者模式：完整商店体验，关闭面板返回游戏。",
	})
