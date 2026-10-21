extends Node

## 灵石阁「买不买得看得见」判据：顶栏气血读数 + 货架上回复道具的兑现量 + 按不动的那颗灰键。
## 运行: $G --headless --path . res://tests/ShopReadoutCheck.tscn
##       $G --headless --path . res://tests/ShopReadoutCheck.tscn -- --selftest
##
## 为什么立这条（用户 2026-10-11 真机两条，都不崩、不报错、只有眼睛看得见）：
##  ① 「商店界面也要显示血量，不然也不知道回复道具要不要买」
##     —— 买不买回气丹是当场决定，而这一屏原先只印金币：血条在战斗 HUD 上，商店面板一盖就没了。
##     光把数字摆出来还不够，卡上写的「回多少」必须是真会兑现的那个数：旧版写死「50% 生命」，
##     缺血 20 时买一颗回 60 的丹实际只回 20 —— 印的是承诺，不是账。
##     这里用真 Player、走真按键那一枪（手指 → Button.pressed → ShopSystem.buy_offer →
##     heal() → refresh），量实际涨的血，与卡上那颗数、与顶栏徽记逐位对。
##  ② 「金币不够的商品应该显示灰色按钮，而不是没有按钮了」
##     —— 禁用态没给 stylebox，引擎默认那套是半透明深灰，压在纯黑面板上等于没画。
##     尺子量三件事：那颗键还占着整行位、它有一块**不透明且比面板明显亮**的灰面、
##     字还留着价格与差额。买得起的那颗必须不落在灰档里（灰只留给按不动的）。
##
## 热区一律走引擎拾取：真发按下-微动-抬起（emit_signal 会绕过拾取，热区是死的也照样全绿）；
## 落点从 get_global_rect() 取画布坐标，再经 get_final_transform() 换到窗口坐标（720 档 scale≠1）。
## --selftest 把修复前的形状原样造一遍（读数与血量分家 / 卡面写百分比 / 禁用键没灰面 /
## 热区没接线），四把尺子各须报一次红，才算有牙齿。

## 4:3 平板 / 16:9 基准 / 20:9 宽屏（与 LayoutCheck 同一套档位）
const WIDTHS: Array[int] = [720, 960, 1204]
const EPS := 0.6
## 钉的样本血量 100/120：缺血 20 < 一颗丹的名义量 60 ⇒ 「印的量」与「兑现的量」必然不相等，
## 只有按当前缺血截断的写法能过
const CUR_RATIO := 5.0 / 6.0
const LOW_RATIO := 0.1          ## 危险档样本（低于 GameBalance.HP_LOW_RATIO）
const POTION_PRICE := 11
## 按下后原地的微动：必须明显小于 GameStyle.TAP_SLACK，否则「根本点不动」也会被判成通过
const JITTER := 4.0
## 灰面的亮度带：面板是纯黑（0），亮面键是 0.6 以上（金币那颗 0.81），
## 中间这一档才是「看得见、但明摆着按不动」的灰
const GRAY_MIN := 0.08
const GRAY_MAX := 0.45

var _c := TestCheck.new()
var _main: Node
var _shop: Control
var _player: Player

func _ready() -> void:
	get_tree().root.size = Vector2i(960, 540)
	call_deferred("_boot")

func _boot() -> void:
	_main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(_main)
	await _settle(3)
	GameManager.cultivator_id = ""
	GameManager.start_run("qingyun_sword")
	await _settle(3)
	_player = GameManager.player as Player
	_c.check(_player != null, "真 Player 已生成（不建 Player 就量不到血量这条链）")
	if _player == null:
		_quit()
		return
	_shop = _main.get_node_or_null("UILayer/WaveShop") as Control
	_c.check(_shop != null, "Main 里有灵石阁节点")
	if _shop == null:
		_quit()
		return
	_quiet_arena()
	if "--selftest" in OS.get_cmdline_user_args():
		await _selftest()
	else:
		await _main_cases()
	_quit()

## 场地静音：刷怪器不再出人、场上妖物散掉、回复不再自己涨血，血量只由本判据自己写
func _quiet_arena() -> void:
	var spawner: Node = GameManager.wave_spawner
	if spawner != null:
		spawner.set_process(false)
		spawner.set_physics_process(false)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is EnemyBase:
			enemy.dissolve()
	GameManager.hp_regen = 0.0
	GameManager.synergy_hp_regen = 0.0

