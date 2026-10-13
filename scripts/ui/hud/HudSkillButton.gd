class_name HudSkillButton
extends Control

## 随行技能 / 额外技能按钮：圆形半透明浮动键 + 环形冷却遮罩 + 秒数读数，按下即放（快捷键与触屏双通道）。
## 一套类两颗键：主键读 active_skill_id（带冷却），额外键读 extra_skill_id（随角色绑定，如影爆——
## 免冷却、由影层门控，影层角标「影 N」归它）。从 GameHUD 拆出：外观基准在 SkillButtonView，
## 摆位算术在 HudButtonLayout，本层只管构建/输入/冷却轮询/释放反馈。

const BTN_SIZE := SkillButtonView.SKILL_BTN_SIZE

## 额外技能键的键面占位文案：还没进局、或该角色没配额外技能时，这颗键平时是隐藏的，
## 只有「按钮调整模式」要把它亮出来当拖动靶子。用户 2026-10-11：原先写英文 "extra"，
## 看不出那是颗什么键 ⇒ 改成「额外技能」。四个字一行收不进 76 圆面（28 号四汉字宽约 112，
## 圆面去掉描边只剩 72），按祭坛键同一口径分两行 + 18 号；口径由 UnitRunner 钉。
const EXTRA_BTN_TEXT := "额外\n技能"
const EXTRA_BTN_FONT := 18

## 槽位绑定：false = 主随行技能键（读 active_skill_id）；true = 额外技能键（读 extra_skill_id，
## 随角色绑定，如影者的影爆——免冷却、由影层层数门控，影层角标「影 N」也归这颗键）
var bind_extra: bool = false

var _btn: Button = null
var _icon_rect: TextureRect = null
var _cd_ring: SkillButtonView.SkillCdOverlay = null
var _cd_label: Label = null
var _name_label: Label = null
var _shadow_chip: Label = null   ## 充能角标（影爆=影层读数，服丹=药池读数；读数与账本同源）
var _shadow_shown: int = -1      ## 上一次画出去的层数：只在变了时重设样式，不每帧刷
var _was_ready: bool = false
var _face_state: int = -1  ## 键面读数态：-1 就绪 / 0 冷却 / 1 效果活跃（只在变化时刷读数配色）
var _shaking: bool = false
var _edit_mode: bool = false
var _last_press_frame: int = -1

func _init(extra_slot: bool = false) -> void:
	bind_extra = extra_slot

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(BTN_SIZE, BTN_SIZE)
	_build_button()
	_apply_layout()
	SettingsManager.setting_changed.connect(func(sec: StringName, key: StringName, _val: Variant):
		if sec == &"display" and key in [_xy_key(), _scale_key()]:
			_apply_layout()
	)

## 本键绑定的槽位 → 设置项/技能 id 的取数口径（主键与额外键各认各的，不串账）
func _xy_key() -> StringName:
	return &"extra_btn_xy" if bind_extra else &"skill_btn_xy"

func _scale_key() -> StringName:
	return &"extra_btn_scale" if bind_extra else &"skill_btn_scale"

func _skill_id() -> String:
	return GameManager.extra_skill_id if bind_extra else GameManager.active_skill_id

## 构建按钮：圆形键体 + 图标 + 环形冷却遮罩 + 秒数 + 技能名
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

	# 影层角标：数字贴在键的右上角（拇指旁边看得见），角色头顶同时画等量残影——
	# 两处同一个数，键上给准确层数、身上给"我攒了多少"的形状。
	_shadow_chip = Label.new()
	_shadow_chip.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_shadow_chip.offset_left = -46.0
	_shadow_chip.offset_right = -1.0
	_shadow_chip.offset_top = 1.0
	_shadow_chip.offset_bottom = 21.0
	_shadow_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shadow_chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_shadow_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shadow_chip.visible = false
	_btn.add_child(_shadow_chip)

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
	var scale_f: float = SettingsManager.extra_btn_scale() if bind_extra else SettingsManager.skill_btn_scale()
	var r := BTN_SIZE * scale_f * 0.5 + 8.0
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
	if player != null:
		# 主键走随行技能入口，额外键走额外技能入口（各自校验各自的门控）
		if bind_extra:
			cast_success = player.try_activate_extra_skill() if player.has_method("try_activate_extra_skill") else false
		else:
			cast_success = player.try_activate_skill() if player.has_method("try_activate_skill") else false

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
	var sid := _skill_id()
	var show := _edit_mode or (GameManager.run_started and not GameManager.is_game_over and not sid.is_empty())
	if visible != show:
		visible = show
		if show:
			_was_ready = false
			var def := SkillData.get_def(sid)
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

	# 冷却/活跃账本只归主技能键：额外键（影爆类）免冷却、由影层门控，读主键的账就是串台
	var cd_left: float = 0.0
	var cd_total: float = 1.0
	var active_left: float = 0.0
	var active_total: float = 1.0
	if not bind_extra:
		active_left = player.skill_active_left
		active_total = maxf(0.01, player.skill_active_total)
		cd_left = player.skill_cd_left
		cd_total = maxf(0.01, player.skill_cd_total)
	var on_active := active_left > 0.0
	var on_cd := cd_left > 0.0

	# 三态键面：效果活跃（点缀黄环倒数、图标全亮，冷却还没开始）→ 冷却（暗环倒数、图标压暗）→ 就绪
	_cd_ring.visible = on_active or on_cd
	_cd_ring.active_ratio = clampf(active_left / active_total, 0.0, 1.0) if on_active else 0.0
	_cd_ring.cd_ratio = clampf(cd_left / cd_total, 0.0, 1.0) if on_cd else 0.0
	_cd_ring.queue_redraw()

	var state := 1 if on_active else (0 if on_cd else -1)
	if state != _face_state:
		_face_state = state
		if _cd_label != null:
			# 活跃读数走点缀黄，与冷却纸白区分：同一颗读数，两种账
			_cd_label.add_theme_color_override("font_color", GameStyle.JADE if state == 1 else GameStyle.CHALK)

	_cd_label.visible = on_active or on_cd
	if _icon_rect != null and _icon_rect.visible:
		_icon_rect.modulate.a = 0.35 if on_cd else 1.0
	if on_active:
		_cd_label.text = str(int(ceil(active_left)))
		_was_ready = false
	elif on_cd:
		_cd_label.text = str(int(ceil(cd_left)))
		_was_ready = false
	elif not _was_ready:
		# 冷却转好：亮一下 + 弹性放大，提醒可以再放
		_was_ready = true
		_btn.pivot_offset = Vector2(BTN_SIZE * 0.5, BTN_SIZE * 0.5)
		var tw = create_tween()
		tw.tween_property(_btn, "scale", Vector2(1.16, 1.16), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(_btn, "scale", Vector2.ONE, 0.14)
	_update_shadow_chip(player)

## 额外技能充能角标：影爆读影层（Player.shadow_ring），服丹读药池存量（GameManager.elixir_pool）。
## 攒上才出现，攒满直接换成可释放的亮面（不靠闪一下提示——看不见等于没做）。
## 读数都现读账本本身，不在这里另记一份。只归额外技能键：主技能键不挂这颗角标。
func _update_shadow_chip(player: Node) -> void:
	if _shadow_chip == null:
		return
	if not bind_extra:
		_shadow_chip.visible = false
		return
	# 服丹：药池读数（绿系，与影层的幽夜紫区分开）
	if GameManager.extra_skill_id == "elixir":
		var max_hp := 1.0
		var hp_val = player.get("max_health")
		if hp_val is float or hp_val is int:
			max_hp = float(hp_val)
		var pool := GameManager.elixir_pool
		var shown_pool := int(round(pool))
		if shown_pool == _shadow_shown:
			return
		_shadow_shown = shown_pool
		var pool_full: bool = pool >= ElixirData.cap_of(max_hp) - 0.01
		_shadow_chip.visible = shown_pool > 0
		if shown_pool <= 0:
			return
		_shadow_chip.text = "药 %d" % shown_pool
		_shadow_chip.add_theme_stylebox_override("normal",
			GameStyle.chip(GameStyle.GOOD if pool_full else GameStyle.GOOD_DK))
		GameStyle.label(_shadow_chip, 10, GameStyle.INK_TEXT if pool_full else GameStyle.GOOD)
		return
	# 影爆：影层读数
	var stacks := 0
	var ring = player.get("shadow_ring")
	if ring is Array:
		stacks = (ring as Array).size()
	if stacks == _shadow_shown:
		return
	_shadow_shown = stacks
	var full: bool = stacks >= ShadowStepData.MAX_STACKS
	_shadow_chip.visible = stacks > 0
	if stacks <= 0:
		return
	_shadow_chip.text = "影 %d" % stacks
	_shadow_chip.add_theme_stylebox_override("normal",
		GameStyle.chip(GameStyle.SHADOW if full else GameStyle.SHADOW_DK))
	GameStyle.label(_shadow_chip, 10, GameStyle.INK_TEXT if full else GameStyle.SHADOW_EDGE)

## 进入/退出调整模式：强制亮出键体交给覆盖层拖动（树此时是暂停态）
func set_edit_mode(on: bool) -> void:
	_edit_mode = on
	if on and _skill_id().is_empty():
		# 还没进局/该槽位无技能：摆个占位字面，照样能拖
		_btn.text = EXTRA_BTN_TEXT if bind_extra else "技"
		SkillButtonView.style_circle_button(_btn, EXTRA_BTN_FONT if bind_extra else SkillButtonView.SKILL_BTN_FONT)
		_icon_rect.visible = false
		_name_label.text = ""
	visible = on or (GameManager.run_started and not GameManager.is_game_over and not _skill_id().is_empty())

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
	var xy: Vector2 = SettingsManager.extra_btn_xy() if bind_extra else SettingsManager.skill_btn_xy()
	var scale_f: float = SettingsManager.extra_btn_scale() if bind_extra else SettingsManager.skill_btn_scale()
	HudButtonLayout.apply(self, xy, scale_f, Vector2(BTN_SIZE, BTN_SIZE))

func _on_btn_input(event: InputEvent) -> void:
	handle_input(event)
