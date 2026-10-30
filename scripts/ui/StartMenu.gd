class_name StartMenu
extends Control

## P5/dudu-cocos 大色块矩阵风格首页：
##   ① 顶栏贴角级联徽章带（右：快速静音 + 游戏设置）
##   ② 左 1 主方块（Hero「开始游戏」，内嵌 2 档危险度）+ 右 2×2 矩阵大方块
##      —— 2026-10-11 用户：「顶部那个『渡个劫』标题去掉，其他按钮卡片纵向再大一点」
##      ⇒ 大匾标题连它身后那条墨色斜带一起撤掉，省下来的 108 单位竖向空间全给方块长高。
##   ③ 右下角一颗「检查更新」小按钮、左下角一颗「游戏共创」小按钮 —— 各贴屏底一角，不再拉通宽横幅
## 2026-10-28 无限闯关改版：无尽试炼开关下线。2026-10-29 用户要求撤掉卡片右上那枚
## 「◆ 无限闯关」角标（太丑）—— 模式信息不再在首页重复标注，Hero 顶部只剩 PLAY 角签。
## 点「开始游戏」后淡出，交给 CultivatorSelect 选择角色（paused 链不中断）。

signal settings_requested
signal career_requested
signal manual_requested
signal cocreation_requested  ## 游戏共创：主菜单左下角「游戏共创」按钮（Main 接 CoCreateDialog.open）
signal resume_requested  ## 中断续玩：主菜单「继续游戏」按钮（Main.resume_from_save 消费）
signal save_requested  ## 多存档：主菜单「存 档」按钮（Main 打开 SaveManageDialog 管理模式）

const DANGER_NAMES := ["普通", "噩梦"]

## 核心矩阵基准尺寸（960×540 下）。`*_BASE` 是「卡内排版」的起点档：
## 卡片按屏现算的高度高于基准时，多出来的那一截由 `hero_metrics()` / `small_metrics()`
## 摊给字号与键高，基准值只在这一处写死。
const BASE_HERO_W := 348.0
const BASE_SMALL_W := 248.0
const BASE_GAP_HERO := 14.0
const BASE_GAP_COL := 16.0
const ROW_GAP := 14.0
const HERO_H_BASE := 284.0
const SMALL_H_BASE := (HERO_H_BASE - ROW_GAP) / 2.0
const CORNER_BTN_H := 26.0            # 右下角「检查更新」小按钮高

## 卡内基准排版（Hero 柱）
const HERO_SEP_BASE := 7.0            # Hero 内各行间距
const HERO_TITLE_FONT_BASE := 32
const HERO_DANGER_HEAD_FONT_BASE := 11
const HERO_TOP_ROW_H_BASE := 28.0      ## Hero 顶部角签行高（原「无限闯关」角标高，撤标后留作留白）
const DANGER_BTN_H_BASE := 28.0       # 危险度那一排两颗键的高
const DANGER_PAD_BASE := 6.0          # 危险度衬板上下内距
const START_BTN_H_BASE := 42.0        # 底部整条出战主按钮高

## 卡内基准排版（右列 2×2）
const SMALL_SEP_BASE := 4.0
const SMALL_NAME_FONT_BASE := 24
const SMALL_SUB_FONT_BASE := 12
const SMALL_PAD_BASE := 12.0          # 卡片上下内距
## 右侧卡内距与副行行内缝：切副文案的可用宽必须和这里同源，否则量出来是两本账
const ENTRY_PAD_L := 18.0
const ENTRY_PAD_R := 16.0
const ENTRY_ROW_SEP := 6.0

## 竖向这一列怎么贴（2026-10-11 撤掉标题大匾之后重算）。
## 旧写法两段账：① 把「标题 + 矩阵 + 横幅」装进一个 VBox 整组居中 ⇒ 标题被推到 y=82，
##    屏上半截全是空的；② 2026-10-10 改成三段各贴各位（标题贴顶栏、按钮贴右下角）。
## 现在标题没了 ⇒ 顶栏底就是这一列的起算线，矩阵与屏底之间的富余先摊成气口
## （≤BLOCK_GAP_MAX），顶到上限还有富余才让主块长高（≤HERO_H_MAX）。
const TOP_BAR_INSET_TOP := 12.0        # 顶栏带离屏顶
const TOP_BAR_H := 40.0                # 顶栏带高（徽章 36 + 余量）
const CONTENT_TOP_GAP := 14.0          # 顶栏底 → 矩阵可落位区顶
## 右下角那颗检查更新按钮的收边位（2026-10-10 用户：底部通宽横幅「不用搞这么长，保留右下角这一块就可以了」）。
## 底距 26 是按钮与屏底之间的视觉留白（连同 4px 硬影也收在内）。
const CORNER_MARGIN_BOTTOM := 26.0
const CORNER_MARGIN_RIGHT := 34.0
const CORNER_MARGIN_LEFT := 34.0
const FOOT_BAND_H := CORNER_MARGIN_BOTTOM + CORNER_BTN_H   # 矩阵与屏底之间为按钮预留的收边带
const BLOCK_GAP_MAX := 32.0            # 矩阵上/下气口上界，再空就让主块长高
const HERO_H_MAX := 400.0              # 主块长高的封顶：再多只是把空白搬进卡里

var _top_bar: HBoxContainer
var _matrix_host: CenterContainer

# 氛围层（2026-10-29 噩梦皮肤）：背景底色 / 血雨流星 / 四周血朱画框 / 整屏迷雾
var _bg: ColorRect
var _shower: MenuMeteorShower
var _chrome: MenuNightmareChrome
var _fog: MenuNightmareFog
## 上一次套用的难度：吃掉 AuthorPanel「迷雾预览」那种同值重发的 danger_changed
var _last_skin_danger: int = -1

# 顶栏徽章控件
var _sound_badge_btn: Button
var _top_set_btn: Button
var _author_badge_btn: Button

# —— 作者模式入口：右上设置徽章 3 秒内连点 5 次，或长按 2 秒 ——
## 不写存档（GameManager.author_mode 是会话成员），下次启动自然回普通模式。
const AUTHOR_TAP_COUNT := 5
const AUTHOR_TAP_WINDOW := 3.0
const AUTHOR_HOLD_SEC := 2.0           ## 长按进入作者模式的按住秒数
var _author_taps: int = 0
var _author_last_tap_ms: int = 0
var _settings_hold_tween: Tween = null ## 长按倒数计时（运行中即表示「正按住」）
var _settings_hold_fired: bool = false ## 长按已触发：松手那一下 pressed 只做收尾，不再开设置
var _corrupt_save_noted: bool = false   ## 续玩档坏档提示只弹一次（反复回菜单不刷屏）

# Hero 大方块与内部控件
var _hero_card: PanelContainer
var _hero_vbox: VBoxContainer
var _hero_top_row: HBoxContainer    # Hero 顶部角签行（撤掉无限闯关角标后只放 PLAY 签，行高照旧）
var _hero_title: Label
var _hero_tag_mark: Panel             # PLAY 角签左端色标（换肤时重铺血朱）
var _danger_box: PanelContainer
var _danger_vbox: VBoxContainer
var _danger_head_lbl: Label
var _hero_void: Control              # Hero 中间那根吃富余的弹簧（量「卡内空洞」用）
var _danger_buttons: Array[Button] = []
var _hero_start_btn: Button
var _resume_btn: Button
var _save_btn: Button

# 右侧 2×2 大方块与动态副文案
var _small_cards: Array[PanelContainer] = []
var _entry_blocks: Array[Dictionary] = []   # 每块 {card, vbox, name_lbl, sub_lbl, chev, sub_raw, void}
var _career_sub_lbl: Label
var _manual_sub_lbl: Label
var _settings_sub_lbl: Label
var _small_w: float = BASE_SMALL_W          # 右列卡片当前宽（副文案切行与它同源）

# 右下角检查更新按钮（右对齐容器托着，按钮随状态文案自己变宽）
var _update_host: HBoxContainer
var _update_btn: Button
var _update_reset_tween: Tween

# 左下角游戏共创按钮（左对齐容器托着，与检查更新共用底部收边带）
var _cocreate_host: HBoxContainer
var _cocreate_btn: Button

# 入场动效队列
var _anim_blocks: Array[Control] = []

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_responsive()

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_background()
	_build_top_bar()
	_build_center_matrix()
	_layout_responsive()
	_refresh_author_badge()
	# 首帧这一屏的实得尺寸还没定（挂在别的容器里时 size 可能是 0），延一帧再按窗口现算一次
	call_deferred("_layout_responsive")
	UpdateManager.update_available.connect(_on_update_available)
	UpdateManager.no_update_found.connect(_on_no_update_found)
	UpdateManager.check_failed.connect(_on_check_failed)
	SettingsManager.audio_volume_changed.connect(func(_b: StringName, _v: float, _m: bool): _refresh_sound_badge())
	SettingsManager.setting_changed.connect(func(_s: StringName, _k: StringName, _v: Variant): _refresh_dynamic_texts())
	# 作者模式可能在首页之外（局内/结算）被关掉：回首页时徽章要跟当前状态一致
	if not GameManager.author_mode_changed.is_connected(_on_author_mode_changed):
		GameManager.author_mode_changed.connect(_on_author_mode_changed)
	# 难度可能在首页之外被改（作者面板 / 程序化 set_danger）：整套氛围换肤由信号统一接管，
	# 建卡路径已按 _skin() 建好，这里只记一次基准值（用于吃掉同值重发）。
	_last_skin_danger = GameManager.danger_level
	if not GameManager.danger_changed.is_connected(_on_danger_changed):
		GameManager.danger_changed.connect(_on_danger_changed)
	# 换主题色时 GameStyle 注册表会把「登记过」的大卡面 / 角签色标刷回主题色，
	# 夜景（噩梦）必须在这里重新盖一遍夜色，否则整块 Hero 会单独变回主题色。
	if not SettingsManager.theme_color_changed.is_connected(_on_theme_color_changed):
		SettingsManager.theme_color_changed.connect(_on_theme_color_changed)