func _set_hp(ratio: float) -> void:
	_player.current_health = _player.max_health * ratio
	GameManager.player_hp_changed.emit(_player.current_health, _player.max_health)

## 开一次货架，钉成「回气丹 + 一把买得起 + 一把买不起 + 一颗已售出」四格样本
func _open_shop(stones: int) -> void:
	GameManager.spirit_stones = stones
	GameManager.shop_slots_bonus = 0
	GameManager.roll_shop(true)
	var offers: Array = GameManager.shop_offers
	offers[0] = {"kind": "potion", "id": WeaponData.POTION_ID, "price": POTION_PRICE,
		"sold": false, "locked": false}
	if offers.size() > 1:
		offers[1] = {"kind": "weapon", "id": "chiyan_dao", "price": 41,
			"sold": false, "locked": false}
	if offers.size() > 2:
		offers[2] = {"kind": "weapon", "id": "liuye_feidao", "price": 400,
			"sold": false, "locked": false}
	if offers.size() > 3:
		offers[3] = {"kind": "weapon", "id": "wulei_paizi", "price": 20,
			"sold": true, "locked": false}
	_shop._on_shop_opened()
	# 等真实时间，不等帧数：货架卡是错峰缩放入场（每格延 0.045s、0.22s 从 0.82 长到 1.0），
	# headless 一帧不到 1ms，等 3 帧动画根本没落定 —— 按下与抬起之间那颗键已经挪走十几像素，
	# 引擎判成「松开时不在键上」，pressed 永远不发（实测踩过：按钮 button_down 响了、买没成）。
	await get_tree().create_timer(0.8).timeout
	await _settle(2)

func _close_shop() -> void:
	DetailTip.close_all(_shop)
	_shop.visible = false
	get_tree().paused = false
	# 详情卡是 0.1 秒淡出后才 destroy 的：那张全屏遮罩还挂在树上，按 STOP 把下一枪就地吃掉。
	# 等真实时间而不是帧数（headless 帧率不固定），否则下一枪打在空气上、看起来像热区坏了。
	await get_tree().create_timer(0.35).timeout
	await _settle(2)

# ================================ 正判 ================================

