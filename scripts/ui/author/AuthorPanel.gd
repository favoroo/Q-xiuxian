class_name AuthorPanel
extends BaseModalDialog

## 作者模式面板（仅 GameManager.author_mode 时由 HUD/商店/悟道顶栏打开）。
##
## 五个分页：
##   ◆ 状态：人物等级 / 跳关 / 金币
##   ◆ 战斗：无敌 / 一击必杀 / 时间加速 / 直接结算
##   ◆ 武器：全武器图鉴式浏览（类型/五行筛选 + 卡面三签），点卡开详情窗、窗内按星免费购买（1 ~ MAX_STAR）
##   ◆ 道具：全道具 + 灵兽，点卡开详情窗、窗内免费购买
##   ◆ 商店：完整商店（AuthorShopView）
##   ◆ 悟道：普通悟道 + 超级悟道免费加/删测试台（AuthorAllocView，删除走从初值重放）
##
## 口径：
## - 打开即 `get_tree().paused = true`（继承 BaseModalDialog 的暂停式模态），关面板不主动解暂停：
##   战斗中它叠在 HUD 上，解暂停由玩家自己的暂停/继续路径负责；商店/悟道期间本来就在暂停。
##   为避免「战斗中关掉面板后整局卡住」，关闭时按打开前的暂停态还原。
## - 所有条目「点卡 = 看详情」，只有详情窗里的购买键才真正发货（2026-10-22 用户口径：
##   原先点一下直接买，容易点错；现在与图鉴一样先看信息再决定）。
## - 直购全部走 AuthorMode.grant，不扣金币；面板自带「金币 +1000 / +10000」供经济测试。
## - 购买成功发 inventory_changed：商店开着时由 Main 转去 shop.refresh(false)，
##   否则买完的东西要等下一波才出现在陈列行里（2026-10-22 用户报的 bug）。
## - 金币/等级/生命这类共享读数改动后发 state_changed：商店与悟道面板开着时由 Main
##   当场重画（2026-10-22 用户报：商店里点金币 +10 000 要出战后才生效）。
## - 所有按钮都走 GameStyle.button（唯一取色入口 + 统一点击音）。

const LEVEL_PRESETS: Array[int] = [1, 5, 10, 20, 30, 50]
const WAVE_PRESETS: Array[int] = [1, 5, 10, 15, 20, 25, 30, 35, 40, 50]
## 条目卡宽与格缝（与 CodexCardFactory 同源）：列数按面板可用宽现算，
## 窄屏（720）落 3 列、桌面（900 面板）落 5 列，绝不把整排顶出面板
const CARD_W := CodexCardFactory.CARD_W
const GRID_GAP := 8

## 购买成功后发一次（kind = "weapon"/"item"/"pet"）：宿主据此刷新商店陈列行等只读视图
signal inventory_changed(kind: String)
## 改动面板外的共享读数后发一次（kind = "stones"/"level"/"hp"）：宿主据此刷新仍开着的
## 商店/悟道面板。原先只发 stats_updated（只有 HUD 在听），商店的「金币 N」与价格键
## 要等下一波重开才更新（2026-10-22 用户报：在商店里点金币 +10000 不即时生效）。
signal state_changed(kind: String)

var _was_paused_before_open: bool = false
## 关面板时是否强制保持暂停（直接结算后结算屏要靠树暂停冻结，不能被本面板解掉）
var _keep_paused_on_close: bool = false
## 关面板时是否强制解除暂停（跳关/本波直接结束：关闭动画要 0.12s，若按「打开前是暂停」
## 还原，新开的波会被这 0.12s 后的回调重新暂停住 —— 必须显式要求解暂停）
var _force_unpause_on_close: bool = false

# 状态页控件
var _level_value_lbl: Label
var _wave_value_lbl: Label
var _stones_value_lbl: Label
var _danger_value_lbl: Label

# 战斗页开关按钮
var _god_btn: Button
var _one_hit_btn: Button
var _speed_btn: Button

