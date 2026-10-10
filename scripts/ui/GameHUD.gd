class_name GameHUD
extends Control

## 顶栏暂停与属性按钮请求（由 Main 接线）
signal pause_requested
signal stats_requested

@onready var hp_bar: ProgressBar = $TopContainer/LeftBox/HPBlock/HBox/HPBar
@onready var hp_label: Label = $TopContainer/LeftBox/HPBlock/HBox/HPLabel
@onready var level_label: Label = $TopContainer/LeftBox/LevelBadge/LevelLabel
@onready var exp_bar: ProgressBar = $ExpBar
@onready var time_label: Label = $TopContainer/CenterBox/TimeBlock/TimeLabel
@onready var wave_label: Label = $TopContainer/CenterBox/WaveChip/WaveLabel
@onready var kills_label: Label = $TopContainer/RightBox/KillsChip/KillsLabel
@onready var shards_label: Label = $TopContainer/RightBox/ShardsChip/ShardsLabel
@onready var weapons_bar: HBoxContainer = $WeaponsBar
@onready var banner: PanelContainer = $Banner
@onready var banner_label: Label = $Banner/BannerLabel

## 顶栏原本留的左右边距与顶边距（安全区让位是在它们之上再加，不是替换）
const BASE_EDGE_X := 22.0
const BASE_TOP := 20.0
## 让位上限：读数再大也不许被一个离谱的 safe area 推到屏心
const SAFE_CAP := 140.0

## 按钮口径与直径基准（真身在 SkillButtonView / HudObeliskButton，判据与覆盖层从这里取值）
const SKILL_BTN_SIZE := SkillButtonView.SKILL_BTN_SIZE
const OBELISK_BTN_SIZE := HudObeliskButton.BTN_SIZE
const OBELISK_BTN_TEXT := HudObeliskButton.BTN_TEXT
const OBELISK_BTN_FONT := HudObeliskButton.BTN_FONT

## 子控件（拆分自本文件）：技能键 / 祭坛键 / 魔君血条 / FPS 读数 / 待加点徽记
var _skill_widget: HudSkillButton = null
var _obelisk_widget: HudObeliskButton = null
var _boss_bar_widget: HudBossBar = null

## 兼容引用：判据（skill_check / obelisk_charge_readout_check）与覆盖层仍从 HUD 取按钮节点
var _skill_box: Control = null
var _skill_btn: Button = null
var _obelisk_btn: Button = null

## 兼容：判据读技能键震颤状态（真身在 HudSkillButton）
var _skill_shaking: bool :
	get:
		return _skill_widget != null and _skill_widget.is_shaking()

var _synergy_box: HBoxContainer = null
var _safe_insets: Array[float] = [0.0, 0.0, 0.0]
var _edit_overlay: HudEditOverlay = null

func _ready() -> void:
	banner.modulate.a = 0.0
	_apply_safe_area()
	# 蓝白黄斜切色块（场景里未定样的两块在这里补）
	banner.add_theme_stylebox_override("panel", GameStyle.block(GameStyle.GOLD, GameStyle.SLANT_BAND, Vector2(5, 6)))
	$TopContainer/CenterBox/TimeBlock.add_theme_stylebox_override("panel", GameStyle.block(GameStyle.INK, GameStyle.SLANT_BAND, Vector2(4, 5)))

	GameStyle.label($TopContainer/LeftBox/HPBlock/HBox/HPTitle, 17, GameStyle.INK_TEXT, 0, GameStyle.INK, true)
	GameStyle.label(hp_label, 14, GameStyle.INK_TEXT)
	GameStyle.label(level_label, 14, GameStyle.INK_TEXT)
	GameStyle.label(time_label, 24, GameStyle.CHALK, 0, GameStyle.INK, true)
	GameStyle.label(wave_label, 15, GameStyle.GOLD)
	GameStyle.label(kills_label, 15, GameStyle.INK_TEXT)
	GameStyle.label(shards_label, 15, GameStyle.INK_TEXT)
	GameStyle.label(banner_label, 17, GameStyle.INK_TEXT, 0, GameStyle.INK, true)

	GameManager.player_hp_changed.connect(_on_hp_changed)
	GameManager.player_exp_changed.connect(_on_exp_changed)
	GameManager.player_leveled_up.connect(_on_leveled_up)
	GameManager.stats_updated.connect(_on_stats_updated)
	GameManager.announcement_triggered.connect(show_announcement)
	GameManager.weapons_updated.connect(_on_weapons_updated)
	GameManager.wave_changed.connect(_on_wave_changed)
	_on_wave_changed(GameManager.wave_number)

	_on_weapons_updated(GameManager.get_weapons_summary())
	_build_top_buttons()
	_build_widgets()
	# 羁绊徽记单独一排，摆在顶栏之下。
	# 挂在顶栏里 = 左组要 755 宽 > 它在 960 屏上只分到的 389 ⇒ 整条顶栏被撑到 1125 宽、
	# 两头各出屏 82（气血块少半截、「暂停」整个没了，用户 2026-10-08 说的「顶部的一些 UI
	# 都显示到外面去了」就是这个）。判据 LayoutCheck 灌最宽读数样本量的就是这一格。
	_synergy_box = HBoxContainer.new()
	_synergy_box.add_theme_constant_override("separation", 6)
	_synergy_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_synergy_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_synergy_box.offset_left = BASE_EDGE_X
	_synergy_box.offset_top = 66.0
	_synergy_box.offset_right = -BASE_EDGE_X
	_synergy_box.offset_bottom = 88.0
	add_child(_synergy_box)
	_build_pending_chip()

