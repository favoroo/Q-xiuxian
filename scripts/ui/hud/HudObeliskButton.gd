class_name HudObeliskButton
extends Control

## 聚灵阵激活按钮：圆形键 + 键面走针环（按住充能），位置/大小可在设置·操作页自由拖调。
## 从 GameHUD 拆出：键径基准钉死在 SkillButtonView.SKILL_BTN_SIZE（与技能键并排必须是同一个圆），
## 摆位算术在 HudButtonLayout。

const BTN_SIZE := Vector2(SkillButtonView.SKILL_BTN_SIZE, SkillButtonView.SKILL_BTN_SIZE)
## 键面主文案（用户 2026-10-11：「祭坛」只说了那是个什么东西，没说这颗键按下去干什么）。
## 2026-10-26 收成单词「激活」：价格从碑顶悬浮字挪进键面（见 _price），四字两行腾不出地方。
const BTN_TEXT := "激活"
## 18 是「不出圆面、也不压走针那一圈」的上限（字号实测口径见 UnitRunner 那条判据）：
## 22 号两行外接框 44×62 → 角半径 38.0，正好顶在描边上；18 号单行 37×18 富余充足，
## 收进走针环半径（CircleProgressOverlay.arc_radius = 33.5）之内，按住充能时那一圈不会压在字上。
## 口径由 UnitRunner 钉（见 tests/unit/unit_infra_tests.gd）。
const BTN_FONT := 18
## 键面价格小字（2026-10-26：碑顶常驻悬浮字很怪，撤掉；价格挪到激活键上简短一行）。
## 够钱「N金币」（奶白），不够「差N」（朱砂）—— 摆在主文案正下方，收在走针环之内。
const PRICE_FONT := 12
## 价格行顶边：主文案（Button 自绘垂直居中 29..47）下方起排，最底 62 仍在走针环内缘之上
const PRICE_TOP := 48.0

var _btn: Button = null
var _ring: SkillButtonView.CircleProgressOverlay = null
## 键面价格小字：读 GameManager 现价（随波上涨）与余额（不够转「差N」），文本变了才重写
var _price: Label = null
var _price_key: String = ""
var _active_ob: BlessingObelisk = null
## 键盘 E 的按住态：只认键盘自己的按下/松开对，E 松开不会误停鼠标/触屏正在充的能
var _key_holding := false
var _anim_tween: Tween = null
var _base_scale: Vector2 = Vector2.ONE
var _edit_mode: bool = false

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
	# 主题色变更：圆键四态是手搓 StyleBox，重跑样式工厂拿新主色
	SettingsManager.theme_color_changed.connect(func(_p: StringName) -> void:
		if _btn != null:
			_style_btn(false)
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

	## 键面价格小字（2026-10-26）：碑顶不再悬浮任何常驻文字，启动价收进这颗键。
	## 显示件纪律：mouse_filter 必须 IGNORE（在键面上截事件就是挖一条按不动的死带）。
	_price = Label.new()
	var pls := LabelSettings.new()
	pls.font = GameStyle.body_font()
	pls.font_size = PRICE_FONT
	pls.outline_size = 3
	pls.outline_color = Color(0.02, 0.03, 0.06, 0.9)
	_price.label_settings = pls
	_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_price.size = Vector2(BTN_SIZE.x, 14)
	_price.position = Vector2(0, PRICE_TOP)
	_btn.add_child(_price)

	# 键位提示签（桌面端/桌面浏览器专属）：E 长按激活，移动端无键盘不亮
	if SkillButtonView.key_hint_enabled():
		_btn.add_child(SkillButtonView.make_key_chip("E"))

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

## 键盘路由判据（GameHUD 分流 E 键用）：按钮亮着且挂着本回合还没用过的阵法
func can_key_charge() -> bool:
	return visible and not _edit_mode and _active_ob != null and not _active_ob.spent_this_wave

## 键盘 E 按下：与键面按住同一套充能状态（start_charge 自带灰相/金币/入阵门）
func key_press() -> void:
	if _edit_mode or _key_holding or _active_ob == null:
		return
	_key_holding = true
	_active_ob.start_charge()
	_style_btn(true)

## 键盘 E 松开：充能收尾（没充上时是幂等空操作）
func key_release() -> void:
	if not _key_holding:
		return
	_key_holding = false
	if _active_ob != null:
		_active_ob.stop_charge()
		_style_btn(false)

func _kill_anim_tween() -> void:
	if _anim_tween != null and _anim_tween.is_valid():
		_anim_tween.kill()
	_anim_tween = null

## 玩家进入聚灵阵范围：显示激活按钮
func show_obelisk_activation(ob: BlessingObelisk) -> void:
	if ob == null or ob.spent_this_wave:
		return
	var was_same_active := (_active_ob == ob)
	_active_ob = ob
	_ring.set_ratio(0.0)
	if was_same_active and visible and modulate.a >= 0.99 and (_anim_tween == null or not _anim_tween.is_valid()):
		scale = _base_scale
		return
	_kill_anim_tween()
	visible = true
	var target_s := _base_scale
	scale = target_s * 0.8
	modulate.a = 0.0
	_anim_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_anim_tween.tween_property(self, "modulate:a", 1.0, 0.18)
	_anim_tween.parallel().tween_property(self, "scale", target_s, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## 玩家离开聚灵阵范围：隐藏激活按钮
func hide_obelisk_activation(ob: BlessingObelisk) -> void:
	if _active_ob != null and ob != null and ob != _active_ob:
		return
	_active_ob = null
	_kill_anim_tween()
	_anim_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_anim_tween.tween_property(self, "modulate:a", 0.0, 0.2)
	_anim_tween.tween_callback(func() -> void:
		if _active_ob == null and not _edit_mode:
			visible = false
			scale = _base_scale
			modulate.a = 1.0
	)

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
func on_obelisk_blessing_triggered(ob: BlessingObelisk) -> void:
	if _active_ob != null and ob != null and ob != _active_ob:
		return
	_kill_anim_tween()
	if visible:
		var target_s := _base_scale
		_anim_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_anim_tween.tween_property(self, "scale", target_s * 1.15, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_anim_tween.parallel().tween_property(self, "modulate:a", 0.0, 0.4)
		_anim_tween.tween_callback(func() -> void:
			if _active_ob == ob or _active_ob == null:
				if not _edit_mode:
					visible = false
				scale = _base_scale
				modulate.a = 1.0
				_ring.set_ratio(0.0)
				_active_ob = null
		)
	else:
		scale = _base_scale
		modulate.a = 1.0
		_ring.set_ratio(0.0)
		_active_ob = null

## 进入/退出调整模式：强制亮出键体交给覆盖层拖动（树此时是暂停态）
func set_edit_mode(on: bool) -> void:
	_edit_mode = on
	_kill_anim_tween()
	modulate.a = 1.0
	scale = _base_scale
	# 退出调整模式时若人还站在阵法范围内，按钮保持可见（等离开范围再收）
	visible = on or _active_ob != null
	if on:
		_ring.set_ratio(0.0)

func _process(_delta: float) -> void:
	if _edit_mode:
		return
	if _active_ob != null:
		if not is_instance_valid(_active_ob) or _active_ob.spent_this_wave or not _active_ob.is_player_inside:
			hide_obelisk_activation(_active_ob)
		elif not visible and (_anim_tween == null or not _anim_tween.is_valid()):
			show_obelisk_activation(_active_ob)
	_refresh_price()

## 键面价格小字：读本回合现价与余额（2026-10-26 从碑顶悬浮字挪进键面）。
## 本局第一次启动免费（2026-10-30）写「免费」；够钱「N金币」奶白，不够「差N」朱砂 ——
## 文本没变不重写，钱每帧都在变也不能每帧重排。
func _refresh_price() -> void:
	if _price == null:
		return
	var key := ""
	var col: Color = GameStyle.CHALK
	if _active_ob != null and is_instance_valid(_active_ob) and visible:
		var cost := GameBalance.obelisk_activation_cost(GameManager.wave_number, GameManager.obelisk_activations)
		if cost <= 0:
			key = "免费"
			col = GameStyle.JADE
		elif GameManager.spirit_stones >= cost:
			key = "%d金币" % cost
		else:
			key = "差%d" % (cost - GameManager.spirit_stones)
			col = GameStyle.BAD
	if key != _price_key:
		_price_key = key
		_price.text = key
	_price.label_settings.font_color = col

## 键面价格小字（判据读它，与 get_btn/get_ring 同款取件口）
func get_price_label() -> Label:
	return _price

## 按钮视觉中心（设计坐标，含缩放摆位）
func center_px() -> Vector2:
	return position + pivot_offset

func size_px() -> Vector2:
	return BTN_SIZE

func get_btn() -> Button:
	return _btn

## 键面走针环（判据与出图台读它，别再去 HUD 上找一个不存在的同名属性）
func get_ring() -> SkillButtonView.CircleProgressOverlay:
	return _ring

func _apply_layout() -> void:
	HudButtonLayout.apply(self, SettingsManager.obelisk_btn_xy(), SettingsManager.obelisk_btn_scale(), BTN_SIZE)
	_base_scale = scale