func _main_cases() -> void:
	# ---- ① 顶栏气血徽记：画没画、对不对、三档屏点不点得到 ----
	for w in WIDTHS:
		get_tree().root.size = Vector2i(w, 540)
		await _settle(2)
		_set_hp(CUR_RATIO)
		await _open_shop(60)
		var tag := "屏宽 %d" % w
		var area: Vector2 = get_tree().root.get_visible_rect().size
		var chip := _hp_chip()
		if chip == null:
			_c.check(false, "%s · 顶栏没有气血徽记（这一屏看不见血量）" % tag)
			continue
		var r: Rect2 = chip.get_global_rect()
		_c.check(chip.visible and r.size.x > 20.0 and r.size.y > 10.0,
			"%s · 气血徽记画出来了 %.0fx%.0f（读成 0x0 就是压根没摆）" % [tag, r.size.x, r.size.y])
		_c.check(r.position.x >= 0.0 and r.end.x <= area.x and r.position.y >= 0.0 \
				and r.end.y <= area.y,
			"%s · 气血徽记整块在屏内 x=%.0f..%.0f / 可视 %.0fx%.0f" % [
				tag, r.position.x, r.end.x, area.x, area.y])
		_c.check(_chip_text() == _want_chip_text(),
			"%s · 徽记读数与玩家血量同源（期望「%s」实得「%s」）" % [
				tag, _want_chip_text(), _chip_text()])
		# 顶栏东西一多就把右端的「属性」推出屏（2026-10-08 踩过的那格）：
		# 量「顶栏要的最小宽」vs「面板给得起的内宽」，不读布局盒实得（实得永远自洽）
		var want_w := _topbar_min_w()
		var give_w: float = WaveShop.panel_inner_w(area)
		_c.check(want_w <= give_w + 0.5,
			"%s · 顶栏摆得进面板（要 %.0f，面板只给 %.0f，差 %.0f）" % [
				tag, want_w, give_w, want_w - give_w])
		var title := await _tap_at(chip)
		_c.check(title == "生命", "%s · 点徽记弹出「生命」拆解（实得「%s」）" % [tag, title])
		var tip := DetailTip.live(_shop)
		if tip != null:
			var tr := tip.card_rect()
			_c.check(tr.position.x >= 0.0 and tr.end.x <= area.x + EPS \
					and tr.position.y >= 0.0 and tr.end.y <= area.y + EPS,
				"%s · 气血拆解卡整块在屏内（%.0f,%.0f %.0fx%.0f）" % [
					tag, tr.position.x, tr.position.y, tr.size.x, tr.size.y])
			_c.check((tip.payload.get("rows", []) as Array).size() >= 3,
				"%s · 拆解卡里有当前/每秒回复/这一口实际回三条读数" % tag)
		await _close_shop()

	# ---- ② 危险档要看得出来：整块翻朱砂，不是只换个字色 ----
	_set_hp(LOW_RATIO)
	await _open_shop(60)
	_c.check(_chip_face() == GameStyle.BAD,
		"残血（%d%%）· 徽记底色翻朱砂，实得 %s" % [int(LOW_RATIO * 100), str(_chip_face())])
	_c.check(await _tap_at(_hp_chip()) == "生命", "残血 · 点得开拆解")
	await _close_shop()
	_set_hp(CUR_RATIO)
	await _open_shop(60)
	_c.check(_chip_face() != GameStyle.BAD,
		"七成半血 · 徽记不装危险（底色 %s）" % str(_chip_face()))
	await _close_shop()

	# ---- ③ 卡面那颗数 == 真涨上去的那截血（走手指那一枪，不走后门）----
	_set_hp(CUR_RATIO)
	await _open_shop(60)
	var printed := _potion_heal_printed()
	var nominal := int(round(GameBalance.potion_heal_amount(_player.max_health)))
	var want := int(round(_player.max_health - _player.current_health))
	_c.check(printed == want,
		"卡面印的是兑现量 +%d（缺血 %d，名义量 %d）" % [printed, want, nominal])
	_c.check(printed != nominal, "布置成立：这一口本来就回不满，写百分比必然骗人")
	var before := _player.current_health
	var stones_before := GameManager.spirit_stones
	await _tap_at(_price_btn(0), false, false)
	await _settle(3)
	_c.near(_player.current_health - before, float(printed), EPS,
		"点一次购买，实际涨的血与卡上印的那颗数逐位相同")
	_c.equals(stones_before - GameManager.spirit_stones, POTION_PRICE, "扣的钱就是标价")
	_c.check(_chip_text() == _want_chip_text(),
		"买完顶栏徽记跟着改口：期望「%s」实得「%s」" % [_want_chip_text(), _chip_text()])
	_c.check(_price_btn(0) != null and _price_btn(0).disabled and _is_gray(_face_of(_price_btn(0))),
		"买完这一格转成看得见的灰键（已售出）")
	await _close_shop()

	# ---- ④ 满血时不许承诺回血 ----
	_set_hp(1.0)
	await _open_shop(60)
	_c.check(_potion_heal_printed() == 0,
		"满血 · 卡面写 +0（实得 +%d）" % _potion_heal_printed())
	await _close_shop()

	# ---- ⑤ 买不起 / 已售出：灰键还在，价格与差额还写着 ----
	_set_hp(0.5)
	await _open_shop(60)
	var afford := _price_btn(1)
	var poor := _price_btn(2)
	var sold := _price_btn(3)
	_c.check(afford != null and poor != null and sold != null, "三张卡的价格键都找得到")
	if poor != null:
		_c.check(poor.disabled, "买不起的那颗键是禁用的")
		_c.check(_is_gray(_face_of(poor)),
			"买不起 · 键上有一块比面板明显亮的实心灰面（实得 %s）" % str(_face_of(poor)))
		_c.check(poor.text.contains("400") and poor.text.contains("差 340"),
			"买不起 · 键上留着价格与差额：「%s」" % poor.text)
		_c.check(_disabled_text_readable(poor), "买不起 · 禁用态的字色看得见（非透明非纯黑）")
		var pr: Rect2 = poor.get_global_rect()
		_c.check(pr.size.y >= 28.0, "买不起 · 这颗键还占着整行高（%.0f）" % pr.size.y)
	if afford != null:
		_c.check(not afford.disabled, "买得起的那颗键能按")
		_c.check(not _is_gray(_face_of(afford)),
			"买得起 · 不是灰面（灰只留给按不动的），实得 %s" % str(_face_of(afford)))
	if sold != null:
		_c.check(sold.disabled and _is_gray(_face_of(sold)), "已售出 · 同样是颗看得见的灰键")
		_c.check(sold.text.contains("售"),
			"已售出 · 文字仍说明为什么按不动：「%s」" % sold.text)
	await _close_shop()

