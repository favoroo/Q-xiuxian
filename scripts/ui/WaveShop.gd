class_name WaveShop
extends Control

## 波间灵石阁：购买法器/回气丹、重掷货架；
## 上阵 + 背包统一点选后操作：三合一合成 / 上阵卸下 / 出售换灵石

signal stats_requested

@onready var panel: PanelContainer = $CenterContainer/Panel
@onready var stones_label: Label = $CenterContainer/Panel/MarginContainer/VBox/TopBar/StonesChip/StonesLabel
@onready var wave_label: Label = $CenterContainer/Panel/MarginContainer/VBox/TopBar/WaveLabel
@onready var offers_scroll: ScrollContainer = $CenterContainer/Panel/MarginContainer/VBox/OffersScroll
@onready var offers_pad: MarginContainer = $CenterContainer/Panel/MarginContainer/VBox/OffersScroll/OffersPad
@onready var offers_container: HBoxContainer = $CenterContainer/Panel/MarginContainer/VBox/OffersScroll/OffersPad/OffersContainer
## 陈列行（上阵 + 背包 + 法宝）整排在 OwnedScroll 里：满仓 6 上阵 + 9 背包 + 15 法宝
## 一共 30 格，任何一档屏都摆不平 ⇒ 槽位先按件数压到 INV_SLOT_MIN，还摆不下就横着滑。
## 竖向禁用滚动：这一行只有一格高，上下滑没有意义，且会把货架的竖向预算再吃掉一条滑条。
@onready var owned_scroll: ScrollContainer = $CenterContainer/Panel/MarginContainer/VBox/OwnedScroll
@onready var owned_container: HBoxContainer = $CenterContainer/Panel/MarginContainer/VBox/OwnedScroll/OwnedContainer
@onready var action_bar: HBoxContainer = $CenterContainer/Panel/MarginContainer/VBox/ActionBar
@onready var reroll_btn: Button = $CenterContainer/Panel/MarginContainer/VBox/BottomBar/RerollButton
@onready var confirm_btn: Button = $CenterContainer/Panel/MarginContainer/VBox/BottomBar/ConfirmButton

## 摆位口径与波后悟道面板同一把尺子（LevelUpDialog 里同名同形的 *_for()）：
## 面板高按 viewport 钉死、卡宽按可用宽均分、两头给斜切画出来的角留出呼吸量。
##
## 2026-10-09 用户真机：「这个界面优化一下，尽量在一个界面下显示，不要去上下滑动，
## 上下滑动体验太差了这里」—— 上一版把货架塞进 ScrollContainer 只是让「出战」不再被顶出屏，
## 代价是五张卡要竖着滑才看得完，而货架一共就 5~6 格：滑一次才能比一次价，比不了。
## 现在的口径改成「一屏放得下」：
## ① 卡内摆位压紧（图标与名号同行、色签与锁定同行），高由内容决定，不再钉 268 死高；
## ② 面板的固定行瘦身（羁绊行并入说明行、提示改点按可得、上下留白与行距收紧、
##    陈列槽与底栏按钮降高），把省下来的每一单位都给货架；
## ③ 判据 LayoutCheck 点名量「最坏样本下货架内容高 ≤ 滚动区高」——
##    量的是 6 格货架 + 羁绊行 + 点选后操作条 + 满背包那一屏，不是空载货架。
## ScrollContainer 仍留纵向 AUTO 作兜底：万一某档屏真放不下，宁可滑也不许切文案
## （不砍文案不压字号是硬口径），但三档测试屏上它必须用不上。
##
## 「货架不许竖滑」不等于「这一屏哪儿都不许滑」：底下那排陈列（上阵 + 背包 + 法宝）满仓是
## 6 + 9 + 15 = 30 格，槽位压到 36 见方也要 1400 宽，任何一档屏都摆不平 ⇒ 整排横滑
## （OwnedScroll，竖向禁用）。2026-10-09 用户真机：「装备太多了，可以左右滑动啊，
## 不然很多装备都操作不了了」。两处口径不同的道理在代价上：货架滑一次才能比一次价，比不了；
## 陈列行划一下就把最右那件点到手里，不挡任何决策。
const OFFER_PAD_X := 12.0
## 面板左右固定占位：Panel 内容边距 28×2 + MarginContainer 12×2（与 .tscn 同源）
const CHROME_X := 80.0
## 面板与屏幕之间的呼吸量：上下合计 24（各 12），左右各 20（斜切画出来的角之外再留）
const SCREEN_PAD_Y := 24.0
const PANEL_AIR_X := 20.0
const PANEL_MIN_H := 420.0
## 面板 stylebox 的斜切（弧度），与 WaveShop.tscn 的 StyleBoxFlat_panel.skew 同源
## （改 .tscn 里的 skew 必须同步这里，判据会核对两头留白）
const PANEL_SKEW_RAD := 0.035
const CARD_W_MIN := 148.0
const CARD_W_MAX := 220.0
const CARD_GAP_MIN := 10.0
const CARD_GAP_MAX := 16.0
## 卡内摆位：内容边距 6、行距 3、图标 44、价格键 32、锁定角键 40×24。
## 这一组数一起决定「最坏文案下这张卡多高」，判据按现量的数说话（见头注 ③）。
## 左右边距不许再压：卡片是 3° 斜切的平行四边形，260 高时上下各挪出 6.8 单位，
## 边距压到 8 以下文字就贴上画出来的边框线（判据 LayoutCheck 的「离面板画出来的边」那把尺）。
const CARD_PAD_Y := 6.0
const CARD_SEP := 3.0
const CARD_ICON := 44.0
const CARD_PRICE_H := 32.0
const CARD_LOCK_W := 40.0
const CARD_LOCK_H := 24.0
## 入场动画的支点参考高，同时是「卡高的设计上限」：卡高由内容决定，判据量出来最坏 256
## （6 格货架 + 最长那句说明）。滚动区两头的留白按这个上限算，超过它卡角就会被削。
const CARD_H_REF := 280.0
## 陈列槽（上阵/背包/法宝）边长的上下限：按件数现算夹在 [36, 44]，压到 36 还摆不下就横滑
const INV_SLOT := 44.0
const INV_SLOT_MIN := 36.0
## 一枚色签（「背包 n/9」「法宝 n」）占的宽：最长读数 + 描边与内容边距
const INV_CHIP_W := 96.0
## 陈列行里控件之间的缝隙（与 .tscn 的 OwnedContainer separation 同源）
const INV_GAP := 10.0
## 卡宽下限的来由：货架 6 格（多宝道人 +1）时若把卡压到 132，最长那句说明要折成 7 行，
## 卡高就追不上这一屏给得起的高 ⇒ 宁可让货架横向滑一格（顶栏/陈列行/出战永远在屏内），
## 也不砍文案、不压字号。真机 20:9（设计可视 1202 宽）上 5~6 格都摆得下，压根不用滑。

## 这一档屏高下面板该占的高
static func panel_h_for(screen_h: float) -> float:
	return maxf(PANEL_MIN_H, screen_h - SCREEN_PAD_Y)

## 斜切把面板画出来的左右边推到布局盒外多少：引擎按布局盒竖直中线居中斜切
## （style_box_flat.cpp: x_skew = -skew.x * (y - center.y)）⇒ 上下各伸出半个斜切量。
static func skew_x(h: float) -> float:
	return absf(PANEL_SKEW_RAD) * h * 0.5

## 货架卡自己的斜切（弧度），与 _create_offer_card 里 style.skew = deg_to_rad(3.0) 同源
const CARD_SKEW_RAD := 0.052

## 滚动区左右要留的白：卡片是斜切的平行四边形，画出来的两个角比布局盒左右各宽 |skew|·h/2。
## 不留就会被滚动区自己的边界切掉角（判据 LayoutCheck 量的是画出来那一圈，不是布局盒）。
## 按卡高上限 CARD_H_REF 算，不按面板高：面板高在 4:3 屏上是 696，照它留白每边要吃 21 单位，
## 而卡最高只有 280 ⇒ 每边 10 就够。多让的那 11×2 正好把 5 格货架挤成要横向滑（960×720 量出来）。
static func card_pad_x() -> float:
	return ceilf(CARD_SKEW_RAD * CARD_H_REF * 0.5) + 2.0

## 面板布局盒可用的宽 = 屏幕宽 - 面板左右占位 - 面板两头画出来的斜切 - 两头呼吸量
static func panel_inner_w(screen: Vector2) -> float:
	var bleed: float = skew_x(panel_h_for(screen.y)) + PANEL_AIR_X
	return maxf(0.0, screen.x - CHROME_X - bleed * 2.0)

## 一排卡可用的宽 = 面板内容宽 - 滚动区两头的斜切留白（card_pad_x）
static func avail_w(screen: Vector2) -> float:
	return maxf(0.0, panel_inner_w(screen) - card_pad_x() * 2.0)

## 卡间缝隙：宽屏上松一点，窄屏上不抢卡片的宽
static func gap_for(avail: float) -> float:
	return clampf(avail * 0.014, CARD_GAP_MIN, CARD_GAP_MAX)

## n 张卡均分可用宽，夹在 [CARD_W_MIN, CARD_W_MAX]。取整：面板宽由「卡宽×格数 + 缝隙」反算，
## 两头但凡有一处带小数，摆出来的内容就会比滚动区可视宽多出几个单位 —— 那几单位足够把
## 横向滑条叫出来（明明放得下却露一条滑条，比滑不动还难看）。
static func offer_card_w(screen: Vector2, count: int) -> float:
	if count <= 0:
		return CARD_W_MAX
	var avail := avail_w(screen)
	return floorf(clampf((avail - gap_px(screen) * float(count - 1)) / float(count),
		CARD_W_MIN, CARD_W_MAX))

## 卡间缝隙的唯二读数：容器用的整数与反算面板宽用的浮点必须是同一个数
static func offer_separation(screen: Vector2) -> int:
	return int(round(gap_for(avail_w(screen))))

static func gap_px(screen: Vector2) -> float:
	return float(offer_separation(screen))

## 卡片里文字可用的宽（与 LevelUpDialog.card_inner_w 同名同形，判据按它切文案的硬换行）
static func card_inner_w(card_w: float) -> float:
	return card_w - OFFER_PAD_X * 2.0

## 名号可用的宽 = 卡内宽再让出图标与缝隙（图标与名号同行）。判据按它切名号的硬换行，别处不抄数字。
static func card_name_w(card_w: float) -> float:
	return maxf(48.0, card_inner_w(card_w) - CARD_ICON - 6.0)

## 陈列槽边长：先按件数把这一行压到摆得下（夹在 [INV_SLOT_MIN, INV_SLOT]，与货架卡同一
## 口径、不抄死数）。压到下限还摆不下时（满仓 6 上阵 + 9 背包 + 15 法宝 = 30 格，任何一档
## 屏都给不起 30×36 的宽）整排横着滑：全留 + 可滑到，不砍件数、不再压字号
## （2026-10-09 用户真机：「装备太多了，可以左右滑动啊，不然很多装备都操作不了了」）。
static func inv_slot_for(avail: float, count: int, chips: int = 0) -> float:
	if count <= 0:
		return INV_SLOT
	return clampf((avail - INV_CHIP_W * float(chips) - INV_GAP * float(count + chips - 1)) / float(count),
		INV_SLOT_MIN, INV_SLOT)

## 这一档屏下整块面板的布局盒该占的宽（画出来还要再加两头斜切，判据按它核对留白）
static func panel_w_for(screen: Vector2, count: int) -> float:
	return offer_card_w(screen, count) * float(count) + gap_px(screen) * float(maxi(count - 1, 0)) \
		+ CHROME_X + card_pad_x() * 2.0

## 面板布局盒的宽上限：再宽一点，画出来的两条斜切边就出屏了
static func panel_max_w(screen: Vector2) -> float:
	return panel_inner_w(screen) + CHROME_X

## 货架可视宽（= 面板宽 − 左右占位 − 滚动区两头的斜切留白）
static func shelf_view_w(screen: Vector2, count: int) -> float:
	var pw: float = minf(panel_w_for(screen, count), panel_max_w(screen))
	return pw - CHROME_X - card_pad_x() * 2.0

## n 张卡摆出来的内容宽
static func shelf_content_w(screen: Vector2, count: int) -> float:
	return offer_card_w(screen, count) * float(count) + gap_px(screen) * float(maxi(count - 1, 0))

## 这一屏货架要不要横向滑：格数多到卡宽已压在下限、或屏太窄时才会要（真机 20:9 上 5~6 格都不要）
static func shelf_needs_h_slide(screen: Vector2, count: int) -> bool:
	return shelf_content_w(screen, count) > shelf_view_w(screen, count) + 0.5

## 第二行：左羁绊、右「怎么用？」（原 OwnedLabel 那一整行提示搬进点按可得的详情卡）
var _info_bar: HBoxContainer = null
var _synergy_box: HBoxContainer = null
## 本次开面板那档屏：卡宽/缝隙/面板高按它现算（与 LevelUpDialog 同一口径，只在打开时量一次）
var _screen: Vector2 = Vector2(960, 540)

