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
## 2026-10-11 用户真机两条口径（本轮改的就是这两处）：
##  · 落点认图标，不认手指：手指按在哪一格就把那一格当落点＝摸黑瞄准（拇指整个盖住那一格，
##    连"选中了哪一格"都看不见）。幽灵抬到手指上方，判定取它**画出来的中心**压在哪一格。
##    ⑨ 钉的就是「手指落在整排下方、图标压着目标格」这一枪 —— 按旧口径当场没有落点；
##    反例③ 钉另一头：手指正压在目标格中心而图标没压到 ⇒ 不许兑现。两头一起钉，判定才真的
##    搬到图标上，而不是"看起来搬了"。
##  · 上阵件拖到背包里的某一件＝互换：旧口径只认「拖回背包区＝卸下」，于是拖到那一件上也是
##    丢进背包，要换的那件没换上（背包满格时更是当场拒绝，只能先卖一件）。⑩ 钉互换，
##    ⑤ 钉「分隔签仍然只是卸下」—— 两条必须在同一把尺里，不然修一头塌另一头。
##
## 尺子清单：
## ① 数据层：swap_into_equipped 上阵未满＝装备、已满＝互换（换下的一件回背包原位），
##   非灵宝且无玩家节点时先验后动不拆半截；equip_stash_into_slot 拖拽落点语义
##   （空格/越界＝直接装备、已占用格＝替换且不满员也替换）、swap_equipped_slots
##   同池互换（i==j / 越界 / 混池＝false）；reorder_stash 顺移、越界夹取、原地不动＝false；
## ①b 同池替换顶在原格（灵宝改 drones[slot]，不排队尾）；互换的两个方向走同一条
##   equip_stash_into_slot（背包件→上阵格 与 上阵件→背包件 只是参数对调）；
##   背包满格时卸下被拒、互换照样成立（件数不变）；
## ② 按住 HOLD_DELAY 才拎起：幽灵出现、原格压暗，且拎起时整排没被拖走；
## ③ 拖着走整排不许跟着滑（OwnedScroll 已在按下那一拍 latch，拖动中的 motion 必须被截走）；
## ④ 拖背包件到已佩戴的武器格放下＝替换那一格（上阵已满样本），数据对、选中清空、详情卡没残留；
## ⑤ 拖上阵件到「背包」分隔签放下＝卸下成功（只指区域不指件，不许被互换吃掉）；
## ⑥ 背包件拖到另一个背包格＝背包内排序；
## ⑥b 上阵件拖到另一个上阵格＝互换位置（同池）；
## ⑥c 背包件拖到上阵空格＝直接装备（上阵区固定画满上限格数，空格也是落点）；
## ⑦ 按住后先划出去＝横滑（不拎起、数据不动、motion 照常送到 OwnedScroll）；
## ⑧ 快速点按照旧选中弹卡（拖拽登记没把点按吃掉）；
## ⑨ 落点认图标：拎起那一下手指正压在源格上也不许有落点；图标中心压到哪格认哪格（此刻
##    手指在整排下方、不在任何格子内）；判定落点 == 幽灵画出来的中心；动作签印「替换·那一格」；
## ⑩ 上阵件拖到背包里某一件＝互换（那件顶在原格、这件回它腾出的背包位，件数不变）。
## 反例（--selftest）：按住不满时限拎不起来；上阵件拖到上阵空格＝不接；
##   手指压在目标格上而图标没压到＝空手松开，数据原样。

const VP := Vector2(1202, 540)
const EPS := 1.5

var _c := TestCheck.new()
var _shop: WaveShop
var _scroll: ScrollContainer
var _row: HBoxContainer
## 出图台：`-- --shot=/tmp/x.png` 在「图标压住目标格、动作签亮着」那一帧拍一张
## （必须不带 --headless，否则没有像素）。这轮改的就是"看得见什么"，纸面判据抓不到糊不糊眼。
var _shot_path := ""

func _ready() -> void:
	get_tree().root.size = VP
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--shot="):
			_shot_path = String(a).trim_prefix("--shot=")
	await _test_inventory_ops()
	await _test_gesture()
	_c.set_min_checks(90)  # 条数掉一半 = 中途炸了还在打 ALL PASS（report 内统一守卫）
	get_tree().quit(0 if _c.report("SHOP_DRAG_RESULT") else 1)

func _grab_shot(tag: String) -> void:
	if _shot_path.is_empty():
		return
	await _settle(6)
	var img := get_tree().root.get_texture().get_image()
	var path := _shot_path.replace(".png", "-%s.png" % tag)
	print("[SHOT] %s err=%d 尺寸 %dx%d" % [path, img.save_png(path), img.get_width(), img.get_height()])

# ================================ ① 数据层 ================================

## headless 没有 Player 节点：上阵池用 drones 灌（与 ShopRowScrollCheck 同一手法），
## 背包件也只用 DRONE 行为的武器（haojin_lun/lihuo_ya/muling_ou…），悬浮法器那半边根本不被碰到。
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

	# swap_into_equipped：上阵已满＝互换，旧的一件回背包原位
	GameManager.drones = _fake_drones(6, "lingdie")
	GameManager.stash = _fake_stash(["haojin_lun"])
	_c.check(GameManager.swap_into_equipped(0, 2), "上阵满时 swap_into_equipped 成立（换装）")
	_c.check(GameManager.drones.size() == 6, "换装后上阵数量不变（6）")
	_c.check(WeaponInventory.drone_id(GameManager.drones[2]) == "haojin_lun"
			and WeaponInventory.drone_id(GameManager.drones[5]) == "lingdie",
			"①b 背包件顶在被指的那一格上（同池原地替换，不排队尾），实得 %s" % str(_drone_ids()))
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

	# equip_stash_into_slot：拖拽落点语义 —— 已占用格＝替换（不满员也替换），顶在原格
	GameManager.drones = _fake_drones(2, "lingdie")
	GameManager.stash = _fake_stash(["haojin_lun"])
	_c.check(GameManager.equip_stash_into_slot(0, 1), "未满员拖到已佩戴格＝替换（equip_stash_into_slot）")
	_c.check(GameManager.drones.size() == 2 and WeaponInventory.drone_id(GameManager.drones[1]) == "haojin_lun",
		"被指中的那一格被替换（drones[1]=haojin_lun）")
	_c.check(WeaponInventory.drone_id(GameManager.drones[0]) == "lingdie",
		"没被指的那一格不动（换装不打乱整排方位），实得 %s" % str(_drone_ids()))
	_c.check(GameManager.stash.size() == 1 and String(GameManager.stash[0].get("id", "")) == "lingdie",
		"换下的一件回背包被腾出的原位（stash[0]=lingdie），实得 %s" % str(_stash_ids()))

	# ①b 互换的两个方向是同一条操作：上阵件拖到背包第 1 件上 = 背包第 1 件拖到上阵第 0 格
	GameManager.drones = _fake_drone_ids(["lingdie", "haojin_lun"])
	GameManager.stash = _fake_stash(["jinming_ling", "muling_ou"])
	_c.check(GameManager.equip_stash_into_slot(1, 0),
		"①b 上阵件拖到背包某一件＝走同一条替换（只是参数对调）")
	_c.check(_drone_ids() == ["muling_ou", "haojin_lun"],
		"①b 被指的那件顶上了第 0 格，实得 %s" % str(_drone_ids()))
	_c.check(_stash_ids() == ["jinming_ling", "lingdie"],
		"①b 拖下来的那件落在它腾出的背包位，实得 %s" % str(_stash_ids()))

	# ①b 背包满仓：卸下这条路会被拒，互换不受容量影响（件数不变）
	GameManager.drones = _fake_drone_ids(["lingdie", "haojin_lun"])
	GameManager.stash = _fake_stash(["jinming_ling", "jianling", "muling_ou", "bingpo_zhu",
			"tuling_shi"])
	_c.check(not GameManager.unequip_to_stash(0), "满背包时卸下被拒（背包已满那条播报）")
	_c.check(GameManager.equip_stash_into_slot(4, 0), "满背包时互换照样成立（不用先卖一件）")
	_c.check(GameManager.stash.size() == WeaponData.MAX_STASH_SLOTS, "互换不动背包件数（仍 %d/%d）" \
			% [GameManager.stash.size(), WeaponData.MAX_STASH_SLOTS])
	_c.check(_drone_ids() == ["tuling_shi", "haojin_lun"],
		"满仓互换后第 0 格是土灵石，实得 %s" % str(_drone_ids()))
	_c.check(String(GameManager.stash[4].get("id", "")) == "lingdie",
		"拖下来的那件落在被换走那件的背包位（stash[4]=lingdie）")

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
	var expect_registered: int = WeaponData.MAX_SLOTS + 1 + GameManager.stash.size()
	_c.check(registered >= expect_registered,
		"上阵格+背包格+分隔签都登记成拖拽源/落点（%d 格，至少 %d）" % [registered, expect_registered])

	await _check_hold_pickup()
	await _check_drag_no_scroll()
	await _check_drag_stash_to_equipped()
	await _check_drag_equipped_to_stash()
	await _check_drag_reorder_stash()
	await _check_fast_swipe_still_scroll()
	await _check_tap_still_works()
	# ⑥b/⑥c/⑨/⑩ 各自重灌样本（上阵不满员才有空格、灵宝要有可分辨的 id），
	# 排在 ⑦⑧ 之后不搅动它们认的「背包 5 件」现场
	await _check_drag_equipped_swap()
	await _check_drag_stash_to_empty_slot()
	await _check_aim_follows_icon()
	await _check_drag_swap_via_equipped_source()

	if "--selftest" in OS.get_cmdline_user_args():
		await _selftest()

## 灌样本：上阵 6 只灵蝶（满槽）+ 背包 4 件（留一格给「卸下」判据；头两件是灵宝类，
## headless 换装不走玩家节点）+ 法宝全量把整排撑到溢出（拖动中的 motion 是否截走才有判别力）。
func _seed_row() -> void:
	GameManager.drones.clear()
	for i in range(WeaponData.MAX_SLOTS):
		GameManager.drones.append({"id": "lingdie", "star": 1})
	GameManager.stash.clear()
	for wid in ["haojin_lun", "lihuo_ya", "qingyun_sword", "huoyan_fu"]:
		var wdef: Dictionary = WeaponData.get_def(wid)
		if wdef.is_empty():
			continue
		GameManager.stash.append({"id": wid, "name": wdef.get("name", "?"), "star": 1,
			"icon": wdef.get("icon", ""), "tag": wdef.get("tag", "")})
	GameManager.items.clear()
	for id in ItemData.all_ids():
		GameManager.add_item(String(id))
	GameManager.recalc_synergies()

## 自留样本：上阵 3 只（可分辨 id）+ 背包 3 件灵宝 + 没有法宝（整排不溢出，两格一定同时看得见）
func _seed_small() -> void:
	GameManager.items.clear()
	GameManager.recalc_synergies()
	_shop._refresh_inventory()
	_deselect()

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
	# 幽灵必须真的带贴图：2026-10-14 用户真机，icon 非空时 add_child 缩错进 if 分支，
	# 幽灵只剩纯黑底 PanelContainer（拖动预览全黑）
	var ghost := _shop.drag_ctl._ghost
	var has_icon_tex := false
	if ghost != null and is_instance_valid(ghost):
		for ch in ghost.get_children():
			var tr := ch as TextureRect
			if tr != null and tr.texture != null:
				has_icon_tex = true
	_c.check(has_icon_tex, "幽灵卡片里有图标贴图（不是黑框）")
	_c.check(src.modulate.a < 0.9, "原格压暗（拿在手里的那件）")
	_btn(p, false)
	await _settle(2)
	_c.check(not _shop.drag_ctl.is_dragging(), "原位松手＝空手，拖拽结束")
	_c.check(GameManager.stash.size() == 4, "空手松手不动数据（背包仍 4 件）")
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
	_c.check(GameManager.stash.size() == 4, "拖远又拖回＝空手松手，数据不动（背包仍 4 件）")
	await _settle(12)

# ---------- ④ 背包件 → 上阵格＝换装 ----------

func _check_drag_stash_to_equipped() -> void:
	var src: Control = _find_tile("stash", 0)
	var dst: Control = _find_tile("equipped", 1)
	if not _c.check(src != null and dst != null, "换装尺：找得到背包第 0 格与上阵第 1 格"):
		return
	var pts := await _bring_pair_into_view(src, dst)
	await _drag_hold(pts[0], pts[1], "fullrow")
	var drones: Array = GameManager.drones
	_c.check(drones.size() == WeaponData.MAX_SLOTS, "换装后上阵数量不变（满槽）")
	_c.check(WeaponInventory.drone_id(drones[1]) == "haojin_lun",
		"背包件（昊金轮）顶在被指的这一格上，实得 %s" % str(_drone_ids()))
	_c.check(GameManager.stash.size() == 4 and String(GameManager.stash[0].get("id", "")) == "lingdie",
		"换下的灵蝶回到背包被腾出的第 0 位，实得 %s" % str(_stash_ids()))
	_c.check(_shop.selected.is_empty() and DetailTip.live(_shop) == null, "换装后选中清空、详情卡没残留")

# ---------- ⑤ 上阵件 → 背包分隔签＝卸下（只指区域，不许被互换吃掉）----------

func _check_drag_equipped_to_stash() -> void:
	var src: Control = _find_tile("equipped", 0)
	var dst: Control = _find_tile("stash", -1)
	if not _c.check(src != null and dst != null, "卸下尺：找得到上阵第 0 格与「背包」分隔签"):
		return
	var pts := await _bring_pair_into_view(src, dst)
	await _drag_hold(pts[0], pts[1])
	_c.check(GameManager.drones.size() == WeaponData.MAX_SLOTS - 1, "上阵少了一件（%d）" % GameManager.drones.size())
	_c.check(GameManager.stash.size() == WeaponData.MAX_STASH_SLOTS \
			and String(GameManager.stash[WeaponData.MAX_STASH_SLOTS - 1].get("id", "")) == "lingdie",
		"卸下的灵蝶进了背包（背包 %d/%d，末位=lingdie），实得 %s" \
		% [GameManager.stash.size(), WeaponData.MAX_STASH_SLOTS, str(_stash_ids())])

# ---------- ⑥ 背包件 → 另一个背包格＝排序 ----------

func _check_drag_reorder_stash() -> void:
	var src: Control = _find_tile("stash", 0)
	var dst: Control = _find_tile("stash", 3)
	if not _c.check(src != null and dst != null, "排序尺：找得到背包第 0、3 格"):
		return
	var ids0: Array = _stash_ids()
	var pts := await _bring_pair_into_view(src, dst)
	await _drag_hold(pts[0], pts[1])
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
	if not _c.check(a != null and b != null, "换位尺：找得到上阵第 0、2 格"):
		return
	var pts := await _bring_pair_into_view(a, b)
	await _drag_hold(pts[0], pts[1])
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
	if not _c.check(src != null and dst != null, "空格尺：找得到背包第 0 格与上阵空格（第 4 格）"):
		return
	var pts := await _bring_pair_into_view(src, dst)
	await _drag_hold(pts[0], pts[1])
	_c.check(GameManager.drones.size() == 5, "拖到空上阵格＝装备（上阵 4 → 5）")
	_c.check(WeaponInventory.drone_id(GameManager.drones[4]) == "haojin_lun",
		"装上的件落在队尾（drones[4]=haojin_lun），实得 %s" % str(_drone_ids()))
	_c.check(GameManager.stash.is_empty(), "装备后背包件离场")

# ---------- ⑨ 落点认图标，不认手指 ----------

## 用户 2026-10-11：「它判定我拖动的那个位置，是根据我手指的位置判定的。常理来讲应该按这个
## 图标来判定，因为手指会遮挡住」。幽灵画在手指上方，判定取它画出来的中心 ⇒ 两把尺：
##  A 拎起那一下手指正压在源格中心，图标已经在整排上方 ⇒ 不许有落点（旧口径当场认一格）；
##  B 图标压到目标格 ⇒ 落点必须是那一格，而此刻手指在整排下方一截，不在任何格子内
##    （旧口径这一枪根本没有落点，换装不会发生）。
func _check_aim_follows_icon() -> void:
	GameManager.drones = _fake_drone_ids(["lingdie", "haojin_lun", "lihuo_ya"])
	GameManager.stash = _fake_stash(["muling_ou", "jinming_ling", "jianling"])
	_seed_small()
	await _settle(6)
	var src: Control = _find_tile("stash", 0)
	var dst: Control = _find_tile("equipped", 1)
	if not _c.check(src != null and dst != null, "认图标尺：找得到背包第 0 格与上阵第 1 格"):
		return
	var pts := await _bring_pair_into_view(src, dst)
	var from: Vector2 = pts[0]
	var to: Vector2 = pts[1]
	_btn(from, true)
	await get_tree().process_frame
	_motion(from + Vector2(2, 0), Vector2(2, 0))
	await get_tree().create_timer(ShopDragDrop.HOLD_DELAY + 0.15).timeout
	if not _c.check(_shop.drag_ctl.is_dragging(), "认图标尺：先拎起来"):
		_btn(from, false)
		await _settle(4)
		return
	# A 此刻手指正压在源格中心上
	_c.check(src.get_global_rect().has_point(from),
		"反证 A：拎起那一下手指确实还压在源格里（按手指判定的旧口径当场就会认一格）")
	_c.check(_shop.drag_ctl.hover_src().is_empty(),
		"拎起那一下没有落点：图标没压在格子上就不算（实得 %s）" % str(_shop.drag_ctl.hover_src()))
	_c.check(_shop.drag_ctl.cap_text().is_empty(), "没有落点时动作签不许亮")
	# B 把图标按到目标格上：手指要往下走一截（lift = 手指 - 图标中心，实测值，不抄常量）
	var lift := from - _shop.drag_ctl.aim_point()
	var press := to + lift
	_motion(press, press - from)
	await _settle(2)
	var hs: Dictionary = _shop.drag_ctl.hover_src()
	_c.check(String(hs.get("pool", "")) == "equipped" and int(hs.get("index", -1)) == 1,
		"图标压到哪一格就认哪一格（实得 %s）" % str(hs))
	_c.check(not dst.get_global_rect().has_point(press),
		"反证 B：这一枪手指在整排下方 %d 单位处，不在目标格内（按手指判定会没有落点）" % int(lift.y))
	var aim := _shop.drag_ctl.aim_point()
	# 认现读的格子矩形：按下那一拍的微动会让整排被拖走几单位（OwnedScroll 已 latch），
	# 事先算好的 to 到这一刻已经旧了几单位，钉死距离会假红
	_c.check(dst.get_global_rect().has_point(aim),
		"判定落点 == 幽灵画出来的中心，且它真落在这一格内（落点 %s，格 %s）" \
		% [str(aim), str(dst.get_global_rect())])
	_c.near(press.y - aim.y, ShopDragDrop.AIM_LIFT, 0.5,
		"图标中心钉在手指正上方 %s 单位处" % str(ShopDragDrop.AIM_LIFT))
	var nm := String(GameManager.get_weapons_summary()[1].get("name", ""))
	_c.equals(_shop.drag_ctl.cap_text(), "替换·%s" % nm, "动作签印出被指这一格是哪一件")
	await _grab_shot("aim")
	_btn(press, false)
	await _settle(4)
	await _settle(12)
	_c.check(_drone_ids() == ["lingdie", "muling_ou", "lihuo_ya"],
		"图标压着的那一格被换上（顶在原格上），实得 %s" % str(_drone_ids()))
	_c.check(_stash_ids() == ["haojin_lun", "jinming_ling", "jianling"],
		"换下的那件回背包被腾出的原位，实得 %s" % str(_stash_ids()))

# ---------- ⑩ 上阵件 → 背包里某一件＝互换 ----------

## 用户 2026-10-11：「拖过去之后它直接就放到背包里面去了，我要替换的那件没换上。拖到那个图标
## 那里就应该替换，把背包里面的武器替换到这个佩戴的武器的原来位置」
func _check_drag_swap_via_equipped_source() -> void:
	GameManager.drones = _fake_drone_ids(["lingdie", "haojin_lun", "lihuo_ya"])
	GameManager.stash = _fake_stash(["jinming_ling", "muling_ou", "jianling"])
	_seed_small()
	await _settle(6)
	var src: Control = _find_tile("equipped", 2)
	var dst: Control = _find_tile("stash", 1)
	if not _c.check(src != null and dst != null, "互换尺：找得到上阵第 2 格与背包第 1 格"):
		return
	var ids: Array = _drone_ids()
	var sids: Array = _stash_ids()
	var pts := await _bring_pair_into_view(src, dst)
	await _drag_hold(pts[0], pts[1])
	_c.check(_drone_ids() == ["lingdie", "haojin_lun", "muling_ou"],
		"拖下来的那件没进背包队尾，而是顶上了原来那一格（离火鸦→木灵偶），实得 %s（拖前 %s）" \
		% [str(_drone_ids()), str(ids)])
	_c.check(_stash_ids() == ["jinming_ling", "lihuo_ya", "jianling"],
		"上阵的那件落在被换走那件的背包位（stash[1]=离火鸦），实得 %s（拖前 %s）" \
		% [str(_stash_ids()), str(sids)])
	_c.check(GameManager.stash.size() == 3, "互换不动背包件数（不是丢进背包）")

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
	_c.check(GameManager.stash.size() == WeaponData.MAX_STASH_SLOTS,
		"横滑一枪不动数据（背包仍 %d 件）" % GameManager.stash.size())
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
	# ⑥b/⑥c/⑨/⑩ 的自留样本后面跑，不认前场留下的状态
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
	_c.check(GameManager.stash.size() == WeaponData.MAX_STASH_SLOTS, "反例① 快速点按只选中不动数据")
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
		var pts := await _bring_pair_into_view(a, b)
		await _drag_hold(pts[0], pts[1])
		_c.check(_drone_ids() == ids, "反例② 上阵件拖到上阵空格＝不接（数据原样），实得 %s" % str(_drone_ids()))
		_c.check(GameManager.stash.size() == 1, "反例② 背包也没被牵连")

	# 反例③ 手指正压在目标格中心、图标没压到 ⇒ 不许兑现。
	# 判定一旦退回手指坐标（或有人把 AIM_LIFT 改成 0），这一枪当场红：旧口径它必换成功。
	GameManager.drones = _fake_drone_ids(["lingdie", "haojin_lun", "lihuo_ya"])
	GameManager.stash = _fake_stash(["muling_ou", "jinming_ling"])
	_seed_small()
	await _settle(4)
	var s: Control = _find_tile("stash", 0)
	var d: Control = _find_tile("equipped", 0)
	var ids0: Array = _drone_ids()
	var sids0: Array = _stash_ids()
	if not _c.check(s != null and d != null, "反例③ 现场找得到背包第 0 格与上阵第 0 格"):
		return
	var pts2 := await _bring_pair_into_view(s, d)
	var from: Vector2 = pts2[0]
	var onto: Vector2 = pts2[1]
	_btn(from, true)
	await get_tree().process_frame
	_motion(from + Vector2(2, 0), Vector2(2, 0))
	await get_tree().create_timer(ShopDragDrop.HOLD_DELAY + 0.15).timeout
	# 纯横移：手指落到目标格中心（旧口径这就是落点），图标仍在整排上方，谁都没压着
	_motion(onto, onto - from)
	await _settle(2)
	_c.check(d.get_global_rect().has_point(onto), "反例③ 这一枪手指正压在目标格中心上")
	_c.check(_shop.drag_ctl.hover_src().is_empty(),
		"反例③ 图标没压到任何格子＝没有落点（实得 %s）" % str(_shop.drag_ctl.hover_src()))
	_btn(onto, false)
	await _settle(4)
	await _settle(12)
	_c.check(_drone_ids() == ids0 and _stash_ids() == sids0,
		"反例③ 空手松开，数据原样（上阵 %s / 背包 %s）" % [str(_drone_ids()), str(_stash_ids())])

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
## 把某一格划进可视框并返回落定后的中心。
## 与 ShopRowScrollCheck 同一把尺：写一次不算数，要「连续两帧读数没再动、且这一格真在框里」
## 才算落定 —— 刚划完那几帧 ScrollContainer 还在收上一次拖动的落点，此时写进去的
## scroll_horizontal 会被顶回去；格子越大（内容越宽、要划的越远）越容易读到还没落地的旧位置，
## 下一枪的「拖前读数」就成了假基准（2026-10-12 陈列行图标从 36 抬到 56 后暴露）。
func _bring_into_view(ctl: Control) -> Vector2:
	var vis := _scroll.get_global_rect()
	var prev := -1
	for i in range(12):
		var want: float = ctl.global_position.x - vis.position.x - (vis.size.x - ctl.size.x) * 0.5
		_scroll.scroll_horizontal = int(maxf(0.0, want))
		await _settle(1)
		var now := _scroll.scroll_horizontal
		var r: Rect2 = ctl.get_global_rect()
		if now == prev and r.position.x >= vis.position.x - EPS and r.end.x <= vis.end.x + EPS:
			break
		prev = now
	return ctl.get_global_rect().get_center()

## 一次把两格都摆进可视框（取它们的中点居中），返回两格落定后的中心。
## 一前一后各滑一次不行：第二次滑动会把第一次算好的落点坐标作废，真按上去是别格的位置
## （全局坐标随滚动走），整条拖拽尺就变成"看着在测 A→B、实际测的是别处→别处"。
## 中点居中后两格一定同时在框内（样本里两格相距远小于框宽），落点才是它自己。
func _bring_pair_into_view(a: Control, b: Control) -> Array[Vector2]:
	var vis := _scroll.get_global_rect()
	var mid_now: float = (a.get_global_rect().get_center().x + b.get_global_rect().get_center().x) * 0.5
	# global_x = content_x - scroll ⇒ content 系中点 = 现读中点 + 现滚动读数
	var want: float = mid_now + float(_scroll.scroll_horizontal) - vis.position.x - vis.size.x * 0.5
	_scroll.scroll_horizontal = int(maxf(0.0, want))
	await _settle(3)
	var pa: Vector2 = a.get_global_rect().get_center()
	var pb: Vector2 = b.get_global_rect().get_center()
	_c.check(vis.has_point(pa) and vis.has_point(pb),
		"两格都摆进了可视框（%s / %s，框 %s）" % [str(pa), str(pb), str(vis)])
	return [pa, pb]

# ---------------- 喂事件（与 ShopRowScrollCheck 同一套真事件枪法） ----------------

## 按住拎起 → 把「图标」压到 to 上放下。判定认的是画出来的图标（见 ShopDragDrop 头注），
## 所以手指要落在 to 下方一截：先原地量一次图标中心离手指的实际距离（viewport 夹取过，
## 纸面常量算的不一定作数），再按它把图标按到 to 上。
func _drag_hold(from: Vector2, to: Vector2, shot_tag: String = "") -> void:
	_btn(from, true)
	await get_tree().process_frame
	_motion(from + Vector2(2, 0), Vector2(2, 0))
	await get_tree().create_timer(ShopDragDrop.HOLD_DELAY + 0.15).timeout
	if not _c.check(_shop.drag_ctl.is_dragging(), "drag_hold 前置：拎起来了"):
		_btn(from, false)
		await _settle(4)
		return
	var lift := from - _shop.drag_ctl.aim_point()
	var press := to + lift
	_motion(press, press - from)
	await get_tree().process_frame
	await get_tree().process_frame
	if not shot_tag.is_empty():
		await _grab_shot(shot_tag)
	_btn(press, false)
	await _settle(4)
	await _settle(12)  # 等可能的飞回动画与行重建都落定

## 原地微动一枪（微动 < TAP_SLACK：待发不被划动作废）
func _tap_at(p: Vector2) -> void:
	_btn(p, true)
	await get_tree().process_frame
	_motion(p + Vector2(4, 0), Vector2(4, 0))
	_btn(p + Vector2(4, 0), false)
	await get_tree().process_frame
	await _settle(2)

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
