class_name BaseModalDialog
extends Control

## 全屏暂停式模态弹窗通用基类
## 统一沉淀：
## 1. 半透明暗色遮罩（点击空白关闭）
## 2. 居中斜切大面板 + 长按防摇杆群组注册 + 统一边框阴影
## 3. 顶部标题色块 + Tab 栏 / 元信息插槽 + 关闭按钮
## 4. open/close 淡入淡出动画与防重入、ESC/ui_cancel 拦截（先退 DetailTip 再关弹窗）
## 5. 通用 Tab 页签切换逻辑（统一按 GameStyle 样式切高亮）

signal closed

var _closing: bool = false

# 核心骨架节点
var _dim_rect: ColorRect
var _center: CenterContainer
var _panel: PanelContainer
var _margin: MarginContainer
var _root_vbox: VBoxContainer
var _top_bar: HBoxContainer
var _title_box: PanelContainer
var _title_label: Label
var _close_btn: Button

# 可选 Tab 栏支持
var _tab_bar: HBoxContainer
var _tab_buttons: Array[Button] = []
var _pages: Array[Control] = []
var _current_tab: int = 0

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_modal_chrome()
	_build_body(_root_vbox)

## 子类覆写：弹窗标题文案
func _get_title_text() -> String:
	return "弹 窗"

## 子类覆写：关闭按钮文案
func _get_close_btn_text() -> String:
	return "返 回"

## 子类覆写：面板尺寸
func _get_panel_size() -> Vector2:
	return Vector2(880, 470)

## 子类覆写：面板内边距 (left, top, right, bottom)
func _get_panel_margins() -> Vector4:
	return Vector4(20, 14, 20, 14)

## 子类覆写：面板根 VBox 行距
func _get_vbox_separation() -> int:
	return 10

## 子类覆写：顶部标题栏间距
func _get_top_bar_separation() -> int:
	return 10

## 子类覆写：Tab 栏间距
func _get_tab_bar_separation() -> int:
	return 8

## 子类覆写：标题字号
func _get_title_font_size() -> int:
	return 18

## 子类覆写：关闭按钮尺寸
func _get_close_btn_min_size() -> Vector2:
	return Vector2(84, 34)

## 子类必须覆写：构建面板主体内容（挂在 _root_vbox 下）
func _build_body(_root: VBoxContainer) -> void:
	pass

## 子类可选覆写：Tab 切换后的额外处理
func _on_tab_switched(_index: int) -> void:
	pass

## 构建通用骨架
func _build_modal_chrome() -> void:
	# 1. 半透明暗色遮罩（点击空白处关闭）
	_dim_rect = ColorRect.new()
	_dim_rect.color = Color(0.02, 0.04, 0.09, 0.85)
	_dim_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim_rect.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			close()
	)
	add_child(_dim_rect)

	# 2. 居中容器
	_center = CenterContainer.new()
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center)

	# 3. 斜切大面板
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = _get_panel_size()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_to_group(DawnJoystick.UI_PRESS_HOLD_GROUP)
	var panel_style := GameStyle.panel(GameStyle.NAVY, GameStyle.SLANT_PLATE, Vector2(8, 9))
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 6
	panel_style.border_color = GameStyle.BLUE
	_panel.add_theme_stylebox_override("panel", panel_style)
	_center.add_child(_panel)

	# 4. 内边距
	_margin = MarginContainer.new()
	var m := _get_panel_margins()
	_margin.add_theme_constant_override("margin_left", int(m.x))
	_margin.add_theme_constant_override("margin_top", int(m.y))
	_margin.add_theme_constant_override("margin_right", int(m.z))
	_margin.add_theme_constant_override("margin_bottom", int(m.w))
	_panel.add_child(_margin)

	_root_vbox = VBoxContainer.new()
	_root_vbox.add_theme_constant_override("separation", _get_vbox_separation())
	_margin.add_child(_root_vbox)

	# 5. 顶部标题栏
	_top_bar = HBoxContainer.new()
	_top_bar.add_theme_constant_override("separation", _get_top_bar_separation())
	_root_vbox.add_child(_top_bar)

	_title_box = PanelContainer.new()
	_title_box.add_theme_stylebox_override("panel", GameStyle.block(GameStyle.BLUE, GameStyle.SLANT_BAND, Vector2(3, 4)))
	var title_margin := MarginContainer.new()
	title_margin.add_theme_constant_override("margin_left", 14)
	title_margin.add_theme_constant_override("margin_right", 14)
	title_margin.add_theme_constant_override("margin_top", 4)
	title_margin.add_theme_constant_override("margin_bottom", 4)
	_title_label = Label.new()
	_title_label.text = _get_title_text()
	GameStyle.label(_title_label, _get_title_font_size(), GameStyle.PAPER, 0, GameStyle.INK, true)
	title_margin.add_child(_title_label)
	_title_box.add_child(title_margin)
	_top_bar.add_child(_title_box)

	# 留出 Tab / 扩展插槽（由子类按需在 _top_bar 里加）
	_tab_bar = HBoxContainer.new()
	_tab_bar.add_theme_constant_override("separation", _get_tab_bar_separation())
	_tab_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top_bar.add_child(_tab_bar)

	_close_btn = Button.new()
	_close_btn.text = _get_close_btn_text()
	_close_btn.custom_minimum_size = _get_close_btn_min_size()
	_close_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(_close_btn, GameStyle.NAVY2, GameStyle.BLUE, 14, GameStyle.PAPER, 5.0)
	_close_btn.pressed.connect(close)
	_top_bar.add_child(_close_btn)

## 添加一个通用 Tab 页签按钮
func add_tab_button(index: int, text: String, min_w: float = 100.0) -> Button:
	return _add_tab_button(_tab_bar, index, text, min_w)

func _add_tab_button(parent: HBoxContainer, index: int, text: String, min_w: float = 100.0) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(min_w, 32)
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(func(): _switch_tab(index))
	parent.add_child(btn)
	_tab_buttons.append(btn)
	return btn

## 切换 Tab（联动按钮样式与 _pages 显示）
func switch_tab(index: int) -> void:
	_switch_tab(index)

func _switch_tab(index: int) -> void:
	_current_tab = index
	for i in range(_pages.size()):
		if is_instance_valid(_pages[i]):
			_pages[i].visible = (i == index)
	for i in range(_tab_buttons.size()):
		var b := _tab_buttons[i]
		if not is_instance_valid(b):
			continue
		if i == index:
			GameStyle.button(b, GameStyle.BLUE, GameStyle.BLUE_EDGE, 13, GameStyle.PAPER, 5.0)
		else:
			GameStyle.button(b, GameStyle.NAVY2, GameStyle.BLUE, 13, GameStyle.PAPER_DIM, 5.0)
	_on_tab_switched(index)

## 子类可选覆写：open 时的刷新逻辑
func _on_opened() -> void:
	pass

## 子类可选覆写：close 时的清理逻辑
func _on_closed() -> void:
	pass

## 打开弹窗（带淡入动画）
func open() -> void:
	if visible:
		return
	visible = true
	_closing = false
	_on_opened()
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.2)

## 关闭弹窗（带淡出动画与防重入）
func close() -> void:
	if _closing or not visible:
		return
	DetailTip.close_all(self)
	_closing = true
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.16)
	tw.tween_callback(func():
		visible = false
		_closing = false
		_on_closed()
		closed.emit()
	)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		if DetailTip.close_all(self):
			get_viewport().set_input_as_handled()
			return
		close()
		get_viewport().set_input_as_handled()