# ================================ 取数 ================================

func _hp_chip() -> Control:
	for ch in _top_bar().get_children():
		if ch is ShopHpChip:
			return ch as Control
	return null

func _top_bar() -> HBoxContainer:
	return _shop.get_node("CenterContainer/Panel/MarginContainer/VBox/TopBar") as HBoxContainer

## 顶栏要的最小宽：Spacer 是弹性件（最小 0），所以这个和就是「一个都不许折」时的硬需求
func _topbar_min_w() -> float:
	var m := 0.0
	var kids := _top_bar().get_children()
	for ch in kids:
		if ch is Control and (ch as Control).size_flags_horizontal != Control.SIZE_EXPAND_FILL:
			m += (ch as Control).get_combined_minimum_size().x
	return m + float(_top_bar().get_theme_constant("separation")) * float(maxi(kids.size() - 1, 0))

## 徽记该印的那串字：词 + 与 HUD 同格式的分数（写死一处，三档屏共用）
func _want_chip_text() -> String:
	return "生命 %d/%d" % [int(_player.current_health), int(_player.max_health)]

func _chip_text() -> String:
	var chip := _hp_chip()
	return (chip as ShopHpChip).get_value_text() if chip != null else ""

## 徽记现在这块底的颜色（stylebox 是唯一取色口径，读 modulate 量不到换色）
func _chip_face() -> Color:
	var chip := _hp_chip()
	if chip == null:
		return Color()
	var sb: StyleBox = (chip as Control).get_theme_stylebox("panel")
	return (sb as StyleBoxFlat).bg_color if sb is StyleBoxFlat else Color()

## 卡面上「回复气血」那一行的读数（BonusRows 的右列）；解析不出正数 = 卡的不是兑现量
func _potion_heal_printed() -> int:
	var card := _offer_card(0)
	if card == null:
		return -9999
	var rows := _find_named(card, "BonusRowsBlock") as Control
	if rows == null:
		return -9998
	for row in rows.get_children():
		var r := row as Control
		if r == null or r.get_child_count() == 0 or not (r.get_child(0) is Label):
			continue
		if String((r.get_child(0) as Label).text) != "回复生命":
			continue
		var val := _value_label(r)
		if val != null:
			return _parse_gain(String(val.text))
	return -9997

## 只认「+20」这种能直接兑现的数：「50% 生命」这类写法返回 -1，
## 于是反例⑤（卡面退回百分比）与「压根没这一行」都能被同一条尺子抓住。
static func _parse_gain(txt: String) -> int:
	var t := txt.replace(" ", "")
	if not t.begins_with("+"):
		return -1
	var digits := t.substr(1)
	if digits.is_empty():
		return -1
	for i in range(digits.length()):
		if digits[i] < "0" or digits[i] > "9":
			return -1
	return int(digits)

func _offer_card(i: int) -> Control:
	var real: Array[Control] = []
	for ch in _shop.offers_container.get_children():
		if ch is Control and not (ch as Control).is_queued_for_deletion():
			real.append(ch as Control)
	return real[i] if i < real.size() else null

## 卡底那颗价格键（custom_minimum_size = (0, 32)；卡里的「锁定」角键是 (40, 24)，认得开）
func _price_btn(i: int) -> Button:
	var card := _offer_card(i)
	if card == null:
		return null
	var stack: Array[Node] = [card]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var b := n as Button
		if b != null and b.custom_minimum_size.x == 0.0 and b.custom_minimum_size.y >= 30.0:
			return b
		for ch in n.get_children():
			stack.append(ch)
	return null

static func _find_named(n: Node, nm: String) -> Node:
	if String(n.name) == nm:
		return n
	for ch in n.get_children():
		var hit := _find_named(ch, nm)
		if hit != null:
			return hit
	return null

