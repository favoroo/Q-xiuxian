extends Node

## UI 摆位判据：逐档屏宽把每个面板真建一遍，量 rect 与「每一行文字的宽」说话。
## 运行: godot --headless --path . res://tests/LayoutCheck.tscn
##       godot --headless --path . res://tests/LayoutCheck.tscn -- --selftest
##
## 为什么立这条判据（2026-10-08 用户真机两张现场）：
##  ① 本命法器/道统/商店卡上的描述「都显示在一行里面叠在一起，都看不清了」。
##     同一段代码、同一份字体度量：macOS 上 `AUTOWRAP_WORD` 折成三行，Android 真机上
##     整行不折、压到邻卡上（把截图量过：卡片仍是 156 宽、面板仍在 y=22，只有文字没折）。
##     折得开折不开取决于引擎给这段中文找到几个断点 —— 那是跨平台不保证的自由量。
##     ⇒ 规则改成「文案自己带换行」(GameStyle.wrap_cjk)，判据量的是**每一行**的宽，
##     不再量「整段文字 + autowrap 开关有没有打开」—— 后者在真机上会全绿而画面是坏的。
##  ② 「顶部的一些 UI 都显示到外面去了」。道统一排 6 张卡各钉 210 宽 = 1340 单位，
##     而 20:9 屏在 canvas_items+expand 下可视宽只有 1202 ⇒ 两头各一张卡出屏，
##     居中的标题被推到屏幕右半边。顶栏横向内容一多同样把「属性/暂停」推出屏外。
##     这类毛病不崩、不报错、编辑器里也看不出来 ⇒ 逐档屏宽度量 rect。
##
## 尺子取引擎自己的账（节点实得 rect + 字体量出来的行宽），不另抄一份像素表。

## 4:3 平板(设计可视 960×720) / 16:9 基准 / 20:9 宽屏 —— 见 ToastCheck 同一套档位
const WIDTHS: Array[int] = [720, 960, 1204]
const EPS := 1.0

var _c := TestCheck.new()
var _holder: Control

func _ready() -> void:
	if "--selftest" in OS.get_cmdline_user_args():
		_selftest()
		get_tree().quit(0 if _c.report("LAYOUT_SELFTEST_RESULT") else 1)
		return
	call_deferred("_run")

