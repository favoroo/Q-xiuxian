class_name DetailTip
extends Control

## 通用「点按看详解」浮层：一层薄遮罩 + 一张贴着触发条目的 P5 详情卡。
##
## 为什么不用 tooltip_text：本作目标是 Android，触屏没有 hover，Godot 的 tooltip 在手机上永远不会出现
## ——「这行数字是什么意思」在真机上就成了无处可查的东西。凡是点一下想知道详情的条目都走这里。
##
## 三条口径：
## 1. 同一时刻只允许一张卡：show_over() 先收起宿主上的旧卡，连点不会叠出一摞压死原面板；
## 2. 卡是自建节点，收起即 destroy，不留「隐藏后复活」的路径（复活路径 = 遮罩变隐形挡板的经典坑）；
## 3. 摆位只认「点那一刻」抓下的条目矩形，不持有条目引用 —— 面板 refresh 会整批重建行，
##    留着引用就是等谁 queue_free 之后崩在 get_global_rect() 上。
##
## payload：
##   title      String      标题（走大标题字体，压在蓝色色带里）
##   chip       String      角签文案，如稀有度 / 器类·五行；空串则不画
##   chip_color Color       角签底色（字色按亮度自动取墨黑或纸白）
##   rows       Array       读数行，每项 [名字, 值] 或 [名字, 值, Color]
##   body       String      BBCode 正文（悟道卡沿用 UpgradeData 的 desc，不再抄一份）
##   notes      Array[String] 规则条目，逐行前缀圆点
##   foot       String      脚注小字
##   actions    Array       底部操作按钮，支持单行 [act1, act2] 或多行 [[act1], [act2, act3]]
##                          每个 act: {"text": String, "callback": Callable, "color": Color, ...}

const GAP := 12.0
const CARD_W := 306.0
const MARGIN := 10.0
## 卡内可用宽 = 卡宽 − 左右边距(12×2) − 描边(2×2)。
## 凡是折行的控件都必须把它钉成 custom_minimum_size.x：折行 Label 的「最小宽」只有一个词，
## 于是容器按那个宽度算「最小高」⇒ 一个词一行、卡高直接冲到两千多像素（判据 ③ 量出来过）。
const INNER_W := 276.0

## 收起那一刻发一次：让触发方把自己那一行的高亮撤掉（卡与它指的那行是同一条信息，得一起亮一起灭）
signal closed

var _card: PanelContainer
var _src := Rect2()
var _closing := false
var _shown := false

## 判据读数：这张卡当初拿到的载荷与它的实际矩形。
## 遮罩是全屏幕的，量它没意义 —— 要量的是卡有没有出屏、标题对不对、行有没有摆进去。
var payload: Dictionary = {}

func card_rect() -> Rect2:
	if _card == null or not is_instance_valid(_card):
		return Rect2()
	return _card.get_global_rect()

## 在 host 上、贴着 anchor 开一张详情卡。
static func show_over(host: Control, anchor: Control, data: Dictionary) -> DetailTip:
	if host == null or not is_instance_valid(host) or anchor == null or not is_instance_valid(anchor):
		return null
	close_all(host)
	var tip := DetailTip.new()
	tip.name = "DetailTip"
	host.add_child(tip)
	tip._open(anchor.get_global_rect(), data)
	return tip

## 收起宿主上所有还活着的详情卡；返回「确实收掉了一张」，供「返回键先退一层」判断用。
static func close_all(host: Control) -> bool:
	if host == null:
		return false
	var any := false
	for c in host.get_children():
		if c is DetailTip and not (c as DetailTip)._closing:
			(c as DetailTip).close()
			any = true
	return any

## 宿主上当前那张还活着的卡（正在淡出的旧卡不算 —— 收起要等 0.1 秒 tween，
## 期间它还在子节点列表里，判据若拿它会读到上一张卡的内容）
static func live(host: Control) -> DetailTip:
	if host == null:
		return null
	for c in host.get_children():
		if c is DetailTip and not (c as DetailTip)._closing:
			return c as DetailTip
	return null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _open(src_global: Rect2, data: Dictionary) -> void:
	payload = data
	_src = Rect2(src_global.position - global_position, src_global.size)
	pivot_offset = Vector2.ZERO
	modulate.a = 0.0

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.09, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)

	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(CARD_W, 0)
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	# 卡体不是按钮（PanelContainer），摇杆认不出 ⇒ 自己登记：详解卡开着时点在卡上不该
	# 顺手在卡底下长出摇杆把人挪走。上面那块整屏暗底 dim 反过来**不许**登记 —— 把它算进去
	# 就是一整块全屏禁区，读详解期间完全不能走位。
	_card.add_to_group(DawnJoystick.UI_PRESS_HOLD_GROUP)
	var sb := GameStyle.outlined_panel(
		Color(GameStyle.NAVY.r, GameStyle.NAVY.g, GameStyle.NAVY.b, 0.99),
		GameStyle.GOLD, 2, GameStyle.SLANT_PLATE)
	sb.shadow_color = Color(0, 0, 0, 0.65)
	sb.shadow_size = 0
	sb.shadow_offset = Vector2(6, 6)
	_card.add_theme_stylebox_override("panel", sb)
	add_child(_card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vbox)

	_build_header(vbox, payload)
	_build_chip(vbox, payload)
	_build_rows(vbox, payload)
	_build_body(vbox, payload)
	_build_notes(vbox, payload)
	_build_foot(vbox, payload)
	_build_actions(vbox, payload)

	# 卡高要等 RichTextLabel 的 fit_content 定下来才知道，所以尺寸一变就重新摆一次
	# （Control 上这个信号叫 resized，size_changed 是 Node2D 的）
	_card.resized.connect(_place)
	_place()
	call_deferred("_place")

func _build_header(vbox: VBoxContainer, payload: Dictionary) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(head)

	var band := PanelContainer.new()
	band.add_theme_stylebox_override("panel", GameStyle.block(GameStyle.GOLD, GameStyle.SLANT_BAND, Vector2(2, 3)))
	var band_margin := MarginContainer.new()
	band_margin.add_theme_constant_override("margin_left", 8)
	band_margin.add_theme_constant_override("margin_right", 8)
	band_margin.add_theme_constant_override("margin_top", 1)
	band_margin.add_theme_constant_override("margin_bottom", 1)
	var title := Label.new()
	title.text = String(payload.get("title", ""))
	GameStyle.label(title, 15, GameStyle.PAPER, 2, GameStyle.INK, true)
	band_margin.add_child(title)
	band.add_child(band_margin)
	head.add_child(band)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(sp)

	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.custom_minimum_size = Vector2(28, 26)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	GameStyle.button(close_btn, GameStyle.NAVY2, GameStyle.BAD, 15, GameStyle.PAPER, 5.0)
	close_btn.pressed.connect(close)
	head.add_child(close_btn)

func _build_chip(vbox: VBoxContainer, payload: Dictionary) -> void:
	var chip := String(payload.get("chip", ""))
	if chip.is_empty():
		return
	var col: Color = payload.get("chip_color", GameStyle.GOLD_DK)
	var lbl := Label.new()
	lbl.text = " " + chip + " "
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameStyle.label(lbl, 11, GameStyle.INK_TEXT if col.get_luminance() > 0.5 else GameStyle.PAPER)
	lbl.add_theme_stylebox_override("normal", GameStyle.chip(col))
	vbox.add_child(lbl)

func _build_rows(vbox: VBoxContainer, payload: Dictionary) -> void:
	var rows: Array = payload.get("rows", [])
	if rows.is_empty():
		return
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 3)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(grid)

	for r in rows:
		var cells: Array = r
		if cells.size() < 2:
			continue
		var k := Label.new()
		k.text = String(cells[0])
		k.mouse_filter = Control.MOUSE_FILTER_IGNORE
		k.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		GameStyle.label(k, 12, GameStyle.GREY)
		grid.add_child(k)

		var v := Label.new()
		v.text = String(cells[1])
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var vcol: Color = cells[2] if cells.size() > 2 else GameStyle.PAPER
		GameStyle.label(v, 12, vcol)
		grid.add_child(v)

func _build_body(vbox: VBoxContainer, payload: Dictionary) -> void:
	var body := String(payload.get("body", ""))
	if body.is_empty():
		return
	var sep := _sep()
	if sep != null:
		vbox.add_child(sep)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rt.custom_minimum_size = Vector2(INNER_W, 0)
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rt.add_theme_font_override("normal_font", GameStyle.body_font())
	rt.add_theme_font_override("bold_font", GameStyle.body_font())
	rt.add_theme_font_size_override("normal_font_size", 13)
	rt.add_theme_font_size_override("bold_font_size", 13)
	rt.add_theme_color_override("default_color", GameStyle.PAPER_DIM)
	rt.text = body
	vbox.add_child(rt)

func _build_notes(vbox: VBoxContainer, payload: Dictionary) -> void:
	var notes: Array = payload.get("notes", [])
	if notes.is_empty():
		return
	var sep := _sep()
	if sep != null:
		vbox.add_child(sep)
	for n in notes:
		var lbl := Label.new()
		lbl.text = "· " + String(n)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.custom_minimum_size = Vector2(INNER_W, 0)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		GameStyle.label(lbl, 12, GameStyle.GREY)
		vbox.add_child(lbl)