## 一行的右列（make_row：名字 Label + 弹性 Control + 数值 Label）
static func _value_label(row: Control) -> Label:
	if row == null:
		return null
	var last: Label = null
	for ch in row.get_children():
		if ch is Label:
			last = ch as Label
	return last

## 这颗键现在这张脸的颜色：禁用读 disabled，能按读 normal（两者都是 GameStyle.button 给的）
static func _face_of(btn: Button) -> Color:
	var sb: StyleBox = btn.get_theme_stylebox("disabled" if btn.disabled else "normal")
	return (sb as StyleBoxFlat).bg_color if sb is StyleBoxFlat else Color()

## 「看得见但按不动」那一档灰：必须是不透明的实心面，亮度明显高出纯黑面板、
## 又明显低于能按的亮面。引擎默认那套 disabled 是半透明深灰，压在黑面板上
## 混出来就是黑的 —— 那正是「没有按钮」的成因，这里用 alpha 与亮度两把尺一起拦。
static func _is_gray(face: Color) -> bool:
	return face.a > 0.9 and face.get_luminance() >= GRAY_MIN \
			and face.get_luminance() <= GRAY_MAX

static func _disabled_text_readable(btn: Button) -> bool:
	var col: Color = btn.get_theme_color("font_disabled_color")
	return col.a > 0.5 and col.get_luminance() > 0.25

# ================================ 拾取 ================================

