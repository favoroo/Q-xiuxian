class_name GameOverDialog
extends Control

## 胜负结算屏（2026-10-14 重制）：分步揭示演出 —— 压暗淡入 → 斜带扫屏 → 标题砸落（定音 sting）
## → 战报数字滚动 → 成就/纪录徽章逐条弹出 → 按钮收尾。胜=金色星屑雨+双金带，败=朱砂暗晕+慢节奏。
## headless 判据环境不播时间轴、直接落终态（LayoutCheck 直接调 _on_game_over 读的就是内容本身）。

@onready var title_label: Label = $CenterContainer/Panel/MarginContainer/VBox/TitleBand/TitleLabel
@onready var stats_label: Label = $CenterContainer/Panel/MarginContainer/VBox/StatsLabel
@onready var retry_btn: Button = $CenterContainer/Panel/MarginContainer/VBox/RetryButton
@onready var endless_btn: Button = $CenterContainer/Panel/MarginContainer/VBox/EndlessButton
@onready var title_band: PanelContainer = $CenterContainer/Panel/MarginContainer/VBox/TitleBand

## 解锁卡尺寸（2026-10-27 收紧）：3 张卡 + 3 条新纪录 + 4 颗按钮同时出现时，
## 旧尺寸（图标 40 / 上下留白 5 / 字号 12+11）会把面板顶到 620 高、整块出 540 屏；
## 图标 30 + 两行字号 11/10 压到约 38 高，两条信息一行不少。
const UNLOCK_CARD_W := 420.0
const UNLOCK_ICON := 30.0

var _menu_btn: Button
var _revive_btn: Button
var _unlocks_box: VBoxContainer
var _records_box: VBoxContainer

## 揭示期交互锁（抄 LevelUpDialog 的 _can_interact：入场未完不许点，防误触）
var _can_interact := false
var _exiting := false
var _victory := false
## 揭示期全部补间的持久句柄：退场时一次杀光，不让迟到 callback 在退出后再动 UI
var _reveal_tweens: Array[Tween] = []
## 氛围层（胜星屑/败暗晕），重开揭示或退场时收掉
var _fx: ResultFx = null

## 战报终值（count-up 的终点，t=1.0 时的读数）
var _r_cult_line := ""
var _r_secs_total := 0
var _r_level := 0
var _r_kills := 0
var _r_stones := 0

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameStyle.label(title_label, 26, GameStyle.INK_TEXT, 0, GameStyle.INK, true)
	GameStyle.label(stats_label, 15, GameStyle.PAPER)
	GameStyle.button(retry_btn, GameStyle.JADE, GameStyle.JADE_EDGE, 18, GameStyle.INK_TEXT)
	GameStyle.button(endless_btn, GameStyle.GOLD, GameStyle.GOLD_EDGE, 16, GameStyle.INK_TEXT)
	# 标题带铺半调网点（胜蓝/败朱砂面上的微芒点阵，垫在标题字底下）
	var strip := GameStyle.halftone(title_band, GameStyle.with_alpha(Color("f2faff"), 0.14))
	title_band.move_child(strip, 0)

	var vbox: VBoxContainer = $CenterContainer/Panel/MarginContainer/VBox
	vbox.add_theme_constant_override("separation", 6)

	_unlocks_box = VBoxContainer.new()
	_unlocks_box.add_theme_constant_override("separation", 4)
	_unlocks_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_unlocks_box.visible = false
	vbox.add_child(_unlocks_box)
	vbox.move_child(_unlocks_box, stats_label.get_index() + 1)

	# 新纪录标签（本局刷新的生涯/道统纪录文案，紧排在成就解锁之后）
	_records_box = VBoxContainer.new()
	_records_box.add_theme_constant_override("separation", 4)
	_records_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_records_box.visible = false
	vbox.add_child(_records_box)
	vbox.move_child(_records_box, _unlocks_box.get_index() + 1)

	_menu_btn = Button.new()
	_menu_btn.text = "返 回 主 菜 单"
	_menu_btn.custom_minimum_size = Vector2(230, 40)
	_menu_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_menu_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(_menu_btn, GameStyle.NAVY2, GameStyle.GOLD, 15, GameStyle.PAPER, 6.0, GameStyle.INK_TEXT)
	_menu_btn.pressed.connect(_on_menu_pressed)
	vbox.add_child(_menu_btn)

	# 原地复活（2026-10-23）：仅败北且有剩余次数时显示，排在重开之前 —— 还魂是首选动作
	_revive_btn = Button.new()
	_revive_btn.text = "原 地 复 活"
	_revive_btn.custom_minimum_size = Vector2(230, 44)
	_revive_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_revive_btn.focus_mode = Control.FOCUS_NONE
	_revive_btn.visible = false
	GameStyle.button(_revive_btn, GameStyle.GOLD, GameStyle.GOLD_EDGE, 18, GameStyle.INK_TEXT)
	_revive_btn.pressed.connect(_on_revive_pressed)
	vbox.add_child(_revive_btn)
	vbox.move_child(_revive_btn, retry_btn.get_index())

	GameManager.game_over_triggered.connect(_on_game_over)
	retry_btn.pressed.connect(_on_retry_pressed)
	endless_btn.pressed.connect(_on_endless_pressed)

