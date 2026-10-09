extends Node

## 判据：滚动列表里「想滑」和「想点」必须分得开 —— 划动不许弹出详解，原地点按照旧要弹对卡。
## 运行: $G --headless --path . res://tests/TapSwipeCheck.tscn
##       $G --headless --path . res://tests/TapSwipeCheck.tscn -- --selftest  （验判据有牙齿）
##
## 为什么立这条判据（用户 2026-10-09 真机：属性面板「悟道历程」里「我本来想滑动，不小心就点按了」）：
##  ① 为了让手指能拖起列表，滚动区里的卡片把 mouse_filter 从 STOP 降成了 PASS
##     （GameStyle.swipeable，见 ScrollSwipeCheck 头注）。「按下」那一拍于是同时被外层
##     ScrollContainer 拿去 latch 拖动滚动。
##  ② 而点按若只认「左键松开」这一枪（旧 PlayerStatsDialog._is_tap、旧 ManualDialog 卡片），
##     划完列表一松手照样算一次点击 → 滑一次弹一张详解卡，滑三下弹三回。
##     这两条各自都对，合起来才是冲突：能滑 = 松手必被当成点。
##  ③ 毛病不崩、不报错、只有手指在屏上划过才看得见 —— 所以判据必须自己造一次
##     「按下 → 移动 → 抬起」，而不是只发一次松开。
##
## 尺子取引擎自己的账：push_input 打真实坐标，走真机同一套拾取；弹出的卡用 DetailTip.live()
## 现读标题，不另抄一份热区表。
## 防假 PASS：界面没建起来 / 采到的行数不够 / 落点全滚出可视区，一律算 FAIL；
## 而「划动那一枪不弹」本身可能是假的（抬起落在行外谁都没收到）—— 所以 --selftest 反例①
## 必须用修复前的写法在同一坐标上被抓出来，才证明这一枪真的送到了行上。

const VIEWPORT_SIZE := Vector2i(1202, 540)
## 有意划动：必须明显大于 GameStyle.TAP_SLACK，否则测的不是「划」
const SWIPE := 70.0
## 手指按在原地的一点微动：必须明显小于容差，否则「根本点不动」也会被判成通过
const JITTER := 4.0
## 悟道历程至少采几行：少于这个数等于没测
const MIN_ROWS := 3
## 手册那一侧采几张卡就够（每张两枪）
const MANUAL_CARDS := 4
## 一块热区横着切几列点：只点中心会被「正中间那层显示件」冤枉成没问题
const SAMPLE_COLS := 3
## 判据自造的假卡：摆在面板正中，谁都不压，好让两把手指打在同一个坐标上
const DECOY_RECT := Rect2(441, 257, 320, 26)

var _c := TestCheck.new()
var _dlg: PlayerStatsDialog
var _manual: ManualDialog
var _decoy_node: Control

func _ready() -> void:
	get_tree().root.size = VIEWPORT_SIZE
	_seed()
	_dlg = PlayerStatsDialog.new()
	add_child(_dlg)
	_dlg.open()
	_dlg._switch_bottom_tab(1)
	_dlg.refresh()
	await _settle(12)
	if "--selftest" in OS.get_cmdline_user_args():
		await _selftest()
	else:
		await _run()
	get_tree().quit(0 if _c.report("TAPSWIPE_RESULT") else 1)

## 造真数据：六条悟道，保证「悟道历程」那一列有东西可滑
func _seed() -> void:
	GameManager.reset_run()
	GameManager.cultivator_id = "shiyue"
	for id in ["atk_up", "melee_up", "armor_up", "speed_up", "hp_up", "haste_up"]:
		GameManager.apply_upgrade(id)

# ================================ 正判 ================================

func _run() -> void:
	# ---- ① 悟道历程：逐行「划一下不许弹」「点一下必须弹对这张卡」----
	var rows := _history_rows()
	_c.check(rows.size() >= MIN_ROWS, "悟道历程在可视区里采到 %d 行（≥%d 才算测到东西）" % [
		rows.size(), MIN_ROWS])
	for one in rows:
		await _two_fingers(_dlg, one[0], one[1], "悟道行", true)

	# ---- ② 左侧属性行（同一块面板、不滚动）：换了识别器不许把点按弄丢，行里不许有死点 ----
	var stat_rows := _zones_in_view(_dlg)
	_c.check(stat_rows.size() >= 4, "属性行在可视区里采到 %d 行" % stat_rows.size())
	for one in stat_rows:
		await _two_fingers(_dlg, one[0], one[1], "属性行", false)

	# ---- ③ 传道玉简·法器图鉴：卡片整页可滑，划过去不许弹卡 ----
	await _close_stats()
	_manual = ManualDialog.new()
	add_child(_manual)
	_manual.open()
	_manual._switch_tab(1)
	await _settle(6)
	var cards := _zones_in_view(_manual)
	_c.check(cards.size() >= MANUAL_CARDS, "法器图鉴采到 %d 张卡可测" % cards.size())
	for one in cards.slice(0, MANUAL_CARDS):
		await _two_fingers(_manual, one[0], one[1], "图鉴卡", true)

## 同一处热区打两把手指：先在中线划一下（不许弹），再在左/中/右各点一下（必须弹对这张卡）。
## 三个点而不是只点中心：行里只要有一层显示件（ProgressBar 这类默认 STOP）没让开，
## 中心那一枪就会打在它身上 —— 多打两个点才量得到「整行可点」是不是真的。
func _two_fingers(host: Control, box: Rect2, title: String, tag: String, swipe_too: bool) -> void:
	if swipe_too:
		var got_swipe := await _swipe_at(host, box.get_center(), SWIPE)
		_c.check(got_swipe == "", "%s「%s」：手指划 %.0f 单位后松手不弹详解（实弹「%s」）" % [
			tag, title, SWIPE, got_swipe])
	var y := box.get_center().y
	for ci in range(SAMPLE_COLS):
		var p := Vector2(box.position.x + box.size.x * (ci + 0.5) / SAMPLE_COLS, y)
		var got := await _tap_at(host, p)
		_c.check(got == title, "%s「%s」第 %d 列点按弹对卡（实得「%s」）" % [
			tag, title, ci + 1, got])

func _close_stats() -> void:
	DetailTip.close_all(_dlg)
	await _wait_tips_gone(_dlg)
	_dlg.close()
	await _settle(12)

## 悟道历程每一行：[可取样矩形, 期望卡标题]，只取与滚动可视区还有交叠的行
func _history_rows() -> Array:
	var out: Array = []
	var vis: Rect2 = _dlg._history_scroll.get_global_rect()
	var hist: Array = GameManager.upgrade_history
	var i := 0
	for ch in _dlg._history_list.get_children():
		var row := ch as Control
		if row == null:
			continue
		var title := String((hist[i] as Dictionary).get("title", "")) if i < hist.size() else ""
		i += 1
		var box := row.get_global_rect().intersection(vis)
		if box.size.y < 6.0 or title.is_empty():
			continue
		out.append([box, title])
	return out

## 登记了 tip_title 的热区（属性行 / 图鉴卡共用同一把尺子）：[可取样矩形, 期望卡标题]
func _zones_in_view(root: Node) -> Array:
	var out: Array = []
	for z in _hot_zones(root):
		var box := _reachable_rect(z)
		if box.size.x <= 0.0 or box.size.y <= 0.0:
			continue
		out.append([box, String(z.get_meta("tip_title"))])
	return out

# ============================ 两把手指 ============================

## 真发一次「按下 → 划 dy 单位 → 抬起」，返回宿主上弹出的卡标题（没弹返回空串）
func _swipe_at(host: Control, pos: Vector2, dy: float) -> String:
	return await _gesture(host, pos, dy)

## 真发一次「按下 → 抖 JITTER 单位 → 抬起」，等于玩家那一下点按
func _tap_at(host: Control, pos: Vector2) -> String:
	return await _gesture(host, pos, JITTER)

func _gesture(host: Control, pos: Vector2, dy: float) -> String:
	await _wait_tips_gone(host)
	_btn(pos, true)
	await get_tree().process_frame
	_motion(pos + Vector2(0, -dy * 0.5))
	await get_tree().process_frame
	_motion(pos + Vector2(0, -dy))
	await get_tree().process_frame
	_btn(pos + Vector2(0, -dy), false)
	await get_tree().process_frame
	var title := ""
	var tip := DetailTip.live(host)
	if tip != null:
		title = String(tip.payload.get("title", ""))	# 收起后节点会被 free，先取成字符串
	DetailTip.close_all(host)
	await _wait_tips_gone(host)
	return title

func _btn(pos: Vector2, down: bool) -> void:
	var b := InputEventMouseButton.new()
	b.button_index = MOUSE_BUTTON_LEFT
	b.position = pos
	b.global_position = pos
	b.pressed = down
	if down:
		b.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_tree().root.push_input(b)

func _motion(pos: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = pos
	m.global_position = pos
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_tree().root.push_input(m)

## 收起宿主上所有详解卡（含正在淡出的旧卡）并等它们真的离树：
## 淡出期间那块全屏遮罩还在树里，会把下一枪测成「遮罩上能不能滑」这种假问题。
func _wait_tips_gone(host: Control) -> void:
	DetailTip.close_all(host)
	for _i in range(40):
		var any := false
		for c in host.get_children():
			if c is DetailTip:
				any = true
		if not any:
			return
		await get_tree().process_frame
	push_warning("详解卡 40 帧还没收干净，后续落点不可信")

# ============================ 共用几何尺 ============================

## 可取样区 = 控件矩形 ∩ 滚动容器露出来的那块，再缩 2（斜切尖角本来就不在可点区里）
func _reachable_rect(zone: Control) -> Rect2:
	var r := zone.get_global_rect()
	var scroll := _scroll_of(zone)
	if scroll != null:
		var vis: Rect2 = scroll.get_global_rect()
		var bar := scroll.get_v_scroll_bar()
		if bar != null and bar.visible:
			vis.size.x -= bar.size.x
		r = r.intersection(vis)
	if r.size.x <= 4.0 or r.size.y <= 4.0:
		return Rect2()
	return r.grow(-2.0)

func _scroll_of(node: Node) -> ScrollContainer:
	var p := node.get_parent()
	while p != null:
		if p is ScrollContainer:
			return p as ScrollContainer
		p = p.get_parent()
	return null

func _hot_zones(root: Node) -> Array[Control]:
	var out: Array[Control] = []
	_collect(root, out)
	return out

func _collect(node: Node, out: Array[Control]) -> void:
	if node is Control and node.has_meta("tip_title") and node.is_visible_in_tree():
		out.append(node as Control)
	for ch in node.get_children():
		_collect(ch, out)

func _settle(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

# ================================ 反例 ================================

## 判据自己得拦得住东西：把「修复前的形状」掺进同一块地方打同一枪，必须报出问题。
## 反例① 顺带证明「划动那一枪的松开确实送到了行上」—— 否则「划动没弹卡」可能只是因为
## 抬起落在了行外面，整条判据就成了自证。
func _selftest() -> void:
	_c.check(GameStyle.TAP_SLACK > JITTER and GameStyle.TAP_SLACK < SWIPE,
		"容差 %.0f 夹在「手指微动 %.0f」与「有意划动 %.0f」之间" % [GameStyle.TAP_SLACK, JITTER, SWIPE])

	# 反例①：旧写法 —— 只认「左键松开」
	var old := _decoy()
	old.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
			_pop(old, "反例① 旧写法")
	)
	_c.check(await _swipe_at(_dlg, DECOY_RECT.get_center(), SWIPE) == "反例① 旧写法",
		"反例① 旧写法在「划动后松手」会弹卡 —— 这条尺子抓得住（抓不住说明抬起没送到行上）")
	_c.check(await _tap_at(_dlg, DECOY_RECT.get_center()) == "反例① 旧写法",
		"反例① 同一张卡原地微动后松手也算点着（旧写法唯一可取处，新写法不许丢）")

	# 正例：新写法 —— 划动不算点，点按算
	var new := _decoy()
	GameStyle.tap(new, func() -> void: _pop(new, "正例 新写法"))
	_c.check(await _swipe_at(_dlg, DECOY_RECT.get_center(), SWIPE) == "",
		"正例 GameStyle.tap 在「划动后松手」不弹卡")
	_c.check(await _tap_at(_dlg, DECOY_RECT.get_center()) == "正例 新写法",
		"正例 GameStyle.tap 原地点按仍然弹卡")

	# 反例②：只收到松开、从没在本热区按下过（按下点在别处）—— 不算点按
	var loose := _decoy()
	GameStyle.tap(loose, func() -> void: _pop(loose, "反例② 只给松开"))
	await _wait_tips_gone(_dlg)
	loose.emit_signal("gui_input", _release_event())
	await get_tree().process_frame
	var opened := DetailTip.live(_dlg) != null
	DetailTip.close_all(_dlg)
	await _wait_tips_gone(_dlg)
	_c.check(not opened, "反例② 没按下过、只送到一次松开 —— 不算这一块的点按")

func _decoy() -> Control:
	if _decoy_node != null and is_instance_valid(_decoy_node):
		_decoy_node.free()	# 同一坐标只留一张，别靠 z 序撞车
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_theme_stylebox_override("panel",
		GameStyle.block(GameStyle.NAVY2, GameStyle.SLANT_BLOCK, Vector2(2, 2)))
	box.position = DECOY_RECT.position
	box.size = DECOY_RECT.size
	_dlg.add_child(box)
	_decoy_node = box
	return box

func _release_event() -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.global_position = DECOY_RECT.get_center()
	ev.position = ev.global_position
	return ev

func _pop(anchor: Control, title: String) -> void:
	DetailTip.show_over(_dlg, anchor, {
		"title": title,
		"body": "判据自己造的假卡，只用来验尺子有没有牙齿。",
	})
