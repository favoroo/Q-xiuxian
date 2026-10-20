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
var _last_cd_visible: bool = false
var _last_drawn_act_ratio: float = -1.0
var _last_drawn_cd_ratio: float = -1.0
var _cd_clip: Control = null     ## 倒计时数字裁切视窗（保证滚动上下溢出时被圆键平滑截断）
var _cd_label_next: Label = null ## 滚动翻滚交替 Label（双 Label 平滑上下滚筒轮换）
var _active_cd_lbl: Label = null ## 当前正处于展示状态的活动 Label
var _roll_tween: Tween = null    ## 滚动刷新补间
var _last_shown_sec: int = -1    ## 上一次画出去的整数秒
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
	# 主题色变更：圆形键的描边/按压面是手搓 StyleBox，重跑一遍样式工厂拿新色
	SettingsManager.theme_color_changed.connect(func(_p: StringName) -> void:
		if _btn != null:
			SkillButtonView.style_circle_button(_btn)
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

	# 倒计时数字滚动视窗：带有裁切（clip_contents），数字垂直翻滚时平滑出入
	_cd_clip = Control.new()
	_cd_clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cd_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cd_clip.clip_contents = true
	_cd_clip.visible = false
	_btn.add_child(_cd_clip)

	_cd_label = Label.new()
	_cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cd_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cd_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cd_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cd_label.visible = false
	GameStyle.label(_cd_label, 22, GameStyle.CHALK, 2, GameStyle.INK, true)
	_cd_clip.add_child(_cd_label)

	_cd_label_next = Label.new()
	_cd_label_next.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cd_label_next.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cd_label_next.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cd_label_next.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cd_label_next.visible = false
	GameStyle.label(_cd_label_next, 22, GameStyle.CHALK, 2, GameStyle.INK, true)
	_cd_clip.add_child(_cd_label_next)

	_active_cd_lbl = _cd_label

	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_name_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_name_label.offset_bottom = -7.0
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameStyle.label(_name_label, 10, GameStyle.with_alpha(GameStyle.CHALK, 0.75), 1, GameStyle.with_alpha(GameStyle.INK, 0.70))
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
	var tw = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(_btn, "scale", Vector2(0.86, 0.86), 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_btn, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## 冷却中或无法释放：左右微抖 + 倒计时脉冲，明确给玩家反馈“在冷却中”，不再静默无反应
func _play_reject_fx() -> void:
	if _btn == null or _shaking:
		return
	_shaking = true
	var orig_pos := _btn.position
	var tw = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(_btn, "position:x", orig_pos.x - 5.0, 0.04)
	tw.tween_property(_btn, "position:x", orig_pos.x + 5.0, 0.04)
	tw.tween_property(_btn, "position:x", orig_pos.x, 0.04)
	var active_lbl: Label = _active_cd_lbl if _active_cd_lbl != null else _cd_label
	if active_lbl != null and active_lbl.visible and _cd_clip != null and _cd_clip.visible:
		active_lbl.pivot_offset = active_lbl.size * 0.5
		tw.parallel().tween_property(active_lbl, "scale", Vector2(1.25, 1.25), 0.06)
		tw.tween_property(active_lbl, "scale", Vector2.ONE, 0.08)
	tw.tween_callback(func(): _shaking = false)
	AudioManager.play_sfx("ui_error", 0.7)

## 立即展示指定数字（用于刚进冷却/活跃状态的第一帧，不滚动，直接显现）
func _show_cd_instant(sec: int, col: Color) -> void:
	if _roll_tween != null and _roll_tween.is_valid():
		_roll_tween.kill()
	_roll_tween = null
	_last_shown_sec = sec
	_cd_clip.visible = true
	var cur: Label = _active_cd_lbl if _active_cd_lbl != null else _cd_label
	cur.text = str(sec)
	cur.add_theme_color_override("font_color", col)
	cur.position = Vector2.ZERO
	cur.scale = Vector2.ONE
	cur.modulate.a = 1.0
	cur.visible = true
	var other: Label = _cd_label_next if cur == _cd_label else _cd_label
	if other != null:
		other.visible = false
		other.position = Vector2.ZERO
		other.modulate.a = 0.0

## 滚动刷新到新秒数（数字垂直向上翻滚滑动：旧数字向上滑出并淡出，新数字从下方滑入居中并淡入）
func _roll_to_sec(new_sec: int, col: Color) -> void:
	if new_sec == _last_shown_sec:
		return
	var old_sec := _last_shown_sec
	_last_shown_sec = new_sec

	if not _cd_clip.visible or old_sec <= 0:
		_show_cd_instant(new_sec, col)
		return

	if _roll_tween != null and _roll_tween.is_valid():
		_roll_tween.kill()

	var out_lbl: Label = _active_cd_lbl if _active_cd_lbl != null else _cd_label
	var in_lbl: Label = _cd_label_next if out_lbl == _cd_label else _cd_label

	# 准备即将滚入的新数字
	in_lbl.text = str(new_sec)
	in_lbl.add_theme_color_override("font_color", col)
	in_lbl.visible = true
	# 从正下方偏移 18px 入场，初始透明
	in_lbl.position = Vector2(0.0, 18.0)
	in_lbl.modulate.a = 0.0
	in_lbl.pivot_offset = in_lbl.size * 0.5
	in_lbl.scale = Vector2(1.15, 1.15) if new_sec <= 3 else Vector2.ONE

	out_lbl.pivot_offset = out_lbl.size * 0.5

	_roll_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	# 旧数字向上平滑滚出并淡出
	_roll_tween.parallel().tween_property(out_lbl, "position:y", -18.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_roll_tween.parallel().tween_property(out_lbl, "modulate:a", 0.0, 0.12)
	# 新数字从下方滚入居中并淡入
	_roll_tween.parallel().tween_property(in_lbl, "position:y", 0.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_roll_tween.parallel().tween_property(in_lbl, "modulate:a", 1.0, 0.12)
	if new_sec <= 3:
		# 最后 3 秒给一个轻快的弹性回落，倒计时紧凑感拉满
		_roll_tween.parallel().tween_property(in_lbl, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var self_ref := self
	_roll_tween.tween_callback(func() -> void:
		if not is_instance_valid(self_ref):
			return
		out_lbl.visible = false
		out_lbl.position = Vector2.ZERO
		out_lbl.scale = Vector2.ONE
		in_lbl.position = Vector2.ZERO
		in_lbl.scale = Vector2.ONE
	)
	_active_cd_lbl = in_lbl

## 倒计时结束消散并触发就绪动画
func _hide_cd_display(play_ready_anim: bool) -> void:
	if _roll_tween != null and _roll_tween.is_valid():
		_roll_tween.kill()
	_last_shown_sec = -1
	if _cd_clip.visible:
		var cur: Label = _active_cd_lbl if _active_cd_lbl != null else _cd_label
		if cur != null and cur.visible:
			cur.pivot_offset = cur.size * 0.5
			_roll_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			_roll_tween.parallel().tween_property(cur, "position:y", -16.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_roll_tween.parallel().tween_property(cur, "modulate:a", 0.0, 0.12)
			_roll_tween.parallel().tween_property(cur, "scale", Vector2(0.8, 0.8), 0.12)
			_roll_tween.tween_callback(func() -> void:
				_cd_clip.visible = false
				cur.position = Vector2.ZERO
				cur.scale = Vector2.ONE
				cur.modulate.a = 1.0
			)
		else:
			_cd_clip.visible = false

	if play_ready_anim:
		_play_ready_fx()

## 冷却转好：弹性放大 + 恢复高亮，提醒玩家技能可放
func _play_ready_fx() -> void:
	if _btn == null:
		return
	_btn.pivot_offset = Vector2(BTN_SIZE * 0.5, BTN_SIZE * 0.5)
	var tw = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(_btn, "scale", Vector2(1.16, 1.16), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_btn, "scale", Vector2.ONE, 0.14)
	if _icon_rect != null and _icon_rect.visible:
		_icon_rect.modulate.a = 1.0

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
			if _icon_rect != null:
				if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
					_btn.text = ""
					_icon_rect.texture = load(icon_path)
					_icon_rect.visible = true
					_icon_rect.modulate = GameStyle.CHALK
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
		if _face_state != -1:
			_face_state = -1
			_last_shown_sec = -1
			if _roll_tween != null and _roll_tween.is_valid():
				_roll_tween.kill()
			if _cd_clip != null:
				_cd_clip.visible = false
		return

	# 冷却/活跃账本：主键读 skill_cd_*，额外键读 extra_skill_cd_*（药爆等带 CD 的额外技能）
	var cd_left: float = 0.0
	var cd_total: float = 1.0
	var active_left: float = 0.0
	var active_total: float = 1.0
	if not bind_extra:
		active_left = player.skill_active_left
		active_total = maxf(0.01, player.skill_active_total)
		cd_left = player.skill_cd_left
		cd_total = maxf(0.01, player.skill_cd_total)
	else:
		var e_cd = player.get("extra_skill_cd_left")
		if e_cd is float or e_cd is int:
			cd_left = float(e_cd)
		var e_tot = player.get("extra_skill_cd_total")
		if e_tot is float or e_tot is int:
			cd_total = maxf(0.01, float(e_tot))
	var on_active := active_left > 0.0
	var on_cd := cd_left > 0.0

	# 三态键面：效果活跃（点缀黄环倒数、图标全亮，冷却还没开始）→ 冷却（暗环倒数、图标压暗）→ 就绪
	var cd_vis := on_active or on_cd
	if cd_vis != _last_cd_visible:
		_last_cd_visible = cd_vis
		_cd_ring.visible = cd_vis
		if not cd_vis:
			_last_drawn_act_ratio = -1.0
			_last_drawn_cd_ratio = -1.0
	if cd_vis:
		var act_r := clampf(active_left / active_total, 0.0, 1.0) if on_active else 0.0
		var cd_r := clampf(cd_left / cd_total, 0.0, 1.0) if on_cd else 0.0
		_cd_ring.active_ratio = act_r
		_cd_ring.cd_ratio = cd_r
		if absf(act_r - _last_drawn_act_ratio) >= 0.005 or absf(cd_r - _last_drawn_cd_ratio) >= 0.005:
			_last_drawn_act_ratio = act_r
			_last_drawn_cd_ratio = cd_r
			_cd_ring.queue_redraw()

	# 状态机：1 = 效果活跃，0 = 冷却中，-1 = 就绪
	var state := 1 if on_active else (0 if on_cd else -1)
	var num_color: Color = GameStyle.JADE if state == 1 else GameStyle.CHALK
	var rem_time: float = active_left if state == 1 else (cd_left if state == 0 else 0.0)
	var cur_sec: int = int(ceil(rem_time))

	if state != _face_state:
		var prev_state := _face_state
		_face_state = state

		if _icon_rect != null and _icon_rect.visible:
			_icon_rect.modulate.a = 0.35 if state == 0 else (0.85 if state == 1 else 1.0)

		if state == -1:
			# 从冷却或活跃转入就绪：若之前是在冷却/活跃，说明刚刚转好，播一次就绪放大反馈
			var was_cooling := (prev_state == 0 or prev_state == 1)
			_was_ready = true
			_hide_cd_display(was_cooling)
		else:
			# 刚进入活跃或刚进入冷却
			_was_ready = false
			if prev_state == -1:
				# 从就绪进入计时：首个数字立刻就位
				_show_cd_instant(cur_sec, num_color)
			else:
				# 活跃与冷却之间过渡（例如持续期结束刚进 CD）：平滑滚动刷新到 CD 秒数
				_roll_to_sec(cur_sec, num_color)
	elif state != -1:
		# 处于计时状态中（活跃或冷却）：每当剩余秒数整数改变时，触发滚动刷新！
		if cur_sec != _last_shown_sec and cur_sec > 0:
			_roll_to_sec(cur_sec, num_color)

	_update_shadow_chip(player)

## 额外技能充能角标：影爆读影层（Player.shadow_ring）。
## 攒上才出现，攒满直接换成可释放的亮面（不靠闪一下提示——看不见等于没做）。
## 读数都现读账本本身，不在这里另记一份。只归额外技能键：主技能键不挂这颗角标。
func _update_shadow_chip(player: Node) -> void:
	if _shadow_chip == null:
		return
	if not bind_extra or GameManager.extra_skill_id != "shadowburst":
		_shadow_chip.visible = false
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
