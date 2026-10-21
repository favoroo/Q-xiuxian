extends Node

## 判据：图鉴「打开不重铺」——五页按页懒建、静态页同筛选复用、动态页每次 open 重铺。
## 运行: $G --headless --path . res://tests/CodexOpenReuseCheck.tscn
##
## 为什么立这条（用户 2026-10-12 真机：灵石阁点「图鉴」先顿一下才弹出来）：
## 旧 ManualDialog 一次 open 把整本手册重铺一遍，武器页还铺两遍（open() 里一次、
## open_weapons_page() 里一次），实测按下后主线程同步占住 124~181 ms（M 系 Mac，
## 五页全量约 1900 节点）。修法是「按页懒建 + 脏标记 + 铺卡晚一帧」（ManualDialog
## ._ensure_page / ._build_page / ._schedule_page），而这类优化最容易被一句
## 「顺手在 open() 里再 rebuild 一下」悄悄改回去，所以钉成判据：
## ① 没被看到过的页不许铺（懒建在干活）；
## ② 当前页两帧内必须有内容（懒建不许变成永远不建）；
## ③ 同筛选重复 open：武器页还是同一批卡对象（静态表，复用）；
## ④ 法宝页每次 open 重铺（受解锁状态影响，不许复用），但重铺排在按下那一拍之后
##    —— open() 返回的那一帧卡对象必须还是旧的（这一条就是「不顿」本身）；
## ⑤ 换筛选必须重铺、数量跟着筛选走（复用不许把内容冻住）。
##
## 反例自证（2026-10-12 逐条打过）：拆掉 _build_page 的「建过就复用」锁 ⇒ ③ 报红；
## 拆掉 _set_weapon_filter 的标脏 ⇒ ③ 报红；把 open 改成同步重铺五页 ⇒ ① 报红；
## 把 _schedule_page 换成当场 _build_page ⇒ ④ 的第一顶报红。

var _c := TestCheck.new()
var _m: ManualDialog

func _ready() -> void:
	get_tree().root.size = Vector2i(960, 540)
	Engine.time_scale = 4.0
	_m = ManualDialog.new()
	add_child(_m)
	await _settle(2)

	# ① 打开落在武器页：只建当前页，其余页还是空壳
	_m.open()
	await _settle(3)
	_c.check(_cards_in(_m._weapons_box).size() > 0, "当前页两帧内已铺上卡（懒建没变成不建）")
	_c.equals(_cards_in(_m._items_box).size(), 0, "武器页在显示时，道具页没被顺手铺出来")
	_c.equals(_cards_in(_m._cult_box).size(), 0, "武器页在显示时，角色页没被顺手铺出来")
	var wpn_first := _first_id(_m._weapons_box)

	# ② 同筛选再开一次：整页复用，卡对象没换、按下那一拍也没往里添新子节点
	_m.close()
	await _wait_closed()
	var wpn_children := _m._weapons_box.get_child_count()
	_m.open()
	_c.equals(_m._weapons_box.get_child_count(), wpn_children,
		"open() 那一拍没动武器页（铺卡不占按下这一帧）")
	await _settle(3)
	_c.equals(_first_id(_m._weapons_box), wpn_first, "同筛选再开：武器页整页复用，没重铺")
	_c.check(_cards_in(_m._weapons_box).size() > 0, "复用后卡还在（%d 张）" % _cards_in(_m._weapons_box).size())

	# ③ 道具页受解锁状态影响：每次 open 要重铺，但重铺排在按下那一拍之后
	#    （量子节点数而不是量首张卡：queue_free 的旧卡当帧还挂在树上，
	#     拿「第一张卡是谁」去判断有没有重铺，会把同步重铺看成没发生）
	_m.switch_tab(1)
	await _settle(3)
	var item_first := _first_id(_m._items_box)
	var item_children := _m._items_box.get_child_count()
	_c.check(item_first != 0, "法宝页切过去才铺（%d 张）" % _cards_in(_m._items_box).size())
	_m.close()
	await _wait_closed()
	_m.open()
	_c.equals(_m._items_box.get_child_count(), item_children, "open() 那一拍也没重铺法宝页")
	await _settle(3)
	var item_second := _first_id(_m._items_box)
	_c.check(item_second != 0 and item_second != item_first, "再开一次：法宝页重铺（解锁状态会变，不许复用）")

	# ④ 换筛选：必须重铺，且只剩该流派
	var want_fire := _tag_total("fire")
	_m.open_weapons_page("fire")
	await _settle(3)
	_c.check(_first_id(_m._weapons_box) != wpn_first, "切到火系筛选：武器页重铺")
	_c.equals(_cards_in(_m._weapons_box).size(), want_fire, "重铺后只剩火系 %d 把" % want_fire)

	get_tree().quit(0 if _c.report("CODEX_REUSE_RESULT") else 1)

# ================================ 取数 ================================

## 卡 = _make_entry_card 打的 tip_title 标；旧树 queue_free 后要过一帧才从树上摘掉，
## 所以每个断言前都 await 过帧（④ 的「那一拍还是旧的」量的正是 open() 返回时那一帧）
func _cards_in(root: Node) -> Array[Control]:
	var out: Array[Control] = []
	_collect(root, out)
	return out

func _collect(node: Node, out: Array[Control]) -> void:
	if node is Control and node.has_meta("tip_title"):
		out.append(node as Control)
	for ch in node.get_children():
		_collect(ch, out)

func _first_id(box: Node) -> int:
	var cards := _cards_in(box)
	return 0 if cards.is_empty() else cards[0].get_instance_id()

## 火系把数从 DEFS 现数，不抄死（加武器/改归属后本判据自动跟表）
func _tag_total(tag: String) -> int:
	var n := 0
	for wid in WeaponData.DEFS.keys():
		if tag in WeaponData.tags_of(String(wid)):
			n += 1
	return n

## 等 close() 的淡出动画收口：没关严就 open() 会被 BaseModalDialog 的防重入直接吃掉
func _wait_closed() -> void:
	for _i in range(400):
		if not _m.visible:
			return
		await get_tree().process_frame
	_c.check(false, "close() 没收口，后面的用例全不可信")

func _settle(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame
