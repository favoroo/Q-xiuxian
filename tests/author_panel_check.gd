extends Node

## 作者面板判据：武器页筛选与卡面三签、所有条目「点卡开详情窗 → 窗内购买」、
## 武器窗内 1 ~ MAX_STAR 全档购买键（★4 极境含在内）、购买后 inventory_changed 联动商店陈列行刷新、
## 金币/等级/生命改动后 state_changed 联动商店读数即时刷新。
## 运行: $G --headless --path . res://tests/AuthorPanelCheck.tscn
##
## 为什么立这条（用户 2026-10-22 三轮反馈）：
##  ① 作者面板武器页原先是一整片无标签的卡，找装备只能靠肉眼扫 —— 要像图鉴一样
##     按类型/五行筛选、卡面直接印类别标签；筛选口径必须与图鉴同源（WeaponData.tags_of）。
##  ② 原先「点一下直接买」容易点错，要改成点卡先看详情、在详情窗里点购买。
##     这条也钉住「只点卡不许发货」——否则改回去时单看购买成功是测不出来的。
##  ③ 商店开着时从作者面板买东西，商店陈列行原先要等下一波才刷新（用户报的 bug），
##     现在购买成功发 inventory_changed，Main 接线到 shop.refresh(false)。
##  ④ 商店里点「金币 +10 000」原先要出战后才生效（用户 2026-10-22 报）：金币只是数据，
##     商店顶栏/价格键/重掷键都是开店时抄的旧账 —— 现在发 state_changed("stones")，
##     Main 转 shop.refresh_readouts() 当场重画；补血/调等级同理。
##
## 假玩家只满足 WeaponInventory 的鸭类型需求（不启真实战场，判据跑得快）。

const VIEWPORT_SIZE := Vector2i(960, 540)

var _c := TestCheck.new()
var _panel: AuthorPanel
var _shop: WaveShop
var _last_inventory_kind: String = ""
var _last_state_kind: String = ""

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
	# Main.gd 的 state_changed 接线（判据里等价复刻：按 kind 调商店对应刷新入口）
	_panel.state_changed.connect(func(kind: String) -> void:
		_last_state_kind = kind
		if not _shop.visible:
			return
		match kind:
			"stones", "hp":
				_shop.refresh_readouts()
	)
	_panel.open()
	await _settle(3)
	await _check_state_page_jump_wave()
	_panel.switch_tab(2)
	await _settle(2)

	await _check_weapon_filters()
	await _check_weapon_tip_purchase()
	await _check_item_purchase()
	_check_pet_tip()
	await _check_shop_state_sync()
	await _check_shop_refresh_link()
	await _check_embedded_shop_tab()

	_c.check(_panel.visible, "全程作者面板没被误关")
	get_tree().quit(0 if _c.report("AUTHOR_PANEL_RESULT") else 1)

# ---------------- 状态页：跳关控制与预设 ----------------

func _check_state_page_jump_wave() -> void:
	_panel.switch_tab(0)
	await _settle(2)
	var all_btns: Array[Button] = _buttons_of(_panel)
	var btn_texts: Array[String] = []
	for b in all_btns:
		btn_texts.append(String(b.text))

	# 1. 验证相对跳关按钮（含连跳 5 关、10 关）
	var expected_rel_btns := ["－ 10 波", "－ 5 波", "－ 1 波", "＋ 1 波", "＋ 5 波", "＋ 10 波"]
	for txt in expected_rel_btns:
		_c.check(btn_texts.has(txt), "状态页包含相对跳关按钮「%s」" % txt)

	# 2. 验证目标预设按钮（W1 ~ W50 关键波次）
	var expected_preset_btns := ["W1", "W5", "W10", "W15", "W20", "W25", "W30", "W35", "W40", "W50"]
	for txt in expected_preset_btns:
		_c.check(btn_texts.has(txt), "状态页包含定点跳关预设按钮「%s」" % txt)

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

