extends Node

## 判据：悟道卡片底部「受益装备」那一排图标 —— 点得动、弹对那件装备的卡，且不许顺手把卡选了。
## 运行: $G --headless --path . res://tests/BenefitIconTapCheck.tscn
##       $G --headless --path . res://tests/BenefitIconTapCheck.tscn -- --selftest
##       换档（落点要换坐标空间，720 档画布/窗口差一个 scale）：
##       $G --headless --path . res://tests/BenefitIconTapCheck.tscn -- --width=720
##
## 为什么立这条（用户 2026-10-11 真机图：「点击这个受益装备的图标，也可以弹窗显示这个对应装备的信息」）：
##  ① 那排图标原本是裸 TextureRect + MOUSE_FILTER_IGNORE：整块是死的，12~18 单位的边在真机上
##     不到 10dp，既按不动也按不准。
##  ② 卡片本体吃「左键松开 = 选中」，热区一旦嵌进卡里，最坏的结果不是点不着，而是「看一眼详情
##     顺手把这张卡选了」= 替玩家做了决定（触屏无 hover，没有第二条路可退）。所以「只读」单独钉。
##  ③ 格子按触控下限放大后，窄卡上会换行、卡于是变高。这一屏是五张卡横向比价用的，
##     要竖滑才看得完就已经很难受（2026-10-12 起卡体降成 PASS、划得动了，滑不再是「永远看不见
##     下半截」，但仍是兜底不是设计）⇒ 这里钉「这一屏不许需要竖滑」，并把每颗格的边长钉在下限之上。
##
## 尺子只认引擎拾取：按下-微动-抬起真发（root.push_input），绝不 emit_signal（emit 绕过拾取，
## 热区是死的也照样全绿）。弹出的卡读 DetailTip.live().payload，不另抄一份热区表。
## 防假 PASS：① 每一枪先自证「引擎在这一格上记了账」（落点没打歪）；② 上阵件数、每卡格数与数据表
## 独立算出来的对不上直接红；③ --selftest 把修复前的形状原样造一颗打同一枪，必须报出「点了没弹」
## 与「点图标把卡选了」，另留正例证明「没弹」不是「事件没送到」。

const VIEWPORT_SIZE := Vector2i(960, 540)
## 手指按在原地的微动：必须明显小于 GameStyle.TAP_SLACK，否则「根本点不动」也会被判成通过
const JITTER := 4.0
## 有意划动：必须明显大于 TAP_SLACK，否则测的不是「划」
const SWIPE := 70.0
## 卡体上「不是格子」的那一点：按卡高比例取，落在图标/标题那一块（图框是 IGNORE，会冒泡到卡）
const BODY_T := 0.22
const EPS := 0.5

## 三把各占一类链路：近战转化 / 远程转化 / 全局乘区都吃得到；再补三把凑满 6 格，
## 让窄屏那一档真的走到「格子摊不开要换行」那一条（不换行就等于没测高度）
const WEAPONS: Array[String] = [
	"qingyun_sword", "gengjin_feijian", "huoyan_fu", "wanmu_lingfu", "hunyuan_zhong", "lingdie"]
## 必钉的三条候选：全体受益 / 只喂近战 / 玩家功能属性（不许长出图标）
const PINNED: Array[String] = ["atk_up", "melee_up", "luck_up"]

var _c := TestCheck.new()
var _dlg: LevelUpDialog
var _width := VIEWPORT_SIZE.x

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--width="):
			_width = int(String(a).trim_prefix("--width="))
	get_tree().root.size = Vector2i(_width, VIEWPORT_SIZE.y)
	call_deferred("_boot")

func _boot() -> void:
	await _setup_run()
	if "--selftest" in OS.get_cmdline_user_args():
		await _selftest()
	else:
		await _run()
	get_tree().quit(0 if _c.report("BENEFITTAP_RESULT") else 1)

