class_name WaveShop
extends Control

## 商店：购买武器/回复药、重掷货架；
## 上阵 + 背包统一点选后操作：三合一合成 / 上阵卸下 / 出售换金币
## 拆分说明：本体保留摆位口径（判据引用）、开面板/刷新编排与陈列行装配；
## 货架卡构建在 ShopOfferCardFactory、武器悬浮菜单在 ShopWeaponTip、陈列槽位在 ShopInventoryRow。

signal stats_requested
signal pause_requested
## 查流派武器总表：filter_tag 为 "" 时打开武器图鉴不筛选（顶栏按钮），
## 否则直达并预选该流派（羁绊详情卡「查看该流派武器」）；Main 接线到 ManualDialog
signal manual_requested(filter_tag: String)
## 作者模式面板（仅 author_mode 时按钮可见，由 Main 接线）
signal author_requested

@onready var panel: PanelContainer = $CenterContainer/Panel
## 内容层（面板本体）：开店的淡入只作用在这一层，根上的全屏 DimOverlay 压暗底随 visible
## 立即满不透明 —— 加点面板收屏与商店进场的交叉淡变期间，两层暗底无缝接力，
## 不会闪出身后的战场（2026-10-16 用户反馈「确认加点后闪一下别的画面」）。
## 出场（出战回战场）仍是整根淡出，让暗底随面板一起退，那是预期效果。
@onready var content: Control = $CenterContainer
@onready var stones_label: Label = $CenterContainer/Panel/MarginContainer/VBox/TopBar/StonesChip/StonesLabel
@onready var wave_label: Label = $CenterContainer/Panel/MarginContainer/VBox/TopBar/WaveLabel
@onready var offers_scroll: ScrollContainer = $CenterContainer/Panel/MarginContainer/VBox/OffersScroll
@onready var offers_pad: MarginContainer = $CenterContainer/Panel/MarginContainer/VBox/OffersScroll/OffersPad
@onready var offers_container: HBoxContainer = $CenterContainer/Panel/MarginContainer/VBox/OffersScroll/OffersPad/OffersContainer
## 陈列行（上阵 + 背包 + 道具）整排在 OwnedScroll 里：满仓 6 上阵 + 9 背包 + 15 道具
## 一共 30 格，任何一档屏都摆不平 ⇒ 槽位先按件数压到 INV_SLOT_MIN，还摆不下就横着滑。
## 竖向禁用滚动：这一行只有一格高，上下滑没有意义，且会把货架的竖向预算再吃掉一条滑条。
@onready var owned_scroll: ScrollContainer = $CenterContainer/Panel/MarginContainer/VBox/OwnedScroll
@onready var owned_container: HBoxContainer = $CenterContainer/Panel/MarginContainer/VBox/OwnedScroll/OwnedContainer
@onready var action_bar: HBoxContainer = $CenterContainer/Panel/MarginContainer/VBox/ActionBar
@onready var reroll_btn: Button = $CenterContainer/Panel/MarginContainer/VBox/BottomBar/RerollButton
@onready var confirm_btn: Button = $CenterContainer/Panel/MarginContainer/VBox/BottomBar/ConfirmButton

## 摆位口径与回合后悟道面板同一把尺子（LevelUpDialog 里同名同形的 *_for()）：
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
## 「货架不许竖滑」不等于「这一屏哪儿都不许滑」：底下那排陈列（上阵 + 背包 + 道具）满仓是
## 6 + 9 + 15 = 30 格，槽位压到 36 见方也要 1400 宽，任何一档屏都摆不平 ⇒ 整排横滑
## （OwnedScroll，竖向禁用）。2026-10-09 用户真机：「装备太多了，可以左右滑动啊，
## 不然很多装备都操作不了了」。两处口径不同的道理在代价上：货架滑一次才能比一次价，比不了；
## 陈列行划一下就把最右那件点到手里，不挡任何决策。
const OFFER_PAD_X := 12.0
## 面板左右固定占位：Panel 内容边距 28×2 + MarginContainer 12×2（与 .tscn 同源）
const CHROME_X := 80.0
## 面板摆位常量已收拢进 ShopCardLayout（SHOP_* / PANEL_* 两档，改口径只动那一份）：
## 面板呼吸量 SCREEN_PAD_Y/PANEL_AIR_X、面板高下限、面板与卡片斜切、卡间缝，见该文件头注。
const CARD_W_MIN := 148.0
const CARD_W_MAX := 220.0
## 卡间缝 SHOP_CARD_GAP_MIN/MAX 已收拢 ShopCardLayout（下同，不再本地声明）

