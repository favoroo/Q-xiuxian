class_name BonusRows
extends RefCounted

## 加成行渲染器（2026-10-11 土豆兄弟式信息呈现改版）：
## 把 apply 字典翻成「属性名白·左对齐 + 幅度彩色·右对齐」的逐条短行 ——
## 正面增益绿（GOOD）、负面代偿红（BAD）；乘算字段（攻击间隔/商店物价）数值越小越好，
## 按语义判向而非符号。数字一律走 StatInfoData.field_name + format_amount ——
## 与生效幅度同源的唯一出口，卡面上不再手抄第二遍数字（desc 只写机制说明）。
## 消费方：商店货架卡（ShopOfferCardFactory）、悟道卡（LevelUpDialog）、开局选武器
## （StartWeaponSelect）、图鉴与详情卡（ManualDialog / StatsTipFactory / ShopInventoryRow）。

## 语义判色：这两类乘算字段 v < 1 才是增益（攻击间隔缩短 / 商店物价降低），
## 其余沿用「正=增益、负=代偿、零=纸白」的通用口径。
static func stat_color(key: String, v: float) -> Color:
	if absf(v) < 0.0001:
		return GameStyle.PAPER
	var good := v > 0.0
	match key:
		"attack_speed_mult_mul", "shop_price_mul":
			good = v < 1.0
	return GameStyle.GOOD_DK if good else GameStyle.BAD

## apply 字典 → [名字, 幅度文本, 颜色] 行数组，DetailTip.rows 可直接拼用
static func apply_rows(apply: Dictionary) -> Array:
	var rows: Array = []
	for key in apply.keys():
		var k := String(key)
		var v := float(apply[key])
		rows.append([StatInfoData.field_name(k), StatInfoData.format_amount(k, v), stat_color(k, v)])
	return rows

## 数值文本：整值不带小数（30.0 → "30"、7.5 → "7.5"），武器伤害行用
static func fmt_num(v: float) -> String:
	if absf(v - roundf(v)) < 0.05:
		return "%d" % int(roundf(v))
	return "%.1f" % v

## 单行：名字白左对齐 + 数值彩色右对齐（钉行宽，窄卡上两列齐整不飘）
static func make_row(name_txt: String, val_txt: String, val_col: Color, font_size: int, row_w: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 4)
	row.custom_minimum_size = Vector2(row_w, 0)

	var l_name := Label.new()
	l_name.text = name_txt
	l_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameStyle.label(l_name, font_size, GameStyle.PAPER)
	row.add_child(l_name)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	var l_val := Label.new()
	l_val.text = val_txt
	l_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l_val.mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameStyle.label(l_val, font_size, val_col)
	row.add_child(l_val)
	return row

## 行块：现成 [名字, 幅度, 颜色] 行数组 → 逐条短行（卡面用，行距紧凑）
static func build_rows_block(rows: Array, font_size: int, row_w: float) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "BonusRowsBlock"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	for r in rows:
		box.add_child(make_row(String(r[0]), String(r[1]), r[2], font_size, row_w))
	return box

## 便捷：apply 字典直接成块
static func build_apply_block(apply: Dictionary, font_size: int, row_w: float) -> VBoxContainer:
	return build_rows_block(apply_rows(apply), font_size, row_w)
