class_name GameHUD
extends Control

## 顶栏暂停与属性按钮请求（由 Main 接线）
signal pause_requested
signal stats_requested
## 作者模式面板请求（仅 author_mode 时按钮可见，由 Main 接线到 AuthorPanel）
signal author_requested

@onready var hp_icon: Control = $TopContainer/LeftBox/HPBlock/HBox/HPIcon
@onready var hp_bar: ProgressBar = $TopContainer/LeftBox/HPBlock/HBox/HPBar
@onready var hp_ghost_bar: ProgressBar = $TopContainer/LeftBox/HPBlock/HBox/HPBar/HPGhostBar
@onready var hp_label: Label = $TopContainer/LeftBox/HPBlock/HBox/HPLabel
@onready var level_label: Label = $TopContainer/LeftBox/LevelBadge/VBox/LevelLabel
@onready var exp_bar: ProgressBar = $TopContainer/LeftBox/LevelBadge/VBox/ExpBar
@onready var time_label: Label = $TopContainer/CenterBox/TimeBlock/TimeLabel
@onready var wave_label: Label = $TopContainer/CenterBox/WaveChip/WaveLabel
@onready var kills_label: Label = $TopContainer/RightBox/KillsChip/KillsLabel
@onready var shards_label: Label = $TopContainer/RightBox/ShardsChip/ShardsLabel
@onready var weapons_bar: HBoxContainer = $WeaponsBar
@onready var banner: PanelContainer = $Banner
@onready var banner_label: Label = $Banner/BannerLabel

## 顶栏原本留的左右边距与顶边距（无刘海时的紧凑基准）
const BASE_EDGE_X := 10.0
const BASE_TOP := 20.0
## 让位上限：读数再大也不许被一个离谱的 safe area 推到屏心
const SAFE_CAP := 140.0

## 按钮口径与直径基准（真身在 SkillButtonView / HudObeliskButton，判据与覆盖层从这里取值）
const SKILL_BTN_SIZE := SkillButtonView.SKILL_BTN_SIZE
const OBELISK_BTN_SIZE := HudObeliskButton.BTN_SIZE
const OBELISK_BTN_TEXT := HudObeliskButton.BTN_TEXT
const OBELISK_BTN_FONT := HudObeliskButton.BTN_FONT

## 子控件（拆分自本文件）：技能键 / 额外技能键 / 祭坛键 / 魔君血条 / FPS 读数 / 待加点徽记
var _skill_widget: HudSkillButton = null
var _extra_skill_widget: HudSkillButton = null
var _obelisk_widget: HudObeliskButton = null
var _boss_bar_widget: HudBossBar = null
var _author_btn: Button = null
## 顶栏回合倒计时（画在 WaveChip 里）：「第 N 波」这条读数的唯一写者是它，
## 本文件只在控件还没建好那一拍兜个底 —— 两处拼文案就会各说各话
var wave_countdown: HudWaveCountdown = null
## 顶栏本波剩余敌数「余妖 N/M」：数据源 WaveSpawner.wave_left_count/wave_total_count，
## 与提前清场判定同源；只有 FIGHT 阶段上屏
var wave_left: HudWaveLeft = null

