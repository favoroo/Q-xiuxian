class_name SuperAllocDialog
extends LevelUpDialog

## 超级悟道面板（2026-10-25）：继承普通悟道的摆位/选中/防误触流程，只换候选来源与文案。
##
## 五选一（3 张流派 + 2 张通用）、不可刷新；点卡只选中，底部「确认领悟」才落地
## （与普通悟道同一条防误触口径）。场景 SuperAllocDialog.tscn 由 LevelUpDialog.tscn 派生，
## Main 运行时挂到 UILayer 末尾（Main.tscn 是多 Agent 共享场景文件，不往里加节点）。
##
## 生命周期：super_alloc_opened → 亮面板；选完发 super_alloc_finished → 复用基类淡出；
## 面板收起后由 WaveSpawner 接着走普通悟道 / 金币阁。

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
	title_label.text = "超 级 悟 道"
	info_label.text = GameStyle.wrap_cjk(
		"第 %d 回合 · 逆天神通 5 选 1 · 选定不可更改" % maxi(GameManager.wave_number, 1),
		GameStyle.body_font(), 13, _info_room_w())
	reroll_btn.visible = false
	_update_confirm_btn()
	_update_gate_label()

func _update_confirm_btn() -> void:
	confirm_btn.text = "确认领悟 ★"
	confirm_btn.disabled = selected_index < 0 or not _can_interact or _is_confirming
	confirm_btn.custom_minimum_size = Vector2(148, 44)

func _update_gate_label() -> void:
	var list := _offers()
	if selected_index < 0 or selected_index >= list.size():
		gate_label.text = "点中一张卡，再按右侧「确认领悟」 · 流派卡按当前构筑挑选"
		GameStyle.label(gate_label, 13, GameStyle.PAPER_DIM)
	else:
		gate_label.text = "已选【%s】 · 确认后本局永久生效" % String(list[selected_index].get("title", "?"))
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
