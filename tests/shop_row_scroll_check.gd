extends Node

## 判据：灵石阁陈列行（上阵 + 背包 + 法宝）满仓时，整排要「处处划得起来、每一格滑得到、
## 划一下不会多选一件、重建后不回跳最左」。
## 运行: $G --headless --path . res://tests/ShopRowScrollCheck.tscn
##       $G --headless --path . res://tests/ShopRowScrollCheck.tscn -- --selftest （验尺子有牙齿）
##
## 为什么立这条（用户 2026-10-09 真机截图：第 13 波，上阵 5 + 背包 7 + 法宝 10，右边几件出屏）：
## 「装备太多了，可以左右滑动啊，不然很多装备都操作不了了」。这一排原先不在滚动区里，
## 槽位按件数从 44 压到 36 也不够 —— 满仓 6 上阵 + 9 背包 + 15 法宝 = 30 格要 1400 宽，
## 最宽那档屏（20:9 设计可视 1202）只给得起 1042。摆不平又不许出屏，剩下的路只有砍件数；
## 正路是全留 + 可滑到。（与货架那一排「不许竖滑」不冲突：货架滑一次才能比一次价，
## 陈列行只是「够得着」—— 划一下就把最右那件点到手里，不挡任何决策。）
##
## 五把尺各自要防的假 PASS：
## ① 处处可起手 —— ScrollContainer 的拖动靠「左键按下那一拍」latch，子控件 STOP 与
##    BaseButton 自己 accept_event() 都会就地吃掉它。所以落点必须打在格子本体上（不是只打
##    缝隙），且按真实坐标 push_input 走引擎拾取，不 emit_signal（同一课见 ManualHotzoneCheck）。
## ② 每一格滑得到 —— 逐格把 scroll_horizontal 钉过去，量那一格**画出来**是否完整落进滚动区
##    可视框：内容宽算对了但被 clip 掉半格，照样操作不了。
## ③ 划动不误选 —— 真发「按下 → 内容跟着手指走 → 在新位置抬起」。抬起点相对屏幕移了 90，
##    但格子跟着内容一起移了 90，手指自始至终压在同一格内 ⇒ 旧写法（BaseButton.pressed）一定
##    误选。这一枪必须能在反例上打出误选，才算有牙齿（反例①）。
## ④ 摆得平不许露滑条 —— 只剩一两件时把 scroll_horizontal 钉到极大再读回，必须是 0。
##    小数宽没取整会叫出一条没用的滑条（与货架 offer_card_w 取整同一条理由）。
## ⑤ 重建不回跳 —— 点一件法器会重建整行（选中描边要重画），滑到的位置必须还在原处。

const VP := Vector2(1202, 540)
## 有意划动：必须明显大于 GameStyle.TAP_SLACK，否则测的不是「划」
const SWIPE := 90.0
## 手指按在原地的微动：必须明显小于容差
const JITTER := 4.0
const EPS := 1.5
## 满仓样本至少要采到多少格：少于这个数等于没测到溢出
const MIN_TILES := 20

var _c := TestCheck.new()
var _shop: WaveShop
var _scroll: ScrollContainer
var _row: HBoxContainer
## 反例道具：插进行首（同一个滚动区里，冒泡才量得着），同一时刻只留一个
var _fixture: Control = null

func _ready() -> void:
	get_tree().root.size = VP
	GameManager.reset_run()
	GameManager.roll_shop(true)
	_shop = load("res://scenes/ui/WaveShop.tscn").instantiate()
	add_child(_shop)
	await get_tree().process_frame
	_seed_full()
	_shop._on_shop_opened()
	get_tree().paused = false
	await _settle(10)
	_scroll = _shop.owned_scroll
	_row = _shop.owned_container
	if "--selftest" in OS.get_cmdline_user_args():
		await _selftest()
	else:
		await _run()
	get_tree().quit(0 if _c.report("SHOP_ROW_RESULT") else 1)

## 灌满仓：headless 不建 Player，add_weapon 没有 player 节点进不了上阵栏 ⇒ 与 LayoutCheck
## 同一手法，直接灌 _refresh_inventory 现读的那几份字段（drones 当上阵、stash 当背包、items 当法宝）。
func _seed_full() -> void:
	GameManager.drones.clear()
	for i in range(WeaponData.MAX_SLOTS):
		GameManager.drones.append({"id": "lingdie", "star": 1})
	GameManager.stash.clear()
	for wid in ["qingyun_sword", "huoyan_fu", "chiyan_dao", "liuye_feidao", "wulei_paizi",
			"gengjin_feijian", "bajiao_fan", "fantian_yin", "fentian_baodeng"]:
		var wdef: Dictionary = WeaponData.get_def(wid)
		if wdef.is_empty():
			continue
		GameManager.stash.append({"id": wid, "name": wdef.get("name", "?"), "star": 1,
			"icon": wdef.get("icon", ""), "tag": wdef.get("tag", "")})
	GameManager.items.clear()
	for id in ItemData.all_ids():
		GameManager.add_item(String(id))
	GameManager.recalc_synergies()

# ================================ 正例 ================================

func _run() -> void:
	var tiles := _tiles()
	_c.check(tiles.size() >= MIN_TILES, "满仓样本建起来了：%d 格（上阵 %d + 背包 %d + 法宝 %d + 色签）" % [
		tiles.size(), GameManager.get_weapons_summary().size(), GameManager.stash.size(),
		GameManager.items.size()])
	var content_w: float = _row.get_combined_minimum_size().x
	var vis_w: float = _scroll.size.x
	_c.check(content_w > vis_w + EPS, "这一档确实摆不平（内容 %.0f > 可视 %.0f）⇒ 不溢出等于没测" % [
		content_w, vis_w])
	_c.check(_scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED,
		"摆不平 ⇒ 横滑已启用（mode=%d）" % _scroll.horizontal_scroll_mode)
	_c.check(_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
		"这一行只有一格高，竖向滚动必须禁用")

	await _check_everywhere_draggable(tiles)
	await _check_each_tile_reachable(tiles)
	await _check_swipe_not_select()
	await _check_chip_swipe()
	await _check_scroll_kept()
	await _check_no_phantom_slide()

# ---------- ① 处处可起手 ----------

## 每格中心 + 相邻格缝隙各打一枪，量 OwnedScroll 收不收得到那一下按下
func _check_everywhere_draggable(tiles: Array) -> void:
	var pts := _sample_points(tiles)
	var reach := 0
	var on_tile := 0
	var blocked: Array[String] = []
	for p in pts:
		if _tile_at(p) != null:
			on_tile += 1
		if await _press_reaches(p):
			reach += 1
		else:
			blocked.append("%s←%s" % [str((p as Vector2).round()), _eater_at(p)])
	print("ROW 采样 %d 点（格子本体上 %d），可起手拖动 %d 点" % [pts.size(), on_tile, reach])
	_c.check(pts.size() >= MIN_TILES + 4, "落点够密：采到 %d 处（下限 %d）" % [pts.size(), MIN_TILES + 4])
	_c.check(on_tile >= 8, "落点里 %d 处打在格子本体上（下限 8），不是只打缝隙" % on_tile)
	_c.check(reach == pts.size(), "处处可起手：%d/%d 处送得到按下；滑不动的：%s" % [
		reach, pts.size(), "、".join(blocked)])
	_c.check(_shop.selected.is_empty(), "采样用的枪不许顺手选中东西")

# ---------- ② 每一格都滑得到 ----------

func _check_each_tile_reachable(tiles: Array) -> void:
	_scroll.scroll_horizontal = 0
	await _settle(3)
	# 内容坐标系里每格的左边界（此刻滚动为 0，画出来的 x 减掉滚动区左界就是内容 x）
	var base_x: float = _scroll.global_position.x
	var content_x: Array = []
	for t in tiles:
		content_x.append((t as Control).global_position.x - base_x)
	var unreachable: Array[String] = []
	for i in range(tiles.size()):
		_scroll.scroll_horizontal = int(content_x[i])
		await _settle(3)
		var r: Rect2 = (tiles[i] as Control).get_global_rect()
		var vis := _scroll.get_global_rect()
		if r.position.x < vis.position.x - EPS or r.end.x > vis.end.x + EPS:
			unreachable.append("第 %d 格 x %.0f..%.0f（滚动区 %.0f..%.0f，滑到 %d）" % [
				i, r.position.x, r.end.x, vis.position.x, vis.end.x, _scroll.scroll_horizontal])
	_c.check(unreachable.is_empty(), "每一格都要滑得到（%d 格全量）；够不着的：%s" % [
		tiles.size(), "；".join(unreachable)])
	_scroll.scroll_horizontal = 100000
	await _settle(3)
	var far := _scroll.scroll_horizontal
	_c.check(far > 0, "引擎自己夹出来的可滑量：%.0f（钉到 100000 后读回）" % far)
	var last: Rect2 = (tiles[tiles.size() - 1] as Control).get_global_rect()
	var vis := _scroll.get_global_rect()
	_c.check(last.end.x <= vis.end.x + EPS,
		"滑到底要看得见最后一格的右边线：末格 x %.0f..%.0f，滚动区右界 %.0f" % [
			last.position.x, last.end.x, vis.end.x])

# ---------- ③ 划动不误选 / 原地点按要选中 ----------

func _check_swipe_not_select() -> void:
	_deselect()
	await _settle(4)
	_scroll.scroll_horizontal = 0
	await _settle(3)
	var t: Control = _tiles()[2]
	var p: Vector2 = t.get_global_rect().get_center()
	await _swipe_over(p)
	_c.check(_shop.selected.is_empty(),
		"在槽位上划 %.0f 单位（内容跟着走）不许选中，实得 %s" % [SWIPE, str(_shop.selected)])
	t = _tiles()[2]
	await _tap_at(t.get_global_rect().get_center())
	_c.check(int(_shop.selected.get("index", -1)) == 2 and _shop.selected.get("pool", "") == "equipped",
		"同一格原地微动后松手必须选中（否则「划不动也点不着」会一起假绿），实得 %s" % str(_shop.selected))

## 法宝徽位：划动不弹详解，点按要弹
func _check_chip_swipe() -> void:
	_deselect()
	await _settle(4)
	var chips := _item_chips()
	if chips.is_empty():
		_c.check(false, "满仓样本里没建出法宝徽位，这一处没量到")
		return
	var chip: Control = chips[0]
	var p: Vector2 = await _bring_into_view(chip)
	await _swipe_over(p)
	_c.check(DetailTip.live(_shop) == null, "在法宝徽位上划 %.0f 单位不许弹详解" % SWIPE)
	p = await _bring_into_view(chip)
	await _tap_at(p)
	var live := DetailTip.live(_shop)
	var want := String(chip.get_meta("tip_title", ""))
	_c.check(live != null and String((live as DetailTip).payload.get("title", "")) == want,
		"点一下法宝徽位要弹它的详解（要「%s」，实得「%s」）" % [
			want, "" if live == null else String((live as DetailTip).payload.get("title", "?"))])
	DetailTip.close_all(_shop)
	await _wait_tips_gone()

# ---------- ⑤ 重建后滑位不跳回最左 ----------

func _check_scroll_kept() -> void:
	_scroll.scroll_horizontal = 260
	await _settle(4)
	var before := _scroll.scroll_horizontal
	_shop._refresh_inventory()
	await _settle(10)
	var after := _scroll.scroll_horizontal
	_c.check(absf(float(after) - float(before)) <= 2.0,
		"点一件法器会重建整行：滑到的位置必须还在原处（滑到 %d，重建后 %d）" % [before, after])

# ---------- ④ 摆得平不露滑条 ----------

func _check_no_phantom_slide() -> void:
	GameManager.drones.clear()
	GameManager.drones.append({"id": "lingdie", "star": 1})
	GameManager.stash.clear()
	GameManager.items.clear()
	GameManager.recalc_synergies()
	_shop._refresh_inventory()
	await _settle(8)
	var content_w: float = _row.get_combined_minimum_size().x
	_c.check(content_w <= _scroll.size.x + EPS,
		"一两件要摆得平（内容 %.0f ≤ 可视 %.0f）" % [content_w, _scroll.size.x])
	_scroll.scroll_horizontal = 100000
	await _settle(4)
	_c.check(_scroll.scroll_horizontal == 0,
		"摆得平就不许有得滑（钉到 100000 后读回 %d：露一条没用的滑条）" % _scroll.scroll_horizontal)
	_c.check(_tiles().size() >= 1, "两件样本这一屏至少要有槽位可看")

# ================================ 反例 ================================