func _build_background() -> void:
	var k := _skin()

	# 1. 不透明暗底（普通 = 纯黑舞台；噩梦 = 深紫黑 —— 卡片之间的缝全变紫，整屏立刻换气）
	var bg := ColorRect.new()
	bg.name = "BackgroundOverlay"
	bg.color = Color(k["stage"])
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	_bg = bg

	# 2. 装饰层（垫在底色与卡片矩阵之间；headless 判据下不建）
	if DisplayServer.get_name() != "headless":
		_shower = MenuMeteorShower.install(self)
		# 画框只吃屏幕最外沿 6px，而矩阵左右各留 43px / 屏底按钮留 26px ⇒
		# 压在卡片「下面」也照样整圈可见，永远盖不到任何可点控件
		_chrome = MenuNightmareChrome.install(self)
		# 迷雾跟上面两层相反：要压在矩阵之上才算「在屏幕前飘」，
		# 所以先按建层顺序装在这里，等控件全建完再由 _build_center_matrix 末尾提到最上层
		_fog = MenuNightmareFog.install(self)
		if bool(k["night"]):
			_shower.set_nightmare(true, false)
			_chrome.set_nightmare(true, false)
			_fog.set_nightmare(true, false)

## 顶栏贴角级联徽章带（右上声音+设置）
func _build_top_bar() -> void:
	var k := _skin()
	var top_margin := MarginContainer.new()
	top_margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_margin.offset_top = TOP_BAR_INSET_TOP
	top_margin.offset_bottom = TOP_BAR_INSET_TOP + TOP_BAR_H
	top_margin.add_theme_constant_override("margin_right", 28)
	top_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_margin)

	_top_bar = HBoxContainer.new()
	_top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_bar.alignment = BoxContainer.ALIGNMENT_END
	_top_bar.add_theme_constant_override("separation", 10)
	top_margin.add_child(_top_bar)

	# 右簇：声音快切徽章 + 设置徽章
	_sound_badge_btn = _make_badge_button("音效 · 开", Vector2(96, 36),
		Color(k["plate_face"]), Color(k["plate_hover"]), Color(k["sound_text"]),
		Color(k["plate_hover_text"]), _on_sound_toggle_pressed)
	_top_bar.add_child(_sound_badge_btn)

	_top_set_btn = _make_badge_button("设置", Vector2(74, 36),
		Color(k["plate_face"]), Color(k["plate_hover"]), Color(k["plate_text"]),
		Color(k["plate_hover_text"]), _on_top_set_pressed)
	_top_bar.add_child(_top_set_btn)
	_attach_author_hold(_top_set_btn)

func _make_badge_button(text: String, min_sz: Vector2, bg: Color, hover_bg: Color,
		font_col: Color, hover_font_col: Color, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = min_sz
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.focus_mode = Control.FOCUS_NONE
	# hover 面按皮肤给（普通态是主题色彩块 → 亮字压上去对比差，统一翻黑字；噩梦态是血朱 → 骨白）
	GameStyle.button(btn, bg, hover_bg, 13, font_col, GameStyle.SLANT_BAND, hover_font_col)
	btn.pressed.connect(callback)
	return btn

## 中央主区：五块大色块矩阵（顶栏下方起算、上下气口居中）+ 右下角检查更新按钮（贴屏底屏右）
## 两块各挂各的容器，竖向落位由 `_layout_responsive()` 现算 —— 组内缝隙不再决定矩阵高低。
func _build_center_matrix() -> void:
	var k := _skin()
	var faces: Array = k["card_faces"]
	var marks: Array = k["tag_marks"]
	var card_ink: Color = k["card_text"]

	# 1. 五块实底大色块矩阵（左 Hero 整柱 + 右 2×2）
	_matrix_host = CenterContainer.new()
	_matrix_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	_matrix_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_matrix_host)

	var matrix_row := HBoxContainer.new()
	matrix_row.alignment = BoxContainer.ALIGNMENT_CENTER
	matrix_row.add_theme_constant_override("separation", int(BASE_GAP_HERO))
	matrix_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_matrix_host.add_child(matrix_row)

	_hero_card = _build_hero_block()
	matrix_row.add_child(_hero_card)
	_anim_blocks.append(_hero_card)

	var right_grid := VBoxContainer.new()
	right_grid.alignment = BoxContainer.ALIGNMENT_CENTER
	right_grid.add_theme_constant_override("separation", int(ROW_GAP))
	right_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	matrix_row.add_child(right_grid)

	var top_pair := HBoxContainer.new()
	top_pair.add_theme_constant_override("separation", int(BASE_GAP_COL))
	top_pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_grid.add_child(top_pair)

	var bot_pair := HBoxContainer.new()
	bot_pair.add_theme_constant_override("separation", int(BASE_GAP_COL))
	bot_pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_grid.add_child(bot_pair)

	# 右上 1：修仙志（普通态点缀黄块 / 噩梦态暗铜）
	var career_res := _build_entry_block(
		"CAREER", "战 绩", "最高 0 波 · 击杀 0 只",
		Color(faces[0]), card_ink, Color(marks[0]),
		_on_career_pressed
	)
	top_pair.add_child(career_res["card"])
	_small_cards.append(career_res["card"])
	_anim_blocks.append(career_res["card"])
	_career_sub_lbl = career_res["sub_label"]

	# 右上 2：传道玉简（普通态增益绿块 / 噩梦态暗玉）
	var manual_res := _build_entry_block(
		"MANUAL", "图鉴", "70 武器 · 103 道具 · 20 角色",
		Color(faces[1]), card_ink, Color(marks[1]),
		_on_manual_pressed
	)
	top_pair.add_child(manual_res["card"])
	_small_cards.append(manual_res["card"])
	_anim_blocks.append(manual_res["card"])
	_manual_sub_lbl = manual_res["sub_label"]

	# 右下 1：天地律动·设置（普通态纸白块 / 噩梦态暗紫）
	var settings_res := _build_entry_block(
		"CONFIG", "设置", "音效 · 画面 · 震屏设置",
		Color(faces[2]), card_ink, Color(marks[2]),
		_on_settings_pressed
	)
	bot_pair.add_child(settings_res["card"])
	_small_cards.append(settings_res["card"])
	_anim_blocks.append(settings_res["card"])
	_settings_sub_lbl = settings_res["sub_label"]

	# 右下 2：新手指南（普通态元素橙块 / 噩梦态暗炭）
	var guide_res := _build_entry_block(
		"GUIDE", "新手指南", "图文指南 · 随时重温",
		Color(faces[3]), card_ink, Color(marks[3]),
		_on_guide_pressed
	)
	bot_pair.add_child(guide_res["card"])
	_small_cards.append(guide_res["card"])
	_anim_blocks.append(guide_res["card"])

	# 2. 右下角一颗检查更新按钮
	_update_host = HBoxContainer.new()
	_update_host.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_update_host.alignment = BoxContainer.ALIGNMENT_END
	_update_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_update_host)

	_update_btn = Button.new()
	_update_btn.text = "检查更新"
	_update_btn.custom_minimum_size = Vector2(76, CORNER_BTN_H)
	_update_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(_update_btn, Color(k["corner_face"]), Color(k["corner_edge"]), 12,
		Color(k["primary_text"]), GameStyle.SLANT_BUTTON, Color(k["primary_hover_text"]))
	# 状态文案（「已是最新版」「新版 v0.0.17!」）比默认四字长，按钮要贴字自己撑开；
	# 共用 _pad_button_h：换肤重铺按钮后还要再补一遍
	_pad_button_h(_update_btn, 10.0)
	_update_btn.pressed.connect(_on_update_pressed)
	_update_host.add_child(_update_btn)
	_anim_blocks.append(_update_btn)

	# 3. 左下角一颗游戏共创按钮（与检查更新共用底部收边带，左右各贴一边）
	_cocreate_host = HBoxContainer.new()
	_cocreate_host.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_cocreate_host.alignment = BoxContainer.ALIGNMENT_BEGIN
	_cocreate_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cocreate_host)

	_cocreate_btn = Button.new()
	_cocreate_btn.text = "游戏共创"
	_cocreate_btn.custom_minimum_size = Vector2(76, CORNER_BTN_H)
	_cocreate_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(_cocreate_btn, Color(k["corner_face"]), Color(k["corner_edge"]), 12,
		Color(k["primary_text"]), GameStyle.SLANT_BUTTON, Color(k["primary_hover_text"]))
	_cocreate_btn.pressed.connect(_on_cocreate_pressed)
	_cocreate_host.add_child(_cocreate_btn)
	_anim_blocks.append(_cocreate_btn)

	# 4. 迷雾层要压在卡片矩阵之上（底色/流星/画框都在矩阵之下），等控件全部建完再提到最上层
	if _fog != null and is_instance_valid(_fog):
		move_child(_fog, -1)

