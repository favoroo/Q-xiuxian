class_name AuthorPanel
extends BaseModalDialog

## 作者模式面板（仅 GameManager.author_mode 时由 HUD/商店/悟道顶栏打开）。
##
## 四个分页：
##   ◆ 状态：人物等级 / 跳关 / 金币
##   ◆ 战斗：无敌 / 一击必杀 / 时间加速 / 直接胜利·失败
##   ◆ 武器：全武器免费直购（点一次拿一件，满栏自动进背包）
##   ◆ 道具：全道具免费直购（灵兽并入此页，避免再开一页挤窄屏）
##
## 口径：
## - 打开即 `get_tree().paused = true`（继承 BaseModalDialog 的暂停式模态），关面板不主动解暂停：
##   战斗中它叠在 HUD 上，解暂停由玩家自己的暂停/继续路径负责；商店/悟道期间本来就在暂停。
##   为避免「战斗中关掉面板后整局卡住」，关闭时按打开前的暂停态还原。
## - 直购全部走 AuthorMode.grant，不扣金币；面板自带「金币 +1000 / +10000」供经济测试。
## - 所有按钮都走 GameStyle.button（唯一取色入口 + 统一点击音）。

const LEVEL_PRESETS: Array[int] = [1, 5, 10, 20, 30, 50]
const WAVE_PRESETS: Array[int] = [1, 5, 10, 15, 20]

var _was_paused_before_open: bool = false
## 关面板时是否强制保持暂停（直接胜利/失败后结算屏要靠树暂停冻结，不能被本面板解掉）
var _keep_paused_on_close: bool = false
## 关面板时是否强制解除暂停（跳关/本波直接结束：关闭动画要 0.12s，若按「打开前是暂停」
## 还原，新开的波会被这 0.12s 后的回调重新暂停住 —— 必须显式要求解暂停）
var _force_unpause_on_close: bool = false

# 状态页控件
var _level_value_lbl: Label
var _wave_value_lbl: Label
var _stones_value_lbl: Label

# 战斗页开关按钮
var _god_btn: Button
var _one_hit_btn: Button
var _speed_btn: Button

# 直购页
var _weapon_grid: GridContainer
var _item_grid: GridContainer
var _pet_grid: GridContainer
var _star_btn: Button
var _buy_hint_lbl: Label

func _get_title_text() -> String:
	return "作 者 模 式"

func _get_close_btn_text() -> String:
	return "返 回"

func _get_panel_size() -> Vector2:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0:
		vp = Vector2(960, 540)
	return Vector2(minf(900.0, vp.x - 40.0), minf(500.0, vp.y - 32.0))

func _get_panel_margins() -> Vector4:
	return Vector4(18, 12, 18, 12)

func _get_vbox_separation() -> int:
	return 8

func _get_tab_bar_separation() -> int:
	return 6

func _get_title_font_size() -> int:
	return 17

func _get_close_btn_min_size() -> Vector2:
	return Vector2(76, 32)

func _build_body(root_vbox: VBoxContainer) -> void:
	add_tab_button(0, "◆ 状态", 76.0)
	add_tab_button(1, "◆ 战斗", 76.0)
	add_tab_button(2, "◆ 武器", 76.0)
	add_tab_button(3, "◆ 道具", 76.0)

	var content_panel := PanelContainer.new()
	content_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb := GameStyle.outlined_panel(GameStyle.NAVY2, GameStyle.INK, 2, 0.0)
	sb.content_margin_left = 14.0
	sb.content_margin_top = 10.0
	sb.content_margin_right = 14.0
	sb.content_margin_bottom = 10.0
	content_panel.add_theme_stylebox_override("panel", sb)
	root_vbox.add_child(content_panel)

	_pages.append(_build_state_page(content_panel))
	_pages.append(_build_combat_page(content_panel))
	_pages.append(_build_weapon_page(content_panel))
	_pages.append(_build_item_page(content_panel))
	switch_tab(0)

func _on_opened() -> void:
	_keep_paused_on_close = false
	_force_unpause_on_close = false
	_was_paused_before_open = get_tree().paused
	get_tree().paused = true
	_refresh_state_labels()
	_refresh_combat_buttons()
	_rebuild_weapon_grid()
	_rebuild_item_grid()
	_rebuild_pet_grid()

