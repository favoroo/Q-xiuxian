class_name LevelUpDialog
extends Control

signal stats_requested
signal pause_requested

## 回合后悟道结算面板：战斗中升级只攒点数（GameManager.pending_upgrade_points），
## 回合结束统一在这里一次性加完 —— 加几点就翻几屏候选，每屏 5 个选项、可刷新。
## 2026-10-09 用户指令：「升级就会直接触发加点，在战斗过程中触发加点的体验不好 …
##   改成每一回合结束后统一去加点 … 加点和商店物品要改成 5 个，技能加点也可以刷新一次」。
##
## 摆位口径：5 张卡不按死宽度摆，按 viewport 现算（下面那几个 *_for() 是纯函数，
## 判据 LayoutCheck 用同一份算术量最窄那一档，别处不再抄数字）。
## 纵向放不下交给 CardScroll 竖着滑 —— 全留 + 可滑到，不砍文案也不压字号。
##
## 2026-10-09 用户真机图：「两边有点溢出了，选中的那个卡片上下也有点溢出了」。
## 两头出屏：旧算术把「屏幕宽 - 面板占位」全分给 5 张卡 ⇒ 面板布局盒正好贴住屏幕左右边，
##   而它是斜切平行四边形（引擎绕布局盒竖直中线居中斜切），画出来的两个角各伸出 13.5 单位，
##   被屏幕切掉。现在两头各让出 PANEL_AIR_X + 斜切伸出量。
## 上下出屏：选中卡放大 1.03，而卡片本来就撑满整行 ⇒ 上下各顶出 5 单位，压到信息条与
##   操作栏上。现在由 CardsPad 在这一行上下各留出 pop_gutter_y() 的放大余量。
## 两处都由判据现量（LayoutCheck 的 drawn_rect 认斜切、滚动区滑不动时不许顶出上下边界），不靠肉眼。
##
## 2026-10-09 用户真机图（第二轮）：「左右还是有点显示溢出了，左右间距可以小一点」。
## 上一轮只把「布局盒」让开了，画出来那一圈还剩三处贴边，量屏边的尺全是绿的：
## ① 面板两头离屏只有 PANEL_AIR_X=20 单位（真机 2048 宽上约 34px），配上深色底，
##   看着就是被屏幕切了；
## ② 卡片行的左右留白是 0 ⇒ ScrollContainer 会把最外侧两张卡**斜切画出来的那两个角剪掉**
##   （卡#0 画出来 47.0 而滚动区左边界 53.4），卡角被削平成一条竖线；
## ③ 面板是平行四边形：底边整体会比顶边左移一个 lean（=skew·h/2≈13.4），所以右下角那颗
##   「确认领悟」离画出来的右边只剩 占位 - lean = 9.0 单位，压着边框线（顶栏反过来偏左）。
## 现在按商店那把尺子收口（与 WaveShop 同一口径）：`chrome_x()` 把 lean 算进占位、
## `card_pad_x()` 给滚动区里的卡角留白、卡间缝与卡内边距按用户口径收窄，省下的宽换成 ① 的呼吸量。
## 判据补两条尺：卡角不许被滚动区横向切掉、控件画出来那一圈离所属面板的画出来的边要留白。
##
## 2026-10-12 用户真机（第 8 回合结束那屏）：「手压在卡片上滑不动，要挪到侧面没有卡片遮挡的
## 地方才能滑，这不合理呀」。根因不在滚动没做，在「按下那一拍被谁吃了」：卡体是 PanelContainer
## （默认 STOP），按下就地吃掉不冒泡 ⇒ CardScroll 锁不住手指拖动，卡盖多大就滑不动多大。
## 现在整行建完过一遍 GameStyle.swipeable（卡与卡内图标/角标降成 PASS），并把「松开=选中」
## 换成 GameStyle.tap 的完整手势识别（否则能滑之后，划一下列表就换一张选中）。
## 判据：tests/ScrollSwipeCheck.tscn（逐落点验按下能起手）+ tests/TapSwipeCheck.tscn（划动不误选）。

## 旧 CARD_W 留作「宽屏上限」：判据的文案表按 card_inner_w() 现算，不直接读它
const CARD_W := 262.0
## 卡片左右内边距（stylebox content margin）：10→8，把宽还给文案
const CARD_PAD_X := 8.0
## 卡片设计下限：118→100。旧下限在窄屏上会把卡顶到min之上，面板于是**反过来吃掉 PANEL_AIR_X**
## （720 宽时画出来的边只剩 15.6 而声明是 20）；放到 100 之后这一档不再触底，让位算术才算数。
const MIN_CARD_W := 100.0
## 卡间缝隙：用户口径「左右间距小一点」，18 的上限砍到 10（20:9 屏上 15→10）
const CARD_GAP_MIN := 5.0
const CARD_GAP_MAX := 10.0
const CARD_MIN_H := 250.0
## Panel stylebox 的左右内容边距（与 .tscn 的 StyleBoxFlat_panel.content_margin_left/right 同源）
const PANEL_CONTENT_SIDE := 12.0
## .tscn 里 MarginContainer 的左右边距初值，摆位时按 lean 现调（见 chrome_side）
const CHROME_INNER_SIDE := 8.0
## 面板与屏幕之间的呼吸量：上下合计 24（各 12），左右各 34（画出来的斜切角之外再留）
const SCREEN_PAD_Y := 24.0
const PANEL_AIR_X := 34.0
const PANEL_MIN_H := 420.0
## 面板 stylebox 的斜切（弧度），与 LevelUpDialog.tscn 的 StyleBoxFlat_panel.skew 同源
## = GameStyle.SLANT_PLATE 3°。判据会核对两边没漂（改 .tscn 里的 skew 必须同步这里）。
const PANEL_SKEW_RAD := 0.052
## 卡片 stylebox 的斜切（弧度），与 _create_card_entry 里 style.skew = deg_to_rad(3.0) 同源
const CARD_SKEW_RAD := 0.052
## 选中/未选中的缩放倍率：放大倍率同时决定这一行上下要留多少余量（pop_gutter_y）
const SEL_SCALE := 1.03
const DIM_SCALE := 0.97
## 受益装备那一排的格子（2026-10-11 用户指令：「点击这个受益装备的图标，也可以弹窗显示
## 这个对应装备的信息」）：图标从「贴图」升成「键」，格子就是那颗键的面。
## 下限 22 与 HUD 武器槽（36）同量级——再小真机上按不准；上限 30 是别盖过卡片主图。
const BF_CELL_MIN := 22.0
const BF_CELL_MAX := 30.0
## 格内边距：图在格子里留一圈呼吸，描边才读得出是「一颗键」而不是一张贴纸
const BF_CELL_PAD := 3.0
## 格间缝（HFlowContainer 的 h/v_separation）
const BF_CELL_GAP := 3
## 幅度行下面那行「当前 X → Y」预读小字的字号：与「受益装备 · 点按看详情」同一档（11），
## 是注脚不是正文。窄屏放不下时由 wrap_cjk 在箭头处切行，不砍字也不压字号。
const FORECAST_FONT := 11

@onready var panel: PanelContainer = $CenterContainer/Panel
## 内容层（面板本体）：开/关/换屏的淡入淡出只作用在这一层。
## 根节点上还挂着全屏压暗层 DimOverlay —— 它必须全程满不透明，否则面板间切换
## （加点→下一屏加点、加点→金币阁）的淡入缝隙里会把身后的战场与 HUD 整个露出来，
## 用户看到的「确认加点后闪一下别的画面」就是这个（2026-10-16 反馈）。
@onready var content: Control = $CenterContainer
## 面板内容那一层：左右边距按「面板斜切从顶走到底挪的那一截」现调（见 chrome_x）
@onready var content_margin: MarginContainer = $CenterContainer/Panel/MarginContainer
@onready var card_scroll: ScrollContainer = $CenterContainer/Panel/MarginContainer/VBox/CardScroll
@onready var cards_pad: MarginContainer = $CenterContainer/Panel/MarginContainer/VBox/CardScroll/CardsPad
@onready var cards_container: HBoxContainer = $CenterContainer/Panel/MarginContainer/VBox/CardScroll/CardsPad/CardsContainer
@onready var title_label: Label = $CenterContainer/Panel/MarginContainer/VBox/TitleBand/TitleLabel
@onready var info_label: Label = $CenterContainer/Panel/MarginContainer/VBox/InfoBand/InfoLabel
@onready var reroll_btn: Button = $CenterContainer/Panel/MarginContainer/VBox/ActionBar/RerollButton
@onready var confirm_btn: Button = $CenterContainer/Panel/MarginContainer/VBox/ActionBar/ConfirmButton
@onready var gate_label: Label = $CenterContainer/Panel/MarginContainer/VBox/ActionBar/GateLabel

