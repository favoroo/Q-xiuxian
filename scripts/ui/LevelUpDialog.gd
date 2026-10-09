class_name LevelUpDialog
extends Control

## 波后悟道结算面板：战斗中升级只攒点数（GameManager.pending_upgrade_points），
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
## 现在按灵石阁那把尺子收口（与 WaveShop 同一口径）：`chrome_x()` 把 lean 算进占位、
## `card_pad_x()` 给滚动区里的卡角留白、卡间缝与卡内边距按用户口径收窄，省下的宽换成 ① 的呼吸量。
## 判据补两条尺：卡角不许被滚动区横向切掉、控件画出来那一圈离所属面板的画出来的边要留白。

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

@onready var panel: PanelContainer = $CenterContainer/Panel
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

## 保存每张卡片的组件引用以便切换选中/未选中视觉状态
var _card_entries: Array[Dictionary] = []

# ---------------- 摆位算术（纯函数，判据共用同一份） ----------------

## 这一档屏高下面板该占的高
static func panel_h_for(screen_h: float) -> float:
	return maxf(PANEL_MIN_H, screen_h - SCREEN_PAD_Y)

## 斜切把面板画出来的左右边推到布局盒外多少：引擎按布局盒竖直中线居中斜切
## （style_box_flat.cpp: x_skew = -skew.x * (y - center.y)）⇒ 上下各伸出半个斜切量。
## 投影不算：shadow_size = 0 时引擎根本不画投影。
static func skew_x(h: float) -> float:
	return absf(PANEL_SKEW_RAD) * h * 0.5

## 内容层单边占位 = Panel 内容边距 + MarginContainer 现调的那一份（取整，与节点逐单位一致）。
## 平行四边形让底边整体比顶边多挪一个 skew_x(h)：右下角那颗按钮离**画出来的**右边
## 只剩「占位 - skew_x」，所以这里按 lean 补一次（灵石阁 WaveShop.card_pad_x 同一口径）。
static func chrome_side(h: float) -> float:
	return PANEL_CONTENT_SIDE + ceilf(CHROME_INNER_SIDE + skew_x(h))

static func chrome_x(h: float) -> float:
	return chrome_side(h) * 2.0

## 滚动区左右要留的白：卡片自己也是斜切的，画出来的两个角比布局盒左右各宽 |skew|·h/2，
## 而 ScrollContainer 会 clip ⇒ 不留白最外侧两张卡的角被削平（用户看到的「卡边没了」）。
## 卡高不超过滚动区高、滚动区高不超过面板高 ⇒ 按面板高算就是最坏情况。
static func card_pad_x(h: float) -> float:
	return ceilf(absf(CARD_SKEW_RAD) * h * 0.5) + 2.0

## 面板布局盒里的内容宽 = 屏幕宽 - 面板占位 - 面板两头画出来的斜切 - 两头呼吸量
static func panel_inner_w(screen: Vector2) -> float:
	var h := panel_h_for(screen.y)
	return maxf(0.0, screen.x - chrome_x(h) - (skew_x(h) + PANEL_AIR_X) * 2.0)

## 卡片行可用的宽 = 内容宽 - 滚动区两头给卡角留的白
static func avail_w(screen: Vector2) -> float:
	return maxf(0.0, panel_inner_w(screen) - card_pad_x(panel_h_for(screen.y)) * 2.0)

## 卡间缝隙：宽屏上松一点，窄屏上不抢卡片的宽
static func gap_for(avail: float) -> float:
	return clampf(avail * 0.010, CARD_GAP_MIN, CARD_GAP_MAX)

## n 张卡均分可用宽，夹在 [MIN_CARD_W, CARD_W] 之间
static func card_w_for(screen: Vector2, n: int) -> float:
	if n <= 0:
		return CARD_W
	var avail := avail_w(screen)
	return clampf((avail - gap_for(avail) * float(n - 1)) / float(n), MIN_CARD_W, CARD_W)

static func card_inner_w(card_w: float) -> float:
	return card_w - CARD_PAD_X * 2.0

## 这一档屏宽下整块面板的布局盒该占的宽（画出来还要再加两头斜切，判据按它核对留白）
static func panel_w_for(screen: Vector2, n: int) -> float:
	var h := panel_h_for(screen.y)
	var avail := avail_w(screen)
	return card_w_for(screen, n) * float(n) + gap_for(avail) * float(maxi(n - 1, 0)) \
		+ card_pad_x(h) * 2.0 + chrome_x(h)