func _on_closed() -> void:
	# 战斗中被 HUD 打开时，关面板要把暂停还回去；商店/悟道期间打开前本来就是暂停，保持。
	# 结算屏路径（直接胜利/失败）由 _keep_paused_on_close 钉住暂停，否则树一解暂停，
	# 结算对话框的入场动画与 GameOver 流程会被 WaveSpawner 抢跑。
	# 跳关/结束本波路径由 _force_unpause_on_close 强制解暂停（新波必须能跑起来）。
	if _keep_paused_on_close:
		get_tree().paused = true
	elif _force_unpause_on_close:
		get_tree().paused = false
	elif not _was_paused_before_open:
		get_tree().paused = false

# ---------------- 分页 1：状态 ----------------

func _build_state_page(parent: Control) -> Control:
	var scroll := _new_scroll(parent)
	var box := _new_scroll_vbox(scroll)

	box.add_child(_make_section_title("人物等级", GameStyle.GOLD))
	box.add_child(_make_hint("只改等级读数与升级门槛；上调的级数折成悟道点，回合末照常加点，属性与正常升级同源。下调不回收已获得属性。"))
	var lv_row := HFlowContainer.new()
	lv_row.add_theme_constant_override("h_separation", 8)
	lv_row.add_theme_constant_override("v_separation", 6)
	box.add_child(lv_row)
	_level_value_lbl = _make_value_label("Lv.1")
	lv_row.add_child(_level_value_lbl)
	lv_row.add_child(_make_button("－ 1", func(): _adjust_level(-1), 66))
	lv_row.add_child(_make_button("＋ 1", func(): _adjust_level(1), 66))
	for n in LEVEL_PRESETS:
		var target: int = n
		lv_row.add_child(_make_button("Lv.%d" % target, func(): _set_level_to(target), 64))

	box.add_child(_make_separator())
	box.add_child(_make_section_title("跳关", GameStyle.JADE))
	box.add_child(_make_hint("清掉场上敌人/宝箱/炮台/预警后直接开波。跳关不发回合末收益，方便定点测 Boss 与高波内容。"))
	var wave_row := HFlowContainer.new()
	wave_row.add_theme_constant_override("h_separation", 8)
	wave_row.add_theme_constant_override("v_separation", 6)
	box.add_child(wave_row)
	_wave_value_lbl = _make_value_label("第 1 波")
	wave_row.add_child(_wave_value_lbl)
	wave_row.add_child(_make_button("－ 1 波", func(): _jump_relative(-1), 72))
	wave_row.add_child(_make_button("＋ 1 波", func(): _jump_relative(1), 72))
	for n in WAVE_PRESETS:
		var target: int = n
		wave_row.add_child(_make_button("W%d" % target, func(): _jump_to(target), 56))

	box.add_child(_make_separator())
	box.add_child(_make_section_title("金币", GameStyle.GOLD))
	box.add_child(_make_hint("直接加金币，供商店价格/折扣/重掷等经济链路测试。"))
	var stone_row := HFlowContainer.new()
	stone_row.add_theme_constant_override("h_separation", 8)
	stone_row.add_theme_constant_override("v_separation", 6)
	box.add_child(stone_row)
	_stones_value_lbl = _make_value_label("0")
	stone_row.add_child(_stones_value_lbl)
	stone_row.add_child(_make_button("＋1 000", func(): _add_stones(1000), 84))
	stone_row.add_child(_make_button("＋10 000", func(): _add_stones(10000), 92))
	stone_row.add_child(_make_button("＋100 000", func(): _add_stones(100000), 100))

	GameStyle.swipeable(scroll)
	return scroll

func _adjust_level(delta: int) -> void:
	_set_level_to(GameManager.level + delta)

func _set_level_to(target: int) -> void:
	if not GameManager.run_started or GameManager.player == null:
		GameManager.announcement_triggered.emit("先开一局再调等级")
		return
	AuthorMode.set_level(GameManager, target)
	_refresh_state_labels()

func _jump_relative(delta: int) -> void:
	_jump_to(GameManager.wave_number + delta)

func _jump_to(target: int) -> void:
	if not GameManager.run_started or GameManager.player == null:
		GameManager.announcement_triggered.emit("先开一局再跳关")
		return
	if GameManager.wave_spawner == null or not GameManager.wave_spawner.has_method("jump_to_wave"):
		return
	# 跳关会开新波：面板自身要先收起，否则玩家看着面板、背后已经在刷怪。
	# 关闭动画 0.12s 后回调会按「打开前暂停态」还原，这里必须显式要求解暂停。
	_force_unpause_on_close = true
	close()
	GameManager.wave_spawner.jump_to_wave(target)

