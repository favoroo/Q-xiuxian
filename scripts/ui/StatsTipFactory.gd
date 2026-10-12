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
	# 额外技能单独一行一段（与选角界面同读机制表，不再混在「加成 N」里）
	for x_line in CultivatorData.get_extra_desc(GameManager.cultivator_id):
		rows.append(["额外技能", String(x_line), GameStyle.SHADOW])
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
	# 加成行（2026-10-11 改版）：统一走 BonusRows —— 乘算字段（攻击间隔/物价）按语义判色，
	# 修正旧 _c 按符号判色把「物价上涨」也染绿的口径问题
	rows.append_array(BonusRows.apply_rows(def.get("apply", {})))

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
## benefit_note：从「受益装备」那一排图标点进来时带上的一句话（这条悟道走的哪条链路），
## 其余入口（HUD 法器栏 / 属性面板 / 商店）留空，卡片内容一字不差是同一张。
static func open_weapon_tip(host: Control, anchor: Control, w: Dictionary, from_stash: bool,
		benefit_note: String = "") -> Control:
	var id: String = String(w.get("id", ""))
	var def := WeaponData.get_def(id)
	if def.is_empty():
		return null
	var star := clampi(int(w.get("star", 1)), 1, WeaponData.MAX_STAR)
	var bonus: float = GameManager.get_weapon_stat_bonus(id, star)
	var gm_dmg: float = GameManager.weapon_damage_mult
	var syn_dmg: float = GameManager.synergy_damage_mult
	var cult_dmg: float = GameManager.cultivator_damage_mult(id)
	var elem_dmg: float = GameManager.element_damage_mult(id)
	# Fixed: 单发以前在这里自己乘了一遍乘区，漏了神识分流与机关羁绊，与运行时跳字不符；
	# 现在与货架卡、商店详情同读 WeaponDamageReadout 一个数。
	var per_hit: float = WeaponDamageReadout.per_hit(id, star)
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

	# 逐行列出的乘区必须能乘回头条「单发伤害」，所以多法器分流与机关羁绊两行不能省
	# （2026-10-11：以前这两档根本没进 per_hit，面板列出来的因子乘完比跳字高一大截）。
	# 每个数前面都带上它自己的名字（2026-10-11 用户「看不懂」口径）：旧写法
	# 「全局×羁绊    ×1.25 × ×1.20」两个乘号连排，玩家分不清哪个数是全局、哪个是羁绊；
	# 行名也不再单写「神识」——这个词全游戏没任何一处解释过。
	var split := WeaponDamageReadout.slot_split_mult(-1, id)
	var factor_rows: Array = [
		["全局与羁绊", "全局 %s · 羁绊 %s" % [_mul(gm_dmg), _mul(syn_dmg)],
				_c(gm_dmg * syn_dmg - 1.0)],
		["角色与五行", "角色 %s · 五行 %s" % [_mul(cult_dmg), _mul(elem_dmg)],
				_c(cult_dmg * elem_dmg - 1.0)],
	]
	# 影层增伤是条件乘区（影者攒着影层才 >1），乘区链要能乘回单发伤害，所以有就列、没有就不列；
	# 层数从乘区反推（amp == 1 + n×AMP_PER_STACK 严格成立，Player 只在这两处写）
	if not is_equal_approx(GameManager.shadow_amp_mult, 1.0):
		var amp_stacks := int(roundf((GameManager.shadow_amp_mult - 1.0) / ShadowStepData.AMP_PER_STACK))
		factor_rows.append(["影层增伤", "%s（影 %d 层）" % [_mul(GameManager.shadow_amp_mult), amp_stacks],
				_c(GameManager.shadow_amp_mult - 1.0)])
	factor_rows.append(["多法器分流", "上阵 %d 把 · 每把 %s" % [GameManager.slots_used(), _mul(split)],
			_c(split - 1.0)])
	if WeaponDamageReadout.is_turret(def):
		var contraption := WeaponDamageReadout.contraption_mult()
		factor_rows.append(["机关羁绊", _mul(contraption), _c(contraption - 1.0)])
	# 环绕类不再单列一行乘区：召唤羁绊那档伤害 2026-10-11 起并在全局「武器伤害」里，
	# 上面「全局与羁绊」那行的羁绊数就是它实际吃的数（与 SunOrb 伤害链同形）。

	var rows: Array = [
		["攻击方式", WeaponData.behavior_label(def), behavior_color(def)],
		["单发伤害", WeaponDamageReadout.arrow_text(WeaponData.damage_for(id, star), per_hit),
				GameStyle.JADE],
		[WeaponDamageReadout.per_second_label(id),
				BonusRows.fmt_num(WeaponDamageReadout.per_second(id, star)), GameStyle.JADE],
		["流派进度", " · ".join(syn_parts) if not syn_parts.is_empty() else "—", GameStyle.GOOD],
		["属性加伤", "+%s" % BonusRows.fmt_num(bonus), _c(bonus)],
	] + factor_rows + [
		["攻击范围", range_txt, GameStyle.JADE if range_buffed else GameStyle.PAPER],
	]
	var feats := weapon_feats(def)
	if not feats.is_empty():
		rows.append(["特性", feats])

	var notes: Array[String] = [
		# 公式句保持原有长度：详情卡定宽 306、notes 走 autowrap，多折一行就把卡底往下推
		# （BenefitIconTapCheck 按「卡不许出屏」判）。行名换成「多法器分流」多的两个字，
		# 用把「全局法伤」缩成「全局」抵平 —— 这两个乘区本来就有各自的行按名字列着，不丢信息。
		"单发伤害 =（基础 × 星级 + 属性加伤）× 全局 × 羁绊 × 角色 × 五行 × 多法器分流；" \
				+ "暴击与斩将按目标另算。",
		WeaponDamageReadout.bonus_bill_text(id, star),
		"升星：同名同星集满 3 件在商店合成，伤害 ×%s、攻击间隔 ×%s，最高 %s。" % [
			_num(WeaponData.STAR_DAMAGE_MULT), _num(WeaponData.STAR_COOLDOWN_MULT), WeaponData.star_text(WeaponData.MAX_STAR)],
	]
	if not benefit_note.is_empty():
		notes.push_front(benefit_note)

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

