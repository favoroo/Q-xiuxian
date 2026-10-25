class_name ShopChipTips
extends RefCounted

## 商店货架卡行②那排色签的「点按看解释」（2026-10-11 用户：点上面那个标签，要弹出对应的解释，
## 加成怎么样、加成哪些）。色签原先只是三块颜色 + 一行字，触屏没有 hover ⇒ 那排字是死字，
## 「环绕」「召唤 6/MAX」到底是出手方式还是羁绊、加在谁身上，全游戏没有任何一处点得到（同一把尺见 DetailTip 头注）。
##
## 四类色签各有各的解释：
##   攻击方式（近战/远程/范围/环绕/机关）＝这一路武器怎么出手、把哪些属性转成伤害；
##   流派进度（剑系 0/2、召唤 6/MAX）＝阶梯每档加什么、买下这一把之后差几件；
##   可合成＝三合一规则、当前件数，以及合成会掉两件羁绊这件事；
##   ★2 成品（2026-10-25 起货架直售）＝这一件比 ★1 强多少、售价倍率与「星级分开计数」规则。
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
static func open(shop, anchor: Control, tip: Dictionary) -> void:
	var w_id := String(tip.get("w_id", ""))
	match String(tip.get("kind", "")):
		"behavior":
			open_behavior(shop, anchor, w_id)
		"synergy":
			open_synergy(shop, anchor, String(tip.get("tag", "")), w_id)
		"merge":
			open_merge(shop, anchor, w_id, int(tip.get("star", 1)))
		"offer_star":
			open_offer_star(shop, anchor, w_id, int(tip.get("star", 2)))
		"element":
			open_element(shop, anchor, w_id)
		_:
			push_warning("ShopChipTips: 未知色签解释类型 %s" % str(tip.get("kind", "")))

## 点「攻击方式」色签：这一类怎么出手 + 本武器把哪些属性转成伤害
static func open_behavior(shop, anchor: Control, w_id: String) -> void:
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
	notes.append("以上只是这把武器自己转化的部分，完整账单看陈列行详情。")
	var host: Control = shop.get_tip_host() if shop.has_method("get_tip_host") else (shop as Control)
	DetailTip.show_over(host, anchor, {
		"title": "攻击方式 · %s" % label,
		"chip": "这一类 %d 把武器" % WeaponData.behavior_count(beh),
		"chip_color": StatsTipFactory.behavior_color(def),
		"body": String(tip.get("how", "")),
		"notes": notes,
		"foot": "这签讲「怎么出手」；带 n/m 的那颗签讲流派羁绊。",
	})

## 点「流派进度」色签：阶梯每档加什么（与顶栏羁绊徽记同一张卡）+ 买下这一把之后差几件
static func open_synergy(shop, anchor: Control, tag: String, w_id: String) -> void:
	var on_manual := func() -> void:
		if shop.has_signal("manual_requested"):
			shop.manual_requested.emit(tag)
	var payload := SynergyUI.build_tip_data(tag, "", "", [], [
		{"text": "查看该流派武器", "callback": on_manual},
	])
	if payload.is_empty():
		return
	var notes: Array = payload.get("notes", [])
	for line in _purchase_lines(tag, w_id):
		notes.append(line)
	payload["notes"] = notes
	payload["foot"] = String(payload.get("foot", "")) \
			+ "\n签上件数是买下前的数，上阵才 +1。"
	var host: Control = shop.get_tip_host() if shop.has_method("get_tip_host") else (shop as Control)
	DetailTip.show_over(host, anchor, payload)

## 点「可合成」角标：三合一规则 + 当前件数 + 合成会掉两件羁绊。
## star = 货架上那一件的星级（2026-10-25 起货架也卖 ★2 成品）：件数与「合成后」必须按同一个星讲，
## 否则 ★2 商品会印出「★1 → ★2」的假账（★1 与 ★2 各算各的三合一，不能混）。
static func open_merge(shop, anchor: Control, w_id: String, star: int = 1) -> void:
	var def := WeaponData.get_def(w_id)
	if def.is_empty():
		return
	var s := clampi(star, 1, WeaponData.MAX_STAR)
	var copies := GameManager.count_copies(w_id, s)
	var rows: Array = [
		["同名同星", "%d/3 件" % copies, GameStyle.GOOD if copies >= 3 else GameStyle.PAPER],
		["合成后", "%s → %s" % [WeaponData.star_text(s), WeaponData.star_text(s + 1)], GameStyle.JADE],
		["单发伤害", "×%s" % _num(WeaponData.STAR_DAMAGE_MULT), GameStyle.GOOD],
		["出手间隔", "×%s（更快）" % _num(WeaponData.STAR_COOLDOWN_MULT), GameStyle.GOOD],
	]
	# ★3 觉醒 / ★4 极境预告：三合一的终点是专属招式，凑材料的奔头在这两行（文案与详情卡同源）
	var perk_desc := WeaponData.star3_perk_desc(w_id)
	if not perk_desc.is_empty():
		rows.append(["★3 觉醒", perk_desc, GameStyle.PAPER_DIM])
	var asc_desc := WeaponData.star4_perk_desc(w_id)
	if not asc_desc.is_empty():
		rows.append(["★4 极境", asc_desc, GameStyle.PAPER_DIM])
	var first_note := "买下即凑满 3 件 ★1，回陈列行点它按【三合一】。"
	if s >= 2:
		first_note = "买下即凑满 3 件 %s，回陈列行点它合成 %s。" % [
			WeaponData.star_text(s),
			WeaponData.star_text(mini(s + 1, WeaponData.MAX_STAR))]
	var notes: Array[String] = [
		first_note,
		"3 件换 1 件：上阵少 2 件，羁绊件数跟着掉——凑档优先、升星其次。",
		"每升一星，属性转化的伤害再 +25%%；最高 %s，%s 觉醒专属招式、%s 极境。" % [
			WeaponData.star_text(WeaponData.MAX_STAR),
			WeaponData.star_text(3), WeaponData.star_text(WeaponData.MAX_STAR)],
		"手里有同名武器时，货架更容易刷出它。",
	]
	# 新规则教育（只在 ★1 商品上补）：货架从第 4 波起也会直接卖 ★2 成品，
	# 而 ★1 与 ★2 的三合一各算各的 —— 不说这句，玩家会把 ★2 当成「等于 3 把 ★1」。
	if s == 1:
		notes.append("第 %d 波起货架也卖 ★2 成品；★2 只能配 ★2 合成，两种星分开计数。" % GameBalance.STAR2_UNLOCK_WAVE)
	var host_merge: Control = shop.get_tip_host() if shop.has_method("get_tip_host") else (shop as Control)
	DetailTip.show_over(host_merge, anchor, {
		"title": "可合成 · %s" % String(def.get("name", "这把武器")),
		"chip": "三合一",
		"chip_color": GameStyle.JADE,
		"rows": rows,
		"notes": notes,
		"foot": "正好 2 把时角标才亮，买第三把凑齐。",
	})

## 点「★2 成品」签：这件货到底是什么、比 ★1 强多少、怎么参与合成。
## 2026-10-25 用户要求「二星武器要有特殊标记，不然容易看漏」——角标负责「看见」，
## 这张卡负责「看懂」：星级分开计数是买错星就会白花钱的硬规则，必须点得到。
static func open_offer_star(shop, anchor: Control, w_id: String, star: int = 2) -> void:
	var def := WeaponData.get_def(w_id)
	if def.is_empty():
		return
	var s := clampi(star, 2, WeaponData.MAX_STAR)
	var copies := GameManager.count_copies(w_id, s)
	var rows: Array = [
		["这一件", "%s 成品（直购）" % WeaponData.star_text(s), GameStyle.JADE],
		["单发伤害", "★1 的 ×%s" % _num(pow(WeaponData.STAR_DAMAGE_MULT, float(s - 1))), GameStyle.GOOD],
		["出手间隔", "★1 的 ×%s（更快）" % _num(pow(WeaponData.STAR_COOLDOWN_MULT, float(s - 1))), GameStyle.GOOD],
		["售价", "约为 ★1 的 %s 倍" % _num(GameBalance.STAR2_PRICE_MULT), GameStyle.PAPER],
		["同名同星", "%d/3 件" % copies, GameStyle.GOOD if copies >= 3 else GameStyle.PAPER],
	]
	var next_txt := WeaponData.star_text(mini(s + 1, WeaponData.MAX_STAR))
	var notes: Array[String] = [
		"星级分开计数：3 件 %s 才能合 %s，★1 替不了。" % [
			WeaponData.star_text(s), next_txt],
		"第 %d 波起出现，波次越深越常见；手里同名已有 2 件更易刷到。" % GameBalance.STAR2_UNLOCK_WAVE,
		"买它是拿金币换时间：省两次凑 ★1 的刷新，单价更高。",
	]
	var host_star: Control = shop.get_tip_host() if shop.has_method("get_tip_host") else (shop as Control)
	DetailTip.show_over(host_star, anchor, {
		"title": "%s 成品 · %s" % [WeaponData.star_text(s), String(def.get("name", "武器"))],
		"chip": "直购成品",
		"chip_color": GameStyle.GOLD,
		"rows": rows,
		"notes": notes,
		"foot": "买下即按 %s 结算，不用先凑 3 件 ★1。" % WeaponData.star_text(s),
	})

## 点「元素」色签：该武器吃「元素伤害」属性加成
static func open_element(shop, anchor: Control, w_id: String) -> void:
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
		"五行灵蕴武器：伤害直接吃【元素伤害】加成。",
		"图标底部橙红边＝元素武器，配五行道具与流派更强。",
	]
	var host_elem: Control = shop.get_tip_host() if shop.has_method("get_tip_host") else (shop as Control)
	DetailTip.show_over(host_elem, anchor, {
		"title": "元素武器 · %s" % String(def.get("name", "武器")),
		"chip": "元素加成",
		"chip_color": GameStyle.ELEMENT,
		"rows": rows,
		"notes": notes,
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
		out.append("但武器槽已满（%d/%d）：%s 进背包，背包不计入羁绊，上阵才算数。" % [
			GameManager.slots_used(), GameManager.max_weapon_slots(), wname])
		return out
	if next_th <= 0:
		out.append("%s 属于这一路，已满档封顶，再买只多一件输出。" % wname)
		return out
	if n + 1 == next_th:
		out.append("%s 属于这一路：上阵正好 %d 件，当场激活第 %d 档——%s。" % [
			wname, next_th, tier_idx + 1, tier_txt])
	elif tier_idx >= 0:
		out.append("%s 属于这一路：上阵后 %d → %d 件，还差 %d 件上第 %d 档（%s）。" % [
			wname, n, n + 1, next_th - 1 - n, tier_idx + 1, tier_txt])
	return out

static func _num(v: float) -> String:
	return String.num(v, 2)
