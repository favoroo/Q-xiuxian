extends Node

## 判据：法宝（被动道具）买得进、卖得掉，卖掉之后每一项属性必须原样退回。
## 运行: $G --headless --path . res://tests/ItemSellCheck.tscn
##       $G --headless --path . res://tests/ItemSellCheck.tscn -- --selftest
##
## 为什么立这条（2026-10-12 用户真机，指着灵石阁里【聚财袋】那张详情卡说：
## 「商店里的这些道具啊，如果有买到不想要的，也可以卖掉」）：
##  ① 法器与灵兽一直卖得掉，法宝这一类点进去只有读数、没有操作 —— 被动道具不占武器槽、
##     也没法「卸下」，买错了要背整局，这一屏是唯一能反悔的地方。
##  ② 出售不是「从数组里删掉一个 id」就完事：add_item 那份 apply 表是真落在属性链路上的，
##     不回退就等于「卖一件 −18% 全伤害的道具，伤害反而涨了」。而回退要碰的字段有乘有加，
##     还有暴击率/攻速这种被上限与地板夹过的 —— 夹掉的那一份落地了多少，只有买那一刻知道，
##     所以卖出时读数还停在顶上就不许扣（宁可少扣，不许白罚）。
##  ③ 于是这把尺子逐件法宝量「买入 → 卖出 → 每一项读数回到买入前」，ItemData.DEFS 一件不落。
##     以后谁往 apply 里加新字段而忘了在 StatSystem.revert_stat_fields 补反向分支，这里直接报红，
##     不靠人记得。
##
## 防假 PASS：
##  ① 尺子活着：每件带 apply 的法宝，买入后必须至少有一项被跟踪的读数真的动了 ——
##     全零说明快照没覆盖到它写的那个字段，后面每一条都会静默空判（"ALL PASS 零项"配方）；
##  ② 回收金币按 ItemData.DEFS 的基准价在本文件现算，不叫被测代码报数；
##  ③ 夹顶那一枪单独开函数，并留一条「低于上限」的正例，证明「不扣」不是「压根没回退」；
##  ④ UI 那一枪走引擎拾取：真发按下 → 抬起，落点从 get_global_rect() 取画布坐标再经
##     get_final_transform() 换窗口坐标；点 Button 前先送一次 motion 建立 hover
##     （无头下没有 hover，按下态与拾取都不成立，直接 press 会打空）；
##  ⑤ --selftest 把修复前的三种形状（只删件不回退 / unique 卖了还能再买 / 夹顶照扣）各打一枪，
##     三把尺子各须报一次红。

const EPS := 0.0005
const JITTER := 4.0
## 三档屏：4:3 平板 / 16:9 基准 / 20:9 宽屏（与 LayoutCheck、ShopReadoutCheck 同一套档位）
const WIDTHS: Array[int] = [720, 960, 1204]
## 用来打 UI 那一枪的样本法宝：非 unique、apply 里有乘区也有负项（全伤害 +18%、护甲 −2）
const UI_ITEM := "kuangxue_dan"
## 夹顶样本：利刃符 = crit_rate +0.06 / armor −1，正好一条会被上限夹、一条照减
const CAP_ITEM := "liren_fu"
const CAP_GAIN := 0.06
const ARMOR_COST := -1.0
## 本局已购账本进池子过滤，抽多少次都不许再出这一件
const ROLL_TRIES := 200

var _c := TestCheck.new()
var _main: Node
var _shop: WaveShop
var _joy: DawnJoystick

func _ready() -> void:
	get_tree().root.size = Vector2i(960, 540)
	call_deferred("_boot")

func _boot() -> void:
	_main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(_main)
	await _settle(3)
	GameManager.cultivator_id = ""
	GameManager.start_run("qingyun_sword")
	get_tree().paused = false
	await _settle(3)
	_shop = _main.get_node_or_null("UILayer/WaveShop") as WaveShop
	_joy = _main.get_node_or_null("UILayer/VirtualJoystick") as DawnJoystick
	_c.check(_shop != null and _joy != null and GameManager.player != null,
			"真场景 + 真 Player 已就位（没有 Player 就量不到 max_hp 这一路）")
	if _shop == null or _joy == null or GameManager.player == null:
		_quit()
		return
	_quiet_arena()
	if "--selftest" in OS.get_cmdline_user_args():
		await _selftest()
	else:
		await _main_cases()
	_quit()

