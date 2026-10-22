class_name UnitConsistencyTests
extends UnitTestsBase

## desc/apply 一致性守卫（2026-10-11）：UpgradeData / ItemData / SkillData 三张表的头注都宣示
## 「数值与生效值同源」。2026-10-11 土豆兄弟式改版后同源由渲染器保证：卡面加成行由 BonusRows
## 从 apply 直接生成（正绿负红），desc 不再手抄数值、只写机制说明——故判据改为两条：
## ① apply 每个字段都在 FIELD_FORM 登记过展示口径（渲染器能显示，不会漏原始 key）；
## ② desc 残余的每个数字都能被 apply 解释或走 ORPHAN_ALLOW（机制性数字如上限/触发次数）。
## 字段→展示口径登记在 FIELD_FORM，新增 apply 字段必须来此登记口径。
##
## 展示口径（与三张表现有写法一一对应）：
##   pct  —— 字段存分数，展示写 ±round(v*100)%（0.15 → +15%、-0.06 → -6%）
##   mul  —— 字段存乘数，展示写 ±round((v-1)*100)%（0.88 → -12%、1.04 → +4%）
##   flat —— 平值（2.0 → 2、-1.0 → -1、0.5 → 0.5），正负号跟展示

const FORM_PCT := "pct"
const FORM_MUL := "mul"
const FORM_FLAT := "flat"

const FIELD_FORM := {
	"weapon_damage_mult": FORM_PCT,
	"move_speed_mult": FORM_PCT,
	"pickup_range_mult": FORM_PCT,
	"attack_range_mult": FORM_PCT,
	"crit_rate": FORM_PCT,
	"crit_mult": FORM_PCT,
	"dodge": FORM_PCT,
	"lifesteal": FORM_PCT,
	"knockback_mult": FORM_PCT,
	"xp_gain_mult": FORM_PCT,
	"thorns": FORM_PCT,
	"elite_damage": FORM_PCT,
	"element_damage_all": FORM_PCT,
	"element_damage_metal": FORM_PCT,
	"element_damage_wood": FORM_PCT,
	"element_damage_water": FORM_PCT,
	"element_damage_fire": FORM_PCT,
	"element_damage_earth": FORM_PCT,
	"attack_speed_mult_mul": FORM_MUL,
	"shop_price_mul": FORM_MUL,
	"melee_damage": FORM_FLAT,
	"ranged_damage": FORM_FLAT,
	"elemental_damage": FORM_FLAT,
	"engineering_damage": FORM_FLAT,
	"contraption_damage": FORM_FLAT,
	"armor": FORM_FLAT,
	"max_hp": FORM_FLAT,
	"hp_heal": FORM_FLAT,
	"hp_regen": FORM_FLAT,
	"harvest": FORM_FLAT,
	"spirit_stones": FORM_FLAT,
	"free_rerolls": FORM_FLAT,
	"bonus_pierce": FORM_FLAT,
	"luck": FORM_FLAT,
	# 2026-10-11 寻宝流：数量与品质是「几口 / 几点」的平值；2026-10-12 第三条腿改抬兑现量，
	# 宝箱掉落是乘区分数（0.35 → +35%），与 StatInfoData.FIELDS 的 "pct" 口径同源
	"chest_count": FORM_FLAT,
	"chest_quality": FORM_FLAT,
	"chest_reward": FORM_PCT,
	# 2026-10-12 灵兽系统加点与法宝属性
	"pet_damage_mult": FORM_PCT,
	"pet_effect_mult": FORM_PCT,
	"pet_cooldown_mult_mul": FORM_MUL,
	"pet_slots": FORM_FLAT,
	"skill_cooldown_mult": FORM_PCT,
}

## 文案中允许出现、但不被 apply 解释的数字（键为条目 id；百分比记整数值，平值记数值）
const ORPHAN_ALLOW := {
	"atk_up": [100],         # 超过100%后收益减半
	"critdmg_up": [250],     # 上限250%
	"grand_atk": [100],      # 超过100%后收益减半
	"dodge_up": [60],        # 上限60%
	"crit_up": [75],         # 上限75%
	"lifesteal_up": [1, 3],  # 吸取1点生命（每秒最多3次）
	"tisi_kuilei": [50],     # 免死并恢复50%生命
	"huichun_hulu": [15],    # 兜底：波末回血由 wave_heal_pct 机制字段解释
	# 2026-10-12 转化核心件：机制数字由各自额外字段承载（apply 留空），在此登记口径
		"jifeng_ren": [10, 4],         # 移速每超基础10% → 全伤害+4%（dmg_per_move_speed 0.04）
		"huanying_ling": [10, 5],      # 每10%闪避 → +5%暴击率（crit_per_dodge 0.05）
		"shanyue_jia": [1.5],          # 每点护甲+1.5%（dmg_per_armor 0.015）
		"xuepan_guyu": [25, 1],        # 每25点最大生命+1%（dmg_per_max_hp 0.02，除数固定 /50.0）
		"jubao_pen": [100, 3, 30],     # 每100灵石+3%，至多+30%（dmg_per_100_stones 0.03 / stone_dmg_cap 0.30）
		"ranxue_fu": [10, 2.5],        # 每损失10%生命+2.5%（dmg_per_missing_hp 0.025）
	"budong_yin": [1, 30],         # 站定1秒+30%（still_seconds 1.0 / still_damage 0.30）
	"zhekou_yufu": [8, 7],         # 商店全场 8 折，最多叠到 7 折（shop_price_mul 0.92 → 折扣以「折」表述）
	# 2026-10-12 深度联动与站定流法宝（14 件）
	"dazuo_putuan": [2],
	"ruding_xiang": [25, 3],
	"xuanwu_fashan": [60, 3],
	"jingang_shenxiang": [-30, 30],
	"panshi_yin": [1, 45],
	"sanmei_guizhen": [4, 1, 15],
	"lingsui_danqi": [3, 25, 15],
	"liuyun_qianyin": [50, 3],
	"jinmang_souhun": [2],
	"tiangong_fatiao": [20, 30],
	"qianfu_lianhuan": [1],
	"kaishan_jianyi": [25, 1, 2],
	"ningshen_fu": [12],
	"tupo_guyu": [3, 0.5, 1, 30, 5, 10],
	# 2026-10-21 角色专属转化件（机制数字由额外字段承载，apply 留空或只承担代偿）
	"zhanqi": [1, 0.8, 24],
	"cangzhen_juan": [1, 1.5, 30],
	"xuehai_fu": [1, 1.5, 10],
	"wanshi_jian": [1],
}

static func _strip_bbcode(s: String) -> String:
	var re := RegEx.new()
	re.compile("\\[[^\\]]*\\]")
	return re.sub(s, "", true)

## 把文案里所有数字抓出来：{pct: 带 ± 的整数值数组, flat: 带 ± 的浮点数组}
## 百分比先整体摘掉再做平值扫描，避免 "12%" 又被当成平值 12
static func _extract_tokens(plain: String) -> Dictionary:
	var re_pct := RegEx.new()
	re_pct.compile("[+-]?\\d+(?:\\.\\d+)?%")
	var re_flat := RegEx.new()
	re_flat.compile("[+-]?\\d+(?:\\.\\d+)?")
	var pcts: Array = []
	for m in re_pct.search_all(plain):
		pcts.append(float(m.get_string().trim_suffix("%").replace("+", "")))
	var flats: Array = []
	for m in re_flat.search_all(re_pct.sub(plain, " ", true)):
		flats.append(float(m.get_string().replace("+", "")))
	return {"pct": pcts, "flat": flats}

## ORPHAN_ALLOW 命中判定：显式数值比较（GDScript 的 in 对 1.0 vs 1 这类跨 int/float 不做宽松相等）
static func _allow_hit(allow: Array, v: float) -> bool:
	for a in allow:
		if absf(float(a) - v) <= 0.051:
			return true
	return false

## 核心判据（2026-10-11 改版后）：
## ① apply 每个字段都在 FIELD_FORM 登记展示口径（卡面加成行由 BonusRows 生成，登记即可显示）；
## ② 文案残余数字都能被字段解释（或走 ORPHAN_ALLOW）——desc 已不复述数值，机制性数字除外
static func _check_desc_matches_apply(_c: TestCheck, table: String, id: String, desc: String, apply: Dictionary, extra_pct_claims: Array = []) -> void:
	var toks := _extract_tokens(_strip_bbcode(desc))
	var claimed_pct: Array = []
	var claimed_flat: Array = []
	var probs: Array = []

	# hp_heal 与 max_hp 同值时是「+N 并回满」的同一份口径，不要求出两个数
	var eff := apply.duplicate()
	if eff.has("hp_heal") and eff.has("max_hp") and absf(float(eff["hp_heal"]) - float(eff["max_hp"])) <= 0.001:
		eff.erase("hp_heal")

	for field in eff.keys():
		var v := float(eff[field])
		var form: String = FIELD_FORM.get(field, "")
		if form.is_empty():
			probs.append("字段 %s 未在 FIELD_FORM 登记展示口径" % field)
			continue
		# 卡面数字由 BonusRows 从 apply 生成，不再要求 desc 里找到对应数字；
		# claimed_* 照记，供方向②放行与 apply 同值的残余文案数字。
		match form:
			FORM_PCT:
				claimed_pct.append(int(round(v * 100.0)))
			FORM_MUL:
				claimed_pct.append(int(round((v - 1.0) * 100.0)))
			FORM_FLAT:
				claimed_flat.append(v)

	for p in extra_pct_claims:
		claimed_pct.append(int(round(float(p) * 100.0)))

	var allow: Array = ORPHAN_ALLOW.get(id, [])
	for t in toks.pct:
		if not (t in claimed_pct) and not _allow_hit(allow, float(t)):
			probs.append("文案数字 %d%% 未被任何字段解释" % t)
	for t in toks.flat:
		var ok := _allow_hit(allow, t)
		if not ok:
			for cf in claimed_flat:
				if absf(cf - t) <= 0.051:
					ok = true
					break
		if not ok:
			probs.append("文案数字 %s 未被任何字段解释" % t)

	_c.check(probs.is_empty(), "%s/%s 文案与 apply 同源（问题: %s）" % [table, id, "；".join(PackedStringArray(probs))])

func _test_upgrade_desc_apply() -> void:
	for u in UpgradeData.UPGRADES:
		_check_desc_matches_apply(_c, "UpgradeData", String(u.get("id", "")), String(u.get("desc", "")), u.get("apply", {}))

## ---------------- 图标断链守卫（2026-10-12） ----------------
## 根因：悟道加点「灵兽疾行」「万兽灵契」的 icon 指向从未生成过的 assets/art/*.png，
## 而 LevelUpDialog 用 `ResourceLoader.exists()` 兜底 ⇒ 文件不在就静默不贴图，卡片只剩一个
## 空墨底框，不报错不报红，跟着 v0.0.24 一路上线。这里把「表里写了路径 ⇒ 文件必须在」钉成判据。
## 空 icon 是设计内占位（神通影爆/服丹用 glyph 字面显示），但白名单外多一条空路径同样报红——
## 那意味着新条目压根没配图，玩家看到的还是一样露白。
const ICON_PLACEHOLDER := {
	"SkillData:shadowburst": true,  ## 影爆：glyph「爆」
	"SkillData:elixir": true,       ## 服丹：glyph「丹」
}
## 扫到的非空 icon 路径条数下限：骤降说明遍历自己炸了（零记账不等于绿灯）
const ICON_FLOOR := 150

## 表名 → 该表所有条目的 {id, icon}；新增带 icon 的数据表要来这里挂上，否则守卫漏表
static func icon_rows() -> Array[Array]:
	var rows: Array[Array] = []
	for u in UpgradeData.UPGRADES:
		rows.append(["UpgradeData", String(u.get("id", "")), String(u.get("icon", ""))])
	for tid in ItemData.all_ids():
		rows.append(["ItemData", String(tid), String(ItemData.get_def(tid).get("icon", ""))])
	for wid in WeaponData.DEFS.keys():
		rows.append(["WeaponData", String(wid), String(WeaponData.get_def(String(wid)).get("icon", ""))])
	for cid in CultivatorData.all_ids():
		rows.append(["CultivatorData", String(cid), String(CultivatorData.get_def(cid).get("icon", ""))])
	for sid in SkillData.all_ids():
		rows.append(["SkillData", String(sid), String(SkillData.get_def(sid).get("icon", ""))])
	return rows

func _test_icon_assets_exist() -> void:
	var rows := icon_rows()
	var checked := 0
	var empties: Array[String] = []
	var broken: Array[String] = []
	var by_table := {}
	for row in rows:
		var table := String(row[0])
		var key := "%s:%s" % [table, String(row[1])]
		var path := String(row[2])
		by_table[table] = int(by_table.get(table, 0)) + 1
		if path.is_empty():
			empties.append(key)
			continue
		checked += 1
		if not ResourceLoader.exists(path):
			broken.append("%s → %s" % [key, path])
	_c.check(not by_table.is_empty(), "图标守卫扫到了条目（各表条数：%s）" % str(by_table))
	_c.check(checked >= ICON_FLOOR,
			"图标守卫扫到 %d 条 icon 路径，不低于下限 %d（骤降=遍历空转）" % [checked, ICON_FLOOR])
	_c.check(broken.is_empty(), "全部 %d 条 icon 路径都指向真实文件（断链：%s）" % [
			checked, "; ".join(PackedStringArray(broken))])
	# 空 icon 只许是白名单里那几条占位；新条目漏配图=玩家看见露白框，同样要拦
	var unlisted: Array[String] = []
	for empty_key in empties:
		if not ICON_PLACEHOLDER.has(empty_key):
			unlisted.append(String(empty_key))
	_c.check(unlisted.is_empty(), "空 icon 条目未超出占位白名单（白名单外：%s）" % "; ".join(PackedStringArray(unlisted)))

func _test_item_desc_apply() -> void:
	for item_id in ItemData.all_ids():
		var d := ItemData.get_def(item_id)
		# wave_heal_pct / revive 走独立机制字段，有数字时也算已被文案解释
		var extra: Array = []
		if d.has("wave_heal_pct"):
			extra.append(float(d["wave_heal_pct"]))
		_check_desc_matches_apply(_c, "ItemData", String(item_id), String(d.get("desc", "")), d.get("apply", {}), extra)

func _test_skill_desc_apply() -> void:
	# 神通卡文案不带富文本，直接对 power 百分比与「N秒」持续时长做同源断言
	for sid in SkillData.all_ids():
		var d := SkillData.get_def(sid)
		var desc := String(d.get("desc", ""))
		var probs: Array = []
		var toks := _extract_tokens(desc)
		if d.has("power") and "%" in desc:
			var want := float(d["power"]) * 100.0
			var hit := false
			for p in toks.pct:
				if absf(float(p) - want) <= 0.05:
					hit = true
					break
			if not hit:
				probs.append("power=%s 与文案百分比不一致（期望 %s%%）" % [d["power"], want])
		# 附加效果的数值也要在文案里对得上账（2026-10-11 技能改版新增字段）
		for extra_key in ["dodge_add", "pet_heal_pct"]:
			if d.has(extra_key) and float(d[extra_key]) > 0.0 and "%" in desc:
				var want_extra := float(d[extra_key]) * 100.0
				var hit := false
				for p in toks.pct:
					if absf(float(p) - want_extra) <= 0.05:
						hit = true
						break
				if not hit:
					probs.append("%s=%s 与文案百分比不一致（期望 %s%%）" % [extra_key, d[extra_key], want_extra])
		if d.has("duration") and "秒" in desc:
			var re := RegEx.new()
			re.compile("(\\d+(?:\\.\\d+)?)\\s*秒")
			# 「N秒」可被 duration / iframe / crit_window / pet_duration 解释
			# （冲刺文案报无敌窗口与必暴窗口，治疗文案报灵兽存活时长）
			var anchors: Array = [float(d["duration"])]
			if d.has("iframe"):
				anchors.append(float(d["iframe"]))
			if d.has("crit_window"):
				anchors.append(float(d["crit_window"]))
			if d.has("pet_duration"):
				anchors.append(float(d["pet_duration"]))
			for m in re.search_all(desc):
				var v := float(m.get_string(1))
				var explained := false
				for a_v in anchors:
					if absf(v - float(a_v)) <= 0.001:
						explained = true
						break
				if not explained:
					probs.append("文案「%s秒」与 duration/iframe/crit_window/pet_duration 均不一致" % m.get_string(1))
		if d.has("knockback_boost") and absf(float(d["knockback_boost"]) - 1.0) > 0.001 and "倍" in desc:
			var want_kb := float(d["knockback_boost"])
			var kb_re := RegEx.new()
			kb_re.compile("(\\d+(?:\\.\\d+)?)\\s*倍")
			var kb_ok := false
			for m in kb_re.search_all(desc):
				if absf(float(m.get_string(1)) - want_kb) <= 0.001:
					kb_ok = true
					break
			if not kb_ok:
				probs.append("knockback_boost=%s 与文案「N倍」不一致" % d["knockback_boost"])
		_c.check(probs.is_empty(), "SkillData/%s 文案与数值同源（问题: %s）" % [sid, "；".join(PackedStringArray(probs))])

# ---------------- 羁绊 effects → 生效值 → 生成文案 对账（2026-10-11） ----------------
## 同一份羁绊幅度以前存三处：SynergySystem 硬编码 side list、WeaponData.desc 手抄一句、
## SynergyUI.TIER_LINES 再手抄一句。2026-10-11 给木系/召唤补伤害乘区时只改了前两处，
## 局内阶梯行于是漏报一整条白送的加成，火系那行还印着属性表里根本不存在的「法伤」。
## 现在数值只在 SYNERGIES.effects 一份、文案由它生成，本判据守住三个洞：
##   ① GameManager 上每条 synergy_* 属性都必须在册 —— 漏登记就是跨波不清零的隐形 Bug；
##   ② 走生产入口 apply_counts 真结算：每条声明效果的 field 增量必须等于表里的数，
##      且不许有任何未声明的 synergy_* 字段被改（隐性加成，玩家看不见的那一条）；
##   ③ 生成的阶梯行里每条声明效果的数字都必须在场，且件数对得上（漏一条 = 白送不显示）。
const SYNERGY_FORMS := ["pct", "pct_down", "flat", "flat1"]

func _test_synergy_effects_text() -> void:
	var fields: Array = WeaponData.SYNERGY_FIELDS
	for prop in GameManager.get_property_list():
		var pname := String(prop.get("name", ""))
		if pname.begins_with("synergy_"):
			_c.check(fields.has(pname), "GameManager.%s 未登记进 WeaponData.SYNERGY_FIELDS" % pname)

	for tag in WeaponData.SYNERGIES.keys():
		var t := String(tag)
		var info: Dictionary = WeaponData.SYNERGIES[tag]
		var ths: Array = info.get("thresholds", [])
		var effs: Array = info.get("effects", [])
		_c.check(not info.has("desc"), "SYNERGIES/%s 不许再手写 desc（文案只能由 effects 生成）" % t)
		_c.check(not effs.is_empty(), "SYNERGIES/%s 一条效果都没声明，局内阶梯行会是空串" % t)
		for eff in effs:
			var field := String(eff.get("field", ""))
			var form := String(eff.get("form", ""))
			var vals: Array = info.get(String(eff.get("list", "values")), [])
			_c.check(fields.has(field), "SYNERGIES/%s 的效果指向 %s，不在 SYNERGY_FIELDS 里" % [t, field])
			_c.check(SYNERGY_FORMS.has(form), "SYNERGIES/%s 的 %s 用了未知展示口径 %s" % [t, field, form])
			_c.check(vals.size() == ths.size(),
					"SYNERGIES/%s 的 %s 只有 %d 档数值，门槛却有 %d 档" % [t, field, vals.size(), ths.size()])

	for tag in WeaponData.SYNERGIES.keys():
		var t := String(tag)
		var effs: Array = SynergyUI.effects_for(t)
		var ths_now: Array = SynergyUI.thresholds_for(t)
		for tier in range(1, ths_now.size() + 1):
			# 先空结算一遍拿基数：清零表与 SYNERGY_BASE 不一致会在这里露出来
			SynergySystem.apply_counts(GameManager, {})
			var base := UnitConsistencyTests._synergy_snapshot(fields)
			SynergySystem.apply_counts(GameManager, {t: int(ths_now[tier - 1])})
			var want := base.duplicate()
			for eff in effs:
				var field := String(eff.get("field", ""))
				if not fields.has(field):
					continue
				var raw := SynergyUI.effect_value(t, eff, tier)
				if is_nan(raw):
					continue
				want[field] = float(want[field]) * raw if String(eff.get("op", "add")) == "mul" \
						else float(want[field]) + raw
			for f in fields:
				_c.near(float(GameManager.get(String(f))), float(want[String(f)]), EPS,
						"%s 第 %d 档：%s 实得 %s（期望 %s）" % [t, tier, f,
						GameManager.get(String(f)), want[String(f)]])
			_synergy_line_has_numbers(t, tier, effs)

	# 说明句（详情卡下方那句、图鉴同一句）的单位必须跟着 form 走：百分比档不许丢百分号。
	# 漏了这条，「武器伤害 +10/20/25」会被读成加 25 点裸伤；flat 档多写 % 同样要报红。
	for tag in WeaponData.SYNERGIES.keys():
		var dt := String(tag)
		var deffs: Array = SynergyUI.effects_for(dt)
		var segs: Array = SynergyUI.synergy_desc(dt).split("，")
		_c.check(segs.size() == deffs.size(),
				"SYNERGIES/%s 说明句拆出 %d 段，表里声明了 %d 条效果" % [dt, segs.size(), deffs.size()])
		for i in range(mini(segs.size(), deffs.size())):
			var eff: Dictionary = deffs[i]
			var seg := String(segs[i])
			var dform := String(eff.get("form", "flat"))
			var want_pct := dform == "pct" or dform == "pct_down"
			_c.check(seg.begins_with(String(eff.get("label", ""))),
					"SYNERGIES/%s 说明句第 %d 段「%s」没按声明顺序以效果名开头" % [dt, i + 1, seg])
			_c.check(seg.contains("%") == want_pct,
					"SYNERGIES/%s 的「%s」是 %s 档，说明句「%s」%s" % [dt, String(eff.get("label", "")),
					dform, seg, "丢了百分号" if want_pct else "多写了百分号"])

	SynergySystem.apply_counts(GameManager, {})
	GameManager.reset_run()

static func _synergy_snapshot(fields: Array) -> Dictionary:
	var out: Dictionary = {}
	for f in fields:
		out[String(f)] = float(GameManager.get(String(f)))
	return out

## 阶梯行必须把每条声明效果的数字都印出来：件数 == 效果条数，逐个数字能在文案里找到
## （实例方法：要往 _c 上记账）
func _synergy_line_has_numbers(tag: String, tier: int, effs: Array) -> void:
	var line := SynergyUI.tier_line(tag, tier)
	_c.check(not line.is_empty(), "SYNERGIES/%s 第 %d 档生成了空文案" % [tag, tier])
	_c.check(line.split(" · ").size() == effs.size(),
			"SYNERGIES/%s 第 %d 档印了 %d 条加成，表里声明了 %d 条（漏的那条玩家看不见）" % [
			tag, tier, line.split(" · ").size(), effs.size()])
	var toks := UnitConsistencyTests._extract_tokens(line)
	for eff in effs:
		var form := String(eff.get("form", "flat"))
		var raw := SynergyUI.effect_value(tag, eff, tier)
		if is_nan(raw):
			continue
		var is_pct := form == "pct" or form == "pct_down"
		# 连符号一起比：攻击间隔那类"越小越好"的档位必须印成 -6%，
		# 取绝对值比就放行不了"把变快写成变慢"这种方向反了的文案
		var want := SynergyUI.displayed_number(raw, form)
		var pool: Array = toks.pct if is_pct else toks.flat
		var hit := false
		for got in pool:
			if absf(float(got) - want) <= (0.51 if is_pct else 0.051):
				hit = true
				break
		_c.check(hit, "SYNERGIES/%s 第 %d 档文案「%s」里找不到 %s 的 %s" % [
				tag, tier, line, String(eff.get("label", "")), want])


func _test_ui_chip_contrast() -> void:
	# 1. 基础明度自适应规则：亮底必配黑字，暗底必配白字
	#    主题色已可切换（5 套预设），逐套断言 on_face_text 的明暗归类 —— 不能钉死「GOLD 必是暗面」，
	#    否则用户切成明黄/天青那四套亮色后，这条判据自己就假了。
	var prev_theme := GameStyle.current_theme()
	for preset in GameStyle.THEME_PRESETS:
		var pid: StringName = preset["id"]
		var main: Color = preset["main"]
		GameStyle.apply_theme_color(pid)
		var want: Color = GameStyle.INK_TEXT if main.get_luminance() > 0.5 else GameStyle.CHALK
		_c.check(GameStyle.on_face_text(main) == want,
			"主题「%s」主色 %s 必须配 %s（亮面黑字/暗面白字）" % [String(preset["name"]), main, want])
		_c.check(GameStyle.GOLD == main,
			"主题「%s」切换后 GOLD 归位为主色（实得 %s）" % [String(preset["name"]), GameStyle.GOLD])
	GameStyle.apply_theme_color(prev_theme)

	_c.check(GameStyle.on_face_text(GameStyle.JADE) == GameStyle.INK_TEXT, "点缀黄 JADE 属于亮面，必须配墨黑字 INK_TEXT")
	_c.check(GameStyle.on_face_text(GameStyle.SWEEP) == GameStyle.INK_TEXT, "琥珀金 SWEEP 属于亮面，必须配墨黑字 INK_TEXT")
	_c.check(GameStyle.on_face_text(GameStyle.GOOD) == GameStyle.INK_TEXT, "增益绿 GOOD 属于亮面，必须配墨黑字 INK_TEXT")
	_c.check(GameStyle.on_face_text(GameStyle.BAD) == GameStyle.CHALK, "朱砂红 BAD 属于暗面，必须配白字 CHALK")
	_c.check(GameStyle.on_face_text(GameStyle.NAVY2) == GameStyle.INK_TEXT, "宣纸白 NAVY2 属于亮面，必须配墨黑字 INK_TEXT")
	_c.check(GameStyle.on_face_text(GameStyle.INK) == GameStyle.CHALK, "纯黑 INK 属于暗面，必须配白字 CHALK")

	# 2. 遍历所有武器在图鉴中生成的色签，断言绝无亮底配白字或暗底配黑字
	for wid in WeaponData.DEFS.keys():
		var def := WeaponData.get_def(String(wid))
		var chips: Array = WeaponCodexBuilder.card_chips(wid, def)
		for chip in chips:
			var txt: String = String(chip[0])
			var face: Color = chip[1]
			var fg: Color = chip[2]
			var is_light := face.get_luminance() > 0.5
			if is_light:
				_c.check(fg == GameStyle.INK_TEXT, "武器 %s 标签「%s」底色 %s 为亮面，字色必须是黑字（实得 %s）" % [wid, txt, face, fg])
			else:
				_c.check(fg != GameStyle.INK_TEXT, "武器 %s 标签「%s」底色 %s 为暗面，字色不应是黑字（实得 %s）" % [wid, txt, face, fg])

## 主题色运行时切换：注册表必须把「已产出的按钮 stylebox」原地换成新色。
## 这是「即点即换」的核心契约 —— 旧实现 GOLD 是 const，换肤只能改源码重启；
## 现在靠 static var + 样式注册表回放。若注册表失效，已显示的按钮会留在旧色（用户点了没反应）。
func _test_theme_swap_runtime() -> void:
	var prev := GameStyle.current_theme()
	GameStyle.apply_theme_color(&"lime")
	var btn := Button.new()
	GameStyle.button(btn, GameStyle.GOLD, GameStyle.GOLD_EDGE, 12)
	var normal := btn.get_theme_stylebox("normal") as StyleBoxFlat
	_c.check(normal != null and normal.bg_color == GameStyle.THEME_PRESETS[0]["main"],
		"默认主题下按钮 normal 面取荧绿")
	# 切到天青：同一颗按钮的 normal StyleBox 必须就地变天青（不动节点引用）
	GameStyle.apply_theme_color(&"cyan")
	_c.check(normal.bg_color == GameStyle.theme_preset(&"cyan")["main"],
		"切换主题后已建按钮的 normal 面原地变天青（注册表回放生效，实得 %s）" % normal.bg_color)
	# 默认主题下 GOLD_EDGE 也要跟着变（hover 面）
	var hover := btn.get_theme_stylebox("hover") as StyleBoxFlat
	_c.check(hover.bg_color == GameStyle.theme_preset(&"cyan")["edge"],
		"切换主题后 hover 面原地变天青亮边")
	btn.free()
	GameStyle.apply_theme_color(prev)

## 主题预设表自身完整性：5 套、id 唯一、三件套齐备、默认荧绿
func _test_theme_presets() -> void:
	_c.check(GameStyle.THEME_PRESETS.size() == 5, "主题预设恰为 5 套（荧绿/品红/明黄/暖橙/天青）")
	var seen := {}
	for preset in GameStyle.THEME_PRESETS:
		_c.check(preset.has("id") and preset.has("name") and preset.has("main") \
				and preset.has("edge") and preset.has("dk"), "主题「%s」三件套字段齐备" % String(preset.get("name", "?")))
		var id: StringName = preset["id"]
		_c.check(not seen.has(id), "主题 id「%s」不重复" % String(id))
		seen[id] = true
	_c.check(GameStyle.THEME_PRESETS[0]["id"] == &"lime", "第一套（默认）是荧绿")
	_c.check(SettingsManager.THEME_DEFAULT == &"lime", "SettingsManager 默认主题与 GameStyle 首项同源")
	_c.check(SettingsManager.theme_color_label() == GameStyle.theme_name(SettingsManager.theme_color()),
		"设置页读到的主题名与当前主题一致")

