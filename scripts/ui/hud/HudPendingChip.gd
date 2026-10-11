class_name HudPendingChip
extends PanelContainer

## 顶栏「悟道 ×N」待加点徽记：只在攒了点数时出现，点按弹详情卡讲清规则。
## 为什么非要这颗：战斗中的升级不再当场弹面板，玩家只看见 Lv 跳了一下 ——
## 不告诉他「这回合结束能补几点」，就会当成加点没生效（看不见的控件就是 bug）。
## 从 GameHUD 拆出：host = 详情卡宿主（GameHUD），「上阵刷新收旧卡」判据按宿主匹配。

var _label: Label = null
var _host: Control = null
## 上一次刷新时的点数：-1 = 还没刷新过；用来区分「首现弹入」和「增长脉冲」
var _last_pending := -1
var _pop_tween: Tween = null
var _pulse_tween: Tween = null

func _init(host: Control) -> void:
	_host = host

func _ready() -> void:
	name = "PendingChip"
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 同羁绊徽记：PanelContainer 不是按钮，摇杆认不出 ⇒ 自己登记
	add_to_group(DawnJoystick.UI_PRESS_HOLD_GROUP)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_theme_stylebox_override("panel", GameStyle.chip(GameStyle.JADE))
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameStyle.label(_label, 13, GameStyle.INK_TEXT)
	add_child(_label)
	gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
			_open_tip()
	)
	GameManager.pending_points_changed.connect(func(_n: int) -> void: _refresh())
	GameManager.player_leveled_up.connect(func(_lvl: int) -> void: _refresh())
	_refresh()

func _open_tip() -> void:
	var pending := GameManager.pending_upgrade_points
	DetailTip.show_over(_host, self, {
		"title": "升级待加点",
		"chip": "回合结算",
		"chip_color": GameStyle.JADE,
		"rows": [
			["本回合攒下", "%d 点" % pending, GameStyle.JADE],
			["什么时候加", "每波敌潮平息后统一结算", GameStyle.PAPER],
			["每次给几个", "%d 个候选，可刷新" % GameManager.UPGRADE_OFFER_COUNT, GameStyle.PAPER],
		],
		"body": "战斗中升级不再打断操作：升 1 级攒 1 点，回合结束一次性加完。",
		"notes": [
			"点数必须加完才能进商店置办武器。",
			"升级候选每回合可免费刷新 1 次，之后按货架同一档价格扣金币。",
			"同一条升级有叠层上限，叠满后不再出现在候选里。",
		],
		"foot": "已领悟的条目可在「属性」面板的升级页翻看。",
	})

func _refresh() -> void:
	var pending: int = GameManager.pending_upgrade_points
	var was_visible := visible
	visible = pending > 0
	if pending <= 0:
		_last_pending = pending
		return
	_label.text = "升级 ×%d" % pending
	if not was_visible:
		_play_pop()
	elif _last_pending >= 0 and pending > _last_pending:
		_play_pulse()
	_last_pending = pending

## 首现弹入：升级攒下第 1 点时从中心弹出来 —— 徽记在闪、这颗跟着蹦，升级感才接得上。
## 文字刚设置时容器尺寸还没排版完，先等一拍再取中心 pivot，否则会从左上角缩放。
func _play_pop() -> void:
	if _pop_tween != null and _pop_tween.is_valid():
		_pop_tween.kill()
	await get_tree().process_frame
	if not visible or not is_inside_tree():
		return
	pivot_offset = size * 0.5
	modulate.a = 0.0
	scale = Vector2(0.6, 0.6)
	_pop_tween = create_tween()
	_pop_tween.set_parallel()
	_pop_tween.tween_property(self, "modulate:a", 1.0, 0.14)
	_pop_tween.tween_property(self, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## 点数增长脉冲：连升多级时 ×N 逐级蹦一下，提示「又攒了一格」
func _play_pulse() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_label.pivot_offset = _label.size * 0.5
	_label.scale = Vector2(1.35, 1.35)
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(_label, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
