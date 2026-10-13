extends Node

## 判据：灵石阁货架卡行②那排色签，每一颗都得「点得动、弹对卡、卡上的数对得上数据表」。
## 运行: $G --headless --path . res://tests/ShopChipTapCheck.tscn
##       $G --headless --path . res://tests/ShopChipTapCheck.tscn -- --selftest
##
## 为什么立这条（用户 2026-10-11 真机，指着卡上「环绕 / 召唤 6/MAX / 水系 0/2」那一排说：
## 「点击也要弹出来对应的解释，就是加成怎么样加成哪些」）：
##  ① 那排色签原先是**纯 Label，一个热区都没挂**：HUD 顶栏的羁绊徽记能点开详情
##     （SynergyUI.create_chip），货架卡上同名的那一颗却按不动 —— 同一句话在两个地方，
##     一个点得开一个点不开，而触屏没有 hover，按不动的那个就等于没有解释。
##  ② 「环绕」是攻击方式、「召唤 6/MAX」是流派羁绊，两颗挨着摆、词还互相撞
##     （BURST 短标＝「范围」与 thunder 羁绊同名，TURRET 短标＝「机关」与 contraption 同名）：
##     不点开看，玩家没有任何办法分清哪颗说的是出手、哪颗说的是凑档。
##  ③ 这条判据量的是「点下去到底有没有兑现」，不是「代码里写了 open_synergy」：
##     接线写成 lambda 按值捕获 null（HUD 那批徽记栽过的那一跤）时不崩不报错，
##     UnitRunner / SmokeRunner 全绿照样看不见。
##
## 尺子只认引擎拾取：真发按下 → 原地微动 → 抬起（emit_signal 会绕过拾取，热区是死的也全绿）；
## 落点从 get_global_rect() 取画布坐标，再经 get_final_transform() 换到窗口坐标（720 档 scale≠1）。
## 防假 PASS：
##  ① 先断言「带解释的色签数 == 画出来的色签数」且不少于 15 颗 —— 采到 0 颗时后面每一条
##     都会静默变成空判（"ALL PASS 零项" 就是没测）；
##  ② 每颗签的期望标题与期望文案由本文件按 WeaponData / SynergyUI.tier_line() 现算，
##     不叫被测代码报数；
##  ③ 弹出的 payload 在收卡之前先取成字典再验内容：DetailTip 是淡出 0.1 秒才 free 的，
##     收完再 live() 就读到 null，那一段就成了零项空判；
##  ④ 划动那一枪必须不弹（色签在滚动区里，按下那一拍同时被 ScrollContainer latch 去拖货架）；
##  ⑤ --selftest 把修复前的形状（同一排、没接热区的一颗 Label）打同一枪，必须报「点了没反应」，
##     旁边留一颗正例证明「没弹」不是「事件没送到」。

const VP := Vector2(960, 540)
## 三档屏（与 LayoutCheck / ShopReadoutCheck 同一套）：真机 4:3 / 16:9 / 20:9
const WIDTHS: Array[int] = [720, 960, 1204]
## 手指按在原地的微动：必须明显小于 GameStyle.TAP_SLACK
const JITTER := 4.0
## 有意划动：必须明显大于 GameStyle.TAP_SLACK
const SWIPE := 70.0
## 五张卡 = 五种攻击方式各一把，每把 2 条流派 ⇒ 至少 15 颗该有解释的色签
const WANT_CHIPS := 15
const SAMPLE_IDS: Array[String] = [
	"qingyun_sword", "gengjin_feijian", "fantian_yin", "lingdie", "jiguan_nu",
]
## 攻击方式短标：本判据自带一份，与 WeaponData.behavior_label 对不上就是词漂了
## （图鉴旧写法把 DRONE 叫「召唤」，与 spirit 羁绊同名 ⇒ 同一排两颗签分不出来）
const BEH_LABEL := {0: "近战", 1: "远程", 2: "范围", 3: "环绕", 4: "机关", 5: "横扫"}

var _c := TestCheck.new()
var _main: Node
var _shop: WaveShop
var _joy: DawnJoystick
var _container: HBoxContainer

func _ready() -> void:
	get_tree().root.size = Vector2i(int(VP.x), int(VP.y))
	call_deferred("_boot")

