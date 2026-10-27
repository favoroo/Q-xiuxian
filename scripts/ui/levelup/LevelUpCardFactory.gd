class_name LevelUpCardFactory
extends RefCounted

## 悟道卡工厂：从 LevelUpDialog._create_card_entry 整体迁出（2026-10-15），
## 与 ui/shop/ShopOfferCardFactory 同构 —— static func + 宿主注入（第一参 dialog）+
## 输入纯数据、输出组件引用字典，工厂不持有宿主状态。
## 拆分动机：LevelUpDialog 是并行开发冲突热区（git 共改率前五），卡装配与面板逻辑
## 混在一文件里会互相踩；落位 scripts/ui/levelup/ 子目录后各自归属。
##
## 摆位常量（CARD_PAD_X / CARD_MIN_H / BF_CELL_* 等）仍归 LevelUpDialog 单一真源，
## 工厂只读不抄；卡宽 card_w 由宿主算好经 create_card 传入。

## 飞升悟道（原超级悟道）卡底染色比例：宣纸白往逆天赤红里掺 14%。
## 下限：8% 出的 #f7e4d9 太淡，缩成五张小卡后与普通卡看不出差别；
## 上限：再深则 PAPER_DIM 次要字（注脚/受益装备标题）对比度掉到无障碍门槛 4.5 以下
## （14% 时 5.14，22% 时只剩 4.61）。纸面墨字 PAPER 全程 13 以上，不受影响。
const SUPER_BG_TINT := 0.14
## 飞升卡描边比普通卡厚一档（左/右/底各 +1）：纸面染了红，边框要够分量才压得住
const SUPER_EDGE_EXTRA := 1