var selected_index: int = -1
var _can_interact: bool = false
var _is_confirming: bool = false
var _card_w: float = CARD_W

## 顶栏圆形剩余加点次数指示与动效
var _points_badge: PanelContainer = null
var _points_label: Label = null
var _badge_tween: Tween = null
var _last_pending: int = -1

## 保存每张卡片的组件引用以便切换选中/未选中视觉状态
var _card_entries: Array[Dictionary] = []

# ---------------- 摆位算术（纯函数，与 WaveShop 同源，统一步入 ShopCardLayout） ----------------

## 这一档屏高下面板该占的高
static func panel_h_for(screen_h: float) -> float:
	return ShopCardLayout.panel_h_for(screen_h, PANEL_MIN_H, SCREEN_PAD_Y)

## 斜切把面板画出来的左右边推到布局盒外多少
static func skew_x(h: float) -> float:
	return ShopCardLayout.skew_x(PANEL_SKEW_RAD, h)

## 内容层单边占位 = Panel 内容边距 + MarginContainer 现调的那一份（取整，与节点逐单位一致）。
## 平行四边形让底边整体比顶边多挪一个 skew_x(h)：右下角那颗按钮离画出来的右边只剩「占位 - skew_x」
static func chrome_side(h: float) -> float:
	return PANEL_CONTENT_SIDE + ceilf(CHROME_INNER_SIDE + skew_x(h))

static func chrome_x(h: float) -> float:
	return chrome_side(h) * 2.0

## 滚动区左右要留的白（卡高不超过面板高，按面板高算最坏情况）
static func card_pad_x(h: float) -> float:
	return ShopCardLayout.card_pad_x(CARD_SKEW_RAD, h)

## 面板布局盒里的内容宽 = 屏幕宽 - 面板占位 - 面板两头画出来的斜切 - 两头呼吸量
static func panel_inner_w(screen: Vector2) -> float:
	var h := panel_h_for(screen.y)
	return maxf(0.0, screen.x - chrome_x(h) - (skew_x(h) + PANEL_AIR_X) * 2.0)

## 卡片行可用的宽 = 内容宽 - 滚动区两头给卡角留的白
static func avail_w(screen: Vector2) -> float:
	return maxf(0.0, panel_inner_w(screen) - card_pad_x(panel_h_for(screen.y)) * 2.0)

## 卡间缝隙：宽屏上松一点，窄屏上不抢卡片的宽
static func gap_for(avail: float) -> float:
	return ShopCardLayout.gap_for(avail, 0.010, CARD_GAP_MIN, CARD_GAP_MAX)

## n 张卡均分可用宽，夹在 [MIN_CARD_W, CARD_W] 之间
static func card_w_for(screen: Vector2, n: int) -> float:
	if n <= 0:
		return CARD_W
	var avail := avail_w(screen)
	return clampf((avail - gap_for(avail) * float(n - 1)) / float(n), MIN_CARD_W, CARD_W)

static func card_inner_w(card_w: float) -> float:
	return ShopCardLayout.card_inner_w(card_w, CARD_PAD_X)

## 这一档屏宽下整块面板的布局盒该占的宽（画出来还要再加两头斜切，判据按它核对留白）
static func panel_w_for(screen: Vector2, n: int) -> float:
	var h := panel_h_for(screen.y)
	var avail := avail_w(screen)
	return card_w_for(screen, n) * float(n) + gap_for(avail) * float(maxi(n - 1, 0)) \
		+ card_pad_x(h) * 2.0 + chrome_x(h)