## 卡内摆位：内容边距 6、行距 3、图标 48、价格键 32、锁定角键 36×20。
## 这一组数一起决定「最坏文案下这张卡多高」，判据按现量的数说话（见头注 ③）。
## 左右边距不许再压：卡片是 3° 斜切的平行四边形，260 高时上下各挪出 6.8 单位，
## 边距压到 8 以下文字就贴上画出来的边框线（判据 LayoutCheck 的「离面板画出来的边」那把尺）。
const CARD_PAD_Y := 6.0
const CARD_SEP := 3.0
const CARD_ICON := 48.0
const CARD_PRICE_H := 32.0
const CARD_LOCK_W := 36.0
const CARD_LOCK_H := 20.0
## 入场动画的支点参考高，同时是「卡高的设计上限」：卡高由内容决定，判据量出来最坏 256
## （6 格货架 + 最长那句说明）。滚动区两头的留白按这个上限算，超过它卡角就会被削。
const CARD_H_REF := 280.0
## 陈列槽（上阵/背包/道具）边长的上下限：按件数现算夹在 [52, 60]，压到 52 还摆不下就横滑。
## 2026-10-12 用户真机（第 10 波，6 上阵 + 9 背包 + 13 道具）：「下面这一排武器啊，物品啊，
## 这些图片显示得再大一点，目前都看不清」—— 那一屏件数一多，槽边长早就撞在旧下限 36 上，
## 图标实际只有 34 见方，像素画糊成一团。这一排的竖向代价按【下限】付（件多时才用到），
## 横滑的代价按【上限】付，而它本来就是可滑列表（头注：划一下就把最右那件点到手里），
## 所以两头一起抬：图标 ≥ 44 见方才认得出是刀是剑，宁可多划两下。
const INV_SLOT := 64.0
const INV_SLOT_MIN := 56.0
## 一枚色签（「背包 n/9」「道具 n」）占的宽：最长读数 + 描边与内容边距
const INV_CHIP_W := 96.0
## 陈列行里控件之间的缝隙（与 .tscn 的 OwnedContainer separation 同源）
const INV_GAP := 10.0
## 卡宽下限的来由：货架 6 格（多宝道人 +1）时若把卡压到 132，最长那句说明要折成 7 行，
## 卡高就追不上这一屏给得起的高 ⇒ 宁可让货架横向滑一格（顶栏/陈列行/出战永远在屏内），
## 也不砍文案、不压字号。真机 20:9（设计可视 1202 宽）上 5~6 格都摆得下，压根不用滑。

## 这一档屏高下面板该占的高（与 LevelUpDialog 同源，见 ShopCardLayout）
static func panel_h_for(screen_h: float) -> float:
	return ShopCardLayout.panel_h_for(screen_h, ShopCardLayout.PANEL_MIN_H, ShopCardLayout.PANEL_SCREEN_PAD_Y)

static func skew_x(h: float) -> float:
	return ShopCardLayout.skew_x(ShopCardLayout.SHOP_PANEL_SKEW_RAD, h)

## 滚动区左右要留的白（按卡高上限 CARD_H_REF 算，防斜切角被裁）
static func card_pad_x() -> float:
	return ShopCardLayout.card_pad_x(ShopCardLayout.SHOP_CARD_SKEW_RAD, CARD_H_REF)

## 面板布局盒可用的宽 = 屏幕宽 - 面板左右占位 - 面板两头画出来的斜切 - 两头呼吸量
static func panel_inner_w(screen: Vector2) -> float:
	var bleed: float = skew_x(panel_h_for(screen.y)) + ShopCardLayout.SHOP_PANEL_AIR_X
	return maxf(0.0, screen.x - CHROME_X - bleed * 2.0)

## 一排卡可用的宽 = 面板内容宽 - 滚动区两头的斜切留白（card_pad_x）
static func avail_w(screen: Vector2) -> float:
	return maxf(0.0, panel_inner_w(screen) - card_pad_x() * 2.0)

## 卡间缝隙：宽屏上松一点，窄屏上不抢卡片的宽
static func gap_for(avail: float) -> float:
	return ShopCardLayout.gap_for(avail, 0.014, ShopCardLayout.SHOP_CARD_GAP_MIN, ShopCardLayout.SHOP_CARD_GAP_MAX)

