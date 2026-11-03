class_name HudMechanismButton
extends Control

## 机关按钮（2026-11-03 手动布设改版，v0.1.20 真机修）：
##   不在机关旁 + 有编制 → 「布设 ×N」：点按在脚下空地落一座机关；
##   靠近机关 + 需维修   → 「维修」：长按连续回填耐久，键面走针环 = 回填进度；
##   靠近机关 + 满耐久 + 有编制（落点为空） → 「布设 ×N」；
##   靠近机关 + 满耐久 + 有编制（落点被占） → 「太近」：抖动 + 报错音 + 文案提示，不再静默；
##   靠近机关 + 满耐久 + 无编制             → 「完好」：暗面键，按下给一句提示；
##   场上已有机关但走远了 + 无编制           → 「在场」：键不收起，只报状态，不写收回提示；
##   收回后的 2 秒整备倒数                   → 「整备」：显示剩余秒数。
##   状态都对却出不了机关（链路内部失败）     → 按 TurretCommand.last_error 说清是哪一环
## （机关模型没加载出来 / 编制已满 / 请再试一次），不再统一报「现在不能布设机关」。
##
## 独立「收回」键（用户真机反馈：顶部小角标看不见）：只在玩家走进机关交互半径时出现
## （主键左侧，左缘不够就自动改到上方/右侧），走远即整颗隐藏 —— 布设键只管布设与维修。
## 键面 = 「机关 → 人物」图标 + 单行「可收回」：旧版「收回 / 可收回」两行字在 56 圆里又挤又重复。
## 收回后起固定 2 秒整备倒数（BalanceTurret.RECALL_COOLDOWN_SEC），倒计时内按主键给提示、不布设。
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
## 「N 座待修」芯片相对键面底缘的间距
const CHIP_GAP := 6.0

## 独立「收回」键：直径 / 与主键的间距 / 字号
const RECALL_SIZE := 56.0
const RECALL_GAP := 10.0
const RECALL_FONT := 14
## 收回键图标尺寸与位置：上图标、下「可收回」单行（旧版「收回 / 可收回」两行在 56 圆里太挤）
const RECALL_ICON_SIZE := 28.0
const RECALL_ICON_TOP := 4.0
const RECALL_TEXT_TOP := 32.0
## 热区外扩：手机手指比鼠标粗，圆形判定比视觉圆再放宽一圈
const HIT_PAD := 14.0
const RECALL_HIT_PAD := 12.0

const FACE_DEPLOY := "布设"
const FACE_REPAIR := "维修"
const FACE_OK := "完好"
const FACE_TOO_CLOSE := "太近"
const FACE_SPENT := "在场"
const FACE_COOLDOWN := "整备"
## 调整模式下的占位文案（与祭坛键的「激活」同款：先说这是什么东西）
const FACE_EDIT := "机关"

## 状态机（判据读 mode() 做断言）
enum Mode { HIDDEN, DEPLOY, REPAIR, OK, TOO_CLOSE, SPENT, COOLDOWN }

## 状态轮询间隔：机关状态变化节奏慢（维修由按住驱动，另行逐帧读），10Hz 足够
const POLL_INTERVAL := 0.1

## 布设落点预览（地面虚影 + 射程环）：纯表现层，判定口径与 TurretCommand 同源
const DEPLOY_PREVIEW := preload("res://scripts/weapons/TurretDeployPreview.gd")

## 收回键图标：上「机关盘」下「人物」+ 中间向下回收箭头。
## 56 圆里只放「可收回」三个字太空，图标要一眼说出「机关收回人身上」，
## 不画通用循环箭头（那读作刷新/重来，和收回不是一回事）。
class RecallIcon extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, 0.0)
		var jade: Color = GameStyle.JADE
		var chalk: Color = GameStyle.CHALK
		var ink: Color = GameStyle.with_alpha(GameStyle.INK, 0.9)
		# 1. 顶部机关：圆盘 + 左右短翼（读作机关座，不是普通圆点）
		var disc := c + Vector2(0.0, 6.0)
		draw_circle(disc, 4.8, ink)
		draw_arc(disc, 4.2, 0.0, TAU, 16, jade, 1.7, true)
		draw_line(disc + Vector2(-6.6, 0.0), disc + Vector2(-4.4, 0.0), jade, 1.5)
		draw_line(disc + Vector2(4.4, 0.0), disc + Vector2(6.6, 0.0), jade, 1.5)
		# 2. 回收箭头：机关下缘 → 人物头顶，箭头朝下
		var tip := c + Vector2(0.0, 13.8)
		draw_line(c + Vector2(0.0, 9.4), tip, jade, 1.8)
		draw_colored_polygon(PackedVector2Array([
			tip + Vector2(0.0, 1.4),
			tip + Vector2(-2.8, -2.4),
			tip + Vector2(2.8, -2.4)]), jade)
		# 3. 下方人物：头 + 肩弧，收回到人身上
		draw_circle(c + Vector2(0.0, 17.2), 2.1, chalk)
		draw_arc(c + Vector2(0.0, 19.8), 5.1, PI * 0.12, PI * 0.88, 14, chalk, 1.6, true)

var _btn: Button = null
var _ring: SkillButtonView.CircleProgressOverlay = null
var _sub: Label = null
var _badge: Label = null
## 独立收回键（不再用主键顶部的 22px 小角标）：图标 + 单行「可收回」
var _recall_btn: Button = null
var _recall_icon: Control = null
var _recall_sub: Label = null
## 收回键小字读数缓存（固定「可收回」，只在变化时重写）
var _recall_sub_key: String = ""
var _chip: Label = null
## 圆键容器：状态收起时整块隐藏（芯片挂在根上，不受它影响）
var _circle_root: Control = null

var _mode: int = Mode.HIDDEN
var _target: TurretUnit = null
var _accent: Color = GameStyle.GOLD
var _face_key: String = ""
var _sub_key: String = ""
var _badge_key: String = ""
## 收回键配色只在「近/远」翻转时重刷，10Hz 轮询不反复建 StyleBox
var _recall_accent: Color = Color(-1, -1, -1, -1)
## 场上有没有自己的机关 / 最近机关是否在交互半径内
var _has_turret: bool = false
var _recall_near: bool = false
## 正在按住维修（键面亮实底色 + 走针环推进）
var _holding: bool = false
var _hold_touch_index: int = -999
## 键盘 F 的按住态：只认键盘自己的按下/松开对
var _key_holding: bool = false
var _edit_mode: bool = false
var _anim_tween: Tween = null
var _base_scale: Vector2 = Vector2.ONE
var _poll_accum: float = 0.0
var _shaking: bool = false
var _last_press_frame: int = -1
var _last_deploy_time: int = -10000
var _last_recall_frame: int = -1
var _last_recall_time: int = -10000
## 动作后的短静默：触屏原生事件与模拟鼠标可能跨帧各来一发，
## 上一发已经布设/收回成功时，下一发不许再弹「完好/在场」之类的提示。
var _suppress_until: int = 0
var _preview: Node2D = null

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
		_recall_accent = Color(-1, -1, -1, -1)
		_apply_face(_accent, _sub_key, _badge_key, TurretCommand.service_count(GameManager.player), false)
	)

# ---------------- 构建 ----------------

