class_name HudMechanismButton
extends Control

## 机关按钮（2026-11-03 手动布设改版）：一颗键身兼多职 ——
##   不在机关旁 + 有编制 → 「布设 ×N」：点按在脚下空地落一座机关；
##   靠近机关 + 需维修   → 「维修」：长按连续回填耐久，键面走针环 = 回填进度；
##   靠近机关 + 完好     → 「完好」：暗面键，按下无动作（只是告诉你这里没活干）。
## 靠近机关时键面顶部另浮出「收回」角标：点按撤回编制（耐久随机关一起带回本体），
## 武器进入整备冷却，到点后才能重放。
##
## 全部待办清空（无编制 + 不在机关旁）时圆键收起；只要有机关磨损/停摆，
## 圆键下方常驻一枚「N 座待修」芯片 —— 圆键收起了也看得见，否则玩家找不到已经走远的坏机关。
##
## 外观/摆位/进度环全部复用现成设施：SkillButtonView.style_circle_action + CircleProgressOverlay
## + HudButtonLayout，键径与其他浮动键钉死同一个 SKILL_BTN_SIZE。

const BTN_SIZE := Vector2(SkillButtonView.SKILL_BTN_SIZE, SkillButtonView.SKILL_BTN_SIZE)
## 键面主文案字号：与祭坛键同口径（两字 18 号收得进圆面，见 UnitRunner 的键面适配判据）
const BTN_FONT := 18
## 键面副读数（下一把机关名 / 耐久百分比）：10 号才收得进走针环内缘
const SUB_FONT := 10
## 副读数行顶边：主文案（88 圆里 Button 自绘垂直居中约 35..53）下方起排，
## 最底 68 仍在走针环内缘（39.5）之上 —— 压到主文案上会出现「维修」和「60%」叠字
const SUB_TOP := 54.0
## 「收回」角标：键面顶部一条横条（拇指常落在圆心中下部，长按维修不会被它截）
const TAG_H := 22.0
## 「N 座待修」芯片相对键面底缘的间距
const CHIP_GAP := 6.0

const FACE_DEPLOY := "布设"
const FACE_REPAIR := "维修"
const FACE_OK := "完好"
## 调整模式下的占位文案（与祭坛键的「激活」同款：先说这是什么东西）
const FACE_EDIT := "机关"

## 状态机（判据读 mode() 做断言）
enum Mode { HIDDEN, DEPLOY, REPAIR, OK }

## 状态轮询间隔：机关状态变化节奏慢（维修由按住驱动，另行逐帧读），10Hz 足够
const POLL_INTERVAL := 0.1

var _btn: Button = null
var _ring: SkillButtonView.CircleProgressOverlay = null
var _sub: Label = null
var _badge: Label = null
var _tag: Button = null
var _chip: Label = null
## 圆键容器：状态收起时整块隐藏（芯片挂在根上，不受它影响）
var _circle_root: Control = null

var _mode: int = Mode.HIDDEN
var _target: TurretUnit = null
var _accent: Color = GameStyle.GOLD
var _face_key: String = ""
var _sub_key: String = ""
var _badge_key: String = ""
## 正在按住维修（键面亮实底色 + 走针环推进）
var _holding: bool = false
## 键盘 F 的按住态：只认键盘自己的按下/松开对
var _key_holding: bool = false
var _edit_mode: bool = false
var _anim_tween: Tween = null
var _base_scale: Vector2 = Vector2.ONE
var _poll_accum: float = 0.0
var _shaking: bool = false
var _last_press_frame: int = -1
var _last_recall_frame: int = -1

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = BTN_SIZE
	_build()
	_apply_layout()
	SettingsManager.setting_changed.connect(func(sec: StringName, key: StringName, _val: Variant):
		if sec == &"display" and key in [&"mechanism_btn_xy", &"mechanism_btn_scale"]:
			_apply_layout()
	)
	SettingsManager.theme_color_changed.connect(func(_p: StringName) -> void:
		_style_btn(_holding)
	)

# ---------------- 构建 ----------------

