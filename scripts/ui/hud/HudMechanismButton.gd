class_name HudMechanismButton
extends Control

## 机关三键（2026-11-03 手动布设改版；2026-11-04 拆分布设 / 维修 / 收回）：
##   主键「维修」常驻（手里有机关武器就一直亮）：
##     交互半径内有磨损机关 → 「维修」+ 耐久%，长按连续回填（走针环 = 回填进度）；
##     交互半径内机关满耐久 → 「完好」+ 100%；
##     人在半径外 + 场上有机关待修 → 「维修」+「走近修」，按下提示走近；
##     场上机关都完好 → 灰面「维修」+「都完好」；还没布设过 → 灰面「维修」+「未布设」。
##   独立小键「布设」：还有未布置的编制才出现（右上角 ×N）：
##     落点为空 → 点按在脚下空地落一座；落点被占 → 键面「太近」+ 抖动 / 报错音；
##     收回后的整备倒数（RECALL_COOLDOWN_SEC=0，链路保留）→ 「整备」。
##   独立小键「收回」：场上有自己的机关就出现（收回不限距离），点按收最近一座。
##
## 为什么要拆（用户真机反馈）：布设与维修原先挤在同一颗键上，想摆机关时常被
## 判成维修；拆开后每颗键只有一个动作，按哪颗就是哪颗。主键常驻也让「维修」
## 始终有个固定落点，不再随场上状态整颗消失。
##
## 外观/摆位/进度环全部复用现成设施：SkillButtonView.style_circle_action
## + CircleProgressOverlay + HudButtonLayout，三颗键钉同一个 SKILL_BTN_SIZE 圆面基准。
## 两颗小键在主键左侧竖排（上「布设」下「收回」），整列底边与主键底边对齐：
## 竖向排是为了手指好够（横排时最外面那颗要往左伸 148px，真机上按不到），
## 底对齐则让整列不往主键下方探，默认位下方的祭坛键在任何缩放档都不会被压住。
## 左缘放不下依次改右侧 / 上方 / 下方，随主键一起缩放 / 拖动；
## 键面语言 = 上图标 + 下单行动作字（布设=落点钉标 / 收回=机关收回到人身上），
## 与主键的扳手图标同一套画法。

const BTN_SIZE := Vector2(SkillButtonView.SKILL_BTN_SIZE, SkillButtonView.SKILL_BTN_SIZE)
## 主键文案字号：与祭坛键同口径（两字 18 号收得进圆面，见 UnitRunner 的键面适配判据）
const BTN_FONT := 18
## 主键副读数（耐久百分比 / 走近修 / 都完好 / 未布设）：10 号才收得进走针环内缘
const SUB_FONT := 10
## 副读数行顶边：主文案（88 圆里 Button 自绘垂直居中约 35..53）下方起排，
## 最底 68 仍在走针环内缘（39.5）之上 —— 压到主文案上会出现「维修」和「60%」叠字
const SUB_TOP := 54.0
## 「N 座待修」芯片相对键面底缘的间距
const CHIP_GAP := 6.0
## 主键动作小图标（维修扳手）：尺寸与顶边 —— 主文案垂直居中约 35..53，
## 图标条占 8..30，压在走针环内缘（39.5）之上，不与文字叠字
const GLYPH_SIZE := 22.0
const GLYPH_TOP := 8.0

## 主键旁的小动作键（布设 / 收回）：与旧收回键同径，两字 12 号收得进 56 圆
const ACTION_SIZE := 56.0
## 小键与主键的间距 / 两颗小键之间的间距（竖排：上布设、下收回）
const ACTION_GAP := 10.0
const ACTION_STACK_GAP := 10.0
const ACTION_FONT := 12
## 小键内部：上图标、下单行动作字（图标 4..32，字 32..48）
const ACTION_ICON_SIZE := 28.0
const ACTION_ICON_TOP := 4.0
const ACTION_TEXT_TOP := 32.0
## 热区外扩：手机手指比鼠标粗，圆形判定比视觉圆再放宽一圈
const HIT_PAD := 14.0
const ACTION_HIT_PAD := 12.0

const FACE_REPAIR := "维修"
const FACE_OK := "完好"
const FACE_DEPLOY := "布设"
const FACE_RECALL := "收回"
## 编制还在但落点被自己的机关占了：布设键改说「太近」，点按抖动 + 提示挪位
const FACE_TOO_CLOSE := "太近"
const FACE_COOLDOWN := "整备"
## 主键在场上有待修机关、但人不在交互半径内时的副读数
const FACE_SPENT_SUB := "走近修"
## 主键灰面副读数：场上机关都完好 / 还没布设过
const SUB_ALL_OK := "都完好"
const SUB_NOT_DEPLOYED := "未布设"
## 调整模式下的占位文案（与祭坛键的「激活」同款：先说这是什么东西）
const FACE_EDIT := "机关"

