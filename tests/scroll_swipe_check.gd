extends Node

## 判据：全应用每一处滚动区，手指按在「卡片本体上」也要能让外层 ScrollContainer 起手锁定拖动。
## 运行: $G --headless --path . res://tests/ScrollSwipeCheck.tscn
##       $G --headless --path . res://tests/ScrollSwipeCheck.tscn -- --selftest  （验判据有牙齿）
##
## 为什么要单独测这个：Godot 4.7 的 ScrollContainer 实现拖动滚动靠的是
## 「左键按下那一拍 latch(drag_touching) + 之后的 MouseMotion 累加 relative」
## （scene/gui/scroll_container.cpp:237-300，整段被 is_touchscreen_available() 门控；
## 真机上手指按下会转成模拟左键，所以这条链在 Android 上成立）。
## 而 PanelContainer / ColorRect 的 mouse_filter 默认是 STOP，STOP 会把「按下」这一拍就地吃掉、
## 不再向父级冒泡 —— 卡片盖住多大面积就滑不动多大面积，只有卡片缝隙（Container 默认 IGNORE）能滑。
## 用户 2026-10-09 真机：传道玉简「灰色卡片滑不动、黑色区域能滑」；
## 用户 2026-10-10 真机：修仙志「只有手碰到那个黑色的间隔才能滑动，其他几个界面也是这样」。
## 修口：GameStyle.swipeable() 把滚动区里的装饰性 STOP 降成 PASS。
##
## 覆盖范围不抄名单：把每个弹窗建出来、页签逐个切过，再遍历子树里【现存】的每一个
## ScrollContainer 采样。新增一处滚动列表不用改本判据，它自己会被扫到 —— 漏调 swipeable 就报红。
## 判据从生产入口进（open / _switch_tab / 展开战报），量的是真机上手指会打到的那些坐标。
##
## 防假 PASS：
## ① 弹窗没建起来、页签没切到、一处真能滚的区域都扫不出来 → FAIL；
## ② 某区域采到的点太少、或全落在卡片缝隙上（等于没测到 STOP 那一类）→ FAIL；
## ③ 内容没超出可视高度（本来不需要滚）→ 跳过，不算通过也不算失败，但把两端的数打出来；
##    用例自己钉了 must_scroll 时，跳过就是数据没造够 → FAIL（悟道面板那一屏就钉着）；
## ④ --selftest 把一处本来能滑的卡片改回修复前的 STOP 形状，必须被这条尺子抓出来；
## ⑤ 落点取「每一格自己的中心 x」，不是滚动区中心 x：横排五张卡（悟道面板）只按中心 x 采
##    等于只测中间那一张。--selftest 另把最左那张换回 STOP，必须被抓出来，才证明这条采法活着。
##
## 用例字段：cls 脚本类名 / name 人话名 / switch 切页签的方法 / pages 页签名（与页签同序）；
## 可选 scene（按 .tscn 实例化，面板靠 @onready 取场景节点时必需）、entry（默认 open）、
## prep（本判据里的造数据方法，跑在 entry 之前）、rows（"一格一格"那层的属性名）、
## settle_sec（入场动画等头）、must_scroll、sliders、expand。

const VP := Vector2(1202, 540)
## 每处滚动区最少采几个落点、其中至少几个必须落在内容卡片上（否则等于没测）
const MIN_SAMPLES := 3
const MIN_ON_CONTENT := 2
const MAX_SAMPLES := 12
## 按下后拖走的距离：够 ScrollContainer 认成拖动，又不会把落点拖出可视区
const DRAG := 24.0
## 全应用至少要扫出这么多处真能滚的区域：少于这个数说明有弹窗没建起来
const MIN_AREAS := 8