## 真数据：真 Player（get_weapons_summary 读的是 player 的上阵表）+ 真悟道会话
func _setup_run() -> void:
	GameManager.reset_run()
	GameManager.cultivator_id = "jianchi"
	var p := (load("res://scenes/entities/Player.tscn") as PackedScene).instantiate() as Player
	add_child(p)
	GameManager.player = p
	await _settle(3)
	for wid in WEAPONS:
		GameManager.add_weapon(wid)
		var in_field := false
		for w in GameManager.get_weapons_summary():
			if String((w as Dictionary).get("id", "")) == wid:
				in_field = true
		# add_weapon 进背包也返回 true：只断言返回值会静测成「上阵 1 把、其余在背包」的假现场
		_c.check(in_field, "法器 %s 真的上阵了（不是掉进背包）" % wid)
	await _settle(3)
	GameManager.pending_upgrade_points = 2
	GameManager.open_alloc_session()
	_pin_offers()
	_dlg = (load("res://scenes/ui/LevelUpDialog.tscn") as PackedScene).instantiate() as LevelUpDialog
	_dlg.visible = true
	add_child(_dlg)
	await _settle(2)
	_dlg._on_alloc_opened()
	get_tree().paused = false
	# 入场是错峰缩放 tween（0.8 → 1.0）：只等两帧量到的是缩小的中间帧，落定后的格子矩形才算数
	await get_tree().create_timer(0.8).timeout
	await _settle(2)

## 候选钉死：三条必钉的 + 两条「全体受益且最占地方」的（加成行数与说明文字都按最坏量，
## 格子数与卡高都取这一档）
func _pin_offers() -> void:
	var scored: Array = []
	for u in UpgradeData.UPGRADES:
		var uid := String(u.get("id", ""))
		var apply: Dictionary = u.get("apply", {})
		if uid in PINNED or apply.is_empty() or not _benefits_all(uid):
			continue
		scored.append({"id": uid, "w": apply.size() * 1000 + _plain_len(String(u.get("desc", "")))})
	scored.sort_custom(func(a, b): return int(a["w"]) > int(b["w"]))
	var ids := PINNED.duplicate()
	for s in scored:
		if ids.size() >= GameManager.UPGRADE_OFFER_COUNT:
			break
		ids.append(String(s["id"]))
	var offers: Array[Dictionary] = []
	for uid in ids:
		var d: Dictionary = UpgradeData.get_upgrade_def(uid).duplicate()
		d["border_color"] = UpgradeData.RARITY_COLORS.get(d.get("rarity", "common"), Color.WHITE)
		offers.append(d)
	GameManager.alloc_offers = offers

static func _plain_len(s: String) -> int:
	var plain: String = s.replace("[center]", "").replace("[/center]", "")
	for tag in ["[color=#ffd24d]", "[/color]", "[b]", "[/b]", "•", "\n", " "]:
		plain = plain.replace(tag, "")
	return plain.length()

func _benefits_all(uid: String) -> bool:
	var apply: Dictionary = UpgradeData.get_upgrade_def(uid).get("apply", {})
	for wid in WEAPONS:
		if not GameBalance.upgrade_benefits_weapon(apply, wid):
			return false
	return not apply.is_empty()

# ================================ 正判 ================================

