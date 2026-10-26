class_name AuthorAllocView
extends VBoxContainer

## 作者面板「◆ 悟道」页（2026-10-25）：普通悟道 + 超级悟道的免费加/删测试台。
##
## 口径：
## - 加点走 AuthorMode.add_upgrade（与真实结算同一条 apply 链路，不消耗待加点，守住 max_stacks）；
##   删除走 AuthorMode.remove_upgrade —— 账本改完由 AuthorStatRebuild 从初值重放整条属性层，
##   被上限夹住的字段也能精确回落（撤销会「宁可少扣」永远卡在 cap，见其头注）。
## - 超级悟道不设阶段/灵兽门控（测试台要能任意组合），撤销连赠予的神通道具一起收走。
## - 点卡 = 看详情，加/删都在详情窗的键上（keep_open 支持连点批量）——与武器/道具页同口径。
## - 只影响本局；作者模式不写存档，退出作者模式随单局重置归零。

signal state_changed(kind: String)

const RARITY_FILTERS: Array = [
	["", "全部"], ["common", "普通"], ["rare", "稀有"], ["epic", "史诗"], ["legendary", "传说"],
]
## 阶段名（道途卡 stage 1~3；共鸣/仪式卡没有阶段）
const STAGE_NAMES: Array = ["", "一阶", "二阶", "三阶"]
const CARD_W := CodexCardFactory.CARD_W
const GRID_GAP := 8

var _author_panel: Control = null
var _rarity_filter: String = ""
var _line_filter: String = ""
var _rarity_chips: Dictionary = {}
var _line_chips: Dictionary = {}

var _level_lbl: Label
var _points_lbl: Label
var _owned_lbl: Label
var _stats_grid: GridContainer
var _owned_box: VBoxContainer
var _upgrade_grid: GridContainer
var _super_grid: GridContainer
var _scroll_box: VBoxContainer

func _init(author_panel: Control) -> void:
	_author_panel = author_panel

## 详情卡宿主：必须交出外层**全屏**的 AuthorPanel（同 AuthorShopView 的注释），
## DetailTip 的全屏遮罩与摆位按宿主 size / global_position 算，挂自己身上会跑出屏幕。
func get_tip_host() -> Control:
	if _author_panel != null and is_instance_valid(_author_panel):
		return _author_panel
	return self

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)
	_build_ui()

# ---------------- 布局 ----------------

func _build_ui() -> void:
	# 顶部固定区：概读 + 快捷键（不随滚动跑）
	var overview := HFlowContainer.new()
	overview.add_theme_constant_override("h_separation", 8)
	overview.add_theme_constant_override("v_separation", 6)
	add_child(overview)

	_level_lbl = _make_value_label("Lv.1")
	overview.add_child(_level_lbl)
	_points_lbl = _make_value_label("待加点 0")
	overview.add_child(_points_lbl)
	_owned_lbl = _make_value_label("已加 0 种 · 0 层")
	overview.add_child(_owned_lbl)
	overview.add_child(_make_button("＋1 点", func() -> void: _grant_points(1), 72))
	overview.add_child(_make_button("＋5 点", func() -> void: _grant_points(5), 72))
	overview.add_child(_make_button("清空加点", func() -> void: _clear_upgrades(), 92))
	overview.add_child(_make_button("清空超级", func() -> void: _clear_supers(), 92))

	# 当前属性读数：加/删之后立刻能看到数值动了没有（测试台的眼睛）
	_stats_grid = GridContainer.new()
	_stats_grid.columns = 4
	_stats_grid.add_theme_constant_override("h_separation", 14)
	_stats_grid.add_theme_constant_override("v_separation", 2)
	add_child(_stats_grid)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	GameStyle.scrollable(scroll)
	add_child(scroll)
	_scroll_box = VBoxContainer.new()
	_scroll_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_scroll_box)

	# 已加点（可删）
	_owned_box = VBoxContainer.new()
	_owned_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_owned_box.add_theme_constant_override("separation", 4)
	_scroll_box.add_child(_owned_box)

	_scroll_box.add_child(_make_separator())
	_scroll_box.add_child(_make_section_title("普通悟道 · 全表", GameStyle.GOLD))
	_scroll_box.add_child(_make_hint("点卡看详情，在弹窗里免费加/删（可连点）。作者模式不受角色锁定约束。"))
	_scroll_box.add_child(_make_filter_row("rarity", RARITY_FILTERS))
	_upgrade_grid = GridContainer.new()
	_upgrade_grid.add_theme_constant_override("h_separation", GRID_GAP)
	_upgrade_grid.add_theme_constant_override("v_separation", GRID_GAP)
	_scroll_box.add_child(_upgrade_grid)

	_scroll_box.add_child(_make_separator())
	_scroll_box.add_child(_make_section_title("飞升悟道 · 全表", GameStyle.RARITY_MYTHIC))
	_scroll_box.add_child(_make_hint("不设阶段/灵兽门控，可任意组合；撤销连赠予的神通道具一起收走（属性与机制同步失效）。"))
	_scroll_box.add_child(_make_filter_row("line", _super_filters()))
	_super_grid = GridContainer.new()
	_super_grid.add_theme_constant_override("h_separation", GRID_GAP)
	_super_grid.add_theme_constant_override("v_separation", GRID_GAP)
	_scroll_box.add_child(_super_grid)

	refresh()