## 每个用例：脚本类名 / 人话名 / 切页签的方法 / 页签名（顺序与页签一致）
const CASES: Array[Dictionary] = [
	{
		"cls": "ManualDialog", "name": "传道玉简", "switch": "_switch_tab",
		"pages": ["入门指南", "法器图鉴", "法宝图鉴", "修士图鉴", "进阶心法"],
	},
	{
		"cls": "CareerDialog", "name": "修仙志", "switch": "_switch_tab",
		"pages": ["天道功绩", "道统功名", "渡劫实录"],
		# 第三页额外走一遍「展开战报」：详情面板是点开后另挂的 STOP 卡片，重建路径与 open 不同
		"expand": {"tab": 2, "label": "渡劫实录(展开)"},
	},
	{
		"cls": "SettingsDialog", "name": "游戏设置", "switch": "_switch_tab",
		"pages": ["灵音调律", "剑意视界", "演化推衍", "其他"],
		# 第一页有音量滑杆：卡片放开「按下」后，滑杆那一枪必须还吃得住（别拿能滑换拖不动滑杆）
		"sliders": true,
	},
	{
		"cls": "PlayerStatsDialog", "name": "属性面板", "switch": "_switch_bottom_tab",
		"pages": ["随身法宝", "悟道历程"],
	},
	{
		# 开局择选：右侧 19 张修士卡（hotzone 把整块压成热区后必须还能拖）+ 左侧详情特性列。
		# 入口不是 open 而是 show_select（它不是 BaseModalDialog，走自己的显隐）
		"cls": "CultivatorSelect", "name": "选择角色", "entry": "show_select",
		"switch": "", "pages": ["左右两栏"],
	},
	{
		# 波后悟道加点：5 张卡横排、卡高超出滚动区 ⇒ 必须每一处都划得起来
		# （用户 2026-10-12 真机：「手压在卡片上滑不动，要挪到侧面没有卡片遮挡的地方才能滑」）。
		# 面板靠 @onready 取场景节点，只能按 .tscn 实例化；候选与上阵法器由 _prep_alloc 钉成
		# 最占地方的一屏（随机 roll 撞出矮卡屏就等于空跑），开法走面板自己的那个信号回调。
		"cls": "LevelUpDialog", "name": "升级加点",
		"scene": "res://scenes/ui/LevelUpDialog.tscn", "prep": "_prep_alloc",
		"entry": "_on_alloc_opened", "switch": "", "pages": ["一屏候选"],
		"rows": "cards_container", "settle_sec": 1.0, "must_scroll": true,
	},
]

var _c := TestCheck.new()
var _areas := 0        ## 扫出的「真能滚」区域数
var _areas_ok := 0     ## 其中每一处落点都能起手拖动的区域数

func _ready() -> void:
	get_tree().root.size = VP
	process_mode = Node.PROCESS_MODE_ALWAYS
	_seed()
	for one_case in CASES:
		await _run_case(one_case)
	await _run_update_dialog()
	if "--selftest" in OS.get_cmdline_user_args():
		await _selftest()
		await _selftest_alloc()
	_c.check(_areas >= MIN_AREAS, "全应用扫出 %d 处真能滚的滚动区（≥%d 才算每个弹窗都走到）" % [
		_areas, MIN_AREAS])
	_c.check(_areas > 0 and _areas_ok == _areas, "%d/%d 处滚动区每一处落点都能起手拖动" % [_areas_ok, _areas])
	get_tree().quit(0 if _c.report("SCROLL_SWIPE_RESULT") else 1)

## 造真数据：让「渡劫实录 / 随身法宝 / 悟道历程」这些列表真有东西可滑。
## 战报快照走生产同一个 builder（ProgressStore._make_victory_snapshot），不另编字段。
func _seed() -> void:
	GameManager.reset_run()
	GameManager.cultivator_id = "shiyue"
	GameManager.kills = 820
	GameManager.level = 14
	GameManager.game_time = 735.0
	GameManager.danger_level = 1
	for id in ["atk_up", "melee_up", "armor_up", "speed_up", "hp_up", "haste_up"]:
		GameManager.apply_upgrade(id)
	for iid in ["jubaopen", "mibao_luopan", "qiankun_dai", "zhekou_yufu", "kuangxue_dan",
			"guijia_fu", "tongxuan_ling"]:
		GameManager.add_item(iid)
	for i in range(3):
		GameManager.victory_log.push_front(
			ProgressStore._make_victory_snapshot(GameManager, "shiyue", 20 - i))
		GameManager.run_history.push_front({
			"cultivator_id": "shiyue", "danger": 1, "wave": 18 - i, "kills": 700 - i * 40,
			"level": 13 - i, "victory": i == 0, "time": 700.0 - i * 30.0,
		})

