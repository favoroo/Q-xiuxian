class_name PlayerStatsDialog
extends BaseModalDialog

## 角色属性详情面板：仿《土豆兄弟》构筑总览界面
## 左侧：主要/次要属性 Tab 切换（覆盖全部 25 项属性，点按看详解与来源拆解）
## 右侧：上阵武器槽 + 流派羁绊阶梯加成卡（直观显示 2/6 持有进度与各级加成激活状态）+ 随身道具/悟道历程双标签
## 拆分说明：本体保留成员声明、open/close/refresh 编排、Tab 切换与全部点按详解口；
## 左栏构建在 StatsPanelBuilder、右栏构建与槽位刷新在 EquipmentPanelBuilder、
## 羁绊卡在 SynergyCardBuilder、道具徽记/历史行在 ItemsHistoryBuilder（builder 直接写回成员）。

var _unpause_on_close: bool = true

# UI 节点引用
var _meta_label: Label

# 左侧属性 Tab 与容器
var _stat_tab_primary_btn: Button
var _stat_tab_secondary_btn: Button
var _primary_stats_box: VBoxContainer
var _secondary_stats_box: VBoxContainer
var _current_stat_tab: int = 0 # 0 = 主要, 1 = 次要

# 左侧属性节点（主要 16 项 + 次要 9 项 = 25 项）
var _hp_bar: ProgressBar
var _hp_val_lbl: Label
var _regen_val_lbl: Label
var _lifesteal_val_lbl: Label
var _atk_val_lbl: Label
var _melee_val_lbl: Label
var _ranged_val_lbl: Label
var _elem_val_lbl: Label
var _eng_val_lbl: Label
var _contraption_val_lbl: Label
var _haste_val_lbl: Label
var _crit_val_lbl: Label
var _range_val_lbl: Label
var _armor_val_lbl: Label
var _dodge_val_lbl: Label
var _speed_val_lbl: Label
var _luck_val_lbl: Label
var _harvest_val_lbl: Label

var _pickup_val_lbl: Label
var _xp_gain_val_lbl: Label
var _elite_dmg_val_lbl: Label
var _knockback_val_lbl: Label
var _pierce_val_lbl: Label
var _thorns_val_lbl: Label
var _shop_price_val_lbl: Label
var _free_rerolls_val_lbl: Label
var _stones_val_lbl: Label
var _kills_val_lbl: Label

# 右侧武器、羁绊、道具与历史节点（保留测试依赖变量名 _weapons_box / _stash_box / _history_list）
var _wp_title_lbl: Label
var _weapons_box: HBoxContainer
# 顶部道统卡：当前角色的正面加成 / 负面代偿速览
var _cult_card: PanelContainer
var _cult_icon: TextureRect
var _cult_name_lbl: Label
var _cult_epi_lbl: Label
var _cult_pros_lbl: Label
var _cult_extra_lbl: Label   ## 额外技能单独一段（幽夜紫），不并进「加成」那串
var _cult_cons_lbl: Label
var _stash_box: HBoxContainer
var _stash_section: HBoxContainer
var _synergy_flow: HFlowContainer
var _synergy_hint_lbl: Label

var _bottom_tab_items_btn: Button
var _bottom_tab_hist_btn: Button
var _items_scroll: ScrollContainer
var _items_flow: HFlowContainer
var _history_scroll: ScrollContainer
var _history_list: VBoxContainer
var _history_count_lbl: Label
var _current_bottom_tab: int = 0 # 0 = 随身道具, 1 = 悟道历程

func _get_title_text() -> String:
	return "等 级  ·  属 性 面 板"

func _get_close_btn_text() -> String:
	return "返 回 战 斗"

func _get_panel_size() -> Vector2:
	var vw := get_viewport_rect().size.x
	if vw <= 0.0:
		vw = 960.0
	return Vector2(minf(900.0, vw - 48.0), _fit_panel_height())