# ---------------- 刷新 ----------------

func refresh() -> void:
	if _level_lbl == null:
		return
	_level_lbl.text = "Lv.%d" % GameManager.level
	_points_lbl.text = "待加点 %d" % GameManager.pending_upgrade_points
	var stacks := 0
	for uid in GameManager.upgrade_counts:
		stacks += int(GameManager.upgrade_counts[uid])
	_owned_lbl.text = "已加 %d 种 · %d 层" % [GameManager.upgrade_counts.size(), stacks]
	_refresh_stats()
	_refresh_owned()
	_rebuild_upgrade_grid()
	_rebuild_super_grid()
	# 卡是 PanelContainer（默认 STOP）：整页建完必须再降一遍，否则整页只能从缝隙里拖动
	GameStyle.swipeable(_scroll_box)

func _refresh_stats() -> void:
	for c in _stats_grid.get_children():
		c.queue_free()
	for line in _stat_lines():
		var name_lbl := Label.new()
		name_lbl.text = String(line[0])
		GameStyle.label(name_lbl, 11, GameStyle.PAPER_DIM)
		_stats_grid.add_child(name_lbl)
		var val_lbl := Label.new()
		val_lbl.text = String(line[1])
		GameStyle.label(val_lbl, 12, GameStyle.PAPER, 0, GameStyle.INK, true)
		_stats_grid.add_child(val_lbl)

## 关键属性现读（测试台的眼睛）：走 GameManager 的有效值 getter，与战斗判定同一算式
func _stat_lines() -> Array:
	var gm := GameManager
	var out: Array = []
	if gm.player != null and is_instance_valid(gm.player):
		out.append(["生命上限", "%d" % int(gm.player.max_health)])
	out.append(["护甲", "%.0f" % gm.get_effective_armor()])
	out.append(["闪避", "%.0f%%" % (gm.get_effective_dodge() * 100.0)])
	out.append(["暴击率", "%.0f%%" % (gm.get_crit_rate() * 100.0)])
	out.append(["暴击伤害", "%.0f%%" % (gm.get_crit_mult() * 100.0)])
	out.append(["武器伤害", "%+.0f%%" % ((gm.get_weapon_damage_mult() - 1.0) * 100.0)])
	out.append(["攻击速度", "%.0f%%" % (gm.get_effective_attack_speed_mult() * 100.0)])
	out.append(["移动速度", "%.0f%%" % ((gm.move_speed_mult + gm.synergy_move_speed_mult) * 100.0)])
	out.append(["攻击范围", "%.0f%%" % (gm.attack_range_mult * gm.synergy_range_mult * 100.0)])
	out.append(["生命回复", "%.1f/秒" % (gm.hp_regen + gm.synergy_hp_regen)])
	out.append(["吸血", "%.0f%%" % ((gm.lifesteal + gm.synergy_lifesteal) * 100.0)])
	out.append(["幸运", "%.0f" % gm.luck])
	out.append(["对精英", "%+.0f%%" % (gm.elite_damage * 100.0)])
	out.append(["技能冷却", "%.0f%%" % (gm.skill_cooldown_mult * 100.0)])
	return out