# ================================ 逐个弹窗 ================================

func _run_case(one_case: Dictionary) -> void:
	var dlg := _make(one_case)
	if dlg == null:
		_c.check(false, "%s：脚本没建起来（多半是编译失败，别当通过）" % one_case["cls"])
		return
	add_child(dlg)
	await _settle(2)
	if one_case.has("prep"):
		await call(String(one_case["prep"]))   # 造真数据：候选钉最坏那一屏，见 _prep_alloc
	dlg.call(String(one_case.get("entry", "open")))   # Control 上没有 open，走动态调用
	await _settle(4)
	# 入场是错峰缩放 tween（0.8 → 1.0）：只等几帧量到的是缩小的中间帧，落定后的卡矩形才算数
	var sec := float(one_case.get("settle_sec", 0.0))
	if sec > 0.0:
		await get_tree().create_timer(sec).timeout
	var pages: Array = one_case["pages"]
	var switch_to := String(one_case["switch"])
	# 可选：点名「一格一格」的那一层（属性名，如悟道面板的 cards_container）
	var rows: Control = null
	if one_case.has("rows"):
		rows = dlg.get(String(one_case["rows"])) as Control
	for i in range(pages.size()):
		if switch_to != "":
			dlg.call(switch_to, i)
		await _settle(3)
		var swept := await _sweep(dlg, "%s·%s" % [String(one_case["name"]), String(pages[i])],
			rows, bool(one_case.get("must_scroll", false)))
		if bool(one_case.get("must_scroll", false)):
			# 空跑防线：这一屏真顶出滚动区才谈得上「滑不动」。数据没造够（候选太矮）时
			# 上面那枪会一处都不扫、只打一条 PASS，等于没测 —— 宁可红，不许静默跳过。
			_c.check(swept > 0, "%s：这一屏必须真需要竖滑（扫到 %d 处可滑区域，0 处就是数据没造够）" % [
				String(one_case["name"]), swept])
		if i == 0 and bool(one_case.get("sliders", false)):
			await _check_sliders(dlg, String(one_case["name"]))
		if switch_to != "" and int((one_case.get("expand", {}) as Dictionary).get("tab", -1)) == i:
			var ex: Dictionary = one_case["expand"]
			dlg.set("_expanded_log_idx", 0)
			dlg.call("_rebuild_log_list")
			await _settle(3)
			await _sweep(dlg, "%s·%s" % [String(one_case["name"]), String(ex["label"])], rows)
			dlg.set("_expanded_log_idx", -1)
			dlg.call("_rebuild_log_list")
	await _close(dlg)

## 更新弹窗不是 BaseModalDialog（没有 open/tab 那套），单独走它的真入口
func _run_update_dialog() -> void:
	var dlg := _make({"cls": "UpdateDialog"})
	if dlg == null:
		_c.check(false, "UpdateDialog：脚本没建起来")
		return
	add_child(dlg)
	var notes := ""
	for i in range(8):
		notes += "### 第 %d 条\n- 优化体验若干项\n" % (i + 1)
	dlg.call("popup_update", {
		"tag_name": "v0.0.99", "file_size_text": "42 MB", "release_notes": notes,
	})
	await _settle(4)
	await _sweep(dlg, "更新弹窗·更新日志")
	await _close(dlg)

## 建出被测弹窗：带 "scene" 的按 .tscn 实例化（面板靠 @onready 取场景节点，脚本 new() 出来
## 是一片空树，测不到东西），其余走脚本 new()
func _make(one_case: Dictionary) -> Control:
	var scene := String(one_case.get("scene", ""))
	if scene != "":
		var ps := load(scene) as PackedScene
		if ps == null:
			return null
		return ps.instantiate() as Control
	var scr := load("res://scripts/ui/%s.gd" % String(one_case["cls"])) as GDScript
	if scr == null:
		return null
	return scr.new() as Control

