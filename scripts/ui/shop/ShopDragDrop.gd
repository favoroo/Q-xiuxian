class_name ShopDragDrop
extends Node

## 金币阁陈列行「按住拎起 → 拖到目标格放下」的换装手势（2026-10-11 用户：背包里的装备
## 和已佩戴的装备要能拖动换位，拖到背包＝卸下、拖到上阵格＝佩戴）。
## 陈列行的格子（上阵格/背包格/背包空位/「背包 n/9」分隔签）在构建时经 register_slot 登记，
## 手势状态机归这一个节点管；数据操作回流 GameManager（equip_stash_into_slot / unequip_to_stash
## / swap_equipped_slots / reorder_stash），刷新走 shop.refresh(false)
## —— 与点按详情卡里的「装备/卸下」按钮同一条链路。
##
## 手势口径（与 GameStyle.tap 同一把 TAP_SLACK 尺，两者互不干扰）：
##  · 按住不动 HOLD_DELAY 秒 ⇒ 拎起：图标抬到手指上方跟手、落点格整块点亮 + 动作签报名字；
##  · 按住后先划出去（> TAP_SLACK）⇒ 那是横滑列表，拎起作废，OwnedScroll 照常滚
##    （待发阶段不截事件，GameStyle.tap 的「划动不误选」账目照记）；
##  · 拎起之后的移动/抬手由 _input 截走（set_input_as_handled）：拖着走时整排不许跟着滑，
##    松手也不许被 tap 兑现成点选；空手松开（没落在任何落点上）＝原样飞回。
##
## 为什么不用 Godot 内建拖放（_get_drag_data/_can_drop_data/_drop_data）：
##  · 内建 DnD 是「按下即拖」，与这一排的横滑滚动抢同一段手势（见 GameStyle.swipeable
##    头注：按下那一拍已被 OwnedScroll latch），真机上一划就滚走，拎不住；
##  · 内建 DnD 给不出「按住多久才算拖」的口径，触屏 + 滚动容器组合下真机行为也不稳。
##
## 放下的口径（2026-10-11 用户补口径：拖到已佩戴的武器上＝替换，上阵格之间＝换位）：
##  · 背包件 → 上阵空格：直接装备（上阵区固定画满上限格数，空格也是落点）；
##  · 背包件 → 已佩戴的武器格：替换那一格（换下的一件回背包被腾出的原位，
##    见 WeaponInventory.equip_stash_into_slot）；
##  · 上阵件 → 背包里某一件＝互换（那件顶替这一格上阵，这一件落到它腾出的那一格背包位）：
##    与上一条是同一个操作的两个方向，走同一条数据路径。
##    （2026-10-11 用户：「拖过去之后它直接就放到背包里面去了，我要替换的那件没换上」——
##     旧口径把这一枪当成卸下，背包满时更是当场拒绝，换不了；现在认到具体一件就是互换。）
##  · 上阵件 → 背包空位/「背包」分隔签＝卸入背包（这两处只指区域不指件，背包满由
##    unequip_to_stash 播报）；
##  · 上阵件 → 上阵另一格＝互换位置（同池才换：悬浮武器换悬浮武器、灵宝换灵宝，
##    见 WeaponInventory.swap_equipped_slots；混池不挪 —— summary 固定
##    「悬浮武器在前、灵宝在后」，跨池次序没有可落的数据）；上阵空格不接上阵件；
##  · 背包件 → 背包区＝背包内排序（空位/分隔签＝挪到队尾）。
##
## 落点认图标，不认手指（2026-10-11 用户：「按手指位置判定的话我会遮挡住要替换的那个图标，
## 应该用图标位置判定」）：幽灵画在手指上方 AIM_LIFT，判定用的是它**画出来的那一圈**的中心
## 压在哪一格 —— 眼睛盯着图标走，图标压到哪一格就是哪一格，格子被不被手指挡住都无所谓。
## 同一条不变量还有一处好处：拎起来那一下图标在整排上方，判定落在排外＝没有落点，
## 不许把"手指底下那一格"当成落点亮起来骗人。
## 幽灵比格子大、落下时正好盖住被指那一格 ⇒ 光有高亮说不出"这是哪一件"，所以图标上方再挂一枚
## 动作签（装备/替换/卸下/换位 + 那一格的名字）：手指挡得住格子，挡不住图标上沿那一行字。

