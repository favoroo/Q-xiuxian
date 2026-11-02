class_name SaveManageDialog
extends BaseModalDialog

## 多局存档管理弹窗（2026-10-28；2026-11-02 一局一位重构）
## 两种模式：
##   MANAGE    —— 首页「存 档」进入：5 局列表，选中一局 → 继续此局 / 删除。
##   MAKE_ROOM —— 暂停菜单「存 档」遇 5 位全满且本局未占位时进入：
##                选一局替换（二次确认），原子写入本局；旧局进度被删除。
## 一局一位：这里不再提供「选空位另存一份」的入口；正常存档由 PauseMenu 直接写本局唯一位。
## 树暂停只置真不置假（打开前本来就在暂停态），关闭后由 Main 决定回暂停菜单还是读档恢复。

signal load_requested(slot_index: int)

enum Mode { MANAGE, MAKE_ROOM }

const SLOT_COUNT := SaveSlots.SLOT_COUNT

var _mode: int = Mode.MANAGE
var _pending_mode: int = Mode.MANAGE
var _selected: int = -1
var _arm: StringName = &""
var _arm_timer: Tween = null
var _cards: Array[Dictionary] = []
var _list: VBoxContainer
var _scroll: ScrollContainer
var _hint: Label
var _count_label: Label
var _primary: Button
var _delete: Button

# ---------------- BaseModalDialog 钩子 ----------------

func _get_title_text() -> String:
	return "存 档 管 理"

func _get_panel_size() -> Vector2:
	return Vector2(760, 470)

func _get_panel_margins() -> Vector4:
	return Vector4(24, 16, 24, 16)

func _get_vbox_separation() -> int:
	return 10

func _build_body(root: VBoxContainer) -> void:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tab_bar.add_child(spacer)

	_count_label = Label.new()
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	GameStyle.label(_count_label, 12, GameStyle.PAPER_DIM)
	_tab_bar.add_child(_count_label)

	_hint = Label.new()
	GameStyle.label(_hint, 12, GameStyle.PAPER_DIM)
	root.add_child(_hint)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)
	GameStyle.scrollable(_scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	_scroll.add_child(_list)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	root.add_child(actions)

	_primary = _make_action_btn()
	_primary.pressed.connect(_on_primary_pressed)
	actions.add_child(_primary)

	_delete = _make_action_btn()
	_delete.pressed.connect(_on_delete_pressed)
	actions.add_child(_delete)

	var foot := Label.new()
	foot.text = "每局只占 1 位 · 存入后进度自动更新 · 阵亡后本局存档删除"
	GameStyle.label(foot, 11, GameStyle.GREY)
	root.add_child(foot)

func _make_action_btn() -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 36)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_NONE
	return btn

# ---------------- 打开 / 关闭 ----------------

func open() -> void:
	_pending_mode = Mode.MANAGE
	super.open()

func open_manage() -> void:
	_pending_mode = Mode.MANAGE
	super.open()

## 满位腾位模式：只有暂停菜单在「5 位全满且本局未占位」时才调。
func open_make_room() -> void:
	_pending_mode = Mode.MAKE_ROOM
	super.open()

## 读档成功时由 Main 调：立刻收起、不播淡出 —— 战场马上恢复，不能留半透明弹窗盖着。
## 不走 close()/closed 信号，避免 Main 的「回暂停菜单」逻辑被误触发。
func dismiss() -> void:
	_reset_arm()
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	_closing = false

func _on_opened() -> void:
	_mode = _pending_mode
	_arm = &""
	_selected = -1
	# 腾位模式若还有空位（并发/异常），默认选中空位；满位则必须由玩家选一局替换
	if _mode == Mode.MAKE_ROOM:
		_selected = SaveSlots.first_free_slot()
	get_tree().paused = true
	_rebuild()

func _on_closed() -> void:
	_reset_arm()
	_selected = -1
	_mode = Mode.MANAGE

# ---------------- 列表 ----------------

func _rebuild() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_cards.clear()
	var used := SaveSlots.count_used()
	for entry in SaveSlots.list_slots():
		var si := int(entry.get("index", 1))
		var res := SaveSlotCardFactory.create(entry, si == _selected,
			func() -> void: _on_slot_pressed(si), _mode == Mode.MAKE_ROOM)
		res["entry"] = entry
		_list.add_child(res["card"])
		_cards.append(res)
	GameStyle.swipeable(_scroll)
	_count_label.text = "已存 %d / %d 局" % [used, SLOT_COUNT]
	_refresh_hint(used)
	_refresh_actions()

func _refresh_hint(used: int) -> void:
	if _mode == Mode.MAKE_ROOM:
		if used >= SLOT_COUNT:
			_hint.text = "◆ 存档已满 · 选择一局替换（该局进度将被删除）◆"
			_hint.add_theme_color_override("font_color", GameStyle.BAD)
		else:
			_hint.text = "选择空位存入本局（一局只占一位，存入后进度自动更新）"
			_hint.add_theme_color_override("font_color", GameStyle.PAPER_DIM)
		return
	_hint.add_theme_color_override("font_color", GameStyle.PAPER_DIM)
	_hint.text = "最多保留 %d 局 · 每局只占 1 位 · 选中后可继续或删除" % SLOT_COUNT

func _on_slot_pressed(index: int) -> void:
	if _selected == index and _arm == &"":
		return
	_reset_arm()
	_selected = index
	for res in _cards:
		var entry: Dictionary = res.get("entry", {})
		SaveSlotCardFactory.apply_style(res["card"], entry,
			int(entry.get("index", -1)) == _selected)
	_refresh_actions()

func _selected_entry() -> Dictionary:
	for res in _cards:
		var entry: Dictionary = res.get("entry", {})
		if int(entry.get("index", -1)) == _selected:
			return entry
	return {}

# ---------------- 动作条 ----------------

func _refresh_actions() -> void:
	var entry := _selected_entry()
	var occupied := not entry.is_empty() and bool(entry.get("occupied", false))
	var corrupt := not entry.is_empty() and bool(entry.get("corrupt", false))
	var loadable := not entry.is_empty() and bool(entry.get("loadable", true))
	_delete.visible = _mode == Mode.MANAGE

	if _mode == Mode.MANAGE:
		# 旧快照（同一局还有更前的一份）不可读，只能删：一局一位的兜底闸
		_primary.text = "继 续 此 局"
		_primary.disabled = not (occupied and not corrupt and loadable)
		GameStyle.button(_primary, GameStyle.GOLD, GameStyle.JADE, 14,
			GameStyle.INK_TEXT, GameStyle.SLANT_BUTTON)
		_delete.disabled = not occupied
		if _arm == &"delete":
			_delete.text = "再点确认删除"
			GameStyle.button(_delete, GameStyle.BAD, GameStyle.JADE, 14,
				GameStyle.CHALK, GameStyle.SLANT_BUTTON, GameStyle.INK_TEXT)
		else:
			_delete.text = "删 除"
			GameStyle.button(_delete, GameStyle.NAVY2, GameStyle.BAD, 14,
				GameStyle.PAPER, GameStyle.SLANT_BUTTON)
		return

	# MAKE_ROOM：空位「存入本局」；已有局一律二次确认后替换
	_primary.disabled = entry.is_empty()
	if occupied:
		_primary.text = "再点确认替换" if _arm == &"replace" else "删 除 并 存 入"
		GameStyle.button(_primary, GameStyle.BAD, GameStyle.JADE, 14,
			GameStyle.CHALK, GameStyle.SLANT_BUTTON, GameStyle.INK_TEXT)
	else:
		_primary.text = "存 入 此 位"
		GameStyle.button(_primary, GameStyle.GOLD, GameStyle.JADE, 14,
			GameStyle.INK_TEXT, GameStyle.SLANT_BUTTON)

func _on_primary_pressed() -> void:
	var entry := _selected_entry()
	if entry.is_empty():
		return
	if _mode == Mode.MANAGE:
		if bool(entry.get("occupied", false)) and not bool(entry.get("corrupt", false)) \
				and bool(entry.get("loadable", true)) and SaveSlots.valid_index(_selected):
			load_requested.emit(_selected)
		return

	var occupied := bool(entry.get("occupied", false))
	if occupied:
		# 替换要二次点按确认；写失败时旧档原样保留（RunSave._atomic_save 先写 .tmp 再 rename）
		if _arm != &"replace":
			_arm = &"replace"
			_start_arm_timer()
			_refresh_actions()
			return
		_reset_arm()
		if SaveSlots.save_run_to_slot(GameManager, _selected):
			UpdateManager.show_toast("◆ 已替换存档位 %d · 本局已存入 ◆" % _selected,
				GameStyle.GOLD, 2.5)
			AudioManager.play_sfx("ui_confirm", 0.95)
			close()
		else:
			UpdateManager.show_toast("◆ 存档失败，旧存档未改动 ◆", GameStyle.BAD, 3.0)
		return

	if SaveSlots.save_run_to_slot(GameManager, _selected):
		UpdateManager.show_toast("◆ 已存入存档位 %d ◆" % _selected, GameStyle.GOLD, 2.5)
		AudioManager.play_sfx("ui_confirm", 0.95)
		close()
	else:
		UpdateManager.show_toast("◆ 存档失败，请稍后再试 ◆", GameStyle.BAD, 3.0)

func _on_delete_pressed() -> void:
	var entry := _selected_entry()
	if entry.is_empty() or not bool(entry.get("occupied", false)):
		return
	if _arm != &"delete":
		_arm = &"delete"
		_start_arm_timer()
		_refresh_actions()
		return
	_reset_arm()
	var index := _selected
	if SaveSlots.delete_slot(index):
		UpdateManager.show_toast("◆ 已删除存档 %d ◆" % index, GameStyle.GOLD, 2.2)
		_selected = -1
		_rebuild()
	else:
		UpdateManager.show_toast("◆ 删除失败 ◆", GameStyle.BAD, 2.5)

func _start_arm_timer() -> void:
	if _arm_timer != null and _arm_timer.is_valid():
		_arm_timer.kill()
	_arm_timer = create_tween()
	_arm_timer.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_arm_timer.tween_interval(3.0)
	_arm_timer.tween_callback(func() -> void:
		_arm = &""
		_arm_timer = null
		_refresh_actions()
	)

func _reset_arm() -> void:
	_arm = &""
	if _arm_timer != null and _arm_timer.is_valid():
		_arm_timer.kill()
	_arm_timer = null