func _on_game_over(victory: bool) -> void:
	_victory = victory
	_exiting = false
	AudioManager.play_bgm_key("victory" if victory else "defeat", true)
	title_label.text = "通 关 成 功 ！" if victory else "阵 亡"
	title_band.add_theme_stylebox_override("panel",
		GameStyle.block(GameStyle.GOLD if victory else GameStyle.BAD, GameStyle.SLANT_BAND, Vector2(4, 5)))
	# 胜利主蓝带配墨黑字；朱砂带配暗底亮字（PAPER 已翻转为墨黑，红底上不可再用）
	GameStyle.label(title_label, 26, GameStyle.INK_TEXT if victory else GameStyle.CHALK, 0, GameStyle.INK, true)
	var cdef: Dictionary = CultivatorData.get_def(GameManager.cultivator_id)
	var cname: String = String(cdef.get("name", ""))
	var dname: String = AchievementData.danger_name(GameManager.danger_level)
	var eff_wave := maxi(GameManager.wave_number, GameManager.VICTORY_WAVE if victory else 1)
	_r_cult_line = ("角色 %s · 难度「%s」· 第 %d 波\n" % [cname, dname, eff_wave]) if not cname.is_empty() else ("难度「%s」· 第 %d 波\n" % [dname, eff_wave])
	_r_secs_total = int(GameManager.game_time)
	_r_level = GameManager.level
	_r_kills = GameManager.kills
	_r_stones = GameManager.spirit_stones
	_refresh_unlocks()
	_refresh_records()
	endless_btn.visible = victory and not GameManager.endless_mode
	# 原地复活：仅败北且还有次数可消耗；文案带剩余次数，让玩家知道这是有限资源
	_revive_btn.visible = not victory and GameManager.revive_charges > 0
	_revive_btn.disabled = false
	_revive_btn.text = "原 地 复 活（剩 %d 次）" % GameManager.revive_charges
	visible = true
	get_tree().paused = true

	if DisplayServer.get_name() == "headless":
		# 判据环境：直接落终态，LayoutCheck/soak 读到的内容与不播动画一致
		stats_label.text = _stats_text(1.0)
		modulate.a = 1.0
		_can_interact = true
		return
	_play_reveal()

## 战报文案：t=0 全零 → t=1 终值，数字滚动只改文本不换结构（LayoutCheck 量的是最终布局）。
## 两行封顶（2026-10-27）：解锁卡 + 新纪录 + 四颗按钮同时在场时，第三行会把面板顶出 540 屏。
func _stats_text(t: float) -> String:
	var total := int(roundf(_r_secs_total * t))
	return "%s生存 %02d:%02d · 等级 %d · 击杀 %d · 金币 %d" % [
		_r_cult_line, int(total / 60.0), total % 60,
		int(roundf(_r_level * t)), int(roundf(_r_kills * t)), int(roundf(_r_stones * t))
	]

# ---------------- 分步揭示时间轴 ----------------

