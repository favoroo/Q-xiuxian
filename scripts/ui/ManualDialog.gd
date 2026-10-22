class_name ManualDialog
extends BaseModalDialog

## 教程手册（传道玉简）：武器/道具/角色图鉴、进阶流派攻略（新手上路走「新手指南」弹窗）。
## 继承 BaseModalDialog；图鉴内容现读
## WeaponData / ItemData / CultivatorData / StatInfoData，新增条目自动进手册。
## 道具/角色两页标注解锁条件，按页懒建、并在每次 open() 后标脏（切到那一页才重建），
## 以反映最新解锁状态。五页全量约 1900 节点：一次 open 只碰当前页、同筛选不重铺、
## 铺卡晚一帧（淡入先亮）—— 商店顶栏点「图鉴」不再顿一下才弹出来，见 _ensure_page。
## 武器页委托 WeaponCodexBuilder 构建：流派筛选条（类型/元素）+ 卡面三签与关键数值行，
## 商店羁绊详情卡「查看该流派武器」经 open_weapons_page() 深链直达并预选筛选。

const PANEL_SIZE := Vector2(880, 470)
## 正文排版宽度：880 面板 − 外边距 40 − 内容面板内边距 28 − 卡片内边距 24，再留余量
const TEXT_W := 756.0

## 五行配色（武器卡 chip 用，与 GameStyle.ELEMENT_COLORS 同源）
const ELEMENT_COLORS := GameStyle.ELEMENT_COLORS

## 「属性受益」行人话名统一走 GameBalance.stat_scaling_label（与商店账单/属性面板同一把尺）。
## 删掉此处手抄表：它按属性侧旧键名（max_hp/move_speed_mult/attack_speed_mult）写，
## 而武器 stat_scalings 用 _bonus 侧键名，23 把武器的图鉴行此前会兜底露出英文原始 key。

const BEHAVIOR_NAMES := {
	WeaponData.Behavior.MELEE: "近战",
	WeaponData.Behavior.PROJECTILE: "远程",
	WeaponData.Behavior.BURST: "范围",
	WeaponData.Behavior.DRONE: "环绕",
	WeaponData.Behavior.TURRET: "机关",
	WeaponData.Behavior.SWEEP: "横扫",
	WeaponData.Behavior.BEAM: "光束",
	WeaponData.Behavior.CONE: "喷吐",
}

const PROC_NAMES := {"proc_burn": "灼烧", "proc_chill": "减速", "proc_poison": "中毒"}

## 敌人图鉴详情卡：皮实度/移速档位 → 语义色（档位词表见 EnemyGuideData.TOUGH_TIERS/SPEED_TIERS）。
## 越危险越红（BAD 朱砂）、越温和越绿（GOOD），中档走纸白——与「敌人」chip 同一套危险语义。
const TOUGH_COLORS := {
	"脆": GameStyle.GOOD_DK, "普通": GameStyle.PAPER, "厚": GameStyle.ELEMENT, "极厚": GameStyle.BAD,
}
const SPEED_COLORS := {
	"极快": GameStyle.BAD, "快": GameStyle.ELEMENT, "寻常": GameStyle.PAPER, "慢": GameStyle.GOOD_DK,
}

var _items_box: VBoxContainer
var _upgrades_box: VBoxContainer
var _pets_box: VBoxContainer
var _cult_box: VBoxContainer
var _weapons_box: VBoxContainer
var _advanced_box: VBoxContainer
var _enemies_box: VBoxContainer
## 武器图鉴当前筛选（"" = 全部）：器类与五行两条线各自独立，同时选中时取交集
var weapon_class_filter: String = ""
var weapon_element_filter: String = ""
## 筛选 chips（tag → Label；两行「全部」分别以 "all_class" / "all_element" 为键），
## build_page 建一次常驻，rebuild 时只重涂不重建
var _filter_chips: Dictionary = {}
## open() 时要直接落到哪一页（-1 = 留在当前页）。深链入口用：省掉「先建当前页、再切页重建」
var _open_tab: int = -1
## 每页内容「建过没有」「还要不要再建」——懒建与去重复建的两把锁，见 _ensure_page
var _page_built: Array[bool] = []
var _page_dirty: Array[bool] = []
## open 那一拍只翻页不铺卡（铺卡排到下一帧），期间压住 _ensure_page
var _defer_build: bool = false

func _get_title_text() -> String:
	return "图 鉴"

func _get_panel_size() -> Vector2:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0:
		vp = Vector2(960, 540)
	return Vector2(minf(PANEL_SIZE.x, vp.x - 48.0), minf(PANEL_SIZE.y, vp.y - 40.0))

func _get_top_bar_separation() -> int:
	return 8

func _get_tab_bar_separation() -> int:
	return 6

func _get_title_font_size() -> int:
	return 17

func _get_close_btn_min_size() -> Vector2:
	return Vector2(76, 34)

func _build_body(root_vbox: VBoxContainer) -> void:
	add_tab_button(0, "武器图鉴", 78.0)
	add_tab_button(1, "道具图鉴", 78.0)
	add_tab_button(2, "悟道图鉴", 78.0)
	add_tab_button(3, "灵兽图鉴", 78.0)
	add_tab_button(4, "角色图鉴", 78.0)
	add_tab_button(5, "敌人图鉴", 78.0)
	add_tab_button(6, "进阶攻略", 78.0)

	var content_panel := PanelContainer.new()
	content_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var cont_sb := GameStyle.outlined_panel(GameStyle.NAVY2, GameStyle.INK, 2, 0.0)
	cont_sb.content_margin_left = 14.0
	cont_sb.content_margin_top = 10.0
	cont_sb.content_margin_right = 14.0
	cont_sb.content_margin_bottom = 10.0
	content_panel.add_theme_stylebox_override("panel", cont_sb)
	root_vbox.add_child(content_panel)

	# 只建七页的「壳」（滚动区 + 空容器），内容等这一页真被看到时才填，见 _ensure_page。
	for i in range(7):
		_page_built.append(false)
		_page_dirty.append(false)
	_pages.append(_build_weapons_page(content_panel))
	_pages.append(_build_items_page(content_panel))
	_pages.append(_build_upgrades_page(content_panel))
	_pages.append(_build_pets_page(content_panel))
	_pages.append(_build_cultivators_page(content_panel))
	_pages.append(_build_enemies_page(content_panel))
	_pages.append(_build_advanced_page(content_panel))

	switch_tab(0)

