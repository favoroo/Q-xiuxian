class_name SynergyUI
extends RefCounted

## 流派羁绊 UI 工厂：集中承载流派徽记（Badge/Chip）与详情卡（DetailTip）的构建逻辑
## 消除 PlayerStatsDialog、WaveShop、GameHUD 三处完全同构的 ~40 行组装代码。

## 各流派每一档的阶梯文案（与 WeaponData.SYNERGIES 数值严格同源）
const TIER_LINES: Dictionary = {
	"sword": ["攻击范围 +15%", "攻击范围 +30%", "攻击范围 +50%"],
	"talisman": ["弹丸穿透 +1", "弹丸穿透 +2", "弹丸穿透 +3"],
	"thunder": ["攻击间隔 -8%", "攻击间隔 -15%", "攻击间隔 -25%"],
	"spirit": ["最大生命 +15", "最大生命 +30", "最大生命 +50"],
	"wide": ["武器伤害 +10%", "武器伤害 +20%", "武器伤害 +30%"],
	"metal": ["暴击率+6% · 暴伤+20%", "暴击率+12% · 暴伤+40%", "暴击率+20% · 暴伤+75%"],
	"wood": ["回复+1.0/秒 · 吸血+2%", "回复+2.0/秒 · 吸血+4%", "回复+3.5/秒 · 吸血+7%"],
	"water": ["攻击间隔-6% · 移速+8%", "攻击间隔-12% · 移速+16%", "攻击间隔-20% · 移速+25%"],
	"fire": ["法伤+8% · 灼烧+30%", "法伤+16% · 灼烧+60%", "法伤+26% · 灼烧+100%"],
	"earth": ["护甲+3 · 击退+25%", "护甲+6 · 击退+50%", "护甲+10 · 击退+80%"],
}

## 组装流派羁绊详情数据字典（供 DetailTip.show_over 使用）
static func build_tip_data(tag: String, custom_body: String = "", custom_foot: String = "", custom_notes: Array = []) -> Dictionary:
	var info: Dictionary = WeaponData.SYNERGIES.get(tag, {})
	if info.is_empty():
		return {}
	var data: Dictionary = GameManager.active_synergies.get(tag, {"count": 0, "level": 0})
	var n: int = int(data.get("count", 0))
	var lv: int = int(data.get("level", 0))
	var raw_th: Array = info.get("thresholds", [2, 4, 6])
	var shift: int = GameManager.spirit_threshold_adj if tag == "spirit" else 0
	var max_th: int = maxi(1, int(raw_th[raw_th.size() - 1]) - shift)
	var first_th: int = maxi(1, int(raw_th[0]) - shift)

	var rows: Array = [
		["当前装备", "%d / %d 件" % [n, max_th], GameStyle.JADE if lv > 0 else GameStyle.PAPER],
			["羁绊状态", "已达成第 %d 档" % lv if lv > 0 else "未激活 (差 %d 件)" % maxi(1, first_th - n), GameStyle.GOOD if lv > 0 else GameStyle.GREY],
	]
	var tier_lines: Array = TIER_LINES.get(tag, [])
	for idx in range(raw_th.size()):
		var th_need: int = maxi(1, int(raw_th[idx]) - shift)
		var tier_txt: String = String(tier_lines[idx]) if idx < tier_lines.size() else ""
		var reached: bool = n >= th_need
		rows.append([
			"(%d/%d) 阶梯" % [th_need, max_th],
			tier_txt,
			GameStyle.GOOD if lv == idx + 1 else (GameStyle.PAPER_DIM if reached else GameStyle.GREY)
		])

	var notes: Array[String] = []
	if not custom_notes.is_empty():
		for item in custom_notes:
			notes.append(String(item))
	else:
			notes = [
				"同标签武器上阵达到 %d / %d / %d 件时依次激活阶梯加成。" % [
				maxi(1, int(raw_th[0]) - shift),
				maxi(1, int(raw_th[1]) - shift),
				max_th
			],
			String(info.get("desc", "")),
		]

	var body_txt := custom_body if not custom_body.is_empty() else "羁绊：持有越多同类武器，加成越强。"
	var foot_txt := custom_foot if not custom_foot.is_empty() else "在波间商店挑选同标签武器可继续提升阶位。"

	return {
		"title": "%s (%d/%d)" % [info.get("name", tag), n, max_th],
		"chip": "元素共鸣" if tag in WeaponData.ELEMENTS else "类型羁绊",
		"chip_color": GameStyle.JADE if tag in WeaponData.ELEMENTS else GameStyle.GOLD,
		"rows": rows,
		"body": body_txt,
		"notes": notes,
		"foot": foot_txt,
	}

## 打开流派羁绊详情弹窗并返回实例
static func open_tip(host: Control, anchor: Control, tag: String, custom_body: String = "", custom_foot: String = "", custom_notes: Array = []) -> Control:
	var data := build_tip_data(tag, custom_body, custom_foot, custom_notes)
	if data.is_empty():
		return null
	return DetailTip.show_over(host, anchor, data)

## 创建一个标准的流派羁绊徽记 Label
static func create_chip(tag: String, font_size: int = 12, on_tap: Callable = Callable()) -> Label:
	var info: Dictionary = WeaponData.SYNERGIES.get(tag, {})
	var data: Dictionary = GameManager.active_synergies.get(tag, {"count": 0, "level": 0})
	var n: int = int(data.get("count", 0))
	var lv: int = int(data.get("level", 0))
	var raw_th: Array = info.get("thresholds", [2, 4, 6])
	var shift: int = GameManager.spirit_threshold_adj if tag == "spirit" else 0
	var max_th: int = maxi(1, int(raw_th[raw_th.size() - 1]) - shift)

	var chip := Label.new()
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	chip.add_to_group(DawnJoystick.UI_PRESS_HOLD_GROUP)
	chip.text = " %s (%d/%d) " % [info.get("name", tag), n, max_th]

	if lv > 0:
		var chip_color: Color = GameStyle.JADE if tag in WeaponData.ELEMENTS else GameStyle.GOLD
		chip.add_theme_stylebox_override("normal", GameStyle.chip(chip_color))
		GameStyle.label(chip, font_size, GameStyle.INK_TEXT)
	else:
		chip.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.NAVY2))
		GameStyle.label(chip, font_size, GameStyle.PAPER_DIM)

	if on_tap.is_valid():
		chip.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
				on_tap.call()
		)
	return chip