# 武器页：筛选状态（"" = 该行全部）与控件
var weapon_class_filter: String = ""
var weapon_element_filter: String = ""
var _filter_chips: Dictionary = {}
var _weapon_box: VBoxContainer

# 道具页
var _item_grid: GridContainer
var _pet_grid: GridContainer

# 商店页
var _shop_view: AuthorShopView = null

# 悟道页
var _alloc_view: AuthorAllocView = null

signal manual_requested(tag: String)

## 分页标题文案（新页追加在末尾；别动 0~4 的下标 —— _show_weapon_tag 与判据都按它跳页）
const TAB_LABELS: Array[String] = ["状态", "战斗", "武器", "道具", "商店", "悟道"]

func _get_title_text() -> String:
	return "作 者 模 式"

func _get_close_btn_text() -> String:
	return "返 回"

func _get_panel_size() -> Vector2:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0:
		vp = Vector2(960, 540)
	# 高按 ShopCardLayout 的面板呼吸量算（上下各 12），不再钉死 500：
	# 【◆ 商店】页要装下货架卡（960×540 下卡高 284）+ 陈列行，500 差一截，
	# 价格键会被挤出滚动视口（2026-10-25 探针：卡高 284 / 视口 247，得先滚才看得见价格）。
	return Vector2(minf(900.0, vp.x - 40.0),
			minf(vp.y - ShopCardLayout.PANEL_SCREEN_PAD_Y, 560.0))

func _get_panel_margins() -> Vector4:
	# 上下 12 → 10：省下的竖向预算给【◆ 商店】页的货架（960×540 下面板里每一格都要争）
	return Vector4(18, 10, 18, 10)

func _get_vbox_separation() -> int:
	return 6

func _get_tab_bar_separation() -> int:
	return 6

func _get_title_font_size() -> int:
	return 17

func _get_close_btn_min_size() -> Vector2:
	return Vector2(76, 32)

func _build_body(root_vbox: VBoxContainer) -> void:
	# tab 宽度按可用宽现算：6 个 tab 在 720 宽视口下用 76 会顶出面板、压到关闭键
	# （面板内宽 ~437，6×76+5×6=486 溢出）。桌面 960 仍是 76，窄屏自动收窄。
	var tab_w := _tab_width()
	for i in range(TAB_LABELS.size()):
		add_tab_button(i, "◆ %s" % TAB_LABELS[i], tab_w)

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
	_pages.append(_build_shop_page(content_panel))
	_pages.append(_build_alloc_page(content_panel))
	switch_tab(0)

## 六个 tab 均分「面板内宽 − 标题块实测宽 − 关闭键 − 顶部栏间距」，夹在 [60, 76]。
## 标题块宽度用 get_combined_minimum_size 实测（_build_modal_chrome 已把文案装好）。
func _tab_width() -> float:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0:
		vp = Vector2(960, 540)
	var inner := minf(900.0, vp.x - 40.0) - _get_panel_margins().x - _get_panel_margins().z
	var reserved := _title_box.get_combined_minimum_size().x + float(_get_close_btn_min_size().x) \
			+ 2.0 * float(_get_top_bar_separation())
	var avail := inner - reserved
	return clampf(floorf((avail - float(_get_tab_bar_separation()) * float(TAB_LABELS.size() - 1))
			/ float(TAB_LABELS.size())), 60.0, 76.0)

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
	if _shop_view != null:
		_shop_view.refresh(false)
	if _alloc_view != null:
		_alloc_view.refresh()

func _on_tab_switched(index: int) -> void:
	if index == 4 and _shop_view != null:
		_shop_view.refresh(false)
	if index == 5 and _alloc_view != null:
		_alloc_view.refresh()