func _on_opened() -> void:
	# 打开这一拍只翻页 + 标脏，铺卡推到下一帧（见 _schedule_page）：面板先亮起来
	# 开始淡入，手指按下到看见响应之间不留主线程空档。
	_defer_build = true
	if _open_tab >= 0:
		# 深链（商店顶栏「图鉴」/「查看该流派武器」）：筛选已在 open() 前设好，
		# 直接落那一页，不再先建当前页、切页后又整页重建一遍。
		switch_tab(_open_tab)
		_open_tab = -1
	else:
		# 每次打开回落「全部」：主菜单/暂停菜单的图鉴入口不带上次筛选。
		_set_weapon_filters("", "")
	# 道具(1)/角色(4)/敌人(5) 受解锁（收录）状态影响：标脏，切到那一页时才重建
	_page_dirty[1] = true
	_page_dirty[4] = true
	_page_dirty[5] = true
	var target := _current_tab
	_defer_build = false
	_schedule_page(target)

## 深链入口：商店顶栏「图鉴」按钮 / 羁绊详情卡「查看该流派武器」直达武器页并预选筛选。
## 羁绊只属于一条线：器类标签锁类型行、五行标签锁元素行，另一条线清空，避免叠加成空结果。
func open_weapons_page(filter_tag: String = "") -> void:
	var tag := String(filter_tag)
	if tag in WeaponData.CLASSES:
		_set_weapon_filters(tag, "")
	elif tag in WeaponData.ELEMENTS:
		_set_weapon_filters("", tag)
	else:
		_set_weapon_filters("", "")
	if visible:
		switch_tab(0)
		return
	_open_tab = 0
	open()

## 点 chip：在本行内切换；再点已选中的（含「全部」）即清空本行，另一行保持不动。
func _on_filter_chip_tapped(group: String, tag: String) -> void:
	var cur := weapon_class_filter if group == "class" else weapon_element_filter
	var next := "" if String(tag) == cur else String(tag)
	if group == "class":
		_set_weapon_filters(next, weapon_element_filter)
	else:
		_set_weapon_filters(weapon_class_filter, next)
	_ensure_page(0)

## 换筛选 = 武器页欠一次重建；两条线都没变则整页照用（卡面全是 WeaponData 里的静态值）
func _set_weapon_filters(class_tag: String, element_tag: String) -> void:
	if class_tag == weapon_class_filter and element_tag == weapon_element_filter:
		return
	weapon_class_filter = class_tag
	weapon_element_filter = element_tag
	if _page_dirty.size() > 0:
		_page_dirty[0] = true

func _on_tab_switched(index: int) -> void:
	_ensure_page(index)

## 分页内容懒建：一页只在「第一次被看到」或「被标脏」时才构建。
## 为什么：五页全量约 1900 个节点，旧写法一次 open 就把整本手册重铺一遍
## （武器页还重复建两次：open() 里一次、open_weapons_page() 里一次），
## 实测按下商店「图鉴」后主线程同步占住 124~181 ms（M 系 Mac，真机更久）
## ⇒ 先顿一下才淡入。现在一次 open 只碰当前页，同筛选不重铺，铺卡晚一帧。
func _ensure_page(index: int) -> void:
	if _defer_build:
		return                      # 打开流程末尾统一排一帧去建
	_build_page(index)

## 把铺卡推到下一帧：淡入第一帧 alpha 还近乎 0，内容晚一拍到，
## 玩家看到的是「立刻弹出来、内容随即填上」，不是按下后卡住。
func _schedule_page(index: int) -> void:
	if not is_inside_tree():
		_build_page(index)
		return
	get_tree().process_frame.connect(_build_page.bind(index), CONNECT_ONE_SHOT)

func _build_page(index: int) -> void:
	if index < 0 or index >= _pages.size():
		return
	if _page_built[index] and not _page_dirty[index]:
		return
	match index:
		0: _rebuild_weapons_page()
		1: _rebuild_items_page()
		2: _rebuild_upgrades_page()
		3: _rebuild_pets_page()
		4: _rebuild_cultivators_page()
		5: _rebuild_enemies_page()
		6: _fill_advanced_page()
	_page_built[index] = true
	_page_dirty[index] = false
	# 整页子树建过就要重挂滚动拖动锁（头注「灰色卡片滑不动」坑）；
	# 筛选 chips 在滚动区外也一起过一遍——PASS 不影响它们收点按。
	GameStyle.swipeable(_pages[index] as Control)

func _rebuild_weapons_page() -> void:
	if _weapons_box == null:
		return
	for c in _weapons_box.get_children():
		c.queue_free()
	WeaponCodexBuilder.rebuild(self)
	WeaponCodexBuilder.restyle_chips(self)

# ----------------- 通用小件 -----------------

func _new_scroll(parent: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	return scroll

func _new_scroll_vbox(scroll: ScrollContainer, separation: int = 8) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", separation)
	scroll.add_child(box)
	return box

## 分段图文卡：段题（黄）+ 可选插图 + 正文（wrap_cjk 硬换行）
func _make_text_card(title: String, body: String, image: String = "", image_h: float = 80.0) -> Control:
	var card := PanelContainer.new()
	var sb := GameStyle.block(GameStyle.NAVY2, GameStyle.SLANT_PLATE, Vector2(2, 3))
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	card.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	card.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = "◆ " + title
	GameStyle.label(title_lbl, 15, GameStyle.JADE_DK, 0, GameStyle.INK, true)
	vbox.add_child(title_lbl)

	if image != "" and ResourceLoader.exists(image):
		var img_center := CenterContainer.new()
		var tex := TextureRect.new()
		tex.texture = load(image)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(image_h * 2.0, image_h)
		img_center.add_child(tex)
		vbox.add_child(img_center)

	var body_lbl := Label.new()
	body_lbl.text = GameStyle.wrap_cjk(body, GameStyle.body_font(), 13, TEXT_W)
	GameStyle.label(body_lbl, 13, GameStyle.PAPER_DIM)
	vbox.add_child(body_lbl)

	return card

func _load_icon(path: String, tex_size: Vector2) -> TextureRect:
	# 统一走 GameStyle 图标工厂：武器图标自动优先 ui/ 128px 高清变体 + LINEAR 滤波，
	# 不再手写 load（手写只拿 48px 战斗画布，40px 槽位放大偏糊）；item 无变体原样回退，行为不变。
	return GameStyle.icon_texture_rect(path, tex_size)

## 图鉴小卡：图标 + 名称（+ 可选色签行 / 副标签 + 可选关键数值行），点按开 DetailTip
## chips = [[文字, 面色, 字色], ...]，与商店卡行②的 chip_defs 同形状、同一个
## GameStyle.chip_label 画。给了 chips 就不画 sub 那行灰字（同一件事不印两遍）。
func _make_entry_card(icon: String, name: String, sub: String, sub_color: Color,
		on_press: Callable, stat_line: String = "", chips: Array = []) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(148, 0)
	var sb := GameStyle.block(GameStyle.NAVY2, GameStyle.SLANT_PLATE, Vector2(2, 3))
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	card.add_theme_stylebox_override("panel", sb)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.set_meta("tip_title", name)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	var icon_center := CenterContainer.new()
	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(48, 48)
	icon_box.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 1, 0.0))
	var tex := _load_icon(icon, Vector2(40, 40))
	tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex.offset_left = 4
	tex.offset_top = 4
	tex.offset_right = -4
	tex.offset_bottom = -4
	icon_box.add_child(tex)
	icon_center.add_child(icon_box)
	vbox.add_child(icon_center)
	card.set_meta("icon_tex", tex)

	var name_lbl := Label.new()
	name_lbl.text = name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameStyle.label(name_lbl, 13, GameStyle.PAPER, 0, GameStyle.INK, true)
	vbox.add_child(name_lbl)

	if not chips.is_empty():
		# 色签成排：摆得下就一行，摆不下自动折第二行（图鉴卡窄，双器类武器有 4 签）
		var flow := HFlowContainer.new()
		flow.name = "TagFlow"
		flow.alignment = FlowContainer.ALIGNMENT_CENTER
		flow.add_theme_constant_override("h_separation", 4)
		flow.add_theme_constant_override("v_separation", 3)
		vbox.add_child(flow)
		for cd in chips:
			flow.add_child(GameStyle.chip_label(String(cd[0]), cd[1] as Color, cd[2] as Color))
	elif sub != "":
		var sub_lbl := Label.new()
		sub_lbl.text = sub
		sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		GameStyle.label(sub_lbl, 11, sub_color)
		vbox.add_child(sub_lbl)

	if stat_line != "":
		var stat_lbl := Label.new()
		stat_lbl.text = stat_line
		stat_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		GameStyle.label(stat_lbl, 10, GameStyle.PAPER_DIM)
		vbox.add_child(stat_lbl)

	GameStyle.tap(card, func() -> void: on_press.call(card))
	# 整格都是热区：图框那层 PanelContainer 默认 STOP，会把「点图片」这一枪截在半路 ——
	# 真机上就成了点名字弹卡、点图没反应（用户 2026-10-09 反馈）。放在最后一步统一压子树。
	GameStyle.hotzone(card)
	return card

# ----------------- 分页 1：武器图鉴 -----------------

## 筛选条 + 网格的构建与重建全在 WeaponCodexBuilder（本类只持状态与深链入口）
func _build_weapons_page(parent: Control) -> Control:
	return WeaponCodexBuilder.build_page(self, parent)

func _open_weapon_tip(wid: String, anchor: Control) -> void:
	var def := WeaponData.get_def(wid)
	if def.is_empty():
		return
	var elem := ""
	for t in def.get("tags", []):
		if t in WeaponData.ELEMENTS:
			elem = String(t)
	var chip_color: Color = ELEMENT_COLORS.get(elem, GameStyle.GOLD)

	# 行名与货架卡/详情卡用同一套词（2026-10-11 用户「看不懂」口径的同类问题）：
	# 旧写法这里自有一套黑话 ——「路数」「射程/范围」「贯穿」，与商店那屏的
	# 「攻击方式」「攻击范围」「穿透」指的是同一件事，玩家对不上号。
	# 「伤害」加「基础」两字：图鉴这一列是数据表纸面值，本局加成不在这里，
	# 而商店卡上那个「伤害 26 → 31.1」右边才是你实际打得出的数，不加限定词会当成同一个。
	var rows: Array = [
		["攻击方式", String(BEHAVIOR_NAMES.get(def.get("behavior", 0), "近战")), chip_color],
		["基础伤害", "%d" % int(def.get("damage", 0)), GameStyle.JADE],
		["攻击间隔", "%s 秒" % String.num(float(def.get("cooldown", 1.0)), 2), GameStyle.PAPER],
		["攻击范围", "%d" % int(def.get("range", 0)), GameStyle.PAPER],
		["买入价格", "%d 金币" % int(def.get("price", 0)), GameStyle.JADE],
	]
	if int(def.get("pierce", 0)) > 1:
		rows.append(["穿透", "%d 敌" % int(def["pierce"]), GameStyle.PAPER])
	if int(def.get("projectile_count", 1)) > 1:
		rows.append(["齐射", "%d 发" % int(def["projectile_count"]), GameStyle.PAPER])
	for proc_key in PROC_NAMES.keys():
		if def.has(proc_key):
			rows.append(["异常状态", PROC_NAMES[proc_key], chip_color])

	var notes: Array[String] = []
	var scalings: Dictionary = def.get("stat_scalings", {})
	if not scalings.is_empty():
		var names: Array[String] = []
		for key in scalings.keys():
			names.append(GameBalance.stat_scaling_label(String(key)))
		notes.append("属性受益：" + "、".join(names))
	notes.append("集齐 3 把同名同星可在商店合成升星")

	DetailTip.show_over(self, anchor, {
		"title": String(def.get("name", wid)),
		"chip": " " + String(def.get("tag", "")) + " ",
		"chip_color": chip_color,
		"rows": rows,
		"body": String(def.get("desc", "")),
		"notes": notes,
		"foot": "武器仅在回合间商店有售",
	})