func _run() -> void:
	_c.check(_dlg != null, "悟道面板已建起")
	if _dlg == null:
		return
	var summary: Array = GameManager.get_weapons_summary()
	_c.check(summary.size() == WEAPONS.size(),
		"前提：%d 把法器都在阵上（实得 %d 件，少了后面那些格数就是空判）" % [
			WEAPONS.size(), summary.size()])
	var cards: Array[Control] = _cards()
	_c.check(cards.size() == GameManager.alloc_offers.size(),
		"一屏 %d 张卡都建出来了（实得 %d）" % [GameManager.alloc_offers.size(), cards.size()])
	_dump(cards)

	# ---- ① 每格都是活的键：本体收事件、挂了识别器、边长不小于触控下限 ----
	var tapped_any := false
	for ci in range(cards.size()):
		var offer: Dictionary = GameManager.alloc_offers[ci]
		var cells := _cells(cards[ci])
		var want_ids := _benefited_ids(String(offer.get("id", "")))
		_c.check(cells.size() == want_ids.size(),
			"卡「%s」长出 %d 颗受益格（数据表算出 %d：%s）" % [
				String(offer.get("title", "?")), cells.size(), want_ids.size(), str(want_ids)])
		for cell in cells:
			# 只要求「本体收得到事件」：STOP 与 PASS 都收，IGNORE 才是死图。
			# 2026-10-12 起整行卡过一遍 GameStyle.swipeable（卡与卡内热区一律降成 PASS，手指压在
			# 格子上也拖得动列表），这里再钉 STOP 就把修法本身判成 bug。原本靠 STOP 拦冒泡才成立的
			# 「点格子不许顺手选卡」，改由 GameStyle.tap 的认领（_TAP_CLAIM_META）兑现，
			# 那条硬口径仍由 ② 与反例② 钉着。
			_c.check(cell.mouse_filter != Control.MOUSE_FILTER_IGNORE,
				"受益格本体收事件（实得 %d，2 就是 IGNORE = 死图）" % cell.mouse_filter)
			_c.check(cell.gui_input.get_connections().size() > 0,
				"受益格真挂了点按回调（尺子活着，不是回退值）")
			var sz := cell.size
			_c.check(sz.x >= LevelUpDialog.BF_CELL_MIN - EPS and sz.y >= LevelUpDialog.BF_CELL_MIN - EPS,
				"受益格边长 %.0fx%.0f 不小于触控下限 %.0f（屏宽 %d 档）" % [
					sz.x, sz.y, LevelUpDialog.BF_CELL_MIN, _width])
			_c.check(sz.x <= LevelUpDialog.BF_CELL_MAX + EPS,
				"受益格边长 %.0f 不盖过上限 %.0f" % [sz.x, LevelUpDialog.BF_CELL_MAX])
		if cells.is_empty():
			continue

		# ---- ② 点图标 = 弹这件装备的卡，且不改写选中态 ----
		var sel_before := _dlg.selected_index
		for gi in range(cells.size()):
			var cell := cells[gi]
			var want := _title_of_id(want_ids[gi]) if gi < want_ids.size() else "?格子多出来了"
			var got := await _tap_cell(cell)
			_c.check(got == want, "点卡「%s」第 %d 颗格弹「%s」（实得「%s」）" % [
				String(offer.get("title", "?")), gi + 1, want, got])
			tapped_any = true
		_c.check(_dlg.selected_index == sel_before,
			"点完这一排的格子，选中态仍是 %d（看详情是只读动作，不许替人选卡）" % sel_before)

		# ---- ③ 详情卡带着「这条悟道走的哪条链路」，与图标同一份判定 ----
		var tip := await _tap_cell_keep(cells[cells.size() - 1])
		var notes: Array = tip.payload.get("notes", []) if tip != null else []
		var has_reason := false
		for n in notes:
			if String(n).contains(String(offer.get("title", "?"))):
				has_reason = true
		_c.check(has_reason, "详情卡里有一句点到本条悟道「%s」的链路（实得 %d 条 notes）" % [
			String(offer.get("title", "?")), notes.size()])
		await _wait_tips_gone()
	_c.check(tapped_any, "前提：至少点着一颗格子（一颗都没弹过 = 整判据空跑）")

	# ---- ④ 划动不算点 ----
	var first_cells := _cells(cards[0]) if not cards.is_empty() else []
	if not first_cells.is_empty():
		_c.check(await _swipe_cell(first_cells[0]) == "",
			"在受益格上划 %.0f 单位再松手不许弹卡" % SWIPE)

	# ---- ⑤ 卡体那一下仍然选中这张卡（格子没把整张卡吃掉）----
	for ci in range(cards.size()):
		var body := cards[ci].get_global_rect()
		var pt := Vector2(body.get_center().x, body.position.y + body.size.y * BODY_T)
		await _wait_tips_gone()
		await _press(pt)
		await _motion(pt + Vector2(0, -JITTER))
		await _release(pt + Vector2(0, -JITTER))
		_c.check(_dlg.selected_index == ci,
			"点第 %d 张卡的卡体（图标那一块）仍能选中它（实得 selected_index=%d）" % [
				ci + 1, _dlg.selected_index])
		_c.check(DetailTip.live(_dlg) == null, "点卡体不许弹详情卡（它只做选中这一件事）")

	# ---- ⑥ 选中之后点格子：只读，不许把选中改掉或取消 ----
	if not first_cells.is_empty():
		_dlg._select_card(0)
		await _settle(4)
		var got := await _tap_cell(first_cells[0])
		_c.check(_dlg.selected_index == 0,
			"已选中第 1 张卡时点它的格子，选中态仍是 0（实得 %d）" % _dlg.selected_index)
		_c.check(got != "", "但详情卡照样弹（实得「%s」）" % got)

	# ---- ⑦ 重建候选收旧卡：停在暗底下的旧详情卡报的是旧数 ----
	await _wait_tips_gone()
	var probe := _cells(cards[0])
	if not probe.is_empty():
		await _tap_cell_keep(probe[0])
		_c.check(DetailTip.live(_dlg) != null, "前提：宿主上确实有一张卡（下一条收卡判定才不是空判）")
		_dlg._populate_cards()
		await _settle(2)
		_c.check(DetailTip.live(_dlg) == null, "重建候选 ⇒ 旧详情卡被收掉")
		await _wait_tips_gone()

	# ---- ⑧ 这一屏不许需要竖滑（卡体 STOP，划不动 = 下半截永远看不见）----
	# 尺子量「最高那张卡要的高 + 上下放大余量」vs「滚动区给的高」，与灵石阁 shelf_fits 同一口径；
	# 不读 VScrollBar.max_value：ScrollContainer 给它设的是内容高，不等于「还差多少要滑」。
	var screen_h := _dlg.get_viewport().get_visible_rect().size.y
	var gutter := LevelUpDialog.pop_gutter_y(screen_h)
	var avail := _dlg.card_scroll.size.y
	var need_h := 0.0
	for ci in range(_cards().size()):
		var card := _cards()[ci]
		need_h = maxf(need_h, card.get_combined_minimum_size().y)
		_c.check(card.size.y >= card.get_combined_minimum_size().y - EPS,
			"第 %d 张卡给到的 %.0f 高装得下它要的 %.0f 高" % [
				ci + 1, card.size.y, card.get_combined_minimum_size().y])
	_c.check(need_h + gutter * 2.0 <= avail + EPS,
		"整屏不用竖滑就能看全：最高那张卡要 %.0f + 上下放大余量 %.0f，滚动区只给 %.0f（屏宽 %d 档）" % [
			need_h, gutter * 2.0, avail, _width])