## 主键（维修）状态（判据读 mode() 做断言）
enum Mode { HIDDEN, IDLE, REPAIR, OK, SPENT }
## 布设小键状态（判据读 deploy_mode() 做断言）
enum DeployMode { HIDDEN, READY, BLOCKED, COOLDOWN }

## 状态轮询间隔：机关状态变化节奏慢（维修由按住驱动，另行逐帧读），10Hz 足够
const POLL_INTERVAL := 0.1

## 布设落点预览（地面虚影 + 射程环）：纯表现层，判定口径与 TurretCommand 同源
const DEPLOY_PREVIEW := preload("res://scripts/weapons/TurretDeployPreview.gd")

## 收回键图标：上「机关盘」下「人物」+ 中间向下回收箭头。
## 56 圆里只放「收回」两个字太空，图标要一眼说出「机关收回人身上」，
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

## 键面动作图标：只画「这一下会做什么」，颜色跟键面主色走。
## 布设 = 落点钉标（向下箭头扎进目标环，与地面落点虚影同一个意义来源）；
## 维修 = 开口扳手（斜柄 + 右上开口的环头），一眼读作「修东西」。
class GlyphIcon extends Control:
	## kind: 0 = 落点钉标（布设），1 = 扳手（维修）
	var kind: int = 0
	var glyph_color: Color = GameStyle.GOLD

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	## 只在读数变化时重绘（10Hz 轮询不许每帧 queue_redraw）
	func set_state(next_kind: int, color: Color) -> void:
		if next_kind == kind and color == glyph_color:
			return
		kind = next_kind
		glyph_color = color
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		if kind == 0:
			# 落点钉标：目标环 + 中心点 + 上方下插箭头
			var ring_c := Vector2(w * 0.5, w * 0.6)
			draw_arc(ring_c, w * 0.28, 0.0, TAU, 18, glyph_color, 1.8, true)
			draw_circle(ring_c, w * 0.09, glyph_color)
			draw_line(Vector2(w * 0.5, w * 0.05), Vector2(w * 0.5, w * 0.2), glyph_color, 1.9)
			draw_colored_polygon(PackedVector2Array([
				Vector2(w * 0.5, w * 0.34),
				Vector2(w * 0.34, w * 0.14),
				Vector2(w * 0.66, w * 0.14)]), glyph_color)
		else:
			# 扳手：斜柄从左下上伸，环头在右上开口（开口朝向右上 = 拧那颗螺母）
			var head := Vector2(w * 0.64, w * 0.34)
			draw_line(Vector2(w * 0.28, w * 0.74), head, glyph_color, 3.2)
			draw_circle(Vector2(w * 0.28, w * 0.74), w * 0.085, glyph_color)
			var gap := -PI * 0.25
			draw_arc(head, w * 0.2, gap + 0.95, gap + TAU - 0.95, 16, glyph_color, 2.3, true)

var _btn: Button = null
var _ring: SkillButtonView.CircleProgressOverlay = null
var _sub: Label = null
## 键面动作小图标（维修扳手）；false = 当前隐藏
var _glyph: GlyphIcon = null
var _glyph_visible: bool = false
## 独立布设键：上落点钉标 + 下「布设 / 太近 / 整备」+ 右上角 ×N
var _deploy_btn: Button = null
var _deploy_icon: GlyphIcon = null
var _deploy_label: Label = null
var _deploy_badge: Label = null
## 独立收回键：图标 + 单行「收回」
var _recall_btn: Button = null
var _recall_icon: RecallIcon = null
var _recall_sub: Label = null
var _chip: Label = null
## 圆键容器：主键收起时整块隐藏（小键/芯片挂在根上，不受它影响）
var _circle_root: Control = null