func _get_panel_margins() -> Vector4:
	return Vector4(16, 8, 16, 8)

func _get_vbox_separation() -> int:
	return 6

func _get_close_btn_min_size() -> Vector2:
	return Vector2(96, 30)

func _build_body(root_vbox: VBoxContainer) -> void:
	_panel.add_theme_stylebox_override("panel", GameStyle.dialog_panel(GameStyle.GOLD, 2.5, Vector2(8, 8)))

	_meta_label = Label.new()
	GameStyle.label(_meta_label, 13, GameStyle.JADE)
	_meta_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_meta_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tab_bar.add_child(_meta_label)

	var hint_lbl := Label.new()
	hint_lbl.text = "点任意条目查看加成拆解"
	GameStyle.label(hint_lbl, 11, GameStyle.GREY)
	hint_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tab_bar.add_child(hint_lbl)

	# 主体内容：左右分栏
	var body_hbox := HBoxContainer.new()
	body_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_hbox.add_theme_constant_override("separation", 12)
	root_vbox.add_child(body_hbox)

	var left_panel := _build_left_stats_panel()
	body_hbox.add_child(left_panel)

	var right_panel := _build_right_equipment_and_history_panel()
	body_hbox.add_child(right_panel)

func _build_left_stats_panel() -> Control:
	return StatsPanelBuilder.build_left_panel(self)

func _switch_stat_tab(tab_idx: int) -> void:
	_current_stat_tab = tab_idx
	if _primary_stats_box != null:
		_primary_stats_box.visible = (tab_idx == 0)
	if _secondary_stats_box != null:
		_secondary_stats_box.visible = (tab_idx == 1)
	if _stat_tab_primary_btn != null:
		if tab_idx == 0:
			# 选中态亮底：CHALK 纸白面托黑字，与纯黑面板拉开
			GameStyle.button(_stat_tab_primary_btn, GameStyle.CHALK, GameStyle.JADE, 12, GameStyle.INK_TEXT, 4.0)
		else:
			GameStyle.button(_stat_tab_primary_btn, GameStyle.NAVY2, GameStyle.GOLD, 12, GameStyle.PAPER_DIM, 4.0, GameStyle.INK_TEXT)
	if _stat_tab_secondary_btn != null:
		if tab_idx == 1:
			GameStyle.button(_stat_tab_secondary_btn, GameStyle.CHALK, GameStyle.JADE, 12, GameStyle.INK_TEXT, 4.0)
		else:
			GameStyle.button(_stat_tab_secondary_btn, GameStyle.NAVY2, GameStyle.GOLD, 12, GameStyle.PAPER_DIM, 4.0, GameStyle.INK_TEXT)

func _highlight_while_open(anchor: Control, tip: DetailTip) -> void:
	if anchor == null or tip == null or not anchor.has_meta("sb_on"):
		return
	var on: StyleBox = anchor.get_meta("sb_on")
	var flat: StyleBox = anchor.get_meta("sb_flat")
	anchor.add_theme_stylebox_override("panel", on)
	tip.closed.connect(func() -> void:
		if is_instance_valid(anchor):
			anchor.add_theme_stylebox_override("panel", flat)
	)

func _build_right_equipment_and_history_panel() -> Control:
	return EquipmentPanelBuilder.build_right_panel(self)

func _switch_bottom_tab(tab_idx: int) -> void:
	_current_bottom_tab = tab_idx
	if _items_scroll != null:
		_items_scroll.visible = (tab_idx == 0)
	if _history_scroll != null:
		_history_scroll.visible = (tab_idx == 1)
	if _bottom_tab_items_btn != null:
		if tab_idx == 0:
			GameStyle.button(_bottom_tab_items_btn, GameStyle.GOLD, GameStyle.JADE, 12, GameStyle.PAPER, 4.0, GameStyle.INK_TEXT)
		else:
			GameStyle.button(_bottom_tab_items_btn, GameStyle.NAVY2, GameStyle.GOLD, 12, GameStyle.PAPER_DIM, 4.0, GameStyle.INK_TEXT)
	if _bottom_tab_hist_btn != null:
		if tab_idx == 1:
			GameStyle.button(_bottom_tab_hist_btn, GameStyle.GOLD, GameStyle.JADE, 12, GameStyle.PAPER, 4.0, GameStyle.INK_TEXT)
		else:
			GameStyle.button(_bottom_tab_hist_btn, GameStyle.NAVY2, GameStyle.GOLD, 12, GameStyle.PAPER_DIM, 4.0, GameStyle.INK_TEXT)

