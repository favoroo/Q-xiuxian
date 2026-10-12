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
		# 2026-10-11 寻宝流：三项都是「几口 / 几点 / 几下」的平值，卡面数字由 BonusRows 从 apply 生成
		"chest_count": FORM_FLAT,
		"chest_quality": FORM_FLAT,
		"chest_break": FORM_FLAT,
		# 2026-10-12 灵兽系统加点与法宝属性
		"pet_damage_mult": FORM_PCT,
		"pet_effect_mult": FORM_PCT,
		"pet_cooldown_mult_mul": FORM_MUL,
		"pet_slots": FORM_FLAT,
	}

## 文案中允许出现、但不被 apply 解释的数字（键为条目 id；百分比记整数值，平值记数值）
const ORPHAN_ALLOW := {
	"dodge_up": [60],        # 上限60%
	"crit_up": [75],         # 上限75%
	"lifesteal_up": [1, 3],  # 吸取1点生命（每秒最多3次）
	"tisi_kuilei": [50],     # 免死并恢复50%生命
	"huichun_hulu": [15],    # 兜底：波末回血由 wave_heal_pct 机制字段解释
	# 2026-10-12 转化核心件：机制数字由各自额外字段承载（apply 留空），在此登记口径
	"jifeng_ren": [10, 4],         # 移速每超基础10% → 全伤害+4%（dmg_per_move_speed 0.04）
	"huanying_ling": [10, 5],      # 每10%闪避 → +5%暴击率（crit_per_dodge 0.05）
	"shanyue_jia": [1],            # 每点护甲+1.5%（dmg_per_armor 0.015；pct 扫描 "1.5%" 截整为 1）
	"xuepan_guyu": [50, 1],        # 每50点最大生命+1%（dmg_per_max_hp 0.01）
	"jubao_pen": [100, 3, 30],     # 每100灵石+3%，至多+30%（dmg_per_100_stones 0.03 / stone_dmg_cap 0.30）
	"ranxue_fu": [10, 2],          # 每损失10%生命+2.5%（dmg_per_missing_hp 0.025；扫描截整为 2）
		"budong_yin": [1, 30],         # 站定1秒+30%（still_seconds 1.0 / still_damage 0.30）
		"zhekou_yufu": [8],            # 商店全场 8 折（shop_price_mul 0.92 → 折扣以「折」表述）
		# 2026-10-12 深度联动与站定流法宝（14 件）
		"dazuo_putuan": [2],
		"ruding_xiang": [25, 3],
		"xuanwu_fashan": [60, 80],
		"panshi_yin": [1, 45],
		"sanmei_guizhen": [4, 1, 15],
		"lingsui_danqi": [3, 25, 15],
		"liuyun_qianyin": [50, 3],
		"jinmang_souhun": [30, 1],
		"tiangong_fatiao": [20, 30],
		"qianfu_lianhuan": [1],
		"kaishan_jianyi": [25, 1, 2],
		"ningshen_fu": [10],
		"tupo_guyu": [3, 0.5, 1],
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
		var toks := _extract_tokens(desc)
		if d.has("power") and "%" in desc:
			var want := int(round(float(d["power"]) * 100.0))
			if not (want in toks.pct):
				probs.append("power=%s 与文案百分比不一致（期望 %d%%）" % [d["power"], want])
		# 附加效果的数值也要在文案里对得上账（2026-10-11 技能改版新增字段）
		for extra_key in ["dodge_add", "pet_heal_pct"]:
			if d.has(extra_key) and float(d[extra_key]) > 0.0 and "%" in desc:
				var want_extra := int(round(float(d[extra_key]) * 100.0))
				if not (want_extra in toks.pct):
					probs.append("%s=%s 与文案百分比不一致（期望 %d%%）" % [extra_key, d[extra_key], want_extra])
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