var _mode: int = Mode.HIDDEN
var _deploy_state: int = DeployMode.HIDDEN
var _target: TurretUnit = null
var _accent: Color = GameStyle.GOLD
var _face_key: String = ""
var _sub_key: String = ""
var _deploy_face_key: String = ""
var _deploy_badge_key: String = ""
## 小键配色只在状态翻转时重刷，10Hz 轮询不反复建 StyleBox
var _deploy_accent: Color = Color(-1, -1, -1, -1)
var _recall_accent: Color = Color(-1, -1, -1, -1)
## 场上有没有自己的机关 / 收回候选是否成立
var _has_turret: bool = false
var _recall_near: bool = false
## 待布设编制（布设键角标 ×N）
var _ready_count: int = 0
## 小键摆位是否需要重算（显隐 / 布局变化时才动，抖动补间不会被每拍轮询打断）
var _actions_placed: bool = true
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
var _last_deploy_press_frame: int = -1
var _last_deploy_time: int = -10000
var _last_recall_frame: int = -1
var _last_recall_time: int = -10000
## 动作后的短静默：触屏原生事件与模拟鼠标可能跨帧各来一发，
## 上一发已经布设/收回成功时，下一发不许再弹「完好/走近修」之类的提示。
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
		_deploy_accent = Color(-1, -1, -1, -1)
		_recall_accent = Color(-1, -1, -1, -1)
		if _recall_icon != null:
			_recall_icon.queue_redraw()
		_apply_face(_accent, _sub_key, TurretCommand.service_count(GameManager.player), false)
	)

# ---------------- 构建 ----------------

func _build() -> void:
	# 圆键容器：主键与它的走针环/副读数/图标都挂在这上面，收起时整块隐藏
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

	# 副读数：维修/完好显示耐久百分比；远距引导显示「走近修」；无待办显示「都完好 / 未布设」
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

	# 键面动作图标（维修扳手）：压在文字上方一条，颜色跟键面主色走
	_glyph = GlyphIcon.new()
	_glyph.name = "GlyphIcon"
	_glyph.kind = 1
	_glyph.size = Vector2(GLYPH_SIZE, GLYPH_SIZE)
	_glyph.position = Vector2((BTN_SIZE.x - GLYPH_SIZE) * 0.5, GLYPH_TOP)
	_glyph.visible = false
	_btn.add_child(_glyph)

	# 独立「布设」键：挂根节点（不随主键收起），有未布置的编制才出现
	_deploy_btn = _make_action_button("DeployButton")
	_deploy_btn.button_down.connect(_deploy_pressed)
	_deploy_icon = GlyphIcon.new()
	_deploy_icon.name = "DeployIcon"
	_deploy_icon.kind = 0
	_deploy_icon.glyph_color = GameStyle.GOLD
	_deploy_icon.size = Vector2(ACTION_ICON_SIZE, ACTION_ICON_SIZE)
	_deploy_icon.position = Vector2((ACTION_SIZE - ACTION_ICON_SIZE) * 0.5, ACTION_ICON_TOP)
	_deploy_btn.add_child(_deploy_icon)
	_deploy_label = _make_action_label()
	_deploy_label.text = FACE_DEPLOY
	_deploy_btn.add_child(_deploy_label)
	# ×N 编制角标：56 圆里放不下第二行，角标贴在键面右上角外侧
	_deploy_badge = GameStyle.chip_label(" ", GameStyle.INK, Color(-1, -1, -1, -1), 10)
	_deploy_badge.name = "DeployBadge"
	_deploy_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deploy_badge.visible = false
	_deploy_btn.add_child(_deploy_badge)

	# 独立「收回」键：场上有自己的机关就出现（收回不限距离）
	_recall_btn = _make_action_button("RecallButton")
	_recall_btn.button_down.connect(_do_recall)
	_recall_icon = RecallIcon.new()
	_recall_icon.name = "RecallIcon"
	_recall_icon.size = Vector2(ACTION_ICON_SIZE, ACTION_ICON_SIZE)
	_recall_icon.position = Vector2((ACTION_SIZE - ACTION_ICON_SIZE) * 0.5, ACTION_ICON_TOP)
	_recall_btn.add_child(_recall_icon)
	_recall_sub = _make_action_label()
	_recall_sub.text = FACE_RECALL
	_recall_btn.add_child(_recall_sub)

	# 「N 座待修」芯片：挂在根上（不随主键一起收起），点按无动作（纯提示）
	_chip = GameStyle.chip_label(" ", GameStyle.BAD, Color(-1, -1, -1, -1), 11)
	_chip.name = "ServiceChip"
	_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_chip.visible = false
	add_child(_chip)

	# 键位提示签（桌面/桌面浏览器专属）：F 维修；R 布设 / G 收回由主键的 F 签同一套键位表说明
	if SkillButtonView.key_hint_enabled():
		_circle_root.add_child(SkillButtonView.make_key_chip("F"))