## 选中要放大 ⇒ 这一行上下各让出的余量
static func pop_gutter_y(screen_h: float) -> float:
	return ShopCardLayout.pop_gutter_y(panel_h_for(screen_h), SEL_SCALE)

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 卡体登记成「长按键」：面板不是按钮，摇杆认不出 ⇒ 点面板空白处不许在它底下长出摇杆
	panel.add_to_group(DawnJoystick.UI_PRESS_HOLD_GROUP)
	_setup_top_bar()
	GameStyle.label(title_label, 22, GameStyle.INK_TEXT, 0, GameStyle.INK, true)
	GameStyle.label(info_label, 13, GameStyle.PAPER_DIM)
	GameStyle.label(gate_label, 13, GameStyle.PAPER_DIM)
	GameStyle.button(reroll_btn, GameStyle.NAVY2, GameStyle.LINE, 14, GameStyle.PAPER)
	GameStyle.button(confirm_btn, GameStyle.JADE, GameStyle.JADE_EDGE, 16, GameStyle.INK_TEXT, 6.0)
	# 这一屏现在真的要靠手指划（卡高超出滚动区）⇒ 那根滚动条得看得见、像游戏里的东西：
	# 引擎默认那根浅灰在深蓝底上像系统控件，且 ScrollContainer 只吃 modulate（GameStyle 头注）
	GameStyle.scrollable(card_scroll)
	reroll_btn.pressed.connect(_on_reroll)
	confirm_btn.pressed.connect(_on_confirm_pick)
	GameManager.alloc_opened.connect(_on_alloc_opened)
	GameManager.alloc_finished.connect(_on_alloc_finished)

## 顶栏：左侧标题色块，右侧「属性」与「暂停」按钮（与金币阁同一布局口径）
func _setup_top_bar() -> void:
	var vbox: VBoxContainer = $CenterContainer/Panel/MarginContainer/VBox
	var title_band: PanelContainer = $CenterContainer/Panel/MarginContainer/VBox/TitleBand
	var top_bar := HBoxContainer.new()
	top_bar.name = "TopBar"
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_theme_constant_override("separation", 10)
	vbox.add_child(top_bar)
	vbox.move_child(top_bar, 0)

	vbox.remove_child(title_band)
	title_band.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	title_band.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_bar.add_child(title_band)

	# 2026-10-12 圆形待加点次数徽记：紧贴标题右侧，不挤占操作区与卡片空间，连升多级时直观告知剩余次数
	_points_badge = PanelContainer.new()
	_points_badge.name = "PointsBadge"
	_points_badge.custom_minimum_size = Vector2(28, 28)
	_points_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_points_badge.mouse_filter = Control.MOUSE_FILTER_STOP
	_points_badge.add_to_group(DawnJoystick.UI_PRESS_HOLD_GROUP)
	var badge_sb := StyleBoxFlat.new()
	badge_sb.bg_color = GameStyle.with_alpha(GameStyle.INK, 0.92)
	badge_sb.border_color = GameStyle.JADE
	badge_sb.border_width_left = 2
	badge_sb.border_width_top = 2
	badge_sb.border_width_right = 2
	badge_sb.border_width_bottom = 2
	var r := 14
	badge_sb.corner_radius_top_left = r
	badge_sb.corner_radius_top_right = r
	badge_sb.corner_radius_bottom_right = r
	badge_sb.corner_radius_bottom_left = r
	_points_badge.add_theme_stylebox_override("panel", badge_sb)

	_points_label = Label.new()
	_points_label.name = "PointsLabel"
	_points_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_points_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	GameStyle.label(_points_label, 14, GameStyle.JADE, 2, GameStyle.INK, true)
	_points_badge.add_child(_points_label)

	_points_badge.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
			_show_points_tip()
	)
	top_bar.add_child(_points_badge)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_child(spacer)

	var stats_btn := Button.new()
	stats_btn.name = "StatsButton"
	stats_btn.text = "属 性"
	stats_btn.custom_minimum_size = Vector2(72, 32)
	stats_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stats_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(stats_btn, GameStyle.NAVY2, GameStyle.JADE, 13, GameStyle.PAPER, 4.0, GameStyle.INK_TEXT)
	stats_btn.pressed.connect(func(): stats_requested.emit())
	top_bar.add_child(stats_btn)

	var pause_btn := Button.new()
	pause_btn.name = "PauseButton"
	pause_btn.text = "暂 停"
	pause_btn.custom_minimum_size = Vector2(72, 32)
	pause_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pause_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(pause_btn, GameStyle.NAVY2, GameStyle.GOLD, 13, GameStyle.PAPER, 4.0, GameStyle.INK_TEXT)
	pause_btn.pressed.connect(func(): pause_requested.emit())
	top_bar.add_child(pause_btn)

