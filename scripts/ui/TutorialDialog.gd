class_name TutorialDialog
extends BaseModalDialog

## 新手指南（首次进入弹窗 + 设置「新手指南」入口）：分页图文向导，只讲本作特色机制。
## 配图是实机截图（tools/TutorialShot.tscn 产出，assets/art/tutorial/），不是图标——
## 教学意义优先：羁绊页拍属性面板、商店页拍货架锁定/重掷/星标陈列，正文直接指着图讲。
## 触发：StartMenu 点「开始游戏」后、选角前（未勾选「下次不弹出」就每次都弹），见 StartMenu._on_start_pressed；
## 设置页入口见 SettingsDialog._build_body（底部常驻按钮，任何页签可见）。
## 翻页为线性向导（上一步/下一步），不复用基类 Tab；_tab_bar 插槽改作页码指示块。
## 出口有两条，语义不同：「跳 过」（右上，同 ESC/遮罩）= 收下指南继续进选角；
## 「〈 返 回」（左上）= 反悔退出回主菜单，且不落「下次不弹出」——玩家只是暂时不想看。
## 两者都走 close() → closed，StartMenu 用 closed 串接：返回键先置 _left_via_back，
## StartMenu._after_tutorial 见该标记就重开主菜单，而不是进选角。
## 「下次不弹出」勾选框：点一下即落 user://settings.cfg（SettingsManager.tutorial_muted），
## 只关掉「开局自动弹」这一条路径；勾了之后仍可从主菜单/设置页手动翻开并取消勾选。

const PANEL_SIZE := Vector2(880, 540)
## 两栏页：左图宽（16:9 → 高 259）与右栏正文换行宽度（788 内宽 − 图 460 − 栏距 14 − 余量）
const IMG_W := 460.0
const COL_TEXT_W := 300.0

## 分页文案：title 页题 / body 正文 / image 实机截图路径（全部带图，左图右文两栏）
const PAGES: Array[Dictionary] = [
	{
		"title": "战斗与技能",
		"body": "左摇杆移动，右按钮放技能。\n武器自动攻击，你只管走位躲伤害。",
		"image": "res://assets/art/tutorial/shot_combat.png",
	},
	{
		"title": "装备标签羁绊",
		"body": "每件武器带「器类 + 五行」标签。\n同标签凑 2 / 4 / 6 件解锁羁绊，阵容越纯越强。",
		"image": "res://assets/art/tutorial/shot_synergy.png",
	},
	{
		"title": "商店与升星",
		"body": "看中的点「锁定」留到下回合；「重掷」换一批，费用递增。\n3 把同名同星合成升星，伤害翻倍。",
		"image": "res://assets/art/tutorial/shot_shop.png",
	},
	{
		"title": "悟道加点",
		"body": "升级不打断战斗，回合结束统一加点。\n点卡再按「确认」；每回合 1 次免费刷新。",
		"image": "res://assets/art/tutorial/shot_alloc.png",
	},
	{
		"title": "场景交互物",
		"body": "聚灵阵：长按启动，首次免费；之后每回合金币启动一次。全屏重创敌人并召唤灵兽。\n宝箱：打 3 下砸开，越稀有掉越多，玉匣必送道具。",
		"image": "res://assets/art/tutorial/shot_field.png",
	},
]

var _page_controls: Array[Control] = []
var _page_dots: Array[Panel] = []
var _cur: int = 0
var _prev_btn: Button
var _next_btn: Button
var _mute_chk: CheckBox
var _back_btn: Button

## 本次关闭是否由「〈 返回」触发（回主菜单，不进选角）。
## 放在关闭信号之前由按钮置位、closed 发出后由 StartMenu._after_tutorial 读走并复位；
## 其余关闭路径（跳过/ESC/遮罩/末页「开始游戏」）恒为 false。
var left_via_back: bool = false

func _get_title_text() -> String:
	return "新 手 指 南"

## 标题块是浅色底，黑字对比更清楚
func _get_title_color() -> Color:
	return GameStyle.INK_TEXT

func _get_close_btn_text() -> String:
	return "跳 过"

func _get_panel_size() -> Vector2:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0:
		vp = Vector2(960, 540)
	return Vector2(minf(PANEL_SIZE.x, vp.x - 48.0), minf(PANEL_SIZE.y, vp.y - 40.0))

func _build_body(root_vbox: VBoxContainer) -> void:
	# 顶栏左侧「〈 返回」：与右上「跳 过」左右对称的两条出口。
	# 跳过 = 收下指南继续进选角；返回 = 反悔回主菜单（不落「下次不弹出」）。
	# 基类 _top_bar 已按 [标题块, Tab插槽, 关闭键] 建好，这里把返回插到最左。
	_back_btn = Button.new()
	_back_btn.text = "〈 返 回"
	_back_btn.custom_minimum_size = Vector2(84, 34)
	_back_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_back_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(_back_btn, GameStyle.NAVY2, GameStyle.GOLD, 14, GameStyle.PAPER, 5.0, GameStyle.INK_TEXT)
	_back_btn.pressed.connect(_on_back_pressed)
	_top_bar.add_child(_back_btn)
	_top_bar.move_child(_back_btn, 0)

	# 内容区：斜切内容面板，各页叠放、按显隐切换
	var content_panel := PanelContainer.new()
	content_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var cont_sb := GameStyle.outlined_panel(GameStyle.NAVY2, GameStyle.INK, 2, 0.0)
	cont_sb.content_margin_left = 14.0
	cont_sb.content_margin_top = 10.0
	cont_sb.content_margin_right = 14.0
	cont_sb.content_margin_bottom = 10.0
	content_panel.add_theme_stylebox_override("panel", cont_sb)
	root_vbox.add_child(content_panel)

	for p in PAGES:
		var page := _build_page(p)
		content_panel.add_child(page)
		_page_controls.append(page)

	# 页码指示块（借用基类 _tab_bar 插槽）
	for i in range(PAGES.size()):
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(20, 8)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_tab_bar.add_child(dot)
		_page_dots.append(dot)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tab_bar.add_child(spacer)

	# 底部翻页栏
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 10)
	root_vbox.add_child(nav)

	_prev_btn = Button.new()
	_prev_btn.text = "〈 上一步"
	_prev_btn.custom_minimum_size = Vector2(110, 36)
	_prev_btn.focus_mode = Control.FOCUS_NONE
	_prev_btn.pressed.connect(func(): _go_page(_cur - 1))
	GameStyle.button(_prev_btn, GameStyle.NAVY2, GameStyle.GOLD, 14, GameStyle.PAPER, 5.0, GameStyle.INK_TEXT)
	nav.add_child(_prev_btn)

	_mute_chk = _build_mute_chk()
	nav.add_child(_mute_chk)

	var mid := Control.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nav.add_child(mid)

	_next_btn = Button.new()
	_next_btn.text = "下一步 〉"
	_next_btn.custom_minimum_size = Vector2(130, 36)
	_next_btn.focus_mode = Control.FOCUS_NONE
	_next_btn.pressed.connect(_on_next_pressed)
	nav.add_child(_next_btn)

	_go_page(0)
	_refresh_mute_chk()

## 「下次不弹出」勾选框：贴着「上一步」摆在左侧，每一页都在手边（不必翻到末页才看见）。
## 方块自己画（勾上 = 主蓝实心，未勾 = 灰线空心），既不用引擎默认那枚灰底对勾，
## 也不用打勾/方框字形 —— 子集字体里没有这类符号，真机上只会画成豆腐块。
func _build_mute_chk() -> CheckBox:
	var chk := CheckBox.new()
	chk.text = "下次不弹出"
	chk.custom_minimum_size = Vector2(150, 36)
	chk.focus_mode = Control.FOCUS_NONE
	chk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# 借 GameStyle.button 拿字体与点击音（点击音在它内部统一挂），随后把底板清空：
	# 这一行只要「方块 + 字」，留一层斜切大色块会看着像第二个按钮。
	GameStyle.button(chk, GameStyle.NAVY2, GameStyle.GOLD, 13, GameStyle.PAPER_DIM, 5.0, GameStyle.INK_TEXT)
	for st: StringName in [&"normal", &"hover", &"pressed", &"disabled", &"focus"]:
		chk.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	# 坑：CheckBox 的方块是 DATA_TYPE_ICON（贴图），不是 stylebox —— 给 "checked" 塞
	# StyleBoxFlat 一句报错都没有，画出来还是引擎那枚灰对勾（实测踩过）。
	# 引擎画贴图时按 checkbox_checked_color / checkbox_unchecked_color 调制，
	# 颜色已经画进贴图里，所以两个调制色一律给白。
	var tex_on := _mute_box_tex(true)
	var tex_off := _mute_box_tex(false)
	chk.add_theme_icon_override("checked", tex_on)
	chk.add_theme_icon_override("checked_disabled", tex_on)
	chk.add_theme_icon_override("unchecked", tex_off)
	chk.add_theme_icon_override("unchecked_disabled", tex_off)
	chk.add_theme_color_override("checkbox_checked_color", Color.WHITE)
	chk.add_theme_color_override("checkbox_unchecked_color", Color.WHITE)
	chk.add_theme_constant_override("h_separation", 8)
	chk.pressed.connect(func():
		SettingsManager.set_tutorial_muted(chk.button_pressed)
		_refresh_mute_chk()
	)
	return chk

## 勾选方块贴图边长与描边厚（16 见方，与引擎默认那枚同尺，换上去不动版面）
const MUTE_BOX_PX := 16
const MUTE_BOX_EDGE := 2

## 勾选方块贴图：勾上填主蓝（GameStyle 里蓝 = 选中）+ 霜华亮蓝描边 + 墨色对勾，
## 未勾只留灰线空心。对勾自己铺像素 —— 子集字体里没有对勾符号，画不成字形。
func _mute_box_tex(on: bool) -> ImageTexture:
	var img := Image.create(MUTE_BOX_PX, MUTE_BOX_PX, false, Image.FORMAT_RGBA8)
	var edge := GameStyle.GOLD_EDGE if on else GameStyle.LINE
	var face := GameStyle.GOLD if on else Color.TRANSPARENT
	for y in MUTE_BOX_PX:
		for x in MUTE_BOX_PX:
			var p := Vector2(x, y) + Vector2(0.5, 0.5)
			var on_edge: bool = x < MUTE_BOX_EDGE or y < MUTE_BOX_EDGE \
				or x >= MUTE_BOX_PX - MUTE_BOX_EDGE or y >= MUTE_BOX_PX - MUTE_BOX_EDGE
			if on and not on_edge and _near_tick(p):
				img.set_pixel(x, y, GameStyle.INK_TEXT)
			else:
				img.set_pixel(x, y, edge if on_edge else face)
	return ImageTexture.create_from_image(img)

## 折线两笔（短腿 3,9→6,12、长腿 6,12→12,5）周围 1.2px 内算「勾身上」
func _near_tick(p: Vector2) -> bool:
	return _seg_d(p, Vector2(3, 9), Vector2(6, 12)) <= 1.2 \
		or _seg_d(p, Vector2(6, 12), Vector2(12, 5)) <= 1.2

func _seg_d(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)

## 勾选态回读（每次 open 与每次点按后都刷）：已勾时文字提到纸白，
## 让人一眼看出「这条已经生效」，不用去猜方块里那点蓝是什么意思
func _refresh_mute_chk() -> void:
	if not is_instance_valid(_mute_chk):
		return
	var muted := SettingsManager.tutorial_muted()
	_mute_chk.set_pressed_no_signal(muted)
	var col := GameStyle.PAPER if muted else GameStyle.PAPER_DIM
	for c: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color", &"font_focus_color"]:
		_mute_chk.add_theme_color_override(c, col)

func _on_opened() -> void:
	# 每次打开复位：上一次「返回」留下的标记不许影响这一次的关闭语义，页码重置回首页
	left_via_back = false
	_go_page(0)
	_refresh_mute_chk()

## 「〈 返 回」：反悔退出回主菜单。与「跳 过」的区别只在落点与存档——
## 不写 tutorial_muted（玩家没表示「以后别弹」），StartMenu 读 left_via_back 决定重开菜单。
func _on_back_pressed() -> void:
	if not visible:
		return
	left_via_back = true
	close()

