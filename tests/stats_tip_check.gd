extends Node

## 属性面板「点按看详解」判据：文案表自洽 + 面板真的接上了点击 + 详情卡逐档屏宽不出屏。
## 运行: godot --headless --path . res://tests/StatsTipCheck.tscn
##       godot --headless --path . res://tests/StatsTipCheck.tscn -- --selftest   （验判据有牙齿）
##
## 为什么立这条判据（三类毛病都不崩、不报错、只有真机看得见）：
##  ① 触屏没有 hover，tooltip_text 在手机上永远不会出现 —— 面板上 15 行属性、6 个法器格、
##     一整列悟道流水，点上去没反应就跟坏了一样。而「接线漏一条」是静默的：
##     所以这里逐个热区真发一次左键松开，看有没有卡真的弹出来、卡上有没有内容。
##  ② 文案表与数据表会分家：新加一条悟道/法宝而 StatInfoData 的人话表没登记字段，
##     详情卡上就会露出 weapon_damage_mult 这种原始 key。
##  ③ 面板原先写死 880×560，比 960×540 的视口还高 ⇒ 上下各被切走 10 单位，
##     被切走的正好是最底下两行 —— 如今那两行是热区，出屏就等于点不到。
##
## 尺子取引擎自己的账（控件的 global rect），不另抄一份字体度量与布局算式：
## 抄一份就会和代码同时错。

## 4:3 平板 / 16:9 基准 / 20:9 宽屏（canvas_items + expand 下可视宽恒 ≥ 960，高跟着变）
const WIDTHS: Array[int] = [720, 960, 1204]

## 详情卡离可视区边缘的最小留白，与 DetailTip.MARGIN 同值
const EDGE := 9.0

var _c := TestCheck.new()
var _dlg: PlayerStatsDialog

func _ready() -> void:
	_seed()
	if "--selftest" in OS.get_cmdline_user_args():
		await _selftest()
		get_tree().quit(0 if _c.report("STATSTIP_SELFTEST_RESULT") else 1)
		return
	await _run()
	get_tree().quit(0 if _c.report("STATSTIP_RESULT") else 1)

## 造一点真数据：上阵一件、仓库一件、悟道两条 —— 否则法器格与流水行全是空的，
## 「接线有没有漏」这一半就量不到东西
func _seed() -> void:
	GameManager.reset_run()
	GameManager.cultivator_id = "shiyue"
	GameManager.drones.append(2)
	GameManager.stash.append({"id": "qingyun_sword", "star": 1})
	GameManager.apply_upgrade("armor_up")
	GameManager.apply_upgrade("armor_up")
	GameManager.apply_upgrade("crit_up")
	GameManager.kills = 37
	GameManager.spirit_stones = 128
	GameManager.game_time = 96.0

# ================================ 正判 ================================

func _run() -> void:
	# ---- ① 文案表自洽 ----
	var ids: Array = StatInfoData.ids()
	_c.check(ids.size() >= 14, "属性详解覆盖 %d 行" % ids.size())
	var no_tip: Array[String] = []
	for id in ids:
		if not _stat_tips_ok(String(id)):
			no_tip.append(String(id))
	_c.check(no_tip.is_empty(), "每行都有「标题 + 一句话 + 至少两条规则」（缺：%s）" % str(no_tip))
	_c.check(_fields_registered(_all_apply_fields()),
		"悟道与法宝的每个加点字段都有人话名（共 %d 个字段）" % _all_apply_fields().size())
	_c.check(_amounts_are_human(), "幅度读数全是人话，不露 snake_case 字段名")
	_c.check(_lookup_consistent(_forward_table()), "字段与面板行的对照两边指得回同一处")

	# ---- ② 每个热区点得动、弹出的卡有内容有标题且不出屏 ----
	var errs := await _sweep_taps()
	for e in errs:
		_c.check(false, e)
	_c.check(errs.is_empty(), "逐档屏宽点遍 %d 处热区：都弹出卡、卡都在屏内" % (_sweep_total()))

	# ---- ③ 面板本体在屏内（底下两行不能出屏，出屏就点不到）----
	for w in WIDTHS:
		get_tree().root.size = Vector2i(w, 540)
		await get_tree().process_frame
		await get_tree().process_frame
		var area := await _open_dialog()
		var pr: Rect2 = _dlg._panel.get_global_rect()
		_c.check(_fits(pr, area), "屏宽 %d · 面板整块在屏内（y=%.0f..%.0f / 可视高 %.0f）" % [
			w, pr.position.y, pr.end.y, area.y])
		await _close_dialog()

