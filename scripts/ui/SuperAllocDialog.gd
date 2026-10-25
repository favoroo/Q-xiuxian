class_name SuperAllocDialog
extends LevelUpDialog

## 超级悟道面板（2026-10-25）：继承普通悟道的摆位/选中/防误触流程，只换候选来源与文案。
##
## 「三道」体系：候选按道途出（剑道/箭道/雷法/体修/五行/灵兽），每张卡带阶段。
## 第一次超级悟道只能开道；第二次必出「延续」（已行之道的下一阶段）+ 一张新道；
## 第三次出大成，或手握两条道时出共鸣。一局三次形成一条线，上次选什么直接决定这次能选什么。
## 不可刷新；点卡只选中，底部「确认领悟」才落地（与普通悟道同一条防误触口径）。
## 场景 SuperAllocDialog.tscn 由 LevelUpDialog.tscn 派生，Main 运行时挂到 UILayer 末尾
## （Main.tscn 是多 Agent 共享场景文件，不往里加节点）。
##
## 生命周期：super_alloc_opened → 亮面板；选完发 super_alloc_finished → 复用基类淡出；
## 面板收起后由 WaveSpawner 接着走普通悟道 / 金币阁。

## 底部机制说明签：基类已删底部读数（普通悟道空实现钩子），本场景 tscn 独立完整、
## GateLabel 节点仍在，这里自持引用并重写钩子，只放界面上没有的机制说明。
@onready var gate_label: Label = $CenterContainer/Panel/MarginContainer/VBox/ActionBar/GateLabel

func _ready() -> void:
	super._ready()
	# 基类 _ready 挂的是普通悟道两路信号：这一屏只认超级悟道两路，先摘干净
	if GameManager.alloc_opened.is_connected(_on_alloc_opened):
		GameManager.alloc_opened.disconnect(_on_alloc_opened)
	if GameManager.alloc_finished.is_connected(_on_alloc_finished):
		GameManager.alloc_finished.disconnect(_on_alloc_finished)
	GameManager.super_alloc_opened.connect(_on_super_alloc_opened)
	GameManager.super_alloc_finished.connect(_on_alloc_finished)
	# 这一屏没有刷新（不可刷新）与「待加点次数」概念：两颗专属控件藏掉
	if reroll_btn != null:
		reroll_btn.visible = false
	if _points_badge != null:
		_points_badge.visible = false

func _offers() -> Array:
	return GameManager.super_alloc_offers

func _card_columns() -> int:
	return maxi(GameManager.super_alloc_offers.size(), 1)

## 与基类 _on_alloc_opened 同一条入场时序（停摇杆 / 先摆位再亮 / 只淡内容层 / 0.14s 防误触）
func _on_super_alloc_opened() -> void:
	if GameManager.joystick != null and GameManager.joystick.has_method("_stop_joystick"):
		GameManager.joystick._stop_joystick()
	_can_interact = false
	_is_confirming = false
	selected_index = -1
	_layout_for_viewport()
	_refresh()
	visible = true
	get_tree().paused = true
	modulate.a = 1.0
	content.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(content, "modulate:a", 1.0, GameStyle.UI_FADE_IN)
	tw.tween_interval(0.14)
	tw.tween_callback(func(): _can_interact = true)

func _refresh_bars() -> void:
	# 顶栏回合徽条已下线（2026-10-25，随基类一起）：回合数 HUD 有、「5 选 1」卡面自明，
	# 已行道途进度改由底部说明签承载（_update_gate_label）。
	title_label.text = "超 级 悟 道"
	reroll_btn.visible = false
	_update_confirm_btn()
	_update_gate_label()

## 已行道途一栏：「已行：雷法 ×2 · 箭道 ×1」；还没开道时返回空串。
func _lane_progress_text() -> String:
	var counts := SuperUpgradeData.lane_counts(GameManager)
	var parts: PackedStringArray = []
	for line_key in SuperUpgradeData.LINE_LABELS.keys():
		var n := int(counts.get(String(line_key), 0))
		if n > 0:
			parts.append("%s ×%d" % [SuperUpgradeData.line_label(String(line_key)), n])
	return "" if parts.is_empty() else "已行：%s" % " · ".join(parts)

func _update_confirm_btn() -> void:
	confirm_btn.text = "确认领悟 ★"
	confirm_btn.disabled = selected_index < 0 or not _can_interact or _is_confirming
	confirm_btn.custom_minimum_size = Vector2(148, 44)

func _update_gate_label() -> void:
	# 「已选哪张」由卡片金框 +「已选 ★」角标表达，不再回念；这里只留机制说明，
	# 未选中时顺带挂已行道途进度（顶栏徽条下线后这是它唯一读数位，2026-10-25）。
	if selected_index < 0 or selected_index >= _offers().size():
		var progress := _lane_progress_text()
		gate_label.text = "三次悟道各开一道，选定不可更改" if progress.is_empty() \
			else "%s，选过的道途会延续出下一阶段" % progress
		GameStyle.label(gate_label, 13, GameStyle.PAPER_DIM)
	else:
		var card: Dictionary = _offers()[selected_index]
		var chip := String(card.get("lane_chip", ""))
		gate_label.text = "确认后本局永久生效" if chip.is_empty() else "%s · 确认后本局永久生效" % chip
		GameStyle.label(gate_label, 13, GameStyle.JADE_DK)

## 超级悟道不可刷新（按钮已隐藏，这里再兜一层防误触）
func _on_reroll() -> void:
	pass

func _on_confirm_pick() -> void:
	if not _can_interact or _is_confirming or selected_index < 0:
		return
	if GameManager.super_alloc_offers.is_empty():
		return
	_is_confirming = true
	_can_interact = false
	# take 内部：赠送神通 → 记账 → 发 super_alloc_finished（面板淡出、流程回到回合间隙闸口）
	var ok := SuperAllocSession.take(GameManager, selected_index)
	_is_confirming = false
	if not ok:
		AudioManager.play_sfx("ui_error", 0.9)
		_can_interact = true
