extends Node

## 作者面板判据：武器页筛选与卡面三签、所有条目「点卡开详情窗 → 窗内购买」、
## 武器窗内 1/2/3 星三键、购买后 inventory_changed 联动商店陈列行刷新。
## 运行: $G --headless --path . res://tests/AuthorPanelCheck.tscn
##
## 为什么立这条（用户 2026-10-22 两轮反馈）：
##  ① 作者面板武器页原先是一整片无标签的卡，找装备只能靠肉眼扫 —— 要像图鉴一样
##     按类型/五行筛选、卡面直接印类别标签；筛选口径必须与图鉴同源（WeaponData.tags_of）。
##  ② 原先「点一下直接买」容易点错，要改成点卡先看详情、在详情窗里点购买。
##     这条也钉住「只点卡不许发货」——否则改回去时单看购买成功是测不出来的。
##  ③ 商店开着时从作者面板买东西，商店陈列行原先要等下一波才刷新（用户报的 bug），
##     现在购买成功发 inventory_changed，Main 接线到 shop.refresh(false)。
##
## 假玩家只满足 WeaponInventory 的鸭类型需求（不启真实战场，判据跑得快）。

const VIEWPORT_SIZE := Vector2i(960, 540)

var _c := TestCheck.new()
var _panel: AuthorPanel
var _shop: WaveShop
var _last_inventory_kind: String = ""

func _ready() -> void:
	get_tree().root.size = VIEWPORT_SIZE
	Engine.time_scale = 4.0
	GameManager.headless_guard_sec = 120.0

	GameManager.run_started = true
	GameManager.player = AuthorTestPlayer.new()
	add_child(GameManager.player)
	GameManager.level = 1
	GameManager.wave_number = 1
	GameManager.author_mode = true
	GameManager.shop_offers = []

	# 商店实例：验证购买后的刷新联动（与 Main.gd 同一条接线）
	_shop = load("res://scenes/ui/WaveShop.tscn").instantiate()
	add_child(_shop)
	await _settle(2)
	_shop.visible = true
	_shop.refresh(false)
	await _settle(3)

	_panel = AuthorPanel.new()
	add_child(_panel)
	_panel.inventory_changed.connect(func(kind: String) -> void:
		_last_inventory_kind = kind
		if _shop.visible and _shop.has_method("refresh"):
			_shop.refresh(false)
	)
	_panel.open()
	await _settle(3)
	_panel.switch_tab(2)
	await _settle(2)

	await _check_weapon_filters()
	await _check_weapon_tip_purchase()
	await _check_item_purchase()
	_check_pet_tip()
	await _check_shop_refresh_link()

	_c.check(_panel.visible, "全程作者面板没被误关")
	get_tree().quit(0 if _c.report("AUTHOR_PANEL_RESULT") else 1)

# ---------------- 武器页：筛选 + 卡面三签 ----------------

func _check_weapon_filters() -> void:
	_c.equals(_cards_in(_panel._weapon_box).size(), _weapon_total(),
		"武器页全量卡数 == DEFS 武器总数（%d）" % _weapon_total())
	_c.check(_group_headers() >= 5, "全部视图按五行分组（%d 组）" % _group_headers())

	# 卡面三签：与图鉴同源（攻击方式 + 器类/五行）
	var first := _cards_in(_panel._weapon_box)[0]
	var wid := String(first.get_meta("wid", ""))
	_c.check(not wid.is_empty(), "武器卡登记了 wid")
	var def := WeaponData.get_def(wid)
	_c.check(_chip_texts(first).has(WeaponData.behavior_label(def)),
		"武器卡不点也印出攻击方式签")
	for t in def.get("tags", []):
		var nm := String(WeaponData.SYNERGIES.get(String(t), {}).get("name", String(t)))
		_c.check(_chip_texts(first).has(nm), "武器卡印出「%s」类别签" % nm)

	# 类型筛选
	var sword_chip: Label = _panel._filter_chips.get("sword")
	_c.check(sword_chip != null and is_instance_valid(sword_chip), "筛选条有「剑系」chip")
	if sword_chip == null:
		return
	await _tap(sword_chip)
	_c.equals(_cards_in(_panel._weapon_box).size(), _tag_total("sword"),
		"点剑系 chip：只剩剑系 %d 把" % _tag_total("sword"))
	_c.check(_is_chip_selected(sword_chip), "剑系 chip 选中态高亮")

	# 类型 × 元素取交集
	var fire_chip: Label = _panel._filter_chips.get("fire")
	_c.check(fire_chip != null and is_instance_valid(fire_chip), "筛选条有「火系」chip")
	if fire_chip != null:
		await _tap(fire_chip)
		var want := _intersect_total("sword", "fire")
		_c.equals(_cards_in(_panel._weapon_box).size(), want,
			"剑系 + 火系取交集 %d 把" % want)
		_c.check(want > 0 and want < _tag_total("sword"), "交集确实收窄")
		_c.check(_header_text().contains("剑系") and _header_text().contains("火系"),
			"组标题并列两条筛选（%s）" % _header_text())

	# 清筛选回全量
	var all_cls: Label = _panel._filter_chips.get("all_class")
	var all_elem: Label = _panel._filter_chips.get("all_element")
	if all_cls != null:
		await _tap(all_cls)
	if all_elem != null:
		await _tap(all_elem)
	_c.equals(_cards_in(_panel._weapon_box).size(), _weapon_total(), "清筛选回全量 %d 把" % _weapon_total())