# ============================ 独立算一遍期望值 ============================

## 诊断落盘：报红时先看清是哪一层把卡撑高的、格子有没有按名字找齐
func _dump(cards: Array[Control]) -> void:
	print("[INFO] 屏宽 %d 视口 %s 滚动区给 %.0f 高，选中放大要上下各让 %.0f" % [
		_width, str(_dlg.get_viewport_rect().size), _dlg.card_scroll.size.y,
		LevelUpDialog.pop_gutter_y(_dlg.get_viewport().get_visible_rect().size.y)])
	for ci in range(cards.size()):
		var card := cards[ci]
		var vb := card.get_child(0) as VBoxContainer
		var parts: Array[String] = []
		if vb != null:
			for ch in vb.get_children():
				var c := ch as Control
				if c != null:
					parts.append("%s:%.0f" % [ch.get_class(), c.size.y])
					if c is HFlowContainer:
						var nm: Array[String] = []
						for x in c.get_children():
							nm.append(String((x as Node).name))
						parts.append("(排内子节点 %d：%s)" % [c.get_child_count(), ", ".join(nm)])
		print("  卡%d「%s」实高 %.0f 要 %.0f 格 %d | %s" % [
			ci, String(GameManager.alloc_offers[ci].get("title", "?")), card.size.y,
			card.get_combined_minimum_size().y, _cells(card).size(), " ".join(parts)])

## 该长出几颗格：按上阵表 + 判定函数现算（判定本身在 UnitRunner 里逐条钉过）
func _benefited_ids(uid: String) -> Array[String]:
	var out: Array[String] = []
	var apply: Dictionary = UpgradeData.get_upgrade_def(uid).get("apply", {})
	for w in GameManager.get_weapons_summary():
		var wid := String((w as Dictionary).get("id", ""))
		if GameBalance.upgrade_benefits_weapon(apply, wid):
			out.append(wid)
	return out

## 详情卡标题与 StatsTipFactory 同一套拼法（名字 + 星级），但不叫它自己报；
## 星级取上阵表里那一件的真实读数，不写死 1。
func _title_of_id(wid: String) -> String:
	var star := 1
	for w in GameManager.get_weapons_summary():
		if String((w as Dictionary).get("id", "")) == wid:
			star = int((w as Dictionary).get("star", 1))
	var def := WeaponData.get_def(wid)
	return "%s %s" % [String(def.get("name", "?")),
		WeaponData.star_text(clampi(star, 1, WeaponData.MAX_STAR))]

# ============================== 取样与手势 ==============================

func _cards() -> Array[Control]:
	var out: Array[Control] = []
	for ch in _dlg.cards_container.get_children():
		if ch is Control:
			out.append(ch as Control)
	return out

