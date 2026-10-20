class_name StatsPanelBuilder
extends RefCounted

## 属性面板左栏构建：主要/次要属性 Tab、常驻生命条、25 项属性行与分组块（攻击/生存/机动…）。
## 从 PlayerStatsDialog 拆出：构建结果直接写回 dialog 成员（refresh 按原名刷新），
## 点按回调经 dialog 门面（_open_stat_tip / _switch_stat_tab）。

static func build_left_panel(dialog: PlayerStatsDialog) -> Control:
	var left_panel := PanelContainer.new()
	left_panel.custom_minimum_size = Vector2(296, 0)
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb := GameStyle.outlined_panel(GameStyle.NAVY2, GameStyle.INK, 2, 0.0)
	sb.content_margin_left = 10.0
	sb.content_margin_top = 8.0
	sb.content_margin_right = 10.0
	sb.content_margin_bottom = 8.0
	left_panel.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	left_panel.add_child(vbox)

	# 顶部：属性标题 + 【主要 / 次要】Tab 切换
	var tab_bar := HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 6)
	vbox.add_child(tab_bar)

	var sec_title := Label.new()
	sec_title.text = "◆ 属 性"
	GameStyle.label(sec_title, 15, GameStyle.JADE_DK)
	sec_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_bar.add_child(sec_title)

	dialog._stat_tab_primary_btn = Button.new()
	dialog._stat_tab_primary_btn.text = "主 要"
	dialog._stat_tab_primary_btn.custom_minimum_size = Vector2(76, 26)
	dialog._stat_tab_primary_btn.focus_mode = Control.FOCUS_NONE
	dialog._stat_tab_primary_btn.pressed.connect(func(): dialog._switch_stat_tab(0))
	tab_bar.add_child(dialog._stat_tab_primary_btn)

	dialog._stat_tab_secondary_btn = Button.new()
	dialog._stat_tab_secondary_btn.text = "次 要"
	dialog._stat_tab_secondary_btn.custom_minimum_size = Vector2(76, 26)
	dialog._stat_tab_secondary_btn.focus_mode = Control.FOCUS_NONE
	dialog._stat_tab_secondary_btn.pressed.connect(func(): dialog._switch_stat_tab(1))
	tab_bar.add_child(dialog._stat_tab_secondary_btn)

	# 常驻生命条（整行可点）
	var hp_box := HBoxContainer.new()
	hp_box.add_theme_constant_override("separation", 6)
	var hp_title := Label.new()
	hp_title.text = StatInfoData.title("hp")
	GameStyle.label(hp_title, 12, GameStyle.PAPER)
	hp_box.add_child(hp_title)

	dialog._hp_bar = ProgressBar.new()
	dialog._hp_bar.custom_minimum_size = Vector2(105, 13)
	dialog._hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialog._hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dialog._hp_bar.show_percentage = false
	# 纯显示件也要让开「按下」那一拍：ProgressBar 的 mouse_filter 默认是 STOP，它自己不处理
	# 输入却照样把事件吃掉 → 生命值那一整行里最显眼的血条成了死点（点名字弹卡、点血条没反应）。
	dialog._hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar_st := GameStyle.bar_styles(GameStyle.NAVY2.darkened(0.08), GameStyle.GOOD)
	dialog._hp_bar.add_theme_stylebox_override("background", bar_st[0])
	dialog._hp_bar.add_theme_stylebox_override("fill", bar_st[1])
	hp_box.add_child(dialog._hp_bar)

	dialog._hp_val_lbl = Label.new()
	GameStyle.label(dialog._hp_val_lbl, 12, GameStyle.GOOD_DK)
	hp_box.add_child(dialog._hp_val_lbl)
	vbox.add_child(make_tip_row(dialog, "hp", hp_box))

	var sep1 := HSeparator.new()
	sep1.add_theme_stylebox_override("separator", _create_line_style(GameStyle.LINE))
	vbox.add_child(sep1)

	# 主要属性页（15 行，加上顶端常驻生命共 16 项）——按 攻击/生存/机动 分三块
	dialog._primary_stats_box = VBoxContainer.new()
	dialog._primary_stats_box.add_theme_constant_override("separation", 2)
	dialog._primary_stats_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(dialog._primary_stats_box)

	var atk_block := add_stat_block(dialog._primary_stats_box, "攻 击")
	dialog._atk_val_lbl = add_stat_row(dialog, atk_block, "damage", "+0%")
	dialog._melee_val_lbl = add_stat_row(dialog, atk_block, "melee_dmg", "0")
	dialog._ranged_val_lbl = add_stat_row(dialog, atk_block, "ranged_dmg", "0")
	dialog._elem_val_lbl = add_stat_row(dialog, atk_block, "elemental_dmg", "0")
	dialog._eng_val_lbl = add_stat_row(dialog, atk_block, "engineering_dmg", "0")
	dialog._contraption_val_lbl = add_stat_row(dialog, atk_block, "contraption_dmg", "0")
	dialog._crit_val_lbl = add_stat_row(dialog, atk_block, "crit", "5% (1.5×)")
	dialog._range_val_lbl = add_stat_row(dialog, atk_block, "range", "+0%")

	var sur_block := add_stat_block(dialog._primary_stats_box, "生 存")
	dialog._regen_val_lbl = add_stat_row(dialog, sur_block, "regen", "+0.0 / 秒")
	dialog._lifesteal_val_lbl = add_stat_row(dialog, sur_block, "lifesteal", "0% 概率")
	dialog._armor_val_lbl = add_stat_row(dialog, sur_block, "armor", "0 (0%)")
	dialog._dodge_val_lbl = add_stat_row(dialog, sur_block, "dodge", "0%")

	var util_block := add_stat_block(dialog._primary_stats_box, "机 动")
	dialog._haste_val_lbl = add_stat_row(dialog, util_block, "haste", "0.0%")
	dialog._speed_val_lbl = add_stat_row(dialog, util_block, "speed", "210 (+0%)")
	dialog._luck_val_lbl = add_stat_row(dialog, util_block, "luck", "0")
	dialog._harvest_val_lbl = add_stat_row(dialog, util_block, "harvest", "0")

	# 次要属性页（9 行）——按 战斗/成长/经营 分三块
	dialog._secondary_stats_box = VBoxContainer.new()
	dialog._secondary_stats_box.add_theme_constant_override("separation", 2)
	dialog._secondary_stats_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(dialog._secondary_stats_box)

	var sec_combat := add_stat_block(dialog._secondary_stats_box, "战 斗")
	dialog._elite_dmg_val_lbl = add_stat_row(dialog, sec_combat, "elite_dmg", "+0%")
	dialog._knockback_val_lbl = add_stat_row(dialog, sec_combat, "knockback", "+0%")
	dialog._pierce_val_lbl = add_stat_row(dialog, sec_combat, "bonus_pierce", "0")
	dialog._thorns_val_lbl = add_stat_row(dialog, sec_combat, "thorns", "0%")

	var sec_growth := add_stat_block(dialog._secondary_stats_box, "成 长")
	dialog._pickup_val_lbl = add_stat_row(dialog, sec_growth, "pickup", "96 (+0%)")
	dialog._xp_gain_val_lbl = add_stat_row(dialog, sec_growth, "xp_gain", "+0%")

	var sec_econ := add_stat_block(dialog._secondary_stats_box, "经 营")
	dialog._shop_price_val_lbl = add_stat_row(dialog, sec_econ, "shop_price", "+0%")
	dialog._free_rerolls_val_lbl = add_stat_row(dialog, sec_econ, "free_rerolls", "0 次")
	dialog._stones_val_lbl = add_stat_row(dialog, sec_econ, "stones", "0 枚")
	dialog._kills_val_lbl = add_stat_row(dialog, sec_econ, "kills", "0 杀")

	dialog._switch_stat_tab(0)
	return left_panel

## 属性行：名字来自 StatInfoData（面板与详解卡共用同一份标题，改一处就两处一起变）。
## 2026-10-11 土豆兄弟式口径：名字纸白左对齐、数值右对齐（零值灰由 refresh 的 _c_row 压暗）
static func add_stat_row(dialog: PlayerStatsDialog, parent: Container, stat_id: String, default_val: String) -> Label:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)

	var l_name := Label.new()
	l_name.text = StatInfoData.title(stat_id)
	l_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	GameStyle.label(l_name, 12, GameStyle.PAPER)
	hbox.add_child(l_name)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(spacer)

	var l_val := Label.new()
	l_val.text = default_val
	l_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	GameStyle.label(l_val, 12, GameStyle.PAPER)
	hbox.add_child(l_val)

	parent.add_child(make_tip_row(dialog, stat_id, hbox))
	return l_val

## 属性分块：一组同类属性包一个浅色凹槽块，头行小标签 + 行列表（攻击/生存/机动…）
static func add_stat_block(parent: Container, header_text: String) -> VBoxContainer:
	var block := PanelContainer.new()
	var bs := GameStyle.outlined_panel(GameStyle.NAVY2.darkened(0.04), GameStyle.LINE, 1, 0.0)
	# 上下内边距 2/3：分组块 ×3，这里每省 2px 就是面板总高 6px——
	# 内容最小高度必须压在 526 钳制值内（StatsTipCheck 的 9px 出屏边距判定），否则面板被撑高出屏。
	bs.content_margin_left = 8.0
	bs.content_margin_top = 2.0
	bs.content_margin_right = 8.0
	bs.content_margin_bottom = 3.0
	block.add_theme_stylebox_override("panel", bs)
	parent.add_child(block)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 1)
	block.add_child(inner)

	var head := Label.new()
	head.text = header_text
	GameStyle.label(head, 11, GameStyle.JADE_DK)
	inner.add_child(head)
	return inner

## 把一行内容包进可点的整行热区。
static func make_tip_row(dialog: PlayerStatsDialog, stat_id: String, content: Control) -> Control:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var flat := StyleBoxFlat.new()
	flat.draw_center = false
	flat.content_margin_top = 0.0
	flat.content_margin_bottom = 0.0
	var on := StyleBoxFlat.new()
	on.bg_color = GameStyle.with_alpha(GameStyle.GOLD, 0.22)
	GameStyle.register_theme_derived_box(on, &"bg_color", &"main", &"alpha", 0.22)
	on.content_margin_top = 0.0
	on.content_margin_bottom = 0.0
	row.add_theme_stylebox_override("panel", flat)
	row.set_meta("sb_flat", flat)
	row.set_meta("sb_on", on)
	row.set_meta("tip_title", StatInfoData.title(stat_id))
	GameStyle.tap(row, func() -> void: dialog._open_stat_tip(stat_id, row))
	row.add_child(content)
	return row

static func _create_line_style(color: Color) -> StyleBoxLine:
	var s := StyleBoxLine.new()
	s.color = color
	s.thickness = 1
	return s
