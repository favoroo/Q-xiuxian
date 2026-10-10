class_name StartMenu
extends Control

## P5/dudu-cocos 大色块矩阵风格首页：
##   ① 顶栏贴角级联徽章带（左：生涯最高危险度 + 灵石囊储备；右：快速静音 + 游戏设置）
##   ② 居中斜切大匾标题（「渡 个 劫」）—— 贴顶栏，不跟着整组往下飘
##   ③ 左 1 主方块（Hero「开始渡劫」，内嵌 6 档危险度与「无尽试炼」直通开关）+ 右 2×2 矩阵大方块
##   ④ 底部通宽横幅（天道版本信息与检查更新）—— 贴屏底
## 点「开始渡劫」后淡出，交给 CultivatorSelect 选择道统（paused 链不中断）。

signal settings_requested
signal career_requested
signal manual_requested

const DANGER_NAMES := ["简单", "普通", "困难", "噩梦", "地狱", "极限"]

## 四角括号是「贴着屏角」的装饰：坐标跟着这一屏的实得尺寸走
const BRACKET_LEN := 48.0
const BRACKET_INSET := 18.0

## 核心矩阵基准尺寸（960×540 下）
const BASE_HERO_W := 348.0
const BASE_SMALL_W := 248.0
const BASE_GAP_HERO := 14.0
const BASE_GAP_COL := 16.0
const ROW_GAP := 14.0
const HERO_H := 284.0
const SMALL_H := 135.0
const BANNER_H := 42.0
const TITLE_H_BASE := 68.0           # 标题匾基准高：只给首帧没量到实得高时兜底用

## 竖向这一列怎么贴（2026-10-10 用户真机：「标题上面怎么有那么大的空白间距」）。
## 旧写法把「标题 + 矩阵 + 横幅」装进一个 VBox 整组居中 ⇒ 标题被推到 y=82，屏上半截全是空的，
## 而眼睛看到的「空白」是屏顶→标题那 82 单位，不是组内那 12 单位缝隙。
## 现在三段各贴各位：标题贴顶栏、横幅贴屏底；中间那点富余先当气口，气口撑到上限
## （4:3 平板那种高屏）才让主块长高 —— 540 这一档富余刚好只够气口，方块密度不变。
const TOP_BAR_INSET_TOP := 12.0        # 顶栏带离屏顶
const TOP_BAR_H := 40.0                # 顶栏带高（徽章 36 + 余量）
const TITLE_GAP_TOP := 10.0            # 顶栏底 → 标题顶
const BANNER_MARGIN_BOTTOM := 16.0     # 横幅底 → 屏底
const BLOCK_GAP_MAX := 40.0            # 标题与矩阵、矩阵与横幅之间的气口上界，再空就让主块长高
const HERO_H_MAX := 340.0              # 主块长高的封顶：再多只是把空白搬进卡里
const BAND_TITLE_OFFSET := 14.0        # 装饰斜带顶边相对标题顶边的下移

var _decor_band: PanelContainer
var _brackets: Array[Line2D] = []
var _top_bar: HBoxContainer
var _title_host: CenterContainer
var _matrix_host: CenterContainer
var _banner_host: CenterContainer
var _title_block: PanelContainer

# 顶栏徽章控件
var _realm_badge_btn: Button
var _purse_badge_btn: Button
var _sound_badge_btn: Button
var _top_set_btn: Button

# Hero 大方块与内部控件
var _hero_card: PanelContainer
var _hero_sub_lbl: Label
var _danger_buttons: Array[Button] = []
var _endless_btn: Button
var _hero_start_btn: Button

# 右侧 2×2 大方块与动态副文案
var _small_cards: Array[PanelContainer] = []
var _career_sub_lbl: Label
var _career_claim_chip: Label
var _manual_sub_lbl: Label
var _settings_sub_lbl: Label

# 底部通宽横幅
var _banner_panel: PanelContainer
var _banner_ver_lbl: Label
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
	_build_decor()
	_build_top_bar()
	_build_center_matrix()
	_layout_responsive()
	# 首帧的标题高要等容器排完才量得到：延一帧再贴一次，否则第一段排版用的是保底高度
	call_deferred("_layout_responsive")
	UpdateManager.update_available.connect(_on_update_available)
	UpdateManager.no_update_found.connect(_on_no_update_found)
	UpdateManager.check_failed.connect(_on_check_failed)
	SettingsManager.audio_volume_changed.connect(func(_b: StringName, _v: float, _m: bool): _refresh_sound_badge())
	SettingsManager.setting_changed.connect(func(_s: StringName, _k: StringName, _v: Variant): _refresh_dynamic_texts())