func _build() -> void:
	# 圆键容器：除芯片外的所有可见件都挂在这上面，收起时整块隐藏
	_circle_root = Control.new()
	_circle_root.name = "CircleRoot"
	_circle_root.custom_minimum_size = BTN_SIZE
	_circle_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_circle_root)

	_btn = Button.new()
	_btn.custom_minimum_size = BTN_SIZE
	_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_btn.focus_mode = Control.FOCUS_NONE
	_style_btn(false)
	_btn.gui_input.connect(handle_input)
	# 按钮类控件由摇杆自动认走（DawnJoystick 两趟收口）：按住它不会在底下长出摇杆
	_circle_root.add_child(_btn)

	# 维修进度环：显示件一律 IGNORE，否则在键面上挖一条按不动的死带
	_ring = SkillButtonView.CircleProgressOverlay.new()
	_ring.progress_color = GameStyle.JADE
	_ring.head_color = GameStyle.JADE_EDGE
	_btn.add_child(_ring)

	# 副读数：布设模式显示下一把机关名，维修/完好模式显示耐久百分比
	_sub = Label.new()
	var sls := LabelSettings.new()
	sls.font = GameStyle.body_font()
	sls.font_size = SUB_FONT
	sls.outline_size = 3
	sls.outline_color = Color(0.02, 0.03, 0.06, 0.9)
	_sub.label_settings = sls
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub.size = Vector2(BTN_SIZE.x, 14)
	_sub.position = Vector2(0, SUB_TOP)
	_btn.add_child(_sub)

	# 编制角标（布设模式 ×N）：右上角小色签，与「收回」角标互斥出现（同一块地方）
	_badge = GameStyle.chip_label(" ", GameStyle.INK, Color(-1, -1, -1, -1), 10)
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.visible = false
	_btn.add_child(_badge)

	# 「收回」角标：键面顶部横条（只靠近机关时出现）。点按撤回编制、耐久带回本体。
	_tag = Button.new()
	_tag.text = "收回"
	_tag.focus_mode = Control.FOCUS_NONE
	_tag.visible = false
	_tag.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_tag.offset_left = 2.0
	_tag.offset_right = -2.0
	_tag.offset_top = 1.0
	_tag.offset_bottom = TAG_H
	# 收回自带 ui_back 音（与技能键的 ui_click 叠在一起会响两声）：预置 meta 跳过统一挂音
	_tag.set_meta("sfx_wired", true)
	GameStyle.button(_tag, GameStyle.INK, GameStyle.NAVY, 11, GameStyle.CHALK)
	_tag.pressed.connect(_do_recall)
	_btn.add_child(_tag)

	# 「N 座待修」芯片：挂在根上（不随圆键一起收起），点按无动作（纯提示）
	_chip = GameStyle.chip_label(" ", GameStyle.BAD, Color(-1, -1, -1, -1), 11)
	_chip.name = "ServiceChip"
	_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_chip.visible = false
	add_child(_chip)

	# 键位提示签（桌面/桌面浏览器专属）：F 主键动作、G 收回
	if SkillButtonView.key_hint_enabled():
		_circle_root.add_child(SkillButtonView.make_key_chip("F"))

## 键面样式：按当前模式取主色，按住维修整面翻实底（状态由底色 + 走针环说）
func _style_btn(holding: bool) -> void:
	if _btn == null:
		return
	SkillButtonView.style_circle_action(_btn, _accent, BTN_FONT, holding)

# ---------------- 输入 ----------------

func handle_input(event: InputEvent) -> void:
	var is_press := false
	var is_release := false
	if event is InputEventScreenTouch:
		if event.pressed:
			is_press = true
		else:
			is_release = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_press = true
		else:
			is_release = true
	if is_press:
		_press_primary()
	elif is_release:
		_release_primary()

## 原生第二指触摸（GameHUD._input 转发）：左手拉摇杆 + 右手布设/维修。
## 键面热区用圆形判定（与技能键同款），角标热区单独判（它压在键面顶部）。
func handle_engine_input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch):
		return
	if not _is_gameplay_active():
		return
	var touch := event as InputEventScreenTouch
	if touch.pressed:
		if _tag != null and _tag.visible and _is_point_on(_tag, touch.position):
			_do_recall()
			return
		if _circle_root.visible and _is_point_on(_btn, touch.position):
			_press_primary()
	elif _holding:
		# 松开也是这一指：不判热区（手指滑出圆面也要能收手）
		_release_primary()

## 键盘 F：与键面同一套动作（点按布设 / 长按维修）
func key_press() -> void:
	if _edit_mode or _key_holding:
		return
	_key_holding = true
	_press_primary()