# ----------------- 分页 2：道具图鉴 -----------------

func _build_items_page(parent: Control) -> Control:
	var scroll := _new_scroll(parent)
	_items_box = _new_scroll_vbox(scroll)
	return scroll

func _rebuild_items_page() -> void:
	if _items_box == null:
		return
	for c in _items_box.get_children():
		c.queue_free()
	_items_box.add_child(_make_text_card("道具规则",
		"道具是买即生效的被动道具，无限持有、不占武器栏位。\n品阶越高现身越晚、价格越贵：普通开局即有，稀有、史诗、传说随回合陆续现身。\n加成读数认颜色：绿色是增益、红色是代偿，数值与实际生效幅度同源。\n点按任意道具卡查看效果与入手价。"))

	for tier in [1, 2, 3, 4]:
		var tier_col: Color = ItemData.tier_color(tier)
		var header := Label.new()
		header.text = "── %s ──" % ItemData.tier_label(tier)
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		GameStyle.label(header, 13, tier_col, 0, GameStyle.INK, true)
		_items_box.add_child(header)

		var grid := GridContainer.new()
		grid.columns = 5
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_items_box.add_child(grid)

		for iid in ItemData.DEFS.keys():
			var def: Dictionary = ItemData.DEFS[iid]
			if int(def.get("tier", 1)) != tier:
				continue
			var unlocked := GameManager.is_item_unlocked(iid)
			var card := _make_entry_card(
				String(def.get("icon", "")), String(def.get("name", iid)),
				"" if unlocked else "未收录", GameStyle.GREY,
				func(anchor: Control): _open_item_tip(iid, anchor))
			if not unlocked:
				(card.get_meta("icon_tex") as TextureRect).modulate = GameStyle.disabled_modulate()
			grid.add_child(card)

func _open_item_tip(iid: String, anchor: Control) -> void:
	var def := ItemData.get_def(iid)
	if def.is_empty():
		return
	var tier_num := int(def.get("tier", 1))
	var tier_col := ItemData.tier_color(tier_num)
	var rows: Array = [
		["品阶", ItemData.tier_label(tier_num), tier_col],
		# 词与商店那张详情卡对齐（2026-10-12 道具可出售）：这一行是数据表里的基准价，
		# 当回合上架价每回合还要 +2，写「买入价格」会让人以为自己付的就是这个数。
		["原价", "%d 金币" % int(def.get("price", 0)), GameStyle.PAPER_DIM],
		["出售返还", "%d 金币" % ItemData.sell_price(iid), GameStyle.JADE],
	]
	# 加成行（2026-10-11 土豆兄弟式改版）：与商店卡面同源同色，BonusRows 从 apply 直接生成
	rows.append_array(BonusRows.apply_rows(def.get("apply", {})))
	var desc_lines := String(def.get("desc", "")).split("\n")
	var notes: Array[String] = []
	for line in desc_lines:
		if line.strip_edges() != "":
			notes.append(line.strip_edges())
	var foot := ""
	if not GameManager.is_item_unlocked(iid):
		foot = AchievementData.unlock_hint_text(iid, true, "收录条件：")
	elif bool(def.get("unique", false)):
		foot = "每局限购一件"

	DetailTip.show_over(self, anchor, {
		"title": String(def.get("name", iid)),
		"chip": " " + ItemData.tier_label(tier_num) + " ",
		"chip_color": tier_col,
		"rows": rows,
		"notes": notes,
		"foot": foot,
	})

# ----------------- 分页 3：悟道图鉴 -----------------

func _build_upgrades_page(parent: Control) -> Control:
	var scroll := _new_scroll(parent)
	_upgrades_box = _new_scroll_vbox(scroll)
	return scroll

func _rebuild_upgrades_page() -> void:
	if _upgrades_box == null:
		return
	for c in _upgrades_box.get_children():
		c.queue_free()
	_upgrades_box.add_child(_make_text_card("悟道规则",
		"悟道是战斗中升级后在回合间领悟的被动增益，整局生效。\n一屏给出 5 个候选，每回合有 1 次免费刷新机会。\n按稀有度分普通、稀有、史诗、传说：品质越高出现概率越低、单项加成幅度越强。\n点按任意悟道卡查看加成幅度与最大加修层数。"))

	var groups: Array = [
		["普通悟道", "common", GameStyle.PAPER],
		["稀有悟道", "rare", GameStyle.GOLD],
		["史诗悟道", "epic", GameStyle.RARITY_EPIC],
		["传说悟道", "legendary", GameStyle.RARITY_LEGEND],
	]
	for g in groups:
		var rarity_key := String(g[1])
		var rarity_col := g[2] as Color
		var header := Label.new()
		header.text = "── %s ──" % String(g[0])
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		GameStyle.label(header, 13, rarity_col, 0, GameStyle.INK, true)
		_upgrades_box.add_child(header)

		var grid := GridContainer.new()
		grid.columns = 5
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_upgrades_box.add_child(grid)

		for udef in UpgradeData.UPGRADES:
			var u: Dictionary = udef
			if String(u.get("rarity", "common")) != rarity_key:
				continue
			var title_str: String = String(u.get("title", ""))
			var icon_str: String = String(u.get("icon", ""))
			var card := _make_entry_card(
				icon_str, title_str,
				String(u.get("rarity_label", "普通")), rarity_col,
				func(anchor: Control): _open_upgrade_tip(u, anchor))
			grid.add_child(card)

