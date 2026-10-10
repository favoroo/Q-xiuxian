extends Node

## 判据：战斗 HUD 左上角那两排（羁绊徽记 + 法器图标槽）必须「点得到、弹对卡」，
## 而且按下那一下不许在脚下长出一根摇杆。
## 运行: $G --headless --path . res://tests/HudHotzoneTapCheck.tscn
##       $G --headless --path . res://tests/HudHotzoneTapCheck.tscn -- --selftest
##
## 为什么立这条（用户 2026-10-10：左上角这些图标点了没反应）：
##  ① 徽记的详情卡一直点不出来。调用方写成 `var chip; chip = create_chip(.., func(): open(tag, chip))`，
##     而 GDScript 的 lambda 在创建那一刻就按值捕获局部变量（官方文档：Local variables are captured
##     by value once, when the lambda is created），捕获到的 chip 永远是 null ⇒ 详情卡拿到空锚点，
##     被 DetailTip.show_over 的空锚点守卫静默 return。不崩、不报错、不打日志，
##     所以 UnitRunner / SmokeRunner 全绿也照样看不见 —— 触屏没有 hover，这就是控件是坏的。
##  ② 法器那一排 6 格全程 MOUSE_FILTER_IGNORE，压根没接任何输入。
##  ③ JoystickHoldCheck 当年明写「现场自造，不实例化 GameHUD ⇒ HUD 里那两处登记本判据测不到」，
##     这条判据就是去补那个洞：走真 Main 场景、真 start_run、真 add_weapon，让徽记和槽位
##     由 WeaponInventory 自己长出来，再拿手指该落的那个坐标去撞。
##
## 尺子只认引擎拾取：事件用 Input.parse_input_event 真发按下/微动/抬起，绝不 emit_signal
## （emit 会绕过拾取，热区是死的也照样全绿）。
## 防假 PASS：① 先自证「空白处按下能叫醒摇杆」，否则后面每一条「没长摇杆」都是空判；
## ② 徽记/槽位数不足、点完 live() 是 null、读数与数据表对不上，一律 FAIL；
## ③ --selftest 把修复前的形状原样造一颗打同一枪，必须报出「点了没反应」，才算有牙齿。

## 默认 960（桌面调试档）；判据可用 --width= 换档，真机三档 720 / 960 / 1204 都要卡不探出屏
const VIEWPORT_SIZE := Vector2i(960, 540)
## 手指按在原地的微动：必须明显小于 GameStyle.TAP_SLACK，否则「根本点不动」也会被判成通过
const JITTER := 4.0
## 有意划动：必须明显大于 TAP_SLACK，否则测的不是「划」
const SWIPE := 70.0
## 槽角取样往里缩这么多：斜切 stylebox 的尖角本来就不在可点区里
const CORNER_INSET := 6.0
## 自证派发通路用的空白点：顶栏（y 小于 132）与右下技能键都够不着的地方
const FREE_POS := Vector2(420, 400)

const CULTIVATOR := "fuzhen"
const START_WEAPON := "qingyun_sword"
const FILL_WEAPON := "huoyan_fu"

var _c := TestCheck.new()
var _main: Node
var _hud: Control
var _joy: DawnJoystick

func _ready() -> void:
	call_deferred("_boot")

func _boot() -> void:
	var w := VIEWPORT_SIZE.x
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--width="):
			w = int(String(a).trim_prefix("--width="))
	get_tree().root.size = Vector2i(w, VIEWPORT_SIZE.y)
	_main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(_main)
	await _settle(4)
	GameManager.cultivator_id = CULTIVATOR
	GameManager.start_run(START_WEAPON)
	get_tree().paused = false
	# 走生产入口补两把同标签武器：三把火焰符 ⇒ 「弹射」徽记自己长出来，不手抄 active_synergies
	GameManager.add_weapon(FILL_WEAPON)
	GameManager.add_weapon(FILL_WEAPON)
	if GameManager.player != null:
		GameManager.player.max_health = 99999.0
		GameManager.player.current_health = 99999.0
	_hud = _main.get_node_or_null("UILayer/GameHUD") as Control
	_joy = _main.get_node_or_null("UILayer/VirtualJoystick") as DawnJoystick
	_clear_overlays()
	# 徽记与槽位都是 queue_free 重建的，等旧那批真离树再取样
	await _settle(10)
	if "--selftest" in OS.get_cmdline_user_args():
		await _selftest()
	else:
		await _run()
	get_tree().quit(0 if _c.report("HUDZONE_RESULT") else 1)

# ================================ 正判 ================================