## 波后悟道面板的前置：真 Player + 上阵法器（受益装备那排图标会把卡撑高）+ 候选钉成最占地方
## 的一屏。不钉的话随机 roll 撞出「五张矮卡摆得下」的屏 ⇒ 本用例一处都扫不到，而扫不到是静默的
## （头注的防假 PASS：空跑必须报红，见 must_scroll）。
func _prep_alloc() -> void:
	var p := (load("res://scenes/entities/Player.tscn") as PackedScene).instantiate() as Player
	add_child(p)
	GameManager.player = p
	await _settle(3)
	for wid in ["qingyun_sword", "gengjin_feijian", "huoyan_fu", "wanmu_lingfu",
			"hunyuan_zhong", "lingdie"]:
		GameManager.add_weapon(wid)
	await _settle(3)
	GameManager.pending_upgrade_points = 2
	# 全表按「加成行数 → 说明字数」排，取最占地方那几条填满一屏（行数每多一条就多一行幅度
	# + 一行「当前 X → Y」注脚，正是用户那张图里 万灵朝元 顶出滚动区的形状）
	var scored: Array[String] = []
	for u in UpgradeData.UPGRADES:
		var apply: Dictionary = u.get("apply", {})
		if apply.is_empty():
			continue
		scored.append(String(u.get("id", "")))
	scored.sort_custom(func(a: String, b: String) -> bool:
		var wa: Dictionary = UpgradeData.get_upgrade_def(a)
		var wb: Dictionary = UpgradeData.get_upgrade_def(b)
		var sa: int = (wa.get("apply", {}) as Dictionary).size() * 1000 + String(wa.get("desc", "")).length()
		var sb: int = (wb.get("apply", {}) as Dictionary).size() * 1000 + String(wb.get("desc", "")).length()
		return sa > sb)
	var offers: Array[Dictionary] = []
	for i in range(GameManager.UPGRADE_OFFER_COUNT):
		var uid := scored[i % scored.size()]
		var d: Dictionary = UpgradeData.get_upgrade_def(uid).duplicate()
		d["border_color"] = UpgradeData.RARITY_COLORS.get(d.get("rarity", "common"), Color.WHITE)
		offers.append(d)
	GameManager.alloc_offers = offers

## 设置页的音量滑杆：行卡从 STOP 降成 PASS 后，「按在滑杆上」这一枪仍要由滑杆吃掉并定值 ——
## 不许拿「能滑」换「拖不动滑杆」。测完把四条总线音量原样写回，判据不许动用户真设置。
func _check_sliders(host: Control, label: String) -> void:
	var sliders: Array[HSlider] = []
	_collect_sliders(host, sliders)
	if sliders.is_empty():
		_c.check(false, "%s：这一页没找到滑杆（界面没建起来）" % label)
		return
	var saved: Dictionary = {}
	for bus in [&"Master", &"BGM", &"SFX", &"Voice"]:
		saved[bus] = SettingsManager.get_bus_volume(bus)
	var s := sliders[0]
	var was := s.value
	var want := 25.0
	if absf(was - want) < 20.0:
		want = 75.0
	var r := s.get_global_rect()
	var at := Vector2(r.position.x + r.size.x * (want / 100.0), r.get_center().y)
	_btn(at, true)
	await get_tree().process_frame
	_btn(at, false)
	await get_tree().process_frame
	_c.check(absf(s.value - want) <= 6.0 and s.value != was,
		"%s：卡片放开按下后，按在滑杆 %.0f%% 处仍定值（%.0f → %.0f）" % [label, want, was, s.value])
	for bus in saved.keys():
		SettingsManager.set_bus_volume(bus, float(saved[bus]))

func _collect_sliders(node: Node, out: Array[HSlider]) -> void:
	if node is HSlider and (node as Control).is_visible_in_tree():
		out.append(node as HSlider)
	for ch in node.get_children():
		_collect_sliders(ch, out)

func _close(dlg: Control) -> void:
	DetailTip.close_all(dlg)
	dlg.queue_free()
	await _settle(4)
	# 设置/属性面板会把游戏树暂停，留给下一个用例会看不清界面
	get_tree().paused = false

# ================================ 扫一处滚动区 ================================