func _play_reveal() -> void:
	var pace := 1.0 if _victory else 1.35  # 阵亡节奏整体放慢一拍：讣告不是喜报
	var dim: ColorRect = $DimOverlay
	var panel: Control = $CenterContainer/Panel
	# 续无尽后再结算是二次进场：把上一次的退场态（收缩/淡出/氛围层）全部复位
	panel.scale = Vector2.ONE
	panel.modulate.a = 1.0
	modulate.a = 1.0
	dim.modulate.a = 0.0
	if _fx != null and is_instance_valid(_fx):
		_fx.queue_free()
	_fx = null
	_can_interact = false

	# 氛围层：垫在压暗遮罩之上、面板之下（胜=金色星屑雨，败=朱砂呼吸暗晕）
	_fx = ResultFx.victory_rain(self) if _victory else ResultFx.defeat_gloom(self)
	move_child(_fx, dim.get_index() + 1)

	# 通关加一笔全屏金光（HUD 升级金光的结算位对照）：压在星屑上、面板下，亮完自毁
	if _victory:
		var flash := ColorRect.new()
		flash.color = GameStyle.with_alpha(GameStyle.JADE, 0.20)
		flash.set_anchors_preset(Control.PRESET_FULL_RECT)
		flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flash.set_meta("layout_bleed", true)
		add_child(flash)
		move_child(flash, _fx.get_index() + 1)
		var ftw := _track(flash.create_tween())
		ftw.tween_property(flash, "modulate:a", 0.0, 0.5).set_delay(0.1)
		ftw.tween_callback(flash.queue_free)

	# 扫屏压场：胜利主蓝+点缀黄双带错峰，失败朱砂单带
	GameStyle.slash_wipe(self, GameStyle.GOLD if _victory else GameStyle.BAD)
	if _victory:
		GameStyle.slash_wipe(self, GameStyle.JADE, 0.09)

	# ① 背景压暗淡入（衔接死亡演出/清场，消除硬切）+ 镜头特写平滑回拉至标准视距
	_track(create_tween()).tween_property(dim, "modulate:a", 1.0, 0.3)
	GameManager.release_camera(0.65)
	# ② 标题带砸落 + 定音 sting（胜利/失败各一声，SFX 与 BGM 同 key 不同层）
	GameStyle.pin_center_pivot(title_band)
	title_band.scale = Vector2(1.3, 1.3)
	var ttw := _track(create_tween())
	ttw.tween_interval(0.08 * pace)
	ttw.tween_callback(func(): AudioManager.play_sfx("victory" if _victory else "defeat"))
	ttw.tween_property(title_band, "scale", Vector2.ONE, 0.3)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# ③ 战报数字滚动（生存时长/等级/击杀/金币从 0 数到终值）
	stats_label.text = _stats_text(0.0)
	stats_label.modulate.a = 0.0
	var stw := _track(create_tween())
	stw.tween_interval(0.3 * pace)
	stw.tween_property(stats_label, "modulate:a", 1.0, 0.12)
	stw.tween_method(_write_stats, 0.0, 1.0, 0.7 if _victory else 0.9)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# ④ 成就/纪录徽章逐条弹出（每条带一声轻叩）
	var chips := _all_chips()
	var t_chip := (0.75 if _victory else 1.0) * pace
	for i in range(chips.size()):
		var chip := chips[i]
		chip.modulate.a = 0.0  # 弹出的那一拍才交给 pop_in 回场，别在揭示前抢戏
		var ctw := _track(create_tween())
		ctw.tween_interval(t_chip + i * 0.09)
		ctw.tween_callback(func():
			GameStyle.pop_in(chip)
			AudioManager.play_sfx("stat_alloc", 0.45))
	# ⑤ 按钮组收尾进场，全部落定后才解锁交互
	var btns: Array[Control] = [retry_btn, _menu_btn]
	if endless_btn.visible:
		btns.push_front(endless_btn)
	if _revive_btn.visible:
		btns.push_front(_revive_btn)
	var t_btn := t_chip + chips.size() * 0.09 + 0.15
	for i in range(btns.size()):
		var b := btns[i]
		b.modulate.a = 0.0
		var btw := _track(create_tween())
		btw.tween_interval(t_btn + i * 0.07)
		btw.tween_callback(func(): GameStyle.pop_in(b, 0.0, 0.9))
	var ltw := _track(create_tween())
	ltw.tween_interval(t_btn + btns.size() * 0.07 + 0.15)
	ltw.tween_callback(func(): _can_interact = true)

func _write_stats(t: float) -> void:
	stats_label.text = _stats_text(t)

func _all_chips() -> Array[Control]:
	var out: Array[Control] = []
	for c in _unlocks_box.get_children():
		out.append(c)
	for c in _records_box.get_children():
		out.append(c)
	return out