func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = GameStyle.INK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

func _build_decor() -> void:
	var decor := Control.new()
	decor.set_anchors_preset(Control.PRESET_FULL_RECT)
	decor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(decor)

	# 横向斜切墨带（横穿标题与矩阵上方，有意比屏宽出血，判据放行）
	_decor_band = PanelContainer.new()
	_decor_band.add_theme_stylebox_override("panel", GameStyle.panel(GameStyle.NAVY, GameStyle.SLANT_BAND, Vector2.ZERO))
	_decor_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_decor_band.set_meta("layout_bleed", true)
	decor.add_child(_decor_band)

	# 四角青玉括号
	for i in range(4):
		var bracket := Line2D.new()
		bracket.width = 4.0
		bracket.default_color = Color(GameStyle.JADE.r, GameStyle.JADE.g, GameStyle.JADE.b, 0.45)
		bracket.joint_mode = Line2D.LINE_JOINT_ROUND
		bracket.begin_cap_mode = Line2D.LINE_CAP_ROUND
		bracket.end_cap_mode = Line2D.LINE_CAP_ROUND
		decor.add_child(bracket)
		_brackets.append(bracket)

## 顶栏贴角级联徽章带（仿 dudu-cocos 左上等级+货币、右上声音+设置）
func _build_top_bar() -> void:
	var top_margin := MarginContainer.new()
	top_margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_margin.offset_top = TOP_BAR_INSET_TOP
	top_margin.offset_bottom = TOP_BAR_INSET_TOP + TOP_BAR_H
	top_margin.add_theme_constant_override("margin_left", 28)
	top_margin.add_theme_constant_override("margin_right", 28)
	top_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_margin)

	_top_bar = HBoxContainer.new()
	_top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_bar.add_theme_constant_override("separation", 10)
	top_margin.add_child(_top_bar)

	# 左簇：境界徽章 + 灵石囊徽章（点按均进入修仙志）
	_realm_badge_btn = _make_badge_button("难度 · 简单", Vector2(118, 36),
		GameStyle.GOLD, GameStyle.GOLD_EDGE, GameStyle.INK_TEXT, _on_career_pressed)
	_top_bar.add_child(_realm_badge_btn)

	_purse_badge_btn = _make_badge_button("金币 0", Vector2(116, 36),
		GameStyle.NAVY2, GameStyle.JADE, GameStyle.JADE, _on_career_pressed)
	_top_bar.add_child(_purse_badge_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_bar.add_child(spacer)

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
	GameStyle.button(btn, bg, hover_bg, 13, font_col, GameStyle.SLANT_BAND)
	btn.pressed.connect(callback)
	return btn

## 中央主区：标题大匾（贴顶栏）+ 五块大色块矩阵（居中）+ 底部通宽横幅（贴屏底）
## 三块各挂各的容器，竖向落位由 `_layout_responsive()` 现算 —— 组内缝隙不再决定标题高低。
func _build_center_matrix() -> void:
	# 1. 街机海报标题大匾
	_title_host = CenterContainer.new()
	_title_host.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_title_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_host)
	_build_title_section(_title_host)

	# 2. 五块实底大色块矩阵（左 Hero 整柱 + 右 2×2）
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

	# 右上 1：修仙志（青玉色块）
	var career_res := _build_entry_block(
		"CAREER", "战 绩", "0 胜 · 击杀 0 只",
		GameStyle.JADE, GameStyle.INK_TEXT, GameStyle.NAVY2, GameStyle.JADE,
		_on_career_pressed, true
	)
	top_pair.add_child(career_res["card"])
	_small_cards.append(career_res["card"])
	_anim_blocks.append(career_res["card"])
	_career_sub_lbl = career_res["sub_label"]
	_career_claim_chip = career_res["badge_label"]

	# 右上 2：传道玉简（青碧色块）
	var manual_res := _build_entry_block(
		"MANUAL", "图鉴", "20 武器 · 18 道具 · 9 角色",
		GameStyle.GOOD, GameStyle.INK_TEXT, GameStyle.NAVY2, GameStyle.GOOD,
		_on_manual_pressed, false
	)
	top_pair.add_child(manual_res["card"])
	_small_cards.append(manual_res["card"])
	_anim_blocks.append(manual_res["card"])
	_manual_sub_lbl = manual_res["sub_label"]

	# 右下 1：天地律动·设置（纸白色块）
	var settings_res := _build_entry_block(
		"CONFIG", "设置", "音效 · 画面 · 震屏设置",
		GameStyle.PAPER, GameStyle.INK_TEXT, GameStyle.NAVY2, GameStyle.GOLD,
		_on_settings_pressed, false
	)
	bot_pair.add_child(settings_res["card"])
	_small_cards.append(settings_res["card"])
	_anim_blocks.append(settings_res["card"])
	_settings_sub_lbl = settings_res["sub_label"]

	# 右下 2：归隐山林·退出（朱砂色块）
	var quit_res := _build_entry_block(
		"EXIT", "退出游戏", "保存进度 · 暂时离开",
		GameStyle.BAD, GameStyle.PAPER, GameStyle.INK, GameStyle.PAPER,
		_on_quit_pressed, false
	)
	bot_pair.add_child(quit_res["card"])
	_small_cards.append(quit_res["card"])
	_anim_blocks.append(quit_res["card"])

	# 3. 底部通宽收尾横幅
	_banner_host = CenterContainer.new()
	_banner_host.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_banner_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner_host)
	_banner_panel = _build_bottom_banner()
	_banner_host.add_child(_banner_panel)
	_anim_blocks.append(_banner_panel)

func _build_title_section(parent: Control) -> void:
	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", 14)
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(title_row)

	_title_block = PanelContainer.new()
	_title_block.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var tstyle := GameStyle.block(GameStyle.GOLD, GameStyle.SLANT_BLOCK, Vector2(6, 7))
	tstyle.content_margin_left = 28.0
	tstyle.content_margin_top = 4.0
	tstyle.content_margin_right = 28.0
	tstyle.content_margin_bottom = 8.0
	_title_block.add_theme_stylebox_override("panel", tstyle)

	var title_hbox := HBoxContainer.new()
	title_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	title_hbox.add_theme_constant_override("separation", 14)
	title_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_block.add_child(title_hbox)

	var title := Label.new()
	title.text = "渡 个 劫"
	GameStyle.label(title, 42, GameStyle.INK_TEXT, 0, GameStyle.INK, true)
	title_hbox.add_child(title)

	var sub_chip := Label.new()
	sub_chip.text = " 击杀敌人 · 生存到波末 "
	sub_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sub_chip.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.NAVY2))
	GameStyle.label(sub_chip, 12, GameStyle.JADE)
	title_hbox.add_child(sub_chip)

	title_row.add_child(_title_block)

## 左侧整柱 Hero 大方块：开始渡劫 + 6 档危险度 + 无尽试炼开关
func _build_hero_block() -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(BASE_HERO_W, HERO_H)
	var sb := GameStyle.block(GameStyle.GOLD, GameStyle.SLANT_BLOCK, Vector2(6, 7))
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 14.0
	card.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 7)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vbox)

	# 顶部角签行 + 无尽试炼直通开关
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(top_row)

	var tag_chip := Label.new()
	tag_chip.text = " DAO TRIAL "
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
	_endless_btn.custom_minimum_size = Vector2(138, 28)
	_endless_btn.focus_mode = Control.FOCUS_NONE
	_endless_btn.pressed.connect(_on_endless_toggle_pressed)
	top_row.add_child(_endless_btn)

	# 大标题 + 副说明
	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 2)
	title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title_box)

	var hero_title := Label.new()
	hero_title.text = "开 始 游 戏"
	GameStyle.label(hero_title, 32, GameStyle.INK_TEXT, 0, GameStyle.INK, true)
	title_box.add_child(hero_title)

	_hero_sub_lbl = Label.new()
	_hero_sub_lbl.text = "九名角色 · 二十波敌人 · 生存通关"
	GameStyle.label(_hero_sub_lbl, 12, GameStyle.NAVY2)
	title_box.add_child(_hero_sub_lbl)

	# 危险度选择区（深色内嵌衬板，让 6 档按钮在金色大块上清晰醒目）
	var danger_box := PanelContainer.new()
	var d_sb := GameStyle.panel(Color(0.07, 0.09, 0.14, 0.92), GameStyle.SLANT_PLATE, Vector2.ZERO)
	d_sb.content_margin_left = 8.0
	d_sb.content_margin_right = 8.0
	d_sb.content_margin_top = 6.0
	d_sb.content_margin_bottom = 6.0
	danger_box.add_theme_stylebox_override("panel", d_sb)
	danger_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(danger_box)

	var danger_vbox := VBoxContainer.new()
	danger_vbox.add_theme_constant_override("separation", 4)
	danger_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	danger_box.add_child(danger_vbox)

	var d_head := HBoxContainer.new()
	d_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	danger_vbox.add_child(d_head)

	var d_lbl := Label.new()
	d_lbl.text = "难度选择 · 通关当前最高档解锁下一档"
	GameStyle.label(d_lbl, 11, GameStyle.PAPER_DIM)
	d_head.add_child(d_lbl)

	var d_row := HBoxContainer.new()
	d_row.alignment = BoxContainer.ALIGNMENT_CENTER
	d_row.add_theme_constant_override("separation", 4)
	d_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	danger_vbox.add_child(d_row)

	_danger_buttons.clear()
	for d in range(GameBalance.DANGER_MAX + 1):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(46, 28)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		var dd := d
		btn.pressed.connect(func(): _on_danger_pressed(dd))
		d_row.add_child(btn)
		_danger_buttons.append(btn)

	var mid_spacer := Control.new()
	mid_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(mid_spacer)

	# 底部整条出战主按钮
	_hero_start_btn = Button.new()
	_hero_start_btn.text = "开 始 游 戏  》"
	_hero_start_btn.custom_minimum_size = Vector2(0, 42)
	_hero_start_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero_start_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(_hero_start_btn, GameStyle.NAVY2, GameStyle.JADE, 18, GameStyle.PAPER, GameStyle.SLANT_BUTTON, GameStyle.INK_TEXT)
	_hero_start_btn.pressed.connect(_on_start_pressed)
	vbox.add_child(_hero_start_btn)

	_refresh_danger_row()
	_refresh_endless_toggle()
	return card

## 右列 2×2 实底大色块构建器（整块可点，内置角签、大名号、副文案、右下箭标）
func _build_entry_block(tag_text: String, title_text: String, sub_text: String,
		face_col: Color, ink_col: Color, chip_bg: Color, chip_fg: Color,
		callback: Callable, with_badge: bool) -> Dictionary:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(BASE_SMALL_W, SMALL_H)
	var normal_sb := GameStyle.block(face_col, GameStyle.SLANT_BLOCK, Vector2(5, 6))
	normal_sb.content_margin_left = 18.0
	normal_sb.content_margin_right = 16.0
	normal_sb.content_margin_top = 12.0
	normal_sb.content_margin_bottom = 12.0
	card.add_theme_stylebox_override("panel", normal_sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	# 顶行：英文角签 + 可选提醒角标
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 6)
	vbox.add_child(top_row)

	var chip := Label.new()
	chip.text = " %s " % tag_text
	chip.add_theme_stylebox_override("normal", GameStyle.chip(chip_bg))
	GameStyle.label(chip, 10, chip_fg)
	top_row.add_child(chip)

	var top_sp := Control.new()
	top_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(top_sp)

	var badge_lbl: Label = null
	if with_badge:
		badge_lbl = Label.new()
		badge_lbl.text = " 有奖可领 "
		badge_lbl.visible = false
		badge_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.ELEMENT))
		GameStyle.label(badge_lbl, 10, GameStyle.INK_TEXT)
		top_row.add_child(badge_lbl)

	# 中行：大标题
	var name_lbl := Label.new()
	name_lbl.text = title_text
	GameStyle.label(name_lbl, 24, ink_col, 0, GameStyle.INK, true)
	vbox.add_child(name_lbl)

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
	var sub_col := Color(ink_col.r, ink_col.g, ink_col.b, 0.78)
	GameStyle.label(sub_lbl, 12, sub_col)
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

	return {
		"card": card,
		"sub_label": sub_lbl,
		"badge_label": badge_lbl,
	}

## 底部通宽横幅（仿 dudu-cocos 底部活动/状态条）
func _build_bottom_banner() -> PanelContainer:
	var total_w := BASE_HERO_W + BASE_GAP_HERO + BASE_SMALL_W * 2.0 + BASE_GAP_COL
	var banner := PanelContainer.new()
	banner.custom_minimum_size = Vector2(total_w, BANNER_H)
	var sb := GameStyle.block(GameStyle.NAVY2, GameStyle.SLANT_BLOCK, Vector2(4, 5))
	sb.border_color = GameStyle.GOLD_DK
	sb.content_margin_left = 16.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 5.0
	sb.content_margin_bottom = 7.0
	banner.add_theme_stylebox_override("panel", sb)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 12)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(hbox)

	var chip := Label.new()
	chip.text = " REALM "
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.ELEMENT))
	GameStyle.label(chip, 10, GameStyle.INK_TEXT)
	hbox.add_child(chip)

	_banner_ver_lbl = Label.new()
	_banner_ver_lbl.text = "%s %s · 生存战斗 · 击杀敌人" % [Version.APP_NAME, Version.APP_VERSION_NAME]
	_banner_ver_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	GameStyle.label(_banner_ver_lbl, 13, GameStyle.PAPER)
	hbox.add_child(_banner_ver_lbl)

	_update_btn = Button.new()
	_update_btn.text = "检 查 更 新"
	_update_btn.custom_minimum_size = Vector2(118, 28)
	_update_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_update_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(_update_btn, GameStyle.GOLD, GameStyle.GOLD_EDGE, 12, GameStyle.INK_TEXT, GameStyle.SLANT_BUTTON)
	_update_btn.pressed.connect(_on_update_pressed)
	hbox.add_child(_update_btn)

	return banner

## 响应式排版：适配 720（4:3）/ 960（16:9）/ 1204（20:9），保证斜切块画出来绝不出屏
func _layout_responsive() -> void:
	var vp := size
	if vp.x <= 0.0 or vp.y <= 0.0:
		if get_viewport() != null:
			vp = get_viewport().get_visible_rect().size
		else:
			vp = Vector2(960, 540)

	# 1. 四角括号贴角重排
	_layout_brackets(vp)

	# 2. 竖向三段落位：标题贴顶栏、横幅贴屏底，矩阵夹在中间。
	#    中间富余先摊成气口（≤BLOCK_GAP_MAX），气口顶到上限还有富余才让主块长高（≤HERO_H_MAX）。
	#    960×540 这一档算出来气口 34、主块 284 ⇒ 方块密度与旧版一致，只是不再往下飘。
	var title_top := TOP_BAR_INSET_TOP + TOP_BAR_H + TITLE_GAP_TOP
	var title_h := _title_h()
	var title_bottom := title_top + title_h
	var banner_top := vp.y - BANNER_MARGIN_BOTTOM - BANNER_H
	var mid_region := banner_top - title_bottom
	var gap := minf(maxf((mid_region - HERO_H) / 2.0, 0.0), BLOCK_GAP_MAX)
	var hero_h := clampf(mid_region - 2.0 * gap, HERO_H, HERO_H_MAX)
	gap = maxf((mid_region - hero_h) / 2.0, 0.0)
	var small_h := (hero_h - ROW_GAP) / 2.0
	if _title_host != null and is_instance_valid(_title_host):
		_title_host.offset_top = title_top
		_title_host.offset_bottom = title_top + title_h
	if _matrix_host != null and is_instance_valid(_matrix_host):
		_matrix_host.offset_top = title_bottom + gap
		_matrix_host.offset_bottom = -(vp.y - banner_top + gap)
	if _banner_host != null and is_instance_valid(_banner_host):
		_banner_host.offset_top = -(BANNER_MARGIN_BOTTOM + BANNER_H)
		_banner_host.offset_bottom = -BANNER_MARGIN_BOTTOM

	# 3. 装饰斜带跨屏重排（顶边跟着标题走，不再钉死像素）
	if _decor_band != null and is_instance_valid(_decor_band):
		_decor_band.custom_minimum_size = Vector2(vp.x + 180.0, 140.0)
		_decor_band.position = Vector2(-90.0, title_top + BAND_TITLE_OFFSET)

	# 4. 按可视宽度计算方块矩阵缩放因子（预留左右 36px 给斜切外扩与安全边距）
	var base_total_w := BASE_HERO_W + BASE_GAP_HERO + BASE_SMALL_W * 2.0 + BASE_GAP_COL
	var avail_w := maxf(640.0, vp.x - 44.0)
	var f := clampf(avail_w / base_total_w, 0.74, 1.15)
	if absf(f - 1.0) < 0.03:
		f = 1.0

	var hero_w := roundf(BASE_HERO_W * f)
	var small_w := roundf(BASE_SMALL_W * f)
	var gap_hero := roundf(BASE_GAP_HERO * f)
	var gap_col := roundf(BASE_GAP_COL * f)
	var total_w := hero_w + gap_hero + small_w * 2.0 + gap_col

	if _hero_card != null and is_instance_valid(_hero_card):
		_hero_card.custom_minimum_size = Vector2(hero_w, hero_h)
	for sc in _small_cards:
		if is_instance_valid(sc):
			sc.custom_minimum_size = Vector2(small_w, small_h)
	for btn in _danger_buttons:
		if is_instance_valid(btn):
			btn.custom_minimum_size = Vector2(maxf(34.0, floorf((hero_w - 64.0) / 6.0)), 28.0)
	if _banner_panel != null and is_instance_valid(_banner_panel):
		_banner_panel.custom_minimum_size = Vector2(total_w, BANNER_H)