func open(unpause_on_close: bool = true) -> void:
	if visible or GameManager.is_game_over:
		return
	_closing = false
	_unpause_on_close = unpause_on_close
	_panel.custom_minimum_size.y = _fit_panel_height()
	refresh()
	visible = true
	get_tree().paused = true
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.16)

func close() -> void:
	if _closing or not visible:
		return
	_closing = true
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.12)
	tw.tween_callback(func():
		visible = false
		if _unpause_on_close:
			get_tree().paused = false
		_closing = false
		closed.emit()
	)

func refresh() -> void:
	DetailTip.close_all(self)
	var stats := GameManager.get_stat_breakdown()
	var mins := int(GameManager.game_time / 60.0)
	var secs := int(GameManager.game_time) % 60
	_meta_label.text = "%s  ·  Lv.%d  ·  第 %d 波 (%02d:%02d)" % [
		_cultivator_name(),
		GameManager.level,
		maxi(GameManager.wave_number, 1),
		mins, secs
	]

	# 1. 左侧主要属性刷新
	_hp_bar.max_value = stats["max_hp"]
	_hp_bar.value = stats["current_hp"]
	_hp_val_lbl.text = "%d / %d" % [int(stats["current_hp"]), int(stats["max_hp"])]

	var reg: float = float(stats["hp_regen"])
	_regen_val_lbl.text = "+%.1f / 秒" % reg
	_regen_val_lbl.add_theme_color_override("font_color", _c_row(reg))

	var ls_pct: float = float(stats["lifesteal_pct"])
	_lifesteal_val_lbl.text = "%.0f%%" % ls_pct
	_lifesteal_val_lbl.add_theme_color_override("font_color", _c_row(ls_pct))

	var dmg_bonus: float = float(stats["damage_bonus_pct"])
	_atk_val_lbl.text = "%s%.0f%%" % ["+" if dmg_bonus >= 0 else "", dmg_bonus]
	_atk_val_lbl.add_theme_color_override("font_color", _c_row(dmg_bonus))

	var melee_v: float = float(stats["melee_damage"])
	_melee_val_lbl.text = "%s%.0f" % ["+" if melee_v > 0 else "", melee_v]
	_melee_val_lbl.add_theme_color_override("font_color", _c_row(melee_v))

	var ranged_v: float = float(stats["ranged_damage"])
	_ranged_val_lbl.text = "%s%.0f" % ["+" if ranged_v > 0 else "", ranged_v]
	_ranged_val_lbl.add_theme_color_override("font_color", _c_row(ranged_v))

	var elem_v: float = float(stats["elemental_damage"])
	_elem_val_lbl.text = "%s%.0f" % ["+" if elem_v > 0 else "", elem_v]
	_elem_val_lbl.add_theme_color_override("font_color", _c_row(elem_v))

	var eng_v: float = float(stats["engineering_damage"])
	_eng_val_lbl.text = "%s%.0f" % ["+" if eng_v > 0 else "", eng_v]
	_eng_val_lbl.add_theme_color_override("font_color", _c_row(eng_v))

	if _contraption_val_lbl != null:
		var contr_v: float = float(stats.get("contraption_damage", 0.0))
		_contraption_val_lbl.text = "%s%.0f" % ["+" if contr_v > 0 else "", contr_v]
		_contraption_val_lbl.add_theme_color_override("font_color", _c_row(contr_v))

	var cdr: float = float(stats["cdr_pct"])
	_haste_val_lbl.text = "%s%.1f%%" % ["+" if cdr > 0 else "", cdr]
	_haste_val_lbl.add_theme_color_override("font_color", _c_row(cdr))

	var cr: float = float(stats["crit_rate_pct"])
	var cdmg: float = float(stats["crit_dmg_pct"]) / 100.0
	_crit_val_lbl.text = "%.0f%% (%.1f×)" % [cr, cdmg]
	_crit_val_lbl.add_theme_color_override("font_color", GameStyle.GOOD if cr > 5.0 or cdmg > 1.5 else GameStyle.PAPER_DIM)

	var rng_bonus: float = float(stats["attack_range_pct"])
	_range_val_lbl.text = "%s%.0f%%" % ["+" if rng_bonus >= 0 else "", rng_bonus]
	_range_val_lbl.add_theme_color_override("font_color", _c_row(rng_bonus))

	var arm: float = float(stats["armor"])
	_armor_val_lbl.text = "%.0f (减伤 %.0f%%)" % [arm, float(stats["dmg_reduction_pct"])]
	_armor_val_lbl.add_theme_color_override("font_color", _c_row(arm))

	var dodge_pct: float = float(stats["dodge_pct"])
	_dodge_val_lbl.text = "%.0f%%" % dodge_pct
	_dodge_val_lbl.add_theme_color_override("font_color", _c_row(dodge_pct))

	var spd_bonus: float = float(stats["move_speed_bonus_pct"])
	_speed_val_lbl.text = "%.0f (%s%.0f%%)" % [float(stats["move_speed"]), "+" if spd_bonus >= 0 else "", spd_bonus]
	_speed_val_lbl.add_theme_color_override("font_color", _c_row(spd_bonus))

	var luck_v: float = float(stats["luck"])
	_luck_val_lbl.text = "%s%.0f" % ["+" if luck_v > 0 else "", luck_v]
	_luck_val_lbl.add_theme_color_override("font_color", _c_row(luck_v))

	var harvest_v: float = float(stats["harvest"])
	_harvest_val_lbl.text = "%.0f (回合末 +%d)" % [harvest_v, GameBalance.harvest_gain(harvest_v)]
	_harvest_val_lbl.add_theme_color_override("font_color", _c_row(harvest_v))

	# 2. 左侧次要属性刷新
	var pk_bonus: float = float(stats["pickup_bonus_pct"])
	_pickup_val_lbl.text = "%.0f (%s%.0f%%)" % [float(stats["pickup_radius"]), "+" if pk_bonus >= 0 else "", pk_bonus]
	_pickup_val_lbl.add_theme_color_override("font_color", _c_row(pk_bonus))

	var xp_pct: float = float(stats["xp_gain_pct"])
	_xp_gain_val_lbl.text = "%s%.0f%%" % ["+" if xp_pct >= 0 else "", xp_pct]
	_xp_gain_val_lbl.add_theme_color_override("font_color", _c_row(xp_pct))

	var elite_pct: float = float(stats["elite_damage_pct"])
	_elite_dmg_val_lbl.text = "%s%.0f%%" % ["+" if elite_pct >= 0 else "", elite_pct]
	_elite_dmg_val_lbl.add_theme_color_override("font_color", _c_row(elite_pct))

	var kb_pct: float = float(stats["knockback_pct"])
	_knockback_val_lbl.text = "%s%.0f%%" % ["+" if kb_pct >= 0 else "", kb_pct]
	_knockback_val_lbl.add_theme_color_override("font_color", _c_row(kb_pct))

	var pierce_v: int = int(stats["bonus_pierce"])
	_pierce_val_lbl.text = "%s%d" % ["+" if pierce_v > 0 else "", pierce_v]
	_pierce_val_lbl.add_theme_color_override("font_color", _c_row(float(pierce_v)))

	var th_pct: float = float(stats.get("thorns_pct", 0.0))
	_thorns_val_lbl.text = "%s%.0f%%" % ["+" if th_pct > 0 else "", th_pct]
	_thorns_val_lbl.add_theme_color_override("font_color", _c_row(th_pct))

	var sp_pct: float = float(stats["shop_price_pct"])
	_shop_price_val_lbl.text = "%s%.0f%%" % ["+" if sp_pct >= 0 else "", sp_pct]
	# 物价降低是好事（绿色），物价上涨是坏事（红色）
	_shop_price_val_lbl.add_theme_color_override("font_color", _c_row(-sp_pct))

	var fr_v: int = int(stats["free_rerolls"])
	_free_rerolls_val_lbl.text = "%d 次" % fr_v
	_free_rerolls_val_lbl.add_theme_color_override("font_color", _c_row(float(fr_v)))

	_stones_val_lbl.text = "%d 枚" % GameManager.spirit_stones
	_stones_val_lbl.add_theme_color_override("font_color", GameStyle.JADE if GameManager.spirit_stones > 0 else GameStyle.PAPER_DIM)

	_kills_val_lbl.text = "%d 杀" % GameManager.kills
	_kills_val_lbl.add_theme_color_override("font_color", GameStyle.PAPER if GameManager.kills > 0 else GameStyle.PAPER_DIM)

	# 3. 右侧道统卡、武器、流派羁绊、道具与历史刷新
	_refresh_cultivator()
	_refresh_weapons()
	_refresh_synergies()
	_refresh_items_and_history()

