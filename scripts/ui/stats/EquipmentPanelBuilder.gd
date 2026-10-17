class_name EquipmentPanelBuilder
extends RefCounted

## 属性面板右栏构建与上阵/仓库槽位刷新：道统卡速览、上阵武器槽、纳戒仓库、
## 羁绊区容器、随身道具/悟道历程双标签容器。
## 从 PlayerStatsDialog 拆出：构建结果直接写回 dialog 成员（_weapons_box / _stash_box /
## _history_list 等名字被判据引用，原样保留），点按回调经 dialog 门面。

static func build_right_panel(dialog: PlayerStatsDialog) -> Control:
	var right_vbox := VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_theme_constant_override("separation", 8)

	# 0. 顶部：当前道统特性速览（正面加成 / 负面代偿，点按看全部详解）
	dialog._cult_card = PanelContainer.new()
	dialog._cult_card.mouse_filter = Control.MOUSE_FILTER_STOP
	var cult_st := GameStyle.outlined_panel(GameStyle.NAVY, GameStyle.LINE, 2, 0.0)
	cult_st.content_margin_left = 12.0
	cult_st.content_margin_top = 5.0
	cult_st.content_margin_right = 12.0
	cult_st.content_margin_bottom = 5.0
	dialog._cult_card.add_theme_stylebox_override("panel", cult_st)
	dialog._cult_card.set_meta("sb_flat", cult_st)
	dialog._cult_card.set_meta("sb_on", GameStyle.outlined_panel(GameStyle.NAVY.lightened(0.08), GameStyle.JADE, 2, 0.0))

	var cult_row := HBoxContainer.new()
	cult_row.add_theme_constant_override("separation", 10)
	dialog._cult_card.add_child(cult_row)

	dialog._cult_icon = GameStyle.icon_texture_rect("", Vector2(40, 40))
	cult_row.add_child(dialog._cult_icon)

	var cult_text := VBoxContainer.new()
	cult_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cult_text.add_theme_constant_override("separation", 1)
	cult_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cult_row.add_child(cult_text)

	var cult_head := HBoxContainer.new()
	cult_head.add_theme_constant_override("separation", 8)
	cult_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cult_text.add_child(cult_head)

	dialog._cult_name_lbl = Label.new()
	GameStyle.label(dialog._cult_name_lbl, 13, GameStyle.JADE)
	cult_head.add_child(dialog._cult_name_lbl)

	dialog._cult_epi_lbl = Label.new()
	GameStyle.label(dialog._cult_epi_lbl, 11, GameStyle.GREY)
	cult_head.add_child(dialog._cult_epi_lbl)

	var cult_head_sp := Control.new()
	cult_head_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cult_head_sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cult_head.add_child(cult_head_sp)

	var cult_hint := Label.new()
	cult_hint.text = "点按看角色全部特性"
	GameStyle.label(cult_hint, 10, GameStyle.GREY)
	cult_head.add_child(cult_hint)

	dialog._cult_pros_lbl = Label.new()
	GameStyle.label(dialog._cult_pros_lbl, 11, GameStyle.GOOD)
	cult_text.add_child(dialog._cult_pros_lbl)

	# 额外技能单独一段（幽夜紫）：没配额外技能的角色这一行隐藏，不占位
	dialog._cult_extra_lbl = Label.new()
	GameStyle.label(dialog._cult_extra_lbl, 11, GameStyle.SHADOW)
	dialog._cult_extra_lbl.visible = false
	cult_text.add_child(dialog._cult_extra_lbl)

	dialog._cult_cons_lbl = Label.new()
	GameStyle.label(dialog._cult_cons_lbl, 11, GameStyle.BAD)
	cult_text.add_child(dialog._cult_cons_lbl)

	GameStyle.tap(dialog._cult_card, func() -> void: dialog._open_cultivator_tip(dialog._cult_card))
	right_vbox.add_child(dialog._cult_card)

	# 1. 上半区：上阵武器与纳戒仓库
	var wp_panel := PanelContainer.new()
	var wp_st := GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 2, 0.0)
	wp_st.content_margin_left = 12.0
	wp_st.content_margin_top = 6.0
	wp_st.content_margin_right = 12.0
	wp_st.content_margin_bottom = 6.0
	wp_panel.add_theme_stylebox_override("panel", wp_st)

	var wp_vbox := VBoxContainer.new()
	wp_vbox.add_theme_constant_override("separation", 6)
	wp_panel.add_child(wp_vbox)

	var wp_head := HBoxContainer.new()
	wp_head.add_theme_constant_override("separation", 10)
	dialog._wp_title_lbl = Label.new()
	dialog._wp_title_lbl.text = "✦ 装备武器 (0/6)"
	GameStyle.label(dialog._wp_title_lbl, 14, GameStyle.JADE)
	wp_head.add_child(dialog._wp_title_lbl)

	var wp_sp := Control.new()
	wp_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wp_head.add_child(wp_sp)

	var wp_sub := Label.new()
	wp_sub.text = "点图标看伤害乘区与升星规则"
	GameStyle.label(wp_sub, 11, GameStyle.PAPER_DIM)
	wp_head.add_child(wp_sub)
	wp_vbox.add_child(wp_head)

	var slots_row := HBoxContainer.new()
	slots_row.add_theme_constant_override("separation", 12)
	wp_vbox.add_child(slots_row)

	dialog._weapons_box = HBoxContainer.new()
	dialog._weapons_box.add_theme_constant_override("separation", 8)
	slots_row.add_child(dialog._weapons_box)

	# 纳戒仓库同排右侧展示（不额外撑高纵向空间）
	dialog._stash_section = HBoxContainer.new()
	dialog._stash_section.add_theme_constant_override("separation", 6)
	var stash_title := Label.new()
	stash_title.text = "仓库:"
	stash_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	GameStyle.label(stash_title, 12, GameStyle.PAPER_DIM)
	dialog._stash_section.add_child(stash_title)
	dialog._stash_box = HBoxContainer.new()
	dialog._stash_box.add_theme_constant_override("separation", 6)
	dialog._stash_section.add_child(dialog._stash_box)
	slots_row.add_child(dialog._stash_section)

	right_vbox.add_child(wp_panel)

	# 2. 中间核心区：流派羁绊与五行共鸣（仿土豆兄弟装备标签阶梯加成）
	var syn_panel := PanelContainer.new()
	var syn_st := GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 2, 0.0)
	syn_st.content_margin_left = 12.0
	syn_st.content_margin_top = 6.0
	syn_st.content_margin_right = 12.0
	syn_st.content_margin_bottom = 6.0
	syn_panel.add_theme_stylebox_override("panel", syn_st)

	var syn_vbox := VBoxContainer.new()
	syn_vbox.add_theme_constant_override("separation", 6)
	syn_panel.add_child(syn_vbox)

	var syn_head := HBoxContainer.new()
	var syn_title := Label.new()
	syn_title.text = "✦ 羁绊与元素共鸣"
	GameStyle.label(syn_title, 14, GameStyle.JADE)
	syn_head.add_child(syn_title)

	var syn_sp := Control.new()
	syn_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	syn_head.add_child(syn_sp)

	dialog._synergy_hint_lbl = Label.new()
	dialog._synergy_hint_lbl.text = "集齐 2 / 4 / 6 件同系武器解锁阶梯加成"
	GameStyle.label(dialog._synergy_hint_lbl, 11, GameStyle.PAPER_DIM)
	syn_head.add_child(dialog._synergy_hint_lbl)
	syn_vbox.add_child(syn_head)

	var syn_scroll := ScrollContainer.new()
	# 76：给顶部道统卡让出纵向空间，同时保住 StatsTipCheck 的 9px 出屏边距判定
	# （内容最小高度必须 ≤ 面板高度钳制 516，否则面板被撑高出屏）。羁绊卡可滚动，不丢信息。
	syn_scroll.custom_minimum_size = Vector2(0, 76)
	syn_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	syn_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	syn_vbox.add_child(syn_scroll)

	dialog._synergy_flow = HFlowContainer.new()
	dialog._synergy_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialog._synergy_flow.add_theme_constant_override("h_separation", 8)
	dialog._synergy_flow.add_theme_constant_override("v_separation", 8)
	syn_scroll.add_child(dialog._synergy_flow)

	right_vbox.add_child(syn_panel)

	# 3. 下半区：随身道具 / 悟道历程（双标签切换）
	var bot_panel := PanelContainer.new()
	bot_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bot_st := GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 2, 0.0)
	bot_st.content_margin_left = 12.0
	bot_st.content_margin_top = 6.0
	bot_st.content_margin_right = 12.0
	bot_st.content_margin_bottom = 6.0
	bot_panel.add_theme_stylebox_override("panel", bot_st)

	var bot_vbox := VBoxContainer.new()
	bot_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bot_vbox.add_theme_constant_override("separation", 6)
	bot_panel.add_child(bot_vbox)

	var bot_header := HBoxContainer.new()
	bot_header.add_theme_constant_override("separation", 8)

	dialog._bottom_tab_items_btn = Button.new()
	dialog._bottom_tab_items_btn.text = "✦ 携带道具 (0)"
	dialog._bottom_tab_items_btn.custom_minimum_size = Vector2(136, 26)
	dialog._bottom_tab_items_btn.focus_mode = Control.FOCUS_NONE
	dialog._bottom_tab_items_btn.pressed.connect(func(): dialog._switch_bottom_tab(0))
	bot_header.add_child(dialog._bottom_tab_items_btn)

	dialog._bottom_tab_hist_btn = Button.new()
	dialog._bottom_tab_hist_btn.text = "✦ 升级记录 (0)"
	dialog._bottom_tab_hist_btn.custom_minimum_size = Vector2(136, 26)
	dialog._bottom_tab_hist_btn.focus_mode = Control.FOCUS_NONE
	dialog._bottom_tab_hist_btn.pressed.connect(func(): dialog._switch_bottom_tab(1))
	bot_header.add_child(dialog._bottom_tab_hist_btn)

	var h_spacer := Control.new()
	h_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot_header.add_child(h_spacer)

	dialog._history_count_lbl = Label.new()
	dialog._history_count_lbl.text = "点按图标或条目查看详情"
	GameStyle.label(dialog._history_count_lbl, 11, GameStyle.PAPER_DIM)
	bot_header.add_child(dialog._history_count_lbl)
	bot_vbox.add_child(bot_header)

	# 随身道具滚动区
	dialog._items_scroll = ScrollContainer.new()
	dialog._items_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialog._items_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dialog._items_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	bot_vbox.add_child(dialog._items_scroll)

	dialog._items_flow = HFlowContainer.new()
	dialog._items_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialog._items_flow.add_theme_constant_override("h_separation", 8)
	dialog._items_flow.add_theme_constant_override("v_separation", 8)
	dialog._items_scroll.add_child(dialog._items_flow)

	# 悟道历程滚动区
	dialog._history_scroll = ScrollContainer.new()
	dialog._history_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialog._history_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dialog._history_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	bot_vbox.add_child(dialog._history_scroll)

	dialog._history_list = VBoxContainer.new()
	dialog._history_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialog._history_list.add_theme_constant_override("separation", 5)
	dialog._history_scroll.add_child(dialog._history_list)

	dialog._switch_bottom_tab(0)
	right_vbox.add_child(bot_panel)

	return right_vbox

## 上阵 + 仓库槽位重建：每格 44/36 见方、可点弹武器详情、锁定格画 ×
static func refresh_weapons(dialog: PlayerStatsDialog) -> void:
	for child in dialog._weapons_box.get_children():
		child.queue_free()
	for child in dialog._stash_box.get_children():
		child.queue_free()

	var summary := GameManager.get_weapons_summary()
	var max_slots := GameManager.max_weapon_slots()
	if dialog._wp_title_lbl != null:
		dialog._wp_title_lbl.text = "✦ 装备武器 (%d/%d)" % [summary.size(), max_slots]

	for i in range(WeaponData.MAX_SLOTS):
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(44, 44)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP

		var filled := i < summary.size()
		var locked := i >= max_slots
		var border_col: Color = GameStyle.GOLD if filled else GameStyle.LINE
		# 元素件 = 暖橙红描边（与商店陈列行/货架卡同一语言；原先贴右上角的「元素」色块已撤，
		# 44 见方的格子上它会遮掉图标一角 —— 2026-10-12 用户）
		if filled:
			border_col = GameStyle.element_border(String(summary[i].get("id", "")), border_col)
		var bg_col: Color = GameStyle.NAVY if filled else GameStyle.with_alpha(GameStyle.INK, 0.45)
		var sb_off := GameStyle.outlined_panel(bg_col, border_col, 2, 0.0)
		slot.add_theme_stylebox_override("panel", sb_off)
		slot.set_meta("sb_flat", sb_off)
		slot.set_meta("sb_on", GameStyle.outlined_panel(bg_col, GameStyle.JADE, 2, 0.0))

		if filled:
			var w_wid := String(summary[i].get("id", ""))
			var w: Dictionary = summary[i]
			var tex_rect := GameStyle.icon_texture_rect(
				String(w.get("icon", "")),
				Vector2(34, 34)
			)
			slot.add_child(tex_rect)

			# 元素武器底部暖橙红下边框
			if GameStyle.is_elemental(w_wid):
				GameStyle.apply_elemental_bottom_bar(slot, true, 2.5)

			# 星级
			GameStyle.star_label(slot, int(w.get("star", 1)), 11)

			GameStyle.tap(slot, func() -> void: dialog._open_weapon_tip(w, false, slot))
		else:
			var empty_dot := Label.new()
			empty_dot.text = "×" if locked else "·"
			empty_dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty_dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			GameStyle.label(empty_dot, 15, GameStyle.BAD if locked else GameStyle.PAPER_DIM)
			slot.add_child(empty_dot)
			GameStyle.tap(slot, func() -> void: dialog._open_empty_slot_tip(i, slot))

		dialog._weapons_box.add_child(slot)

	# 仓库武器
	var has_stash: bool = not GameManager.stash.is_empty()
	dialog._stash_section.visible = has_stash
	if has_stash:
		for i in range(GameManager.stash.size()):
			var item: Dictionary = GameManager.stash[i]
			var def: Dictionary = WeaponData.get_def(item.get("id", ""))
			var s_slot := PanelContainer.new()
			s_slot.custom_minimum_size = Vector2(36, 36)
			# 元素件 = 暖橙红描边（与上阵件/商店同一口径；36 见方的格子上，原先那枚角标会把图标整个盖住）
			var s_sb := GameStyle.outlined_panel(GameStyle.NAVY2,
					GameStyle.element_border(String(item.get("id", "")), GameStyle.LINE), 1, 0.0)
			s_slot.add_theme_stylebox_override("panel", s_sb)

			var s_wid := String(item.get("id", ""))
			var s_icon_path: String = item.get("icon", def.get("icon", ""))
			var s_tex := GameStyle.icon_texture_rect(s_icon_path, Vector2(26, 26))
			s_slot.add_child(s_tex)
			s_slot.set_meta("sb_flat", s_sb)
			s_slot.set_meta("sb_on", GameStyle.outlined_panel(GameStyle.NAVY2, GameStyle.JADE, 1, 0.0))

			# 元素武器底部暖橙红下边框
			if GameStyle.is_elemental(s_wid):
				GameStyle.apply_elemental_bottom_bar(s_slot, true, 2.0)

			# 补星级
			GameStyle.star_label(s_slot, int(item.get("star", 1)), 10)

			if not def.is_empty():
				s_slot.mouse_filter = Control.MOUSE_FILTER_STOP
				GameStyle.tap(s_slot, func() -> void: dialog._open_weapon_tip(item, true, s_slot))
			dialog._stash_box.add_child(s_slot)