func _run() -> void:
	_c.check(_hud != null, "GameHUD 挂在 UILayer 下（实得 %s）" % str(_hud))
	_c.check(_joy != null, "VirtualJoystick 挂在 UILayer 下（实得 %s）" % str(_joy))
	if _hud == null or _joy == null:
		return

	# 前提自证：先把「事件送得到谁」量一遍，再决定后面哪些断言不算空判
	_dump_stage()
	await _probe_dispatch()
	await _run_chips()
	await _run_slots()
	await _run_swipe_and_rebuild()

## 判据走 start_run 这条捷径，跳过了「主菜单 → 选道统 → 选本命法器」那一串面板，
## 可它们还挂在树上：StartMenu 的整屏 STOP 底板与居中大按钮正盖在左上角之上，
## 不清场测到的就是「菜单挡不挡道」—— 实测徽记与槽位一个事件都收不到、整判据全红。
func _clear_overlays() -> void:
	for ch in _hud.get_parent().get_children():
		var c := ch as Control
		if c != null and c != _hud and c.name != &"VirtualJoystick" and c.visible:
			c.visible = false

## 现场有没有整屏面板还压着 HUD：有就是判据自己的前提没立住，直接报红而不是让后面全空判
func _dump_stage() -> void:
	var cover: Array[String] = []
	for ch in _hud.get_parent().get_children():
		var c := ch as Control
		if c != null and c.visible and c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			cover.append("%s(%d)" % [c.name, c.mouse_filter])
	print("[INFO] paused=%s 顶层未 IGNORE 的可见控件: %s" % [str(get_tree().paused), str(cover)])
	_c.check(not cover.any(func(n: String) -> bool: return not n.begins_with("VirtualJoystick")),
		"前提：除了摇杆，没有第二块整屏面板压在 HUD 之上（实得 %s）" % str(cover))

## 分别量两条派发路：ScreenTouch 走摇杆那条，MouseButton 走 gui_input 那条。
## 哪条不通，对应断言就得改口径，不许把「没收到事件」当成「没问题」。
func _probe_dispatch() -> void:
	await _reset_joy()
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.pressed = true
	t.position = _to_input(FREE_POS)
	get_tree().root.push_input(t)
	await get_tree().process_frame
	var by_touch := _joy.is_active
	await _release_touch(FREE_POS)
	await _reset_joy()
	await _press(FREE_POS)
	var by_mouse := _joy.is_active
	await _release(FREE_POS)
	await _reset_joy()
	print("[INFO] 空白处按下：ScreenTouch 叫醒摇杆=%s，MouseButton 叫醒摇杆=%s" % [str(by_touch), str(by_mouse)])
	_c.check(by_touch, "前提：空白处发 ScreenTouch 能叫醒摇杆（摇杆这条派发路是活的）")

func _run_chips() -> void:
	var chips := _chips()
	_c.check(chips.size() >= 2, "顶栏长出 %d 枚羁绊徽记（少于 2 枚等于没测）" % chips.size())
	print("[INFO] 徽记矩形: ", chips.map(func(c: Label) -> String: return str(c.get_global_rect())))
	var want_titles := _titles_from_data()
	for chip in chips:
		var title := chip.text.strip_edges()
		_c.check(chip.is_in_group(DawnJoystick.UI_PRESS_HOLD_GROUP),
			"徽记「%s」登记了 ui_press_hold（非按钮热区摇杆认不出）" % title)
		_c.check(chip.gui_input.get_connections().size() > 0,
			"徽记「%s」真挂了点按回调（尺子活着，不是回退值）" % title)
		_c.check(want_titles.has(title),
			"徽记读数「%s」与羁绊数据表独立算出来的一致（实算 %s）" % [title, str(want_titles.keys())])
		var got := await _tap_at(_hud, chip, "徽记「%s」" % title)
		_c.check(got == title, "点徽记「%s」弹出同名流派详情卡（实得「%s」）" % [title, got])