func _add_stones(amount: int) -> void:
	GameManager.add_spirit_stones(amount)
	GameManager.stats_updated.emit(GameManager.kills, GameManager.game_time, GameManager.spirit_stones)
	_refresh_state_labels()

func _refresh_state_labels() -> void:
	if _level_value_lbl != null:
		_level_value_lbl.text = "Lv.%d" % GameManager.level
	if _wave_value_lbl != null:
		_wave_value_lbl.text = "第 %d 波" % GameManager.wave_number
	if _stones_value_lbl != null:
		_stones_value_lbl.text = "%d 金币" % GameManager.spirit_stones

# ---------------- 分页 2：战斗 ----------------

func _build_combat_page(parent: Control) -> Control:
	var scroll := _new_scroll(parent)
	var box := _new_scroll_vbox(scroll)

	box.add_child(_make_section_title("战斗开关", GameStyle.GOLD))
	box.add_child(_make_hint("开关只作用于本局，关闭作者模式时自动全部复位。"))
	var row1 := HFlowContainer.new()
	row1.add_theme_constant_override("h_separation", 10)
	row1.add_theme_constant_override("v_separation", 6)
	box.add_child(row1)
	_god_btn = _make_button("无敌：关", func(): _toggle_god(), 150)
	row1.add_child(_god_btn)
	_one_hit_btn = _make_button("一击必杀：关", func(): _toggle_one_hit(), 168)
	row1.add_child(_one_hit_btn)
	_speed_btn = _make_button("时间：1x", func(): _cycle_speed(), 110)
	row1.add_child(_speed_btn)

	box.add_child(_make_separator())
	box.add_child(_make_section_title("结算", GameStyle.JADE))
	box.add_child(_make_hint("直接触发结算屏，测胜利/失败演出、成就弹窗与返回流程（作者模式下不记录生涯与成就）。"))
	var row2 := HFlowContainer.new()
	row2.add_theme_constant_override("h_separation", 10)
	row2.add_theme_constant_override("v_separation", 6)
	box.add_child(row2)
	row2.add_child(_make_button("直接胜利", func(): _force_end(true), 120))
	row2.add_child(_make_button("直接失败", func(): _force_end(false), 120))

	box.add_child(_make_separator())
	box.add_child(_make_section_title("其他快捷", GameStyle.JADE))
	var row3 := HFlowContainer.new()
	row3.add_theme_constant_override("h_separation", 10)
	row3.add_theme_constant_override("v_separation", 6)
	box.add_child(row3)
	row3.add_child(_make_button("补满生命", func(): _heal_full(), 110))
	row3.add_child(_make_button("本波直接结束", func(): _end_wave_now(), 130))
	row3.add_child(_make_button("金币 +10 000", func(): _add_stones(10000), 130))
	row3.add_child(_make_button("清空背包", func(): _clear_stash(), 110))

	GameStyle.swipeable(scroll)
	return scroll

func _toggle_god() -> void:
	AuthorMode.god_mode = not AuthorMode.god_mode
	_refresh_combat_buttons()

func _toggle_one_hit() -> void:
	AuthorMode.one_hit_kill = not AuthorMode.one_hit_kill
	_refresh_combat_buttons()

func _cycle_speed() -> void:
	AuthorMode.cycle_time_scale()
	_refresh_combat_buttons()

func _refresh_combat_buttons() -> void:
	if _god_btn != null:
		_style_toggle(_god_btn, "无敌", AuthorMode.god_mode)
	if _one_hit_btn != null:
		_style_toggle(_one_hit_btn, "一击必杀", AuthorMode.one_hit_kill)
	if _speed_btn != null:
		_speed_btn.text = "时间：%dx" % int(AuthorMode.time_scale)
		GameStyle.button(_speed_btn, GameStyle.GOLD if AuthorMode.time_scale > 1.0 else GameStyle.NAVY2,
			GameStyle.GOLD_EDGE, 13, GameStyle.INK_TEXT, 4.0, GameStyle.INK_TEXT)