## 道统卡文案折行宽度预算：面板最小宽 900 − 外边距32 − 左栏296 − 分栏间距12 − 卡片内边距24 − 图标40 − 列距10 − 余量8
func _cult_text_width() -> float:
	var panel_w: float = maxf(900.0, get_viewport_rect().size.x)
	return panel_w - 32.0 - 296.0 - 12.0 - 24.0 - 40.0 - 10.0 - 8.0

func _refresh_cultivator() -> void:
	if _cult_card == null:
		return
	var def := CultivatorData.get_def(GameManager.cultivator_id)
	if def.is_empty():
		_cult_card.visible = false
		return
	_cult_card.visible = true
	if _cult_icon != null:
		var icon_path: String = String(def.get("icon", ""))
		_cult_icon.texture = load(icon_path) if not icon_path.is_empty() and ResourceLoader.exists(icon_path) else null
	if _cult_name_lbl != null:
		_cult_name_lbl.text = String(def.get("name", "未选角色"))
	if _cult_epi_lbl != null:
		_cult_epi_lbl.text = "「%s」" % String(def.get("epithet", ""))
	var w := _cult_text_width()
	var font := GameStyle.body_font()
	var pros: Array = def.get("pros", [])
	var cons: Array = def.get("cons", [])
	if _cult_pros_lbl != null:
		var pros_txt := "加成：" + "；".join(PackedStringArray(pros))
		_cult_pros_lbl.text = GameStyle.wrap_cjk(pros_txt, font, 11, w)
		_cult_pros_lbl.visible = not pros.is_empty()
	# 额外技能单独一行：与选角界面同读机制表那一段，两行各自切完再叠，不并进「加成」那串
	if _cult_extra_lbl != null:
		var extra_lines := CultivatorData.get_extra_desc(GameManager.cultivator_id)
		var extra_txt := ""
		for xl in extra_lines:
			if not extra_txt.is_empty():
				extra_txt += "\n"
			extra_txt += GameStyle.wrap_cjk(String(xl), font, 11, w)
		_cult_extra_lbl.text = extra_txt
		_cult_extra_lbl.visible = not extra_lines.is_empty()
	if _cult_cons_lbl != null:
		var cons_txt := "代偿：" + "；".join(PackedStringArray(cons))
		_cult_cons_lbl.text = GameStyle.wrap_cjk(cons_txt, font, 11, w)
		_cult_cons_lbl.visible = not cons.is_empty()