func _build() -> void:
	# 圆键容器：除芯片/收回键外的所有可见件都挂在这上面，收起时整块隐藏
	_circle_root = Control.new()
	_circle_root.name = "CircleRoot"
	_circle_root.custom_minimum_size = BTN_SIZE
	_circle_root.size = BTN_SIZE
	_circle_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_circle_root)

	_btn = Button.new()
	_btn.custom_minimum_size = BTN_SIZE
	_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_btn.size = BTN_SIZE
	_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_btn.focus_mode = Control.FOCUS_NONE
	_style_btn(false)
	_btn.gui_input.connect(handle_input)
	# 双保险：原生触摸链之外再挂 Button 自己的按下/抬起信号。
	# 真机上若某个上层控件吞掉了 gui_input，引擎信号仍会到（帧去重保证不会一次点两座）。
	_btn.button_down.connect(_on_main_button_down)
	_btn.button_up.connect(_on_main_button_up)
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

	# 编制角标（布设模式 ×N）：右上角小色签
	_badge = GameStyle.chip_label(" ", GameStyle.INK, Color(-1, -1, -1, -1), 10)
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.visible = false
	_btn.add_child(_badge)

	# 独立「收回」键：挂根节点（不随圆键收起），只在靠近机关时出现
	_recall_btn = Button.new()
	_recall_btn.name = "RecallButton"
	_recall_btn.text = ""
	_recall_btn.focus_mode = Control.FOCUS_NONE
	_recall_btn.visible = false
	_recall_btn.custom_minimum_size = Vector2(RECALL_SIZE, RECALL_SIZE)
	_recall_btn.size = Vector2(RECALL_SIZE, RECALL_SIZE)
	_recall_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	# 收回自带 ui_back 音（与技能键的 ui_click 叠在一起会响两声）：预置 meta 跳过统一挂音
	_recall_btn.set_meta("sfx_wired", true)
	SkillButtonView.style_circle_action(_recall_btn, GameStyle.JADE, RECALL_FONT)
	_recall_btn.button_down.connect(_do_recall)
	add_child(_recall_btn)

	# 收回键内部：上「机关 → 人物」图标，下「可收回」单行。
	# 旧版是「收回」+「可收回」两行字，56 圆里又挤又重复，玩家一眼读不完。
	_recall_icon = RecallIcon.new()
	_recall_icon.name = "RecallIcon"
	_recall_icon.size = Vector2(RECALL_ICON_SIZE, RECALL_ICON_SIZE)
	_recall_icon.position = Vector2((RECALL_SIZE - RECALL_ICON_SIZE) * 0.5, RECALL_ICON_TOP)
	_recall_btn.add_child(_recall_icon)

	_recall_sub = Label.new()
	var rss := LabelSettings.new()
	rss.font = GameStyle.body_font()
	rss.font_size = 10
	rss.outline_size = 2
	rss.outline_color = Color(0.02, 0.03, 0.06, 0.9)
	_recall_sub.label_settings = rss
	_recall_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_recall_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_recall_sub.position = Vector2(0, RECALL_TEXT_TOP)
	_recall_sub.size = Vector2(RECALL_SIZE, 14)
	_recall_sub.text = "可收回"
	_recall_btn.add_child(_recall_sub)

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

## Button 自己的按下信号：gui_input 被上层吃掉时的兜底路径。
## 与 handle_input / handle_engine_input 共用按帧去重，三种路径同帧只会执行一次。
func _on_main_button_down() -> void:
	if _edit_mode or not _is_gameplay_active():
		return
	_press_primary(-1)

func _on_main_button_up() -> void:
	if _holding:
		_release_primary(-999)

func handle_input(event: InputEvent) -> void:
	if not _is_gameplay_active():
		return
	var is_press := false
	var is_release := false
	var touch_index := -1
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		touch_index = st.index
		if st.pressed:
			is_press = true
		else:
			is_release = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		touch_index = -1
		if event.pressed:
			is_press = true
		else:
			is_release = true
	if is_press:
		_poll_state()
		_press_primary(touch_index)
	elif is_release:
		_release_primary(touch_index)