func _main_cases() -> void:
	await _round_trip_every_item()
	await _refund_matches_base_price()
	await _unique_ledger_survives_selling()
	await _capped_stat_must_not_be_punished()
	await _pet_slot_item_refuses_to_overcap()
	await _tip_fits_three_widths()
	await _sell_from_the_shop_ui()

func _quit() -> void:
	get_tree().quit(0 if _c.report("ITEMSELL_RESULT") else 1)

# ================================ ① 逐件回退 ================================

## 每一件法宝：买入 → 至少有一项读数动了（尺子活着）→ 卖出 → 全部读数回到买入前。
func _round_trip_every_item() -> void:
	var ids: Array = ItemData.all_ids()
	_c.check(ids.size() >= 50, "采到 %d 件法宝（少于 50 件说明 ItemData 没读全）" % ids.size())
	var bad: Array[String] = []
	var with_apply := 0
	var done := 0
	for raw_id in ids:
		var id := String(raw_id)
		var apply: Dictionary = ItemData.get_def(id).get("apply", {})
		var before := _snap()
		if not GameManager.add_item(id):
			bad.append("%s 买不进" % id)
			continue
		if not apply.is_empty():
			# 尺子活着：这一件写进去的东西必须在我的快照里看得见
			if _diff(before, _snap()).is_empty():
				bad.append("%s 买入后一项读数都没动（apply=%s 没被跟踪）" % [id, str(apply.keys())])
				continue
			with_apply += 1
		if not GameManager.sell_item(id):
			bad.append("%s 卖不掉（sell_item 返回 false）" % id)
			continue
		var left := _diff(before, _snap())
		if not left.is_empty():
			bad.append("%s 卖出后没退回：%s" % [id, str(left)])
			continue
		done += 1
	_c.check(bad.is_empty(), "逐件法宝「买入 → 卖出」全字段回原值（共 %d 件，异常 %s）" % [
			ids.size(), str(bad)])
	_c.equals(done, ids.size(), "%d 件法宝全部走完一次回退（完成 %d，不等就是中途漏件）" % [
			ids.size(), done])
	_c.check(with_apply >= 60,
			"其中 %d 件带 apply 属性，买入后至少有一项被跟踪的读数动了（尺子活着，不是零项空判）" % with_apply)
	_c.check(GameManager.items.is_empty(), "全部卖完时持有清单为空（实得 %d 件）" % GameManager.items.size())

## 回收金币 = 原价一半：期望值本文件按 ItemData.DEFS 现算，不叫被测代码报数。
func _refund_matches_base_price() -> void:
	var samples: Array[String] = ["jubaopen", "jucai_dai", "taiyi_jindan", "panshi_yin"]
	var bad: Array[String] = []
	for id in samples:
		var base := int(ItemData.get_def(id).get("price", 0))
		var want: int = maxi(1, int(ceil(float(base) * 0.5)))
		GameManager.spirit_stones = 0
		GameManager.add_item(id)
		GameManager.sell_item(id)
		if GameManager.spirit_stones != want:
			bad.append("%s 原价 %d 期望回收 %d 实得 %d" % [
					id, base, want, GameManager.spirit_stones])
	_c.check(bad.is_empty(), "回收金币 = 原价一半（%d 件样本，异常 %s）" % [samples.size(), str(bad)])
	_c.check(GameManager.items.is_empty() and GameManager.spirit_stones > 0,
			"卖完即清空并真的进账（金币 %d）" % GameManager.spirit_stones)

# ================================ ② unique 账本 ================================

## unique 法宝「每局限购一件」：出售后不许解禁 —— 详情卡上那句「出售后本局不再出现」
## 由这里兑现，货架池也必须真的不再出这一件。
func _unique_ledger_survives_selling() -> void:
	_clean_items()
	var id := "tisi_kuilei"
	_c.check(GameManager.add_item(id), "替身娃娃第一次买得进")
	_c.check(not GameManager.add_item(id), "持有时买不进（每局限购一件）")
	_c.check(GameManager.sell_item(id), "替身娃娃卖得掉")
	_c.check(not GameManager.add_item(id), "卖掉之后本局仍买不进（unique 不因退货解禁）")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261012
	var leaks := 0
	for _i in range(ROLL_TRIES):
		if ItemData.pick_id(50.0, 20, GameManager.items_bought, rng, GameManager.unlocked_items) == id:
			leaks += 1
	_c.equals(leaks, 0, "抽 %d 次货架池不再出这一件（已购账本进池子过滤）" % ROLL_TRIES)
	# 非 unique 的那一件卖掉后必须还能再买 —— 限购只锁 unique
	_c.check(GameManager.add_item("jucai_dai") and GameManager.sell_item("jucai_dai"),
			"聚财袋（非 unique）买得进也卖得掉")
	_c.check(GameManager.add_item("jucai_dai"), "聚财袋卖掉后还能再买（限购只锁 unique）")
	GameManager.sell_item("jucai_dai")