func _style_toggle(btn: Button, label: String, on: bool) -> void:
	btn.text = "%s：%s" % [label, "开" if on else "关"]
	GameStyle.button(btn, GameStyle.GOLD if on else GameStyle.NAVY2,
		GameStyle.GOLD_EDGE, 13, GameStyle.INK_TEXT, 4.0, GameStyle.INK_TEXT)

func _force_end(victory: bool) -> void:
	_keep_paused_on_close = true
	close()
	GameManager.trigger_game_over(victory)

## 清空背包（上阵不动）：测试换装/合成时不必一件件点出售
func _clear_stash() -> void:
	if GameManager.stash.is_empty():
		GameManager.announcement_triggered.emit("背包已经是空的")
		return
	GameManager.stash.clear()
	GameManager.notify_weapons_updated(GameManager.get_weapons_summary())
	GameManager.announcement_triggered.emit("背包已清空")
	AudioManager.play_sfx("sell", 0.9)

func _heal_full() -> void:
	var p = GameManager.player
	if p != null and is_instance_valid(p):
		p.heal(p.max_health)

func _end_wave_now() -> void:
	if GameManager.wave_spawner == null:
		return
	# end_wave 进 CLEARING 靠 _process 走倒计时，树必须是解暂停态
	_force_unpause_on_close = true
	close()
	GameManager.wave_spawner.end_wave()

# ---------------- 分页 3：武器直购 ----------------