# ---------------- 武器详情窗：三颗星级购买键 ----------------

func _check_weapon_tip_purchase() -> void:
	var card := _find_card(_panel._weapon_box, "wid", "qingyun_sword")
	_c.check(card != null, "找得到长剑卡")
	if card == null:
		return
	var before := GameManager.slots_used()
	await _tap(card)
	var tip := DetailTip.live(_panel)
	_c.check(tip != null, "点武器卡弹出详情窗")
	if tip == null:
		return
	_c.equals(String(tip.payload.get("title", "")), "长剑", "详情窗标题是长剑")
	var acts := _action_texts(tip)
	_c.check(acts.has("买 1 星") and acts.has("买 2 星") and acts.has("买 3 星"),
		"详情窗有 1 / 2 / 3 星三颗购买键（实得 %s）" % str(acts))
	_c.equals(GameManager.slots_used(), before, "只点卡不直接购买")
	await _press_action(tip, "买 2 星")
	await _settle(3)
	_c.equals(GameManager.slots_used(), before + 1, "点「买 2 星」后上阵 +1")
	_c.equals(_last_star(), 2, "到手的是 2 星")
	_c.check(DetailTip.live(_panel) == null, "购买后详情窗收起")
	_c.equals(_last_inventory_kind, "weapon", "购买成功发 inventory_changed(weapon)")

# ---------------- 道具 / 灵兽详情窗 ----------------

func _check_item_purchase() -> void:
	_panel.switch_tab(3)
	await _settle(2)
	var card := _find_card(_panel._item_grid, "iid", "jubaopen")
	_c.check(card != null, "找得到储蓄罐卡")
	if card == null:
		return
	var before := GameManager.items.size()
	await _tap(card)
	var tip := DetailTip.live(_panel)
	_c.check(tip != null, "点道具卡弹出详情窗")
	if tip == null:
		return
	_c.equals(GameManager.items.size(), before, "只点道具卡不直接购买")
	_c.check(_action_texts(tip).has("免费获得"), "道具详情窗有「免费获得」键")
	await _press_action(tip, "免费获得")
	await _settle(2)
	_c.equals(GameManager.items.size(), before + 1, "窗内购买后道具 +1")

func _check_pet_tip() -> void:
	var card := _find_card(_panel._pet_grid, "pid", "yanhu")
	_c.check(card != null, "找得到焰灵狐卡")
	if card == null:
		return
	# 灵兽区在道具页底部，滚出可视区外点不到（push_input 落在窗外）——直接走同一个入口
	_panel._open_pet_tip("yanhu", card)
	await _settle(2)
	var tip := DetailTip.live(_panel)
	_c.check(tip != null, "灵兽详情窗能打开")
	if tip != null:
		_c.check(_action_texts(tip).has("免费获得"), "灵兽详情窗有「免费获得」键")
		DetailTip.close_all(_panel)
		await _settle(2)

# ---------------- 商店刷新联动 ----------------

