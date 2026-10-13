class_name ShopChipTips
extends RefCounted

## 商店货架卡行②那排色签的「点按看解释」（2026-10-11 用户：点上面那个标签，要弹出对应的解释，
## 加成怎么样、加成哪些）。色签原先只是三块颜色 + 一行字，触屏没有 hover ⇒ 那排字是死字，
## 「环绕」「召唤 6/MAX」到底是出手方式还是羁绊、加在谁身上，全游戏没有任何一处点得到（同一把尺见 DetailTip 头注）。
##
## 三类色签各有各的解释：
##   攻击方式（近战/远程/范围/环绕/机关）＝这一路武器怎么出手、把哪些属性转成伤害；
##   流派进度（剑系 0/2、召唤 6/MAX）＝阶梯每档加什么、买下这一把之后差几件；
##   可合成＝三合一规则、当前件数，以及合成会掉两件羁绊这件事。
##
## 三条口径：
## ① 数字一律现读，不在这里算第二遍：阶梯与门槛走 SynergyUI（与顶栏羁绊徽记同一张卡、同一把尺），
##    属性账单走 WeaponDamageReadout（与卡面「伤害 24 → 31.1」同一个数），
##    机制文案走 WeaponData.BEHAVIOR_TIPS（只写代码真做了的事，数值不进文案）。
## ② 宿主仍是 WaveShop：DetailTip 判据按宿主收卡，关面板/刷新时一起收，不留旧账。
## ③ 卡上印的件数是「买下之前」的数 —— 与色签读数一致，另起一行讲清买下之后会变成什么，
##    不替玩家把 3 件写成 4 件。

## 色签的统一入口：tip 由 ShopOfferCardFactory 在画签那一刻写好（{"kind": ...}），
## 回调里只带这一颗字典，不带控件引用 —— 货架 refresh 会整批重建卡片。
static func open(shop: WaveShop, anchor: Control, tip: Dictionary) -> void:
	var w_id := String(tip.get("w_id", ""))
	match String(tip.get("kind", "")):
		"behavior":
			open_behavior(shop, anchor, w_id)
		"synergy":
			open_synergy(shop, anchor, String(tip.get("tag", "")), w_id)
		"merge":
			open_merge(shop, anchor, w_id)
		"element":
			open_element(shop, anchor, w_id)
		_:
			push_warning("ShopChipTips: 未知色签解释类型 %s" % str(tip.get("kind", "")))

## 点「攻击方式」色签：这一类怎么出手 + 本武器把哪些属性转成伤害
static func open_behavior(shop: WaveShop, anchor: Control, w_id: String) -> void:
	var def := WeaponData.get_def(w_id)
	if def.is_empty():
		return
	var beh := int(def.get("behavior", WeaponData.Behavior.MELEE))
	var tip := WeaponData.behavior_tip(beh)
	var label := WeaponData.behavior_label(def)
	if label.is_empty():
		return
	var notes: Array[String] = []
	for n in tip.get("notes", []):
		notes.append(String(n))
	# 「加成哪些」的硬账：这一行与商店详情卡/属性面板同一个函数，卡上那个箭头右边的数就是它乘出来的
	notes.append(WeaponDamageReadout.bonus_bill_text(w_id, 1))
	notes.append("以上是这一把武器自己转化的属性；全局、羁绊、角色与五行几道乘区要点陈列行里那件看完整账单。")
	DetailTip.show_over(shop, anchor, {
		"title": "攻击方式 · %s" % label,
		"chip": "这一类 %d 把武器" % WeaponData.behavior_count(beh),
		"chip_color": StatsTipFactory.behavior_color(def),
		"body": String(tip.get("how", "")),
		"notes": notes,
		"foot": "攻击方式说的是「怎么出手」；同一排带 n/m 的那颗色签说的是流派羁绊，两回事。",
	})

## 点「流派进度」色签：阶梯每档加什么（与顶栏羁绊徽记同一张卡）+ 买下这一把之后差几件
static func open_synergy(shop: WaveShop, anchor: Control, tag: String, w_id: String) -> void:
	var payload := SynergyUI.build_tip_data(tag, "", "", [], [
		{"text": "查看该流派武器", "callback": func() -> void: shop.manual_requested.emit(tag)},
	])
	if payload.is_empty():
		return
	var notes: Array = payload.get("notes", [])
	for line in _purchase_lines(tag, w_id):
		notes.append(line)
	payload["notes"] = notes
	payload["foot"] = String(payload.get("foot", "")) \
			+ "\n色签上的件数是买下之前的数，买下并上阵才会 +1。"
	DetailTip.show_over(shop, anchor, payload)

## 点「可合成」角标：三合一规则 + 当前件数 + 合成会掉两件羁绊
static func open_merge(shop: WaveShop, anchor: Control, w_id: String) -> void:
	var def := WeaponData.get_def(w_id)
	if def.is_empty():
		return
	var copies := GameManager.count_copies(w_id, 1)
	var rows: Array = [
		["同名同星", "%d/3 件" % copies, GameStyle.GOOD if copies >= 3 else GameStyle.PAPER],
		["合成后", "%s → %s" % [WeaponData.star_text(1), WeaponData.star_text(2)], GameStyle.JADE],
		["单发伤害", "×%s" % _num(WeaponData.STAR_DAMAGE_MULT), GameStyle.GOOD],
		["出手间隔", "×%s（更快）" % _num(WeaponData.STAR_COOLDOWN_MULT), GameStyle.GOOD],
	]
	var notes: Array[String] = [
		"货架只卖 ★1：买下这一把就凑满 3 件，回陈列行点它，详情卡里有【三合一】那颗键。",
		"3 件换 1 件：合成后上阵少 2 件 ⇒ 流派羁绊的件数也跟着掉 2 件，凑档优先、升星其次。",
		"最高 %s（%d 档），每升一星属性转化的那部分伤害再多 +25%%。" % [
			WeaponData.star_text(WeaponData.MAX_STAR), WeaponData.MAX_STAR],
	]
	DetailTip.show_over(shop, anchor, {
		"title": "可合成 · %s" % String(def.get("name", "这把武器")),
		"chip": "三合一",
		"chip_color": GameStyle.JADE,
		"rows": rows,
		"notes": notes,
		"foot": "手里正好 2 把时这颗角标才亮：买下第三把就凑齐。",
	})

## 点「元素」色签：该武器吃「元素伤害」属性加成
static func open_element(shop: WaveShop, anchor: Control, w_id: String) -> void:
	var def := WeaponData.get_def(w_id)
	if def.is_empty():
		return
	var coef := WeaponData.elemental_scaling_coef(w_id)
	var stats := GameManager.get_player_stat_dict()
	var edmg: float = float(stats.get("elemental_damage", 0.0))
	var gain: float = edmg * coef
	var rows: Array = [
		["元素转化系数", "%.1f" % coef, GameStyle.ELEMENT],
		["当前元素伤害", "%+.1f" % edmg, GameStyle.GOOD if edmg > 0.0 else (GameStyle.BAD if edmg < 0.0 else GameStyle.PAPER)],
		["换算额外伤害", "%+.1f" % gain, GameStyle.GOOD if gain > 0.0 else (GameStyle.BAD if gain < 0.0 else GameStyle.PAPER)],
	]
	var notes: Array[String] = [
		"该武器带有五行灵蕴，其单发与每秒伤害直接受角色【元素伤害】属性加成。",
		"图标底部的暖橙红下边框代表具备元素特性，可与五行道具或火/木/水等流派产生强联动。",
	]
	DetailTip.show_over(shop, anchor, {
		"title": "元素武器 · %s" % String(def.get("name", "武器")),
		"chip": "元素加成",
		"chip_color": GameStyle.ELEMENT,
		"rows": rows,
		"notes": notes,
		"foot": "受元素伤害加成的武器在商店与背包图标底部均有暖橙红下边框提示。",
	})

## 买下这一把对这一路羁绊的效应（逐条人话，件数与门槛全部现读 SynergyUI 那把尺子）
static func _purchase_lines(tag: String, w_id: String) -> Array[String]:
	var out: Array[String] = []
	var p := SynergyUI.progress(tag, GameManager.get_tag_count(tag))
	var n: int = int(p["count"])
	var ths: Array = p["ths"]
	var next_th: int = int(p["next_th"])
	var wname := String(WeaponData.get_def(w_id).get("name", "这把武器"))
	# 下一档是第几档、给什么（阶梯文案与顶栏徽记的详情卡同一张表）
	var tier_idx := -1
	for i in range(ths.size()):
		if int(ths[i]) == next_th:
			tier_idx = i
			break
	var tier_txt := ""
	if tier_idx >= 0:
		tier_txt = SynergyUI.tier_line(tag, tier_idx + 1)
	# 武器槽满了这一把进背包，而背包不计入羁绊（tag_counts 只数上阵与环绕件）——
	# 不写这一句，色签上的「差 1 件」就成了按下去不会兑现的承诺
	if GameManager.slots_used() >= GameManager.max_weapon_slots():
		out.append("但武器槽已满（%d/%d）：%s 会先进背包，背包里的武器不计入羁绊，上阵才算数。" % [
			GameManager.slots_used(), GameManager.max_weapon_slots(), wname])
		return out
	if next_th <= 0:
		out.append("%s 属于这一路，但已满档：%d 件封顶，再买只多一件输出，不再涨档。" % [
			wname, int(p["max_th"])])
		return out
	if n + 1 == next_th:
		out.append("%s 属于这一路：买下并上阵正好 %d 件，当场激活第 %d 档 —— %s。" % [
			wname, next_th, tier_idx + 1, tier_txt])
	elif tier_idx >= 0:
		out.append("%s 属于这一路：买下并上阵后 %d → %d 件，还差 %d 件上第 %d 档（%s）。" % [
			wname, n, n + 1, next_th - 1 - n, tier_idx + 1, tier_txt])
	return out

static func _num(v: float) -> String:
	return String.num(v, 2)