## 选中要放大 ⇒ 这一行上下各让出的余量。卡片最高不超过滚动区高，而滚动区高不超过面板高，
## 按 panel_h 上限算就是最坏情况：放大后画出来的高度正好落回滚动区内。
## 再补 2 单位给入场/选中动画的 TRANS_BACK 过冲。
static func pop_gutter_y(screen_h: float) -> float:
	var h := panel_h_for(screen_h)
	return ceilf(h * (SEL_SCALE - 1.0) / (2.0 * SEL_SCALE)) + 2.0

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 卡体登记成「长按键」：面板不是按钮，摇杆认不出 ⇒ 点面板空白处不许在它底下长出摇杆
	panel.add_to_group(DawnJoystick.UI_PRESS_HOLD_GROUP)
	GameStyle.label(title_label, 22, GameStyle.PAPER, 0, GameStyle.INK, true)
	GameStyle.label(info_label, 13, GameStyle.PAPER_DIM)
	GameStyle.label(gate_label, 13, GameStyle.PAPER_DIM)
	GameStyle.button(reroll_btn, GameStyle.NAVY2, GameStyle.LINE, 14, GameStyle.PAPER)
	GameStyle.button(confirm_btn, GameStyle.YELLOW, GameStyle.YELLOW_EDGE, 16, GameStyle.INK_TEXT, 6.0)
	reroll_btn.pressed.connect(_on_reroll)
	confirm_btn.pressed.connect(_on_confirm_pick)
	GameManager.alloc_opened.connect(_on_alloc_opened)
	GameManager.alloc_finished.connect(_on_alloc_finished)

## 回合结束、有待加点：开面板并把这一屏的候选摆出来
func _on_alloc_opened() -> void:
	# 立即重置触屏摇杆状态，防止手指还压在摇杆上时误点卡片
	if GameManager.joystick != null and GameManager.joystick.has_method("_stop_joystick"):
		GameManager.joystick._stop_joystick()

	_can_interact = false
	_is_confirming = false
	_layout_for_viewport()
	_refresh()
	visible = true
	get_tree().paused = true
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.16)
	# 入场防误触保护窗口：动画播放完后才允许交互
	tw.tween_interval(0.14)
	tw.tween_callback(func(): _can_interact = true)

## 点数加完：收面板（灵石阁由 WaveSpawner 接手，不在这里指挥流程）
func _on_alloc_finished() -> void:
	if not visible:
		return
	_can_interact = false
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.14)
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
	var head: String = "第 %d 波已平" % maxi(GameManager.wave_number, 1)
	if pending > 1:
		head += " · 待加点 %d/%d" % [pending, GameManager.alloc_points_total]
	elif pending == 1:
		head += " · 待加点 1"
	else:
		head += " · 悟道已圆满"
	title_label.text = "悟 道 加 点"
	info_label.text = GameStyle.wrap_cjk(head, GameStyle.body_font(), 13,
		maxf(120.0, get_viewport().get_visible_rect().size.x - 120.0))
	reroll_btn.text = GameManager.alloc_reroll_label()
	reroll_btn.disabled = not GameManager.can_reroll_alloc() or pending <= 0
	_update_confirm_btn()
	_update_gate_label()

func _update_confirm_btn() -> void:
	confirm_btn.text = "确认领悟 ✦"
	confirm_btn.disabled = selected_index < 0 or not _can_interact or _is_confirming
	confirm_btn.custom_minimum_size = Vector2(148, 44)

## 底部这条读数把「选了哪一条」与「还剩几点」都摆在明面上（触屏无 hover，点了就得看得见）
func _update_gate_label() -> void:
	var pending: int = GameManager.pending_upgrade_points
	var rest := "还剩 %d 点未加" % pending if pending > 0 else "点已加完 · 稍候进灵石阁"
	if selected_index < 0 or selected_index >= GameManager.alloc_offers.size():
		gate_label.text = "点中一张卡，再按右侧「确认领悟」 · %s" % rest
		GameStyle.label(gate_label, 13, GameStyle.PAPER_DIM)
	else:
		gate_label.text = "已选【%s】 · %s" % [
			GameManager.alloc_offers[selected_index].get("title", "?"), rest]
		GameStyle.label(gate_label, 13, GameStyle.YELLOW)

