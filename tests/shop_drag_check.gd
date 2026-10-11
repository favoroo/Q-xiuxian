extends Node

## 判据：灵石阁陈列行「按住拎起 → 拖到目标格放下」的拖拽换装（背包与上阵互相拖动换位）。
## 运行: $G --headless --path . res://tests/ShopDragCheck.tscn
##       $G --headless --path . res://tests/ShopDragCheck.tscn -- --selftest （验尺子有牙齿）
##
## 为什么立这条（用户 2026-10-11：背包里的装备和已佩戴的装备要能拖动换位，拖到背包＝卸下、
## 拖到上阵格＝佩戴）：数据层的装备/卸下早就有（点按详情卡里的按钮），但满仓时换一件要
## 「点开卡 → 找按钮 → 关卡」三步；拖拽一步到位。手势必须与陈列行横滑共存 —— 按住不动才
## 拎起（HOLD_DELAY），按住后先划出去就是横滑（ShopRowScrollCheck 那一套照旧不能破）。
##
## 尺子清单：
## ① 数据层：swap_into_equipped 上阵未满＝装备、已满＝互换（换下的一件回背包原位），
##   非灵宝且无玩家节点时先验后动不拆半截；equip_stash_into_slot 拖拽落点语义
##   （空格/越界＝直接装备、已占用格＝替换且不满员也替换）、swap_equipped_slots
##   同池互换（i==j / 越界 / 混池＝false）；reorder_stash 顺移、越界夹取、原地不动＝false；
## ② 按住 HOLD_DELAY 才拎起：幽灵出现、原格压暗，且拎起时整排没被拖走；
## ③ 拖着走整排不许跟着滑（ OwnedScroll 已在按下那一拍 latch，拖动中的 motion 必须被截走）；
## ④ 拖背包件到已佩戴的武器格放下＝替换那一格（上阵已满样本），数据对、选中清空、详情卡没残留；
## ⑤ 拖上阵件到「背包」分隔签放下＝卸下成功；
## ⑥ 背包件拖到另一个背包格＝背包内排序；
## ⑥b 上阵件拖到另一个上阵格＝互换位置（同池）；
## ⑥c 背包件拖到上阵空格＝直接装备（上阵区固定画满上限格数，空格也是落点）；
## ⑦ 按住后先划出去＝横滑（不拎起、数据不动、motion 照常送到 OwnedScroll）；
## ⑧ 快速点按照旧选中弹卡（拖拽登记没把点按吃掉）。
## 反例（--selftest）：按住不满时限拎不起来；上阵件拖到上阵空格＝不接（数据原样）。

const VP := Vector2(1202, 540)
const EPS := 1.5

var _c := TestCheck.new()
var _shop: WaveShop
var _scroll: ScrollContainer
var _row: HBoxContainer

func _ready() -> void:
	get_tree().root.size = VP
	await _test_inventory_ops()
	await _test_gesture()
	get_tree().quit(0 if _c.report("SHOP_DRAG_RESULT") else 1)

# ================================ ① 数据层 ================================