## 小键公共外观：56 圆 + 12 号字 + 自己带动作音（按下动作自己播 ui_back / 布设音）
func _make_action_button(node_name: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = ""
	b.focus_mode = Control.FOCUS_NONE
	b.visible = false
	b.custom_minimum_size = Vector2(ACTION_SIZE, ACTION_SIZE)
	b.size = Vector2(ACTION_SIZE, ACTION_SIZE)
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.set_meta("sfx_wired", true)
	SkillButtonView.style_circle_action(b, GameStyle.JADE, ACTION_FONT)
	add_child(b)
	return b

## 小键单行动作字：图标下方一行，12 号字 + 描边压住圆面底
func _make_action_label() -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font = GameStyle.body_font()
	ls.font_size = ACTION_FONT
	ls.outline_size = 2
	ls.outline_color = Color(0.02, 0.03, 0.06, 0.9)
	l.label_settings = ls
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = Vector2(0, ACTION_TEXT_TOP)
	l.size = Vector2(ACTION_SIZE, 16)
	return l

## 主键样式：按当前模式取主色，按住维修整面翻实底（状态由底色 + 走针环说）
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

## 原生第二指触摸（GameHUD._input 转发）：左手拉摇杆 + 右手维修/布设/收回。
## 三颗键的热区都用圆形判定（与技能键同款），重叠带按「离谁的心更近」分配。
func handle_engine_input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch):
		return
	if not _is_gameplay_active():
		return
	var touch := event as InputEventScreenTouch
	if touch.pressed:
		# 先现算一拍状态：10Hz 轮询在快速走位时可能还停在上一格，
		# 直接用旧状态判会把「布设」误判成「完好」而静默吞掉这一下。
		_poll_state()
		match _hit_action(touch.position):
			0:
				_press_primary(touch.index)
			1:
				_deploy_pressed()
			2:
				_do_recall()
	elif _holding:
		# 松开分支只认匹配的 index，左手松摇杆不打断右手维修
		if touch.index == _hold_touch_index:
			_release_primary(touch.index)

## 键盘 F：与主键同一套动作（长按维修 / 点按给状态提示）
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

## 键盘 R：布设（与独立布设键同一动作）—— 键亮着才吃
func deploy_by_key() -> void:
	if _edit_mode or not _is_gameplay_active():
		return
	if _deploy_state == DeployMode.HIDDEN:
		return
	_deploy_pressed()

## 键盘 G：收回（与独立收回键同一动作）—— 口径与收回键显隐同源：
## 场上有自己的机关就能收（收回不限距离），不要求主键此刻可见
func recall_by_key() -> void:
	if _edit_mode or not _has_turret or not _is_gameplay_active():
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

## 布设小键当前状态（判据用；HIDDEN = 没有可布设编制）
func deploy_mode() -> int:
	return _deploy_state

## 按帧去重：触屏原生事件与 Godot 的鼠标模拟会各来一发，不去重会一次点按布设两座
func _press_frame_guard() -> bool:
	var cur := Engine.get_process_frames()
	if _last_press_frame == cur:
		return false
	_last_press_frame = cur
	return true

## 布设同样是「按一下就走一个动作」，原生触点与鼠标模拟必须同帧只认一次
func _deploy_frame_guard() -> bool:
	var cur := Engine.get_process_frames()
	if _last_deploy_press_frame == cur:
		return false
	_last_deploy_press_frame = cur
	return true

## 收回同样要按帧去重：原生触点与鼠标模拟会各触发一次 pressed
func _recall_frame_guard() -> bool:
	var cur := Engine.get_process_frames()
	if _last_recall_frame == cur:
		return false
	_last_recall_frame = cur
	return true

## 主键只有维修一个动作：够得着就按住修，够不着就给一句为什么修不了。
func _press_primary(touch_index: int = -1) -> void:
	if _edit_mode or not _press_frame_guard():
		return
	match _mode:
		Mode.REPAIR:
			if _target != null and is_instance_valid(_target):
				_target.begin_repair()
				_holding = true
				_hold_touch_index = touch_index
				_style_btn(true)
		Mode.SPENT:
			if Time.get_ticks_msec() >= _suppress_until:
				_hint("走近机关再维修")
		Mode.OK:
			if Time.get_ticks_msec() >= _suppress_until:
				_hint("机关完好，无需维修")
		Mode.IDLE:
			if Time.get_ticks_msec() >= _suppress_until:
				_hint("机关都完好，无需维修" if _has_turret else "还没有布设机关")

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

## 原生触点落到哪颗键：热区取圆，重叠带按「离谁的心更近」判 ——
## 小键热区外扩后与主键会叠一小圈，按最近心分配才不会点布设误起维修。
## 返回 0 = 主键、1 = 布设、2 = 收回、-1 = 都没点到。
func _hit_action(pos: Vector2) -> int:
	var best := -1
	var best_d := 1.0e9
	var s := SettingsManager.mechanism_btn_scale()
	if _mode != Mode.HIDDEN and _btn != null:
		var d := pos.distance_to(center_px())
		if d <= BTN_SIZE.x * 0.5 * s + HIT_PAD:
			best = 0
			best_d = d
	if _deploy_btn != null and _deploy_btn.visible:
		var d := pos.distance_to(_action_center(_deploy_btn))
		if d <= ACTION_SIZE * 0.5 * s + ACTION_HIT_PAD and d < best_d:
			best = 1
			best_d = d
	if _recall_btn != null and _recall_btn.visible:
		var d := pos.distance_to(_action_center(_recall_btn))
		if d <= ACTION_SIZE * 0.5 * s + ACTION_HIT_PAD and d < best_d:
			best = 2
			best_d = d
	return best