## 装配一张悟道候选卡。返回组件引用字典（root/style/icon_panel_style/rarity_col/
## state_badge/title_lbl/bg_base），选中态切换由宿主 _select_card 用这些引用重写样式。
## 卡内需要调回宿主的两个交互入口：on_card_tapped / open_benefit_tip。
static func create_card(dialog: LevelUpDialog, data: Dictionary, index: int,
		card_w: float, forecast: StatForecast) -> Dictionary:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(card_w, LevelUpDialog.CARD_MIN_H)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.pivot_offset = Vector2(card_w * 0.5, LevelUpDialog.CARD_MIN_H * 0.5)

	var rarity_str: String = String(data.get("rarity", "common"))
	var rarity_col: Color = data.get("border_color", GameStyle.rarity_color(rarity_str))
	# T-5.1 稀有度卡框描边接 FX_HDR 对应档（普通白不发辉、金色档 HDR 超白起辉）：
	var edge_col: Color = GameStyle.rarity_edge_color(rarity_str) if data.has("rarity") else GameStyle.rarity_edge_color(rarity_col)
	# 飞升悟道（2026-10-26）：普通悟道卡是纯宣纸白底，飞升卡整面淡红染 —— 两屏卡面
	# 一眼分得开（只染底不改字色，纸面墨字对比度不变）。payload 无 is_super 即普通卡。
	var is_super := bool(data.get("is_super", false))
	var bg_base: Color = GameStyle.NAVY2.lerp(GameStyle.RARITY_MYTHIC, SUPER_BG_TINT) if is_super else GameStyle.NAVY2
	var style_normal := GameStyle.card(edge_col, GameStyle.SLANT_BLOCK, Vector2(4, 5))
	style_normal.bg_color = bg_base
	if is_super:
		style_normal.border_width_left += SUPER_EDGE_EXTRA
		style_normal.border_width_right += SUPER_EDGE_EXTRA
		style_normal.border_width_bottom += SUPER_EDGE_EXTRA
	style_normal.content_margin_left = LevelUpDialog.CARD_PAD_X
	style_normal.content_margin_top = 10.0
	style_normal.content_margin_right = LevelUpDialog.CARD_PAD_X
	style_normal.content_margin_bottom = 10.0
	card.add_theme_stylebox_override("panel", style_normal)

	var inner_w: float = LevelUpDialog.card_inner_w(card_w)
	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 5)

	# 1. 顶部稀有度色签 + 已修层数
	var hbox_top := _create_top_row(dialog, data, rarity_col)
	vbox.add_child(hbox_top)

	# 2. 中央图标（墨底白框；飞升卡描边换逆天赤红，普通卡仍是中性线）
	var icon_panel_style := _create_icon_box(vbox, String(data.get("icon", "")), is_super)

	# 3. 名称（纸白大字，窄卡上自己切硬换行）
	var title_lbl := Label.new()
	title_lbl.text = GameStyle.wrap_cjk(String(data["title"]), GameStyle.display_font(), 17, inner_w)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.custom_minimum_size = Vector2(inner_w, 0)
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title_lbl)
	GameStyle.label(title_lbl, 17, GameStyle.PAPER, 0, GameStyle.INK, true)

	# 4. 分隔线（稀有度色）
	var sep := HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sep_style := StyleBoxLine.new()
	sep_style.color = GameStyle.with_alpha(edge_col, 0.45)
	sep_style.thickness = 2
	sep.add_theme_stylebox_override("separator", sep_style)
	vbox.add_child(sep)

	# 5. 加成行块（2026-10-11 土豆兄弟式改版）：数值全部由 apply 经 BonusRows 直接生成——
	#    名字白·左对齐、幅度彩色·右对齐、正增益绿/负代偿红，与生效幅度天然同源。
	#    表里的 desc 只写 apply 之外的机制说明（纯数值项为空串），非空才渲染、灰白小字。
	#    每条幅度行下面再插一行「当前 X → Y」小字，读数走 StatForecast（属性面板同一份算式）。
	vbox.add_child(_build_apply_block(data.get("apply", {}), 13, inner_w, forecast))
	var flavor := String(data.get("desc", ""))
	if not flavor.is_empty():
		var note_lbl := Label.new()
		note_lbl.text = GameStyle.wrap_cjk(flavor, GameStyle.body_font(), 12, inner_w)
		note_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		note_lbl.custom_minimum_size = Vector2(inner_w, 0)
		note_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		GameStyle.label(note_lbl, 12, GameStyle.PAPER_DIM)
		vbox.add_child(note_lbl)

	# 受益武器图标行（2026-10-10 用户指令）：这条悟道会让当前上阵的哪些武器变强，
	# 把它们的图标摆在卡片底部。判定走 GameBalance.upgrade_benefits_weapon 纯函数，
	# 与伤害结算的属性映射同源（stat_scalings / 五行 tags / 全局乘区），不写死升级 id。
	# 图标详情卡复用 StatsTipFactory.open_weapon_tip（HUD 武器栏/属性面板/金币阁同一张卡）。
	# 三条硬口径，判据 tests/BenefitIconTapCheck.tscn 逐条量：
	# ① 只读 —— 点图标不许顺手把这张卡选中（格体与卡体都是 PASS，拦住选中的是
	#    GameStyle.tap 的「一次手势只兑现最里那一层」认领，不是 STOP 拦冒泡）。
	# ② 划得起来 —— 中途划过 TAP_SLACK 就不算点，不许一划弹一张卡。
	# ③ 摆得下 —— 格子按卡内宽现算并夹在 [BF_CELL_MIN, BF_CELL_MAX]，摊不开就换行。
	var benefited: Array = []
	for w in GameManager.get_weapons_summary():
		if GameBalance.upgrade_benefits_weapon(data.get("apply", {}), String(w.get("id", ""))):
			benefited.append(w)
	if not benefited.is_empty():
		# 2026-10-21 用户指令：「这个受益装备要放在卡片底部显示」。
		# 一屏五张卡被 HBoxContainer 拉成同高，内容各自只到自身最小高 ⇒ 不加这一格弹性留白，
		# 这排图标就贴着最后一条加成行，高矮不一的卡上位置乱跳。留白本身最小高 0，
		# 不吃卡高、不影响「这一屏不许竖滑」那条尺子（BenefitIconTapCheck ⑧）。
		var spring := Control.new()
		spring.name = "BenefitSpring"
		spring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		spring.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox.add_child(spring)
		_append_benefit_row(dialog, vbox, benefited, inner_w, data)

	card.add_child(vbox)

	# 点卡片本体 = 只选中，不直接加点（防误触）；正式生效要走底部「确认选择」。
	# 认「按下与抬起都留在原地」的完整手势：卡体已从 STOP 降成 PASS（宿主 _populate_cards
	# 末尾统一 swipeable），只认松开的话，手指在卡上划一下列表就换一张选中。
	GameStyle.tap(card, func() -> void: dialog.on_card_tapped(index))

	return {
		"root": card,
		"style": style_normal,
		"icon_panel_style": icon_panel_style,
		"rarity_col": edge_col,
		"rarity_base": rarity_col,
		"rarity": rarity_str,
		"is_super": is_super,
		"bg_base": bg_base,
		"state_badge": hbox_top.get_node_or_null("StateBadge"),
		"title_lbl": title_lbl,
	}