func _boot() -> void:
	_main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(_main)
	await _settle(3)
	GameManager.cultivator_id = ""
	GameManager.start_run("qingyun_sword")
	get_tree().paused = false
	# 手里再一把长剑 ⇒ 货架上那把长剑正好凑满 3 件，「可合成」角标才会亮
	GameManager.add_weapon("qingyun_sword")
	await _settle(2)
	_shop = _main.get_node_or_null("UILayer/WaveShop") as WaveShop
	_joy = _main.get_node_or_null("UILayer/VirtualJoystick") as DawnJoystick
	_c.check(_shop != null and _joy != null,
			"Main 里有灵石阁与摇杆节点（实得 %s / %s）" % [str(_shop), str(_joy)])
	if _shop == null or _joy == null:
		_quit()
		return
	_container = _shop.offers_container
	_quiet_arena()
	if "--selftest" in OS.get_cmdline_user_args():
		await _selftest()
	else:
		await _main_cases()
	_quit()

## 场地静音：刷怪器不再出人，判据只管这一屏的拾取
func _quiet_arena() -> void:
	var spawner: Node = GameManager.wave_spawner
	if spawner != null:
		spawner.set_process(false)
		spawner.set_physics_process(false)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is EnemyBase:
			enemy.dissolve()

func _quit() -> void:
	get_tree().quit(0 if _c.report("SHOPCHIP_RESULT") else 1)

# ================================ 正判 ================================

func _main_cases() -> void:
	await _open_pinned_shop(int(VP.x))
	await _ruler_is_alive()
	await _tap_every_chip()
	await _swipe_must_not_open()
	await _tips_fit_three_widths()

## 开一次钉好的货架：五把法器 = 五种攻击方式，流派签与可合成角标都齐
func _open_pinned_shop(width: int) -> void:
	DetailTip.close_all(_shop)
	get_tree().root.size = Vector2i(width, int(VP.y))
	await _settle(2)
	GameManager.spirit_stones = 999
	GameManager.shop_slots_bonus = 0
	GameManager.roll_shop(true)
	var offers: Array = GameManager.shop_offers
	for i in range(mini(offers.size(), SAMPLE_IDS.size())):
		var def := WeaponData.get_def(SAMPLE_IDS[i])
		offers[i] = {"kind": "weapon", "id": SAMPLE_IDS[i],
			"price": int(def.get("price", 20)), "sold": false, "locked": false}
	_shop._on_shop_opened()
	# 等真实时间：卡是错峰缩放入场的，headless 一帧不到 1ms，等帧数会量到还在动的矩形
	await get_tree().create_timer(0.8).timeout
	await _settle(2)

## 前提自证：采到的可点色签必须等于画出来的色签。
## 采到 0 颗 = 我这把尺子自己没接上（meta 名写错 / 整排没接线），后面每条都会静默空判。
func _ruler_is_alive() -> void:
	var chips := _chips()
	var drawn := _drawn_chips()
	_c.check(not chips.is_empty(), "货架上至少采到一颗可点色签（实得 %d，0 颗等于没测）" % chips.size())
	_c.check(chips.size() >= WANT_CHIPS,
			"五张卡采到 %d 颗带解释的色签（攻击方式 5 + 流派 10，少于 %d 就是漏接了一类）" % [
			chips.size(), WANT_CHIPS])
	_c.check(chips.size() == drawn.size(),
			"画出来的色签全都接了热区（画 %d 颗 / 可点 %d 颗）" % [drawn.size(), chips.size()])
	for chip in chips:
		_c.check(chip.gui_input.get_connections().size() > 0,
				"色签「%s」真挂了点按回调（尺子活着，不是回退值）" % chip.text.strip_edges())

## 逐颗点：弹对卡 + 卡上的数与数据表一致
func _tap_every_chip() -> void:
	for chip in _chips():
		var tip: Dictionary = chip.get_meta("chip_tip")
		var label := "色签「%s」" % chip.text.strip_edges()
		var payload := await _tap(chip, label)
		var want := _want_title(tip)
		_c.check(not payload.is_empty(), "%s 点开了详情卡（实得：没弹）" % label)
		_c.check(String(payload.get("title", "")) == want,
				"%s 点出「%s」（实得「%s」）" % [label, want, String(payload.get("title", ""))])
		_check_content(payload, tip, label)