func _build_foot(vbox: VBoxContainer, payload: Dictionary) -> void:
	var foot := String(payload.get("foot", ""))
	if foot.is_empty():
		return
	var lbl := Label.new()
	lbl.text = foot
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(INNER_W, 0)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	GameStyle.label(lbl, 11, GameStyle.GOLD_EDGE)
	vbox.add_child(lbl)

func _build_actions(vbox: VBoxContainer, payload: Dictionary) -> void:
	var raw_actions: Variant = payload.get("actions", [])
	if not (raw_actions is Array) or (raw_actions as Array).is_empty():
		return
	var arr: Array = raw_actions as Array
	var rows: Array = []
	if arr[0] is Dictionary:
		rows.append(arr)
	elif arr[0] is Array:
		rows.append_array(arr)
	else:
		return

	var sep := _sep()
	if sep != null:
		vbox.add_child(sep)

	var acts_box := VBoxContainer.new()
	acts_box.name = "ActionsContainer"
	acts_box.add_theme_constant_override("separation", 6)
	acts_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(acts_box)

	for row in rows:
		if not (row is Array) or (row as Array).is_empty():
			continue
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		acts_box.add_child(hbox)

		for act_item in (row as Array):
			if not (act_item is Dictionary):
				continue
			var act: Dictionary = act_item
			var btn := Button.new()
			btn.text = String(act.get("text", ""))
			btn.disabled = bool(act.get("disabled", false))
			btn.focus_mode = Control.FOCUS_NONE
			btn.mouse_filter = Control.MOUSE_FILTER_STOP
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.custom_minimum_size = Vector2(0, 32)
			var bg_col: Color = act.get("color", GameStyle.NAVY2)
			var edge_col: Color = act.get("edge_color", GameStyle.LINE)
			var text_col: Color = act.get("text_color", GameStyle.PAPER)
			if btn.disabled:
				bg_col = GameStyle.NAVY2.darkened(0.2)
				edge_col = GameStyle.LINE.darkened(0.2)
				text_col = GameStyle.GREY
			GameStyle.button(btn, bg_col, edge_col, 13, text_col, 4.0)
			if btn.disabled:
				btn.add_theme_stylebox_override("disabled", GameStyle.block(bg_col, 4.0, Vector2(1, 1)))
				btn.add_theme_color_override("font_disabled_color", text_col)
			var cb: Callable = act.get("callback", Callable())
			if cb.is_valid():
				var keep_open: bool = bool(act.get("keep_open", false))
				btn.pressed.connect(func() -> void:
					if not keep_open:
						close()
					cb.call()
				)
			hbox.add_child(btn)

func _sep() -> Control:
	var s := HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = GameStyle.LINE
	line.thickness = 1
	s.add_theme_stylebox_override("separator", line)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s

func _on_dim_input(event: InputEvent) -> void:
	# 只认鼠标左键：触屏上 Godot 会同时给出 ScreenTouch 与合成的鼠标事件，
	# 两个都处理就是一次点击走两遍（与 LevelUpDialog / 本面板遮罩同一口径）
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		close()

## 摆位：优先贴在条目右侧、顶边对齐；右侧放不下就翻到左侧；再不行压回可视区内。
## 纵向同理（先下后上），最后上下都塞不下时贴可视区顶，保证标题一定看得见。
## 第一次量出尺寸才淡入 —— 浮层刚 add_child 时 size 还是 0，直接放会在左上角闪一下。
func _place() -> void:
	if _card == null or not is_instance_valid(_card):
		return
	var cs := _card.size
	if cs.x <= 0.0 or cs.y <= 0.0:
		cs = _card.get_combined_minimum_size()
	var area := size
	if area.x <= 0.0 or area.y <= 0.0:
		area = get_viewport_rect().size
	if area.x <= 0.0 or area.y <= 0.0:
		return

	var x := _src.end.x + GAP
	if x + cs.x > area.x - MARGIN:
		x = _src.position.x - cs.x - GAP
	if x < MARGIN:
		x = clampf(_src.position.x, MARGIN, maxf(MARGIN, area.x - cs.x - MARGIN))

	var y := _src.end.y + GAP
	if y + cs.y > area.y - MARGIN:
		y = _src.position.y - cs.y - GAP
	if y < MARGIN:
		y = clampf(area.y - cs.y - MARGIN, MARGIN, maxf(MARGIN, area.y - cs.y - MARGIN))

	_card.position = Vector2(x, y)
	if _shown:
		return
	_shown = true
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.12)

func close() -> void:
	if _closing or not is_instance_valid(self):
		return
	_closing = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameStyle._ignore_input(self)
	closed.emit()
	if _card != null and is_instance_valid(_card):
		_card.resized.disconnect(_place)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.1)
	tw.tween_callback(queue_free)
