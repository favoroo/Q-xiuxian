class_name SaveSlotCardFactory
extends RefCounted

## 存档位卡（2026-10-28）：SaveManageDialog 的列表行工厂。
## 固定高 52、整卡可点（PanelContainer + GameStyle.tap）—— 滚动区里绝不能用 Button，
## BaseButton 会吞掉按下那一拍，整列就划不动（AGENTS.md 坑 11）。
## 五张卡的高度完全一致（空位/坏档也画满），列表不会因为有没有存档而跳动。

const CARD_H := 52.0
const PAD_L := 12.0
const PAD_R := 12.0
const PAD_Y := 7.0
const NO_W := 34.0

static func create(entry: Dictionary, selected: bool, on_tap: Callable,
		save_mode: bool = false) -> Dictionary:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, CARD_H)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	apply_style(card, entry, selected)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", int(PAD_L))
	margin.add_theme_constant_override("margin_right", int(PAD_R))
	margin.add_theme_constant_override("margin_top", int(PAD_Y))
	margin.add_theme_constant_override("margin_bottom", int(PAD_Y))
	card.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)

	var corrupt := bool(entry.get("corrupt", false))
	var occupied := bool(entry.get("occupied", false))

	var no_lbl := Label.new()
	no_lbl.text = str(int(entry.get("index", 1)))
	no_lbl.custom_minimum_size = Vector2(NO_W, NO_W)
	no_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	no_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	no_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var no_face := GameStyle.DISABLED_FACE
	var no_fg := GameStyle.PAPER_DIM
	if corrupt:
		no_face = GameStyle.BAD_DK
		no_fg = GameStyle.CHALK
	elif occupied:
		no_face = GameStyle.GOLD
		no_fg = GameStyle.INK_TEXT
	no_lbl.add_theme_stylebox_override("normal", GameStyle.chip(no_face))
	GameStyle.label(no_lbl, 16, no_fg, 0, GameStyle.INK, true)
	row.add_child(no_lbl)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 1)
	row.add_child(col)

	var title := Label.new()
	title.text = _title_text(entry)
	GameStyle.label(title, 14, GameStyle.BAD if corrupt else GameStyle.PAPER)
	col.add_child(title)

	var sub := Label.new()
	sub.text = _sub_text(entry)
	GameStyle.label(sub, 11, GameStyle.PAPER_DIM)
	col.add_child(sub)

	var state := GameStyle.chip_label(_state_text(entry, save_mode), _state_face(entry),
		Color(-1, -1, -1, -1), 11)
	state.custom_minimum_size = Vector2(64, 0)
	state.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(state)

	# 整卡热区：卡内装饰节点全部不参与交互，点哪都算点这张卡
	GameStyle.hotzone(card)
	GameStyle.tap(card, on_tap)
	return {"card": card, "title": title, "sub": sub, "state": state, "no": no_lbl}

## 选中态只换样式（不重建节点）：列表滚动位置不会因为点选而复位
static func apply_style(card: PanelContainer, entry: Dictionary, selected: bool) -> void:
	if card == null or not is_instance_valid(card):
		return
	var bg := GameStyle.NAVY2
	var border := GameStyle.LINE
	var border_w := 2
	if bool(entry.get("corrupt", false)):
		bg = GameStyle.with_alpha(GameStyle.BAD, 0.10)
		border = GameStyle.BAD
	elif bool(entry.get("occupied", false)):
		border = GameStyle.INK
	if selected:
		border = GameStyle.GOLD
		border_w = 3
	card.add_theme_stylebox_override("panel",
		GameStyle.outlined_panel(bg, border, border_w, GameStyle.SLANT_PLATE))

static func _title_text(entry: Dictionary) -> String:
	if bool(entry.get("corrupt", false)):
		return "存 档 损 坏"
	if not bool(entry.get("occupied", false)):
		return "空 存 档 位"
	var cname := String(entry.get("cname", ""))
	if cname.is_empty():
		cname = "修士"
	return "%s · 第%d波" % [cname, int(entry.get("wave", 1))]

static func _sub_text(entry: Dictionary) -> String:
	if bool(entry.get("corrupt", false)):
		return "文件解析失败 · 只能删除"
	if not bool(entry.get("occupied", false)):
		return "尚未存入进度"
	return "等级 %d · %s · 用时 %s · %s" % [
		int(entry.get("level", 1)),
		AchievementData.danger_name(int(entry.get("danger", 0))),
		fmt_duration(float(entry.get("play_time", 0.0))),
		fmt_saved(int(entry.get("time_unix", 0))),
	]

static func _state_text(entry: Dictionary, save_mode: bool) -> String:
	if bool(entry.get("corrupt", false)):
		return "损 坏"
	if not bool(entry.get("occupied", false)):
		return "空 位"
	# 存档模式点已有档是「覆盖」，管理模式点它是「读取」—— 同一张卡按入口换动作提示
	return "可 覆 盖" if save_mode else "可 读"

static func _state_face(entry: Dictionary) -> Color:
	if bool(entry.get("corrupt", false)):
		return GameStyle.BAD_DK
	if not bool(entry.get("occupied", false)):
		return GameStyle.INK.lightened(0.12)
	return GameStyle.JADE_DK

## 游戏时长：不足 1 小时用 mm:ss，超过用 h:mm:ss
static func fmt_duration(sec: float) -> String:
	var t := int(maxf(sec, 0.0))
	if t >= 3600:
		return "%d:%02d:%02d" % [floori(t / 3600.0), floori((t % 3600) / 60.0), t % 60]
	return "%02d:%02d" % [floori(t / 60.0), t % 60]

## 落盘时刻：unix 秒（UTC）按本机时区偏置转成本地「MM-DD HH:MM」
static func fmt_saved(unix_ts: int) -> String:
	if unix_ts <= 0:
		return "--"
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	var dt := Time.get_datetime_dict_from_unix_time(unix_ts + bias * 60)
	return "%02d-%02d %02d:%02d" % [dt.month, dt.day, dt.hour, dt.minute]