## 当前点选的法器：{"pool": "equipped"/"stash", "index": int}
var selected: Dictionary = {}

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 卡体登记成「长按键」：面板不是按钮，摇杆认不出 ⇒ 点面板空白处不许在它底下长出摇杆
	panel.add_to_group(DawnJoystick.UI_PRESS_HOLD_GROUP)
	GameStyle.label(stones_label, 17, GameStyle.INK_TEXT)
	GameStyle.label(wave_label, 15, GameStyle.PAPER_DIM)
	GameStyle.button(reroll_btn, GameStyle.NAVY2, GameStyle.LINE, 14, GameStyle.PAPER_DIM)
	GameStyle.button(confirm_btn, GameStyle.BLUE, GameStyle.YELLOW, 18, GameStyle.PAPER, 6.0, GameStyle.INK_TEXT)
	confirm_btn.text = "出  战"
	# 两排滚动条统一长相：引擎默认那根浅灰与这块深蓝面板不搭（货架摆不平那一档会露出来）
	GameStyle.scrollable(offers_scroll)
	GameStyle.scrollable(owned_scroll)
	GameManager.shop_opened.connect(_on_shop_opened)
	reroll_btn.pressed.connect(_on_reroll)
	confirm_btn.pressed.connect(_on_confirm)

	# 顶栏右侧添加「属性」按钮，方便随时查看主要/次要面板
	var top_bar: HBoxContainer = $CenterContainer/Panel/MarginContainer/VBox/TopBar
	var stats_btn := Button.new()
	stats_btn.text = "属 性"
	stats_btn.custom_minimum_size = Vector2(72, 32)
	stats_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(stats_btn, GameStyle.NAVY2, GameStyle.YELLOW, 13, GameStyle.PAPER, 4.0, GameStyle.INK_TEXT)
	stats_btn.pressed.connect(func(): stats_requested.emit())
	top_bar.add_child(stats_btn)

	# 第二行：左边羁绊总览，右边「怎么用？」。原先这一屏有两行纯文字（羁绊行 + 操作提示行），
	# 合起来吃掉 25+8 单位竖向预算；提示是「想知道才看」的东西 ⇒ 收进点按可得的详情卡。
	_info_bar = HBoxContainer.new()
	_info_bar.name = "InfoBar"
	_info_bar.add_theme_constant_override("separation", 8)
	_synergy_box = HBoxContainer.new()
	_synergy_box.name = "SynergyBox"
	_synergy_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_synergy_box.add_theme_constant_override("separation", 8)
	_info_bar.add_child(_synergy_box)
	var help_btn := Button.new()
	help_btn.name = "HelpButton"
	help_btn.text = "怎么用？"
	help_btn.custom_minimum_size = Vector2(80, 22)
	help_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(help_btn, GameStyle.NAVY2, GameStyle.LINE, 12, GameStyle.PAPER_DIM, 4.0)
	help_btn.pressed.connect(_open_usage_tip)
	_info_bar.add_child(help_btn)
	var vbox: VBoxContainer = $CenterContainer/Panel/MarginContainer/VBox
	vbox.add_child(_info_bar)
	vbox.move_child(_info_bar, 1)

## 羁绊总览：激活的流派显示金色等级徽记，未激活显示灰色进度；支持点按查看详情卡
func _refresh_synergy_bar() -> void:
	if _synergy_box == null:
		return
	for child in _synergy_box.get_children():
		child.queue_free()
	for tag in GameManager.active_synergies.keys():
		var info: Dictionary = WeaponData.SYNERGIES.get(tag, {})
		if info.is_empty():
			continue
		var data: Dictionary = GameManager.active_synergies[tag]
		var n := int(data.get("count", 0))
		var lv := int(data.get("level", 0))
		var raw_th: Array = info.get("thresholds", [2, 4, 6])
		var shift: int = GameManager.spirit_threshold_adj if tag == "spirit" else 0
		var max_th: int = maxi(1, int(raw_th[raw_th.size() - 1]) - shift)
		var chip_lbl := Label.new()
		chip_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		chip_lbl.text = " %s (%d/%d) " % [info.get("name", tag), n, max_th]
		if lv > 0:
			chip_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.YELLOW if tag in WeaponData.ELEMENTS else GameStyle.BLUE))
			GameStyle.label(chip_lbl, 12, GameStyle.INK_TEXT)
		else:
			chip_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.NAVY2))
			GameStyle.label(chip_lbl, 12, GameStyle.PAPER_DIM)
		chip_lbl.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
				_open_shop_synergy_tip(tag, chip_lbl)
		)
		_synergy_box.add_child(chip_lbl)

func _open_shop_synergy_tip(tag: String, anchor: Control) -> void:
	var info: Dictionary = WeaponData.SYNERGIES.get(tag, {})
	if info.is_empty():
		return
	var data: Dictionary = GameManager.active_synergies.get(tag, {"count": 0, "level": 0})
	var n: int = int(data.get("count", 0))
	var lv: int = int(data.get("level", 0))
	var raw_th: Array = info.get("thresholds", [2, 4, 6])
	var shift: int = GameManager.spirit_threshold_adj if tag == "spirit" else 0
	var max_th: int = maxi(1, int(raw_th[raw_th.size() - 1]) - shift)
	var first_th: int = maxi(1, int(raw_th[0]) - shift)
	var rows: Array = [
		["当前装备", "%d / %d 件" % [n, max_th], GameStyle.YELLOW if lv > 0 else GameStyle.PAPER],
		["共鸣状态", "已达成第 %d 档" % lv if lv > 0 else "未激活 (差 %d 件)" % maxi(1, first_th - n), GameStyle.GOOD if lv > 0 else GameStyle.GREY],
	]
	var tier_lines: Array = PlayerStatsDialog.SYNERGY_TIER_LINES.get(tag, [])
	for idx in range(raw_th.size()):
		var th_need: int = maxi(1, int(raw_th[idx]) - shift)
		var tier_txt: String = String(tier_lines[idx]) if idx < tier_lines.size() else ""
		var reached: bool = n >= th_need
		rows.append([
			"(%d/%d) 阶梯" % [th_need, max_th],
			tier_txt,
			GameStyle.GOOD if lv == idx + 1 else (GameStyle.PAPER_DIM if reached else GameStyle.GREY)
		])
	var notes: Array[String] = [
		"同标签法器上阵达到 %d / %d / %d 件时依次激活阶梯加成。" % [
			maxi(1, int(raw_th[0]) - shift),
			maxi(1, int(raw_th[1]) - shift),
			max_th
		],
		String(info.get("desc", "")),
	]
	DetailTip.show_over(self, anchor, {
		"title": "%s (%d/%d)" % [info.get("name", tag), n, max_th],
		"chip": "五行共鸣" if tag in WeaponData.ELEMENTS else "器类羁绊",
		"chip_color": GameStyle.YELLOW if tag in WeaponData.ELEMENTS else GameStyle.BLUE,
		"rows": rows,
		"body": "流派共鸣：持有越多同类法器，道法威能越强盛。",
		"notes": notes,
		"foot": "在波间灵石阁挑选同标签法器可继续提升阶位。",
	})