# ---------------- 武器详情窗：全档星级购买键 ----------------

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
	# 键数跟着 WeaponData.MAX_STAR 走：升 ★4 那批（2026-10-24）就是靠这条钉住
	# 「面板上买不到最高档」——原先写死三颗键，加档后作者模式永远拿不到 ★4。
	var want_keys: Array[String] = []
	for s in range(1, WeaponData.MAX_STAR + 1):
		want_keys.append("买 %d 星" % s)
	var missing: Array[String] = []
	for k in want_keys:
		if not acts.has(k):
			missing.append(k)
	_c.check(missing.is_empty(),
		"详情窗有 1 ~ %d 星全部购买键（缺 %s / 实得 %s）" % [WeaponData.MAX_STAR, str(missing), str(acts)])
	var buy_keys: Array[String] = []
	for k in acts:
		if k.begins_with("买 "):
			buy_keys.append(k)
	_c.equals(buy_keys.size(), WeaponData.MAX_STAR, "购买键数 == 最高星级（不多出废键）")
	# 四颗键并排不能把卡片撑宽：DetailTip 卡宽钉在 306（720 窄屏上的安全宽），
	# 按钮最小宽 = 文字宽 + 内边距，键数再涨一颗就会顶破 —— 那时必须改两行摆而不是加宽卡。
	var card_w := tip.card_rect().size.x
	_c.check(card_w <= DetailTip.CARD_W + 1.0,
		"%d 颗购买键并排不撑宽详情卡（卡宽 %.1f ≤ %.1f）" % [buy_keys.size(), card_w, DetailTip.CARD_W])
	_c.equals(GameManager.slots_used(), before, "只点卡不直接购买")
	await _press_action(tip, "买 2 星")
	await _settle(3)
	_c.equals(GameManager.slots_used(), before + 1, "点「买 2 星」后上阵 +1")
	_c.equals(_last_star(), 2, "到手的是 2 星")
	_c.check(DetailTip.live(_panel) != null, "购买后详情窗不消失（支持连点批量购买）")
	_c.equals(_last_inventory_kind, "weapon", "购买成功发 inventory_changed(weapon)")

	# 在同一详情窗内直接连买最高档（★4）：不需要重新点卡开窗
	var before4 := GameManager.slots_used()
	await _press_action(tip, "买 %d 星" % WeaponData.MAX_STAR)
	await _settle(3)
	_c.equals(GameManager.slots_used(), before4 + 1, "同一窗内连点「买 %d 星」后上阵 +1" % WeaponData.MAX_STAR)
	_c.equals(_last_star(), WeaponData.MAX_STAR, "到手的是最高星级 ★%d" % WeaponData.MAX_STAR)
	_c.check(DetailTip.live(_panel) != null, "连买多把后详情窗仍保持打开")

	# 点卡片外空白处（屏幕边缘）才会收起
	var blank_p := Vector2(10.0, 10.0)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.position = blank_p
		ev.global_position = blank_p
		ev.pressed = pressed
		get_tree().root.push_input(ev)
	await _settle(3)
	_c.check(DetailTip.live(_panel) == null, "点空白处后详情窗收起")

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

# ---------------- 金币/生命即时联动 ----------------

## 用户 2026-10-22：在商店界面点作者面板「金币 +10 000」，要出战后才加上来。
## 根因：金币只是数据，商店顶栏/价格键/重掷键都是开店时抄的旧账；_add_stones 只发了
## stats_updated（只有战斗 HUD 在听）。这里钉住 state_changed("stones") 发出、
## 且走一遍 Main 的等价接线后商店读数当场变。
func _check_shop_state_sync() -> void:
	_panel.switch_tab(0)
	await _settle(2)
	# 摆一格买不起的货：价格键应显示「差 N」并置灰，加钱后当场变回可买（用户报的正是这一屏）
	GameManager.spirit_stones = 0
	GameManager.shop_offers = [{"kind": "weapon", "id": "qingyun_sword", "price": 99999,
		"sold": false, "locked": false}]
	_shop.refresh(false)
	await _settle(3)
	var price_btn := _find_price_btn()
	_c.check(price_btn != null and price_btn.disabled, "钱不够时价格键置灰")
	if price_btn != null:
		_c.check(price_btn.text.contains("差"), "灰键写明差额（%s）" % price_btn.text)
	var stones_before := GameManager.spirit_stones
	_panel._add_stones(100000)
	await _settle(3)
	_c.equals(_last_state_kind, "stones", "加金币后发 state_changed(stones)")
	_c.equals(GameManager.spirit_stones, stones_before + 100000, "金币当场入账 +100000")
	_c.equals(_shop.stones_label.text, "金币 %d" % GameManager.spirit_stones,
		"商店顶栏金币当场刷新（%s）" % _shop.stones_label.text)
	var price_after := _find_price_btn()
	_c.check(price_after != null and not price_after.disabled,
		"加钱后价格键当场解除置灰（%s）" % (price_after.text if price_after != null else "无键"))

	# 补满生命后商店生命徽记也要当场变
	var p := GameManager.player as AuthorTestPlayer
	p.current_health = 10.0
	p.max_health = 100.0
	_panel._heal_full()
	await _settle(3)
	_c.equals(_last_state_kind, "hp", "补满生命后发 state_changed(hp)")
	_c.check(_shop._hp_chip.get_value_text().contains("100/100"),
		"商店生命徽记当场刷新（%s）" % _shop._hp_chip.get_value_text())
	GameManager.shop_offers = []

## 货架卡的价格键：唯一一颗 custom_minimum_size 高 = CARD_PRICE_H 的按钮
func _find_price_btn() -> Button:
	for btn in _buttons_of(_shop.offers_container):
		if is_equal_approx(btn.custom_minimum_size.y, WaveShop.CARD_PRICE_H):
			return btn
	return null

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

# ---------------- 内嵌商店 Tab ----------------

func _check_embedded_shop_tab() -> void:
	_panel.switch_tab(4)
	await _settle(3)
	var sv: AuthorShopView = _panel._shop_view
	_c.check(sv != null and sv.visible, "作者面板成功切换到【◆ 商店】Tab")
	_c.check(sv.offers_container != null and sv.offers_container.get_child_count() > 0,
		"商店 Tab 货架已生成商品（%d 格）" % (sv.offers_container.get_child_count() if sv.offers_container != null else 0))
	_c.check(sv.owned_container != null and sv.owned_container.get_child_count() > 0,
		"商店 Tab 陈列行已生成（%d 格）" % (sv.owned_container.get_child_count() if sv.owned_container != null else 0))
	_c.check(sv.stones_label != null and sv.stones_label.text.contains(str(GameManager.spirit_stones)),
		"商店 Tab 顶栏金币读数同步正确（%s）" % (sv.stones_label.text if sv.stones_label != null else ""))

	# 测试重掷货架
	sv.reroll_btn.pressed.emit()
	await _settle(3)
	_c.check(GameManager.shop_offers.size() > 0, "重掷后货架商品依然存在")

	# 测试点陈列行的武器能弹出详情卡
	var first_slot := _find_first_weapon_slot(sv.owned_container)
	_c.check(first_slot != null, "陈列行内找到上阵武器槽位")
	if first_slot != null:
		await _tap(first_slot)
		var tip := DetailTip.live(sv)
		_c.check(tip != null, "点击陈列行武器槽位成功弹出详情卡")
		if tip != null:
			var acts := _action_texts(tip)
			_c.check(acts.has("卸入背包") or acts.has("装 备"), "详情卡内具备换装操作键（实得 %s）" % str(acts))
			DetailTip.close_all(sv)
			await _settle(2)
			_c.check(DetailTip.live(sv) == null, "关闭后详情卡顺利收起")

	await _check_shop_tip_on_screen()
	await _check_shop_shelf_price_visible()
	await _check_shop_sell_from_tip()
	await _check_shop_merge_in_place()
	await _check_shop_drag_swap()
	await _check_shop_synergy_jump()

## 用户 2026-10-25：作者模式商店点下面装备图标，弹窗看不到、卖都卖不掉。
## 根因：AuthorShopView 的 get_tip_host 返回了自己 —— 它是面板 VBox 里的布局节点，
## DetailTip 按宿主 size/global_position 摆卡，卡被算到屏幕底边之外（探针量出卡顶 y=535）。
## 这条钉两件事：卡完整落在屏内 + 出售键真的能按到（能按到才能卖）。
func _check_shop_tip_on_screen() -> void:
	var sv: AuthorShopView = _panel._shop_view
	sv.refresh(false)
	await _settle(3)
	var slot := _find_first_weapon_slot(sv.owned_container)
	if slot == null:
		_c.fail("商店 Tab 里没有可点的武器槽位（弹窗位置判据无从量起）")
		return
	await _tap(slot)
	var tip := DetailTip.live(_panel)
	_c.check(tip != null, "商店槽位弹窗挂在面板上（宿主解析到全屏 AuthorPanel）")
	if tip == null:
		return
	var cr := tip.card_rect()
	var screen := Rect2(Vector2.ZERO, Vector2(VIEWPORT_SIZE))
	_c.check(screen.encloses(cr),
		"详情卡完整落在屏内（卡 %s / 屏 %s）" % [str(cr), str(screen)])
	# 出售键必须真在屏内：卡在屏外时人按不到，只能看着它「存在」
	var sell_btn: Button = null
	for b in _buttons_of(tip):
		if String(b.text).begins_with("售") or String(b.text).begins_with("原价售"):
			sell_btn = b
			break
	_c.check(sell_btn != null, "武器详情卡有出售键")
	if sell_btn != null:
		_c.check(screen.encloses(sell_btn.get_global_rect()),
			"出售键在屏内可按（键 %s）" % str(sell_btn.get_global_rect()))
	DetailTip.close_all(_panel)
	await _settle(2)

## 货架价格键必须落在滚动视口内：卡高 284 vs 视口 247 时键会被挤出去，买货得先滚一下
## （2026-10-25 探针发现）。面板高按 ShopCardLayout 呼吸量算 + 空羁绊行不占位后修复。
func _check_shop_shelf_price_visible() -> void:
	var sv: AuthorShopView = _panel._shop_view
	if sv.offers_container.get_child_count() == 0:
		_c.fail("货架为空，价格键可见性无从量起")
		return
	var card: Control = sv.offers_container.get_child(0)
	var price_btn: Button = null
	for b in _buttons_of(card):
		if is_equal_approx(b.custom_minimum_size.y, WaveShop.CARD_PRICE_H):
			price_btn = b
			break
	_c.check(price_btn != null, "货架卡有价格键")
	if price_btn == null:
		return
	var view := sv.offers_scroll.get_global_rect()
	_c.check(view.encloses(price_btn.get_global_rect()),
		"价格键完整落在货架视口内（键 %s / 视口 %s）" % [str(price_btn.get_global_rect()), str(view)])

## 出售：从槽位弹窗的出售键扣掉一件并退金币（用户诉求就是「卖都卖不掉」）
func _check_shop_sell_from_tip() -> void:
	var sv: AuthorShopView = _panel._shop_view
	sv.refresh(false)
	await _settle(3)
	var before_eq := GameManager.slots_used()
	var before_stones := GameManager.spirit_stones
	var slot := _find_first_weapon_slot(sv.owned_container)
	if slot == null:
		_c.fail("出售判据找不到武器槽位")
		return
	await _tap(slot)
	var tip := DetailTip.live(_panel)
	if tip == null:
		_c.fail("出售判据：弹窗没打开")
		return
	await _press_action(tip, _sell_btn_text(tip))
	await _settle(3)
	_c.equals(GameManager.slots_used(), before_eq - 1, "点出售后上阵 -1（%d → %d）" % [before_eq, GameManager.slots_used()])
	_c.check(GameManager.spirit_stones > before_stones,
		"出售退金币（%d → %d）" % [before_stones, GameManager.spirit_stones])
	_c.check(DetailTip.live(_panel) == null, "出售后详情卡收起（不留一张写着旧账的卡）")

func _sell_btn_text(tip: DetailTip) -> String:
	for btn in _buttons_of(tip):
		var t := String(btn.text)
		if t.begins_with("售") or t.begins_with("原价售"):
			return t
	return ""

## 三合一：凑满 3 件同名同星后点合成键，陈列行里当场升星（作者模式也要能合成）。
## 这条曾经整条断掉 —— 假玩家缺 remove/upgrade_weapon_instance，merge_weapon 报
## 「副本数量不足」只打 warning，星数不动（2026-10-25 探针抓到）。
func _check_shop_merge_in_place() -> void:
	var sv: AuthorShopView = _panel._shop_view
	# 先清空上阵与背包，灌 3 件同名 ★1，保证合成键一定亮
	GameManager.drones.clear()
	GameManager.stash.clear()
	var p := GameManager.player as AuthorTestPlayer
	p.equipped.clear()
	for i in range(3):
		AuthorMode.grant(GameManager, "weapon", "qingyun_sword", 1)
	sv.refresh(false)
	await _settle(4)
	_c.equals(GameManager.count_copies("qingyun_sword", 1), 3, "灌好 3 件同名 ★1")
	var slot := _find_first_weapon_slot(sv.owned_container)
	if slot == null:
		_c.fail("合成判据找不到武器槽位")
		return
	await _tap(slot)
	var tip := DetailTip.live(_panel)
	if tip == null:
		_c.fail("合成判据：弹窗没打开")
		return
	var merge_txt := ""
	for btn in _buttons_of(tip):
		if String(btn.text).begins_with("◆ 三合一"):
			merge_txt = String(btn.text)
			break
	_c.check(not merge_txt.is_empty(), "凑满 3 件后合成键亮起")
	if merge_txt.is_empty():
		return
	await _press_action(tip, merge_txt)
	# 演出约 0.55s（★2 档），迸发帧落地后再等一帧重建陈列行
	await _settle(90)
	_c.equals(GameManager.count_copies("qingyun_sword", 2), 1, "三合一后 ★2 到手 1 件")
	_c.equals(GameManager.count_copies("qingyun_sword", 1), 0, "3 件 ★1 被吃干净")
	_c.check(_find_node_named(sv, "MergeFx") == null, "合成演出层已收干净（无残留覆盖层）")

## 拖拽换装：按住 HOLD_DELAY 拎起上阵件、拖到背包格放下＝互换（作者模式也要能拖）
func _check_shop_drag_swap() -> void:
	var sv: AuthorShopView = _panel._shop_view
	if GameManager.stash.is_empty():
		AuthorMode.grant(GameManager, "weapon", "qingyun_sword", 1)
		if GameManager.stash.is_empty() and GameManager.slots_used() > 1:
			GameManager.unequip_to_stash(0)
	sv.refresh(false)
	await _settle(4)
	var src := _find_weapon_slot_in_pool(sv.owned_container, "equipped")
	# 落点取「背包 n/9」分隔签（只指区域不指件）＝卸下语义；拖到具体某一件上那是互换
	# （件数不变），两种语义各钉各的，别混在一个断言里。
	var tgt := _find_slot_with_kind(sv.owned_container, "stash", "end")
	if src == null or tgt == null:
		_c.fail("拖拽判据缺源/落点格（src=%s tgt=%s）" % [str(src), str(tgt)])
		return
	var eq_before := GameManager.slots_used()
	var stash_before := GameManager.stash.size()
	var src_id := String(GameManager.get_weapons_summary()[0].get("id", ""))
	_press(src.get_global_rect().get_center())
	await get_tree().create_timer(ShopDragDrop.HOLD_DELAY + 0.15).timeout
	_c.check(sv.drag_ctl.is_dragging(), "按住 %.2f 秒后拎起（作者模式商店内）" % (ShopDragDrop.HOLD_DELAY + 0.15))
	if not sv.drag_ctl.is_dragging():
		_release(src.get_global_rect().get_center())
		return
	# 幽灵整颗抬到手指上方 AIM_LIFT，判定认图标中心 ⇒ 手指停在落点格下方
	var aim := tgt.get_global_rect().get_center() + Vector2(0, ShopDragDrop.AIM_LIFT)
	_motion(aim)
	await _settle(2)
	_c.check(String(sv.drag_ctl.hover_src().get("pool", "")) == "stash", "图标压到背包格时点亮该落点")
	_release(aim)
	await _settle(4)
	_c.equals(GameManager.slots_used(), eq_before - 1, "拖到背包后上阵 -1")
	_c.equals(GameManager.stash.size(), stash_before + 1, "背包 +1")
	_c.check(not sv.drag_ctl.is_dragging(), "松手后手势已结清（不会卡住吞输入）")
	# 道具 id 不变（互换只换位置，不换件）
	_c.check(GameManager.stash.any(func(e): return String(e.get("id", "")) == src_id),
		"背包里出现的就是刚拖下去的那件（%s）" % src_id)