func _run() -> void:
	_holder = Control.new()
	_holder.name = "LayoutHolder"
	_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().root.add_child(_holder)
	GameManager.cultivator_id = "jianchi"
	GameManager.start_run("qingyun_sword")
	GameManager.add_spirit_stones(500)
	GameManager.roll_shop(true)
	# 货架是随机的 ⇒ 钉两格必测的短文案色签：回气丹的「丹药」与法宝的「凡品·法宝」。
	# 这两枚正是「贴着字走的色签被引擎再折一次、多出一行孤字」的现场（框 29、字也要 29）。
	if GameManager.shop_offers.size() >= 2:
		GameManager.shop_offers[0] = {
			"kind": "potion", "id": WeaponData.POTION_ID, "price": 11, "sold": false, "locked": false,
		}
		GameManager.shop_offers[1] = {
			"kind": "item", "id": String(ItemData.all_ids()[0]), "price": 14, "sold": false, "locked": false,
		}
	for i in range(3):
		GameManager.add_weapon("huoyan_fu")
	await get_tree().process_frame
	for w in WIDTHS:
		get_tree().root.size = Vector2i(w, 540)
		await get_tree().process_frame
		await get_tree().process_frame
		var screen: Vector2 = get_tree().root.get_visible_rect().size
		print("\n===== 窗口 %dx540 → 设计可视 %s =====" % [w, str(screen)])
		for spec in _screens():
			await _check_screen(spec, screen)
		get_tree().paused = false
	_check_all_table_texts()
	if _c.report("LAYOUT_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

## 文案表逐条量：随机抽三张卡盖不住全部条目，而「哪一句会撑破格子」是数据决定的。
## 每一格的可用的宽与面板里用的是同一份算术（StartWeaponSelect.CARD_W /
## LevelUpDialog.CARD_W / CultivatorSelect.text_col_w），所以这里不抄数字。
func _check_all_table_texts() -> void:
	var body := GameStyle.body_font()
	var disp := GameStyle.display_font()
	var bad: Array[String] = []
	var w_inner: float = StartWeaponSelect.CARD_W - StartWeaponSelect.CARD_PAD_X * 2.0
	for id in WeaponData.DEFS.keys():
		var def: Dictionary = WeaponData.get_def(id)
		var txt := GameStyle.wrap_cjk(String(def.get("desc", "")), body, 12, w_inner)
		if GameStyle.line_max_w(txt, body, 12) > w_inner + EPS:
			bad.append("法器 %s 的说明切完仍超 %d 宽" % [id, int(w_inner)])
		var name_txt := GameStyle.wrap_cjk(String(def.get("name", "")), disp, 17, w_inner)
		if GameStyle.line_max_w(name_txt, disp, 17) > w_inner + EPS:
			bad.append("法器 %s 的名号切完仍超 %d 宽" % [id, int(w_inner)])
	var l_inner: float = LevelUpDialog.CARD_W - LevelUpDialog.CARD_PAD_X * 2.0
	for up in UpgradeData.UPGRADES:
		var utxt := GameStyle.wrap_bbcode(String(up.get("desc", "")), body, 13, l_inner)
		for line in String(utxt).split("\n"):
			if _plain_w(line, body, 13) > l_inner + EPS:
				bad.append("悟道 %s 的一句超 %d 宽：「%s」" % [
					String(up.get("id", "?")), int(l_inner), line])
	# 道统名单：列宽按最窄那一档屏算（960 是 canvas_items+expand 的下限）
	var col_w := CultivatorSelect.text_col_w(960.0)
	for cid in CultivatorData.all_ids():
		var cdef: Dictionary = CultivatorData.get_def(cid)
		for key in ["pros", "cons"]:
			for raw in cdef.get(key, []):
				var t := GameStyle.wrap_cjk(String(raw), body, CultivatorSelect.TXT, col_w)
				if GameStyle.line_max_w(t, body, CultivatorSelect.TXT) > col_w + EPS:
					bad.append("修士 %s 的 %s 超列宽 %d：「%s」" % [cid, key, int(col_w), String(raw)])
	_c.check(bad.is_empty(), "文案表逐条切行后都装得下自己那一格（%d 处超宽）%s" % [
		bad.size(), ("" if bad.is_empty() else "\n      " + "\n      ".join(bad))])

func _plain_w(s: String, font: Font, size: int) -> float:
	return font.get_string_size(_strip_bbcode(s), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

## 「有些情况下顶部 UI 出屏」里的那些情况：读数取打得最久那一局的最宽样本、
## 羁绊徽记挂满五枚。空载顶栏永远量不出毛病 ⇒ 必须灌最坏样本再量。
func _stress_hud(hud: Control) -> void:
	hud.hp_label.text = "12847/12847"
	hud.level_label.text = "Lv.99"
	hud.time_label.text = "20:00"
	hud.wave_label.text = "第 20 波"
	hud.kills_label.text = "斩妖 12847"
	hud.shards_label.text = "灵石 99999"
	var box: HBoxContainer = hud.get("_synergy_box")
	if box == null:
		return
	for tag in ["剑系", "符箓", "雷法", "御灵", "广域"]:
		var chip := Label.new()
		chip.text = " %s Lv.3 " % tag
		chip.add_theme_stylebox_override("normal", GameStyle.chip(GameStyle.BLUE_DK))
		GameStyle.label(chip, 11, GameStyle.PAPER)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(chip)

## 每个板块：怎么建、怎么打开
func _screens() -> Array[Dictionary]:
	return [
		{"tag": "顶栏 HUD", "path": "res://scenes/ui/GameHUD.tscn", "open": "none"},
		{"tag": "开始菜单", "path": "res://scenes/ui/StartMenu.tscn", "open": "open"},
		{"tag": "道统选择", "path": "res://scripts/ui/CultivatorSelect.gd", "open": "show_select"},
		{"tag": "本命法器", "path": "res://scenes/ui/StartWeaponSelect.tscn", "open": "show_select"},
		{"tag": "升级三选一", "path": "res://scenes/ui/LevelUpDialog.tscn", "open": "_on_level_up"},
		{"tag": "灵石阁", "path": "res://scenes/ui/WaveShop.tscn", "open": "_on_shop_opened"},
		{"tag": "属性面板", "path": "res://scripts/ui/PlayerStatsDialog.gd", "open": "open"},
		{"tag": "暂停菜单", "path": "res://scripts/ui/PauseMenu.gd", "open": "open"},
		{"tag": "设置面板", "path": "res://scenes/ui/SettingsDialog.tscn", "open": "open"},
		{"tag": "结算", "path": "res://scenes/ui/GameOverDialog.tscn", "open": "_on_game_over"},
	]

func _check_screen(spec: Dictionary, screen: Vector2) -> void:
	var node: Control = null
	var res := load(spec["path"])
	if spec["path"].ends_with(".gd"):
		node = res.new()
	else:
		node = res.instantiate()
	node.visible = true
	_holder.add_child(node)
	await get_tree().process_frame
	match String(spec["open"]):
		"open":
			node.open()
		"show_select":
			node.show_select()
		"_on_level_up":
			node._on_level_up(3)
		"_on_game_over":
			node._on_game_over(false)
		"_on_shop_opened":
			node._on_shop_opened()
		_:
			pass
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().paused = false
	if not node.visible:
		# 面板没开 = 整棵子树量不到 ⇒ 判据会假绿，必须当场报红
		_c.check(false, "%s · 屏宽 %d：面板未打开（visible=false，这一屏没量到）" % [
			String(spec["tag"]), int(screen.x)])
		node.queue_free()
		await get_tree().process_frame
		return
	if String(spec["tag"]) == "顶栏 HUD":
		_stress_hud(node)
	await get_tree().process_frame
	await get_tree().process_frame
	var bad := _walk(node, screen)
	_c.check(bad.is_empty(), "%s · 屏宽 %d：无出屏、每行文字装得下（%d 处毛病）%s" % [
		String(spec["tag"]), int(screen.x), bad.size(),
		("" if bad.is_empty() else "\n      " + "\n      ".join(bad))])
	node.queue_free()
	await get_tree().process_frame

## 整棵树逐个控件量两件事：① 这一格在屏内 ② 这一格里的每一行文字装得下。
## 落在 ScrollContainer 里的控件只量横向那一半：竖着滑出去是这一屏的设计，
## 横着出去才是毛病（名单的横向滚动已被禁用）。
func _walk(root: Control, screen: Vector2) -> Array[String]:
	var bad: Array[String] = []
	var stack: Array = [[root, false]]
	while not stack.is_empty():
		var top: Array = stack.pop_back()
		var n: Control = top[0]
		var in_scroll: bool = top[1]
		if not n.visible:
			continue
		var next_scroll := in_scroll or n is ScrollContainer
		for c in n.get_children():
			if c is Control:
				stack.append([c, next_scroll])
		var r: Rect2 = n.get_global_rect()
		if r.size.x > 0.0 and r.size.y > 0.0 and not n.has_meta("layout_bleed") \
				and not rect_on_screen(r, screen, in_scroll):
			bad.append("出屏 %s %s rect=%.0f,%.0f %.0fx%.0f" % [
				_path(n), n.get_class(), r.position.x, r.position.y, r.size.x, r.size.y])
		var probe := text_probe(n)
		if not probe.is_empty():
			if not text_fits(probe["widths"], probe["box"].x, probe["box"].y, probe["line_h"]):
				var lines: Array = probe["widths"]
				bad.append("文字装不下 %s %s 框=%.0fx%.0f 最宽行=%.0f 行数=%d 需高=%.0f 文案=「%s」" % [
					_path(n), n.get_class(), probe["box"].x, probe["box"].y,
					_maxf(lines), lines.size(), lines.size() * float(probe["line_h"]),
					String(probe["text"]).replace("\n", "⏎")])
	return bad

func _path(n: Node) -> String:
	var p := String(n.name)
	var parent := n.get_parent()
	while parent != null and parent != _holder:
		p = String(parent.name) + "/" + p
		parent = parent.get_parent()
	return p

static func _maxf(a: Array) -> float:
	var m := 0.0
	for v in a:
		m = maxf(m, float(v))
	return m

# ---------------- 两条尺子（纯函数，selftest 直接喂反例） ----------------

static func rect_on_screen(rect: Rect2, screen: Vector2, allow_off_vertical: bool = false) -> bool:
	if rect.position.x < -EPS or rect.end.x > screen.x + EPS:
		return false
	if allow_off_vertical:
		return true
	return rect.position.y >= -EPS and rect.end.y <= screen.y + EPS

## 每一行的宽都要不超过这一格的宽；整块的高也要不超过这一格的高。
static func text_fits(line_widths: Array, box_w: float, box_h: float, line_h: float) -> bool:
	if line_widths.is_empty():
		return true
	for w in line_widths:
		if float(w) > box_w + EPS:
			return false
	if float(line_widths.size()) * line_h > box_h + EPS:
		return false
	return true

## 取一个控件的文案与字体：Label/Button 走 "font"，RichTextLabel 走 normal_font。
## 空文本、纯装饰控件返回 {}（不参与判据）。
func text_probe(n: Control) -> Dictionary:
	var txt := ""
	var font: Font = null
	var fsize := 16
	if n is RichTextLabel:
		if not (n as RichTextLabel).bbcode_enabled:
			txt = (n as RichTextLabel).text
		else:
			txt = _strip_bbcode((n as RichTextLabel).text)
		font = n.get_theme_font("normal_font")
		fsize = n.get_theme_font_size("normal_font_size")
	elif n is Label:
		txt = (n as Label).text
		font = n.get_theme_font("font")
		fsize = n.get_theme_font_size("font_size")
	elif n is Button:
		txt = (n as Button).text
		font = n.get_theme_font("font")
		fsize = n.get_theme_font_size("font_size")
	else:
		return {}
	if txt.strip_edges() == "" or font == null:
		return {}
	var widths: Array = []
	for line in txt.split("\n"):
		widths.append(font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x)
	return {
		"widths": widths, "box": n.size, "line_h": font.get_height(fsize),
		"text": txt,
	}

func _strip_bbcode(s: String) -> String:
	var out := ""
	var i := 0
	while i < s.length():
		if s[i] == "[":
			var close := s.find("]", i)
			if close >= 0:
				i = close + 1
				continue
		out += s[i]
		i += 1
	return out

# ---------------- 反例：尺子必须有牙齿 ----------------

func _selftest() -> void:
	var screen := Vector2(1204, 540)
	_c.check(text_fits([120.0, 96.0], 136.0, 98.0, 19.0), "正例 两行各 120/96 装进 136×98")
	_c.check(not text_fits([360.0], 136.0, 98.0, 19.0),
		"反例① 整段一行 360 压进 136 的卡里（真机上「叠在一起看不清」那一格）被拦住")
	_c.check(not text_fits([130.0, 130.0, 130.0, 130.0, 130.0, 130.0], 136.0, 98.0, 19.0),
		"反例② 六行装不进 98 高（折对了但格子不够高）被拦住")
	_c.check(not text_fits([140.0], 136.0, 98.0, 19.0),
		"反例③ 行宽只超 4 单位（斜切/描边吃掉的那点）也被拦住")
	_c.check(rect_on_screen(Rect2(0, 0, 1204, 540), screen), "正例 通屏控件放行")
	_c.check(not rect_on_screen(Rect2(-68, 20, 1340, 380), screen),
		"反例④ 道统一排 6×210 = 1340 居中后两头各出屏 68 被拦住")
	_c.check(not rect_on_screen(Rect2(1150, 20, 62, 30), screen),
		"反例⑤ 顶栏右侧按钮被推到屏外（x 尾 1212 > 1204）被拦住")
	_c.check(not rect_on_screen(Rect2(20, 520, 200, 30), screen),
		"反例⑥ 底部控件掉出屏底被拦住")
	_c.check(rect_on_screen(Rect2(20, 520, 200, 300), screen, true),
		"正例 名单里滑出屏底的那一行放行（竖着滑出去是设计）")
	_c.check(not rect_on_screen(Rect2(20, 520, 1400, 300), screen, true),
		"反例⑦ 名单里横向超出屏宽的那一行仍被拦住（横向滚动已被禁用）")
	_check_safe_insets()

## 刘海让位的算术：桌面窗口化时窗口 ⊊ 屏幕，交集就是窗口 ⇒ 三个 0，摆位不许动
func _check_safe_insets() -> void:
	var zero := GameHUD.safe_insets(Rect2(100, 100, 1280, 720), Rect2(100, 100, 1280, 720), 1.0)
	_c.check(_same(zero, [0.0, 0.0, 0.0]), "正例 无刘海/窗口化 ⇒ 顶栏不让位（实得 %s）" % str(zero))
	var notch := GameHUD.safe_insets(Rect2(0, 30, 1140, 540), Rect2(0, 0, 1200, 540), 2.0)
	_c.check(_same(notch, [0.0, 15.0, 30.0]),
		"正例 顶部 30px + 右侧 60px 刘海按 scale=2 折成设计单位（实得 %s）" % str(notch))
	var wild := GameHUD.safe_insets(Rect2(0, 900, 100, 100), Rect2(0, 0, 1200, 540), 1.0)
	_c.check(float(wild[1]) <= GameHUD.SAFE_CAP + 0.01 and float(wild[2]) <= GameHUD.SAFE_CAP + 0.01,
		"反例⑧ 离谱的 safe area 读数被夹在上限内，不会把顶栏推到屏心（实得 %s）" % str(wild))

func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if absf(float(a[i]) - float(b[i])) > 0.01:
			return false
	return true
