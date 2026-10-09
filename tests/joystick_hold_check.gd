extends Node

## 摇杆与「长按类 UI 键」冲突判据：按在键上不许长出摇杆，别处照常。
## 运行: godot --headless --path . res://tests/JoystickHoldCheck.tscn
##       godot --headless --path . res://tests/JoystickHoldCheck.tscn -- --selftest
##
## 立条目的现场（用户 2026-10-09）：长按「聚 灵」激活聚灵阵，人却跟着走了。
## 摇杆走全局 _input，同一次按下比按钮自己的 _gui_input 先到 ⇒ 按住按钮的同时
## 按钮底下也立起一根摇杆；手指滚过 deadzone（0.1 × max_radius 64 = 6.4px，拇指一压就有）
## 就发方向，人被带出 InteractionArea ⇒ body_exited 调 stop_charge() ⇒ 长按永远充不满。
##
## 收口口径（用户 2026-10-09 追加："其他按钮你也收口一下"）：
##  ① 按钮类（BaseButton）由摇杆自动入组，不靠每个界面自己登记 ⇒ 本判据要分别验到
##     两条来路：摇杆入树前就存在的（走 _ready 的整树扫）与之后现造的（走 node_added）。
##  ② 非按钮热区（带 gui_input 的 Label / PanelContainer，如羁绊徽记、悟道待加点）仍要
##     自己 add_to_group ⇒ 判据用「登记过的标签」与「没登记的标签」把这条边界钉住。
##  ③ 灰掉（disabled）的按钮不接单 ⇒ 不许抢走这次走位。
##  ④ 让位只让"按下的那一下、落在那颗键的矩形里"：不许把整屏糊成禁区，也不许按过一次就不能动。
##
## 两条取舍：
##  ① 现场自造，不实例化 GameHUD —— GameHUD 要 GameManager 一堆信号才起得来，判据就会
##     绑死在玩法状态上；这里只判「摇杆让不让位」这一件事。HUD 里那两处登记的接线由
##     冒烟/编辑器现场负责（本判据测不到）。
##  ② 事件走 Input.parse_input_event 真打进引擎，不直接调 _start_joystick() —— 直接调
##     只测得到我自己的算术，测不到「同一次按下两边都收到」这个真正的冲突。
##     派发不通时先自证并明说，不许把「没收到事件」当成通过。

const JOY_SCENE := "res://scenes/ui/VirtualJoystick.tscn"
## 现场那颗登记键的摆位：照 GameHUD 聚灵按钮的尺寸（110×44）
const HOLD_RECT := Rect2(700, 60, 110, 44)
## 屏中段空白：这儿什么都没有，按下就该长出摇杆
const FREE_POS := Vector2(420, 300)

var _c := TestCheck.new()
var _joy: DawnJoystick
var _host: Control
## ① 摇杆入树前就存在的一颗按钮 ⇒ 走整树扫那条路
var _pre_btn: Button
## ② 非按钮热区，自己登记了 ⇒ 走 ui_press_hold 那条路
var _hold_key: Label
## ③ 之后现造的按钮，不登记 ⇒ 走 node_added 自动入组那条路
var _auto_btn: Button
## ④ 灰掉的按钮 ⇒ 不许让位
var _disabled_btn: Button
## ⑤ 没登记的非按钮热区 ⇒ 不许让位（边界：只有按钮自动）
var _plain_label: Label

func _ready() -> void:
	if "--selftest" in OS.get_cmdline_user_args():
		await _selftest()
		get_tree().quit(0 if _c.report("JOYSTICK_HOLD_SELFTEST_RESULT") else 1)
		return
	await _run()
	get_tree().quit(0 if _c.report("JOYSTICK_HOLD_RESULT") else 1)

func _run() -> void:
	get_tree().root.size = Vector2i(960, 540)
	await get_tree().process_frame
	_build_stage_before_joy()
	await get_tree().process_frame
	# 摇杆此刻才入树：它的 _ready 要能认出上面这颗已经在场景里的按钮
	_joy = (load(JOY_SCENE) as PackedScene).instantiate() as DawnJoystick
	get_tree().root.add_child(_joy)
	await get_tree().process_frame
	_build_stage_after_joy()
	await get_tree().process_frame
	await get_tree().process_frame

	# 一、纯算术：命中判定含余量，且余量有限（不许把按钮糊成一大片禁区）
	_c.check(DawnJoystick.rect_claims_ui_hold(HOLD_RECT, HOLD_RECT.position + Vector2(55, 22)),
		"正例 按钮正中算命中")
	_c.check(DawnJoystick.rect_claims_ui_hold(HOLD_RECT, HOLD_RECT.position - Vector2(4, 4)),
		"正例 角上外扩 4px（斜切裁掉的视觉）仍算命中")
	_c.check(not DawnJoystick.rect_claims_ui_hold(HOLD_RECT, HOLD_RECT.position - Vector2(DawnJoystick.UI_PRESS_HOLD_PAD + 2.0, 0)),
		"反例 按钮外 %dpx 放行 —— 键边上还得能走位" % int(DawnJoystick.UI_PRESS_HOLD_PAD + 2.0))
	_c.check(not DawnJoystick.rect_claims_ui_hold(HOLD_RECT, FREE_POS),
		"反例 屏中段空白与按钮不相干")

	# 二、派发通路自证：空白处按下必须真能把摇杆叫醒，否则后面的「没叫醒」不算判定
	if not await _dispatch_works():
		print("[SKIP] headless 派发不通，摇杆行为各项不予判定")
		return

	# 三、登记过的非按钮热区：按下不长摇杆，在键上滚动手指也不发方向
	await _reset()
	await _touch_press(0, HOLD_RECT.get_center())
	_c.check(not _joy.is_active, "按在已登记的键上 ⇒ 摇杆不接管（is_active 仍为 false）")
	_c.check(_joy.touch_id == -1, "按在已登记的键上 ⇒ 没占住任何手指（touch_id 仍为 -1）")
	await _touch_drag(0, HOLD_RECT.position + Vector2(90, 30))
	await _touch_drag(0, HOLD_RECT.position + Vector2(20, 10))
	_c.check(_joy.output.length() == 0.0, "手指在键上滚了两下 ⇒ 方向仍为零（人不会被带出阵法）")
	await _touch_release(0, HOLD_RECT.position + Vector2(20, 10))

	# 四、自动收口①：摇杆入树前就存在的按钮（整树扫那条路）—— 不登记也该让位
	await _reset()
	await _touch_press(1, _pre_btn.position + _pre_btn.size * 0.5)
	_c.check(not _joy.is_active, "场景里既有的按钮 ⇒ 摇杆入树时扫到了（不用逐颗登记）")
	await _touch_release(1, _pre_btn.position + _pre_btn.size * 0.5)

	# 五、自动收口②：摇杆入树之后现造的按钮（node_added 那条路）—— 商店卡/详解关闭键都是这一类
	await _reset()
	await _touch_press(2, _auto_btn.position + _auto_btn.size * 0.5)
	_c.check(not _joy.is_active, "运行中新造的按钮 ⇒ node_added 当场接住（没登记也让位）")
	await _touch_release(2, _auto_btn.position + _auto_btn.size * 0.5)

	# 六、灰掉的按钮不接单 ⇒ 也不许抢走这次走位（点它没反应，人就该照常动）
	await _reset()
	await _touch_press(3, _disabled_btn.position + _disabled_btn.size * 0.5)
	_c.check(_joy.is_active, "disabled 按钮按下去 ⇒ 摇杆照常用（灰键不许变成死区）")
	await _touch_release(3, _disabled_btn.position + _disabled_btn.size * 0.5)

	# 七、边界：没登记的非按钮热区不让位（判据有牙齿 —— 拦住的是"登记/按钮"这一步）
	await _reset()
	await _touch_press(4, _plain_label.position + _plain_label.size * 0.5)
	_c.check(_joy.is_active, "未登记的普通控件按下去 ⇒ 摇杆照旧长出来（只有按钮自动让位）")
	await _touch_release(4, _plain_label.position + _plain_label.size * 0.5)

	# 八、键藏起来就该把走位还回去：出范围时整块隐藏，那颗键的位置不许变成死区
	await _reset()
	_host.visible = false
	await get_tree().process_frame
	await _touch_press(5, HOLD_RECT.get_center())
	_c.check(_joy.is_active, "键隐藏后同一位置恢复走位（不许留隐形禁区）")
	await _touch_release(5, HOLD_RECT.get_center())
	_host.visible = true
	await get_tree().process_frame

	# 九、真机常态①：一根手指跑着，另一根手指去按聚灵键 ⇒ 不许打断已经在走的摇杆
	# touch_id 不钉死成具体手指号：桌面跑判据时 emulate_mouse_from_touch 为真，同一次按下
	# 可能先到鼠标分支（占 999）再到手指分支 —— 判的是"这根没被第二根抢走"。
	await _reset()
	await _touch_press(6, FREE_POS)
	var claimed := _joy.touch_id
	_c.check(_joy.is_active and claimed != -1, "先按空白 ⇒ 摇杆占住这根指针（touch_id=%d）" % claimed)
	await _touch_drag(6, FREE_POS + Vector2(40, 0))
	_c.check(_joy.output.length() > 0.0, "拖出 deadzone ⇒ 有方向（实得 %.3f）" % _joy.output.length())
	await _touch_press(7, HOLD_RECT.get_center())
	_c.check(_joy.is_active and _joy.touch_id == claimed, "第二根手指按聚灵键 ⇒ 跑动的那根不被抢走")
	await _touch_drag(6, FREE_POS + Vector2(0, 40))
	_c.check(_joy.output.length() > 0.0, "按住键期间另一指的拖动仍生效（键不吞别人的手指）")
	await _touch_release(7, HOLD_RECT.get_center())
	await _touch_release(6, FREE_POS + Vector2(0, 40))
	_c.check(not _joy.is_active, "两根都抬起 ⇒ 摇杆归零")

	# 十、真机常态②（用户追问"不会导致按下后不可以移动吧"）：先按住键不放，另一指去按空白
	await _reset()
	await _touch_press(8, HOLD_RECT.get_center())
	_c.check(not _joy.is_active and _joy.touch_id == -1, "先按住聚灵键 ⇒ 摇杆空着，等另一根手指")
	await _touch_press(9, FREE_POS)
	var mover := _joy.touch_id
	_c.check(_joy.is_active and mover != -1 and mover != 8,
		"按住键的同时按空白 ⇒ 照样长出摇杆（没被那颗键锁死）")
	await _touch_drag(9, FREE_POS + Vector2(0, 45))
	_c.check(_joy.output.length() > 0.25, "另一指拖动 ⇒ 方向发得出来（实得 %.3f）" % _joy.output.length())
	await _touch_release(8, HOLD_RECT.get_center())
	_c.check(_joy.is_active and _joy.touch_id == mover, "抬起按键那根手指 ⇒ 跑动不被误停")
	await _touch_drag(9, FREE_POS + Vector2(-45, 0))
	_c.check(_joy.output.length() > 0.25, "抬键之后继续跑 ⇒ 方向仍有（实得 %.3f）" % _joy.output.length())
	# 让位只看"按下"那一下：跑动的手指一路滑到键底下也不许停（真机上拇指就是会路过）
	await _touch_drag(9, Vector2(HOLD_RECT.position.x - 250, HOLD_RECT.get_center().y))
	await _touch_drag(9, HOLD_RECT.get_center())
	_c.check(_joy.is_active and _joy.output.length() > 0.25,
		"跑动手指滑到键底下 ⇒ 仍照常走位（让位只判按下那一下，不吞拖动）")
	await _touch_release(9, FREE_POS + Vector2(-45, 0))
	_c.check(not _joy.is_active, "两根都抬起 ⇒ 摇杆归零")

	# 十一、不粘滞：按过键的这一次不许把后面的走位一起带走
	await _reset()
	await _touch_press(10, HOLD_RECT.get_center())
	await _touch_release(10, HOLD_RECT.get_center())
	await _touch_press(11, FREE_POS)
	_c.check(_joy.is_active, "在键上按一下就抬起 ⇒ 下一次按空白照常走位")
	await _touch_release(11, FREE_POS)

	# 十二、整次手势归那颗键（取舍要钉住）：按住键后把手指滑出键外，不许"人突然自己跑"
	await _reset()
	await _touch_press(12, HOLD_RECT.get_center())
	await _touch_drag(12, FREE_POS)
	await _touch_drag(12, Vector2(200, 480))
	_c.check(not _joy.is_active and _joy.output.length() == 0.0,
		"按住键后滑出键外 ⇒ 这根手指仍归那颗键（不会半路开始走位）")
	await _touch_release(12, Vector2(200, 480))

	# 十三、禁区只有那颗键那么大：键外 12px（余量 8 之外）必须还能走位
	await _reset()
	await _touch_press(13, Vector2(HOLD_RECT.end.x + 12.0, HOLD_RECT.position.y + 22.0))
	_c.check(_joy.is_active, "紧贴键右侧 12px 按下 ⇒ 仍是走位区（不许把键糊成大禁区）")
	await _touch_release(13, Vector2(HOLD_RECT.end.x + 12.0, HOLD_RECT.position.y + 22.0))

	# 十四、桌面鼠标路径（编辑器里试玩走的是这条）：同样不许在键上长摇杆
	await _reset()
	await _mouse_press(HOLD_RECT.get_center())
	_c.check(not _joy.is_active, "鼠标按在聚灵键上 ⇒ 摇杆不接管")
	await _mouse_release(HOLD_RECT.get_center())
	await _reset()
	await _mouse_press(FREE_POS)
	_c.check(_joy.is_active, "鼠标按在空白处 ⇒ 摇杆照常")
	await _mouse_release(FREE_POS)

	# 十五、真件：详解卡（非按钮的 PanelContainer 卡体）卡体让位、整屏暗底不让位。
	# 用真 DetailTip 而不是自造替身，顺便把这件控件拉进编译 —— 它今天的改动就是这两条边界。
	var tip := DetailTip.show_over(_host, _hold_key, {
		"title": "判据详解", "chip": "现场", "chip_color": GameStyle.YELLOW,
		"rows": [["当前", "1", GameStyle.PAPER]],
		"body": "卡体不算禁区外的例外；暗底仍要把走位留下。",
		"notes": ["这条判据盯的是「卡体让位、遮罩不让位」这条边界。"],
		"foot": "无",
	})
	_c.check(tip != null, "详解卡开得出来（DetailTip 编译通过）")
	await get_tree().create_timer(0.45).timeout
	var card_rect := tip._card.get_global_rect()
	await _reset()
	await _touch_press(20, card_rect.get_center())
	_c.check(not _joy.is_active, "详解卡开着 ⇒ 点在卡体上不长摇杆（读卡时人不挪窝）")
	await _touch_release(20, card_rect.get_center())
	await _reset()
	var far := Vector2(24, 24)
	if card_rect.has_point(far):
		far = Vector2(936, 516)
	await _touch_press(21, far)
	_c.check(_joy.is_active, "卡的整屏暗底上按下 ⇒ 照常走位（遮罩不许变成全屏禁区）")
	await _touch_release(21, far)
	DetailTip.close_all(_host)
	await get_tree().create_timer(0.6).timeout
	_c.check(DetailTip.live(_host) == null, "详解卡收干净 ⇒ 关掉后那个位置不再拦走位")

	# 十六、更新对话框：能构造（编译通过），且它没显示时那颗卡体不许变成禁区
	var dlg: Control = (load("res://scripts/ui/UpdateDialog.gd") as GDScript).new()
	get_tree().root.add_child(dlg)
	await get_tree().process_frame
	await _reset()
	var far_of_card := Vector2(420, 500)
	var far_of_card := Vector2(420, 300)
	_c.check(absf(far_of_card.x - 480.0) < 230.0 and absf(far_of_card.y - 270.0) < 190.0,
		"前提：这个点确实落在更新对话框那颗 460×380 面板矩形里")
	await _touch_press(22, far_of_card)
	_c.check(_joy.is_active, "更新对话框隐藏时 ⇒ 它的卡体不算禁区（该点正落在面板矩形里）")
	await _touch_release(22, far_of_card)
	dlg.queue_free()
	await get_tree().process_frame

## 摇杆入树之前：只有这颗"场景里既有的按钮"（它自己 _ready 时该扫到）
func _build_stage_before_joy() -> void:
	_pre_btn = _make_btn(Rect2(120, 60, 110, 44), "场已有")
	get_tree().root.add_child(_pre_btn)

## 摇杆入树之后：登记过的标签键（连同它的宿主）+ 现造按钮 + 灰按钮 + 没登记的标签
func _build_stage_after_joy() -> void:
	_host = Control.new()
	_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().root.add_child(_host)

	_hold_key = Label.new()
	_hold_key.text = "聚 灵"
	_hold_key.mouse_filter = Control.MOUSE_FILTER_STOP
	_hold_key.position = HOLD_RECT.position
	_hold_key.size = HOLD_RECT.size
	_hold_key.add_to_group(DawnJoystick.UI_PRESS_HOLD_GROUP)
	_host.add_child(_hold_key)

	_auto_btn = _make_btn(Rect2(700, 420, 110, 44), "现造键")
	_host.add_child(_auto_btn)

	_disabled_btn = _make_btn(Rect2(120, 420, 110, 44), "灰键")
	_disabled_btn.disabled = true
	_host.add_child(_disabled_btn)

	_plain_label = Label.new()
	_plain_label.text = "没登记"
	_plain_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_plain_label.position = Vector2(420, 60)
	_plain_label.size = Vector2(110, 44)
	_host.add_child(_plain_label)

func _make_btn(rect: Rect2, label: String) -> Button:
	var b := Button.new()
	b.text = label
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.focus_mode = Control.FOCUS_NONE
	b.position = rect.position
	b.size = rect.size
	return b

## 派发通路自证：空白处一次按下能不能真的把摇杆叫醒
func _dispatch_works() -> bool:
	await _reset()
	await _mouse_press(FREE_POS)
	var ok := _joy.is_active
	await _mouse_release(FREE_POS)
	_c.check(ok, "前提：headless 能把 parse_input_event 派发进 _input")
	return ok

## 每段开头把摇杆恢复到空闲态；归零本身只在第九/十段末尾判一次
func _reset() -> void:
	if _joy != null and _joy.is_active:
		_joy._stop_joystick()
	await get_tree().process_frame

func _touch_press(idx: int, pos: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.pressed = true
	e.position = pos
	Input.parse_input_event(e)
	await get_tree().process_frame

func _touch_drag(idx: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = pos
	Input.parse_input_event(e)
	await get_tree().process_frame

func _touch_release(idx: int, pos: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.pressed = false
	e.position = pos
	Input.parse_input_event(e)
	await get_tree().process_frame

func _mouse_press(pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = pos
	Input.parse_input_event(e)
	await get_tree().process_frame

func _mouse_release(pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.position = pos
	Input.parse_input_event(e)
	await get_tree().process_frame

## 判据自己的牙齿：命中判定反着喂必须判 false
func _selftest() -> void:
	_c.check(not DawnJoystick.rect_claims_ui_hold(HOLD_RECT, Vector2(0, 0)),
		"反例 屏外左上角不算命中")
	_c.check(not DawnJoystick.rect_claims_ui_hold(HOLD_RECT, Vector2(959, 539)),
		"反例 屏右下角不算命中")
	_c.check(not DawnJoystick.rect_claims_ui_hold(HOLD_RECT, Vector2(700 + 110 + 9, 60 + 22)),
		"反例 键右侧超出余量 9px 不算命中")
	_c.check(DawnJoystick.rect_claims_ui_hold(HOLD_RECT, Vector2(700 + 110 + 3, 60 + 22)),
		"正例 键右侧余量内 3px 算命中")