## 已加账本：一条 = 一张卡（普通或超级），右侧小键直接删
func _refresh_owned() -> void:
	for c in _owned_box.get_children():
		c.queue_free()
	if GameManager.upgrade_counts.is_empty():
		_owned_box.add_child(_make_hint("还没有加点。下面从全表里点卡加，或回合末正常悟道。"))
		return
	for uid in GameManager.upgrade_counts.keys():
		var ledger_id := String(uid)
		var count := int(GameManager.upgrade_counts[ledger_id])
		var card := SuperUpgradeData.get_def(ledger_id)
		if not card.is_empty():
			_owned_box.add_child(_make_owned_row(ledger_id, SuperUpgradeData.card_payload(card), count, true))
		else:
			var def := UpgradeData.get_upgrade_def(ledger_id)
			if def.is_empty():
				continue  # 脏账本（旧版本删掉的卡）：跳过不画
			_owned_box.add_child(_make_owned_row(ledger_id, def, count, false))

## 一条已加记录：稀有度签 + 标题 ×N + 「－1」「清空」小键（点行本体弹详情）
func _make_owned_row(ledger_id: String, data: Dictionary, count: int, is_super: bool) -> Control:
	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var accent: Color = data.get("border_color", GameStyle.PAPER)
	var sb := GameStyle.side_card(accent, 0.0)
	sb.content_margin_left = 8.0
	sb.content_margin_top = 3.0
	sb.content_margin_right = 8.0
	sb.content_margin_bottom = 3.0
	row.add_theme_stylebox_override("panel", sb)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	if is_super:
		GameStyle.tap(row, func() -> void: _open_super_tip(ledger_id, row))
	else:
		GameStyle.tap(row, func() -> void: _open_upgrade_tip(ledger_id, row))

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	row.add_child(hbox)

	var rarity_col: Color = data.get("border_color", GameStyle.PAPER)
	var pill := Label.new()
	pill.text = " %s " % String(data.get("rarity_label", "普通"))
	GameStyle.label(pill, 10, GameStyle.on_face_text(rarity_col))
	pill.add_theme_stylebox_override("normal", GameStyle.chip(rarity_col))
	hbox.add_child(pill)

	var title_lbl := Label.new()
	title_lbl.text = "%s ×%d" % [String(data.get("title", ledger_id)), count] if count > 1 \
			else String(data.get("title", ledger_id))
	GameStyle.label(title_lbl, 12, GameStyle.PAPER)
	hbox.add_child(title_lbl)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(sp)

	hbox.add_child(_make_action_chip("－1", func() -> void:
		if is_super:
			_remove_super(ledger_id)
		else:
			_remove(ledger_id, 1)
	))
	if not is_super and count > 1:
		hbox.add_child(_make_action_chip("清空", func() -> void: _remove(ledger_id, count)))
	return row

# ---------------- 卡片网格 ----------------

func _rebuild_upgrade_grid() -> void:
	for c in _upgrade_grid.get_children():
		c.queue_free()
	_upgrade_grid.columns = _grid_cols()
	for uid in UpgradeData.UPGRADES:
		var ledger_id := String(uid.get("id", ""))
		if ledger_id.is_empty():
			continue
		var rarity := String(uid.get("rarity", "common"))
		if _rarity_filter != "" and rarity != _rarity_filter:
			continue
		var count := int(GameManager.upgrade_counts.get(ledger_id, 0))
		var col: Color = uid.get("border_color", GameStyle.PAPER)
		var chips: Array = [[String(uid.get("rarity_label", "普通")), col, GameStyle.on_face_text(col)]]
		if count > 0:
			chips.append(["×%d" % count, GameStyle.JADE, GameStyle.INK_TEXT])
		var card := CodexCardFactory.make_entry_card(
			String(uid.get("icon", "")), String(uid.get("title", ledger_id)),
			"", GameStyle.PAPER_DIM,
			func(anchor: Control): _open_upgrade_tip(ledger_id, anchor),
			_apply_summary(uid.get("apply", {})), chips)
		_upgrade_grid.add_child(card)
	if _upgrade_grid.get_child_count() == 0:
		_upgrade_grid.add_child(_make_hint("这一档没有卡。点上方「全部」放宽筛选。"))