func _sweep_total() -> int:
	return StatInfoData.ids().size() + WeaponData.MAX_SLOTS + GameManager.stash.size() \
		+ GameManager.upgrade_history.size()

## 逐档屏宽把每个热区点一遍，返回问题清单（空 = 全绿）
func _sweep_taps() -> Array[String]:
	var errs: Array[String] = []
	for w in WIDTHS:
		get_tree().root.size = Vector2i(w, 540)
		await get_tree().process_frame
		await get_tree().process_frame
		var area := await _open_dialog()
		var tag := "屏宽 %d" % w
		for row in _stat_rows():
			errs.append_array(await _tap_and_read(row, String(row.get_meta("tip_title", "")), area, tag + " · 属性行"))
		errs.append_array(await _tap_box(_dlg._weapons_box, tag + " · 法器格", area))
		errs.append_array(await _tap_box(_dlg._stash_box, tag + " · 仓库格", area))
		errs.append_array(await _tap_box(_dlg._history_list, tag + " · 悟道行", area))
		await _close_dialog()
	return errs

func _tap_box(box: Node, tag: String, area: Vector2) -> Array[String]:
	var errs: Array[String] = []
	var n := 0
	for ch in box.get_children():
		if not (ch is Control):
			continue
		n += 1
		errs.append_array(await _tap_and_read(ch as Control, "", area, "%s %d" % [tag, n]))
	return errs

## 真发一次「左键松开」，看链路的四件事：接没接线、有没有卡、卡上有没有内容、卡整块在不在屏内
func _tap_and_read(ctrl: Control, expect_title: String, area: Vector2, tag: String) -> Array[String]:
	var errs: Array[String] = []
	if ctrl.get_signal_connection_list("gui_input").is_empty():
		errs.append("%s 没接点击（点了没反应）" % tag)
		return errs
	ctrl.emit_signal("gui_input", _tap_event())
	await get_tree().process_frame
	await get_tree().process_frame
	var tip := DetailTip.live(_dlg)
	if tip == null:
		errs.append("%s 点下去没弹出详情卡" % tag)
		return errs
	var p: Dictionary = tip.payload
	var title := String(p.get("title", ""))
	if title.is_empty():
		errs.append("%s 弹出的卡没有标题" % tag)
	elif not expect_title.is_empty() and title != expect_title:
		errs.append("%s 卡标题串了：期望「%s」实得「%s」" % [tag, expect_title, title])
	if (p.get("rows", []) as Array).is_empty():
		errs.append("「%s」的卡里没有读数" % title)
	if String(p.get("body", "")).is_empty():
		errs.append("「%s」的卡里没有解释" % title)
	if (p.get("notes", []) as Array).is_empty():
		errs.append("「%s」的卡里没有规则条目" % title)
	var rect := tip.card_rect()
	if not _fits(rect, area):
		errs.append("「%s」的卡出屏（x=%.0f..%.0f y=%.0f..%.0f / 可视 %.0f×%.0f）" % [
			title, rect.position.x, rect.end.x, rect.position.y, rect.end.y, area.x, area.y])
	if rect.size.x < 120.0 or rect.size.y < 40.0:
		errs.append("「%s」的卡小得装不下内容（%.0f×%.0f）" % [title, rect.size.x, rect.size.y])
	DetailTip.close_all(_dlg)
	return errs

## 建一个挂在测试节点下的面板实例并等布局落定，返回可视区尺寸。
## 不走 open()：它会 pause 整棵树，判据要的是「面板摆好之后」的几何，不是暂停状态。
func _open_dialog() -> Vector2:
	_dlg = PlayerStatsDialog.new()
	add_child(_dlg)
	_dlg.visible = true
	_dlg.refresh()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	return _dlg.get_viewport_rect().size

func _close_dialog() -> void:
	if _dlg != null and is_instance_valid(_dlg):
		_dlg.queue_free()
	_dlg = null
	await get_tree().process_frame
	await get_tree().process_frame

## 一条热区的全部几何账：四边都在可视区内、且留出边缘
func _fits(rect: Rect2, area: Vector2) -> bool:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return false
	if rect.position.x < EDGE or rect.position.y < EDGE:
		return false
	return rect.end.x <= area.x - EDGE + 0.5 and rect.end.y <= area.y - EDGE + 0.5

## 文案表三段都在：标题、一句话、规则（规则只有一条也算没写：那通常是敷衍）
func _stat_tips_ok(id: String) -> bool:
	return StatInfoData.has(id) \
		and not StatInfoData.title(id).is_empty() \
		and not StatInfoData.brief(id).is_empty() \
		and StatInfoData.rules(id).size() >= 2