func _on_closed() -> void:
	if _shop_view != null:
		DetailTip.close_all(_shop_view)
	if _alloc_view != null:
		DetailTip.close_all(_alloc_view)
	# 战斗中被 HUD 打开时，关面板要把暂停还回去；商店/悟道期间打开前本来就是暂停，保持。
	# 结算屏路径（直接结算）由 _keep_paused_on_close 钉住暂停，否则树一解暂停，
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
	box.add_child(_make_hint("清掉场上敌人/宝箱/炮台/预警后直接开波。跳关不发回合末收益，方便定点测 Boss 与深层内容（20 波以上即深层）。"))
	var wave_rel_row := HFlowContainer.new()
	wave_rel_row.add_theme_constant_override("h_separation", 8)
	wave_rel_row.add_theme_constant_override("v_separation", 6)
	box.add_child(wave_rel_row)
	_wave_value_lbl = _make_value_label("第 1 波")
	wave_rel_row.add_child(_wave_value_lbl)
	wave_rel_row.add_child(_make_button("－ 10 波", func(): _jump_relative(-10), 76))
	wave_rel_row.add_child(_make_button("－ 5 波", func(): _jump_relative(-5), 72))
	wave_rel_row.add_child(_make_button("－ 1 波", func(): _jump_relative(-1), 72))
	wave_rel_row.add_child(_make_button("＋ 1 波", func(): _jump_relative(1), 72))
	wave_rel_row.add_child(_make_button("＋ 5 波", func(): _jump_relative(5), 72))
	wave_rel_row.add_child(_make_button("＋ 10 波", func(): _jump_relative(10), 76))

	var wave_preset_row := HFlowContainer.new()
	wave_preset_row.add_theme_constant_override("h_separation", 8)
	wave_preset_row.add_theme_constant_override("v_separation", 6)
	box.add_child(wave_preset_row)
	for wave_target in WAVE_PRESETS:
		var target: int = wave_target
		wave_preset_row.add_child(_make_button("W%d" % target, func(): _jump_to(target), 56))

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

	box.add_child(_make_separator())
	box.add_child(_make_section_title("难度", GameStyle.BAD))
	box.add_child(_make_hint("实时切换普通(D0)与噩梦(D1)难度。噩梦模式自带迷雾视野限制、双Boss车轮战与强敌凶化。"))
	var danger_row := HFlowContainer.new()
	danger_row.add_theme_constant_override("h_separation", 8)
	danger_row.add_theme_constant_override("v_separation", 6)
	box.add_child(danger_row)
	_danger_value_lbl = _make_value_label("普通 (D0)")
	danger_row.add_child(_danger_value_lbl)
	danger_row.add_child(_make_button("切为「普通」", func(): _set_danger_to(0), 96))
	danger_row.add_child(_make_button("切为「噩梦」", func(): _set_danger_to(1), 96))
	danger_row.add_child(_make_button("开关迷雾", func(): _toggle_fog_preview(), 96))

	GameStyle.swipeable(scroll)
	return scroll

func _set_danger_to(d: int) -> void:
	GameManager.set_danger(d)
	_refresh_state_labels()
	GameManager.announcement_triggered.emit("已切换为难度「%s」" % ("噩梦" if d >= 1 else "普通"))

func _toggle_fog_preview() -> void:
	NightmareFogOverlay.force_fog_preview = not NightmareFogOverlay.force_fog_preview
	GameManager.danger_changed.emit(GameManager.danger_level)
	_refresh_state_labels()
	var txt := "迷雾视野已开启" if NightmareFogOverlay.force_fog_preview else "迷雾预览已关闭"
	GameManager.announcement_triggered.emit(txt)

func _adjust_level(delta: int) -> void:
	_set_level_to(GameManager.level + delta)

func _set_level_to(target: int) -> void:
	if not GameManager.run_started or GameManager.player == null:
		GameManager.announcement_triggered.emit("先开一局再调等级")
		return
	AuthorMode.set_level(GameManager, target)
	_refresh_state_labels()
	state_changed.emit("level")

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
	# 商店/悟道面板开着时，金币读数、价格键的「买得起/差 N」与刷新键的可用态都要当场重画
	state_changed.emit("stones")
	if _shop_view != null:
		_shop_view.refresh_readouts()