## 道统详解：正面加成、负面代偿、随行技能契合、开局自带与商店/加点限制（委托 StatsTipFactory）
func _open_cultivator_tip(anchor: Control) -> void:
	var tip := StatsTipFactory.open_cultivator_tip(self, anchor)
	_highlight_while_open(anchor, tip)

func _refresh_weapons() -> void:
	EquipmentPanelBuilder.refresh_weapons(self)

func _refresh_synergies() -> void:
	if _synergy_flow == null:
		return
	for child in _synergy_flow.get_children():
		child.queue_free()

	# 按已激活优先、持有数从高到低排列当前拥有的流派
	var tags: Array[String] = []
	for tag in GameManager.active_synergies.keys():
		var data: Dictionary = GameManager.active_synergies[tag]
		if int(data.get("count", 0)) > 0:
			tags.append(String(tag))

	tags.sort_custom(func(a: String, b: String) -> bool:
		var da: Dictionary = GameManager.active_synergies.get(a, {})
		var db: Dictionary = GameManager.active_synergies.get(b, {})
		var lva := int(da.get("level", 0))
		var lvb := int(db.get("level", 0))
		if lva != lvb:
			return lva > lvb
		return int(da.get("count", 0)) > int(db.get("count", 0))
	)

	if tags.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "当前尚未装备武器。装备同系（如剑系、火系）武器满 2 / 4 / 6 件即可触发阶梯共鸣加成。"
		GameStyle.label(empty_lbl, 12, GameStyle.PAPER_DIM)
		_synergy_flow.add_child(empty_lbl)
		return

	for tag in tags:
		_synergy_flow.add_child(SynergyCardBuilder.create_card(self, tag))
	GameStyle.swipeable(_synergy_flow)