## 数据表里出现过的每个 apply 字段，人话表都得登记（漏登记时 field_name 原样吐回 key）
func _fields_registered(fields: Array) -> bool:
	for f in fields:
		if StatInfoData.field_name(String(f)) == String(f):
			push_warning("未登记字段: " + String(f))
			return false
	return true

func _all_apply_fields() -> Array:
	var out: Array = []
	for udef in UpgradeData.UPGRADES:
		for k in (udef as Dictionary).get("apply", {}).keys():
			out.append(String(k))
	for id in ItemData.DEFS.keys():
		for k in (ItemData.DEFS[id] as Dictionary).get("apply", {}).keys():
			out.append(String(k))
	return out

## 幅度读数不许露原始字段名（漏登记时就是「weapon_damage_mult +0.15」这种话）
func _amounts_are_human() -> bool:
	for f in _all_apply_fields():
		var line := "%s %s" % [StatInfoData.field_name(String(f)),
			StatInfoData.format_amount(String(f), 0.15)]
		if "_" in line:
			push_warning("露出原始字段: " + line)
			return false
	return true

func _forward_table() -> Dictionary:
	var m: Dictionary = {}
	for id in StatInfoData.ids():
		m[String(id)] = StatInfoData.apply_fields(String(id))
	return m

## 正查表与反查表必须指得回同一处：一处登记、另一处就会漂
func _lookup_consistent(m: Dictionary) -> bool:
	for id in m.keys():
		for f in m[id]:
			if StatInfoData.stat_of_field(String(f)) != String(id):
				push_warning("反查错位: %s 应指 %s" % [String(f), String(id)])
				return false
	return true

## 按标题文字找出属性行（行 = 包着 Label 的那层 PanelContainer）
func _stat_rows() -> Array[Control]:
	var want: Dictionary = {}
	for id in StatInfoData.ids():
		want[StatInfoData.title(String(id))] = true
	var out: Array[Control] = []
	for lbl in _labels_of(_dlg):
		if not want.has(lbl.text):
			continue
		var p: Node = lbl.get_parent()
		while p != null and p != _dlg:
			if p is PanelContainer and not String((p as Control).get_meta("tip_title", "")).is_empty():
				out.append(p as Control)
				break
			p = p.get_parent()
	return out

func _labels_of(node: Node) -> Array[Label]:
	var out: Array[Label] = []
	if node is Label:
		out.append(node as Label)
	for ch in node.get_children():
		out.append_array(_labels_of(ch))
	return out

func _tap_event() -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	return ev

# ================================ 反例 ================================

## 判据自己得拦得住东西：拿旧写法与几种坏法喂同一条尺子
func _selftest() -> void:
	var area := Vector2(960.0, 540.0)
	_c.check(_fits(Rect2(20, 20, 300, 200), area), "正例 卡整块在屏内放行")
	_c.check(not _fits(Rect2(700, 380, 300, 200), area), "反例① 卡片底边压出屏外被拦住")
	_c.check(not _fits(Rect2(-160, 20, 300, 200), area), "反例② 整块推到屏外被拦住")
	_c.check(not _fits(Rect2(0, 0, 0, 0), area), "反例③ 没量到尺寸（空 rect）被拦住")
	_c.check(not _fits(Rect2(5, 20, 300, 200), area), "反例④ 贴到屏边没留缝被拦住")
	_c.check(_stat_tips_ok("hp"), "正例 气血值三段文案齐")
	_c.check(not _stat_tips_ok("no_such_stat"), "反例⑤ 面板有行、文案表没这条被拦住")
	_c.check(_fields_registered(_all_apply_fields()), "正例 现有悟道/法宝字段全部登记")
	_c.check(not _fields_registered(["weapon_damage_mult", "not_a_real_field"]),
		"反例⑥ 数据表新增字段而人话表漏登记被拦住")
	_c.check(_lookup_consistent(_forward_table()), "正例 字段对照两边指得回同一处")
	_c.check(not _lookup_consistent({"hp": ["armor"]}),
		"反例⑦ 字段反查指不到自己那一行被拦住")
	# 反例⑧：一个没接点击的热区 —— 判据必须报「点了没反应」
	_dlg = PlayerStatsDialog.new()
	add_child(_dlg)
	_dlg.visible = true
	await get_tree().process_frame
	var bare := PanelContainer.new()
	_dlg.add_child(bare)
	var errs := await _tap_and_read(bare, "", _dlg.get_viewport_rect().size, "反例⑧")
	_c.check(not errs.is_empty(), "反例⑧ 热区没接 gui_input 被拦住（%s）" % str(errs))
	await _close_dialog()