## 升级动效句柄（_on_leveled_up）：连升多级时信号连发，tween 全部可杀可重播
var _lv_tween: Tween = null
var _lv_label_tween: Tween = null
var _flash_tween: Tween = null
var _flash_queued: bool = false  ## 升级闪屏防重入：上一闪没淡完时排队等淡完再补，不跳峰
var _last_hp_low: bool = false  ## 血量告急色守卫：仅状态翻转时写一次 override，不每次信号都刷
var _hp_tween: Tween = null     ## 血条补间持久句柄：命中/吸血每帧都可能发信号，局部 tween 不 kill 会堆积（2026-10-13 掉帧根因）
var _exp_tween: Tween = null    ## 经验条补间持久句柄：拾宝连发同因
var _banner_tween: Tween = null ## 横幅补间持久句柄
## 低血量血条呼吸脉冲（循环 tween，脱离告急时杀掉复位）
var _hp_low_tween: Tween = null
## 徽记底色要动，但场景 stylebox 是共享资源 ⇒ 首次升级时换成私有副本再动色
var _lv_badge_style: StyleBoxFlat = null
var _lv_badge_base_bg := Color(0, 0, 0, 0)
var _lv_badge_base_border := Color(0, 0, 0, 0)
## 经验条填充同样得脱场景共享资源自己一份：.tscn 里烘的是固定色，玩家换主题色它才跟得上
var _exp_fill_style: StyleBoxFlat = null
## 全屏升级金光（_ready 里代码创建，压在 HUD 控件之下）
var _flash_rect: ColorRect = null
## 镜头缩放冲击节流：连升多级 0.2s 内只顿一次
var _last_zoom_ms := 0
## 血条/经验条 tween 创建最小间隔（2026-10-14）：高频信号闸外才补间，闸内直接写终值
const HUD_TWEEN_MIN_INTERVAL := 0.05
var _last_hp_tween_ms := 0
var _last_exp_tween_ms := 0
## 血条白影（HPGhostBar，受创两段式 2026-10-15）：红条立即落、白影延迟追平。
## 白影在主条背后透光（show_behind_parent）⇒ 掉血瞬间白影才从残血处露出来。
var _hp_ghost_tween: Tween = null
var _hp_last_cur: float = -1.0  ## 上一拍血量：判断这次信号是扣血还是回血
var _hp_text_cur: int = -1      ## 上一次写进血条文本的整数当前值（拼串去重闸）
var _hp_text_max: int = -1      ## 上一次写进血条文本的整数上限（拼串去重闸）
## 血条装饰与动效句柄
var _hp_fill_style: StyleBoxFlat = null
var _hp_block_style: StyleBoxFlat = null
var _hp_block_base_border := Color(0, 0, 0, 0)
var _hp_heal_flash: Panel = null
var _hp_heal_tween: Tween = null
var _hp_label_heal_tween: Tween = null
var _hp_icon_heal_tween: Tween = null
## 回血演出量级闸（与金币 SHARDS_PULSE_MIN_GAIN 同思路）：站定涓流等每拍 <0.5 的微涨
## 不播整套三补间强调（血条/文字照常走），只有事件型回复（吸血/回复珠一口 ≥0.5）才值得闪
const HEAL_FX_MIN_GAIN := 0.5
var _hp_notch: Control = null
## —— HUD 脉冲色硬上限（2026-10-20 真机 UI 频闪根治）——
## 项目开了 viewport/hdr_2d + Environment.glow_hdr_threshold=1.0，任何分量 >1.0 的颜色
## 都会被 WorldEnvironment glow 的屏幕空间后处理 bloom，而 UI 与世界同处根视口帧缓冲
## （Main.tscn 无 SubViewport 隔离），所以 HUD 上一处超白 = 整层 HUD 跟着 bloom 起辉。
## 战斗里 glow_intensity 还会在 0.4 与 0.25 之间升降，超白元素的辉光强度随之整帧跳变，
## 真机（Mobile 渲染器）观感就是「所有 UI 时不时闪一下/连闪几下」。
## 判据 tests/glow_channel_check.gd 会扫 scripts/ui/ 下所有 modulate 字面量，分量必须 ≤1.0。
const HP_LOW_PULSE_COLOR := Color(1.0, 0.72, 0.72)   ## 低血呼吸：纯色相转红，不发辉
const HP_HEAL_PULSE_COLOR := Color(0.35, 1.0, 0.62)  ## 回血：纯色相转碧，不发辉
const SHARDS_PULSE_COLOR := Color(1.0, 0.94, 0.66)   ## 金币进账：纯色相偏金，不发辉

## 金币增量脉冲（2026-10-15）：金币跳涨时 Label squash 回弹 + 金色驻留一闪，读得出「进账了」
const SHARDS_PULSE_MIN_GAIN := 5    ## 单拍增量阈值：低于它（单珠碎金）不闪，防常亮刷屏
const SHARDS_PULSE_GATE_MS := 150   ## 脉冲最小间隔：磁吸齐吃一拍几十金只闪一次
var _shards_pulse_tween: Tween = null
var _shards_last: int = -1
var _last_shards_pulse_ms := 0

## 兼容引用：判据（skill_check / obelisk_charge_readout_check）与覆盖层仍从 HUD 取按钮节点
var _skill_box: Control = null
var _skill_btn: Button = null
var _extra_skill_box: Control = null
var _extra_skill_btn: Button = null
var _obelisk_btn: Button = null
## 键面走针环：充能读数判据与出图台读它（拆分时漏了这一根，判据当场跑成 0 项空转）
var _obelisk_ring: SkillButtonView.CircleProgressOverlay = null

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
	$TopContainer/CenterBox/TimeBlock.add_theme_stylebox_override("panel", GameStyle.block(GameStyle.INK, GameStyle.SLANT_BLOCK, Vector2(4, 5)))
	# 场景里 .tscn 烘焙的主题粉（血条块/等级徽记底/波次字色）不经 GameStyle 工厂，
	# 注册表够不到 ⇒ 这里补一次重涂 + 订阅主题变更，换色后同拍跟上。
	_retheme_baked_styles()
	SettingsManager.theme_color_changed.connect(_on_theme_color_changed)

	var badge_lbl: Label = hp_icon.get_node_or_null("BadgeLabel") if hp_icon != null else null
	if badge_lbl != null:
		GameStyle.label(badge_lbl, 11, GameStyle.CHALK, 0, GameStyle.INK, true)
	elif hp_icon is Label:
		GameStyle.label(hp_icon, 13, GameStyle.INK_TEXT, 0, GameStyle.INK, true)
	GameStyle.label(hp_label, 14, GameStyle.INK_TEXT)
	GameStyle.label(level_label, 14, GameStyle.INK_TEXT)
	GameStyle.label(time_label, 24, GameStyle.CHALK, 0, GameStyle.INK, true)
	GameStyle.label(wave_label, 15, GameStyle.GOLD)
	GameStyle.label(kills_label, 15, GameStyle.CHALK)
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
	# 两头各出屏 82（生命块少半截、「暂停」整个没了，用户 2026-10-08 说的「顶部的一些 UI
	# 都显示到外面去了」就是这个）。判据 LayoutCheck 灌最宽读数样本量的就是这一格。
	_synergy_box = HBoxContainer.new()
	_synergy_box.add_theme_constant_override("separation", 6)
	_synergy_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_synergy_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_synergy_box.offset_left = _left_edge_x()
	_synergy_box.offset_top = 66.0
	_synergy_box.offset_right = -BASE_EDGE_X - _safe_insets[2]
	_synergy_box.offset_bottom = 88.0
	add_child(_synergy_box)
	_build_pending_chip()
	_build_level_flash()
	_build_hp_bar_decorations()

## .tscn 烘焙主题色重涂：HP 块面/底边、等级徽记面/底边、波次字色。
## 这几个节点在场景里写死了品红（Color(1,0,0.431) 系），运行时改外观只能就地改属性。
func _retheme_baked_styles() -> void:
	var hp_block: PanelContainer = $TopContainer/LeftBox/HPBlock
	if _hp_block_style == null:
		_hp_block_style = hp_block.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		hp_block.add_theme_stylebox_override("panel", _hp_block_style)
		GameStyle.register_theme_box(_hp_block_style, &"bg_color", &"main")
		GameStyle.register_theme_box(_hp_block_style, &"border_color", &"dk")
	_hp_block_style.bg_color = GameStyle.GOLD
	_hp_block_style.border_color = GameStyle.GOLD_DK
	_hp_block_base_border = GameStyle.GOLD_DK
	var badge: PanelContainer = $TopContainer/LeftBox/LevelBadge
	if _lv_badge_style == null:
		_lv_badge_style = badge.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		badge.add_theme_stylebox_override("panel", _lv_badge_style)
		GameStyle.register_theme_box(_lv_badge_style, &"bg_color", &"main")
		GameStyle.register_theme_box(_lv_badge_style, &"border_color", &"dk")
	_lv_badge_style.border_color = GameStyle.GOLD_DK
	_lv_badge_style.bg_color = GameStyle.GOLD
	_lv_badge_base_bg = GameStyle.GOLD
	_lv_badge_base_border = GameStyle.GOLD_DK
	# 经验条：槽保持纯黑，填充走主题亮边。原 .tscn 里烘的是固定增益绿，
	# 于是整块顶栏只有它不跟主题（2026-10-21 用户抓出来的：换色后经验条还是绿的）。
	if _exp_fill_style == null:
		_exp_fill_style = exp_bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
		exp_bar.add_theme_stylebox_override("fill", _exp_fill_style)
		GameStyle.register_theme_box(_exp_fill_style, &"bg_color", &"edge")
	_exp_fill_style.bg_color = GameStyle.GOLD_EDGE
	wave_label.add_theme_color_override("font_color", GameStyle.GOLD)
	# 波次字色是直接 override 的，注册一个字色条目让它跟主题一起变
	GameStyle.register_theme_label(wave_label)

## 主题色变更：重涂场景烘焙样式 + 重建横幅色块（工厂样式由注册表自动换色）
func _on_theme_color_changed(_preset: StringName) -> void:
	_retheme_baked_styles()
	banner.add_theme_stylebox_override("panel", GameStyle.block(GameStyle.GOLD, GameStyle.SLANT_BAND, Vector2(5, 6)))

## 血条斜切装饰与刻度线：
## 1. 28% 告急刻线（与 BalanceCombat.HP_LOW_RATIO 同源）：5° 斜切雕刻刻度，直观预知进入危险阈值
## 2. 治疗翡翠微闪遮罩（Panel + StyleBoxFlat 5° 斜切）：回血时温润翠光拂过
func _build_hp_bar_decorations() -> void:
	var flash_sb := StyleBoxFlat.new()
	flash_sb.bg_color = GameStyle.GOOD
	flash_sb.skew = Vector2(deg_to_rad(GameStyle.SLANT_BLOCK), 0.0)
	_hp_heal_flash = Panel.new()
	_hp_heal_flash.name = "HPHealFlash"
	_hp_heal_flash.add_theme_stylebox_override("panel", flash_sb)
	_hp_heal_flash.modulate.a = 0.0
	_hp_heal_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_heal_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hp_bar.add_child(_hp_heal_flash)

	_hp_notch = Control.new()
	_hp_notch.name = "HPNotch"
	_hp_notch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_notch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hp_bar.add_child(_hp_notch)
	_hp_notch.draw.connect(_on_hp_notch_draw)

func _on_hp_notch_draw() -> void:
	if _hp_notch == null or hp_bar == null:
		return
	var w: float = hp_bar.size.x
	var h: float = hp_bar.size.y
	if w <= 0.0 or h <= 0.0:
		return
	var x: float = w * BalanceCombat.HP_LOW_RATIO
	var skew_x: float = tan(deg_to_rad(GameStyle.SLANT_BLOCK))
	var top_x: float = x + (h * 0.5) * skew_x
	var btm_x: float = x - (h * 0.5) * skew_x
	if _last_hp_low:
		_hp_notch.draw_line(Vector2(top_x, 0.0), Vector2(btm_x, h), GameStyle.BAD, 1.5)
	else:
		_hp_notch.draw_line(Vector2(top_x - 0.5, 0.0), Vector2(btm_x - 0.5, h), Color(0.0, 0.0, 0.0, 0.55), 1.0)
		_hp_notch.draw_line(Vector2(top_x + 0.5, 0.0), Vector2(btm_x + 0.5, h), Color(1.0, 1.0, 1.0, 0.25), 1.0)

## 全屏升级金光：升级瞬间轻闪一下（对照受击红晕的反馈位，换金色、更短促）。
## 挪到首个子节点 ⇒ 画在 HUD 所有控件之下、游戏画面之上，顶栏读数不被染色。
func _build_level_flash() -> void:
	_flash_rect = ColorRect.new()
	_flash_rect.name = "LevelFlash"
	_flash_rect.color = GameStyle.with_alpha(GameStyle.JADE, 0.14)
	_flash_rect.modulate.a = 0.0
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_flash_rect)
	move_child(_flash_rect, 0)

# ---------------- 安全区让位（刘海 / 圆角 / 系统手势条） ----------------

func _left_edge_x() -> float:
	return (_safe_insets[0] + 4.0) if _safe_insets[0] > 0.0 else BASE_EDGE_X

## 顶栏整条往安全区里让：刘海会把最左那颗生命块与最右那颗暂停键吃掉一半 ——
## 桌面预览里永远是整屏，只有真机看得见，所以这条算术做成纯函数交给判据喂假刘海。
func _apply_safe_area() -> void:
	var win := Rect2(Vector2(DisplayServer.window_get_position()), Vector2(DisplayServer.window_get_size()))
	var safe := Rect2(DisplayServer.get_display_safe_area()).intersection(win)
	var vp: Rect2 = get_viewport().get_visible_rect()
	var scale: float = win.size.x / vp.size.x if vp.size.x > 0.0 else 1.0
	_safe_insets = safe_insets(safe, win, scale)
	var top := $TopContainer
	top.offset_left = _left_edge_x()
	top.offset_top = BASE_TOP + _safe_insets[1]
	top.offset_right = -BASE_EDGE_X - _safe_insets[2]
	if _synergy_box != null:
		_synergy_box.offset_left = _left_edge_x()
		_synergy_box.offset_right = -BASE_EDGE_X - _safe_insets[2]

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

## 构建五块子控件，add_child 顺序保持拆分前的树序（Boss 血条 → 祭坛键 → 技能键 → 额外技能键 → FPS）
func _build_widgets() -> void:
	_boss_bar_widget = HudBossBar.new()
	add_child(_boss_bar_widget)
	_obelisk_widget = HudObeliskButton.new()
	add_child(_obelisk_widget)
	_obelisk_btn = _obelisk_widget.get_btn()
	_obelisk_ring = _obelisk_widget.get_ring()
	_skill_widget = HudSkillButton.new()
	add_child(_skill_widget)
	_skill_box = _skill_widget
	_skill_btn = _skill_widget.get_btn()
	# 额外技能键：随角色绑定（影者=影爆），没配额外技能的角色整颗隐藏；摆位/缩放独立持久化
	_extra_skill_widget = HudSkillButton.new(true)
	add_child(_extra_skill_widget)
	_extra_skill_box = _extra_skill_widget
	_extra_skill_btn = _extra_skill_widget.get_btn()
	add_child(HudFpsCounter.new())
	# 回合倒计时：作为 WaveChip 的第二个孩子铺进同一格内容矩形 —— PanelContainer 会把
	# 所有子节点都摆成内容区，所以这颗零最小尺寸的 Control 既不改变芯片大小，又能拿到
	# 与文字同样宽的底边去画那根线（不改 .tscn、不给顶栏添新格子）。
	wave_countdown = HudWaveCountdown.new(wave_label)
	$TopContainer/CenterBox/WaveChip.add_child(wave_countdown)
	# 本波剩余敌数：第二排右缘自锚定芯片（顶栏最坏样本已零余量，见 HudWaveLeft 头注），
	# 只读 spawner 两个 int，5Hz 轮询
	wave_left = HudWaveLeft.new()
	add_child(wave_left)