func _refresh_state_labels() -> void:
	if _level_value_lbl != null:
		_level_value_lbl.text = "Lv.%d" % GameManager.level
	if _wave_value_lbl != null:
		_wave_value_lbl.text = "第 %d 波" % GameManager.wave_number
	if _stones_value_lbl != null:
		_stones_value_lbl.text = "%d 金币" % GameManager.spirit_stones
	if _danger_value_lbl != null:
		var d_str := "噩梦 (D1)" if GameManager.danger_level >= 1 else "普通 (D0)"
		if NightmareFogOverlay.force_fog_preview:
			d_str += " · 迷雾强制开"
		_danger_value_lbl.text = d_str

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
	box.add_child(_make_hint("直接触发阵亡结算屏，测结算演出、成就弹窗与返回流程（作者模式下不记录生涯与成就）。"))
	var row2 := HFlowContainer.new()
	row2.add_theme_constant_override("h_separation", 10)
	row2.add_theme_constant_override("v_separation", 6)
	box.add_child(row2)
	row2.add_child(_make_button("直接结算", func(): _force_end(), 120))

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

func _force_end() -> void:
	_keep_paused_on_close = true
	# 商店开着时直接结算：商店是 UILayer 里排在结算屏之后的兄弟，不先收起会整块盖住
	# 结算屏（玩家只看到商店，以为「直接结算」没反应）。Main 接到这条把商店藏掉。
	state_changed.emit("game_over")
	close()
	GameManager.trigger_game_over()

## 清空背包（上阵不动）：测试换装/合成时不必一件件点出售
func _clear_stash() -> void:
	if GameManager.stash.is_empty():
		GameManager.announcement_triggered.emit("背包已经是空的")
		return
	GameManager.stash.clear()
	GameManager.notify_weapons_updated(GameManager.get_weapons_summary())
	# 商店开着时陈列行要当场收掉这些格子（原先只发 weapons_updated，商店不监听）
	inventory_changed.emit("weapon")
	if _shop_view != null:
		_shop_view.refresh_inventory()
	GameManager.announcement_triggered.emit("背包已清空")
	AudioManager.play_sfx("sell", 0.9)

func _heal_full() -> void:
	var p = GameManager.player
	if p != null and is_instance_valid(p):
		p.heal(p.max_health)
		# 商店顶栏的生命徽记与回复药卡「这一口回多少」都按当前血量现算：补满后必须重画
		state_changed.emit("hp")
		if _shop_view != null:
			_shop_view.refresh_readouts()

func _end_wave_now() -> void:
	if GameManager.wave_spawner == null:
		return
	# 只允许战斗中调用：商店/悟道期间 end_wave 会再发一次回合收益、把阶段打回 CLEARING，
	# 随后又重开一次商店（货架整批重 roll）—— 作者面板在这两屏也能打开，必须挡掉。
	var phase_val: Variant = GameManager.wave_spawner.get("phase")
	if phase_val != null and int(phase_val) != WaveSpawner.Phase.FIGHT:
		GameManager.announcement_triggered.emit("只在战斗中可结束本波")
		return
	# end_wave 进 CLEARING 靠 _process 走倒计时，树必须是解暂停态
	_force_unpause_on_close = true
	close()
	GameManager.wave_spawner.end_wave()

# ---------------- 分页 3：武器 ----------------

## 页结构：两行筛选 chips 钉在滚动区上方（选完流派只滚内容，筛选条不跑），
## 下面是滚动网格。筛选口径与图鉴完全一致：类型 × 五行两条线独立、同时选中取交集。
func _build_weapon_page(parent: Control) -> Control:
	var page := VBoxContainer.new()
	page.name = "WeaponsPage"
	page.add_theme_constant_override("separation", 6)
	parent.add_child(page)

	page.add_child(_build_filter_row("class", "类型", WeaponData.CLASSES))
	page.add_child(_build_filter_row("element", "元素", WeaponData.ELEMENTS))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	GameStyle.scrollable(scroll)
	page.add_child(scroll)

	_weapon_box = VBoxContainer.new()
	_weapon_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weapon_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_weapon_box)
	return page

