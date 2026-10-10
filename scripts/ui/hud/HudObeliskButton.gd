class_name HudObeliskButton
extends Control

## 聚灵阵激活按钮：圆形键 + 键面走针环（按住充能），位置/大小可在设置·操作页自由拖调。
## 从 GameHUD 拆出：键径基准钉死在 SkillButtonView.SKILL_BTN_SIZE（与技能键并排必须是同一个圆），
## 摆位算术在 HudButtonLayout。

const BTN_SIZE := Vector2(SkillButtonView.SKILL_BTN_SIZE, SkillButtonView.SKILL_BTN_SIZE)
const BTN_TEXT := "祭坛"
## 圆键里两个字的最大字号：再大就贴着描边了
const BTN_FONT := 22

var _btn: Button = null
var _ring: SkillButtonView.CircleProgressOverlay = null
var _active_ob: BlessingObelisk = null

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = BTN_SIZE
	_build_button()
	_apply_layout()
	SettingsManager.setting_changed.connect(func(sec: StringName, key: StringName, _val: Variant):
		if sec == &"display" and key in [&"obelisk_btn_xy", &"obelisk_btn_scale"]:
			_apply_layout()
	)

## 构建激活 UI：圆形键 + 键面走针环（摆位交给 HudButtonLayout）
func _build_button() -> void:
	_btn = Button.new()
	_btn.text = BTN_TEXT
	_btn.custom_minimum_size = BTN_SIZE
	_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_btn.focus_mode = Control.FOCUS_NONE
	_style_btn(false)
	_btn.gui_input.connect(handle_input)
	# 这颗键不需要登记：按钮类控件由摇杆自动认走（DawnJoystick._ready 的两趟收口），
	# 按住它不会在底下长出摇杆、也不会把人带出阵法范围。
	add_child(_btn)

	## 充能进度画成键面上那一圈走针（原来是键底一根横条 —— 圆键里横条两头会探出圆面）。
	## 两条约束照旧：
	##  ① mouse_filter 必须 IGNORE —— 显示件在键面上截事件，就是挖一条按不动的死带。
	##  ② 整圈收在圆面之内，半径由 overlay 自己的 arc_radius() 一处算（判据读同一个函数）。
	## 按住时拇指正压着这颗键，所以真读数在阵法上（碑脚环 + 碑顶百分比），
	## 键面这一圈只是「手没离开、眼睛还在别处」时的第二读数，两处读同一个 ratio。
	_ring = SkillButtonView.CircleProgressOverlay.new()
	_ring.progress_color = GameStyle.JADE
	_ring.head_color = GameStyle.JADE_EDGE
	_btn.add_child(_ring)

## 键面样式：平时墨底蓝勾边，按住充能整面翻实蓝 —— 文案不动，状态由底色 + 那一圈说
func _style_btn(charging: bool) -> void:
	SkillButtonView.style_circle_action(_btn, GameStyle.GOLD, BTN_FONT, charging)

## 按钮输入处理：按下开始充能，松开结束充能（支持鼠标与多点触控）
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

	if is_press and _active_ob != null:
		_active_ob.start_charge()
		_style_btn(true)
	elif is_release and _active_ob != null:
		_active_ob.stop_charge()
		_style_btn(false)

## 玩家进入聚灵阵范围：显示激活按钮
func show_obelisk_activation(ob: BlessingObelisk) -> void:
	_active_ob = ob
	_ring.set_ratio(0.0)
	visible = true
	modulate.a = 0.0
	## 弹入只动「相对缩放」：直接 tween 到 1.0 会把设置里存的键体大小抹平
	var s := scale
	var tw = create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.18)
	tw.parallel().tween_property(self, "scale", s, 0.18).from(s * 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## 玩家离开聚灵阵范围：隐藏激活按钮
func hide_obelisk_activation(_ob: BlessingObelisk) -> void:
	_active_ob = null
	var tw = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func(): visible = false)

## 聚灵阵开始充能：视觉反馈
func on_obelisk_charge_started(_ob: BlessingObelisk) -> void:
	pass

## 聚灵阵充能进度更新：更新键面走针环
func on_obelisk_charge_progress(_ob: BlessingObelisk, ratio: float) -> void:
	if _ring != null:
		_ring.set_ratio(ratio)

## 聚灵阵充能取消：重置按钮状态
func on_obelisk_charge_cancelled(_ob: BlessingObelisk) -> void:
	if _btn != null:
		_style_btn(false)
	if _ring != null:
		_ring.set_ratio(0.0)

## 聚灵阵触发成功：播放完成动画后隐藏
func on_obelisk_blessing_triggered(_ob: BlessingObelisk) -> void:
	if visible:
		var s := scale
		var tw = create_tween()
		tw.tween_property(self, "scale", s * 1.15, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(self, "modulate:a", 0.0, 0.4)
		tw.tween_callback(func():
			visible = false
			scale = s
			modulate.a = 1.0
			_ring.set_ratio(0.0)
			_active_ob = null
		)

## 进入/退出调整模式：强制亮出键体交给覆盖层拖动（树此时是暂停态）
func set_edit_mode(on: bool) -> void:
	# 退出调整模式时若人还站在阵法范围内，按钮保持可见（等离开范围再收）
	visible = on or _active_ob != null
	if on:
		_ring.set_ratio(0.0)

## 按钮视觉中心（设计坐标，含缩放摆位）
func center_px() -> Vector2:
	return position + pivot_offset

func size_px() -> Vector2:
	return BTN_SIZE

func get_btn() -> Button:
	return _btn

func _apply_layout() -> void:
	HudButtonLayout.apply(self, SettingsManager.obelisk_btn_xy(), SettingsManager.obelisk_btn_scale(), BTN_SIZE)