# ================================ ③ 夹顶不白罚 ================================

## 正向 min(x+v, cap)：卖出时读数还停在顶上 ⇒ 这一份被上限吃掉过、吃掉多少无从得知 ⇒ 一分不扣。
## 反例（旧写法照扣）会把没兑现的东西收回去 = 白罚。下面那条「低于上限」的正例证明
## 「不扣」不是「压根没回退」。
func _capped_stat_must_not_be_punished() -> void:
	_clean_items()
	var cap: float = GameManager.CRIT_RATE_CAP
	var crit_before := GameManager.crit_rate
	GameManager.crit_rate = cap - 0.01
	var armor_before := GameManager.armor
	GameManager.add_item(CAP_ITEM)
	_c.near(GameManager.crit_rate, cap, EPS, "买入利刃符：暴击率被上限夹在顶上（只兑现了一点点）")
	GameManager.sell_item(CAP_ITEM)
	_c.near(GameManager.crit_rate, cap, EPS, "卖出利刃符：夹顶那一份不许倒扣（读数留在上限）")
	_c.near(GameManager.armor, armor_before, EPS,
			"同一件里没被夹的护甲照原样退回（不是整条不回退）")
	GameManager.crit_rate = cap - 0.30
	var low_before := _snap()
	GameManager.add_item(CAP_ITEM)
	_c.near(GameManager.crit_rate, cap - 0.30 + CAP_GAIN, EPS, "低于上限时买入：+%s 完整兑现" % str(CAP_GAIN))
	GameManager.sell_item(CAP_ITEM)
	_c.check(_diff(low_before, _snap()).is_empty(), "低于上限时卖出：完整收回并整组回到买入前")
	GameManager.crit_rate = crit_before

# ================================ ④ 退了会超编的不许退 ================================

## 万兽笼给灵兽上限 +1：手里已经占着两格时卖掉会当场把灵兽栏搞成 2/1 那种假读数 ⇒ 拒卖。
func _pet_slot_item_refuses_to_overcap() -> void:
	_clean_items()
	var max_before := GameManager.max_pet_slots()
	_c.check(GameManager.add_item("wanshou_long"), "万兽笼买得进")
	_c.equals(GameManager.max_pet_slots(), max_before + 1, "万兽笼给灵兽上限 +1")
	var first := String(PetData.all_ids()[0])
	var second := String(_other_pet_id(first))
	_c.check(GameManager.add_pet(first) and GameManager.add_pet(second), "两只灵兽入栏（占满 +1 后的栏位）")
	_c.equals(GameManager.pets.size(), 2, "灵兽栏现有 2 只")
	# 顺手钉住 sync_pet_instances 这一路：数据有了场上就得有（旧写法在这里静默少一只，
	# 因为 Object.get("pet_id","") 抛错中断了 sync 的后半段）
	_c.equals(_pet_entities(), 2, "场上真的跟着出现两只灵兽实体（不是只多了一条数据）")
	_c.check(not GameManager.sell_item("wanshou_long"), "超编时拒绝出售万兽笼（不许把读数搞成 2/1）")
	_c.check(GameManager.has_item("wanshou_long"), "拒卖之后万兽笼还在手里（没删件也没退钱）")
	_c.check(GameManager.sell_pet(second), "先腾空一栏")
	_c.check(GameManager.sell_item("wanshou_long"), "腾空后就卖得掉万兽笼")
	_c.equals(GameManager.max_pet_slots(), max_before, "退掉万兽笼后灵兽上限回到原值")
	GameManager.sell_pet(first)
	_c.check(GameManager.pets.is_empty(), "样本灵兽清场（实得 %d 只）" % GameManager.pets.size())

