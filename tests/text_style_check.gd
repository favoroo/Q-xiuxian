extends Node

## 文本强调色与标色表一致性判据：headless 运行，退出码 0 且打印 ALL PASS 即通过。
## 运行: $G --headless --path . res://tests/TextStyleCheck.tscn
##
## 为什么立这条（2026-10-23 标色重做）：
##  ① 防死规则：TextStyleData.RULES 里的每一条短语都必须在当前文案语料库里原样命中；
##     谁改了文案导致规则脱钩，这里立即报错，杜绝「规则写了但实际没生效」的静默腐烂。
##  ② 字符无损性：apply 标色后 strip 掉 BBCode 必须与原文逐字完全一致，绝不允许误删改字。
##  ③ 标签闭合：[bgcolor]/[color]/[b] 必须严格配对闭合，不许漏标签。
##  ④ 颜色收口：只允许三种主题色块（GOOD/BAD/JADE）与墨黑文字，杜绝散落私有色。
##  ⑤ 语义方向正确：攻击间隔/冷却等负值必须判绿（GAIN），不许机械按符号判红。

var _c := TestCheck.new()

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var corpus := _collect_corpus()
	_c.check(corpus.size() >= 100, "文案语料库收集完备（实得 %d 句，少于 100 说明有漏接）" % corpus.size())

	_test_no_dead_rules(corpus)
	_test_markup_lossless(corpus)
	_test_tag_closure(corpus)
	_test_color_whitelist(corpus)
	_test_semantic_direction()

	var ok := _c.report("TEXT_STYLE_RESULT")
	get_tree().quit(0 if ok else 1)

## 收集全量教程类文案原文字符串
func _collect_corpus() -> Array[String]:
	var out: Array[String] = []

	# 1. 新手指南
	for p in TutorialDialog.PAGES:
		out.append(String(p.get("body", "")))

	# 2. 进阶心法
	for sec in ManualData.ADVANCED_SECTIONS:
		out.append(String(sec.get("body", "")))

	# 3. 流派攻略 tips
	for guide in ManualData.BUILD_GUIDES:
		out.append(String(guide.get("tips", "")))

	# 4. 手册静态卡
	for k in ManualData.RULE_CARDS.keys():
		out.append(String(ManualData.RULE_CARDS[k].get("body", "")))
	# 武器分页的规则卡真实格式化文本
	out.append(ManualData.WEAPON_RULE_BODY % [
		WeaponData.MAX_SLOTS, WeaponData.MAX_STASH_SLOTS,
		String.num(WeaponData.STAR_DAMAGE_MULT, 1), String.num(WeaponData.STAR_COOLDOWN_MULT, 2),
		WeaponData.MAX_STAR])

	# 5. 属性规则（全部 25 条）
	for id in StatInfoData.ids():
		for r in StatInfoData.rules(String(id)):
			out.append(String(r))

	# 6. 技能说明
	for sid in SkillData.DEFS.keys():
		var desc: String = String(SkillData.DEFS[sid].get("desc", ""))
		if not desc.is_empty():
			out.append(desc)

	# 7. 道具说明（非空）
	for iid in ItemData.DEFS.keys():
		var desc: String = String(ItemData.DEFS[iid].get("desc", ""))
		if not desc.is_empty():
			out.append(desc)

	# 8. 灵兽说明
	for pid in PetData.all_ids():
		var desc: String = String(PetData.get_def(String(pid)).get("desc", ""))
		if not desc.is_empty():
			out.append(desc)

	return out

## ① 显式表里的短语必须至少命中一次
func _test_no_dead_rules(corpus: Array[String]) -> void:
	var total_text := "\n".join(corpus)
	var dead: Array[String] = []
	for rule in TextStyleData.RULES:
		var t := String(rule["t"])
		if not total_text.contains(t):
			dead.append(t)
	_c.check(dead.is_empty(),
		"TextStyleData.RULES 无死规则（全 %d 条均在文案里真实命中；未命中 %d 条: %s）" % [
			TextStyleData.RULES.size(), dead.size(), str(dead.slice(0, 5))])

## ② 标色处理是无损的：strip 后必须与原文逐字完全一致
func _test_markup_lossless(corpus: Array[String]) -> void:
	var mismatch := 0
	for raw in corpus:
		var colored := GameStyle.colorize_terms(raw)
		var stripped := GameStyle.strip_markup(colored)
		if stripped != raw:
			mismatch += 1
	_c.check(mismatch == 0, "全部文案标色前后文字无损（实测 %d 句，不匹配 %d 句）" % [corpus.size(), mismatch])

## ③ 标签闭合检查
func _test_tag_closure(corpus: Array[String]) -> void:
	## ③ 标签闭合检查 + 杜绝背景色块
	var broken := 0
	var has_bgcolor := 0
	for raw in corpus:
		var colored := GameStyle.colorize_terms(raw)
		if colored.contains("[bgcolor=") or colored.contains("[/bgcolor]"):
			has_bgcolor += 1
		var col_opens: int = colored.count("[color=")
		var col_closes: int = colored.count("[/color]")
		var b_opens: int = colored.count("[b]")
		var b_closes: int = colored.count("[/b]")
		if col_opens != col_closes or b_opens != b_closes:
			broken += 1
	_c.check(has_bgcolor == 0, "杜绝 [bgcolor] 背景色块卡片，全部走纯文字着色（违规句数: %d）" % has_bgcolor)
	_c.check(broken == 0, "全部文案 BBCode 标签严格配对闭合（未闭合句数: %d）" % broken)

## ④ 颜色白名单：只允许三色高对比纯文字（深绿/深红/深金）+ 墨黑加粗
func _test_color_whitelist(corpus: Array[String]) -> void:
	var allowed_col := {
		GameStyle.GOOD_DK.to_html(false).to_lower(): true,
		GameStyle.BAD_DK.to_html(false).to_lower(): true,
		GameStyle.JADE_DK.to_html(false).to_lower(): true,
		GameStyle.PAPER.to_html(false).to_lower(): true,
	}
	var re_col := RegEx.new()
	re_col.compile("\\[color=#([0-9a-fA-F]+)\\]")
	var illegal: Array[String] = []
	for raw in corpus:
		var colored := GameStyle.colorize_terms(raw)
		for m in re_col.search_all(colored):
			var c := m.get_string(1).to_lower()
			if not allowed_col.has(c) and not (c in illegal):
				illegal.append(c)
	_c.check(illegal.is_empty(), "文本颜色全在纸底高对比白名单内（非法颜色: %s）" % str(illegal))

## ⑤ 语义反例测试（防「攻击间隔 -30%」误标红回归）
func _test_semantic_direction() -> void:
	var good_hex: String = GameStyle.GOOD_DK.to_html(false).to_lower()
	var bad_hex: String = GameStyle.BAD_DK.to_html(false).to_lower()

	# 攻击间隔缩短是收益 → 必须绿
	var s1 := GameStyle.colorize_terms("攻击间隔 -30%")
	_c.check(s1.to_lower().contains("[color=#" + good_hex + "]"),
		"「攻击间隔 -30%」正确标为 GAIN 绿字")

	# 攻速略降是代价 → 必须红
	var s2 := GameStyle.colorize_terms("武器伤害大幅提升，攻速略降")
	_c.check(s2.to_lower().contains("[color=#" + good_hex + "]")
			and s2.to_lower().contains("[color=#" + bad_hex + "]"),
		"「武器伤害大幅提升，攻速略降」双色字并存（增益绿 + 代价红）")
