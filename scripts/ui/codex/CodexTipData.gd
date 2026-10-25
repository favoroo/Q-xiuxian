class_name CodexTipData
extends RefCounted

## 图鉴 / 作者面板共用的详情卡载荷工厂：把 WeaponData / ItemData / PetData 的静态数据
## 翻成 DetailTip 的 payload（title / chip / rows / body / notes / foot）。
##
## 2026-10-22 从 ManualDialog 抽出：作者面板的购买弹窗必须与图鉴详情卡同源，
## 否则同一把武器在两屏上写着两套数字（改表漏改一处就是假话）。
## foot 允许调用方覆写（作者模式要写「免费获得」而不是「仅商店有售」）。

const PROC_NAMES := {"proc_burn": "灼烧", "proc_chill": "减速", "proc_poison": "中毒"}

const BEHAVIOR_NAMES := {
	WeaponData.Behavior.MELEE: "近战",
	WeaponData.Behavior.PROJECTILE: "远程",
	WeaponData.Behavior.BURST: "范围",
	WeaponData.Behavior.DRONE: "环绕",
	WeaponData.Behavior.TURRET: "机关",
	WeaponData.Behavior.SWEEP: "横扫",
	WeaponData.Behavior.BEAM: "光束",
	WeaponData.Behavior.CONE: "喷吐",
}

## 武器详情：攻击方式 / 基础伤害 / 间隔 / 范围 / 买入价 + 穿透·齐射·异常 + 属性受益
## 未实战收录（CodexCollection）时只给名字与一句话定位，数值与词条一律不剧透（2026-10-25 锁图鉴）。
## 注意：title 始终是真实武器名 —— 图鉴卡的 tip_title 与它必须一致，否则热区判据会判「弹错卡」。
static func weapon_payload(wid: String, foot: String = "") -> Dictionary:
	var def := WeaponData.get_def(wid)
	if def.is_empty():
		return {}
	var elem := ""
	for t in def.get("tags", []):
		if t in WeaponData.ELEMENTS:
			elem = String(t)
	var chip_color: Color = GameStyle.ELEMENT_COLORS.get(elem, GameStyle.GOLD)

	if not CodexCollection.is_weapon_seen(wid):
		var lock_foot := foot
		if lock_foot == "":
			lock_foot = AchievementData.weapon_unlock_hint_text(wid, "解锁条件：")
			if lock_foot == AchievementData.NO_UNLOCK_HINT:
				lock_foot = "收录条件：在金币阁买下这件武器"
		return {
			"title": String(def.get("name", wid)),
			"icon": String(def.get("icon", "")),
			"chip": " 未收录 ",
			"chip_color": GameStyle.GREY,
			"rows": [],
			"body": "尚未用过这件武器。买下或获得一次后，这里会显示它的完整数值与特性。",
			"notes": [],
			"foot": lock_foot,
		}

	# 行名与货架卡/详情卡用同一套词（2026-10-11 用户「看不懂」口径的同类问题）：
	# 「伤害」加「基础」两字：图鉴这一列是数据表纸面值，本局加成不在这里。
	var rows: Array = [
		["攻击方式", String(BEHAVIOR_NAMES.get(def.get("behavior", 0), "近战")), chip_color],
		["基础伤害", "%d" % int(def.get("damage", 0)), GameStyle.JADE],
		["攻击间隔", "%s 秒" % String.num(float(def.get("cooldown", 1.0)), 2), GameStyle.PAPER],
		["攻击范围", "%d" % int(def.get("range", 0)), GameStyle.PAPER],
		["买入价格", "%d 金币" % int(def.get("price", 0)), GameStyle.JADE],
	]
	if int(def.get("pierce", 0)) > 1:
		rows.append(["穿透", "%d 敌" % int(def["pierce"]), GameStyle.PAPER])
	if int(def.get("projectile_count", 1)) > 1:
		rows.append(["齐射", "%d 发" % int(def["projectile_count"]), GameStyle.PAPER])
	for proc_key in PROC_NAMES.keys():
		if def.has(proc_key):
			rows.append(["异常状态", PROC_NAMES[proc_key], chip_color])

	var notes: Array[String] = []
	var scalings: Dictionary = def.get("stat_scalings", {})
	if not scalings.is_empty():
		var names: Array[String] = []
		for key in scalings.keys():
			names.append(GameBalance.stat_scaling_label(String(key)))
		notes.append("属性受益：" + "、".join(names))
	notes.append("集齐 3 把同名同星可在商店合成升星")

	return {
		"title": String(def.get("name", wid)),
		"icon": String(def.get("icon", "")),
		"chip": " " + String(def.get("tag", "")) + " ",
		"chip_color": chip_color,
		"rows": rows,
		"body": String(def.get("desc", "")),
		"notes": notes,
		"foot": foot if foot != "" else "武器仅在回合间商店有售",
	}


## 道具详情：品阶 / 原价 / 出售返还 + apply 加成行 + desc 逐行 notes
## 未实战收录时只留品阶与原价，加成行与说明不剧透（2026-10-25 锁图鉴）。
static func item_payload(iid: String, foot: String = "") -> Dictionary:
	var def := ItemData.get_def(iid)
	if def.is_empty():
		return {}
	var tier_num := int(def.get("tier", 1))
	var tier_col := ItemData.tier_color(tier_num)

	if not CodexCollection.is_item_seen(iid):
		var lock_foot := foot
		if lock_foot == "":
			lock_foot = AchievementData.unlock_hint_text(iid, true, "收录条件：")
			if lock_foot == AchievementData.NO_UNLOCK_HINT:
				lock_foot = "收录条件：在金币阁买下或开玉匣获得一次"
		return {
			"title": String(def.get("name", iid)),
			"icon": String(def.get("icon", "")),
			"chip": " 未收录 ",
			"chip_color": GameStyle.GREY,
			"rows": [["品阶", ItemData.tier_label(tier_num), tier_col]],
			"notes": [],
			"body": "尚未拿到过这件法宝。买到或开出一次后，这里会显示它的完整效果。",
			"foot": lock_foot,
		}

	var rows: Array = [
		["品阶", ItemData.tier_label(tier_num), tier_col],
		# 词与商店那张详情卡对齐（2026-10-12 道具可出售）：这一行是数据表里的基准价，
		# 当回合上架价每回合还要 +2，写「买入价格」会让人以为自己付的就是这个数。
		["原价", "%d 金币" % int(def.get("price", 0)), GameStyle.PAPER_DIM],
		["出售返还", "%d 金币" % ItemData.sell_price(iid), GameStyle.JADE],
	]
	rows.append_array(BonusRows.apply_rows(def.get("apply", {})))
	var notes: Array[String] = []
	for line in String(def.get("desc", "")).split("\n"):
		if line.strip_edges() != "":
			notes.append(line.strip_edges())

	var resolved_foot := foot
	if resolved_foot == "":
		if not GameManager.is_item_unlocked(iid):
			resolved_foot = AchievementData.unlock_hint_text(iid, true, "收录条件：")
		elif bool(def.get("unique", false)):
			resolved_foot = "每局限购一件"
	return {
		"title": String(def.get("name", iid)),
		"icon": String(def.get("icon", "")),
		"chip": " " + ItemData.tier_label(tier_num) + " ",
		"chip_color": tier_col,
		"rows": rows,
		"notes": notes,
		"foot": resolved_foot,
	}


## 灵兽详情：定位 / 买价 / 出手周期 / 出售返还 + desc
static func pet_payload(pid: String, foot: String = "") -> Dictionary:
	var pdef := PetData.get_def(pid)
	if pdef.is_empty():
		return {}
	var p_col: Color = pdef.get("color", GameStyle.GOLD)
	var role_key := String(pdef.get("role", "attack"))
	var role_name := String(PetData.ROLES.get(role_key, "助战"))
	var base_price := int(pdef.get("base_price", 0))
	var rows: Array = [
		["定位", role_name, p_col],
		["基础买价", "%d 金币" % base_price, GameStyle.JADE],
		["出手周期", "%.1f 秒" % float(pdef.get("base_cooldown", 1.0)), GameStyle.PAPER],
		["出售返还", "%d 金币" % int(float(base_price) * PetData.SELL_RATIO), GameStyle.JADE],
	]
	var notes: Array[String] = []
	var desc := String(pdef.get("desc", "")).strip_edges()
	if not desc.is_empty():
		notes.append(desc)
	notes.append("灵兽属性吃「灵兽伤害 / 灵兽效果 / 灵兽冷却」加成")
	notes.append("普通修士限带 1 只，御兽师最多随行 3 只")
	return {
		"title": String(pdef.get("name", "")),
		"chip": " 灵兽 ",
		"chip_color": p_col,
		"rows": rows,
		"notes": notes,
		"foot": foot if foot != "" else "仅在金币阁有售，购买后永久随行",
	}