## 按住多久算拎起：Android 拖拽的长按阀，比系统长按（0.4s）短一截，比误触划动停顿长
const HOLD_DELAY := 0.28
## 拖拽看门狗（秒）：Android 多指触屏下，模拟鼠标的 Release 只在最后一根手指抬起时才发；
## 若拖拽途中别的手指先抬或系统插入手势中断，_drag 会永久卡死并在 _input 里持续
## set_input_as_handled 吞噬全屏输入（商店点哪儿都没反应）。超过此时长无运动即就地取消。
const DRAG_WATCHDOG_SEC := 8.0
## 图标中心离手指的竖直距离：整颗图标抬到手指上方，才谈得上"按图标判定"（见头注）
const AIM_LIFT := 44.0
## 落点容差：图标中心落在格子外扩 AIM_SLACK 的范围内就算这一格。陈列行格子之间只有 10 单位
## 的缝，不给容差就是"两条边界之间没有落点"，扫过去一路闪空白
const AIM_SLACK := 10.0
## 幽灵图标边长的夹取范围（源格 36~44 见方，拎起来放大一号才像「拿在手里」）
const GHOST_MIN := 40.0
const GHOST_MAX := 72.0
## 动作签的五种说法（与 _apply 的落点语义一一对应，不许许诺做不到的事）
const VERB_EQUIP := "装备"
const VERB_SWAP := "替换"
const VERB_UNEQUIP := "卸下"
const VERB_MOVE := "移动"
const VERB_EXCHANGE := "换位"

var _shop: WaveShop
## 登记表：[{node: Control, src: Dictionary}]；整行每次点按/操作后重建，
## 旧格子 queue_free 后由 is_instance_valid + is_queued_for_deletion 惰性剔除
var _slots: Array = []
## 待发：按住未满时限 {_press: Control, src, down: Vector2, at: Vector2, gen: int}
## down 是判定"划出去了没"的锚（不许改），at 是最新落点（拎起那一下按它摆幽灵）
var _press: Dictionary = {}
var _gen := 0
## 进行中：{src: Dictionary}；空字典＝没拎着
var _drag: Dictionary = {}
## 拖拽开始的真实时刻（Time.get_ticks_msec，不受暂停/time_scale 影响）：看门狗用
var _drag_start_ms: int = 0
var _ghost: Control = null
## 动作签：贴在幽灵上沿之上，跟着图标走（被手指挡住的是格子，不是这一行字）
var _cap: Label = null
## 动作签此刻的文字（只在换格子时重算，见 _drag_move）
var _cap_txt := ""
## 拎起时的原件：松手飞回 / 还原压暗用（重建后可能已失效，用时先 is_instance_valid）
var _src_node: Control = null
var _hover_node: Control = null
var _hover_sb: StyleBoxFlat = null
var _hover_border := Color()
var _hover_bg := Color()
var _hover_w := 0
var _hover_mod := Color()

func _init(shop: WaveShop) -> void:
	_shop = shop

# ---------------- 登记 ----------------

## 陈列行的每一格在构建时登记：上阵/背包格是「可拎可落」，上阵空格、背包空位与分隔签只作落点。
## src 口径与 shop.selected 同源：{pool: "equipped"/"stash", index: int}；
## 背包空位/分隔签这类「只指区域不指件」的落点用 index = -1（kind = "end"＝挪到队尾）；
## 上阵空格用 kind = "empty" 标记（index 是格位号）。
func register_slot(node: Control, src: Dictionary) -> void:
	if node == null:
		return
	node.set_meta("drag_src", src)
	node.gui_input.connect(_on_slot_input.bind(node, src))
	_slots.append({"node": node, "src": src})

## 判据读数：现在是否拎着一件
func is_dragging() -> bool:
	return not _drag.is_empty()

## 判据读数：幽灵图标画出来的矩形（没拎着返回空矩形）
func ghost_rect() -> Rect2:
	if _ghost == null or not is_instance_valid(_ghost):
		return Rect2()
	return _ghost.get_global_rect()

## 判据读数：幽灵画出来之后真正的判定落点（= 画出来的那一圈的中心，夹取过 viewport 才算）
func aim_point() -> Vector2:
	var r := ghost_rect()
	return r.get_center() if r.size.x > 0.0 else Vector2.INF

## 判据读数：当前点亮的落点登记（没有落点返回空字典）
func hover_src() -> Dictionary:
	if _hover_node == null or not is_instance_valid(_hover_node):
		return {}
	return _hover_node.get_meta("drag_src", {})

## 判据读数：动作签此刻的文字
func cap_text() -> String:
	if _cap == null or not is_instance_valid(_cap) or not _cap.visible:
		return ""
	return _cap.text

# ---------------- 按下 → 待发 → 拎起 ----------------

func _on_slot_input(ev: InputEvent, node: Control, src: Dictionary) -> void:
	var mb := ev as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		if _press.is_empty() and not is_dragging():
			_press_start(node, src, mb.global_position)
	elif not _press.is_empty() and _press.get("node") == node:
		_press_cancel()

func _press_start(node: Control, src: Dictionary, down: Vector2) -> void:
	_gen += 1
	_press = {"node": node, "src": src, "down": down, "at": down, "gen": _gen}
	var g := _gen
	get_tree().create_timer(HOLD_DELAY).timeout.connect(func() -> void:
		if not _press.is_empty() and int(_press.get("gen", -1)) == g:
			_pickup()
	)

func _press_cancel() -> void:
	_press = {}

func _input(event: InputEvent) -> void:
	# 商店已关（出战的瞬间等）：把没结的手势就地结清，不许再吞玩家输入
	if not _shop.visible:
		if not _drag.is_empty() or not _press.is_empty():
			_cancel_all()
		return
	# Android 返回键：手势进行中按下返回，就地取消（否则 _drag 卡死后连返回都吞不到）
	if event.is_action_pressed("ui_cancel") and (not _drag.is_empty() or not _press.is_empty()):
		_cancel_all()
		return
	# 拖拽看门狗：超过 DRAG_WATCHDOG_SEC 无运动即取消（Android 多指抬起事件丢失的兜底）
	if not _drag.is_empty() and (Time.get_ticks_msec() - _drag_start_ms) > int(DRAG_WATCHDOG_SEC * 1000.0):
		_cancel_all()
		return
	var mm := event as InputEventMouseMotion
	if not _drag.is_empty():
		var mb := event as InputEventMouseButton
		if mm != null:
			get_viewport().set_input_as_handled()
			_drag_move(mm.global_position)
		elif mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
			get_viewport().set_input_as_handled()
			if not mb.pressed:
				_drop()
		elif event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed:
			# 原生触屏抬起：多指场景下模拟鼠标不发 Release，认到任何触屏抬起就松手（宁可早放不可锁死）
			get_viewport().set_input_as_handled()
			_drop()
		return
	if _press.is_empty():
		return
	# 待发阶段不截事件：划出去就是横滑，拎起作废（滚动照旧、tap 的账照记）
	if mm != null:
		if (_press.get("down", Vector2.ZERO) as Vector2).distance_to(mm.global_position) > GameStyle.TAP_SLACK:
			_press_cancel()
		else:
			# 原地微动也要记账：拎起那一下幽灵认最新落点，不认 0.28 秒前的那一枪
			_press["at"] = mm.global_position
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_press_cancel()

func _pickup() -> void:
	var src: Dictionary = _press.get("src", {})
	var n = _press.get("node")
	var at: Vector2 = _press.get("at", _press.get("down", Vector2.ZERO))
	_press_cancel()
	if is_dragging() or src.is_empty():
		return
	var item: Dictionary = _item_of(src)
	if item.is_empty():
		return
	_src_node = null
	var tile := GHOST_MIN
	if n != null and is_instance_valid(n):
		var node := n as Control
		tile = maxf(node.size.x, GHOST_MIN * 0.75)
		_src_node = node
	# 拎起时收掉还开着的详情卡（收卡会触发整行重建，幽灵挂在本商店上，不受影响）
	DetailTip.close_all(_shop)
	_drag = {"src": src}
	_drag_start_ms = Time.get_ticks_msec()
	_cap_txt = ""
	_build_ghost(item, tile)
	if _src_node != null and is_instance_valid(_src_node):
		_src_node.modulate = Color(1.0, 1.0, 1.0, 0.45)
	AudioManager.play_sfx("ui_click", 0.9)
	_drag_move(at)

func _build_ghost(item: Dictionary, tile: float) -> void:
	var gsize := clampf(tile * 1.18, GHOST_MIN, GHOST_MAX)
	var ghost := PanelContainer.new()
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.top_level = true
	var sb := GameStyle.outlined_panel(GameStyle.NAVY, GameStyle.PAPER, 2, 0.0)
	sb.content_margin_left = 4.0
	sb.content_margin_top = 4.0
	sb.content_margin_right = 4.0
	sb.content_margin_bottom = 4.0
	ghost.add_theme_stylebox_override("panel", sb)
	var icon_path: String = item.get("icon", "")
	if icon_path.is_empty():
		icon_path = WeaponData.get_def(item.get("id", "")).get("icon", "")
	var icon := GameStyle.icon_texture_rect(icon_path)
	ghost.add_child(icon)
	GameStyle.star_label(ghost, int(item.get("star", 1)), 12)
	GameStyle.apply_star4_trim(ghost, int(item.get("star", 1)))
	_shop.add_child(ghost)
	ghost.custom_minimum_size = Vector2(gsize, gsize)
	ghost.size = Vector2(gsize, gsize)
	# 动作签：图标上沿之上那一行字，报「松手会做什么 · 这一格是哪一件」。
	# 幽灵比格子大、正好盖住被指那一格 ⇒ 只有描边认不出"这是哪一件"（见头注）
	var cap := GameStyle.chip_label("", GameStyle.JADE, GameStyle.INK_TEXT, 12)
	cap.top_level = true
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.visible = false
	_shop.add_child(cap)
	_cap = cap
	# 拎起的一下小弹跳：让「拎起来了」看得见（不引渐变不引辉光，只动尺寸）
	ghost.pivot_offset = ghost.size * 0.5
	ghost.scale = Vector2(0.85, 0.85)
	var tw := ghost.create_tween()
	tw.tween_property(ghost, "scale", Vector2.ONE, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_ghost = ghost

# ---------------- 拖动 / 落点 ----------------

## 幽灵跟手：整颗图标抬到手指上方 AIM_LIFT，横向居中、纵向以图标中心为判定落点。
## 夹进 viewport 之后再取中心来判定 —— 判的是"画出来的那一圈"，被夹走多少就差多少。
func _drag_move(p: Vector2) -> void:
	if _ghost == null or not is_instance_valid(_ghost):
		return
	# 看门狗续命：手指还在动就重置计时，只有真静止超时才会被取消
	_drag_start_ms = Time.get_ticks_msec()
	var vr := get_viewport().get_visible_rect()
	var gs := _ghost.size
	var pos := p - Vector2(gs.x * 0.5, AIM_LIFT + gs.y * 0.5)
	pos = pos.clamp(vr.position + Vector2(2.0, 2.0), vr.end - gs - Vector2(2.0, 2.0))
	_ghost.global_position = pos
	var t := _target_at(_ghost.get_global_rect().get_center())
	# 动作文字只在换格子时重算（_action_text 要现读 summary，逐帧 motion 重算白给一次数组重建）
	if _set_hover(t):
		_cap_txt = _action_text(t)
	_place_cap()

## 图标画出来的中心压着哪一格（不是手指按在哪：手指底下那一格整个被拇指盖着，
## 量出来玩家也看不见，等于摸黑瞄准 —— 2026-10-11 用户口径）。
## 源格自己不算：拖回原位＝空手松开＝飞回，不许高亮骗人。
## 外扩 AIM_SLACK 后可能同时够着左右两格，取中心最近的那一格，扫过去一路只闪一下。
func _target_at(aim: Vector2) -> Dictionary:
	var src: Dictionary = _drag.get("src", {})
	# 整行每次点按/操作后重建：先把已释放的登记惰性压掉（freed instance 不能赋给类型化变量，
	# 必须先 is_instance_valid 再转 Control）
	_slots = _slots.filter(func(t) -> bool:
		var n = t.get("node")
		return n != null and is_instance_valid(n) and not (n as Control).is_queued_for_deletion()
	)
	var best: Dictionary = {}
	var best_d := INF
	for t in _slots:
		var node: Control = t.get("node")
		if not node.is_visible_in_tree():
			continue
		var ts: Dictionary = t.get("src", {})
		if not _droppable(src, ts):
			continue
		if String(ts.get("pool", "")) == String(src.get("pool", "")) \
				and int(ts.get("index", -9)) == int(src.get("index", -9)):
			continue
		var r: Rect2 = node.get_global_rect()
		if not r.grow(AIM_SLACK).has_point(aim):
			continue
		var d := r.get_center().distance_squared_to(aim)
		if d < best_d:
			best_d = d
			best = {"node": node, "src": ts}
	return best

## 落点合法性（与 _apply 同一条规则，高亮与动作签都不许许诺做不到的事）
func _droppable(src: Dictionary, ts: Dictionary) -> bool:
	var sp := String(src.get("pool", ""))
	var tp := String(ts.get("pool", ""))
	if sp == "stash":
		return tp == "equipped" or tp == "stash"
	if sp == "equipped":
		# 背包区两种落点都接，兑现不同：认到具体一件＝互换，只指区域（空位/分隔签）＝卸下
		if tp == "stash":
			return true
		# 上阵 → 上阵＝互换位置；上阵空格不是一件武器，不接（松手原样飞回）
		return tp == "equipped" and String(ts.get("kind", "")) != "empty"
	return false

## 落点整块点亮：描边翻纸白 + 底翻亮 + 微过曝。旧写法只改描边色，2 单位的线在满排黑底
## 小格子里几乎看不出来，而它正是"我瞄到了"的唯一凭据。返回落点有没有换格子。
func _set_hover(t: Dictionary) -> bool:
	var node: Control = t.get("node")
	if node == _hover_node:
		return false
	_clear_hover()
	if node == null or not is_instance_valid(node):
		return true
	_hover_node = node
	_hover_mod = node.modulate
	# 提亮走色相不提分量：>1.0 的分量会被 WorldEnvironment glow 当起辉源（HDR 根视口含 UI），
	# 「落点微过曝」在真机上等于让整块格子在 glow pass 里跳一下。
	node.modulate = Color(1.0, 0.98, 0.93, 1.0)
	var sb := node.get_theme_stylebox("panel")
	if sb is StyleBoxFlat:
		_hover_sb = sb
		_hover_border = sb.border_color
		_hover_bg = sb.bg_color
		_hover_w = sb.get_border_width(SIDE_LEFT)
		sb.border_color = GameStyle.PAPER
		sb.bg_color = GameStyle.LINE
		sb.set_border_width_all(3)
	return true

func _clear_hover() -> void:
	if _hover_node != null and is_instance_valid(_hover_node):
		_hover_node.modulate = _hover_mod
	if _hover_sb != null:
		_hover_sb.border_color = _hover_border
		_hover_sb.bg_color = _hover_bg
		_hover_sb.set_border_width_all(_hover_w)
	_hover_sb = null
	_hover_node = null

## 动作签跟着图标走（手指挡得住格子，挡不住这一行字）：文字由 _drag_move 在换格子时算好，
## 这里只管摆位与显隐。两头夹进屏内：最左/最右那一格的动作签不许画到屏外。
func _place_cap() -> void:
	if _cap == null or not is_instance_valid(_cap) or _ghost == null or not is_instance_valid(_ghost):
		return
	if _cap_txt.is_empty():
		_cap.visible = false
		return
	if _cap.text != _cap_txt:
		_cap.text = _cap_txt
		_cap.custom_minimum_size = Vector2(
				GameStyle.chip_pin_w(_cap_txt, GameStyle.body_font(), 12), 0.0)
		_cap.reset_size()
	_cap.visible = true
	var gr := _ghost.get_global_rect()
	var vr := get_viewport().get_visible_rect()
	var cs := _cap.size
	var cx := clampf(gr.get_center().x - cs.x * 0.5, vr.position.x + 2.0,
			maxf(vr.position.x + 2.0, vr.end.x - cs.x - 2.0))
	var cy := gr.position.y - cs.y - 3.0
	if cy < vr.position.y + 2.0:
		cy = gr.end.y + 3.0
	_cap.global_position = Vector2(cx, cy)

## 落点 → 一句话读数（与 _apply 同一条规则：签上许诺的必须做得出来）
func _action_text(t: Dictionary) -> String:
	if t.is_empty():
		return ""
	var sp := String(_drag.get("src", {}).get("pool", ""))
	var ts: Dictionary = t.get("src", {})
	var tp := String(ts.get("pool", ""))
	var kind := String(ts.get("kind", ""))
	var tail := _slot_name(ts, kind)
	if tp == "equipped":
		if kind == "empty":
			return VERB_EQUIP
		return (VERB_SWAP if sp == "stash" else VERB_EXCHANGE) + tail
	if tp == "stash":
		if kind == "end":
			return VERB_UNEQUIP if sp == "equipped" else VERB_MOVE
		return (VERB_SWAP if sp == "equipped" else VERB_MOVE) + tail
	return ""

## 那一格此刻站着谁：「·弹弓」；上阵空格与背包空位/分隔签只指区域，返回空串（签上只印动作）
func _slot_name(ts: Dictionary, kind: String) -> String:
	if kind == "empty" or kind == "end" or int(ts.get("index", -1)) < 0:
		return ""
	var item: Dictionary = _item_of(ts)
	var nm := String(item.get("name", ""))
	if nm.is_empty():
		nm = String(WeaponData.get_def(String(item.get("id", ""))).get("name", ""))
	return "·%s" % nm if not nm.is_empty() else ""

# ---------------- 放下 ----------------

func _drop() -> void:
	var src: Dictionary = _drag.get("src", {})
	var tgt: Dictionary = {}
	if _hover_node != null and is_instance_valid(_hover_node):
		tgt = _hover_node.get_meta("drag_src", {})
	var ghost := _ghost
	var cap := _cap
	_ghost = null
	_cap = null
	_cap_txt = ""
	_clear_hover()
	_drag = {}
	var ok := false
	if not tgt.is_empty() and not src.is_empty():
		ok = _apply(src, tgt)
	if ok:
		_shop.selected = {}
		_shop.refresh(false)
		_restore_src()
		_free_part(ghost)
		_free_part(cap)
	else:
		_snap_back(ghost, cap)

## 落点语义 → 数据操作（合法性已由 _droppable 把过关，这里只管执行）
func _apply(src: Dictionary, tgt: Dictionary) -> bool:
	var sp := String(src.get("pool", ""))
	var tp := String(tgt.get("pool", ""))
	if sp == "stash" and tp == "equipped":
		return GameManager.equip_stash_into_slot(int(src.get("index", -1)), int(tgt.get("index", -1)))
	if sp == "stash" and tp == "stash":
		if String(tgt.get("kind", "")) == "end":
			return GameManager.reorder_stash(int(src.get("index", -1)), GameManager.stash.size() - 1)
		return GameManager.reorder_stash(int(src.get("index", -1)), int(tgt.get("index", -1)))
	if sp == "equipped" and tp == "stash":
		# 拖到背包里的某一件上＝互换（2026-10-11 用户：拖过去直接丢背包里、要换的那件没换上）：
		# 那件顶替这一格上阵，这一件落到它腾出的那一格背包位。背包满也换得动（件数不变）。
		var si := int(tgt.get("index", -1))
		if si >= 0:
			return GameManager.equip_stash_into_slot(si, int(src.get("index", -1)))
		# 空位/「背包」签只指区域不指件：这一枪才是卸下
		return GameManager.unequip_to_stash(int(src.get("index", -1)))
	if sp == "equipped" and tp == "equipped":
		return GameManager.swap_equipped_slots(int(src.get("index", -1)), int(tgt.get("index", -1)))
	return false

## 空手松开 / 操作失败：幽灵飞回原格（原格还在的话），原格的压暗还原，动作签就地淡掉
func _snap_back(ghost: Control, cap: Control) -> void:
	_restore_src()
	if cap != null and is_instance_valid(cap):
		var ctw := cap.create_tween()
		ctw.tween_property(cap, "modulate:a", 0.0, 0.1)
		ctw.tween_callback(_free_part.bind(cap))
	if ghost == null or not is_instance_valid(ghost):
		return
	var home := Vector2.ZERO
	var have_home := false
	if _src_node != null and is_instance_valid(_src_node) and not _src_node.is_queued_for_deletion():
		home = _src_node.get_global_rect().get_center() - ghost.size * 0.5
		have_home = true
	var tw := ghost.create_tween()
	if have_home:
		tw.tween_property(ghost, "global_position", home, 0.12) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		# 原格已经不在了（重建过）：就地淡出，别悬在半空
		tw.tween_property(ghost, "modulate:a", 0.0, 0.1)
	tw.tween_callback(_free_part.bind(ghost))

func _free_part(c: Control) -> void:
	if c != null and is_instance_valid(c):
		c.queue_free()

func _restore_src() -> void:
	if _src_node != null and is_instance_valid(_src_node):
		_src_node.modulate = Color.WHITE
	_src_node = null

## 商店已关/换回合等异常收场：一切复位，不吐操作
func _cancel_all() -> void:
	_press_cancel()
	_drag = {}
	_clear_hover()
	_free_part(_ghost)
	_free_part(_cap)
	_ghost = null
	_cap = null
	_cap_txt = ""
	_restore_src()

# ---------------- 数据读数 ----------------

## 按登记的 src 取当下那一件（拎起那一刻的数据，拿图标与星级用）：
## 上阵池现读 get_weapons_summary（悬浮武器 + 灵宝），背包池读 stash
func _item_of(src: Dictionary) -> Dictionary:
	var i := int(src.get("index", -1))
	if String(src.get("pool", "")) == "stash":
		if i >= 0 and i < GameManager.stash.size():
			return GameManager.stash[i]
		return {}
	var list: Array = GameManager.get_weapons_summary()
	if i >= 0 and i < list.size():
		return list[i]
	return {}

func _exit_tree() -> void:
	_clear_hover()
