class_name WaveShop
extends Control

## 波间灵石阁：购买法器/回气丹、重掷货架；
## 上阵 + 背包统一点选后操作：三合一合成 / 上阵卸下 / 出售换灵石

@onready var stones_label: Label = $CenterContainer/Panel/MarginContainer/VBox/TopBar/StonesChip/StonesLabel
@onready var wave_label: Label = $CenterContainer/Panel/MarginContainer/VBox/TopBar/WaveLabel
@onready var offers_container: HBoxContainer = $CenterContainer/Panel/MarginContainer/VBox/OffersContainer
@onready var owned_container: HBoxContainer = $CenterContainer/Panel/MarginContainer/VBox/OwnedContainer
@onready var action_bar: HBoxContainer = $CenterContainer/Panel/MarginContainer/VBox/ActionBar
@onready var reroll_btn: Button = $CenterContainer/Panel/MarginContainer/VBox/BottomBar/RerollButton
@onready var confirm_btn: Button = $CenterContainer/Panel/MarginContainer/VBox/BottomBar/ConfirmButton

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
	# 羁绊总览行：插在顶栏之下
	_synergy_bar = HBoxContainer.new()
	_synergy_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_synergy_bar.add_theme_constant_override("separation", 10)
	var vbox: VBoxContainer = $CenterContainer/Panel/MarginContainer/VBox
	vbox.add_child(_synergy_bar)
	vbox.move_child(_synergy_bar, 1)

## 羁绊总览：激活的流派显示金色等级徽记，未激活显示灰色进度
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
		if lv > 0:
			chip_lbl.text = " %s Lv.%d " % [info.get("name", tag), lv]
			chip_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.YELLOW))
			GameStyle.label(chip_lbl, 12, GameStyle.INK_TEXT)
		else:
			chip_lbl.text = " %s %d/%s " % [info.get("name", tag), n, next]
			chip_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.NAVY2))
			GameStyle.label(chip_lbl, 12, GameStyle.PAPER_DIM)
		chip_lbl.tooltip_text = info.get("desc", "")
		_synergy_bar.add_child(chip_lbl)
		any = true
	_synergy_bar.visible = any

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
	reroll_btn.text = "重掷货架 (%d 灵石)" % GameManager.reroll_cost
	_refresh_synergy_bar()

	for child in offers_container.get_children():
		child.queue_free()
	var offers: Array = GameManager.shop_offers
	for i in range(offers.size()):
		var c := _create_offer_card(offers[i], i)
		offers_container.add_child(c)
		c.pivot_offset = Vector2(98.0, 134.0)
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
			AudioManager.play_sfx("orb_hit", 0.9)
			GameManager.merge_weapon(id, star, keep)
			selected = {}
			refresh()
		)
		action_bar.add_child(merge_btn)

	var move_btn = Button.new()
	move_btn.custom_minimum_size = Vector2(108, 38)
	move_btn.focus_mode = Control.FOCUS_NONE
	if in_stash:
		move_btn.text = "上 阵"
		move_btn.disabled = GameManager.slots_used() >= WeaponData.MAX_SLOTS
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

func _create_offer_card(offer: Dictionary, index: int) -> Control:
	var is_potion: bool = offer.get("kind") == "potion"
	var def := {}
	var title: String
	var icon_path: String
	var tag: String
	var desc: String
	if is_potion:
		title = "回气丹"
		icon_path = "res://assets/art/icon_hp.png"
		tag = "丹药"
		desc = "服下立刻恢复五成气血"
	else:
		def = WeaponData.get_def(offer.get("id", ""))
		title = WeaponData.star_text(1) + " " + def.get("name", "?")
		icon_path = def.get("icon", "")
		tag = def.get("tag", "")
		# 羁绊进度：「符箓 3/4」提示离下一档还差几件
		var wtags: Array = def.get("tags", [])
		if not wtags.is_empty():
			var n := GameManager.get_tag_count(wtags[0])
			var next := "MAX"
			for th in WeaponData.SYNERGIES.get(wtags[0], {}).get("thresholds", []):
				if n < int(th):
					next = str(th)
					break
			tag = "%s %d/%s" % [tag, n, next]
		desc = def.get("desc", "")

	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(196.0, 268.0)
	var style = StyleBoxFlat.new()
	style.bg_color = GameStyle.NAVY
	style.skew = Vector2(deg_to_rad(3.0), 0)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 5
	style.border_color = GameStyle.YELLOW_DK if is_potion else GameStyle.BLUE_DK
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 0
	style.shadow_offset = Vector2(5, 5)
	style.content_margin_left = 12.0
	style.content_margin_top = 12.0
	style.content_margin_right = 12.0
	style.content_margin_bottom = 12.0
	card.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 8)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var icon_box = PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(72, 72)
	icon_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 2, 0.0))
	var icon_tex = TextureRect.new()
	if ResourceLoader.exists(icon_path):
		icon_tex.texture = load(icon_path)
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.custom_minimum_size = Vector2(58, 58)
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_box.add_child(icon_tex)
	vbox.add_child(icon_box)

	var title_lbl = Label.new()
	title_lbl.text = title
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_lbl)
	GameStyle.label(title_lbl, 17, GameStyle.PAPER, 0, GameStyle.INK, true)

	var tag_lbl = Label.new()
	tag_lbl.text = " " + tag + " "
	tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag_lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tag_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.BLUE if not is_potion else GameStyle.GOOD))
	vbox.add_child(tag_lbl)
	GameStyle.label(tag_lbl, 11, GameStyle.PAPER if not is_potion else GameStyle.INK_TEXT)

	var desc_lbl = Label.new()
	desc_lbl.text = desc
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
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
	elif not is_potion and GameManager.slots_used() >= WeaponData.MAX_SLOTS \
			and GameManager.stash.size() >= WeaponData.MAX_STASH_SLOTS:
		btn.disabled = true
		btn.text = "上阵背包已满"
	elif not is_potion and GameManager.slots_used() >= WeaponData.MAX_SLOTS:
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