func _build_filter_row(group: String, group_label: String, tags: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var g_lbl := Label.new()
	g_lbl.text = group_label
	GameStyle.label(g_lbl, 12, GameStyle.GREY)
	row.add_child(g_lbl)
	row.add_child(_make_filter_chip(group, "", "全部"))
	for tag in tags:
		row.add_child(_make_filter_chip(group, String(tag),
			String(WeaponData.SYNERGIES.get(tag, {}).get("name", tag))))
	return row

func _make_filter_chip(group: String, tag: String, text: String) -> Label:
	var chip_lbl := Label.new()
	chip_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	chip_lbl.text = " %s " % text
	chip_lbl.set_meta("filter_tag", tag)
	chip_lbl.set_meta("filter_group", group)
	# 两行各有一枚「全部」（tag 都是 ""），字典键按行分开存，否则后建的会覆盖前一枚
	GameStyle.tap(chip_lbl, func() -> void: _on_filter_chip_tapped(group, tag))
	_filter_chips[tag if tag != "" else "all_" + group] = chip_lbl
	_restyle_filter_chips()
	return chip_lbl

## 点 chip：本行内切换；再点已选中的（含「全部」）即清空本行，另一行保持不动。
func _on_filter_chip_tapped(group: String, tag: String) -> void:
	var cur := weapon_class_filter if group == "class" else weapon_element_filter
	var next := "" if String(tag) == cur else String(tag)
	if group == "class":
		weapon_class_filter = next
	else:
		weapon_element_filter = next
	_restyle_filter_chips()
	_rebuild_weapon_grid()

## 选中主蓝底墨字、未选灰蓝底暗字，与图鉴筛选条同一套语言
func _restyle_filter_chips() -> void:
	for key in _filter_chips.keys():
		var chip_lbl: Label = _filter_chips[key]
		if not is_instance_valid(chip_lbl):
			continue
		var group := String(chip_lbl.get_meta("filter_group", "class"))
		var cur := weapon_class_filter if group == "class" else weapon_element_filter
		if String(chip_lbl.get_meta("filter_tag", "")) == cur:
			chip_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.GOLD))
			GameStyle.label(chip_lbl, 12, GameStyle.INK_TEXT, 0, GameStyle.INK, true)
		else:
			chip_lbl.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.NAVY2))
			GameStyle.label(chip_lbl, 12, GameStyle.PAPER_DIM)

func _rebuild_weapon_grid() -> void:
	if _weapon_box == null:
		return
	for c in _weapon_box.get_children():
		c.queue_free()
	_weapon_box.add_child(_make_hint("点卡片查看详情，在弹窗里选星级免费获得（上阵满则自动进背包）。类型与元素两条筛选可同时选中，取交集。"))

	var cls_tag := weapon_class_filter
	var elem_tag := weapon_element_filter
	if cls_tag == "" and elem_tag == "":
		for elem in WeaponData.ELEMENTS:
			_weapon_box.add_child(_make_group_header(
				"── %s行武器 ──" % String(StatInfoData.ELEMENT_NAMES.get(elem, elem)),
				GameStyle.ELEMENT_COLORS.get(elem, GameStyle.PAPER)))
			_weapon_box.add_child(_make_weapon_grid(func(wid: String) -> bool:
				return String(elem) in WeaponData.tags_of(wid)))
	else:
		var keep := func(wid: String) -> bool:
			var tags := WeaponData.tags_of(wid)
			if cls_tag != "" and not (cls_tag in tags):
				return false
			if elem_tag != "" and not (elem_tag in tags):
				return false
			return true
		var count := 0
		for wid in WeaponData.DEFS.keys():
			if WeaponData.DEFS[wid].has("tags") and bool(keep.call(String(wid))):
				count += 1
		var head_col: Color = GameStyle.GOLD
		if elem_tag != "":
			head_col = GameStyle.ELEMENT_COLORS.get(elem_tag, GameStyle.GOLD)
		_weapon_box.add_child(_make_group_header("── %s · %d 把 ──" % [_filter_title(cls_tag, elem_tag), count], head_col))
		if count == 0:
			_weapon_box.add_child(CodexCardFactory.make_text_card("没有匹配的武器",
				"「%s」里没有同时满足的武器。点上方「全部」放宽其中一条筛选。" % _filter_title(cls_tag, elem_tag),
				_content_w() - 12.0))
		else:
			_weapon_box.add_child(_make_weapon_grid(keep))
	# 卡是 PanelContainer（默认 STOP）：整页建完必须再降一遍，否则整页只能从缝隙里拖动
	GameStyle.swipeable(_weapon_box)

