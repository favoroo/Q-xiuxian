extends Node

## 图鉴「整格可点」判据：一张卡里不许存在「点了没反应」的地方。
## 运行: $G --headless --path . res://tests/ManualHotzoneCheck.tscn
##       $G --headless --path . res://tests/ManualHotzoneCheck.tscn -- --selftest  （验判据有牙齿）
##
## 为什么立这条判据（用户 2026-10-09 真机图：法宝图鉴里点名字弹卡、点图片没反应）：
##  ① 卡本体是 PanelContainer + gui_input，而卡里那层 48×48 的图框**也是** PanelContainer。
##     PanelContainer 的 mouse_filter 默认就是 STOP，事件在它那一层就被截走了，永远到不了卡。
##     于是「整格可点」在代码里看着成立，真机上只有文字那一小块点得动 —— 而卡上写着
##     「点按任意法宝卡查看效果」，做不到的那半截就是坏功能，不是待优化。
##  ② 已有的 StatsTipCheck 是直接 `emit_signal("gui_input")`，绕过了引擎的命中测试，
##     所以它量不出「热区里被挖了个洞」：信号照样发、卡照样弹、判据照样全绿。
##     本判据改用 `viewport.push_input()` 打真实坐标，走真机上同一套拾取，
##     洞在哪儿就报在哪儿，还把截走事件的那一层节点名字打出来。
##
## 尺子取引擎自己的账（控件 global rect、ScrollContainer 的可见区、push_input 的真实落点），
## 不另抄一份布局算式 —— 抄一份就会和代码同时错。

## 取样密度：4×3 网格已盖住「图框 / 名字 / 副标签」三条横带
const COLS := 4
const ROWS := 3
## 四周缩进：斜切面板的尖角本来就不在可点区里，别拿它冤枉人
const INSET := 2.0
## 桌面调试分辨率（AGENTS.md 口径）。headless 下 root window 默认只有 64×64，
## 落点超出视口的点击会被引擎直接判成「点在窗外」，一枪都打不中 —— 必须先开尺寸。
const VIEWPORT_SIZE := Vector2i(960, 540)

var _c := TestCheck.new()
var _manual: ManualDialog
var _taps := 0

func _ready() -> void:
	if "--selftest" in OS.get_cmdline_user_args():
		await _selftest()
		get_tree().quit(0 if _c.report("HOTZONE_SELFTEST_RESULT") else 1)
		return
	await _run()
	get_tree().quit(0 if _c.report("HOTZONE_RESULT") else 1)

# ================================ 正判 ================================

func _run() -> void:
	get_tree().root.size = VIEWPORT_SIZE
	_manual = ManualDialog.new()
	add_child(_manual)
	_manual.open()
	await _settle(3)
	var cards := 0
	for tab in [1, 2]:
		_manual._switch_tab(tab)
		await _settle(3)
		var tag := "法器图鉴" if tab == 1 else "法宝图鉴"
		var zones := _hot_zones(_manual)
		_c.check(zones.size() >= 10, "%s：%d 张卡都登记了热区" % [tag, zones.size()])
		cards += zones.size()

		# ① 结构性检查：卡里有没有会截走事件的容器（先把责任层点名打出来）
		var holes: Array[String] = []
		for z in zones:
			for bad in _blocking_descendants(z):
				holes.append("%s「%s」内 %s 是 STOP，会截走点击" % [tag, z.get_meta("tip_title"), bad])
		for h in holes.slice(0, 8):
			print("    " + h)
		_c.check(holes.is_empty(), "%s：卡内没有任何一层容器截事件（洞 %d 处）" % [tag, holes.size()])

		# ② 行为检查：真打坐标，逐点问「这一枪弹没弹出它自己的卡」
		var errs: Array[String] = await _sweep(zones, tag)
		_c.check(errs.is_empty(), "%s：%d 张卡每格 %d 个取样点全点得动（死点 %d 个）" % [
			tag, zones.size(), COLS * ROWS, errs.size()])
		for e in errs.slice(0, 10):
			print("    " + e)
	_c.check(_manual.visible, "全程没被误点关掉（扫 %d 张卡、实打 %d 次）" % [cards, _taps])

## 逐张卡把取样点打一遍，返回问题清单（空 = 全绿）
func _sweep(zones: Array[Control], tag: String) -> Array[String]:
	var errs: Array[String] = []
	for z in zones:
		errs.append_array(await _sweep_zone(z, tag))
	return errs

func _sweep_zone(zone: Control, tag: String) -> Array[String]:
	var errs: Array[String] = []
	var want := String(zone.get_meta("tip_title"))
	await _bring_into_view(zone)
	var box := _reachable_rect(zone)
	if box.size.x <= 0.0 or box.size.y <= 0.0:
		errs.append("%s「%s」滚不进可视区（点不到 = 等于没有这个热区）" % [tag, want])
		return errs
	for ci in range(COLS):
		for ri in range(ROWS):
			var p := Vector2(
				box.position.x + box.size.x * (ci + 0.5) / COLS,
				box.position.y + box.size.y * (ri + 0.5) / ROWS)
			var tip: DetailTip = await _tap(p)
			_taps += 1
			if tip == null:
				errs.append("%s「%s」点 (%.0f,%.0f) 没反应，事件被 %s 截走" % [
					tag, want, p.x, p.y, _picker(p)])
			elif String(tip.payload.get("title", "")) != want:
				errs.append("%s 点 (%.0f,%.0f) 弹错了卡：期望「%s」实得「%s」" % [
					tag, p.x, p.y, want, String(tip.payload.get("title", ""))])
			await _dismiss()
	return errs

## 把热区滚进可视区，并等它**真的停住**：滚动是带补间的，只等固定帧数会读到飞行中的矩形，
## 下一枪就打在已经移走的位置上（判据自己先错，比漏判更糟）。
func _bring_into_view(zone: Control) -> void:
	var scroll := _scroll_of(zone)
	if scroll == null:
		return
	scroll.ensure_control_visible(zone)
	var last := Rect2(-1.0, -1.0, 0.0, 0.0)
	for _i in range(30):
		await get_tree().process_frame
		var r := zone.get_global_rect()
		if r == last:
			return
		last = r

## 可取样区 = 卡自己的矩形 ∩ 滚动容器露出来的那块，再缩 INSET。
## 滚动条压在右侧那一竖条不是卡的锅，剔掉。
func _reachable_rect(zone: Control) -> Rect2:
	var r := zone.get_global_rect()
	var scroll := _scroll_of(zone)
	if scroll != null:
		var vis: Rect2 = scroll.get_global_rect()
		var bar := scroll.get_v_scroll_bar()
		if bar != null and bar.visible:
			vis.size.x -= bar.size.x
		r = r.intersection(vis)
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return Rect2()
	return r.grow(-INSET)

## 真发一次左键按下+松开（同一坐标），返回宿主上当初那张活卡
func _tap(pos: Vector2) -> DetailTip:
	_press(pos, true)
	_press(pos, false)
	await get_tree().process_frame
	return DetailTip.live(_manual)

func _press(pos: Vector2, down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = pos
	ev.global_position = pos
	ev.pressed = down
	get_tree().root.push_input(ev)

## 收起上一张卡，并等它**真的从树上下来**：详解卡是一块全屏遮罩 + 一张卡，
## 遮罩还在 = 下一枪打在遮罩上（判据自己造出死点，比漏判更糟）。
## 所以走正常 close()（会把 _closing 置上、0.1 秒淡出后 free），再轮询到节点没了为止。
func _dismiss() -> void:
	DetailTip.close_all(_manual)
	for _i in range(30):
		await get_tree().process_frame
		var any := false
		for c in _manual.get_children():
			if c is DetailTip:
				any = true
		if not any:
			return
	push_error("详解卡 30 帧还没收干净，后续点击不可信")

## 那一枪打空时，按「矩形 + mouse_filter」找出最里面那层会截住事件的控件。
## 4.7 没把 gui_find_control 开放给 GDScript，所以这里只做事后诊断，
## 判据的牙齿仍然在 push_input 那一枪（走的是引擎真正的拾取）。
func _picker(pos: Vector2) -> String:
	var hit := _deepest_stop(_manual, pos, "ManualDialog")
	return hit if hit != "" else "没有控件收得到"

func _deepest_stop(node: Control, pos: Vector2, path: String) -> String:
	var found := ""
	if node.is_visible_in_tree() and node.mouse_filter == Control.MOUSE_FILTER_STOP \
			and node.get_global_rect().has_point(pos):
		found = "%s[%s] %s" % [path, node.get_class(), node.get_global_rect()]
	for ch in node.get_children():
		if ch is Control:
			var sub := _deepest_stop(ch as Control, pos, "%s/%s" % [path, String(ch.name)])
			if sub != "":
				found = sub
	return found

## 热区：登记了 tip_title 的控件。图鉴卡由 _make_entry_card 打标，
## 属性面板的详解行由 _make_tip_row 打标 —— 同一把尺子量两处。
func _hot_zones(root: Node) -> Array[Control]:
	var out: Array[Control] = []
	_collect(root, out)
	return out

func _collect(node: Node, out: Array[Control]) -> void:
	if node is Control and node.has_meta("tip_title") and node.is_visible_in_tree():
		out.append(node as Control)
	for ch in node.get_children():
		_collect(ch, out)

## 卡内所有 STOP 的子孙 = 会把事件截在卡之外的洞。
## Label 默认 IGNORE、各类容器默认 PASS，两者都往上传，只有 STOP 真的挡住。
func _blocking_descendants(zone: Control) -> Array[String]:
	var out: Array[String] = []
	for ch in zone.get_children():
		if not (ch is Control):
			continue
		var c := ch as Control
		if c.mouse_filter == Control.MOUSE_FILTER_STOP:
			out.append("%s[%s]" % [String(c.name), c.get_class()])
		out.append_array(_blocking_descendants(c))
	return out

func _scroll_of(node: Node) -> ScrollContainer:
	var p := node.get_parent()
	while p != null:
		if p is ScrollContainer:
			return p as ScrollContainer
		p = p.get_parent()
	return null

func _settle(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

# ================================ 反例 ================================

## 判据自己得拦得住东西：在同一张页面上掺一张「图框会截事件」的坏卡（修复前的法宝卡形状），
## 它必须只报这张坏卡，不许冤枉旁边的好卡。
func _selftest() -> void:
	get_tree().root.size = VIEWPORT_SIZE
	_manual = ManualDialog.new()
	add_child(_manual)
	_manual.open()
	await _settle(3)
	_manual._switch_tab(2)
	await _settle(3)

	var bad := _make_card_replica("BadCard", "反例卡")
	_manual._items_box.add_child(bad)
	await _settle(3)

	var holes := _blocking_descendants(bad)
	_c.check(holes.size() == 1, "反例① 卡内那层图框被点名（%s）" % str(holes))
	var errs: Array[String] = await _sweep([bad] as Array[Control], "反例")
	_c.check(not errs.is_empty(), "反例② 图框那一枪打空被抓住（%d 条）" % errs.size())
	for e in errs.slice(0, 6):
		print("    " + e)
	# 牙齿要指得准：坏在图框那一块，文字那一块本来就得放行。
	# 读数一律在收起卡之前取成字符串 —— 卡节点随后就 queue_free 了，攥着引用比 null 会读成假空。
	var on_icon := await _tap_node(bad, bad.get_node("VBox/IconCenter/IconBox"))
	_c.check(on_icon == "", "反例③ 打在图框上没反应（这就是真机那条毛病，实得「%s」）" % on_icon)
	var on_name := await _tap_node(bad, bad.get_node("VBox/NameLabel"))
	_c.check(on_name == "反例卡", "反例④ 打在名字上照旧弹卡 —— 判据没把好的也冤枉（实得「%s」）" % on_name)

	# 正例：同一张卡按 hotzone 口径重铺一遍子孙，判据必须放行
	var good := _make_card_replica("GoodCard", "正例卡")
	GameStyle.hotzone(good)
	_manual._items_box.add_child(good)
	await _settle(3)
	_c.check(_blocking_descendants(good).is_empty(), "正例⑤ 走完 hotzone 的卡内没有截事件的层")
	var clean: Array[String] = await _sweep([good] as Array[Control], "正例")
	_c.check(clean.is_empty(), "正例⑥ 整格逐点打下来都弹得出卡")

## 复刻修复前图鉴卡的结构：图框 + 名字，整块 PanelContainer 收事件。
## 节点名一律 ASCII —— Godot 的 add_child 会把非标识符字符改掉，诊断串里就认不出是谁了。
func _make_card_replica(node_name: String, title: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = node_name
	card.custom_minimum_size = Vector2(148, 0)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.set_meta("tip_title", title)
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)
	var center := CenterContainer.new()
	center.name = "IconCenter"
	var icon_box := PanelContainer.new()
	icon_box.name = "IconBox"
	icon_box.custom_minimum_size = Vector2(48, 48)
	center.add_child(icon_box)
	vbox.add_child(center)
	var lbl := Label.new()
	lbl.name = "NameLabel"
	lbl.text = title
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl)
	card.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
			DetailTip.show_over(_manual, card, {"title": title, "rows": [["x", "1"]]})
	)
	return card

## 打在某个控件的正中间（先把热区滚进可视区），返回弹出来的那张卡的标题（没弹 = 空串）。
## 只回字符串：卡收起时节点会被 free，把引用带出这个函数就是拿一个「看起来像 null 的废引用」去比。
func _tap_node(zone: Control, target: Control) -> String:
	await _bring_into_view(zone)
	var tip: DetailTip = await _tap(target.get_global_rect().get_center())
	var got := "" if tip == null else String(tip.payload.get("title", ""))
	await _dismiss()
	return got
