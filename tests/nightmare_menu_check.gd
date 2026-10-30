extends Node

## 首页噩梦氛围换肤判据（2026-10-29）：
##   ① 普通态逐件与改动前一致（大卡 = 主题色、四卡 = 点缀黄/增益绿/纸白/元素橙、标题 = 墨字、
##      角签色标各随本卡）—— 这条是「普通难度零改动」的护栏；
##   ② 切到噩梦后整套换血月夜（舞台深紫黑、大卡深渊紫、标题骨白、主行动血朱、
##      四卡压进夜色、所有角签统一血朱、未选中 chip 换暗紫）；
##   ③ 切回普通逐件还原（可逆）；
##   ④ 夜景里换主题色，Hero 不许被 GameStyle 主题注册表洗回主题色；
##   ⑤ 同值重发的 danger_changed（作者面板迷雾预览）不打第二次扫屏音效。
##
## 运行: godot --headless --path . res://tests/NightmareMenuCheck.tscn
## 说明: headless 下 StartMenu 不建流星雨/画框（DisplayServer 判定），所以本判据只量配色；
##       血雨配色与画框观感由 tests/StartMenuTagPreview.tscn 的噩梦截图人眼验收。

const EPS := 0.004

var _c := TestCheck.new()
var _menu: StartMenu

