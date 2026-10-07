class_name DamageNumber
extends Node2D

static func spawn(parent: Node, pos: Vector2, amount: int, is_crit: bool = false, custom_text: String = "") -> void:
    var holder = Node2D.new()
    holder.global_position = pos + Vector2(randf_range(-10.0, 10.0), -16.0)
    holder.z_index = 50
    parent.add_child(holder)
    
    var label = Label.new()
    label.text = custom_text if custom_text != "" else str(amount)
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    
    var settings = LabelSettings.new()
    if custom_text != "":
        settings.font_size = 15
        settings.font_color = Color(0.55, 1.0, 0.65)
        settings.outline_size = 4
        settings.outline_color = Color(0.03, 0.03, 0.04, 0.95)
    elif is_crit:
        settings.font_size = 19
        settings.font_color = Color(1.0, 0.83, 0.0)
        settings.outline_size = 5
        settings.outline_color = Color(0.03, 0.03, 0.04, 0.95)
    else:
        settings.font_size = 14
        settings.font_color = Color(0.96, 0.95, 0.92)
        settings.outline_size = 4
        settings.outline_color = Color(0.03, 0.03, 0.04, 0.92)
    
    label.label_settings = settings
    label.position = Vector2(-30.0, -12.0)
    label.custom_minimum_size = Vector2(60.0, 24.0)
    holder.add_child(label)
    
    var tw = holder.create_tween()
    tw.set_parallel(true)
    tw.tween_property(holder, "global_position:y", holder.global_position.y - 28.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    tw.tween_property(holder, "scale", Vector2(1.28, 1.28) if is_crit else Vector2(1.06, 1.06), 0.12)
    tw.chain().tween_property(holder, "modulate:a", 0.0, 0.22)
    tw.chain().tween_callback(holder.queue_free)