## 左侧整柱 Hero 大方块：开始游戏 + 2 档危险度
func _build_hero_block() -> PanelContainer:
	var k := _skin()
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(BASE_HERO_W, HERO_H_BASE)
	var sb := GameStyle.block(Color(k["hero_face"]), GameStyle.SLANT_BLOCK, Vector2(6, 7))
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 14.0
	card.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(HERO_SEP_BASE))
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vbox)
	_hero_vbox = vbox

	# 顶部角签行：只留 PLAY 角签（2026-10-29 撤掉右端「◆ 无限闯关」角标，用户嫌丑）。
	# 行高仍按 hero_metrics 的 top_h 撑住 —— 撤角标不该把下面整摞元素往上挪，
	# 那样省下来的 17 单位只会变成「卡内空洞」，把危险度区与出战键之间的绿带拉宽。
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(top_row)
	_hero_top_row = top_row

	var tag_chip := GameStyle.corner_tag("PLAY", Color(k["play_mark"]))
	top_row.add_child(tag_chip)
	_hero_tag_mark = _tag_mark_of(tag_chip)

	var top_spacer := Control.new()
	top_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(top_spacer)

	# 标题行：大标题 + 右侧「存 档」小键。
	# 存档键放这里而不是底部再叠一行 —— Hero 卡竖向预算已排满（底部再塞一键会顶破，
	# 缩 hero_metrics 又会把字号/键高的比例带歪），标题行右侧本来就是空的。
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title_row)

	_hero_title = Label.new()
	_hero_title.text = "开 始 游 戏"
	_hero_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	GameStyle.label(_hero_title, HERO_TITLE_FONT_BASE, Color(k["hero_text"]), 0, GameStyle.INK, true)
	title_row.add_child(_hero_title)

	_save_btn = Button.new()
	_save_btn.text = "存 档"
	_save_btn.custom_minimum_size = Vector2(72, 28)
	_save_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	_save_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_save_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(_save_btn, Color(k["plate_face"]), Color(k["plate_hover"]), 13,
		Color(k["plate_text"]), GameStyle.SLANT_BUTTON, Color(k["plate_hover_text"]))
	_save_btn.pressed.connect(_on_save_pressed)
	title_row.add_child(_save_btn)

	# 危险度选择区（内嵌衬板：普通态纯黑衬板，噩梦态更深并封一道血朱细边）
	_danger_box = PanelContainer.new()
	var d_sb := GameStyle.panel(Color(k["danger_plate"]), GameStyle.SLANT_PLATE, Vector2.ZERO)
	# 1px 边宽建卡时就给足（普通态边框全透明）：换肤只换颜色，绝不让布局抖一下
	d_sb.border_width_left = 1
	d_sb.border_width_top = 1
	d_sb.border_width_right = 1
	d_sb.border_width_bottom = 1
	d_sb.border_color = Color(k["danger_border"])
	d_sb.content_margin_left = 8.0
	d_sb.content_margin_right = 8.0
	d_sb.content_margin_top = DANGER_PAD_BASE
	d_sb.content_margin_bottom = DANGER_PAD_BASE
	_danger_box.add_theme_stylebox_override("panel", d_sb)
	_danger_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_danger_box)

	_danger_vbox = VBoxContainer.new()
	_danger_vbox.add_theme_constant_override("separation", 4)
	_danger_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_danger_box.add_child(_danger_vbox)

	var d_head := HBoxContainer.new()
	d_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_danger_vbox.add_child(d_head)

	var d_lbl := Label.new()
	d_lbl.text = "难度选择"
	GameStyle.label(d_lbl, HERO_DANGER_HEAD_FONT_BASE, Color(k["danger_head"]))
	_danger_head_lbl = d_lbl
	d_head.add_child(d_lbl)

	var d_row := HBoxContainer.new()
	d_row.alignment = BoxContainer.ALIGNMENT_CENTER
	d_row.add_theme_constant_override("separation", 4)
	d_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_danger_vbox.add_child(d_row)

	_danger_buttons.clear()
	for d in range(GameBalance.DANGER_MAX + 1):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(46, DANGER_BTN_H_BASE)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		var dd := d
		btn.pressed.connect(func(): _on_danger_pressed(dd))
		d_row.add_child(btn)
		_danger_buttons.append(btn)

	# 吃富余的弹簧：卡片长高多出来的那一截本该全堆在这里 ⇒ 卡内一大片空洞，
	# 看着像没画完（2026-10-10 定的口径）。现在富余先由 `_layout_responsive()` 摊给
	# 字号/键高/内距，这里只留摊完剩下的那点。
	_hero_void = Control.new()
	_hero_void.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hero_void.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_hero_void)

	# 底部整条出战主按钮
	_hero_start_btn = Button.new()
	_hero_start_btn.text = "开 始 游 戏  》"
	_hero_start_btn.custom_minimum_size = Vector2(0, START_BTN_H_BASE)
	_hero_start_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero_start_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(_hero_start_btn, Color(k["start_face"]), Color(k["start_edge"]), 18,
		Color(k["primary_text"]), GameStyle.SLANT_BUTTON, Color(k["primary_hover_text"]))
	_hero_start_btn.pressed.connect(_on_start_pressed)
	vbox.add_child(_hero_start_btn)

	# 中断续玩：有局内存档时插一条「继续游戏」（点按直达上次的局；文案由存档摘要现取）
	_resume_btn = Button.new()
	_resume_btn.text = "继 续 游 戏  》"
	_resume_btn.custom_minimum_size = Vector2(0, START_BTN_H_BASE * 0.72)
	_resume_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resume_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(_resume_btn, Color(k["plate_face"]), Color(k["resume_hover"]), 14,
		Color(k["plate_text"]), GameStyle.SLANT_BUTTON, Color(k["resume_hover_text"]))
	_resume_btn.pressed.connect(_on_resume_pressed)
	vbox.add_child(_resume_btn)

	_refresh_danger_row()
	return card

## 右列 2×2 实底大色块构建器（整块可点，内置角签、大名号、副文案、右下箭标）
## accent 只喂角签左端那道色标 —— 签面恒为墨黑，字色由 ink_col 显式传（普通态墨字 / 噩梦态骨白）；
## 噩梦态所有卡统一换血朱印记，块字典里同时记下原始 accent 供切回普通时还原。
func _build_entry_block(tag_text: String, title_text: String, sub_text: String,
		face_col: Color, ink_col: Color, accent: Color,
		callback: Callable) -> Dictionary:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(BASE_SMALL_W, SMALL_H_BASE)
	var normal_sb := GameStyle.block(face_col, GameStyle.SLANT_BLOCK, Vector2(5, 6))
	normal_sb.content_margin_left = ENTRY_PAD_L
	normal_sb.content_margin_right = ENTRY_PAD_R
	normal_sb.content_margin_top = SMALL_PAD_BASE
	normal_sb.content_margin_bottom = SMALL_PAD_BASE
	card.add_theme_stylebox_override("panel", normal_sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(SMALL_SEP_BASE))
	card.add_child(vbox)

	# 顶行：英文角签
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 6)
	vbox.add_child(top_row)

	var chip := GameStyle.corner_tag(tag_text, accent)
	top_row.add_child(chip)

	# 中行：大标题
	var name_lbl := Label.new()
	name_lbl.text = title_text
	GameStyle.label(name_lbl, SMALL_NAME_FONT_BASE, ink_col, 0, GameStyle.INK, true)
	vbox.add_child(name_lbl)

	# 吃富余的弹簧（同 Hero 那一根：卡片长高先摊给字号与内距，剩下才归它）
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(sp)

	# 底行：副说明 + 右侧箭标
	var bot_row := HBoxContainer.new()
	bot_row.add_theme_constant_override("separation", int(ENTRY_ROW_SEP))
	vbox.add_child(bot_row)

	var sub_lbl := Label.new()
	sub_lbl.text = sub_text
	sub_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sub_col := GameStyle.with_alpha(ink_col, 0.78)
	GameStyle.label(sub_lbl, SMALL_SUB_FONT_BASE, sub_col)
	bot_row.add_child(sub_lbl)

	var chev_lbl := Label.new()
	chev_lbl.text = "》"
	GameStyle.label(chev_lbl, 16, ink_col, 0, GameStyle.INK, true)
	bot_row.add_child(chev_lbl)

	# 整块热区 + 点按交互 + 悬停微放缩
	GameStyle.hotzone(card)
	GameStyle.tap(card, func():
		AudioManager.play_sfx("ui_click")
		callback.call()
	)
	card.mouse_entered.connect(func():
		card.pivot_offset = card.size * 0.5
		var tw := card.create_tween()
		tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw.tween_property(card, "scale", Vector2(1.02, 1.02), 0.1)
	)
	card.mouse_exited.connect(func():
		card.pivot_offset = card.size * 0.5
		var tw := card.create_tween()
		tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw.tween_property(card, "scale", Vector2.ONE, 0.1)
	)

	var block := {
		"card": card,
		"sub_label": sub_lbl,
		"sub_raw": sub_text,
		"sub_col": sub_col,
		"chev": chev_lbl,
		"vbox": vbox,
		"name_label": name_lbl,
		"void": sp,
		# 换肤用：角签左端色标引用 + 本卡原本的 accent（普通态要能原样退回去）
		"tag_mark": _tag_mark_of(chip),
		"tag_accent": accent,
	}
	_entry_blocks.append(block)
	# 建卡时就按当前列宽切一次：首帧不会把整行塞进卡里等下一次 resize 才收
	_wrap_entry_sub(block)
	return block