## 原生第二指触摸（GameHUD._input 转发）：左手拉摇杆 + 右手布设/维修。
## 键面热区用圆形判定（与技能键同款），收回键单独判。
func handle_engine_input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch):
		return
	if not _is_gameplay_active():
		return
	var touch := event as InputEventScreenTouch
	if touch.pressed:
		# 先现算一拍状态：10Hz 轮询在快速走位时可能还停在上一格，
		# 直接用旧 mode 判会把「布设」误判成「完好」而静默吞掉这一下。
		_poll_state()
		# 主键优先：两个圆的热区外扩后会在交界处重叠（主键半径 44+14 / 收回 28+12，
		# 圆心距仅 82），先判收回会把「点主键左缘维修/布设」误判成收回（真的撤场 + 整备冷却）。
		if _circle_root != null and _circle_root.visible and _is_point_on_btn(touch.position):
			_press_primary(touch.index)
			return
		if _recall_btn != null and _recall_btn.visible and _is_point_on_recall(touch.position):
			_do_recall()
	elif _holding:
		# 松开分支只认匹配的 index，左手松摇杆不打断右手维修
		if touch.index == _hold_touch_index:
			_release_primary(touch.index)

## 键盘 F：与键面同一套动作（点按布设 / 长按维修）
func key_press() -> void:
	if _edit_mode or _key_holding:
		return
	_key_holding = true
	_press_primary(-2)

func key_release() -> void:
	if not _key_holding:
		return
	_key_holding = false
	_release_primary(-2)

## 键盘路由判据（GameHUD 分流 F 键用）
func can_key_act() -> bool:
	return visible and not _edit_mode and _is_gameplay_active() and _mode != Mode.HIDDEN

## 键盘 G：收回（与独立收回键同一动作；不靠近机关时给提示）
func recall_by_key() -> void:
	if _edit_mode or _mode == Mode.HIDDEN or not _is_gameplay_active():
		return
	_do_recall()

## 暂停/失焦时收不到按键或触点的松开事件：主动收手，避免回到战斗后
## 「没人按住也在回填耐久」，以及 F 的按住标志卡到下一次真实松开。
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_PAUSED, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			_key_holding = false
			_release_primary(-999)

func mode() -> int:
	return _mode

## 按帧去重：触屏原生事件与 Godot 的鼠标模拟会各来一发，不去重会一次点按布设两座
func _press_frame_guard() -> bool:
	var cur := Engine.get_process_frames()
	if _last_press_frame == cur:
		return false
	_last_press_frame = cur
	return true

## 收回同样要按帧去重：原生触点与鼠标模拟会各触发一次 pressed
func _recall_frame_guard() -> bool:
	var cur := Engine.get_process_frames()
	if _last_recall_frame == cur:
		return false
	_last_recall_frame = cur
	return true

func _press_primary(touch_index: int = -1) -> void:
	if _edit_mode or not _press_frame_guard():
		return
	match _mode:
		Mode.DEPLOY:
			_do_deploy()
		Mode.TOO_CLOSE:
			_play_reject_fx()
			_hint("离机关太近，走远一点")
		Mode.REPAIR:
			if _target != null and is_instance_valid(_target):
				_target.begin_repair()
				_holding = true
				_hold_touch_index = touch_index
				_style_btn(true)
		Mode.SPENT:
			if Time.get_ticks_msec() >= _suppress_until:
				_hint("机关已在场上")
		Mode.COOLDOWN:
			if Time.get_ticks_msec() >= _suppress_until:
				_hint("机关整备中，稍等片刻")
		Mode.OK:
			if Time.get_ticks_msec() >= _suppress_until:
				_hint("机关完好，无需维修")
		_:
			# 状态轮询还没刷出来时的兜底：手里确实有编制就照常布设，
			# 不让「点了没反应」发生在一次合法的布设上。
			if TurretCommand.next_ready(GameManager.player) != null:
				_do_deploy()

func _release_primary(touch_index: int = -999) -> void:
	if not _holding:
		return
	if touch_index != -999 and touch_index != _hold_touch_index:
		return
	_holding = false
	_hold_touch_index = -999
	if _target != null and is_instance_valid(_target):
		_target.end_repair()
	if _ring != null:
		_ring.set_ratio(0.0)
	_style_btn(false)