func _show_points_tip() -> void:
	if _points_badge == null:
		return
	var pending := GameManager.pending_upgrade_points
	var total := GameManager.alloc_points_total
	DetailTip.show_over(self, _points_badge, {
		"title": "悟道点数",
		"chip": "剩余 %d 次" % pending,
		"chip_color": GameStyle.JADE,
		"rows": [
			["本回合连升", "%d 级" % total, GameStyle.JADE],
			["剩余加点", "%d 次" % pending, GameStyle.PAPER],
			["每次消耗", "1 点", GameStyle.PAPER],
		],
		"body": "战斗中升级不打断节奏，升级点数暂存，回合结束后在此统一领悟加点。",
		"notes": [
			"每次确认选择一条属性消耗 1 点。",
			"本回合点数全部加完后即可前往商店。",
		],
		"foot": "可随时按右上角「属 性」查看当前完整属性与加点。",
	})

func _pulse_points_badge() -> void:
	if _points_badge == null or not is_inside_tree():
		return
	if _badge_tween != null and _badge_tween.is_valid():
		_badge_tween.kill()
	var p_sz := _points_badge.size if _points_badge.size.x > 0.0 else _points_badge.custom_minimum_size
	_points_badge.pivot_offset = p_sz * 0.5
	_points_badge.scale = Vector2(1.35, 1.35)
	_badge_tween = create_tween()
	_badge_tween.tween_property(_points_badge, "scale", Vector2.ONE, 0.22)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## 回合结束、有待加点：开面板并把这一屏的候选摆出来
func _on_alloc_opened() -> void:
	# 立即重置触屏摇杆状态，防止手指还压在摇杆上时误点卡片
	if GameManager.joystick != null and GameManager.joystick.has_method("_stop_joystick"):
		GameManager.joystick._stop_joystick()

	_last_pending = -1
	_can_interact = false
	_is_confirming = false
	_layout_for_viewport()
	_refresh()
	visible = true
	get_tree().paused = true
	# 只淡入内容层（卡片）：DimOverlay 压暗底随 visible 立即满不透明盖住战场，
	# 不再整根淡入 —— 否则入场缝隙里暗底是透明的，会闪出身后的战场与 HUD。
	# 根透明度复位是防御：万一有别处整根淡出过（如商店出战的旧路径），重开不能带着 0 的根。
	modulate.a = 1.0
	content.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(content, "modulate:a", 1.0, GameStyle.UI_FADE_IN)
	# 入场防误触保护窗口：动画播放完后才允许交互
	tw.tween_interval(0.14)
	tw.tween_callback(func(): _can_interact = true)

## 点数加完：收面板（商店由 WaveSpawner 接手，不在这里指挥流程）
func _on_alloc_finished() -> void:
	if not visible:
		return
	_can_interact = false
	# 详情卡是本面板的子节点：不收干净就是「隐藏后复活」——下次开面板它会带着上一局的旧读数亮出来
	DetailTip.close_all(self)
	# 只淡内容层：同一帧金币阁已带着自己满不透明的 DimOverlay 亮起来，这里暗底若跟着淡出，
	# 两层半透明暗底叠加会露出战场（2026-10-16 用户反馈「确认加点后闪一下别的画面」）。
	var tw := create_tween()
	tw.tween_property(content, "modulate:a", 0.0, GameStyle.UI_FADE_OUT)
	tw.tween_callback(func(): visible = false)

