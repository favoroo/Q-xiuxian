class_name SkillButtonView
extends RefCounted

## 随行神通按钮外观与位置布局辅助
## 从 GameHUD 抽离，负责圆形冷却绘制遮罩、半透明墨蓝/流金样式以及按偏好设置定位。

const SKILL_BTN_SIZE := 76.0

## 圆形冷却绘制遮罩：暗色半透明圆面 + 顺时针环形冷却进度弧
class SkillCdOverlay extends Control:
	var cd_ratio: float = 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		if cd_ratio <= 0.001:
			return
		var center := size * 0.5
		var radius := minf(center.x, center.y)
		draw_circle(center, radius, Color(0.02, 0.04, 0.08, 0.70))
		var sweep := TAU * clampf(1.0 - cd_ratio, 0.0, 1.0)
		draw_arc(center, maxf(2.0, radius - 2.5), -PI * 0.5, -PI * 0.5 + sweep, 36, Color(0.35, 0.75, 1.0, 0.95), 3.0, true)

static func style_circle_button(btn: Button) -> void:
	var r := int(SKILL_BTN_SIZE * 0.5)
	var is_enhanced := false
	if not GameManager.active_skill_id.is_empty():
		is_enhanced = SkillData.is_enhanced_for_cultivator(GameManager.active_skill_id, GameManager.cultivator_id)
	var border_col: Color = Color(GameStyle.JADE, 0.9) if is_enhanced else Color(GameStyle.GOLD, 0.8)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(GameStyle.INK, 0.55)
	normal.border_color = border_col
	normal.border_width_left = 2
	normal.border_width_top = 2
	normal.border_width_right = 2
	normal.border_width_bottom = 2
	normal.corner_radius_top_left = r
	normal.corner_radius_top_right = r
	normal.corner_radius_bottom_right = r
	normal.corner_radius_bottom_left = r

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(GameStyle.NAVY, 0.7)
	hover.border_color = border_col.lightened(0.2)
	hover.border_width_left = 3
	hover.border_width_top = 3
	hover.border_width_right = 3
	hover.border_width_bottom = 3
	hover.corner_radius_top_left = r
	hover.corner_radius_top_right = r
	hover.corner_radius_bottom_right = r
	hover.corner_radius_bottom_left = r

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(GameStyle.GOLD, 0.72)
	pressed.border_color = Color(GameStyle.GOLD_EDGE, 0.95)
	pressed.border_width_left = 3
	pressed.border_width_top = 3
	pressed.border_width_right = 3
	pressed.border_width_bottom = 3
	pressed.corner_radius_top_left = r
	pressed.corner_radius_top_right = r
	pressed.corner_radius_bottom_right = r
	pressed.corner_radius_bottom_left = r

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_font_override("font", GameStyle.display_font())
	btn.add_theme_font_size_override("font_size", 28)
	btn.add_theme_color_override("font_color", GameStyle.PAPER)
	btn.add_theme_color_override("font_hover_color", GameStyle.JADE)
	btn.add_theme_color_override("font_pressed_color", GameStyle.PAPER)
	btn.add_theme_constant_override("outline_size", 4)
	btn.add_theme_color_override("font_outline_color", GameStyle.INK)

static func apply_btn_pos(skill_box: Control) -> void:
	if skill_box == null:
		return
	var pos := StringName(str(SettingsManager.get_val(&"display", &"skill_btn_pos", &"right_bottom")))
	match pos:
		&"right_mid":
			skill_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
			skill_box.offset_left = -SKILL_BTN_SIZE - 56.0
			skill_box.offset_right = -56.0
			skill_box.offset_top = 130.0
			skill_box.offset_bottom = 130.0 + SKILL_BTN_SIZE
		&"left_bottom":
			skill_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
			skill_box.offset_left = 68.0
			skill_box.offset_right = 68.0 + SKILL_BTN_SIZE
			skill_box.offset_top = -SKILL_BTN_SIZE - 72.0
			skill_box.offset_bottom = -72.0
		_:
			skill_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
			skill_box.offset_left = -SKILL_BTN_SIZE - 68.0
			skill_box.offset_right = -68.0
			skill_box.offset_top = -SKILL_BTN_SIZE - 72.0
			skill_box.offset_bottom = -72.0