## 主键热区：与技能键同一算法（中心取 pivot，缩放由 radius 跟上），
## 不再用 get_global_rect().get_center() —— 根节点缩放时那个中心会偏出视觉圆心。
func _is_point_on_btn(pos: Vector2) -> bool:
	if _btn == null or not is_instance_valid(_btn) or not _btn.is_visible_in_tree():
		return false
	var r := BTN_SIZE.x * 0.5 * SettingsManager.mechanism_btn_scale() + HIT_PAD
	return pos.distance_to(center_px()) <= r

func _is_point_on_recall(pos: Vector2) -> bool:
	if _recall_btn == null or not is_instance_valid(_recall_btn) or not _recall_btn.is_visible_in_tree():
		return false
	var center := _recall_btn.get_global_rect().get_center()
	var r := RECALL_SIZE * 0.5 * SettingsManager.mechanism_btn_scale() + RECALL_HIT_PAD
	return pos.distance_to(center) <= r

# ---------------- 动作 ----------------

func _do_deploy() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_deploy_time < 150:
		return
	_last_deploy_time = now
	var player = GameManager.player
	var turret := TurretCommand.deploy_at_player(player)
	if turret == null:
		_play_reject_fx()
		_hint_deploy_denied(TurretCommand.deny_reason(player))
		return
	_suppress_until = Time.get_ticks_msec() + 250
	var spawner: Node = GameManager.wave_spawner
	if spawner != null and int(spawner.get("phase")) == int(WaveSpawner.Phase.CLEARING):
		turret.set_wave_active(false)
	_play_pop_fx()
	# 一次性引导：首次真布设时弹一条情境提示（HudContextTips 自带去重门控）
	GameManager.context_tip_requested.emit(&"mechanism")
	# 立刻刷新状态：布设后脚下即可维修/收回，不等下一拍 10Hz
	_poll_state()

func _hint_deploy_denied(reason: String) -> void:
	match reason:
		"no_charge":
			_hint("机关已在场上")
		"occupied":
			_hint("离机关太近，走远一点")
		"no_player":
			_hint("尚未进入战斗")
		_:
			# 状态都对、链路自己失败了：按 TurretCommand 记下的原因码说清是哪一环，
			# 别再统一报一句「现在不能布设机关」（玩家看不懂，排查也拿不到线索）。
			_hint_deploy_failed()

## 布设链路内部失败的具体文案：原因码同时写进设备日志（file_logging 开着，可查 godot.log）
func _hint_deploy_failed() -> void:
	var code := TurretCommand.last_error
	push_warning("[TURRET] 机关布设内部失败：%s" % code)
	match code:
		"scene":
			_hint("机关模型没加载出来")
		"cap":
			_hint("机关编制已满")
		_:
			_hint("布设失败，请再试一次")

func _hint(text: String) -> void:
	if text.is_empty():
		return
	UpdateManager.show_toast(text, GameStyle.BAD, 1.4)