## 「怎么用？」：原先钉在货架下方那一整行的操作提示，收进点按可得的详情卡
## （触屏无 hover，说明必须点得到；这一行省下来的竖向预算全给货架）。
func _open_usage_tip() -> void:
	var help_btn: Button = _info_bar.get_node("HelpButton")
	var max_slots: int = GameManager.max_weapon_slots()
	var slot_txt: String = "%d 件（本道统上限）" % max_slots if max_slots < WeaponData.MAX_SLOTS else "%d 件" % max_slots
	var rows: Array = [
		["周身槽位", slot_txt, GameStyle.YELLOW if max_slots < WeaponData.MAX_SLOTS else GameStyle.PAPER],
		["背包格数", "%d 格" % WeaponData.MAX_STASH_SLOTS, GameStyle.PAPER],
		["货架格数", "%d 格" % GameManager.shop_offers.size(), GameStyle.PAPER],
	]
	var notes: Array[String] = [
		"点中一件法器（上阵或背包里的）才能动手：三合一合成升星、上阵卸下、出售换灵石。",
		"三合一：集齐三把同名同星，合成后升一星（最高 %s）。" % WeaponData.star_text(WeaponData.MAX_STAR),
		"锁定：这一格留到下波，重掷与刷新都不会换掉它。",
		"重掷货架：换一批候选；每波有免费次数，用完按价格扣灵石。",
		"已售出的格子本波不会补货，出战后货架重开。",
	]
	if max_slots < WeaponData.MAX_SLOTS:
		notes.insert(0, "本道统限佩 %d 件上阵法器：超出上限的法器会收进背包，可用于三合一升星或先卸下当前法器再换装。" % max_slots)
	DetailTip.show_over(self, help_btn, {
		"title": "灵石阁怎么用",
		"chip": "波间商店",
		"chip_color": GameStyle.BLUE,
		"rows": rows,
		"body": "每波结束后来此置办法器：灵石换法器与法宝，摆不满的收进背包。",
		"notes": notes,
		"foot": "周身槽位满时再买，新法器会自动进背包。",
	})

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		if DetailTip.close_all(self):
			get_viewport().set_input_as_handled()

func _on_shop_opened() -> void:
	selected = {}
	_layout_for_viewport()
	refresh()
	visible = true
	get_tree().paused = true
	modulate.a = 0.0
	var tw = create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.2)

## 按这一档屏宽现算面板与货架卡：高钉成「屏幕高 - 呼吸量」，宽按格数均分可用宽。
## 货架卡高由内容决定 ⇒ 这一屏正常情况下竖着不需要滑（判据点名量那条）；
## 格数多到一屏宽摆不下时（6 格 + 窄窗）面板宽钉在上限、多出来的那一格由货架横向滑 ——
## 顶栏、陈列行、重掷/出战永远在屏内，比「竖着滑才能看到出战」是轻得多的毛病。
func _layout_for_viewport() -> void:
	var screen: Vector2 = get_viewport().get_visible_rect().size
	_screen = screen
	var count: int = maxi(GameManager.shop_offers.size(), 1)
	var max_w: float = panel_max_w(screen)
	var want_w: float = panel_w_for(screen, count)
	panel.custom_minimum_size = Vector2(minf(want_w, max_w), panel_h_for(screen.y))
	offers_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO \
			if shelf_needs_h_slide(screen, count) else ScrollContainer.SCROLL_MODE_DISABLED
	# 两头让出卡片斜切的余量：画出来的角不许被滚动区边界切掉（判据量的是画出来那一圈）
	var pad := int(card_pad_x())
	offers_pad.add_theme_constant_override("margin_left", pad)
	offers_pad.add_theme_constant_override("margin_right", pad)
	offers_scroll.scroll_vertical = 0
	offers_scroll.scroll_horizontal = 0
	# 每次开面板陈列行回到最左：上一波划到哪里不该带到这一波
	owned_scroll.scroll_horizontal = 0

