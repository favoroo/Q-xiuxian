extends Node

## 判据：开局「选择角色」右侧修士列表 —— 划一下不许换人，点一下必须换对人。
## 运行: $G --headless --path . res://tests/RosterTapCheck.tscn
##       $G --headless --path . res://tests/RosterTapCheck.tscn -- --selftest  （验判据有牙齿）
##
## 为什么单独测这一屏（用户 2026-10-12 真机：「右侧人物列表我去滑动的时候有时候会触发它那个
## 点击，会点中某个英雄，然后滑动的时候感觉不是很流畅」）：
## 这一屏是 2026-10-09 那轮「滚动区里能滑 / 不许误触」收口时的漏网之鱼 —— 别的卡片都换成了
## GameStyle.tap（认完整手势），它这里还认「按下」那一枪，于是手指一落到卡片上就换人：
##  ① 想滑动 = 点中了某个英雄（还白响一声 ui_click）；
##  ② 换人要重建左侧整栏详情（实测平均 4.0ms、最坏 6.0ms 纯 CPU，真机更慢），
##     而这一下正好砸在 ScrollContainer 起手锁定拖动的那一帧 ⇒ 滑动发涩。
## 「误触」和「不流畅」是同一条根因的两面，所以两条判据打在同一个动作上。
##
## 尺子从生产入口进（show_select → 真发按下-移动-抬起），读的是这一屏自己的状态
## _selected_id 与卡片底色，不另抄一份热区表。
## 注意：ScrollContainer 的触摸拖动整段被 is_touchscreen_available() 门控，headless 里
## 列表不会被真的拖走 —— 所以本判据量的是「点按识别器认不认这一枪」，
## 「按下能不能起手拖动」由 ScrollSwipeCheck 负责（它已把这一屏列入 CASES）。
##
## 防假 PASS：
## ① 界面没建起来 / 列表根本没超出可视高度（等于没有滑动这回事）/ 采到的卡不够 → FAIL；
## ② 「划动没换人」也可能是抬起落在了卡外面谁都没收到 → --selftest 在同一坐标掺一张
##    修复前写法（认按下）的假卡，要求它被抓出来，才证明那一枪确实送到了卡上。

const VP := Vector2(1202, 540)
## 有意划动：必须明显大于 GameStyle.TAP_SLACK，否则测的不是「划」
const SWIPE := 70.0
## 手指按在原地的一点微动：必须明显小于容差，否则「根本点不动」也会被判成通过
const JITTER := 4.0
## 至少采几张卡、每张横着切几列：只点中心会被卡里的头像框冤枉成没问题
const MIN_CARDS := 4
const SAMPLE_COLS := 3
## 两条路径各自至少要记的账：项数骤降说明脚本中途炸了，那不是通过
const RUN_ITEMS := 30
const SELF_ITEMS := 4

var _c := TestCheck.new()
var _sel: CultivatorSelect
var _decoy_node: Control
var _decoy_hit := false

func _ready() -> void:
	get_tree().root.size = Vector2i(int(VP.x), int(VP.y))
	GameManager.reset_run()
	_sel = CultivatorSelect.new()
	add_child(_sel)
	_sel.show_select()
	await _settle(8)
	var is_self := "--selftest" in OS.get_cmdline_user_args()
	if is_self:
		await _selftest()
	else:
		await _run()
	# 判据中途炸掉照样会走到这里收尾：半截账不许报绿（踩过「ALL PASS（0 项）」那种空转）
	var items := _c.passed + _c.failures.size()
	var floor_items := SELF_ITEMS if is_self else RUN_ITEMS
	_c.check(items >= floor_items,
		"本轮记了 %d 项账（≥%d 才算尺子跑完了，不是中途报错空转）" % [items, floor_items])
	get_tree().quit(0 if _c.report("ROSTER_TAP_RESULT") else 1)

# ================================ 正判 ================================

