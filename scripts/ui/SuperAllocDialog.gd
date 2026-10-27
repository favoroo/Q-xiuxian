class_name SuperAllocDialog
extends LevelUpDialog

## 飞升悟道面板（原超级悟道，2026-10-26 改名）：继承普通悟道的摆位/选中/防误触流程，
## 只换候选来源、文案与一套专属赤红皮。
##
## 候选来源（2026-10-26 去阶段门控）：全表 − 已拿过 − 未过闸（灵兽卡要手上已有灵兽、
## 共鸣卡要两条道各 ≥1 张）里加权随机五选一 —— 没有「先开道才轮到进阶」的顺序解锁，
## 每一屏抽到什么就是什么。不可刷新；点卡只选中，底部「确认领悟」才落地
## （与普通悟道同一条防误触口径）。
## 场景 SuperAllocDialog.tscn 由 LevelUpDialog.tscn 派生，Main 运行时挂到 UILayer 末尾
## （Main.tscn 是多 Agent 共享场景文件，不往里加节点）。
##
## 生命周期：super_alloc_opened → 亮面板；选完发 super_alloc_finished → 复用基类淡出；
## 面板收起后由 WaveSpawner 接着走普通悟道 / 金币阁。
##
## 与普通悟道的视觉区分（2026-10-26，两层）：
## ① 面板层 —— 标题带、确认键、面板外框一律逆天赤红（本文件 _apply_super_palette 重涂）；
## ② 卡面层 —— LevelUpCardFactory 按 payload 的 is_super 染淡红卡底 + 加粗红框 + 红图标框。

## 底部机制说明签：基类已删底部读数（普通悟道空实现钩子），本场景 tscn 独立完整、
## GateLabel 节点仍在，这里自持引用并重写钩子，只放界面上没有的机制说明。
@onready var gate_label: Label = $CenterContainer/Panel/MarginContainer/VBox/ActionBar/GateLabel
## 标题带在基类 _setup_top_bar 里被移进 TopBar（VBox/TitleBand → VBox/TopBar/TitleBand），
## 所以这里不能在 @onready 里写死路径，_apply_super_palette 现取。
var title_band: PanelContainer = null

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
	_apply_super_palette()

## 面板级赤红皮：基类 _ready 已把标题带重涂成主题色并登记进主题回放表，
## 这里换成逆天赤红（飞升专属色，不随玩家主题色变 —— 所以用新 StyleBoxFlat 覆盖、
## 不再登记，主题切换时它保持红）。
func _apply_super_palette() -> void:
	title_band = get_node_or_null(
		"CenterContainer/Panel/MarginContainer/VBox/TopBar/TitleBand") as PanelContainer
	if title_band != null:
		var tb_sb := title_band.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		tb_sb.bg_color = GameStyle.RARITY_MYTHIC
		title_band.add_theme_stylebox_override("panel", tb_sb)
	# 红底配纸白大字（on_face_text 按面色明暗自动判，深红面上给亮字）
	GameStyle.label(title_label, 22, GameStyle.on_face_text(GameStyle.RARITY_MYTHIC), 0, GameStyle.INK, true)
	GameStyle.button(confirm_btn, GameStyle.RARITY_MYTHIC, GameStyle.RARITY_MYTHIC.lightened(0.18),
		16, GameStyle.CHALK, 6.0)
	if panel != null:
		var p_sb := panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		p_sb.border_color = GameStyle.RARITY_MYTHIC
		panel.add_theme_stylebox_override("panel", p_sb)

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
	title_label.text = "飞 升 悟 道"
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
	# 「已选哪张」由卡片描边 +「已选 ★」角标表达，不再回念；这里只留机制说明，
	# 未选中时顺带挂已行道途进度（顶栏徽条下线后这是它唯一读数位，2026-10-25）。
	if selected_index < 0 or selected_index >= _offers().size():
		var progress := _lane_progress_text()
		gate_label.text = "飞升五选一，选定不可更改" if progress.is_empty() \
			else "%s，选定不可更改" % progress
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