## 标题匾这一行多高：量实得的最小高（字体 + stylebox 边距），量不到时（首帧还没排）
## 用基准档兜一帧，`_ready` 里已 call_deferred 再贴一次。
func _title_h() -> float:
	if _title_block != null and is_instance_valid(_title_block):
		var h := _title_block.get_combined_minimum_size().y
		if h > 0.0:
			return h
	return TITLE_H_BASE

func _layout_brackets(vp: Vector2) -> void:
	var w := vp.x
	var h := vp.y
	if w <= 0.0 or h <= 0.0 or _brackets.is_empty():
		return
	var corners := [
		Vector2(BRACKET_INSET, BRACKET_INSET), Vector2(1, 1),
		Vector2(w - BRACKET_INSET, BRACKET_INSET), Vector2(-1, 1),
		Vector2(w - BRACKET_INSET, h - BRACKET_INSET), Vector2(-1, -1),
		Vector2(BRACKET_INSET, h - BRACKET_INSET), Vector2(1, -1),
	]
	for i in range(_brackets.size()):
		var origin: Vector2 = corners[i * 2]
		var sgn: Vector2 = corners[i * 2 + 1]
		_brackets[i].points = PackedVector2Array([
			origin + Vector2(-sgn.x * BRACKET_LEN, 0),
			origin,
			origin + Vector2(0, -sgn.y * BRACKET_LEN),
		])

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
		GameStyle.button(_endless_btn, GameStyle.GOOD, GameStyle.JADE_EDGE, 12, GameStyle.INK_TEXT, GameStyle.SLANT_BAND)
		if _hero_sub_lbl != null:
			_hero_sub_lbl.text = "无尽模式已开 · 突破二十波上限 · 战至终局"
		if _hero_start_btn != null:
			_hero_start_btn.text = "直 入 无 尽  》"
			GameStyle.button(_hero_start_btn, GameStyle.GOOD_DK, GameStyle.GOOD, 18, GameStyle.PAPER, GameStyle.SLANT_BUTTON, GameStyle.INK_TEXT)
	else:
		_endless_btn.text = "无尽模式 · [关]"
		GameStyle.button(_endless_btn, GameStyle.NAVY2, GameStyle.JADE, 12, GameStyle.PAPER_DIM, GameStyle.SLANT_BAND, GameStyle.INK_TEXT)
		if _hero_sub_lbl != null:
			_hero_sub_lbl.text = "九名角色 · 二十波敌人 · 生存通关"
		if _hero_start_btn != null:
			_hero_start_btn.text = "开 始 游 戏  》"
			GameStyle.button(_hero_start_btn, GameStyle.NAVY2, GameStyle.JADE, 18, GameStyle.PAPER, GameStyle.SLANT_BUTTON, GameStyle.INK_TEXT)

func _refresh_sound_badge() -> void:
	if _sound_badge_btn == null or not is_instance_valid(_sound_badge_btn):
		return
	var muted := SettingsManager.is_bus_muted(&"Master")
	if muted:
		_sound_badge_btn.text = "音效 · 关"
		GameStyle.button(_sound_badge_btn, GameStyle.BAD_DK, GameStyle.BAD, 13, GameStyle.PAPER, GameStyle.SLANT_BAND)
	else:
		_sound_badge_btn.text = "音效 · 开"
		GameStyle.button(_sound_badge_btn, GameStyle.NAVY2, GameStyle.GOLD, 13, GameStyle.JADE, GameStyle.SLANT_BAND)

func _refresh_dynamic_texts() -> void:
	# 1. 顶栏最高危险度与灵石囊
	var max_d := clampi(GameManager.max_danger_unlocked, 0, DANGER_NAMES.size() - 1)
	if _realm_badge_btn != null and is_instance_valid(_realm_badge_btn):
		_realm_badge_btn.text = "难度 · %s" % DANGER_NAMES[max_d]
	if _purse_badge_btn != null and is_instance_valid(_purse_badge_btn):
		_purse_badge_btn.text = "金币 %d" % GameManager.stone_purse

	# 2. 修仙志卡片副行与可领角签
	if _career_sub_lbl != null and is_instance_valid(_career_sub_lbl):
		var cs := GameManager.career_stats
		var wins := int(cs.get("total_wins", 0))
		var kills := int(cs.get("total_kills", 0))
		var b_wave := int(cs.get("best_wave", 0))
		if b_wave > 0:
			_career_sub_lbl.text = "%d 胜 · 最高 %d 波 · 击杀 %d" % [wins, b_wave, kills]
		else:
			_career_sub_lbl.text = "%d 胜 · 累计击杀 %d 只" % [wins, kills]
	if _career_claim_chip != null and is_instance_valid(_career_claim_chip):
		_career_claim_chip.visible = GameManager.has_claimable_rewards()

	# 3. 传道玉简副行（显示已解锁修士/法宝数）
	if _manual_sub_lbl != null and is_instance_valid(_manual_sub_lbl):
		var c_cnt := GameManager.unlocked_cultivators.size()
		var i_cnt := GameManager.unlocked_items.size()
		_manual_sub_lbl.text = "角色 %d/%d · 道具 %d/%d" % [
			c_cnt, CultivatorData.all_ids().size(),
			i_cnt, ItemData.all_ids().size()
		]

	# 4. 天地律动设置副行
	if _settings_sub_lbl != null and is_instance_valid(_settings_sub_lbl):
		var vol := int(round(SettingsManager.get_bus_volume(&"Master") * 100.0))
		var muted := SettingsManager.is_bus_muted(&"Master")
		var vol_str := "静音" if muted else ("音量 %d%%" % vol)
		_settings_sub_lbl.text = "%s · 震屏「%s」" % [vol_str, SettingsManager.shake_level_label()]

	_refresh_sound_badge()

# ---------------- 打开 / 关闭与入场动效 ----------------

func open() -> void:
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
	if _title_block != null and is_instance_valid(_title_block):
		_title_block.pivot_offset = _title_block.size * 0.5
		_title_block.scale = Vector2(0.75, 0.75)
		_title_block.modulate.a = 0.0
		var ttw := _title_block.create_tween().set_parallel(true)
		ttw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		ttw.tween_property(_title_block, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.05)
		ttw.tween_property(_title_block, "modulate:a", 1.0, 0.18).set_delay(0.05)

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
	AudioManager.play_sfx("level_up", 0.9)
	if ResourceLoader.exists("res://assets/audio/vo_guide_start.wav"):
		AudioManager.play_voice(load("res://assets/audio/vo_guide_start.wav"))
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(self, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func():
		visible = false
		var cult_select := get_parent().get_node_or_null("CultivatorSelect")
		if cult_select != null:
			cult_select.show_select()
		else:
			var weapon_select := get_parent().get_node_or_null("StartWeaponSelect")
			if weapon_select != null:
				weapon_select.show_select()
	)

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
			_update_btn.text = "检 查 更 新"
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
			_update_btn.text = "检 查 更 新"
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

func _on_quit_pressed() -> void:
	get_tree().quit()