## 三档屏（与 LayoutCheck / ShopReadoutCheck 同一套）：徽记压在屏底那一排，详情卡多出来的
## 「出售返还」一行与卡底那颗键不许把卡顶出可视区（真机上探出屏 = 按不到 = 没有这个功能）。
func _tip_fits_three_widths() -> void:
	_clean_items()
	GameManager.add_item(UI_ITEM)
	for w in WIDTHS:
		await _open_shop(w)
		var chip := _item_chip(UI_ITEM)
		_c.check(chip != null, "屏宽 %d：陈列行画出了道具徽记" % w)
		if chip == null:
			await _open_close()
			continue
		await _scroll_into_view(chip)
		var payload := await _tap(chip, "屏宽 %d · 道具徽记" % w)
		_c.check(_has_sell_action(payload), "屏宽 %d：卡底摆了【出售】那颗键" % w)
		_c.check(_sell_button() != null, "屏宽 %d：那颗键真的画出来了（不是只写在 payload 里）" % w)
		await _open_close()

# ================================ ⑤ 灵石阁里真点得掉 ================================

## 从生产入口打这一枪：陈列行里的道具徽记 → 详情卡 → 卡底那颗【出售】键。
## 全程引擎拾取（真按下 + 抬起），热区是死的、按钮没接线、回调漏刷新都会在这里报红。
func _sell_from_the_shop_ui() -> void:
	_clean_items()
	# 基准 = 还没买这一件时的读数：按下出售后必须回到这里（拿「按下之前」比是错的，
	# 那一刻道具正生效着，退回恰恰意味着两个数不相等）
	var baseline := _snap()
	GameManager.add_item(UI_ITEM)
	await _open_shop()
	var chip := _item_chip(UI_ITEM)
	_c.check(chip != null, "陈列行画出了道具徽记「%s」" % String(
			ItemData.get_def(UI_ITEM).get("name", "?")))
	if chip == null:
		return
	var gold := GameManager.spirit_stones
	var want_refund: int = ItemData.sell_price(UI_ITEM)
	var payload := await _tap(chip, "道具徽记")
	_c.equals(String(payload.get("title", "")), String(ItemData.get_def(UI_ITEM).get("name", "")),
			"点徽记弹的是这一件法宝的详情卡（实得「%s」）" % String(payload.get("title", "")))
	var joined := _joined(payload)
	_c.check(joined.contains("出售返还"), "卡上印了「出售返还」这一行")
	_c.check(joined.contains("原价"), "卡上把原价与回收价并排印出来（回收是按原价折半）")
	_c.check(_has_sell_action(payload), "详情卡底部摆了【出售】那颗键")
	# 先自证「这一件真的动了读数」，否则下面那条「回到买入前」是空判
	_c.check(not _diff(baseline, _snap()).is_empty(),
			"买入这一件后读数确实变了（不然回退那条断言就是零项空判）")
	await _scroll_into_view(chip)
	var btn := _sell_button()
	_c.check(btn != null and btn.text.contains(str(want_refund)),
			"键上印的回收金币与原价一半同号（键「%s」/ 期望含 %d）" % [
			btn.text if btn != null else "<没有这颗键>", want_refund])
	if btn == null:
		await _open_close()
		return
	await _tap_button(btn)
	_c.equals(GameManager.items.count(UI_ITEM), 0, "点一下真的从持有清单里删掉了这一件")
	_c.equals(GameManager.spirit_stones, gold + want_refund,
			"金币当场进账 %d（实得 %d）" % [want_refund, GameManager.spirit_stones - gold])
	var left_after_tap := _diff(baseline, _snap())
	_c.check(left_after_tap.is_empty(),
			"整组读数回到「还没买这一件」之前（含 max_hp 那一路）：未退回 %s" % str(left_after_tap))
	_c.check(DetailTip.live(_shop) == null, "按下后详情卡收起（不留一张写着旧账的卡）")
	await _settle(2)
	_c.check(_item_chip(UI_ITEM) == null, "陈列行里那颗徽记跟着没了（不是只删数据没重画）")
	await _open_close()

# ================================ 反例（--selftest） ================================

## 三把尺子各须抓住修复前的形状，否则这条判据只是「现在恰好是绿的」。
func _selftest() -> void:
	# 反例①：只删件不回退属性 —— 逐件回退那把尺子必须报「没退回」
	_clean_items()
	var before := _snap()
	GameManager.add_item(UI_ITEM)
	GameManager.items.clear()  # 旧写法：出售 = 从数组里删一个 id
	var left := _diff(before, _snap())
	_c.check(not left.is_empty(), "反例①：不回退属性的写法被抓住（未退回字段 %s）" % str(left))
	_clean_items()
	# 反例②：unique 卖了还能再买 —— 没有本局已购账本时，旧行为复现
	GameManager.add_item("tisi_kuilei")
	GameManager.sell_item("tisi_kuilei")
	GameManager.items_bought.clear()
	_c.check(GameManager.add_item("tisi_kuilei"),
			"反例②：账本一清，卖掉就能再买（旧行为复现 ⇒ 那条「不因退货解禁」的尺子有牙齿）")
	_clean_items()
	# 反例③：夹顶照扣 —— 同一个断言打在旧算式上必须落空
	var cap: float = GameManager.CRIT_RATE_CAP
	var naive: float = cap - CAP_GAIN
	_c.check(naive < cap - EPS, "反例③：夹顶照扣会把读数从上限拖回 %.4f（正写法原样留在顶上）" % naive)
	_c.near(StatSystem.undo_capped_add(cap, CAP_GAIN, cap), cap, EPS, "正写法：停在顶上时一分不扣")
	_c.near(StatSystem.undo_capped_add(cap - 0.3, CAP_GAIN, cap), cap - 0.3 - CAP_GAIN, EPS,
			"正写法：没被夹时照减（不是一律不动）")
	_clean_items()

# ================================ 取样与手势 ================================

## 被跟踪的读数清单：直接抄 StatShadow.COPIED（属性影子/面板共用的那一份），
## 另加两件影子不带的：五行分项与真身气血（max_hp 那一路落在 Player 节点上）。
## spirit_stones 单独量（回收金币就是它），不进「回到原值」这一组。
func _snap() -> Dictionary:
	var out: Dictionary = {}
	for k in StatShadow.COPIED:
		if k == "spirit_stones":
			continue
		out[k] = GameManager.get(k)
	var elems: Dictionary = {}
	for e in WeaponData.ELEMENTS:
		elems[e] = float(GameManager.element_damage.get(e, 0.0))
	out["element_damage"] = elems
	var p: Node = GameManager.player
	if p != null and is_instance_valid(p):
		out["player_max_hp"] = float(p.get("max_health"))
		out["player_cur_hp"] = minf(float(p.get("max_health")), float(p.get("current_health")))
	return out

func _diff(a: Dictionary, b: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for k in a.keys():
		var av = a[k]
		if av is Dictionary:
			for e in (av as Dictionary).keys():
				if not _near(float((av as Dictionary)[e]), float((b[k] as Dictionary).get(e, 0.0))):
					out.append("%s.%s" % [k, e])
		elif av is int:
			if int(av) != int(b[k]):
				out.append(k)
		elif not _near(float(av), float(b[k])):
			out.append(String(k))
	return out

func _near(x: float, y: float) -> bool:
	return absf(x - y) <= EPS

## 清场：把持有清单与本局已购账本倒空（属性由各段自己走完回退，段间不留残留）
func _clean_items() -> void:
	GameManager.items.clear()
	GameManager.items_bought.clear()
	GameManager.unique_item_count = 0

func _other_pet_id(first: String) -> String:
	for pid in PetData.all_ids():
		if String(pid) != first:
			return String(pid)
	return first

## 场上活着的灵兽实体数（正在消散的不算，与 PetSystem.sync_pet_instances 同一个口径）
func _pet_entities() -> int:
	var n := 0
	for p in get_tree().get_nodes_in_group("spirit_pets"):
		if is_instance_valid(p) and p.get("_dying") != true and p.get("pet_id") != null:
			n += 1
	return n

func _item_chip(item_id: String) -> Control:
	var want := String(ItemData.get_def(item_id).get("name", item_id))
	var out: Array[Control] = []
	_collect_chips(_shop.owned_container, want, out)
	return out[0] if not out.is_empty() else null

## 遍历 + 读 meta：代码建的子件同名会被引擎改名（@PanelContainer@N），按名字找就是静默拿 null
func _collect_chips(node: Node, want: String, out: Array[Control]) -> void:
	for ch in node.get_children():
		var ctl := ch as Control
		if ctl != null and ctl.has_meta("tip_title") \
				and String(ctl.get_meta("tip_title")) == want and ctl.is_visible_in_tree():
			out.append(ctl)
		_collect_chips(ch, want, out)

## 卡底那颗出售键（正例文案「出售 (+n 金币)」，超编那一档是灰着的「先出售灵兽」）
func _sell_button() -> Button:
	var tip := DetailTip.live(_shop)
	if tip == null:
		return null
	var found: Array[Button] = []
	_collect_buttons(tip, found)
	return found[0] if not found.is_empty() else null

func _collect_buttons(node: Node, out: Array[Button]) -> void:
	for ch in node.get_children():
		var b := ch as Button
		if b != null and (b.text.begins_with("出售") or b.text.begins_with("先出售")):
			out.append(b)
		_collect_buttons(ch, out)

func _has_sell_action(payload: Dictionary) -> bool:
	for row in payload.get("actions", []):
		if row is Array:
			for act in row:
				if act is Dictionary and String((act as Dictionary).get("text", "")).begins_with("出售"):
					return true
		elif row is Dictionary:
			if String((row as Dictionary).get("text", "")).begins_with("出售"):
				return true
	return false

func _joined(payload: Dictionary) -> String:
	var out := String(payload.get("body", "")) + String(payload.get("foot", ""))
	for n in payload.get("notes", []):
		out += "\n" + String(n)
	for r in payload.get("rows", []):
		out += "\n" + str(r)
	return out

func _open_shop(width: int = 960) -> void:
	DetailTip.close_all(_shop)
	get_tree().root.size = Vector2i(width, 540)
	GameManager.spirit_stones = 500
	GameManager.roll_shop(true)
	_shop._on_shop_opened()
	# 等真实时间：卡是错峰缩放入场的，headless 一帧不到 1ms，等帧数会量到还在动的矩形
	await get_tree().create_timer(0.8).timeout
	await _settle(2)

func _open_close() -> void:
	DetailTip.close_all(_shop)
	_shop.visible = false
	get_tree().paused = false
	await get_tree().create_timer(0.35).timeout
	await _settle(2)

## 徽记在横滑行里：整排摆不下一屏时它可能整颗在视口外，落点会打空
func _scroll_into_view(c: Control) -> void:
	var r := c.get_global_rect()
	var view_w := float(get_tree().root.size.x)
	if r.position.x < 0.0 or r.end.x > view_w:
		_shop.owned_scroll.scroll_horizontal = maxi(0, int(r.get_center().x - view_w * 0.5))
		await _settle(3)

func _tap(target: Control, label: String) -> Dictionary:
	var pos := target.get_global_rect().get_center()
	await _wait_tips_gone()
	await _press(pos)
	_c.check(target.has_meta(GameStyle._TAP_DOWN_META),
			"%s：这一枪送到了它身上（引擎没记账 ⇒ 落点打歪了）" % label)
	await _motion(pos + Vector2(0, -JITTER))
	await _release(pos + Vector2(0, -JITTER))
	return _collect_tip()

## 点详情卡里的键：不许先收卡（_wait_tips_gone 会把键连同它那张卡一起 free 掉），
## 且按下前先送一次 motion 建立 hover —— 无头没有真鼠标，缺这一拍 BaseButton 认不出按下态。
func _tap_button(target: Button) -> void:
	var pos := target.get_global_rect().get_center()
	await _motion(pos)
	await _press(pos)
	await _release(pos)
	await _settle(2)

func _collect_tip() -> Dictionary:
	var payload: Dictionary = {}
	var tip := DetailTip.live(_shop)
	if tip != null:
		payload = tip.payload
		var card := tip.card_rect()
		var vp := _shop.get_viewport_rect()
		_c.check(Rect2(vp.position, vp.size).encloses(card),
				"详情卡整块落在视口内（卡 %s / 视口 %s）" % [str(card), str(vp.size)])
	return payload

func _wait_tips_gone() -> void:
	DetailTip.close_all(_shop)
	for _i in range(40):
		var any := false
		for ch in _shop.get_children():
			if ch is DetailTip:
				any = true
		if not any:
			return
		await get_tree().process_frame
	push_warning("详解卡 40 帧还没收干净，后续落点不可信")

func _to_input(pos: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * pos

func _press(pos: Vector2) -> void:
	var p := _to_input(pos)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = p
	e.global_position = p
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_tree().root.push_input(e)
	await get_tree().process_frame

func _release(pos: Vector2) -> void:
	var p := _to_input(pos)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.position = p
	e.global_position = p
	get_tree().root.push_input(e)
	await get_tree().process_frame

func _motion(pos: Vector2) -> void:
	var p := _to_input(pos)
	var m := InputEventMouseMotion.new()
	m.position = p
	m.global_position = p
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_tree().root.push_input(m)
	await get_tree().process_frame

func _quiet_arena() -> void:
	var spawner: Node = GameManager.wave_spawner
	if spawner != null:
		spawner.set_process(false)
		spawner.set_physics_process(false)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is EnemyBase:
			enemy.dissolve()

func _settle(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame
