class_name SynergyUI
extends RefCounted

## 流派羁绊 UI 工厂：集中承载流派徽记（Badge/Chip）与详情卡（DetailTip）的构建逻辑
## 消除 PlayerStatsDialog、WaveShop、GameHUD 三处完全同构的 ~40 行组装代码。
## 门槛读数唯一真话在 progress()/badge()：徽记、详情卡、属性面板、货架卡都从这里取，
## 谁都不许再自己拿 WeaponData.SYNERGIES.thresholds 比大小（角色门槛下移会漏减）。

## 各流派每一档的阶梯文案（与 WeaponData.SYNERGIES 数值严格同源）
const TIER_LINES: Dictionary = {
	"sword": ["攻击范围 +15%", "攻击范围 +30%", "攻击范围 +50%"],
	"talisman": ["弹丸穿透 +1", "弹丸穿透 +2", "弹丸穿透 +3"],
	"thunder": ["攻击间隔 -8%", "攻击间隔 -15%", "攻击间隔 -25%"],
	"spirit": ["生命+15 · 灵宝伤+10%", "生命+30 · 灵宝伤+20%", "生命+50 · 灵宝伤+25%"],
	"wide": ["武器伤害 +10%", "武器伤害 +20%", "武器伤害 +30%"],
	"contraption": ["机关伤害 +15%", "机关伤害 +30%", "机关伤害 +50%"],
	"metal": ["暴击率+6% · 暴伤+20%", "暴击率+12% · 暴伤+40%", "暴击率+20% · 暴伤+75%"],
	"wood": ["回复+1.0/秒 · 吸血+2%", "回复+2.0/秒 · 吸血+4%", "回复+3.5/秒 · 吸血+7%"],
	"water": ["攻击间隔-6% · 移速+8%", "攻击间隔-12% · 移速+16%", "攻击间隔-20% · 移速+25%"],
	"fire": ["法伤+8% · 灼烧+30%", "法伤+16% · 灼烧+60%", "法伤+26% · 灼烧+100%"],
	"earth": ["护甲+3 · 击退+25%", "护甲+6 · 击退+50%", "护甲+10 · 击退+80%"],
}

# ---------------- 门槛与进度读数（唯一取数口） ----------------

## 角色对某流派门槛的下移量：只有召唤/机关两条道统会改，其余流派恒为 0
static func shift_for(tag: String) -> int:
	if tag == "spirit":
		return GameManager.spirit_threshold_adj
	if tag == "contraption":
		return GameManager.contraption_threshold_adj
	return 0

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
## extra_actions：追加到底部的操作按钮（DetailTip actions 口径），如商店的「查看该流派法器」
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
	var tier_lines: Array = TIER_LINES.get(tag, [])
	for idx in range(ths.size()):
		var th_need: int = int(ths[idx])
		var tier_txt: String = String(tier_lines[idx]) if idx < tier_lines.size() else ""
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
			String(info.get("desc", "")),
		]

	var body_txt := custom_body if not custom_body.is_empty() else "羁绊：持有越多同类武器，加成越强。"
	var foot_txt := custom_foot if not custom_foot.is_empty() else "在波间商店挑选同标签武器可继续提升阶位。"

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
