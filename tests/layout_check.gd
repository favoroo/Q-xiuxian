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
##  ③ 2026-10-09 悟道面板「两边有点溢出了，选中的那个卡片上下也有点溢出了」——
##     ①② 那两把尺都是绿的，因为量的是**布局盒**：控件是斜切平行四边形，画出来的比布局盒
##     左右各宽半个斜切；选中卡又放大 1.03，撑满整行的卡片上下各顶出一截。
##     ⇒ 现在量「画出来的那一圈」，并且滚动区不需要滚动时不许顶出滚动区（见 _check_bleed）。
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
	# 悟道结算面板要有内容可摆：先攒两点并开一次会话（候选 5 个），
	# 后面每个屏宽都按 GameManager.alloc_offers 现建一版面板来量。
	GameManager.pending_upgrade_points = 2
	GameManager.open_alloc_session()
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
	_stress_shop()
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
	var l_inner: float = LevelUpDialog.card_inner_w(LevelUpDialog.card_w_for(
		Vector2(float(WIDTHS.min()), 540.0), GameManager.UPGRADE_OFFER_COUNT))
	for up in UpgradeData.UPGRADES:
		var utxt := GameStyle.wrap_bbcode(String(up.get("desc", "")), body, 13, l_inner)
		for line in String(utxt).split("\n"):
			if _plain_w(line, body, 13) > l_inner + EPS:
				bad.append("悟道 %s 的一句超 %d 宽：「%s」" % [
					String(up.get("id", "?")), int(l_inner), line])
	# 货架卡比悟道卡更窄（卡宽按屏与格数现算），法器/法宝文案要连最窄那一档一起量
	var s_inner: float = WaveShop.card_inner_w(WaveShop.offer_card_w(
		Vector2(float(WIDTHS.min()), 540.0), GameManager.SHOP_BASE_SLOTS + 1))
	for id in WeaponData.DEFS.keys():
		var stxt := GameStyle.wrap_cjk(String(WeaponData.get_def(id).get("desc", "")), body, 12, s_inner)
		if GameStyle.line_max_w(stxt, body, 12) > s_inner + EPS:
			bad.append("法器 %s 的说明在 %d 宽货架卡里仍超宽" % [id, int(s_inner)])
	for iid in ItemData.all_ids():
		var itxt := GameStyle.wrap_cjk(String(ItemData.get_def(iid).get("desc", "")), body, 12, s_inner)
		if GameStyle.line_max_w(itxt, body, 12) > s_inner + EPS:
			bad.append("法宝 %s 的说明在 %d 宽货架卡里仍超宽" % [iid, int(s_inner)])
	# 道统名单：列宽按最窄那一档屏算（960 是 canvas_items+expand 的下限）
	var col_w := CultivatorSelect.text_col_w(960.0)
	for cid in CultivatorData.all_ids():
		var cdef: Dictionary = CultivatorData.get_def(cid)
		for key in ["pros", "cons"]:
			for raw in cdef.get(key, []):
				var t := GameStyle.wrap_cjk(String(raw), body, CultivatorSelect.TXT, col_w)
				if GameStyle.line_max_w(t, body, CultivatorSelect.TXT) > col_w + EPS:
					bad.append("修士 %s 的 %s 超列宽 %d：「%s」" % [cid, key, int(col_w), String(raw)])
		var seq: String = String(cdef.get("start_equip", ""))
		if not seq.is_empty():
			var t_seq := GameStyle.wrap_cjk(seq, body, CultivatorSelect.TXT, col_w)
			if GameStyle.line_max_w(t_seq, body, CultivatorSelect.TXT) > col_w + EPS:
				bad.append("修士 %s 的开局装备超列宽 %d：「%s」" % [cid, int(col_w), seq])
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