## 落点换算：get_global_rect() 是画布（设计）坐标，push_input 要窗口坐标。
## 720 这类非 1:1 档下 expand 会把画布拉到 960×720（scale 0.75），不打折就打歪（实测踩过）。
func _to_input(pos: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * pos

static func _center(c: Control) -> Vector2:
	var r := c.get_global_rect()
	return r.position + r.size * 0.5

## 真发一次「按下 → 原地微动 → 抬起」。返回宿主上弹出的卡标题（没弹返回空串）。
## 顺带打印这一枪有没有落在那颗控件身上（引擎记账）——落点打歪与热区是死的，两回事。
## check_landing=false 只给两类目标用：Button（自己吃事件，不走 GameStyle.tap 的记账）、
## 以及反例里那颗本来就没接线的裸控件（没记账正是要判的东西）。
func _tap_at(target: Control, check_landing := true, jitter := true) -> String:
	if target == null:
		return ""
	await _wait_tips_gone()
	var pos := _to_input(_center(target))
	# 先送一次「移动到落点」再按下：BaseButton 在抬起那一刻还要看 is_hovered()，
	# 而 hover 是 motion 事件建立的 —— 只发按下/抬起，button_down 会响、pressed 永远不发
	# （真机上手指移动总在按下之前，这里补上这一拍才是生产路径的形状）。
	await _motion(pos)
	await _press(pos)
	var landed := _landed_on(target)
	# jitter=true 给 GameStyle.tap 那类热区：手指原地漂 4 单位仍须算一次点按（小于 TAP_SLACK）。
	# jitter=false 给 BaseButton：按下与抬起之间插一次微动，引擎就不发 pressed 了
	# （hover 一路是真，mouse_status 却被那次 motion 判成了离开）—— 实测踩过，别照抄。
	var end := pos + Vector2(0, -JITTER) if jitter else pos
	if jitter:
		await _motion(end)
	await _release(end)
	await get_tree().process_frame
	await get_tree().process_frame
	var tip := DetailTip.live(_shop)
	var title := "" if tip == null else String((tip.payload as Dictionary).get("title", ""))
	print("[INFO] 落点 %s 记账=%s → %s" % [str(pos), str(landed), \
			("卡「" + title + "」") if tip != null else "没弹卡/没触发"])
	if check_landing:
		_c.check(landed, "这一枪确实送到了那颗控件上（引擎没记账 ⇒ 落点打歪了）")
	return title

## GameStyle.tap 在收到「按下」时会在落在的那颗节点上记账；按钮自己吃事件，
## 所以按钮这一路改读它有没有真的 pressed（由调用方按结果断言）。
func _landed_on(target: Control) -> bool:
	var stack: Array[Node] = [target]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Control and (n as Control).has_meta(GameStyle._TAP_DOWN_META):
			return true
		for ch in n.get_children():
			stack.append(ch)
	return false

func _wait_tips_gone() -> void:
	for i in range(60):
		if not _any_tip_in_tree():
			return
		await get_tree().process_frame
	push_warning("详解卡 60 帧还没收干净，后续落点不可信")

## 连正在淡出的那张也算：live() 故意不认它（怕读到上一张的内容），
## 但它那张全屏遮罩还挂在树上按 STOP 收事件 —— 拿它当「没有卡」就会把下一枪打在空气上。
func _any_tip_in_tree() -> bool:
	var stack: Array[Node] = [_shop]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is DetailTip:
			return true
		for ch in n.get_children():
			stack.append(ch)
	return false

func _press(pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.global_position = pos
	e.position = pos
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_tree().root.push_input(e)
	await get_tree().process_frame

func _motion(pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.global_position = pos
	e.position = pos
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	e.relative = Vector2(0, -JITTER)
	get_tree().root.push_input(e)
	await get_tree().process_frame

func _release(pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.global_position = pos
	e.position = pos
	get_tree().root.push_input(e)
	await get_tree().process_frame

func _settle(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame
		if get_tree().paused:
			get_tree().paused = false

# ================================ 反例（判据的牙齿）================================

## 把修复前的四种形状原样造出来，量同一把尺子，必须各报一次红
func _selftest() -> void:
	_set_hp(CUR_RATIO)
	await _open_shop(60)

	# 反例① 徽记读数与血量分家：写死一个数
	var chip := _hp_chip()
	_c.check(chip != null, "正例 顶栏有气血徽记")
	_c.check(_chip_text() == _want_chip_text(), "正例 徽记读数与血量同源（%s）" % _chip_text())
	(chip as ShopHpChip).set_value(1.0, 120.0)
	_c.check(_chip_text() != "%d/%d" % [int(_player.current_health), int(_player.max_health)],
		"反例① 读数与血量分家被拦住（喂成 1/120 后不再相等）")
	(chip as ShopHpChip).set_value(_player.current_health, _player.max_health)

	# 反例②③ 禁用键没有灰面：先摘掉覆盖退回引擎默认那套，再换成与面板同色的黑面
	var poor := _price_btn(2)
	_c.check(poor != null and _is_gray(_face_of(poor)), "正例 买不起的键有实心灰面")
	poor.remove_theme_stylebox_override("disabled")
	_c.check(not _is_gray(_face_of(poor)),
		"反例② 引擎默认的禁用面被拦住（实得 %s：压在黑面板上看不见）" % str(_face_of(poor)))
	poor.add_theme_stylebox_override("disabled", GameStyle.block(GameStyle.NAVY2))
	_c.check(not _is_gray(_face_of(poor)),
		"反例③ 灰面与面板同色（纯黑）也被拦住（实得 %s）" % str(_face_of(poor)))

	# 反例④ 热区没接线：旁边摆一颗裸 PanelContainer，同一把尺子必须报「点了没反应」
	var bare := PanelContainer.new()
	_shop.add_child(bare)
	bare.custom_minimum_size = Vector2(80, 24)
	await get_tree().process_frame
	_c.check(await _tap_at(bare, false) == "", "反例④ 没接点击的热区弹不出卡（就是颗坏控件）")
	bare.queue_free()
	await get_tree().process_frame

	# 反例⑤ 卡面写百分比：把读数换成旧文案，解析器要认不出兑现量
	var rows := _find_named(_offer_card(0), "BonusRowsBlock") as Control
	var val := _value_label(rows.get_child(0) as Control)
	_c.check(_potion_heal_printed() == int(round(_player.max_health - _player.current_health)),
		"正例 卡面印的是缺血截断后的兑现量（+%d）" % _potion_heal_printed())
	val.text = "50% 生命"
	_c.check(_potion_heal_printed() < 0, "反例⑤ 卡面退回百分比文案被拦住（读不出兑现量）")
	await _close_shop()

func _quit() -> void:
	var prefix := "SHOPREADOUT_SELFTEST_RESULT" \
			if "--selftest" in OS.get_cmdline_user_args() else "SHOPREADOUT_RESULT"
	get_tree().quit(0 if _c.report(prefix) else 1)