## n 张卡均分可用宽，夹在 [CARD_W_MIN, CARD_W_MAX] 并向下取整防浮点余量唤出横向滑条
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
	return ShopCardLayout.card_inner_w(card_w, OFFER_PAD_X)

## 名号可用的宽 = 卡内宽再让出图标与缝隙（图标与名号同行）。判据按它切名号的硬换行，别处不抄数字。
static func card_name_w(card_w: float) -> float:
	return maxf(48.0, card_inner_w(card_w) - CARD_ICON - 6.0)

## 陈列槽边长：先按件数把这一行压到摆得下（夹在 [INV_SLOT_MIN, INV_SLOT]，与货架卡同一
## 口径、不抄死数）。压到下限还摆不下时（满仓 6 上阵 + 9 背包 + 15 道具 = 30 格，任何一档
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
## 顶栏生命徽记（见 ShopHpChip 头注）：买不买回复道具的依据就印在这一屏
var _hp_chip: ShopHpChip = null
## 顶栏「作者」按钮（仅作者模式可见）
var _author_btn: Button = null
## 暂停键长按作者模式彩蛋的助手句柄（_on_pause_pressed 收口松手用）
var _pause_author_hold: HudAuthorHold = null
## 本次开面板那档屏：卡宽/缝隙/面板高按它现算（与 LevelUpDialog 同一口径，只在打开时量一次）
var _screen: Vector2 = Vector2(960, 540)

## 当前点选的武器：{"pool": "equipped"/"stash", "index": int}
var selected: Dictionary = {}
## 出战确认退场防重入（淡出期间再点不重复 confirm_shop）
var _confirming: bool = false
## 拖拽换装手势控制器（按住拎起 → 拖到目标格放下）：陈列行的格子构建时经 drag_register 登记
var drag_ctl: ShopDragDrop = null

## ShopInventoryRow 静态工厂回调入口：把一格登记成拖拽源/落点（口径见 ShopDragDrop 头注）
func drag_register(node: Control, src: Dictionary) -> void:
	if drag_ctl != null:
		drag_ctl.register_slot(node, src)

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	drag_ctl = ShopDragDrop.new(self)
	drag_ctl.name = "DragDrop"
	add_child(drag_ctl)
	# 卡体登记成「长按键」：面板不是按钮，摇杆认不出 ⇒ 点面板空白处不许在它底下长出摇杆
	panel.add_to_group(DawnJoystick.UI_PRESS_HOLD_GROUP)
	GameStyle.label(stones_label, 17, GameStyle.INK_TEXT)
	GameStyle.label(wave_label, 15, GameStyle.PAPER_DIM)
	GameStyle.button(reroll_btn, GameStyle.NAVY2, GameStyle.LINE, 14, GameStyle.PAPER_DIM)
	GameStyle.button(confirm_btn, GameStyle.GOLD, GameStyle.JADE, 18, GameStyle.INK_TEXT, 6.0, GameStyle.INK_TEXT)
	confirm_btn.text = "出  战"
	# 两排滚动条统一长相：引擎默认那根浅灰与这块深蓝面板不搭（货架摆不平那一档会露出来）
	GameStyle.scrollable(offers_scroll)
	GameStyle.scrollable(owned_scroll)
	# 标题带底色在 .tscn 里烘焙成默认品红，不走 GameStyle 工厂 ⇒ 按当前主题重涂并登记
	var title_band: PanelContainer = $CenterContainer/Panel/MarginContainer/VBox/TopBar/TitleBand
	var tb_sb := title_band.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	tb_sb.bg_color = GameStyle.GOLD
	title_band.add_theme_stylebox_override("panel", tb_sb)
	GameStyle.register_theme_box(tb_sb, &"bg_color", &"main")
	GameManager.shop_opened.connect(_on_shop_opened)
	reroll_btn.pressed.connect(_on_reroll)
	confirm_btn.pressed.connect(_on_confirm)

	# 顶栏右侧添加「属性」与「暂停」按钮，方便随时查看面板或唤出暂停菜单
	var top_bar: HBoxContainer = $CenterContainer/Panel/MarginContainer/VBox/TopBar
	var stats_btn := Button.new()
	stats_btn.name = "StatsButton"
	stats_btn.text = "属 性"
	stats_btn.custom_minimum_size = Vector2(72, 32)
	stats_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(stats_btn, GameStyle.NAVY2, GameStyle.JADE, 13, GameStyle.PAPER, 4.0, GameStyle.INK_TEXT)
	stats_btn.pressed.connect(func(): stats_requested.emit())
	top_bar.add_child(stats_btn)

	var pause_btn := Button.new()
	pause_btn.name = "PauseButton"
	pause_btn.text = "暂 停"
	pause_btn.custom_minimum_size = Vector2(72, 32)
	pause_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(pause_btn, GameStyle.NAVY2, GameStyle.GOLD, 13, GameStyle.PAPER, 4.0, GameStyle.INK_TEXT)
	pause_btn.pressed.connect(_on_pause_pressed)
	top_bar.add_child(pause_btn)
	# 长按 2 秒切作者模式（与战斗 HUD / 首页设置徽章同一彩蛋）：松手那一下由 consume_press 吃掉
	_pause_author_hold = HudAuthorHold.attach(self, pause_btn)

	# 「图鉴」插在「属性」左边：买武器的间隙随时查流派武器总表；
	# 更顺的一条路是点上面羁绊签（如「召唤 (6/5)」）详情卡里的直达按钮（见 _open_shop_synergy_tip）
	var manual_btn := Button.new()
	manual_btn.name = "ManualButton"
	manual_btn.text = "图 鉴"
	manual_btn.custom_minimum_size = Vector2(72, 32)
	manual_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(manual_btn, GameStyle.NAVY2, GameStyle.JADE, 13, GameStyle.PAPER, 4.0, GameStyle.INK_TEXT)
	manual_btn.pressed.connect(func(): manual_requested.emit(""))
	top_bar.add_child(manual_btn)
	top_bar.move_child(manual_btn, stats_btn.get_index())

	# 作者模式按钮：只在作者模式开启时出现，插在「属性」左边
	_author_btn = Button.new()
	_author_btn.name = "AuthorButton"
	_author_btn.text = "作者"
	_author_btn.custom_minimum_size = Vector2(56, 32)
	_author_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(_author_btn, GameStyle.BAD_DK, GameStyle.BAD, 13, GameStyle.CHALK, 4.0)
	_author_btn.pressed.connect(func(): author_requested.emit())
	top_bar.add_child(_author_btn)
	top_bar.move_child(_author_btn, stats_btn.get_index())
	_author_btn.visible = GameManager.author_mode
	if not GameManager.author_mode_changed.is_connected(_on_author_mode_changed):
		GameManager.author_mode_changed.connect(_on_author_mode_changed)

	# 生命徽记插在「金币」左边：这两颗是同一类东西（这一屏上仅有的两个资源读数），
	# 买回气丹要在它们之间来回比 —— 隔成一左一右就得靠记忆算账（见 ShopHpChip 头注）。
	_hp_chip = ShopHpChip.new(self)
	top_bar.add_child(_hp_chip)
	top_bar.move_child(_hp_chip, stones_label.get_parent().get_index())

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
		if not WeaponData.SYNERGIES.has(tag):
			continue
		var chip_lbl: Label = SynergyUI.create_chip(tag, 12, func(c: Control) -> void:
			_open_shop_synergy_tip(tag, c)
		)
		_synergy_box.add_child(chip_lbl)

func _open_shop_synergy_tip(tag: String, anchor: Control) -> void:
	# 详情卡底部给一键直达：跳图鉴武器页并按该流派筛选（DetailTip 会先收卡再回调）
	SynergyUI.open_tip(self, anchor, tag, "", "", [], [
		{"text": "查看该流派武器", "callback": func() -> void: manual_requested.emit(tag)},
	])