func _run_slots() -> void:
	var slots := _slots()
	_c.check(slots.size() == WeaponData.MAX_SLOTS,
		"法器槽一排 %d 格（期望 %d）" % [slots.size(), WeaponData.MAX_SLOTS])
	print("[INFO] 视口 %s 槽位矩形: " % str(_hud.get_viewport().get_visible_rect().size),
		slots.map(func(c: Control) -> String: return str(c.get_global_rect())))
	var summary: Array = GameManager.get_weapons_summary()
	_c.check(not summary.is_empty(), "开局武器与补的武器都在阵上（%d 件）" % summary.size())
	var filled_done := false
	var empty_done := false
	for i in range(slots.size()):
		var slot := slots[i] as Control
		var want := _slot_title(summary, i)
		var filled := i < summary.size()
		_c.check(slot.is_in_group(DawnJoystick.UI_PRESS_HOLD_GROUP),
			"法器槽第 %d 格登记了 ui_press_hold" % (i + 1))
		_c.check(slot.mouse_filter == Control.MOUSE_FILTER_STOP,
			"法器槽第 %d 格本体收事件（实得 %d，2 就是 IGNORE）" % [i + 1, slot.mouse_filter])
		var got := await _tap_at(_hud, slot, "法器槽第 %d 格" % (i + 1))
		_c.check(got == want, "点法器槽第 %d 格弹「%s」（实得「%s」）" % [i + 1, want, got])
		# 角上再各打一枪：图框与 ★ 压在槽面上，只要有一层没让开就是中间一个按不动的洞。
		# 满格与空格各抽一格就够（一枪四个落点，全打会把判据拖到波次结束）。
		if (filled and not filled_done) or (not filled and not empty_done):
			if filled:
				filled_done = true
			else:
				empty_done = true
			for corner in _corners(slot):
				var g := await _tap_at(_hud, slot, "法器槽第 %d 格角上" % (i + 1), corner)
				_c.check(g == want, "第 %d 格角上 %s 也点得动（实得「%s」）" % [i + 1, str(corner), g])

func _run_swipe_and_rebuild() -> void:
	var chips := _chips()
	var slots := _slots()
	# 划过去不算点：识别器换成 GameStyle.tap 之后，这条在新地方照样得成立
	if not chips.is_empty():
		_c.check(await _swipe_at(_hud, chips[0], SWIPE) == "",
			"在徽记上划 %.0f 单位再松手不许弹卡" % SWIPE)
	if not slots.is_empty():
		_c.check(await _swipe_at(_hud, slots[0], SWIPE) == "",
			"在法器槽上划 %.0f 单位再松手不许弹卡" % SWIPE)
	if chips.is_empty() or slots.is_empty():
		return
	# 上阵一变整排就重建：摊在暗底下的旧卡报的是旧数，必须先收掉。
	# 这里不用 _tap_at —— 它收尾会把卡收掉，那张卡正是这一段要读的东西。
	await _wait_tips_gone(_hud)
	var rp := _center(slots[0])
	await _press(rp)
	await _motion(rp + Vector2(0, -JITTER))
	await _release(rp + Vector2(0, -JITTER))
	await get_tree().process_frame
	_c.check(DetailTip.live(_hud) != null, "点开后宿主上确实有一张卡（后面那条收卡判定才不是空判）")
	GameManager.notify_weapons_updated(GameManager.get_weapons_summary())
	await _settle(2)
	_c.check(DetailTip.live(_hud) == null, "上阵刷新 ⇒ 旧详情卡被收掉（不许停在暗底下报旧数）")
	await _wait_tips_gone(_hud)
	await _reset_joy()

# ============================ 独立算一遍期望值 ============================

## 徽记读数由数据表自己算，不叫 SynergyUI 报 —— 它错成什么判据就跟着说什么，等于没判
func _titles_from_data() -> Dictionary:
	var out: Dictionary = {}
	for tag in GameManager.active_synergies.keys():
		var data: Dictionary = GameManager.active_synergies[tag]
		if int(data.get("count", 0)) <= 0 or not WeaponData.SYNERGIES.has(String(tag)):
			continue
		out[_chip_title(String(tag))] = String(tag)
	return out

func _chip_title(tag: String) -> String:
	var info: Dictionary = WeaponData.SYNERGIES[tag]
	var raw_th: Array = info.get("thresholds", [2, 4, 6])
	var shift: int = 0
	if tag == "spirit":
		shift = GameManager.spirit_threshold_adj
	elif tag == "contraption":
		shift = GameManager.contraption_threshold_adj
	var max_th: int = maxi(1, int(raw_th[raw_th.size() - 1]) - shift)
	var n: int = int((GameManager.active_synergies[tag] as Dictionary).get("count", 0))
	return "%s (%d/%d)" % [String(info.get("name", tag)), n, max_th]

## 槽位卡的标题与 StatsTipFactory 同一套拼法（名字 + 星级 / 空槽 / 锁定槽）
func _slot_title(summary: Array, i: int) -> String:
	if i < summary.size():
		var w: Dictionary = summary[i]
		var def := WeaponData.get_def(String(w.get("id", "")))
		var star := clampi(int(w.get("star", 1)), 1, WeaponData.MAX_STAR)
		return "%s %s" % [String(def.get("name", "?")), WeaponData.star_text(star)]
	return "锁定武器位" if i >= GameManager.max_weapon_slots() else "空武器位"

# ============================== 取样与手势 ==============================

func _chips() -> Array[Label]:
	var out: Array[Label] = []
	var box: HBoxContainer = _hud.get("_synergy_box")
	if box == null:
		return out
	for ch in box.get_children():
		var lbl := ch as Label
		if lbl != null and lbl.is_visible_in_tree():
			out.append(lbl)
	return out

func _slots() -> Array[Control]:
	var out: Array[Control] = []
	var bar: HBoxContainer = _hud.get("weapons_bar")
	if bar == null:
		return out
	for ch in bar.get_children():
		if ch is Control and (ch as Control).is_visible_in_tree():
			out.append(ch as Control)
	return out

func _center(c: Control) -> Vector2:
	return c.get_global_rect().get_center()

func _corners(c: Control) -> Array[Vector2]:
	var r := c.get_global_rect()
	return [
		r.position + Vector2(CORNER_INSET, CORNER_INSET),
		Vector2(r.end.x - CORNER_INSET, r.position.y + CORNER_INSET),
		Vector2(r.position.x + CORNER_INSET, r.end.y - CORNER_INSET),
		r.end - Vector2(CORNER_INSET, CORNER_INSET),
	]

## 真发一次「按下 → 原地微动 → 抬起」，返回宿主上弹出的卡标题（没弹返回空串）。
## 每一枪顺手量两件事：① 按下那一下不许把走位杆叫醒；② 这一枪确实送到了我要的那颗控件上
## —— 第二条是防「落点打歪」冒充「热区是坏的」：720 档画布/窗口两套坐标差一个 scale，
## 打歪时徽记那一排会整排红，看起来像真 bug（实测踩过）。GameStyle.tap 在收到按下时会在
## 那颗控件上留 _gs_tap_down 记账，读它就等于问引擎「这一枪落在谁身上」。
func _tap_at(host: Control, target: Control, label: String, at := Vector2(INF, INF)) -> String:
	var pos: Vector2 = at if at.x < INF.x else _center(target)
	await _wait_tips_gone(host)
	await _press(pos)
	_c.check(target.has_meta(GameStyle._TAP_DOWN_META),
		"%s：这一枪确实送到了它身上（引擎没记账 ⇒ 落点打歪了）" % label)
	_c.check(not _joy.is_active, "%s 按下时脚下不长摇杆" % label)
	await _motion(pos + Vector2(0, -JITTER))
	await _release(pos + Vector2(0, -JITTER))
	return _collect(host)

## 反例专用：诱饵本来就不该登记，摇杆长不长不是这一枪要判的事，收尾归零即可。
## 但「送到了没有」照量 —— 否则反例那条「没弹卡」可能只是打歪了。
func _tap_only(host: Control, target: Control) -> String:
	var pos := _center(target)
	await _wait_tips_gone(host)
	await _press(pos)
	var landed := target.has_meta(GameStyle._TAP_DOWN_META)
	await _motion(pos + Vector2(0, -JITTER))
	await _release(pos + Vector2(0, -JITTER))
	var title := _collect(host)
	await _reset_joy()
	_c.check(landed, "反例落点：这一枪真送到了诱饵 %s 身上（否则「没弹卡」不算判定）" % target.name)
	return title

func _swipe_at(host: Control, target: Control, dy: float) -> String:
	var pos := _center(target)
	await _wait_tips_gone(host)
	await _press(pos)
	await _motion(pos - Vector2(0, dy * 0.5))
	await _motion(pos - Vector2(0, dy))
	await _release(pos - Vector2(0, dy))
	var title := _collect(host)
	await _reset_joy()
	return title

func _collect(host: Control) -> String:
	var title := ""
	var tip := DetailTip.live(host)
	if tip != null:
		title = String(tip.payload.get("title", ""))	# 收起后节点会被 free，先取成字符串
		# 徽记与槽位都钉在左上角，卡要是只会往右下方摆，真机上就探出屏外了
		var vp := host.get_viewport().get_visible_rect()
		var card := tip.card_rect()
		_c.check(Rect2(vp.position, vp.size).encloses(card),
			"详情卡整块落在视口内（卡 %s / 视口 %s）" % [str(card), str(vp.size)])
	DetailTip.close_all(host)
	return title

## 淡出期间那块全屏暗底还在树里，会把下一枪测成「暗底上能不能点」这种假问题
func _wait_tips_gone(host: Control) -> void:
	DetailTip.close_all(host)
	for _i in range(40):
		var any := false
		for ch in host.get_children():
			if ch is DetailTip:
				any = true
		if not any:
			return
		await get_tree().process_frame
	push_warning("详解卡 40 帧还没收干净，后续落点不可信")