## host 子树里每一个可见滚动区：逐落点喂「按下-拖动-抬起」，看 ScrollContainer 收不收得到按下。
## 返回这一趟真扫到几处「需要滚」的区域（用例据此判断自己有没有空跑，见 must_scroll）。
func _sweep(host: Control, label: String, rows: Control = null, must_scroll := false) -> int:
	var scrolls := _scrolls(host)
	_c.check(not scrolls.is_empty(), "%s：子树里找到 %d 个 ScrollContainer" % [label, scrolls.size()])
	var counted := 0
	for sc in scrolls:
		var content := _content_of(sc)
		if content == null:
			_c.check(false, "%s：%s 里没有内容控件（界面没建起来）" % [label, sc.name])
			continue
		if sc.size.y <= 1.0:
			_c.check(false, "%s：%s 高 %.0f，没布局出来（测不到东西）" % [label, sc.name, sc.size.y])
			continue
		if not _needs_scroll(sc, content):
			# 摆得下就不谈「滑不动」，但要把数打出来：用例钉了 must_scroll 时这是数据没造够
			print("SKIP  %-22s %s 内容 %.0f ≤ 滚动区 %.0f（这一屏本来不用滑）" % [
				label, sc.name, maxf(content.size.y, content.get_combined_minimum_size().y),
				sc.size.y])
			continue
		counted += 1
		_areas += 1
		var points := _sample_points(sc, content, rows)
		var on_content := 0
		var got := 0
		var bad: Array[String] = []
		for one in points:
			if one[1]:
				on_content += 1
			if await _press_at(sc, host, one[0]):
				got += 1
			else:
				bad.append("落点 %s 的「按下」被 %s 吃掉" % [str(one[0]), _eater_at(host, one[0])])
		var enough := points.size() >= MIN_SAMPLES and on_content >= MIN_ON_CONTENT
		var all_ok := enough and bad.is_empty()
		if all_ok:
			_areas_ok += 1
		_c.check(all_ok, "%s：%s 内容 %.0f/%.0f，采样 %d 点（卡片上 %d）→ %s" % [
			label, sc.name, content.size.y, sc.size.y, points.size(), on_content,
			("每一处都能起手拖动" if all_ok else ("；".join(bad) if enough else
				"落点太少（<%d 点或卡片上 <%d 个），等于没测" % [MIN_SAMPLES, MIN_ON_CONTENT])) as String])
		print("CHECK %-22s 采样 %2d 点（卡片上 %2d），可起手拖动 %2d 点" % [
			label, points.size(), on_content, got])
	return counted

## 内容是否真的摆不下（只有摆不下才谈得上「滑不动」）
func _needs_scroll(sc: ScrollContainer, content: Control) -> bool:
	if sc.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED:
		return false
	return maxf(content.size.y, content.get_combined_minimum_size().y) > sc.size.y + 2.0

## 滚动区的正文容器：第一个非滚动条的子控件（代码 new() 出来的卡片 owner 为空，
## find_children 的 owned 默认 true 会一个都找不到，所以全程手写递归）
func _content_of(sc: ScrollContainer) -> Control:
	for ch in sc.get_children():
		if ch is Control and not (ch is ScrollBar):
			return ch as Control
	return null

func _scrolls(root: Node) -> Array[Control]:
	var out: Array[Control] = []
	_collect_scrolls(root, out)
	return out

func _collect_scrolls(node: Node, out: Array[Control]) -> void:
	if node is ScrollContainer and (node as Control).is_visible_in_tree():
		out.append(node as Control)
	for ch in node.get_children():
		_collect_scrolls(ch, out)