## 行①：稀有度色签 + 已修层数徽记
static func _create_top_row(dialog: LevelUpDialog, data: Dictionary, rarity_col: Color) -> HBoxContainer:
	var hbox_top := HBoxContainer.new()
	hbox_top.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var rarity_lbl := Label.new()
	rarity_lbl.text = " " + data.get("rarity_label", "普通") + " "
	GameStyle.label(rarity_lbl, 11, GameStyle.PAPER)
	var band_text_col: Color = GameStyle.on_face_text(rarity_col)
	rarity_lbl.add_theme_color_override("font_color", band_text_col)
	var pill_style := GameStyle.block(rarity_col, GameStyle.SLANT_BAND, Vector2(2, 2))
	pill_style.content_margin_top = 2.0
	pill_style.content_margin_bottom = 2.0
	rarity_lbl.add_theme_stylebox_override("normal", pill_style)
	hbox_top.add_child(rarity_lbl)

	# 道途签（飞升悟道专属）：标出所属道途。
	# 普通悟道 payload 没有 lane_label，这里整段不渲染，行为零变化。
	# 文案形如「剑道」/「共鸣」，一行读得出「这张卡属于哪一路」（2026-10-26 去阶段后不再带「新道/延续/大成」）。
	var lane_text := String(data.get("lane_label", ""))
	var lane_chip_text := String(data.get("lane_chip", ""))
	if not lane_text.is_empty() or not lane_chip_text.is_empty():
		var lane_lbl := Label.new()
		lane_lbl.name = "LaneBadge"
		lane_lbl.text = " %s " % ("%s·%s" % [lane_text, lane_chip_text]
			if not lane_text.is_empty() and not lane_chip_text.is_empty()
			else (lane_text if not lane_text.is_empty() else lane_chip_text))
		lane_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		lane_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.PAPER_DIM))
		hbox_top.add_child(lane_lbl)
		GameStyle.label(lane_lbl, 11, GameStyle.NAVY)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox_top.add_child(spacer)

	var state_badge := Label.new()
	state_badge.name = "StateBadge"
	var count_already: int = int(GameManager.upgrade_counts.get(data.get("id", ""), 0))
	state_badge.text = "×%d" % count_already if count_already > 0 else ""
	GameStyle.label(state_badge, 11, GameStyle.GREY)
	hbox_top.add_child(state_badge)
	return hbox_top

## 行②：中央图标盒（墨底描边框），样式返回给宿主供选中态改边框色。
## 飞升卡描边用逆天赤红（与卡框同色系），普通卡仍是中性 LINE。
static func _create_icon_box(vbox: VBoxContainer, icon_path: String, is_super: bool = false) -> StyleBoxFlat:
	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(56, 56)
	icon_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_edge: Color = GameStyle.RARITY_MYTHIC if is_super else GameStyle.LINE
	var icon_panel_style := GameStyle.outlined_panel(GameStyle.INK, icon_edge, 2, 0.0)
	icon_box.add_theme_stylebox_override("panel", icon_panel_style)

	var icon_tex := GameStyle.icon_texture_rect(icon_path, Vector2(42, 42))
	icon_box.add_child(icon_tex)
	vbox.add_child(icon_box)
	return icon_panel_style