## 取 corner_tag 的左端色标引用（结构：chip PanelContainer → row HBox → [色标 Panel, 字 Label]）。
## 换肤要重铺这道标记，但 corner_tag 只返回外层 chip；NightmareMenuCheck 会断言这枚色标
## 真的换了色 —— corner_tag 内部结构若被改动，判据会当场报红，而不是静默失效。
static func _tag_mark_of(chip: Control) -> Panel:
	if chip == null or not is_instance_valid(chip) or chip.get_child_count() == 0:
		return null
	var row := chip.get_child(0)
	if row == null or row.get_child_count() == 0:
		return null
	return row.get_child(0) as Panel

## 副文案统一入口：先记原始文案（含「◆ 新解锁」前缀），再按当前卡宽切硬换行。
## 直接赋 .text 会让 Label 的内容最小宽决定卡宽 —— 长度一变整排矩阵就顶出屏幕
## （2026-10-25 CI 4:3 档：全新存档带前缀时 973 > 960）。
func _set_entry_sub(lbl: Label, raw: String) -> void:
	for blk in _entry_blocks:
		if blk.get("sub_label") == lbl:
			blk["sub_raw"] = raw
			_wrap_entry_sub(blk)
			return
	lbl.text = raw

## 取某张卡当前的原始副文案（不加前缀、不切行），前缀拼接前用它取底
func _entry_sub_raw(lbl: Label) -> String:
	for blk in _entry_blocks:
		if blk.get("sub_label") == lbl:
			return String(blk.get("sub_raw", ""))
	return lbl.text

## 按当前列宽切副文案：可用宽 = 卡宽 − 左右内距 − 行内缝 − 右端箭标。
## 与 _build_entry_block 的排版同一份常量，别在这里另抄数字。
func _wrap_entry_sub(blk: Dictionary) -> void:
	var lbl: Label = blk.get("sub_label") as Label
	if lbl == null or not is_instance_valid(lbl):
		return
	var chev: Label = blk.get("chev") as Label
	var chev_w := 0.0
	if chev != null and is_instance_valid(chev):
		chev_w = chev.get_combined_minimum_size().x
	var inner := _small_w - ENTRY_PAD_L - ENTRY_PAD_R - ENTRY_ROW_SEP - chev_w
	lbl.text = GameStyle.wrap_cjk(String(blk.get("sub_raw", "")),
		GameStyle.body_font(), lbl.get_theme_font_size("font_size"), inner)

## 未读解锁时副文案转强调色，读掉之后要能退回原色（不然颜色会一直留在卡上）
func _tint_entry_sub(lbl: Label, hot: bool) -> void:
	for blk in _entry_blocks:
		if blk.get("sub_label") == lbl:
			var base_col: Color = blk.get("sub_col", GameStyle.PAPER)
			var hot_col: Color = _skin()["hot_text"]
			lbl.add_theme_color_override("font_color", hot_col if hot else base_col)
			return

## 响应式排版：适配 720（4:3）/ 960（16:9）/ 1204（20:9），保证斜切块画出来绝不出屏
func _layout_responsive() -> void:
	var vp := size
	if vp.x <= 0.0 or vp.y <= 0.0:
		if get_viewport() != null:
			vp = get_viewport().get_visible_rect().size
		else:
			vp = Vector2(960, 540)

	# 1. 竖向两段落位：矩阵从顶栏下方起算，检查更新按钮贴右下角。
	#    可落位的富余先摊成上下气口（≤BLOCK_GAP_MAX），气口顶到上限还有富余才让主块长高
	#    （≤HERO_H_MAX）。960×540 这一档：可落位 422 → 气口 32、主块 358（撤标题前 300）。
	var region_top := TOP_BAR_INSET_TOP + TOP_BAR_H + CONTENT_TOP_GAP
	var foot_top := vp.y - FOOT_BAND_H
	var region := foot_top - region_top
	var gap := minf(maxf((region - HERO_H_BASE) / 2.0, 0.0), BLOCK_GAP_MAX)
	var hero_h := clampf(region - 2.0 * gap, HERO_H_BASE, HERO_H_MAX)
	gap = maxf((region - hero_h) / 2.0, 0.0)
	var small_h := (hero_h - ROW_GAP) / 2.0
	if _matrix_host != null and is_instance_valid(_matrix_host):
		_matrix_host.offset_top = region_top + gap
		_matrix_host.offset_bottom = -(vp.y - foot_top + gap)
	if _update_host != null and is_instance_valid(_update_host):
		_update_host.offset_top = -FOOT_BAND_H
		_update_host.offset_bottom = -CORNER_MARGIN_BOTTOM
		_update_host.offset_right = -CORNER_MARGIN_RIGHT
	if _cocreate_host != null and is_instance_valid(_cocreate_host):
		_cocreate_host.offset_left = CORNER_MARGIN_LEFT
		_cocreate_host.offset_top = -FOOT_BAND_H
		_cocreate_host.offset_bottom = -CORNER_MARGIN_BOTTOM

	# 2. 按可视宽度计算方块矩阵缩放因子（预留左右 48px 给斜切外扩与安全边距）
	var base_total_w := BASE_HERO_W + BASE_GAP_HERO + BASE_SMALL_W * 2.0 + BASE_GAP_COL
	var avail_w := maxf(640.0, vp.x - 48.0)
	var f := clampf(avail_w / base_total_w, 0.74, 1.15)
	if absf(f - 1.0) < 0.03:
		f = 1.0

	var hero_w := roundf(BASE_HERO_W * f)
	var small_w := roundf(BASE_SMALL_W * f)
	_small_w = small_w

	if _hero_card != null and is_instance_valid(_hero_card):
		_hero_card.custom_minimum_size = Vector2(hero_w, hero_h)
	for sc in _small_cards:
		if is_instance_valid(sc):
			sc.custom_minimum_size = Vector2(small_w, small_h)
	_apply_hero_metrics(hero_h, hero_w)
	_apply_small_metrics(small_h)

## 卡高 → 卡内各件尺寸（纯函数，量尺直接喂数读比例，不抄第二份表）。
## 为什么要有这一摊：撤掉标题大匾省出 108 单位竖向空间，全给卡片长高的话，多出来的那一截
## 会被 VBox 里那根 expanding 弹簧一口吃掉 ⇒ 卡片中间出现一大片什么都没有的空洞
## （2026-10-10 用户已否过一次「竖向空白会被当 bug」）。所以富余先按这一组系数摊给字号、
## 键高与卡内距，各档上限就是「再大就顶破这一格」的量。
static func hero_metrics(hero_h: float) -> Dictionary:
	var extra := maxf(hero_h - HERO_H_BASE, 0.0)
	return {
		"sep": clampf(HERO_SEP_BASE + extra * 0.07, HERO_SEP_BASE, 12.0),
		"title_font": clampi(HERO_TITLE_FONT_BASE + int(extra * 0.06), HERO_TITLE_FONT_BASE, 38),
		# 顶部角签行高：原本由「无限闯关」角标撑起（2026-10-29 该角标已撤），
		# 公式与上限原样保留给这一行当纯留白，保证下面元素的位置与撤标前逐像素一致。
		"top_h": clampf(HERO_TOP_ROW_H_BASE + extra * 0.10, HERO_TOP_ROW_H_BASE, 36.0),
		"danger_h": clampf(DANGER_BTN_H_BASE + extra * 0.12, DANGER_BTN_H_BASE, 40.0),
		"danger_pad": clampf(DANGER_PAD_BASE + extra * 0.06, DANGER_PAD_BASE, 11.0),
		"danger_head_font": clampi(HERO_DANGER_HEAD_FONT_BASE + int(extra * 0.03),
			HERO_DANGER_HEAD_FONT_BASE, 13),
		"start_h": clampf(START_BTN_H_BASE + extra * 0.20, START_BTN_H_BASE, 58.0),
	}

