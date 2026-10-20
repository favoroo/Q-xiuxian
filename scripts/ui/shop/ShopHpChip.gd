class_name ShopHpChip
extends PanelContainer

## 商店顶栏的生命徽记：摆在「金币 n」左边那颗「心 生命 87/120」。
##
## 为什么非要这一颗（2026-10-11 用户真机：「商店界面也要显示生命，
## 不然也不知道回复道具要不要买」）：买不买回复药是一次当场决定，而这一屏原先只印金币 ——
## 血条在战斗 HUD 上，商店面板一盖就没了，等于闭眼花钱。读数要贴在决策发生的那一屏，
## 不能指望人记住刚才挨了多少下。
##
## 三条口径：
## ① 数字与 HUD 那行血字同一个格式（int(cur)/int(max)），分档取色走 GameBalance.hp_is_low，
##    两边不许各判各的（抄一份阈值就是一份永远不会跟着改的假账）。
## ② 危险那一档整块翻朱砂底 + 墨字：满屏就它最亮，不用读数字也知道该不该吃药。
## ③ 点按可得拆解（触屏无 hover，tooltip 等于没做）：上限、每秒回复、
##    以及「这一颗丹现在实际回多少」——最后那个数与货架卡、与 ShopSystem 真喂给 heal()
##    的量同一条公式（GameBalance.potion_effective_heal）。

const ICON_PATH := "res://assets/art/icon_hp.png"
const FONT_SIZE := 16
const ICON_SIZE := 18.0
## 面内边距：与 WaveShop.tscn 里那颗金币徽记的 14/5 同一档（斜切面贴字会糊到边上）
const FACE_PAD_X := 12.0
const FACE_PAD_Y := 4.0

var _host: Control = null
var _label: Label = null
var _icon: TextureRect = null
var _cur: float = 0.0
var _max: float = 0.0

func _init(host: Control) -> void:
	_host = host

func _ready() -> void:
	name = "HpChip"
	mouse_filter = Control.MOUSE_FILTER_STOP
	# PanelContainer 不是按钮，摇杆认不出 ⇒ 自己登记（同 HudPendingChip 与羁绊徽记）
	add_to_group(DawnJoystick.UI_PRESS_HOLD_GROUP)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var row := HBoxContainer.new()
	row.name = "HpRow"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 5)
	add_child(row)

	var icon := GameStyle.icon_texture_rect(ICON_PATH, Vector2(ICON_SIZE, ICON_SIZE))
	_icon = icon
	icon.name = "HpIcon"
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	_label = Label.new()
	_label.name = "HpValue"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_label)

	# 整块都是热区：徽记一共就那么大，只把文字那一小条接上事件，真机上就是「点了没反应」
	GameStyle.tap(self, _open_tip)
	_paint()

## 由 WaveShop 在每次 refresh 时喂进来（开店、买药、重掷后都会重画）。
## add_child 之前也能调：那时 _label 还不存在，值先记下，_ready 里统一画第一遍。
func set_value(cur: float, max_v: float) -> void:
	_cur = cur
	_max = max_v
	if _label != null:
		_paint()

## 判据读数：徽记现在印的那串字（与 HUD 血字同格式）
func get_value_text() -> String:
	return _label.text if _label != null else ""

func _paint() -> void:
	var low := GameBalance.hp_is_low(_cur, _max)
	var face := GameStyle.BAD if low else GameStyle.NAVY2
	# 独立实例色签：要改 content_margin（chip() 是共享缓存，改 margin 会污染别处的同色签）
	var sb := GameStyle.chip_of(face)
	# 与「金币」那颗同一档内边距（.tscn 里是 14/5）：贴着字走的斜切面，字会糊到画出来的边上
	sb.content_margin_left = FACE_PAD_X
	sb.content_margin_right = FACE_PAD_X
	sb.content_margin_top = FACE_PAD_Y
	sb.content_margin_bottom = FACE_PAD_Y
	add_theme_stylebox_override("panel", sb)
	# 危险那一档心形跟着压成墨色：朱砂底上一颗红心等于没有，黑字配黑形才读得出那颗图标
	if _icon != null:
		_icon.modulate = GameStyle.INK if low else Color.WHITE
	# 危险 = 朱砂底配墨字（与金币那颗同一条「亮面配黑字」口径）；满血 = 增益绿；其余纸白
	var txt := GameStyle.INK_TEXT if low else (
			GameStyle.GOOD if GameBalance.hp_is_full(_cur, _max) else GameStyle.PAPER)
	GameStyle.label(_label, FONT_SIZE, txt)
	# 带「生命」两个字，与旁边那颗「金币 34」配成一对：两颗都是这一屏仅有的资源读数，
	# 一个只给数字、一个给词，读起来就像两类东西（心形图标管扫不管认）
	_label.text = "生命 %d/%d" % [int(_cur), int(_max)]

func _open_tip() -> void:
	var stats: Dictionary = GameManager.get_player_stat_dict()
	var max_hp: float = float(stats.get("max_hp", _max))
	var cur_hp: float = float(stats.get("current_hp", _cur))
	var regen: float = float(stats.get("hp_regen", 0.0))
	var nominal := GameBalance.potion_heal_amount(max_hp)
	var effective := GameBalance.potion_effective_heal(max_hp, cur_hp)
	var low := GameBalance.hp_is_low(cur_hp, max_hp)
	var rows: Array = [
		["当前生命", "%d / %d" % [int(cur_hp), int(max_hp)],
			GameStyle.BAD if low else GameStyle.PAPER],
		["每秒回复（战斗中）", "+%s" % BonusRows.fmt_num(regen),
			GameStyle.GOOD if regen > 0.0 else GameStyle.GREY],
		["回复药这一口", "+%d" % int(round(effective)),
			GameStyle.GOOD if effective > 0.5 else GameStyle.BAD],
	]
	DetailTip.show_over(_host, self, {
		"title": "生命",
		"chip": "买不买回复道具就看这一格",
		"chip_color": GameStyle.BAD if low else GameStyle.JADE,
		"rows": rows,
		"body": "商店这一屏不会自动回血：现在多少，进下一回合就是多少。",
		"notes": [
			"回复药按生命上限的 %d%% 结算（满上限是 %d 点），上限越高回得越多。" % [
				int(round(GameBalance.POTION_HEAL_RATIO * 100.0)), int(round(nominal))],
			"回不上的那一截不折算成任何东西：现在这一口只吃得到 %d，满血时买就是白花钱。" % int(round(effective)),
			"战斗里掉的回复珠按缺血回血，回不上的那截折成金币；丹药没有这条折算。",
			"生命上限来自悟道加点与部分道具，回合间不会自己涨。",
		],
		"foot": "全部加成来源在顶栏「属性」面板里逐条可查。",
	})