## headless 没有 Player 节点：上阵池用 drones 灌（与 ShopRowScrollCheck 同一手法），
## 背包件也只用 DRONE 行为的武器（haojin_lun/lihuo_ya），悬浮法器那半边根本不被碰到。
func _test_inventory_ops() -> void:
	GameManager.reset_run()

	# reorder_stash：顺移 + 越界夹取 + 原地不动
	GameManager.stash = _fake_stash(["a", "b", "c", "d"])
	_c.check(GameManager.reorder_stash(0, 2), "reorder_stash(0→2) 成立")
	_c.check(_stash_ids() == ["b", "c", "a", "d"], "reorder_stash 顺移：[a,b,c,d] → [b,c,a,d]，实得 %s" % str(_stash_ids()))
	_c.check(not GameManager.reorder_stash(3, 99), "reorder_stash 越界夹回原地（from==to）＝false 不算操作")
	_c.check(not GameManager.reorder_stash(-1, 0), "reorder_stash 负下标＝false")
	_c.check(GameManager.reorder_stash(0, 99), "reorder_stash to 超限夹到队尾仍成立")
	_c.check(_stash_ids() == ["c", "a", "d", "b"], "夹到队尾的顺移结果对：[c,a,d,b]，实得 %s" % str(_stash_ids()))

	# swap_into_equipped：上阵已满＝互换，换下的一件回背包原位
	GameManager.drones = _fake_drones(6, "lingdie")
	GameManager.stash = _fake_stash(["haojin_lun"])
	_c.check(GameManager.swap_into_equipped(0, 2), "上阵满时 swap_into_equipped 成立（换装）")
	_c.check(GameManager.drones.size() == 6, "换装后上阵数量不变（6）")
	_c.check(WeaponInventory.drone_id(GameManager.drones[5]) == "haojin_lun", "背包件顶上（灵宝进 drones 队尾）")
	_c.check(GameManager.stash.size() == 1 and String(GameManager.stash[0].get("id", "")) == "lingdie",
		"换下的一件回到背包被腾出的原位（stash[0]=lingdie），实得 %s" % str(_stash_ids()))

	# swap_into_equipped：上阵未满＝退化为直接装备
	GameManager.drones = _fake_drones(2, "lingdie")
	GameManager.stash = _fake_stash(["lihuo_ya"])
	_c.check(GameManager.swap_into_equipped(0, 0), "上阵未满时 swap_into_equipped 退化为装备")
	_c.check(GameManager.drones.size() == 3 and WeaponInventory.drone_id(GameManager.drones[2]) == "lihuo_ya",
		"未满路径把背包件装上了（drones 第 3 件=lihuo_ya）")
	_c.check(GameManager.stash.is_empty(), "装备后背包件离场")

	# swap_into_equipped：下标不合法 / 非灵宝且无玩家节点＝先验后动，背包不动半截
	GameManager.drones = _fake_drones(6, "lingdie")
	GameManager.stash = _fake_stash(["qingyun_sword"])
	var before: Array = _stash_ids()
	_c.check(not GameManager.swap_into_equipped(5, 0), "背包下标越界＝false")
	_c.check(not GameManager.swap_into_equipped(0, 99), "上阵下标越界＝false")
	_c.check(not GameManager.swap_into_equipped(0, 0),
		"非灵宝件在无玩家节点时拒绝换装（headless 防线，不拆半截）")
	_c.check(_stash_ids() == before, "拒绝路径背包原样不动")

	# equip_stash_into_slot：拖拽落点语义 —— 已占用格＝替换（不满员也替换），换下的回背包原位
	GameManager.drones = _fake_drones(2, "lingdie")
	GameManager.stash = _fake_stash(["haojin_lun"])
	_c.check(GameManager.equip_stash_into_slot(0, 1), "未满员拖到已佩戴格＝替换（equip_stash_into_slot）")
	_c.check(GameManager.drones.size() == 2 and WeaponInventory.drone_id(GameManager.drones[1]) == "haojin_lun",
		"被指中的那一格被替换（drones[1]=haojin_lun）")
	_c.check(GameManager.stash.size() == 1 and String(GameManager.stash[0].get("id", "")) == "lingdie",
		"换下的一件回背包被腾出的原位（stash[0]=lingdie），实得 %s" % str(_stash_ids()))

	# equip_stash_into_slot：空格（下标到 summary 尾部之外）＝直接装备
	GameManager.drones = _fake_drones(2, "lingdie")
	GameManager.stash = _fake_stash(["lihuo_ya"])
	_c.check(GameManager.equip_stash_into_slot(0, 5), "拖到空上阵格＝直接装备（越到 summary 之外）")
	_c.check(GameManager.drones.size() == 3 and WeaponInventory.drone_id(GameManager.drones[2]) == "lihuo_ya",
		"空格路径把背包件装上了（drones 第 3 件=lihuo_ya）")
	_c.check(GameManager.stash.is_empty(), "装备后背包件离场")
	_c.check(not GameManager.equip_stash_into_slot(9, 0), "背包下标越界＝false")

	# swap_equipped_slots：两件灵宝互换位置；同格/越界＝false
	GameManager.drones = _fake_drone_ids(["lingdie", "haojin_lun", "lihuo_ya", "lingdie"])
	_c.check(GameManager.swap_equipped_slots(0, 2), "swap_equipped_slots(0,2) 成立")
	_c.check(_drone_ids() == ["lihuo_ya", "haojin_lun", "lingdie", "lingdie"],
		"上阵两格互换：drones[0] 与 drones[2] 对调，实得 %s" % str(_drone_ids()))
	_c.check(not GameManager.swap_equipped_slots(1, 1), "同格互换＝false")
	_c.check(not GameManager.swap_equipped_slots(-1, 0), "负下标＝false")
	_c.check(not GameManager.swap_equipped_slots(0, 99), "上阵下标越界＝false")

# ================================ 手势现场 ================================

func _test_gesture() -> void:
	GameManager.reset_run()
	GameManager.roll_shop(true)
	_seed_row()
	_shop = load("res://scenes/ui/WaveShop.tscn").instantiate()
	add_child(_shop)
	await get_tree().process_frame
	_shop._on_shop_opened()
	get_tree().paused = false
	await _settle(8)
	_scroll = _shop.owned_scroll
	_row = _shop.owned_container
	_c.check(_shop.drag_ctl != null, "拖拽控制器挂上了（WaveShop.drag_ctl）")
	var registered := 0
	for t in _tiles():
		if t.has_meta("drag_src"):
			registered += 1
	_c.check(registered >= 15, "上阵格+背包格+分隔签都登记成拖拽源/落点（%d 格）" % registered)

	await _check_hold_pickup()
	await _check_drag_no_scroll()
	await _check_drag_stash_to_equipped()
	await _check_drag_equipped_to_stash()
	await _check_drag_reorder_stash()
	await _check_fast_swipe_still_scroll()
	await _check_tap_still_works()
	# ⑥b/⑥c 各自重灌样本（上阵不满员才有空格、灵宝要有可分辨的 id），
	# 排在 ⑦⑧ 之后不搅动它们认的「背包 9 件」现场
	await _check_drag_equipped_swap()
	await _check_drag_stash_to_empty_slot()

	if "--selftest" in OS.get_cmdline_user_args():
		await _selftest()

## 灌样本：上阵 6 只灵蝶（满槽）+ 背包 8 件（头两件是灵宝类，headless 换装不走玩家节点）
## + 法宝全量把整排撑到溢出（拖动中的 motion 是否截走才有判别力）。
func _seed_row() -> void:
	GameManager.drones.clear()
	for i in range(WeaponData.MAX_SLOTS):
		GameManager.drones.append({"id": "lingdie", "star": 1})
	GameManager.stash.clear()
	for wid in ["haojin_lun", "lihuo_ya", "qingyun_sword", "huoyan_fu", "chiyan_dao",
			"liuye_feidao", "wulei_paizi", "gengjin_feijian"]:
		var wdef: Dictionary = WeaponData.get_def(wid)
		if wdef.is_empty():
			continue
		GameManager.stash.append({"id": wid, "name": wdef.get("name", "?"), "star": 1,
			"icon": wdef.get("icon", ""), "tag": wdef.get("tag", "")})
	GameManager.items.clear()
	for id in ItemData.all_ids():
		GameManager.add_item(String(id))
	GameManager.recalc_synergies()

# ---------- ② 按住拎起 ----------

func _check_hold_pickup() -> void:
	_deselect()
	await _settle(4)
	var src: Control = _find_tile("stash", 0)
	_c.check(src != null, "样本里找得到背包第 0 格")
	if src == null:
		return
	var p: Vector2 = await _bring_into_view(src)
	_btn(p, true)
	_motion(p + Vector2(2, 0), Vector2(2, 0))
	await get_tree().create_timer(ShopDragDrop.HOLD_DELAY + 0.15).timeout
	_c.check(_shop.drag_ctl.is_dragging(), "按住 %.2f 秒后拎起（is_dragging）" % (ShopDragDrop.HOLD_DELAY + 0.15))
	var gr: Rect2 = _shop.drag_ctl.ghost_rect()
	_c.check(gr.size.x > 0.0 and gr.size.y > 0.0, "拎起后幽灵图标画出来了 %s" % str(gr))
	_c.check(src.modulate.a < 0.9, "原格压暗（拿在手里的那件）")
	_btn(p, false)
	await _settle(2)
	_c.check(not _shop.drag_ctl.is_dragging(), "原位松手＝空手，拖拽结束")
	_c.check(GameManager.stash.size() == 8, "空手松手不动数据（背包仍 8 件）")
	await _settle(12)  # 等飞回动画把幽灵收掉

# ---------- ③ 拖动中整排不许跟着滑 ----------

func _check_drag_no_scroll() -> void:
	var src: Control = _find_tile("stash", 1)
	if src == null:
		_c.check(false, "拖动不滚尺没量到：找不到背包第 1 格")
		return
	var p: Vector2 = await _bring_into_view(src)
	var scroll0 := _scroll.scroll_horizontal
	_btn(p, true)
	_motion(p + Vector2(2, 0), Vector2(2, 0))
	await get_tree().create_timer(ShopDragDrop.HOLD_DELAY + 0.15).timeout
	if not _c.check(_shop.drag_ctl.is_dragging(), "拖动不滚尺：先拎起来"):
		_btn(p, false)
		await _settle(4)
		return
	_motion(p + Vector2(320, 0), Vector2(318, 0))
	await get_tree().process_frame
	await get_tree().process_frame
	_c.check(_scroll.scroll_horizontal == scroll0,
		"拖动中的 motion 被截走：整排没跟着滑（拖前 %d，拖中 %d）" % [scroll0, _scroll.scroll_horizontal])
	# 拖回原格再松手：不在未知落点上松手污染后续样本
	_motion(p, Vector2(-318, 0))
	await get_tree().process_frame
	_btn(p, false)
	await _settle(4)
	_c.check(GameManager.stash.size() == 8, "拖远又拖回＝空手松手，数据不动（背包仍 8 件）")
	await _settle(12)

# ---------- ④ 背包件 → 上阵格＝换装 ----------

func _check_drag_stash_to_equipped() -> void:
	var src: Control = _find_tile("stash", 0)
	var dst: Control = _find_tile("equipped", 1)
	_c.check(src != null and dst != null, "换装尺：找得到背包第 0 格与上阵第 1 格")
	if src == null or dst == null:
		return
	var from: Vector2 = await _bring_into_view(src)
	var to: Vector2 = await _bring_into_view(dst)
	await _drag_hold(from, to)
	var drones: Array = GameManager.drones
	_c.check(drones.size() == WeaponData.MAX_SLOTS, "换装后上阵数量不变（满槽）")
	var has_new := false
	for d in drones:
		if WeaponInventory.drone_id(d) == "haojin_lun":
			has_new = true
	_c.check(has_new, "背包件（昊金轮）顶上了阵")
	_c.check(GameManager.stash.size() == 8 and String(GameManager.stash[0].get("id", "")) == "lingdie",
		"换下的灵蝶回到背包被腾出的第 0 位，实得 %s" % str(_stash_ids()))
	_c.check(_shop.selected.is_empty() and DetailTip.live(_shop) == null, "换装后选中清空、详情卡没残留")

# ---------- ⑤ 上阵件 → 背包分隔签＝卸下 ----------

func _check_drag_equipped_to_stash() -> void:
	var src: Control = _find_tile("equipped", 0)
	var dst: Control = _find_tile("stash", -1)
	_c.check(src != null and dst != null, "卸下尺：找得到上阵第 0 格与「背包」分隔签")
	if src == null or dst == null:
		return
	var from: Vector2 = await _bring_into_view(src)
	var to: Vector2 = await _bring_into_view(dst)
	await _drag_hold(from, to)
	_c.check(GameManager.drones.size() == WeaponData.MAX_SLOTS - 1, "上阵少了一件（%d）" % GameManager.drones.size())
	_c.check(GameManager.stash.size() == 9 and String(GameManager.stash[8].get("id", "")) == "lingdie",
		"卸下的灵蝶进了背包（背包 9/9，末位=lingdie），实得 %s" % str(_stash_ids()))

# ---------- ⑥ 背包件 → 另一个背包格＝排序 ----------

func _check_drag_reorder_stash() -> void:
	var src: Control = _find_tile("stash", 0)
	var dst: Control = _find_tile("stash", 3)
	_c.check(src != null and dst != null, "排序尺：找得到背包第 0、3 格")
	if src == null or dst == null:
		return
	var ids0: Array = _stash_ids()
	var from: Vector2 = await _bring_into_view(src)
	var to: Vector2 = await _bring_into_view(dst)
	await _drag_hold(from, to)
	var want: Array = ids0.duplicate()
	var moved = want.pop_at(0)
	want.insert(3, moved)
	_c.check(_stash_ids() == want, "背包内拖动排序（0 → 3），实得 %s" % str(_stash_ids()))

# ---------- ⑥b 上阵件 → 另一个上阵格＝互换位置 ----------

func _check_drag_equipped_swap() -> void:
	GameManager.drones = _fake_drone_ids(["lingdie", "haojin_lun", "lihuo_ya", "lingdie"])
	GameManager.stash = _fake_stash(["wulei_paizi"])
	GameManager.recalc_synergies()
	_shop._refresh_inventory()
	await _settle(6)
	var a: Control = _find_tile("equipped", 0)
	var b: Control = _find_tile("equipped", 2)
	_c.check(a != null and b != null, "换位尺：找得到上阵第 0、2 格")
	if a == null or b == null:
		return
	var from: Vector2 = await _bring_into_view(a)
	var to: Vector2 = await _bring_into_view(b)
	await _drag_hold(from, to)
	_c.check(_drone_ids() == ["lihuo_ya", "haojin_lun", "lingdie", "lingdie"],
		"上阵件拖到另一个上阵格＝互换位置，实得 %s" % str(_drone_ids()))
	_c.check(GameManager.stash.size() == 1, "换位不动背包")

# ---------- ⑥c 背包件 → 上阵空格＝直接装备 ----------

func _check_drag_stash_to_empty_slot() -> void:
	GameManager.drones = _fake_drones(4, "lingdie")
	GameManager.stash = _fake_stash(["haojin_lun"])
	GameManager.recalc_synergies()
	_shop._refresh_inventory()
	await _settle(6)
	var src: Control = _find_tile("stash", 0)
	var dst: Control = _find_tile("equipped", 4)
	_c.check(src != null and dst != null, "空格尺：找得到背包第 0 格与上阵空格（第 4 格）")
	if src == null or dst == null:
		return
	var from: Vector2 = await _bring_into_view(src)
	var to: Vector2 = await _bring_into_view(dst)
	await _drag_hold(from, to)
	_c.check(GameManager.drones.size() == 5, "拖到空上阵格＝装备（上阵 4 → 5）")
	_c.check(WeaponInventory.drone_id(GameManager.drones[4]) == "haojin_lun",
		"装上的件落在队尾（drones[4]=haojin_lun），实得 %s" % str(_drone_ids()))
	_c.check(GameManager.stash.is_empty(), "装备后背包件离场")

# ---------- ⑦ 按住后先划出去＝横滑 ----------

func _check_fast_swipe_still_scroll() -> void:
	_scroll.scroll_horizontal = 0
	await _settle(4)
	var src: Control = _find_tile("stash", 2)
	if src == null:
		_c.check(false, "横滑共存尺没量到：找不到背包第 2 格")
		return
	var p: Vector2 = await _bring_into_view(src)
	_scroll.scroll_horizontal = 0
	await _settle(3)
	var motions := [0]
	var cb := func(ev: InputEvent) -> void:
		if ev is InputEventMouseMotion:
			motions[0] += 1
	_scroll.gui_input.connect(cb)
	_btn(p, true)
	await get_tree().process_frame
	_motion(p + Vector2(90, 0), Vector2(90, 0))
	await get_tree().process_frame
	_btn(p + Vector2(90, 0), false)
	await get_tree().process_frame
	_scroll.gui_input.disconnect(cb)
	_c.check(not _shop.drag_ctl.is_dragging(), "按住后先划出去＝不拎起（是横滑）")
	_c.check(GameManager.stash.size() == 9, "横滑一枪不动数据（背包仍 9 件）")
	_c.check(motions[0] > 0, "待发阶段的 motion 没被截走，OwnedScroll 照常收到（%d 次）" % motions[0])
	_scroll.scroll_horizontal = 0
	await _settle(4)

# ---------- ⑧ 快速点按照旧选中弹卡 ----------

func _check_tap_still_works() -> void:
	_deselect()
	await _settle(4)
	var src: Control = _find_tile("stash", 2)
	if src == null:
		_c.check(false, "点按共存尺没量到：找不到背包第 2 格")
		return
	var p: Vector2 = await _bring_into_view(src)
	await _tap_at(p)
	_c.check(String(_shop.selected.get("pool", "")) == "stash" and int(_shop.selected.get("index", -1)) == 2,
		"快速点按照旧选中（%s）" % str(_shop.selected))
	_c.check(DetailTip.live(_shop) != null, "点按照旧弹出法器详情卡")
	DetailTip.close_all(_shop)
	await _settle(2)

# ================================ 反例 ================================

func _selftest() -> void:
	# 反例① 按住不满时限：不许拎起（拎起阀有牙齿）。自灌满仓样本：selftest 可能跟在
	# ⑥b/⑥c 的自留样本后面跑，不认前场留下的状态
	_seed_row()
	GameManager.stash.append(_fake_stash(["fantian_yin"])[0])
	_shop._refresh_inventory()
	_deselect()
	await _settle(4)
	var src: Control = _find_tile("stash", 4)
	var p: Vector2 = await _bring_into_view(src)
	_btn(p, true)
	_motion(p + Vector2(2, 0), Vector2(2, 0))
	await get_tree().create_timer(0.08).timeout
	_c.check(not _shop.drag_ctl.is_dragging(),
		"反例① 按住 0.08 秒（< HOLD_DELAY %.2f）不许拎起" % ShopDragDrop.HOLD_DELAY)
	_btn(p, false)
	await _settle(4)
	_c.check(GameManager.stash.size() == 9, "反例① 快速点按只选中不动数据")
	_c.check(DetailTip.live(_shop) != null, "反例① 同一枪按点按口径弹出了详情卡（两套手势在同一格上并存）")
	DetailTip.close_all(_shop)
	await _settle(2)

	# 反例② 上阵件拖到上阵空格＝不接（空格不是一件武器；数据原样，背包也没被牵连）
	GameManager.drones = _fake_drone_ids(["lingdie", "haojin_lun", "lihuo_ya", "lingdie"])
	GameManager.stash = _fake_stash(["wulei_paizi"])
	GameManager.recalc_synergies()
	_shop._refresh_inventory()
	_deselect()
	await _settle(4)
	var a: Control = _find_tile("equipped", 0)
	var b: Control = _find_tile("equipped", 4)
	var ids: Array = _drone_ids()
	_c.check(a != null and b != null, "反例② 现场里找得到上阵第 0 格与空格（第 4 格）")
	if a != null and b != null:
		var from: Vector2 = await _bring_into_view(a)
		var to: Vector2 = await _bring_into_view(b)
		await _drag_hold(from, to)
		_c.check(_drone_ids() == ids, "反例② 上阵件拖到上阵空格＝不接（数据原样），实得 %s" % str(_drone_ids()))
		_c.check(GameManager.stash.size() == 1, "反例② 背包也没被牵连")

# ---------------- 道具与采样 ----------------

func _tiles() -> Array:
	var out: Array = []
	for ch in _row.get_children():
		var ctl := ch as Control
		if ctl == null or ctl.is_queued_for_deletion():
			continue
		if ctl.visible and ctl.size.x > 0.0:
			out.append(ctl)
	return out

## 按登记的 drag_src 找格子：pool + index（index -1＝背包分隔签/空位这类「只指区域」的落点）
func _find_tile(pool: String, index: int) -> Control:
	for t in _tiles():
		if not t.has_meta("drag_src"):
			continue
		var s: Dictionary = t.get_meta("drag_src")
		if String(s.get("pool", "")) == pool and int(s.get("index", -9)) == index:
			return t
	return null

func _stash_ids() -> Array:
	var out: Array = []
	for e in GameManager.stash:
		out.append(String(e.get("id", "?")))
	return out

func _fake_stash(ids: Array) -> Array:
	var out: Array = []
	for wid in ids:
		var def: Dictionary = WeaponData.get_def(wid)
		var wid_s := String(wid)
		out.append({"id": wid_s, "name": def.get("name", wid_s), "star": 1,
			"icon": def.get("icon", ""), "tag": def.get("tag", "")})
	return out

func _fake_drones(n: int, wid: String) -> Array:
	var out: Array = []
	for _i in range(n):
		out.append({"id": wid, "star": 1})
	return out

## 可分辨 id 的上阵样本：互换/换位尺要看出「谁换了谁」
func _fake_drone_ids(ids: Array) -> Array:
	var out: Array = []
	for wid in ids:
		out.append({"id": String(wid), "star": 1})
	return out

func _drone_ids() -> Array:
	var out: Array = []
	for d in GameManager.drones:
		out.append(WeaponInventory.drone_id(d))
	return out

func _deselect() -> void:
	_shop.selected = {}
	_shop._refresh_inventory()

## 把某一格滑到可视框正中，返回它落定后的中心（溢出的整排不滑进来就打不到）
func _bring_into_view(ctl: Control) -> Vector2:
	var vis := _scroll.get_global_rect()
	var want: float = ctl.global_position.x - vis.position.x - (vis.size.x - ctl.size.x) * 0.5
	_scroll.scroll_horizontal = int(maxf(0.0, want))
	await _settle(3)
	return ctl.get_global_rect().get_center()

# ---------------- 喂事件（与 ShopRowScrollCheck 同一套真事件枪法） ----------------

## 按住拎起 → 拖到 to 放下
func _drag_hold(from: Vector2, to: Vector2) -> void:
	_btn(from, true)
	await get_tree().process_frame
	_motion(from + Vector2(2, 0), Vector2(2, 0))
	await get_tree().create_timer(ShopDragDrop.HOLD_DELAY + 0.15).timeout
	_motion(to, to - from)
	await get_tree().process_frame
	await get_tree().process_frame
	_btn(to, false)
	await _settle(4)
	await _settle(12)  # 等可能的飞回动画与行重建都落定

## 原地微动一枪（微动 < TAP_SLACK：待发不被划动作废）
func _tap_at(p: Vector2) -> void:
	_btn(p, true)
	await get_tree().process_frame
	_motion(p + Vector2(4, 0), Vector2(4, 0))
	_btn(p + Vector2(4, 0), false)
	await get_tree().process_frame
	await get_tree().process_frame

func _btn(pos: Vector2, down: bool) -> void:
	var b := InputEventMouseButton.new()
	b.position = pos
	b.global_position = pos
	b.button_index = MOUSE_BUTTON_LEFT
	b.pressed = down
	if down:
		b.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_window().push_input(b)

func _motion(pos: Vector2, delta: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = pos
	m.global_position = pos
	m.relative = delta
	m.screen_relative = delta
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_window().push_input(m)

func _settle(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame
