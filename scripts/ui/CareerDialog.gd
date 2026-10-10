class_name CareerDialog
extends BaseModalDialog

## 修仙志（生涯功绩簿）三页签：天道功绩 / 道统功名 / 渡劫实录
## 道统功名：每角色渡劫成功次数、无尽最高波数、最高危险度、称号里程碑与灵石囊领取
## 渡劫实录：每次渡劫成功的完整战报快照（上阵法器/法宝/关键属性），点击行展开回看
## 滚动区内的领取/展开控件一律 PanelContainer + GameStyle.tap()（BaseButton 会吞滑动事件）
## 三页列表每次刷新都重建子树，所以重建末尾要重跑 GameStyle.swipeable()（见 _refresh_data 第 5 步）

# 顶部概览数据标签（6 卡）
var _runs_val_lbl: Label
var _wins_val_lbl: Label
var _kills_val_lbl: Label
var _wave_val_lbl: Label
var _purse_val_lbl: Label
var _title_val_lbl: Label

# 各页列表容器
var _ach_list_box: VBoxContainer
var _cult_list_box: VBoxContainer
var _log_list_box: VBoxContainer
var _expanded_log_idx: int = -1  ## 渡劫实录当前展开的快照下标（-1 = 全部收起）

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

	# 2. 生涯核心数据横条（6 个指标卡）
	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 8)
	root_vbox.add_child(stats_row)

	_runs_val_lbl = _add_summary_card(stats_row, "游戏局数", "0 局")
	_wins_val_lbl = _add_summary_card(stats_row, "通关", "0 胜")
	_kills_val_lbl = _add_summary_card(stats_row, "累计击杀", "0 只")
	_wave_val_lbl = _add_summary_card(stats_row, "最高波数", "第 0 波")
	_purse_val_lbl = _add_summary_card(stats_row, "金币", "0")
	_title_val_lbl = _add_summary_card(stats_row, "已获称号", "0/0")

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

# ----------------- 分页 1：天道功绩列表 -----------------

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

# ----------------- 分页 2：道统功名（每角色档案 + 里程碑领取） -----------------

func _build_cultivators_page(parent: Control) -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)

	_cult_list_box = VBoxContainer.new()
	_cult_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cult_list_box.add_theme_constant_override("separation", 6)
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
	_purse_val_lbl.text = "%d 金币" % GameManager.stone_purse

	# 已获称号数：有渡劫成功的角色数 / 角色总数
	var total_c := CultivatorData.DEFS.size()
	var titled_c := 0
	for cid in CultivatorData.DEFS.keys():
		if AchievementData.title_for_wins(GameManager.get_cultivator_record(String(cid))["wins"]) != "":
			titled_c += 1
	_title_val_lbl.text = "%d/%d" % [titled_c, total_c]

	# 2. 刷新成就列表
	for c in _ach_list_box.get_children():
		c.queue_free()
	for a in AchievementData.ACHIEVEMENTS:
		_ach_list_box.add_child(_create_achievement_row(a))

	# 3. 刷新道统功名列表
	for c in _cult_list_box.get_children():
		c.queue_free()
	for cid in CultivatorData.DEFS.keys():
		_cult_list_box.add_child(_create_cultivator_row(String(cid)))

	# 4. 刷新渡劫实录列表
	_rebuild_log_list()

	# 5. 三页整棵子树放开「按下」冒泡：行卡是 PanelContainer（mouse_filter 默认 STOP），
	#    会把外层 ScrollContainer 起手锁定手指拖动要的那一拍就地吃掉 —— 卡片盖住多大面积
	#    就滑不动多大面积，只有卡片缝隙能划（用户 2026-10-10 真机：天道功绩簿「只有手碰到
	#    黑色间隔才能滑动」）。列表每次刷新都重建，所以在这里补刷，不在 _build_body 里补。
	for p in _pages:
		GameStyle.swipeable(p as Control)

func _fmt_time(t: float) -> String:
	return "%02d:%02d" % [int(t / 60.0), int(t) % 60]

## 小节标题条
func _section_header(text: String) -> Control:
	var lbl := Label.new()
	lbl.text = text
	GameStyle.label(lbl, 13, GameStyle.GOLD, 0, GameStyle.INK, true)
	return lbl

# ----------------- 天道功绩行 -----------------

func _create_achievement_row(adef: Dictionary) -> Control:
	var aid := String(adef.get("id", ""))
	var is_done: bool = GameManager.is_achievement_unlocked(aid)
	var row := PanelContainer.new()
	var style := GameStyle.side_card(GameStyle.JADE if is_done else GameStyle.LINE)
	if not is_done:
		style.bg_color = GameStyle.INK.lightened(0.02)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	row.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	row.add_child(hbox)

	# 图标
	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(36, 36)
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_box.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 1, 0.0))
	var icon_tex := TextureRect.new()
	if ResourceLoader.exists(String(adef.get("icon", ""))):
		icon_tex.texture = load(String(adef["icon"]))
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.custom_minimum_size = Vector2(30, 30)
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if not is_done:
		icon_tex.modulate = Color(0.4, 0.4, 0.5, 0.7)
	icon_box.add_child(icon_tex)
	hbox.add_child(icon_box)

	# 成就名与条件
	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 2)
	hbox.add_child(text_col)

	var name_lbl := Label.new()
	name_lbl.text = String(adef.get("name", "未命名成就"))
	GameStyle.label(name_lbl, 14, GameStyle.PAPER if is_done else GameStyle.PAPER_DIM, 0, GameStyle.INK, true)
	text_col.add_child(name_lbl)

	var cond_lbl := Label.new()
	cond_lbl.text = String(adef.get("cond_desc", ""))
	GameStyle.label(cond_lbl, 11, GameStyle.JADE if is_done else GameStyle.GREY)
	text_col.add_child(cond_lbl)

	# 奖励说明
	var rtype := String(adef.get("reward_type", ""))
	var rprefix := "解锁角色：" if rtype == "cultivator" else "解锁道具："
	var rname := String(adef.get("reward_name", ""))
	var reward_lbl := Label.new()
	reward_lbl.text = "%s%s" % [rprefix, rname]
	reward_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	reward_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.NAVY2))
	GameStyle.label(reward_lbl, 11, GameStyle.PAPER_DIM)
	hbox.add_child(reward_lbl)

	# 状态色签
	var status_lbl := Label.new()
	status_lbl.text = " 已达成 " if is_done else " 未达成 "
	status_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.GOOD_DK if is_done else GameStyle.LINE))
	GameStyle.label(status_lbl, 12, GameStyle.GOOD if is_done else GameStyle.GREY)
	hbox.add_child(status_lbl)

	return row

# ----------------- 道统功名行 -----------------

func _create_cultivator_row(cid: String) -> Control:
	var unlocked: bool = GameManager.is_cultivator_unlocked(cid)
	var rec := GameManager.get_cultivator_record(cid)
	var wins := int(rec["wins"])
	var title := AchievementData.title_for_wins(wins)
	var best_danger := GameManager.get_cultivator_best_danger(cid)

	var row := PanelContainer.new()
	var style := GameStyle.side_card(GameStyle.JADE if (unlocked and wins > 0) else GameStyle.LINE)
	if not unlocked:
		style.bg_color = GameStyle.INK.lightened(0.02)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	row.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	row.add_child(hbox)

	# 头像
	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(44, 44)
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_box.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 1, 0.0))
	var cdef := CultivatorData.get_def(cid)
	var icon_tex := TextureRect.new()
	if ResourceLoader.exists(String(cdef.get("icon", ""))):
		icon_tex.texture = load(String(cdef["icon"]))
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.custom_minimum_size = Vector2(38, 38)
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if not unlocked:
		icon_tex.modulate = Color(0.4, 0.4, 0.5, 0.7)
	icon_box.add_child(icon_tex)
	hbox.add_child(icon_box)

	# 名字 + 称号 / 生涯摘要
	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 2)
	hbox.add_child(text_col)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	text_col.add_child(name_row)

	var name_lbl := Label.new()
	name_lbl.text = String(cdef.get("name", "未知角色"))
	GameStyle.label(name_lbl, 14, GameStyle.PAPER if unlocked else GameStyle.PAPER_DIM, 0, GameStyle.INK, true)
	name_row.add_child(name_lbl)

	var title_lbl := Label.new()
	if not unlocked:
		title_lbl.text = " 未解锁 "
		title_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.LINE))
		GameStyle.label(title_lbl, 11, GameStyle.GREY)
	elif title != "":
		title_lbl.text = " %s " % title
		title_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.GOLD))
		GameStyle.label(title_lbl, 11, GameStyle.INK_TEXT)
	else:
		title_lbl.text = "待解锁"
		title_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.NAVY2))
		GameStyle.label(title_lbl, 11, GameStyle.PAPER_DIM)
	title_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(title_lbl)

	var endless_txt := "无尽第 %d 波" % int(rec["endless_best_wave"]) if int(rec["endless_best_wave"]) > 0 else "无尽未达"
	var danger_txt := "最高「%s」" % AchievementData.danger_name(best_danger) if best_danger >= 0 else "未通关"
	var detail_lbl := Label.new()
	detail_lbl.text = "通关 %d 次 · %s · 最高击杀 %d · %s" % [wins, endless_txt, int(rec["best_kills"]), danger_txt]
	GameStyle.label(detail_lbl, 12, GameStyle.PAPER_DIM)
	text_col.add_child(detail_lbl)

	# 里程碑 4 档进度签（1/3/5/10 胜）
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 4)
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(pips)
	var claimed: Array = GameManager.claimed_milestones
	for m in AchievementData.milestones_of(cid):
		var m_id := String(m["id"])
		var m_wins := int(m["wins"])
		var pip := Label.new()
		if m_id in claimed:
			pip.text = " 已领 "
			pip.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.GOOD_DK))
			GameStyle.label(pip, 10, GameStyle.GOOD)
		elif wins >= m_wins:
			pip.text = " 可领 "
			pip.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.GOLD))
			GameStyle.label(pip, 10, GameStyle.INK_TEXT)
		else:
			pip.text = " %d胜 " % m_wins
			pip.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.LINE))
			GameStyle.label(pip, 10, GameStyle.GREY)
		pips.add_child(pip)

	# 领取控件（滚动区禁 Button，PanelContainer + tap）
	var next_mile := _next_claimable_milestone(cid)
	if next_mile.size() > 0:
		var claim_panel := PanelContainer.new()
		claim_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		claim_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var c_sb := GameStyle.block(GameStyle.GOLD, GameStyle.SLANT_BUTTON, Vector2(2, 3))
		c_sb.content_margin_left = 10.0
		c_sb.content_margin_right = 10.0
		c_sb.content_margin_top = 6.0
		c_sb.content_margin_bottom = 6.0
		claim_panel.add_theme_stylebox_override("panel", c_sb)
		var claim_lbl := Label.new()
		claim_lbl.text = "领 %d 金币" % int(next_mile["stones"])
		GameStyle.label(claim_lbl, 12, GameStyle.INK_TEXT, 0, GameStyle.INK, true)
		claim_panel.add_child(claim_lbl)
		var tier := int(next_mile["wins"])
		GameStyle.tap(claim_panel, func() -> void: _on_claim_pressed(cid, tier))
		hbox.add_child(claim_panel)
	elif wins <= 0:
		hbox.add_child(_dim_hint("待首次通关"))
	elif _all_milestones_claimed(cid):
		hbox.add_child(_dim_hint("已 领 齐"))
	else:
		var need := _next_milestone_wins(cid)
		hbox.add_child(_dim_hint("通关 %d 次可领" % need))

	# 行点按 → 「这是什么」详情（生涯档案 / 解锁条件）
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	GameStyle.tap(row, func() -> void: _open_cultivator_tip(cid, row))
	return row

func _dim_hint(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = " %s " % text
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.LINE))
	GameStyle.label(lbl, 11, GameStyle.GREY)
	return lbl

func _next_claimable_milestone(cid: String) -> Dictionary:
	var wins: int = int(GameManager.get_cultivator_record(cid).get("wins", 0))
	for m in AchievementData.milestones_of(cid):
		if AchievementData.is_milestone_claimable(m, int(wins), GameManager.claimed_milestones):
			return m
	return {}

func _next_milestone_wins(cid: String) -> int:
	var wins := int(GameManager.get_cultivator_record(cid)["wins"])
	for m in AchievementData.milestones_of(cid):
		if int(m["wins"]) > wins:
			return int(m["wins"])
	return -1

func _all_milestones_claimed(cid: String) -> bool:
	for m in AchievementData.milestones_of(cid):
		if not (String(m["id"]) in GameManager.claimed_milestones):
			return false
	return true

## 领取里程碑奖励：灵石入灵石囊，音效 + 全页刷新
func _on_claim_pressed(cid: String, tier: int) -> void:
	if not GameManager.claim_milestone(cid, tier):
		return
	AudioManager.play_sfx("level_up", 1.0)
	_refresh_data()

## 道统行点按详情：已解锁看生涯档案，未解锁看达成条件
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
	var rows: Array = [
		["游戏局数", "%d 局" % int(rec["runs"]), GameStyle.PAPER],
		["通关", "%d 次" % wins, GameStyle.JADE],
		["无尽最高", ("第 %d 波" % int(rec["endless_best_wave"])) if int(rec["endless_best_wave"]) > 0 else "未入无尽", GameStyle.PAPER],
		["最高击杀", "%d 只" % int(rec["best_kills"]), GameStyle.PAPER],
		["最高难度", AchievementData.danger_name(GameManager.get_cultivator_best_danger(cid)) if GameManager.get_cultivator_best_danger(cid) >= 0 else "未通关", GameStyle.GOLD],
	]
	DetailTip.show_over(self, anchor, {
		"title": "%s · 角色记录" % cname,
		"chip": "档案",
		"chip_color": GameStyle.JADE,
		"rows": rows,
		"body": "称号「%s」" % AchievementData.title_for_wins(wins) if AchievementData.title_for_wins(wins) != "" else "尚未获得称号",
		"foot": "里程碑奖励为一次性金币，领取后于下一局开局到账。",
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

	# 上阵法器
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
	GameStyle.label(v_tag, 11, GameStyle.PAPER if is_vic else GameStyle.BAD)
	hbox.add_child(v_tag)

	return row