## 自己递归找格子：find_children 的 owned 参数默认 true，只认 owner 非空的节点，
## 而这张卡整棵子树都是代码 new() 出来的（owner 为空）→ 用它一个都找不到。
## 按前缀而不是等值：Godot 会给同层重名节点自动改名（@PanelContainer@92），生产代码一旦
## 少带序号，这里就会静默只找到第一颗 —— 所以格子数还另与数据表对账（_run ①）。
func _cells(n: Node) -> Array[Control]:
	var out: Array[Control] = []
	for ch in n.get_children():
		var c := ch as Control
		if c == null:
			continue
		if String(c.name).begins_with("BenefitCell") and c.is_visible_in_tree():
			out.append(c)
		out.append_array(_cells(c))
	return out

## 真发一次「按下 → 原地微动 → 抬起」，返回弹出的卡标题（没弹返回空串）并顺手收卡
func _tap_cell(cell: Control) -> String:
	var tip := await _tap_cell_keep(cell)
	var got := ""
	if tip != null:
		got = String(tip.payload.get("title", ""))
	await _wait_tips_gone()
	return got

## 同上但把卡留着（要读 notes 时用），并当场自证落点与「卡整块在视口内」
func _tap_cell_keep(cell: Control) -> DetailTip:
	var pos := _center(cell)
	await _wait_tips_gone()
	await _press(pos)
	_c.check(cell.has_meta(GameStyle._TAP_DOWN_META),
		"受益格 %s：这一枪确实送到了它身上（引擎没记账 ⇒ 落点打歪了）" % str(cell.get_index()))
	await _motion(pos + Vector2(0, -JITTER))
	await _release(pos + Vector2(0, -JITTER))
	var tip := DetailTip.live(_dlg)
	if tip != null:
		var vp := _dlg.get_viewport_rect()
		var card := tip.card_rect()
		_c.check(Rect2(vp.position, vp.size).encloses(card),
			"详情卡整块落在视口内（卡 %s / 视口 %s）" % [str(card), str(vp.size)])
	return tip

func _swipe_cell(cell: Control) -> String:
	var pos := _center(cell)
	await _wait_tips_gone()
	await _press(pos)
	await _motion(pos - Vector2(0, SWIPE * 0.5))
	await _motion(pos - Vector2(0, SWIPE))
	await _release(pos - Vector2(0, SWIPE))
	var got := ""
	var tip := DetailTip.live(_dlg)
	if tip != null:
		got = String(tip.payload.get("title", ""))
	await _wait_tips_gone()
	return got

## 淡出期间那块全屏暗底还在树里，会把下一枪测成「暗底上能不能点」这种假问题
func _wait_tips_gone() -> void:
	DetailTip.close_all(_dlg)
	for _i in range(40):
		var any := false
		for ch in _dlg.get_children():
			if ch is DetailTip:
				any = true
		if not any:
			return
		await get_tree().process_frame
	push_warning("详解卡 40 帧还没收干净，后续落点不可信")

func _center(c: Control) -> Vector2:
	return c.get_global_rect().get_center()