## 供冒烟测试与调试断言：血条当前是否上屏
func is_boss_bar_visible() -> bool:
	return _boss_bar_widget != null and _boss_bar_widget.is_showing()

## 供 HudEditOverlay 同步拖动代理与判据用：按钮视觉中心（设计坐标）
func skill_btn_center_px() -> Vector2:
	return _skill_widget.center_px()

func skill_btn_size_px() -> Vector2:
	return _skill_widget.size_px()

func extra_skill_btn_center_px() -> Vector2:
	return _extra_skill_widget.center_px()

func extra_skill_btn_size_px() -> Vector2:
	return _extra_skill_widget.size_px()

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
	_extra_skill_widget.handle_engine_input(event)

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

## 进入/退出按钮调整模式：强制亮出三颗键交给覆盖层拖动（树此时是暂停态）
func set_btn_edit_mode(on: bool) -> void:
	_skill_widget.set_edit_mode(on)
	_extra_skill_widget.set_edit_mode(on)
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

	# 作者模式按钮：只在作者模式开启时出现，排在「属性」左边（不挤占最常用的暂停键）。
	# 宽度刻意压到 42：960 宽最坏读数（12847/12847 · Lv.99 · 第 20 波 · 击杀 12847 · 金币 99999）
	# 下顶栏本来只剩 ~42 的余量，再宽就会把「暂停」顶出屏（判据 LayoutCheck 量屏缘）。
	_author_btn = Button.new()
	_author_btn.name = "AuthorButton"
	_author_btn.text = "作者"
	_author_btn.custom_minimum_size = Vector2(42, 0)
	_author_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_author_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_author_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(_author_btn, GameStyle.BAD_DK, GameStyle.BAD, 12, GameStyle.CHALK, 5.0)
	_author_btn.pressed.connect(func(): author_requested.emit())
	$TopContainer/RightBox.add_child(_author_btn)
	$TopContainer/RightBox.move_child(_author_btn, stats_btn.get_index())
	_refresh_author_btn()
	if not GameManager.author_mode_changed.is_connected(_on_author_mode_changed):
		GameManager.author_mode_changed.connect(_on_author_mode_changed)

func _on_author_mode_changed(_enabled: bool) -> void:
	_refresh_author_btn()

func _refresh_author_btn() -> void:
	if _author_btn != null and is_instance_valid(_author_btn):
		_author_btn.visible = GameManager.author_mode

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		if DetailTip.close_all(self):
			get_viewport().set_input_as_handled()
			return
	# E 松开半拍先收祭坛键盘充能（没在充时键内自判为空操作）
	if event is InputEventKey and not event.pressed and event.keycode == KEY_E:
		_obelisk_widget.key_release()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE or event.keycode == KEY_SHIFT:
			if _skill_box != null and _skill_box.visible:
				_skill_widget.trigger_press()
				get_viewport().set_input_as_handled()
		elif event.keycode == KEY_E:
			# E 专职祭坛激活：键亮着才充能，额外技能只走鼠标/触屏
			if _obelisk_widget.can_key_charge():
				_obelisk_widget.key_press()
				get_viewport().set_input_as_handled()

func _on_hp_changed(cur: float, max_v: float) -> void:
	hp_bar.max_value = max_v
	hp_ghost_bar.max_value = max_v
	# 受创两段式（2026-10-15）：扣血拍红条立即直写（受创可读性优先，不做缓动），
	# 白影条延迟 0.25s 后 0.3s 追平 —— 红白落差就是「这一刀有多疼」的量尺；
	# 回血拍红条保持既有补间，白影同步跟随（治疗不留白影差）。
	var heal_gain: float = (cur - _hp_last_cur) if _hp_last_cur >= 0.0 else 0.0
	var is_damage := _hp_last_cur >= 0.0 and cur < _hp_last_cur
	var is_heal := heal_gain > 0.0
	_hp_last_cur = cur

	# 满血微亮：满血纯白高光，未满血温润纸白
	if _hp_fill_style == null:
		_hp_fill_style = hp_bar.get_theme_stylebox("fill").duplicate()
		hp_bar.add_theme_stylebox_override("fill", _hp_fill_style)
	var full := cur >= max_v - 0.001
	_hp_fill_style.bg_color = Color(1.0, 1.0, 1.0, 1.0) if full else GameStyle.CHALK

	if _hp_ghost_tween != null and _hp_ghost_tween.is_valid():
		_hp_ghost_tween.kill()
		_hp_ghost_tween = null
	if is_damage:
		# 白影先停在旧值（露出白影差），主条立即扣到底；白影随后追平
		hp_ghost_bar.value = hp_bar.value
		hp_bar.value = cur
		_hp_ghost_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_hp_ghost_tween.tween_interval(0.25)
		_hp_ghost_tween.tween_property(hp_ghost_bar, "value", cur, 0.3)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		if is_heal and heal_gain >= HEAL_FX_MIN_GAIN:
			_play_heal_fx()
		if _hp_tween != null and _hp_tween.is_valid():
			_hp_tween.kill()
			_hp_tween = null
		# tween 创建闸（2026-10-14）：战斗中挨打/吸血每秒十几次信号，闸外才补间、
		# 闸内直接写终值 —— kill+create 的 Tween 分配从每信号一次降到 20 次/秒上限以下
		var now_ms := Time.get_ticks_msec()
		if now_ms - _last_hp_tween_ms >= int(HUD_TWEEN_MIN_INTERVAL * 1000.0):
			_last_hp_tween_ms = now_ms
			_hp_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			_hp_tween.tween_property(hp_bar, "value", cur, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_hp_tween.parallel().tween_property(hp_ghost_bar, "value", cur, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		else:
			hp_bar.value = cur
			hp_ghost_bar.value = cur
	# 先比整数值再拼串（2026-10-21）：战斗中血量信号秒级十几次，旧写法每次 str()+str()+拼串
	# 都分配，即使显示值没变。整数没变就跳过拼串。
	var cur_i := int(cur)
	var max_i := int(max_v)
	if cur_i != _hp_text_cur or max_i != _hp_text_max:
		_hp_text_cur = cur_i
		_hp_text_max = max_i
		hp_label.text = str(cur_i) + "/" + str(max_i)
	var low := GameBalance.hp_is_low(cur, max_v)
	# 仅在告急状态翻转时写 override：战斗中挨打/吸血每秒十几次信号，
	# 每次都调 add_theme_color_override 触发 NOTIFICATION_THEME_CHANGED 是无谓开销
	if low != _last_hp_low:
		_last_hp_low = low
		hp_label.add_theme_color_override("font_color", GameStyle.BAD if low else GameStyle.INK_TEXT)
		var badge_lbl: Label = hp_icon.get_node_or_null("BadgeLabel") if hp_icon != null else null
		if badge_lbl != null:
			badge_lbl.add_theme_color_override("font_color", GameStyle.BAD if low else GameStyle.CHALK)
		elif hp_icon is Label:
			hp_icon.add_theme_color_override("font_color", GameStyle.BAD if low else GameStyle.INK_TEXT)
		if _hp_notch != null:
			_hp_notch.queue_redraw()
		if _hp_block_style == null:
			var hp_block: PanelContainer = $TopContainer/LeftBox/HPBlock
			_hp_block_style = hp_block.get_theme_stylebox("panel").duplicate()
			_hp_block_base_border = _hp_block_style.border_color
			hp_block.add_theme_stylebox_override("panel", _hp_block_style)
			# 告急期血条本体呼吸闪烁与底边描边泛红同拍：
			# 整条血槽连同外框一起起伏才是明确的濒死警报
			if _hp_low_tween != null and _hp_low_tween.is_valid():
				_hp_low_tween.kill()
				_hp_low_tween = null
			if low and GameFeel.screen_flash_enabled():
				if hp_icon != null:
					hp_icon.pivot_offset = hp_icon.size * 0.5
				_hp_low_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_loops()
				_hp_low_tween.tween_property(hp_bar, "modulate", HP_LOW_PULSE_COLOR, 0.35)\
					.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
				_hp_low_tween.parallel().tween_property(_hp_block_style, "border_color", GameStyle.BAD, 0.35)\
					.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
				if hp_icon != null:
					_hp_low_tween.parallel().tween_property(hp_icon, "scale", Vector2(1.18, 1.18), 0.35)\
						.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
				_hp_low_tween.tween_property(hp_bar, "modulate", Color.WHITE, 0.35)\
					.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
				_hp_low_tween.parallel().tween_property(_hp_block_style, "border_color", _hp_block_base_border, 0.35)\
					.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
				if hp_icon != null:
					_hp_low_tween.parallel().tween_property(hp_icon, "scale", Vector2.ONE, 0.35)\
						.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			else:
				hp_bar.modulate = Color.WHITE
				if _hp_block_style != null:
					_hp_block_style.border_color = _hp_block_base_border
				if hp_icon != null:
					hp_icon.scale = Vector2.ONE

## 回血视觉反馈（克制版，不加受击冲突反馈）：翡翠微光拂过血槽 + 血字温和回弹 + 气血图标轻跳
func _play_heal_fx() -> void:
	if _hp_heal_flash != null:
		if _hp_heal_tween != null and _hp_heal_tween.is_valid():
			_hp_heal_tween.kill()
		_hp_heal_flash.modulate.a = 0.45
		_hp_heal_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_hp_heal_tween.tween_property(_hp_heal_flash, "modulate:a", 0.0, 0.28)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	if hp_label != null:
		if _hp_label_heal_tween != null and _hp_label_heal_tween.is_valid():
			_hp_label_heal_tween.kill()
		hp_label.pivot_offset = hp_label.size * 0.5
		hp_label.scale = Vector2(1.15, 1.15)
		_hp_label_heal_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_hp_label_heal_tween.tween_property(hp_label, "scale", Vector2.ONE, 0.2)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_hp_label_heal_tween.parallel().tween_property(hp_label, "modulate", HP_HEAL_PULSE_COLOR, 0.05)
		_hp_label_heal_tween.tween_property(hp_label, "modulate", Color.WHITE, 0.15)

	if hp_icon != null:
		if _hp_icon_heal_tween != null and _hp_icon_heal_tween.is_valid():
			_hp_icon_heal_tween.kill()
		hp_icon.pivot_offset = hp_icon.size * 0.5
		hp_icon.scale = Vector2(1.2, 1.2)
		_hp_icon_heal_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_hp_icon_heal_tween.tween_property(hp_icon, "scale", Vector2.ONE, 0.22)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Lv 徽记升级组合动画：squash 回弹 + 底色金闪 + 数字脉冲 + 单圈斜切光环/星屑（HudLevelBadgeFx）。
## 可重入：连升多级时 player_leveled_up 连发，先杀旧 tween、颜色复位，再整段重播。
func _on_leveled_up(_lvl: int) -> void:
	var badge: PanelContainer = $TopContainer/LeftBox/LevelBadge
	if badge == null:
		return
	if _lv_tween != null and _lv_tween.is_valid():
		_lv_tween.kill()
	if _lv_label_tween != null and _lv_label_tween.is_valid():
		_lv_label_tween.kill()
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	# 底色金闪：场景 stylebox 是共享资源，首次先把私有副本挂上再动色
	if _lv_badge_style == null:
		_lv_badge_style = badge.get_theme_stylebox("panel").duplicate()
		_lv_badge_base_bg = _lv_badge_style.bg_color
		_lv_badge_base_border = _lv_badge_style.border_color
		badge.add_theme_stylebox_override("panel", _lv_badge_style)
	_lv_badge_style.bg_color = GameStyle.JADE
	_lv_badge_style.border_color = GameStyle.JADE_DK
	# squash & stretch：先压扁，再 TRANS_BACK 回弹过冲落位（比直线缩放更弹）
	# 幅度收在「看得出弹了一下」这一档：顶栏一直在动，压得太狠整条 UI 跟着抖
	badge.pivot_offset = badge.size * 0.5
	badge.scale = Vector2(0.88, 1.12)
	_lv_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_lv_tween.tween_property(badge, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 金色只驻留 0.26s 再渐回主蓝，杀出「跳了一下」的信号又不停在错误配色上
	_lv_tween.parallel().tween_property(_lv_badge_style, "bg_color", _lv_badge_base_bg, 0.22).set_delay(0.26)
	_lv_tween.parallel().tween_property(_lv_badge_style, "border_color", _lv_badge_base_border, 0.22).set_delay(0.26)
	# 数字脉冲：Lv 数值从中心放大回弹，视线钉在「升了几级」上
	level_label.pivot_offset = level_label.size * 0.5
	level_label.scale = Vector2(1.25, 1.25)
	_lv_label_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_lv_label_tween.tween_property(level_label, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	HudLevelBadgeFx.burst(self, badge)
	# 全屏金光：防重入——上一闪没淡完时排队，等淡完再补一次，避免 alpha 跳峰造成按钮闪
	if _flash_rect != null:
		if _flash_tween != null and _flash_tween.is_valid():
			_flash_queued = true
		else:
			_play_level_flash()
	# 震屏只给特殊场景：升级算一个，但只给最轻一档的缩放冲击，连升 0.2s 内只顿一次
	var now_ms := Time.get_ticks_msec()
	if now_ms - _last_zoom_ms >= 200:
		_last_zoom_ms = now_ms
		GameFeel.zoom_punch(GameManager, 0.025, 0.2)

## 升级金光实际播放：alpha 跳峰→淡出，结束后检查排队标记补一次
func _play_level_flash() -> void:
	if _flash_rect == null:
		return
	_flash_rect.modulate.a = 1.0
	_flash_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_flash_tween.tween_property(_flash_rect, "modulate:a", 0.0, 0.28).set_delay(0.06)
	_flash_tween.tween_callback(func():
		if _flash_queued:
			_flash_queued = false
			_play_level_flash()
	)

func _on_exp_changed(cur: int, target: int, lvl: int) -> void:
	exp_bar.max_value = target
	if _exp_tween != null and _exp_tween.is_valid():
		_exp_tween.kill()
		_exp_tween = null
	# 同血条闸：磁吸齐吃一帧几十次拾取信号，不再每发都新建 Tween
	var now_ms := Time.get_ticks_msec()
	if now_ms - _last_exp_tween_ms >= int(HUD_TWEEN_MIN_INTERVAL * 1000.0):
		_last_exp_tween_ms = now_ms
		_exp_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_exp_tween.tween_property(exp_bar, "value", float(cur), 0.12)
	else:
		exp_bar.value = float(cur)
	var lv_text := "Lv." + str(lvl)
	if level_label.text != lv_text:
		level_label.text = lv_text

func _on_stats_updated(kills: int, g_time: float, stones: int) -> void:
	# 文本去重：0.2s 节流信号里击杀/金币多数没变，相同文本不重排 Label
	var kills_text := "击杀 " + str(kills)
	if kills_label.text != kills_text:
		kills_label.text = kills_text
	var shards_text := "金币 " + str(stones)
	if shards_label.text != shards_text:
		shards_label.text = shards_text
	# 金币增量脉冲：跳涨过阈值时 Label squash 回弹（击杀数不闪——+1 离散事件闪起来是噪音）
	_pulse_shards(stones)
	var mins = int(g_time / 60.0)
	var secs = int(g_time) % 60
	var time_text := "%02d:%02d" % [mins, secs]
	if time_label.text != time_text:
		time_label.text = time_text

## 金币进账脉冲（2026-10-15）：单拍增量过阈值且过 0.15s 闸才闪一次，防止磁吸齐吃
## 一拍几十金变成常亮。squash 用 TRANS_BACK 回弹落位，与升级徽记同一套手感；
## 金色驻留 0.18s 渐回（金币芯片底色本来就是点缀黄，闪的是字色白→金→白读不出，
## 改闪 Label 整体 scale + 字色加深一拍，芯片不换色）。
func _pulse_shards(stones: int) -> void:
	if _shards_last < 0:
		_shards_last = stones
		return
	var gain := stones - _shards_last
	_shards_last = stones
	if gain < SHARDS_PULSE_MIN_GAIN:
		return
	var now_ms := Time.get_ticks_msec()
	if now_ms - _last_shards_pulse_ms < SHARDS_PULSE_GATE_MS:
		return
	_last_shards_pulse_ms = now_ms
	if _shards_pulse_tween != null and _shards_pulse_tween.is_valid():
		_shards_pulse_tween.kill()
	shards_label.pivot_offset = shards_label.size * 0.5
	shards_label.scale = Vector2(1.25, 1.25)
	_shards_pulse_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_shards_pulse_tween.tween_property(shards_label, "scale", Vector2.ONE, 0.22)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_shards_pulse_tween.parallel().tween_property(shards_label, "modulate", SHARDS_PULSE_COLOR, 0.05)
	_shards_pulse_tween.parallel().tween_property(shards_label, "modulate", Color.WHITE, 0.2).set_delay(0.05)

func _on_wave_changed(n: int) -> void:
	wave_label.get_parent().visible = n >= 1
	# 文案交给回合倒计时控件写（它与剩余时间同一条读数、同一次取值）；
	# _ready 里这一次调用发生在控件建好之前，所以留一条纯波号的兜底。
	if wave_countdown != null:
		wave_countdown.refresh_now()
	else:
		wave_label.text = HudWaveCountdown.wave_head(n)

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
			GameStyle.NAVY if filled else GameStyle.with_alpha(GameStyle.INK, 0.55),
			GameStyle.GOLD if filled else GameStyle.LINE, 2, 5.0)
		slot.add_theme_stylebox_override("panel", style)

		if filled:
			var tex_rect := GameStyle.icon_texture_rect(
				String(w.get("icon", "")),
				Vector2(26, 26)
			)
			slot.add_child(tex_rect)

			GameStyle.star_label(slot, int(w.get("star", 1)), 10)

		weapons_bar.add_child(slot)
		# 整块都是热区：图框与 ★ 只是显示件，子树压成 IGNORE 才不会在槽面中间挖按不动的洞
		GameStyle.hotzone(slot)
		# 槽不是按钮，摇杆的自动收口认不出 ⇒ 自己登记，否则点一下脚下就长出一根摇杆
		slot.add_to_group(DawnJoystick.UI_PRESS_HOLD_GROUP)
		# 详情卡与属性面板/金币阁同一工厂出，不另编一套文案
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
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var tw := _banner_tween
	tw.tween_property(banner, "modulate:a", 1.0, 0.18)
	tw.parallel().tween_property(banner, "scale", Vector2(1.08, 1.08), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(banner, "scale", Vector2.ONE, 0.1)
	tw.tween_interval(1.9)
	tw.tween_property(banner, "modulate:a", 0.0, 0.35)