func _populate_cards() -> void:
	for child in cards_container.get_children():
		child.queue_free()
	_card_entries.clear()

	for i in range(GameManager.alloc_offers.size()):
		var data: Dictionary = GameManager.alloc_offers[i]
		var entry := _create_card_entry(data, i)
		_card_entries.append(entry)
		var card_col: Control = entry["root"]
		cards_container.add_child(card_col)
		card_col.pivot_offset = Vector2(_card_w * 0.5, CARD_MIN_H * 0.5)
		card_col.scale = Vector2(0.8, 0.8)
		card_col.modulate.a = 0.0
		var ctw := card_col.create_tween()
		# 缩放的支点要绕卡片自己的中心：布局出尺寸之前无从得知，动画第一帧（还是全透明）补上
		ctw.tween_callback(_center_pivot.bind(card_col))
		ctw.tween_interval(float(i) * 0.05)
		ctw.set_parallel(true)
		ctw.tween_property(card_col, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		ctw.tween_property(card_col, "modulate:a", 1.0, 0.16)

## 支点 = 这一格自己的中心。不居中则放大时上下不对称（选中卡会往一边多顶出一截）。
static func _center_pivot(c: Control) -> void:
	if c.size.y > 0.0:
		c.pivot_offset = c.size * 0.5

func _create_card_entry(data: Dictionary, index: int) -> Dictionary:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(_card_w, CARD_MIN_H)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.pivot_offset = Vector2(_card_w * 0.5, CARD_MIN_H * 0.5)

	var rarity_col: Color = data.get("border_color", GameStyle.PAPER)
	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = Color(GameStyle.NAVY.r, GameStyle.NAVY.g, GameStyle.NAVY.b, 0.985)
	style_normal.skew = Vector2(deg_to_rad(3.0), 0.0)
	style_normal.border_width_left = 2
	style_normal.border_width_top = 2
	style_normal.border_width_right = 2
	style_normal.border_width_bottom = 5
	style_normal.border_color = rarity_col
	style_normal.shadow_color = Color(0, 0, 0, 0.6)
	style_normal.shadow_size = 0
	style_normal.shadow_offset = Vector2(6, 6)
	style_normal.content_margin_left = CARD_PAD_X
	style_normal.content_margin_top = 12.0
	style_normal.content_margin_right = CARD_PAD_X
	style_normal.content_margin_bottom = 12.0
	card.add_theme_stylebox_override("panel", style_normal)

	var inner_w: float = card_inner_w(_card_w)
	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 8)

	# 1. 顶部稀有度色签 + 已修层数
	var hbox_top := HBoxContainer.new()
	hbox_top.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var rarity_lbl := Label.new()
	rarity_lbl.text = " " + data.get("rarity_label", "凡品") + " "
	GameStyle.label(rarity_lbl, 11, GameStyle.PAPER)
	var band_text_col: Color = GameStyle.INK_TEXT if rarity_col.get_luminance() > 0.5 else GameStyle.PAPER
	rarity_lbl.add_theme_color_override("font_color", band_text_col)
	var pill_style := GameStyle.block(rarity_col, GameStyle.SLANT_BAND, Vector2(2, 2))
	pill_style.content_margin_top = 2.0
	pill_style.content_margin_bottom = 2.0
	rarity_lbl.add_theme_stylebox_override("normal", pill_style)
	hbox_top.add_child(rarity_lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox_top.add_child(spacer)

	var state_badge := Label.new()
	var count_already: int = int(GameManager.upgrade_counts.get(data.get("id", ""), 0))
	state_badge.text = "×%d" % count_already if count_already > 0 else ""
	GameStyle.label(state_badge, 11, GameStyle.GREY)
	hbox_top.add_child(state_badge)
	vbox.add_child(hbox_top)

	# 2. 中央图标（墨底白框）
	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(56, 56)
	icon_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_panel_style := GameStyle.outlined_panel(GameStyle.INK, GameStyle.PAPER_DIM, 2, 0.0)
	icon_box.add_theme_stylebox_override("panel", icon_panel_style)

	var icon_tex := TextureRect.new()
	if data.has("icon") and ResourceLoader.exists(data["icon"]):
		icon_tex.texture = load(data["icon"])
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.custom_minimum_size = Vector2(42, 42)
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_child(icon_tex)
	vbox.add_child(icon_box)

	# 3. 名称（纸白大字，窄卡上自己切硬换行）
	var title_lbl := Label.new()
	title_lbl.text = GameStyle.wrap_cjk(String(data["title"]), GameStyle.display_font(), 17, inner_w)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.custom_minimum_size = Vector2(inner_w, 0)
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title_lbl)
	GameStyle.label(title_lbl, 17, GameStyle.PAPER, 0, GameStyle.INK, true)

	# 4. 分隔线（稀有度色）
	var sep := HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sep_style := StyleBoxLine.new()
	sep_style.color = Color(rarity_col.r, rarity_col.g, rarity_col.b, 0.45)
	sep_style.thickness = 2
	sep.add_theme_stylebox_override("separator", sep_style)
	vbox.add_child(sep)

	# 5. 描述富文本（表里按语义写了 \n，这里再把「一行放不下的那一句」切成硬换行）
	#   为什么自己切：AUTOWRAP_WORD 只认词间断点，一句不带空格的中文在它眼里是一个词 ——
	#   真机上整行不折、压到邻卡上（见 GameStyle.wrap_cjk 头注）。BBCode 的状态跨行延续，
	#   所以 wrap_bbcode 可以从中间下刀而不破坏 [color]/[b] 配对。
	var r_desc := RichTextLabel.new()
	r_desc.bbcode_enabled = true
	r_desc.text = GameStyle.wrap_bbcode(String(data["desc"]), GameStyle.body_font(), 13, inner_w)
	r_desc.fit_content = true
	r_desc.scroll_active = false
	r_desc.custom_minimum_size = Vector2(inner_w, 0)
	r_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r_desc.add_theme_font_override("normal_font", GameStyle.body_font())
	r_desc.add_theme_font_override("bold_font", GameStyle.body_font())
	r_desc.add_theme_font_size_override("normal_font_size", 13)
	r_desc.add_theme_font_size_override("bold_font_size", 13)
	r_desc.add_theme_color_override("default_color", Color(0.85, 0.87, 0.94))
	vbox.add_child(r_desc)

	card.add_child(vbox)

	# 点卡片本体 = 只选中，不直接加点（防误触）；正式生效要走底部「确认领悟」
	card.gui_input.connect(func(event: InputEvent):
		if not _can_interact or _is_confirming:
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_select_card(index)
	)

	return {
		"root": card,
		"style": style_normal,
		"icon_panel_style": icon_panel_style,
		"rarity_col": rarity_col,
		"state_badge": state_badge,
		"title_lbl": title_lbl,
	}

