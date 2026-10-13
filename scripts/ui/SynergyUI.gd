class_name SynergyUI
extends RefCounted

## 流派羁绊 UI 工厂：集中承载流派徽记（Badge/Chip）与详情卡（DetailTip）的构建逻辑
## 消除 PlayerStatsDialog、WaveShop、GameHUD 三处完全同构的 ~40 行组装代码。
## 门槛读数唯一真话在 progress()/badge()：徽记、详情卡、属性面板、货架卡都从这里取，
## 谁都不许再自己拿 WeaponData.SYNERGIES.thresholds 比大小（角色门槛下移会漏减）。
##
## 文案口径（2026-10-11）：**这里不再存任何手写字符串**。
## 阶梯行 tier_line() 与图鉴长句 synergy_desc() 都由 WeaponData.SYNERGIES[tag].effects 生成，
## 与 SynergySystem.apply_counts 结算读的是同一张表、同一批数字。
## 以前 TIER_LINES 手抄一遍 desc 手抄一遍、SynergySystem 再硬编码一份 side list，
## 结果火系局内写「法伤」（属性表里根本没这条）、木系与召唤当天补的伤害乘区漏在局内文案外。

const FORM_PCT := "pct"          ## 存分数：0.08 → +8%
const FORM_PCT_DOWN := "pct_down" ## 存系数：0.92 → -8%（攻击间隔这类越小越好的档位）
const FORM_FLAT := "flat"        ## 平值：3 → +3
const FORM_FLAT1 := "flat1"      ## 一位小数的平值：1.0 → +1.0（每秒回复）

## 某流派的效果声明表（唯一取数口；SynergySystem 结算与本文案生成共用）
static func effects_for(tag: String) -> Array:
	var info: Dictionary = WeaponData.SYNERGIES.get(tag, {})
	return info.get("effects", [])

## 第 tier 档（1 起）某条效果的原始数值；档位越界返回 NAN（调用方跳过该条）
static func effect_value(tag: String, eff: Dictionary, tier: int) -> float:
	var info: Dictionary = WeaponData.SYNERGIES.get(tag, {})
	var vals: Array = info.get(String(eff.get("list", "values")), [])
	if tier < 1 or tier > vals.size():
		return NAN
	return float(vals[tier - 1])

## 原始数值 → 展示数值（带符号，单位已折算）
## pct_down 必须落成负数：攻击间隔 0.94 是「缩短 6%」，取绝对值就成了「间隔 +6%」，
## 玩家读到的方向正好反了（2026-10-11 生成器第一版就栽在这里，被负例判据抓出来）
static func displayed_number(raw: float, form: String) -> float:
	match form:
		FORM_PCT:
			return raw * 100.0
		FORM_PCT_DOWN:
			return (raw - 1.0) * 100.0
		_:
			return raw

## 「+8%」「-8%」「+15」「+1.0」——阶梯行里的单个读数
static func _signed(raw: float, form: String) -> String:
	var d := displayed_number(raw, form)
	var sign := "-" if d < 0.0 else "+"
	return "%s%s%s" % [sign, _magnitude(d, form), unit_for(form)]

## 展示单位：百分比档恒带 %，flat 档不带。阶梯行与说明句共用这一条规则
## （2026-10-11 生成器第一版只在说明句拼了 suffix 没拼 %，「武器伤害 +10/20/25」读着像加 25 点）
static func unit_for(form: String) -> String:
	return "%" if form == FORM_PCT or form == FORM_PCT_DOWN else ""

## 绝对值部分：整数不写小数点，flat1 恒留一位
static func _magnitude(d: float, form: String) -> String:
	var a := absf(d)
	if form == FORM_FLAT1:
		return "%.1f" % a
	if absf(a - round(a)) <= 0.0001:
		return str(int(round(a)))
	return "%g" % a

## 某流派第 tier 档（1 起）的阶梯文案：「武器伤害+8% · 灼烧+30%」
## 分隔符与紧凑写法沿用原 TIER_LINES 口径，长度由 UnitRunner 的量尺判据兜（详情卡定宽 306）
static func tier_line(tag: String, tier: int) -> String:
	var parts: Array[String] = []
	for eff in effects_for(tag):
		var raw := effect_value(tag, eff, tier)
		if is_nan(raw):
			continue
		parts.append("%s%s%s" % [String(eff.get("label", "")),
				_signed(raw, String(eff.get("form", FORM_FLAT))), String(eff.get("suffix", ""))])
	return " · ".join(parts)

## 图鉴与详情卡通用长句：「武器伤害 +8/16/26%，灼烧 +30/60/100%」
## 符号只写在首档前，与改前手抄的 desc 写法一致；数值仍逐档取自 effects，不另写一遍
static func synergy_desc(tag: String) -> String:
	var info: Dictionary = WeaponData.SYNERGIES.get(tag, {})
	var tiers: int = (info.get("thresholds", []) as Array).size()
	var parts: Array[String] = []
	for eff in effects_for(tag):
		var form := String(eff.get("form", FORM_FLAT))
		var nums: Array[String] = []
		var sign := "+"
		for t in range(1, tiers + 1):
			var raw := effect_value(tag, eff, t)
			if is_nan(raw):
				continue
			var d := displayed_number(raw, form)
			if nums.is_empty():
				sign = "-" if d < 0.0 else "+"
			nums.append(_magnitude(d, form))
		if nums.is_empty():
			continue
		parts.append("%s %s%s%s%s" % [String(eff.get("label", "")), sign,
				"/".join(nums), unit_for(form), String(eff.get("suffix", ""))])
	return "，".join(parts)

# ---------------- 门槛与进度读数（唯一取数口） ----------------

## 角色对某流派门槛的下移量：只有召唤/机关两条道统会改，其余流派恒为 0
## 折算与结算同一真话（SynergySystem.shift_for），局内门槛显示与角色门槛下移不会各算一套
static func shift_for(tag: String) -> int:
	return SynergySystem.shift_for(tag)

## 某流派的下移后三档门槛（与 GameBalance.synergy_level 同一条折算）
static func thresholds_for(tag: String) -> Array:
	var info: Dictionary = WeaponData.SYNERGIES.get(tag, {})
	return GameBalance.synergy_thresholds(info.get("thresholds", []), shift_for(tag))

## 持有 count 件时的进度读数：{"count","level","ths","max_th","next_th"(0=已满档),"is_max","name"}
## count 缺省读本局结算表 active_synergies；货架卡传「买下前的件数」自己算，口径不变。
static func progress(tag: String, count: int = -1) -> Dictionary:
	var info: Dictionary = WeaponData.SYNERGIES.get(tag, {})
	var ths: Array = thresholds_for(tag)
	var data: Dictionary = GameManager.active_synergies.get(tag, {"count": 0, "level": 0})
	var n: int = int(data.get("count", 0)) if count < 0 else count
	var max_th: int = int(ths[ths.size() - 1]) if not ths.is_empty() else 1
	var next_th: int = GameBalance.synergy_next_threshold(n, info.get("thresholds", []), shift_for(tag))
	return {
		"count": n,
		"level": int(data.get("level", 0)),
		"ths": ths,
		"max_th": max_th,
		"next_th": next_th,
		"is_max": next_th == 0,
		"name": String(info.get("name", tag)),
	}

## 徽记/标题读数：「召唤 (3/5)」= 还差 2 件满档；已满档印「召唤 (6/MAX)」。
## 2026-10-11 修：门槛 -1 的角色满档只要 5 件，第 6 件照拿 ⇒ 原样拼成「6/5」，
## 看着像「超出上限」的数值 Bug。满档就是满档，不拿件数去比一个已经作废的分母。
static func progress_text(tag: String, count: int = -1) -> String:
	var p := progress(tag, count)
	var denom: String = "MAX" if bool(p["is_max"]) else str(int(p["max_th"]))
	return "%s (%d/%s)" % [String(p["name"]), int(p["count"]), denom]

## 货架卡色签读数：「召唤 4/5」= 下一档要 5 件，「召唤 5/MAX」= 已满档。
## hot = 买下这一件正好踩到下一档（临门一档亮绿边）。
## 2026-10-11 修：原先直接比原表 2/4/6，漏减角色门槛下移 ⇒ 驯兽师 5 件已满档
## 还被提示「5/6 再买一件」，绿边也错一档。
static func badge(tag: String, count: int) -> Dictionary:
	var p := progress(tag, count)
	var denom: String = "MAX" if bool(p["is_max"]) else str(int(p["next_th"]))
	return {
		"text": "%s %d/%s" % [String(p["name"]), int(p["count"]), denom],
		"hot": int(p["next_th"]) > 0 and int(p["count"]) + 1 == int(p["next_th"]),
	}

## 组装流派羁绊详情数据字典（供 DetailTip.show_over 使用）
## extra_actions：追加到底部的操作按钮（DetailTip actions 口径），如商店的「查看该流派武器」
static func build_tip_data(tag: String, custom_body: String = "", custom_foot: String = "", custom_notes: Array = [], extra_actions: Array = []) -> Dictionary:
	var info: Dictionary = WeaponData.SYNERGIES.get(tag, {})
	if info.is_empty():
		return {}
	var p := progress(tag)
	var n: int = int(p["count"])
	var lv: int = int(p["level"])
	var ths: Array = p["ths"]
	var max_th: int = int(p["max_th"])
	var owned_txt: String = ("%d 件 · 已满档" % n) if bool(p["is_max"]) else ("%d / %d 件" % [n, max_th])
	var rows: Array = [
		["当前装备", owned_txt, GameStyle.JADE if lv > 0 else GameStyle.PAPER],
		["羁绊状态", "已达成第 %d 档" % lv if lv > 0 else "未激活 (差 %d 件)" % maxi(1, int(ths[0]) - n),
			GameStyle.GOOD if lv > 0 else GameStyle.GREY],
	]
	for idx in range(ths.size()):
		var th_need: int = int(ths[idx])
		var tier_txt: String = tier_line(tag, idx + 1)
		var reached: bool = n >= th_need
		rows.append([
			"%d 件档" % th_need,
			tier_txt,
			GameStyle.GOOD if lv == idx + 1 else (GameStyle.PAPER_DIM if reached else GameStyle.GREY)
		])

	var notes: Array[String] = []
	if not custom_notes.is_empty():
		for item in custom_notes:
			notes.append(String(item))
	else:
		var step_txt := ""
		for idx in range(ths.size()):
			step_txt += (" / " if idx > 0 else "") + str(int(ths[idx]))
		notes = [
			"同标签武器上阵达到 %s 件时依次激活阶梯加成。" % step_txt,
			synergy_desc(tag),
		]

	var body_txt := custom_body if not custom_body.is_empty() else "羁绊：持有越多同类武器，加成越强。"
	var foot_txt := custom_foot if not custom_foot.is_empty() else "在回合间商店挑选同标签武器可继续提升阶位。"

	var payload: Dictionary = {
		"title": progress_text(tag),
		"chip": "元素共鸣" if tag in WeaponData.ELEMENTS else "类型羁绊",
		"chip_color": GameStyle.JADE if tag in WeaponData.ELEMENTS else GameStyle.GOLD,
		"rows": rows,
		"body": body_txt,
		"notes": notes,
		"foot": foot_txt,
	}
	if not extra_actions.is_empty():
		payload["actions"] = extra_actions
	return payload

## 打开流派羁绊详情弹窗并返回实例
static func open_tip(host: Control, anchor: Control, tag: String, custom_body: String = "", custom_foot: String = "", custom_notes: Array = [], extra_actions: Array = []) -> Control:
	var data := build_tip_data(tag, custom_body, custom_foot, custom_notes, extra_actions)
	if data.is_empty():
		return null
	return DetailTip.show_over(host, anchor, data)

## 创建一个标准的流派羁绊徽记 Label；on_tap 会收到徽记自身，作为详情卡的锚点
static func create_chip(tag: String, font_size: int = 12, on_tap: Callable = Callable()) -> Label:
	var p := progress(tag)
	var lv: int = int(p["level"])

	var chip := Label.new()
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	chip.add_to_group(DawnJoystick.UI_PRESS_HOLD_GROUP)
	chip.text = " %s " % progress_text(tag)

	if lv > 0:
		var chip_color: Color = GameStyle.JADE if tag in WeaponData.ELEMENTS else GameStyle.GOLD
		chip.add_theme_stylebox_override("normal", GameStyle.chip(chip_color))
		GameStyle.label(chip, font_size, GameStyle.INK_TEXT)
	else:
		chip.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.NAVY2))
		GameStyle.label(chip, font_size, GameStyle.PAPER_DIM)

	if on_tap.is_valid():
		# 锚点由工厂回送给回调，不让调用方自己捕获：GDScript lambda 在创建那一刻按值捕获局部变量
		# （`var chip; chip = create_chip(.., func(): open(tag, chip))` 里那一刻 chip 还是 null），
		# 于是徽记拿着 null 去开卡、被 DetailTip 的空锚点守卫静默吞掉 —— 点了没反应且不报错。
		# 识别器同属性面板换 GameStyle.tap：按下与抬起都在原地才算点，划动不误触。
		GameStyle.tap(chip, func() -> void: on_tap.call(chip))
	return chip