## 落点换算：get_global_rect() 给的是画布（设计）坐标，push_input 要的是窗口坐标。
## 720×540 这类非 1:1 的档位下 expand 会把画布拉到 960×720（scale 0.75），
## 直接把画布坐标推回去会被再放大一次 —— 实测点徽记 (52.5,78) 落在 (70,104) 打中法器槽，
## 判据红成一片而游戏其实没问题。960 / 1204 档 scale=1 恒等，所以只有 4:3 会露出来。
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

func _release_touch(pos: Vector2) -> void:
	var p := _to_input(pos)
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.pressed = false
	e.position = p
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

## 判据自己得拦得住东西：把修复前的形状原样造一颗摆进同一排打同一枪，必须报出「点了没反应」。
## 同时留一颗正例，证明这一枪确实送到了那颗诱饵上 —— 否则「没弹卡」可能只是谁都没收到。
func _selftest() -> void:
	_c.check(GameStyle.TAP_SLACK > JITTER and GameStyle.TAP_SLACK < SWIPE,
		"容差 %.0f 夹在「手指微动 %.0f」与「有意划动 %.0f」之间" % [GameStyle.TAP_SLACK, JITTER, SWIPE])
	if _hud == null or _joy == null:
		return
	var box := _hud.get("_synergy_box") as HBoxContainer
	var bar := _hud.get("weapons_bar") as HBoxContainer
	_c.check(box != null and bar != null, "反例现场：徽记那一排与法器槽那一排都在")
	if box == null or bar == null:
		return

	# 反例①：修复前的徽记接线 —— 只认左键松开，且回调引用「尚未赋值的局部变量」
	var old_chip: Label
	var old_cb := func() -> void:
		DetailTip.show_over(_hud, old_chip, {"title": "反例① 旧接线"})
	old_chip = Label.new()
	old_chip.mouse_filter = Control.MOUSE_FILTER_STOP
	old_chip.text = " 反例① "
	old_chip.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
			old_cb.call()
	)
	box.add_child(old_chip)
	await _settle(2)
	var got_old := await _tap_only(_hud, old_chip)
	_c.check(got_old == "",
		"反例① 旧接线同一枪弹不出卡（实得「%s」）—— 尺子抓得住按值捕获 null 那个根因" % got_old)

	# 正例：修复后的接线（锚点由工厂回送）在同一类坐标上必须弹得出来，
	# 这一条才让上面那个「没弹」成为判定而不是「事件没人收到」
	var new_chip: Label = SynergyUI.create_chip("talisman", 11, func(a: Control) -> void:
		DetailTip.show_over(_hud, a, {"title": "正例 新接线"})
	)
	box.add_child(new_chip)
	await _settle(2)
	var got_new := await _tap_only(_hud, new_chip)
	_c.check(got_new == "正例 新接线",
		"正例 新接线在同一类坐标上弹得出来（实得「%s」）—— 反例① 的没弹不是事件没送到" % got_new)

	# 反例②：修复前的法器槽 —— 整格 IGNORE、没接任何输入
	var old_slot := PanelContainer.new()
	old_slot.custom_minimum_size = Vector2(36, 36)
	old_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(old_slot)
	await _settle(2)
	var got_slot := await _tap_only(_hud, old_slot)
	_c.check(got_slot == "",
		"反例② 全 IGNORE 的槽同一枪弹不出卡（实得「%s」）—— 尺子抓得住整排零热区" % got_slot)
	old_slot.free()

	# 反例③：接了热区但没登记 ui_press_hold ⇒ 摇杆必须长出来（拦住「忘了登记」这一步）
	var loose_slot := PanelContainer.new()
	loose_slot.custom_minimum_size = Vector2(36, 36)
	bar.add_child(loose_slot)
	GameStyle.hotzone(loose_slot)
	GameStyle.tap(loose_slot, func() -> void:
		DetailTip.show_over(_hud, loose_slot, {"title": "反例③ 没登记"})
	)
	await _settle(2)
	var lp := _center(loose_slot)
	await _wait_tips_gone(_hud)
	await _press(lp)
	_c.check(_joy.is_active, "反例③ 没登记 ui_press_hold 的热区 ⇒ 按下长出了摇杆 —— 尺子抓得住忘登记")
	await _release(lp)
	await _reset_joy()
	DetailTip.close_all(_hud)
	await _wait_tips_gone(_hud)
	loose_slot.free()
