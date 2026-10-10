class_name HudSkillButton
extends Control

## 随行神通按钮：圆形半透明浮动键 + 环形冷却遮罩 + 秒数读数，按下即放（快捷键与触屏双通道）。
## 从 GameHUD 拆出：外观基准在 SkillButtonView，摆位算术在 HudButtonLayout，本层只管构建/输入/冷却轮询/释放反馈。

const BTN_SIZE := SkillButtonView.SKILL_BTN_SIZE

var _btn: Button = null
var _icon_rect: TextureRect = null
var _cd_ring: SkillButtonView.SkillCdOverlay = null
var _cd_label: Label = null
var _name_label: Label = null
var _was_ready: bool = false
var _shaking: bool = false
var _edit_mode: bool = false
var _last_press_frame: int = -1

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(BTN_SIZE, BTN_SIZE)
	_build_button()
	_apply_layout()
	SettingsManager.setting_changed.connect(func(sec: StringName, key: StringName, _val: Variant):
		if sec == &"display" and key in [&"skill_btn_xy", &"skill_btn_scale"]:
			_apply_layout()
	)

## 构建按钮：圆形键体 + 图标 + 环形冷却遮罩 + 秒数 + 神通名
func _build_button() -> void:
	_btn = Button.new()
	_btn.custom_minimum_size = Vector2(BTN_SIZE, BTN_SIZE)
	_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_btn.focus_mode = Control.FOCUS_NONE
	SkillButtonView.style_circle_button(_btn)
	_btn.gui_input.connect(_on_btn_input)
	add_child(_btn)

	_icon_rect = TextureRect.new()
	_icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon_rect.offset_left = 16.0
	_icon_rect.offset_top = 11.0
	_icon_rect.offset_right = -16.0
	_icon_rect.offset_bottom = -21.0
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_rect.visible = false
	_btn.add_child(_icon_rect)

	_cd_ring = SkillButtonView.SkillCdOverlay.new()
	_cd_ring.visible = false
	_btn.add_child(_cd_ring)

	_cd_label = Label.new()
	_cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cd_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cd_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cd_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cd_label.visible = false
	_btn.add_child(_cd_label)
	GameStyle.label(_cd_label, 22, GameStyle.CHALK, 2, GameStyle.INK, true)

	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_name_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_name_label.offset_bottom = -7.0
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameStyle.label(_name_label, 10, GameStyle.JADE_EDGE, 2, GameStyle.INK)
	_btn.add_child(_name_label)

## 引擎 _input 转发入口（由 GameHUD._input 调）：支持触屏第二根手指
## （左手拉摇杆时右手点技能，系统不再发鼠标模拟，走原生 ScreenTouch）
func handle_engine_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		if _is_gameplay_active() and _is_point_on_btn(event.position):
			trigger_press()

func _is_gameplay_active() -> bool:
	if not is_visible_in_tree() or get_tree().paused:
		return false
	if not GameManager.run_started or GameManager.is_game_over:
		return false
	var spawner: Node = GameManager.wave_spawner
	if spawner != null and int(spawner.get("phase")) != int(WaveSpawner.Phase.FIGHT):
		return false
	return true

func _is_point_on_btn(pos: Vector2) -> bool:
	if _btn == null or not is_instance_valid(_btn) or not _btn.is_visible_in_tree():
		return false
	# 圆形热区跟随缩放，半径外扩 8px 触控容错
	var r := BTN_SIZE * SettingsManager.skill_btn_scale() * 0.5 + 8.0
	return pos.distance_to(center_px()) <= r

## 输入处理：触屏与鼠标统一支持，按下即放（0 延迟），解决双指拉摇杆时技能不响应问题
func handle_input(event: InputEvent) -> void:
	var pressed := false
	if event is InputEventScreenTouch:
		pressed = event.pressed
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pressed = event.pressed

	if pressed:
		trigger_press()

## 触发技能释放（含成功弹性反馈与冷却震颤反馈）
func trigger_press() -> void:
	var cur_frame := Engine.get_process_frames()
	if _last_press_frame == cur_frame:
		return
	_last_press_frame = cur_frame

	var player = GameManager.player
	var cast_success := false
	if player != null and player.has_method("try_activate_skill"):
		cast_success = player.try_activate_skill()

	if cast_success:
		_play_cast_fx()
	else:
		_play_reject_fx()

## 释放成功：弹性微缩放 + 脉冲反馈
func _play_cast_fx() -> void:
	if _btn == null:
		return
	_btn.pivot_offset = Vector2(BTN_SIZE * 0.5, BTN_SIZE * 0.5)
	var tw = create_tween()
	tw.tween_property(_btn, "scale", Vector2(0.86, 0.86), 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_btn, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## 冷却中或无法释放：左右微抖 + 倒计时脉冲，明确给玩家反馈“在冷却中”，不再静默无反应
func _play_reject_fx() -> void:
	if _btn == null or _shaking:
		return
	_shaking = true
	var orig_pos := _btn.position
	var tw = create_tween()
	tw.tween_property(_btn, "position:x", orig_pos.x - 5.0, 0.04)
	tw.tween_property(_btn, "position:x", orig_pos.x + 5.0, 0.04)
	tw.tween_property(_btn, "position:x", orig_pos.x, 0.04)
	if _cd_label != null and _cd_label.visible:
		_cd_label.pivot_offset = _cd_label.size * 0.5
		tw.parallel().tween_property(_cd_label, "scale", Vector2(1.25, 1.25), 0.06)
		tw.tween_property(_cd_label, "scale", Vector2.ONE, 0.08)
	tw.tween_callback(func(): _shaking = false)
	AudioManager.play_sfx("ui_error", 0.7)

## 冷却与可见性轮询（每帧）
func _process(_delta: float) -> void:
	var player = GameManager.player
	var show := _edit_mode or (GameManager.run_started and not GameManager.is_game_over and not GameManager.active_skill_id.is_empty())
	if visible != show:
		visible = show
		if show:
			_was_ready = false
			var def := SkillData.get_def(GameManager.active_skill_id)
			var icon_path: String = String(def.get("icon", ""))
			var is_enhanced: bool = SkillData.is_enhanced_for_cultivator(GameManager.active_skill_id, GameManager.cultivator_id)
			if _icon_rect != null:
				if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
					_btn.text = ""
					_icon_rect.texture = load(icon_path)
					_icon_rect.visible = true
					_icon_rect.modulate = GameStyle.JADE_EDGE if is_enhanced else GameStyle.CHALK
				else:
					_icon_rect.visible = false
					_btn.text = String(def.get("glyph", "?"))
			else:
				_btn.text = String(def.get("glyph", "?"))

			var s_name: String = String(def.get("name", ""))
			if _name_label != null:
				_name_label.text = s_name.substr(0, 2)
			SkillButtonView.style_circle_button(_btn)
	if not show or player == null:
		return

	var cd_left: float = player.skill_cd_left
	var cd_total: float = maxf(0.01, player.skill_cd_total)
	var on_cd := cd_left > 0.0
	var ratio := clampf(cd_left / cd_total, 0.0, 1.0)

	_cd_ring.visible = on_cd
	_cd_ring.cd_ratio = ratio
	_cd_ring.queue_redraw()

	_cd_label.visible = on_cd
	if _icon_rect != null and _icon_rect.visible:
		_icon_rect.modulate.a = 0.35 if on_cd else 1.0
	if on_cd:
		_cd_label.text = str(int(ceil(cd_left)))
		_was_ready = false
	elif not _was_ready:
		# 冷却转好：亮一下 + 弹性放大，提醒可以再放
		_was_ready = true
		_btn.pivot_offset = Vector2(BTN_SIZE * 0.5, BTN_SIZE * 0.5)
		var tw = create_tween()
		tw.tween_property(_btn, "scale", Vector2(1.16, 1.16), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(_btn, "scale", Vector2.ONE, 0.14)

## 进入/退出调整模式：强制亮出键体交给覆盖层拖动（树此时是暂停态）
func set_edit_mode(on: bool) -> void:
	_edit_mode = on
	if on and GameManager.active_skill_id.is_empty():
		# 主菜单阶段还没选神通：摆个占位字面，照样能拖
		_btn.text = "技"
		_icon_rect.visible = false
		_name_label.text = ""
	visible = on or (GameManager.run_started and not GameManager.is_game_over and not GameManager.active_skill_id.is_empty())

## 按钮视觉中心（设计坐标，含缩放摆位）
func center_px() -> Vector2:
	return position + pivot_offset

func size_px() -> Vector2:
	return Vector2(BTN_SIZE, BTN_SIZE)

## 冷却中点击的震颤反馈是否正在播放（判据读）
func is_shaking() -> bool:
	return _shaking

func get_btn() -> Button:
	return _btn

func _apply_layout() -> void:
	HudButtonLayout.apply(self, SettingsManager.skill_btn_xy(), SettingsManager.skill_btn_scale(), Vector2(BTN_SIZE, BTN_SIZE))

func _on_btn_input(event: InputEvent) -> void:
	handle_input(event)
