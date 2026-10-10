class_name TutorialDialog
extends BaseModalDialog

## 新手指南（首次进入弹窗 + 设置「新手指南」入口）：分页图文向导，只讲本作特色机制。
## 配图是实机截图（tools/TutorialShot.tscn 产出，assets/art/tutorial/），不是图标——
## 教学意义优先：羁绊页拍属性面板、商店页拍货架锁定/重掷/星标陈列，正文直接指着图讲。
## 触发：StartMenu 点「开始游戏」后、选角前（未看过就弹），见 StartMenu._on_start_pressed；
## 设置页入口见 SettingsDialog._build_body（底部常驻按钮，任何页签可见）。
## 翻页为线性向导（上一步/下一步），不复用基类 Tab；_tab_bar 插槽改作页码指示块。
## 任意关闭路径（跳过/ESC/遮罩）都走 close() → closed，StartMenu 用 closed 信号串接选角。

const PANEL_SIZE := Vector2(880, 540)
## 两栏页：左图宽（16:9 → 高 259）与右栏正文换行宽度（788 内宽 − 图 460 − 栏距 14 − 余量）
const IMG_W := 460.0
const COL_TEXT_W := 300.0

## 分页文案：title 页题 / body 正文 / image 实机截图路径（全部带图，左图右文两栏）
const PAGES: Array[Dictionary] = [
	{
		"title": "战斗与神通",
		"body": "左下摇杆走位，法器自动索敌攻击——你只管躲伤害、捡金币和经验。\n右下圆钮是神通，手动释放带冷却，关键时刻保命（图中「冲刺」）。打不过就跑，边退边打是活下去的第一要义。",
		"image": "res://assets/art/tutorial/shot_combat.png",
	},
	{
		"title": "装备标签羁绊",
		"body": "每件法器带「器类 + 五行」双标签。点右上「属性」打开面板，看「羁绊与元素共鸣」一栏：同标签凑齐 2 / 4 / 6 件，阶梯式点亮加成（图中火系 2/6 已亮）——阵容越纯越强。",
		"image": "res://assets/art/tutorial/shot_synergy.png",
	},
	{
		"title": "灵石阁与升星",
		"body": "波间商店刷 5 格货架：看中的点卡上「锁定」留到下波；不满意点左下「重掷货架」，费用逐次递增。\n背包陈列槽里集齐 3 把同名同星法器可合成升星，每星伤害翻倍——看到同名先买下囤着。",
		"image": "res://assets/art/tutorial/shot_shop.png",
	},
	{
		"title": "悟道加点",
		"body": "战斗中升级不打断，只攒点数，波次结束后统一加。\n一屏给 5 张候选卡：点中一张再按「确认选择」；每回合 1 次免费刷新（图中左下按钮），之后按次扣金币。",
		"image": "res://assets/art/tutorial/shot_alloc.png",
	},
	{
		"title": "场景交互物",
		"body": "场上三座聚灵阵（图中顶部发光的阵）：走入光圈长按「激活」约 1.5 秒，全屏冲击重创敌人并散落金币——每座只能用一次，留给 Boss 波或绝境。\n场上的宝箱挨 3 下砸开，掉回复或金币。",
		"image": "res://assets/art/tutorial/shot_field.png",
	},
]

var _page_controls: Array[Control] = []
var _page_dots: Array[Panel] = []
var _cur: int = 0
var _prev_btn: Button
var _next_btn: Button

func _get_title_text() -> String:
	return "修 仙 指 南"

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
	var cont_sb := GameStyle.outlined_panel(GameStyle.INK, GameStyle.LINE, 2, 0.0)
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
	GameStyle.button(_prev_btn, GameStyle.NAVY2, GameStyle.GOLD, 14, GameStyle.PAPER)
	nav.add_child(_prev_btn)

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
	title_lbl.text = "✦ " + String(p.get("title", ""))
	GameStyle.label(title_lbl, 16, GameStyle.JADE, 0, GameStyle.INK, true)
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
		GameStyle.button(_next_btn, GameStyle.NAVY2, GameStyle.GOLD, 14, GameStyle.PAPER)