func _filter_title(cls_tag: String, elem_tag: String) -> String:
	var parts: Array[String] = []
	for tag in [cls_tag, elem_tag]:
		var t := String(tag)
		if t != "":
			parts.append(String(WeaponData.SYNERGIES.get(t, {}).get("name", t)))
	return " · ".join(parts)

func _make_group_header(text: String, color: Color) -> Label:
	var header := Label.new()
	header.text = text
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameStyle.label(header, 13, color, 0, GameStyle.INK, true)
	return header

func _make_weapon_grid(keep: Callable) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = _grid_cols()
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for wid in WeaponData.DEFS.keys():
		var def: Dictionary = WeaponData.DEFS[wid]
		if not def.has("tags"):
			continue
		if not bool(keep.call(String(wid))):
			continue
		grid.add_child(_make_weapon_card(String(wid), def))
	return grid

## 武器卡：与图鉴同一张卡（三签 = 攻击方式 + 器类 + 五行，关键数值行），
## 只是点按后弹的是「带购买键」的详情窗。
func _make_weapon_card(wid: String, def: Dictionary) -> PanelContainer:
	var stat_line := WeaponCodexBuilder.STAT_LINE_FMT % [
		int(def.get("damage", 0)),
		String.num(float(def.get("cooldown", 1.0)), 2),
		int(def.get("price", 0)),
	]
	var card := CodexCardFactory.make_entry_card(
		String(def.get("icon", "")), String(def.get("name", wid)),
		"", GameStyle.PAPER_DIM,
		func(anchor: Control): _open_weapon_tip(wid, anchor),
		stat_line, WeaponCodexBuilder.card_chips(wid, def))
	card.set_meta("wid", wid)
	# 元素件 = 图标框那一圈暖橙红描边（图鉴与商店/属性面板同一口径）
	var icon_tex := card.get_meta("icon_tex") as TextureRect
	if icon_tex != null and GameStyle.is_elemental(wid):
		var icon_box := icon_tex.get_parent() as Control
		if icon_box != null:
			icon_box.add_theme_stylebox_override("panel",
					GameStyle.outlined_panel(GameStyle.INK, GameStyle.ELEMENT, 1, 0.0))
	return card

func _open_weapon_tip(wid: String, anchor: Control) -> void:
	var payload := CodexTipData.weapon_payload(wid, "作者模式：免费获得，不扣金币，也不写存档")
	if payload.is_empty():
		return
	# 每个星级一颗键：点哪颗就按哪一星发货（2026-10-22 用户口径）。
	# 键数按 WeaponData.MAX_STAR 现算 —— 2026-10-24 加 ★4 时这里原先写死三颗，
	# 面板上就永远买不到新档；升档只改 MAX_STAR，这一排自己跟。
	var row: Array = []
	for s in range(1, WeaponData.MAX_STAR + 1):
		var want: int = s
		var is_top := want >= WeaponData.MAX_STAR
		row.append({
			"text": "买 %d 星" % want,
			# 顶档键走 ★4 霓虹青（与 HUD/商店槽位的极境描边同一副色），一眼看出这是最高档
			"color": GameStyle.STAR4_NEON if is_top else GameStyle.JADE,
			"edge_color": GameStyle.STAR4_NEON_EDGE if is_top else GameStyle.JADE_EDGE,
			"text_color": GameStyle.INK_TEXT,
			"keep_open": true,
			"callback": func() -> void: _buy_weapon(wid, want),
		})
	payload["actions"] = [row]
	DetailTip.show_over(self, anchor, payload)