func refresh() -> void:
	stones_label.text = "灵石 %d" % GameManager.spirit_stones
	wave_label.text = "第 %d 波来犯之前 · 置办法器" % (GameManager.wave_number + 1)
	if GameManager.reroll_free_left > 0:
		reroll_btn.text = "免费重掷 (剩 %d 次)" % GameManager.reroll_free_left
	else:
		reroll_btn.text = "重掷货架 (%d 灵石)" % GameManager.reroll_cost
	_refresh_synergy_bar()

	for child in offers_container.get_children():
		child.queue_free()
	var offers: Array = GameManager.shop_offers
	var count := offers.size()
	var card_w := offer_card_w(_screen, count)
	offers_container.add_theme_constant_override("separation", offer_separation(_screen))
	for i in range(count):
		var c := _create_offer_card(offers[i], i, count)
		offers_container.add_child(c)
		c.pivot_offset = Vector2(card_w * 0.5, CARD_H_REF * 0.5)
		c.scale = Vector2(0.82, 0.82)
		c.modulate.a = 0.0
		var ctw := c.create_tween()
		# 卡高由内容决定 ⇒ 支点要等布局出尺寸之后按实际那一格中心重设，
		# 否则入场放大绕的是参考高的中心，落点会往一边偏（与 LevelUpDialog 同一处理）。
		ctw.tween_callback(_center_pivot.bind(c))
		ctw.tween_interval(float(i) * 0.045)
		ctw.set_parallel(true)
		ctw.tween_property(c, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		ctw.tween_property(c, "modulate:a", 1.0, 0.15)

	_refresh_inventory()

## 支点 = 这一格自己的中心（布局出尺寸之前无从得知，动画第一帧补上）
static func _center_pivot(c: Control) -> void:
	if c.size.y > 0.0:
		c.pivot_offset = c.size * 0.5

# ---------------- 上阵 + 背包栏位 ----------------

func _refresh_inventory() -> void:
	# 点一件法器会重建整行（选中描边/合成高亮都要重画）：不记着滑到的位置，视野会跳回最左，
	# 刚点的那一格从眼前跑掉 —— 满仓时等于逼玩家每点一次就重新划一遍。
	var keep_x: float = owned_scroll.scroll_horizontal
	for child in owned_container.get_children():
		child.queue_free()

	var summary: Array = GameManager.get_weapons_summary()
	var max_slots: int = GameManager.max_weapon_slots()
	var slot_capped: bool = max_slots < WeaponData.MAX_SLOTS
	# 背包空位画成凹槽提示容量；上阵较满时少画几个避免溢出
	var empty_budget: int = clampi(10 - summary.size() - GameManager.stash.size(), 0, 3)
	var free_tiles: int = mini(WeaponData.MAX_STASH_SLOTS - GameManager.stash.size(), empty_budget)
	# 槽边长按件数现算，压到下限还摆不下就由 OwnedScroll 横滑（满仓 6 上阵 + 9 背包 + 法宝徽记）
	var n_tile: int = summary.size() + GameManager.stash.size() + free_tiles + GameManager.items.size()
	var n_chip: int = (0 if summary.is_empty() and GameManager.stash.is_empty() else (2 if slot_capped else 1)) \
		+ (1 if not GameManager.items.is_empty() else 0)
	var tile := inv_slot_for(panel_inner_w(_screen), n_tile, n_chip)
	if summary.is_empty() and GameManager.stash.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "（周身还没有法器）"
		owned_container.add_child(empty_lbl)
		GameStyle.label(empty_lbl, 13, GameStyle.GREY)
	else:
		if slot_capped:
			owned_container.add_child(_create_equipped_cap_chip(summary.size(), max_slots))
		for i in range(summary.size()):
			owned_container.add_child(_create_inv_slot(summary[i], i, "equipped", tile))
		owned_container.add_child(_create_stash_divider())
		for i in range(GameManager.stash.size()):
			owned_container.add_child(_create_inv_slot(GameManager.stash[i], i, "stash", tile))
		for i in range(free_tiles):
			owned_container.add_child(_create_empty_stash_slot(tile))

	# 已持有法宝（被动道具）陈列：小图标 + 点按查看说明，不参与点选操作
	if not GameManager.items.is_empty():
		owned_container.add_child(_create_items_divider())
		for item_id in GameManager.items:
			owned_container.add_child(_create_item_chip(item_id, tile))

	# 整排都要划得起来：装饰性 STOP 会把「按下」那一拍就地吃掉，卡住多大面积就滑不动多大面积
	# （同一把尺见 GameStyle.swipeable 头注）。这一排的格子已经都不是 Button 了（见
	# _create_inv_slot 头注），所以这里递归一遍 + 构造函数里显式 PASS，两处一起兜住以后加的装饰件。
	GameStyle.swipeable(owned_container)
	_keep_row_scroll(keep_x)
	_refresh_action_bar()

## 重建之后（下一帧才量得出新的内容宽）把横向位置还回去：早一帧设会被旧宽度夹成 0。
## 等两帧而不是等一帧：第一帧子节点才从队列里真删掉、容器重排，第二帧宽度才是新内容宽。
func _keep_row_scroll(x: float) -> void:
	if x <= 0.0:
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(owned_scroll):
		owned_scroll.scroll_horizontal = int(x)

func _create_inv_slot(item: Dictionary, index: int, pool: String, tile: float) -> Control:
	var id: String = item.get("id", "")
	var star: int = int(item.get("star", 1))
	var mergeable: bool = star < WeaponData.MAX_STAR and GameManager.count_copies(id, star) >= 3
	var is_sel: bool = selected.get("pool", "") == pool and int(selected.get("index", -1)) == index

	# 不用 Button：BaseButton 在自己的 gui_input 里 accept_event()，「按下」那一拍不往父级冒泡
	# ⇒ 手指压在槽位上就划不动整排，而满仓 30 格里几乎全是槽位。属性面板的槽位同一口径
	# （PanelContainer + GameStyle.tap，见 PlayerStatsDialog._refresh_weapons）。
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(tile, tile)
	slot.mouse_filter = Control.MOUSE_FILTER_PASS

	var border: Color = GameStyle.LINE
	var bg: Color = GameStyle.NAVY2
	if pool == "equipped":
		border = GameStyle.BLUE
		bg = GameStyle.NAVY
	if mergeable:
		border = GameStyle.YELLOW
	if is_sel:
		border = GameStyle.PAPER
		bg = GameStyle.NAVY.lightened(0.08)
	var sb := GameStyle.outlined_panel(bg, border, 2, 0.0)
	# 图标与星角共用的内缩：PanelContainer 把每个子节点都铺满内容区，内缩只能给在 stylebox 上
	sb.content_margin_left = 3.0
	sb.content_margin_top = 3.0
	sb.content_margin_right = 3.0
	sb.content_margin_bottom = 3.0
	slot.add_theme_stylebox_override("panel", sb)

	var icon_path: String = item.get("icon", "")
	if icon_path.is_empty():
		icon_path = WeaponData.get_def(id).get("icon", "")

	var icon_tex := TextureRect.new()
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		icon_tex.texture = load(icon_path)
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(icon_tex)

	# 吃「元素伤害」属性加成的法器挂橙红角标（与属性面板/图鉴同一口径）
	if WeaponData.elemental_scaling_coef(id) > 0.0:
		slot.add_child(GameStyle.element_badge(8))

	var star_lbl := Label.new()
	star_lbl.text = "★%d" % star
	star_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	star_lbl.add_theme_font_override("font", GameStyle.body_font())
	star_lbl.add_theme_font_size_override("font_size", 11)
	star_lbl.add_theme_color_override("font_color", GameStyle.YELLOW)
	star_lbl.add_theme_color_override("font_outline_color", GameStyle.INK)
	star_lbl.add_theme_constant_override("outline_size", 3)
	star_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	star_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	star_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	star_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slot.add_child(star_lbl)

	# 点选认「按下与抬起都留在原地」，不认松开：划列表时格子跟着内容一起走，手指自始至终压在
	# 同一格内 ⇒ 按旧写法（BaseButton.pressed）每划一下都顺手多选一件。
	GameStyle.tap(slot, func():
		if is_sel:
			selected = {}
		else:
			selected = {"pool": pool, "index": index}
		_refresh_inventory()
	)
	return slot

func _create_equipped_cap_chip(used: int, max_slots: int) -> Control:
	var chip := PanelContainer.new()
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, GameStyle.YELLOW_DK, 1, 0.0))
	var lbl := Label.new()
	lbl.text = "上阵 %d/%d（仅限%d件）" % [used, max_slots, max_slots]
	chip.add_child(lbl)
	GameStyle.label(lbl, 11, GameStyle.YELLOW)
	return chip