## 羁绊详情卡「查看该流派武器」：原先这条信号一路发到 AuthorPanel 就断了（Main 只接了
## WaveShop 的那一条），点了没反应。现在面板自己切到◆武器页并按该路筛选。
func _check_shop_synergy_jump() -> void:
	var sv: AuthorShopView = _panel._shop_view
	_panel.switch_tab(4)
	await _settle(3)
	var chips: Array[Label] = []
	for lbl in _labels_of(sv._synergy_box):
		chips.append(lbl)
	if chips.is_empty():
		# 没激活流派时整条隐藏（竖向预算让给货架），这条判据就跳过
		_c.check(not sv._info_bar.visible, "无激活流派时羁绊行隐藏（不白占货架预算）")
		return
	_c.check(sv._info_bar.visible, "有激活流派时羁绊行显示")
	var tag := _first_active_tag()
	_c.check(not tag.is_empty(), "取到一个激活流派标签（%s）" % tag)
	if tag.is_empty():
		return
	# 走面板自己的跳转入口（与羁绊卡「查看该流派武器」同一路径）
	_panel._show_weapon_tag(tag)
	await _settle(3)
	_c.equals(_panel._current_tab, 2, "跳转后停在◆武器页")
	var want_filter := tag if tag in WeaponData.CLASSES else ""
	if want_filter != "":
		_c.equals(_panel.weapon_class_filter, want_filter, "类型流派预选到类型行（%s）" % want_filter)
	else:
		_c.equals(_panel.weapon_element_filter, tag, "五行流派预选到五行行（%s）" % tag)
	_c.equals(_cards_in(_panel._weapon_box).size(), _tag_total(tag),
		"武器页已按该流派筛好（%d 把）" % _tag_total(tag))
	# 复位筛选，后面的判据（以及退出时的状态）不带上这一手
	_panel.weapon_class_filter = ""
	_panel.weapon_element_filter = ""
	_panel._restyle_filter_chips()
	_panel._rebuild_weapon_grid()
	await _settle(2)

func _first_active_tag() -> String:
	for tag in GameManager.active_synergies.keys():
		if WeaponData.SYNERGIES.has(tag):
			return String(tag)
	return ""

func _find_weapon_slot_in_pool(root: Control, pool: String) -> Control:
	for ch in root.get_children():
		if not (ch is Control) or not ch.has_meta("drag_src"):
			continue
		var s: Dictionary = ch.get_meta("drag_src")
		if String(s.get("pool", "")) != pool:
			continue
		if not String(s.get("kind", "")).is_empty():
			continue
		return ch as Control
	return null

func _find_slot_with_kind(root: Control, pool: String, kind: String) -> Control:
	for ch in root.get_children():
		if not (ch is Control) or not ch.has_meta("drag_src"):
			continue
		var s: Dictionary = ch.get_meta("drag_src")
		if String(s.get("pool", "")) == pool and String(s.get("kind", "")) == kind:
			return ch as Control
	return null

func _find_node_named(n: Node, nm: String) -> Node:
	if String(n.name) == nm:
		return n
	for c in n.get_children():
		var r := _find_node_named(c, nm)
		if r != null:
			return r
	return null

func _find_first_weapon_slot(root: Control) -> Control:
	for ch in root.get_children():
		if ch is Control and ch.has_meta("drag_src"):
			return ch as Control
	return null

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
	if ctrl == null:
		return
	var p := ctrl.get_global_rect().get_center()
	_press(p)
	_release(p)
	await _settle(2)

func _press(p: Vector2) -> void:
	for pressed in [true]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.position = p
		ev.global_position = p
		ev.pressed = pressed
		get_tree().root.push_input(ev)

func _release(p: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = p
	ev.global_position = p
	ev.pressed = false
	get_tree().root.push_input(ev)

func _motion(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = p
	ev.global_position = p
	get_tree().root.push_input(ev)

func _settle(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame
