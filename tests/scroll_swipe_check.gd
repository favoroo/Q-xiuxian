extends Node

## 判据：手册每一页的正文列，手指按在「任何一处」都要能让外层 ScrollContainer 起手锁定拖动。
##
## 为什么要单独测这个：Godot 4.7 的 ScrollContainer 实现拖动滚动靠的是
## 「左键按下那一拍 latch(drag_touching) + 之后的 MouseMotion 累加 relative」
## （scene/gui/scroll_container.cpp:237-300，整段被 is_touchscreen_available() 门控；
## 真机上手指按下会转成模拟左键，所以这条链在 Android 上成立）。
## 而 PanelContainer / ColorRect / Control 的 mouse_filter 默认是 STOP，
## STOP 会把「按下」这一拍就地吃掉、不再向父级冒泡 —— 于是卡片盖住多大面积就滑不动多大面积，
## 只有卡片缝隙（VBoxContainer 是 PASS）能滑。
## 用户 2026-10-09 真机：传道玉简「灰色卡片滑不动、黑色区域能滑」就是这个。
## 修口：GameStyle.swipeable() 把滚动区里的装饰性 STOP 降成 PASS。
##
## 用法：$G --headless --path . res://tests/ScrollSwipeCheck.tscn
## 判据：退出码 0 且末行 SCROLL_SWIPE_RESULT: ALL PASS
## 防假 PASS：界面没建起来 / 一页采不到点 / 采到的点全落在缝隙上，都算 FAIL。

const VP := Vector2(1202, 540)
const PAGE_NAMES := ["入门指南", "法器图鉴", "法宝图鉴", "修士图鉴", "进阶心法"]
## 每页最少采几个落点、其中至少几个必须落在卡片本体上（否则等于没测到 STOP 那一类）
const MIN_SAMPLES := 3
const MIN_ON_CARD := 2
## 每页最多采多少个落点：卡片中心 + 卡片缝隙，够覆盖整列又不拖慢
const MAX_SAMPLES := 14

var _manual: ManualDialog
var _fail: Array[String] = []

func _ready() -> void:
	get_viewport().size = VP
	var main: Node = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	_manual = main.get_node("UILayer/ManualDialog") as ManualDialog
	_manual.open()
	for i in range(4):
		await get_tree().process_frame

	if _manual._pages.size() != PAGE_NAMES.size():
		_fail.append("手册没建起来：_pages=%d 期望=%d（多半是某个脚本编译失败，别当通过）" % [
			_manual._pages.size(), PAGE_NAMES.size()])
	else:
		for tab in range(PAGE_NAMES.size()):
			await _check_page(tab)

	await _report()

## 单页：先取整列采样点，再逐点喂「按下-抬起」，看 ScrollContainer 收不收得到按下
func _check_page(tab: int) -> void:
	_manual._switch_tab(tab)
	await get_tree().process_frame
	await get_tree().process_frame
	var scroll := _manual._pages[tab] as ScrollContainer
	if scroll == null:
		_fail.append("%s：这一页不是 ScrollContainer" % PAGE_NAMES[tab])
		return
	var box := scroll.get_child(0) as VBoxContainer
	if box == null or box.get_child_count() == 0:
		_fail.append("%s：滚动列里没有内容（界面没建起来）" % PAGE_NAMES[tab])
		return
	var points := _sample_points(scroll, box)
	var on_card := 0
	var got := 0
	for one in points:
		var p: Vector2 = one[0]
		if one[1]:
			on_card += 1
		if await _press_at(scroll, p):
			got += 1
		else:
			_fail.append("%s：落点 %s 按在「%s」上，ScrollContainer 没收到按下 → 这一处滑不动" % [
				PAGE_NAMES[tab], str(p), _eater_at(p)])
	print("CHECK %-6s 采样 %2d 点（卡片上 %d），可起手拖动 %2d 点" % [
		PAGE_NAMES[tab], points.size(), on_card, got])
	if points.size() < MIN_SAMPLES:
		_fail.append("%s：只采到 %d 个落点，测不到东西" % [PAGE_NAMES[tab], points.size()])
	if on_card < MIN_ON_CARD:
		_fail.append("%s：落在卡片本体上的点只有 %d 个，这一页等于没测" % [PAGE_NAMES[tab], on_card])

## 采样：每张卡片的中心（标记 on_card=true）+ 相邻卡片之间的缝隙中点，限制在可视高度内
func _sample_points(scroll: ScrollContainer, box: VBoxContainer) -> Array:
	var vis := scroll.get_global_rect()
	var out: Array = []
	var rects: Array[Rect2] = []
	for ch in box.get_children():
		var c := ch as Control
		if c == null or not c.visible:
			continue
		rects.append(c.get_global_rect())
	var cx := vis.get_center().x
	for i in range(rects.size()):
		if out.size() >= MAX_SAMPLES:
			break
		var r := rects[i]
		if r.intersects(vis):
			out.append([Vector2(cx, clampf(r.get_center().y, vis.position.y + 4.0, vis.end.y - 4.0)), true])
		if i + 1 < rects.size():
			var gap_y := (r.end.y + rects[i + 1].position.y) * 0.5
			if gap_y > vis.position.y and gap_y < vis.end.y:
				out.append([Vector2(cx, gap_y), false])
	return out

## 喂一次按下+移动+抬起，返回 ScrollContainer 是否收到那一拍按下
func _press_at(scroll: ScrollContainer, pos: Vector2) -> bool:
	var hits := [0]
	var callable := func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			hits[0] += 1
	# 图鉴卡松手会弹详解，详解自带全屏 STOP 遮罩会盖住下一个落点 → 每一枪前先等它离树，
	# 否则测的是「详解卡上能不能滑」这种假问题（收起是 0.1s 淡出，固定等几帧不可靠）。
	await _wait_tips_gone()
	scroll.gui_input.connect(callable)
	_btn(pos, true)
	await get_tree().process_frame
	_motion(pos + Vector2(0, -24))
	await get_tree().process_frame
	_btn(pos + Vector2(0, -24), false)
	await get_tree().process_frame
	scroll.gui_input.disconnect(callable)
	DetailTip.close_all(_manual)
	scroll.scroll_vertical = 0
	await _wait_tips_gone()
	return hits[0] > 0

## 等宿主上所有详解卡（含正在淡出的旧卡）真的离开节点树
func _wait_tips_gone() -> void:
	DetailTip.close_all(_manual)
	for i in range(40):
		var any := false
		for c in _manual.get_children():
			if c is DetailTip:
				any = true
		if not any:
			return
		await get_tree().process_frame

func _btn(pos: Vector2, down: bool) -> void:
	var b := InputEventMouseButton.new()
	b.position = pos
	b.global_position = pos
	b.button_index = MOUSE_BUTTON_LEFT
	b.pressed = down
	if down:
		b.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_window().push_input(b)

func _motion(pos: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = pos
	m.global_position = pos
	m.relative = Vector2(0, -24)
	m.screen_relative = Vector2(0, -24)
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_window().push_input(m)

## 报是谁吃掉了那一拍：包含该点、且 mouse_filter 为 STOP 的最深控件
## （手写递归：find_children 的 owned 参数默认 true，代码 new() 出来的卡片 owner 为空会被漏掉）
func _eater_at(pos: Vector2) -> String:
	var best: Control = null
	var best_area := INF
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for ch in cur.get_children():
			stack.append(ch)
			var ctl := ch as Control
			if ctl == null or ctl.mouse_filter != Control.MOUSE_FILTER_STOP:
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

func _report() -> void:
	print("")
	if _fail.is_empty():
		print("SCROLL_SWIPE_RESULT: ALL PASS")
		get_tree().quit(0)
		return
	for f in _fail:
		print("FAIL " + f)
	print("SCROLL_SWIPE_RESULT: %d FAIL" % _fail.size())
	get_tree().quit(1)