func _rebuild_super_grid() -> void:
	for c in _super_grid.get_children():
		c.queue_free()
	_super_grid.columns = _grid_cols()
	for card_id in SuperUpgradeData.all_ids():
		var card := SuperUpgradeData.get_def(String(card_id))
		if card.is_empty():
			continue
		var line_key := String(card.get("line", ""))
		if line_key.is_empty():
			line_key = String(card.get("kind", "ritual"))
		if _line_filter != "" and line_key != _line_filter:
			continue
		var payload := SuperUpgradeData.card_payload(card)
		var taken: bool = String(card_id) in GameManager.super_cards_taken
		var chips: Array = _super_card_chips(card, taken)
		var card_node := CodexCardFactory.make_entry_card(
			String(payload.get("icon", "")), String(payload.get("title", String(card_id))),
			"", GameStyle.PAPER_DIM,
			func(anchor: Control): _open_super_tip(String(card_id), anchor),
			_apply_summary(payload.get("apply", {})), chips,
			GameStyle.RARITY_MYTHIC if String(payload.get("icon", "")).is_empty() else Color(-1, -1, -1, -1))
		_super_grid.add_child(card_node)
	if _super_grid.get_child_count() == 0:
		_super_grid.add_child(_make_hint("这一路没有卡。点上方「全部」放宽筛选。"))

## 超级卡色签：道途/共鸣/仪式 + 阶段 + 已领悟
func _super_card_chips(card: Dictionary, taken: bool) -> Array:
	var chips: Array = []
	var line := String(card.get("line", ""))
	var kind := String(card.get("kind", "ritual"))
	if line != "":
		chips.append([SuperUpgradeData.line_label(line), GameStyle.GOLD, GameStyle.INK_TEXT])
		var stage := int(card.get("stage", 0))
		if stage > 0 and stage < STAGE_NAMES.size():
			chips.append([String(STAGE_NAMES[stage]), GameStyle.PAPER_DIM, GameStyle.PAPER])
	else:
		chips.append(["共鸣" if kind == "resonance" else "仪式", GameStyle.GOLD, GameStyle.INK_TEXT])
	if taken:
		chips.append(["已领悟", GameStyle.RARITY_MYTHIC, GameStyle.on_face_text(GameStyle.RARITY_MYTHIC)])
	return chips

## 卡面加成摘要（取前两行，与卡同宽能摆下）
func _apply_summary(apply: Dictionary) -> String:
	var rows: Array = BonusRows.apply_rows(apply)
	if rows.is_empty():
		return ""
	var parts: Array[String] = []
	for i in range(mini(2, rows.size())):
		parts.append("%s %s" % [String(rows[i][0]), String(rows[i][1])])
	var txt := " · ".join(parts)
	if rows.size() > 2:
		txt += " …"
	return txt

# ---------------- 详情窗 ----------------

func _open_upgrade_tip(ledger_id: String, anchor: Control) -> void:
	var def := UpgradeData.get_upgrade_def(ledger_id)
	if def.is_empty():
		return
	var count := int(GameManager.upgrade_counts.get(ledger_id, 0))
	var cap := int(def.get("max_stacks", 99))
	var rows: Array = BonusRows.apply_rows(def.get("apply", {}))
	rows.append(["已加层数", "%d / %d" % [count, cap], GameStyle.JADE])
	var payload := {
		"title": String(def.get("title", ledger_id)),
		"icon": String(def.get("icon", "")),
		"chip": " %s " % String(def.get("rarity_label", "普通")),
		"chip_color": def.get("border_color", GameStyle.PAPER),
		"rows": rows,
		"body": String(def.get("desc", "")),
		"notes": ["作者模式：免费加点，不消耗悟道点。"],
		"foot": "",
	}
	var acts: Array = []
	if count > 0:
		acts.append({
			"text": "－1 层", "color": GameStyle.NAVY2, "edge_color": GameStyle.LINE,
			"text_color": GameStyle.PAPER, "keep_open": true,
			"callback": func() -> void: _remove(ledger_id, 1),
		})
	acts.append({
		"text": "＋1 层", "color": GameStyle.JADE, "edge_color": GameStyle.JADE_EDGE,
		"text_color": GameStyle.INK_TEXT, "keep_open": true,
		"callback": func() -> void: _add(ledger_id),
	})
	payload["actions"] = [acts]
	DetailTip.show_over(get_tip_host(), anchor, payload)

func _open_super_tip(card_id: String, anchor: Control) -> void:
	var card := SuperUpgradeData.get_def(card_id)
	if card.is_empty():
		return
	var payload_def := SuperUpgradeData.card_payload(card)
	var taken: bool = card_id in GameManager.super_cards_taken
	var rows: Array = BonusRows.apply_rows(payload_def.get("apply", {}))
	rows.insert(0, ["道途", _super_lane_text(card), GameStyle.RARITY_MYTHIC])
	rows.append(["状态", "已领悟" if taken else "未领悟", GameStyle.JADE if taken else GameStyle.GREY])
	var payload := {
		"title": String(payload_def.get("title", card_id)),
		"icon": String(payload_def.get("icon", "")),
		"chip": " 逆天 ",
		"chip_color": GameStyle.RARITY_MYTHIC,
		"rows": rows,
		"body": String(payload_def.get("desc", "")),
		"notes": ["作者模式：不设阶段/灵兽门控；撤销会把赠予的神通道具一并收走。"],
		"foot": "",
	}
	var acts: Array = []
	if taken:
		acts.append({
			"text": "移除", "color": GameStyle.NAVY2, "edge_color": GameStyle.LINE,
			"text_color": GameStyle.PAPER, "keep_open": true,
			"callback": func() -> void: _remove_super(card_id),
		})
	acts.append({
		"text": "领悟", "color": GameStyle.RARITY_MYTHIC, "edge_color": GameStyle.RARITY_MYTHIC,
		"text_color": GameStyle.on_face_text(GameStyle.RARITY_MYTHIC), "keep_open": true,
		"callback": func() -> void: _take_super(card_id),
	})
	payload["actions"] = [acts]
	DetailTip.show_over(get_tip_host(), anchor, payload)

## 「剑道 · 二阶」/「共鸣」/「仪式」
func _super_lane_text(card: Dictionary) -> String:
	var line := String(card.get("line", ""))
	var kind := String(card.get("kind", "ritual"))
	var txt := SuperUpgradeData.line_label(line) if line != "" \
			else ("共鸣" if kind == "resonance" else "仪式")
	var stage := int(card.get("stage", 0))
	if stage > 0 and stage < STAGE_NAMES.size():
		txt += " · %s" % String(STAGE_NAMES[stage])
	return txt

# ---------------- 动作 ----------------
##
## ⚠ 重放触发只能在这里（ui/author 侧），不能下沉进 AuthorMode：
## Player.gd 引用 AuthorMode（god_mode 读侧），AuthorMode 若再引用 AuthorStatRebuild
## （它要 StatSystem/Player）就构成循环类依赖（坑 12），Player.gd 直接解析失败。
## 所以分工是：AuthorMode 只改账本 + 落地，本视图账本改完立刻触发从初值重放。

func _ensure_run() -> bool:
	if not GameManager.run_started or GameManager.player == null:
		GameManager.announcement_triggered.emit("先开一局再调加点")
		return false
	return true

func _add(ledger_id: String, stacks: int = 1) -> void:
	if not _ensure_run():
		return
	if not AuthorMode.add_upgrade(GameManager, ledger_id, stacks):
		return
	AuthorStatRebuild.rebuild(GameManager)
	_after_change()

func _remove(ledger_id: String, stacks: int) -> void:
	if not _ensure_run():
		return
	if not AuthorMode.remove_upgrade(GameManager, ledger_id, stacks):
		return
	AuthorStatRebuild.rebuild(GameManager)
	_after_change()

func _take_super(card_id: String) -> void:
	if not _ensure_run():
		return
	if not AuthorMode.take_super(GameManager, card_id):
		return
	AuthorStatRebuild.rebuild(GameManager)
	_after_change()

func _remove_super(card_id: String) -> void:
	if not _ensure_run():
		return
	if not AuthorMode.remove_super(GameManager, card_id):
		return
	AuthorStatRebuild.rebuild(GameManager)
	_after_change()

func _grant_points(n: int) -> void:
	if not _ensure_run():
		return
	AuthorMode.grant_points(GameManager, n)
	_after_change()

func _clear_upgrades() -> void:
	if not _ensure_run():
		return
	if AuthorMode.clear_upgrades(GameManager) == 0:
		GameManager.announcement_triggered.emit("还没有普通加点")
		return
	AuthorStatRebuild.rebuild(GameManager)
	_after_change()

func _clear_supers() -> void:
	if not _ensure_run():
		return
	if AuthorMode.clear_supers(GameManager) == 0:
		GameManager.announcement_triggered.emit("还没有飞升悟道可清")
		return
	AuthorStatRebuild.rebuild(GameManager)
	_after_change()

## 改完统一：发宿主信号（Main 转去刷新悟道/商店面板）+ 本页重铺
func _after_change() -> void:
	state_changed.emit("alloc")
	refresh()

# ---------------- 筛选 chips ----------------

func _make_filter_row(group: String, filters: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for f in filters:
		var tag := String(f[0])
		var text := String(f[1])
		var chip_lbl := Label.new()
		chip_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		chip_lbl.text = " %s " % text
		chip_lbl.set_meta("filter_tag", tag)
		chip_lbl.set_meta("filter_group", group)
		GameStyle.tap(chip_lbl, func() -> void: _on_filter_tapped(group, tag))
		if group == "rarity":
			_rarity_chips[tag] = chip_lbl
		else:
			_line_chips[tag] = chip_lbl
		row.add_child(chip_lbl)
	_restyle_filter_chips()
	return row

## 点 chip：本行内切换；再点已选中的（含「全部」）即回到全部
func _on_filter_tapped(group: String, tag: String) -> void:
	if group == "rarity":
		_rarity_filter = "" if tag == _rarity_filter else tag
	else:
		_line_filter = "" if tag == _line_filter else tag
	_restyle_filter_chips()
	refresh()

func _restyle_filter_chips() -> void:
	for group in ["rarity", "line"]:
		var chips: Dictionary = _rarity_chips if group == "rarity" else _line_chips
		var cur := _rarity_filter if group == "rarity" else _line_filter
		for tag in chips.keys():
			var chip_lbl: Label = chips[tag]
			if not is_instance_valid(chip_lbl):
				continue
			if String(tag) == cur:
				chip_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.GOLD))
				GameStyle.label(chip_lbl, 12, GameStyle.INK_TEXT, 0, GameStyle.INK, true)
			else:
				chip_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.NAVY2))
				GameStyle.label(chip_lbl, 12, GameStyle.PAPER_DIM)

## 超级悟道的筛选档：六条道途 + 共鸣 + 仪式
func _super_filters() -> Array:
	var filters: Array = [["", "全部"]]
	for line in SuperUpgradeData.LINE_LABELS.keys():
		filters.append([String(line), String(SuperUpgradeData.LINE_LABELS[line])])
	filters.append(["resonance", "共鸣"])
	filters.append(["ritual", "仪式"])
	return filters

# ---------------- 通用小件（与 AuthorPanel 同一套语言，本视图自带免得跨类调私有） ----------------

func _content_w() -> float:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0:
		vp = Vector2(960, 540)
	return maxf(240.0, minf(900.0, vp.x - 40.0) - 64.0)

func _grid_cols() -> int:
	return maxi(2, int(floor((_content_w() + GRID_GAP) / (CARD_W + GRID_GAP))))

func _make_section_title(text: String, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = "── %s ──" % text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	GameStyle.label(lbl, 14, color, 0, GameStyle.INK, true)
	return lbl

func _make_hint(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = GameStyle.wrap_cjk(text, GameStyle.body_font(), 11, _content_w() - 12.0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	GameStyle.label(lbl, 11, GameStyle.PAPER_DIM)
	return lbl

func _make_value_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size = Vector2(104, 0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	GameStyle.label(lbl, 14, GameStyle.PAPER, 0, GameStyle.INK, true)
	return lbl

func _make_button(text: String, cb: Callable, min_w: float) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(min_w, 32)
	btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(btn, GameStyle.NAVY2, GameStyle.GOLD, 13, GameStyle.PAPER, 4.0, GameStyle.INK_TEXT)
	btn.pressed.connect(cb)
	return btn

## 行内小键：Label + tap（不用 Button —— 滚动区里 BaseButton 会吞按下事件，坑 11）
func _make_action_chip(text: String, cb: Callable) -> Label:
	var chip_lbl := Label.new()
	chip_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	chip_lbl.text = " %s " % text
	GameStyle.label(chip_lbl, 11, GameStyle.INK_TEXT, 0, GameStyle.INK, true)
	chip_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.JADE_DK))
	GameStyle.tap(chip_lbl, cb)
	return chip_lbl

func _make_separator() -> Control:
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(0, 1)
	line.color = GameStyle.with_alpha(GameStyle.PAPER, 0.12)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line