## 加成行块 + 每行下面那条「当前 X → Y」（2026-10-12 用户指令）。幅度行仍由 BonusRows 出
## （与商店货架卡、开局选武器同一长相、同一把尺），注脚的数走 StatForecast ——
## 落地算式与聚合算式都是属性面板在用的那一份，卡面不许自己再算。
## 面板没有对应行的机制项（宝箱数量/品质、开箱省击、单系元素伤）不插注脚。
## 加了等于没加（夹到上限、满血回血）照实写，且退成 GREY，与 desc 互相印证。
static func _build_apply_block(apply: Dictionary, font_size: int, row_w: float, forecast: StatForecast) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "ApplyRowsBlock"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	var notes: Dictionary = {}
	for line in forecast.lines_for(apply):
		notes[String(line["key"])] = line
	# hp_heal 与 max_hp 同值成对时折叠不单列（与模型注脚同一把尺 BonusRows.folded_keys）
	var folded := BonusRows.folded_keys(apply)
	for key in apply.keys():
		var k := String(key)
		if k in folded:
			continue
		var v := float(apply[key])
		var group := VBoxContainer.new()
		group.name = "ApplyGroup_%s" % k
		group.mouse_filter = Control.MOUSE_FILTER_IGNORE
		group.add_theme_constant_override("separation", 1)
		group.add_child(BonusRows.make_row(StatInfoData.field_name(k),
			StatInfoData.format_amount(k, v), BonusRows.stat_color(k, v), font_size, row_w))
		if notes.has(k):
			var line: Dictionary = notes[k]
			var note := Label.new()
			note.name = "ForecastNote"
			note.text = GameStyle.wrap_cjk(String(line["text"]), GameStyle.body_font(),
				LevelUpDialog.FORECAST_FONT, row_w)
			note.custom_minimum_size = Vector2(row_w, 0)
			note.mouse_filter = Control.MOUSE_FILTER_IGNORE
			GameStyle.label(note, LevelUpDialog.FORECAST_FONT,
				GameStyle.PAPER_DIM if bool(line["changed"]) else GameStyle.GREY)
			group.add_child(note)
		box.add_child(group)
	return box

## 受益装备那一排：小字提醒 + 描边格 + 点按弹装备详解（StatsTipFactory 同一张卡）。
## 格子名带序号：Godot 会给同层重名节点自动改名（@PanelContainer@92），判据按名字取样会漏。
static func _append_benefit_row(dialog: LevelUpDialog, vbox: VBoxContainer,
		benefited: Array, inner_w: float, data: Dictionary) -> void:
	var n_bf := benefited.size()
	var cap_lbl := Label.new()
	cap_lbl.text = "受益装备"
	cap_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap_lbl.custom_minimum_size = Vector2(inner_w, 0)
	cap_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameStyle.label(cap_lbl, 11, GameStyle.PAPER_DIM)
	vbox.add_child(cap_lbl)
	var icon_row := HFlowContainer.new()
	icon_row.alignment = FlowContainer.ALIGNMENT_CENTER
	icon_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_row.add_theme_constant_override("h_separation", LevelUpDialog.BF_CELL_GAP)
	icon_row.add_theme_constant_override("v_separation", LevelUpDialog.BF_CELL_GAP)
	var cell_sz: float = clampf(
		(inner_w - float(LevelUpDialog.BF_CELL_GAP) * float(n_bf - 1)) / float(n_bf),
		LevelUpDialog.BF_CELL_MIN, LevelUpDialog.BF_CELL_MAX)
	var glyph_sz: float = maxf(12.0, cell_sz - LevelUpDialog.BF_CELL_PAD * 2.0)
	for gi in range(n_bf):
		var wd: Dictionary = benefited[gi]
		var cell := PanelContainer.new()
		cell.name = "BenefitCell%d" % gi
		cell.custom_minimum_size = Vector2(cell_sz, cell_sz)
		cell.add_theme_stylebox_override("panel",
			GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 1, 0.0))
		var w_icon := GameStyle.icon_texture_rect(
			String(wd.get("icon", "")),
			Vector2(glyph_sz, glyph_sz)
		)
		cell.add_child(w_icon)
		icon_row.add_child(cell)
		# 整格都是热区：图是显示件，留着 STOP 会在格面中间挖一个按不动的洞
		GameStyle.hotzone(cell)
		# 锚点与数据都得在挂回调之前定下来：GDScript 的 lambda 按值捕获创建那一刻的局部变量
		GameStyle.tap(cell, func() -> void: dialog.open_benefit_tip(cell, wd, data))
	vbox.add_child(icon_row)