func _build_weapon_page(parent: Control) -> Control:
	var scroll := _new_scroll(parent)
	var box := _new_scroll_vbox(scroll)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	head.add_child(_make_hint("点卡片免费获得一件（上阵满则自动进背包）。"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	_star_btn = _make_button("星级：1 星", func(): _cycle_star(), 104)
	head.add_child(_star_btn)
	_buy_hint_lbl = _make_value_label("")
	head.add_child(_buy_hint_lbl)

	_weapon_grid = GridContainer.new()
	_weapon_grid.columns = 7
	_weapon_grid.add_theme_constant_override("h_separation", 6)
	_weapon_grid.add_theme_constant_override("v_separation", 6)
	box.add_child(_weapon_grid)

	GameStyle.swipeable(scroll)
	return scroll

func _cycle_star() -> void:
	AuthorMode.grant_star = AuthorMode.grant_star % WeaponData.MAX_STAR + 1
	if _star_btn != null:
		_star_btn.text = "星级：%d 星" % AuthorMode.grant_star

func _rebuild_weapon_grid() -> void:
	if _weapon_grid == null:
		return
	for c in _weapon_grid.get_children():
		c.queue_free()
	for wid in WeaponData.DEFS.keys():
		var def: Dictionary = WeaponData.DEFS[wid]
		_weapon_grid.add_child(_make_grant_card(
			String(def.get("icon", "")), String(def.get("name", wid)),
			"weapon", String(wid)))
	# 卡是 PanelContainer（默认 STOP）：重建后必须再降一遍，否则整页只能从缝隙里拖动
	GameStyle.swipeable(_weapon_grid)

# ---------------- 分页 4：道具 + 灵兽直购 ----------------

func _build_item_page(parent: Control) -> Control:
	var scroll := _new_scroll(parent)
	var box := _new_scroll_vbox(scroll)

	box.add_child(_make_section_title("道具（免费直购）", GameStyle.GOLD))
	box.add_child(_make_hint("点一次拿一件，立即生效。unique 道具本局限购一件，重复点会被拒绝。"))
	_item_grid = GridContainer.new()
	_item_grid.columns = 7
	_item_grid.add_theme_constant_override("h_separation", 6)
	_item_grid.add_theme_constant_override("v_separation", 6)
	box.add_child(_item_grid)

	box.add_child(_make_separator())
	box.add_child(_make_section_title("灵兽（免费直购）", GameStyle.JADE))
	box.add_child(_make_hint("受灵兽栏上限约束；栏满先卖掉再点。"))
	_pet_grid = GridContainer.new()
	_pet_grid.columns = 7
	_pet_grid.add_theme_constant_override("h_separation", 6)
	_pet_grid.add_theme_constant_override("v_separation", 6)
	box.add_child(_pet_grid)

	GameStyle.swipeable(scroll)
	return scroll

func _rebuild_item_grid() -> void:
	if _item_grid == null:
		return
	for c in _item_grid.get_children():
		c.queue_free()
	for iid in ItemData.DEFS.keys():
		var def: Dictionary = ItemData.DEFS[iid]
		_item_grid.add_child(_make_grant_card(
			String(def.get("icon", "")), String(def.get("name", iid)),
			"item", String(iid)))
	GameStyle.swipeable(_item_grid)

func _rebuild_pet_grid() -> void:
	if _pet_grid == null:
		return
	for c in _pet_grid.get_children():
		c.queue_free()
	for pid in PetData.DEFS.keys():
		var def: Dictionary = PetData.DEFS[pid]
		# 灵兽没有位图图标（战斗里是程序化光灵）：用它的主体色画一颗圆点占位
		_pet_grid.add_child(_make_grant_card(
			"", String(def.get("name", pid)), "pet", String(pid),
			def.get("color", GameStyle.GOLD)))
	GameStyle.swipeable(_pet_grid)

## 直购小卡：图标 + 名字 + 品阶/价格角标。点按即 grant（免费）。
## icon 为空时用 tint 画一颗纯色圆点（灵兽没有位图图标）。
func _make_grant_card(icon: String, name: String, kind: String, id: String,
		tint: Color = Color(-1, -1, -1, -1)) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(112, 0)
	var sb := GameStyle.block(GameStyle.NAVY2, GameStyle.SLANT_PLATE, Vector2(2, 3))
	sb.content_margin_left = 6.0
	sb.content_margin_right = 6.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	card.add_theme_stylebox_override("panel", sb)
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	var icon_center := CenterContainer.new()
	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(40, 40)
	icon_box.add_theme_stylebox_override("panel", GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 1, 0.0))
	if icon.is_empty() and tint.a > 0.0:
		var dot := Control.new()
		dot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.draw.connect(func() -> void:
			var c := dot.size * 0.5
			dot.draw_circle(c, minf(dot.size.x, dot.size.y) * 0.30, tint)
			dot.draw_circle(c, minf(dot.size.x, dot.size.y) * 0.15, Color(1, 1, 1, 0.55))
		)
		icon_box.add_child(dot)
	else:
		var tex := GameStyle.icon_texture_rect(icon, Vector2(34, 34))
		tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tex.offset_left = 3
		tex.offset_top = 3
		tex.offset_right = -3
		tex.offset_bottom = -3
		icon_box.add_child(tex)
	icon_center.add_child(icon_box)
	vbox.add_child(icon_center)

	var name_lbl := Label.new()
	name_lbl.text = name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	GameStyle.label(name_lbl, 11, GameStyle.PAPER, 0, GameStyle.INK, true)
	vbox.add_child(name_lbl)

	GameStyle.tap(card, func() -> void: _grant(kind, id))
	GameStyle.hotzone(card)
	return card

func _grant(kind: String, id: String) -> void:
	var ok := AuthorMode.grant(GameManager, kind, id, AuthorMode.grant_star)
	if ok:
		if _buy_hint_lbl != null:
			_buy_hint_lbl.text = "已获得"
		AudioManager.play_sfx("shop_buy", 1.0)
	else:
		if _buy_hint_lbl != null:
			_buy_hint_lbl.text = "栏位已满或限购"
		AudioManager.play_sfx("ui_error", 0.9)

# ---------------- 通用小件 ----------------

func _new_scroll(parent: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	GameStyle.scrollable(scroll)
	parent.add_child(scroll)
	return scroll

func _new_scroll_vbox(scroll: ScrollContainer) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	return box

func _make_section_title(text: String, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = "── %s ──" % text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	GameStyle.label(lbl, 14, color, 0, GameStyle.INK, true)
	return lbl

func _make_hint(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = GameStyle.wrap_cjk(text, GameStyle.body_font(), 11, 720.0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	GameStyle.label(lbl, 11, GameStyle.PAPER_DIM)
	return lbl

func _make_value_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size = Vector2(104, 0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	GameStyle.label(lbl, 14, GameStyle.PAPER, 0, GameStyle.INK, true)
	return lbl

func _make_button(text: String, cb: Callable, min_w: float) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(min_w, 32)
	btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(btn, GameStyle.NAVY2, GameStyle.GOLD, 13, GameStyle.PAPER, 4.0, GameStyle.INK_TEXT)
	btn.pressed.connect(cb)
	return btn

func _make_separator() -> Control:
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(0, 1)
	line.color = GameStyle.with_alpha(GameStyle.PAPER, 0.12)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line