## 攻击方式的类别色：近战朱砂 / 非近战主蓝（红蓝二值）——
## 货架卡色签与详情卡「攻击方式」值色都走这里，改色只动这一处。
static func behavior_color(def: Dictionary) -> Color:
	return GameStyle.BAD if WeaponData.behavior_label(def) == "近战" else GameStyle.GOLD

static func weapon_feats(def: Dictionary) -> String:
	var out: Array[String] = []
	if int(def.get("behavior", -1)) == WeaponData.Behavior.PROJECTILE:
		out.append("锁敌追击")
	var pierce: int = int(def.get("pierce", 0))
	if pierce > 0:
		out.append("穿透 %d" % (pierce + GameManager.bonus_pierce))
	var count: int = int(def.get("projectile_count", 1))
	if count > 1:
		out.append("一次 %d 发" % count)
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

	var rows: Array = BonusRows.apply_rows(apply)
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

	# 纯数值项的 desc 已不再复述数字（卡面加成行由 BonusRows 从 apply 生成，见 UpgradeData 头注），
	# 「解释」由口径说明兜底——判据 StatsTipCheck 要求每张点开的卡都有解释行
	var body := String(item.get("desc", ""))
	if body.is_empty():
		body = "这一条的加成幅度就是上面几行读数：与生效数值同源，选中即生效、不可撤销。"

	return DetailTip.show_over(host, anchor, {
		"title": String(item.get("title", "升级")),
		"chip": String(item.get("rarity_label", "普通")),
		"chip_color": item.get("border_color", GameStyle.GOLD_DK),
		"rows": rows,
		"body": body,
		"notes": notes,
		"foot": foot,
	})