func _buy_weapon(wid: String, star: int) -> void:
	_grant("weapon", wid, star)

# ---------------- 分页 4：道具 + 灵兽 ----------------

func _build_item_page(parent: Control) -> Control:
	var scroll := _new_scroll(parent)
	var box := _new_scroll_vbox(scroll)

	box.add_child(_make_section_title("道具", GameStyle.GOLD))
	box.add_child(_make_hint("点卡片查看效果与入手价，在弹窗里免费购买。部分道具本局限购一件。"))
	_item_grid = GridContainer.new()
	_item_grid.columns = _grid_cols()
	_item_grid.add_theme_constant_override("h_separation", 8)
	_item_grid.add_theme_constant_override("v_separation", 8)
	box.add_child(_item_grid)

	box.add_child(_make_separator())
	box.add_child(_make_section_title("灵兽", GameStyle.JADE))
	box.add_child(_make_hint("点卡片查看助战技能，在弹窗里免费购买。受灵兽栏上限约束，栏满先卖掉再买。"))
	_pet_grid = GridContainer.new()
	_pet_grid.columns = _grid_cols()
	_pet_grid.add_theme_constant_override("h_separation", 8)
	_pet_grid.add_theme_constant_override("v_separation", 8)
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
		var tier_num := int(def.get("tier", 1))
		var tier_col := ItemData.tier_color(tier_num)
		var card := CodexCardFactory.make_entry_card(
			String(def.get("icon", "")), String(def.get("name", iid)),
			"", GameStyle.PAPER_DIM,
			func(anchor: Control): _open_item_tip(iid, anchor),
			"", [[ItemData.tier_label(tier_num), tier_col, GameStyle.on_face_text(tier_col)]])
		card.set_meta("iid", iid)
		_item_grid.add_child(card)
	GameStyle.swipeable(_item_grid)

func _rebuild_pet_grid() -> void:
	if _pet_grid == null:
		return
	for c in _pet_grid.get_children():
		c.queue_free()
	for pid in PetData.DEFS.keys():
		var def: Dictionary = PetData.DEFS[pid]
		var p_col: Color = def.get("color", GameStyle.GOLD)
		var role_name := String(PetData.ROLES.get(String(def.get("role", "attack")), "助战"))
		var card := CodexCardFactory.make_entry_card(
			"", String(def.get("name", pid)),
			"", GameStyle.PAPER_DIM,
			func(anchor: Control): _open_pet_tip(pid, anchor),
			"%d金币 · %.1f秒" % [int(def.get("base_price", 0)), float(def.get("base_cooldown", 1.0))],
			[[role_name, p_col, GameStyle.on_face_text(p_col)]],
			p_col)
		card.set_meta("pid", pid)
		_pet_grid.add_child(card)
	GameStyle.swipeable(_pet_grid)

func _open_item_tip(iid: String, anchor: Control) -> void:
	var payload := CodexTipData.item_payload(iid, "作者模式：免费获得，不扣金币，也不写存档")
	if payload.is_empty():
		return
	payload["actions"] = [[{
		"text": "免费获得",
		"color": GameStyle.JADE, "edge_color": GameStyle.JADE_EDGE, "text_color": GameStyle.INK_TEXT,
		"callback": func() -> void: _grant("item", iid),
	}]]
	DetailTip.show_over(self, anchor, payload)

