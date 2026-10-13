class_name StartMenu
extends Control

## P5/dudu-cocos 大色块矩阵风格首页：
##   ① 顶栏贴角级联徽章带（右：快速静音 + 游戏设置）
##   ② 左 1 主方块（Hero「开始渡劫」，内嵌 6 档危险度与「无尽试炼」直通开关）+ 右 2×2 矩阵大方块
##      —— 2026-10-11 用户：「顶部那个『渡个劫』标题去掉，其他按钮卡片纵向再大一点」
##      ⇒ 大匾标题连它身后那条墨色斜带一起撤掉，省下来的 108 单位竖向空间全给方块长高。
##   ③ 右下角一颗「检查更新」小按钮 —— 贴屏底贴屏右，不再拉通宽横幅
## 点「开始渡劫」后淡出，交给 CultivatorSelect 选择角色（paused 链不中断）。

signal settings_requested
signal career_requested
signal manual_requested

const DANGER_NAMES := ["简单", "普通", "困难", "噩梦", "地狱", "极限"]

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
const ENDLESS_BTN_H_BASE := 28.0
const DANGER_BTN_H_BASE := 28.0       # 危险度那一排六颗键的高
const DANGER_PAD_BASE := 6.0          # 危险度衬板上下内距
const START_BTN_H_BASE := 42.0        # 底部整条出战主按钮高

## 卡内基准排版（右列 2×2）
const SMALL_SEP_BASE := 4.0
const SMALL_NAME_FONT_BASE := 24
const SMALL_SUB_FONT_BASE := 12
const SMALL_PAD_BASE := 12.0          # 卡片上下内距

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
const FOOT_BAND_H := CORNER_MARGIN_BOTTOM + CORNER_BTN_H   # 矩阵与屏底之间为按钮预留的收边带
const BLOCK_GAP_MAX := 32.0            # 矩阵上/下气口上界，再空就让主块长高
const HERO_H_MAX := 400.0              # 主块长高的封顶：再多只是把空白搬进卡里

var _top_bar: HBoxContainer
var _matrix_host: CenterContainer

# 顶栏徽章控件
var _sound_badge_btn: Button
var _top_set_btn: Button

# Hero 大方块与内部控件
var _hero_card: PanelContainer
var _hero_vbox: VBoxContainer
var _hero_title: Label
var _danger_box: PanelContainer
var _danger_vbox: VBoxContainer
var _danger_head_lbl: Label
var _hero_void: Control              # Hero 中间那根吃富余的弹簧（量「卡内空洞」用）
var _danger_buttons: Array[Button] = []
var _endless_btn: Button
var _hero_start_btn: Button

# 右侧 2×2 大方块与动态副文案
var _small_cards: Array[PanelContainer] = []
var _entry_blocks: Array[Dictionary] = []   # 每块 {card, vbox, name_lbl, sub_lbl, void}
var _career_sub_lbl: Label
var _manual_sub_lbl: Label
var _settings_sub_lbl: Label

# 右下角检查更新按钮（右对齐容器托着，按钮随状态文案自己变宽）
var _update_host: HBoxContainer
var _update_btn: Button
var _update_reset_tween: Tween

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
	# 首帧这一屏的实得尺寸还没定（挂在别的容器里时 size 可能是 0），延一帧再按窗口现算一次
	call_deferred("_layout_responsive")
	UpdateManager.update_available.connect(_on_update_available)
	UpdateManager.no_update_found.connect(_on_no_update_found)
	UpdateManager.check_failed.connect(_on_check_failed)
	SettingsManager.audio_volume_changed.connect(func(_b: StringName, _v: float, _m: bool): _refresh_sound_badge())
	SettingsManager.setting_changed.connect(func(_s: StringName, _k: StringName, _v: Variant): _refresh_dynamic_texts())

func _build_background() -> void:
	# 1. 纯黑不透明暗底
	var bg := ColorRect.new()
	bg.name = "BackgroundOverlay"
	bg.color = GameStyle.INK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	# 2. 柔和暗角晕映（四周向内柔和压暗，将视觉重心锁在中央 Hero 与 2×2 功能矩阵）
	var vig := ColorRect.new()
	vig.name = "BackgroundVignette"
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vig_mat := ShaderMaterial.new()
	vig_mat.shader = preload("res://assets/shaders/vignette_soft.gdshader")
	vig_mat.set_shader_parameter("tint_color", Color(0.0, 0.0, 0.0, 0.0))
	vig_mat.set_shader_parameter("vignette_intensity", 0.45)
	vig_mat.set_shader_parameter("vignette_opacity", 0.85)
	vig.material = vig_mat
	add_child(vig)