## 卡上内容核对：标题之外还要验「加成怎么样、加成哪些」这两句话真的在卡上。
## payload 是收卡前从那张卡上取下来的快照，期望值一律本文件按数据表现算，不叫 ShopChipTips 自己报。
func _check_content(payload: Dictionary, tip: Dictionary, label: String) -> void:
	if payload.is_empty():
		return
	var joined := _joined(payload)
	match String(tip.get("kind", "")):
		"behavior":
			var def := WeaponData.get_def(String(tip.get("w_id", "")))
			var beh := int(def.get("behavior", 0))
			_c.equals(String(payload.get("body", "")), String(
					(WeaponData.BEHAVIOR_TIPS.get(beh, {}) as Dictionary).get("how", "")),
					"%s 的出手解释与 WeaponData.BEHAVIOR_TIPS 同源" % label)
			_c.check(joined.contains("不吃任何属性加成") or joined.contains("每下多打"),
					"%s 的卡上印了属性账单（加成哪些）：实得 %s" % [label, joined])
			_c.check(joined.contains("流派羁绊"),
					"%s 的卡上讲清它和带 n/m 那颗签不是一回事" % label)
		"synergy":
			var tag := String(tip.get("tag", ""))
			var n := GameManager.get_tag_count(tag)
			_c.check(joined.contains("上阵达到"), "%s 的卡上印了阶梯规则" % label)
			_c.check(joined.contains("属于这一路") or joined.contains("不计入羁绊"),
					"%s 的卡上讲清买下这一把之后会怎样（当前 %d 件）" % [label, n])
			# 阶梯文案现在由 WeaponData.effects 生成（手抄的 TIER_LINES 已删），这里只验
			# 「第一档给什么有没有上卡」；数字对不对另由 UnitRunner 的 apply_counts 对账判据管
			var tier1 := SynergyUI.tier_line(tag, 1)
			_c.check(not tier1.is_empty() and joined.contains(tier1),
					"%s 的卡上印了第一档给什么（期望含「%s」）" % [label, tier1])
		"merge":
			_c.check(joined.contains("3 件换 1 件"),
					"%s 的卡上印了三合一会掉羁绊件数这件事" % label)

## 划过去不算点：色签在滚动区里，按下那一拍同时被 ScrollContainer 拿去 latch 拖货架
func _swipe_must_not_open() -> void:
	var chips := _chips()
	if chips.is_empty():
		return
	_c.check((await _swipe(chips[0])).is_empty(), "在色签上划 %.0f 单位再松手不许弹卡" % SWIPE)
	if chips.size() > 1:
		_c.check((await _swipe(chips[1])).is_empty(), "第二颗同理（划货架不该顺手开详解）")

## 三档屏：详情卡整块必须在可视区内 —— 色签都卡在卡面上半部，卡只会往右下摆就探出屏了
func _tips_fit_three_widths() -> void:
	for w in WIDTHS:
		await _open_pinned_shop(w)
		var chips := _chips()
		_c.check(chips.size() >= WANT_CHIPS, "屏宽 %d：货架色签 %d 颗都在" % [w, chips.size()])
		if chips.is_empty():
			continue
		for idx in [0, int(chips.size() / 2), chips.size() - 1]:
			var chip: Control = chips[idx]
			var tip: Dictionary = chip.get_meta("chip_tip")
			var payload := await _tap(chip, "屏宽 %d · %s" % [w, chip.text.strip_edges()])
			_c.check(String(payload.get("title", "")) == _want_title(tip),
					"屏宽 %d：点「%s」弹对卡（实得「%s」）" % [
					w, chip.text.strip_edges(), String(payload.get("title", ""))])
		await _open_close()

func _open_close() -> void:
	DetailTip.close_all(_shop)
	_shop.visible = false
	get_tree().paused = false
	# 详情卡是 0.1 秒淡出后才 destroy 的：那块全屏暗底还挂在树上会把下一枪就地吃掉
	await get_tree().create_timer(0.35).timeout
	await _settle(2)

# ============================ 期望值（本文件自己算） ============================

func _want_title(tip: Dictionary) -> String:
	var w_id := String(tip.get("w_id", ""))
	match String(tip.get("kind", "")):
		"behavior":
			var def := WeaponData.get_def(w_id)
			return "攻击方式 · %s" % String(BEH_LABEL.get(int(def.get("behavior", 0)), "?"))
		"synergy":
			return _synergy_title(String(tip.get("tag", "")))
		"merge":
			return "可合成 · %s" % String(WeaponData.get_def(w_id).get("name", "?"))
	return ""

## 详情卡标题「剑系 (2/6)」= 手里 2 件、满档要 6 件（分母是满档件数，不是下一档）。
## 卡上那颗色签印的是「剑系 2/4」= 下一档要 4 件 —— 两个读数一实一待，各算一遍：
## SynergyUI 里 progress_text 用满档做分母、badge 用下一档做分母，本判据按同一套各自复算。
func _synergy_title(tag: String) -> String:
	var info: Dictionary = WeaponData.SYNERGIES.get(tag, {})
	var shift: int = 0
	if tag == "spirit":
		shift = GameManager.spirit_threshold_adj
	elif tag == "contraption":
		shift = GameManager.contraption_threshold_adj
	var ths: Array = []
	for th in info.get("thresholds", [2, 4, 6]):
		ths.append(maxi(1, int(th) - shift))
	var n: int = int((GameManager.active_synergies.get(tag, {"count": 0}) as Dictionary).get("count", 0))
	var max_th: int = int(ths[ths.size() - 1])
	var denom: String = "MAX"
	for th in ths:
		if n < int(th):
			denom = str(max_th)
			break
	return "%s (%d/%s)" % [String(info.get("name", tag)), n, denom]

func _joined(payload: Dictionary) -> String:
	var out := String(payload.get("body", "")) + String(payload.get("foot", ""))
	for n in payload.get("notes", []):
		out += "\n" + String(n)
	for r in payload.get("rows", []):
		out += "\n" + str(r)
	return out

# ============================== 取样与手势 ==============================

## 递归采「带解释的色签」：代码建的 Label 同名会被引擎改名（@Label@N），
## 按名字找就是静默拿 null ⇒ 一律遍历 + 读 meta（meta 是接线那一刻写的，不会漂）。
func _chips() -> Array[Control]:
	var out: Array[Control] = []
	for c in _cards():
		_collect_chips(c, out)
	return out

func _collect_chips(node: Node, out: Array[Control]) -> void:
	for ch in node.get_children():
		var ctl := ch as Control
		if ctl != null and ctl.has_meta("chip_tip") and ctl.is_visible_in_tree():
			out.append(ctl)
		_collect_chips(ch, out)

## 画出来的色签总数（不带 meta 的也算）：与 _chips 一比就知道有没有漏接的那一颗。
## 自己递归而不是 find_children("TagFlow/*")：那个带路径的模式在「TagFlow 是孙节点」时
## 一条都匹配不到（实测采回 0 颗），拿它当分母就是「零项空判」的现成配方。
func _drawn_chips() -> Array[Control]:
	var out: Array[Control] = []
	for card in _cards():
		_collect_drawn(card, out)
	return out

func _collect_drawn(node: Node, out: Array[Control]) -> void:
	for ch in node.get_children():
		var lbl := ch as Label
		if lbl != null:
			var flow := lbl.get_parent() as HFlowContainer
			if flow != null and flow.name == &"TagFlow" and lbl.has_theme_stylebox("normal"):
				out.append(lbl)
		_collect_drawn(ch, out)

func _cards() -> Array[Node]:
	return _container.get_children()

## 深度优先找第一排色签的容器（反例要摆进「同一排、同一尺寸」才说明问题）
func _first_tag_flow(node: Node) -> HFlowContainer:
	for ch in node.get_children():
		var flow := ch as HFlowContainer
		if flow != null and flow.name == &"TagFlow":
			return flow
		var deeper := _first_tag_flow(ch)
		if deeper != null:
			return deeper
	return null

## 真发一次「按下 → 原地微动 → 抬起」，返回弹出的那张卡的 payload 快照（没弹返回空字典）。
## 顺手量两件事：这一枪确实送到了这颗签身上（引擎记账）、按下不许把走位杆叫醒。
func _tap(target: Control, label: String) -> Dictionary:
	var pos := _center(target)
	await _wait_tips_gone()
	await _press(pos)
	_c.check(target.has_meta(GameStyle._TAP_DOWN_META),
			"%s：这一枪送到了它身上（引擎没记账 ⇒ 落点打歪了）" % label)
	_c.check(not _joy.is_active, "%s 按下时脚下不长摇杆" % label)
	await _motion(pos + Vector2(0, -JITTER))
	await _release(pos + Vector2(0, -JITTER))
	return _collect_tip()

func _swipe(target: Control) -> Dictionary:
	var pos := _center(target)
	await _wait_tips_gone()
	await _press(pos)
	await _motion(pos - Vector2(0, SWIPE * 0.5))
	await _motion(pos - Vector2(0, SWIPE))
	await _release(pos - Vector2(0, SWIPE))
	var got := _collect_tip()
	await _reset_joy()
	return got