func _create_stash_divider() -> Control:
	var chip = PanelContainer.new()
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 1, 0.0))
	var lbl = Label.new()
	lbl.text = "背包 %d/%d" % [GameManager.stash.size(), WeaponData.MAX_STASH_SLOTS]
	chip.add_child(lbl)
	GameStyle.label(lbl, 11, GameStyle.GREY)
	return chip

func _create_items_divider() -> Control:
	var chip = PanelContainer.new()
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 1, 0.0))
	var lbl = Label.new()
	lbl.text = "法宝 %d" % GameManager.items.size()
	chip.add_child(lbl)
	GameStyle.label(lbl, 11, GameStyle.GREY)
	return chip

## 已持有法宝的小徽记：按档位描边，支持点按弹出 DetailTip 详解卡
func _create_item_chip(item_id: String, tile: float) -> Control:
	var def := ItemData.get_def(item_id)
	var chip = PanelContainer.new()
	chip.custom_minimum_size = Vector2(tile, tile)
	# 与图鉴卡/属性行同一约定：登记一下这颗徽位弹的是谁，判据不必再抄一份对照表
	chip.set_meta("tip_title", String(def.get("name", item_id)))
	# 与槽位同一口径：PASS，让「按下」那一拍冒泡到 OwnedScroll，压在法宝徽位上也划得动整排
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	var tier_num: int = int(def.get("tier", 1))
	var tier_col: Color = ItemData.tier_color(tier_num)
	chip.add_theme_stylebox_override("panel",
		GameStyle.outlined_panel(GameStyle.NAVY2, tier_col, 2, 0.0))
	var icon_tex = TextureRect.new()
	var icon_path: String = def.get("icon", "")
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		icon_tex.texture = load(icon_path)
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_tex.offset_left = 5
	icon_tex.offset_top = 5
	icon_tex.offset_right = -5
	icon_tex.offset_bottom = -5
	chip.add_child(icon_tex)

	# 划列表不算点按（同 _create_inv_slot：整排在 OwnedScroll 里）
	GameStyle.tap(chip, func(): _open_shop_item_tip(item_id, chip))
	return chip

func _open_shop_item_tip(item_id: String, anchor: Control) -> void:
	var def := ItemData.get_def(item_id)
	if def.is_empty():
		return
	var tier_num: int = int(def.get("tier", 1))
	var tier_col: Color = ItemData.tier_color(tier_num)
	var rows: Array = [
		["品阶", ItemData.tier_label(tier_num), tier_col],
		["买入灵石", "%d 灵石" % int(def.get("price", 0)), GameStyle.YELLOW],
	]
	var desc_lines: Array = String(def.get("desc", "")).split("\n")
	var notes: Array[String] = []
	for line in desc_lines:
		var s := String(line).strip_edges()
		if not s.is_empty():
			notes.append(s)
	DetailTip.show_over(self, anchor, {
		"title": String(def.get("name", item_id)),
		"chip": "法宝灵物",
		"chip_color": tier_col,
		"rows": rows,
		"body": "本命法宝：被动生效，无需占用上阵槽位，整局战斗持续庇护。",
		"notes": notes,
		"foot": "在波间灵石阁可邂逅更多稀世奇珍。",
	})

func _create_empty_stash_slot(tile: float) -> Control:
	var slot = PanelContainer.new()
	slot.custom_minimum_size = Vector2(maxf(20.0, tile * 0.6), tile)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := GameStyle.slot()
	style.bg_color = Color(GameStyle.INK.r, GameStyle.INK.g, GameStyle.INK.b, 0.55)
	slot.add_theme_stylebox_override("panel", style)
	return slot

# ---------------- 点选操作条 ----------------

func _refresh_action_bar() -> void:
	for child in action_bar.get_children():
		child.queue_free()

	if selected.is_empty():
		# 操作提示已并进上方「上阵与背包」那一行（OwnedLabel）：空载时这一排整排收起来，
		# 把高度让给货架 —— 面板高已钉死，这里省下的每一单位都是少滑一点。
		action_bar.visible = false
		return
	action_bar.visible = true

	var item := _resolve_selected()
	if item.is_empty():
		selected = {}
		_refresh_action_bar()
		return

	var id: String = item.get("id", "")
	var star: int = int(item.get("star", 1))
	var pool: String = selected.get("pool", "")
	var in_stash: bool = pool == "stash"
	var mergeable: bool = star < WeaponData.MAX_STAR and GameManager.count_copies(id, star) >= 3

	var max_slots: int = GameManager.max_weapon_slots()
	var slots_full: bool = GameManager.slots_used() >= max_slots
	var name_lbl = Label.new()
	var loc_txt := "背包" if in_stash else "上阵中"
	if in_stash and slots_full:
		loc_txt = "背包（上阵已满 %d/%d 件）" % [GameManager.slots_used(), max_slots]
	name_lbl.text = "%s · %s" % [WeaponData.full_name(id, star), loc_txt]
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	action_bar.add_child(name_lbl)
	GameStyle.label(name_lbl, 15, GameStyle.PAPER)

	if mergeable:
		var merge_btn = Button.new()
		merge_btn.text = "三合一 ▲★%d" % (star + 1)
		merge_btn.custom_minimum_size = Vector2(128, 32)
		merge_btn.focus_mode = Control.FOCUS_NONE
		GameStyle.button(merge_btn, GameStyle.YELLOW, GameStyle.YELLOW_EDGE, 14, GameStyle.INK_TEXT, 6.0)
		var keep := {"pool": "equipped", "index": int(selected.get("index", -1))}
		if in_stash:
			keep["pool"] = "stash"
		elif item.get("is_drone", false):
			keep["pool"] = "drone"
			keep["index"] = int(item.get("drone_index", -1))
		merge_btn.pressed.connect(func():
			# 成功音由 GameManager.merge_weapon 统一播（merge_success）；
			# 这里只补「按了但没合成」的反馈，不让它听起来像成功了
			if not GameManager.merge_weapon(id, star, keep):
				AudioManager.play_sfx("ui_error", 0.9)
			selected = {}
			refresh()
		)
		action_bar.add_child(merge_btn)

	var move_btn = Button.new()
	move_btn.custom_minimum_size = Vector2(108, 32)
	move_btn.focus_mode = Control.FOCUS_NONE
	if in_stash:
		move_btn.disabled = slots_full
		move_btn.text = "上阵已满(%d/%d)" % [GameManager.slots_used(), max_slots] if slots_full else "上 阵"
		if slots_full:
			move_btn.custom_minimum_size = Vector2(118, 32)
		GameStyle.button(move_btn, GameStyle.GOOD if not move_btn.disabled else GameStyle.NAVY2, GameStyle.GOOD_DK, 14, GameStyle.INK_TEXT if not move_btn.disabled else GameStyle.GREY, 6.0)
		move_btn.pressed.connect(func():
			if GameManager.equip_from_stash(int(selected.get("index", -1))):
				selected = {}
				refresh()
		)
	else:
		move_btn.text = "卸入背包"
		move_btn.disabled = GameManager.stash.size() >= WeaponData.MAX_STASH_SLOTS
		GameStyle.button(move_btn, GameStyle.NAVY2, GameStyle.LINE, 14, GameStyle.PAPER, 6.0)
		move_btn.pressed.connect(func():
			if GameManager.unequip_to_stash(int(selected.get("index", -1))):
				selected = {}
				refresh()
		)
	action_bar.add_child(move_btn)

	var price := WeaponData.sell_price(id, star)
	var sell_btn = Button.new()
	sell_btn.text = "售 %d 灵石" % price
	sell_btn.custom_minimum_size = Vector2(112, 32)
	sell_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(sell_btn, GameStyle.BAD, GameStyle.BAD_DK, 14, GameStyle.PAPER, 6.0)
	sell_btn.pressed.connect(func():
		var ok := false
		if in_stash:
			ok = GameManager.sell_stash(int(selected.get("index", -1)))
		else:
			ok = GameManager.sell_weapon(int(selected.get("index", -1)))
		if ok:
			selected = {}
			refresh()
	)
	action_bar.add_child(sell_btn)