## 顶栏贴角级联徽章带（右上声音+设置）
func _build_top_bar() -> void:
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
		GameStyle.NAVY2, GameStyle.GOLD, GameStyle.JADE, _on_sound_toggle_pressed)
	_top_bar.add_child(_sound_badge_btn)

	_top_set_btn = _make_badge_button("设置", Vector2(74, 36),
		GameStyle.NAVY2, GameStyle.GOLD, GameStyle.PAPER, _on_settings_pressed)
	_top_bar.add_child(_top_set_btn)

func _make_badge_button(text: String, min_sz: Vector2, bg: Color, hover_bg: Color,
		font_col: Color, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = min_sz
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.focus_mode = Control.FOCUS_NONE
	# hover 面是彩块（GOLD），亮字压上去对比差，统一翻黑字
	GameStyle.button(btn, bg, hover_bg, 13, font_col, GameStyle.SLANT_BAND, GameStyle.INK_TEXT)
	btn.pressed.connect(callback)
	return btn

## 中央主区：五块大色块矩阵（顶栏下方起算、上下气口居中）+ 右下角检查更新按钮（贴屏底屏右）
## 两块各挂各的容器，竖向落位由 `_layout_responsive()` 现算 —— 组内缝隙不再决定矩阵高低。
func _build_center_matrix() -> void:
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

	# 右上 1：修仙志（点缀黄色块）
	var career_res := _build_entry_block(
		"CAREER", "战 绩", "0 胜 · 击杀 0 只",
		GameStyle.JADE, GameStyle.INK_TEXT, GameStyle.NAVY2, GameStyle.JADE,
		_on_career_pressed
	)
	top_pair.add_child(career_res["card"])
	_small_cards.append(career_res["card"])
	_anim_blocks.append(career_res["card"])
	_career_sub_lbl = career_res["sub_label"]

	# 右上 2：传道玉简（增益绿色块）
	var manual_res := _build_entry_block(
		"MANUAL", "图鉴", "20 武器 · 18 道具 · 9 角色",
		GameStyle.GOOD, GameStyle.INK_TEXT, GameStyle.NAVY2, GameStyle.GOOD,
		_on_manual_pressed
	)
	top_pair.add_child(manual_res["card"])
	_small_cards.append(manual_res["card"])
	_anim_blocks.append(manual_res["card"])
	_manual_sub_lbl = manual_res["sub_label"]

	# 右下 1：天地律动·设置（纸白色块）
	var settings_res := _build_entry_block(
		"CONFIG", "设置", "音效 · 画面 · 震屏设置",
		GameStyle.PAPER, GameStyle.INK_TEXT, GameStyle.NAVY2, GameStyle.GOLD,
		_on_settings_pressed
	)
	bot_pair.add_child(settings_res["card"])
	_small_cards.append(settings_res["card"])
	_anim_blocks.append(settings_res["card"])
	_settings_sub_lbl = settings_res["sub_label"]

	# 右下 2：新手指南（元素橙色块）
	var guide_res := _build_entry_block(
		"GUIDE", "新手指南", "六页图文 · 随时重温",
		GameStyle.ELEMENT, GameStyle.INK_TEXT, GameStyle.NAVY2, GameStyle.ELEMENT,
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
	GameStyle.button(_update_btn, GameStyle.GOLD, GameStyle.GOLD_EDGE, 12, GameStyle.INK_TEXT, GameStyle.SLANT_BUTTON)
	# 状态文案（「已是最新版」「新版 v0.0.17!」）比默认四字长，按钮要贴字自己撑开；
	# GameStyle.block 不带左右内距，这里补上，否则长文案会顶到斜切边。
	for key in ["normal", "hover", "pressed"]:
		var sbs := _update_btn.get_theme_stylebox(StringName(key)) as StyleBoxFlat
		if sbs != null:
			sbs.content_margin_left = 10.0
			sbs.content_margin_right = 10.0
	_update_btn.pressed.connect(_on_update_pressed)
	_update_host.add_child(_update_btn)
	_anim_blocks.append(_update_btn)

## 左侧整柱 Hero 大方块：开始渡劫 + 6 档危险度 + 无尽试炼开关
func _build_hero_block() -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(BASE_HERO_W, HERO_H_BASE)
	var sb := GameStyle.block(GameStyle.GOLD, GameStyle.SLANT_BLOCK, Vector2(6, 7))
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

	# 顶部角签行 + 无尽试炼直通开关
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(top_row)

	var tag_chip := Label.new()
	tag_chip.text = " PLAY "
	tag_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag_chip.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.NAVY2))
	GameStyle.label(tag_chip, 11, GameStyle.JADE)
	top_row.add_child(tag_chip)

	var top_spacer := Control.new()
	top_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(top_spacer)

	# 无尽模式切换开关（紧贴危险度上方/主块右上）
	_endless_btn = Button.new()
	_endless_btn.custom_minimum_size = Vector2(138, ENDLESS_BTN_H_BASE)
	_endless_btn.focus_mode = Control.FOCUS_NONE
	_endless_btn.pressed.connect(_on_endless_toggle_pressed)
	top_row.add_child(_endless_btn)

	# 大标题
	_hero_title = Label.new()
	_hero_title.text = "开 始 游 戏"
	GameStyle.label(_hero_title, HERO_TITLE_FONT_BASE, GameStyle.INK_TEXT, 0, GameStyle.INK, true)
	vbox.add_child(_hero_title)

	# 危险度选择区（纯黑内嵌衬板，让 6 档按钮在金色大块上清晰醒目）
	_danger_box = PanelContainer.new()
	var d_sb := GameStyle.panel(GameStyle.with_alpha(Color.BLACK, 0.82), GameStyle.SLANT_PLATE, Vector2.ZERO)
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
	d_lbl.text = "难度选择 · 通关当前最高档解锁下一档"
	GameStyle.label(d_lbl, HERO_DANGER_HEAD_FONT_BASE, GameStyle.PAPER_DIM)
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
	GameStyle.button(_hero_start_btn, GameStyle.JADE, GameStyle.JADE_EDGE, 18, GameStyle.INK_TEXT, GameStyle.SLANT_BUTTON)
	_hero_start_btn.pressed.connect(_on_start_pressed)
	vbox.add_child(_hero_start_btn)

	_refresh_danger_row()
	_refresh_endless_toggle()
	return card

## 右列 2×2 实底大色块构建器（整块可点，内置角签、大名号、副文案、右下箭标）
func _build_entry_block(tag_text: String, title_text: String, sub_text: String,
		face_col: Color, ink_col: Color, chip_bg: Color, chip_fg: Color,
		callback: Callable) -> Dictionary:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(BASE_SMALL_W, SMALL_H_BASE)
	var normal_sb := GameStyle.block(face_col, GameStyle.SLANT_BLOCK, Vector2(5, 6))
	normal_sb.content_margin_left = 18.0
	normal_sb.content_margin_right = 16.0
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

	var chip := Label.new()
	chip.text = " %s " % tag_text
	chip.add_theme_stylebox_override("normal", GameStyle.chip(chip_bg))
	GameStyle.label(chip, 10, chip_fg)
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
	bot_row.add_theme_constant_override("separation", 6)
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
		"vbox": vbox,
		"name_label": name_lbl,
		"void": sp,
	}
	_entry_blocks.append(block)
	return block

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

	# 2. 按可视宽度计算方块矩阵缩放因子（预留左右 36px 给斜切外扩与安全边距）
	var base_total_w := BASE_HERO_W + BASE_GAP_HERO + BASE_SMALL_W * 2.0 + BASE_GAP_COL
	var avail_w := maxf(640.0, vp.x - 44.0)
	var f := clampf(avail_w / base_total_w, 0.74, 1.15)
	if absf(f - 1.0) < 0.03:
		f = 1.0

	var hero_w := roundf(BASE_HERO_W * f)
	var small_w := roundf(BASE_SMALL_W * f)

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
		"endless_h": clampf(ENDLESS_BTN_H_BASE + extra * 0.10, ENDLESS_BTN_H_BASE, 36.0),
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
	_hero_title.add_theme_font_size_override("font_size", int(m["title_font"]))
	_danger_head_lbl.add_theme_font_size_override("font_size", int(m["danger_head_font"]))
	_endless_btn.custom_minimum_size = Vector2(138.0, float(m["endless_h"]))
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
		var sb := card.get_theme_stylebox("panel") as StyleBoxFlat
		if sb != null:
			sb.content_margin_top = float(m["pad_y"])
			sb.content_margin_bottom = float(m["pad_y"])

# ---------------- 状态刷新 ----------------

func _refresh_danger_row() -> void:
	for d in range(_danger_buttons.size()):
		var btn := _danger_buttons[d]
		var unlocked := d <= GameManager.max_danger_unlocked
		btn.disabled = not unlocked
		btn.text = DANGER_NAMES[d] if unlocked else "锁"
		if d == GameManager.danger_level and unlocked:
			GameStyle.button(btn, GameStyle.JADE, GameStyle.JADE_EDGE, 12, GameStyle.INK_TEXT, GameStyle.SLANT_BUTTON)
		elif unlocked:
			GameStyle.button(btn, GameStyle.NAVY2, GameStyle.LINE, 12, GameStyle.PAPER_DIM, GameStyle.SLANT_BUTTON)
		else:
			GameStyle.button(btn, GameStyle.INK, GameStyle.LINE, 12, GameStyle.GREY, GameStyle.SLANT_BUTTON)

func _refresh_endless_toggle() -> void:
	if _endless_btn == null or not is_instance_valid(_endless_btn):
		return
	var on := GameManager.start_in_endless
	if on:
		_endless_btn.text = "✦ 无尽模式 · [开]"
		GameStyle.button(_endless_btn, GameStyle.GOOD, GameStyle.JADE, 12, GameStyle.INK_TEXT, GameStyle.SLANT_BAND)
		if _hero_start_btn != null:
			_hero_start_btn.text = "直 入 无 尽  》"
			GameStyle.button(_hero_start_btn, GameStyle.GOOD, GameStyle.JADE_EDGE, 18, GameStyle.INK_TEXT, GameStyle.SLANT_BUTTON)
	else:
		_endless_btn.text = "无尽模式 · [关]"
		GameStyle.button(_endless_btn, GameStyle.NAVY2, GameStyle.JADE, 12, GameStyle.PAPER_DIM, GameStyle.SLANT_BAND, GameStyle.INK_TEXT)
		if _hero_start_btn != null:
			_hero_start_btn.text = "开 始 游 戏  》"
			GameStyle.button(_hero_start_btn, GameStyle.JADE, GameStyle.JADE_EDGE, 18, GameStyle.INK_TEXT, GameStyle.SLANT_BUTTON)

func _refresh_sound_badge() -> void:
	if _sound_badge_btn == null or not is_instance_valid(_sound_badge_btn):
		return
	var muted := SettingsManager.is_bus_muted(&"Master")
	if muted:
		_sound_badge_btn.text = "音效 · 关"
		GameStyle.button(_sound_badge_btn, GameStyle.BAD_DK, GameStyle.BAD, 13, GameStyle.CHALK, GameStyle.SLANT_BAND)
	else:
		_sound_badge_btn.text = "音效 · 开"
		GameStyle.button(_sound_badge_btn, GameStyle.NAVY2, GameStyle.GOLD, 13, GameStyle.JADE, GameStyle.SLANT_BAND, GameStyle.INK_TEXT)

func _refresh_dynamic_texts() -> void:
	# 1. 修仙志卡片副行
	if _career_sub_lbl != null and is_instance_valid(_career_sub_lbl):
		var cs := GameManager.career_stats
		var wins := int(cs.get("total_wins", 0))
		var kills := int(cs.get("total_kills", 0))
		var b_wave := int(cs.get("best_wave", 0))
		if b_wave > 0:
			_career_sub_lbl.text = "%d 胜 · 最高 %d 波 · 击杀 %d" % [wins, b_wave, kills]
		else:
			_career_sub_lbl.text = "%d 胜 · 累计击杀 %d 只" % [wins, kills]

	# 2. 传道玉简副行（显示已解锁角色/道具数）
	if _manual_sub_lbl != null and is_instance_valid(_manual_sub_lbl):
		var c_cnt := GameManager.unlocked_cultivators.size()
		var i_cnt := GameManager.unlocked_items.size()
		_manual_sub_lbl.text = "角色 %d/%d · 道具 %d/%d" % [
			c_cnt, CultivatorData.all_ids().size(),
			i_cnt, ItemData.all_ids().size()
		]

	# 3. 天地律动设置副行
	if _settings_sub_lbl != null and is_instance_valid(_settings_sub_lbl):
		var vol := int(round(SettingsManager.get_bus_volume(&"Master") * 100.0))
		var muted := SettingsManager.is_bus_muted(&"Master")
		var vol_str := "静音" if muted else ("音量 %d%%" % vol)
		_settings_sub_lbl.text = "%s · 震屏「%s」" % [vol_str, SettingsManager.shake_level_label()]

	_refresh_sound_badge()

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
	_layout_responsive()
	_refresh_danger_row()
	_refresh_endless_toggle()
	_refresh_dynamic_texts()
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
	GameManager.set_danger(d)
	_refresh_danger_row()

func _on_endless_toggle_pressed() -> void:
	GameManager.set_start_in_endless(not GameManager.start_in_endless)
	_refresh_endless_toggle()

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
	var cult_select := get_parent().get_node_or_null("CultivatorSelect")
	if cult_select != null:
		cult_select.show_select()
	else:
		var weapon_select := get_parent().get_node_or_null("StartWeaponSelect")
		if weapon_select != null:
			weapon_select.show_select()

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
	settings_requested.emit()

func _on_career_pressed() -> void:
	career_requested.emit()

func _on_manual_pressed() -> void:
	manual_requested.emit()

func _on_guide_pressed() -> void:
	# 手动重温新手指南：不受「下次不弹出」偏好影响，关闭后留在主菜单
	var tut := get_parent().get_node_or_null("TutorialDialog")
	if tut != null:
		tut.open()