## 揭示期补间统一入口：登记持久句柄（退场可杀）+ 暂停态照跑（结算屏开着时整树 paused）
func _track(tw: Tween) -> Tween:
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_reveal_tweens.append(tw)
	return tw

func _kill_reveal() -> void:
	for tw in _reveal_tweens:
		if tw.is_valid():
			tw.kill()
	_reveal_tweens.clear()

# ---------------- 退场（重试/回菜单/续无尽共用：收缩淡出后再动作） ----------------

func _exit_to(action: Callable) -> void:
	if _exiting:
		return
	_exiting = true
	_can_interact = false
	_kill_reveal()
	if _fx != null and is_instance_valid(_fx):
		_fx.queue_free()
	_fx = null
	var panel: Control = $CenterContainer/Panel
	if panel.size != Vector2.ZERO:
		panel.pivot_offset = panel.size * 0.5
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_parallel()
	tw.tween_property(self, "modulate:a", 0.0, GameStyle.UI_FADE_OUT + 0.05)
	tw.tween_property(panel, "scale", Vector2(0.96, 0.96), GameStyle.UI_FADE_OUT + 0.05)
	tw.chain().tween_callback(action)

func _refresh_unlocks() -> void:
	for c in _unlocks_box.get_children():
		c.queue_free()
	var newly: Array = GameManager.last_run_new_achievements
	if newly.is_empty():
		_unlocks_box.visible = false
		return
	_unlocks_box.visible = true
	# 区块标题：列表现在装的是「整局」（含回合末横幅已播过的中途解锁），
	# 不给标题玩家会以为只是最后这一下的奖励。溢出条数并进标题，
	# 不再单占一行 —— 3 卡 + 3 纪录 + 4 按钮已经是这一屏的高度上限。
	var head := Label.new()
	var max_show := mini(newly.size(), 3)
	if newly.size() > max_show:
		head.text = "◆ 本 局 解 锁 %d 项（余下 %d 项见「战绩」） ◆" % [
			newly.size(), newly.size() - max_show]
	else:
		head.text = "◆ 本 局 解 锁 ◆"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	GameStyle.label(head, 11, GameStyle.PAPER, 0, GameStyle.INK, true)
	_unlocks_box.add_child(head)
	for i in range(max_show):
		var aid := String(newly[i])
		var adef := AchievementData.get_def(aid)
		if adef.is_empty():
			continue
		_unlocks_box.add_child(_make_unlock_card(adef))

## 单条解锁卡（2026-10-25 解锁提示升级）：图标 + 成就名 + 「新角色/道具/武器：X」+ 右端「新」角签。
## 旧写法只是一行纯文字 chip —— 结算屏是全项目唯一展示解锁的通道，纯文字等于把奖励藏了。
## 图标取成就自己的 icon 字段（以前完全没用上）；尺寸见 UNLOCK_ICON 处的收紧说明。
func _make_unlock_card(adef: Dictionary) -> Control:
	var rtype := String(adef.get("reward_type", ""))
	var label := AchievementData.reward_label(adef)
	var reward_name := String(adef.get("reward_name", ""))

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.custom_minimum_size = Vector2(UNLOCK_CARD_W, 0)
	var sb := GameStyle.block(GameStyle.JADE_DK, GameStyle.SLANT_BLOCK, Vector2(3, 4))
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 3.0
	sb.content_margin_bottom = 3.0
	card.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)

	# 左：奖励对象图标（成就 icon 字段；缺图时留空框，与图鉴卡同一兜底口径）
	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(UNLOCK_ICON, UNLOCK_ICON)
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_box.add_theme_stylebox_override("panel",
		GameStyle.outlined_panel(GameStyle.INK, GameStyle.JADE, 1, 0.0))
	var icon_path := String(adef.get("icon", ""))
	var icon_tex := GameStyle.icon_texture_rect(icon_path, Vector2(UNLOCK_ICON - 4, UNLOCK_ICON - 4))
	icon_box.add_child(icon_tex)
	row.add_child(icon_box)

	# 中：两行文字（成就名 / 解锁了什么）
	var text_box := VBoxContainer.new()
	text_box.add_theme_constant_override("separation", 1)
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(text_box)

	var title_lbl := Label.new()
	title_lbl.text = "成就「%s」" % String(adef.get("name", ""))
	GameStyle.label(title_lbl, 11, GameStyle.CHALK, 0, GameStyle.INK, true)
	text_box.add_child(title_lbl)

	var sub_lbl := Label.new()
	if label.is_empty():
		sub_lbl.text = "达成"
	else:
		sub_lbl.text = "%s：%s" % [label, reward_name]
	GameStyle.label(sub_lbl, 10, GameStyle.JADE)
	text_box.add_child(sub_lbl)

	# 右：「新」角签（与主菜单/选人角标同一枚字，玩家能把它和别处的红点对上）
	var new_chip := Label.new()
	new_chip.text = " 新 "
	new_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	new_chip.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.GOLD))
	GameStyle.label(new_chip, 10, GameStyle.INK_TEXT)
	row.add_child(new_chip)
	return card

## 新纪录标签：本局刷新的生涯/道统纪录（金 chips，最多 3 行）。
## 2026-10-27：首通关一口气能刷出六条（击杀/波次/首胜/境界/难度/皮肤），
## 超额不再另起一行 —— 把第 3 颗签换成汇总签，行数封顶 3。
func _refresh_records() -> void:
	for c in _records_box.get_children():
		c.queue_free()
	var records: Array = GameManager.last_run_new_records
	if records.is_empty():
		_records_box.visible = false
		return
	_records_box.visible = true
	var detailed := mini(records.size(), 3)
	if records.size() > detailed:
		detailed -= 1   # 留最后一格给汇总签
	for i in range(detailed):
		var chip := Label.new()
		chip.text = " ◆ %s ◆ " % String(records[i])
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		chip.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.GOLD))
		GameStyle.label(chip, 11, GameStyle.INK_TEXT)
		_records_box.add_child(chip)
	if records.size() > detailed:
		var more := Label.new()
		more.text = " ◆ 另有 %d 条新纪录 · 见「战绩」 ◆ " % (records.size() - detailed)
		more.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		more.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		more.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.GOLD))
		GameStyle.label(more, 11, GameStyle.INK_TEXT)
		_records_box.add_child(more)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_menu_pressed()
		get_viewport().set_input_as_handled()

func _on_retry_pressed() -> void:
	if not _can_interact:
		return
	if is_instance_valid(retry_btn):
		retry_btn.text = "正在重置..."
		retry_btn.disabled = true
	# 带标记重载：与暂停菜单「重新开始」同路，跳过主菜单直落选角界面
	_exit_to(func():
		get_tree().paused = false
		GameManager.restart_to_select = true
		GameManager.reset_run()
		await get_tree().process_frame
		get_tree().reload_current_scene())

func _on_menu_pressed() -> void:
	if not _can_interact:
		return
	# 与「重新开始」同规格：先画出一帧「正在返回」再同步重载整树，避免按下即冻死（ESC 同路）
	if is_instance_valid(_menu_btn):
		_menu_btn.text = "正在返回..."
		_menu_btn.disabled = true
	_exit_to(func():
		get_tree().paused = false
		GameManager.reset_run()
		await get_tree().process_frame
		get_tree().reload_current_scene())

func _on_endless_pressed() -> void:
	if not _can_interact:
		return
	_exit_to(func():
		visible = false
		AudioManager.play_sfx("level_up", 1.0)
		GameManager.continue_endless())

## 原地复活（2026-10-23）：消耗一次「轮回重生」次数，解除暂停与结算态，
## 由 Player.revive_from_death 完成还魂仪式（凝魂阵→光柱爆发→3 秒无敌）。
func _on_revive_pressed() -> void:
	if not _can_interact:
		return
	if GameManager.revive_charges <= 0:
		_revive_btn.visible = false
		return
	if is_instance_valid(_revive_btn):
		_revive_btn.text = "还 魂 中..."
		_revive_btn.disabled = true
	GameManager.revive_charges -= 1
	_exit_to(func():
		visible = false
		get_tree().paused = false
		GameManager.is_game_over = false
		AudioManager.play_bgm_key(_battle_bgm_key())
		if GameManager.player != null and is_instance_valid(GameManager.player)\
			and GameManager.player.has_method("revive_from_death"):
			GameManager.player.revive_from_death())

## 复活回场续播的战斗 BGM：与 WaveSpawner 开局同一口径（Boss/精英波 trial，其余 battle）
func _battle_bgm_key() -> String:
	var ws: Node = GameManager.wave_spawner
	if ws != null and ws.has_method("current_wave_bgm_key"):
		return String(ws.current_wave_bgm_key())
	return "battle"
