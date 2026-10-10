class_name TutorialDialog
extends BaseModalDialog

## 新手指南（首次进入弹窗）：分页图文向导，只讲本作特色机制。
## 触发：StartMenu 点「开始游戏」后、选角前（仅新档未看过），见 StartMenu._on_start_pressed。
## 翻页为线性向导（上一步/下一步），不复用基类 Tab（Tab 是任意跳转模式）；
## _tab_bar 插槽改作页码指示块。任意关闭路径（跳过/ESC/遮罩）都走 close() → closed，
## StartMenu 用 closed 信号串接选角界面，无死路。

const PANEL_SIZE := Vector2(760, 430)
## 正文排版宽度：760 面板 − 外边距 40 − 内容面板内边距 28 − 页内边距 24，再留余量
const TEXT_W := 652.0
const IMG_H := 72.0

## 分页文案：title 页题 / body 正文 / images 插图路径列表（assets/art/ 独立 PNG）
const PAGES: Array[Dictionary] = [
	{
		"title": "欢迎渡劫",
		"body": "道友初入修行界。目标很简单：活过二十波天劫。\n武器会自动索敌攻击，你只管摇杆走位、捡金币和经验；每波结束先悟道加点，再进灵石阁武装自己。",
		"images": ["res://assets/art/icon_coin.png"],
	},
	{
		"title": "装备标签羁绊",
		"body": "每件法器带「器类 + 五行」双标签。凑齐同标签的多件法器会点亮羁绊加成，凑得越多加成越强——阵容越纯越好。\n连续两波没刷到本命标签，下一波天必补。",
		"images": ["res://assets/art/weapon_fire_blade.png", "res://assets/art/weapon_ice_lotus.png"],
	},
	{
		"title": "灵石阁与悟道",
		"body": "商店每波给 5 格货架：看中的可锁定留到下波；不满意可重掷，费用逐次递增，先用免费次数。\n波后悟道一屏给 5 张属性卡，每回合也有 1 次免费刷新。",
		"images": ["res://assets/art/item_jubaopen.png"],
	},
	{
		"title": "三合一升星",
		"body": "集齐 3 把同名同星的法器即可合成升一星：每星伤害翻倍，最高三颗星。前期看到同名法器不妨先买下囤着。\n战斗中升级只攒点数，波次结束后统一加点，打怪途中不打断。",
		"images": ["res://assets/art/weapon_gold_sword.png"],
	},
	{
		"title": "场景交互物",
		"body": "场上共有三座聚灵阵：走入光圈长按「激活」约 1.5 秒，触发全屏冲击重创敌人并散落金币——每座只能用一次，留给 Boss 或绝境。\n宝箱挨 3 下砸开，掉回复或金币。",
		"images": ["res://assets/art/obelisk.png", "res://assets/art/prop_chest.png"],
	},
	{
		"title": "神通",
		"body": "出战前择一件神通随身携带，战斗中点右侧按钮手动释放，带冷却，关键时刻能保命。\n祝道友渡劫顺利——完整机制可随时在暂停菜单的「图鉴」中查阅。",
		"images": ["res://assets/art/skill_aegis.png"],
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

## 构建单页：页题（青玉）+ 插图行（居中）+ 正文（wrap_cjk 硬换行）
func _build_page(p: Dictionary) -> Control:
	var page := PanelContainer.new()
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := GameStyle.block(GameStyle.NAVY2, GameStyle.SLANT_PLATE, Vector2(2, 3))
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	page.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = "✦ " + String(p.get("title", ""))
	GameStyle.label(title_lbl, 16, GameStyle.JADE, 0, GameStyle.INK, true)
	vbox.add_child(title_lbl)

	var imgs: Array = p.get("images", [])
	if not imgs.is_empty():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		for path in imgs:
			var tex := TextureRect.new()
			if ResourceLoader.exists(String(path)):
				tex.texture = load(String(path))
			tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex.custom_minimum_size = Vector2(IMG_H * 1.4, IMG_H)
			row.add_child(tex)
		vbox.add_child(row)

	var body_lbl := Label.new()
	body_lbl.text = GameStyle.wrap_cjk(String(p.get("body", "")), GameStyle.body_font(), 14, TEXT_W)
	GameStyle.label(body_lbl, 14, GameStyle.PAPER_DIM)
	vbox.add_child(body_lbl)

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