func _layout_for_viewport() -> void:
	var screen: Vector2 = get_viewport().get_visible_rect().size
	var n: int = GameManager.UPGRADE_OFFER_COUNT
	var h: float = panel_h_for(screen.y)
	_card_w = card_w_for(screen, n)
	panel.custom_minimum_size = Vector2(panel_w_for(screen, n), h)
	cards_container.add_theme_constant_override("separation", int(gap_for(avail_w(screen))))
	# 上下各让出放大余量：选中卡放大后仍在这行之内（判据 LayoutCheck 量这一点）
	# 左右各让出卡角斜切量：不然滚动区把最外侧两张卡的角削平
	var gutter := int(pop_gutter_y(screen.y))
	var pad_x := int(card_pad_x(h))
	cards_pad.add_theme_constant_override("margin_top", gutter)
	cards_pad.add_theme_constant_override("margin_bottom", gutter)
	cards_pad.add_theme_constant_override("margin_left", pad_x)
	cards_pad.add_theme_constant_override("margin_right", pad_x)
	# 内容层左右各再让 lean：面板是平行四边形，底边整体比顶边挪走 skew_x，
	# 不补的话底栏那颗「确认领悟」离**画出来的**右边只剩 20 - lean ≈ 7 单位（顶栏反过来）。
	var side := int(chrome_side(h) - PANEL_CONTENT_SIDE)
	content_margin.add_theme_constant_override("margin_left", side)
	content_margin.add_theme_constant_override("margin_right", side)

# ---------------- 一屏候选 ----------------

func _refresh() -> void:
	selected_index = -1
	_populate_cards()
	_refresh_bars()

func _refresh_bars() -> void:
	var pending: int = GameManager.pending_upgrade_points
	var total: int = GameManager.alloc_points_total
	if _points_label != null:
		_points_label.text = str(maxi(pending, 0))
		if _last_pending >= 0 and pending < _last_pending and pending > 0:
			_pulse_points_badge()
	_last_pending = pending

	var head: String = "第 %d 回合结束" % maxi(GameManager.wave_number, 1)
	if total > 1:
		head += " · 本回合连升 %d 级 · 剩余加点 %d 次" % [total, pending]
	elif total == 1:
		head += " · 待加点 1 次"
	else:
		head += " · 升级已完成"
	title_label.text = "升 级 加 点"
	info_label.text = GameStyle.wrap_cjk(head, GameStyle.body_font(), 13,
		maxf(120.0, get_viewport().get_visible_rect().size.x - 120.0))
	reroll_btn.text = GameManager.alloc_reroll_label()
	reroll_btn.disabled = not GameManager.can_reroll_alloc() or pending <= 0
	_update_confirm_btn()
	_update_gate_label()

func _update_confirm_btn() -> void:
	confirm_btn.text = "确认选择 ✦"
	confirm_btn.disabled = selected_index < 0 or not _can_interact or _is_confirming
	confirm_btn.custom_minimum_size = Vector2(148, 44)

## 底部这条读数把「选了哪一条」与「还剩几点」都摆在明面上（触屏无 hover，点了就得看得见）
func _update_gate_label() -> void:
	var pending: int = GameManager.pending_upgrade_points
	var rest := "还剩 %d 点未加" % pending if pending > 0 else "点已加完 · 稍候进商店"
	if selected_index < 0 or selected_index >= GameManager.alloc_offers.size():
		gate_label.text = "点中一张卡，再按右侧「确认选择」 · %s" % rest
		GameStyle.label(gate_label, 13, GameStyle.PAPER_DIM)
	else:
		gate_label.text = "已选【%s】 · %s" % [
			GameManager.alloc_offers[selected_index].get("title", "?"), rest]
		GameStyle.label(gate_label, 13, GameStyle.JADE)

func _populate_cards() -> void:
	# 整批重建前先收掉摊在暗底下的旧详情卡：它还挂在 self 上，不收就会停在新那一屏后面
	# 报旧装备的数（与 GameHUD._on_weapons_updated 同一口径）
	DetailTip.close_all(self)
	for child in cards_container.get_children():
		child.queue_free()
	_card_entries.clear()

	# 一屏候选只抄一份「加之前」的属性影子：五张卡的预读都跟这一份对表，屏内不会自相矛盾
	var forecast := StatForecast.open()
	for i in range(GameManager.alloc_offers.size()):
		var data: Dictionary = GameManager.alloc_offers[i]
		var entry := _create_card_entry(data, i, forecast)
		_card_entries.append(entry)
		var card_col: Control = entry["root"]
		cards_container.add_child(card_col)
		# 统一卡片入场配方（支点随布局自动归中，见 GameStyle.pop_in 头注）
		GameStyle.pop_in(card_col, float(i) * 0.05, 0.8)
	# 整行建完再放开「按下」冒泡（必须在子树建完之后，见 GameStyle.swipeable 头注）：
	# 卡体是 PanelContainer（mouse_filter 默认 STOP），会把 CardScroll 起手锁定手指拖动要的
	# 那一拍就地吃掉、不再向上冒泡 ⇒ 卡盖住多大面积就滑不动多大面积。
	# 用户 2026-10-12 真机：「手在卡片上面去滑动是滑不动的，要挪到侧面没有卡片遮挡的地方才能滑」。
	# 卡里那排受益装备图标与「荐」签也一起降成 PASS（否则它们各自是一小块划不动的死区）：
	# 点它们仍只弹详解、不选卡，靠的是 GameStyle.tap 的「只兑现最里一层」认领，见那里。
	GameStyle.swipeable(cards_container)

## 支点 = 这一格自己的中心。不居中则放大时上下不对称（选中卡会往一边多顶出一截）。
static func _center_pivot(c: Control) -> void:
	if c.size.y > 0.0:
		c.pivot_offset = c.size * 0.5

## 卡片装配整体在 ui/levelup/LevelUpCardFactory（与商店 ShopOfferCardFactory 同构）：
## 本文件只留面板流程（摆位/选中/刷新/确认），卡内交互经下面三个入口调回。
func _create_card_entry(data: Dictionary, index: int, forecast: StatForecast) -> Dictionary:
	return LevelUpCardFactory.create_card(self, data, index, _card_w, forecast)

## 工厂回调：点卡片本体 = 只选中，不直接加点（防误触）；正式生效要走底部「确认选择」。
func on_card_tapped(index: int) -> void:
	if _can_interact and not _is_confirming:
		_select_card(index)

## 工厂回调：点「荐」签 = 看推荐理由（统一走 RecommendTip，与商店货架卡同一张卡）。
## 理由是打分那一刻生成的只读快照（offer.recommend_reasons），不在 UI 里二次推算。
func open_recommend_tip(anchor: Control, data: Dictionary) -> void:
	if not _can_interact or _is_confirming:
		return
	RecommendTip.open(self, anchor, data.get("recommend_reasons", []), float(data.get("recommend_score", 0.0)))

## 点「受益装备」那一排的图标 = 看这件装备的详解，纯只读：不许顺手把这张卡选中
## （看东西这个动作不改写状态；选中仍要走卡体那一下 + 底部「确认选择」）。
## 卡片与 HUD 武器栏 / 属性面板 / 商店同一工厂出，这里只多带一句「这条悟道算到它头上走的是
## 哪条链路」，链路名取自 GameBalance.upgrade_benefit_reasons —— 与「该不该挂这颗图标」同源。
func open_benefit_tip(anchor: Control, w: Dictionary, up: Dictionary) -> void:
	if not _can_interact or _is_confirming:
		return
	var reasons: Array[String] = GameBalance.upgrade_benefit_reasons(
		up.get("apply", {}), String(w.get("id", "")))
	var note := ""
	if not reasons.is_empty():
		var names: Array[String] = []
		for k in reasons:
			names.append(StatInfoData.field_name(String(k)))
		note = "这条悟道【%s】走的正是「%s」这条链路，所以这件装备会跟着变强。" % [
			String(up.get("title", "")), "、".join(names)]
	StatsTipFactory.open_weapon_tip(self, anchor, w, false, note)

## 选中态：鎏金框 + 标题转金 + 徽记换成「已选 ✦」，未选中的退回「×层数」。
## 底部 gate_label 同时把「已选【名字】+ 还剩几点」写在明面上。
func _select_card(index: int) -> void:
	if index < 0 or index >= GameManager.alloc_offers.size():
		return
	if selected_index == index:
		return
	selected_index = index
	AudioManager.play_sfx("gem_pickup", 0.95)
	for i in range(_card_entries.size()):
		var entry: Dictionary = _card_entries[i]
		var card: PanelContainer = entry["root"]
		var style: StyleBoxFlat = entry["style"]
		var icon_st: StyleBoxFlat = entry["icon_panel_style"]
		var rarity_col: Color = entry["rarity_col"]
		var badge: Label = entry["state_badge"]
		var title_lbl: Label = entry["title_lbl"]
		var is_sel: bool = (i == selected_index)
		var owned := int(GameManager.upgrade_counts.get(GameManager.alloc_offers[i].get("id", ""), 0))

		_center_pivot(card)
		var tw := card.create_tween()
		tw.set_parallel(true)
		if is_sel:
			tw.tween_property(card, "scale", Vector2(SEL_SCALE, SEL_SCALE), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(card, "modulate", Color.WHITE, 0.12)
			style.bg_color = GameStyle.NAVY2.lightened(0.10)
			icon_st.border_color = GameStyle.GOLD
			title_lbl.add_theme_color_override("font_color", GameStyle.GOLD)
			badge.text = "已选 ✦"
			badge.add_theme_color_override("font_color", GameStyle.GOLD)
			# T-5.1 选中高光：按稀有度起辉（普通微白高光，金色档 HDR 强起辉）
			var r_key: String = String(entry.get("rarity", "common"))
			var sel_glow := GameStyle.rarity_select_glow(r_key)
			var sel_edge := GameStyle.rarity_edge_color(r_key)
			style.border_color = sel_glow
			tw.chain().tween_property(style, "border_color", sel_edge, 0.22)
		else:
			tw.tween_property(card, "scale", Vector2(DIM_SCALE, DIM_SCALE), 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(card, "modulate", GameStyle.with_alpha(Color(0.78, 0.80, 0.86), 0.78), 0.12)
			style.bg_color = GameStyle.with_alpha(GameStyle.NAVY, 0.96)
			style.border_color = rarity_col
			icon_st.border_color = GameStyle.LINE
			title_lbl.add_theme_color_override("font_color", GameStyle.PAPER)
			badge.text = "×%d" % owned if owned > 0 else ""
			badge.add_theme_color_override("font_color", GameStyle.GREY)
	_update_confirm_btn()
	_update_gate_label()

## 刷新这一屏候选：第一次吃本回合免费额度，之后按货架重掷同一条价格线扣金币。
## 刷新只换候选、不动点数，所以刷新完要把选中态清掉（刚选的那张卡已经不在这屏了）。
func _on_reroll() -> void:
	if not _can_interact or _is_confirming:
		return
	if not GameManager.reroll_alloc():
		return
	selected_index = -1
	_populate_cards()
	_refresh_bars()

## 底部「确认领悟」：正式落地这一条悟道
func _on_confirm_pick() -> void:
	if not _can_interact or _is_confirming or selected_index < 0:
		return
	if GameManager.pending_upgrade_points <= 0:
		return
	_is_confirming = true
	_can_interact = false
	# take_alloc_upgrade 内部发属性、扣点数；点数清零时同步发 alloc_finished（金币阁由回合状态机接手）
	var ok := GameManager.take_alloc_upgrade(selected_index)
	_is_confirming = false
	if not ok:
		AudioManager.play_sfx("ui_error", 0.9)
		_can_interact = true
		return
	if GameManager.pending_upgrade_points <= 0:
		return
	_layout_for_viewport()
	_refresh()
	# 连点保护：新一屏候选先淡入（同样只淡内容层，暗底不动），动画放完才放行手指
	content.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(content, "modulate:a", 1.0, 0.12)
	tw.tween_interval(0.1)
	tw.tween_callback(func(): _can_interact = true)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		# 详解卡开着 → 返回键先收卡；无详解卡则唤出暂停菜单（面板本身不直接关，点数没加完不许走）
		if DetailTip.close_all(self):
			get_viewport().set_input_as_handled()
			return
		pause_requested.emit()
		get_viewport().set_input_as_handled()
