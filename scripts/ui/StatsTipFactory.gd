class_name StatsTipFactory
extends RefCounted

## 人物属性面板详情卡工厂
## 从 PlayerStatsDialog 抽离，集中承载道统、法宝、空槽位、法器及悟道历史的 DetailTip 数据组装。

static func _c(v: float) -> Color:
	if v > 0.0001:
		return GameStyle.GOOD
	if v < -0.0001:
		return GameStyle.BAD
	return GameStyle.PAPER

static func _mul(v: float) -> String:
	return "×%.2f" % v

static func _num(v: float) -> String:
	if absf(v - roundf(v)) < 0.0001:
		return "%d" % int(roundf(v))
	return "%.2f" % v

## 道统特性详解卡
static func open_cultivator_tip(host: Control, anchor: Control) -> Control:
	var def := CultivatorData.get_def(GameManager.cultivator_id)
	if def.is_empty():
		return null
	var rows: Array = []
	var pros: Array = def.get("pros", [])
	for i in range(pros.size()):
		rows.append(["加成 %d" % (i + 1), String(pros[i]), GameStyle.GOOD])
	var cons: Array = def.get("cons", [])
	for i in range(cons.size()):
		rows.append(["代偿 %d" % (i + 1), String(cons[i]), GameStyle.BAD])
	var skill_id := CultivatorData.get_synergy_skill_id(GameManager.cultivator_id)
	if not skill_id.is_empty():
		var sdef := SkillData.get_def(skill_id)
		var enh := SkillData.enhance_desc(skill_id, GameManager.cultivator_id)
		rows.append(["随行技能", "%s（%s）" % [String(sdef.get("name", skill_id)), enh if not enh.is_empty() else "无专属强化"], GameStyle.JADE])
	var start_equip := CultivatorData.get_start_equip(GameManager.cultivator_id)
	if not start_equip.is_empty():
		rows.append(["开局自带", start_equip, GameStyle.PAPER])

	var notes: Array[String] = []
	var allowed: Array = def.get("allowed_tags", [])
	if not allowed.is_empty():
		var tag_names: Array[String] = []
		for t in allowed:
			tag_names.append(String(WeaponData.SYNERGIES.get(String(t), {}).get("name", t)))
		notes.append("角色适配：商店大幅偏向「%s」系武器，仍有少量他派漏出。" % "、".join(tag_names))
	var locked: Array = def.get("locked_upgrades", [])
	if not locked.is_empty():
		var titles: Array[String] = []
		for uid in locked:
			titles.append(String(UpgradeData.get_upgrade_def(String(uid)).get("title", uid)))
		notes.append("加点锁定：「%s」与本角色无缘，升级候选中不会出现。" % "、".join(titles))

	return DetailTip.show_over(host, anchor, {
		"title": "%s · 角色特性" % String(def.get("name", "")),
		"chip": "角色",
		"chip_color": GameStyle.GOLD,
		"rows": rows,
		"body": "「%s」" % String(def.get("epithet", "")),
		"notes": notes,
		"foot": "加成与代偿开局即生效、全程不变；具体数值已计入左侧属性行与各条详解。",
	})

## 法宝详情卡
static func open_item_tip(host: Control, anchor: Control, item_id: String, count: int) -> Control:
	var def := ItemData.get_def(item_id)
	if def.is_empty():
		return null
	var tier_num: int = int(def.get("tier", 1))
	var tier_col: Color = ItemData.tier_color(tier_num)
	var rows: Array = [
		["品阶", ItemData.tier_label(tier_num), tier_col],
		["当前持有", "%d 件" % count, GameStyle.JADE],
	]
	var apply: Dictionary = def.get("apply", {})
	for key in apply.keys():
		var k := String(key)
		var v := float(apply[key])
		rows.append([StatInfoData.field_name(k), StatInfoData.format_amount(k, v), _c(v)])

	var desc_lines: Array = String(def.get("desc", "")).split("\n")
	var notes: Array[String] = [
		"被动道具：购入即永久生效，不占用上阵武器槽位。",
	]
	for line in desc_lines:
		var s := String(line).strip_edges()
		if not s.is_empty():
			notes.append(s)

	return DetailTip.show_over(host, anchor, {
		"title": String(def.get("name", item_id)),
		"chip": "%s道具" % ItemData.tier_label(tier_num),
		"chip_color": tier_col,
		"rows": rows,
		"body": "稀有道具：属性加成与升级同源叠加。",
		"notes": notes,
		"foot": "在波间商店可继续购置更多奇珍。",
	})

## 空/封印法器位详情卡
static func open_empty_slot_tip(host: Control, anchor: Control, index: int) -> Control:
	var max_slots: int = GameManager.max_weapon_slots()
	var locked: bool = index >= max_slots
	return DetailTip.show_over(host, anchor, {
		"title": "锁定武器位" if locked else "空武器位",
		"rows": [
			["上阵位", "第 %d 槽 / 上限 %d 槽" % [index + 1, max_slots]],
			["当前上阵", "%d 件" % GameManager.get_weapons_summary().size()],
			["背包", "%d 件" % GameManager.stash.size()],
		],
		"body": "本角色限制了上阵武器槽上限，此槽位不可装备。" if locked else "这一格还空着。武器按获得顺序自动补上阵武器位，不需要手动摆。",
		"notes": [
			"上阵 %d 格全满之后，新买的武器进背包，只用于合成与出售。" % max_slots,
			"上阵武器的数量（如 2/6、4/6、6/6）决定流派羁绊的激活档位。",
		],
		"foot": "波间在商店买武器即可补上空槽。",
	})

## 法器详情卡
static func open_weapon_tip(host: Control, anchor: Control, w: Dictionary, from_stash: bool) -> Control:
	var id: String = String(w.get("id", ""))
	var def := WeaponData.get_def(id)
	if def.is_empty():
		return null
	var star := clampi(int(w.get("star", 1)), 1, WeaponData.MAX_STAR)
	var base_dmg: float = float(def.get("damage", 0.0))
	var star_mul: float = pow(WeaponData.STAR_DAMAGE_MULT, float(star - 1))
	var bonus: float = GameManager.get_weapon_stat_bonus(id, star)
	var gm_dmg: float = GameManager.weapon_damage_mult
	var syn_dmg: float = GameManager.synergy_damage_mult
	var cult_dmg: float = GameManager.cultivator_damage_mult(id)
	var elem_dmg: float = GameManager.element_damage_mult(id)
	var per_hit: float = (base_dmg * star_mul + bonus) * gm_dmg * syn_dmg * cult_dmg * elem_dmg
	var cd: float = WeaponData.cooldown_for(id, star) * GameManager.attack_speed_mult * GameManager.synergy_haste_mult
	var base_range: float = float(def.get("range", 0.0))
	var eff_range: float = base_range * GameManager.attack_range_mult * GameManager.synergy_range_mult
	var range_buffed: bool = not is_equal_approx(eff_range, base_range)
	var range_txt: String = "%.0f" % eff_range
	if range_buffed:
		range_txt = "%.0f（基础 %.0f）" % [eff_range, base_range]

	var syn_parts: Array[String] = []
	for t in def.get("tags", []):
		var sinfo: Dictionary = WeaponData.SYNERGIES.get(t, {})
		if not sinfo.is_empty():
			var cnt: int = GameManager.get_tag_count(String(t))
			syn_parts.append("%s(%d/6)" % [sinfo.get("name", t), cnt])

	var rows: Array = [
		["单发伤害", "%.1f" % per_hit, GameStyle.JADE],
		["流派进度", " · ".join(syn_parts) if not syn_parts.is_empty() else "—", GameStyle.GOOD],
		["基础 × 星级", "%.0f × %.1f" % [base_dmg, star_mul]],
		["属性转化", "+%.1f" % bonus, _c(bonus)],
		["全局×羁绊", "%s × %s" % [_mul(gm_dmg), _mul(syn_dmg)], _c(gm_dmg * syn_dmg - 1.0)],
		["角色×元素", "%s × %s" % [_mul(cult_dmg), _mul(elem_dmg)], _c(cult_dmg * elem_dmg - 1.0)],
		["攻击范围", range_txt, GameStyle.JADE if range_buffed else GameStyle.PAPER],
		["攻击间隔", "%.2f 秒" % cd],
	]
	var feats := weapon_feats(def)
	if not feats.is_empty():
		rows.append(["特性", feats])

	var notes: Array[String] = [
		"单发伤害 =（基础 × 星级 + 属性转化）× 全局法伤 × 流派羁绊 × 角色 × 元素；暴击另按 %.0f%% 概率 ×%.2f 结算。" % [
			GameManager.get_crit_rate() * 100.0, GameManager.crit_mult + GameManager.synergy_crit_mult],
		"%s（每星效率 +25%%）。" % WeaponData.scaling_desc(id),
		"升星：同名同星集满 3 件在商店合成，伤害 ×%s、攻击间隔 ×%s，最高 %s。" % [
			_num(WeaponData.STAR_DAMAGE_MULT), _num(WeaponData.STAR_COOLDOWN_MULT), WeaponData.star_text(WeaponData.MAX_STAR)],
	]

	var foot := "同名同星 %d 件 · 出售可得 %d 枚" % [
		GameManager.count_copies(id, star), WeaponData.sell_price(id, star)]
	if from_stash:
		foot += "\n在背包里：未上阵、不出手、不吃羁绊，只用于合成与出售。"

	return DetailTip.show_over(host, anchor, {
		"title": "%s %s" % [String(def.get("name", "武器")), WeaponData.star_text(star)],
		"chip": " · ".join(syn_parts) if not syn_parts.is_empty() else String(def.get("tag", "")),
		"chip_color": GameStyle.JADE_DK if from_stash else GameStyle.GOLD_DK,
		"rows": rows,
		"body": String(def.get("desc", "")),
		"notes": notes,
		"foot": foot,
	})

static func weapon_feats(def: Dictionary) -> String:
	var out: Array[String] = []
	if int(def.get("behavior", -1)) == WeaponData.Behavior.PROJECTILE:
		out.append("锁敌追击")
	var pierce: int = int(def.get("pierce", 0))
	if pierce > 0:
		out.append("穿透 %d" % (pierce + GameManager.bonus_pierce))
	var count: int = int(def.get("projectile_count", 1))
	if count > 1:
		out.append("一次 %d 段" % count)
	var bounce: int = int(def.get("bounce_count", 0))
	if bounce > 0:
		out.append("弹射 %d 次" % bounce)
	var arc: float = float(def.get("arc_scale", 1.0))
	if arc > 1.001:
		out.append("横扫 ×%s" % _num(arc))
	if bool(def.get("proc_poison", false)):
		out.append("附毒")
	if bool(def.get("proc_burn", false)):
		out.append("灼烧")
	if float(def.get("proc_chill", 0.0)) > 0.0:
		out.append("冰缓")
	return "、".join(out)

## 悟道历史详情卡
static func open_history_tip(host: Control, anchor: Control, item: Dictionary) -> Control:
	var id: String = String(item.get("id", ""))
	var def := UpgradeData.get_upgrade_def(id)
	var apply: Dictionary = def.get("apply", {})
	var taken: int = int(item.get("count", 1))
	var cap: int = int(def.get("max_stacks", 0))
	var t: float = float(item.get("time", 0.0))

	var rows: Array = []
	for key in apply.keys():
		var k := String(key)
		var v := float(apply[key])
		rows.append([StatInfoData.field_name(k), StatInfoData.format_amount(k, v), _c(v)])
	rows.append(["已领悟", "第 %d 次 / 上限 %d 次" % [taken, cap],
		GameStyle.JADE if cap > 0 and taken >= cap else GameStyle.PAPER])
	rows.append(["领悟于", "Lv.%d · %02d:%02d" % [int(item.get("level", 1)), int(t / 60.0), int(t) % 60]])
	if cap > 0 and taken >= cap:
		rows.append(["状态", "已叠满，不再出现在候选里", GameStyle.GREY])

	var notes: Array[String] = [
		"升级只攒点数，每波敌潮平息后统一加点；选定即生效、不可撤销，同一条最多领悟 %d 次，叠满后从池子里剔除。" % cap,
		"领悟时卡片上写的那点幅度，就是真正落地的幅度：不会另有一本账。",
	]
	var stat_id := ""
	for key in apply.keys():
		var sid: String = StatInfoData.stat_of_field(String(key))
		if not sid.is_empty():
			stat_id = sid
			break
	var foot := "" if stat_id.is_empty() else "这一条落在左侧「%s」那一行，点它可以看来源拆解。" % StatInfoData.title(stat_id)

	return DetailTip.show_over(host, anchor, {
		"title": String(item.get("title", "升级")),
		"chip": String(item.get("rarity_label", "普通")),
		"chip_color": item.get("border_color", GameStyle.GOLD_DK),
		"rows": rows,
		"body": String(item.get("desc", "")),
		"notes": notes,
		"foot": foot,
	})
