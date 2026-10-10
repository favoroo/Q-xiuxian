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
	"armor": FORM_FLAT,
	"max_hp": FORM_FLAT,
	"hp_heal": FORM_FLAT,
	"hp_regen": FORM_FLAT,
	"harvest": FORM_FLAT,
	"spirit_stones": FORM_FLAT,
	"free_rerolls": FORM_FLAT,
	"bonus_pierce": FORM_FLAT,
	"luck": FORM_FLAT,
}

## 文案中允许出现、但不被 apply 解释的数字（键为条目 id；百分比记整数值，平值记数值）
const ORPHAN_ALLOW := {
	"dodge_up": [60],        # 上限60%
	"lifesteal_up": [1, 3],  # 吸取1点生命（每秒最多3次）
	"tisi_kuilei": [50],     # 免死并恢复50%生命
	"huichun_hulu": [15],    # 兜底：波末回血由 wave_heal_pct 机制字段解释
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
		pcts.append(m.get_string().trim_suffix("%").replace("+", "").to_int())
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
		if d.has("power") and "%" in desc:
			var want := int(round(float(d["power"]) * 100.0))
			var toks := _extract_tokens(desc)
			if not (want in toks.pct):
				probs.append("power=%s 与文案百分比不一致（期望 %d%%）" % [d["power"], want])
		if d.has("duration") and "秒" in desc:
			var re := RegEx.new()
			re.compile("(\\d+(?:\\.\\d+)?)\\s*秒")
			for m in re.search_all(desc):
				if absf(float(m.get_string(1)) - float(d["duration"])) > 0.001:
					probs.append("文案「%s秒」与 duration=%s 不一致" % [m.get_string(1), d["duration"]])
		_c.check(probs.is_empty(), "SkillData/%s 文案与数值同源（问题: %s）" % [sid, "；".join(PackedStringArray(probs))])