## 采样：每张内容卡片在「与可视区的重叠带」里取点（标记 on_content=true）+ 相邻卡片之间的
## 缝隙中点，限在可视高度内。长卡要按重叠带切三段：传道玉简·进阶心法那一页整页就是一张
## 两千多单位高的长卡，只取中心等于一处滚动区只测了一个落点（判据自己据此判「等于没测」）。
## 横向取**这一格自己的中心 x**，不是滚动区中心 x：悟道面板那一屏是 5 张卡横排，全按中心 x
## 采等于只测了中间那一张，另外四张卡有没有吃掉「按下」没人知道。
func _sample_points(sc: ScrollContainer, content: Control, rows: Control = null) -> Array:
	var vis := sc.get_global_rect()
	var out: Array = []
	var rects: Array[Rect2] = []
	for ch in _rows_of(sc, content, rows).get_children():
		var c := ch as Control
		if c == null or not c.visible:
			continue
		rects.append(c.get_global_rect())
	for i in range(rects.size()):
		if out.size() >= MAX_SAMPLES:
			break
		var r := rects[i]
		var cx := clampf(r.get_center().x, vis.position.x + 4.0, vis.end.x - 4.0)
		var band := r.intersection(vis)
		if band.size.y > 0.0:
			# 重叠带高过 0.8 屏才值得切三段，否则一个中心点就够（切多了纯浪费点按次数）
			var cuts: Array = [0.5]
			if band.size.y >= vis.size.y * 0.8:
				cuts = [0.25, 0.5, 0.75]
			for f in cuts:
				if out.size() >= MAX_SAMPLES:
					break
				var y := clampf(band.position.y + band.size.y * f,
					vis.position.y + 4.0, vis.end.y - 4.0)
				if not _near_already(out, Vector2(cx, y)):
					out.append([Vector2(cx, y), true])
		if i + 1 < rects.size():
			var gap_y := (r.end.y + rects[i + 1].position.y) * 0.5
			var gp := Vector2(cx, gap_y)
			if gap_y > vis.position.y and gap_y < vis.end.y and not _near_already(out, gp):
				out.append([gp, false])
	return out

## 用例点名「一格一格」的那一层（悟道面板：CardScroll → CardsPad → CardsContainer，
## 直接子节点只有一张壳，按壳采等于只测一个落点）。没点名、或点名的不是这个滚动区里的，
## 一律退回滚动区的直接子节点 —— 别拿别的滚动区的格子来充数。
func _rows_of(sc: ScrollContainer, content: Control, rows: Control) -> Control:
	if rows == null or not is_instance_valid(rows) or rows.get_child_count() < 2:
		return content
	var p: Node = rows.get_parent()
	while p != null and p != content:
		p = p.get_parent()
	return (rows as Control) if p == content else content

## 同一处已经采过点了吗（横排五张卡同高、卡缝与卡心重合、长卡切三段挤在一起都会撞）
static func _near_already(points: Array, pos: Vector2) -> bool:
	for pt in points:
		if ((pt as Array)[0] as Vector2).distance_to(pos) < 6.0:
			return true
	return false

## 喂一次按下+拖动+抬起，返回 ScrollContainer 是否收到那一拍按下
func _press_at(sc: ScrollContainer, host: Control, pos: Vector2) -> bool:
	var hits := [0]
	var callable := func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			hits[0] += 1
	# 卡片松手可能弹详解，详解自带全屏 STOP 遮罩会盖住下一个落点 → 每一枪前先等它离树，
	# 否则测的是「详解卡上能不能滑」这种假问题（收起是淡出，固定等几帧不可靠）。
	await _wait_tips_gone(host)
	sc.gui_input.connect(callable)
	_btn(pos, true)
	await get_tree().process_frame
	_motion(pos + Vector2(0, -DRAG))
	await get_tree().process_frame
	_btn(pos + Vector2(0, -DRAG), false)
	await get_tree().process_frame
	sc.gui_input.disconnect(callable)
	DetailTip.close_all(host)
	sc.scroll_vertical = 0
	await _wait_tips_gone(host)
	return hits[0] > 0

## 等宿主上所有详解卡（含正在淡出的旧卡）真的离开节点树
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
	m.relative = Vector2(0, -DRAG)
	m.screen_relative = Vector2(0, -DRAG)
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_window().push_input(m)

## 报是谁吃掉了那一拍：包含该点、且 mouse_filter 为 STOP 的最小控件
func _eater_at(root: Node, pos: Vector2) -> String:
	var best: Control = null
	var best_area := INF
	var stack: Array[Node] = [root]
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
	# par.name 是 StringName，与 String 字面量在三元里类型不互容（4.7 告警即错误），拆开写
	if par == null:
		return "非 STOP 控件(无父)"
	return "%s(父:%s)" % [best.get_class(), String(par.name)]

