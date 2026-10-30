extends Node

## 首页噩梦模式判据（2026-10-30 精简口径）：
##   ① 两档难度共用同一套首页配色 —— 切到噩梦后**逐件与普通态完全一致**
##      （大卡 = 主题色、四卡 = 点缀黄/增益绿/纸白/元素橙、标题 = 墨字、角签各随本卡、
##        舞台底 = 纯黑、chip/徽章/角落按钮全不动），这条是「噩梦零换肤」的护栏；
##   ② 首页不挂血朱画框 / 整屏迷雾（当天那两件已撤掉，节点名都不许存在）；
##   ③ 唯一的难度差异落在流星雨：nightmare 权重置 1 且整盘配色转血红（红通道压过绿蓝）；
##   ④ 噩梦态里换主题色，Hero 大卡跟着主题色走（不被笔误钉成暗色）；
##   ⑤ 同值重发的 danger_changed（作者面板迷雾预览）不打第二次扫屏音效；
##   ⑥ 切回普通照样可逆。
##
## 运行: godot --headless --path . res://tests/NightmareMenuCheck.tscn
## 说明: headless 下 StartMenu 不建流星雨（DisplayServer 判定），所以流星配色在 ③ 里
##       单独装一层真 MenuMeteorShower 探针来量；观感由 tests/StartMenuTagPreview.tscn 出图验收。

const EPS := 0.004

var _c := TestCheck.new()
var _menu: StartMenu

func _ready() -> void:
	_c.set_min_checks(30)
	_menu = load("res://scenes/ui/StartMenu.tscn").instantiate()
	add_child(_menu)
	_menu.open()
	await get_tree().process_frame

	# ① 普通态基线
	_check_palette("初始（普通）", false)

	# ② 进噩梦：判据环境没有真实生涯进度，先在进程内把「已破普通」补上（不落盘）
	#    —— set_danger 会按 max_danger_unlocked 夹位，不补就永远只能停在 0
	var saved_best := int(GameManager.career_stats.get("best_danger_cleared", -1))
	GameManager.career_stats["best_danger_cleared"] = 0
	AudioManager.begin_sfx_capture()
	GameManager.set_danger(1)
	var enter_cap := AudioManager.end_sfx_capture()
	_c.check(_has_key(enter_cap, "boss_raid"), "进噩梦打一记魔君低吼（boss_raid）")
	await get_tree().process_frame

	# ③ 噩梦态：配色逐件与普通态一致（零换肤）
	_check_palette("噩梦（零换肤）", true)
	_c.check(_is_night(), "噩梦态 _is_night() 为真（流星走血红）")
	_c.check(_menu.get_node_or_null("MenuNightmareChrome") == null, "噩梦态不挂血朱画框")
	_c.check(_menu.get_node_or_null("MenuNightmareFog") == null, "噩梦态不挂整屏迷雾")

	# ④ 噩梦态里换主题色：Hero 大卡跟随主题色刷新
	var saved_theme := SettingsManager.theme_color()
	GameStyle.apply_theme_color(&"pink")
	SettingsManager.theme_color_changed.emit(&"pink")
	await get_tree().process_frame
	_c.check(_same(_block_bg(_menu._hero_card), GameStyle.GOLD),
		"噩梦态换主题色后 Hero 大卡跟随主题色")
	GameStyle.apply_theme_color(saved_theme)
	SettingsManager.theme_color_changed.emit(saved_theme)
	await get_tree().process_frame
	_c.check(_same(_block_bg(_menu._hero_card), GameStyle.GOLD),
		"主题色还原后 Hero 大卡仍是主题色")

	# ⑤ 同值重发（作者面板迷雾预览会这么干）：不该再打人声/扫屏
	AudioManager.begin_sfx_capture()
	GameManager.danger_changed.emit(1)
	var dup_cap := AudioManager.end_sfx_capture()
	_c.check(dup_cap.is_empty(), "同值重发 danger_changed 不打音效")

	# ⑥ 回普通：逐件还原
	AudioManager.begin_sfx_capture()
	GameManager.set_danger(0)
	var exit_cap := AudioManager.end_sfx_capture()
	_c.check(_has_key(exit_cap, "ui_confirm"), "回普通打一声轻确认（ui_confirm）")
	await get_tree().process_frame
	_check_palette("切回普通", false)
	_c.check(not _is_night(), "切回普通后 _is_night() 归假")

	# ⑦ 流星雨探针：这是全首页唯一跟难度走的东西 —— 噩梦整盘转血红，回普通复原
	var shower := MenuMeteorShower.install(_menu)
	_c.check(not shower._night > 0.001, "流星雨默认为普通天象（night = 0）")
	shower.set_nightmare(true, false)
	_c.check(absf(shower._night - 1.0) < 0.01, "切噩梦后流星 nightmare 权重置 1.0")
	_c.check(_all_blood_red(shower._palette()), "噩梦态流星整盘转血红（红通道压过绿蓝）")
	_c.check(_all_blood_red(shower._star_palette()), "噩梦态星屑同调转血红")
	shower.set_nightmare(false, false)
	_c.check(absf(shower._night) < 0.01, "切回普通后流星 nightmare 权重归 0")
	_c.check(not _all_blood_red(shower._palette()), "普通态流星恢复纸白/主题色（非全红）")
	shower.queue_free()

	GameManager.career_stats["best_danger_cleared"] = saved_best
	if _c.report("NIGHTMARE_MENU_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

# ---------------- 逐件核对 ----------------

## 两档难度共用同一份配色：`night` 只用来决定「哪一档 chip 是选中态」，色值全部一致。
func _check_palette(tag: String, night: bool) -> void:
	var faces := [GameStyle.JADE, GameStyle.GOOD, GameStyle.NAVY2, GameStyle.ELEMENT]
	var marks := [GameStyle.JADE, GameStyle.GOOD, GameStyle.GOLD, GameStyle.ELEMENT]
	_c.check(_same(_block_bg(_menu._hero_card), GameStyle.GOLD), "%s：Hero 大卡 = 主题色" % tag)
	_c.check(_same(_label_col(_menu._hero_title), GameStyle.INK_TEXT), "%s：大标题 = 墨字" % tag)
	_c.check(_same(_btn_bg(_menu._hero_start_btn), GameStyle.JADE), "%s：开始游戏键 = 点缀黄" % tag)
	_c.check(_same(_btn_bg(_menu._save_btn), GameStyle.NAVY2), "%s：存档键 = 纸白" % tag)
	var ok_cards := true
	var ok_marks := true
	for i in range(_menu._entry_blocks.size()):
		var blk: Dictionary = _menu._entry_blocks[i]
		ok_cards = ok_cards and _same(_block_bg(blk["card"]), faces[i])
		ok_marks = ok_marks and _same(_mark_col(blk.get("tag_mark") as Panel), marks[i])
	_c.check(ok_cards, "%s：四张副卡 = 点缀黄/增益绿/纸白/元素橙" % tag)
	_c.check(ok_marks, "%s：四张卡角签色标各随本卡" % tag)
	_c.check(_same(_mark_col(_menu._hero_tag_mark), GameStyle.GOLD), "%s：PLAY 色标 = 主题色" % tag)
	# 选中态永远是点缀黄（两档一致），只是落在不同那一颗 chip 上
	var sel := 1 if night else 0
	var unsel := 0 if night else 1
	_c.check(_same(_btn_bg(_menu._danger_buttons[sel]), GameStyle.JADE),
		"%s：选中 chip（%s）= 点缀黄" % [tag, StartMenu.DANGER_NAMES[sel]])
	_c.check(_same(_btn_bg(_menu._danger_buttons[unsel]), GameStyle.NAVY2),
		"%s：未选中 chip（%s）= 纸白" % [tag, StartMenu.DANGER_NAMES[unsel]])
	_c.check(_same(_bg_color(), GameStyle.INK), "%s：舞台底 = 纯黑" % tag)
	_c.check(_same(_btn_bg(_menu._top_set_btn), GameStyle.NAVY2), "%s：顶栏设置徽章 = 纸白" % tag)
	_c.check(_same(_btn_bg(_menu._update_btn), GameStyle.GOLD), "%s：检查更新键 = 主题色" % tag)
	# 危险度衬板：两档都不封边（边色全透明），只保留 1px 边宽占位
	var d_sb := _menu._danger_box.get_theme_stylebox("panel") as StyleBoxFlat
	_c.check(d_sb != null and d_sb.border_color.a < 0.02 and d_sb.border_width_left == 1,
		"%s：危险度衬板不封血朱边（边宽恒 1px、边色透明）" % tag)
	_c.check(_same(_label_col(_menu._danger_head_lbl),
		GameStyle.with_alpha(GameStyle.CHALK, 0.75)), "%s：难度提示行 = 半透明骨白" % tag)

func _is_night() -> bool:
	return GameManager.danger_level >= 1

# ---------------- 取色小工具 ----------------

## 血红判定：红通道明显压过绿/蓝（骨白、幽紫、主题金都会被这条筛掉）
func _all_blood_red(palette: Array) -> bool:
	for col in palette:
		var c: Color = col
		if c.r < 0.45 or c.r - maxf(c.g, c.b) < 0.25:
			return false
	return true

func _block_bg(panel: PanelContainer) -> Color:
	if panel == null or not is_instance_valid(panel):
		return Color(0, 0, 0, 0)
	var sb := panel.get_theme_stylebox("panel") as StyleBoxFlat
	return sb.bg_color if sb != null else Color(0, 0, 0, 0)

func _btn_bg(btn: Button) -> Color:
	if btn == null or not is_instance_valid(btn):
		return Color(0, 0, 0, 0)
	var sb := btn.get_theme_stylebox("normal") as StyleBoxFlat
	return sb.bg_color if sb != null else Color(0, 0, 0, 0)

func _label_col(lbl: Label) -> Color:
	if lbl == null or not is_instance_valid(lbl):
		return Color(0, 0, 0, 0)
	return lbl.get_theme_color("font_color")

func _mark_col(mark: Panel) -> Color:
	if mark == null or not is_instance_valid(mark):
		return Color(0, 0, 0, 0)
	var sb := mark.get_theme_stylebox("panel") as StyleBoxFlat
	return sb.bg_color if sb != null else Color(0, 0, 0, 0)

func _bg_color() -> Color:
	var bg := _menu.get_node_or_null("BackgroundOverlay") as ColorRect
	return bg.color if bg != null else Color(0, 0, 0, 0)

## 色值比较：逐通道容差（含 alpha），不做浮点完全相等
func _same(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < EPS and absf(a.g - b.g) < EPS \
		and absf(a.b - b.b) < EPS and absf(a.a - b.a) < EPS

func _has_key(cap: Array, key: String) -> bool:
	for rec in cap:
		if String(rec.get("key", "")) == key:
			return true
	return false
