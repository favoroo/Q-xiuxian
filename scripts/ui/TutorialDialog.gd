class_name TutorialDialog
extends BaseModalDialog

## 新手指南（首次进入弹窗 + 设置「新手指南」入口）：分页图文向导，只讲本作特色机制。
## 配图是实机截图（tools/TutorialShot.tscn 产出，assets/art/tutorial/），不是图标——
## 教学意义优先：羁绊页拍属性面板、商店页拍货架锁定/重掷/星标陈列，正文直接指着图讲。
## 触发：StartMenu 点「开始游戏」后、选角前（未勾选「下次不弹出」就每次都弹），见 StartMenu._on_start_pressed；
## 设置页入口见 SettingsDialog._build_body（底部常驻按钮，任何页签可见）。
## 翻页为线性向导（上一步/下一步），不复用基类 Tab；_tab_bar 插槽改作页码指示块。
## 任意关闭路径（跳过/ESC/遮罩）都走 close() → closed，StartMenu 用 closed 信号串接选角。
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
		"body": "左下摇杆走位，武器自动索敌攻击——你只管躲伤害、捡金币和经验。\n右下圆钮是技能，手动释放带冷却，关键时刻保命（图中「闪避」）；部分角色还有一个专属的「额外技能」圆钮，攒上资源就能按（如影者的「影爆」）。打不过就跑，边退边打是活下去的第一要义。",
		"image": "res://assets/art/tutorial/shot_combat.png",
	},
	{
		"title": "装备标签羁绊",
		"body": "每件武器带「器类 + 五行」双标签。点右上「属性」打开面板，看「羁绊与元素共鸣」一栏：同标签凑齐 2 / 4 / 6 件，阶梯式点亮加成（图中火系 2/6 已亮）——阵容越纯越强。",
		"image": "res://assets/art/tutorial/shot_synergy.png",
	},
	{
		"title": "商店与升星",
		"body": "商店刷 5 格货架：看中的点卡上「锁定」留到下回合；不满意点左下「重掷货架」，费用逐次递增。\n背包陈列槽里集齐 3 把同名同星武器可合成升星，每星伤害翻倍——看到同名先买下囤着。",
		"image": "res://assets/art/tutorial/shot_shop.png",
	},
	{
		"title": "悟道加点",
		"body": "战斗中升级不打断，只攒点数，回合结束后统一加。\n一屏给 5 张候选卡：点中一张再按「确认选择」；每回合 1 次免费刷新（图中左下按钮），之后按次扣金币。",
		"image": "res://assets/art/tutorial/shot_alloc.png",
	},
	{
		"title": "场景交互物",
		"body": "场上三座聚灵阵（图中顶部发光的阵）：走入光圈长按「激活祭祀」约 1.5 秒，全屏冲击重创敌人并散落金币——每座只能用一次，留给 Boss 回合或绝境。\n场上的宝箱挨 3 下砸开，掉回复或金币；分木匣、铜匣、玉匣三档，越稀有的档掉得越多，玉匣砸开直接送一件道具。",
		"image": "res://assets/art/tutorial/shot_field.png",
	},
]

var _page_controls: Array[Control] = []
var _page_dots: Array[Panel] = []
var _cur: int = 0
var _prev_btn: Button
var _next_btn: Button
var _mute_chk: CheckBox

func _get_title_text() -> String:
	return "修 仙 指 南"

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
	for c: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color"]:
		_mute_chk.add_theme_color_override(c, col)

func _on_opened() -> void:
	_refresh_mute_chk()

## 构建单页：左实机截图 + 右（页题 + 正文顶对齐），正文 wrap_cjk 硬换行
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

	var body_lbl := Label.new()
	body_lbl.text = GameStyle.wrap_cjk(String(p.get("body", "")), GameStyle.body_font(), 13, COL_TEXT_W)
	GameStyle.label(body_lbl, 13, GameStyle.PAPER_DIM)
	col.add_child(body_lbl)

	return page

func _on_next_pressed() -> void:
	if _cur >= PAGES.size() - 1:
		close()
	else:
		_go_page(_cur + 1)

## 翻页：切显隐、刷指示块、首页禁用上一步、末页下一步换「开始修仙」
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
		_next_btn.text = "开 始 修 仙"
		GameStyle.button(_next_btn, GameStyle.GOLD, GameStyle.GOLD_EDGE, 15, GameStyle.INK_TEXT)
	else:
		_next_btn.text = "下一步 〉"
		GameStyle.button(_next_btn, GameStyle.NAVY2, GameStyle.GOLD, 14, GameStyle.PAPER, 5.0, GameStyle.INK_TEXT)