## 尺子得拦得住东西：把「修复前的形状」掺进同一个滚动区里打同一枪，必须报出问题。
## 反例① 顺带证明「划动那一枪的抬起确实还落在同一格内」—— 否则「划动没选中」可能只是因为
## 抬起落在了格子外面，整条判据就成了自证。
func _selftest() -> void:
	_c.check(GameStyle.TAP_SLACK > JITTER and GameStyle.TAP_SLACK < SWIPE,
		"容差 %.0f 夹在「手指微动 %.0f」与「有意划动 %.0f」之间" % [
			GameStyle.TAP_SLACK, JITTER, SWIPE])
	_c.check(_scroll != null and _scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED,
		"反例打在真滚动区里（OwnedScroll 横滑已开）")

	# 反例① 旧写法：BaseButton.pressed —— 内容跟着手指走了，抬起仍在同一格内 ⇒ 误选
	var old_btn := Button.new()
	old_btn.custom_minimum_size = Vector2(44, 44)
	old_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	old_btn.focus_mode = Control.FOCUS_NONE
	var old_fired := [false]
	old_btn.pressed.connect(func(): old_fired[0] = true)
	await _add_fixture(old_btn)
	await _swipe_over(old_btn.get_global_rect().get_center())
	_c.check(old_fired[0], "反例① 旧写法（Button.pressed）在「划动 + 内容跟着走」会误选 —— " +
		"这一枪抓得住（抓不住说明抬起没落回同一格，正例③就是假的）")

	# 反例② 旧写法：只认「左键松开」⇒ 划完一松手照样兑现
	var old_chip := _panel(Control.MOUSE_FILTER_PASS)
	var popped := [false]
	old_chip.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
			popped[0] = true
	)
	await _add_fixture(old_chip)
	await _swipe_over(old_chip.get_global_rect().get_center())
	_c.check(popped[0], "反例② 只认松开的旧点按，同一枪也会兑现")

	# 正例：新写法 GameStyle.tap —— 同一枪不算点，原地点按照旧要兑现
	var new_chip := _panel(Control.MOUSE_FILTER_PASS)
	var tapped := [false]
	GameStyle.tap(new_chip, func(): tapped[0] = true)
	await _add_fixture(new_chip)
	await _swipe_over(new_chip.get_global_rect().get_center())
	_c.check(not tapped[0], "正例 GameStyle.tap 在同一枪上不兑现")
	# 划动把行首这件划出可视框了：先滑回最左，再打「原地点按」这一枪
	_scroll.scroll_horizontal = 0
	await _settle(3)
	await _tap_at(new_chip.get_global_rect().get_center())
	_c.check(tapped[0], "正例 GameStyle.tap 原地微动后松手仍然兑现")

	# 反例③ STOP 把「按下」那一拍吃掉 ⇒ 滚动区收不到，这一处滑不动
	var stopper := _panel(Control.MOUSE_FILTER_STOP)
	await _add_fixture(stopper)
	_c.check(not await _press_reaches(stopper.get_global_rect().get_center()),
		"反例③ 压在 STOP 面板上时 OwnedScroll 收不到按下（证明这一把尺抓得住 STOP）")
	var passer := _panel(Control.MOUSE_FILTER_PASS)
	await _add_fixture(passer)
	_c.check(await _press_reaches(passer.get_global_rect().get_center()),
		"反例③ 同一处换成 PASS 就送得到按下（证明上一行报的是 STOP，不是采样点打偏）")
	await _add_fixture(null)
	_c.check(await _press_reaches(_tiles()[3].get_global_rect().get_center()),
		"正例③ 真槽位（PanelContainer + PASS）上按下能起手拖动")

# ---------------- 道具与采样 ----------------

func _tiles() -> Array:
	var out: Array = []
	for ch in _row.get_children():
		var ctl := ch as Control
		if ctl != null and ctl.visible and ctl.size.x > 0.0:
			out.append(ctl)
	return out

## 法宝徽位：_create_item_chip 登记了 tip_title（与 ManualDialog/PlayerStatsDialog 同一约定）
func _item_chips() -> Array:
	var out: Array = []
	for t in _tiles():
		if t.has_meta("tip_title"):
			out.append(t)
	return out

## 每格中心 + 相邻格缝隙中点，x 夹在滚动区可视框内
func _sample_points(tiles: Array) -> Array:
	var vis := _scroll.get_global_rect()
	var xs: Array = []
	var prev_end: float = -1.0
	for t in tiles:
		var r: Rect2 = (t as Control).get_global_rect()
		if prev_end > 0.0:
			var gap := (prev_end + r.position.x) * 0.5
			if gap > vis.position.x + 2.0 and gap < vis.end.x - 2.0:
				xs.append(gap)
		if r.intersects(vis):
			xs.append(clampf(r.get_center().x, vis.position.x + 3.0, vis.end.x - 3.0))
		prev_end = r.end.x
	var y: float = clampf(vis.get_center().y, vis.position.y + 3.0, vis.end.y - 3.0)
	var pts: Array = []
	for x in xs:
		pts.append(Vector2(x, y))
	return pts

