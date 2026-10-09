class_name GameOverDialog
extends Control

@onready var title_label: Label = $CenterContainer/Panel/MarginContainer/VBox/TitleBand/TitleLabel
@onready var stats_label: Label = $CenterContainer/Panel/MarginContainer/VBox/StatsLabel
@onready var retry_btn: Button = $CenterContainer/Panel/MarginContainer/VBox/RetryButton
@onready var endless_btn: Button = $CenterContainer/Panel/MarginContainer/VBox/EndlessButton
@onready var title_band: PanelContainer = $CenterContainer/Panel/MarginContainer/VBox/TitleBand

var _menu_btn: Button
var _unlocks_box: VBoxContainer

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameStyle.label(title_label, 26, GameStyle.PAPER, 0, GameStyle.INK, true)
	GameStyle.label(stats_label, 15, GameStyle.PAPER)
	GameStyle.button(retry_btn, GameStyle.JADE, GameStyle.PAPER, 18, GameStyle.INK_TEXT)
	GameStyle.button(endless_btn, GameStyle.GOLD, GameStyle.GOLD_EDGE, 16, GameStyle.INK_TEXT)
	# 标题带铺半调网点（胜金/败朱砂面上的印刷味，压暗点阵两种底都读得出；垫在标题字底下）
	var strip := GameStyle.halftone(title_band, Color(0.08, 0.07, 0.04, 0.16))
	title_band.move_child(strip, 0)

	var vbox: VBoxContainer = $CenterContainer/Panel/MarginContainer/VBox
	vbox.add_theme_constant_override("separation", 10)

	_unlocks_box = VBoxContainer.new()
	_unlocks_box.add_theme_constant_override("separation", 4)
	_unlocks_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_unlocks_box.visible = false
	vbox.add_child(_unlocks_box)
	vbox.move_child(_unlocks_box, stats_label.get_index() + 1)

	_menu_btn = Button.new()
	_menu_btn.text = "返 回 主 菜 单"
	_menu_btn.custom_minimum_size = Vector2(230, 40)
	_menu_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_menu_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(_menu_btn, GameStyle.NAVY2, GameStyle.GOLD, 15, GameStyle.PAPER)
	_menu_btn.pressed.connect(_on_menu_pressed)
	vbox.add_child(_menu_btn)

	GameManager.game_over_triggered.connect(_on_game_over)
	retry_btn.pressed.connect(_on_retry_pressed)
	endless_btn.pressed.connect(_on_endless_pressed)

func _on_game_over(victory: bool) -> void:
	title_label.text = "渡 劫 成 功 ！" if victory else "道 消 身 殒"
	title_band.add_theme_stylebox_override("panel",
		GameStyle.block(GameStyle.GOLD if victory else GameStyle.BAD, GameStyle.SLANT_BAND, Vector2(4, 5)))
	# 鎏金带面上纸白字会洗白，胜利用墨黑字；朱砂带上保留纸白
	GameStyle.label(title_label, 26, GameStyle.INK_TEXT if victory else GameStyle.PAPER, 0, GameStyle.INK, true)
	var mins := int(GameManager.game_time / 60.0)
	var secs := int(GameManager.game_time) % 60
	var cdef: Dictionary = CultivatorData.get_def(GameManager.cultivator_id)
	var cname: String = String(cdef.get("name", ""))
	var dname: String = AchievementData.danger_name(GameManager.danger_level)
	var eff_wave := maxi(GameManager.wave_number, GameManager.VICTORY_WAVE if victory else 1)
	var cult_line: String = ("道统 %s · 危险度「%s」· 第 %d 波\n" % [cname, dname, eff_wave]) if not cname.is_empty() else ("危险度「%s」· 第 %d 波\n" % [dname, eff_wave])
	stats_label.text = "%s镇守时长 %02d:%02d · 境界 Lv.%d\n斩妖 %d 只 · 囊中灵石 %d 枚" % [
		cult_line, mins, secs, GameManager.level, GameManager.kills, GameManager.spirit_stones
	]
	_refresh_unlocks()
	endless_btn.visible = victory and not GameManager.endless_mode
	visible = true
	get_tree().paused = true
	modulate.a = 0.0
	var tw = create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.25)
	# 开场一条斜带扫过（胜金败朱砂），压场用
	GameStyle.slash_wipe(self, GameStyle.GOLD if victory else GameStyle.BAD)

func _refresh_unlocks() -> void:
	for c in _unlocks_box.get_children():
		c.queue_free()
	var newly: Array = GameManager.last_run_new_achievements
	if newly.is_empty():
		_unlocks_box.visible = false
		return
	_unlocks_box.visible = true
	var max_show := mini(newly.size(), 3)
	for i in range(max_show):
		var aid := String(newly[i])
		var adef := AchievementData.get_def(aid)
		if adef.is_empty():
			continue
		var rtype := String(adef.get("reward_type", ""))
		var rname := String(adef.get("reward_name", ""))
		var prefix := "新道统解锁" if rtype == "cultivator" else "新法宝入阁"
		var chip := Label.new()
		chip.text = " ✦ 功绩「%s」· %s：%s ✦ " % [adef.get("name", ""), prefix, rname]
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		chip.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.JADE_DK))
		GameStyle.label(chip, 12, GameStyle.JADE)
		_unlocks_box.add_child(chip)
	if newly.size() > max_show:
		var more := Label.new()
		more.text = "（另有 %d 项功绩达成，可于主菜单「修仙志」查阅）" % (newly.size() - max_show)
		more.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		GameStyle.label(more, 11, GameStyle.PAPER_DIM)
		_unlocks_box.add_child(more)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_menu_pressed()
		get_viewport().set_input_as_handled()

func _on_retry_pressed() -> void:
	get_tree().paused = false
	GameManager.reset_run()
	get_tree().reload_current_scene()

func _on_menu_pressed() -> void:
	get_tree().paused = false
	GameManager.reset_run()
	get_tree().reload_current_scene()

func _on_endless_pressed() -> void:
	visible = false
	AudioManager.play_sfx("level_up", 1.0)
	GameManager.continue_endless()