func _open_pet_tip(pid: String, anchor: Control) -> void:
	var payload := CodexTipData.pet_payload(pid, "作者模式：免费获得，不扣金币，也不写存档")
	if payload.is_empty():
		return
	payload["actions"] = [[{
		"text": "免费获得",
		"color": GameStyle.JADE, "edge_color": GameStyle.JADE_EDGE, "text_color": GameStyle.INK_TEXT,
		"callback": func() -> void: _grant("pet", pid),
	}]]
	DetailTip.show_over(self, anchor, payload)

## 发货：成功才发 inventory_changed（商店开着时宿主据此重铺陈列行）
func _grant(kind: String, id: String, star: int = 1) -> void:
	var ok := AuthorMode.grant(GameManager, kind, id, star)
	if ok:
		inventory_changed.emit(kind)
		if _shop_view != null:
			_shop_view.refresh_inventory()
	else:
		AudioManager.play_sfx("ui_error", 0.9)
		match kind:
			"weapon":
				GameManager.announcement_triggered.emit("上阵与背包都满了")
			"item":
				GameManager.announcement_triggered.emit("这件道具本局限购一件")
			"pet":
				GameManager.announcement_triggered.emit("灵兽栏已满或已持有")

# ---------------- 分页 5：商店 ----------------

func _build_shop_page(parent: Control) -> Control:
	_shop_view = AuthorShopView.new(self)
	_shop_view.state_changed.connect(func(k: String) -> void: state_changed.emit(k))
	_shop_view.inventory_changed.connect(func(k: String) -> void: inventory_changed.emit(k))
	# 「查看该流派武器」：面板自己就是图鉴，直接切到◆武器页并按这一路筛选 ——
	# 不往 Main 发 manual_requested 去叠一层 ManualDialog：那会让作者面板背后再压一个
	# 全屏模态，关图鉴后还得记着回到第几页（2026-10-25 探针发现这条信号原先没人接，点了没反应）。
	# 仍然照发 manual_requested，外部（Main / 判据）想接就有得接。
	_shop_view.manual_requested.connect(func(tag: String) -> void:
		manual_requested.emit(tag)
		_show_weapon_tag(tag)
	)
	parent.add_child(_shop_view)
	return _shop_view

# ---------------- 分页 6：悟道 ----------------

## 悟道加点测试台：免费加/删普通与超级悟道，删除由 AuthorStatRebuild 从初值重放属性层。
## 加删后发 state_changed("alloc")：Main 转去刷新开着的悟道/超级悟道面板（层数角标）与商店读数。
func _build_alloc_page(parent: Control) -> Control:
	_alloc_view = AuthorAllocView.new(self)
	_alloc_view.state_changed.connect(func(k: String) -> void: state_changed.emit(k))
	parent.add_child(_alloc_view)
	return _alloc_view

## 切到◆武器页并预选一路筛选：类型标签走类型行、五行标签走五行行（与图鉴同一套口径）
func _show_weapon_tag(tag: String) -> void:
	var t := String(tag)
	if t in WeaponData.CLASSES:
		weapon_class_filter = t
		weapon_element_filter = ""
	elif t in WeaponData.ELEMENTS:
		weapon_class_filter = ""
		weapon_element_filter = t
	else:
		weapon_class_filter = ""
		weapon_element_filter = ""
	_restyle_filter_chips()
	_rebuild_weapon_grid()
	switch_tab(2)

# ---------------- 通用小件 ----------------

## 面板内容可用宽：面板宽（随屏收窄）− 面板内边距 36 − 内容面板内边距 28。
## 折行文案必须按这个宽度预切，写死 720 在 720 宽屏上会把面板顶宽。
func _content_w() -> float:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0:
		vp = Vector2(960, 540)
	return maxf(240.0, minf(900.0, vp.x - 40.0) - 64.0)

## 网格列数：内容宽内摆得下几张 148 卡就几列（至少 2 列）
func _grid_cols() -> int:
	return maxi(2, int(floor((_content_w() + GRID_GAP) / (CARD_W + GRID_GAP))))

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
	lbl.text = GameStyle.wrap_cjk(text, GameStyle.body_font(), 11, _content_w() - 12.0)
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