static func small_metrics(small_h: float) -> Dictionary:
	var extra := maxf(small_h - SMALL_H_BASE, 0.0)
	return {
		"sep": clampf(SMALL_SEP_BASE + extra * 0.10, SMALL_SEP_BASE, 9.0),
		"name_font": clampi(SMALL_NAME_FONT_BASE + int(extra * 0.10), SMALL_NAME_FONT_BASE, 30),
		"sub_font": clampi(SMALL_SUB_FONT_BASE + int(extra * 0.05), SMALL_SUB_FONT_BASE, 14),
		"pad_y": clampf(SMALL_PAD_BASE + extra * 0.16, SMALL_PAD_BASE, 22.0),
	}

## 把 hero_metrics 落到节点上。字号只改 font_size 这一条 override（颜色与字体仍留在
## 建卡时那一次 GameStyle.label 里），避免排版刷新顺手把取色口径改写一遍。
func _apply_hero_metrics(hero_h: float, hero_w: float) -> void:
	if _hero_vbox == null or not is_instance_valid(_hero_vbox):
		return
	var m := hero_metrics(hero_h)
	_hero_vbox.add_theme_constant_override("separation", int(m["sep"]))
	if _hero_top_row != null and is_instance_valid(_hero_top_row):
		_hero_top_row.custom_minimum_size = Vector2(0, float(m["top_h"]))
	_hero_title.add_theme_font_size_override("font_size", int(m["title_font"]))
	_danger_head_lbl.add_theme_font_size_override("font_size", int(m["danger_head_font"]))
	var d_sb := _danger_box.get_theme_stylebox("panel") as StyleBoxFlat
	if d_sb != null:
		d_sb.content_margin_top = float(m["danger_pad"])
		d_sb.content_margin_bottom = float(m["danger_pad"])
	_hero_start_btn.custom_minimum_size = Vector2(0, float(m["start_h"]))
	for btn in _danger_buttons:
		if is_instance_valid(btn):
			btn.custom_minimum_size = Vector2(
				maxf(34.0, floorf((hero_w - 64.0) / 6.0)), float(m["danger_h"]))

func _apply_small_metrics(small_h: float) -> void:
	var m := small_metrics(small_h)
	for blk in _entry_blocks:
		# 先验活再转类型：freed 实例直接赋给类型化变量会当场把这段脚本打断
		# （#40 金币阁拖拽踩过同一格），而这里每帧排版都要跑一遍。
		if not is_instance_valid(blk["card"]):
			continue
		var card: PanelContainer = blk["card"]
		var vbox: VBoxContainer = blk["vbox"]
		vbox.add_theme_constant_override("separation", int(m["sep"]))
		(blk["name_label"] as Label).add_theme_font_size_override("font_size", int(m["name_font"]))
		(blk["sub_label"] as Label).add_theme_font_size_override("font_size", int(m["sub_font"]))
		# 字号变了，副文案的可用宽也要按新字号重切（否则字变大后仍按旧行宽摆）
		_wrap_entry_sub(blk)
		var sb := card.get_theme_stylebox("panel") as StyleBoxFlat
		if sb != null:
			sb.content_margin_top = float(m["pad_y"])
			sb.content_margin_bottom = float(m["pad_y"])

# ---------------- 氛围换肤（按难度） ----------------

## 当前首页氛围调色板（唯一真话源）：
## 2026-10-30 调整：响应用户反馈，噩梦模式下卡片不再变色（保持原汁原味的高级撞色与墨字），
## 氛围感全量转移给「迷雾层 + 暗角煞气 + 深紫夜空 + 血雨流星 + 四周血朱画框」，
## 危险度 chip 保持明确选中态。
func _skin() -> Dictionary:
	if GameManager.danger_level < 1:
		return {
			"night": false,
			"stage": GameStyle.INK,
			"hero_face": GameStyle.GOLD,
			"hero_text": GameStyle.INK_TEXT,
			"start_face": GameStyle.JADE,
			"start_edge": GameStyle.JADE_EDGE,
			"corner_face": GameStyle.GOLD,
			"corner_edge": GameStyle.GOLD_EDGE,
			"primary_text": GameStyle.INK_TEXT,
			"primary_hover_text": GameStyle.INK_TEXT,
			"plate_face": GameStyle.NAVY2,
			"plate_text": GameStyle.PAPER,
			"plate_hover": GameStyle.GOLD,
			"plate_hover_text": GameStyle.INK_TEXT,
			"resume_hover": GameStyle.JADE,
			"resume_hover_text": GameStyle.PAPER,
			"sound_text": GameStyle.JADE_DK,
			"danger_plate": GameStyle.with_alpha(Color.BLACK, 0.82),
			"danger_border": Color(0, 0, 0, 0),
			"danger_head": GameStyle.with_alpha(GameStyle.CHALK, 0.75),
			"chip_on": GameStyle.JADE,
			"chip_on_hover": GameStyle.JADE,
			"chip_on_text": GameStyle.INK_TEXT,
			"chip_off": GameStyle.NAVY2,
			"chip_off_hover": GameStyle.LINE,
			"chip_off_text": GameStyle.PAPER_DIM,
			"card_faces": [GameStyle.JADE, GameStyle.GOOD, GameStyle.NAVY2, GameStyle.ELEMENT],
			"tag_marks": [GameStyle.JADE, GameStyle.GOOD, GameStyle.GOLD, GameStyle.ELEMENT],
			"play_mark": GameStyle.GOLD,
			"card_text": GameStyle.INK_TEXT,
			"card_sub": GameStyle.with_alpha(GameStyle.INK_TEXT, 0.78),
			"hot_text": GameStyle.JADE_DK,
		}
	return {
		"night": true,
		"stage": GameStyle.NIGHT_STAGE,
		# 卡片全量保持原色与墨字，不施加暗沉夜色
		"hero_face": GameStyle.GOLD,
		"hero_text": GameStyle.INK_TEXT,
		"start_face": GameStyle.JADE,
		"start_edge": GameStyle.JADE_EDGE,
		"corner_face": GameStyle.GOLD,
		"corner_edge": GameStyle.GOLD_EDGE,
		"primary_text": GameStyle.INK_TEXT,
		"primary_hover_text": GameStyle.INK_TEXT,
		"plate_face": GameStyle.NAVY2,
		"plate_text": GameStyle.PAPER,
		"plate_hover": GameStyle.GOLD,
		"plate_hover_text": GameStyle.INK_TEXT,
		"resume_hover": GameStyle.JADE,
		"resume_hover_text": GameStyle.PAPER,
		"sound_text": GameStyle.JADE_DK,
		# 危险度控制区：选中的「噩梦」呈现醒目血朱，机制提示行红调高亮
		"danger_plate": GameStyle.with_alpha(Color.BLACK, 0.82),
		"danger_border": GameStyle.with_alpha(GameStyle.NIGHT_SEAL, 0.6),
		"danger_head": GameStyle.with_alpha(GameStyle.NIGHT_SEAL_EDGE, 0.95),
		"chip_on": GameStyle.NIGHT_SEAL,
		"chip_on_hover": GameStyle.NIGHT_SEAL_EDGE,
		"chip_on_text": GameStyle.CHALK,
		"chip_off": GameStyle.NAVY2,
		"chip_off_hover": GameStyle.LINE,
		"chip_off_text": GameStyle.PAPER_DIM,
		"card_faces": [GameStyle.JADE, GameStyle.GOOD, GameStyle.NAVY2, GameStyle.ELEMENT],
		"tag_marks": [GameStyle.JADE, GameStyle.GOOD, GameStyle.GOLD, GameStyle.ELEMENT],
		"play_mark": GameStyle.GOLD,
		"card_text": GameStyle.INK_TEXT,
		"card_sub": GameStyle.with_alpha(GameStyle.INK_TEXT, 0.78),
		"hot_text": GameStyle.JADE_DK,
	}