func _ready() -> void:
	_c.set_min_checks(28)
	_menu = load("res://scenes/ui/StartMenu.tscn").instantiate()
	add_child(_menu)
	_menu.open()
	await get_tree().process_frame

	# ① 普通态基线
	_check_normal("初始（普通）")

	# ② 进噩梦：判据环境没有真实生涯进度，先在进程内把「已破普通」补上（不落盘）
	#    —— set_danger 会按 max_danger_unlocked 夹位，不补就永远只能停在 0
	var saved_best := int(GameManager.career_stats.get("best_danger_cleared", -1))
	GameManager.career_stats["best_danger_cleared"] = 0
	AudioManager.begin_sfx_capture()
	GameManager.set_danger(1)
	var enter_cap := AudioManager.end_sfx_capture()
	_c.check(_has_key(enter_cap, "boss_raid"), "进噩梦打一记魔君低吼（boss_raid）")
	# 舞台底色走 0.45s 补间，等它落定再量
	await get_tree().create_timer(0.7).timeout
	_check_night()

	# ④ 夜景里换主题色：Hero 大卡跟随主题色刷新
	var saved_theme := SettingsManager.theme_color()
	GameStyle.apply_theme_color(&"pink")
	SettingsManager.theme_color_changed.emit(&"pink")
	await get_tree().process_frame
	_c.check(_same(_block_bg(_menu._hero_card), GameStyle.GOLD),
		"夜景里换主题色后 Hero 大卡跟随主题色（保持主题色面）")
	GameStyle.apply_theme_color(saved_theme)
	SettingsManager.theme_color_changed.emit(saved_theme)
	await get_tree().process_frame
	_c.check(_same(_block_bg(_menu._hero_card), GameStyle.GOLD),
		"主题色还原后 Hero 大卡仍是原本主题色")

	# ⑤ 同值重发（作者面板迷雾预览会这么干）：不该再打人声/扫屏
	AudioManager.begin_sfx_capture()
	GameManager.danger_changed.emit(1)
	var dup_cap := AudioManager.end_sfx_capture()
	_c.check(dup_cap.is_empty(), "同值重发 danger_changed 不打音效")

	# ③ 回普通：逐件还原
	AudioManager.begin_sfx_capture()
	GameManager.set_danger(0)
	var exit_cap := AudioManager.end_sfx_capture()
	_c.check(_has_key(exit_cap, "ui_confirm"), "回普通打一声轻确认（ui_confirm）")
	await get_tree().create_timer(0.7).timeout
	_check_normal("切回普通")

	# ⑥ 迷雾层独立自检（headless 下主菜单不挂装饰层，在此显式核对控件状态与切换逻辑）
	var fog_probe := MenuNightmareFog.install(_menu)
	_c.check(fog_probe.mouse_filter == Control.MOUSE_FILTER_IGNORE, "迷雾层鼠标穿透（MOUSE_FILTER_IGNORE）")
	_c.check(bool(fog_probe.get_meta("layout_bleed", false)), "迷雾层标 layout_bleed 布局放行")
	_c.check(not fog_probe.visible, "迷雾层初始隐藏（普通模式零消耗）")
	fog_probe.set_nightmare(true, false)
	_c.check(fog_probe.visible, "切噩梦后迷雾层点亮")
	_c.check(absf(fog_probe._night - 1.0) < 0.01, "切噩梦后 night 权重置 1.0")
	fog_probe.set_nightmare(false, false)
	_c.check(not fog_probe.visible, "切回普通后迷雾层熄灭")
	fog_probe.queue_free()

	GameManager.career_stats["best_danger_cleared"] = saved_best
	if _c.report("NIGHTMARE_MENU_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

# ---------------- 逐件核对 ----------------

func _check_normal(tag: String) -> void:
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
	_c.check(_same(_btn_bg(_menu._danger_buttons[0]), GameStyle.JADE), "%s：选中「普通」chip = 点缀黄" % tag)
	_c.check(_same(_btn_bg(_menu._danger_buttons[1]), GameStyle.NAVY2), "%s：未选中「噩梦」chip = 纸白" % tag)
	_c.check(_same(_bg_color(), GameStyle.INK), "%s：舞台底 = 纯黑" % tag)
	_c.check(_same(_btn_bg(_menu._top_set_btn), GameStyle.NAVY2), "%s：顶栏设置徽章 = 纸白" % tag)
	_c.check(_same(_label_col(_menu._danger_head_lbl),
		GameStyle.with_alpha(GameStyle.CHALK, 0.75)), "%s：难度提示行 = 半透明骨白" % tag)

func _check_night() -> void:
	var faces := [GameStyle.JADE, GameStyle.GOOD, GameStyle.NAVY2, GameStyle.ELEMENT]
	var marks := [GameStyle.JADE, GameStyle.GOOD, GameStyle.GOLD, GameStyle.ELEMENT]
	_c.check(_same(_block_bg(_menu._hero_card), GameStyle.GOLD), "噩梦：Hero 大卡保持主题色（不换暗色）")
	_c.check(_same(_label_col(_menu._hero_title), GameStyle.INK_TEXT), "噩梦：大标题保持墨字（高可读性）")
	_c.check(_same(_btn_bg(_menu._hero_start_btn), GameStyle.JADE), "噩梦：开始游戏键保持点缀黄")
	_c.check(_same(_btn_bg(_menu._save_btn), GameStyle.NAVY2), "噩梦：存档键保持纸白面")
	_c.check(_same(_menu._save_btn.get_theme_color("font_color"), GameStyle.PAPER),
		"噩梦：存档键字保持墨色纸字")
	var ok_cards := true
	var ok_marks := true
	for i in range(_menu._entry_blocks.size()):
		var blk: Dictionary = _menu._entry_blocks[i]
		ok_cards = ok_cards and _same(_block_bg(blk["card"]), faces[i])
		ok_marks = ok_marks and _same(_mark_col(blk.get("tag_mark") as Panel), marks[i])
	_c.check(ok_cards, "噩梦：四张副卡保持原色（点缀黄/增益绿/纸白/元素橙）")
	_c.check(ok_marks, "噩梦：四张卡角签色标各随本卡")
	_c.check(_same(_mark_col(_menu._hero_tag_mark), GameStyle.GOLD), "噩梦：PLAY 色标保持主题色")
	_c.check(_same(_btn_bg(_menu._danger_buttons[1]), GameStyle.NIGHT_SEAL), "噩梦：选中「噩梦」chip = 血朱高亮")
	_c.check(_same(_btn_bg(_menu._danger_buttons[0]), GameStyle.NAVY2), "噩梦：未选中「普通」chip = 纸白")
	_c.check(_same(_bg_color(), GameStyle.NIGHT_STAGE), "噩梦：舞台底 = 深紫黑夜色")
	_c.check(_same(_btn_bg(_menu._update_btn), GameStyle.GOLD), "噩梦：检查更新键保持主题色")
	# 危险度衬板：1px 边宽恒定，封一道微弱血朱细边
	var d_sb := _menu._danger_box.get_theme_stylebox("panel") as StyleBoxFlat
	_c.check(d_sb != null and absf(d_sb.border_color.a - 0.6) < 0.02
		and d_sb.border_width_left == 1, "噩梦：危险度衬板封一道血朱细边（边宽恒 1px）")
	_c.check(_same(_label_col(_menu._danger_head_lbl),
		GameStyle.with_alpha(GameStyle.NIGHT_SEAL_EDGE, 0.95)), "噩梦：难度提示行转血朱亮调")
	_c.check("噩梦" in _menu._danger_head_lbl.text, "噩梦：提示行写明「噩梦」及其机制")

# ---------------- 取色小工具 ----------------

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