func _settle(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

# ================================ 反例 ================================

## 尺子得拦得住东西：把「修复前的形状」（卡片默认 STOP）原样换回一处本来能滑的地方，
## 同一个落点必须被报成滑不动；改回 PASS 后必须又报能滑 —— 两头都对，正判才可信。
func _selftest() -> void:
	var dlg := _make({"cls": "CareerDialog"})
	if dlg == null:
		_c.check(false, "反例：CareerDialog 没建起来")
		return
	add_child(dlg)
	dlg.call("open")
	await _settle(4)
	var scrolls := _scrolls(dlg)
	var content: Control = null
	if not scrolls.is_empty():
		content = _content_of(scrolls[0])
	var pts: Array = []
	if content != null:
		pts = _sample_points(scrolls[0], content)
	if scrolls.is_empty() or content == null or pts.is_empty() or content.get_child_count() == 0:
		_c.check(false, "反例：修仙志·天道功绩没铺出可测的卡片（界面没建起来）")
		await _close(dlg)
		return
	var pos: Vector2 = (pts[0] as Array)[0]
	var card := content.get_child(0) as Control
	_c.check(card.mouse_filter != Control.MOUSE_FILTER_STOP,
		"反例前提：修复后第一张卡片是「%s」不是 STOP" % _mf_name(card.mouse_filter))
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	_c.check(not await _press_at(scrolls[0], dlg, pos),
		"反例 修复前形状（卡片 STOP）在落点 %s 被这条尺子抓成滑不动" % str(pos))
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	_c.check(await _press_at(scrolls[0], dlg, pos),
		"同一落点改回 PASS 又能起手拖动（说明上一枪抓的是 mouse_filter，不是别的东西）")
	await _close(dlg)

func _mf_name(mf: int) -> String:
	match mf:
		Control.MOUSE_FILTER_STOP: return "STOP"
		Control.MOUSE_FILTER_PASS: return "PASS"
		_: return "IGNORE"

## 反例（悟道面板那一横排）：这条尺子新加的「按每格自己的中心 x 采点」必须有牙齿。
## 只按滚动区中心 x 采的话，横排五张卡里只有中间那张被真测过，另外四张有没有吃掉「按下」
## 没人管得住 —— 而用户这张图上的毛病正好落在卡上。所以把最左那张换回修复前的 STOP 形状，
## 落在它身上的那一枪必须被报成滑不动，改回 PASS 必须又能滑。
func _selftest_alloc() -> void:
	var one_case: Dictionary = {}
	for c in CASES:
		if String(c["cls"]) == "LevelUpDialog":
			one_case = c
	if one_case.is_empty():
		_c.check(false, "反例：CASES 里没有悟道面板这一项")
		return
	var dlg := _make(one_case)
	if dlg == null:
		_c.check(false, "反例：LevelUpDialog 没建起来")
		return
	add_child(dlg)
	await _settle(2)
	await _prep_alloc()
	dlg.call(String(one_case["entry"]))
	await _settle(4)
	await get_tree().create_timer(float(one_case.get("settle_sec", 0.0))).timeout
	var sc: ScrollContainer = dlg.card_scroll
	var rows: Control = dlg.cards_container
	var pts := _sample_points(sc, _content_of(sc), rows)
	var first := rows.get_child(0) as Control
	var on_first: Array = []
	for pt in pts:
		if first.get_global_rect().has_point((pt as Array)[0] as Vector2):
			on_first.append(pt)
	_c.check(not on_first.is_empty() and first.mouse_filter != Control.MOUSE_FILTER_STOP,
		"反例前提：悟道面板采到 %d 个落在最左那张卡上的点，卡体是「%s」不是 STOP" % [
			on_first.size(), _mf_name(first.mouse_filter)])
	if on_first.is_empty():
		await _close(dlg)
		return
	var pos: Vector2 = (on_first[0] as Array)[0]
	first.mouse_filter = Control.MOUSE_FILTER_STOP
	_c.check(not await _press_at(sc, dlg, pos),
		"反例 最左那张卡换回 STOP ⇒ 落点 %s 被抓成滑不动（证明每格自己的中心 x 真在采）" % str(pos))
	first.mouse_filter = Control.MOUSE_FILTER_PASS
	_c.check(await _press_at(sc, dlg, pos),
		"同一落点改回 PASS 又能起手拖动（上一枪抓的是 mouse_filter，不是别的东西）")
	await _close(dlg)
