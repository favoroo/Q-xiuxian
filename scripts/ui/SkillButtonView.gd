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
		draw_circle(center, radius, GameStyle.dim_overlay(0.70))
		var sweep := TAU * clampf(1.0 - cd_ratio, 0.0, 1.0)
		draw_arc(center, maxf(2.0, radius - 2.5), -PI * 0.5, -PI * 0.5 + sweep, 36, GameStyle.with_alpha(GameStyle.COOLDOWN_ARC, 0.95), 3.0, true)

## 键面环形进度：正上方起针、顺时针填满的一圈弧 + 弧头亮点。
## 给「按住才生效」的动作键（祭坛充能）当键面读数 —— 横条在圆键里会探出圆面，
## 而且拇指正压着键，条画在键底等于没画。
## 轨道不画：平时键面就该是干净的，只有真在充的那一圈才是信息。
class CircleProgressOverlay extends Control:
	var ratio: float = 0.0
	var width: float = 5.0
	var points: int = 72
	## 颜色一律由外层灌进来（GameStyle 是唯一取色入口，这里只留空默认）
	var progress_color: Color = Color.WHITE
	var head_color: Color = Color.WHITE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func set_ratio(v: float) -> void:
		ratio = clampf(v, 0.0, 1.0)
		queue_redraw()

	## 走针半径：贴着圆键内缘收一档（2px 描边 + 半根线宽），绘制与判据读同一个函数，
	## 否则「圈有没有超出键面」这件事会出现两套说法
	func arc_radius() -> float:
		return minf(size.x, size.y) * 0.5 - 2.0 - width * 0.5

	func _draw() -> void:
		if ratio <= 0.0:
			return
		var center := size * 0.5
		var radius := maxf(2.0, arc_radius())
		var start := -PI * 0.5
		var end := start + TAU * ratio
		draw_arc(center, radius, start, end, points, progress_color, width, true)
		draw_circle(center + Vector2.RIGHT.rotated(end) * radius, width * 0.82, head_color)

static func style_circle_button(btn: Button) -> void:
	var r := int(SKILL_BTN_SIZE * 0.5)
	var is_enhanced := false
	if not GameManager.active_skill_id.is_empty():
		is_enhanced = SkillData.is_enhanced_for_cultivator(GameManager.active_skill_id, GameManager.cultivator_id)
	var border_col: Color = GameStyle.with_alpha(GameStyle.JADE, 0.9) if is_enhanced else GameStyle.with_alpha(GameStyle.GOLD, 0.8)

	var normal := StyleBoxFlat.new()
	normal.bg_color = GameStyle.with_alpha(GameStyle.INK, 0.55)
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
	hover.bg_color = GameStyle.with_alpha(GameStyle.NAVY, 0.7)
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
	pressed.bg_color = GameStyle.with_alpha(GameStyle.GOLD, 0.72)
	pressed.border_color = GameStyle.with_alpha(GameStyle.GOLD_EDGE, 0.95)
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
	btn.add_theme_color_override("font_color", GameStyle.CHALK)
	btn.add_theme_color_override("font_hover_color", GameStyle.JADE)
	btn.add_theme_color_override("font_pressed_color", GameStyle.PAPER)
	btn.add_theme_constant_override("outline_size", 4)
	btn.add_theme_color_override("font_outline_color", GameStyle.INK)

## 圆形动作键通用样式：技能键之外的那几颗浮动键（祭坛激活键）照这一套画。
## 直径同样钉死在 SKILL_BTN_SIZE 上 —— 两颗键并排在屏幕上必须是同一个圆，
## 要改大小只改那一处，不许每颗键自己报一个尺寸。
## filled = 按住生效态：整面翻成 accent 实底、字改黑，状态不靠第三根颜色条去说。
static func style_circle_action(btn: Button, accent: Color, font_size: int,
		filled: bool = false) -> void:
	btn.add_theme_stylebox_override("normal", _circle_box(
			GameStyle.with_alpha(accent, 0.72) if filled else GameStyle.with_alpha(GameStyle.INK, 0.55),
			accent.lightened(0.25) if filled else accent,
			3 if filled else 2))
	btn.add_theme_stylebox_override("hover", _circle_box(GameStyle.with_alpha(GameStyle.NAVY, 0.7), accent.lightened(0.2), 3))
	btn.add_theme_stylebox_override("pressed", _circle_box(GameStyle.with_alpha(accent, 0.72), accent.lightened(0.4), 3))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_font_override("font", GameStyle.display_font())
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", GameStyle.INK_TEXT if filled else GameStyle.CHALK)
	btn.add_theme_color_override("font_hover_color", GameStyle.CHALK)
	btn.add_theme_color_override("font_pressed_color", GameStyle.INK_TEXT)
	btn.add_theme_constant_override("outline_size", 4)
	btn.add_theme_color_override("font_outline_color", GameStyle.INK)

static func _circle_box(bg: Color, border: Color, w: int) -> StyleBoxFlat:
	var r := int(SKILL_BTN_SIZE * 0.5)
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left = w
	s.border_width_top = w
	s.border_width_right = w
	s.border_width_bottom = w
	s.corner_radius_top_left = r
	s.corner_radius_top_right = r
	s.corner_radius_bottom_right = r
	s.corner_radius_bottom_left = r
	return s
