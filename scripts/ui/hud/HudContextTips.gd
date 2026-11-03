class_name HudContextTips
extends CanvasLayer

## 局内一次性情境提示气泡（T3：首进商店 / 首遇藏宝匣 / 聚灵阵 / 精英怪）。
## 视觉复用 DetailTip 那一套（墨面板 + 主题色描边 + 硬墨影），但**非模态**：
## 不暂停、不抢焦点、不铺遮罩 —— 只有气泡自己那一条矩形接点按（点按即收），
## 其余区域照常走位开火；几秒后自消，不打断战斗节奏。
##
## 挂载：独立 CanvasLayer（layer 12 > UILayer 10），商店暂停时也能盖在面板上；
## GameHUD._ready 里 attach(self) 一行挂上（与 HudShieldBar.attach 同模式），不改 Main.tscn。
## 触发链路：触发点 emit GameManager.context_tip_requested(tip_id) → 这里按
## SettingsManager 的「已看过」键（ui/ctx_tip_<id>）门控，弹出当刻落盘，之后跨会话永不复弹。

## 自动消失时长（秒）：自消兜底，点按可提前收
const AUTO_HIDE_SEC := 3.6
const FADE_IN := 0.15
const FADE_OUT := 0.2
## 纵向落点：顶栏血条在 y≈20~62、播报横幅在 y≈84~122，提示条顶在横幅之下；
## 摇杆/技能键与武器栏都在屏幕下缘 —— 这里两头都不压（避开准星与血条区）
const TOP_Y := 132.0
## 距屏边的最小横距（窄屏兜底）
const EDGE_X := 8.0

## 五个触发点的文案（每条 = [标题, 一句机制说明]；术语只用项目通用词：金币/道具/武器/灵兽/回合）
const TIPS: Dictionary = {
	&"shop": ["金币阁", "回合间隙花金币买武器道具"],
	&"chest": ["藏宝匣", "打碎掉金币和道具"],
	&"obelisk": ["聚灵阵", "站进去充能领灵兽"],
	&"elite": ["精英怪", "血厚招狠，击杀掉好货"],
	&"mechanism": ["机关", "空地按「布设」，靠近站定长按「维修」（机关停火），旁边「收回」键撤回"],
}

var _bubble: PanelContainer = null
var _title_lbl: Label = null
var _body_lbl: Label = null
var _tween: Tween = null

## 挂载到 HUD（重复调用幂等）
static func attach(hud: Control) -> void:
	if hud == null:
		return
	if hud.get_node_or_null("ContextTipsLayer") != null:
		return
	var layer := HudContextTips.new()
	layer.name = "ContextTipsLayer"
	hud.add_child(layer)

func _ready() -> void:
	layer = 12
	# 商店开着时整棵树是暂停的，气泡要照常能点收/自消
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not GameManager.context_tip_requested.is_connected(_on_tip_requested):
		GameManager.context_tip_requested.connect(_on_tip_requested)

## 判据读数：气泡当前是否在屏（含淡出途中）
func is_showing() -> bool:
	return _bubble != null and is_instance_valid(_bubble) and _bubble.visible

func current_text() -> String:
	if not is_showing():
		return ""
	return _title_lbl.text + _body_lbl.text

func _on_tip_requested(tip_id: StringName) -> void:
	var tip: Variant = TIPS.get(tip_id, null)
	if tip == null:
		return
	if SettingsManager.context_tip_seen(tip_id):
		return
	# 弹出当刻即落盘：哪怕随后杀进程，这条提示也不再出现
	SettingsManager.mark_context_tip_seen(tip_id)
	_show(String(tip[0]), String(tip[1]))

func _show(title: String, body: String) -> void:
	_kill_tween()
	if _bubble == null or not is_instance_valid(_bubble):
		_build_bubble()
	_title_lbl.text = title
	_body_lbl.text = body
	_bubble.visible = true
	_bubble.modulate.a = 0.0
	# 气泡宽按内容定，等容器量出尺寸再居中；当帧 size 还是 0，推迟一拍摆位
	_place.call_deferred()
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(_bubble, "modulate:a", 1.0, FADE_IN)
	_tween.tween_interval(AUTO_HIDE_SEC)
	_tween.tween_property(_bubble, "modulate:a", 0.0, FADE_OUT)
	_tween.tween_callback(_bubble.hide)

func _dismiss() -> void:
	if not is_showing():
		return
	_kill_tween()
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(_bubble, "modulate:a", 0.0, FADE_OUT)
	_tween.tween_callback(_bubble.hide)

func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null

func _build_bubble() -> void:
	_bubble = PanelContainer.new()
	_bubble.name = "ContextTipBubble"
	_bubble.visible = false
	_bubble.mouse_filter = Control.MOUSE_FILTER_STOP
	# 气泡不是按钮，摇杆认不出 ⇒ 自己登记：点在泡上不该顺手在脚下长出摇杆
	_bubble.add_to_group(DawnJoystick.UI_PRESS_HOLD_GROUP)
	var sb := GameStyle.outlined_panel(
		GameStyle.with_alpha(GameStyle.NAVY, 0.99), GameStyle.GOLD, 2, GameStyle.SLANT_PLATE)
	sb.shadow_color = GameStyle.INK
	sb.shadow_size = 1
	sb.shadow_offset = Vector2(4, 4)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	_bubble.add_theme_stylebox_override("panel", sb)
	add_child(_bubble)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.add_child(row)

	_title_lbl = Label.new()
	_title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameStyle.label(_title_lbl, 13, GameStyle.GOLD, 0, GameStyle.INK, true)
	row.add_child(_title_lbl)

	_body_lbl = Label.new()
	_body_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameStyle.label(_body_lbl, 13, GameStyle.PAPER)
	row.add_child(_body_lbl)

	# 点按即收（与 DetailTip 同一口径：只认左键，触屏合成事件同一条路）
	GameStyle.tap(_bubble, _dismiss)
	_bubble.resized.connect(_place)

func _place() -> void:
	if not is_showing():
		return
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		vp = Vector2(960, 540)
	var sz := _bubble.size
	if sz.x <= 0.0:
		sz = _bubble.get_combined_minimum_size()
	_bubble.position = Vector2(
		clampf((vp.x - sz.x) * 0.5, EDGE_X, maxf(EDGE_X, vp.x - sz.x - EDGE_X)), TOP_Y)