## 选中态：金框 + 标题转黄 + 徽记换成「已选 ✦」，未选中的退回「×层数」。
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
			tw.tween_property(card, "modulate", Color(1, 1, 1, 1), 0.12)
			style.bg_color = Color(0.10, 0.15, 0.28, 0.99)
			style.border_color = GameStyle.YELLOW
			icon_st.border_color = GameStyle.YELLOW
			title_lbl.add_theme_color_override("font_color", GameStyle.YELLOW)
			badge.text = "已选 ✦"
			badge.add_theme_color_override("font_color", GameStyle.YELLOW)
		else:
			tw.tween_property(card, "scale", Vector2(DIM_SCALE, DIM_SCALE), 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(card, "modulate", Color(0.78, 0.80, 0.86, 0.78), 0.12)
			style.bg_color = Color(GameStyle.NAVY.r, GameStyle.NAVY.g, GameStyle.NAVY.b, 0.96)
			style.border_color = rarity_col
			icon_st.border_color = GameStyle.PAPER_DIM
			title_lbl.add_theme_color_override("font_color", GameStyle.PAPER)
			badge.text = "×%d" % owned if owned > 0 else ""
			badge.add_theme_color_override("font_color", GameStyle.GREY)
	_update_confirm_btn()
	_update_gate_label()

## 刷新这一屏候选：第一次吃本回合免费额度，之后按货架重掷同一条价格线扣灵石。
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
	# take_alloc_upgrade 内部发属性、扣点数；点数清零时同步发 alloc_finished（灵石阁由波次状态机接手）
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
	# 连点保护：新一屏候选先淡入，动画放完才放行手指
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.12)
	tw.tween_interval(0.1)
	tw.tween_callback(func(): _can_interact = true)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		# 这一屏没有可退的浮层：点数没加完不许走（用户指令「必须加完才能出战」）
		get_viewport().set_input_as_handled()
