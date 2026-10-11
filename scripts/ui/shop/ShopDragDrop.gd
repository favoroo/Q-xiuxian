class_name ShopDragDrop
extends Node

## 灵石阁陈列行「按住拎起 → 拖到目标格放下」的换装手势（2026-10-11 用户：背包里的装备
## 和已佩戴的装备要能拖动换位，拖到背包＝卸下、拖到上阵格＝佩戴）。
## 陈列行的格子（上阵格/背包格/背包空位/「背包 n/9」分隔签）在构建时经 register_slot 登记，
## 手势状态机归这一个节点管；数据操作回流 GameManager（swap_into_equipped / unequip_to_stash
## / reorder_stash），刷新走 shop.refresh(false) —— 与点按详情卡里的「装备/卸下」按钮同一条链路。
##
## 手势口径（与 GameStyle.tap 同一把 TAP_SLACK 尺，两者互不干扰）：
##  · 按住不动 HOLD_DELAY 秒 ⇒ 拎起：图标跟手（上提一段不被手指挡住）、落点格描边高亮；
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
##  · 上阵件 → 背包区（背包格/空位/分隔签）＝卸入背包（背包满由 unequip_to_stash 播报）；
##  · 上阵件 → 上阵另一格＝互换位置（同池才换：悬浮法器换悬浮法器、灵宝换灵宝，
##    见 WeaponInventory.swap_equipped_slots；混池不挪 —— summary 固定
##    「悬浮法器在前、灵宝在后」，跨池次序没有可落的数据）；上阵空格不接上阵件；
##  · 背包件 → 背包区＝背包内排序（空位/分隔签＝挪到队尾）。

## 按住多久算拎起：Android 拖拽的长按阀，比系统长按（0.4s）短一截，比误触划动停顿长
const HOLD_DELAY := 0.28
## 幽灵图标上提量：跟手时抬到手指上方一截，不被手指挡住
const GHOST_LIFT := 18.0
## 幽灵图标边长的夹取范围（源格 36~44 见方，拎起来放大一号才像「拿在手里」）
const GHOST_MIN := 40.0
const GHOST_MAX := 72.0

var _shop: WaveShop
## 登记表：[{node: Control, src: Dictionary}]；整行每次点按/操作后重建，
## 旧格子 queue_free 后由 is_instance_valid + is_queued_for_deletion 惰性剔除
var _slots: Array = []
## 待发：按住未满时限 {_press: Control, src, down: Vector2, gen: int}
var _press: Dictionary = {}
var _gen := 0
## 进行中：{src: Dictionary}；空字典＝没拎着
var _drag: Dictionary = {}
var _ghost: Control = null
## 拎起时的原件：松手飞回 / 还原压暗用（重建后可能已失效，用时先 is_instance_valid）
var _src_node: Control = null
var _hover_node: Control = null
var _hover_sb: StyleBoxFlat = null
var _hover_border := Color()

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
	_press = {"node": node, "src": src, "down": down, "gen": _gen}
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
		return
	if _press.is_empty():
		return
	# 待发阶段不截事件：划出去就是横滑，拎起作废（滚动照旧、tap 的账照记）
	if mm != null and (_press.get("down", Vector2.ZERO) as Vector2).distance_to(mm.global_position) > GameStyle.TAP_SLACK:
		_press_cancel()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_press_cancel()

func _pickup() -> void:
	var src: Dictionary = _press.get("src", {})
	var n = _press.get("node")
	var down: Vector2 = _press.get("down", Vector2.ZERO)
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
	_build_ghost(item, tile)
	if _src_node != null and is_instance_valid(_src_node):
		_src_node.modulate = Color(1.0, 1.0, 1.0, 0.45)
	AudioManager.play_sfx("ui_click", 0.9)
	_drag_move(down)

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
	var icon := TextureRect.new()
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		icon.texture = load(icon_path)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.add_child(icon)
	GameStyle.star_label(ghost, int(item.get("star", 1)), 12)
	_shop.add_child(ghost)
	ghost.custom_minimum_size = Vector2(gsize, gsize)
	ghost.size = Vector2(gsize, gsize)
	# 拎起的一下小弹跳：让「拎起来了」看得见（不引渐变不引辉光，只动尺寸）
	ghost.pivot_offset = ghost.size * 0.5
	ghost.scale = Vector2(0.85, 0.85)
	var tw := ghost.create_tween()
	tw.tween_property(ghost, "scale", Vector2.ONE, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_ghost = ghost

# ---------------- 拖动 / 落点 ----------------

func _drag_move(p: Vector2) -> void:
	if _ghost == null or not is_instance_valid(_ghost):
		return
	var vr := get_viewport().get_visible_rect()
	var pos := p - Vector2(_ghost.size.x * 0.5, _ghost.size.y + GHOST_LIFT)
	pos = pos.clamp(vr.position + Vector2(2.0, 2.0), vr.end - _ghost.size - Vector2(2.0, 2.0))
	_ghost.global_position = pos
	_set_hover(_target_at(p))

## 指针压着哪个合法落点（源格自己不算：拖回原位＝空手松开＝飞回，不许高亮骗人）
func _target_at(p: Vector2) -> Dictionary:
	var src: Dictionary = _drag.get("src", {})
	# 整行每次点按/操作后重建：先把已释放的登记惰性压掉（freed instance 不能赋给类型化变量，
	# 必须先 is_instance_valid 再转 Control）
	_slots = _slots.filter(func(t) -> bool:
		var n = t.get("node")
		return n != null and is_instance_valid(n) and not (n as Control).is_queued_for_deletion()
	)
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
		if node.get_global_rect().has_point(p):
			return {"node": node, "src": ts}
	return {}

## 落点合法性（与 _apply 同一条规则，高亮不许许诺做不到的事）
func _droppable(src: Dictionary, ts: Dictionary) -> bool:
	var sp := String(src.get("pool", ""))
	var tp := String(ts.get("pool", ""))
	if sp == "stash":
		return tp == "equipped" or tp == "stash"
	if sp == "equipped":
		if tp == "stash":
			return true
		# 上阵 → 上阵＝互换位置；上阵空格不是一件武器，不接（松手原样飞回）
		return tp == "equipped" and String(ts.get("kind", "")) != "empty"
	return false

func _set_hover(t: Dictionary) -> void:
	var node: Control = t.get("node")
	if node == _hover_node:
		return
	_clear_hover()
	if node == null or not is_instance_valid(node):
		return
	_hover_node = node
	var sb := node.get_theme_stylebox("panel")
	if sb is StyleBoxFlat:
		_hover_sb = sb
		_hover_border = sb.border_color
		sb.border_color = GameStyle.PAPER

func _clear_hover() -> void:
	if _hover_sb != null:
		_hover_sb.border_color = _hover_border
	_hover_sb = null
	_hover_node = null

# ---------------- 放下 ----------------

func _drop() -> void:
	var src: Dictionary = _drag.get("src", {})
	var tgt: Dictionary = {}
	if _hover_node != null and is_instance_valid(_hover_node):
		tgt = _hover_node.get_meta("drag_src", {})
	var ghost := _ghost
	_ghost = null
	_clear_hover()
	_drag = {}
	var ok := false
	if not tgt.is_empty() and not src.is_empty():
		ok = _apply(src, tgt)
	if ok:
		_shop.selected = {}
		_shop.refresh(false)
		_restore_src()
		if ghost != null and is_instance_valid(ghost):
			ghost.queue_free()
	else:
		_snap_back(ghost)

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
		return GameManager.unequip_to_stash(int(src.get("index", -1)))
	if sp == "equipped" and tp == "equipped":
		return GameManager.swap_equipped_slots(int(src.get("index", -1)), int(tgt.get("index", -1)))
	return false

## 空手松开 / 操作失败：幽灵飞回原格（原格还在的话），原格的压暗还原
func _snap_back(ghost: Control) -> void:
	_restore_src()
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
	tw.tween_callback(func() -> void:
		if is_instance_valid(ghost):
			ghost.queue_free()
	)

func _restore_src() -> void:
	if _src_node != null and is_instance_valid(_src_node):
		_src_node.modulate = Color.WHITE
	_src_node = null

## 商店已关/换波等异常收场：一切复位，不吐操作
func _cancel_all() -> void:
	_press_cancel()
	_drag = {}
	_clear_hover()
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	_restore_src()

# ---------------- 数据读数 ----------------

## 按登记的 src 取当下那一件（拎起那一刻的数据，拿图标与星级用）：
## 上阵池现读 get_weapons_summary（悬浮法器 + 灵宝），背包池读 stash
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