func _open_synergy_tip(tag: String, anchor: Control) -> void:
	var info: Dictionary = WeaponData.SYNERGIES.get(tag, {})
	if info.is_empty():
		return
	var match_weapons: Array[String] = []
	for wid in WeaponData.DEFS.keys():
		if tag in WeaponData.tags_of(wid):
			match_weapons.append(String(WeaponData.get_def(wid).get("name", wid)))
	var notes: Array[String] = [
		"上阵同系武器（含同名多把）达到门槛件数即自动激活对应阶梯。",
		"本流派武器：" + "、".join(match_weapons) + "。",
	]
	var tip := SynergyUI.open_tip(self, anchor, tag,
		"流派总加成：" + SynergyUI.synergy_desc(tag),
		"背包中的备用武器不计入上阵数量。",
		notes
	)
	_highlight_while_open(anchor, tip)

func _refresh_items_and_history() -> void:
	for child in _items_flow.get_children():
		child.queue_free()
	for child in _history_list.get_children():
		child.queue_free()

	var item_list := GameManager.items
	var history := GameManager.upgrade_history
	if _bottom_tab_items_btn != null:
		_bottom_tab_items_btn.text = "✦ 携带道具 (%d)" % item_list.size()
	if _bottom_tab_hist_btn != null:
		_bottom_tab_hist_btn.text = "✦ 升级记录 (%d)" % history.size()

	# 若道具为空但已有悟道记录，自动展示悟道历程避免空面板；反之有道具时优先展示道具
	if item_list.is_empty() and not history.is_empty() and _current_bottom_tab == 0:
		_switch_bottom_tab(1)

	# 1. 填充随身道具
	if item_list.is_empty():
		var empty_item_lbl := Label.new()
		empty_item_lbl.text = "尚未购入携带道具。在回合间商店可购置各类被动道具。"
		GameStyle.label(empty_item_lbl, 12, GameStyle.PAPER_DIM)
		_items_flow.add_child(empty_item_lbl)
	else:
		# 合并同名道具计数展示，如「聚宝盆 ×2」
		var counts: Dictionary = {}
		var order: Array[String] = []
		for raw_id in item_list:
			var iid := String(raw_id)
			if not counts.has(iid):
				counts[iid] = 0
				order.append(iid)
			counts[iid] = int(counts[iid]) + 1
		for iid in order:
			_items_flow.add_child(ItemsHistoryBuilder.create_item_badge(self, iid, int(counts[iid])))
		GameStyle.swipeable(_items_flow)

	# 2. 填充历史悟道记录
	if history.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "尚未有升级加成，每回合平息后可根据等级提升领悟天地法则。"
		GameStyle.label(empty_lbl, 12, GameStyle.PAPER_DIM)
		_history_list.add_child(empty_lbl)
		return

	for i in range(history.size()):
		var item: Dictionary = history[i]
		var row := ItemsHistoryBuilder.create_history_row(self, item, i + 1)
		_history_list.add_child(row)
	GameStyle.swipeable(_history_list)