func _tile_at(pos: Vector2) -> Control:
	for t in _tiles():
		if (t as Control).get_global_rect().has_point(pos):
			return t
	return null

## 把某一格滑到可视框正中，返回它落定后的中心（满仓时最右那几件在屏外，不滑进来就打不到）
func _bring_into_view(ctl: Control) -> Vector2:
	var vis := _scroll.get_global_rect()
	var want: float = ctl.global_position.x - vis.position.x - (vis.size.x - ctl.size.x) * 0.5
	_scroll.scroll_horizontal = int(maxf(0.0, want))
	await _settle(3)
	return ctl.get_global_rect().get_center()

## 反例道具插进行首：同一个滚动区、同一个冒泡链，且 scroll=0 时就在眼前
func _add_fixture(node: Control) -> void:
	if _fixture != null and is_instance_valid(_fixture):
		_fixture.free()
	_fixture = node
	if node == null:
		return
	_row.add_child(node)
	_row.move_child(node, 0)
	_scroll.scroll_horizontal = 0
	await get_tree().process_frame
	await get_tree().process_frame

func _panel(filter: Control.MouseFilter) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(44, 44)
	p.mouse_filter = filter
	return p

# ---------------- 喂事件 ----------------

## 连一次 OwnedScroll.gui_input，打「按下」，看它收不收得到（收得到才 latch 得住拖动）。
## 抬起故意挪 40 单位再放：超过 TAP_SLACK ⇒ 这一枪只测「送不送得到按下」，不顺手选中东西。
func _press_reaches(pos: Vector2) -> bool:
	var hits := [0]
	var cb := func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			hits[0] += 1
	_scroll.gui_input.connect(cb)
	_btn(pos, true)
	await get_tree().process_frame
	_btn(pos + Vector2(40, 0), false)
	await get_tree().process_frame
	_scroll.gui_input.disconnect(cb)
	return hits[0] > 0

## 有意划动：按下 → 内容跟着手指走（真机上就是这一条让旧写法误选）→ 在新位置抬起
func _swipe_over(from: Vector2) -> void:
	_btn(from, true)
	await get_tree().process_frame
	_scroll.scroll_horizontal = int(_scroll.scroll_horizontal + SWIPE)
	await get_tree().process_frame
	_motion(from - Vector2(SWIPE, 0), Vector2(-SWIPE, 0))
	_btn(from - Vector2(SWIPE, 0), false)
	await get_tree().process_frame

## 原地微动一枪
func _tap_at(p: Vector2) -> void:
	_btn(p, true)
	await get_tree().process_frame
	_motion(p + Vector2(JITTER, 0), Vector2(JITTER, 0))
	_btn(p + Vector2(JITTER, 0), false)
	await get_tree().process_frame
	await get_tree().process_frame

func _deselect() -> void:
	_shop.selected = {}
	_shop._refresh_inventory()

func _btn(pos: Vector2, down: bool) -> void:
	var b := InputEventMouseButton.new()
	b.position = pos
	b.global_position = pos
	b.button_index = MOUSE_BUTTON_LEFT
	b.pressed = down
	if down:
		b.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_window().push_input(b)

func _motion(pos: Vector2, delta: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = pos
	m.global_position = pos
	m.relative = delta
	m.screen_relative = delta
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_window().push_input(m)

## 等宿主上所有详解卡（含正在淡出的旧卡）真的离开节点树
func _wait_tips_gone() -> void:
	DetailTip.close_all(_shop)
	for i in range(40):
		var any := false
		for ch in _shop.get_children():
			if ch is DetailTip:
				any = true
		if not any:
			return
		await get_tree().process_frame

## 报是谁吃掉了那一拍：包含该点、mouse_filter 为 STOP 的最深控件
## （手写递归：find_children 的 owned 参数默认 true，代码 new() 出来的控件 owner 为空会漏掉）
func _eater_at(pos: Vector2) -> String:
	var best: Control = null
	var best_area := INF
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for ch in cur.get_children():
			stack.append(ch)
			var ctl := ch as Control
			if ctl == null or not ctl.visible or ctl.mouse_filter != Control.MOUSE_FILTER_STOP:
				continue
			var r := ctl.get_global_rect()
			if not r.has_point(pos):
				continue
			var area := r.size.x * r.size.y
			if area < best_area:
				best_area = area
				best = ctl
	if best == null:
		return "非 STOP 控件"
	var par := best.get_parent()
	return "%s(父:%s)" % [best.get_class(), par.name if par else "?"]

func _settle(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame
