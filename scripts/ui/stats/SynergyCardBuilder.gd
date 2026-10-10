class_name SynergyCardBuilder
extends RefCounted

## 流派羁绊阶梯卡片：仿《土豆兄弟》样式，直接展示 (2/6) 进度与各级加成激活情况。
## 从 PlayerStatsDialog 拆出：卡片点按回调经 dialog 门面（_open_synergy_tip）。

static func create_card(dialog: PlayerStatsDialog, tag: String) -> Control:
	var info: Dictionary = WeaponData.SYNERGIES.get(tag, {})
	var data: Dictionary = GameManager.active_synergies.get(tag, {"count": 0, "level": 0})
	var n: int = int(data.get("count", 0))
	var lv: int = int(data.get("level", 0))
	var raw_th: Array = info.get("thresholds", [2, 4, 6])
	var shift: int = 0
	if tag == "spirit":
		shift = GameManager.spirit_threshold_adj
	elif tag == "contraption":
		shift = GameManager.contraption_threshold_adj
	var max_th: int = maxi(1, int(raw_th[raw_th.size() - 1]) - shift)
	var is_elem: bool = tag in WeaponData.ELEMENTS

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(168, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var border_col: Color = (GameStyle.JADE if is_elem else GameStyle.GOLD) if lv > 0 else GameStyle.LINE
	var bg_col: Color = GameStyle.NAVY2 if lv > 0 else Color(GameStyle.INK.r, GameStyle.INK.g, GameStyle.INK.b, 0.78)
	var sb_flat := GameStyle.outlined_panel(bg_col, border_col, 2 if lv > 0 else 1, 0.0)
	sb_flat.content_margin_left = 8.0
	sb_flat.content_margin_top = 5.0
	sb_flat.content_margin_right = 8.0
	sb_flat.content_margin_bottom = 5.0
	var sb_on := GameStyle.outlined_panel(bg_col.lightened(0.08), GameStyle.JADE, 2, 0.0)
	sb_on.content_margin_left = 8.0
	sb_on.content_margin_top = 5.0
	sb_on.content_margin_right = 8.0
	sb_on.content_margin_bottom = 5.0
	card.add_theme_stylebox_override("panel", sb_flat)
	card.set_meta("sb_flat", sb_flat)
	card.set_meta("sb_on", sb_on)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vbox)

	# 顶部标题行：如「剑系 (2/6)」或「离火 (3/6)」
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(head)

	var kind_lbl := Label.new()
	kind_lbl.text = "元素" if is_elem else "类型"
	# 纸灰激活卡上亮蓝字会洗白，走主蓝；未激活暗卡上主蓝依旧可读
	GameStyle.label(kind_lbl, 10, GameStyle.JADE if is_elem else GameStyle.GOLD)
	head.add_child(kind_lbl)

	var title_lbl := Label.new()
	title_lbl.text = "%s (%d/%d)" % [info.get("name", tag), n, max_th]
	# 黑底上的次级亮灰做未激活态标题字
	var title_col: Color = (GameStyle.JADE if is_elem else GameStyle.PAPER) if lv > 0 else GameStyle.PAPER_DIM
	GameStyle.label(title_lbl, 13, title_col)
	head.add_child(title_lbl)

	# 展开 3 档阶梯加成（参照土豆兄弟：(2) +15% 范围，达成的高亮，未达成的置灰）
	var tier_lines: Array = SynergyUI.TIER_LINES.get(tag, [])
	for idx in range(raw_th.size()):
		var th_need: int = maxi(1, int(raw_th[idx]) - shift)
		var tier_txt: String = String(tier_lines[idx]) if idx < tier_lines.size() else String(info.get("desc", ""))
		var reached: bool = n >= th_need
		var is_current_tier: bool = (lv == idx + 1)
		var line_lbl := Label.new()
		var prefix: String = "★" if is_current_tier else ("·" if not reached else "+")
		line_lbl.text = "%s(%d) %s" % [prefix, th_need, tier_txt]
		# 当前档增益绿；激活卡（纸灰面）灰墨分档，未激活暗卡统一暗底亮字
		var line_col: Color = GameStyle.GOOD if is_current_tier \
				else ((GameStyle.PAPER_DIM if reached else GameStyle.GREY) if lv > 0 else GameStyle.PAPER_DIM)
		GameStyle.label(line_lbl, 11, line_col)
		vbox.add_child(line_lbl)

	GameStyle.tap(card, func() -> void: dialog._open_synergy_tip(tag, card))
	return card