## 灵石阁最坏样本（2026-10-09 用户真机现场：五张长文案货架卡把「出战」整排推出屏外，
## 顶栏标题同时被推到屏上方看不见了）。货架卡高是这一屏唯一的可变高度：
## ① 三格钉成文案最长的法器，且带「(当前属性额外伤害 +N)」那一行 —— 先把近战/元素点满 5 层；
## ② 一半格子挂「锁定」按钮（比已售出多一行 26 高）；
## ③ 法宝与背包同屏 ⇒ 陈列行、提示行、操作条都占实位。
## 空载货架（回气丹两字说明）永远量不出这一屏 ⇒ 必须灌满再量。
func _stress_shop() -> void:
	for i in range(5):
		GameManager.apply_upgrade("melee_up")
		GameManager.apply_upgrade("elemental_up")
	var long_ids: Array[String] = ["chiyan_dao", "liuye_feidao", "wulei_paizi"]
	var offers: Array = GameManager.shop_offers
	for i in range(mini(long_ids.size(), maxi(offers.size() - 2, 0))):
		offers[2 + i] = {
			"kind": "weapon", "id": long_ids[i], "price": 41,
			"sold": false, "locked": i % 2 == 0,
		}
	GameManager.add_item(String(ItemData.all_ids()[0]))
	if ItemData.all_ids().size() > 1:
		GameManager.add_item(String(ItemData.all_ids()[1]))
	GameManager.add_weapon("qingyun_sword")
	GameManager.unequip_to_stash(0)

## 每个板块：怎么建、怎么打开
func _screens() -> Array[Dictionary]:
	return [
		{"tag": "顶栏 HUD", "path": "res://scenes/ui/GameHUD.tscn", "open": "none"},
		{"tag": "开始菜单", "path": "res://scenes/ui/StartMenu.tscn", "open": "open"},
		{"tag": "道统选择", "path": "res://scripts/ui/CultivatorSelect.gd", "open": "show_select"},
		{"tag": "本命法器", "path": "res://scenes/ui/StartWeaponSelect.tscn", "open": "show_select"},
		{"tag": "波后悟道结算", "path": "res://scenes/ui/LevelUpDialog.tscn",
			"open": "_on_alloc_opened", "select": 1},
		{"tag": "灵石阁", "path": "res://scenes/ui/WaveShop.tscn", "open": "_on_shop_opened"},
		{"tag": "属性面板", "path": "res://scripts/ui/PlayerStatsDialog.gd", "open": "open"},
		{"tag": "暂停菜单", "path": "res://scripts/ui/PauseMenu.gd", "open": "open"},
			{"tag": "设置面板", "path": "res://scenes/ui/SettingsDialog.tscn", "open": "open"},
			{"tag": "修仙志", "path": "res://scripts/ui/CareerDialog.gd", "open": "open"},
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
		"_on_alloc_opened":
			node._on_alloc_opened()
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
	# 选中态才是这一屏的最坏情况（卡片放大），入场动画落定后再点选、再等放大落定。
	# 按真实时间等：headless 帧率不固定，等帧数会量到动画中间那一帧。
	if spec.has("select"):
		await get_tree().create_timer(0.6).timeout
		node._select_card(int(spec["select"]))
		await get_tree().create_timer(0.4).timeout
		await get_tree().process_frame
		await get_tree().process_frame
	var bad := _walk(node, screen)
	if String(spec["tag"]) == "灵石阁":
		bad.append_array(_check_shop_exits(node, screen))
	_c.check(bad.is_empty(), "%s · 屏宽 %d：无出屏、每行文字装得下（%d 处毛病）%s" % [
		String(spec["tag"]), int(screen.x), bad.size(),
		("" if bad.is_empty() else "\n      " + "\n      ".join(bad))])
	node.queue_free()
	await get_tree().process_frame

## 用户报的那一格（2026-10-09 真机）：货架卡再长，「重掷 / 出战」这一排与顶栏标题必须整颗在屏内
## —— 它们是灵石阁唯一的出口，看不见等于把玩家关在面板里。通用 _walk 量的是每个控件，
## 这三颗单独点名：以后谁再动摆位，报的是「出口不在屏内」而不是一串 rect。
func _check_shop_exits(shop: Control, screen: Vector2) -> Array[String]:
	var bad: Array[String] = []
	var title: Label = shop.get_node(
		"CenterContainer/Panel/MarginContainer/VBox/TopBar/TitleBand/TitleLabel")
	for pair in [["出战", shop.confirm_btn], ["重掷", shop.reroll_btn], ["灵石阁标题", title]]:
		var r: Rect2 = (pair[1] as Control).get_global_rect()
		if r.position.x < -EPS or r.end.x > screen.x + EPS \
				or r.position.y < -EPS or r.end.y > screen.y + EPS:
			bad.append("出口不在屏内 %s rect=%.0f,%.0f %.0fx%.0f 屏=%.0fx%.0f" % [
				String(pair[0]), r.position.x, r.position.y, r.size.x, r.size.y, screen.x, screen.y])
	# 货架装不下时靠竖滑，滑条必须看得见（看不见 = 玩家不知道下面还有卡）
	var scroll: ScrollContainer = shop.offers_scroll
	var content_h: float = shop.offers_container.size.y
	if content_h > scroll.size.y + EPS and not scroll.get_v_scroll_bar().visible:
		bad.append("货架高出滚动区 %.0f 却没露出滑条" % (content_h - scroll.size.y))
	# 滑得起来才算「全留 + 可滑到」：滚动区里的装饰性 STOP 会吃掉「按下」那一拍，
	# 卡片盖多大面积就滑不动多大面积（真机现场见 ScrollSwipeCheck 头注）⇒ 除按钮外一律放行。
	var stopped: Array[String] = []
	var stack: Array[Node] = [scroll]
	while not stack.is_empty():
		var parent: Node = stack.pop_back()
		for ch in parent.get_children():
			if not (ch is Control):
				continue
			var ctl := ch as Control
			if ctl.visible and ctl.size.x > 0.0 and ctl.size.y > 0.0 \
					and not (ctl is BaseButton) and ctl.mouse_filter == Control.MOUSE_FILTER_STOP:
				stopped.append(_path(ctl))
			stack.append(ctl)
	if not stopped.is_empty():
		bad.append("货架滚动区里 %d 处装饰控件留 STOP，手指压在卡上滑不动：%s" % [
			stopped.size(), "、".join(stopped)])
	return bad

## 整棵树逐个控件量三件事：① 这一格在屏内 ② 它**画出来**的那一圈也在屏内
## ③ 这一格里的每一行文字装得下。
## ② 是新加的一把尺：控件是斜切平行四边形时，画出来的比布局盒左右各宽出 |skew|·h/2，
## 只量 get_global_rect() 量不到「两边溢出」（面板布局盒正好贴屏边、两个斜切角被屏幕切掉）。
## 落在 ScrollContainer 里的控件只量横向那一半：竖着滑出去是这一屏的设计，
## 横着出去才是毛病（名单的横向滚动已被禁用）。
## 但这一屏**滑不动**时（滚动条没东西可滑），上下顶出滚动区就是真顶出面板 ——
## 悟道那屏「选中的卡片上下溢出」是卡片撑满整行、选中又放大 1.03，量布局盒量不出来。
func _walk(root: Control, screen: Vector2) -> Array[String]:
	var bad: Array[String] = []
	var stack: Array = [[root, null]]
	while not stack.is_empty():
		var top: Array = stack.pop_back()
		var n: Control = top[0]
		var scroll: ScrollContainer = top[1]
		if not n.visible:
			continue
		var next_scroll: ScrollContainer = (n as ScrollContainer) if n is ScrollContainer else scroll
		var in_scroll := next_scroll != null and next_scroll != n
		for c in n.get_children():
			if c is Control:
				stack.append([c, next_scroll])
		var r: Rect2 = n.get_global_rect()
		if r.size.x > 0.0 and r.size.y > 0.0 and not n.has_meta("layout_bleed"):
			var drawn := drawn_rect(r, skew_rad(n))
			if not rect_on_screen(r, screen, in_scroll):
				bad.append("出屏 %s %s rect=%.0f,%.0f %.0fx%.0f" % [
					_path(n), n.get_class(), r.position.x, r.position.y, r.size.x, r.size.y])
			elif not rect_on_screen(drawn, screen, in_scroll):
				bad.append("画出来出屏 %s %s 布局盒=%.0f,%.0f %.0fx%.0f 斜切后=%.0f..%.0f x %.0f..%.0f" % [
					_path(n), n.get_class(), r.position.x, r.position.y, r.size.x, r.size.y,
					drawn.position.x, drawn.end.x, drawn.position.y, drawn.end.y])
			elif in_scroll and not _can_slide_v(next_scroll) \
					and not inside_v(next_scroll.get_global_rect(), drawn):
				bad.append("顶出滚动区上下边界 %s %s 滚动区 y %.0f..%.0f 画出来 y %.0f..%.0f（%.0fx%.0f 格）" % [
					_path(n), n.get_class(), next_scroll.global_position.y,
					next_scroll.global_position.y + next_scroll.size.y,
					drawn.position.y, drawn.end.y, r.size.x, r.size.y])
		var probe := text_probe(n)
		if not probe.is_empty():
			if not text_fits(probe["widths"], probe["box"].x, probe["box"].y, probe["line_h"]):
				var lines: Array = probe["widths"]
				bad.append("文字装不下 %s %s 框=%.0fx%.0f 最宽行=%.0f 行数=%d 需高=%.0f 文案=「%s」" % [
					_path(n), n.get_class(), probe["box"].x, probe["box"].y,
					_maxf(lines), lines.size(), lines.size() * float(probe["line_h"]),
					String(probe["text"]).replace("\n", "⏎")])
	return bad

## 这一格自己用的斜切（弧度）：PanelContainer 走 "panel"，按钮/色签走 "normal"。
## 取引擎自己的账，不另抄一份斜率表 —— .tscn 里把 skew 改陡了而算术没跟上，这里就量得出来。
static func skew_rad(n: Control) -> float:
	for key in ["panel", "normal"]:
		if n.has_theme_stylebox(key):
			var sb: StyleBox = n.get_theme_stylebox(key)
			if sb is StyleBoxFlat:
				return (sb as StyleBoxFlat).skew.x
	return 0.0

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

## 布局盒 → 画出来的边界。斜切平行四边形绕布局盒的竖直中线居中斜切
## （Godot style_box_flat.cpp：x_skew = -skew.x * (y - center.y)）⇒ 上边右伸、下边左伸
## 各 |skew|·h/2，所以左右各要按整个高度让一次。
## 缩放不必再乘：get_global_rect() 给的已经是放大后的那一圈（选中卡 1.03 量出来就是 1.03）。
## 投影不参与：shadow_size = 0 时引擎压根不画（draw_shadow = shadow_size > 0）。
static func drawn_rect(rect: Rect2, skew: float) -> Rect2:
	var over: float = absf(skew) * rect.size.y * 0.5
	return Rect2(rect.position.x - over, rect.position.y,
		rect.size.x + over * 2.0, rect.size.y)

## drawn 的上下是否整块落在 view 里（滚动区滑不动时用它管住上下顶出；
## 横向不归它管 —— 卡片是斜切的，两个角本来要伸进面板那点占位里，屏内即可）
static func inside_v(view: Rect2, drawn: Rect2, eps: float = 0.5) -> bool:
	return drawn.position.y >= view.position.y - eps and drawn.end.y <= view.end.y + eps

## 这一屏滑不滑得动：问引擎自己的滑条，别拿 get_combined_minimum_size() 猜 ——
## 竖向滚动模式为 AUTO 时它返回的 y 恒为 0（scroll_container.cpp 只给 DISABLED/MAXIMIZE_FIRST 算高）。
static func _can_slide_v(sc: ScrollContainer) -> bool:
	var bar: VScrollBar = sc.get_v_scroll_bar()
	return bar != null and (bar.is_visible_in_tree() or bar.max_value > 0.0)

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
	_check_bleed()
	_check_safe_insets()

## 斜切与放大这两圈「布局盒量不到」的账（2026-10-09 用户真机：悟道面板两边溢出、
## 选中卡上下溢出）。反例必须拦住，正例必须放行 —— 拦不住的那一次就是漏判。
func _check_bleed() -> void:
	var wide := Vector2(1204, 540)
	var n: int = GameManager.UPGRADE_OFFER_COUNT
	var h: float = LevelUpDialog.panel_h_for(wide.y)
	# 旧算术：「屏宽 - 面板占位」全分给 5 张卡 ⇒ 面板布局盒正好贴住屏幕左右边
	var flush := Rect2(0, (wide.y - h) * 0.5, wide.x, h)
	var drawn_flush := drawn_rect(flush, LevelUpDialog.PANEL_SKEW_RAD)
	_c.check(not rect_on_screen(drawn_flush, wide),
		"反例⑨ 面板布局盒贴屏边（旧算术）⇒ 斜切画出来的两个角出屏被拦住（伸到 %.1f..%.1f）" % [
			drawn_flush.position.x, drawn_flush.end.x])
	_c.check(absf(drawn_flush.position.x) - LevelUpDialog.skew_x(h) < 0.01,
		"反例⑨ 出屏的量正好是一个斜切伸出量（%.1f 单位）" % LevelUpDialog.skew_x(h))
	# 新算术：两头各让出 PANEL_AIR_X + 斜切伸出量
	var pw: float = LevelUpDialog.panel_w_for(wide, n)
	var centered := Rect2((wide.x - pw) * 0.5, flush.position.y, pw, h)
	var drawn_new := drawn_rect(centered, LevelUpDialog.PANEL_SKEW_RAD)
	_c.check(rect_on_screen(drawn_new, wide), "正例 新算术下面板画出来的边在屏内")
	_c.check(near_air(drawn_new.position.x, LevelUpDialog.PANEL_AIR_X),
		"正例 让位算术自洽：画出来的边离屏 %.1f = PANEL_AIR_X %.1f（占位与 .tscn 没漂）" % [
			drawn_new.position.x, LevelUpDialog.PANEL_AIR_X])
	# 选中放大：卡片撑满整行时上下各顶出去；让出 pop_gutter_y 之后仍在这行之内
	var row := Rect2(28, 116, 1144, 340)
	var no_gutter := drawn_rect(Rect2(28, row.position.y, 216, row.size.y * LevelUpDialog.SEL_SCALE), 0.0)
	_c.check(not inside_v(row, no_gutter),
		"反例⑩ 选中卡放大 1.03 顶出这一行（上 %.1f 下 %.1f）被拦住" % [
			row.position.y - no_gutter.position.y, no_gutter.end.y - row.end.y])
	var g: float = LevelUpDialog.pop_gutter_y(wide.y)
	var with_gutter := drawn_rect(Rect2(28, row.position.y + g, 216,
		(row.size.y - g * 2.0) * LevelUpDialog.SEL_SCALE), 0.0)
	_c.check(inside_v(row, with_gutter),
		"正例 上下各让 %d 单位后放大仍在这行之内（放大后高 %.1f ≤ %.0f）" % [
			int(g), with_gutter.size.y, row.size.y])

static func near_air(actual: float, want: float) -> bool:
	return absf(actual - want) <= 1.0

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
