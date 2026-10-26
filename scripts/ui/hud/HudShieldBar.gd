class_name HudShieldBar
extends RefCounted

## HUD 血条护盾覆盖段（2026-10-25 血海护盾·体修进阶神通）：把 GameManager.shield_hp
## 以一道半透明靛青覆盖段叠在血条填充之上，盾量从左侧起算、宽度 = 盾 / 盾上限。
##
## 为什么独立成 hud/ 子目录模块：GameHUD 是核心热区大文件，护盾显示只有「建一条覆盖
## + 两路刷新」这点事，全部收在这里；GameHUD 只加 attach/refresh 两行调用。
## 刷新走两路：shield_changed（结盾/吸盾/碎盾）+ 宿主 _on_hp_changed（生命上限变化改盾宽）。

const SHIELD_TINT := Color(0.55, 0.85, 1.0, 0.55)  ## 靛青盾色：与血红/纸白底拉开，不抢濒死警报
## 盾量变化补间时长：与血条本体同节奏（GameHUD 血条 0.15s）。
## 旧写法盾条瞬跳、血条平滑 —— 挨打那一刻两条读数错位，读起来像「血没掉但盾没了」。
const SHIELD_TWEEN := 0.15

## 挂载：在血条内叠一条全幅 ProgressBar 覆盖层，并接好两路刷新信号。重复调用幂等。
static func attach(hud) -> void:
	if hud == null or hud.hp_bar == null:
		return
	if hud.get("_shield_bar") != null:
		return
	var bar := ProgressBar.new()
	bar.name = "ShieldBar"
	bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 0.0
	bar.show_percentage = false
	bar.visible = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0)
	bg.draw_center = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = SHIELD_TINT
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	hud.hp_bar.add_child(bar)
	hud.set("_shield_bar", bar)
	if not GameManager.shield_changed.is_connected(_on_shield_changed.bind(hud)):
		GameManager.shield_changed.connect(_on_shield_changed.bind(hud))
	refresh(hud)

## 刷新覆盖段宽度与显隐（零盾直接藏掉，不留一道空槽误导）
static func refresh(hud) -> void:
	var bar: ProgressBar = hud.get("_shield_bar")
	if bar == null:
		return
	var shield: float = GameManager.shield_hp
	if shield <= 0.05:
		bar.visible = false
		bar.value = 0.0
		_kill_tween(hud)
		return
	var cap := BalanceChain.shield_cap(GameManager.player.max_health) \
		if GameManager.player != null and is_instance_valid(GameManager.player) else 1.0
	bar.max_value = maxf(cap, 1.0)
	bar.visible = true
	_tween_to(hud, bar, shield)

## 补间到目标盾量（与血条 0.15s 同节奏）；结盾瞬间（从 0 起）直接落值，不做「从零长出来」的假动作
static func _tween_to(hud, bar: ProgressBar, target: float) -> void:
	_kill_tween(hud)
	if not bar.visible or bar.value <= 0.0:
		bar.value = target
		return
	var tw: Tween = bar.create_tween()
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(bar, "value", target, SHIELD_TWEEN)
	hud.set("_shield_tween", tw)

static func _kill_tween(hud) -> void:
	var tw: Tween = hud.get("_shield_tween")
	if tw != null and tw.is_valid():
		tw.kill()
	hud.set("_shield_tween", null)

static func _on_shield_changed(_shield: float, _cap: float, hud) -> void:
	if hud == null or not is_instance_valid(hud):
		return
	refresh(hud)