func _open_upgrade_tip(udef: Dictionary, anchor: Control) -> void:
	var rarity_str: String = String(udef.get("rarity", "common"))
	var rarity_col: Color = GameStyle.rarity_color(rarity_str)
	var rows: Array = [
		["稀有度", String(udef.get("rarity_label", "普通")), rarity_col],
		["最多加修", "%d 层" % int(udef.get("max_stacks", 1)), GameStyle.PAPER],
	]
	rows.append_array(BonusRows.apply_rows(udef.get("apply", {})))
	var notes: Array[String] = []
	var desc := String(udef.get("desc", "")).strip_edges()
	if not desc.is_empty():
		notes.append(desc)
	notes.append("回合结束后升级时从 5 个候选卡中领悟")

	DetailTip.show_over(self, anchor, {
		"title": String(udef.get("title", "")),
		"chip": " " + String(udef.get("rarity_label", "普通")) + " ",
		"chip_color": rarity_col,
		"rows": rows,
		"notes": notes,
		"foot": "加点即刻生效，局内永久加成",
	})

# ----------------- 分页 4：灵兽图鉴 -----------------

func _build_pets_page(parent: Control) -> Control:
	var scroll := _new_scroll(parent)
	_pets_box = _new_scroll_vbox(scroll)
	return scroll

func _rebuild_pets_page() -> void:
	if _pets_box == null:
		return
	for c in _pets_box.get_children():
		c.queue_free()
	_pets_box.add_child(_make_text_card("灵兽伙伴",
		"随行灵兽可在金币阁货架购买，购买后永久随行战斗，不占武器栏位。\n寻常修士限带 1 只，御兽师最多可随行 3 只；随行期间亦可在商店折半退还金币。\n灵兽伤害、效果与冷却享受「灵兽伤害 / 灵兽效果 / 灵兽冷却」属性加成。\n点按任意灵兽卡查看助战技能与买价。"))

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_pets_box.add_child(grid)

	for pid in PetData.all_ids():
		var pdef: Dictionary = PetData.get_def(String(pid))
		var card := _make_pet_entry_card(pdef, func(anchor: Control): _open_pet_tip(pdef, anchor))
		grid.add_child(card)

func _make_pet_entry_card(pdef: Dictionary, on_press: Callable) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(160, 0)
	var sb := GameStyle.block(GameStyle.NAVY2, GameStyle.SLANT_PLATE, Vector2(2, 3))
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	card.add_theme_stylebox_override("panel", sb)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.set_meta("tip_title", String(pdef.get("name", "")))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	var icon_center := CenterContainer.new()
	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(48, 48)
	var p_col: Color = pdef.get("color", GameStyle.GOLD)
	icon_box.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, p_col, 1, 0.0))

	var pet_preview := Control.new()
	pet_preview.custom_minimum_size = Vector2(40, 40)
	pet_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pet_preview.draw.connect(func():
		var c: Color = pdef.get("color", Color(0.9, 0.9, 0.9))
		var halo: Color = pdef.get("halo_color", Color(1.0, 1.0, 1.0, 0.3))
		var sz: Vector2 = pet_preview.size
		var center := sz * 0.5
		var r: float = sz.x * 0.28
		pet_preview.draw_circle(center, r * 1.6, halo)
		pet_preview.draw_circle(center, r, c)
		pet_preview.draw_circle(center + Vector2(-r * 0.25, -r * 0.25), r * 0.35, Color(1.0, 1.0, 1.0, 0.85))
	)
	icon_box.add_child(pet_preview)
	icon_center.add_child(icon_box)
	vbox.add_child(icon_center)

	var name_lbl := Label.new()
	name_lbl.text = String(pdef.get("name", ""))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameStyle.label(name_lbl, 13, GameStyle.PAPER, 0, GameStyle.INK, true)
	vbox.add_child(name_lbl)

	var role_key := String(pdef.get("role", "attack"))
	var role_name := String(PetData.ROLES.get(role_key, "助战"))
	var role_chip := GameStyle.chip_label(role_name, p_col, GameStyle.on_face_text(p_col))
	role_chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(role_chip)

	var stat_lbl := Label.new()
	stat_lbl.text = "%d金币 · %.1f秒" % [int(pdef.get("base_price", 0)), float(pdef.get("base_cooldown", 1.0))]
	stat_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameStyle.label(stat_lbl, 10, GameStyle.PAPER_DIM)
	vbox.add_child(stat_lbl)

	GameStyle.tap(card, func() -> void: on_press.call(card))
	GameStyle.hotzone(card)
	return card

func _open_pet_tip(pdef: Dictionary, anchor: Control) -> void:
	var p_col: Color = pdef.get("color", GameStyle.GOLD)
	var role_key := String(pdef.get("role", "attack"))
	var role_name := String(PetData.ROLES.get(role_key, "助战"))
	var base_price := int(pdef.get("base_price", 0))
	var rows: Array = [
		["定位", role_name, p_col],
		["基础买价", "%d 金币" % base_price, GameStyle.JADE],
		["出手周期", "%.1f 秒" % float(pdef.get("base_cooldown", 1.0)), GameStyle.PAPER],
		["出售返还", "%d 金币" % int(float(base_price) * PetData.SELL_RATIO), GameStyle.JADE],
	]
	var notes: Array[String] = []
	var desc := String(pdef.get("desc", "")).strip_edges()
	if not desc.is_empty():
		notes.append(desc)
	notes.append("灵兽属性吃「灵兽伤害 / 灵兽效果 / 灵兽冷却」加成")
	notes.append("普通修士限带 1 只，御兽师最多随行 3 只")

	DetailTip.show_over(self, anchor, {
		"title": String(pdef.get("name", "")),
		"chip": " 灵兽 ",
		"chip_color": p_col,
		"rows": rows,
		"notes": notes,
		"foot": "仅在金币阁有售，购买后永久随行",
	})

# ----------------- 分页 5：角色图鉴 -----------------

func _build_cultivators_page(parent: Control) -> Control:
	var scroll := _new_scroll(parent)
	_cult_box = _new_scroll_vbox(scroll)
	return scroll

func _rebuild_cultivators_page() -> void:
	if _cult_box == null:
		return
	for c in _cult_box.get_children():
		c.queue_free()
	_cult_box.add_child(_make_text_card("角色规则",
		"每名角色都是「超能力 + 严苛负面代偿」的不对称设计：选人是本局最重要的流派决定。\n初始开放八名角色，其余通过「战绩」的成就解锁。"))

	for cid in CultivatorData.DEFS.keys():
		var def: Dictionary = CultivatorData.DEFS[cid]
		_cult_box.add_child(_make_cultivator_row(cid, def))

func _make_cultivator_row(cid: String, def: Dictionary) -> Control:
	var unlocked := GameManager.is_cultivator_unlocked(cid)
	var row := PanelContainer.new()
	var sb := GameStyle.block(GameStyle.NAVY2 if unlocked else GameStyle.INK.lightened(0.02),
		GameStyle.SLANT_PLATE, Vector2(2, 3))
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	sb.border_color = GameStyle.LINE if unlocked else GameStyle.LINE.darkened(0.3)
	row.add_theme_stylebox_override("panel", sb)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	row.add_child(hbox)

	# 头像
	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(56, 56)
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_box.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 1, 0.0))
	var tex := _load_icon(String(def.get("icon", "")), Vector2(48, 48))
	tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex.offset_left = 4
	tex.offset_top = 4
	tex.offset_right = -4
	tex.offset_bottom = -4
	if not unlocked:
		tex.modulate = GameStyle.disabled_modulate()
	icon_box.add_child(tex)
	hbox.add_child(icon_box)

	# 名号 + 题词 + 优劣
	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 2)
	hbox.add_child(text_col)

	var name_lbl := Label.new()
	name_lbl.text = String(def.get("name", cid))
	# 锁定行是暗底（INK 压暗），名字走暗底亮字；解锁行同底，名字走纸白
	GameStyle.label(name_lbl, 15, GameStyle.PAPER if unlocked else GameStyle.PAPER_DIM, 0, GameStyle.INK, true)
	text_col.add_child(name_lbl)

	var epithet_lbl := Label.new()
	epithet_lbl.text = String(def.get("epithet", ""))
	GameStyle.label(epithet_lbl, 11, GameStyle.GREY)
	text_col.add_child(epithet_lbl)

	var equip_str: String = String(def.get("start_equip", ""))
	if not equip_str.is_empty():
		var equip_lbl := Label.new()
		equip_lbl.text = "◆ " + equip_str
		GameStyle.label(equip_lbl, 12, GameStyle.JADE_DK)
		text_col.add_child(equip_lbl)

	for pro in def.get("pros", []):
		var pro_lbl := Label.new()
		pro_lbl.text = "＋ " + String(pro)
		GameStyle.label(pro_lbl, 12, GameStyle.GOOD_DK)
		text_col.add_child(pro_lbl)
	# 额外技能单独一段（幽夜紫）：与选角界面同一份文案、同一个色语义（数字现读机制表）
	for x_line in CultivatorData.get_extra_desc(cid):
		var x_lbl := Label.new()
		x_lbl.text = String(x_line)
		GameStyle.label(x_lbl, 12, GameStyle.SHADOW)
		text_col.add_child(x_lbl)
	for con in def.get("cons", []):
		var con_lbl := Label.new()
		con_lbl.text = "－ " + String(con)
		GameStyle.label(con_lbl, 12, GameStyle.BAD)
		text_col.add_child(con_lbl)

	# 解锁状态
	var status_lbl := Label.new()
	status_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if unlocked:
		status_lbl.text = " 已入门 "
		status_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.GOOD_DK))
		# 暗绿徽章配暗底亮字（GOOD 已调深，与 GOOD_DK 同明度会糊）
		GameStyle.label(status_lbl, 12, GameStyle.CHALK)
	else:
		status_lbl.text = " 未解锁 "
		status_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.LINE))
		GameStyle.label(status_lbl, 12, GameStyle.GREY)
		var cond_lbl := Label.new()
		cond_lbl.text = AchievementData.unlock_hint_text(cid, false, "解锁条件：")
		GameStyle.label(cond_lbl, 11, GameStyle.JADE_DK)
		text_col.add_child(cond_lbl)
	hbox.add_child(status_lbl)

	return row

func _on_closed() -> void:
	if GameManager.run_started:
		trim_heavy_pages()

## 在对局战斗期间释放重页内容（保树体精简，待下次打开再按页懒建）
func trim_heavy_pages() -> void:
	if visible:
		return
	if _weapons_box != null:
		for c in _weapons_box.get_children():
			c.queue_free()
		_page_built[0] = false
		_page_dirty[0] = true
	if _items_box != null:
		for c in _items_box.get_children():
			c.queue_free()
		_page_built[1] = false
		_page_dirty[1] = true
	if _upgrades_box != null:
		for c in _upgrades_box.get_children():
			c.queue_free()
		_page_built[2] = false
		_page_dirty[2] = true
	if _pets_box != null:
		for c in _pets_box.get_children():
			c.queue_free()
		_page_built[3] = false
		_page_dirty[3] = true
	if _cult_box != null:
		for c in _cult_box.get_children():
			c.queue_free()
		_page_built[4] = false
		_page_dirty[4] = true
	if _enemies_box != null:
		for c in _enemies_box.get_children():
			c.queue_free()
		_page_built[5] = false
		_page_dirty[5] = true

# ----------------- 分页 6：敌人图鉴 -----------------

func _build_enemies_page(parent: Control) -> Control:
	var scroll := _new_scroll(parent)
	_enemies_box = _new_scroll_vbox(scroll)
	return scroll