func _do_recall() -> void:
	if _edit_mode:
		return
	var now := Time.get_ticks_msec()
	# 原生触点与鼠标模拟可能跨帧各来一发：只按帧去重会连收两座，补一道 200ms 时间闸
	if now - _last_recall_time < 200:
		return
	if not _recall_frame_guard():
		return
	_last_recall_time = now
	var player = GameManager.player
	if player == null or not is_instance_valid(player):
		return
	if not TurretCommand.recall_nearest(player, player.global_position):
		# 收回已不限距离，唯一会失败的情况就是场上真没有机关（或机关正被收回）。
		_hint("场上没有机关")
		_play_reject_fx()
		return
	_release_primary(-999)
	_suppress_until = Time.get_ticks_msec() + 250
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
			_release_primary(-999)
	# 布设落点虚影逐帧跟随玩家（10Hz 走位会一格一格跳），代价只有几个圆
	_update_preview()
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
	var has_weapon := false
	var has_turret := false
	var recall_near := false

	if player != null and is_instance_valid(player):
		var weapons: Array = TurretCommand.mechanism_weapons(player)
		has_weapon = not weapons.is_empty()
		ready = TurretCommand.ready_count(player)
		service = TurretCommand.service_count(player)
		next_target = TurretCommand.nearest_turret(player, player.global_position,
			BalanceTurret.INTERACT_RADIUS)
		var turrets: Array[TurretUnit] = TurretCommand.deployed_turrets(player)
		has_turret = not turrets.is_empty()
		# 收回不限距离（BalanceTurret.RECALL_RADIUS <= 0）：场上有机关就随时能收最近那座，
		# 键亮着 == 按下去真能收（显隐与 recall_nearest 读同一个候选口）
		recall_near = has_turret and TurretCommand.recall_candidate(player, player.global_position) != null

		if next_target != null and next_target.durability_ratio() < 0.999:
			# 1) 交互半径内最近机关 durability_ratio() < 0.999 → Mode.REPAIR（维修优先）
			next_mode = Mode.REPAIR
			accent = GameStyle.JADE
			sub_text = "%d%%" % roundi(next_target.durability_ratio() * 100.0)
		elif ready > 0 and TurretCommand.can_deploy(player):
			# 2) 否则 ready > 0 且落点为空 → Mode.DEPLOY（站在满耐久机关旁也能布设）
			next_mode = Mode.DEPLOY
			accent = GameStyle.GOLD
			badge_text = "×%d" % ready
			var w = TurretCommand.next_ready(player)
			if w != null:
				sub_text = String(WeaponData.get_def(String(w.weapon_def_id)).get("name", ""))
		elif next_target != null:
			# 3) 交互半径内有机关
			if ready > 0:
				# 有编制但落点被占 → 「太近」+ 提示挪位
				next_mode = Mode.TOO_CLOSE
				accent = GameStyle.GREY
				badge_text = "×%d" % ready
				sub_text = "走远一点"
			else:
				next_mode = Mode.OK
				accent = GameStyle.GREY
				sub_text = "100%"
		elif ready > 0:
			# 4) 有编制（理论上落点被占时 next_target 必非空；这里只做兜底）
			next_mode = Mode.DEPLOY
			accent = GameStyle.GOLD
			badge_text = "×%d" % ready
		elif has_turret:
			# 5) 编制用尽、场上还有机关 → 键不收起，只报「在场」状态（收回键靠近才出现）
			next_mode = Mode.SPENT
			accent = GameStyle.GREY
		elif has_weapon:
			# 6) 有机关武器、无编制、场上无机关 = 收回后的 2 秒整备倒数
			next_mode = Mode.COOLDOWN
			accent = GameStyle.GREY
			var left := TurretCommand.cooldown_left(player)
			if left > 0.05:
				sub_text = "整备 %d秒" % int(ceil(left))
			else:
				sub_text = "整备中"
		# 7) 否则 Mode.HIDDEN

	# 目标换了（或离开范围）：正在按的那次维修收手，避免修到一半换目标
	if _target != next_target and _holding:
		_release_primary(-999)

	_mode = next_mode
	_target = next_target
	_has_turret = has_turret
	_recall_near = recall_near
	# 芯片只在「附近这台本身不缺维修」时提示别处的机器（站在坏机关旁边时芯片是废话）
	var near_needs := next_target != null and next_target.needs_service()
	_apply_face(accent, sub_text, badge_text, service, near_needs)
	_apply_visibility()
	_update_preview()

## 键面文案/副读数/角标/芯片/收回键：只在读数变化时重写，避免每帧排版
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
	# 独立收回键：只在靠近自己的机关时出现（走远不占屏，也不在布设键上写收回提示）
	if _recall_btn != null:
		var want_recall := _has_turret and _recall_near and not _edit_mode
		if _recall_btn.visible != want_recall:
			_recall_btn.visible = want_recall
		if want_recall:
			_recall_btn.modulate.a = 1.0
			var raccent: Color = GameStyle.JADE
			if raccent != _recall_accent:
				_recall_accent = raccent
				SkillButtonView.style_circle_action(_recall_btn, raccent, RECALL_FONT)
			var rsub := "可收回"
			if rsub != _recall_sub_key:
				_recall_sub_key = rsub
				if _recall_sub != null:
					_recall_sub.text = rsub
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
		Mode.TOO_CLOSE:
			return FACE_TOO_CLOSE
		Mode.SPENT:
			return FACE_SPENT
		Mode.COOLDOWN:
			return FACE_COOLDOWN
	return FACE_EDIT

## 收放：只在状态真的翻转时起 Tween（10Hz 轮询不能反复重建动画）。
## 圆键收起后根节点可能还要留着（收回键 / 待修芯片），所以三者显隐分开管。
func _apply_visibility() -> void:
	var want_circle := _mode != Mode.HIDDEN
	if _circle_root.visible != want_circle:
		_circle_root.visible = want_circle
	var want_recall := _recall_btn != null and _recall_btn.visible
	var want_any := want_circle or want_recall or (_chip != null and _chip.visible)
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
		# 不把 alpha 强行拉回 1：淡入途中翻成收起时，从当前透明度接着淡出，
		# 否则会先闪一帧全亮再消失（布设后 0.16s 内立刻收回就能看到）。
		_anim_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_anim_tween.tween_property(self, "modulate:a", 0.0, 0.18)
		_anim_tween.tween_callback(func() -> void:
			# 淡出途中可能又被点回来（刚收回又买到新机关）：那时把透明度收回来即可
			var now_want := _mode != Mode.HIDDEN or (_recall_btn != null and _recall_btn.visible) \
				or (_chip != null and _chip.visible)
			modulate.a = 1.0
			scale = _base_scale
			if not now_want:
				visible = false
		)

func _kill_anim_tween() -> void:
	if _anim_tween != null and _anim_tween.is_valid():
		_anim_tween.kill()
	_anim_tween = null

## 战斗门控（照 HudSkillButton._is_gameplay_active 口径）：暂停/结算/加点/商店不接单；
## 波间 WAITING 也放行 —— 玩家可以在下一波开打前把机关摆好，开波时 start_wave 统一激活。
func _is_gameplay_active() -> bool:
	if not is_visible_in_tree() or get_tree().paused:
		return false
	if not GameManager.run_started or GameManager.is_game_over:
		return false
	var spawner: Node = GameManager.wave_spawner
	if spawner != null:
		var phase = spawner.get("phase")
		if phase != null:
			var iphase := int(phase)
			if iphase != int(WaveSpawner.Phase.WAITING) \
				and iphase != int(WaveSpawner.Phase.FIGHT) \
				and iphase != int(WaveSpawner.Phase.CLEARING):
				return false
	return true

# ---------------- 布设落点预览 ----------------

## 懒建预览节点：挂在玩家所在的战场层（不是玩家子节点，避免跟着人跑）
func _ensure_preview() -> void:
	if _preview != null and is_instance_valid(_preview):
		return
	var player = GameManager.player
	if player == null or not is_instance_valid(player):
		return
	var layer: Node = player.get_parent()
	if layer == null or not is_instance_valid(layer):
		return
	_preview = DEPLOY_PREVIEW.new()
	_preview.name = "TurretDeployPreview"
	# 贴地：画在实体下面，别让射程环盖住人物/机关本体
	_preview.z_index = -1
	layer.add_child(_preview)
	_preview.visible = false

## 只在「布设 / 太近」两态显示：绿色虚影 = 可落位，红色 = 落点被占；
## 外圈射程环半径与 TurretUnit.effective_range() 同一条乘区，画多大就判多大。
func _update_preview() -> void:
	var want_show := _mode in [Mode.DEPLOY, Mode.TOO_CLOSE] and not _edit_mode \
		and _is_gameplay_active()
	if not want_show:
		if _preview != null and is_instance_valid(_preview):
			_preview.visible = false
		return
	var player = GameManager.player
	var w = TurretCommand.next_ready(player)
	if player == null or not is_instance_valid(player) or w == null:
		if _preview != null and is_instance_valid(_preview):
			_preview.visible = false
		return
	_ensure_preview()
	if _preview == null or not is_instance_valid(_preview):
		return
	var def := WeaponData.get_def(String(w.weapon_def_id))
	var radius := float(def.get("range", 220.0)) * GameManager.attack_range_mult * GameManager.synergy_range_mult
	_preview.call("set_state", TurretCommand.deploy_candidate_pos(player),
		TurretCommand.is_landing_open(player), radius)

# ---------------- 调整模式 / 判据取件口 ----------------

## 进入/退出调整模式：强制亮出键体交给覆盖层拖动（树此时是暂停态）
func set_edit_mode(on: bool) -> void:
	_edit_mode = on
	_kill_anim_tween()
	_release_primary(-999)
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
		if _recall_btn != null:
			_recall_btn.visible = false
		if _chip != null:
			_chip.visible = false
		if _preview != null and is_instance_valid(_preview):
			_preview.visible = false
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

## 兼容旧判据名：现在返回独立收回键
func get_tag() -> Button:
	return _recall_btn

func get_recall_btn() -> Button:
	return _recall_btn

func get_recall_sub() -> Label:
	return _recall_sub

func get_recall_icon() -> Control:
	return _recall_icon

func get_badge() -> Label:
	return _badge

func get_chip() -> Label:
	return _chip

func get_sub_label() -> Label:
	return _sub

func get_preview() -> Node2D:
	return _preview

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

## 收回键摆位：优先主键左侧；左缘放不下就改上方，还放不下改右侧。
## 只改 child.position（父节点的缩放/拖动仍由 HudButtonLayout 统一管）。
func _place_recall() -> void:
	if _recall_btn == null:
		return
	var s := SettingsManager.mechanism_btn_scale()
	var center := center_px()
	var vp := get_viewport_rect().size
	var half := RECALL_SIZE * 0.5 * s
	var off := (BTN_SIZE.x * 0.5 + RECALL_GAP + RECALL_SIZE * 0.5) * s
	var left_center := center.x - off
	var above_center := center.y - off
	if left_center - half >= 4.0:
		_recall_btn.position = Vector2(-RECALL_SIZE - RECALL_GAP,
			(BTN_SIZE.y - RECALL_SIZE) * 0.5)
	elif above_center - half >= 4.0:
		_recall_btn.position = Vector2((BTN_SIZE.x - RECALL_SIZE) * 0.5,
			-RECALL_SIZE - RECALL_GAP)
	elif center.x + off + half <= vp.x - 4.0:
		_recall_btn.position = Vector2(BTN_SIZE.x + RECALL_GAP,
			(BTN_SIZE.y - RECALL_SIZE) * 0.5)
	else:
		# 三面都放不下（极端小屏）：仍然挂在左侧，至少跟着主键走
		_recall_btn.position = Vector2(-RECALL_SIZE - RECALL_GAP,
			(BTN_SIZE.y - RECALL_SIZE) * 0.5)

func _apply_layout() -> void:
	HudButtonLayout.apply(self, SettingsManager.mechanism_btn_xy(),
		SettingsManager.mechanism_btn_scale(), BTN_SIZE)
	_base_scale = scale
	_center_chip()
	_place_recall()

func _exit_tree() -> void:
	if _preview != null and is_instance_valid(_preview):
		_preview.queue_free()
		_preview = null