## 把当前难度对应的整套配色铺到已建好的控件上（建卡路径也读 _skin，这里负责「切换」）。
## 颜色按新野兽派口径硬切（见 GameStyle 头注释：颜色/阴影瞬间硬切）；只有舞台底色走补间 ——
## 那是整屏底而不是某块 UI 的态变，渐变不违反「无渐变」口径，也正好给出「天光压下来」的过渡。
func _apply_skin(animate: bool) -> void:
	_last_skin_danger = GameManager.danger_level
	var k := _skin()
	var night: bool = k["night"]

	# 1. 舞台底色（普通 = 纯黑，噩梦 = 深紫黑）
	if _bg != null and is_instance_valid(_bg):
		var stage: Color = k["stage"]
		if animate:
			var bg_tw := create_tween()
			bg_tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			bg_tw.tween_property(_bg, "color", stage, 0.45)
		else:
			_bg.color = stage

	# 2. 氛围层（四周画框 / 血雨流星 / 整屏迷雾）：只补间透明度与配色，不重建任何层
	if _chrome != null and is_instance_valid(_chrome):
		_chrome.set_nightmare(night, animate)
	if _shower != null and is_instance_valid(_shower):
		_shower.set_nightmare(night, animate)
	if _fog != null and is_instance_valid(_fog):
		_fog.set_nightmare(night, animate)

	# 3. Hero 大卡：卡面 / 标题字 / PLAY 色标 / 三颗键
	if _hero_card != null and is_instance_valid(_hero_card):
		_restyle_block(_hero_card, Color(k["hero_face"]), Vector2(6, 7))
	if _hero_title != null and is_instance_valid(_hero_title):
		_hero_title.add_theme_color_override("font_color", Color(k["hero_text"]))
	_restyle_tag_mark(_hero_tag_mark, Color(k["play_mark"]))
	_repaint_button(_hero_start_btn, Color(k["start_face"]), Color(k["start_edge"]),
		Color(k["primary_text"]), Color(k["primary_hover_text"]))
	_repaint_button(_save_btn, Color(k["plate_face"]), Color(k["plate_hover"]),
		Color(k["plate_text"]), Color(k["plate_hover_text"]))
	_repaint_button(_resume_btn, Color(k["plate_face"]), Color(k["resume_hover"]),
		Color(k["plate_text"]), Color(k["resume_hover_text"]))

	# 4. 危险度衬板（1px 边宽建卡时已给足，这里只换底色与边色，布局零抖动）
	if _danger_box != null and is_instance_valid(_danger_box):
		var d_sb := _danger_box.get_theme_stylebox("panel") as StyleBoxFlat
		if d_sb != null:
			d_sb.bg_color = Color(k["danger_plate"])
			d_sb.border_color = Color(k["danger_border"])
	if _danger_head_lbl != null and is_instance_valid(_danger_head_lbl):
		_danger_head_lbl.add_theme_color_override("font_color", Color(k["danger_head"]))

	# 5. 右列 2×2：卡面 / 名字 / 角签色标。色标与副文案底色要回写进块字典 ——
	#    否则「未读高亮退色」会退到建卡那一刻的旧色，换难度后残留。
	var faces: Array = k["card_faces"]
	var marks: Array = k["tag_marks"]
	var card_ink: Color = k["card_text"]
	var card_sub: Color = k["card_sub"]
	for i in range(_entry_blocks.size()):
		var blk: Dictionary = _entry_blocks[i]
		var card: PanelContainer = blk["card"]
		if not is_instance_valid(card):
			continue
		if i < faces.size():
			_restyle_block(card, Color(faces[i]), Vector2(5, 6))
		if i < marks.size():
			blk["tag_accent"] = Color(marks[i])
			_restyle_tag_mark(blk.get("tag_mark") as Panel, Color(marks[i]))
		var name_lbl := blk.get("name_label") as Label
		if name_lbl != null and is_instance_valid(name_lbl):
			name_lbl.add_theme_color_override("font_color", card_ink)
		var chev := blk.get("chev") as Label
		if chev != null and is_instance_valid(chev):
			chev.add_theme_color_override("font_color", card_ink)
		blk["sub_col"] = card_sub

	# 6. 顶栏徽章 + 屏底两颗角按钮
	_refresh_top_badges()
	_refresh_corner_buttons()

	# 7. 难度键 + 动态副文案（顺带把未读高亮与声音徽章按新色重铺一遍）
	_refresh_danger_row()
	_refresh_dynamic_texts()

## 重铺一张实底大色块卡：新建实例（连内距一起搬过去），不就地改旧实例 ——
## 主题色面在 GameStyle 的主题注册表里登记过，就地改会被下一次换主题色刷回去；
## 新实例只要面不是主题色就天然不进注册表。面没变时直接跳过（重复 open 不产垃圾）。
func _restyle_block(card: PanelContainer, face: Color, shadow: Vector2) -> void:
	if card == null or not is_instance_valid(card):
		return
	var old := card.get_theme_stylebox("panel") as StyleBoxFlat
	if old != null and old.bg_color == face:
		return
	var sb := GameStyle.block(face, GameStyle.SLANT_BLOCK, shadow)
	if old != null:
		sb.content_margin_left = old.content_margin_left
		sb.content_margin_right = old.content_margin_right
		sb.content_margin_top = old.content_margin_top
		sb.content_margin_bottom = old.content_margin_bottom
	card.add_theme_stylebox_override("panel", sb)

## 重铺角签左端那道 3px 色标（与 corner_tag 内部同款 panel 参数，只换色不换形）
func _restyle_tag_mark(mark: Panel, accent: Color) -> void:
	if mark == null or not is_instance_valid(mark):
		return
	var old := mark.get_theme_stylebox("panel") as StyleBoxFlat
	if old != null and old.bg_color == accent:
		return
	mark.add_theme_stylebox_override("panel",
		GameStyle.panel(accent, GameStyle.SLANT_BAND, Vector2.ZERO))

## 按 skin 重铺一颗按钮：字号默认沿用当前 override（换肤只改颜色，绝不改排版）。
## 绝不要就地改 GameStyle.button() 返回的 StyleBox —— 那是按色缓存的共享实例，
## 就地改会顺着缓存污染全项目其它界面。
func _repaint_button(btn: Button, face: Color, hover: Color, text: Color, hover_text: Color,
		skew: float = GameStyle.SLANT_BUTTON, font_size: int = -1) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	var fs := font_size if font_size > 0 else btn.get_theme_font_size("font_size")
	GameStyle.button(btn, face, hover, fs, text, skew, hover_text)

## 顶栏设置徽章（声音徽章另走 _refresh_sound_badge，它还要跟静音态）
func _refresh_top_badges() -> void:
	if _top_set_btn == null or not is_instance_valid(_top_set_btn):
		return
	var k := _skin()
	_repaint_button(_top_set_btn, Color(k["plate_face"]), Color(k["plate_hover"]),
		Color(k["plate_text"]), Color(k["plate_hover_text"]), GameStyle.SLANT_BAND)

## 屏底两颗角按钮（检查更新 / 游戏共创）
func _refresh_corner_buttons() -> void:
	var k := _skin()
	_repaint_button(_update_btn, Color(k["corner_face"]), Color(k["corner_edge"]),
		Color(k["primary_text"]), Color(k["primary_hover_text"]))
	_pad_button_h(_update_btn, 10.0)
	_repaint_button(_cocreate_btn, Color(k["corner_face"]), Color(k["corner_edge"]),
		Color(k["primary_text"]), Color(k["primary_hover_text"]))

## 状态文案（「检查更新中...」「新版 v0.0.17!」）比默认四字长，按钮要贴字自己撑开；
## GameStyle.block 不带左右内距，这里补上，否则长文案会顶到斜切边。
## 重铺按钮后必须重补一遍（工厂会换回它自己的缓存实例）。
func _pad_button_h(btn: Button, pad: float) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	for key in ["normal", "hover", "pressed"]:
		var sbs := btn.get_theme_stylebox(StringName(key)) as StyleBoxFlat
		if sbs != null:
			sbs.content_margin_left = pad
			sbs.content_margin_right = pad

## 难度变化：整套氛围换肤（作者面板改难度 / 程序化 set_danger 也会走到这里）。
## 与 _last_skin_danger 比对只为一件事：吃掉 AuthorPanel 迷雾预览那种「同值重发」——
## 那种不该再打一次扫屏与音效。不可见时静默套用，别在后台播声音。
func _on_danger_changed(_new_danger: int) -> void:
	var changed := GameManager.danger_level != _last_skin_danger
	_apply_skin(changed and visible)
	if changed and visible:
		_play_mood_sting(GameManager.danger_level >= 1)

## 换主题色：GameStyle 注册表会把登记过的大卡面 / 角签色标刷回主题色，
## 夜景（噩梦）必须在这里重新盖一遍夜色，否则整块 Hero 会单独变回主题色。
func _on_theme_color_changed(_id: StringName) -> void:
	_apply_skin(false)

## 切难度的手感落点：进噩梦是压低音高的一记魔君低吼 + 一道半透明血带扫屏；
## 回普通只给一声轻确认 + 主题色扫带。颜色本身硬切（项目口径），这一下只当标点。
func _play_mood_sting(enter_night: bool) -> void:
	if enter_night:
		AudioManager.play_sfx("boss_raid", 0.42, 0.78)
		GameStyle.slash_wipe(self, GameStyle.with_alpha(GameStyle.NIGHT_SEAL, 0.5))
	else:
		AudioManager.play_sfx("ui_confirm", 0.9)
		GameStyle.slash_wipe(self, GameStyle.with_alpha(GameStyle.GOLD, 0.45))

# ---------------- 状态刷新 ----------------

func _refresh_danger_row() -> void:
	# 逐级解锁（2026-10-28 改口径）：在上一档难度抵达破境波即解锁下一档 —— 未解锁档位画成锁定态
	# （灰底 + 「×」前缀，点它不切换，按钮 disabled），头部提示行说明解锁条件。
	var k := _skin()
	var top := GameManager.max_danger_unlocked()
	for d in range(_danger_buttons.size()):
		var btn := _danger_buttons[d]
		var unlocked := GameManager.is_danger_unlocked(d)
		btn.disabled = not unlocked
		btn.text = DANGER_NAMES[d] if unlocked else ("×" + DANGER_NAMES[d])
		if d == GameManager.danger_level and unlocked:
			# 选中态 hover 不换浅面：点完指针仍停在键上，换亮边会整块泛白成淡色。
			# 悬停反馈交给硬阴影 (3,4)→(5,6) 硬切；pressed 面由面色压暗派生，点击反馈仍在。
			GameStyle.button(btn, Color(k["chip_on"]), Color(k["chip_on_hover"]), 12,
				Color(k["chip_on_text"]), GameStyle.SLANT_BUTTON)
		elif not unlocked:
			GameStyle.button(btn, GameStyle.INK.lightened(0.06), GameStyle.LINE, 12, GameStyle.GREY, GameStyle.SLANT_BUTTON)
		else:
			GameStyle.button(btn, Color(k["chip_off"]), Color(k["chip_off_hover"]), 12,
				Color(k["chip_off_text"]), GameStyle.SLANT_BUTTON)
	_refresh_danger_hint(top)

## 难度区头部提示：全解锁时只写「难度选择」，还有锁时补一句解锁条件。
## 复用已有的头部标签而不新增一行 —— 首页竖向预算已排满（StartMenuCompositionProbe 量过卡内空洞）。
func _refresh_danger_hint(top: int) -> void:
	if _danger_head_lbl == null or not is_instance_valid(_danger_head_lbl):
		return
	if top >= GameBalance.DANGER_MAX:
		if GameManager.danger_level >= 1:
			_danger_head_lbl.text = "难度选择 · 噩梦：迷雾视野 · 魔君双生 · 强敌凶化"
		else:
			_danger_head_lbl.text = "难度选择 · 普通：适中敌潮，稳步求道"
	else:
		_danger_head_lbl.text = "难度选择 · 在「%s」打到第 %d 波解锁下一档" % [
			DANGER_NAMES[top], GameManager.MILESTONE_WAVE]

func _refresh_sound_badge() -> void:
	if _sound_badge_btn == null or not is_instance_valid(_sound_badge_btn):
		return
	var k := _skin()
	var muted := SettingsManager.is_bus_muted(&"Master")
	if muted:
		_sound_badge_btn.text = "音效 · 关"
		_repaint_button(_sound_badge_btn, GameStyle.BAD_DK, GameStyle.BAD,
			GameStyle.CHALK, GameStyle.CHALK, GameStyle.SLANT_BAND)
	else:
		_sound_badge_btn.text = "音效 · 开"
		_repaint_button(_sound_badge_btn, Color(k["plate_face"]), Color(k["plate_hover"]),
			Color(k["sound_text"]), Color(k["plate_hover_text"]), GameStyle.SLANT_BAND)

func _refresh_dynamic_texts() -> void:
	# 1. 修仙志卡片副行
	if _career_sub_lbl != null and is_instance_valid(_career_sub_lbl):
		var cs := GameManager.career_stats
		var kills := int(cs.get("total_kills", 0))
		var b_wave := int(cs.get("best_wave", 0))
		var runs := int(cs.get("total_runs", 0))
		var career_txt := ""
		if b_wave > 0:
			career_txt = "最高 %d 波 · 击杀 %d · %d 局" % [b_wave, kills, runs]
		else:
			career_txt = "累计击杀 %d 只 · %d 局" % [kills, runs]
		_set_entry_sub(_career_sub_lbl, career_txt)

	# 2. 传道玉简副行（显示已解锁角色/道具数）
	if _manual_sub_lbl != null and is_instance_valid(_manual_sub_lbl):
		var c_cnt := GameManager.unlocked_cultivators.size()
		var i_cnt := GameManager.unlocked_items.size()
		_set_entry_sub(_manual_sub_lbl, "角色 %d/%d · 道具 %d/%d" % [
			c_cnt, CultivatorData.all_ids().size(),
			i_cnt, ItemData.shop_ids().size()
		])

	# 2b. 新解锁角标（2026-10-25）：结算屏发放的解锁在玩家点开对应条目之前一直算「新」。
	# 用副标题前缀而不是新加控件 —— 首页布局是满的，多一个节点就会顶破卡片（LayoutCheck 量过）。
	# 战绩页承载角色，图鉴页承载道具/武器，两处分开报，玩家知道该点哪张卡。
	# 前缀会加长整行 ⇒ 统一走 _set_entry_sub 按卡宽切行（不切就会把矩阵顶出屏）。
	if _career_sub_lbl != null and is_instance_valid(_career_sub_lbl):
		var new_cult := _count_unread_kinds(["cultivator"])
		if new_cult > 0:
			_set_entry_sub(_career_sub_lbl, "◆ 新角色 %d · %s" % [
				new_cult, _entry_sub_raw(_career_sub_lbl)])
		_tint_entry_sub(_career_sub_lbl, new_cult > 0)
	if _manual_sub_lbl != null and is_instance_valid(_manual_sub_lbl):
		var new_gear := _count_unread_kinds(["item", "weapon"])
		if new_gear > 0:
			_set_entry_sub(_manual_sub_lbl, "◆ 新解锁 %d · %s" % [
				new_gear, _entry_sub_raw(_manual_sub_lbl)])
		_tint_entry_sub(_manual_sub_lbl, new_gear > 0)

	# 3. 天地律动设置副行
	if _settings_sub_lbl != null and is_instance_valid(_settings_sub_lbl):
		var vol := int(round(SettingsManager.get_bus_volume(&"Master") * 100.0))
		var muted := SettingsManager.is_bus_muted(&"Master")
		var vol_str := "静音" if muted else ("音量 %d%%" % vol)
		_set_entry_sub(_settings_sub_lbl, "%s · 震屏「%s」" % [
			vol_str, SettingsManager.shake_level_label()])

	_refresh_sound_badge()

## 数一数未读解锁里属于指定类型（cultivator/item/weapon）的条数。
## 未读标记的 key 形如 "item:pojia_zhui"，只比对冒号前那段。
func _count_unread_kinds(kinds: Array) -> int:
	var n := 0
	for key in GameManager.unread_unlocks:
		var kind := String(key).get_slice(":", 0)
		if kind in kinds:
			n += 1
	return n

# ---------------- 打开 / 关闭与入场动效 ----------------

func open() -> void:
	var parent_node = get_parent()
	if parent_node != null:
		var backdrop = parent_node.get_node_or_null("StageBackdrop")
		if backdrop != null:
			# 菜单显示期间让纯黑幕布常驻：既消除开局淡入时透过半透明菜单露出战场的闪现，
			# 也保证从结算页返回菜单时背景仍是纯黑。选人链路会自行接管其显隐。
			backdrop.visible = true
		var hud = parent_node.get_node_or_null("GameHUD")
		if hud != null:
			hud.visible = false
		var joy = parent_node.get_node_or_null("VirtualJoystick")
		if joy != null:
			joy.visible = false
	# 坏档可见化（2026-10-24）：进度档读坏（autoload 期暂存）在这里补弹 toast；
	# 续玩档「文件在但摘要解析不出」原先表现为按钮默默消失，玩家无从得知，一并提示。
	# 一次性闸：同一次进程里坏档提示只弹一回，反复回菜单不刷屏。
	if GameManager.pending_load_alert != "":
		UpdateManager.show_toast(GameManager.pending_load_alert, GameStyle.BAD, 3.5)
		GameManager.pending_load_alert = ""
	elif not _corrupt_save_noted and RunSave.peek_summary().is_empty() \
			and FileAccess.file_exists(RunSave.SAVE_PATH):
		_corrupt_save_noted = true
		UpdateManager.show_toast("◆ 上局存档损坏，无法继续 ◆", GameStyle.BAD, 3.5)
	# 中断续玩：按存档有无决定「继续游戏」按钮的显隐与文案（无档藏按钮不留空位）
	if _resume_btn != null and is_instance_valid(_resume_btn):
		var summary := RunSave.peek_summary()
		_resume_btn.visible = not summary.is_empty()
		if not summary.is_empty():
			var cid := String(summary.get("cid", ""))
			var c_name := String(CultivatorData.get_def(cid).get("name", "修士"))
			_resume_btn.text = "继续游戏 · %s第%d波  》" % [c_name, int(summary.get("wave", 1))]
	_layout_responsive()
	# 整套氛围按当前难度静默重铺：从噩梦局回菜单时首帧就是夜色，不会先闪一帧普通配色
	_apply_skin(false)
	visible = true
	modulate.a = 0.0
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(self, "modulate:a", 1.0, 0.22)

	await get_tree().process_frame
	if not is_inside_tree():
		return

	var idx := 0
	for blk in _anim_blocks:
		if not is_instance_valid(blk):
			continue
		blk.pivot_offset = blk.size * 0.5
		blk.scale = Vector2(0.85, 0.85)
		blk.modulate.a = 0.0
		var btw := blk.create_tween().set_parallel(true)
		btw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		var delay := 0.12 + float(idx) * 0.05
		btw.tween_property(blk, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(delay)
		btw.tween_property(blk, "modulate:a", 1.0, 0.16).set_delay(delay)
		idx += 1

func close() -> void:
	if not visible:
		return
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(self, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func(): visible = false)

# ---------------- 事件回调 ----------------

func _on_danger_pressed(d: int) -> void:
	# 只改状态：难度键高亮 / 提示行 / 整套氛围换肤统一由 danger_changed 接管
	# （点未解锁档位时按钮 disabled 不可达；点已选档位时值不变、信号不发，也就无需重绘）
	GameManager.set_danger(d)

## 多存档：打开存档管理弹窗（查看/读档/删除），首页留在遮罩后不淡出
## —— 与「修仙志 / 图鉴 / 游戏共创」同一交互。
func _on_save_pressed() -> void:
	save_requested.emit()

## 中断续玩：淡出菜单后通知 Main 按存档重建整局（Main.resume_from_save）
func _on_resume_pressed() -> void:
	AudioManager.play_sfx("ui_confirm", 0.95)
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(self, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func():
		visible = false
		resume_requested.emit()
	)

func _on_sound_toggle_pressed() -> void:
	SettingsManager.toggle_bus_muted(&"Master")
	_refresh_sound_badge()
	_refresh_dynamic_texts()

func _on_start_pressed() -> void:
	AudioManager.play_sfx("ui_confirm", 0.95)
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(self, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func():
		visible = false
		# 新手指南：没勾「下次不弹出」就在选角前弹一次（每次开局都弹），关闭后再进选角
		if _auto_show_tutorial():
			var tut := get_parent().get_node_or_null("TutorialDialog")
			# one-shot：现在指南每局都弹，常驻连接会让后面任何一次关闭（含主菜单/设置页
			# 手动翻开）都再跳一次选角，且第二次 connect 同_callable 会被引擎报错拒绝
			tut.closed.connect(_after_tutorial, CONNECT_DEFERRED | CONNECT_ONE_SHOT)
			tut.open()
			return
		_after_tutorial()
	)

## 开局自动弹新手指南的门控：只看玩家偏好（勾过「下次不弹出」= SettingsManager.tutorial_muted
## = true 才不弹）。判定抽成函数是给 TutorialGateCheck 直接调的，别在测试里另抄一份条件。
## 手动入口（主菜单「新手指南」/设置页底部按钮）不受这条门控影响。
func _auto_show_tutorial() -> bool:
	var tut := get_parent().get_node_or_null("TutorialDialog")
	return tut != null and not SettingsManager.tutorial_muted()

func _after_tutorial() -> void:
	# 「〈 返 回」= 反悔退出：回主菜单，不进选角。标记读一次即清，避免下一次关闭误判。
	var tut := get_parent().get_node_or_null("TutorialDialog")
	if tut != null and bool(tut.get("left_via_back")):
		tut.set("left_via_back", false)
		open()
		return
	var cult_select := get_parent().get_node_or_null("CultivatorSelect")
	if cult_select != null:
		cult_select.show_select()
	else:
		var weapon_select := get_parent().get_node_or_null("StartWeaponSelect")
		if weapon_select != null:
			weapon_select.show_select()

## 游戏共创：交给 Main 打开 CoCreateDialog（首页不直接持有弹窗，沿用信号接线约定）
func _on_cocreate_pressed() -> void:
	cocreation_requested.emit()

func _on_update_pressed() -> void:
	if not is_instance_valid(_update_btn):
		return
	if not UpdateManager.pending_update.is_empty():
		UpdateManager.show_update_dialog(UpdateManager.pending_update)
		return
	if UpdateManager.is_checking:
		_cancel_reset_timer()
		_update_btn.text = "检查更新中..."
		UpdateManager.check_for_update(true)
		UpdateManager.show_toast("正在检查最新版本，请稍候...", GameStyle.GOLD)
		return

	_cancel_reset_timer()
	_update_btn.text = "检查更新中..."
	UpdateManager.check_for_update(true)

func _on_update_available(info: Dictionary) -> void:
	if not is_instance_valid(_update_btn):
		return
	_cancel_reset_timer()
	_update_btn.text = "新版 %s!" % info.get("tag_name", "")

func _on_no_update_found() -> void:
	if not is_instance_valid(_update_btn):
		return
	_cancel_reset_timer()
	_update_btn.text = "已是最新版"
	_update_reset_tween = create_tween()
	_update_reset_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_update_reset_tween.tween_interval(2.5)
	_update_reset_tween.tween_callback(func():
		if is_instance_valid(_update_btn):
			_update_btn.text = "检查更新"
	)

func _on_check_failed(_err_msg: String) -> void:
	if not is_instance_valid(_update_btn):
		return
	_cancel_reset_timer()
	_update_btn.text = "检查失败"
	_update_reset_tween = create_tween()
	_update_reset_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_update_reset_tween.tween_interval(2.5)
	_update_reset_tween.tween_callback(func():
		if is_instance_valid(_update_btn):
			_update_btn.text = "检查更新"
	)

func _cancel_reset_timer() -> void:
	if _update_reset_tween != null and _update_reset_tween.is_valid():
		_update_reset_tween.kill()
		_update_reset_tween = null

func _on_settings_pressed() -> void:
	# 作者模式入口：连点计数。满 5 次在 3 秒窗口内即切换开关，不再弹设置面板。
	if _count_author_tap():
		return
	settings_requested.emit()

## 右上设置徽章专属的 pressed 收口：长按刚触发过作者模式切换时，
## 这一下松手只做收尾（不开设置、不计连点），否则按满 3 秒还会再弹设置面板。
func _on_top_set_pressed() -> void:
	if _settings_hold_fired:
		_settings_hold_fired = false
		return
	_on_settings_pressed()

## 连点计数：返回 true 表示这一下已消费为作者模式切换（调用方不要再开设置）。
## 用真实毫秒而不是帧数：低帧设备上连点间隔不该被帧率放大。
func _count_author_tap() -> bool:
	var now := Time.get_ticks_msec()
	if _author_taps > 0 and now - _author_last_tap_ms > int(AUTHOR_TAP_WINDOW * 1000.0):
		_author_taps = 0
	_author_last_tap_ms = now
	_author_taps += 1
	if _author_taps < AUTHOR_TAP_COUNT:
		return false
	_trigger_author_toggle()
	return true

## 连点满 5 次与长按满 5 秒的共同落点：切换作者模式并广播提示。
## 连点计数一并清零，长按后的松手不会把旧计数带进下一次窗口。
func _trigger_author_toggle() -> void:
	_author_taps = 0
	GameManager.set_author_mode(not GameManager.author_mode)
	GameManager.announcement_triggered.emit(
		"◆ 作者模式已开启 ◆" if GameManager.author_mode else "作者模式已关闭")
	AudioManager.play_sfx("ui_confirm", 0.9)

## 长按入口接线：按住满 AUTHOR_HOLD_SEC 秒切换作者模式。
## 刻意零视觉反馈（不动文案不动色）——入口是隐藏彩蛋，按住过程不能给旁人任何提示；
## 滑出徽章即作废（mouse_exited 杀计时），松开恢复正常点按。
func _attach_author_hold(btn: Button) -> void:
	btn.button_down.connect(_on_settings_hold_down)
	btn.button_up.connect(_on_settings_hold_up)
	btn.mouse_exited.connect(_on_settings_hold_leave)

func _on_settings_hold_down() -> void:
	_settings_hold_fired = false
	_cancel_settings_hold()
	if _top_set_btn == null or not is_instance_valid(_top_set_btn):
		return
	var tw := create_tween()
	_settings_hold_tween = tw
	tw.tween_interval(AUTHOR_HOLD_SEC)
	tw.tween_callback(_on_settings_hold_complete)

func _on_settings_hold_up() -> void:
	_cancel_settings_hold()

func _on_settings_hold_leave() -> void:
	if _settings_hold_tween != null and _settings_hold_tween.is_valid():
		_cancel_settings_hold()

func _on_settings_hold_complete() -> void:
	_settings_hold_tween = null
	_settings_hold_fired = true
	_trigger_author_toggle()

func _cancel_settings_hold() -> void:
	if _settings_hold_tween != null and _settings_hold_tween.is_valid():
		_settings_hold_tween.kill()
	_settings_hold_tween = null

## 首页顶栏作者徽章：开启时显示，作为状态提示（同时是关闭入口的视觉锚点）
func _refresh_author_badge() -> void:
	if _top_bar == null or not is_instance_valid(_top_bar):
		return
	if _author_badge_btn == null or not is_instance_valid(_author_badge_btn):
		_author_badge_btn = _make_badge_button("作者模式", Vector2(92, 36),
			GameStyle.BAD_DK, GameStyle.BAD, GameStyle.CHALK, GameStyle.INK_TEXT, _on_author_badge_pressed)
		_top_bar.add_child(_author_badge_btn)
		_top_bar.move_child(_author_badge_btn, 0)
	_author_badge_btn.visible = GameManager.author_mode

func _on_author_badge_pressed() -> void:
	GameManager.set_author_mode(false)
	GameManager.announcement_triggered.emit("作者模式已关闭")

func _on_author_mode_changed(_enabled: bool) -> void:
	_refresh_author_badge()

func _on_career_pressed() -> void:
	career_requested.emit()

func _on_manual_pressed() -> void:
	manual_requested.emit()

func _on_guide_pressed() -> void:
	# 手动重温新手指南：不受「下次不弹出」偏好影响，关闭后留在主菜单
	var tut := get_parent().get_node_or_null("TutorialDialog")
	if tut != null:
		tut.open()