## 落点换算：get_global_rect() 给画布（设计）坐标，push_input 要窗口坐标。
## canvas_items + expand 下 960/1204 档 scale=1 恒等，只有 720 档（scale 0.75）会露馅。
func _to_input(pos: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * pos

func _press(pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = _to_input(pos)
	e.global_position = e.position
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_tree().root.push_input(e)
	await get_tree().process_frame

func _release(pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.position = _to_input(pos)
	e.global_position = e.position
	get_tree().root.push_input(e)
	await get_tree().process_frame

func _motion(pos: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = _to_input(pos)
	m.global_position = m.position
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_tree().root.push_input(m)
	await get_tree().process_frame

func _settle(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

# ================================ 反例 ================================

## 判据自己得拦得住东西：把修复前的两种形状原样造进同一张卡里，各打同一枪。
func _selftest() -> void:
	_c.check(GameStyle.TAP_SLACK > JITTER and GameStyle.TAP_SLACK < SWIPE,
		"容差 %.0f 夹在「手指微动 %.0f」与「有意划动 %.0f」之间" % [
			GameStyle.TAP_SLACK, JITTER, SWIPE])
	var cards := _cards()
	_c.check(not cards.is_empty(), "反例现场：卡片已建起")
	if cards.is_empty():
		return
	var card: Control = cards[0]
	var row: HFlowContainer = null
	for ch in _walk_list(card):
		var f := ch as HFlowContainer
		if f != null:
			row = f
	_c.check(row != null, "反例现场：第 1 张卡里找得到受益格那一排")
	if row == null:
		return

	# 反例①：修复前的形状 —— 裸贴图 + IGNORE，点了没反应
	var old_icon := TextureRect.new()
	old_icon.name = "DecoyOld"
	old_icon.custom_minimum_size = Vector2(LevelUpDialog.BF_CELL_MIN, LevelUpDialog.BF_CELL_MIN)
	old_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(old_icon)
	await _settle(3)
	var got_old := await _tap_decoy(old_icon)
	_c.check(got_old == "",
		"反例① 裸贴图同一枪弹不出卡（实得「%s」）—— 尺子抓得住「图标是死的」" % got_old)
	_c.check(_dlg.selected_index == 0,
		"反例① 顺带证明：那一枪被卡体收走了（selected_index=%d）—— 旧形状不但不弹，还会顺手选卡" % _dlg.selected_index)

	# 正例：修复后的形状在同一排打同一类坐标必须弹得出来 —— 上面那个「没弹」才是判定而不是没送到
	var good := PanelContainer.new()
	good.name = "DecoyGood"
	good.custom_minimum_size = Vector2(LevelUpDialog.BF_CELL_MIN, LevelUpDialog.BF_CELL_MIN)
	row.add_child(good)
	GameStyle.hotzone(good)
	GameStyle.tap(good, func() -> void:
		DetailTip.show_over(_dlg, good, {"title": "正例 新形状"})
	)
	await _settle(3)
	var sel_before := _dlg.selected_index
	var got_good := await _tap_decoy(good)
	_c.check(got_good == "正例 新形状",
		"正例 新形状在同一类坐标弹得出来（实得「%s」）" % got_good)
	_c.check(_dlg.selected_index == sel_before,
		"正例 点格子没改选中态（%d → %d）" % [sel_before, _dlg.selected_index])

	# 反例②：格体收事件、却**不认完整手势也不认领**（修复前的写法：裸 gui_input 认「左键松开」）
	# —— 那一枪顺着冒泡链走到卡体，看一眼详情就把这张卡选了。
	# 2026-10-12 起这一枪不能再靠 mouse_filter 造：格体与卡体都是 PASS，拦住选中的是
	# GameStyle.tap 的认领标记，不是 STOP 拦冒泡 ⇒ 反例照旧写法自己发松开那一枪。
	var leaky := PanelContainer.new()
	leaky.name = "DecoyLeaky"
	leaky.custom_minimum_size = Vector2(LevelUpDialog.BF_CELL_MIN, LevelUpDialog.BF_CELL_MIN)
	row.add_child(leaky)
	GameStyle.hotzone(leaky)
	leaky.mouse_filter = Control.MOUSE_FILTER_PASS
	leaky.gui_input.connect(func(ev: InputEvent) -> void:
		var mb := ev as InputEventMouseButton
		if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			DetailTip.show_over(_dlg, leaky, {"title": "反例② 会漏的格"})
	)
	await _settle(3)
	_dlg.selected_index = -1
	var got_leak := await _tap_decoy(leaky, false)
	_c.check(got_leak == "反例② 会漏的格" and _dlg.selected_index == 0,
		"反例② 格体不认领那一枪时：卡弹了但选中态被那一枪改掉（弹「%s」selected=%d）—— 尺子抓得住「只读」这条" % [
			got_leak, _dlg.selected_index])
	old_icon.queue_free()
	good.queue_free()
	leaky.queue_free()
	await _settle(3)

## 反例专用落点：先自证送到了，再读弹出结果（选中态留给调用方判）
## prove_by_meta=false 给「不认完整手势」的旧写法用：它身上没有 GameStyle.tap 的按下记账可查，
## 送达与否由调用方那条「弹出了哪张卡」自己证明（没送到就什么也弹不出来）。
func _tap_decoy(node: Control, prove_by_meta := true) -> String:
	var pos := _center(node)
	await _wait_tips_gone()
	await _press(pos)
	var landed := node.has_meta(GameStyle._TAP_DOWN_META) \
			or node.mouse_filter == Control.MOUSE_FILTER_IGNORE
	await _motion(pos + Vector2(0, -JITTER))
	await _release(pos + Vector2(0, -JITTER))
	if prove_by_meta:
		_c.check(landed, "反例落点：这一枪真送到了 %s 身上（否则「没弹卡」不算判定）" % node.name)
	var got := ""
	var tip := DetailTip.live(_dlg)
	if tip != null:
		got = String(tip.payload.get("title", ""))
	await _wait_tips_gone()
	return got

func _walk_list(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for ch in n.get_children():
		out.append_array(_walk_list(ch))
	return out