# ---------------- 安全区让位（刘海 / 圆角 / 系统手势条） ----------------

## 顶栏整条往安全区里让：刘海会把最左那颗气血块与最右那颗暂停键吃掉一半 ——
## 桌面预览里永远是整屏，只有真机看得见，所以这条算术做成纯函数交给判据喂假刘海。
func _apply_safe_area() -> void:
	var win := Rect2(Vector2(DisplayServer.window_get_position()), Vector2(DisplayServer.window_get_size()))
	var safe := Rect2(DisplayServer.get_display_safe_area()).intersection(win)
	var vp: Rect2 = get_viewport().get_visible_rect()
	var scale: float = win.size.x / vp.size.x if vp.size.x > 0.0 else 1.0
	_safe_insets = safe_insets(safe, win, scale)
	var top := $TopContainer
	top.offset_left = BASE_EDGE_X + _safe_insets[0]
	top.offset_top = BASE_TOP + _safe_insets[1]
	top.offset_right = -BASE_EDGE_X - _safe_insets[2]

## 纯算术：安全区与窗口都取**屏幕像素**、scale = 像素/设计单位。
## 返回 [左, 上, 右] 三个让位量（设计单位，已夹到 0..SAFE_CAP）。
## 窗口比安全区小时（桌面窗口化）交集就是窗口本身 ⇒ 三个 0，摆位不变。
static func safe_insets(safe: Rect2, win: Rect2, scale: float) -> Array[float]:
	var out: Array[float] = [0.0, 0.0, 0.0]
	if scale <= 0.0 or safe.size.x <= 0.0 or win.size.x <= 0.0:
		return out
	out[0] = clampf((safe.position.x - win.position.x) / scale, 0.0, SAFE_CAP)
	out[1] = clampf((safe.position.y - win.position.y) / scale, 0.0, SAFE_CAP)
	out[2] = clampf((win.end.x - safe.end.x) / scale, 0.0, SAFE_CAP)
	return out

# ---------------- 子控件构建与门面（判据 / 覆盖层 / Main 接线的兼容接口） ----------------

## 构建四块子控件，add_child 顺序保持拆分前的树序（Boss 血条 → 祭坛键 → 技能键 → FPS）
func _build_widgets() -> void:
	_boss_bar_widget = HudBossBar.new()
	add_child(_boss_bar_widget)
	_obelisk_widget = HudObeliskButton.new()
	add_child(_obelisk_widget)
	_obelisk_btn = _obelisk_widget.get_btn()
	_skill_widget = HudSkillButton.new()
	add_child(_skill_widget)
	_skill_box = _skill_widget
	_skill_btn = _skill_widget.get_btn()
	add_child(HudFpsCounter.new())

## 供冒烟测试与调试断言：血条当前是否上屏
func is_boss_bar_visible() -> bool:
	return _boss_bar_widget != null and _boss_bar_widget.is_showing()

## 供 HudEditOverlay 同步拖动代理与判据用：按钮视觉中心（设计坐标）
func skill_btn_center_px() -> Vector2:
	return _skill_widget.center_px()

func skill_btn_size_px() -> Vector2:
	return _skill_widget.size_px()

func obelisk_btn_center_px() -> Vector2:
	return _obelisk_widget.center_px()

func obelisk_btn_size_px() -> Vector2:
	return _obelisk_widget.size_px()

func _on_skill_btn_input(event: InputEvent) -> void:
	_skill_widget.handle_input(event)

func _on_obelisk_btn_input(event: InputEvent) -> void:
	_obelisk_widget.handle_input(event)

## 全局输入拦截：触屏第二根手指直通（左手拉摇杆时右手点技能，系统不再发鼠标模拟，走原生 ScreenTouch）
func _input(event: InputEvent) -> void:
	_skill_widget.handle_engine_input(event)

## 触发技能释放（判据从 HUD 门面调用）
func _trigger_skill_press() -> void:
	_skill_widget.trigger_press()

## 聚灵阵显隐与充能反馈（BlessingObelisk 信号经 Main 接到这里）
func show_obelisk_activation(ob: BlessingObelisk) -> void:
	_obelisk_widget.show_obelisk_activation(ob)

func hide_obelisk_activation(ob: BlessingObelisk) -> void:
	_obelisk_widget.hide_obelisk_activation(ob)

func on_obelisk_charge_started(ob: BlessingObelisk) -> void:
	_obelisk_widget.on_obelisk_charge_started(ob)

func on_obelisk_charge_progress(ob: BlessingObelisk, ratio: float) -> void:
	_obelisk_widget.on_obelisk_charge_progress(ob, ratio)

func on_obelisk_charge_cancelled(ob: BlessingObelisk) -> void:
	_obelisk_widget.on_obelisk_charge_cancelled(ob)

func on_obelisk_blessing_triggered(ob: BlessingObelisk) -> void:
	_obelisk_widget.on_obelisk_blessing_triggered(ob)

## 进入/退出按钮调整模式：强制亮出两颗键交给覆盖层拖动（树此时是暂停态）
func set_btn_edit_mode(on: bool) -> void:
	_skill_widget.set_edit_mode(on)
	_obelisk_widget.set_edit_mode(on)

## 打开调整覆盖层（设置·操作页「进入调整模式」调用；on_done 在调整结束后回调用）
func open_btn_edit_overlay(on_done: Callable = Callable()) -> void:
	if _edit_overlay == null:
		_edit_overlay = HudEditOverlay.new()
		get_parent().add_child(_edit_overlay)
		_edit_overlay.finished.connect(func():
			set_btn_edit_mode(false)
			_edit_overlay.visible = false
		)
	_edit_overlay.move_to_front()
	set_btn_edit_mode(true)
	_edit_overlay.open(self)
	if on_done.is_valid():
		_edit_overlay.finished.connect(on_done, CONNECT_ONE_SHOT)

# ---------------- 待加点徽记（真身 HudPendingChip，挂顶栏左组） ----------------

func _build_pending_chip() -> void:
	var chip := HudPendingChip.new(self)
	var left_box: HBoxContainer = $TopContainer/LeftBox
	left_box.add_child(chip)
	# 贴在 Lv 徽记之后（附属读数跟着主体走，不许甩到屏幕另一头）
	left_box.move_child(chip, 2)

# ---------------- 羁绊徽记 ----------------

func _refresh_synergy_badges() -> void:
	if _synergy_box == null:
		return
	for child in _synergy_box.get_children():
		child.queue_free()
	for tag in GameManager.active_synergies.keys():
		var data: Dictionary = GameManager.active_synergies[tag]
		var n: int = int(data.get("count", 0))
		if n <= 0 or not WeaponData.SYNERGIES.has(tag):
			continue
		var chip: Label = SynergyUI.create_chip(tag, 11, func(c: Control) -> void:
			_open_hud_synergy_tip(tag, c)
		)
		_synergy_box.add_child(chip)

func _open_hud_synergy_tip(tag: String, anchor: Control) -> void:
	SynergyUI.open_tip(self, anchor, tag)

## 顶栏右侧追加属性与暂停按钮（触屏入口）
func _build_top_buttons() -> void:
	var stats_btn := Button.new()
	stats_btn.text = "属 性"
	stats_btn.custom_minimum_size = Vector2(62, 0)
	stats_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stats_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	stats_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(stats_btn, GameStyle.NAVY2, GameStyle.JADE, 13, GameStyle.PAPER, 5.0, GameStyle.INK_TEXT)
	stats_btn.pressed.connect(func(): stats_requested.emit())
	$TopContainer/RightBox.add_child(stats_btn)

	var pause_btn := Button.new()
	pause_btn.text = "暂 停"
	pause_btn.custom_minimum_size = Vector2(62, 0)
	pause_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pause_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(pause_btn, GameStyle.NAVY2, GameStyle.GOLD, 13, GameStyle.PAPER, 5.0, GameStyle.INK_TEXT)
	pause_btn.pressed.connect(func(): pause_requested.emit())
	$TopContainer/RightBox.add_child(pause_btn)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		if DetailTip.close_all(self):
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE or event.keycode == KEY_SHIFT:
			if _skill_box != null and _skill_box.visible:
				_skill_widget.trigger_press()
				get_viewport().set_input_as_handled()

func _on_hp_changed(cur: float, max_v: float) -> void:
	hp_bar.max_value = max_v
	var tw = create_tween()
	tw.tween_property(hp_bar, "value", cur, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hp_label.text = str(int(cur)) + "/" + str(int(max_v))
	var low := max_v > 0.0 and (cur / max_v) < 0.28
	hp_label.add_theme_color_override("font_color", GameStyle.BAD if low else GameStyle.PAPER)

func _on_leveled_up(_lvl: int) -> void:
	var badge := $TopContainer/LeftBox/LevelBadge
	if badge != null:
		badge.pivot_offset = badge.size * 0.5
		badge.scale = Vector2(1.4, 1.4)
		var tw := badge.create_tween()
		tw.tween_property(badge, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_exp_changed(cur: int, target: int, lvl: int) -> void:
	exp_bar.max_value = target
	var tw = create_tween()
	tw.tween_property(exp_bar, "value", float(cur), 0.12)
	level_label.text = "Lv." + str(lvl)

func _on_stats_updated(kills: int, g_time: float, stones: int) -> void:
	kills_label.text = "击杀 " + str(kills)
	shards_label.text = "金币 " + str(stones)
	var mins = int(g_time / 60.0)
	var secs = int(g_time) % 60
	time_label.text = "%02d:%02d" % [mins, secs]

func _on_wave_changed(n: int) -> void:
	wave_label.text = "第 %d 波" % maxi(n, 1)
	wave_label.get_parent().visible = n >= 1

func _on_weapons_updated(weapons: Array) -> void:
	# 上阵一变就整排重建：摊在暗底下的旧详情卡报的是旧数，先收掉再建
	DetailTip.close_all(self)
	_refresh_synergy_badges()
	for child in weapons_bar.get_children():
		child.queue_free()

	for i in range(WeaponData.MAX_SLOTS):
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(36, 36)

		var filled := i < weapons.size()
		# w 在挂回调之前就得有值：GDScript lambda 按值捕获创建那一刻的局部变量
		var w: Dictionary = weapons[i] if filled else {}
		var style = GameStyle.outlined_panel(
			GameStyle.NAVY if filled else Color(GameStyle.INK.r, GameStyle.INK.g, GameStyle.INK.b, 0.55),
			GameStyle.GOLD if filled else GameStyle.LINE, 2, 5.0)
		slot.add_theme_stylebox_override("panel", style)

		if filled:
			var tex_rect = TextureRect.new()
			if w.has("icon") and ResourceLoader.exists(w["icon"]):
				tex_rect.texture = load(w["icon"])
			tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex_rect.custom_minimum_size = Vector2(26, 26)
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(tex_rect)

			GameStyle.star_label(slot, int(w.get("star", 1)), 10)

		weapons_bar.add_child(slot)
		# 整块都是热区：图框与 ★ 只是显示件，子树压成 IGNORE 才不会在槽面中间挖按不动的洞
		GameStyle.hotzone(slot)
		# 槽不是按钮，摇杆的自动收口认不出 ⇒ 自己登记，否则点一下脚下就长出一根摇杆
		slot.add_to_group(DawnJoystick.UI_PRESS_HOLD_GROUP)
		# 详情卡与属性面板/灵石阁同一工厂出，不另编一套文案
		if filled:
			GameStyle.tap(slot, func() -> void:
				StatsTipFactory.open_weapon_tip(self, slot, w, false)
			)
		else:
			GameStyle.tap(slot, func() -> void:
				StatsTipFactory.open_empty_slot_tip(self, slot, i)
			)

func show_announcement(msg: String) -> void:
	banner_label.text = msg
	banner.pivot_offset = banner.size / 2.0
	var tw = create_tween()
	tw.tween_property(banner, "modulate:a", 1.0, 0.18)
	tw.parallel().tween_property(banner, "scale", Vector2(1.08, 1.08), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(banner, "scale", Vector2.ONE, 0.1)
	tw.tween_interval(1.9)
	tw.tween_property(banner, "modulate:a", 0.0, 0.35)
