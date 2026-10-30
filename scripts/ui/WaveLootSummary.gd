class_name WaveLootSummary
extends Control

## 波末战利品摘要卡（多条目摘要：灵石/法宝/葫芦各一行）
## 在回合结束吸附清场后、进入悟道面板/金币阁之前弹出，展示本回合战斗中获得的全部战利品。
## 特别当玉匣开出商店道具时醒目高亮并注明「可在金币阁出售」，让玩家清晰掌握背包变动。
## 遵循 GameStyle 新野兽派直角规范，纯代码构建。

signal summary_closed

const CARD_WIDTH := 450.0
const AUTO_DISMISS_NORMAL := 2.2
const AUTO_DISMISS_WITH_ITEM := 3.0

var _dim_bg: ColorRect
var _center: CenterContainer
var _card_panel: PanelContainer
var _content_vbox: VBoxContainer
var _title_label: Label
var _gold_val_label: Label
var _items_row_box: VBoxContainer
var _heals_val_label: Label
var _continue_btn: Button
var _hint_label: Label

var _is_showing: bool = false
var _tween: Tween = null
var _auto_dismiss_time: float = 0.0
var _current_loot: Dictionary = {}
var _sold_items: Dictionary = {}

func _init() -> void:
	name = "WaveLootSummary"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func _ready() -> void:
	_build_ui()
	if not GameManager.wave_loot_summary_requested.is_connected(popup_summary):
		GameManager.wave_loot_summary_requested.connect(popup_summary)

func _build_ui() -> void:
	# 1. 半透明暗色背景（点击任意空白处关闭跳过）
	_dim_bg = ColorRect.new()
	_dim_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim_bg.color = Color(0.0, 0.0, 0.0, 0.52)
	_dim_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim_bg.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
			dismiss()
	)
	add_child(_dim_bg)

	# 2. 居中容器
	_center = CenterContainer.new()
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center)

	# 3. 卡片面板（新野兽派直角纯黑宣纸面板 + 暖金色线框）
	_card_panel = PanelContainer.new()
	_card_panel.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	_card_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_sb := GameStyle.outlined_panel(GameStyle.NAVY2, GameStyle.GOLD, 2, 0.0)
	_card_panel.add_theme_stylebox_override("panel", panel_sb)
	_center.add_child(_card_panel)

	# 内边距
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	_card_panel.add_child(margin)

	_content_vbox = VBoxContainer.new()
	_content_vbox.add_theme_constant_override("separation", 9)
	margin.add_child(_content_vbox)

	# 标题带
	_title_label = Label.new()
	GameStyle.label(_title_label, 15, GameStyle.GOLD, 0, GameStyle.INK, true)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.text = "◆ 本回合所得 ◆"
	_content_vbox.add_child(_title_label)

	var sep1 := _make_separator(GameStyle.GOLD_DK)
	_content_vbox.add_child(sep1)

	# 条目 1：灵石收益
	var gold_row := HBoxContainer.new()
	var gold_lbl := Label.new()
	gold_lbl.text = "灵石收益"
	GameStyle.label(gold_lbl, 13, GameStyle.PAPER_DIM)
	gold_row.add_child(gold_lbl)

	_gold_val_label = Label.new()
	_gold_val_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gold_val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	GameStyle.label(_gold_val_label, 14, GameStyle.GOLD, 0, GameStyle.INK, true)
	gold_row.add_child(_gold_val_label)
	_content_vbox.add_child(gold_row)

	# 条目 2：掉落法宝（多行容器）
	_items_row_box = VBoxContainer.new()
	_items_row_box.add_theme_constant_override("separation", 4)
	_content_vbox.add_child(_items_row_box)

	# 条目 3：回春葫芦
	var heals_row := HBoxContainer.new()
	var heals_lbl := Label.new()
	heals_lbl.text = "回春葫芦"
	GameStyle.label(heals_lbl, 13, GameStyle.PAPER_DIM)
	heals_row.add_child(heals_lbl)

	_heals_val_label = Label.new()
	_heals_val_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heals_val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	GameStyle.label(_heals_val_label, 13, GameStyle.GOOD)
	heals_row.add_child(_heals_val_label)
	_content_vbox.add_child(heals_row)

	var sep2 := _make_separator(GameStyle.LINE)
	_content_vbox.add_child(sep2)

	# 操作按钮行（居中）
	var action_box := HBoxContainer.new()
	action_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_continue_btn = Button.new()
	_continue_btn.custom_minimum_size = Vector2(180, 32)
	GameStyle.button(_continue_btn, GameStyle.GOLD, GameStyle.GOLD_EDGE, 12, GameStyle.INK_TEXT, 0.0)
	_continue_btn.text = "继续 (点击跳过)"
	_continue_btn.pressed.connect(dismiss)
	action_box.add_child(_continue_btn)
	_content_vbox.add_child(action_box)

	# 底部提示小字
	_hint_label = Label.new()
	_hint_label.text = "[ 点击任意处继续 ]"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameStyle.label(_hint_label, 10, GameStyle.CHALK)
	_content_vbox.add_child(_hint_label)

func _make_separator(color: Color) -> ColorRect:
	var cr := ColorRect.new()
	cr.custom_minimum_size = Vector2(0, 1)
	cr.color = color
	return cr

## 弹出战利品摘要并计时，关闭时触发 summary_closed 信号
func popup_summary(loot: Dictionary, auto_dismiss_in_headless: bool = true) -> void:
	if _is_showing:
		return
	_is_showing = true
	_current_loot = loot.duplicate(true)
	_sold_items.clear()

	var wave := int(_current_loot.get("wave", 1))
	var items: Array = _current_loot.get("items", [])
	var heals := int(_current_loot.get("heals", 0))
	var heal_hp := float(_current_loot.get("heal_hp", 0.0))
	var heal_stones := int(_current_loot.get("heal_stones", 0))

	# 标题
	_title_label.text = "◆ 第 %d 波所得 ◆" % wave

	# 灵石
	_refresh_gold_label()

	# 掉落法宝
	for c in _items_row_box.get_children():
		c.queue_free()

	if items.is_empty():
		var empty_row := HBoxContainer.new()
		var lbl_t := Label.new()
		lbl_t.text = "掉落法宝"
		GameStyle.label(lbl_t, 13, GameStyle.PAPER_DIM)
		empty_row.add_child(lbl_t)

		var lbl_v := Label.new()
		lbl_v.text = "无"
		lbl_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl_v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		GameStyle.label(lbl_v, 13, GameStyle.PAPER_DIM)
		empty_row.add_child(lbl_v)
		_items_row_box.add_child(empty_row)
	else:
		for i in range(items.size()):
			var item_id := String(items[i])
			var def := ItemData.get_def(item_id)
			var item_name := String(def.get("name", item_id))
			var tier_num := int(def.get("tier", 1))
			var tier_col := ItemData.tier_color(tier_num)
			var refund := ItemData.sell_price(item_id)
			var no_sell := ItemData.is_no_sell(item_id)

			var row := HBoxContainer.new()
			if i == 0:
				var lbl_t := Label.new()
				lbl_t.text = "掉落法宝"
				GameStyle.label(lbl_t, 13, GameStyle.PAPER_DIM)
				row.add_child(lbl_t)
			else:
				var spacer := Control.new()
				spacer.custom_minimum_size = Vector2(56, 0)
				row.add_child(spacer)

			var val_box := HBoxContainer.new()
			val_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			val_box.alignment = BoxContainer.ALIGNMENT_END
			val_box.add_theme_constant_override("separation", 8)

			# 可点按看详情的法宝名微标
			var name_lbl := Label.new()
			name_lbl.text = "【%s】" % item_name
			name_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
			GameStyle.label(name_lbl, 13, tier_col, 0, GameStyle.INK, true)
			val_box.add_child(name_lbl)

			# 直接变卖按钮（或不可售卖状态）
			var sell_btn := Button.new()
			sell_btn.custom_minimum_size = Vector2(86, 24)
			val_box.add_child(sell_btn)

			if no_sell:
				sell_btn.text = "不可售"
				sell_btn.disabled = true
				GameStyle.button(sell_btn, GameStyle.DISABLED_FACE, GameStyle.DISABLED_FACE, 11, GameStyle.PAPER_DIM, 0.0)
			else:
				sell_btn.text = "变卖 (+%d)" % refund
				GameStyle.button(sell_btn, GameStyle.BAD, GameStyle.BAD_DK, 11, GameStyle.PAPER, 0.0)
				sell_btn.pressed.connect(func() -> void:
					_sell_item(item_id, sell_btn, refund)
				)

			# 点按法宝名弹出详情浮层，同样支持在详情卡内变卖
			GameStyle.tap(name_lbl, func() -> void:
				_open_item_detail(item_id, name_lbl, sell_btn, refund)
			)

			row.add_child(val_box)
			_items_row_box.add_child(row)

	# 回春葫芦
	if heals > 0:
		var heal_desc := "%d 颗 (恢复 %d 生命" % [heals, int(round(heal_hp))]
		if heal_stones > 0:
			heal_desc += "，折算 +%d 灵石)" % heal_stones
		else:
			heal_desc += ")"
		_heals_val_label.text = heal_desc
		_heals_val_label.modulate = GameStyle.GOOD
	else:
		_heals_val_label.text = "0 颗"
		_heals_val_label.modulate = GameStyle.PAPER_DIM

	# 下一步按钮文案适配
	if GameManager.has_pending_upgrades() or (GameManager.wave_number % 5 == 0 and GameManager.wave_number <= 15):
		_continue_btn.text = "前往悟道"
	else:
		_continue_btn.text = "前往金币阁"

	# 提示文字
	if items.is_empty():
		_hint_label.text = "[ 点击任意处继续 ]"
	else:
		_hint_label.text = "[ 点击法宝看属性 · 可直接点击变卖回收 ]"

	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 无头测试环境下直接关闭，防死锁与超时
	if DisplayServer.get_name() == "headless" and auto_dismiss_in_headless:
		call_deferred("dismiss")
		return

	# 入场动效
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_dim_bg.modulate.a = 0.0
	_card_panel.scale = Vector2(0.96, 0.96)
	_card_panel.pivot_offset = _card_panel.size * 0.5

	_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.parallel().tween_property(_dim_bg, "modulate:a", 1.0, 0.16)
	_tween.parallel().tween_property(_card_panel, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# 倒计时自动关闭：有法宝掉落时保持常开留给玩家决策，无法宝时 2.2s 自动跳过
	if items.is_empty():
		_auto_dismiss_time = AUTO_DISMISS_NORMAL
		get_tree().create_timer(_auto_dismiss_time, false, false, true).timeout.connect(func():
			if _is_showing:
				dismiss()
		)

func _refresh_gold_label() -> void:
	var stones := int(_current_loot.get("stones", 0))
	_gold_val_label.text = "+%d" % stones

## 执行法宝变卖逻辑：调用 GameManager.sell_item，回退属性、增加灵石、刷新 UI
func _sell_item(item_id: String, btn: Button, refund: int) -> void:
	if _sold_items.get(item_id, false):
		return
	var def := ItemData.get_def(item_id)
	var slots_given := int((def.get("apply", {}) as Dictionary).get("pet_slots", 0))
	if slots_given > 0 and GameManager.pets.size() > GameManager.max_pet_slots() - slots_given:
		GameManager.announcement_triggered.emit("灵兽栏已超编：无法直接变卖该法宝")
		return

	if GameManager.sell_item(item_id):
		_sold_items[item_id] = true
		btn.text = "已变卖"
		btn.disabled = true
		btn.add_theme_stylebox_override("disabled", GameStyle.panel(GameStyle.DISABLED_FACE, 0.0))
		btn.add_theme_color_override("font_disabled_color", GameStyle.GREY)
		# 实时刷新灵石显示
		var cur_stones := int(_current_loot.get("stones", 0))
		_current_loot["stones"] = cur_stones + refund
		_refresh_gold_label()
		# 移除本回合新获得标记
		GameManager.wave_loot_items.erase(item_id)
		# 弹出飞字反馈
		DamageNumber.spawn(self, btn.global_position + Vector2(20.0, -10.0), refund, false, "+%d 灵石" % refund)

## 点按法宝名弹出详情浮层，同样支持在详情卡内变卖
func _open_item_detail(item_id: String, anchor: Control, sell_btn: Button, refund: int) -> void:
	var def := ItemData.get_def(item_id)
	if def.is_empty():
		return
	var tier_num := int(def.get("tier", 1))
	var tier_col := ItemData.tier_color(tier_num)
	var no_sell := ItemData.is_no_sell(item_id)
	var is_sold: bool = bool(_sold_items.get(item_id, false))

	var rows: Array = [["品阶", ItemData.tier_label(tier_num), tier_col]]
	if no_sell:
		rows.append(["来源", "飞升悟道", tier_col])
	else:
		rows.append(["原价", "%d 金币" % int(def.get("price", 0)), GameStyle.PAPER_DIM])
		rows.append(["出售返还", "%d 金币" % refund, GameStyle.JADE])

	rows.append_array(BonusRows.apply_rows(def.get("apply", {})))

	var desc_lines: Array = String(def.get("desc", "")).split("\n")
	var notes: Array[String] = []
	for line in desc_lines:
		var s := String(line).strip_edges()
		if not s.is_empty():
			notes.append(s)
	if no_sell:
		notes.append("神通来自飞升悟道，本局永久生效，不可出售。")
	else:
		notes.append("出售按原价一半回收金币，加过的属性当场退回。")

	var foot := "可在本界面直接变卖，或进入金币阁后变卖。"
	if no_sell:
		foot = "神通不可出售：它已经是你这一局的一部分。"

	var slots_given := int((def.get("apply", {}) as Dictionary).get("pet_slots", 0))
	var over_pets := slots_given > 0 and GameManager.pets.size() > GameManager.max_pet_slots() - slots_given

	var actions: Array = []
	if no_sell:
		actions = [[{
			"text": "神通不可出售",
			"disabled": true,
			"color": GameStyle.GREY,
			"edge_color": GameStyle.GREY,
			"text_color": GameStyle.PAPER,
			"callback": func(): pass,
		}]]
	elif is_sold:
		actions = [[{
			"text": "已变卖",
			"disabled": true,
			"color": GameStyle.GREY,
			"edge_color": GameStyle.GREY,
			"text_color": GameStyle.PAPER,
			"callback": func(): pass,
		}]]
	else:
		actions = [[{
			"text": "先出售灵兽" if over_pets else "出售 (+%d 金币)" % refund,
			"disabled": over_pets,
			"color": GameStyle.BAD,
			"edge_color": GameStyle.BAD_DK,
			"text_color": GameStyle.PAPER,
			"callback": func():
				_sell_item(item_id, sell_btn, refund),
		}]]

	DetailTip.show_over(self, anchor, {
		"title": String(def.get("name", item_id)),
		"chip": "神通" if no_sell else "被动道具",
		"chip_color": tier_col,
		"rows": rows,
		"body": "被动道具：自动生效，不占武器槽，整局持续有效。",
		"notes": notes,
		"foot": foot,
		"actions": actions,
	})

## 关闭摘要并触发 closed
func dismiss() -> void:
	if not _is_showing:
		return
	_is_showing = false
	if _tween != null and _tween.is_valid():
		_tween.kill()

	if DisplayServer.get_name() == "headless":
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		summary_closed.emit()
		GameManager.wave_loot_summary_finished.emit()
		return

	_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.parallel().tween_property(_dim_bg, "modulate:a", 0.0, 0.10)
	_tween.parallel().tween_property(_card_panel, "scale", Vector2(0.95, 0.95), 0.10)
	_tween.tween_callback(func():
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		summary_closed.emit()
		GameManager.wave_loot_summary_finished.emit()
	)

func _exit_tree() -> void:
	if GameManager.wave_loot_summary_requested.is_connected(popup_summary):
		GameManager.wave_loot_summary_requested.disconnect(popup_summary)