## 「怎么用？」：原先钉在货架下方那一整行的操作提示，收进点按可得的详情卡
## （触屏无 hover，说明必须点得到；这一行省下来的竖向预算全给货架）。
func _open_usage_tip() -> void:
	var help_btn: Button = _info_bar.get_node("HelpButton")
	var max_slots: int = GameManager.max_weapon_slots()
	var slot_txt: String = "%d 件（本角色上限）" % max_slots if max_slots < WeaponData.MAX_SLOTS else "%d 件" % max_slots
	var rows: Array = [
		["武器槽", slot_txt, GameStyle.JADE if max_slots < WeaponData.MAX_SLOTS else GameStyle.PAPER],
		["背包格数", "%d 格" % WeaponData.MAX_STASH_SLOTS, GameStyle.PAPER],
		["货架格数", "%d 格" % GameManager.shop_offers.size(), GameStyle.PAPER],
	]
	var notes: Array[String] = [
		"先点中一件武器，才能升星、换装或出售。",
		"格子边框：外框色＝五行，黄框＝可合成，白框＝选中；底部橙红边＝受【元素伤害】加成。",
		"道具与灵兽买错可退：点徽记开详情，【出售】半价回收。",
		"拖动换装：拖到上阵格＝装备，拖到武器上＝替换，拖到背包＝卸下。",
		"三合一：三把同名同星合成升一星（最高 %s）。★1 与 ★2 各算各的。" % WeaponData.star_text(WeaponData.MAX_STAR),
		"第 %d 波起货架偶尔直卖 ★2 成品，价约 ★1 的 %s 倍。" % [
			GameBalance.STAR2_UNLOCK_WAVE, String.num(GameBalance.STAR2_PRICE_MULT, 2)],
		"「锁定」：这格留到下回合，重掷不换。",
		"「重掷」：换一批候选；每回合有免费次数，用完扣金币。",
		"卖掉的格子本回合不补货。",
	]
	if max_slots < WeaponData.MAX_SLOTS:
		notes.insert(0, "本角色限装备 %d 件：超出的收进背包。" % max_slots)
	DetailTip.show_over(self, help_btn, {
		"title": "商店怎么用",
		"chip": "商店",
		"chip_color": GameStyle.GOLD,
		"rows": rows,
		"body": "用金币买武器与道具，多买的收进背包。",
		"notes": notes,
		"foot": "武器槽满再买会自动进背包。",
	})

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		if DetailTip.close_all(self):
			get_viewport().set_input_as_handled()
			return
		pause_requested.emit()
		get_viewport().set_input_as_handled()

func _on_shop_opened() -> void:
	DetailTip.close_all(self)
	# 作者模式可能在商店开着时被关掉：每次开店顺手同步按钮显隐
	if _author_btn != null and is_instance_valid(_author_btn):
		_author_btn.visible = GameManager.author_mode	# 上一次商店会话可能残留拖拽手势（_drag/_press），开店即清，防悬空指针 + 输入吞锁
	if drag_ctl != null:
		drag_ctl._cancel_all()
	selected = {}
	_confirming = false
	_layout_for_viewport()
	refresh()
	visible = true
	get_tree().paused = true
	# 上一回合出战的整根淡出会把根透明度留在 0，这里必须复位；淡入只淡内容层（见 content 注释）
	modulate.a = 1.0
	content.modulate.a = 0.0
	var tw = create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(content, "modulate:a", 1.0, GameStyle.UI_FADE_IN)

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
	# 每次开面板陈列行回到最左：上一波划到哪里不该带到这一回合
	owned_scroll.scroll_horizontal = 0

## animate=false 时卡片直接就位、不重播入场动画：买入一件/切换锁定这类操作型刷新
## 不该把整排卡的注意力拽走（2026-10-10 用户指令优化）；开店与重掷（真换了新货）才播。
func refresh(animate: bool = true) -> void:
	# 整排卡要重建 ⇒ 先收掉还开着的详情卡：卡上印的是刚才那批数，买入/锁定之后就是旧账
	DetailTip.close_all(self)
	# 陈列行会被整批 queue_free 重建：拖拽手势若还挂着旧格子引用，重建后就是悬空指针，
	# 且 _drag 态会在 _input 里持续 set_input_as_handled 吞噬全屏输入。任何 refresh 前先结清。
	if drag_ctl != null:
		drag_ctl._cancel_all()
	_refresh_top_readouts()
	_refresh_synergy_bar()

	for child in offers_container.get_children():
		child.queue_free()
	var offers: Array = GameManager.shop_offers
	var count := offers.size()
	var card_w := offer_card_w(_screen, count)
	offers_container.add_theme_constant_override("separation", offer_separation(_screen))
	# 道具卡「当前→购买后」预览（item_stat_rows）的读数源：一屏只抄一份影子，
	# 整排 before 同源，与悟道 _populate_cards 同构（refresh 重建时状态已定，逐卡现抄也一样，
	# 但一份影子省得每件道具各跑一遍 from_gm）。
	var forecast := StatForecast.open()
	for i in range(count):
		var c: Control = ShopOfferCardFactory.create_card(self, offers[i], i, count, forecast)
		offers_container.add_child(c)
		if not animate:
			continue
		# 统一卡片入场配方（支点/回弹/错峰全在 GameStyle.pop_in 里，布局前调用安全）
		GameStyle.pop_in(c, float(i) * 0.045)

	_refresh_inventory()