func _run() -> void:
	var sc := _sel._roster_scroll
	var grid := _sel._roster_grid
	var n := grid.get_child_count() if grid != null else 0
	_c.check(sc != null and n >= 8, "右侧列表铺出 %d 张修士卡（≥8 才算界面真建起来）" % n)
	if sc == null or grid == null:
		return
	# 列表得真摆不下，否则「划」这个动作在这屏不存在，两枪都测不到东西
	var content_h := maxf(grid.size.y, grid.get_combined_minimum_size().y)
	_c.check(content_h > sc.size.y + 2.0,
		"列表内容 %.0f 高出可视 %.0f ⇒ 这一屏确实需要滑" % [content_h, sc.size.y])

	var picked: Array = _cids_in_view(sc)
	_c.check(picked.size() >= MIN_CARDS, "可视区里采到 %d 张卡可测（≥%d 才算测到东西）" % [
		picked.size(), MIN_CARDS])

	for cid_s in picked:
		var cid := String(cid_s)
		# 每一枪前把列表归零并现读矩形：上一枪万一真把列表拖走了，抄旧坐标会打在邻卡上
		var box := _box_of(sc, cid)
		if box.size.x <= 0.0:
			_c.check(false, "「%s」这一轮没落在可视区里（坐标不可信）" % cid)
			continue
		var style: StyleBoxFlat = _sel._roster_cards[cid]["style"]

		# ---- ① 划一下：不许换人 ----
		# 先把基准钉在「另一张卡」上：划的就是当前已选那张时，旧写法也不会换人，那枪是自证的
		var baseline := _other_than(cid)
		_sel._select_cultivator(baseline)
		await _settle(2)
		var rest_col := style.bg_color
		var down_col := rest_col
		_btn(box.get_center(), true)
		await get_tree().process_frame
		down_col = style.bg_color
		_motion(box.get_center() + Vector2(0, -SWIPE * 0.5))
		await get_tree().process_frame
		_motion(box.get_center() + Vector2(0, -SWIPE))
		await get_tree().process_frame
		_btn(box.get_center() + Vector2(0, -SWIPE), false)
		await _settle(2)
		_c.check(_sel._selected_id == baseline,
			"「%s」上手指划 %.0f 单位后没换人（实得「%s」）" % [cid, SWIPE, _sel._selected_id])
		# 按下要立刻亮（反馈不等抬手），抬起后要交还给「选中态」那唯一真话，不许留一颗亮着的卡
		_c.check(down_col != rest_col, "「%s」按下那一刻底色变亮（%s → %s）" % [
			cid, rest_col.to_html(false), down_col.to_html(false)])
		style.bg_color = Color.MAGENTA          # 故意破坏，验恢复走的是同一条真话
		_sel._update_small_card_selection(cid)
		_c.check(_same_color(style.bg_color, rest_col),
			"「%s」抬起后底色由选中态重算回来（按下没留在卡上）" % cid)

		# ---- ② 点一下：必须换对这张人，且整块没有死点 ----
		for ci in range(SAMPLE_COLS):
			var p := Vector2(box.position.x + box.size.x * (ci + 0.5) / SAMPLE_COLS,
				box.get_center().y)
			_sel._select_cultivator(baseline)
			await _settle(2)
			await _tap(p)
			_c.check(_sel._selected_id == cid,
				"「%s」第 %d 列点按选中它（实得「%s」）" % [cid, ci + 1, _sel._selected_id])

## 横切三列点一次：按下 → 抖 JITTER → 抬起，等于玩家那一下点按
func _tap(p: Vector2) -> void:
	_btn(p, true)
	await get_tree().process_frame
	_motion(p + Vector2(0, JITTER))
	await get_tree().process_frame
	_btn(p + Vector2(0, JITTER), false)
	await _settle(2)

## 列表里前若干张卡：只认此刻在可视区里还有交叠的
func _cids_in_view(sc: ScrollContainer) -> Array:
	var out: Array = []
	for cid in _sel._roster_cards.keys():
		if _box_of(sc, String(cid)).size.y >= 8.0:
			out.append(String(cid))
		if out.size() >= MIN_CARDS + 2:
			break
	return out

## 一张卡当前可打到的矩形 = 卡片矩形与滚动区露出来那块的重叠，再缩 2
## （斜切卡片的尖角本来就不在可点区里，打在角上会被判成「谁都没收到」）
func _box_of(sc: ScrollContainer, cid: String) -> Rect2:
	sc.scroll_vertical = 0
	var card := (_sel._roster_cards.get(cid, {}) as Dictionary).get("card") as Control
	if card == null or not card.is_visible_in_tree():
		return Rect2()
	var box := card.get_global_rect().intersection(sc.get_global_rect())
	if box.size.x <= 4.0 or box.size.y <= 4.0:
		return Rect2()
	return box.grow(-2.0)

## 列表里除 cid 之外的一张卡：拿它当「划之前是谁」的基准
func _other_than(cid: String) -> String:
	for k in _sel._roster_cards.keys():
		if String(k) != cid:
			return String(k)
	return cid

# ================================ 反例 ================================

## 判据自己得拦得住东西：把「修复前的形状」（认按下那一枪）原样摆在同一个坐标上，
## 同一把划动必须让它换人 —— 否则「划动没换人」可能只是因为那一枪谁都没收到。
func _selftest() -> void:
	_c.check(GameStyle.TAP_SLACK > JITTER and GameStyle.TAP_SLACK < SWIPE,
		"容差 %.0f 夹在「手指微动 %.0f」与「有意划动 %.0f」之间" % [
			GameStyle.TAP_SLACK, JITTER, SWIPE])
	var sc := _sel._roster_scroll
	if sc == null:
		_c.check(false, "反例：右侧滚动区没建起来（多半是编译失败，别当通过）")
		return
	var vis := sc.get_global_rect()
	if vis.size.x < 100.0 or vis.size.y < 100.0:
		_c.check(false, "反例：滚动区可视矩形 %s，界面没铺出来" % str(vis.size))
		return
	var at := vis.get_center()

	# 反例：旧写法 —— 认「按下」那一枪
	var old := _decoy(vis)
	old.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			_hit("反例 旧写法（认按下）")
	)
	_btn(at, true)
	await get_tree().process_frame
	_motion(at + Vector2(0, -SWIPE))
	await get_tree().process_frame
	_btn(at + Vector2(0, -SWIPE), false)
	await _settle(2)
	_c.check(_decoy_hit,
		"反例 旧写法在「划动」中被抓出来 —— 这条尺子抓得住（抓不住说明那一枪没送到卡上）")

	# 正例：新写法 —— 划动不算点，点按照旧算
	_decoy_hit = false
	var neu := _decoy(vis)
	GameStyle.tap(neu, func() -> void: _hit("正例 GameStyle.tap"))
	_btn(at, true)
	await get_tree().process_frame
	_motion(at + Vector2(0, -SWIPE))
	await get_tree().process_frame
	_btn(at + Vector2(0, -SWIPE), false)
	await _settle(2)
	_c.check(not _decoy_hit, "正例 GameStyle.tap 在「划动后松手」不兑现")
	_decoy_hit = false
	await _tap(at)
	_c.check(_decoy_hit, "正例 GameStyle.tap 原地点按仍然兑现")

func _decoy(vis: Rect2) -> Control:
	if _decoy_node != null and is_instance_valid(_decoy_node):
		_decoy_node.free()      # 同一坐标只留一张，别靠 z 序撞车
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_theme_stylebox_override("panel",
		GameStyle.block(GameStyle.NAVY2, GameStyle.SLANT_BLOCK, Vector2(2, 2)))
	box.size = Vector2(200, 26)
	box.position = vis.get_center() - box.size * 0.5
	_sel.add_child(box)
	_decoy_node = box
	return box

func _hit(who: String) -> void:
	_decoy_hit = true
	print("  DECOY_HIT ", who)

## 底色逐分量比：同一个常量算出来的色本来该严格相等，留一点余量只为报错信息比断言本身值钱
static func _same_color(a: Color, b: Color) -> bool:
	return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a))) < 0.001

# ============================ 输入与节拍 ============================

func _btn(pos: Vector2, down: bool) -> void:
	var b := InputEventMouseButton.new()
	b.button_index = MOUSE_BUTTON_LEFT
	b.position = pos
	b.global_position = pos
	b.pressed = down
	if down:
		b.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_window().push_input(b)

func _motion(pos: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = pos
	m.global_position = pos
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_window().push_input(m)

func _settle(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame
