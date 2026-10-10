class_name HudPendingChip
extends PanelContainer

## 顶栏「悟道 ×N」待加点徽记：只在攒了点数时出现，点按弹详情卡讲清规则。
## 为什么非要这颗：战斗中的升级不再当场弹面板，玩家只看见 Lv 跳了一下 ——
## 不告诉他「这回合结束能补几点」，就会当成加点没生效（看不见的控件就是 bug）。
## 从 GameHUD 拆出：host = 详情卡宿主（GameHUD），「上阵刷新收旧卡」判据按宿主匹配。

var _label: Label = null
var _host: Control = null

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
	visible = pending > 0
	if pending > 0:
		_label.text = "升级 ×%d" % pending
