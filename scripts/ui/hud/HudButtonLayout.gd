class_name HudButtonLayout
extends RefCounted

## 浮动圆键（技能键 / 祭坛键）自由摆位算术：归一化中心点 + 缩放 → 实际摆位。
## 从 GameHUD 抽出，技能键与祭坛键共用同一条算术。
## 布局矩形按未缩放底尺寸居中，视觉缩放围绕 pivot（矩形中心）放大
## ⇒ 视觉中心永远钉在存档点上，换屏比不漂移。

static func apply(box: Control, norm: Vector2, scale_f: float, base: Vector2) -> void:
	if box == null:
		return
	var vp := box.get_viewport_rect().size
	var s := clampf(scale_f, SettingsManager.BTN_SCALE_MIN, SettingsManager.BTN_SCALE_MAX)
	# 中心点夹回屏内（半尺寸 + 2px 余量），怎么拖都不会整个出屏找不回来
	var half := base * s * 0.5 + Vector2(2.0, 2.0)
	half.x = minf(half.x, vp.x * 0.5)
	half.y = minf(half.y, vp.y * 0.5)
	var c := Vector2(clampf(norm.x, 0.0, 1.0) * vp.x, clampf(norm.y, 0.0, 1.0) * vp.y)
	c.x = clampf(c.x, half.x, vp.x - half.x)
	c.y = clampf(c.y, half.y, vp.y - half.y)
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	box.offset_left = c.x - base.x * 0.5
	box.offset_top = c.y - base.y * 0.5
	box.offset_right = c.x + base.x * 0.5
	box.offset_bottom = c.y + base.y * 0.5
	box.pivot_offset = base * 0.5
	box.scale = Vector2(s, s)
