class_name DamageNumber
extends Node2D

## 伤害跳字系统：扇形抛物线漂移 + 暴击弹性过冲（TRANS_BACK）+ 静态共享样式缓存（避免 GC 抖动）

static var _normal_settings: LabelSettings
static var _crit_settings: LabelSettings
static var _heal_settings: LabelSettings

static func _ensure_settings() -> void:
	if _normal_settings != null:
		return

	_normal_settings = LabelSettings.new()
	_normal_settings.font = GameStyle.body_font()
	_normal_settings.font_size = 14
	_normal_settings.font_color = GameStyle.PAPER
	_normal_settings.outline_size = 4
	_normal_settings.outline_color = Color(0.02, 0.03, 0.06, 0.92)

	_crit_settings = LabelSettings.new()
	_crit_settings.font = GameStyle.display_font()
	_crit_settings.font_size = 20
	_crit_settings.font_color = GameStyle.YELLOW
	_crit_settings.outline_size = 5
	_crit_settings.outline_color = Color(0.04, 0.02, 0.0, 0.96)

	_heal_settings = LabelSettings.new()
	_heal_settings.font = GameStyle.body_font()
	_heal_settings.font_size = 15
	_heal_settings.font_color = GameStyle.GOOD
	_heal_settings.outline_size = 4
	_heal_settings.outline_color = Color(0.02, 0.03, 0.06, 0.95)

static func spawn(parent: Node, pos: Vector2, amount: int, is_crit: bool = false, custom_text: String = "") -> void:
	if parent == null or not is_instance_valid(parent):
		return

	_ensure_settings()

	var holder := Node2D.new()
	holder.global_position = pos + Vector2(randf_range(-12.0, 12.0), -12.0)
	holder.z_index = 50
	parent.add_child(holder)

	var label := Label.new()
	if custom_text != "":
		label.text = custom_text
		label.label_settings = _heal_settings
	elif is_crit:
		label.text = str(amount) + "!"
		label.label_settings = _crit_settings
	else:
		label.text = str(amount)
		label.label_settings = _normal_settings

	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-35.0, -12.0)
	label.custom_minimum_size = Vector2(70.0, 24.0)
	holder.add_child(label)

	# 初始缩放与弧线偏移
	var drift_x := randf_range(-26.0, 26.0)
	var rise_y := randf_range(32.0, 42.0) if not is_crit else randf_range(40.0, 52.0)

	if is_crit:
		holder.scale = Vector2(0.5, 0.5)
	else:
		holder.scale = Vector2(0.85, 0.85)

	var tw := holder.create_tween()
	tw.set_parallel(true)

	# X 轴抛物线线性侧移，Y 轴先冲后缓
	tw.tween_property(holder, "global_position:x", holder.global_position.x + drift_x, 0.52)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(holder, "global_position:y", holder.global_position.y - rise_y, 0.52)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 尺寸变化：暴击用过冲（TRANS_BACK），普通用平滑弹跳
	if is_crit:
		tw.tween_property(holder, "scale", Vector2(1.35, 1.35), 0.12)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.chain().tween_property(holder, "scale", Vector2(1.0, 1.0), 0.22)
	else:
		tw.tween_property(holder, "scale", Vector2(1.05, 1.05), 0.10)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.chain().tween_property(holder, "scale", Vector2(0.9, 0.9), 0.22)

	# 淡出与自动销毁
	tw.chain().tween_property(holder, "modulate:a", 0.0, 0.16)
	tw.chain().tween_callback(holder.queue_free)