## 顶栏读数：金币/波次/生命徽记/重掷键。只改文本与状态、不建节点，所以轻量刷新也照走一遍
## ——「什么变了才刷什么」的分支留在这个函数里，调用点不用各自记得补。
func _refresh_top_readouts() -> void:
	stones_label.text = "金币 %d" % GameManager.spirit_stones
	wave_label.text = "第 %d 波之前 · 购买武器" % (GameManager.wave_number + 1)
	# 生命读数：开店、买入、锁定、重掷后都重画（吞一颗丹下去，这一格当场就该变）
	var hp_stats: Dictionary = GameManager.get_player_stat_dict()
	_hp_chip.set_value(float(hp_stats.get("current_hp", 0.0)), float(hp_stats.get("max_hp", 0.0)))
	if GameManager.reroll_free_left > 0:
		reroll_btn.text = "免费重掷 (剩 %d 次)" % GameManager.reroll_free_left
		reroll_btn.disabled = false
	else:
		reroll_btn.text = "重掷货架 (%d 金币)" % GameManager.reroll_cost
		# 重掷也是一笔要花钱的货：钱不够就转成那颗看得见的灰键（与货架价格键同一条口径），
		# 不许按下去什么也没发生（原先 buy 之外的这条路径静默 return false，连个反馈都没有）
		reroll_btn.disabled = GameManager.spirit_stones < GameManager.reroll_cost

## 只重建陈列行（上阵/御灵/背包/道具/灵兽）：三合一只动武器库存，货架 5 张大卡与报价键
## 都还是原账，整屏重铺纯属白做功。2026-10-25 用户反馈「合成动画还有点卡顿」——
## 迸发帧正好压在这次刷新上，几十个节点的重建（5 张货架卡 + 30 格 + StatForecast 影子）
## 吃掉一帧预算，肉眼就是爆点那一顿。合成改走这条轻量通道，别改回 refresh(false)。
func refresh_owned() -> void:
	DetailTip.close_all(self)
	if drag_ctl != null:
		drag_ctl._cancel_all()
	_refresh_top_readouts()
	_refresh_synergy_bar()
	_refresh_inventory()

## 作者面板改金币/生命后由 Main 调用：顶栏金币、货架价格键（买得起/差 N）、重掷键、
## 生命徽记与回复药卡「这一口回多少」都要按新读数重画。走 refresh(false) 这条既有的
## 「本地状态变了」通道，不重播入场动画；作者面板盖在上面，收掉商店详情卡与拖拽态
## 也不会打断玩家操作。
func refresh_readouts() -> void:
	refresh(false)

## 作者面板发货（买到/清空背包）后由 Main 调用：库存变了，选中态与详情卡指向的都是旧账，
## 先清选中再整屏重铺（不重播入场动画）。
func refresh_inventory() -> void:
	selected = {}
	refresh(false)

# ---------------- 上阵 + 背包栏位 ----------------

func _refresh_inventory() -> void:
	if selected.is_empty():
		DetailTip.close_all(self)
	# 点一件武器会重建整行（选中描边/合成高亮都要重画）：不记着滑到的位置，视野会跳回最左，
	# 刚点的那一格从眼前跑掉 —— 满仓时等于逼玩家每点一次就重新划一遍。
	var keep_x: float = owned_scroll.scroll_horizontal
	for child in owned_container.get_children():
		child.queue_free()

	var summary: Array = GameManager.get_weapons_summary()
	var max_slots: int = GameManager.max_weapon_slots()
	# 上阵区固定摆满上限格数（2026-10-11 用户：没佩戴的也要显示一个空格子在那里）——
	# 格位本身就是容量口径，限件数角色（独臂刀圣 3 格）一眼看出还空几格、还差几件。
	# summary 不会被顶破上限，maxi 只是防御：真超了就全画，不吞件。
	var eq_count: int = maxi(max_slots, summary.size())
	var slot_capped: bool = max_slots < WeaponData.MAX_SLOTS
	# 背包空位画成凹槽提示容量
	var empty_budget: int = clampi(10 - eq_count - GameManager.stash.size(), 0, 3)
	var free_tiles: int = mini(WeaponData.MAX_STASH_SLOTS - GameManager.stash.size(), empty_budget)
	# 槽边长按件数现算，压到下限还摆不下就由 OwnedScroll 横滑（满仓 6 上阵 + 9 背包 + 灵兽徽记 + 道具徽记）
	var n_tile: int = eq_count + GameManager.stash.size() + free_tiles + GameManager.items.size() + GameManager.pets.size()
	var n_chip: int = (2 if slot_capped else 1) + (1 if not GameManager.items.is_empty() else 0) + (1 if not GameManager.pets.is_empty() else 0)
	var tile := inv_slot_for(panel_inner_w(_screen), n_tile, n_chip)
	if slot_capped:
		owned_container.add_child(ShopInventoryRow.create_equipped_cap_chip(summary.size(), max_slots))
	for i in range(eq_count):
		if i < summary.size():
			owned_container.add_child(ShopInventoryRow.create_inv_slot(self, summary[i], i, "equipped", tile))
		else:
			owned_container.add_child(ShopInventoryRow.create_empty_equipped_slot(self, i, tile))
	owned_container.add_child(ShopInventoryRow.create_stash_divider(self))
	for i in range(GameManager.stash.size()):
		owned_container.add_child(ShopInventoryRow.create_inv_slot(self, GameManager.stash[i], i, "stash", tile))
	for i in range(free_tiles):
		owned_container.add_child(ShopInventoryRow.create_empty_stash_slot(self, tile))

	# 已持有随行灵兽陈列：小圆球 + 点按查看详情与出售操作（2026-10-14 用户：灵兽排到道具前面）
	if not GameManager.pets.is_empty():
		owned_container.add_child(ShopInventoryRow.create_pets_divider())
		for pet_id in GameManager.pets:
			owned_container.add_child(ShopInventoryRow.create_pet_chip(self, pet_id, tile))

	# 已持有道具（被动道具）陈列：小图标 + 点按查看说明与【出售】，不参与点选换装那套操作
	if not GameManager.items.is_empty():
		owned_container.add_child(ShopInventoryRow.create_items_divider())
		for item_id in GameManager.items:
			owned_container.add_child(ShopInventoryRow.create_item_chip(self, item_id, tile))

	# 整排都要划得起来：装饰性 STOP 会把「按下」那一拍就地吃掉，卡住多大面积就滑不动多大面积
	# （同一把尺见 GameStyle.swipeable 头注）。这一排的格子已经都不是 Button 了（见
	# ShopInventoryRow.create_inv_slot 头注），所以这里递归一遍 + 构造函数里显式 PASS，两处一起兜住以后加的装饰件。
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

func _refresh_action_bar() -> void:
	for child in action_bar.get_children():
		child.queue_free()
	# 武器详情与操作已收归悬浮菜单（DetailTip），底部横条常驻收起，把高度让给货架
	action_bar.visible = false

## 作者模式开关联动：商店开着时切模式，按钮跟着显隐
func _on_author_mode_changed(_enabled: bool) -> void:
	if _author_btn != null and is_instance_valid(_author_btn):
		_author_btn.visible = GameManager.author_mode

## 暂停键 pressed 收口：长按刚触发过作者模式切换时，这一下松手只做收尾（不开暂停菜单）。
func _on_pause_pressed() -> void:
	if _pause_author_hold != null and _pause_author_hold.consume_press():
		return
	pause_requested.emit()

func _on_reroll() -> void:
	DetailTip.close_all(self)
	GameManager.reroll_shop()
	refresh()

func _on_confirm() -> void:
	if _confirming:
		return
	_confirming = true
	DetailTip.close_all(self)
	# 出战淡出期间不许再有拖拽手势挂着：清掉幽灵与悬停高亮，防淡出回调里 _shop.visible 翻 false 时
	# ShopDragDrop._input 走 _cancel_all 路径与 confirm_shop 竞态
	if drag_ctl != null:
		drag_ctl._cancel_all()
	AudioManager.play_sfx("ui_confirm", 0.9)
	# 淡出后再交回流程（之前是 visible=false 硬切，与进场淡入不对称）
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(self, "modulate:a", 0.0, GameStyle.UI_FADE_OUT)
	tw.tween_callback(func():
		_confirming = false
		visible = false
		GameManager.confirm_shop())