func _open_item_tip(item_id: String, count: int, anchor: Control) -> void:
	var tip := StatsTipFactory.open_item_tip(self, anchor, item_id, count)
	_highlight_while_open(anchor, tip)

# ============================ 点按详解 ============================

func _fit_panel_height() -> float:
	var vp := get_viewport_rect().size
	if vp.y <= 0.0:
		return 516.0
	return clampf(vp.y - 14.0, 380.0, 516.0)

func _open_stat_tip(id: String, anchor: Control) -> void:
	if not StatInfoData.has(id):
		return
	# 若点按的条目属于隐藏的 Tab（例如自动化测试全扫 25 项），自动切过去使其具有真实屏幕坐标
	if id in StatInfoData.SECONDARY_IDS and _current_stat_tab != 1:
		_switch_stat_tab(1)
	elif id in StatInfoData.PRIMARY_IDS and id != "hp" and _current_stat_tab != 0:
		_switch_stat_tab(0)

	var tip := DetailTip.show_over(self, anchor, {
		"title": StatInfoData.title(id),
		"rows": _stat_tip_rows(id),
		"body": StatInfoData.brief(id),
		"notes": StatInfoData.rules(id),
		"foot": _stat_tip_foot(id),
	})
	_highlight_while_open(anchor, tip)

## 来源拆解：覆盖全部 25 项主要与次要属性（下放到 StatInfoData）
func _stat_tip_rows(id: String) -> Array:
	return StatInfoData.stat_tip_rows(id)

func _stat_tip_foot(id: String) -> String:
	var src: Array[String] = StatInfoData.sources(id)
	if src.is_empty():
		return ""
	return "可提升途径：" + "、".join(src)

func _open_empty_slot_tip(index: int, anchor: Control) -> void:
	var tip := StatsTipFactory.open_empty_slot_tip(self, anchor, index)
	_highlight_while_open(anchor, tip)

func _open_weapon_tip(w: Dictionary, from_stash: bool, anchor: Control) -> void:
	var tip := StatsTipFactory.open_weapon_tip(self, anchor, w, from_stash)
	_highlight_while_open(anchor, tip)

func _open_history_tip(item: Dictionary, _idx: int, anchor: Control) -> void:
	if _current_bottom_tab != 1:
		_switch_bottom_tab(1)
	var tip := StatsTipFactory.open_history_tip(self, anchor, item)
	_highlight_while_open(anchor, tip)

func _cultivator_name() -> String:
	return StatInfoData._cultivator_name()

func _c(v: float) -> Color:
	return StatsTipFactory._c(v)

## 面板行专用判色（2026-10-11 土豆兄弟式口径）：非零走正绿负红，零值压暗灰白——
## 一眼只看见「有修炼成果」的那几行； stones 金币与暴击等特殊口径在 refresh 里单独处理
func _c_row(v: float) -> Color:
	if absf(v) < 0.0001:
		return GameStyle.PAPER_DIM
	return _c(v)