## 小键视觉中心（设计坐标）：父节点缩放围绕主键 pivot，子键局部坐标要跟着换算，
## 不能直接读 get_global_rect() 的中心（缩放档位下那个口径会漂）。
func _action_center(action: Button) -> Vector2:
	var s := SettingsManager.mechanism_btn_scale()
	var local := action.position + Vector2(ACTION_SIZE, ACTION_SIZE) * 0.5
	return position + pivot_offset + (local - pivot_offset) * s

# ---------------- 动作 ----------------

## 布设键按下：只有布设这一个动作，拒绝时也只抖这颗键，不碰维修键
func _deploy_pressed() -> void:
	if _edit_mode or not _is_gameplay_active():
		return
	if not _deploy_frame_guard():
		return
	# 鼠标/触屏路径没有 handle_engine_input 的现算一拍：按下时自己再算一次，
	# 免得 10Hz 轮询慢半拍，把「已经能布设」误判成「太近」。
	_poll_state()
	match _deploy_state:
		DeployMode.READY:
			_do_deploy()
		DeployMode.BLOCKED:
			_play_reject_fx(_deploy_btn)
			_hint("离机关太近，走远一点")
		DeployMode.COOLDOWN:
			if Time.get_ticks_msec() >= _suppress_until:
				_hint("机关整备中，稍等片刻")

func _do_deploy() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_deploy_time < 150:
		return
	_last_deploy_time = now
	var player = GameManager.player
	var turret := TurretCommand.deploy_at_player(player)
	if turret == null:
		_play_reject_fx(_deploy_btn)
		_hint_deploy_denied(TurretCommand.deny_reason(player))
		return
	_suppress_until = Time.get_ticks_msec() + 250
	var spawner: Node = GameManager.wave_spawner
	if spawner != null and int(spawner.get("phase")) == int(WaveSpawner.Phase.CLEARING):
		turret.set_wave_active(false)
	_play_pop_fx(_deploy_btn)
	# 一次性引导：首次真布设时弹一条情境提示（HudContextTips 自带去重门控）
	GameManager.context_tip_requested.emit(&"mechanism")
	# 立刻刷新状态：布设后脚下即可维修/收回，不等下一拍 10Hz
	_poll_state()

func _hint_deploy_denied(reason: String) -> void:
	match reason:
		"no_charge":
			_hint("先收回机关，才能再布设")
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
		_play_reject_fx(_recall_btn)
		return
	_release_primary(-999)
	_suppress_until = Time.get_ticks_msec() + 250
	AudioManager.play_sfx("ui_back", 0.7)
	_poll_state()

func _play_pop_fx(target: Button) -> void:
	if target == null:
		return
	target.pivot_offset = target.size * 0.5
	var tw = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(target, "scale", Vector2(0.88, 0.88), 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(target, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## 动作被拒（落点被自己的机关占了 / 没编制）：左右微抖 + 报错音，不静默
func _play_reject_fx(target: Button) -> void:
	if target == null or _shaking:
		return
	_shaking = true
	var orig_x := target.position.x
	var tw = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(target, "position:x", orig_x - 5.0, 0.04)
	tw.tween_property(target, "position:x", orig_x + 5.0, 0.04)
	tw.tween_property(target, "position:x", orig_x, 0.04)
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
	var accent: Color = GameStyle.GREY
	var service := 0
	var has_weapon := false
	var has_turret := false
	var recall_near := false
	var deploy_state := DeployMode.HIDDEN

	if player != null and is_instance_valid(player):
		var weapons: Array = TurretCommand.mechanism_weapons(player)
		has_weapon = not weapons.is_empty()
		ready = TurretCommand.ready_count(player)
		service = TurretCommand.service_count(player)
		# 维修目标优先「最需要修」（耐久最低，停摆最优先），再按距离；
		# 没有待修机关时才退回最近一座，供「完好」读数用。
		var repair_target := TurretCommand.repair_candidate(player, player.global_position,
			BalanceTurret.INTERACT_RADIUS)
		var near_target := TurretCommand.nearest_turret(player, player.global_position,
			BalanceTurret.INTERACT_RADIUS)
		next_target = repair_target if repair_target != null else near_target
		# 按住维修时锁定当前目标：另一座更破也不许中途换手（换手等于白丢这次按压）。
		# 目标修满后本身就不再是 repair_candidate，下一次轮询自然会切到下一座待修的。
		if _holding and _target != null and is_instance_valid(_target) \
				and _target.durability < BalanceTurret.MAX_DURABILITY - 0.001 \
				and _target.global_position.distance_to(player.global_position) <= BalanceTurret.INTERACT_RADIUS:
			next_target = _target
		var turrets: Array[TurretUnit] = TurretCommand.deployed_turrets(player)
		has_turret = not turrets.is_empty()
		# 收回不限距离（BalanceTurret.RECALL_RADIUS <= 0）：场上有机关就随时能收最近那座，
		# 键亮着 == 按下去真能收（显隐与 recall_nearest 读同一个候选口）
		recall_near = has_turret and TurretCommand.recall_candidate(player, player.global_position) != null

		# 布设键：有未布置的编制才出现（落点被占也亮，键面改说「太近」）；
		# 编制全在场上且还在整备倒数时显示剩余窗口。
		if ready > 0:
			deploy_state = DeployMode.READY if TurretCommand.can_deploy(player) else DeployMode.BLOCKED
		elif TurretCommand.cooldown_left(player) > 0.05:
			deploy_state = DeployMode.COOLDOWN

		if has_weapon:
			if next_target != null and next_target.durability_ratio() < 0.999:
				# 1) 交互半径内有磨损机关 → 维修态（维修优先于一切）
				next_mode = Mode.REPAIR
				accent = GameStyle.JADE
				sub_text = "%d%%" % roundi(next_target.durability_ratio() * 100.0)
			elif next_target != null:
				# 2) 交互半径内的机关满耐久 → 完好（有编制时布设键独立在旁边）
				next_mode = Mode.OK
				accent = GameStyle.GREY
				sub_text = "%d%%" % roundi(next_target.durability_ratio() * 100.0)
			elif service > 0:
				# 3) 人不在半径内、场上有机关待修 → 键面「维修」+「走近修」引导走回去修
				next_mode = Mode.SPENT
				accent = GameStyle.JADE
				sub_text = FACE_SPENT_SUB
			else:
				# 4) 常驻待命：维修键不消失，灰面说明现在没得修
				next_mode = Mode.IDLE
				accent = GameStyle.GREY
				sub_text = SUB_ALL_OK if has_turret else SUB_NOT_DEPLOYED
		# 5) 没有机关武器 → Mode.HIDDEN（整颗收起）

	# 目标换了（或离开范围）：正在按的那次维修收手，避免修到一半换目标
	if _target != next_target and _holding:
		_release_primary(-999)

	_mode = next_mode
	_target = next_target
	_has_turret = has_turret
	_recall_near = recall_near
	_ready_count = ready
	_deploy_state = DeployMode.HIDDEN if _edit_mode else deploy_state
	# 芯片只在「附近这台本身不缺维修」时提示别处的机器（站在坏机关旁边时芯片是废话）
	var near_needs := next_target != null and next_target.needs_service()
	_apply_face(accent, sub_text, service, near_needs)
	_apply_visibility()
	_update_preview()

## 主键文案/副读数/图标/芯片 + 两颗小键的显隐与键面：只在读数变化时重写，避免每帧排版
func _apply_face(accent: Color, sub_text: String, service: int, near_needs: bool) -> void:
	var face := FACE_EDIT if _edit_mode else _face_for_mode(_mode)
	if face != _face_key:
		_face_key = face
		if _btn != null:
			_btn.text = face
	if accent != _accent:
		_accent = accent
		_style_btn(_holding)
	# 键面动作图标：维修 / 远距维修引导亮扳手；颜色跟键面主色走
	# （主题换色回调会带着新 accent 再进来，图标跟得上）
	var want_glyph := not _edit_mode and _mode in [Mode.REPAIR, Mode.SPENT]
	if _glyph != null:
		if want_glyph != _glyph_visible:
			_glyph_visible = want_glyph
			_glyph.visible = want_glyph
		if want_glyph:
			_glyph.set_state(1, accent)
	if sub_text != _sub_key:
		_sub_key = sub_text
		if _sub != null:
			_sub.text = sub_text
	_apply_deploy_key()
	_apply_recall_key()
	# 待修芯片：主键灰面待命时照样提示（否则找不到已经走远的那几台）
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

## 布设小键：独立动作、独立反馈 —— 有编制亮「布设 ×N」，落点被占亮灰「太近」
func _apply_deploy_key() -> void:
	if _deploy_btn == null:
		return
	var want := _deploy_state != DeployMode.HIDDEN and not _edit_mode
	if _deploy_btn.visible != want:
		_deploy_btn.visible = want
		_actions_placed = false
	if not want:
		# 键收起时角标也收干净：否则下次亮出来会沿用上一拍的 ×N / 显隐状态
		if _deploy_badge.visible:
			_deploy_badge.visible = false
			_deploy_badge_key = ""
		return
	var face := FACE_DEPLOY
	var accent: Color = GameStyle.GOLD
	var badge := ""
	match _deploy_state:
		DeployMode.BLOCKED:
			face = FACE_TOO_CLOSE
			accent = GameStyle.GREY
			badge = "×%d" % _ready_count
		DeployMode.COOLDOWN:
			face = FACE_COOLDOWN
			accent = GameStyle.GREY
		DeployMode.READY:
			badge = "×%d" % _ready_count
	if face != _deploy_face_key:
		_deploy_face_key = face
		_deploy_label.text = face
	if accent != _deploy_accent:
		_deploy_accent = accent
		SkillButtonView.style_circle_action(_deploy_btn, accent, ACTION_FONT)
		_deploy_icon.set_state(0, accent)
	if badge != _deploy_badge_key:
		_deploy_badge_key = badge
		_deploy_badge.visible = not badge.is_empty()
		if not badge.is_empty():
			_deploy_badge.text = " %s " % badge
			_deploy_badge.custom_minimum_size = Vector2(
				GameStyle.chip_pin_w(_deploy_badge.text, GameStyle.body_font(), 10), 0)
			_place_deploy_badge()

## 收回小键：场上有自己的机关就亮（收回不限距离），文本只写「收回」两个字
func _apply_recall_key() -> void:
	if _recall_btn == null:
		return
	var want := _has_turret and _recall_near and not _edit_mode
	if _recall_btn.visible != want:
		_recall_btn.visible = want
		_actions_placed = false
	if not want:
		return
	var raccent: Color = GameStyle.JADE
	if raccent != _recall_accent:
		_recall_accent = raccent
		SkillButtonView.style_circle_action(_recall_btn, raccent, ACTION_FONT)
		_recall_icon.queue_redraw()
	if _recall_sub.text != FACE_RECALL:
		_recall_sub.text = FACE_RECALL

func _face_for_mode(m: int) -> String:
	match m:
		Mode.REPAIR, Mode.SPENT, Mode.IDLE:
			# 远距维修引导 / 待命都用同一个动词，玩家只需认「维修」
			return FACE_REPAIR
		Mode.OK:
			return FACE_OK
	return FACE_EDIT

## 收放：只在状态真的翻转时起 Tween（10Hz 轮询不能反复重建动画）。
## 主键收起后根节点可能还要留着（小键 / 待修芯片），所以三者显隐分开管。
func _apply_visibility() -> void:
	var want_circle := _mode != Mode.HIDDEN
	if _circle_root.visible != want_circle:
		_circle_root.visible = want_circle
	if not _actions_placed:
		_place_action_buttons()
		_actions_placed = true
	var want_recall := _recall_btn != null and _recall_btn.visible
	var want_deploy := _deploy_btn != null and _deploy_btn.visible
	var want_any := want_circle or want_recall or want_deploy or (_chip != null and _chip.visible)
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
			var now_want := _mode != Mode.HIDDEN \
				or (_deploy_btn != null and _deploy_btn.visible) \
				or (_recall_btn != null and _recall_btn.visible) \
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

## 只在布设键亮着（可布设 / 太近）时显示：绿色虚影 = 可落位，红色 = 落点被占；
## 外圈射程环半径与 TurretUnit.effective_range() 同一条乘区，画多大就判多大。
func _update_preview() -> void:
	var want_show := _deploy_state in [DeployMode.READY, DeployMode.BLOCKED] and not _edit_mode \
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

## 进入/退出调整模式：强制亮出主键交给覆盖层拖动（树此时是暂停态）
func set_edit_mode(on: bool) -> void:
	_edit_mode = on
	_kill_anim_tween()
	_release_primary(-999)
	if on:
		_mode = Mode.IDLE
		_deploy_state = DeployMode.HIDDEN
		_accent = GameStyle.GOLD
		# 占位读数：只留「机关」二字，不留上一拍的耐久/编制数字
		_face_key = ""
		if _btn != null:
			_btn.text = FACE_EDIT
		if _sub != null:
			_sub.text = ""
		_sub_key = ""
		_deploy_face_key = ""
		_deploy_badge_key = ""
		_glyph_visible = false
		if _glyph != null:
			_glyph.visible = false
		if _deploy_btn != null:
			_deploy_btn.visible = false
			_deploy_badge.visible = false
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
		_deploy_face_key = ""
		_deploy_badge_key = ""
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

func get_deploy_btn() -> Button:
	return _deploy_btn

func get_deploy_label() -> Label:
	return _deploy_label

func get_deploy_badge() -> Label:
	return _deploy_badge

func get_deploy_icon() -> Control:
	return _deploy_icon

## 兼容旧判据名：现在返回独立收回键
func get_tag() -> Button:
	return _recall_btn

func get_recall_btn() -> Button:
	return _recall_btn

func get_recall_sub() -> Label:
	return _recall_sub

func get_recall_icon() -> Control:
	return _recall_icon

## 判据用：当前主键指向的机关（维修时就是正在修的那座）
func get_target() -> TurretUnit:
	return _target

## 兼容旧判据名：编制角标现在挂在布设小键上
func get_badge() -> Label:
	return _deploy_badge

## 键面动作图标（判据用：可见性 + kind）
func get_glyph() -> Control:
	return _glyph

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

## ×N 角标：56 圆里塞不下第二行，贴在布设键右上角外侧（父节点不裁剪，别往圆内挤图标）
func _place_deploy_badge() -> void:
	_deploy_badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_deploy_badge.offset_right = 2.0
	_deploy_badge.offset_left = 2.0 - _deploy_badge.custom_minimum_size.x
	_deploy_badge.offset_top = -7.0
	_deploy_badge.offset_bottom = 7.0

## 小键摆位：两颗小键在主键左侧竖排（上「布设」下「收回」），整列底边与主键底边对齐。
## 竖向排是为了手指好够：横排时最外面那颗离主键中心 148px，真机上经常按不到；
## 底对齐让整列不往主键下方探，默认位下方的祭坛键在任何缩放档都不会被压住。
## 左缘放不下依次改右侧 / 上方 / 下方，整列最后夹回屏内。
## 主键位置由 HudButtonLayout 管，这里只摆小键。
func _place_action_buttons() -> void:
	var items: Array[Button] = []
	if _deploy_btn != null and _deploy_btn.visible:
		items.append(_deploy_btn)
	if _recall_btn != null and _recall_btn.visible:
		items.append(_recall_btn)
	if items.is_empty():
		return
	var s := SettingsManager.mechanism_btn_scale()
	var vp := get_viewport_rect().size
	var n := items.size()
	var col_h := ACTION_SIZE * n + ACTION_STACK_GAP * (n - 1)
	var half := BTN_SIZE.x * 0.5
	var c := center_px()
	# 整列离主键中心固定 82px（缩放后随 s 放大），底边贴主键底边
	var side_off := (half + ACTION_GAP + ACTION_SIZE) * s
	var bottom_y := BTN_SIZE.y - col_h
	var origin := Vector2(-ACTION_GAP - ACTION_SIZE, bottom_y)
	var left_ok := c.x - side_off >= 4.0
	var right_ok := c.x + side_off <= vp.x - 4.0
	if not left_ok:
		if right_ok:
			origin = Vector2(BTN_SIZE.x + ACTION_GAP, bottom_y)
		elif c.y - (half + ACTION_GAP + col_h) * s >= 4.0:
			origin = Vector2((BTN_SIZE.x - ACTION_SIZE) * 0.5, -ACTION_GAP - col_h)
		elif c.y + (half + ACTION_GAP + col_h) * s <= vp.y - 4.0:
			origin = Vector2((BTN_SIZE.x - ACTION_SIZE) * 0.5, BTN_SIZE.y + ACTION_GAP)
	# 整列夹回屏内（局部坐标 → 屏幕：c + (p - half) * s）
	var min_x := half + (4.0 - c.x) / s
	var max_x := half + (vp.x - 4.0 - c.x) / s - ACTION_SIZE
	var min_y := half + (4.0 - c.y) / s
	var max_y := half + (vp.y - 4.0 - c.y) / s - col_h
	origin.x = clampf(origin.x, min_x, max_x) if min_x <= max_x else min_x
	origin.y = clampf(origin.y, min_y, max_y) if min_y <= max_y else min_y
	for i in n:
		items[i].position = origin + Vector2(0.0, i * (ACTION_SIZE + ACTION_STACK_GAP))

func _apply_layout() -> void:
	HudButtonLayout.apply(self, SettingsManager.mechanism_btn_xy(),
		SettingsManager.mechanism_btn_scale(), BTN_SIZE)
	_base_scale = scale
	_center_chip()
	_place_action_buttons()
	_actions_placed = true

func _exit_tree() -> void:
	if _preview != null and is_instance_valid(_preview):
		_preview.queue_free()
		_preview = null