func key_release() -> void:
	if not _key_holding:
		return
	_key_holding = false
	_release_primary()

## 键盘路由判据（GameHUD 分流 F 键用）
func can_key_act() -> bool:
	return visible and not _edit_mode and _is_gameplay_active() and _mode != Mode.HIDDEN

## 键盘 G：收回（与角标点按同一动作；不靠近机关时是空操作）
func recall_by_key() -> void:
	if _edit_mode or _mode == Mode.HIDDEN:
		return
	if _mode != Mode.REPAIR and _mode != Mode.OK:
		return
	_do_recall()

func mode() -> int:
	return _mode

## 按帧去重：触屏原生事件与 Godot 的鼠标模拟会各来一发，不去重会一次点按布设两座
func _press_frame_guard() -> bool:
	var cur := Engine.get_process_frames()
	if _last_press_frame == cur:
		return false
	_last_press_frame = cur
	return true

## 收回同样要按帧去重：角标是 Button，原生触点与鼠标模拟会各触发一次 pressed
func _recall_frame_guard() -> bool:
	var cur := Engine.get_process_frames()
	if _last_recall_frame == cur:
		return false
	_last_recall_frame = cur
	return true

func _press_primary() -> void:
	if _edit_mode or not _press_frame_guard():
		return
	match _mode:
		Mode.DEPLOY:
			_do_deploy()
		Mode.REPAIR:
			if _target != null and is_instance_valid(_target):
				_target.begin_repair()
				_holding = true
				_style_btn(true)
		_:
			pass

func _release_primary() -> void:
	if not _holding:
		return
	_holding = false
	if _target != null and is_instance_valid(_target):
		_target.end_repair()
	if _ring != null:
		_ring.set_ratio(0.0)
	_style_btn(false)

func _is_point_on(box: Control, pos: Vector2) -> bool:
	if box == null or not is_instance_valid(box) or not box.is_visible_in_tree():
		return false
	var r := box.get_global_rect().grow(8.0)
	return r.has_point(pos)

# ---------------- 动作 ----------------

func _do_deploy() -> void:
	var player = GameManager.player
	var turret := TurretCommand.deploy_at_player(player)
	if turret == null:
		_play_reject_fx()
		return
	_play_pop_fx()
	# 一次性引导：首次真布设时弹一条情境提示（HudContextTips 自带去重门控）
	GameManager.context_tip_requested.emit(&"mechanism")

func _do_recall() -> void:
	if _edit_mode or not _recall_frame_guard():
		return
	var player = GameManager.player
	if player == null or not is_instance_valid(player):
		return
	if not TurretCommand.recall_nearest(player, player.global_position):
		_play_reject_fx()
		return
	_holding = false
	if _ring != null:
		_ring.set_ratio(0.0)
	AudioManager.play_sfx("ui_back", 0.7)
	_poll_state()

func _play_pop_fx() -> void:
	if _btn == null:
		return
	_btn.pivot_offset = BTN_SIZE * 0.5
	var tw = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(_btn, "scale", Vector2(0.88, 0.88), 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_btn, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## 无法布设（落点被自己的机关占了 / 没编制）：左右微抖 + 报错音，不静默
func _play_reject_fx() -> void:
	if _btn == null or _shaking:
		return
	_shaking = true
	var orig_x := _btn.position.x
	var tw = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(_btn, "position:x", orig_x - 5.0, 0.04)
	tw.tween_property(_btn, "position:x", orig_x + 5.0, 0.04)
	tw.tween_property(_btn, "position:x", orig_x, 0.04)
	tw.tween_callback(func(): _shaking = false)
	AudioManager.play_sfx("ui_error", 0.7)

# ---------------- 状态轮询 ----------------

func _process(delta: float) -> void:
	if _edit_mode:
		return
	# 按住维修时逐帧推进走针环（唯一需要每帧刷的读数）
	if _holding and _target != null and is_instance_valid(_target):
		if _ring != null:
			_ring.set_ratio(_target.repair_ratio())
		if not _target.is_repairing():
			# 修满了：收手并复位
			_holding = false
			if _ring != null:
				_ring.set_ratio(0.0)
			_style_btn(false)
	_poll_accum += delta
	if _poll_accum < POLL_INTERVAL:
		return
	_poll_accum = 0.0
	_poll_state()

func _poll_state() -> void:
	var player = GameManager.player
	var next_mode := Mode.HIDDEN
	var next_target: TurretUnit = null
	var ready := 0
	var sub_text := ""
	var badge_text := ""
	var accent: Color = GameStyle.GOLD
	var service := 0

	if player != null and is_instance_valid(player):
		next_target = TurretCommand.nearest_turret(player, player.global_position,
			BalanceTurret.INTERACT_RADIUS)
		if next_target != null:
			# 「能不能修」与「要不要报警」分开：只要没满就能修（磨到 40% 以下才报磨损），
			# 否则修到 41% 那一刻键面就翻「完好」、长按再也按不动 —— 玩家永远修不满。
			if next_target.durability_ratio() < 0.999:
				next_mode = Mode.REPAIR
				accent = GameStyle.JADE
				sub_text = "%d%%" % roundi(next_target.durability_ratio() * 100.0)
			else:
				next_mode = Mode.OK
				accent = GameStyle.GREY
				sub_text = "100%"
		else:
			ready = TurretCommand.ready_count(player)
			if ready > 0:
				next_mode = Mode.DEPLOY
				accent = GameStyle.GOLD
				badge_text = "×%d" % ready
				var w = TurretCommand.next_ready(player)
				if w != null:
					sub_text = String(WeaponData.get_def(String(w.weapon_def_id)).get("name", ""))
		service = TurretCommand.service_count(player)

	# 目标换了（或离开范围）：正在按的那次维修收手，避免修到一半换目标
	if _target != next_target and _holding:
		_release_primary()

	_mode = next_mode
	_target = next_target
	# 芯片只在「附近这台本身不缺维修」时提示别处的机器（站在坏机关旁边时芯片是废话）
	var near_needs := next_target != null and next_target.needs_service()
	_apply_face(accent, sub_text, badge_text, service, near_needs)
	_apply_visibility()

## 键面文案/副读数/角标/芯片：只在读数变化时重写，避免每帧排版
func _apply_face(accent: Color, sub_text: String, badge_text: String, service: int,
		near_needs: bool) -> void:
	var face := FACE_EDIT if _edit_mode else _face_for_mode(_mode)
	if face != _face_key:
		_face_key = face
		if _btn != null:
			_btn.text = face
	if accent != _accent:
		_accent = accent
		_style_btn(_holding)
	if sub_text != _sub_key:
		_sub_key = sub_text
		if _sub != null:
			_sub.text = sub_text
	if badge_text != _badge_key:
		_badge_key = badge_text
		if _badge != null:
			_badge.visible = not badge_text.is_empty()
			if not badge_text.is_empty():
				_badge.text = " %s " % badge_text
				_badge.custom_minimum_size = Vector2(GameStyle.chip_pin_w(_badge.text, GameStyle.body_font(), 10), 0)
				_badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
				_badge.offset_right = -3.0
				_badge.offset_left = _badge.offset_right - _badge.custom_minimum_size.x
				_badge.offset_top = 3.0
				_badge.offset_bottom = 3.0 + 14.0
	# 「收回」角标与编制角标互斥（同一块地方），且只在真靠近机关时出现
	if _tag != null:
		_tag.visible = _mode == Mode.REPAIR or _mode == Mode.OK
	# 角标显隐每拍按最终状态收口：只在文案变化时写 visible 的话，
	# 从「维修（角标态）」走回「布设」时旧角标已经被收回角标压掉、再也不会亮回来
	if _badge != null:
		_badge.visible = not badge_text.is_empty() and not (_tag != null and _tag.visible)
	# 待修芯片：圆键收起了也照样提示（否则找不到已经走远的那几台）
	if _chip != null:
		var show_chip := service > 0 and not near_needs and not _edit_mode
		if _chip.visible != show_chip:
			_chip.visible = show_chip
		if show_chip:
			var txt := " %d 座待修 " % service
			if _chip.text != txt:
				_chip.text = txt
				_chip.custom_minimum_size = Vector2(GameStyle.chip_pin_w(txt, GameStyle.body_font(), 11), 0)
				_center_chip()

func _face_for_mode(m: int) -> String:
	match m:
		Mode.DEPLOY:
			return FACE_DEPLOY
		Mode.REPAIR:
			return FACE_REPAIR
		Mode.OK:
			return FACE_OK
	return FACE_EDIT

## 收放：只在状态真的翻转时起 Tween（10Hz 轮询不能反复重建动画）。
## 圆键收起后根节点可能还要留着（待修芯片），所以「圆键显隐」与「根节点显隐」分开管。
func _apply_visibility() -> void:
	var want_circle := _mode != Mode.HIDDEN
	if _circle_root.visible != want_circle:
		_circle_root.visible = want_circle
	var want_any := want_circle or (_chip != null and _chip.visible)
	if want_any == visible:
		# 动画在跑时不要去改 alpha/scale（会把弹入/淡出当场掐断）
		if want_any and (_anim_tween == null or not _anim_tween.is_valid()):
			modulate.a = 1.0
			scale = _base_scale
		return
	_kill_anim_tween()
	if want_any:
		visible = true
		modulate.a = 0.0
		scale = _base_scale * 0.85
		_anim_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_anim_tween.tween_property(self, "modulate:a", 1.0, 0.16)
		_anim_tween.parallel().tween_property(self, "scale", _base_scale, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		modulate.a = 1.0
		scale = _base_scale
		_anim_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_anim_tween.tween_property(self, "modulate:a", 0.0, 0.18)
		_anim_tween.tween_callback(func() -> void:
			# 淡出途中可能又被点回来（刚收回又买到新机关）：那时把透明度收回来即可
			var now_want := _mode != Mode.HIDDEN or (_chip != null and _chip.visible)
			modulate.a = 1.0
			scale = _base_scale
			if not now_want:
				visible = false
		)

func _kill_anim_tween() -> void:
	if _anim_tween != null and _anim_tween.is_valid():
		_anim_tween.kill()
	_anim_tween = null

## 战斗门控（照 HudSkillButton._is_gameplay_active 口径）：暂停/结算/非战斗阶段不接单
func _is_gameplay_active() -> bool:
	if not is_visible_in_tree() or get_tree().paused:
		return false
	if not GameManager.run_started or GameManager.is_game_over:
		return false
	var spawner: Node = GameManager.wave_spawner
	if spawner != null and int(spawner.get("phase")) != int(WaveSpawner.Phase.FIGHT):
		return false
	return true

# ---------------- 调整模式 / 判据取件口 ----------------

## 进入/退出调整模式：强制亮出键体交给覆盖层拖动（树此时是暂停态）
func set_edit_mode(on: bool) -> void:
	_edit_mode = on
	_kill_anim_tween()
	_holding = false
	if on:
		_mode = Mode.DEPLOY
		_accent = GameStyle.GOLD
		# 占位读数：只留「机关」二字，不留上一波的耐久/编制数字
		_face_key = ""
		if _btn != null:
			_btn.text = FACE_EDIT
		if _sub != null:
			_sub.text = ""
		_sub_key = ""
		_badge_key = ""
		if _badge != null:
			_badge.visible = false
		if _tag != null:
			_tag.visible = false
		if _chip != null:
			_chip.visible = false
		_style_btn(false)
		visible = true
		_circle_root.visible = true
		modulate.a = 1.0
		scale = _base_scale
	else:
		_face_key = ""
		_sub_key = ""
		_badge_key = ""
		visible = false
		_circle_root.visible = false
		modulate.a = 1.0
		scale = _base_scale
		_poll_accum = 1.0
		_poll_state()

## 判据取件口：真身控件都从这里拿（别去 HUD 上找同名属性）
func get_btn() -> Button:
	return _btn

func get_ring() -> SkillButtonView.CircleProgressOverlay:
	return _ring

func get_tag() -> Button:
	return _tag

func get_badge() -> Label:
	return _badge

func get_chip() -> Label:
	return _chip

func get_sub_label() -> Label:
	return _sub

func is_circle_shown() -> bool:
	return _circle_root != null and _circle_root.visible

func center_px() -> Vector2:
	return position + pivot_offset

func size_px() -> Vector2:
	return BTN_SIZE

func _center_chip() -> void:
	if _chip == null:
		return
	_chip.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_chip.offset_left = -20.0
	_chip.offset_right = BTN_SIZE.x + 20.0
	_chip.offset_top = BTN_SIZE.y + CHIP_GAP
	_chip.offset_bottom = BTN_SIZE.y + CHIP_GAP + 16.0

func _apply_layout() -> void:
	HudButtonLayout.apply(self, SettingsManager.mechanism_btn_xy(),
		SettingsManager.mechanism_btn_scale(), BTN_SIZE)
	_base_scale = scale
	_center_chip()