## 构建单页：左实机截图 + 右（页题 + 正文顶对齐），正文 wrap_bbcode 硬换行
func _build_page(p: Dictionary) -> Control:
	var page := PanelContainer.new()
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := GameStyle.block(GameStyle.NAVY2, GameStyle.SLANT_PLATE, Vector2(2, 3))
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	page.add_theme_stylebox_override("panel", sb)

	# 两栏：左实机截图 + 右（页题 + 正文，顶部对齐）
	# 整行按内容高（259）收缩并在卡片内垂直居中——行内两者顶对齐、整块上下居中，
	# 消掉卡片底部大空白。
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	page.add_child(row)

	var img_path := String(p.get("image", ""))
	var tex := TextureRect.new()
	if ResourceLoader.exists(img_path):
		tex.texture = load(img_path)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.custom_minimum_size = Vector2(IMG_W, IMG_W * 9.0 / 16.0)
	# 顶部对齐关键：不能 FILL——面板比图片高时矩形被撑高，KEEP_ASPECT_CENTERED 会把
	# 画面垂直居中，图片顶部就比右栏文字低一截；SHRINK_BEGIN 让矩形贴顶、画面即矩形。
	tex.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(tex)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	row.add_child(col)

	var title_lbl := Label.new()
	title_lbl.text = "◆ " + String(p.get("title", ""))
	GameStyle.label(title_lbl, 16, GameStyle.JADE_DK, 0, GameStyle.INK, true)
	col.add_child(title_lbl)

	# 正文走 RichTextLabel：名词与数值由 colorize_terms 自动上语义色（文案表里仍是纯文本）。
	# 换行必须用 wrap_bbcode —— 纯文本的 wrap_cjk 会把 [color] 标签当可见字符切断。
	var body_lbl := RichTextLabel.new()
	body_lbl.bbcode_enabled = true
	body_lbl.fit_content = true
	body_lbl.scroll_active = false
	body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body_lbl.custom_minimum_size = Vector2(COL_TEXT_W, 0)
	body_lbl.add_theme_font_override("normal_font", GameStyle.body_font())
	body_lbl.add_theme_font_override("bold_font", GameStyle.emph_font())
	body_lbl.add_theme_font_size_override("normal_font_size", 13)
	body_lbl.add_theme_font_size_override("bold_font_size", 13)
	body_lbl.add_theme_color_override("default_color", GameStyle.PAPER_DIM)
	# 段间距：正文用 \n 分段，行距留 6px 让两段不糊在一起（单页最多两三段，不会顶高）
	body_lbl.add_theme_constant_override("line_separation", 6)
	body_lbl.text = GameStyle.wrap_bbcode(
		GameStyle.colorize_headings(String(p.get("body", ""))), GameStyle.body_font(), 13, COL_TEXT_W)
	col.add_child(body_lbl)

	return page

func _on_next_pressed() -> void:
	if _cur >= PAGES.size() - 1:
		close()
	else:
		_go_page(_cur + 1)

## 翻页：切显隐、刷指示块、首页禁用上一步、末页下一步换「开始游戏」
func _go_page(i: int) -> void:
	_cur = clampi(i, 0, PAGES.size() - 1)
	for k in range(_page_controls.size()):
		_page_controls[k].visible = (k == _cur)
	for k in range(_page_dots.size()):
		var dot := _page_dots[k]
		var face := GameStyle.GOLD if k == _cur else GameStyle.NAVY2
		dot.add_theme_stylebox_override("panel", GameStyle.block(face, GameStyle.SLANT_PLATE, Vector2(0, 0)))
	_prev_btn.disabled = (_cur == 0)
	_prev_btn.modulate.a = 0.45 if _cur == 0 else 1.0
	if _cur == PAGES.size() - 1:
		_next_btn.text = "开 始 游 戏"
		GameStyle.button(_next_btn, GameStyle.GOLD, GameStyle.GOLD_EDGE, 15, GameStyle.INK_TEXT)
	else:
		_next_btn.text = "下一步 〉"
		GameStyle.button(_next_btn, GameStyle.NAVY2, GameStyle.GOLD, 14, GameStyle.PAPER, 5.0, GameStyle.INK_TEXT)