## 收卡之前先把 payload 取成字典：DetailTip 淡出 0.1 秒才 free，
## 收完再 live() 就读到 null，内容那一段就成了零项空判。
func _collect_tip() -> Dictionary:
	var payload: Dictionary = {}
	var tip := DetailTip.live(_shop)
	if tip != null:
		payload = tip.payload
		var card := tip.card_rect()
		var vp := _shop.get_viewport_rect()
		_c.check(Rect2(vp.position, vp.size).encloses(card),
				"详情卡整块落在视口内（卡 %s / 视口 %s）" % [str(card), str(vp.size)])
	DetailTip.close_all(_shop)
	return payload

func _wait_tips_gone() -> void:
	DetailTip.close_all(_shop)
	for _i in range(40):
		var any := false
		for ch in _shop.get_children():
			if ch is DetailTip:
				any = true
		if not any:
			return
		await get_tree().process_frame
	push_warning("详解卡 40 帧还没收干净，后续落点不可信")

func _center(c: Control) -> Vector2:
	return c.get_global_rect().get_center()

## 落点换算：get_global_rect() 是画布坐标，push_input 要窗口坐标（720 档 scale 0.75）
func _to_input(pos: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * pos

func _press(pos: Vector2) -> void:
	var p := _to_input(pos)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = p
	e.global_position = p
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_tree().root.push_input(e)
	await get_tree().process_frame

func _release(pos: Vector2) -> void:
	var p := _to_input(pos)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.position = p
	e.global_position = p
	get_tree().root.push_input(e)
	await get_tree().process_frame

func _motion(pos: Vector2) -> void:
	var p := _to_input(pos)
	var m := InputEventMouseMotion.new()
	m.position = p
	m.global_position = p
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_tree().root.push_input(m)
	await get_tree().process_frame

func _reset_joy() -> void:
	if _joy != null and _joy.is_active:
		_joy._stop_joystick()
	await get_tree().process_frame

func _settle(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

# ================================ 反例 ================================

## 判据得拦得住东西：把修复前的形状（同一排、纯 Label、没接热区）原样造一颗打同一枪。
## 旁边留一颗正例，证明「没弹」是热区坏了，不是那一枪没人收到。
func _selftest() -> void:
	_c.check(GameStyle.TAP_SLACK > JITTER and GameStyle.TAP_SLACK < SWIPE,
			"容差 %.0f 夹在「手指微动 %.0f」与「有意划动 %.0f」之间" % [
			GameStyle.TAP_SLACK, JITTER, SWIPE])
	await _open_pinned_shop(int(VP.x))
	var flow := _first_tag_flow(_shop)
	_c.check(flow != null, "反例现场：货架卡上那一排色签找得到")
	if flow == null:
		return

	# 反例：修复前的色签 —— 只画不接（整排原先就是这个形状，点下去什么也不会发生）
	var old_chip := Label.new()
	old_chip.text = " 反例 "
	old_chip.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.GOLD))
	old_chip.mouse_filter = Control.MOUSE_FILTER_STOP
	flow.add_child(old_chip)
	await _settle(2)
	var old_pos := _center(old_chip)
	await _wait_tips_gone()
	await _press(old_pos)
	_c.check(not old_chip.has_meta(GameStyle._TAP_DOWN_META),
			"反例 落点自证：没接热区的那颗压根不记账 ⇒ 所以下面那条「没弹」是热区坏，不是打歪")
	await _motion(old_pos + Vector2(0, -JITTER))
	await _release(old_pos + Vector2(0, -JITTER))
	_c.check(_collect_tip().is_empty(),
			"反例 没接热区的色签同一枪弹不出卡 —— 尺子抓得住整排零热区")
	old_chip.free()

	# 正例：同一排、同一尺寸，接好热区的那一颗必须弹得出来
	var good_chip := Label.new()
	good_chip.text = " 正例 "
	good_chip.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.GOLD))
	flow.add_child(good_chip)
	var tip := {"kind": "behavior", "w_id": "qingyun_sword"}
	ShopOfferCardFactory._mark_chip_tappable(good_chip, tip)
	GameStyle.tap(good_chip, func() -> void: ShopChipTips.open(_shop, good_chip, tip))
	await _settle(2)
	var payload := await _tap(good_chip, "正例 色签")
	_c.check(String(payload.get("title", "")) == "攻击方式 · 近战",
			"正例 同一排接好热区的色签弹得出来（实得「%s」）—— 反例的没弹是热区的锅" % str(payload.get("title", "")))
	good_chip.free()