func _check_shop_refresh_link() -> void:
	_panel.switch_tab(2)
	await _settle(2)
	var before := _first_slot_id()
	var ok := AuthorMode.grant(GameManager, "weapon", "qingyun_sword", 1)
	_c.check(ok, "作者模式直购成功")
	_panel.inventory_changed.emit("weapon")
	await _settle(3)
	var after := _first_slot_id()
	_c.check(before != 0 and after != 0 and before != after,
		"商店开着时购买 → 陈列行立即重建（槽位实例换新）")

	# 商店隐藏时不该被无谓重建
	_shop.visible = false
	var hidden_before := _first_slot_id()
	_panel.inventory_changed.emit("weapon")
	await _settle(2)
	_c.equals(_first_slot_id(), hidden_before, "商店未打开时不重建陈列行")

func _first_slot_id() -> int:
	if _shop.owned_container.get_child_count() == 0:
		return 0
	return _shop.owned_container.get_child(0).get_instance_id()

# ---------------- 取数 ----------------

func _weapon_total() -> int:
	var n := 0
	for wid in WeaponData.DEFS.keys():
		if WeaponData.DEFS[wid].has("tags"):
			n += 1
	return n

func _tag_total(tag: String) -> int:
	var n := 0
	for wid in WeaponData.DEFS.keys():
		if tag in WeaponData.tags_of(String(wid)):
			n += 1
	return n

func _intersect_total(a: String, b: String) -> int:
	var n := 0
	for wid in WeaponData.DEFS.keys():
		var tags := WeaponData.tags_of(String(wid))
		if a in tags and b in tags:
			n += 1
	return n

func _is_chip_selected(chip: Control) -> bool:
	var sb := chip.get_theme_stylebox("normal") as StyleBoxFlat
	return sb != null and sb.bg_color == GameStyle.GOLD

func _last_star() -> int:
	var s := GameManager.get_weapons_summary()
	if s.is_empty():
		return -1
	return int(s[s.size() - 1].get("star", -1))

func _cards_in(root: Node) -> Array[Control]:
	var out: Array[Control] = []
	_collect(root, out)
	return out

func _collect(node: Node, out: Array[Control]) -> void:
	if node is Control and node.has_meta("tip_title"):
		out.append(node as Control)
	for ch in node.get_children():
		_collect(ch, out)

func _find_card(root: Node, meta_key: String, id: String) -> Control:
	for c in _cards_in(root):
		if String(c.get_meta(meta_key, "")) == id:
			return c
	return null

func _group_headers() -> int:
	var n := 0
	for lbl in _labels_of(_panel._weapon_box):
		if String(lbl.text).begins_with("──"):
			n += 1
	return n

func _header_text() -> String:
	for lbl in _labels_of(_panel._weapon_box):
		if String(lbl.text).begins_with("──"):
			return String(lbl.text)
	return ""

func _labels_of(root: Node) -> Array[Label]:
	var out: Array[Label] = []
	_walk_labels(root, out)
	return out

func _walk_labels(node: Node, out: Array[Label]) -> void:
	if node is Label:
		out.append(node as Label)
	for ch in node.get_children():
		_walk_labels(ch, out)

func _chip_texts(card: Control) -> PackedStringArray:
	var out := PackedStringArray()
	for lbl in _labels_of(card):
		if lbl.get_theme_stylebox("normal") != null:
			out.append(String(lbl.text).strip_edges())
	return out

func _action_texts(tip: DetailTip) -> Array[String]:
	var out: Array[String] = []
	for btn in _buttons_of(tip):
		out.append(String(btn.text))
	return out

func _press_action(tip: DetailTip, text: String) -> void:
	for btn in _buttons_of(tip):
		if String(btn.text) == text:
			btn.pressed.emit()
			return
	_c.fail("找不到按钮「%s」" % text)

func _buttons_of(root: Node) -> Array[Button]:
	var out: Array[Button] = []
	_walk_buttons(root, out)
	return out

func _walk_buttons(node: Node, out: Array[Button]) -> void:
	if node is Button:
		out.append(node as Button)
	for ch in node.get_children():
		_walk_buttons(ch, out)

# ---------------- 点按 ----------------

## 真发一次按下+抬起（同一坐标）：GameStyle.tap 的划动容差口径下原地点必触发
func _tap(ctrl: Control) -> void:
	var p := ctrl.get_global_rect().get_center()
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.position = p
		ev.global_position = p
		ev.pressed = pressed
		get_tree().root.push_input(ev)
	await _settle(2)

func _settle(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame
