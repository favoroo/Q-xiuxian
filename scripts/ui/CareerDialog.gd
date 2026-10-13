class_name CareerDialog
extends BaseModalDialog

## 修仙志（生涯功绩簿）三页签：成就 / 角色 / 战斗记录
## 成就页：四分类（试炼/流派/历练/机缘）× 大色块方卡网格 —— 已达成 = 分类色实底块，未达成 = 墨底灰像
## 角色页：大色块角色卡（左头像色块 + 境界称号 chip + 六难度封印格），
##         封印按 GameManager.cultivator_danger_clears 位掩码点亮，境界按最高通关难度晋升
## 滚动区内的展开控件一律 PanelContainer + GameStyle.tap()（BaseButton 会吞滑动事件）
## 三页列表每次刷新都重建子树，所以重建末尾要重跑 GameStyle.swipeable()（见 _refresh_data 末尾）

# 顶部概览数据标签（5 卡）
var _runs_val_lbl: Label
var _wins_val_lbl: Label
var _kills_val_lbl: Label
var _wave_val_lbl: Label
var _ach_val_lbl: Label

# 各页列表容器
var _ach_list_box: VBoxContainer
var _cult_list_box: VBoxContainer
var _log_list_box: VBoxContainer
var _expanded_log_idx: int = -1  ## 渡劫实录当前展开的快照下标（-1 = 全部收起）

## 六难度封印格的单字（与 AchievementData.DANGER_NAMES 对位）
const SEAL_CHARS: Array[String] = ["简", "普", "困", "噩", "狱", "极"]

func _get_title_text() -> String:
	return "战 绩  ·  游 戏 记 录"

func _get_panel_size() -> Vector2:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0:
		vp = Vector2(960, 540)
	return Vector2(minf(880.0, vp.x - 48.0), minf(470.0, vp.y - 40.0))

func _get_panel_margins() -> Vector4:
	return Vector4(20, 14, 20, 14)

func _build_body(root_vbox: VBoxContainer) -> void:
	# 1. 注册顶部 Tab 按钮
	add_tab_button(0, "✦ 成就")
	add_tab_button(1, "✦ 角色")
	add_tab_button(2, "✦ 战斗记录")

	# 2. 生涯核心数据横条（5 个指标卡）
	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 8)
	root_vbox.add_child(stats_row)

	_runs_val_lbl = _add_summary_card(stats_row, "游戏局数", "0 局")
	_wins_val_lbl = _add_summary_card(stats_row, "通关", "0 胜")
	_kills_val_lbl = _add_summary_card(stats_row, "累计击杀", "0 只")
	_wave_val_lbl = _add_summary_card(stats_row, "最高波数", "第 0 波")
	_ach_val_lbl = _add_summary_card(stats_row, "成就", "0/0")

	# 3. 内容分页面板
	var content_panel := PanelContainer.new()
	content_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var cont_sb := GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 2, 0.0)
	cont_sb.content_margin_left = 14.0
	cont_sb.content_margin_top = 10.0
	cont_sb.content_margin_right = 14.0
	cont_sb.content_margin_bottom = 10.0
	content_panel.add_theme_stylebox_override("panel", cont_sb)
	root_vbox.add_child(content_panel)

	_pages.append(_build_achievements_page(content_panel))
	_pages.append(_build_cultivators_page(content_panel))
	_pages.append(_build_victory_log_page(content_panel))

	switch_tab(0)

func _on_opened() -> void:
	_expanded_log_idx = -1
	_refresh_data()

func _add_summary_card(parent: HBoxContainer, title: String, init_val: String) -> Label:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := GameStyle.block(GameStyle.NAVY2, GameStyle.SLANT_PLATE, Vector2(2, 3))
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	card.add_theme_stylebox_override("panel", sb)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 5)
	card.add_child(hbox)

	var t_lbl := Label.new()
	t_lbl.text = title
	GameStyle.label(t_lbl, 11, GameStyle.GREY)
	hbox.add_child(t_lbl)

	var v_lbl := Label.new()
	v_lbl.text = init_val
	v_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	GameStyle.label(v_lbl, 13, GameStyle.JADE)
	hbox.add_child(v_lbl)

	parent.add_child(card)
	return v_lbl

# ----------------- 分页 1：成就（分类大色块卡） -----------------

func _build_achievements_page(parent: Control) -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)

	_ach_list_box = VBoxContainer.new()
	_ach_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ach_list_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_ach_list_box)
	return scroll

# ----------------- 分页 2：角色（大色块卡 + 六难度封印） -----------------

func _build_cultivators_page(parent: Control) -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)

	_cult_list_box = VBoxContainer.new()
	_cult_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cult_list_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_cult_list_box)
	return scroll

# ----------------- 分页 3：渡劫实录（战报快照 + 近期历战） -----------------

func _build_victory_log_page(parent: Control) -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)

	_log_list_box = VBoxContainer.new()
	_log_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_list_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_log_list_box)
	return scroll


func _refresh_data() -> void:
	# 1. 刷新顶部生涯概览
	var cs := GameManager.career_stats
	var runs := int(cs.get("total_runs", 0))
	var wins := int(cs.get("total_wins", 0))
	var kills := int(cs.get("total_kills", 0))
	var b_wave := int(cs.get("best_wave", 0))
	var win_rate := (float(wins) / float(runs) * 100.0) if runs > 0 else 0.0

	_runs_val_lbl.text = "%d 局" % runs
	_wins_val_lbl.text = "%d 胜 (%.0f%%)" % [wins, win_rate]
	_kills_val_lbl.text = "%d 只" % kills
	_wave_val_lbl.text = "第 %d 波" % b_wave
	_ach_val_lbl.text = "%d/%d" % [GameManager.unlocked_achievements.size(), AchievementData.ACHIEVEMENTS.size()]

	# 2. 重建成就页（分类分节 + 3 列卡网格）
	for c in _ach_list_box.get_children():
		c.queue_free()
	for cat in AchievementData.CATEGORY_ORDER:
		var defs: Array = AchievementData.ACHIEVEMENTS.filter(
			func(a: Dictionary) -> bool: return String(a.get("category", "")) == cat)
		if defs.is_empty():
			continue
		var done := 0
		for a in defs:
			if GameManager.is_achievement_unlocked(String(a.get("id", ""))):
				done += 1
		_ach_list_box.add_child(_section_header("✦ %s · %d/%d" % [
			String(AchievementData.CATEGORY_NAMES.get(cat, cat)), done, defs.size()],
			_category_color(cat)))
		var grid := GridContainer.new()
		grid.columns = 3
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		for a in defs:
			grid.add_child(_create_achievement_card(a))
		_ach_list_box.add_child(grid)
		_ach_list_box.add_child(_spacer(4))

	# 3. 重建角色页（2 列大卡网格）
	for c in _cult_list_box.get_children():
		c.queue_free()
	var unlocked_n := 0
	for cid in CultivatorData.DEFS.keys():
		if GameManager.is_cultivator_unlocked(String(cid)):
			unlocked_n += 1
	_cult_list_box.add_child(_section_header("✦ 角色 · 已解锁 %d/%d · 通关对应难度即可点亮该档封印" % [
		unlocked_n, CultivatorData.DEFS.size()], GameStyle.GOLD))
	var cgrid := GridContainer.new()
	cgrid.columns = 2
	cgrid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cgrid.add_theme_constant_override("h_separation", 8)
	cgrid.add_theme_constant_override("v_separation", 8)
	for cid in CultivatorData.DEFS.keys():
		cgrid.add_child(_create_cultivator_card(String(cid)))
	_cult_list_box.add_child(cgrid)

	# 4. 刷新渡劫实录列表
	_rebuild_log_list()

	# 5. 三页整棵子树放开「按下」冒泡：卡片是 PanelContainer（mouse_filter 默认 STOP），
	#    会把外层 ScrollContainer 起手锁定手指拖动要的那一拍就地吃掉 —— 卡片盖住多大面积
	#    就滑不动多大面积，只有卡片缝隙能划（用户 2026-10-10 真机：「只有手碰到
	#    黑色间隔才能滑动」）。列表每次刷新都重建，所以在这里补刷，不在 _build_body 里补。
	for p in _pages:
		GameStyle.swipeable(p as Control)

func _fmt_time(t: float) -> String:
	return "%02d:%02d" % [int(t / 60.0), int(t) % 60]

## 成就分类色（试炼朱砂 / 流派主蓝 / 历练增益绿 / 机缘点缀黄）
func _category_color(cat: String) -> Color:
	match cat:
		"trial":
			return GameStyle.BAD
		"style":
			return GameStyle.GOLD
		"grind":
			return GameStyle.GOOD
		_:
			return GameStyle.JADE

## 难度档色（封印格与境界 chip 共用：难度越高色越烈）
func _danger_color(d: int) -> Color:
	match d:
		0:
			return GameStyle.GOOD
		1:
			return GameStyle.GOLD
		2:
			return GameStyle.JADE
		3:
			return GameStyle.ELEMENT
		4:
			return GameStyle.BAD
		_:
			return GameStyle.RARITY_LEGEND

## 小节标题条
func _section_header(text: String, color: Color = GameStyle.GOLD) -> Control:
	var lbl := Label.new()
	lbl.text = text
	GameStyle.label(lbl, 13, color, 0, GameStyle.INK, true)
	return lbl

# ----------------- 成就大色块卡 -----------------

func _create_achievement_card(adef: Dictionary) -> Control:
	var aid := String(adef.get("id", ""))
	var is_done: bool = GameManager.is_achievement_unlocked(aid)
	var cat := String(adef.get("category", "luck"))
	var cat_col := _category_color(cat)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(240, 128)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 已达成 = 分类色实底大色块（奖章）；未达成 = 墨底灰线描边
	var sb: StyleBoxFlat
	if is_done:
		sb = GameStyle.block(cat_col, GameStyle.SLANT_BLOCK, Vector2(2, 3))
	else:
		sb = GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 1, GameStyle.SLANT_BLOCK)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	card.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	# 顶行：图标 + 状态签
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	vbox.add_child(top)

	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(40, 40)
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_box.add_theme_stylebox_override("panel",
		GameStyle.outlined_panel(GameStyle.INK, cat_col.darkened(0.55) if is_done else GameStyle.LINE, 1, 0.0))
	var icon_tex := TextureRect.new()
	if ResourceLoader.exists(String(adef.get("icon", ""))):
		icon_tex.texture = load(String(adef["icon"]))
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.custom_minimum_size = Vector2(32, 32)
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if not is_done:
		icon_tex.modulate = GameStyle.disabled_modulate()
	icon_box.add_child(icon_tex)
	top.add_child(icon_box)

	var status_lbl := Label.new()
	status_lbl.text = " 已达成 " if is_done else " 未达成 "
	status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.INK if is_done else GameStyle.LINE))
	# 已达成：黑签配分类色字（色块卡上再压一块亮签会糊）；未达成：灰签灰字
	GameStyle.label(status_lbl, 11, cat_col if is_done else GameStyle.GREY)
	top.add_child(status_lbl)

	# 成就名
	var name_lbl := Label.new()
	name_lbl.text = String(adef.get("name", "未命名成就"))
	GameStyle.label(name_lbl, 14, GameStyle.INK_TEXT if is_done else GameStyle.PAPER, 0, GameStyle.INK, true)
	vbox.add_child(name_lbl)

	# 达成条件（硬换行，最多 2 行，全文进 DetailTip）
	var cond_lbl := Label.new()
	cond_lbl.text = _wrap2(String(adef.get("cond_desc", "")), 218.0)
	cond_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	GameStyle.label(cond_lbl, 11,
		GameStyle.with_alpha(GameStyle.INK_TEXT, 0.75) if is_done else GameStyle.PAPER_DIM)
	vbox.add_child(cond_lbl)

	# 奖励签
	var reward_lbl := Label.new()
	var rtype := String(adef.get("reward_type", ""))
	if rtype == "cultivator":
		reward_lbl.text = " 解锁角色：%s " % String(adef.get("reward_name", ""))
	elif rtype == "item":
		reward_lbl.text = " 解锁道具：%s " % String(adef.get("reward_name", ""))
	else:
		reward_lbl.text = " 荣誉 "
	reward_lbl.add_theme_stylebox_override("normal",
		GameStyle.chip(GameStyle.INK if is_done else GameStyle.NAVY2))
	GameStyle.label(reward_lbl, 10, GameStyle.CHALK if is_done else GameStyle.PAPER_DIM)
	vbox.add_child(reward_lbl)

	# 卡面点按 → 「这是什么」详情
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	GameStyle.tap(card, func() -> void: _open_achievement_tip(adef, card))
	return card

## 条件文案硬换行并截到 2 行（卡片高有限，全文走点按详情）
func _wrap2(text: String, max_w: float) -> String:
	var wrapped := GameStyle.wrap_cjk(text, GameStyle.body_font(), 11, max_w)
	var lines := wrapped.split("\n")
	if lines.size() <= 2:
		return wrapped
	var cut := lines[1]
	if cut.length() > 0:
		cut = cut.substr(0, cut.length() - 1) + "…"
	return lines[0] + "\n" + cut

## 成就卡点按详情
func _open_achievement_tip(adef: Dictionary, anchor: Control) -> void:
	var is_done: bool = GameManager.is_achievement_unlocked(String(adef.get("id", "")))
	var cat := String(adef.get("category", "luck"))
	var rtype := String(adef.get("reward_type", ""))
	var reward_txt := "纯荣誉纪念"
	if rtype == "cultivator":
		reward_txt = "解锁角色：%s" % String(adef.get("reward_name", ""))
	elif rtype == "item":
		reward_txt = "解锁道具：%s" % String(adef.get("reward_name", ""))
	DetailTip.show_over(self, anchor, {
		"title": String(adef.get("name", "成就")),
		"chip": String(AchievementData.CATEGORY_NAMES.get(cat, cat)),
		"chip_color": _category_color(cat),
		"rows": [
			["状态", "已达成" if is_done else "未达成", GameStyle.GOOD if is_done else GameStyle.GREY],
			["奖励", reward_txt, GameStyle.JADE],
		],
		"body": String(adef.get("cond_desc", "")),
		"foot": "成就只作记录与解锁，不提供局内数值加成。",
	})

# ----------------- 角色大色块卡（境界 + 六难度封印） -----------------

func _create_cultivator_card(cid: String) -> Control:
	var unlocked: bool = GameManager.is_cultivator_unlocked(cid)
	var rec := GameManager.get_cultivator_record(cid)
	var wins := int(rec["wins"])
	var best_danger := GameManager.get_cultivator_best_danger(cid)
	var mask := GameManager.get_cultivator_danger_mask(cid)
	var has_realm := unlocked and best_danger >= 0
	var realm_col := _danger_color(best_danger) if has_realm else GameStyle.LINE

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(380, 116)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 卡框即境界色：通关过的角色一眼能看出打到了什么高度
	var sb := GameStyle.outlined_panel(GameStyle.INK, realm_col if has_realm else GameStyle.LINE, 2, GameStyle.SLANT_BLOCK)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	card.add_theme_stylebox_override("panel", sb)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	card.add_child(hbox)

	# 左侧头像大色块：有境界 = 境界色实底，未通关/未解锁 = 墨底
	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(84, 84)
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if has_realm:
		icon_box.add_theme_stylebox_override("panel", GameStyle.block(realm_col, 0.0, Vector2(2, 3)))
	else:
		icon_box.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 1, 0.0))
	var cdef := CultivatorData.get_def(cid)
	var icon_tex := TextureRect.new()
	if ResourceLoader.exists(String(cdef.get("icon", ""))):
		icon_tex.texture = load(String(cdef["icon"]))
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.custom_minimum_size = Vector2(72, 72)
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if not unlocked:
		icon_tex.modulate = GameStyle.disabled_modulate()
	icon_box.add_child(icon_tex)
	hbox.add_child(icon_box)

	# 右侧信息列
	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 4)
	hbox.add_child(text_col)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	text_col.add_child(name_row)

	var name_lbl := Label.new()
	name_lbl.text = String(cdef.get("name", "未知角色"))
	GameStyle.label(name_lbl, 15, GameStyle.PAPER if unlocked else GameStyle.PAPER_DIM, 0, GameStyle.INK, true)
	name_row.add_child(name_lbl)

	var realm_lbl := Label.new()
	if not unlocked:
		realm_lbl.text = " 未解锁 "
		realm_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.LINE))
		GameStyle.label(realm_lbl, 11, GameStyle.GREY)
	elif has_realm:
		realm_lbl.text = " %s " % AchievementData.realm_for_danger(best_danger)
		realm_lbl.add_theme_stylebox_override("normal", GameStyle.chip(realm_col))
		GameStyle.label(realm_lbl, 11, GameStyle.INK_TEXT)
	else:
		realm_lbl.text = " 未通关 "
		realm_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.NAVY2))
		GameStyle.label(realm_lbl, 11, GameStyle.PAPER_DIM)
	realm_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(realm_lbl)

	# 六难度封印格：通关过该档即点亮（未解锁角色全灭）
	var seals := HBoxContainer.new()
	seals.add_theme_constant_override("separation", 4)
	seals.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_col.add_child(seals)
	for d in range(SEAL_CHARS.size()):
		var lit := unlocked and (mask & (1 << d)) != 0
		var seal := Label.new()
		seal.text = SEAL_CHARS[d]
		seal.custom_minimum_size = Vector2(24, 24)
		seal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		seal.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if lit:
			seal.add_theme_stylebox_override("normal", GameStyle.panel(_danger_color(d), 0.0, Vector2.ZERO))
			GameStyle.label(seal, 11, GameStyle.INK_TEXT)
		else:
			seal.add_theme_stylebox_override("normal", GameStyle.slot())
			GameStyle.label(seal, 11, GameStyle.GREY)
		seals.add_child(seal)
	# 封印格图例
	var legend := Label.new()
	legend.text = " 简→极"
	legend.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	GameStyle.label(legend, 10, GameStyle.GREY)
	seals.add_child(legend)

	# 生涯摘要行
	var detail_lbl := Label.new()
	if not unlocked:
		var adef := AchievementData.cultivator_unlock_achievement(cid)
		var aname := String(adef.get("name", ""))
		detail_lbl.text = "达成成就「%s」后解锁" % aname if aname != "" else AchievementData.NO_UNLOCK_HINT
		GameStyle.label(detail_lbl, 11, GameStyle.GREY)
	else:
		var endless_txt := "无尽第 %d 波" % int(rec["endless_best_wave"]) if int(rec["endless_best_wave"]) > 0 else "无尽未达"
		detail_lbl.text = "通关 %d 次 · %s · 最高击杀 %d" % [wins, endless_txt, int(rec["best_kills"])]
		GameStyle.label(detail_lbl, 11, GameStyle.PAPER_DIM)
	text_col.add_child(detail_lbl)

	# 卡面点按 → 「这是什么」详情（生涯档案 / 解锁条件）
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	GameStyle.tap(card, func() -> void: _open_cultivator_tip(cid, card))
	return card

## 角色卡点按详情：已解锁看生涯档案与封印进度，未解锁看达成条件
func _open_cultivator_tip(cid: String, anchor: Control) -> void:
	var cdef := CultivatorData.get_def(cid)
	var cname := String(cdef.get("name", "未知角色"))
	if not GameManager.is_cultivator_unlocked(cid):
		var adef := AchievementData.cultivator_unlock_achievement(cid)
		var cond := String(adef.get("cond_desc", "达成对应成就后解锁"))
		var rname := String(adef.get("name", ""))
		DetailTip.show_over(self, anchor, {
			"title": "%s · 未解锁" % cname,
			"chip": "锁定",
			"chip_color": GameStyle.LINE,
			"rows": [["解锁条件", rname if rname != "" else "——", GameStyle.PAPER]],
			"body": cond,
			"foot": "达成后自动解锁，届时在此显示该角色的记录。",
		})
		return
	var rec := GameManager.get_cultivator_record(cid)
	var wins := int(rec["wins"])
	var best_danger := GameManager.get_cultivator_best_danger(cid)
	var mask := GameManager.get_cultivator_danger_mask(cid)
	var lit_n := 0
	for d in range(SEAL_CHARS.size()):
		if (mask & (1 << d)) != 0:
			lit_n += 1
	var rows: Array = [
		["游戏局数", "%d 局" % int(rec["runs"]), GameStyle.PAPER],
		["通关", "%d 次" % wins, GameStyle.JADE],
		["难度封印", "已点亮 %d/%d" % [lit_n, SEAL_CHARS.size()], GameStyle.GOLD],
		["无尽最高", ("第 %d 波" % int(rec["endless_best_wave"])) if int(rec["endless_best_wave"]) > 0 else "未入无尽", GameStyle.PAPER],
		["最高击杀", "%d 只" % int(rec["best_kills"]), GameStyle.PAPER],
		["最高难度", AchievementData.danger_name(best_danger) if best_danger >= 0 else "未通关", GameStyle.GOLD],
	]
	DetailTip.show_over(self, anchor, {
		"title": "%s · 角色记录" % cname,
		"chip": "档案",
		"chip_color": GameStyle.JADE,
		"rows": rows,
		"body": "境界「%s」" % AchievementData.realm_for_danger(best_danger) if best_danger >= 0 else "尚未通关，未入境界",
		"foot": "通关对应难度即点亮该档封印；境界按通关过的最高难度晋升，仅作记录、不发奖励。",
	})

# ----------------- 渡劫实录行 -----------------

func _rebuild_log_list() -> void:
	for c in _log_list_box.get_children():
		c.queue_free()

	_log_list_box.add_child(_section_header("✦ 通关记录 · 共 %d 次" % GameManager.victory_log.size()))
	if GameManager.victory_log.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "暂无通关记录 · 完成 20 波即可记录"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		GameStyle.label(empty_lbl, 13, GameStyle.GREY)
		_log_list_box.add_child(empty_lbl)
	else:
		for i in range(GameManager.victory_log.size()):
			_log_list_box.add_child(_create_log_row(GameManager.victory_log[i], i))

	_log_list_box.add_child(_spacer(6))
	_log_list_box.add_child(_section_header("✦ 最近游戏 · 最近 %d 局" % GameManager.run_history.size()))
	if GameManager.run_history.is_empty():
		var empty2 := Label.new()
		empty2.text = "暂无记录 · 开始游戏即可记录"
		empty2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		GameStyle.label(empty2, 13, GameStyle.GREY)
		_log_list_box.add_child(empty2)
	else:
		for entry in GameManager.run_history:
			_log_list_box.add_child(_create_history_row(entry))

	# 展开/收起战报只重建本列（不走 _refresh_data），新挂的详情面板同样是 STOP 卡片
	GameStyle.swipeable(_log_list_box)

func _spacer(h: float) -> Control:
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, h)
	return sp

func _create_log_row(snap: Dictionary, idx: int) -> Control:
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 4)

	var expanded := idx == _expanded_log_idx

	# —— 头行（点击展开/收起）——
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := GameStyle.side_card(GameStyle.GOLD, 0.0)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	row.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	row.add_child(hbox)

	# 日期（"2026-10-10T12:34:56" → "10-10 12:34"）
	var dt := String(snap.get("datetime", ""))
	var date_txt := dt.substr(5, 11).replace("T", " ") if dt.length() >= 16 else "——"
	var date_lbl := Label.new()
	date_lbl.text = date_txt
	GameStyle.label(date_lbl, 11, GameStyle.GREY)
	hbox.add_child(date_lbl)

	var cid := String(snap.get("cultivator_id", "jianchi"))
	var cdef := CultivatorData.get_def(cid)
	var dname := AchievementData.danger_name(int(snap.get("danger", 0)))
	var c_lbl := Label.new()
	c_lbl.text = "%s「%s」" % [String(cdef.get("name", "角色")), dname]
	GameStyle.label(c_lbl, 13, GameStyle.PAPER, 0, GameStyle.INK, true)
	hbox.add_child(c_lbl)

	var detail_lbl := Label.new()
	detail_lbl.text = "第 %d 波 · 击杀 %d · Lv.%d · %s" % [
		int(snap.get("wave", 0)), int(snap.get("kills", 0)), int(snap.get("level", 1)), _fmt_time(float(snap.get("time", 0.0))),
	]
	detail_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	GameStyle.label(detail_lbl, 12, GameStyle.PAPER_DIM)
	hbox.add_child(detail_lbl)

	var v_tag := Label.new()
	v_tag.text = " 通关 %s " % ("▲" if expanded else "◆")
	v_tag.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.GOLD))
	GameStyle.label(v_tag, 11, GameStyle.INK_TEXT)
	hbox.add_child(v_tag)

	GameStyle.tap(row, func() -> void:
		_expanded_log_idx = idx if not expanded else -1
		_rebuild_log_list()
	)
	root.add_child(row)

	# —— 展开详情（仅当前展开行）——
	if not expanded:
		return root

	var detail := PanelContainer.new()
	var d_sb := GameStyle.outlined_panel(GameStyle.NAVY, GameStyle.LINE, 1, 0.0)
	d_sb.content_margin_left = 12.0
	d_sb.content_margin_right = 12.0
	d_sb.content_margin_top = 8.0
	d_sb.content_margin_bottom = 8.0
	detail.add_theme_stylebox_override("panel", d_sb)
	var d_vbox := VBoxContainer.new()
	d_vbox.add_theme_constant_override("separation", 6)
	detail.add_child(d_vbox)

	# 上阵武器
	var weapons: Array = snap.get("weapons", [])
	d_vbox.add_child(_kit_section("装备武器", weapons, false))
	# 道具
	var items: Array = snap.get("items", [])
	d_vbox.add_child(_kit_section("携带道具", items, true))
	# 关键属性
	d_vbox.add_child(_stats_grid(snap))

	root.add_child(detail)
	return root

## 装备小节：一排图标槽（点按出「这是什么」详情）
func _kit_section(section_name: String, kit: Array, is_item: bool) -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 4)

	var head := Label.new()
	head.text = "· %s（%d）" % [section_name, kit.size()]
	GameStyle.label(head, 11, GameStyle.GREY)
	wrap.add_child(head)

	if kit.is_empty():
		var none := Label.new()
		none.text = "空空如也"
		GameStyle.label(none, 11, GameStyle.PAPER_DIM)
		wrap.add_child(none)
		return wrap

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	wrap.add_child(row)
	for w in kit:
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(40, 40)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 1, 0.0))
		var tex_rect := TextureRect.new()
		if ResourceLoader.exists(String(w.get("icon", ""))):
			tex_rect.texture = load(String(w["icon"]))
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.custom_minimum_size = Vector2(32, 32)
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(tex_rect)
		if not is_item:
			GameStyle.star_label(slot, int(w.get("star", 1)), 10)
		GameStyle.tap(slot, func() -> void: _open_kit_tip(w, is_item, slot))
		row.add_child(slot)
	return wrap

## 装备详情弹卡（快照只存了名称/星级等纯数据，按类型给简版详情）
func _open_kit_tip(kit: Dictionary, is_item: bool, anchor: Control) -> void:
	var kit_name := String(kit.get("name", "——"))
	if is_item:
		DetailTip.show_over(self, anchor, {
			"title": kit_name,
			"chip": "道具",
			"chip_color": GameStyle.GOLD,
			"rows": [["类型", "携带的被动道具", GameStyle.PAPER]],
			"body": "通关当局购买并持有的道具。",
			"foot": "道具买即生效、整局持有，详情可在图鉴查阅。",
		})
	else:
		var star := int(kit.get("star", 1))
		DetailTip.show_over(self, anchor, {
			"title": kit_name,
			"chip": "武器",
			"chip_color": GameStyle.JADE,
			"rows": [["星级", "★%d" % star, GameStyle.JADE]],
			"body": "通关当局装备的武器（含召唤武器）。",
			"foot": "护蝶为环绕型召唤武器，其余为自动攻击的武器。",
		})

## 关键属性 4 列网格（境界取快照根字段，其余取 stats 子字典）
func _stats_grid(snap: Dictionary) -> Control:
	var stats: Dictionary = snap.get("stats", {})
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 2)
	var dodge := float(stats.get("dodge", 0.0))
	var crit := float(stats.get("crit_rate", 0.0))
	var cells: Array = [
		["等级", "Lv.%d" % int(snap.get("level", 1))],
		["最大生命", "%.0f" % float(stats.get("hp_max", 0.0))],
		["护甲", "%.0f" % float(stats.get("armor", 0.0))],
		["闪避", "%.0f%%" % (dodge * 100.0)],
		["暴击率", "%.0f%%" % (crit * 100.0)],
		["收益", "%.0f" % float(stats.get("harvest", 0.0))],
		["幸运", "%.0f" % float(stats.get("luck", 0.0))],
		["持有金币", "%d" % int(stats.get("stones", 0))],
	]
	for c in cells:
		var k_lbl := Label.new()
		k_lbl.text = "%s " % String(c[0])
		GameStyle.label(k_lbl, 11, GameStyle.GREY)
		grid.add_child(k_lbl)
		var v_lbl := Label.new()
		v_lbl.text = String(c[1])
		GameStyle.label(v_lbl, 12, GameStyle.PAPER)
		grid.add_child(v_lbl)
	return grid

# ----------------- 近期历战紧凑行 -----------------

func _create_history_row(entry: Dictionary) -> Control:
	var row := PanelContainer.new()
	var is_vic := bool(entry.get("victory", false))
	var is_endless := bool(entry.get("endless", false))
	var style := GameStyle.side_card(GameStyle.GOLD if is_vic else GameStyle.BAD, 0.0)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	row.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	row.add_child(hbox)

	var cid := String(entry.get("cultivator_id", "jianchi"))
	var cdef := CultivatorData.get_def(cid)
	var cname := String(cdef.get("name", "角色"))
	var dname := AchievementData.danger_name(int(entry.get("danger", 0)))

	var c_lbl := Label.new()
	c_lbl.text = "%s「%s」" % [cname, dname]
	GameStyle.label(c_lbl, 13, GameStyle.PAPER, 0, GameStyle.INK, true)
	hbox.add_child(c_lbl)

	var wave := int(entry.get("wave", 1))
	var kills := int(entry.get("kills", 0))
	var lvl := int(entry.get("level", 1))
	var dur := float(entry.get("time", 0.0))

	var detail_lbl := Label.new()
	detail_lbl.text = "抵达第 %d 波 · 击杀 %d 只 · 等级 Lv.%d · 耗时 %s" % [wave, kills, lvl, _fmt_time(dur)]
	detail_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	GameStyle.label(detail_lbl, 12, GameStyle.PAPER_DIM)
	hbox.add_child(detail_lbl)

	var v_tag := Label.new()
	if is_vic:
		v_tag.text = " 通关 "
	elif is_endless:
		v_tag.text = " 无尽结束 "
	else:
		v_tag.text = " 阵亡 "
	v_tag.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.GOLD if is_vic else GameStyle.BAD_DK))
	# 朱砂暗徽章配暗底亮字（BAD 压 BAD_DK 会糊）
	GameStyle.label(v_tag, 11, GameStyle.PAPER if is_vic else GameStyle.CHALK)
	hbox.add_child(v_tag)

	return row