## 分组重建：常规妖物（12 种）→ 精英劫（3 种）→ 魔君 → 金蟾。未遭遇的种灰显「未收录」，
## 与道具页同款待遇；收录口径 = 实战里刷出过（EnemyCodex），追不上的金蟾也算。
## 图标现渲捕获（EnemyIconCapture）：先铺占位，捕完逐张回填，页不卡在建图上。
func _rebuild_enemies_page() -> void:
	if _enemies_box == null:
		return
	for c in _enemies_box.get_children():
		c.queue_free()
	_enemies_box.add_child(_make_text_card("敌人图鉴",
		"妖物在实战中刷出过一次即自动收录。\n点按任意妖物卡查看威胁与出没波次。"))

	var groups: Array = [
		["常规妖物", EnemyGuideData.catalog_ids().slice(0, 12), false],
		["精英劫", EnemyGuideData.catalog_ids().slice(12, 15), true],
		["魔君劫", ["boss"], false],
		["招财金蟾", ["jinchan"], false],
	]
	for g in groups:
		var header := Label.new()
		header.text = "── %s ──" % String(g[0])
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		GameStyle.label(header, 13, GameStyle.JADE_DK, 0, GameStyle.INK, true)
		_enemies_box.add_child(header)

		var grid := GridContainer.new()
		grid.columns = 5
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_enemies_box.add_child(grid)

		for eid_v in g[1] as Array:
			var eid := String(eid_v)
			var is_elite := bool(g[2])
			var seen := EnemyCodex.is_seen(eid)
			# chips 非空时 _make_entry_card 不画 sub 行 ⇒ 未遭遇干脆不放威胁签
			# （没见过就该什么都不知道），空 chips 让「未收录」副标照常显示，与道具页同款待遇
			var chips: Array = []
			if seen:
				for tag in EnemyGuideData.GUIDE[eid].get("tags", []):
					chips.append([String(tag), GameStyle.GOLD, GameStyle.INK_TEXT])
			var card := _make_entry_card(
				"", EnemyGuideData.display_name(eid),
				"" if seen else "未收录", GameStyle.GREY,
				func(anchor: Control): _open_enemy_tip(eid, anchor),
				EnemyGuideData.first_seen_text(eid, GameManager.endless_mode), chips)
			if not seen:
				# 未遭遇不捕图不剧透形象：灰显的是空占位框（与道具页「图标压暗」同理——
				# 没见过的东西不该在图鉴里先亮出来）
				(card.get_meta("icon_tex") as TextureRect).modulate = GameStyle.disabled_modulate()
			else:
				_fill_enemy_icon(card, eid, is_elite)
			grid.add_child(card)

## 图标异步回填：已捕过直接同步给图（重开页不重捕）；没捕过排队现渲。
## 卡片可能在捕获期间被整页重建拆走 —— 回填前过 is_instance_valid。
func _fill_enemy_icon(card: Control, eid: String, is_elite: bool) -> void:
	var tex := card.get_meta("icon_tex") as TextureRect
	if tex == null:
		return
	var cached := EnemyIconCapture.peek(eid, is_elite)
	if cached != null:
		tex.texture = cached
		return
	_apply_icon_async(tex, eid, is_elite)

func _apply_icon_async(tex: TextureRect, eid: String, is_elite: bool) -> void:
	var got := await EnemyIconCapture.capture(eid, is_elite)
	if got != null and is_instance_valid(tex):
		tex.texture = got

func _open_enemy_tip(eid: String, anchor: Control) -> void:
	var def: Dictionary = EnemyGuideData.GUIDE.get(eid, {})
	if def.is_empty():
		return
	var seen := EnemyCodex.is_seen(eid)
	var desc := String(def.get("desc", ""))
	var rows: Array = []
	var body := ""
	var notes: Array[String] = []
	if seen:
		# 遭遇过才给强度行：没见过的东西只露「出没/收录」，与卡面不放威胁签同一口径。
		# 攻击方式固定朱砂（它就是「它会怎么打你」），皮实度/移速按档位取色（越极端越红）。
		rows.append(["攻击方式", String(def.get("attack", "")), GameStyle.BAD])
		var tough := String(def.get("tough", ""))
		rows.append(["皮实度", tough, TOUGH_COLORS.get(tough, GameStyle.PAPER)])
		var swift := String(def.get("swift", ""))
		rows.append(["移速", swift, SPEED_COLORS.get(swift, GameStyle.PAPER)])
		# 正文两行：威胁句（【】机制词染朱砂）+「应对」灰标签配纸白建议。
		# 中文长句在真机上不能指望引擎折行（AGENTS.md 坑 4），按卡内可用宽预切硬换行。
		var text := _danger_bbcode(desc)
		var counter := String(def.get("counter", ""))
		if not counter.is_empty():
			text += "\n" + _bbcode_text("应对", GameStyle.GREY) + " " \
				+ _bbcode_text(counter, GameStyle.PAPER)
		body = GameStyle.wrap_bbcode(text, GameStyle.body_font(), 13, DetailTip.INNER_W)
	else:
		notes.append(_desc_plain(desc))
	rows.append(["出没", EnemyGuideData.first_seen_text(eid, GameManager.endless_mode), GameStyle.PAPER])
	rows.append(["收录", "已遭遇" if seen else "未遭遇", GameStyle.GOOD if seen else GameStyle.GREY])
	DetailTip.show_over(self, anchor, {
		"title": EnemyGuideData.display_name(eid),
		"chip": " 敌人 ",
		"chip_color": GameStyle.BAD,
		"rows": rows,
		"body": body,
		"notes": notes,
		"foot": "收录途径：实战中遭遇" if not seen else "",
	})

## 文案里的【】是「危险机制词」标记（口径见 EnemyGuideData 头注），详情卡正文染朱砂。
## 与 CultivatorSelect.highlight_bbcode 同一手法，只是这里只认一种强调色。
static func _danger_bbcode(raw: String) -> String:
	var re := RegEx.new()
	re.compile("【([^】]+)】")
	return re.sub(raw, _bbcode_open(GameStyle.BAD) + "$1" + BB_COLOR_CLOSE, true)

## 未收录只给纯文本：括号是排版记号，不该在玩家面前露出来
static func _desc_plain(raw: String) -> String:
	return raw.replace("【", "").replace("】", "")

const BB_COLOR_CLOSE := "[/color]"

static func _bbcode_open(col: Color) -> String:
	return "[color=#" + col.to_html(false) + "]"

static func _bbcode_text(s: String, col: Color) -> String:
	return _bbcode_open(col) + s + BB_COLOR_CLOSE


# ----------------- 分页 7：进阶心法 -----------------

func _build_advanced_page(parent: Control) -> Control:
	var scroll := _new_scroll(parent)
	_advanced_box = _new_scroll_vbox(scroll)
	return scroll

## 静态内容，一辈子建一次（_ensure_page 里不标脏）
func _fill_advanced_page() -> void:
	if _advanced_box == null:
		return
	_advanced_box.add_child(_make_synergy_card())
	_advanced_box.add_child(_make_stat_guide_card())
	for guide in ManualData.BUILD_GUIDES:
		_advanced_box.add_child(_make_build_card(guide))
	for sec in ManualData.ADVANCED_SECTIONS:
		_advanced_box.add_child(_make_text_card(String(sec.get("title", "")), String(sec.get("body", ""))))