func _resolve_selected() -> Dictionary:
	if selected.is_empty():
		return {}
	var pool: String = selected.get("pool", "")
	var index := int(selected.get("index", -1))
	if pool == "stash":
		if index < 0 or index >= GameManager.stash.size():
			return {}
		return GameManager.stash[index]
	var summary: Array = GameManager.get_weapons_summary()
	if index < 0 or index >= summary.size():
		return {}
	return summary[index]

# ---------------- 货架 ----------------

func _create_offer_card(offer: Dictionary, index: int, total_count: int = 4) -> Control:
	var card_w := offer_card_w(_screen, total_count)
	var kind: String = offer.get("kind", "weapon")
	var is_potion: bool = kind == "potion"
	var is_item: bool = kind == "item"
	var def := {}
	var title: String
	var icon_path: String
	var tag: String
	var tag_parts: Array = []  # 武器羁绊每维一颗签的文案（2026-10-09 用户：不同的属性分块放）
	var part_hot: Array = []   # 与 tag_parts 一一对应：买下这件该维羁绊是否即激活
	var desc: String
	var chip_color: Color = GameStyle.BLUE
	var chip_text_color: Color = GameStyle.PAPER
	var edge_color: Color = GameStyle.BLUE_DK
	if is_potion:
		title = "回气丹"
		icon_path = "res://assets/art/icon_hp.png"
		tag = "丹药"
		desc = "服下立刻恢复五成气血"
		chip_color = GameStyle.GOOD
		chip_text_color = GameStyle.INK_TEXT
		edge_color = GameStyle.YELLOW_DK
	elif is_item:
		def = ItemData.get_def(offer.get("id", ""))
		var tier := int(def.get("tier", 1))
		title = def.get("name", "?")
		icon_path = def.get("icon", "")
		tag = "%s·法宝" % ItemData.tier_label(tier)
		desc = def.get("desc", "")
		chip_color = ItemData.tier_color(tier)
		chip_text_color = GameStyle.INK_TEXT
		edge_color = ItemData.tier_color(tier).darkened(0.35)
	else:
		var w_id: String = String(offer.get("id", ""))
		def = WeaponData.get_def(w_id)
		# 名号不带「★ 」前缀：货架上每一件都是 ★1（roll_shop 只出 1 星），前缀是冗余信息，
		# 而它正好把 5 字名号挤出「图标旁那一行」—— 省下来换名号不折行。
		title = def.get("name", "?")
		icon_path = def.get("icon", "")
		tag = def.get("tag", "")
		# 双维羁绊进度：器类与五行各占一颗签、分块摆放（2026-10-09 用户：「不同的属性可以分块放」）。
		# 「离下一档还差几件」的进度留在各自签上；买下能激活的那一维整签金色高亮（卡边框同步泛金）。
		var wtags: Array = def.get("tags", [])
		var will_activate := false
		for t in wtags:
			var syn: Dictionary = WeaponData.SYNERGIES.get(t, {})
			if syn.is_empty():
				continue
			var n := GameManager.get_tag_count(t)
			var next := "MAX"
			var hot := false
			var th_arr: Array = syn.get("thresholds", [])
			for th in th_arr:
				if n < int(th):
					next = str(th)
					hot = (n + 1 == int(th))
					break
			tag_parts.append("%s %d/%s" % [syn.get("name", t), n, next])
			part_hot.append(hot)
			will_activate = will_activate or hot
		if not tag_parts.is_empty():
			tag = " · ".join(tag_parts)
		if will_activate:
			chip_color = GameStyle.YELLOW
			chip_text_color = GameStyle.INK_TEXT
			edge_color = GameStyle.YELLOW
		desc = def.get("desc", "")
		var bonus_dmg := GameManager.get_weapon_stat_bonus(w_id, 1)
		if bonus_dmg > 0.05:
			desc += "\n(当前属性额外伤害 +%d)" % int(round(bonus_dmg))

	var card = PanelContainer.new()
	# 高由内容决定：钉死 268 的那一版让五张卡顶出滚动区 ⇒ 整排要竖着滑（用户报的就是这个）。
	# 判据 LayoutCheck 现在点名量「最坏样本下内容高 ≤ 滚动区高」，这张卡不许再往回长。
	card.custom_minimum_size = Vector2(card_w, 0)
	var inner_w: float = card_inner_w(card_w)
	var style = StyleBoxFlat.new()
	style.bg_color = GameStyle.NAVY
	style.skew = Vector2(deg_to_rad(3.0), 0)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 5
	style.border_color = edge_color
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 0
	style.shadow_offset = Vector2(5, 5)
	style.content_margin_left = OFFER_PAD_X
	style.content_margin_top = CARD_PAD_Y
	style.content_margin_right = OFFER_PAD_X
	style.content_margin_bottom = CARD_PAD_Y
	card.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", int(CARD_SEP))
	vbox.alignment = BoxContainer.ALIGNMENT_BEGIN

	var sold: bool = offer.get("sold", false)
	var price: int = int(offer.get("price", 0))

	# ── 行①：图标与名号同一行。旧版图标独占一行 62 高，是这一屏最贵的一笔浪费。
	var head := HBoxContainer.new()
	head.name = "CardHead"
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 6)
	var icon_box = PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(CARD_ICON, CARD_ICON)
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 2, 0.0))
	var icon_tex = TextureRect.new()
	if ResourceLoader.exists(icon_path):
		icon_tex.texture = load(icon_path)
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.custom_minimum_size = Vector2(CARD_ICON - 10.0, CARD_ICON - 10.0)
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_child(icon_tex)
	# 吃「元素伤害」属性加成的法器挂橙红角标（仅武器，丹药/法宝不走该链路）
	if kind == "weapon" and WeaponData.elemental_scaling_coef(String(offer.get("id", ""))) > 0.0:
		icon_box.add_child(GameStyle.element_badge(8))
	head.add_child(icon_box)
	# 名号可用宽 = 卡内宽 − 图标 − 缝隙；切完仍摆不下的名号由判据点名
	var name_w: float = card_name_w(card_w)
	var title_lbl = Label.new()
	title_lbl.text = GameStyle.wrap_cjk(title, GameStyle.display_font(), 17, name_w)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_lbl.custom_minimum_size = Vector2(name_w, 0)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(title_lbl)
	GameStyle.label(title_lbl, 17, GameStyle.PAPER, 0, GameStyle.INK, true)
	vbox.add_child(head)

	# ── 行②：羁绊色签（每维一颗、分块摆放）+ 锁定开关同一行。锁定从「独占一行 26」压成色签行右端一枚角键，
	#    「留到下波」那句解释改由「怎么用？」点按可得（触屏无 hover，见 AGENTS.md UI 规范）。
	var lock_w := 0.0 if sold else CARD_LOCK_W
	var tag_row := HBoxContainer.new()
	tag_row.name = "TagRow"
	tag_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_row.add_theme_constant_override("separation", 4)
	# 签流：一行摆不下就整签换到下一行；签内文字永不竖排 —— 文案钉宽 + 不开 autowrap（杜绝「框 5×191」老坑）
	var tag_flow := HFlowContainer.new()
	tag_flow.name = "TagFlow"
	tag_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag_flow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag_flow.add_theme_constant_override("h_separation", 4)
	tag_flow.add_theme_constant_override("v_separation", 2)
	tag_row.add_child(tag_flow)
	# 武器每维羁绊一颗签（买下即激活的那一维整签泛金），丹药/法宝维持单签
	var chip_defs: Array = []
	if tag_parts.is_empty():
		chip_defs.append([tag, chip_color, chip_text_color])
	else:
		for i in range(tag_parts.size()):
			var hot_i: bool = bool(part_hot[i])
			chip_defs.append([tag_parts[i],
				GameStyle.YELLOW if hot_i else chip_color,
				GameStyle.INK_TEXT if hot_i else chip_text_color])
	for cd in chip_defs:
		var chip_txt: String = " %s " % cd[0]
		var chip_lbl = Label.new()
		chip_lbl.text = chip_txt
		chip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# 贴着字走的色签：宽钉成「整句单行的宽」，签内不折行（判据 LayoutCheck 抓过竖排老坑）
		chip_lbl.custom_minimum_size = Vector2(GameStyle.chip_pin_w(chip_txt, GameStyle.body_font(), 11), 0)
		chip_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip_lbl.add_theme_stylebox_override("normal", GameStyle.chip(cd[1]))
		tag_flow.add_child(chip_lbl)
		GameStyle.label(chip_lbl, 11, cd[2])
	if not sold:
		var locked: bool = offer.get("locked", false)
		var lock_btn = Button.new()
		lock_btn.name = "LockButton"
		lock_btn.custom_minimum_size = Vector2(CARD_LOCK_W, CARD_LOCK_H)
		lock_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		lock_btn.focus_mode = Control.FOCUS_NONE
		lock_btn.text = "已锁" if locked else "锁定"
		GameStyle.button(lock_btn, GameStyle.YELLOW if locked else GameStyle.NAVY2,
			GameStyle.YELLOW_DK if locked else GameStyle.LINE, 11,
			GameStyle.INK_TEXT if locked else GameStyle.PAPER_DIM, 4.0)
		lock_btn.pressed.connect(func():
			GameManager.toggle_lock(index)
			refresh()
		)
		tag_row.add_child(lock_btn)
	vbox.add_child(tag_row)

	# ── 行③：说明全文留在卡上（不砍文案不压字号），它吃掉剩余高度 ⇒ 各卡的价格键自然对齐
	var desc_lbl = Label.new()
	desc_lbl.text = GameStyle.wrap_cjk(desc, GameStyle.body_font(), 12, inner_w)
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	desc_lbl.custom_minimum_size = Vector2(inner_w, 0)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(desc_lbl)
	GameStyle.label(desc_lbl, 12, GameStyle.PAPER_DIM)

	# ── 行④：价格键整宽（最长的那句「上阵背包已满」要独得下这一行）
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(0, CARD_PRICE_H)
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	GameStyle.button(btn, GameStyle.YELLOW, GameStyle.PAPER, 14, GameStyle.INK_TEXT, 6.0)
	btn.text = "%d 灵石" % price
	if sold:
		btn.text = "已 售 出"
		btn.disabled = true
	elif GameManager.spirit_stones < price:
		btn.disabled = true
	elif is_item and bool(def.get("unique", false)) and GameManager.has_item(offer.get("id", "")):
		btn.disabled = true
		btn.text = "已 持 有"
	elif kind == "weapon" and GameManager.slots_used() >= GameManager.max_weapon_slots() \
			and GameManager.stash.size() >= WeaponData.MAX_STASH_SLOTS:
		btn.disabled = true
		btn.text = "上阵背包已满"
	elif kind == "weapon" and GameManager.slots_used() >= GameManager.max_weapon_slots():
		btn.text = "%d 灵石 · 入背包" % price
	btn.pressed.connect(func():
		if GameManager.buy_offer(index):
			refresh()
	)
	vbox.add_child(btn)
	card.add_child(vbox)
	# 货架排仍留在 ScrollContainer 里作兜底（万一某档屏真放不下，宁可滑也不许切文案）：
	# 卡片本体要把「按下」那一拍冒泡给它，否则手指压在卡上滑不动（真机现场见 ScrollSwipeCheck 头注）。
	# 只降装饰层：价格/锁定是 BaseButton，GameStyle.swipeable 会跳过，点按照常。
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	GameStyle.swipeable(card)
	return card

func _on_reroll() -> void:
	GameManager.reroll_shop()
	refresh()

func _on_confirm() -> void:
	AudioManager.play_sfx("orb_hit", 1.0)
	visible = false
	GameManager.confirm_shop()