## 流派羁绊一览：现读 WeaponData.SYNERGIES，器类 5 行 + 五行 5 行
func _make_synergy_card() -> Control:
	var card := PanelContainer.new()
	var sb := GameStyle.block(GameStyle.NAVY2, GameStyle.SLANT_PLATE, Vector2(2, 3))
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	card.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	card.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = "◆ 流派羁绊"
	GameStyle.label(title_lbl, 15, GameStyle.JADE_DK, 0, GameStyle.INK, true)
	vbox.add_child(title_lbl)

	var intro_lbl := Label.new()
	intro_lbl.text = GameStyle.wrap_cjk(
		"持有同一标签的武器达 2 / 4 / 6 件时逐级激活羁绊加成。类型与元素两条线互不冲突、同时生效——凑羁绊是中期发力的核心。",
		GameStyle.body_font(), 13, TEXT_W)
	GameStyle.label(intro_lbl, 13, GameStyle.PAPER_DIM)
	vbox.add_child(intro_lbl)

	for group in [["类型", WeaponData.CLASSES], ["元素", WeaponData.ELEMENTS]]:
		var g_lbl := Label.new()
		g_lbl.text = "─ %s ─" % String(group[0])
		GameStyle.label(g_lbl, 12, GameStyle.GREY)
		vbox.add_child(g_lbl)
		for tag in group[1]:
			var syn: Dictionary = WeaponData.SYNERGIES.get(tag, {})
			if syn.is_empty():
				continue
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 10)
			vbox.add_child(line)
			var name_lbl := Label.new()
			name_lbl.text = String(syn.get("name", tag))
			name_lbl.custom_minimum_size = Vector2(64, 0)
			# 纸灰卡上亮蓝字会洗白，类型名走主蓝（元素名深玉绿白底可读，不动）
			GameStyle.label(name_lbl, 13, GameStyle.GOLD if group[0] == "类型" else GameStyle.JADE,
				0, GameStyle.INK, true)
			line.add_child(name_lbl)
			var desc_lbl := Label.new()
			# 阶梯文案由 WeaponData.SYNERGIES.effects 生成，与局内商店详情卡同一张表同一个口径
			desc_lbl.text = GameStyle.wrap_cjk(SynergyUI.synergy_desc(tag),
				GameStyle.body_font(), 12, TEXT_W - 74.0)
			GameStyle.label(desc_lbl, 12, GameStyle.PAPER_DIM)
			line.add_child(desc_lbl)
	return card

## 属性词条解读：现读 StatInfoData 的一句话说明
func _make_stat_guide_card() -> Control:
	var card := PanelContainer.new()
	var sb := GameStyle.block(GameStyle.NAVY2, GameStyle.SLANT_PLATE, Vector2(2, 3))
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	card.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	card.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = "◆ 属性词条 · 这是什么"
	GameStyle.label(title_lbl, 15, GameStyle.JADE_DK, 0, GameStyle.INK, true)
	vbox.add_child(title_lbl)

	var intro_lbl := Label.new()
	intro_lbl.text = GameStyle.wrap_cjk(
		"局内点右上「等级」打开属性面板，每条属性还能点按看结算公式与上限。以下是常用词条的一句话解读：",
		GameStyle.body_font(), 13, TEXT_W)
	GameStyle.label(intro_lbl, 13, GameStyle.PAPER_DIM)
	vbox.add_child(intro_lbl)

	for sid in ManualData.STAT_GUIDE_IDS:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		vbox.add_child(line)
		var name_lbl := Label.new()
		name_lbl.text = StatInfoData.title(sid)
		name_lbl.custom_minimum_size = Vector2(96, 0)
		GameStyle.label(name_lbl, 12, GameStyle.GOLD, 0, GameStyle.INK, true)
		line.add_child(name_lbl)
		var brief_lbl := Label.new()
		brief_lbl.text = GameStyle.wrap_cjk(StatInfoData.brief(sid), GameStyle.body_font(), 12, TEXT_W - 116.0)
		brief_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		GameStyle.label(brief_lbl, 12, GameStyle.PAPER_DIM)
		line.add_child(brief_lbl)
	return card

## 流派攻略卡
func _make_build_card(guide: Dictionary) -> Control:
	var card := PanelContainer.new()
	var sb := GameStyle.block(GameStyle.NAVY2, GameStyle.SLANT_PLATE, Vector2(2, 3))
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	sb.border_width_bottom = 4
	sb.border_color = GameStyle.GOLD
	GameStyle.register_theme_box(sb, &"border_color", &"main")
	card.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	card.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = "◆ 流派 · " + String(guide.get("name", ""))
	GameStyle.label(title_lbl, 15, GameStyle.GOLD, 0, GameStyle.INK, true)
	vbox.add_child(title_lbl)

	var wps: Array[String] = []
	for w in guide.get("weapons", []):
		wps.append(String(w))
	var rows := [
		["推荐角色", String(guide.get("cultivator", ""))],
		["核心武器", "、".join(wps)],
		["关键羁绊", String(guide.get("synergies", ""))],
		["加点顺序", String(guide.get("upgrades", ""))],
		["推荐道具", String(guide.get("items", ""))],
	]
	for r in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		vbox.add_child(line)
		var k_lbl := Label.new()
		k_lbl.text = String(r[0])
		k_lbl.custom_minimum_size = Vector2(72, 0)
		GameStyle.label(k_lbl, 12, GameStyle.GREY)
		line.add_child(k_lbl)
		var v_lbl := Label.new()
		v_lbl.text = String(r[1])
		GameStyle.label(v_lbl, 12, GameStyle.PAPER)
		line.add_child(v_lbl)

	var tips_lbl := Label.new()
	tips_lbl.text = GameStyle.wrap_cjk(String(guide.get("tips", "")), GameStyle.body_font(), 12, TEXT_W)
	GameStyle.label(tips_lbl, 12, GameStyle.PAPER_DIM)
	vbox.add_child(tips_lbl)
	return card
